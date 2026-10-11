-- Prova: plano, gravação e cancelamento da F3 (migration 20261011303000; usa 20261011300000-302000/304000).
--
-- Uma linha por ramo da 3.5 da spec da F3:
--   GV1 débito verde: o sim grava e liga (classifica a proposta), sem anotar
--   GV2 débito cinza: espera o banco (aguardar_banco), sem anotar
--   GV3 Pix com CNPJ cinza: anota (a anotação liga quando o banco trouxer)
--   GV4 Pix verde: liga na gravação
--   GV5 crédito verde (compra PENDING no cartão): liga e classifica quando a proposta aparece; crédito
--       de nome diferente: azul, espera a fatura e pergunta
--   GV6 conta a pagar em aberto + linha verde: o sim casa a conta com a linha
--   GV7 técnico com diária: reembolso nas Diárias (a despesa da OS fica "reembolsada"); sem diária: a
--       pendência da F2 + o aviso
-- Cancelamento:
--   GX1 ligada sem lançamento: desfaz e devolve a linha ao motor
--   GX2 a linha virou lançamento depois da ligação: bloqueia (linha_lancada), nada muda
--   GX3 casada: bloqueia (linha_casada)
--   GX4 reembolso em período aberto: cancela o crédito
--   GX5 reembolso em acerto fechado: bloqueia (reembolso_acertado)
--   GX6 anotação aplicada sem lançamento: não bloqueia; a proposta volta para o motor
-- Notas e índice:
--   GN1 NF-e com a nota confirmada: a OS pela linha da nota já na gravação; com a nota ainda pendente
--       (sem linhas), espera o XML
--   GN2 NF-e aguardando o XML: a nota pendente não fecha; confirmada, a R5 fecha o CMP e liga os itens
--   GN3 a nota chegou só no e-mail: a varredura marca nota_no_email_em e o "pendentes" mostra
--   GI1 o índice do mês não lista o PESSOAL; o gatilho marca o índice pessoal; a R7 lista
-- Correção da revisão de 11/10/2026:
--   GA1 a linha ligada que o dono aprovou com outra categoria e sem a OS: a varredura só adota; cancelar recusa
--   GA2 conta a pagar em aberto + a linha já lançada em outro registro: nunca verde, não liga, avisa
--   GR1 a despesa da OS paga pelo técnico fica "reembolsada" pelas Diárias; cancelar volta; já reembolsada
--       pela aba Reembolsos não ganha outro crédito
--   GT1 técnico que saiu das Diárias (a diária tem de valer na compra e hoje): a pendência da F2
--   GD1 a linha ligada foi estornada: desliga e deixa a pendência "conferir o estorno"
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado PF3-2 da spec da F3; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/comprovantes_gravacao_f3.sql --output json
--
-- Seguro em produção: tudo dentro da transação e ROLLBACK no fim (as rotas reais — so_expense_add,
-- anotar_transacao, corrigir_lancamento, conciliar_lancamento, fechar_acerto_diarias — gravam e são
-- desfeitas). Dono e freelancers de teste, OS/clientes/barcos/notas de mentira, valores aleatórios
-- (não casam com o extrato real). Sem id nem data fixos.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (dono uuid, phone text, conta uuid, cartao uuid) on commit drop;
create temp table _guarda (nome text primary key, id uuid, tx uuid, extra uuid) on commit drop;

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
create function pg_temp._cnpj() returns text language sql volatile as $$
  select '7' || lpad((floor(random() * 9999999))::bigint::text, 7, '0') || '0001' || lpad((floor(random() * 99))::bigint::text, 2, '0')
$$;
create function pg_temp._hoje() returns date language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;
create function pg_temp._chave() returns text language sql volatile as $$
  select '352610' || '112223330001' || '81' || '55' || '001'
         || lpad((floor(random() * 999999999))::bigint::text, 9, '0') || '1'
         || lpad((floor(random() * 99999999))::bigint::text, 8, '0') || '0'
$$;

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
create function pg_temp._extra(p_nome text) returns uuid language sql stable as $$ select extra from _guarda where nome = p_nome $$;
create function pg_temp._guardar(p_nome text, p_id uuid, p_tx uuid default null, p_extra uuid default null) returns void language sql as $$
  insert into _guarda values (p_nome, p_id, p_tx, p_extra) on conflict (nome) do update set id = excluded.id, tx = excluded.tx, extra = excluded.extra
$$;

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
create function pg_temp._proposta(p_tx uuid) returns uuid language sql as $$
  insert into public.finance_review_queue (kind, status, bank_transaction_id, title, confidence, suggested_category, reasoning)
  values ('create_payable', 'pending', p_tx, 'Teste F3', 50, 'Outras despesas', 'motor de teste') returning id
$$;

create function pg_temp._os() returns uuid language plpgsql as $$
declare
  v_cli uuid;
  v_ves uuid;
  v_os uuid;
  v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number = 'OS-' || v_num) loop
    v_num := v_num + 1;
  end loop;
  insert into public.clients (type, name) values ('individual', 'Cliente Teste F3 ' || pg_temp._letras(6)) returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Navio' || pg_temp._letras(8)) returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, invoicing_status,
                                     grand_total, operational_cost_total, labor_cost_total, travel_cost_total)
  values ('OS-' || v_num, v_cli, v_ves, 'open', 'not_invoiced', 0, 0, 0, 0)
  returning id into v_os;
  return v_os;
end $$;

-- freelancer de teste (com diária ou não)
create function pg_temp._freelancer(p_diaria boolean) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  insert into public.payees (name, kind, active, conta_corrente_desde)
  values ('Técnico Teste F3 ' || pg_temp._letras(5), case when p_diaria then 'diarista' else 'prestador' end, true,
          case when p_diaria then pg_temp._hoje() - 60 end)
  returning id into v;
  if p_diaria then
    insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
    values (v, 'freelancer', 'diaria', 300, pg_temp._hoje() - 60);
  end if;
  return v;
end $$;

create function pg_temp._livrar_perguntas() returns void language sql as $$
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste'
   where phone_normalized = pg_temp._phone() and status = 'aberta'
$$;

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

-- CMP lido → fila → respostas → resumo → sim (o caminho de verdade). Devolve a saída do responder + {"id","plano_mostrado"}.
create function pg_temp._cmp(p jsonb) returns jsonb language plpgsql as $$
declare
  v uuid;
  v_p jsonb;
begin
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized,
                                   tipo_whatsapp, recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca,
                                   data_compra, data_confianca, forma_pagamento, chave_acesso, lido_em,
                                   emitente_cnpj, cnpj_confianca, favorecido_doc, supplier_id, fornecedor_receita)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(),
          'TESTE-F3-' || gen_random_uuid(), pg_temp._phone(), 'image', now(),
          md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text),
          coalesce(p->>'tipo', 'nfce'), 'alta', (p->>'valor')::numeric, 'alta',
          coalesce((p->>'data')::date, pg_temp._hoje()), 'alta', p->>'forma', p->>'chave', now(),
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

