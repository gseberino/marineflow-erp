-- Prova: técnico não troca a embarcação/veículo de uma OS, o dono de uma embarcação/veículo, nem o
-- nome, o CPF/CNPJ ou o tipo de um cliente (migration 20261022180000_tecnico_cadastro_e_embarcacao).
--
--   OS (service_orders.vessel_id)
--   E1  técnico ativo trocando a embarcação de OS que já tem uma (mesmo cliente): recusado, com a
--       mensagem; a OS fica com a embarcação antiga
--   E2  técnico tirando a embarcação (vessel_id nulo): recusado pelo gatilho, com a mensagem (ele
--       roda antes do NOT NULL da coluna)
--   E3  técnico pondo embarcação de OUTRO cliente: recusado com a mensagem de antes ("não é do
--       cliente desta OS" vem primeiro: o aviso dela é o que resolve a tela velha)
--   E4  técnico mudando OUTRO campo da OS mandando a MESMA embarcação no SET: passa
--   E5  admin troca a embarcação: passa
--   E6  sem sessão (service_role / cron / assistente) troca: passa
--   E7  técnico INATIVO troca: passa
--   E8  primeira unidade: técnico CRIA OS já com a embarcação: passa (service_orders.vessel_id é
--       NOT NULL desde antes de 22/10 — 0 de 124 OS sem unidade —, então escolher a primeira é criar)
--
--   Embarcação/veículo (vessels.client_id)
--   D1  técnico trocando o dono: recusado, com a mensagem; o dono fica
--   D2  técnico mudando outro campo (nome, local e acesso) mandando o MESMO client_id no SET: passa
--   D3  admin troca o dono: passa
--   D4  sem sessão troca o dono: passa
--   D5  técnico inativo troca o dono: passa
--   D6  técnico CRIA embarcação para um cliente: passa
--
--   Cliente (clients.name, cpf_cnpj, type)
--   C1  técnico mudando o nome: recusado, com a mensagem; o nome fica
--   C2  técnico mudando o CPF/CNPJ: recusado
--   C3  técnico mudando o tipo (PF → PJ): recusado
--   C4  técnico mudando telefone, e-mail e endereço, com nome/CPF/tipo IGUAIS no SET (o diálogo
--       antigo manda tudo): passa e grava
--   C5  admin muda nome, CPF/CNPJ e tipo: passa
--   C6  sem sessão muda o nome: passa
--   C7  técnico inativo muda o nome: passa
--   C8  técnico CRIA cliente: passa
--
--   P1  privilégios: ninguém executa as três funções de gatilho direto (anon e authenticated sem EXECUTE)
--   P2  os gatilhos estão no lugar: BEFORE UPDATE OF client_id em vessels; BEFORE UPDATE OF name,
--       cpf_cnpj, type em clients; o da OS segue BEFORE UPDATE OF client_id, vessel_id
--
-- ═══ COMO RODAR ═══ (só com OK nomeado; DEPOIS da migration aplicada)
--   npx supabase@2.111.0 db query --linked -f supabase/tests/tecnico_cadastro_e_embarcacao.sql --output json
--   (a partir do repositório principal: o worktree não é linkado)
--
-- Seguro em produção: usuários, clientes, barcos e OS de teste nascem aqui; termina em ROLLBACK.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._usuario(p_role text, p_ativo boolean default true) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste cadastro (' || p_role || ')', 'teste-cadastro-' || v_id || '@teste.invalido', p_role, p_ativo);
  return v_id;
end $$;

create function pg_temp._entrar(p_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case when p_id is null then '' else json_build_object('sub', p_id)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_id::text, ''), true);
end $$;

