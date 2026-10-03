// "Parece pagar": quais contas que JÁ EXISTEM uma entrada do banco paga (forma A, F4 — 03/10/2026).
//
// Por que existe: o Extrato só sugeria UMA conta de valor parecido (vinculo.ts filtra a 25% do
// valor), e "Este Pix paga…" (F2) começava em branco. Um Pix que paga duas OS, ou os sinais
// lançados à mão, virava receita nova — foi assim que a receita de agosto contou o Pix do Lenine
// (R$ 4.800) duas vezes.
//
// Regras (do dono e do plano "Um Pix, várias contas"):
//   - Nunca só pelo valor: quem chama passa SÓ as contas e pagamentos do cliente IDENTIFICADO
//     (documento, histórico, nome idêntico ou regra do dono). Pagador com outro nome é pergunta.
//   - É sugestão: abre "Este Pix paga…" já preenchido; quem aplica é a pessoa (ou o dono, pelo
//     assistente, depois de perguntado).
//   - Mesma tolerância da aplicação (src/lib/este-pix-paga.ts e aplicar_entrada_em_contas): até
//     R$ 10 a mais vira receita de uma conta; até R$ 10 a menos quita com desconto.
//   - Uma conta só fica de fora: essa já é a sugestão de vínculo da linha (vinculo.ts). Aqui entram
//     duas ou mais, ou a parte de uma conta (OS paga em mais de um Pix).
// Sem I/O: testado em parece-pagar_test.ts e usado pela tela do Extrato e pelo assistente.

export const TOLERANCIA_PARECE_PAGAR = 10;
/** Pagamento lançado à mão só conta como "este Pix" se a data for perto da do Pix. */
export const DIAS_DO_PAGAMENTO_A_MAO = 15;
const MAX_CONTAS = 8;
const MAX_PAGAMENTOS = 6;

export interface CandidatoDaEntrada {
  tipo: "conta" | "pagamento";
  /** receivable_id (conta) ou payment id (pagamento lançado à mão, sem Pix). */
  id: string;
  /** Saldo da conta, ou o valor do pagamento. */
  valor: number;
  /** Vencimento da conta, ou a data do pagamento (AAAA-MM-DD). */
  data: string;
  /** "OS-00045", "Sinal — ORÇ-00074"… */
  rotulo: string;
}

export interface ItemParecePagar {
  tipo: "conta" | "pagamento";
  id: string;
  rotulo: string;
  /** O que falta na conta / o valor do pagamento. */
  saldo: number;
  /** Quanto da entrada vai para ele. */
  valor: number;
  /** Conta quitada com desconto (até R$ 10 a menos). */
  quitar: boolean;
}

export interface ParecePagar {
  itens: ItemParecePagar[];
  /** Entrada − soma dos saldos: > 0 pagou a mais (até R$ 10), < 0 a menos (até R$ 10). */
  diferenca: number;
  /** Outra combinação também cabe: a pessoa confere qual é. */
  outraCombinacao: boolean;
  /** Paga só parte da única conta em aberto (OS paga em mais de um Pix). */
  parcial: boolean;
}

const cents = (v: number) => Math.round((Number(v) || 0) * 100);
const reais = (c: number) => c / 100;

function diasEntre(a: string, b: string): number {
  return Math.abs(Date.parse(`${a.slice(0, 10)}T12:00:00Z`) - Date.parse(`${b.slice(0, 10)}T12:00:00Z`)) / 86_400_000;
}

