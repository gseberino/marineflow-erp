-- ═══════════════════════════════════════════════════════════════════════════
-- As duas pontas que faziam a execução se perder
-- Plano: plans/marineflow-execucao-os-roteiro.md, Fases 2 e 3
--
-- A revisão do plano (03/08) encontrou o mesmo defeito em dois lugares: a
-- tabela existe, a consulta existe, e nada escreve nela.
--
--   · `time_entries` — o tempo do passo ficava em service_order_steps e subia
--     para a linha de serviço, mas nunca chegava aqui. É desta tabela que os
--     relatórios de hora leem (use-reports.ts), e a coluna `step_id` foi criada
--     para este fim e nunca tinha sido usada.
--
--   · `service_cases` — a Fase 3 é chamada no plano de "pré-requisito de tudo
--     que vem depois", e `estimate_from_cases()` está pronta há dias esperando
--     dado. Nenhuma rotina criava caso ao concluir OS.
--
-- Sem isto, um dia inteiro de serviço real produziria metade do dado: os passos
-- marcados, e nenhuma base para tempo padrão nem para estimativa por analogia.
-- Por isso vem antes da primeira execução, não depois.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. Passo concluído vira apontamento de hora ────────────────────────────
create or replace function public.log_step_time_entry()
returns trigger
language plpgsql security definer set search_path = public
as $fn$
declare v_tecnico uuid;
begin
  -- Só quando o passo FICA pronto com tempo apontado. Reabrir e concluir de
  -- novo atualiza o registro existente em vez de criar outro.
  if new.status <> 'done' or coalesce(new.actual_minutes, 0) <= 0 then
    return new;
  end if;
  if old.status = 'done' and coalesce(old.actual_minutes, 0) = coalesce(new.actual_minutes, 0) then
    return new;
  end if;

  -- technician_user_id é NOT NULL: quem executou o passo, senão o técnico da
  -- OS, senão quem está marcando. Sem nenhum dos três, é melhor não gravar do
  -- que gravar hora no nome de alguém que não trabalhou.
  v_tecnico := coalesce(
    new.assigned_user_id,
    (select sot.user_id from public.service_order_technicians sot
      where sot.service_order_id = new.service_order_id
      order by sot.created_at limit 1),
    auth.uid());

  if v_tecnico is null then
    return new;
  end if;

  if exists (select 1 from public.time_entries where step_id = new.id) then
    update public.time_entries set
      duration_minutes = new.actual_minutes,
      started_at = coalesce(new.started_at, started_at),
      ended_at = coalesce(new.completed_at, now()),
      updated_at = now()
    where step_id = new.id;
  else
    insert into public.time_entries (
      service_order_id, technician_user_id, started_at, ended_at,
      duration_minutes, billable, step_id, notes)
    values (
      new.service_order_id, v_tecnico,
      coalesce(new.started_at, new.completed_at, now()),
      coalesce(new.completed_at, now()),
      new.actual_minutes, true, new.id,
      'Passo do roteiro: ' || new.title);
  end if;

  return new;
end;
$fn$;

revoke all on function public.log_step_time_entry() from public, anon, authenticated;

drop trigger if exists trg_log_step_time_entry on public.service_order_steps;
create trigger trg_log_step_time_entry
  after update on public.service_order_steps
  for each row execute function public.log_step_time_entry();

-- ─── 2. OS concluída vira caso, um por linha de serviço ─────────────────────
-- `estimate_from_cases(service_id)` busca por serviço, então o caso é por
-- LINHA, não por OS: uma OS com cinco serviços produz cinco casos.
--
-- `usable` é o campo mais importante aqui. Caso sem tempo real não serve para
-- estimar coisa alguma, e entrar na base como se servisse é pior que não
-- entrar — a média mentiria com cara de dado.
create or replace function public.create_service_cases_on_complete()
returns trigger
language plpgsql security definer set search_path = public
as $fn$
declare v_criados integer;
begin
  if new.status not in ('completed','invoiced') then return new; end if;
  if old.status in ('completed','invoiced') then return new; end if;

  insert into public.service_cases (
    service_order_id, service_id, vessel_id, client_id, marina_id, asset_type,
    features, planned_minutes, actual_minutes, materials_cost, parts_used,
    variance_pct, outcome, usable, unusable_reason)
  select
    new.id,
    sos.service_id,
    new.vessel_id,
    new.client_id,
    new.marina_id,
    v.asset_type,
    -- O que descreve a execução para a busca por semelhança depois.
    jsonb_build_object(
      'servico',  sos.name_snapshot,
      'sistema',  coalesce(sos.service_system, s.service_system),
      'verbo',    s.service_verb,
      'passos',   (select count(*) from public.service_order_steps st
                    where st.service_order_service_id = sos.id),
      'travas',   (select count(*) from public.service_order_steps st
                    where st.service_order_service_id = sos.id and st.blocked_reason_code is not null),
      'nao_se_aplica', (select count(*) from public.service_order_steps st
                    where st.service_order_service_id = sos.id and st.status = 'not_applicable')),
    nullif((select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
             where st.service_order_service_id = sos.id), 0),
    nullif(coalesce(sos.elapsed_minutes, 0), 0),
    (select coalesce(sum(p.line_total_cost), 0) from public.service_order_parts p
      where p.service_order_service_id = sos.id),
    (select coalesce(jsonb_agg(jsonb_build_object(
              'produto', pr.name, 'qtd', p.quantity)), '[]'::jsonb)
       from public.service_order_parts p
       join public.products pr on pr.id = p.product_id
      where p.service_order_service_id = sos.id),
    case when coalesce(sos.elapsed_minutes,0) > 0
          and (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                where st.service_order_service_id = sos.id) > 0
         then round(100.0 * (sos.elapsed_minutes -
              (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                where st.service_order_service_id = sos.id))
              / (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                  where st.service_order_service_id = sos.id), 1)
         else null end,
    -- Faixa de tolerância: convenção de negócio, ajustável. Fora de ±10% do
    -- previsto, o caso é sinal de que a estimativa precisa mudar.
    case when coalesce(sos.elapsed_minutes,0) = 0 then null
         when (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                where st.service_order_service_id = sos.id) = 0 then null
         when sos.elapsed_minutes >
              1.1 * (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                      where st.service_order_service_id = sos.id) then 'estourou'
         when sos.elapsed_minutes <
              0.9 * (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                      where st.service_order_service_id = sos.id) then 'sobrou'
         else 'dentro' end,
    -- Sem tempo real não há o que aprender com este caso.
    coalesce(sos.elapsed_minutes, 0) > 0,
    case when coalesce(sos.elapsed_minutes, 0) > 0 then null
         else 'Concluída sem hora apontada — não serve para estimar tempo.' end
  from public.service_order_services sos
  join public.services s on s.id = sos.service_id
  left join public.vessels v on v.id = new.vessel_id
  where sos.service_order_id = new.id
    and sos.service_id is not null
    -- Reabrir e concluir de novo não duplica o caso.
    and not exists (select 1 from public.service_cases c
                    where c.service_order_id = new.id and c.service_id = sos.service_id);

  get diagnostics v_criados = row_count;
  if v_criados > 0 then
    raise notice 'OS %: % caso(s) registrado(s).', new.service_order_number, v_criados;
  end if;

  return new;
end;
$fn$;

revoke all on function public.create_service_cases_on_complete() from public, anon, authenticated;

drop trigger if exists trg_create_service_cases on public.service_orders;
create trigger trg_create_service_cases
  after update on public.service_orders
  for each row execute function public.create_service_cases_on_complete();
