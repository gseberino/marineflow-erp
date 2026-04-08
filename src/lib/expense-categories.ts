export const OPERATIONAL_EXPENSE_CATEGORIES = [
  'Alimentação',
  'Combustível',
  'Pedágio',
  'Estacionamento',
  'Ferry / Transporte aquático',
  'Transporte (uber/taxi)',
  'Hospedagem',
  'Ferramentas e consumíveis',
  'Material de apoio',
  'Outros',
] as const;

export type ExpenseCategory = typeof OPERATIONAL_EXPENSE_CATEGORIES[number];
