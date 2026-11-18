-- Prova: revisão do documento (migration 20270123100000_revisao_de_documentos).
--
--   R1  primeira emissão = Rev. 1, código XXXX-XXXX, sem anterior
--   R2  emitir de novo sem mudar nada = a mesma Rev. 1 (mesmo código)
--   R3  mudança interna (nota interna, prioridade, técnico) não sobe a revisão
--   R4  texto nulo -> vazio não sobe
--   R5  nota do técnico não muda o ORÇAMENTO (ela e a data agendada só saem na OS)
--   R6  mudar a quantidade de uma peça: Rev. 2, com a anterior (Rev. 1) e o retrato do histórico ligado
--   R7  cinco edições seguidas e um PDF = uma revisão só (Rev. 3)
--   R8  situação: depois de emitir não "mudou"; depois de editar, "mudou"; sem emitir de novo, segue Rev. 3
--   R9  envio ao cliente (registro da F5) marca a revisão enviada; envio que não foi ao cliente não marca
--   R10 aprovação marca a revisão aprovada (no tipo de antes: orçamento)
--   R11 a OS do mesmo número tem contador próprio (começa na Rev. 1)
--   R12 conferir código: acha o documento, diz se é a atual
--   R13 cliente do link: com o token certo emite; sem token, recusado
--   R14 recibo não tem revisão (null)
--   R15 privilégios: anon sem EXECUTE em situação/conferir; ninguém lê a tabela direto
--
-- ═══ COMO RODAR ═══ (DEPOIS da migration aplicada; a partir do repositório principal, que é o linkado)
--   npx supabase@2.111.0 db query --linked -f supabase/tests/revisao_documentos.sql --output json
-- Seguro em produção: usuário, cliente, barco e OS de teste nascem aqui; termina em ROLLBACK.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._req(p_sub uuid, p_papel text, p_headers jsonb default null) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_papel is null then '' else json_build_object('sub', p_sub, 'role', p_papel)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_sub::text, ''), true);
  perform set_config('request.headers', coalesce(p_headers::text, ''), true);
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_cli uuid; v_barco uuid; v_os uuid; v_peca uuid; v_token uuid;
  v_r jsonb; v_r2 jsonb; v_s jsonb; v_msg text; v_n int;
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_admin, 'Teste Revisão (admin)', 'teste-rev-' || v_admin || '@teste.invalido', 'admin', true);
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Revisão') returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Barco Teste Revisão') returning id into v_barco;

  perform pg_temp._req(v_admin, 'authenticated');
  insert into public.service_orders (service_order_number, client_id, vessel_id, problem_description, status, quote_status)
  values ('TESTE-REV-' || substr(md5(random()::text), 1, 8), v_cli, v_barco, 'trocar a bomba', 'draft', 'draft')
  returning id, share_token into v_os, v_token;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, line_total_cost,
                                          unit_sale_snapshot, line_total_sale)
  values (v_os, (select id from public.products order by created_at limit 1), 2, 50, 100, 100, 200)
  returning id into v_peca;
  insert into public.service_order_services (service_order_id, name_snapshot, quantity, unit_price_snapshot, line_total)
  values (v_os, 'Mão de obra', 1, 300, 300);

  -- R1
  v_r := public.documento_revisao_emitir(v_os, 'quote');
  insert into _resultado values ('R1 primeira = Rev. 1', (v_r ->> 'revisao')::int = 1
    and v_r ->> 'codigo' ~ '^[0-9A-F]{4}-[0-9A-F]{4}$' and v_r -> 'anterior' = 'null'::jsonb, v_r::text);

  -- R2
  v_r2 := public.documento_revisao_emitir(v_os, 'quote');
  insert into _resultado values ('R2 sem mudança = mesma', (v_r2 ->> 'revisao')::int = 1 and v_r2 ->> 'codigo' = v_r ->> 'codigo',
    v_r2::text);

  -- R3
  update public.service_orders set internal_notes = 'só para a equipe', priority = 'high' where id = v_os;
  insert into public.service_order_technicians (service_order_id, user_id) values (v_os, v_admin);
  v_r2 := public.documento_revisao_emitir(v_os, 'quote');
  insert into _resultado values ('R3 mudança interna não sobe', (v_r2 ->> 'revisao')::int = 1, v_r2 ->> 'revisao');

  -- R4
  update public.service_orders set extra_notes = '' where id = v_os and extra_notes is null;
  v_r2 := public.documento_revisao_emitir(v_os, 'quote');
  insert into _resultado values ('R4 nulo -> vazio não sobe', (v_r2 ->> 'revisao')::int = 1, v_r2 ->> 'revisao');

  -- R5
  update public.service_orders set technician_notes = 'conferir o dreno' where id = v_os;
  v_r2 := public.documento_revisao_emitir(v_os, 'quote');
  insert into _resultado values ('R5 nota do técnico não muda o orçamento', (v_r2 ->> 'revisao')::int = 1, v_r2 ->> 'revisao');

  -- R6
  update public.service_order_parts set quantity = 3, line_total_sale = 300 where id = v_peca;
  v_r2 := public.documento_revisao_emitir(v_os, 'quote');
  select count(*) into v_n from public.documento_revisoes r
   where r.service_order_id = v_os and r.revisao = 2 and r.versao_historico is not null;
  insert into _resultado values ('R6 peça mudou = Rev. 2', (v_r2 ->> 'revisao')::int = 2
    and (v_r2 -> 'anterior' ->> 'revisao')::int = 1 and v_r2 ->> 'codigo' <> v_r ->> 'codigo' and v_n = 1,
    v_r2::text);

  -- R7
  update public.service_order_parts set quantity = 4, line_total_sale = 400 where id = v_peca;
  update public.service_order_parts set quantity = 5, line_total_sale = 500 where id = v_peca;
  update public.service_orders set problem_description = 'trocar a bomba de porão' where id = v_os;
  update public.service_orders set extra_notes = 'levar a peça antiga' where id = v_os;
  update public.service_orders set quote_validity_days = 10 where id = v_os;
  v_r2 := public.documento_revisao_emitir(v_os, 'quote');
  insert into _resultado values ('R7 cinco edições, um PDF = uma revisão', (v_r2 ->> 'revisao')::int = 3, v_r2 ->> 'revisao');

  -- R8
  v_s := public.documento_revisao_situacao(v_os);
  update public.service_orders set extra_notes = 'levar a peça antiga e a nova' where id = v_os;
  v_r2 := public.documento_revisao_situacao(v_os);
  insert into _resultado values ('R8 situação', v_s ->> 'tipo' = 'quote' and not (v_s ->> 'mudou_desde_a_ultima')::boolean
    and (v_r2 ->> 'mudou_desde_a_ultima')::boolean and (v_r2 -> 'atual' ->> 'revisao')::int = 3,
    format('antes=%s depois=%s', v_s, v_r2));

  -- R9 (o envio emite a revisão do conteúdo de agora: Rev. 4)
  insert into public.orcamento_envios (service_order_id, client_id, via, ao_cliente, em)
  values (v_os, v_cli, 'tela', false, now() - interval '1 minute');
  v_s := public.documento_revisao_situacao(v_os);
  insert into public.orcamento_envios (service_order_id, client_id, via, ao_cliente, em)
  values (v_os, v_cli, 'tela', true, now());
  v_r2 := public.documento_revisao_situacao(v_os);
  insert into _resultado values ('R9 envio ao cliente marca a revisão', v_s -> 'enviada' = 'null'::jsonb
    and (v_r2 -> 'enviada' ->> 'revisao')::int = 4 and v_r2 -> 'enviada' ->> 'enviada_via' = 'tela',
    format('so interno=%s ao cliente=%s', v_s -> 'enviada', v_r2 -> 'enviada'));

  -- R10
  update public.service_orders set quote_status = 'approved' where id = v_os;
  v_s := public.documento_revisao_situacao(v_os, 'quote');
  insert into _resultado values ('R10 aprovação marca a revisão', (v_s -> 'aprovada' ->> 'revisao')::int = 4
    and v_s -> 'aprovada' ->> 'aprovada_em' is not null, v_s -> 'aprovada' ->> 'revisao');

  -- R11
  update public.service_orders set status = 'approved', converted_to_os_at = now() where id = v_os;
  v_r2 := public.documento_revisao_emitir(v_os, 'service_order');
  v_s := public.documento_revisao_situacao(v_os);
  insert into _resultado values ('R11 OS tem contador próprio', (v_r2 ->> 'revisao')::int = 1 and v_s ->> 'tipo' = 'service_order',
    format('%s / %s', v_r2 ->> 'revisao', v_s ->> 'tipo'));

  -- R12
  v_s := public.documento_revisao_conferir(lower(replace(v_r ->> 'codigo', '-', '')));
  v_r2 := public.documento_revisao_conferir(v_r2 ->> 'codigo');
  insert into _resultado values ('R12 conferir código', (v_s ->> 'achou')::boolean
    and (v_s -> 'documentos' -> 0 ->> 'revisao')::int = 1 and not (v_s -> 'documentos' -> 0 ->> 'e_a_atual')::boolean
    and (v_r2 -> 'documentos' -> 0 ->> 'e_a_atual')::boolean,
    format('antigo=%s atual=%s', v_s, v_r2));

  -- R13
  perform pg_temp._req(null, 'anon', jsonb_build_object('x-share-token', v_token::text));
  v_r2 := public.documento_revisao_emitir(v_os, 'service_order');
  perform pg_temp._req(null, 'anon');
  begin
    perform public.documento_revisao_emitir(v_os, 'service_order');
    v_msg := 'emitiu';
  exception when insufficient_privilege then v_msg := 'recusado';
  end;
  insert into _resultado values ('R13 link do cliente', (v_r2 ->> 'revisao')::int = 1 and v_msg = 'recusado',
    format('com token=%s sem token=%s', v_r2 ->> 'revisao', v_msg));

  -- R14
  perform pg_temp._req(v_admin, 'authenticated');
  insert into _resultado values ('R14 recibo sem revisão', public.documento_revisao_emitir(v_os, 'receipt') is null, '');

  -- R15
  insert into _resultado values ('R15 privilégios',
    not has_function_privilege('anon', 'public.documento_revisao_situacao(uuid, text)', 'execute')
    and not has_function_privilege('anon', 'public.documento_revisao_conferir(text)', 'execute')
    and has_function_privilege('anon', 'public.documento_revisao_emitir(uuid, text)', 'execute')
    and not has_function_privilege('anon', 'private.documento_revisao_emitir(uuid, text)', 'execute')
    and not has_function_privilege('authenticated', 'private.documento_conteudo_impresso(uuid, text)', 'execute')
    and not has_table_privilege('anon', 'public.documento_revisoes', 'select')
    and not has_table_privilege('authenticated', 'public.documento_revisoes', 'select'),
    '');
end $$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
