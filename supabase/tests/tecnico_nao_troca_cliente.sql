-- Prova: técnico não troca o cliente de uma OS (migration 20261021160000_tecnico_nao_troca_cliente_da_os).
--
--   T1  técnico ativo trocando client_id: recusado, com a mensagem; a OS fica com o cliente antigo
--   T2  técnico mudando OUTRO campo da mesma OS (descrição): passa
--   T3  admin trocando client_id: passa
--   T4  técnico INATIVO trocando: passa (a regra é do cargo ativo; inativo nem entra no app)
--   T5  sem sessão (service_role / cron / assistente): passa
--   T6  técnico CRIANDO OS com cliente: passa (escolher o primeiro cliente não é trocar)
--   T7  privilégios: ninguém executa a função de gatilho direto (anon e authenticated sem EXECUTE)
--   T8  técnico pondo embarcação de OUTRO cliente (tela velha depois da troca de cliente): recusado
--   T9  técnico trocando para outra embarcação do MESMO cliente: passa
--   T10 OS de barco vendido (dono mudou), técnico mexe em outro campo sem trocar a embarcação: passa
--
-- ═══ COMO RODAR ═══ (só com OK nomeado; DEPOIS da migration aplicada)
--   npx supabase@2.111.0 db query --linked -f supabase/tests/tecnico_nao_troca_cliente.sql --output json
--   (a partir do repositório principal: o worktree não é linkado)
--
-- Seguro em produção: usuários, clientes, barco e OS de teste nascem aqui; termina em ROLLBACK.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._usuario(p_role text, p_ativo boolean default true) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste troca cliente (' || p_role || ')', 'teste-troca-' || v_id || '@teste.invalido', p_role, p_ativo);
  return v_id;
end $$;

create function pg_temp._entrar(p_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case when p_id is null then '' else json_build_object('sub', p_id)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_id::text, ''), true);
end $$;

do $$
declare
  v_tec uuid := pg_temp._usuario('technician');
  v_tec_inativo uuid := pg_temp._usuario('technician', false);
  v_admin uuid := pg_temp._usuario('admin');
  v_c1 uuid; v_c2 uuid; v_barco uuid; v_barco_b uuid; v_barco_a2 uuid; v_os uuid; v_os2 uuid; v_os3 uuid;
  v_cli_agora uuid; v_barco_agora uuid; v_msg text;
begin
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Troca A') returning id into v_c1;
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Troca B') returning id into v_c2;
  insert into public.vessels (client_id, name) values (v_c1, 'Barco Teste Troca') returning id into v_barco;
  insert into public.vessels (client_id, name) values (v_c2, 'Barco Teste Troca do B') returning id into v_barco_b;
  insert into public.vessels (client_id, name) values (v_c1, 'Segundo Barco Teste Troca') returning id into v_barco_a2;
  -- número de teste: não gasta a numeração de verdade
  insert into public.service_orders (service_order_number, client_id, vessel_id, problem_description, status)
  values ('TESTE-TROCA-' || substr(md5(random()::text), 1, 8), v_c1, v_barco, 'teste troca de cliente', 'draft')
  returning id into v_os;

  -- T1
  perform pg_temp._entrar(v_tec);
  begin
    update public.service_orders set client_id = v_c2 where id = v_os;
    v_msg := null;
  exception when insufficient_privilege then
    v_msg := sqlerrm;
  end;
  select client_id into v_cli_agora from public.service_orders where id = v_os;
  insert into _resultado values ('T1 técnico não troca', v_msg = 'Só o escritório troca o cliente de uma OS.' and v_cli_agora = v_c1, coalesce(v_msg, 'passou sem erro'));

  -- T2
  begin
    update public.service_orders set problem_description = 'mudou a descrição' where id = v_os;
    insert into _resultado values ('T2 técnico muda outro campo', true, null);
  exception when others then
    insert into _resultado values ('T2 técnico muda outro campo', false, sqlerrm);
  end;

  -- T3
  perform pg_temp._entrar(v_admin);
  begin
    update public.service_orders set client_id = v_c2 where id = v_os;
    select client_id into v_cli_agora from public.service_orders where id = v_os;
    insert into _resultado values ('T3 admin troca', v_cli_agora = v_c2, null);
  exception when others then
    insert into _resultado values ('T3 admin troca', false, sqlerrm);
  end;

  -- T4
  perform pg_temp._entrar(v_tec_inativo);
  begin
    update public.service_orders set client_id = v_c1 where id = v_os;
    insert into _resultado values ('T4 técnico inativo', true, null);
  exception when others then
    insert into _resultado values ('T4 técnico inativo', false, sqlerrm);
  end;

  -- T5
  perform pg_temp._entrar(null);
  begin
    update public.service_orders set client_id = v_c2 where id = v_os;
    insert into _resultado values ('T5 sem sessão', true, null);
  exception when others then
    insert into _resultado values ('T5 sem sessão', false, sqlerrm);
  end;

  -- T6
  perform pg_temp._entrar(v_tec);
  begin
    insert into public.service_orders (service_order_number, client_id, vessel_id, problem_description, status)
    values ('TESTE-TROCA-' || substr(md5(random()::text), 1, 8), v_c1, v_barco, 'técnico cria OS', 'draft')
    returning id into v_os2;
    insert into _resultado values ('T6 técnico cria OS', v_os2 is not null, null);
  exception when others then
    insert into _resultado values ('T6 técnico cria OS', false, sqlerrm);
  end;

  -- T8 (v_os2: cliente A, barco do A; o técnico manda o barco do B)
  begin
    update public.service_orders set vessel_id = v_barco_b where id = v_os2;
    v_msg := null;
  exception when insufficient_privilege then
    v_msg := sqlerrm;
  end;
  select vessel_id into v_barco_agora from public.service_orders where id = v_os2;
  insert into _resultado values ('T8 técnico não põe barco de outro cliente', v_msg = 'A embarcação ou veículo escolhido não é do cliente desta OS.' and v_barco_agora = v_barco, coalesce(v_msg, 'passou sem erro'));

  -- T9
  begin
    update public.service_orders set vessel_id = v_barco_a2 where id = v_os2;
    select vessel_id into v_barco_agora from public.service_orders where id = v_os2;
    insert into _resultado values ('T9 técnico troca para barco do mesmo cliente', v_barco_agora = v_barco_a2, null);
  exception when others then
    insert into _resultado values ('T9 técnico troca para barco do mesmo cliente', false, sqlerrm);
  end;

  -- T10 (o barco v_barco_a2 é vendido ao cliente B; a OS antiga continua com ele e com o cliente A)
  perform pg_temp._entrar(null);
  update public.vessels set client_id = v_c2 where id = v_barco_a2;
  perform pg_temp._entrar(v_tec);
  begin
    update public.service_orders set problem_description = 'depois da venda do barco', vessel_id = v_barco_a2 where id = v_os2;
    insert into _resultado values ('T10 OS de barco vendido segue editável', true, null);
  exception when others then
    insert into _resultado values ('T10 OS de barco vendido segue editável', false, sqlerrm);
  end;
  perform pg_temp._entrar(null);
end $$;

-- T7
insert into _resultado
select 'T7 ninguém executa a função de gatilho',
       not has_function_privilege('anon', 'public._os_tecnico_nao_troca_cliente()', 'EXECUTE')
       and not has_function_privilege('authenticated', 'public._os_tecnico_nao_troca_cliente()', 'EXECUTE'),
       null;

select teste, ok, detalhe from _resultado order by teste;

rollback;
