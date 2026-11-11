// ============================================================================
// Tomass Seguridad — Generadores de informes del dashboard web
// ============================================================================
// Un dict `Informes` donde cada entrada es un informe distinto. Cada informe
// sabe dibujar su panel de filtros y generar su PDF.
//
// POR QUÉ SE GENERA ACÁ Y NO EN EL CELU
//   El PDF que generaba la app Flutter pedía el mapa satelital a Mapbox desde
//   la red del celular, y esa red a veces bloqueaba la respuesta — los PDFs
//   salían con "plano abstracto" en vez del mapa satelital. En la web usamos
//   Leaflet con tiles de Esri (sin API key), que es mucho más estable, y
//   capturamos el mapa con html2canvas para meterlo en el PDF. El PDF del
//   celular queda como respaldo cuando no hay computadora a mano.
// ============================================================================

const COLOR_GRAFITO_RGB = [13, 43, 94];
const COLOR_ROJO_RGB    = [198, 40, 40];
const COLOR_VERDE_RGB   = [39, 174, 96];
const COLOR_NARANJA_RGB = [245, 158, 11];
const COLOR_GRIS_RGB    = [107, 114, 128];

// --------------------------------------------------------------------------
// HELPERS COMPARTIDOS
// --------------------------------------------------------------------------

