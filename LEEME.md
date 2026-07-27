# Tomass Seguridad

Sistema de control de acceso para condominios residenciales.
App para celular (residentes) y tablet (guardias), más panel de administración.

**Estado: Fases 1, 2 y 3 de 5 terminadas.**
Última actualización: 26 de julio de 2026.

---

## Qué hay listo hoy

**Fase 1 — la base de datos.** Donde se guarda toda la información del sistema,
con los candados de seguridad puestos y probados uno por uno.

**Fase 2 — el cerebro de seguridad.** Las tres funciones del servidor que generan
los códigos QR que caducan en 60 segundos, deciden quién entra y avisan al guardia.

Nada de esto es teórico: está corriendo en un servidor real, con un condominio de
prueba cargado, y verifiqué cada pieza antes de entregártela.

### Lo que cubre

| Área | Qué guarda |
|---|---|
| Condominios | Varios condominios en el mismo sistema, con los datos totalmente separados |
| Unidades y personas | Departamentos, casas, propietarios, arrendatarios, guardias, administradores |
| Vehículos | Con aprobación obligatoria del administrador antes de poder entrar |
| Accesos | **Entradas Y salidas**, peatonales y vehiculares, imposibles de borrar |
| Cola de la barrera | Los autos esperando que el guardia abra, en tiempo real |
| Paquetes | Recepción con foto, inventario por antigüedad, entrega con firma digital |
| Visitas | Pre-registradas por WhatsApp **y** espontáneas con aprobación del residente |
| Personal de servicio | Nana, jardinero, profesor: credencial que solo sirve sus días y su horario |
| Incidentes | El cuaderno de novedades del guardia, con fotos |
| Turnos | Qué guardia está en qué puesto, para que le lleguen los avisos correctos |
| Dispositivos | Los celulares registrados, para poder revocarlos a distancia |

---

## Las tres garantías que quedaron grabadas en la base de datos

Esto no depende de que la app se acuerde de hacerlo bien. Lo bloquea la base de
datos misma, así que ni un error de programación futuro puede romperlo.

**1 · Un condominio jamás ve los datos de otro.**
Es lo que te permite venderle el sistema a varios condominios sin rehacer nada.

**2 · Un residente solo ve lo suyo.**
Lo probé: Juan Pérez, entrando como residente, ve **1 persona** (él mismo) de las
7 que hay cargadas, sus 2 vehículos, sus 2 paquetes y sus 3 movimientos. Cero
acceso a la lista de residentes, a la cola de autos o a los incidentes.

**3 · Los registros de acceso no se pueden modificar ni borrar. Por nadie.**
Ni por el administrador, ni por mí, ni por tu freelance. Es lo que convierte al
registro en prueba válida si hay un robo o un juicio.
Lo probé sin querer: mi propio archivo de datos de ejemplo intentó modificar un
registro y la base de datos lo rechazó. Tuve que corregir el archivo.

---

## Fase 2 · El cerebro de seguridad (ya funcionando)

### Cómo funciona el código QR, explicado simple

El código QR de esta app **no es un número guardado en una lista**. Es un mensaje
firmado, como un cheque:

> *"El residente Juan Pérez, unidad 101, acceso vehicular con el auto ABC-123,
> válido hasta las 18:05:22"* — firmado por el servidor.

El servidor firma con una llave secreta que solo él tiene. Cuando alguien presenta
un código, revisa dos cosas: que la firma sea la suya, y que no haya pasado la hora
de vencimiento.

**Por qué esto importa tanto.** Si el código fuera fijo, alguien le saca una foto a
la pantalla del residente, la manda por WhatsApp, y el que reciba la foto entra al
condominio. Con un código que vive 60 segundos, la foto no sirve para nada.

Cada condominio tiene **su propia llave**. Si algún día se filtrara la de uno, los
demás siguen seguros. Se crean solas y nunca hay que tocarlas.

### Las tres funciones

| Función | Qué hace |
|---|---|
| `generar-qr` | Le da al celular del residente un código nuevo cada 60 segundos |
| `validar-acceso` | El portero digital: decide si el residente entra, y avisa al guardia |
| `validar-credencial` | El guardia escanea a un visitante o a la nana, y le dice si pasa |

### Cómo decide si es entrada o salida

