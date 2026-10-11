-- Prova: gravação depois do sim e cancelamento (migration 20261011203000; usa 20261011200000-202000).
--
-- Uma linha por cenário da matriz 2.6.1 da spec da F2 (A-L) + A1/A2/A3 + anti-duplicado + cada linha
-- da tabela de cancelamento (desfaz e bloqueia). Revisão de 11/10/2026: anexar só do que não contradiz
-- (AD), conta a pagar já aberta (PL/CA), a mesma compra em dois CMPs (MC), a nota reprocessada (NR), a
-- OS que mudou depois do sim (XF) e o fornecedor que não vai à rota (FH).
-- Ajustes do dono (11/10/2026): o comprovante nunca é cobrado do cliente — a despesa da OS é custo
-- INTERNO (não faturável, origem = o CMP) e o total da OS não muda em NENHUM status (A, DI, S, XF); o
-- lançamento que já está na OS só é comprovado (AN: despesa, peça, ambíguo; peça sem candidata = a
-- pendência de lançá-la); o link público não vê o custo interno e vê a despesa manual (LP); o PESSOAL que
-- a empresa pagou é gasto pessoal do sócio (L2); o lançamento que já existe só ganha o vazio (A3).
--
-- O caminho é o de verdade: o CMP entra na fila, a pergunta do confirmar é aberta pela RPC 7 e o sim
-- vai pela RPC 9 (comprovante_responder), que chama _comprovante_gravar e as rotas.
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado P3 da spec da F2; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/comprovantes_gravacao.sql --output json
--
-- Seguro em produção: tudo dentro da transação e ROLLBACK no fim (as rotas reais —
-- so_expense_add, anotar_transacao, lancar_no_caixa, cancelar_lancamento, corrigir_lancamento —
-- gravam e são desfeitas). Dono de teste (admin com created_at em 2000), OS/clientes/barcos/notas de
-- mentira, valores aleatórios (não casam com o extrato real), o mês fechado é o de 25 anos atrás.
-- No PGlite as rotas financeiras são dublês e public.ensaio_respostas escolhe o resultado; em
-- produção (sem essa tabela) A2 e A3 rodam com a rota real e o teste só confere que o resultado
-- que ela devolveu foi gravado de forma coerente.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (dono uuid, phone text, socio uuid, tecnico uuid) on commit drop;
create temp table _cmps (nome text primary key, id uuid, os uuid, valor numeric, extra uuid) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._telefone() returns text language sql volatile as $$
  select '55000' || lpad((floor(random() * 1000000000))::bigint::text, 9, '0')
$$;
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;
create function pg_temp._val() returns numeric language sql volatile as $$
  select round((1000 + random() * 8000)::numeric, 2)
$$;
create function pg_temp._hoje() returns date language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;
-- CNPJ de mentira de quem recebe o Pix (raiz 7xxxxxxx: nunca a da HBR). A anotação "antes do banco"
-- é do Pix ao CNPJ: com a F3 instalada (20261011303000), o débito e o Pix sem o CNPJ de quem recebeu
-- esperam a linha pela pergunta do extrato em vez de anotar — os testes da anotação usam o Pix ao CNPJ,
-- que anota nos dois esquemas (e a situação é "gravado" na F2, "aguardando_banco" com a F3).
create function pg_temp._cnpj() returns text language sql volatile as $$
  select '7' || lpad((floor(random() * 9999999))::bigint::text, 7, '0') || '0001' || lpad((floor(random() * 99))::bigint::text, 2, '0')
$$;

do $$
declare
  v_dono uuid := gen_random_uuid();
  v_phone text := pg_temp._telefone();
  v_socio uuid;
  v_tec uuid;
begin
  insert into public.app_users (id, full_name, email, role, active, phone_normalized, ai_whatsapp_enabled, created_at)
  values (v_dono, 'Dono de teste F2', 'teste-f2-' || v_dono || '@teste.invalido', 'admin', true, v_phone, true,
          now() - interval '30 years');
  insert into public.app_settings (key, value) values ('comprovante_fluxo', 'dono')
  on conflict (key) do update set value = excluded.value;
  insert into public.app_settings (key, value) values ('comprovante_conversa', 'on')
  on conflict (key) do update set value = excluded.value;
  insert into public.payees (name, kind, active, app_user_id) values ('Sócio Teste F2', 'socio', true, v_dono) returning id into v_socio;
  insert into public.payees (name, kind, active) values ('Técnico Teste F2', 'prestador', true) returning id into v_tec;
  insert into _ctx values (v_dono, v_phone, v_socio, v_tec);
end $$;

create function pg_temp._dono() returns uuid language sql stable as $$ select dono from _ctx $$;
create function pg_temp._phone() returns text language sql stable as $$ select phone from _ctx $$;
create function pg_temp._id(p_nome text) returns uuid language sql stable as $$ select id from _cmps where nome = p_nome $$;

-- a rota financeira devolve o resultado escolhido (só no ensaio, com os dublês); false = rota real
create function pg_temp._rota(p_rota text, p_resposta jsonb) returns boolean language plpgsql as $$
begin
  if to_regclass('public.ensaio_respostas') is null then
    return false;
  end if;
  execute 'insert into public.ensaio_respostas (rota, resposta) values ($1, $2)' using p_rota, p_resposta;
  return true;
end $$;

create function pg_temp._os(p_status text default 'open', p_assinada boolean default false, p_invoicing text default 'not_invoiced')
returns uuid language plpgsql as $$
declare
  v_cli uuid;
  v_ves uuid;
  v_os uuid;
  v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number = 'OS-' || v_num) loop
    v_num := v_num + 1;
  end loop;
  insert into public.clients (type, name) values ('individual', 'Cliente Teste F2 ' || pg_temp._letras(6)) returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Navio' || pg_temp._letras(8)) returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, invoicing_status,
                                     grand_total, operational_cost_total, labor_cost_total, travel_cost_total, signed_at, check_out_at)
  values ('OS-' || v_num, v_cli, v_ves, p_status, p_invoicing, 0, 0, 0, 0,
          case when p_assinada then now() end, case when p_status in ('completed', 'invoiced') then now() end)
  returning id into v_os;
  return v_os;
end $$;

-- chave de NF-e modelo 55 (44 dígitos) de mentira
create function pg_temp._chave() returns text language sql volatile as $$
  select '352610' || '112223330001' || '81' || '55' || '001'
         || lpad((floor(random() * 999999999))::bigint::text, 9, '0') || '1'
         || lpad((floor(random() * 99999999))::bigint::text, 8, '0') || '0'
$$;

-- CMP já lido e na fila, com as respostas dadas (as perguntas têm teste próprio)
create function pg_temp._preparar(p jsonb) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized,
                                   tipo_whatsapp, recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca,
                                   data_compra, data_confianca, forma_pagamento, chave_acesso, lido_em,
                                   emitente_cnpj, cnpj_confianca, favorecido_doc, supplier_id)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(),
          'TESTE-F2-' || gen_random_uuid(), pg_temp._phone(), 'image', now(),
          md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text),
          coalesce(p->>'tipo', 'nfce'), 'alta', (p->>'valor')::numeric, 'alta',
          coalesce((p->>'data')::date, pg_temp._hoje()), 'alta', p->>'forma', p->>'chave', now(),
          p->>'cnpj', case when p ? 'cnpj' then 'alta' end, p->>'favorecido', nullif(p->>'fornecedor', '')::uuid)
  returning id into v;
  perform public.comprovante_conversa_entrar(array[v]);
  update public.comprovantes
     set destino = p->>'destino', destino_os_id = nullif(p->>'os', '')::uuid, tipo_na_os = p->>'tipo_na_os',
         quem_pagou = p->>'quem', pagador_payee_id = nullif(p->>'pagador', '')::uuid, categoria = p->>'categoria'
   where id = v;
  return v;
end $$;

-- o sim como o edge manda: a pergunta saiu (whatsapp-send confirmou) e a mensagem do dono é de DEPOIS
create function pg_temp._sim(p_pergunta jsonb) returns jsonb language plpgsql as $$
declare
  v_msg uuid;
begin
  perform public.pergunta_marcar_enviada((p_pergunta->>'pergunta_id')::uuid, 'WA-' || (p_pergunta->>'pergunta_id'));
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', pg_temp._phone(), 'text', 'sim', 'TESTE-F2-' || gen_random_uuid(), now() + interval '10 seconds')
  returning id into v_msg;
  return public.comprovante_responder(jsonb_build_object(
    'pergunta_id', p_pergunta->>'pergunta_id', 'message_id', v_msg, 'interpretacao', jsonb_build_object('tipo', 'sim')));
end $$;

-- abre o resumo (RPC 7) e responde sim (RPC 9); devolve a saída do responder + o plano mostrado
create function pg_temp._gravar(p_cmp uuid) returns jsonb language plpgsql as $$
declare
  v_p jsonb;
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste'
   where phone_normalized = pg_temp._phone() and status = 'aberta';
  update public.comprovantes set situacao = 'aguardando_vez'
   where phone_normalized = pg_temp._phone() and situacao in ('perguntando', 'aguardando_sim');
  -- os outros da fila não atrapalham: saem para o fim
  update public.comprovantes set fila_ordem = now() + interval '1 day'
   where phone_normalized = pg_temp._phone() and situacao = 'aguardando_vez' and id <> p_cmp;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', p_cmp);
  if not coalesce((v_p->>'perguntou')::boolean, false) or v_p->>'passo' is distinct from 'confirmar' then
    return jsonb_build_object('resultado', 'nao_chegou_no_confirmar', 'pergunta', v_p);
  end if;
  return pg_temp._sim(v_p) || jsonb_build_object('plano_mostrado', v_p->'plano', 'avisos_mostrados', v_p->'avisos');
end $$;

create function pg_temp._tipos(p_efeitos jsonb) returns text language sql immutable as $$
  select coalesce(string_agg(e->>'tipo' || case when e->>'tipo' = 'pendencia' then ':' || (e->>'qual') else '' end, ',' order by o), '')
    from jsonb_array_elements(coalesce(p_efeitos, '[]'::jsonb)) with ordinality as t(e, o)
$$;

create function pg_temp._guarda(p_nome text, p_id uuid, p_os uuid, p_valor numeric, p_extra uuid default null) returns void language sql as $$
  insert into _cmps values (p_nome, p_id, p_os, p_valor, p_extra) on conflict (nome) do update
    set id = excluded.id, os = excluded.os, valor = excluded.valor, extra = excluded.extra
$$;

create function pg_temp._mes(p date) returns date language sql immutable as $$ select date_trunc('month', p)::date $$;

-- ═══ A / A1: a despesa da OS é custo interno (ajustes do dono, 11/10/2026) ═══════════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  r jsonb;
  c record;
  d record;
  a record;
  o record;
