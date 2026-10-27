// Documentos das diárias: o extrato em PDF (para imprimir e o freelancer assinar no papel) e as
// linhas do CSV do contador. Puro — sem Supabase, sem janela —, para ser testado.
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

/** O extrato de um freelancer no período, em A4, com as duas linhas de assinatura. */
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
  .assinaturas { display: flex; justify-content: space-between; gap: 30px; margin-top: 42px; page-break-inside: avoid; }
  .assinaturas div { flex: 1; border-top: 1px solid #4b616f; padding-top: 4px; text-align: center; font-size: 10px; }
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

  <div class="assinaturas">
    <div>${esc(empresa.nome)}</div>
    <div>${esc(freelancer.nome)}${freelancer.documento ? `<br>CPF ${esc(documentoFormatado(freelancer.documento))}` : ''}</div>
  </div>

  <div class="rodape"><span>Controle interno de prestação de serviços por dia.</span><span>Gerado em ${quandoEmBrasilia(p.geradoEm)}</span></div>
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
