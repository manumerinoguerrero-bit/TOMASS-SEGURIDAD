-- ============================================================================
-- 33 · Auditoría de seguridad — Fase 1 (hallazgos SEG-01 y SEG-05)
-- ============================================================================
-- Cierra dos agujeros encontrados en la auditoría del 2026-11-11:
--
--   SEG-01 (crítico) · El panel web insertaba nombre/teléfono del guardia sin
--     escapar (XSS). El arreglo real está en web/js (escapar()); acá va la
--     segunda barrera: que el propio usuario NO pueda cambiarse el nombre, la
--     cédula ni el email por API, y que el teléfono tenga un formato acotado.
--
--   SEG-05 (alto) · "Dar de baja" cerraba la sesión pero no bloqueaba la cuenta:
--     el ex-guardia volvía a iniciar sesión y la API le seguía respondiendo.
--     Acá: se banea la cuenta en Auth, se borran sus sesiones, y mi_condominio()
--     deja de devolver instalación para cuentas inactivas.
--
-- Todo este archivo es seguro de correr con guardias trabajando: ningún cambio
-- afecta a un usuario ACTIVO; solo agrega restricciones a cuentas inactivas y a
-- la auto-edición de datos de identidad.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SEG-01 · Segunda barrera: el usuario no edita su propia identidad
-- ----------------------------------------------------------------------------
create or replace function public.proteger_campos_sensibles()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if auth.uid() = old.id and not public.es_administrador() then
    if new.rol                  is distinct from old.rol
    or new.estado               is distinct from old.estado
    or new.condominio_id        is distinct from old.condominio_id
    or new.unidad_id            is distinct from old.unidad_id
    or new.ultimo_qr_emitido_en is distinct from old.ultimo_qr_emitido_en
    -- Datos que identifican a la persona: solo la administración los cambia.
    -- El residente/guardia puede cambiar su foto y su teléfono, nada más.
    or new.nombre_completo      is distinct from old.nombre_completo
    or new.cedula               is distinct from old.cedula
    or new.email                is distinct from old.email then
      raise exception
        'No podés cambiar tu nombre, tu cédula, tu email, tu rol, tu estado ni '
        'tu unidad. Pedíselo a la administración.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end; $$;

-- Teléfono: solo dígitos, espacios, +, paréntesis y guion, 6 a 20 caracteres.
-- NOT VALID para no fallar con filas viejas; solo valida escrituras nuevas.
alter table public.usuarios
  drop constraint if exists usuarios_telefono_formato;
alter table public.usuarios
  add constraint usuarios_telefono_formato
  check (telefono is null or telefono ~ '^[0-9+() -]{6,20}$') not valid;

-- ----------------------------------------------------------------------------
-- SEG-05 · Dar de baja corta el acceso de verdad
-- ----------------------------------------------------------------------------

-- mi_condominio(): el fallback ahora exige estado = 'activo'. La rama principal
-- ya lo exigía; solo faltaba acá. Un inactivo deja de tener instalación y así
-- ninguna policy que compare contra mi_condominio() lo deja pasar.
create or replace function public.mi_condominio()
returns uuid
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select coalesce(
    -- La elegida, pero SOLO si de verdad la puede atender (activo + rol + suya).
    (select u.condominio_activo
       from public.usuarios u
      where u.id = auth.uid()
        and u.estado = 'activo'
        and u.rol in ('administrador', 'guardia')
        and u.condominio_activo is not null
        and (
          u.condominio_activo = u.condominio_id
          or exists (
            select 1 from public.administra_instalaciones a
             where a.usuario_id = u.id
               and a.condominio_id = u.condominio_activo)
        )),
    -- La suya de toda la vida, pero solo si la cuenta sigue activa.
    (select condominio_id from public.usuarios
      where id = auth.uid() and estado = 'activo')
  );
$$;

-- Policies de fila propia: solo cuentas activas (mi_rol()/es_guardia() son
-- null/false para inactivos).
alter policy "editar mi propia ficha" on public.usuarios
  using (id = auth.uid() and public.mi_rol() is not null)
  with check (id = auth.uid());

alter policy "guardia cierra su turno" on public.turnos
  using (guardia_id = auth.uid() and public.es_guardia())
  with check (guardia_id = auth.uid());

-- dar_de_baja_guardia: además de cerrar sesión, banea la cuenta en Auth y
-- borra sus sesiones, para que no pueda volver a iniciar sesión.
create or replace function public.dar_de_baja_guardia(p_guardia_id uuid, p_motivo text default null::text)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp', 'auth'
as $function$
begin
  if not public.es_administrador() then
    raise exception 'Solo la administración puede dar de baja guardias.'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from public.usuarios u
    where u.id = p_guardia_id
      and u.rol = 'guardia'
      and (u.condominio_id in (select id from public.mis_instalaciones())
           or exists (select 1 from public.administra_instalaciones ai
                      where ai.usuario_id = u.id
                        and ai.condominio_id in (select id from public.mis_instalaciones())))
  ) then
    raise exception 'Ese guardia no esta en tus instalaciones.'
      using errcode = 'insufficient_privilege';
  end if;

  update public.usuarios
  set estado = 'inactivo',
      motivo_inactivo = nullif(trim(coalesce(p_motivo, '')), ''),
      inactivo_desde = now()
  where id = p_guardia_id;

  delete from public.administra_instalaciones where usuario_id = p_guardia_id;

  -- Cortar el acceso en Auth: banear la cuenta y matar refresh tokens + sesiones.
  update auth.users set banned_until = 'infinity' where id = p_guardia_id;
  delete from auth.refresh_tokens where user_id = p_guardia_id::text;
  delete from auth.sessions where user_id = p_guardia_id;

  update public.turnos
  set cerrado_en = now(),
      notas_entrega = 'Cerrado al dar de baja al guardia.'
  where guardia_id = p_guardia_id and cerrado_en is null;
end;
$function$;

-- reactivar_guardia: levanta el baneo (necesita 'auth' en el search_path).
create or replace function public.reactivar_guardia(p_guardia_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp', 'auth'
as $function$
declare
  v_condo_principal uuid;
begin
  if not public.es_administrador() then
    raise exception 'Solo la administración puede reactivar guardias.'
      using errcode = 'insufficient_privilege';
  end if;

  select condominio_id into v_condo_principal
  from public.usuarios
  where id = p_guardia_id and rol = 'guardia';

  if v_condo_principal is null then
    raise exception 'Ese guardia no existe.'
      using errcode = 'insufficient_privilege';
  end if;

  if v_condo_principal not in (select id from public.mis_instalaciones()) then
    raise exception 'Ese guardia no esta en tus instalaciones.'
      using errcode = 'insufficient_privilege';
  end if;

  update public.usuarios
  set estado = 'activo',
      motivo_inactivo = null,
      inactivo_desde = null
  where id = p_guardia_id;

  -- Levantar el baneo de Auth.
  update auth.users set banned_until = null where id = p_guardia_id;

  insert into public.administra_instalaciones (usuario_id, condominio_id)
  select p_guardia_id, c.id from public.condominios c
  where c.id <> v_condo_principal
  on conflict do nothing;
end;
$function$;
