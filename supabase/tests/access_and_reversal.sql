\set ON_ERROR_STOP on
begin;
insert into auth.users(id,aud,role,email,created_at,updated_at) values
('11111111-1111-4111-8111-111111111111','authenticated','authenticated','admin-test@example.invalid',now(),now()),
('11111111-1111-4111-8111-111111111112','authenticated','authenticated','collector-test@example.invalid',now(),now());
insert into public.tenants(id,name,state,approved_at) values('22222222-2222-4222-8222-222222222222','Teste A','approved',now()),('22222222-2222-4222-8222-222222222223','Teste B','approved',now());
insert into public.memberships(tenant_id,user_id,role) values('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','tenant_admin'),('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111112','collector');
insert into public.clients(id,tenant_id,full_name,cpf) values('33333333-3333-4333-8333-333333333331','22222222-2222-4222-8222-222222222222','Atribuído','52998224725'),('33333333-3333-4333-8333-333333333332','22222222-2222-4222-8222-222222222222','Não atribuído','11144477735'),('33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222223','Outra empresa','52998224725');
insert into public.collector_assignments(tenant_id,client_id,collector_user_id) values('22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333331','11111111-1111-4111-8111-111111111112');
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
set local role authenticated;
do $$ declare t uuid:='22222222-2222-4222-8222-222222222222';m uuid;e uuid;v uuid;duplicate uuid;n numeric;begin
 if (select count(*) from public.clients)<>2 then raise exception 'tenant_isolation_failed';end if;
 select id into m from public.memberships where tenant_id=t and user_id=auth.uid();
 begin perform public.update_tenant_membership(t,m,false);raise exception 'last_admin_not_protected';exception when others then if SQLERRM<>'last_admin' then raise;end if;end;
 begin perform public.master_user_directory();raise exception 'global_directory_exposed';exception when insufficient_privilege then null;end;
 e:=public.create_expense_atomic(t,'Teste',5,current_date,'teste','expense-security-001');
 select ledger_movement_id into m from public.expenses where id=e;
 v:=public.reverse_cash_movement(t,m,'Corrigir despesa');duplicate:=public.reverse_cash_movement(t,m,'Repetição');
 if v<>duplicate then raise exception 'cash_reversal_not_idempotent';end if;
 select sum(amount*direction) into n from public.ledger_movements where tenant_id=t;if n<>0 then raise exception 'cash_reversal_balance_mismatch';end if;
 if not exists(select 1 from public.expenses where id=e and reversed_at is not null) then raise exception 'expense_status_not_reconciled';end if;
end $$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111112',true);
do $$ begin
 if (select count(*) from public.clients)<>1 then raise exception 'collector_scope_failed';end if;
 if exists(select 1 from public.clients where id='33333333-3333-4333-8333-333333333332') then raise exception 'unassigned_client_exposed';end if;
 begin perform public.create_cash_adjustment('22222222-2222-4222-8222-222222222222',10,1::smallint,now(),'proibido','collector-cash-001');raise exception 'collector_finance_allowed';exception when insufficient_privilege then null;end;
 raise notice 'PASS: tenant isolation, collector scope, last admin, master authorization, cash reversal';
end $$;
reset role;
rollback;
