-- Prova da base da Agenda de Produção, Fase 3 (pacote P1): os parâmetros e os modos novos, as colunas, as 4 tabelas e
-- o gatilho da entrega (migration 20261026100000).
-- bancada: depende de 20261026100000
--
--   A  estrutura e portas: as 4 tabelas com RLS; policies só de leitura e TO authenticated; anon sem privilégio;
--      authenticated só lê; service_role escreve; os 16 DEFAULTs de agenda_config (modo_diaria nascendo 'sombra') e a
--      linha com modo_diaria 'desligado' enquanto a migration de dado não veio; comissao_config com o pagamento
--      desligado; os gatilhos; critica gerada com 'diaria', no mesmo lugar e com as duas constraints; as colunas e as FKs
--   B  cada CHECK (e índice único, PK, FK) das 4 tabelas, os 16 de agenda_config, os 3 de agenda_vigia_rodadas, o da
--      entrega e as 4 listas fechadas ampliadas recusam uma linha errada; os valores novos entram; a cobrança de que
--      nenhum ficou sem caso
--   C  a diária que diverge é crítica: critica por tipo; ação crítica de diária só com a pergunta respondida em ligado
--   D  a entrega só pela porta, em todos os modos: UPDATE e INSERT fora da porta recusados com a frase; pela porta entra;
--      valor igual e outra coluna passam
--   E  o registro: a mensagem à equipe não se apaga e só muda no estado, na fila e na resposta; a carona da pergunta;
--      as FKs novas ON DELETE SET NULL (apagar a diária ou o favorecido não esbarra no "não muda"); as cobranças da
--      ação não mudam; a rodada antiga é da vigia
--   F  RLS de verdade: admin e financeiro leem; o técnico nada; anon não lê; ninguém escreve
--   G  portas das funções: gatilhos sem grant; só _so_entrega_pela_porta é security definer; search_path fixo
--   H  (só na bancada) a fixture-fase3 roda e dá o que os pacotes seguintes esperam; os gatilhos de produção da conclusão
--      (coerência do recebível, período fechado, estado do pagamento, vencimento na entrega, sinal pago) e a trava do
--      acerto fechado estão ligados
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261026100000
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase3_base.sql
--   Seguro em produção: as pessoas, os logins, as OS e as linhas de teste ("TESTE AG3", OS-TESTE-AG3-*) só são
--   inseridos, nada real é tocado (o "hoje" vem de agenda.hoje e a chave agenda.porta é local à transação); termina em
--   ROLLBACK. A seção H só roda na bancada (fora dela, PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Executa um comando e diz que porta o recusou: o nome do CHECK, do índice único ou da FK; 'aceitou' quando entrou (e
-- desfaz, para não sujar os casos seguintes); 'erro <estado>: <mensagem>' para o resto.
create function pg_temp.recusa(p_sql text) returns text language plpgsql as $f$
declare
  v_nome text; v_estado text; v_msg text;
begin
  begin
    execute p_sql;
    raise exception using errcode = 'P0001', message = '__aceitou__';
  exception when others then
    get stacked diagnostics v_nome = constraint_name, v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg = '__aceitou__' then return 'aceitou'; end if;
    if v_estado in ('23514', '23505', '23503', '23502', '23P01') then return coalesce(nullif(v_nome, ''), v_estado); end if;
    return 'erro ' || v_estado || ': ' || v_msg;
  end;
end $f$;

-- Executa de verdade e devolve o erro ('<sqlstate> <mensagem>'), ou 'sem erro'.
create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_estado text; v_msg text;
begin
  execute p_sql;
  return 'sem erro';
exception when others then
  get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  return v_estado || ' ' || v_msg;
end $f$;

-- Um resultado numa lista jsonb (para os blocos que se desfazem no fim: a linha de _resultado iria junto).
create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

-- Executa p_sql (que devolve um valor) como o papel p_papel com o login p_uid (o JWT do Supabase): o resultado em
-- texto, ou 'erro <estado>: <mensagem>'. Volta ao dono do teste no fim, dê certo ou não.
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- ── H. A bancada: a fixture da Fase 3 e os gatilhos de produção que a conclusão atravessa ───────────────
-- Roda ANTES da montagem e desfaz tudo no fim: as OS de teste em andamento entrariam na carteira que a vigia publica.
do $h$
declare
  c_rob   constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao  constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_ven   constant uuid := '05000000-0000-4000-8000-000000000069';
  c_len   constant uuid := '05000000-0000-4000-8000-000000000074';
  c_mp    constant uuid := '05000000-0000-4000-8000-000000000095';
  v text; v_n int; x record;
  v_res jsonb := '[]'::jsonb;   -- os resultados ficam aqui: o bloco abaixo é desfeito no fim, a variável não
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('H a fixture da Fase 3 e os gatilhos da conclusão', true,
      'PULADO: sem agenda_teste.fase3 (só na bancada: scripts/bancada-agenda/rodar.mjs)');
    return;
  end if;

  begin
    execute current_setting('agenda_teste.fase3');

    -- A semana publicada (a vigia de qui 29/10 16:30, com a proposta e a vigia ligadas).
    select count(*) into v_n from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada');
    v_res := pg_temp.ok(v_res, 'H1 a fixture publica a semana de 03 a 06/11: 4 OS na publicação, meio-dias em vigor, o Nelson perguntado',
      v_n >= 12
      and (select count(*) from public.agenda_acoes a where a.tipo = 'publicar' and a.origem = 'vigia' and a.executada) = 4
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = c_ven and a.estado = 'publicada'
                     and a.payee_id = c_rob and a.dia = date '2026-11-03')
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = c_len and a.estado = 'publicada')
      and exists (select 1 from public.agenda_perguntas q where q.tipo = 'nao_cabe' and q.estado = 'aberta' and q.critica
                     and q.service_order_id = '05000000-0000-4000-8000-000000000112')
      and (select modo_proposta = 'ligado' and modo_vigia = 'ligado' and modo_equipe = 'desligado' and modo_diaria = 'desligado'
             from public.agenda_config),
      v_n || ' meio-dias em vigor');

    v_res := pg_temp.ok(v_res, 'H2 a equipe: Roberto R$ 180 com telefone e na rotina (pela regra); João R$ 150, sem telefone, fora',
      (select valor_diaria from public.work_profiles where id = 'cc000000-0000-4000-8000-000000000002') = 180
      and (select valor_diaria from public.work_profiles where id = 'cc000000-0000-4000-8000-000000000003') = 150
      and (select phone from public.payees where id = c_rob) = '5547900000001'
      and (select phone from public.payees where id = c_joao) is null
      and (select recebe_rotina and incluido_por = 'regra' from public.agenda_equipe_contato where payee_id = c_rob)
      and not exists (select 1 from public.agenda_equipe_contato where payee_id = c_joao), null);

    v_res := pg_temp.ok(v_res, 'H3 Lenine: a condição 50/50, mão de obra 4.560, nenhum recebível vivo e "não pago"',
      (select p.label = '50% de sinal + 50% na entrega' and so.labor_cost_total = 4560 and so.parts_cost_total = 0
              and so.payment_status = 'unpaid'
         from public.service_orders so join public.payment_condition_presets p on p.id = so.payment_condition_preset_id
        where so.id = c_len)
      and not exists (select 1 from public.receivables r where r.service_order_id = c_len and r.status <> 'cancelled'), null);

    v_res := pg_temp.ok(v_res, 'H4 Vanderlei: o sinal pago (4.500) e o saldo na entrega pendente (2.800), com a cobrança; "pago em parte"',
      (select so.payment_status = 'partially_paid' and so.labor_cost_total = 5600 and so.parts_cost_total = 2005.40
         from public.service_orders so where so.id = c_ven)
      and (select count(*) from public.receivables r where r.service_order_id = c_ven and r.is_deposit and r.status = 'paid'
              and r.amount = 4500) = 1
      and (select count(*) from public.receivables r where r.service_order_id = c_ven and not r.is_deposit
              and r.status = 'pending' and r.due_on_completion and r.amount = 2800) = 1
      and exists (select 1 from public.collections c where c.receivable_id = 'd3000000-0000-4000-8000-000000000011'), null);

    -- O acerto fechado do João trava os dias dele (trg_dia_em_acerto_fechado, 20261006220000).
    v := pg_temp.erro_de($q$insert into public.work_shifts (work_profile_id, data, tipo, fracao, valor_diaria, origem, status,
                                                         registrado_por, aprovado_por, aprovado_em)
                            values ('cc000000-0000-4000-8000-000000000003', '2026-10-13', 'diaria', 1, 150, 'agente', 'aprovado',
                                    'aa000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001', now())$q$);
    v_res := pg_temp.ok(v_res, 'H5 o acerto fechado do João (29/09 a 17/10) recusa lançar diária no período, com a frase',
      v = 'P0001 O dia 13/10 de João está no acerto nº 0001 (29/09 a 17/10), já fechado. Para mudar, reabra o acerto em Financeiro › Diárias.'
      and (select status = 'fechado' and dias = 8 from public.acertos_diarias where favorecido_id = c_joao), v);
    v_res := pg_temp.ok(v_res, 'H6 …e um dia depois do acerto entra (seg 19/10)',
      pg_temp.erro_de($q$insert into public.work_shifts (work_profile_id, data, tipo, fracao, valor_diaria, origem, status,
                                                      registrado_por, aprovado_por, aprovado_em)
                         values ('cc000000-0000-4000-8000-000000000003', '2026-10-19', 'diaria', 0.5, 150, 'agente', 'aprovado',
                                 'aa000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001', now())$q$) = 'sem erro',
      null);

    -- Os gatilhos de produção que a conclusão (P2) atravessa estão ligados na bancada.
    v := pg_temp.erro_de(format($q$insert into public.receivables (client_id, service_order_id, description, issue_date, due_date,
                                   amount, status, paid_amount, balance_amount) values (%L, %L, 'TESTE AG3', '2026-11-05', '2026-11-05',
                                   0, 'pending', 0, 0)$q$, 'c1000000-0000-4000-8000-000000000002', c_len));
    v_res := pg_temp.ok(v_res, 'H7 receivables_coerencia: recebível de valor zero é recusado',
      v like '23514 Recebível precisa de valor maior que zero.%', v);

    insert into public.periodos_fechados (ano, mes) values (2026, 9);
    v := pg_temp.erro_de(format($q$insert into public.receivables (client_id, service_order_id, description, issue_date, due_date,
                                   amount, status, paid_amount, balance_amount) values (%L, %L, 'TESTE AG3', '2026-09-10', '2026-09-10',
                                   10, 'pending', 0, 10)$q$, 'c1000000-0000-4000-8000-000000000002', c_len));
    v_res := pg_temp.ok(v_res, 'H8 trg_receivables_periodo_fechado: lançar em setembro fechado é recusado',
      v = 'P0001 O período de 09/2026 está fechado. Reabra-o para lançar nesta data.', v);

    -- A conclusão direta (só aqui, para provar o vencimento): o saldo na entrega e a cobrança dele passam a vencer no dia da
    -- saída; a comissão de vendedor não nasce (a OS não tem comissão).
    update public.service_orders set status = 'completed', check_out_at = timestamptz '2026-11-05 17:00-03' where id = c_ven;
    v_res := pg_temp.ok(v_res, 'H9 trg_sync_balance_due_on_completion: o saldo na entrega e a cobrança vencem no dia da saída; nada em commissions',
      (select due_date from public.receivables where id = 'd3000000-0000-4000-8000-000000000011')
        = (timestamptz '2026-11-05 17:00-03')::date
      and (select due_date from public.collections where id = 'd3000000-0000-4000-8000-000000000012')
        = (timestamptz '2026-11-05 17:00-03')::date
      and not exists (select 1 from public.commissions where service_order_id = c_ven),
      (select due_date::text from public.receivables where id = 'd3000000-0000-4000-8000-000000000011'));

    -- O sinal pago converte o orçamento que espera o sinal (on_quote_deposit_paid → handle_quote_deposit_payment).
    insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status,
                                    paid_amount, balance_amount, is_deposit)
    values ('d3000000-0000-4000-8000-000000000031', 'c1000000-0000-4000-8000-000000000008', c_mp, 'Sinal — ORÇ-00095',
            '2026-11-05', '2026-11-05', 5000, 'pending', 0, 5000, true);
    update public.receivables set status = 'paid', paid_amount = 5000, balance_amount = 0
     where id = 'd3000000-0000-4000-8000-000000000031';
    select so.status, so.quote_status, so.converted_to_os_at is not null as convertida into x
      from public.service_orders so where so.id = c_mp;
    v_res := pg_temp.ok(v_res, 'H10 on_quote_deposit_paid: o sinal pago converte o orçamento que esperava o sinal',
      x.status = 'approved' and x.quote_status = 'approved' and x.convertida, format('%s %s %s', x.status, x.quote_status, x.convertida));

    v_res := pg_temp.ok(v_res, 'H11 as funções da paridade e da equipe estão na bancada ("ok" é concordância; o telefone normaliza)',
      public._e_concordancia('OK') and not public._e_concordancia('não vou')
      and public.wa_normalize_phone('(47) 90000-0001') = '5547900000001'
      and to_regprocedure('public.registrar_diaria(uuid,date,text,uuid[],text,numeric,numeric,numeric,text,uuid)') is not null
      and to_regprocedure('public.registrar_conferencia_do_freelancer(text,text,uuid)') is not null,
      public.wa_normalize_phone('(47) 90000-0001'));

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(v_res) e;
end
$h$;

