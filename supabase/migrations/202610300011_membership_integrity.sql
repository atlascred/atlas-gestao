-- Serialize membership administration to preserve the last active administrator.
create or replace function public.update_tenant_membership(p_tenant uuid,p_membership uuid,p_active boolean,p_role public.member_role default null,p_permissions jsonb default null)
returns void language plpgsql security definer set search_path=public as $$
declare target public.memberships%rowtype; next_role public.member_role;
begin
 if not public.has_tenant_role(p_tenant,array['tenant_admin']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501'; end if;
 perform 1 from public.tenants where id=p_tenant for update;
 select * into target from public.memberships where id=p_membership and tenant_id=p_tenant for update;
 if not found then raise exception 'membership_not_found'; end if;
 next_role:=coalesce(p_role,target.role);
 if next_role='master_admin' then raise exception 'global_role_not_allowed'; end if;
 if target.role='tenant_admin' and target.active and (not p_active or next_role<>'tenant_admin') and not exists(select 1 from public.memberships where tenant_id=p_tenant and id<>p_membership and role='tenant_admin' and active) then raise exception 'last_admin'; end if;
 if p_permissions is not null and jsonb_typeof(p_permissions)<>'object' then raise exception 'invalid_permissions'; end if;
 update public.memberships set active=p_active,role=next_role,permissions=coalesce(p_permissions,permissions) where id=p_membership;
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id,metadata) values(p_tenant,auth.uid(),'membership.updated','memberships',p_membership,jsonb_build_object('active',p_active,'role',next_role));
end $$;
revoke all on function public.update_tenant_membership(uuid,uuid,boolean,public.member_role,jsonb) from public;
grant execute on function public.update_tenant_membership(uuid,uuid,boolean,public.member_role,jsonb) to authenticated;
