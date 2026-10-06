// Cobertura do detector/importador de CSV — módulo sem teste até agora.
//
// É por aqui que entra catálogo inteiro de produto, serviço e cadastro vindo de outro ERP.
// Um erro aqui não aparece como erro: aparece como preço, estoque ou telefone errado em
// centenas de linhas de uma vez, já gravados, misturados aos certos.
//
// Dois defeitos reais apareceram enquanto estes casos eram escritos — `NOVO-017` em
// audit/novos-achados.md — e já estão corrigidos. Os casos marcados com o ID afirmam o
// comportamento certo e explicam o que quebrava, para ninguém "simplificar" de volta.
import { describe, it, expect } from 'vitest';
import {
  parseCSVContent, detectFormat, transformValue, applyMapping, celulasInvalidas, campoInvalido, semCamposInvalidos, colunasNoMesmoCampo,
} from './import-detector';

describe('parseCSVContent — separador, aspas e linhas irregulares', () => {
  it('usa ponto e vírgula por padrão (é o que o Excel pt-BR gera)', () => {
    const p = parseCSVContent('nome;preco\nCabo 6mm;89,90');
    expect(p.separator).toBe(';');
    expect(p.headers).toEqual(['nome', 'preco']);
    expect(p.rows).toEqual([{ nome: 'Cabo 6mm', preco: '89,90' }]);
  });

  it('cai para vírgula quando a primeira linha não tem ponto e vírgula', () => {
    const p = parseCSVContent('nome,preco\nCabo 6mm,89.90');
    expect(p.separator).toBe(',');
    expect(p.rows[0]).toEqual({ nome: 'Cabo 6mm', preco: '89.90' });
  });

  it('separador dentro de aspas não parte a coluna', () => {
    const p = parseCSVContent('nome;obs\n"Disjuntor 63A";"tripolar; curva C"');
    expect(p.rows[0]).toEqual({ nome: 'Disjuntor 63A', obs: 'tripolar; curva C' });
  });

  it('aspas duplicadas viram uma aspa literal', () => {
    const p = parseCSVContent('nome;obs\nCabo;"cabo ""flex"" 6mm"');
    expect(p.rows[0].obs).toBe('cabo "flex" 6mm');
  });

  it('linha com menos colunas que o cabeçalho preenche com vazio, não com undefined', () => {
    const p = parseCSVContent('a;b;c\n1;2');
    expect(p.rows[0]).toEqual({ a: '1', b: '2', c: '' });
  });

  it('linhas em branco no meio e no fim são descartadas', () => {
    const p = parseCSVContent('a;b\n1;2\n\n3;4\n\n');
    expect(p.rows).toHaveLength(2);
  });

  it('arquivo do Windows (CRLF) não deixa \\r grudado no último campo', () => {
    const p = parseCSVContent('nome;uf\r\nCabo;SC\r\n');
    expect(p.headers).toEqual(['nome', 'uf']);
    expect(p.rows[0].uf).toBe('SC');
  });

  it('conteúdo vazio não quebra', () => {
    expect(parseCSVContent('')).toEqual({ headers: [], rows: [], encoding: 'utf-8', separator: ';' });
  });
});

describe('detectFormat — reconhecer de onde veio o arquivo', () => {
  const cabecalhoProdutos = ['Tipo (Produto/Servico)', 'Valor Venda (Tabela Padrão)', 'Nome do Produto (120)'];

  it('arquivo só de serviços é reconhecido como serviços', () => {
    const r = detectFormat({
      headers: cabecalhoProdutos,
      rows: [{ 'Tipo (Produto/Servico)': 'Serviço' }, { 'Tipo (Produto/Servico)': 'Servico' }],
      encoding: 'utf-8', separator: ';',
    });
    expect(r.entityType).toBe('services');
    expect(r.recordCount).toBe(2);
    expect(r.confidence).toBe(95);
  });

  it('arquivo misto é tratado como produtos, contando SÓ as linhas de produto', () => {
    // Detalhe que importa na tela: o número mostrado ao usuário é quantos registros vão
    // entrar, não quantas linhas o arquivo tem.
    const r = detectFormat({
      headers: cabecalhoProdutos,
      rows: [
        { 'Tipo (Produto/Servico)': 'Produto' },
        { 'Tipo (Produto/Servico)': 'Servico' },
        { 'Tipo (Produto/Servico)': 'Produto' },
      ],
      encoding: 'utf-8', separator: ';',
    });
    expect(r.entityType).toBe('products');
    expect(r.recordCount).toBe(2);
  });

  it('reconhece o arquivo de clientes e fornecedores', () => {
    const r = detectFormat({
      headers: ['Razao Social/Nome', 'Tipo Cadastro (Cliente/Fornecedor/Ambos)'],
      rows: [{}], encoding: 'utf-8', separator: ';',
    });
    expect(r.entityType).toBe('mixed');
    expect(r.suggestedMapping['CNPJ/CPF']).toBe('cnpj_cpf');
  });

  it('formato desconhecido volta com confiança 0 e sem mapeamento — não chuta', () => {
    const r = detectFormat({ headers: ['coluna_a', 'coluna_b'], rows: [{}, {}], encoding: 'utf-8', separator: ';' });
    expect(r.format).toBe('generic');
    expect(r.confidence).toBe(0);
    expect(r.suggestedMapping).toEqual({});
    expect(r.recordCount).toBe(2);
  });
});