Mira el último movimiento de la persona. Si la última vez entró, ahora sale. Si
salió (o nunca pasó), ahora entra. **Así alcanza un solo QR pegado en el muro** y
nadie tiene que elegir nada.

Y si alguien escanea dos veces por error, no lo cuenta como salida: dentro de los
primeros 2 minutos en el mismo punto lo toma como repetido.

### Dos detalles chicos que evitan problemas grandes

**Nadie queda encerrado.** El código de un visitante sirve una sola vez para entrar,
pero para **salir funciona siempre**, incluso vencido. Si no fuera así, un visitante
que se quedó hasta tarde no podría salir y habría que abrirle a mano. Lo mismo con
la nana que terminó pasadas sus horas: el horario solo se revisa al entrar.

**Un acceso nunca se cae por una notificación.** Si el aviso al guardia falla, el
residente entra igual y el aviso queda guardado. Un sistema de acceso que se bloquea
porque falló una notificación es un sistema roto.

### Los avisos ya funcionan, sin Firebase

Los avisos viajan por dos caminos, y esto es a propósito:

**Camino 1 — dentro de la app. Funciona desde hoy, sin configurar nada.** Si el
guardia tiene la tablet prendida en la caseta, la pantalla se actualiza **sola** en
menos de un segundo. Ya está probado y andando.

**Camino 2 — la notificación que suena. Necesita Firebase (Fase 5).** Hace sonar el
celular aunque la app esté cerrada, para cuando el guardia lo tiene en el bolsillo.

El código de Firebase ya está escrito y listo. Cuando cargues la cuenta de Firebase,
se enciende solo. Mientras tanto no molesta ni rompe nada.

---

## Fase 3 · La app del residente (completa)

El proyecto Flutter está en la carpeta `app/`: **32 archivos, unas 8.900 líneas.**
Pasa la revisión automática de Flutter sin un solo error ni advertencia.

### Las nueve pantallas, todas listas

| Pantalla | |
|---|---|
| 01 · Iniciar sesión (correo, contraseña y huella) | ✅ |
| 02 · Mi código de acceso — peatonal | ✅ |
| 03 · Mi código de acceso — vehicular | ✅ |
| Escanear el código del muro | ✅ |
| 04 · Acceso aprobado (verde) | ✅ |
| 05 · Acceso denegado (rojo) | ✅ |
| 06 · Mis vehículos, con lectura automática de la patente | ✅ |
| 07 · Mis paquetes | ✅ |
| 08 · Invitar visitante y responder visitas espontáneas | ✅ |
| 09 · Mi perfil e historial de accesos | ✅ |

### ⚠️ Falta poner el logo

Guardá el logo en `app/assets/imagenes/logo.png`, con **fondo transparente**,
al menos 512 píxeles de alto, y **solo el escudo** (sin las palabras debajo, que
las escribe la app aparte).

En cuanto el archivo esté ahí, la app lo usa sola. Mientras tanto dibuja un escudo
de respaldo parecido pero simplificado: no se rompe, pero el logo real se ve mucho
mejor porque tiene metal cepillado y degradados que el código no reproduce bien.

Hay instrucciones completas en `app/assets/imagenes/LEEME.txt`.

### Cómo funciona la lectura de la patente

El residente le saca una foto a la patente y la app lee el texto sola. Pero una
foto de un auto tiene texto por todos lados: la marca, el modelo, la automotora,
algún adhesivo. Así que no alcanza con "leer texto": la app busca cuál de todos
esos textos **tiene forma de patente chilena**, y acepta los tres formatos
vigentes (BCDF-12, AB-1234, ABC-12).

También corrige las confusiones típicas: en la parte de las letras, un 0 leído
pasa a O; en la de los números, una O pasa a 0.

**Siempre le pide confirmar lo que leyó.** Ninguna lectura automática acierta el
100% de las veces, y una patente mal cargada significa que el auto no entra y que
el residente discute con el guardia sin entender por qué. Confirmar 6 caracteres
cuesta dos segundos y evita ese problema entero.

### Las fotos son privadas

Las fotos de vehículos, paquetes, firmas y personas se guardan en cajones
**privados**. No tienen enlace fijo: cuando la app va a mostrar una, le pide al
servidor un enlace temporal que vale una hora y después deja de funcionar.