begin
  v_cmp := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', pg_temp._cnpj(),
                                                'destino', 'os', 'os', v_os, 'tipo_na_os', 'despesa',
                                                'categoria', 'Combustível e deslocamento'));
  r := pg_temp._gravar(v_cmp);
  select * into c from public.comprovantes where id = v_cmp;
  select * into d from public.service_order_expenses where id = c.so_expense_id;
  select * into a from public.anotacoes_do_extrato where id = c.anotacao_id;
  select grand_total, operational_cost_total into o from public.service_orders where id = v_os;
  perform pg_temp._guarda('A', v_cmp, v_os, v_val);
  insert into _resultado values ('A/A1 OS aberta, Pix ao CNPJ: a despesa é custo interno (não faturável, origem = o CMP, total igual) + anotação',
    r->>'resultado' = 'gravado' and pg_temp._tipos(c.efeitos) = 'despesa_os,anotar' and c.efeitos->1->>'resultado' = 'aguardando'
    and c.situacao in ('gravado', 'aguardando_banco') and c.gravado_por = pg_temp._dono() and c.aguardando_banco_desde is not null
    and not d.billable_to_client and d.origem_codigo = c.codigo and d.amount = v_val and d.paid_by = 'company'
    and d.category = 'Combustível e deslocamento'
    and d.created_by = pg_temp._dono() and d.notes = c.codigo and d.description like c.codigo || ' · %'
    and o.grand_total = 0 and o.operational_cost_total = 0
    and a.status = 'aguardando' and a.valor = v_val and a.os_id = v_os and a.categoria = 'Combustível e deslocamento'
    and a.descricao like c.codigo || ' · %' and a.sentido = 'debit'
    and c.dropbox_pendente = 'mover' and c.indice_mes = pg_temp._mes(pg_temp._hoje())
    and (select pendente from public.comprovantes_indice_mensal where mes = c.indice_mes)
    and c.plano = r->'plano_mostrado' and c.quem_pagou = 'empresa' and c.categoria = 'Combustível e deslocamento'
    and c.tipo_na_os = 'despesa' and jsonb_array_length(r->'plano_mostrado'->'avisos') = 0,
    'resultado=' || coalesce(r->>'resultado', '-') || ' ' || coalesce(r->>'motivo', '') || ' efeitos=' || pg_temp._tipos(c.efeitos)
    || ' despesa=' || coalesce(d.amount::text, '-') || '/' || coalesce(d.origem_codigo, '-') || ' anotacao=' || coalesce(a.status, '-'));
exception when others then
  insert into _resultado values ('A/A1 OS aberta, Pix ao CNPJ: a despesa é custo interno (não faturável, origem = o CMP, total igual) + anotação', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ A2 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  v_dubla boolean;
  r jsonb;
  c record;
  v_status text;
begin
  v_dubla := pg_temp._rota('anotar_transacao', '{"modo":"aplicada"}');
  v_cmp := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', pg_temp._cnpj(),
                                                'destino', 'os', 'os', v_os, 'tipo_na_os', 'despesa',
                                                'categoria', 'Combustível e deslocamento'));
  r := pg_temp._gravar(v_cmp);
  select * into c from public.comprovantes where id = v_cmp;
  select status into v_status from public.anotacoes_do_extrato where id = c.anotacao_id;
  perform pg_temp._guarda('A2', v_cmp, v_os, v_val);
  insert into _resultado values ('A2 a linha já estava na fila: anotação aplicada (falta aprovar no Extrato)',
    r->>'resultado' = 'gravado' and c.anotacao_id is not null and c.aguardando_banco_desde is not null
    and case when v_dubla then c.efeitos->1->>'resultado' = 'aplicada' and v_status = 'aplicada'
             else c.efeitos->1->>'resultado' = v_status or (c.efeitos->1->>'resultado' = 'aguardando' and v_status = 'aguardando') end,
    case when v_dubla then 'dublê' else 'rota real (resultado ' || coalesce(c.efeitos->1->>'resultado', '-') || ')' end
    || ' efeitos=' || pg_temp._tipos(c.efeitos) || ' anotacao=' || coalesce(v_status, '-'));
exception when others then
  insert into _resultado values ('A2 a linha já estava na fila: anotação aplicada (falta aprovar no Extrato)', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ A3: a linha já virou lançamento — só concilia e comprova (resposta 8 do dono, 11/10/2026) ════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_os2 uuid := pg_temp._os('open');
  v_val numeric := pg_temp._val();
  v_val2 numeric := pg_temp._val();
  v_pay uuid;
  v_pay2 uuid;
  v_cmp uuid;
  v_cmp2 uuid;
  v_dubla boolean;
  r jsonb;
  r2 jsonb;
  c record;
  c2 record;
  p record;
  p2 record;
  p3 record;
  p4 record;
  v_canc jsonb;
  v_canc2 jsonb;
  v_ligada uuid;
  v_falhas text[];
begin
  if to_regclass('public.ensaio_respostas') is null then
    insert into _resultado values ('A3 a linha já virou lançamento: só preenche o vazio (OS, categoria), avisa a categoria diferente; cancelar volta só o que preencheu', true,
      'pulado em produção: forçar "já lançada" pede o dublê do ensaio (A1 cobre a rota real)');
    return;
  end if;
  -- (1) o lançamento já tem categoria: não troca (avisa); a OS vazia é preenchida
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category, origin)
  values ('linha do banco de teste', pg_temp._hoje(), pg_temp._hoje(), v_val, v_val, 0, 'paid', 'Outras despesas', 'bank_reconciliation')
  returning id into v_pay;
  v_dubla := pg_temp._rota('anotar_transacao', jsonb_build_object('modo', 'ja_lancada', 'lancamento_id', v_pay));
  v_cmp := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'pix', 'tipo', 'pix', 'favorecido', pg_temp._cnpj(),
                                                'destino', 'os', 'os', v_os, 'tipo_na_os', 'despesa',
                                                'categoria', 'Combustível e deslocamento'));
  r := pg_temp._gravar(v_cmp);
  -- (2) o lançamento sem categoria e sem OS: ganha as duas
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category, origin)
  values ('linha do banco de teste 2', pg_temp._hoje(), pg_temp._hoje(), v_val2, v_val2, 0, 'paid', null, 'bank_reconciliation')
  returning id into v_pay2;
  perform pg_temp._rota('anotar_transacao', jsonb_build_object('modo', 'ja_lancada', 'lancamento_id', v_pay2));
  v_cmp2 := pg_temp._preparar(jsonb_build_object('valor', v_val2, 'forma', 'pix', 'tipo', 'pix', 'favorecido', pg_temp._cnpj(),
                                                 'destino', 'os', 'os', v_os2, 'tipo_na_os', 'despesa',
                                                 'categoria', 'Combustível e deslocamento'));
  r2 := pg_temp._gravar(v_cmp2);
  select * into c from public.comprovantes where id = v_cmp;
  select * into c2 from public.comprovantes where id = v_cmp2;
  select * into p from public.payables where id = v_pay;
  select * into p2 from public.payables where id = v_pay2;
  select linked_payable_id into v_ligada from public.service_order_expenses where id = c.so_expense_id;
  v_canc := public.comprovante_cancelar(v_cmp, 'teste do A3', pg_temp._dono());
  v_canc2 := public.comprovante_cancelar(v_cmp2, 'teste do A3', pg_temp._dono());
  select * into p3 from public.payables where id = v_pay;
  select * into p4 from public.payables where id = v_pay2;
  select array_agg(nome) into v_falhas from (values
    ('gravou', r->>'resultado' = 'gravado' and pg_temp._tipos(c.efeitos) = 'despesa_os,anexar_lancamento'),
    ('anexou', c.payable_id = v_pay and c.anotacao_id is null),
    ('nao_trocou_a_categoria', p.expense_category = 'Outras despesas'
                               and not coalesce(c.efeitos->1->'corrigido' ? 'expense_category', false)),
    ('avisou', r->'gravacao'->'avisos' @> '["categoria_existente_diferente"]'::jsonb
               and c.efeitos->1->>'categoria_existente' = 'Outras despesas'),
    ('preencheu_a_os', p.linked_service_order_id = v_os
                       and c.efeitos->1->'corrigido'->'linked_service_order_id'->>'depois' = v_os::text),
    ('despesa_ligada', v_ligada = v_pay),
    ('preencheu_o_vazio', r2->>'resultado' = 'gravado' and p2.expense_category = 'Combustível e deslocamento'
                          and p2.linked_service_order_id = v_os2 and c2.efeitos->1->'corrigido' ? 'expense_category'
                          and not (r2->'gravacao'->'avisos' @> '["categoria_existente_diferente"]'::jsonb)),
    ('cancelou', (v_canc->>'ok')::boolean and (v_canc2->>'ok')::boolean),
    ('voltou_so_o_que_preencheu', p3.expense_category = 'Outras despesas' and p3.linked_service_order_id is null and p3.status = 'paid'
                                  and p4.expense_category is null and p4.linked_service_order_id is null and p4.status = 'paid'),
    ('tirou_o_custo_interno', not exists (select 1 from public.service_order_expenses where service_order_id in (v_os, v_os2)))
  ) as t(nome, ok) where not coalesce(ok, false);
  insert into _resultado values ('A3 a linha já virou lançamento: só preenche o vazio (OS, categoria), avisa a categoria diferente; cancelar volta só o que preencheu',
    v_falhas is null,
    coalesce('falhou: ' || array_to_string(v_falhas, ', ') || ' | ', '')
    || 'efeitos=' || pg_temp._tipos(c.efeitos) || ' categoria=' || coalesce(p.expense_category, '-') || '→' || coalesce(p3.expense_category, '-')
    || ' vazio=' || coalesce(p2.expense_category, 'null') || '→' || coalesce(p4.expense_category, 'null'));
