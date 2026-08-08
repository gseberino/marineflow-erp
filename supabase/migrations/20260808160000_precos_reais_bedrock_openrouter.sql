-- Preços REAIS, derivados do CSV de atividade do OpenRouter (exportado em 08/08/2026).
--
-- Duas correções sobre a migration anterior, ambas confirmadas contra linhas reais da fatura:
--
-- 1) PREÇO. Eu havia usado a tabela cheia da Anthropic (USD 3/M entrada, 15/M saída). O real:
--    o provedor é **Amazon Bedrock** (não a Anthropic direto), o modelo é
--    anthropic/claude-sonnet-5-20260630, e o preço está no PROMOCIONAL de USD 2/M entrada e
--    10/M saída. O OpenRouter não aplica markup.
--      Conferência (gen-1786105336): 75.836 prompt, 68.941 cached, 149 saída, custo 0,029068
--        75836*2/1e6 - 68941*1,80/1e6 + 149*10/1e6 = 0,029069  ✓
--      Conferência do Haiku (gen-1786220417): 2933*1/1e6 + 395*5/1e6 = 0,004908  ✓
--
--    ⚠️ O promocional vale até 31/08/2026. Depois volta para 3/15 — um aumento de 50% que
--    chega sozinho, sem ninguém mexer em nada. Reajustar a CTE quando virar o mês.
--
-- 2) MODELAGEM DA GRAVAÇÃO DE CACHE. A view anterior subtraía cache_creation do preço cheio,
--    como se gravar substituísse pagar. É o contrário: a gravação é um ADICIONAL sobre o preço
--    cheio (+25% no TTL de 5 min, +100% no de 1 h).
--      Conferência (gen-1786223556, já com TTL de 1h): 78.220 prompt, 0 cached, 273 saída
--        78220*2/1e6 + 77603*2/1e6 + 273*10/1e6 = 0,314376  ✓ (custo real: 0,314376)
--
-- Validação do conjunto: somando as 24 linhas Sonnet de 07/08 no CSV dá USD 1,627; a view dá
-- 1,397. A diferença (0,23) é precisamente a gravação dos 6 cache misses do dia, que o
-- histórico não registrava — a coluna cache_creation_tokens só passou a ser gravada em 08/08.

drop view if exists public.v_ai_custo_diario;

create view public.v_ai_custo_diario
with (security_invoker = on) as
with precos as (
  select
    2.00::numeric  as usd_entrada_por_milhao,             -- promocional até 31/08/2026 (depois 3.00)
    10.00::numeric as usd_saida_por_milhao,               -- promocional até 31/08/2026 (depois 15.00)
    0.20::numeric  as usd_leitura_cache_por_milhao,       -- 0,1x a entrada
    2.00::numeric  as usd_adicional_gravacao_por_milhao   -- +100% da entrada (TTL 1h); era +0,50 no TTL de 5min
),
base as (
  select
    date_trunc('day', m.created_at)::date  as dia,
    coalesce(m.source, 'web')              as canal,
    m.model                                as modelo,
    coalesce(m.tokens_in, 0)               as tokens_in,
    coalesce(m.tokens_out, 0)              as tokens_out,
    coalesce(m.cache_read_tokens, 0)       as cache_lido,
    coalesce(m.cache_creation_tokens, 0)   as cache_gravado,
    -- tokens_in inclui o que veio do cache; o que se paga cheio é o resto.
    -- cache_gravado NÃO entra aqui: ele já está dentro de tokens_in e é cobrado como adicional.
    greatest(0, coalesce(m.tokens_in, 0) - coalesce(m.cache_read_tokens, 0)) as tokens_preco_cheio,
    m.usd_real,
    coalesce(m.usd_cache_discount, 0)      as usd_cache_discount
  from public.ai_operator_messages m
  where m.model is not null
),
com_custo as (
  select
    b.*,
    (
      b.tokens_preco_cheio * p.usd_entrada_por_milhao
      + b.cache_lido       * p.usd_leitura_cache_por_milhao
      + b.cache_gravado    * p.usd_adicional_gravacao_por_milhao
      + b.tokens_out       * p.usd_saida_por_milhao
    ) / 1e6 as usd_estimado
  from base b
  cross join precos p
)
select
  c.dia,
  c.canal,
  c.modelo,
  count(*)                                                as chamadas,
  count(*) filter (where c.cache_lido = 0)                as chamadas_sem_cache,
  round(100.0 * count(*) filter (where c.cache_lido > 0) / nullif(count(*), 0), 1) as pct_com_cache,
  count(*) filter (where c.usd_real is not null)          as chamadas_reconciliadas,
  round(100.0 * count(*) filter (where c.usd_real is not null) / nullif(count(*), 0), 1) as pct_reconciliado,
  sum(c.tokens_in)                                        as tokens_entrada,
  sum(c.cache_lido)                                       as tokens_lidos_do_cache,
  sum(c.cache_gravado)                                    as tokens_gravados_no_cache,
  sum(c.tokens_preco_cheio)                               as tokens_preco_cheio,
  sum(c.tokens_out)                                       as tokens_saida,
  round(sum(c.usd_estimado), 4)                           as usd_estimado,
  round(sum(c.usd_real), 4)                               as usd_real_parcial,
  round(sum(coalesce(c.usd_real, c.usd_estimado)), 4)     as usd_total,
  round(sum(coalesce(c.usd_real, c.usd_estimado)) / nullif(count(*), 0), 5) as usd_por_chamada
from com_custo c
group by c.dia, c.canal, c.modelo
order by c.dia desc, c.canal;

comment on view public.v_ai_custo_diario is
  'Custo do agente por dia/canal/modelo. Precos derivados do CSV real do OpenRouter em 08/08/2026 (provedor Amazon Bedrock, sem markup): Sonnet 5 a USD 2/M entrada e 10/M saida, PROMOCIONAL ate 31/08/2026 (depois 3/15, +50%). Leitura de cache 0,20/M; gravacao +2/M no TTL de 1h, ADICIONAL ao preco cheio.';

revoke all on public.v_ai_custo_diario from anon;
grant select on public.v_ai_custo_diario to authenticated, service_role;
