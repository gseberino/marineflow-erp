// Demonstrativo do mês em PDF, para conferir e fechar o mês no papel (pedido do dono, 29/09/2026).
//
// Nada aqui calcula por conta própria: o resultado é o `montarDRE` (o mesmo do DRE e do Resumo do
// mês), o dinheiro que passou pelas contas é o fluxo do extrato (o mesmo da Central de relatórios)
// e a lista do "Mês pronto?" vem do banco (checklist_do_mes). Este arquivo só monta o documento.
import { montarDRE, type GrupoDRE, type LancamentoDRE } from '@/lib/dre';

export interface LancamentoDoDemonstrativo extends LancamentoDRE {
  descricao: string;
  /** Fornecedor, favorecido ou cliente, quando houver. */
  quem: string | null;
  /** Situação do lançamento (pago, em aberto…). */
  situacao: string | null;
}

export interface FluxoDoMesNoDemonstrativo {
  entrou: number;
  saiu: number;
  liquido: number;
  transferencias: { entrou: number; saiu: number };
  creditoDoCartao: { entrou: number; saiu: number };
}

export interface ItemDoMesPronto {
  titulo: string;
  ok: boolean;
  bloqueia: boolean;
  detalhe: string;
}

/** As três categorias do sócio que o dono acompanha juntas (pró-labore pelo salário mínimo). */
export const CATEGORIAS_DO_SOCIO = ['Pró-labore', 'Retirada de sócio', 'Gasto Pessoal Sócio - Descontar PL'] as const;

const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

const ORDEM_DOS_GRUPOS: Array<GrupoDRE | 'sem_grupo'> =
  ['receita', 'custo_direto', 'despesa_operacional', 'financeiro', 'nao_operacional', 'sem_grupo'];

const ROTULO_DO_GRUPO: Record<GrupoDRE | 'sem_grupo', string> = {
  receita: 'Receitas',
  custo_direto: 'Custo dos serviços e produtos',
  despesa_operacional: 'Despesas operacionais',
  financeiro: 'Juros e tarifas',
  nao_operacional: 'Não operacional (fora do resultado)',
  sem_grupo: 'Sem categoria do plano de contas',
};

const SITUACAO: Record<string, string> = {
  paid: 'pago', received: 'recebido', pending: 'em aberto', partial: 'parcial', overdue: 'vencido',
};

function esc(v: unknown): string {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
}

const brl = (v: number) => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const pct = (v: number | null | undefined) => (v == null ? '' : `${v.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`);
const diaMes = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;

export function nomeDoMesPorExtenso(mes: string): string {
  const [ano, m] = mes.split('-').map(Number);
  return `${MESES[m - 1]} de ${ano}`;
}

export function nomeDoArquivoDoDemonstrativo(mes: string): string {
  return `demonstrativo-${mes}.pdf`;
}

