-- Prova: NOVO-historico-03 — só admin e financeiro (e o sistema) alteram a assinatura do cliente
-- (migration 20270211100000_assinaturas_admin_financeiro_altera; decisão do dono: "Admin e financeiro").
--
--   A1  técnico tenta alterar a assinatura pela API: recusado (0 linhas, a assinatura fica como estava)
--   A2  vendedor externo idem
--   A3  financeiro altera: aceito (mesmo cargo dos termos e do PIX, is_admin_or_financial)
--   A4  admin altera: aceito
--   A5  anon não grava (sem permissão na tabela)
--   A6  fluxo real do cliente (edge submit-signature, service_role): grava a assinatura e substitui a anterior
--   A7  sistema: técnico edita o CABEÇALHO de uma OS assinada -> a assinatura deixa de valer (gatilho
--       detect_so_change_after_signature, agora definer). Sem a migration, a RLS nova deixaria a velha valendo.
--   A8  sistema: técnico muda a quantidade de uma PEÇA de OS assinada -> a assinatura deixa de valer
--   A9  portal do cliente (anon com o token do link) continua lendo a assinatura válida
--   A10 privilégios: a policy é só de authenticated e o gatilho não é executável por anon/authenticated
--
-- ═══ COMO RODAR ═══ (DEPOIS da migration aplicada; a partir do repositório principal, que é o linkado)
--   npx supabase@2.111.0 db query --linked -f supabase/tests/assinaturas_admin_financeiro_altera.sql --output json
-- Ensaio ANTES de aplicar: begin + a migration + este arquivo (sem o begin dele) — termina em ROLLBACK.
-- Seguro em produção: usuários, cliente, barco, OS e assinaturas de teste nascem aqui; termina em ROLLBACK.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
grant all on _resultado to authenticated, anon, service_role;

create function pg_temp._usuario(p_role text) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste Assinatura (' || p_role || ')', 'teste-assin-' || v_id || '@teste.invalido', p_role, true);
  return v_id;
end $$;

-- Simula a requisição do PostgREST: claims do JWT e cabeçalhos.
create function pg_temp._req(p_sub uuid, p_papel text, p_headers jsonb default null) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_papel is null then '' else json_build_object('sub', p_sub, 'role', p_papel)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_sub::text, ''), true);
  perform set_config('request.headers', coalesce(p_headers::text, ''), true);
end $$;

-- Uma OS assinada (como a submit-signature deixa) com uma peça; devolve o id da OS.
create function pg_temp._os_assinada(p_rotulo text) returns uuid language plpgsql as $$
declare v_cli uuid; v_barco uuid; v_os uuid; v_prod uuid; v_token uuid;
begin
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Assinatura ' || p_rotulo) returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Barco Teste Assinatura') returning id into v_barco;
  insert into public.service_orders (service_order_number, client_id, vessel_id, problem_description, status, quote_status)
  values ('TESTE-ASSIN-' || substr(md5(random()::text), 1, 8), v_cli, v_barco, 'descrição assinada', 'draft', 'draft')
  returning id, share_token into v_os, v_token;
  insert into public.products (name, sale_price, cost_price) values ('Peça Teste Assinatura ' || p_rotulo, 100, 50)
  returning id into v_prod;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_os, v_prod, 1, 50, 100, 50, 100);
  insert into public.service_order_signatures (service_order_id, share_token, accepted_name, document_hash)
  values (v_os, v_token, 'Cliente Que Assinou', 'hash-original');
  update public.service_orders set signed_at = now(), signed_by_name = 'Cliente Que Assinou',
         signed_document_hash = 'hash-original', requires_resignature = false where id = v_os;
  return v_os;
end $$;

do $$
begin
  perform set_config('teste.admin', pg_temp._usuario('admin')::text, true);
  perform set_config('teste.tec', pg_temp._usuario('technician')::text, true);
  perform set_config('teste.vend', pg_temp._usuario('external_seller')::text, true);
  perform set_config('teste.fin', pg_temp._usuario('financial')::text, true);
  perform set_config('teste.os1', pg_temp._os_assinada('1')::text, true);
  perform set_config('teste.os2', pg_temp._os_assinada('2')::text, true);
  perform set_config('teste.os3', pg_temp._os_assinada('3')::text, true);
