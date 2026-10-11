-- Comprovantes F2b (11/10/2026): reembolso do técnico nas Diárias.
--
-- Dono: "pode ser assim". Quando quem pagou a compra foi um técnico com diária (work_profiles
-- modo_pagamento = 'diaria'), o CMP grava um CRÉDITO de reembolso na conta corrente dele, que entra
-- no próximo acerto/recibo; cancelar o CMP desfaz o crédito (bloqueado se o acerto que o inclui já
-- foi fechado). Substitui a pendência "acerto_tecnico" da F2 (que fica só para o técnico sem diária).
--
--   * tabela diarias_reembolsos: um crédito por CMP (status ativo/cancelado). Só as funções dos
--     comprovantes escrevem; o financeiro lê (pode_ver_folha). A tabela leva só origem_codigo
--     ('CMP-00124'): FK só comprovantes.reembolso_id → diarias_reembolsos (PGRST201);
--   * trava _reembolso_em_acerto_fechado: reembolso dentro de acerto fechado não entra, não muda, não
--     sai (a mesma regra do _dia_em_acerto_fechado);
--   * acertos_diarias.reembolsos (a foto do período ganha a coluna);
--   * _comprovante_reembolso_data: o reembolso entra sempre no período ABERTO ("no próximo acerto");
--   * redefinidas, com a MESMA casca (linguagem, security definer, search_path = public, grants):
--     _conta_corrente_linhas (ramo "reembolso"), conta_corrente_freelancer (trabalhado = só os dias;
--     reembolsos à parte; o saldo soma os dois), resumo_freelancers (reembolsos por pessoa e no total)
--     e fechar_acerto_diarias (grava a foto e mostra "· reembolso de despesas pagas pelo técnico R$ X";
--     a simulação lista os itens). Corpo de 20261006200000 / 20261006220000 IGUAL + só o diff da F2b.
--
-- Ajustes do dono (11/10/2026, resposta 4): o pagamento ao técnico é dividido entre "Diárias de
-- freelancers" e o reembolso de despesas pagas pelo técnico (a categoria de cada comprovante) — o sistema
-- propõe, o dono confirma: tabela diarias_pagamentos_divididos, as RPCs proposta_de_divisao_do_pagamento,
-- registrar_pagamento_do_freelancer e dividir_pagamento_do_freelancer, e _diarias_aplicar_divisoes_pendentes
-- (a manutenção do cron aplica a divisão do Pix anotado depois da aprovação). A conta corrente mostra o
-- pagamento dividido como UMA linha (o saldo não muda). Rótulo inequívoco (resposta 9): "Reembolso de
-- despesas pagas pelo técnico".
--
-- DDL + funções. Não escreve dados. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. Tabela
-- ---------------------------------------------------------------------------------------------
create table if not exists public.diarias_reembolsos (
  id                   uuid primary key default gen_random_uuid(),
  favorecido_id        uuid not null references public.payees(id),
  data                 date not null,
  valor                numeric(12,2) not null,
  descricao            text not null,
  origem               text not null default 'comprovante',
  origem_codigo        text,
  os_id                uuid references public.service_orders(id) on delete set null,
  categoria            text,
  status               text not null default 'ativo',
  criado_por           uuid,
  criado_em            timestamptz not null default now(),
  cancelado_em         timestamptz,
  cancelado_por        uuid,
  motivo_cancelamento  text,
  constraint diarias_reembolsos_valor_chk check (valor > 0),
  constraint diarias_reembolsos_descricao_chk check (char_length(descricao) between 1 and 200),
  constraint diarias_reembolsos_origem_chk check (origem in ('comprovante')),
  constraint diarias_reembolsos_codigo_chk check (origem_codigo is null or origem_codigo ~ '^CMP-[0-9]{5,}$'),
  constraint diarias_reembolsos_categoria_chk check (categoria is null or char_length(categoria) <= 100),
  constraint diarias_reembolsos_status_chk check (status in ('ativo', 'cancelado')),
  constraint diarias_reembolsos_motivo_chk check (motivo_cancelamento is null or char_length(motivo_cancelamento) <= 300),
  constraint diarias_reembolsos_cancelado_chk check ((status = 'cancelado') = (cancelado_em is not null))
);

comment on table public.diarias_reembolsos is
  'F2b: reembolso ao freelancer de despesa que ele pagou (comprovante). Só pelas funções dos comprovantes.';
comment on column public.diarias_reembolsos.data is 'O dia em que o crédito entra na conta corrente: sempre no período aberto (depois do último acerto fechado).';
comment on column public.diarias_reembolsos.origem_codigo is 'O código do comprovante (CMP-00124). Sem FK para comprovantes: o financeiro não lê comprovantes.';

create index if not exists diarias_reembolsos_por_pessoa
  on public.diarias_reembolsos (favorecido_id, data) where status = 'ativo';

alter table public.diarias_reembolsos enable row level security;
revoke all on table public.diarias_reembolsos from public, anon, authenticated;
grant select on table public.diarias_reembolsos to authenticated;
grant all on table public.diarias_reembolsos to service_role;
drop policy if exists diarias_reembolsos_ler on public.diarias_reembolsos;
create policy diarias_reembolsos_ler on public.diarias_reembolsos
  for select to authenticated using (public.pode_ver_folha((select auth.uid())));

-- ---------------------------------------------------------------------------------------------
-- 1b. A divisão do pagamento do técnico entre diárias e reembolso (resposta 4 do dono; as funções
--     moram na seção 9)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.diarias_pagamentos_divididos (
  id            uuid primary key default gen_random_uuid(),
  favorecido_id uuid not null references public.payees(id),
  anotacao_id   uuid references public.anotacoes_do_extrato(id) on delete set null,
  payable_id    uuid references public.payables(id) on delete set null,
  reembolsos    uuid[] not null,
  partes        jsonb not null default '[]'::jsonb,
  status        text not null default 'pendente',
  motivo        text,
  criado_por    uuid,
  criado_em     timestamptz not null default now(),
  aplicada_em   timestamptz,
  desfeita_em   timestamptz,
  -- bolso do sócio: sem linha do banco não há divisao_id; as contas ao sócio das partes de REEMBOLSO
  -- (a divisão vale enquanto todas valem; a das diárias não conta)
  lancamentos   uuid[],
  -- a última tentativa da manutenção que não conseguiu aplicar a pendente (mês fechado, erro): as
  -- outras passam na frente e ela espera 1 h
  tentada_em    timestamptz,
  constraint diarias_pagamentos_divididos_reembolsos_chk check (cardinality(reembolsos) between 1 and 50),
  constraint diarias_pagamentos_divididos_partes_chk check (jsonb_typeof(partes) = 'array' and octet_length(partes::text) <= 4096),
  constraint diarias_pagamentos_divididos_status_chk check (status in ('pendente', 'aplicada', 'desfeita')),
  constraint diarias_pagamentos_divididos_motivo_chk check (motivo is null or char_length(motivo) <= 200),
  constraint diarias_pagamentos_divididos_aplicada_chk check (status <> 'aplicada' or aplicada_em is not null),
  constraint diarias_pagamentos_divididos_desfeita_chk check (status <> 'desfeita' or desfeita_em is not null)
);
comment on table public.diarias_pagamentos_divididos is
  'Resposta 4 do dono (11/10/2026): o pagamento ao técnico dividido entre "Diárias de freelancers" e o reembolso de despesas pagas pelo técnico (categoria de cada comprovante). pendente = Pix anotado (divide quando a linha for aprovada); aplicada = partes gravadas; desfeita = juntada de volta ou o lançamento caiu. Só pelas funções; o financeiro lê (pode_ver_folha).';
create unique index if not exists diarias_pagamentos_divididos_um_por_lancamento
  on public.diarias_pagamentos_divididos (payable_id) where status = 'aplicada';
create unique index if not exists diarias_pagamentos_divididos_um_por_anotacao
  on public.diarias_pagamentos_divididos (anotacao_id) where status = 'pendente';
create index if not exists diarias_pagamentos_divididos_por_pessoa
  on public.diarias_pagamentos_divididos (favorecido_id) where status <> 'desfeita';

alter table public.diarias_pagamentos_divididos enable row level security;
revoke all on table public.diarias_pagamentos_divididos from public, anon, authenticated;
grant select on table public.diarias_pagamentos_divididos to authenticated;
grant all on table public.diarias_pagamentos_divididos to service_role;
drop policy if exists diarias_pagamentos_divididos_ler on public.diarias_pagamentos_divididos;
create policy diarias_pagamentos_divididos_ler on public.diarias_pagamentos_divididos
  for select to authenticated using (public.pode_ver_folha((select auth.uid())));