export function parecePagar(
  entrada: { valor: number; data: string },
  candidatos: CandidatoDaEntrada[],
): ParecePagar | null {
  const alvo = cents(entrada.valor);
  if (alvo <= 0) return null;
  const tol = cents(TOLERANCIA_PARECE_PAGAR);

  // Contas: as mais antigas primeiro (paga-se o que vence antes). Pagamentos à mão: os mais
  // perto da data do Pix, e só até 15 dias.
  const contas = candidatos.filter((c) => c.tipo === "conta" && cents(c.valor) > 0)
    .sort((a, b) => a.data.localeCompare(b.data) || a.rotulo.localeCompare(b.rotulo))
    .slice(0, MAX_CONTAS);
  const pagamentos = candidatos
    .filter((c) => c.tipo === "pagamento" && cents(c.valor) > 0 && diasEntre(c.data, entrada.data) <= DIAS_DO_PAGAMENTO_A_MAO)
    .sort((a, b) => diasEntre(a.data, entrada.data) - diasEntre(b.data, entrada.data))
    .slice(0, MAX_PAGAMENTOS);
  const pool = [...contas, ...pagamentos];
  if (pool.length === 0) return null;

  type Aceita = { mask: number; diff: number; tamanho: number; idade: number };
  const aceitas: Aceita[] = [];
  const total = 1 << pool.length;
  for (let mask = 1; mask < total; mask++) {
    let soma = 0, tamanho = 0, idade = 0, temConta = false;
    for (let i = 0; i < pool.length; i++) {
      if (!(mask & (1 << i))) continue;
      soma += cents(pool[i].valor);
      tamanho++;
      idade += i;
      if (pool[i].tipo === "conta") temConta = true;
    }
    const diff = alvo - soma;
    // A diferença só cabe numa conta (receita ou desconto dela); pagamento à mão liga inteiro.
    if (diff === 0 || (temConta && Math.abs(diff) <= tol)) aceitas.push({ mask, diff, tamanho, idade });
  }

  if (aceitas.length === 0) {
    // OS paga em mais de um Pix: o Pix é menos do que falta numa conta — e só UMA conta do
    // cliente comporta esse valor (com duas, não se adivinha qual recebeu a parte). Caso real:
    // MP Motor Homes, OS-00045 de R$ 1.650 em aberto e Pix de R$ 1.250 (11/08) + R$ 400 (14/08).
    const comportam = contas.filter((c) => alvo < cents(c.valor) - tol);
    if (comportam.length === 1) {
      const c = comportam[0];
      return {
        itens: [{ tipo: "conta", id: c.id, rotulo: c.rotulo, saldo: c.valor, valor: entrada.valor, quitar: false }],
        diferenca: reais(alvo - cents(c.valor)), outraCombinacao: false, parcial: true,
      };
    }
    return null;
  }

  aceitas.sort((a, b) => Math.abs(a.diff) - Math.abs(b.diff) || a.idade - b.idade || a.tamanho - b.tamanho);
  const melhor = aceitas[0];
  // Uma conta ou um pagamento só: é a sugestão de vínculo da própria linha, não esta.
  if (melhor.tamanho < 2) return null;

  const escolhidos = pool.filter((_, i) => melhor.mask & (1 << i));
  const itens: ItemParecePagar[] = escolhidos.map((c) => ({
    tipo: c.tipo, id: c.id, rotulo: c.rotulo, saldo: c.valor, valor: c.valor, quitar: false,
  }));
  if (melhor.diff !== 0) {
    // A diferença vai para a conta que vence por último entre as escolhidas.
    const ultima = [...itens].reverse().find((i) => i.tipo === "conta")!;
    ultima.valor = reais(cents(ultima.valor) + melhor.diff);
    ultima.quitar = melhor.diff < 0;
  }
  // Ambígua quando outra combinação é tão boa quanto (mesma diferença), ou quando a melhor já não
  // é exata — aí qualquer outra que caiba também é plausível.
  const outraCombinacao = aceitas.slice(1).some((a) => Math.abs(a.diff) === Math.abs(melhor.diff) || melhor.diff !== 0);
  return { itens, diferenca: reais(melhor.diff), outraCombinacao, parcial: false };
}

const ddmm = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

