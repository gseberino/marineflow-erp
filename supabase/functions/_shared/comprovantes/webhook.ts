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
//
// F2 (11/10/2026 — spec-f2.md, 5.7): o TEXTO e o ÁUDIO do dono (admin) passam pelo registro de
// perguntas (rotearTextoDoDono): uma RPC (pergunta_rotear) dentro do waitUntil. Conversa desligada →
// o despacho de hoje, sem mais nada. De quem não é admin: zero leitura nova (como na F1).
import type { Dono } from "../whatsapp/dono.ts";
import { type Destino, type EstadoDoTelefone, quemResponde } from "../whatsapp/pergunta-ativa.ts";
import type { Modo } from "./modo.ts";
import { type Rota, rotaDaMensagem } from "./nucleo.ts";
import { classeDoComando, interpretarResposta, lerComando, pareceDica, respostaNaoEntendida } from "./respostas.ts";
import { TEXTO_FALHA } from "./conversa.ts";

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

// ---------------------------------------------------------------------------------------------
// F2: texto e áudio do dono (a conversa dos comprovantes)
// ---------------------------------------------------------------------------------------------

export type DependenciasDoTexto = {
  /** pergunta_rotear (lerEstadoDoTelefone): a ÚNICA leitura nova; erro = conversa desligada. */
  estado(citado: string | null): Promise<EstadoDoTelefone>;
  /** Transcreve o áudio (whatsapp-transcribe-audio). null = não deu. */
  transcrever(): Promise<string | null>;
  /** POST comprovantes-whatsapp (responder | pendentes | desempatar). */
  chamarComprovantes(corpo: Record<string, unknown>): Promise<{ status: number; tratada?: boolean }>;
  /** O dispatchToAgent de hoje; com `texto`, usa esse texto (o áudio já transcrito não transcreve de novo). */
  despacharAoAgente(texto?: string): Promise<void>;
  /** "Não consegui registrar essa resposta agora…": só quando o responder recusou ANTES de processar. */
  avisarFalha(): Promise<void>;
  /**
   * pergunta_interromper: o texto livre vai ao assistente com a pergunta de um CMP aberta — o próximo
   * "sim"/número sem citar não vale para o CMP sem reapresentar a pergunta. Opcional (nunca lança).
   */
  interromper?(): Promise<void>;
};

/**
 * Para onde vai o texto (ou o áudio) do dono. Ordem: estado (1 RPC); desligada → despacho de hoje
 * (o áudio transcreve lá, como hoje). Ligada: áudio → transcreve UMA vez (falhou → "[audio]" ao
 * assistente); quemResponde; comprovante/reabrir/comando/dica/foto/não-entendi → responder:
 *   - 200 + tratada:false, ou 422 (a edge recusou antes de processar: mensagem que não confere,
 *     conversa desligada no meio) → despacha com o texto (nada se perde);
 *   - 5xx → aviso de falha e NENHUM despacho (um "1" de menu nunca cai no assistente por falha);
 *   - sem resposta (rede, tempo): NADA — o responder pode ter gravado e mandado o "Próximo:"; pedir
 *     para repetir faria o "1" cair na pergunta seguinte;
 * pendentes → a lista e depois o despacho; ambíguo → desempate, sem despacho; assistente → despacho
 * com o texto (com a pergunta de um CMP aberta, marcada "interrompida" antes). Exceção antes de
 * decidir → despacho de hoje, uma vez. Nunca lança.
 */
