-- Retorno F1 (P7): o gatilho da fila em modo "conta" (trg_whatsapp_send_queue_retorno_conta).
-- Só conta, nunca recusa: cada linha nova da fila vira UMA linha 'contada' em retorno_saidas, com
-- recusaria = true só na linha AUTOMÁTICA a cliente, ambíguo ou número novo de fonte fora da lista fechada;
-- a linha da fila fica como os gatilhos BEFORE a deixaram, inclusive com fila_modo = 'trava'. Erro dentro do
-- gatilho é engolido e registrado; os resultados de retorno_f0a_canal_bloqueado.sql (mesmas fontes e
-- telefones) não mudam; modo 'desligado' ou sem a linha de configuração não conta nada.
-- Cadastros SINTÉTICOS (nenhum cadastro real é alterado); a linha de retorno_config só muda dentro do
-- arranjo. Telefones de teste 55479000097xx e, no caso 4, os da F0a (55479000070xx, 5547900007999).
-- Run (só pela bancada, fora do pico: P15): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_fila.sql
-- Termina em ROLLBACK: nada fica gravado. Todo o arranjo é desfeito dentro do arquivo (sub-bloco que termina
-- em 'desfaz'), inclusive a constraint que força o erro do caso 5.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- A contagem de uma linha da fila: quantas linhas em retorno_saidas e a primeira delas, inteira.
create or replace function pg_temp.retorno_f1_fila_contagem(p_fila uuid) returns jsonb
language sql as $f$
  select jsonb_build_object('n', count(*), 'linha', coalesce(jsonb_agg(to_jsonb(s)) -> 0, 'null'::jsonb))
    from public.retorno_saidas s
   where s.fila_id = p_fila
$f$;

-- Confere a linha contada de uma linha da fila (levanta '<caso>: …' na 1ª diferença) e devolve 1, para quem
-- chama somar as conferidas.
create or replace function pg_temp.retorno_f1_fila_confere(p_caso text, p_fila uuid, p_fonte text, p_recusaria boolean,
                                                          p_papeis text[], p_status text, p_fila_modo text)
returns integer
language plpgsql as $f$
declare
  v_c jsonb := pg_temp.retorno_f1_fila_contagem(p_fila);
  v_s jsonb := v_c -> 'linha';
  v_q public.whatsapp_send_queue;
begin
  select * into v_q from public.whatsapp_send_queue q where q.id = p_fila;
  if not found then
    raise exception '%: a linha da fila (%) não existe (o insert foi descartado ou recusado)', p_caso, p_fonte;
  end if;
  if (v_c ->> 'n')::int <> 1 then
    raise exception '%: a linha da fila (%) foi contada % vezes', p_caso, p_fonte, v_c ->> 'n';
  end if;
  if v_s ->> 'emissor' is distinct from 'fila' or v_s ->> 'tipo' is distinct from 'fila'
     or v_s ->> 'estado' is distinct from 'contada' or v_s ->> 'modo' is distinct from 'sombra'
     or v_s ->> 'fila_source' is distinct from p_fonte
     or v_s ->> 'dedupe_key' is distinct from ('fila:' || p_fila::text)
     or v_s ->> 'phone_normalized' is distinct from v_q.phone_normalized
     or v_s ->> 'chave' is distinct from coalesce(public._agenda_chave_telefone(v_q.phone_normalized), '00000000')
     or (v_s ->> 'enviar_em')::timestamptz is distinct from v_q.scheduled_for
     or (v_s ->> 'decidida_em')::timestamptz is distinct from now()
     or v_s ->> 'abertura_id' is not null or v_s ->> 'client_id' is not null or v_s ->> 'texto' is not null
     or v_s ->> 'enviada_em' is not null then
    raise exception '%: a linha contada saiu do molde (emissor, tipo, estado, modo, chave, horas): %', p_caso, v_s;
  end if;
  if (v_s -> 'recusaria') is distinct from to_jsonb(p_recusaria)
     or v_s ->> 'motivo' is distinct from (case when p_recusaria then 'recusaria_fila' end) then
    raise exception '%: % deveria dar recusaria = % (veio %, motivo %)', p_caso, p_fonte, p_recusaria,
      v_s -> 'recusaria', v_s ->> 'motivo';
  end if;
  if jsonb_typeof(v_s -> 'dados') is distinct from 'object'
     or (select array_agg(k order by k collate "C") from jsonb_object_keys(v_s -> 'dados') k)
          is distinct from array['fila_modo', 'papel', 'status']
     or not coalesce((v_s -> 'dados' ->> 'papel') = any (p_papeis), false)
     or v_s -> 'dados' ->> 'status' is distinct from p_status
     or v_s -> 'dados' ->> 'fila_modo' is distinct from p_fila_modo then
    raise exception '%: dados da linha contada errados (papel em %, status %, fila_modo %): %', p_caso, p_papeis,
      p_status, p_fila_modo, v_s -> 'dados';
  end if;
  return 1;
