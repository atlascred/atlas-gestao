create or replace function public.dashboard_summary(p_tenant uuid) returns jsonb language plpgsql security invoker set search_path=public as $$
declare v_today date:=(now() at time zone 'America/Sao_Paulo')::date;v_month date:=date_trunc('month',now() at time zone 'America/Sao_Paulo')::date;v_out jsonb;begin
 if not public.has_tenant_permission(p_tenant,'dashboard.read') then raise exception 'not_authorized' using errcode='42501';end if;
 select jsonb_build_object(
 'asOf',v_today,
 'clients',(select count(*) from public.clients c where c.tenant_id=p_tenant and c.active),
 'activeLoans',(select count(*) from public.loans l where l.tenant_id=p_tenant and l.state='active'),
 'principalActive',(select coalesce(sum(l.principal),0) from public.loans l where l.tenant_id=p_tenant and l.state='active'),
 'receivable',(select coalesce(sum(i.amount-i.paid_amount),0) from public.installments i where i.tenant_id=p_tenant and i.state in ('open','partial')),
 'cashBalance',(select coalesce(sum(m.amount*m.direction),0) from public.ledger_movements m where m.tenant_id=p_tenant),
 'cashInMonth',(select coalesce(sum(m.amount),0) from public.ledger_movements m where m.tenant_id=p_tenant and m.kind='payment' and (m.occurred_at at time zone 'America/Sao_Paulo')::date>=v_month),
 'cashOutMonth',(select coalesce(sum(m.amount),0) from public.ledger_movements m where m.tenant_id=p_tenant and m.direction=-1 and (m.occurred_at at time zone 'America/Sao_Paulo')::date>=v_month),
 'scheduledToday',(select coalesce(sum(i.amount),0) from public.installments i where i.tenant_id=p_tenant and i.due_date=v_today and i.state<>'cancelled'),
 'receivedToday',(select coalesce(sum(a.amount),0) from public.payment_allocations a join public.payments p on p.id=a.payment_id and p.tenant_id=a.tenant_id join public.installments i on i.id=a.installment_id and i.tenant_id=a.tenant_id where a.tenant_id=p_tenant and i.due_date=v_today and p.reversed_at is null and (p.paid_at at time zone 'America/Sao_Paulo')::date=v_today),
 'dueToday',(select coalesce(sum(i.amount-i.paid_amount),0) from public.installments i where i.tenant_id=p_tenant and i.due_date=v_today and i.state in ('open','partial')),
 'dueCount',(select count(*) from public.installments i where i.tenant_id=p_tenant and i.due_date=v_today and i.state in ('open','partial')),
 'overdue',(select coalesce(sum(i.amount-i.paid_amount),0) from public.installments i where i.tenant_id=p_tenant and i.due_date<v_today and i.state in ('open','partial')),
 'overdueCount',(select count(*) from public.installments i where i.tenant_id=p_tenant and i.due_date<v_today and i.state in ('open','partial')),
 'monthly',(select coalesce(jsonb_agg(jsonb_build_object('month',to_char(g.month,'MM'),'loans',coalesce(l.total,0),'payments',coalesce(p.total,0)) order by g.month),'[]'::jsonb) from generate_series((date_trunc('month',now() at time zone 'America/Sao_Paulo')-interval '5 months')::date,date_trunc('month',now() at time zone 'America/Sao_Paulo')::date,interval '1 month') as g(month) left join lateral(select sum(m.amount) total from public.ledger_movements m where m.tenant_id=p_tenant and m.kind='loan_disbursement' and date_trunc('month',m.occurred_at at time zone 'America/Sao_Paulo')=g.month) l on true left join lateral(select sum(m.amount) total from public.ledger_movements m where m.tenant_id=p_tenant and m.kind='payment' and date_trunc('month',m.occurred_at at time zone 'America/Sao_Paulo')=g.month) p on true)
 ) into v_out;return v_out;end $$;
