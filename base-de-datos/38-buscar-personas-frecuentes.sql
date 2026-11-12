-- ============================================================================
-- 38 · Buscar personas frecuentes para autorrellenar "Anotar"
-- ============================================================================
-- Para que el guardia no reescriba los datos de alguien que ya ingresó antes.
-- La "base de personas" no es una tabla aparte: son los propios ingresos que
-- los guardias fueron registrando. Se autoalimenta con el uso.
--
-- Acotado por seguridad: solo busca en la instalación del guardia (es_porteria
-- + mi_condominio), y la función no es ejecutable por anon.
-- ============================================================================

create index if not exists idx_mov_busqueda_nombre
  on public.movimientos_acceso (condominio_id, lower(nombre_snapshot));
create index if not exists idx_mov_busqueda_rut
  on public.movimientos_acceso (condominio_id, rut_snapshot);

create or replace function public.buscar_personas_frecuentes(p_texto text)
returns table(
  nombre text, rut text, patente text,
  a_donde_va text, autorizado_por text, tipo_acceso text,
  ultima_vez timestamptz
)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  with ultimo as (
    select distinct on (coalesce(nullif(trim(m.rut_snapshot), ''), lower(m.nombre_snapshot)))
           m.nombre_snapshot, m.rut_snapshot, m.patente_snapshot,
           m.a_donde_va, m.autorizado_por_texto, m.tipo_acceso, m.ocurrido_en
      from public.movimientos_acceso m
     where m.condominio_id = public.mi_condominio()
       and public.es_porteria()
       and m.persona_tipo = 'manual'
       and length(coalesce(trim(p_texto), '')) >= 2
       and (
         m.nombre_snapshot ilike '%' || trim(p_texto) || '%'
         or replace(coalesce(m.rut_snapshot, ''), '.', '')
            ilike '%' || replace(trim(p_texto), '.', '') || '%'
       )
     order by coalesce(nullif(trim(m.rut_snapshot), ''), lower(m.nombre_snapshot)),
              m.ocurrido_en desc
  )
  select nombre_snapshot::text, rut_snapshot::text, patente_snapshot::text,
         a_donde_va::text, autorizado_por_texto::text, tipo_acceso::text, ocurrido_en
    from ultimo
   order by ocurrido_en desc
   limit 8;
$$;

revoke execute on function public.buscar_personas_frecuentes(text) from public, anon;
grant execute on function public.buscar_personas_frecuentes(text) to authenticated;
