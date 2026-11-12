-- Serviços do prestador (Alex) na conta corrente — 12/11/2026.
--
-- POR QUE: o Alex (ex-sócio, hoje prestador com CNPJ MEI) não recebe diária: recebe por serviço — um valor
-- combinado em cada OS ou um percentual que varia de serviço a serviço (da mão de obra, do total ou do lucro da
-- OS). O sistema não tinha onde guardar isso; os Pix a ele (R$ 2.950 desde 23/10) caíam na fila como
-- "Distrato de ex-sócio" e nada dizia quanto se devia.
--
-- DECISÕES DO DONO (12/11/2026, madrugada):
--   1. A base do percentual varia: ele diz em cada serviço (o assistente pergunta quando faltar).
--   2. O valor só vira "a pagar" QUANDO O CLIENTE PAGA A OS. Antes disso o serviço aparece como "aguardando o
--      cliente pagar", com o valor previsto, fora do saldo.
--   3. Os Pix ao CNPJ dele desde 23/10 são pagamento de serviço: abatem a conta (categoria "Serviços de terceiros").
--
-- DESENHO (estender, não criar módulo novo — a mesma recomendação de 28/09 para comissões):
--   · o serviço é uma linha de `commissions` com payee_id (a coluna existe desde 31/07) e as colunas novas
--     modo/base/descricao/data_servico/cliente_pagou_em. A view de lucro por OS (v_os_profitability) já desconta
--     commissions.amount: o custo do Alex passa a sair do lucro da OS sem mexer nela.
--   · a conta corrente do freelancer (_conta_corrente_linhas) ganha o tipo 'servico': crédito na data em que o
--     cliente pagou a OS. Saldo, extrato, PDF, Pix pelo CNPJ abatendo e o assistente vêm junto.
--   · o percentual acompanha a OS enquanto o cliente não paga; quando a OS fica paga, um gatilho congela o valor
--     (e descongela se o pagamento for estornado).
--   · o recibo de diárias NÃO se aplica a prestador com CNPJ (o comprovante é a nota dele): o acerto recusa.
--
-- O QUE NÃO MUDA: diárias, o recibo dos diaristas, a comissão "maior dos dois" da agenda (comissao_tecnicos_do_mes
-- lê work_shifts, não commissions) e o gatilho antigo sync_commission_on_so_complete (só commissioned_user_id).
-- _abate_diarias passa a aceitar também "Serviços de terceiros" (medido: nenhum pagamento dos diaristas tem essa
-- categoria — o saldo deles não muda; ver o teste).
--
-- Funções redefinidas partem do corpo de produção conferido em 12/11 (igual ao repo):
--   _conta_corrente_linhas ← 20261028150000; conta_corrente_freelancer e resumo_freelancers ← 20261027120000;
--   _abate_diarias ← 20261027150000.
-- Nenhum dado é escrito aqui. Teste: supabase/tests/servicos_do_prestador.sql.

-- ── 1. O serviço como linha de commissions ─────────────────────────────────────────────────────────────
alter table public.commissions
  add column if not exists modo text,
  add column if not exists base text,
  add column if not exists descricao text,
  add column if not exists data_servico date,
  add column if not exists cliente_pagou_em date,
  add column if not exists criado_por uuid;

alter table public.commissions drop constraint if exists commissions_modo_check;
alter table public.commissions add constraint commissions_modo_check
  check (modo is null or modo in ('valor', 'percentual'));
alter table public.commissions drop constraint if exists commissions_base_check;
alter table public.commissions add constraint commissions_base_check
  check (base is null or base in ('mao_de_obra', 'total', 'lucro'));
alter table public.commissions drop constraint if exists commissions_servico_coerente;
alter table public.commissions add constraint commissions_servico_coerente
  check (modo is null
         or (payee_id is not null and service_order_id is not null and user_id is null
             and (modo = 'valor' and amount > 0
                  or modo = 'percentual' and percentage > 0 and percentage <= 100 and base is not null)));

comment on column public.commissions.modo is
  'Serviço do prestador (12/11/2026): valor = combinado em reais; percentual = percentage % da base. Nulo = comissão antiga (vendedor com login).';
comment on column public.commissions.base is
  'Base do percentual: mao_de_obra (serviços da OS, com o desconto proporcional), total (OS sem a taxa de cartão repassada) ou lucro (recebido − peças a custo − despesas − imposto − taxa).';
comment on column public.commissions.cliente_pagou_em is
  'Dia em que o cliente terminou de pagar a OS: o serviço entra na conta corrente do prestador nesse dia e o percentual fica congelado. Nulo = aguardando o cliente pagar.';

-- um serviço por pessoa por OS: registrar de novo CORRIGE (o "sim" em dobro não duplica)
create unique index if not exists commissions_um_servico_por_os
  on public.commissions (service_order_id, payee_id)
  where modo is not null and status is distinct from 'cancelled';

-- ── 2. A base e o valor ────────────────────────────────────────────────────────────────────────────────
create or replace function public._base_do_servico(p_os uuid, p_base text)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  t record;
  so record;
  v_pago boolean;
  v_recebido numeric;
  v_taxa numeric;
  v_material numeric;
  v_despesas numeric;
  v_imposto numeric := 0;
  v_aliq numeric;
  v_fonte text;
