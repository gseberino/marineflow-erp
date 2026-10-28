// Documentos das diárias: o extrato em PDF (consulta, sem assinatura desde 27/10/2026), o recibo de
// pagamento de serviços que o prestador assina e as linhas do CSV do contador. Puro — sem Supabase,
// sem janela —, para ser testado.
//
// Mora em _shared desde 06/10/2026: a tela (Financeiro › Diárias, "Extrato em PDF") e o assistente
// do WhatsApp ("me manda o extrato do Roberto") montam o MESMO documento — uma fonte só, como o PDF
// do orçamento (pedido do dono: "da mesma forma como o pdf do orçamento"). src/lib/extrato-diarias.ts
// só reexporta este arquivo.
//
// É controle interno de prestação de serviço por dia, não registro de ponto: não há horário de
// entrada e saída, só o dia, a diária e o que foi pago.

export type JornadaNoDocumento = 'inteiro' | 'meio' | 'faltou';
export type EstadoNoDocumento = 'deve' | 'adiantado' | 'quitado' | 'semdias';

// O rótulo do reembolso, o mesmo em todo lugar (resposta 9 do dono, 11/10/2026: "fica confuso
// dependendo de quem está lendo" — "despesas pagas por mim" no recibo, "Reembolsos" solto na tela).
// Quem lê o recibo, o extrato, a planilha da contadora ou a tela entende a mesma coisa. A tela
// (src/lib/extrato-diarias.ts) e o assistente (tools/diarias.ts) importam daqui.
/** Seções e totais: "Reembolso de despesas pagas pelo técnico". */
export const ROTULO_REEMBOLSOS = 'Reembolso de despesas pagas pelo técnico';
/** Uma linha, o selo e a planilha: "Reembolso de despesa paga pelo técnico". */
export const ROTULO_REEMBOLSO = 'Reembolso de despesa paga pelo técnico';

/**
 * A linha da conta corrente como as funções do banco devolvem (conta_corrente_freelancer).
 *
 * `reembolso` (F2b dos comprovantes, 11/10/2026): despesa da empresa que o técnico pagou do
 * bolso, com o comprovante (CMP). Soma a favor dele como o dia (`trabalhado` = o valor, `pago` = 0),
 * `conta` = o código do comprovante ("CMP-00124"), `categoria` e `os` vêm do comprovante. Coberto
 * por um pagamento dividido (diárias + reembolso), `observacao` = "pago em DD/MM".
 */
export interface LinhaDoExtrato {
  data: string;
  tipo: 'dia' | 'pagamento' | 'reembolso';
  id: string;
  jornada: JornadaNoDocumento | null;
  fracao: number | null;
  valor_diaria: number | null;
  extras: number | null;
  descontos: number | null;
  trabalhado: number;
  pago: number;
  descricao: string | null;
  conta: string | null;
  categoria: string | null;
  observacao: string | null;
  os: { id: string; numero: string }[];
  saldo: number;
  /** Pagamento ainda sem lançamento (já desconta): anotado à mão, ou já no banco esperando a fila. */
  aguardando?: boolean;
}

/** O Pix que o banco já trouxe e espera a aprovação na fila (a frase vem do banco na coluna "conta"). */
export const CONTA_FALTA_APROVAR = 'No banco — falta aprovar na fila';
/** Só o anotado à mão é "ainda não confirmado pelo banco"; o que já está na fila saiu de fato. */
const lancadoAMao = (l: Pick<LinhaDoExtrato, 'aguardando' | 'conta'>) => !!l.aguardando && l.conta !== CONTA_FALTA_APROVAR;

export interface ContaDoExtrato {
  favorecido: { id: string; nome: string; desde: string | null; saldo_inicial: number; diaria: number | null };
  de: string | null;
  ate: string | null;
  saldo_anterior: number;
  linhas: LinhaDoExtrato[];
  dias: number;
  /** Só os dias (diária + extras − descontos); os reembolsos vêm à parte. */
  trabalhado: number;
  pago: number;
  /** Reembolsos de comprovantes no período (F2b). Ausente = o banco de antes da F2b = nenhum. */
  reembolsos?: number;
  saldo_final: number;
  estado: EstadoNoDocumento;
}

export interface EmpresaNoDocumento {
  nome: string;
  cnpj: string | null;
  cidade: string | null;
}

export interface FreelancerNoDocumento {
  nome: string;
  documento: string | null;
  pix: string | null;
}

const brl = (v: number) => (Number(v) || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }).replace(/ /g, ' ');
const numero = (v: number) => (Number(v) || 0).toLocaleString('pt-BR', { maximumFractionDigits: 2 });
const dataBR = (d: string) => d.slice(0, 10).split('-').reverse().join('/');
const DIAS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
const diaDaSemana = (d: string) => { const [a, m, x] = d.split('-').map(Number); return DIAS[new Date(Date.UTC(a, m - 1, x)).getUTCDay()]; };
const ROTULO_DA_JORNADA: Record<JornadaNoDocumento, string> = { inteiro: 'Dia inteiro', meio: 'Meio período', faltou: 'Não trabalhou' };

/** No papel, "Faltou" (cabe na coluna e é o que se lê ao assinar); na tela é "Não trabalhou". */
const tipoDoDia = (j: LinhaDoExtrato['jornada']) => (j === 'faltou' ? 'Faltou' : j ? ROTULO_DA_JORNADA[j] : '—');

function esc(v: unknown): string {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
}

/** "06/10/2026 às 18:07", no horário de Brasília — igual no navegador e no servidor (UTC). */
function quandoEmBrasilia(g: Date): string {
  const b = new Date(g.getTime() - 3 * 3600_000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(b.getUTCDate())}/${p(b.getUTCMonth() + 1)}/${b.getUTCFullYear()} às ${p(b.getUTCHours())}:${p(b.getUTCMinutes())}`;
}

/** CPF/CNPJ com a pontuação de costume; outro formato passa como veio. */
export function documentoFormatado(doc: string | null | undefined): string {
  const d = String(doc ?? '').replace(/\D/g, '');
  if (d.length === 11) return `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`;
  if (d.length === 14) return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}/${d.slice(8, 12)}-${d.slice(12)}`;
  return String(doc ?? '');
}

/** "01/09/2026 a 30/09/2026", ou "desde 25/08/2026" quando é o histórico inteiro. */
export function textoDoPeriodo(conta: Pick<ContaDoExtrato, 'de' | 'ate' | 'favorecido'>): string {
  if (conta.de && conta.ate) return `${dataBR(conta.de)} a ${dataBR(conta.ate)}`;
  if (conta.de) return `desde ${dataBR(conta.de)}`;
  return conta.favorecido.desde ? `desde ${dataBR(conta.favorecido.desde)}` : 'todo o histórico';
}