create function pg_temp._tipos(p_efeitos jsonb) returns text language sql immutable as $$
  select coalesce(string_agg(e->>'tipo' || case when e->>'tipo' = 'pendencia' then ':' || (e->>'qual') else '' end, ',' order by o), '')
    from jsonb_array_elements(coalesce(p_efeitos, '[]'::jsonb)) with ordinality as t(e, o)
$$;
create function pg_temp._efeito(p_efeitos jsonb, p_tipo text) returns jsonb language sql immutable as $$
  select e from jsonb_array_elements(coalesce(p_efeitos, '[]'::jsonb)) e where e->>'tipo' = p_tipo limit 1
$$;

-- confirma a nota como a Entrada de Mercadoria (confirm_nfe_import): em produção, o gatilho
-- sync_fiscal_note_items refaz as linhas a partir de fiscal_notes.items quando confirmed_at é preenchido
-- (por isso as linhas vão também no items); no ensaio PGlite (sem as colunas), só o status.
create function pg_temp._confirmar_nota(p_nota uuid, p_itens integer) returns void language plpgsql as $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'fiscal_notes' and column_name = 'confirmed_at') then
    execute 'update public.fiscal_notes set items = $2, status = ''confirmed'', confirmed_at = now() where id = $1'
      using p_nota, (select jsonb_agg(jsonb_build_object('index', i, 'description', 'item ' || i, 'quantity', 1, 'unit_price', 1, 'total_price', 1))
                       from generate_series(1, p_itens) i);
  else
    update public.fiscal_notes set status = 'confirmed' where id = p_nota;
  end if;
end $$;

-- ═══ GV1 / GV2 / GV3 / GV4 ═══════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric;
  v_tx uuid;
  v_q uuid;
  r jsonb;
  c record;
  q record;
  v_cnpj text := pg_temp._cnpj();
  v_anot_antes integer;
begin
  -- GV1: débito com a linha (sem nome) e a proposta já na fila: verde → o sim grava e liga
  v_val := pg_temp._val();
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val));
  v_q := pg_temp._proposta(v_tx);
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj(), 'receita', 'Auto Peças Teste F3'));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  select * into q from public.finance_review_queue where id = v_q;
  perform pg_temp._guardar('GV1', c.id, v_tx, v_q);
  insert into _resultado values ('GV1 débito verde: o resumo mostra a linha, o sim grava e liga (classifica), sem anotar',
    r->>'resultado' = 'gravado' and pg_temp._tipos(r->'plano_mostrado'->'efeitos') = 'ligar_linha'
    and r->'plano_mostrado'->'efeitos'->0->'linha'->>'acao' = 'classificar' and r->'plano_mostrado'->>'situacao_final' = 'conciliado'
    and c.situacao = 'conciliado' and c.bank_transaction_id = v_tx and c.conciliacao = 'verde'
    and pg_temp._efeito(c.efeitos, 'ligar_linha')->>'origem' = 'gravacao'
    and pg_temp._efeito(c.efeitos, 'ligar_linha')->>'como' = 'classificou'
    and c.linha_explicada_em is not null and c.banco_regra = 'debito' and not c.banco_perguntar
    and r->'gravacao'->'banco'->>'nivel' = 'verde' and r->'gravacao'->'banco'->>'perguntar' = 'false'
    and q.confidence = 99 and q.evidencia ? 'anotacao'
    and (select documento from public.anotacoes_do_extrato where id = c.anotacao_id) is null
    and (select nome_pelo_comprovante from public.bank_transactions where id = v_tx) like 'Auto Peças Teste F3 · CMP-%',
    'efeitos=' || pg_temp._tipos(c.efeitos) || ' situacao=' || c.situacao || ' banco=' || coalesce(r->'gravacao'->>'banco', '-'));

  -- GV2: débito sem linha (cinza): espera o banco, sem anotar (o C6 manda o débito sem documento)
  v_val := pg_temp._val();
  select count(*) into v_anot_antes from public.anotacoes_do_extrato;
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'cnpj', pg_temp._cnpj()));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  insert into _resultado values ('GV2 débito cinza: aguardar_banco, sem anotação, espera 30 dias',
    r->>'resultado' = 'gravado' and pg_temp._tipos(c.efeitos) = 'aguardar_banco' and c.situacao = 'aguardando_banco'
    and c.efeitos->0->>'regra' = 'debito' and c.efeitos->0->>'nivel' = 'cinza' and c.anotacao_id is null
    and c.aguardando_banco_desde is not null and (select count(*) from public.anotacoes_do_extrato) = v_anot_antes
    and r->'gravacao'->'banco'->>'nivel' = 'cinza' and r->'gravacao'->'banco'->>'perguntar' = 'false'
    and r->'cmp'->'banco'->>'estado' = 'esperando',
    'efeitos=' || pg_temp._tipos(c.efeitos) || ' situacao=' || c.situacao || ' estado=' || coalesce(r->'cmp'->'banco'->>'estado', '-'));

  -- GV3: Pix com CNPJ e sem linha (cinza): anota (a anotação liga quando o banco trouxer)
  v_val := pg_temp._val();
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', v_cnpj));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  insert into _resultado values ('GV3 Pix com CNPJ cinza: anota e espera o banco',
    r->>'resultado' = 'gravado' and pg_temp._tipos(c.efeitos) = 'anotar' and c.situacao = 'aguardando_banco'
    and c.anotacao_id is not null and (select documento from public.anotacoes_do_extrato where id = c.anotacao_id) = v_cnpj,
    'efeitos=' || pg_temp._tipos(c.efeitos) || ' situacao=' || c.situacao);

  -- GV4: Pix com a linha do mesmo CNPJ na fila: verde → liga na gravação (sem a anotação da F2)
  v_val := pg_temp._val();
  v_cnpj := pg_temp._cnpj();
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX', 'doc', v_cnpj, 'nome', 'LOJA PIX F3'));
  v_q := pg_temp._proposta(v_tx);
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', v_cnpj));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  perform pg_temp._guardar('GV4', c.id, v_tx, v_q);
  insert into _resultado values ('GV4 Pix verde: liga na gravação, sem anotar pela rota da F2',
    r->>'resultado' = 'gravado' and pg_temp._tipos(c.efeitos) = 'ligar_linha' and c.situacao = 'conciliado'
    and c.bank_transaction_id = v_tx and not exists (select 1 from jsonb_array_elements(c.efeitos) e where e->>'tipo' = 'anotar')
    -- a loja do Pix tem nome na linha: a F3 não grava outro
    and (select nome_pelo_comprovante from public.bank_transactions where id = v_tx) is null,
    'efeitos=' || pg_temp._tipos(c.efeitos) || ' situacao=' || c.situacao);
