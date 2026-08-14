-- The heart beating at the middle of the route belongs to the couple, not to one
-- phone. Both partners look at the same globe, so they should see the same heart.
-- It lives on the connection row and is read back through the connection state
-- both clients already poll.
--
-- Whether the heart is drawn at all, and whether it beats, stay on the device:
-- those are display preferences, and turning your own animation off should not
-- reach into the other person's globe.

alter table public.wty_connections
  add column if not exists route_heart_emoji text not null default '🩷';

alter table public.wty_connections
  drop constraint if exists wty_connections_route_heart_emoji_check;

-- Same shape as the Signal keycap check. Naming the app's hearts here would mean
-- a migration every time one is added, so the rule is "one emoji, never text".
alter table public.wty_connections
  add constraint wty_connections_route_heart_emoji_check check (
    route_heart_emoji = btrim(route_heart_emoji)
    and char_length(route_heart_emoji) between 1 and 16
    and route_heart_emoji !~ '^[[:ascii:]]+$'
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
      'route_heart_emoji', v_connection.route_heart_emoji,
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

-- Either partner can change it, and it lands on the connection they share. The
-- caller cannot name a connection: it is looked up from their own membership.
create or replace function public.wty_set_route_heart_emoji(p_emoji text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_connection_id uuid;
  v_emoji text := btrim(p_emoji);
  v_connection public.wty_connections%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if v_emoji is null
    or char_length(v_emoji) < 1
    or char_length(v_emoji) > 16
    or v_emoji ~ '^[[:ascii:]]+$'
  then
    raise exception using errcode = '22023', message = 'invalid_route_heart_emoji';
  end if;

  select member.connection_id into v_connection_id
  from public.wty_connection_members member
  where member.user_id = v_user_id
  limit 1;

  if v_connection_id is null then
    raise exception using errcode = '22023', message = 'connection_required';
  end if;

  update public.wty_connections
  set route_heart_emoji = v_emoji
  where id = v_connection_id
  returning * into v_connection;

  return jsonb_build_object(
    'connection_id', v_connection.id,
    'route_heart_emoji', v_connection.route_heart_emoji
  );
end;
$$;

revoke all on function public.wty_set_route_heart_emoji(text) from public, anon;
grant execute on function public.wty_set_route_heart_emoji(text) to authenticated;