function fmtFechaHora(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  return d.toLocaleString('es-CL', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

function fmtFecha(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  return d.toLocaleDateString('es-CL',
    { day: '2-digit', month: '2-digit', year: 'numeric' });
}

function fmtHora(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  return d.toLocaleTimeString('es-CL',
    { hour: '2-digit', minute: '2-digit' });
}

function primeroDelMes() {
  const d = new Date();
  d.setDate(1); d.setHours(0, 0, 0, 0);
  return d.toISOString().slice(0, 10);
}

function hoyIso() {
  return new Date().toISOString().slice(0, 10);
}

function haceDiasIso(dias) {
  const d = new Date();
  d.setDate(d.getDate() - dias);
  return d.toISOString().slice(0, 10);
}

// Ensancha un rango YYYY-MM-DD a timestamp UTC completo (00:00 a 23:59:59)
// para que las queries agarren todo el día en la zona local del usuario.
function rangoAConsulta(desde, hasta) {
  return {
    desde: new Date(`${desde}T00:00:00`).toISOString(),
    hasta: new Date(`${hasta}T23:59:59`).toISOString(),
  };
}

function nombreCondominioActual() {
  return estado.instalaciones.find((i) => i.id === estado.condominioFiltro)?.nombre
    || 'Todas';
}

function instalacionesAccesibles() {
  return estado.instalaciones.filter((i) => !!i.id);
}

// Bota un mensaje de error/éxito en el panel del informe activo.
function avisoEnPanel(texto, tono = 'ok') {
  const cont = document.getElementById('informePanelContenido');
  if (!cont) return;
  const d = document.createElement('div');
  d.className = tono === 'err' ? 'aviso-err' : 'aviso-ok';
  d.style.marginTop = '12px';
  d.style.padding = '10px 12px';
  d.style.borderRadius = '6px';
  d.style.fontSize = '13px';
  d.style.background = tono === 'err' ? '#FEE2E2' : '#D1FAE5';
  d.style.color = tono === 'err' ? '#991B1B' : '#065F46';
  d.textContent = texto;
  cont.appendChild(d);
  setTimeout(() => d.remove(), 6000);
}

// --------------------------------------------------------------------------
// PDF HEADER ESTÁNDAR
// --------------------------------------------------------------------------

function dibujarCabeceraPdf(doc, titulo, subtitulo) {
  const ancho = doc.internal.pageSize.getWidth();
  doc.setFillColor(...COLOR_GRAFITO_RGB);
  doc.rect(0, 0, ancho, 22, 'F');
  doc.setTextColor(255, 255, 255);
  doc.setFontSize(10);
  doc.setFont('helvetica', 'bold');
  doc.text('TOMASS SEGURIDAD', 14, 10);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.text('Informe generado desde el panel web', 14, 15);

  doc.setTextColor(26, 26, 46);
  doc.setFontSize(15);
  doc.setFont('helvetica', 'bold');
  doc.text(titulo, 14, 32);
  if (subtitulo) {
    doc.setFontSize(10);
    doc.setFont('helvetica', 'normal');
    doc.setTextColor(...COLOR_GRIS_RGB);
    doc.text(subtitulo, 14, 38);
  }
}

function dibujarPiePdf(doc) {
  const paginas = doc.getNumberOfPages();
  for (let i = 1; i <= paginas; i++) {
    doc.setPage(i);
    const ancho = doc.internal.pageSize.getWidth();
    const alto = doc.internal.pageSize.getHeight();
    doc.setFontSize(7.5);
    doc.setFont('helvetica', 'normal');
    doc.setTextColor(...COLOR_GRIS_RGB);
    const ts = new Date().toLocaleString('es-CL');
    doc.text(`Generado el ${ts} · Tomass Seguridad Privada`, 14, alto - 8);
    doc.text(`Página ${i} de ${paginas}`, ancho - 14, alto - 8,
      { align: 'right' });
  }
}

// --------------------------------------------------------------------------
// MAPA LEAFLET OCULTO: dibuja puntos + marcas y devuelve PNG via html2canvas.
// --------------------------------------------------------------------------

async function capturarMapaComoPng({ puntos, marcas = [], rastro = [], pins = [] }) {
  const divId = 'informeMapaOculto';
  const div = document.getElementById(divId);
  if (!div) return null;
  div.innerHTML = '';
  div.style.width = '900px';
  div.style.height = '600px';

  const mapa = L.map(div, {
    zoomControl: false, attributionControl: false, preferCanvas: true,
  });
  L.tileLayer(
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    { maxZoom: 19 }
  ).addTo(mapa);
  L.tileLayer(
    'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',
    { maxZoom: 19 }
  ).addTo(mapa);
  L.tileLayer(
    'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
    { maxZoom: 19 }
  ).addTo(mapa);

  const bounds = [];
  // Puntos de control (circulos grandes grafito con número)
  for (const p of (puntos || [])) {
    if (!p.latitud || !p.longitud) continue;
    const latlng = [p.latitud, p.longitud];
    L.circle(latlng, {
      radius: p.metros_de_tolerancia || 20,
      color: '#0D2B5E', weight: 1, fillColor: '#0D2B5E', fillOpacity: 0.12,
    }).addTo(mapa);
    L.marker(latlng, {
      icon: L.divIcon({
        className: 'pin-sector',
        html: `<div style="background:#0D2B5E;color:white;border-radius:50%;width:26px;height:26px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:12px;border:2px solid white;box-shadow:0 1px 3px rgba(0,0,0,.4)">${p.orden ?? ''}</div>`,
        iconSize: [26, 26], iconAnchor: [13, 13],
      }),
    }).addTo(mapa);
    bounds.push(latlng);
  }
  // Marcas (puntos chicos verdes o rojos según distancia)
  for (const m of (marcas || [])) {
    if (!m.marca_lat || !m.marca_lng) continue;
    const color = m.lejos ? '#C62828' : '#27AE60';
    L.circleMarker([m.marca_lat, m.marca_lng], {
      radius: 5, color: color, fillColor: color, fillOpacity: 0.9, weight: 1.5,
    }).addTo(mapa);
    bounds.push([m.marca_lat, m.marca_lng]);
  }
  // Rastro GPS (polyline)
  if (rastro.length > 1) {
    L.polyline(rastro, {
      color: '#C62828', weight: 3, opacity: 0.75,
    }).addTo(mapa);
    rastro.forEach((p) => bounds.push(p));
  }
  // Pins arbitrarios
  for (const p of pins) {
    L.circleMarker([p.lat, p.lng], {
      radius: 6, color: p.color || '#0D2B5E', fillColor: p.color || '#0D2B5E',
      fillOpacity: 0.9, weight: 2,
    }).addTo(mapa);
    bounds.push([p.lat, p.lng]);
  }

  if (bounds.length === 0) {
    mapa.setView([-33.4489, -70.6693], 12);
  } else if (bounds.length === 1) {
    mapa.setView(bounds[0], 18);
  } else {
    mapa.fitBounds(bounds, { padding: [30, 30] });
  }

  // Esperar que los tiles estén listos — crucial: si capturamos antes, el
  // mapa sale a medio cargar y aparecen cuadros grises en el PDF.
  await new Promise((resolve) => {
    let listos = 0;
    const total = 3;
    mapa.eachLayer((l) => {
      if (l instanceof L.TileLayer) {
        l.on('load', () => { listos++; if (listos >= total) resolve(); });
      }
    });
    setTimeout(resolve, 4500); // red timeout de seguridad
  });
  // Una pequeña pausa adicional para que termine el repaint final.
  await new Promise((r) => setTimeout(r, 400));

  let dataUrl = null;
  try {
    const canvas = await html2canvas(div, {
      useCORS: true, allowTaint: true, backgroundColor: null, logging: false,
    });
    dataUrl = canvas.toDataURL('image/jpeg', 0.85);
  } catch (e) {
    console.error('html2canvas falló:', e);
  }
  mapa.remove();
  div.innerHTML = '';
  return dataUrl;
}

// --------------------------------------------------------------------------
// INFORME 1: RONDAS CON MAPA SATELITAL
// --------------------------------------------------------------------------

const InformeRondas = {
  nombre: 'Informe de rondas',

  async render() {
    const condos = instalacionesAccesibles();
    const cont = document.getElementById('informePanelContenido');
    cont.innerHTML = `
      <h2 style="margin-top:0">Informe de rondas con mapa satelital</h2>
      <p style="color:var(--texto-suave);font-size:13px;margin-top:0">
        PDF con la tabla de rondas del período y un mapa satelital por cada
        ronda mostrando los sectores y las marcaciones del guardia.
      </p>
      <div class="informe-filtros">
        <label>Instalación
          <select id="rndCondo">
            ${condos.map((c) => `<option value="${escapar(c.id)}">${escapar(c.nombre)}</option>`).join('')}
          </select>
        </label>
        <label>Desde
          <input type="date" id="rndDesde" value="${haceDiasIso(7)}">
        </label>
        <label>Hasta
          <input type="date" id="rndHasta" value="${hoyIso()}">
        </label>
        <label>Guardia (opcional)
          <select id="rndGuardia"><option value="">— Todos —</option></select>
        </label>
        <label>Garita (opcional)
          <select id="rndGarita"><option value="">— Todas —</option></select>
        </label>
      </div>
      <div class="informe-botones">
        <button class="btn-primario" id="rndGenerar">Generar PDF</button>
      </div>
    `;
    const refreshFiltros = async () => {
      const condo = document.getElementById('rndCondo').value;
      if (!condo) return;
      const [guardias, garitas] = await Promise.all([
        api.guardiasDelCondominio(condo).catch(() => []),
        api.garitasDelCondominio(condo).catch(() => []),
      ]);
      document.getElementById('rndGuardia').innerHTML =
        '<option value="">— Todos —</option>' +
        guardias.map((g) =>
          `<option value="${escapar(g.id)}">${escapar(g.nombre_completo)}</option>`).join('');
      document.getElementById('rndGarita').innerHTML =
        '<option value="">— Todas —</option>' +
        garitas.map((g) => `<option value="${escapar(g.id)}">${escapar(g.nombre)}</option>`).join('');
    };
    document.getElementById('rndCondo').addEventListener('change', refreshFiltros);
    await refreshFiltros();
    document.getElementById('rndGenerar').addEventListener('click', () =>
      InformeRondas.generar());
  },

  async generar() {
    const boton = document.getElementById('rndGenerar');
    boton.disabled = true; boton.textContent = 'Generando…';
    try {
      const condoId = document.getElementById('rndCondo').value;
      const desdeStr = document.getElementById('rndDesde').value;
      const hastaStr = document.getElementById('rndHasta').value;
      const guardiaId = document.getElementById('rndGuardia').value || null;
      const garitaId = document.getElementById('rndGarita').value || null;
      if (!condoId || !desdeStr || !hastaStr) {
        throw new Error('Completá instalación y fechas.');
      }
      const { desde, hasta } = rangoAConsulta(desdeStr, hastaStr);
      const condoNombre = estado.instalaciones.find((i) => i.id === condoId)?.nombre
        || 'Instalación';

      const [rondas, marcas, puntos] = await Promise.all([
        api.informeDeRondas({ condominioId: condoId, desde, hasta, guardiaId, garitaId }),
        api.detalleDeRondas({ condominioId: condoId, desde, hasta, guardiaId, garitaId }),
        api.puntosDeControl({ condominioId: condoId, garitaId }),
      ]);

      if (rondas.length === 0) {
        throw new Error('No hay rondas en ese período con esos filtros.');
      }

      const { jsPDF } = window.jspdf;
      const doc = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });
      dibujarCabeceraPdf(doc,
        `Informe de rondas — ${condoNombre}`,
        `Del ${fmtFecha(desde)} al ${fmtFecha(hasta)}` +
        (guardiaId ? ` · ${rondas[0].guardia}` : '') +
        (garitaId && puntos[0]?.garita_nombre ? ` · ${puntos[0].garita_nombre}` : ''));

      // Tabla resumen
      doc.autoTable({
        startY: 44,
        head: [['Día', 'Hora', 'Guardia', 'Garita', 'Marcados', 'Duración', 'Completa']],
        body: rondas.map((r) => [
          fmtFecha(r.inicio), fmtHora(r.inicio),
          r.guardia || '—', r.garita || '— cubre todo —',
          `${r.marcados} / ${r.total}`, `${r.minutos} min`,
          r.completa ? '✓' : (r.cerrada_en ? '✗' : 'En curso'),
        ]),
        styles: { font: 'helvetica', fontSize: 8.5, cellPadding: 2.2 },
        headStyles: { fillColor: COLOR_GRAFITO_RGB, textColor: 255 },
      });

      // Un mapa general del período con TODAS las marcas superpuestas
      doc.addPage();
      doc.setFontSize(13); doc.setFont('helvetica', 'bold');
      doc.setTextColor(26, 26, 46);
      doc.text('Mapa general del período', 14, 20);
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(9); doc.setTextColor(...COLOR_GRIS_RGB);
      doc.text('Cada círculo grafito es un sector con su número de orden. ' +
               'Cada punto verde es una marca hecha en el lugar; rojo = marca desde lejos.',
        14, 26, { maxWidth: 180 });
      const pngGeneral = await capturarMapaComoPng({ puntos, marcas });
      if (pngGeneral) {
        doc.addImage(pngGeneral, 'JPEG', 14, 34, 180, 120);
      } else {
        doc.setTextColor(...COLOR_ROJO_RGB);
        doc.text('(No se pudo generar el mapa)', 14, 60);
      }

      // Detalle por ronda
      for (const r of rondas) {
        doc.addPage();
        doc.setTextColor(26, 26, 46);
        doc.setFontSize(12); doc.setFont('helvetica', 'bold');
        doc.text(`${fmtFecha(r.inicio)} · ${fmtHora(r.inicio)}` +
                 (r.cerrada_en ? ` a ${fmtHora(r.cerrada_en)}` : ' · en curso'), 14, 18);
        doc.setFontSize(9.5); doc.setFont('helvetica', 'normal');
        doc.setTextColor(...COLOR_GRIS_RGB);
        doc.text(`Guardia: ${r.guardia}  ·  ${r.garita || '— cubre todo —'}`, 14, 24);

        const suyas = marcas.filter((m) => m.ronda_id === r.ronda_id);
        doc.autoTable({
          startY: 30,
          head: [['Orden', 'Sector', 'Hora', 'A metros']],
          body: suyas.map((m) => [
            m.sector_orden ?? '', m.sector || '', fmtHora(m.marcado_en),
            m.metros_de_lejos == null ? 'sin GPS' : `${Math.round(m.metros_de_lejos)} m`,
          ]),
          styles: { font: 'helvetica', fontSize: 8.5, cellPadding: 2 },
          headStyles: { fillColor: COLOR_GRAFITO_RGB, textColor: 255 },
        });
        const yFin = doc.lastAutoTable.finalY || 40;
        if (suyas.length < r.total) {
          doc.setFontSize(9); doc.setTextColor(...COLOR_NARANJA_RGB);
          doc.setFont('helvetica', 'bold');
          doc.text(`Quedaron ${r.total - suyas.length} sectores sin marcar.`,
            14, yFin + 7);
        }
        if (r.notas) {
          doc.setFont('helvetica', 'normal');
          doc.setTextColor(26, 26, 46);
          doc.setFontSize(9);
          doc.text(`Notas: ${r.notas}`, 14, yFin + 14, { maxWidth: 180 });
        }

        // Mapa por ronda
        const png = await capturarMapaComoPng({ puntos, marcas: suyas });
        if (png) {
          const y = Math.max(yFin + 22, 75);
          const espacio = 290 - y - 12;
          if (espacio > 60) {
            doc.addImage(png, 'JPEG', 14, y, 180, Math.min(120, espacio));
          } else {
            doc.addPage();
            doc.addImage(png, 'JPEG', 14, 20, 180, 150);
          }
        }
      }

      dibujarPiePdf(doc);
      doc.save(`rondas-${condoNombre.replace(/\s+/g, '-').toLowerCase()}-${desdeStr}.pdf`);
      avisoEnPanel('Informe listo.', 'ok');
    } catch (e) {
      console.error(e);
      avisoEnPanel(e.message || 'No se pudo generar el informe.', 'err');
    } finally {
      boton.disabled = false; boton.textContent = 'Generar PDF';
    }
  },
};

