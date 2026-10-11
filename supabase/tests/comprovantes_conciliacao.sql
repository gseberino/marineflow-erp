-- Prova: conciliação dos comprovantes com o extrato (migrations 20261011300000-304000; usa a F1 e a F2).
--
--   T1  grants: R1-R10 só service_role; helpers para ninguém; tabelas novas fechadas ao anon
--   T2  débito único sem nome → verde → "sim" liga: proposta classificada (anotação criada e aplicada,
--       evidencia.anotacao), a loja do CMP na linha (nome_pelo_comprovante) e no extrato_da_conta
--   T3  dois débitos iguais → azul 1/2/0 → a escolha 2 liga a segunda
--   T4  "0" → as listadas vão para banco_recusados; a próxima avaliação fica cinza
--   T5  Pix com CNPJ: a linha do mesmo CNPJ é verde; a de outro CNPJ fica de fora
--   T6  Pix com CPF mascarado → azul (cpf_parcial); CPF com outros finais fica de fora
--   T7  crédito: à vista com nome igual em D+0 verde; nome diferente azul; parcela 1/3 azul com o total
--   T8  a linha já virou lançamento → anexa e corrige categoria
--   T9  CMP com conta a pagar em aberto → o "sim" casa (conciliar_lancamento) e a proposta sai da fila
--   T10 a anotação da F2 aplicada pelo aplicar_anotacoes_pendentes → R1 liga sem pergunta
--   T11 linha forte de dois CMPs → azul nos dois (disputada)
--   T12 abandono em 30 dias (45 no crédito) + pendência "classificar no Extrato"
--   T13 re-validação: valor mudou → desliga; proposta recusada → desliga e recusa a linha
--   T14 vigia: horário seg–sáb 08–20, espaçamento de 4 h, 3 tentativas, a fila da F2 primeiro; conversa
--       desligada → nada perguntado, candidatos guardados
--   T15 PESSOAL só registra (nada reservado, nunca pergunta, nunca liga)
--   T16 R2 = ligadas + candidatas com pergunta (nunca o PESSOAL) + as anotações dos CMPs
--   T17 as linhas mudaram desde a pergunta → "mudou" e a pergunta nova
--   T18 resposta mandada antes da pergunta → "invalida", nada muda
--   (correção da revisão de 11/10/2026)
--   T19 débito com a forte e outra linha do mesmo valor na janela → azul (a forte em 1); só a forte é reservada
--   T20 cupom pago no Pix da maquininha: a linha do intermediador fica (fraca, azul); o comprovante do Pix
--       guardado como "a mesma compra" dá o documento de quem recebeu → verde
--   T21 linha dispensada da fila nunca é candidata; a ligada que o dono dispensa depois é desligada
--   T22 crédito: a busca vai até D+5 (o cartão data a linha na compra); D+8 fica de fora
--   T23 R10: a pergunta do extrato aberta cede a vez ao comprovante novo (só ela)
--   T24 a varredura só grava o que mudou: 10 rodadas sem linha nova = nenhuma versão nova de linha; a da
--       manutenção do cron não calcula as reservadas
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado PF3-2 da spec da F3; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/comprovantes_conciliacao.sql --output json
--
-- Seguro em produção: tudo dentro da transação e ROLLBACK no fim. Dono de teste (admin com created_at
-- 30 anos atrás, que vira o _comprovante_dono() só dentro da transação), contas e linhas do extrato
-- de teste com valores aleatórios entre R$ 1.000 e R$ 9.000 (não casam com o extrato real), CNPJs de
-- mentira. As varreduras (R1) passam também pelos CMPs reais — dentro da transação, desfeito no
-- rollback. No PGlite as rotas financeiras são dublês (public.ensaio_respostas); em produção, as reais.
-- Sem id nem data fixos.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (dono uuid, phone text, conta uuid, cartao uuid) on commit drop;
create temp table _guarda (nome text primary key, id uuid, tx uuid) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._telefone() returns text language sql volatile as $$
  select '55000' || lpad((floor(random() * 1000000000))::bigint::text, 9, '0')
$$;
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select upper(translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop'))
$$;
create function pg_temp._val() returns numeric language sql volatile as $$
  select round((1000 + random() * 8000)::numeric, 2)
$$;
-- CNPJ de mentira (14 dígitos, raiz 7xxxxxxx: nunca a da HBR)
create function pg_temp._cnpj() returns text language sql volatile as $$
  select '7' || lpad((floor(random() * 9999999))::bigint::text, 7, '0') || '0001' || lpad((floor(random() * 99))::bigint::text, 2, '0')
$$;
create function pg_temp._hoje() returns date language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;

do $$
declare
  v_dono uuid := gen_random_uuid();
  v_phone text := pg_temp._telefone();
  v_conta uuid;
  v_cartao uuid;
begin
  insert into public.app_users (id, full_name, email, role, active, phone_normalized, ai_whatsapp_enabled, created_at)
  values (v_dono, 'Dono de teste F3', 'teste-f3-' || v_dono || '@teste.invalido', 'admin', true, v_phone, true,
          now() - interval '30 years');
  insert into public.app_settings (key, value) values ('comprovante_fluxo', 'dono')
  on conflict (key) do update set value = excluded.value;
  insert into public.app_settings (key, value) values ('comprovante_conversa', 'on')
  on conflict (key) do update set value = excluded.value;
  insert into public.bank_connections (provider, external_id, label, account_kind)
  values ('manual', 'teste-f3-' || gen_random_uuid(), 'Conta Teste F3', 'bank') returning id into v_conta;
  insert into public.bank_connections (provider, external_id, label, account_kind)
  values ('manual', 'teste-f3-' || gen_random_uuid(), 'Cartão Teste F3', 'credit_card') returning id into v_cartao;
  insert into _ctx values (v_dono, v_phone, v_conta, v_cartao);
end $$;

create function pg_temp._dono() returns uuid language sql stable as $$ select dono from _ctx $$;
create function pg_temp._phone() returns text language sql stable as $$ select phone from _ctx $$;
create function pg_temp._conta() returns uuid language sql stable as $$ select conta from _ctx $$;
create function pg_temp._cartao() returns uuid language sql stable as $$ select cartao from _ctx $$;
create function pg_temp._id(p_nome text) returns uuid language sql stable as $$ select id from _guarda where nome = p_nome $$;
create function pg_temp._tx(p_nome text) returns uuid language sql stable as $$ select tx from _guarda where nome = p_nome $$;
create function pg_temp._guardar(p_nome text, p_id uuid, p_tx uuid default null) returns void language sql as $$
  insert into _guarda values (p_nome, p_id, p_tx) on conflict (nome) do update set id = excluded.id, tx = excluded.tx
$$;

-- a linha do extrato (sempre de saída). p: valor, data, descricao, fonte (bank|credit_card), nome,
-- doc, loja, metodo, parcela, status
create function pg_temp._linha(p jsonb) returns uuid language sql as $$
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id,
                                        counterparty_name, counterparty_document, merchant_name, payment_method,
                                        installment_label, tx_status)
  values (coalesce((p->>'data')::date, pg_temp._hoje()), coalesce(p->>'descricao', 'DEBITO DE CARTAO'), (p->>'valor')::numeric,
          'debit', coalesce(p->>'fonte', 'bank'),
          case when coalesce(p->>'fonte', 'bank') = 'credit_card' then pg_temp._cartao() else pg_temp._conta() end,
          p->>'nome', p->>'doc', p->>'loja', p->>'metodo', p->>'parcela', coalesce(p->>'status', 'POSTED'))
  returning id
$$;
-- a proposta pendente da fila do Extrato para a linha
create function pg_temp._proposta(p_tx uuid, p_kind text default 'create_payable') returns uuid language sql as $$
  insert into public.finance_review_queue (kind, status, bank_transaction_id, title, confidence, suggested_category, reasoning)
  values (p_kind, 'pending', p_tx, 'Teste F3', 50, 'Outras despesas', 'motor de teste') returning id
$$;

-- o sim como o edge manda: a pergunta saiu (whatsapp-send confirmou) e a mensagem do dono é de DEPOIS
create function pg_temp._sim(p_pergunta jsonb) returns jsonb language plpgsql as $$
declare
  v_msg uuid;
begin
  perform public.pergunta_marcar_enviada((p_pergunta->>'pergunta_id')::uuid, 'WA-' || (p_pergunta->>'pergunta_id'));
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', pg_temp._phone(), 'text', 'sim', 'TESTE-F3-' || gen_random_uuid(), now() + interval '10 seconds')
  returning id into v_msg;
  return public.comprovante_responder(jsonb_build_object(
    'pergunta_id', p_pergunta->>'pergunta_id', 'message_id', v_msg, 'interpretacao', jsonb_build_object('tipo', 'sim')));
