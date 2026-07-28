// ============================================================================
// Tomass Seguridad — Pantalla que todavía no está hecha
// ============================================================================
// POR QUÉ EXISTE ESTO EN LUGAR DE DEJAR LA PESTAÑA SIN CONECTAR
//
//   Una pestaña que no hace nada al tocarla parece una app rota, y el guardia no
//   tiene forma de saber si es que falta o si se colgó. Con este cartel queda
//   claro qué va a hacer y que todavía no está.
//
//   Además permite recorrer la app completa desde ya y probar que el menú, la
//   navegación y los avisos funcionan.
// ============================================================================

import 'package:flutter/material.dart';

import '../../config/tema.dart';

class PantallaEnConstruccion extends StatelessWidget {
  const PantallaEnConstruccion({
    super.key,
    required this.titulo,
    required this.queVaAHacer,
    this.icono = Icons.construction_rounded,
  });

  final String titulo;
  final String queVaAHacer;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colores.grafito.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icono, size: 32, color: Colores.textoSuave),
                ),
                const SizedBox(height: 20),
                Text(
                  'Esta pantalla está en construcción',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  queVaAHacer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: Colores.textoSuave,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colores.grafito.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                    border: Border.all(color: Colores.linea),
                  ),
                  child: const Text(
                    'Llega en la próxima entrega',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: Colores.textoSuave,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
