// ============================================================================
// Tomass Seguridad — Helper para exportar datos como PDF
// ============================================================================
// Usa jsPDF + jsPDF-AutoTable (ambas cargadas por CDN desde panel.html).
//
// Cada export tiene un HEADER con el branding Tomass (barra grafito, logo T
// rojo, título) y un pie con fecha/hora de generación. Las tablas se
// autoajustan por ancho de columna y hacen saltos de página solos.
//
// Uso:
//   descargarPDF({
//     nombreArchivo: 'ingresos-milagros.pdf',
//     titulo: 'Ingresos — Condominio Milagros',
//     subtitulo: 'Del 01/09/2026 al 30/09/2026',
//     orientacion: 'landscape', // o 'portrait'
//     columnas: [
//       { campo: 'ocurrido_en', titulo: 'Fecha', ancho: 28 },
//       { campo: 'nombre',      titulo: 'Persona' },
//     ],
//     filas: [...],
//   });
// ============================================================================

const COLOR_GRAFITO = [13, 43, 94];     // #0D2B5E
const COLOR_ROJO    = [198, 40, 40];    // #C62828
const COLOR_VERDE   = [39, 174, 96];    // #27AE60
const COLOR_TEXTO_SUAVE = [107, 114, 128];

async function descargarPDF({
  nombreArchivo,
  titulo,
  subtitulo = '',
  orientacion = 'portrait',
  columnas,
  filas,
}) {
  const { jsPDF } = window.jspdf;
  const doc = new jsPDF({
    orientation: orientacion,
    unit: 'mm',
    format: 'a4',
  });

  const anchoHoja = doc.internal.pageSize.getWidth();
  const altoHoja = doc.internal.pageSize.getHeight();

  // --- HEADER ---
  dibujarEncabezado(doc, anchoHoja, titulo, subtitulo);

  // --- TABLA ---
  const defs = columnas.map((c) =>
    typeof c === 'string' ? { campo: c, titulo: c } : c
  );
  const head = [defs.map((d) => d.titulo)];
  const body = filas.map((f) =>
    defs.map((d) => formatearValorPdf(f[d.campo]))
  );
  const columnStyles = {};
  defs.forEach((d, i) => {
    if (d.ancho) columnStyles[i] = { cellWidth: d.ancho };
  });

  doc.autoTable({
    startY: 32,
    head,
    body,
    columnStyles,
    styles: {
      font: 'helvetica',
      fontSize: 8.5,
      cellPadding: 2.5,
      overflow: 'linebreak',
      textColor: [26, 26, 46],
    },
    headStyles: {
      fillColor: COLOR_GRAFITO,
      textColor: 255,
      fontSize: 8.5,
      fontStyle: 'bold',
      halign: 'left',
    },
    alternateRowStyles: {
      fillColor: [250, 251, 252],
    },
    margin: { left: 10, right: 10, top: 32, bottom: 18 },
    // Pie en cada página: fecha generación + número de página.
    didDrawPage: (data) => {
      dibujarPie(doc, anchoHoja, altoHoja,
        data.pageNumber, doc.internal.getNumberOfPages());
    },
  });

  // Si no hay filas, autoTable igual dibuja la primera página con el pie,
  // pero conviene avisar en el PDF que está vacío.
  if (filas.length === 0) {
    doc.setFontSize(11);
    doc.setTextColor(...COLOR_TEXTO_SUAVE);
    doc.text('Sin datos para los filtros seleccionados.',
      anchoHoja / 2, 50, { align: 'center' });
  }

  doc.save(nombreArchivo);
}

function dibujarEncabezado(doc, anchoHoja, titulo, subtitulo) {
  // Barra superior en grafito
  doc.setFillColor(...COLOR_GRAFITO);
  doc.rect(0, 0, anchoHoja, 22, 'F');

  // Cuadrado rojo con "T" (simulación del logo sin cargar PNG)
  doc.setFillColor(...COLOR_ROJO);
  doc.rect(10, 5, 12, 12, 'F');
  doc.setTextColor(255);
  doc.setFontSize(13);
  doc.setFont('helvetica', 'bold');
  doc.text('T', 13.5, 13);

  // Marca y títulos
  doc.setFontSize(13);
  doc.setFont('helvetica', 'bold');
  doc.text('TOMASS SEGURIDAD', 26, 10);
  doc.setFontSize(9);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(220, 220, 230);
  doc.text('Panel de administración', 26, 15);

  // Título del informe (debajo de la barra)
  doc.setTextColor(13, 43, 94);
  doc.setFontSize(14);
  doc.setFont('helvetica', 'bold');
  doc.text(titulo, 10, 28);
  if (subtitulo) {
    doc.setFontSize(9);
    doc.setFont('helvetica', 'normal');
    doc.setTextColor(...COLOR_TEXTO_SUAVE);
    doc.text(subtitulo, anchoHoja - 10, 28, { align: 'right' });
  }
}