end $$;

-- fecha as perguntas abertas do dono de teste (cada teste começa limpo)
create function pg_temp._livrar() returns void language plpgsql as $$
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste'
   where phone_normalized = pg_temp._phone() and status = 'aberta';
  update public.comprovantes set situacao = 'cancelado', motivo_cancelamento = 'dono_cancelou', cancelado_em = now()
   where phone_normalized = pg_temp._phone() and situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
  update public.comprovantes_fila_do_telefone set pausada_ate = null, ultima_pergunta_fechada_em = null
   where phone_normalized = pg_temp._phone();
  delete from public.whatsapp_messages where phone_normalized = pg_temp._phone();
end $$;

-- CMP lido → fila → respostas → resumo → sim (o caminho de verdade: RPC 7 e RPC 9). p: valor, forma,
-- destino (insumo), cnpj (emitente), favorecido, fornecedor, os, cobrar, quem, pagador, categoria,
-- data, tipo. Devolve a saída do responder + {"id"}.
create function pg_temp._cmp(p jsonb) returns jsonb language plpgsql as $$
declare
  v uuid;
  v_p jsonb;
begin
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized,
                                   tipo_whatsapp, recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca,
                                   data_compra, data_confianca, forma_pagamento, lido_em,
                                   emitente_cnpj, cnpj_confianca, favorecido_doc, supplier_id, fornecedor_receita)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(),
          'TESTE-F3-' || gen_random_uuid(), pg_temp._phone(), 'image', now(),
          md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text),
          coalesce(p->>'tipo', 'nfce'), 'alta', (p->>'valor')::numeric, 'alta',
          coalesce((p->>'data')::date, pg_temp._hoje()), 'alta', p->>'forma', now(),
          p->>'cnpj', case when p ? 'cnpj' then 'alta' end, p->>'favorecido', nullif(p->>'fornecedor', '')::uuid,
          p->>'receita')
  returning id into v;
  perform public.comprovante_conversa_entrar(array[v]);
  update public.comprovantes
     set destino = coalesce(p->>'destino', 'insumo'), destino_os_id = nullif(p->>'os', '')::uuid,
         cobrar_cliente = (p->>'cobrar')::boolean, quem_pagou = p->>'quem', pagador_payee_id = nullif(p->>'pagador', '')::uuid,
         categoria = p->>'categoria', outra_compra = true
   where id = v;
  perform pg_temp._livrar_perguntas();
  update public.comprovantes set fila_ordem = now() + interval '1 day'
   where phone_normalized = pg_temp._phone() and situacao = 'aguardando_vez' and id <> v;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v);
  if not coalesce((v_p->>'perguntou')::boolean, false) or v_p->>'passo' is distinct from 'confirmar' then
    return jsonb_build_object('id', v, 'resultado', 'nao_chegou_no_confirmar', 'passo', v_p->>'passo', 'motivo', v_p->>'motivo');
  end if;
  return pg_temp._sim(v_p) || jsonb_build_object('id', v, 'plano_mostrado', v_p->'plano');
end $$;

create function pg_temp._livrar_perguntas() returns void language sql as $$
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste'
   where phone_normalized = pg_temp._phone() and status = 'aberta'
$$;

-- a pergunta da F3 de um CMP (como o "cmp N": ignora horário e espaçamento)
create function pg_temp._banco(p_cmp uuid) returns jsonb language plpgsql as $$
begin
  perform pg_temp._livrar_perguntas();
  return public.comprovante_banco_proxima(pg_temp._phone(), 'cmp', p_cmp);
end $$;

-- a resposta do dono à pergunta da F3, mandada depois de a pergunta sair
create function pg_temp._resp(p_pergunta jsonb, p_interp jsonb, p_antes boolean default false) returns jsonb language plpgsql as $$
declare
  v_msg uuid;
begin
  perform public.pergunta_marcar_enviada((p_pergunta->>'pergunta_id')::uuid, 'WA-' || (p_pergunta->>'pergunta_id'));
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', pg_temp._phone(), 'text', 'resposta', 'TESTE-F3-' || gen_random_uuid(),
          case when p_antes then now() - interval '1 minute' else now() + interval '10 seconds' end)
  returning id into v_msg;
  return public.comprovante_banco_responder(jsonb_build_object(
    'pergunta_id', p_pergunta->>'pergunta_id', 'message_id', v_msg, 'interpretacao', p_interp, 'autor', pg_temp._dono()));
end $$;

create function pg_temp._tipos(p_efeitos jsonb) returns text language sql immutable as $$
  select coalesce(string_agg(e->>'tipo' || case when e->>'tipo' = 'pendencia' then ':' || (e->>'qual') else '' end, ',' order by o), '')
    from jsonb_array_elements(coalesce(p_efeitos, '[]'::jsonb)) with ordinality as t(e, o)
$$;

-- ═══ T1 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f text;
  v_ruins text[] := '{}';
begin
  foreach v_f in array array[
    'public.comprovantes_reavaliar_banco(text, uuid)', 'public.comprovantes_linhas_da_conciliacao(uuid[])',
    'public.comprovante_banco_proxima(text, text, uuid)', 'public.comprovante_banco_responder(jsonb)',
    'public.comprovante_nota_chegou(uuid)', 'public.comprovantes_vigia_banco(integer)',
    'public.comprovantes_indice_pessoal_do_mes(date)', 'public.comprovante_indice_pessoal_gravado(date, text, text, text, integer)',
    'public.comprovante_indice_pessoal_falhou(date, text)', 'public.comprovante_banco_ceder(text)'] loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute')
       or not has_function_privilege('service_role', v_f, 'execute') then
      v_ruins := v_ruins || v_f;
    end if;
  end loop;
  foreach v_f in array array[
    'public._comprovante_candidatos(public.comprovantes)', 'public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean)',
    'public._comprovante_ligar(uuid, uuid, text, text, uuid, boolean)', 'public._comprovante_desligar(uuid, text, uuid, boolean)',
    'public._comprovantes_banco_varrer(integer, text)', 'public._comprovante_banco_regra(public.comprovantes)',
    'public._comprovante_reembolso_data(uuid, date)', 'public._comprovante_nota_aplicar(uuid, uuid)',
    'public._comprovante_banco_abrir(uuid, text)', 'public._comprovantes_indice_pessoal_marcar()'] loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute')
       or has_function_privilege('service_role', v_f, 'execute') then
      v_ruins := v_ruins || v_f;
    end if;
  end loop;
  if has_table_privilege('anon', 'public.diarias_reembolsos', 'select') or has_table_privilege('authenticated', 'public.diarias_reembolsos', 'insert')
     or has_table_privilege('anon', 'public.comprovantes_indice_pessoal', 'select')
     or has_table_privilege('authenticated', 'public.comprovantes_indice_pessoal', 'insert')
     or has_column_privilege('anon', 'public.comprovantes', 'banco_candidatos', 'select') then
    v_ruins := v_ruins || 'tabelas'::text;
  end if;
  insert into _resultado values ('T1 grants: R1-R10 só service_role, helpers para ninguém, tabelas novas fechadas',
    cardinality(v_ruins) = 0, array_to_string(v_ruins, ', '));
