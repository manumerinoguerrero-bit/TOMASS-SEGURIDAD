-- ============================================================================
-- Tomass Seguridad — Asiducam: tipo definitivo 'empresa'
-- ============================================================================
-- En la migration 23 Asiducam quedó como tipo 'otro' porque Manuel no había
-- confirmado la clasificación. El 05/10/2026 confirmó que es 'empresa'.
-- Idempotente: UPDATE sin efecto si ya está en 'empresa'.
-- ============================================================================

UPDATE public.condominios
   SET tipo = 'empresa'
 WHERE nombre = 'Asiducam'
   AND tipo <> 'empresa';
