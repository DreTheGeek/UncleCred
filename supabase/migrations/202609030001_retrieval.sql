-- Retrieval layer. The knowledge base has been fully embedded since 2026-09-03 (7,424 of
-- 7,424 chunks, gte-small, 384 dims) but nothing could query it: there was no match
-- function anywhere in the schema. This is the piece every grounded claim depends on.
--
-- Hybrid by design. Vector alone misses exact terms that matter in credit ("609", "FCRA",
-- "30 day", a specific card name); full text alone misses paraphrase, which is most of how
-- a viewer asks a question. Both indexes already exist:
--   document_chunks_embedding_hnsw_idx  hnsw on embedding
--   document_chunks_fts_idx             gin on to_tsvector('english', content)
-- The FTS expression below is written to match that index definition exactly so it is used.
--
-- Ranking is Reciprocal Rank Fusion, which needs no score normalisation between two
-- incomparable scales, then weighted by source authority. Superseded documents are excluded:
-- knowledge.documents.supersedes_document_id points at what a document replaces, so anything
-- pointed at is stale and must never ground a claim.
--
-- SECURITY INVOKER on purpose. RLS on knowledge.document_chunks stays the authorization
-- boundary; a caller can only retrieve what its own policies already allow.

create or replace function knowledge.match_chunks(
  p_organization_id uuid,
  p_query_embedding extensions.vector(384),
  p_query_text      text default null,
  p_match_count     int default 8,
  p_min_similarity  double precision default 0.0,
  p_topics          text[] default null,
  p_authorities     text[] default null
)
returns table (
  chunk_id        uuid,
  document_id     uuid,
  document_title  text,
  topic           text,
  authority       text,
  heading_path    text,
  content         text,
  similarity      double precision,
  text_rank       double precision,
  score           double precision
)
language sql
stable
set search_path = ''
as $$
  with live_docs as (
    -- Anything another document supersedes is stale and cannot ground a claim.
    select d.id, d.title, d.authority
    from knowledge.documents d
    where d.organization_id = p_organization_id
      and not exists (
        select 1 from knowledge.documents s
        where s.supersedes_document_id = d.id
      )
      and (p_authorities is null or d.authority::text = any(p_authorities))
  ),
  candidates as (
    select c.id, c.document_id, c.heading_path, c.content,
           c.metadata->>'topic' as topic,
           c.embedding
    from knowledge.document_chunks c
    join live_docs ld on ld.id = c.document_id
    where c.embedding is not null
      and (p_topics is null or c.metadata->>'topic' = any(p_topics))
  ),
  vector_hits as (
    select id,
           1 - (embedding operator(extensions.<=>) p_query_embedding) as similarity,
           row_number() over (
             order by embedding operator(extensions.<=>) p_query_embedding
           ) as rnk
    from candidates
    order by embedding operator(extensions.<=>) p_query_embedding
    limit greatest(p_match_count * 8, 40)
  ),
  text_hits as (
    select id,
           ts_rank_cd(to_tsvector('english', content), websearch_to_tsquery('english', p_query_text)) as text_rank,
           row_number() over (
             order by ts_rank_cd(to_tsvector('english', content), websearch_to_tsquery('english', p_query_text)) desc
           ) as rnk
    from candidates
    where p_query_text is not null
      and to_tsvector('english', content) @@ websearch_to_tsquery('english', p_query_text)
    limit greatest(p_match_count * 8, 40)
  ),
  fused as (
    select coalesce(v.id, t.id) as id,
           coalesce(v.similarity, 0)::double precision as similarity,
           coalesce(t.text_rank, 0)::double precision as text_rank,
           -- RRF with k = 60. Vector is weighted higher because paraphrase is the common case.
           (case when v.id is not null then 1.0 / (60 + v.rnk) else 0 end) * 1.0
         + (case when t.id is not null then 1.0 / (60 + t.rnk) else 0 end) * 0.6
             as base_score
    from vector_hits v
    full outer join text_hits t on t.id = v.id
  )
  select cd.id,
         cd.document_id,
         ld.title,
         cd.topic,
         ld.authority::text,
         cd.heading_path,
         cd.content,
         f.similarity,
         f.text_rank,
         f.base_score * case ld.authority::text
             when 'canonical'  then 1.30
             when 'verified'   then 1.15
             when 'working'    then 1.00
             when 'historical' then 0.80
             when 'external'   then 0.70
             when 'unverified' then 0.50
             else 1.00
           end as score
  from fused f
  join candidates cd on cd.id = f.id
  join live_docs ld on ld.id = cd.document_id
  where f.similarity >= p_min_similarity
  order by score desc
  limit p_match_count;
$$;

comment on function knowledge.match_chunks is
  'Hybrid retrieval over the credit knowledge base. Vector (hnsw, gte-small 384) fused with '
  'English full text via reciprocal rank fusion, weighted by source authority, excluding '
  'superseded documents. Callers must supply an embedding produced by the same gte-small '
  'model that wrote the column, otherwise the vectors are not comparable.';

grant execute on function knowledge.match_chunks(uuid, extensions.vector(384), text, int, double precision, text[], text[])
  to authenticated, service_role;