function dibujarPie(doc, anchoHoja, altoHoja, pagina, total) {
  const y = altoHoja - 10;
  doc.setDrawColor(229, 231, 235);
  doc.line(10, y - 4, anchoHoja - 10, y - 4);

  doc.setFontSize(8);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...COLOR_TEXTO_SUAVE);

  const ahora = new Date();
  const stamp = ahora.toLocaleString('es-CL', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
  doc.text(`Generado el ${stamp} · Tomass Seguridad Privada`, 10, y);
  doc.text(`Página ${pagina} de ${total}`, anchoHoja - 10, y,
    { align: 'right' });
}

// ============================================================================
// Descarga de imágenes para embeber en PDF
// ============================================================================

/**
 * Baja una imagen (URL firmada de Supabase Storage) y la devuelve como
 * dataURL base64. Devuelve null si falla, para que el PDF pueda seguir
 * sin esa imagen.
 */
async function fetchComoDataUrl(url) {
  if (!url) return null;
  try {
    const resp = await fetch(url);
    if (!resp.ok) return null;
    const blob = await resp.blob();
    return await new Promise((resolve) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result);
      reader.onerror = () => resolve(null);
      reader.readAsDataURL(blob);
    });
  } catch (_) {
    return null;
  }
}

/** Detecta el formato de imagen a partir de un dataURL. */
function formatoImagenDeDataUrl(dataUrl) {
  if (!dataUrl) return 'PNG';
  if (dataUrl.startsWith('data:image/jpeg') ||
      dataUrl.startsWith('data:image/jpg')) return 'JPEG';
  if (dataUrl.startsWith('data:image/webp')) return 'WEBP';
  return 'PNG';
}

// ============================================================================
// PDF de paquetes CON foto de entrega + firma embebidas
// ============================================================================
// Formato distinto al tabular: una tarjeta por paquete, 2 por hoja A4
// portrait. Es el mismo diseño que el PDF del Informe de Encomiendas de la
// app Flutter — así el mandante ve "el mismo producto" sin importar desde
// dónde se saque.
//
// Como embeber imágenes es lento (requiere bajarlas desde Storage con URL
// firmada), el llamador pasa un callback `alProgresar(hechos, total)` que
// la UI usa para pintar progreso.

async function descargarPdfPaquetesConPruebas({
  filas,
  nombreArchivo,
  titulo,
  subtitulo = '',
  alProgresar = null,
}) {
  // 1) Bajar todas las fotos y firmas en tandas paralelas de 5 — ni una
  //    por una (lento) ni todas de golpe (satura Storage y traba el browser).
  const imagenesPorFila = new Map();  // id -> { foto, firma }
  const tandasDe = 5;
  let hechos = 0;
  for (let i = 0; i < filas.length; i += tandasDe) {
    const grupo = filas.slice(i, i + tandasDe);
    await Promise.all(grupo.map(async (f) => {
      const [foto, firma] = await Promise.all([
        f.foto_entrega_url
          ? api.urlFoto('paquetes', f.foto_entrega_url).then(fetchComoDataUrl)
          : Promise.resolve(null),
        f.firma_url
          ? api.urlFoto('firmas', f.firma_url).then(fetchComoDataUrl)
          : Promise.resolve(null),
      ]);
      imagenesPorFila.set(f.id, { foto, firma });
      hechos++;
      if (alProgresar) alProgresar(hechos, filas.length);
    }));
  }

  // 2) Armar el PDF.
  const { jsPDF } = window.jspdf;
  const doc = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });
  const anchoHoja = doc.internal.pageSize.getWidth();
  const altoHoja = doc.internal.pageSize.getHeight();
  dibujarEncabezado(doc, anchoHoja, titulo, subtitulo);

  // 2 tarjetas por página. Cada tarjeta ocupa 125 mm de alto.
  const yInicio = [34, 162];   // posiciones Y de cada tarjeta en la página
  const altoTarjeta = 122;
  const margenLat = 10;
  const anchoTarjeta = anchoHoja - margenLat * 2;

  filas.forEach((f, i) => {
    const posEnPagina = i % 2;
    if (i > 0 && posEnPagina === 0) {
      doc.addPage();
      dibujarEncabezado(doc, anchoHoja, titulo, subtitulo);
    }

    const y = yInicio[posEnPagina];
    const imgs = imagenesPorFila.get(f.id) || {};
    dibujarTarjetaPaquete(doc, {
      x: margenLat, y, ancho: anchoTarjeta, alto: altoTarjeta,
      paquete: f,
      foto: imgs.foto,
      firma: imgs.firma,
    });
    dibujarPie(doc, anchoHoja, altoHoja,
      doc.internal.getCurrentPageInfo().pageNumber,
      doc.internal.getNumberOfPages());
  });

  doc.save(nombreArchivo);
}