exception when others then
  insert into _resultado values ('A3 a linha já virou lançamento: só preenche o vazio (OS, categoria), avisa a categoria diferente; cancelar volta só o que preencheu', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ DI: o custo interno em OS concluída e faturada — o total nunca muda (ajustes do dono) ══════
do $$
declare
  v_osb uuid := pg_temp._os('completed');
  v_osc uuid := pg_temp._os('invoiced', false, 'invoiced');
  v_vb numeric := pg_temp._val();
  v_vc numeric := pg_temp._val();
  v_b uuid;
  v_c uuid;
  rb jsonb;
  rc jsonb;
  cb record;
  cc record;
  db record;
  dc record;
  ob0 record; ob1 record; oc0 record; oc1 record;
  v_check text := 'nenhum erro';
  v_trava_sai text := 'apagou';
  v_trava_muda text := 'mudou';
  v_trava_ok text := 'recusou';
begin
  select grand_total, operational_cost_total into ob0 from public.service_orders where id = v_osb;
  select grand_total, operational_cost_total into oc0 from public.service_orders where id = v_osc;
  v_b := pg_temp._preparar(jsonb_build_object('valor', v_vb, 'forma', 'credito', 'destino', 'os', 'os', v_osb,
                                              'tipo_na_os', 'despesa', 'categoria', 'Alimentação de campo'));
  rb := pg_temp._gravar(v_b);
  v_c := pg_temp._preparar(jsonb_build_object('valor', v_vc, 'forma', 'credito', 'destino', 'os', 'os', v_osc,
                                              'tipo_na_os', 'despesa', 'categoria', 'Pedágio e estacionamento'));
  rc := pg_temp._gravar(v_c);
  select * into cb from public.comprovantes where id = v_b;
  select * into cc from public.comprovantes where id = v_c;
  select * into db from public.service_order_expenses where id = cb.so_expense_id;
  select * into dc from public.service_order_expenses where id = cc.so_expense_id;
  select grand_total, operational_cost_total into ob1 from public.service_orders where id = v_osb;
  select grand_total, operational_cost_total into oc1 from public.service_orders where id = v_osc;
  -- a despesa que nasceu de comprovante nunca é faturável (CHECK)
  begin
    update public.service_order_expenses set billable_to_client = true where id = cb.so_expense_id;
  exception when check_violation then
    v_check := sqlstate;
  end;
  -- revisão dos ajustes: a despesa do CMP só muda ou sai pelo comprovante (gatilho); o resto da linha muda
  begin
    delete from public.service_order_expenses where id = cb.so_expense_id;
  exception when sqlstate '42501' then
    v_trava_sai := sqlstate;
  end;
  begin
    update public.service_order_expenses set amount = amount + 1 where id = cb.so_expense_id;
  exception when sqlstate '42501' then
    v_trava_muda := sqlstate;
  end;
  begin
    update public.service_order_expenses set notes = 'conferida' where id = cb.so_expense_id;
    v_trava_ok := 'mudou';
  exception when others then
    v_trava_ok := sqlstate;
  end;
  perform pg_temp._guarda('B', v_b, v_osb, v_vb);
  perform pg_temp._guarda('C', v_c, v_osc, v_vc);
  insert into _resultado values ('DI custo interno em OS concluída e faturada: total igual, origem gravada, sem aviso nem pendência; o CHECK recusa faturável',
    rb->>'resultado' = 'gravado' and pg_temp._tipos(cb.efeitos) = 'despesa_os,aguardar_fatura'
    and not db.billable_to_client and db.origem_codigo = cb.codigo
    and rc->>'resultado' = 'gravado' and pg_temp._tipos(cc.efeitos) = 'despesa_os,aguardar_fatura'
    and not dc.billable_to_client and dc.origem_codigo = cc.codigo
    and cardinality(cb.pendencias) = 0 and cardinality(cc.pendencias) = 0
    and jsonb_array_length(rb->'plano_mostrado'->'avisos') = 0 and jsonb_array_length(rc->'plano_mostrado'->'avisos') = 0
    and ob1.grand_total = ob0.grand_total and ob1.operational_cost_total = ob0.operational_cost_total
    and oc1.grand_total = oc0.grand_total and oc1.operational_cost_total = oc0.operational_cost_total
    and v_check = '23514' and v_trava_sai = '42501' and v_trava_muda = '42501' and v_trava_ok = 'mudou'
    and exists (select 1 from public.service_order_expenses where id = cb.so_expense_id and amount = db.amount),
    'concluida=' || pg_temp._tipos(cb.efeitos) || ' faturada=' || pg_temp._tipos(cc.efeitos)
    || ' total ' || ob0.grand_total || '→' || ob1.grand_total || ' / ' || oc0.grand_total || '→' || oc1.grand_total
    || ' check=' || v_check || ' trava=' || v_trava_sai || '/' || v_trava_muda || '/' || v_trava_ok);
exception when others then
  insert into _resultado values ('DI custo interno em OS concluída e faturada: total igual, origem gravada, sem aviso nem pendência; o CHECK recusa faturável', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ D, E, F: dinheiro no Caixa, bolso do sócio, crédito ═════════════════════════════════════
do $$
declare
  v_vd numeric := pg_temp._val();
  v_ve numeric := pg_temp._val();
  v_vf numeric := pg_temp._val();
  v_vf2 numeric := pg_temp._val();
  v_d uuid; v_e uuid; v_f uuid; v_f2 uuid;
  rd jsonb; re jsonb; rf jsonb; rf2 jsonb;
  cd record; ce record; cf record; cf2 record;
  pd record; pe record;
begin
  v_d := pg_temp._preparar(jsonb_build_object('valor', v_vd, 'forma', 'dinheiro', 'destino', 'insumo', 'quem', 'empresa'));
  rd := pg_temp._gravar(v_d);
  v_e := pg_temp._preparar(jsonb_build_object('valor', v_ve, 'forma', 'dinheiro', 'destino', 'empresa', 'quem', 'socio',
                                              'categoria', 'Alimentação de campo'));
  re := pg_temp._gravar(v_e);
  v_f := pg_temp._preparar(jsonb_build_object('valor', v_vf, 'forma', 'credito', 'destino', 'empresa', 'categoria', 'Outras despesas'));
  rf := pg_temp._gravar(v_f);
  v_f2 := pg_temp._preparar(jsonb_build_object('valor', v_vf2, 'forma', 'credito_loja', 'destino', 'empresa', 'categoria', 'Outras despesas'));
  rf2 := pg_temp._gravar(v_f2);
  select * into cd from public.comprovantes where id = v_d;
  select * into ce from public.comprovantes where id = v_e;
  select * into cf from public.comprovantes where id = v_f;
  select * into cf2 from public.comprovantes where id = v_f2;
  select * into pd from public.payables where id = cd.payable_id;
  select * into pe from public.payables where id = ce.payable_id;
  perform pg_temp._guarda('D', v_d, null, v_vd);
  perform pg_temp._guarda('E', v_e, null, v_ve);
  insert into _resultado values ('D dinheiro da empresa: saída do Caixa (conta paga em dinheiro)',
    rd->>'resultado' = 'gravado' and pg_temp._tipos(cd.efeitos) = 'caixa' and pd.payment_method = 'cash' and pd.status = 'paid'
    and pd.amount = v_vd and pd.expense_category = 'Materiais e Insumos Operacionais' and pd.description like cd.codigo || ' · %',
    'efeitos=' || pg_temp._tipos(cd.efeitos) || ' conta=' || coalesce(pd.status, '-') || '/' || coalesce(pd.payment_method, '-'));
  insert into _resultado values ('E bolso do sócio: reembolso pendente no nome dele',
    re->>'resultado' = 'gravado' and pg_temp._tipos(ce.efeitos) = 'reembolso_socio' and pe.status = 'pending'
    and pe.payee_id = (select socio from _ctx) and pe.amount = v_ve and pe.expense_category = 'Alimentação de campo'
    and ce.pagador_payee_id = (select socio from _ctx),
    'efeitos=' || pg_temp._tipos(ce.efeitos) || ' conta=' || coalesce(pe.status, '-'));
  insert into _resultado values ('F crédito: nada no financeiro (espera a fatura); crédito de loja deixa "classificar no Extrato"',
    rf->>'resultado' = 'gravado' and pg_temp._tipos(cf.efeitos) = 'aguardar_fatura' and cf.aguardando_banco_desde is not null
    and cf.payable_id is null and cf.anotacao_id is null and cardinality(cf.pendencias) = 0
    and not exists (select 1 from public.payables where abs(amount - v_vf) < 0.005)
    and not exists (select 1 from public.anotacoes_do_extrato where abs(valor - v_vf) < 0.005)
    and pg_temp._tipos(cf2.efeitos) = 'aguardar_fatura,pendencia:classificar_no_extrato'
    and cf2.pendencias = array['classificar_no_extrato'],
    'credito=' || pg_temp._tipos(cf.efeitos) || ' credito_loja=' || pg_temp._tipos(cf2.efeitos));
exception when others then
  insert into _resultado values ('D/E/F Caixa, sócio e crédito', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G, H: técnico pagou, cliente pagou ════════════════════════════════════════════════════════
do $$
declare
  v_osg uuid := pg_temp._os('open');
  v_osh uuid := pg_temp._os('open');
  v_vg numeric := pg_temp._val();
  v_vh numeric := pg_temp._val();
  v_g uuid; v_h uuid;
  rg jsonb; rh jsonb;
  cg record; ch record;
  dg record;
begin
  v_g := pg_temp._preparar(jsonb_build_object('valor', v_vg, 'forma', 'pix', 'destino', 'os', 'os', v_osg, 'tipo_na_os', 'despesa',
                                              'categoria', 'Alimentação de campo', 'quem', 'tecnico', 'pagador', (select tecnico from _ctx)));
  rg := pg_temp._gravar(v_g);
  v_h := pg_temp._preparar(jsonb_build_object('valor', v_vh, 'forma', 'pix', 'destino', 'os', 'os', v_osh, 'quem', 'cliente'));
  rh := pg_temp._gravar(v_h);
  select * into cg from public.comprovantes where id = v_g;
  select * into ch from public.comprovantes where id = v_h;
  select * into dg from public.service_order_expenses where id = cg.so_expense_id;
  insert into _resultado values ('G técnico pagou: despesa da OS (custo interno) paga pelo técnico, nada no financeiro (acerto = F2b)',
    rg->>'resultado' = 'gravado' and pg_temp._tipos(cg.efeitos) = 'despesa_os,nada,pendencia:acerto_tecnico'
    and dg.paid_by = 'technician' and not dg.billable_to_client and dg.origem_codigo = cg.codigo
    and cg.anotacao_id is null and cg.payable_id is null
    and cg.pendencias = array['acerto_tecnico'] and cg.efeitos->1->>'motivo' = 'tecnico_f2b'
    and not exists (select 1 from public.anotacoes_do_extrato where abs(valor - v_vg) < 0.005),
    'efeitos=' || pg_temp._tipos(cg.efeitos) || ' paid_by=' || coalesce(dg.paid_by, '-'));
  insert into _resultado values ('H cliente pagou direto: nada na OS, nada no financeiro',
    rh->>'resultado' = 'gravado' and pg_temp._tipos(ch.efeitos) = 'nada' and ch.efeitos->0->>'motivo' = 'cliente_pagou'
    and not exists (select 1 from public.service_order_expenses where service_order_id = v_osh)
    and ch.so_expense_id is null and ch.anotacao_id is null and ch.payable_id is null and ch.tipo_na_os is null,
    'efeitos=' || pg_temp._tipos(ch.efeitos));
exception when others then
  insert into _resultado values ('G/H técnico e cliente', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ I, J: NF-e (a OS pela linha da nota; nota que ainda não chegou) ══════════════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_outra uuid := pg_temp._os('open');
  v_chave text := pg_temp._chave();
  v_chave_j text := pg_temp._chave();
  v_nota uuid;
  v_nota_j uuid;
  v_i uuid; v_j uuid;
  ri jsonb; rj jsonb;
  ci record; cj record; cj2 record;
  v_ligou integer;
  v_aplicadas integer;
begin
  insert into public.fiscal_notes (nfe_key, nfe_number, status) values (v_chave, '12345', 'confirmed') returning id into v_nota;
  insert into public.fiscal_note_items (fiscal_note_id, item_index, description) values (v_nota, 1, 'item 1'), (v_nota, 2, 'item 2');
  insert into public.fiscal_note_items (fiscal_note_id, item_index, description, service_order_id) values (v_nota, 3, 'item 3', v_outra);
  v_i := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'tipo', 'nfe_danfe', 'chave', v_chave,
                                              'destino', 'os', 'os', v_os, 'tipo_na_os', 'peca'));
  ri := pg_temp._gravar(v_i);
  select * into ci from public.comprovantes where id = v_i;
  select count(*) into v_ligou from public.fiscal_note_items where fiscal_note_id = v_nota and service_order_id = v_os;
  perform pg_temp._guarda('I', v_i, v_os, null, v_nota);
  insert into _resultado values ('I NF-e já importada: OS pela linha da nota (só as linhas sem OS), nunca despesa da OS',
    ri->>'resultado' = 'gravado' and pg_temp._tipos(ci.efeitos) = 'itens_da_nota,pendencia:incluir_na_os'
    and jsonb_array_length(ci.efeitos->0->'itens') = 2 and v_ligou = 2
    and (select service_order_id from public.fiscal_note_items where fiscal_note_id = v_nota and item_index = 3) = v_outra
    and ci.fiscal_note_id = v_nota and ci.so_expense_id is null
    and not exists (select 1 from public.service_order_expenses where service_order_id = v_os)
    and ci.anotacao_id is null and ci.payable_id is null,
    'efeitos=' || pg_temp._tipos(ci.efeitos) || ' ligadas=' || v_ligou);

  v_j := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'tipo', 'nfe_xml', 'chave', v_chave_j,
                                              'destino', 'os', 'os', v_os, 'tipo_na_os', 'despesa'));
  rj := pg_temp._gravar(v_j);
  select * into cj from public.comprovantes where id = v_j;
  insert into public.fiscal_notes (nfe_key, nfe_number, status) values (v_chave_j, '67890', 'confirmed') returning id into v_nota_j;
  insert into public.fiscal_note_items (fiscal_note_id, item_index, description) values (v_nota_j, 1, 'item único');
  v_aplicadas := public._comprovante_aplicar_notas_chegadas();
  select * into cj2 from public.comprovantes where id = v_j;
  insert into _resultado values ('J NF-e ainda não importada: aguardando_xml; quando a nota chega, liga os itens e grava',
    rj->>'resultado' = 'gravado' and rj->'gravacao'->>'situacao' = 'aguardando_xml' and cj.situacao = 'aguardando_xml'
    and pg_temp._tipos(cj.efeitos) = 'aguardar_nota,despesa_os' and cj.gravado_em is not null
    -- a despesa da NF-e: custo interno da OS com o valor da nota (o Lucro por OS desconta; fora do cliente)
    and (select not billable_to_client and origem_codigo = cj.codigo from public.service_order_expenses where id = cj.so_expense_id)
    and v_aplicadas >= 1 and cj2.situacao = 'gravado' and cj2.fiscal_note_id = v_nota_j
    and pg_temp._tipos(cj2.efeitos) = 'aguardar_nota,despesa_os,itens_da_nota'
    and (select service_order_id from public.fiscal_note_items where fiscal_note_id = v_nota_j) = v_os,
    'antes=' || cj.situacao || ' depois=' || cj2.situacao || ' efeitos=' || pg_temp._tipos(cj2.efeitos));
