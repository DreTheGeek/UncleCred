-- Let signed-in org members read the private buckets.
--
-- storage.objects had no policies at all, so canon and renders were reachable only by
-- service_role. The studio app runs on the anon key with the user's session by design, so it
-- could not show Boss the character candidates it had just generated for him to pick from.
--
-- SELECT only, deliberately. Uploads stay server side under service_role; nothing in the
-- browser needs write access to canon, and least privilege is the whole point of RLS.
--
-- FOLLOW UP FOR MULTI TENANCY: this grants any active member of any organization read access
-- to both buckets, which is correct today because there is exactly one organization and one
-- universe. Object paths are keyed by character code (uncle_cred/face_master_001.jpg), not by
-- organization, so there is nothing in the path to scope on yet. When universe two lands
-- (DECISIONS D2, Year One migrating in), paths must gain an organization prefix and this
-- policy must scope to it, or one tenant will read another tenant's canon.

create policy "org members read canon and renders"
on storage.objects
for select
to authenticated
using (
  bucket_id in ('canon', 'renders')
  and exists (
    select 1
    from platform.organization_members om
    where om.user_id = (select auth.uid())
      and om.status = 'active'
  )
);
