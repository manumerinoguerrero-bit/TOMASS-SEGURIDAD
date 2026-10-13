// ============================================================================
// Tomass Seguridad — Helper para exportar datos como CSV
// ============================================================================
// Convierte un array de objetos en un CSV descargable con escaping RFC 4180
// y BOM UTF-8 al inicio para que Excel abra bien los acentos y la ñ.
//
// Uso:
//   const filas = [
//     { nombre: 'Juan', edad: 30 },
//     { nombre: 'Ana',  edad: 25 },
//   ];
//   descargarCSV('personas.csv', ['nombre', 'edad'], filas);
//
// También acepta columnas con alias (para renombrar la cabecera del CSV):
//   descargarCSV('personas.csv',
//     [{ campo: 'nombre', titulo: 'Nombre completo' },
//      { campo: 'edad',   titulo: 'Años' }],
//     filas);
// ============================================================================

/**
 * Escapa un valor según RFC 4180: envuelve en comillas si contiene coma,
 * comilla, salto de línea o retorno de carro; duplica las comillas internas.
 */
function escaparCSV(valor) {
  if (valor == null) return '';
  const s = String(valor);
  if (/[",\n\r]/.test(s)) {
    return '"' + s.replace(/"/g, '""') + '"';
  }
  return s;
}

/**
 * Dispara la descarga de un CSV generado al vuelo.
 *
 * @param {string} nombreArchivo  "ingresos-2026-10.csv"
 * @param {Array<string|{campo:string,titulo:string}>} columnas
 * @param {Array<Object>} filas
 */
function descargarCSV(nombreArchivo, columnas, filas) {
  const defs = columnas.map((c) =>
    typeof c === 'string' ? { campo: c, titulo: c } : c
  );

  const encabezado = defs.map((d) => escaparCSV(d.titulo)).join(',');
  const cuerpo = filas.map((fila) =>
    defs.map((d) => escaparCSV(formatearValor(fila[d.campo]))).join(',')
  ).join('\n');

  // BOM UTF-8 para que Excel detecte el encoding y muestre acentos bien.
  const csv = '﻿' + encabezado + '\n' + cuerpo + '\n';

  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = nombreArchivo;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

/**
 * Formateo mínimo para hacer el CSV legible en Excel sin perder precisión:
 *   * Fechas ISO -> "YYYY-MM-DD HH:MM" (Excel las entiende como fecha)
 *   * Booleanos  -> "sí" / "no"
 *   * null       -> ""
 */
function formatearValor(v) {
  if (v == null) return '';
  if (typeof v === 'boolean') return v ? 'sí' : 'no';
  if (typeof v === 'string') {
    // Si parece ISO date (ej. "2026-10-13T15:30:00+00:00"), convertir.
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(v)) {
      const d = new Date(v);
      if (!isNaN(d.getTime())) {
        const pad = (n) => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
          `${pad(d.getHours())}:${pad(d.getMinutes())}`;
      }
    }
  }
  return v;
}

/** Nombre de archivo seguro: sin espacios ni caracteres especiales. */
function nombreArchivoSeguro(base) {
  return (base || 'archivo')
    .toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')  // quita acentos
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}
