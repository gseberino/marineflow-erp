-- O preço do modelo muda em 01/09/2026 — e a view passa a saber disso sozinha.
--
-- O Sonnet 5 está em preço promocional (USD 2/M entrada, 10/M saída) até 31/08/2026. A partir de
-- 01/09 volta à tabela cheia: USD 3/M e 15/M, um aumento de 50% que chega sem ninguém mexer em
-- nada.
--
-- A versão anterior da view tinha os preços fixos numa CTE, o que criava uma dívida com data
-- marcada: alguém teria que lembrar de trocar dois números em 01/09. Dívida datada é dívida
-- esquecida — o custo passaria a ser subestimado em 50% e ninguém notaria, porque o número
-- continuaria parecendo plausível.
--
-- Agora o preço é função do DIA da chamada. Um relatório de agosto continua correto depois de
-- setembro, e um de setembro já nasce certo. Nada a lembrar.
--
-- Preços derivados do CSV real de atividade do OpenRouter (provedor Amazon Bedrock, sem markup) —
-- ver 20260808160000. Gravação de cache é ADICIONAL ao preço cheio (+25% no TTL de 5 min, que é o
-- que está em uso desde a reversão do TTL de 1h).

drop view if exists public.v_ai_custo_diario;

create view public.v_ai_custo_diario
with (security_invoker = on) as
with base as (
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
com_preco as (
  select
    b.*,
    -- Haiku tem tabela própria e não entra na promoção do Sonnet.
    case when b.modelo like '%haiku%' then 1.00
         when b.dia <= date '2026-08-31' then 2.00
         else 3.00 end as usd_entrada_por_milhao,
    case when b.modelo like '%haiku%' then 5.00
         when b.dia <= date '2026-08-31' then 10.00
         else 15.00 end as usd_saida_por_milhao
  from base b
),
com_custo as (
  select
    c.*,
    ( c.tokens_preco_cheio * c.usd_entrada_por_milhao
    + c.cache_lido         * c.usd_entrada_por_milhao * 0.10   -- leitura de cache: 0,1x a entrada
    + c.cache_gravado      * c.usd_entrada_por_milhao * 0.25   -- gravação: +25% (TTL de 5 min)
    + c.tokens_out         * c.usd_saida_por_milhao ) / 1e6 as usd_estimado
  from com_preco c
)
select
  c.dia, c.canal, c.modelo,
  count(*)                                                as chamadas,
  count(*) filter (where c.cache_lido = 0)                as chamadas_sem_cache,
  round(100.0 * count(*) filter (where c.cache_lido > 0) / nullif(count(*), 0), 1) as pct_com_cache,
  count(*) filter (where c.usd_real is not null)          as chamadas_reconciliadas,
  round(100.0 * count(*) filter (where c.usd_real is not null) / nullif(count(*), 0), 1) as pct_reconciliado,
  max(c.usd_entrada_por_milhao)                           as usd_entrada_vigente,
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
  'Custo do agente por dia/canal/modelo. O preco e funcao do DIA: Sonnet 5 a USD 2/10 por milhao ate 31/08/2026 e 3/15 a partir de 01/09 (fim do promocional); Haiku a 1/5 sempre. Leitura de cache 0,1x a entrada; gravacao +25% (TTL de 5 min), ADICIONAL ao preco cheio. usd_total prefere o valor real reconciliado do OpenRouter e so cai na estimativa onde ele falta.';

revoke all on public.v_ai_custo_diario from anon;
grant select on public.v_ai_custo_diario to authenticated, service_role;
