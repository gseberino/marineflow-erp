-- Prova: conciliação dos comprovantes com o extrato (migrations 20261011300000-304000 e 400000; usa a F1 e a F2).
--
--   T1  grants: R1-R10 só service_role; helpers para ninguém; tabelas novas fechadas ao anon
--   T2  débito único sem nome → verde → "sim" liga: proposta classificada (anotação criada e aplicada,
--       evidencia.anotacao), a loja do CMP na linha (nome_pelo_comprovante) e no extrato_da_conta
--   T3  dois débitos iguais → azul 1/2/0 → a escolha 2 liga a segunda
--   T4  "0" → as listadas vão para banco_recusados; a próxima avaliação fica cinza
--   T5  Pix com CNPJ: a linha do mesmo CNPJ é verde; a de outro CNPJ fica de fora
--   T6  Pix com CPF mascarado → azul (cpf_parcial); CPF com outros finais fica de fora
--   T7  crédito: à vista com nome igual em D+0 verde; nome diferente azul; parcela 1/3 azul com o total
--   T8  a linha já virou lançamento → anexa; só preenche o vazio (resposta 8 do dono): categoria diferente
--       fica (aviso); a vazia é preenchida e o cancelar a devolve vazia; nada a aprovar
--   T9  CMP com conta a pagar em aberto → o "sim" casa (conciliar_lancamento) e a proposta sai da fila
--   T10 a anotação da F2 aplicada pelo aplicar_anotacoes_pendentes → R1 liga sem pergunta
--   T11 linha forte de dois CMPs → azul nos dois (disputada)
--   T12 abandono em 30 dias (45 no crédito) + pendência "classificar no Extrato"
--   T13 re-validação: valor mudou → desliga; proposta recusada → desliga e recusa a linha
--   T14 vigia: horário seg–sáb 08–20, espaçamento de 4 h, 3 tentativas, a fila da F2 primeiro; conversa
--       desligada → nada perguntado, candidatos guardados
--   T15 PESSOAL pago pela empresa procura e liga como qualquer compra; o do bolso não procura (resposta 1)
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
--   (ajustes do dono, 11/10/2026)
--   T25 o SIM já aprova a linha: a ligação classificada devolve "aprovar"; R12 grava o lançamento; cancelar o
--       CMP desfaz a aprovação (desfazer_aprovacao) e a linha volta à fila; no mês fechado, recusa
--   T26 regra E: 5 dias sem aparecer em conta nenhuma → "quem pagou?" (4 dias, a linha em outra conta, ou uma
--       conta com o extrato atrasado, não); "a empresa" só marca; "eu" refaz como reembolso ao sócio (e a
--       anotação do dono que dizia "a empresa paga" sai); o técnico com diária, crédito nas Diárias; "pessoal"
--       tira o custo interno da OS e vai para PESSOAL; bloqueio = nada muda; a compra que aparece depois na
--       conta da empresa = pendência "conferir quem pagou" e a linha reservada (nunca ligada sozinha)
--   (revisão dos ajustes, 11/10/2026)
--   T27 a aprovação do SIM que o dono desfez no Extrato nunca é refeita sozinha: pendência "classificar no
--       Extrato"; a nova aprovação do dono é adotada (e o cancelamento do CMP recusa)
--   (conta sem movimento, 11/10/2026)
--   T28 a conta parada que sincroniza bem (ok, UPDATED, importada, o Pluggy no banco depois de D+5; D+13 no
--       cartão) não segura o "quem pagou?"; manual, com erro, OUTDATED, cedo ou não importada, segura
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
-- destino (insumo), cnpj (emitente), favorecido, fornecedor, os, tipo_na_os, quem, pagador, categoria,
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
         tipo_na_os = p->>'tipo_na_os', quem_pagou = p->>'quem', pagador_payee_id = nullif(p->>'pagador', '')::uuid,
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
    'public.comprovante_indice_pessoal_falhou(date, text)', 'public.comprovante_banco_ceder(text)',
    'public.comprovante_a_aprovar(uuid)', 'public.comprovante_aprovado(uuid, uuid, uuid)'] loop
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
    'public._comprovante_banco_abrir(uuid, text)', 'public._comprovantes_indice_pessoal_marcar()',
    'public._comprovante_a_aprovar(public.comprovantes)', 'public._comprovante_quem_pode(public.comprovantes)',
    'public._comprovante_aparece_em_alguma_conta(public.comprovantes)', 'public._comprovante_desfazer(public.comprovantes, text, text, uuid)',
    'public._comprovante_trocar_pagador(uuid, text, uuid, uuid)', 'public._diarias_dividir(uuid, uuid[], uuid, uuid)'] loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute')
       or has_function_privilege('service_role', v_f, 'execute') then
      v_ruins := v_ruins || v_f;
    end if;
  end loop;
  if has_table_privilege('anon', 'public.diarias_reembolsos', 'select') or has_table_privilege('authenticated', 'public.diarias_reembolsos', 'insert')
     or has_table_privilege('anon', 'public.comprovantes_indice_pessoal', 'select')
     or has_table_privilege('authenticated', 'public.comprovantes_indice_pessoal', 'insert')
     or has_column_privilege('anon', 'public.comprovantes', 'banco_candidatos', 'select')
     or has_table_privilege('anon', 'public.diarias_pagamentos_divididos', 'select')
     or has_table_privilege('authenticated', 'public.diarias_pagamentos_divididos', 'insert') then
    v_ruins := v_ruins || 'tabelas'::text;
  end if;
  insert into _resultado values ('T1 grants: R1-R12 só service_role, helpers para ninguém, tabelas novas fechadas',
    cardinality(v_ruins) = 0, array_to_string(v_ruins, ', '));
