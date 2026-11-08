// Retorno rápido, F2 (P3): a camada determinística do retorno, antes da trava do comprovante e da confirmação.
//
// Por que antes: "não 2" rejeitaria o cartão inteiro, e "1 A sim <PIN>" levaria o PIN ao modelo.
//
// A camada nunca grava a metadata da sessão: quem mexe no ponteiro é o SQL, por merge, ou a confirmação de sempre. E o PIN
// nunca vai ao banco por aqui: a RPC recebe o comando sem ele, e quem confere é o caminho único do *sim <PIN>* (deps.confirmar),
// com as mesmas tentativas e a mesma rejeição na 3ª.
//
// Falha fecha: erro de RPC responde R15 e nada vai ao modelo, porque o texto pode levar PIN. Só a função ausente (o ai-agent
// subindo antes das migrations) devolve null, e o texto segue como sempre.
//
// Fora de _shared/ai/ de propósito: isolamento_test.ts varre esta pasta. `ehConfirmacao` vem como parâmetro por isso.
//
// Reverter: tirar a chamada de handleWhatsAppTurn e a marca do webhook.

import { ehComandoDeCartao, lerComandoDoRetorno, type ComandoDoRetorno } from "./comandos.ts";

export interface CartaoVivo {
  id: string;
  estado: "vivo" | "lista";
  pendencia_id: string | null;
  letras: Record<string, string[]>;
}

export type RespostaDaRpc = { data: unknown; error: { code?: string } | null };

export interface DependenciasDaCamada {
  ehDoDono: () => Promise<boolean>;
  rpc: (fn: string, args: Record<string, unknown>) => Promise<RespostaDaRpc>;
  /** retorno_cartao_vivo(). Erro sobe como exceção com `code`. */
  cartaoVivo: () => Promise<CartaoVivo | null>;
  /** metadata.pending_confirm_action_id, lido de novo. */
  ponteiro: () => Promise<string | null>;
  /** O título da pendência do ponteiro. */
  tituloDoPonteiro: () => Promise<string | null>;
  /** Delega à confirmação de sempre, a mesma de *sim <PIN>*. */
  confirmar: (pin: string) => Promise<void>;
}

export interface RespostaDaCamada {
  comando: string;
  texto: string;
  /** Nunca com texto do cliente nem PIN; null = nada na conversa. */
  noHistorico: { user: string; assistant: string } | null;
  cartaoId?: string;
  jaEnviado?: boolean;
}

export const R13 = "Esse cartão já não existe, e nada foi feito. Mande *retorno* para ver quem espera.";
export const R15 = "Não consegui agora; tente de novo em instantes.";
export const SO_CONSULTA = "Esta lista é só para consulta. Mande *retorno* quando o pedido aberto terminar.";
export const DITADO_LONGO = "Ditado longo demais: até 1.000 caracteres.";
export const TEXTO_MAX_DITADO = 1000;

export function r14(n: number, letra: string): string {
  return `O caso ${n} não tem a opção ${letra}, e nada foi feito.`;
}

export function c13(titulo: string): string {
  return `Antes deste cartão há outro pedido aberto: *${titulo}*. Responda a ele (*sim <PIN>* ou *não*) e mande *retorno*.`;
}

/** Função que ainda não existe no banco: o ai-agent pode subir antes das migrations. */
function funcaoAusente(e: unknown): boolean {
  const code = (e as { code?: string } | null)?.code;
  return code === "PGRST202" || code === "42883";
}

/** O comando como ele vai ao banco: sem o PIN, que nunca sai deste processo por aqui. */
function semPin(c: ComandoDoRetorno): Record<string, unknown> {
  const { pin: _pin, ...resto } = c as ComandoDoRetorno & { pin?: string | null };
  return resto;
}

function pinDe(c: ComandoDoRetorno): string | null {
  return "pin" in c ? c.pin : null;
}

function falha(comando: string, texto: string): RespostaDaCamada {
  return { comando, texto, noHistorico: null };
}

