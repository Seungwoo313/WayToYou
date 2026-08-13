-- Signal is now whatever emoji the sender put on their keypad, not one of five fixed states.
-- The stored value is the emoji itself; the five legacy slugs stay readable for old rows.
-- Keycap labels are private to each device and never reach the server.

alter table public.wty_signals
  drop constraint if exists wty_signals_signal_type_check;

alter table public.wty_signals
  add constraint wty_signals_signal_type_check check (
    (
      signal_type = btrim(signal_type)
      and char_length(signal_type) between 1 and 16
      and signal_type !~ '^[[:ascii:]]+$'
    )
    or signal_type = any (array['sleeping', 'focusing', 'free', 'out', 'resting'])
  );

create or replace function public.wty_send_signal(p_signal_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_connection_id uuid;
  v_signal_type text := btrim(p_signal_type);
  v_signal public.wty_signals%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  -- One emoji, or a legacy slug. Plain ASCII text would let this become a chat field.
  if v_signal_type is null
    or char_length(v_signal_type) < 1
    or char_length(v_signal_type) > 16
    or (
      v_signal_type ~ '^[[:ascii:]]+$'
      and lower(v_signal_type) <> all (array['sleeping', 'focusing', 'free', 'out', 'resting'])
    )
  then
    raise exception using errcode = '22023', message = 'invalid_signal_type';
  end if;

  if v_signal_type ~ '^[[:ascii:]]+$' then
    v_signal_type := lower(v_signal_type);
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

revoke all on function public.wty_send_signal(text) from public, anon;
grant execute on function public.wty_send_signal(text) to authenticated;
