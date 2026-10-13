// ============================================================================
// Panel — lógica de la SPA (tabs + render)
// ============================================================================
// No usamos framework. Cada vista tiene su propia función de render que
// escribe HTML directo al DOM. Las vistas se cargan on-demand (al cambiar
// de pestaña) para no sumar latencia inicial.
// ============================================================================

const estado = {
  perfil: null,
  instalaciones: [],
  condominioFiltro: null, // null = todas
  mapa: null,
  mapaMarkers: [],
  // Últimas filas cargadas por vista: las guardamos para que los botones
  // "Descargar CSV" / "Descargar PDF" exporten exactamente lo que el usuario
  // está viendo sin re-pegarle al servidor.
  ultimasFilas: {
    resumen: [],
    ingresos: [],
    novedades: [],
    paquetes: [],
  },
  // Estado seleccionado en la pestaña Paquetes (afecta render + CSV).
  paquetesEstadoActual: 'en_porteria',
};

// ============================================================================
// Arranque
// ============================================================================

(async function arrancar() {
  // Si no hay sesión, al login.
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) {
    window.location.replace('index.html');
    return;
  }

  // Perfil + instalaciones.
  try {
    estado.perfil = await api.perfil();
    estado.instalaciones = await api.misInstalaciones();
  } catch (e) {
    alert('No pudimos cargar tu perfil: ' + (e.message || e));
    await api.salir();
    return;
  }

  document.getElementById('rolUsuario').textContent =
    `${estado.perfil?.nombre_completo || 'Usuario'} · ${rotuloRol(estado.perfil?.rol)}`;

  llenarSelectorInstalacion();

  // Fechas por defecto del filtro de ingresos (últimos 7 días).
  const hoy = new Date();
  const hace7 = new Date(hoy.getTime() - 7 * 24 * 60 * 60 * 1000);
  document.getElementById('ingresosDesde').value = aYMD(hace7);
  document.getElementById('ingresosHasta').value = aYMD(hoy);

  // Listeners generales.
  document.getElementById('btnSalir').addEventListener('click', api.salir);
  document.getElementById('btnActualizar').addEventListener('click', () => {
    renderVistaActiva();
  });
  document.getElementById('selectorInstalacion')
    .addEventListener('change', (ev) => {
      estado.condominioFiltro = ev.target.value || null;
      renderVistaActiva();
    });

  document.querySelectorAll('.pestana').forEach((btn) => {
    btn.addEventListener('click', () => cambiarTab(btn.dataset.tab));
  });

  document.getElementById('btnFiltrarIngresos').addEventListener('click',
    renderIngresos);
  document.getElementById('btnFiltrarNovedades').addEventListener('click',
    renderNovedades);
  document.getElementById('btnFiltrarPaquetes').addEventListener('click',
    renderPaquetes);
  document.getElementById('cerrarModal').addEventListener('click', cerrarModal);

  // Descargas CSV.
  document.getElementById('btnCsvIngresos').addEventListener('click',
    descargarCsvIngresos);
  document.getElementById('btnCsvNovedades').addEventListener('click',
    descargarCsvNovedades);
  document.getElementById('btnCsvPaquetes').addEventListener('click',
    descargarCsvPaquetes);

  // Descargas PDF.
  document.getElementById('btnPdfResumen').addEventListener('click',
    descargarPdfResumenHandler);
  document.getElementById('btnPdfIngresos').addEventListener('click',
    descargarPdfIngresos);
  document.getElementById('btnPdfNovedades').addEventListener('click',
    descargarPdfNovedades);
  document.getElementById('btnPdfPaquetes').addEventListener('click',
    descargarPdfPaquetes);

  // Vista inicial.
  await renderResumen();
})();

// ============================================================================
// Barra superior + selector de instalación
// ============================================================================

function llenarSelectorInstalacion() {
  const sel = document.getElementById('selectorInstalacion');
  sel.innerHTML = '';
  const opcionTodas = document.createElement('option');
  opcionTodas.value = '';
  opcionTodas.textContent = estado.instalaciones.length > 1
    ? 'Todas mis instalaciones'
    : (estado.instalaciones[0]?.nombre || 'Sin instalación');
  sel.appendChild(opcionTodas);

  if (estado.instalaciones.length > 1) {
    for (const i of estado.instalaciones) {
      const op = document.createElement('option');
      op.value = i.id;
      op.textContent = i.nombre;
      sel.appendChild(op);
    }
  }
}

