-- Route endpoints come from MapKit. The database stores the selected city and
-- airport snapshot instead of validating against a hard-coded airport list.

alter table public.wty_profiles
  drop constraint if exists wty_profiles_city_id_check;

alter table public.wty_profiles
  add column if not exists route_endpoint jsonb;

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
        'route_endpoint', v_me.route_endpoint
      ) end,
      'partner', case when v_partner.id is null then null else jsonb_build_object(
        'id', v_partner.id,
        'display_name', v_partner.display_name,
        'route_endpoint', v_partner.route_endpoint
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
      'route_endpoint', v_me.route_endpoint
    ) end,
    'invite_id', v_invite.id,
    'invite_expires_at', v_invite.expires_at
  );
end;
$$;

create or replace function public.wty_save_profile(
  p_display_name text,
  p_route_endpoint jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_name text := btrim(p_display_name);
  v_city_id text := p_route_endpoint #>> '{city,id}';
  v_city_name text := p_route_endpoint #>> '{city,name}';
  v_airport_id text := p_route_endpoint #>> '{airport,id}';
  v_airport_name text := p_route_endpoint #>> '{airport,name}';
  v_profile public.wty_profiles%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception using errcode = '22023', message = 'invalid_display_name';
  end if;
  if jsonb_typeof(p_route_endpoint) <> 'object'
     or nullif(btrim(v_city_id), '') is null
     or nullif(btrim(v_city_name), '') is null then
    raise exception using errcode = '22023', message = 'invalid_city';
  end if;
  if nullif(btrim(v_airport_id), '') is null
     or nullif(btrim(v_airport_name), '') is null then
    raise exception using errcode = '22023', message = 'invalid_airport';
  end if;

  insert into public.wty_profiles (id, display_name, city_id, route_endpoint)
  values (v_user_id, v_name, v_city_id, p_route_endpoint)
  on conflict (id) do update
    set display_name = excluded.display_name,
        city_id = excluded.city_id,
        route_endpoint = excluded.route_endpoint,
        updated_at = now()
  returning * into v_profile;

  return jsonb_build_object(
    'id', v_profile.id,
    'display_name', v_profile.display_name,
    'route_endpoint', v_profile.route_endpoint
  );
end;
$$;

revoke all on function public.wty_save_profile(text, jsonb) from public, anon;
grant execute on function public.wty_save_profile(text, jsonb) to authenticated;

-- New clients must send both a city and an airport. Keep the old function in
-- place for migration history, but do not allow clients to call it anymore.
revoke execute on function public.wty_save_profile(text, text) from authenticated;
