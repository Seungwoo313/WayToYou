-- Signal is a lightweight current-state event shared only inside one connection.
-- Clients use security-definer RPCs and never access the backing table directly.

create table if not exists public.wty_signals (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.wty_connections(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  signal_type text not null check (
    signal_type = any (array['sleeping', 'focusing', 'free', 'out', 'resting'])
  ),
  sent_at timestamptz not null default now()
);

create index if not exists wty_signals_connection_sent_idx
  on public.wty_signals (connection_id, sent_at desc);

alter table public.wty_signals enable row level security;
revoke all on table public.wty_signals from anon, authenticated;

create or replace function public.wty_send_signal(p_signal_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_connection_id uuid;
  v_signal_type text := lower(btrim(p_signal_type));
  v_signal public.wty_signals%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if v_signal_type is null or v_signal_type <> all (
    array['sleeping', 'focusing', 'free', 'out', 'resting']
  ) then
    raise exception using errcode = '22023', message = 'invalid_signal_type';
  end if;

  select member.connection_id into v_connection_id
  from public.wty_connection_members member
  where member.user_id = v_user_id
  limit 1;

  if v_connection_id is null then
    raise exception using errcode = '22023', message = 'connection_required';
  end if;

  insert into public.wty_signals (connection_id, sender_id, signal_type)
  values (v_connection_id, v_user_id, v_signal_type)
  returning * into v_signal;

  return jsonb_build_object(
    'id', v_signal.id,
    'sender_id', v_signal.sender_id,
    'signal_type', v_signal.signal_type,
    'sent_at', v_signal.sent_at
  );
end;
$$;

create or replace function public.wty_list_signals(p_limit integer default 80)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_connection_id uuid;
  v_limit integer := least(greatest(coalesce(p_limit, 80), 1), 120);
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select member.connection_id into v_connection_id
  from public.wty_connection_members member
  where member.user_id = v_user_id
  limit 1;

  if v_connection_id is null then
    raise exception using errcode = '22023', message = 'connection_required';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', recent.id,
        'sender_id', recent.sender_id,
        'signal_type', recent.signal_type,
        'sent_at', recent.sent_at
      ) order by recent.sent_at
    ),
    '[]'::jsonb
  ) into v_result
  from (
    select signal.id, signal.sender_id, signal.signal_type, signal.sent_at
    from public.wty_signals signal
    where signal.connection_id = v_connection_id
    order by signal.sent_at desc
    limit v_limit
  ) recent;

  return v_result;
end;
$$;

revoke all on function public.wty_send_signal(text) from public, anon;
revoke all on function public.wty_list_signals(integer) from public, anon;
grant execute on function public.wty_send_signal(text) to authenticated;
grant execute on function public.wty_list_signals(integer) to authenticated;
