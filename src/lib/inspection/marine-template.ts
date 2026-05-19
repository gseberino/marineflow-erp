export type InspectionItemStatus =
  | 'pending'
  | 'ok'
  | 'attention'
  | 'critical'
  | 'not_applicable';

export type InspectionTemplateItem = {
  id: string;
  systemGroup: string;
  category: string;
  label: string;
  hint?: string;
};

export type InspectionDraftItem = InspectionTemplateItem & {
  status: InspectionItemStatus;
  observations?: string;
};

export const INSPECTION_STATUS_LABEL: Record<InspectionItemStatus, string> = {
  pending: 'Pendente',
  ok: 'Conforme',
  attention: 'Atenção',
  critical: 'Crítico',
  not_applicable: 'Não se aplica',
};

export const MARINE_INSPECTION_TEMPLATE: InspectionTemplateItem[] = [
  // Armazenamento de Energia
  {
    id: 'bat-fixacao',
    systemGroup: 'Armazenamento de Energia',
    category: 'Banco de Baterias',
    label: 'Estado físico, limpeza e fixação estrutural rígida',
    hint: 'Avaliar corrosão, vibração e isolamento dos terminais.',
  },
  {
    id: 'bat-ventilacao',
    systemGroup: 'Armazenamento de Energia',
    category: 'Banco de Baterias',
    label: 'Ventilação do compartimento e proteção contra gases',
  },
  {
    id: 'bat-fusivel-principal',
    systemGroup: 'Armazenamento de Energia',
    category: 'Banco de Baterias',
    label: 'Fusível principal (MRBF/ANL) a até 7" dos bornes',
    hint: 'ABYC E-11 — proteção contra curto-circuito.',
  },
  {
    id: 'bat-bms',
    systemGroup: 'Armazenamento de Energia',
    category: 'Banco de Baterias',
    label: 'BMS / monitor de bateria responsivo e calibrado',
  },

  // Distribuição DC
  {
    id: 'dc-chave-principal',
    systemGroup: 'Distribuição DC',
    category: 'Distribuição e Manobra',
    label: 'Chave geral DC dimensionada e acessível',
  },
  {
    id: 'dc-cabeamento',
    systemGroup: 'Distribuição DC',
    category: 'Cabeamento',
    label: 'Cabeamento principal: bitola adequada, terminação e identificação',
    hint: 'Cores ABYC, terminais selados, proteção mecânica.',
  },
  {
    id: 'dc-painel',
    systemGroup: 'Distribuição DC',
    category: 'Painéis e Disjuntores',
    label: 'Painel DC: disjuntores, etiquetas e barramento',
  },
  {
    id: 'dc-queda-tensao',
    systemGroup: 'Distribuição DC',
    category: 'Cabeamento',
    label: 'Queda de tensão dentro do limite (cálculo auxiliar abaixo)',
    hint: 'Crítico: ≤3%. Geral: ≤10%.',
  },

  // Geração e Conversão
  {
    id: 'gen-alternador',
    systemGroup: 'Geração e Conversão',
    category: 'Geração',
    label: 'Alternador / regulador externo: estado e parâmetros',
  },
  {
    id: 'gen-inversor',
    systemGroup: 'Geração e Conversão',
    category: 'Inversores',
    label: 'Inversor/carregador: instalação, ventilação e proteção',
  },
  {
    id: 'gen-solar',
    systemGroup: 'Geração e Conversão',
    category: 'Solar',
    label: 'Painéis solares: fixação, vedação e controlador MPPT',
  },

  // Sistema AC
  {
    id: 'ac-tomada-shore',
    systemGroup: 'Sistema AC',
    category: 'Entrada Shore Power',
    label: 'Tomada/shore power: condição, gasket e selagem',
  },
  {
    id: 'ac-elci',
    systemGroup: 'Sistema AC',
    category: 'Proteção AC',
    label: 'ELCI / dispositivo diferencial principal funcional',
  },
  {
    id: 'ac-painel',
    systemGroup: 'Sistema AC',
    category: 'Painéis AC',
    label: 'Painel AC: disjuntores, voltímetro e identificação de circuitos',
  },

  // Aterramento e Segurança
  {
    id: 'gnd-bonding',
    systemGroup: 'Aterramento e Segurança',
    category: 'Bonding',
    label: 'Sistema de bonding contínuo e medido',
  },
  {
    id: 'gnd-isolador',
    systemGroup: 'Aterramento e Segurança',
    category: 'Proteção Galvânica',
    label: 'Isolador galvânico ou transformador de isolação instalado',
  },
  {
    id: 'gnd-extintor',
    systemGroup: 'Aterramento e Segurança',
    category: 'Segurança',
    label: 'Detecção de gás/fumaça e extintor próximo ao painel',
  },
];

export function createDraftFromTemplate(
  template: InspectionTemplateItem[] = MARINE_INSPECTION_TEMPLATE,
): InspectionDraftItem[] {
  return template.map((item) => ({ ...item, status: 'pending', observations: '' }));
}

export function groupDraftBySystem(items: InspectionDraftItem[]): Array<{
  systemGroup: string;
  items: InspectionDraftItem[];
}> {
  const map = new Map<string, InspectionDraftItem[]>();
  for (const item of items) {
    const arr = map.get(item.systemGroup) ?? [];
    arr.push(item);
    map.set(item.systemGroup, arr);
  }
  return Array.from(map.entries()).map(([systemGroup, items]) => ({ systemGroup, items }));
}