exception when others then
  insert into _resultado values ('I/J NF-e', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ K, L: estoque (dar entrada pelo XML) e pessoal (do bolso: só arquivo; da empresa: gasto do sócio) ═══
do $$
declare
  v_vk numeric := pg_temp._val();
  v_vl numeric := pg_temp._val();
  v_vl2 numeric := pg_temp._val();
  v_k uuid; v_l uuid; v_l2 uuid;
  rk jsonb; rl jsonb; rl2 jsonb;
  ck record; cl record; cl2 record;
  ak record; al2 record;
  v_chamadas_antes integer := 0;
  v_chamadas_depois integer := 0;
begin
  v_k := pg_temp._preparar(jsonb_build_object('valor', v_vk, 'forma', 'pix', 'tipo', 'pix', 'favorecido', pg_temp._cnpj(), 'destino', 'estoque'));
  rk := pg_temp._gravar(v_k);
  select * into ck from public.comprovantes where id = v_k;
  select * into ak from public.anotacoes_do_extrato where id = ck.anotacao_id;
  perform pg_temp._guarda('K', v_k, null, v_vk);
  if to_regclass('public.ensaio_chamadas') is not null then
    execute 'select count(*) from public.ensaio_chamadas' into v_chamadas_antes;
  end if;
  -- L1: do bolso (ou do cartão pessoal) — só o arquivo
  v_l := pg_temp._preparar(jsonb_build_object('valor', v_vl, 'forma', 'pix', 'destino', 'pessoal', 'quem', 'socio'));
  rl := pg_temp._gravar(v_l);
  if to_regclass('public.ensaio_chamadas') is not null then
    execute 'select count(*) from public.ensaio_chamadas' into v_chamadas_depois;
  end if;
  select * into cl from public.comprovantes where id = v_l;
  -- L2: a conta da EMPRESA pagou (Pix ao CNPJ): o efeito de uma compra, em gasto pessoal do sócio
  v_l2 := pg_temp._preparar(jsonb_build_object('valor', v_vl2, 'forma', 'pix', 'tipo', 'pix', 'favorecido', pg_temp._cnpj(),
                                               'destino', 'pessoal', 'quem', 'empresa'));
  rl2 := pg_temp._gravar(v_l2);
  select * into cl2 from public.comprovantes where id = v_l2;
  select * into al2 from public.anotacoes_do_extrato where id = cl2.anotacao_id;
  insert into _resultado values ('K estoque: anota com "Compras de mercadorias" e deixa "dar entrada" (estoque só pelo XML)',
    rk->>'resultado' = 'gravado' and pg_temp._tipos(ck.efeitos) = 'anotar,pendencia:dar_entrada'
    and ak.categoria = 'Compras de mercadorias' and ak.os_id is null and ck.pendencias = array['dar_entrada'],
    'efeitos=' || pg_temp._tipos(ck.efeitos) || ' categoria=' || coalesce(ak.categoria, '-'));
  insert into _resultado values ('L1 pessoal do bolso: só o arquivo em PESSOAL, nada no financeiro',
    rl->>'resultado' = 'gravado' and pg_temp._tipos(cl.efeitos) = 'nada' and cl.efeitos->0->>'motivo' = 'pessoal'
    and rl->'plano_mostrado'->>'pasta' = 'pessoal' and cl.anotacao_id is null and cl.payable_id is null
    and cl.so_expense_id is null and v_chamadas_depois = v_chamadas_antes and cl.quem_pagou = 'socio'
    and not exists (select 1 from public.anotacoes_do_extrato where abs(valor - v_vl) < 0.005),
    'efeitos=' || pg_temp._tipos(cl.efeitos) || ' chamadas de rota=' || (v_chamadas_depois - v_chamadas_antes));
  insert into _resultado values ('L2 pessoal pago pela empresa: anota em "Gasto Pessoal Sócio - Descontar PL" com o sócio de favorecido, sem OS',
    rl2->>'resultado' = 'gravado' and pg_temp._tipos(cl2.efeitos) = 'anotar' and rl2->'plano_mostrado'->>'pasta' = 'pessoal'
    and al2.categoria = 'Gasto Pessoal Sócio - Descontar PL' and al2.favorecido_id = (select socio from _ctx)
    and al2.os_id is null and cl2.situacao in ('gravado', 'aguardando_banco')
    and cl2.categoria = 'Gasto Pessoal Sócio - Descontar PL' and cl2.pagador_payee_id = (select socio from _ctx),
    'efeitos=' || pg_temp._tipos(cl2.efeitos) || ' categoria=' || coalesce(al2.categoria, '-')
    || ' favorecido=' || coalesce((al2.favorecido_id = (select socio from _ctx))::text, '-'));
exception when others then
  insert into _resultado values ('K/L estoque e pessoal', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ S: OS assinada — o custo interno não mexe no total nem pede nova assinatura ═══════════════
do $$
declare
  v_os uuid := pg_temp._os('open', true);
  v_cmp uuid;
  r jsonb;
  v_antes record;
  v_depois record;
begin
  select requires_resignature, grand_total into v_antes from public.service_orders where id = v_os;
  v_cmp := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'debito', 'destino', 'os', 'os', v_os,
                                                'tipo_na_os', 'despesa', 'categoria', 'Combustível e deslocamento'));
  r := pg_temp._gravar(v_cmp);
  select requires_resignature, grand_total into v_depois from public.service_orders where id = v_os;
  insert into _resultado values ('S OS assinada: o custo interno não mexe no total nem pede nova assinatura (sem aviso)',
    r->>'resultado' = 'gravado' and not (r->'plano_mostrado'->'avisos' @> '["os_assinada_pede_nova_assinatura"]'::jsonb)
    and not (r->'avisos_mostrados' @> '["os_assinada_pede_nova_assinatura"]'::jsonb)
    and not v_antes.requires_resignature and not v_depois.requires_resignature and v_depois.grand_total = v_antes.grand_total,
    'avisos=' || coalesce(r->'plano_mostrado'->>'avisos', '-') || ' requires_resignature ' || v_antes.requires_resignature
    || '→' || v_depois.requires_resignature);
