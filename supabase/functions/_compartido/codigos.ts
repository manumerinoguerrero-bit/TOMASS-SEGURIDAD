// ============================================================================
// Tomass Seguridad — Firma y verificación de los códigos QR
// ============================================================================
// Archivo de apoyo. Es el corazón de la seguridad del sistema.
//
// CÓMO FUNCIONA, EXPLICADO SIMPLE
//
// Un código QR de esta app NO es un número guardado en una lista. Es un mensaje
// firmado, como un cheque:
//
//   Contenido del mensaje: "el residente Juan Pérez, unidad 101, acceso
//                           vehicular con el auto ABC-123, válido hasta las
//                           18:05:22"
//   Firma: un sello que solo el servidor puede hacer, porque solo él tiene la
//          llave secreta del condominio.
//
// Cuando alguien presenta un código, el servidor revisa dos cosas:
//   1. Que la firma sea la suya (o sea que el código no fue inventado).
//   2. Que no haya pasado la hora de vencimiento.
//
// POR QUÉ ESTO IMPORTA TANTO
//
// Si el código fuera fijo, alguien le saca una foto a la pantalla del residente,
// la manda por WhatsApp, y el que reciba la foto entra al condominio. Con un
// código que vive 60 segundos, la foto ya no sirve para nada.
//
// Y como la información va DENTRO del código firmado, el servidor no necesita
// guardar los códigos en ninguna parte ni buscarlos en una lista: le alcanza con
// mirar la firma. Eso lo hace muy rápido y sin acumular basura.
// ============================================================================

import * as jose from "npm:jose@5";

/** Lo que va escrito adentro del código QR del residente. */
export interface ContenidoCodigo {
  /** A quién pertenece el código (el id del residente) */
  sub: string;
  /** De qué condominio es */
  cond: string;
  /** Qué unidad (para mostrarla en pantalla sin otra consulta) */
  uni?: string;
  /** peatonal o vehicular */
  tipo: "peatonal" | "vehicular";
  /** Qué vehículo va a entrar, si es acceso vehicular */
  veh?: string;
  /** Cuándo se emitió y cuándo vence (los pone la librería) */
  iat?: number;
  exp?: number;
}

const EMISOR = "tomass-seguridad";
const PUBLICO = "acceso-condominio";

/** Convierte la llave secreta del condominio al formato que usa la firma. */
function llaveDesdeTexto(secreto: string): Uint8Array {
  return new TextEncoder().encode(secreto);
}

/**
 * Crea un código QR firmado que vence en los segundos indicados.
 * Devuelve un texto largo que es lo que se dibuja como QR en la pantalla.
 */
export async function firmarCodigo(
  secreto: string,
  contenido: ContenidoCodigo,
  segundosDeVida: number,
): Promise<string> {
  return await new jose.SignJWT({ ...contenido })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer(EMISOR)
    .setAudience(PUBLICO)
    .setIssuedAt()
    .setExpirationTime(`${segundosDeVida}s`)
    .sign(llaveDesdeTexto(secreto));
}

/** Los motivos por los que un código puede no servir. */
export type MotivoInvalido = "vencido" | "firma_falsa" | "otro_condominio" | "ilegible";

export interface ResultadoVerificacion {
  valido: boolean;
  contenido?: ContenidoCodigo;
  motivo?: MotivoInvalido;
  /** Mensaje listo para mostrarle a la persona en la pantalla */
  mensaje?: string;
}

/**
 * Revisa que un código sea auténtico y esté vigente.
 *
 * Se le pasa el condominio esperado para atajar el caso de alguien que presente
 * un código legítimo pero de OTRO condominio. Sin esta comprobación, en un
 * sistema con varios condominios el código de uno serviría en el de al lado.
 */
export async function verificarCodigo(
  secreto: string,
  codigo: string,
  condominioEsperado: string,
): Promise<ResultadoVerificacion> {
  try {
    const { payload } = await jose.jwtVerify(codigo, llaveDesdeTexto(secreto), {
      issuer: EMISOR,
      audience: PUBLICO,
      // Sin tolerancia: si venció, venció. Son 60 segundos, no hace falta margen.
      clockTolerance: 0,
    });

    const contenido = payload as unknown as ContenidoCodigo;

    if (contenido.cond !== condominioEsperado) {
      return {
        valido: false,
        motivo: "otro_condominio",
        mensaje: "Este código es de otro condominio.",
      };
    }

    return { valido: true, contenido };
  } catch (fallo) {
    const codigoDeError = (fallo as { code?: string })?.code ?? "";

    if (codigoDeError === "ERR_JWT_EXPIRED") {
      return {
        valido: false,
        motivo: "vencido",
        mensaje: "El código ya venció. Volvé a la pantalla principal y esperá el nuevo.",
      };
    }

    if (
      codigoDeError === "ERR_JWS_SIGNATURE_VERIFICATION_FAILED" ||
      codigoDeError === "ERR_JWT_CLAIM_VALIDATION_FAILED"
    ) {
      return {
        valido: false,
        motivo: "firma_falsa",
        mensaje: "Este código no es válido.",
      };
    }

    return {
      valido: false,
      motivo: "ilegible",
      mensaje: "No se pudo leer el código. Intentá de nuevo.",
    };
  }
}
