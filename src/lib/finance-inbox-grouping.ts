// Agrupa a caixa de entrada financeira por favorecido.
//
// POR QUE ISTO EXISTE
// A fila tem 1.178 propostas, e 558 delas caíram em "Outras despesas" — quase metade.
// Aprová-las em bloco criaria 558 despesas sem classificação, que é o incômodo que a tela
// existe para acabar; classificá-las uma a uma são 558 decisões. Mas essas 558 vêm de
// apenas 253 favorecidos, e 85 favorecidos repetidos respondem por 390 delas: 34 compras
// no mesmo estabelecimento de Curitiba, 14 corridas de Uber, 13 no mesmo mercado.
//
// A decisão real não é "o que é esta compra de R$ 9,42" — é "o que são as compras neste
// lugar". Uma pergunta no lugar de trinta e quatro, e a resposta vira regra.
//
// O AGRUPAMENTO NÃO AFROUXA A GOVERNANÇA
// Classificar em grupo é barato e reversível; aprovar cria lançamento. Por isso o grupo
// resolve a CATEGORIA de todas de uma vez, mas o botão de aprovar só alcança as que estão
// abaixo do limite de lote. As grandes continuam pedindo olho individual, como sempre —
// elas só chegam lá já classificadas.

import type { PropostaFinanceira } from '@/hooks/use-finance-review';

/** Caixa alta, sem acento e sem pontuação — a forma comparável de um nome de extrato. */
export function normalizarFavorecido(valor: string): string {
  return (valor || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, ' ')
    .trim();
}

export interface GrupoDeFavorecido {
  /** Identidade do grupo: fornecedor > documento > nome > histórico. */
  chave: string;
  rotulo: string;
  supplierId: string | null;
  documento: string | null;
  propostas: PropostaFinanceira[];
  /** Abaixo do limite e não transferência: o que o botão do grupo alcança. */
  emLote: PropostaFinanceira[];
  /** Acima do limite ou transferência: continuam individuais. */
  individuais: PropostaFinanceira[];
  total: number;
  totalEmLote: number;
  /** Categorias sugeridas distintas — mais de uma significa que o sistema hesitou. */
  categorias: string[];
  /** Nenhuma proposta do grupo tem categoria de verdade. */
  semCategoria: boolean;
  primeiraData: string | null;
  ultimaData: string | null;
}

/** Ausência de classificação, não uma classificação. */
export const SEM_CATEGORIA = 'Outras despesas';

function identidade(p: PropostaFinanceira): { chave: string; rotulo: string } {
  const tx = p.bank_transactions;

  // Fornecedor cadastrado é a identidade mais forte: sobrevive a mudança de razão social
  // e a variações de escrita no extrato.
  if (p.suggested_supplier_id) {
    return {
      chave: `fornecedor:${p.suggested_supplier_id}`,
      rotulo: tx?.counterparty_name || p.suggested_description || p.title,
    };
  }

  const doc = (tx?.counterparty_document || '').replace(/\D/g, '');
  if (doc.length >= 11) {
    return { chave: `documento:${doc}`, rotulo: tx?.counterparty_name || doc };
  }

  const nome = normalizarFavorecido(tx?.counterparty_name || '');
  if (nome) return { chave: `nome:${nome}`, rotulo: (tx?.counterparty_name || '').trim() };

  // Sem nome no extrato, o histórico é a única identificação que existe. Costuma render
  // grupo de um só — e é honesto que renda: são compras que o banco não identificou.
  const texto = normalizarFavorecido(tx?.description || p.suggested_description || p.title);
  return { chave: `historico:${texto}`, rotulo: (tx?.description || p.title).trim() };
}