function documentoFormatado(doc: string | null | undefined): string {
  const d = String(doc ?? '').replace(/\D/g, '');
  if (d.length === 14) return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}/${d.slice(8, 12)}-${d.slice(12)}`;
  if (d.length === 11) return `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`;
  return String(doc ?? '');
}

/** Os lançamentos por grupo e, dentro dele, por categoria — na ordem do resultado. */
export function lancamentosPorGrupo(lancamentos: LancamentoDoDemonstrativo[]) {
  const grupos: Array<{
    grupo: GrupoDRE | 'sem_grupo';
    rotulo: string;
    total: number;
    categorias: Array<{ categoria: string; total: number; linhas: LancamentoDoDemonstrativo[] }>;
  }> = [];
  for (const g of ORDEM_DOS_GRUPOS) {
    const doGrupo = lancamentos.filter((l) => (l.grupo ?? 'sem_grupo') === g);
    if (!doGrupo.length) continue;
    const porCategoria = new Map<string, LancamentoDoDemonstrativo[]>();
    for (const l of doGrupo) {
      const c = l.categoria ?? 'Sem categoria';
      porCategoria.set(c, [...(porCategoria.get(c) ?? []), l]);
    }
    const categorias = [...porCategoria.entries()]
      .map(([categoria, linhas]) => ({
        categoria,
        total: linhas.reduce((s, l) => s + l.valor, 0),
        linhas: [...linhas].sort((a, b) => a.data.localeCompare(b.data) || b.valor - a.valor),
      }))
      .sort((a, b) => b.total - a.total);
    grupos.push({ grupo: g, rotulo: ROTULO_DO_GRUPO[g], total: doGrupo.reduce((s, l) => s + l.valor, 0), categorias });
  }
  return grupos;
}

export function montarDemonstrativoHtml(p: {
  empresa: { nome: string; cnpj: string | null };
  /** 'AAAA-MM' */
  mes: string;
  lancamentos: LancamentoDoDemonstrativo[];
  extrato: FluxoDoMesNoDemonstrativo | null;
  checklist: { pronto: boolean; itens: ItemDoMesPronto[] } | null;
  fechado: boolean;
  geradoEm: Date;
}): string {
  const { empresa, mes, lancamentos, extrato, checklist, fechado, geradoEm } = p;
  const dre = montarDRE(lancamentos);
  const naoOperacional = lancamentos.filter((l) => l.grupo === 'nao_operacional');
  const doSocio = CATEGORIAS_DO_SOCIO
    .map((c) => ({ categoria: c, total: lancamentos.filter((l) => l.categoria === c).reduce((s, l) => s + l.valor, 0) }))
    .filter((c) => c.total > 0);
  const titulo = `Demonstrativo de ${nomeDoMesPorExtenso(mes)}`;
  const quando = geradoEm.toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', dateStyle: 'short', timeStyle: 'short' });

  const blocoChecklist = checklist
    ? `<h2>O mês está pronto? ${checklist.pronto ? '— sim' : '— ainda não'}</h2>
  <table><colgroup><col style="width:40%"><col style="width:12%"><col style="width:48%"></colgroup><thead><tr><th>Conferência</th><th>Situação</th><th>Detalhe</th></tr></thead><tbody>
  ${checklist.itens.map((i) => `<tr><td>${esc(i.titulo)}</td><td class="b">${i.ok ? 'OK' : i.bloqueia ? 'Falta' : 'Aviso'}</td><td>${esc(i.detalhe)}</td></tr>`).join('')}
  </tbody></table>`
    : '<p class="vazio">A lista do "Mês pronto?" não respondeu na hora de gerar.</p>';

  const blocoDre = `<h2>Resultado do mês (DRE, pela data do lançamento)</h2>
  <table><colgroup><col style="width:60%"><col style="width:22%"><col style="width:18%"></colgroup><thead><tr><th>Linha</th><th class="n">Valor</th><th class="n">% da receita</th></tr></thead><tbody>
  ${dre.linhas.map((l) => `<tr class="${l.total ? 'total' : ''}"><td>${esc(l.rotulo)}</td><td class="n">${brl(l.valor)}</td><td class="n">${pct(l.percentual)}</td></tr>
    ${(l.detalhe ?? []).map((d) => `<tr class="det"><td>${esc(d.categoria)}</td><td class="n">${brl(d.valor)}</td><td></td></tr>`).join('')}`).join('')}
  </tbody></table>
  ${naoOperacional.length ? `<p class="nota">Fora do resultado (não operacional): ${brl(dre.naoOperacional)} — pagamento de fatura, transferência entre contas, retirada de sócio e parecidos movimentam dinheiro, mas não são despesa.</p>` : ''}
  ${dre.semGrupo > 0 ? `<p class="nota aviso">Atenção: ${brl(dre.semGrupo)} em lançamentos sem categoria do plano de contas ficaram fora do resultado.</p>` : ''}`;

  const blocoSocio = doSocio.length
    ? `<h2>Sócio no mês</h2>
  <table><tbody>
  ${doSocio.map((c) => `<tr><td>${esc(c.categoria)}</td><td class="n">${brl(c.total)}</td></tr>`).join('')}
  <tr class="total"><td>Total pago ao sócio</td><td class="n">${brl(doSocio.reduce((s, c) => s + c.total, 0))}</td></tr>
  </tbody></table>`
    : '';

  const blocoExtrato = extrato
    ? `<h2>Dinheiro que passou pelas contas (extrato)</h2>
  <table><tbody>
  <tr><td>Entrou</td><td class="n">${brl(extrato.entrou)}</td></tr>
  <tr><td>Saiu</td><td class="n">${brl(extrato.saiu)}</td></tr>
  <tr class="total"><td>Líquido do mês</td><td class="n">${brl(extrato.liquido)}</td></tr>
  </tbody></table>
  <p class="nota">À parte, sem contar acima: transferências entre as suas contas (${brl(extrato.transferencias.entrou)} entrou, ${brl(extrato.transferencias.saiu)} saiu) e crédito do cartão na conta (${brl(extrato.creditoDoCartao.entrou)}).</p>`
    : '<p class="vazio">O extrato não respondeu na hora de gerar.</p>';

  const grupos = lancamentosPorGrupo(lancamentos);
  const blocoLancamentos = grupos.length
    ? `<h2 class="quebra">Lançamentos do mês, para conferir linha a linha (${lancamentos.length})</h2>
  ${grupos.map((g) => `<h3>${esc(g.rotulo)} — ${brl(g.total)}</h3>
  <table class="lancs"><colgroup><col style="width:9%"><col style="width:38%"><col style="width:23%"><col style="width:11%"><col style="width:14%"><col style="width:5%"></colgroup><thead><tr><th>Data</th><th>Descrição</th><th>Quem</th><th>Situação</th><th class="n">Valor</th><th>✓</th></tr></thead><tbody>
  ${g.categorias.map((c) => `<tr class="cat"><td colspan="4">${esc(c.categoria)}</td><td class="n">${brl(c.total)}</td><td></td></tr>
    ${c.linhas.map((l) => `<tr><td>${diaMes(l.data)}</td><td>${esc(l.descricao)}</td><td>${esc(l.quem ?? '')}</td><td>${esc(SITUACAO[l.situacao ?? ''] ?? l.situacao ?? '')}</td><td class="n">${brl(l.valor)}</td><td class="caixa"></td></tr>`).join('')}`).join('')}
  </tbody></table>`).join('')}`
    : '<p class="vazio">Nenhum lançamento neste mês.</p>';

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>${esc(titulo)} — ${esc(empresa.nome)}</title>
<style>
  @page { size: A4; margin: 10mm; }
  * { box-sizing: border-box; }
  html, body { width: 100%; }
  body { font-family: Arial, Helvetica, sans-serif; color: #10293a; font-size: 10px; margin: 0; }
  .topo { display: flex; justify-content: space-between; align-items: flex-end; border-bottom: 2px solid #10293a; padding-bottom: 6px; }
  .topo h1 { margin: 0; font-size: 16px; }
  .topo .emp { font-size: 10px; color: #4b616f; }
  .selo { display: inline-block; margin-top: 3px; padding: 1px 6px; border: 1px solid #4b616f; border-radius: 3px; font-size: 9.5px; }
  .resumo { display: flex; gap: 6px; margin: 10px 0 2px; }
  .resumo div { flex: 1 1 0; min-width: 0; border: 1px solid #cfd8da; border-radius: 4px; padding: 5px 6px; }
  .resumo span { display: block; color: #4b616f; font-size: 9px; }
  .resumo b { font-size: 13px; }
  /* Largura fixa por coluna e quebra dentro da célula: uma descrição longa do banco não empurra
     a tabela para fora da folha (o dono imprimiu em 30/09 e as colunas saíram cortadas). */
  table { width: 100%; max-width: 100%; border-collapse: collapse; margin-top: 4px; table-layout: fixed; }
  th, td { border: 1px solid #cfd8da; padding: 3px 4px; text-align: left; vertical-align: top; overflow-wrap: anywhere; word-break: break-word; }
  table.lancs { font-size: 9px; }
  th { background: #eef2f3; font-size: 9.5px; }
  td.n, th.n { text-align: right; white-space: nowrap; }
  td.b { font-weight: bold; }
  tr.total td { background: #eef2f3; font-weight: bold; }
  tr.det td:first-child { padding-left: 16px; color: #4b616f; }
  tr.cat td { background: #f6f8f9; font-weight: bold; }
  h2 { font-size: 12px; margin: 14px 0 2px; }
  h3 { font-size: 11px; margin: 10px 0 0; }
  h2.quebra { page-break-before: always; }
  tr { page-break-inside: avoid; }
  .vazio { color: #7f929c; font-style: italic; }
  .nota { color: #4b616f; font-size: 9.5px; margin-top: 4px; }
  .aviso { color: #9a3412; }
  .assinaturas { display: flex; justify-content: space-between; gap: 30px; margin-top: 36px; page-break-inside: avoid; }
  .assinaturas div { flex: 1; border-top: 1px solid #4b616f; padding-top: 4px; text-align: center; font-size: 10px; }
  .rodape { margin-top: 18px; color: #7f929c; font-size: 9px; display: flex; justify-content: space-between; gap: 12px; }
</style>
</head>
<body>
  <div class="topo">
    <div>
      <h1>${esc(titulo)}</h1>
      <div class="emp">Para conferência e fechamento do mês</div>
      <span class="selo">${fechado ? 'Mês fechado' : 'Mês aberto: os números ainda podem mudar'}</span>
    </div>
    <div class="emp" style="text-align:right">
      <b>${esc(empresa.nome)}</b><br>${empresa.cnpj ? `CNPJ ${esc(documentoFormatado(empresa.cnpj))}` : ''}
    </div>
  </div>

  <div class="resumo">
    <div><span>Receita (lançada)</span><b>${brl(dre.receitaTotal)}</b></div>
    <div><span>Resultado do mês</span><b>${brl(dre.resultado)}</b></div>
    <div><span>Entrou nas contas</span><b>${extrato ? brl(extrato.entrou) : '—'}</b></div>
    <div><span>Saiu das contas</span><b>${extrato ? brl(extrato.saiu) : '—'}</b></div>
  </div>

  ${blocoChecklist}
  ${blocoDre}
  ${blocoSocio}
  ${blocoExtrato}
  ${blocoLancamentos}

  <div class="assinaturas">
    <div>Conferido por</div>
    <div>Data</div>
  </div>

  <div class="rodape">
    <span>Gerado pelo MarineFlow em ${esc(quando)}. Resultado pela data do lançamento; extrato pelo dinheiro que passou nas contas.</span>
    <span>${esc(empresa.nome)}</span>
  </div>
</body>
</html>`;
}
