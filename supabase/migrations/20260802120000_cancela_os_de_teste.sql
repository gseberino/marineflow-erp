-- ═══════════════════════════════════════════════════════════════════════════
-- As OS de teste saem da amostra (autorizado pelo dono em 02/08)
--
-- Três OS do cliente "TESTE AUDITORIA CLAUDE" estavam com status `completed`.
-- Em dinheiro são R$ 870 de R$ 38.443 — 2%. Em contagem eram METADE das seis OS
-- concluídas do banco, e é a contagem que envenena o que vem pela frente:
-- a base de casos (estimativa por analogia), os tempos P50/P80 da Fase 6 e o
-- aprendizado da Fase 7 saem todos das OS concluídas. Metade da amostra sendo
-- ficção, qualquer número nasceria torto — e do jeito difícil de perceber,
-- porque pareceria legítimo.
--
-- Usa a função oficial `cancel_service_order_cascade` em vez de UPDATE direto:
-- é ela que sabe desfazer recebível, pagamento e conciliação bancária. Nestas
-- três não há nenhum dos casos (0 recebíveis, 0 pagamentos, 0 comissões), então
-- na prática ela muda o status e deixa o trigger de estoque agir.
--
-- Efeito de estoque esperado: a OS-00025 tem 1 baixa registrada. Ao sair de
-- `completed`, o trigger devolve a peça ao estoque criando um movimento de
-- estorno COM referência (`reverses_movement_id`) — que é o comportamento
-- correto, e o oposto do estoque fantasma que já apareceu neste sistema quando
-- o estorno não tinha referência.
--
-- O que NÃO acontece: nada é enviado ao cliente. O gancho de ciclo de vida
-- (ai-lifecycle-hooks) apenas registra o evento e resolve alertas pendentes.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
declare
  r record;
  v_resultado json;
begin
  for r in
    select so.id, so.service_order_number, so.status
    from public.service_orders so
    join public.clients c on c.id = so.client_id
    where c.name = 'TESTE AUDITORIA CLAUDE'
      and so.status <> 'cancelled'
  loop
    v_resultado := public.cancel_service_order_cascade(
      r.id,
      'OS de teste — criada para validar parâmetros de valor, não é atendimento real. '
      || 'Cancelada em 02/08/2026 para não contaminar a base de casos e as estatísticas de tempo.'
    );
    raise notice 'OS % (%): %', r.service_order_number, r.status, v_resultado;
  end loop;
end $$;