function rotuloRol(rol) {
  if (rol === 'administrador') return 'Administrador';
  if (rol === 'mandante') return 'Mandante';
  return rol || '—';
}

// ============================================================================
// Switch de pestañas
// ============================================================================

function cambiarTab(tabId) {
  document.querySelectorAll('.pestana').forEach((b) => {
    b.classList.toggle('activa', b.dataset.tab === tabId);
  });
  document.querySelectorAll('.vista').forEach((v) => {
    v.classList.toggle('oculta', v.dataset.vista !== tabId);
  });
  renderVistaActiva();
}

function tabActivo() {
  return document.querySelector('.pestana.activa')?.dataset.tab || 'resumen';
}

function renderVistaActiva() {
  const t = tabActivo();
  if (t === 'resumen') return renderResumen();
  if (t === 'ingresos') return renderIngresos();
  if (t === 'novedades') return renderNovedades();
  if (t === 'paquetes') return renderPaquetes();
  if (t === 'mapa') return renderMapa();
}

// ============================================================================
// Vista RESUMEN
// ============================================================================

async function renderResumen() {
  const cont = document.getElementById('resumenCards');
  cont.innerHTML = '<div class="cargando">Cargando resumen…</div>';
  try {
    const filas = await api.resumen();
    const visibles = estado.condominioFiltro
      ? filas.filter((f) => f.condominio_id === estado.condominioFiltro)
      : filas;
    estado.ultimasFilas.resumen = visibles;
    if (visibles.length === 0) {
      cont.innerHTML = '<div class="vacio">No hay instalaciones para mostrar.</div>';
      return;
    }
    cont.innerHTML = visibles.map((f) => `
      <div class="card ${f.novedades_criticas > 0 ? 'card-critica' : ''}">
        <div class="card-head">
          <h3>${escapar(f.condominio_nombre)}</h3>
          <span class="chip chip-${f.condominio_tipo}">${rotuloTipo(f.condominio_tipo)}</span>
        </div>
        <div class="kpis">
          <div class="kpi">
            <div class="kpi-num ${f.guardias_de_turno > 0 ? 'ok' : 'warn'}">
              ${f.guardias_de_turno}
            </div>
            <div class="kpi-lbl">Guardias de turno</div>
          </div>
          <div class="kpi">
            <div class="kpi-num ${f.novedades_abiertas > 0 ? 'warn' : ''}">
              ${f.novedades_abiertas}
            </div>
            <div class="kpi-lbl">Novedades abiertas</div>
          </div>
          <div class="kpi">
            <div class="kpi-num ${f.novedades_criticas > 0 ? 'danger' : ''}">
              ${f.novedades_criticas}
            </div>
            <div class="kpi-lbl">Críticas</div>
          </div>
          <div class="kpi">
            <div class="kpi-num ${f.paquetes_en_porteria > 0 ? 'warn' : ''}">
              ${f.paquetes_en_porteria}
            </div>
            <div class="kpi-lbl">Paquetes en portería</div>
          </div>
          <div class="kpi">
            <div class="kpi-num">${f.accesos_hoy}</div>
            <div class="kpi-lbl">Accesos hoy</div>
          </div>
        </div>
      </div>
    `).join('');
  } catch (e) {
    cont.innerHTML = `<div class="vacio error">Error: ${escapar(e.message || String(e))}</div>`;
  }
}

// ============================================================================
// Vista INGRESOS
// ============================================================================

