// "Cobrar em lote" da tela (dono, 26/11/2026: "1. A" — o lote ganha a mesma conferência da ficha, com prévia).
//
// Antes: uma mensagem POR CONTA (cliente com 3 contas recebia 3), com o modelo e o valor que a tela tinha, a número
// sem conferência, sem piso, sem olhar a entrada esperando no Extrato, sem opt-out, sem horário e sem registrar nada.
// Agora, como o "cobra todos os vencidos" do assistente: UMA mensagem por cliente (a cobrança do cliente inteiro, só as
// contas com saldo — o mesmo texto do "cobra o Fulano"), as travas da ficha em cada um, quem fica de fora com o motivo,
// uma mensagem por número, no máximo 20 por vez. O envio de cada um passa de novo pelas travas com dado fresco
// (enviarCobrancaDoCliente) e registra a cobrança do dia.
//
// Puro: a tela lê o banco e entrega aqui; os testes leem as frases.
import { buildClientStatement, type StatementItem } from '@/lib/client-statement';
import { normalizePhoneE164 } from '@/lib/masks';
import {
  contaVencida, saldoDaConta, travaDoCobrarJuntas,
} from '../../supabase/functions/_shared/receivables/cobrar-juntas';

/** No máximo 20 clientes por lote, como o lote do assistente. */
export const MAX_CLIENTES_DO_LOTE = 20;

/** Pausa entre um envio e o próximo no Cobrar em lote (o WhatsApp não gosta de rajada). Os testes trocam. */
export const intervaloDoLote = { ms: 2500 };

/** "vencidas": clientes com alguma conta vencida (a mensagem leva tudo que ele tem em aberto); "todas": todo cliente com saldo. */
export type FiltroDoLote = 'vencidas' | 'todas';

export interface ContaParaOLote extends StatementItem {
  id: string;
  client_id: string | null;
}

export interface ClienteParaOLote {
  id: string;
  name?: string | null;
  generico?: boolean | null;
  opt_out_whatsapp?: boolean | null;
  whatsapp?: string | null;
  phone?: string | null;
}

export interface ItemDoLoteDaTela {
  cliente: ClienteParaOLote;
  /** O WhatsApp (ou telefone) do cadastro — o envio relê e manda para ele. */
  telefone: string;
  /** As contas com saldo do cliente, com o saldo mostrado (o envio relê e recusa se mudou). */
  contas: Array<{ id: string; saldo: number }>;
  total: number;
  vencido: number;
  mensagem: string;
}

export interface ForaDoLote {
  cliente: string;
  motivo: string;
}

export interface LoteDaTela {
  vao: ItemDoLoteDaTela[];
  fora: ForaDoLote[];
}

const centavos = (v: number) => Math.round(v * 100) / 100;

/** "às 10h15" em Brasília, para o "já recebeu cobrança hoje". */
function horaDe(iso: string): string {
  return new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' })
    .format(new Date(iso)).replace(':', 'h');
}

export function montarLoteDaTela(p: {
  /** As contas abertas (com saldo) de todos os clientes. */
  contas: ContaParaOLote[];
  clientes: ClienteParaOLote[];
  filtro: FiltroDoLote;
  hoje: string;
  /** app_settings.collection_min_amount (0 = sem piso). */
  piso: number;
  pixKey?: string | null;
  /** Entradas esperando no Extrato, por cliente (lerDinheiroEsperando). */
  pixEsperando: Map<string, Array<{ valor: number; data?: string | null }>>;
  /** Quem já recebeu cobrança hoje, com a hora da última (lerCobradosHoje). */
  cobradosHoje: Map<string, string>;
}): LoteDaTela {
  const porCliente = new Map<string, ContaParaOLote[]>();
  let semCliente = 0;
  for (const c of p.contas) {
    if (!(saldoDaConta(c) > 0)) continue;
    if (!c.client_id) {
      if (p.filtro === 'todas' || contaVencida(c, p.hoje)) semCliente++;
      continue;
    }
    const lista = porCliente.get(c.client_id) ?? [];
    lista.push(c);
    porCliente.set(c.client_id, lista);
  }
  const cadastro = new Map(p.clientes.map((c) => [c.id, c]));

  type Candidato = { clienteId: string; contas: ContaParaOLote[]; total: number; vencido: number };
  const candidatos: Candidato[] = [];
  for (const [clienteId, contas] of porCliente) {
    const vencido = centavos(contas.filter((c) => contaVencida(c, p.hoje)).reduce((s, c) => s + saldoDaConta(c), 0));
    if (p.filtro === 'vencidas' && !(vencido > 0)) continue;
    candidatos.push({ clienteId, contas, total: centavos(contas.reduce((s, c) => s + saldoDaConta(c), 0)), vencido });
  }
  // Quem deve mais vencido primeiro (o que importa cobrar), depois o total e o nome.
  const nome = (id: string) => (cadastro.get(id)?.name || '').trim();
  candidatos.sort((a, b) => b.vencido - a.vencido || b.total - a.total || nome(a.clienteId).localeCompare(nome(b.clienteId)));

  const vao: ItemDoLoteDaTela[] = [];
  const fora: ForaDoLote[] = [];
  const numeros = new Map<string, string>();
  for (const k of candidatos) {
    const cliente = cadastro.get(k.clienteId);
    if (!cliente) {
      fora.push({ cliente: 'cliente', motivo: 'O cadastro do cliente não foi encontrado.' });
      continue;
    }
    const rotulo = (cliente.name || '').trim() || 'cliente';
    const telefone = cliente.whatsapp || cliente.phone || '';
    // As travas da ficha, sem o horário (a tela confere o horário uma vez para o lote; o envio confere de novo).
    const trava = travaDoCobrarJuntas({
      clienteNome: cliente.name,
      generico: cliente.generico,
      optOut: cliente.opt_out_whatsapp,
      piso: p.piso,
      totalEmAberto: k.total,
      pixEsperando: p.pixEsperando.get(k.clienteId) ?? [],
      telefone,
      quantidadeOs: null,
    });
    if (trava) { fora.push({ cliente: rotulo, motivo: trava }); continue; }
    const cobradoAs = p.cobradosHoje.get(k.clienteId);
    if (cobradoAs) { fora.push({ cliente: rotulo, motivo: `Já recebeu cobrança hoje (às ${horaDe(cobradoAs)}).` }); continue; }
    const numero = normalizePhoneE164(telefone);
    const dono = numeros.get(numero);
    if (dono) { fora.push({ cliente: rotulo, motivo: `O mesmo número já recebe a cobrança de ${dono} neste lote.` }); continue; }
    if (vao.length >= MAX_CLIENTES_DO_LOTE) {
      fora.push({ cliente: rotulo, motivo: `Passa do limite de ${MAX_CLIENTES_DO_LOTE} clientes por lote: cobre no próximo.` });
      continue;
    }
    numeros.set(numero, rotulo);
    vao.push({
      cliente,
      telefone,
      contas: k.contas.map((c) => ({ id: c.id, saldo: saldoDaConta(c) })),
      total: k.total,
      vencido: k.vencido,
      mensagem: buildClientStatement({ clientName: cliente.name, items: k.contas, pixKey: p.pixKey, cobranca: true, hoje: p.hoje }),
    });
  }
  if (semCliente > 0) {
    fora.push({
      cliente: semCliente === 1 ? '1 conta' : `${semCliente} contas`,
      motivo: 'Sem cliente do cadastro: ligue a conta a um cliente para cobrar.',
    });
  }
  return { vao, fora };
}
