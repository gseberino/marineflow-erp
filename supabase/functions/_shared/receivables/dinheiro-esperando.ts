// Dinheiro de cliente que já entrou no banco e espera decisão no Extrato (24/11/2026).
//
// POR QUE ISTO EXISTE: uma conta a receber fica "em aberto" até alguém aplicar a entrada nela. Enquanto a entrada espera
// na fila do Extrato, o sistema seguia tratando o cliente como devedor. A trava que já existia (pix-esperando.ts) só
// olhava entradas com o CLIENTE identificado pela fila. Medido em 24/11/2026: das 12 contas vencidas (R$ 45.908,67),
// 7 tinham dinheiro esperando (R$ 22.830,67), e 3 delas (R$ 12.586,07) passavam pela trava — os dois boletos da Apolo
// (valor e dia exatos do vencimento) e o Pix do Nelson estavam na fila SEM cliente, só com o vínculo sugerido apontando
// a conta. A manhã recomendou "ligar hoje" para a Apolo 50 vezes sobre dinheiro que estava no banco desde o vencimento.
//
// A REGRA: uma entrada pendente conta para um cliente quando
//   · a fila identificou o cliente (suggested_client_id) — o que já valia; ou
//   · o vínculo sugerido principal aponta uma conta a receber ABERTA — aí vale o cliente dessa conta.
// O segundo caso pode ter nascido só de valor e data: por isso isto NUNCA aplica dinheiro, não dá baixa e não liga nada.
// Serve para duas coisas, as duas do lado seguro: segurar a cobrança ("pode ser este pagamento, confira") e mostrar ao
// dono que há entrada esperando baixa. A baixa continua sendo dele, no Extrato.
//
// Pura na regra (dinheiroEsperando) e usada também pela tela (src/hooks/use-cobrar-juntas.ts): a ficha do cliente e o
// assistente têm de barrar as mesmas cobranças.

/** Uma entrada pendente da fila do Extrato (finance_review_queue, kind create_receivable). */
export interface EntradaDaFila {
  suggested_client_id: string | null;
  suggested_amount: number | string | null;
  suggested_date: string | null;
  title?: string | null;
  vinculo_sugerido?: unknown;
}

/** Conta a receber em aberto (pending ou partially_paid). */
export interface ContaAberta {
  id: string;
  client_id: string | null;
}

export interface EntradaEsperando {
  clienteId: string;
  valor: number;
  /** 'AAAA-MM-DD' */
  data: string | null;
  titulo: string;
  /** a conta aberta que o vínculo sugerido aponta (null = a entrada só tem o cliente) */
  contaId: string | null;
  /** true = o cliente veio da conta apontada pelo vínculo (a fila não o identificou) */
  pelaConta: boolean;
}

/** A conta a receber que o vínculo sugerido principal aponta, ou null. */
export function contaApontada(vinculo: unknown): string | null {
  if (!vinculo || typeof vinculo !== "object") return null;
  const principal = (vinculo as { principal?: unknown }).principal;
  if (!principal || typeof principal !== "object") return null;
  const p = principal as { tipo?: unknown; lancamentoId?: unknown };
  return p.tipo === "receivable" && typeof p.lancamentoId === "string" && p.lancamentoId ? p.lancamentoId : null;
}

/** As contas que as entradas apontam (para ler só essas do banco). */
export function contasApontadas(entradas: EntradaDaFila[]): string[] {
  return [...new Set(entradas.map((e) => contaApontada(e.vinculo_sugerido)).filter((id): id is string => !!id))];
}

/**
 * As entradas que contam para algum cliente. `contasAbertas`: as contas apontadas que estão em aberto (conta paga ou
 * cancelada não entra na lista, e a entrada que a aponta não segura cobrança de ninguém).
 */
