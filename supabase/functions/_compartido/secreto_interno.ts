// ============================================================================
// Tomass Seguridad — Llamadas internas (SEG-08)
// ============================================================================
// Algunas funciones del servidor NO las llama la app, sino la propia base de
// datos: el aviso de novedad crítica (un trigger) y la limpieza nocturna de
// fotos (pg_cron). Para pasar la puerta de Supabase (verify_jwt) esas llamadas
// usan la llave pública del proyecto, la misma que va dentro de la app. Eso
// significa que cualquiera que la saque del APK podría llamar a estas
// funciones y, por ejemplo, hacer sonar avisos falsos a los administradores.
//
// La solución: un secreto que solo conoce la base de datos.
//
//   - Vive en el vault con el nombre tomass_secreto_interno (el "secreto
//     interno" de SEG-08). Se generó al azar dentro de la base y nunca salió
//     de ahí: nadie lo tuvo que copiar ni pegar.
//   - El trigger y el cron lo mandan en la cabecera x-tomass-secreto.
//   - La función le pregunta a la base, con la llave maestra, si lo que llegó
//     coincide (public._secreto_interno_valido). La comparación se hace allá.
//
// Si no coincide, o si la consulta falla, la función contesta 401 y no hace
// nada (falla cerrada): es preferible perder un aviso a dejar la puerta
// abierta. Lo deja anotado en el log para que se note enseguida.
// ============================================================================

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { error, registrar } from "./respuesta.ts";

export const CABECERA_SECRETO = "x-tomass-secreto";

/**
 * Devuelve null si la llamada trae el secreto correcto. Si no, devuelve la
 * respuesta 401 que la función tiene que contestar tal cual.
 */
export async function exigirSecretoInterno(
  peticion: Request,
  servidor: SupabaseClient,
  funcion: string,
): Promise<Response | null> {
  const recibido = peticion.headers.get(CABECERA_SECRETO) ?? "";
  if (recibido.length === 0) {
    registrar("secreto_interno_rechazado", { funcion, trae_cabecera: false });
    return error("No autorizado.", 401);
  }
  const { data, error: falla } = await servidor.rpc("_secreto_interno_valido", {
    p_secreto: recibido,
  });
  if (falla) {
    registrar("secreto_interno_no_se_pudo_validar", { funcion, detalle: falla.message });
    return error("No autorizado.", 401);
  }
  if (data !== true) {
    registrar("secreto_interno_rechazado", { funcion, trae_cabecera: true });
    return error("No autorizado.", 401);
  }
  return null;
}
