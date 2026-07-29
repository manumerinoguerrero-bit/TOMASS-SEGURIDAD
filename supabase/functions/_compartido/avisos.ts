// ============================================================================
// Tomass Seguridad — Avisos a los celulares
// ============================================================================
// Archivo de apoyo. Se encarga de avisarle a la gente cuando pasa algo.
//
// LOS AVISOS VIAJAN POR DOS CAMINOS, Y ESTO ES A PROPÓSITO
//
//   Camino 1 — DENTRO DE LA APP (funciona desde hoy, sin configurar nada).
//     El aviso se guarda en la tabla de notificaciones. Si el guardia tiene la
//     app abierta, la pantalla se actualiza SOLA en menos de un segundo. Esto ya
//     funciona: es la parte de "avisos en vivo" que se activó en la base de datos.
//
//   Camino 2 — NOTIFICACIÓN QUE SUENA (necesita Firebase, es la Fase 5).
//     Hace sonar el celular aunque la app esté cerrada o el teléfono en el
//     bolsillo. Para eso hace falta una cuenta de Firebase.
//
// POR QUÉ ESTÁ HECHO ASÍ
//
// Porque el camino 1 solo alcanza para que TODO el sistema funcione y se pueda
// probar de punta a punta antes de tocar Firebase. El guardia con la tablet
// prendida en la caseta ve el auto aparecer al instante. Firebase se suma después
// para el caso de que tenga el celular guardado.
//
// Y lo más importante: si Firebase falla o no está configurado, el acceso NO se
// cae. El residente entra igual y el aviso queda guardado. Un sistema de acceso
// que se bloquea porque falló una notificación es un sistema roto.
// ============================================================================

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import * as jose from "npm:jose@5";
import { registrar } from "./respuesta.ts";

export type TipoAviso =
  | "acceso_peatonal"
  | "acceso_vehicular_pendiente"
  | "paquete_recibido"
  | "paquete_entregado"
  | "vehiculo_aprobado"
  | "vehiculo_rechazado"
  | "visita_esperando_aprobacion"
  | "visita_ingreso"
  | "personal_servicio_ingreso"
  | "incidente_unidad"
  | "paquete_sin_retirar"
  | "sistema";

export interface Aviso {
  condominio_id: string;
  /** A quiénes se les avisa */
  usuarios: string[];
  tipo: TipoAviso;
  titulo: string;
  mensaje: string;
  /** Información extra para que la app sepa a qué pantalla llevar al tocarlo */
  datos?: Record<string, unknown>;
  /** true = suena fuerte aunque el teléfono esté en silencio */
  urgente?: boolean;
}

// ============================================================================
// CAMINO 1 · GUARDAR EL AVISO (siempre funciona)
// ============================================================================

export async function guardarAviso(
  cliente: SupabaseClient,
  aviso: Aviso,
): Promise<void> {
  if (aviso.usuarios.length === 0) return;

  const filas = aviso.usuarios.map((usuario_id) => ({
    condominio_id: aviso.condominio_id,
    usuario_id,
    tipo: aviso.tipo,
    titulo: aviso.titulo,
    mensaje: aviso.mensaje,
    datos: aviso.datos ?? {},
    urgente: aviso.urgente ?? false,
    canal: "push",
    enviada_en: new Date().toISOString(),
  }));

  const { error } = await cliente.from("notificaciones").insert(filas);

  if (error) {
    // Se anota el problema pero NO se corta la operación: el acceso importa
    // más que el aviso.
    registrar("aviso_no_se_pudo_guardar", { detalle: error.message, tipo: aviso.tipo });
  }
}

// ============================================================================
// CAMINO 2 · HACER SONAR EL CELULAR (necesita Firebase)
// ============================================================================

/** Se guarda el permiso de Firebase en memoria porque dura una hora. */
let permisoFirebase: { token: string; vence: number } | null = null;

interface CuentaFirebase {
  client_email: string;
  private_key: string;
  project_id: string;
}