-- A divisão ainda quita os reembolsos dela? Pendente (o Pix anotado) sim; aplicada enquanto o lançamento
-- vale — no bolso do sócio, enquanto TODAS as contas ao sócio das partes de reembolso valem (cancelar a
-- do reembolso devolve os reembolsos ao "em aberto"; cancelar só a das diárias não).
create or replace function public._diarias_divisao_viva(p_status text, p_payable uuid, p_lancamentos uuid[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_status = 'pendente' then true
    when p_status is distinct from 'aplicada' then false
    when coalesce(cardinality(p_lancamentos), 0) > 0 then
      not exists (select 1 from unnest(p_lancamentos) l
                   where not exists (select 1 from public.payables p where p.id = l and p.status <> 'cancelled'))
    else exists (select 1 from public.payables p where p.id = p_payable and p.status <> 'cancelled') end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 2. Colunas novas
-- ---------------------------------------------------------------------------------------------
alter table public.comprovantes
  add column if not exists reembolso_id uuid references public.diarias_reembolsos(id) on delete set null;
comment on column public.comprovantes.reembolso_id is 'F2b: o crédito de reembolso nas Diárias que este CMP gravou (técnico com diária pagou a compra).';
create index if not exists comprovantes_reembolso on public.comprovantes (reembolso_id) where reembolso_id is not null;

alter table public.acertos_diarias
  add column if not exists reembolsos numeric(12,2) not null default 0;
comment on column public.acertos_diarias.reembolsos is 'F2b: os reembolsos de despesas pagas pelo freelancer (comprovantes) dentro do período do acerto.';

-- ---------------------------------------------------------------------------------------------
-- 3. A trava: reembolso dentro de acerto fechado não entra, não muda e não sai (a mesma do dia)
-- ---------------------------------------------------------------------------------------------
create or replace function public._reembolso_em_acerto_fechado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nome text;
  v_acerto record;
  v_linha record;
begin
  for v_linha in
    select * from (values (case when tg_op = 'INSERT' then null else old.favorecido_id end,
                           case when tg_op = 'INSERT' then null else old.data end,
                           case when tg_op = 'INSERT' then null else old.status end),
                          (case when tg_op = 'DELETE' then null else new.favorecido_id end,
                           case when tg_op = 'DELETE' then null else new.data end,
                           case when tg_op = 'DELETE' then null else new.status end)) x(favorecido, data, status)
     where x.favorecido is not null and x.status = 'ativo'
  loop
    select a.numero, a.de, a.ate into v_acerto from public.acertos_diarias a
     where a.favorecido_id = v_linha.favorecido and a.status = 'fechado' and v_linha.data between a.de and a.ate
     order by a.ate desc limit 1;
    if v_acerto.numero is not null then
      select p.name into v_nome from public.payees p where p.id = v_linha.favorecido;
      raise exception 'O reembolso de % de % está no acerto nº % (% a %), já fechado. Para mudar, reabra o acerto em Financeiro › Diárias.',
        to_char(v_linha.data, 'DD/MM'), v_nome, lpad(v_acerto.numero::text, 4, '0'),
        to_char(v_acerto.de, 'DD/MM'), to_char(v_acerto.ate, 'DD/MM');
    end if;
  end loop;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists trg_reembolso_em_acerto_fechado on public.diarias_reembolsos;
create trigger trg_reembolso_em_acerto_fechado
  before insert or update or delete on public.diarias_reembolsos
  for each row execute function public._reembolso_em_acerto_fechado();

-- ---------------------------------------------------------------------------------------------
-- 4. O dia do crédito: o da compra, mas nunca antes do início da conta corrente nem dentro de um
--    acerto já fechado ("entra no próximo acerto")
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_reembolso_data(p_favorecido uuid, p_data date)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(p_data,
                  (select p.conta_corrente_desde from public.payees p where p.id = p_favorecido),
                  (select max(a.ate) + 1 from public.acertos_diarias a
                    where a.favorecido_id = p_favorecido and a.status = 'fechado'));
$$;

-- ---------------------------------------------------------------------------------------------
-- 5. _conta_corrente_linhas: corpo de 20261006200000 IGUAL + o ramo "reembolso" (crédito: entra em
--    "trabalhado"; o saldo corrido trabalhado − pago já soma)
-- ---------------------------------------------------------------------------------------------
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
         p.description || coalesce(' (inclui reembolso de despesas pagas pelo técnico: ' || public._brl(dv.reembolsos) || ')', ''),
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
  union all
  -- Pix/débito ANOTADO para ele que ainda não virou lançamento (decisão do dono, 06/10/2026: já
  -- desconta). Esperando a linha do banco, ou já casado com ela e esperando a aprovação. Quando o
  -- lançamento existe, ele entra pela parte de cima e esta linha sai — nunca os dois. Linha casada
  -- que foi RECUSADA na fila não conta: o dono disse que não era aquilo.
  select a.data_prevista, 'pagamento'::text, a.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric, a.valor,
         coalesce(a.descricao, 'Pix anotado')
           || coalesce(' (inclui reembolso de despesas pagas pelo técnico: ' || public._brl(dva.reembolsos) || ')', ''),
         'Anotado — aguardando o banco',
         a.categoria, null::text, '[]'::jsonb, a.criada_em, true
    from public.anotacoes_do_extrato a
    join fav on fav.id = a.favorecido_id
    left join lateral (
      select sum(r.valor) as reembolsos
        from public.diarias_pagamentos_divididos d
        join public.diarias_reembolsos r on r.id = any (d.reembolsos)
       where d.anotacao_id = a.id and d.status = 'pendente') dva on true
   where a.sentido = 'debit' and a.data_prevista >= fav.desde
     and (a.status = 'aguardando'
          or (a.status = 'aplicada' and a.bank_transaction_id is not null
              and not exists (select 1 from public.payables p
                               where p.bank_transaction_id = a.bank_transaction_id and p.status <> 'cancelled')
              and not exists (select 1 from public.finance_review_queue q
                               where q.bank_transaction_id = a.bank_transaction_id and q.status = 'rejected')))
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
   where r.status = 'ativo' and r.data >= fav.desde;
$$;

-- ---------------------------------------------------------------------------------------------
-- 6. conta_corrente_freelancer: corpo de 20261006200000 IGUAL + "trabalhado" só dos dias,
--    "reembolsos" à parte, saldo_final = anterior + trabalhado + reembolsos − pago
-- ---------------------------------------------------------------------------------------------
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
  v_reemb numeric;
  v_pago numeric;
  v_aguardando numeric;
  v_final numeric;
  v_dias_tudo numeric;
  v_pago_tudo numeric;
begin
  select id, name, conta_corrente_desde, saldo_anterior into v_fav
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
             order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id
             rows between unbounded preceding and current row) as saldo,
           row_number() over (order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id) as ordem
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
         coalesce(sum(o.trabalhado) filter (where o.tipo = 'dia'), 0),
         coalesce(sum(o.trabalhado) filter (where o.tipo = 'reembolso'), 0),
         coalesce(sum(o.pago), 0),
         coalesce(sum(o.pago) filter (where o.aguardando), 0)
    into v_linhas, v_dias, v_trab, v_reemb, v_pago, v_aguardando
    from o;

  v_final := v_anterior + v_trab + v_reemb - v_pago;

  select coalesce(sum(l.fracao) filter (where l.tipo = 'dia'), 0), coalesce(sum(l.pago), 0)
    into v_dias_tudo, v_pago_tudo
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data <= v_ate;

  return jsonb_build_object(
    'favorecido', jsonb_build_object('id', v_fav.id, 'nome', v_fav.name,
                                     'desde', v_fav.conta_corrente_desde, 'saldo_inicial', v_fav.saldo_anterior,
                                     'diaria', v_perfil.valor_diaria),
    'atalho', p_atalho,
    'de', case when v_de = date '1900-01-01' then null else v_de end,
    'ate', case when v_ate = date '9999-12-31' then null else v_ate end,
    'saldo_anterior', round(v_anterior, 2),
    'linhas', v_linhas,
    'dias', v_dias,
    'trabalhado', round(v_trab, 2),
    'reembolsos', round(v_reemb, 2),
    'pago', round(v_pago, 2),
    'pago_aguardando_banco', round(v_aguardando, 2),
    'saldo_final', round(v_final, 2),
    'estado', public._estado_do_saldo(v_final, v_dias_tudo, v_pago_tudo)
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 7. resumo_freelancers: corpo de 20261006200000 IGUAL + "reembolsos" por pessoa e no total
-- ---------------------------------------------------------------------------------------------
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
    select distinct p.id, p.name
      from public.payees p
      join public.work_profiles wp on wp.payee_id = p.id and wp.modo_pagamento = 'diaria'
     where p.active
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
      'desde', c -> 'favorecido' -> 'desde',
      'de', c -> 'de', 'ate', c -> 'ate',
      'dias', c -> 'dias', 'trabalhado', c -> 'trabalhado', 'reembolsos', c -> 'reembolsos', 'pago', c -> 'pago',
      'pago_aguardando_banco', c -> 'pago_aguardando_banco',
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

-- ---------------------------------------------------------------------------------------------
-- 8. fechar_acerto_diarias: corpo de 20261006220000 IGUAL + a foto ganha "reembolsos", o resumo
--    mostra "· reembolso de despesas pagas pelo técnico R$ X" antes dos vales e a simulação lista os itens
-- ---------------------------------------------------------------------------------------------
create or replace function public.fechar_acerto_diarias(
  p_favorecido_id uuid,
  p_ate date default null,
  p_simular boolean default false,
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
  v_ultimo record;
  v_de date;
  v_ate date := coalesce(p_ate, public._hoje_brt());
  c jsonb;
  v_aguardando numeric;
  v_vales jsonb;
  v_reemb_itens jsonb;
  v_id uuid;
  v_numero integer;
  v_resumo text;
begin
  if v_autor is null and not coalesce(p_simular, false) then raise exception 'Diga quem está fechando o acerto.'; end if;
  select id, name, conta_corrente_desde into v_fav from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;
  if v_ate > public._hoje_brt() then raise exception 'Acerto no futuro (%): feche até hoje.', to_char(v_ate, 'DD/MM/YYYY'); end if;

  select numero, ate into v_ultimo from public.acertos_diarias
   where favorecido_id = p_favorecido_id and status = 'fechado' order by ate desc limit 1;
  v_de := coalesce(v_ultimo.ate + 1, v_fav.conta_corrente_desde,
                   (select min(l.data) from public._conta_corrente_linhas(p_favorecido_id) l), v_ate);
  if v_de > v_ate then
    raise exception 'Nada a fechar: o acerto nº % de % já vai até %.', lpad(v_ultimo.numero::text, 4, '0'), v_fav.name, to_char(v_ultimo.ate, 'DD/MM');
  end if;

  c := public.conta_corrente_freelancer(p_favorecido_id, v_de, v_ate, p_autor);
  if jsonb_array_length(c -> 'linhas') = 0 and (c ->> 'saldo_anterior')::numeric = 0 then
    raise exception 'Nenhum dia nem pagamento de % entre % e %: nada a fechar.', v_fav.name, to_char(v_de, 'DD/MM'), to_char(v_ate, 'DD/MM');
  end if;
  v_aguardando := coalesce((c ->> 'pago_aguardando_banco')::numeric, 0);
  select coalesce(jsonb_agg(jsonb_build_object('data', x ->> 'data', 'valor', (x ->> 'pago')::numeric, 'descricao', x ->> 'descricao',
                                               'aguardando', coalesce((x ->> 'aguardando')::boolean, false))), '[]'::jsonb)
    into v_vales
    from jsonb_array_elements(c -> 'linhas') x where x ->> 'tipo' = 'pagamento';
  select coalesce(jsonb_agg(jsonb_build_object('data', x ->> 'data', 'valor', (x ->> 'trabalhado')::numeric,
                                               'descricao', x ->> 'descricao', 'codigo', x ->> 'conta')), '[]'::jsonb)
    into v_reemb_itens
    from jsonb_array_elements(c -> 'linhas') x where x ->> 'tipo' = 'reembolso';

  v_resumo := v_fav.name || ' · ' || to_char(v_de, 'DD/MM') || ' a ' || to_char(v_ate, 'DD/MM')
    || ' · ' || replace(rtrim(to_char((c ->> 'dias')::numeric, 'FM9999990.99'), '.'), '.', ',')
    || ' diária(s) ' || public._brl((c ->> 'trabalhado')::numeric)
    || case when coalesce((c ->> 'reembolsos')::numeric, 0) <> 0
            then ' · reembolso de despesas pagas pelo técnico ' || public._brl((c ->> 'reembolsos')::numeric) else '' end
    || ' · vales ' || public._brl((c ->> 'pago')::numeric)
    || case when (c ->> 'saldo_anterior')::numeric <> 0 then ' · saldo anterior ' || public._brl((c ->> 'saldo_anterior')::numeric) else '' end
    || ' · a pagar ' || public._brl((c ->> 'saldo_final')::numeric);

  if coalesce(p_simular, false) then
    return jsonb_build_object('ok', true, 'simulacao', true, 'favorecido', v_fav.name, 'de', v_de, 'ate', v_ate,
      'saldo_anterior', (c ->> 'saldo_anterior')::numeric, 'dias', (c ->> 'dias')::numeric,
      'trabalhado', (c ->> 'trabalhado')::numeric, 'pago_no_periodo', (c ->> 'pago')::numeric,
      'reembolsos', coalesce((c ->> 'reembolsos')::numeric, 0), 'reembolsos_itens', v_reemb_itens,
      'valor_do_acerto', (c ->> 'saldo_final')::numeric, 'pago_aguardando_banco', v_aguardando,
      'vales', v_vales, 'resumo', v_resumo);
  end if;

  insert into public.acertos_diarias (favorecido_id, de, ate, saldo_anterior, dias, trabalhado, reembolsos, pago_no_periodo,
                                      valor_do_acerto, criado_por)
  values (p_favorecido_id, v_de, v_ate, (c ->> 'saldo_anterior')::numeric, (c ->> 'dias')::numeric,
          (c ->> 'trabalhado')::numeric, coalesce((c ->> 'reembolsos')::numeric, 0), (c ->> 'pago')::numeric,
          (c ->> 'saldo_final')::numeric, v_autor)
  returning id, numero into v_id, v_numero;

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_numero, 'favorecido', v_fav.name, 'de', v_de, 'ate', v_ate,
    'valor_do_acerto', (c ->> 'saldo_final')::numeric, 'pago_aguardando_banco', v_aguardando,
    'message', 'Acerto nº ' || lpad(v_numero::text, 4, '0') || ' fechado: ' || v_resumo
      || '. Os dias até ' || to_char(v_ate, 'DD/MM') || ' ficam travados.'
      || case when v_aguardando > 0 then ' Atenção: ' || public._brl(v_aguardando) || ' dos vales são Pix lançados à mão que o banco ainda não confirmou.' else '' end);
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 9. Pagamento do técnico dividido entre diárias e reembolso (resposta 4 do dono, 11/10/2026: "sim,
--    mas eu sempre vou sinalizar o que é o que"). Ao registrar o pagamento, o sistema PROPÕE a divisão
--    pelos reembolsos em aberto do técnico (os do acerto primeiro, por data, somando enquanto cabe no
--    valor) e o dono confirma ou desmarca. A parte do reembolso vai para a categoria de cada CMP (sem
--    categoria ativa: "Outras despesas" — "Reembolso de despesas de campo" não existe e criar categoria
--    é dado); o resto fica em "Diárias de freelancers". Na mesma linha do banco, pelo payables.divisao_id
--    que já existe (as partes somam a linha; gatilho payables_divisao_confere).
--    Tabela à parte (e não coluna em diarias_reembolsos): a trava _reembolso_em_acerto_fechado recusa
--    qualquer UPDATE no reembolso de acerto fechado — e o pagamento vem justamente depois de fechar.
-- ---------------------------------------------------------------------------------------------
-- (a tabela diarias_pagamentos_divididos nasce na seção 1b: a conta corrente, abaixo, já a lê)

-- Os reembolsos de um técnico que nenhum pagamento vivo quitou: ativos e fora de divisão pendente ou
-- aplicada cujo lançamento segue valendo (p_ignorar = a divisão que está sendo refeita).
create or replace function public._diarias_reembolsos_em_aberto(p_favorecido uuid, p_ignorar uuid default null)
returns setof public.diarias_reembolsos
language sql
stable
security definer
set search_path = ''
as $$
  select r.*
    from public.diarias_reembolsos r
   where r.favorecido_id = p_favorecido and r.status = 'ativo'
     and not exists (select 1 from public.diarias_pagamentos_divididos d
                      where r.id = any (d.reembolsos) and d.id is distinct from p_ignorar
                        and public._diarias_divisao_viva(d.status, d.payable_id, d.lancamentos));
$$;

-- A categoria do reembolso: a do CMP, se é uma categoria de despesa ativa; senão "Outras despesas".
create or replace function public._diarias_categoria_do_reembolso(p_categoria text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select f.name from public.financial_categories f
                    where lower(f.name) = lower(btrim(p_categoria)) and f.type = 'payable' and coalesce(f.active, false)
                    order by (f.name = btrim(p_categoria)) desc
                    limit 1),
                  'Outras despesas');
$$;

-- Confere os reembolsos escolhidos (do técnico, ativos, em aberto, sem repetir, somando até o valor) e
-- devolve a divisão: {"diarias","reembolsos","partes":[{"categoria","valor","codigos"}],"codigos"}.
-- As partes: Diárias primeiro (se sobra), depois uma por categoria, na ordem dos comprovantes.
create or replace function public._diarias_partes(p_favorecido uuid, p_valor numeric, p_reembolsos uuid[], p_ignorar uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := coalesce((select array_agg(distinct x) from unnest(p_reembolsos) x where x is not null), '{}'::uuid[]);
  v_achados integer;
  v_soma numeric;
  v_partes jsonb;
  v_codigos jsonb;
begin
  if p_valor is null or p_valor <= 0 then
    raise exception 'O valor do pagamento precisa ser maior que zero.' using errcode = '22023';
  end if;
  if cardinality(v_ids) > 50 then
    raise exception 'São reembolsos demais para um pagamento só (no máximo 50).' using errcode = '22023';
  end if;
  if cardinality(v_ids) = 0 then
    return jsonb_build_object('diarias', round(p_valor, 2), 'reembolsos', 0,
                              'partes', jsonb_build_array(jsonb_build_object('categoria', 'Diárias de freelancers',
                                                                             'valor', round(p_valor, 2), 'codigos', '[]'::jsonb)),
                              'codigos', '[]'::jsonb);
  end if;
  select count(*), coalesce(sum(r.valor), 0) into v_achados, v_soma
    from public._diarias_reembolsos_em_aberto(p_favorecido, p_ignorar) r where r.id = any (v_ids);
  if v_achados <> cardinality(v_ids) then
    raise exception 'Algum reembolso escolhido não é deste técnico, foi cancelado ou já foi pago em outro pagamento. Abra a proposta de novo.'
      using errcode = '22023';
  end if;
  if v_soma > p_valor + 0.005 then
    raise exception 'Os reembolsos escolhidos (%) passam do valor pago (%): desmarque algum.', public._brl(v_soma), public._brl(p_valor)
      using errcode = '22023';
  end if;
  with r as (
    select x.id, x.valor, x.origem_codigo, x.data, x.criado_em,
           public._diarias_categoria_do_reembolso(x.categoria) as categoria
      from public.diarias_reembolsos x where x.id = any (v_ids)
  ), cat as (
    select r.categoria, sum(r.valor) as valor, min(r.data) as primeira, min(r.criado_em) as criado,
           jsonb_agg(r.origem_codigo order by r.data, r.criado_em, r.id) filter (where r.origem_codigo is not null) as codigos
      from r group by r.categoria
  )
  select coalesce(jsonb_agg(jsonb_build_object('categoria', cat.categoria, 'valor', round(cat.valor, 2),
                                               'codigos', coalesce(cat.codigos, '[]'::jsonb))
                            order by cat.primeira, cat.criado, cat.categoria), '[]'::jsonb)
    into v_partes from cat;
  select coalesce(jsonb_agg(x.origem_codigo order by x.data, x.criado_em, x.id) filter (where x.origem_codigo is not null), '[]'::jsonb)
    into v_codigos from public.diarias_reembolsos x where x.id = any (v_ids);
  if p_valor - v_soma > 0.005 then
    v_partes := jsonb_build_array(jsonb_build_object('categoria', 'Diárias de freelancers', 'valor', round(p_valor - v_soma, 2),
                                                     'codigos', '[]'::jsonb)) || v_partes;
  end if;
  return jsonb_build_object('diarias', round(greatest(p_valor - v_soma, 0), 2), 'reembolsos', round(v_soma, 2),
                            'partes', v_partes, 'codigos', v_codigos);
end $$;

-- A divisão como as telas e o assistente a leem (sem os códigos por parte).
create or replace function public._diarias_divisao_saida(p_id uuid, p_status text, p_div jsonb)
returns jsonb
language sql
immutable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_id, 'status', p_status,
    'diarias', coalesce((p_div->>'diarias')::numeric, 0),
    'reembolsos', coalesce((p_div->>'reembolsos')::numeric, 0),
    'partes', coalesce((select jsonb_agg(jsonb_build_object('categoria', e->>'categoria', 'valor', (e->>'valor')::numeric) order by o)
                          from jsonb_array_elements(coalesce(p_div->'partes', '[]'::jsonb)) with ordinality as t(e, o)), '[]'::jsonb));
$$;

-- O rótulo do reembolso nos lançamentos (o mesmo do recibo e do extrato da pessoa)
create or replace function public._diarias_rotulo_do_reembolso(p_codigos jsonb)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select 'Reembolso de despesas pagas pelo técnico'
         || coalesce(' (' || (select string_agg(x, ', ' order by o)
                                from jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) with ordinality as t(x, o)) || ')', '');
$$;

-- O miolo: divide (ou junta de volta, com p_reembolsos vazio) o pagamento das Diárias que está numa linha
-- do banco ou do Caixa. Principal = Diárias X (com X = 0, o principal fica com a categoria do primeiro
-- reembolso); uma parte por categoria (divisao_id = principal, mesmo favorecido, linha e OS). p_divisao =
-- a divisão pendente do Pix anotado que agora se aplica. Erro de regra = 22023 (nada muda).
create or replace function public._diarias_dividir(p_payable uuid, p_reembolsos uuid[], p_autor uuid, p_divisao uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r public.payables%rowtype;
  v_raiz uuid;
  v_atual record;
  v_total numeric;
  v_linha numeric;
  v_div jsonb;
  v_partes_antes jsonb;
  v_principal jsonb;
  v_parte jsonb;
  v_ids uuid[] := coalesce((select array_agg(distinct x) from unnest(p_reembolsos) x where x is not null), '{}'::uuid[]);
  v_hoje text := to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');
  v_nome text;
  v_novo uuid;
  v_status text;
  v_i integer := 0;
begin
  select coalesce(p.divisao_id, p.id) into v_raiz from public.payables p where p.id = p_payable;
  if v_raiz is null then
    raise exception 'Lançamento não encontrado.' using errcode = '22023';
  end if;
  -- sempre o principal primeiro, depois as partes (a mesma ordem de _juntar_divisao e do pró-labore)
  select * into r from public.payables p where p.id = v_raiz for update;
  perform 1 from public.payables p where p.divisao_id = v_raiz and p.status <> 'cancelled' for update;
  if r.status is distinct from 'paid' then
    raise exception 'Só se divide um pagamento já pago (este está %).', coalesce(r.status, '?') using errcode = '22023';
  end if;
  if r.bank_transaction_id is null then
    raise exception 'O pagamento não está numa linha do banco ou do Caixa: não há o que dividir.' using errcode = '22023';
  end if;
  if r.payee_id is null or not exists (select 1 from public.work_profiles wp
                                        where wp.payee_id = r.payee_id and wp.modo_pagamento = 'diaria') then
    raise exception 'O lançamento não é de um freelancer de diária.' using errcode = '22023';
  end if;
  if public.periodo_esta_fechado(r.issue_date) then
    raise exception 'O mês % está fechado. Reabra-o em Financeiro › Conciliação para dividir este pagamento.',
      to_char(r.issue_date, 'MM/YYYY') using errcode = '22023';
  end if;
  select d.id, d.partes into v_atual from public.diarias_pagamentos_divididos d
   where d.payable_id = v_raiz and d.status = 'aplicada' for update;
  if v_atual.id is null
     and (exists (select 1 from public.payables x where x.divisao_id = v_raiz and x.status <> 'cancelled')
          or r.expense_category is distinct from 'Diárias de freelancers') then
    raise exception 'O lançamento não está em "Diárias de freelancers" (ou foi dividido de outro jeito): não divido por aqui.'
      using errcode = '22023';
  end if;
  -- o pagamento registrado à parte (o casamento com o extrato grava "Conciliado com o extrato…" em
  -- payments): dividir mudaria o valor do lançamento por baixo do pagamento dele — o mesmo critério do
  -- separar_pro_labore (vai inteiro)
  if exists (select 1 from public.payments pm
              join public.payables x on x.id = pm.payable_id
             where pm.status = 'confirmed' and (x.id = v_raiz or x.divisao_id = v_raiz) and x.status <> 'cancelled') then
    raise exception 'Este pagamento tem baixa registrada à parte (conciliação com o extrato): não divido por aqui, para o valor do lançamento não mudar por baixo dela.'
      using errcode = '22023';
  end if;
  select sum(x.amount) into v_total from public.payables x
   where (x.id = v_raiz or x.divisao_id = v_raiz) and x.status <> 'cancelled';
  select abs(t.amount) into v_linha from public.bank_transactions t where t.id = r.bank_transaction_id;
  if v_linha is null or abs(v_total - v_linha) > 0.005 then
    raise exception 'O pagamento (%) não bate com a linha do banco (%): não divido.', public._brl(v_total), public._brl(v_linha)
      using errcode = '22023';
  end if;
  -- a divisão que está sendo refeita (ou a pendente que agora se aplica) não conta como "já paga"
  v_div := public._diarias_partes(r.payee_id, v_total, v_ids, coalesce(v_atual.id, p_divisao));
  select p.name into v_nome from public.payees p where p.id = r.payee_id;
  select jsonb_agg(jsonb_build_object('id', x.id, 'categoria', x.expense_category, 'valor', x.amount) order by x.divisao_id nulls first, x.created_at, x.id)
    into v_partes_antes
    from public.payables x where (x.id = v_raiz or x.divisao_id = v_raiz) and x.status <> 'cancelled';

  -- 1. junta de volta (o pagamento inteiro em Diárias), se já estava dividido
  update public.payables x
     set status = 'cancelled', bank_transaction_id = null,
         notes = btrim(coalesce(x.notes, '') || ' [' || v_hoje || '] Parte juntada de volta ao pagamento das diárias.')
   where x.divisao_id = v_raiz and x.status <> 'cancelled';
  update public.payables x
     set amount = v_total, paid_amount = v_total, balance_amount = 0, expense_category = 'Diárias de freelancers'
   where x.id = v_raiz;
  if v_atual.id is not null then
    update public.diarias_pagamentos_divididos d
       set status = 'desfeita', desfeita_em = now(),
           motivo = case when cardinality(v_ids) = 0 then 'juntado de volta' else 'refeito com outros reembolsos' end
     where d.id = v_atual.id;
  end if;

  if cardinality(v_ids) = 0 then
    v_status := case when v_atual.id is null then 'nenhuma' else 'desfeita' end;
    if v_atual.id is not null then
      insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, valor, detalhe, antes, depois)
      values ('dividiu_pagamento_diarias', p_autor, r.bank_transaction_id, v_raiz, v_total,
              left('O pagamento das diárias de ' || coalesce(v_nome, 'freelancer') || ' voltou a ser um lançamento só ('
                   || public._brl(v_total) || ' em Diárias de freelancers).', 300),
              jsonb_build_object('partes', v_partes_antes), jsonb_build_object('partes', v_div->'partes'));
    end if;
    set constraints public.payables_divisao_confere immediate;
    set constraints public.payables_divisao_confere deferred;
    return jsonb_build_object('payable_id', v_raiz,
                              'divisao', public._diarias_divisao_saida(v_atual.id, v_status, v_div));
  end if;

  -- 2. divide: o principal fica com a primeira parte (Diárias, ou o primeiro reembolso se não sobra)
  v_principal := v_div->'partes'->0;
  update public.payables x
     set amount = (v_principal->>'valor')::numeric, paid_amount = (v_principal->>'valor')::numeric, balance_amount = 0,
         expense_category = v_principal->>'categoria',
         notes = btrim(coalesce(x.notes, '') || ' [' || v_hoje || '] Pagamento de ' || public._brl(v_total)
                       || ' dividido: ' || public._brl((v_div->>'diarias')::numeric) || ' de diárias e '
                       || public._brl((v_div->>'reembolsos')::numeric) || ' de '
                       || lower(public._diarias_rotulo_do_reembolso(v_div->'codigos')) || '.')
   where x.id = v_raiz;
  for v_parte in select e from jsonb_array_elements(v_div->'partes') with ordinality as t(e, o) where o > 1 order by o loop
    v_i := v_i + 1;
    insert into public.payables (
      description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
      supplier_id, supplier_name, payee_id, beneficiario_id, bank_transaction_id, origin, payment_method, currency,
      cost_center_id, linked_service_order_id, notes, divisao_id)
    values (
      left(public._diarias_rotulo_do_reembolso(v_parte->'codigos') || ' · ' || coalesce(v_nome, 'freelancer'), 200),
      r.issue_date, r.due_date, (v_parte->>'valor')::numeric, (v_parte->>'valor')::numeric, 0, 'paid', v_parte->>'categoria',
      r.supplier_id, r.supplier_name, r.payee_id, r.beneficiario_id, r.bank_transaction_id, r.origin, r.payment_method, r.currency,
      r.cost_center_id, r.linked_service_order_id,
      '[' || v_hoje || '] Parte do pagamento de ' || public._brl(v_total) || ' às diárias: '
        || lower(public._diarias_rotulo_do_reembolso(v_parte->'codigos')) || '.',
      v_raiz)
    returning id into v_novo;
  end loop;

  if p_divisao is not null then
    update public.diarias_pagamentos_divididos d
       set status = 'aplicada', aplicada_em = now(), payable_id = v_raiz, partes = v_div->'partes', reembolsos = v_ids
     where d.id = p_divisao
    returning d.id into v_novo;
  else
    insert into public.diarias_pagamentos_divididos (favorecido_id, payable_id, reembolsos, partes, status, criado_por, aplicada_em)
    values (r.payee_id, v_raiz, v_ids, v_div->'partes', 'aplicada', p_autor, now())
    returning id into v_novo;
  end if;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, valor, detalhe, antes, depois)
  values ('dividiu_pagamento_diarias', p_autor, r.bank_transaction_id, v_raiz, v_total,
          left('Pagamento de ' || public._brl(v_total) || ' a ' || coalesce(v_nome, 'freelancer') || ' dividido: '
               || public._brl((v_div->>'diarias')::numeric) || ' em Diárias de freelancers e '
               || public._brl((v_div->>'reembolsos')::numeric) || ' de '
               || lower(public._diarias_rotulo_do_reembolso(v_div->'codigos')) || '.'
               || case when p_autor is null then ' Rotina automática.' else '' end, 300),
          jsonb_build_object('partes', v_partes_antes), jsonb_build_object('partes', v_div->'partes'));
  -- a conferência das partes (soma = linha) roda aqui, para o erro cair em quem chamou
  set constraints public.payables_divisao_confere immediate;
  set constraints public.payables_divisao_confere deferred;
  return jsonb_build_object('payable_id', v_raiz, 'divisao', public._diarias_divisao_saida(v_novo, 'aplicada', v_div));