exception when others then
  insert into _resultado values ('GV1-GV4 débito e Pix', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GV5 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cnpj text := pg_temp._cnpj();
  v_loja text := 'AUTO TESTE F3 ' || pg_temp._letras(5);
  v_tx uuid;
  r jsonb;
  c record;
  c2 record;
  r2 jsonb;
  ca record;
begin
  insert into public.cnpj_consultas (cnpj, encontrado, razao_social, nome_fantasia, consultado_em)
  values (v_cnpj, true, v_loja || ' BRASIL LTDA', v_loja, now()) on conflict (cnpj) do nothing;
  -- compra no cartão ainda PENDING, sem proposta: liga agora, classifica quando a proposta aparecer
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val, 'fonte', 'credit_card', 'descricao', v_loja, 'loja', v_loja, 'status', 'PENDING'));
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'credito', 'cnpj', v_cnpj));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  update public.bank_transactions set tx_status = 'POSTED' where id = v_tx;
  perform pg_temp._proposta(v_tx);
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c2 from public.comprovantes where id = c.id;
  -- nome diferente no cartão: azul (nunca liga sozinho), espera a fatura e pergunta
  v_val := pg_temp._val();
  perform pg_temp._linha(jsonb_build_object('valor', v_val, 'fonte', 'credit_card', 'descricao', 'NOME DIFERENTE F3', 'loja', 'NOME DIFERENTE F3'));
  r2 := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'credito', 'cnpj', v_cnpj));
  select * into ca from public.comprovantes where id = (r2->>'id')::uuid;
  insert into _resultado values ('GV5 crédito verde liga (classifica quando a compra entra na fila); nome diferente fica azul e pergunta',
    r->>'resultado' = 'gravado' and pg_temp._tipos(c.efeitos) = 'ligar_linha' and c.situacao = 'conciliado'
    and pg_temp._efeito(c.efeitos, 'ligar_linha')->>'como' = 'aguardando' and c.linha_explicada_em is null
    and c2.linha_explicada_em is not null and pg_temp._efeito(c2.efeitos, 'ligar_linha')->>'como' = 'classificou'
    and pg_temp._efeito(c2.efeitos, 'ligar_linha')->>'origem' = 'gravacao'
    and r2->>'resultado' = 'gravado' and pg_temp._tipos(ca.efeitos) = 'aguardar_fatura' and ca.situacao = 'aguardando_banco'
    and ca.conciliacao = 'azul' and ca.banco_perguntar and r2->'gravacao'->'banco'->>'perguntar' = 'true',
    'verde=' || pg_temp._tipos(c.efeitos) || '/' || coalesce(pg_temp._efeito(c2.efeitos, 'ligar_linha')->>'como', '-')
    || ' azul=' || pg_temp._tipos(ca.efeitos) || '/' || ca.situacao || '/' || coalesce(ca.conciliacao, '-'));
exception when others then
  insert into _resultado values ('GV5 crédito verde liga (classifica quando a compra entra na fila); nome diferente fica azul e pergunta', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GV6 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cnpj text := pg_temp._cnpj();
  v_sup uuid;
  v_pay uuid;
  v_tx uuid;
  v_q uuid;
  r jsonb;
  c record;
  pay record;
begin
  insert into public.suppliers (name, cnpj_cpf) values ('Fornecedor Conta F3 ' || pg_temp._letras(5), v_cnpj) returning id into v_sup;
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               supplier_id, origin)
  values ('Conta aberta F3', pg_temp._hoje(), pg_temp._hoje() + 5, v_val, 0, v_val, 'pending', 'Materiais e Insumos Operacionais', v_sup, 'manual')
  returning id into v_pay;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX', 'doc', v_cnpj, 'nome', 'FORNECEDOR CONTA'));
  v_q := pg_temp._proposta(v_tx);
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', v_cnpj, 'fornecedor', v_sup));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  select * into pay from public.payables where id = v_pay;
  perform pg_temp._guardar('GV6', c.id, v_tx, v_pay);
  insert into _resultado values ('GV6 conta a pagar em aberto + linha verde: o sim casa a conta com a linha',
    r->>'resultado' = 'gravado' and pg_temp._tipos(r->'plano_mostrado'->'efeitos') = 'anexar_lancamento,ligar_linha,pendencia:classificar_no_extrato'
    and r->'plano_mostrado'->'efeitos'->1->>'acao' = 'casar'
    and pg_temp._tipos(c.efeitos) = 'anexar_lancamento,ligar_linha' and c.situacao = 'conciliado'
    and pg_temp._efeito(c.efeitos, 'ligar_linha')->>'como' = 'casou' and c.payable_id = v_pay
    and pay.bank_transaction_id = v_tx and pay.status = 'paid' and cardinality(c.pendencias) = 0
    and (select status from public.finance_review_queue where id = v_q) = 'superseded',
    'plano=' || pg_temp._tipos(r->'plano_mostrado'->'efeitos') || ' efeitos=' || pg_temp._tipos(c.efeitos) || ' pay=' || coalesce(pay.status, '-'));
exception when others then
  insert into _resultado values ('GV6 conta a pagar em aberto + linha verde: o sim casa a conta com a linha', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GV7 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_com uuid := pg_temp._freelancer(true);
  v_sem uuid := pg_temp._freelancer(false);
  v_val numeric := pg_temp._val();
  r jsonb;
  r2 jsonb;
  c record;
  c2 record;
  re record;
  d record;
begin
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'dinheiro', 'destino', 'os', 'os', v_os, 'cobrar', false,
                                       'quem', 'tecnico', 'pagador', v_com, 'cnpj', pg_temp._cnpj(), 'receita', 'Posto Teste F3'));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  select * into re from public.diarias_reembolsos where id = c.reembolso_id;
  select * into d from public.service_order_expenses where id = c.so_expense_id;
  perform pg_temp._guardar('GV7', c.id, null, v_com);
  r2 := pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'dinheiro', 'destino', 'os', 'os', v_os, 'cobrar', false,
                                        'quem', 'tecnico', 'pagador', v_sem, 'cnpj', pg_temp._cnpj()));
  select * into c2 from public.comprovantes where id = (r2->>'id')::uuid;
  insert into _resultado values ('GV7 técnico com diária: reembolso nas Diárias (sem pendência); sem diária: a pendência da F2 e o aviso',
    r->>'resultado' = 'gravado' and pg_temp._tipos(c.efeitos) = 'despesa_os,reembolso_tecnico'
    and re.status = 'ativo' and re.favorecido_id = v_com and re.valor = v_val and re.data = pg_temp._hoje()
    and re.origem_codigo = c.codigo and re.os_id = v_os and re.descricao = 'Reembolso ' || c.codigo || ' · Posto Teste F3'
    and re.criado_por = pg_temp._dono() and d.paid_by = 'technician' and not ('acerto_tecnico' = any (c.pendencias))
    -- a despesa da OS não fica "a reembolsar" também na aba Reembolsos (pagaria o mesmo gasto duas vezes)
    and d.reimbursed and d.reimbursed_at is not null
    and pg_temp._efeito(c.efeitos, 'reembolso_tecnico')->>'despesa_reembolsada' = d.id::text
    and pg_temp._efeito(c.efeitos, 'reembolso_tecnico')->>'reembolso_id' = re.id::text
    and r2->>'resultado' = 'gravado' and pg_temp._tipos(c2.efeitos) = 'despesa_os,nada,pendencia:acerto_tecnico'
    and c2.reembolso_id is null and r2->'gravacao'->'avisos' ? 'tecnico_fora_das_diarias',
    'com=' || pg_temp._tipos(c.efeitos) || ' sem=' || pg_temp._tipos(c2.efeitos) || ' avisos=' || coalesce(r2->'gravacao'->>'avisos', '-'));
