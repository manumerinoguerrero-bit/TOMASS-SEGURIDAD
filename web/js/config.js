// ============================================================================
// Tomass Seguridad — Configuración del cliente Supabase
// ============================================================================
// La anon key es un token PÚBLICO con permisos limitados (solo lo que RLS
// permite). No es un secreto, se puede commitear sin problemas — así es el
// patrón de Supabase. Lo peligroso sería la service_role key, que NO
// aparece acá.
//
// Las RPCs web_* chequean es_admin_o_mandante() + mis_instalaciones() del
// lado del servidor, así que un usuario con solo la anon key no puede ver
// más que lo que su cuenta tiene permitido.
// ============================================================================

const SUPABASE_URL = 'https://ymgadpinqxqkjgxslftg.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_gy8OAPO4k4KhbWOBRZ027Q_RBvUiClS';

// Inicializa el cliente globalmente para que lo use el resto del código.
const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false,
    },
  }
);
