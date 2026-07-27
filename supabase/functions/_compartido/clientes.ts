// ============================================================================
// Tomass Seguridad — Conexiones a la base de datos
// ============================================================================
// Archivo de apoyo. Define las dos formas en que el servidor se conecta a la
// base de datos, que son muy distintas y NO hay que confundir:
//
//   clienteServidor()  → tiene la llave maestra. Ve y escribe todo, se salta
//                        los candados. Se usa solo acá dentro, en el servidor.
//                        Esta llave JAMÁS va dentro de la app del celular.
//
//   quienPregunta(req) → averigua quién es la persona que está usando la app,
//                        verificando su sesión. No se confía en lo que la app
//                        dice ser: se comprueba contra el servidor.
// ============================================================================

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const URL_SUPABASE = Deno.env.get("SUPABASE_URL")!;
const LLAVE_MAESTRA = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const LLAVE_PUBLICA = Deno.env.get("SUPABASE_ANON_KEY")!;

/** Conexión con llave maestra. Se salta todos los candados a propósito. */
export function clienteServidor(): SupabaseClient {
  return createClient(URL_SUPABASE, LLAVE_MAESTRA, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Los datos de la persona que está usando la app. */
export interface Usuario {
  id: string;
  condominio_id: string;
  nombre_completo: string;
  rol: "administrador" | "guardia" | "residente";
  estado: string;
  unidad_id: string | null;
  foto_url: string | null;
  telefono: string | null;
}

export class ErrorDeSesion extends Error {
  constructor(mensaje: string) {
    super(mensaje);
    this.name = "ErrorDeSesion";
  }
}

/**
 * Averigua quién está haciendo la petición.
 *
 * ESTO ES LO MÁS IMPORTANTE DE LA SEGURIDAD DEL SERVIDOR: la identidad se saca
 * de la sesión verificada, nunca de lo que la app manda en el mensaje. Si se
 * confiara en el mensaje, cualquiera podría decir "soy el residente de la 101"
 * y entrar.
 */
export async function quienPregunta(peticion: Request): Promise<Usuario> {
  const cabecera = peticion.headers.get("Authorization");
  if (!cabecera?.startsWith("Bearer ")) {
    throw new ErrorDeSesion("Tenés que iniciar sesión de nuevo.");
  }

  // Cliente con la llave pública, usando la sesión de quien pregunta
  const cliente = createClient(URL_SUPABASE, LLAVE_PUBLICA, {
    global: { headers: { Authorization: cabecera } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: sesion, error: errorSesion } = await cliente.auth.getUser();
  if (errorSesion || !sesion?.user) {
    throw new ErrorDeSesion("Tu sesión venció. Volvé a iniciar sesión.");
  }

  // La ficha completa se lee con la llave maestra, porque los candados de la
  // tabla de usuarios no dejan que un residente lea su condominio_id de forma
  // fiable para lo que sigue.
  const { data: ficha, error: errorFicha } = await clienteServidor()
    .from("usuarios")
    .select("id, condominio_id, nombre_completo, rol, estado, unidad_id, foto_url, telefono")
    .eq("id", sesion.user.id)
    .maybeSingle();

  if (errorFicha || !ficha) {
    throw new ErrorDeSesion(
      "Tu cuenta no está registrada en ningún condominio. Avisale a la administración.",
    );
  }

  if (ficha.estado !== "activo") {
    throw new ErrorDeSesion(
      ficha.estado === "suspendido"
        ? "Tu cuenta está suspendida. Comunicate con la administración."
        : "Tu cuenta está desactivada. Comunicate con la administración.",
    );
  }

  return ficha as Usuario;
}
