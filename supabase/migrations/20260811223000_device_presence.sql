-- Device Presence: 연결된 상대에게만 보이는 기기 배터리 상태.
-- 정확한 배터리 수치는 생활 패턴을 드러낼 수 있으므로 현재 연결 상대 외에는 읽을 수 없다.
-- 클라이언트는 테이블에 직접 접근하지 않고 아래 security-definer RPC만 사용한다.
-- 클라이언트는 user id, connection id, timestamp를 지정할 수 없다. 시각은 항상 서버 now()다.

create table if not exists public.wty_device_presence (
  connection_id uuid not null,
  user_id uuid primary key references auth.users(id) on delete cascade,
  battery_level integer not null check (battery_level between 0 and 100),
  battery_state text not null check (
    battery_state = any (array['charging', 'full', 'unplugged'])
  ),
  updated_at timestamptz not null default now(),
  foreign key (connection_id, user_id)
    references public.wty_connection_members(connection_id, user_id)
    on delete cascade
);

create index if not exists wty_device_presence_connection_idx
  on public.wty_device_presence (connection_id);

alter table public.wty_device_presence enable row level security;
revoke all on table public.wty_device_presence from anon, authenticated;

create or replace function public.wty_set_device_presence(
  p_battery_level integer,
  p_battery_state text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_connection_id uuid;
  v_state text := lower(btrim(p_battery_state));
  v_row public.wty_device_presence%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_battery_level is null or p_battery_level < 0 or p_battery_level > 100 then
    raise exception using errcode = '22023', message = 'invalid_battery_level';
  end if;
  if v_state is null or v_state <> all (array['charging', 'full', 'unplugged']) then
    raise exception using errcode = '22023', message = 'invalid_battery_state';
  end if;
  select member.connection_id into v_connection_id
  from public.wty_connection_members member
  where member.user_id = v_user_id
  limit 1;

  if v_connection_id is null then
    raise exception using errcode = '22023', message = 'connection_required';
  end if;

  insert into public.wty_device_presence as presence (
    connection_id,
    user_id,
    battery_level,
    battery_state,
    updated_at
  )
  values (v_connection_id, v_user_id, p_battery_level, v_state, now())
  on conflict (user_id) do update
    set connection_id = excluded.connection_id,
        battery_level = excluded.battery_level,
        battery_state = excluded.battery_state,
        updated_at = now()
    where presence.connection_id is distinct from excluded.connection_id
       or presence.battery_level is distinct from excluded.battery_level
       or presence.battery_state is distinct from excluded.battery_state
       or presence.updated_at <= now() - interval '5 minutes'
  returning * into v_row;

  -- 서버 throttle로 write를 건너뛴 경우에도 현재 서버 값을 반환한다.
  if not found then
    select * into v_row
    from public.wty_device_presence presence
    where presence.user_id = v_user_id;
  end if;

  return jsonb_build_object(
    'battery_level', v_row.battery_level,
    'battery_state', v_row.battery_state,
    'updated_at', v_row.updated_at
  );
end;
$$;

create or replace function public.wty_get_partner_presence()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_connection_id uuid;
  v_partner_id uuid;
  v_row public.wty_device_presence%rowtype;
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

  select member.user_id into v_partner_id
  from public.wty_connection_members member
  where member.connection_id = v_connection_id
    and member.user_id <> v_user_id
  limit 1;

  if v_partner_id is not null then
    select * into v_row
    from public.wty_device_presence presence
    where presence.connection_id = v_connection_id
      and presence.user_id = v_partner_id;
  end if;

  return jsonb_build_object(
    'presence',
    case when v_row.user_id is null then null else jsonb_build_object(
      'battery_level', v_row.battery_level,
      'battery_state', v_row.battery_state,
      'updated_at', v_row.updated_at
    ) end
  );
end;
$$;

create or replace function public.wty_clear_device_presence()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  delete from public.wty_device_presence where user_id = v_user_id;
end;
$$;

revoke all on function public.wty_set_device_presence(integer, text) from public, anon;
revoke all on function public.wty_get_partner_presence() from public, anon;
revoke all on function public.wty_clear_device_presence() from public, anon;

grant execute on function public.wty_set_device_presence(integer, text) to authenticated;
grant execute on function public.wty_get_partner_presence() to authenticated;
grant execute on function public.wty_clear_device_presence() to authenticated;
