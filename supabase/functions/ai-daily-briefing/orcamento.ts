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

export interface OrcamentoDoFechamento {
  fixas: string[];
  linhas: string[];
  avisar: string[];
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
  const d = data as { fixas?: unknown; linhas?: unknown; avisar?: unknown };
  const fixas = lista(d.fixas);
  const linhas = lista(d.linhas);
  const avisar = lista(d.avisar);
  if (!fixas || !linhas || !avisar) return null;

  const linhasBoas = linhas
    .filter((l) => linhaBoa(l, LINHA_MAX))
    .map((l) => (l as string).trim())
    .slice(0, LINHAS_MAX_DO_ORCAMENTO);

  // A fixa e os passos dela andam juntos: qualquer defeito em um derruba os dois.
  const fixasBoas = fixas.every((f) => linhaBoa(f, FIXA_MAX));
  const avisarBom = avisar.every((p) => typeof p === "string" && UUID.test(p));
  if (!fixasBoas || !avisarBom || fixas.length === 0 || avisar.length === 0) {
    return { fixas: [], linhas: linhasBoas, avisar: [] };
  }
  return { fixas: fixas.map((f) => (f as string).trim()), linhas: linhasBoas, avisar: avisar as string[] };
}

function codigoDe(e: unknown): string {
  return String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro");
}

/**
 * orcamento_resumo_fechamento(p_agora) — contrato C-FECH-O. {fixas, linhas, avisar} já conferidos; listas vazias = nada do
 * orçamento hoje; null = erro, função ausente ou forma inesperada (a tarde de antes). Nunca lança.
 *
 * ATENÇÃO (contrato da P8): a função grava resultado.nao_saiu_fechado_em nos aceites cuja linha ela devolve (o aviso do
 * "Fechado" que não saiu aparece uma vez). Por isso quem chama chama uma vez por tarde, e só na tarde que vai ao dono.
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
