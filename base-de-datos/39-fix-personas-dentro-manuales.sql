-- ============================================================================
-- 39 · Arreglo: el "inicio" no mostraba a todas las personas anotadas a mano
-- ============================================================================
-- La vista v_personas_dentro (lista de quién está adentro) usaba como clave de
-- de-duplicación COALESCE(residente_id, visita_id, personal_servicio_id). Para un
-- ingreso MANUAL esos tres son NULL, y Postgres agrupa todos los NULL como uno
-- solo: así, todas las personas anotadas a mano colapsaban en UNA fila (la última
-- que entró). Por eso un guardia anotaba a alguien y "no se veía" en el inicio.
--
-- Arreglo: para manuales se identifica a la persona por su RUT; si no hay RUT,
-- por el nombre; si tampoco, por el id del movimiento (cada ingreso es su propia
-- fila y nunca colapsa). Para residentes, visitas y personal el comportamiento es
-- idéntico (el COALESCE toma su id primero). Además se usa LEFT JOIN a
-- puntos_acceso para no esconder un ingreso que venga sin punto de acceso.
--
-- Se conserva security_invoker=true (SEG-04): la vista respeta el RLS del usuario
-- que la consulta, no del dueño.
-- ============================================================================

create or replace view public.v_personas_dentro
with (security_invoker = true) as
  with ultimo_movimiento as (
    select distinct on (
             m.persona_tipo,
             coalesce(
               m.residente_id::text,
               m.visita_id::text,
               m.personal_servicio_id::text,
               nullif(trim(m.rut_snapshot), ''),
               nullif(lower(trim(m.nombre_snapshot)), ''),
               m.id::text
             )
           )
           m.condominio_id,
           m.persona_tipo,
           m.residente_id,
           m.visita_id,
           m.personal_servicio_id,
           m.nombre_snapshot,
           m.unidad_snapshot,
           m.punto_acceso_id,
           m.tipo_acceso,
           m.sentido,
           m.patente_snapshot,
           m.ocurrido_en
      from public.movimientos_acceso m
     where m.estado = 'aprobado'
       and m.condominio_id = mi_condominio()
     order by m.persona_tipo,
              coalesce(
                m.residente_id::text,
                m.visita_id::text,
                m.personal_servicio_id::text,
                nullif(trim(m.rut_snapshot), ''),
                nullif(lower(trim(m.nombre_snapshot)), ''),
                m.id::text
              ),
              m.ocurrido_en desc
  )
  select u.condominio_id,
         u.persona_tipo,
         coalesce(u.residente_id, u.visita_id, u.personal_servicio_id) as persona_id,
         u.nombre_snapshot as nombre,
         u.unidad_snapshot as unidad,
         u.tipo_acceso,
         u.patente_snapshot as patente,
         u.ocurrido_en as entro_en,
         now() - u.ocurrido_en as tiempo_adentro,
         case
           when u.persona_tipo = 'visita'::text
                and (now() - u.ocurrido_en) > '12:00:00'::interval then true
           when u.persona_tipo = 'personal_servicio'::text
                and (now() - u.ocurrido_en) > '14:00:00'::interval then true
           else false
         end as estadia_inusual,
         p.nombre as entro_por
    from ultimo_movimiento u
    left join public.puntos_acceso p on p.id = u.punto_acceso_id
   where u.sentido = 'entrada'::text;