// --------------------------------------------------------------------------
// INFORME 2: RESUMEN MENSUAL CONSOLIDADO
// --------------------------------------------------------------------------

const InformeResumenMensual = {
  nombre: 'Resumen mensual consolidado',

  async render() {
    const cont = document.getElementById('informePanelContenido');
    cont.innerHTML = `
      <h2 style="margin-top:0">Resumen mensual consolidado</h2>
      <p style="color:var(--texto-suave);font-size:13px;margin-top:0">
        PDF con una fila por instalación del mes: turnos, horas, rondas,
        novedades, paquetes y guardias activos. Útil para enviar al directorio
        o al cliente mandante.
      </p>
      <div class="informe-filtros">
        <label>Desde
          <input type="date" id="rmDesde" value="${primeroDelMes()}">
        </label>
        <label>Hasta
          <input type="date" id="rmHasta" value="${hoyIso()}">
        </label>
      </div>
      <div class="informe-botones">
        <button class="btn-primario" id="rmGenerar">Generar PDF</button>
      </div>
    `;
    document.getElementById('rmGenerar').addEventListener('click', () =>
      InformeResumenMensual.generar());
  },

  async generar() {
    const boton = document.getElementById('rmGenerar');
    boton.disabled = true; boton.textContent = 'Generando…';
    try {
      const desdeStr = document.getElementById('rmDesde').value;
      const hastaStr = document.getElementById('rmHasta').value;
      if (!desdeStr || !hastaStr) throw new Error('Completá las fechas.');
      const { desde, hasta } = rangoAConsulta(desdeStr, hastaStr);
      const filas = await api.resumenDelPeriodo({ desde, hasta });
      if (filas.length === 0) throw new Error('No hay datos en ese período.');

      const totales = filas.reduce((acc, f) => ({
        turnos_abiertos: acc.turnos_abiertos + (f.turnos_abiertos || 0),
        horas_turno: acc.horas_turno + Number(f.horas_turno || 0),
        rondas: acc.rondas + (f.rondas || 0),
        rondas_completas: acc.rondas_completas + (f.rondas_completas || 0),
        marcas_lejanas: acc.marcas_lejanas + (f.marcas_lejanas || 0),
        novedades: acc.novedades + (f.novedades || 0),
        novedades_criticas: acc.novedades_criticas + (f.novedades_criticas || 0),
        paquetes_recibidos: acc.paquetes_recibidos + (f.paquetes_recibidos || 0),
        paquetes_entregados: acc.paquetes_entregados + (f.paquetes_entregados || 0),
        paquetes_pendientes: acc.paquetes_pendientes + (f.paquetes_pendientes || 0),
        movimientos: acc.movimientos + (f.movimientos || 0),
        guardias_activos: acc.guardias_activos + (f.guardias_activos || 0),
      }), {
        turnos_abiertos: 0, horas_turno: 0, rondas: 0, rondas_completas: 0,
        marcas_lejanas: 0, novedades: 0, novedades_criticas: 0,
        paquetes_recibidos: 0, paquetes_entregados: 0, paquetes_pendientes: 0,
        movimientos: 0, guardias_activos: 0,
      });

      const { jsPDF } = window.jspdf;
      const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });
      dibujarCabeceraPdf(doc, 'Resumen consolidado del período',
        `Del ${fmtFecha(desde)} al ${fmtFecha(hasta)} · ${filas.length} instalaciones`);

      doc.autoTable({
        startY: 44,
        head: [[
          'Instalación', 'Turnos', 'Horas', 'Rondas', 'Compl.', 'Lejanas',
          'Novedades', 'Críticas', 'Paq. in', 'Paq. out', 'Pend.',
          'Accesos', 'Guardias',
        ]],
        body: filas.map((f) => [
          f.condominio_nombre, f.turnos_abiertos, Number(f.horas_turno).toFixed(0),
          f.rondas, f.rondas_completas, f.marcas_lejanas,
          f.novedades, f.novedades_criticas,
          f.paquetes_recibidos, f.paquetes_entregados, f.paquetes_pendientes,
          f.movimientos, f.guardias_activos,
        ]),
        foot: [[
          'TOTAL', totales.turnos_abiertos, totales.horas_turno.toFixed(0),
          totales.rondas, totales.rondas_completas, totales.marcas_lejanas,
          totales.novedades, totales.novedades_criticas,
          totales.paquetes_recibidos, totales.paquetes_entregados,
          totales.paquetes_pendientes, totales.movimientos,
          totales.guardias_activos,
        ]],
        styles: { font: 'helvetica', fontSize: 9, cellPadding: 2.5 },
        headStyles: { fillColor: COLOR_GRAFITO_RGB, textColor: 255 },
        footStyles: { fillColor: [240, 242, 245], textColor: COLOR_GRAFITO_RGB, fontStyle: 'bold' },
      });

      dibujarPiePdf(doc);
      doc.save(`resumen-${desdeStr}-${hastaStr}.pdf`);
      avisoEnPanel('Resumen listo.', 'ok');
    } catch (e) {
      console.error(e);
      avisoEnPanel(e.message || 'No se pudo generar el resumen.', 'err');
    } finally {
      boton.disabled = false; boton.textContent = 'Generar PDF';
    }
  },
};