describe('transformValue — converter texto de planilha em dado', () => {
  it('vazio, nulo e indefinido viram null', () => {
    for (const v of ['', '   ', null, undefined]) {
      expect(transformValue(v, 'name')).toBeNull();
    }
  });

  it('"Ativo" e afins viram true; o resto vira false', () => {
    for (const v of ['Ativo', 'ativo', 'true', '1', 'Sim', 'sim', 'yes']) {
      expect(transformValue(v, 'active'), `${v} deveria ser true`).toBe(true);
    }
    for (const v of ['Inativo', 'nao', '0', 'false']) {
      expect(transformValue(v, 'active'), `${v} deveria ser false`).toBe(false);
    }
  });

  it('preço com vírgula decimal vira número', () => {
    expect(transformValue('89,90', 'sale_price')).toBe(89.9);
    expect(transformValue('1200.50', 'cost_price')).toBe(1200.5);
    expect(transformValue('0,01', 'default_price')).toBe(0.01);
  });

  // NOVO-import-01 (decisão do dono, 12/08/2026): era 0 — preço que parece válido e sai numa
  // proposta. Agora null, e a conferência lista a linha (celulasInvalidas).
  it('preço ilegível vira null, nunca 0 nem NaN', () => {
    expect(transformValue('sob consulta', 'sale_price')).toBeNull();
  });

  it('estoque vira inteiro', () => {
    expect(transformValue('12', 'stock_quantity')).toBe(12);
    expect(transformValue('12,7', 'stock_quantity')).toBe(12);
    expect(transformValue('abc', 'minimum_stock')).toBeNull();
  });

  it('PJ/PF viram company/individual, com company como padrão', () => {
    expect(transformValue('PJ', '_type')).toBe('company');
    expect(transformValue('PF', '_type')).toBe('individual');
    expect(transformValue('qualquer', '_type')).toBe('company');
  });

  it('campo de texto chega aparado', () => {
    expect(transformValue('  Cabo 6mm  ', 'name')).toBe('Cabo 6mm');
  });

  // [NOVO-017a] CORRIGIDO. `parseFloat(str.replace(',', '.'))` trocava só a PRIMEIRA vírgula e
  // deixava o ponto de milhar: "1.234,56" virava "1.234.56" e o parseFloat parava em 1.234.
  it('[NOVO-017] preço pt-BR com milhar entra inteiro', () => {
    expect(transformValue('1.234,56', 'sale_price')).toBe(1234.56);
    expect(transformValue('12.500,00', 'cost_price')).toBe(12500);
    expect(transformValue('1.234.567,89', 'sale_price')).toBe(1234567.89);
  });

  it('[NOVO-017] preço en-US também entra inteiro', () => {
    // O arquivo pode vir de um ERP configurado em inglês. O último separador manda.
    expect(transformValue('1,234.56', 'sale_price')).toBe(1234.56);
    expect(transformValue('12,500.00', 'cost_price')).toBe(12500);
  });

  it('[NOVO-017] formas simples continuam valendo', () => {
    expect(transformValue('89,90', 'sale_price')).toBe(89.9);
    expect(transformValue('89.90', 'sale_price')).toBe(89.9);
    // Um separador só, com uma casa: decimal nos dois idiomas.
    expect(transformValue('12,5', 'sale_price')).toBe(12.5);
    expect(transformValue('12.5', 'sale_price')).toBe(12.5);
    expect(transformValue('1234', 'sale_price')).toBe(1234);
    expect(transformValue('0', 'sale_price')).toBe(0);
  });

  it('[NOVO-017] célula vazia é null, não zero — vazio e "0" são informações diferentes', () => {
    // "0" é um preço declarado; célula em branco é ausência de preço. Misturar os dois faria
    // o importador gravar R$ 0,00 em produto cujo preço ninguém informou.
    expect(transformValue('', 'sale_price')).toBeNull();
    expect(transformValue('   ', 'cost_price')).toBeNull();
    expect(transformValue('', 'stock_quantity')).toBeNull();
  });

  it('[NOVO-017] símbolo de moeda e espaço do Excel não atrapalham', () => {
    expect(transformValue('R$ 1.234,56', 'sale_price')).toBe(1234.56);
    // Espaço não-quebrável (U+00A0) — o que o Excel de fato exporta.
    expect(transformValue('R$ 1.234,56', 'sale_price')).toBe(1234.56);
  });

  it('[NOVO-017] negativo, inclusive o contábil entre parênteses', () => {
    expect(transformValue('-1.234,56', 'cost_price')).toBe(-1234.56);
    expect(transformValue('(1.234,56)', 'cost_price')).toBe(-1234.56);
  });

  it('[NOVO-017] "1.500" é mil e quinhentos, não um e meio', () => {
    // O caso genuinamente ambíguo: ponto seguido de EXATAMENTE 3 dígitos. Resolvido como
    // milhar porque este é um ERP brasileiro e preço com 3 casas decimais é raro em catálogo.
    // Registrado no livro do turno para o dono revisar.
    expect(transformValue('1.500', 'stock_quantity')).toBe(1500);
    expect(transformValue('1.500', 'sale_price')).toBe(1500);
    // Duas casas depois do ponto continua sendo decimal.
    expect(transformValue('1.50', 'sale_price')).toBe(1.5);
  });

  it('[NOVO-017] estoque trunca em vez de arredondar', () => {
    // "1.500,80" são 1.500 unidades na prateleira; arredondar inventaria uma.
    expect(transformValue('1.500,80', 'stock_quantity')).toBe(1500);
    expect(transformValue('3,9', 'minimum_stock')).toBe(3);
  });

  it('[NOVO-017 / NOVO-import-01] texto sem dígito nenhum vira null (decisão do dono, 12/08/2026)', () => {
    // Era 0, preservado até a decisão de produto. O dono decidiu: importar null e listar na
    // conferência, nunca 0 calado (audit/relatorio-noturno-20260811.md, tabela de decisões).
    expect(transformValue('sob consulta', 'sale_price')).toBeNull();
  });
});