exception when others then
  insert into _resultado values ('T1 grants: R1-R12 só service_role, helpers para ninguém, tabelas novas fechadas', false,
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
    and r->'cmp'->'banco'->>'estado' = 'ligado'
    -- resposta 3 do dono: o SIM já aprova (o finance-review aprova esta proposta, a classificada)
    and r->'aprovar'->>'proposta_id' = v_q::text and public.comprovante_a_aprovar(v_cmp)->>'proposta_id' = v_q::text,
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
  v_cmp8b uuid;
  v_tx8b uuid;
  v_pay8b uuid;
  p8b jsonb;
  r8b jsonb;
  v_cat8b text;
  v_canc8b jsonb;
begin
  -- T8: a linha já virou lançamento (Outras despesas): o "sim" anexa, NÃO troca a categoria (avisa) e não
  -- há o que aprovar; (b) o lançamento sem categoria ganha a do CMP e o cancelar a devolve vazia
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
  -- (b) a linha com o lançamento sem categoria
  v_val := pg_temp._val();
  v_cmp8b := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_tx8b := pg_temp._linha(jsonb_build_object('valor', v_val));
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               bank_transaction_id, origin)
  values ('Débito sem categoria F3', pg_temp._hoje(), pg_temp._hoje(), v_val, v_val, 0, 'paid', null, v_tx8b, 'manual')
  returning id into v_pay8b;
  perform public.comprovantes_reavaliar_banco('teste', null);
  p8b := pg_temp._banco(v_cmp8b);
  r8b := pg_temp._resp(p8b, '{"tipo":"sim"}'::jsonb);
  select expense_category into v_cat8b from public.payables where id = v_pay8b;
  v_canc8b := public.comprovante_cancelar(v_cmp8b, 'teste do T8', pg_temp._dono());
  insert into _resultado values ('T8 a linha já virou lançamento: o "sim" anexa e só preenche o vazio (categoria diferente fica, com aviso); nada a aprovar',
    p->'banco'->'linhas'->0->>'acao' = 'anexar' and r->>'resultado' = 'ligado' and r->'ligacao'->>'como' = 'anexou'
    and c.payable_id = v_pay and pay.expense_category = 'Outras despesas'
    and not coalesce(r->'ligacao'->'corrigido' ? 'expense_category', false)
    and r->>'motivo' = 'categoria_existente_diferente' and r->'ligacao'->>'categoria_existente' = 'Outras despesas'
    and c.linha_explicada_em is not null and r->'aprovar' = 'null'::jsonb
    and r8b->>'resultado' = 'ligado' and v_cat8b = 'Materiais e Insumos Operacionais'
    and r8b->'ligacao'->'corrigido'->'expense_category'->>'depois' = 'Materiais e Insumos Operacionais'
    and (v_canc8b->>'ok')::boolean and (select expense_category from public.payables where id = v_pay8b) is null,
    'acao=' || coalesce(p->'banco'->'linhas'->0->>'acao', '-') || ' r=' || coalesce(r->>'resultado', '-') || '/' || coalesce(r->'ligacao'->>'como', r->>'motivo', '-')
    || ' cat=' || coalesce(pay.expense_category, '-') || ' aviso=' || coalesce(r->>'motivo', '-')
    || ' vazio=' || coalesce(v_cat8b, 'null') || '→' || coalesce((select expense_category from public.payables where id = v_pay8b), 'null'));

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
    and (v_r1->>'ligados')::integer >= 1
    -- resposta 3: a anotação que o SIM do resumo autorizou classificou a linha → a varredura manda aprovar
    and v_r1->'aprovar' @> jsonb_build_array(jsonb_build_object('cmp_id', v_cmp::text, 'proposta_id', v_q::text,
                                                                'autor', pg_temp._dono()::text)),
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
  v_tx_emp uuid;
  g_emp jsonb;
  c_emp public.comprovantes;
begin
  -- T15: PESSOAL pago no cartão. Da EMPRESA (resposta 1): procura e liga como qualquer compra (gasto pessoal
  -- do sócio); do bolso: não procura (nada guardado, nunca pergunta, nunca liga)
  perform pg_temp._livrar();
  insert into public.cnpj_consultas (cnpj, encontrado, razao_social, nome_fantasia, consultado_em)
  values (v_cnpj, true, v_loja || ' LTDA', v_loja, now()) on conflict (cnpj) do nothing;
  v_tx_emp := pg_temp._linha(jsonb_build_object('valor', v_val, 'fonte', 'credit_card', 'descricao', v_loja, 'loja', v_loja));
  g_emp := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'credito', 'cnpj', v_cnpj, 'destino', 'pessoal', 'quem', 'empresa'));
  select * into c_emp from public.comprovantes where id = (g_emp->>'id')::uuid;
  v_val := pg_temp._val();
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val, 'fonte', 'credit_card', 'descricao', v_loja, 'loja', v_loja));
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'credito', 'cnpj', v_cnpj, 'destino', 'pessoal', 'quem', 'socio'))->>'id')::uuid;
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
  insert into _resultado values ('T15 PESSOAL da empresa procura e liga (gasto pessoal do sócio); o do bolso não procura, nunca pergunta, nunca liga',
    g_emp->>'resultado' = 'gravado' and c_emp.situacao = 'conciliado' and c_emp.bank_transaction_id = v_tx_emp
    and c_emp.banco_regra = 'credito' and c_emp.categoria = 'Gasto Pessoal Sócio - Descontar PL' and c_emp.destino = 'pessoal'
    and c.situacao = 'gravado' and c.banco_regra is null
    and jsonb_array_length(c.banco_candidatos) = 0 and not c.banco_perguntar and c.bank_transaction_id is null
    and v_p->>'motivo' = 'nao_pergunta' and v_lig->>'motivo' = 'situacao'
    and public._comprovante_banco_resumo(c) is null
    and not exists (select 1 from jsonb_array_elements(v_r2->'linhas') l where l->>'bank_transaction_id' = v_tx::text),
    'empresa=' || coalesce(c_emp.situacao, '-') || '/' || coalesce(c_emp.categoria, '-') || ' bolso=' || c.situacao
    || ' p=' || coalesce(v_p->>'motivo', '-') || ' lig=' || coalesce(v_lig->>'motivo', '-'));
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

