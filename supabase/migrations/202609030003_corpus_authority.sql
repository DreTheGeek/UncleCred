-- Downgrade internal operations SOPs so viewer facing teaching outranks them.
--
-- The credit knowledge base was imported at a uniform authority of 'verified', which made an
-- internal dispute-team checklist rank equal to a lesson written for a viewer. Asked "how do
-- I dispute an error on my credit report", three of the top five passages were team SOPs:
-- [Bel] Round 1 Process, [Bel] R1 Review + Round 2 Process, [Empress] After KickOff Round 1
-- Ready SOP. Grounding would pass on those and the episode would still be wrong, because
-- Uncle Cred cannot teach a viewer from Kay's round-4 checklist.
--
-- The corpus labels itself, so this is not a guess. Documents carry
-- metadata.src_metadata.source and metadata.tags:
--   drive_sops    25 docs  2,253 chunks  tags include 'sop'   internal process
--   skool_course  95 docs  3,615 chunks                       course teaching
--   youtube       47 docs  1,556 chunks                       public teaching
--
-- 'working' rather than 'historical' or 'unverified': these documents are current and true,
-- they are simply the wrong register for a viewer. knowledge.match_chunks weights canonical
-- 1.30, verified 1.15, working 1.00, so this demotes without burying. A dispute-process
-- question with no teaching material available will still surface them.
--
-- Reversible in one statement: set authority back to 'verified' where the same predicate holds.

update knowledge.documents
set authority = 'working', updated_at = now()
where metadata->'src_metadata'->>'source' = 'drive_sops'
  and authority::text = 'verified';
