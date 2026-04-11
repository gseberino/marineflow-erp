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
          'Nome do Produto (120)': 'service_name',
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
        'Nome do Produto (120)': 'product_name',
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
      },
    };
  }

  // Bling Clients/Suppliers
  if (headers.includes('Razao Social/Nome') && headers.includes('Tipo Cadastro (Cliente/Fornecedor/Ambos)')) {
    return {
      format: 'bling_clients',
      entityType: 'mixed',
      confidence: 95,
      recordCount: rows.length,
      suggestedMapping: {
        'Razao Social/Nome': 'full_name_or_company_name',
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
        'Telefone': 'contact_phone',
        'E-mail': 'email',
        'Observacoes': 'notes',
        'Situacao (Ativo/Inativo)': 'active',
      },
    };
  }

  return {
    format: 'generic',
    entityType: 'products',
    confidence: 0,
    recordCount: rows.length,
    suggestedMapping: {},
  };
}

export function transformValue(value: any, targetField: string): any {
  if (value === undefined || value === null || value === '') return null;
  const str = String(value).trim();
  if (str === '') return null;

  if (targetField === 'active' || targetField === '_active') {
    return ['Ativo', 'ativo', 'true', '1', 'Sim', 'sim', 'yes', 'Yes'].includes(str);
  }

  if (['sale_price', 'cost_price', 'default_price'].includes(targetField)) {
    const num = parseFloat(str.replace(',', '.'));
    return isNaN(num) ? 0 : num;
  }

  if (['stock_quantity', 'minimum_stock'].includes(targetField)) {
    const num = parseInt(str.replace(',', '.'), 10);
    return isNaN(num) ? 0 : num;
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
      mapped[targetField] = transformValue(row[sourceCol], targetField);
    }
    return mapped;
  });
}
