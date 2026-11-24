// O que o BANCO diz do cartão de crédito (24/11/2026): o saldo da conta de crédito, o vencimento, o mínimo, o limite e
// as faturas emitidas. A sincronização trazia só as compras; quanto falta pagar e quando vence nunca foram guardados, e
// a fila de pagamentos da semana não tem de onde tirar a fatura sem inventar a data.
//
// Aqui só se GUARDA (tabelas cartao_posicoes e cartao_faturas_do_banco, migration 20270225100000). Nada mostra estes
// números ao dono ainda: primeiro se confere no dado real o que cada banco preenche e o que cada número quer dizer.
//
// Nunca derruba a sincronização (todo erro é engolido aqui) e não a segura: a leitura das faturas tem prazo próprio em
// `fetchBills` (pluggy.ts), e o estouro chega aqui como erro.

/** `app_settings.cartao_posicao_modo = 'desligado'` para de guardar (ausente = ligado). */
export const CHAVE_DO_CARTAO = "cartao_posicao_modo";

/** Faturas vencidas há mais que isto ficam fora do resumo de cada leitura (já não mudam; o cru segue na tabela delas). */
const DIAS_DE_FATURA_NO_RESUMO = 60;

export interface PosicaoDoCartao {
  provider_account_id: string;
  nome: string | null;
  final: string | null;
  /**
   * O `balance` da conta de crédito, como veio. A documentação diz "fatura aberta ainda não paga" e, para conexão de
   * Open Finance (o nosso caso), "limite usado" — que inclui parcela futura. Não chamar de fatura antes de conferir.
   */
  saldo_informado: number | null;
  vencimento: string | null;
  fechamento: string | null;
  minimo: number | null;
  limite: number | null;
  limite_disponivel: number | null;
  situacao: string | null;
  dados: Record<string, unknown> | null;
}

export interface FaturaDoBanco {
  bill_id: string;
  provider_account_id: string;
  vencimento: string | null;
  fechamento: string | null;
  total: number | null;
  minimo: number | null;
  pago: number | null;
  encargos: number | null;
  dados: Record<string, unknown>;
}

/** O estado de uma fatura numa leitura, para a série (a tabela das faturas guarda só o último). */
export interface FaturaVista {
  bill_id: string;
  vencimento: string | null;
  total: number | null;
  minimo: number | null;
  pago: number | null;
  encargos: number | null;
  pagamentos: number | null;
  ultimo_pagamento: string | null;
}

const ehObjeto = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);

/**
 * O dia como o banco escreveu. A data vem como "2026-12-10" ou "2026-12-10T00:00:00.000Z": é um DIA, não um instante,
 * então se corta o texto — converter para o fuso de Brasília empurraria o vencimento para a véspera.
 */
function dia(v: unknown): string | null {
  const s = typeof v === "string" ? v.slice(0, 10) : "";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s ? s : null;
}

/** Um instante (data e hora) válido, ou null. Nunca "agora": o que o provedor não disse fica sem dizer. */
function instante(v: unknown): string | null {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}T/.test(v)) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/**
 * Número com centavos, ou null. Só número ou texto com conteúdo: `Number(null)`, `Number("")`, `Number(" ")` e
 * `Number([])` são todos ZERO, e campo que o banco não mandou não pode virar "R$ 0,00".
 */
function valor(v: unknown): number | null {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : null;
}

function texto(v: unknown, max = 120): string | null {
  const s = typeof v === "string" ? v.trim() : typeof v === "number" ? String(v) : "";
  return s ? s.slice(0, max) : null;
}

/**
 * Soma o `amount` de uma lista do banco. Sem lista = null (não se sabe); lista vazia = 0 (o banco disse que não há);
 * um item sem valor legível = null (soma parcial passaria por total sem marca nenhuma).
 */
function soma(lista: unknown): number | null {
  if (!Array.isArray(lista)) return null;
  let total = 0;
  for (const item of lista) {
    const n = valor(ehObjeto(item) ? item.amount : null);
    if (n === null) return null;
    total += n;
  }
  return Math.round(total * 100) / 100;
}

/** O retrato de uma conta de crédito. Conta que não é de crédito (ou sem código) = null. */
export function posicaoDoCartao(conta: unknown): PosicaoDoCartao | null {
  if (!ehObjeto(conta)) return null;
  if (String(conta.type ?? "").toUpperCase() !== "CREDIT") return null;
  const id = texto(conta.id, 200);
  if (!id) return null;
  const credito = ehObjeto(conta.creditData) ? conta.creditData : null;
  const digitos = String(conta.number ?? "").replace(/\D/g, "");
  return {
    provider_account_id: id,
    nome: texto(conta.name),
    final: digitos.length >= 4 ? digitos.slice(-4) : null,
    saldo_informado: valor(conta.balance),
    vencimento: dia(credito?.balanceDueDate),
    fechamento: dia(credito?.balanceCloseDate),
    minimo: valor(credito?.minimumPayment),
    limite: valor(credito?.creditLimit),
    limite_disponivel: valor(credito?.availableCreditLimit),
    situacao: texto(credito?.status, 40),
    dados: credito,
  };
}