-- O dia de quem age: qui 05/11/2026 (a semana publicada da fixture vai de 03 a 06/11).
select set_config('agenda.hoje', '2026-11-05', true);

-- ── Montagem: logins, pessoas, OS, diárias, perguntas, ações e as linhas das tabelas novas ──────────────
-- Ids e3000000-…: 0000000000NN logins; 1NN pessoas; 2NN OS; 3NN perfis; 4NN diárias; 5NN perguntas; 6NN ações;
-- 7NN mensagens; 8NN alocações.
do $m$
declare
  v_barco   uuid := (select id from public.vessels where client_id is not null order by created_at, id limit 1);
  v_cliente uuid := (select client_id from public.vessels where id = v_barco);
begin
  if v_barco is null then raise exception 'FALHOU: nenhum barco cadastrado para montar a OS de teste'; end if;

  insert into public.app_users (id, full_name, email, role, active) values
    ('e3000000-0000-4000-8000-000000000001', 'TESTE AG3 admin', 'teste-ag3-admin@teste.invalid', 'admin', true),
    ('e3000000-0000-4000-8000-000000000002', 'TESTE AG3 técnico', 'teste-ag3-tecnico@teste.invalid', 'technician', true),
    ('e3000000-0000-4000-8000-000000000003', 'TESTE AG3 financeiro', 'teste-ag3-fin@teste.invalid', 'financial', true);

  insert into public.payees (id, name, kind, active, app_user_id) values
    ('e3000000-0000-4000-8000-000000000101', 'TESTE AG3 Roberto', 'prestador', true, 'e3000000-0000-4000-8000-000000000002'),
    ('e3000000-0000-4000-8000-000000000102', 'TESTE AG3 João', 'prestador', true, null),
    -- só a pergunta e a ação apontam para ele: apagá-lo prova o ON DELETE SET NULL (seção E)
    ('e3000000-0000-4000-8000-000000000103', 'TESTE AG3 descartável', 'prestador', true, null);

  insert into public.service_orders (id, client_id, vessel_id, service_order_number, status, quote_status, check_out_at) values
    ('e3000000-0000-4000-8000-000000000201', v_cliente, v_barco, 'OS-TESTE-AG3-1', 'completed', 'approved', timestamptz '2026-11-04 17:00-03'),
    ('e3000000-0000-4000-8000-000000000202', v_cliente, v_barco, 'OS-TESTE-AG3-2', 'in_progress', 'approved', null);

  insert into public.work_profiles (id, payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
  values ('e3000000-0000-4000-8000-000000000301', 'e3000000-0000-4000-8000-000000000101', 'diarista', 'diaria', 180, '2026-10-01');
  insert into public.work_shifts (id, work_profile_id, data, tipo, fracao, valor_diaria, origem, status, registrado_por,
                                  aprovado_por, aprovado_em) values
    ('e3000000-0000-4000-8000-000000000401', 'e3000000-0000-4000-8000-000000000301', '2026-11-03', 'diaria', 1, 180, 'agente',
     'aprovado', 'e3000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000001', now()),
    ('e3000000-0000-4000-8000-000000000402', 'e3000000-0000-4000-8000-000000000301', '2026-11-04', 'diaria', 1, 180, 'agente',
     'aprovado', 'e3000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000001', now());

  insert into public.agenda_perguntas (id, tipo, chave, texto, modo, opcoes, recomendacao, payee_id, service_order_id) values
    ('e3000000-0000-4000-8000-000000000501', 'diaria', 'diaria:teste-ag3', 'TESTE AG3: meia ou inteira?', 'ligado',
     '[{"n":1,"texto":"meia"},{"n":2,"texto":"inteira"},{"n":3,"texto":"não lançar"}]', 1,
     'e3000000-0000-4000-8000-000000000101', 'e3000000-0000-4000-8000-000000000202'),
    ('e3000000-0000-4000-8000-000000000502', 'concluir', 'concluir:teste-ag3', 'TESTE AG3: terminou?', 'sombra', '[]', null,
     'e3000000-0000-4000-8000-000000000103', 'e3000000-0000-4000-8000-000000000202'),
    ('e3000000-0000-4000-8000-000000000503', 'diaria', 'diaria:teste-ag3-sombra', 'TESTE AG3: meia ou inteira? (sombra)', 'sombra',
     '[{"n":1,"texto":"meia"},{"n":2,"texto":"inteira"}]', 1,
     'e3000000-0000-4000-8000-000000000101', 'e3000000-0000-4000-8000-000000000202');

  -- FASE 3 (P4): a diária executada pela agenda sem a confirmação do dia é recusada pelo gatilho agenda_acoes_diaria_confirmada
  -- (20261026100300); esta linha só prova o ON DELETE SET NULL da pessoa e da diária, então é a do dono (que não passa
  -- pela confirmação: é a ordem dele).
  insert into public.agenda_acoes (id, dia, executada, origem, tipo, texto, payee_id, work_shift_id, service_order_id) values
    ('e3000000-0000-4000-8000-000000000601', '2026-11-04', true, 'dono', 'diaria', 'TESTE AG3: lancei a diária do Roberto.',
     'e3000000-0000-4000-8000-000000000101', 'e3000000-0000-4000-8000-000000000402', 'e3000000-0000-4000-8000-000000000202'),
    ('e3000000-0000-4000-8000-000000000602', '2026-11-04', false, 'equipe', 'equipe', 'TESTE AG3: o descartável respondeu.',
     'e3000000-0000-4000-8000-000000000103', null, 'e3000000-0000-4000-8000-000000000202');

  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, estado) values
    ('e3000000-0000-4000-8000-000000000801', 'e3000000-0000-4000-8000-000000000202', 'e3000000-0000-4000-8000-000000000101',
     '2026-11-04', 'manha', 'publicada');

  insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por)
  values ('e3000000-0000-4000-8000-000000000101', true, 'regra');

  insert into public.agenda_equipe_mensagens (id, payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key) values
    ('e3000000-0000-4000-8000-000000000701', 'e3000000-0000-4000-8000-000000000101', '2026-11-05', 'ficha', 'sombra',
     'TESTE AG3 Roberto, amanhã: 8h no barco. Responde OK se tá certo.', timestamptz '2026-11-04 19:30-03',
     'agenda-equipe:ficha:teste-ag3:2026-11-05:sombra');

  insert into public.agenda_intervencoes_do_dono (service_order_id, dia, prevista, dita, classe, origem, trecho, autor)
  values ('e3000000-0000-4000-8000-000000000202', '2026-11-04', 'nenhuma', 'manha', 'execucao', 'conversa',
          'TESTE AG3: eu fui de manhã', 'e3000000-0000-4000-8000-000000000001');