exception when others then
  insert into _resultado values ('T1 grants: R1-R10 só service_role, helpers para ninguém, tabelas novas fechadas', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T2 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cnpj text := pg_temp._cnpj();
  g jsonb;
  v_cmp uuid;
  v_tx uuid;
  v_q uuid;
  v_r1 jsonb;
  p jsonb;
  r jsonb;
  c record;
  q record;
  a record;
  v_nome text;
  v_extrato text;
begin
  perform pg_temp._livrar();
  g := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', v_cnpj, 'receita', 'Loja Teste F3 Dois'));
  v_cmp := (g->>'id')::uuid;
  select * into c from public.comprovantes where id = v_cmp;
  -- gravado sem linha (cinza): espera o banco, sem anotar (o débito do C6 chega sem documento)
  if g->>'resultado' <> 'gravado' or c.situacao <> 'aguardando_banco' or pg_temp._tipos(c.efeitos) <> 'aguardar_banco'
     or c.anotacao_id is not null or c.banco_regra <> 'debito' then
    raise exception 'gravação inesperada: % % %', g->>'resultado', c.situacao, pg_temp._tipos(c.efeitos);
  end if;
  -- a linha chega (sem nome, sem documento) e a proposta entra na fila; a varredura acha a verde
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val, 'data', pg_temp._hoje() + 1));
  v_q := pg_temp._proposta(v_tx);
  v_r1 := public.comprovantes_reavaliar_banco('teste', null);
  select * into c from public.comprovantes where id = v_cmp;
  p := pg_temp._banco(v_cmp);
  r := pg_temp._resp(p, '{"tipo":"sim"}'::jsonb);
  select * into c from public.comprovantes where id = v_cmp;
  select * into q from public.finance_review_queue where id = v_q;
  select * into a from public.anotacoes_do_extrato where id = (q.evidencia->'anotacao'->>'id')::uuid;
  select nome_pelo_comprovante into v_nome from public.bank_transactions where id = v_tx;
  select e.contraparte into v_extrato from public.extrato_da_conta(pg_temp._conta(), pg_temp._hoje() + 1, pg_temp._hoje() + 1) e
   where e.id = v_tx;
  perform pg_temp._guardar('T2', v_cmp, v_tx);
  insert into _resultado values ('T2 débito único sem nome: verde, "sim" liga e classifica (anotação aplicada), loja no extrato',
    (v_r1->>'verdes')::integer >= 1 and p->>'perguntou' = 'true' and p->'banco'->>'nivel' = 'verde'
    and jsonb_array_length(p->'opcoes') = 1 and p->'opcoes'->0->>'valor' = 'tx:' || v_tx
    and r->>'resultado' = 'ligado' and r->'ligacao'->>'como' = 'classificou' and r->'ligacao'->>'origem' = 'sim'
    and c.situacao = 'conciliado' and c.bank_transaction_id = v_tx and c.conciliacao = 'verde'
    and c.linha_explicada_em is not null and not c.banco_perguntar
    and q.status = 'pending' and q.confidence = 99 and q.evidencia ? 'anotacao' and q.suggested_category = 'Materiais e Insumos Operacionais'
    and a.status = 'aplicada' and a.bank_transaction_id = v_tx and a.descricao like c.codigo || ' · %' and a.documento is null
    and c.anotacao_id = a.id
    and v_nome like '%' || c.codigo and v_extrato = v_nome
    and r->'cmp'->'banco'->>'estado' = 'ligado',
    'r1=' || coalesce(v_r1->>'verdes', '-') || ' nivel=' || coalesce(p->'banco'->>'nivel', p->>'motivo', '-')
    || ' r=' || coalesce(r->>'resultado', '-') || '/' || coalesce(r->>'motivo', '-') || ' situacao=' || c.situacao
    || ' prop=' || q.confidence || ' extrato=' || coalesce(v_extrato, '-'));
exception when others then
  insert into _resultado values ('T2 débito único sem nome: verde, "sim" liga e classifica (anotação aplicada), loja no extrato', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T3 / T4 ═════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  g jsonb;
  g2 jsonb;
  v_cmp uuid;
  v_cmp2 uuid;
  v_tx1 uuid;
  v_tx2 uuid;
  v_tx3 uuid;
  v_tx4 uuid;
  p jsonb;
  r jsonb;
  p2 jsonb;
  r2 jsonb;
  c record;
  c2 record;
begin
  -- T3: dois débitos iguais (D e D+1) → azul; "2" liga a segunda
  perform pg_temp._livrar();
  g := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()));
  v_cmp := (g->>'id')::uuid;
  v_tx1 := pg_temp._linha(jsonb_build_object('valor', v_val, 'data', pg_temp._hoje()));
  v_tx2 := pg_temp._linha(jsonb_build_object('valor', v_val, 'data', pg_temp._hoje() + 1));
  perform pg_temp._proposta(v_tx1);
  perform pg_temp._proposta(v_tx2);
  perform public.comprovantes_reavaliar_banco('teste', null);
  p := pg_temp._banco(v_cmp);
  r := pg_temp._resp(p, '{"tipo":"opcao","n":2}'::jsonb);
  select * into c from public.comprovantes where id = v_cmp;
  insert into _resultado values ('T3 dois débitos iguais: azul 1/2/0, a escolha 2 liga a segunda',
    p->'banco'->>'nivel' = 'azul' and jsonb_array_length(p->'opcoes') = 3
    and p->'opcoes'->0->>'valor' = 'tx:' || v_tx1 and p->'opcoes'->1->>'valor' = 'tx:' || v_tx2
    and p->'opcoes'->2->>'n' = '0' and p->'opcoes'->2->>'valor' = 'nenhum'
    and r->>'resultado' = 'ligado' and c.bank_transaction_id = v_tx2 and c.conciliacao = 'azul'
    and r->'ligacao'->>'origem' = 'escolha',
    'nivel=' || coalesce(p->'banco'->>'nivel', p->>'motivo', '-') || ' r=' || coalesce(r->>'resultado', '-') || '/' || coalesce(r->>'motivo', '-'));

  -- T4: outro CMP, outras duas linhas iguais: "0" recusa as duas; a próxima avaliação é cinza
  v_val := pg_temp._val();
  g2 := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()));
  v_cmp2 := (g2->>'id')::uuid;
  v_tx3 := pg_temp._linha(jsonb_build_object('valor', v_val));
  v_tx4 := pg_temp._linha(jsonb_build_object('valor', v_val, 'data', pg_temp._hoje() + 2));
  perform public.comprovantes_reavaliar_banco('teste', null);
  p2 := pg_temp._banco(v_cmp2);
  r2 := pg_temp._resp(p2, '{"tipo":"opcao","n":0}'::jsonb);
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c2 from public.comprovantes where id = v_cmp2;
  insert into _resultado values ('T4 "0" recusa as listadas; a próxima avaliação fica cinza',
    p2->'banco'->>'nivel' = 'azul' and r2->>'resultado' = 'recusado' and r2->>'ate' is not null
    and c2.banco_recusados @> array[v_tx3, v_tx4] and c2.conciliacao = 'cinza' and not c2.banco_perguntar
    and c2.situacao = 'aguardando_banco' and jsonb_array_length(c2.banco_candidatos) = 0,
    'p=' || coalesce(p2->'banco'->>'nivel', '-') || ' r=' || coalesce(r2->>'resultado', '-') || ' nivel_depois=' || coalesce(c2.conciliacao, '-'));
