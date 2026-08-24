-- Fase 5 da Jornada: o que a mão de obra de uma OS CUSTOU, e não o que se estimou que custaria.
--
-- O PROBLEMA QUE ISTO RESOLVE: `get_os_profitability` calcula margem com o custo de mão de obra
-- PREVISTO (hora × valor de referência). O que a empresa desembolsou de verdade só aparece depois,
-- na folha — e as duas contas nunca se encontravam. Uma diária de R$ 160 num serviço orçado com 4h
-- de mão de obra a R$ 90 é uma diferença que a margem não mostrava.
--
-- POR QUE PELO TURNO, E NÃO POR `time_entries`: `time_entries.technician_user_id` é NOT NULL, e as
-- duas pessoas que hoje têm perfil de pagamento são `payees` SEM login — não cabem naquela tabela.
-- Além disso `time_entries` tem 0 linhas desde que existe, porque depende de `log_service_order_hours`,
-- que nunca foi chamada uma única vez. Construir a Fase 5 sobre ela seria construir uma view que
-- retorna vazio para sempre.
--
-- O turno, sim, existe e é o que a pessoa realmente informa ("hoje fiz diária no barco do Rodrigo").
-- E casa com como o trabalho acontece aqui: diarista passa o dia numa OS, não 40 minutos.
--
-- LIMITE ASSUMIDO: um turno aponta para UMA OS. Dia dividido entre dois barcos fica no primeiro
-- que a pessoa citar. Rateio proporcional exige `time_entries` com dado dentro — quando houver,
-- entra por cima desta view sem quebrá-la. Preferi um número honesto e grosso a um rateio
-- inventado, que erraria a margem sem ninguém saber.

alter table public.work_shifts
  add column if not exists service_order_id uuid references public.service_orders(id) on delete set null;

comment on column public.work_shifts.service_order_id is
  'OS em que o dia foi trabalhado, quando o dia inteiro foi de uma so. Opcional: dia de oficina, deslocamento e administrativo nao tem OS -- e e justamente por eles nao caberem em time_entries (service_order_id NOT NULL) que work_shifts existe.';

create index if not exists work_shifts_service_order_idx
  on public.work_shifts (service_order_id) where service_order_id is not null;

-- ── O custo que de fato saiu do caixa, por OS ───────────────────────────────────────────────────
-- Lê o `detalhamento` das linhas de folha JÁ FECHADAS: é lá que está o valor de cada dia, do jeito
-- que foi apurado e pago. Não recalcula nada — recalcular aqui abriria a porta para a view divergir
-- do que a pessoa recebeu.
drop view if exists public.v_custo_real_mao_de_obra_por_os;

create view public.v_custo_real_mao_de_obra_por_os
with (security_invoker = on) as
with dias as (
  select
    pl.id                                   as payroll_line_id,
    pl.payroll_period_id,
    pl.work_profile_id,
    (d->>'turno_id')::uuid                  as turno_id,
    (d->>'data')::date                      as data,
    d->>'tipo'                              as tipo,
    coalesce((d->>'valor')::numeric, 0)     as valor_do_dia
  from public.payroll_lines pl
  cross join lateral jsonb_array_elements(coalesce(pl.detalhamento, '[]'::jsonb)) as d
  where d->>'turno_id' is not null
),
com_os as (
  select
    dias.*,
    ws.service_order_id,
    ws.duracao_minutos,
    coalesce(py.name, au.full_name, 'equipe') as quem
  from dias
  join public.work_shifts ws on ws.id = dias.turno_id
  join public.work_profiles wp on wp.id = dias.work_profile_id
  left join public.payees    py on py.id = wp.payee_id
  left join public.app_users au on au.id = wp.app_user_id
  where ws.service_order_id is not null
)
select
  c.service_order_id,
  so.service_order_number,
  so.client_id,
  count(*)                                              as dias_trabalhados,
  count(distinct c.work_profile_id)                     as pessoas,
  round(sum(coalesce(c.duracao_minutos, 0)) / 60.0, 2)  as horas_apontadas,
  round(sum(c.valor_do_dia), 2)                         as custo_real_mao_de_obra,
  min(c.data)                                           as primeiro_dia,
  max(c.data)                                           as ultimo_dia,
  string_agg(distinct c.quem, ', ' order by c.quem)     as quem_trabalhou
from com_os c
join public.service_orders so on so.id = c.service_order_id
group by c.service_order_id, so.service_order_number, so.client_id;

comment on view public.v_custo_real_mao_de_obra_por_os is
  'Custo de mao de obra EFETIVAMENTE PAGO por OS, lido do detalhamento das linhas de folha ja fechadas -- nao do valor de referencia de hora. Cobre apenas turnos com service_order_id preenchido: dia de oficina e deslocamento nao entram, e um turno divide-se por uma OS so. Comparar com o previsto de get_os_profitability e o que revela orcamento de mao de obra fora da realidade.';

revoke all on public.v_custo_real_mao_de_obra_por_os from anon;
grant select on public.v_custo_real_mao_de_obra_por_os to authenticated, service_role;