end
$m$;

-- ── A. Estrutura e portas ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('A1 RLS ligada: %s', t),
       coalesce((select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || t)), false), null
  from unnest(array['agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config']) t;

insert into _resultado
select format('A2 policies de %s: só leitura e TO authenticated', t),
       count(p.policyname) >= 1 and coalesce(bool_and(p.roles = '{authenticated}'::name[] and p.cmd = 'SELECT'), false),
       string_agg(p.policyname || ' ' || p.cmd || ' ' || p.roles::text, '; ')
  from unnest(array['agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config']) t
  left join pg_policies p on p.schemaname = 'public' and p.tablename = t
 group by t;

insert into _resultado
select format('A3 anon sem privilégio: %s', t),
       not (has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'insert')
            or has_table_privilege('anon', 'public.' || t, 'update') or has_table_privilege('anon', 'public.' || t, 'delete')
            or has_table_privilege('anon', 'public.' || t, 'truncate')), null
  from unnest(array['agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config']) t;

insert into _resultado
select format('A4 authenticated só lê (nem apaga), service_role escreve: %s', t),
       has_table_privilege('authenticated', 'public.' || t, 'select')
       and not (has_table_privilege('authenticated', 'public.' || t, 'insert')
                or has_table_privilege('authenticated', 'public.' || t, 'update')
                or has_table_privilege('authenticated', 'public.' || t, 'delete')
                or has_table_privilege('authenticated', 'public.' || t, 'truncate'))
       and has_table_privilege('service_role', 'public.' || t, 'insert')
       and has_table_privilege('service_role', 'public.' || t, 'update'), null
  from unnest(array['agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config']) t;

