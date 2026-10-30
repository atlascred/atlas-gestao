-- Public company applications do not create an Auth user or grant operational access.
create table public.tenant_applications (
 id uuid primary key default gen_random_uuid(), company_name text not null check(length(trim(company_name)) between 2 and 140),
 contact_name text not null check(length(trim(contact_name)) between 2 and 140), email text not null check(length(email)<=254), phone text not null,
 message text, status public.tenant_state not null default 'pending' check(status in ('pending','approved','rejected')),
 submitted_at timestamptz not null default now(), reviewed_at timestamptz, reviewed_by uuid references auth.users(id) on delete set null, review_note text
);
create index tenant_applications_queue_idx on public.tenant_applications(status,submitted_at);
alter table public.tenant_applications enable row level security;
create policy application_public_submit on public.tenant_applications for insert to anon,authenticated with check(status='pending' and reviewed_at is null and reviewed_by is null);
create policy application_master_select on public.tenant_applications for select to authenticated using(public.is_master_admin());
create policy application_master_update on public.tenant_applications for update to authenticated using(public.is_master_admin()) with check(public.is_master_admin());

-- Master administrators are global; callers must still be authenticated.
create or replace function public.has_tenant_role(target uuid, allowed public.member_role[]) returns boolean language sql stable security definer set search_path=public as $$ select public.is_master_admin() or exists(select 1 from public.memberships m join public.tenants t on t.id=m.tenant_id where m.user_id=auth.uid() and m.tenant_id=target and m.active and m.role=any(allowed) and t.state='approved'); $$;
-- Prevent a collector from inferring financial/customer records outside assigned routes.
drop policy if exists client_read on public.clients;
create policy client_read on public.clients for select to authenticated using(
 public.has_tenant_role(tenant_id,array['master_admin','tenant_admin','employee']::public.member_role[]) or exists(select 1 from public.collector_assignments ca where ca.tenant_id=clients.tenant_id and ca.client_id=clients.id and ca.collector_user_id=auth.uid() and ca.active)
);
-- Tenant request and ordinary operators cannot read all membership/profile data.
drop policy if exists memberships_read on public.memberships;
create policy memberships_read on public.memberships for select to authenticated using(user_id=auth.uid() or public.has_tenant_role(tenant_id,array['master_admin','tenant_admin']::public.member_role[]));
-- Replace broad generic policies, which must never grant collectors finance access.
do $$ declare tab text; begin foreach tab in array array['client_documents','loans','loan_versions','installments','payments','payment_allocations','ledger_movements','expenses','daily_closures','audit_log'] loop
 execute format('drop policy if exists tenant_select on public.%I',tab);
 execute format('drop policy if exists tenant_insert on public.%I',tab);
 execute format('drop policy if exists tenant_update on public.%I',tab);
 if tab='audit_log' then execute format('create policy tenant_select on public.%I for select to authenticated using(public.has_tenant_role(tenant_id,array[''master_admin'',''tenant_admin'']::public.member_role[]))',tab);
 else execute format('create policy tenant_select on public.%I for select to authenticated using(public.has_tenant_role(tenant_id,array[''master_admin'',''tenant_admin'',''employee'']::public.member_role[]))',tab); end if;
 end loop; end $$;
