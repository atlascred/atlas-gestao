-- Financial events preserve fees, concessions and renewal history independently of receipts.
alter table public.payments add column payment_kind text not null default 'receipt' check(payment_kind in ('receipt','renewal','settlement','negotiation'));
alter table public.installments add column waived_amount numeric(14,2) not null default 0 check(waived_amount>=0);
alter table public.installments add constraint installment_paid_waived_limit check(paid_amount+waived_amount<=amount);
create table public.loan_fee_charges(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,loan_id uuid not null,charge_date date not null,
 amount numeric(14,2) not null check(amount>0),paid_amount numeric(14,2) not null default 0,waived_amount numeric(14,2) not null default 0,
 calculation jsonb not null,unique(loan_id,charge_date),unique(id,tenant_id),
 foreign key(loan_id,tenant_id) references public.loans(id,tenant_id),check(paid_amount>=0 and waived_amount>=0 and paid_amount+waived_amount<=amount)
);
create table public.payment_fee_allocations(tenant_id uuid not null,payment_id uuid not null,fee_id uuid not null,amount numeric(14,2) not null check(amount>0),primary key(payment_id,fee_id),foreign key(payment_id,tenant_id) references public.payments(id,tenant_id),foreign key(fee_id,tenant_id) references public.loan_fee_charges(id,tenant_id));
create table public.payment_concessions(tenant_id uuid not null,payment_id uuid not null,installment_id uuid,fee_id uuid,amount numeric(14,2) not null check(amount>0),check(num_nonnulls(installment_id,fee_id)=1),foreign key(payment_id,tenant_id) references public.payments(id,tenant_id),foreign key(installment_id,tenant_id) references public.installments(id,tenant_id),foreign key(fee_id,tenant_id) references public.loan_fee_charges(id,tenant_id));
create table public.loan_renewals(tenant_id uuid not null,payment_id uuid primary key,loan_id uuid not null,old_due date not null,new_due date not null,interest_received numeric(14,2) not null,foreign key(payment_id,tenant_id) references public.payments(id,tenant_id),foreign key(loan_id,tenant_id) references public.loans(id,tenant_id));
alter table public.loans add column fees_assessed_through date;
alter table public.loans add column delinquent_days integer not null default 0;
do $$ declare t text;begin foreach t in array array['loan_fee_charges','payment_fee_allocations','payment_concessions','loan_renewals'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('create policy read_financial_events on public.%I for select to authenticated using(public.has_tenant_permission(tenant_id,''payments.read''))',t);
 execute format('revoke insert, update, delete on public.%I from anon,authenticated',t);
end loop;end $$;
-- Assessment is performed under the same loan row lock as a receipt.
create function public.assess_loan_fees(p_tenant uuid,p_loan uuid,p_day date) returns void
language plpgsql security definer set search_path=public as $$
declare l public.loans%rowtype;d date;cnt integer;v numeric(14,2);begin
 if not public.has_tenant_permission(p_tenant,'payments.receive') then raise exception 'not_authorized' using errcode='42501';end if;
 select * into l from public.loans where tenant_id=p_tenant and id=p_loan for update;
 if not found or l.state<>'active' then return;end if;
 if p_day>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'future_date';end if;
 for d in select generate_series(coalesce(l.fees_assessed_through,l.start_date)+1,p_day,interval '1 day')::date loop
  select count(*) into cnt from public.installments where tenant_id=p_tenant and loan_id=p_loan and due_date<d and amount>paid_amount+waived_amount and state<>'cancelled';
  v:=0;
  if cnt>0 then
   if l.modality='daily' then l.delinquent_days:=l.delinquent_days+1;if mod(l.delinquent_days,l.late_fee_block_days)=0 then v:=l.late_fee;end if;
   else v:=l.late_fee*cnt;end if;
  else l.delinquent_days:=0;
  end if;
  if v>0 then insert into public.loan_fee_charges(tenant_id,loan_id,charge_date,amount,calculation) values(p_tenant,p_loan,d,v,jsonb_build_object('modality',l.modality,'unpaid_installments',cnt,'fixed_fee',l.late_fee,'block_days',l.late_fee_block_days,'delinquent_days',l.delinquent_days));end if;
 end loop;
 update public.loans set fees_assessed_through=greatest(coalesce(fees_assessed_through,l.start_date),p_day),delinquent_days=l.delinquent_days where id=p_loan;
end $$;
revoke all on function public.assess_loan_fees(uuid,uuid,date) from public,anon,authenticated;

create function public.receive_loan_payment(p_tenant uuid,p_loan uuid,p_amount numeric,p_key text,p_kind text default 'receipt',p_note text default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare l public.loans%rowtype;pid uuid;existing public.payments%rowtype;r record;v numeric(14,2);remaining numeric(14,2);base_due numeric(14,2);fee_due numeric(14,2);today date:=(now() at time zone 'America/Sao_Paulo')::date;old_due date;new_due date;month_start date;begin
 if not public.has_tenant_permission(p_tenant,'payments.receive') then raise exception 'not_authorized' using errcode='42501';end if;
 if p_kind in ('settlement','renewal','negotiation') and not public.has_tenant_role(p_tenant,array['tenant_admin']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501';end if;
 if p_key is null or length(p_key) not between 12 and 120 or p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) or p_kind not in ('receipt','settlement','renewal','negotiation') then raise exception 'invalid_payment';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant::text||p_key,0));
 select * into existing from public.payments where tenant_id=p_tenant and idempotency_key=p_key;
 if found then if existing.loan_id<>p_loan or existing.amount<>p_amount or existing.payment_kind<>p_kind then raise exception 'idempotency_conflict';end if;return existing.id;end if;
 select * into l from public.loans where id=p_loan and tenant_id=p_tenant for update;
 if not found or l.state<>'active' then raise exception 'loan_not_active';end if;
 perform public.assess_loan_fees(p_tenant,p_loan,today);
 select coalesce(sum(amount-paid_amount-waived_amount),0) into base_due from public.installments where loan_id=p_loan and state<>'cancelled';
 select coalesce(sum(amount-paid_amount-waived_amount),0) into fee_due from public.loan_fee_charges where loan_id=p_loan;
 if p_kind='renewal' then
  if l.modality<>'monthly' or exists(select 1 from public.installments where loan_id=p_loan and (paid_amount>0 or waived_amount>0)) or p_amount<>l.interest_amount+fee_due then raise exception 'invalid_renewal_amount';end if;
 elsif p_kind='negotiation' then
  if l.modality='monthly' then raise exception 'use_monthly_renewal';end if;
  select coalesce(sum(amount-paid_amount-waived_amount),0) into v from public.installments where loan_id=p_loan and due_date<=today and state<>'cancelled';
  if p_amount<>v+fee_due then raise exception 'invalid_negotiation_amount';end if;
 elsif p_amount>base_due+fee_due then raise exception 'payment_exceeds_balance';end if;
 insert into public.payments(tenant_id,loan_id,amount,paid_at,note,received_by,idempotency_key,payment_kind) values(p_tenant,p_loan,p_amount,now(),p_note,auth.uid(),p_key,p_kind) returning id into pid;
 remaining:=p_amount;
 -- Oldest installments first, then assessed fees; renewal receives only fees and interest.
 if p_kind<>'renewal' then
  for r in select * from public.installments where loan_id=p_loan and state<>'cancelled' and amount>paid_amount+waived_amount and (p_kind<>'negotiation' or due_date<=today) order by due_date,sequence for update loop
   v:=least(remaining,r.amount-r.paid_amount-r.waived_amount);exit when v<=0;
   insert into public.payment_allocations(tenant_id,payment_id,installment_id,amount) values(p_tenant,pid,r.id,v);
   update public.installments set paid_amount=paid_amount+v,state=case when paid_amount+waived_amount+v=amount then 'paid'::public.installment_state else 'partial'::public.installment_state end where id=r.id;
   remaining:=remaining-v;
  end loop;
 end if;
 for r in select * from public.loan_fee_charges where loan_id=p_loan and amount>paid_amount+waived_amount order by charge_date for update loop
  v:=least(remaining,r.amount-r.paid_amount-r.waived_amount);exit when v<=0;
  insert into public.payment_fee_allocations values(p_tenant,pid,r.id,v);
  update public.loan_fee_charges set paid_amount=paid_amount+v where id=r.id;remaining:=remaining-v;
 end loop;
 if p_kind='settlement' then
  for r in select * from public.installments where loan_id=p_loan and amount>paid_amount+waived_amount loop
   v:=r.amount-r.paid_amount-r.waived_amount;insert into public.payment_concessions values(p_tenant,pid,r.id,null,v);update public.installments set waived_amount=waived_amount+v,state='paid' where id=r.id;
  end loop;
  for r in select * from public.loan_fee_charges where loan_id=p_loan and amount>paid_amount+waived_amount loop
   v:=r.amount-r.paid_amount-r.waived_amount;insert into public.payment_concessions values(p_tenant,pid,null,r.id,v);update public.loan_fee_charges set waived_amount=waived_amount+v where id=r.id;
  end loop;
 end if;
 if p_kind='renewal' then
  select due_date into old_due from public.installments where loan_id=p_loan;
  month_start:=(date_trunc('month',greatest(old_due,today))+interval '1 month')::date;
  new_due:=month_start+least(extract(day from l.start_date)::int,extract(day from (month_start+interval '1 month - 1 day'))::int)-1;
  insert into public.loan_renewals values(p_tenant,pid,p_loan,old_due,new_due,l.interest_amount);
  update public.installments set due_date=new_due where loan_id=p_loan;
 end if;
 if not exists(select 1 from public.installments where loan_id=p_loan and amount>paid_amount+waived_amount and state<>'cancelled') and not exists(select 1 from public.loan_fee_charges where loan_id=p_loan and amount>paid_amount+waived_amount) then update public.loans set state='paid',updated_at=now() where id=p_loan;end if;
 insert into public.ledger_movements(tenant_id,kind,amount,direction,reference_table,reference_id,description,idempotency_key,created_by) values(p_tenant,'payment',p_amount,1,'payments',pid,'Recebimento '||l.contract_number,'payment:'||pid,auth.uid());
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id,metadata) values(p_tenant,auth.uid(),'payment.'||p_kind,'payments',pid,jsonb_build_object('amount',p_amount,'fee_due',fee_due));
 return pid;