exception when others then
  insert into _resultado values ('T3/T4 azul e recusa', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T5 / T6 / T7 (candidatos por forma, sem gravar o vínculo) ══════════════════════════════
do $$
declare
  v_val numeric;
  v_cnpj text := pg_temp._cnpj();
  v_outro text := pg_temp._cnpj();
  v_cmp uuid;
  v_txa uuid;
  v_txb uuid;
  c public.comprovantes;
  av5 jsonb;
  av6 jsonb;
  av7a jsonb;
  av7b jsonb;
  av7c jsonb;
  v_loja text := 'LOJA TESTE F3 ' || pg_temp._letras(6);
  v_cnpj7 text := pg_temp._cnpj();
  v_total numeric;
begin
  perform pg_temp._livrar();
  -- T5: Pix com CNPJ (o do recebedor): a linha da mesma raiz é forte; a de outra raiz sai
  v_val := pg_temp._val();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', v_cnpj))->>'id')::uuid;
  v_txa := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX',
                                             'doc', left(v_cnpj, 8) || '000299', 'nome', 'NOME QUALQUER'));
  v_txb := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX', 'doc', v_outro));
  select * into c from public.comprovantes where id = v_cmp;
  av5 := public._comprovante_candidatos(c);
  perform pg_temp._guardar('T5', v_cmp, v_txa);
  insert into _resultado values ('T5 Pix com CNPJ: a linha do mesmo CNPJ (raiz) é verde; a de outro CNPJ fica de fora',
    av5->>'nivel' = 'verde' and av5->>'regra' = 'pix' and jsonb_array_length(av5->'linhas') = 1
    and av5->'linhas'->0->>'id' = v_txa::text and av5->'linhas'->0->'motivos' ? 'documento'
    and (av5->'linhas'->0->>'forte')::boolean,
    'nivel=' || coalesce(av5->>'nivel', '-') || ' linhas=' || coalesce(jsonb_array_length(av5->'linhas'), -1));

  -- T6: Pix com CPF mascarado: o CPF que bate nos 5 dígitos é candidata fraca (azul); outro CPF sai
  v_val := pg_temp._val();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', '***.***.123-45'))->>'id')::uuid;
  v_txa := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX', 'doc', '98765412345'));
  v_txb := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX', 'doc', '98765499999'));
  select * into c from public.comprovantes where id = v_cmp;
  av6 := public._comprovante_candidatos(c);
  insert into _resultado values ('T6 Pix com CPF mascarado: azul (cpf_parcial); CPF com outros finais fica de fora',
    av6->>'nivel' = 'azul' and jsonb_array_length(av6->'linhas') = 1 and av6->'linhas'->0->>'id' = v_txa::text
    and av6->'linhas'->0->'motivos' ? 'cpf_parcial' and not (av6->'linhas'->0->>'forte')::boolean,
    'nivel=' || coalesce(av6->>'nivel', '-') || ' linhas=' || coalesce(jsonb_array_length(av6->'linhas'), -1));

  -- T7: crédito. A Receita diz o nome fantasia (cache da BrasilAPI)
  insert into public.cnpj_consultas (cnpj, encontrado, razao_social, nome_fantasia, consultado_em)
  values (v_cnpj7, true, v_loja || ' COMERCIO LTDA', v_loja, now())
  on conflict (cnpj) do update set nome_fantasia = excluded.nome_fantasia, razao_social = excluded.razao_social, encontrado = true;
  -- (a) à vista, nome igual, D+0 → verde
  v_val := pg_temp._val();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'credito', 'cnpj', v_cnpj7))->>'id')::uuid;
  v_txa := pg_temp._linha(jsonb_build_object('valor', v_val, 'fonte', 'credit_card', 'descricao', v_loja, 'loja', v_loja, 'status', 'PENDING'));
  select * into c from public.comprovantes where id = v_cmp;
  av7a := public._comprovante_candidatos(c);
  -- (b) nome diferente → azul (nunca forte)
  v_val := pg_temp._val();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'credito', 'cnpj', v_cnpj7))->>'id')::uuid;
  v_txa := pg_temp._linha(jsonb_build_object('valor', v_val, 'fonte', 'credit_card', 'descricao', 'OUTRA LOJA QUALQUER', 'loja', 'OUTRA LOJA QUALQUER'));
  select * into c from public.comprovantes where id = v_cmp;
  av7b := public._comprovante_candidatos(c);
  -- (c) parcela 1/3 da compra → azul, com o total (a parcela 1/n vem datada perto da compra: D-1..D+5)
  v_total := round(pg_temp._val() / 3, 2) * 3;
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_total, 'forma', 'credito', 'cnpj', v_cnpj7))->>'id')::uuid;
  v_txa := pg_temp._linha(jsonb_build_object('valor', v_total / 3, 'fonte', 'credit_card', 'descricao', v_loja, 'loja', v_loja,
                                             'parcela', '1/3', 'data', pg_temp._hoje() + 2));
  select * into c from public.comprovantes where id = v_cmp;
  av7c := public._comprovante_candidatos(c);
  insert into _resultado values ('T7 crédito: à vista com nome igual verde; nome diferente azul; parcela 1/3 azul com o total',
    av7a->>'nivel' = 'verde' and (av7a->'linhas'->0->>'pendente')::boolean and av7a->'linhas'->0->>'acao' = 'aguardar'
    and av7a->'linhas'->0->'motivos' ? 'nome_igual'
    and av7b->>'nivel' = 'azul' and av7b->'linhas'->0->'motivos' ? 'nome_diferente'
    and av7c->>'nivel' = 'azul' and av7c->'linhas'->0->>'parcela' = '1/3'
    and (av7c->'linhas'->0->>'total_da_compra')::numeric = v_total and av7c->'linhas'->0->'motivos' ? 'parcela_1_de_3',
    'a=' || coalesce(av7a->>'nivel', '-') || ' b=' || coalesce(av7b->>'nivel', '-') || ' c=' || coalesce(av7c->>'nivel', '-'));
exception when others then
  insert into _resultado values ('T5/T6/T7 candidatos por forma', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T8 / T9 ═════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  v_tx uuid;
  v_pay uuid;
  v_sup uuid;
  v_cnpj text := pg_temp._cnpj();
  v_q uuid;
  p jsonb;
  r jsonb;
  c record;
  pay record;
  q record;
  g jsonb;
begin
  -- T8: a linha já virou lançamento (Outras despesas): o "sim" anexa e corrige a categoria
  perform pg_temp._livrar();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val));
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               bank_transaction_id, origin)
  values ('Débito de teste F3', pg_temp._hoje(), pg_temp._hoje(), v_val, v_val, 0, 'paid', 'Outras despesas', v_tx, 'manual')
  returning id into v_pay;
  perform public.comprovantes_reavaliar_banco('teste', null);
  p := pg_temp._banco(v_cmp);
  r := pg_temp._resp(p, '{"tipo":"sim"}'::jsonb);
  select * into c from public.comprovantes where id = v_cmp;
  select * into pay from public.payables where id = v_pay;
  insert into _resultado values ('T8 a linha já virou lançamento: o "sim" anexa e corrige a categoria (o "antes" fica)',
    p->'banco'->'linhas'->0->>'acao' = 'anexar' and r->>'resultado' = 'ligado' and r->'ligacao'->>'como' = 'anexou'
    and c.payable_id = v_pay and pay.expense_category = 'Materiais e Insumos Operacionais'
    and r->'ligacao'->'corrigido'->'expense_category'->>'antes' = 'Outras despesas' and c.linha_explicada_em is not null,
    'acao=' || coalesce(p->'banco'->'linhas'->0->>'acao', '-') || ' r=' || coalesce(r->>'resultado', '-') || '/' || coalesce(r->'ligacao'->>'como', r->>'motivo', '-')
    || ' cat=' || coalesce(pay.expense_category, '-'));

  -- T9: conta a pagar em aberto do fornecedor (mesmo CNPJ): o CMP Pix a anexa e espera o banco;
  -- a linha chega, o "sim" casa (conciliar_lancamento) e a proposta sai da fila
  perform pg_temp._livrar();
  v_val := pg_temp._val();
  insert into public.suppliers (name, cnpj_cpf) values ('Fornecedor Teste F3 ' || pg_temp._letras(5), v_cnpj) returning id into v_sup;
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               supplier_id, origin)
  values ('Conta aberta de teste F3', pg_temp._hoje(), pg_temp._hoje() + 5, v_val, 0, v_val, 'pending', 'Peças e materiais', v_sup, 'manual')
  returning id into v_pay;
  g := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', v_cnpj, 'fornecedor', v_sup));
  v_cmp := (g->>'id')::uuid;
  select * into c from public.comprovantes where id = v_cmp;
  if c.situacao <> 'aguardando_banco' or c.payable_id is distinct from v_pay or not ('classificar_no_extrato' = any (c.pendencias)) then
    raise exception 'conta em aberto: gravação inesperada % % %', c.situacao, pg_temp._tipos(c.efeitos), c.pendencias;
  end if;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX', 'doc', v_cnpj, 'nome', 'FORNECEDOR'));
  v_q := pg_temp._proposta(v_tx);
  perform public.comprovantes_reavaliar_banco('teste', null);
  p := pg_temp._banco(v_cmp);
  r := pg_temp._resp(p, '{"tipo":"sim"}'::jsonb);
  select * into c from public.comprovantes where id = v_cmp;
  select * into pay from public.payables where id = v_pay;
  select * into q from public.finance_review_queue where id = v_q;
  insert into _resultado values ('T9 conta a pagar em aberto: o "sim" casa a conta com a linha e a proposta sai da fila',
    p->'banco'->>'nivel' = 'verde' and p->'banco'->'linhas'->0->>'acao' = 'casar'
    and r->>'resultado' = 'ligado' and r->'ligacao'->>'como' = 'casou'
    and pay.bank_transaction_id = v_tx and pay.status = 'paid' and q.status = 'superseded'
    and q.decision_note like 'Casada com a conta do CMP-%' and c.situacao = 'conciliado'
    and not ('classificar_no_extrato' = any (c.pendencias))
    and exists (select 1 from jsonb_array_elements(c.efeitos) e where e->>'tipo' = 'pendencia_resolvida'),
    'nivel=' || coalesce(p->'banco'->>'nivel', p->>'motivo', '-') || ' r=' || coalesce(r->>'resultado', '-') || '/' || coalesce(r->>'motivo', '-')
    || ' pay=' || coalesce(pay.status, '-') || ' fila=' || coalesce(q.status, '-'));