exception when others then
  insert into _resultado values ('GV7 técnico com diária: reembolso nas Diárias (sem pendência); sem diária: a pendência da F2 e o aviso', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GX1 / GX2 / GX3 ═════════════════════════════════════════════════════════════════════════
do $$
declare
  k jsonb;
  k2 jsonb;
  k3 jsonb;
  v_cmp uuid := pg_temp._id('GV1');
  v_tx uuid := pg_temp._tx('GV1');
  v_q uuid := pg_temp._extra('GV1');
  v_anot uuid;
  q record;
  c record;
  c4 record;
  v_pay4 uuid;
begin
  -- GX1: ligada sem lançamento → cancelar desfaz e a linha volta ao motor
  select anotacao_id into v_anot from public.comprovantes where id = v_cmp;
  k := public.comprovante_cancelar(v_cmp, 'comprei errado no teste', pg_temp._dono());
  select * into q from public.finance_review_queue where id = v_q;
  select * into c from public.comprovantes where id = v_cmp;
  insert into _resultado values ('GX1 cancelar a ligada sem lançamento: desfaz e devolve a linha ao motor',
    (k->>'ok')::boolean and k->'desfeitos' @> '[{"tipo":"ligar_linha"}]'::jsonb
    and c.situacao = 'cancelado' and c.bank_transaction_id is null
    and not (q.evidencia ? 'anotacao') and q.confidence <= 50 and q.status = 'pending'
    and (select status from public.anotacoes_do_extrato where id = v_anot) = 'cancelada'
    and (select nome_pelo_comprovante from public.bank_transactions where id = v_tx) is null
    and not exists (select 1 from public.comprovantes where bank_transaction_id = v_tx and situacao <> 'cancelado'),
    coalesce(k::text, '-'));

  -- GX2: a linha do GV4 virou lançamento (aprovado no Extrato) → bloqueia, nada muda
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               bank_transaction_id, origin)
  select 'Aprovado no Extrato F3', pg_temp._hoje(), pg_temp._hoje(), t.amount, t.amount, 0, 'paid', 'Materiais e Insumos Operacionais', t.id, 'manual'
    from public.bank_transactions t where t.id = pg_temp._tx('GV4')
  returning id into v_pay4;
  k2 := public.comprovante_cancelar(pg_temp._id('GV4'), 'teste de bloqueio', pg_temp._dono());
  select * into c4 from public.comprovantes where id = pg_temp._id('GV4');
  -- GX3: a do GV6 foi casada → bloqueia
  k3 := public.comprovante_cancelar(pg_temp._id('GV6'), 'teste de bloqueio', pg_temp._dono());
  insert into _resultado values ('GX2/GX3 cancelar recusa: a linha virou lançamento (linha_lancada) ou foi casada (linha_casada)',
    not (k2->>'ok')::boolean and k2->'bloqueios' @> '[{"motivo":"linha_lancada"}]'::jsonb
    and c4.situacao = 'conciliado' and c4.bank_transaction_id = pg_temp._tx('GV4')
    and not (k3->>'ok')::boolean and k3->'bloqueios' @> '[{"motivo":"linha_casada"}]'::jsonb
    and (select situacao from public.comprovantes where id = pg_temp._id('GV6')) = 'conciliado',
    'gx2=' || coalesce(k2->>'bloqueios', '-') || ' gx3=' || coalesce(k3->>'bloqueios', '-'));
exception when others then
  insert into _resultado values ('GX1-GX3 cancelar a ligação', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GX4 / GX5 ═══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_b uuid := pg_temp._freelancer(true);
  k jsonb;
  k5 jsonb;
  r jsonb;
  c5 record;
  v_reemb4 uuid;
  v_acerto jsonb;
  v_cc jsonb;
begin
  -- GX4: reembolso no período aberto → cancelar tira o crédito
  select reembolso_id into v_reemb4 from public.comprovantes where id = pg_temp._id('GV7');
  k := public.comprovante_cancelar(pg_temp._id('GV7'), 'o técnico não pagou', pg_temp._dono());
  -- GX5: reembolso dentro de um acerto já fechado → bloqueia
  r := pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'dinheiro', 'destino', 'os', 'os', v_os, 'cobrar', false,
                                       'quem', 'tecnico', 'pagador', v_b, 'cnpj', pg_temp._cnpj()));
  select * into c5 from public.comprovantes where id = (r->>'id')::uuid;
  v_acerto := public.fechar_acerto_diarias(v_b, pg_temp._hoje(), false, pg_temp._dono());
  k5 := public.comprovante_cancelar(c5.id, 'teste do acerto fechado', pg_temp._dono());
  v_cc := public.conta_corrente_freelancer(v_b, null, null, pg_temp._dono(), null);
  insert into _resultado values ('GX4/GX5 cancelar o reembolso: período aberto tira o crédito; acerto fechado bloqueia',
    (k->>'ok')::boolean and (select status from public.diarias_reembolsos where id = v_reemb4) = 'cancelado'
    and (select motivo_cancelamento from public.diarias_reembolsos where id = v_reemb4) like 'CMP-% cancelado: o técnico não pagou'
    and (v_acerto->>'ok')::boolean and v_acerto->>'message' like '%· reembolsos R$ %'
    and not (k5->>'ok')::boolean and k5->'bloqueios' @> '[{"motivo":"reembolso_acertado"}]'::jsonb
    and k5->'bloqueios'->0->>'como_destravar' like 'reabra o acerto nº % em Financeiro › Diárias e cancele de novo'
    and (select status from public.diarias_reembolsos where id = c5.reembolso_id) = 'ativo'
    and (v_cc->>'reembolsos')::numeric = c5.valor_confirmado,
    'gx4=' || coalesce(k->>'ok', '-') || ' acerto=' || coalesce(v_acerto->>'message', '-') || ' gx5=' || coalesce(k5->>'bloqueios', '-'));
