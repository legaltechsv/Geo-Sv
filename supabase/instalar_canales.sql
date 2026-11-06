-- ════════════════════════════════════════════════════════════════════
-- GeoMark · Canales en tiempo real
-- Pegar COMPLETO en Supabase → SQL Editor → New query → Run.
-- Se puede ejecutar más de una vez sin romper nada.
-- ════════════════════════════════════════════════════════════════════

-- Canales (grupos de trabajo). Se entra con un código de 6 caracteres.
create table if not exists public.channels (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 80),
  code        text not null unique,
  created_by  uuid not null default auth.uid(),
  created_at  timestamptz not null default now()
);

create table if not exists public.channel_members (
  channel_id   uuid not null references public.channels(id) on delete cascade,
  user_id      uuid not null default auth.uid(),
  display_name text not null check (char_length(display_name) between 1 and 60),
  joined_at    timestamptz not null default now(),
  primary key (channel_id, user_id)
);

create table if not exists public.channel_messages (
  id          uuid primary key default gen_random_uuid(),
  channel_id  uuid not null references public.channels(id) on delete cascade,
  user_id     uuid not null default auth.uid(),
  user_name   text not null,
  kind        text not null check (kind in ('text', 'photo', 'location')),
  body        text check (body is null or char_length(body) <= 2000),
  photo_url   text,
  lat         double precision,
  lng         double precision,
  heading     double precision,
  created_at  timestamptz not null default now()
);
create index if not exists channel_messages_channel_created
  on public.channel_messages (channel_id, created_at desc);
create index if not exists channel_members_user on public.channel_members (user_id);

-- ¿El usuario actual es miembro del canal? (security definer evita recursión en RLS)
create or replace function public.is_member(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from channel_members where channel_id = cid and user_id = auth.uid());
$$;

-- Crear canal: genera el código y agrega al creador como miembro.
create or replace function public.create_channel(p_name text, p_display text)
returns public.channels language plpgsql security definer set search_path = public as $$
declare c channels; v_code text;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from channels where code = v_code);
  end loop;
  insert into channels (name, code, created_by) values (trim(p_name), v_code, auth.uid()) returning * into c;
  insert into channel_members (channel_id, user_id, display_name) values (c.id, auth.uid(), trim(p_display));
  return c;
end $$;

-- Unirse con el código.
create or replace function public.join_channel(p_code text, p_display text)
returns public.channels language plpgsql security definer set search_path = public as $$
declare c channels;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  select * into c from channels where code = upper(trim(p_code));
  if not found then raise exception 'Código de canal no válido'; end if;
  insert into channel_members (channel_id, user_id, display_name)
    values (c.id, auth.uid(), trim(p_display))
    on conflict (channel_id, user_id) do update set display_name = excluded.display_name;
  return c;
end $$;

revoke all on function public.create_channel(text, text) from public, anon;
revoke all on function public.join_channel(text, text) from public, anon;
grant execute on function public.create_channel(text, text) to authenticated;
grant execute on function public.join_channel(text, text) to authenticated;
grant execute on function public.is_member(uuid) to authenticated;

-- Seguridad por filas: solo los miembros ven y escriben en su canal.
alter table public.channels         enable row level security;
alter table public.channel_members  enable row level security;
alter table public.channel_messages enable row level security;

drop policy if exists "miembros ven el canal" on public.channels;
create policy "miembros ven el canal" on public.channels
  for select to authenticated using (public.is_member(id));

drop policy if exists "miembros ven a los miembros" on public.channel_members;
create policy "miembros ven a los miembros" on public.channel_members
  for select to authenticated using (public.is_member(channel_id));

drop policy if exists "salir del canal" on public.channel_members;
create policy "salir del canal" on public.channel_members
  for delete to authenticated using (user_id = auth.uid());

drop policy if exists "miembros leen mensajes" on public.channel_messages;
create policy "miembros leen mensajes" on public.channel_messages
  for select to authenticated using (public.is_member(channel_id));

drop policy if exists "miembros envían mensajes" on public.channel_messages;
create policy "miembros envían mensajes" on public.channel_messages
  for insert to authenticated with check (public.is_member(channel_id) and user_id = auth.uid());

-- Tiempo real para los mensajes nuevos.
do $$ begin
  alter publication supabase_realtime add table public.channel_messages;
exception when duplicate_object then null; end $$;

-- Fotos del canal (rutas con UUID, no adivinables).
insert into storage.buckets (id, name, public)
  values ('channel-photos', 'channel-photos', true)
  on conflict (id) do nothing;

drop policy if exists "subir fotos de canal" on storage.objects;
create policy "subir fotos de canal" on storage.objects
  for insert to authenticated with check (bucket_id = 'channel-photos');