exception when others then
  insert into _resultado values ('T8/T9 lançamento e conta em aberto', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T10 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cnpj text := pg_temp._cnpj();
  v_sup uuid;
  v_cmp uuid;
  v_tx uuid;
  v_q uuid;
  v_aplicadas integer;
  v_r1 jsonb;
  c record;
  a record;
  v_perg integer;
begin
  -- o Pix com CNPJ e sem linha (cinza) anota (o sim do resumo já autorizou); quando a linha chega, o
  -- aplicar_anotacoes_pendentes a classifica e a varredura liga sem pergunta
  perform pg_temp._livrar();
  insert into public.suppliers (name, cnpj_cpf) values ('Fornecedor Pix F3 ' || pg_temp._letras(5), v_cnpj) returning id into v_sup;
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', v_cnpj, 'fornecedor', v_sup))->>'id')::uuid;
  select * into c from public.comprovantes where id = v_cmp;
  if pg_temp._tipos(c.efeitos) <> 'anotar' or c.situacao <> 'aguardando_banco' or c.anotacao_id is null then
    raise exception 'Pix com CNPJ cinza deveria anotar: % %', pg_temp._tipos(c.efeitos), c.situacao;
  end if;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX', 'doc', v_cnpj,
                                            'nome', 'FORNECEDOR PIX'));
  v_q := pg_temp._proposta(v_tx);
  update public.finance_review_queue set suggested_supplier_id = v_sup where id = v_q;
  v_aplicadas := public.aplicar_anotacoes_pendentes();
  select count(*) into v_perg from public.whatsapp_perguntas where referencia_id = v_cmp and passo = 'banco';
  v_r1 := public.comprovantes_reavaliar_banco('teste', null);
  select * into c from public.comprovantes where id = v_cmp;
  select * into a from public.anotacoes_do_extrato where id = c.anotacao_id;
  insert into _resultado values ('T10 a anotação da F2 aplicada pelo motor: a varredura liga sem pergunta',
    v_aplicadas >= 1 and a.status = 'aplicada' and a.bank_transaction_id = v_tx
    and c.situacao = 'conciliado' and c.bank_transaction_id = v_tx and c.linha_explicada_em is not null
    and exists (select 1 from jsonb_array_elements(c.efeitos) e
                 where e->>'tipo' = 'ligar_linha' and e->>'origem' = 'anotacao' and e->>'como' = 'classificou')
    and v_perg = 0 and (select count(*) from public.whatsapp_perguntas where referencia_id = v_cmp and passo = 'banco') = 0
    and (v_r1->>'ligados')::integer >= 1,
    'aplicadas=' || v_aplicadas || ' anot=' || coalesce(a.status, '-') || ' situacao=' || c.situacao || ' ligados=' || coalesce(v_r1->>'ligados', '-'));
exception when others then
  insert into _resultado values ('T10 a anotação da F2 aplicada pelo motor: a varredura liga sem pergunta', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T11 / T12 ═══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_a uuid;
  v_b uuid;
  v_tx uuid;
  ca record;
  cb record;
  v_d uuid;
  v_c30 uuid;
  v_c46 uuid;
  v_c31 uuid;
  d public.comprovantes;
  c30 record;
  c46 record;
  c31 record;
begin
  -- T11: a mesma linha forte para dois CMPs → disputada → azul nos dois
  perform pg_temp._livrar();
  v_a := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_b := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val));
  perform public.comprovantes_reavaliar_banco('teste', null);
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into ca from public.comprovantes where id = v_a;
  select * into cb from public.comprovantes where id = v_b;
  insert into _resultado values ('T11 linha forte de dois CMPs: disputada, azul nos dois',
    ca.conciliacao = 'azul' and cb.conciliacao = 'azul'
    and ca.banco_candidatos->0->'motivos' ? 'disputada' and cb.banco_candidatos->0->'motivos' ? 'disputada'
    and not (ca.banco_candidatos->0->>'forte')::boolean and not (cb.banco_candidatos->0->>'forte')::boolean,
    'a=' || coalesce(ca.conciliacao, '-') || ' b=' || coalesce(cb.conciliacao, '-'));
  -- tira os dois do caminho dos próximos testes
  update public.comprovantes set banco_recusados = array[v_tx] where id in (v_a, v_b);

  -- T12: abandono (30 dias; 45 no crédito) e a pendência
  v_d := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_c30 := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'credito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_c46 := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'credito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_c31 := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  update public.comprovantes set aguardando_banco_desde = now() - interval '31 days' where id in (v_d, v_c30);
  update public.comprovantes set aguardando_banco_desde = now() - interval '46 days' where id = v_c46;
  update public.comprovantes set aguardando_banco_desde = now() - interval '29 days' where id = v_c31;
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into d from public.comprovantes where id = v_d;
  select * into c30 from public.comprovantes where id = v_c30;
  select * into c46 from public.comprovantes where id = v_c46;
  select * into c31 from public.comprovantes where id = v_c31;
  insert into _resultado values ('T12 abandono: débito em 30 dias, crédito em 45, com a pendência "classificar no Extrato"',
    d.situacao = 'abandonado' and 'classificar_no_extrato' = any (d.pendencias)
    and c30.situacao = 'aguardando_banco' and c46.situacao = 'abandonado' and 'classificar_no_extrato' = any (c46.pendencias)
    and c31.situacao = 'aguardando_banco' and public._comprovante_banco_resumo(d)->>'estado' = 'abandonado',
    'debito31=' || d.situacao || ' credito31=' || c30.situacao || ' credito46=' || c46.situacao || ' debito29=' || c31.situacao);
exception when others then
  insert into _resultado values ('T11/T12 disputa e abandono', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T13 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  v_tx uuid;
  v_q uuid;
  v_cmp2 uuid;
  v_tx2 uuid;
  v_q2 uuid;
  p jsonb;
  r jsonb;
  c record;
  c2 record;
  q record;
  v_anot uuid;
  v_anot_status text;
  v_nome text;
begin
  -- (a) o valor da linha mudou (pré-autorização do posto) → desliga e volta a procurar
  perform pg_temp._livrar();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val));
  v_q := pg_temp._proposta(v_tx);
  perform public.comprovantes_reavaliar_banco('teste', null);
  p := pg_temp._banco(v_cmp);
  r := pg_temp._resp(p, '{"tipo":"sim"}'::jsonb);
  select anotacao_id into v_anot from public.comprovantes where id = v_cmp;
  update public.bank_transactions set amount = amount + 10 where id = v_tx;
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c from public.comprovantes where id = v_cmp;
  select * into q from public.finance_review_queue where id = v_q;
  select status into v_anot_status from public.anotacoes_do_extrato where id = v_anot;
  select nome_pelo_comprovante into v_nome from public.bank_transactions where id = v_tx;

  -- (b) o dono recusou a proposta da linha no Extrato → desliga e a linha não volta
  v_val := pg_temp._val();
  v_cmp2 := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_tx2 := pg_temp._linha(jsonb_build_object('valor', v_val));
  v_q2 := pg_temp._proposta(v_tx2);
  perform public.comprovantes_reavaliar_banco('teste', null);
  p := pg_temp._banco(v_cmp2);
  r := pg_temp._resp(p, '{"tipo":"sim"}'::jsonb);
  update public.finance_review_queue set status = 'rejected', decided_at = now() where id = v_q2;
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c2 from public.comprovantes where id = v_cmp2;
  insert into _resultado values ('T13 re-validação: valor mudou desliga (a linha volta ao motor); proposta recusada desliga e recusa',
    r->>'resultado' = 'ligado'
    and c.situacao = 'aguardando_banco' and c.bank_transaction_id is null and c.linha_explicada_em is null
    and not (q.evidencia ? 'anotacao') and q.confidence <= 50 and q.reasoning like c.codigo || ' desligado%'
    and v_anot_status = 'cancelada' and v_nome is null
    and exists (select 1 from jsonb_array_elements(c.efeitos) e where e->>'tipo' = 'ligar_linha' and e->>'desligado_motivo' = 'linha_mudou')
    and c2.situacao = 'aguardando_banco' and c2.bank_transaction_id is null and v_tx2 = any (c2.banco_recusados),
    'a=' || c.situacao || '/' || coalesce(v_anot_status, '-') || ' b=' || c2.situacao || ' recusada=' || (v_tx2 = any (c2.banco_recusados)));