-- ═══ T25: o SIM já aprova a linha (resposta 3 do dono, 11/10/2026) ═════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  v_tx uuid;
  v_q uuid;
  v_pay uuid;
  p jsonb;
  r jsonb;
  v_a11 jsonb;
  v_r12 jsonb;
  v_r12b jsonb;
  v_r12x jsonb;
  c record;
  v_canc jsonb;
  c2 record;
  v_chamou boolean;
  v_dubla boolean := to_regclass('public.ensaio_chamadas') is not null;
  -- mês fechado
  v_dia_velho date := (date_trunc('month', now() - interval '25 years') + interval '14 days')::date;
  v_val2 numeric := pg_temp._val();
  v_cmp2 uuid;
  v_tx2 uuid;
  v_q2 uuid;
  v_pay2 uuid;
  v_canc2 jsonb;
begin
  perform pg_temp._livrar();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val));
  v_q := pg_temp._proposta(v_tx);
  perform public.comprovantes_reavaliar_banco('teste', null);
  p := pg_temp._banco(v_cmp);
  r := pg_temp._resp(p, '{"tipo":"sim"}'::jsonb);
  v_a11 := public.comprovante_a_aprovar(v_cmp);
  -- o que o finance-review faz ao aprovar (a rota da tela): o lançamento na linha e a proposta aprovada
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               bank_transaction_id, origin)
  values ('Aprovado pelo SIM (teste F3)', pg_temp._hoje(), pg_temp._hoje(), v_val, v_val, 0, 'paid', 'Materiais e Insumos Operacionais',
          v_tx, 'bank_reconciliation')
  returning id into v_pay;
  update public.finance_review_queue set status = 'approved', created_payable_id = v_pay, decided_by = pg_temp._dono(), decided_at = now()
   where id = v_q;
  -- R12 errado (outra proposta) recusa; o certo grava; de novo é idempotente
  v_r12x := public.comprovante_aprovado(v_cmp, gen_random_uuid(), v_pay);
  v_r12 := public.comprovante_aprovado(v_cmp, v_q, v_pay);
  v_r12b := public.comprovante_aprovado(v_cmp, v_q, v_pay);
  -- a varredura não acha mais o que aprovar e não marca "lançado depois" (o lançamento é o do CMP)
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c from public.comprovantes where id = v_cmp;
  -- cancelar o CMP desfaz a aprovação pela rota da tela e a linha volta para a fila
  v_canc := public.comprovante_cancelar(v_cmp, 'era outra compra', pg_temp._dono());
  select * into c2 from public.comprovantes where id = v_cmp;
  if v_dubla then
    execute 'select exists (select 1 from public.ensaio_chamadas where rota = ''desfazer_aprovacao'' and args->>''id'' = $1)'
      into v_chamou using v_pay::text;
  end if;
  -- no mês fechado, o cancelamento do aprovado recusa (nada muda)
  v_cmp2 := (pg_temp._cmp(jsonb_build_object('valor', v_val2, 'forma', 'debito', 'cnpj', pg_temp._cnpj(), 'data', v_dia_velho))->>'id')::uuid;
  v_tx2 := pg_temp._linha(jsonb_build_object('valor', v_val2, 'data', v_dia_velho));
  v_q2 := pg_temp._proposta(v_tx2);
  perform public.comprovantes_reavaliar_banco('teste', null);
  r := pg_temp._resp(pg_temp._banco(v_cmp2), '{"tipo":"sim"}'::jsonb);
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               bank_transaction_id, origin)
  values ('Aprovado pelo SIM no mês velho (teste F3)', v_dia_velho, v_dia_velho, v_val2, v_val2, 0, 'paid', 'Materiais e Insumos Operacionais',
          v_tx2, 'bank_reconciliation')
  returning id into v_pay2;
  update public.finance_review_queue set status = 'approved', created_payable_id = v_pay2, decided_by = pg_temp._dono(), decided_at = now()
   where id = v_q2;
  perform public.comprovante_aprovado(v_cmp2, v_q2, v_pay2);
  insert into public.periodos_fechados (ano, mes) values (extract(year from v_dia_velho)::int, extract(month from v_dia_velho)::int);
  v_canc2 := public.comprovante_cancelar(v_cmp2, 'quero desfazer', pg_temp._dono());
  insert into _resultado values ('T25 o SIM aprova: R11 diz a proposta, R12 grava o lançamento (idempotente); cancelar desfaz a aprovação; mês fechado recusa',
    r is not null and v_a11->>'proposta_id' = v_q::text and v_a11->>'autor' = pg_temp._dono()::text
    and not (v_r12x->>'ok')::boolean and (v_r12->>'ok')::boolean and not (v_r12->>'ja_estava')::boolean
    and (v_r12b->>'ok')::boolean and (v_r12b->>'ja_estava')::boolean
    and c.payable_id = v_pay and c.situacao = 'conciliado'
    and exists (select 1 from jsonb_array_elements(c.efeitos) e
                 where e->>'tipo' = 'ligar_linha' and e->'aprovado'->>'payable_id' = v_pay::text
                   and not coalesce((e->>'lancado_depois')::boolean, false))
    and public.comprovante_a_aprovar(v_cmp) is null
    and (v_canc->>'ok')::boolean and c2.situacao = 'cancelado'
    and v_canc->'desfeitos' @> '[{"tipo": "ligar_linha", "aprovado": true}]'::jsonb
    and not exists (select 1 from public.payables x where x.bank_transaction_id = v_tx and x.status <> 'cancelled')
    and (not v_dubla or (v_chamou and (select status from public.finance_review_queue where id = v_q) = 'pending'))
    and not (v_canc2->>'ok')::boolean and v_canc2->'bloqueios'->0->>'motivo' = 'mes_fechado'
    and (select status from public.payables where id = v_pay2) = 'paid',
    'a11=' || coalesce(v_a11->>'proposta_id' = v_q::text, false) || ' r12=' || coalesce(v_r12->>'ok', '-') || '/' || coalesce(v_r12b->>'ja_estava', '-')
    || ' cancelar=' || coalesce(v_canc->>'ok', v_canc->'bloqueios'->0->>'motivo', '-')
    || ' mes_fechado=' || coalesce(v_canc2->'bloqueios'->0->>'motivo', v_canc2->>'ok', '-'));
  delete from public.periodos_fechados where ano = extract(year from v_dia_velho)::int and mes = extract(month from v_dia_velho)::int;
