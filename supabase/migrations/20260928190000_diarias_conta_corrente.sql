-- Diárias de freelancers: o dia com o valor gravado, a conta corrente por pessoa e o rateio do
-- dia entre OS. Decisões do dono em 28/09/2026 (D1–D12); plano em
-- plans/marineflow-diarias-freelancers.md.
--
-- NÃO cria um módulo paralelo: estende o de jornada (20260818160000), que existia e nunca foi
-- usado. O freelancer é o favorecido (payees) com perfil de diária (work_profiles); o dia é
-- work_shifts; o pagamento é o lançamento que já vem do extrato (payables com payee_id). O saldo é
-- CALCULADO, nunca armazenado: saldo inicial + trabalhado − pago.
--
-- Por que o valor da diária é gravado no dia: mudar a diária no cadastro não pode reescrever o
-- que já foi trabalhado (decisão do dono). O perfil tem vigência, mas o dia carrega o número.
--
-- Por que o dia não guarda horário: diarista recebe pelo dia, e início/fim de expediente não
-- entram no valor. O registro aqui é de prestação de serviço por dia, não de ponto.

-- ---------------------------------------------------------------------------
-- 1. work_shifts: o dia do diarista
-- ---------------------------------------------------------------------------
alter table public.work_shifts
  add column if not exists fracao       numeric(3,2),
  add column if not exists valor_diaria numeric(12,2),
  add column if not exists extras       numeric(12,2) not null default 0,
  add column if not exists descontos    numeric(12,2) not null default 0;

alter table public.work_shifts
  add column if not exists valor_dia numeric(12,2)
  generated always as (coalesce(fracao, 0) * coalesce(valor_diaria, 0) + extras - descontos) stored;

alter table public.work_shifts drop constraint if exists work_shifts_fracao_do_dia;
alter table public.work_shifts add constraint work_shifts_fracao_do_dia check (
  fracao is null
  or (fracao = 0 and tipo = 'falta')
  or (fracao in (0.5, 1) and tipo = 'diaria')
);
alter table public.work_shifts drop constraint if exists work_shifts_dia_tem_valor;
alter table public.work_shifts add constraint work_shifts_dia_tem_valor check (
  fracao is null or (valor_diaria is not null and valor_diaria > 0)
);
alter table public.work_shifts drop constraint if exists work_shifts_extras_descontos;
alter table public.work_shifts add constraint work_shifts_extras_descontos check (extras >= 0 and descontos >= 0);

-- Um dia por pessoa: é o que torna "registre que o Roberto faltou hoje" idempotente. Vale só para
-- o dia de diarista (fracao preenchida); o turno por hora continua podendo ter vários no dia.
create unique index if not exists work_shifts_um_dia_por_perfil
  on public.work_shifts (work_profile_id, data) where fracao is not null;

comment on column public.work_shifts.fracao is
  'Dia de diarista: 1 = dia inteiro, 0.5 = meio período, 0 = faltou (tipo falta). Nulo = turno por hora.';
comment on column public.work_shifts.valor_diaria is
  'Diária GRAVADA no lançamento (vinda do perfil vigente na data). Mudar o cadastro não reescreve o dia.';
comment on column public.work_shifts.extras is
  'O que o freelancer pagou do próprio bolso e a empresa devolve (almoço, transporte, material). O que a empresa pagou direto não entra aqui.';
comment on column public.work_shifts.valor_dia is
  'fracao × valor_diaria + extras − descontos. Base do saldo e do custo da OS.';

-- ---------------------------------------------------------------------------
-- 2. work_shift_os: o dia dividido entre OS (D5: partes iguais)
-- ---------------------------------------------------------------------------
create table if not exists public.work_shift_os (
  shift_id         uuid not null references public.work_shifts(id) on delete cascade,
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  created_at       timestamptz not null default now(),
  primary key (shift_id, service_order_id)
);
create index if not exists work_shift_os_por_os on public.work_shift_os (service_order_id);

comment on table public.work_shift_os is
  'Em quais OS o dia foi trabalhado. O valor do dia se divide em partes iguais entre elas (decisão do dono, 28/09/2026).';