export function nomeDoArquivo(prefixo: string, nome: string, conta: Pick<ContaDoExtrato, 'de' | 'ate'>, ext: string): string {
  const slug = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  const quando = conta.de && conta.ate && conta.de.slice(0, 7) === conta.ate.slice(0, 7) ? conta.de.slice(0, 7)
    : conta.de && conta.ate ? `${conta.de}_${conta.ate}`
    : conta.de ? `desde-${conta.de}` : 'historico';
  return `${[prefixo, slug(nome), quando].filter(Boolean).join('-')}.${ext}`;
}

const ESTADO_NO_PAPEL: Record<EstadoNoDocumento, string> = {
  deve: 'a pagar ao prestador',
  adiantado: 'pago adiantado',
  quitado: 'quitado',
  semdias: 'sem dias lançados',
};

// O que é o extra e o que é o reembolso (resposta 6 do dono, 11/10/2026: o extra de R$ 20 é o
// almoço, pago quando o freelancer traz o próprio). A nota do reembolso só sai quando há reembolso.
const NOTA_DO_EXTRA = 'Extra = o almoço (quando ele traz o próprio) e outros acréscimos combinados do dia.';
const NOTA_DO_REEMBOLSO = `${ROTULO_REEMBOLSOS} = despesa da empresa que ele pagou, com o comprovante (CMP) enviado pelo WhatsApp; a mesma despesa não entra também como extra.`;

/** As linhas de reembolso (comprovante) de uma conta. */
const reembolsosDe = (linhas: LinhaDoExtrato[]) => linhas.filter((l) => l.tipo === 'reembolso');

/**
 * A descrição do reembolso para a tela, o PDF e o recibo: sem o "Reembolso CMP-00124 · " que o banco
 * grava (o código e a palavra já aparecem ao lado — no selo e na coluna Comprovante). O CSV da
 * contadora leva o texto inteiro.
 */
export function descricaoDoReembolso(l: Pick<LinhaDoExtrato, 'descricao'>): string {
  return (l.descricao ?? '').replace(/^Reembolso\s+CMP-\d+\s*(?:·\s*)?/u, '').trim();
}

/** "CMP-00124, CMP-00130" — os códigos dos comprovantes, na ordem das linhas, sem repetir. */
const codigosDe = (linhas: LinhaDoExtrato[]) => [...new Set(linhas.map((l) => l.conta).filter((c): c is string => !!c))].join(', ');

/**
 * O total dos reembolsos: o do banco quando vem (conta corrente e foto do acerto); sem ele (banco
 * de antes da F2b), a soma das linhas. Sem reembolso, os documentos saem exatamente como antes.
 */
const totalDosReembolsos = (informado: number | null | undefined, linhas: LinhaDoExtrato[]) =>
  informado != null ? Number(informado) || 0 : reembolsosDe(linhas).reduce((s, l) => s + (Number(l.trabalhado) || 0), 0);