insert into _resultado
select format('A5 agenda_config nasce com %s = %s', x.coluna, x.esperado),
       pg_get_expr(d.adbin, d.adrelid) = x.esperado, pg_get_expr(d.adbin, d.adrelid)
  from (values ('modo_diaria', '''sombra''::text'),
               ('equipe_janela_inicio', '''07:30:00''::time without time zone'),
               ('equipe_janela_fim', '''20:00:00''::time without time zone'),
               ('equipe_hora_ficha', '''19:30:00''::time without time zone'),
               ('equipe_hora_confirmar', '''07:45:00''::time without time zone'),
               ('equipe_silencio_ate', '''09:00:00''::time without time zone'),
               ('equipe_hora_como_foi', '''17:00:00''::time without time zone'),
               ('equipe_proativas_dia_max', '2'), ('equipe_respostas_dia_max', '4'),
               ('equipe_resposta_validade', '''14:00:00''::interval'),
               ('diaria_janela_dias', '7'), ('entrega_aviso_du', '5'), ('carona_por_os_dias', '7'),
               ('carteira_laranja_du', '5'), ('carteira_vermelho_du', '20'), ('ppc_meta', '0.70')) as x(coluna, esperado)
  left join pg_attribute a on a.attrelid = 'public.agenda_config'::regclass and a.attname = x.coluna and not a.attisdropped
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum;

-- A linha ganha os parâmetros pelo DEFAULT e o modo da diária DESLIGADO (o DEFAULT 'sombra' vem depois do add column):
-- a estrutura não muda comportamento. Depois da migration de dado (20261026101000) a linha é dela.
insert into _resultado
select 'A6 a linha de agenda_config ganhou os 15 parâmetros com o DEFAULT e modo_diaria desligado (até a migration de dado)',
       c.equipe_janela_inicio = time '07:30' and c.equipe_janela_fim = time '20:00' and c.equipe_hora_ficha = time '19:30'
       and c.equipe_hora_confirmar = time '07:45' and c.equipe_silencio_ate = time '09:00'
       and c.equipe_hora_como_foi = time '17:00' and c.equipe_proativas_dia_max = 2 and c.equipe_respostas_dia_max = 4
       and c.equipe_resposta_validade = interval '14 hours' and c.diaria_janela_dias = 7 and c.entrega_aviso_du = 5
       and c.carona_por_os_dias = 7 and c.carteira_laranja_du = 5 and c.carteira_vermelho_du = 20 and c.ppc_meta = 0.70
       and (c.modo_diaria = 'desligado'
            or exists (select 1 from supabase_migrations.schema_migrations s where s.version = '20261026101000')),
       format('modo_diaria %s, modo_equipe %s', c.modo_diaria, c.modo_equipe)
  from public.agenda_config c;

insert into _resultado
select 'A7 comissao_config: uma linha, 20%, o maior dos dois, 3 meses de teste, imposto pela alíquota com nota, pagamento desligado',
       count(*) = 1 and bool_and(c.id and c.pct = 0.200 and c.modelo = 'maior_dos_dois' and c.meses_teste = 3
                                 and c.imposto_fonte = 'aliquota_simples_com_nota' and c.pagamento = 'desligado'),
       string_agg(format('%s %s %s %s %s inicio=%s', c.pct, c.modelo, c.meses_teste, c.imposto_fonte, c.pagamento, c.inicio), '; ')
  from public.comissao_config c;

insert into _resultado
select 'A8 os gatilhos novos existem e estão ligados (a entrega no INSERT e no UPDATE OF delivered_at)',
       count(*) = 3 and bool_and(t.tgenabled = 'O')
       and bool_or(t.tgname = 'trg_so_entrega_pela_porta'
                   and pg_get_triggerdef(t.oid) like 'CREATE TRIGGER trg_so_entrega_pela_porta BEFORE INSERT OR UPDATE OF delivered_at ON public.service_orders %'),
       string_agg(t.tgname || ': ' || pg_get_triggerdef(t.oid), ' | ' order by t.tgname)
  from pg_trigger t
 where not t.tgisinternal
   and ((t.tgrelid = 'public.agenda_equipe_mensagens'::regclass
         and t.tgname in ('agenda_equipe_mensagens_nao_apaga', 'agenda_equipe_mensagens_so_responde'))
        or (t.tgrelid = 'public.service_orders'::regclass and t.tgname = 'trg_so_entrega_pela_porta'));

-- critica: SET EXPRESSION mantém a coluna no lugar (antes de chave) e as duas constraints com o mesmo nome.
insert into _resultado
select 'A9 agenda_perguntas.critica é gerada (stored), tem ''diaria'' e continua no mesmo lugar (antes de chave)',
       a.attgenerated = 's' and pg_get_expr(d.adbin, d.adrelid) like '%''diaria''%'
       and a.attnum < (select k.attnum from pg_attribute k where k.attrelid = a.attrelid and k.attname = 'chave'),
       format('attnum %s: %s', a.attnum, pg_get_expr(d.adbin, d.adrelid))
  from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica';

insert into _resultado
select 'A10 critica_tem_opcoes e critica_decidida continuam, lendo critica',
       count(*) = 2 and bool_and(pg_get_constraintdef(c.oid) like '%critica%'),
       string_agg(c.conname || ': ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname)
  from pg_constraint c
 where c.conrelid = 'public.agenda_perguntas'::regclass and c.conname in ('critica_tem_opcoes', 'critica_decidida');

insert into _resultado
select format('A11 coluna %s.%s: %s', x.tabela, x.coluna, x.tipo),
       a.attnum is not null and format_type(a.atttypid, a.atttypmod) = x.tipo and a.attnotnull = x.nao_nulo
       and coalesce(pg_get_expr(d.adbin, d.adrelid), '') = x.padrao,
       format('%s, not null %s, default %s', format_type(a.atttypid, a.atttypmod), a.attnotnull, pg_get_expr(d.adbin, d.adrelid))
  from (values ('service_orders', 'delivered_at', 'timestamp with time zone', false, ''),
               ('agenda_alocacoes', 'work_shift_id', 'uuid', false, ''),
               ('agenda_acoes', 'payee_id', 'uuid', false, ''),
               ('agenda_acoes', 'work_shift_id', 'uuid', false, ''),
               ('agenda_acoes', 'receivable_ids', 'uuid[]', true, '''{}''::uuid[]'),
               ('agenda_perguntas', 'payee_id', 'uuid', false, ''),
               ('agenda_perguntas', 'carona_em', 'timestamp with time zone', false, ''),
               ('agenda_vigia_rodadas', 'rotina', 'text', true, '''vigia''::text'),
               ('agenda_vigia_rodadas', 'modo_equipe', 'text', false, ''),
               ('agenda_vigia_rodadas', 'modo_diaria', 'text', false, '')) as x(tabela, coluna, tipo, nao_nulo, padrao)
  left join pg_attribute a on a.attrelid = ('public.' || x.tabela)::regclass and a.attname = x.coluna and not a.attisdropped
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum;

-- As FKs: o que vira nulo (n), o que vai junto (c) e o que segura (a = no action).
insert into _resultado
select format('A12 FK %s: on delete %s', x.nome, x.acao),
       c.confdeltype::text = x.acao, coalesce(c.confdeltype::text, 'não existe')
  from (values ('agenda_alocacoes_work_shift_id_fkey', 'n'), ('agenda_acoes_payee_id_fkey', 'n'),
               ('agenda_acoes_work_shift_id_fkey', 'n'), ('agenda_perguntas_payee_id_fkey', 'n'),
               ('agenda_equipe_contato_payee_id_fkey', 'c'), ('agenda_equipe_mensagens_payee_id_fkey', 'a'),
               ('agenda_equipe_mensagens_acao_id_fkey', 'n'), ('agenda_intervencoes_do_dono_service_order_id_fkey', 'c'),
               ('agenda_intervencoes_do_dono_autor_fkey', 'n')) as x(nome, acao)
  left join pg_constraint c on c.conname = x.nome and c.contype = 'f' and c.connamespace = 'public'::regnamespace;

insert into _resultado
select 'A13 os índices: o turno da alocação, uma mensagem por pessoa/dia/tipo/modo (fora as respostas) e a do envio',
       count(*) = 3
       and bool_or(i.indexname = 'agenda_equipe_uma_por_dia' and i.indexdef like 'CREATE UNIQUE INDEX %(payee_id, dia, tipo, modo) WHERE (tipo <> ''resposta''::text)')
       and bool_or(i.indexname = 'agenda_alocacoes_turno' and i.indexdef like '%(work_shift_id) WHERE (work_shift_id IS NOT NULL)'),
       string_agg(i.indexname, ', ' order by i.indexname)
  from pg_indexes i
 where i.schemaname = 'public' and i.indexname in ('agenda_alocacoes_turno', 'agenda_equipe_uma_por_dia', 'agenda_equipe_por_envio');

insert into _resultado
select 'A14 os comentários dos modos dizem o que cada um faz (modo_equipe: a R10 deixa de mandar; modo_diaria: sombra registra)',
       col_description('public.agenda_config'::regclass,
                       (select attnum from pg_attribute where attrelid = 'public.agenda_config'::regclass and attname = 'modo_equipe'))
         like '%a R10 deixa de mandar.'
       and col_description('public.agenda_config'::regclass,
                           (select attnum from pg_attribute where attrelid = 'public.agenda_config'::regclass and attname = 'modo_diaria'))
         like 'desligado = a agenda não lança diária; sombra (nasce) = registra a diária que lançaria%', null;

-- ── B. Cada CHECK recusa uma linha errada ───────────────────────────────────────────────────────────────
do $b$
declare
  r record; v text; v_cmd text;
  v_testados text[] := '{}';
  v_sem_caso text;
  c_msg  text := $q$insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key, estado, recusa_motivo, resposta_texto, resposta_em, leitura) values $q$;
  c_int  text := $q$insert into public.agenda_intervencoes_do_dono (service_order_id, dia, prevista, dita, classe, origem, trecho) values $q$;
  c_cont text := $q$insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, parou_em, parou_motivo) values $q$;
  c_acao text := $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values $q$;
  c_perg text := $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao, estado, respondida_em, opcao_escolhida) values $q$;
  c_rod  text := $q$insert into public.agenda_vigia_rodadas (p_hoje, p_agora, modo_proposta, modo_vigia, rotina, modo_equipe, modo_diaria) values $q$;
  c_aloc text := $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, resultado, resultado_via) values $q$;
  -- os 16 CHECKs da Fase 3 em agenda_config e os 3 de agenda_vigia_rodadas (a cobrança abaixo e as das Fases 1 e 2)
  c_cfg  text[] := array['agenda_config_modo_diaria_check', 'agenda_config_equipe_janela_inicio_check',
    'agenda_config_equipe_janela_fim_check', 'agenda_config_equipe_hora_ficha_check', 'agenda_config_equipe_hora_confirmar_check',
    'agenda_config_equipe_hora_como_foi_check', 'agenda_config_equipe_silencio_ate_check',
    'agenda_config_equipe_proativas_dia_max_check', 'agenda_config_equipe_respostas_dia_max_check',
    'agenda_config_equipe_resposta_validade_check', 'agenda_config_diaria_janela_dias_check',
    'agenda_config_entrega_aviso_du_check', 'agenda_config_carona_por_os_dias_check', 'agenda_config_carteira_laranja_du_check',
    'agenda_config_carteira_vermelho_du_check', 'agenda_config_ppc_meta_check',
    'agenda_vigia_rodadas_rotina_check', 'agenda_vigia_rodadas_modo_equipe_check', 'agenda_vigia_rodadas_modo_diaria_check'];
begin
  for r in
    select * from (values
      -- agenda_config: os 16 parâmetros pelos limites
      ('agenda_config_modo_diaria_check', 'modo talvez', $q$update public.agenda_config set modo_diaria = 'talvez'$q$),
      ('agenda_config_equipe_janela_inicio_check', 'janela às 05:30', $q$update public.agenda_config set equipe_janela_inicio = '05:30'$q$),
      ('agenda_config_equipe_janela_inicio_check', 'janela às 09:30', $q$update public.agenda_config set equipe_janela_inicio = '09:30', equipe_hora_confirmar = '09:45', equipe_silencio_ate = '10:30'$q$),
      ('agenda_config_equipe_janela_fim_check', 'janela até 17:30', $q$update public.agenda_config set equipe_janela_fim = '17:30', equipe_hora_ficha = '17:00', equipe_hora_como_foi = '16:00'$q$),
      ('agenda_config_equipe_janela_fim_check', 'janela até 21:30', $q$update public.agenda_config set equipe_janela_fim = '21:30'$q$),
      ('agenda_config_equipe_hora_ficha_check', 'ficha às 20:00 (o fim da janela)', $q$update public.agenda_config set equipe_hora_ficha = '20:00'$q$),
      ('agenda_config_equipe_hora_ficha_check', 'ficha às 07:00 (antes da janela)', $q$update public.agenda_config set equipe_hora_ficha = '07:00'$q$),
      ('agenda_config_equipe_hora_confirmar_check', 'confirmar às 07:00', $q$update public.agenda_config set equipe_hora_confirmar = '07:00'$q$),
      ('agenda_config_equipe_hora_como_foi_check', '"como foi" às 20:30', $q$update public.agenda_config set equipe_hora_como_foi = '20:30'$q$),
      ('agenda_config_equipe_silencio_ate_check', 'silêncio até 08:00 (menos de 30 min depois da confirmação)', $q$update public.agenda_config set equipe_silencio_ate = '08:00'$q$),
      ('agenda_config_equipe_silencio_ate_check', 'silêncio até 11:30', $q$update public.agenda_config set equipe_silencio_ate = '11:30'$q$),
      ('agenda_config_equipe_proativas_dia_max_check', '4 mensagens por dia', $q$update public.agenda_config set equipe_proativas_dia_max = 4$q$),
      ('agenda_config_equipe_proativas_dia_max_check', '0 mensagens por dia', $q$update public.agenda_config set equipe_proativas_dia_max = 0$q$),
      ('agenda_config_equipe_respostas_dia_max_check', '7 respostas por dia', $q$update public.agenda_config set equipe_respostas_dia_max = 7$q$),
      ('agenda_config_equipe_resposta_validade_check', 'o "ok" vale 1 h', $q$update public.agenda_config set equipe_resposta_validade = '1 hour'$q$),
      ('agenda_config_equipe_resposta_validade_check', 'o "ok" vale 25 h', $q$update public.agenda_config set equipe_resposta_validade = '25 hours'$q$),
      ('agenda_config_diaria_janela_dias_check', 'diária até 15 dias atrás', $q$update public.agenda_config set diaria_janela_dias = 15$q$),
      ('agenda_config_entrega_aviso_du_check', 'aviso da entrega em 0 du', $q$update public.agenda_config set entrega_aviso_du = 0$q$),
      ('agenda_config_carona_por_os_dias_check', 'carona a cada 15 dias', $q$update public.agenda_config set carona_por_os_dias = 15$q$),
      ('agenda_config_carteira_laranja_du_check', 'laranja em 16 du', $q$update public.agenda_config set carteira_laranja_du = 16, carteira_vermelho_du = 30$q$),
      ('agenda_config_carteira_vermelho_du_check', 'vermelho igual ao laranja', $q$update public.agenda_config set carteira_vermelho_du = 5$q$),
      ('agenda_config_carteira_vermelho_du_check', 'vermelho em 61 du', $q$update public.agenda_config set carteira_vermelho_du = 61$q$),
      ('agenda_config_ppc_meta_check', 'meta 0,4', $q$update public.agenda_config set ppc_meta = 0.4$q$),
      ('agenda_config_ppc_meta_check', 'meta 0,96', $q$update public.agenda_config set ppc_meta = 0.96$q$),
      ('aceitou', 'janela 06:00–21:00, ficha 20:59, silêncio 08:15, vermelho 6, meta 0,95, diária ligada',
       $q$update public.agenda_config set equipe_janela_inicio = '06:00', equipe_janela_fim = '21:00', equipe_hora_ficha = '20:59', equipe_silencio_ate = '08:15', carteira_vermelho_du = 6, ppc_meta = 0.95, modo_diaria = 'ligado'$q$),
      -- service_orders: a entrega só depois da saída (pela porta, para o gatilho deixar passar e o CHECK responder)
      ('so_entrega_depois_da_conclusao', 'entregue sem a saída', $q$set local agenda.porta = 'on'; update public.service_orders set delivered_at = now() where id = {os2}$q$),
      ('so_entrega_depois_da_conclusao', 'a saída apagada com a entrega gravada', $q$set local agenda.porta = 'on'; update public.service_orders set delivered_at = now() where id = {os}; update public.service_orders set check_out_at = null where id = {os}$q$),
      ('aceitou', 'entregue depois da saída', $q$set local agenda.porta = 'on'; update public.service_orders set delivered_at = now() where id = {os}$q$),
      -- as listas fechadas ampliadas
      ('agenda_alocacoes_resultado_via_check', 'resultado por sms', '{ins_aloc}' || $q$({os2}, {rob}, '2026-11-03', 'tarde', 'publicada', 'cumprido', 'sms')$q$),
      ('aceitou', 'resultado dito pela equipe', '{ins_aloc}' || $q$({os2}, {rob}, '2026-11-03', 'tarde', 'publicada', 'cumprido', 'equipe')$q$),
      ('agenda_acoes_tipo_check', 'tipo outro', '{ins_acao}' || $q$('2026-11-05', false, 'equipe', 'outro', 'TESTE AG3.')$q$),
      ('agenda_acoes_origem_check', 'origem chute', '{ins_acao}' || $q$('2026-11-05', false, 'chute', 'diaria', 'TESTE AG3.')$q$),
      ('aceitou', 'os 4 tipos novos, da equipe', '{ins_acao}' || $q$('2026-11-05', false, 'equipe', 'diaria', 'TESTE AG3.'), ('2026-11-05', false, 'equipe', 'concluir', 'TESTE AG3.'), ('2026-11-05', false, 'dono', 'entregar', 'TESTE AG3.'), ('2026-11-05', false, 'sistema', 'equipe', 'TESTE AG3.')$q$),
      ('agenda_perguntas_tipo_check', 'tipo outro', '{ins_perg}' || $q$('outro', 'outro:ag3', 'Pergunta?', 'sombra', '[]', null, 'aberta', null, null)$q$),
      ('aceitou', 'os 4 tipos novos que não são críticos, sem opções', '{ins_perg}' || $q$('diaria_ligar', 'diaria_ligar:ag3', 'Ligo?', 'sombra', '[]', null, 'aberta', null, null), ('equipe_resposta', 'equipe_resposta:ag3', 'O que ele quis dizer?', 'sombra', '[]', null, 'aberta', null, null), ('concluir', 'concluir:ag3', 'Terminou?', 'sombra', '[]', null, 'aberta', null, null), ('entrega', 'entrega:ag3', 'Já entregou?', 'sombra', '[]', null, 'aberta', null, null)$q$),
      ('critica_tem_opcoes', 'diária com 1 opção', '{ins_perg}' || $q$('diaria', 'diaria:ag3', 'Meia ou inteira?', 'sombra', '[{"n":1}]', 1, 'aberta', null, null)$q$),
      ('critica_tem_opcoes', 'diária sem recomendação', '{ins_perg}' || $q$('diaria', 'diaria:ag3', 'Meia ou inteira?', 'sombra', '[{"n":1},{"n":2}]', null, 'aberta', null, null)$q$),
      ('critica_decidida', 'diária respondida sem a opção', '{ins_perg}' || $q$('diaria', 'diaria:ag3', 'Meia ou inteira?', 'ligado', '[{"n":1},{"n":2}]', 1, 'respondida', now(), null)$q$),
      ('aceitou', 'diária com 3 opções e a recomendação; respondida com a opção', '{ins_perg}' || $q$('diaria', 'diaria:ag3', 'Meia ou inteira?', 'sombra', '[{"n":1},{"n":2},{"n":3}]', 1, 'aberta', null, null), ('diaria', 'diaria:ag3b', 'Meia ou inteira?', 'ligado', '[{"n":1},{"n":2}]', 2, 'respondida', now(), 2)$q$),
      -- agenda_vigia_rodadas
      ('agenda_vigia_rodadas_rotina_check', 'rotina talvez', '{ins_rod}' || $q$('2026-11-05', now(), 'sombra', 'sombra', 'talvez', null, null)$q$),
      ('agenda_vigia_rodadas_modo_equipe_check', 'modo da equipe talvez', '{ins_rod}' || $q$('2026-11-05', now(), 'sombra', 'sombra', 'rotina', 'talvez', 'sombra')$q$),
      ('agenda_vigia_rodadas_modo_diaria_check', 'modo da diária talvez', '{ins_rod}' || $q$('2026-11-05', now(), 'sombra', 'sombra', 'rotina', 'sombra', 'talvez')$q$),
      ('aceitou', 'uma rodada da rotina com os modos; uma da vigia sem eles', '{ins_rod}' || $q$('2026-11-05', now(), 'ligado', 'ligado', 'rotina', 'sombra', 'desligado'), ('2026-11-05', now(), 'ligado', 'ligado', 'vigia', null, null)$q$),
      -- agenda_equipe_contato
      ('agenda_equipe_contato_incluido_por_check', 'incluído pelo cadastro', '{ins_cont}' || $q$({joao}, true, 'cadastro', null, null)$q$),
      ('agenda_equipe_contato_parou_motivo_check', 'motivo de 201', '{ins_cont}' || $q$({joao}, false, 'dono', now(), repeat('x', 201))$q$),
      ('parou_coerente', 'parou e ainda recebe', '{ins_cont}' || $q$({joao}, true, 'dono', now(), 'pediu para parar')$q$),
      ('agenda_equipe_contato_pkey', 'o Roberto duas vezes', '{ins_cont}' || $q$({rob}, true, 'dono', null, null)$q$),
      ('agenda_equipe_contato_payee_id_fkey', 'pessoa que não existe', '{ins_cont}' || $q$(gen_random_uuid(), true, 'dono', null, null)$q$),
      ('aceitou', 'o João pelo dono, parado, e o descartável sem rotina', '{ins_cont}' || $q$({joao}, false, 'dono', now(), 'não tem telefone'), ({desc}, false, 'regra', null, null)$q$),
      -- agenda_equipe_mensagens
      ('agenda_equipe_mensagens_tipo_check', 'tipo aviso', '{ins_msg}' || $q$({rob}, '2026-11-06', 'aviso', 'sombra', 'Roberto, amanhã.', now(), 'k:1', 'registrada', null, null, null, null)$q$),
      ('agenda_equipe_mensagens_modo_check', 'modo desligado', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'desligado', 'Roberto, amanhã.', now(), 'k:1', 'registrada', null, null, null, null)$q$),
      ('agenda_equipe_mensagens_texto_check', 'texto de 2', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', 'ok', now(), 'k:1', 'registrada', null, null, null, null)$q$),
      ('agenda_equipe_mensagens_texto_check', 'texto de 601', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', repeat('x', 601), now(), 'k:1', 'registrada', null, null, null, null)$q$),
      ('agenda_equipe_mensagens_estado_check', 'estado talvez', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'k:1', 'talvez', null, null, null, null)$q$),
      ('agenda_equipe_mensagens_recusa_motivo_check', 'recusada por preguiça', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'k:1', 'recusada', 'preguica', null, null, null)$q$),
      ('agenda_equipe_mensagens_resposta_texto_check', 'resposta de 501', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'k:1', 'respondida', null, repeat('x', 501), now(), null)$q$),
      ('agenda_equipe_mensagens_leitura_check', 'leitura em lista', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'k:1', 'respondida', null, 'ok', now(), '[]')$q$),
      ('recusa_coerente', 'recusada sem o motivo', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'k:1', 'recusada', null, null, null, null)$q$),
      ('recusa_coerente', 'registrada com motivo de recusa', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'k:1', 'registrada', 'teto', null, null, null)$q$),
      ('resposta_coerente', 'resposta sem a hora', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'k:1', 'respondida', null, 'ok', null, null)$q$),
      ('resposta_coerente', 'a hora da resposta sem o texto', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'k:1', 'respondida', null, null, now(), null)$q$),
      ('agenda_equipe_mensagens_dedupe_key_key', 'a mesma chave da fila de novo', '{ins_msg}' || $q$({rob}, '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'agenda-equipe:ficha:teste-ag3:2026-11-05:sombra', 'registrada', null, null, null, null)$q$),
      ('agenda_equipe_uma_por_dia', 'duas fichas do mesmo dia no mesmo modo', '{ins_msg}' || $q$({rob}, '2026-11-05', 'ficha', 'sombra', 'Roberto, amanhã de novo.', now(), 'k:2', 'registrada', null, null, null, null)$q$),
      ('agenda_equipe_mensagens_payee_id_fkey', 'pessoa que não existe', '{ins_msg}' || $q$(gen_random_uuid(), '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'k:1', 'registrada', null, null, null, null)$q$),
      ('agenda_equipe_mensagens_acao_id_fkey', 'ação que não existe', $q$insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key, acao_id) values ({rob}, '2026-11-06', 'ficha', 'sombra', 'Roberto, amanhã.', now(), 'k:1', gen_random_uuid())$q$),
      ('aceitou', 'a ficha do mesmo dia em ligado; duas respostas no mesmo dia; a confirmação recusada pelo teto; a resposta lida',
       '{ins_msg}' || $q$({rob}, '2026-11-05', 'ficha', 'ligado', 'Roberto, amanhã: 8h.', now(), 'k:3', 'enfileirada', null, null, null, null), ({rob}, '2026-11-05', 'resposta', 'ligado', 'Amanhã: 8h no barco.', now(), 'k:4', 'enfileirada', null, null, null, null), ({rob}, '2026-11-05', 'resposta', 'ligado', 'Amanhã: 8h no barco.', now(), 'k:5', 'enfileirada', null, null, null, null), ({rob}, '2026-11-05', 'confirmar', 'ligado', 'Bom dia, Roberto. Tá confirmado?', now(), 'k:6', 'recusada', 'teto', null, null, null), ({rob}, '2026-11-05', 'como_foi', 'sombra', 'Como foi hoje?', now(), 'k:7', 'respondida', null, 'ok', now(), '{"jornada":"dia"}')$q$),
      -- agenda_intervencoes_do_dono
      ('agenda_intervencoes_do_dono_prevista_check', 'prevista talvez', '{ins_int}' || $q$({os2}, '2026-11-03', 'talvez', 'manha', 'execucao', 'conversa', null)$q$),
      ('agenda_intervencoes_do_dono_dita_check', 'dita à noite', '{ins_int}' || $q$({os2}, '2026-11-03', 'nenhuma', 'noite', 'execucao', 'conversa', null)$q$),
      ('agenda_intervencoes_do_dono_classe_check', 'classe outra', '{ins_int}' || $q$({os2}, '2026-11-03', 'nenhuma', 'manha', 'outra', 'conversa', null)$q$),
      ('agenda_intervencoes_do_dono_origem_check', 'origem sms', '{ins_int}' || $q$({os2}, '2026-11-03', 'nenhuma', 'manha', 'execucao', 'sms', null)$q$),
      ('agenda_intervencoes_do_dono_trecho_check', 'trecho de 301', '{ins_int}' || $q$({os2}, '2026-11-03', 'nenhuma', 'manha', 'execucao', 'conversa', repeat('x', 301))$q$),
      ('agenda_intervencoes_do_dono_service_order_id_dia_origem_key', 'a mesma OS, dia e origem de novo', '{ins_int}' || $q$({os2}, '2026-11-04', 'abertura', 'dia', 'execucao', 'conversa', null)$q$),
      ('agenda_intervencoes_do_dono_service_order_id_fkey', 'OS que não existe', '{ins_int}' || $q$(gen_random_uuid(), '2026-11-03', 'nenhuma', 'manha', 'execucao', 'conversa', null)$q$),
      ('aceitou', 'a mesma OS e dia pela conferência; o diagnóstico em que ele passou', '{ins_int}' || $q$({os2}, '2026-11-04', 'abertura', 'dia', 'execucao', 'conferencia', null), ({os}, '2026-11-03', 'turno', 'passou', 'diagnostico', 'tela', 'passei lá')$q$),
      -- comissao_config
      ('comissao_config_id_check', 'uma 2ª linha', $q$insert into public.comissao_config (id) values (false)$q$),
      ('comissao_config_pkey', 'a mesma linha de novo', $q$insert into public.comissao_config (id) values (true)$q$),
      ('comissao_config_pct_check', '60% do lucro', $q$update public.comissao_config set pct = 0.6$q$),
      ('comissao_config_modelo_check', 'modelo só diária', $q$update public.comissao_config set modelo = 'so_diaria'$q$),
      ('comissao_config_meses_teste_check', '13 meses de teste', $q$update public.comissao_config set meses_teste = 13$q$),
      ('comissao_config_imposto_fonte_check', 'imposto pelo chute', $q$update public.comissao_config set imposto_fonte = 'chute'$q$),
      ('comissao_config_pagamento_check', 'pagamento ligado', $q$update public.comissao_config set pagamento = 'ligado'$q$),
      ('aceitou', '30%, começo em novembro, sem imposto', $q$update public.comissao_config set pct = 0.3, inicio = '2026-11-01', imposto_fonte = 'nenhum'$q$)
    ) as c(esperado, caso, comando)
  loop
    v_cmd := r.comando;
    v_cmd := replace(replace(replace(replace(replace(replace(replace(v_cmd,
               '{ins_msg}', c_msg), '{ins_int}', c_int), '{ins_cont}', c_cont), '{ins_acao}', c_acao), '{ins_perg}', c_perg),
               '{ins_rod}', c_rod), '{ins_aloc}', c_aloc);
    v_cmd := replace(replace(replace(replace(replace(v_cmd,
               '{os2}', quote_literal('e3000000-0000-4000-8000-000000000202')),
               '{os}', quote_literal('e3000000-0000-4000-8000-000000000201')),
               '{rob}', quote_literal('e3000000-0000-4000-8000-000000000101')),
               '{joao}', quote_literal('e3000000-0000-4000-8000-000000000102')),
               '{desc}', quote_literal('e3000000-0000-4000-8000-000000000103'));
    v := pg_temp.recusa(v_cmd);
    v_testados := v_testados || r.esperado;
    insert into _resultado values (
      format('B %s: %s', case when r.esperado = 'aceitou' then 'entra' else 'recusa' end, r.caso),
      v = r.esperado,
      case when v = r.esperado then r.esperado else format('esperava %s, veio %s', r.esperado, v) end);
  end loop;

  -- FASE 3 (P5, 20261026100400): comissao_config ganhou competencia (premissa b do dono) e imposto_fonte aceita
  -- 'aliquota_simples_sempre'. Só quando a coluna existe (este teste roda também no corte de 20261026100000); o resto da
  -- prova está em agenda_fase3_comissao.sql (J7).
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'comissao_config' and column_name = 'competencia') then
    for r in
      select * from (values
        ('comissao_config_competencia_check', 'competência pelo pagamento', $q$update public.comissao_config set competencia = 'pagamento'$q$),
        ('aceitou', 'competência pela saída, imposto em toda OS', $q$update public.comissao_config set competencia = 'saida', imposto_fonte = 'aliquota_simples_sempre'$q$)
      ) as c(esperado, caso, comando)
    loop
      v := pg_temp.recusa(r.comando);
      v_testados := v_testados || r.esperado;
      insert into _resultado values (
        format('B %s: %s', case when r.esperado = 'aceitou' then 'entra' else 'recusa' end, r.caso),
        v = r.esperado,
        case when v = r.esperado then r.esperado else format('esperava %s, veio %s', r.esperado, v) end);
    end loop;
  end if;

  -- Nenhum CHECK das 4 tabelas novas nem dos que a Fase 3 pôs ou ampliou nas outras ficou sem caso (um CHECK novo sem
  -- teste reprova aqui).
  select string_agg(c.conname, ', ' order by c.conname) into v_sem_caso
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public' and c.contype in ('c', 'x')
     and (t.relname in ('agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config')
          or c.conname = any (c_cfg)
          or c.conname in ('so_entrega_depois_da_conclusao', 'agenda_alocacoes_resultado_via_check', 'agenda_acoes_tipo_check',
                           'agenda_acoes_origem_check', 'agenda_perguntas_tipo_check', 'critica_tem_opcoes', 'critica_decidida'))
     and not (c.conname = any (v_testados));
  insert into _resultado values ('B todo CHECK da Fase 3 (novo ou ampliado) tem um caso que ele recusa', v_sem_caso is null, v_sem_caso);

  insert into _resultado
  select 'B os 19 CHECKs da Fase 3 em agenda_config e agenda_vigia_rodadas existem com o nome', count(*) = 19,
         count(*)::text || ' de 19'
    from pg_constraint c where c.conname = any (c_cfg) and c.contype = 'c' and c.connamespace = 'public'::regnamespace;
end
$b$;

-- ── C. A diária que diverge é crítica ───────────────────────────────────────────────────────────────────
insert into _resultado
select format('C1 critica de %s = %s', x.tipo, x.critica),
       (select p.critica from public.agenda_perguntas p where p.tipo = x.tipo order by p.criada_em limit 1) is not distinct from x.critica,
       (select p.critica::text from public.agenda_perguntas p where p.tipo = x.tipo order by p.criada_em limit 1)
  from (values ('diaria', true), ('concluir', false)) as x(tipo, critica);

-- As outras pelo cálculo da coluna numa pergunta de cada tipo (inserida e lida aqui).
do $c$
declare
  r record; v boolean;
begin
  for r in
    select * from (values ('nao_cabe', true), ('segundo_atraso', true), ('atraso_longo', true), ('remarcar_confirmado', true),
                          ('fixada_pelo_dono', true), ('diaria', true), ('diaria_ligar', false), ('equipe_resposta', false),
                          ('concluir', false), ('entrega', false), ('chegou', false), ('conferencia', false)) as t(tipo, critica)
  loop
    insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao, dia)
    values (r.tipo, 'c1:' || r.tipo, 'TESTE AG3 C1?', 'sombra',
            case when r.critica then '[{"n":1},{"n":2}]'::jsonb else '[]'::jsonb end,
            case when r.critica then 1 end, date '2026-11-05')
    returning critica into v;
    insert into _resultado values (format('C2 uma pergunta %s nasce com critica = %s', r.tipo, r.critica), v = r.critica, v::text);
  end loop;
