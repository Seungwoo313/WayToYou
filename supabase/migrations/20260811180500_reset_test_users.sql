-- One-time development reset after replacing legacy city-only profiles with
-- MapKit city and airport endpoints. This intentionally removes test accounts.

truncate table
  public.wty_heart_bursts,
  public.wty_connection_attempt_limits,
  public.wty_connection_invites,
  public.wty_connection_members,
  public.wty_connections,
  public.wty_profiles
restart identity cascade;

delete from auth.users;
