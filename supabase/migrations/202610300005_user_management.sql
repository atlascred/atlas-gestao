create policy profile_tenant_admin_read on public.profiles for select to authenticated using(exists(select 1 from public.memberships m where m.user_id=profiles.id and m.active and public.has_tenant_role(m.tenant_id,array['master_admin','tenant_admin']::public.member_role[])));
revoke insert,update,delete on public.memberships from anon,authenticated;
