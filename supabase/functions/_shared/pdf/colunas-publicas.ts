/**
 * O que o link público da OS (/view/<token>) pode ler — e o que é só do escritório.
 *
 * Achado de 01/10/2026: o portal lia service_orders, vessels e service_order_parts com
 * `select('*')` como anônimo. O que não aparecia na tela chegava ao navegador do cliente
 * mesmo assim: custo de cada peça (e a margem), comissão, notas internas, custo e margem do
 * produto, taxa de cartão do pagamento.
 *
 * Duas camadas, que precisam concordar:
 *  1. O portal e o PDF do portal pedem SÓ as colunas abaixo (`*_PUBLICA`).
 *  2. O banco (migration 20261001190104) tira do anônimo o SELECT das colunas em
 *     `COLUNAS_INTERNAS`. Mesmo quem chamar a API direto com o token não as lê.
 * O teste colunas-publicas.test.ts garante que nenhuma lista pública peça coluna interna e
 * que a migration fecha exatamente as colunas daqui.
 *
 * Atenção ao nome enganoso: em service_orders, labor_cost_total, parts_cost_total,
 * operational_cost_total e subcontract_cost_total são valores de VENDA (entram no subtotal
 * cobrado, ver calc_so_totals). O custo de verdade das peças está em
 * service_order_parts.unit_cost_snapshot/line_total_cost. As notas do técnico e as
 * observações financeiras saem impressas no documento da OS do cliente — por isso ficam
 * públicas.
 *
 * Coluna nova numa destas tabelas nasce FECHADA para o anônimo (o grant é por coluna). Se o
 * portal precisar dela, entra aqui e numa migration nova.
 */

export const COLUNAS_INTERNAS: Record<string, readonly string[]> = {
  service_orders: [
    'internal_notes', 'commission_rate', 'commission_amount', 'commissioned_person',
    'commissioned_user_id', 'technician_instructions', 'site_access', 'estimate_confidence',
    'contingency_pct', 'original_quote_amount', 'created_by', 'hourly_rate', 'travel_cost_per_km',
  ],
  service_order_parts: ['unit_cost_snapshot', 'line_total_cost'],
  service_order_services: ['technician_instructions', 'field_status', 'field_status_note'],
  products: [
    'cost_price', 'cost_currency', 'profit_margin', 'commission_rate', 'is_commissionable',
    'stock_quantity', 'minimum_stock', 'reserved_quantity', 'location_bin', 'supplier_id',
    'notes', 'last_stock_entry_at',
  ],
  clients: ['notes', 'communication_tone'],
  marinas: ['billing_notes', 'access_notes'],
  vessels: ['access_notes'],
  payments: ['card_fee_percent', 'net_amount', 'notes', 'payable_id'],
  receivables: ['notes', 'category', 'sub_category', 'cost_center_id', 'bank_transaction_id'],
  service_order_expenses: [
    'notes', 'receipt_url', 'receipt_storage_path', 'supplier_id', 'technician_user_id',
    'reimbursed', 'reimbursed_at', 'reimbursed_payment_id', 'linked_payable_id', 'created_by',
  ],
};

/**
 * A ordem como o portal e o PDF do cliente a leem: a tela, a assinatura (hash) e o documento.
 * Texto literal de propósito: com ele o cliente tipado do Supabase sabe que colunas voltam.
 */
export const OS_PUBLICA = 'id, service_order_number, client_id, vessel_id, marina_id, status, quote_status, priority, service_type, currency, created_at, scheduled_start_at, problem_description, diagnosis, solution_applied, customer_visible_report, technician_notes, financial_notes, extra_notes, payment_conditions, payment_method_preferred, payment_condition_preset_id, payment_method, card_installments, custom_payment_installments, grand_total, labor_cost_total, parts_cost_total, travel_cost_total, travel_hours, ferry_cost, travel_type, is_travel_billable, discount_amount, discount_services_pct, discount_parts_pct, tax_amount, operational_cost_total, subcontract_cost_total, card_fee_passthrough_enabled, card_fee_amount, quote_validity_days, quote_validity_date, signed_at, signed_by_name, requires_resignature';

export const CLIENTE_PUBLICO = 'id, name, cpf_cnpj, phone, email, address_line_1, city, state';
export const VEICULO_PUBLICO = 'id, name, manufacturer, model, year, hull_id_or_registration';
export const MARINA_PUBLICA = 'id, name, city';
export const LINHA_SERVICO_PUBLICA =
  'id, name_snapshot, description_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, discount_pct, discount_amount';
export const PECA_PUBLICA =
  'id, quantity, unit_sale_snapshot, line_total_sale, discount_pct, discount_amount';
export const PRODUTO_PUBLICO = 'name, sku, image_url';
export const DESPESA_PUBLICA = 'category, description, amount, paid_by';
