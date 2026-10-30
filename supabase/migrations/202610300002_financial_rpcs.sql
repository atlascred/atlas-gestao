-- Atomic contract creation and payment allocation; only callable by an approved tenant operator.
create or replace function public.create_loan_atomic(p jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_tenant uuid:=(p->>'tenant_id')::uuid; v_client uuid:=(p->>'client_id')::uuid; v_loan uuid:=gen_random_uuid(); v_user uuid:=auth.uid(); v_principal numeric(14,2):=(p->>'principal')::numeric; v_interest numeric(14,2):=(p->>'interest_amount')::numeric; v_total numeric(14,2):=(p->>'total_amount')::numeric; v_count int:=jsonb_array_length(p->'installments'); v_sum numeric(14,2); v_due numeric(14,2); v_row jsonb; v_i int:=0;
begin
 if v_user is null or not public.has_tenant_role(v_tenant,array['master_admin','tenant_admin','employee']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501'; end if;
 if v_principal<=0 or v_interest<0 or v_total<>v_principal+v_interest or v_count<1 then raise exception 'invalid_terms' using errcode='22023'; end if;
 if not exists(select 1 from public.clients where id=v_client and tenant_id=v_tenant and active) then raise exception 'client_not_found' using errcode='22023'; end if;
 select coalesce(sum((x->>'amount')::numeric),0) into v_sum from jsonb_array_elements(p->'installments') x;
 if v_sum<>v_total then raise exception 'installment_total_mismatch' using errcode='22023'; end if;
 insert into public.loans(id,tenant_id,client_id,contract_number,modality,state,principal,interest_percent,interest_amount,total_amount,installment_count,installment_amount,start_date,due_day,late_fee,late_fee_block_days,include_sundays,terms_snapshot,created_by)
 values(v_loan,v_tenant,v_client,p->>'contract_number',(p->>'modality')::public.loan_modality,'active',v_principal,(p->>'interest_percent')::numeric,v_interest,v_total,v_count,(v_total/v_count), (p->>'start_date')::date,nullif(p->>'due_day','')::int,coalesce((p->>'late_fee')::numeric,0),coalesce((p->>'late_fee_block_days')::int,2),coalesce((p->>'include_sundays')::boolean,true),p->'terms_snapshot',v_user);
 for v_row in select value from jsonb_array_elements(p->'installments') loop
  v_i:=v_i+1; insert into public.installments(tenant_id,loan_id,sequence,due_date,amount) values(v_tenant,v_loan,v_i,(v_row->>'due_date')::date,(v_row->>'amount')::numeric);
 end loop;
 insert into public.ledger_movements(tenant_id,kind,amount,direction,occurred_at,reference_table,reference_id,description,idempotency_key,created_by)
 values(v_tenant,'loan_disbursement',v_principal,-1,((p->>'start_date')::date::timestamp at time zone 'America/Sao_Paulo'),'loans',v_loan,'Liberação do contrato '||(p->>'contract_number'),'loan:'||v_loan::text,v_user);
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id,metadata) values(v_tenant,v_user,'loan.created','loans',v_loan,jsonb_build_object('principal',v_principal,'installments',v_count));
 return v_loan;
end $$;
create or replace function public.record_payment_atomic(p_tenant uuid,p_loan uuid,p_amount numeric,p_paid_at timestamptz,p_idempotency_key text,p_note text default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_payment uuid; v_left numeric(14,2):=round(p_amount,2); v_due numeric(14,2); v_alloc numeric(14,2); v_row record;
begin
 if v_user is null or not public.has_tenant_role(p_tenant,array['master_admin','tenant_admin','employee']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_amount<=0 or p_idempotency_key is null or length(p_idempotency_key)>120 then raise exception 'invalid_payment' using errcode='22023'; end if;
 select id into v_payment from public.payments where tenant_id=p_tenant and idempotency_key=p_idempotency_key;
 if v_payment is not null then return v_payment; end if;
 perform 1 from public.loans where id=p_loan and tenant_id=p_tenant and state='active' for update;
 if not found then raise exception 'loan_not_active' using errcode='22023'; end if;
 select coalesce(sum(amount-paid_amount),0) into v_due from public.installments where tenant_id=p_tenant and loan_id=p_loan and state in ('open','partial');
 if round(p_amount,2)>v_due then raise exception 'payment_exceeds_balance' using errcode='22023'; end if;
 insert into public.payments(tenant_id,loan_id,amount,paid_at,note,received_by,idempotency_key) values(p_tenant,p_loan,round(p_amount,2),p_paid_at,p_note,v_user,p_idempotency_key) returning id into v_payment;
 for v_row in select id,amount,paid_amount from public.installments where tenant_id=p_tenant and loan_id=p_loan and state in ('open','partial') order by due_date,sequence for update loop
   exit when v_left<=0; v_alloc:=least(v_left,v_row.amount-v_row.paid_amount);
   insert into public.payment_allocations(tenant_id,payment_id,installment_id,amount) values(p_tenant,v_payment,v_row.id,v_alloc);
   update public.installments set paid_amount=paid_amount+v_alloc,state=case when paid_amount+v_alloc>=amount then 'paid'::public.installment_state else 'partial'::public.installment_state end where id=v_row.id;
   v_left:=v_left-v_alloc;
 end loop;
 insert into public.ledger_movements(tenant_id,kind,amount,direction,occurred_at,reference_table,reference_id,description,idempotency_key,created_by)
 values(p_tenant,'payment',round(p_amount,2),1,p_paid_at,'payments',v_payment,'Recebimento de parcela','payment:'||v_payment::text,v_user);
 if not exists(select 1 from public.installments where tenant_id=p_tenant and loan_id=p_loan and state in ('open','partial')) then update public.loans set state='paid',updated_at=now() where id=p_loan; end if;
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id,metadata) values(p_tenant,v_user,'payment.recorded','payments',v_payment,jsonb_build_object('amount',round(p_amount,2),'loan_id',p_loan));
 return v_payment;
end $$;
revoke all on function public.create_loan_atomic(jsonb) from public;
revoke all on function public.record_payment_atomic(uuid,uuid,numeric,timestamptz,text,text) from public;
grant execute on function public.create_loan_atomic(jsonb) to authenticated;
grant execute on function public.record_payment_atomic(uuid,uuid,numeric,timestamptz,text,text) to authenticated;

create or replace function public.create_expense_atomic(p_tenant uuid,p_category text,p_amount numeric,p_date date,p_note text default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_expense uuid:=gen_random_uuid(); v_move uuid:=gen_random_uuid();
begin
 if v_user is null or not public.has_tenant_role(p_tenant,array['master_admin','tenant_admin','employee']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501';end if;
 if length(trim(p_category))<2 or length(p_category)>100 or p_amount<=0 then raise exception 'invalid_expense' using errcode='22023';end if;
 insert into public.ledger_movements(id,tenant_id,kind,amount,direction,occurred_at,reference_table,reference_id,description,idempotency_key,created_by) values(v_move,p_tenant,'expense',round(p_amount,2),-1,(p_date::timestamp at time zone 'America/Sao_Paulo'),'expenses',v_expense,'Despesa: '||trim(p_category),'expense:'||v_expense::text,v_user);
 insert into public.expenses(id,tenant_id,category,amount,expense_date,note,ledger_movement_id,created_by) values(v_expense,p_tenant,trim(p_category),round(p_amount,2),p_date,p_note,v_move,v_user);
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id) values(p_tenant,v_user,'expense.created','expenses',v_expense);return v_expense;
end $$;
create or replace function public.create_cash_adjustment(p_tenant uuid,p_amount numeric,p_direction smallint,p_date timestamptz,p_note text) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_id uuid:=gen_random_uuid();
begin
 if v_user is null or not public.has_tenant_role(p_tenant,array['master_admin','tenant_admin']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501';end if;
 if p_amount<=0 or p_direction not in (-1,1) or length(trim(coalesce(p_note,'')))<3 then raise exception 'invalid_adjustment' using errcode='22023';end if;
 insert into public.ledger_movements(id,tenant_id,kind,amount,direction,occurred_at,description,idempotency_key,created_by) values(v_id,p_tenant,'adjustment',round(p_amount,2),p_direction,p_date,trim(p_note),'adjust:'||v_id::text,v_user);
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id) values(p_tenant,v_user,'cash.adjusted','ledger_movements',v_id);
 return v_id;
end $$;
create or replace function public.close_cash_day(p_tenant uuid,p_date date,p_notes text default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_open numeric(14,2);v_in numeric(14,2);v_out numeric(14,2);v_id uuid;
begin
 if v_user is null or not public.has_tenant_role(p_tenant,array['master_admin','tenant_admin']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501';end if;
 select coalesce(sum(amount*direction),0) into v_open from public.ledger_movements where tenant_id=p_tenant and occurred_at < (p_date::timestamp at time zone 'America/Sao_Paulo');
 select coalesce(sum(amount) filter(where direction=1),0),coalesce(sum(amount) filter(where direction=-1),0) into v_in,v_out from public.ledger_movements where tenant_id=p_tenant and (occurred_at at time zone 'America/Sao_Paulo')::date=p_date;
 insert into public.daily_closures(tenant_id,closure_date,opening_balance,entries,exits,closing_balance,notes,closed_by,closed_at) values(p_tenant,p_date,v_open,v_in,v_out,v_open+v_in-v_out,p_notes,v_user,now()) on conflict(tenant_id,closure_date) do update set opening_balance=excluded.opening_balance,entries=excluded.entries,exits=excluded.exits,closing_balance=excluded.closing_balance,notes=excluded.notes,closed_by=excluded.closed_by,closed_at=now() returning id into v_id;
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id,metadata) values(p_tenant,v_user,'cash.closed','daily_closures',v_id,jsonb_build_object('date',p_date));return v_id;
end $$;
create or replace function public.reverse_payment_atomic(p_tenant uuid,p_payment uuid,p_reason text) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_loan uuid;v_amount numeric(14,2);v_move uuid:=gen_random_uuid();v_old_move uuid;
begin
 if v_user is null or not public.has_tenant_role(p_tenant,array['master_admin','tenant_admin']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501';end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'reason_required' using errcode='22023';end if;
 select loan_id,amount into v_loan,v_amount from public.payments where id=p_payment and tenant_id=p_tenant and reversed_at is null for update;
 if not found then raise exception 'payment_not_found_or_reversed' using errcode='22023';end if;
 update public.installments i set paid_amount=i.paid_amount-a.amount,state=case when i.paid_amount-a.amount<=0 then 'open'::public.installment_state else 'partial'::public.installment_state end from public.payment_allocations a where a.payment_id=p_payment and a.installment_id=i.id and a.tenant_id=p_tenant;
 update public.payments set reversed_at=now() where id=p_payment;
 select id into v_old_move from public.ledger_movements where tenant_id=p_tenant and reference_table='payments' and reference_id=p_payment and kind='payment';
 insert into public.ledger_movements(id,tenant_id,kind,amount,direction,reference_table,reference_id,description,idempotency_key,created_by,reversed_movement_id) values(v_move,p_tenant,'reversal',v_amount,-1,'payments',p_payment,'Estorno: '||trim(p_reason),'reversal:'||p_payment::text,v_user,v_old_move);
 if exists(select 1 from public.installments where tenant_id=p_tenant and loan_id=v_loan and state in ('open','partial')) then update public.loans set state='active',updated_at=now() where id=v_loan and state='paid';end if;
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id,metadata) values(p_tenant,v_user,'payment.reversed','payments',p_payment,jsonb_build_object('reason',trim(p_reason)));return p_payment;
end $$;
revoke all on function public.create_expense_atomic(uuid,text,numeric,date,text) from public;
revoke all on function public.create_cash_adjustment(uuid,numeric,smallint,timestamptz,text) from public;
revoke all on function public.close_cash_day(uuid,date,text) from public;
revoke all on function public.reverse_payment_atomic(uuid,uuid,text) from public;
grant execute on function public.create_expense_atomic(uuid,text,numeric,date,text) to authenticated;
grant execute on function public.create_cash_adjustment(uuid,numeric,smallint,timestamptz,text) to authenticated;
grant execute on function public.close_cash_day(uuid,date,text) to authenticated;
grant execute on function public.reverse_payment_atomic(uuid,uuid,text) to authenticated;
