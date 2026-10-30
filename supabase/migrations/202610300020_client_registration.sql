alter table public.clients add column reference_postal_code text;
alter table public.clients add column facebook text;
alter table public.clients add column instagram text;
update public.clients set facebook=social_profiles->>'facebook',instagram=social_profiles->>'instagram' where social_profiles<>'{}'::jsonb;
alter table public.clients add constraint reference_postal_code_format check(reference_postal_code is null or reference_postal_code='' or reference_postal_code ~ '^[0-9]{8}$');
alter table public.client_documents drop constraint client_documents_document_kind_check;
alter table public.client_documents add constraint client_documents_document_kind_check check(document_kind in ('identity','selfie','residence','professional','income','pix','other','business','house_front','business_front'));
