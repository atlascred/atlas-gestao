-- Consistent contract details and protected aggregate metrics.
drop policy if exists tenant_select on public.installments;
create policy tenant_select on public.installments for select to authenticated using(public.has_tenant_permission(tenant_id,'installments.read') or public.has_tenant_permission(tenant_id,'loans.read'));
create policy contract_fee_read on public.loan_fee_charges for select to authenticated using(public.has_tenant_permission(tenant_id,'loans.read'));
create function public.projected_loan_fee_balance(p_tenant uuid,p_loan uuid,p_today date) returns numeric language plpgsql security definer set search_path=public as $$
declare l public.loans%rowtype;balance numeric;day date;arrears int;unpaid int;begin
 if not(public.has_tenant_permission(p_tenant,'dashboard.read') or public.has_tenant_permission(p_tenant,'loans.read')) then raise exception 'not_authorized' using errcode='42501';end if;
 select * into l from public.loans where id=p_loan and tenant_id=p_tenant;if not found then return 0;end if;
 select coalesce(sum(amount-paid_amount-waived_amount),0) into balance from public.loan_fee_charges where loan_id=p_loan and tenant_id=p_tenant;
 if l.state<>'active' then return balance;end if;
 day:=coalesce(l.fees_assessed_through,l.start_date)+1;arrears:=l.delinquent_days;
 while day<=p_today loop
  select count(*) into unpaid from public.installments where loan_id=p_loan and tenant_id=p_tenant and due_date<day and amount>paid_amount+waived_amount;
  if unpaid=0 then arrears:=0;else arrears:=arrears+1;if l.modality='daily' then if mod(arrears,l.late_fee_block_days)=0 then balance:=balance+l.late_fee;end if;else balance:=balance+unpaid*l.late_fee;end if;end if;
  day:=day+1;
 end loop;return balance;
end $$;
revoke all on function public.projected_loan_fee_balance(uuid,uuid,date) from public;
grant execute on function public.projected_loan_fee_balance(uuid,uuid,date) to authenticated;
create or replace function public.dashboard_summary(p_tenant uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_today date:=(now() at time zone 'America/Sao_Paulo')::date;v_month date:=date_trunc('month',now() at time zone 'America/Sao_Paulo')::date;v_out jsonb;begin
 if not public.has_tenant_permission(p_tenant,'dashboard.read') then raise exception 'not_authorized' using errcode='42501';end if;
 select jsonb_build_object(
 'asOf',v_today,
 'clients',(select count(*) from public.clients c where c.tenant_id=p_tenant and c.active),
 'activeLoans',(select count(*) from public.loans l where l.tenant_id=p_tenant and l.state='active'),
 'principalActive',(select coalesce(sum(l.principal),0) from public.loans l where l.tenant_id=p_tenant and l.state='active'),
 'receivable',(select coalesce(sum(i.amount-i.paid_amount-i.waived_amount),0) from public.installments i where i.tenant_id=p_tenant and i.state in ('open','partial'))+(select coalesce(sum(public.projected_loan_fee_balance(p_tenant,l.id,v_today)),0) from public.loans l where l.tenant_id=p_tenant and l.state='active'),
 'cashBalance',(select coalesce(sum(m.amount*m.direction),0) from public.ledger_movements m where m.tenant_id=p_tenant),
 'cashInMonth',(select coalesce(sum(m.amount*m.direction),0) from public.ledger_movements m where m.tenant_id=p_tenant and m.kind in ('payment','reversal') and m.reference_table='payments' and (m.occurred_at at time zone 'America/Sao_Paulo')::date>=v_month),
 'cashOutMonth',(select coalesce(sum(m.amount),0) from public.ledger_movements m where m.tenant_id=p_tenant and m.direction=-1 and (m.occurred_at at time zone 'America/Sao_Paulo')::date>=v_month),
 'scheduledToday',(select coalesce(sum(i.amount),0) from public.installments i where i.tenant_id=p_tenant and i.due_date=v_today and i.state<>'cancelled'),
 'receivedToday',(select coalesce(sum(a.amount),0) from public.payment_allocations a join public.payments p on p.id=a.payment_id and p.tenant_id=a.tenant_id join public.installments i on i.id=a.installment_id and i.tenant_id=a.tenant_id where a.tenant_id=p_tenant and i.due_date=v_today and p.reversed_at is null and (p.paid_at at time zone 'America/Sao_Paulo')::date=v_today),
 'dueToday',(select coalesce(sum(i.amount-i.paid_amount-i.waived_amount),0) from public.installments i where i.tenant_id=p_tenant and i.due_date=v_today and i.state in ('open','partial')),
 'dueCount',(select count(*) from public.installments i where i.tenant_id=p_tenant and i.due_date=v_today and i.state in ('open','partial')),
 'overdue',(select coalesce(sum(i.amount-i.paid_amount-i.waived_amount),0) from public.installments i where i.tenant_id=p_tenant and i.due_date<v_today and i.state in ('open','partial'))+(select coalesce(sum(public.projected_loan_fee_balance(p_tenant,l.id,v_today)),0) from public.loans l where l.tenant_id=p_tenant and l.state='active'),
 'overdueCount',(select count(*) from public.installments i where i.tenant_id=p_tenant and i.due_date<v_today and i.state in ('open','partial')),
 'monthly',(select coalesce(jsonb_agg(jsonb_build_object('month',to_char(g.month,'MM'),'loans',coalesce(l.total,0),'payments',coalesce(p.total,0)) order by g.month),'[]'::jsonb) from generate_series((date_trunc('month',now() at time zone 'America/Sao_Paulo')-interval '5 months')::date,date_trunc('month',now() at time zone 'America/Sao_Paulo')::date,interval '1 month') as g(month) left join lateral(select sum(m.amount) total from public.ledger_movements m where m.tenant_id=p_tenant and m.kind='loan_disbursement' and date_trunc('month',m.occurred_at at time zone 'America/Sao_Paulo')=g.month) l on true left join lateral(select sum(m.amount*m.direction) total from public.ledger_movements m where m.tenant_id=p_tenant and m.kind in ('payment','reversal') and m.reference_table='payments' and date_trunc('month',m.occurred_at at time zone 'America/Sao_Paulo')=g.month) p on true)
 ) into v_out;return v_out;end $$;

create function public.bootstrap_global_admin(p_user uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 lock table public.global_admins in exclusive mode;
 if exists(select 1 from public.global_admins) then raise exception 'bootstrap_completed';end if;
 if not exists(select 1 from auth.users where id=p_user and email_confirmed_at is not null) then raise exception 'unconfirmed_user';end if;
 insert into public.global_admins(user_id,created_by) values(p_user,p_user);
 insert into public.audit_log(actor_id,action,entity,entity_id) values(p_user,'master.bootstrap.completed','global_admins',p_user);
end $$;
revoke all on function public.bootstrap_global_admin(uuid) from public,anon,authenticated;
grant execute on function public.bootstrap_global_admin(uuid) to service_role;