-- Roda o UPDATE como texto e devolve a mensagem da recusa (42501) ou null se passou. Outro erro
-- qualquer volta como 'OUTRO ERRO: ...' — para o teste falhar dizendo o porquê.
create function pg_temp._tentar(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception
  when insufficient_privilege then return sqlerrm;
  when others then return 'OUTRO ERRO: ' || sqlerrm;
end $$;

do $$
declare
  v_tec uuid := pg_temp._usuario('technician');
  v_tec_inativo uuid := pg_temp._usuario('technician', false);
  v_admin uuid := pg_temp._usuario('admin');
  v_c1 uuid; v_c2 uuid; v_barco uuid; v_barco_a2 uuid; v_barco_b uuid; v_barco_novo uuid;
  v_os uuid; v_os2 uuid; v_cli_novo uuid;
  v_msg text; v_agora uuid; v_nome text; v_doc text; v_tipo text; v_fone text; v_email text; v_cidade text;
  c_os constant text := 'Só o escritório troca a embarcação ou veículo de uma OS.';
  c_outro constant text := 'A embarcação ou veículo escolhido não é do cliente desta OS.';
  c_dono constant text := 'Só o escritório troca o dono de uma embarcação ou veículo.';
  c_cli constant text := 'Só o escritório muda o nome, o CPF/CNPJ ou o tipo de um cliente.';
begin
  insert into public.clients (type, name, cpf_cnpj) values ('individual', 'Cliente Teste Cadastro A', '000.000.001-91') returning id into v_c1;
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Cadastro B') returning id into v_c2;
  insert into public.vessels (client_id, name) values (v_c1, 'Barco Teste Cadastro') returning id into v_barco;
  insert into public.vessels (client_id, name) values (v_c1, 'Segundo Barco Teste Cadastro') returning id into v_barco_a2;
  insert into public.vessels (client_id, name) values (v_c2, 'Barco Teste Cadastro do B') returning id into v_barco_b;
  -- número de teste: não gasta a numeração de verdade
  insert into public.service_orders (service_order_number, client_id, vessel_id, problem_description, status)
  values ('TESTE-CAD-' || substr(md5(random()::text), 1, 8), v_c1, v_barco, 'teste troca de embarcação', 'draft')
  returning id into v_os;

  -- ═══ OS ═══
  perform pg_temp._entrar(v_tec);

  -- E1
  v_msg := pg_temp._tentar(format('update public.service_orders set vessel_id = %L where id = %L', v_barco_a2, v_os));
  select vessel_id into v_agora from public.service_orders where id = v_os;
  insert into _resultado values ('E1 técnico não troca a embarcação da OS', v_msg is not distinct from c_os and v_agora = v_barco, coalesce(v_msg, 'passou sem erro'));

  -- E2
  v_msg := pg_temp._tentar(format('update public.service_orders set vessel_id = null where id = %L', v_os));
  select vessel_id into v_agora from public.service_orders where id = v_os;
  insert into _resultado values ('E2 técnico não tira a embarcação da OS', v_msg is not distinct from c_os and v_agora = v_barco, coalesce(v_msg, 'passou sem erro'));

  -- E3
  v_msg := pg_temp._tentar(format('update public.service_orders set vessel_id = %L where id = %L', v_barco_b, v_os));
  select vessel_id into v_agora from public.service_orders where id = v_os;
  insert into _resultado values ('E3 técnico não põe embarcação de outro cliente', v_msg is not distinct from c_outro and v_agora = v_barco, coalesce(v_msg, 'passou sem erro'));

  -- E4
  v_msg := pg_temp._tentar(format('update public.service_orders set problem_description = %L, vessel_id = %L where id = %L', 'mudou a descrição', v_barco, v_os));
  insert into _resultado values ('E4 técnico muda outro campo com a mesma embarcação', v_msg is null, v_msg);

  -- E5
  perform pg_temp._entrar(v_admin);
  v_msg := pg_temp._tentar(format('update public.service_orders set vessel_id = %L where id = %L', v_barco_a2, v_os));
  select vessel_id into v_agora from public.service_orders where id = v_os;
  insert into _resultado values ('E5 admin troca a embarcação', v_msg is null and v_agora = v_barco_a2, v_msg);

  -- E6
  perform pg_temp._entrar(null);
  v_msg := pg_temp._tentar(format('update public.service_orders set vessel_id = %L where id = %L', v_barco, v_os));
  select vessel_id into v_agora from public.service_orders where id = v_os;
  insert into _resultado values ('E6 sem sessão troca a embarcação', v_msg is null and v_agora = v_barco, v_msg);

  -- E7
  perform pg_temp._entrar(v_tec_inativo);
  v_msg := pg_temp._tentar(format('update public.service_orders set vessel_id = %L where id = %L', v_barco_a2, v_os));
  select vessel_id into v_agora from public.service_orders where id = v_os;
  insert into _resultado values ('E7 técnico inativo troca a embarcação', v_msg is null and v_agora = v_barco_a2, v_msg);

  -- E8
  perform pg_temp._entrar(v_tec);
  begin
    insert into public.service_orders (service_order_number, client_id, vessel_id, problem_description, status)
    values ('TESTE-CAD-' || substr(md5(random()::text), 1, 8), v_c1, v_barco, 'técnico cria OS com a primeira unidade', 'draft')
    returning id into v_os2;
    insert into _resultado values ('E8 técnico cria OS com a primeira unidade', v_os2 is not null, null);
  exception when others then
    insert into _resultado values ('E8 técnico cria OS com a primeira unidade', false, sqlerrm);
  end;

  -- ═══ Embarcação/veículo: o dono ═══
  -- D1
  v_msg := pg_temp._tentar(format('update public.vessels set client_id = %L where id = %L', v_c2, v_barco_a2));
  select client_id into v_agora from public.vessels where id = v_barco_a2;
  insert into _resultado values ('D1 técnico não troca o dono', v_msg is not distinct from c_dono and v_agora = v_c1, coalesce(v_msg, 'passou sem erro'));

  -- D2
  v_msg := pg_temp._tentar(format('update public.vessels set name = %L, access_notes = %L, client_id = %L where id = %L',
    'Segundo Barco Teste Cadastro (renomeado)', 'portaria 2', v_c1, v_barco_a2));
  insert into _resultado values ('D2 técnico muda outro campo com o mesmo dono', v_msg is null, v_msg);

  -- D3
  perform pg_temp._entrar(v_admin);
  v_msg := pg_temp._tentar(format('update public.vessels set client_id = %L where id = %L', v_c2, v_barco_a2));
  select client_id into v_agora from public.vessels where id = v_barco_a2;
  insert into _resultado values ('D3 admin troca o dono', v_msg is null and v_agora = v_c2, v_msg);

  -- D4
  perform pg_temp._entrar(null);
  v_msg := pg_temp._tentar(format('update public.vessels set client_id = %L where id = %L', v_c1, v_barco_a2));
  select client_id into v_agora from public.vessels where id = v_barco_a2;
  insert into _resultado values ('D4 sem sessão troca o dono', v_msg is null and v_agora = v_c1, v_msg);

  -- D5
  perform pg_temp._entrar(v_tec_inativo);
  v_msg := pg_temp._tentar(format('update public.vessels set client_id = %L where id = %L', v_c2, v_barco_a2));
  select client_id into v_agora from public.vessels where id = v_barco_a2;
  insert into _resultado values ('D5 técnico inativo troca o dono', v_msg is null and v_agora = v_c2, v_msg);

  -- D6
  perform pg_temp._entrar(v_tec);
  begin
    insert into public.vessels (client_id, name) values (v_c2, 'Barco que o técnico cadastrou') returning id into v_barco_novo;
    insert into _resultado values ('D6 técnico cria embarcação', v_barco_novo is not null, null);
  exception when others then
    insert into _resultado values ('D6 técnico cria embarcação', false, sqlerrm);
  end;

  -- ═══ Cliente: nome, CPF/CNPJ e tipo ═══
  -- C1
  v_msg := pg_temp._tentar(format('update public.clients set name = %L where id = %L', 'Outro Nome', v_c1));
  select name into v_nome from public.clients where id = v_c1;
  insert into _resultado values ('C1 técnico não muda o nome', v_msg is not distinct from c_cli and v_nome = 'Cliente Teste Cadastro A', coalesce(v_msg, 'passou sem erro'));

  -- C2
  v_msg := pg_temp._tentar(format('update public.clients set cpf_cnpj = %L where id = %L', '000.000.002-72', v_c1));
  select cpf_cnpj into v_doc from public.clients where id = v_c1;
  insert into _resultado values ('C2 técnico não muda o CPF/CNPJ', v_msg is not distinct from c_cli and v_doc = '000.000.001-91', coalesce(v_msg, 'passou sem erro'));

  -- C3
  v_msg := pg_temp._tentar(format('update public.clients set type = %L where id = %L', 'company', v_c1));
  select type into v_tipo from public.clients where id = v_c1;
  insert into _resultado values ('C3 técnico não muda o tipo', v_msg is not distinct from c_cli and v_tipo = 'individual', coalesce(v_msg, 'passou sem erro'));

  -- C4
  v_msg := pg_temp._tentar(format(
    'update public.clients set name = %L, cpf_cnpj = %L, type = %L, phone = %L, email = %L, city = %L where id = %L',
    'Cliente Teste Cadastro A', '000.000.001-91', 'individual', '(47) 98888-7777', 'novo@teste.invalido', 'Itajaí', v_c1));
  select phone, email, city into v_fone, v_email, v_cidade from public.clients where id = v_c1;
  insert into _resultado values ('C4 técnico muda telefone, e-mail e endereço',
    v_msg is null and v_fone = '(47) 98888-7777' and v_email = 'novo@teste.invalido' and v_cidade = 'Itajaí', v_msg);

  -- C5
  perform pg_temp._entrar(v_admin);
  v_msg := pg_temp._tentar(format('update public.clients set name = %L, cpf_cnpj = %L, type = %L where id = %L',
    'Cliente Teste Cadastro A Ltda', '00.000.000/0001-91', 'company', v_c1));
  select name, cpf_cnpj, type into v_nome, v_doc, v_tipo from public.clients where id = v_c1;
  insert into _resultado values ('C5 admin muda nome, CPF/CNPJ e tipo',
    v_msg is null and v_nome = 'Cliente Teste Cadastro A Ltda' and v_doc = '00.000.000/0001-91' and v_tipo = 'company', v_msg);

  -- C6
  perform pg_temp._entrar(null);
  v_msg := pg_temp._tentar(format('update public.clients set name = %L where id = %L', 'Cliente Teste Cadastro A (sem sessão)', v_c1));
  insert into _resultado values ('C6 sem sessão muda o nome', v_msg is null, v_msg);

  -- C7
  perform pg_temp._entrar(v_tec_inativo);
  v_msg := pg_temp._tentar(format('update public.clients set name = %L where id = %L', 'Cliente Teste Cadastro A (inativo)', v_c1));
  insert into _resultado values ('C7 técnico inativo muda o nome', v_msg is null, v_msg);

  -- C8
  perform pg_temp._entrar(v_tec);
  begin
    insert into public.clients (type, name) values ('individual', 'Cliente que o técnico cadastrou') returning id into v_cli_novo;
    insert into _resultado values ('C8 técnico cria cliente', v_cli_novo is not null, null);
  exception when others then
    insert into _resultado values ('C8 técnico cria cliente', false, sqlerrm);
  end;

  perform pg_temp._entrar(null);
end $$;

-- P1 (função que não existe conta como falha, sem derrubar o resto da prova)
insert into _resultado
select 'P1 ninguém executa as funções de gatilho',
       bool_and(aberta is false),
       string_agg(f || case when aberta is null then ' (não existe)' else '' end, ', ') filter (where aberta is not false)
from (
  select f, case when to_regprocedure(f) is null then null
                 else has_function_privilege('anon', f, 'EXECUTE') or has_function_privilege('authenticated', f, 'EXECUTE') end as aberta
  from unnest(array[
    'public._os_tecnico_nao_troca_cliente()',
    'public._unidade_tecnico_nao_troca_dono()',
    'public._cliente_tecnico_nao_muda_identidade()'
  ]) as f
) as funcoes;

-- P2
insert into _resultado
select 'P2 gatilhos no lugar',
       exists (select 1 from pg_trigger t where t.tgrelid = 'public.vessels'::regclass and t.tgname = 'unidade_tecnico_nao_troca_dono'
               and pg_get_triggerdef(t.oid) like '%BEFORE UPDATE OF client_id ON public.vessels FOR EACH ROW%')
   and exists (select 1 from pg_trigger t where t.tgrelid = 'public.clients'::regclass and t.tgname = 'cliente_tecnico_nao_muda_identidade'
               and pg_get_triggerdef(t.oid) like '%BEFORE UPDATE OF name, cpf_cnpj, type ON public.clients FOR EACH ROW%')
   and exists (select 1 from pg_trigger t where t.tgrelid = 'public.service_orders'::regclass and t.tgname = 'os_tecnico_nao_troca_cliente'
               and pg_get_triggerdef(t.oid) like '%BEFORE UPDATE OF client_id, vessel_id ON public.service_orders FOR EACH ROW%'),
       null;

select teste, ok, detalhe from _resultado order by teste;

rollback;
