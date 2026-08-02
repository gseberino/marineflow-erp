-- ═══════════════════════════════════════════════════════════════════════════
-- Os 4 serviços de teste que a salvaguarda tinha preservado
--
-- A migration de 02/08 deixou de fora quatro serviços de nome suspeito porque
-- tinham faturamento atrás — a regra era "nome de teste com dinheiro não é
-- lixo, é engano". O dono esclareceu: o dinheiro também era de teste. Eles
-- foram criados para exercitar parâmetros de valor em OS e orçamentos que
-- igualmente não eram reais.
--
-- Com isso a salvaguarda perde a razão de existir para estes quatro, e eles
-- saem do catálogo como os outros nove.
--
-- As OS que os usam NÃO são tocadas aqui: mexer em ordem de serviço é decisão
-- do dono, e há um efeito colateral maior a discutir antes — metade das OS
-- concluídas do banco é do cliente "TESTE AUDITORIA CLAUDE", o que envenenaria
-- qualquer estatística de tempo ou base de casos construída sobre elas.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
declare v_inativados integer;
begin
  update public.services
  set active = false, updated_at = now()
  where active
    and id in (
      'b36a5930-ed56-4411-b7be-0d5f61d57f2f',  -- Serviço Teste Auditoria
      '337677e0-0c62-415d-9682-dc023e9b746d',  -- Teste serviço
      '70092082-3fd6-4e04-ab55-1cebc46ebe28',  -- Teste Funcional OK
      '048cda93-d91d-4bf8-a195-893a1cdafcbb'   -- testet
    );

  get diagnostics v_inativados = row_count;
  raise notice 'Serviços de teste com valor inativados: %', v_inativados;
end $$;
