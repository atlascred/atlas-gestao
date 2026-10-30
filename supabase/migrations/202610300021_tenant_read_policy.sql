-- A tenant member must be able to resolve its own approved tenant row.
-- Use the security-definer membership predicate to avoid policy recursion.
drop policy if exists tenants_read on public.tenants;
create policy tenants_read on public.tenants
for select to authenticated
using (public.is_master_admin() or public.is_tenant_member(id));