El motivo es concreto: la foto de la patente de un auto o la cara de un residente
son datos personales, y los enlaces fijos se filtran solos (quedan en historiales,
en capturas, en mensajes reenviados).

Además, las fotos se comprimen antes de subirlas. Una foto de celular pesa 4 o 5
MB y subir eso desde la entrada del condominio con mala señal tarda medio minuto.
Comprimida pesa unos 300 KB y se ve igual de bien para reconocer un auto.

### Tres decisiones del código que conviene que sepas

**La sesión se guarda en la zona blindada del teléfono.**
No en el almacenamiento común. Va al Keychain en iPhone y al Keystore en Android,
donde el sistema operativo la encripta con una llave que vive en un chip aparte.

**Los errores están traducidos al español, todos.**
En vez de mostrar `SocketException: Failed host lookup`, la app dice *"Sin
conexión a internet. Revisá el wifi o los datos del celular e intentá de nuevo."*
Cada mensaje indica el siguiente paso, no solo el problema.

**La app deja de pedir códigos cuando pasa a segundo plano.**
Sin eso, pediría un código por minuto toda la noche con el teléfono guardado en el
bolsillo, gastando batería y datos para nada. Al volver, si el código venció, pide
uno nuevo al instante.

### Dos trampas que ya están resueltas

**`MainActivity` extiende `FlutterFragmentActivity`, no `FlutterActivity`.**
Flutter lo crea con `FlutterActivity`, que es lo normal. Pero la huella digital
necesita la otra. Con la incorrecta, la app compila y arranca igual, y **se cae en
el momento exacto en que el residente toca "Ingresar con huella"**. Está anotado
dentro del propio archivo para que nadie lo revierta sin saber.

**Los permisos de iPhone ya están escritos.**
Si falta la frase que explica para qué se usa la cámara o el Face ID, Apple
rechaza la app al publicarla y en las pruebas se cae al usar esa función.

### ⚠️ Si la compilación falla con "Unable to establish loopback connection"

Al compilar en el equipo de Manuel, aparece este error:

```
java.io.IOException: Unable to establish loopback connection
```

**No es un problema del proyecto ni de Flutter.** Está roto algo de la red interna
de Windows en ese equipo. Lo comprobamos así:

1. Falla igual en una carpeta limpia, corta y fuera de OneDrive → no es la ruta.
2. Falla igual con Java 17 y con Java 21 → no es la versión de Java.
3. Un programa de Java de 20 líneas que solo hace `Selector.open()` —
   la operación más básica de red que existe— **también falla**, sin Gradle,
   sin Flutter y sin el proyecto de por medio.

El error de fondo es este:

```
java.net.SocketException: Invalid argument: connect
    at sun.nio.ch.UnixDomainSockets.connect0
    at sun.nio.ch.WEPollSelectorImpl.<init>
```

Java necesita crear una "tubería" interna para comunicarse consigo mismo, y en
Windows la arma con sockets de dominio Unix. En ese equipo esa conexión falla.

**Cómo se arregla** (hay que hacerlo a mano, con permisos de administrador):

1. Botón de inicio → escribí `cmd`
2. Clic derecho en "Símbolo del sistema" → **Ejecutar como administrador**
3. Escribí este comando y presioná Enter:

```
netsh winsock reset
```

4. **Reiniciá el computador.** Sin reiniciar no toma efecto.
5. Después del reinicio, probá de nuevo:

```bash
flutter build apk --debug
```

Ese comando repara el catálogo de red de Windows, que es donde está el problema.
Es una reparación estándar de Windows y no borra archivos ni programas. Sí puede
hacer que tengas que volver a conectarte a una VPN, si usás alguna.

**Lo que ya se probó y NO sirvió** (26 y 27 de julio de 2026):

- Reiniciar Windows (dos veces)
- `netsh winsock reset` + reiniciar
- Cambiar entre Java 17 y Java 21
- Compilar fuera de OneDrive, en una ruta corta y sin espacios
- Cambiar la carpeta temporal
- Forzar IPv4 y forzar el mecanismo de red antiguo de Java

El controlador `afunix` de Windows está instalado y corriendo, pero igual falla.
Lo que queda son reparaciones profundas del sistema (`sfc /scannow`, `DISM`), que
hay que correr como administrador y pueden tardar una hora.

**Pero no hace falta esperar a arreglar ese computador.** Ver la sección
siguiente.

---

