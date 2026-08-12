-- Rapid Heart taps are grouped into a single burst. The receiver replays the
-- stored count as individual floating hearts without read receipts or chat.

create table if not exists public.wty_heart_bursts (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.wty_connections(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  heart_count integer not null check (heart_count between 1 and 50),
  sent_at timestamptz not null default now()
);

create index if not exists wty_heart_bursts_connection_sent_idx
  on public.wty_heart_bursts (connection_id, sent_at desc);

alter table public.wty_heart_bursts enable row level security;
revoke all on table public.wty_heart_bursts from anon, authenticated;

create or replace function public.wty_send_heart_burst(p_count integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_connection_id uuid;
  v_count integer := least(greatest(coalesce(p_count, 0), 0), 50);
  v_burst public.wty_heart_bursts%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if v_count < 1 then
    raise exception using errcode = '22023', message = 'invalid_heart_count';
  end if;

  select member.connection_id into v_connection_id
  from public.wty_connection_members member
  where member.user_id = v_user_id
  limit 1;

  if v_connection_id is null then
    raise exception using errcode = '22023', message = 'connection_required';
  end if;

  insert into public.wty_heart_bursts (connection_id, sender_id, heart_count)
  values (v_connection_id, v_user_id, v_count)
  returning * into v_burst;

  return jsonb_build_object(
    'id', v_burst.id,
    'sender_id', v_burst.sender_id,
    'heart_count', v_burst.heart_count,
    'sent_at', v_burst.sent_at
  );
end;
$$;

create or replace function public.wty_list_heart_bursts(p_limit integer default 40)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_connection_id uuid;
  v_limit integer := least(greatest(coalesce(p_limit, 40), 1), 100);
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
        'heart_count', recent.heart_count,
        'sent_at', recent.sent_at
      ) order by recent.sent_at
    ),
    '[]'::jsonb
  ) into v_result
  from (
    select burst.id, burst.sender_id, burst.heart_count, burst.sent_at
    from public.wty_heart_bursts burst
    where burst.connection_id = v_connection_id
    order by burst.sent_at desc
    limit v_limit
  ) recent;

  return v_result;
end;
$$;

revoke all on function public.wty_send_heart_burst(integer) from public, anon;
revoke all on function public.wty_list_heart_bursts(integer) from public, anon;
grant execute on function public.wty_send_heart_burst(integer) to authenticated;
grant execute on function public.wty_list_heart_bursts(integer) to authenticated;
