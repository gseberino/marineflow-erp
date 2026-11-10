// Retorno rápido, F4 (P11.1): a camada determinística do parceiro, antes da camada do retorno (F2) no ai-agent.
//
// Duas coisas, nesta ordem:
//  1. as palavras próprias (comandos.ts): *parceiro* abre ou reapresenta o cartão (parceiro_cartao_abrir), *parceiro 74*
//     abre um item de uma OS (parceiro_cartao_abrir_os), e *N tira L* / *N sabe L* vão a parceiro_decidir_dito, só com o
//     cartão do parceiro vivo;
//  2. com o cartão do parceiro vivo e sem o da F2 vivo, as palavras de cartão do leitor da F2 (escolher, so, sem, tirar,
//     ver, resolvido) vão a parceiro_decidir_dito. Sem cartão do parceiro, null, e o texto segue à camada do retorno.
//
// Só o dono. O PIN nunca vai ao banco por aqui: a RPC recebe o comando sem ele, e quem confere é o caminho único do
// *sim <PIN>* (deps.confirmar, o mesmo resolveWhatsAppConfirmation da F2), com as mesmas tentativas.
//
// O histórico do assistente não recebe nada daqui: o par da conversa do cartão é gravado pelo SQL, só com a contagem
// (_parceiro_cartao_viver), e o texto do cartão pode ter trecho do parceiro.
//
// Falha fecha: erro de RPC responde R15 e nada vai ao modelo, porque o texto pode levar PIN. Só a função ausente (o ai-agent
// subindo antes das migrations) devolve null, e o texto segue como sempre. *parceiro* com o parceiro desligado
// (parceiro_cartao_abrir devolve vazio sem texto) também segue como hoje: a palavra não existia antes da F4.
//
// Fora de _shared/ai/ de propósito: isolamento_test.ts varre esta pasta. Tudo chega por parâmetro.
//
// Reverter: tirar a chamada de camadaDoParceiro do ai-agent e a marca do webhook (ehPalavraDoParceiroLigada).

import { type ComandoDoRetorno, ehComandoDeCartao, lerComandoDoRetorno } from "../retorno/comandos.ts";
import type { RespostaDaCamada, RespostaDaRpc } from "../retorno/camada.ts";
import { type ComandoDoParceiro, lerComandoDoParceiro } from "./comandos.ts";

export interface CartaoDoParceiroVivo {
  id: string;
  estado: string;
  pendencia_id: string | null;
  letras: Record<string, string[]>;
}

export interface DependenciasDoParceiro {
  /** O usuário do turno: vai como p_autor só às RPCs cuja assinatura o tem. */
  autor: string;
  ehDoDono: () => Promise<boolean>;
  /** A RPC como ela é (sem acrescentar p_autor: parceiro_cartao_abrir não o tem). */
  rpc: (fn: string, args: Record<string, unknown>) => Promise<RespostaDaRpc>;
  /** parceiro_cartao_vivo(). Erro sobe como exceção com `code`. */
  cartaoVivo: () => Promise<CartaoDoParceiroVivo | null>;
  /** retorno_cartao_vivo() não nulo. Erro sobe como exceção com `code`. */
  cartaoDoRetornoVivo: () => Promise<boolean>;
  /** metadata.pending_confirm_action_id, lido de novo. */
  ponteiro: () => Promise<string | null>;
  /** O título da pendência do ponteiro. */
  tituloDoPonteiro: () => Promise<string | null>;
  /** Delega à confirmação de sempre, a mesma de *sim <PIN>*. */
  confirmar: (pin: string) => Promise<void>;
}

export const R15_PARCEIRO = "Não consegui agora; tente de novo em instantes.";

/** A letra que o item não tem, dita com o PIN: nada é confirmado, e nenhuma tentativa é gasta. */
export function p14(n: number, letra: string): string {
  return `O ${n} não tem a opção ${letra}, e nada foi feito.`;
}

/** O ponteiro está em outra pendência: o *sim <PIN>* seguinte aprovaria o pedido errado. */
export function P13(titulo: string): string {
  return `Antes deste cartão há outro pedido aberto: *${titulo}*. Responda a ele (*sim <PIN>* ou *não*) e mande *parceiro*.`;
}

