insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('tenant-branding','tenant-branding',false,1048576,array['image/png','image/jpeg']) on conflict(id) do nothing;
create policy branding_read on storage.objects for select to authenticated using(bucket_id='tenant-branding' and public.is_tenant_member((storage.foldername(name))[1]::uuid));
create policy branding_insert on storage.objects for insert to authenticated with check(bucket_id='tenant-branding' and public.has_tenant_role((storage.foldername(name))[1]::uuid,array['tenant_admin']::public.member_role[]));
create policy branding_delete on storage.objects for delete to authenticated using(bucket_id='tenant-branding' and public.has_tenant_role((storage.foldername(name))[1]::uuid,array['tenant_admin']::public.member_role[]));
create function public.update_tenant_settings(p_tenant uuid,p_name text,p_message text,p_settings jsonb) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.has_tenant_role(p_tenant,array['tenant_admin']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501';end if;
 if length(trim(p_name)) not between 2 and 140 or length(p_message)>1000 or jsonb_typeof(p_settings)<>'object' or length(p_settings::text)>20000 then raise exception 'invalid_settings';end if;
 update public.tenants set name=trim(p_name),updated_at=now() where id=p_tenant;
 insert into public.tenant_settings(tenant_id,collection_message,settings) values(p_tenant,p_message,p_settings) on conflict(tenant_id) do update set collection_message=excluded.collection_message,settings=excluded.settings,updated_at=now();
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id) values(p_tenant,auth.uid(),'settings.updated','tenant_settings',p_tenant);
end $$;
revoke all on function public.update_tenant_settings(uuid,text,text,jsonb) from public;
grant execute on function public.update_tenant_settings(uuid,text,text,jsonb) to authenticated;
