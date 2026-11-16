-- Prova: consulta e restauração do histórico de documentos (migrations 20270121100100 e 20270121100200).
--
--   C1  alteracoes: um salvamento vira UM evento com o autor, a peça pelo nome e "Quantidade 2 → 3"
--   C2  alteracoes: valor em R$ e situação em português
--   C3  versoes: lista v1 (enviado) e v2 (aprovado)
--   C4  ver_versao: a v1 mostra a peça com a quantidade de então
--   C5  comparar: v1 × atual acusa a peça alterada e o serviço incluído
--   C6  técnico não consulta (42501)
--   C7  documento por número (ORÇ escrito com C)
--   R1  simular volta para v1: mostra o que muda e NÃO grava nada
--   R2  restaurar v1 de verdade: peça volta a 3, serviço incluído depois sai, total recalculado, versão "restaurado"
--   R3  desfazer um evento: a descrição volta
--   R4  desfazer campo que foi mudado de novo depois: não mexe e avisa
--   R5  conferir_hash diferente: recusa ("mudou depois do pedido")
--   R6  documento concluído: recusa
--   R7  técnico não restaura (42501)
--   R8  a peça removida volta com o MESMO id
--
-- ═══ COMO RODAR ═══ (DEPOIS das três migrations aplicadas; a partir do repositório principal)
--   npx supabase@2.111.0 db query --linked -f supabase/tests/historico_documentos_consulta.sql --output json
-- Seguro em produção: tudo nasce aqui e termina em ROLLBACK. Todas as linhas com ok = true.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._usuario(p_role text) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste Consulta (' || p_role || ')', 'teste-hcons-' || v_id || '@teste.invalido', p_role, true);
  return v_id;
end $$;

create function pg_temp._req(p_sub uuid, p_papel text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_papel is null then '' else json_build_object('sub', p_sub, 'role', p_papel)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_sub::text, ''), true);
  perform set_config('request.headers', '', true);
  perform set_config('marineflow.historico_interno', '', true);
  perform set_config('marineflow.historico_origem', '', true);
  perform set_config('marineflow.historico_ator', '', true);
  perform set_config('marineflow.historico_motivo', '', true);
end $$;

do $$
declare
  v_admin uuid := pg_temp._usuario('admin');
  v_tec   uuid := pg_temp._usuario('technician');
  v_cli uuid; v_barco uuid; v_os uuid; v_num text; v_peca uuid; v_peca2 uuid; v_serv uuid;
  v_prod uuid := (select id from public.products order by created_at limit 1);
  r jsonb; v_msg text; v_ev uuid; v_n int; v_q numeric; v_tot numeric;
