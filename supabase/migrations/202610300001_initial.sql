-- ATLAS initial schema. Apply with `supabase db push` after linking the project.
create extension if not exists pgcrypto;
create type public.tenant_state as enum ('pending','approved','rejected','suspended');
create type public.member_role as enum ('master_admin','tenant_admin','employee','collector');
create type public.loan_modality as enum ('daily','weekly','monthly');
create type public.loan_state as enum ('active','paid','suspended','cancelled');
create type public.installment_state as enum ('open','partial','paid','cancelled');
create type public.ledger_kind as enum ('loan_disbursement','payment','expense','adjustment','reversal');
create type public.visit_result as enum ('completed','absent','route_not_attended');

create table public.tenants (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 2 and 140),
 state public.tenant_state not null default 'pending', requested_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz, approved_by uuid references auth.users(id) on delete set null,
 rejected_at timestamptz, rejection_reason text, suspended_at timestamptz, suspended_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check ((state <> 'approved') or approved_at is not null)
);
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, full_name text not null check(length(trim(full_name)) between 1 and 140), phone text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.memberships (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade, role public.member_role not null default 'employee', active boolean not null default true,
 permissions jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(), unique(tenant_id,user_id), unique(id,tenant_id)
);
create table public.tenant_settings (tenant_id uuid primary key references public.tenants(id) on delete cascade, logo_path text, favicon_path text, collection_message text not null default 'Olá, {{nome}}. Sua parcela de {{valor}} vence em {{vencimento}}.', settings jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table public.clients (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 full_name text not null check(length(trim(full_name)) between 2 and 180), cpf text not null, address text, address_number text, neighborhood text, city text, postal_code text, whatsapp text, phone text,
 reference_name text, reference_relation text, reference_phone text, reference_address text, housing_status text, email text, social_profiles jsonb not null default '{}'::jsonb, notes text,
 active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(tenant_id,cpf), unique(id,tenant_id)
);
create index clients_tenant_name_idx on public.clients(tenant_id,lower(full_name));
create table public.client_documents (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null, client_id uuid not null, storage_path text not null unique,
 document_kind text not null check(document_kind in ('identity','selfie','residence','professional','income','pix','other')),
 original_name text not null, mime_type text not null, byte_size bigint not null check(byte_size between 1 and 10485760), uploaded_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(),
 foreign key(client_id,tenant_id) references public.clients(id,tenant_id) on delete cascade
);
create table public.loans (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null, client_id uuid not null, contract_number text not null,
 modality public.loan_modality not null, state public.loan_state not null default 'active', principal numeric(14,2) not null check(principal > 0), interest_percent numeric(7,3) not null check(interest_percent >= 0), interest_amount numeric(14,2) not null check(interest_amount >= 0), total_amount numeric(14,2) not null check(total_amount >= principal),
 installment_count integer not null check(installment_count > 0), installment_amount numeric(14,2) not null check(installment_amount > 0), start_date date not null, due_day integer, late_fee numeric(14,2) not null default 0 check(late_fee >= 0), late_fee_block_days integer not null default 2 check(late_fee_block_days > 0), include_sundays boolean not null default true, terms_snapshot jsonb not null default '{}'::jsonb,
 created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(tenant_id,contract_number), unique(id,tenant_id), foreign key(client_id,tenant_id) references public.clients(id,tenant_id) on delete restrict
);
create index loans_tenant_state_idx on public.loans(tenant_id,state,start_date desc);
create table public.loan_versions (id uuid primary key default gen_random_uuid(), tenant_id uuid not null, loan_id uuid not null, version integer not null check(version>0), terms jsonb not null, reason text not null, changed_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(), unique(loan_id,version), foreign key(loan_id,tenant_id) references public.loans(id,tenant_id) on delete cascade);
create table public.installments (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null, loan_id uuid not null, sequence integer not null check(sequence>0), due_date date not null, amount numeric(14,2) not null check(amount>0), paid_amount numeric(14,2) not null default 0 check(paid_amount>=0), state public.installment_state not null default 'open', created_at timestamptz not null default now(), unique(loan_id,sequence), unique(id,tenant_id), foreign key(loan_id,tenant_id) references public.loans(id,tenant_id) on delete cascade
);
create index installments_due_idx on public.installments(tenant_id,due_date,state);
create table public.payments (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null, loan_id uuid not null, amount numeric(14,2) not null check(amount>0), paid_at timestamptz not null default now(), method text not null default 'manual', note text, received_by uuid references auth.users(id) on delete set null, idempotency_key text not null, reversed_at timestamptz, created_at timestamptz not null default now(), unique(tenant_id,idempotency_key), unique(id,tenant_id), foreign key(loan_id,tenant_id) references public.loans(id,tenant_id) on delete restrict
);
create table public.payment_allocations (id uuid primary key default gen_random_uuid(), tenant_id uuid not null, payment_id uuid not null, installment_id uuid not null, amount numeric(14,2) not null check(amount>0), created_at timestamptz not null default now(), unique(payment_id,installment_id), foreign key(payment_id,tenant_id) references public.payments(id,tenant_id) on delete restrict, foreign key(installment_id,tenant_id) references public.installments(id,tenant_id) on delete restrict);
create table public.ledger_movements (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade, kind public.ledger_kind not null, amount numeric(14,2) not null check(amount>0), direction smallint not null check(direction in (-1,1)), occurred_at timestamptz not null default now(), reference_table text, reference_id uuid, description text not null, idempotency_key text not null, created_by uuid references auth.users(id) on delete set null, reversed_movement_id uuid references public.ledger_movements(id), created_at timestamptz not null default now(), unique(tenant_id,idempotency_key)
);
create index ledger_tenant_date_idx on public.ledger_movements(tenant_id,occurred_at desc);
create table public.expenses (id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade, category text not null, amount numeric(14,2) not null check(amount>0), expense_date date not null, note text, ledger_movement_id uuid not null unique references public.ledger_movements(id) on delete restrict, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create table public.collector_assignments (id uuid primary key default gen_random_uuid(), tenant_id uuid not null, client_id uuid not null, collector_user_id uuid not null references auth.users(id) on delete cascade, route_name text, active boolean not null default true, created_at timestamptz not null default now(), unique(tenant_id,client_id,collector_user_id), foreign key(client_id,tenant_id) references public.clients(id,tenant_id) on delete cascade);
create table public.collector_visits (id uuid primary key default gen_random_uuid(), tenant_id uuid not null, client_id uuid not null, collector_user_id uuid not null references auth.users(id) on delete restrict, result public.visit_result not null, note text, visited_at timestamptz not null default now(), foreign key(client_id,tenant_id) references public.clients(id,tenant_id) on delete restrict);
create table public.daily_closures (id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade, closure_date date not null, opening_balance numeric(14,2) not null, entries numeric(14,2) not null, exits numeric(14,2) not null, closing_balance numeric(14,2) not null, notes text, closed_by uuid references auth.users(id) on delete set null, closed_at timestamptz not null default now(), unique(tenant_id,closure_date));
create table public.audit_log (id uuid primary key default gen_random_uuid(), tenant_id uuid references public.tenants(id) on delete set null, actor_id uuid references auth.users(id) on delete set null, action text not null, entity text not null, entity_id uuid, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create index audit_tenant_date_idx on public.audit_log(tenant_id,created_at desc);

create or replace function public.is_master_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.memberships m where m.user_id=auth.uid() and m.role='master_admin' and m.active); $$;
create or replace function public.is_tenant_member(target uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.memberships m join public.tenants t on t.id=m.tenant_id where m.user_id=auth.uid() and m.tenant_id=target and m.active and t.state='approved'); $$;
create or replace function public.has_tenant_role(target uuid, allowed public.member_role[]) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.memberships m join public.tenants t on t.id=m.tenant_id where m.user_id=auth.uid() and m.tenant_id=target and m.active and m.role=any(allowed) and t.state='approved'); $$;
revoke all on function public.is_master_admin() from public;
revoke all on function public.is_tenant_member(uuid) from public;
revoke all on function public.has_tenant_role(uuid,public.member_role[]) from public;
grant execute on function public.is_master_admin() to authenticated;
grant execute on function public.is_tenant_member(uuid) to authenticated;
grant execute on function public.has_tenant_role(uuid,public.member_role[]) to authenticated;

-- Apply RLS consistently to every tenant scoped table. Master admin can administer global requests.
do $$ declare tab text; begin foreach tab in array array['profiles','tenants','tenant_settings','memberships','clients','client_documents','loans','loan_versions','installments','payments','payment_allocations','ledger_movements','expenses','collector_assignments','collector_visits','daily_closures','audit_log'] loop execute format('alter table public.%I enable row level security',tab); end loop; end $$;
create policy tenants_read on public.tenants for select to authenticated using (public.is_master_admin() or exists(select 1 from public.memberships m where m.tenant_id=id and m.user_id=auth.uid() and m.active));
create policy tenants_master_manage on public.tenants for all to authenticated using(public.is_master_admin()) with check(public.is_master_admin());
create policy profile_self_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_master_admin());
create policy profile_self_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy profile_self_insert on public.profiles for insert to authenticated with check(id=auth.uid());
create policy memberships_read on public.memberships for select to authenticated using(public.is_master_admin() or public.is_tenant_member(tenant_id));
create policy memberships_admin_write on public.memberships for all to authenticated using(public.is_master_admin() or public.has_tenant_role(tenant_id,array['tenant_admin']::public.member_role[])) with check(public.is_master_admin() or public.has_tenant_role(tenant_id,array['tenant_admin']::public.member_role[]));
create policy client_read on public.clients for select to authenticated using(public.is_master_admin() or public.is_tenant_member(tenant_id));
create policy client_write on public.clients for all to authenticated using(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin','employee']::public.member_role[])) with check(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin','employee']::public.member_role[]));
create policy tenant_scope_select on public.tenant_settings for select to authenticated using(public.is_master_admin() or public.is_tenant_member(tenant_id));
create policy tenant_admin_all on public.tenant_settings for all to authenticated using(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin']::public.member_role[])) with check(public.has_tenant_role(tenant_id,array['master_admin','tenant_admin']::public.member_role[]));
-- The tenant_id predicate is shared by all remaining operational entities.
do $$ declare tab text; begin foreach tab in array array['client_documents','loans','loan_versions','installments','payments','payment_allocations','ledger_movements','expenses','collector_assignments','collector_visits','daily_closures','audit_log'] loop execute format('create policy tenant_select on public.%I for select to authenticated using(public.is_master_admin() or public.is_tenant_member(tenant_id))',tab); execute format('create policy tenant_insert on public.%I for insert to authenticated with check(public.has_tenant_role(tenant_id,array[''master_admin'',''tenant_admin'',''employee'']::public.member_role[]))',tab); execute format('create policy tenant_update on public.%I for update to authenticated using(public.has_tenant_role(tenant_id,array[''master_admin'',''tenant_admin'',''employee'']::public.member_role[])) with check(public.has_tenant_role(tenant_id,array[''master_admin'',''tenant_admin'',''employee'']::public.member_role[]))',tab); end loop; end $$;
-- Private client document bucket; objects are addressed by tenant UUID / client UUID / random object name.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('client-documents','client-documents',false,10485760,array['image/jpeg','image/png','application/pdf']) on conflict(id) do nothing;
create policy client_docs_storage_read on storage.objects for select to authenticated using(bucket_id='client-documents' and (public.is_master_admin() or public.is_tenant_member((storage.foldername(name))[1]::uuid)));
create policy client_docs_storage_insert on storage.objects for insert to authenticated with check(bucket_id='client-documents' and public.has_tenant_role((storage.foldername(name))[1]::uuid,array['master_admin','tenant_admin','employee']::public.member_role[]));