describe('applyMapping — do arquivo para os campos do sistema', () => {
  it('mapeia coluna a coluna, aplicando a conversão de cada destino', () => {
    const linhas = [{ 'Nome do Produto (120)': 'Cabo 6mm', 'Valor Venda (Tabela Padrão)': '89,90', 'Situação (Ativo/Inativo)': 'Ativo' }];
    expect(applyMapping(linhas, {
      'Nome do Produto (120)': 'name',
      'Valor Venda (Tabela Padrão)': 'sale_price',
      'Situação (Ativo/Inativo)': 'active',
    }, 'products')).toEqual([{ name: 'Cabo 6mm', sale_price: 89.9, active: true }]);
  });

  it('coluna mapeada para null é ignorada', () => {
    expect(applyMapping([{ a: '1', b: '2' }], { a: 'name', b: null }, 'products'))
      .toEqual([{ name: '1' }]);
  });

  it('coluna que não existe na linha vira null, sem quebrar', () => {
    expect(applyMapping([{ a: '1' }], { a: 'name', inexistente: 'sku' }, 'products'))
      .toEqual([{ name: '1', sku: null }]);
  });

  // [NOVO-017b] CORRIGIDO. O mapeamento de clientes manda 'Celular' E 'Telefone' para o mesmo
  // campo `phone`; a atribuição era incondicional e o vazio ganhava do preenchido.
  it('[NOVO-017] coluna vazia NÃO apaga o que outra já preencheu', () => {
    const resultado = applyMapping(
      [{ Celular: '(47) 99999-0000', Telefone: '' }],
      { Celular: 'phone', Telefone: 'phone' },
      'clients',
    );
    expect(resultado[0].phone).toBe('(47) 99999-0000');
  });

  it('[NOVO-017] vale nos dois sentidos — a ordem das colunas não decide quem sobrevive', () => {
    // A planilha pode trazer 'Telefone' antes de 'Celular'. Se a regra dependesse da ordem,
    // metade dos arquivos continuaria perdendo o número.
    const resultado = applyMapping(
      [{ Telefone: '', Celular: '(47) 99999-0000' }],
      { Telefone: 'phone', Celular: 'phone' },
      'clients',
    );
    expect(resultado[0].phone).toBe('(47) 99999-0000');
  });

  it('[NOVO-017] coluna só com espaços conta como vazia', () => {
    // Planilha exportada de outro ERP traz " " onde não tinha nada. Se espaço contasse como
    // valor, o celular seria apagado do mesmo jeito — só que por um caractere invisível.
    const resultado = applyMapping(
      [{ Celular: '(47) 99999-0000', Telefone: '   ' }],
      { Celular: 'phone', Telefone: 'phone' },
      'clients',
    );
    expect(resultado[0].phone).toBe('(47) 99999-0000');
  });

  it('[NOVO-017] preenchido AINDA sobrescreve preenchido — corrigir continua possível', () => {
    // A correção não pode virar "o primeiro valor tranca o campo": quando as duas colunas têm
    // número, a última continua vencendo, que era o comportamento pretendido.
    const resultado = applyMapping(
      [{ Celular: '(47) 90000-0000', Telefone: '(47) 3348-0000' }],
      { Celular: 'phone', Telefone: 'phone' },
      'clients',
    );
    expect(resultado[0].phone).toBe('(47) 3348-0000');
  });

  it('[NOVO-017] campo que só tem coluna vazia continua null', () => {
    const resultado = applyMapping([{ Celular: '' }], { Celular: 'phone' }, 'clients');
    expect(resultado[0].phone).toBeNull();
  });
});