exception when others then
  insert into _resultado values ('S OS assinada: o custo interno não mexe no total nem pede nova assinatura (sem aviso)', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ Anti-duplicado: o que já foi lançado — e não contradiz o fornecedor — é anexado, nunca lançado de novo ═══
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_v1 numeric := pg_temp._val();
  v_v2 numeric := pg_temp._val();
  v_v3 numeric := pg_temp._val();
  v_v4 numeric := pg_temp._val();
  v_v5 numeric := pg_temp._val();
  v_v6 numeric := pg_temp._val();
  v_cnpj text := '6' || lpad((floor(random() * 1e12))::bigint::text, 13, '0');
  v_sup uuid;
  v_outro uuid;
  v_desp uuid;
  v_desp5 uuid;
  v_anot uuid;
  v_cx uuid;
  c1 uuid; c2 uuid; c3 uuid; c4 uuid; c5 uuid; c6 uuid;
  r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb;
  x1 record; x2 record; x3 record; x4 record; x5 record;
  x6 public.comprovantes;
begin
  insert into public.suppliers (name, cnpj_cpf) values ('Fornecedor Teste F2 ' || pg_temp._letras(6), v_cnpj) returning id into v_sup;
  insert into public.suppliers (name, cnpj_cpf) values ('Outro Fornecedor Teste F2 ' || pg_temp._letras(6), '8' || lpad((floor(random() * 1e12))::bigint::text, 13, '0'))
  returning id into v_outro;
  insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date, paid_by, billable_to_client, supplier_id)
  values (v_os, 'Peças e materiais', 'lançada antes pela tela', v_v1, pg_temp._hoje(), 'company', true, v_sup) returning id into v_desp;
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, documento, categoria, descricao, criada_por)
  values ('debit', v_v2, pg_temp._hoje(), true, v_cnpj, 'Outras despesas', 'anotada antes pelo assistente', pg_temp._dono())
  returning id into v_anot;
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category, origin, payment_method, supplier_id)
  values ('caixa de teste 1', pg_temp._hoje(), pg_temp._hoje(), v_v3, v_v3, 0, 'paid', 'Outras despesas', 'manual', 'cash', v_sup),
         ('caixa de teste 2', pg_temp._hoje() - 1, pg_temp._hoje() - 1, v_v3, v_v3, 0, 'paid', 'Outras despesas', 'manual', 'cash', v_sup);
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category, origin, payment_method, supplier_id)
  values ('caixa de teste 3', pg_temp._hoje(), pg_temp._hoje(), v_v4, v_v4, 0, 'paid', 'Outras despesas', 'manual', 'cash', v_sup)
  returning id into v_cx;
  -- a despesa do MESMO valor e data na OS, lançada sem fornecedor: não contradiz — o CMP só a comprova
  insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date, paid_by, billable_to_client)
  values (v_os, 'Alimentação de campo', 'almoço da equipe', v_v5, pg_temp._hoje(), 'company', true) returning id into v_desp5;
  -- a despesa do mesmo valor de OUTRO fornecedor: contradiz — não é dela (pergunta "peça ou despesa?")
  insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date, paid_by, billable_to_client, supplier_id)
  values (v_os, 'Peças e materiais', 'peça de outro fornecedor', v_v6, pg_temp._hoje(), 'company', true, v_outro);

  c1 := pg_temp._preparar(jsonb_build_object('valor', v_v1, 'forma', 'credito', 'destino', 'os', 'os', v_os, 'fornecedor', v_sup));
  r1 := pg_temp._gravar(c1);
  c2 := pg_temp._preparar(jsonb_build_object('valor', v_v2, 'forma', 'pix', 'destino', 'empresa', 'categoria', 'Outras despesas', 'cnpj', v_cnpj));
  r2 := pg_temp._gravar(c2);
  c3 := pg_temp._preparar(jsonb_build_object('valor', v_v3, 'forma', 'dinheiro', 'destino', 'empresa', 'quem', 'empresa',
                                             'categoria', 'Outras despesas', 'fornecedor', v_sup));
  r3 := pg_temp._gravar(c3);
  c4 := pg_temp._preparar(jsonb_build_object('valor', v_v4, 'forma', 'dinheiro', 'destino', 'empresa', 'quem', 'empresa',
                                             'categoria', 'Outras despesas', 'fornecedor', v_sup));
  r4 := pg_temp._gravar(c4);
  c5 := pg_temp._preparar(jsonb_build_object('valor', v_v5, 'forma', 'credito', 'destino', 'os', 'os', v_os, 'fornecedor', v_sup));
  r5 := pg_temp._gravar(c5);
  c6 := pg_temp._preparar(jsonb_build_object('valor', v_v6, 'forma', 'credito', 'destino', 'os', 'os', v_os, 'fornecedor', v_sup));
  select * into x1 from public.comprovantes where id = c1;
  select * into x2 from public.comprovantes where id = c2;
  select * into x3 from public.comprovantes where id = c3;
  select * into x4 from public.comprovantes where id = c4;
  select * into x5 from public.comprovantes where id = c5;
  select * into x6 from public.comprovantes where id = c6;
  perform pg_temp._guarda('AD1', c1, v_os, v_v1, v_desp);
  perform pg_temp._guarda('AD2', c2, null, v_v2, v_anot);
  perform pg_temp._guarda('AD4', c4, null, v_v4, v_cx);
  insert into _resultado values ('AD anti-duplicado: anexa despesa (a do fornecedor e a sem fornecedor), anotação e conta do Caixa; outro fornecedor não; dois iguais = classificar no Extrato',
    pg_temp._tipos(x1.efeitos) = 'anexar_despesa,aguardar_fatura' and x1.so_expense_id = v_desp
    and pg_temp._tipos(x2.efeitos) = 'anexar_anotacao' and x2.anotacao_id = v_anot
    and (select count(*) from public.anotacoes_do_extrato where abs(valor - v_v2) < 0.005) = 1
    and pg_temp._tipos(x3.efeitos) = 'pendencia:classificar_no_extrato' and x3.payable_id is null
    and r3->'plano_mostrado'->'avisos' @> '["duplicado_ambiguo"]'::jsonb
    and (select count(*) from public.payables where abs(amount - v_v3) < 0.005) = 2
    and pg_temp._tipos(x4.efeitos) = 'anexar_lancamento' and x4.payable_id = v_cx and x4.efeitos->0->>'origem' = 'anterior'
    and (select count(*) from public.payables where abs(amount - v_v4) < 0.005) = 1
    -- a despesa sem fornecedor não contradiz: é ela
    and pg_temp._tipos(x5.efeitos) = 'anexar_despesa,aguardar_fatura' and x5.so_expense_id = v_desp5
    -- a de outro fornecedor contradiz: não é ela, e o dono diz "peça ou despesa"
    and public._comprovante_lancamento_na_os(x6) is null and public._comprovante_proximo_passo(x6) = 'tipo_na_os',
    'despesa=' || pg_temp._tipos(x1.efeitos) || ' anotacao=' || pg_temp._tipos(x2.efeitos)
    || ' dois_caixas=' || pg_temp._tipos(x3.efeitos) || ' um_caixa=' || pg_temp._tipos(x4.efeitos)
    || ' sem_fornecedor=' || pg_temp._tipos(x5.efeitos) || ' outro_fornecedor=' || coalesce(public._comprovante_proximo_passo(x6), '-'));
exception when others then
  insert into _resultado values ('AD anti-duplicado: anexa despesa (a do fornecedor e a sem fornecedor), anotação e conta do Caixa; outro fornecedor não; dois iguais = classificar no Extrato', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ AN: o lançamento que já está na OS só é comprovado (ajustes do dono, 11/10/2026) ═══════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_val numeric := pg_temp._val();
  v_vp numeric := 2 * round(pg_temp._val() / 2, 2);
  v_va numeric := pg_temp._val();
  v_vs numeric := pg_temp._val();
  v_desp uuid;
  v_peca uuid;
  d0 record;
  d1 record;
  v_op0 numeric; v_gt0 numeric; v_op1 numeric; v_gt1 numeric; v_op2 numeric;
  c1 uuid; c2 uuid; c3 uuid; c4 uuid;
  r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb;
  x1 record; x2 record; x3 record; x4 record;
  k1 jsonb; k2 jsonb; k4 jsonb;
  v_n_desp integer;
  v_falhas text[];
  v_alm public.comprovantes;
  v_na_alm jsonb;
  v_na_pec jsonb;
begin
  -- a despesa lançada pela tela, cobrada do cliente (faturável: entra no total)
  perform public.so_expense_add(v_os, 'Frete e importação', 'frete lançado na OS', v_val, pg_temp._hoje(), 'company', true, null, null);
  select id into v_desp from public.service_order_expenses where service_order_id = v_os;
  select billable_to_client, amount, category, description into d0 from public.service_order_expenses where id = v_desp;
  -- a peça lançada na OS (2 × o custo)
  insert into public.service_order_parts (service_order_id, quantity, unit_cost_snapshot) values (v_os, 2, v_vp / 2)
  returning id into v_peca;
  -- duas despesas iguais lançadas na OS (ambíguo)
  insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date, paid_by, billable_to_client)
  values (v_os, 'Alimentação de campo', 'almoço 1', v_va, pg_temp._hoje(), 'company', true),
         (v_os, 'Alimentação de campo', 'almoço 2', v_va, pg_temp._hoje(), 'company', true);
  select operational_cost_total, grand_total into v_op0, v_gt0 from public.service_orders where id = v_os;

  c1 := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'credito', 'destino', 'os', 'os', v_os));
  r1 := pg_temp._gravar(c1);
  c2 := pg_temp._preparar(jsonb_build_object('valor', v_vp, 'forma', 'credito', 'destino', 'os', 'os', v_os));
  r2 := pg_temp._gravar(c2);
  c3 := pg_temp._preparar(jsonb_build_object('valor', v_va, 'forma', 'credito', 'destino', 'os', 'os', v_os));
  r3 := pg_temp._gravar(c3);
  c4 := pg_temp._preparar(jsonb_build_object('valor', v_vs, 'forma', 'credito', 'destino', 'os', 'os', v_os, 'tipo_na_os', 'peca'));
  r4 := pg_temp._gravar(c4);
  select * into x1 from public.comprovantes where id = c1;
  select * into x2 from public.comprovantes where id = c2;
  select * into x3 from public.comprovantes where id = c3;
  select * into x4 from public.comprovantes where id = c4;
  select billable_to_client, amount, category, description into d1 from public.service_order_expenses where id = v_desp;
  select operational_cost_total, grand_total into v_op1, v_gt1 from public.service_orders where id = v_os;
  select count(*) into v_n_desp from public.service_order_expenses where service_order_id = v_os;
  -- a peça só casa com comprovante de material (revisão dos ajustes): o mesmo valor num cupom de almoço não é
  -- a peça; de "Peças e materiais", é
  select * into v_alm from public.comprovantes where id = c2;
  v_alm.categoria := 'Alimentação de campo';
  v_na_alm := public._comprovante_lancamento_na_os(v_alm);
  v_alm.categoria := 'Peças e materiais';
  v_na_pec := public._comprovante_lancamento_na_os(v_alm);
  k1 := public.comprovante_cancelar(c1, 'anexei errado', pg_temp._dono());
  k2 := public.comprovante_cancelar(c2, 'anexei errado', pg_temp._dono());
  k4 := public.comprovante_cancelar(c4, 'foto errada', pg_temp._dono());
  select operational_cost_total into v_op2 from public.service_orders where id = v_os;
  select array_agg(nome) into v_falhas from (values
    ('anexou_a_despesa', r1->>'resultado' = 'gravado' and pg_temp._tipos(x1.efeitos) = 'anexar_despesa,aguardar_fatura'
                         and x1.so_expense_id = v_desp and x1.tipo_na_os is null and x1.categoria = 'Frete e importação'),
    ('nada_na_despesa_mudou', d1.billable_to_client and d1.amount = d0.amount and d1.category = d0.category
                              and d1.description = d0.description),
    ('anexou_a_peca', r2->>'resultado' = 'gravado' and pg_temp._tipos(x2.efeitos) = 'anexar_peca,aguardar_fatura'
                      and x2.so_part_id = v_peca and x2.categoria = 'Peças e materiais'),
    ('peca_so_de_material', v_na_alm is null and v_na_pec->>'tipo' = 'peca' and v_na_pec->>'id' = v_peca::text),
    ('ambiguo_so_prova', r3->>'resultado' = 'gravado' and pg_temp._tipos(x3.efeitos) = 'comprovar_na_os,aguardar_fatura'
                         and r3->'plano_mostrado'->'avisos' @> '["varios_na_os"]'::jsonb and x3.so_expense_id is null
                         and (x3.efeitos->0->>'n')::int = 2),
    ('peca_sem_candidata', r4->>'resultado' = 'gravado' and pg_temp._tipos(x4.efeitos) = 'comprovar_na_os,aguardar_fatura,pendencia:incluir_na_os'
                           and x4.pendencias = array['incluir_na_os'] and x4.efeitos->0->>'motivo' = 'peca'),
    ('nenhum_custo_novo', v_n_desp = 3 and v_op1 = v_op0 and v_gt1 = v_gt0),
    ('cancelar_so_solta', (k1->>'ok')::boolean and (k2->>'ok')::boolean and (k4->>'ok')::boolean
                          and exists (select 1 from public.service_order_expenses where id = v_desp and billable_to_client)
                          and exists (select 1 from public.service_order_parts where id = v_peca)
                          and (select so_part_id from public.comprovantes where id = c2) is null and v_op2 = v_op0)
  ) as t(nome, ok) where not coalesce(ok, false);
  insert into _resultado values ('AN o que já está na OS só é comprovado: despesa e peça anexadas (nada nelas muda), ambíguo e peça nova sem custo',
    v_falhas is null,
    coalesce('falhou: ' || array_to_string(v_falhas, ', ') || ' | ', '')
    || 'despesa=' || pg_temp._tipos(x1.efeitos) || ' peca=' || pg_temp._tipos(x2.efeitos) || ' ambiguo=' || pg_temp._tipos(x3.efeitos)
    || ' sem_candidata=' || pg_temp._tipos(x4.efeitos) || ' op ' || v_op0 || '→' || v_op1 || '→' || coalesce(v_op2::text, '-'));
