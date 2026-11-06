-- ════════════════════════════════════════════════════════════════════
-- GeoMark · Control de acceso por institución (ejecutar DESPUÉS de
-- instalar_canales.sql). Solo los teléfonos que ingresen el código de
-- acceso pueden crear canales o unirse a ellos.
--
-- Ver / cambiar el código:
--   select name, access_code from public.institutions;
--   update public.institutions set access_code = 'NUEVOCODIGO' where name = 'GEO SV';
-- Quitar el acceso a un teléfono:
--   delete from public.authorized_users where display_name = 'Nombre';
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.institutions (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  access_code text not null unique check (char_length(access_code) between 6 and 32),
  created_at  timestamptz not null default now()
);

create table if not exists public.authorized_users (
  user_id        uuid primary key,
  institution_id uuid not null references public.institutions(id) on delete cascade,
  display_name   text not null,
  authorized_at  timestamptz not null default now()
);
create index if not exists authorized_users_institution on public.authorized_users (institution_id);

-- Sin políticas: nadie las lee directo por la API; solo vía funciones.
alter table public.institutions     enable row level security;
alter table public.authorized_users enable row level security;

alter table public.channels add column if not exists institution_id uuid references public.institutions(id);

create or replace function public.my_institution()
returns text language sql stable security definer set search_path = public as $$
  select i.name from authorized_users a join institutions i on i.id = a.institution_id
  where a.user_id = auth.uid();
$$;

create or replace function public.register_access(p_code text, p_display text)
returns text language plpgsql security definer set search_path = public as $$
declare inst institutions;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  select * into inst from institutions where access_code = upper(trim(p_code));
  if not found then raise exception 'Código de acceso incorrecto'; end if;
  insert into authorized_users (user_id, institution_id, display_name)
    values (auth.uid(), inst.id, coalesce(nullif(trim(p_display), ''), 'Usuario'))
    on conflict (user_id) do update
      set institution_id = excluded.institution_id, display_name = excluded.display_name;
  return inst.name;
end $$;

create or replace function public.create_channel(p_name text, p_display text)
returns public.channels language plpgsql security definer set search_path = public as $$
declare c channels; v_code text; v_inst uuid;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  select institution_id into v_inst from authorized_users where user_id = auth.uid();
  if v_inst is null then raise exception 'Sin acceso: ingresa el código de tu institución'; end if;
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from channels where code = v_code);
  end loop;
  insert into channels (name, code, created_by, institution_id)
    values (trim(p_name), v_code, auth.uid(), v_inst) returning * into c;
  insert into channel_members (channel_id, user_id, display_name) values (c.id, auth.uid(), trim(p_display));
  return c;
end $$;

create or replace function public.join_channel(p_code text, p_display text)
returns public.channels language plpgsql security definer set search_path = public as $$
declare c channels; v_inst uuid;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  select institution_id into v_inst from authorized_users where user_id = auth.uid();
  if v_inst is null then raise exception 'Sin acceso: ingresa el código de tu institución'; end if;
  select * into c from channels where code = upper(trim(p_code));
  if not found or c.institution_id is distinct from v_inst then
    raise exception 'Código de canal no válido';
  end if;
  insert into channel_members (channel_id, user_id, display_name)
    values (c.id, auth.uid(), trim(p_display))
    on conflict (channel_id, user_id) do update set display_name = excluded.display_name;
  return c;
end $$;

revoke all on function public.my_institution() from public, anon;
revoke all on function public.register_access(text, text) from public, anon;
revoke all on function public.create_channel(text, text) from public, anon;
revoke all on function public.join_channel(text, text) from public, anon;
revoke all on function public.is_member(uuid) from public, anon;
grant execute on function public.my_institution() to authenticated;
grant execute on function public.register_access(text, text) to authenticated;
grant execute on function public.create_channel(text, text) to authenticated;
grant execute on function public.join_channel(text, text) to authenticated;
grant execute on function public.is_member(uuid) to authenticated;

-- Institución inicial con un código aleatorio de 8 caracteres
-- (consúltalo después con: select name, access_code from public.institutions;)
insert into public.institutions (name, access_code)
select 'Mi institución', upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8))
where not exists (select 1 from public.institutions);
