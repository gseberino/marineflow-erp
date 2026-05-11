export type DuplicateKeyRule = Record<string, string[]>;

export type ForeignKeyRule = {
  table: string;
  column: string;
  references: string;
};

export const duplicateKeyRules: DuplicateKeyRule = {
  clients: ['email', 'cpf_cnpj'],
  suppliers: ['email', 'cnpj_cpf'],
  services: ['name'],
};

export const foreignKeyRules: ForeignKeyRule[] = [
  { table: 'service_orders', column: 'client_id', references: 'clients' },
  { table: 'service_orders', column: 'vessel_id', references: 'vessels' },
  { table: 'service_order_parts', column: 'service_order_id', references: 'service_orders' },
  { table: 'service_order_services', column: 'service_order_id', references: 'service_orders' },
  { table: 'service_order_technicians', column: 'service_order_id', references: 'service_orders' },
  { table: 'external_quotes', column: 'lead_id', references: 'external_quote_leads' },
];

export const importGuardMessage =
  'Set CONFIRM_IMPORT=true only after backup confirmation, dry-run approval, and explicit authorization.';
