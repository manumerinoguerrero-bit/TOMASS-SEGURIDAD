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
// La solución: un secreto que solo conocen la base de datos y el servidor.
//
//   - En el servidor vive como variable de entorno TOMASS_SECRETO_INTERNO
//     (Supabase → Edge Functions → Secrets).
//   - En la base vive en el vault con el nombre tomass_secreto_interno, y el
//     trigger y el cron lo mandan en la cabecera x-tomass-secreto.
//
// Si los dos valores no coinciden, la función contesta 401 y no hace nada.
// Si la variable de entorno no está cargada, también rechaza (falla cerrada):
// es preferible perder un aviso a dejar la puerta abierta. Lo deja anotado en
// el log para que se note enseguida.
// ============================================================================

import { error, registrar } from "./respuesta.ts";

export const CABECERA_SECRETO = "x-tomass-secreto";

/** Compara dos textos sin filtrar por el tiempo cuántos caracteres coinciden. */
function igualesSinFiltrar(a: string, b: string): boolean {
  const codificador = new TextEncoder();
  const x = codificador.encode(a);
  const y = codificador.encode(b);
  let diferencia = x.length ^ y.length;
  const largo = Math.max(x.length, y.length);
  for (let i = 0; i < largo; i++) {
    diferencia |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diferencia === 0;
}

/**
 * Devuelve null si la llamada trae el secreto correcto. Si no, devuelve la
 * respuesta 401 que la función tiene que contestar tal cual.
 */
export function exigirSecretoInterno(peticion: Request, funcion: string): Response | null {
  const esperado = Deno.env.get("TOMASS_SECRETO_INTERNO") ?? "";
  if (esperado.length < 32) {
    registrar("secreto_interno_sin_configurar", { funcion });
    return error("Función interna no disponible.", 401);
  }
  const recibido = peticion.headers.get(CABECERA_SECRETO) ?? "";
  if (!igualesSinFiltrar(recibido, esperado)) {
    registrar("secreto_interno_rechazado", { funcion, trae_cabecera: recibido.length > 0 });
    return error("No autorizado.", 401);
  }
  return null;
}
