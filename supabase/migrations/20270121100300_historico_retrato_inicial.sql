-- Histórico de documentos: RETRATO INICIAL (v1, marco "inicial") de todo orçamento/OS que existe hoje.
--
-- ESCREVE DADOS: só se aplica com o OK nomeado do dono (CLAUDE.md). Sem ele, a primeira versão de cada documento
-- só nasceria no próximo marco (enviado, aprovado...) — e "como estava antes da primeira mudança" ficaria sem
-- resposta para os documentos antigos. Princípio da carga inicial (temporal_tables/nearform, BC "archive").
--
-- Depende de 20270121100000_historico_de_documentos_captura (private.documento_versionar).
-- Idempotente: documento_versionar só grava se o retrato mudou desde o último — rodar de novo não duplica.
-- Volume medido em 16/11/2026: 133 documentos, ~3-5 KB cada (< 1 MB no total).
do $$
declare
  v_id uuid;
  v_n  integer := 0;
begin
  -- num bloco só: os set_config locais valem para a transação inteira
  perform set_config('marineflow.historico_origem', 'migracao', true);
  perform set_config('marineflow.historico_motivo', 'Retrato inicial: estado do documento ao ligar o histórico', true);
  for v_id in select id from public.service_orders order by created_at, id loop
    perform private.documento_versionar(v_id, 'inicial');
    v_n := v_n + 1;
  end loop;
  raise notice 'retrato inicial: % documentos', v_n;
end $$;
