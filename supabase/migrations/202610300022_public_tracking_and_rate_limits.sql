alter table public.tenant_applications add column if not exists status_token_hash text;
create unique index if not exists tenant_applications_status_token_hash_idx
 on public.tenant_applications(status_token_hash) where status_token_hash is not null;

create table if not exists public.api_rate_limits(
 key_hash text primary key,
 window_started_at timestamptz not null,
 hit_count integer not null check(hit_count>0)
);
alter table public.api_rate_limits enable row level security;
revoke all on public.api_rate_limits from anon,authenticated;

create or replace function public.consume_api_rate_limit(p_key_hash text,p_limit integer,p_window_seconds integer)
returns boolean language plpgsql security definer set search_path=public as $$
declare current_hits integer;
begin
 if length(p_key_hash)<>64 or p_limit<1 or p_limit>100 or p_window_seconds<1 or p_window_seconds>86400 then
  raise exception 'invalid_rate_limit_arguments';
 end if;
 insert into public.api_rate_limits(key_hash,window_started_at,hit_count)
 values(p_key_hash,now(),1)
 on conflict(key_hash) do update set
  window_started_at=case when api_rate_limits.window_started_at<=now()-make_interval(secs=>p_window_seconds) then now() else api_rate_limits.window_started_at end,
  hit_count=case when api_rate_limits.window_started_at<=now()-make_interval(secs=>p_window_seconds) then 1 else api_rate_limits.hit_count+1 end
 returning hit_count into current_hits;
 if random()<0.02 then delete from public.api_rate_limits where window_started_at<now()-interval '1 day'; end if;
 return current_hits<=p_limit;
end $$;
revoke all on function public.consume_api_rate_limit(text,integer,integer) from public,anon,authenticated;
grant execute on function public.consume_api_rate_limit(text,integer,integer) to service_role;

create or replace function public.lookup_tenant_application(p_status_token_hash text)
returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object('companyName',company_name,'status',status,'submittedAt',submitted_at,'reviewedAt',reviewed_at,'reviewNote',review_note)
 from public.tenant_applications where status_token_hash=p_status_token_hash limit 1
$$;
revoke all on function public.lookup_tenant_application(text) from public,anon,authenticated;
grant execute on function public.lookup_tenant_application(text) to service_role;