function leerCuentaFirebase(): CuentaFirebase | null {
  const crudo = Deno.env.get("FIREBASE_CUENTA_SERVICIO");
  if (!crudo) return null;
  try {
    const cuenta = JSON.parse(crudo) as CuentaFirebase;
    if (!cuenta.client_email || !cuenta.private_key || !cuenta.project_id) return null;
    return cuenta;
  } catch {
    registrar("firebase_cuenta_mal_escrita");
    return null;
  }
}

/** Le pide permiso a Google para poder mandar notificaciones. */
async function pedirPermisoAFirebase(cuenta: CuentaFirebase): Promise<string | null> {
  const ahora = Math.floor(Date.now() / 1000);

  if (permisoFirebase && permisoFirebase.vence > ahora + 60) {
    return permisoFirebase.token;
  }

  try {
    const llave = await jose.importPKCS8(cuenta.private_key, "RS256");

    const solicitud = await new jose.SignJWT({
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    })
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(cuenta.client_email)
      .setSubject(cuenta.client_email)
      .setAudience("https://oauth2.googleapis.com/token")
      .setIssuedAt(ahora)
      .setExpirationTime(ahora + 3600)
      .sign(llave);

    const respuesta = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: solicitud,
      }),
    });

    if (!respuesta.ok) {
      registrar("firebase_rechazo_el_permiso", { estado: respuesta.status });
      return null;
    }

    const cuerpo = await respuesta.json() as { access_token: string; expires_in: number };
    permisoFirebase = {
      token: cuerpo.access_token,
      vence: ahora + (cuerpo.expires_in ?? 3600),
    };
    return permisoFirebase.token;
  } catch (fallo) {
    registrar("firebase_error_de_permiso", { detalle: String(fallo) });
    return null;
  }
}

/**
 * Manda la notificación que suena.
 * Si Firebase no está configurado, no hace nada y avisa en el registro.
 * Nunca lanza un error hacia afuera.
 */
export async function hacerSonarCelulares(
  cliente: SupabaseClient,
  aviso: Aviso,
): Promise<void> {
  const cuenta = leerCuentaFirebase();
  if (!cuenta) {
    registrar("firebase_sin_configurar", {
      nota: "El aviso quedó guardado y la app lo muestra en vivo. Falta la Fase 5.",
      tipo: aviso.tipo,
    });
    return;
  }

  // Los celulares registrados y activos de esas personas
  const { data: aparatos } = await cliente
    .from("dispositivos")
    .select("token_fcm")
    .in("usuario_id", aviso.usuarios)
    .eq("activo", true)
    .not("token_fcm", "is", null);

  const destinos = (aparatos ?? [])
    .map((a: { token_fcm: string | null }) => a.token_fcm)
    .filter((t): t is string => !!t);

  if (destinos.length === 0) {
    registrar("sin_celulares_registrados", { tipo: aviso.tipo });
    return;
  }

  const permiso = await pedirPermisoAFirebase(cuenta);
  if (!permiso) return;

  const direccion =
    `https://fcm.googleapis.com/v1/projects/${cuenta.project_id}/messages:send`;

  // Todos los valores de "data" tienen que ser texto: lo exige Firebase.
  const extras: Record<string, string> = { tipo: aviso.tipo };
  for (const [clave, valor] of Object.entries(aviso.datos ?? {})) {
    extras[clave] = typeof valor === "string" ? valor : JSON.stringify(valor);
  }

  await Promise.all(destinos.map(async (destino) => {
    try {
      const respuesta = await fetch(direccion, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${permiso}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: destino,
            notification: { title: aviso.titulo, body: aviso.mensaje },
            data: extras,
            // ANDROID
            //
            // El canal es lo único que hay que acertar acá. De Android 8 en
            // adelante, el canal manda: él decide el sonido, la vibración y si
            // el aviso aparece encima de lo que la persona esté haciendo. Lo
            // que se pida en este mensaje, si contradice al canal, se ignora.
            //
            // ⚠️ Estos dos nombres tienen que existir en la app, creados en
            //    android/app/src/main/kotlin/cl/tomass/tomass_seguridad/
            //    MainActivity.kt. Si acá se escriben distinto, Android no
            //    encuentra el canal, usa uno por defecto y el aviso urgente
            //    pierde su vibración y su prioridad, sin ningún error.
            android: {
              priority: aviso.urgente ? "HIGH" : "NORMAL",
              notification: {
                channel_id: aviso.urgente ? "accesos_urgentes" : "avisos",
              },
            },
            // IPHONE
            //
            // Acá no hay canales: el iPhone lee estos valores directo.
            // "time-sensitive" es lo que permite que el aviso suene aunque la
            // persona tenga puesto el modo concentración, que es justo el caso
            // del guardia de noche.
            apns: {
              headers: {
                "apns-priority": aviso.urgente ? "10" : "5",
                "apns-push-type": "alert",
              },
              payload: {
                aps: {
                  sound: "default",
                  "interruption-level": aviso.urgente ? "time-sensitive" : "active",
                  badge: 1,
                },
              },
            },
          },
        }),
      });

      if (!respuesta.ok) {
        const detalle = await respuesta.text();
        registrar("push_rechazado", { estado: respuesta.status, detalle });

        // Si el celular ya no existe (app borrada, teléfono cambiado), se marca
        // el aparato como inactivo para no seguir intentando para siempre.
        if (respuesta.status === 404 || detalle.includes("UNREGISTERED")) {
          await cliente
            .from("dispositivos")
            .update({
              activo: false,
              revocado_en: new Date().toISOString(),
              motivo_revocacion: "El celular ya no acepta notificaciones (app desinstalada).",
            })
            .eq("token_fcm", destino);
        }
      }
    } catch (fallo) {
      registrar("push_fallo_de_red", { detalle: String(fallo) });
    }
  }));
}

