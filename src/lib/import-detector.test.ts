// Cobertura do detector/importador de CSV — módulo sem teste até agora.
//
// É por aqui que entra catálogo inteiro de produto, serviço e cadastro vindo de outro ERP.
// Um erro aqui não aparece como erro: aparece como preço, estoque ou telefone errado em
// centenas de linhas de uma vez, já gravados, misturados aos certos.
//
// Dois defeitos reais apareceram enquanto eu escrevia estes casos — `NOVO-017` em
// audit/novos-achados.md. Estão documentados abaixo pelo que fazem HOJE, marcados com o ID,
// para que a correção seja uma decisão e não um efeito colateral.
import { describe, it, expect } from 'vitest';
import { parseCSVContent, detectFormat, transformValue, applyMapping } from './import-detector';

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

  it('preço ilegível vira 0 em vez de NaN', () => {
    expect(transformValue('sob consulta', 'sale_price')).toBe(0);
  });

  it('estoque vira inteiro', () => {
    expect(transformValue('12', 'stock_quantity')).toBe(12);
    expect(transformValue('12,7', 'stock_quantity')).toBe(12);
    expect(transformValue('abc', 'minimum_stock')).toBe(0);
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
    expect(transformValue('1234', 'sale_price')).toBe(1234);
    expect(transformValue('0', 'sale_price')).toBe(0);
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

  it('[NOVO-017] texto sem dígito nenhum continua caindo em 0', () => {
    // Comportamento PRESERVADO de propósito: mudar para null/erro é decisão de produto,
    // registrada no livro do turno. O que se corrigiu foi a leitura errada, não este contrato.
    expect(transformValue('sob consulta', 'sale_price')).toBe(0);
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
