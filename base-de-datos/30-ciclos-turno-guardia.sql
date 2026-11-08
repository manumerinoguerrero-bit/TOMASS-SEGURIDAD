-- ============================================================================
-- Tomass Seguridad — 30 · El calendario 4x4 del guardia
-- ============================================================================
-- ⚠️ ESTE ARCHIVO YA ESTÁ APLICADO EN EL SERVIDOR. Queda para el historial.
--
-- QUÉ GUARDA Y POR QUÉ
--
--   Los guardias de Tomass trabajan ciclos fijos 4x4: cuatro días seguidos y
--   cuatro de descanso. Cada guardia tiene un turno FIJO (siempre de día o
--   siempre de noche). Hoy saben qué les toca preguntando al admin o mirando
--   una planilla; el objetivo es que lo vean solos en la app.
--
--   Lo único que hace falta persistir es el ANCLA del ciclo de cada guardia:
--     · si es de día o de noche (siempre lo mismo para ese guardia)
--     · UN día concreto en el que sí trabajó (para calcular el resto)
--   Con esos dos datos la app arma el calendario entero sin pedir nada más.
--
--   La hora aproximada de inicio es opcional, para futuros recordatorios push.
-- ============================================================================

create table if not exists public.ciclos_turno_guardia (
  guardia_id          uuid primary key references public.usuarios(id) on delete cascade,
  turno               text not null check (turno in ('dia','noche')),
  primer_dia_trabajo  date not null,
  hora_inicio_aprox   time,  -- 08:00 para el de día, 20:00 para el de noche, por ejemplo
  actualizado_en      timestamptz not null default now()
);

comment on table  public.ciclos_turno_guardia is
  'Ancla del ciclo 4x4 de cada guardia: con turno (dia/noche) y un día de referencia la app calcula todo el calendario';
comment on column public.ciclos_turno_guardia.primer_dia_trabajo is
  'Un día en el que el guardia SÍ trabajó. Sirve de ancla para el cálculo mod 8 del ciclo';

alter table public.ciclos_turno_guardia enable row level security;

-- El guardia es el único que ve y edita su ciclo. No lo comparte con nadie.
drop policy if exists "guardia ve su ciclo" on public.ciclos_turno_guardia;
create policy "guardia ve su ciclo" on public.ciclos_turno_guardia
  for select to authenticated
  using (guardia_id = auth.uid());

drop policy if exists "guardia edita su ciclo" on public.ciclos_turno_guardia;
create policy "guardia edita su ciclo" on public.ciclos_turno_guardia
  for all to authenticated
  using (guardia_id = auth.uid())
  with check (guardia_id = auth.uid());

-- ============================================================================
-- GUARDAR EL CICLO (UPSERT)
-- ============================================================================
-- Toda la validación vive en la RPC para que el cliente no pueda meter basura
-- (turno fuera de dia/noche, fecha absurda). Los mensajes de error están en
-- español para que el guardia los entienda si algo sale mal.
-- ============================================================================

create or replace function public.guardar_mi_ciclo_de_turno(
  p_turno              text,
  p_primer_dia_trabajo date,
  p_hora_inicio_aprox  time default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_guardia uuid := auth.uid();
begin
  if v_guardia is null then
    raise exception 'Hay que iniciar sesión primero.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_turno not in ('dia','noche') then
    raise exception 'El turno tiene que ser "dia" o "noche".'
      using errcode = 'check_violation';
  end if;

  -- Rango razonable: un año para atrás o para adelante. Más lejos no tiene
  -- sentido para calcular un ciclo en curso.
  if p_primer_dia_trabajo < (current_date - interval '1 year')::date
     or p_primer_dia_trabajo > (current_date + interval '1 year')::date then
    raise exception 'La fecha tiene que estar dentro del año anterior o del próximo año.'
      using errcode = 'check_violation';
  end if;

  insert into public.ciclos_turno_guardia
    (guardia_id, turno, primer_dia_trabajo, hora_inicio_aprox, actualizado_en)
  values
    (v_guardia, p_turno, p_primer_dia_trabajo, p_hora_inicio_aprox, now())
  on conflict (guardia_id) do update
    set turno              = excluded.turno,
        primer_dia_trabajo = excluded.primer_dia_trabajo,
        hora_inicio_aprox  = excluded.hora_inicio_aprox,
        actualizado_en     = now();
end;
$$;

grant execute on function
  public.guardar_mi_ciclo_de_turno(text, date, time) to authenticated;


-- ============================================================================
-- FIN DEL ARCHIVO 30
-- ============================================================================
