-- Reverte o TTL de 1h do cache de prompt (introduzido horas antes, na mesma sessão) e devolve
-- o custo de gravação para +25% da entrada.
--
-- POR QUE REVERTER: a hipótese era que o cache de 5 min expirava entre as mensagens do dono e
-- que estendê-lo para 1 h converteria misses caros em leituras baratas. Simulação sobre 20 dias
-- de histórico real — agrupando as chamadas por turno e medindo o intervalo ENTRE turnos, já
-- que todas as linhas de um mesmo turno compartilham created_at — mostrou o contrário:
--
--     TTL 5 min ... USD 15,03
--     TTL 1 h   ... USD 15,15      (salva 22 cache misses, encarece 33)
--
-- A maior parte dos misses vem de turnos separados por MAIS de uma hora, que TTL nenhum
-- alcança; e para esses a gravação subiria de +25% para +100% da entrada. O TTL longo cobra
-- mais caro justamente nos casos que não têm salvação.
--
-- LIÇÃO: com prefixo de ~69k tokens, o caro é a GRAVAÇÃO, não a expiração. Baratear o miss
-- passa por encolher o prefixo (Fases 1, 2, 4 e 5), não por esticar o cache.
--
-- A view volta a usar 0,50/M de adicional de gravação. Ver o arquivo da migration
-- 20260808160000 para a derivação dos demais preços a partir do CSV real do OpenRouter.

create or replace view public.v_ai_custo_diario
with (security_invoker = on) as
with precos as (
  select
    2.00::numeric  as usd_entrada_por_milhao,
    10.00::numeric as usd_saida_por_milhao,
    0.20::numeric  as usd_leitura_cache_por_milhao,
    0.50::numeric  as usd_adicional_gravacao_por_milhao   -- TTL de 5 min: +25% da entrada
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
    greatest(0, coalesce(m.tokens_in, 0) - coalesce(m.cache_read_tokens, 0)) as tokens_preco_cheio,
    m.usd_real
  from public.ai_operator_messages m
  where m.model is not null
),
com_custo as (
  select b.*,
    ( b.tokens_preco_cheio * p.usd_entrada_por_milhao
    + b.cache_lido         * p.usd_leitura_cache_por_milhao
    + b.cache_gravado      * p.usd_adicional_gravacao_por_milhao
    + b.tokens_out         * p.usd_saida_por_milhao ) / 1e6 as usd_estimado
  from base b cross join precos p
)
select
  c.dia, c.canal, c.modelo,
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
  'Custo do agente por dia/canal/modelo. Precos reais do OpenRouter (Amazon Bedrock, sem markup): Sonnet 5 a USD 2/M entrada e 10/M saida, PROMOCIONAL ate 31/08/2026 (depois 3/15). Leitura de cache 0,20/M; gravacao +0,50/M (TTL 5min), ADICIONAL ao preco cheio.';

revoke all on public.v_ai_custo_diario from anon;
grant select on public.v_ai_custo_diario to authenticated, service_role;
