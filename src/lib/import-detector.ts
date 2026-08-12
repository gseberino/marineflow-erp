export type KnownFormat = 'vhsys_products' | 'vhsys_services' | 'vhsys_clients' | 'generic';

export type ColumnMapping = {
  [sourceColumn: string]: string | null;
};

export type ParsedFile = {
  headers: string[];
  rows: Record<string, any>[];
  encoding: string;
  separator: string;
};

export type DetectionResult = {
  format: KnownFormat;
  formatLabel: string;
  entityType: 'products' | 'services' | 'clients' | 'suppliers' | 'mixed';
  confidence: number;
  suggestedMapping: ColumnMapping;
  recordCount: number;
};

export function parseCSVContent(content: string, encoding: string = 'utf-8'): ParsedFile {
  let separator = ';';
  const firstLine = content.split('\n')[0] || '';
  if (!firstLine.includes(';') && firstLine.includes(',')) {
    separator = ',';
  }

  const lines = content.split('\n').map(l => l.trim()).filter(l => l.length > 0);
  if (lines.length === 0) return { headers: [], rows: [], encoding, separator };

  const parseLine = (line: string): string[] => {
    const result: string[] = [];
    let current = '';
    let inQuotes = false;
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (ch === '"') {
        if (inQuotes && line[i + 1] === '"') {
          current += '"';
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch === separator && !inQuotes) {
        result.push(current.trim());
        current = '';
      } else {
        current += ch;
      }
    }
    result.push(current.trim());
    return result;
  };

  const headers = parseLine(lines[0]);
  const rows = lines.slice(1).map(line => {
    const values = parseLine(line);
    const obj: Record<string, any> = {};
    headers.forEach((h, i) => {
      obj[h] = values[i] ?? '';
    });
    return obj;
  });

  return { headers, rows, encoding, separator };
}

export function detectFormat(parsed: ParsedFile): DetectionResult {
  const { headers, rows } = parsed;

  // Bling Products/Services
  if (headers.includes('Tipo (Produto/Servico)') && headers.includes('Valor Venda (Tabela Padrão)')) {
    const types = rows.map(r => r['Tipo (Produto/Servico)']).filter(Boolean);
    const allServices = types.length > 0 && types.every(t => t === 'Servico' || t === 'Serviço');
    const allProducts = types.length > 0 && types.every(t => t === 'Produto');

    if (allServices) {
      return {
        format: 'vhsys_services',
        formatLabel: 'VHSYS — Serviços',
        entityType: 'services',
        confidence: 95,
        recordCount: rows.length,
        suggestedMapping: {
          'Nome do Produto (120)': 'name',
          'Valor Venda (Tabela Padrão)': 'default_price',
          'Observações': 'notes',
          'Situação (Ativo/Inativo)': 'active',
        },
      };
    }

    return {
      format: 'vhsys_products',
      formatLabel: 'VHSYS — Produtos',
      entityType: 'products',
      confidence: 95,
      recordCount: allProducts ? rows.length : rows.filter(r => r['Tipo (Produto/Servico)'] === 'Produto').length,
      suggestedMapping: {
        'Código do Produto (60)': 'sku',
        'Nome do Produto (120)': 'name',
        'Valor Venda (Tabela Padrão)': 'sale_price',
        'Valor Custo': 'cost_price',
        'Estoque Atual': 'stock_quantity',
        'Estoque Mínimo': 'minimum_stock',
        'Unidade (06)': 'unit',
        'Marca (25)': 'brand',
        'Localização no Estoque': 'location_bin',
        'Observações': 'notes',
        'Situação (Ativo/Inativo)': 'active',
        'Fornecedor': '_supplier_name',
        'NCM (8)': 'ncm',
        'Código de Barras (GTIN-8,12,13,14)': 'barcode',
        'Origem (0 a 8)': 'fiscal_origin',
      },
    };
  }

  // VHSYS Clients/Suppliers
  if (headers.includes('Razao Social/Nome') && headers.includes('Tipo Cadastro (Cliente/Fornecedor/Ambos)')) {
    return {
      format: 'vhsys_clients',
      formatLabel: 'VHSYS — Clientes e Fornecedores',
      entityType: 'mixed',
      confidence: 95,
      recordCount: rows.length,
      suggestedMapping: {
        'Razao Social/Nome': 'name',
        'Fantasia': 'trade_name',
        'CNPJ/CPF': 'cnpj_cpf',
        'Tipo Pessoa (PJ/PF)': '_type',
        'Tipo Cadastro (Cliente/Fornecedor/Ambos)': '_entity_type',
        'Endereco': 'address_line_1',
        'Numero': 'address_number',
        'Bairro': 'neighborhood',
        'Complemento': 'address_complement',
        'CEP': 'postal_code',
        'Cidade': 'city',
        'UF': 'state',
        'Celular': 'phone',
        'Telefone': 'phone',
        'E-mail': 'email',
        'Observacoes': 'notes',
        'Situacao (Ativo/Inativo)': 'active',
      },
    };
  }

  return {
    format: 'generic',
    formatLabel: 'Formato desconhecido',
    entityType: 'products',
    confidence: 0,
    recordCount: rows.length,
    suggestedMapping: {},
  };
}

