// "Cobrar juntas" (Fase 0 do Fechar juntas, 28/10/2026): uma mensagem só com o saldo de várias OS
// já executadas do mesmo cliente. Não muda o banco: é o extrato filtrado pelas OS escolhidas.
//
// Regra PURA, sem import nenhum, para valer igual na tela (Vite importa este arquivo pelo caminho
// relativo, como faz com _shared/banking/mcc.ts) e no assistente (Deno). Duas cópias de regra de
// dinheiro divergem — foi assim que nasceram o "Pago" que ignorava pago parcial e o "a vencer" de
// dívida de julho (spec-fechar-juntas 4.1).
//
// As travas são as mesmas do send_collection_reminder (_shared/ai/tools/whatsapp.ts): piso de
// materialidade, Pix do cliente esperando no Extrato, opt-out, telefone e o horário de cobrança
// (8h–20h em Brasília, o portão de _shared/ai/comms/compliance-guard.ts) — mais a recusa do
// cadastro genérico (sem CPF/CNPJ), que nunca entra em cobrança conjunta (dono, 28/10/2026), e os
// limites de 2 a 10 OS da tool cobrar_juntas.
//
// O registro do envio (last_auto_sent_at) só existe quando a conta tem cobrança formal
// (collections). Sem ela — o caso da MP em 28/10/2026 — nada fica registrado e o plano de
// inadimplência, que lê collections, pode sugerir cobrar de novo no mesmo dia: SEM_COBRANCA_FORMAL.

/**
 * OS que entram no "Cobrar juntas": já começaram (em execução, concluída ou faturada). As que não
 * começaram se juntam pelo Agrupar OS; origem de agrupamento (merged_into_id) nunca entra.
 * Decidido pela SITUAÇÃO: uma OS "aguardando peças/cliente" com execução já registrada (chegada no
 * barco, hora, despesa…) fica fora dos dois — o agrupar_os a recusa por já ter começado. A tool
 * cobrar_juntas explica isso em vez de mandar ao agrupar_os (problemaDaOS).
 */
export const STATUS_QUE_COBRAM_JUNTAS: readonly string[] = ['in_progress', 'completed', 'invoiced'];

export function osEntraNoCobrarJuntas(os: { status?: string | null; merged_into_id?: string | null } | null | undefined): boolean {
  return !!os && !os.merged_into_id && STATUS_QUE_COBRAM_JUNTAS.includes(String(os.status));
}

export interface ContaDoCliente {
  id: string;
  service_order_id?: string | null;
  numero_os?: string | null;
  description?: string | null;
  due_date?: string | null;
  status?: string | null;
  amount?: number | null;
  paid_amount?: number | null;
  balance_amount?: number | null;
}

const n = (v: unknown) => {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
};
const centavos = (v: number) => Math.round(v * 100) / 100;

/** O que já entrou na conta. Sem paid_amount (dado antigo), deduz pelo status e pelo saldo. */
export function pagoDaConta(c: Pick<ContaDoCliente, 'status' | 'amount' | 'paid_amount' | 'balance_amount'>): number {
  if (c.paid_amount != null) return n(c.paid_amount);
  if (c.status === 'paid') return n(c.amount);
  if (c.balance_amount != null) return Math.max(0, centavos(n(c.amount) - n(c.balance_amount)));
  return 0;
}

/**
 * O que falta pagar. Mesma regra de resumirEmAberto (src/lib/ficha-cliente.ts), que a ficha do
 * cliente na OS usa: paga ou cancelada = 0; senão balance_amount (o banco mantém), com
 * amount − paid_amount de reserva. Nunca negativo.
 */
export function saldoDaConta(c: Pick<ContaDoCliente, 'status' | 'amount' | 'paid_amount' | 'balance_amount'>): number {
  if (c.status === 'paid' || c.status === 'cancelled') return 0;
  const saldo = c.balance_amount != null ? n(c.balance_amount) : n(c.amount) - n(c.paid_amount);
  return saldo > 0.009 ? centavos(saldo) : 0;
}

export function hojeLocal(d: Date = new Date()): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** Vencida = tem saldo e a data passou. O banco nunca grava 'overdue' (medido em 28/10/2026). */
export function contaVencida(c: ContaDoCliente, hoje: string = hojeLocal()): boolean {
  return saldoDaConta(c) > 0 && !!c.due_date && c.due_date.slice(0, 10) < hoje;
}

export interface OsParaCobrar {
  service_order_id: string;
  numero_os: string;
  /** Só as contas com saldo, por vencimento. */
  contas: ContaDoCliente[];
  saldo: number;
  vencido: boolean;
}

