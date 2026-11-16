-- Prova: histórico de documentos (migration 20270121100000_historico_de_documentos_captura).
--
--   T1  tela (usuário logado) cria OS: linha 'insert' com autor = login, origem 'tela', doc = a OS
--   T2  salvar sem mudar nada: nenhuma linha nova
--   T3  null -> "" (o formulário troca sem o usuário mexer): nenhuma linha nova
--   T4  mudar a descrição: 'update' só com o campo mudado (antes e depois)
--   T5  incluir peça: 'insert' em service_order_parts com doc = a OS
--   T6  assistente pelo WhatsApp (service_role + cabeçalho): autor = cabeçalho, origem assistente_whatsapp
--   T7  usuário logado mandando cabeçalho de outro autor: vale o login, não o cabeçalho
--   T8  sem requisição (cron/banco): origem 'banco', sem autor
--   T9  marco: orçamento enviado gera retrato v1 com as peças; reenvio sem mudança não gera v2
--   T10 marco: aprovado gera v2 (o status mudou); o retrato traz o número e o cliente
--   T11 documento assinado: mudar a QUANTIDADE de uma peça pede nova assinatura (decisão 4)
--   T12 documento assinado: mudar só o campo de execução do serviço (field_status) NÃO pede
--   T13 excluir a OS: as linhas apagadas em cascata ficam no histórico ('delete' com a linha inteira)
--   T14 a API não grava ação do banco ('versao'): recusado
--   T15 autor forjado no corpo do insert: o banco troca pelo login
--   T16 técnico não lê o histórico; admin lê; anon sem permissão
--   T17 configuração: cursor de automação não vira histórico; termo do documento vira
--   T18 captura desligada (carga de backup): nada gravado
--   T19 privilégios: anon e authenticated sem EXECUTE nas funções novas
--
-- ═══ COMO RODAR ═══ (DEPOIS da migration aplicada; a partir do repositório principal, que é o linkado)
--   npx supabase@2.111.0 db query --linked -f supabase/tests/historico_documentos.sql --output json
-- Seguro em produção: usuários, cliente, barco e OS de teste nascem aqui; termina em ROLLBACK.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._usuario(p_role text) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste Histórico (' || p_role || ')', 'teste-hist-' || v_id || '@teste.invalido', p_role, true);
  return v_id;
end $$;

-- Simula a requisição do PostgREST: claims do JWT e cabeçalhos.
create function pg_temp._req(p_sub uuid, p_papel text, p_headers jsonb default null) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_papel is null then '' else json_build_object('sub', p_sub, 'role', p_papel)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_sub::text, ''), true);
  perform set_config('request.headers', coalesce(p_headers::text, ''), true);
  perform set_config('marineflow.historico_interno', '', true);
end $$;

create function pg_temp._linhas(p_os uuid) returns integer language sql as $$
  select count(*)::int from public.audit_log where doc_id = p_os;
$$;

do $$
declare
  v_admin uuid := pg_temp._usuario('admin');
  v_tec   uuid := pg_temp._usuario('technician');
  v_cli uuid; v_barco uuid; v_os uuid; v_peca uuid; v_serv uuid;
  v_n int; v_n2 int; v_l record; v_msg text; v_bool boolean;
