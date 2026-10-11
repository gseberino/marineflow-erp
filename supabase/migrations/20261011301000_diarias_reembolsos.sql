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
--     e fechar_acerto_diarias (grava a foto e mostra "· reembolsos R$ X"; a simulação lista os itens).
--     Corpo de 20261006200000 / 20261006220000 IGUAL + só o diff da F2b.
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
  select p.issue_date, 'pagamento'::text, p.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric,
         case when p.payee_id = fav.id then coalesce(p.paid_amount, 0) else p.amount end,
         p.description,
         case when p.payee_id = fav.id
              then coalesce(bc.label, case when p.payment_method = 'cash' then 'Caixa (dinheiro)' end, 'Sem conta ligada')
              else 'Bolso de ' || coalesce(soc.name, 'sócio') end,
         p.expense_category, null::text, '[]'::jsonb, p.created_at, false
    from public.payables p
    join fav on (p.payee_id = fav.id or p.beneficiario_id = fav.id)
    left join public.payees soc on soc.id = p.payee_id
    left join public.bank_transactions bt on bt.id = p.bank_transaction_id
    left join public.bank_connections bc on bc.id = bt.bank_connection_id
   where p.status <> 'cancelled' and p.issue_date >= fav.desde
     and (case when p.payee_id = fav.id then coalesce(p.paid_amount, 0) else p.amount end) > 0
  union all
  -- Pix/débito ANOTADO para ele que ainda não virou lançamento (decisão do dono, 06/10/2026: já
  -- desconta). Esperando a linha do banco, ou já casado com ela e esperando a aprovação. Quando o
  -- lançamento existe, ele entra pela parte de cima e esta linha sai — nunca os dois. Linha casada
  -- que foi RECUSADA na fila não conta: o dono disse que não era aquilo.
  select a.data_prevista, 'pagamento'::text, a.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric, a.valor,
         coalesce(a.descricao, 'Pix anotado'),
         'Anotado — aguardando o banco',
         a.categoria, null::text, '[]'::jsonb, a.criada_em, true
    from public.anotacoes_do_extrato a
    join fav on fav.id = a.favorecido_id
   where a.sentido = 'debit' and a.data_prevista >= fav.desde
     and (a.status = 'aguardando'
          or (a.status = 'aplicada' and a.bank_transaction_id is not null
              and not exists (select 1 from public.payables p
                               where p.bank_transaction_id = a.bank_transaction_id and p.status <> 'cancelled')
              and not exists (select 1 from public.finance_review_queue q
                               where q.bank_transaction_id = a.bank_transaction_id and q.status = 'rejected')))
  union all
  -- F2b: o reembolso de despesa que ele pagou (comprovante). Crédito dele: entra como "trabalhado";
  -- "conta" é o código do CMP. Cancelado não conta.
  select r.data, 'reembolso'::text, r.id, null::text, null::numeric, null::numeric, null::numeric, null::numeric,
         r.valor, 0::numeric, r.descricao, r.origem_codigo, r.categoria, null::text,
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
--    mostra "· reembolsos R$ X" antes dos vales e a simulação lista os itens
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
            then ' · reembolsos ' || public._brl((c ->> 'reembolsos')::numeric) else '' end
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
-- 9. Privilégios: os de hoje nas redefinidas; a trava e o helper sem grant para ninguém
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
