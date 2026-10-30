alter table public.loans add column if not exists idempotency_key text;
create unique index if not exists loans_tenant_idempotency_idx on public.loans(tenant_id,idempotency_key) where idempotency_key is not null;
alter table public.expenses add column if not exists idempotency_key text;
create unique index if not exists expenses_tenant_idempotency_idx on public.expenses(tenant_id,idempotency_key) where idempotency_key is not null;

create or replace function public.create_loan_atomic(p jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare v_tenant uuid:=(p->>'tenant_id')::uuid;v_client uuid:=(p->>'client_id')::uuid;v_loan uuid:=gen_random_uuid();v_existing uuid;v_user uuid:=auth.uid();v_key text:=p->>'idempotency_key';v_principal numeric(14,2):=(p->>'principal')::numeric;v_interest numeric(14,2):=(p->>'interest_amount')::numeric;v_total numeric(14,2):=(p->>'total_amount')::numeric;v_count int:=jsonb_array_length(p->'installments');v_sum numeric(14,2);v_row jsonb;v_i int:=0;begin
 if v_user is null or not public.has_tenant_permission(v_tenant,'loans.create') then raise exception 'not_authorized' using errcode='42501';end if;
 if v_key is null or length(v_key)<12 or length(v_key)>120 then raise exception 'invalid_idempotency_key' using errcode='22023';end if;
 select id into v_existing from public.loans where tenant_id=v_tenant and idempotency_key=v_key;if v_existing is not null then return v_existing;end if;
 if v_principal<=0 or v_interest<0 or v_total<>v_principal+v_interest or v_count<1 then raise exception 'invalid_terms' using errcode='22023';end if;
 if not exists(select 1 from public.clients where id=v_client and tenant_id=v_tenant and active) then raise exception 'client_not_found' using errcode='22023';end if;
 select coalesce(sum((x->>'amount')::numeric),0) into v_sum from jsonb_array_elements(p->'installments') x;if v_sum<>v_total then raise exception 'installment_total_mismatch' using errcode='22023';end if;
 insert into public.loans(id,tenant_id,client_id,contract_number,modality,state,principal,interest_percent,interest_amount,total_amount,installment_count,installment_amount,start_date,due_day,late_fee,late_fee_block_days,include_sundays,terms_snapshot,created_by,idempotency_key) values(v_loan,v_tenant,v_client,p->>'contract_number',(p->>'modality')::public.loan_modality,'active',v_principal,(p->>'interest_percent')::numeric,v_interest,v_total,v_count,v_total/v_count,(p->>'start_date')::date,nullif(p->>'due_day','')::int,coalesce((p->>'late_fee')::numeric,0),coalesce((p->>'late_fee_block_days')::int,2),coalesce((p->>'include_sundays')::boolean,true),p->'terms_snapshot',v_user,v_key);
 for v_row in select value from jsonb_array_elements(p->'installments') loop v_i:=v_i+1;insert into public.installments(tenant_id,loan_id,sequence,due_date,amount) values(v_tenant,v_loan,v_i,(v_row->>'due_date')::date,(v_row->>'amount')::numeric);end loop;
 insert into public.ledger_movements(tenant_id,kind,amount,direction,occurred_at,reference_table,reference_id,description,idempotency_key,created_by) values(v_tenant,'loan_disbursement',v_principal,-1,((p->>'start_date')::date::timestamp at time zone 'America/Sao_Paulo'),'loans',v_loan,'Liberação do contrato '||(p->>'contract_number'),'loan:'||v_loan::text,v_user);
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id,metadata) values(v_tenant,v_user,'loan.created','loans',v_loan,jsonb_build_object('principal',v_principal,'installments',v_count));return v_loan;end $$;

drop function if exists public.create_expense_atomic(uuid,text,numeric,date,text);
create or replace function public.create_expense_atomic(p_tenant uuid,p_category text,p_amount numeric,p_date date,p_note text,p_idempotency_key text) returns uuid language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_expense uuid:=gen_random_uuid();v_existing uuid;v_move uuid:=gen_random_uuid();begin
 if v_user is null or not public.has_tenant_permission(p_tenant,'expenses.create') then raise exception 'not_authorized' using errcode='42501';end if;
 if p_idempotency_key is null or length(p_idempotency_key)<12 or length(p_idempotency_key)>120 then raise exception 'invalid_idempotency_key' using errcode='22023';end if;
 select id into v_existing from public.expenses where tenant_id=p_tenant and idempotency_key=p_idempotency_key;if v_existing is not null then return v_existing;end if;
 if length(trim(p_category))<2 or length(p_category)>100 or p_amount<=0 then raise exception 'invalid_expense' using errcode='22023';end if;
 insert into public.ledger_movements(id,tenant_id,kind,amount,direction,occurred_at,reference_table,reference_id,description,idempotency_key,created_by) values(v_move,p_tenant,'expense',round(p_amount,2),-1,(p_date::timestamp at time zone 'America/Sao_Paulo'),'expenses',v_expense,'Despesa: '||trim(p_category),'expense:'||p_tenant::text||':'||p_idempotency_key,v_user);
 insert into public.expenses(id,tenant_id,category,amount,expense_date,note,ledger_movement_id,created_by,idempotency_key) values(v_expense,p_tenant,trim(p_category),round(p_amount,2),p_date,p_note,v_move,v_user,p_idempotency_key);
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id) values(p_tenant,v_user,'expense.created','expenses',v_expense);return v_expense;end $$;

 drop function if exists public.create_cash_adjustment(uuid,numeric,smallint,timestamptz,text);
create or replace function public.create_cash_adjustment(p_tenant uuid,p_amount numeric,p_direction smallint,p_date timestamptz,p_note text,p_idempotency_key text) returns uuid language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_id uuid:=gen_random_uuid();v_existing uuid;begin
 if v_user is null or not public.has_tenant_role(p_tenant,array['master_admin','tenant_admin']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501';end if;
 if p_idempotency_key is null or length(p_idempotency_key)<12 or length(p_idempotency_key)>120 then raise exception 'invalid_idempotency_key' using errcode='22023';end if;
 select id into v_existing from public.ledger_movements where tenant_id=p_tenant and idempotency_key='adjust:'||p_tenant::text||':'||p_idempotency_key;if v_existing is not null then return v_existing;end if;
 if p_amount<=0 or p_direction not in (-1,1) or length(trim(coalesce(p_note,'')))<3 then raise exception 'invalid_adjustment' using errcode='22023';end if;
 insert into public.ledger_movements(id,tenant_id,kind,amount,direction,occurred_at,description,idempotency_key,created_by) values(v_id,p_tenant,'adjustment',round(p_amount,2),p_direction,p_date,trim(p_note),'adjust:'||p_tenant::text||':'||p_idempotency_key,v_user);
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id) values(p_tenant,v_user,'cash.adjusted','ledger_movements',v_id);return v_id;end $$;
revoke all on function public.create_expense_atomic(uuid,text,numeric,date,text,text) from public;
revoke all on function public.create_cash_adjustment(uuid,numeric,smallint,timestamptz,text,text) from public;
grant execute on function public.create_expense_atomic(uuid,text,numeric,date,text,text) to authenticated;
grant execute on function public.create_cash_adjustment(uuid,numeric,smallint,timestamptz,text,text) to authenticated;
