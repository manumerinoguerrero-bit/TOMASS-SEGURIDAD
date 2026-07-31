// ============================================================================
// Tomass Seguridad — Borrar las fotos de encomiendas ya entregadas
// ============================================================================
// QUÉ HACE Y POR QUÉ
//
//   La foto de una encomienda es el respaldo del condominio mientras el paquete
//   está en portería o recién entregado: si el residente reclama que llegó
//   dañado, ahí está la prueba. Pero una vez que firmó y se lo llevó, esa foto
//   va perdiendo sentido, y a los 6 meses ya no lo tiene ninguno.
//
//   Guardarlas para siempre sale caro: con ~90 encomiendas por día entre las
//   instalaciones, son más de 1 GB por mes solo en fotos de cajas. En cinco
//   años se estaría pagando por 80 GB de fotos de cajas de 2026.
//
//   Esto borra las fotos de encomiendas ENTREGADAS hace más de 6 meses. El
//   registro escrito y la FIRMA quedan intactos para siempre: eso es lo que
//   vale como constancia, y pesa casi nada.
//
// CÓMO SE EJECUTA
//
//   Solo, todas las madrugadas. El "reloj despertador" de la base de datos
//   (pg_cron) llama a esta función una vez por día. Manuel no tiene que hacer
//   nada, nunca.
//
// POR QUÉ NO ES PELIGROSO QUE ALGUIEN LA LLAME
//
//   La función no recibe instrucciones: hace siempre lo mismo, con la regla
//   fija de los 6 meses. Si alguien ajeno la invocara, lo único que lograría es
//   adelantar unas horas una limpieza que iba a pasar igual esa madrugada. No
//   devuelve datos de nadie, solo cuántas fotos borró.
//
// POR QUÉ VA DE A TANDAS DE 200
//
//   El primer día que se active con años de fotos acumuladas, borrar todo de
//   una tardaría demasiado y podría cortarse a la mitad. De a 200 por noche,
//   se pone al día en pocos días y después mantiene el ritmo sin esfuerzo.
// ============================================================================

import { clienteServidor } from "../_compartido/clientes.ts";
import { error, exito, registrar, saludoPrevio } from "../_compartido/respuesta.ts";

/// Cuántos meses se guarda la foto de una encomienda ya entregada.
/// Lo decidió Manuel: pasado ese tiempo, el reclamo ya no llega.
const MESES_QUE_SE_GUARDA = 6;

/// Cuántas encomiendas se limpian por pasada.
const TANDA = 200;

Deno.serve(async (peticion: Request) => {
  if (peticion.method === "OPTIONS") return saludoPrevio();
  if (peticion.method !== "POST") return error("Método no permitido.", 405);

  try {
    const servidor = clienteServidor();

    const limite = new Date();
    limite.setMonth(limite.getMonth() - MESES_QUE_SE_GUARDA);

    // Encomiendas entregadas hace más de 6 meses que todavía tienen foto
    const { data: viejas, error: fallaLista } = await servidor
      .from("paquetes")
      .select("id, foto_url, foto_entrega_url")
      .eq("estado", "entregado")
      .lt("entregado_en", limite.toISOString())
      .is("fotos_borradas_en", null)
      .or("foto_url.not.is.null,foto_entrega_url.not.is.null")
      .limit(TANDA);

    if (fallaLista) {
      registrar("limpieza_no_pudo_listar", { detalle: fallaLista.message });
      return error("No se pudo armar la lista de fotos viejas.", 500);
    }

    if (!viejas || viejas.length === 0) {
      return exito({ paquetes: 0, mensaje: "No hay fotos viejas que borrar." });
    }

    // Las rutas de los archivos. Cada encomienda puede tener dos fotos: la de
    // cuando llegó y la de cuando se entregó. Las dos viven en el cajón
    // "paquetes". La FIRMA vive en otro cajón y NO se toca.
    const rutas: string[] = [];
    for (const p of viejas) {
      if (p.foto_url) rutas.push(p.foto_url);
      if (p.foto_entrega_url) rutas.push(p.foto_entrega_url);
    }

    // Primero se borran los ARCHIVOS. Si esto falla, no se marca nada: la
    // próxima madrugada se reintenta solo. Al revés sería peor: quedarían
    // archivos huérfanos ocupando espacio sin que nadie los pueda encontrar.
    const { error: fallaBorrado } = await servidor.storage
      .from("paquetes")
      .remove(rutas);

    if (fallaBorrado) {
      registrar("limpieza_no_pudo_borrar", { detalle: fallaBorrado.message });
      return error("No se pudieron borrar los archivos. Se reintenta mañana.", 500);
    }

    // Y recién ahora se anota en cada encomienda que su foto ya no está, y
    // desde cuándo. Así la app puede mostrar "foto borrada por antigüedad" en
    // vez de un error de imagen faltante.
    const ids = viejas.map((p) => p.id);
    const { error: fallaMarca } = await servidor
      .from("paquetes")
      .update({
        foto_url: null,
        foto_entrega_url: null,
        fotos_borradas_en: new Date().toISOString(),
      })
      .in("id", ids);

    if (fallaMarca) {
      // Los archivos ya no están pero las filas siguen apuntándolos. No es
      // grave: la próxima pasada los archivos ya no existen y el remove() de
      // rutas inexistentes no falla, así que se termina de marcar igual.
      registrar("limpieza_no_pudo_marcar", { detalle: fallaMarca.message });
    }

    registrar("fotos_viejas_borradas", {
      paquetes: ids.length,
      archivos: rutas.length,
    });

    return exito({
      paquetes: ids.length,
      archivos: rutas.length,
      mensaje:
        `Se borraron las fotos de ${ids.length} encomiendas entregadas hace ` +
        `más de ${MESES_QUE_SE_GUARDA} meses. Las firmas quedan intactas.`,
    });
  } catch (falla) {
    registrar("limpieza_error_inesperado", { detalle: String(falla) });
    return error("Algo salió mal en la limpieza. Se reintenta mañana.", 500);
  }
});
