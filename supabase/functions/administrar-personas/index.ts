// ============================================================================
// Tomass Seguridad — Dar de alta y administrar personas
// ============================================================================
// QUÉ HACE
//
//   Le permite al administrador crear residentes, apoderados y guardias desde
//   el panel, sin tener que entrar a la base de datos por atrás.
//
// POR QUÉ ESTO NO PUEDE VIVIR EN LA APP
//
//   Crear la CUENTA DE ACCESO de alguien (el correo y la contraseña con los que
//   entra) exige la llave maestra del servidor. Esa llave nunca puede estar
//   dentro de la app: cualquiera que baje el archivo de la app la podría sacar,
//   y con ella tendría el control de todo el sistema.
//
//   Por eso la app le pide a este archivo que lo haga, y este archivo corre en
//   el servidor, donde la llave maestra está a salvo.
//
// LAS TRES COSAS QUE HACE
//
//   crear             → da de alta a una persona nueva, con su cuenta de acceso
//   cambiar_estado    → la activa, desactiva o suspende
//   restablecer_clave → le pone una contraseña nueva, para cuando la olvidó
//
// ⚠️ QUIÉN PUEDE USAR ESTO
//
//   Solo un administrador ACTIVO, y solo sobre gente de SU PROPIA instalación.
//   Las dos cosas se revisan acá adentro, contra la sesión verificada, y nunca
//   contra lo que venga escrito en el mensaje. Si se confiara en el mensaje,
//   cualquiera podría decir "soy administrador" y crearse un usuario.
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { clienteServidor, ErrorDeSesion, quienPregunta } from "../_compartido/clientes.ts";
import { error, exito, registrar, saludoPrevio } from "../_compartido/respuesta.ts";

/**
 * En qué instalación está trabajando el administrador AHORA.
 *
 * POR QUÉ NO ALCANZA CON usuarios.condominio_id
 *
 *   Tomass Seguridad Privada atiende varias instalaciones, y su administrador
 *   se cambia entre ellas con el selector del panel. Su condominio_id sigue
 *   siendo el de siempre; la que está atendiendo ahora es otra cosa.
 *
 *   Sin esto, un administrador parado en el Colegio Alemán daría de alta a los
 *   apoderados en Los Aromos, y recién se daría cuenta cuando la gente no
 *   apareciera en la lista.
 *
 * POR QUÉ SE LE PREGUNTA A LA BASE Y NO SE CALCULA ACÁ
 *
 *   Porque la base ya sabe la respuesta y, sobre todo, ya sabe VALIDARLA: si el
 *   administrador tuviera anotada una instalación que no le corresponde, la
 *   función mi_condominio() la ignora y devuelve la suya. Repetir esa lógica
 *   acá sería tener dos reglas que se pueden desincronizar, y la que manda es
 *   la de la base.
 */
async function instalacionEnLaQueTrabaja(peticion: Request): Promise<string | null> {
  const cliente = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: peticion.headers.get("Authorization")! } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );

  const { data, error: falla } = await cliente.rpc("mi_condominio");
  if (falla) {
    registrar("no_se_pudo_saber_la_instalacion", { detalle: falla.message });
    return null;
  }
  return data as string | null;
}

interface Peticion {
  accion: "crear" | "cambiar_estado" | "restablecer_clave";
  // Para crear
  nombre_completo?: string;
  email?: string;
  rol?: "residente" | "guardia" | "administrador";
  telefono?: string;
  cedula?: string;
  unidad_id?: string | null;
  relacion_unidad?: string | null;
  // Para las otras dos
  usuario_id?: string;
  estado?: "activo" | "inactivo" | "suspendido";
}

