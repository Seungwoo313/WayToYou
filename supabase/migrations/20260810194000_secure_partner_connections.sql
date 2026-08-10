-- WayToYou partner profiles, one-time invitations, and one-to-one connections.
-- Clients never read these tables directly. Authenticated users can only use the
-- narrow RPC functions below, which return their own connection state.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.wty_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  city_id text not null check (
    city_id = any (array[
      'seoul', 'tokyo', 'shanghai', 'singapore', 'jakarta', 'hanoi', 'dubai',
      'berlin', 'paris', 'lisbon', 'london', 'new-york', 'toronto',
      'los-angeles', 'vancouver', 'sydney', 'melbourne'
    ])
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.wty_connections (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table if not exists public.wty_connection_members (
  connection_id uuid not null references public.wty_connections(id) on delete cascade,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (connection_id, user_id)
);

create table if not exists public.wty_connection_invites (
  id uuid primary key default gen_random_uuid(),
  code_hash bytea not null unique,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  claimed_by uuid references auth.users(id) on delete set null,
  claimed_at timestamptz,
  check ((claimed_by is null) = (claimed_at is null))
);

create index if not exists wty_connection_invites_creator_idx
  on public.wty_connection_invites (created_by, expires_at desc);

create table if not exists public.wty_connection_attempt_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  attempt_count integer not null check (attempt_count >= 0)
);

alter table public.wty_profiles enable row level security;
alter table public.wty_connections enable row level security;
alter table public.wty_connection_members enable row level security;
alter table public.wty_connection_invites enable row level security;
alter table public.wty_connection_attempt_limits enable row level security;

revoke all on table public.wty_profiles from anon, authenticated;
revoke all on table public.wty_connections from anon, authenticated;
revoke all on table public.wty_connection_members from anon, authenticated;
revoke all on table public.wty_connection_invites from anon, authenticated;
revoke all on table public.wty_connection_attempt_limits from anon, authenticated;

create or replace function public.wty_connection_state_for(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me public.wty_profiles%rowtype;
  v_partner public.wty_profiles%rowtype;
  v_connection public.wty_connections%rowtype;
  v_invite public.wty_connection_invites%rowtype;
begin
  select * into v_me
  from public.wty_profiles
  where id = p_user_id;

  select c.* into v_connection
  from public.wty_connections c
  join public.wty_connection_members mine on mine.connection_id = c.id
  where mine.user_id = p_user_id
  limit 1;

  if v_connection.id is not null then
    select p.* into v_partner
    from public.wty_connection_members member
    join public.wty_profiles p on p.id = member.user_id
    where member.connection_id = v_connection.id
      and member.user_id <> p_user_id
    limit 1;

    return jsonb_build_object(
      'status', 'connected',
      'connection_id', v_connection.id,
      'connected_at', v_connection.created_at,
      'me', case when v_me.id is null then null else jsonb_build_object(
        'id', v_me.id,
        'display_name', v_me.display_name,
        'city_id', v_me.city_id
      ) end,
      'partner', case when v_partner.id is null then null else jsonb_build_object(
        'id', v_partner.id,
        'display_name', v_partner.display_name,
        'city_id', v_partner.city_id
      ) end
    );
  end if;

  select * into v_invite
  from public.wty_connection_invites
  where created_by = p_user_id
    and claimed_at is null
    and expires_at > now()
  order by created_at desc
  limit 1;

  return jsonb_build_object(
    'status', case when v_invite.id is null then 'not_connected' else 'inviting' end,
    'me', case when v_me.id is null then null else jsonb_build_object(
      'id', v_me.id,
      'display_name', v_me.display_name,
      'city_id', v_me.city_id
    ) end,
    'invite_id', v_invite.id,
    'invite_expires_at', v_invite.expires_at
  );
end;
$$;

revoke all on function public.wty_connection_state_for(uuid) from public, anon, authenticated;

create or replace function public.wty_get_connection_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return public.wty_connection_state_for(v_user_id);
end;
$$;

create or replace function public.wty_save_profile(p_display_name text, p_city_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_name text := btrim(p_display_name);
  v_profile public.wty_profiles%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception using errcode = '22023', message = 'invalid_display_name';
  end if;
  if p_city_id is null or p_city_id <> all (array[
    'seoul', 'tokyo', 'shanghai', 'singapore', 'jakarta', 'hanoi', 'dubai',
    'berlin', 'paris', 'lisbon', 'london', 'new-york', 'toronto',
    'los-angeles', 'vancouver', 'sydney', 'melbourne'
  ]) then
    raise exception using errcode = '22023', message = 'invalid_city';
  end if;

  insert into public.wty_profiles (id, display_name, city_id)
  values (v_user_id, v_name, p_city_id)
  on conflict (id) do update
    set display_name = excluded.display_name,
        city_id = excluded.city_id,
        updated_at = now()
  returning * into v_profile;

  return jsonb_build_object(
    'id', v_profile.id,
    'display_name', v_profile.display_name,
    'city_id', v_profile.city_id
  );
end;
$$;

create or replace function public.wty_create_invite()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := '';
  v_alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_random bytea;
  v_invite public.wty_connection_invites%rowtype;
  v_attempt integer := 0;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));
  if not exists (select 1 from public.wty_profiles where id = v_user_id) then
    raise exception using errcode = '22023', message = 'profile_required';
  end if;
  if exists (select 1 from public.wty_connection_members where user_id = v_user_id) then
    raise exception using errcode = '23505', message = 'already_connected';
  end if;

  update public.wty_connection_invites
  set expires_at = now()
  where created_by = v_user_id
    and claimed_at is null
    and expires_at > now();

  loop
    v_attempt := v_attempt + 1;
    v_random := extensions.gen_random_bytes(8);
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, (get_byte(v_random, i) % char_length(v_alphabet)) + 1, 1);
    end loop;

    begin
      insert into public.wty_connection_invites (
        code_hash, created_by, expires_at
      ) values (
        extensions.digest(convert_to(v_code, 'UTF8'), 'sha256'),
        v_user_id,
        now() + interval '24 hours'
      ) returning * into v_invite;
      exit;
    exception when unique_violation then
      if v_attempt >= 5 then
        raise exception using errcode = '55000', message = 'invite_generation_failed';
      end if;
    end;
  end loop;

  return jsonb_build_object(
    'id', v_invite.id,
    'code', v_code,
    'created_by_id', v_invite.created_by,
    'created_at', v_invite.created_at,
    'expires_at', v_invite.expires_at
  );
