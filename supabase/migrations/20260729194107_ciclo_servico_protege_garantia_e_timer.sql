-- Dois efeitos colaterais encontrados na análise de impacto do Roteiro de Execução.
--
-- (1) GARANTIA REINICIANDO SOZINHA
-- calc_warranty_expiry() roda BEFORE INSERT OR UPDATE em service_order_services e
-- service_order_parts e reescrevia warranty_expires_at como CURRENT_DATE + N meses
-- a CADA update da linha — inclusive updates sem relação com garantia. O bug já
-- existia (editar quantidade reiniciava a garantia), mas o rollup do roteiro
-- dispara update a cada passo concluído, o que o transformaria de raro em
-- rotineiro: um serviço fechado em janeiro com 12 meses passaria a vencer 12
-- meses depois do último passo mexido.
-- Correção: só calcula quando a linha nasce ou quando warranty_months muda.
--
-- (2) ROLLUP APAGANDO O CRONÔMETRO DE LINHA
-- ServiceTimer.tsx já cronometrava started_at/finished_at/elapsed_minutes direto
-- na linha de serviço. O rollup do roteiro escreve nos MESMOS campos: uma linha
-- com 120 min cronometrados e um roteiro sem tempo apontado voltaria para zero.
-- Correção: o roteiro só assume a linha quando ele próprio tem tempo real
-- apontado. Sem isso, não encosta — quem mandava continua mandando. Também evita
-- UPDATE redundante, que dispararia triggers alheios à toa.
--
-- Validado em Postgres 17 efêmero, 5 cenários (ver plano, seção de impacto).

create or replace function public.calc_warranty_expiry()
returns trigger
language plpgsql
set search_path to 'public'
as $fn$
begin
  if new.warranty_months is null or new.warranty_months <= 0 then
    return new;
  end if;

  if tg_op = 'INSERT'
     or new.warranty_months is distinct from old.warranty_months
     or new.warranty_expires_at is null then
    new.warranty_expires_at := current_date + (new.warranty_months || ' months')::interval;
  end if;

  return new;
end;
$fn$;

create or replace function public.rollup_step_time_to_service_line()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_line uuid := coalesce(new.service_order_service_id, old.service_order_service_id);
  v_total integer;
  v_first timestamptz;
  v_last timestamptz;
  v_pendentes integer;
begin
  if v_line is null then
    return coalesce(new, old);
  end if;

  select coalesce(sum(coalesce(actual_minutes, 0)), 0)::integer,
         min(started_at),
         max(completed_at),
         count(*) filter (where status not in ('done','not_applicable'))
    into v_total, v_first, v_last, v_pendentes
  from public.service_order_steps
  where service_order_service_id = v_line;

  if v_total <= 0 then
    return coalesce(new, old);
  end if;

  update public.service_order_services sos
  set elapsed_minutes = v_total,
      started_at = coalesce(sos.started_at, v_first),
      finished_at = case when v_pendentes = 0 then v_last else sos.finished_at end
  where sos.id = v_line
    and (sos.elapsed_minutes is distinct from v_total
      or sos.started_at is distinct from coalesce(sos.started_at, v_first)
      or (v_pendentes = 0 and sos.finished_at is distinct from v_last));

  return coalesce(new, old);
end;
$fn$;

revoke all on function public.rollup_step_time_to_service_line() from public, anon, authenticated;
