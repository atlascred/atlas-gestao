\set ON_ERROR_STOP on
begin;
insert into auth.users(id,aud,role,email,created_at,updated_at) values('11111111-1111-4111-8111-111111111111','authenticated','authenticated','lifecycle@example.invalid',now(),now());
insert into public.tenants(id,name,state,approved_at) values('22222222-2222-4222-8222-222222222222','Teste descartável','approved',now());
insert into public.memberships(tenant_id,user_id,role) values('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','tenant_admin');
insert into public.clients(id,tenant_id,full_name,cpf) values('33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222222','Teste','52998224725');
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
set local role authenticated;
do $$ declare t uuid:='22222222-2222-4222-8222-222222222222'; c uuid:='33333333-3333-4333-8333-333333333333';l uuid;p uuid;q uuid;today date:=(now() at time zone 'America/Sao_Paulo')::date;n numeric;begin
 l:=public.create_loan_atomic(jsonb_build_object('tenant_id',t,'client_id',c,'idempotency_key','lifecycle-daily-001','contract_number','LIFECYCLE-DAILY','modality','daily','principal',100,'interest_percent',20,'interest_amount',20,'total_amount',120,'start_date',today-5,'late_fee',5,'late_fee_block_days',2,'terms_snapshot','{}'::jsonb,'installments',jsonb_build_array(jsonb_build_object('due_date',today-4,'amount',60),jsonb_build_object('due_date',today-3,'amount',60))));
 p:=public.receive_loan_payment(t,l,10,'lifecycle-partial-001','receipt','teste');
 q:=public.receive_loan_payment(t,l,10,'lifecycle-partial-001','receipt','teste');
 if p<>q then raise exception 'duplicate receipt';end if;
 select sum(amount) into n from public.loan_fee_charges where loan_id=l;if n<>10 then raise exception 'daily fee duplicated or block incorrect: %',n;end if;
 p:=public.receive_loan_payment(t,l,100,'lifecycle-settle-001','settlement','desconto');
 select sum(amount-paid_amount-waived_amount) into n from public.installments where loan_id=l;if n<>0 then raise exception 'settlement left balance';end if;
 perform public.reverse_payment_atomic(t,p,'reabrir');
 select sum(amount-paid_amount-waived_amount) into n from public.installments where loan_id=l;if n<>110 then raise exception 'reversal invalid: %',n;end if;
 -- Monthly renewal and reversal preserve principal and the original due date.
 l:=public.create_loan_atomic(jsonb_build_object('tenant_id',t,'client_id',c,'idempotency_key','lifecycle-month-001','contract_number','LIFECYCLE-MONTH','modality','monthly','principal',100,'interest_percent',20,'interest_amount',20,'total_amount',120,'start_date',((today-2)-interval '1 month')::date,'late_fee',2,'terms_snapshot','{}'::jsonb,'installments',jsonb_build_array(jsonb_build_object('due_date',today-2,'amount',120))));
 p:=public.receive_loan_payment(t,l,24,'lifecycle-renew-001','renewal','renovar');
 select sum(amount-paid_amount-waived_amount) into n from public.installments where loan_id=l;if n<>120 then raise exception 'renewal capitalized interest';end if;
 perform public.reverse_payment_atomic(t,p,'corrigir renovação');
 if not exists(select 1 from public.installments where loan_id=l and due_date=today-2) then raise exception 'renewal reversal due';end if;
 raise notice 'PASS: fees, partial receipt, idempotency, settlement, reversal, renewal';
end $$;
rollback;
