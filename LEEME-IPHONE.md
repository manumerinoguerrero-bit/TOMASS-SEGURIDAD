# ¿Se puede usar en iPhone?

**Sí, la app está escrita para funcionar en iPhone.** Pero hay tres cosas que
saber antes de prometérselo a un cliente, y una de ellas cuesta plata.

---

## Lo corto

| | Android | iPhone |
|---|---|---|
| ¿El código funciona? | Sí, andando hoy | Sí, ya revisado |
| ¿Podés compilarla vos? | Sí, en GitHub, gratis | Solo en un Mac prestado de GitHub |
| ¿Podés instalarla en un teléfono? | Sí, ahora mismo | **No, sin la cuenta de Apple** |
| Costo | $0 | **99 dólares al año** |

---

## Lo que ya se arregló

Revisando el proyecto encontré un problema que habría hecho fallar la
compilación para iPhone apenas se intentara:

El proyecto declaraba que funcionaba desde **iOS 13**, pero tres piezas que la
app usa de verdad exigen **iOS 15.5**:

- el lector de patentes (google_mlkit_text_recognition)
- su librería de apoyo (google_mlkit_commons)
- el lector de códigos QR (mobile_scanner)

Con iOS 13 declarado, la compilación falla con un error que no explica nada.
Ya está subido a 15.5 en todos lados, y se agregó el archivo `ios/Podfile`, que
no existía.

**iOS 15.5 salió en mayo de 2022 y anda desde el iPhone 6s en adelante**, así
que en la práctica cubre cualquier iPhone que alguien use hoy.

---

## Los tres obstáculos reales

### 1. Una app de iPhone solo se puede armar en una Mac

No es una limitación de cómo está hecha la app: es una regla de Apple. En
Windows no hay forma, ni con trucos.

**La vuelta:** GitHub presta computadores Mac por minutos. Se agregó el flujo
**"Comprobar iPhone"** que hace exactamente eso.

Para usarlo: en GitHub → pestaña **Comportamiento** (Actions) → en la lista de la
izquierda elegí **"Comprobar iPhone"** → botón **Run workflow**.

> ⚠️ **Ese flujo NO arranca solo, a propósito.** Los minutos de Mac se cobran
> **diez veces más caro** que los normales. Con los 2.000 minutos gratis que da
> GitHub por mes, alcanza para unas 15 comprobaciones de iPhone. Si corriera en
> cada cambio, en dos semanas te quedarías sin minutos y **también** se caerían
> las compilaciones de Android, que son las que usás todos los días.

### 2. Para instalarla en un iPhone de verdad hay que pagarle a Apple

Esto es lo que de verdad te frena, y no tiene vuelta.

Apple no deja instalar una app en un iPhone si no está **firmada** con una
cuenta de desarrollador. Esa cuenta cuesta **99 dólares al año** (unos 95.000
pesos chilenos, precio de julio de 2026).

Con la cuenta pagada podés:

- Repartir la app por **TestFlight**, que es lo que conviene para los clientes:
  ellos instalan una app desde una invitación, sin trámites raros.
- Publicarla en la App Store, si más adelante querés venderla como producto.

**Sin la cuenta pagada** solo se puede instalar conectando el iPhone por cable a
una Mac con Xcode, y la app **se vence a los 7 días**. Para probar vos mismo
sirve; para un cliente, no.

### 3. Los avisos que suenan también necesitan esa cuenta

Los avisos en iPhone pasan por el sistema de Apple (APNs), y la llave para
usarlo sale de la misma cuenta de desarrollador.

O sea: **sin los 99 dólares no hay avisos en iPhone**, aunque Firebase esté
configurado. En Android sí funcionan, y son gratis.

---

## Mientras esperás que Apple te apruebe la cuenta: instalarla igual, gratis, en UN iPhone

Esto no reemplaza la cuenta paga — es solo para ver la app andando en un iPhone
de verdad HOY, mientras Apple aprueba tu membresía (puede tardar de horas a un
par de días).

### Lo que hace falta

