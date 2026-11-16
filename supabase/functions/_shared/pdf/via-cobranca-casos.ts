// Os casos da regra de COBRANÇA da via do técnico (resposta 4A do dono: frete, deslocamento e insumos saem da lista de
// serviços; os outros mantêm o número). Porte da via v2, F1 (16/11/2026), escolha E12. Uma lista só: o Deno roda agora
// (via-texto_test.ts, ehCobranca) e o teste SQL da F2 roda a MESMA lista contra private._via_eh_cobranca, porque o
// canal automático (B) decide em SQL puro quem não recebe instrução. Dado sintético: os nomes reais que motivaram cada
// caso (porte/sql/m1-cobranca.sql, 6 linhas em 358) foram reescritos mantendo a forma que importa à regra.

export interface CasoDeCobranca {
  caso: string;
  /** O nome cru da linha (name_snapshot), como o banco guarda. */
  nome: string;
  /** true = linha de cobrança: sai dos cartões da via e da tela "Lançar a via". */
  cobranca: boolean;
}

export const CASOS_DE_COBRANCA: CasoDeCobranca[] = [
  {
    caso: 'insumos no fim do título, com parêntese de detalhe',
    nome: 'Termorretráteis e insumos (abraçadeiras, terminais e fita)',
    cobranca: true,
  },
  {
    caso: '"Insumos" no começo, em caixa alta e baixa, com barra',
    nome: 'Insumos Elétricos / terminais, fusíveis e conectores',
    cobranca: true,
  },
  {
    caso: 'frete DEPOIS do travessão é detalhe do serviço: fica',
    nome: 'Retirada e reinstalação do carregador TM41 — inclui frete de ida e volta ao fornecedor',
    cobranca: false,
  },
  {
    caso: 'frete em CAIXA ALTA (palavra inteira, sem acento e em minúsculas na comparação)',
    nome: 'FRETE EQUIPAMENTO',
    cobranca: true,
  },
  {
    caso: 'deslocamento sozinho no título',
    nome: 'Deslocamento técnico',
    cobranca: true,
  },
  {
    caso: 'insumos no fim de um título longo em caixa alta (falso positivo aceito: era OS cancelada)',
    nome: 'LEVANTAMENTO E DIMENSIONAMENTO DE PROTEÇÃO TÉRMICA DO CHICOTE E INSUMOS',
    cobranca: true,
  },
  {
    caso: '"Transporte" não é palavra da regra: fica (pergunta antiga ao dono, sem resposta)',
    nome: 'Transporte',
    cobranca: false,
  },
  {
    caso: 'insumo no singular também conta',
    nome: 'Insumo de vedação',
    cobranca: true,
  },
  {
    caso: 'palavra só começando igual não conta ("fretado", "deslocamentos" de peça não são a palavra inteira)',
    nome: 'Ajuste do banco fretado e deslocamentos do trilho',
    cobranca: false,
  },
  {
    caso: 'serviço comum: fica',
    nome: 'Instalação de inversor 3000 W',
    cobranca: false,
  },
  {
    caso: '"Mão de obra —" na frente sai antes de olhar o título (limparRuido)',
    nome: 'Mão de obra — deslocamento até a marina',
    cobranca: true,
  },
  {
    caso: 'preço no nome sai antes de olhar o título; o frete continua sendo o título',
    nome: 'Frete (R$ 150,00)',
    cobranca: true,
  },
  {
    caso: 'nome vazio vira "Serviço": não é cobrança',
    nome: '',
    cobranca: false,
  },
];