end $f$;

do $fila$
declare
  -- as fontes reais da fila em 120 dias (seção 2.2, mais me_acorde, que apareceu na conferência de 01/11), menos
  -- agenda-dono, que só a agenda grava
  c_fontes_reais constant text[] := array['ai_monitor', 'ai_briefing', 'ai_agent', 'balance_escalation', 'ai_followup',
                                          'ai_briefing_tarde', 'resumo_nao_chegou', 'email_urgente', 'diagnostico',
                                          'me_acorde'];
  v_f record;
  v_dono text;
  v_modo_antes text;
  v_fila_modo_antes text;
  v_chegou boolean := false;
  v_c_cliente uuid; v_c_amb_a uuid; v_c_amb_b uuid; v_forn uuid; v_payee uuid; v_c_final uuid; v_c_opt uuid;
  v_ids uuid[] := '{}';
  v_id uuid;
  v_status text;
  v_motivo text;
  v_fonte text;
  v_det text;
  v_c jsonb;
  v_lote_ids uuid[];
  v_lote_fontes text[];
  v_lote_status text[];
  v_i int;
  v_agenda_sqlstate text;
  v_conf int := 0;
  v_n_contadas bigint;
  v_n_recusaria bigint;
  -- caso 5 (erro forçado)
  v5_id uuid;
  v5_status text;
  v5_existe boolean := false;
  v5_contada boolean := true;
  v5_log jsonb;
  v5_erro text;
  v5_passo text;
  v5_chegou boolean := false;
