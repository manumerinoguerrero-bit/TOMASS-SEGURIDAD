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
  document.getElementById('cerrarModal').addEventListener('click', cerrarModal);

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
  try {
    const filas = await api.paquetes({
      condominioId: estado.condominioFiltro,
    });
    if (filas.length === 0) {
      cont.innerHTML = '<div class="vacio">No hay paquetes pendientes de retiro.</div>';
      return;
    }
    cont.innerHTML = filas.map((f) => `
      <div class="card paquete ${f.dias_en_porteria > 7 ? 'card-atrasado' : ''}">
        <div class="card-head">
          <h3>${escapar(f.destinatario || 'Sin destinatario')}</h3>
          <span class="chip ${f.dias_en_porteria > 7 ? 'chip-critica' : 'chip-info'}">
            ${f.dias_en_porteria} día${f.dias_en_porteria === 1 ? '' : 's'}
          </span>
        </div>
        <div class="meta">
          <span>Unidad ${escapar(f.unidad || '—')}</span>
          <span>${escapar(f.condominio_nombre)}</span>
          <span>Recibido ${formatearFecha(f.recibido_en)}</span>
          <span>por ${escapar(f.guardia_receptor || '—')}</span>
        </div>
        ${f.descripcion ? `<p>${escapar(f.descripcion)}</p>` : ''}
      </div>
    `).join('');
  } catch (e) {
    cont.innerHTML = `<div class="vacio error">Error: ${escapar(e.message || String(e))}</div>`;
  }
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