begin
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Histórico') returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Barco Teste Histórico') returning id into v_barco;

  -- T1
  perform pg_temp._req(v_admin, 'authenticated');
  insert into public.service_orders (service_order_number, client_id, vessel_id, problem_description, status, quote_status)
  values ('TESTE-HIST-' || substr(md5(random()::text), 1, 8), v_cli, v_barco, 'descrição inicial', 'draft', 'draft')
  returning id into v_os;
  select * into v_l from public.audit_log where doc_id = v_os and table_name = 'service_orders' and action = 'insert';
  insert into _resultado values ('T1 tela cria OS', v_l.ator_id = v_admin and v_l.origem = 'tela'
    and v_l.doc_tabela = 'service_orders' and v_l.new_value ? 'problem_description' and not (v_l.new_value ? 'share_token'),
    format('ator=%s origem=%s', v_l.ator_id, v_l.origem));

  -- T2
  v_n := pg_temp._linhas(v_os);
  update public.service_orders set problem_description = 'descrição inicial' where id = v_os;
  insert into _resultado values ('T2 salvar sem mudança', pg_temp._linhas(v_os) = v_n, format('%s -> %s', v_n, pg_temp._linhas(v_os)));

  -- T3
  update public.service_orders set diagnosis = null where id = v_os;
  v_n := pg_temp._linhas(v_os);
  update public.service_orders set diagnosis = '' where id = v_os;
  insert into _resultado values ('T3 null -> vazio', pg_temp._linhas(v_os) = v_n, format('%s -> %s', v_n, pg_temp._linhas(v_os)));

  -- T4
  update public.service_orders set problem_description = 'descrição corrigida' where id = v_os;
  select * into v_l from public.audit_log where doc_id = v_os and table_name = 'service_orders' and action = 'update'
   order by changed_at desc, id desc limit 1;
  insert into _resultado values ('T4 update só do campo', v_l.previous_value = jsonb_build_object('problem_description', 'descrição inicial')
    and v_l.new_value = jsonb_build_object('problem_description', 'descrição corrigida'),
    format('antes=%s depois=%s', v_l.previous_value, v_l.new_value));

  -- T5
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, line_total_cost,
                                          unit_sale_snapshot, line_total_sale, notes)
  values (v_os, (select id from public.products order by created_at limit 1), 2, 50, 100, 100, 200, 'peça de teste')
  returning id into v_peca;
  insert into public.service_order_services (service_order_id, name_snapshot, quantity, unit_price_snapshot, line_total)
  values (v_os, 'Serviço de teste', 1, 300, 300) returning id into v_serv;
  select * into v_l from public.audit_log where record_id = v_peca and action = 'insert';
  insert into _resultado values ('T5 peça incluída', v_l.doc_id = v_os and v_l.table_name = 'service_order_parts'
    and (v_l.new_value ->> 'quantity')::numeric = 2, format('doc=%s', v_l.doc_id));

  -- T6
  perform pg_temp._req(null, 'service_role', jsonb_build_object('x-mf-ator', v_admin, 'x-mf-origem', 'assistente_whatsapp'));
  update public.service_order_parts set quantity = 3, line_total_sale = 300 where id = v_peca;
  select * into v_l from public.audit_log where record_id = v_peca and action = 'update' order by changed_at desc, id desc limit 1;
  insert into _resultado values ('T6 assistente WhatsApp', v_l.ator_id = v_admin and v_l.origem = 'assistente_whatsapp'
    and v_l.changed_by like 'Teste Histórico%', format('ator=%s origem=%s por=%s', v_l.ator_id, v_l.origem, v_l.changed_by));

  -- T7
  perform pg_temp._req(v_tec, 'authenticated', jsonb_build_object('x-mf-ator', v_admin, 'x-mf-origem', 'assistente_whatsapp'));
  update public.service_order_parts set notes = 'nota do técnico' where id = v_peca;
  select * into v_l from public.audit_log where record_id = v_peca and action = 'update' order by changed_at desc, id desc limit 1;
  insert into _resultado values ('T7 cabeçalho não vale para logado', v_l.ator_id = v_tec and v_l.origem = 'tela',
    format('ator=%s origem=%s', v_l.ator_id, v_l.origem));

  -- T8
  perform pg_temp._req(null, null);
  update public.service_orders set internal_notes = 'nota da automação' where id = v_os;
  select * into v_l from public.audit_log where doc_id = v_os and table_name = 'service_orders' and action = 'update'
     and new_value ? 'internal_notes'
   order by changed_at desc, id desc limit 1;
  insert into _resultado values ('T8 sem requisição', v_l.ator_id is null and v_l.origem in ('banco', 'automacao'),
    format('ator=%s origem=%s', v_l.ator_id, v_l.origem));

  -- T9
  perform pg_temp._req(v_admin, 'authenticated');
  update public.service_orders set quote_status = 'sent' where id = v_os;
  select * into v_l from public.audit_log where doc_id = v_os and action = 'versao' order by versao desc limit 1;
  v_n := v_l.versao;
  insert into public.audit_log (table_name, record_id, action, new_value)
  values ('service_orders', v_os, 'whatsapp_send_api', jsonb_build_object('kind', 'document', 'context', 'quote'));
  select max(versao) into v_n2 from public.audit_log where doc_id = v_os and action = 'versao';
  insert into _resultado values ('T9 enviado = v1; reenvio igual não duplica',
    v_n = 1 and v_n2 = 1 and v_l.reason = 'enviado'
    and jsonb_array_length(v_l.new_value -> 'retrato' -> 'pecas') = 1
    and (v_l.new_value -> 'retrato' -> 'pecas' -> 0 ->> 'quantity')::numeric = 3,
    format('v=%s depois do reenvio=%s marco=%s', v_n, v_n2, v_l.reason));

  -- T10
  update public.service_orders set quote_status = 'approved' where id = v_os;
  select * into v_l from public.audit_log where doc_id = v_os and action = 'versao' order by versao desc limit 1;
  insert into _resultado values ('T10 aprovado = v2', v_l.versao = 2 and v_l.reason = 'aprovado'
    and v_l.new_value -> 'retrato' -> 'cliente' ->> 'nome' = 'Cliente Teste Histórico'
    and not (v_l.new_value -> 'retrato' -> 'cabecalho' ? 'share_token'),
    format('v=%s marco=%s', v_l.versao, v_l.reason));

  -- T11
  update public.service_orders set signed_at = now(), requires_resignature = false where id = v_os;
  update public.service_order_parts set quantity = 4, line_total_sale = 400 where id = v_peca;
  select requires_resignature into v_bool from public.service_orders where id = v_os;
  insert into _resultado values ('T11 item mudado após assinatura', v_bool, format('requires_resignature=%s', v_bool));

  -- T12
  update public.service_orders set requires_resignature = false where id = v_os;
  update public.service_order_services set field_status = 'feito' where id = v_serv;
  select requires_resignature into v_bool from public.service_orders where id = v_os;
  insert into _resultado values ('T12 execução do serviço não pede assinatura', not v_bool, format('requires_resignature=%s', v_bool));

  -- T13
  delete from public.service_orders where id = v_os;
  select * into v_l from public.audit_log where record_id = v_peca and action = 'delete';
  insert into _resultado values ('T13 exclusão em cascata guardada', v_l.doc_id = v_os
    and (v_l.previous_value ->> 'quantity')::numeric = 4 and v_l.new_value is null,
    format('achou=%s', v_l.id is not null));

  -- T14
  perform pg_temp._req(v_admin, 'authenticated');
  begin
    insert into public.audit_log (table_name, record_id, action, new_value)
    values ('service_orders', gen_random_uuid(), 'versao', '{}'::jsonb);
    v_msg := 'passou';
  exception when insufficient_privilege then v_msg := 'recusado';
  end;
  insert into _resultado values ('T14 API não grava versao', v_msg = 'recusado', v_msg);

  -- T15
  insert into public.audit_log (table_name, record_id, action, changed_by, new_value)
  values ('clients', v_cli, 'update', 'Outra Pessoa', '{"x":1}'::jsonb)
  returning * into v_l;
  insert into _resultado values ('T15 autor forjado trocado', v_l.ator_id = v_admin and v_l.changed_by like 'Teste Histórico%',
    format('changed_by=%s', v_l.changed_by));

  -- T17
  perform pg_temp._req(null, null);
  v_n := (select count(*) from public.audit_log where table_name = 'app_settings');
  update public.app_settings set value = value || '' where key = 'acompanhar_cursor';
  update public.app_settings set value = coalesce(value, '') || ' (teste)' where key = 'terms_general';
  v_n2 := (select count(*) from public.audit_log where table_name = 'app_settings');
  insert into _resultado values ('T17 só configuração do documento', v_n2 = v_n + 1, format('%s -> %s', v_n, v_n2));

  -- T18
  perform set_config('marineflow.historico_desligado', 'on', true);
  v_n := (select count(*) from public.audit_log where table_name = 'clients' and record_id = v_cli);
  update public.clients set notes = 'carga de backup' where id = v_cli;
  v_n2 := (select count(*) from public.audit_log where table_name = 'clients' and record_id = v_cli);
  perform set_config('marineflow.historico_desligado', '', true);
  insert into _resultado values ('T18 captura desligada', v_n2 = v_n, format('%s -> %s', v_n, v_n2));

  -- T19
  select bool_and(not has_function_privilege(r, p.oid, 'execute')) into v_bool
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join (values ('anon'), ('authenticated')) as x(r)
   where n.nspname = 'private'
     and p.proname in ('historico_contexto', 'historico_nome', 'historico_config_relevante', 'historico_registrar',
                       'audit_log_carimbar', 'documento_retrato', 'documento_versionar', 'documento_marco_os',
                       'documento_marco_envio', 'linha_pede_nova_assinatura');
  insert into _resultado values ('T19 funções fechadas', v_bool, '');

  -- T20: linha forjada pela API (pelo_banco, outro documento, versão) — o carimbo desfaz tudo
  perform pg_temp._req(v_admin, 'authenticated');
  insert into public.service_orders (service_order_number, client_id, vessel_id, problem_description, status, quote_status)
  values ('TESTE-HIST2-' || substr(md5(random()::text), 1, 8), v_cli, v_barco, 'segunda OS', 'draft', 'draft')
  returning id into v_os;
  insert into public.audit_log (table_name, record_id, action, new_value, previous_value, doc_tabela, doc_id, pelo_banco, versao)
  values ('service_order_parts', gen_random_uuid(), 'update', '{"quantity": 9}', '{"quantity": 1}', 'service_orders', v_os, true, 7)
  returning * into v_l;
  insert into _resultado values ('T20 linha forjada não vira linha do banco',
    not v_l.pelo_banco and v_l.doc_id is null and v_l.versao is null, format('pelo_banco=%s doc=%s', v_l.pelo_banco, v_l.doc_id));

  -- T21: envio que o provedor recusou não vira versão "enviado"; o aceito vira
  v_n := (select count(*) from public.audit_log where doc_id = v_os and action = 'versao');
  insert into public.audit_log (table_name, record_id, action, new_value)
  values ('service_orders', v_os, 'whatsapp_send_api',
          jsonb_build_object('kind', 'document', 'context', 'quote', 'provider_result', jsonb_build_object('ok', false, 'error', 'HTTP 530')));
  v_n2 := (select count(*) from public.audit_log where doc_id = v_os and action = 'versao');
  insert into public.audit_log (table_name, record_id, action, new_value)
  values ('service_orders', v_os, 'whatsapp_send_api',
          jsonb_build_object('kind', 'document', 'context', 'quote', 'provider_result', jsonb_build_object('ok', true)));
  insert into _resultado values ('T21 só envio aceito vira versão',
    v_n2 = v_n and (select count(*) from public.audit_log where doc_id = v_os and action = 'versao' and reason = 'enviado') = 1,
    format('antes=%s depois da falha=%s', v_n, v_n2));

  -- T22: a licença interna não fica ligada depois do gatilho (a próxima linha da API com ação do banco é recusada)
  update public.service_orders set extra_notes = 'liga a licença' where id = v_os;
  begin
    insert into public.audit_log (table_name, record_id, action, new_value) values ('service_orders', v_os, 'restore', '{}'::jsonb);
    v_msg := 'passou';
  exception when insufficient_privilege then v_msg := 'recusado';
  end;
  insert into _resultado values ('T22 licença interna desliga após o gatilho', v_msg = 'recusado', v_msg);

  -- guarda os ids para o T16 (fora do bloco, com SET ROLE)
  perform set_config('teste.admin', v_admin::text, true);
  perform set_config('teste.tec', v_tec::text, true);
