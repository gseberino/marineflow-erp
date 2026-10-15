// Entradas do banco sem identificação, separadas pelo que pedem — lógica pura, sem banco.
//
// ═══ POR QUE EXISTE ═══
//
// A linha "🏦 Entradas sem identificação" lia os créditos não conciliados com `.limit(4)` e contava
// o que voltava: ficou travada em *4* (em 15/10/2026 eram 10, R$ 18.798,45). E misturava três
// coisas que pedem ações diferentes:
//   · entrada do mês, sem nada lançado — essa é a que o dono precisa identificar;
//   · Pix que já é um SINAL lançado à mão (pagamento confirmado sem linha do extrato): aprovar
//     como receita nova duplicaria a receita; é papelada de escritório (ligar ao extrato);
//   · entrada antiga ou de centavos (pedágio estornado, R$ 0,35 de cheque especial): escritório.
// Em 15/10: R$ 7.600 (05/10) era o "Sinal — ORÇ-00112" do Nelson e R$ 2.869,50 (13/10) o
// "Sinal — ORÇ-00100" do Giancarlo — este pago por outra pessoa (Jeanine). Por isso o critério é
// valor + data, NUNCA o nome de quem pagou; e nada é ligado sozinho: o resumo só separa.

export interface EntradaDoBanco { id: string; transaction_date: string; amount: number | string; description: string | null }
/**
 * rotulo = descrição do recebível (+ cliente), ex.: "Sinal — ORÇ-00112 (Nelson)".
 * forma = payments.payment_method. Dinheiro ("cash") nunca casa: não passa pelo banco (em 15/10/2026,
 * 0 dos 4 pagamentos em dinheiro tinham linha do extrato) — casar esconderia um Pix de verdade.
 */
export interface PagamentoSemExtrato { id: string; amount: number | string; payment_date: string; rotulo: string; forma?: string | null }
export interface EntradasSeparadas {
  doMes: EntradaDoBanco[];
  sinais: Array<{ entrada: EntradaDoBanco; rotulo: string }>;
  antigas: EntradaDoBanco[];
}

/** Diferença máxima de valor (em centavos) e de dias para um pagamento lançado casar uma entrada. */
const TOLERANCIA_CENTAVOS = 100;
const TOLERANCIA_DIAS = 7;
/** Abaixo disto, a entrada do mês é "centavos" (vai para o escritório). */
const MINIMO_DO_MES = 10;

const MESES = [
  "janeiro", "fevereiro", "março", "abril", "maio", "junho",
  "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
];

const centavos = (v: number | string) => Math.round(Number(v) * 100);
/** Dias entre dois dias de calendário 'aaaa-mm-dd' (sem fuso: dia não tem hora). */
function diasEntre(a: string, b: string): number {
  const t = (d: string) => Date.UTC(Number(d.slice(0, 4)), Number(d.slice(5, 7)) - 1, Number(d.slice(8, 10)));
  return Math.round(Math.abs(t(a) - t(b)) / 86_400_000);
}

/** Ordem: valor desc. Cada pagamento casa no máximo UMA entrada (|valor| ≤ R$ 1,00 e |dias| ≤ 7).
 *  Sem casar: do mês = transaction_date ≥ 1º dia do mês de Brasília E valor ≥ R$ 10; o resto é antiga/centavos. */
export function separarEntradas(entradas: EntradaDoBanco[], pagamentos: PagamentoSemExtrato[], hojeBR: string): EntradasSeparadas {
  const inicioDoMes = `${String(hojeBR).slice(0, 7)}-01`;
  const ordenadas = (entradas ?? []).slice().sort((a, b) => centavos(b.amount) - centavos(a.amount));
  const usados = new Set<string>();
  const r: EntradasSeparadas = { doMes: [], sinais: [], antigas: [] };
  for (const e of ordenadas) {
    const dia = String(e.transaction_date).slice(0, 10);
    // O pagamento mais parecido: menor diferença de valor, depois de dias.
    let melhor: { p: PagamentoSemExtrato; dv: number; dd: number } | null = null;
    for (const p of pagamentos ?? []) {
      if (usados.has(p.id) || p.forma === "cash") continue;
      const dv = Math.abs(centavos(p.amount) - centavos(e.amount));
      const dd = diasEntre(dia, String(p.payment_date).slice(0, 10));
      if (dv > TOLERANCIA_CENTAVOS || dd > TOLERANCIA_DIAS) continue;
      if (!melhor || dv < melhor.dv || (dv === melhor.dv && dd < melhor.dd)) melhor = { p, dv, dd };
    }
    if (melhor) {
      usados.add(melhor.p.id);
      r.sinais.push({ entrada: e, rotulo: melhor.p.rotulo });
    } else if (dia >= inicioDoMes && centavos(e.amount) >= MINIMO_DO_MES * 100) {
      r.doMes.push(e);
    } else {
      r.antigas.push(e);
    }
  }
  return r;
}

const somar = (l: EntradaDoBanco[]) => l.reduce((s, e) => s + Number(e.amount || 0), 0);

/**
 * Linhas do resumo: o cabeçalho do mês com até 3 entradas (com o palpite do motor de conciliação,
 * quando houver) e UMA linha de escritório para os sinais já lançados e as antigas/centavos.
 * Sem entrada do mês, só a linha do escritório, com o 🏦 na frente. Nada pendente: nenhuma linha.
 */
export function linhasDasEntradas(
  s: EntradasSeparadas,
  fmt: (v: number) => string,
  palpites: Map<string, string>,
  hojeBR: string,
): string[] {
  const linhas: string[] = [];
  if (s.doMes.length > 0) {
    const mes = MESES[Number(String(hojeBR).slice(5, 7)) - 1] ?? "";
    linhas.push(`🏦 Entradas do banco sem identificação${mes ? ` (${mes})` : ""}: *${s.doMes.length}* (${fmt(somar(s.doMes))})`);
    for (const t of s.doMes.slice(0, 3)) {
      const palpite = palpites.get(t.id);
      linhas.push(palpite
        ? `   • ${fmt(Number(t.amount))} — parece ser ${palpite}`
        : `   • ${fmt(Number(t.amount))} — ${String(t.description || "").slice(0, 40)}`);
    }
  }
  const partes: string[] = [];
  if (s.sinais.length > 0) {
    const n = s.sinais.length;
    const total = somar(s.sinais.map((x) => x.entrada));
    // "Sinal" só quando todos são sinal: o casamento aceita qualquer pagamento já lançado ("À vista —
    // OS-…", "Saldo 50% — …"), e chamar de sinal o que não é seria afirmar o que não se sabe.
    const todosSinal = s.sinais.every((x) => /^\s*sinal\b/i.test(x.rotulo));
    const nome = todosSinal
      ? (n === 1 ? "sinal já lançado" : "sinais já lançados")
      : (n === 1 ? "pagamento já lançado" : "pagamentos já lançados");
    partes.push(`${n} ${nome} para ligar ao extrato, não aprovar como receita nova (${fmt(total)})`);
  }
  if (s.antigas.length > 0) {
    const n = s.antigas.length;
    partes.push(`${n} ${n === 1 ? "antiga" : "antigas"} ou de centavos (${fmt(somar(s.antigas))})`);
  }
  if (partes.length > 0) {
    linhas.push(`${linhas.length > 0 ? "   " : "🏦 "}Escritório: ${partes.join(" · ")}`);
  }
  return linhas;
}