end;
$$;

create or replace function public.wty_cancel_invite(p_invite_id uuid)
returns jsonb
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

  update public.wty_connection_invites
  set expires_at = now()
  where id = p_invite_id
    and created_by = v_user_id
    and claimed_at is null;

  return public.wty_connection_state_for(v_user_id);
end;
$$;

create or replace function public.wty_accept_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_attempt_count integer;
  v_invite public.wty_connection_invites%rowtype;
  v_invite_id uuid;
  v_creator_id uuid;
  v_connection_id uuid;
  v_first_lock text;
  v_second_lock text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if not exists (select 1 from public.wty_profiles where id = v_user_id) then
    return jsonb_build_object('error', 'profile_required');
  end if;
  if exists (select 1 from public.wty_connection_members where user_id = v_user_id) then
    return jsonb_build_object('error', 'already_connected');
  end if;

  insert into public.wty_connection_attempt_limits (
    user_id, window_started_at, attempt_count
  ) values (
    v_user_id, now(), 1
  )
  on conflict (user_id) do update set
    window_started_at = case
      when public.wty_connection_attempt_limits.window_started_at < now() - interval '10 minutes'
        then now()
      else public.wty_connection_attempt_limits.window_started_at
    end,
    attempt_count = case
      when public.wty_connection_attempt_limits.window_started_at < now() - interval '10 minutes'
        then 1
      else public.wty_connection_attempt_limits.attempt_count + 1
    end
  returning attempt_count into v_attempt_count;

  if v_attempt_count > 12 then
    return jsonb_build_object('error', 'rate_limited');
  end if;
  if char_length(v_code) <> 8 then
    return jsonb_build_object('error', 'invalid_code');
  end if;

  select id, created_by into v_invite_id, v_creator_id
  from public.wty_connection_invites
  where code_hash = extensions.digest(convert_to(v_code, 'UTF8'), 'sha256')
    and claimed_at is null
    and expires_at > now()
  limit 1;

  if v_invite_id is null or v_creator_id = v_user_id then
    return jsonb_build_object('error', 'invalid_code');
  end if;

  v_first_lock := least(v_user_id::text, v_creator_id::text);
  v_second_lock := greatest(v_user_id::text, v_creator_id::text);
  perform pg_advisory_xact_lock(hashtextextended(v_first_lock, 0));
  perform pg_advisory_xact_lock(hashtextextended(v_second_lock, 0));

  select * into v_invite
  from public.wty_connection_invites
  where id = v_invite_id
    and claimed_at is null
    and expires_at > now()
  limit 1
  for update;

  if v_invite.id is null then
    return jsonb_build_object('error', 'invalid_code');
  end if;

  if exists (
    select 1 from public.wty_connection_members
    where user_id in (v_user_id, v_creator_id)
  ) then
    return jsonb_build_object('error', 'already_connected');
  end if;

  insert into public.wty_connections default values
  returning id into v_connection_id;

  insert into public.wty_connection_members (connection_id, user_id)
  values
    (v_connection_id, v_creator_id),
    (v_connection_id, v_user_id);

  update public.wty_connection_invites
  set claimed_by = v_user_id,
      claimed_at = now()
  where id = v_invite.id;

  update public.wty_connection_invites
  set expires_at = now()
  where claimed_at is null
    and expires_at > now()
    and created_by in (v_user_id, v_creator_id);

  delete from public.wty_connection_attempt_limits where user_id = v_user_id;

  return public.wty_connection_state_for(v_user_id);
end;
$$;

revoke all on function public.wty_get_connection_state() from public, anon;
revoke all on function public.wty_save_profile(text, text) from public, anon;
revoke all on function public.wty_create_invite() from public, anon;
revoke all on function public.wty_cancel_invite(uuid) from public, anon;
revoke all on function public.wty_accept_invite(text) from public, anon;

grant execute on function public.wty_get_connection_state() to authenticated;
grant execute on function public.wty_save_profile(text, text) to authenticated;
grant execute on function public.wty_create_invite() to authenticated;
grant execute on function public.wty_cancel_invite(uuid) to authenticated;
grant execute on function public.wty_accept_invite(text) to authenticated;