drop policy if exists tenant_select on public.collector_assignments;
create policy assignment_read on public.collector_assignments for select to authenticated using(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin','employee']::public.member_role[]) or (collector_user_id=auth.uid() and active and public.is_tenant_member(tenant_id)));
drop policy if exists tenant_select on public.collector_visits;
create policy visit_read on public.collector_visits for select to authenticated using(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin','employee']::public.member_role[]) or (collector_user_id=auth.uid() and public.is_tenant_member(tenant_id)));
-- Finance mutations happen only through transaction-safe functions, never direct REST table writes.
do $$ declare tab text; begin foreach tab in array array['loans','loan_versions','installments','payments','payment_allocations','ledger_movements','expenses','daily_closures'] loop
 execute format('revoke insert,update,delete on public.%I from anon,authenticated',tab);
end loop; end $$;

create or replace function public.dashboard_summary(p_tenant uuid) returns jsonb language plpgsql security invoker set search_path=public as $$
declare v_today date:=(now() at time zone 'America/Sao_Paulo')::date; v_month date:=date_trunc('month',now() at time zone 'America/Sao_Paulo')::date; v_out jsonb;
begin
 if not public.has_tenant_role(p_tenant,array['master_admin','tenant_admin','employee']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501'; end if;
 select jsonb_build_object(
 'asOf',v_today,
 'clients',(select count(*) from public.clients c where c.tenant_id=p_tenant and c.active),
 'activeLoans',(select count(*) from public.loans l where l.tenant_id=p_tenant and l.state='active'),
 'principalActive',(select coalesce(sum(l.principal),0) from public.loans l where l.tenant_id=p_tenant and l.state='active'),
 'receivable',(select coalesce(sum(i.amount-i.paid_amount),0) from public.installments i where i.tenant_id=p_tenant and i.state in ('open','partial')),
 'cashBalance',(select coalesce(sum(m.amount*m.direction),0) from public.ledger_movements m where m.tenant_id=p_tenant),
 'cashInMonth',(select coalesce(sum(m.amount),0) from public.ledger_movements m where m.tenant_id=p_tenant and m.direction=1 and m.kind='payment' and (m.occurred_at at time zone 'America/Sao_Paulo')::date>=v_month),
 'cashOutMonth',(select coalesce(sum(m.amount),0) from public.ledger_movements m where m.tenant_id=p_tenant and m.direction=-1 and (m.occurred_at at time zone 'America/Sao_Paulo')::date>=v_month),
 'dueToday',(select coalesce(sum(i.amount-i.paid_amount),0) from public.installments i where i.tenant_id=p_tenant and i.due_date=v_today and i.state in ('open','partial')),
 'dueCount',(select count(*) from public.installments i where i.tenant_id=p_tenant and i.due_date=v_today and i.state in ('open','partial')),
 'overdue',(select coalesce(sum(i.amount-i.paid_amount),0) from public.installments i where i.tenant_id=p_tenant and i.due_date<v_today and i.state in ('open','partial')),
 'overdueCount',(select count(*) from public.installments i where i.tenant_id=p_tenant and i.due_date<v_today and i.state in ('open','partial'))
 ) into v_out; return v_out;
end $$;
revoke all on function public.dashboard_summary(uuid) from public;
grant execute on function public.dashboard_summary(uuid) to authenticated;

-- Client documents are private and only tenant operators can manage them.
create policy client_document_insert on public.client_documents for insert to authenticated with check(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin','employee']::public.member_role[]));
create policy client_document_update on public.client_documents for update to authenticated using(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin']::public.member_role[])) with check(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin']::public.member_role[]));
create policy client_document_delete on public.client_documents for delete to authenticated using(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin']::public.member_role[]));
-- Assignment changes are managerial; collectors may record visits only for their assigned clients.
drop policy if exists tenant_insert on public.collector_assignments;
drop policy if exists tenant_update on public.collector_assignments;
create policy assignment_manage on public.collector_assignments for all to authenticated using(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin','employee']::public.member_role[])) with check(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin','employee']::public.member_role[]));
drop policy if exists tenant_insert on public.collector_visits;
drop policy if exists tenant_update on public.collector_visits;
create policy visit_insert on public.collector_visits for insert to authenticated with check(
 (public.has_tenant_role(tenant_id,array['master_admin','tenant_admin','employee']::public.member_role[])) or
 (collector_user_id=auth.uid() and public.has_tenant_role(tenant_id,array['collector']::public.member_role[]) and exists(select 1 from public.collector_assignments ca where ca.tenant_id=collector_visits.tenant_id and ca.client_id=collector_visits.client_id and ca.collector_user_id=auth.uid() and ca.active))
);
create policy visit_manager_update on public.collector_visits for update to authenticated using(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin']::public.member_role[])) with check(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin']::public.member_role[]));
-- Allow a tenant operator to replace or remove objects in its private Storage folder.
create policy client_docs_storage_update on storage.objects for update to authenticated using(bucket_id='client-documents' and public.has_tenant_role((storage.foldername(name))[1]::uuid,array['master_admin','tenant_admin']::public.member_role[])) with check(bucket_id='client-documents' and public.has_tenant_role((storage.foldername(name))[1]::uuid,array['master_admin','tenant_admin']::public.member_role[]));
create policy client_docs_storage_delete on storage.objects for delete to authenticated using(bucket_id='client-documents' and public.has_tenant_role((storage.foldername(name))[1]::uuid,array['master_admin','tenant_admin']::public.member_role[]));
