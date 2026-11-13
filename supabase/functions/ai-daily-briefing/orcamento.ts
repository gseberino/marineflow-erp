// O orçamento enviado no fechamento das 17:30 (retorno rápido, F5, P10.2). Spec: retorno-rapido/f5/spec.md, P10.2, C-FECH-O e
// C-AVISO-O. Molde: parceiro.ts (F4).
//
// O fechamento PEDE, não abre: nenhuma linha cria cartão, nenhuma RPC de envio. Tudo o que é dado vem do banco
// (orcamento_resumo_fechamento: o 1º nome do cadastro e o número do orçamento, nunca telefone nem documento). Aqui só se
// confere a forma: a linha que traz telefone, documento (8 dígitos ou mais, com ou sem separador) ou e-mail sai (falha
// fecha), e o resto vai como veio.
//
//   fixas  — "Orçamentos: amanhã sai sozinho o lembrete do ORÇ-00151 (Ana) · *segura 151*": entra logo depois do "Mandei
//            sozinho" e não sai em nenhum corte da tarde (secretario-tarde-texto.ts). Os passos dela vêm em `avisar`.
//   linhas — as outras (amanhã esperam o *sim*, encerrados, o "Fechado" que não saiu, os vencidos sem desfecho): extras do
//            fechamento (fixa = false), as primeiras a sair quando a tarde não cabe.
//   avisar — os passos da linha fixa. Só viram "avisados" (orcamento_avisados) depois de a tarde com CADA linha fixa ir à
//            fila, com o id da linha da fila; quem decide se o passo sai sozinho é o vigia, no dia seguinte, pela fila em
//            'sent'. Sem isso, o passo vai ao cartão (falha fecha).
//   naoSaiu — (revisão das ondas 4 a 9, achados banco-2, seguranca-1 e edge-fechamento) o aceite e a linha exata de cada
//            aviso do "Fechado" (ou do pedido de dados) que não saiu. A leitura não grava nada; o aviso só sai da lista do
//            cartão (orcamento_nao_saiu_avisados) depois de a tarde com AQUELA linha ir à fila, com o id da linha da fila. A
//            tarde que descartou a linha (a revisão, o corte das extras, a tentativa que falhou) não marca, e o aviso volta.
//
// Uma fixa com forma errada, ou fixas sem passo, ou passo sem fixa: nenhuma fixa e nenhum aviso (a linha diria "sai sozinho"
// e nada seria marcado, ou o passo seria marcado sem o dono ler).
//
// Falha fecha: erro, função ausente (antes do deploy da F5) ou forma inesperada = null, e a tarde sai como antes, sem aviso,
// e nada sai sozinho. O erro (fora a função ausente) vai a app_error_logs (ai-daily-briefing, orcamento:fechamento). Nunca
// lança. Não importa nada de _shared/ai/.
//
// Reverter: tirar as chamadas a lerOrcamento e a avisarOrcamentoNaTarde de secretario-tarde.ts (os campos opcionais somem
// sozinhos).

import { logEdgeError } from "../_shared/log-error.ts";
import { chaveDaFilaDaTarde, idDaFilaPelaChave } from "../_shared/uma-voz/guardado.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

/** O aviso do que não saiu: o aceite e a linha exata que o fechamento mostra (uma das `linhas`). */
export interface AvisoNaoSaiu {
  aceite: string;
  linha: string;
}

export interface OrcamentoDoFechamento {
  fixas: string[];
  linhas: string[];
  avisar: string[];
  /** os avisos do que não saiu entre as `linhas` (ausente ou torto na resposta = [], e nada é marcado; lerOrcamento sempre o põe) */
  naoSaiu?: AvisoNaoSaiu[];
}

/** Quantas linhas do orçamento cabem no fechamento (o banco devolve no máximo 4; são extras: as primeiras a sair). */
export const LINHAS_MAX_DO_ORCAMENTO = 4;
const LINHA_MAX = 300;
/** A fixa tem até 3 orçamentos (cerca de 120 caracteres cada um no máximo, com o "e mais N"). */
const FIXA_MAX = 400;