/** As palavras de cartão do leitor da F2 que o cartão do parceiro entende (parceiro_decidir_dito). */
const DO_CARTAO: ReadonlySet<string> = new Set(["escolher", "so", "sem", "tirar", "ver", "resolvido"]);

function funcaoAusente(e: unknown): boolean {
  const code = (e as { code?: string } | null)?.code;
  return code === "PGRST202" || code === "42883";
}

function semPin(c: ComandoDoRetorno): Record<string, unknown> {
  const { pin: _pin, ...resto } = c as ComandoDoRetorno & { pin?: string | null };
  return resto;
}

function falha(comando: string, texto: string): RespostaDaCamada {
  return { comando, texto, noHistorico: null };
}

async function doDono(deps: DependenciasDoParceiro): Promise<boolean> {
  try {
    return (await deps.ehDoDono()) === true;
  } catch {
    return false;
  }
}

type LidoDaRpc = { r: Record<string, unknown> } | { saida: RespostaDaCamada | null };

/** Chama a RPC: função ausente → null (segue como sempre); erro → R15. */
async function chamar(deps: DependenciasDoParceiro, comando: string, fn: string, args: Record<string, unknown>): Promise<LidoDaRpc> {
  let resposta: RespostaDaRpc;
  try {
    resposta = await deps.rpc(fn, args);
  } catch {
    return { saida: falha(comando, R15_PARCEIRO) };
  }
  if (resposta.error) return { saida: funcaoAusente(resposta.error) ? null : falha(comando, R15_PARCEIRO) };
  return { r: (resposta.data ?? {}) as Record<string, unknown> };
}

/** Lê o cartão vivo do parceiro: função ausente → "ausente"; erro → "erro". */
async function lerCartao(deps: DependenciasDoParceiro): Promise<CartaoDoParceiroVivo | null | "ausente" | "erro"> {
  try {
    return await deps.cartaoVivo();
  } catch (e) {
    return funcaoAusente(e) ? "ausente" : "erro";
  }
}

/**
 * Depois da RPC do cartão: com o PIN (ou com a escolha que pede PIN) e o ponteiro em outra pendência, nada de confirmar;
 * com o PIN e o ponteiro no cartão, o caminho único da confirmação.
 */
async function comPin(
  saida: RespostaDaCamada,
  pin: string | null,
  precisaPin: boolean,
  vivo: CartaoDoParceiroVivo,
  deps: DependenciasDoParceiro,
): Promise<RespostaDaCamada> {
  if (!pin && !precisaPin) return saida;
  let ponteiro: string | null;
  try {
    ponteiro = await deps.ponteiro();
  } catch {
    return falha(saida.comando, R15_PARCEIRO);
  }
  if (ponteiro !== vivo.pendencia_id) {
    let titulo: string | null = null;
    try {
      titulo = await deps.tituloDoPonteiro();
    } catch {
      titulo = null;
    }
    return { ...saida, texto: P13(titulo ?? "ação pendente") };
  }
  if (!pin) return saida;
  try {
    await deps.confirmar(pin);
  } catch {
    return falha(saida.comando, R15_PARCEIRO);
  }
  return { comando: saida.comando, texto: "", noHistorico: null, jaEnviado: true };
}

/** O texto que a RPC devolveu, ou R15. seguir_ao_modelo e nao_e_o_dono = null. */
function textoDe(comando: string, r: Record<string, unknown>): RespostaDaCamada | null {
  if (r.seguir_ao_modelo === true || r.motivo === "nao_e_o_dono") return null;
  if (typeof r.texto !== "string" || !r.texto) return falha(comando, R15_PARCEIRO);
  return {
    comando,
    texto: r.texto,
    noHistorico: null,
    ...(typeof r.cartao_id === "string" && r.cartao_id ? { cartaoId: r.cartao_id } : {}),
  };
}

