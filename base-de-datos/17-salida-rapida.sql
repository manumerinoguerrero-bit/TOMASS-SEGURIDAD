-- ============================================================================
-- Tomass Seguridad — Salida rápida desde "Personas dentro"
-- ============================================================================
-- El guardia veía en la pantalla "Personas dentro" quiénes no habían marcado
-- salida, pero para cerrar una tenía que ir a "Registrar", elegir 'Sale',
-- reescribir nombre, RUT, autorizador... 30+ segundos por persona. Al final
-- del turno con 10-15 personas adentro se hacían 5+ minutos.
--
-- Esta RPC recibe (persona_tipo, persona_id) y crea la salida clonando los
-- datos del ÚLTIMO ingreso de esa persona (nombre_snapshot, unidad,
-- patente, punto_acceso, vehiculo, autorizador). Con un tap se cierra.
--
-- Reglas:
--   * Solo el condominio activo (mi_condominio()).
--   * Si no hay entrada previa aprobada → error visible al guardia.
--   * Si la última fue salida (ya salió) → error visible al guardia.
--   * idempotencia por p_id_local (mismo idLocal → mismo movimiento).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.registrar_salida_rapida(
  p_persona_tipo text,
  p_persona_id uuid,
  p_id_local uuid,
  p_geo_lat numeric DEFAULT NULL,
  p_geo_lng numeric DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_condominio  uuid := public.mi_condominio();
  v_movimiento  uuid;
  v_ultima      public.movimientos_acceso%rowtype;
begin
  if v_condominio is null then
    raise exception 'No hay condominio activo.';
  end if;

  select * into v_ultima
    from public.movimientos_acceso m
   where m.condominio_id = v_condominio
     and m.persona_tipo = p_persona_tipo
     and (
       (p_persona_tipo = 'residente'         and m.residente_id         = p_persona_id) or
       (p_persona_tipo = 'visita'            and m.visita_id            = p_persona_id) or
       (p_persona_tipo = 'personal_servicio' and m.personal_servicio_id = p_persona_id)
     )
     and m.estado = 'aprobado'
   order by m.ocurrido_en desc
   limit 1;

  if v_ultima.id is null then
    raise exception 'No se encontro un movimiento previo de esta persona.';
  end if;

  if v_ultima.sentido = 'salida' then
    raise exception 'Esta persona ya tiene su salida registrada.';
  end if;

  insert into public.movimientos_acceso (
    condominio_id, id_local, persona_tipo,
    residente_id, visita_id, personal_servicio_id,
    nombre_snapshot, unidad_snapshot, rut_snapshot,
    punto_acceso_id, tipo_acceso, sentido,
    vehiculo_id, patente_snapshot, estado,
    guardia_id, turno_id,
    ocurrido_en, geo_lat, geo_lng, autorizado_por_texto
  ) values (
    v_condominio, p_id_local, v_ultima.persona_tipo,
    v_ultima.residente_id, v_ultima.visita_id, v_ultima.personal_servicio_id,
    v_ultima.nombre_snapshot, v_ultima.unidad_snapshot, v_ultima.rut_snapshot,
    v_ultima.punto_acceso_id, v_ultima.tipo_acceso, 'salida',
    v_ultima.vehiculo_id, v_ultima.patente_snapshot, 'aprobado',
    case when public.es_guardia() then auth.uid() end,
    public.mi_turno_activo(),
    now(), p_geo_lat, p_geo_lng, v_ultima.autorizado_por_texto
  )
  on conflict (id_local) do nothing
  returning id into v_movimiento;

  if v_movimiento is null then
    select id into v_movimiento
      from public.movimientos_acceso where id_local = p_id_local;
  end if;

  return v_movimiento;
end; $function$;

GRANT EXECUTE ON FUNCTION public.registrar_salida_rapida(text, uuid, uuid, numeric, numeric)
  TO authenticated;