async function renderIngresos() {
  const tbody = document.getElementById('ingresosTbody');
  tbody.innerHTML = '<tr><td colspan="8" class="cargando">Cargando…</td></tr>';
  const desdeInput = document.getElementById('ingresosDesde').value;
  const hastaInput = document.getElementById('ingresosHasta').value;
  try {
    const filas = await api.ingresos({
      desde: desdeInput ? new Date(desdeInput + 'T00:00:00').toISOString() : undefined,
      hasta: hastaInput ? new Date(hastaInput + 'T23:59:59').toISOString() : undefined,
      condominioId: estado.condominioFiltro,
    });
    estado.ultimasFilas.ingresos = filas;
    if (filas.length === 0) {
      tbody.innerHTML = '<tr><td colspan="8" class="vacio">No hay ingresos en el período.</td></tr>';
      return;
    }
    tbody.innerHTML = filas.map((f) => `
      <tr class="${f.estado === 'denegado' ? 'fila-denegada' : ''}">
        <td>${formatearFecha(f.ocurrido_en)}</td>
        <td>${escapar(f.condominio_nombre)}</td>
        <td>${escapar(f.nombre || '—')}</td>
        <td>${rotuloTipoAcceso(f.tipo_acceso)}</td>
        <td class="${f.sentido === 'entrada' ? 'entrada' : 'salida'}">
          ${f.sentido === 'entrada' ? '→ Entrada' : '← Salida'}
          ${f.estado === 'denegado' ? '<span class="badge-rojo">DENEGADO</span>' : ''}
        </td>
        <td>${escapar(f.unidad || '—')}</td>
        <td>${escapar(f.autorizado_por || '—')}</td>
        <td>${escapar(f.guardia_nombre || '—')}</td>
      </tr>
    `).join('');
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="8" class="vacio error">Error: ${escapar(e.message || String(e))}</td></tr>`;
  }
}

// ============================================================================
// Vista NOVEDADES
// ============================================================================

async function renderNovedades() {
  const cont = document.getElementById('novedadesLista');
  cont.innerHTML = '<div class="cargando">Cargando…</div>';
  const estadoFiltro = document.getElementById('novedadesEstado').value;
  try {
    const filas = await api.novedades({
      estado: estadoFiltro || null,
      condominioId: estado.condominioFiltro,
    });
    estado.ultimasFilas.novedades = filas;
    if (filas.length === 0) {
      cont.innerHTML = '<div class="vacio">Sin novedades en este filtro.</div>';
      return;
    }
    cont.innerHTML = filas.map((f, i) => `
      <div class="card novedad gravedad-${f.gravedad}" data-i="${i}">
        <div class="card-head">
          <h3>${escapar(f.titulo)}</h3>
          <span class="chip chip-${f.gravedad}">${rotuloGravedad(f.gravedad)}</span>
        </div>
        <div class="meta">
          <span>${formatearFecha(f.ocurrido_en)}</span>
          <span>${escapar(f.condominio_nombre)}</span>
          <span>${escapar(f.reportado_por_nombre || 'Sistema')}</span>
          <span class="chip-estado chip-estado-${f.estado}">${f.estado}</span>
        </div>
        ${f.descripcion ? `<p>${escapar(f.descripcion)}</p>` : ''}
        ${(f.fotos && f.fotos.length) ? `<div class="mini-fotos" data-fotos='${encodeURIComponent(JSON.stringify(f.fotos))}'>📷 ${f.fotos.length} foto${f.fotos.length > 1 ? 's' : ''} (click para ver)</div>` : ''}
      </div>
    `).join('');

    cont.querySelectorAll('.mini-fotos').forEach((el) => {
      el.addEventListener('click', async () => {
        const fotos = JSON.parse(decodeURIComponent(el.dataset.fotos));
        await mostrarFotosEnModal(fotos);
      });
    });
  } catch (e) {
    cont.innerHTML = `<div class="vacio error">Error: ${escapar(e.message || String(e))}</div>`;
  }
}

async function mostrarFotosEnModal(paths) {
  const mod = document.getElementById('modalContenido');
  mod.innerHTML = '<div class="cargando">Cargando fotos…</div>';
  abrirModal();
  const urls = await Promise.all(paths.map((p) => api.urlFoto('paquetes', p)));
  mod.innerHTML = urls
    .filter(Boolean)
    .map((u) => `<img src="${u}" alt="Foto de novedad" class="foto-modal">`)
    .join('') || '<div class="vacio">No pudimos cargar las fotos.</div>';
}

// ============================================================================
// Vista PAQUETES
// ============================================================================

async function renderPaquetes() {
  const cont = document.getElementById('paquetesLista');
  cont.innerHTML = '<div class="cargando">Cargando…</div>';
  const estadoSel = document.getElementById('paquetesEstado').value;
  // "" = todos; 'en_porteria' | 'entregado' = filtro específico
  estado.paquetesEstadoActual = estadoSel || null;
  try {
    const filas = await api.paquetes({
      condominioId: estado.condominioFiltro,
      estado: estadoSel === '' ? null : estadoSel,
    });
    estado.ultimasFilas.paquetes = filas;
    if (filas.length === 0) {
      const msg = estadoSel === 'entregado'
        ? 'Sin paquetes entregados en el histórico.'
        : estadoSel === 'en_porteria'
          ? 'No hay paquetes pendientes de retiro.'
          : 'Sin paquetes para mostrar.';
      cont.innerHTML = `<div class="vacio">${msg}</div>`;
      return;
    }
    cont.innerHTML = filas.map((f) => renderCardPaquete(f)).join('');

    // Click en firma/foto abre modal con la imagen a tamaño grande.
    cont.querySelectorAll('.mini-firma, .mini-foto-paquete').forEach((el) => {
      el.addEventListener('click', async () => {
        const path = el.dataset.path;
        const bucket = el.dataset.bucket;
        const titulo = el.dataset.titulo;
        await mostrarImagenEnModal(bucket, path, titulo);
      });
    });
  } catch (e) {
    cont.innerHTML = `<div class="vacio error">Error: ${escapar(e.message || String(e))}</div>`;
  }
}

/** Renderiza una tarjeta de paquete, con columnas distintas según su estado. */
function renderCardPaquete(f) {
  const entregado = f.estado === 'entregado';
  const chipEstado = entregado
    ? '<span class="chip chip-ok">ENTREGADO</span>'
    : (f.dias_en_porteria > 7
        ? `<span class="chip chip-critica">${f.dias_en_porteria} día${f.dias_en_porteria === 1 ? '' : 's'} atrasado</span>`
        : `<span class="chip chip-info">${f.dias_en_porteria} día${f.dias_en_porteria === 1 ? '' : 's'}</span>`);

  const metaEntrega = entregado ? `
    <div class="meta meta-entrega">
      <span><strong>Retiró:</strong> ${escapar(f.retirado_por || f.destinatario || '—')}</span>
      <span><strong>Entregado:</strong> ${formatearFecha(f.entregado_en)}</span>
      <span><strong>Por:</strong> ${escapar(f.guardia_entrega || '—')}</span>
      <span>${f.identidad_validada ? '✓ Identidad validada' : '⚠ Sin validar'}</span>
    </div>
    <div class="mini-pruebas">
      ${f.firma_url ? `<button class="mini-firma" data-bucket="firmas" data-path="${escapar(f.firma_url)}" data-titulo="Firma del residente">✍ Ver firma</button>` : '<span class="sin-prueba">Sin firma</span>'}
      ${(f.foto_entrega_url || f.foto_url) ? `<button class="mini-foto-paquete" data-bucket="paquetes" data-path="${escapar(f.foto_entrega_url || f.foto_url)}" data-titulo="Foto del paquete">📷 Ver foto del paquete</button>` : ''}
    </div>
  ` : '';

  return `
    <div class="card paquete ${!entregado && f.dias_en_porteria > 7 ? 'card-atrasado' : ''} ${entregado ? 'card-entregado' : ''}">
      <div class="card-head">
        <h3>${escapar(f.destinatario || 'Sin destinatario')}</h3>
        ${chipEstado}
      </div>
      <div class="meta">
        <span>Unidad ${escapar(f.unidad || '—')}</span>
        <span>${escapar(f.condominio_nombre)}</span>
        <span>Recibido ${formatearFecha(f.recibido_en)}</span>
        <span>por ${escapar(f.guardia_receptor || '—')}</span>
      </div>
      ${f.descripcion ? `<p>${escapar(f.descripcion)}</p>` : ''}
      ${metaEntrega}
    </div>
  `;
}

/** Muestra una sola imagen (firma o foto) a tamaño grande en el modal. */
async function mostrarImagenEnModal(bucket, path, titulo) {
  const mod = document.getElementById('modalContenido');
  mod.innerHTML = '<div class="cargando">Cargando…</div>';
  abrirModal();
  const url = await api.urlFoto(bucket, path);
  if (!url) {
    mod.innerHTML = '<div class="vacio">No pudimos cargar la imagen.</div>';
    return;
  }
  mod.innerHTML = `
    <h3 class="titulo-modal">${escapar(titulo || '')}</h3>
    <img src="${url}" alt="${escapar(titulo || '')}" class="foto-modal">
  `;
}

// ============================================================================
// Vista MAPA (guardias en vivo)
// ============================================================================

async function renderMapa() {
  const lista = document.getElementById('mapaLista');
  lista.innerHTML = '<div class="cargando">Cargando guardias de turno…</div>';
  try {
    const guardias = await api.guardiasDeTurno({
      condominioId: estado.condominioFiltro,
    });

    // Inicializar mapa si todavía no.
    if (!estado.mapa) {
      estado.mapa = L.map('mapa').setView([-33.4489, -70.6693], 12);
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap',
        maxZoom: 19,
      }).addTo(estado.mapa);
    }

    // Limpiar markers anteriores.
    estado.mapaMarkers.forEach((m) => estado.mapa.removeLayer(m));
    estado.mapaMarkers = [];

    const puntos = [];
    for (const g of guardias) {
      if (g.ultima_lat == null || g.ultima_lng == null) continue;
      const latlng = [parseFloat(g.ultima_lat), parseFloat(g.ultima_lng)];
      const icono = L.divIcon({
        className: 'marker-guardia',
        html: '<div class="pulso"></div><div class="pin"></div>',
        iconSize: [24, 24],
        iconAnchor: [12, 12],
      });
      const m = L.marker(latlng, { icon: icono }).addTo(estado.mapa);
      m.bindPopup(`
        <strong>${escapar(g.guardia_nombre)}</strong><br>
        ${escapar(g.condominio_nombre)}<br>
        ${g.punto_acceso ? escapar(g.punto_acceso) + '<br>' : ''}
        Última señal: ${g.ultima_ubicacion_en ? haceCuanto(g.ultima_ubicacion_en) : 'sin señal'}
      `);
      estado.mapaMarkers.push(m);
      puntos.push(latlng);
    }

    if (puntos.length > 0) {
      estado.mapa.fitBounds(puntos, { padding: [40, 40], maxZoom: 15 });
    }
    // Forzar un resize por si el div estaba oculto cuando se creó.
    setTimeout(() => estado.mapa.invalidateSize(), 50);

    if (guardias.length === 0) {
      lista.innerHTML = '<div class="vacio">No hay guardias con turno abierto en este momento.</div>';
      return;
    }
    lista.innerHTML = guardias.map((g) => `
      <div class="card guardia-vivo">
        <div class="card-head">
          <h3>${escapar(g.guardia_nombre)}</h3>
          <span class="chip chip-${g.ultima_ubicacion_en ? 'ok' : 'warn'}">
            ${g.ultima_ubicacion_en ? haceCuanto(g.ultima_ubicacion_en) : 'sin señal'}
          </span>
        </div>
        <div class="meta">
          <span>${escapar(g.condominio_nombre)}</span>
          ${g.punto_acceso ? `<span>${escapar(g.punto_acceso)}</span>` : ''}
          <span>Turno abierto ${formatearFecha(g.inicio)}</span>
          ${g.guardia_telefono ? `<a href="tel:${g.guardia_telefono}" class="link-telefono">📞 ${g.guardia_telefono}</a>` : ''}
        </div>
      </div>
    `).join('');
  } catch (e) {
    lista.innerHTML = `<div class="vacio error">Error: ${escapar(e.message || String(e))}</div>`;
  }
}

// ============================================================================
// Modal
// ============================================================================

function abrirModal() {
  document.getElementById('modalDetalle').classList.remove('oculto');
}
function cerrarModal() {
  document.getElementById('modalDetalle').classList.add('oculto');
}

// ============================================================================
// Helpers
// ============================================================================

function escapar(txt) {
  if (txt == null) return '';
  return String(txt)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function formatearFecha(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  const hoy = new Date();
  const ayer = new Date(hoy.getTime() - 24 * 60 * 60 * 1000);
  const esHoy = d.toDateString() === hoy.toDateString();
  const esAyer = d.toDateString() === ayer.toDateString();
  const hora = d.toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' });
  if (esHoy) return `Hoy ${hora}`;
  if (esAyer) return `Ayer ${hora}`;
  return d.toLocaleDateString('es-CL', { day: '2-digit', month: 'short' }) + ' ' + hora;
}

function haceCuanto(iso) {
  if (!iso) return 'sin señal';
  const ahora = Date.now();
  const t = new Date(iso).getTime();
  const dif = Math.round((ahora - t) / 1000); // segundos
  if (dif < 60) return 'hace segundos';
  if (dif < 3600) return `hace ${Math.floor(dif / 60)} min`;
  if (dif < 86400) return `hace ${Math.floor(dif / 3600)} h`;
  return `hace ${Math.floor(dif / 86400)} d`;
}

function aYMD(d) {
  return d.toISOString().substring(0, 10);
}

function rotuloTipo(tipo) {
  if (tipo === 'condominio') return 'Condominio';
  if (tipo === 'empresa') return 'Empresa';
  return 'Otro';
}

function rotuloTipoAcceso(t) {
  if (t === 'peatonal') return '🚶 Peatonal';
  if (t === 'vehicular') return '🚗 Vehicular';
  return t || '—';
}

function rotuloGravedad(g) {
  if (g === 'critica') return 'Crítica';
  if (g === 'alta') return 'Alta';
  if (g === 'media') return 'Media';
  if (g === 'baja') return 'Baja';
  return g || '—';
}

// ============================================================================
// Descarga CSV — una función por vista
// ============================================================================
// Cada botón exporta EXACTAMENTE las filas que el usuario está viendo
// (incluyendo el filtro aplicado). El nombre del archivo incluye la fecha
// y la instalación para que no se pisen entre descargas.

function nombreBaseArchivo(seccion) {
  const inst = estado.condominioFiltro
    ? (estado.instalaciones.find((i) => i.id === estado.condominioFiltro)
        ?.nombre_corto || 'instalacion')
    : 'todas';
  const hoy = new Date();
  const stamp = `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-${String(hoy.getDate()).padStart(2, '0')}`;
  return `tomass-${seccion}-${nombreArchivoSeguro(inst)}-${stamp}.csv`;
}

function descargarCsvIngresos() {
  const filas = estado.ultimasFilas.ingresos || [];
  if (filas.length === 0) {
    alert('No hay ingresos cargados para descargar. Filtrá primero.');
    return;
  }
  descargarCSV(
    nombreBaseArchivo('ingresos'),
    [
      { campo: 'ocurrido_en',       titulo: 'Fecha y hora' },
      { campo: 'condominio_nombre', titulo: 'Instalación' },
      { campo: 'nombre',            titulo: 'Persona' },
      { campo: 'tipo_acceso',       titulo: 'Tipo' },
      { campo: 'sentido',           titulo: 'Sentido' },
      { campo: 'estado',            titulo: 'Estado' },
      { campo: 'unidad',            titulo: 'Unidad' },
      { campo: 'patente',           titulo: 'Patente' },
      { campo: 'a_donde_va',        titulo: 'Destino' },
      { campo: 'autorizado_por',    titulo: 'Autorizó' },
      { campo: 'guardia_nombre',    titulo: 'Guardia' },
    ],
    filas,
  );
}

function descargarCsvNovedades() {
  const filas = estado.ultimasFilas.novedades || [];
  if (filas.length === 0) {
    alert('No hay novedades cargadas para descargar. Filtrá primero.');
    return;
  }
  descargarCSV(
    nombreBaseArchivo('novedades'),
    [
      { campo: 'ocurrido_en',           titulo: 'Fecha y hora' },
      { campo: 'condominio_nombre',     titulo: 'Instalación' },
      { campo: 'tipo',                  titulo: 'Tipo' },
      { campo: 'gravedad',              titulo: 'Gravedad' },
      { campo: 'titulo',                titulo: 'Título' },
      { campo: 'descripcion',           titulo: 'Descripción' },
      { campo: 'estado',                titulo: 'Estado' },
      { campo: 'reportado_por_nombre',  titulo: 'Reportó' },
    ],
    filas,
  );
}

function descargarCsvPaquetes() {
  const filas = estado.ultimasFilas.paquetes || [];
  if (filas.length === 0) {
    alert('No hay paquetes cargados para descargar. Filtrá primero.');
    return;
  }
  // Columnas que varían según el filtro: si solo son pendientes no tiene sentido
  // exportar 'entregado_en' porque viene null; si solo son entregados no tiene
  // sentido 'días en portería'. Para el filtro Todos exportamos todo.
  const esSoloEntregados = estado.paquetesEstadoActual === 'entregado';
  const esSoloPendientes = estado.paquetesEstadoActual === 'en_porteria';

  const cols = [
    { campo: 'condominio_nombre', titulo: 'Instalación' },
    { campo: 'destinatario',      titulo: 'Destinatario' },
    { campo: 'unidad',            titulo: 'Unidad' },
    { campo: 'descripcion',       titulo: 'Descripción' },
    { campo: 'recibido_en',       titulo: 'Recibido' },
    { campo: 'guardia_receptor',  titulo: 'Recibido por' },
  ];
  if (!esSoloEntregados) {
    cols.push({ campo: 'dias_en_porteria', titulo: 'Días en portería' });
  }
  if (!esSoloPendientes) {
    cols.push(
      { campo: 'estado',            titulo: 'Estado' },
      { campo: 'entregado_en',      titulo: 'Entregado' },
      { campo: 'retirado_por',      titulo: 'Retiró' },
      { campo: 'identidad_validada',titulo: 'Identidad validada' },
      { campo: 'guardia_entrega',   titulo: 'Entregado por' },
    );
  }

  descargarCSV(nombreBaseArchivo('paquetes'), cols, filas);
}

// ============================================================================
// Descarga PDF
// ============================================================================

function tituloConInstalacion(base) {
  if (!estado.condominioFiltro) return `${base} — Todas mis instalaciones`;
  const inst = estado.instalaciones.find((i) => i.id === estado.condominioFiltro);
  return `${base} — ${inst?.nombre || 'Instalación'}`;
}

function nombreBaseArchivoPdf(seccion) {
  // Igual que nombreBaseArchivo pero con extensión pdf en vez de csv.
  return nombreBaseArchivo(seccion).replace(/\.csv$/, '.pdf');
}

async function descargarPdfResumenHandler() {
  const filas = estado.ultimasFilas.resumen || [];
  if (filas.length === 0) {
    alert('No hay resumen cargado. Esperá a que termine de cargar.');
    return;
  }
  await descargarPdfResumen({
    filas,
    instalacionNombre: estado.condominioFiltro
      ? (estado.instalaciones.find((i) => i.id === estado.condominioFiltro)
          ?.nombre || 'Instalación')
      : 'Todas mis instalaciones',
  });
}

async function descargarPdfIngresos() {
  const filas = estado.ultimasFilas.ingresos || [];
  if (filas.length === 0) {
    alert('No hay ingresos cargados. Filtrá primero.');
    return;
  }
  const desde = document.getElementById('ingresosDesde').value;
  const hasta = document.getElementById('ingresosHasta').value;
  await descargarPDF({
    nombreArchivo: nombreBaseArchivoPdf('ingresos'),
    titulo: tituloConInstalacion('Informe de Ingresos'),
    subtitulo: desde && hasta
      ? `Del ${formatearFechaCorta(desde)} al ${formatearFechaCorta(hasta)}`
      : '',
    orientacion: 'landscape',
    columnas: [
      { campo: 'ocurrido_en',        titulo: 'Fecha y hora',  ancho: 32 },
      { campo: 'condominio_nombre',  titulo: 'Instalación',   ancho: 40 },
      { campo: 'nombre',             titulo: 'Persona',       ancho: 40 },
      { campo: 'tipo_acceso',        titulo: 'Tipo',          ancho: 20 },
      { campo: 'sentido',            titulo: 'Sentido',       ancho: 20 },
      { campo: 'unidad',             titulo: 'Unidad',        ancho: 18 },
      { campo: 'patente',            titulo: 'Patente',       ancho: 20 },
      { campo: 'autorizado_por',     titulo: 'Autorizó',      ancho: 35 },
      { campo: 'guardia_nombre',     titulo: 'Guardia',       ancho: 35 },
    ],
    filas,
  });
}

async function descargarPdfNovedades() {
  const filas = estado.ultimasFilas.novedades || [];
  if (filas.length === 0) {
    alert('No hay novedades cargadas. Filtrá primero.');
    return;
  }
  await descargarPDF({
    nombreArchivo: nombreBaseArchivoPdf('novedades'),
    titulo: tituloConInstalacion('Informe de Novedades'),
    subtitulo: '',
    orientacion: 'portrait',
    columnas: [
      { campo: 'ocurrido_en',          titulo: 'Fecha y hora', ancho: 32 },
      { campo: 'condominio_nombre',    titulo: 'Instalación',  ancho: 35 },
      { campo: 'tipo',                 titulo: 'Tipo',         ancho: 22 },
      { campo: 'gravedad',             titulo: 'Gravedad',     ancho: 20 },
      { campo: 'titulo',               titulo: 'Título' },
      { campo: 'estado',               titulo: 'Estado',       ancho: 20 },
      { campo: 'reportado_por_nombre', titulo: 'Reportó',      ancho: 30 },
    ],
    filas,
  });
}

async function descargarPdfPaquetes() {
  const filas = estado.ultimasFilas.paquetes || [];
  if (filas.length === 0) {
    alert('No hay paquetes cargados. Filtrá primero.');
    return;
  }
  const esSoloEntregados = estado.paquetesEstadoActual === 'entregado';
  const esSoloPendientes = estado.paquetesEstadoActual === 'en_porteria';

  const subtituloEstado =
    esSoloPendientes ? 'Pendientes de retiro'
      : esSoloEntregados ? 'Entregados (histórico)'
        : 'Todos';

  // Si el filtro es "pendientes de retiro" solamente, mantener el PDF
  // tabular — no hay foto de entrega ni firma todavía para esos paquetes.
  if (esSoloPendientes) {
    await descargarPDF({
      nombreArchivo: nombreBaseArchivoPdf('paquetes'),
      titulo: tituloConInstalacion('Informe de Paquetes'),
      subtitulo: subtituloEstado,
      orientacion: 'landscape',
      columnas: [
        { campo: 'condominio_nombre', titulo: 'Instalación',  ancho: 38 },
        { campo: 'destinatario',      titulo: 'Destinatario', ancho: 38 },
        { campo: 'unidad',            titulo: 'Unidad',       ancho: 18 },
        { campo: 'descripcion',       titulo: 'Descripción',  ancho: 50 },
        { campo: 'recibido_en',       titulo: 'Recibido',     ancho: 28 },
        { campo: 'guardia_receptor',  titulo: 'Recibido por', ancho: 32 },
        { campo: 'dias_en_porteria',  titulo: 'Días',         ancho: 14 },
      ],
      filas,
    });
    return;
  }

  // Para "Entregados" o "Todos" generamos el PDF detallado con tarjetas
  // que incluyen foto de la entrega + firma del residente.
  // Confirmar porque va a tardar unos segundos (bajar las imágenes).
  const cantidadConPruebas = filas.filter(
    (f) => f.foto_entrega_url || f.firma_url).length;
  const confirmar = confirm(
    `El PDF va a incluir las fotos y firmas de ${cantidadConPruebas} ` +
    `entregas. Esto puede tardar unos ${Math.ceil(cantidadConPruebas / 5)} ` +
    `segundos descargando las imágenes. ¿Continuar?`);
  if (!confirmar) return;

  mostrarProgresoPdf('Bajando fotos y firmas…', 0, filas.length);
  try {
    await descargarPdfPaquetesConPruebas({
      filas,
      nombreArchivo: nombreBaseArchivoPdf('paquetes'),
      titulo: tituloConInstalacion('Informe de Paquetes'),
      subtitulo: subtituloEstado,
      alProgresar: (hechos, total) => {
        mostrarProgresoPdf('Bajando fotos y firmas…', hechos, total);
      },
    });
  } finally {
    cerrarProgresoPdf();
  }
}

// ============================================================================
// Overlay de progreso para descargas de PDF que tardan
// ============================================================================

function mostrarProgresoPdf(mensaje, hechos, total) {
  let overlay = document.getElementById('progresoPdf');
  if (!overlay) {
    overlay = document.createElement('div');
    overlay.id = 'progresoPdf';
    overlay.className = 'overlay-progreso';
    overlay.innerHTML = `
      <div class="caja-progreso">
        <div class="spinner-grande"></div>
        <div class="mensaje-progreso" id="mensajeProgreso"></div>
        <div class="barra-progreso-wrap">
          <div class="barra-progreso" id="barraProgreso"></div>
        </div>
        <div class="contador-progreso" id="contadorProgreso"></div>
      </div>
    `;
    document.body.appendChild(overlay);
  }
  document.getElementById('mensajeProgreso').textContent = mensaje;
  const pct = total > 0 ? Math.round((hechos / total) * 100) : 0;
  document.getElementById('barraProgreso').style.width = pct + '%';
  document.getElementById('contadorProgreso').textContent =
    `${hechos} de ${total}`;
}

function cerrarProgresoPdf() {
  const overlay = document.getElementById('progresoPdf');
  if (overlay) overlay.remove();
}

function formatearFechaCorta(ymd) {
  // "2026-09-01" -> "01/09/2026"
  if (!ymd || ymd.length !== 10) return ymd;
  const [a, m, d] = ymd.split('-');
  return `${d}/${m}/${a}`;
}