/**
 * Contas em aberto e pagamentos lançados à mão (sem Pix, fora dinheiro) dos clientes — a mesma
 * leitura das listas do "Este Pix paga…" (use-lancamentos.ts), numa consulta para a fila toda.
 * `desde`: pagamentos à mão a partir desta data (a regra só olha 15 dias em volta do Pix).
 * Leitura que falha LANÇA: "não parece pagar nada" por erro deixaria aprovar receita em dobro.
 */
// deno-lint-ignore no-explicit-any
export async function candidatosDosClientes(sb: any, clientIds: string[], desde: string): Promise<Map<string, CandidatoDaEntrada[]>> {
  const mapa = new Map<string, CandidatoDaEntrada[]>(clientIds.map((id) => [id, []]));
  if (clientIds.length === 0) return mapa;
  const [contas, pagamentos] = await Promise.all([
    sb.from("receivables")
      .select("id, client_id, description, due_date, amount, paid_amount, service_orders!receivables_service_order_id_fkey(service_order_number)")
      .in("client_id", clientIds)
      .in("status", ["pending", "overdue", "partially_paid"])
      .range(0, 999),
    sb.from("payments")
      .select("id, amount, payment_date, receivables!inner(client_id, description, status, service_orders!receivables_service_order_id_fkey(service_order_number))")
      .in("receivables.client_id", clientIds)
      .neq("receivables.status", "cancelled")
      .eq("status", "confirmed")
      .is("bank_transaction_id", null)
      .neq("payment_method", "cash")
      .gte("payment_date", desde)
      .range(0, 999),
  ]);
  if (contas.error) throw new Error(`Não consegui ler as contas em aberto: ${contas.error.message}`);
  if (pagamentos.error) throw new Error(`Não consegui ler os pagamentos lançados à mão: ${pagamentos.error.message}`);
  for (const r of (contas.data ?? []) as Array<{
    id: string; client_id: string; description: string | null; due_date: string; amount: number; paid_amount: number | null;
    service_orders: { service_order_number: string } | null;
  }>) {
    const saldo = Math.round((Number(r.amount) - Number(r.paid_amount ?? 0)) * 100) / 100;
    if (saldo <= 0) continue;
    mapa.get(r.client_id)?.push({
      tipo: "conta", id: r.id, valor: saldo, data: r.due_date,
      rotulo: r.service_orders?.service_order_number ?? r.description ?? "Conta a receber",
    });
  }
  for (const p of (pagamentos.data ?? []) as Array<{
    id: string; amount: number; payment_date: string;
    receivables: { client_id: string; description: string | null; service_orders: { service_order_number: string } | null } | null;
  }>) {
    if (!p.receivables) continue;
    const doQue = p.receivables.service_orders?.service_order_number ?? p.receivables.description ?? "conta a receber";
    mapa.get(p.receivables.client_id)?.push({
      tipo: "pagamento", id: p.id, valor: Number(p.amount), data: p.payment_date,
      rotulo: `${doQue} (lançado à mão em ${ddmm(p.payment_date)})`,
    });
  }
  return mapa;
}

/** Uma frase do que a sugestão diz, para a tela e para o assistente. */
export function fraseDoParecePagar(p: ParecePagar, formatar: (v: number) => string): string {
  const lista = p.itens.map((i) => `${i.rotulo} (${formatar(i.valor)})`).join(" + ");
  if (p.parcial) {
    return `Parece ser parte de ${lista}: faltavam ${formatar(p.itens[0].saldo)}.`;
  }
  const dif = p.diferenca > 0
    ? ` Pagou ${formatar(p.diferenca)} a mais: vira receita da última conta.`
    : p.diferenca < 0 ? ` Faltam ${formatar(-p.diferenca)}: a última conta fica quitada com desconto (dá para desmarcar).` : "";
  const outra = p.outraCombinacao ? " Outra combinação também soma esse valor: confira." : "";
  return `Parece pagar ${lista}.${dif}${outra}`;
}