end $$;

-- R. proposta_de_divisao_do_pagamento: o que o sistema proporia para um pagamento deste valor (só lê).
create or replace function public.proposta_de_divisao_do_pagamento(p_favorecido_id uuid, p_valor numeric, p_autor uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_em_aberto jsonb;
  v_propostos uuid[] := '{}';
  v_soma numeric := 0;
  v_div jsonb;
  x record;
begin
  select p.id, p.name into v_fav from public.payees p where p.id = p_favorecido_id;
  if v_fav.id is null then
    raise exception 'Freelancer não encontrado entre os favorecidos.' using errcode = '22023';
  end if;
  if p_valor is null or p_valor <= 0 then
    raise exception 'O valor do pagamento precisa ser maior que zero.' using errcode = '22023';
  end if;
  -- os do acerto (fechado) primeiro, por data; somando enquanto cabe no valor
  for x in
    select r.id, r.valor,
           (select a.numero from public.acertos_diarias a
             where a.favorecido_id = r.favorecido_id and a.status = 'fechado' and r.data between a.de and a.ate
             order by a.ate desc limit 1) as acerto
      from public._diarias_reembolsos_em_aberto(p_favorecido_id, null) r
     order by 3 nulls last, r.data, r.criado_em, r.id
  loop
    exit when v_soma + x.valor > p_valor + 0.005;
    v_soma := v_soma + x.valor;
    v_propostos := v_propostos || x.id;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'codigo', r.origem_codigo, 'data', r.data, 'valor', r.valor,
           'categoria', public._diarias_categoria_do_reembolso(r.categoria),
           'descricao', r.descricao, 'acerto', r.acerto)
           order by r.acerto nulls last, r.data, r.criado_em, r.id), '[]'::jsonb)
    into v_em_aberto
    from (select y.*, (select a.numero from public.acertos_diarias a
                        where a.favorecido_id = y.favorecido_id and a.status = 'fechado' and y.data between a.de and a.ate
                        order by a.ate desc limit 1) as acerto
            from public._diarias_reembolsos_em_aberto(p_favorecido_id, null) y) r;
  v_div := public._diarias_partes(p_favorecido_id, p_valor, v_propostos, null);
  return jsonb_build_object(
    'favorecido', jsonb_build_object('id', v_fav.id, 'nome', v_fav.name),
    'valor', round(p_valor, 2),
    'em_aberto', v_em_aberto,
    'propostos', to_jsonb(v_propostos),
    'reembolsos', (v_div->>'reembolsos')::numeric,
    'diarias', (v_div->>'diarias')::numeric,
    'partes', public._diarias_divisao_saida(null, null, v_div)->'partes');