end $$;

-- A1..A4: a alteração direta pela API, com o papel de verdade.
do $$
declare
  v_os uuid := current_setting('teste.os1')::uuid;
  v_quem text; v_n int; v_nome text;
begin
  foreach v_quem in array array['tec', 'vend'] loop
    perform pg_temp._req(current_setting('teste.' || v_quem)::uuid, 'authenticated');
    set local role authenticated;
    update public.service_order_signatures set accepted_name = 'Nome Forjado', document_hash = 'hash-forjado'
     where service_order_id = v_os;
    get diagnostics v_n = row_count;
    reset role;
    select accepted_name into v_nome from public.service_order_signatures where service_order_id = v_os;
    insert into _resultado values (
      case v_quem when 'tec' then 'A1 técnico não altera a assinatura'
                  else 'A2 vendedor externo não altera a assinatura' end,
      v_n = 0 and v_nome = 'Cliente Que Assinou', format('linhas=%s nome=%s', v_n, v_nome));
  end loop;

  foreach v_quem in array array['fin', 'admin'] loop
    perform pg_temp._req(current_setting('teste.' || v_quem)::uuid, 'authenticated');
    set local role authenticated;
    update public.service_order_signatures set superseded_reason = 'correção do ' || v_quem where service_order_id = v_os;
    get diagnostics v_n = row_count;
    reset role;
    select superseded_reason into v_nome from public.service_order_signatures where service_order_id = v_os;
    insert into _resultado values (
      case v_quem when 'fin' then 'A3 financeiro altera' else 'A4 admin altera' end,
      v_n = 1 and v_nome = 'correção do ' || v_quem, format('linhas=%s motivo=%s', v_n, v_nome));
  end loop;
end $$;

-- A5: anon (portador da chave pública) nem com o token do link grava.
do $$
declare v_os uuid := current_setting('teste.os1')::uuid; v_token uuid; v_msg text;
begin
  select share_token into v_token from public.service_orders where id = v_os;
  perform pg_temp._req(null, 'anon', jsonb_build_object('x-share-token', v_token));
  set local role anon;
  begin
    update public.service_order_signatures set accepted_name = 'Anon' where service_order_id = v_os;
    v_msg := 'gravou';
  exception when insufficient_privilege then v_msg := 'sem permissão';
  end;
  begin
    insert into public.service_order_signatures (service_order_id, share_token, accepted_name, document_hash)
    values (v_os, v_token, 'Anon', 'x');
    v_msg := v_msg || ' / inseriu';
  exception when insufficient_privilege then v_msg := v_msg || ' / sem permissão';
  end;
  reset role;
  insert into _resultado values ('A5 anon não grava', v_msg = 'sem permissão / sem permissão', v_msg);
end $$;

-- A6: o caminho da edge submit-signature (service_role): reassinatura substitui a anterior e grava a nova.
do $$
declare v_os uuid := current_setting('teste.os2')::uuid; v_token uuid; v_n int; v_validas int; v_total int;
begin
  select share_token into v_token from public.service_orders where id = v_os;
  perform pg_temp._req(null, 'service_role');
  set local role service_role;
  update public.service_order_signatures set superseded_at = now(), superseded_reason = 'Reassinatura solicitada'
   where service_order_id = v_os and superseded_at is null;
  get diagnostics v_n = row_count;
  insert into public.service_order_signatures (service_order_id, share_token, accepted_name, document_hash)
  values (v_os, v_token, 'Cliente Reassinou', 'hash-novo');
  reset role;
  select count(*) filter (where superseded_at is null), count(*) into v_validas, v_total
    from public.service_order_signatures where service_order_id = v_os;
  insert into _resultado values ('A6 submit-signature (service_role) grava e substitui', v_n = 1 and v_validas = 1 and v_total = 2,
    format('substituídas=%s válidas=%s total=%s', v_n, v_validas, v_total));
