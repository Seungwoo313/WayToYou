-- A person's profile location is a MapKit city. Airports are stored separately
-- as reusable delivery defaults, and future parcels will copy them as route snapshots.

alter table public.wty_profiles
  add column if not exists city jsonb,
  add column if not exists default_airport jsonb;

update public.wty_profiles
set city = coalesce(city, route_endpoint -> 'city'),
    default_airport = coalesce(default_airport, route_endpoint -> 'airport');

do $$
begin
  if exists (
    select 1
    from public.wty_profiles
    where city is null or default_airport is null
  ) then
    raise exception 'profile_city_or_default_airport_migration_incomplete';
  end if;
end;
$$;

alter table public.wty_profiles
  alter column city set not null,
  alter column default_airport set not null;

alter table public.wty_profiles
  drop constraint if exists wty_profiles_city_check,
  drop constraint if exists wty_profiles_default_airport_check;

alter table public.wty_profiles
  add constraint wty_profiles_city_check check (
    jsonb_typeof(city) = 'object'
    and nullif(btrim(city ->> 'id'), '') is not null
    and nullif(btrim(city ->> 'name'), '') is not null
    and jsonb_typeof(city -> 'latitude') = 'number'
    and jsonb_typeof(city -> 'longitude') = 'number'
    and nullif(btrim(city ->> 'timeZoneID'), '') is not null
  ),
  add constraint wty_profiles_default_airport_check check (
    jsonb_typeof(default_airport) = 'object'
    and nullif(btrim(default_airport ->> 'id'), '') is not null
    and nullif(btrim(default_airport ->> 'name'), '') is not null
    and jsonb_typeof(default_airport -> 'latitude') = 'number'
    and jsonb_typeof(default_airport -> 'longitude') = 'number'
    and (
      default_airport -> 'code' is null
      or jsonb_typeof(default_airport -> 'code') = 'null'
      or (
        jsonb_typeof(default_airport -> 'code') = 'string'
        and char_length(default_airport ->> 'code') = 3
      )
    )
  );

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
        'city', v_me.city,
        'default_airport', v_me.default_airport,
        'avatar_path', v_me.avatar_path,
        'avatar_updated_at', v_me.avatar_updated_at
      ) end,
      'partner', case when v_partner.id is null then null else jsonb_build_object(
        'id', v_partner.id,
        'display_name', v_partner.display_name,
        'city', v_partner.city,
        'default_airport', v_partner.default_airport,
        'avatar_path', v_partner.avatar_path,
        'avatar_updated_at', v_partner.avatar_updated_at
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
      'city', v_me.city,
      'default_airport', v_me.default_airport,
      'avatar_path', v_me.avatar_path,
      'avatar_updated_at', v_me.avatar_updated_at
    ) end,
    'invite_id', v_invite.id,
    'invite_expires_at', v_invite.expires_at
  );
end;
$$;

drop function if exists public.wty_save_profile(text, text);
drop function if exists public.wty_save_profile(text, jsonb);

create function public.wty_save_profile(
  p_display_name text,
  p_city jsonb,
  p_default_airport jsonb
)
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
  if jsonb_typeof(p_city) <> 'object'
     or nullif(btrim(p_city ->> 'id'), '') is null
     or nullif(btrim(p_city ->> 'name'), '') is null
     or jsonb_typeof(p_city -> 'latitude') <> 'number'
     or jsonb_typeof(p_city -> 'longitude') <> 'number'
     or nullif(btrim(p_city ->> 'timeZoneID'), '') is null then
    raise exception using errcode = '22023', message = 'invalid_city';
  end if;
  if jsonb_typeof(p_default_airport) <> 'object'
     or nullif(btrim(p_default_airport ->> 'id'), '') is null
     or nullif(btrim(p_default_airport ->> 'name'), '') is null
     or jsonb_typeof(p_default_airport -> 'latitude') <> 'number'
     or jsonb_typeof(p_default_airport -> 'longitude') <> 'number' then
    raise exception using errcode = '22023', message = 'invalid_airport';
  end if;

  insert into public.wty_profiles (
    id,
    display_name,
    city,
    default_airport
  ) values (
    v_user_id,
    v_name,
    p_city,
    p_default_airport
  )
  on conflict (id) do update
    set display_name = excluded.display_name,
        city = excluded.city,
        default_airport = excluded.default_airport,
        updated_at = now()
  returning * into v_profile;

  return jsonb_build_object(
    'id', v_profile.id,
    'display_name', v_profile.display_name,
    'city', v_profile.city,
    'default_airport', v_profile.default_airport,
    'avatar_path', v_profile.avatar_path,
    'avatar_updated_at', v_profile.avatar_updated_at
  );
end;
$$;

create or replace function public.wty_set_profile_avatar()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_expected_path text;
  v_object_updated_at timestamptz;
  v_profile public.wty_profiles%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if not exists (select 1 from public.wty_profiles where id = v_user_id) then
    raise exception using errcode = '22023', message = 'profile_required';
  end if;

  v_expected_path := v_user_id::text || '/avatar.jpg';
  select object.updated_at into v_object_updated_at
  from storage.objects object
  where object.bucket_id = 'wty-profile-photos'
    and object.name = v_expected_path
    and object.owner_id = v_user_id::text
  limit 1;

  if not found then
    raise exception using errcode = '22023', message = 'avatar_upload_required';
  end if;

  update public.wty_profiles
  set avatar_path = v_expected_path,
      avatar_updated_at = coalesce(v_object_updated_at, now()),
      updated_at = now()
  where id = v_user_id
  returning * into v_profile;

  return jsonb_build_object(
    'id', v_profile.id,
    'display_name', v_profile.display_name,
    'city', v_profile.city,
    'default_airport', v_profile.default_airport,
    'avatar_path', v_profile.avatar_path,
    'avatar_updated_at', v_profile.avatar_updated_at
  );
end;
$$;

create or replace function public.wty_clear_profile_avatar()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.wty_profiles%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  update public.wty_profiles
  set avatar_path = null,
      avatar_updated_at = null,
      updated_at = now()
  where id = v_user_id
  returning * into v_profile;

  if not found then
    raise exception using errcode = '22023', message = 'profile_required';
  end if;

  return jsonb_build_object(
    'id', v_profile.id,
    'display_name', v_profile.display_name,
    'city', v_profile.city,
    'default_airport', v_profile.default_airport,
    'avatar_path', v_profile.avatar_path,
    'avatar_updated_at', v_profile.avatar_updated_at
  );
end;
$$;

alter table public.wty_profiles
  drop column route_endpoint,
  drop column city_id;

revoke all on function public.wty_save_profile(text, jsonb, jsonb) from public, anon;
grant execute on function public.wty_save_profile(text, jsonb, jsonb) to authenticated;