begin
  select * into t from public.calc_so_totals(p_os);
  if t.grand_total is null then return 0; end if;
  select s.discount_services_pct, s.payment_status into so from public.service_orders s where s.id = p_os;

  if p_base = 'mao_de_obra' then
    -- o desconto da OS: o de serviços quando a OS tem a divisão; senão, proporcional (discountRatio)
    if exists (select 1 from public.service_orders s where s.id = p_os
                and (coalesce(s.discount_services_pct, 0) > 0 or coalesce(s.discount_parts_pct, 0) > 0)) then
      return round(t.labor_cost_total * (1 - coalesce(so.discount_services_pct, 0) / 100), 2);
    end if;
    return round(case when t.subtotal > 0 then t.labor_cost_total * (t.subtotal - t.discount_amount) / t.subtotal
                      else t.labor_cost_total end, 2);
  elsif p_base = 'total' then
    return round(t.base, 2);
  elsif p_base = 'lucro' then
    -- a mesma conta da comissão da agenda (comissao_tecnicos_do_mes): recebido − material ao custo − despesas
    -- − imposto − taxa do cartão. Antes de o cliente pagar, o recebido é o total previsto.
    v_pago := so.payment_status = 'paid';
    select coalesce(sum(p.amount), 0),
           coalesce(sum(case when p.net_amount is not null then p.amount - p.net_amount
                             else p.amount * coalesce(p.card_fee_percent, 0) / 100 end), 0)
      into v_recebido, v_taxa
      from public.receivables r
      join public.payments p on p.receivable_id = r.id
     where r.service_order_id = p_os and r.status is distinct from 'cancelled' and p.status = 'confirmed';
    if not v_pago then
      v_recebido := t.grand_total;
      v_taxa := coalesce(t.card_fee_amount, 0);
    end if;
    select round(coalesce(sum(coalesce(sp.line_total_cost, sp.quantity * sp.unit_cost_snapshot)), 0), 2) into v_material
      from public.service_order_parts sp where sp.service_order_id = p_os;
    select round(coalesce(sum(e.amount), 0), 2) into v_despesas
      from public.service_order_expenses e where e.service_order_id = p_os;
    select c.imposto_fonte into v_fonte from public.comissao_config c where c.id;
    if coalesce(v_fonte, 'nenhum') <> 'nenhum' then
      v_aliq := coalesce(
        (select f.nfse_total_tax_rate_sn from public.company_fiscal_settings f order by f.created_at, f.id limit 1),
        (select replace(btrim(s.value), ',', '.')::numeric from public.app_settings s
          where s.key = 'simples_aliquota' and btrim(s.value) ~ '^[0-9]+([.,][0-9]+)?$'), 0);
      if v_fonte = 'aliquota_simples_sempre'
         or exists (select 1 from public.issued_fiscal_documents f
                     where f.origin_type = 'service_order' and f.origin_id = p_os
                       and f.status = 'authorized' and f.environment = 'producao') then
        v_imposto := round(v_recebido * v_aliq / 100, 2);
      end if;
    end if;
    return round(v_recebido - v_material - v_despesas - v_imposto - v_taxa, 2);
  end if;
  return 0;
end;
$$;

-- o valor do serviço: o combinado; o percentual congelado depois que o cliente pagou; senão, o de hoje
create or replace function public._valor_do_servico(p_modo text, p_valor numeric, p_pct numeric, p_base text,
                                                    p_os uuid, p_pagou date)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select case when p_modo = 'valor' or p_pagou is not null then p_valor
              else round(p_pct / 100 * greatest(public._base_do_servico(p_os, p_base), 0), 2) end;
$$;

create or replace function public._rotulo_do_servico(p_modo text, p_pct numeric, p_base text)
returns text
language sql
immutable
set search_path = public
as $$
  select case when p_modo = 'valor' then 'valor combinado'
              else replace(trim_scale(p_pct)::text, '.', ',') || '% ' ||
                   case p_base when 'mao_de_obra' then 'da mão de obra' when 'total' then 'do total da OS'
                               else 'do lucro da OS' end end;
$$;

-- o dia em que o cliente terminou de pagar a OS (nulo = ainda não pagou tudo)
create or replace function public._os_paga_em(p_os uuid)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select case when so.payment_status = 'paid' then
           coalesce((select max(p.payment_date)
                       from public.receivables r
                       join public.payments p on p.receivable_id = r.id
                      where r.service_order_id = so.id and r.status is distinct from 'cancelled'
                        and p.status = 'confirmed'),
                    public._hoje_brt())
         end
    from public.service_orders so where so.id = p_os;
$$;