// --------------------------------------------------------------------------
// INFORME 3: MAPA DE RECORRIDO GPS DEL TURNO
// --------------------------------------------------------------------------

const InformeRecorridoTurno = {
  nombre: 'Mapa de recorrido del turno',

  async render() {
    const condos = instalacionesAccesibles();
    const cont = document.getElementById('informePanelContenido');
    cont.innerHTML = `
      <h2 style="margin-top:0">Mapa de recorrido GPS del turno</h2>
      <p style="color:var(--texto-suave);font-size:13px;margin-top:0">
        Elegí un turno del período y te armo un PDF con el rastro completo del
        guardia (pings cada 3 min + marcas de ronda + accesos) sobre el mapa
        satelital. Permite ver si recorrió todos los sectores o si se quedó
        solo en garita.
      </p>
      <div class="informe-filtros">
        <label>Instalación
          <select id="rtCondo">
            ${condos.map((c) => `<option value="${c.id}">${c.nombre}</option>`).join('')}
          </select>
        </label>
        <label>Desde
          <input type="date" id="rtDesde" value="${haceDiasIso(7)}">
        </label>
        <label>Hasta
          <input type="date" id="rtHasta" value="${hoyIso()}">
        </label>
      </div>
      <button class="btn-neutro" id="rtListar">Buscar turnos</button>
      <div class="informe-vista-previa oculto" id="rtListaTurnos" style="margin-top:12px"></div>
    `;
    document.getElementById('rtListar').addEventListener('click', () =>
      InformeRecorridoTurno.listar());
  },

  async listar() {
    const boton = document.getElementById('rtListar');
    boton.disabled = true; boton.textContent = 'Buscando…';
    try {
      const condoId = document.getElementById('rtCondo').value;
      const desdeStr = document.getElementById('rtDesde').value;
      const hastaStr = document.getElementById('rtHasta').value;
      const { desde, hasta } = rangoAConsulta(desdeStr, hastaStr);
      const turnos = await api.turnosDelCondominio({
        condominioId: condoId, desde, hasta,
      });
      const div = document.getElementById('rtListaTurnos');
      div.classList.remove('oculto');
      if (turnos.length === 0) {
        div.innerHTML = '<em>No hay turnos en ese período.</em>';
        return;
      }
      div.innerHTML = `<table class="tabla" style="width:100%;font-size:12.5px">
        <thead><tr><th>Día</th><th>Guardia</th><th>Garita</th><th>Duración</th><th>Marcas</th><th>Accesos</th><th></th></tr></thead>
        <tbody>
          ${turnos.map((t) => `
            <tr>
              <td>${fmtFechaHora(t.inicio)}</td>
              <td>${escapar(t.guardia_nombre)}</td>
              <td>${escapar(t.garita)}</td>
              <td>${escapar(t.minutos)} min</td>
              <td>${escapar(t.marcas_ronda)}</td>
              <td>${escapar(t.movimientos_acceso)}</td>
              <td><button class="btn-primario" data-turno="${escapar(t.id)}">PDF</button></td>
            </tr>`).join('')}
        </tbody>
      </table>`;
      div.querySelectorAll('button[data-turno]').forEach((b) => {
        b.addEventListener('click', () =>
          InformeRecorridoTurno.generar(b.dataset.turno));
      });
    } catch (e) {
      console.error(e);
      avisoEnPanel(e.message || 'No se pudo buscar.', 'err');
    } finally {
      boton.disabled = false; boton.textContent = 'Buscar turnos';
    }
  },

  async generar(turnoId) {
    try {
      const puntos = await api.recorridoGpsTurno(turnoId);
      if (puntos.length === 0) {
        avisoEnPanel('Ese turno no tiene puntos GPS registrados.', 'err');
        return;
      }
      const rastro = puntos.filter((p) => p.lat && p.lng).map((p) => [p.lat, p.lng]);
      const pins = puntos.filter((p) => p.tipo !== 'ping').map((p) => ({
        lat: p.lat, lng: p.lng,
        color: p.tipo === 'apertura' ? '#F59E0B' :
               p.tipo === 'marca_ronda' ? '#0D2B5E' : '#27AE60',
      }));
      const png = await capturarMapaComoPng({ puntos: [], rastro, pins });

      const { jsPDF } = window.jspdf;
      const doc = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });
      const t0 = puntos[0];
      dibujarCabeceraPdf(doc, 'Recorrido GPS del turno',
        `${fmtFechaHora(t0.cuando)} · ${puntos.length} puntos registrados`);
      if (png) {
        doc.addImage(png, 'JPEG', 14, 44, 180, 170);
      } else {
        doc.setTextColor(...COLOR_ROJO_RGB);
        doc.text('(No se pudo generar el mapa)', 14, 60);
      }
      doc.autoTable({
        startY: 220,
        head: [['Hora', 'Tipo', 'Qué pasó']],
        body: puntos.slice(0, 40).map((p) => [
          fmtHora(p.cuando),
          p.tipo === 'apertura' ? 'Apertura' :
          p.tipo === 'marca_ronda' ? 'Ronda' :
          p.tipo === 'acceso' ? 'Acceso' : 'GPS',
          p.descripcion,
        ]),
        styles: { font: 'helvetica', fontSize: 8, cellPadding: 1.8 },
        headStyles: { fillColor: COLOR_GRAFITO_RGB, textColor: 255 },
      });
      dibujarPiePdf(doc);
      doc.save(`recorrido-${turnoId.slice(0, 8)}.pdf`);
      avisoEnPanel('PDF listo.', 'ok');
    } catch (e) {
      console.error(e);
      avisoEnPanel(e.message || 'No se pudo generar.', 'err');
    }
  },
};

