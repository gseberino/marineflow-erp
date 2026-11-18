-- Prova da ficha paga, parte C (18/11/2026, migration 20270127100000; plano agenda-pesquisa/via-os129-1711/plano/F2c/RESUMO.md), com a
-- decisão do dono de 18/11 ~18:10 ("Não mandar o 'como foi'"): o dia em que a ficha do técnico ficou segurada (a ficha da véspera recusada
-- por veto e nenhuma confirmação da manhã saída) não recebe o "Como foi hoje?" das 17:00. Sobre a carteira REAL de 29/10 (o replay da 7a).
-- bancada: depende de 20270127100000
--
--   C0 a porta de antes; tirado o bloco "-- FICHA PAGA C:", a _agenda_rotina_como_foi é a de produção (d3e8b6f7), byte a byte; o comentário
--   C1 (o C3 da revisão da F2b v2) o dia 1 segurado: sem "como foi", o "ok" não vira prova e a ficha do dia 2 fica
--   C2 (o C5) o "ok" das 19:45 também não: a ficha e a confirmação do dia 2 ficam
--   C3 a ficha liberada: o "como foi" de sempre
--   C4 a ficha recusada por veto mas a confirmação da manhã saiu: o "como foi" de sempre
--   C5 a ficha recusada pelo teto (não por veto): o "como foi" de sempre
--   C5b a ficha recusada sem telefone (não por veto): o "como foi" de sempre
--   C6 a ficha saiu e só a confirmação foi recusada por veto: o "como foi" de sempre
--   C7 em teste (sombra): o "como foi" é registrado como antes
--   C8 nenhuma mensagem nem pergunta nova (nem com a vigia do "sem registro")
--   XC1–XC6 (da revisão independente da F2c, 18/11): nenhuma linha de confirmar (XC1); a confirmação de OUTRO dia que saiu, o caso do Alex
--   (XC2); a ficha vetada de OUTRO dia (XC3); outra pessoa no mesmo dia (XC4, XC5); a confirmação em sem_resposta, o estado real às 17:00 (XC6)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration: C0 só lê; C1 a C8 e XC1 a XC6 usam o replay e só rodam na bancada (fora dela saem PULADO). Termina em
--   ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select py.id from public.payees py where py.name = p_nome and py.active order by py.id limit 1
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O texto sem os blocos "-- FICHA PAGA B: … -- FICHA PAGA B: fim" (contados por nível) e, com p_f2, também sem os "-- FICHA PAGA:" da F2
-- (a linha de antes que um bloco trocou volta: "--antes:" na coluna 0).
create function pg_temp.sem_b(p text, p_f2 boolean default false) returns text language sql immutable as $f$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ x.abre and l !~ x.fim then 1 when l ~ x.fim then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ x.fim as fecha
                     from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o),
                          (select case when p_f2 then '^\s*-- FICHA PAGA( B)?:' else '^\s*-- FICHA PAGA B:' end as abre,
                                  case when p_f2 then '^\s*-- FICHA PAGA( B)?: fim' else '^\s*-- FICHA PAGA B: fim' end as fim) x) y
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
$f$;
-- O replay com o gestor ligado (o ligar de qui 29/10 16:46), o Lenine e o Vanderlei pela estimativa (como a 7a P11) e o João na rotina.
create function pg_temp.fixtures() returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
begin
  execute current_setting('agenda_teste.replay2910');
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  update public.payees set phone = '5547900000004' where name = 'João' and phone is null;
  update public.agenda_config
     set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado',
         modo_vaga_fechamento = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03',
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id;
  v_p := public.agenda_propor('os', null, null, array[pg_temp.os('OS-00069'), pg_temp.os('OS-00074')], '{}'::jsonb, true, 'vigia',
                              null, date '2026-10-29', timestamptz '2026-10-29 16:52-03');
  v_p := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-10-29',
                               timestamptz '2026-10-29 16:52-03');
  -- o João na rotina (no replay ele não está): a ficha de ter 03/11 é dele
  insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
  values (pg_temp.pessoa('João'), true, 'dono', timestamptz '2026-10-20 10:00-03')
  on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
  return v_p;