exception when others then
  insert into _resultado values ('GX4/GX5 cancelar o reembolso: período aberto tira o crédito; acerto fechado bloqueia', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GX6 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cnpj text := pg_temp._cnpj();
  v_sup uuid;
  v_tx uuid;
  v_q uuid;
  r jsonb;
  c record;
  k jsonb;
  q record;
  v_aplic integer;
  v_anot uuid;
begin
  -- a anotação do Pix foi aplicada à linha (falta aprovar) e o dono cancela antes da varredura ligar
  insert into public.suppliers (name, cnpj_cpf) values ('Fornecedor GX6 ' || pg_temp._letras(5), v_cnpj) returning id into v_sup;
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', v_cnpj, 'fornecedor', v_sup));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  v_anot := c.anotacao_id;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX', 'doc', v_cnpj, 'nome', 'FORNECEDOR GX6'));
  v_q := pg_temp._proposta(v_tx);
  update public.finance_review_queue set suggested_supplier_id = v_sup where id = v_q;
  v_aplic := public.aplicar_anotacoes_pendentes();
  k := public.comprovante_cancelar(c.id, 'teste da anotação aplicada', pg_temp._dono());
  select * into q from public.finance_review_queue where id = v_q;
  insert into _resultado values ('GX6 anotação aplicada sem lançamento: o cancelamento não bloqueia e a proposta volta ao motor',
    v_aplic >= 1 and (k->>'ok')::boolean and not (q.evidencia ? 'anotacao') and q.confidence <= 50
    and (select status from public.anotacoes_do_extrato where id = v_anot) = 'cancelada',
    'aplicadas=' || v_aplic || ' k=' || coalesce(k->>'ok', '-') || '/' || coalesce(k->>'bloqueios', '-'));
exception when others then
  insert into _resultado values ('GX6 anotação aplicada sem lançamento: o cancelamento não bloqueia e a proposta volta ao motor', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GN1 / GN2 / GN3 ═════════════════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_chave0 text := pg_temp._chave();
  v_chave1 text := pg_temp._chave();
  v_chave2 text := pg_temp._chave();
  v_chave3 text := pg_temp._chave();
  v_nota0 uuid;
  v_nota1 uuid;
  v_nota2 uuid;
  r0 jsonb;
  r1 jsonb;
  r2 jsonb;
  r3 jsonb;
  c0 record;
  c1 record;
  c2 record;
  c2b record;
  c3 record;
  v_r5_pendente jsonb;
  v_r5 jsonb;
  v_r5_vazio jsonb;
  v_pend jsonb;
begin
  -- GN1: a nota CONFIRMADA vale na gravação (os itens vão à OS); a ainda pendente (prévia da importação:
  -- sem as linhas, pode ser desistida) não — o CMP espera o XML
  insert into public.fiscal_notes (nfe_key, nfe_number, status) values (v_chave0, '10000', 'pending') returning id into v_nota0;
  insert into public.fiscal_note_items (fiscal_note_id, item_index, description) values (v_nota0, 1, 'item 1');
  perform pg_temp._confirmar_nota(v_nota0, 1);
  r0 := pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'tipo', 'nfe_danfe', 'chave', v_chave0,
                                        'destino', 'os', 'os', v_os, 'cobrar', true));
  select * into c0 from public.comprovantes where id = (r0->>'id')::uuid;
  insert into public.fiscal_notes (nfe_key, nfe_number, status) values (v_chave1, '11111', 'pending') returning id into v_nota1;
  insert into public.fiscal_note_items (fiscal_note_id, item_index, description) values (v_nota1, 1, 'item 1');
  r1 := pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'tipo', 'nfe_danfe', 'chave', v_chave1,
                                        'destino', 'os', 'os', v_os, 'cobrar', true));
  select * into c1 from public.comprovantes where id = (r1->>'id')::uuid;
  -- GN2: aguardando o XML; a nota entra pendente (process-nfe-xml): nada fecha; confirmada (Entrada de
  -- Mercadoria): a R5 (e o cron, até 2 min depois) fecha o CMP e liga os itens à OS
  r2 := pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'tipo', 'nfe_xml', 'chave', v_chave2,
                                        'destino', 'os', 'os', v_os, 'cobrar', false));
  select * into c2 from public.comprovantes where id = (r2->>'id')::uuid;
  if c2.situacao <> 'aguardando_xml' then
    raise exception 'GN2 deveria esperar o XML: %', c2.situacao;
  end if;
  insert into public.fiscal_notes (nfe_key, nfe_number, status) values (v_chave2, '22222', 'pending') returning id into v_nota2;
  insert into public.fiscal_note_items (fiscal_note_id, item_index, description) values (v_nota2, 1, 'item único');
  v_r5_pendente := public.comprovante_nota_chegou(v_nota2);
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c2 from public.comprovantes where id = c2.id;
  perform pg_temp._confirmar_nota(v_nota2, 1);
  v_r5 := public.comprovante_nota_chegou(v_nota2);
  v_r5_vazio := public.comprovante_nota_chegou(gen_random_uuid());
  select * into c2b from public.comprovantes where id = c2.id;
  -- GN3: a nota só chegou no e-mail (anexo ainda não importado): a varredura marca e o "pendentes" mostra
  r3 := pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'tipo', 'nfe_danfe', 'chave', v_chave3,
                                        'destino', 'os', 'os', v_os, 'cobrar', false));
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'email_messages' and column_name = 'account_id') then
    -- produção: uma conta de e-mail existente (o rollback desfaz)
    execute 'insert into public.email_messages (account_id, dedup_key, from_address, received_at, dados_extraidos)
             select a.id, $1, ''nfe@teste.invalido'', now(), $2 from public.email_accounts a limit 1'
      using 'teste-f3-' || gen_random_uuid(), jsonb_build_object('nfes', jsonb_build_array(jsonb_build_object('chave', v_chave3)));
  else
    execute 'insert into public.email_messages (from_address, received_at, dados_extraidos) values (''nfe@teste.invalido'', now(), $1)'
      using jsonb_build_object('nfes', jsonb_build_array(jsonb_build_object('chave', v_chave3)));
  end if;
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c3 from public.comprovantes where id = (r3->>'id')::uuid;
  v_pend := public.comprovantes_pendentes(pg_temp._phone());
  insert into _resultado values ('GN1-GN3 NF-e: só a nota confirmada vale (a pendente não tem linhas); a confirmada fecha o CMP (R5); a do e-mail aparece no "pendentes"',
    r0->>'resultado' = 'gravado' and c0.situacao = 'gravado' and c0.fiscal_note_id = v_nota0
    and pg_temp._tipos(c0.efeitos) like 'itens_da_nota%'
    and (select service_order_id from public.fiscal_note_items where fiscal_note_id = v_nota0) = v_os
    and r1->>'resultado' = 'gravado' and c1.situacao = 'aguardando_xml' and c1.fiscal_note_id is null
    and (select service_order_id from public.fiscal_note_items where fiscal_note_id = v_nota1) is null
    and v_r5_pendente = '{"fechados": []}'::jsonb and c2.situacao = 'aguardando_xml'
    and jsonb_array_length(v_r5->'fechados') = 1 and v_r5->'fechados'->0->>'codigo' = c2.codigo
    and (v_r5->'fechados'->0->>'itens')::integer = 1 and v_r5_vazio = '{"fechados": []}'::jsonb
    and c2b.situacao = 'gravado' and c2b.fiscal_note_id = v_nota2
    and (select service_order_id from public.fiscal_note_items where fiscal_note_id = v_nota2) = v_os
    and c3.situacao = 'aguardando_xml' and c3.nota_no_email_em is not null
    and exists (select 1 from jsonb_array_elements(v_pend->'abertos') a
                 where a->>'codigo' = c3.codigo and (a->>'nota_no_email')::boolean),
    'gn1=' || c0.situacao || '/' || c1.situacao || ' pendente=' || coalesce(v_r5_pendente::text, '-') || ' r5=' || coalesce(v_r5::text, '-')
    || ' gn3=' || c3.situacao || '/' || coalesce(c3.nota_no_email_em::text, 'sem marca'));