exception when others then
  insert into _resultado values ('AN o que já está na OS só é comprovado: despesa e peça anexadas (nada nelas muda), ambíguo e peça nova sem custo', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ PL / CA: conta a pagar que já existe para o gasto — anexa, não lança outra ═════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_v1 numeric := pg_temp._val();
  v_v2 numeric := pg_temp._val();
  v_cnpj text := '4' || lpad((floor(random() * 1e12))::bigint::text, 13, '0');
  v_sup uuid;
  v_pay1 uuid;
  v_pay2 uuid;
  v_desp uuid;
  c1 uuid; c2 uuid;
  r1 jsonb; r2 jsonb;
  x1 record; x2 record;
begin
  insert into public.suppliers (name, cnpj_cpf) values ('Fornecedor Teste F2 ' || pg_temp._letras(6), v_cnpj) returning id into v_sup;
  -- a despesa lançada pela tela com "também criar conta a pagar" (pendente)
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               origin, supplier_id, linked_service_order_id)
  values ('conta da despesa da OS', pg_temp._hoje(), pg_temp._hoje() + 10, v_v1, 0, v_v1, 'pending', 'Peças e materiais',
          'service_order_expense', v_sup, v_os)
  returning id into v_pay1;
  insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date, paid_by, billable_to_client,
                                             supplier_id, linked_payable_id)
  values (v_os, 'Peças e materiais', 'peça do fornecedor', v_v1, pg_temp._hoje(), 'company', true, v_sup, v_pay1)
  returning id into v_desp;
  -- uma conta em aberto do fornecedor (boleto cadastrado), sem despesa na OS
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               origin, supplier_id)
  values ('boleto do fornecedor', pg_temp._hoje() - 2, pg_temp._hoje() + 3, v_v2, 0, v_v2, 'pending', 'Outras despesas', 'manual', v_sup)
  returning id into v_pay2;

  c1 := pg_temp._preparar(jsonb_build_object('valor', v_v1, 'forma', 'dinheiro', 'destino', 'os', 'os', v_os,
                                             'quem', 'empresa', 'fornecedor', v_sup));
  r1 := pg_temp._gravar(c1);
  c2 := pg_temp._preparar(jsonb_build_object('valor', v_v2, 'forma', 'pix', 'destino', 'empresa', 'categoria', 'Outras despesas',
                                             'cnpj', v_cnpj));
  r2 := pg_temp._gravar(c2);
  select * into x1 from public.comprovantes where id = c1;
  select * into x2 from public.comprovantes where id = c2;
  insert into _resultado values ('PL/CA conta a pagar já aberta (da despesa da OS ou do fornecedor): anexa e deixa a baixa/classificação',
    pg_temp._tipos(x1.efeitos) = 'anexar_despesa,anexar_lancamento,pendencia:dar_baixa' and x1.payable_id = v_pay1
    and x1.efeitos->1->>'origem' = 'despesa_da_os'
    and (select count(*) from public.payables where abs(amount - v_v1) < 0.005) = 1
    and not exists (select 1 from public.payables where abs(amount - v_v1) < 0.005 and payment_method = 'cash')
    and pg_temp._tipos(x2.efeitos) = 'anexar_lancamento,pendencia:classificar_no_extrato' and x2.payable_id = v_pay2
    and x2.efeitos->0->>'origem' = 'conta_em_aberto' and x2.anotacao_id is null
    and (select count(*) from public.anotacoes_do_extrato where abs(valor - v_v2) < 0.005) = 0,
    'despesa_da_os=' || pg_temp._tipos(x1.efeitos) || ' conta_em_aberto=' || pg_temp._tipos(x2.efeitos));
exception when others then
  insert into _resultado values ('PL/CA conta a pagar já aberta (da despesa da OS ou do fornecedor): anexa e deixa a baixa/classificação', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ MC: a mesma compra em dois CMPs (cupom + recibo) — o segundo só guarda o arquivo ═══════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_val numeric := pg_temp._val();
  c1 uuid; c2 uuid; c3 uuid;
  r1 jsonb; r2 jsonb;
  v_p jsonb;
  v_m jsonb;
  v_outra jsonb;
  x1 record; x2 record;
  v_canc jsonb;
  v_cx integer;
  v_desp_n integer;
begin
  -- o cupom, em dinheiro: despesa da OS (custo interno)
  c1 := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'dinheiro', 'destino', 'os', 'os', v_os, 'tipo_na_os', 'despesa',
                                             'categoria', 'Alimentação de campo', 'quem', 'empresa'));
  r1 := pg_temp._gravar(c1);
  -- o recibo da mesma compra: o passo "mesma compra" vem antes de tudo o mais
  c2 := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'dinheiro', 'destino', 'os', 'os', v_os, 'tipo', 'recibo'));
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste'
   where phone_normalized = pg_temp._phone() and status = 'aberta';
  update public.comprovantes set situacao = 'aguardando_vez' where phone_normalized = pg_temp._phone() and situacao in ('perguntando', 'aguardando_sim');
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', c2);
  -- "sim" = é a mesma compra (só guardar o arquivo)
  v_m := pg_temp._sim(v_p);
  r2 := pg_temp._gravar(c2);
  select * into x1 from public.comprovantes where id = c1;
  select * into x2 from public.comprovantes where id = c2;
  select count(*) into v_cx from public.payables where abs(amount - v_val) < 0.005 and payment_method = 'cash';
  -- um terceiro do mesmo valor que o dono diz ser OUTRA compra: grava normal
  c3 := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'credito', 'destino', 'os', 'os', v_os, 'tipo_na_os', 'despesa',
                                             'categoria', 'Alimentação de campo'));
  update public.comprovantes set outra_compra = true where id = c3;
  v_outra := pg_temp._gravar(c3);
  select count(*) into v_desp_n from public.service_order_expenses where service_order_id = v_os and abs(amount - v_val) < 0.005;
  v_canc := public.comprovante_cancelar(c1, 'teste da mesma compra', pg_temp._dono());
  insert into _resultado values ('MC a mesma compra em dois CMPs: o 2º pergunta, só guarda o arquivo (1 despesa, 1 Caixa); "outra" grava normal',
    v_p->>'passo' = 'mesma_compra' and v_p->'mesma_compra'->>'codigo' = x1.codigo
    and v_m->>'resultado' = 'resumo' and x2.mesma_compra_de = c1
    and r2->>'resultado' = 'gravado' and pg_temp._tipos(x2.efeitos) = 'mesma_compra'
    and v_desp_n = 2 and v_cx = 1
    and v_outra->>'resultado' = 'gravado'
    and (v_canc->>'ok')::boolean and v_canc->'avisos' @> '["outros_da_mesma_compra"]'::jsonb
    and v_canc->'mesma_compra' @> to_jsonb(array[x2.codigo]),
    'passo=' || coalesce(v_p->>'passo', '-') || ' resposta=' || coalesce(v_m->>'resultado', '-') || ' 2º=' || pg_temp._tipos(x2.efeitos)
    || ' caixa=' || v_cx || ' outra=' || coalesce(v_outra->>'resultado', '-') || ' cancelar=' || coalesce(v_canc->>'avisos', '-'));
exception when others then
  insert into _resultado values ('MC a mesma compra em dois CMPs: o 2º pergunta, só guarda o arquivo (1 despesa, 1 Caixa); "outra" grava normal', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ NR: a nota reprocessada (ids novos dos itens) e o cancelamento pelo item_index ═══════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_chave text := pg_temp._chave();
  v_nota uuid;
  v_cmp uuid;
  r jsonb;
  v_canc jsonb;
  v_ligadas integer;
  v_soltas integer;
begin
  insert into public.fiscal_notes (nfe_key, nfe_number, status) values (v_chave, '55555', 'confirmed') returning id into v_nota;
  insert into public.fiscal_note_items (fiscal_note_id, item_index, description) values (v_nota, 1, 'item 1'), (v_nota, 2, 'item 2');
  v_cmp := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'tipo', 'nfe_danfe', 'chave', v_chave,
                                                'destino', 'os', 'os', v_os, 'tipo_na_os', 'peca'));
  r := pg_temp._gravar(v_cmp);
  -- o reprocessamento da nota (sync_fiscal_note_items): apaga e reinsere as linhas, a OS fica pelo índice
  create temp table _itens on commit drop as select item_index, description, service_order_id from public.fiscal_note_items where fiscal_note_id = v_nota;
  delete from public.fiscal_note_items where fiscal_note_id = v_nota;
  insert into public.fiscal_note_items (fiscal_note_id, item_index, description, service_order_id)
  select v_nota, item_index, description, service_order_id from _itens;
  select count(*) into v_ligadas from public.fiscal_note_items where fiscal_note_id = v_nota and service_order_id = v_os;
  v_canc := public.comprovante_cancelar(v_cmp, 'nota de outra OS', pg_temp._dono());
  select count(*) into v_soltas from public.fiscal_note_items where fiscal_note_id = v_nota and service_order_id is null;
  insert into _resultado values ('NR NF-e: o cancelamento desliga os itens pelo item_index, mesmo depois de a nota ser reprocessada',
    r->>'resultado' = 'gravado' and v_ligadas = 2 and (v_canc->>'ok')::boolean and v_soltas = 2,
    'ligadas=' || v_ligadas || ' cancelar=' || coalesce(v_canc->>'ok', '-') || ' soltas=' || v_soltas);
exception when others then
  insert into _resultado values ('NR NF-e: o cancelamento desliga os itens pelo item_index, mesmo depois de a nota ser reprocessada', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ XF: cancelar o custo interno com a OS que mudou depois do sim (concluída, faturada e paga) ═══
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_os2 uuid := pg_temp._os('open');
  v_val numeric := pg_temp._val();
  v_cmp uuid;
  v_cmp2 uuid;
  r jsonb;
  v_antes record;
  v_depois record;
  v_antes2 record;
  v_depois2 record;
  v_canc jsonb;
  v_canc2 jsonb;
begin
  -- custo interno lançado com a OS aberta; a OS é concluída depois: sai sem recálculo
  v_cmp := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'credito', 'destino', 'os', 'os', v_os,
                                                'tipo_na_os', 'despesa', 'categoria', 'Alimentação de campo'));
  r := pg_temp._gravar(v_cmp);
  update public.service_orders set status = 'completed', labor_cost_total = 100, check_out_at = now() where id = v_os;
  select grand_total, operational_cost_total into v_antes from public.service_orders where id = v_os;
  v_canc := public.comprovante_cancelar(v_cmp, 'não era desta OS', pg_temp._dono());
  select grand_total, operational_cost_total into v_depois from public.service_orders where id = v_os;
  -- a OS foi faturada e o cliente pagou tudo: o custo interno não está no total — cancela sem bloqueio
  v_cmp2 := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'credito', 'destino', 'os', 'os', v_os2,
                                                 'tipo_na_os', 'despesa', 'categoria', 'Alimentação de campo'));
  r := pg_temp._gravar(v_cmp2);
  update public.service_orders set invoicing_status = 'invoiced' where id = v_os2;
  insert into public.receivables (service_order_id, amount, paid_amount, status) values (v_os2, v_val, v_val, 'paid');
  select grand_total, operational_cost_total into v_antes2 from public.service_orders where id = v_os2;
  v_canc2 := public.comprovante_cancelar(v_cmp2, 'quero desfazer', pg_temp._dono());
  select grand_total, operational_cost_total into v_depois2 from public.service_orders where id = v_os2;
  insert into _resultado values ('XF cancelar o custo interno: OS concluída ou faturada e paga, sai sem mexer no total e sem bloqueio',
    (v_canc->>'ok')::boolean and v_depois.grand_total = v_antes.grand_total
    and v_depois.operational_cost_total = v_antes.operational_cost_total
    and not exists (select 1 from public.service_order_expenses where service_order_id = v_os)
    and (v_canc2->>'ok')::boolean and v_depois2.grand_total = v_antes2.grand_total
    and v_depois2.operational_cost_total = v_antes2.operational_cost_total
    and not exists (select 1 from public.service_order_expenses where service_order_id = v_os2),
    'concluida=' || coalesce(v_canc->>'ok', '-') || ' total ' || v_antes.grand_total || '→' || v_depois.grand_total
    || ' faturada_paga=' || coalesce(v_canc2->>'ok', v_canc2->'bloqueios'->0->>'motivo'));