// --------------------------------------------------------------------------
// INFORME 4: NOVEDADES CON FOTOS
// --------------------------------------------------------------------------

const InformeNovedades = {
  nombre: 'Novedades con fotos',

  async render() {
    const cont = document.getElementById('informePanelContenido');
    cont.innerHTML = `
      <h2 style="margin-top:0">Novedades con fotos</h2>
      <p style="color:var(--texto-suave);font-size:13px;margin-top:0">
        Listado filtrable de incidentes del período con fotos y descripciones.
      </p>
      <div class="informe-filtros">
        <label>Estado
          <select id="nvEstado">
            <option value="">Todas</option>
            <option value="abierto" selected>Abiertas</option>
            <option value="resuelto">Resueltas</option>
          </select>
        </label>
      </div>
      <div class="informe-botones">
        <button class="btn-primario" id="nvGenerar">Generar PDF</button>
      </div>
    `;
    document.getElementById('nvGenerar').addEventListener('click', () =>
      InformeNovedades.generar());
  },

  async generar() {
    const boton = document.getElementById('nvGenerar');
    boton.disabled = true; boton.textContent = 'Generando…';
    try {
      const estadoFiltro = document.getElementById('nvEstado').value || null;
      const condoId = estado.condominioFiltro || null;
      const novedades = await api.novedades({
        estado: estadoFiltro, condominioId: condoId,
      });
      if (novedades.length === 0) throw new Error('No hay novedades con esos filtros.');

      const { jsPDF } = window.jspdf;
      const doc = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });
      dibujarCabeceraPdf(doc, 'Novedades',
        `${nombreCondominioActual()} · ${novedades.length} ${novedades.length === 1 ? 'novedad' : 'novedades'}` +
        (estadoFiltro ? ` · ${estadoFiltro}` : ''));

      let y = 44;
      const maxY = 280;
      for (const n of novedades) {
        if (y > maxY - 40) { doc.addPage(); y = 20; }
        doc.setFillColor(248, 249, 250);
        doc.rect(14, y, 182, 7, 'F');
        doc.setTextColor(26, 26, 46);
        doc.setFontSize(10); doc.setFont('helvetica', 'bold');
        doc.text(n.titulo || '(sin título)', 16, y + 5);
        doc.setFontSize(8); doc.setFont('helvetica', 'normal');
        doc.setTextColor(...COLOR_GRIS_RGB);
        doc.text(`${n.tipo || ''} · ${n.gravedad || ''} · ${n.estado || ''}`,
          196, y + 5, { align: 'right' });
        y += 10;
        doc.setTextColor(26, 26, 46);
        doc.setFontSize(9);
        doc.text(`${fmtFechaHora(n.ocurrido_en)}  ·  ${n.condominio_nombre || ''}  ·  ${n.reportado_por_nombre || 'Guardia'}`,
          16, y);
        y += 5;
        if (n.descripcion) {
          const lineas = doc.splitTextToSize(n.descripcion, 180);
          doc.setFontSize(9);
          doc.text(lineas, 16, y);
          y += lineas.length * 4.5 + 2;
        }

        // Fotos: la columna i.fotos viene como jsonb (array de paths).
        // El bucket se llama 'paquetes' por historia — ahí van todas las
        // fotos del guardia (paquetes y novedades juntos).
        const fotos = Array.isArray(n.fotos) ? n.fotos : [];
        for (const path of fotos.slice(0, 2)) {
          try {
            const url = await api.urlFoto('paquetes', path);
            if (!url) continue;
            const img = await cargarImagen(url);
            if (!img) continue;
            if (y + 50 > maxY) { doc.addPage(); y = 20; }
            doc.addImage(img, 'JPEG', 16, y, 70, 50);
            y += 54;
          } catch { /* saltamos la foto si falla */ }
        }
        y += 4;
        doc.setDrawColor(230, 232, 236);
        doc.line(14, y, 196, y);
        y += 6;
      }
      dibujarPiePdf(doc);
      doc.save(`novedades-${hoyIso()}.pdf`);
      avisoEnPanel('Informe listo.', 'ok');
    } catch (e) {
      console.error(e);
      avisoEnPanel(e.message || 'No se pudo generar.', 'err');
    } finally {
      boton.disabled = false; boton.textContent = 'Generar PDF';
    }
  },
};