/** Dibuja una tarjeta con los datos del paquete + foto + firma. */
function dibujarTarjetaPaquete(doc, { x, y, ancho, alto, paquete, foto, firma }) {
  // Marco de la tarjeta
  doc.setDrawColor(229, 231, 235);
  doc.setLineWidth(0.3);
  doc.roundedRect(x, y, ancho, alto, 2, 2);

  // Franja superior con destinatario y chip de estado
  doc.setFillColor(13, 43, 94);
  doc.roundedRect(x, y, ancho, 10, 2, 2, 'F');
  doc.setFillColor(13, 43, 94);
  doc.rect(x, y + 5, ancho, 5, 'F');

  doc.setTextColor(255);
  doc.setFontSize(11);
  doc.setFont('helvetica', 'bold');
  doc.text(paquete.destinatario || 'Sin destinatario', x + 4, y + 7);

  doc.setFontSize(8);
  doc.setFont('helvetica', 'normal');
  const chip = paquete.estado === 'entregado' ? 'ENTREGADO' : 'EN PORTERÍA';
  doc.text(chip, x + ancho - 4, y + 7, { align: 'right' });

  // Datos del paquete (lado izquierdo)
  const yCuerpo = y + 15;
  doc.setTextColor(26, 26, 46);
  doc.setFontSize(9);
  doc.setFont('helvetica', 'normal');

  const col1 = x + 4;
  const col2 = x + 44;
  const anchoLabel = 36;
  let lineaY = yCuerpo;
  const linea = (label, valor) => {
    doc.setTextColor(107, 114, 128);
    doc.setFont('helvetica', 'bold');
    doc.text(label, col1, lineaY);
    doc.setTextColor(26, 26, 46);
    doc.setFont('helvetica', 'normal');
    doc.text(String(valor || '—').substring(0, 50), col2, lineaY);
    lineaY += 5;
  };

  linea('Instalación:', paquete.condominio_nombre);
  linea('Unidad:',      paquete.unidad);
  linea('Recibido:',    formatearValorPdf(paquete.recibido_en));
  linea('Por:',         paquete.guardia_receptor);
  if (paquete.descripcion) {
    doc.setTextColor(107, 114, 128);
    doc.setFont('helvetica', 'bold');
    doc.text('Descripción:', col1, lineaY);
    doc.setTextColor(26, 26, 46);
    doc.setFont('helvetica', 'normal');
    const lines = doc.splitTextToSize(paquete.descripcion, 90);
    doc.text(lines.slice(0, 2), col2, lineaY);  // máx 2 líneas
    lineaY += 5 * Math.min(lines.length, 2);
  }

  if (paquete.estado === 'entregado') {
    lineaY += 2;
    doc.setDrawColor(229, 231, 235);
    doc.line(col1, lineaY, col1 + 95, lineaY);
    lineaY += 4;

    linea('Retiró:',       paquete.retirado_por || paquete.destinatario);
    linea('Entregado:',    formatearValorPdf(paquete.entregado_en));
    linea('Entregó:',      paquete.guardia_entrega);
    linea('Identidad:',    paquete.identidad_validada
                             ? '✓ Validada' : '⚠ Sin validar');
  }

  // Foto + firma (lado derecho)
  const xDerecha = x + 108;
  const anchoImagen = ancho - 112;

  // Foto del paquete (si hay)
  if (foto) {
    try {
      const altoFoto = 55;
      doc.addImage(foto, formatoImagenDeDataUrl(foto),
        xDerecha, yCuerpo, anchoImagen, altoFoto);
      doc.setFontSize(7);
      doc.setTextColor(107, 114, 128);
      doc.text('Foto de la entrega', xDerecha, yCuerpo + altoFoto + 3);
    } catch (_) { /* foto corrupta, ignorar */ }
  } else {
    recuadroVacio(doc, xDerecha, yCuerpo, anchoImagen, 55,
      paquete.estado === 'entregado' ? 'Sin foto' : 'Sin entrega aún');
  }

  // Firma del residente (si hay)
  const yFirma = yCuerpo + 62;
  if (firma) {
    try {
      doc.addImage(firma, formatoImagenDeDataUrl(firma),
        xDerecha, yFirma, anchoImagen, 40);
      doc.setFontSize(7);
      doc.setTextColor(107, 114, 128);
      doc.text('Firma del residente', xDerecha, yFirma + 43);
    } catch (_) { /* firma corrupta */ }
  } else if (paquete.estado === 'entregado') {
    recuadroVacio(doc, xDerecha, yFirma, anchoImagen, 40, 'Sin firma');
  }
}

