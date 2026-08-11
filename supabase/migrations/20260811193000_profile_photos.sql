-- Profile photos stay in a private Storage bucket. Only an object's owner and
-- the owner's current partner can read it; clients never receive a public URL.

alter table public.wty_profiles
  add column if not exists avatar_path text,
  add column if not exists avatar_updated_at timestamptz;

alter table public.wty_profiles
  drop constraint if exists wty_profiles_avatar_fields_check;

alter table public.wty_profiles
  add constraint wty_profiles_avatar_fields_check check (
    (avatar_path is null and avatar_updated_at is null)
    or (
      avatar_path = id::text || '/avatar.jpg'
      and avatar_updated_at is not null
    )
  );

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'wty-profile-photos',
  'wty-profile-photos',
  false,
  1048576,
  array['image/jpeg']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create schema if not exists wty_private;
revoke all on schema wty_private from public, anon;
grant usage on schema wty_private to authenticated;

create or replace function wty_private.can_read_avatar(
  p_owner_id text,
  p_object_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and (
    p_owner_id = auth.uid()::text
    or exists (
      select 1
      from public.wty_profiles owner_profile
      join public.wty_connection_members owner_member
        on owner_member.user_id = owner_profile.id
      join public.wty_connection_members viewer_member
        on viewer_member.connection_id = owner_member.connection_id
      where owner_profile.id::text = p_owner_id
        and owner_profile.avatar_path = p_object_name
        and viewer_member.user_id = auth.uid()
    )
  );
$$;

revoke all on function wty_private.can_read_avatar(text, text) from public, anon;
grant execute on function wty_private.can_read_avatar(text, text) to authenticated;

drop policy if exists wty_avatar_select_connected on storage.objects;
create policy wty_avatar_select_connected
on storage.objects
for select
to authenticated
using (
  bucket_id = 'wty-profile-photos'
  and wty_private.can_read_avatar(owner_id, name)
);

drop policy if exists wty_avatar_insert_own on storage.objects;
create policy wty_avatar_insert_own
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'wty-profile-photos'
  and owner_id = auth.uid()::text
  and name = auth.uid()::text || '/avatar.jpg'
  and storage.extension(name) = 'jpg'
);

drop policy if exists wty_avatar_update_own on storage.objects;
create policy wty_avatar_update_own
on storage.objects
for update
to authenticated
using (
  bucket_id = 'wty-profile-photos'
  and owner_id = auth.uid()::text
  and name = auth.uid()::text || '/avatar.jpg'
)
with check (
  bucket_id = 'wty-profile-photos'
  and owner_id = auth.uid()::text
  and name = auth.uid()::text || '/avatar.jpg'
  and storage.extension(name) = 'jpg'
);

drop policy if exists wty_avatar_delete_own on storage.objects;
create policy wty_avatar_delete_own
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'wty-profile-photos'
  and owner_id = auth.uid()::text
  and name = auth.uid()::text || '/avatar.jpg'
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
        'route_endpoint', v_me.route_endpoint,
        'avatar_path', v_me.avatar_path,
        'avatar_updated_at', v_me.avatar_updated_at
      ) end,
      'partner', case when v_partner.id is null then null else jsonb_build_object(
        'id', v_partner.id,
        'display_name', v_partner.display_name,
        'route_endpoint', v_partner.route_endpoint,
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
      'route_endpoint', v_me.route_endpoint,
      'avatar_path', v_me.avatar_path,
      'avatar_updated_at', v_me.avatar_updated_at
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
    'route_endpoint', v_profile.route_endpoint,
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
    'route_endpoint', v_profile.route_endpoint,
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
    'route_endpoint', v_profile.route_endpoint,
    'avatar_path', v_profile.avatar_path,
    'avatar_updated_at', v_profile.avatar_updated_at
  );
end;
$$;

revoke all on function public.wty_save_profile(text, jsonb) from public, anon;
grant execute on function public.wty_save_profile(text, jsonb) to authenticated;
revoke all on function public.wty_set_profile_avatar() from public, anon;
grant execute on function public.wty_set_profile_avatar() to authenticated;
revoke all on function public.wty_clear_profile_avatar() from public, anon;
grant execute on function public.wty_clear_profile_avatar() to authenticated;
