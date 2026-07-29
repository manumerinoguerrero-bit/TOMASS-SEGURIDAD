# Que el celular suene con la app cerrada

## Qué pasa hoy y qué falta

**Hoy ya funciona:** si el guardia tiene la app abierta, los avisos le aparecen
en menos de un segundo. En la garita eso alcanza, porque la app está prendida
todo el turno.

**Lo que falta:** que suene el teléfono cuando la app está cerrada o guardada en
el bolsillo. Eso le importa sobre todo al residente: si llega una visita y él no
está mirando la app, hoy no se entera.

Para eso hace falta **Firebase**, un servicio de Google. Es **gratis** para lo
que necesitamos y no tiene límite práctico.

**Todo el código de la app ya está escrito y funcionando.** Lo único que falta
son dos trámites en dos páginas web, que solo podés hacer vos porque hay que
entrar con tu cuenta. Son unos 20 minutos.

> **La app funciona igual mientras tanto.** Nada se rompe por no hacer esto. Si
> el archivo de Google no está, la app compila igual, se instala igual y anda
> igual. Lo único que no pasa es que suene con la app cerrada.

---

## PARTE 1 · Crear el proyecto en Firebase (10 minutos)

### Paso 1 — Entrá y creá el proyecto

1. Andá a **https://console.firebase.google.com**
2. Entrá con tu cuenta de Google.
3. Apretá **"Crear un proyecto"**.
4. Ponele de nombre: **Tomass Seguridad**
5. Cuando pregunte por Google Analytics, elegí **desactivarlo**. No lo
   necesitamos y solo agrega trámites.
6. Apretá **Crear proyecto** y esperá.

### Paso 2 — Agregá la app de Android

1. Ya adentro del proyecto, apretá el ícono de **Android** (el robot verde).
2. Te va a pedir el "nombre del paquete". Copiá y pegá **exactamente** esto:

   ```
   cl.tomass.tomass_seguridad
   ```

   > ⚠️ Tiene que ser igual, letra por letra, con los guiones bajos. Si le
   > cambiás una letra, Google crea una app distinta y los avisos nunca van a
   > llegar. No hay ningún mensaje de error que te avise de esto.

3. El apodo y la huella SHA-1 los podés dejar en blanco.
4. Apretá **Registrar app**.

### Paso 3 — Bajá el archivo y guardalo en su lugar

1. Firebase te va a ofrecer descargar un archivo llamado
   **`google-services.json`**. Descargalo.
2. Guardalo **exactamente acá**, dentro de la carpeta del proyecto:

   ```
   TOMASS SEGURIDAD\app\android\app\google-services.json
   ```

   > Ojo con la carpeta: es `app\android\app`, con "app" dos veces. Es así de
   > verdad, no es un error.

3. Los pasos siguientes que muestra Firebase (los de "agregar el SDK") **saltalos
   todos**: eso ya está hecho en el código.

---

## PARTE 2 · Darle permiso al servidor (10 minutos)

Firebase ahora sabe quién es la app. Falta que el servidor tenga permiso para
mandarle avisos.

### Paso 4 — Conseguí la llave del servidor

1. En Firebase, arriba a la izquierda, apretá la **rueda dentada** ⚙️ y elegí
   **Configuración del proyecto**.
2. Andá a la pestaña **Cuentas de servicio**.
3. Apretá **Generar nueva clave privada** y confirmá.
4. Se descarga un archivo `.json`. **Guardalo en un lugar seguro.**

   > ⚠️ Ese archivo es una llave maestra. Cualquiera que lo tenga puede mandar
   > notificaciones a nombre de tu app. **No lo guardes dentro de la carpeta del
   > proyecto** y no lo subas a GitHub.

### Paso 5 — Pegá la llave en Supabase

1. Andá a **https://supabase.com/dashboard** y entrá a tu proyecto.
2. En el menú de la izquierda, abajo: **Project Settings** → **Edge Functions**.
3. Buscá la sección de **Secrets** y apretá **Add new secret**.
4. En el nombre, escribí exactamente:

   ```
   FIREBASE_CUENTA_SERVICIO
   ```

5. En el valor, abrí el archivo `.json` que bajaste con el Bloc de notas,
   seleccioná **TODO** el contenido (Ctrl+E, Ctrl+C) y pegalo ahí.

   > Tiene que ir el contenido completo, desde la primera llave `{` hasta la
   > última `}`.

6. Guardá.

---

## PARTE 3 · Prender todo

### Paso 6 — Subí el cambio

1. Abrí **GitHub Desktop**.
2. Vas a ver el archivo `google-services.json` como cambio nuevo.
3. Escribí un mensaje ("Firebase configurado") y apretá **Commit**, después
   **Push origin**.

Cuando GitHub compile, la app nueva ya va a traer los avisos prendidos.

### Paso 7 — Probá que funciona

1. Instalá el APK nuevo en un celular.
2. Entrá con un usuario **residente**.
3. La primera vez, el teléfono te va a preguntar si permitís las notificaciones.
   Decí que **sí**.
4. **Cerrá la app del todo** (deslizala fuera de las apps recientes).
5. Desde otro teléfono, entrá como **guardia** y registrale un paquete a ese
   residente.
6. El primer teléfono tiene que **sonar**, con la app cerrada.

---

## Cómo saber si quedó bien

En la compilación de GitHub, buscá esta línea en el registro:

- ✅ `Tomass: Firebase configurado, los avisos van a sonar.`
- ❌ `Tomass: falta google-services.json...` → el archivo no está donde va.
  Revisá la ruta del paso 3.

---

## Los dos tonos de aviso

La app tiene dos tipos de aviso separados, y el residente puede silenciar uno
sin silenciar el otro desde los ajustes de su teléfono:

| Tono | Para qué | Cómo se comporta |
|---|---|---|
| **Accesos urgentes** | Autos esperando en la barrera, visitas que necesitan respuesta ahora | Aparece en pantalla y vibra con un ritmo doble |
| **Avisos** | Paquetes, vehículos aprobados, novedades | Solo aparece en la barra de arriba |

Esto es a propósito: un guardia cansado de que le suenen los paquetes podría
apagar los avisos, y con un solo tono apagaría también los de los autos.

---

## Para iPhone hace falta un paso más

Los avisos en iPhone necesitan además una **llave APNs**, que solo se consigue
con la cuenta de desarrollador de Apple (99 dólares al año). Está explicado en
**LEEME-IPHONE.md**.

Mientras tanto, en Android funciona todo.

---

## Si algo sale mal

**"Se instaló pero no suena nada"**
Revisá que en el paso 2 hayas puesto exactamente `cl.tomass.tomass_seguridad`.
Es el error más común y no da ningún aviso.

**"No me preguntó por el permiso de notificaciones"**
Andá a los ajustes del teléfono → Aplicaciones → Tomass Seguridad →
Notificaciones, y activalas a mano. Android a veces no vuelve a preguntar.

**"Suena en un teléfono pero no en otro"**
Cada teléfono se registra la primera vez que entra con la app nueva. En el que
no suena, cerrá sesión y volvé a entrar.
