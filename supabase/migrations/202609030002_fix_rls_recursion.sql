-- Fix: infinite recursion in RLS, which broke every authenticated read in the product.
--
-- platform.organization_members carries owner_select with qual is_org_member(organization_id).
-- platform.is_org_member queries platform.organization_members. It was SECURITY INVOKER, so
-- that inner query was itself subject to the policy, which called is_org_member again:
--
--   select from organization_members
--     -> policy owner_select -> is_org_member()
--       -> select from organization_members
--         -> policy owner_select -> is_org_member()  ... until the stack ran out
--
-- Symptom: ERROR 54001 stack depth limit exceeded on any authenticated query, on any table,
-- because all 436 owner_* policies call is_org_member and every call reaches this table.
-- Found 2026-09-03 when the first real login showed the "not in the org yet" state despite a
-- correct, active owner row existing in platform.organization_members.
--
-- SECURITY DEFINER is the fix and is the standard Supabase pattern for a membership predicate:
-- the function must read the membership table without that read being re-filtered by the
-- policy that depends on it. It is safe because the function takes no data out. It answers one
-- boolean about the *current* auth.uid() and nothing else, so it cannot be used to enumerate
-- other organizations or leak rows.
--
-- search_path stays pinned. A SECURITY DEFINER function with a mutable search_path is a
-- privilege escalation waiting to happen.

alter function platform.is_org_member(uuid) security definer;
alter function platform.is_org_member(uuid) set search_path = pg_catalog, auth, platform;

-- is_org_admin has the same shape and the same exposure through
-- "admins manage memberships" and "members read memberships" on the same table.
do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'platform' and p.proname = 'is_org_admin'
  ) then
    execute 'alter function platform.is_org_admin(uuid) security definer';
    execute 'alter function platform.is_org_admin(uuid) set search_path = pg_catalog, auth, platform';
  end if;
end $$;
