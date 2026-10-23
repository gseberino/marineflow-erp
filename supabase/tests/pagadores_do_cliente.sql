-- Prova: pagadores do cliente (migration 20261022190000_pagadores_do_cliente).
--
--   T0  nenhum documento de teste existe em clients (senão as recusas de "outro cliente" mentem)
--   T1  anon não lê a tabela nem a view e não executa as funções; as internas ficam fechadas para todos
--   T2  técnico e vendedor: não leem pagador nenhum, não veem quem pagou na view, a lista vem vazia, e não guardam
--   T3  financeiro guarda: fica 'proposto', sem confirmado_em, com origem 'historico' e a prova (a linha do banco)
--   T4  financeiro não confirma (é o SIM do dono)
--   T5  admin confirma o proposto: 'confirmado', com quem e quando
--   T6  admin guarda direto: 'confirmado'; a regra de entrada do mesmo documento deixa de apontar o cliente (mantém a
--       categoria) e a trilha registra a regra consolidada; documento e nome vêm da linha do banco, não do pedido
--   T7  cada recusa de validação, com o motivo, no mesmo lote (e a linha esperando na fila é aceita, origem 'fila')
--   T8  lote vazio e lote com mais de 50: recusados inteiros
--   T9  financeiro não mexe no que o dono decidiu: não recusa nem pausa o confirmado (decidir e guardar), não mexe no
--       pausado (decidir e recusar_pagadores), não reativa; o admin recusa, reativa e pausa
--   T10 pagadores_para_conferir: grupo, aviso (pagou para vários clientes, documento de outro cliente); recusado e
--       guardado não voltam; documento do próprio cliente, CNPJ da HBR (ligado a uma conta do A) e cliente inativo (com
--       conta paga por terceiro) não aparecem
--   T11 cada situação da view (cliente, terceiro com e sem relação, indefinido, sem_dado) e o pagamento em dinheiro de
--       uma conta paga em parte por Pix que NÃO herda o pagador do Pix
--   T12 o PROPOSTO pelo financeiro continua na lista (pagador_id, situacao, relacao_proposta, quem e quando) até o
--       SIM do administrador; confirmado, sai
--   T13 aviso 'ligacao_duvidosa': a única ligação do par é a conciliação (reconciled_payment_id) para um pagamento que
--       já tem OUTRA linha do banco (o caso MUNDO DOCE COLOMBO 9d5f1352)
--   T14 recusar_pagadores_do_cliente: grava 'recusado' a partir da linha do banco e o par não volta; repetir não muda
--       nada; o documento de outro cliente também sai da lista; o financeiro não desfaz o confirmado (o admin sim);
--       cada recusa de validação; técnico/vendedor barrados; lote vazio e grande
--   T15 regra antiga de entrada do mesmo documento apontando OUTRO cliente: guardar e decidir avisam, a regra fica
--       como está (é o vínculo com o outro cliente) e a trilha registra o conflito
--   T16 consolidação da regra de entrada do MESMO cliente quando o proposto vira confirmado: pelo decidir('confirmar')
--       (o fluxo real da EQUIT) e pelo guardar do admin sobre o par que já existe; o admin troca a relação ao
--       confirmar (p_relacao), relação inválida e relação fora do 'confirmar' são recusadas
--   T17 o PROPOSTO que não está nas ligações (guardado pela fila): aparece na lista (vezes 1, a linha dele, grupo, quem
--       e quando), sai com o SIM; cliente inativo, documento do próprio cliente e CNPJ da HBR ficam de fora; conta como
--       "pagou para vários clientes" junto com um par de outro cliente
--   T18 a trava "documento de outro cliente" no decidir: confirmar um proposto e reativar um pausado cujo documento
--       passou a ser de outro cliente ativo são recusados, e a situação não muda (o proposto mostra o aviso na lista)
--
-- ═══ COMO RODAR ═══ (só com OK nomeado; DEPOIS da migration aplicada)
--   npx supabase@2.111.0 db query --linked -f supabase/tests/pagadores_do_cliente.sql --output json
--   (a partir do repositório principal: o worktree não é linkado)
--
-- Seguro em produção: usuários, clientes, linhas do banco, contas, pagamentos e a regra de teste nascem aqui; termina
-- em ROLLBACK. Documentos de mentira (começam com 90/91). A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._usuario(p_role text) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste pagadores (' || p_role || ')', 'teste-pagadores-' || v_id || '@teste.invalido', p_role, true);
  return v_id;
end $$;

-- Entra como um usuário logado (papel authenticated + o JWT dele); sair volta ao dono da sessão.
create function pg_temp._como(p_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_id::text, true);
  set local role authenticated;
end $$;

create function pg_temp._sair() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

create function pg_temp._linha(p_doc text, p_nome text, p_tipo text default 'credit', p_valor numeric default 100)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, counterparty_name, counterparty_document)
  values (current_date, 'Pix recebido (teste pagadores)', p_valor, p_tipo, p_nome, p_doc)
  returning id into v;
  return v;
end $$;

create function pg_temp._conta(p_cliente uuid, p_linha uuid default null, p_valor numeric default 100) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into public.receivables (client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status, bank_transaction_id)
  values (p_cliente, 'Conta de teste pagadores', current_date, current_date, p_valor, p_valor, 0, 'paid', p_linha)
  returning id into v;
  return v;
end $$;

create function pg_temp._pagamento(p_conta uuid, p_linha uuid default null, p_valor numeric default 100) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into public.payments (receivable_id, amount, payment_date, payment_method, status, bank_transaction_id)
  values (p_conta, p_valor, current_date, 'pix', 'confirmed', p_linha)
  returning id into v;
  return v;
end $$;

do $$
declare
  -- documentos de mentira
  c_cpf_a constant text := '90011122233';
  c_cnpj_c constant text := '90888777000166';
  c_cpf_e constant text := '90044455566';
  c_cpf_d constant text := '90077788899';
  c_p1 constant text := '91000000001';       -- cônjuge do A
  c_p2 constant text := '91222333000144';    -- empresa do A (tem regra de entrada → A)
  c_p3 constant text := '91000000003';       -- linha solta
  c_p4 constant text := '91000000004';       -- esperando na fila
  c_p5 constant text := '91555666000177';    -- paga pelo B e pelo C
  c_cpf_f constant text := '90055566677';
  c_cpf_g constant text := '90066677788';
  c_p6 constant text := '91000000006';       -- ligado ao F só pela conciliação torta
  c_p8 constant text := '91888999000188';    -- empresa que paga pelo F; regra antiga diz que é do G
  c_p9 constant text := '91000000009';       -- idem, proposto pelo financeiro e confirmado pelo admin
  c_p10 constant text := '91000000010';      -- proposto pelo financeiro (fica na lista)
  c_p7 constant text := '91000000007';       -- terceiro que pagou a conta do cliente INATIVO D
  c_cpf_h constant text := '90099900011';    -- cliente H (T16 a T18)
  c_p11 constant text := '91000000011';      -- solto na fila, proposto para o H
  c_p12 constant text := '91000000012';      -- solto na fila, proposto para o M (sem documento)
  c_p13 constant text := '91333444000155';   -- solto na fila; vira o CNPJ da HBR
  c_p14 constant text := '91000000014';      -- solto do H e par do F: pagou para vários clientes
  c_p15 constant text := '91000000015';      -- proposto do H; depois vira o documento do cliente J
  c_p16 constant text := '91000000016';      -- proposto e pausado do H; depois vira o documento do cliente K
  c_p17 constant text := '91777888000199';   -- empresa do H, com regra de entrada → H (consolida no decidir)
  c_p18 constant text := '91000000018';      -- parente do H, com regra de entrada → H (consolida no guardar)
  v_admin uuid := pg_temp._usuario('admin');
  v_fin uuid := pg_temp._usuario('financial');
  v_tec uuid := pg_temp._usuario('technician');
  v_vend uuid := pg_temp._usuario('seller');
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e uuid; v_f uuid; v_g uuid; v_h uuid; v_j_cli uuid; v_k_cli uuid; v_m_cli uuid;
  btd uuid; bty uuid; btp uuid; btr uuid; btq uuid; bti uuid;
  bts1 uuid; bts2 uuid; bts3 uuid; bts4 uuid; bts5 uuid; bts6 uuid; bts7 uuid; btc1 uuid; btc2 uuid;
  v_regra4 uuid; v_regra5 uuid; v_p uuid;
  r_f1 uuid; r_f2 uuid; r_f3 uuid; r_f4 uuid; p_f1 uuid;
  v_regra2 uuid; v_regra3 uuid;
  v_lista2 jsonb;
  v_hbr text;
  bt1 uuid; bt2 uuid; bt3 uuid; bt4 uuid; bt5 uuid; bt6 uuid; bt7 uuid; bt8 uuid; bt9 uuid; bt10 uuid; bt11 uuid; bt12 uuid;
  r_a1 uuid; r_a2 uuid; r_a3 uuid; r_a4 uuid; r_a5 uuid; r_a6 uuid; r_b1 uuid; r_c1 uuid;
  p_a1 uuid; p_a2 uuid; p_a3 uuid; p_a5pix uuid; p_a5cash uuid; p_a6 uuid; p_b1 uuid; p_c1 uuid;
  v_regra uuid;
  v_res jsonb;
  v_res2 jsonb;
  v_lista jsonb;
  v_view jsonb;
  v_msg text;
  v_estado text;
  v_n integer;
  v_m integer;
  v_k integer;
  v_id uuid;
  v_row record;
  v_ok boolean;
