-- Generalized persistent story domain for Scene and future cinematic universes.
-- This migration creates only the schema boundary and privileges. Domain tables
-- land in later migrations after reconciliation with existing studio entities.

create schema if not exists story;

grant usage on schema story to anon, authenticated, service_role;
grant all on all tables in schema story to service_role;
grant all on all sequences in schema story to service_role;
grant all on all functions in schema story to service_role;
grant select, insert, update, delete on all tables in schema story to authenticated;
grant usage, select on all sequences in schema story to authenticated;
grant execute on all functions in schema story to authenticated;

alter default privileges in schema story grant all on tables to service_role;
alter default privileges in schema story grant all on sequences to service_role;
alter default privileges in schema story grant all on functions to service_role;
alter default privileges in schema story grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema story grant usage, select on sequences to authenticated;
alter default privileges in schema story grant execute on functions to authenticated;

comment on schema story is 'Generalized narrative state, canon, planning, and story-world memory for Scene-backed universes.';