exception when others then
  insert into _resultado values ('T25 o SIM aprova: R11 diz a proposta, R12 grava o lançamento (idempotente); cancelar desfaz a aprovação; mês fechado recusa', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T27: a aprovação do SIM que o dono desfez no Extrato fica desfeita (revisão dos ajustes, 11/10/2026) ═══
do $$
declare
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  v_tx uuid;
  v_q uuid;
  v_pay uuid;
  v_pay2 uuid;
  v_r1 jsonb;
  v_r1b jsonb;
  v_status_q text;
  v_ctid_antes text;
  v_ctid_depois text;
  c1 record;
  c2 record;
  v_canc jsonb;
  v_falhas text[];
begin
  perform pg_temp._livrar();
  v_cmp := (pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()))->>'id')::uuid;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val));
  v_q := pg_temp._proposta(v_tx);
  perform public.comprovantes_reavaliar_banco('teste', null);
  perform pg_temp._resp(pg_temp._banco(v_cmp), '{"tipo":"sim"}'::jsonb);
  -- o SIM aprovou (o finance-review: lançamento na linha, proposta aprovada, R12)
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               bank_transaction_id, origin)
  values ('Aprovado pelo SIM (teste F3)', pg_temp._hoje(), pg_temp._hoje(), v_val, v_val, 0, 'paid', 'Materiais e Insumos Operacionais',
          v_tx, 'bank_reconciliation')
  returning id into v_pay;
  update public.finance_review_queue set status = 'approved', created_payable_id = v_pay, decided_by = pg_temp._dono(), decided_at = now()
   where id = v_q;
  perform public.comprovante_aprovado(v_cmp, v_q, v_pay);
  -- o dono vê a categoria errada e usa "Desfazer aprovação" no Extrato: o lançamento cai e a proposta volta a pendente
  perform public.desfazer_aprovacao('payable', v_pay, 'categoria errada', pg_temp._dono());
  -- a varredura (cron e finance-review): nada a aprovar de novo; a linha fica com o dono
  v_r1 := public.comprovantes_reavaliar_banco('teste', null);
  select status into v_status_q from public.finance_review_queue where id = v_q;
  select * into c1 from public.comprovantes where id = v_cmp;
  select ctid::text into v_ctid_antes from public.comprovantes where id = v_cmp;
  v_r1b := public.comprovantes_reavaliar_banco('teste', null);
  select ctid::text into v_ctid_depois from public.comprovantes where id = v_cmp;
  -- o dono aprova de novo pela tela, com a categoria dele: a varredura só adota o lançamento
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               bank_transaction_id, origin)
  values ('Aprovado pelo dono no Extrato (teste F3)', pg_temp._hoje(), pg_temp._hoje(), v_val, v_val, 0, 'paid', 'Outras despesas',
          v_tx, 'bank_reconciliation')
  returning id into v_pay2;
  update public.finance_review_queue set status = 'approved', created_payable_id = v_pay2, decided_by = pg_temp._dono(), decided_at = now()
   where id = v_q;
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c2 from public.comprovantes where id = v_cmp;
  v_canc := public.comprovante_cancelar(v_cmp, 'era outra compra', pg_temp._dono());

  select array_agg(nome) into v_falhas from (values
    ('nada_a_aprovar', not (v_r1->'aprovar' @> jsonb_build_array(jsonb_build_object('cmp_id', v_cmp)))
                       and not (v_r1b->'aprovar' @> jsonb_build_array(jsonb_build_object('cmp_id', v_cmp)))
                       and v_status_q = 'pending'),
    ('desfeita_marcada', c1.situacao = 'conciliado' and c1.bank_transaction_id = v_tx and c1.payable_id is null
                         and 'classificar_no_extrato' = any (c1.pendencias)
                         and exists (select 1 from jsonb_array_elements(c1.efeitos) e
                                      where e->>'tipo' = 'ligar_linha' and not e ? 'aprovado'
                                        and e->'aprovado_desfeito'->>'payable_id' = v_pay::text)),
    ('uma_gravacao', v_ctid_antes = v_ctid_depois),
    ('adota_o_do_dono', c2.payable_id = v_pay2 and not ('classificar_no_extrato' = any (c2.pendencias))
                        and exists (select 1 from jsonb_array_elements(c2.efeitos) e
                                     where e->>'tipo' = 'ligar_linha' and coalesce((e->>'lancado_depois')::boolean, false))
                        and (select expense_category from public.payables where id = v_pay2) = 'Outras despesas'),
    ('cancelar_recusa', not (v_canc->>'ok')::boolean and v_canc->'bloqueios'->0->>'motivo' = 'linha_lancada')
  ) as t(nome, ok) where not coalesce(ok, false);
  insert into _resultado values ('T27 a aprovação do SIM desfeita no Extrato: nunca aprova de novo; pendência para o dono; a nova aprovação dele é adotada',
    v_falhas is null,
    coalesce('falhou: ' || array_to_string(v_falhas, ', ') || ' | ', '')
    || 'proposta=' || coalesce(v_status_q, '-') || ' pend=' || coalesce(array_to_string(c1.pendencias, ','), '-')
    || ' pay=' || coalesce(c1.payable_id::text, 'nulo') || ' adotou=' || coalesce(c2.payable_id = v_pay2, false)
    || ' cancelar=' || coalesce(v_canc->'bloqueios'->0->>'motivo', v_canc->>'ok', '-'));