exception when others then
  insert into _resultado values ('T13 re-validação: valor mudou desliga (a linha volta ao motor); proposta recusada desliga e recusa', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T14 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_agora timestamp := now() at time zone 'America/Sao_Paulo';
  v_dentro boolean;
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  v_fila uuid;
  v_pode_livre text;
  v_pode_f2 text;
  v_lista_1h jsonb;
  v_lista_5h jsonb;
  v_lista_lim jsonb;
  v_vigia jsonb;
  v_desl jsonb;
  c record;
  v_detalhe text;
begin
  perform pg_temp._livrar();
  v_dentro := extract(isodow from v_agora) <> 7 and v_agora::time >= time '08:00' and v_agora::time < time '20:00';
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  perform pg_temp._linha(jsonb_build_object('valor', v_val));
  perform public.comprovantes_reavaliar_banco('teste', null);
  perform pg_temp._livrar();
  -- só este CMP tem pergunta da F3 a fazer (os dos testes anteriores, do mesmo telefone, não contam)
  update public.comprovantes set banco_perguntar = false where phone_normalized = pg_temp._phone() and id <> v_cmp;
  -- sem fila da F2: pode (dentro do horário) ou fora_do_horario
  v_pode_livre := public._comprovante_banco_pode(pg_temp._phone());
  -- espaçamento de 4 h e limite de 3 (pela lista do vigia)
  update public.comprovantes set banco_ultima_pergunta_em = now() - interval '1 hour', banco_perguntas = 1 where id = v_cmp;
  v_lista_1h := public.comprovantes_vigia_banco(5);
  update public.comprovantes set banco_ultima_pergunta_em = now() - interval '5 hours' where id = v_cmp;
  v_lista_5h := public.comprovantes_vigia_banco(5);
  update public.comprovantes set banco_perguntas = 3 where id = v_cmp;
  v_lista_lim := public.comprovantes_vigia_banco(5);
  update public.comprovantes set banco_perguntas = 0 where id = v_cmp;
  -- a fila da F2 vem primeiro: um CMP esperando a vez
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized, tipo_whatsapp,
                                   recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca, data_compra, lido_em)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(), 'TESTE-F3-' || gen_random_uuid(),
          pg_temp._phone(), 'image', now(), md5(random()::text) || md5(clock_timestamp()::text), 'nfce', 'alta', pg_temp._val(), 'alta',
          pg_temp._hoje(), now())
  returning id into v_fila;
  perform public.comprovante_conversa_entrar(array[v_fila]);
  v_pode_f2 := public._comprovante_banco_pode(pg_temp._phone());
  v_vigia := public.comprovante_banco_proxima(pg_temp._phone(), 'vigia', null);
  update public.comprovantes set situacao = 'cancelado', motivo_cancelamento = 'dono_cancelou', cancelado_em = now() where id = v_fila;
  -- conversa desligada: nada perguntado; a varredura só guarda os candidatos
  update public.app_settings set value = 'off' where key = 'comprovante_conversa';
  update public.comprovantes set banco_hash = null, banco_avaliado_em = null, banco_candidatos = '[]' where id = v_cmp;
  perform public.comprovantes_reavaliar_banco('teste', null);
  v_desl := public.comprovante_banco_proxima(pg_temp._phone(), 'cmp', v_cmp);
  select * into c from public.comprovantes where id = v_cmp;
  update public.app_settings set value = 'on' where key = 'comprovante_conversa';

  v_detalhe := 'dentro=' || v_dentro || ' livre=' || coalesce(v_pode_livre, 'pode') || ' f2=' || coalesce(v_pode_f2, 'pode')
    || ' 1h=' || (v_lista_1h->'perguntar' @> to_jsonb(pg_temp._phone())) || ' 5h=' || (v_lista_5h->'perguntar' @> to_jsonb(pg_temp._phone()))
    || ' limite=' || (v_lista_lim->'perguntar' @> to_jsonb(pg_temp._phone())) || ' vigia=' || coalesce(v_vigia->>'motivo', '-')
    || ' desligada=' || coalesce(v_desl->>'motivo', '-') || ' guardados=' || jsonb_array_length(c.banco_candidatos);
  insert into _resultado values ('T14 vigia: horário, 4 h, 3 tentativas, a F2 primeiro; conversa desligada só guarda os candidatos',
    case when v_dentro
         then v_pode_livre is null and v_pode_f2 = 'fila_da_f2' and v_vigia->>'motivo' = 'fila_da_f2'
              and v_lista_5h->'perguntar' @> to_jsonb(pg_temp._phone())
         else v_pode_livre = 'fora_do_horario' and v_pode_f2 = 'fora_do_horario' and v_vigia->>'motivo' = 'fora_do_horario'
              and not (v_lista_5h->'perguntar' @> to_jsonb(pg_temp._phone())) end
    and not (v_lista_1h->'perguntar' @> to_jsonb(pg_temp._phone())) and not (v_lista_lim->'perguntar' @> to_jsonb(pg_temp._phone()))
    and v_desl->>'motivo' = 'desligada' and jsonb_array_length(c.banco_candidatos) = 1 and not c.banco_perguntar,
    v_detalhe);
  update public.comprovantes set banco_recusados = array(select (e->>'id')::uuid from jsonb_array_elements(c.banco_candidatos) e) where id = v_cmp;
exception when others then
  update public.app_settings set value = 'on' where key = 'comprovante_conversa';
  insert into _resultado values ('T14 vigia: horário, 4 h, 3 tentativas, a F2 primeiro; conversa desligada só guarda os candidatos', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T15 / T16 ═══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cnpj text := pg_temp._cnpj();
  v_loja text := 'FARMACIA TESTE F3 ' || pg_temp._letras(5);
  v_cmp uuid;
  v_tx uuid;
  v_az uuid;
  v_tx_az1 uuid;
  v_tx_az2 uuid;
  c public.comprovantes;
  v_r2 jsonb;
  v_p jsonb;
  v_lig jsonb;
  v_t2 uuid := pg_temp._tx('T2');
begin
  -- T15: PESSOAL pago no cartão (lido): só registra
  perform pg_temp._livrar();
  insert into public.cnpj_consultas (cnpj, encontrado, razao_social, nome_fantasia, consultado_em)
  values (v_cnpj, true, v_loja || ' LTDA', v_loja, now()) on conflict (cnpj) do nothing;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val, 'fonte', 'credit_card', 'descricao', v_loja, 'loja', v_loja));
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'credito', 'cnpj', v_cnpj, 'destino', 'pessoal'))->>'id')::uuid;
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c from public.comprovantes where id = v_cmp;
  v_p := public.comprovante_banco_proxima(pg_temp._phone(), 'cmp', v_cmp);
  v_lig := public._comprovante_ligar(v_cmp, v_tx, 'sim', 'verde', pg_temp._dono(), true);

  -- T16: um CMP azul com pergunta (candidatas reservadas) + o ligado do T2
  v_val := pg_temp._val();
  v_az := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_tx_az1 := pg_temp._linha(jsonb_build_object('valor', v_val));
  v_tx_az2 := pg_temp._linha(jsonb_build_object('valor', v_val, 'data', pg_temp._hoje() + 1));
  perform public.comprovantes_reavaliar_banco('teste', null);
  v_r2 := public.comprovantes_linhas_da_conciliacao(null);
  insert into _resultado values ('T15 PESSOAL só registra: candidatos guardados, nunca pergunta, nunca liga, nada reservado',
    c.situacao = 'gravado' and c.banco_so_registro and c.banco_regra = 'credito'
    and jsonb_array_length(c.banco_candidatos) = 1 and c.banco_candidatos->0->>'id' = v_tx::text
    and not c.banco_perguntar and c.bank_transaction_id is null
    and v_p->>'motivo' = 'nao_pergunta' and v_lig->>'motivo' = 'so_registro'
    and public._comprovante_banco_resumo(c)->>'estado' = 'so_registro'
    and not exists (select 1 from jsonb_array_elements(v_r2->'linhas') l where l->>'bank_transaction_id' = v_tx::text),
    'situacao=' || c.situacao || ' so_registro=' || c.banco_so_registro || ' p=' || coalesce(v_p->>'motivo', '-') || ' lig=' || coalesce(v_lig->>'motivo', '-'));
  insert into _resultado values ('T16 R2: ligadas + candidatas com pergunta (nunca o PESSOAL) + as anotações dos CMPs',
    exists (select 1 from jsonb_array_elements(v_r2->'linhas') l where l->>'bank_transaction_id' = v_t2::text and l->>'papel' = 'ligada')
    and exists (select 1 from jsonb_array_elements(v_r2->'linhas') l where l->>'bank_transaction_id' = v_tx_az1::text and l->>'papel' = 'candidata')
    and exists (select 1 from jsonb_array_elements(v_r2->'linhas') l where l->>'bank_transaction_id' = v_tx_az2::text and l->>'papel' = 'candidata')
    and v_r2->'anotacoes' @> to_jsonb((select anotacao_id from public.comprovantes where id = pg_temp._id('T2'))::text)
    and jsonb_array_length(public.comprovantes_linhas_da_conciliacao(array[v_tx_az1])->'linhas') = 1,
    'linhas=' || jsonb_array_length(v_r2->'linhas') || ' anotacoes=' || jsonb_array_length(v_r2->'anotacoes'));
  update public.comprovantes set banco_recusados = array[v_tx_az1, v_tx_az2], banco_perguntar = false where id = v_az;