export async function camadaDoRetorno(texto: string, deps: DependenciasDaCamada): Promise<RespostaDaCamada | null> {
  const comando = lerComandoDoRetorno(texto);
  if (!comando) return null;

  let dono = false;
  try {
    dono = (await deps.ehDoDono()) === true;
  } catch {
    dono = false;
  }
  if (!dono) return null;

  const pin = pinDe(comando);
  let vivo: CartaoVivo | null = null;

  if (ehComandoDeCartao(comando)) {
    try {
      vivo = await deps.cartaoVivo();
    } catch (e) {
      if (funcaoAusente(e)) return null;
      return falha(comando.comando, R15);
    }
    if (!vivo) return pin ? falha(comando.comando, R13) : null;

    if (comando.comando === "escolher" && !(vivo.letras[String(comando.n)] ?? []).includes(comando.letra)) {
      return pin ? falha(comando.comando, r14(comando.n, comando.letra)) : null;
    }
    if (vivo.estado === "lista" && comando.comando !== "ver" && comando.comando !== "pessoal" && comando.comando !== "resolvido") {
      return falha(comando.comando, SO_CONSULTA);
    }
    if (comando.comando === "ditar" && comando.texto.length > TEXTO_MAX_DITADO) {
      return falha(comando.comando, DITADO_LONGO);
    }
  }

  const naPalavra = !ehComandoDeCartao(comando) || comando.comando === "ver" || comando.comando === "pessoal" ||
    comando.comando === "resolvido";
  const rpc = naPalavra ? "retorno_dito" : "retorno_decidir_dito";
  let resposta: RespostaDaRpc;
  try {
    resposta = await deps.rpc(rpc, { p_comando: semPin(comando) });
  } catch {
    return falha(comando.comando, R15);
  }
  if (resposta.error) {
    return funcaoAusente(resposta.error) ? null : falha(comando.comando, R15);
  }

  const r = (resposta.data ?? {}) as {
    ok?: boolean;
    texto?: string;
    historico?: { user: string; assistant: string } | null;
    cartao_id?: string | null;
    seguir_ao_modelo?: boolean;
    precisa_pin?: boolean;
    motivo?: string;
  };
  if (r.seguir_ao_modelo || r.motivo === "nao_e_o_dono") return null;
  if (typeof r.texto !== "string" || !r.texto) return falha(comando.comando, R15);

  const saida: RespostaDaCamada = {
    comando: comando.comando,
    texto: r.texto,
    noHistorico: r.historico ?? null,
    ...(r.cartao_id ? { cartaoId: r.cartao_id } : {}),
  };

  // Com o ponteiro em outra pendência, o *sim <PIN>* seguinte aprovaria o pedido errado: nada de confirmar, nenhuma
  // tentativa gasta, e a seleção fica.
  if ((pin || r.precisa_pin) && vivo) {
    let ponteiro: string | null;
    try {
      ponteiro = await deps.ponteiro();
    } catch {
      return falha(comando.comando, R15);
    }
    if (ponteiro !== vivo.pendencia_id) {
      let titulo: string | null = null;
      try {
        titulo = await deps.tituloDoPonteiro();
      } catch {
        titulo = null;
      }
      return { ...saida, texto: c13(titulo ?? "ação pendente") };
    }
    if (pin) {
      try {
        await deps.confirmar(pin);
      } catch {
        return falha(comando.comando, R15);
      }
      return { comando: comando.comando, texto: "", noHistorico: null, jaEnviado: true };
    }
  }
  return saida;
}

/**
 * Cobre o turno concorrente que regravou a metadata inteira e apagou o ponteiro: com cartão vivo e ponteiro vazio, se o
 * texto é confirmação, devolve a metadata com o ponteiro reposto. Ponteiro de outra pendência nunca é trocado.
 */
export async function ponteiroDoCartao(
  texto: string,
  metadata: Record<string, unknown>,
  deps: DependenciasDaCamada,
  ehConfirmacao: (t: string) => boolean,
): Promise<Record<string, unknown> | null> {
  if (metadata.pending_confirm_action_id || !ehConfirmacao(texto)) return null;
  try {
    if ((await deps.ehDoDono()) !== true) return null;
    const vivo = await deps.cartaoVivo();
    if (vivo?.estado !== "vivo" || !vivo.pendencia_id) return null;
    return { ...metadata, pending_confirm_action_id: vivo.pendencia_id, pin_attempts: 0, pendencia_herdada: false };
  } catch {
    return null;
  }
}

/**
 * A palavra do retorno, para o webhook não deixar o CMP aberto engoli-la. A de cartão só conta com cartão vivo: "1 b" sem
 * cartão segue o caminho de hoje. Nunca lança; erro = false.
 */
export async function ehPalavraDoRetornoLigada(
  // deno-lint-ignore no-explicit-any
  admin: any,
  texto: string,
): Promise<boolean> {
  try {
    const comando = lerComandoDoRetorno(texto);
    if (!comando) return false;
    const { data, error } = await admin.rpc("retorno_cartao_vivo");
    if (error) return false;
    return !ehComandoDeCartao(comando) || data !== null;
  } catch {
    return false;
  }
}