- Un iPhone, con su cable para conectarlo a la computadora.
- Tu computadora Windows (no hace falta Mac para esto).
- Un **Apple ID gratuito** (no la cuenta paga — el que se crea en
  appleid.apple.com sin costo).

### Paso a paso

1. En GitHub → pestaña **Comportamiento** → **"Comprobar iPhone"** → **Run
   workflow**. Esperá a que termine (tarda varios minutos, es normal).
2. Entrá a esa ejecución terminada. Abajo de todo hay una sección
   **"Artifacts"** con un archivo llamado **tomass-seguridad-ipa-sin-firmar**.
   Descargalo y descomprimilo: adentro va a estar el archivo
   `tomass-seguridad-sin-firmar.ipa`.
3. Bajá e instalá **Sideloadly** (gratis) desde **sideloadly.io**, la versión
   para Windows.
4. Conectá el iPhone a la computadora por cable. Si el teléfono pregunta "¿Confiar
   en esta computadora?", tocá que sí.
5. Abrí Sideloadly. Debería reconocer el iPhone conectado solo.
6. Arrastrá el archivo `tomass-seguridad-sin-firmar.ipa` a la ventana de
   Sideloadly.
7. Te va a pedir un Apple ID y su contraseña: poné el **gratuito** (no hace
   falta que sea el mismo que estás dando de alta como pago). Sideloadly lo usa
   solo para firmar la app, no toca nada de tu cuenta.
8. Tocá **Start**. Va a tardar un par de minutos.
9. **Paso que la gente se olvida y por eso la app no abre:** en el iPhone, andá
   a **Ajustes → General → VPN y Gestión de dispositivos**. Ahí va a aparecer
   tu Apple ID gratuito con un aviso de que no es de confianza. Tocalo, y tocá
   **"Confiar"**. Recién ahí el ícono de la app va a abrir sin quejarse.

### Lo que hay que tener presente

- **Se vence a los 7 días.** Pasada la semana, la app deja de abrir. Hay que
  repetir del paso 4 en adelante. No es un error de la app: es lo máximo que
  Apple permite sin la cuenta paga.
- **Sirve para UN iPhone a la vez**, el que tengas conectado por cable en ese
  momento. No hay forma de mandarle esto a un guardia a distancia: para eso
  sigue haciendo falta TestFlight.

---

## Qué te conviene hacer

**Mi recomendación: empezá solo con Android.**

Razones concretas:

1. En Chile, alrededor de tres de cada cuatro celulares son Android. Los
   guardias, que son quienes más usan la app, casi siempre tienen Android.
2. Android no te cuesta nada y ya está funcionando.
3. Los 99 dólares se pagan **todos los años**, no una sola vez. Si la app deja
   de renovarse, desaparece de los iPhone de todos.

**Cuándo sí conviene pagarlos:** cuando tengas un cliente firmado que lo pida.
Un colegio o un condominio caro puede tener directiva con iPhone. Ahí los 99
dólares salen del contrato y no de tu bolsillo.

Mientras tanto, el código para iPhone queda listo y comprobado. El día que
pagues la cuenta, no hay que reescribir nada.

---

## Si algún día pagás la cuenta

Los pasos, en orden:

1. Comprar la membresía en **https://developer.apple.com/programs** (99 USD/año).
2. En Firebase, agregar una app de iPhone con el identificador
   `cl.tomass.tomassSeguridad` y bajar el archivo `GoogleService-Info.plist`.
3. En la cuenta de Apple, crear una **llave APNs** y subirla a Firebase.
4. Configurar la firma digital en GitHub, para que las compilaciones salgan
   instalables.
5. Subir la app a TestFlight e invitar a los clientes por correo.

Cuando llegues a eso, avisame y lo hacemos paso a paso.

> Nota sobre el identificador: en iPhone es `cl.tomass.tomassSeguridad` y en
> Android es `cl.tomass.tomass_seguridad`. **Son distintos y está bien así**:
> Apple no permite guiones bajos. Cada uno se registra por separado en Firebase.