export function dinheiroEsperando(entradas: EntradaDaFila[], contasAbertas: ContaAberta[]): EntradaEsperando[] {
  const abertas = new Map(contasAbertas.map((c) => [c.id, c]));
  const saida: EntradaEsperando[] = [];
  for (const e of entradas) {
    const apontada = contaApontada(e.vinculo_sugerido);
    const conta = apontada ? abertas.get(apontada) ?? null : null;
    const clienteId = e.suggested_client_id || conta?.client_id || null;
    if (!clienteId) continue;
    saida.push({
      clienteId,
      valor: Math.abs(Number(e.suggested_amount ?? 0)) || 0,
      data: e.suggested_date ? String(e.suggested_date).slice(0, 10) : null,
      titulo: String(e.title ?? ""),
      // a conta só vale como "desta entrada" quando é do mesmo cliente
      contaId: conta && conta.client_id === clienteId ? conta.id : null,
      pelaConta: !e.suggested_client_id,
    });
  }
  return saida;
}

/** As entradas esperando de uma conta: as que a apontam; sem nenhuma, as do cliente dela que não apontam outra conta. */
export function esperandoDaConta(todas: EntradaEsperando[], conta: { id: string; client_id: string | null }): EntradaEsperando[] {
  const dela = todas.filter((e) => e.contaId === conta.id);
  if (dela.length > 0) return dela;
  return conta.client_id ? todas.filter((e) => e.clienteId === conta.client_id && !e.contaId) : [];
}

// deno-lint-ignore no-explicit-any
type Admin = any;

/**
 * Lê a fila e as contas apontadas. LANÇA em erro: "nenhum dinheiro esperando" por falha de leitura mandaria cobrar quem
 * já pagou. Quem chama decide o que fazer com o erro.
 */
export async function lerDinheiroEsperando(admin: Admin): Promise<EntradaEsperando[]> {
  // Em páginas: o servidor corta em 1.000 linhas sem avisar, e entrada cortada vira "ninguém pagou" calado.
  const entradas: EntradaDaFila[] = [];
  for (let de = 0; de < 20_000; de += 1000) {
    const { data, error } = await admin
      .from("finance_review_queue")
      // A fila tem duas ligações com a linha do banco (a própria e a relacionada): o nome da ligação é obrigatório.
      .select("suggested_client_id, suggested_amount, suggested_date, title, vinculo_sugerido, bank_transactions!finance_review_queue_bank_transaction_id_fkey(reconciled)")
      .eq("status", "pending")
      .eq("kind", "create_receivable")
      .order("id")
      .range(de, de + 999);
    if (error) throw new Error(`Não consegui ler os Pix que esperam no Extrato: ${error.message}`);
    const lote = (data ?? []) as Array<EntradaDaFila & { bank_transactions?: unknown }>;
    // Entrada que ficou pendente na fila mas cuja linha do banco JÁ foi conciliada (o sinal de um orçamento, lançado por
    // outro caminho) não é dinheiro esperando: já foi aplicado. Sem a linha (ou sem poder lê-la) continua contando — é o
    // lado seguro, não libera cobrança.
    entradas.push(...lote.filter((e) => {
      const linha = (Array.isArray(e.bank_transactions) ? e.bank_transactions[0] : e.bank_transactions) as { reconciled?: unknown } | null | undefined;
      return linha?.reconciled !== true;
    }));
    if (lote.length < 1000) break;
  }
  const ids = contasApontadas(entradas);
  const abertas: ContaAberta[] = [];
  // Em blocos: a lista de códigos vai na URL do pedido.
  for (let i = 0; i < ids.length; i += 150) {
    const { data: contas, error: erroDasContas } = await admin
      .from("receivables")
      .select("id, client_id, status")
      .in("id", ids.slice(i, i + 150))
      .in("status", ["pending", "partially_paid"]);
    if (erroDasContas) throw new Error(`Não consegui ler as contas que as entradas do Extrato apontam: ${erroDasContas.message}`);
    for (const c of (contas ?? []) as Array<{ id: string; client_id: string | null }>) abertas.push({ id: String(c.id), client_id: c.client_id ?? null });
  }
  return dinheiroEsperando(entradas, abertas);
}
