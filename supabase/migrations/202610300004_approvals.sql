alter table public.tenant_applications add column if not exists tenant_id uuid references public.tenants(id) on delete set null;
create or replace function public.reject_tenant_application(p_application uuid,p_reason text) returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_master_admin() then raise exception 'not_authorized' using errcode='42501';end if;if length(trim(coalesce(p_reason,'')))<3 then raise exception 'reason_required' using errcode='22023';end if;update public.tenant_applications set status='rejected',reviewed_at=now(),reviewed_by=auth.uid(),review_note=trim(p_reason) where id=p_application and status='pending';if not found then raise exception 'application_not_pending' using errcode='22023';end if;insert into public.audit_log(actor_id,action,entity,entity_id,metadata) values(auth.uid(),'tenant.rejected','tenant_applications',p_application,jsonb_build_object('reason',trim(p_reason)));end $$;
create or replace function public.approve_tenant_application(p_application uuid,p_user uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_app public.tenant_applications%rowtype;v_tenant uuid:=gen_random_uuid();
begin if not public.is_master_admin() then raise exception 'not_authorized' using errcode='42501';end if;select * into v_app from public.tenant_applications where id=p_application and status='pending' for update;if not found then raise exception 'application_not_pending' using errcode='22023';end if;if not exists(select 1 from auth.users where id=p_user and lower(email)=lower(v_app.email)) then raise exception 'auth_user_not_found' using errcode='22023';end if;
 insert into public.tenants(id,name,state,requested_by,approved_at,approved_by) values(v_tenant,v_app.company_name,'approved',p_user,now(),auth.uid());
 insert into public.memberships(tenant_id,user_id,role,active) values(v_tenant,p_user,'tenant_admin',true);
 insert into public.profiles(id,full_name) values(p_user,v_app.contact_name) on conflict(id) do update set full_name=excluded.full_name;
 insert into public.tenant_settings(tenant_id) values(v_tenant);
 update public.tenant_applications set status='approved',reviewed_at=now(),reviewed_by=auth.uid(),tenant_id=v_tenant where id=p_application;
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id,metadata) values(v_tenant,auth.uid(),'tenant.approved','tenants',v_tenant,jsonb_build_object('application_id',p_application,'initial_admin',p_user));return v_tenant;
end $$;
revoke all on function public.reject_tenant_application(uuid,text) from public;
revoke all on function public.approve_tenant_application(uuid,uuid) from public;
grant execute on function public.reject_tenant_application(uuid,text) to authenticated;
grant execute on function public.approve_tenant_application(uuid,uuid) to authenticated;
