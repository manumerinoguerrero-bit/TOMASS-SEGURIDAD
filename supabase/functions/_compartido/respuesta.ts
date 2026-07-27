// ============================================================================
// Tomass Seguridad — Respuestas del servidor
// ============================================================================
// Archivo de apoyo. No hace nada por sí solo: le da forma a lo que el servidor
// le contesta a la app, para que todas las respuestas se vean igual.
// ============================================================================

/**
 * Permisos para que la app pueda hablarle al servidor desde cualquier celular.
 * (En inglés esto se llama CORS. Sin estas líneas el navegador bloquea la
 * comunicación y nada funciona.)
 */
export const CABECERAS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

/** Respuesta de saludo previo que manda el celular antes de la real. */
export function saludoPrevio(): Response {
  return new Response("ok", { headers: CABECERAS });
}

/** Todo salió bien. */
export function exito(datos: unknown, codigo = 200): Response {
  return new Response(JSON.stringify(datos), {
    status: codigo,
    headers: CABECERAS,
  });
}

/**
 * Algo falló.
 *
 * El mensaje va escrito para que lo lea una persona, no un programador:
 * aparece tal cual en la pantalla del celular. Nunca se le manda a la app el
 * detalle técnico del error, porque eso le daría pistas a alguien que esté
 * tratando de romper el sistema.
 */
export function error(
  mensaje: string,
  codigo = 400,
  extras: Record<string, unknown> = {},
): Response {
  return new Response(
    JSON.stringify({ aprobado: false, mensaje, ...extras }),
    { status: codigo, headers: CABECERAS },
  );
}

/** Escribe en el registro del servidor. Sirve para revisar qué pasó. */
export function registrar(
  etiqueta: string,
  datos: Record<string, unknown> = {},
): void {
  console.log(JSON.stringify({ momento: new Date().toISOString(), etiqueta, ...datos }));
}