exception when others then
  insert into _resultado values ('T27 a aprovação do SIM desfeita no Extrato: nunca aprova de novo; pendência para o dono; a nova aprovação dele é adotada', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T26: regra E — 5 dias sem aparecer em conta nenhuma: "quem pagou?" (ajustes do dono, 11/10/2026) ═══
do $$
declare
  v_d6 date := pg_temp._hoje() - 6;
  v_socio uuid;
  v_tec uuid;
  v_perfil uuid;
  v_os uuid;
  v_cli uuid;
  v_ves uuid;
  v_cnpj text := pg_temp._cnpj();
  c4 uuid; c6 uuid; cx uuid; cs uuid; ct uuid; cp uuid; cb uuid;
  p jsonb;
  r_emp jsonb; r_soc jsonb; r_tec jsonb; r_pes jsonb;
  v_opcoes text;
  x4 public.comprovantes; x6 record; xx public.comprovantes; xs record; xt record; xp record; xb record;
  v_anot_s uuid;
  v_bloq jsonb;
  v_efeitos_antes jsonb;
  v_falhas text[];
  -- revisão dos ajustes: o extrato atrasado, a anotação do dono e a vigia depois da troca
  v_outras uuid[];
  v_atrasada uuid;
  x6a public.comprovantes;
  v_pode_atrasada boolean;
  v_val_a numeric := pg_temp._val();
  v_cnpj_a text := pg_temp._cnpj();
  v_anot_a uuid;
  ca uuid;
  v_tipos_a text;
  r_ane jsonb;
  v_tx_vigia uuid;
  xs2 record;
  v_r2 jsonb;
  v_ctid1 text;
  v_ctid2 text;
begin
  perform pg_temp._livrar();
  -- só as contas de teste contam para "o extrato está em dia até D+5" (as outras ficam inativas só dentro
  -- da transação) e as duas recebem uma linha importada hoje
  select coalesce(array_agg(id), '{}'::uuid[]) into v_outras from public.bank_connections
   where active and id not in (pg_temp._conta(), pg_temp._cartao());
  update public.bank_connections set active = false where id = any (v_outras);
  perform pg_temp._linha(jsonb_build_object('valor', pg_temp._val(), 'descricao', 'LINHA DE HOJE'));
  perform pg_temp._linha(jsonb_build_object('valor', pg_temp._val(), 'descricao', 'LINHA DE HOJE', 'fonte', 'credit_card'));
  -- (i) uma conta ATRASADA: teve linha perto da compra e nada importado de D+5 em diante
  insert into public.bank_connections (provider, external_id, label, account_kind)
  values ('manual', 'teste-f3-' || gen_random_uuid(), 'Conta Atrasada F3', 'bank') returning id into v_atrasada;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id)
  values (v_d6 - 2, 'LINHA ANTIGA', pg_temp._val(), 'debit', 'bank', v_atrasada);
  insert into public.payees (name, kind, active, app_user_id) values ('Sócio Teste F3', 'socio', true, pg_temp._dono())
  returning id into v_socio;
  -- técnico com diária (o nome começa por "Aaa": entra nos 6 primeiros do menu)
  insert into public.payees (name, kind, active, conta_corrente_desde) values ('Aaa Técnico Teste F3 ' || pg_temp._letras(4), 'diarista', true, v_d6 - 30)
  returning id into v_tec;
  insert into public.work_profiles (payee_id, modo_pagamento, valor_diaria, vigencia_inicio) values (v_tec, 'diaria', 300, v_d6 - 30)
  returning id into v_perfil;
  insert into public.clients (type, name) values ('individual', 'Cliente Teste F3 ' || pg_temp._letras(5)) returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Barco Teste F3 ' || pg_temp._letras(5)) returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, grand_total, operational_cost_total,
                                     labor_cost_total, travel_cost_total)
  values ('OS-' || (900000 + floor(random() * 99000)::integer), v_cli, v_ves, 'open', 0, 0, 0, 0) returning id into v_os;
  -- (a) há 4 dias: não pergunta; (b) há 6: pergunta; (c) há 6 com a linha do mesmo valor no CARTÃO: não pergunta
  c4 := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'debito', 'cnpj', pg_temp._cnpj(), 'data', pg_temp._hoje() - 4))->>'id')::uuid;
  c6 := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'debito', 'cnpj', pg_temp._cnpj(), 'data', v_d6))->>'id')::uuid;
  cx := (pg_temp._cmp(jsonb_build_object('valor', 1234.56 + floor(random() * 1000), 'forma', 'debito', 'cnpj', pg_temp._cnpj(), 'data', v_d6))->>'id')::uuid;
  perform pg_temp._linha(jsonb_build_object('valor', (select valor_confirmado from public.comprovantes where id = cx),
                                            'fonte', 'credit_card', 'descricao', 'OUTRA CONTA', 'data', v_d6 + 2));
  -- (e) o Pix ao CNPJ que anotou; (f) a despesa da OS para o técnico; (g) a despesa da OS que era pessoal;
  -- (h) a anotação já aplicada com lançamento: bloqueia
  cs := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix', 'tipo', 'pix', 'favorecido', pg_temp._cnpj(),
                                         'data', v_d6))->>'id')::uuid;
  ct := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'debito', 'cnpj', pg_temp._cnpj(), 'data', v_d6,
                                         'destino', 'os', 'os', v_os, 'tipo_na_os', 'despesa', 'categoria', 'Ferramentas e equipamentos'))->>'id')::uuid;
  cp := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'debito', 'cnpj', pg_temp._cnpj(), 'data', v_d6,
                                         'destino', 'os', 'os', v_os, 'tipo_na_os', 'despesa', 'categoria', 'Alimentação de campo'))->>'id')::uuid;
  cb := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix', 'tipo', 'pix', 'favorecido', v_cnpj,
                                         'data', v_d6))->>'id')::uuid;
  -- (j) o Pix que achou a anotação do PRÓPRIO dono ("vai sair um Pix de R$ X para o CNPJ Y"): anexa a ela
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, documento, categoria, descricao, criada_por)
  values ('debit', v_val_a, v_d6, true, v_cnpj_a, 'Outras despesas', 'anotada antes pelo dono', pg_temp._dono())
  returning id into v_anot_a;
  ca := (pg_temp._cmp(jsonb_build_object('valor', v_val_a, 'forma', 'pix', 'tipo', 'pix', 'favorecido', v_cnpj_a,
                                         'data', v_d6))->>'id')::uuid;
  select pg_temp._tipos(efeitos) into v_tipos_a from public.comprovantes where id = ca;
  -- com a conta atrasada, ninguém pergunta "quem pagou?" (o extrato pode só não ter chegado)
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into x6a from public.comprovantes where id = c6;
  v_pode_atrasada := public._comprovante_quem_pode(x6a);
  -- a conta atrasada importa uma linha de hoje: agora sim
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id)
  values (pg_temp._hoje(), 'LINHA NOVA', pg_temp._val(), 'debit', 'bank', v_atrasada);
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into x4 from public.comprovantes where id = c4;
  select * into x6 from public.comprovantes where id = c6;
  select * into xx from public.comprovantes where id = cx;
  p := pg_temp._banco(c6);
  select string_agg(o->>'valor', ',' order by (o->>'n')::int) into v_opcoes from jsonb_array_elements(p->'opcoes') o;
  -- (d) "a empresa": só marca (continua esperando; não pergunta de novo)
  r_emp := pg_temp._resp(p, '{"tipo":"palavra","valor":"empresa"}'::jsonb);
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into x6 from public.comprovantes where id = c6;
  -- (e) "eu": desfaz a anotação e grava o reembolso ao sócio
  select anotacao_id into v_anot_s from public.comprovantes where id = cs;
  r_soc := pg_temp._resp(pg_temp._banco(cs), '{"tipo":"opcao","n":2}'::jsonb);
  select * into xs from public.comprovantes where id = cs;
  -- (f) o técnico com diária: o crédito nas Diárias e a despesa da OS paga por ele
  p := pg_temp._banco(ct);
  r_tec := pg_temp._resp(p, jsonb_build_object('tipo', 'opcao', 'n',
             (select (o->>'n')::int from jsonb_array_elements(p->'opcoes') o where o->>'valor' = 'payee:' || v_tec)));
  select * into xt from public.comprovantes where id = ct;
  -- (g) "pessoal": o custo interno sai da OS e o arquivo vai para PESSOAL
  p := pg_temp._banco(cp);
  r_pes := pg_temp._resp(p, jsonb_build_object('tipo', 'palavra', 'valor', 'pessoal'));
  select * into xp from public.comprovantes where id = cp;
  -- (h) a anotação aplicada e a linha dela já lançada: bloqueia, nada muda
  update public.anotacoes_do_extrato set status = 'aplicada', aplicada_em = now(),
         bank_transaction_id = pg_temp._linha(jsonb_build_object('valor', 9.99, 'descricao', 'PIX ENVIADO', 'data', v_d6))
   where id = (select anotacao_id from public.comprovantes where id = cb);
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category, bank_transaction_id, origin)
  select 'Aprovado no Extrato (teste F3)', v_d6, v_d6, 9.99, 9.99, 0, 'paid', 'Outras despesas', a.bank_transaction_id, 'manual'
    from public.anotacoes_do_extrato a where a.id = (select anotacao_id from public.comprovantes where id = cb);
  select efeitos into v_efeitos_antes from public.comprovantes where id = cb;
  v_bloq := public._comprovante_trocar_pagador(cb, 'socio', null, pg_temp._dono());
  select * into xb from public.comprovantes where id = cb;
  -- (j) "eu": a anotação do dono que dizia que a EMPRESA ia pagar sai junto
  r_ane := pg_temp._resp(pg_temp._banco(ca), '{"tipo":"opcao","n":2}'::jsonb);
  -- (k) a vigia: depois do "eu" do (e), a compra aparece na conta da empresa — pendência e linha reservada,
  -- nada ligado; a rodada seguinte não grava de novo
  v_tx_vigia := pg_temp._linha(jsonb_build_object('valor', (select valor_confirmado from public.comprovantes where id = cs),
                                                  'descricao', 'PIX ENVIADO', 'data', v_d6 + 1));
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into xs2 from public.comprovantes where id = cs;
  v_r2 := public.comprovantes_linhas_da_conciliacao(array[v_tx_vigia]);
  select ctid::text into v_ctid1 from public.comprovantes where id = cs;
  perform public.comprovantes_reavaliar_banco('teste', null);
  select ctid::text into v_ctid2 from public.comprovantes where id = cs;
  update public.bank_connections set active = true where id = any (v_outras);

  select array_agg(nome) into v_falhas from (values
    ('conta_atrasada_espera', not x6a.banco_perguntar and not coalesce(v_pode_atrasada, true)),
    ('anotacao_do_dono_sai', v_tipos_a like '%anexar_anotacao%' and r_ane->>'resultado' = 'regravado'
                             and (select status from public.anotacoes_do_extrato where id = v_anot_a) = 'cancelada'),
    ('vigia_avisa', 'conferir_quem_pagou' = any (xs2.pendencias) and xs2.bank_transaction_id is null
                    and xs2.banco_candidatos @> jsonb_build_array(jsonb_build_object('id', v_tx_vigia, 'vigia', true))
                    and v_r2->'linhas' @> jsonb_build_array(jsonb_build_object('bank_transaction_id', v_tx_vigia, 'papel', 'candidata'))
                    and v_ctid1 = v_ctid2),
    ('4_dias_nao', not x4.banco_perguntar and not public._comprovante_quem_pode(x4)),
    ('6_dias_pergunta', p is not null and v_opcoes like 'empresa,socio,%payee:' || v_tec || '%,pessoal'),
    ('outra_conta_nao', not xx.banco_perguntar and public._comprovante_aparece_em_alguma_conta(xx)),
    ('empresa_so_marca', r_emp->>'resultado' = 'esperando' and x6.banco_quem_em is not null and not x6.banco_perguntar
                         and x6.situacao = 'aguardando_banco' and r_emp->>'ate' is not null),
    ('socio_reembolso', r_soc->>'resultado' = 'regravado' and pg_temp._tipos(xs.efeitos) = 'reembolso_socio'
                        and xs.situacao = 'gravado' and xs.quem_pagou = 'socio' and xs.anotacao_id is null
                        and (select status from public.anotacoes_do_extrato where id = v_anot_s) = 'cancelada'
                        and (select payee_id from public.payables where id = xs.payable_id) = v_socio
                        and (select status from public.payables where id = xs.payable_id) = 'pending'
                        and r_soc->'gravacao'->>'situacao' = 'gravado'),
    ('tecnico_diarias', r_tec->>'resultado' = 'regravado' and pg_temp._tipos(xt.efeitos) = 'despesa_os,reembolso_tecnico'
                        and xt.reembolso_id is not null
                        and (select status from public.diarias_reembolsos where id = xt.reembolso_id) = 'ativo'
                        and (select count(*) from public.service_order_expenses e where e.service_order_id = v_os and e.paid_by = 'technician'
                              and e.reimbursed and e.origem_codigo = xt.codigo) = 1
                        and (select count(*) from public.service_order_expenses e where e.service_order_id = v_os and e.origem_codigo = xt.codigo) = 1),
    ('pessoal_arquivo', r_pes->>'resultado' = 'regravado' and pg_temp._tipos(xp.efeitos) = 'nada' and xp.destino = 'pessoal'
                        and xp.destino_os_id is null and xp.dropbox_pendente = 'mover'
                        and not exists (select 1 from public.service_order_expenses e where e.origem_codigo = xp.codigo)),
    ('bloqueio_nada_muda', not (v_bloq->>'ok')::boolean and v_bloq->'bloqueios'->0->>'motivo' = 'anotacao_aplicada'
                           and xb.efeitos = v_efeitos_antes and xb.situacao = 'aguardando_banco')
  ) as t(nome, ok) where not coalesce(ok, false);
  insert into _resultado values ('T26 regra E: 5 dias sem aparecer = "quem pagou?"; empresa marca; eu, técnico e pessoal regravam; bloqueio não muda nada',
    v_falhas is null,
    coalesce('falhou: ' || array_to_string(v_falhas, ', ') || ' | ', '')
    || 'opcoes=' || coalesce(regexp_replace(v_opcoes, 'payee:[0-9a-f-]+', 'payee', 'g'), '-') || ' empresa=' || coalesce(r_emp->>'resultado', '-')
    || ' socio=' || coalesce(r_soc->>'resultado', '-') || '/' || coalesce(r_soc->>'motivo', '') || ' tecnico=' || coalesce(r_tec->>'resultado', '-')
    || '/' || coalesce(r_tec->>'motivo', '') || ' pessoal=' || coalesce(r_pes->>'resultado', '-') || ' bloqueio='
    || coalesce(v_bloq->'bloqueios'->0->>'motivo', v_bloq->>'ok', '-'));
  -- tira do caminho do T24 (a varredura de novo não pergunta deles)
  update public.comprovantes set banco_quem_em = now(), banco_perguntar = false
   where id in (c4, c6, cx, cs, ct, cp, cb, ca) and situacao = 'aguardando_banco';