exception when others then
  insert into _resultado values ('T15/T16 PESSOAL e linhas reservadas', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T17 / T18 ═══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  v_tx uuid;
  v_tx2 uuid;
  p jsonb;
  r jsonb;
  p18 jsonb;
  r18 jsonb;
  c record;
  v_cmp18 uuid;
begin
  -- T17: a pergunta verde saiu; chegou outra linha igual → o "sim" vira "mudou" e a pergunta nova é azul
  perform pg_temp._livrar();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val));
  perform public.comprovantes_reavaliar_banco('teste', null);
  p := pg_temp._banco(v_cmp);
  v_tx2 := pg_temp._linha(jsonb_build_object('valor', v_val, 'data', pg_temp._hoje() + 1));
  r := pg_temp._resp(p, '{"tipo":"sim"}'::jsonb);
  select * into c from public.comprovantes where id = v_cmp;
  insert into _resultado values ('T17 as linhas mudaram desde a pergunta: "mudou" e a pergunta nova (azul), nada ligado',
    p->'banco'->>'nivel' = 'verde' and r->>'resultado' = 'mudou' and r->'proxima'->'banco'->>'nivel' = 'azul'
    and jsonb_array_length(r->'proxima'->'opcoes') = 3 and c.bank_transaction_id is null
    and (select status from public.whatsapp_perguntas where id = (p->>'pergunta_id')::uuid) = 'substituida',
    'p=' || coalesce(p->'banco'->>'nivel', '-') || ' r=' || coalesce(r->>'resultado', '-') || ' nova=' || coalesce(r->'proxima'->'banco'->>'nivel', '-'));

  -- T18: a resposta é de antes de a pergunta sair → inválida, nada muda, a pergunta continua
  perform pg_temp._livrar();
  v_val := pg_temp._val();
  v_cmp18 := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  perform pg_temp._linha(jsonb_build_object('valor', v_val));
  perform public.comprovantes_reavaliar_banco('teste', null);
  p18 := pg_temp._banco(v_cmp18);
  r18 := pg_temp._resp(p18, '{"tipo":"sim"}'::jsonb, true);
  select * into c from public.comprovantes where id = v_cmp18;
  insert into _resultado values ('T18 resposta mandada antes da pergunta: inválida, nada muda, a pergunta continua',
    r18->>'resultado' = 'invalida' and r18->>'motivo' = 'resposta_anterior_a_pergunta' and c.bank_transaction_id is null
    and c.situacao = 'aguardando_banco' and r18->'proxima'->>'pergunta_id' = p18->>'pergunta_id'
    and (select status from public.whatsapp_perguntas where id = (p18->>'pergunta_id')::uuid) = 'aberta',
    'r=' || coalesce(r18->>'resultado', '-') || '/' || coalesce(r18->>'motivo', '-'));
exception when others then
  insert into _resultado values ('T17/T18 linhas que mudam e resposta velha', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T19 / T20 / T21 / T22 (as regras que a simulação de 11/10/2026 mandou mudar) ════════════
do $$
declare
  v_val numeric;
  v_cmp uuid;
  v_forte uuid;
  v_fraca uuid;
  v_r2 jsonb;
  c public.comprovantes;
  av19 jsonb;
  v_detalhe text;
begin
  -- T19: débito com a forte (DEBITO DE CARTAO, sem nome) e outra do mesmo valor na janela com o
  -- descritor cortado (fraca: nome diferente) → AZUL, a forte em 1 (o dono vê as duas); só a forte
  -- fica reservada do "lançar sozinho"
  perform pg_temp._livrar();
  v_val := pg_temp._val();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_forte := pg_temp._linha(jsonb_build_object('valor', v_val));
  v_fraca := pg_temp._linha(jsonb_build_object('valor', v_val, 'data', pg_temp._hoje() + 1, 'descricao', 'AZ BALNEARIO', 'nome', 'AZ BALNEARIO'));
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c from public.comprovantes where id = v_cmp;
  av19 := public._comprovante_candidatos(c);
  v_r2 := public.comprovantes_linhas_da_conciliacao(array[v_forte, v_fraca]);
  v_detalhe := 'nivel=' || coalesce(av19->>'nivel', '-') || ' linhas=' || coalesce(jsonb_array_length(av19->'linhas'), -1)
    || ' guardado=' || coalesce(c.conciliacao, '-') || ' perguntar=' || c.banco_perguntar || ' r2=' || coalesce(v_r2->>'linhas', '-');
  insert into _resultado values ('T19 débito: a forte com outra linha do mesmo valor na janela é azul (a forte em 1); só a forte fica reservada',
    av19->>'nivel' = 'azul' and jsonb_array_length(av19->'linhas') = 2 and av19->'linhas'->0->>'id' = v_forte::text
    and (av19->'linhas'->0->>'forte')::boolean and not (av19->'linhas'->1->>'forte')::boolean
    and av19->'linhas'->1->'motivos' ? 'nome_diferente'
    and c.conciliacao = 'azul' and c.banco_perguntar
    and exists (select 1 from jsonb_array_elements(v_r2->'linhas') l where l->>'bank_transaction_id' = v_forte::text and l->>'papel' = 'candidata')
    and not exists (select 1 from jsonb_array_elements(v_r2->'linhas') l where l->>'bank_transaction_id' = v_fraca::text),
    v_detalhe);
  update public.comprovantes set banco_recusados = array[v_forte, v_fraca], banco_perguntar = false where id = v_cmp;
exception when others then
  insert into _resultado values ('T19 débito: a forte com outra linha do mesmo valor na janela é azul (a forte em 1); só a forte fica reservada', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_val numeric := pg_temp._val();
  v_cnpj_loja text := pg_temp._cnpj();
  v_cnpj_inter text := pg_temp._cnpj();
  v_inter uuid;
  v_principal uuid;
  v_mc uuid;
  v_cinza uuid;
  c public.comprovantes;
  ci public.comprovantes;
  av20a jsonb;
  av20b jsonb;
begin
  -- T20: o cupom (CNPJ do EMITENTE) pago no Pix da maquininha: a linha do Pix vai ao CNPJ do
  -- intermediador — fica como candidata fraca (outro_documento), nunca de fora; o plano espera a linha
  -- (nada de anotar com o CNPJ da loja, que nunca casaria)
  perform pg_temp._livrar();
  v_inter := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX', 'doc', v_cnpj_inter,
                                               'nome', 'MAQUININHA TESTE'));
  v_principal := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'pix', 'cnpj', v_cnpj_loja))->>'id')::uuid;
  select * into c from public.comprovantes where id = v_principal;
  av20a := public._comprovante_candidatos(c);
  -- o comprovante do Pix da mesma compra (favorecido = o intermediador), guardado como "a mesma compra":
  -- o principal passa a usar o documento de quem recebeu e a linha vira forte (verde)
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized, tipo_whatsapp,
                                   recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca, data_compra, lido_em,
                                   favorecido_doc, mesma_compra_de)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(), 'TESTE-F3-' || gen_random_uuid(),
          pg_temp._phone(), 'image', now(), md5(random()::text || 'mc') || md5(clock_timestamp()::text || 'mc'), 'pix', 'alta', v_val, 'alta',
          pg_temp._hoje(), now(), v_cnpj_inter, v_principal)
  returning id into v_mc;
  av20b := public._comprovante_candidatos(c);
  -- o mesmo cupom pago no Pix, sem linha nenhuma ainda (cinza): espera a linha, não anota
  v_cinza := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  select * into ci from public.comprovantes where id = v_cinza;
  insert into _resultado values ('T20 cupom pago no Pix da maquininha: a linha do intermediador fica (fraca, azul) e o plano espera a linha; o Pix da mesma compra dá o documento (verde)',
    av20a->>'nivel' = 'azul' and jsonb_array_length(av20a->'linhas') = 1 and av20a->'linhas'->0->>'id' = v_inter::text
    and av20a->'linhas'->0->'motivos' ? 'outro_documento' and not (av20a->'linhas'->0->>'forte')::boolean
    and pg_temp._tipos(c.efeitos) = 'aguardar_banco' and c.anotacao_id is null
    and av20b->>'nivel' = 'verde' and av20b->'linhas'->0->'motivos' ? 'documento' and (av20b->'linhas'->0->>'forte')::boolean
    and pg_temp._tipos(ci.efeitos) = 'aguardar_banco' and ci.anotacao_id is null and ci.situacao = 'aguardando_banco',
    'a=' || coalesce(av20a->>'nivel', '-') || ' efeitos=' || pg_temp._tipos(c.efeitos) || ' b=' || coalesce(av20b->>'nivel', '-')
    || ' cinza=' || pg_temp._tipos(ci.efeitos) || '/' || ci.situacao);
  update public.comprovantes set banco_recusados = array[v_inter], banco_perguntar = false where id = v_principal;