/** Arma una contraseña provisoria fácil de dictar por teléfono. */
function claveProvisoria(): string {
  // Se evitan las letras y números que se confunden al dictar: O/0, I/l/1.
  const letras = "ABCDEFGHJKMNPQRSTUVWXYZ";
  const numeros = "23456789";
  const azar = (origen: string, cuantos: number) =>
    Array.from(
      { length: cuantos },
      () => origen[Math.floor(Math.random() * origen.length)],
    ).join("");
  return `${azar(letras, 4)}${azar(numeros, 4)}`;
}

Deno.serve(async (peticion: Request) => {
  if (peticion.method === "OPTIONS") return saludoPrevio();
  if (peticion.method !== "POST") return error("Método no permitido.", 405);

  try {
    // La identidad sale de la sesión verificada, nunca del mensaje.
    const quien = await quienPregunta(peticion);

    if (quien.rol !== "administrador") {
      return error(
        "Solo la administración puede dar de alta o modificar personas.",
        403,
        { titulo: "NO TENÉS PERMISO" },
      );
    }

    // Todo lo que sigue pasa en la instalacion que esta administrando AHORA,
    // que puede no ser la suya propia.
    const instalacion = await instalacionEnLaQueTrabaja(peticion);
    if (!instalacion) {
      return error(
        "No se pudo determinar en que instalacion estas trabajando. " +
        "Volve a entrar y proba de nuevo.",
        500,
      );
    }

    const cuerpo = (await peticion.json()) as Peticion;
    const servidor = clienteServidor();

    // ------------------------------------------------------------------
    // CREAR UNA PERSONA
    // ------------------------------------------------------------------
    if (cuerpo.accion === "crear") {
      const nombre = (cuerpo.nombre_completo ?? "").trim();
      const email = (cuerpo.email ?? "").trim().toLowerCase();
      const rol = cuerpo.rol ?? "residente";

      if (nombre.length < 3) {
        return error("Falta el nombre completo de la persona.", 400);
      }
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
        return error("Ese correo no parece válido. Revisalo.", 400);
      }
      if (!["residente", "guardia", "administrador"].includes(rol)) {
        return error("Ese rol no existe.", 400);
      }

      // Que no exista ya, para dar un mensaje claro en vez de un error crudo
      const { data: yaEsta } = await servidor
        .from("usuarios")
        .select("id, condominio_id")
        .eq("email", email)
        .maybeSingle();

      if (yaEsta) {
        return error(
          yaEsta.condominio_id === instalacion
            ? "Ya hay una persona registrada con ese correo en esta instalación."
            : "Ese correo ya está en uso en otra instalación.",
          409,
          { titulo: "CORREO REPETIDO" },
        );
      }

      // Si viene un espacio (unidad o curso), tiene que ser de ESTA instalación.
      // Sin esta revisión, un administrador podría colgar a alguien de una
      // unidad de otro condominio.
      if (cuerpo.unidad_id) {
        const { data: espacio } = await servidor
          .from("unidades")
          .select("id")
          .eq("id", cuerpo.unidad_id)
          .eq("condominio_id", instalacion)
          .maybeSingle();

        if (!espacio) {
          return error("Ese espacio no pertenece a esta instalación.", 400);
        }
      }

      const clave = claveProvisoria();

      const { data: cuenta, error: fallaCuenta } = await servidor.auth.admin
        .createUser({
          email,
          password: clave,
          email_confirm: true,
        });

      if (fallaCuenta || !cuenta?.user) {
        registrar("no_se_pudo_crear_la_cuenta", { detalle: fallaCuenta?.message });
        return error(
          "No se pudo crear la cuenta de acceso. Probá de nuevo en un momento.",
          500,
        );
      }

      const { error: fallaFicha } = await servidor.from("usuarios").insert({
        id: cuenta.user.id,
        condominio_id: instalacion,
        nombre_completo: nombre,
        email,
        rol,
        estado: "activo",
        telefono: cuerpo.telefono?.trim() || null,
        cedula: cuerpo.cedula?.trim() || null,
        unidad_id: cuerpo.unidad_id || null,
        relacion_unidad: cuerpo.relacion_unidad || null,
      });

      if (fallaFicha) {
        // Si la ficha falla, se borra la cuenta recién creada. Sin esto quedaría
        // una cuenta de acceso huérfana: la persona podría entrar pero la app no
        // sabría quién es, y el correo quedaría ocupado para siempre.
        await servidor.auth.admin.deleteUser(cuenta.user.id);
        registrar("no_se_pudo_crear_la_ficha", { detalle: fallaFicha.message });
        return error("No se pudo guardar la ficha de la persona.", 500);
      }

      return exito({
        usuario_id: cuenta.user.id,
        email,
        clave_provisoria: clave,
        mensaje:
          `${nombre} ya puede entrar con el correo ${email} y la contraseña ` +
          `${clave}. Pedile que la cambie apenas entre.`,
      });
    }

    // ------------------------------------------------------------------
    // ACTIVAR, DESACTIVAR O SUSPENDER
    // ------------------------------------------------------------------
    if (cuerpo.accion === "cambiar_estado") {
      if (!cuerpo.usuario_id || !cuerpo.estado) {
        return error("Falta decir a quién y a qué estado.", 400);
      }
      if (cuerpo.usuario_id === quien.id) {
        return error(
          "No podés desactivarte a vos mismo: te quedarías sin poder entrar.",
          400,
          { titulo: "OJO" },
        );
      }

      const { data: persona } = await servidor
        .from("usuarios")
        .select("id, nombre_completo")
        .eq("id", cuerpo.usuario_id)
        .eq("condominio_id", instalacion)
        .maybeSingle();

      if (!persona) {
        return error("Esa persona no está en tu instalación.", 404);
      }

      await servidor
        .from("usuarios")
        .update({ estado: cuerpo.estado })
        .eq("id", cuerpo.usuario_id);

      // Si se la desactiva, se le dan de baja los teléfonos: si no, le seguirían
      // llegando avisos a alguien que ya no pertenece a la instalación.
      if (cuerpo.estado !== "activo") {
        await servidor
          .from("dispositivos")
          .update({
            activo: false,
            revocado_en: new Date().toISOString(),
            motivo_revocacion: "La administración desactivó a la persona.",
          })
          .eq("usuario_id", cuerpo.usuario_id);
      }

      return exito({
        mensaje: `${persona.nombre_completo} quedó en estado "${cuerpo.estado}".`,
      });
    }

    // ------------------------------------------------------------------
    // PONERLE UNA CONTRASEÑA NUEVA
    // ------------------------------------------------------------------
    if (cuerpo.accion === "restablecer_clave") {
      if (!cuerpo.usuario_id) return error("Falta decir a quién.", 400);

      const { data: persona } = await servidor
        .from("usuarios")
        .select("id, nombre_completo, email")
        .eq("id", cuerpo.usuario_id)
        .eq("condominio_id", instalacion)
        .maybeSingle();

      if (!persona) {
        return error("Esa persona no está en tu instalación.", 404);
      }

      const clave = claveProvisoria();
      const { error: falla } = await servidor.auth.admin.updateUserById(
        cuerpo.usuario_id,
        { password: clave },
      );

      if (falla) {
        registrar("no_se_pudo_cambiar_la_clave", { detalle: falla.message });
        return error("No se pudo cambiar la contraseña.", 500);
      }

      return exito({
        clave_provisoria: clave,
        mensaje:
          `La contraseña de ${persona.nombre_completo} ahora es ${clave}. ` +
          `Pedile que la cambie apenas entre.`,
      });
    }

    return error("No entendí qué querés hacer.", 400);
  } catch (falla) {
    if (falla instanceof ErrorDeSesion) {
      return error(falla.message, 401, { hay_que_iniciar_sesion: true });
    }
    registrar("error_inesperado_administrar_personas", { detalle: String(falla) });
    return error("Algo salió mal. Probá de nuevo.", 500);
  }
});