end $$;

-- T16: a leitura pela RLS, com o papel de verdade (a contagem sai do papel antes de gravar no _resultado,
-- que é do postgres).
do $$
declare v_tec bigint; v_env bigint; v_adm bigint; v_msg text;
begin
  perform pg_temp._req(current_setting('teste.tec')::uuid, 'authenticated');
  set local role authenticated;
  select count(*) filter (where action not in ('whatsapp_send_api', 'whatsapp_send')),
         count(*) filter (where action in ('whatsapp_send_api', 'whatsapp_send'))
    into v_tec, v_env from public.audit_log;
  reset role;

  perform pg_temp._req(current_setting('teste.admin')::uuid, 'authenticated');
  set local role authenticated;
  select count(*) into v_adm from public.audit_log;
  reset role;

  perform pg_temp._req(null, 'anon');
  set local role anon;
  begin
    perform count(*) from public.audit_log;
    v_msg := 'leu';
  exception when insufficient_privilege then v_msg := 'sem permissão';
  end;
  reset role;

  insert into _resultado values ('T16a técnico não lê o histórico', v_tec = 0, v_tec::text);
  insert into _resultado values ('T16d técnico continua vendo o selo de envio', v_env > 0, v_env::text);
  insert into _resultado values ('T16b admin lê', v_adm > 0, v_adm::text);
  insert into _resultado values ('T16c anon sem permissão', v_msg = 'sem permissão', v_msg);
end $$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