-- Escrita só pelas funções abaixo (security definer); a tela e o assistente só leem.
alter table public.work_shift_os enable row level security;
create policy work_shift_os_read on public.work_shift_os
  for select to authenticated using (public.pode_ver_folha((select auth.uid())));
revoke all on public.work_shift_os from anon;
grant select on public.work_shift_os to authenticated;

-- ---------------------------------------------------------------------------
-- 3. payees: de quando a conta corrente vale, e com que saldo começa (D3)
-- ---------------------------------------------------------------------------
alter table public.payees
  add column if not exists conta_corrente_desde date,
  add column if not exists saldo_anterior numeric(12,2) not null default 0;

comment on column public.payees.conta_corrente_desde is
  'Dias e pagamentos antes desta data não entram no saldo do freelancer (acertados por fora).';
comment on column public.payees.saldo_anterior is
  'Saldo na data de início: positivo = a empresa devia a ele; negativo = tinha adiantado.';

-- ---------------------------------------------------------------------------
-- 4. payables: quem recebeu, quando o lançamento está no nome de outro (D1)
-- ---------------------------------------------------------------------------
-- No "pago do bolso do sócio" o lançamento fica no nome do SÓCIO (é a ele que a empresa deve o
-- reembolso), e quem recebeu o dinheiro só aparecia no texto — por isso o Pix do Nubank pessoal
-- para o Roberto não entrava no que ele recebeu.
alter table public.payables
  add column if not exists beneficiario_id uuid references public.payees(id) on delete set null;
create index if not exists payables_por_beneficiario on public.payables (beneficiario_id) where beneficiario_id is not null;
comment on column public.payables.beneficiario_id is
  'Quem recebeu o dinheiro quando o lançamento está no nome de outro favorecido (bolso do sócio: payee = sócio a reembolsar).';