-- congela/descongela os serviços de uma OS conforme o cliente pagou ou não
create or replace function public._atualizar_servicos_da_os(p_os uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pagou date := public._os_paga_em(p_os);
  c record;
  v_base numeric;
begin
  for c in
    select * from public.commissions
     where service_order_id = p_os and modo is not null and status is distinct from 'cancelled'
       and cliente_pagou_em is distinct from v_pagou
     for update
  loop
    if v_pagou is not null and c.modo = 'percentual' then
      v_base := public._base_do_servico(p_os, c.base);
      update public.commissions
         set cliente_pagou_em = v_pagou, base_value = v_base,
             amount = round(c.percentage / 100 * greatest(v_base, 0), 2),
             updated_at = now()
       where id = c.id;
    else
      update public.commissions set cliente_pagou_em = v_pagou, updated_at = now() where id = c.id;
    end if;
  end loop;
end;
$$;

create or replace function public._trg_servicos_quando_a_os_e_paga()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.payment_status is distinct from old.payment_status then
    perform public._atualizar_servicos_da_os(new.id);
  end if;
  return null;
end;
$$;

drop trigger if exists trg_servicos_quando_a_os_e_paga on public.service_orders;
create trigger trg_servicos_quando_a_os_e_paga
  after update of payment_status on public.service_orders
  for each row execute function public._trg_servicos_quando_a_os_e_paga();

-- ── 3. Registrar, apagar e listar ──────────────────────────────────────────────────────────────────────
create or replace function public.registrar_servico_prestador(
  p_favorecido_id uuid,
  p_os_id uuid,
  p_valor numeric default null,
  p_percentual numeric default null,
  p_base text default null,
  p_descricao text default null,
  p_data date default null,
  p_autor uuid default null,
  p_simular boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav public.payees%rowtype;
  v_os record;
  v_antes public.commissions%rowtype;
  v_modo text;
  v_base text;
  v_pagou date;
  v_base_valor numeric;
  v_valor numeric;
  v_desde date;
  v_id uuid;
  v_txt text[] := '{}';
  v_saldo jsonb;
begin
  select * into v_fav from public.payees where id = p_favorecido_id;
  if v_fav.id is null or not v_fav.active then
    raise exception 'Prestador não encontrado entre os favorecidos ativos.' using errcode = 'P0001';
  end if;
  if v_fav.kind not in ('prestador', 'comissionado', 'diarista') then
    raise exception '% não é prestador de serviço (cadastro: %).', v_fav.name, v_fav.kind using errcode = 'P0001';
  end if;

  select so.id, so.service_order_number as numero, so.status, so.payment_status, so.grand_total,
         cl.name as cliente, ve.name as barco
    into v_os
    from public.service_orders so
    left join public.clients cl on cl.id = so.client_id
    left join public.vessels ve on ve.id = so.vessel_id
   where so.id = p_os_id;
  if v_os.id is null then raise exception 'OS não encontrada.' using errcode = 'P0001'; end if;
  if v_os.status = 'cancelled' then
    raise exception 'A % está cancelada: serviço em OS cancelada não se paga.', v_os.numero using errcode = 'P0001';
  end if;

  if (p_valor is null) = (p_percentual is null) then
    raise exception 'Diga o valor combinado OU o percentual (com a base: mão de obra, total ou lucro).' using errcode = 'P0001';
  end if;
  if p_valor is not null then
    if p_valor <= 0 then raise exception 'O valor do serviço tem de ser maior que zero.' using errcode = 'P0001'; end if;
    v_modo := 'valor';
  else
    if p_percentual <= 0 or p_percentual > 100 then
      raise exception 'Percentual fora do razoável: % %%.', p_percentual using errcode = 'P0001';
    end if;
    v_base := case lower(btrim(coalesce(p_base, '')))
                when 'mao_de_obra' then 'mao_de_obra' when 'mão de obra' then 'mao_de_obra' when 'servicos' then 'mao_de_obra'
                when 'total' then 'total' when 'lucro' then 'lucro' end;
    if v_base is null then
      raise exception 'Percentual de quê? Diga a base: mão de obra, total da OS ou lucro da OS.' using errcode = 'P0001';
    end if;
    v_modo := 'percentual';
  end if;

  select * into v_antes from public.commissions
   where service_order_id = p_os_id and payee_id = p_favorecido_id and modo is not null
     and status is distinct from 'cancelled';

  v_pagou := public._os_paga_em(p_os_id);
  if v_modo = 'percentual' then
    v_base_valor := public._base_do_servico(p_os_id, v_base);
    v_valor := round(p_percentual / 100 * greatest(v_base_valor, 0), 2);
  else
    v_valor := round(p_valor, 2);
  end if;
  v_desde := coalesce(v_fav.conta_corrente_desde, coalesce(p_data, public._hoje_brt()));

  -- o texto da confirmação (o mesmo que volta depois de gravar)
  v_txt := v_txt || format('Serviço de %s na %s%s', v_fav.name, v_os.numero,
                           coalesce(' (' || nullif(concat_ws(' – ', v_os.cliente, v_os.barco), '') || ')', ''));
  if v_modo = 'valor' then
    v_txt := v_txt || format('Valor combinado: %s', public._brl(v_valor));
  else
    v_txt := v_txt || format('%s: %s × %s = %s%s',
                             initcap(public._rotulo_do_servico(v_modo, p_percentual, v_base)),
                             replace(trim_scale(p_percentual)::text, '.', ',') || '%', public._brl(v_base_valor),
                             public._brl(v_valor),
                             case when v_pagou is null then ' hoje (acompanha a OS até o cliente pagar)' else '' end);
    if v_valor <= 0 then
      v_txt := v_txt || 'Atenção: hoje a base dá zero ou negativa — o serviço fica sem valor até a OS mudar.'::text;
    end if;
  end if;
  if p_descricao is not null and btrim(p_descricao) <> '' then
    v_txt := v_txt || format('O que fez: %s', btrim(p_descricao));
  end if;
  if v_pagou is not null then
    v_txt := v_txt || format('O cliente já pagou a OS (%s): entra agora na conta de %s.',
                             to_char(v_pagou, 'DD/MM'), split_part(v_fav.name, ' ', 1));
  else
    v_txt := v_txt || format('Entra na conta de %s quando o cliente pagar a OS (hoje: %s).',
                             split_part(v_fav.name, ' ', 1),
                             case v_os.payment_status when 'partially_paid' then 'paga em parte' else 'não paga' end);
  end if;
  if v_antes.id is not null then
    v_txt := v_txt || format('Substitui o que estava registrado: %s (%s).',
                             public._brl(public._valor_do_servico(v_antes.modo, v_antes.amount, v_antes.percentage,
                                                                  v_antes.base, v_antes.service_order_id, v_antes.cliente_pagou_em)),
                             public._rotulo_do_servico(v_antes.modo, v_antes.percentage, v_antes.base));
  end if;
  if v_fav.conta_corrente_desde is null then
    v_txt := v_txt || format('A conta corrente de %s começa em %s.', split_part(v_fav.name, ' ', 1), to_char(v_desde, 'DD/MM/YYYY'));
  end if;

  if p_simular then
    return jsonb_build_object('ok', true, 'simulacao', true, 'message', array_to_string(v_txt, E'\n'),
                              'valor', v_valor, 'entra_na_conta', v_pagou is not null);
  end if;

  if v_fav.conta_corrente_desde is null then
    update public.payees set conta_corrente_desde = v_desde where id = v_fav.id;
  end if;

  if v_antes.id is not null then
    update public.commissions
       set modo = v_modo, base = v_base, percentage = case when v_modo = 'percentual' then p_percentual end,
           amount = greatest(v_valor, 0), base_value = v_base_valor,
           descricao = coalesce(nullif(btrim(p_descricao), ''), descricao),
           data_servico = coalesce(p_data, data_servico),
           cliente_pagou_em = v_pagou, updated_at = now()
     where id = v_antes.id
    returning id into v_id;
  else
    insert into public.commissions (service_order_id, payee_id, amount, base_value, percentage, status, modo, base,
                                    descricao, data_servico, cliente_pagou_em, criado_por)
    values (p_os_id, p_favorecido_id, greatest(v_valor, 0), v_base_valor,
            case when v_modo = 'percentual' then p_percentual end, 'pending', v_modo, v_base,
            nullif(btrim(p_descricao), ''), coalesce(p_data, public._hoje_brt()), v_pagou, v_autor)
    returning id into v_id;
  end if;

  v_saldo := public.conta_corrente_freelancer(p_favorecido_id, null, null, p_autor);
  return jsonb_build_object('ok', true, 'id', v_id, 'valor', v_valor, 'entra_na_conta', v_pagou is not null,
                            'substituiu', v_antes.id is not null,
                            'saldo', v_saldo -> 'saldo_final', 'estado', v_saldo -> 'estado',
                            'message', array_to_string(v_txt, E'\n'));
end;
$$;

create or replace function public.apagar_servico_prestador(p_servico_id uuid, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  c record;
begin
  select cm.*, so.service_order_number as numero, p.name as nome into c
    from public.commissions cm
    join public.service_orders so on so.id = cm.service_order_id
    join public.payees p on p.id = cm.payee_id
   where cm.id = p_servico_id and cm.modo is not null;
  if c.id is null then raise exception 'Serviço não encontrado.' using errcode = 'P0001'; end if;
  if c.status = 'cancelled' then
    return jsonb_build_object('ok', true, 'apagado', false, 'message', 'Esse serviço já estava apagado.');
  end if;
  update public.commissions set status = 'cancelled', updated_at = now() where id = c.id;
  return jsonb_build_object('ok', true, 'apagado', true,
    'message', format('Serviço de %s na %s apagado (%s).', c.nome, c.numero,
                      public._rotulo_do_servico(c.modo, c.percentage, c.base)));
end;
$$;

create or replace function public.servicos_do_prestador(p_favorecido_id uuid, p_autor uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.id, 'os_id', so.id, 'numero', so.service_order_number,
             'cliente', cl.name, 'barco', ve.name, 'status_os', so.status, 'pagamento_os', so.payment_status,
             'modo', c.modo, 'percentual', c.percentage, 'base', c.base,
             'rotulo', public._rotulo_do_servico(c.modo, c.percentage, c.base),
             'valor', public._valor_do_servico(c.modo, c.amount, c.percentage, c.base, c.service_order_id, c.cliente_pagou_em),
             'descricao', c.descricao, 'data_servico', c.data_servico,
             'cliente_pagou_em', c.cliente_pagou_em,
             'situacao', case when c.cliente_pagou_em is null then 'aguardando_cliente' else 'na_conta' end)
           order by (c.cliente_pagou_em is not null), coalesce(c.cliente_pagou_em, c.data_servico) desc, so.service_order_number)
      from public.commissions c
      join public.service_orders so on so.id = c.service_order_id
      left join public.clients cl on cl.id = so.client_id
      left join public.vessels ve on ve.id = so.vessel_id
     where c.payee_id = p_favorecido_id and c.modo is not null and c.status is distinct from 'cancelled'), '[]'::jsonb);