begin
  -- ── 0. O gatilho e a função ──────────────────────────────────────────────────────────────────────────
  -- AFTER INSERT, por linha, sem WHEN e ligado (vê a linha depois de todos os BEFORE e não pode recusar);
  -- só ele usa a função; a função é SECURITY DEFINER com search_path e lock_timeout de 1 s (espera não trava a fila), e
  -- anon/authenticated não executam.
  select t.tgtype, t.tgenabled::text as ligado, t.tgqual is null as sem_when, t.tgfoid into v_f
    from pg_trigger t
   where t.tgrelid = 'public.whatsapp_send_queue'::regclass and t.tgname = 'trg_whatsapp_send_queue_retorno_conta';
  if not found then
    raise exception '0: o gatilho trg_whatsapp_send_queue_retorno_conta não existe';
  end if;
  if v_f.tgtype <> 5 or v_f.ligado <> 'O' or not v_f.sem_when
     or v_f.tgfoid is distinct from to_regprocedure('public._fila_retorno_conta()')::oid then
    raise exception '0a: o gatilho não é AFTER INSERT por linha, ligado, sem WHEN, com _fila_retorno_conta (tgtype %, %)',
      v_f.tgtype, v_f.ligado;
  end if;
  if (select count(*) from pg_trigger t where t.tgfoid = to_regprocedure('public._fila_retorno_conta()')::oid) <> 1 then
    raise exception '0b: _fila_retorno_conta é usada por outro gatilho';
  end if;
  select p.prosecdef, coalesce(p.proconfig, '{}') as config, p.prorettype = 'trigger'::regtype::oid as de_gatilho into v_f
    from pg_proc p where p.oid = to_regprocedure('public._fila_retorno_conta()');
  if not found then
    raise exception '0c: _fila_retorno_conta não existe';
  end if;
  if not v_f.prosecdef or not ('search_path=public' = any (v_f.config)) or not ('lock_timeout=1s' = any (v_f.config))
     or not v_f.de_gatilho then
    raise exception '0c: _fila_retorno_conta não é função de gatilho SECURITY DEFINER com search_path = public e lock_timeout = 1s (%)',
      v_f.config;
  end if;
  if has_function_privilege('anon', 'public._fila_retorno_conta()', 'execute')
     or has_function_privilege('authenticated', 'public._fila_retorno_conta()', 'execute') then
    raise exception '0d: _fila_retorno_conta aberta a anon/authenticated';
  end if;

  -- O valor de hoje da configuração: o arranjo devolve a ele.
  select c.modo, c.fila_modo into v_modo_antes, v_fila_modo_antes from public.retorno_config c where c.id;
  if not found then
    raise exception '0e: retorno_config sem a linha de configuração';
  end if;

  -- O telefone do dono (o mesmo de donoDoWhatsApp); sem ele, o 1º admin ativo com telefone.
  v_dono := coalesce((select d.phone from public._comprovante_dono() d),
                     (select u.phone_normalized from public.app_users u
                       where u.active and u.phone_normalized is not null order by u.created_at limit 1));
  if v_dono is null then
    raise exception '0f: sem telefone do dono para o caso 1';
  end if;
  if public.quem_escreve(v_dono) ->> 'papel' is distinct from 'equipe' then
    raise exception '0f: o telefone do dono não dá papel equipe: %', public.quem_escreve(v_dono);
  end if;

  -- A faixa 55479000097xx está livre: um arranjo deixado por outro arquivo da bancada mudaria o papel dos
  -- números de teste.
  if exists (select 1 from public.clients c
              where public._agenda_chave_telefone(c.whatsapp) like '000097%'
                 or public._agenda_chave_telefone(c.phone) like '000097%')
     or exists (select 1 from public.suppliers s where public._agenda_chave_telefone(s.phone) like '000097%')
     or exists (select 1 from public.payees p where public._agenda_chave_telefone(p.phone) like '000097%')
     or exists (select 1 from public.app_users u
                 where public._agenda_chave_telefone(u.phone) like '000097%'
                    or public._agenda_chave_telefone(u.phone_normalized) like '000097%')
     or exists (select 1 from public.whatsapp_blocked_numbers b
                 where public._agenda_chave_telefone(b.phone_normalized) like '000097%') then
    raise exception '0g: a faixa de teste 55479000097xx já tem cadastro ou bloqueio';
  end if;

  begin
    -- O arranjo: o retorno em sombra e a fila em "conta" (o valor de produção volta no 'desfaz').
    update public.retorno_config set modo = 'sombra', fila_modo = 'conta' where id;

    -- Cadastros sintéticos: cada número de teste tem só os cadastros abaixo (9703 = número novo, sem cadastro).
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 fila cliente', '(47) 90000-9701') returning id into v_c_cliente;
    insert into public.clients (type, name, phone)
      values ('individual', 'Teste F1 fila ambíguo A', '47 90000-9702') returning id into v_c_amb_a;
    insert into public.clients (type, name, whatsapp)
      values ('company', 'Teste F1 fila ambíguo B', '(47) 90000-9702') returning id into v_c_amb_b;
    insert into public.suppliers (name, phone, active)
      values ('Teste F1 fila fornecedor', '(47) 90000-9704', true) returning id into v_forn;
    insert into public.payees (name, phone)
      values ('Teste F1 fila equipe', '(47) 90000-9705') returning id into v_payee;
    -- Caso 4, com os telefones da F0a: o "Cliente Final" no 7001 e um cliente com opt-out no 7003.
    insert into public.clients (type, name, phone, generico)
      values ('individual', 'Teste F1 fila Cliente Final', '5547900007001', true) returning id into v_c_final;
    insert into public.clients (type, name, whatsapp, opt_out_whatsapp)
      values ('individual', 'Teste F1 fila opt-out', '(47) 90000-7003', true) returning id into v_c_opt;

    if public.quem_escreve('5547900009701') ->> 'papel' is distinct from 'cliente'
       or public.quem_escreve('5547900009702') ->> 'papel' is distinct from 'cliente_ambiguo'
       or public.quem_escreve('5547900009703') ->> 'papel' is distinct from 'novo'
       or public.quem_escreve('5547900009704') ->> 'papel' is distinct from 'fornecedor'
       or public.quem_escreve('5547900009705') ->> 'papel' is distinct from 'equipe' then
      raise exception '0h: o arranjo não deu os papéis esperados (cliente, ambíguo, novo, fornecedor, equipe)';
    end if;

    -- ── 1. ai_briefing ao telefone do dono: pendente; contada, sem recusaria ───────────────────────────
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values (v_dono, 'teste F1 fila 1', 'ai_briefing') returning id, status into v_id, v_status;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'pending' then
      raise exception '1: ai_briefing ao dono ficou % (devia seguir pendente)', v_status;
    end if;
    v_conf := v_conf + pg_temp.retorno_f1_fila_confere('1', v_id, 'ai_briefing', false, array['equipe'], 'pending', 'conta');

    -- 1b. As outras fontes reais, ao dono, num insert só (lote): todas pendentes e contadas, nenhuma
    --     recusaria — inclusive a ai_followup, porque vai à equipe. É o "sem recusa falsa" do G.0.
    with ins as (
      insert into public.whatsapp_send_queue (phone_normalized, message, source)
      select v_dono, 'teste F1 fila 1b ' || f, f from unnest(c_fontes_reais) f where f <> 'ai_briefing'
      returning id, source, status)
    select array_agg(ins.id order by ins.source), array_agg(ins.source order by ins.source),
           array_agg(ins.status order by ins.source)
      into v_lote_ids, v_lote_fontes, v_lote_status
      from ins;
    if coalesce(cardinality(v_lote_ids), 0) <> cardinality(c_fontes_reais) - 1 then
      raise exception '1b: o lote ao dono gravou % linhas, esperadas %', coalesce(cardinality(v_lote_ids), 0),
        cardinality(c_fontes_reais) - 1;
    end if;
    for v_i in 1 .. cardinality(v_lote_ids) loop
      v_ids := v_ids || v_lote_ids[v_i];
      if v_lote_status[v_i] is distinct from 'pending' then
        raise exception '1b: % ao dono ficou %', v_lote_fontes[v_i], v_lote_status[v_i];
      end if;
      v_conf := v_conf + pg_temp.retorno_f1_fila_confere('1b ' || v_lote_fontes[v_i], v_lote_ids[v_i], v_lote_fontes[v_i],
                                                         false, array['equipe'], 'pending', 'conta');
    end loop;

    -- ── 2. ai_followup (o cron 7) a um cliente de teste: a linha da fila continua PENDENTE (não recusou) ─
    --       e a contagem tem recusaria = true.
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('5547900009701', 'teste F1 fila 2', 'ai_followup') returning id, status into v_id, v_status;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'pending' then
      raise exception '2: ai_followup ao cliente ficou % (o gatilho novo nunca recusa)', v_status;
    end if;
    v_conf := v_conf + pg_temp.retorno_f1_fila_confere('2', v_id, 'ai_followup', true, array['cliente'], 'pending', 'conta');

    -- 2b. O resto da regra pelo papel: ambíguo e número novo recusariam; fornecedor e equipe não.
    for v_f in
      select x.fone, x.fonte, x.recusaria, x.papel
        from (values ('5547900009702', 'ai_followup', true, 'cliente_ambiguo'),
                     ('5547900009703', 'ai_monitor', true, 'novo'),
                     ('5547900009704', 'ai_followup', false, 'fornecedor'),
                     ('5547900009705', 'ai_followup', false, 'equipe')) x(fone, fonte, recusaria, papel)
    loop
      insert into public.whatsapp_send_queue (phone_normalized, message, source)
        values (v_f.fone, 'teste F1 fila 2b ' || v_f.fone, v_f.fonte) returning id, status into v_id, v_status;
      v_ids := v_ids || v_id;
      if v_status is distinct from 'pending' then
        raise exception '2b: % a % ficou %', v_f.fonte, v_f.papel, v_status;
      end if;
      v_conf := v_conf + pg_temp.retorno_f1_fila_confere('2b ' || v_f.papel, v_id, v_f.fonte, v_f.recusaria,
                                                         array[v_f.papel], 'pending', 'conta');
    end loop;

    -- ── 3. O que alguém pediu (ai_agent, manual, on-my-way, quote_request) ao cliente: recusaria = false ─
    --       Também o que o dono aprova antes de ir à fila (revisao-plano, ai_followup_mission): são fontes raras, e a
    --       semana do G.0 pode passar sem nenhuma delas.
    foreach v_fonte in array array['ai_agent', 'manual', 'on-my-way', 'quote_request', 'revisao-plano',
                                   'ai_followup_mission'] loop
      insert into public.whatsapp_send_queue (phone_normalized, message, source)
        values ('5547900009701', 'teste F1 fila 3 ' || v_fonte, v_fonte) returning id, status into v_id, v_status;
      v_ids := v_ids || v_id;
      if v_status is distinct from 'pending' then
        raise exception '3: % ao cliente ficou %', v_fonte, v_status;
      end if;
      v_conf := v_conf + pg_temp.retorno_f1_fila_confere('3 ' || v_fonte, v_id, v_fonte, false, array['cliente'],
                                                         'pending', 'conta');
    end loop;
    -- 3b. Uma fonte agenda-* que entra direto na fila (sem gatilho da agenda na entrada): nunca recusaria.
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('5547900009701', 'teste F1 fila 3b', 'agenda-confirmacao') returning id, status into v_id, v_status;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'pending' then
      raise exception '3b: agenda-confirmacao ao cliente ficou %', v_status;
    end if;
    v_conf := v_conf + pg_temp.retorno_f1_fila_confere('3b', v_id, 'agenda-confirmacao', false, array['cliente'],
                                                       'pending', 'conta');

    -- ── 4. A F0a intacta (retorno_f0a_canal_bloqueado.sql, mesmas fontes e telefones) ────────────────────
    --       O gatilho novo não muda nenhum resultado (uma linha que um BEFORE recusa nunca chega ao AFTER).
    -- 4a. (F0a 7a) on-my-way e quote_request ao "Cliente Final": recusa 23514 com detail sem_telefone.
    foreach v_fonte in array array['on-my-way', 'quote_request'] loop
      v_det := null;
      begin
        insert into public.whatsapp_send_queue (phone_normalized, message, source)
          values ('5547900007001', 'teste F1 fila 4a ' || v_fonte, v_fonte);
      exception when sqlstate '23514' then
        get stacked diagnostics v_det = pg_exception_detail;
      end;
      if v_det is distinct from 'sem_telefone' then
        raise exception '4a: % ao Cliente Final não foi recusada com 23514/sem_telefone (detail %)', v_fonte, v_det;
      end if;
    end loop;
    -- 4b. agenda-cliente gravada direto ao "Cliente Final": o gatilho da agenda (trg_agenda_fila_do_cliente, que dispara
    --     antes do da F0a pela ordem alfabética) barra com 42501 o que ela não registrou. Igual a antes do P7.
    --     O 23514 da F0a à agenda-cliente não se alcança por insert direto: só pelo _agenda_cliente_enfileirar (congelado;
    --     o arranjo de OS, conversa, janela e revalidação mora nos testes da agenda). É o mesmo ramo do 4a
    --     (v_fonte in ('agenda-cliente', 'on-my-way', 'quote_request')), que já roda aqui com o gatilho novo; a regressão
    --     retorno_f0a_canal_bloqueado.sql também só o prova com on-my-way e quote_request. A regra agenda-* do gatilho
    --     novo é a do 3b.
    v_agenda_sqlstate := null;
    begin
      insert into public.whatsapp_send_queue (phone_normalized, message, source)
        values ('5547900007001', 'teste F1 fila 4b', 'agenda-cliente');
    exception when others then
      v_agenda_sqlstate := sqlstate;
    end;
    if v_agenda_sqlstate is distinct from '42501' then
      raise exception '4b: agenda-cliente direto ao Cliente Final não foi recusada pela agenda com 42501 (sqlstate %)',
        v_agenda_sqlstate;
    end if;
    -- 4c. (F0a 7c) Opt-out: a ai_followup nasce CANCELADA pela F0a; a contagem registra o status cancelled (o
    --     AFTER vê a linha como os BEFORE a deixaram), com recusaria = true.
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('5547900007003', 'teste F1 fila 4c', 'ai_followup')
      returning id, status, failed_reason into v_id, v_status, v_motivo;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'cancelled' or coalesce(v_motivo, '') not like 'Recusado:%não receber%' then
      raise exception '4c: ai_followup a quem pediu para não receber ficou %, % (a F0a cancela)', v_status, v_motivo;
    end if;
    -- (cliente sozinho, ou ambíguo se a regressão da F0a já pôs o 7003 num cliente real nesta transação)
    v_conf := v_conf + pg_temp.retorno_f1_fila_confere('4c', v_id, 'ai_followup', true, array['cliente', 'cliente_ambiguo'],
                                                       'cancelled', 'conta');
    -- 4d. (F0a 7c) O que o dono pediu (ai_agent) a quem pediu opt-out segue pendente; contada sem recusaria.
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('5547900007003', 'teste F1 fila 4d', 'ai_agent') returning id, status into v_id, v_status;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'pending' then
      raise exception '4d: ai_agent a quem pediu opt-out ficou % (a F0a deixa passar)', v_status;
    end if;
    v_conf := v_conf + pg_temp.retorno_f1_fila_confere('4d', v_id, 'ai_agent', false, array['cliente', 'cliente_ambiguo'],
                                                       'pending', 'conta');
    -- 4e. (F0a 7) ai_agent ao "Cliente Final": nasce cancelada, com o motivo; contada como cancelled. O "Cliente
    --     Final" nunca identifica (quem_escreve): papel novo.
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('5547900007001', 'teste F1 fila 4e', 'ai_agent')
      returning id, status, failed_reason into v_id, v_status, v_motivo;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'cancelled' or coalesce(v_motivo, '') not like 'Recusado:%Cliente Final%' then
      raise exception '4e: linha da fila ao Cliente Final ficou %, motivo %', v_status, v_motivo;
    end if;
    v_conf := v_conf + pg_temp.retorno_f1_fila_confere('4e', v_id, 'ai_agent', false, array['novo'], 'cancelled', 'conta');
    -- 4f. (F0a 7b e 8) ai_agent a um número livre: pendente. Trocar o telefone para o do "Cliente Final" cancela
    --     (gatilho da F0a no UPDATE) e não mexe na contagem (o gatilho novo é só do INSERT).
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('5547900007999', 'teste F1 fila 4f', 'ai_agent') returning id, status into v_id, v_status;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'pending' then
      raise exception '4f: linha comum da fila ficou %', v_status;
    end if;
    update public.whatsapp_send_queue set phone_normalized = '5547900007001' where id = v_id returning status into v_status;
    if v_status is distinct from 'cancelled' then
      raise exception '4f: troca de telefone para o Cliente Final ficou % (a F0a cancela)', v_status;
    end if;
    v_c := pg_temp.retorno_f1_fila_contagem(v_id);
    if (v_c ->> 'n')::int <> 1 or v_c -> 'linha' ->> 'phone_normalized' is distinct from '5547900007999'
       or v_c -> 'linha' ->> 'recusaria' is distinct from 'false'
       or v_c -> 'linha' -> 'dados' ->> 'status' is distinct from 'pending' then
      raise exception '4f: o update da linha mexeu na contagem: %', v_c;
    end if;
    v_conf := v_conf + 1;

    -- ── 5. Erro dentro do gatilho não derruba (seção 7.1) ───────────────────────────────────────────────
    --       Uma constraint que recusa toda linha NOVA de retorno_saidas (not valid: os casos 1–4 já gravaram
    --       linhas, e um check validado falharia na hora). O insert na fila passa, nada é contado e o erro vai
    --       ao app_error_logs (upsert por fingerprint: confere-se por context/action e last_seen_at = now()).
    --       As variáveis guardam o resultado; o 'desfaz' tira a constraint, a linha e o registro.
    begin
      v5_passo := 'a constraint tmp_falha não entrou';
      alter table public.retorno_saidas add constraint tmp_falha check (false) not valid;
      v5_passo := 'o erro dentro do gatilho derrubou o insert na fila';
      insert into public.whatsapp_send_queue (phone_normalized, message, source)
        values ('5547900009701', 'teste F1 fila 5', 'ai_followup') returning id, status into v5_id, v5_status;
      v5_passo := 'a conferência depois do insert falhou';
      v5_existe := exists (select 1 from public.whatsapp_send_queue q where q.id = v5_id);
      v5_contada := exists (select 1 from public.retorno_saidas s where s.fila_id = v5_id);
      select to_jsonb(l) into v5_log
        from public.app_error_logs l
       where l.context = 'retorno' and l.action = 'fila_conta' and l.last_seen_at = now() and l.resolved_at is null
         and l.details ->> 'fila' = v5_id::text
       limit 1;
      v5_chegou := true;
      raise exception 'desfaz' using errcode = 'P0001';
    exception
      when sqlstate 'P0001' then
        if sqlerrm <> 'desfaz' then raise; end if;
      when others then
        v5_erro := sqlstate || ': ' || sqlerrm;
    end;
    if v5_erro is not null then
      raise exception '5: % (%)', v5_passo, v5_erro;
    end if;
    if not v5_chegou then
      raise exception '5: o arranjo do erro forçado não chegou ao fim';
    end if;
    if not v5_existe or v5_status is distinct from 'pending' then
      raise exception '5: com erro no gatilho, a linha da fila não ficou gravada e pendente (%)', v5_status;
    end if;
    if v5_contada then
      raise exception '5: a linha foi contada apesar da constraint que recusa toda linha nova';
    end if;
    if v5_log is null or v5_log ->> 'source' is distinct from 'db' or v5_log ->> 'level' is distinct from 'warn'
       or v5_log -> 'details' ->> 'sqlstate' is distinct from '23514'
       or coalesce(v5_log ->> 'message', '') not like 'retorno, fila em conta:%' then
      raise exception '5: o erro não foi registrado em app_error_logs (retorno/fila_conta, warn): %', v5_log;
    end if;
    if exists (select 1 from pg_constraint k where k.conrelid = 'public.retorno_saidas'::regclass and k.conname = 'tmp_falha')
       or exists (select 1 from public.whatsapp_send_queue q where q.id = v5_id) then
      raise exception '5: o arranjo do erro forçado não foi desfeito';
    end if;

    -- ── 5b/5c. Telefone de grupo (@): não conta; telefone sem chave: conta com '00000000' e papel sem_numero ─
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('120363000000009799@g.us', 'teste F1 fila 5b', 'ai_monitor') returning id into v_id;
    v_ids := v_ids || v_id;
    if v_id is null or not exists (select 1 from public.whatsapp_send_queue q where q.id = v_id)
       or (pg_temp.retorno_f1_fila_contagem(v_id) ->> 'n')::int <> 0 then
      raise exception '5b: telefone de grupo foi contado (ou a linha da fila não ficou): %', pg_temp.retorno_f1_fila_contagem(v_id);
    end if;
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('9799', 'teste F1 fila 5c', 'ai_monitor') returning id, status into v_id, v_status;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'pending' then
      raise exception '5c: telefone sem chave ficou %', v_status;
    end if;
    v_conf := v_conf + pg_temp.retorno_f1_fila_confere('5c', v_id, 'ai_monitor', false, array['sem_numero'], 'pending', 'conta');

    -- ── 6. fila_modo = 'trava' não muda nada nesta leva: a ai_followup ao cliente continua pendente ─────
    update public.retorno_config set fila_modo = 'trava' where id;
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('5547900009701', 'teste F1 fila 6', 'ai_followup') returning id, status into v_id, v_status;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'pending' then
      raise exception '6: com fila_modo = trava, a ai_followup ao cliente ficou % (a trava não vale nesta leva)', v_status;
    end if;
    v_conf := v_conf + pg_temp.retorno_f1_fila_confere('6', v_id, 'ai_followup', true, array['cliente'], 'pending', 'trava');

    -- ── 7. modo = 'desligado': nada contado, e a linha da fila passa ────────────────────────────────────
    update public.retorno_config set modo = 'desligado', fila_modo = 'conta' where id;
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('5547900009701', 'teste F1 fila 7', 'ai_followup') returning id, status into v_id, v_status;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'pending' or (pg_temp.retorno_f1_fila_contagem(v_id) ->> 'n')::int <> 0 then
      raise exception '7: com modo desligado, a linha ficou % e foi contada (%)', v_status,
        pg_temp.retorno_f1_fila_contagem(v_id) ->> 'n';
    end if;
    -- 7b. Sem a linha de configuração (falha fecha): nada contado, e a linha da fila passa.
    delete from public.retorno_config;
    insert into public.whatsapp_send_queue (phone_normalized, message, source)
      values ('5547900009701', 'teste F1 fila 7b', 'ai_followup') returning id, status into v_id, v_status;
    v_ids := v_ids || v_id;
    if v_status is distinct from 'pending' or (pg_temp.retorno_f1_fila_contagem(v_id) ->> 'n')::int <> 0 then
      raise exception '7b: sem a linha de configuração, a linha ficou % e foi contada (%)', v_status,
        pg_temp.retorno_f1_fila_contagem(v_id) ->> 'n';
    end if;

    -- O total: uma contagem por linha conferida, e recusaria só nos casos 2, 2b (ambíguo e novo), 4c e 6.
    select count(*), count(*) filter (where s.recusaria) into v_n_contadas, v_n_recusaria
      from public.retorno_saidas s
     where s.fila_id = any (v_ids);
    if v_n_contadas <> v_conf or v_n_recusaria <> 5 then
      raise exception '8: % linhas contadas (esperadas %) e % com recusaria (esperadas 5)', v_n_contadas, v_conf, v_n_recusaria;
    end if;

    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '8: o arranjo não chegou ao fim';
  end if;

  -- ── 8. O arranjo foi desfeito ────────────────────────────────────────────────────────────────────────
  -- Nenhuma linha da fila nem contagem do teste ficou, os cadastros sintéticos sumiram e retorno_config voltou
  -- ao valor de antes.
  if exists (select 1 from public.whatsapp_send_queue q where q.id = any (v_ids))
     or exists (select 1 from public.retorno_saidas s where s.fila_id = any (v_ids))
     or exists (select 1 from public.clients c where c.id in (v_c_cliente, v_c_amb_a, v_c_amb_b, v_c_final, v_c_opt))
     or exists (select 1 from public.suppliers s where s.id = v_forn)
     or exists (select 1 from public.payees p where p.id = v_payee)
     or (select c.modo from public.retorno_config c where c.id) is distinct from v_modo_antes
     or (select c.fila_modo from public.retorno_config c where c.id) is distinct from v_fila_modo_antes then
    raise exception '8: o arranjo não foi desfeito';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_fila', true,
          jsonb_build_object('contadas', v_n_contadas, 'recusaria', v_n_recusaria,
                             'fontes_reais_ao_dono_sem_recusa', cardinality(c_fontes_reais),
                             'agenda_cliente_recusada_com', v_agenda_sqlstate, 'erro_engolido', v5_log is not null));
end
$fila$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
