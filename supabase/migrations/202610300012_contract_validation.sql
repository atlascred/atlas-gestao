-- RPC callers cannot bypass monetary invariants by providing a forged payload.
create or replace function public.validate_loan_terms() returns trigger
language plpgsql set search_path=public as $$
begin
 if new.interest_percent<0 or new.interest_percent>1000 then raise exception 'invalid_interest_rate'; end if;
 if new.interest_amount<>round(new.principal*new.interest_percent/100,2) or new.total_amount<>new.principal+new.interest_amount then raise exception 'invalid_financial_totals'; end if;
 if new.installment_count>730 or new.installment_count<1 or (new.modality='monthly' and new.installment_count<>1) then raise exception 'invalid_installment_count'; end if;
 if new.total_amount*100<new.installment_count then raise exception 'installment_below_one_cent'; end if;
 if TG_OP='UPDATE' and (new.principal,new.interest_percent,new.interest_amount,new.total_amount,new.modality,new.start_date,new.installment_count,new.late_fee,new.late_fee_block_days,new.include_sundays) is distinct from (old.principal,old.interest_percent,old.interest_amount,old.total_amount,old.modality,old.start_date,old.installment_count,old.late_fee,old.late_fee_block_days,old.include_sundays) then raise exception 'contract_terms_immutable'; end if;
 return new;
end $$;
create trigger validate_loan_terms before insert or update on public.loans for each row execute function public.validate_loan_terms();
alter table public.installments add constraint paid_not_above_amount check(paid_amount<=amount);
-- Tenant relationships also cover collectors and ledger references.
create or replace function public.validate_collector_membership() returns trigger language plpgsql set search_path=public as $$
begin
 if not exists(select 1 from public.memberships where tenant_id=new.tenant_id and user_id=new.collector_user_id and active and role='collector') then raise exception 'collector_not_in_tenant'; end if;
 return new;
end $$;
create trigger collector_same_tenant before insert or update on public.collector_assignments for each row execute function public.validate_collector_membership();