describe('NOVO-import-01 — texto no lugar de número é listado, nunca vira 0', () => {
  const linhas = [
    { Nome: 'Anodo', Preco: '35,90', Estoque: '3' },
    { Nome: 'Bomba', Preco: 'sob consulta', Estoque: '2' },
    { Nome: 'Cabo', Preco: '', Estoque: 'muitos' },
  ];
  const mapa = { Nome: 'name', Preco: 'sale_price', Estoque: 'stock_quantity' };

  it('a conferência diz linha (1 é o cabeçalho), campo e o texto; célula vazia não entra', () => {
    expect(celulasInvalidas(linhas, mapa)).toEqual([
      { linha: 3, campo: 'sale_price', valor: 'sob consulta' },
      { linha: 4, campo: 'stock_quantity', valor: 'muitos' },
    ]);
  });

  it('a linha mapeada marca o campo inválido; atualizar sem ele não apaga o valor atual', () => {
    const [ok, bomba, cabo] = applyMapping(linhas, mapa, 'products');
    expect(campoInvalido(ok, 'sale_price')).toBe(false);
    expect(campoInvalido(bomba, 'sale_price')).toBe(true);
    expect(bomba.sale_price).toBeNull();
    // Vazio é vazio, não texto inválido.
    expect(campoInvalido(cabo, 'sale_price')).toBe(false);
    expect(campoInvalido(cabo, 'stock_quantity')).toBe(true);
    expect(semCamposInvalidos(bomba)).toEqual({ name: 'Bomba', stock_quantity: 2 });
    expect(semCamposInvalidos(ok)).toEqual({ name: 'Anodo', sale_price: 35.9, stock_quantity: 3 });
  });
});

// NOVO-import-02 (06/10/2026): duas colunas para o mesmo campo — o mapeamento avisa.
describe('colunasNoMesmoCampo', () => {
  const mapping = { Celular: 'phone', Telefone: 'phone', Nome: 'name', Obs: null };

  it('acha o grupo e conta só as linhas com valores DIFERENTES nas duas', () => {
    const rows = [
      { Celular: '47 99999-0000', Telefone: '', Nome: 'A' },            // só uma: sem conflito
      { Celular: '47 99999-0000', Telefone: '47 3333-0000', Nome: 'B' }, // conflito
      { Celular: ' 47 1 ', Telefone: '47 1', Nome: 'C' },                // iguais depois do trim
    ];
    expect(colunasNoMesmoCampo(rows, mapping)).toEqual([{ campo: 'phone', colunas: ['Celular', 'Telefone'], conflitos: 1 }]);
  });

  it('sem colunas repetidas (ou só ignoradas), nada a avisar', () => {
    expect(colunasNoMesmoCampo([{ Nome: 'A' }], { Nome: 'name', Obs: null, Extra: null })).toEqual([]);
  });
});
