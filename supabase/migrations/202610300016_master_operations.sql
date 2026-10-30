-- Paginated directory reads Auth only after verifying the global administrator.
create function public.master_user_directory(p_page integer default 1,p_query text default '',p_role text default '',p_state text default '') returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;begin
 if not public.is_master_admin() then raise exception 'not_authorized' using errcode='42501';end if;
 with directory as (select u.id,u.email,u.created_at,coalesce(p.full_name,'') full_name,m.id membership_id,m.tenant_id,m.role,coalesce(m.active,false) active,coalesce(t.name,'—') tenant,coalesce(t.state::text,'sem empresa') "tenantState",exists(select 1 from public.global_admins g where g.user_id=u.id) "isMaster" from auth.users u left join public.profiles p on p.id=u.id left join public.memberships m on m.user_id=u.id left join public.tenants t on t.id=m.tenant_id), filtered as (select * from directory where (coalesce(p_query,'')='' or concat_ws(' ',email,full_name,tenant) ilike '%'||left(p_query,100)||'%') and (coalesce(p_role,'')='' or role::text=p_role) and (coalesce(p_state,'')='' or "tenantState"=p_state)), paged as (select * from filtered order by created_at desc,id,membership_id limit 20 offset (greatest(1,least(p_page,100000))-1)*20)
 select jsonb_build_object('data',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]'::jsonb),'count',(select count(*) from filtered),'page',greatest(1,p_page)) into result;return result;
end $$;
revoke all on function public.master_user_directory(integer,text,text,text) from public;
grant execute on function public.master_user_directory(integer,text,text,text) to authenticated;
create function public.set_tenant_state(p_tenant uuid,p_state public.tenant_state) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_master_admin() then raise exception 'not_authorized' using errcode='42501';end if;
 if p_state not in ('approved','suspended') then raise exception 'invalid_state';end if;
 update public.tenants set state=p_state,suspended_at=case when p_state='suspended' then now() end,suspended_by=case when p_state='suspended' then auth.uid() end,updated_at=now() where id=p_tenant and state=case when p_state='suspended' then 'approved'::public.tenant_state else 'suspended'::public.tenant_state end;
 if not found then raise exception 'state_conflict';end if;
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id) values(p_tenant,auth.uid(),'tenant.'||p_state::text,'tenants',p_tenant);
end $$;
revoke all on function public.set_tenant_state(uuid,public.tenant_state) from public;
grant execute on function public.set_tenant_state(uuid,public.tenant_state) to authenticated;
