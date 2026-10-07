-- Any2Any production hardening for Supabase.
-- Safe to run after 20261007000000_any2any.sql.

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Make the conversion counter a single logical global counter.
alter table public.converts_counters
  add column if not exists scope text;

do $$
declare
  total bigint;
  keep_id bigint;
begin
  update public.converts_counters
     set scope = 'legacy-' || id::text
   where scope is null;

  select coalesce(sum(count), 0), min(id)
    into total, keep_id
    from public.converts_counters;

  if keep_id is null then
    insert into public.converts_counters(scope, count)
    values ('global', 0);
  else
    update public.converts_counters
       set scope = 'global',
           count = total,
           updated_at = now()
     where id = keep_id;

    delete from public.converts_counters
     where id <> keep_id;
  end if;
end $$;

alter table public.converts_counters
  alter column scope set not null;

create unique index if not exists converts_counters_scope_uidx
  on public.converts_counters(scope);

insert into public.converts_counters(scope, count)
values ('global', 0)
on conflict (scope) do nothing;

create or replace function public.increment_convert_counter()
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  new_count bigint;
begin
  insert into public.converts_counters(scope, count)
  values ('global', 1)
  on conflict (scope)
  do update set
    count = public.converts_counters.count + 1,
    updated_at = now()
  returning count into new_count;

  return new_count;
end;
$$;

revoke all on function public.increment_convert_counter() from public;
grant execute on function public.increment_convert_counter() to anon, authenticated;

-- The counter must not be directly writable by clients.
drop policy if exists "counter insert" on public.converts_counters;
drop policy if exists "counter select" on public.converts_counters;
create policy "admin read counters"
  on public.converts_counters
  for select
  to authenticated
  using (public.is_admin());

revoke all on public.converts_counters from anon;
revoke insert, update, delete on public.converts_counters from authenticated;
grant select on public.converts_counters to authenticated;

-- Avoid RLS recursion and protect the auth trigger.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles(id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', new.email, 'User')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public;

-- Replace admin policies with the stable zero-argument helper.
drop policy if exists "admin profiles read" on public.profiles;
create policy "admin profiles read"
  on public.profiles
  for select
  to authenticated
  using (public.is_admin());

drop policy if exists "admin manage formats" on public.converter_formats;
create policy "admin manage formats"
  on public.converter_formats
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admin manage pages" on public.pages;
create policy "admin manage pages"
  on public.pages
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admin manage posts" on public.posts;
create policy "admin manage posts"
  on public.posts
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admin conversions" on public.conversions;
create policy "admin conversions"
  on public.conversions
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Keep conversion updates limited to server-created rows and their owner/admin.
drop policy if exists "users update own conversions" on public.conversions;
create policy "users update own conversions"
  on public.conversions
  for update
  to authenticated
  using ((select auth.uid()) = user_id or public.is_admin())
  with check ((select auth.uid()) = user_id or public.is_admin());

-- Ensure realtime remains enabled for operational tables.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='converter_formats'
  ) then
    alter publication supabase_realtime add table public.converter_formats;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='conversions'
  ) then
    alter publication supabase_realtime add table public.conversions;
  end if;
end $$;
