// ============================================================================
// Tomass Seguridad — Borrar las fotos de encomiendas que ya salieron en un PDF
// ============================================================================
// PARA QUÉ SIRVE
//
//   En el panel web (pestaña Paquetes), el administrador descarga el PDF de
//   las encomiendas entregadas, con foto y firma. Una vez guardado ese PDF, las
//   fotos ya no hacen falta en el servidor: están en el papel. Este botón las
//   borra para ir liberando espacio, sin esperar los 6 meses de la limpieza
//   automática (limpiar-fotos).
//
// QUÉ SE BORRA Y QUÉ NO
//
//   SE BORRA:   la foto de cuando llegó el paquete y la de la entrega.
//   NO SE TOCA: la FIRMA del residente, ni el registro escrito (quién recibió,
//               quién retiró, a qué hora). Eso queda para siempre.
//   NUNCA:      encomiendas que siguen en portería. Mientras el paquete no se
//               entrega, la foto es la prueba de cómo llegó.
//
// POR QUÉ ES UNA FUNCIÓN DEL SERVIDOR Y NO SE HACE DESDE EL NAVEGADOR
//
//   Los candados de la base de datos dejan al administrador tocar solo la
//   instalación que tiene "activa" en la app. El panel web, en cambio, muestra
//   todas sus instalaciones a la vez. Acá se comprueba a mano, con la sesión
//   verificada, que cada encomienda sea de una instalación que esa persona
//   administra, y recién ahí se borra con la llave maestra.
//
// QUÉ RECIBE
//
//   { ids: [uuid, ...] }  → las encomiendas que quedaron en el PDF.
//
//   No se confía en nada más de lo que manda el navegador: las rutas de los
//   archivos se vuelven a leer de la base de datos, y se descarta todo lo que
//   no cumpla las reglas de arriba.
// ============================================================================

import { clienteServidor, ErrorDeSesion, quienPregunta } from "../_compartido/clientes.ts";
import { error, exito, registrar, saludoPrevio } from "../_compartido/respuesta.ts";

/// Máximo de encomiendas por pedido (el panel trae hasta 1000 por vista).
const MAXIMO_POR_PEDIDO = 1000;

/// Storage acepta listas largas, pero de a 100 archivos no se corta a la mitad.
const TANDA_ARCHIVOS = 100;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (peticion: Request) => {
  if (peticion.method === "OPTIONS") return saludoPrevio();
  if (peticion.method !== "POST") return error("Método no permitido.", 405);

  try {
    // 1 · Quién pide. Solo un administrador activo.
    const yo = await quienPregunta(peticion);
    if (yo.rol !== "administrador") {
      return error("Solo el administrador puede borrar fotos.", 403);
    }

    // 2 · Qué pide. Una lista de ids válidos, sin repetidos.
    let cuerpo: { ids?: unknown };
    try {
      cuerpo = await peticion.json();
    } catch {
      return error("Pedido mal armado.", 400);
    }
    const ids = Array.isArray(cuerpo.ids)
      ? [...new Set(cuerpo.ids.filter((x): x is string => typeof x === "string" && UUID.test(x)))]
      : [];
    if (ids.length === 0) return error("No llegó ninguna encomienda para borrar.", 400);
    if (ids.length > MAXIMO_POR_PEDIDO) {
      return error(`Máximo ${MAXIMO_POR_PEDIDO} encomiendas por vez.`, 400);
    }

    const servidor = clienteServidor();

    // 3 · Las instalaciones que administra: la suya + las asignadas.
    const { data: asignadas, error: fallaAsignadas } = await servidor
      .from("administra_instalaciones")
      .select("condominio_id")
      .eq("usuario_id", yo.id);
    if (fallaAsignadas) {
      registrar("borrar_informadas_no_pudo_leer_instalaciones", { detalle: fallaAsignadas.message });
      return error("No se pudo comprobar tus instalaciones.", 500);
    }
    const misInstalaciones = new Set<string>([
      yo.condominio_id,
      ...(asignadas ?? []).map((a) => a.condominio_id as string),
    ]);

    // 4 · Se vuelven a leer las encomiendas desde la base. Solo quedan las
    //     ENTREGADAS, de MIS instalaciones, que todavía tienen foto.
    const { data: filas, error: fallaLista } = await servidor
      .from("paquetes")
      .select("id, condominio_id, foto_url, foto_entrega_url")
      .in("id", ids)
      .eq("estado", "entregado")
      .is("fotos_borradas_en", null);
    if (fallaLista) {
      registrar("borrar_informadas_no_pudo_listar", { detalle: fallaLista.message });
      return error("No se pudo armar la lista de fotos.", 500);
    }

    const aBorrar = (filas ?? []).filter((f) => misInstalaciones.has(f.condominio_id));
    if (aBorrar.length === 0) {
      return exito({
        paquetes: 0,
        archivos: 0,
        ids: [],
        mensaje: "No había fotos para borrar (ya estaban borradas o no corresponden).",
      });
    }

    const rutas: string[] = [];
    for (const f of aBorrar) {
      if (f.foto_url) rutas.push(f.foto_url);
      if (f.foto_entrega_url) rutas.push(f.foto_entrega_url);
    }

    // 5 · Primero los ARCHIVOS. Si falla, no se marca nada: mejor un archivo
    //     de más que una fila que dice "borrada" con la foto ocupando espacio.
    for (let i = 0; i < rutas.length; i += TANDA_ARCHIVOS) {
      const { error: fallaBorrado } = await servidor.storage
        .from("paquetes")
        .remove(rutas.slice(i, i + TANDA_ARCHIVOS));
      if (fallaBorrado) {
        registrar("borrar_informadas_no_pudo_borrar", { detalle: fallaBorrado.message, desde: i });
        return error("No se pudieron borrar los archivos. Probá de nuevo en un rato.", 500);
      }
    }

    // 6 · Y recién ahora se marca la encomienda. foto_url no se vacía porque
    //     la columna es obligatoria: la marca fotos_borradas_en es la que
    //     avisa que el archivo ya no existe.
    const idsBorrados = aBorrar.map((f) => f.id as string);
    const { error: fallaMarca } = await servidor
      .from("paquetes")
      .update({
        foto_entrega_url: null,
        fotos_borradas_en: new Date().toISOString(),
      })
      .in("id", idsBorrados);
    if (fallaMarca) {
      // Los archivos ya no están. Repetir el botón termina de marcar: borrar
      // un archivo que ya no existe no da error.
      registrar("borrar_informadas_no_pudo_marcar", { detalle: fallaMarca.message });
      return error("Las fotos se borraron pero no se pudo anotar. Repetí el botón.", 500);
    }

    registrar("fotos_informadas_borradas", {
      administrador: yo.id,
      paquetes: idsBorrados.length,
      archivos: rutas.length,
    });

    return exito({
      paquetes: idsBorrados.length,
      archivos: rutas.length,
      ids: idsBorrados,
      mensaje: `Se borraron las fotos de ${idsBorrados.length} encomiendas. ` +
        "Las firmas y el registro quedan intactos.",
    });
  } catch (falla) {
    if (falla instanceof ErrorDeSesion) return error(falla.message, 401);
    registrar("borrar_informadas_error_inesperado", { detalle: String(falla) });
    return error("Algo salió mal al borrar las fotos.", 500);
  }
});
