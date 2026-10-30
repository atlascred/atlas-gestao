-- Superadmins are independent of any tenant so suspending a company cannot remove global access.
create table public.global_admins(user_id uuid primary key references auth.users(id) on delete cascade,created_at timestamptz not null default now(),created_by uuid references auth.users(id) on delete set null);
alter table public.global_admins enable row level security;
create policy global_admins_read on public.global_admins for select to authenticated using(public.is_master_admin());
create or replace function public.is_master_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.global_admins ga where ga.user_id=auth.uid());$$;
revoke all on function public.is_master_admin() from public;
grant execute on function public.is_master_admin() to authenticated;