exception when others then
  insert into _resultado values ('XF cancelar o custo interno: OS concluída ou faturada e paga, sai sem mexer no total e sem bloqueio', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ FH: o CNPJ da HBR nunca é fornecedor; documento que contradiz o cadastro não vai junto ═══════
do $$
declare
  v_val numeric := pg_temp._val();
  v_val2 numeric := pg_temp._val();
  v_hbr uuid;
  v_outro uuid;
  v_cnpj_pix text := '3' || lpad((floor(random() * 1e12))::bigint::text, 13, '0');
  c1 uuid; c2 uuid;
  r1 jsonb; r2 jsonb;
  v_args1 jsonb;
  v_args2 jsonb;
begin
  insert into public.suppliers (name, cnpj_cpf)
  values ('HBR (cadastro errado)', public.raiz_do_cnpj_da_empresa() || '000190') returning id into v_hbr;
  insert into public.suppliers (name, cnpj_cpf)
  values ('Fornecedor Teste F2 ' || pg_temp._letras(6), '2' || lpad((floor(random() * 1e12))::bigint::text, 13, '0')) returning id into v_outro;
  c1 := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'dinheiro', 'destino', 'empresa', 'quem', 'empresa',
                                             'categoria', 'Outras despesas', 'fornecedor', v_hbr));
  r1 := pg_temp._gravar(c1);
  c2 := pg_temp._preparar(jsonb_build_object('valor', v_val2, 'forma', 'pix', 'destino', 'empresa', 'categoria', 'Outras despesas',
                                             'fornecedor', v_outro, 'favorecido', v_cnpj_pix));
  r2 := pg_temp._gravar(c2);
  if to_regclass('public.ensaio_chamadas') is not null then
    execute 'select args from public.ensaio_chamadas where rota = ''lancar_no_caixa'' and (args->>''valor'')::numeric = $1 order by id desc limit 1'
      into v_args1 using v_val;
    execute 'select args from public.ensaio_chamadas where rota = ''anotar_transacao'' and (args->>''valor'')::numeric = $1 order by id desc limit 1'
      into v_args2 using v_val2;
  end if;
  insert into _resultado values ('FH o cadastro com a raiz da HBR não vira fornecedor; o Pix de outro CNPJ anota só com o documento',
    r1->>'resultado' = 'gravado' and r2->>'resultado' = 'gravado'
    and (select supplier_id from public.payables where id = (select payable_id from public.comprovantes where id = c1)) is null
    and (select fornecedor_id from public.anotacoes_do_extrato where id = (select anotacao_id from public.comprovantes where id = c2)) is null
    and (select documento from public.anotacoes_do_extrato where id = (select anotacao_id from public.comprovantes where id = c2)) = v_cnpj_pix
    and (v_args1 is null or v_args1->>'fornecedor_id' is null) and (v_args2 is null or v_args2->>'fornecedor_id' is null),
    'caixa=' || coalesce(r1->>'resultado', '-') || ' anotar=' || coalesce(r2->>'resultado', '-'));
exception when others then
  insert into _resultado values ('FH o cadastro com a raiz da HBR não vira fornecedor; o Pix de outro CNPJ anota só com o documento', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ Cancelamento: desfaz cada efeito ═════════════════════════════════════════════════════════
do $$
declare
  v_a jsonb; v_b jsonb; v_c jsonb; v_d jsonb; v_i jsonb; v_k jsonb; v_ad1 jsonb; v_ad2 jsonb; v_ad4 jsonb;
  v_cmd jsonb;
  ob0 record; ob1 record;
  v_det text := '';
  v_ok boolean := true;
  v_dup jsonb;
begin
  -- custo interno em OS aberta (A) + anotação aguardando: tudo some, o total continua o mesmo
  v_a := public.comprovante_cancelar(pg_temp._id('A'), 'comprei em dobro', pg_temp._dono());
  v_ok := v_ok and (v_a->>'ok')::boolean
          and not exists (select 1 from public.service_order_expenses where service_order_id = (select os from _cmps where nome = 'A'))
          and (select operational_cost_total from public.service_orders where id = (select os from _cmps where nome = 'A')) = 0
          and (select status from public.anotacoes_do_extrato where id = (select anotacao_id from public.comprovantes where id = pg_temp._id('A'))) = 'cancelada'
          and (select motivo_cancelamento from public.anotacoes_do_extrato where id = (select anotacao_id from public.comprovantes where id = pg_temp._id('A')))
              like 'CMP-%cancelado: comprei em dobro';
  v_det := v_det || 'A=' || coalesce(v_a->>'ok', '-') || ' ';
  -- custo interno em OS concluída (B): delete sem recálculo, o total da OS continua igual
  select grand_total, operational_cost_total into ob0 from public.service_orders where id = (select os from _cmps where nome = 'B');
  v_b := public.comprovante_cancelar(pg_temp._id('B'), 'não era da OS', pg_temp._dono());
  select grand_total, operational_cost_total into ob1 from public.service_orders where id = (select os from _cmps where nome = 'B');
  v_ok := v_ok and (v_b->>'ok')::boolean
          and not exists (select 1 from public.service_order_expenses where service_order_id = (select os from _cmps where nome = 'B'))
          and ob1.grand_total = ob0.grand_total and ob1.operational_cost_total = ob0.operational_cost_total;
  v_det := v_det || 'B=' || coalesce(v_b->>'ok', '-') || ' ';
  -- caixa (D): cancelar_lancamento estorna a conta do Caixa
  v_d := public.comprovante_cancelar(pg_temp._id('D'), 'lancei errado', pg_temp._dono());
  v_ok := v_ok and (v_d->>'ok')::boolean
          and (select status from public.payables where id = (select payable_id from public.comprovantes where id = pg_temp._id('D'))) = 'cancelled';
  v_det := v_det || 'D=' || coalesce(v_d->>'ok', '-') || ' ';
  -- itens_da_nota (I): as linhas voltam sem OS; a de outra OS fica
  v_i := public.comprovante_cancelar(pg_temp._id('I'), 'nota errada', pg_temp._dono());
  v_ok := v_ok and (v_i->>'ok')::boolean
          and (select count(*) from public.fiscal_note_items where fiscal_note_id = (select extra from _cmps where nome = 'I') and service_order_id is null) = 2
          and (select count(*) from public.fiscal_note_items where fiscal_note_id = (select extra from _cmps where nome = 'I') and service_order_id is not null) = 1;
  v_det := v_det || 'I=' || coalesce(v_i->>'ok', '-') || ' ';
  -- pendência (K) some; a anotação dele é cancelada — pelo comando do WhatsApp
  v_cmd := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'cancelar',
             'numero', (select numero from public.comprovantes where id = pg_temp._id('K')), 'motivo', 'era de outro mês'));
  v_ok := v_ok and v_cmd->>'resultado' = 'cancelado'
          and (select cardinality(pendencias) from public.comprovantes where id = pg_temp._id('K')) = 0
          and (select status from public.anotacoes_do_extrato where id = (select anotacao_id from public.comprovantes where id = pg_temp._id('K'))) = 'cancelada';
  v_det := v_det || 'K=' || coalesce(v_cmd->>'resultado', '-') || ' ';
  -- anexados (AD1, AD2, AD4): só desliga; despesa, anotação e conta continuam valendo
  v_ad1 := public.comprovante_cancelar(pg_temp._id('AD1'), 'anexei errado', pg_temp._dono());
  v_ad2 := public.comprovante_cancelar(pg_temp._id('AD2'), 'anexei errado', pg_temp._dono());
  v_ad4 := public.comprovante_cancelar(pg_temp._id('AD4'), 'anexei errado', pg_temp._dono());
  v_ok := v_ok and (v_ad1->>'ok')::boolean and (v_ad2->>'ok')::boolean and (v_ad4->>'ok')::boolean
          and exists (select 1 from public.service_order_expenses where id = (select extra from _cmps where nome = 'AD1'))
          and (select so_expense_id from public.comprovantes where id = pg_temp._id('AD1')) is null
          and (select status from public.anotacoes_do_extrato where id = (select extra from _cmps where nome = 'AD2')) = 'aguardando'
          and (select anotacao_id from public.comprovantes where id = pg_temp._id('AD2')) is null
          and (select status from public.payables where id = (select extra from _cmps where nome = 'AD4')) = 'paid'
          and (select payable_id from public.comprovantes where id = pg_temp._id('AD4')) is null;
  v_det := v_det || 'anexados=' || coalesce(v_ad1->>'ok', '-') || coalesce(v_ad2->>'ok', '-') || coalesce(v_ad4->>'ok', '-') || ' ';
  -- o CMP fica cancelado pelo dono, número queimado, arquivo para _CANCELADOS, índice refeito
  v_ok := v_ok and (select situacao = 'cancelado' and motivo_cancelamento = 'dono_cancelou' and cancelado_em is not null
                           and cancelado_por = pg_temp._dono() and cancelamento_texto = 'comprei em dobro'
                           and dropbox_pendente = 'cancelar' and numero is not null
                      from public.comprovantes where id = pg_temp._id('A'));
  -- cancelar de novo: recusa (já cancelado), nada muda
  v_dup := public.comprovante_cancelar(pg_temp._id('A'), 'de novo', pg_temp._dono());
  v_ok := v_ok and not (v_dup->>'ok')::boolean and v_dup->'bloqueios'->0->>'motivo' = 'ja_cancelado';
  insert into _resultado values ('X1 cancelar desfaz: custo interno da OS (aberta e concluída), anotação, Caixa, itens da nota, pendência, anexos',
    v_ok, v_det || 'de_novo=' || coalesce(v_dup->'bloqueios'->0->>'motivo', '-'));