/** Uma fatura da lista do banco. Sem código não há como regravar a mesma fatura depois: fica de fora. */
export function faturaDoBanco(fatura: unknown, contaId: string): FaturaDoBanco | null {
  if (!ehObjeto(fatura)) return null;
  const id = texto(fatura.id, 200);
  if (!id) return null;
  return {
    bill_id: id,
    provider_account_id: contaId,
    vencimento: dia(fatura.dueDate),
    // `billClosingDate` aparece nos exemplos do provedor, mas não na tabela de campos: se vier, guarda.
    fechamento: dia(fatura.billClosingDate),
    total: valor(fatura.totalAmount),
    minimo: valor(fatura.minimumPaymentAmount),
    pago: soma(fatura.payments),
    encargos: soma(fatura.financeCharges),
    dados: fatura,
  };
}

/** As faturas válidas da lista, uma por código (a última vence: o banco pode repetir a mesma na resposta). */
export function faturasDoBanco(lista: unknown, contaId: string): FaturaDoBanco[] {
  const porCodigo = new Map<string, FaturaDoBanco>();
  for (const item of Array.isArray(lista) ? lista : []) {
    const f = faturaDoBanco(item, contaId);
    if (f) porCodigo.set(f.bill_id, f);
  }
  return [...porCodigo.values()];
}

/**
 * O estado das faturas NESTA leitura, para a série do retrato: a tabela das faturas é regravada a cada passagem, e sem
 * isto se perde como o total e os pagamentos andam (o que é justamente o que se quer observar). Só as que ainda podem
 * mudar: sem vencimento, a vencer, ou vencidas há até 60 dias.
 */
export function faturasVistas(faturas: FaturaDoBanco[], hoje: string): FaturaVista[] {
  const corte = new Date(new Date(`${hoje}T00:00:00Z`).getTime() - DIAS_DE_FATURA_NO_RESUMO * 86_400_000)
    .toISOString().slice(0, 10);
  return faturas
    .filter((f) => !f.vencimento || f.vencimento >= corte)
    .map((f) => {
      const pagamentos = Array.isArray(f.dados.payments) ? f.dados.payments as unknown[] : null;
      const dias = (pagamentos ?? []).map((p) => dia(ehObjeto(p) ? p.paymentDate : null)).filter((d): d is string => !!d).sort();
      return {
        bill_id: f.bill_id,
        vencimento: f.vencimento,
        total: f.total,
        minimo: f.minimo,
        pago: f.pago,
        encargos: f.encargos,
        pagamentos: pagamentos ? pagamentos.length : null,
        ultimo_pagamento: dias.length > 0 ? dias[dias.length - 1] : null,
      };
    })
    .sort((a, b) => String(a.vencimento ?? "9999").localeCompare(String(b.vencimento ?? "9999")) || a.bill_id.localeCompare(b.bill_id));
}

// deno-lint-ignore no-explicit-any
type Admin = any;

/**
 * Guarda o retrato do cartão e as faturas que o banco emitiu. Chamada uma vez por conta de crédito, por sincronização.
 *
 * Nunca lança. A lista de faturas é uma chamada a mais ao provedor: se ela falhar (ou estourar o prazo), o retrato é
 * gravado do mesmo jeito, com o motivo em `faturas_erro` — é assim que se descobre se este banco entrega a lista, sem
 * abrir o log. `provedorAtualizadoEm` é quando o provedor foi ao banco (ele vai uma vez por dia e a sincronização lê
 * três): sem isso, duas de cada três linhas da série repetem o dado da véspera sem marca.
 */
export async function guardarCartao(
  admin: Admin,
  conexaoId: string,
  conta: unknown,
  lerFaturas: (contaId: string) => Promise<unknown>,
  provedorAtualizadoEm?: unknown,
): Promise<void> {
  try {
    const posicao = posicaoDoCartao(conta);
    if (!posicao) return;

    const { data: chave } = await admin.from("app_settings").select("value").eq("key", CHAVE_DO_CARTAO).maybeSingle();
    if (String(chave?.value ?? "").trim().replace(/^"(.*)"$/, "$1").toLowerCase() === "desligado") return;

    const agora = new Date().toISOString();
    let faturasLidas: number | null = null;
    let faturasErro: string | null = null;
    let vistas: FaturaVista[] | null = null;
    try {
      const faturas = faturasDoBanco(await lerFaturas(posicao.provider_account_id), posicao.provider_account_id);
      // antes de gravar: se a gravação das faturas falhar, o que o banco disse nesta leitura fica na série mesmo assim
      vistas = faturasVistas(faturas, agora.slice(0, 10));
      if (faturas.length > 0) {
        // `visto_em` fica de fora de propósito: na primeira vez vale o padrão da coluna, depois não muda.
        const { error } = await admin.from("cartao_faturas_do_banco").upsert(
          faturas.map((f) => ({ ...f, bank_connection_id: conexaoId, lido_em: agora })),
          { onConflict: "bill_id" },
        );
        if (error) throw error;
      }
      faturasLidas = faturas.length;
    } catch (e) {
      faturasErro = String((e as Error)?.message ?? e).slice(0, 300) || "erro sem mensagem";
    }

    const { error } = await admin.from("cartao_posicoes").insert({
      ...posicao,
      bank_connection_id: conexaoId,
      faturas_lidas: faturasLidas,
      faturas_erro: faturasErro,
      faturas_vistas: vistas,
      provedor_atualizado_em: instante(provedorAtualizadoEm),
      lido_em: agora,
    });
    if (error) throw error;
  } catch (e) {
    console.warn("[banking-sync] retrato do cartão não gravado (ignorado):", (e as Error)?.message ?? e);
  }
}