end;
$$;

-- ── 4. O que abate: diária e também serviço de terceiros ───────────────────────────────────────────────
create or replace function public._abate_diarias(p_categoria text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_categoria, 'Diárias de freelancers') in ('Diárias de freelancers', 'Serviços de terceiros');
$$;

-- ── 5. A conta corrente com o tipo 'servico' ───────────────────────────────────────────────────────────
create or replace function public._conta_corrente_linhas(p_favorecido_id uuid)
returns table(data date, tipo text, id uuid, jornada text, fracao numeric, valor_diaria numeric, extras numeric,
              descontos numeric, trabalhado numeric, pago numeric, descricao text, conta text, categoria text,
              observacao text, os jsonb, criado_em timestamptz, aguardando boolean)
language sql
stable
security definer
set search_path = public
as $$
  with fav as (
    select id, coalesce(conta_corrente_desde, date '1900-01-01') as desde,
           nullif(regexp_replace(coalesce(document, ''), '\D', '', 'g'), '') as doc
      from public.payees where id = p_favorecido_id
  ),
  -- 1a: o lançamento com o valor que ele recebeu (o principal do grupo, com a soma das partes)
  lanc as (
    select p.id, p.issue_date, p.bank_transaction_id, g.pago
      from public.payables p
      join fav on (p.payee_id = fav.id or p.beneficiario_id = fav.id)
      cross join lateral (
        select sum(case when x.payee_id = fav.id then coalesce(x.paid_amount, 0) else x.amount end) as pago
          from public.payables x
         where (x.id = p.id or x.divisao_id = p.id) and x.status <> 'cancelled') g
     where p.status <> 'cancelled' and p.divisao_id is null and p.issue_date >= fav.desde and g.pago > 0
       and public._abate_diarias(p.expense_category)
  ),
  -- 1a: anotação que nunca casou com o banco e o lançamento que já a cobre (defeito 4)
  soltas as (
    select a.id, a.valor, a.data_prevista
      from public.anotacoes_do_extrato a
      join fav on fav.id = a.favorecido_id
     where a.sentido = 'debit' and a.status = 'aguardando' and a.bank_transaction_id is null
       and a.data_prevista >= fav.desde and public._abate_diarias(a.categoria)
  ),
  cobertas as (
    select s.id
      from soltas s
     where (select count(*) from soltas o
             where o.valor = s.valor and abs(o.data_prevista - s.data_prevista) <= 3
               and (o.data_prevista, o.id) <= (s.data_prevista, s.id))
        <= (select count(*) from lanc l
             where l.pago = s.valor and abs(l.issue_date - s.data_prevista) <= 3
               and not exists (select 1 from public.anotacoes_do_extrato an
                                where an.bank_transaction_id = l.bank_transaction_id and an.status <> 'cancelada'))
  ),
  -- 28/10: anotação solta que nenhum lançamento cobre
  vivas as (
    select s.* from soltas s where not exists (select 1 from cobertas c where c.id = s.id)
  ),
  -- 1a: Pix do banco para o CPF dele que ainda não virou lançamento nem tem anotação ligada (defeito 3)
  pix_cpf as (
    select bt.id, bt.amount as valor, bt.transaction_date as data
      from public.bank_transactions bt
      join fav on fav.doc is not null
              and regexp_replace(coalesce(bt.counterparty_document, ''), '\D', '', 'g') = fav.doc
     where bt.transaction_type = 'debit' and bt.amount > 0 and bt.transaction_date >= fav.desde
       and bt.dismissed_kind is null
       and not exists (select 1 from public.payables p where p.bank_transaction_id = bt.id and p.status <> 'cancelled')
       and not exists (select 1 from public.anotacoes_do_extrato an where an.bank_transaction_id = bt.id and an.status <> 'cancelada')
       and not exists (select 1 from public.finance_review_queue q where q.bank_transaction_id = bt.id and q.status = 'rejected')
  ),
  -- 28/10: o Pix do banco que é uma anotação ainda solta (mesmo valor, até 3 dias, um para um) conta
  -- uma vez só, pela anotação — que passa a dizer "No banco". Antes contava duas vezes até o motor
  -- ligar os dois (06:10/15:10), e para sempre quando a anotação não tinha como casar (CPF que faltava).
  pix_anotados as (
    select b.id
      from pix_cpf b
     where (select count(*) from pix_cpf o
             where o.valor = b.valor and abs(o.data - b.data) <= 3 and (o.data, o.id) <= (b.data, b.id))
        <= (select count(*) from vivas s where s.valor = b.valor and abs(s.data_prevista - b.data) <= 3)
  ),
  vivas_no_banco as (
    select s.id
      from vivas s
     where (select count(*) from vivas o
             where o.valor = s.valor and abs(o.data_prevista - s.data_prevista) <= 3
               and (o.data_prevista, o.id) <= (s.data_prevista, s.id))
        <= (select count(*) from pix_cpf b where b.valor = s.valor and abs(b.data - s.data_prevista) <= 3)
  )
  select ws.data, 'dia'::text, ws.id,
         case ws.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
         ws.fracao, ws.valor_diaria, ws.extras, ws.descontos, ws.valor_dia, 0::numeric,
         null::text, null::text, null::text, ws.observacao,
         coalesce((select jsonb_agg(jsonb_build_object('id', so.id, 'numero', so.service_order_number)
                                    order by so.service_order_number)
                     from public.work_shift_os wo
                     join public.service_orders so on so.id = wo.service_order_id
                    where wo.shift_id = ws.id), '[]'::jsonb),
         ws.created_at, false
    from public.work_shifts ws
    join public.work_profiles wp on wp.id = ws.work_profile_id
    join fav on fav.id = wp.payee_id
   where ws.fracao is not null and ws.data >= fav.desde
  union all
  -- O que ele recebeu: lançamento no nome dele (conta o que foi pago dele) ou pago do bolso do
  -- sócio para ele (conta o valor inteiro — o dinheiro já chegou a ele, o reembolso é do sócio).
  -- Resposta 4 do dono (11/10/2026): o pagamento dividido entre diárias e reembolso é UMA linha (o
  -- principal do grupo, com a soma das partes) e diz quanto dele foi reembolso: o saldo não muda.
  select p.issue_date, 'pagamento'::text, p.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric,
         g.pago,
         -- 1a: sufixo só quando houve reembolso (defeito 1)
         p.description || case when coalesce(dv.reembolsos, 0) > 0
                               then ' (inclui reembolso de despesas pagas pelo técnico: ' || public._brl(dv.reembolsos) || ')'
                               else '' end,
         case when p.payee_id = fav.id
              then coalesce(bc.label, case when p.payment_method = 'cash' then 'Caixa (dinheiro)' end, 'Sem conta ligada')
              else 'Bolso de ' || coalesce(soc.name, 'sócio') end,
         p.expense_category, null::text, '[]'::jsonb, p.created_at, false
    from public.payables p
    join fav on (p.payee_id = fav.id or p.beneficiario_id = fav.id)
    cross join lateral (
      select sum(case when x.payee_id = fav.id then coalesce(x.paid_amount, 0) else x.amount end) as pago
        from public.payables x
       where (x.id = p.id or x.divisao_id = p.id) and x.status <> 'cancelled') g
    left join lateral (
      select sum(r.valor) as reembolsos
        from public.diarias_pagamentos_divididos d
        join public.diarias_reembolsos r on r.id = any (d.reembolsos)
       where d.payable_id = p.id and d.status = 'aplicada' and p.bank_transaction_id is not null) dv on true
    left join public.payees soc on soc.id = p.payee_id
    left join public.bank_transactions bt on bt.id = p.bank_transaction_id
    left join public.bank_connections bc on bc.id = bt.bank_connection_id
   where p.status <> 'cancelled' and p.divisao_id is null and p.issue_date >= fav.desde
     and g.pago > 0
     and public._abate_diarias(p.expense_category)  -- 1b
  union all
  -- Pix/débito ANOTADO para ele que ainda não virou lançamento (decisão do dono, 06/10/2026: já
  -- desconta). Esperando a linha do banco, ou já casado com ela e esperando a aprovação. Quando o
  -- lançamento existe, ele entra pela parte de cima e esta linha sai — nunca os dois. Linha casada
  -- que foi RECUSADA na fila não conta: o dono disse que não era aquilo.
  select a.data_prevista, 'pagamento'::text, a.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric, a.valor,
         coalesce(a.descricao, 'Pix anotado')
           || case when coalesce(dva.reembolsos, 0) > 0
                   then ' (inclui reembolso de despesas pagas pelo técnico: ' || public._brl(dva.reembolsos) || ')'
                   else '' end,
         -- 1a: o que o banco já trouxe não está "aguardando o banco" (defeito 2)
         case when a.bank_transaction_id is not null
                or exists (select 1 from vivas_no_banco v where v.id = a.id) then 'No banco — falta aprovar na fila'  -- 28/10
              else 'Anotado — aguardando o banco' end,
         a.categoria, null::text, '[]'::jsonb, a.criada_em, true
    from public.anotacoes_do_extrato a
    join fav on fav.id = a.favorecido_id
    left join lateral (
      select sum(r.valor) as reembolsos
        from public.diarias_pagamentos_divididos d
        join public.diarias_reembolsos r on r.id = any (d.reembolsos)
       where d.anotacao_id = a.id and d.status = 'pendente') dva on true
   where a.sentido = 'debit' and a.data_prevista >= fav.desde
     and public._abate_diarias(a.categoria)  -- 1b
     and (a.status = 'aguardando'
          or (a.status = 'aplicada' and a.bank_transaction_id is not null
              and not exists (select 1 from public.payables p
                               where p.bank_transaction_id = a.bank_transaction_id and p.status <> 'cancelled')
              and not exists (select 1 from public.finance_review_queue q
                               where q.bank_transaction_id = a.bank_transaction_id and q.status = 'rejected')))
     and not exists (select 1 from cobertas c where c.id = a.id)
  union all
  -- 1a: Pix do banco para o CPF dele que ainda não virou lançamento nem tem anotação (defeito 3)
  select bt.transaction_date, 'pagamento'::text, bt.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric, bt.amount,
         coalesce(nullif(btrim(bt.description), ''), 'Pix enviado'),
         'No banco — falta aprovar na fila',
         null::text, null::text, '[]'::jsonb, bt.created_at, true
    from pix_cpf b
    join public.bank_transactions bt on bt.id = b.id
   where not exists (select 1 from pix_anotados x where x.id = b.id)  -- 28/10
  union all
  -- F2b: o reembolso de despesa que ele pagou (comprovante). Crédito dele: entra como "trabalhado";
  -- "conta" é o código do CMP. Cancelado não conta. Já quitado por um pagamento dividido (resposta 4):
  -- "pago em DD/MM".
  select r.data, 'reembolso'::text, r.id, null::text, null::numeric, null::numeric, null::numeric, null::numeric,
         r.valor, 0::numeric, r.descricao, r.origem_codigo, r.categoria,
         (select 'pago em ' || to_char(coalesce(pp.issue_date, an.data_prevista), 'DD/MM')
            from public.diarias_pagamentos_divididos d
            left join public.payables pp on pp.id = d.payable_id
            left join public.anotacoes_do_extrato an on an.id = d.anotacao_id
           where r.id = any (d.reembolsos)
             and public._diarias_divisao_viva(d.status, d.payable_id, d.lancamentos)
           order by d.criado_em desc
           limit 1),
         case when so.id is null then '[]'::jsonb
              else jsonb_build_array(jsonb_build_object('id', so.id, 'numero', so.service_order_number)) end,
         r.criado_em, false
    from public.diarias_reembolsos r
    join fav on fav.id = r.favorecido_id
    left join public.service_orders so on so.id = r.os_id
   where r.status = 'ativo' and r.data >= fav.desde
  union all
  -- 12/11/2026: o serviço por OS (prestador). Crédito na data em que o cliente terminou de pagar a OS
  -- (decisão do dono); a OS paga antes do começo da conta entra no primeiro dia dela. jornada = o rótulo
  -- ("valor combinado", "30% da mão de obra"); observacao = o que ele fez.
  select greatest(c.cliente_pagou_em, fav.desde), 'servico'::text, c.id,
         public._rotulo_do_servico(c.modo, c.percentage, c.base),
         null::numeric, null::numeric, null::numeric, null::numeric,
         c.amount, 0::numeric,
         'Serviço ' || so.service_order_number
           || coalesce(' — ' || nullif(concat_ws(' – ', cl.name, ve.name), ''), ''),
         null::text, null::text, c.descricao,
         jsonb_build_array(jsonb_build_object('id', so.id, 'numero', so.service_order_number)),
         c.created_at, false
    from public.commissions c
    join fav on fav.id = c.payee_id
    join public.service_orders so on so.id = c.service_order_id
    left join public.clients cl on cl.id = so.client_id
    left join public.vessels ve on ve.id = so.vessel_id
   where c.modo is not null and c.status is distinct from 'cancelled' and c.cliente_pagou_em is not null;
