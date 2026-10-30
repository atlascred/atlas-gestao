drop policy if exists client_docs_storage_read on storage.objects;
create policy client_docs_storage_read on storage.objects for select to authenticated using(bucket_id='client-documents' and public.has_tenant_permission((storage.foldername(name))[1]::uuid,'documents.read'));
drop policy if exists client_docs_storage_insert on storage.objects;
create policy client_docs_storage_insert on storage.objects for insert to authenticated with check(bucket_id='client-documents' and public.has_tenant_permission((storage.foldername(name))[1]::uuid,'documents.upload'));