end $f$;
-- Uma conta a receber paga: o que falta para a OS ficar paga por inteiro.
create function pg_temp.pagar(p_os uuid) returns void language plpgsql as $f$
begin
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
                                  balance_amount, is_deposit)
  select gen_random_uuid(), so.client_id, so.id, 'Pago (teste da ficha paga B)', date '2026-10-20', date '2026-10-20', f.falta, 'paid', f.falta, 0, false
    from public.service_orders so,
         lateral (select so.grand_total - coalesce((select sum(coalesce(r.paid_amount, 0)) from public.receivables r
                                                     where r.service_order_id = so.id and r.status is distinct from 'cancelled'), 0) as falta) f
   where so.id = p_os;
end $f$;
-- O status gravado direto (só para a leitura: a porta da OS faria mais coisas) e o check-in.
create function pg_temp.status(p_os uuid, p_status text, p_check_in timestamptz default null) returns void language plpgsql as $f$
begin
  alter table public.service_orders disable trigger user;
  update public.service_orders set status = p_status, check_in_at = coalesce(p_check_in, check_in_at) where id = p_os;
  alter table public.service_orders enable trigger user;
end $f$;
-- Mexe na alocação vigente de uma pessoa num dia (turno opcional) sem os gatilhos: a OS, o resultado, o estado, o tipo, a fonte.
create function pg_temp.aloc(p_os uuid, p_dia date, p_set text, p_payee uuid default null, p_turno text default null) returns int language plpgsql as $f$
declare
  v_n int;
