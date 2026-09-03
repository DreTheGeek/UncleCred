-- Fix: four bigint event tables lost "generated always as identity" somewhere in the port
-- from laseanpickens. Their id column is "bigint not null" with no default and no identity,
-- so every insert fails with 23502 null value in column "id".
--
-- Found 2026-09-03 during the Phase 01 pipeline proof. system.start_media_assembly_line
-- creates the run and the 14 stages, then inserts one studio.pipeline_events row and dies,
-- which rolls the whole function back. Net effect: the media assembly line cannot be started
-- at all, and system.complete_pipeline_stage and system.advance_media_assembly_lines have the
-- same failure on their pipeline_events writes.
--
-- system.system_events is unaffected. It was written fresh in 202609020010 and already
-- declares "id bigint generated always as identity primary key".
--
-- All four tables were verified empty (0 rows) on 2026-09-03 before this ran, so an identity
-- starting at 1 cannot collide with existing ids. If any of them is non-empty when this is
-- applied, set the sequence past the max id afterward, for example:
--   select setval(pg_get_serial_sequence('studio.pipeline_events','id'),
--                 (select coalesce(max(id),0)+1 from studio.pipeline_events), false);

alter table studio.pipeline_events          alter column id add generated always as identity;
alter table studio.content_lifecycle_events alter column id add generated always as identity;
alter table system.automation_events        alter column id add generated always as identity;
alter table system.workflow_events          alter column id add generated always as identity;
