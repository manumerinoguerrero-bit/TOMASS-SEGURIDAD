// ============================================================================
// Login del dashboard web
// ============================================================================
// Si ya hay sesión activa, redirige directo al panel. Si no, muestra el
// formulario y al enviarlo intenta signInWithPassword. Al éxito, panel.
// ============================================================================

(async function () {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (session) {
    window.location.replace('panel.html');
    return;
  }

  const form = document.getElementById('formLogin');
  const btn = document.getElementById('btnLogin');
  const err = document.getElementById('mensajeError');

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    err.hidden = true;
    btn.disabled = true;
    btn.textContent = 'Ingresando…';

    const email = document.getElementById('email').value.trim();
    const password = document.getElementById('password').value;

    const { data, error } = await supabaseClient.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      btn.disabled = false;
      btn.textContent = 'Ingresar';
      err.textContent = traducirError(error.message);
      err.hidden = false;
      return;
    }

    // Chequeo rápido: el usuario tiene que ser admin o mandante. Un residente
    // o guardia que use sus credenciales de la app NO debe entrar.
    const { data: perfil } = await supabaseClient
      .from('usuarios')
      .select('rol, estado')
      .eq('id', data.user.id)
      .maybeSingle();

    if (!perfil || perfil.estado !== 'activo' ||
        !['administrador', 'mandante'].includes(perfil.rol)) {
      await supabaseClient.auth.signOut();
      btn.disabled = false;
      btn.textContent = 'Ingresar';
      err.textContent = 'Tu cuenta no tiene acceso al panel. Pedí a Tomass ' +
        'Seguridad que te den rol de mandante o administrador.';
      err.hidden = false;
      return;
    }

    window.location.replace('panel.html');
  });

  function traducirError(mensaje) {
    const m = (mensaje || '').toLowerCase();
    if (m.includes('invalid login') || m.includes('invalid credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (m.includes('email not confirmed')) {
      return 'La cuenta todavía no fue confirmada. Contactá a Tomass.';
    }
    if (m.includes('network') || m.includes('failed to fetch')) {
      return 'Sin conexión. Revisá tu internet y volvé a intentar.';
    }
    return mensaje || 'No se pudo iniciar sesión.';
  }
})();
