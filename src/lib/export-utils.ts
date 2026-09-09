import { downloadCSV } from './download';

export type ExportColumn = {
  header: string;
  key: string;
  transform?: (value: any) => string;
};

export function exportToCSV(
  data: any[],
  filename: string,
  columns: ExportColumn[],
): void {
  const BOM = '\uFEFF';
  const header = columns.map(c => c.header).join(';');
  const rows = data.map(row =>
    columns.map(col => {
      const val = row[col.key];
      const transformed = col.transform ? col.transform(val) : (val ?? '');
      let str = String(transformed);
      // NOVO-019: c\u00E9lula come\u00E7ando com = @ (ou +/\u2212 que n\u00E3o seja n\u00FAmero) \u00E9 executada
      // como f\u00F3rmula pelo Excel ao abrir \u2014 e o conte\u00FAdo vem de campo livre do cadastro.
      // O ap\u00F3strofo neutraliza; n\u00FAmero negativo leg\u00EDtimo (-1234,56) passa intacto.
      if (/^[=@\t\r]/.test(str) || (/^[+-]/.test(str) && !/^[+-]?\d+(?:[.,]\d+)?$/.test(str))) {
        str = `'${str}`;
      }
      str = str.replace(/"/g, '""');
      // NOVO-019: aspas tamb\u00E9m exigem envelope \u2014 sem ele o `""` chega literal na planilha.
      return /[";\n]/.test(str) ? `"${str}"` : str;
    }).join(';'),
  );
  const csv = BOM + [header, ...rows].join('\n');
  downloadCSV(csv, filename);
}

export const PRODUCTS_COLUMNS: ExportColumn[] = [
  { header: 'SKU', key: 'sku' },
  { header: 'Nome do Produto', key: 'name' },
  { header: 'Categoria', key: 'category' },
  { header: 'Marca', key: 'brand' },
  { header: 'Unidade', key: 'unit' },
  { header: 'Preço de Custo', key: 'cost_price' },
  { header: 'Moeda Custo', key: 'cost_currency' },
  { header: 'Preço de Venda', key: 'sale_price' },
  { header: 'Moeda Venda', key: 'sale_currency' },
  { header: 'Estoque Atual', key: 'stock_quantity' },
  { header: 'Estoque Mínimo', key: 'minimum_stock' },
  { header: 'Localização', key: 'location_bin' },
  { header: 'Notas', key: 'notes' },
  { header: 'Situação', key: 'active', transform: v => v ? 'Ativo' : 'Inativo' },
];

export const SERVICES_COLUMNS: ExportColumn[] = [
  { header: 'Nome do Serviço', key: 'name' },
  { header: 'Categoria', key: 'category' },
  { header: 'Unidade de Cobrança', key: 'billing_unit' },
  { header: 'Preço Padrão', key: 'default_price' },
  { header: 'Moeda', key: 'currency' },
  { header: 'Descrição', key: 'description' },
  { header: 'Situação', key: 'active', transform: v => v ? 'Ativo' : 'Inativo' },
];

export const CLIENTS_COLUMNS: ExportColumn[] = [
  { header: 'Tipo', key: 'type', transform: v => v === 'company' ? 'PJ' : 'PF' },
  { header: 'Nome/Razão Social', key: 'name' },
  { header: 'CPF/CNPJ', key: 'cpf_cnpj' },
  { header: 'Email', key: 'email' },
  { header: 'Telefone', key: 'phone' },
  { header: 'WhatsApp', key: 'whatsapp' },
  { header: 'Endereço', key: 'address_line_1' },
  { header: 'CEP', key: 'postal_code' },
  { header: 'Cidade', key: 'city' },
  { header: 'Estado', key: 'state' },
  { header: 'Notas', key: 'notes' },
  { header: 'Situação', key: 'active', transform: v => v ? 'Ativo' : 'Inativo' },
];

export const VESSELS_COLUMNS: ExportColumn[] = [
  { header: 'Nome', key: 'name' },
  { header: 'Modelo', key: 'model' },
  { header: 'Fabricante', key: 'manufacturer' },
  { header: 'Ano', key: 'year' },
  { header: 'Tipo', key: 'boat_type' },
  { header: 'Material', key: 'hull_material' },
  { header: 'Comprimento (m)', key: 'length_meters' },
  { header: 'Motorização', key: 'engine_type' },
  { header: 'Registro', key: 'registration_number' },
  // NOVO-019: era key 'name' — repetia o nome da EMBARCAÇÃO na coluna da marina.
  // A lista embeda marinas(name); a célula agora lê o nome da marina de verdade.
  { header: 'Marina', key: 'marinas', transform: (v: any) => v?.name ?? '' },
  { header: 'Situação', key: 'active', transform: (v: any) => v ? 'Ativo' : 'Inativo' },
];

export const MARINAS_COLUMNS: ExportColumn[] = [
  { header: 'Marina', key: 'name' },
  { header: 'Cidade', key: 'city' },
  { header: 'Estado', key: 'state' },
  { header: 'Telefone', key: 'phone' },
  { header: 'Email', key: 'email' },
  { header: 'Total de Vagas', key: 'total_berths' },
  { header: 'Vagas Disponíveis', key: 'available_berths' },
  { header: 'Notas', key: 'notes' },
  { header: 'Situação', key: 'active', transform: (v: any) => v ? 'Ativo' : 'Inativo' },
];

export const SUPPLIERS_COLUMNS: ExportColumn[] = [
  { header: 'Razão Social', key: 'name' },
  { header: 'Nome Fantasia', key: 'trade_name' },
  { header: 'CNPJ/CPF', key: 'cnpj_cpf' },
  { header: 'Contato', key: 'contact_name' },
  { header: 'Telefone', key: 'phone' },
  { header: 'Email', key: 'email' },
  { header: 'Cidade', key: 'city' },
  { header: 'Estado', key: 'state' },
  { header: 'Notas', key: 'notes' },
  { header: 'Situação', key: 'active', transform: v => v ? 'Ativo' : 'Inativo' },
];