end $$;

-- A7: técnico mexe no cabeçalho de uma OS assinada — o sistema derruba a assinatura velha.
do $$
declare v_os uuid := current_setting('teste.os3')::uuid; v_sub timestamptz; v_motivo text; v_req boolean;
begin
  perform pg_temp._req(current_setting('teste.tec')::uuid, 'authenticated');
  set local role authenticated;
  update public.service_orders set problem_description = 'descrição mudada depois de assinar' where id = v_os;
  reset role;
  select superseded_at, superseded_reason into v_sub, v_motivo from public.service_order_signatures where service_order_id = v_os;
  select requires_resignature into v_req from public.service_orders where id = v_os;
  insert into _resultado values ('A7 cabeçalho mudado pelo técnico: assinatura deixa de valer',
    v_sub is not null and v_motivo = 'OS alterada após assinatura' and v_req,
    format('substituída=%s motivo=%s pede_nova=%s', v_sub is not null, v_motivo, v_req));
end $$;

-- A8: técnico muda a quantidade da peça de uma OS assinada (OS 1: a assinatura ainda vale lá).
do $$
declare v_os uuid := current_setting('teste.os1')::uuid; v_sub timestamptz; v_motivo text;
begin
  perform pg_temp._req(current_setting('teste.tec')::uuid, 'authenticated');
  set local role authenticated;
  update public.service_order_parts set quantity = 3, line_total_sale = 300, line_total_cost = 150 where service_order_id = v_os;
  reset role;
  select superseded_at, superseded_reason into v_sub, v_motivo from public.service_order_signatures where service_order_id = v_os;
  insert into _resultado values ('A8 peça mudada pelo técnico: assinatura deixa de valer',
    v_sub is not null and v_motivo = 'Itens alterados após assinatura', format('substituída=%s motivo=%s', v_sub is not null, v_motivo));
end $$;

-- A9: o portal do cliente (anon, token do link no cabeçalho) lê a assinatura válida da OS 2.
do $$
declare v_os uuid := current_setting('teste.os2')::uuid; v_token uuid; v_nome text;
begin
  select share_token into v_token from public.service_orders where id = v_os;
  perform pg_temp._req(null, 'anon', jsonb_build_object('x-share-token', v_token));
  set local role anon;
  select accepted_name into v_nome from public.service_order_signatures
   where service_order_id = v_os and superseded_at is null order by signed_at desc limit 1;
  reset role;
  insert into _resultado values ('A9 portal do cliente lê a assinatura', v_nome = 'Cliente Reassinou', coalesce(v_nome, '(nada)'));
end $$;

-- A10: privilégios.
insert into _resultado
select 'A10a policy de UPDATE só de authenticated e por cargo',
       roles = '{authenticated}' and qual ilike '%is_admin_or_financial(%' and with_check ilike '%is_admin_or_financial(%',
       format('roles=%s qual=%s', roles, qual)
  from pg_policies where tablename = 'service_order_signatures' and policyname = 'auth_update_signatures';
insert into _resultado
select 'A10b gatilho definer e fechado para anon/authenticated',
       p.prosecdef
         and not has_function_privilege('anon', p.oid, 'execute')
         and not has_function_privilege('authenticated', p.oid, 'execute'),
       format('definer=%s anon=%s auth=%s', p.prosecdef, has_function_privilege('anon', p.oid, 'execute'),
              has_function_privilege('authenticated', p.oid, 'execute'))
  from pg_proc p where p.oid = 'public.detect_so_change_after_signature()'::regprocedure;
insert into _resultado
select 'A10c anon só lê a tabela',
       has_table_privilege('anon', 'public.service_order_signatures', 'select')
         and not has_table_privilege('anon', 'public.service_order_signatures', 'insert')
         and not has_table_privilege('anon', 'public.service_order_signatures', 'update')
         and not has_table_privilege('anon', 'public.service_order_signatures', 'delete'),
       'select/insert/update/delete';

select teste, ok, detalhe from _resultado order by teste;
rollback;
