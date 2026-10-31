create or replace function public.dashboard_period_summary(p_tenant uuid,p_from date,p_to date)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare result jsonb;
begin
 if not public.has_tenant_permission(p_tenant,'dashboard.read') then raise exception 'not_authorized' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>1826 then raise exception 'invalid_period' using errcode='22023';end if;
 select jsonb_build_object(
  'from',p_from,
  'to',p_to,
  'cashIn',coalesce((select sum(m.amount*m.direction) from public.ledger_movements m where m.tenant_id=p_tenant and m.kind in ('payment','reversal') and m.reference_table='payments' and (m.occurred_at at time zone 'America/Sao_Paulo')::date between p_from and p_to),0),
  'cashOut',coalesce((select sum(case when m.kind='reversal' then case when original.direction=-1 then -m.amount else 0 end when m.direction=-1 then m.amount else 0 end) from public.ledger_movements m left join public.ledger_movements original on original.id=m.reversed_movement_id and original.tenant_id=m.tenant_id where m.tenant_id=p_tenant and (m.occurred_at at time zone 'America/Sao_Paulo')::date between p_from and p_to),0),
  'expenses',coalesce((select sum(case when m.kind='expense' then m.amount when m.kind='reversal' and original.kind='expense' then -m.amount else 0 end) from public.ledger_movements m left join public.ledger_movements original on original.id=m.reversed_movement_id and original.tenant_id=m.tenant_id where m.tenant_id=p_tenant and m.reference_table='expenses' and (m.occurred_at at time zone 'America/Sao_Paulo')::date between p_from and p_to),0),
  'monthly',(select coalesce(jsonb_agg(jsonb_build_object('month',to_char(g.month,'YYYY-MM'),'loans',coalesce(l.total,0),'payments',coalesce(p.total,0)) order by g.month),'[]'::jsonb)
   from generate_series(date_trunc('month',p_from::timestamp),date_trunc('month',p_to::timestamp),interval '1 month') as g(month)
   left join lateral(select sum(m.amount) total from public.ledger_movements m where m.tenant_id=p_tenant and m.kind='loan_disbursement' and date_trunc('month',m.occurred_at at time zone 'America/Sao_Paulo')=g.month and (m.occurred_at at time zone 'America/Sao_Paulo')::date between p_from and p_to) l on true
   left join lateral(select sum(m.amount*m.direction) total from public.ledger_movements m where m.tenant_id=p_tenant and m.kind in ('payment','reversal') and m.reference_table='payments' and date_trunc('month',m.occurred_at at time zone 'America/Sao_Paulo')=g.month and (m.occurred_at at time zone 'America/Sao_Paulo')::date between p_from and p_to) p on true)
 ) into result;
 return result;
end $$;
revoke all on function public.dashboard_period_summary(uuid,date,date) from public;
grant execute on function public.dashboard_period_summary(uuid,date,date) to authenticated;