// ============================================================================
// LA FUNCIÓN QUE SE USA DESDE AFUERA
// ============================================================================

/**
 * Avisa por los dos caminos. Nunca corta la operación que la llamó.
 */
export async function avisar(cliente: SupabaseClient, aviso: Aviso): Promise<void> {
  try {
    await guardarAviso(cliente, aviso);
    await hacerSonarCelulares(cliente, aviso);
  } catch (fallo) {
    registrar("aviso_fallo_completo", { detalle: String(fallo), tipo: aviso.tipo });
  }
}

/**
 * Busca a qué guardias hay que avisarles por algo que pasó en una entrada.
 *
 * Incluye DOS grupos:
 *   · los que están parados justo en esa entrada, y
 *   · los que cubren TODO el condominio.
 *
 * El segundo grupo es el caso normal de este condominio: hay un solo guardia y
 * tiene que atender la entrada peatonal y la vehicular al mismo tiempo. Si solo
 * se avisara al del puesto exacto, ese guardia quedaría ciego a la mitad de lo
 * que pasa.
 *
 * La regla vive en la base de datos (función guardias_a_avisar) y no acá, para
 * que sea una sola y no haya que acordarse de repetirla en cada función que
 * manda avisos.
 */
export async function guardiasEnEsePuesto(
  cliente: SupabaseClient,
  punto_acceso_id: string,
): Promise<string[]> {
  const { data, error } = await cliente
    .rpc("guardias_a_avisar", { p_punto_acceso_id: punto_acceso_id });

  if (error) {
    registrar("no_se_pudo_saber_a_quien_avisar", { detalle: error.message });
    return [];
  }

  return (data as { guardia_id: string }[] ?? []).map((t) => t.guardia_id);
}

/**
 * Si en el puesto no hay nadie de turno, el aviso va a los administradores.
 * Así un ingreso nunca queda sin que nadie se entere.
 */
export async function administradores(
  cliente: SupabaseClient,
  condominio_id: string,
): Promise<string[]> {
  const { data } = await cliente
    .from("usuarios")
    .select("id")
    .eq("condominio_id", condominio_id)
    .eq("rol", "administrador")
    .eq("estado", "activo");

  return (data ?? []).map((u: { id: string }) => u.id);
}