/** As OS do cliente que têm saldo em aberto, com as contas abertas de cada uma. */
export function osComSaldo(contas: ContaDoCliente[], hoje: string = hojeLocal()): OsParaCobrar[] {
  const porOs = new Map<string, OsParaCobrar>();
  for (const c of contas || []) {
    if (!c.service_order_id || saldoDaConta(c) <= 0) continue;
    const os = porOs.get(c.service_order_id) ?? {
      service_order_id: c.service_order_id,
      numero_os: c.numero_os || 'OS',
      contas: [],
      saldo: 0,
      vencido: false,
    };
    os.contas.push(c);
    os.saldo = centavos(os.saldo + saldoDaConta(c));
    os.vencido = os.vencido || contaVencida(c, hoje);
    if (c.numero_os && os.numero_os === 'OS') os.numero_os = c.numero_os;
    porOs.set(c.service_order_id, os);
  }
  const lista = [...porOs.values()];
  for (const os of lista) os.contas.sort((a, b) => String(a.due_date).localeCompare(String(b.due_date)));
  return lista.sort((a, b) => a.numero_os.localeCompare(b.numero_os));
}

const brl = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);
const brlDoLembrete = (v: number) => `R$ ${v.toFixed(2)}`;

/** Quantas OS uma cobrança conjunta junta: menos de 2 é a cobrança da OS; mais de 10, peça por partes. */
export const MIN_COBRAR_JUNTAS = 2;
export const MAX_COBRAR_JUNTAS = 10;

/**
 * Janela de cobrança a cliente pelo WhatsApp, em Brasília: das 8h até 19h59. A MESMA de
 * checarConformidade (_shared/ai/comms/compliance-guard.ts, H_INICIO/H_FIM), que o assistente
 * aplica no envio; a tela aplica esta. O teste de paridade compara as duas hora a hora.
 */
export const HORA_INICIO_COBRANCA = 8;
export const HORA_FIM_COBRANCA = 20;

/** Hora cheia (0-23) em Brasília, qualquer que seja o fuso da máquina. */
export function horaEmBrasilia(d: Date = new Date()): number {
  const h = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Sao_Paulo', hour: 'numeric', hourCycle: 'h23' }).format(d);
  return Number(h) % 24;
}

/** Aviso quando nenhuma conta escolhida tem cobrança formal: o envio não fica registrado. */
export const SEM_COBRANCA_FORMAL =
  'Nenhuma cobrança formal ligada a estas contas: o envio não fica registrado, e o plano de inadimplência '
  + 'pode sugerir cobrar este cliente de novo hoje.';

export interface EntradaDasTravas {
  clienteNome?: string | null;
  /** clients.generico: o cadastro de balcão ("Cliente Final"), sem CPF/CNPJ. */
  generico?: boolean | null;
  /** Quantas OS entram (2 a 10). Ausente = não confere (a tool confere antes, com a frase dela). */
  quantidadeOs?: number | null;
  /** Hora em Brasília (0-23). Ausente = não confere (a tool aplica o portão guardaDeEnvio no envio). */
  horaBrasilia?: number | null;
  optOut?: boolean | null;
  /** app_settings.collection_min_amount (0 = sem piso). */
  piso?: number | null;
  /** Soma do saldo das contas escolhidas. */
  totalEmAberto: number;
  /** Pix do cliente esperando decisão no Extrato (finance_review_queue pendente). */
  pixEsperando?: Array<{ valor: number; data?: string | null }>;
  telefone?: string | null;
}

/**
 * Por que NÃO enviar (mensagem pronta), ou null quando pode. A ordem é a da tool cobrar_juntas e do
 * send_collection_reminder: o cadastro, quantas OS, o dinheiro (piso, Pix esperando), o contato e,
 * por último, o horário (que lá é o portão do envio).
 */
