// O portão do whatsapp-webhook para o fluxo de comprovantes (F1, 11/10/2026).
//
// Roda DENTRO do waitUntil do webhook (a resposta à Evolution já saiu), com as dependências
// injetadas para ser testado sem rede. Leve de propósito: importa só nucleo/modo/dono.
//
// Garantias (o webhook é o caminho de todo o WhatsApp):
//   - texto e áudio (sem mediaKind) ou mensagem sem id → despacho de hoje SEM ler nada;
//   - mídia de quem não é admin → despacho de hoje sem ler nada;
//   - mídia com o interruptor em "off" → só a leitura da chave, e o despacho de hoje;
//   - qualquer erro ao ler modo/dono → despacho de hoje;
//   - rota "comprovante" cujo receber falha → despacho de hoje (nada se perde);
//   - rota "ambos" → o despacho de hoje E o receber, em paralelo.
// Nunca lança: o despacho acontece no máximo uma vez.
import type { Dono } from "../whatsapp/dono.ts";
import type { Modo } from "./modo.ts";
import { type Rota, rotaDaMensagem } from "./nucleo.ts";

export type CorpoDoReceber = { message_id: string; modo: "sombra" | "dono"; rota: "comprovante" | "ambos"; dono_id: string };

export type DependenciasDoRoteador = {
  lerModo(): Promise<Modo>;
  dono(): Promise<Dono | null>;
  /** POST comprovantes-whatsapp {acao:"receber"}; true só com HTTP 200 e aceito=true. */
  chamarReceber(corpo: CorpoDoReceber): Promise<boolean>;
  /** O dispatchToAgent de hoje (ele mesmo engole os próprios erros). */
  despacharAoAgente(): Promise<void>;
  /**
   * Rota "comprovante" que caiu no despacho de hoje: marca a linha (se o receber chegou a criá-la,
   * por exemplo respondendo depois do prazo) como já encaminhada na chegada — o banco não manda
   * a mesma mensagem ao assistente de novo depois da leitura (comprovante_ja_encaminhado).
   */
  marcarEncaminhado?(messageId: string): Promise<void>;
};

/** Prazo do receber: roda dentro do waitUntil (não atrasa a Evolution) e cobre a partida a frio. */
export const PRAZO_DO_RECEBER_MS = 20_000;

/**
 * POST comprovantes-whatsapp {acao:"receber"} com a chave de serviço (porta chamadaInterna) e
 * 20 s de prazo. true SÓ com HTTP 200 e aceito=true; qualquer outra coisa (422, 5xx, rede, tempo)
 * = false, e o roteador cai no despacho de hoje.
 */
export async function chamarReceberPorHttp(
  corpo: CorpoDoReceber,
  opts: { url: string; chave: string; fetch?: typeof fetch; timeoutMs?: number },
): Promise<boolean> {
  try {
    const res = await (opts.fetch ?? fetch)(`${opts.url}/functions/v1/comprovantes-whatsapp`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${opts.chave}` },
      body: JSON.stringify({ acao: "receber", ...corpo }),
      signal: AbortSignal.timeout(opts.timeoutMs ?? PRAZO_DO_RECEBER_MS),
    });
    if (res.status !== 200) {
      await res.body?.cancel().catch(() => {});
      return false;
    }
    const resposta = await res.json().catch(() => null) as { aceito?: unknown } | null;
    return resposta?.aceito === true;
  } catch {
    return false;
  }
}

export async function rotearMidiaDoDono(
  p: {
    msgId: string | null;
    appUserId: string;
    appUserRole: string | null;
    mediaKind: "image" | "document" | null | undefined;
    caption: string | null | undefined;
    /** O mimetype declarado do documento: planilha/zip/docx nem entram no fluxo. */
    mimetype?: string | null;
  },
  deps: DependenciasDoRoteador,
): Promise<Rota> {
  let despachou = false;
  const despachar = async () => {
    if (despachou) return;
    despachou = true;
    try {
      await deps.despacharAoAgente();
    } catch {
      /* o despacho de hoje já registra a própria falha */
    }
  };

  // Texto, áudio, vídeo, figurinha ou mensagem que não foi gravada: nada novo é lido.
  if (!p.msgId || (p.mediaKind !== "image" && p.mediaKind !== "document")) {
    await despachar();
    return "agente";
  }
  // Só o dono (um admin) entra no fluxo: funcionário habilitado segue como hoje, sem consulta nova.
  if (p.appUserRole !== "admin") {
    await despachar();
    return "agente";
  }

  let rota: Rota = "agente";
  let modo: Modo = "off";
  let dono: Dono | null = null;
  try {
    modo = await deps.lerModo();
    if (modo !== "off") {
      dono = await deps.dono();
      rota = rotaDaMensagem({
        modo,
        ehDono: Boolean(dono && dono.id === p.appUserId),
        mediaKind: p.mediaKind,
        temMsgId: true,
        caption: p.caption,
        mimetype: p.mimetype,
      });
    }
  } catch {
    rota = "agente";
  }

  if (rota === "agente" || !dono || (modo !== "sombra" && modo !== "dono")) {
    await despachar();
    return "agente";
  }

  const corpo: CorpoDoReceber = { message_id: p.msgId, modo, rota, dono_id: dono.id };
  const receber = async (): Promise<boolean> => {
    try {
      return (await deps.chamarReceber(corpo)) === true;
    } catch {
      return false;
    }
  };

  if (rota === "ambos") {
    await Promise.allSettled([receber(), despachar()]);
    return "ambos";
  }

  // rota "comprovante": o fluxo assume; se o receber falhar, a mensagem vai ao assistente como hoje.
  if (await receber()) return "comprovante";
  if (deps.marcarEncaminhado) {
    try {
      await deps.marcarEncaminhado(p.msgId);
    } catch {
      /* sem a marca, no pior caso o assistente recebe a mesma foto duas vezes */
    }
  }
  await despachar();
  return "agente";
}