export async function rotearTextoDoDono(
  p: { msgId: string; phone: string; tipo: string; texto: string; citado: string | null },
  deps: DependenciasDoTexto,
): Promise<Destino> {
  let despachou = false;
  const despachar = async (texto?: string) => {
    if (despachou) return;
    despachou = true;
    try {
      await deps.despacharAoAgente(texto);
    } catch {
      /* o despacho de hoje já registra a própria falha */
    }
  };
  const avisar = async () => {
    try {
      await deps.avisarFalha();
    } catch {
      /* sem aviso: no pior caso o dono repete a resposta */
    }
  };

  let estado: EstadoDoTelefone;
  try {
    estado = await deps.estado(p.citado);
  } catch {
    await despachar();
    return "assistente";
  }
  if (!estado?.conversa || !estado.dono) {
    await despachar();
    return "assistente";
  }
  const ativaDoCmp = estado.ativa?.origem === "comprovante";
  // o texto livre vai ao assistente com a pergunta de um CMP aberta: ela fica "interrompida"
  const despacharAoAssistente = async (texto?: string) => {
    if (ativaDoCmp && deps.interromper) {
      try {
        await deps.interromper();
      } catch {
        /* sem a marca: no pior caso o "sim" seguinte cai no empate de sempre */
      }
    }
    await despachar(texto);
  };

  let texto = p.texto;
  let destino: Destino;
  try {
    if (p.tipo === "audio") {
      let transcrito: string | null = null;
      try {
        transcrito = await deps.transcrever();
      } catch {
        transcrito = null;
      }
      if (!transcrito || !transcrito.trim()) {
        await despacharAoAssistente("[audio]");
        return "assistente";
      }
      texto = transcrito;
    }
    const agora = new Date();
    const comando = lerComando(texto, agora);
    const ativa = ativaDoCmp ? estado.ativa : null;
    const interp = ativa ? interpretarResposta(ativa.passo, ativa.opcoes, texto, agora) : null;
    const ultima = !estado.ativa ? estado.ultima_do_cmp ?? null : null;
    const iUltima = ultima ? interpretarResposta(ultima.passo, ultima.opcoes, texto, agora) : null;
    destino = quemResponde({
      texto, citado: p.citado, estado, ehRespostaValida: interp !== null, ehComando: classeDoComando(comando), agora,
      ehRespostaAUltima: iUltima !== null && iUltima.tipo !== "sim" && iUltima.tipo !== "nao" && iUltima.tipo !== "ok",
      ehDica: pareceDica(texto),
      ehNaoEntendida: ativa !== null && interp === null && respostaNaoEntendida(texto),
    }).destino;
  } catch {
    await despachar(p.tipo === "audio" && texto !== p.texto ? texto : undefined);
    return "assistente";
  }

  const chamar = async (corpo: Record<string, unknown>) => {
    try {
      return await deps.chamarComprovantes(corpo);
    } catch {
      return { status: 0 } as { status: number; tratada?: boolean };
    }
  };

  switch (destino) {
    case "comprovante":
    case "comprovante_reabrir":
    case "comando":
    case "dica":
    case "foto_do_cmp":
    case "nao_entendi": {
      const r = await chamar({ acao: "responder", message_id: p.msgId, phone: p.phone, texto, citado: p.citado, destino });
      if ((r.status === 200 && r.tratada === false) || r.status === 422) {
        await despacharAoAssistente(texto);
        return "assistente";
      }
      if (r.status >= 500) await avisar();
      return destino;
    }
    case "pendentes":
      await chamar({ acao: "pendentes", message_id: p.msgId, phone: p.phone });
      await despacharAoAssistente(texto);
      return "pendentes";
    case "ambiguo": {
      const r = await chamar({ acao: "desempatar", message_id: p.msgId, phone: p.phone, citado: p.citado });
      if (r.status >= 500) await avisar();
      return "ambiguo";
    }
    default:
      await despacharAoAssistente(texto);
      return "assistente";
  }
}

/** POST comprovantes-whatsapp com a chave de serviço (porta chamadaInterna); { status, tratada }. */
export async function chamarComprovantesPorHttp(
  corpo: Record<string, unknown>,
  opts: { url: string; chave: string; fetch?: typeof fetch; timeoutMs?: number },
): Promise<{ status: number; tratada?: boolean }> {
  try {
    const res = await (opts.fetch ?? fetch)(`${opts.url}/functions/v1/comprovantes-whatsapp`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${opts.chave}` },
      body: JSON.stringify(corpo),
      signal: AbortSignal.timeout(opts.timeoutMs ?? PRAZO_DO_RECEBER_MS),
    });
    const resposta = await res.json().catch(() => null) as { tratada?: unknown } | null;
    return { status: res.status, tratada: typeof resposta?.tratada === "boolean" ? resposta.tratada : undefined };
  } catch {
    return { status: 0 };
  }
}

/** O aviso de falha ao dono, pelo whatsapp-send (context comprovante, uma vez por mensagem). */
export async function avisarFalhaPorHttp(
  p: { phone: string; msgId: string },
  opts: { url: string; chave: string; fetch?: typeof fetch },
): Promise<void> {
  try {
    const res = await (opts.fetch ?? fetch)(`${opts.url}/functions/v1/whatsapp-send`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${opts.chave}` },
      body: JSON.stringify({ phone: p.phone, kind: "text", message: TEXTO_FALHA, context: "comprovante", dedupe_key: `cmp:f:${p.msgId}` }),
      signal: AbortSignal.timeout(PRAZO_DO_RECEBER_MS),
    });
    await res.body?.cancel().catch(() => {});
  } catch {
    /* sem aviso */
  }
}
