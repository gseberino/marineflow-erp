-- ═══════════════════════════════════════════════════════════════════════════
-- Restos de teste saem do catálogo (autorizado pelo dono em 02/08)
--
-- Doze serviços criados em testes de desenvolvimento poluem a busca, a
-- classificação e qualquer relatório por serviço. Inativar não apaga nada: as
-- OS antigas que os referenciam continuam intactas, com o nome preservado em
-- name_snapshot. Eles apenas param de aparecer para quem monta orçamento.
--
-- Só entram nomes inequívocos. Qualquer serviço com faturamento ou uso real
-- ficaria de fora — por isso a condição extra sobre valor cobrado.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
declare v_inativados integer;
begin
  update public.services s
  set active = false, updated_at = now()
  where s.active
    and s.id in (
      '6b5479b9-47bf-4c9d-8908-3395588ca64a',  -- Test Service
      '884b3962-beed-4ef1-b530-64f9353ec0f4',  -- Test Service
      'b36a5930-ed56-4411-b7be-0d5f61d57f2f',  -- Serviço Teste Auditoria
      'b85d1790-17b1-4128-a7d5-4dfd9fed7b13',  -- Teste de Sistema
      '694e540d-9b3f-4dcc-8f4c-f2422625ba71',  -- Teste de Sistema
      '5a61d45b-b3dc-4bd2-bd7c-da96c4982f72',  -- Teste de Sistema
      'd2197dbe-52e3-4bba-a13d-ef1736c9b41a',  -- Teste de Sistema
      '98b65aae-c97f-4c8b-905f-2cc5bce1cef9',  -- Teste de Sistema
      'a25af8fe-8a5b-40af-8d89-b3b73a769934',  -- Teste de Sistema
      'fa9feaa5-52f7-4225-a951-7e89f7a8f325',  -- Teste de Sistema
      '70092082-3fd6-4e04-ab55-1cebc46ebe28',  -- Teste Funcional OK
      '337677e0-0c62-415d-9682-dc023e9b746d',  -- Teste serviço
      '048cda93-d91d-4bf8-a195-893a1cdafcbb'   -- testet
    )
    -- Salvaguarda: se algum deles foi de fato cobrado em OS, fica de pé para o
    -- dono decidir. Nome de teste com dinheiro atrás não é lixo, é engano.
    and not exists (
      select 1 from public.service_order_services sos
      where sos.service_id = s.id and coalesce(sos.line_total, 0) > 0
    );

  get diagnostics v_inativados = row_count;
  raise notice 'Serviços de teste inativados: %', v_inativados;
end $$;