end
$c$;

insert into _resultado values
  ('C3 ação crítica de diária com a pergunta ainda aberta: recusada',
   pg_temp.erro_de($q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, critica, pergunta_id)
                      values ('2026-11-05', true, 'conferencia', 'diaria', 'TESTE AG3: meia diária.', true,
                              'e3000000-0000-4000-8000-000000000501')$q$)
     = 'P0001 Ação crítica sem decisão do dono: nada foi feito.',
   pg_temp.erro_de($q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, critica, pergunta_id)
                      values ('2026-11-05', true, 'conferencia', 'diaria', 'TESTE AG3: meia diária.', true,
                              'e3000000-0000-4000-8000-000000000501')$q$));

update public.agenda_perguntas
   set estado = 'respondida', respondida_em = now(), respondida_via = 'whatsapp', opcao_escolhida = 1,
       respondida_por = 'e3000000-0000-4000-8000-000000000001', resposta = 'diária Roberto meia'
 where id in ('e3000000-0000-4000-8000-000000000501', 'e3000000-0000-4000-8000-000000000503');

insert into _resultado values
  ('C4 ação crítica de diária com a pergunta respondida em ligado: entra',
   pg_temp.erro_de($q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, critica, pergunta_id, payee_id)
                      values ('2026-11-05', true, 'conferencia', 'diaria', 'TESTE AG3: meia diária.', true,
                              'e3000000-0000-4000-8000-000000000501', 'e3000000-0000-4000-8000-000000000101')$q$) = 'sem erro',
   null),
  ('C5 …e executada com a pergunta respondida só em sombra: recusada (a pergunta nunca foi feita de verdade)',
   pg_temp.erro_de($q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, critica, pergunta_id)
                      values ('2026-11-05', true, 'conferencia', 'diaria', 'TESTE AG3: meia diária.', true,
                              'e3000000-0000-4000-8000-000000000503')$q$)
     = 'P0001 Ação crítica sem decisão do dono: nada foi feito.', null),
  ('C6 …em sombra (executada = false) a ação registra com a pergunta de sombra',
   pg_temp.erro_de($q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, critica, pergunta_id)
                      values ('2026-11-05', false, 'conferencia', 'diaria', 'TESTE AG3: meia diária.', true,
                              'e3000000-0000-4000-8000-000000000503')$q$) = 'sem erro', null);