exception when others then
  insert into _resultado values ('X1 cancelar desfaz: custo interno da OS (aberta e concluída), anotação, Caixa, itens da nota, pendência, anexos', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ Cancelamento: o que recusa (e nada muda) ═════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_fat uuid;
  v_aplic uuid;
  v_mes uuid;
  v_vm numeric := pg_temp._val();
  v_dia_velho date := (date_trunc('month', now() - interval '25 years') + interval '14 days')::date;
  r jsonb;
  v1 jsonb; v2 jsonb; v3 jsonb; v4 jsonb; v5 jsonb; v6 jsonb;
  v_linha_aplic uuid;
  v_curto text := 'nenhum erro';
  v_fila uuid;
  v_fila_r jsonb;
  v_ok boolean := true;
  v_det text := '';
begin
  -- custo interno numa OS que depois foi faturada: NÃO bloqueia (o comprovante nunca mexeu no total)
  v_fat := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'credito', 'destino', 'os', 'os', v_os,
                                                'tipo_na_os', 'despesa', 'categoria', 'Alimentação de campo'));
  r := pg_temp._gravar(v_fat);
  update public.service_orders set invoicing_status = 'invoiced' where id = v_os;
  v1 := public.comprovante_cancelar(v_fat, 'quero desfazer', pg_temp._dono());
  v_ok := v_ok and (v1->>'ok')::boolean and not exists (select 1 from public.service_order_expenses where service_order_id = v_os)
          and (select situacao from public.comprovantes where id = v_fat) = 'cancelado';
  v_det := v_det || 'faturada=' || coalesce(v1->>'ok', v1->'bloqueios'->0->>'motivo') || ' ';
  -- anotação já aplicada pelo Extrato e a linha dela aprovada (virou lançamento) → anotacao_aplicada.
  -- (Com a F3, a aplicada SEM lançamento na linha não bloqueia mais: o cancelamento devolve a linha ao
  -- motor — teste GX6 de comprovantes_gravacao_f3.sql.)
  v_aplic := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix', 'tipo', 'pix', 'favorecido', pg_temp._cnpj(),
                                                  'destino', 'empresa', 'categoria', 'Outras despesas'));
  r := pg_temp._gravar(v_aplic);
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type)
  values (pg_temp._hoje(), 'PIX ENVIADO TESTE F2', (select valor_confirmado from public.comprovantes where id = v_aplic), 'debit', 'bank')
  returning id into v_linha_aplic;
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               bank_transaction_id)
  select 'Aprovado no Extrato (teste F2)', pg_temp._hoje(), pg_temp._hoje(), x.valor_confirmado, x.valor_confirmado, 0, 'paid',
         'Outras despesas', v_linha_aplic
    from public.comprovantes x where x.id = v_aplic;
  update public.anotacoes_do_extrato set status = 'aplicada', aplicada_em = now(), bank_transaction_id = v_linha_aplic
   where id = (select anotacao_id from public.comprovantes where id = v_aplic);
  v2 := public.comprovante_cancelar(v_aplic, 'quero desfazer', pg_temp._dono());
  v_ok := v_ok and not (v2->>'ok')::boolean and v2->'bloqueios'->0->>'motivo' = 'anotacao_aplicada'
          and (select situacao from public.comprovantes where id = v_aplic) in ('gravado', 'aguardando_banco');
  v_det := v_det || 'aplicada=' || coalesce(v2->'bloqueios'->0->>'motivo', v2->>'ok') || ' ';
  -- Caixa num mês que depois foi fechado → mes_fechado (o mês de 25 anos atrás: nenhum lançamento real)
  v_mes := pg_temp._preparar(jsonb_build_object('valor', v_vm, 'forma', 'dinheiro', 'destino', 'insumo', 'quem', 'empresa',
                                                'data', v_dia_velho));
  update public.comprovantes set data_confirmada = v_dia_velho where id = v_mes;
  r := pg_temp._gravar(v_mes);
  insert into public.periodos_fechados (ano, mes) values (extract(year from v_dia_velho)::int, extract(month from v_dia_velho)::int);
  v3 := public.comprovante_cancelar(v_mes, 'quero desfazer', pg_temp._dono());
  v_ok := v_ok and r->>'resultado' = 'gravado' and not (v3->>'ok')::boolean and v3->'bloqueios'->0->>'motivo' = 'mes_fechado'
          and (select status from public.payables where id = (select payable_id from public.comprovantes where id = v_mes)) = 'paid';
  v_det := v_det || 'mes=' || coalesce(v3->'bloqueios'->0->>'motivo', v3->>'ok') || ' ';
  -- reembolso já pago → reembolso_pago; depois de desfeito o pagamento, cancela
  update public.payables set paid_amount = 1 where id = (select payable_id from public.comprovantes where id = pg_temp._id('E'));
  v4 := public.comprovante_cancelar(pg_temp._id('E'), 'quero desfazer', pg_temp._dono());
  update public.payables set paid_amount = 0 where id = (select payable_id from public.comprovantes where id = pg_temp._id('E'));
  v5 := public.comprovante_cancelar(pg_temp._id('E'), 'quero desfazer', pg_temp._dono());
  v_ok := v_ok and not (v4->>'ok')::boolean and v4->'bloqueios'->0->>'motivo' = 'reembolso_pago'
          and (v5->>'ok')::boolean
          and (select status from public.payables where id = (select payable_id from public.comprovantes where id = pg_temp._id('E'))) = 'cancelled';
  v_det := v_det || 'reembolso=' || coalesce(v4->'bloqueios'->0->>'motivo', v4->>'ok') || '/' || coalesce(v5->>'ok', '-') || ' ';
  -- CMP ainda não gravado (na fila): cancela direto, sem efeitos
  v_fila := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix'));
  v_fila_r := public.comprovante_cancelar(v_fila, 'foto errada', pg_temp._dono());
  v_ok := v_ok and (v_fila_r->>'ok')::boolean and jsonb_array_length(v_fila_r->'desfeitos') = 0
          and (select situacao from public.comprovantes where id = v_fila) = 'cancelado';
  -- motivo curto: recusa com 22023; comando sem motivo: motivo_obrigatorio
  begin
    perform public.comprovante_cancelar(v_aplic, 'ok', pg_temp._dono());
  exception when others then
    v_curto := sqlstate;
  end;
  v6 := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'cancelar',
          'numero', (select numero from public.comprovantes where id = v_aplic)));
  v_ok := v_ok and v_curto = '22023' and v6->>'resultado' = 'motivo_obrigatorio';
  v_det := v_det || 'fila=' || coalesce(v_fila_r->>'ok', '-') || ' curto=' || v_curto || ' sem_motivo=' || coalesce(v6->>'resultado', '-');
  insert into _resultado values ('X2 cancelar recusa (e nada muda): anotação aplicada, mês fechado, reembolso pago; a OS faturada não bloqueia o custo interno',
    v_ok, v_det);
exception when others then
  insert into _resultado values ('X2 cancelar recusa (e nada muda): anotação aplicada, mês fechado, reembolso pago; a OS faturada não bloqueia o custo interno', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ Rota que falha: nada gravado, a pergunta continua ════════════════════════════════════════
do $$
declare
  v_cmp uuid;
  v_p jsonb;
  r jsonb;
  v_dubla boolean;
begin
  v_dubla := pg_temp._rota('lancar_no_caixa', '{"modo":"erro","message":"Caixa fora do ar (ensaio)"}');
  v_cmp := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'dinheiro', 'destino', 'insumo', 'quem', 'empresa'));
  if not v_dubla then
    -- em produção: categoria que não existe faz a rota real recusar
    update public.comprovantes set categoria = 'Categoria que não existe F2' where id = v_cmp;
  end if;
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste'
   where phone_normalized = pg_temp._phone() and status = 'aberta';
  update public.comprovantes set passo = 'confirmar' where id = v_cmp;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  if v_p->>'passo' = 'confirmar' then
    r := pg_temp._sim(v_p);
  end if;
  insert into _resultado values ('R rota que falha: não grava nada e a pergunta do sim continua aberta',
    case when v_dubla
         then r->>'resultado' = 'nao_gravado' and r->>'motivo' like '%Caixa fora do ar%'
              and (select situacao from public.comprovantes where id = v_cmp) = 'aguardando_sim'
              and (select gravado_em from public.comprovantes where id = v_cmp) is null
              and (select status from public.whatsapp_perguntas where id = (v_p->>'pergunta_id')::uuid) = 'aberta'
         -- categoria inexistente: o passo "categoria" é perguntado antes do sim (nunca chega a gravar)
         else v_p->>'passo' = 'categoria' and (select gravado_em from public.comprovantes where id = v_cmp) is null end,
    'passo=' || coalesce(v_p->>'passo', '-') || ' resultado=' || coalesce(r->>'resultado', '-'));
exception when others then
  insert into _resultado values ('R rota que falha: não grava nada e a pergunta do sim continua aberta', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ LP: o link público (anon com o share token da OS) não vê o custo interno; vê a despesa manual ══
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_token text;
  v_manual uuid;
  v_interna uuid;
  v_cmp uuid;
  r jsonb;
  v_ve_manual integer;
  v_ve_interna integer;
  v_sem_token integer;
  v_col text := 'nenhum erro';
begin
  select share_token::text into v_token from public.service_orders where id = v_os;
  insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date, paid_by, billable_to_client)
  values (v_os, 'Frete e importação', 'frete lançado à mão', pg_temp._val(), pg_temp._hoje(), 'company', true)
  returning id into v_manual;
  v_cmp := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'credito', 'destino', 'os', 'os', v_os,
                                                'tipo_na_os', 'despesa', 'categoria', 'Combustível e deslocamento'));
  r := pg_temp._gravar(v_cmp);
  select so_expense_id into v_interna from public.comprovantes where id = v_cmp;
  -- como o link público: o papel anon com o token da OS na requisição (em produção, o cabeçalho
  -- x-share-token; no ensaio, o dublê de share_token_da_requisicao lê ensaio.share_token)
  perform set_config('request.headers', json_build_object('x-share-token', v_token)::text, true);
  perform set_config('ensaio.share_token', v_token, true);
  execute 'set local role anon';
  select count(*) filter (where id = v_manual), count(*) filter (where id = v_interna) into v_ve_manual, v_ve_interna
    from public.service_order_expenses where service_order_id = v_os;
  begin
    perform origem_codigo from public.service_order_expenses limit 1;
  exception when insufficient_privilege then
    v_col := sqlstate;
  end;
  perform set_config('request.headers', '{}', true);
  perform set_config('ensaio.share_token', '', true);
  select count(*) into v_sem_token from public.service_order_expenses where service_order_id = v_os;
  execute 'reset role';
  insert into _resultado values ('LP link público (anon com o token da OS): vê a despesa manual, não vê o custo interno nem a coluna da origem',
    r->>'resultado' = 'gravado' and v_interna is not null and v_ve_manual = 1 and v_ve_interna = 0 and v_col = '42501' and v_sem_token = 0,
    'manual=' || coalesce(v_ve_manual::text, '-') || ' interna=' || coalesce(v_ve_interna::text, '-') || ' coluna=' || v_col
    || ' sem_token=' || coalesce(v_sem_token::text, '-'));
exception when others then
  insert into _resultado values ('LP link público (anon com o token da OS): vê a despesa manual, não vê o custo interno nem a coluna da origem', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