-- lancar_no_caixa: igual à de 20260926150000, gravando beneficiario_id no ramo do sócio.
create or replace function public.lancar_no_caixa(
  p_sentido text,                 -- 'saida' | 'entrada'
  p_valor numeric,
  p_descricao text,
  p_data date default null,
  p_categoria text default null,
  p_fornecedor_id uuid default null,
  p_favorecido_id uuid default null,
  p_cliente_id uuid default null,
  p_os_id uuid default null,
  p_pago_por text default 'caixa',   -- 'caixa' | 'socio' (saiu do bolso de um sócio: vira reembolso a pagar)
  p_socio_id uuid default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_data date := coalesce(p_data, public._hoje_brt());
  v_desc text := nullif(btrim(coalesce(p_descricao, '')), '');
  v_cat text;
  v_quem text;
  v_tx uuid;
  v_id uuid;
  v_socio text;
begin
  if p_sentido not in ('saida', 'entrada') then raise exception 'Sentido inválido: % (saida ou entrada).', p_sentido; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'O valor precisa ser maior que zero.'; end if;
  if v_desc is null then raise exception 'Diga o que foi (ex.: almoço da equipe).'; end if;
  if p_pago_por not in ('caixa', 'socio') then raise exception 'Pago por: caixa ou socio.'; end if;
  if v_data > public._hoje_brt() + 1 then raise exception 'Data no futuro: para algo que ainda vai acontecer, use conta a pagar.'; end if;
  perform public._recusa_se_mes_fechado(v_data, 'lançar nesta data');

  v_quem := coalesce(
    (select name from public.suppliers where id = p_fornecedor_id),
    (select name from public.payees where id = p_favorecido_id),
    (select name from public.clients where id = p_cliente_id));

  if p_sentido = 'saida' then
    -- Categoria: a informada; senão a padrão do favorecido; senão "Outras despesas".
    v_cat := coalesce(nullif(btrim(coalesce(p_categoria, '')), ''),
                      (select default_category from public.payees where id = p_favorecido_id),
                      'Outras despesas');

    if p_pago_por = 'socio' then
      if p_socio_id is null then raise exception 'Diga qual sócio pagou, para o reembolso ficar no nome dele.'; end if;
      select name into v_socio from public.payees where id = p_socio_id;
      if v_socio is null then raise exception 'Sócio não encontrado entre os favorecidos.'; end if;
      -- A despesa existe (entra no resultado) e a empresa DEVE ao sócio: conta a pagar em
      -- aberto no nome dele. Nada sai do Caixa. Quem recebeu vai em beneficiario_id (28/09/2026).
      insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status,
                                   expense_category, supplier_id, payee_id, beneficiario_id, linked_service_order_id, origin, notes)
      values (left('Pago por ' || v_socio || ': ' || v_desc, 200), v_data, v_data, round(p_valor, 2), 0, round(p_valor, 2), 'pending',
              v_cat, p_fornecedor_id, p_socio_id, p_favorecido_id, p_os_id, 'manual',
              'Reembolso ao sócio — pago do bolso' || coalesce(' para ' || v_quem, '') || '.')
      returning id into v_id;
    else
      v_tx := public._linha_do_caixa('debit', p_valor, v_data, v_desc, coalesce(v_quem, v_desc), null, null, v_autor);
      insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status,
                                   expense_category, supplier_id, payee_id, supplier_name, linked_service_order_id,
                                   origin, payment_method, bank_transaction_id)
      values (left(v_desc, 200), v_data, v_data, round(p_valor, 2), round(p_valor, 2), 0, 'paid',
              v_cat, p_fornecedor_id, p_favorecido_id, case when p_fornecedor_id is null then v_quem end, p_os_id,
              'manual', 'cash', v_tx)
      returning id into v_id;
    end if;
  else
    if p_cliente_id is null then raise exception 'Dinheiro que entra precisa de cliente: de quem veio?'; end if;
    if p_pago_por <> 'caixa' then raise exception 'Entrada em dinheiro vai para o Caixa.'; end if;
    v_cat := coalesce(nullif(btrim(coalesce(p_categoria, '')), ''), 'Serviços prestados');
    v_tx := public._linha_do_caixa('credit', p_valor, v_data, v_desc, v_quem, null, null, v_autor);
    insert into public.receivables (description, issue_date, due_date, amount, paid_amount, balance_amount, status,
                                    category, client_id, service_order_id, payment_method, bank_transaction_id)
    values (left(v_desc, 200), v_data, v_data, round(p_valor, 2), round(p_valor, 2), 0, 'paid',
            v_cat, p_cliente_id, p_os_id, 'cash', v_tx)
    returning id into v_id;
  end if;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values ('lancou_no_caixa', v_autor, v_tx,
          case when p_sentido = 'saida' then v_id end, case when p_sentido = 'entrada' then v_id end,
          round(p_valor, 2),
          left(case when p_pago_por = 'socio' then 'Pago do bolso de ' || v_socio || ': ' else '' end || v_desc || coalesce(' · ' || v_quem, ''), 300),
          null, jsonb_build_object('sentido', p_sentido, 'categoria', v_cat, 'pago_por', p_pago_por, 'data', v_data));

  return jsonb_build_object(
    'ok', true,
    'lancamento_id', v_id,
    'tipo', case when p_sentido = 'saida' then 'payable' else 'receivable' end,
    'categoria', v_cat,
    'saldo_do_caixa', public.saldo_do_caixa(),
    'message', case
      when p_pago_por = 'socio' then 'Lançado ' || public._brl(p_valor) || ' em ' || v_cat || ', pago por ' || v_socio || ' — fica como reembolso a pagar a ele.'
      when p_sentido = 'saida' then 'Lançado ' || public._brl(p_valor) || ' em ' || v_cat || ', pago em dinheiro. Caixa agora: ' || public._brl(public.saldo_do_caixa()) || '.'
        || case when public.saldo_do_caixa() < 0 then ' Atenção: o Caixa ficou negativo — falta registrar o dinheiro que entrou nele (saldo inicial pela contagem, ou o saque do banco).' else '' end
      else 'Entrada de ' || public._brl(p_valor) || ' em dinheiro lançada. Caixa agora: ' || public._brl(public.saldo_do_caixa()) || '.' end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Funções: registrar, apagar, extrato (conta corrente) e resumo
-- ---------------------------------------------------------------------------

-- "qui 24/09" — dia da semana em português, sem depender do locale do servidor.
create or replace function public._dia_curto(p date)
returns text language sql immutable set search_path = public as $$
  select (array['dom','seg','ter','qua','qui','sex','sáb'])[extract(dow from p)::int + 1] || ' ' || to_char(p, 'DD/MM');
$$;

create or replace function public._rotulo_jornada(p_fracao numeric)
returns text language sql immutable set search_path = public as $$
  select case p_fracao when 1 then 'dia inteiro' when 0.5 then 'meio período' when 0 then 'faltou' end;
$$;

-- Todas as linhas da conta corrente de um favorecido, desde o início dela: os dias e o que ele
-- recebeu. Interna: só as funções abaixo a chamam.
create or replace function public._conta_corrente_linhas(p_favorecido_id uuid)
returns table (
  data date, tipo text, id uuid, jornada text, fracao numeric, valor_diaria numeric, extras numeric,
  descontos numeric, trabalhado numeric, pago numeric, descricao text, conta text, categoria text,
  observacao text, os jsonb, criado_em timestamptz
)
language sql stable security definer set search_path = public as $$
  with fav as (
    select id, coalesce(conta_corrente_desde, date '1900-01-01') as desde
      from public.payees where id = p_favorecido_id
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
         ws.created_at
    from public.work_shifts ws
    join public.work_profiles wp on wp.id = ws.work_profile_id
    join fav on fav.id = wp.payee_id
   where ws.fracao is not null and ws.data >= fav.desde
  union all
  -- O que ele recebeu: lançamento no nome dele (conta o que foi pago dele) ou pago do bolso do
  -- sócio para ele (conta o valor inteiro — o dinheiro já chegou a ele, o reembolso é do sócio).
  select p.issue_date, 'pagamento'::text, p.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric,
         case when p.payee_id = fav.id then coalesce(p.paid_amount, 0) else p.amount end,
         p.description,
         case when p.payee_id = fav.id
              then coalesce(bc.label, case when p.payment_method = 'cash' then 'Caixa (dinheiro)' end, 'Sem conta ligada')
              else 'Bolso de ' || coalesce(soc.name, 'sócio') end,
         p.expense_category, null::text, '[]'::jsonb, p.created_at
    from public.payables p
    join fav on (p.payee_id = fav.id or p.beneficiario_id = fav.id)
    left join public.payees soc on soc.id = p.payee_id
    left join public.bank_transactions bt on bt.id = p.bank_transaction_id
    left join public.bank_connections bc on bc.id = bt.bank_connection_id
   where p.status <> 'cancelled' and p.issue_date >= fav.desde
     and (case when p.payee_id = fav.id then coalesce(p.paid_amount, 0) else p.amount end) > 0;
$$;

create or replace function public._estado_do_saldo(p_saldo numeric, p_dias numeric, p_pago numeric)
returns text language sql immutable set search_path = public as $$
  select case
    when coalesce(p_dias, 0) = 0 and coalesce(p_pago, 0) > 0.005 then 'semdias'
    when p_saldo > 0.005 then 'deve'
    when p_saldo < -0.005 then 'adiantado'
    else 'quitado' end;
$$;

-- Extrato de um freelancer no período: saldo antes do período, cada dia e pagamento com o saldo
-- corrido, totais, saldo final e o estado (deve / adiantado / quitado / semdias).
create or replace function public.conta_corrente_freelancer(
  p_favorecido_id uuid,
  p_de date default null,
  p_ate date default null,
  p_autor uuid default null
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
  v_de date;
  v_ate date;
  v_anterior numeric;
  v_linhas jsonb;
  v_dias numeric;
  v_trab numeric;
  v_pago numeric;
  v_final numeric;
  v_dias_tudo numeric;
  v_pago_tudo numeric;
begin
  select id, name, conta_corrente_desde, saldo_anterior into v_fav
    from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;

  v_de := greatest(coalesce(p_de, v_fav.conta_corrente_desde, date '1900-01-01'),
                   coalesce(v_fav.conta_corrente_desde, date '1900-01-01'));
  v_ate := coalesce(p_ate, date '9999-12-31');
  if v_ate < v_de then raise exception 'Período invertido: % a %.', v_de, v_ate; end if;

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
             order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id
             rows between unbounded preceding and current row) as saldo,
           row_number() over (order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id) as ordem
      from l
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'data', o.data, 'tipo', o.tipo, 'id', o.id, 'jornada', o.jornada, 'fracao', o.fracao,
           'valor_diaria', o.valor_diaria, 'extras', o.extras, 'descontos', o.descontos,
           'trabalhado', o.trabalhado, 'pago', o.pago, 'descricao', o.descricao, 'conta', o.conta,
           'categoria', o.categoria, 'observacao', o.observacao, 'os', o.os, 'saldo', round(o.saldo, 2))
           order by o.ordem), '[]'::jsonb),
         coalesce(sum(o.fracao) filter (where o.tipo = 'dia'), 0),
         coalesce(sum(o.trabalhado), 0),
         coalesce(sum(o.pago), 0)
    into v_linhas, v_dias, v_trab, v_pago
    from o;

  v_final := v_anterior + v_trab - v_pago;

  select coalesce(sum(l.fracao) filter (where l.tipo = 'dia'), 0), coalesce(sum(l.pago), 0)
    into v_dias_tudo, v_pago_tudo
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data <= v_ate;

  return jsonb_build_object(
    'favorecido', jsonb_build_object('id', v_fav.id, 'nome', v_fav.name,
                                     'desde', v_fav.conta_corrente_desde, 'saldo_inicial', v_fav.saldo_anterior,
                                     'diaria', v_perfil.valor_diaria),
    'de', case when v_de = date '1900-01-01' then null else v_de end,
    'ate', case when v_ate = date '9999-12-31' then null else v_ate end,
    'saldo_anterior', round(v_anterior, 2),
    'linhas', v_linhas,
    'dias', v_dias,
    'trabalhado', round(v_trab, 2),
    'pago', round(v_pago, 2),
    'saldo_final', round(v_final, 2),
    'estado', public._estado_do_saldo(v_final, v_dias_tudo, v_pago_tudo)
  );
