-- ============================================================================
-- 42 · Base de destinatarios de encomiendas, por instalación
-- ============================================================================
-- EL PEDIDO (Manuel, 18/11/2026)
--
--   "Que en cada instalación se mantenga una base de datos de todas las
--   personas a las que les llegan encomiendas, para que cuando el guardia
--   ingrese una encomienda, al poner el nombre, una lupa le busque los datos
--   que ya están en la base y el ingreso sea más rápido."
--
-- POR QUÉ HACÍA FALTA
--
--   Casi todas las encomiendas se anotan "a mano" (en Milagros 642 de 652),
--   porque los residentes no están dados de alta. La app ya sugería nombres
--   escritos antes, pero los sacaba de una muestra de 80 paquetes sin orden y
--   solo si el nombre EMPEZABA con lo escrito. Con 189 personas distintas en
--   Milagros, la mayoría nunca aparecía, y buscar por número de casa
--   ("275") o por apellido ("Vargas") no encontraba nada.
--
-- LA SOLUCIÓN
--
--   1. Tabla destinatarios_encomiendas: una fila por persona + unidad en cada
--      instalación, con cuántas encomiendas recibió y cuándo fue la última.
--
--   2. Se llena SOLA: un trigger sobre paquetes agrega (o suma un uso a) la
--      persona cada vez que un guardia registra una encomienda escrita a mano.
--      Funciona también con los APK viejos que todavía no tienen la lupa.
--
--   3. Se rellena una vez con TODAS las encomiendas que ya existen, así la
--      base nace con las personas de hoy.
--
--   4. Función buscar_destinatarios_encomienda(texto): busca por nombre,
--      apellido o unidad, sin importar tildes ni mayúsculas, solo en la
--      instalación activa del guardia. Ordena primero los que más reciben.
--
-- SEGURIDAD
--
--   - RLS activa. La portería y el administrador VEN solo los de su
--     instalación activa (mi_condominio()). Nadie escribe directo desde la app:
--     el trigger es SECURITY DEFINER. El administrador puede borrar una fila
--     mal escrita.
--   - La función de búsqueda no es ejecutable por anon.
--   - Solo agrega una tabla, un trigger y una función. No toca ni borra datos
--     de paquetes.
-- ============================================================================

-- ---------------------------------------------------------------- normalizar
-- "María  Fernández " y "maria fernandez" son la misma persona. Inmutable para
-- poder usarla en el índice único.
create or replace function public.normalizar_texto_busqueda(p text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $$
  select nullif(
    regexp_replace(
      translate(lower(trim(coalesce(p, ''))),
                'áàäâéèëêíìïîóòöôúùüûñç',
                'aaaaeeeeiiiioooouuuunc'),
      '\s+', ' ', 'g'),
    '');
$$;

-- ---------------------------------------------------------------- la tabla
create table if not exists public.destinatarios_encomiendas (
  id              uuid primary key default gen_random_uuid(),
  condominio_id   uuid not null references public.condominios(id) on delete cascade,
  -- Como lo escribió el guardia la primera vez (con tildes y mayúsculas)
  nombre          text not null,
  unidad          text,
  -- Claves normalizadas para no duplicar y para buscar sin tildes
  clave_nombre    text not null,
  clave_unidad    text not null default '',
  usos            integer not null default 1,
  ultima_vez      timestamptz not null default now(),
  creado_en       timestamptz not null default now(),
  unique (condominio_id, clave_nombre, clave_unidad)
);

create index if not exists idx_dest_enc_condominio_usos
  on public.destinatarios_encomiendas (condominio_id, usos desc, ultima_vez desc);

alter table public.destinatarios_encomiendas enable row level security;

drop policy if exists "porteria ve destinatarios del condominio"
  on public.destinatarios_encomiendas;
create policy "porteria ve destinatarios del condominio"
  on public.destinatarios_encomiendas
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria());

drop policy if exists "administrador borra destinatarios"
  on public.destinatarios_encomiendas;
create policy "administrador borra destinatarios"
  on public.destinatarios_encomiendas
  for delete to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador());

revoke all on public.destinatarios_encomiendas from anon;
grant select, delete on public.destinatarios_encomiendas to authenticated;