async function palavraDoParceiro(c: ComandoDoParceiro, deps: DependenciasDoParceiro): Promise<RespostaDaCamada | null> {
  if (!(await doDono(deps))) return null;

  if (c.comando === "parceiro") {
    const lido = await chamar(deps, c.comando, "parceiro_cartao_abrir", { p_gatilho: "puxar" });
    if ("saida" in lido) return lido.saida;
    // vazio sem texto: parceiro desligado (ou sem dono no banco). A palavra não existia antes da F4: segue como sempre.
    if (lido.r.acao === "vazio" && (typeof lido.r.texto !== "string" || !lido.r.texto)) return null;
    return textoDe(c.comando, lido.r);
  }

  if (c.comando === "parceiro_os") {
    const lido = await chamar(deps, c.comando, "parceiro_cartao_abrir_os", { p_sigla: c.sigla, p_numero: c.numero, p_autor: deps.autor });
    if ("saida" in lido) return lido.saida;
    return textoDe(c.comando, lido.r);
  }

  // *N tira L* e *N sabe L*: só com o cartão do parceiro vivo
  const vivo = await lerCartao(deps);
  if (vivo === "erro") return falha(c.comando, R15_PARCEIRO);
  if (vivo === "ausente" || vivo === null) return null;
  const lido = await chamar(deps, c.comando, "parceiro_decidir_dito", { p_comando: { ...c }, p_autor: deps.autor });
  if ("saida" in lido) return lido.saida;
  const saida = textoDe(c.comando, lido.r);
  if (!saida) return null;
  return await comPin(saida, null, lido.r.precisa_pin === true, vivo, deps);
}

export async function camadaDoParceiro(texto: string, deps: DependenciasDoParceiro): Promise<RespostaDaCamada | null> {
  const proprio = lerComandoDoParceiro(texto);
  if (proprio) return await palavraDoParceiro(proprio, deps);

  const comando = lerComandoDoRetorno(texto);
  if (!comando || !ehComandoDeCartao(comando) || !DO_CARTAO.has(comando.comando)) return null;
  // "3 c dia 14": a data é da F2 (o dia da visita); no cartão do parceiro não há letra com texto
  if (comando.comando === "escolher" && comando.resto !== null) return null;
  if (!(await doDono(deps))) return null;

  const pin = "pin" in comando ? comando.pin : null;
  const vivo = await lerCartao(deps);
  if (vivo === "erro") return falha(comando.comando, R15_PARCEIRO);
  if (vivo === "ausente" || vivo === null) return null;
  // Os dois cartões nunca vivem juntos (P8). Se viverem, o leitor da F2 é dele.
  try {
    if (await deps.cartaoDoRetornoVivo()) return null;
  } catch (e) {
    if (!funcaoAusente(e)) return falha(comando.comando, R15_PARCEIRO);
  }

  if (comando.comando === "escolher" && pin && !(vivo.letras[String(comando.n)] ?? []).includes(comando.letra)) {
    return falha(comando.comando, p14(comando.n, comando.letra));
  }

  const lido = await chamar(deps, comando.comando, "parceiro_decidir_dito", { p_comando: semPin(comando), p_autor: deps.autor });
  if ("saida" in lido) return lido.saida;
  const saida = textoDe(comando.comando, lido.r);
  if (!saida) return null;
  return await comPin(saida, pin, lido.r.precisa_pin === true, vivo, deps);
}

/**
 * A palavra do parceiro, para o webhook não deixar o CMP aberto engoli-la. Verdadeiro em dois casos: (a) *parceiro* e
 * *parceiro 74*, com ou sem cartão, e *N tira L* / *N sabe L* com o cartão do parceiro vivo; (b) as palavras de cartão do
 * leitor da F2 (1 A, só 2, não 2, ver 1, resolvido 1) com o cartão do parceiro vivo. *segura pátio* e *solta pátio* já
 * passam pela marca da F2. Nunca lança; erro ou função ausente = false.
 */
export async function ehPalavraDoParceiroLigada(
  // deno-lint-ignore no-explicit-any
  admin: any,
  texto: string,
): Promise<boolean> {
  try {
    const proprio = lerComandoDoParceiro(texto);
    const doRetorno = proprio ? null : lerComandoDoRetorno(texto);
    if (!proprio && !(doRetorno && ehComandoDeCartao(doRetorno))) return false;
    const { data, error } = await admin.rpc("parceiro_cartao_vivo");
    if (error) return false;
    const vivo = data !== null && data !== undefined;
    if (proprio) return proprio.comando === "parceiro" || proprio.comando === "parceiro_os" || vivo;
    return vivo;
  } catch {
    return false;
  }
}