begin
  alter table public.agenda_alocacoes disable trigger user;
  execute format('update public.agenda_alocacoes set %s where service_order_id = $1 and dia = $2 and estado in (''publicada'', ''fixada'')
                    and ($3 is null or payee_id = $3) and ($4 is null or turno = $4)', p_set)
    using p_os, p_dia, p_payee, p_turno;
  get diagnostics v_n = row_count;
  alter table public.agenda_alocacoes enable trigger user;
  return v_n;
end $f$;
-- As mensagens à equipe de uma pessoa: "tipo dia estado/motivo [leva]".
create function pg_temp.equipe(p_payee uuid) returns text language sql stable as $f$
  select string_agg(format('%s %s %s%s', m.tipo, m.dia, m.estado || coalesce('/' || m.recusa_motivo, ''),
                           coalesce(' leva ' || m.leva_ficha_de, '')), ' | ' order by m.dia, m.criada_em, m.tipo)
    from public.agenda_equipe_mensagens m where m.payee_id = p_payee and m.modo = 'ligado'
$f$;
-- A ação ao dono da ficha segurada de uma pessoa: "texto [por]".
create function pg_temp.acao(p_payee uuid) returns text language sql stable as $f$
  select string_agg(a.texto || ' [' || coalesce(a.depois ->> 'por', '-') || ']', ' | ' order by a.criada_em)
    from public.agenda_acoes a where a.tipo = 'equipe' and a.origem = 'vigia' and a.payee_id = p_payee and a.depois ->> 'motivo' = 'ficha_segurada'
$f$;

-- O texto sem os blocos "-- FICHA PAGA C: … -- FICHA PAGA C: fim" (contados por nível).
create function pg_temp.sem_c(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FICHA PAGA C:' and l !~ '^\s*-- FICHA PAGA C: fim' then 1
                                                when l ~ '^\s*-- FICHA PAGA C: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FICHA PAGA C: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;

-- ── C0. A porta e o que é (sem fixture; roda também em produção depois de aplicar) ───────────────────────────────────
do $c0$
declare
  v_res jsonb := '[]'::jsonb;
  v     text;
  v_c   text;
begin
  select replace(p.prosrc, E'\r\n', E'\n'), obj_description(p.oid, 'pg_proc') into v, v_c
    from pg_proc p where p.oid = 'public._agenda_rotina_como_foi(date, timestamptz)'::regprocedure;
  v_res := pg_temp.ok(v_res, 'C0a a porta de antes: invoker, volátil, search_path fixo, só o dono do banco (nem anon, nem PUBLIC, nem authenticated, nem service_role)',
    (select not p.prosecdef and p.provolatile = 'v' and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
       from pg_proc p where p.oid = 'public._agenda_rotina_como_foi(date, timestamptz)'::regprocedure)
    and not has_function_privilege('anon', 'public._agenda_rotina_como_foi(date, timestamptz)', 'execute')
    and not has_function_privilege('public', 'public._agenda_rotina_como_foi(date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public._agenda_rotina_como_foi(date, timestamptz)', 'execute')
    and not has_function_privilege('service_role', 'public._agenda_rotina_como_foi(date, timestamptz)', 'execute'), null);
  v_res := pg_temp.ok(v_res, 'C0b a F2c só acrescenta: sem o bloco "-- FICHA PAGA C:" (1) a _agenda_rotina_como_foi é a de produção (d3e8b6f7), byte a byte; só ela tem blocos C',
    md5(pg_temp.sem_c(v)) = 'd3e8b6f77ecef723fd4a529979ea338f' and (select count(*) from regexp_matches(v, '-- FICHA PAGA C: fim', 'g')) = 1
    and (select string_agg(p.proname, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%-- FICHA PAGA C:%') = '_agenda_rotina_como_foi',
    md5(pg_temp.sem_c(v)));
  v_res := pg_temp.ok(v_res, 'C0c o comentário de produção inteiro (603f6272) e o "FICHA PAGA C (18/11/2026, 20270127100000…" no fim',
    md5(split_part(v_c, ' FICHA PAGA C (18/11/2026, 20270127100000', 1)) = '603f62726e6cea8372be20c1d9afab08' and v_c like '% FICHA PAGA C (18/11/2026, 20270127100000%',
    md5(split_part(v_c, ' FICHA PAGA C (18/11/2026, 20270127100000', 1)));
  perform pg_temp.gravar(v_res);
end
$c0$;

-- ── C1 a C8. Com o replay de 29/10 ──────────────────────────────────────────────────────────────────────
do $cx$
declare
  v_res   jsonb := '[]'::jsonb;
  c_s30   constant date := date '2026-10-30';
  c_t03   constant date := date '2026-11-03';
  c_q04   constant date := date '2026-11-04';
  v_len   uuid;
  v_joao  uuid;
  v_adm   uuid;
  r       jsonb;
  r2      jsonb;
  v_t     text;
  v_t2    text;
  v_n     int;
  v_n2    int;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('C1 a C8 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.fixtures();
    v_len := pg_temp.os('OS-00074');
    v_joao := pg_temp.pessoa('João');
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;

    -- C1 (era o C3 da revisão da v2, o B9a da F2b v3) fora da janela, a OS paga, o dia 1 segurado (sem *mande*): sem o "como foi" de 03/11, o
    -- "ok" do João não vira prova e a ficha do dia 2 fica (recusada, veto)
    begin
      perform pg_temp.pagar(v_len);
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:30'));
      perform public._agenda_rotina_confirmar(c_t03, pg_temp.em(c_t03, '07:45'));
      r := public._agenda_gestor_fichas(c_t03, pg_temp.em(c_t03, '16:52'));
      r := public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      r2 := public.agenda_resposta_da_equipe('5547900000004', 'ok', 'wa-f2c-c1', pg_temp.em(c_t03, '17:30'));
      perform public._agenda_rotina_ficha(c_t03, pg_temp.em(c_t03, '19:30'));
      v_t := pg_temp.equipe(v_joao);
      v_t2 := 'comecou(04/11)=' || public._agenda_os_comecou(v_len, c_q04);
      v_res := pg_temp.ok(v_res, 'C1 (o C3 da revisão) o dia 1 segurado não recebe o "como foi"; o "ok" não vira prova e a ficha do dia 2 fica (recusada, veto)',
        v_t = 'ficha 2026-11-03 recusada/veto | confirmar 2026-11-03 recusada/veto | ficha 2026-11-04 recusada/veto' and v_t2 = 'comecou(04/11)=false'
        and not exists (select 1 from public.agenda_equipe_mensagens m where m.payee_id = v_joao and m.tipo = 'como_foi'),
        coalesce(v_t, '-') || ' | ' || v_t2 || ' | ' || r::text || ' | ' || coalesce(r2::text, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- C2 (era o C5) o "ok" às 19:45 e a confirmação da manhã do dia 2: sem o "como foi", nenhuma prova; a confirmação de 04/11 também fica
    begin
      perform pg_temp.pagar(v_len);
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:30'));
      perform public._agenda_rotina_confirmar(c_t03, pg_temp.em(c_t03, '07:45'));
      r := public._agenda_gestor_fichas(c_t03, pg_temp.em(c_t03, '16:52'));
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      perform public._agenda_rotina_ficha(c_t03, pg_temp.em(c_t03, '19:30'));
      r2 := public.agenda_resposta_da_equipe('5547900000004', 'ok', 'wa-f2c-c2', pg_temp.em(c_t03, '19:45'));
      perform public._agenda_rotina_confirmar(c_q04, pg_temp.em(c_q04, '07:45'));
      v_t := pg_temp.equipe(v_joao);
      v_res := pg_temp.ok(v_res, 'C2 (o C5 da revisão) sem o "como foi", o "ok" das 19:45 não vira prova: a ficha e a confirmação do dia 2 ficam (recusada, veto)',
        v_t = 'ficha 2026-11-03 recusada/veto | confirmar 2026-11-03 recusada/veto | ficha 2026-11-04 recusada/veto | confirmar 2026-11-04 recusada/veto'
        and not public._agenda_os_comecou(v_len, c_q04),
        coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- C3 a ficha liberada (fora da janela, sem OS paga): o "como foi" de sempre
    begin
      update public.agenda_config set marcar_sozinho_desde = null where id;
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:30'));
      perform public._agenda_rotina_confirmar(c_t03, pg_temp.em(c_t03, '07:45'));
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      v_t := pg_temp.equipe(v_joao);
      v_res := pg_temp.ok(v_res, 'C3 com a ficha liberada (enfileirada) e a confirmação saída, o "como foi" sai como antes',
        v_t like 'ficha 2026-11-03 enfileirada | confirmar 2026-11-03 enfileirada | como_foi 2026-11-03 enfileirada%', coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- C4 a ficha recusada por veto, mas a confirmação da manhã saiu (o plano chegou de manhã): o "como foi" sai como antes
    begin
      perform pg_temp.pagar(v_len);
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:30'));
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em)
      values (v_joao, c_t03, 'confirmar', 'ligado', 'Confirmação de teste da ficha paga C', pg_temp.em(c_t03, '07:45'), 'enfileirada',
              'teste-f2c:confirmar:' || v_joao || ':' || c_t03, pg_temp.em(c_t03, '07:45'));
      alter table public.agenda_equipe_mensagens enable trigger user;
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      v_t := pg_temp.equipe(v_joao);
      v_res := pg_temp.ok(v_res, 'C4 a ficha recusada por veto mas a confirmação da manhã saiu: o "como foi" sai como antes',
        v_t like 'ficha 2026-11-03 recusada/veto | confirmar 2026-11-03 enfileirada | como_foi 2026-11-03 %', coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- C5 a ficha recusada por OUTRO motivo (o teto), sem confirmação: o "como foi" sai como antes (só o veto conta)
    begin
      update public.agenda_config set marcar_sozinho_desde = null where id;
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key, criada_em)
      values (v_joao, c_t03, 'ficha', 'ligado', 'Ficha de teste da ficha paga C', pg_temp.em(c_s30, '19:30'), 'recusada', 'teto',
              'teste-f2c:ficha:' || v_joao || ':' || c_t03, pg_temp.em(c_s30, '19:30'));
      alter table public.agenda_equipe_mensagens enable trigger user;
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      v_t := pg_temp.equipe(v_joao);
      v_res := pg_temp.ok(v_res, 'C5 a ficha recusada pelo teto (não por veto): o "como foi" sai como antes',
        v_t like 'ficha 2026-11-03 recusada/teto | como_foi 2026-11-03 %', coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- C5b a ficha recusada por OUTRO motivo, sem telefone (o motivo que já apareceu em produção), sem confirmação: o "como foi" sai como antes
    -- (só o veto conta; da revisão independente da F2c: mata o MR9, "qualquer recusa menos o teto")
    begin
      update public.agenda_config set marcar_sozinho_desde = null where id;
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key, criada_em)
      values (v_joao, c_t03, 'ficha', 'ligado', 'Ficha de teste da ficha paga C', pg_temp.em(c_s30, '19:30'), 'recusada', 'sem_telefone',
              'teste-f2c:ficha:' || v_joao || ':' || c_t03, pg_temp.em(c_s30, '19:30'));
      alter table public.agenda_equipe_mensagens enable trigger user;
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      v_t := pg_temp.equipe(v_joao);
      v_res := pg_temp.ok(v_res, 'C5b a ficha recusada sem telefone (não por veto): o "como foi" sai como antes',
        v_t like 'ficha 2026-11-03 recusada/sem_telefone | como_foi 2026-11-03 %', coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- C6 a ficha saiu e só a confirmação da manhã foi recusada por veto (a OS encerrada de madrugada): o "como foi" sai como antes (o plano
    -- chegou na véspera)
    begin
      update public.agenda_config set marcar_sozinho_desde = null where id;
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em)
      values (v_joao, c_t03, 'ficha', 'ligado', 'Ficha de teste da ficha paga C', pg_temp.em(c_s30, '19:30'), 'enfileirada',
              'teste-f2c:ficha:' || v_joao || ':' || c_t03, pg_temp.em(c_s30, '19:30'));
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key, criada_em)
      values (v_joao, c_t03, 'confirmar', 'ligado', 'Confirmação de teste da ficha paga C', pg_temp.em(c_t03, '07:45'), 'recusada', 'veto',
              'teste-f2c:confirmar:' || v_joao || ':' || c_t03, pg_temp.em(c_t03, '07:45'));
      alter table public.agenda_equipe_mensagens enable trigger user;
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      v_t := pg_temp.equipe(v_joao);
      v_res := pg_temp.ok(v_res, 'C6 a ficha saiu e só a confirmação foi recusada por veto: o "como foi" sai como antes',
        v_t like 'ficha 2026-11-03 enfileirada | confirmar 2026-11-03 recusada/veto | como_foi 2026-11-03 %', coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- C7 com a mensagem à equipe em teste (sombra), mesmo com uma ficha ligada recusada por veto no dia: o "como foi" é registrado como antes
    begin
      update public.agenda_config set marcar_sozinho_desde = null, modo_equipe = 'sombra' where id;
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key, criada_em)
      values (v_joao, c_t03, 'ficha', 'ligado', 'Ficha de teste da ficha paga C', pg_temp.em(c_s30, '19:30'), 'recusada', 'veto',
              'teste-f2c:ficha:' || v_joao || ':' || c_t03, pg_temp.em(c_s30, '19:30'));
      alter table public.agenda_equipe_mensagens enable trigger user;
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      v_n := (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = v_joao and m.tipo = 'como_foi' and m.dia = c_t03 and m.modo = 'sombra');
      v_res := pg_temp.ok(v_res, 'C7 em teste (sombra) o "como foi" é registrado como antes, mesmo com a ficha ligada recusada por veto',
        public._agenda_modo_da_equipe() = 'sombra' and v_n = 1, format('modo=%s como_foi_sombra=%s', public._agenda_modo_da_equipe(), v_n));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- C8 nenhuma mensagem nova: o dia segurado sem "como foi" não gera mensagem nem pergunta (nem a vigia do "sem registro" depois)
    begin
      perform pg_temp.pagar(v_len);
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      r := public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:30'));
      perform public._agenda_rotina_confirmar(c_t03, pg_temp.em(c_t03, '07:45'));
      v_n := (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = v_joao);
      v_n2 := (select count(*) from public.agenda_perguntas q);
      r := public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      perform set_config('agenda.hoje', '2026-11-10', true);  -- o dia de quem age (o gatilho só aceita resultado de dia que já chegou)
      r2 := public._agenda_vigia_sem_registro(date '2026-11-10', pg_temp.em(date '2026-11-10', '08:00'));
      v_res := pg_temp.ok(v_res, 'C8 o dia segurado sem "como foi" não gera mensagem nem pergunta nova (o "como foi" pula; a vigia só marca sem_registro)',
        (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = v_joao) = v_n
        and (select count(*) from public.agenda_perguntas q) = v_n2
        and not exists (select 1 from public.agenda_equipe_mensagens m where m.payee_id = v_joao and m.tipo = 'como_foi'),
        format('msgs %s -> %s; perguntas %s -> %s; como_foi=%s; vigia=%s', v_n, (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = v_joao),
               v_n2, (select count(*) from public.agenda_perguntas q), r, r2));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then
    v_res := pg_temp.ok(v_res, 'C1-C8 sem erro', false, sqlstate || ': ' || sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$cx$;

-- ── Casos extra da revisão (força dos testes): cada um mira um mutante que sobrevive aos C1–C8 e ao B9a/B9b ──────────────────
--   XC1 (MR1) a ficha vetada e NENHUMA linha de confirmar (disponibilidade confirmada: a rotina da manhã pula): sem "como foi"
--   XC2 (MR2, o caso do Alex) a ficha vetada e uma confirmação de OUTRO dia que saiu (sem_resposta): sem "como foi"
--   XC3 (MR3) a ficha de hoje saiu, só a confirmação recusada, e uma ficha vetada de OUTRO dia: o "como foi" de sempre
--   XC4 (MR4) duas pessoas: o João vetado; o Roberto com a ficha saída e a confirmação recusada: o Roberto recebe o "como foi"
--   XC5 (MR5) duas pessoas: o João vetado; o Roberto com a confirmação saída: o João continua sem "como foi"
--   XC6 (MR6) a ficha vetada e a confirmação saída no estado REAL das 17:00 (sem_resposta): o "como foi" de sempre
do $xc$
declare
  v_res   jsonb := '[]'::jsonb;
  c_s30   constant date := date '2026-10-30';
  c_t03   constant date := date '2026-11-03';
  v_len   uuid;
  v_joao  uuid;
  v_rob   uuid;
  v_t     text;
  v_n     int;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('XC (o replay de 29/10)', true, 'PULADO: rode pela bancada');
    return;
  end if;
  begin
    perform pg_temp.fixtures();
    v_len := pg_temp.os('OS-00074');
    v_joao := pg_temp.pessoa('João');
    v_rob := pg_temp.pessoa('Roberto');

    -- XC1 (MR1) a ficha vetada pelo caminho de verdade e a disponibilidade confirmada do dia (a rotina da manhã não cria a linha de confirmar)
    begin
      perform pg_temp.pagar(v_len);
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      perform public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:30'));
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem)
      values (v_joao, daterange(c_t03, c_t03 + 1, '[)'), 'confirmada', 'dono');
      perform public._agenda_rotina_confirmar(c_t03, pg_temp.em(c_t03, '07:45'));
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      v_t := pg_temp.equipe(v_joao);
      v_res := pg_temp.ok(v_res, 'XC1 (MR1) a ficha vetada e nenhuma linha de confirmar (disponibilidade confirmada): sem "como foi"',
        v_t = 'ficha 2026-11-03 recusada/veto', coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- XC2 (MR2; o caso do Alex: ele tem confirmação de dia anterior que saiu) a ficha vetada pelo caminho de verdade e uma confirmação de
    -- sex 30/10 que saiu (sem_resposta)
    begin
      perform pg_temp.pagar(v_len);
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em)
      values (v_joao, c_s30, 'confirmar', 'ligado', 'Confirmação de outro dia (revisão F2c)', pg_temp.em(c_s30, '07:45'), 'sem_resposta',
              'rev-f2c:confirmar:' || v_joao || ':' || c_s30, pg_temp.em(c_s30, '07:45'));
      alter table public.agenda_equipe_mensagens enable trigger user;
      perform public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:30'));
      perform public._agenda_rotina_confirmar(c_t03, pg_temp.em(c_t03, '07:45'));
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      v_t := pg_temp.equipe(v_joao);
      v_res := pg_temp.ok(v_res, 'XC2 (MR2, o caso do Alex) a ficha vetada e uma confirmação de OUTRO dia que saiu: sem "como foi"',
        v_t = 'confirmar 2026-10-30 sem_resposta | ficha 2026-11-03 recusada/veto | confirmar 2026-11-03 recusada/veto', coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- XC3 (MR3) a ficha de hoje saiu, só a confirmação recusada por veto (o C6), e uma ficha vetada de OUTRO dia (sex 30/10)
    begin
      update public.agenda_config set marcar_sozinho_desde = null where id;
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key, criada_em)
      values (v_joao, c_s30, 'ficha', 'ligado', 'Ficha vetada de outro dia (revisão F2c)', pg_temp.em(c_s30 - 1, '19:30'), 'recusada', 'veto',
              'rev-f2c:ficha:' || v_joao || ':' || c_s30, pg_temp.em(c_s30 - 1, '19:30')),
             (v_joao, c_t03, 'ficha', 'ligado', 'Ficha de teste (revisão F2c)', pg_temp.em(c_s30, '19:30'), 'enfileirada', null,
              'rev-f2c:ficha:' || v_joao || ':' || c_t03, pg_temp.em(c_s30, '19:30')),
             (v_joao, c_t03, 'confirmar', 'ligado', 'Confirmação de teste (revisão F2c)', pg_temp.em(c_t03, '07:45'), 'recusada', 'veto',
              'rev-f2c:confirmar:' || v_joao || ':' || c_t03, pg_temp.em(c_t03, '07:45'));
      alter table public.agenda_equipe_mensagens enable trigger user;
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      v_t := pg_temp.equipe(v_joao);
      v_res := pg_temp.ok(v_res, 'XC3 (MR3) a ficha de hoje saiu e há uma ficha vetada de OUTRO dia: o "como foi" de sempre',
        v_t like '%ficha 2026-11-03 enfileirada | confirmar 2026-11-03 recusada/veto | como_foi 2026-11-03 %', coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- XC4 e XC5: o Roberto também em ter 03/11 (a alocação do João copiada para ele, sem os gatilhos) e na rotina
    for v_n in 4 .. 5 loop
      begin
        update public.agenda_config set marcar_sozinho_desde = null where id;
        alter table public.agenda_alocacoes disable trigger user;
        insert into public.agenda_alocacoes
        select (jsonb_populate_record(null::public.agenda_alocacoes, to_jsonb(a) || jsonb_build_object('id', gen_random_uuid(), 'payee_id', v_rob))).*
          from public.agenda_alocacoes a where a.payee_id = v_joao and a.dia = c_t03 and a.estado in ('publicada', 'fixada');
        alter table public.agenda_alocacoes enable trigger user;
        insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
        values (v_rob, true, 'dono', timestamptz '2026-10-20 10:00-03')
        on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
        alter table public.agenda_equipe_mensagens disable trigger user;
        insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key, criada_em)
        values (v_joao, c_t03, 'ficha', 'ligado', 'Ficha de teste (revisão F2c)', pg_temp.em(c_s30, '19:30'), 'recusada', 'veto',
                'rev-f2c:ficha:' || v_joao || ':' || c_t03, pg_temp.em(c_s30, '19:30')),
               (v_joao, c_t03, 'confirmar', 'ligado', 'Confirmação de teste (revisão F2c)', pg_temp.em(c_t03, '07:45'), 'recusada', 'veto',
                'rev-f2c:confirmar:' || v_joao || ':' || c_t03, pg_temp.em(c_t03, '07:45')),
               (v_rob, c_t03, 'ficha', 'ligado', 'Ficha de teste (revisão F2c)', pg_temp.em(c_s30, '19:30'), 'enfileirada', null,
                'rev-f2c:ficha:' || v_rob || ':' || c_t03, pg_temp.em(c_s30, '19:30')),
               (v_rob, c_t03, 'confirmar', 'ligado', 'Confirmação de teste (revisão F2c)', pg_temp.em(c_t03, '07:45'),
                case when v_n = 4 then 'recusada' else 'sem_resposta' end, case when v_n = 4 then 'veto' end,
                'rev-f2c:confirmar:' || v_rob || ':' || c_t03, pg_temp.em(c_t03, '07:45'));
        alter table public.agenda_equipe_mensagens enable trigger user;
        perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
        v_t := 'joao: ' || coalesce(pg_temp.equipe(v_joao), '-') || ' || roberto: ' || coalesce(pg_temp.equipe(v_rob), '-');
        v_res := pg_temp.ok(v_res,
          case when v_n = 4 then 'XC4 (MR4) o João vetado não tira o "como foi" do Roberto (ficha saída, confirmação recusada)'
               else 'XC5 (MR5) a confirmação saída do Roberto não devolve o "como foi" ao João vetado' end,
          (select count(*) from public._agenda_contatos_com_plano(c_t03)) = 2
          and not exists (select 1 from public.agenda_equipe_mensagens m where m.payee_id = v_joao and m.tipo = 'como_foi')
          and exists (select 1 from public.agenda_equipe_mensagens m where m.payee_id = v_rob and m.tipo = 'como_foi' and m.dia = c_t03 and m.modo = 'ligado'),
          v_t);
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
    end loop;

    -- XC6 (MR6) a ficha vetada pelo caminho de verdade e a confirmação da manhã saída, no estado que ela tem às 17:00 em produção (sem_resposta)
    begin
      perform pg_temp.pagar(v_len);
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      perform public._agenda_gestor_fichas(c_s30, pg_temp.em(c_s30, '16:52'));
      perform public._agenda_rotina_ficha(c_s30, pg_temp.em(c_s30, '19:30'));
      alter table public.agenda_equipe_mensagens disable trigger user;
      insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em)
      values (v_joao, c_t03, 'confirmar', 'ligado', 'Confirmação de teste (revisão F2c)', pg_temp.em(c_t03, '07:45'), 'sem_resposta',
              'rev-f2c:confirmar:' || v_joao || ':' || c_t03, pg_temp.em(c_t03, '07:45'));
      alter table public.agenda_equipe_mensagens enable trigger user;
      perform public._agenda_rotina_como_foi(c_t03, pg_temp.em(c_t03, '17:00'));
      v_t := pg_temp.equipe(v_joao);
      v_res := pg_temp.ok(v_res, 'XC6 (MR6) a ficha vetada e a confirmação saída em sem_resposta (o estado real às 17:00): o "como foi" de sempre',
        v_t like 'ficha 2026-11-03 recusada/veto | confirmar 2026-11-03 sem_resposta | como_foi 2026-11-03 %', coalesce(v_t, '-'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then
    v_res := pg_temp.ok(v_res, 'XC sem erro', false, sqlstate || ': ' || sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$xc$;

select teste, ok, detalhe from _resultado order by ok, teste;
rollback;