/**
 * Número vindo de planilha, em pt-BR ou en-US. [NOVO-017a]
 *
 * O que havia antes era `parseFloat(str.replace(',', '.'))`, e ele tem dois furos que se
 * somam: `replace` sem flag global troca só a PRIMEIRA vírgula, e o ponto de milhar fica.
 * "1.234,56" virava "1.234.56", que o `parseFloat` lê até o segundo ponto e devolve 1.234.
 * Um produto de R$ 1.234,56 entrava no catálogo por R$ 1,23 — sem erro, no meio de centenas
 * de linhas certas.
 *
 * COMO O SEPARADOR DECIMAL É DECIDIDO, em ordem:
 *
 *  1. Se há vírgula E ponto, o ÚLTIMO a aparecer é o decimal e o outro é milhar. Vale para
 *     os dois formatos: "1.234,56" (pt-BR) e "1,234.56" (en-US).
 *  2. Se há só um tipo de separador e ele aparece MAIS DE UMA VEZ, é milhar: "1.234.567".
 *  3. Se aparece uma vez só:
 *     · vírgula  → decimal. "1234,56" = 1234,56. É o padrão pt-BR e este é um ERP brasileiro.
 *     · ponto seguido de EXATAMENTE 3 dígitos → milhar. "1.500" = 1500 unidades.
 *     · ponto em qualquer outro caso → decimal. "89.9" = 89,9.
 *
 * A regra 3 com ponto e 3 dígitos é a única genuinamente ambígua: "1.234" pode ser mil
 * duzentos e trinta e quatro (pt-BR) ou um inteiro com três decimais (en-US). Escolhi
 * pt-BR porque é o formato que o Excel local gera e porque preço com três casas decimais é
 * raro em catálogo. Está registrado no livro do turno para o dono revisar.
 *
 * Devolve `null` quando não há dígito nenhum — quem chama decide o que fazer com isso.
 */
export function parseNumeroBR(bruto: string): number | null {
  // Fora símbolo de moeda, espaço comum e espaço não-quebrável (o Excel exporta o segundo).
  const limpo = String(bruto).replace(/[R$\s ]/gi, '');
  if (!/\d/.test(limpo)) return null;

  const negativo = /^-/.test(limpo) || /^\(.*\)$/.test(limpo); // (1.234,56) = negativo contábil
  const corpo = limpo.replace(/[()-]/g, '');

  const ultimaVirgula = corpo.lastIndexOf(',');
  const ultimoPonto = corpo.lastIndexOf('.');

  let decimal: string | null = null;
  if (ultimaVirgula >= 0 && ultimoPonto >= 0) {
    decimal = ultimaVirgula > ultimoPonto ? ',' : '.';
  } else if (ultimaVirgula >= 0) {
    decimal = (corpo.match(/,/g) ?? []).length > 1 ? null : ',';
  } else if (ultimoPonto >= 0) {
    const casas = corpo.length - ultimoPonto - 1;
    const varios = (corpo.match(/\./g) ?? []).length > 1;
    decimal = varios || casas === 3 ? null : '.';
  }

  // `decimal === null` = todos os separadores são de milhar.
  const semMilhar = decimal === null
    ? corpo.replace(/[.,]/g, '')
    : corpo.split(decimal).map((p, i, a) =>
        i === a.length - 1 ? p : p.replace(/[.,]/g, '')).join('.');

  const num = Number(semMilhar);
  if (!Number.isFinite(num)) return null;
  return negativo ? -num : num;
}

export function transformValue(value: any, targetField: string): any {
  if (value === undefined || value === null || value === '') return null;
  const str = String(value).trim();
  if (str === '') return null;

  if (targetField === 'active' || targetField === '_active') {
    return ['Ativo', 'ativo', 'true', '1', 'Sim', 'sim', 'yes', 'Yes'].includes(str);
  }

  if (['sale_price', 'cost_price', 'default_price'].includes(targetField)) {
    const num = parseNumeroBR(str);
    return num === null ? 0 : num;
  }

  if (['stock_quantity', 'minimum_stock'].includes(targetField)) {
    const num = parseNumeroBR(str);
    // Trunca em vez de arredondar: estoque de "1.500,80" é 1.500 unidades, não 1.501 —
    // arredondar para cima inventaria uma unidade que não existe na prateleira.
    return num === null ? 0 : Math.trunc(num);
  }

  if (targetField === '_type') {
    if (str === 'PJ' || str === 'pj') return 'company';
    if (str === 'PF' || str === 'pf') return 'individual';
    return 'company';
  }

  return str;
}

export function applyMapping(
  rows: Record<string, any>[],
  mapping: ColumnMapping,
  _entityType: string,
): Record<string, any>[] {
  return rows.map(row => {
    const mapped: Record<string, any> = {};
    for (const [sourceCol, targetField] of Object.entries(mapping)) {
      if (!targetField) continue;
      const valor = transformValue(row[sourceCol], targetField);

      // [NOVO-017b] Coluna VAZIA não apaga o que outra coluna já preencheu.
      //
      // Mais de uma coluna de origem pode apontar para o mesmo campo — no mapeamento de
      // clientes, 'Celular' E 'Telefone' vão os dois para `phone`. A atribuição era
      // incondicional e o laço percorre o mapeamento em ordem, então um 'Telefone' em branco
      // sobrescrevia com null o celular já lido. Perdia-se justamente o número que serve para
      // WhatsApp, em silêncio, em toda linha da planilha que só preenchia 'Celular'.
      //
      // Preencher continua podendo CORRIGIR: valor não-nulo sobrescreve valor não-nulo, e a
      // última coluna preenchida vence. O que não pode é o vazio ganhar do preenchido.
      if (valor === null && mapped[targetField] != null) continue;
      mapped[targetField] = valor;
    }
    return mapped;
  });
}
