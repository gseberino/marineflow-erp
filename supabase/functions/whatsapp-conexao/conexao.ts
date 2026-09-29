// Regras da conexão do WhatsApp com a Evolution, sem I/O (testáveis em conexao_test.ts).
//
// Por que existe: em 29/09/2026 o celular removeu o aparelho conectado às 16:21 e ninguém
// soube por 4 horas — o vigia do PC só olhava se o servidor respondia, não se o número estava
// conectado. Reconectar exigia o Claude gerar o QR no PC. Agora o ERP mostra o estado, gera o
// QR (ou o código de 8 dígitos para conectar só com o celular) e avisa no sino quando cai.

export type EstadoConexao = "open" | "connecting" | "close" | "inacessivel";

const ESTADOS_DA_EVOLUTION = new Set(["open", "connecting", "close"]);

/** Estado a partir da resposta de /instance/connectionState ou /instance/connect. */
export function lerEstado(json: unknown): EstadoConexao | null {
  const j = json as { instance?: { state?: unknown }; state?: unknown } | null;
  const bruto = String(j?.instance?.state ?? j?.state ?? "");
  return ESTADOS_DA_EVOLUTION.has(bruto) ? bruto as EstadoConexao : null;
}

export interface RespostaDoConnect {
  estado: EstadoConexao;
  qr: string | null;
  codigo: string | null;
}

/**
 * /instance/connect devolve { base64, code, pairingCode, count } enquanto espera a leitura,
 * ou o formato do connectionState quando já está conectado. Sem QR e sem estado explícito
 * (primeiros segundos, o Baileys ainda não emitiu o código) conta como "connecting".
 */
export function lerRespostaDoConnect(json: unknown): RespostaDoConnect {
  const j = (json ?? {}) as { base64?: unknown; pairingCode?: unknown };
  const estado = lerEstado(json);
  if (estado === "open") return { estado, qr: null, codigo: null };
  const qr = typeof j.base64 === "string" && j.base64.startsWith("data:image/") ? j.base64 : null;
  const codigo = typeof j.pairingCode === "string" && j.pairingCode.trim() ? j.pairingCode.trim() : null;
  return { estado: estado ?? "connecting", qr, codigo };
}

/**
 * Número para o código de pareamento: só dígitos, com DDI 55. Aceita o que a pessoa digita
 * ("(47) 99999-0000", "+55 47 ...") e o ownerJid da instância ("5547...@s.whatsapp.net").
 */
export function numeroParaPareamento(entrada: string | null | undefined): string | null {
  const bruto = String(entrada ?? "").split("@")[0];
  let d = bruto.replace(/\D/g, "");
  if (d.length === 10 || d.length === 11) d = `55${d}`;
  // DDD nunca começa com 0 (0800, 0300 não são celular).
  return /^55[1-9]\d{9,10}$/.test(d) ? d : null;
}

/** Motivo legível do último código de desconexão do Baileys. */
export function motivoDaQueda(codigo: number | null | undefined): string | null {
  switch (codigo) {
    case 401: return "o aparelho foi desconectado pelo celular (Dispositivos conectados)";
    case 440: return "outra conexão tomou o lugar desta";
    case 403: return "o WhatsApp recusou a conexão";
    case 411: return "o celular pediu para conectar de novo";
    case 428: return "a conexão foi encerrada";
    case 408: return "a conexão expirou sem resposta";
    case 500: return "a sessão ficou inválida";
    case 515: return "o servidor reiniciou a conexão";
    default: return null;
  }
}

// ---------------------------------------------------------------------------------------------
// Vigia: roda a cada 5 min pelo pg_cron e guarda uma linha só (whatsapp_conexao_vigia).

export interface RegistroDoVigia {
  estado: EstadoConexao;
  /** Desde quando está NESTE estado. */
  desde: string;
  /** Quando o aviso de queda foi mandado (null = queda ainda não avisada, ou está conectado). */
  avisado_em: string | null;
}

export type Aviso = "caiu" | "voltou" | null;

/** Minutos fora do ar antes de avisar: absorve o religamento do túnel/Docker pelo vigia do PC. */
export const MINUTOS_ATE_AVISAR = 10;

export function decidirVigia(
  anterior: RegistroDoVigia | null,
  agora: EstadoConexao,
  quando: Date,
  minutosAteAvisar = MINUTOS_ATE_AVISAR,
): { registro: RegistroDoVigia; aviso: Aviso } {
  const iso = quando.toISOString();
  const foraDoAr = (e: EstadoConexao) => e !== "open";

  if (!anterior) {
    return { registro: { estado: agora, desde: iso, avisado_em: null }, aviso: null };
  }

  if (agora === "open") {
    const avisou = anterior.avisado_em !== null;
    const desde = anterior.estado === "open" ? anterior.desde : iso;
    return { registro: { estado: "open", desde, avisado_em: null }, aviso: avisou ? "voltou" : null };
  }

  // Fora do ar. Trocar entre close/connecting/inacessivel não zera o relógio da queda.
  const desde = foraDoAr(anterior.estado) ? anterior.desde : iso;
  const registro: RegistroDoVigia = { estado: agora, desde, avisado_em: anterior.avisado_em };
  if (registro.avisado_em) return { registro, aviso: null };

  const minutosFora = (quando.getTime() - new Date(desde).getTime()) / 60000;
  if (minutosFora >= minutosAteAvisar) {
    return { registro: { ...registro, avisado_em: iso }, aviso: "caiu" };
  }
  return { registro, aviso: null };
}

function hhmm(iso: string): string {
  return new Date(iso).toLocaleTimeString("pt-BR", {
    timeZone: "America/Sao_Paulo", hour: "2-digit", minute: "2-digit",
  });
}

export function textoDoAviso(
  aviso: Exclude<Aviso, null>,
  registro: RegistroDoVigia,
  motivo: string | null = null,
): { title: string; body: string } {
  if (aviso === "voltou") {
    return {
      title: "WhatsApp da HBR conectado de novo",
      body: "Mensagens voltaram a entrar e sair.",
    };
  }
  const desde = hhmm(registro.desde);
  if (registro.estado === "inacessivel") {
    return {
      title: "WhatsApp fora do ar",
      body: `Desde ${desde} o ERP não alcança o servidor do WhatsApp no PC (PC, Docker ou túnel desligado). Religar no PC.`,
    };
  }
  return {
    title: "WhatsApp da HBR desconectado",
    body: `Desde ${desde} nenhuma mensagem entra ou sai${motivo ? `: ${motivo}` : ""}. Toque para reconectar.`,
  };
}