async function cargarImagen(url) {
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = url;
  });
}

// --------------------------------------------------------------------------
// INFORME 5: MOVIMIENTOS DE ACCESO
// --------------------------------------------------------------------------

const InformeMovimientos = {
  nombre: 'Movimientos de acceso',

  async render() {
    const cont = document.getElementById('informePanelContenido');
    cont.innerHTML = `
      <h2 style="margin-top:0">Movimientos de acceso del período</h2>
      <p style="color:var(--texto-suave);font-size:13px;margin-top:0">
        Entradas y salidas de personas y vehículos registradas por los guardias.
      </p>
      <div class="informe-filtros">
        <label>Desde
          <input type="date" id="mvDesde" value="${haceDiasIso(7)}">
        </label>
        <label>Hasta
          <input type="date" id="mvHasta" value="${hoyIso()}">
        </label>
      </div>
      <div class="informe-botones">
        <button class="btn-primario" id="mvGenerar">Generar PDF</button>
      </div>
    `;
    document.getElementById('mvGenerar').addEventListener('click', () =>
      InformeMovimientos.generar());
  },

  async generar() {
    const boton = document.getElementById('mvGenerar');
    boton.disabled = true; boton.textContent = 'Generando…';
    try {
      const desdeStr = document.getElementById('mvDesde').value;
      const hastaStr = document.getElementById('mvHasta').value;
      const { desde, hasta } = rangoAConsulta(desdeStr, hastaStr);
      const filas = await api.ingresos({
        desde, hasta, condominioId: estado.condominioFiltro,
      });
      if (filas.length === 0) throw new Error('No hay movimientos en ese período.');

      const { jsPDF } = window.jspdf;
      const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });
      dibujarCabeceraPdf(doc, 'Movimientos de acceso',
        `${nombreCondominioActual()} · Del ${fmtFecha(desde)} al ${fmtFecha(hasta)} · ${filas.length} registros`);
      doc.autoTable({
        startY: 44,
        head: [['Fecha', 'Instalación', 'Persona', 'Tipo', 'Sentido', 'Unidad', 'Autorizó', 'Guardia']],
        body: filas.map((f) => [
          fmtFechaHora(f.ocurrido_en), f.condominio_nombre || '',
          f.nombre || '', f.tipo_acceso || '', f.sentido || '',
          f.unidad || '', f.autorizado_por || '', f.guardia_nombre || '',
        ]),
        styles: { font: 'helvetica', fontSize: 8, cellPadding: 1.8 },
        headStyles: { fillColor: COLOR_GRAFITO_RGB, textColor: 255 },
      });
      dibujarPiePdf(doc);
      doc.save(`movimientos-${desdeStr}-${hastaStr}.pdf`);
      avisoEnPanel('Informe listo.', 'ok');
    } catch (e) {
      console.error(e);
      avisoEnPanel(e.message || 'No se pudo generar.', 'err');
    } finally {
      boton.disabled = false; boton.textContent = 'Generar PDF';
    }
  },
};

