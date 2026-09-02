CREATE OR REPLACE FUNCTION platform.is_org_admin(target_org uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'auth', 'platform'
AS $function$
  select exists (
    select 1
    from platform.organization_members om
    where om.organization_id = target_org
      and om.user_id = (select auth.uid())
      and om.status = 'active'
      and om.role in ('owner','admin')
  );
$function$
;

CREATE OR REPLACE FUNCTION platform.is_org_member(target_org uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'auth', 'platform'
AS $function$
  select exists (
    select 1
    from platform.organization_members om
    where om.organization_id = target_org
      and om.user_id = (select auth.uid())
      and om.status = 'active'
  );
$function$
;

CREATE OR REPLACE FUNCTION platform.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION intelligence.record_preference_response(p_organization_id uuid, p_user_id uuid, p_question_id uuid, p_answer jsonb, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_id uuid;v_key text;v_value text;
begin
 select signal_key into v_key from intelligence.preference_questions where id=p_question_id and organization_id=p_organization_id and active;
 if v_key is null then raise exception 'Preference question not found'; end if;
 v_value=trim(both '"' from p_answer::text);
 insert into intelligence.preference_responses(organization_id,user_id,question_id,signal_key,answer,context) values(p_organization_id,p_user_id,p_question_id,v_key,p_answer,p_context) returning id into v_id;
 insert into intelligence.preference_signals(organization_id,signal_key,signal_value,weight,positive_count,evidence_count,confidence,last_evidence_at)
 values(p_organization_id,v_key,v_value,1,1,1,.25,now())
 on conflict(organization_id,signal_key,signal_value) do update set weight=least(10,intelligence.preference_signals.weight+1),positive_count=intelligence.preference_signals.positive_count+1,evidence_count=intelligence.preference_signals.evidence_count+1,confidence=least(.95,intelligence.preference_signals.confidence+.08),last_evidence_at=now(),updated_at=now();
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION intelligence.upsert_performance_hypothesis(p_organization_id uuid, p_hypothesis_type text, p_mechanism_key text, p_statement text, p_episode_id uuid, p_post_id uuid, p_supports boolean, p_evidence jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'platform', 'intelligence'
AS $function$
declare v_id uuid; v_sample integer; v_support integer; v_contra integer; v_conf numeric; v_status text;
begin
  if not exists(select 1 from platform.organization_members where organization_id=p_organization_id and user_id=auth.uid() and status='active') then raise exception 'forbidden'; end if;
  select id into v_id from intelligence.performance_hypotheses where organization_id=p_organization_id and hypothesis_type=p_hypothesis_type and mechanism_key=p_mechanism_key limit 1;
  if v_id is null then
    insert into intelligence.performance_hypotheses(organization_id,hypothesis_type,mechanism_key,statement,evidence_episode_ids,evidence_post_ids,sample_size,supporting_count,contradicting_count,confidence,status,evidence,last_observed_at)
    values(p_organization_id,p_hypothesis_type,p_mechanism_key,p_statement,
      case when p_episode_id is null then '{}'::uuid[] else array[p_episode_id] end,
      case when p_post_id is null then '{}'::uuid[] else array[p_post_id] end,
      1,case when p_supports then 1 else 0 end,case when p_supports then 0 else 1 end,0.25,'observed',jsonb_build_array(p_evidence),now()) returning id into v_id;
  else
    update intelligence.performance_hypotheses h set
      statement=p_statement,
      evidence_episode_ids=case when p_episode_id is null or p_episode_id=any(h.evidence_episode_ids) then h.evidence_episode_ids else array_append(h.evidence_episode_ids,p_episode_id) end,
      evidence_post_ids=case when p_post_id is null or p_post_id=any(h.evidence_post_ids) then h.evidence_post_ids else array_append(h.evidence_post_ids,p_post_id) end,
      sample_size=h.sample_size+case when p_post_id is null or p_post_id=any(h.evidence_post_ids) then 0 else 1 end,
      supporting_count=h.supporting_count+case when p_supports and (p_post_id is null or not p_post_id=any(h.evidence_post_ids)) then 1 else 0 end,
      contradicting_count=h.contradicting_count+case when not p_supports and (p_post_id is null or not p_post_id=any(h.evidence_post_ids)) then 1 else 0 end,
      evidence=case when p_post_id is null or p_post_id=any(h.evidence_post_ids) then h.evidence else h.evidence||jsonb_build_array(p_evidence) end,
      last_observed_at=now(),updated_at=now()
    where h.id=v_id;
  end if;
  select sample_size,supporting_count,contradicting_count into v_sample,v_support,v_contra from intelligence.performance_hypotheses where id=v_id;
  v_conf := least(0.95, greatest(0.10, (v_support+1)::numeric/(v_sample+2) * least(1.0,v_sample::numeric/5.0)));
  v_status := case
    when v_sample>=5 and v_support::numeric/nullif(v_sample,0)>=0.80 then 'working_pattern'
    when v_sample>=8 and v_contra::numeric/nullif(v_sample,0)>=0.50 then 'rejected'
    when v_sample>=3 then 'testing'
    else 'observed' end;
  update intelligence.performance_hypotheses set confidence=v_conf,status=v_status,updated_at=now() where id=v_id;
  return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION knowledge.enqueue_chunk_embedding()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.embedding is null then
    perform pgmq.send(
      'dre_embeddings',
      jsonb_build_object(
        'chunk_id', new.id,
        'organization_id', new.organization_id,
        'document_id', new.document_id,
        'event', 'embed_chunk'
      )
    );
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION knowledge.invalidate_chunk_embedding()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'knowledge'
AS $function$
begin
  if new.content is distinct from old.content or new.heading_path is distinct from old.heading_path then
    new.embedding := null;
    new.embedding_model := null;
    new.embedding_dimensions := null;
    new.embedded_at := null;
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION studio.align_retention_to_beats(p_platform_post_id uuid, p_observed_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'platform', 'studio', 'intelligence'
AS $function$
declare
  v_post studio.platform_posts%rowtype;
  v_obs timestamptz;
  v_duration numeric;
  v_inserted integer := 0;
  v_skipped integer := 0;
  r record;
  v_start numeric;
  v_end numeric;
  v_avg numeric;
  v_rel numeric;
  v_points integer;
  v_conf numeric;
begin
  select * into v_post from studio.platform_posts where id=p_platform_post_id;
  if v_post.id is null then raise exception 'platform post not found'; end if;
  if not exists(select 1 from platform.organization_members where organization_id=v_post.organization_id and user_id=auth.uid() and status='active') then raise exception 'forbidden'; end if;

  select coalesce(p_observed_at,max(observed_at)) into v_obs from studio.retention_points where platform_post_id=v_post.id;
  if v_obs is null then return jsonb_build_object('aligned',0,'skipped',0,'reason','no_retention_points'); end if;

  select nullif(coalesce((metadata->>'duration_seconds')::numeric,avg_view_duration_seconds/nullif(avg_percentage_viewed,0)),0)
    into v_duration
  from studio.content_metrics
  where platform_post_id=v_post.id and observed_at<=v_obs
  order by observed_at desc limit 1;

  if v_duration is null then
    select max(end_seconds) into v_duration from studio.beat_time_ranges where episode_id=v_post.episode_id and (platform_post_id is null or platform_post_id=v_post.id);
  end if;
  if v_duration is null or v_duration<=0 then return jsonb_build_object('aligned',0,'skipped',0,'reason','unknown_duration'); end if;

  for r in
    select distinct on (btr.beat_id) btr.*
    from studio.beat_time_ranges btr
    where btr.episode_id=v_post.episode_id and (btr.platform_post_id is null or btr.platform_post_id=v_post.id)
    order by btr.beat_id, (btr.platform_post_id=v_post.id) desc, btr.confidence desc nulls last, btr.created_at desc
  loop
    select
      (select rp.audience_watch_ratio from studio.retention_points rp where rp.platform_post_id=v_post.id and rp.observed_at=v_obs and rp.audience_watch_ratio is not null order by abs((rp.elapsed_ratio*v_duration)-r.start_seconds) limit 1),
      (select rp.audience_watch_ratio from studio.retention_points rp where rp.platform_post_id=v_post.id and rp.observed_at=v_obs and rp.audience_watch_ratio is not null order by abs((rp.elapsed_ratio*v_duration)-r.end_seconds) limit 1),
      avg(rp.audience_watch_ratio) filter(where rp.audience_watch_ratio is not null),
      avg(rp.relative_retention_performance) filter(where rp.relative_retention_performance is not null),
      count(*)
    into v_start,v_end,v_avg,v_rel,v_points
    from studio.retention_points rp
    where rp.platform_post_id=v_post.id and rp.observed_at=v_obs
      and (rp.elapsed_ratio*v_duration) between r.start_seconds and r.end_seconds;

    if v_points=0 then v_skipped:=v_skipped+1; continue; end if;
    v_conf := least(1.0, coalesce(r.confidence,0.7) * least(1.0, v_points::numeric/3.0));

    insert into studio.beat_performance_observations(
      organization_id,episode_id,platform_post_id,beat_id,observed_at,start_seconds,end_seconds,
      start_audience_ratio,end_audience_ratio,avg_audience_ratio,retention_delta,relative_retention_avg,points_used,alignment_confidence,interpretation
    ) values(
      v_post.organization_id,v_post.episode_id,v_post.id,r.beat_id,v_obs,r.start_seconds,r.end_seconds,
      v_start,v_end,v_avg,case when v_start is not null and v_end is not null then v_end-v_start end,v_rel,v_points,v_conf,
      jsonb_build_object('causal_claims_allowed',false,'source','retention_curve_alignment','duration_seconds',v_duration,'range_source',r.source)
    ) on conflict(platform_post_id,beat_id,observed_at) do update set
      start_audience_ratio=excluded.start_audience_ratio,end_audience_ratio=excluded.end_audience_ratio,
      avg_audience_ratio=excluded.avg_audience_ratio,retention_delta=excluded.retention_delta,
      relative_retention_avg=excluded.relative_retention_avg,points_used=excluded.points_used,
      alignment_confidence=excluded.alignment_confidence,interpretation=excluded.interpretation;
    v_inserted:=v_inserted+1;
  end loop;
  return jsonb_build_object('aligned',v_inserted,'skipped',v_skipped,'observed_at',v_obs,'duration_seconds',v_duration);
end $function$
;

CREATE OR REPLACE FUNCTION studio.auto_capture_platform_lineage()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.episode_id is not null then perform studio.capture_platform_lineage(new.id); end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION studio.capture_platform_lineage(p_platform_post_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_post studio.platform_posts%rowtype;
  v_package studio.packaging_hypotheses%rowtype;
  v_edit studio.edit_decision_specs%rowtype;
  v_lineage uuid;
begin
  select * into v_post from studio.platform_posts where id=p_platform_post_id;
  if v_post.id is null or v_post.episode_id is null then return null; end if;
  select * into v_package from studio.packaging_hypotheses where episode_id=v_post.episode_id order by selected desc,score desc nulls last,created_at limit 1;
  select * into v_edit from studio.edit_decision_specs where episode_id=v_post.episode_id order by version desc,updated_at desc limit 1;
  insert into studio.creative_lineage(organization_id,episode_id,platform_post_id,clip_id,package_hypothesis_id,edit_spec_id,opening_text,thumbnail_snapshot,package_snapshot,story_snapshot,production_snapshot)
  select e.organization_id,e.id,v_post.id,v_post.clip_id,v_package.id,v_edit.id,e.opening,
    coalesce((select to_jsonb(t) from studio.thumbnails t where t.episode_id=e.id and t.selected order by t.updated_at desc limit 1),coalesce(e.metadata->'thumbnail_package','{}'::jsonb)),
    coalesce(to_jsonb(v_package),'{}'::jsonb),
    jsonb_build_object('viewer_promise',e.viewer_promise,'stakes',e.stakes,'central_question',e.central_question,'story_arc',e.story_arc,'beats',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'beat_number',b.beat_number,'type',b.beat_type,'purpose',b.purpose,'emotion',b.emotion_target,'clip_candidate',b.clip_candidate) order by b.beat_number) from studio.episode_beats b where b.episode_id=e.id),'[]'::jsonb)),
    jsonb_build_object('actor_pack',coalesce(e.metadata->'actor_pack_v2','{}'::jsonb),'capture_qc',coalesce(e.metadata->'capture_qc','{}'::jsonb),'edit_spec_version',v_edit.version)
  from studio.episodes e where e.id=v_post.episode_id
  on conflict(platform_post_id) do update set package_hypothesis_id=excluded.package_hypothesis_id,edit_spec_id=excluded.edit_spec_id,opening_text=excluded.opening_text,thumbnail_snapshot=excluded.thumbnail_snapshot,package_snapshot=excluded.package_snapshot,story_snapshot=excluded.story_snapshot,production_snapshot=excluded.production_snapshot
  returning id into v_lineage;
  return v_lineage;
end $function$
;

CREATE OR REPLACE FUNCTION studio.capture_text_coverage(p_expected text, p_actual text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
with expected_words as (
  select distinct w
  from regexp_split_to_table(lower(coalesce(p_expected,'')),'[^a-z0-9]+') w
  where length(w)>=4
    and w not in ('this','that','with','from','your','have','what','when','then','they','them','there','here','into','about','just','like','because','would','could','should','will','dont','doesnt','cant','youre','were','been','being')
), actual_text as (
  select ' '||regexp_replace(lower(coalesce(p_actual,'')),'[^a-z0-9]+',' ','g')||' ' as t
)
select case when count(*)=0 then 1::numeric
            else round(count(*) filter(where strpos((select t from actual_text),' '||w||' ')>0)::numeric/count(*)::numeric,4)
       end
from expected_words;
$function$
;

CREATE OR REPLACE FUNCTION studio.enqueue_metrics_learning()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform pgmq.send(
    'dre_content_learning',
    jsonb_build_object(
      'metric_id', new.id,
      'organization_id', new.organization_id,
      'platform_post_id', new.platform_post_id,
      'observed_at', new.observed_at,
      'event', 'metrics_snapshot_created'
    )
  );
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION studio.get_unused_formats(p_organization_id uuid, p_days integer DEFAULT NULL::integer)
 RETURNS SETOF studio.content_formats
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$ select f.* from studio.content_formats f where f.organization_id = p_organization_id and f.status = 'active' and not exists ( select 1 from studio.content_ideas i join studio.format_variants v on v.id = i.format_variant_id where v.format_id = f.id and i.created_at > now() - (coalesce(p_days, f.fatigue_window_days, 30) || ' days')::interval ); $function$
;

CREATE OR REPLACE FUNCTION studio.ingest_director_episode(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'platform', 'studio', 'knowledge'
AS $function$
declare
  v_org uuid := '3430937f-4288-4e1a-be5c-ec6b5c1c7976';
  v_series uuid;
  v_day uuid;
  v_doc uuid;
  v_episode uuid;
  v_chunk text;
  v_idx int;
begin
  select id into v_series from studio.content_series where organization_id=v_org and series_code='RANK';
  select id into v_day from studio.production_days where organization_id=v_org and production_code='PD-2026-08-10-001';
  select id into v_doc from knowledge.documents where organization_id=v_org and checksum='7ffc32270a739bc009bed4713dc04c4bf82c6ff48ba8d5eaccd8c5533b73e942' order by created_at desc limit 1;

  insert into studio.episodes
    (organization_id,series_id,production_day_id,episode_code,working_title,audience,viewer_promise,why_it_exists,opening,cta,status,metadata)
  values
    (v_org,v_series,v_day,p->>'code',p->>'title',p->>'audience',p->>'angle',p->>'scenario',p->>'opening',p->>'cta','ready',
     jsonb_build_object('runtime',p->>'runtime','operator_instruction',p->>'operator_instruction','director_note',p->>'director_note','set_note',p->>'set_note','source_file','LaSean_PD001_Studio_Director_Bible.html','planned_only',true))
  on conflict (organization_id,episode_code) do update
    set working_title=excluded.working_title,audience=excluded.audience,viewer_promise=excluded.viewer_promise,why_it_exists=excluded.why_it_exists,
        opening=excluded.opening,cta=excluded.cta,status='ready',metadata=excluded.metadata,updated_at=now()
  returning id into v_episode;

  delete from studio.episode_cues where episode_id=v_episode;
  insert into studio.episode_cues
    (organization_id,episode_id,cue_number,operator_prompt,default_rank,default_response,performance_direction,planned,metadata)
  select v_org,v_episode,(c->>'cue_number')::int,c->>'operator_prompt',c->>'default_rank',c->>'default_response',c->>'performance_direction',true,
         jsonb_build_object('source_file','LaSean_PD001_Studio_Director_Bible.html')
  from jsonb_array_elements(coalesce(p->'cues','[]'::jsonb)) c;

  insert into studio.hooks (organization_id,episode_id,hook_text,hook_type,variant_label,selected,metadata)
  values (v_org,v_episode,p->>'opening','opening_exact','director_bible',true,jsonb_build_object('source_file','LaSean_PD001_Studio_Director_Bible.html'))
  on conflict (episode_id,variant_label) where episode_id is not null and variant_label is not null
  do update set hook_text=excluded.hook_text,hook_type=excluded.hook_type,selected=true,metadata=excluded.metadata;

  insert into studio.titles (organization_id,episode_id,title_text,variant_label,selected,metadata)
  values (v_org,v_episode,p->>'title','director_bible',true,jsonb_build_object('source_file','LaSean_PD001_Studio_Director_Bible.html'))
  on conflict (episode_id,variant_label) where episode_id is not null and variant_label is not null
  do update set title_text=excluded.title_text,selected=true,metadata=excluded.metadata;

  insert into studio.thumbnails (organization_id,episode_id,concept,visual_direction,variant_label,selected,status,metadata)
  values (v_org,v_episode,p->>'thumbnail',p->>'thumbnail','director_bible',true,'ready',jsonb_build_object('source_file','LaSean_PD001_Studio_Director_Bible.html'))
  on conflict (episode_id,variant_label) do update set concept=excluded.concept,visual_direction=excluded.visual_direction,selected=true,status='ready',metadata=excluded.metadata,updated_at=now();

  delete from studio.scripts where episode_id=v_episode and script_type='director_bible';
  select concat_ws(E'\n',p->>'title','Opening: '||(p->>'opening'),'Angle: '||(p->>'angle'),'Audience: '||(p->>'audience'),'Director note: '||(p->>'director_note'),'CTA: '||(p->>'cta'),
    (select string_agg('Cue '||(c->>'cue_number')||': '||(c->>'operator_prompt')||' | Default rank: '||(c->>'default_rank')||' | Response: '||(c->>'default_response'), E'\n' order by (c->>'cue_number')::int)
     from jsonb_array_elements(coalesce(p->'cues','[]'::jsonb)) c)) into v_chunk;

  insert into studio.scripts (organization_id,episode_id,script_type,version,content,approved,status,metadata)
  values (v_org,v_episode,'director_bible',1,v_chunk,false,'ready',jsonb_build_object('source_file','LaSean_PD001_Studio_Director_Bible.html','planned_only',true));

  v_idx := nullif(regexp_replace(p->>'code','\D','','g'),'')::int;
  if v_doc is not null and v_idx is not null then
    insert into knowledge.document_chunks (organization_id,document_id,chunk_index,heading_path,content,metadata)
    values (v_org,v_doc,v_idx,p->>'code',v_chunk,jsonb_build_object('episode_code',p->>'code','title',p->>'title','production_code','PD-2026-08-10-001'))
    on conflict (document_id,chunk_index) do update set heading_path=excluded.heading_path,content=excluded.content,metadata=excluded.metadata,embedding=null,embedding_model=null,embedding_dimensions=null,embedded_at=null;
  end if;
  return v_episode;
end;
$function$
;

CREATE OR REPLACE FUNCTION studio.latest_platform_baseline(p_organization_id uuid, p_platform text, p_exclude_episode uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'studio'
AS $function$
  with latest as (
    select distinct on (p.id) p.id,p.episode_id,m.*
    from studio.platform_posts p join studio.content_metrics m on m.platform_post_id=p.id
    where p.organization_id=p_organization_id and p.platform=p_platform and (p_exclude_episode is null or p.episode_id is distinct from p_exclude_episode)
    order by p.id,m.observed_at desc
  )
  select jsonb_build_object(
    'sample_size',count(*),
    'median_views',percentile_cont(.5) within group(order by views) filter(where views is not null),
    'median_ctr',percentile_cont(.5) within group(order by ctr) filter(where ctr is not null),
    'median_retention_30s',percentile_cont(.5) within group(order by retention_30s) filter(where retention_30s is not null),
    'median_avg_percentage_viewed',percentile_cont(.5) within group(order by avg_percentage_viewed) filter(where avg_percentage_viewed is not null),
    'median_completion_rate',percentile_cont(.5) within group(order by completion_rate) filter(where completion_rate is not null),
    'median_engagement_rate',percentile_cont(.5) within group(order by case when views>0 then (coalesce(likes,0)+coalesce(comments,0)+coalesce(shares,0)+coalesce(saves,0))::numeric/views end)
  ) from latest
$function$
;

CREATE OR REPLACE FUNCTION studio.log_episode_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status is distinct from old.status then
    insert into studio.content_lifecycle_events(
      organization_id, episode_id, event_type, from_status, to_status, source, metadata
    ) values (
      new.organization_id, new.id, 'episode_status_changed', old.status::text, new.status::text, 'database_trigger',
      jsonb_build_object('episode_code', new.episode_code)
    );
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION studio.log_platform_post_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status is distinct from old.status then
    insert into studio.content_lifecycle_events(
      organization_id, episode_id, clip_id, platform_post_id, event_type, from_status, to_status, source, metadata
    ) values (
      new.organization_id, new.episode_id, new.clip_id, new.id, 'platform_post_status_changed', old.status::text, new.status::text, 'database_trigger',
      jsonb_build_object('platform', new.platform, 'external_post_id', new.external_post_id)
    );
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION studio.materialize_content_calendar(p_organization_id uuid, p_start_date date DEFAULT CURRENT_DATE, p_days integer DEFAULT 21)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'studio', 'public'
AS $function$
declare v_count integer;
begin
 insert into studio.content_calendar(organization_id,publish_date,slot_number,content_role,format_mode,platform_targets,status,metadata)
 select pt.organization_id,d::date,pt.slot_number,pt.content_role,pt.source_pool,pt.platform_targets,'planned',jsonb_build_object('template_id',pt.id,'preferred_formats',pt.preferred_formats,'strategic_note',pt.strategic_note)
 from generate_series(p_start_date,p_start_date+greatest(p_days-1,0),interval '1 day') d
 join studio.publishing_templates pt on pt.organization_id=p_organization_id and pt.active=true and pt.day_of_week=extract(dow from d)::int
 on conflict (organization_id,publish_date,slot_number) do nothing;
 get diagnostics v_count=row_count; return v_count;
end;$function$
;

CREATE OR REPLACE FUNCTION studio.process_content_learning_queue(p_limit integer DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; processed integer := 0; v_post studio.platform_posts%rowtype; v_episode studio.episodes%rowtype; v_metric studio.content_metrics%rowtype; v_format_id uuid; v_engagement bigint; v_engagement_rate numeric;
begin
  for r in select * from pgmq.read('dre_content_learning', 120, greatest(1,least(coalesce(p_limit,20),100))) loop
    begin
      select * into v_metric from studio.content_metrics where id=(r.message->>'metric_id')::uuid;
      if not found then perform pgmq.delete('dre_content_learning', r.msg_id); continue; end if;
      select * into v_post from studio.platform_posts where id=v_metric.platform_post_id;
      if found and v_post.episode_id is not null then select * into v_episode from studio.episodes where id=v_post.episode_id; v_format_id := v_episode.format_id; else v_format_id := null; end if;
      v_engagement := coalesce(v_metric.likes,0)+coalesce(v_metric.comments,0)+coalesce(v_metric.shares,0)+coalesce(v_metric.saves,0);
      v_engagement_rate := case when coalesce(v_metric.views,0)>0 then v_engagement::numeric/v_metric.views::numeric else null end;
      insert into studio.performance_observations(organization_id,platform_post_id,metric_id,episode_id,format_id,observed_at,views,engagement_count,engagement_rate,avg_percentage_viewed,completion_rate,leads,customers,revenue,evidence_strength,interpretation)
      values (v_metric.organization_id,v_metric.platform_post_id,v_metric.id,v_post.episode_id,v_format_id,v_metric.observed_at,v_metric.views,v_engagement,v_engagement_rate,v_metric.avg_percentage_viewed,v_metric.completion_rate,v_metric.leads,v_metric.customers,v_metric.revenue,'snapshot',jsonb_build_object('guardrail','One metrics snapshot is an observation, not a validated content lesson. Promote patterns only after repeated evidence or explicit review.'))
      on conflict (metric_id) do nothing;
      perform pgmq.delete('dre_content_learning', r.msg_id); processed := processed + 1;
    exception when others then null;
    end;
  end loop;
  return processed;
end;
$function$
;

CREATE OR REPLACE FUNCTION studio.run_capture_qc(p_episode_id uuid, p_asset_id uuid, p_transcript text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
  v_opening text;
  v_opening_cov numeric;
  v_beat record;
  v_cov numeric;
  v_failures jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_passes integer := 0;
  v_total integer := 0;
  v_pickup boolean := false;
  v_summary jsonb;
begin
  select organization_id,opening into v_org,v_opening from studio.episodes where id=p_episode_id;
  if v_org is null then raise exception 'episode not found'; end if;
  if length(trim(coalesce(p_transcript,'')))<40 then
    v_summary:=jsonb_build_object('status','insufficient_transcript','pickup_required',false,'confidence',0,'message','Transcript is too short for capture QC.');
    return v_summary;
  end if;

  delete from studio.capture_checks
  where episode_id=p_episode_id and metadata->>'asset_id'=p_asset_id::text and metadata->>'qc_version'='capture_text_v1';

  v_opening_cov:=studio.capture_text_coverage(v_opening,p_transcript);
  insert into studio.capture_checks(organization_id,episode_id,check_type,status,message,confidence,metadata)
  values(v_org,p_episode_id,'locked_opening',case when v_opening_cov<0.25 then 'fail' when v_opening_cov<0.45 then 'warn' else 'pass' end,
    case when v_opening_cov<0.25 then 'Locked opening appears missing or materially different. Capture a clean opening pickup.' when v_opening_cov<0.45 then 'Opening is present only partially. Review before leaving the set.' else 'Locked opening is represented in the transcript.' end,
    v_opening_cov,jsonb_build_object('asset_id',p_asset_id,'qc_version','capture_text_v1','coverage',v_opening_cov));
  if v_opening_cov<0.25 then v_pickup:=true;v_failures:=v_failures||jsonb_build_array(jsonb_build_object('type','opening','coverage',v_opening_cov,'pickup','Recapture the locked opening cleanly.'));
  elsif v_opening_cov<0.45 then v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('type','opening','coverage',v_opening_cov)); end if;

  for v_beat in select id,beat_number,purpose,spoken_content from studio.episode_beats where episode_id=p_episode_id order by beat_number loop
    v_total:=v_total+1;
    v_cov:=studio.capture_text_coverage(v_beat.spoken_content,p_transcript);
    insert into studio.capture_checks(organization_id,episode_id,check_type,status,message,confidence,metadata)
    values(v_org,p_episode_id,'planned_beat',case when v_cov<0.15 then 'fail' when v_cov<0.35 then 'warn' else 'pass' end,
      case when v_cov<0.15 then format('Beat %s appears absent: %s',v_beat.beat_number,v_beat.purpose) when v_cov<0.35 then format('Beat %s is only partially represented: %s',v_beat.beat_number,v_beat.purpose) else format('Beat %s is represented.',v_beat.beat_number) end,
      v_cov,jsonb_build_object('asset_id',p_asset_id,'qc_version','capture_text_v1','beat_id',v_beat.id,'beat_number',v_beat.beat_number,'purpose',v_beat.purpose,'coverage',v_cov));
    if v_cov<0.15 then
      v_pickup:=true;
      v_failures:=v_failures||jsonb_build_array(jsonb_build_object('type','beat','beat_number',v_beat.beat_number,'purpose',v_beat.purpose,'coverage',v_cov,'pickup',format('Capture the missing Beat %s: %s',v_beat.beat_number,v_beat.purpose)));
    elsif v_cov<0.35 then
      v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('type','beat','beat_number',v_beat.beat_number,'purpose',v_beat.purpose,'coverage',v_cov));
    else v_passes:=v_passes+1; end if;
  end loop;

  v_summary:=jsonb_build_object(
    'status',case when v_pickup then 'pickup_required' when jsonb_array_length(v_warnings)>0 then 'review' else 'pass' end,
    'pickup_required',v_pickup,
    'opening_coverage',v_opening_cov,
    'beats_total',v_total,
    'beats_passed',v_passes,
    'failures',v_failures,
    'warnings',v_warnings,
    'qc_version','capture_text_v1',
    'note','Lexical capture QC is a conservative missing-material check, not a performance-quality score.'
  );

  update studio.episodes
  set production_state=case when v_pickup then 'reshoot_required' else case when production_state in ('recorded','shoot_ready') then 'ingested' else production_state end end,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('capture_qc',v_summary),updated_at=now()
  where id=p_episode_id;

  return v_summary;
end $function$
;

CREATE OR REPLACE FUNCTION studio.submit_episode_review(p_organization_id uuid, p_episode_id uuid, p_reviewer_person_id uuid DEFAULT NULL::uuid, p_liked text DEFAULT NULL::text, p_disliked text DEFAULT NULL::text, p_felt_natural text DEFAULT NULL::text, p_felt_forced text DEFAULT NULL::text, p_keep_next_time text DEFAULT NULL::text, p_change_next_time text DEFAULT NULL::text, p_overall_notes text DEFAULT NULL::text, p_overall_rating numeric DEFAULT NULL::numeric, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'studio', 'public'
AS $function$
declare
  v_review_id uuid;
  v_prod_day uuid;
  v_episode_code text;
  v_title text;
begin
  select production_day_id, episode_code, working_title
    into v_prod_day, v_episode_code, v_title
  from studio.episodes
  where id = p_episode_id and organization_id = p_organization_id;

  if not found then
    raise exception 'Episode not found for organization';
  end if;

  insert into studio.episode_reviews(
    organization_id, episode_id, production_day_id, reviewer_person_id,
    liked, disliked, felt_natural, felt_forced, keep_next_time, change_next_time,
    overall_notes, overall_rating, metadata, learnings_generated
  ) values (
    p_organization_id, p_episode_id, v_prod_day, p_reviewer_person_id,
    p_liked, p_disliked, p_felt_natural, p_felt_forced, p_keep_next_time, p_change_next_time,
    p_overall_notes, p_overall_rating, coalesce(p_metadata,'{}'::jsonb), true
  ) returning id into v_review_id;

  if nullif(trim(p_liked),'') is not null then
    insert into studio.content_learnings(
      organization_id, production_day_id, episode_id, learning_stage, learning_type,
      statement, evidence, confidence, action_recommendation, status, metadata
    ) values (
      p_organization_id, v_prod_day, p_episode_id, 'post_film', 'positive_feedback',
      p_liked,
      jsonb_build_object('review_id',v_review_id,'episode_code',v_episode_code,'title',v_title,'source','direct_user_review'),
      1.0,
      coalesce(nullif(trim(p_keep_next_time),''),'Preserve the elements LaSean explicitly liked in future relevant productions.'),
      'active', jsonb_build_object('authoritative_user_feedback',true)
    );
  end if;

  if nullif(trim(p_disliked),'') is not null then
    insert into studio.content_learnings(
      organization_id, production_day_id, episode_id, learning_stage, learning_type,
      statement, evidence, confidence, action_recommendation, status, metadata
    ) values (
      p_organization_id, v_prod_day, p_episode_id, 'post_film', 'negative_feedback',
      p_disliked,
      jsonb_build_object('review_id',v_review_id,'episode_code',v_episode_code,'title',v_title,'source','direct_user_review'),
      1.0,
      coalesce(nullif(trim(p_change_next_time),''),'Avoid or redesign the elements LaSean explicitly disliked in future relevant productions.'),
      'active', jsonb_build_object('authoritative_user_feedback',true)
    );
  end if;

  if nullif(trim(p_felt_natural),'') is not null then
    insert into studio.content_learnings(
      organization_id, production_day_id, episode_id, learning_stage, learning_type,
      statement, evidence, confidence, action_recommendation, status, metadata
    ) values (
      p_organization_id, v_prod_day, p_episode_id, 'post_film', 'performance_naturalness',
      p_felt_natural,
      jsonb_build_object('review_id',v_review_id,'episode_code',v_episode_code,'source','direct_user_review'),
      1.0,
      'Favor these performance mechanics, script structures, and production choices when they fit the premise.',
      'active', jsonb_build_object('authoritative_user_feedback',true,'valence','positive')
    );
  end if;

  if nullif(trim(p_felt_forced),'') is not null then
    insert into studio.content_learnings(
      organization_id, production_day_id, episode_id, learning_stage, learning_type,
      statement, evidence, confidence, action_recommendation, status, metadata
    ) values (
      p_organization_id, v_prod_day, p_episode_id, 'post_film', 'performance_naturalness',
      p_felt_forced,
      jsonb_build_object('review_id',v_review_id,'episode_code',v_episode_code,'source','direct_user_review'),
      1.0,
      'Remove, shorten, or redesign these forced-feeling mechanics in future productions.',
      'active', jsonb_build_object('authoritative_user_feedback',true,'valence','negative')
    );
  end if;

  update studio.episodes
     set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('last_review_id',v_review_id,'reviewed_at',now()),
         updated_at = now()
   where id = p_episode_id;

  return v_review_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION research.sync_creator_mechanism_to_knowledge()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'research', 'knowledge', 'platform'
AS $function$
declare
  v_doc_id uuid;
  v_text text;
  v_source_uri text;
begin
  v_source_uri := 'dre://creator-mechanism/' || new.id::text;
  v_text := concat_ws(E'\n',
    'Creator: ' || coalesce((select canonical_name from research.creator_profiles where id=new.creator_profile_id),'Unknown'),
    'Mechanism: ' || new.mechanism_name,
    case when new.category is not null then 'Category: ' || new.category end,
    case when new.description is not null then 'Description: ' || new.description end,
    case when new.why_it_works is not null then 'Why it works: ' || new.why_it_works end,
    case when new.lasean_adaptation is not null then 'LaSean adaptation: ' || new.lasean_adaptation end,
    case when new.avoid is not null then 'Avoid: ' || new.avoid end,
    case when new.success_metric is not null then 'Success metric: ' || new.success_metric end,
    case when new.trend_dependency is not null then 'Trend dependency: ' || new.trend_dependency end
  );

  select id into v_doc_id
  from knowledge.documents
  where organization_id=new.organization_id and source_uri=v_source_uri
  order by created_at desc limit 1;

  if v_doc_id is null then
    insert into knowledge.documents(
      organization_id,title,document_type,source_uri,authority,confidentiality,effective_at,ingestion_status,raw_text,metadata
    ) values (
      new.organization_id,
      'Creator Mechanism · ' || coalesce((select canonical_name from research.creator_profiles where id=new.creator_profile_id),'Unknown') || ' · ' || new.mechanism_name,
      'creator_mechanism',v_source_uri,'verified','internal',now(),'complete',v_text,
      jsonb_build_object('creator_mechanism_id',new.id,'creator_profile_id',new.creator_profile_id,'source','dre_research_sync')
    ) returning id into v_doc_id;
  else
    update knowledge.documents
    set title='Creator Mechanism · ' || coalesce((select canonical_name from research.creator_profiles where id=new.creator_profile_id),'Unknown') || ' · ' || new.mechanism_name,
        raw_text=v_text,updated_at=now(),effective_at=now(),ingestion_status='complete',
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('creator_mechanism_id',new.id,'creator_profile_id',new.creator_profile_id,'source','dre_research_sync')
    where id=v_doc_id;
  end if;

  if exists(select 1 from knowledge.document_chunks where document_id=v_doc_id and chunk_index=0) then
    update knowledge.document_chunks
    set heading_path=new.mechanism_name,content=v_text,token_count=ceil(length(v_text)/4.0)::int,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('creator_mechanism_id',new.id,'creator_profile_id',new.creator_profile_id,'creator_intelligence',true)
    where document_id=v_doc_id and chunk_index=0;
  else
    insert into knowledge.document_chunks(organization_id,document_id,chunk_index,heading_path,content,token_count,metadata)
    values(new.organization_id,v_doc_id,0,new.mechanism_name,v_text,ceil(length(v_text)/4.0)::int,
      jsonb_build_object('creator_mechanism_id',new.id,'creator_profile_id',new.creator_profile_id,'creator_intelligence',true));
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION system.advance_media_assembly_lines()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_unlocked int:=0; v_failed int:=0; v_waiting int:=0;
begin
  update studio.pipeline_stages s
  set status='queued',available_at=now(),updated_at=now()
  where s.status='blocked'
    and exists(select 1 from studio.pipeline_stages d where d.pipeline_run_id=s.pipeline_run_id and d.stage_code=s.depends_on_stage_code and d.status in ('completed','skipped'))
    and not exists(select 1 from studio.pipeline_stages f where f.pipeline_run_id=s.pipeline_run_id and f.status='failed')
    and not (s.stage_code='analyze_structure' and exists(select 1 from studio.pipeline_runs r where r.id=s.pipeline_run_id and coalesce((r.context_snapshot#>>'{capture_qc,pickup_required}')::boolean,false)=true));
  get diagnostics v_unlocked=row_count;

  update studio.pipeline_runs r
  set status='failed',current_stage=s.stage_code,error=jsonb_build_object('stage',s.stage_code,'code',s.error_code,'message',s.error_message),updated_at=now()
  from studio.pipeline_stages s where s.pipeline_run_id=r.id and s.status='failed' and r.status not in ('failed','cancelled','completed');
  get diagnostics v_failed=row_count;

  with next_stage as (select distinct on (pipeline_run_id) pipeline_run_id,stage_code from studio.pipeline_stages where status in ('queued','running','awaiting_approval') order by pipeline_run_id,stage_order)
  update studio.pipeline_runs r
  set status=case when s.stage_code='human_review' then 'awaiting_approval' when s.stage_code='publish' then 'publishing' else 'running' end,current_stage=s.stage_code,started_at=coalesce(r.started_at,now()),updated_at=now()
  from next_stage s where s.pipeline_run_id=r.id and r.status not in ('failed','cancelled','completed','approved');
  get diagnostics v_waiting=row_count;

  update studio.pipeline_runs r set status='completed',completed_at=now(),updated_at=now()
  where r.status not in ('completed','failed','cancelled') and not exists(select 1 from studio.pipeline_stages s where s.pipeline_run_id=r.id and s.status not in ('completed','skipped'));

  return jsonb_build_object('unlocked',v_unlocked,'failed',v_failed,'active_updated',v_waiting,'at',now());
end $function$
;

CREATE OR REPLACE FUNCTION system.autonomy_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare retried int:=0; timed_out int:=0;
begin
  update system.automation_runs set status='failed', error_message='worker lease expired', available_at=now()+interval '2 minutes', updated_at=now()
  where status='running' and claimed_at < now()-interval '15 minutes' and attempt_count < max_attempts;
  get diagnostics timed_out = row_count;
  update system.automation_runs set status='queued', updated_at=now() where status='failed' and attempt_count < max_attempts and available_at <= now();
  get diagnostics retried = row_count;
  return jsonb_build_object('retried',retried,'leases_recovered',timed_out,'at',now());
end $function$
;

CREATE OR REPLACE FUNCTION system.capture_qc_after_transcribe()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_episode uuid;
  v_transcript text;
  v_qc jsonb;
begin
  if new.stage_code='transcribe' and new.status='completed' and old.status is distinct from new.status then
    select episode_id into v_episode from studio.assets where id=new.source_asset_id;
    if v_episode is not null then
      v_transcript:=coalesce(new.output->>'transcript',new.output->>'text',new.output->>'full_text',new.output#>>'{transcript,text}',new.output#>>'{result,transcript}',new.output#>>'{result,text}');
      if length(trim(coalesce(v_transcript,'')))>=40 then
        update studio.assets set transcript=v_transcript,updated_at=now() where id=new.source_asset_id and (transcript is null or length(transcript)<length(v_transcript));
        v_qc:=studio.run_capture_qc(v_episode,new.source_asset_id,v_transcript);
        update studio.pipeline_runs set context_snapshot=coalesce(context_snapshot,'{}'::jsonb)||jsonb_build_object('capture_qc',v_qc),updated_at=now() where id=new.pipeline_run_id;
      end if;
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION system.claim_pipeline_stage(p_worker_class text, p_worker_id text)
 RETURNS SETOF studio.pipeline_stages
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  return query
  with candidate as (
    select id from studio.pipeline_stages where status='queued' and worker_class=p_worker_class and available_at<=now()
    order by stage_order,created_at for update skip locked limit 1
  )
  update studio.pipeline_stages s set status='running',claimed_by=p_worker_id,claimed_at=now(),heartbeat_at=now(),started_at=coalesce(started_at,now()),attempts=attempts+1,updated_at=now()
  from candidate c where s.id=c.id returning s.*;
end $function$
;

CREATE OR REPLACE FUNCTION system.complete_pipeline_stage(p_stage_id uuid, p_worker_id text, p_output jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 s studio.pipeline_stages;
 v_policy studio.stage_gate_policies;
 v_eval studio.stage_gate_evaluations;
begin
 select * into s
 from studio.pipeline_stages
 where id=p_stage_id and status='running' and claimed_by=p_worker_id
 for update;
 if s.id is null then raise exception 'Stage claim not found'; end if;

 select * into v_policy
 from studio.stage_gate_policies
 where organization_id=s.organization_id and stage_code=s.stage_code and active
 order by policy_version desc limit 1;

 if v_policy.id is not null then
  select * into v_eval
  from studio.stage_gate_evaluations
  where pipeline_stage_id=s.id and policy_id=v_policy.id and attempt_number=s.attempts
  order by created_at desc limit 1;

  if v_eval.id is null then
    raise exception 'RAG quality gate evaluation required for stage % attempt %',s.stage_code,s.attempts;
  end if;

  if v_eval.decision <> 'pass'
     or v_eval.overall_score < v_policy.minimum_overall_score
     or jsonb_array_length(v_eval.hard_failures)>0 then
   update studio.pipeline_stages
   set status=case when v_eval.decision='human_review' then 'awaiting_approval' else 'queued' end,
       output=p_output,error_code='QUALITY_GATE_BLOCKED',
       error_message='Stage did not satisfy RAG quality policy',
       claimed_by=null,claimed_at=null,heartbeat_at=null,
       available_at=now()+interval '1 minute',updated_at=now()
   where id=s.id;

   insert into studio.pipeline_events(
     organization_id,pipeline_run_id,pipeline_stage_id,event_type,from_status,to_status,
     actor_type,actor_ref,detail
   ) values(
     s.organization_id,s.pipeline_run_id,s.id,'quality_gate_blocked','running',
     case when v_eval.decision='human_review' then 'awaiting_approval' else 'queued' end,
     'gate',v_eval.evaluated_by,
     jsonb_build_object('evaluation_id',v_eval.id,'attempt',s.attempts,'score',v_eval.overall_score,'decision',v_eval.decision,'remediation',v_eval.remediation_plan)
   );

   return jsonb_build_object('stage_id',s.id,'status','blocked','evaluation_id',v_eval.id,'attempt',s.attempts,'decision',v_eval.decision);
  end if;
 end if;

 update studio.pipeline_stages
 set status='completed',output=coalesce(p_output,'{}'),completed_at=now(),heartbeat_at=now(),updated_at=now()
 where id=s.id;

 insert into studio.pipeline_events(
   organization_id,pipeline_run_id,pipeline_stage_id,event_type,from_status,to_status,
   actor_type,actor_ref,detail
 ) values(
   s.organization_id,s.pipeline_run_id,s.id,'stage_completed','running','completed',
   'worker',p_worker_id,jsonb_build_object('attempt',s.attempts,'output',p_output)
 );

 perform system.advance_media_assembly_lines();
 return jsonb_build_object('stage_id',s.id,'pipeline_run_id',s.pipeline_run_id,'status','completed','attempt',s.attempts);
end
$function$
;

CREATE OR REPLACE FUNCTION system.inject_production_intelligence_into_pipeline_stage()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_pi jsonb;
begin
  if new.status='completed' and new.stage_code='intake' and old.status is distinct from new.status then
    select context_snapshot->'production_intelligence' into v_pi
    from studio.pipeline_runs where id=new.pipeline_run_id;
    if v_pi is not null and v_pi <> '{}'::jsonb then
      new.output := coalesce(new.output,'{}'::jsonb) || jsonb_build_object('production_intelligence',v_pi);
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION system.persist_edit_spec_after_plan()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_episode uuid;
  v_org uuid;
  v_spec jsonb;
  v_version integer;
begin
  if new.stage_code='build_edit_plan' and new.status='completed' and old.status is distinct from new.status then
    select a.episode_id,a.organization_id into v_episode,v_org from studio.assets a where a.id=new.source_asset_id;
    v_spec:=coalesce(new.output->'edit_plan','{}'::jsonb);
    if v_episode is not null and v_spec<>'{}'::jsonb then
      select coalesce(max(version),0)+1 into v_version from studio.edit_decision_specs where episode_id=v_episode;
      insert into studio.edit_decision_specs(organization_id,episode_id,version,status,decisions,source_manifest,story_notes,qc_requirements)
      values(v_org,v_episode,v_version,'draft',v_spec,
        jsonb_build_object('source_asset_id',new.source_asset_id,'pipeline_run_id',new.pipeline_run_id),
        jsonb_build_object('production_intelligence',(select context_snapshot->'production_intelligence' from studio.pipeline_runs where id=new.pipeline_run_id),'capture_qc',(select context_snapshot->'capture_qc' from studio.pipeline_runs where id=new.pipeline_run_id)),
        jsonb_build_object('must_preserve_package_promise',true,'must_not_invent_uncaptured_material',true,'human_final_qc_required',true));
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION system.recover_media_jobs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare recovered int:=0; failed_final int:=0;
begin
  update studio.media_jobs set status='queued',claimed_by=null,claimed_at=null,available_at=now()+interval '2 minutes',attempts=attempts+1,updated_at=now()
  where status='running' and claimed_at < now()-interval '20 minutes' and attempts < max_attempts;
  get diagnostics recovered = row_count;
  update studio.media_jobs set status='failed',error_code='MAX_ATTEMPTS',error_message='Worker lease expired after maximum attempts',updated_at=now()
  where status='running' and claimed_at < now()-interval '20 minutes' and attempts >= max_attempts;
  get diagnostics failed_final = row_count;
  return jsonb_build_object('recovered',recovered,'failed_final',failed_final,'at',now());
end $function$
;

CREATE OR REPLACE FUNCTION system.recover_pipeline_stages()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_retry int:=0;v_failed int:=0;
begin
  update studio.pipeline_stages set status='queued',claimed_by=null,claimed_at=null,heartbeat_at=null,available_at=now()+interval '2 minutes',updated_at=now()
  where status='running' and coalesce(heartbeat_at,claimed_at)<now()-interval '15 minutes' and attempts<max_attempts;
  get diagnostics v_retry=row_count;
  update studio.pipeline_stages set status='failed',error_code='LEASE_EXPIRED',error_message='Worker stopped responding',updated_at=now()
  where status='running' and coalesce(heartbeat_at,claimed_at)<now()-interval '15 minutes' and attempts>=max_attempts;
  get diagnostics v_failed=row_count;
  perform system.advance_media_assembly_lines();
  return jsonb_build_object('retried',v_retry,'failed',v_failed,'at',now());
end $function$
;

CREATE OR REPLACE FUNCTION system.run_media_acceptance(p_organization_id uuid, p_episode_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'system', 'studio', 'knowledge', 'intelligence'
AS $function$
declare
  v_episode_id uuid;
  v_results jsonb;
  v_passed int;
  v_failed int;
  v_total int;
  v_run_id uuid;
begin
  v_episode_id := p_episode_id;
  if v_episode_id is null then
    select e.id into v_episode_id
    from studio.episodes e
    where e.organization_id=p_organization_id
      and e.metadata->>'source'='ask_dre'
    order by e.created_at desc
    limit 1;
  end if;

  with latest_script as (
    select s.* from studio.scripts s
    where s.episode_id=v_episode_id
    order by s.version desc,s.created_at desc limit 1
  ), required(platform) as (
    values ('youtube'),('youtube_shorts'),('tiktok'),('instagram'),('facebook'),('linkedin')
  ), raw_checks as (
    select 1 n,'knowledge_documents_exist' test,(select count(*)>0 from knowledge.documents d where d.organization_id=p_organization_id) pass,(select count(*)::text from knowledge.documents d where d.organization_id=p_organization_id) detail
    union all select 2,'knowledge_chunks_exist',(select count(*)>0 from knowledge.document_chunks c join knowledge.documents d on d.id=c.document_id where d.organization_id=p_organization_id),(select count(*)::text from knowledge.document_chunks c join knowledge.documents d on d.id=c.document_id where d.organization_id=p_organization_id)
    union all select 3,'all_org_chunks_embedded',(select count(*) filter(where c.embedding is null)=0 from knowledge.document_chunks c join knowledge.documents d on d.id=c.document_id where d.organization_id=p_organization_id),(select concat(count(*) filter(where c.embedding is not null),'/',count(*)) from knowledge.document_chunks c join knowledge.documents d on d.id=c.document_id where d.organization_id=p_organization_id)
    union all select 4,'hybrid_search_function_exists',exists(select 1 from pg_proc p where p.proname='dre_hybrid_search'),'dre_hybrid_search'
    union all select 5,'ask_dre_gate_active',exists(select 1 from studio.stage_gate_policies sg where sg.organization_id=p_organization_id and sg.stage_code='ask_dre_generate' and sg.active),coalesce((select sg.minimum_overall_score::text from studio.stage_gate_policies sg where sg.organization_id=p_organization_id and sg.stage_code='ask_dre_generate' and sg.active order by sg.policy_version desc limit 1),'missing')
    union all select 6,'target_episode_exists',v_episode_id is not null,coalesce(v_episode_id::text,'missing')
    union all select 7,'target_has_script',exists(select 1 from studio.scripts s where s.episode_id=v_episode_id),(select count(*)::text from studio.scripts s where s.episode_id=v_episode_id)
    union all select 8,'target_has_exactly_six_required_platforms',(select count(distinct dp.platform)=6 and count(*)=6 and count(*) filter(where dp.platform in(select platform from required))=6 from studio.distribution_packages dp where dp.episode_id=v_episode_id),(select coalesce(string_agg(dp.platform,',' order by dp.platform),'missing') from studio.distribution_packages dp where dp.episode_id=v_episode_id)
    union all select 9,'target_no_duplicate_platforms',not exists(select 1 from studio.distribution_packages dp where dp.episode_id=v_episode_id group by dp.platform having count(*)>1),'no duplicate episode/platform rows'
    union all select 10,'youtube_title_100_or_less',coalesce((select length(dp.title)<=100 and length(trim(dp.title))>0 from studio.distribution_packages dp where dp.episode_id=v_episode_id and dp.platform='youtube' limit 1),false),coalesce((select length(dp.title)::text from studio.distribution_packages dp where dp.episode_id=v_episode_id and dp.platform='youtube' limit 1),'missing')
    union all select 11,'shorts_title_100_or_less',coalesce((select length(dp.title)<=100 and length(trim(dp.title))>0 from studio.distribution_packages dp where dp.episode_id=v_episode_id and dp.platform='youtube_shorts' limit 1),false),coalesce((select length(dp.title)::text from studio.distribution_packages dp where dp.episode_id=v_episode_id and dp.platform='youtube_shorts' limit 1),'missing')
    union all select 12,'all_six_have_copy',not exists(select 1 from required r where not exists(select 1 from studio.distribution_packages dp where dp.episode_id=v_episode_id and dp.platform=r.platform and length(trim(coalesce(dp.caption,'')))+length(trim(coalesce(dp.description,'')))>0)),'caption or description per platform'
    union all select 13,'script_no_object_object',coalesce((select position('[object Object]' in ls.content)=0 from latest_script ls),false),'latest script'
    union all select 14,'metadata_no_object_object',coalesce((select position('[object Object]' in e.metadata::text)=0 from studio.episodes e where e.id=v_episode_id),false),'episode metadata'
    union all select 15,'script_no_em_dash',coalesce((select position(',' in ls.content)=0 from latest_script ls),false),'owner-authored copy'
    union all select 16,'script_no_banned_population_phrases',coalesce((select lower(ls.content) !~ '(most people|a lot of people|everybody|everyone|people always|business owners usually|creators always)' from latest_script ls),false),'banned population language'
    union all select 17,'target_not_marked_filmed_without_confirmation',coalesce((select not coalesce((e.metadata->>'filmed')::boolean,false) from studio.episodes e where e.id=v_episode_id),false),coalesce((select e.metadata->>'filmed' from studio.episodes e where e.id=v_episode_id),'false')
    union all select 18,'target_source_ask_dre',coalesce((select e.metadata->>'source'='ask_dre' from studio.episodes e where e.id=v_episode_id),false),coalesce((select e.metadata->>'source' from studio.episodes e where e.id=v_episode_id),'missing')
    union all select 19,'target_status_ready',coalesce((select e.status::text='ready' from studio.episodes e where e.id=v_episode_id),false),coalesce((select e.status::text from studio.episodes e where e.id=v_episode_id),'missing')
    union all select 20,'global_no_duplicate_distribution_platforms',not exists(select 1 from studio.distribution_packages dp where dp.organization_id=p_organization_id group by dp.episode_id,dp.platform having count(*)>1),coalesce((select count(*)::text from (select dp.episode_id,dp.platform from studio.distribution_packages dp where dp.organization_id=p_organization_id group by dp.episode_id,dp.platform having count(*)>1)x),'0')
    union all select 21,'ready_ask_dre_episodes_have_scripts',not exists(select 1 from studio.episodes e where e.organization_id=p_organization_id and e.status::text='ready' and e.metadata->>'source'='ask_dre' and not exists(select 1 from studio.scripts s where s.episode_id=e.id)),coalesce((select count(*)::text from studio.episodes e where e.organization_id=p_organization_id and e.status::text='ready' and e.metadata->>'source'='ask_dre' and not exists(select 1 from studio.scripts s where s.episode_id=e.id)),'0')
    union all select 22,'studio_rpc_exists',exists(select 1 from pg_proc p where p.proname='dre_content_studio_episode'),'dre_content_studio_episode'
    union all select 23,'teach_rpc_exists',exists(select 1 from pg_proc p where p.proname='dre_content_teach'),'dre_content_teach'
    union all select 24,'preference_signals_exist',exists(select 1 from intelligence.preference_signals ps where ps.organization_id=p_organization_id),(select count(*)::text from intelligence.preference_signals ps where ps.organization_id=p_organization_id)
    union all select 25,'population_rule_canonical_and_embedded',exists(select 1 from knowledge.document_chunks c join knowledge.documents d on d.id=c.document_id where d.organization_id=p_organization_id and d.authority::text='canonical' and c.embedding is not null and (lower(c.heading_path::text) like '%population%' or lower(c.heading_path::text) like '%generalization%') and (lower(c.content) like '%most people%' or lower(c.content) like '%a lot of people%')),'canonical embedded rule'
    union all select 26,'target_has_production_plans',coalesce((select jsonb_array_length(coalesce(e.metadata->'director_notes','[]'))>0 and jsonb_array_length(coalesce(e.metadata->'board','[]'))>0 and jsonb_array_length(coalesce(e.metadata->'shots','[]'))>0 and jsonb_array_length(coalesce(e.metadata->'edit','[]'))>0 and jsonb_array_length(coalesce(e.metadata->'clip_candidates','[]'))>0 from studio.episodes e where e.id=v_episode_id),false),'director+board+shots+edit+clips'
    union all select 27,'target_has_thumbnail_package',coalesce((select e.metadata ? 'thumbnail_package' and e.metadata->'thumbnail_package' is not null and length(trim(coalesce(e.metadata->'thumbnail_package'->>'composition','')))>0 and length(trim(coalesce(e.metadata->'thumbnail_package'->>'ready_to_generate_image_prompt','')))>0 from studio.episodes e where e.id=v_episode_id),false),'thumbnail package'
  ), checks as (
    select n,test,pass,detail from raw_checks order by n
  )
  select jsonb_agg(jsonb_build_object('n',n,'test',test,'pass',pass,'detail',detail) order by n),
         count(*) filter(where pass),count(*) filter(where not pass),count(*)
  into v_results,v_passed,v_failed,v_total
  from checks;

  insert into system.acceptance_runs(organization_id,episode_id,suite_code,status,passed_count,failed_count,total_count,results,metadata)
  values(p_organization_id,v_episode_id,'dre_media_core_v1',case when v_failed=0 then 'pass' else 'fail' end,v_passed,v_failed,v_total,v_results,jsonb_build_object('generator_target_version',6))
  returning id into v_run_id;

  return jsonb_build_object('run_id',v_run_id,'status',case when v_failed=0 then 'pass' else 'fail' end,'passed',v_passed,'failed',v_failed,'total',v_total,'episode_id',v_episode_id,'results',v_results);
end;
$function$
;

CREATE OR REPLACE FUNCTION system.start_media_assembly_line(p_organization_id uuid, p_asset_id uuid, p_created_by uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_run uuid; v_stages text[][] := array[
  array['intake','media'],array['probe','media'],array['transcribe','speech'],array['analyze_structure','intelligence'],
  array['retrieve_context','intelligence'],array['build_edit_plan','intelligence'],array['render_master','media'],
  array['generate_clips','media'],array['generate_captions','media'],array['package_variants','media'],
  array['quality_control','intelligence'],array['human_review','approval'],array['publish','distribution'],array['learn','intelligence']
]; i int;
begin
  if not exists(select 1 from studio.assets where id=p_asset_id and organization_id=p_organization_id) then raise exception 'Asset not found'; end if;
  insert into studio.pipeline_runs(organization_id,source_asset_id,status,current_stage,created_by)
  values(p_organization_id,p_asset_id,'queued','intake',p_created_by)
  on conflict(organization_id,source_asset_id) do update set updated_at=now()
  returning id into v_run;
  for i in 1..array_length(v_stages,1) loop
    insert into studio.pipeline_stages(organization_id,pipeline_run_id,source_asset_id,stage_order,stage_code,worker_class,status,depends_on_stage_code,input)
    values(p_organization_id,v_run,p_asset_id,i,v_stages[i][1],v_stages[i][2],case when i=1 then 'queued' else 'blocked' end,
      case when i=1 then null else v_stages[i-1][1] end,jsonb_build_object('asset_id',p_asset_id))
    on conflict(pipeline_run_id,stage_code) do nothing;
  end loop;
  insert into studio.pipeline_events(organization_id,pipeline_run_id,event_type,to_status,detail)
  values(p_organization_id,v_run,'pipeline_created','queued',jsonb_build_object('asset_id',p_asset_id));
  return v_run;
end $function$
;

CREATE OR REPLACE FUNCTION system.start_media_assembly_line(p_organization_id uuid, p_asset_id uuid, p_created_by uuid, p_context jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_run uuid;
  v_episode uuid;
  v_production_intelligence jsonb := '{}'::jsonb;
  v_owner_goal text;
  v_editor_goal text;
begin
  v_run := system.start_media_assembly_line(p_organization_id,p_asset_id,p_created_by);

  select a.episode_id into v_episode from studio.assets a where a.id=p_asset_id and a.organization_id=p_organization_id;
  if v_episode is not null then
    select jsonb_build_object(
      'episode_id',e.id,
      'episode_code',e.episode_code,
      'working_title',e.working_title,
      'production_state',e.production_state,
      'viewer_promise',e.viewer_promise,
      'opening',e.opening,
      'stakes',e.stakes,
      'central_question',e.central_question,
      'story_arc',e.story_arc,
      'locked_package',coalesce((select to_jsonb(p) from studio.packaging_hypotheses p where p.episode_id=e.id order by p.selected desc,p.score desc nulls last,p.created_at limit 1),'{}'::jsonb),
      'creative_gate',coalesce((select to_jsonb(c) from studio.creative_evaluations c where c.episode_id=e.id order by c.created_at desc limit 1),'{}'::jsonb),
      'actor_pack',coalesce(e.metadata->'actor_pack_v2','{}'::jsonb),
      'beats',coalesce((select jsonb_agg(jsonb_build_object('beat_number',b.beat_number,'beat_type',b.beat_type,'purpose',b.purpose,'spoken_content',b.spoken_content,'open_loop',b.open_loop,'payoff_for',b.payoff_for,'emotion_target',b.emotion_target,'visual_plan',b.visual_plan,'clip_candidate',b.clip_candidate) order by b.beat_number) from studio.episode_beats b where b.episode_id=e.id),'[]'::jsonb),
      'requirements',coalesce((select jsonb_agg(jsonb_build_object('type',r.requirement_type,'key',r.requirement_key,'description',r.description,'required',r.required,'status',r.status) order by r.requirement_type,r.requirement_key) from studio.production_requirements r where r.episode_id=e.id),'[]'::jsonb)
    ) into v_production_intelligence
    from studio.episodes e where e.id=v_episode;
  end if;

  v_owner_goal:=nullif(trim(coalesce(p_context->>'goal','')),'');
  v_editor_goal:=coalesce(v_owner_goal,'Edit this video to fulfill the approved creative package and preserve the intended story.')
    || E'\n\nLOCKED PRODUCTION INTELLIGENCE. Treat this as the preproduction contract. Preserve the package promise and opening. Use the planned beats, visual intent, B-roll, clip moments and production requirements when the captured footage supports them. Never invent uncaptured material. If capture_qc says a beat is missing, do not fabricate a replacement.\n'
    || coalesce(v_production_intelligence,'{}'::jsonb)::text;

  update studio.pipeline_runs
  set context_snapshot=coalesce(context_snapshot,'{}'::jsonb)
      || coalesce(p_context,'{}'::jsonb)
      || jsonb_build_object(
          'owner_goal',v_owner_goal,
          'goal',v_editor_goal,
          'production_intelligence',coalesce(v_production_intelligence,'{}'::jsonb)
        ),
      updated_at=now()
  where id=v_run;
  return v_run;
end $function$
;

CREATE OR REPLACE FUNCTION system.sync_episode_recorded_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.status::text='completed'
     and coalesce((new.metadata->>'filmed')::boolean,false)=true
     and (old.status::text is distinct from new.status::text or coalesce((old.metadata->>'filmed')::boolean,false)=false)
     and coalesce(new.production_state,'insight') not in ('recorded','ingested','edit_locked','qc_locked','scheduled','published','learning_locked') then
    new.production_state := 'recorded';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION system.sync_pipeline_stage_to_production_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_episode uuid;
  v_org uuid;
  v_from text;
  v_to text;
begin
  if new.status<>'completed' or old.status is not distinct from new.status then return new; end if;
  select a.episode_id,a.organization_id into v_episode,v_org from studio.assets a where a.id=new.source_asset_id;
  if v_episode is null then return new; end if;

  v_to:=case new.stage_code
    when 'quality_control' then 'qc_locked'
    when 'publish' then 'published'
    when 'learn' then 'learning_locked'
    else null end;
  if v_to is null then return new; end if;

  select production_state into v_from from studio.episodes where id=v_episode;
  if v_from is distinct from v_to then
    update studio.episodes set production_state=v_to,updated_at=now() where id=v_episode;
    insert into studio.content_state_events(organization_id,episode_id,from_state,to_state,trigger_type,actor_type,reason,snapshot)
    values(v_org,v_episode,v_from,v_to,'pipeline_stage','system',format('Pipeline stage %s completed',new.stage_code),jsonb_build_object('pipeline_run_id',new.pipeline_run_id,'stage_id',new.id,'stage_code',new.stage_code));
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION system.sync_raw_asset_ingested_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_from text;
begin
  if new.episode_id is not null and new.asset_type='raw_video' and new.status::text='ready' and old.status::text is distinct from new.status::text then
    select production_state into v_from from studio.episodes where id=new.episode_id;
    if v_from in ('recorded','shoot_ready') then
      update studio.episodes set production_state='ingested',updated_at=now() where id=new.episode_id;
      insert into studio.content_state_events(organization_id,episode_id,from_state,to_state,trigger_type,actor_type,reason,snapshot)
      values(new.organization_id,new.episode_id,v_from,'ingested','asset_ingest','system','Raw footage bytes confirmed in storage',jsonb_build_object('asset_id',new.id,'file_name',new.file_name));
    end if;
  end if;
  return new;
end $function$
;