exception when others then
  insert into _resultado values ('T26 regra E: 5 dias sem aparecer = "quem pagou?"; empresa marca; eu, técnico e pessoal regravam; bloqueio não muda nada', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T28: regra E — a conta sem movimento que sincroniza bem não segura o "quem pagou?" (11/10/2026) ═══
-- O Nubank PJ sincroniza todo dia (ok, UPDATED) sem linha nova desde 18/09: pela regra antiga ele segurava
-- toda compra, o "quem pagou?" nunca era feito e o CMP virava 'abandonado'. A conexão sã, com o Pluggy indo
-- ao banco depois de D+5 (D+13 no cartão) e o que ele trouxe já importado, deixa a conta em dia.
do $$
declare
  v_d date := pg_temp._hoje() - 20;
  v_d6 date := pg_temp._hoje() - 6;
  v_ini6 timestamptz;
  v_outras uuid[];
  v_parada uuid;
  v_cartao uuid;
  x public.comprovantes;
  c6 uuid;
  x6 public.comprovantes;
  a_manual boolean; b_sa boolean; c_erro boolean; c_outdated boolean; d_dentro_d5 boolean; f_nao_importada boolean;
  e_cartao_d7 boolean; e_cartao_d13 boolean; g_doente boolean; g_sa boolean; g_marcou boolean;
  v_falhas text[];
begin
  perform pg_temp._livrar();
  -- só as contas deste teste contam (as outras ficam inativas só dentro da transação)
  select coalesce(array_agg(id), '{}'::uuid[]) into v_outras from public.bank_connections where active;
  update public.bank_connections set active = false where id = any (v_outras);
  -- a conta PARADA: uma linha antiga perto da compra e nada de D+5 em diante
  insert into public.bank_connections (provider, external_id, label, account_kind)
  values ('manual', 'teste-f3-' || gen_random_uuid(), 'Conta Parada F3', 'bank') returning id into v_parada;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id)
  values (v_d - 2, 'LINHA ANTIGA', pg_temp._val(), 'debit', 'bank', v_parada);
  x.data_confirmada := v_d;
  v_ini6 := (v_d + 6)::timestamp at time zone 'America/Sao_Paulo';
  -- (a) sem sincronização (a conexão manual): segura
  a_manual := public._comprovante_extrato_em_dia(x);
  -- (b) ok + UPDATED + o Pluggy no banco 1 h depois de D+5 terminar + importado depois: em dia
  update public.bank_connections set last_sync_status = 'ok', provider_status = 'UPDATED',
         provider_updated_at = v_ini6 + interval '1 hour', last_synced_at = v_ini6 + interval '65 minutes'
   where id = v_parada;
  b_sa := public._comprovante_extrato_em_dia(x);
  -- (c) a última sincronização deu erro; o item está OUTDATED no Pluggy: segura
  update public.bank_connections set last_sync_status = 'error' where id = v_parada;
  c_erro := public._comprovante_extrato_em_dia(x);
  update public.bank_connections set last_sync_status = 'ok', provider_status = 'OUTDATED' where id = v_parada;
  c_outdated := public._comprovante_extrato_em_dia(x);
  -- (d) o Pluggy foi ao banco ainda dentro de D+5: segura
  update public.bank_connections set provider_status = 'UPDATED', provider_updated_at = v_ini6 - interval '1 minute'
   where id = v_parada;
  d_dentro_d5 := public._comprovante_extrato_em_dia(x);
  -- (f) o que o Pluggy trouxe ainda não foi importado (last_synced_at antes de provider_updated_at): segura
  update public.bank_connections set provider_updated_at = v_ini6 + interval '1 hour', last_synced_at = v_ini6 + interval '30 minutes'
   where id = v_parada;
  f_nao_importada := public._comprovante_extrato_em_dia(x);
  -- (e) o CARTÃO parado: a sincronização sã em D+7 não basta (a compra do cartão chega dias depois); em D+13, sim
  update public.bank_connections set active = false where id = v_parada;
  insert into public.bank_connections (provider, external_id, label, account_kind, last_sync_status, provider_status,
                                       provider_updated_at, last_synced_at)
  values ('manual', 'teste-f3-' || gen_random_uuid(), 'Cartão Parado F3', 'credit_card', 'ok', 'UPDATED',
          ((v_d + 7)::timestamp at time zone 'America/Sao_Paulo') + interval '1 hour',
          ((v_d + 7)::timestamp at time zone 'America/Sao_Paulo') + interval '65 minutes')
  returning id into v_cartao;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id)
  values (v_d - 2, 'COMPRA ANTIGA', pg_temp._val(), 'debit', 'credit_card', v_cartao);
  e_cartao_d7 := public._comprovante_extrato_em_dia(x);
  update public.bank_connections
     set provider_updated_at = ((v_d + 13)::timestamp at time zone 'America/Sao_Paulo') + interval '1 hour',
         last_synced_at = ((v_d + 13)::timestamp at time zone 'America/Sao_Paulo') + interval '65 minutes'
   where id = v_cartao;
  e_cartao_d13 := public._comprovante_extrato_em_dia(x);
  -- (g) de ponta a ponta: o CMP de 6 dias com a conta parada. Com a sincronização em erro, não pergunta; sã
  -- (o Pluggy foi ao banco hoje), o "quem pagou?" cabe e a varredura o marca
  update public.bank_connections set active = false where id = v_cartao;
  update public.bank_connections set active = true, last_sync_status = 'error' where id = v_parada;
  c6 := (pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'debito', 'cnpj', pg_temp._cnpj(), 'data', v_d6))->>'id')::uuid;
  select * into x6 from public.comprovantes where id = c6;
  g_doente := public._comprovante_quem_pode(x6);
  update public.bank_connections set last_sync_status = 'ok', provider_status = 'UPDATED',
         provider_updated_at = now(), last_synced_at = now()
   where id = v_parada;
  g_sa := public._comprovante_quem_pode(x6);
  perform public.comprovantes_reavaliar_banco('teste', null);
  select banco_perguntar into g_marcou from public.comprovantes where id = c6;
  update public.bank_connections set active = false where id = v_parada;
  update public.bank_connections set active = true where id = any (v_outras);

  select array_agg(nome) into v_falhas from (values
    ('a_manual_segura', not a_manual),
    ('b_sa_em_dia', b_sa),
    ('c_erro_segura', not c_erro),
    ('c_outdated_segura', not c_outdated),
    ('d_dentro_de_d5_segura', not d_dentro_d5),
    ('f_nao_importada_segura', not f_nao_importada),
    ('e_cartao_d7_segura', not e_cartao_d7),
    ('e_cartao_d13_em_dia', e_cartao_d13),
    ('g_doente_nao_pergunta', x6.situacao = 'aguardando_banco' and not g_doente),
    ('g_sa_pergunta', g_sa and g_marcou)
  ) as t(nome, ok) where not coalesce(ok, false);
  insert into _resultado values ('T28 regra E: a conta sem movimento que sincroniza bem (D+6; D+13 no cartão) não segura o "quem pagou?"; manual, erro, OUTDATED, cedo ou não importada, segura',
    v_falhas is null,
    coalesce('falhou: ' || array_to_string(v_falhas, ', ') || ' | ', '')
    || 'manual=' || coalesce(a_manual::text, '-') || ' sa=' || coalesce(b_sa::text, '-') || ' erro=' || coalesce(c_erro::text, '-')
    || ' outdated=' || coalesce(c_outdated::text, '-') || ' d5=' || coalesce(d_dentro_d5::text, '-')
    || ' nao_importada=' || coalesce(f_nao_importada::text, '-') || ' cartao_d7=' || coalesce(e_cartao_d7::text, '-')
    || ' cartao_d13=' || coalesce(e_cartao_d13::text, '-') || ' cmp=' || coalesce(x6.situacao, '-') || '/'
    || coalesce(g_doente::text, '-') || '/' || coalesce(g_sa::text, '-') || '/' || coalesce(g_marcou::text, '-'));
  -- tira do caminho do T24 (a varredura de novo não pergunta dele)
  update public.comprovantes set banco_quem_em = now(), banco_perguntar = false
   where id = c6 and situacao = 'aguardando_banco';
exception when others then
  insert into _resultado values ('T28 regra E: a conta sem movimento que sincroniza bem (D+6; D+13 no cartão) não segura o "quem pagou?"; manual, erro, OUTDATED, cedo ou não importada, segura', false,
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