$$;

-- ── 6. conta_corrente_freelancer: serviços no trabalhado + o que espera o cliente pagar ────────────────
create or replace function public.conta_corrente_freelancer(
  p_favorecido_id uuid,
  p_de date default null,
  p_ate date default null,
  p_autor uuid default null,
  p_atalho text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_perfil record;
  v_de date := p_de;
  v_ate date := p_ate;
  v_anterior numeric;
  v_linhas jsonb;
  v_dias numeric;
  v_trab numeric;
  v_serv numeric;
  v_n_serv int;
  v_reemb numeric;
  v_pago numeric;
  v_aguardando numeric;
  v_falta_aprovar numeric;
  v_final numeric;
  v_dias_tudo numeric;
  v_pago_tudo numeric;
  v_aguardando_cliente jsonb;
begin
  select id, name, kind, conta_corrente_desde, saldo_anterior into v_fav
    from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;

  if p_atalho is not null then
    select x.de, x.ate into v_de, v_ate from public._periodo_do_atalho(p_favorecido_id, p_atalho) x;
  end if;

  v_de := greatest(coalesce(v_de, v_fav.conta_corrente_desde, date '1900-01-01'),
                   coalesce(v_fav.conta_corrente_desde, date '1900-01-01'));
  v_ate := coalesce(v_ate, date '9999-12-31');
  if v_ate < v_de then raise exception 'Período invertido: % a %.', to_char(v_de, 'DD/MM/YYYY'), to_char(v_ate, 'DD/MM/YYYY'); end if;

  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
     and vigencia_inicio <= least(v_ate, public._hoje_brt())
   order by vigencia_inicio desc limit 1;

  select v_fav.saldo_anterior + coalesce(sum(l.trabalhado - l.pago), 0) into v_anterior
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data < v_de;

  with l as (
    select * from public._conta_corrente_linhas(p_favorecido_id) where data between v_de and v_ate
  ), o as (
    select l.*, v_anterior + sum(l.trabalhado - l.pago) over (
             order by l.data, case l.tipo when 'dia' then 0 when 'servico' then 0 else 1 end, l.criado_em, l.id
             rows between unbounded preceding and current row) as saldo,
           row_number() over (order by l.data, case l.tipo when 'dia' then 0 when 'servico' then 0 else 1 end,
                              l.criado_em, l.id) as ordem
      from l
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'data', o.data, 'tipo', o.tipo, 'id', o.id, 'jornada', o.jornada, 'fracao', o.fracao,
           'valor_diaria', o.valor_diaria, 'extras', o.extras, 'descontos', o.descontos,
           'trabalhado', o.trabalhado, 'pago', o.pago, 'descricao', o.descricao, 'conta', o.conta,
           'categoria', o.categoria, 'observacao', o.observacao, 'os', o.os, 'saldo', round(o.saldo, 2),
           'aguardando', o.aguardando, 'criado_em', o.criado_em)
           order by o.ordem), '[]'::jsonb),
         coalesce(sum(o.fracao) filter (where o.tipo = 'dia'), 0),
         -- 12/11: "trabalhado" = diárias + serviços (o crédito pelo trabalho); "servicos" à parte
         coalesce(sum(o.trabalhado) filter (where o.tipo in ('dia', 'servico')), 0),
         coalesce(sum(o.trabalhado) filter (where o.tipo = 'servico'), 0),
         count(*) filter (where o.tipo = 'servico'),
         coalesce(sum(o.trabalhado) filter (where o.tipo = 'reembolso'), 0),
         coalesce(sum(o.pago), 0),
         -- 1a: só o que o banco ainda não trouxe; o que já está no banco vai à parte
         coalesce(sum(o.pago) filter (where o.aguardando and o.conta = 'Anotado — aguardando o banco'), 0),
         coalesce(sum(o.pago) filter (where o.aguardando and o.conta = 'No banco — falta aprovar na fila'), 0)
    into v_linhas, v_dias, v_trab, v_serv, v_n_serv, v_reemb, v_pago, v_aguardando, v_falta_aprovar
    from o;

  v_final := v_anterior + v_trab + v_reemb - v_pago;

  -- 12/11: o que ele já fez e espera o cliente pagar a OS (fora do saldo)
  select coalesce(jsonb_agg(x order by x ->> 'numero'), '[]'::jsonb) into v_aguardando_cliente
    from jsonb_array_elements(public.servicos_do_prestador(p_favorecido_id, p_autor)) x
   where x ->> 'situacao' = 'aguardando_cliente';

  -- 12/11: o serviço (na conta ou esperando o cliente) conta como "trabalho lançado" para o estado: pago
  -- antes de o cliente pagar é "adiantado", não "pagamento sem dia lançado"
  select coalesce(sum(l.fracao) filter (where l.tipo = 'dia'), 0) + count(*) filter (where l.tipo = 'servico')
           + jsonb_array_length(v_aguardando_cliente),
         coalesce(sum(l.pago), 0)
    into v_dias_tudo, v_pago_tudo
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data <= v_ate;

  return jsonb_build_object(
    'favorecido', jsonb_build_object('id', v_fav.id, 'nome', v_fav.name,
                                     'desde', v_fav.conta_corrente_desde, 'saldo_inicial', v_fav.saldo_anterior,
                                     'diaria', v_perfil.valor_diaria,
                                     'modo', case when v_perfil.id is not null then 'diaria' else 'servico' end),
    'atalho', p_atalho,
    'de', case when v_de = date '1900-01-01' then null else v_de end,
    'ate', case when v_ate = date '9999-12-31' then null else v_ate end,
    'saldo_anterior', round(v_anterior, 2),
    'linhas', v_linhas,
    'dias', v_dias,
    'trabalhado', round(v_trab, 2),
    'servicos', round(v_serv, 2),
    'n_servicos', v_n_serv,
    'reembolsos', round(v_reemb, 2),
    'pago', round(v_pago, 2),
    'pago_aguardando_banco', round(v_aguardando, 2),
    'pago_falta_aprovar', round(v_falta_aprovar, 2),
    'saldo_final', round(v_final, 2),
    'estado', public._estado_do_saldo(v_final, v_dias_tudo, v_pago_tudo),
    'aguardando_cliente', round(coalesce((select sum((x ->> 'valor')::numeric) from jsonb_array_elements(v_aguardando_cliente) x), 0), 2),
    'servicos_aguardando_cliente', v_aguardando_cliente
  );
