-- Fase 0 da otimização de tokens: tornar o custo de IA visível.
--
-- Motivação: `ai_operator_messages` já guardava tokens_in / tokens_out / cache_read_tokens,
-- mas ninguém traduzia isso em dinheiro, e faltava a peça que mais importa para decidir sobre
-- cache: quantos tokens foram GRAVADOS no cache. Gravação custa 1,25x a entrada base no TTL de
-- 5 minutos e 2x no de 1 hora; leitura custa 0,1x. Sem separar as três, qualquer conta de
-- economia é chute.
--
-- Medição que originou isto (07/08/2026): 24 chamadas ao modelo no dia, 6 delas sem cache
-- nenhum, cada miss ~6,5x mais cara que uma leitura. Prefixo fixo de ~69k tokens por chamada.

-- ---------------------------------------------------------------------------
-- 1. A coluna que faltava
-- ---------------------------------------------------------------------------
-- O valor já vinha do OpenRouter (prompt_tokens_details.cache_write_tokens) e era lido em
-- _shared/ai/anthropic.ts, mas nunca chegava ao banco.
alter table public.ai_operator_messages
  add column if not exists cache_creation_tokens integer;

comment on column public.ai_operator_messages.cache_creation_tokens is
  'Tokens gravados no cache de prompt nesta chamada. Custa 1,25x a entrada base (TTL 5min) ou 2x (TTL 1h). Nulo em linhas anteriores a 08/08/2026.';

-- ---------------------------------------------------------------------------
-- 2. Custo diário por canal
-- ---------------------------------------------------------------------------
create or replace view public.v_ai_custo_diario
with (security_invoker = on) as
with precos as (
  -- Preços de tabela do Sonnet 5 em USD por milhão de tokens.
  -- AJUSTAR quando o valor real do painel do OpenRouter for conhecido: o OpenRouter pode
  -- aplicar markup, e a Anthropic tem preço promocional de entrada até 31/08/2026 ($2/$10).
  -- Deliberadamente conservador: usa a tabela cheia, então a view nunca subestima o gasto.
  select
    3.00::numeric  as usd_entrada_por_milhao,
    15.00::numeric as usd_saida_por_milhao,
    0.30::numeric  as usd_leitura_cache_por_milhao,   -- 0,1x da entrada
    6.00::numeric  as usd_gravacao_cache_por_milhao   -- 2,0x da entrada (TTL de 1h, ativo desde 08/08/2026)
),
base as (
  select
    date_trunc('day', m.created_at)::date              as dia,
    coalesce(m.source, 'web')                          as canal,
    m.model                                            as modelo,
    coalesce(m.tokens_in, 0)                           as tokens_in,
    coalesce(m.tokens_out, 0)                          as tokens_out,
    coalesce(m.cache_read_tokens, 0)                   as cache_lido,
    coalesce(m.cache_creation_tokens, 0)               as cache_gravado,
    -- tokens_in do OpenRouter INCLUI o que veio do cache, então o que se paga a preço cheio é o
    -- resto. greatest() protege contra a hipótese de a gravação ser contabilizada à parte —
    -- a checar assim que as primeiras linhas com cache_creation_tokens chegarem.
    greatest(
      0,
      coalesce(m.tokens_in, 0) - coalesce(m.cache_read_tokens, 0) - coalesce(m.cache_creation_tokens, 0)
    )                                                  as tokens_preco_cheio
  from public.ai_operator_messages m
  where m.model is not null      -- só linhas de chamada real ao modelo
)
select
  b.dia,
  b.canal,
  b.modelo,
  count(*)                                                     as chamadas,
  count(*) filter (where b.cache_lido = 0)                     as chamadas_sem_cache,
  round(
    100.0 * count(*) filter (where b.cache_lido > 0) / nullif(count(*), 0)
  , 1)                                                         as pct_com_cache,
  sum(b.tokens_in)                                             as tokens_entrada,
  sum(b.cache_lido)                                            as tokens_lidos_do_cache,
  sum(b.cache_gravado)                                         as tokens_gravados_no_cache,
  sum(b.tokens_preco_cheio)                                    as tokens_preco_cheio,
  sum(b.tokens_out)                                            as tokens_saida,
  round(sum(b.tokens_preco_cheio) * p.usd_entrada_por_milhao       / 1e6, 4) as usd_entrada,
  round(sum(b.cache_lido)         * p.usd_leitura_cache_por_milhao / 1e6, 4) as usd_leitura_cache,
  round(sum(b.cache_gravado)      * p.usd_gravacao_cache_por_milhao/ 1e6, 4) as usd_gravacao_cache,
  round(sum(b.tokens_out)         * p.usd_saida_por_milhao         / 1e6, 4) as usd_saida,
  round(
    (
      sum(b.tokens_preco_cheio) * p.usd_entrada_por_milhao
      + sum(b.cache_lido)       * p.usd_leitura_cache_por_milhao
      + sum(b.cache_gravado)    * p.usd_gravacao_cache_por_milhao
      + sum(b.tokens_out)       * p.usd_saida_por_milhao
    ) / 1e6
  , 4)                                                         as usd_total,
  round(
    (
      sum(b.tokens_preco_cheio) * p.usd_entrada_por_milhao
      + sum(b.cache_lido)       * p.usd_leitura_cache_por_milhao
      + sum(b.cache_gravado)    * p.usd_gravacao_cache_por_milhao
      + sum(b.tokens_out)       * p.usd_saida_por_milhao
    ) / 1e6 / nullif(count(*), 0)
  , 5)                                                         as usd_por_chamada
from base b
cross join precos p
group by b.dia, b.canal, b.modelo,
         p.usd_entrada_por_milhao, p.usd_saida_por_milhao,
         p.usd_leitura_cache_por_milhao, p.usd_gravacao_cache_por_milhao
order by b.dia desc, b.canal;

comment on view public.v_ai_custo_diario is
  'Custo do agente de IA por dia/canal/modelo, decomposto em entrada, leitura de cache, gravação de cache e saída. Preços em USD/milhão definidos na CTE `precos` — ajustar ao valor real do painel do OpenRouter.';

-- View nova nasce acessível a `anon` por privilégio padrão; fechar na MESMA migration.
revoke all on public.v_ai_custo_diario from anon;
grant select on public.v_ai_custo_diario to authenticated, service_role;
