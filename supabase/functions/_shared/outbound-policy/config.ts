// Outbound Policy Engine — configuração padrão
//
// Estes são valores CONSERVADORES de partida. Os números de negócio reais
// (limites de valor, horário comercial) devem ser confirmados pelo usuário e,
// futuramente, carregados de uma tabela de config (app_settings) para ajuste
// sem deploy. Por ora ficam aqui como default seguro.

import type { PolicyConfig } from "./types.ts";

export const DEFAULT_POLICY_CONFIG: PolicyConfig = {
  // Começa em SOMBRA: nada é executado automaticamente; só registramos o que
  // teria acontecido. Liga-se de verdade só depois de validar as decisões.
  shadowMode: true,

  // Gestor de aprovações: contato único de WhatsApp que recebe confirmações,
  // lembretes e avisos. Definido pelo usuário em app_settings (não hardcoded).
  approvalManager: { whatsapp: null },

  // Conservador de partida: TODO envio ao cliente (orçamento incluído) é
  // confirmado pelo gestor no WhatsApp antes de sair. Afrouxa por tipo depois.
  clientSendsRequireManagerConfirmation: true,

  // Cliente conhecido: auto-envio de orçamento/link abaixo de R$ 1.500.
  autoSendMaxValue: 1500,
  // Lead novo/desconhecido: muito mais rígido.
  newLeadAutoSendMaxValue: 0,

  // Horário comercial: seg–sex (1..5), 8h–18h.
  businessHours: { startHour: 8, endHour: 18, days: [1, 2, 3, 4, 5] },

  // Não manda 2x para o mesmo destinatário em menos de 6 horas.
  minFrequencyGapMinutes: 360,

  // Confiança mínima do modelo para auto-envio.
  minAiConfidence: 0.8,

  // Dinheiro/legal: SEMPRE humano, sem exceção.
  alwaysHumanTypes: [
    "send_charge",
    "send_collection_reminder",
    "request_client_confirmation",
  ],
};