/** O extrato de um freelancer no período, em A4: consulta, sem assinatura (quem assina é o recibo). */
export function montarExtratoHtml(p: {
  empresa: EmpresaNoDocumento;
  freelancer: FreelancerNoDocumento;
  conta: ContaDoExtrato;
  geradoEm: Date;
}): string {
  const { empresa, freelancer, conta } = p;
  const dias = conta.linhas.filter((l) => l.tipo === 'dia');
  const pagamentos = conta.linhas.filter((l) => l.tipo === 'pagamento');
  const aguardando = pagamentos.some(lancadoAMao);
  // Reembolso de comprovante (F2b): coluna no total e seção própria SÓ quando há — sem ele, o
  // documento é byte a byte o de antes (teste em src/lib/extrato-diarias.test.ts).
  const reembolsos = reembolsosDe(conta.linhas);
  const totalReembolsos = totalDosReembolsos(conta.reembolsos, conta.linhas);
  const comReembolso = totalReembolsos > 0 || reembolsos.length > 0;

  const linhaDoDia = (l: LinhaDoExtrato) => `
      <tr>
        <td>${dataBR(l.data)}</td><td>${diaDaSemana(l.data)}</td>
        <td>${esc(l.os.map((o) => o.numero).join(', '))}</td>
        <td>${esc(l.observacao ?? '')}</td>
        <td>${esc(tipoDoDia(l.jornada))}</td>
        <td class="n">${l.jornada === 'faltou' ? '' : brl(l.valor_diaria ?? 0)}</td>
        <td class="n">${l.extras ? brl(l.extras) : ''}</td>
        <td class="n">${l.descontos ? brl(l.descontos) : ''}</td>
        <td class="n b">${brl(l.trabalhado)}</td>
      </tr>`;
  const linhaDoPagamento = (l: LinhaDoExtrato) => `
      <tr>
        <td>${dataBR(l.data)}</td><td>${esc(lancadoAMao(l) ? 'Pix lançado à mão *' : l.aguardando ? 'Pix (extrato do banco)' : l.conta ?? '')}</td><td>${esc(l.descricao ?? '')}</td>
        <td class="n b">${brl(l.pago)}</td>
      </tr>`;
  const linhaDoReembolso = (l: LinhaDoExtrato) => `
      <tr>
        <td>${dataBR(l.data)}</td><td>${esc(l.conta ?? '')}</td>
        <td>${[descricaoDoReembolso(l), l.categoria ?? ''].filter(Boolean).map(esc).join(' · ')}</td>
        <td>${esc(l.os.map((o) => o.numero).join(', '))}</td>
        <td class="n b">${brl(l.trabalhado)}</td>
      </tr>`;
  const secaoDosReembolsos = reembolsos.length ? `

  <h2>${ROTULO_REEMBOLSOS} (comprovantes)</h2>
  <table>
    <thead><tr><th>Data</th><th>Comprovante</th><th>Descrição</th><th>OS</th><th class="n">Valor</th></tr></thead>
    <tbody>${reembolsos.map(linhaDoReembolso).join('')}</tbody>
    <tfoot><tr><td colspan="4">${reembolsos.length} reembolso(s)</td><td class="n">${brl(totalReembolsos)}</td></tr></tfoot>
  </table>` : '';

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Extrato de diárias — ${esc(freelancer.nome)}</title>
<style>
  @page { size: A4; margin: 12mm; }
  * { box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; color: #10293a; font-size: 10.5px; margin: 0; }
  .topo { display: flex; justify-content: space-between; align-items: flex-end; border-bottom: 2px solid #10293a; padding-bottom: 6px; }
  .topo h1 { margin: 0; font-size: 16px; }
  .topo .emp { font-size: 10px; color: #4b616f; }
  .quem { margin: 10px 0 6px; }
  .quem b { font-size: 14px; }
  .quem span { color: #4b616f; margin-right: 14px; }
  table { width: 100%; border-collapse: collapse; margin-top: 4px; }
  th, td { border: 1px solid #cfd8da; padding: 3px 5px; text-align: left; vertical-align: top; }
  th { background: #eef2f3; font-size: 9.5px; }
  td.n, th.n { text-align: right; white-space: nowrap; }
  td.b { font-weight: bold; }
  h2 { font-size: 11.5px; margin: 12px 0 2px; }
  tfoot td { background: #eef2f3; font-weight: bold; }
  .vazio { color: #7f929c; font-style: italic; }
  .nota { color: #4b616f; font-size: 9.5px; margin-top: 6px; }
  .rodape { margin-top: 18px; color: #7f929c; font-size: 9px; display: flex; justify-content: space-between; }
</style>
</head>
<body>
  <div class="topo">
    <div>
      <h1>Extrato de diárias</h1>
      <div class="emp">Prestação de serviços por dia · ${esc(textoDoPeriodo(conta))}</div>
    </div>
    <div class="emp" style="text-align:right">
      <b>${esc(empresa.nome)}</b><br>${empresa.cnpj ? `CNPJ ${esc(documentoFormatado(empresa.cnpj))}` : ''}
    </div>
  </div>

  <div class="quem">
    <b>${esc(freelancer.nome)}</b><br>
    ${freelancer.documento ? `<span>CPF ${esc(documentoFormatado(freelancer.documento))}</span>` : ''}
    ${conta.favorecido.diaria != null ? `<span>Diária ${brl(conta.favorecido.diaria)}</span>` : ''}
    ${freelancer.pix ? `<span>PIX ${esc(freelancer.pix)}</span>` : ''}
  </div>

  <table>
    <thead><tr>
      <th class="n">${conta.de ? 'Saldo antes do período' : 'Saldo inicial'}</th><th class="n">Diárias</th>
      <th class="n">Trabalhado</th>${comReembolso ? `<th class="n" style="white-space:normal">${ROTULO_REEMBOLSOS}</th>` : ''}<th class="n">Pago</th><th class="n">Saldo no fim do período</th>
    </tr></thead>
    <tbody><tr>
      <td class="n">${brl(conta.saldo_anterior)}</td><td class="n">${numero(conta.dias)}</td>
      <td class="n">${brl(conta.trabalhado)}</td>${comReembolso ? `<td class="n">${brl(totalReembolsos)}</td>` : ''}<td class="n">${brl(conta.pago)}</td>
      <td class="n b">${brl(conta.saldo_final)} (${ESTADO_NO_PAPEL[conta.estado]})</td>
    </tr></tbody>
  </table>

  <h2>Dias trabalhados</h2>
  <table>
    <thead><tr>
      <th>Data</th><th>Dia</th><th>OS</th><th>Serviço / observação</th><th>Tipo</th>
      <th class="n">Diária</th><th class="n">Extras</th><th class="n">Desc.</th><th class="n">Total</th>
    </tr></thead>
    <tbody>${dias.length ? dias.map(linhaDoDia).join('') : '<tr><td colspan="9" class="vazio">Nenhum dia lançado no período.</td></tr>'}</tbody>
    ${dias.length ? `<tfoot><tr><td colspan="8">${numero(conta.dias)} diária(s)</td><td class="n">${brl(conta.trabalhado)}</td></tr></tfoot>` : ''}
  </table>${secaoDosReembolsos}

  <h2>Pagamentos recebidos</h2>
  <table>
    <thead><tr><th>Data</th><th>De onde saiu</th><th>Identificação</th><th class="n">Valor</th></tr></thead>
    <tbody>${pagamentos.length ? pagamentos.map(linhaDoPagamento).join('') : '<tr><td colspan="4" class="vazio">Nenhum pagamento no período.</td></tr>'}</tbody>
    ${pagamentos.length ? `<tfoot><tr><td colspan="3">${pagamentos.length} pagamento(s)</td><td class="n">${brl(conta.pago)}</td></tr></tfoot>` : ''}
  </table>

  <p class="nota">Saldo positivo = valor a pagar ao prestador; negativo = pago adiantado. ${NOTA_DO_EXTRA}${comReembolso ? ` ${NOTA_DO_REEMBOLSO}` : ''}${aguardando ? ' * Pagamento lançado à mão, ainda não confirmado pelo extrato do banco.' : ''}</p>

  <div class="rodape"><span>Extrato para conferência: não é recibo nem quitação (o papel assinado é o recibo de serviços).</span><span>Gerado em ${quandoEmBrasilia(p.geradoEm)}</span></div>
</body>
</html>`;
}

// ── Recibo do acerto (06/10/2026) ───────────────────────────────────────────────────────────
// O acerto fecha o período ao pagar (acertos_diarias, migration 20261006220000). O recibo é dele:
// número sequencial, competência (de–até), os dias, os vales já pagos, o valor deste acerto por
// extenso e a assinatura de quem recebe — o que o art. 320 do Código Civil pede de uma quitação.

/** O acerto como a tabela acertos_diarias guarda (a foto do período). */
export interface AcertoNoDocumento {
  numero: number;
  de: string;
  ate: string;
  saldo_anterior: number;
  dias: number;
  trabalhado: number;
  pago_no_periodo: number;
  valor_do_acerto: number;
  /** Reembolsos de comprovantes do período, na foto do acerto (F2b). Ausente = nenhum. */
  reembolsos?: number;
}

const UNIDADES = ['', 'um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove', 'dez', 'onze', 'doze', 'treze',
  'quatorze', 'quinze', 'dezesseis', 'dezessete', 'dezoito', 'dezenove'];
const DEZENAS = ['', '', 'vinte', 'trinta', 'quarenta', 'cinquenta', 'sessenta', 'setenta', 'oitenta', 'noventa'];
const CENTENAS = ['', 'cento', 'duzentos', 'trezentos', 'quatrocentos', 'quinhentos', 'seiscentos', 'setecentos', 'oitocentos', 'novecentos'];

/** 0–999 por extenso ("cento e vinte e três"). */
function ateMil(n: number): string {
  if (n === 0) return '';
  if (n === 100) return 'cem';
  const c = Math.floor(n / 100);
  const resto = n % 100;
  const partes: string[] = [];
  if (c) partes.push(CENTENAS[c]);
  if (resto < 20) { if (resto) partes.push(UNIDADES[resto]); }
  else {
    partes.push(DEZENAS[Math.floor(resto / 10)] + (resto % 10 ? ` e ${UNIDADES[resto % 10]}` : ''));
  }
  return partes.join(' e ');
}

/** Valor em reais por extenso: 1.250,50 → "mil, duzentos e cinquenta reais e cinquenta centavos". */
export function valorPorExtenso(valor: number): string {
  const centavosTotais = Math.round(Math.abs(Number(valor) || 0) * 100);
  const reais = Math.floor(centavosTotais / 100);
  const centavos = centavosTotais % 100;
  const milhoes = Math.floor(reais / 1_000_000);
  const milhares = Math.floor((reais % 1_000_000) / 1000);
  const unidades = reais % 1000;
  // O "e" entre grupos só quando o grupo seguinte é redondo ou menor que cem: "mil e cem",
  // "mil e cinquenta", mas "mil duzentos e cinquenta".
  const comE = (n: number) => n < 100 || n % 100 === 0;
  let texto = '';
  const juntar = (g: string, sep: string) => { texto = texto ? `${texto}${sep}${g}` : g; };
  if (milhoes) juntar(`${ateMil(milhoes)} ${milhoes === 1 ? 'milhão' : 'milhões'}`, '');
  if (milhares) juntar(milhares === 1 ? 'mil' : `${ateMil(milhares)} mil`, unidades === 0 && comE(milhares) ? ' e ' : ', ');
  if (unidades) juntar(ateMil(unidades), comE(unidades) ? ' e ' : ' ');
  const deReais = reais > 0 && unidades === 0 && milhares === 0 && milhoes > 0 ? ' de' : '';
  const parteReais = reais ? `${texto}${deReais} ${reais === 1 ? 'real' : 'reais'}` : '';
  const parteCentavos = centavos ? `${ateMil(centavos)} ${centavos === 1 ? 'centavo' : 'centavos'}` : '';
  if (parteReais && parteCentavos) return `${parteReais} e ${parteCentavos}`;
  return parteReais || parteCentavos || 'zero real';
}

const MESES_POR_EXTENSO = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
const dataPorExtenso = (g: Date) => {
  const b = new Date(g.getTime() - 3 * 3600_000);
  return `${b.getUTCDate()} de ${MESES_POR_EXTENSO[b.getUTCMonth()]} de ${b.getUTCFullYear()}`;
};

/** "0001" — o número do recibo como vai no papel e no nome do arquivo. */
export const numeroDoRecibo = (n: number) => String(n).padStart(4, '0');

/**
 * O recibo do acerto, em A4. As linhas (dias, reembolsos e vales) vêm da conta corrente do MESMO
 * período do acerto (conta_corrente_freelancer de–até); os totais vêm da foto do acerto, que não muda.
 * Reembolso de comprovante (F2b) só aparece quando há: sem ele, o recibo é o de antes.
 */
export function montarReciboHtml(p: {
  empresa: EmpresaNoDocumento;
  freelancer: FreelancerNoDocumento;
  acerto: AcertoNoDocumento;
  linhas: LinhaDoExtrato[];
  geradoEm: Date;
}): string {
  const { empresa, freelancer, acerto } = p;
  const dias = p.linhas.filter((l) => l.tipo === 'dia');
  const vales = p.linhas.filter((l) => l.tipo === 'pagamento');
  const reembolsos = reembolsosDe(p.linhas);
  // O total é o da foto do acerto (não muda depois de fechado); os códigos, das linhas do período.
  const totalReembolsos = totalDosReembolsos(acerto.reembolsos, p.linhas);
  const codigos = codigosDe(reembolsos);
  const aReceber = acerto.valor_do_acerto > 0;
  const competencia = `${dataBR(acerto.de)} a ${dataBR(acerto.ate)}`;
  const cpf = freelancer.documento ? `, CPF ${esc(documentoFormatado(freelancer.documento))}` : '';

  const linhaDoDia = (l: LinhaDoExtrato) => `
      <tr><td>${dataBR(l.data)}</td><td>${diaDaSemana(l.data)}</td><td>${esc(tipoDoDia(l.jornada))}</td>
        <td>${esc(l.os.map((o) => o.numero).join(', '))}</td><td class="n">${brl(l.trabalhado)}</td></tr>`;
  const linhaDoVale = (l: LinhaDoExtrato) => `
      <tr><td>${dataBR(l.data)}</td><td>${esc(l.descricao ?? '')}${lancadoAMao(l) ? ' *' : ''}</td><td class="n">${brl(l.pago)}</td></tr>`;
  const linhaDoReembolso = (l: LinhaDoExtrato) => `
      <tr><td>${dataBR(l.data)}</td><td>${esc(l.conta ?? '')}</td><td>${esc(descricaoDoReembolso(l))}</td><td class="n">${brl(l.trabalhado)}</td></tr>`;
  // O recibo é a declaração do prestador ("Recebi…"), mas quem mais lê é a contadora: o reembolso
  // vai com o rótulo de todo lugar ("…pagas pelo técnico"), nunca "por mim" (resposta 9 do dono).
  const quaisComprovantes = codigos ? ` (${esc(codigos)})` : '';
  const rotuloComCodigos = `${ROTULO_REEMBOLSOS.toLowerCase()}${quaisComprovantes}`;
  const reembolsoNaQuitacao = totalReembolsos > 0
    ? ` e ao ${rotuloComCodigos}: ${brl(totalReembolsos)}` : '';
  // sem valor a receber, o reembolso JÁ foi compensado neste acerto (nada "a reembolsar")
  const reembolsoNaDeclaracao = totalReembolsos > 0
    ? `, com o ${rotuloComCodigos}: ${brl(totalReembolsos)}, compensado neste acerto,` : '';
  const secaoDosReembolsos = reembolsos.length ? `

  <h2>${ROTULO_REEMBOLSOS}</h2>
  <table>
    <thead><tr><th>Data</th><th>Comprovante</th><th>Descrição</th><th class="n">Valor</th></tr></thead>
    <tbody>${reembolsos.map(linhaDoReembolso).join('')}</tbody>
  </table>` : '';
  const linhaDoAcertoReembolsos = totalReembolsos > 0
    ? `\n    <tr><td>(+) ${ROTULO_REEMBOLSOS}${quaisComprovantes}</td><td class="n">${brl(totalReembolsos)}</td></tr>` : '';

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Recibo de diárias nº ${numeroDoRecibo(acerto.numero)} — ${esc(freelancer.nome)}</title>
<style>
  @page { size: A4; margin: 14mm; }
  * { box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; color: #10293a; font-size: 11px; margin: 0; }
  .topo { display: flex; justify-content: space-between; align-items: flex-end; border-bottom: 2px solid #10293a; padding-bottom: 6px; }
  .topo h1 { margin: 0; font-size: 18px; letter-spacing: .5px; }
  .topo .emp { font-size: 10px; color: #4b616f; text-align: right; }
  .valor { font-size: 20px; font-weight: bold; text-align: right; margin: 10px 0 4px; }
  .texto { font-size: 12px; line-height: 1.6; margin: 8px 0 12px; text-align: justify; }
  table { width: 100%; border-collapse: collapse; margin-top: 4px; }
  th, td { border: 1px solid #cfd8da; padding: 3px 5px; text-align: left; }
  th { background: #eef2f3; font-size: 10px; }
  td.n, th.n { text-align: right; white-space: nowrap; }
  h2 { font-size: 11.5px; margin: 12px 0 2px; }
  .conta td { border: none; padding: 2px 5px; }
  .conta tr.total td { border-top: 1px solid #10293a; font-weight: bold; font-size: 12px; }
  .nota { color: #4b616f; font-size: 9.5px; margin-top: 6px; }
  .local { margin-top: 26px; }
  .assinatura { margin: 46px auto 0; width: 60%; border-top: 1px solid #4b616f; padding-top: 4px; text-align: center; font-size: 10.5px; page-break-inside: avoid; }
  .rodape { margin-top: 18px; color: #7f929c; font-size: 9px; display: flex; justify-content: space-between; }
</style>
</head>
<body>
  <div class="topo">
    <div><h1>RECIBO DE DIÁRIAS Nº ${numeroDoRecibo(acerto.numero)}</h1><div class="emp" style="text-align:left">Competência: ${competencia}</div></div>
    <div class="emp"><b>${esc(empresa.nome)}</b><br>${empresa.cnpj ? `CNPJ ${esc(documentoFormatado(empresa.cnpj))}` : ''}</div>
  </div>

  <div class="valor">${aReceber ? brl(acerto.valor_do_acerto) : 'Sem valor a receber'}</div>

  <p class="texto">${aReceber
    ? `Recebi de <b>${esc(empresa.nome)}</b> a importância de <b>${brl(acerto.valor_do_acerto)}</b> (${esc(valorPorExtenso(acerto.valor_do_acerto))}), referente ao acerto de ${numero(acerto.dias)} diária(s) de prestação de serviços no período de ${competencia}${reembolsoNaQuitacao}, já descontados os valores recebidos antecipadamente, conforme o detalhamento abaixo, dando plena quitação do período.`
    : `Declaro que, no período de ${competencia}, prestei ${numero(acerto.dias)} diária(s) de serviço a <b>${esc(empresa.nome)}</b>${reembolsoNaDeclaracao} e já recebi antecipadamente ${brl(acerto.pago_no_periodo)}, ficando ${acerto.valor_do_acerto < 0 ? `um adiantamento de ${brl(-acerto.valor_do_acerto)} a compensar em dias futuros` : 'o período quitado'}.`}</p>

  <h2>Dias trabalhados</h2>
  <table>
    <thead><tr><th>Data</th><th>Dia</th><th>Tipo</th><th>OS</th><th class="n">Valor</th></tr></thead>
    <tbody>${dias.length ? dias.map(linhaDoDia).join('') : '<tr><td colspan="5">Nenhum dia no período.</td></tr>'}</tbody>
  </table>${secaoDosReembolsos}

  ${vales.length ? `<h2>Vales e adiantamentos já pagos no período</h2>
  <table>
    <thead><tr><th>Data</th><th>Identificação</th><th class="n">Valor</th></tr></thead>
    <tbody>${vales.map(linhaDoVale).join('')}</tbody>
  </table>` : ''}

  <h2>Acerto</h2>
  <table class="conta">
    ${acerto.saldo_anterior ? `<tr><td>${acerto.saldo_anterior > 0 ? 'Saldo a receber de antes do período' : 'Adiantamento de antes do período'}</td><td class="n">${brl(Math.abs(acerto.saldo_anterior))}</td></tr>` : ''}
    <tr><td>Trabalhado no período (${numero(acerto.dias)} diária(s))</td><td class="n">${brl(acerto.trabalhado)}</td></tr>${linhaDoAcertoReembolsos}
    <tr><td>(−) Vales e adiantamentos já pagos</td><td class="n">${brl(acerto.pago_no_periodo)}</td></tr>
    <tr class="total"><td>${aReceber ? 'Valor deste recibo' : 'Saldo'}</td><td class="n">${brl(acerto.valor_do_acerto)}</td></tr>
  </table>
  ${vales.some(lancadoAMao) ? '<p class="nota">* Pix lançado à mão, ainda não confirmado pelo extrato do banco quando o acerto foi fechado.</p>' : ''}
  ${freelancer.pix ? `<p class="nota">Chave Pix do prestador: ${esc(freelancer.pix)}</p>` : ''}

  <p class="local">${esc(empresa.cidade || '')}${empresa.cidade ? ', ' : ''}${dataPorExtenso(p.geradoEm)}.</p>
  <div class="assinatura">${esc(freelancer.nome)}${cpf}</div>

  <div class="rodape"><span>Prestação de serviços por dia · acerto nº ${numeroDoRecibo(acerto.numero)}</span><span>Gerado em ${quandoEmBrasilia(p.geradoEm)}</span></div>
</body>
</html>`;
}

// ── Recibo de pagamento de serviços (F2, 27/10/2026) ────────────────────────────────────────
// O papel que o prestador assina, aprovado pelo dono na revisão de 24/10 (protótipo v3): sai no Pix
// que zera a conta e é montado SÓ da foto congelada no banco (acertos_diarias.documento, com hash) —
// reimprimir o nº N dá sempre o mesmo papel. Uma conta só, de cima para baixo, até "Pago neste
// acerto, por Pix"; depois a lista dos serviços e dos pagamentos parciais; por fim a declaração e a
// assinatura. Nada sai como "a informar": o que não há (NIT, E2E, chave Pix) simplesmente não sai.
// Quadro de INSS: só depois da resposta da contadora (portão F0J da revisão).

/** A foto que fechar_acerto_diarias grava em acertos_diarias.documento (migration 20261027180000). */
export interface DocumentoDoRecibo {
  versao: number;
  empresa: { nome: string; cnpj: string | null; endereco: string | null; bairro: string | null; cidade: string | null; uf: string | null };
  prestador: { id: string; nome: string; cpf: string | null; nit: string | null; pix: string | null };
  servico: string;
  diaria: number | null;
  pix: { id: string; data: string; valor: number; conta: string | null; e2e: string | null; pelo_socio: string | null };
  de: string;
  ate: string;
  pagos_ate: string;
  saldo_anterior: number;
  dias: number;
  trabalhado: number;
  reembolsos: number;
  /** Tudo o que ele recebeu no recibo, com o Pix de quitação. */
  pago: number;
  linhas: Array<LinhaDoExtrato & { quitacao?: boolean }>;
}

/** O aviso enquanto o dono não liberou o recibo (contrato, contadora e advogado: portão F0J). */
export const AVISO_RECIBO_EM_CONFERENCIA =
  'Documento de conferência: ainda não vale como recibo. Falta o contrato de prestação de serviços e a revisão da contadora e do advogado.';

const SOCIO = /^Bolso de\s+/i;
/** "R$ 160" quando é redondo (cabe na linha do cabeçalho); com centavos, o valor inteiro. */
const brlCurto = (v: number) => (Number.isInteger(v) ? `R$ ${numero(v)}` : brl(v));
const quantas = (n: number, um: string, varios: string) => `${numero(n)} ${n === 1 ? um : varios}`;

export function montarReciboDeServicosHtml(p: {
  numero: number;
  documento: DocumentoDoRecibo;
  /** Falso enquanto o dono não liberar: o papel sai com o aviso de conferência. */
  liberado: boolean;
  geradoEm: Date;
}): string {
  const d = p.documento;
  const n = numeroDoRecibo(p.numero);
  // Dia sem diária (fração 0) não vai para a lista de serviços (F5: "falta" não se lança mais), mas um
  // adicional ou desconto lançado nele continua na conta.
  const todosOsDias = d.linhas.filter((l) => l.tipo === 'dia');
  const dias = todosOsDias.filter((l) => (Number(l.fracao) || 0) > 0);
  const reembolsos = d.linhas.filter((l) => l.tipo === 'reembolso');
  const parciais = d.linhas.filter((l) => l.tipo === 'pagamento' && !l.quitacao);
  const inteiros = dias.filter((l) => Number(l.fracao) === 1);
  const meios = dias.filter((l) => Number(l.fracao) === 0.5);
  const base = dias.reduce((s, l) => s + (Number(l.fracao) || 0) * (Number(l.valor_diaria) || 0), 0);
  const adicionais = todosOsDias.filter((l) => (Number(l.extras) || 0) > 0);
  const descontos = todosOsDias.filter((l) => (Number(l.descontos) || 0) > 0);
  const somaParciais = parciais.reduce((s, l) => s + (Number(l.pago) || 0), 0);
  const anterior = Number(d.saldo_anterior) || 0;
  const pix = Number(d.pix.valor) || 0;
  // O que ele tinha a receber; o adiantamento de antes entra do lado do que já recebeu.
  const devido = Math.max(anterior, 0) + (Number(d.trabalhado) || 0) + (Number(d.reembolsos) || 0);
  const jaRecebido = somaParciais + Math.max(-anterior, 0);
  const socios = [...new Set(parciais.map((l) => l.conta ?? '').filter((c) => SOCIO.test(c)).map((c) => c.replace(SOCIO, '')))];
  const pelaEmpresa = d.pix.pelo_socio ? `feito por ${esc(d.pix.pelo_socio)} em nome da empresa` : 'da empresa';
  const precos = [...new Set(dias.map((l) => Number(l.valor_diaria) || 0))];
  const formula = precos.length === 1
    ? ` <span class="det">(${[inteiros.length ? `${inteiros.length} × ${numero(precos[0])}` : '', meios.length ? `${meios.length} × ${numero(precos[0] / 2)}` : '']
      .filter(Boolean).join(' + ')})</span>` : '';
  const qtd = [inteiros.length ? quantas(inteiros.length, 'diária', 'diárias') : '', meios.length ? quantas(meios.length, 'meia diária', 'meias diárias') : '']
    .filter(Boolean).join(' e ') || 'Nenhuma diária';
  const motivo = (l: LinhaDoExtrato) => (l.observacao ? ` <span class="det">(${esc(l.observacao)})</span>` : '');
  const linhaDaConta = (op: string, texto: string, valor: number) =>
    `<tr><td><span class="op">${op}</span>${texto}</td><td class="n">${brl(valor)}</td></tr>`;
  const conta = [
    anterior > 0.005 ? linhaDaConta('', `Saldo a receber de antes de ${dataBR(d.de)}`, anterior) : '',
    anterior < -0.005 ? linhaDaConta('−', `Adiantamento recebido antes de ${dataBR(d.de)}`, -anterior) : '',
    dias.length ? linhaDaConta('+', `${qtd}${formula}`, base) : '',
    ...adicionais.map((l) => linhaDaConta('+', `Adicional em ${dataBR(l.data).slice(0, 5)}${motivo(l)}`, Number(l.extras))),
    ...descontos.map((l) => linhaDaConta('−', `Desconto em ${dataBR(l.data).slice(0, 5)}${motivo(l)}`, Number(l.descontos))),
    reembolsos.length ? linhaDaConta('+', `${ROTULO_REEMBOLSOS} <span class="det">(${esc(codigosDe(reembolsos))})</span>`, Number(d.reembolsos)) : '',
    parciais.length ? linhaDaConta('−', `Pagamentos parciais já recebidos <span class="det">(${parciais.length}, lista abaixo)</span>`, somaParciais) : '',
  ].join('');
  const identificacao = d.pix.e2e ? ` · identificação ${esc(d.pix.e2e)}` : d.pix.conta ? ` · ${esc(d.pix.conta)}` : '';
  const diaDoServico = (l: LinhaDoExtrato) =>
    `<li><b>${dataBR(l.data).slice(0, 5)}</b> ${Number(l.fracao) === 1 ? 'diária' : 'meia diária'}${(Number(l.extras) || 0) > 0 ? ` <span class="mais">+ ${brl(Number(l.extras))}</span>` : ''}${(Number(l.descontos) || 0) > 0 ? ` <span class="menos">− ${brl(Number(l.descontos))}</span>` : ''}${l.os.length ? ` <span class="os">${esc(l.os.map((o) => o.numero).join(', '))}</span>` : ''}</li>`;
  const pagamento = (l: LinhaDoExtrato) =>
    `<li><b>${dataBR(l.data).slice(0, 5)}</b>${SOCIO.test(l.conta ?? '') ? '<span class="soc">pelo sócio</span>' : ''} <span class="v">${brl(Number(l.pago))}</span></li>`;
  const reembolso = (l: LinhaDoExtrato) =>
    `<li><b>${dataBR(l.data).slice(0, 5)}</b> <span class="os">${esc(l.conta ?? '')}</span> <span class="v">${brl(Number(l.trabalhado))}</span></li>`;
  const porQue = [anterior > 0.005 ? 'pelo saldo de antes' : '', reembolsos.length ? `pelo ${ROTULO_REEMBOLSOS.toLowerCase()}` : '']
    .filter(Boolean).join(' e ');
  const recebimentos = [
    parciais.length ? `${brl(somaParciais)} nos ${parciais.length} pagamentos parciais listados, feitos por conta destes serviços${socios.length ? ` (os marcados “pelo sócio” foram feitos por ${socios.map(esc).join(' e ')} em nome da empresa)` : ''}` : '',
    anterior < -0.005 ? `${brl(-anterior)} adiantados antes de ${dataBR(d.de)}` : '',
  ].filter(Boolean);
  const declaracao = `Declaro que prestei à <b>${esc(d.empresa.nome)}</b>${d.empresa.cnpj ? `, CNPJ ${esc(documentoFormatado(d.empresa.cnpj))}` : ''}, como autônomo, os serviços listados neste recibo, de ${dataBR(d.de)} a ${dataBR(d.ate)}. Por eles${porQue ? ` e ${porQue}` : ''}, eu tinha a receber <b>${brl(devido)} (${esc(valorPorExtenso(devido))})</b>, que recebi por inteiro: ${recebimentos.length ? `${recebimentos.join(', ')}, e ` : ''}<b>${brl(pix)} (${esc(valorPorExtenso(pix))})</b> no Pix ${pelaEmpresa} de ${dataBR(d.pix.data)}${d.pix.e2e ? `, identificação ${esc(d.pix.e2e)}` : ''}. Nada mais tenho a receber pelos serviços prestados até ${dataBR(d.ate)}.`;
  const cidade = [d.empresa.cidade, d.empresa.uf].filter(Boolean).join('/');
  const cpf = d.prestador.cpf ? documentoFormatado(d.prestador.cpf) : '';
  // Sem o "jaRecebido" a conta não fecha: o banco só fecha com saldo zero, mas o papel confere de novo.
  const fecha = Math.abs(devido - jaRecebido - pix) < 0.005;

  return `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<title>Recibo de serviços nº ${n} — ${esc(d.prestador.nome)}</title>
<style>
  @page { size: A4; margin: 12mm; }
  * { box-sizing: border-box; }
  body { margin: 0; color: #1a1f2b; font: 12px/1.38 "Segoe UI", Arial, Helvetica, sans-serif; }
  .aviso { font-size: 10px; color: #8a5a00; border: 1px dashed #c9a55a; border-radius: 6px; padding: 4px 8px; margin-bottom: 7px; }
  header { display: flex; justify-content: space-between; align-items: flex-end; gap: 16px; border-bottom: 2px solid #1a1f2b; padding-bottom: 7px; }
  h1 { font-size: 19px; margin: 0; }
  .sub { color: #5b6474; margin-top: 2px; }
  .emp { text-align: right; color: #5b6474; font-size: 10.5px; line-height: 1.4; }
  .emp b { color: #1a1f2b; font-size: 12px; }
  .quem { margin: 8px 0 10px; display: grid; grid-template-columns: 1.45fr 1fr 1fr; gap: 5px 18px; }
  .rot { display: block; font-size: 9.5px; color: #5b6474; text-transform: uppercase; letter-spacing: .4px; }
  .val { font-size: 12px; font-weight: 600; }
  .conta { width: 100%; border-collapse: collapse; background: #f3f5f8; font-size: 13.5px; }
  .conta td { padding: 4px 14px; }
  .conta td.n { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
  .op { display: inline-block; width: 16px; color: #5b6474; font-weight: 700; }
  .det { color: #5b6474; font-size: 11.5px; }
  .conta .total td { border-top: 2px solid #1a1f2b; font-size: 17px; font-weight: 700; color: #0b3a66; padding-top: 7px; padding-bottom: 1px; }
  .conta .pix td { font-size: 10.5px; color: #5b6474; padding-top: 0; padding-bottom: 7px; }
  h2 { font-size: 11px; text-transform: uppercase; letter-spacing: .5px; color: #5b6474; margin: 10px 0 3px; }
  ul.g { list-style: none; margin: 0; padding: 0; display: grid; gap: 0 14px; grid-template-columns: repeat(4, 1fr); }
  ul.g li { padding: 1.5px 0; border-bottom: 1px solid #d9dde4; font-variant-numeric: tabular-nums; }
  ul.g li b { font-weight: 600; margin-right: 4px; }
  .mais { color: #0b3a66; font-weight: 600; }
  .menos { color: #8a2b2b; font-weight: 600; }
  .os, .soc { color: #5b6474; font-size: 10px; margin-left: 4px; }
  .v { float: right; }
  .soma { text-align: right; font-weight: 700; margin-top: 2px; }
  .bloco { break-inside: avoid; page-break-inside: avoid; margin-top: 12px; border: 1.5px solid #1a1f2b; border-radius: 8px; padding: 11px 15px 10px; }
  .bloco p { margin: 0 0 7px; font-size: 12px; line-height: 1.48; }
  .fim { display: flex; justify-content: space-between; align-items: flex-end; gap: 20px; margin-top: 18px; }
  .data { font-size: 12px; white-space: nowrap; padding-bottom: 16px; }
  .assina { flex: 1; border-top: 1px solid #1a1f2b; text-align: center; padding-top: 4px; font-size: 12px; }
  .assina small { color: #5b6474; }
  footer { margin-top: 6px; color: #5b6474; font-size: 10px; display: flex; justify-content: space-between; gap: 12px; }
</style></head>
<body>
  ${p.liberado ? '' : `<div class="aviso">${AVISO_RECIBO_EM_CONFERENCIA}</div>`}
  ${fecha ? '' : '<div class="aviso">A conta deste recibo não fecha: não imprima, reabra o acerto e confira.</div>'}
  <header>
    <div><h1>Recibo de pagamento de serviços nº ${n}</h1><div class="sub">Serviços de ${dataBR(d.de)} a ${dataBR(d.ate)}</div></div>
    <div class="emp"><b>${esc(d.empresa.nome)}</b>${d.empresa.cnpj ? `<br>CNPJ ${esc(documentoFormatado(d.empresa.cnpj))}` : ''}${d.empresa.endereco ? `<br>${esc(d.empresa.endereco)}` : ''}${d.empresa.bairro || cidade ? `<br>${[d.empresa.bairro, cidade].filter(Boolean).map(esc).join(' · ')}` : ''}</div>
  </header>
  <div class="quem">
    <div><span class="rot">Prestador (autônomo)</span><span class="val">${esc(d.prestador.nome)}</span></div>
    <div><span class="rot">CPF</span><span class="val">${esc(cpf)}</span></div>
    ${d.prestador.nit ? `<div><span class="rot">NIT/PIS</span><span class="val">${esc(d.prestador.nit)}</span></div>` : '<div></div>'}
    <div><span class="rot">Serviço</span><span class="val">${esc(d.servico)}</span></div>
    ${d.diaria != null ? `<div><span class="rot">Valor combinado</span><span class="val">diária ${brlCurto(Number(d.diaria))} · meia diária ${brlCurto(Number(d.diaria) / 2)}</span></div>` : ''}
    ${d.prestador.pix ? `<div><span class="rot">Chave Pix do prestador</span><span class="val">${esc(d.prestador.pix)}</span></div>` : ''}
  </div>
  <table class="conta">
    ${conta}
    <tr class="total"><td><span class="op">=</span>Pago neste acerto, por Pix</td><td class="n">${brl(pix)}</td></tr>
    <tr class="pix"><td colspan="2"><span class="op"></span>Pix de ${dataBR(d.pix.data)}${identificacao}</td></tr>
  </table>
  ${dias.length ? `<h2>Serviços prestados</h2>
  <ul class="g">${dias.map(diaDoServico).join('')}</ul>` : ''}
  ${reembolsos.length ? `<h2>${ROTULO_REEMBOLSOS}</h2>
  <ul class="g">${reembolsos.map(reembolso).join('')}</ul>` : ''}
  ${parciais.length ? `<h2>Pagamentos parciais já recebidos</h2>
  <ul class="g">${parciais.map(pagamento).join('')}</ul>
  <div class="soma">${parciais.length} ${parciais.length === 1 ? 'pagamento' : 'pagamentos'} · ${brl(somaParciais)}</div>` : ''}
  <div class="bloco">
    <p>${declaracao}</p>
    <p>O original assinado fica com a empresa; recebo uma cópia.</p>
    <div class="fim">
      <div class="data">${esc(cidade || '')}${cidade ? ', ' : ''}____/____/________</div>
      <div class="assina">${esc(d.prestador.nome)}<br><small>${cpf ? `CPF ${esc(cpf)} · ` : ''}assinatura e data de próprio punho</small></div>
    </div>
  </div>
  <footer><span>Original na pasta do prestador, guardado por 10 anos.</span><span>Recibo nº ${n} · gerado em ${quandoEmBrasilia(p.geradoEm)}</span></footer>
</body></html>`;
}

// ── CSV do contador ─────────────────────────────────────────────────────────────────────────

export interface LinhaDoCsv {
  data: string;
  tipo: string;
  freelancer: string;
  cpf: string;
  jornada: string;
  diarias: string;
  valor_diaria: string;
  extras: string;
  descontos: string;
  trabalhado: string;
  pago: string;
  conta: string;
  categoria: string;
  os: string;
  observacao: string;
  /** Reembolso de comprovante (F2b): o valor; vazio nas outras linhas. Coluna no FIM do arquivo. */
  reembolso: string;
}

const dec = (v: number | null | undefined) => (v == null ? '' : (Number(v) || 0).toFixed(2).replace('.', ','));

/** Ordem no mesmo dia: o dia, depois o reembolso (os dois a favor dele), depois o pagamento. */
const ORDEM_NO_DIA: Record<LinhaDoExtrato['tipo'], number> = { dia: 0, reembolso: 1, pagamento: 2 };

/**
 * Todos os dias, reembolsos e pagamentos das contas, em ordem de data (no mesmo dia: dia, reembolso,
 * pagamento). O reembolso leva o código do comprovante em "Conta de origem" e o valor na última
 * coluna ("Reembolso de despesa paga pelo técnico").
 */
export function linhasDoCsv(contas: Array<{ conta: ContaDoExtrato; documento: string | null }>): LinhaDoCsv[] {
  const linhas: Array<LinhaDoCsv & { _ordem: string }> = [];
  for (const { conta, documento } of contas) {
    for (const l of conta.linhas) {
      const dia = l.tipo === 'dia';
      const reembolso = l.tipo === 'reembolso';
      linhas.push({
        _ordem: `${l.data}|${ORDEM_NO_DIA[l.tipo] ?? 2}|${conta.favorecido.nome}`,
        data: dataBR(l.data),
        tipo: dia ? 'Diária' : reembolso ? ROTULO_REEMBOLSO : lancadoAMao(l) ? 'Pagamento (aguardando o banco)' : l.aguardando ? 'Pagamento (falta aprovar na fila)' : 'Pagamento',
        freelancer: conta.favorecido.nome,
        cpf: documentoFormatado(documento),
        jornada: dia ? tipoDoDia(l.jornada) : '',
        diarias: dia ? dec(l.fracao).replace(/,00$/, '').replace(/0$/, '') : '',
        valor_diaria: dia ? dec(l.valor_diaria) : '',
        extras: dia ? dec(l.extras) : '',
        descontos: dia ? dec(l.descontos) : '',
        trabalhado: dia ? dec(l.trabalhado) : '',
        pago: dia || reembolso ? '' : dec(l.pago),
        conta: dia ? '' : l.conta ?? '',
        categoria: dia ? '' : l.categoria ?? '',
        os: l.os.map((o) => o.numero).join(', '),
        observacao: dia ? l.observacao ?? '' : l.descricao ?? '',
        reembolso: reembolso ? dec(l.trabalhado) : '',
      });
    }
  }
  return linhas.sort((a, b) => a._ordem.localeCompare(b._ordem)).map(({ _ordem: _, ...resto }) => resto);
}

export const COLUNAS_DO_CSV: Array<{ header: string; key: keyof LinhaDoCsv }> = [
  { header: 'Data', key: 'data' },
  { header: 'Tipo', key: 'tipo' },
  { header: 'Freelancer', key: 'freelancer' },
  { header: 'CPF', key: 'cpf' },
  { header: 'Tipo do dia', key: 'jornada' },
  { header: 'Diárias', key: 'diarias' },
  { header: 'Valor da diária', key: 'valor_diaria' },
  { header: 'Extras', key: 'extras' },
  { header: 'Descontos', key: 'descontos' },
  { header: 'Trabalhado', key: 'trabalhado' },
  { header: 'Pago', key: 'pago' },
  { header: 'Conta de origem', key: 'conta' },
  { header: 'Categoria', key: 'categoria' },
  { header: 'OS', key: 'os' },
  { header: 'Observação / identificação', key: 'observacao' },
  // F2b (11/10/2026): coluna nova À DIREITA, para a planilha da contadora não mudar de lugar; com o
  // rótulo de todo lugar (resposta 9 do dono).
  { header: ROTULO_REEMBOLSO, key: 'reembolso' },
];