begin
  -- T0
  select count(*) into v_n from public.clients
   where public._doc_normalizado(cpf_cnpj) in (c_cpf_a, c_cnpj_c, c_cpf_e, c_cpf_d, c_p1, c_p2, c_p3, c_p4, c_p5,
                                                c_cpf_f, c_cpf_g, c_p6, c_p8, c_p9, c_p10, c_p7, c_cpf_h,
                                                c_p11, c_p12, c_p13, c_p14, c_p15, c_p16, c_p17, c_p18)
      or left(public._doc_normalizado(cpf_cnpj), 8) in (left(c_cnpj_c, 8), left(c_p2, 8), left(c_p5, 8), left(c_p8, 8),
                                                         left(c_p13, 8), left(c_p17, 8));
  insert into _resultado values ('T0 documentos de teste não existem', v_n = 0, v_n || ' cadastro(s) com documento de teste');

  -- O CNPJ da HBR (o de produção, se houver; senão um de teste dentro desta transação)
  v_hbr := public._doc_normalizado((select value from public.app_settings where key = 'cnpj'));
  if length(coalesce(v_hbr, '')) <> 14 then
    v_hbr := '90999888000100';
    insert into public.app_settings (key, value, description) values ('cnpj', v_hbr, 'teste pagadores')
    on conflict (key) do update set value = excluded.value;
  end if;

  insert into public.clients (type, name, cpf_cnpj) values ('individual', 'Cliente Teste Pagadores A', c_cpf_a) returning id into v_a;
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Pagadores B') returning id into v_b;
  insert into public.clients (type, name, cpf_cnpj) values ('company', 'Cliente Teste Pagadores C', c_cnpj_c) returning id into v_c;
  insert into public.clients (type, name, cpf_cnpj, active) values ('individual', 'Cliente Teste Pagadores D', c_cpf_d, false) returning id into v_d;
  insert into public.clients (type, name, cpf_cnpj) values ('individual', 'Cliente Teste Pagadores E', c_cpf_e) returning id into v_e;

  bt1 := pg_temp._linha(c_p1, 'CONJUGE DO A TESTE');
  bt2 := pg_temp._linha(c_p2, 'EMPRESA DO A TESTE LTDA');
  bt3 := pg_temp._linha(c_cpf_a, 'CLIENTE TESTE PAGADORES A');
  bt4 := pg_temp._linha(v_hbr, 'HBR (teste)');
  bt5 := pg_temp._linha(c_p1, 'CONJUGE DO A TESTE', 'debit');
  bt6 := pg_temp._linha(null, 'SEM DOCUMENTO TESTE');
  bt7 := pg_temp._linha(c_cpf_e, 'CLIENTE TESTE PAGADORES E');
  bt8 := pg_temp._linha(c_p3, 'SOLTO TESTE');
  bt9 := pg_temp._linha(c_p4, 'NA FILA TESTE');
  bt10 := pg_temp._linha(c_p5, 'PAGA POR DOIS TESTE LTDA');
  bt11 := pg_temp._linha(c_p5, 'PAGA POR DOIS TESTE LTDA');
  bt12 := pg_temp._linha(c_p1, 'CONJUGE DO A TESTE', 'credit', 60);

  -- ligação 1: receivables.bank_transaction_id (o pagamento sem a linha)
  r_a1 := pg_temp._conta(v_a, bt1);       p_a1 := pg_temp._pagamento(r_a1, null);
  -- ligação 2: payments.bank_transaction_id
  r_a2 := pg_temp._conta(v_a);            p_a2 := pg_temp._pagamento(r_a2, bt2);
  r_a3 := pg_temp._conta(v_a);            p_a3 := pg_temp._pagamento(r_a3, bt3);
  r_a4 := pg_temp._conta(v_a, bt7);
  -- conta paga em parte pelo Pix (bt12) e em parte em dinheiro
  r_a5 := pg_temp._conta(v_a, bt12, 100); p_a5pix := pg_temp._pagamento(r_a5, bt12, 60); p_a5cash := pg_temp._pagamento(r_a5, null, 40);
  -- pagamento em dinheiro, sem linha nenhuma
  r_a6 := pg_temp._conta(v_a);            p_a6 := pg_temp._pagamento(r_a6, null);
  -- ligação 3: bank_transactions.reconciled_payment_id (o B não tem documento)
  r_b1 := pg_temp._conta(v_b);            p_b1 := pg_temp._pagamento(r_b1, null);
  update public.bank_transactions set reconciled_payment_id = p_b1, reconciled = true where id = bt10;
  r_c1 := pg_temp._conta(v_c, bt11);      p_c1 := pg_temp._pagamento(r_c1, bt11);
  -- a linha da própria HBR ligada a uma conta do A, e a conta do cliente INATIVO D paga por um terceiro: as duas
  -- estão nas ligações, e a lista para conferir não pode mostrar nenhuma (T10)
  perform pg_temp._conta(v_a, bt4);
  bti := pg_temp._linha(c_p7, 'TERCEIRO DO INATIVO TESTE');
  perform pg_temp._conta(v_d, bti);

  insert into public.finance_review_queue (kind, status, bank_transaction_id, title, suggested_amount, suggested_date)
  values ('create_receivable', 'pending', bt9, 'Receita: NA FILA TESTE', 100, current_date);

  insert into public.finance_rules (match_type, match_value, direction, set_category, set_dre_group, set_client_id, autonomy, origin, status)
  values ('document', c_p2, 'credit', 'Serviços prestados', 'receita', v_a, 'suggest', 'user', 'active')
  returning id into v_regra;

  -- ── T2 (antes) técnico e vendedor não guardam ──
  foreach v_id in array array[v_tec, v_vend] loop
    perform pg_temp._como(v_id);
    begin
      v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt1, 'relacao', 'conjuge')));
      v_msg := null;
    exception when insufficient_privilege then
      v_msg := sqlerrm;
    end;
    perform pg_temp._sair();
    insert into _resultado values ('T2 técnico/vendedor não guardam', v_msg is not null, coalesce(v_msg, 'guardou sem erro'));
  end loop;

  -- ── T3 financeiro guarda: proposto ──
  perform pg_temp._como(v_fin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt1, 'relacao', 'conjuge')));
  perform pg_temp._sair();
  select * into v_row from public.pagadores_do_cliente where client_id = v_a and documento = c_p1;
  insert into _resultado values ('T3 financeiro grava proposto',
    v_res -> 'gravados' -> 0 ->> 'situacao' = 'proposto' and v_row.situacao = 'proposto' and v_row.confirmado_em is null
    and v_row.proposto_por = v_fin and v_row.origem = 'historico' and v_row.bank_transaction_id = bt1
    and v_row.nome = 'CONJUGE DO A TESTE' and v_res ->> 'message' like '1 pagador proposto%',
    v_res::text);

  -- ── T4 financeiro não confirma ──
  perform pg_temp._como(v_fin);
  begin
    perform public.decidir_pagador_do_cliente(v_row.id, 'confirmar');
    v_msg := null;
  exception when insufficient_privilege then
    v_msg := sqlerrm;
  end;
  perform pg_temp._sair();
  select situacao into v_estado from public.pagadores_do_cliente where id = v_row.id;
  insert into _resultado values ('T4 financeiro não confirma', v_msg is not null and v_estado = 'proposto', coalesce(v_msg, 'confirmou'));

  -- ── T5 admin confirma ──
  perform pg_temp._como(v_admin);
  v_res := public.decidir_pagador_do_cliente(v_row.id, 'confirmar');
  perform pg_temp._sair();
  select * into v_row from public.pagadores_do_cliente where id = v_row.id;
  insert into _resultado values ('T5 admin confirma',
    v_row.situacao = 'confirmado' and v_row.confirmado_por = v_admin and v_row.confirmado_em is not null
    and v_res ->> 'situacao' = 'confirmado'
    and exists (select 1 from public.reconciliation_log l where l.acao = 'decidiu_pagador_do_cliente' and l.autor = v_admin
                 and l.depois ->> 'pagador_id' = v_row.id::text),
    v_res::text);

  -- ── T6 admin guarda direto: confirmado + regra consolidada; o pedido não escolhe documento nem nome ──
  perform pg_temp._como(v_admin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object(
    'client_id', v_a, 'bank_transaction_id', bt2, 'relacao', 'empresa_do_cliente', 'observacao', 'a empresa dele',
    'documento', '00000000000', 'nome', 'NOME INVENTADO')));
  perform pg_temp._sair();
  select * into v_row from public.pagadores_do_cliente where client_id = v_a and documento = c_p2;
  insert into _resultado values ('T6 admin grava confirmado (documento e nome da linha do banco)',
    v_row.situacao = 'confirmado' and v_row.confirmado_por = v_admin and v_row.nome = 'EMPRESA DO A TESTE LTDA'
    and v_row.observacao = 'a empresa dele'
    and not exists (select 1 from public.pagadores_do_cliente where documento = '00000000000'),
    v_res::text);
  select count(*) into v_n from public.finance_rules
   where id = v_regra and set_client_id is null and set_category = 'Serviços prestados' and status = 'active';
  insert into _resultado values ('T6 regra de entrada consolidada (sem cliente, com categoria)',
    v_n = 1 and v_res -> 'regras_consolidadas' ? v_regra::text
    and exists (select 1 from public.reconciliation_log l where l.acao = 'guardou_pagador_do_cliente'
                 and l.finance_rule_id = v_regra and l.autor = v_admin and l.bank_transaction_id = bt2),
    v_res ->> 'message');

  -- ── T7 cada recusa, no mesmo lote ──
  perform pg_temp._como(v_admin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt5, 'relacao', 'conjuge'),             -- 1 saída
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt6, 'relacao', 'conjuge'),             -- 2 sem documento
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt3, 'relacao', 'conjuge'),             -- 3 próprio cliente
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt4, 'relacao', 'outro'),               -- 4 CNPJ da HBR
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt7, 'relacao', 'parente'),             -- 5 doc de outro cliente
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt8, 'relacao', 'parente'),             -- 6 linha solta
    jsonb_build_object('client_id', v_d, 'bank_transaction_id', bt1, 'relacao', 'parente'),             -- 7 cliente inativo
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt1, 'relacao', 'vizinho'),             -- 8 relação inválida
    jsonb_build_object('bank_transaction_id', bt1, 'relacao', 'parente'),                               -- 9 sem cliente
    jsonb_build_object('client_id', v_b, 'bank_transaction_id', bt9, 'relacao', 'marina')               -- 10 na fila: aceito
  ));
  perform pg_temp._sair();
  v_ok := jsonb_array_length(v_res -> 'recusados') = 9 and jsonb_array_length(v_res -> 'gravados') = 1;
  for v_row in
    select (x ->> 'indice')::int as i, x ->> 'motivo' as motivo from jsonb_array_elements(v_res -> 'recusados') x
  loop
    v_ok := v_ok and case v_row.i
      when 1 then v_row.motivo like 'Só uma entrada%'
      when 2 then v_row.motivo like 'O banco não informou o CPF/CNPJ%'
      when 3 then v_row.motivo like 'Quem pagou é o próprio cliente%'
      when 4 then v_row.motivo like 'É o CNPJ da própria HBR%'
      when 5 then v_row.motivo like 'Este CPF/CNPJ é do cliente Cliente Teste Pagadores E%possível cadastro duplicado%'
      when 6 then v_row.motivo like 'Esta entrada não paga uma conta%'
      when 7 then v_row.motivo like '%está inativo%'
      when 8 then v_row.motivo like 'Diga quem é o pagador%'
      when 9 then v_row.motivo like 'Falta o cliente%'
      else false end;
  end loop;
  insert into _resultado values ('T7 cada recusa com o motivo', v_ok, (v_res -> 'recusados')::text);
  select * into v_row from public.pagadores_do_cliente where client_id = v_b and documento = c_p4;
  insert into _resultado values ('T7 linha esperando na fila é aceita (origem fila)',
    v_row.situacao = 'confirmado' and v_row.origem = 'fila' and v_row.relacao = 'marina',
    (v_res -> 'gravados')::text);

  -- ── T8 lote vazio e lote grande ──
  perform pg_temp._como(v_admin);
  begin
    perform public.guardar_pagadores_do_cliente('[]'::jsonb);
    v_msg := null;
  exception when others then v_msg := sqlerrm;
  end;
  begin
    perform public.guardar_pagadores_do_cliente((select jsonb_agg(jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt1, 'relacao', 'conjuge'))
                                                   from generate_series(1, 51)));
    v_estado := null;
  exception when others then v_estado := sqlerrm;
  end;
  perform pg_temp._sair();
  insert into _resultado values ('T8 lote vazio e mais de 50 recusados',
    v_msg like 'Escolha ao menos um pagador%' and v_estado like 'No máximo 50 pagadores%', coalesce(v_msg, '-') || ' | ' || coalesce(v_estado, '-'));

  -- ── T9 o que o dono decidiu só o dono desfaz ──
  select id into v_id from public.pagadores_do_cliente where client_id = v_a and documento = c_p1;
  -- a) o financeiro não muda o confirmado: nem pelo guardar, nem recusando, nem pausando
  perform pg_temp._como(v_fin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt1, 'relacao', 'parente')));
  begin
    perform public.decidir_pagador_do_cliente(v_id, 'recusar', 'não é mais');
    v_msg := null;
  exception when insufficient_privilege then v_msg := sqlerrm;
  end;
  begin
    perform public.decidir_pagador_do_cliente(v_id, 'pausar');
    v_estado := null;
  exception when insufficient_privilege then v_estado := sqlerrm;
  end;
  perform pg_temp._sair();
  select * into v_row from public.pagadores_do_cliente where id = v_id;
  insert into _resultado values ('T9 financeiro não recusa nem pausa o confirmado (só o admin desfaz o SIM)',
    v_res -> 'recusados' -> 0 ->> 'motivo' like '%já é pagador confirmado%'
    and v_msg like '%é pagador confirmado de Cliente Teste Pagadores A: só o administrador recusa ou pausa%'
    and v_estado like '%só o administrador recusa ou pausa%'
    and v_row.situacao = 'confirmado' and v_row.relacao = 'conjuge',
    coalesce(v_msg, 'recusou') || ' | ' || coalesce(v_estado, 'pausou'));
  -- b) o administrador recusa; o financeiro não reativa nem traz de volta pelo guardar
  perform pg_temp._como(v_admin);
  v_res2 := public.decidir_pagador_do_cliente(v_id, 'recusar', 'não é mais');
  perform pg_temp._sair();
  perform pg_temp._como(v_fin);
  begin
    perform public.decidir_pagador_do_cliente(v_id, 'reativar');
    v_msg := null;
  exception when insufficient_privilege then v_msg := sqlerrm;
  end;
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt1, 'relacao', 'conjuge')));
  perform pg_temp._sair();
  select * into v_row from public.pagadores_do_cliente where id = v_id;
  insert into _resultado values ('T9 admin recusa; financeiro não reativa',
    v_res2 ->> 'situacao' = 'recusado' and v_res2 ->> 'message' like '%não volta a ser sugerido%'
    and v_row.situacao = 'recusado' and v_row.relacao = 'conjuge'
    and v_row.decidido_motivo = 'não é mais' and v_msg is not null,
    v_res2::text || ' | ' || coalesce(v_msg, 'reativou'));
  insert into _resultado values ('T9 recusado só volta pelo admin',
    v_res -> 'recusados' -> 0 ->> 'motivo' like '%só o administrador traz de volta%', v_res::text);
  -- c) o admin reativa e pausa; com o pausado, o financeiro não recusa (nem pelo decidir, nem pelo recusar_pagadores)
  perform pg_temp._como(v_admin);
  v_res := public.decidir_pagador_do_cliente(v_id, 'reativar');
  v_res2 := public.decidir_pagador_do_cliente(v_id, 'pausar', 'em dúvida');
  perform pg_temp._sair();
  select situacao into v_estado from public.pagadores_do_cliente where id = v_id;
  insert into _resultado values ('T9 admin reativa; pausar tira de sugestão',
    v_res ->> 'situacao' = 'confirmado' and v_res2 ->> 'situacao' = 'pausado' and v_estado = 'pausado'
    and v_res2 ->> 'message' like '%deixa de ser sugerido até o administrador reativar%', v_res2 ->> 'message');
  perform pg_temp._como(v_fin);
  begin
    perform public.decidir_pagador_do_cliente(v_id, 'recusar');
    v_msg := null;
  exception when insufficient_privilege then v_msg := sqlerrm;
  end;
  v_res := public.recusar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt1)));
  perform pg_temp._sair();
  select situacao into v_estado from public.pagadores_do_cliente where id = v_id;
  insert into _resultado values ('T9 financeiro não mexe no pausado (decidir e recusar_pagadores)',
    v_msg like '%está pausado como pagador de Cliente Teste Pagadores A: só o administrador muda%'
    and v_res -> 'recusados' -> 0 ->> 'motivo' like '%está pausado como pagador de%só o administrador muda%'
    and jsonb_array_length(v_res -> 'gravados') = 0 and v_estado = 'pausado',
    coalesce(v_msg, 'recusou') || ' | ' || v_res::text);
  perform pg_temp._como(v_admin);
  perform public.decidir_pagador_do_cliente(v_id, 'reativar');
  perform pg_temp._sair();

  -- ── T10 lista para conferir (como o financeiro: security invoker) ──
  -- O resultado lido como o usuário vai para uma variável; a conferência roda de volta como dono da sessão.
  perform pg_temp._como(v_fin);
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_lista
    from public.pagadores_para_conferir() x where x.client_id in (v_a, v_b, v_c, v_d, v_e);
  perform pg_temp._sair();
  select count(*) into v_n from jsonb_array_elements(v_lista);
  select count(*) into v_m from jsonb_array_elements(v_lista) l
   where l ->> 'client_id' = v_b::text and l ->> 'pagador_documento' = c_p5 and l ->> 'grupo' = 'cliente_sem_documento'
     and l ->> 'aviso' = 'pagou_para_varios_clientes' and (l ->> 'vezes')::int = 1
     and l -> 'bank_transaction_ids' = jsonb_build_array(bt10);
  select count(*) into v_k from jsonb_array_elements(v_lista) l
   where l ->> 'client_id' = v_c::text and l ->> 'pagador_documento' = c_p5 and l ->> 'grupo' = 'documento_diferente'
     and l ->> 'aviso' = 'pagou_para_varios_clientes' and l ->> 'tipo_documento' = 'CNPJ';
  insert into _resultado values ('T10 lista: pagou para vários clientes, por grupo', v_m = 1 and v_k = 1,
    (select coalesce(jsonb_agg(l - 'pagador_documento'), '[]'::jsonb) from jsonb_array_elements(v_lista) l)::text);
  select count(*) into v_m from jsonb_array_elements(v_lista) l
   where l ->> 'client_id' = v_a::text and l ->> 'pagador_documento' = c_cpf_e and l ->> 'aviso' = 'documento_de_outro_cliente';
  insert into _resultado values ('T10 lista: documento de outro cliente vem marcado', v_m = 1, null);
  -- de fora: os já guardados (confirmado e o que foi recusado/reativado), o próprio cliente, a HBR, o cliente inativo
  select count(*) into v_m from jsonb_array_elements(v_lista) l
   where (l ->> 'client_id' = v_a::text and l ->> 'pagador_documento' in (c_p1, c_p2, c_cpf_a, v_hbr))
      or l ->> 'client_id' = v_d::text;
  insert into _resultado values ('T10 lista: guardados, próprio cliente e HBR ficam de fora', v_m = 0 and v_n = 3, v_n || ' linha(s)');
  -- recusado não volta
  perform pg_temp._como(v_fin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_c, 'bank_transaction_id', bt11, 'relacao', 'outro')));
  perform public.decidir_pagador_do_cliente((v_res -> 'gravados' -> 0 ->> 'id')::uuid, 'recusar', 'não é pagador habitual');
  select count(*) into v_m from public.pagadores_para_conferir() x where x.client_id = v_c;
  perform pg_temp._sair();
  insert into _resultado values ('T10 recusado não volta na lista', v_m = 0 and v_res -> 'gravados' -> 0 ->> 'situacao' = 'proposto', v_res::text);

  -- ── T2 (depois) técnico e vendedor não leem nada ──
  foreach v_id in array array[v_tec, v_vend] loop
    perform pg_temp._como(v_id);
    select count(*) into v_n from public.pagadores_do_cliente;
    select count(*) into v_m from public.pagadores_para_conferir();
    select count(*) into v_k from public.pagamentos_com_pagador where pagador_documento is not null or relacao is not null;
    perform pg_temp._sair();
    insert into _resultado values ('T2 técnico/vendedor não leem pagadores nem quem pagou', v_n = 0 and v_m = 0 and v_k = 0,
      format('tabela %s, lista %s, view %s', v_n, v_m, v_k));
  end loop;
  -- e o admin lê (o zero acima não é tabela vazia)
  perform pg_temp._como(v_admin);
  select count(*) into v_n from public.pagadores_do_cliente where client_id in (v_a, v_b, v_c);
  perform pg_temp._sair();
  insert into _resultado values ('T2 admin lê os pagadores', v_n = 4, v_n || ' linha(s)');

  -- ── T11 cada situação da view (como o financeiro) ──
  perform pg_temp._como(v_fin);
  select coalesce(jsonb_object_agg(v.payment_id, to_jsonb(v)), '{}'::jsonb) into v_view
    from public.pagamentos_com_pagador v where v.client_id in (v_a, v_b, v_c);
  perform pg_temp._sair();
  insert into _resultado values ('T11 view: terceiro confirmado pela conta (ligação 1)',
    v_view -> p_a1::text ->> 'situacao' = 'terceiro' and v_view -> p_a1::text ->> 'relacao' = 'conjuge'
    and v_view -> p_a1::text ->> 'bank_transaction_id' = bt1::text and v_view -> p_a1::text ->> 'pagador_documento' = c_p1
    and v_view -> p_a1::text ->> 'pagador_nome' = 'CONJUGE DO A TESTE', (v_view -> p_a1::text)::text);
  insert into _resultado values ('T11 view: terceiro confirmado pelo pagamento (ligação 2)',
    v_view -> p_a2::text ->> 'situacao' = 'terceiro' and v_view -> p_a2::text ->> 'relacao' = 'empresa_do_cliente'
    and v_view -> p_a2::text ->> 'bank_transaction_id' = bt2::text, (v_view -> p_a2::text)::text);
  insert into _resultado values ('T11 view: o próprio cliente',
    v_view -> p_a3::text ->> 'situacao' = 'cliente' and v_view -> p_a3::text ->> 'relacao' is null, (v_view -> p_a3::text)::text);
  insert into _resultado values ('T11 view: cliente sem documento = indefinido (ligação 3)',
    v_view -> p_b1::text ->> 'situacao' = 'indefinido' and v_view -> p_b1::text ->> 'bank_transaction_id' = bt10::text
    and v_view -> p_b1::text ->> 'relacao' is null, (v_view -> p_b1::text)::text);
  insert into _resultado values ('T11 view: documentos diferentes sem pagador guardado = terceiro',
    v_view -> p_c1::text ->> 'situacao' = 'terceiro' and v_view -> p_c1::text ->> 'relacao' is null, (v_view -> p_c1::text)::text);
  insert into _resultado values ('T11 view: sem linha do banco = sem_dado',
    v_view -> p_a6::text ->> 'situacao' = 'sem_dado' and v_view -> p_a6::text ->> 'bank_transaction_id' is null, (v_view -> p_a6::text)::text);
  insert into _resultado values ('T11 view: o dinheiro não herda o pagador do Pix da mesma conta',
    v_view -> p_a5pix::text ->> 'bank_transaction_id' = bt12::text and v_view -> p_a5pix::text ->> 'situacao' = 'terceiro'
    and v_view -> p_a5cash::text ->> 'bank_transaction_id' is null and v_view -> p_a5cash::text ->> 'situacao' = 'sem_dado',
    (v_view -> p_a5cash::text)::text);
  -- pausado deixa de aparecer como relação (a view só usa o confirmado)
  perform pg_temp._como(v_admin);
  perform public.decidir_pagador_do_cliente((select id from public.pagadores_do_cliente where client_id = v_a and documento = c_p1), 'pausar');
  select count(*) into v_n from public.pagamentos_com_pagador where payment_id = p_a1 and situacao = 'terceiro' and relacao is null;
  perform pg_temp._sair();
  insert into _resultado values ('T11 view: pagador pausado não dá relação', v_n = 1, null);

  -- Daqui em diante, clientes novos (F e G): as contagens de T2/T10 acima não mudam.
  insert into public.clients (type, name, cpf_cnpj) values ('individual', 'Cliente Teste Pagadores F', c_cpf_f) returning id into v_f;
  insert into public.clients (type, name, cpf_cnpj) values ('individual', 'Cliente Teste Pagadores G', c_cpf_g) returning id into v_g;

  -- ── T12 o proposto continua na lista até o SIM do administrador ──
  btp := pg_temp._linha(c_p10, 'PROPOSTO TESTE');
  r_f2 := pg_temp._conta(v_f, btp);
  perform pg_temp._como(v_fin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_f, 'bank_transaction_id', btp, 'relacao', 'parente')));
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_lista
    from public.pagadores_para_conferir() x where x.client_id = v_f and x.pagador_documento = c_p10;
  perform pg_temp._sair();
  insert into _resultado values ('T12 proposto pelo financeiro continua na lista, com quem e quando',
    v_res -> 'gravados' -> 0 ->> 'situacao' = 'proposto' and v_res -> 'avisos' = '[]'::jsonb
    and jsonb_array_length(v_lista) = 1
    and v_lista -> 0 ->> 'situacao' = 'proposto'
    and v_lista -> 0 ->> 'pagador_id' = v_res -> 'gravados' -> 0 ->> 'id'
    and v_lista -> 0 ->> 'relacao_proposta' = 'parente'
    and v_lista -> 0 ->> 'proposto_por_nome' = 'Teste pagadores (financial)'
    and v_lista -> 0 ->> 'proposto_em' is not null
    and v_lista -> 0 ->> 'aviso' is null,
    (select coalesce(jsonb_agg(l - 'pagador_documento'), '[]'::jsonb) from jsonb_array_elements(v_lista) l)::text);
  perform pg_temp._como(v_admin);
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_lista2
    from public.pagadores_para_conferir() x where x.client_id = v_f and x.pagador_documento = c_p10;
  v_res2 := public.decidir_pagador_do_cliente((v_res -> 'gravados' -> 0 ->> 'id')::uuid, 'confirmar');
  select count(*) into v_m from public.pagadores_para_conferir() x where x.client_id = v_f and x.pagador_documento = c_p10;
  perform pg_temp._sair();
  insert into _resultado values ('T12 o administrador vê o proposto (com o nome) e, confirmado, ele sai da lista',
    jsonb_array_length(v_lista2) = 1 and v_lista2 -> 0 ->> 'proposto_por_nome' = 'Teste pagadores (financial)'
    and v_res2 ->> 'situacao' = 'confirmado' and v_m = 0,
    coalesce(v_res2 ->> 'message', '-') || ' | ' || v_m || ' na lista');

  -- ── T13 ligação duvidosa (o caso MUNDO DOCE COLOMBO) ──
  -- O pagamento p_f1 é de outra linha (bty); a btd ficou apontando para ele pela conciliação, e só por ela.
  r_f1 := pg_temp._conta(v_f);
  p_f1 := pg_temp._pagamento(r_f1, null, 4500);
  btd := pg_temp._linha(c_p6, 'COLOMBO TESTE', 'credit', 3000);
  bty := pg_temp._linha(c_cpf_f, 'CLIENTE TESTE PAGADORES F', 'credit', 4500);
  update public.bank_transactions set reconciled_payment_id = p_f1, reconciled = true where id = btd;
  update public.bank_transactions set reconciled_payment_id = p_f1, reconciled = true where id = bty;
  perform pg_temp._como(v_fin);
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_lista
    from public.pagadores_para_conferir() x where x.client_id = v_f;
  perform pg_temp._sair();
  select count(*) into v_m from jsonb_array_elements(v_lista) l
   where l ->> 'pagador_documento' = c_p6 and l ->> 'aviso' = 'ligacao_duvidosa' and (l ->> 'vezes')::int = 1
     and l -> 'bank_transaction_ids' = jsonb_build_array(btd)
     and l ->> 'situacao' is null and l ->> 'pagador_id' is null and l ->> 'relacao_proposta' is null;
  select count(*) into v_k from jsonb_array_elements(v_lista) l where l ->> 'pagador_documento' = c_cpf_f;
  insert into _resultado values ('T13 lista: a única ligação é a conciliação de um pagamento com outra linha = ligacao_duvidosa',
    v_m = 1 and v_k = 0,
    (select coalesce(jsonb_agg(l - 'pagador_documento'), '[]'::jsonb) from jsonb_array_elements(v_lista) l)::text);

  -- ── T14 recusar_pagadores_do_cliente ──
  -- a) o financeiro recusa o par duvidoso, que ainda não está na tabela
  perform pg_temp._como(v_fin);
  v_res := public.recusar_pagadores_do_cliente(
    jsonb_build_array(jsonb_build_object('client_id', v_f, 'bank_transaction_id', btd, 'documento', '00000000000')), 'ligação errada');
  select count(*) into v_m from public.pagadores_para_conferir() x where x.client_id = v_f and x.pagador_documento = c_p6;
  perform pg_temp._sair();
  select * into v_row from public.pagadores_do_cliente where client_id = v_f and documento = c_p6;
  insert into _resultado values ('T14 financeiro recusa um par novo (da linha do banco) e ele não volta na lista',
    v_res -> 'gravados' -> 0 ->> 'situacao' = 'recusado' and (v_res -> 'gravados' -> 0 ->> 'ja_existia')::boolean = false
    and v_res -> 'regras_consolidadas' = '[]'::jsonb and v_res ->> 'message' like '1 pagador recusado%'
    and v_row.situacao = 'recusado' and v_row.relacao = 'outro' and v_row.decidido_motivo = 'ligação errada'
    and v_row.nome = 'COLOMBO TESTE' and v_row.proposto_por = v_fin and v_row.confirmado_em is null
    and v_row.bank_transaction_id = btd and v_m = 0
    and not exists (select 1 from public.pagadores_do_cliente where documento = '00000000000')
    and exists (select 1 from public.reconciliation_log l where l.acao = 'recusou_pagador_do_cliente' and l.autor = v_fin
                 and l.bank_transaction_id = btd and l.depois ->> 'pagador_id' = v_row.id::text),
    v_res::text);
  -- b) pedir de novo não muda nada (nem a trilha)
  perform pg_temp._como(v_fin);
  v_res := public.recusar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_f, 'bank_transaction_id', btd)), 'outro motivo');
  perform pg_temp._sair();
  select count(*) into v_n from public.reconciliation_log l where l.acao = 'recusou_pagador_do_cliente' and l.bank_transaction_id = btd;
  insert into _resultado values ('T14 recusar de novo não muda nada',
    v_res -> 'gravados' -> 0 ->> 'situacao' = 'recusado' and (v_res -> 'gravados' -> 0 ->> 'ja_existia')::boolean
    and v_n = 1 and (select decidido_motivo from public.pagadores_do_cliente where id = v_row.id) = 'ligação errada',
    v_res::text);
  -- c) o documento de OUTRO cliente (que o guardar recusa) sai da lista pela recusa
  perform pg_temp._como(v_fin);
  v_res := public.recusar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt7)));
  select count(*) into v_m from public.pagadores_para_conferir() x where x.client_id = v_a and x.pagador_documento = c_cpf_e;
  perform pg_temp._sair();
  insert into _resultado values ('T14 o par com documento de outro cliente é recusado e sai da lista',
    v_res -> 'gravados' -> 0 ->> 'situacao' = 'recusado' and v_m = 0
    and (select decidido_motivo from public.pagadores_do_cliente where client_id = v_a and documento = c_cpf_e) = 'Não é pagador habitual',
    v_res::text);
  -- d) o financeiro não desfaz o que o administrador confirmou; o administrador recusa
  perform pg_temp._como(v_fin);
  v_res := public.recusar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_f, 'bank_transaction_id', btp)));
  perform pg_temp._sair();
  select situacao into v_estado from public.pagadores_do_cliente where client_id = v_f and documento = c_p10;
  insert into _resultado values ('T14 financeiro não recusa um confirmado',
    v_res -> 'recusados' -> 0 ->> 'motivo' like '%só o administrador recusa%' and jsonb_array_length(v_res -> 'gravados') = 0
    and v_estado = 'confirmado', v_res::text);
  perform pg_temp._como(v_admin);
  v_res := public.recusar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_f, 'bank_transaction_id', btp)), 'mudou');
  perform pg_temp._sair();
  select * into v_row from public.pagadores_do_cliente where client_id = v_f and documento = c_p10;
  insert into _resultado values ('T14 o administrador recusa o confirmado',
    v_res -> 'gravados' -> 0 ->> 'situacao' = 'recusado' and (v_res -> 'gravados' -> 0 ->> 'ja_existia')::boolean
    and v_res -> 'gravados' -> 0 ->> 'situacao_anterior' = 'confirmado'
    and v_row.situacao = 'recusado' and v_row.decidido_motivo = 'mudou' and v_row.relacao = 'parente',
    v_res::text);
  -- e) cada recusa de validação, no mesmo lote
  perform pg_temp._como(v_admin);
  v_res := public.recusar_pagadores_do_cliente(jsonb_build_array(
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt5),                 -- 1 saída
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt6),                 -- 2 sem documento
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt3),                 -- 3 próprio cliente
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt4),                 -- 4 CNPJ da HBR
    jsonb_build_object('client_id', v_a, 'bank_transaction_id', bt8),                 -- 5 linha solta
    jsonb_build_object('bank_transaction_id', bt1),                                   -- 6 sem cliente
    jsonb_build_object('client_id', gen_random_uuid(), 'bank_transaction_id', bt1)    -- 7 cliente que não existe
  ));
  perform pg_temp._sair();
  v_ok := jsonb_array_length(v_res -> 'recusados') = 7 and jsonb_array_length(v_res -> 'gravados') = 0
          and (v_res ->> 'ok')::boolean = false and v_res ->> 'message' like 'Nenhum pagador recusado.%';
  for v_row in
    select (x ->> 'indice')::int as i, x ->> 'motivo' as motivo from jsonb_array_elements(v_res -> 'recusados') x
  loop
    v_ok := v_ok and case v_row.i
      when 1 then v_row.motivo like 'Só uma entrada%'
      when 2 then v_row.motivo like 'O banco não informou o CPF/CNPJ%'
      when 3 then v_row.motivo like 'Quem pagou é o próprio cliente%'
      when 4 then v_row.motivo like 'É o CNPJ da própria HBR%'
      when 5 then v_row.motivo like 'Esta entrada não paga uma conta%'
      when 6 then v_row.motivo like 'Falta o cliente%'
      when 7 then v_row.motivo = 'Cliente não encontrado.'
      else false end;
  end loop;
  insert into _resultado values ('T14 cada recusa de validação com o motivo', v_ok, (v_res -> 'recusados')::text);
  -- f) técnico e vendedor não recusam; lote vazio e lote com mais de 50
  foreach v_id in array array[v_tec, v_vend] loop
    perform pg_temp._como(v_id);
    begin
      v_res := public.recusar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_f, 'bank_transaction_id', btd)));
      v_msg := null;
    exception when insufficient_privilege then
      v_msg := sqlerrm;
    end;
    perform pg_temp._sair();
    insert into _resultado values ('T14 técnico/vendedor não recusam', v_msg is not null, coalesce(v_msg, 'recusou sem erro'));
  end loop;
  perform pg_temp._como(v_admin);
  begin
    perform public.recusar_pagadores_do_cliente('[]'::jsonb);
    v_msg := null;
  exception when others then v_msg := sqlerrm;
  end;
  begin
    perform public.recusar_pagadores_do_cliente((select jsonb_agg(jsonb_build_object('client_id', v_f, 'bank_transaction_id', btd))
                                                   from generate_series(1, 51)));
    v_estado := null;
  exception when others then v_estado := sqlerrm;
  end;
  perform pg_temp._sair();
  insert into _resultado values ('T14 lote vazio e mais de 50 recusados',
    v_msg like 'Escolha ao menos um pagador para recusar%' and v_estado like 'No máximo 50 pagadores%',
    coalesce(v_msg, '-') || ' | ' || coalesce(v_estado, '-'));

  -- ── T15 regra antiga do mesmo documento apontando OUTRO cliente ──
  btr := pg_temp._linha(c_p8, 'EMPRESA EM CONFLITO TESTE LTDA');
  r_f3 := pg_temp._conta(v_f, btr);
  insert into public.finance_rules (match_type, match_value, direction, set_category, set_dre_group, set_client_id, autonomy, origin, status)
  values ('document', c_p8, 'credit', 'Serviços prestados', 'receita', v_g, 'suggest', 'user', 'active')
  returning id into v_regra2;
  perform pg_temp._como(v_admin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_f, 'bank_transaction_id', btr, 'relacao', 'empresa_do_cliente')));
  perform pg_temp._sair();
  insert into _resultado values ('T15 guardar avisa da regra antiga de outro cliente (e não mexe nela)',
    v_res -> 'gravados' -> 0 ->> 'situacao' = 'confirmado'
    and v_res -> 'gravados' -> 0 -> 'regra_de_outro_cliente' ->> 'client_id' = v_g::text
    and v_res -> 'gravados' -> 0 -> 'regra_de_outro_cliente' ->> 'finance_rule_id' = v_regra2::text
    and jsonb_array_length(v_res -> 'avisos') = 1
    and v_res -> 'avisos' ->> 0 like 'Atenção: uma regra antiga diz que este CPF/CNPJ é do cliente Cliente Teste Pagadores G;%passam a perguntar de quem é%'
    and v_res ->> 'message' like '%regra antiga diz que este CPF/CNPJ é do cliente Cliente Teste Pagadores G%'
    and v_res -> 'regras_consolidadas' = '[]'::jsonb
    and exists (select 1 from public.finance_rules where id = v_regra2 and set_client_id = v_g and status = 'active')
    and exists (select 1 from public.reconciliation_log l where l.acao = 'guardou_pagador_do_cliente' and l.bank_transaction_id = btr
                 and l.depois -> 'regra_em_conflito' ->> 'client_id' = v_g::text and l.finance_rule_id = v_regra2),
    v_res::text);
  -- decidir: o financeiro propõe (o aviso fala do SIM que falta) e o administrador confirma (o aviso vem na mensagem)
  btq := pg_temp._linha(c_p9, 'OUTRA EM CONFLITO TESTE');
  r_f4 := pg_temp._conta(v_f, btq);
  insert into public.finance_rules (match_type, match_value, direction, set_category, set_dre_group, set_client_id, autonomy, origin, status)
  values ('document', c_p9, 'credit', 'Serviços prestados', 'receita', v_g, 'suggest', 'user', 'active')
  returning id into v_regra3;
  perform pg_temp._como(v_fin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_f, 'bank_transaction_id', btq, 'relacao', 'outro')));
  perform pg_temp._sair();
  perform pg_temp._como(v_admin);
  v_res2 := public.decidir_pagador_do_cliente((v_res -> 'gravados' -> 0 ->> 'id')::uuid, 'confirmar');
  perform pg_temp._sair();
  insert into _resultado values ('T15 decidir (confirmar) também avisa da regra antiga de outro cliente',
    v_res -> 'gravados' -> 0 ->> 'situacao' = 'proposto'
    and v_res -> 'avisos' ->> 0 like '%quando o administrador confirmar%'
    and v_res2 ->> 'situacao' = 'confirmado'
    and v_res2 -> 'regra_de_outro_cliente' ->> 'finance_rule_id' = v_regra3::text
    and v_res2 ->> 'message' like '%regra antiga diz que este CPF/CNPJ é do cliente Cliente Teste Pagadores G%'
    and exists (select 1 from public.finance_rules where id = v_regra3 and set_client_id = v_g),
    coalesce(v_res2 ->> 'message', '-'));

  -- ── T16 a regra de entrada do MESMO cliente perde o cliente quando o proposto vira confirmado ──
  insert into public.clients (type, name, cpf_cnpj) values ('individual', 'Cliente Teste Pagadores H', c_cpf_h) returning id into v_h;
  -- a) pelo decidir('confirmar') — o fluxo real da EQUIT: o financeiro propõe, o administrador confirma
  btc1 := pg_temp._linha(c_p17, 'EMPRESA DO H TESTE LTDA');
  perform pg_temp._conta(v_h, btc1);
  insert into public.finance_rules (match_type, match_value, direction, set_category, set_dre_group, set_client_id, autonomy, origin, status)
  values ('document', c_p17, 'credit', 'Serviços prestados', 'receita', v_h, 'suggest', 'user', 'active')
  returning id into v_regra4;
  perform pg_temp._como(v_fin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_h, 'bank_transaction_id', btc1, 'relacao', 'outro')));
  perform pg_temp._sair();
  v_p := (v_res -> 'gravados' -> 0 ->> 'id')::uuid;
  -- o proposto não mexe na regra
  select count(*) into v_n from public.finance_rules where id = v_regra4 and set_client_id = v_h;
  -- relação inválida e relação fora do 'confirmar': recusadas, e nada muda
  perform pg_temp._como(v_admin);
  begin
    perform public.decidir_pagador_do_cliente(p_id => v_p, p_decisao => 'confirmar', p_relacao => 'vizinho');
    v_msg := null;
  exception when others then v_msg := sqlerrm;
  end;
  begin
    perform public.decidir_pagador_do_cliente(p_id => v_p, p_decisao => 'pausar', p_relacao => 'conjuge');
    v_estado := null;
  exception when others then v_estado := sqlerrm;
  end;
  perform pg_temp._sair();
  select * into v_row from public.pagadores_do_cliente where id = v_p;
  insert into _resultado values ('T16 proposto não consolida; relação inválida ou fora do confirmar é recusada',
    v_res -> 'gravados' -> 0 ->> 'situacao' = 'proposto' and v_res -> 'regras_consolidadas' = '[]'::jsonb and v_n = 1
    and v_msg like 'Relação desconhecida%' and v_estado like 'A relação só muda ao confirmar%'
    and v_row.situacao = 'proposto' and v_row.relacao = 'outro',
    coalesce(v_msg, 'aceitou a relação inválida') || ' | ' || coalesce(v_estado, 'aceitou relação no pausar'));
  perform pg_temp._como(v_admin);
  v_res2 := public.decidir_pagador_do_cliente(p_id => v_p, p_decisao => 'confirmar', p_relacao => 'empresa_do_cliente');
  perform pg_temp._sair();
  select * into v_row from public.pagadores_do_cliente where id = v_p;
  insert into _resultado values ('T16 decidir(confirmar) consolida a regra do mesmo cliente e troca a relação',
    v_row.situacao = 'confirmado' and v_row.relacao = 'empresa_do_cliente' and v_row.confirmado_por = v_admin
    and v_res2 ->> 'situacao' = 'confirmado' and v_res2 ->> 'relacao' = 'empresa_do_cliente'
    and v_res2 ->> 'message' like '%(relação trocada para empresa do cliente)%'
    and v_res2 ->> 'message' like '%A regra de entrada deste documento deixou de apontar o cliente%'
    and v_res2 -> 'regras_consolidadas' ? v_regra4::text
    and exists (select 1 from public.finance_rules where id = v_regra4 and set_client_id is null
                 and set_category = 'Serviços prestados' and status = 'active')
    and exists (select 1 from public.reconciliation_log l where l.acao = 'decidiu_pagador_do_cliente' and l.autor = v_admin
                 and l.finance_rule_id = v_regra4 and l.antes ->> 'relacao' = 'outro'
                 and l.depois ->> 'relacao' = 'empresa_do_cliente' and l.depois -> 'regras_consolidadas' ? v_regra4::text),
    v_res2::text);
  -- b) pelo guardar do administrador sobre o par que o financeiro já tinha proposto
  btc2 := pg_temp._linha(c_p18, 'PARENTE DO H TESTE');
  perform pg_temp._conta(v_h, btc2);
  insert into public.finance_rules (match_type, match_value, direction, set_category, set_dre_group, set_client_id, autonomy, origin, status)
  values ('document', c_p18, 'credit', 'Serviços prestados', 'receita', v_h, 'suggest', 'user', 'active')
  returning id into v_regra5;
  perform pg_temp._como(v_fin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_h, 'bank_transaction_id', btc2, 'relacao', 'parente')));
  perform pg_temp._sair();
  perform pg_temp._como(v_admin);
  v_res2 := public.guardar_pagadores_do_cliente(jsonb_build_array(jsonb_build_object('client_id', v_h, 'bank_transaction_id', btc2, 'relacao', 'parente')));
  perform pg_temp._sair();
  select * into v_row from public.pagadores_do_cliente where client_id = v_h and documento = c_p18;
  insert into _resultado values ('T16 guardar do admin sobre o proposto que já existe confirma e consolida a regra',
    v_res -> 'gravados' -> 0 ->> 'situacao' = 'proposto' and v_res -> 'regras_consolidadas' = '[]'::jsonb
    and v_res2 -> 'gravados' -> 0 ->> 'situacao' = 'confirmado'
    and (v_res2 -> 'gravados' -> 0 ->> 'ja_existia')::boolean
    and v_res2 -> 'gravados' -> 0 ->> 'situacao_anterior' = 'proposto'
    and v_res2 -> 'regras_consolidadas' ? v_regra5::text
    and v_res2 -> 'gravados' -> 0 -> 'regras_consolidadas' ? v_regra5::text
    and v_row.situacao = 'confirmado' and v_row.confirmado_por = v_admin
    and exists (select 1 from public.finance_rules where id = v_regra5 and set_client_id is null and status = 'active'),
    v_res2::text);

  -- ── T17 o proposto que veio da fila (fora das 3 ligações) aparece na lista ──
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Pagadores M') returning id into v_m_cli;
  bts1 := pg_temp._linha(c_p11, 'SOLTO DA FILA TESTE', 'credit', 250);
  bts2 := pg_temp._linha(c_p12, 'SOLTO DO M TESTE', 'credit', 80);
  bts3 := pg_temp._linha(c_p13, 'SOLTO QUE VIRA A HBR TESTE LTDA', 'credit', 90);
  bts4 := pg_temp._linha(c_p14, 'PAGA PELO H E PELO F TESTE', 'credit', 70);
  bts5 := pg_temp._linha(c_p14, 'PAGA PELO H E PELO F TESTE', 'credit', 30);
  perform pg_temp._conta(v_f, bts5);  -- o mesmo documento é par do F pelas ligações
  insert into public.finance_review_queue (kind, status, bank_transaction_id, title, suggested_amount, suggested_date)
  select 'create_receivable', 'pending', x, 'Receita: solto teste', 100, current_date from unnest(array[bts1, bts2, bts3, bts4]) x;
  perform pg_temp._como(v_fin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(
    jsonb_build_object('client_id', v_h, 'bank_transaction_id', bts1, 'relacao', 'parente', 'origem', 'fila'),
    jsonb_build_object('client_id', v_m_cli, 'bank_transaction_id', bts2, 'relacao', 'conjuge', 'origem', 'fila'),
    jsonb_build_object('client_id', v_h, 'bank_transaction_id', bts3, 'relacao', 'empresa_do_cliente', 'origem', 'fila'),
    jsonb_build_object('client_id', v_h, 'bank_transaction_id', bts4, 'relacao', 'outro', 'origem', 'fila')));
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_lista
    from public.pagadores_para_conferir() x where x.client_id in (v_h, v_m_cli, v_f);
  perform pg_temp._sair();
  select count(*) into v_n from jsonb_array_elements(v_lista) l
   where l ->> 'client_id' = v_h::text and l ->> 'pagador_documento' = c_p11
     and l ->> 'situacao' = 'proposto' and l ->> 'pagador_id' = v_res -> 'gravados' -> 0 ->> 'id'
     and (l ->> 'vezes')::int = 1 and (l ->> 'total')::numeric = 250
     and l ->> 'primeira' = current_date::text and l ->> 'ultima' = current_date::text
     and l -> 'bank_transaction_ids' = jsonb_build_array(bts1)
     and l ->> 'grupo' = 'documento_diferente' and l ->> 'tipo_documento' = 'CPF' and l ->> 'aviso' is null
     and l ->> 'pagador_nome' = 'SOLTO DA FILA TESTE' and l ->> 'relacao_proposta' = 'parente'
     and l ->> 'proposto_por_nome' = 'Teste pagadores (financial)' and l ->> 'proposto_em' is not null;
  select count(*) into v_m from jsonb_array_elements(v_lista) l
   where l ->> 'client_id' = v_m_cli::text and l ->> 'pagador_documento' = c_p12
     and l ->> 'grupo' = 'cliente_sem_documento' and l ->> 'situacao' = 'proposto';
  select count(*) into v_k from jsonb_array_elements(v_lista) l
   where l ->> 'pagador_documento' = c_p14 and l ->> 'aviso' = 'pagou_para_varios_clientes'
     and ((l ->> 'client_id' = v_h::text and l ->> 'situacao' = 'proposto')
          or (l ->> 'client_id' = v_f::text and l ->> 'situacao' is null and (l ->> 'vezes')::int = 1));
  insert into _resultado values ('T17 lista: o proposto da fila aparece (vezes 1, a linha dele, grupo, quem e quando)',
    jsonb_array_length(v_res -> 'gravados') = 4 and v_n = 1 and v_m = 1
    and exists (select 1 from jsonb_array_elements(v_lista) l where l ->> 'client_id' = v_h::text and l ->> 'pagador_documento' = c_p13),
    (select coalesce(jsonb_agg(l - 'pagador_documento'), '[]'::jsonb) from jsonb_array_elements(v_lista) l)::text);
  insert into _resultado values ('T17 lista: o proposto da fila e o par de outro cliente = pagou para vários clientes', v_k = 2,
    (select coalesce(jsonb_agg(l - 'pagador_documento'), '[]'::jsonb) from jsonb_array_elements(v_lista) l
      where l ->> 'pagador_documento' = c_p14)::text);
  -- cliente inativo, documento do próprio cliente e CNPJ da HBR: o proposto solto sai da lista
  select value into v_estado from public.app_settings where key = 'cnpj';
  update public.clients set active = false where id = v_m_cli;
  perform pg_temp._como(v_fin);
  select count(*) into v_n from public.pagadores_para_conferir() x where x.client_id = v_m_cli;
  perform pg_temp._sair();
  update public.clients set active = true, cpf_cnpj = c_p12 where id = v_m_cli;
  perform pg_temp._como(v_fin);
  select count(*) into v_m from public.pagadores_para_conferir() x where x.client_id = v_m_cli;
  perform pg_temp._sair();
  update public.app_settings set value = c_p13 where key = 'cnpj';
  perform pg_temp._como(v_fin);
  select count(*) into v_k from public.pagadores_para_conferir() x where x.client_id = v_h and x.pagador_documento = c_p13;
  perform pg_temp._sair();
  update public.app_settings set value = v_estado where key = 'cnpj';
  insert into _resultado values ('T17 lista: proposto solto de cliente inativo, do próprio cliente ou da HBR fica de fora',
    v_n = 0 and v_m = 0 and v_k = 0, format('inativo %s, próprio %s, HBR %s', v_n, v_m, v_k));
  -- o SIM do administrador tira o proposto solto da lista
  perform pg_temp._como(v_admin);
  v_res2 := public.decidir_pagador_do_cliente((v_res -> 'gravados' -> 0 ->> 'id')::uuid, 'confirmar');
  select count(*) into v_n from public.pagadores_para_conferir() x where x.client_id = v_h and x.pagador_documento = c_p11;
  perform pg_temp._sair();
  insert into _resultado values ('T17 confirmado, o proposto da fila sai da lista',
    v_res2 ->> 'situacao' = 'confirmado' and v_n = 0, coalesce(v_res2 ->> 'message', '-') || ' | ' || v_n || ' na lista');

  -- ── T18 a trava "documento de outro cliente" no decidir (o cadastro mudou depois da proposta) ──
  bts6 := pg_temp._linha(c_p15, 'VIRA O CLIENTE J TESTE');
  bts7 := pg_temp._linha(c_p16, 'VIRA O CLIENTE K TESTE');
  insert into public.finance_review_queue (kind, status, bank_transaction_id, title, suggested_amount, suggested_date)
  select 'create_receivable', 'pending', x, 'Receita: trava teste', 100, current_date from unnest(array[bts6, bts7]) x;
  perform pg_temp._como(v_fin);
  v_res := public.guardar_pagadores_do_cliente(jsonb_build_array(
    jsonb_build_object('client_id', v_h, 'bank_transaction_id', bts6, 'relacao', 'parente'),
    jsonb_build_object('client_id', v_h, 'bank_transaction_id', bts7, 'relacao', 'parente')));
  v_p := (v_res -> 'gravados' -> 0 ->> 'id')::uuid;
  v_id := (v_res -> 'gravados' -> 1 ->> 'id')::uuid;
  -- o financeiro pausa o PROPOSTO (pode: ainda não é decisão do dono)
  v_res2 := public.decidir_pagador_do_cliente(v_id, 'pausar', 'em dúvida');
  perform pg_temp._sair();
  insert into public.clients (type, name, cpf_cnpj) values ('individual', 'Cliente Teste Pagadores J', c_p15) returning id into v_j_cli;
  insert into public.clients (type, name, cpf_cnpj) values ('individual', 'Cliente Teste Pagadores K', c_p16) returning id into v_k_cli;
  perform pg_temp._como(v_fin);
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_lista
    from public.pagadores_para_conferir() x where x.client_id = v_h and x.pagador_documento = c_p15;
  perform pg_temp._sair();
  perform pg_temp._como(v_admin);
  begin
    perform public.decidir_pagador_do_cliente(v_p, 'confirmar');
    v_msg := null;
  exception when others then v_msg := sqlerrm;
  end;
  begin
    perform public.decidir_pagador_do_cliente(v_id, 'reativar');
    v_estado := null;
  exception when others then v_estado := sqlerrm;
  end;
  perform pg_temp._sair();
  insert into _resultado values ('T18 financeiro pausa o proposto; o proposto com documento de outro cliente vem com o aviso',
    jsonb_array_length(v_res -> 'gravados') = 2 and v_res2 ->> 'situacao' = 'pausado'
    and jsonb_array_length(v_lista) = 1 and v_lista -> 0 ->> 'aviso' = 'documento_de_outro_cliente'
    and v_lista -> 0 ->> 'situacao' = 'proposto',
    v_res::text || ' | ' || v_lista::text);
  insert into _resultado values ('T18 decidir não confirma nem reativa o documento que virou de outro cliente',
    v_msg like 'Este CPF/CNPJ é do cliente Cliente Teste Pagadores J: possível cadastro duplicado%'
    and v_estado like 'Este CPF/CNPJ é do cliente Cliente Teste Pagadores K: possível cadastro duplicado%'
    and (select situacao from public.pagadores_do_cliente where id = v_p) = 'proposto'
    and (select situacao from public.pagadores_do_cliente where id = v_id) = 'pausado',
    coalesce(v_msg, 'confirmou') || ' | ' || coalesce(v_estado, 'reativou'));
