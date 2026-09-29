// Documentos das diárias: o extrato em PDF (para imprimir e o freelancer assinar no papel) e as
// linhas do CSV do contador. Puro — sem Supabase, sem janela —, para ser testado.
//
// É controle interno de prestação de serviço por dia, não registro de ponto: não há horário de
// entrada e saída, só o dia, a diária e o que foi pago.
import type { ContaCorrente, LinhaDaContaCorrente } from '@/hooks/use-diarias';
import type { ExportColumn } from '@/lib/export-utils';
import { rotuloDaJornada } from '@/lib/diarias';

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
const diaDaSemana = (d: string) => { const [a, m, x] = d.split('-').map(Number); return DIAS[new Date(a, m - 1, x).getDay()]; };

/** No papel, "Faltou" (cabe na coluna e é o que se lê ao assinar); na tela é "Não trabalhou". */
const tipoDoDia = (j: LinhaDaContaCorrente['jornada']) => (j === 'faltou' ? 'Faltou' : rotuloDaJornada(j));

function esc(v: unknown): string {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
}

/** CPF/CNPJ com a pontuação de costume; outro formato passa como veio. */
export function documentoFormatado(doc: string | null | undefined): string {
  const d = String(doc ?? '').replace(/\D/g, '');
  if (d.length === 11) return `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`;
  if (d.length === 14) return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}/${d.slice(8, 12)}-${d.slice(12)}`;
  return String(doc ?? '');
}

/** "01/09/2026 a 30/09/2026", ou "desde 25/08/2026" quando é o histórico inteiro. */
export function textoDoPeriodo(conta: Pick<ContaCorrente, 'de' | 'ate' | 'favorecido'>): string {
  if (conta.de && conta.ate) return `${dataBR(conta.de)} a ${dataBR(conta.ate)}`;
  if (conta.de) return `desde ${dataBR(conta.de)}`;
  return conta.favorecido.desde ? `desde ${dataBR(conta.favorecido.desde)}` : 'todo o histórico';
}

export function nomeDoArquivo(prefixo: string, nome: string, conta: Pick<ContaCorrente, 'de' | 'ate'>, ext: string): string {
  const slug = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  const quando = conta.de && conta.ate && conta.de.slice(0, 7) === conta.ate.slice(0, 7) ? conta.de.slice(0, 7)
    : conta.de && conta.ate ? `${conta.de}_${conta.ate}` : 'historico';
  return `${[prefixo, slug(nome), quando].filter(Boolean).join('-')}.${ext}`;
}

const ESTADO_NO_PAPEL: Record<ContaCorrente['estado'], string> = {
  deve: 'a pagar ao prestador',
  adiantado: 'pago adiantado',
  quitado: 'quitado',
  semdias: 'sem dias lançados',
};

/** O extrato de um freelancer no período, em A4, com as duas linhas de assinatura. */
export function montarExtratoHtml(p: {
  empresa: EmpresaNoDocumento;
  freelancer: FreelancerNoDocumento;
  conta: ContaCorrente;
  geradoEm: Date;
}): string {
  const { empresa, freelancer, conta } = p;
  const dias = conta.linhas.filter((l) => l.tipo === 'dia');
  const pagamentos = conta.linhas.filter((l) => l.tipo === 'pagamento');
  const g = p.geradoEm;
  const gerado = `${String(g.getDate()).padStart(2, '0')}/${String(g.getMonth() + 1).padStart(2, '0')}/${g.getFullYear()} às ${String(g.getHours()).padStart(2, '0')}:${String(g.getMinutes()).padStart(2, '0')}`;

  const linhaDoDia = (l: LinhaDaContaCorrente) => `
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
  const linhaDoPagamento = (l: LinhaDaContaCorrente) => `
      <tr>
        <td>${dataBR(l.data)}</td><td>${esc(l.conta ?? '')}</td><td>${esc(l.descricao ?? '')}</td>
        <td class="n b">${brl(l.pago)}</td>
      </tr>`;

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
      <th class="n">Trabalhado</th><th class="n">Pago</th><th class="n">Saldo no fim do período</th>
    </tr></thead>
    <tbody><tr>
      <td class="n">${brl(conta.saldo_anterior)}</td><td class="n">${numero(conta.dias)}</td>
      <td class="n">${brl(conta.trabalhado)}</td><td class="n">${brl(conta.pago)}</td>
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
  </table>

  <h2>Pagamentos recebidos</h2>
  <table>
    <thead><tr><th>Data</th><th>De onde saiu</th><th>Identificação</th><th class="n">Valor</th></tr></thead>
    <tbody>${pagamentos.length ? pagamentos.map(linhaDoPagamento).join('') : '<tr><td colspan="4" class="vazio">Nenhum pagamento no período.</td></tr>'}</tbody>
    ${pagamentos.length ? `<tfoot><tr><td colspan="3">${pagamentos.length} pagamento(s)</td><td class="n">${brl(conta.pago)}</td></tr></tfoot>` : ''}
  </table>

  <p class="nota">Saldo positivo = valor a pagar ao prestador; negativo = pago adiantado. Extras são despesas pagas pelo prestador e reembolsadas.</p>

  <div class="assinaturas">
    <div>${esc(empresa.nome)}</div>
    <div>${esc(freelancer.nome)}${freelancer.documento ? `<br>CPF ${esc(documentoFormatado(freelancer.documento))}` : ''}</div>
  </div>

  <div class="rodape"><span>Controle interno de prestação de serviços por dia.</span><span>Gerado em ${gerado}</span></div>
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
}

const dec = (v: number | null | undefined) => (v == null ? '' : (Number(v) || 0).toFixed(2).replace('.', ','));

/** Todos os dias e pagamentos das contas, em ordem de data (dia antes de pagamento no mesmo dia). */
export function linhasDoCsv(contas: Array<{ conta: ContaCorrente; documento: string | null }>): LinhaDoCsv[] {
  const linhas: Array<LinhaDoCsv & { _ordem: string }> = [];
  for (const { conta, documento } of contas) {
    for (const l of conta.linhas) {
      const dia = l.tipo === 'dia';
      linhas.push({
        _ordem: `${l.data}|${dia ? 0 : 1}|${conta.favorecido.nome}`,
        data: dataBR(l.data),
        tipo: dia ? 'Diária' : 'Pagamento',
        freelancer: conta.favorecido.nome,
        cpf: documentoFormatado(documento),
        jornada: dia ? tipoDoDia(l.jornada) : '',
        diarias: dia ? dec(l.fracao).replace(/,00$/, '').replace(/0$/, '') : '',
        valor_diaria: dia ? dec(l.valor_diaria) : '',
        extras: dia ? dec(l.extras) : '',
        descontos: dia ? dec(l.descontos) : '',
        trabalhado: dia ? dec(l.trabalhado) : '',
        pago: dia ? '' : dec(l.pago),
        conta: dia ? '' : l.conta ?? '',
        categoria: dia ? '' : l.categoria ?? '',
        os: l.os.map((o) => o.numero).join(', '),
        observacao: dia ? l.observacao ?? '' : l.descricao ?? '',
      });
    }
  }
  return linhas.sort((a, b) => a._ordem.localeCompare(b._ordem)).map(({ _ordem: _, ...resto }) => resto);
}

export const COLUNAS_DO_CSV: ExportColumn[] = [
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
];