exception when others then
  insert into _resultado values ('T20 cupom pago no Pix da maquininha: a linha do intermediador fica (fraca, azul) e o plano espera a linha; o Pix da mesma compra dá o documento (verde)', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  v_disp uuid;
  v_boa uuid;
  c public.comprovantes;
  av21 jsonb;
  p jsonb;
  r jsonb;
  c2 record;
begin
  -- T21: a linha dispensada da fila ("lançada em dobro") nunca é candidata; a ligada que o dono dispensa
  -- depois no Extrato é desligada (sem ir para as recusadas: dispensada não volta como candidata)
  perform pg_temp._livrar();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_disp := pg_temp._linha(jsonb_build_object('valor', v_val));
  update public.bank_transactions set dismissed_kind = 'manual', dismissed_reason = 'lançada em dobro (teste F3)', dismissed_at = now()
   where id = v_disp;
  v_boa := pg_temp._linha(jsonb_build_object('valor', v_val, 'data', pg_temp._hoje() + 1));
  perform pg_temp._proposta(v_boa);
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c from public.comprovantes where id = v_cmp;
  av21 := public._comprovante_candidatos(c);
  p := pg_temp._banco(v_cmp);
  r := pg_temp._resp(p, '{"tipo":"sim"}'::jsonb);
  update public.bank_transactions set dismissed_kind = 'duplicata', dismissed_reason = 'duplicata (teste F3)', dismissed_at = now()
   where id = v_boa;
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c2 from public.comprovantes where id = v_cmp;
  insert into _resultado values ('T21 linha dispensada nunca é candidata; a ligada que o dono dispensa depois é desligada (sem recusar)',
    av21->>'nivel' = 'verde' and jsonb_array_length(av21->'linhas') = 1 and av21->'linhas'->0->>'id' = v_boa::text
    and r->>'resultado' = 'ligado'
    and c2.situacao = 'aguardando_banco' and c2.bank_transaction_id is null and not (v_boa = any (c2.banco_recusados))
    and exists (select 1 from jsonb_array_elements(c2.efeitos) e
                 where e->>'tipo' = 'ligar_linha' and e->>'desligado_motivo' = 'linha_dispensada')
    and c2.conciliacao = 'cinza',
    'antes=' || coalesce(av21->>'nivel', '-') || '/' || coalesce(jsonb_array_length(av21->'linhas'), -1) || ' r=' || coalesce(r->>'resultado', '-')
    || ' depois=' || c2.situacao || '/' || coalesce(c2.conciliacao, '-'));
exception when others then
  insert into _resultado values ('T21 linha dispensada nunca é candidata; a ligada que o dono dispensa depois é desligada (sem recusar)', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_val numeric := pg_temp._val();
  v_cnpj text := pg_temp._cnpj();
  v_loja text := 'LOJA JANELA F3 ' || pg_temp._letras(5);
  v_cmp uuid;
  v_d4 uuid;
  v_d8 uuid;
  c public.comprovantes;
  av22 jsonb;
begin
  -- T22: crédito — o cartão data a linha na compra: a busca vai até D+5 (D+4 entra, fraca: fora do D+3
  -- do verde); D+8 fica de fora. Os 45 dias do crédito são só a espera antes do abandono (T12).
  perform pg_temp._livrar();
  insert into public.cnpj_consultas (cnpj, encontrado, razao_social, nome_fantasia, consultado_em)
  values (v_cnpj, true, v_loja || ' LTDA', v_loja, now()) on conflict (cnpj) do nothing;
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'credito', 'cnpj', v_cnpj))->>'id')::uuid;
  v_d4 := pg_temp._linha(jsonb_build_object('valor', v_val, 'fonte', 'credit_card', 'descricao', v_loja, 'loja', v_loja, 'data', pg_temp._hoje() + 4));
  v_d8 := pg_temp._linha(jsonb_build_object('valor', v_val, 'fonte', 'credit_card', 'descricao', v_loja, 'loja', v_loja, 'data', pg_temp._hoje() + 8));
  select * into c from public.comprovantes where id = v_cmp;
  av22 := public._comprovante_candidatos(c);
  insert into _resultado values ('T22 crédito: a busca vai até D+5 (D+4 entra, fraca); D+8 fica de fora',
    av22->>'nivel' = 'azul' and jsonb_array_length(av22->'linhas') = 1 and av22->'linhas'->0->>'id' = v_d4::text
    and not (av22->'linhas'->0->>'forte')::boolean and av22->'linhas'->0->'motivos' ? 'dias:4'
    and coalesce((av22->>'mais')::integer, -1) = 0,
    'nivel=' || coalesce(av22->>'nivel', '-') || ' linhas=' || coalesce(jsonb_array_length(av22->'linhas'), -1));
  update public.comprovantes set banco_recusados = array[v_d4, v_d8], banco_perguntar = false where id = v_cmp;
exception when others then
  insert into _resultado values ('T22 crédito: a busca vai até D+5 (D+4 entra, fraca); D+8 fica de fora', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T23 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  v_tx uuid;
  p jsonb;
  v_ceder jsonb;
  v_de_novo jsonb;
  w record;
  c record;
begin
  -- R10: chegou comprovante novo do dono e a pergunta aberta é a do extrato: ela cede a vez (fecha
  -- "substituida"; o CMP continua com a pergunta a fazer, o vigia volta a ela depois)
  perform pg_temp._livrar();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val));
  perform public.comprovantes_reavaliar_banco('teste', null);
  p := pg_temp._banco(v_cmp);
  v_ceder := public.comprovante_banco_ceder(pg_temp._phone());
  v_de_novo := public.comprovante_banco_ceder(pg_temp._phone());
  select status, motivo into w from public.whatsapp_perguntas where id = (p->>'pergunta_id')::uuid;
  select * into c from public.comprovantes where id = v_cmp;
  insert into _resultado values ('T23 R10: a pergunta do extrato aberta cede a vez ao comprovante novo; sem ela, nada',
    p->>'perguntou' = 'true' and (v_ceder->>'cedeu')::boolean and v_ceder->>'codigo' = c.codigo
    and w.status = 'substituida' and w.motivo = 'cmp_novo' and c.banco_perguntar and c.situacao = 'aguardando_banco'
    and not (v_de_novo->>'cedeu')::boolean,
    'ceder=' || coalesce(v_ceder::text, '-') || ' pergunta=' || coalesce(w.status, '-') || '/' || coalesce(w.motivo, '-')
    || ' de_novo=' || coalesce(v_de_novo->>'cedeu', '-'));
  update public.comprovantes set banco_recusados = array[v_tx], banco_perguntar = false where id = v_cmp;
exception when others then
  insert into _resultado values ('T23 R10: a pergunta do extrato aberta cede a vez ao comprovante novo; sem ela, nada', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T24 (por último: passa por todos os CMPs dos testes anteriores) ═════════════════════════
do $$
declare
  v_antes text;
  v_depois text;
  v_fila_antes text;
  v_fila_depois text;
  v_perg_antes text;
  v_perg_depois text;
  v_m jsonb;
  i integer;
begin
  -- a varredura roda a cada 2 min (cron) e em cada finance-review: sem linha nova, nenhuma versão nova
  -- de linha (o ctid muda a cada UPDATE) nos comprovantes, na fila do Extrato nem nas perguntas.
  -- Duas rodadas antes: a disputa (T11) propaga numa rodada.
  perform public.comprovantes_reavaliar_banco('teste', null);
  perform public.comprovantes_reavaliar_banco('teste', null);
  select string_agg(ctid::text, ',' order by id) into v_antes from public.comprovantes;
  select string_agg(ctid::text, ',' order by id) into v_fila_antes from public.finance_review_queue;
  select string_agg(ctid::text, ',' order by id) into v_perg_antes from public.whatsapp_perguntas;
  for i in 1..10 loop
    perform public.comprovantes_reavaliar_banco('teste', null);
  end loop;
  -- a da manutenção do cron: não calcula as reservadas nem a lista do vigia (ninguém usa)
  v_m := public._comprovantes_banco_varrer(20, 'manutencao');
  select string_agg(ctid::text, ',' order by id) into v_depois from public.comprovantes;
  select string_agg(ctid::text, ',' order by id) into v_fila_depois from public.finance_review_queue;
  select string_agg(ctid::text, ',' order by id) into v_perg_depois from public.whatsapp_perguntas;
  insert into _resultado values ('T24 10 rodadas da varredura sem linha nova: nenhum UPDATE; a da manutenção não calcula as reservadas',
    v_antes = v_depois and v_fila_antes is not distinct from v_fila_depois and v_perg_antes is not distinct from v_perg_depois
    and v_m->'reservadas' = '[]'::jsonb and v_m->'perguntar' = '[]'::jsonb and not (v_m->>'ocupada')::boolean,
    'comprovantes=' || case when v_antes = v_depois then 'iguais' else 'MUDARAM' end
    || ' fila=' || case when v_fila_antes is not distinct from v_fila_depois then 'iguais' else 'MUDARAM' end
    || ' perguntas=' || case when v_perg_antes is not distinct from v_perg_depois then 'iguais' else 'MUDARAM' end
    || ' manutencao=' || coalesce(v_m->>'reservadas', '-'));
exception when others then
  insert into _resultado values ('T24 10 rodadas da varredura sem linha nova: nenhum UPDATE; a da manutenção não calcula as reservadas', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