-- ── D. A entrega só pela porta ──────────────────────────────────────────────────────────────────────────
do $d$
declare
  c_os    constant uuid := 'e3000000-0000-4000-8000-000000000201';
  c_frase constant text := 'P0001 A entrega é registrada na OS (botão Entregue) ou dizendo "entreguei <cliente>".';
  v text; v_ent timestamptz;
  v_barco   uuid := (select id from public.vessels where client_id is not null order by created_at, id limit 1);
  v_cliente uuid := (select client_id from public.vessels where id = v_barco);
begin
  -- Em todos os modos da agenda (a coluna é nova: ninguém mais escreve nela).
  for v in select unnest(array['desligado', 'sombra', 'ligado']) loop
    update public.agenda_config set modo_proposta = v where id;
    insert into _resultado values (format('D1 com modo_proposta %s, gravar a entrega direto na OS é recusado com a frase', v),
      pg_temp.erro_de(format('update public.service_orders set delivered_at = %L where id = %L',
                             timestamptz '2026-11-05 10:00-03', c_os)) = c_frase,
      pg_temp.erro_de(format('update public.service_orders set delivered_at = %L where id = %L',
                             timestamptz '2026-11-05 10:00-03', c_os)));
  end loop;
  update public.agenda_config set modo_proposta = 'desligado' where id;

  -- Pela porta (a chave local à transação que só as funções da porta ligam) entra.
  perform set_config('agenda.porta', 'on', true);
  v := pg_temp.erro_de(format('update public.service_orders set delivered_at = %L where id = %L',
                              timestamptz '2026-11-05 10:00-03', c_os));
  perform set_config('agenda.porta', 'off', true);
  select delivered_at into v_ent from public.service_orders where id = c_os;
  insert into _resultado values ('D2 pela porta (agenda.porta = on) a entrega entra',
    v = 'sem erro' and v_ent = timestamptz '2026-11-05 10:00-03', v || ' ' || coalesce(v_ent::text, 'nula'));

  insert into _resultado values
    ('D3 mudar outra coluna da OS entregue, fora da porta, passa',
     pg_temp.erro_de(format('update public.service_orders set internal_notes = %L where id = %L', 'TESTE AG3', c_os)) = 'sem erro', null),
    ('D4 regravar a entrega com o mesmo valor (o formulário que manda a linha inteira) passa',
     pg_temp.erro_de(format('update public.service_orders set delivered_at = %L where id = %L',
                            timestamptz '2026-11-05 10:00-03', c_os)) = 'sem erro', null),
    ('D5 apagar a entrega fora da porta é recusado',
     pg_temp.erro_de(format('update public.service_orders set delivered_at = null where id = %L', c_os)) = c_frase, null),
    ('D6 a OS que nasce entregue, fora da porta, é recusada',
     pg_temp.erro_de(format($q$insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status,
                                 check_out_at, delivered_at) values (%L, %L, 'OS-TESTE-AG3-3', 'completed', 'approved', %L, %L)$q$,
                            v_cliente, v_barco, timestamptz '2026-11-04 17:00-03', timestamptz '2026-11-05 10:00-03')) = c_frase, null),
    ('D7 a OS nova sem entrega nasce como sempre',
     pg_temp.erro_de(format($q$insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
                               values (%L, %L, 'OS-TESTE-AG3-4', 'open', 'approved')$q$, v_cliente, v_barco)) = 'sem erro', null);