const FUNCAO_AUSENTE = new Set(["PGRST202", "42883"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Telefone ou documento (8 dígitos ou mais, com ou sem separador) ou e-mail: a linha não sai. */
function temDadoPessoal(l: string): boolean {
  return /\d(?:[\s().-]*\d){7,}/.test(l) || /\S@\S/.test(l);
}

function linhaBoa(l: unknown, max: number): l is string {
  return typeof l === "string" && l.trim() !== "" && !l.includes("\n") && l.trim().length <= max && !temDadoPessoal(l);
}

/** A lista do campo: nulo/ausente = []; outra coisa que não lista = forma inesperada (undefined). */
function lista(v: unknown): unknown[] | undefined {
  if (v === null || v === undefined) return [];
  return Array.isArray(v) ? v : undefined;
}

function formaDe(data: unknown): OrcamentoDoFechamento | null {
  if (data === null || data === undefined || typeof data !== "object" || Array.isArray(data)) return null;
  const d = data as { fixas?: unknown; linhas?: unknown; avisar?: unknown; nao_saiu?: unknown };
  const fixas = lista(d.fixas);
  const linhas = lista(d.linhas);
  const avisar = lista(d.avisar);
  if (!fixas || !linhas || !avisar) return null;

  const linhasBoas = linhas
    .filter((l) => linhaBoa(l, LINHA_MAX))
    .map((l) => (l as string).trim())
    .slice(0, LINHAS_MAX_DO_ORCAMENTO);
  const naoSaiu = avisosNaoSaiu(d.nao_saiu, linhasBoas);

  // A fixa e os passos dela andam juntos: qualquer defeito em um derruba os dois.
  const fixasBoas = fixas.every((f) => linhaBoa(f, FIXA_MAX));
  const avisarBom = avisar.every((p) => typeof p === "string" && UUID.test(p));
  if (!fixasBoas || !avisarBom || fixas.length === 0 || avisar.length === 0) {
    return { fixas: [], linhas: linhasBoas, avisar: [], naoSaiu };
  }
  return { fixas: fixas.map((f) => (f as string).trim()), linhas: linhasBoas, avisar: avisar as string[], naoSaiu };
}

/**
 * Os avisos do que não saiu que a tarde pode marcar: o aceite (uuid) e a linha, que tem de ser uma das linhas boas (a que a
 * tarde mostra). Qualquer outra forma = de fora (falha fecha: o aviso fica no cartão e volta no próximo fechamento).
 */
function avisosNaoSaiu(v: unknown, linhasBoas: string[]): AvisoNaoSaiu[] {
  if (!Array.isArray(v)) return [];
  const out: AvisoNaoSaiu[] = [];
  for (const x of v) {
    if (x === null || typeof x !== "object" || Array.isArray(x)) continue;
    const { aceite, linha } = x as { aceite?: unknown; linha?: unknown };
    if (typeof aceite !== "string" || !UUID.test(aceite) || typeof linha !== "string") continue;
    const l = linha.trim();
    if (linhasBoas.includes(l)) out.push({ aceite, linha: l });
  }
  return out;
}

function codigoDe(e: unknown): string {
  return String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro");
}

/**
 * orcamento_resumo_fechamento(p_agora) — contrato C-FECH-O. {fixas, linhas, avisar, naoSaiu} já conferidos; listas vazias =
 * nada do orçamento hoje; null = erro, função ausente ou forma inesperada (a tarde de antes). Nunca lança.
 *
 * A função só lê (revisão das ondas 4 a 9): antes ela gravava resultado.nao_saiu_fechado_em ao devolver a linha do aviso, e
 * a linha que a tarde descartava (a revisão, o corte das extras) sumia do cartão sem chegar ao dono. A marca agora é de
 * avisarNaoSaiuNaTarde, depois do envio.
 */
export async function lerOrcamento(admin: Admin, agora: Date): Promise<OrcamentoDoFechamento | null> {
  try {
    const { data, error } = await admin.rpc("orcamento_resumo_fechamento", { p_agora: agora.toISOString() });
    if (error) throw error;
    const lido = formaDe(data);
    // nulo é "nada a dizer" (como em lerParceiro); só a forma errada vai a app_error_logs
    if (lido === null && data != null) {
      console.warn(JSON.stringify({ fn: "ai-daily-briefing", orcamento: "forma_inesperada" }));
      await logEdgeError(admin, {
        context: "ai-daily-briefing",
        action: "orcamento:fechamento",
        message: "orcamento: orcamento_resumo_fechamento devolveu uma forma inesperada; as linhas do orçamento ficaram de fora",
        details: { codigo: "forma_inesperada" },
      });
    }
    return lido;
  } catch (e) {
    const codigo = codigoDe(e);
    console.warn(JSON.stringify({ fn: "ai-daily-briefing", orcamento: "leitura_falhou", codigo }));
    if (!FUNCAO_AUSENTE.has(codigo)) {
      await logEdgeError(admin, {
        context: "ai-daily-briefing",
        action: "orcamento:fechamento",
        message: `orcamento: a leitura de orcamento_resumo_fechamento falhou: ${String((e as { message?: unknown })?.message ?? codigo).slice(0, 300)}`,
        details: { codigo },
        error: e,
      });
    }
    return null;
  }
}

export type AvisoDoOrcamento = "avisado" | "nada" | "sem_linha" | "sem_fila" | "erro";

/**
 * C-AVISO-O: depois de a tarde com a linha fixa ir à fila (quem chama confere r.novo && r.enviado), grava o aviso nos
 * passos: só se o texto enviado tem CADA linha fixa e só com o id da linha da fila da tarde (secretario_tarde:<dia>:<tel>).
 * Sem o id, não chama (o passo vai ao cartão). Erro = app_error_logs (sem telefone) e o passo vai ao cartão. Nunca lança.
 */
export async function avisarOrcamentoNaTarde(admin: Admin, p: {
  texto: string | null;
  fixas: string[];
  avisar: string[];
  hoje: string;
  phone: string;
  agora: Date;
}): Promise<AvisoDoOrcamento> {
  if (p.fixas.length === 0 || p.avisar.length === 0) return "nada";
  const texto = p.texto ?? "";
  if (!p.fixas.every((f) => texto.includes(f))) return "sem_linha";
  try {
    const fila = await idDaFilaPelaChave(admin, chaveDaFilaDaTarde(p.hoje, p.phone));
    if (!fila) return "sem_fila";
    const { error } = await admin.rpc("orcamento_avisados", { p_passos: p.avisar, p_fila: fila, p_agora: p.agora.toISOString() });
    if (error) throw error;
    return "avisado";
  } catch (e) {
    const codigo = codigoDe(e);
    console.warn(JSON.stringify({ fn: "ai-daily-briefing", orcamento: "aviso_falhou", codigo }));
    await logEdgeError(admin, {
      context: "ai-daily-briefing",
      action: "orcamento:avisados",
      message: `orcamento: orcamento_avisados falhou; os passos de amanhã vão ao cartão: ${String((e as { message?: unknown })?.message ?? codigo).slice(0, 300)}`,
      details: { codigo, passos: p.avisar.length },
      error: e,
    });
    return "erro";
  }
}

/**
 * (Revisão das ondas 4 a 9, achados banco-2, seguranca-1 e edge-fechamento) Depois de a tarde ir à fila (quem chama confere
 * r.novo && r.enviado), marca como mostrado o aviso do que não saiu: só os aceites cuja linha o texto enviado tem, e só com o
 * id da linha da fila da tarde (orcamento_nao_saiu_avisados). A linha que a tarde descartou (a revisão, o corte das extras)
 * não marca: o aviso fica no cartão e volta no próximo fechamento. Sem o id da fila, não chama. Erro = app_error_logs (sem
 * telefone), e o aviso também fica. Nunca lança.
 */
export async function avisarNaoSaiuNaTarde(admin: Admin, p: {
  texto: string | null;
  naoSaiu: AvisoNaoSaiu[];
  hoje: string;
  phone: string;
  agora: Date;
}): Promise<AvisoDoOrcamento> {
  if (p.naoSaiu.length === 0) return "nada";
  const texto = p.texto ?? "";
  const aceites = [...new Set(p.naoSaiu.filter((n) => texto.includes(n.linha)).map((n) => n.aceite))];
  if (aceites.length === 0) return "sem_linha";
  try {
    const fila = await idDaFilaPelaChave(admin, chaveDaFilaDaTarde(p.hoje, p.phone));
    if (!fila) return "sem_fila";
    const { error } = await admin.rpc("orcamento_nao_saiu_avisados", { p_aceites: aceites, p_fila: fila, p_agora: p.agora.toISOString() });
    if (error) throw error;
    return "avisado";
  } catch (e) {
    const codigo = codigoDe(e);
    console.warn(JSON.stringify({ fn: "ai-daily-briefing", orcamento: "nao_saiu_falhou", codigo }));
    await logEdgeError(admin, {
      context: "ai-daily-briefing",
      action: "orcamento:nao_saiu_avisados",
      message: `orcamento: orcamento_nao_saiu_avisados falhou; o aviso do que não saiu fica no cartão: ${String((e as { message?: unknown })?.message ?? codigo).slice(0, 300)}`,
      details: { codigo, aceites: aceites.length },
      error: e,
    });
    return "erro";
  }
}
