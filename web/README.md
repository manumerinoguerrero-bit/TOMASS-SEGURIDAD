# Dashboard web — Tomass Seguridad

Panel web para administradores y mandantes. Lectura en tiempo real de lo
que pasa en cada instalación: ingresos, novedades, paquetes y guardias de
turno con mapa en vivo.

## Qué es y qué NO es

**Es** — un dashboard de solo lectura que corre en el browser contra las
RPCs `web_*` del backend Supabase. No necesita servidor propio: es HTML +
CSS + JS plano publicado como sitio estático.

**NO es** — una app de gestión. Para crear usuarios, editar instalaciones
o cualquier cambio de configuración, Manuel sigue usando la app Flutter
de Android. Esta carpeta no modifica datos, solo los muestra.

## Para qué usuarios

- **Administrador** (rol `administrador`) — Manuel y futuros admins de
  Tomass. Ven todas las instalaciones donde están delegados.
- **Mandante** (rol `mandante`) — administrador de edificio, dueño de
  empresa cliente. Ve solo SU instalación. Puede entrar con su correo
  institucional y la contraseña que le crea el administrador.

Los roles `guardia` y `residente` no pueden entrar — el login los
rechaza con mensaje explícito.

## URL de producción

Una vez activado GitHub Pages (ver abajo), el dashboard queda en:
`https://manumerinoguerrero-bit.github.io/TOMASS-SEGURIDAD/`

## Primera vez: activar GitHub Pages

1. Ir a **Settings → Pages** del repo.
2. En **Source** elegir **GitHub Actions**.
3. Hacer un commit a `/web/` o lanzar manualmente el workflow
   "Publicar dashboard web" desde la pestaña Actions.
4. En 1-2 minutos el sitio queda publicado.

## Estructura

```
web/
├── index.html         Login
├── panel.html         Panel SPA con 5 pestañas
├── css/estilo.css     Hoja de estilos (mismo branding que la app)
├── js/
│   ├── config.js      URL y anon key de Supabase
│   ├── login.js       Lógica del login
│   ├── api.js         Wrappers de las 5 RPCs web_*
│   └── panel.js       Renderizado de cada vista
├── img/logo.png       Logo T rojo
└── README.md
```

## Dependencias externas (por CDN)

- **@supabase/supabase-js v2** — cliente oficial
- **Leaflet 1.9.4** — mapa en vivo con tiles de OpenStreetMap

Zero build, zero npm. Modificar y pushear es publicar.

## RPCs del backend que consume

Todas definidas en `base-de-datos/27-rol-mandante-y-rpcs-web.sql`:

- `web_mi_resumen()` — resumen de instalaciones con contadores
- `web_mis_ingresos(desde, hasta, condominio)` — accesos del período
- `web_mis_novedades(estado, condominio)` — incidentes
- `web_mis_paquetes(condominio)` — paquetes pendientes de retiro
- `web_guardias_de_turno(condominio)` — turnos abiertos con GPS

Todas chequean `es_admin_o_mandante()` + `mis_instalaciones()` del lado
del servidor. La anon key del cliente NO da acceso a más que lo que RLS
permite.

## Cómo crear un mandante

Desde SQL (hasta que haya UI de alta de usuarios en el dashboard):

```sql
-- 1. Crear la auth user (desde Supabase dashboard: Authentication → Add user)
-- 2. Insertar en public.usuarios:
INSERT INTO public.usuarios (id, nombre_completo, email, rol, estado)
VALUES (
  '<auth_user_id>',
  'Nombre del mandante',
  'mandante@edificio.cl',
  'mandante',
  'activo'
);

-- 3. Darle acceso a su instalación:
INSERT INTO public.administra_instalaciones (usuario_id, condominio_id)
VALUES ('<auth_user_id>', '<condominio_id>');
```

Después el mandante entra a la URL del dashboard con su correo + contraseña
y ve solo esa instalación.