exception when others then
  insert into _resultado values ('GN1-GN3 NF-e: só a nota confirmada vale (a pendente não tem linhas); a confirmada fecha o CMP (R5); a do e-mail aparece no "pendentes"', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GI1 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  r jsonb;
  c record;
  v_mes date := date_trunc('month', pg_temp._hoje())::date;
  v_ind jsonb;
  v_pes jsonb;
  v_pend boolean;
begin
  update public.comprovantes_indice_pessoal set pendente = false where mes = v_mes;
  r := pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'credito', 'destino', 'pessoal', 'cnpj', pg_temp._cnpj()));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  select pendente into v_pend from public.comprovantes_indice_pessoal where mes = v_mes;
  v_ind := public.comprovantes_indice_do_mes(v_mes);
  v_pes := public.comprovantes_indice_pessoal_do_mes(v_mes);
  insert into _resultado values ('GI1 o índice da contadora não lista o PESSOAL; o gatilho marca o índice pessoal; a R7 lista',
    r->>'resultado' = 'gravado' and c.destino = 'pessoal'
    and not exists (select 1 from jsonb_array_elements(v_ind->'linhas') l where l->>'codigo' = c.codigo)
    and exists (select 1 from jsonb_array_elements(v_pes->'linhas') l where l->>'codigo' = c.codigo)
    and not exists (select 1 from jsonb_array_elements(v_pes->'linhas') l where l->>'destino' is distinct from 'pessoal')
    and v_pend and v_pes->>'mes' = to_char(v_mes, 'YYYY-MM'),
    'no_indice=' || exists (select 1 from jsonb_array_elements(v_ind->'linhas') l where l->>'codigo' = c.codigo)
    || ' pessoal_pendente=' || coalesce(v_pend::text, '-'));
exception when others then
  insert into _resultado values ('GI1 o índice da contadora não lista o PESSOAL; o gatilho marca o índice pessoal; a R7 lista', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GA1 (a linha ligada que o dono aprovou com outra categoria e sem a OS) ════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_val numeric := pg_temp._val();
  v_tx uuid;
  v_q uuid;
  v_pay uuid;
  r jsonb;
  c record;
  c2 record;
  p record;
  ef jsonb;
  k jsonb;
  v_r2 jsonb;
  v_desp uuid;
begin
  -- o SIM ligou e classificou a linha (Peças e materiais, a OS do CMP); o dono aprovou no Extrato com
  -- OUTRA categoria e sem a OS. A varredura (cron a cada 2 min e finance-review) só ADOTA o lançamento
  -- dele: nada de pôr de volta a categoria e a OS do CMP sem SIM. E cancelar o CMP recusa: o lançamento
  -- não é o que existia ao ligar (desfaz-se pelo Extrato).
  perform pg_temp._livrar_perguntas();
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val));
  v_q := pg_temp._proposta(v_tx);
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'destino', 'os', 'os', v_os, 'cobrar', false,
                                       'cnpj', pg_temp._cnpj(), 'receita', 'Loja GA1 F3'));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               bank_transaction_id, origin)
  values ('Aprovado pelo dono no Extrato (GA1)', pg_temp._hoje(), pg_temp._hoje(), v_val, v_val, 0, 'paid', 'Outras despesas', v_tx, 'manual')
  returning id into v_pay;
  update public.finance_review_queue set status = 'approved', decided_at = now() where id = v_q;
  perform public.comprovantes_reavaliar_banco('teste', null);
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c2 from public.comprovantes where id = c.id;
  select * into p from public.payables where id = v_pay;
  select linked_payable_id into v_desp from public.service_order_expenses where id = c2.so_expense_id;
  ef := pg_temp._efeito(c2.efeitos, 'ligar_linha');
  k := public.comprovante_cancelar(c.id, 'teste do GA1', pg_temp._dono());
  v_r2 := public.comprovantes_linhas_da_conciliacao(array[v_tx]);
  insert into _resultado values ('GA1 aprovada pelo dono depois da ligação: a varredura só adota (categoria e OS do dono ficam) e cancelar recusa',
    r->>'resultado' = 'gravado' and c.situacao = 'conciliado' and pg_temp._efeito(c.efeitos, 'ligar_linha')->>'como' = 'classificou'
    and p.expense_category = 'Outras despesas' and p.linked_service_order_id is null
    and c2.payable_id = v_pay and v_desp = v_pay
    and ef->>'como' = 'classificou' and coalesce((ef->>'lancado_depois')::boolean, false)
    and coalesce(ef->'corrigido', '{}'::jsonb) = '{}'::jsonb
    and not (k->>'ok')::boolean and k->'bloqueios' @> '[{"motivo":"linha_lancada"}]'::jsonb
    and (select situacao from public.comprovantes where id = c.id) = 'conciliado'
    and jsonb_array_length(v_r2->'linhas') = 0,
    'categoria=' || coalesce(p.expense_category, '-') || ' os=' || coalesce(p.linked_service_order_id::text, 'nenhuma')
    || ' como=' || coalesce(ef->>'como', '-') || ' depois=' || coalesce(ef->>'lancado_depois', '-')
    || ' cancelar=' || coalesce(k->'bloqueios'->0->>'motivo', k->>'ok', '-') || ' r2=' || jsonb_array_length(v_r2->'linhas'));