end $$;

-- R. registrar_pagamento_do_freelancer: o pagamento ao técnico já com a divisão (o mesmo caminho de
--    hoje para a forma): Pix → anotar_transacao em Diárias (favorecido = ele) + divisão PENDENTE ligada à
--    anotação (divide quando a linha for aprovada, venha a aprovação da tela, do assistente ou da regra
--    por CPF); dinheiro → lancar_no_caixa('caixa') + divisão aplicada na hora; bolso do sócio → um
--    lancar_no_caixa('socio') por parte (sem linha do banco não há divisao_id: cada parte vira uma conta
--    ao sócio, com o técnico de beneficiário). Reembolso de outro técnico, cancelado, já pago ou que passa
--    do valor = 22023 (nada gravado).
create or replace function public.registrar_pagamento_do_freelancer(
  p_favorecido_id uuid, p_valor numeric, p_data date, p_forma text, p_socio_id uuid, p_reembolsos uuid[],
  p_descricao text, p_autor uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_ids uuid[] := coalesce((select array_agg(distinct x) from unnest(p_reembolsos) x where x is not null), '{}'::uuid[]);
  v_div jsonb;
  v_desc text;
  v_r jsonb;
  v_d jsonb;
  v_divisao uuid;
  v_anot uuid;
  v_pay uuid;
  v_primeiro uuid;
  v_lancs uuid[] := '{}';
  v_parte jsonb;
  v_msg text;
begin
  if v_autor is null then
    raise exception 'Diga quem está registrando o pagamento.' using errcode = '42501';
  end if;
  select p.id, p.name, p.active into v_fav from public.payees p where p.id = p_favorecido_id;
  if v_fav.id is null or not coalesce(v_fav.active, false)
     or not exists (select 1 from public.work_profiles wp where wp.payee_id = p_favorecido_id and wp.modo_pagamento = 'diaria') then
    raise exception 'Freelancer de diária não encontrado (ou desativado).' using errcode = '22023';
  end if;
  if p_forma is null or p_forma not in ('pix', 'dinheiro', 'socio') then
    raise exception 'Como foi pago: pix, dinheiro ou socio.' using errcode = '22023';
  end if;
  -- a data não dita: o Pix vai sem ela (anotar_transacao anota com a janela larga, D-3..D+7 — "paguei o
  -- Roberto" sem dizer quando pode ser o Pix de anteontem); dinheiro e bolso do sócio, hoje (o padrão do
  -- lancar_no_caixa)
  if p_data > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'Pagamento no futuro não se lança: lance quando pagar.' using errcode = '22023';
  end if;
  if p_forma = 'socio' and (p_socio_id is null
                            or not exists (select 1 from public.payees s where s.id = p_socio_id and s.kind = 'socio')) then
    raise exception 'Diga qual sócio pagou, para o reembolso ficar no nome dele.' using errcode = '22023';
  end if;
  v_div := public._diarias_partes(p_favorecido_id, p_valor, v_ids, null);
  v_desc := left(coalesce(nullif(btrim(coalesce(p_descricao, '')), ''),
                          'Pagamento de diárias — ' || split_part(btrim(v_fav.name), ' ', 1)), 200);

  if p_forma = 'pix' then
    v_r := public.anotar_transacao('saida', p_valor, p_data, null, null, null, p_favorecido_id, null,
                                   'Diárias de freelancers', null, v_desc, v_autor);
    if not coalesce((v_r->>'ok')::boolean, false) then
      -- a rota não anotou (linha já lançada, ambígua…): nada de divisão; a mensagem dela diz o que fazer
      return jsonb_build_object('ok', false, 'forma', p_forma, 'anotacao_id', null, 'payable_id', v_r->'lancamento_id',
        'divisao', public._diarias_divisao_saida(null, 'nenhuma', public._diarias_partes(p_favorecido_id, p_valor, '{}', null)),
        'message', coalesce(v_r->>'message', 'O Pix não foi anotado.')
                   || case when cardinality(v_ids) > 0 and coalesce((v_r->>'ja_lancada')::boolean, false)
                           then ' Para separar o reembolso, use "Dividir" na linha desse pagamento nas Diárias.' else '' end);
    end if;
    v_anot := (v_r->>'id')::uuid;
    if cardinality(v_ids) > 0 then
      insert into public.diarias_pagamentos_divididos (favorecido_id, anotacao_id, reembolsos, partes, status, criado_por)
      values (p_favorecido_id, v_anot, v_ids, v_div->'partes', 'pendente', v_autor)
      returning id into v_divisao;
    end if;
    v_msg := coalesce(v_r->>'message', 'Pix anotado.')
             || case when v_divisao is not null
                     then ' Divido quando a linha do banco for aprovada: Diárias ' || public._brl((v_div->>'diarias')::numeric)
                          || ' · Reembolso de despesas pagas pelo técnico ' || public._brl((v_div->>'reembolsos')::numeric) || '.'
                     else '' end;
    -- o que a anotação diz além do ok (a tela avisa por 15 s quando trocou uma anotação igual: o caso do
    -- dono de 06/10/2026, "dois R$ 100 ao Roberto", um sumiu)
    return jsonb_build_object('ok', true, 'forma', p_forma, 'anotacao_id', v_anot, 'payable_id', null,
      'divisao', public._diarias_divisao_saida(v_divisao, case when v_divisao is null then 'nenhuma' else 'pendente' end, v_div),
      'message', v_msg,
      'substituidas', coalesce((v_r->>'substituidas')::integer, 0),
      'falta_quem', coalesce((v_r->>'falta_quem')::boolean, false),
      'outra_contraparte', v_r->'outra_contraparte');

  elsif p_forma = 'dinheiro' then
    v_r := public.lancar_no_caixa('saida', p_valor, v_desc, p_data, 'Diárias de freelancers', null, p_favorecido_id, null,
                                  null, 'caixa', null, v_autor);
    v_pay := (v_r->>'lancamento_id')::uuid;
    if cardinality(v_ids) > 0 then
      v_d := public._diarias_dividir(v_pay, v_ids, v_autor, null);
    end if;
    return jsonb_build_object('ok', true, 'forma', p_forma, 'anotacao_id', null, 'payable_id', v_pay,
      'divisao', coalesce(v_d->'divisao', public._diarias_divisao_saida(null, 'nenhuma', v_div)),
      'message', coalesce(v_r->>'message', 'Lançado no Caixa.')
                 || case when v_d is not null
                         then ' Dividido: Diárias ' || public._brl((v_div->>'diarias')::numeric)
                              || ' · Reembolso de despesas pagas pelo técnico ' || public._brl((v_div->>'reembolsos')::numeric) || '.'
                         else '' end);
  end if;

  -- bolso do sócio: uma conta ao sócio por parte (o técnico de beneficiário). A divisão guarda as contas
  -- das partes de REEMBOLSO (vale enquanto todas valem): cancelar a do reembolso devolve os reembolsos ao
  -- "em aberto". Sem linha do banco não há "Desfazer a divisão" pela tela: cancelam-se as contas.
  for v_parte in select e from jsonb_array_elements(v_div->'partes') with ordinality as t(e, o) order by o loop
    v_r := public.lancar_no_caixa('saida', (v_parte->>'valor')::numeric,
                                  case when v_parte->>'categoria' = 'Diárias de freelancers' and jsonb_array_length(v_parte->'codigos') = 0
                                       then v_desc
                                       else left(public._diarias_rotulo_do_reembolso(v_parte->'codigos') || ' · ' || v_fav.name, 200) end,
                                  p_data, v_parte->>'categoria', null, p_favorecido_id, null, null, 'socio', p_socio_id, v_autor);
    v_primeiro := coalesce(v_primeiro, (v_r->>'lancamento_id')::uuid);
    if jsonb_array_length(coalesce(v_parte->'codigos', '[]'::jsonb)) > 0 or v_parte->>'categoria' <> 'Diárias de freelancers' then
      v_lancs := v_lancs || (v_r->>'lancamento_id')::uuid;
    end if;
  end loop;
  if cardinality(v_ids) > 0 then
    insert into public.diarias_pagamentos_divididos (favorecido_id, payable_id, reembolsos, partes, status, criado_por, aplicada_em,
                                                     lancamentos)
    values (p_favorecido_id, v_primeiro, v_ids, v_div->'partes', 'aplicada', v_autor, now(), v_lancs)
    returning id into v_divisao;
  end if;
  return jsonb_build_object('ok', true, 'forma', p_forma, 'anotacao_id', null, 'payable_id', v_primeiro,
    'divisao', public._diarias_divisao_saida(v_divisao, case when v_divisao is null then 'nenhuma' else 'aplicada' end, v_div),
    'message', case when v_divisao is null then 'Lançado como reembolso a pagar ao sócio.'
                    else 'Lançado como reembolso a pagar ao sócio, em ' || jsonb_array_length(v_div->'partes')
                         || ' contas: Diárias ' || public._brl((v_div->>'diarias')::numeric)
                         || ' · Reembolso de despesas pagas pelo técnico ' || public._brl((v_div->>'reembolsos')::numeric) || '.' end);
end $$;

-- R. dividir_pagamento_do_freelancer: o Pix que veio do banco (aprovado na tela, pelo assistente ou pela
--    regra por CPF) sem registro dividido: "Dividir: diárias e reembolso". p_reembolsos vazio = junta de
--    volta (a divisão fica desfeita).
create or replace function public.dividir_pagamento_do_freelancer(p_payable_id uuid, p_reembolsos uuid[], p_autor uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_d jsonb;
  v_div jsonb;
begin
  if v_autor is null then
    raise exception 'Diga quem está dividindo o pagamento.' using errcode = '42501';
  end if;
  v_d := public._diarias_dividir(p_payable_id, coalesce(p_reembolsos, '{}'::uuid[]), v_autor, null);
  v_div := v_d->'divisao';
  return jsonb_build_object('ok', true, 'forma', null, 'anotacao_id', null, 'payable_id', v_d->'payable_id',
    'divisao', v_div,
    'message', case v_div->>'status'
                 when 'aplicada' then 'Pagamento dividido: Diárias ' || public._brl((v_div->>'diarias')::numeric)
                                      || ' · Reembolso de despesas pagas pelo técnico ' || public._brl((v_div->>'reembolsos')::numeric) || '.'
                 when 'desfeita' then 'Divisão desfeita: o pagamento voltou inteiro para Diárias de freelancers.'
                 else 'Nada a dividir: o pagamento continua inteiro em Diárias de freelancers.' end);
end $$;

-- A manutenção do cron (até 2 min depois da aprovação): a divisão pendente do Pix anotado se aplica
-- quando a anotação foi aplicada e a linha dela ganhou o lançamento do técnico em Diárias; anotação
-- cancelada (ou lançamento em outra categoria/favorecido) = desfeita. Os reembolsos cancelados depois
-- (o CMP cancelado) saem dela; sem nenhum, desfeita. Erro de regra (22023: outro já pagou o reembolso,
-- o valor não bate com a linha…) = desfeita com o motivo, nunca tentar de novo a cada 2 min; mês
-- fechado ou erro de sistema = espera 1 h e as outras passam na frente (20 travadas não param a fila).
-- A aplicada cujo lançamento caiu (desfeito ou cancelado no Extrato) também fica desfeita: os reembolsos
-- voltam a ficar em aberto.
create or replace function public._diarias_aplicar_divisoes_pendentes(p_limite integer default 20)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  d record;
  a record;
  p record;
  v_ativos uuid[];
  v_estado text;
  v_msg text;
  v_n integer := 0;
begin
  for d in
    select x.id, x.favorecido_id, x.anotacao_id, x.reembolsos, x.criado_por
      from public.diarias_pagamentos_divididos x
      left join public.anotacoes_do_extrato an on an.id = x.anotacao_id
     where x.status = 'pendente'
       -- a que ainda espera o banco não tem o que fazer (e não ocupa a vez das outras)
       and (an.id is null or an.status <> 'aguardando')
       and (x.tentada_em is null or x.tentada_em < now() - interval '1 hour')
     order by x.tentada_em nulls first, x.criado_em, x.id
     limit greatest(coalesce(p_limite, 20), 1)
     for update of x skip locked
  loop
    begin
      select an.status, an.bank_transaction_id into a from public.anotacoes_do_extrato an where an.id = d.anotacao_id;
      select coalesce(array_agg(r.id order by r.data, r.criado_em, r.id), '{}'::uuid[]) into v_ativos
        from public.diarias_reembolsos r where r.id = any (d.reembolsos) and r.status = 'ativo';
      if a.status is null or a.status = 'cancelada' then
        update public.diarias_pagamentos_divididos x set status = 'desfeita', desfeita_em = now(), motivo = 'a anotação do Pix foi cancelada'
         where x.id = d.id;
        v_n := v_n + 1;
      elsif cardinality(v_ativos) = 0 then
        update public.diarias_pagamentos_divididos x
           set status = 'desfeita', desfeita_em = now(), motivo = 'os reembolsos desta divisão foram cancelados'
         where x.id = d.id;
        v_n := v_n + 1;
      elsif a.status = 'aplicada' and a.bank_transaction_id is not null then
        select y.id, y.payee_id, y.expense_category, y.status, y.issue_date into p from public.payables y
         where y.bank_transaction_id = a.bank_transaction_id and y.status <> 'cancelled' and y.divisao_id is null
         order by y.created_at, y.id limit 1;
        if p.id is null then
          null;   -- a linha ainda espera a aprovação
        elsif p.payee_id is distinct from d.favorecido_id or p.expense_category is distinct from 'Diárias de freelancers'
              or p.status <> 'paid' then
          update public.diarias_pagamentos_divididos x
             set status = 'desfeita', desfeita_em = now(), motivo = 'a linha foi lançada de outro jeito (favorecido ou categoria)'
           where x.id = d.id;
          v_n := v_n + 1;
        elsif public.periodo_esta_fechado(p.issue_date) then
          -- o dono reabre o mês e ela se aplica; até lá, espera e não segura a fila
          update public.diarias_pagamentos_divididos x set tentada_em = now() where x.id = d.id;
        else
          perform public._diarias_dividir(p.id, v_ativos, d.criado_por, d.id);
          v_n := v_n + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      if v_estado = '22023' then
        update public.diarias_pagamentos_divididos x
           set status = 'desfeita', desfeita_em = now(), motivo = left('não deu para dividir: ' || v_msg, 200)
         where x.id = d.id;
        v_n := v_n + 1;
      else
        update public.diarias_pagamentos_divididos x set tentada_em = now() where x.id = d.id;
        raise warning 'diárias: aplicar a divisão do pagamento falhou: %', v_estado;
      end if;
    end;
  end loop;
  update public.diarias_pagamentos_divididos x
     set status = 'desfeita', desfeita_em = now(), motivo = 'o lançamento foi desfeito ou cancelado'
   where x.status = 'aplicada'
     and not public._diarias_divisao_viva(x.status, x.payable_id, x.lancamentos);
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. Privilégios: os de hoje nas redefinidas; a trava e os helpers sem grant para ninguém; as RPCs da
--     divisão para authenticated e service_role (o cargo é conferido dentro, por _autor_do_financeiro)
-- ---------------------------------------------------------------------------------------------
revoke all on function public._reembolso_em_acerto_fechado() from public, anon, authenticated, service_role;
revoke all on function public._comprovante_reembolso_data(uuid, date) from public, anon, authenticated, service_role;
revoke all on function public._conta_corrente_linhas(uuid) from public, anon, authenticated;
grant execute on function public._conta_corrente_linhas(uuid) to service_role;
revoke all on function public.conta_corrente_freelancer(uuid, date, date, uuid, text) from public, anon;
revoke all on function public.resumo_freelancers(date, date, uuid, text) from public, anon;
revoke all on function public.fechar_acerto_diarias(uuid, date, boolean, uuid) from public, anon;
grant execute on function public.conta_corrente_freelancer(uuid, date, date, uuid, text) to authenticated, service_role;
grant execute on function public.resumo_freelancers(date, date, uuid, text) to authenticated, service_role;
grant execute on function public.fechar_acerto_diarias(uuid, date, boolean, uuid) to authenticated, service_role;
revoke all on function public._diarias_divisao_viva(text, uuid, uuid[]) from public, anon, authenticated, service_role;
revoke all on function public._diarias_reembolsos_em_aberto(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public._diarias_categoria_do_reembolso(text) from public, anon, authenticated, service_role;
revoke all on function public._diarias_partes(uuid, numeric, uuid[], uuid) from public, anon, authenticated, service_role;
revoke all on function public._diarias_divisao_saida(uuid, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public._diarias_rotulo_do_reembolso(jsonb) from public, anon, authenticated, service_role;
revoke all on function public._diarias_dividir(uuid, uuid[], uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public._diarias_aplicar_divisoes_pendentes(integer) from public, anon, authenticated, service_role;
revoke all on function public.proposta_de_divisao_do_pagamento(uuid, numeric, uuid) from public, anon, authenticated;
revoke all on function public.registrar_pagamento_do_freelancer(uuid, numeric, date, text, uuid, uuid[], text, uuid) from public, anon, authenticated;
revoke all on function public.dividir_pagamento_do_freelancer(uuid, uuid[], uuid) from public, anon, authenticated;
grant execute on function public.proposta_de_divisao_do_pagamento(uuid, numeric, uuid) to authenticated, service_role;
grant execute on function public.registrar_pagamento_do_freelancer(uuid, numeric, date, text, uuid, uuid[], text, uuid) to authenticated, service_role;
grant execute on function public.dividir_pagamento_do_freelancer(uuid, uuid[], uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova (só catálogo; nenhum dado escrito)
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.diarias_reembolsos'::regclass) then
    raise exception 'RLS desligada em diarias_reembolsos';
  end if;
  if has_table_privilege('anon', 'public.diarias_reembolsos', 'select') or has_table_privilege('anon', 'public.diarias_reembolsos', 'insert')
     or has_table_privilege('anon', 'public.diarias_reembolsos', 'update') or has_table_privilege('anon', 'public.diarias_reembolsos', 'delete') then
    raise exception 'anon alcança diarias_reembolsos';
  end if;
  if not has_table_privilege('authenticated', 'public.diarias_reembolsos', 'select')
     or has_table_privilege('authenticated', 'public.diarias_reembolsos', 'insert')
     or has_table_privilege('authenticated', 'public.diarias_reembolsos', 'update')
     or has_table_privilege('authenticated', 'public.diarias_reembolsos', 'delete') then
    raise exception 'authenticated deve só ler diarias_reembolsos';
  end if;
  if not has_table_privilege('service_role', 'public.diarias_reembolsos', 'insert') then
    raise exception 'service_role não alcança diarias_reembolsos';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'diarias_reembolsos') <> 1
     or not exists (select 1 from pg_policies
                     where schemaname = 'public' and tablename = 'diarias_reembolsos' and policyname = 'diarias_reembolsos_ler'
                       and cmd = 'SELECT' and roles = array['authenticated']::name[]
                       and qual like '%pode_ver_folha%') then
    raise exception 'policy de diarias_reembolsos diferente da prevista';
  end if;
  if has_column_privilege('anon', 'public.comprovantes', 'reembolso_id', 'select')
     or has_column_privilege('authenticated', 'public.comprovantes', 'reembolso_id', 'update') then
    raise exception 'comprovantes.reembolso_id aberta';
  end if;
  if has_column_privilege('anon', 'public.acertos_diarias', 'reembolsos', 'select')
     or not has_column_privilege('authenticated', 'public.acertos_diarias', 'reembolsos', 'select') then
    raise exception 'acertos_diarias.reembolsos com privilégio diferente da tabela';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_reembolso_em_acerto_fechado'
                    and tgrelid = 'public.diarias_reembolsos'::regclass and tgenabled <> 'D') then
    raise exception 'trava do reembolso em acerto fechado ausente';
  end if;
  -- a divisão do pagamento (resposta 4): RLS, anon nada, authenticated só lê (pode_ver_folha)
  if not (select relrowsecurity from pg_class where oid = 'public.diarias_pagamentos_divididos'::regclass) then
    raise exception 'RLS desligada em diarias_pagamentos_divididos';
  end if;
  if has_table_privilege('anon', 'public.diarias_pagamentos_divididos', 'select')
     or has_table_privilege('anon', 'public.diarias_pagamentos_divididos', 'insert')
     or not has_table_privilege('authenticated', 'public.diarias_pagamentos_divididos', 'select')
     or has_table_privilege('authenticated', 'public.diarias_pagamentos_divididos', 'insert')
     or has_table_privilege('authenticated', 'public.diarias_pagamentos_divididos', 'update')
     or has_table_privilege('authenticated', 'public.diarias_pagamentos_divididos', 'delete')
     or not has_table_privilege('service_role', 'public.diarias_pagamentos_divididos', 'insert') then
    raise exception 'privilégios de diarias_pagamentos_divididos diferentes dos previstos';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'diarias_pagamentos_divididos') <> 1
     or not exists (select 1 from pg_policies
                     where schemaname = 'public' and tablename = 'diarias_pagamentos_divididos'
                       and policyname = 'diarias_pagamentos_divididos_ler' and cmd = 'SELECT'
                       and roles = array['authenticated']::name[] and qual like '%pode_ver_folha%') then
    raise exception 'policy de diarias_pagamentos_divididos diferente da prevista';
  end if;
  foreach v_f in array array['public._diarias_divisao_viva(text, uuid, uuid[])',
                             'public._diarias_reembolsos_em_aberto(uuid, uuid)', 'public._diarias_categoria_do_reembolso(text)',
                             'public._diarias_partes(uuid, numeric, uuid[], uuid)', 'public._diarias_divisao_saida(uuid, text, jsonb)',
                             'public._diarias_rotulo_do_reembolso(jsonb)', 'public._diarias_dividir(uuid, uuid[], uuid, uuid)',
                             'public._diarias_aplicar_divisoes_pendentes(integer)'] loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute')
       or has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'helper da divisão do pagamento exposto: %', v_f;
    end if;
  end loop;
  foreach v_f in array array['public.proposta_de_divisao_do_pagamento(uuid, numeric, uuid)',
                             'public.registrar_pagamento_do_freelancer(uuid, numeric, date, text, uuid, uuid[], text, uuid)',
                             'public.dividir_pagamento_do_freelancer(uuid, uuid[], uuid)'] loop
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception 'RPC da divisão do pagamento aberta para anon: %', v_f;
    end if;
    if not has_function_privilege('authenticated', v_f, 'execute') or not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'RPC da divisão do pagamento sem authenticated/service_role: %', v_f;
    end if;
  end loop;
  -- as rotas reaproveitadas (o Pix dividido usa a divisão do pró-labore): assinatura igual
  if to_regprocedure('public._juntar_divisao(uuid, text, uuid)') is null
     or not exists (select 1 from pg_trigger where tgname = 'payables_divisao_confere' and tgrelid = 'public.payables'::regclass) then
    raise exception 'a divisão de pagamento do ERP (_juntar_divisao, payables_divisao_confere) mudou';
  end if;
  foreach v_f in array array['public._reembolso_em_acerto_fechado()', 'public._comprovante_reembolso_data(uuid, date)'] loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute')
       or has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'helper do reembolso exposto: %', v_f;
    end if;
  end loop;
  -- as redefinidas mantêm os grants de hoje
  if has_function_privilege('anon', 'public._conta_corrente_linhas(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public._conta_corrente_linhas(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public._conta_corrente_linhas(uuid)', 'execute') then
    raise exception '_conta_corrente_linhas com grants diferentes dos de hoje (só service_role)';
  end if;
  foreach v_f in array array['public.conta_corrente_freelancer(uuid, date, date, uuid, text)',
                             'public.resumo_freelancers(date, date, uuid, text)',
                             'public.fechar_acerto_diarias(uuid, date, boolean, uuid)'] loop
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception 'função das Diárias aberta para anon: %', v_f;
    end if;
    if not has_function_privilege('authenticated', v_f, 'execute') or not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'função das Diárias sem authenticated/service_role: %', v_f;
    end if;
    if not (select prosecdef from pg_proc where oid = v_f::regprocedure) then
      raise exception 'função das Diárias deixou de ser security definer: %', v_f;
    end if;
  end loop;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011301000', 'diarias_reembolsos')
on conflict do nothing;