export function agruparPorFavorecido(
  propostas: PropostaFinanceira[],
  limiteLote: number,
): GrupoDeFavorecido[] {
  const mapa = new Map<string, GrupoDeFavorecido>();

  for (const p of propostas) {
    const { chave, rotulo } = identidade(p);
    const grupo = mapa.get(chave) ?? {
      chave,
      rotulo: rotulo || '(sem identificação no extrato)',
      supplierId: p.suggested_supplier_id ?? null,
      documento: p.bank_transactions?.counterparty_document ?? null,
      propostas: [],
      emLote: [],
      individuais: [],
      total: 0,
      totalEmLote: 0,
      categorias: [],
      semCategoria: true,
      primeiraData: null,
      ultimaData: null,
    };

    const valor = Number(p.suggested_amount ?? 0);
    grupo.propostas.push(p);
    grupo.total += valor;

    // Transferência entre contas nunca entra no lote: confirmar que dois lançamentos são o
    // mesmo dinheiro é decisão de fato, não volume.
    if (p.kind !== 'internal_transfer' && valor < limiteLote) {
      grupo.emLote.push(p);
      grupo.totalEmLote += valor;
    } else {
      grupo.individuais.push(p);
    }

    const cat = p.suggested_category ?? '';
    if (cat && !grupo.categorias.includes(cat)) grupo.categorias.push(cat);
    if (cat && cat !== SEM_CATEGORIA) grupo.semCategoria = false;

    const data = p.suggested_date;
    if (data) {
      if (!grupo.primeiraData || data < grupo.primeiraData) grupo.primeiraData = data;
      if (!grupo.ultimaData || data > grupo.ultimaData) grupo.ultimaData = data;
    }

    // O documento pode aparecer só em algumas linhas do mesmo favorecido.
    if (!grupo.documento && p.bank_transactions?.counterparty_document) {
      grupo.documento = p.bank_transactions.counterparty_document;
    }
    if (!grupo.supplierId && p.suggested_supplier_id) grupo.supplierId = p.suggested_supplier_id;

    mapa.set(chave, grupo);
  }

  // Dentro do grupo, da mais recente para a mais antiga. Extrato se lê por data, e uma
  // ordem estável é o que permite conferir uma lista longa sem se perder nela.
  for (const g of mapa.values()) {
    const porData = (a: PropostaFinanceira, b: PropostaFinanceira) =>
      String(b.suggested_date ?? '').localeCompare(String(a.suggested_date ?? ''));
    g.propostas.sort(porData);
    g.emLote.sort(porData);
    g.individuais.sort(porData);
  }

  return ordenarGrupos([...mapa.values()], 'decisoes');
}

/** Como a fila se apresenta. Cada uma serve a um jeito de trabalhar. */
export type OrdemDaFila = 'decisoes' | 'prontos' | 'data' | 'favorecido';

export const ROTULO_DA_ORDEM: Record<OrdemDaFila, string> = {
  decisoes: 'Mais linhas primeiro',
  prontos: 'Prontos para aprovar',
  data: 'Mais recentes',
  favorecido: 'Favorecido (A-Z)',
};

/**
 * Ordena os grupos.
 *
 * Não existe uma ordem certa — existe a ordem que serve ao que se está fazendo. Fazendo
 * mutirão, o que rende mais decisão por clique vem primeiro. Querendo despachar o que já
 * está resolvido, os prontos. Conferindo contra a fatura do mês, a data. Procurando um
 * fornecedor específico, o alfabeto.
 *
 * `jaResolvido` deixa a tela informar o que ela sabe e a lista não: a categoria que o
 * gestor acabou de escolher no cabeçalho e ainda não aprovou.
 */
export function ordenarGrupos(
  grupos: GrupoDeFavorecido[],
  ordem: OrdemDaFila,
  jaResolvido?: (g: GrupoDeFavorecido) => boolean,
): GrupoDeFavorecido[] {
  const pronto = (g: GrupoDeFavorecido) =>
    jaResolvido?.(g) ?? (!g.semCategoria && g.categorias.length === 1);

  const porDecisoes = (a: GrupoDeFavorecido, b: GrupoDeFavorecido) =>
    b.propostas.length - a.propostas.length || b.total - a.total;

  const copia = [...grupos];
  switch (ordem) {
    case 'prontos':
      // Resolvidos primeiro, e entre eles os que rendem mais — é a fila de despacho.
      return copia.sort((a, b) => Number(pronto(b)) - Number(pronto(a)) || porDecisoes(a, b));
    case 'data':
      return copia.sort((a, b) =>
        String(b.ultimaData ?? '').localeCompare(String(a.ultimaData ?? '')) || porDecisoes(a, b));
    case 'favorecido':
      return copia.sort((a, b) => a.rotulo.localeCompare(b.rotulo, 'pt-BR'));
    default:
      return copia.sort(porDecisoes);
  }
}

/** Resumo para a barra da tela: o que o agrupamento economiza de decisão. */
export function resumoDoAgrupamento(grupos: GrupoDeFavorecido[]) {
  const repetidos = grupos.filter((g) => g.propostas.length > 1);
  return {
    grupos: grupos.length,
    propostas: grupos.reduce((s, g) => s + g.propostas.length, 0),
    repetidos: repetidos.length,
    propostasEmRepetidos: repetidos.reduce((s, g) => s + g.propostas.length, 0),
    semCategoria: grupos.filter((g) => g.semCategoria).length,
  };
}
