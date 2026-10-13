// ============================================================================
// Wrappers de las RPCs del dashboard
// ============================================================================
// Cada función es un async que llama a una RPC web_* y devuelve data o
// lanza un error con el mensaje de Supabase. Ninguna hace cache: siempre
// pega al servidor para que el dato sea fresco (el admin de la instalación
// quiere ver lo último).
// ============================================================================

const api = {
  async perfil() {
    const { data: { user } } = await supabaseClient.auth.getUser();
    if (!user) return null;
    const { data, error } = await supabaseClient
      .from('usuarios')
      .select('id, nombre_completo, rol, foto_url')
      .eq('id', user.id)
      .maybeSingle();
    if (error) throw error;
    return data;
  },

  async misInstalaciones() {
    const { data, error } = await supabaseClient.rpc('mis_instalaciones');
    if (error) throw error;
    return data || [];
  },

  async resumen() {
    const { data, error } = await supabaseClient.rpc('web_mi_resumen');
    if (error) throw error;
    return data || [];
  },

  async ingresos({ desde, hasta, condominioId }) {
    const { data, error } = await supabaseClient.rpc('web_mis_ingresos', {
      p_desde: desde,
      p_hasta: hasta,
      p_condominio_id: condominioId || null,
    });
    if (error) throw error;
    return data || [];
  },

  async novedades({ estado, condominioId }) {
    const { data, error } = await supabaseClient.rpc('web_mis_novedades', {
      p_estado: estado || null,
      p_condominio_id: condominioId || null,
    });
    if (error) throw error;
    return data || [];
  },

  async paquetes({ condominioId, estado = 'en_porteria' }) {
    const { data, error } = await supabaseClient.rpc('web_mis_paquetes', {
      p_condominio_id: condominioId || null,
      // estado puede ser 'en_porteria', 'entregado' o null (todos)
      p_estado: estado,
    });
    if (error) throw error;
    return data || [];
  },

  async guardiasDeTurno({ condominioId }) {
    const { data, error } = await supabaseClient.rpc('web_guardias_de_turno', {
      p_condominio_id: condominioId || null,
    });
    if (error) throw error;
    return data || [];
  },

  /// URL firmada para ver una foto almacenada en storage. Vale 1 hora.
  async urlFoto(bucket, path) {
    if (!path) return null;
    const { data, error } = await supabaseClient.storage
      .from(bucket)
      .createSignedUrl(path, 3600);
    if (error) return null;
    return data.signedUrl;
  },

  async salir() {
    await supabaseClient.auth.signOut();
    window.location.replace('index.html');
  },
};