end
$d$;

-- ── E. O registro ───────────────────────────────────────────────────────────────────────────────────────
insert into _resultado values
  ('E1 a mensagem à equipe não se apaga',
   pg_temp.erro_de($q$delete from public.agenda_equipe_mensagens where id = 'e3000000-0000-4000-8000-000000000701'$q$)
     = 'P0001 O registro da agenda não se apaga.', null);

insert into _resultado
select format('E2 a mensagem não muda: %s', x.campo),
       pg_temp.erro_de(format('update public.agenda_equipe_mensagens set %s where id = %L', x.mudanca,
                              'e3000000-0000-4000-8000-000000000701'))
         = 'P0001 A mensagem registrada não muda: só o estado, a fila e a resposta.',
       pg_temp.erro_de(format('update public.agenda_equipe_mensagens set %s where id = %L', x.mudanca,
                              'e3000000-0000-4000-8000-000000000701'))
  from (values ('o texto', $q$texto = 'Outro texto.'$q$), ('o modo', $q$modo = 'ligado'$q$), ('o dia', $q$dia = '2026-11-06'$q$),
               ('a pessoa', $q$payee_id = 'e3000000-0000-4000-8000-000000000102'$q$),
               ('a hora de enviar', $q$enviar_em = now()$q$), ('a chave da fila', $q$dedupe_key = 'outra'$q$)) as x(campo, mudanca);