// --------------------------------------------------------------------------
// INFORME 6: PAQUETES ATRASADOS
// --------------------------------------------------------------------------

const InformePaquetesAtrasados = {
  nombre: 'Paquetes atrasados',

  async render() {
    const cont = document.getElementById('informePanelContenido');
    cont.innerHTML = `
      <h2 style="margin-top:0">Paquetes atrasados en portería</h2>
      <p style="color:var(--texto-suave);font-size:13px;margin-top:0">
        Paquetes recibidos hace más de N días que no fueron retirados.
        Útil para presionar al residente o devolver al remitente.
      </p>
      <div class="informe-filtros">
        <label>Más de
          <input type="number" id="paDias" value="7" min="1" max="60"> días
        </label>
      </div>
      <div class="informe-botones">
        <button class="btn-primario" id="paGenerar">Generar PDF</button>
      </div>
    `;
    document.getElementById('paGenerar').addEventListener('click', () =>
      InformePaquetesAtrasados.generar());
  },

  async generar() {
    const boton = document.getElementById('paGenerar');
    boton.disabled = true; boton.textContent = 'Generando…';
    try {
      const dias = parseInt(document.getElementById('paDias').value) || 7;
      const filas = await api.paquetesAtrasados({
        diasUmbral: dias, condominioId: estado.condominioFiltro,
      });
      if (filas.length === 0) {
        throw new Error(`No hay paquetes atrasados más de ${dias} días.`);
      }
      const { jsPDF } = window.jspdf;
      const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });
      dibujarCabeceraPdf(doc, 'Paquetes atrasados',
        `${nombreCondominioActual()} · Sin retirar hace más de ${dias} días · ${filas.length} paquetes`);
      doc.autoTable({
        startY: 44,
        head: [['Recibido', 'Días', 'Instalación', 'Destinatario', 'Unidad', 'Courier', 'Seguimiento']],
        body: filas.map((f) => [
          fmtFecha(f.recibido_en), f.dias_en_porteria,
          f.condominio_nombre || '', f.destinatario || '',
          f.unidad || '', f.empresa_courier || '', f.numero_seguimiento || '',
        ]),
        styles: { font: 'helvetica', fontSize: 9, cellPadding: 2 },
        headStyles: { fillColor: COLOR_GRAFITO_RGB, textColor: 255 },
      });
      dibujarPiePdf(doc);
      doc.save(`paquetes-atrasados-${hoyIso()}.pdf`);
      avisoEnPanel('Informe listo.', 'ok');
    } catch (e) {
      console.error(e);
      avisoEnPanel(e.message || 'No se pudo generar.', 'err');
    } finally {
      boton.disabled = false; boton.textContent = 'Generar PDF';
    }
  },
};

// --------------------------------------------------------------------------
// INFORME 7: COMPARATIVA ENTRE INSTALACIONES
// --------------------------------------------------------------------------