-- ---------------------------------------------------------------- se llena sola
create or replace function public.guardar_destinatario_de_paquete()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_clave text := public.normalizar_texto_busqueda(new.destinatario_texto);
begin
  if v_clave is null or length(v_clave) < 2 then
    return new;
  end if;

  insert into public.destinatarios_encomiendas
    (condominio_id, nombre, unidad, clave_nombre, clave_unidad, usos, ultima_vez)
  values
    (new.condominio_id,
     regexp_replace(trim(new.destinatario_texto), '\s+', ' ', 'g'),
     nullif(trim(coalesce(new.unidad_texto, '')), ''),
     v_clave,
     coalesce(public.normalizar_texto_busqueda(new.unidad_texto), ''),
     1,
     coalesce(new.recibido_en, now()))
  on conflict (condominio_id, clave_nombre, clave_unidad) do update
    set usos       = public.destinatarios_encomiendas.usos + 1,
        ultima_vez = greatest(public.destinatarios_encomiendas.ultima_vez,
                              excluded.ultima_vez);

  return new;
exception when others then
  -- Nunca bloquear la recepción de un paquete por la base de sugerencias.
  return new;
end;
$$;

revoke execute on function public.guardar_destinatario_de_paquete() from public, anon, authenticated;

drop trigger if exists trg_guardar_destinatario_de_paquete on public.paquetes;
create trigger trg_guardar_destinatario_de_paquete
  after insert on public.paquetes
  for each row execute function public.guardar_destinatario_de_paquete();

-- ---------------------------------------------------------------- relleno inicial
-- Con las encomiendas que ya existen. Se puede correr más de una vez: la
-- segunda no duplica, recalcula los usos desde cero.
insert into public.destinatarios_encomiendas
  (condominio_id, nombre, unidad, clave_nombre, clave_unidad, usos, ultima_vez, creado_en)
select distinct on (p.condominio_id, g.clave_nombre, g.clave_unidad)
       p.condominio_id,
       regexp_replace(trim(p.destinatario_texto), '\s+', ' ', 'g'),
       nullif(trim(coalesce(p.unidad_texto, '')), ''),
       g.clave_nombre,
       g.clave_unidad,
       count(*) over (partition by p.condominio_id, g.clave_nombre, g.clave_unidad),
       max(p.recibido_en) over (partition by p.condominio_id, g.clave_nombre, g.clave_unidad),
       min(p.recibido_en) over (partition by p.condominio_id, g.clave_nombre, g.clave_unidad)
  from public.paquetes p
 cross join lateral (
   select public.normalizar_texto_busqueda(p.destinatario_texto) as clave_nombre,
          coalesce(public.normalizar_texto_busqueda(p.unidad_texto), '') as clave_unidad
 ) g
 where g.clave_nombre is not null
   and length(g.clave_nombre) >= 2
 -- Se queda con la forma escrita más reciente
 order by p.condominio_id, g.clave_nombre, g.clave_unidad, p.recibido_en desc
on conflict (condominio_id, clave_nombre, clave_unidad) do update
  set usos       = excluded.usos,
      ultima_vez = excluded.ultima_vez;

-- ---------------------------------------------------------------- la lupa
-- Busca por nombre, apellido o unidad. Cada palabra escrita tiene que
-- aparecer en el nombre o en la unidad ("vargas 275", "275", "mari").
-- Sin texto devuelve los más frecuentes, para tocarlos sin escribir.
create or replace function public.buscar_destinatarios_encomienda(p_texto text)
returns table(
  id uuid, nombre text, unidad text, usos integer, ultima_vez timestamptz
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with palabras as (
    select coalesce(
             string_to_array(public.normalizar_texto_busqueda(p_texto), ' '),
             '{}'::text[]) as lista
  )
  select d.id, d.nombre, d.unidad, d.usos, d.ultima_vez
    from public.destinatarios_encomiendas d, palabras w
   where d.condominio_id = public.mi_condominio()
     and public.es_porteria()
     and not exists (
       select 1 from unnest(w.lista) as pal
        where not (d.clave_nombre like '%' || pal || '%'
                   or d.clave_unidad like '%' || pal || '%')
     )
   order by
     -- Primero los que empiezan con lo escrito, después los más frecuentes
     (d.clave_nombre like coalesce(w.lista[1], '') || '%'
      or d.clave_unidad = coalesce(w.lista[1], '')) desc,
     d.usos desc,
     d.ultima_vez desc
   limit 12;
$$;

revoke execute on function public.buscar_destinatarios_encomienda(text) from public, anon;
grant execute on function public.buscar_destinatarios_encomienda(text) to authenticated;
