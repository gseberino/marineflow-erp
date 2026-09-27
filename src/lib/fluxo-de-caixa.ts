// Fluxo de caixa pelo extrato — a regra mora em supabase/functions/_shared/banking/fluxo-de-caixa.ts
// e é importada daqui: a tela, o painel inicial e o assistente contam "entrou" e "saiu" do
// mesmo jeito (revisão de 27/09/2026 — eram três números diferentes para o mesmo mês).
export * from '../../supabase/functions/_shared/banking/fluxo-de-caixa';