const InformeComparativa = {
  nombre: 'Comparativa entre instalaciones',

  async render() {
    const cont = document.getElementById('informePanelContenido');
    cont.innerHTML = `
      <h2 style="margin-top:0">Comparativa entre instalaciones</h2>
      <p style="color:var(--texto-suave);font-size:13px;margin-top:0">
        Para el período elegido, ordena las instalaciones por ranking (más
        rondas, más novedades, peor completitud) y señala las que necesitan
        atención.
      </p>
      <div class="informe-filtros">
        <label>Desde
          <input type="date" id="cmpDesde" value="${primeroDelMes()}">
        </label>
        <label>Hasta
          <input type="date" id="cmpHasta" value="${hoyIso()}">
        </label>
      </div>
      <div class="informe-botones">
        <button class="btn-primario" id="cmpGenerar">Generar PDF</button>
      </div>
    `;
    document.getElementById('cmpGenerar').addEventListener('click', () =>
      InformeComparativa.generar());
  },

  async generar() {
    const boton = document.getElementById('cmpGenerar');
    boton.disabled = true; boton.textContent = 'Generando…';
    try {
      const desdeStr = document.getElementById('cmpDesde').value;
      const hastaStr = document.getElementById('cmpHasta').value;
      const { desde, hasta } = rangoAConsulta(desdeStr, hastaStr);
      const filas = await api.resumenDelPeriodo({ desde, hasta });
      if (filas.length === 0) throw new Error('No hay datos en ese período.');

      // Score simple: rondas * 2 - marcas_lejanas - novedades_criticas * 3
      const rankeados = filas.map((f) => ({
        ...f,
        score: (f.rondas * 2) - (f.marcas_lejanas || 0) -
               (f.novedades_criticas || 0) * 3,
        completitud: f.rondas > 0 ? Math.round((f.rondas_completas / f.rondas) * 100) : 0,
      })).sort((a, b) => b.score - a.score);

      const { jsPDF } = window.jspdf;
      const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });
      dibujarCabeceraPdf(doc, 'Comparativa entre instalaciones',
        `Del ${fmtFecha(desde)} al ${fmtFecha(hasta)} · ordenadas por índice de actividad`);

      doc.autoTable({
        startY: 44,
        head: [['#', 'Instalación', 'Rondas', 'Compl. %', 'Marcas lejanas',
                'Novedades', 'Críticas', 'Horas turno', 'Alerta']],
        body: rankeados.map((f, i) => [
          i + 1, f.condominio_nombre, f.rondas, `${f.completitud}%`,
          f.marcas_lejanas, f.novedades, f.novedades_criticas,
          Number(f.horas_turno).toFixed(0),
          f.novedades_criticas > 0 ? '⚠ crítica' :
          f.completitud < 70 ? '⚠ rondas incompletas' :
          f.marcas_lejanas > 10 ? '⚠ marcas lejanas' : '✓',
        ]),
        styles: { font: 'helvetica', fontSize: 9, cellPadding: 2 },
        headStyles: { fillColor: COLOR_GRAFITO_RGB, textColor: 255 },
        didParseCell: (data) => {
          if (data.section === 'body' && data.column.index === 8) {
            const texto = String(data.cell.raw || '');
            if (texto.startsWith('⚠')) {
              data.cell.styles.textColor = COLOR_ROJO_RGB;
              data.cell.styles.fontStyle = 'bold';
            } else if (texto === '✓') {
              data.cell.styles.textColor = COLOR_VERDE_RGB;
            }
          }
        },
      });

      // Mini texto final de recomendación
      const peor = rankeados[rankeados.length - 1];
      const mejor = rankeados[0];
      const yFin = doc.lastAutoTable.finalY || 100;
      doc.setFontSize(10); doc.setFont('helvetica', 'bold');
      doc.setTextColor(26, 26, 46);
      doc.text('Observaciones', 14, yFin + 10);
      doc.setFont('helvetica', 'normal'); doc.setFontSize(9);
      doc.setTextColor(...COLOR_GRIS_RGB);
      const lineas = [
        `Mejor desempeño: ${mejor.condominio_nombre} con ${mejor.rondas} rondas y ${mejor.completitud}% de completitud.`,
        `Necesita atención: ${peor.condominio_nombre} con ${peor.rondas} rondas, ${peor.completitud}% completas y ${peor.novedades_criticas} novedades críticas.`,
      ];
      doc.text(lineas, 14, yFin + 16);

      dibujarPiePdf(doc);
      doc.save(`comparativa-${desdeStr}-${hastaStr}.pdf`);
      avisoEnPanel('Informe listo.', 'ok');
    } catch (e) {
      console.error(e);
      avisoEnPanel(e.message || 'No se pudo generar.', 'err');
    } finally {
      boton.disabled = false; boton.textContent = 'Generar PDF';
    }
  },
};

// --------------------------------------------------------------------------
// CATÁLOGO + ENRUTADOR
// --------------------------------------------------------------------------

const Informes = {
  'rondas':              InformeRondas,
  'resumen-mensual':     InformeResumenMensual,
  'recorrido-turno':     InformeRecorridoTurno,
  'novedades-pdf':       InformeNovedades,
  'movimientos':         InformeMovimientos,
  'paquetes-atrasados':  InformePaquetesAtrasados,
  'comparativa':         InformeComparativa,
};

function iniciarInformes() {
  const grid = document.getElementById('informesGrid');
  const panel = document.getElementById('informePanel');
  const volver = document.getElementById('informeVolver');
  if (!grid || !panel || !volver) return;

  grid.querySelectorAll('.informe-card').forEach((card) => {
    card.addEventListener('click', () => {
      const clave = card.dataset.informe;
      const informe = Informes[clave];
      if (!informe) return;
      grid.classList.add('oculto');
      panel.classList.remove('oculto');
      Promise.resolve(informe.render()).catch((e) => {
        avisoEnPanel(e.message || 'No se pudo abrir el informe.', 'err');
      });
    });
  });
  volver.addEventListener('click', () => {
    panel.classList.add('oculto');
    grid.classList.remove('oculto');
    document.getElementById('informePanelContenido').innerHTML = '';
  });
}