end $$;

-- T1 (fora do bloco: prova por privilégio, não por linha)
insert into _resultado
select 'T1 anon não lê nem executa; internas fechadas',
       not has_table_privilege('anon', 'public.pagadores_do_cliente', 'select')
       and not has_table_privilege('anon', 'public.pagamentos_com_pagador', 'select')
       and not has_function_privilege('anon', 'public.guardar_pagadores_do_cliente(jsonb, uuid)', 'execute')
       and not has_function_privilege('anon', 'public.decidir_pagador_do_cliente(uuid, text, text, uuid, text)', 'execute')
       and has_function_privilege('authenticated', 'public.decidir_pagador_do_cliente(uuid, text, text, uuid, text)', 'execute')
       -- a assinatura antiga (sem p_relacao) não sobra: com as duas, a chamada por nome ficaria ambígua
       and (select count(*) from pg_proc where proname = 'decidir_pagador_do_cliente'
              and pronamespace = 'public'::regnamespace) = 1
       and not has_function_privilege('anon', 'public.pagadores_para_conferir()', 'execute')
       and not has_function_privilege('anon', 'public.recusar_pagadores_do_cliente(jsonb, text, uuid)', 'execute')
       and has_function_privilege('authenticated', 'public.recusar_pagadores_do_cliente(jsonb, text, uuid)', 'execute')
       and not has_function_privilege('anon', 'public._pagador_consolidar_regras(uuid, text)', 'execute')
       and not has_function_privilege('authenticated', 'public._pagador_consolidar_regras(uuid, text)', 'execute')
       and not has_function_privilege('anon', 'public._pagador_regra_de_outro_cliente(uuid, text)', 'execute')
       and not has_function_privilege('authenticated', 'public._pagador_regra_de_outro_cliente(uuid, text)', 'execute')
       and not has_function_privilege('authenticated', 'public._raizes_do_cnpj_da_hbr()', 'execute')
       and not has_table_privilege('authenticated', 'public.pagadores_do_cliente', 'insert')
       and not has_table_privilege('authenticated', 'public.pagadores_do_cliente', 'update')
       and not has_table_privilege('authenticated', 'public.pagadores_do_cliente', 'delete'),
       null;

select teste, ok, detalhe from _resultado order by teste;

rollback;