exception when others then
  insert into _resultado values ('GA1 aprovada pelo dono depois da ligação: a varredura só adota (categoria e OS do dono ficam) e cancelar recusa', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GA2 (conta a pagar em aberto + a linha já lançada em outro registro) ══════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v_cnpj text := pg_temp._cnpj();
  v_sup uuid;
  v_p1 uuid;
  v_p2 uuid;
  v_tx uuid;
  r jsonb;
  c record;
  cc public.comprovantes;
  av jsonb;
  p jsonb;
  v_msg uuid;
  resp jsonb;
  c2 record;
  k jsonb;
begin
  -- o mesmo gasto duas vezes: a conta a pagar em aberto (P1) que o CMP anexa e a linha do Pix que já
  -- virou outro lançamento (P2). Nunca verde; o plano avisa e não liga; escolher a linha na pergunta não
  -- liga ("cancele um dos dois"); cancelar o CMP não esbarra no P2.
  perform pg_temp._livrar_perguntas();
  insert into public.suppliers (name, cnpj_cpf) values ('Fornecedor GA2 ' || pg_temp._letras(5), v_cnpj) returning id into v_sup;
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               supplier_id, origin)
  values ('Conta aberta GA2', pg_temp._hoje(), pg_temp._hoje() + 5, v_val, 0, v_val, 'pending', 'Materiais e Insumos Operacionais', v_sup, 'manual')
  returning id into v_p1;
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val, 'descricao', 'PIX ENVIADO', 'metodo', 'PIX', 'doc', v_cnpj, 'nome', 'FORNECEDOR GA2'));
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               bank_transaction_id, origin)
  values ('Lançado à parte (GA2)', pg_temp._hoje(), pg_temp._hoje(), v_val, v_val, 0, 'paid', 'Outras despesas', v_tx, 'manual')
  returning id into v_p2;
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', v_cnpj, 'fornecedor', v_sup));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  select * into cc from public.comprovantes where id = c.id;
  av := public._comprovante_candidatos(cc);
  perform pg_temp._livrar_perguntas();
  p := public.comprovante_banco_proxima(pg_temp._phone(), 'cmp', c.id);
  perform public.pergunta_marcar_enviada((p->>'pergunta_id')::uuid, 'WA-' || (p->>'pergunta_id'));
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', pg_temp._phone(), 'text', '1', 'TESTE-F3-' || gen_random_uuid(), now() + interval '10 seconds')
  returning id into v_msg;
  resp := public.comprovante_banco_responder(jsonb_build_object('pergunta_id', p->>'pergunta_id', 'message_id', v_msg,
            'interpretacao', '{"tipo":"opcao","n":1}'::jsonb, 'autor', pg_temp._dono()));
  select * into c2 from public.comprovantes where id = c.id;
  k := public.comprovante_cancelar(c.id, 'teste do GA2', pg_temp._dono());
  insert into _resultado values ('GA2 conta em aberto + linha já lançada em outro registro: nunca verde, não liga, avisa; cancelar não esbarra no outro lançamento',
    r->>'resultado' = 'gravado' and r->'plano_mostrado'->'avisos' ? 'conta_aberta_e_linha_lancada'
    and not exists (select 1 from jsonb_array_elements(c.efeitos) e where e->>'tipo' = 'ligar_linha')
    and c.situacao = 'aguardando_banco' and c.payable_id = v_p1
    and av->>'nivel' = 'azul' and av->'linhas'->0->>'acao' = 'conflito' and not (av->'linhas'->0->>'forte')::boolean
    and av->'linhas'->0->'conta_aberta' is not null and av->'linhas'->0->'conta_aberta' <> 'null'::jsonb
    and p->>'perguntou' = 'true' and resp->>'resultado' = 'nao_ligado' and resp->>'motivo' = 'conflito'
    and c2.bank_transaction_id is null and c2.situacao = 'aguardando_banco'
    and (select status from public.payables where id = v_p1) = 'pending'
    and (k->>'ok')::boolean
    and (select status from public.payables where id = v_p2) = 'paid' and (select status from public.payables where id = v_p1) = 'pending',
    'avisos=' || coalesce(r->'plano_mostrado'->>'avisos', '-') || ' nivel=' || coalesce(av->>'nivel', '-')
    || ' acao=' || coalesce(av->'linhas'->0->>'acao', '-') || ' resp=' || coalesce(resp->>'resultado', '-') || '/' || coalesce(resp->>'motivo', '-')
    || ' cancelar=' || coalesce(k->>'ok', '-'));
