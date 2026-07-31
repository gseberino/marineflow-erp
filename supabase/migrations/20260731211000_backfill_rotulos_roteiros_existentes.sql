-- ═══════════════════════════════════════════════════════════════════════════
-- Backfill: os roteiros já gerados passam a usar os rótulos novos
--
-- A OS-00051 e as outras que o dono gerou hoje ficaram com "Preparação ·
-- Eletrônico" — o rótulo que ele apontou como confuso. Regerar é a forma mais
-- limpa de aplicar block_key/block_note, porque a composição é determinística:
-- os mesmos blocos aprovados produzem os mesmos passos.
--
-- SALVAGUARDA: só regenera OS em que NADA foi executado — nenhum passo fora de
-- 'pending', sem início, sem tempo apontado — e em que todos os passos vieram
-- de template ou composição. Roteiro com trabalho registrado ou com passo
-- escrito à mão fica intocado; nesse caso o rótulo velho é preferível a perder
-- o que o técnico anotou.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
declare
  r record;
  v_passos integer;
  v_os integer := 0;
  v_total integer := 0;
begin
  for r in
    select distinct service_order_id from public.service_order_steps
  loop
    -- Alguém já mexeu neste roteiro? Então não se toca nele.
    if exists (
      select 1 from public.service_order_steps
      where service_order_id = r.service_order_id
        and (status <> 'pending'
             or started_at is not null
             or actual_minutes is not null
             or completed_at is not null
             or notes is not null
             or origin not in ('template','composed'))
    ) then
      raise notice 'OS % preservada: tem trabalho registrado ou passo manual.', r.service_order_id;
      continue;
    end if;

    delete from public.service_order_steps where service_order_id = r.service_order_id;
    v_passos := public.generate_service_order_steps(r.service_order_id);
    v_os := v_os + 1;
    v_total := v_total + v_passos;
  end loop;

  raise notice 'Roteiros regenerados: % OS, % passos.', v_os, v_total;
end $$;