end;
$$;

-- ── 7. resumo_freelancers: entra o prestador com conta corrente ────────────────────────────────────────
create or replace function public.resumo_freelancers(
  p_de date default null,
  p_ate date default null,
  p_autor uuid default null,
  p_atalho text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_pessoas jsonb := '[]'::jsonb;
  f record;
  c jsonb;
  v_ultimo date;
begin
  for f in
    select p.id, p.name
      from public.payees p
     where p.active
       and (exists (select 1 from public.work_profiles wp where wp.payee_id = p.id and wp.modo_pagamento = 'diaria')
            -- 12/11: o prestador por serviço (Alex) — com conta corrente começada
            or (p.kind in ('prestador', 'comissionado') and p.conta_corrente_desde is not null))
     order by p.name
  loop
    c := public.conta_corrente_freelancer(f.id, p_de, p_ate, p_autor, p_atalho);
    select max(l.data) into v_ultimo
      from public._conta_corrente_linhas(f.id) l
     where l.tipo = 'pagamento'
       and l.data <= coalesce((c ->> 'ate')::date, date '9999-12-31')
       and l.data >= coalesce((c ->> 'de')::date, date '1900-01-01');
    v_pessoas := v_pessoas || jsonb_build_object(
      'id', f.id, 'nome', f.name,
      'diaria', c -> 'favorecido' -> 'diaria',
      'modo', c -> 'favorecido' -> 'modo',
      'desde', c -> 'favorecido' -> 'desde',
      'de', c -> 'de', 'ate', c -> 'ate',
      'dias', c -> 'dias', 'trabalhado', c -> 'trabalhado', 'reembolsos', c -> 'reembolsos', 'pago', c -> 'pago',
      'servicos', c -> 'servicos', 'n_servicos', c -> 'n_servicos',
      'aguardando_cliente', c -> 'aguardando_cliente',
      'pago_aguardando_banco', c -> 'pago_aguardando_banco',
      'pago_falta_aprovar', c -> 'pago_falta_aprovar',
      'ultimo_pagamento', v_ultimo,
      'saldo_final', c -> 'saldo_final', 'estado', c -> 'estado');
  end loop;

  return jsonb_build_object(
    'pessoas', v_pessoas,
    'atalho', p_atalho,
    'trabalhado', coalesce((select sum((x ->> 'trabalhado')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'reembolsos', coalesce((select sum((x ->> 'reembolsos')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'pago', coalesce((select sum((x ->> 'pago')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'dias', coalesce((select sum((x ->> 'dias')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'deve', coalesce((select sum(greatest((x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0),
    'adiantado', coalesce((select sum(greatest(-(x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0)
  );
end;
$$;

-- ── 8. O recibo de diárias não se aplica ao prestador por serviço ──────────────────────────────────────
create or replace function public._trg_acerto_so_de_diarista()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.work_profiles wp
                  where wp.payee_id = new.favorecido_id and wp.modo_pagamento = 'diaria') then
    raise exception 'Recibo de diárias é só para diarista. Para prestador com CNPJ, o comprovante é a nota fiscal (NFS-e) dele.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_acerto_so_de_diarista on public.acertos_diarias;
create trigger trg_acerto_so_de_diarista
  before insert on public.acertos_diarias
  for each row execute function public._trg_acerto_so_de_diarista();

-- ── 9. Quem executa ────────────────────────────────────────────────────────────────────────────────────
revoke all on function public._base_do_servico(uuid, text) from public, anon, authenticated;
revoke all on function public._valor_do_servico(text, numeric, numeric, text, uuid, date) from public, anon, authenticated;
revoke all on function public._rotulo_do_servico(text, numeric, text) from public, anon, authenticated;
revoke all on function public._os_paga_em(uuid) from public, anon, authenticated;
revoke all on function public._atualizar_servicos_da_os(uuid) from public, anon, authenticated;
revoke all on function public._trg_servicos_quando_a_os_e_paga() from public, anon, authenticated;
revoke all on function public._trg_acerto_so_de_diarista() from public, anon, authenticated;
revoke all on function public._abate_diarias(text) from public, anon, authenticated;
revoke all on function public._conta_corrente_linhas(uuid) from public, anon, authenticated;

revoke all on function public.registrar_servico_prestador(uuid, uuid, numeric, numeric, text, text, date, uuid, boolean) from public, anon;
revoke all on function public.apagar_servico_prestador(uuid, uuid) from public, anon;
revoke all on function public.servicos_do_prestador(uuid, uuid) from public, anon;
grant execute on function public.registrar_servico_prestador(uuid, uuid, numeric, numeric, text, text, date, uuid, boolean) to authenticated, service_role;
grant execute on function public.apagar_servico_prestador(uuid, uuid) to authenticated, service_role;
grant execute on function public.servicos_do_prestador(uuid, uuid) to authenticated, service_role;

revoke all on function public.conta_corrente_freelancer(uuid, date, date, uuid, text) from public, anon;
revoke all on function public.resumo_freelancers(date, date, uuid, text) from public, anon;
grant execute on function public.conta_corrente_freelancer(uuid, date, date, uuid, text) to authenticated, service_role;
grant execute on function public.resumo_freelancers(date, date, uuid, text) to authenticated, service_role;
