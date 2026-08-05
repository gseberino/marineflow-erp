-- ─────────────────────────────────────────────────────────────────────────────
-- Despesa e hora da OS com recálculo garantido — para o agente ter as mesmas
-- capacidades da tela.
--
-- MOTIVO: a tela de edição de OS lança despesa e aponta hora; o agente não sabia
-- fazer nenhum dos dois. Mas não bastava criar uma tool que insere na tabela: as
-- duas operações mexem no VALOR da OS, e o recálculo é encadeado.
--
-- A armadilha concreta: `recalc_so_totals` recalcula mão de obra, peças, taxa de
-- cartão e total — mas LÊ `operational_cost_total` da própria OS em vez de somá-lo
-- das despesas. Uma tool que só inserisse a despesa e chamasse recalc deixaria o
-- total ERRADO, e o erro apareceria no valor cobrado do cliente. Por isso a soma
-- do custo operacional é feita aqui, ANTES do recálculo.
--
-- Só despesa FATURÁVEL entra no custo repassado (`billable_to_client`); a interna
-- fica registrada para margem e reembolso, sem inflar a conta do cliente — mesma
-- regra do hook use-service-order-expenses.ts.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.so_expense_add(
  p_so_id        uuid,
  p_category     text,
  p_description  text,
  p_amount       numeric,
  p_expense_date date    default null,
  p_paid_by      text    default 'company',
  p_billable     boolean default true,
  p_supplier_id  uuid    default null,
  p_notes        text    default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
  v_total numeric;
begin
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'Valor da despesa deve ser maior que zero.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from service_orders where id = p_so_id) then
    raise exception 'Ordem de serviço não encontrada.' using errcode = 'no_data_found';
  end if;

  insert into service_order_expenses (
    service_order_id, category, description, amount, expense_date,
    paid_by, billable_to_client, supplier_id, notes, created_by
  ) values (
    p_so_id, p_category, p_description, p_amount, coalesce(p_expense_date, current_date),
    coalesce(p_paid_by, 'company'), coalesce(p_billable, true), p_supplier_id, p_notes, auth.uid()
  ) returning id into v_id;

  perform public.so_recalc_operational_cost(p_so_id);
  select grand_total into v_total from service_orders where id = p_so_id;

  return jsonb_build_object('id', v_id, 'grand_total', v_total);
end;
$$;

create or replace function public.so_expense_remove(p_expense_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_so uuid;
  v_total numeric;
begin
  select service_order_id into v_so from service_order_expenses where id = p_expense_id;
  if v_so is null then
    raise exception 'Despesa não encontrada.' using errcode = 'no_data_found';
  end if;

  delete from service_order_expenses where id = p_expense_id;
  perform public.so_recalc_operational_cost(v_so);
  select grand_total into v_total from service_orders where id = v_so;

  return jsonb_build_object('service_order_id', v_so, 'grand_total', v_total);
end;
$$;

-- Soma as despesas faturáveis e SÓ ENTÃO recalcula o total. Separada porque as três
-- operações (incluir, remover, editar) precisam exatamente da mesma sequência.
create or replace function public.so_recalc_operational_cost(p_so_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_op numeric;
begin
  select coalesce(sum(amount), 0) into v_op
  from service_order_expenses
  where service_order_id = p_so_id and billable_to_client is distinct from false;

  update service_orders
     set operational_cost_total = round(v_op, 2)
   where id = p_so_id;

  perform public.recalc_so_totals(p_so_id);
end;
$$;

-- ── Apontamento de hora ──────────────────────────────────────────────────────
create or replace function public.so_time_entry_add(
  p_so_id      uuid,
  p_minutes    integer,
  p_technician uuid    default null,
  p_started_at timestamptz default null,
  p_billable   boolean default true,
  p_notes      text    default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
  v_tech uuid;
  v_inicio timestamptz;
begin
  if coalesce(p_minutes, 0) <= 0 then
    raise exception 'Duração deve ser maior que zero.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from service_orders where id = p_so_id) then
    raise exception 'Ordem de serviço não encontrada.' using errcode = 'no_data_found';
  end if;

  -- Sem técnico informado, é de quem está falando: o caso comum é o próprio
  -- técnico apontando a hora dele pelo WhatsApp.
  v_tech := coalesce(p_technician, auth.uid());
  if v_tech is null then
    raise exception 'Informe o técnico do apontamento.' using errcode = 'check_violation';
  end if;

  -- Sem início informado, assume que a hora acabou agora e conta para trás — é como
  -- se apontam horas na prática ("trabalhei 2h nisso"), não marcando o relógio antes.
  v_inicio := coalesce(p_started_at, now() - make_interval(mins => p_minutes));

  insert into time_entries (
    service_order_id, technician_user_id, started_at, ended_at,
    duration_minutes, billable, notes
  ) values (
    p_so_id, v_tech, v_inicio, v_inicio + make_interval(mins => p_minutes),
    p_minutes, coalesce(p_billable, true), p_notes
  ) returning id into v_id;

  perform public.recalc_so_totals(p_so_id);
  return jsonb_build_object('id', v_id, 'minutos', p_minutes);
end;
$$;

comment on function public.so_expense_add(uuid,text,text,numeric,date,text,boolean,uuid,text) is
  'Lanca despesa na OS e recalcula o total. Existe porque recalc_so_totals LE operational_cost_total em vez de soma-lo das despesas — inserir sem recalcular deixaria o valor cobrado do cliente errado.';
comment on function public.so_time_entry_add(uuid,integer,uuid,timestamptz,boolean,text) is
  'Aponta hora na OS e recalcula o total. Sem started_at, conta para tras a partir de agora — e como se aponta hora na pratica.';

revoke all on function public.so_expense_add(uuid,text,text,numeric,date,text,boolean,uuid,text) from public, anon;
revoke all on function public.so_expense_remove(uuid) from public, anon;
revoke all on function public.so_recalc_operational_cost(uuid) from public, anon;
revoke all on function public.so_time_entry_add(uuid,integer,uuid,timestamptz,boolean,text) from public, anon;
grant execute on function public.so_expense_add(uuid,text,text,numeric,date,text,boolean,uuid,text) to authenticated, service_role;
grant execute on function public.so_expense_remove(uuid) to authenticated, service_role;
grant execute on function public.so_recalc_operational_cost(uuid) to authenticated, service_role;
grant execute on function public.so_time_entry_add(uuid,integer,uuid,timestamptz,boolean,text) to authenticated, service_role;
