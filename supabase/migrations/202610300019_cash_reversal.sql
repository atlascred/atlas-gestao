alter table public.expenses add column reversed_at timestamptz;
create function public.reverse_cash_movement(p_tenant uuid,p_movement uuid,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare m public.ledger_movements%rowtype;existing uuid;new_id uuid;begin
 if not public.has_tenant_role(p_tenant,array['tenant_admin']::public.member_role[]) then raise exception 'not_authorized' using errcode='42501';end if;
 if length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'invalid_reason';end if;
 select * into m from public.ledger_movements where id=p_movement and tenant_id=p_tenant for update;
 if not found or m.kind not in ('expense','adjustment') then raise exception 'use_payment_reversal_or_invalid_movement';end if;
 select id into existing from public.ledger_movements where tenant_id=p_tenant and reversed_movement_id=m.id;if found then return existing;end if;
 insert into public.ledger_movements(tenant_id,kind,amount,direction,reference_table,reference_id,description,idempotency_key,created_by,reversed_movement_id) values(p_tenant,'reversal',m.amount,-m.direction,m.reference_table,m.reference_id,'Estorno: '||trim(p_reason),'cash-reversal:'||m.id,auth.uid(),m.id) returning id into new_id;
 if m.kind='expense' then update public.expenses set reversed_at=now() where id=m.reference_id and tenant_id=p_tenant;end if;
 insert into public.audit_log(tenant_id,actor_id,action,entity,entity_id,metadata) values(p_tenant,auth.uid(),'cash.reversed','ledger_movements',m.id,jsonb_build_object('reversal_id',new_id,'reason',trim(p_reason)));return new_id;
end $$;
revoke all on function public.reverse_cash_movement(uuid,uuid,text) from public;
grant execute on function public.reverse_cash_movement(uuid,uuid,text) to authenticated;
