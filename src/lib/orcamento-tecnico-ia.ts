// Orçamento técnico com IA — leitura da proposta que o HBR AI Gateway grava em ai_jobs.response.
// O formato é garantido pelo JSON Schema do job (ai_orcamento_tecnico_solicitar), mas a tela não
// confia cegamente: tudo que vem do modelo passa por aqui antes de virar número na tela.

export type TipoDoItem = 'equipamento' | 'material' | 'mao_de_obra';

export interface ItemDaProposta {
  tipo: TipoDoItem;
  descricao: string;
  produtoId: string | null;
  servicoId: string | null;
  quantidade: number;
  unidade: string;
  custoUnitario: number;
  origemDoCusto: string;
  dataDoCusto: string | null;
  provisorio: boolean;
  precoVendaUnitario: number;
  totalVenda: number;
}

export interface OrcamentoDaProposta {
  titulo: string;
  itens: ItemDaProposta[];
  resumo: {
    custoEstimado: number;
    margemAplicadaPct: number;
    totalMateriaisEEquipamentos: number;
    totalMaoDeObra: number;
    totalGeral: number;
  };
  observacoesProvisorias: string[];
}

export interface PropostaTecnica {
  orcamentos: OrcamentoDaProposta[];
  premissas: string[];
  perguntasPendentes: string[];
  margem: { criterio: string; markup: number } | null;
}

export type EstadoDoPedido = 'na_fila' | 'montando' | 'pronta' | 'falhou' | 'cancelado';

/** Linha de ai_jobs que a tela lê (colunas pedidas em use-orcamento-tecnico-ia). */
export interface JobDeOrcamento {
  id: string;
  status: string;
  created_at: string;
  started_at: string | null;
  completed_at: string | null;
  model: string;
  model_used: string | null;
  duration_ms: number | null;
  error: string | null;
  error_code: string | null;
  prompt: string;
  response: unknown;
  metadata: unknown;
  attempts: number;
  max_attempts: number;
}

const num = (v: unknown): number => {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
};
const txt = (v: unknown): string => (typeof v === 'string' ? v : '');
const lista = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);
const objeto = (v: unknown): Record<string, unknown> =>
  v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {};

const TIPOS: TipoDoItem[] = ['equipamento', 'material', 'mao_de_obra'];

/** Lê `response` do job. Devolve null se não houver proposta utilizável. */
export function lerProposta(response: unknown): PropostaTecnica | null {
  const dados = objeto(objeto(response).data);
  if (!Array.isArray(dados.orcamentos) || dados.orcamentos.length === 0) return null;

  const orcamentos = dados.orcamentos.map((o): OrcamentoDaProposta => {
    const orc = objeto(o);
    const resumo = objeto(orc.resumo);
    const itens = (Array.isArray(orc.itens) ? orc.itens : []).map((i): ItemDaProposta => {
      const it = objeto(i);
      const tipo = TIPOS.includes(it.tipo as TipoDoItem) ? (it.tipo as TipoDoItem) : 'material';
      return {
        tipo,
        descricao: txt(it.descricao) || 'Item sem descrição',
        produtoId: txt(it.produto_id) || null,
        servicoId: txt(it.servico_id) || null,
        quantidade: num(it.quantidade),
        unidade: txt(it.unidade),
        custoUnitario: num(it.custo_unitario),
        origemDoCusto: txt(it.origem_do_custo),
        dataDoCusto: txt(it.data_do_custo) || null,
        provisorio: it.provisorio === true,
        precoVendaUnitario: num(it.preco_venda_unitario),
        totalVenda: num(it.total_venda),
      };
    });
    return {
      titulo: txt(orc.titulo) || 'Orçamento',
      itens,
      resumo: {
        custoEstimado: num(resumo.custo_estimado),
        margemAplicadaPct: num(resumo.margem_aplicada_pct),
        totalMateriaisEEquipamentos: num(resumo.total_materiais_e_equipamentos),
        totalMaoDeObra: num(resumo.total_mao_de_obra),
        totalGeral: num(resumo.total_geral),
      },
      observacoesProvisorias: lista(orc.observacoes_valores_provisorios),
    };
  });

  const margem = objeto(dados.margem_adotada);
  return {
    orcamentos,
    premissas: lista(dados.premissas_tecnicas),
    perguntasPendentes: lista(dados.perguntas_pendentes),
    margem: txt(margem.criterio) ? { criterio: txt(margem.criterio), markup: num(margem.markup) } : null,
  };
}

const centavos = (v: number) => Math.round(v * 100);

/**
 * Confere as contas que o modelo declarou. A tela mostra o aviso em vez de esconder:
 * quem decide se cria o rascunho é o dono, e o banco recalcula os totais de qualquer jeito.
 */
export function conferirContas(orc: OrcamentoDaProposta): string[] {
  const avisos: string[] = [];
  orc.itens.forEach((i) => {
    if (Math.abs(centavos(i.quantidade * i.precoVendaUnitario) - centavos(i.totalVenda)) > 1) {
      avisos.push(`"${i.descricao}": quantidade × preço não bate com o total da linha.`);
    }
  });
  const soma = orc.itens.reduce((s, i) => s + i.totalVenda, 0);
  if (Math.abs(centavos(soma) - centavos(orc.resumo.totalGeral)) > 1) {
    avisos.push('O total geral declarado não bate com a soma das linhas.');
  }
  return avisos;
}

export function estadoDoPedido(job: Pick<JobDeOrcamento, 'status' | 'started_at'>): EstadoDoPedido {
  switch (job.status) {
    case 'completed':
      return 'pronta';
    case 'failed':
      return 'falhou';
    case 'cancelled':
      return 'cancelado';
    case 'processing':
      return 'montando';
    default:
      return 'na_fila';
  }
}

/** Rascunhos já criados a partir desta proposta: índice do orçamento → id da OS. */
export function rascunhosCriados(metadata: unknown): Record<number, string> {
  const r = objeto(objeto(metadata).rascunhos);
  const out: Record<number, string> = {};
  for (const [k, v] of Object.entries(r)) {
    if (/^\d+$/.test(k) && typeof v === 'string' && v) out[Number(k)] = v;
  }
  return out;
}

/** "3 min 05 s" — quanto tempo o pedido está rodando (ou levou). */
export function duracaoLegivel(ms: number): string {
  const s = Math.max(0, Math.round(ms / 1000));
  const m = Math.floor(s / 60);
  const resto = String(s % 60).padStart(2, '0');
  return m > 0 ? `${m} min ${resto} s` : `${s} s`;
}

/** Mensagem humana para os códigos de erro do gateway. */
export function motivoDaFalha(job: Pick<JobDeOrcamento, 'error_code' | 'error'>): string {
  switch (job.error_code) {
    case 'rate_limited':
    case 'local_quota':
      return 'O limite de uso da assinatura do Claude foi atingido. O pedido volta sozinho quando o limite liberar.';
    case 'auth_failed':
      return 'O Claude do computador da HBR está sem login. Verifique o HBR AI Gateway.';
    case 'timeout':
      return 'O pedido passou do tempo máximo. Tente de novo, talvez com o Sonnet ou com um pedido menor.';
    case 'invalid_output':
      return 'A IA não devolveu a proposta no formato esperado. Tente de novo.';
    case 'policy_denied':
      return 'Este pedido não pode usar o Claude da assinatura (só pedidos do administrador).';
    case 'cancelled':
      return 'Pedido cancelado.';
    default:
      return job.error || 'O pedido falhou.';
  }
}
