-- Custo REAL do OpenRouter, em vez de estimativa por tabela de preço.
--
-- A view v_ai_custo_diario (migration anterior) calcula custo multiplicando tokens por preços
-- fixos numa CTE. Isso ignora markup do OpenRouter, promoção vigente e o desconto de cache que
-- ele aplica. O OpenRouter expõe `GET /api/v1/generation?id=` com o valor efetivamente cobrado
-- (total_cost) e o desconto de cache (cache_discount) — basta guardar o id da geração, que já
-- vinha na resposta e era descartado em _shared/ai/anthropic.ts.
--
-- Fluxo: ai-agent grava openrouter_generation_id -> ai-cost-reconcile (cron horário) consulta a
-- API e preenche usd_real -> a view prefere usd_real e só cai na estimativa quando ele falta.

-- ---------------------------------------------------------------------------
-- 1. Colunas de reconciliação
-- ---------------------------------------------------------------------------
alter table public.ai_operator_messages
  add column if not exists openrouter_generation_id text,
  add column if not exists usd_real                 numeric(12, 8),
  add column if not exists usd_cache_discount       numeric(12, 8),
  add column if not exists custo_reconciliado_em    timestamptz,
  add column if not exists reconcile_tentativas     smallint not null default 0;

comment on column public.ai_operator_messages.openrouter_generation_id is
  'id da geração no OpenRouter; chave para consultar o custo real em /api/v1/generation.';
comment on column public.ai_operator_messages.usd_real is
  'Custo efetivamente cobrado pelo OpenRouter nesta chamada (total_cost). Nulo enquanto não reconciliado.';
comment on column public.ai_operator_messages.usd_cache_discount is
  'Quanto o cache de prompt economizou nesta chamada, segundo o OpenRouter (cache_discount).';
comment on column public.ai_operator_messages.reconcile_tentativas is
  'Quantas vezes ai-cost-reconcile tentou esta linha. O OpenRouter não guarda geração para sempre; após 5 tentativas a linha é abandonada para não virar fila eterna.';

-- Índice para a varredura do cron: só linhas pendentes de reconciliação.
create index if not exists idx_ai_msgs_reconcile_pendente
  on public.ai_operator_messages (created_at desc)
  where openrouter_generation_id is not null
    and custo_reconciliado_em is null
    and reconcile_tentativas < 5;

-- ---------------------------------------------------------------------------
-- 2. View: prefere o custo real, cai na estimativa quando ele falta
-- ---------------------------------------------------------------------------
-- `create or replace view` não aceita inserir coluna no meio da lista (42P16); como a versão
-- anterior é de horas atrás e ninguém depende dela ainda, recriar é mais limpo que ALTER.
drop view if exists public.v_ai_custo_diario;

create view public.v_ai_custo_diario
with (security_invoker = on) as
with precos as (
  -- Fallback apenas. Vale enquanto a linha não foi reconciliada com o OpenRouter.
  select
    3.00::numeric  as usd_entrada_por_milhao,
    15.00::numeric as usd_saida_por_milhao,
    0.30::numeric  as usd_leitura_cache_por_milhao,
    6.00::numeric  as usd_gravacao_cache_por_milhao
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
    greatest(
      0,
      coalesce(m.tokens_in, 0) - coalesce(m.cache_read_tokens, 0) - coalesce(m.cache_creation_tokens, 0)
    )                                      as tokens_preco_cheio,
    m.usd_real,
    coalesce(m.usd_cache_discount, 0)      as usd_cache_discount
  from public.ai_operator_messages m
  where m.model is not null
),
com_custo as (
  select
    b.*,
    -- Estimativa por tabela — o que a view fazia antes.
    (
      b.tokens_preco_cheio * p.usd_entrada_por_milhao
      + b.cache_lido       * p.usd_leitura_cache_por_milhao
      + b.cache_gravado    * p.usd_gravacao_cache_por_milhao
      + b.tokens_out       * p.usd_saida_por_milhao
    ) / 1e6                                as usd_estimado
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
  -- Quanto do dia já foi confirmado contra a fatura do OpenRouter.
  count(*) filter (where c.usd_real is not null)          as chamadas_reconciliadas,
  round(100.0 * count(*) filter (where c.usd_real is not null) / nullif(count(*), 0), 1) as pct_reconciliado,
  sum(c.tokens_in)                                        as tokens_entrada,
  sum(c.cache_lido)                                       as tokens_lidos_do_cache,
  sum(c.cache_gravado)                                    as tokens_gravados_no_cache,
  sum(c.tokens_preco_cheio)                               as tokens_preco_cheio,
  sum(c.tokens_out)                                       as tokens_saida,
  round(sum(c.usd_estimado), 4)                           as usd_estimado,
  round(sum(c.usd_real), 4)                               as usd_real_parcial,
  round(sum(c.usd_cache_discount), 4)                     as usd_economizado_pelo_cache,
  -- O número para olhar: real onde existe, estimativa no resto.
  round(sum(coalesce(c.usd_real, c.usd_estimado)), 4)     as usd_total,
  round(sum(coalesce(c.usd_real, c.usd_estimado)) / nullif(count(*), 0), 5) as usd_por_chamada
from com_custo c
group by c.dia, c.canal, c.modelo
order by c.dia desc, c.canal;

comment on view public.v_ai_custo_diario is
  'Custo do agente de IA por dia/canal/modelo. usd_total usa o valor real do OpenRouter onde ja reconciliado (ver pct_reconciliado) e cai na estimativa por tabela no restante.';

revoke all on public.v_ai_custo_diario from anon;
grant select on public.v_ai_custo_diario to authenticated, service_role;