insert into _resultado values
  ('E3 a mensagem vai para a fila (estado e fila_id) e recebe a resposta lida, com a ação',
   pg_temp.erro_de($q$update public.agenda_equipe_mensagens set estado = 'enfileirada', fila_id = gen_random_uuid()
                      where id = 'e3000000-0000-4000-8000-000000000701'$q$) = 'sem erro'
   and pg_temp.erro_de($q$update public.agenda_equipe_mensagens
                          set estado = 'respondida', resposta_texto = 'ok', resposta_em = now(), resposta_wa_id = 'wa-teste-ag3',
                              leitura = '{"concorda": true}', acao_id = 'e3000000-0000-4000-8000-000000000601'
                        where id = 'e3000000-0000-4000-8000-000000000701'$q$) = 'sem erro',
   null);

-- O meio-dia publicado ganha a diária (work_shift_id não é "o que" da alocação: muda sem cancelar).
insert into _resultado values
  ('E4 o meio-dia publicado ganha a diária sem ser cancelado',
   pg_temp.erro_de($q$update public.agenda_alocacoes set work_shift_id = 'e3000000-0000-4000-8000-000000000402'
                      where id = 'e3000000-0000-4000-8000-000000000801'$q$) = 'sem erro', null);

-- Apagar a diária no Financeiro: a ação e o meio-dia ficam, com a diária nula. (O apagar vai num comando e a conferência
-- noutro: as subconsultas do mesmo comando ainda veriam a foto de antes.)
do $e5$
declare
  v text := pg_temp.erro_de($q$delete from public.work_shifts where id = 'e3000000-0000-4000-8000-000000000402'$q$);
begin
  insert into _resultado values
    ('E5 apagar a diária deixa a ação e o meio-dia com a diária nula (o "não muda" aceita o ON DELETE SET NULL)',
     v = 'sem erro'
     and (select work_shift_id from public.agenda_acoes where id = 'e3000000-0000-4000-8000-000000000601') is null
     and (select work_shift_id from public.agenda_alocacoes where id = 'e3000000-0000-4000-8000-000000000801') is null
     and exists (select 1 from public.agenda_acoes where id = 'e3000000-0000-4000-8000-000000000601'), v);
end
$e5$;

-- A carona: muda com a pergunta aberta; fechada, não muda mais.
insert into _resultado values
  ('E6 a pergunta aberta pega carona (carona_em muda)',
   pg_temp.erro_de($q$update public.agenda_perguntas set carona_em = now() where id = 'e3000000-0000-4000-8000-000000000502'$q$)
     = 'sem erro', null);
update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'TESTE AG3: concluída pela tela'
 where id = 'e3000000-0000-4000-8000-000000000502';
insert into _resultado values
  ('E7 …fechada, a carona não muda mais',
   pg_temp.erro_de($q$update public.agenda_perguntas set carona_em = null where id = 'e3000000-0000-4000-8000-000000000502'$q$)
     = 'P0001 A pergunta fechada não muda: a decisão registrada fica como foi.', null),
  ('E8 a pergunta aberta não muda a pessoa',
   pg_temp.erro_de($q$update public.agenda_perguntas set payee_id = 'e3000000-0000-4000-8000-000000000102'
                      where chave = 'c1:diaria_ligar'$q$)
     = 'P0001 A pergunta não muda o que pergunta: só se mostra, se responde ou se resolve.', null);

-- Apagar o favorecido: a pergunta (fechada) e a ação ficam, com a pessoa nula.
do $e9$
declare
  v text := pg_temp.erro_de($q$delete from public.payees where id = 'e3000000-0000-4000-8000-000000000103'$q$);
begin
  insert into _resultado values
    ('E9 apagar o favorecido deixa a pergunta fechada e a ação com a pessoa nula',
     v = 'sem erro'
     and (select payee_id from public.agenda_perguntas where id = 'e3000000-0000-4000-8000-000000000502') is null
     and (select payee_id from public.agenda_acoes where id = 'e3000000-0000-4000-8000-000000000602') is null
     and exists (select 1 from public.agenda_perguntas where id = 'e3000000-0000-4000-8000-000000000502'), v);
end
$e9$;

insert into _resultado values
  ('E10 as cobranças que a ação criou não mudam depois',
   pg_temp.erro_de($q$update public.agenda_acoes set receivable_ids = array[gen_random_uuid()]
                      where id = 'e3000000-0000-4000-8000-000000000601'$q$)
     = 'P0001 A ação registrada não muda: só se desfaz (uma vez) ou se marca como contada.', null),
  ('E11 a ação não troca a pessoa',
   pg_temp.erro_de($q$update public.agenda_acoes set payee_id = 'e3000000-0000-4000-8000-000000000102'
                      where id = 'e3000000-0000-4000-8000-000000000601'$q$)
     = 'P0001 A ação registrada não muda: só se desfaz (uma vez) ou se marca como contada.', null);

insert into public.agenda_vigia_rodadas (id, p_hoje, p_agora, modo_proposta, modo_vigia)
values ('e3000000-0000-4000-8000-000000000901', '2026-11-05', now(), 'sombra', 'sombra');
insert into _resultado
select 'E12 a rodada gravada como na Fase 2 é da vigia, sem os modos novos',
       r.rotina = 'vigia' and r.modo_equipe is null and r.modo_diaria is null, r.rotina
  from public.agenda_vigia_rodadas r where r.id = 'e3000000-0000-4000-8000-000000000901';

-- ── F. RLS de verdade ───────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('F1 %s lê %s', x.quem, t),
       pg_temp.como(x.uid, 'authenticated', format('select count(*) from public.%I', t)) ~ '^[1-9][0-9]*$',
       pg_temp.como(x.uid, 'authenticated', format('select count(*) from public.%I', t))
  from (values ('o admin', 'e3000000-0000-4000-8000-000000000001'::uuid),
               ('o financeiro', 'e3000000-0000-4000-8000-000000000003'::uuid)) as x(quem, uid)
 cross join unnest(array['agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config']) t;

insert into _resultado
select format('F2 o técnico não vê nada de %s (nem a própria rotina: é de gestão)', t),
       pg_temp.como('e3000000-0000-4000-8000-000000000002', 'authenticated', format('select count(*) from public.%I', t)) = '0',
       pg_temp.como('e3000000-0000-4000-8000-000000000002', 'authenticated', format('select count(*) from public.%I', t))
  from unnest(array['agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config']) t;

insert into _resultado
select format('F3 anon não lê %s', t),
       pg_temp.como(null, 'anon', format('select count(*) from public.%I', t)) like 'erro 42501:%',
       pg_temp.como(null, 'anon', format('select count(*) from public.%I', t))
  from unnest(array['agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config']) t;

insert into _resultado values
  ('F4 nem o admin escreve direto: incluir alguém na rotina',
   pg_temp.como('e3000000-0000-4000-8000-000000000001', 'authenticated',
     $q$with i as (insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por)
                   values ('e3000000-0000-4000-8000-000000000102', true, 'dono') returning 1) select count(*) from i$q$)
     like 'erro 42501:%', null),
  ('F5 nem o admin liga o pagamento da comissão',
   pg_temp.como('e3000000-0000-4000-8000-000000000001', 'authenticated',
     $q$with u as (update public.comissao_config set pct = 0.3 returning 1) select count(*) from u$q$) like 'erro 42501:%', null),
  ('F6 nem o admin apaga uma mensagem',
   pg_temp.como('e3000000-0000-4000-8000-000000000001', 'authenticated',
     $q$with d as (delete from public.agenda_equipe_mensagens returning 1) select count(*) from d$q$) like 'erro 42501:%', null);

-- ── G. Portas das funções ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'G1 as funções de gatilho (novas e recriadas): nem anon nem authenticated',
       bool_and(not has_function_privilege('anon', f::regprocedure, 'execute')
                and not has_function_privilege('authenticated', f::regprocedure, 'execute')),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f::regprocedure, 'execute')
                                      or has_function_privilege('authenticated', f::regprocedure, 'execute'))
  from unnest(array['public._agenda_equipe_mensagens_so_responde()', 'public._so_entrega_pela_porta()',
                    'public._agenda_perguntas_antes()', 'public._agenda_acoes_so_desfaz()']) f;

insert into _resultado
select 'G2 só _so_entrega_pela_porta é security definer (como _so_datas_pela_agenda); todas com search_path fixo',
       count(*) = 4 and bool_and(p.prosecdef = (p.proname = '_so_entrega_pela_porta'))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       count(*)::text || ' | ' || string_agg(p.proname || ':' || p.prosecdef::text, ', ' order by p.proname)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('_agenda_equipe_mensagens_so_responde', '_so_entrega_pela_porta', '_agenda_perguntas_antes',
                     '_agenda_acoes_so_desfaz');

select teste, ok, detalhe from _resultado order by teste;

rollback;