begin
  perform pg_temp._req(v_admin, 'authenticated');
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Consulta') returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Barco Teste Consulta') returning id into v_barco;
  v_num := 'ORÇ-TESTE' || substr(md5(random()::text), 1, 6);
  insert into public.service_orders (service_order_number, client_id, vessel_id, problem_description, status, quote_status)
  values (v_num, v_cli, v_barco, 'descrição v1', 'draft', 'draft') returning id into v_os;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, line_total_cost, unit_sale_snapshot, line_total_sale)
  values (v_os, v_prod, 3, 50, 150, 100, 300) returning id into v_peca;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, line_total_cost, unit_sale_snapshot, line_total_sale)
  values (v_os, v_prod, 1, 10, 10, 20, 20) returning id into v_peca2;
  perform public.recalc_so_totals(v_os);
  update public.service_orders set quote_status = 'sent' where id = v_os;                 -- v1

  -- "um salvamento": quantidade + descrição
  update public.service_order_parts set quantity = 5, line_total_sale = 500, line_total_cost = 250 where id = v_peca;
  update public.service_orders set problem_description = 'descrição v2' where id = v_os;
  insert into public.service_order_services (service_order_id, name_snapshot, quantity, unit_price_snapshot, line_total)
  values (v_os, 'Serviço incluído depois', 1, 1000, 1000) returning id into v_serv;
  delete from public.service_order_parts where id = v_peca2;
  perform public.recalc_so_totals(v_os);
  update public.service_orders set quote_status = 'approved' where id = v_os;             -- v2

  -- C1/C2
  r := public.documento_historico('os', v_os::text, 'alteracoes', null, null, null, null, 50);
  insert into _resultado values ('C1 evento com peça pelo nome e quantidade',
    (r::text like '%Quantidade%') and (r::text like '%Peça: %') and (r::text like '%Teste Consulta (admin)%')
    and (r ->> 'total_de_eventos')::int >= 1,
    left(r::text, 300));
  insert into _resultado values ('C2 R$ e situação em português', r::text like '%R$ %' and r::text like '%Aprovado%', '');

  -- C3
  r := public.documento_historico('os', v_os::text, 'versoes');
  insert into _resultado values ('C3 versões v1 e v2', jsonb_array_length(r -> 'versoes') = 2
    and r -> 'versoes' -> 0 ->> 'marco' = 'aprovado' and r -> 'versoes' -> 1 ->> 'marco' = 'enviado', left(r::text, 300));

  -- C4
  r := public.documento_historico('os', v_os::text, 'ver_versao', 1);
  insert into _resultado values ('C4 v1 com a quantidade de então',
    exists (select 1 from jsonb_array_elements(r -> 'conteudo' -> 'pecas') p where (p ->> 'quantidade')::numeric = 3)
    and jsonb_array_length(r -> 'conteudo' -> 'pecas') = 2,
    left((r -> 'conteudo')::text, 300));

  -- C5
  r := public.documento_historico('os', v_os::text, 'comparar', 1);
  insert into _resultado values ('C5 comparar v1 x atual',
    jsonb_array_length(r -> 'diferencas' -> 'itens_alterados') = 1 and jsonb_array_length(r -> 'diferencas' -> 'itens_incluidos') = 1
    and jsonb_array_length(r -> 'diferencas' -> 'itens_removidos') = 1,
    left((r -> 'diferencas')::text, 400));

  -- C7
  r := public.documento_historico('os', replace(v_num, 'Ç', 'C'), 'versoes');
  insert into _resultado values ('C7 número com C no lugar de Ç', r -> 'documento' ->> 'numero' = v_num, r -> 'documento' ->> 'numero');

  -- C6
  perform pg_temp._req(v_tec, 'authenticated');
  begin
    r := public.documento_historico('os', v_os::text);
    v_msg := 'leu';
  exception when insufficient_privilege then v_msg := 'recusado';
  end;
  insert into _resultado values ('C6 técnico não consulta', v_msg = 'recusado', v_msg);

  -- R7
  begin
    r := public.documento_restaurar(v_os::text, 1);
    v_msg := 'restaurou';
  exception when insufficient_privilege then v_msg := 'recusado';
  end;
  insert into _resultado values ('R7 técnico não restaura', v_msg = 'recusado', v_msg);

  -- R1
  perform pg_temp._req(v_admin, 'authenticated');
  v_n := (select count(*) from public.audit_log where doc_id = v_os);
  r := public.documento_restaurar(v_os::text, 1, null, 'teste', true);
  insert into _resultado values ('R1 simulação mostra e não grava',
    (r ->> 'simulacao')::boolean and not (r ->> 'restaurado')::boolean
    and (select quantity from public.service_order_parts where id = v_peca) = 5
    and (select count(*) from public.audit_log where doc_id = v_os) = v_n
    and jsonb_array_length(r -> 'o_que_muda' -> 'itens_removidos') = 1,
    left(r::text, 400));

  -- R5
  begin
    r := public.documento_restaurar(v_os::text, 1, null, 'teste', false, 'hash-que-nao-bate');
    v_msg := 'restaurou';
  exception when raise_exception then v_msg := sqlerrm;
  end;
  insert into _resultado values ('R5 documento mudou desde o pedido', v_msg like '%mudou depois do pedido%', v_msg);

  -- R2 / R8
  r := public.documento_restaurar(v_os::text, 1, null, 'cliente voltou atrás', false);
  select quantity into v_q from public.service_order_parts where id = v_peca;
  insert into _resultado values ('R2 voltou para v1',
    (r ->> 'restaurado')::boolean and v_q = 3
    and not exists (select 1 from public.service_order_services where id = v_serv)
    and (select problem_description from public.service_orders where id = v_os) = 'descrição v1'
    and (select grand_total from public.service_orders where id = v_os) =
        (select sum(line_total_sale) from public.service_order_parts where service_order_id = v_os)
    and exists (select 1 from public.audit_log where doc_id = v_os and action = 'versao' and reason = 'restaurado')
    and exists (select 1 from public.audit_log where doc_id = v_os and action = 'restore'),
    left(r::text, 300));
  insert into _resultado values ('R8 peça removida volta com o mesmo id', exists (select 1 from public.service_order_parts where id = v_peca2), '');

  -- R3: desfazer a mudança de descrição feita agora
  update public.service_orders set problem_description = 'descrição errada' where id = v_os;
  select id into v_ev from public.audit_log
   where doc_id = v_os and table_name = 'service_orders' and action = 'update' and new_value ->> 'problem_description' = 'descrição errada';
  r := public.documento_restaurar(v_os::text, null, array[v_ev], 'digitei errado', false);
  insert into _resultado values ('R3 desfazer a descrição', (select problem_description from public.service_orders where id = v_os) = 'descrição v1',
    left(r::text, 300));

  -- R4: o campo mudou de novo depois do evento
  update public.service_orders set extra_notes = 'A' where id = v_os;
  select id into v_ev from public.audit_log
   where doc_id = v_os and table_name = 'service_orders' and action = 'update' and new_value ->> 'extra_notes' = 'A';
  update public.service_orders set extra_notes = 'B' where id = v_os;
  r := public.documento_restaurar(v_os::text, null, array[v_ev], null, false);
  insert into _resultado values ('R4 conflito não mexe e avisa', (select extra_notes from public.service_orders where id = v_os) = 'B'
    and jsonb_array_length(r -> 'nao_desfeito') = 1, left((r -> 'nao_desfeito')::text, 300));

  -- R9: linha forjada pela API (pendurada neste documento, apontando para a peça) não se desfaz
  insert into public.audit_log (table_name, record_id, action, new_value, previous_value)
  values ('service_orders', v_os, 'update', jsonb_build_object('problem_description', 'descrição v1'),
          jsonb_build_object('problem_description', 'FORJADO'))
  returning id into v_ev;
  r := public.documento_restaurar(v_os::text, null, array[v_ev], null, false);
  insert into _resultado values ('R9 linha da API não se desfaz',
    (select problem_description from public.service_orders where id = v_os) = 'descrição v1'
    and r -> 'nao_desfeito' -> 0 ->> 'motivo' like 'registro antigo ou manual%', left((r -> 'nao_desfeito')::text, 300));

  -- R10: registro manual sem o valor de antes (como o "converter sem sinal" gravava) não apaga o campo
  update public.service_orders set payment_conditions = 'à vista' where id = v_os;
  insert into public.audit_log (table_name, record_id, action, new_value)
  values ('service_orders', v_os, 'update', jsonb_build_object('payment_conditions', 'à vista', 'motivo', 'converter sem sinal'))
  returning id into v_ev;
  r := public.documento_restaurar(v_os::text, null, array[v_ev], null, false);
  insert into _resultado values ('R10 sem valor de antes não vira vazio',
    (select payment_conditions from public.service_orders where id = v_os) = 'à vista', left(r::text, 300));

  -- C8: o histórico marca o que dá para desfazer
  r := public.documento_historico('os', v_os::text, 'alteracoes', null, null, null, null, 50);
  insert into _resultado values ('C8 itens marcados desfazível ou não',
    exists (select 1 from jsonb_array_elements(r -> 'eventos') e, jsonb_array_elements(e -> 'itens') i where (i ->> 'desfazivel')::boolean)
    and exists (select 1 from jsonb_array_elements(r -> 'eventos') e, jsonb_array_elements(e -> 'itens') i
                 where i ->> 'registro_id' = v_ev::text and not (i ->> 'desfazivel')::boolean),
    '');

  -- R6
  update public.service_orders set status = 'completed' where id = v_os;
  begin
    r := public.documento_restaurar(v_os::text, 1, null, null, true);
    v_msg := 'restaurou';
  exception when raise_exception then v_msg := sqlerrm;
  end;
  insert into _resultado values ('R6 concluída não restaura', v_msg like '%só documento em aberto%', v_msg);
end $$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