end;
$$;

-- Um cartão por freelancer de diária: o período e o saldo acumulado até o fim dele.
create or replace function public.resumo_freelancers(
  p_de date default null,
  p_ate date default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_ate date := coalesce(p_ate, date '9999-12-31');
  v_pessoas jsonb := '[]'::jsonb;
  f record;
  c jsonb;
  v_ultimo date;
begin
  for f in
    select distinct p.id, p.name
      from public.payees p
      join public.work_profiles wp on wp.payee_id = p.id and wp.modo_pagamento = 'diaria'
     where p.active
     order by p.name
  loop
    c := public.conta_corrente_freelancer(f.id, p_de, p_ate, p_autor);
    select max(l.data) into v_ultimo
      from public._conta_corrente_linhas(f.id) l
     where l.tipo = 'pagamento' and l.data <= v_ate
       and l.data >= coalesce(p_de, date '1900-01-01');
    v_pessoas := v_pessoas || jsonb_build_object(
      'id', f.id, 'nome', f.name,
      'diaria', c -> 'favorecido' -> 'diaria',
      'desde', c -> 'favorecido' -> 'desde',
      'dias', c -> 'dias', 'trabalhado', c -> 'trabalhado', 'pago', c -> 'pago',
      'ultimo_pagamento', v_ultimo,
      'saldo_final', c -> 'saldo_final', 'estado', c -> 'estado');
  end loop;

  return jsonb_build_object(
    'pessoas', v_pessoas,
    'trabalhado', coalesce((select sum((x ->> 'trabalhado')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'pago', coalesce((select sum((x ->> 'pago')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'dias', coalesce((select sum((x ->> 'dias')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'deve', coalesce((select sum(greatest((x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0),
    'adiantado', coalesce((select sum(greatest(-(x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0)
  );
end;
$$;

-- Registra o dia de um freelancer. Idempotente por pessoa + data: se já há dia lançado, atualiza.
-- "faltou" grava a ausência (valor zero), nunca apaga. O mesmo caminho serve a tela e o assistente.
create or replace function public.registrar_diaria(
  p_favorecido_id uuid,
  p_data date,
  p_jornada text,                    -- 'inteiro' | 'meio' | 'faltou'
  p_os_ids uuid[] default null,      -- nulo = não mexe nas OS; '{}' = tira todas
  p_observacao text default null,    -- nulo = não mexe; '' = limpa
  p_extras numeric default null,     -- nulo = mantém (0 num dia novo)
  p_descontos numeric default null,  -- nulo = mantém (0 num dia novo)
  p_valor_diaria numeric default null, -- nulo = a do perfil vigente na data (ou a já gravada)
  p_origem text default 'painel',
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_perfil record;
  v_antes record;
  v_depois record;
  v_fracao numeric;
  v_tipo text;
  v_id uuid;
  v_acao text;
  v_os_antes text[];
  v_os_depois text[];
  v_resumo text;
begin
  if v_autor is null then raise exception 'Diga quem está registrando a diária.'; end if;
  if p_data is null then raise exception 'Informe a data do dia trabalhado.'; end if;
  if p_data > public._hoje_brt() then raise exception 'Data no futuro (%): registre a diária no dia trabalhado ou depois.', to_char(p_data, 'DD/MM/YYYY'); end if;
  v_fracao := case lower(btrim(coalesce(p_jornada, ''))) when 'inteiro' then 1 when 'meio' then 0.5 when 'faltou' then 0 end;
  if v_fracao is null then raise exception 'Jornada inválida: "%". Use inteiro, meio ou faltou.', p_jornada; end if;
  v_tipo := case when v_fracao = 0 then 'falta' else 'diaria' end;
  if coalesce(p_origem, '') not in ('whatsapp', 'painel', 'agente', 'importado') then raise exception 'Origem inválida: %.', p_origem; end if;
  if coalesce(p_extras, 0) < 0 or coalesce(p_descontos, 0) < 0 then raise exception 'Extras e descontos não podem ser negativos.'; end if;
  if p_valor_diaria is not null and p_valor_diaria <= 0 then raise exception 'O valor da diária precisa ser maior que zero.'; end if;

  select id, name into v_fav from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;

  -- O perfil vigente NA DATA do dia (não o de hoje): a diária de agosto é a de agosto.
  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
     and vigencia_inicio <= p_data and (vigencia_fim is null or vigencia_fim >= p_data)
   order by vigencia_inicio desc limit 1;
  if v_perfil.id is null then
    raise exception '% não tem diária cadastrada em %: cadastre o valor da diária antes.', v_fav.name, to_char(p_data, 'DD/MM/YYYY');
  end if;

  if p_os_ids is not null and exists (
       select 1 from unnest(p_os_ids) o(id) where not exists (select 1 from public.service_orders so where so.id = o.id)) then
    raise exception 'Uma das OS informadas não existe.';
  end if;

  select ws.* into v_antes
    from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = p_favorecido_id and ws.data = p_data and ws.fracao is not null
   for update of ws;

  select coalesce(array_agg(so.service_order_number order by so.service_order_number), '{}') into v_os_antes
    from public.work_shift_os wo join public.service_orders so on so.id = wo.service_order_id
   where wo.shift_id = v_antes.id;

  if v_antes.id is null then
    insert into public.work_shifts (work_profile_id, data, tipo, origem, status, observacao, registrado_por,
                                    aprovado_por, aprovado_em, fracao, valor_diaria, extras, descontos)
    values (v_perfil.id, p_data, v_tipo, p_origem, 'aprovado', nullif(btrim(coalesce(p_observacao, '')), ''), v_autor,
            v_autor, now(), v_fracao, round(coalesce(p_valor_diaria, v_perfil.valor_diaria), 2),
            round(coalesce(p_extras, 0), 2), round(coalesce(p_descontos, 0), 2))
    returning id into v_id;
    v_acao := 'criado';
  else
    v_id := v_antes.id;
    update public.work_shifts set
      tipo = v_tipo,
      fracao = v_fracao,
      valor_diaria = round(coalesce(p_valor_diaria, valor_diaria), 2),
      extras = round(coalesce(p_extras, extras), 2),
      descontos = round(coalesce(p_descontos, descontos), 2),
      observacao = case when p_observacao is null then observacao else nullif(btrim(p_observacao), '') end,
      status = 'aprovado', aprovado_por = v_autor, aprovado_em = now()
    where id = v_id;
    v_acao := 'atualizado';
  end if;

  if p_os_ids is not null then
    delete from public.work_shift_os where shift_id = v_id and not (service_order_id = any (p_os_ids));
    insert into public.work_shift_os (shift_id, service_order_id)
    select v_id, x.os from (select distinct unnest(p_os_ids) as os) x
    on conflict do nothing;
  end if;

  select ws.* into v_depois from public.work_shifts ws where ws.id = v_id;
  select coalesce(array_agg(so.service_order_number order by so.service_order_number), '{}') into v_os_depois
    from public.work_shift_os wo join public.service_orders so on so.id = wo.service_order_id
   where wo.shift_id = v_id;

  if v_acao = 'atualizado'
     and v_antes.fracao = v_depois.fracao and v_antes.valor_dia = v_depois.valor_dia
     and v_antes.observacao is not distinct from v_depois.observacao and v_os_antes = v_os_depois then
    v_acao := 'sem_mudanca';
  end if;

  v_resumo := v_fav.name || ' · ' || public._dia_curto(p_data) || ' · ' || public._rotulo_jornada(v_depois.fracao)
              || ' · ' || public._brl(v_depois.valor_dia)
              || case when cardinality(v_os_depois) > 0 then ' · OS ' || array_to_string(v_os_depois, ', ') else '' end;

  return jsonb_build_object(
    'ok', true,
    'acao', v_acao,
    'diaria_id', v_id,
    'favorecido_id', v_fav.id,
    'favorecido', v_fav.name,
    'data', p_data,
    'jornada', case v_depois.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
    'valor_diaria', v_depois.valor_diaria,
    'valor_dia', v_depois.valor_dia,
    'os', to_jsonb(v_os_depois),
    'antes', case when v_antes.id is null then null else jsonb_build_object(
               'jornada', case v_antes.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
               'valor_dia', v_antes.valor_dia, 'os', to_jsonb(v_os_antes)) end,
    'message', v_resumo || case v_acao
      when 'criado' then ' — registrado.'
      when 'sem_mudanca' then ' — já estava assim.'
      else ' — atualizado (era ' || public._rotulo_jornada(v_antes.fracao) || ', ' || public._brl(v_antes.valor_dia) || ').' end
  );
end;
$$;

-- Apaga um dia e devolve tudo o que ele tinha — é o que o "Desfazer" usa para registrar de novo.
create or replace function public.apagar_diaria(p_diaria_id uuid, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v record;
  v_os uuid[];
begin
  if v_autor is null then raise exception 'Diga quem está apagando a diária.'; end if;
  select ws.*, wp.payee_id, p.name as nome into v
    from public.work_shifts ws
    join public.work_profiles wp on wp.id = ws.work_profile_id
    join public.payees p on p.id = wp.payee_id
   where ws.id = p_diaria_id and ws.fracao is not null
   for update of ws;
  if v.id is null then raise exception 'Diária não encontrada (talvez já tenha sido apagada).'; end if;

  select coalesce(array_agg(service_order_id), '{}') into v_os from public.work_shift_os where shift_id = p_diaria_id;
  delete from public.work_shifts where id = p_diaria_id;

  return jsonb_build_object(
    'ok', true,
    'apagado', jsonb_build_object(
      'favorecido_id', v.payee_id, 'data', v.data,
      'jornada', case v.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
      'valor_diaria', v.valor_diaria, 'extras', v.extras, 'descontos', v.descontos,
      'observacao', v.observacao, 'os_ids', to_jsonb(v_os)),
    'message', 'Diária de ' || v.nome || ' em ' || public._dia_curto(v.data) || ' apagada.'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Trava: a folha não paga diarista que tem conta corrente
-- ---------------------------------------------------------------------------
-- O que se paga ao diarista vem do extrato (Pix → lançamento). O fechamento de folha criaria uma
-- conta a pagar do mesmo trabalho, e o casamento com o Pix só é sugerido quando o valor bate —
-- adiantamento e pagamento parcial virariam despesa em dobro.
create or replace function public._folha_sem_diarista_de_conta_corrente()
returns trigger language plpgsql set search_path = public as $$
declare
  v_nome text;
begin
  select p.name into v_nome
    from public.work_profiles wp join public.payees p on p.id = wp.payee_id
   where wp.id = new.work_profile_id and wp.modo_pagamento = 'diaria' and p.conta_corrente_desde is not null;
  if v_nome is not null then
    raise exception '% é diarista com conta corrente: o que se paga a ele vem do extrato, e a folha criaria a mesma despesa em dobro. Veja o saldo em Financeiro › Diárias.', v_nome
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_folha_sem_diarista on public.payroll_lines;
create trigger trg_folha_sem_diarista before insert on public.payroll_lines
  for each row execute function public._folha_sem_diarista_de_conta_corrente();

-- ---------------------------------------------------------------------------
-- 7. D10: valor deste módulo só para admin e financeiro
-- ---------------------------------------------------------------------------
-- Antes, o titular com login lia o próprio perfil, os próprios dias e a própria folha (com
-- valores). Ninguém da equipe tem login hoje; a regra do dono é que técnico não vê valor nenhum.
alter policy work_profiles_read on public.work_profiles using (public.pode_ver_folha((select auth.uid())));
alter policy work_shifts_read on public.work_shifts using (public.pode_ver_folha((select auth.uid())));
alter policy work_shifts_insert_proprio on public.work_shifts with check (public.pode_ver_folha((select auth.uid())));
alter policy work_shifts_update_proprio on public.work_shifts
  using (public.pode_ver_folha((select auth.uid()))) with check (public.pode_ver_folha((select auth.uid())));
alter policy payroll_lines_read on public.payroll_lines using (public.pode_ver_folha((select auth.uid())));

-- ---------------------------------------------------------------------------
-- 8. Quem executa
-- ---------------------------------------------------------------------------
-- Função nova nasce executável por PUBLIC (e, por ele, por anon). Fechar na MESMA migration.
revoke all on function public._conta_corrente_linhas(uuid) from public, anon, authenticated;
revoke all on function public._dia_curto(date) from public, anon, authenticated;
revoke all on function public._rotulo_jornada(numeric) from public, anon, authenticated;
revoke all on function public._estado_do_saldo(numeric, numeric, numeric) from public, anon, authenticated;
revoke all on function public._folha_sem_diarista_de_conta_corrente() from public, anon, authenticated;
revoke all on function public.conta_corrente_freelancer(uuid, date, date, uuid) from public, anon;
revoke all on function public.resumo_freelancers(date, date, uuid) from public, anon;
revoke all on function public.registrar_diaria(uuid, date, text, uuid[], text, numeric, numeric, numeric, text, uuid) from public, anon;
revoke all on function public.apagar_diaria(uuid, uuid) from public, anon;
grant execute on function public.conta_corrente_freelancer(uuid, date, date, uuid) to authenticated, service_role;
grant execute on function public.resumo_freelancers(date, date, uuid) to authenticated, service_role;
grant execute on function public.registrar_diaria(uuid, date, text, uuid[], text, numeric, numeric, numeric, text, uuid) to authenticated, service_role;
grant execute on function public.apagar_diaria(uuid, uuid) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260928190000', 'diarias_conta_corrente')
on conflict (version) do nothing;
