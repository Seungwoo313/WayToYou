-- The route starts with the familiar red heart. The previous migration briefly
-- used the pink heart as its default, so rows still carrying that initial value
-- move to red as well. Pink remains a valid choice after this one-time update.

alter table public.wty_connections
  alter column route_heart_emoji set default '❤️';

update public.wty_connections
set route_heart_emoji = '❤️'
where route_heart_emoji = '🩷';
