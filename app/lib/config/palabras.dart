// ============================================================================
// Tomass Seguridad — Las palabras de cada instalación
// ============================================================================
// EL PROBLEMA QUE RESUELVE
//
//   La app se escribió pensando en condominios, así que decía "residente",
//   "unidad" y "condominio" en todas las pantallas.
//
//   Pero Tomass Seguridad Privada también atiende COLEGIOS. Y a un colegio no
//   se le puede hablar de residentes ni de unidades: ahí hay apoderados y
//   cursos. Un director que abre la app y lee "tu unidad" entiende, en un
//   segundo, que el sistema no fue hecho para él.
//
//   Este archivo tiene las palabras correctas de cada tipo de instalación. Las
//   pantallas piden la palabra en vez de tenerla escrita a mano.
//
// CÓMO SE USA EN UNA PANTALLA
//
//   final palabras = ref.watch(palabrasProvider);
//   Text('Avisale a ${palabras.elHabitante}')     → "residente" o "apoderado"
//   Text(palabras.elEspacioConMayuscula)          → "Unidad" o "Curso"
//
// DÓNDE MÁS VIVE ESTA MISMA LISTA
//
//   En la base de datos, en la función palabras_de_la_instalacion (archivo
//   base-de-datos/08-instalaciones.sql). Sirve para los informes que salen del
//   servidor. Las dos listas tienen que decir lo mismo: si se agrega un tipo
//   nuevo de instalación, hay que agregarlo en los dos lados.
// ============================================================================

/// Las palabras que usa una instalación según su tipo.
class Palabras {
  const Palabras({
    required this.tipo,
    required this.laInstalacion,
    required this.elHabitante,
    required this.losHabitantes,
    required this.elEspacio,
    required this.losEspacios,
  });

  /// 'condominio', 'colegio', 'empresa', 'edificio' u 'otro'
  final String tipo;

  /// Con artículo, para meterlo en una frase: "el condominio", "el colegio".
  final String laInstalacion;

  /// "residente", "apoderado", "trabajador"
  final String elHabitante;

  /// "residentes", "apoderados", "trabajadores"
  final String losHabitantes;

  /// "unidad", "curso", "oficina", "departamento"
  final String elEspacio;

  /// "unidades", "cursos", "oficinas", "departamentos"
  final String losEspacios;

  /// Para arrancar una frase o poner un título: "Residente", "Apoderado".
  String get elHabitanteConMayuscula => _mayuscula(elHabitante);
  String get losHabitantesConMayuscula => _mayuscula(losHabitantes);

  /// Para etiquetas de formulario: "Unidad", "Curso".
  String get elEspacioConMayuscula => _mayuscula(elEspacio);
  String get losEspaciosConMayuscula => _mayuscula(losEspacios);

  /// Sin el artículo: "condominio", "colegio". Para cuando la frase ya lo tiene.
  String get instalacionSinArticulo {
    final partes = laInstalacion.split(' ');
    return partes.length > 1 ? partes.sublist(1).join(' ') : laInstalacion;
  }

  /// Para un título o una etiqueta de ficha: "Condominio", "Colegio".
  String get instalacionConMayuscula => _mayuscula(instalacionSinArticulo);

  static String _mayuscula(String texto) =>
      texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);

  /// Devuelve las palabras del tipo pedido.
  ///
  /// Si el tipo viene vacío o es uno que todavía no conocemos, usa las de
  /// condominio: es lo más común y nunca deja una pantalla sin texto.
  factory Palabras.deTipo(String? tipo) =>
      _porTipo[tipo] ?? _porTipo['condominio']!;

  static const Map<String, Palabras> _porTipo = {
    'condominio': Palabras(
      tipo: 'condominio',
      laInstalacion: 'el condominio',
      elHabitante: 'residente',
      losHabitantes: 'residentes',
      elEspacio: 'unidad',
      losEspacios: 'unidades',
    ),
    'colegio': Palabras(
      tipo: 'colegio',
      laInstalacion: 'el colegio',
      elHabitante: 'apoderado',
      losHabitantes: 'apoderados',
      elEspacio: 'curso',
      losEspacios: 'cursos',
    ),
    'empresa': Palabras(
      tipo: 'empresa',
      laInstalacion: 'la empresa',
      elHabitante: 'trabajador',
      losHabitantes: 'trabajadores',
      elEspacio: 'oficina',
      losEspacios: 'oficinas',
    ),
    'edificio': Palabras(
      tipo: 'edificio',
      laInstalacion: 'el edificio',
      elHabitante: 'residente',
      losHabitantes: 'residentes',
      elEspacio: 'departamento',
      losEspacios: 'departamentos',
    ),
    'otro': Palabras(
      tipo: 'otro',
      laInstalacion: 'la instalación',
      elHabitante: 'usuario',
      losHabitantes: 'usuarios',
      elEspacio: 'unidad',
      losEspacios: 'unidades',
    ),
  };
}