## Compilar el APK sin usar tu computador

El proyecto trae una receta que hace que **GitHub compile el APK gratis en sus
propios computadores**. Tu equipo no participa, así que el problema de Windows
deja de importar.

Está en `.github/workflows/compilar-apk.yml`. Tarda unos 6 minutos y GitHub regala
2.000 minutos por mes, así que no cuesta nada.

### Pasos, una sola vez

1. Creá una cuenta gratis en [github.com](https://github.com) si no tenés.

2. Instalá GitHub Desktop desde [desktop.github.com](https://desktop.github.com).
   Es un programa con botones, no hay que escribir comandos.

3. Abrilo, andá a `File` → `Add local repository` y elegí la carpeta
   **TOMASS SEGURIDAD**.

4. Te va a decir que no es un repositorio. Aceptá **`create a repository`**.

5. Apretá **`Publish repository`**. **Dejá marcado "Keep this code private"**:
   el proyecto tiene la dirección de tu servidor y no conviene que sea público.

### Cada vez que quieras un APK nuevo

1. En GitHub Desktop, escribí un resumen del cambio y apretá `Commit to main`.
2. Apretá `Push origin`.
3. Andá a tu repositorio en github.com → pestaña **`Actions`**.
4. Esperá que el círculo amarillo se ponga verde (unos 6 minutos).
5. Entrá a esa compilación y descargá **`tomass-seguridad-apk`** desde abajo.

Ese archivo es el instalador de la app. Pasalo al celular por WhatsApp o cable, y
al abrirlo Android te va a pedir permiso para "instalar apps desconocidas": es
normal para una app que no viene de la Play Store.

> ⚠️ El archivo `.gitignore` que está en el proyecto ya bloquea la subida de
> llaves y secretos (`google-services.json`, archivos de firma, `.env`). No lo
> borres ni lo edites sin saber lo que hacés.

---

## Cómo ponerlo a funcionar

### Ya está funcionando

Creé un proyecto en tu cuenta de Supabase con todo cargado y andando:

- **Dirección:** `https://ymgadpinqxqkjgxslftg.supabase.co`
- **Costo:** $0 al mes (plan gratuito)
- **Panel de control:** entrá a [supabase.com](https://supabase.com) con tu cuenta
- **Nombre del proyecto:** todavía figura como `condoaccess-pro`, el nombre que
  tenía la app antes. Es solo una etiqueta y no afecta nada, pero si te molesta
  verla podés cambiarla vos en 10 segundos: entrá al proyecto → `Project Settings`
  → `General` → campo `Project name` → escribí `tomass-seguridad` → `Save`.
  La dirección de arriba **no cambia** al renombrarlo, así que nada se rompe.
  No lo renombré yo porque la única forma sería borrar el proyecto y crearlo de
  nuevo, y eso destruiría la base de datos que ya está cargada y probada.

Tu proyecto de Merlyn Seguridad **no se tocó**. Son dos proyectos separados.

### Cuentas para probar

Todas usan la misma contraseña: **`Demo1234!`**

| Rol | Correo | Para qué sirve |
|---|---|---|
| Administrador | `admin@losaromos.cl` | Ver todo, aprobar vehículos, sacar informes |
| Guardia vehicular | `carlos@losaromos.cl` | Abrir la barrera, recibir paquetes |
| Guardia peatonal | `luis@losaromos.cl` | Escanear códigos en la garita |
| Residente | `juan@gmail.com` | Unidad 101, tiene 1 auto aprobado y 1 pendiente |
| Residente | `ana@gmail.com` | Unidad 102, tiene un auto esperando la barrera |

> ⚠️ Estas cuentas son **solo para pruebas**. Cuando pongas el sistema a funcionar
> de verdad en tu condominio, hay que borrarlas y crear las reales con contraseñas
> propias.

### Si tu freelance necesita empezar de cero

Los cuatro archivos de la carpeta `base-de-datos/` se ejecutan **en orden**, uno
por uno, pegándolos en el editor SQL de Supabase (menú `SQL Editor` → botón `Run`):

```
1. base-de-datos/01-tablas.sql              crea las 16 tablas
2. base-de-datos/02-seguridad.sql           pone los candados
3. base-de-datos/03-funciones-y-vistas.sql  crea los atajos y los avisos en vivo
4. base-de-datos/04-datos-de-ejemplo.sql    carga el condominio de prueba
5. base-de-datos/05-llaves-y-limites.sql    las llaves secretas de los códigos QR
```

Y después las tres funciones del servidor, con la herramienta de Supabase:

```bash
supabase functions deploy generar-qr validar-acceso validar-credencial
```

El archivo 4 termina con seis consultas de verificación y el comentario de qué
tiene que devolver cada una. Si los números coinciden, quedó bien instalado.

**El archivo 4 NO se ejecuta en la base de datos real del condominio.** Es solo
para probar.

---

## Una cosa que tenés que activar a mano

En el panel de Supabase hay una protección apagada que conviene encender:

1. Entrá a [supabase.com](https://supabase.com) → tu proyecto
2. Menú `Authentication` → `Policies` (o `Sign In / Providers`)
3. Activá **Leaked password protection**

Eso impide que un residente use una contraseña que ya se filtró en algún hackeo
conocido de internet. Es un solo interruptor y sube bastante la seguridad.

---

## Decisiones que tomé y por qué te conviene saberlas

**Cambié el plan técnico original para ahorrarte plata.**
El plan pedía cinco servicios: servidor Node.js, PostgreSQL, Redis, Socket.io y
Cloudinary. Los reemplacé por **Supabase**, que trae todo eso adentro y que ya usás
en tu app de Merlyn.

| | Plan original | Con Supabase |
|---|---|---|
| Costo al empezar | 40 a 60 USD/mes | **0 USD** |
| Costo al crecer | 60 a 100 USD/mes | **25 USD** |
| Servicios que mantener | 5 | 1 |
| Código a la medida | ~40 endpoints | 4 funciones chicas |

El ahorro grande no son los dólares: son las **horas de tu freelance**, que ya
conoce esta herramienta.

**Las contraseñas no las guarda nuestro sistema.**
Las maneja Supabase, encriptadas, junto con el "olvidé mi contraseña" y la
verificación por correo. Menos código y ninguna posibilidad de que se nos filtre
una lista de contraseñas, porque nunca las tocamos.

**Los avisos en vivo son tres líneas, no un servidor aparte.**
La pantalla del guardia se actualiza sola cuando llega un auto. En el plan
original eso requería un servidor de Socket.io corriendo aparte.

**La paleta de colores es negro grafito, no azul.**
El plan original decía azul índigo. Se cambió el 26 de julio de 2026, después de
comparar las dos opciones en mockups.

| Para qué | Color |
|---|---|
| Base: encabezados, botones, barra lateral | `#1c1e24` grafito |
| Base secundaria | `#2b2f39` |
| Aprobar | `#2e7d32` verde |
| Denegar | `#d32f2f` rojo |
| Atención: autos esperando, paquetes viejos | `#ef6c00` naranja |
| Fondo de las pantallas | `#f4f5f6` |

El motivo no es estético. El rojo es un color de la marca (está en el logo), así que
si además fuera el color de base de la app, el guardia lo vería todo el día y
**"ACCESO DENEGADO" perdería fuerza justo cuando más importa**. Con el grafito de
base, el rojo en pantalla significa siempre una sola cosa.

> ⚠️ Regla para el desarrollador: el rojo **nunca** se usa como decoración ni como
> acento de marca dentro de la interfaz. Solo para denegar o alertar.

**Nadie se borra, se desactiva.**
Cuando un residente se muda, pasa a inactivo y se anota el motivo. Su código deja
de funcionar al instante, pero su historial de entradas se conserva.

---

## Lo que verifiqué antes de entregarte esto

Cada una de estas pruebas la corrí de verdad contra la base de datos:

- Las 15 tablas se crean sin errores
- Las 7 cuentas de login se crean y quedan listas para entrar
- El panel del administrador devuelve los 11 números correctos
- **Quiénes están adentro** devuelve exactamente Juan, Pedro y la visita María,
  y excluye a Ana porque ya salió
- Un residente ve solo lo suyo (1 usuario de 7, sus 2 autos, sus 2 paquetes)
- Un guardia ve lo que necesita (7 usuarios, 8 movimientos, la cola de autos)
- El sistema sabe solo que el puesto de Carlos es la Entrada Vehicular
- **ABRIR ACCESO funciona completo**: registra la entrada, deja anotado que Carlos
  autorizó, saca la tarjeta de la cola y hace aparecer a Ana adentro del condominio
- **Modo sin internet**: el mismo movimiento enviado dos veces crea una sola fila
- El personal de servicio queda bien denegado un domingo si trabaja lunes,
  miércoles y viernes
- Los registros de acceso rechazan cualquier intento de modificación
- El chequeo de seguridad automático de Supabase quedó sin advertencias reales

### Y de la Fase 2

- El código QR se genera firmado y vence exactamente a los 60 segundos
- **Un código con la firma alterada se rechaza** (probado adulterando la firma)
- Un código del muro inventado se rechaza
- El límite de 1 código cada 30 segundos funciona (respondió "esperá 26 segundos")
- Un guardia no puede pedir un código de residente
- Sin sesión iniciada no se puede llamar a ninguna función
- **El flujo vehicular completo**: Juan escanea, se crea la solicitud, y a Carlos le
  llega el aviso urgente con la patente y la pantalla a la que ir
- La solicitud aparece en la pantalla del guardia con todos los datos de la tarjeta
- Detecta bien entrada o salida según el último movimiento de la persona
- Un visitante que ya entró puede **salir** aunque su código haya vencido
- Una visita espontánea sin responder muestra "esperando al residente", no "denegado"
- La nana de lunes/miércoles/viernes queda denegada un domingo, con el motivo exacto
  y su horario en pantalla
- Un residente no puede validar credenciales de nadie

### Errores míos que encontré y corregí en el camino

Los anoto para que sepas que esto se revisó en serio:

1. Usé letras inválidas en los identificadores del archivo de datos. No se habría
   podido ejecutar.
2. El archivo de datos intentaba modificar un registro de acceso, justo lo que el
   candado prohíbe. Lo cambié para que el valor vaya en el insert.
3. El cálculo de "accesos de hoy" usaba la hora del servidor en vez de la de Chile.
   Habría contado mal cerca de la medianoche.
4. Las funciones quedaban al alcance de cualquiera sin iniciar sesión, incluida la
   de limpieza automática. Lo detectó el chequeo de Supabase.
5. **El login no funcionaba.** Las cuentas creadas por SQL dejaban ocho columnas en
   "nulo" y el sistema de login de Supabase se caía con un error que no menciona en
   ningún momento cuál es el problema real. Ya está corregido en el archivo 4, con la
   explicación al lado para que nadie más lo sufra.
6. En el camino vehicular, si el celular reintentaba por mala señal, el código usaba
   una variable antes de que existiera y habría reventado. Reestructurado.

---

## Qué falta (fases 2 a 5)

| Fase | Qué incluye |
|---|---|
| **3** | App del residente: login con huella, código QR que cambia solo, mis vehículos, mis paquetes, invitar visitante |
| **4** | App del guardia: escáner, **autos esperando la barrera**, paquetes con firma digital, incidentes, modo sin internet |
| **5** | Panel del administrador, configuración de Firebase para Android y iPhone, y la guía paso a paso para compilar e instalar la app |

El [prototipo visual de las 20 pantallas](https://claude.ai/code/artifact/f2cb8241-2b18-4f9c-b235-6c9f89709627)
ya está aprobado y es la referencia de cómo se va a ver todo.

---

## Estructura de archivos

```
TOMASS SEGURIDAD/
├── LEEME.md                            ← este archivo
├── base-de-datos/
│   ├── 01-tablas.sql                   las 16 tablas
│   ├── 02-seguridad.sql                los candados (el archivo más importante)
│   ├── 03-funciones-y-vistas.sql       atajos y avisos en vivo
│   ├── 04-datos-de-ejemplo.sql         condominio de prueba
│   └── 05-llaves-y-limites.sql         llaves secretas de los códigos QR
└── supabase/functions/                 el servidor
    ├── _compartido/
    │   ├── respuesta.ts                da forma a las respuestas
    │   ├── clientes.ts                 conexiones a la base de datos
    │   ├── codigos.ts                  firma y verifica los códigos QR
    │   └── avisos.ts                   avisa a los celulares
    ├── generar-qr/index.ts             entrega el código al residente
    ├── validar-acceso/index.ts         el portero digital
    └── validar-credencial/index.ts     visitantes y personal de servicio
```

Cada archivo está comentado en español y explica qué hace y por qué.