exception when others then
  insert into _resultado values ('GA2 conta em aberto + linha já lançada em outro registro: nunca verde, não liga, avisa; cancelar não esbarra no outro lançamento', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GR1 (a despesa da OS paga pelo técnico não fica "a reembolsar" em dois lugares) ═══════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_tec uuid := pg_temp._freelancer(true);
  v_cnpj text := pg_temp._cnpj();
  v_sup uuid;
  v_val numeric := pg_temp._val();
  v_val2 numeric := pg_temp._val();
  v_e1 uuid;
  v_e2 uuid;
  r1 jsonb;
  r2 jsonb;
  c1 record;
  c2 record;
  e1 record;
  e1b record;
  k jsonb;
begin
  -- o técnico lançou a despesa no app (paga por ele, a reembolsar) e mandou o cupom: o CMP anexa e o
  -- reembolso vai às Diárias — a despesa passa a "reembolsada" (sai da aba Financeiro › Reembolsos, que
  -- pagaria o mesmo gasto outra vez). Cancelar volta. Já reembolsada pela aba: nenhum crédito nas Diárias.
  insert into public.suppliers (name, cnpj_cpf) values ('Posto GR1 ' || pg_temp._letras(5), v_cnpj) returning id into v_sup;
  insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date, paid_by,
                                             billable_to_client, supplier_id, reimbursed)
  values (v_os, 'Peças e materiais', 'Despesa do técnico pelo app (GR1)', v_val, pg_temp._hoje(), 'technician', false, v_sup, false)
  returning id into v_e1;
  r1 := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'dinheiro', 'destino', 'os', 'os', v_os, 'cobrar', false,
                                        'quem', 'tecnico', 'pagador', v_tec, 'fornecedor', v_sup, 'cnpj', v_cnpj));
  select * into c1 from public.comprovantes where id = (r1->>'id')::uuid;
  select * into e1 from public.service_order_expenses where id = v_e1;
  k := public.comprovante_cancelar(c1.id, 'teste do GR1', pg_temp._dono());
  select * into e1b from public.service_order_expenses where id = v_e1;
  insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date, paid_by,
                                             billable_to_client, supplier_id, reimbursed, reimbursed_at)
  values (v_os, 'Peças e materiais', 'Despesa já reembolsada (GR1)', v_val2, pg_temp._hoje(), 'technician', false, v_sup, true, now())
  returning id into v_e2;
  r2 := pg_temp._cmp(jsonb_build_object('valor', v_val2, 'forma', 'dinheiro', 'destino', 'os', 'os', v_os, 'cobrar', false,
                                        'quem', 'tecnico', 'pagador', v_tec, 'fornecedor', v_sup, 'cnpj', v_cnpj));
  select * into c2 from public.comprovantes where id = (r2->>'id')::uuid;
  insert into _resultado values ('GR1 despesa da OS paga pelo técnico: reembolsada pelas Diárias (sai da aba Reembolsos); cancelar volta; já reembolsada não ganha outro crédito',
    r1->>'resultado' = 'gravado' and pg_temp._tipos(c1.efeitos) = 'anexar_despesa,reembolso_tecnico' and c1.so_expense_id = v_e1
    and e1.reimbursed and e1.reimbursed_at is not null
    and pg_temp._efeito(c1.efeitos, 'reembolso_tecnico')->>'despesa_reembolsada' = v_e1::text
    and (k->>'ok')::boolean and not e1b.reimbursed and e1b.reimbursed_at is null
    and (select status from public.diarias_reembolsos where id = c1.reembolso_id) = 'cancelado'
    and r2->>'resultado' = 'gravado' and pg_temp._tipos(c2.efeitos) = 'anexar_despesa,nada' and c2.reembolso_id is null
    and pg_temp._efeito(c2.efeitos, 'nada')->>'motivo' = 'ja_reembolsado'
    and r2->'plano_mostrado'->'avisos' ? 'despesa_ja_reembolsada'
    and not exists (select 1 from public.diarias_reembolsos where origem_codigo = c2.codigo),
    'com=' || pg_temp._tipos(c1.efeitos) || ' reembolsada=' || coalesce(e1.reimbursed::text, '-') || '→' || coalesce(e1b.reimbursed::text, '-')
    || ' ja=' || pg_temp._tipos(c2.efeitos) || ' avisos=' || coalesce(r2->'plano_mostrado'->>'avisos', '-'));
exception when others then
  insert into _resultado values ('GR1 despesa da OS paga pelo técnico: reembolsada pelas Diárias (sai da aba Reembolsos); cancelar volta; já reembolsada não ganha outro crédito', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GT1 (a diária tem de valer na data da compra e hoje) ══════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_tec uuid;
  r jsonb;
  c record;
begin
  -- era diarista na data da compra, mas passou para empreitada: o acerto das Diárias não é mais dele —
  -- o reembolso fica como a pendência da F2 (com o aviso), não numa conta corrente que ninguém acerta
  insert into public.payees (name, kind, active, conta_corrente_desde)
  values ('Técnico Empreitada F3 ' || pg_temp._letras(5), 'diarista', true, pg_temp._hoje() - 90)
  returning id into v_tec;
  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio, vigencia_fim)
  values (v_tec, 'freelancer', 'diaria', 300, pg_temp._hoje() - 90, pg_temp._hoje() - 15);
  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, vigencia_inicio)
  values (v_tec, 'freelancer', 'empreitada', pg_temp._hoje() - 14);
  r := pg_temp._cmp(jsonb_build_object('valor', pg_temp._val(), 'forma', 'dinheiro', 'destino', 'os', 'os', v_os, 'cobrar', false,
                                       'quem', 'tecnico', 'pagador', v_tec, 'cnpj', pg_temp._cnpj(), 'data', pg_temp._hoje() - 20));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  insert into _resultado values ('GT1 técnico que saiu das Diárias (diária vencida, hoje empreitada): a pendência da F2 com o aviso, nenhum reembolso',
    r->>'resultado' = 'gravado' and pg_temp._tipos(c.efeitos) = 'despesa_os,nada,pendencia:acerto_tecnico'
    and c.reembolso_id is null and r->'gravacao'->'avisos' ? 'tecnico_fora_das_diarias'
    and not exists (select 1 from public.diarias_reembolsos where origem_codigo = c.codigo),
    'efeitos=' || pg_temp._tipos(c.efeitos) || ' avisos=' || coalesce(r->'gravacao'->>'avisos', '-') || ' data=' || coalesce(c.data_confirmada::text, '-'));
exception when others then
  insert into _resultado values ('GT1 técnico que saiu das Diárias (diária vencida, hoje empreitada): a pendência da F2 com o aviso, nenhum reembolso', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ GD1 (a linha ligada foi estornada no banco) ══════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_val numeric := pg_temp._val();
  v_tx uuid;
  r jsonb;
  c record;
  c2 record;
begin
  -- o débito ligado (e classificado) foi estornado: a varredura desliga a linha (dispensada nunca volta
  -- como candidata) e deixa a pendência para o dono decidir a despesa da OS
  v_tx := pg_temp._linha(jsonb_build_object('valor', v_val));
  perform pg_temp._proposta(v_tx);
  r := pg_temp._cmp(jsonb_build_object('valor', v_val, 'forma', 'debito', 'destino', 'os', 'os', v_os, 'cobrar', false, 'cnpj', pg_temp._cnpj()));
  select * into c from public.comprovantes where id = (r->>'id')::uuid;
  update public.bank_transactions set dismissed_kind = 'estornada', dismissed_reason = 'estorno (teste F3)', dismissed_at = now()
   where id = v_tx;
  perform public.comprovantes_reavaliar_banco('teste', null);
  select * into c2 from public.comprovantes where id = c.id;
  insert into _resultado values ('GD1 a linha ligada foi estornada: desliga e deixa a pendência "conferir o estorno" (a despesa da OS fica para o dono)',
    c.situacao = 'conciliado' and c.bank_transaction_id = v_tx
    and c2.situacao = 'aguardando_banco' and c2.bank_transaction_id is null and 'conferir_estorno' = any (c2.pendencias)
    and exists (select 1 from public.service_order_expenses where id = c2.so_expense_id)
    and exists (select 1 from jsonb_array_elements(c2.efeitos) e where e->>'desligado_motivo' = 'linha_dispensada'),
    'antes=' || c.situacao || ' depois=' || c2.situacao || ' pendencias=' || array_to_string(c2.pendencias, ','));
exception when others then
  insert into _resultado values ('GD1 a linha ligada foi estornada: desliga e deixa a pendência "conferir o estorno" (a despesa da OS fica para o dono)', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