function recuadroVacio(doc, x, y, w, h, texto) {
  doc.setDrawColor(229, 231, 235);
  doc.setFillColor(250, 251, 252);
  doc.roundedRect(x, y, w, h, 1, 1, 'FD');
  doc.setTextColor(156, 163, 175);
  doc.setFontSize(8);
  doc.text(texto, x + w / 2, y + h / 2 + 1, { align: 'center' });
}

/** Fechas ISO -> "YYYY-MM-DD HH:MM", booleanos -> "Sí"/"No". */
function formatearValorPdf(v) {
  if (v == null) return '';
  if (typeof v === 'boolean') return v ? 'Sí' : 'No';
  if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(v)) {
    const d = new Date(v);
    if (!isNaN(d.getTime())) {
      const pad = (n) => String(n).padStart(2, '0');
      return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ` +
        `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }
  }
  return String(v);
}

// ============================================================================
// PDF del RESUMEN cross-instalación (formato distinto: tarjetas por fila)
// ============================================================================

async function descargarPdfResumen({ filas, instalacionNombre }) {
  const { jsPDF } = window.jspdf;
  const doc = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });

  const anchoHoja = doc.internal.pageSize.getWidth();
  const altoHoja = doc.internal.pageSize.getHeight();

  dibujarEncabezado(doc, anchoHoja,
    `Resumen — ${instalacionNombre}`,
    `Generado ${new Date().toLocaleDateString('es-CL')}`);

  // Tabla con KPIs por fila (una fila por instalación)
  const columnas = [
    { campo: 'condominio_nombre', titulo: 'Instalación',           ancho: 55 },
    { campo: 'condominio_tipo',   titulo: 'Tipo',                  ancho: 20 },
    { campo: 'guardias_de_turno', titulo: 'Guardias de turno',     ancho: 20 },
    { campo: 'novedades_abiertas',titulo: 'Novedades abiertas',    ancho: 22 },
    { campo: 'novedades_criticas',titulo: 'Críticas',              ancho: 15 },
    { campo: 'paquetes_en_porteria', titulo: 'Paquetes en portería', ancho: 25 },
    { campo: 'accesos_hoy',       titulo: 'Accesos hoy',           ancho: 20 },
  ];
  const defs = columnas;

  doc.autoTable({
    startY: 32,
    head: [defs.map((d) => d.titulo)],
    body: filas.map((f) =>
      defs.map((d) => formatearValorPdf(f[d.campo]))
    ),
    columnStyles: Object.fromEntries(
      defs.map((d, i) => [i, { cellWidth: d.ancho,
        halign: i >= 2 ? 'center' : 'left' }])
    ),
    styles: {
      font: 'helvetica', fontSize: 9, cellPadding: 3,
      textColor: [26, 26, 46],
    },
    headStyles: {
      fillColor: COLOR_GRAFITO, textColor: 255,
      fontSize: 8.5, fontStyle: 'bold',
    },
    alternateRowStyles: { fillColor: [250, 251, 252] },
    margin: { left: 10, right: 10, top: 32, bottom: 18 },
    // Pintar números críticos en rojo
    didParseCell: (data) => {
      if (data.section !== 'body') return;
      const col = data.column.index;
      // Columnas 4 (críticas) y 3 (novedades abiertas): rojo si > 0
      if ((col === 3 || col === 4) && Number(data.cell.raw) > 0) {
        data.cell.styles.textColor = COLOR_ROJO;
        data.cell.styles.fontStyle = 'bold';
      }
      // Columna 2 (guardias de turno): verde si > 0, rojo si 0
      if (col === 2) {
        data.cell.styles.textColor =
          Number(data.cell.raw) > 0 ? COLOR_VERDE : COLOR_ROJO;
        data.cell.styles.fontStyle = 'bold';
      }
    },
    didDrawPage: (data) => {
      dibujarPie(doc, anchoHoja, altoHoja,
        data.pageNumber, doc.internal.getNumberOfPages());
    },
  });

  doc.save(nombreArchivoSeguro(`resumen-${instalacionNombre}`) + '.pdf');
}