end $$;
revoke all on function public.receive_loan_payment(uuid,uuid,numeric,text,text,text) from public;
grant execute on function public.receive_loan_payment(uuid,uuid,numeric,text,text,text) to authenticated;
-- Disable old receipt path so it cannot bypass fee accounting.
revoke execute on function public.record_payment_atomic(uuid,uuid,numeric,timestamptz,text,text) from authenticated;
create or replace function public.reverse_payment_atomic(p_tenant uuid,p_payment uuid,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare p public.payments%rowtype;r record;renewal public.loan_renewals%rowtype;begin
 if not public.has_tenant_role(p_tenant,array['tenant_admin']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501';end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'reason_required';end if;
 select * into p from public.payments where tenant_id=p_tenant and id=p_payment;
 if not found then raise exception 'payment_not_found';end if;
 perform 1 from public.loans where id=p.loan_id for update;
 select * into p from public.payments where id=p_payment for update;
 if p.reversed_at is not null then return p.id;end if;
 select * into renewal from public.loan_renewals where payment_id=p.id;
 if found then
  if exists(select 1 from public.payments where loan_id=p.loan_id and paid_at>p.paid_at and reversed_at is null) or exists(select 1 from public.loan_fee_charges where loan_id=p.loan_id and charge_date>(p.paid_at at time zone 'America/Sao_Paulo')::date) then raise exception 'reverse_later_events_first';end if;
  update public.installments set due_date=renewal.old_due where loan_id=p.loan_id;
  update public.loans set fees_assessed_through=(p.paid_at at time zone 'America/Sao_Paulo')::date where id=p.loan_id;
 end if;
 for r in select * from public.payment_allocations where payment_id=p.id loop update public.installments set paid_amount=paid_amount-r.amount where id=r.installment_id;end loop;
 for r in select * from public.payment_fee_allocations where payment_id=p.id loop update public.loan_fee_charges set paid_amount=paid_amount-r.amount where id=r.fee_id;end loop;
 for r in select * from public.payment_concessions where payment_id=p.id loop
  if r.installment_id is not null then update public.installments set waived_amount=waived_amount-r.amount where id=r.installment_id;else update public.loan_fee_charges set waived_amount=waived_amount-r.amount where id=r.fee_id;end if;
 end loop;
 update public.installments set state=case when paid_amount+waived_amount=amount then 'paid'::public.installment_state when paid_amount+waived_amount>0 then 'partial'::public.installment_state else 'open'::public.installment_state end where loan_id=p.loan_id and state<>'cancelled';
 update public.payments set reversed_at=now() where id=p.id;
 update public.loans set state='active',updated_at=now() where id=p.loan_id and state='paid';
 insert into public.ledger_movements(tenant_id,kind,amount,direction,reference_table,reference_id,description,idempotency_key,created_by,reversed_movement_id) select p_tenant,'reversal',p.amount,-1,'payments',p.id,'Estorno: '||trim(p_reason),'reversal:'||p.id,auth.uid(),id from public.ledger_movements where tenant_id=p_tenant and idempotency_key='payment:'||p.id;
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id,metadata) values(p_tenant,auth.uid(),'payment.reversed','payments',p.id,jsonb_build_object('reason',p_reason));return p.id;
end $$;