export function travaDoCobrarJuntas(e: EntradaDasTravas): string | null {
  const nome = (e.clienteNome || '').trim() || 'deste cliente';
  if (e.generico) {
    return `O cadastro ${nome} é genérico, sem CPF/CNPJ: não entra em cobrança conjunta. `
      + 'Passe as OS para o cadastro do cliente de verdade e cobre por lá.';
  }
  if (e.quantidadeOs != null) {
    if (e.quantidadeOs < MIN_COBRAR_JUNTAS) {
      return 'Cobrar juntas é para 2 OS ou mais. Para uma OS só, cobre pela cobrança dela.';
    }
    if (e.quantidadeOs > MAX_COBRAR_JUNTAS) return `Cobre no máximo ${MAX_COBRAR_JUNTAS} OS de uma vez: desmarque algumas.`;
  }
  const total = centavos(n(e.totalEmAberto));
  if (!(total > 0)) return 'As OS escolhidas não têm saldo em aberto: não há o que cobrar.';
  const piso = n(e.piso);
  if (piso > 0 && total < piso) {
    return `Cobrança de ${brlDoLembrete(total)} fica abaixo do piso de R$ ${piso} (Configurações): só listar, não cobrar por WhatsApp.`;
  }
  const pix = e.pixEsperando ?? [];
  if (pix.length) {
    const lista = pix.map((p) => `${brlDoLembrete(n(p.valor))}${p.data ? ` de ${p.data}` : ''}`).join(', ');
    return `Este cliente tem Pix esperando no Extrato (${lista}): pode ser este pagamento. `
      + 'Confira no Extrato (Este Pix paga…) antes de cobrar; se for outra coisa, decida a linha lá e cobre depois.';
  }
  if (e.optOut) return 'Este cliente pediu para não receber mensagens no WhatsApp (opt-out). Cobre por outro canal.';
  const digitos = (e.telefone || '').replace(/\D/g, '');
  if (digitos.length < 10) return 'Sem telefone para enviar a cobrança.';
  if (e.horaBrasilia != null && (e.horaBrasilia < HORA_INICIO_COBRANCA || e.horaBrasilia >= HORA_FIM_COBRANCA)) {
    return `Fora do horário de cobrança (${e.horaBrasilia}h; janela ${HORA_INICIO_COBRANCA}–${HORA_FIM_COBRANCA}h em Brasília): `
      + `cliente não recebe cobrança à noite nem de madrugada. Envie a partir das ${HORA_INICIO_COBRANCA}h.`;
  }
  return null;
}

/**
 * O que mudou nas contas desde que a tela abriu, em português; null = nada. `antes`: as contas
 * (id e saldo) que a mensagem mostra; `agora`: as contas relidas do banco, das mesmas OS e do
 * mesmo cliente. Mesmo critério de oQueMudouNaCobrancaConjunta (tool): conjunto e saldo de cada uma.
 */
export function mudancaNasContas(
  antes: Array<{ id: string; saldo: number }>,
  agora: Array<Pick<ContaDoCliente, 'id' | 'status' | 'amount' | 'paid_amount' | 'balance_amount'>>,
): string | null {
  const abertas = (agora || []).filter((c) => saldoDaConta(c) > 0);
  const idsAntes = antes.map((c) => c.id).sort().join('|');
  const idsAgora = abertas.map((c) => c.id).sort().join('|');
  const totalAntes = centavos(antes.reduce((s, c) => s + n(c.saldo), 0));
  const totalAgora = centavos(abertas.reduce((s, c) => s + saldoDaConta(c), 0));
  const fecheEAbra = 'Nada foi enviado: feche e abra o Cobrar juntas de novo para conferir a mensagem.';
  if (idsAntes !== idsAgora) {
    return `As contas em aberto destas OS mudaram desde que a tela abriu (era ${brl(totalAntes)}, agora ${brl(totalAgora)}). ${fecheEAbra}`;
  }
  const mexida = abertas.find((c) => Math.round(saldoDaConta(c) * 100) !== Math.round(n(antes.find((a) => a.id === c.id)?.saldo) * 100));
  if (mexida) return `O saldo das OS mudou desde que a tela abriu (era ${brl(totalAntes)}, agora ${brl(totalAgora)}). ${fecheEAbra}`;
  return null;
}

/** Hash curto e estável (djb2) — só para a chave de idempotência, não é segurança. */
function hashCurto(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return (h >>> 0).toString(36);
}

/**
 * dedupe_key do whatsapp-send: o mesmo cliente, as mesmas contas e o mesmo texto no mesmo dia
 * saem uma vez só (clique duplo, tela e assistente ao mesmo tempo).
 */
export function chaveDoCobrarJuntas(clientId: string, contaIds: string[], dia: string, mensagem: string): string {
  const contas = [...contaIds].sort().join(',');
  return `cobrar-juntas:${clientId}:${dia}:${hashCurto(`${contas}|${mensagem.trim()}`)}`;
}

/** "OS-00045 + OS-00046 — R$ 1.670,00", para o resumo da confirmação. */
export function resumoDoCobrarJuntas(oss: OsParaCobrar[]): string {
  const total = centavos(oss.reduce((s, o) => s + o.saldo, 0));
  return `${oss.map((o) => o.numero_os).join(' + ')} — ${brl(total)}`;
}
