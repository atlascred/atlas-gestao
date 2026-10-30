-- Runs inside a transaction and rolls back all test data. Use only against a staging/test project.
begin;
select gen_random_uuid() as tenant_id \gset
select '11111111-1111-4111-8111-111111111111'::uuid as user_id \gset
select '22222222-2222-4222-8222-222222222222'::uuid as client_id \gset
select gen_random_uuid() as other_tenant_id \gset
select '33333333-3333-4333-8333-333333333333'::uuid as other_client_id \gset
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values(:'user_id'::uuid,'authenticated','authenticated','atlas-rpc-smoke@example.invalid','',now(),'{}','{}',now(),now());
insert into public.tenants(id,name,state,approved_at) values(:'tenant_id'::uuid,'ATLAS smoke test','approved',now());
insert into public.memberships(tenant_id,user_id,role,active) values(:'tenant_id'::uuid,:'user_id'::uuid,'tenant_admin',true);
insert into public.tenants(id,name,state,approved_at) values(:'other_tenant_id'::uuid,'Outro tenant','approved',now());
insert into public.clients(id,tenant_id,full_name,cpf) values(:'client_id'::uuid,:'tenant_id'::uuid,'Teste Transacional','52998224725');
insert into public.clients(id,tenant_id,full_name,cpf) values(:'other_client_id'::uuid,:'other_tenant_id'::uuid,'Cliente Isolado','11144477735');
select set_config('request.jwt.claim.sub',:'user_id',true);
select set_config('request.jwt.claim.role','authenticated',true);
set local role authenticated;
select public.has_tenant_permission(:'other_tenant_id'::uuid,'dashboard.read') as other_tenant_access \gset
\if :other_tenant_access
\echo 'RLS tenant isolation failed.'
\quit 3
\endif
select count(*) as visible_other_clients from public.clients where tenant_id=:'other_tenant_id'::uuid \gset
\if :visible_other_clients
\echo 'RLS exposed a client from another tenant.'
\quit 3
\endif
select public.create_loan_atomic(jsonb_build_object(
 'idempotency_key','smoke-loan-key-0001','tenant_id', :'tenant_id'::uuid, 'client_id', :'client_id'::uuid, 'contract_number','AT-SMOKE-0001','modality','daily',
 'principal',100.00,'interest_percent',20,'interest_amount',20.00,'total_amount',120.00,'start_date',to_char((now() at time zone 'America/Sao_Paulo')::date,'YYYY-MM-DD'),
 'late_fee',2,'late_fee_block_days',2,'include_sundays',true,'terms_snapshot','{}'::jsonb,
 'installments',jsonb_build_array(jsonb_build_object('due_date',to_char((now() at time zone 'America/Sao_Paulo')::date+1,'YYYY-MM-DD'),'amount',60.00),jsonb_build_object('due_date',to_char((now() at time zone 'America/Sao_Paulo')::date+2,'YYYY-MM-DD'),'amount',60.00))
)) as loan_id \gset
select public.create_loan_atomic(jsonb_build_object('tenant_id',:'tenant_id'::uuid,'idempotency_key','smoke-loan-key-0001')) as duplicate_loan_id \gset
select (:'loan_id'::uuid=:'duplicate_loan_id'::uuid) as loan_idempotency_ok \gset
\if :loan_idempotency_ok
\else
\echo 'Loan idempotency failed.'
\quit 3
\endif
select public.receive_loan_payment(:'tenant_id'::uuid,:'loan_id'::uuid,10.00,'smoke-payment-0001','receipt','smoke test') as payment_id \gset
select public.receive_loan_payment(:'tenant_id'::uuid,:'loan_id'::uuid,10.00,'smoke-payment-0001','receipt','duplicate') as duplicate_payment_id \gset
select public.create_expense_atomic(:'tenant_id'::uuid,'Teste',5.00,(now() at time zone 'America/Sao_Paulo')::date,'smoke test','smoke-expense-key-0001');
select public.create_expense_atomic(:'tenant_id'::uuid,'Teste',5.00,(now() at time zone 'America/Sao_Paulo')::date,'duplicado','smoke-expense-key-0001');
select public.create_cash_adjustment(:'tenant_id'::uuid,1.00,1::smallint,now(),'Teste de ajuste','smoke-adjust-key-0001');
select public.create_cash_adjustment(:'tenant_id'::uuid,1.00,1::smallint,now(),'duplicado','smoke-adjust-key-0001');
select public.close_cash_day(:'tenant_id'::uuid,(now() at time zone 'America/Sao_Paulo')::date,'smoke test');
select public.dashboard_summary(:'tenant_id'::uuid);
select public.reverse_payment_atomic(:'tenant_id'::uuid,:'payment_id'::uuid,'smoke test reversal');
select (:'payment_id'::uuid=:'duplicate_payment_id'::uuid) as idempotency_ok \gset
\if :idempotency_ok
\else
\echo 'Payment idempotency failed.'
\quit 3
\endif
select ((select count(*) from public.ledger_movements where tenant_id=:'tenant_id'::uuid and reference_table='payments')=2) as ledger_ok \gset
\if :ledger_ok
\else
\echo 'Ledger reconciliation failed.'
\quit 3
\endif
reset role;
rollback;
