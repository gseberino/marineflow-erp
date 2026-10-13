-- Prova: a compra de campo sem "peça ou despesa?" e a pergunta que não saiu (migration 20261013100000; usa
-- 20261011202000, 20261011302000, 20261011303000 e 20261012100000).
--
--   C1  financial_categories.despesa_de_campo: boolean not null default false; as 3 de produção (quando ativas)
--       marcadas; categoria nova nasce sem a marca
--   C2  categoria DITA de campo numa OS (Pix, a empresa): sem "peça ou despesa?" nem "categoria"; o resumo diz
--       'despesa' pela categoria; comprovantes.tipo_na_os segue nulo; o plano é despesa_os; nada lançado
--   C3  sem categoria dita, a de sempre do fornecedor (2 contas da categoria de campo): sem pergunta, despesa_os
--   C4  continua perguntando: categoria sem a marca, sem categoria nem histórico, NF-e modelo 55, categoria
--       marcada mas inativa; e a despesa igual já na OS só é comprovada (anexar_despesa, sem "pela categoria")
--   C5  o dito vale: "peça" gravado → comprovar_na_os; no resumo pela categoria, "não" → "Peça ou despesa" →
--       passo forçado → "peça" → resumo peça
--   C6  "corrigir categoria" para uma sem a marca traz a pergunta de volta; "corrigir os" (outra OS) segue sem
--   C7  o SIM grava pela rota real: custo interno da OS (origem = o CMP, não faturável, a categoria de campo)
--   C8  comprovante_completar com a categoria de campo: sem pergunta de tipo; "despesa" dito = já estava; "peça"
--       dito = o passo forçado e respondido; nada no financeiro
--   C8e com o telefone ocupado (pendência do assistente), o "peça" dito força o passo: na vez dele, a pergunta
--       é "peça ou despesa?" (revisão de 13/10/2026)
--   C9 comprovantes_consultar (admin) mostra o tipo que vale
--   N1  a pergunta do vigia que não saiu: fecha (nao_enviada), o CMP volta à fila, a tentativa é devolvida, o
--       vigia espera 4 h e a última pergunta é a que saiu
--   N2  chamar de novo não muda nada
--   N3  o vigia não pega o CMP adiado; passado o adiamento, pega
--   N4  a pergunta do dono ("cmp N") que não saiu também devolve o CMP à fila (o defeito de 13/10), sem mexer na
--       contagem nem no adiamento
--   N5  nenhum CMP do telefone fica "perguntando"/"aguardando o sim" sem pergunta aberta
--   N6  F3: a pergunta do extrato do vigia que não saiu devolve banco_perguntas (o espaçamento e a situação ficam)
--   N7  a pergunta do vigia que JÁ saiu (enviada_em) fecha e volta à fila sem descontar nem adiar
--   P1  privilégios: _comprovante_tipo_na_os para ninguém; comprovante_pergunta_nao_enviada só service_role
--
-- ═══ COMO RODAR ═══ (só com OK nomeado; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/comprovante_despesa_de_campo_e_envio_falho.sql --output json
--
-- Seguro em produção: cria um dono de teste (admin com created_at em 2000, que vira o _comprovante_dono() só
-- dentro da transação), três categorias de despesa de nome aleatório (uma de campo, uma sem a marca e uma de
-- campo inativa), OS/clientes/barcos/fornecedores de mentira, liga a conversa só dentro da transação e termina
-- em ROLLBACK. O C7 grava pela rota real (custo interno numa OS de teste, no crédito: espera a fatura): tudo some
-- no rollback. Sem id nem data fixa. Nenhuma mensagem sai (a fila de envio não é tocada: as RPCs só abrem a
-- pergunta; quem manda é a edge).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (dono uuid, phone text, campo text, outra text, inativa text) on commit drop;
create temp table _cmps (nome text primary key, id uuid, extra uuid) on commit drop;

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
-- CNPJ de mentira (raiz 7xxxxxxx: nunca a da HBR)
create function pg_temp._cnpj() returns text language sql volatile as $$
  select '7' || lpad((floor(random() * 9999999))::bigint::text, 7, '0') || '0001' || lpad((floor(random() * 99))::bigint::text, 2, '0')
$$;
-- chave de NF-e modelo 55 (44 dígitos) de mentira
create function pg_temp._chave() returns text language sql volatile as $$
  select '352610' || '112223330001' || '81' || '55' || '001'
         || lpad((floor(random() * 999999999))::bigint::text, 9, '0') || '1'
         || lpad((floor(random() * 99999999))::bigint::text, 8, '0') || '0'
$$;

do $$
declare
  v_dono uuid := gen_random_uuid();
  v_phone text := pg_temp._telefone();
  v_campo text := 'Categoria teste campo ' || pg_temp._letras(8);
  v_outra text := 'Categoria teste outra ' || pg_temp._letras(8);
  v_inativa text := 'Categoria teste inativa ' || pg_temp._letras(8);
begin
  insert into public.app_users (id, full_name, email, role, active, phone_normalized, ai_whatsapp_enabled, created_at)
  values (v_dono, 'Dono de teste 1310', 'teste-1310-' || v_dono || '@teste.invalido', 'admin', true, v_phone, true,
          now() - interval '30 years');
  insert into public.app_settings (key, value) values ('comprovante_fluxo', 'dono')
  on conflict (key) do update set value = excluded.value;
  insert into public.app_settings (key, value) values ('comprovante_conversa', 'on')
  on conflict (key) do update set value = excluded.value;
  -- as categorias do teste (nome aleatório: não dependem das de produção)
  insert into public.financial_categories (name, type, active, dre_group, despesa_de_campo)
  values (v_campo, 'payable', true, 'custo_direto', true),
         (v_outra, 'payable', true, 'custo_direto', false),
         (v_inativa, 'payable', false, 'custo_direto', true);
  insert into _ctx values (v_dono, v_phone, v_campo, v_outra, v_inativa);
end $$;

create function pg_temp._dono() returns uuid language sql stable as $$ select dono from _ctx $$;
create function pg_temp._phone() returns text language sql stable as $$ select phone from _ctx $$;
create function pg_temp._campo() returns text language sql stable as $$ select campo from _ctx $$;
create function pg_temp._outra() returns text language sql stable as $$ select outra from _ctx $$;
create function pg_temp._inativa() returns text language sql stable as $$ select inativa from _ctx $$;
create function pg_temp._id(p_nome text) returns uuid language sql stable as $$ select id from _cmps where nome = p_nome $$;
create function pg_temp._extra(p_nome text) returns uuid language sql stable as $$ select extra from _cmps where nome = p_nome $$;

-- OS de teste com cliente e barco próprios; número OS-9xxxxx livre
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
  insert into public.clients (type, name) values ('individual', 'Cliente Teste 1310 ' || pg_temp._letras(6)) returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Navio' || pg_temp._letras(8)) returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, invoicing_status,
                                     grand_total, operational_cost_total, labor_cost_total, travel_cost_total)
  values ('OS-' || v_num, v_cli, v_ves, 'open', 'not_invoiced', 0, 0, 0, 0)
  returning id into v_os;
  return v_os;
end $$;

create function pg_temp._os_num(p_os uuid) returns integer language sql stable as $$
  select substring(service_order_number from '([0-9]+)$')::integer from public.service_orders where id = p_os
$$;

-- um CMP lido do dono de teste (direto na tabela: o caminho da F1 tem os próprios testes)
create function pg_temp._cmp(p jsonb default '{}'::jsonb) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized,
                                   tipo_whatsapp, recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca,
                                   data_compra, data_confianca, forma_pagamento, lido_em)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(),
          'TESTE-1310-' || gen_random_uuid(), pg_temp._phone(), 'image', now(),
          md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text),
          'nfce', 'alta', coalesce((p->>'valor')::numeric, pg_temp._val()), 'alta', pg_temp._hoje(), 'alta', p->>'forma', now())
  returning id into v;
  return v;
end $$;

-- CMP já lido e na fila, com as respostas dadas (como em comprovantes_gravacao.sql)
create function pg_temp._preparar(p jsonb) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized,
                                   tipo_whatsapp, recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca,
                                   data_compra, data_confianca, forma_pagamento, chave_acesso, lido_em,
                                   emitente_cnpj, cnpj_confianca, supplier_id)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(),
          'TESTE-1310-' || gen_random_uuid(), pg_temp._phone(), 'image', now(),
          md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text),
          coalesce(p->>'tipo', 'nfce'), 'alta', (p->>'valor')::numeric, 'alta', pg_temp._hoje(), 'alta', p->>'forma',
          p->>'chave', now(), p->>'cnpj', case when p ? 'cnpj' then 'alta' end, nullif(p->>'fornecedor', '')::uuid)
  returning id into v;
  perform public.comprovante_conversa_entrar(array[v]);
  update public.comprovantes
     set destino = p->>'destino', destino_os_id = nullif(p->>'os', '')::uuid, tipo_na_os = p->>'tipo_na_os',
         quem_pagou = p->>'quem', categoria = p->>'categoria'
   where id = v;
  return v;
end $$;

create function pg_temp._numero(p_id uuid) returns integer language sql stable as $$
  select numero from public.comprovantes where id = p_id
$$;
create function pg_temp._linha(p_id uuid) returns public.comprovantes language sql stable as $$
  select x.* from public.comprovantes x where x.id = p_id
$$;

-- deixa o telefone livre: fecha a pergunta aberta e tira da fila o que sobrou do teste anterior
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

create function pg_temp._abertas() returns integer language sql stable as $$
  select count(*)::integer from public.whatsapp_perguntas where phone_normalized = pg_temp._phone() and status = 'aberta'
$$;

-- a mensagem do dono (texto recebido) DEPOIS da pergunta; devolve o id (o que o edge manda ao responder)
create function pg_temp._msg() returns uuid language sql as $$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', pg_temp._phone(), 'text', 'teste', 'TESTE-1310-' || gen_random_uuid(), now() + interval '10 seconds')
  returning id
$$;

-- como o edge: a pergunta foi enviada (whatsapp-send confirmou) e o dono respondeu DEPOIS dela
create function pg_temp._responder(p_pergunta jsonb, p_interp jsonb) returns jsonb language plpgsql as $$
begin
  perform public.pergunta_marcar_enviada((p_pergunta->>'pergunta_id')::uuid, 'WA-' || (p_pergunta->>'pergunta_id'));
  return public.comprovante_responder(jsonb_build_object(
    'pergunta_id', p_pergunta->>'pergunta_id', 'message_id', pg_temp._msg(), 'interpretacao', p_interp));
end $$;

-- abre o resumo (RPC 7) e responde sim (RPC 9)
create function pg_temp._gravar(p_cmp uuid) returns jsonb language plpgsql as $$
declare
  v_p jsonb;
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste'
   where phone_normalized = pg_temp._phone() and status = 'aberta';
  update public.comprovantes set situacao = 'aguardando_vez'
   where phone_normalized = pg_temp._phone() and situacao in ('perguntando', 'aguardando_sim');
  update public.comprovantes set fila_ordem = now() + interval '1 day'
   where phone_normalized = pg_temp._phone() and situacao = 'aguardando_vez' and id <> p_cmp;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', p_cmp);
  if not coalesce((v_p->>'perguntou')::boolean, false) or v_p->>'passo' is distinct from 'confirmar' then
    return jsonb_build_object('resultado', 'nao_chegou_no_confirmar', 'passo', v_p->>'passo', 'motivo', v_p->>'motivo');
  end if;
  return pg_temp._responder(v_p, jsonb_build_object('tipo', 'sim')) || jsonb_build_object('plano_mostrado', v_p->'plano');
end $$;

-- o pedido do assistente, como a edge manda (o dono, o telefone e o número do CMP já postos)
create function pg_temp._completar(p_id uuid, p jsonb) returns jsonb language sql as $$
  select public.comprovante_completar(jsonb_build_object('phone', pg_temp._phone(), 'autor', pg_temp._dono(),
                                                         'cmp', pg_temp._numero(p_id)) || p)
$$;

-- os tipos dos efeitos de um plano, na ordem ("despesa_os,aguardar_fatura")
create function pg_temp._tipos(p_efeitos jsonb) returns text language sql immutable as $$
  select coalesce(string_agg(e->>'tipo' || case when e->>'tipo' = 'pendencia' then ':' || (e->>'qual') else '' end, ',' order by o), '')
    from jsonb_array_elements(coalesce(p_efeitos, '[]'::jsonb)) with ordinality as t(e, o)
$$;
-- o efeito de um tipo (o primeiro)
create function pg_temp._efeito(p_plano jsonb, p_tipo text) returns jsonb language sql immutable as $$
  select e from jsonb_array_elements(coalesce(p_plano->'efeitos', '[]'::jsonb)) with ordinality as t(e, o)
   where e->>'tipo' = p_tipo order by o limit 1
$$;

-- ═══ C1 a marca na categoria ═════════════════════════════════════════════════════════════════
do $$
declare
  v_col record;
  v_nova boolean;
  v_ativas integer;
  v_marcadas integer;
begin
  select k.is_nullable, k.column_default, k.data_type into v_col
    from information_schema.columns k
   where k.table_schema = 'public' and k.table_name = 'financial_categories' and k.column_name = 'despesa_de_campo';
  insert into public.financial_categories (name, type, active, dre_group)
  values ('Categoria teste nova ' || pg_temp._letras(8), 'payable', true, 'custo_direto')
  returning despesa_de_campo into v_nova;
  select count(*) filter (where coalesce(f.active, false)), count(*) filter (where coalesce(f.active, false) and f.despesa_de_campo)
    into v_ativas, v_marcadas
    from public.financial_categories f
   where f.type = 'payable' and f.name in ('Combustível e deslocamento', 'Alimentação de campo', 'Pedágio e estacionamento');
  insert into _resultado values ('C1 despesa_de_campo é boolean not null default false; as 3 de campo ativas marcadas; a nova nasce sem',
    v_col.data_type = 'boolean' and v_col.is_nullable = 'NO' and v_col.column_default = 'false'
    and v_nova is false and v_marcadas = v_ativas,
    'coluna=' || coalesce(v_col.data_type, '-') || '/' || coalesce(v_col.is_nullable, '-') || '/' || coalesce(v_col.column_default, '-')
    || ' nova=' || coalesce(v_nova::text, '-') || ' ativas=' || v_ativas || ' marcadas=' || v_marcadas);
exception when others then
  insert into _resultado values ('C1 despesa_de_campo é boolean not null default false; as 3 de campo ativas marcadas; a nova nasce sem',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C2 a categoria DITA de campo ════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_val numeric := pg_temp._val();
  v uuid;
  x public.comprovantes;
  v_passo text;
  v_res jsonb;
  v_plano jsonb;
  v_desp jsonb;
  v_p jsonb;
  v_lancadas integer;
  v_tipo_depois text;
begin
  perform pg_temp._livrar();
  v := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'pix', 'destino', 'os', 'os', v_os, 'quem', 'empresa',
                                            'categoria', pg_temp._campo()));
  x := pg_temp._linha(v);
  v_passo := public._comprovante_proximo_passo(x);
  v_res := public._comprovante_resumo(x);
  v_plano := public._comprovante_plano(v);
  v_desp := pg_temp._efeito(v_plano, 'despesa_os');
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v);
  select count(*) into v_lancadas from public.service_order_expenses where origem_codigo = x.codigo;
  select tipo_na_os into v_tipo_depois from public.comprovantes where id = v;
  insert into _resultado values ('C2 categoria dita de campo numa OS: sem "peça ou despesa?"; resumo despesa pela categoria; plano despesa_os; nada lançado',
    v_passo = 'confirmar' and x.tipo_na_os is null and v_tipo_depois is null
    and v_res->>'tipo_na_os' = 'despesa' and v_res->'tipo_na_os_pela_categoria' = 'true'::jsonb
    and v_res->>'categoria' = pg_temp._campo()
    and not (v_plano ? 'falta') and v_desp->>'categoria' = pg_temp._campo() and v_desp->>'paid_by' = 'company'
    and (v_desp->>'os_id')::uuid = v_os
    and v_p->>'passo' = 'confirmar' and v_p->'cmp'->>'tipo_na_os' = 'despesa'
    and v_p->'cmp'->'tipo_na_os_pela_categoria' = 'true'::jsonb
    and v_lancadas = 0 and x.gravado_em is null,
    'passo=' || coalesce(v_passo, '-') || ' resumo=' || coalesce(v_res->>'tipo_na_os', 'null') || '/'
    || coalesce(v_res->>'tipo_na_os_pela_categoria', '-') || ' plano=' || pg_temp._tipos(v_plano->'efeitos')
    || coalesce(' falta=' || (v_plano->>'falta'), '') || ' pergunta=' || coalesce(v_p->>'passo', v_p->>'motivo', '-')
    || ' lancadas=' || v_lancadas);
exception when others then
  insert into _resultado values ('C2 categoria dita de campo numa OS: sem "peça ou despesa?"; resumo despesa pela categoria; plano despesa_os; nada lançado',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C3 a categoria de sempre do fornecedor ═════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_val numeric := pg_temp._val();
  v_sup uuid;
  v uuid;
  x public.comprovantes;
  v_passo text;
  v_res jsonb;
  v_plano jsonb;
begin
  perform pg_temp._livrar();
  insert into public.suppliers (name, cnpj_cpf) values ('Fornecedor Teste 1310 ' || pg_temp._letras(6), pg_temp._cnpj())
  returning id into v_sup;
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               origin, payment_method, supplier_id)
  values ('teste 1310 a', pg_temp._hoje() - 20, pg_temp._hoje() - 20, v_val + 1, v_val + 1, 0, 'paid', pg_temp._campo(), 'manual', 'cash', v_sup),
         ('teste 1310 b', pg_temp._hoje() - 40, pg_temp._hoje() - 40, v_val + 2, v_val + 2, 0, 'paid', pg_temp._campo(), 'manual', 'cash', v_sup);
  v := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'credito', 'destino', 'os', 'os', v_os, 'fornecedor', v_sup));
  x := pg_temp._linha(v);
  v_passo := public._comprovante_proximo_passo(x);
  v_res := public._comprovante_resumo(x);
  v_plano := public._comprovante_plano(v);
  insert into _resultado values ('C3 sem categoria dita, a de sempre do fornecedor é de campo: sem pergunta, despesa_os com ela',
    public._comprovante_categoria_provavel(v_sup) = pg_temp._campo() and x.categoria is null
    and v_passo = 'confirmar' and v_res->>'tipo_na_os' = 'despesa' and v_res->'tipo_na_os_pela_categoria' = 'true'::jsonb
    and v_res->>'categoria' = pg_temp._campo()
    and pg_temp._efeito(v_plano, 'despesa_os')->>'categoria' = pg_temp._campo(),
    'provavel=' || coalesce((public._comprovante_categoria_provavel(v_sup) = pg_temp._campo())::text, 'null')
    || ' passo=' || coalesce(v_passo, '-') || ' resumo=' || coalesce(v_res->>'tipo_na_os', 'null')
    || ' plano=' || pg_temp._tipos(v_plano->'efeitos'));
exception when others then
  insert into _resultado values ('C3 sem categoria dita, a de sempre do fornecedor é de campo: sem pergunta, despesa_os com ela',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C4 continua perguntando (e o que já está na OS só é comprovado) ═════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_val numeric := pg_temp._val();
  a uuid; b uuid; c uuid; d uuid; e uuid;
  v_desp uuid;
  v_pa text; v_pb text; v_pc text; v_pd text; v_pe text;
  v_res jsonb;
  v_plano jsonb;
begin
  perform pg_temp._livrar();
  a := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix', 'destino', 'os', 'os', v_os,
                                            'categoria', pg_temp._outra()));
  b := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix', 'destino', 'os', 'os', v_os));
  c := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'tipo', 'nfe_danfe', 'chave', pg_temp._chave(),
                                            'destino', 'os', 'os', v_os, 'categoria', pg_temp._campo()));
  d := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix', 'destino', 'os', 'os', v_os,
                                            'categoria', pg_temp._inativa()));
  -- a despesa do mesmo valor e data já lançada na OS (à mão, sem fornecedor): o CMP só a comprova
  insert into public.service_order_expenses (service_order_id, category, description, amount, expense_date, paid_by, billable_to_client)
  values (v_os, pg_temp._campo(), 'lançada antes pela tela', v_val, pg_temp._hoje(), 'company', false) returning id into v_desp;
  e := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'credito', 'destino', 'os', 'os', v_os,
                                            'categoria', pg_temp._campo()));
  v_pa := public._comprovante_proximo_passo(pg_temp._linha(a));
  v_pb := public._comprovante_proximo_passo(pg_temp._linha(b));
  v_pc := public._comprovante_proximo_passo(pg_temp._linha(c));
  v_pd := public._comprovante_proximo_passo(pg_temp._linha(d));
  v_pe := public._comprovante_proximo_passo(pg_temp._linha(e));
  v_res := public._comprovante_resumo(pg_temp._linha(e));
  v_plano := public._comprovante_plano(e);
  insert into _resultado values ('C4 continua perguntando: sem a marca, sem categoria, NF-e e marcada inativa; o que já está na OS só é comprovado',
    v_pa = 'tipo_na_os' and v_pb = 'tipo_na_os' and v_pc = 'tipo_na_os' and v_pd = 'tipo_na_os'
    and public._comprovante_tipo_na_os(pg_temp._linha(a)) is null and public._comprovante_tipo_na_os(pg_temp._linha(c)) is null
    and v_pe = 'confirmar' and v_res->>'tipo_na_os' is null and v_res->'tipo_na_os_pela_categoria' = 'false'::jsonb
    and v_res->'na_os'->>'tipo' = 'despesa' and (v_res->'na_os'->>'id')::uuid = v_desp
    and pg_temp._tipos(v_plano->'efeitos') like 'anexar_despesa%'
    and (pg_temp._efeito(v_plano, 'anexar_despesa')->>'so_expense_id')::uuid = v_desp
    and pg_temp._efeito(v_plano, 'despesa_os') is null,
    'sem_marca=' || coalesce(v_pa, '-') || ' sem_categoria=' || coalesce(v_pb, '-') || ' nfe=' || coalesce(v_pc, '-')
    || ' inativa=' || coalesce(v_pd, '-') || ' ja_na_os=' || coalesce(v_pe, '-') || '/' || coalesce(v_res->>'tipo_na_os', 'null')
    || '/' || coalesce(v_res->>'tipo_na_os_pela_categoria', '-') || ' plano=' || pg_temp._tipos(v_plano->'efeitos'));
exception when others then
  insert into _resultado values ('C4 continua perguntando: sem a marca, sem categoria, NF-e e marcada inativa; o que já está na OS só é comprovado',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C5 o dito vale ═════════════════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  a uuid;
  b uuid;
  v_res_a jsonb;
  v_plano_a jsonb;
  v_p jsonb;
  v_nao jsonb;
  v_menu jsonb;
  v_forcado jsonb;
  v_peca jsonb;
begin
  perform pg_temp._livrar();
  -- (a) "peça" gravado + a categoria de campo: o dito vale
  a := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'credito', 'destino', 'os', 'os', v_os,
                                            'tipo_na_os', 'peca', 'categoria', pg_temp._campo()));
  v_res_a := public._comprovante_resumo(pg_temp._linha(a));
  v_plano_a := public._comprovante_plano(a);
  perform pg_temp._livrar();
  -- (b) no resumo pela categoria: "não" → menu → "Peça ou despesa" → passo forçado → "peça"
  b := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'credito', 'destino', 'os', 'os', v_os,
                                            'categoria', pg_temp._campo()));
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', b);
  v_nao := pg_temp._responder(v_p, jsonb_build_object('tipo', 'nao'));
  v_menu := v_nao->'proxima';
  v_forcado := pg_temp._responder(v_menu, jsonb_build_object('tipo', 'opcao', 'n',
                 (select (o->>'n')::int from jsonb_array_elements(v_menu->'opcoes') o where o->>'valor' = 'tipo_na_os')));
  v_peca := pg_temp._responder(v_forcado->'proxima', jsonb_build_object('tipo', 'palavra', 'valor', 'peca'));
  insert into _resultado values ('C5 o dito vale: "peça" gravado comprova; no resumo pela categoria, não → Peça ou despesa → peça',
    v_res_a->>'tipo_na_os' = 'peca' and v_res_a->'tipo_na_os_pela_categoria' = 'false'::jsonb
    and pg_temp._efeito(v_plano_a, 'comprovar_na_os')->>'motivo' = 'peca' and pg_temp._efeito(v_plano_a, 'despesa_os') is null
    and v_p->>'passo' = 'confirmar' and v_p->'cmp'->>'tipo_na_os' = 'despesa'
    and v_nao->>'resultado' = 'corrigir' and v_menu->>'passo' = 'corrigir'
    and v_forcado->'proxima'->>'passo' = 'tipo_na_os' and v_forcado->'proxima'->>'forcado' = 'true'
    and v_peca->>'resultado' = 'resumo' and v_peca->'proxima'->>'passo' = 'confirmar'
    and v_peca->'cmp'->>'tipo_na_os' = 'peca' and v_peca->'cmp'->'tipo_na_os_pela_categoria' = 'false'::jsonb
    and (select tipo_na_os from public.comprovantes where id = b) = 'peca',
    'gravado=' || coalesce(v_res_a->>'tipo_na_os', 'null') || '/' || pg_temp._tipos(v_plano_a->'efeitos')
    || ' resumo=' || coalesce(v_p->>'passo', '-') || '/' || coalesce(v_p->'cmp'->>'tipo_na_os', 'null')
    || ' nao=' || coalesce(v_nao->>'resultado', '-') || ' forcado=' || coalesce(v_forcado->'proxima'->>'passo', '-')
    || '/' || coalesce(v_forcado->'proxima'->>'forcado', '-') || ' peca=' || coalesce(v_peca->>'resultado', '-')
    || '/' || coalesce(v_peca->'cmp'->>'tipo_na_os', 'null'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('C5 o dito vale: "peça" gravado comprova; no resumo pela categoria, não → Peça ou despesa → peça',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C6 corrigir categoria / corrigir os ════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_os2 uuid := pg_temp._os();
  a uuid;
  b uuid;
  v_cat jsonb;
  v_os_r jsonb;
begin
  perform pg_temp._livrar();
  a := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix', 'destino', 'os', 'os', v_os,
                                            'categoria', pg_temp._campo()));
  v_cat := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'message_id', null, 'comando', 'corrigir',
             'cmp', pg_temp._numero(a), 'campo', 'categoria', 'categoria', pg_temp._outra()));
  perform pg_temp._livrar();
  b := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix', 'destino', 'os', 'os', v_os,
                                            'categoria', pg_temp._campo()));
  v_os_r := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'message_id', null, 'comando', 'corrigir',
              'cmp', pg_temp._numero(b), 'campo', 'os', 'numero', pg_temp._os_num(v_os2)));
  insert into _resultado values ('C6 corrigir categoria para uma sem a marca pergunta "peça ou despesa?"; corrigir os (outra OS) segue sem',
    v_cat->>'resultado' = 'pergunta' and v_cat->'pergunta'->>'passo' = 'tipo_na_os'
    and v_cat->'pergunta'->'cmp'->>'tipo_na_os' is null
    and v_os_r->>'resultado' = 'pergunta' and v_os_r->'pergunta'->>'passo' = 'confirmar'
    and v_os_r->'pergunta'->'cmp'->>'tipo_na_os' = 'despesa'
    and (select destino_os_id from public.comprovantes where id = b) = v_os2
    and (select tipo_na_os from public.comprovantes where id = b) is null,
    'categoria=' || coalesce(v_cat->>'resultado', '-') || '/' || coalesce(v_cat->'pergunta'->>'passo', v_cat->>'motivo', '-')
    || ' os=' || coalesce(v_os_r->>'resultado', '-') || '/' || coalesce(v_os_r->'pergunta'->>'passo', v_os_r->>'motivo', '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('C6 corrigir categoria para uma sem a marca pergunta "peça ou despesa?"; corrigir os (outra OS) segue sem',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C7 o SIM grava pela rota real ══════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v_val numeric := pg_temp._val();
  v uuid;
  r jsonb;
  x public.comprovantes;
  d record;
  v_n integer;
  o record;
begin
  perform pg_temp._livrar();
  v := pg_temp._preparar(jsonb_build_object('valor', v_val, 'forma', 'credito', 'destino', 'os', 'os', v_os,
                                            'categoria', pg_temp._campo()));
  r := pg_temp._gravar(v);
  x := pg_temp._linha(v);
  select count(*) into v_n from public.service_order_expenses where origem_codigo = x.codigo;
  select * into d from public.service_order_expenses where origem_codigo = x.codigo limit 1;
  select grand_total into o from public.service_orders where id = v_os;
  insert into _resultado values ('C7 o SIM grava a despesa da OS pela categoria: custo interno (origem = o CMP, não faturável), total igual',
    r->>'resultado' = 'gravado' and x.gravado_em is not null and x.tipo_na_os is null
    and pg_temp._tipos(x.efeitos) like 'despesa_os%' and v_n = 1
    and d.amount = v_val and not d.billable_to_client and d.category = pg_temp._campo() and d.service_order_id = v_os
    and o.grand_total = 0
    and r->'cmp'->>'tipo_na_os' = 'despesa' and public._comprovante_resumo(x)->>'tipo_na_os' = 'despesa',
    'resultado=' || coalesce(r->>'resultado', '-') || ' ' || coalesce(r->>'passo', r->>'motivo', '') || ' efeitos=' || pg_temp._tipos(x.efeitos)
    || ' despesas=' || v_n || ' categoria_ok=' || coalesce((d.category = pg_temp._campo())::text, '-')
    || ' billable=' || coalesce(d.billable_to_client::text, '-') || ' resumo=' || coalesce(r->'cmp'->>'tipo_na_os', 'null'));
exception when others then
  insert into _resultado values ('C7 o SIM grava a despesa da OS pela categoria: custo interno (origem = o CMP, não faturável), total igual',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C8 comprovante_completar com a categoria de campo ══════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  a uuid := pg_temp._cmp(jsonb_build_object('forma', 'pix'));
  b uuid := pg_temp._cmp(jsonb_build_object('forma', 'pix'));
  c uuid := pg_temp._cmp(jsonb_build_object('forma', 'pix'));
  v_ra jsonb; v_rb jsonb; v_rc jsonb;
  v_tipo_a integer;
  v_abertas_c integer;
  v_pay integer; v_anot integer; v_desp integer;
begin
  perform pg_temp._livrar();
  select count(*) into v_pay from public.payables;
  select count(*) into v_anot from public.anotacoes_do_extrato;
  select count(*) into v_desp from public.service_order_expenses;
  perform public.comprovante_conversa_entrar(array[a, b, c]);
  -- (a) a categoria de campo e a OS: o passo "peça ou despesa?" não vem
  v_ra := pg_temp._completar(a, jsonb_build_object('categoria', pg_temp._campo(), 'os', pg_temp._os_num(v_os)));
  select count(*) into v_tipo_a from public.whatsapp_perguntas
   where phone_normalized = pg_temp._phone() and referencia_id = a and passo = 'tipo_na_os';
  -- (b) + "despesa" dito: o mesmo que a categoria diz = já estava
  v_rb := pg_temp._completar(b, jsonb_build_object('categoria', pg_temp._campo(), 'os', pg_temp._os_num(v_os), 'tipo_na_os', 'despesa'));
  -- (c) + "peça" dito: o passo é forçado e respondido
  v_rc := pg_temp._completar(c, jsonb_build_object('categoria', pg_temp._campo(), 'os', pg_temp._os_num(v_os), 'tipo_na_os', 'peca'));
  v_abertas_c := pg_temp._abertas();
  insert into _resultado values ('C8 completar com a categoria de campo: sem pergunta de tipo; "despesa" = já estava; "peça" = forçado e respondido; nada no financeiro',
    v_ra->>'resultado' = 'ok' and v_ra->'aplicados' = '["categoria", "os"]'::jsonb and v_ra->'ignorados' = '[]'::jsonb
    and v_ra->'pergunta'->>'passo' = 'confirmar' and v_ra->'pergunta'->'cmp'->>'tipo_na_os' = 'despesa' and v_tipo_a = 0
    and v_rb->>'resultado' = 'ok' and v_rb->'ja_estava' ? 'tipo_na_os' and v_rb->'ignorados' = '[]'::jsonb
    and not (v_rb->'aplicados' ? 'tipo_na_os') and v_rb->'pergunta'->>'passo' = 'confirmar'
    and (select tipo_na_os from public.comprovantes where id = b) is null
    and v_rc->>'resultado' = 'ok' and v_rc->'aplicados' ? 'tipo_na_os' and v_rc->'ignorados' = '[]'::jsonb
    and exists (select 1 from jsonb_array_elements(v_rc->'itens') i where i->>'campo' = 'tipo_na_os' and i->>'valor' = 'peca')
    and v_rc->'pergunta'->>'passo' = 'confirmar' and v_rc->'pergunta'->'cmp'->>'tipo_na_os' = 'peca'
    and (select tipo_na_os from public.comprovantes where id = c) = 'peca' and v_abertas_c = 1
    and (select count(*) from public.comprovantes where id in (a, b, c) and gravado_em is not null) = 0
    and (select count(*) from public.payables) = v_pay and (select count(*) from public.anotacoes_do_extrato) = v_anot
    and (select count(*) from public.service_order_expenses) = v_desp,
    'a=' || coalesce(v_ra->>'resultado', '-') || ' ' || coalesce(v_ra->>'aplicados', '-') || ' ign=' || coalesce(v_ra->>'ignorados', '-')
    || ' passo=' || coalesce(v_ra->'pergunta'->>'passo', '-') || ' tipo_perguntas=' || v_tipo_a
    || ' | b=' || coalesce(v_rb->>'resultado', '-') || ' ja=' || coalesce(v_rb->>'ja_estava', '-') || ' ign=' || coalesce(v_rb->>'ignorados', '-')
    || ' | c=' || coalesce(v_rc->>'resultado', '-') || ' ' || coalesce(v_rc->>'aplicados', '-') || ' ign=' || coalesce(v_rc->>'ignorados', '-')
    || ' passo=' || coalesce(v_rc->'pergunta'->>'passo', '-') || '/' || coalesce(v_rc->'pergunta'->'cmp'->>'tipo_na_os', 'null')
    || ' abertas=' || v_abertas_c);
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('C8 completar com a categoria de campo: sem pergunta de tipo; "despesa" = já estava; "peça" = forçado e respondido; nada no financeiro',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C9 a consulta do assistente ════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  v uuid;
  r jsonb;
begin
  perform pg_temp._livrar();
  v := pg_temp._preparar(jsonb_build_object('valor', pg_temp._val(), 'forma', 'pix', 'destino', 'os', 'os', v_os,
                                            'categoria', pg_temp._campo()));
  r := public.comprovantes_consultar(jsonb_build_object('numero', pg_temp._numero(v), 'autor', pg_temp._dono()));
  insert into _resultado values ('C9 comprovantes_consultar (admin) mostra o tipo que vale (despesa pela categoria)',
    (r->>'total')::integer = 1 and r->'itens'->0->>'tipo_na_os' = 'despesa'
    and (select tipo_na_os from public.comprovantes where id = v) is null,
    'total=' || coalesce(r->>'total', '-') || ' tipo=' || coalesce(r->'itens'->0->>'tipo_na_os', 'null'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('C9 comprovantes_consultar (admin) mostra o tipo que vale (despesa pela categoria)',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C8e completar com o telefone ocupado (revisão de 13/10/2026) ═══════════════════════════
do $$
declare
  v_os uuid := pg_temp._os();
  d uuid := pg_temp._cmp(jsonb_build_object('forma', 'pix'));
  v_sess uuid;
  v_rd jsonb;
  v_passo_ocupado text;
  v_tipo_ocupado text;
  v_p jsonb;
  v_peca jsonb;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[d]);
  -- a pendência do assistente (a lista de opções de agora há pouco) segura o telefone
  insert into public.ai_operator_sessions (channel, external_thread_key, status, metadata, last_activity_at)
  values ('whatsapp', pg_temp._phone(), 'open', '{"pending_options":[{"n":1,"label":"x"}]}'::jsonb, now())
  returning id into v_sess;
  v_rd := pg_temp._completar(d, jsonb_build_object('categoria', pg_temp._campo(), 'os', pg_temp._os_num(v_os), 'tipo_na_os', 'peca'));
  select passo, tipo_na_os into v_passo_ocupado, v_tipo_ocupado from public.comprovantes where id = d;
  -- a pendência acabou: na vez dele, a pergunta é "peça ou despesa?" (o "peça" dito não se perde no resumo
  -- pela categoria)
  update public.ai_operator_sessions set metadata = '{}'::jsonb where id = v_sess;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', d);
  v_peca := pg_temp._responder(v_p, jsonb_build_object('tipo', 'palavra', 'valor', 'peca'));
  insert into _resultado values ('C8e completar com o telefone ocupado: o "peça" dito com a categoria de campo força o passo; na vez dele, "peça ou despesa?"',
    v_rd->>'resultado' = 'ok' and v_rd->'aplicados' = '["categoria", "os"]'::jsonb and v_rd->'ignorados' = '["tipo_na_os"]'::jsonb
    and v_rd->'pergunta' = 'null'::jsonb and v_rd->>'ocupado' = 'true'
    and v_passo_ocupado = 'tipo_na_os' and v_tipo_ocupado is null
    and v_p->>'perguntou' = 'true' and v_p->>'passo' = 'tipo_na_os'
    and v_peca->>'resultado' = 'resumo' and v_peca->'cmp'->>'tipo_na_os' = 'peca'
    and (select gravado_em from public.comprovantes where id = d) is null,
    'r=' || coalesce(v_rd->>'resultado', '-') || ' ' || coalesce(v_rd->>'aplicados', '-') || ' ign=' || coalesce(v_rd->>'ignorados', '-')
    || ' ocupado=' || coalesce(v_rd->>'ocupado', '-') || ' passo_ocupado=' || coalesce(v_passo_ocupado, 'null')
    || ' depois=' || coalesce(v_p->>'passo', v_p->>'motivo', '-') || ' peca=' || coalesce(v_peca->>'resultado', '-')
    || '/' || coalesce(v_peca->'cmp'->>'tipo_na_os', 'null'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('C8e completar com o telefone ocupado: o "peça" dito com a categoria de campo força o passo; na vez dele, "peça ou despesa?"',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ N1 a pergunta do vigia que não saiu ════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp(jsonb_build_object('forma', 'pix'));
  v_p0 jsonb;
  v_ab jsonb;
  v_pid uuid;
  v_meio record;
  v_depois record;
  w record;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v]);
  -- a pergunta de ontem, que saiu e expirou sem resposta
  v_p0 := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v);
  perform public.pergunta_marcar_enviada((v_p0->>'pergunta_id')::uuid, 'WA-' || (v_p0->>'pergunta_id'));
  update public.whatsapp_perguntas set aberta_em = now() - interval '1 day', expira_em = now() - interval '22 hours'
   where id = (v_p0->>'pergunta_id')::uuid;
  perform public._pergunta_limpar(pg_temp._phone());
  -- a do vigia (a tentativa conta na abertura) e o whatsapp-send que não confirmou
  v_ab := public._comprovante_abrir_pergunta(v, 'vigia', null);
  v_pid := (v_ab->'pergunta'->>'pergunta_id')::uuid;
  select situacao, perguntas_automaticas into v_meio from public.comprovantes where id = v;
  perform public.comprovante_pergunta_nao_enviada(v_pid);
  select x.status, x.motivo into w from public.whatsapp_perguntas x where x.id = v_pid;
  select situacao, perguntas_automaticas, adiado_ate, ultima_pergunta_em into v_depois from public.comprovantes where id = v;
  insert into _cmps values ('N', v, v_pid);
  insert into _resultado values ('N1 a do vigia que não saiu: fecha nao_enviada, o CMP volta à fila, a tentativa é devolvida, 4 h de espera, a última é a que saiu',
    v_meio.situacao = 'perguntando' and v_meio.perguntas_automaticas = 1
    and w.status = 'cancelada' and w.motivo = 'nao_enviada'
    and v_depois.situacao = 'aguardando_vez' and v_depois.perguntas_automaticas = 0
    and v_depois.adiado_ate = now() + interval '4 hours' and v_depois.ultima_pergunta_em = now() - interval '1 day'
    and pg_temp._abertas() = 0,
    'meio=' || coalesce(v_meio.situacao, '-') || '/' || coalesce(v_meio.perguntas_automaticas::text, '-')
    || ' pergunta=' || coalesce(w.status, '-') || '/' || coalesce(w.motivo, '-')
    || ' depois=' || coalesce(v_depois.situacao, '-') || '/' || coalesce(v_depois.perguntas_automaticas::text, '-')
    || ' adiado_4h=' || coalesce((v_depois.adiado_ate = now() + interval '4 hours')::text, 'null')
    || ' ultima_ontem=' || coalesce((v_depois.ultima_pergunta_em = now() - interval '1 day')::text, 'null')
    || ' abertas=' || pg_temp._abertas());
exception when others then
  insert into _resultado values ('N1 a do vigia que não saiu: fecha nao_enviada, o CMP volta à fila, a tentativa é devolvida, 4 h de espera, a última é a que saiu',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ N2 de novo: nada muda ═════════════════════════════════════════════════════════════════
do $$
declare
  v_antes record;
  v_depois record;
begin
  select situacao, perguntas_automaticas, adiado_ate, ultima_pergunta_em into v_antes from public.comprovantes where id = pg_temp._id('N');
  perform public.comprovante_pergunta_nao_enviada(pg_temp._extra('N'));
  select situacao, perguntas_automaticas, adiado_ate, ultima_pergunta_em into v_depois from public.comprovantes where id = pg_temp._id('N');
  insert into _resultado values ('N2 chamar de novo não muda nada (não vai a -1; o mesmo adiamento)',
    v_antes.situacao is not null and v_depois.situacao = v_antes.situacao
    and v_depois.perguntas_automaticas = v_antes.perguntas_automaticas and v_depois.perguntas_automaticas = 0
    and v_depois.adiado_ate = v_antes.adiado_ate and v_depois.ultima_pergunta_em = v_antes.ultima_pergunta_em
    and (select status from public.whatsapp_perguntas where id = pg_temp._extra('N')) = 'cancelada',
    'situacao=' || coalesce(v_depois.situacao, '-') || ' tentativas=' || coalesce(v_depois.perguntas_automaticas::text, '-')
    || ' adiado_igual=' || coalesce((v_depois.adiado_ate = v_antes.adiado_ate)::text, 'null'));
exception when others then
  insert into _resultado values ('N2 chamar de novo não muda nada (não vai a -1; o mesmo adiamento)', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ N3 o vigia respeita o adiamento ═══════════════════════════════════════════════════════
do $$
declare
  v_adiado uuid;
  v_depois uuid;
begin
  v_adiado := public._comprovante_cmp_da_vigia(pg_temp._phone());
  update public.comprovantes set adiado_ate = now() - interval '1 minute' where id = pg_temp._id('N');
  update public.comprovantes_fila_do_telefone set ultima_pergunta_fechada_em = now() - interval '5 hours'
   where phone_normalized = pg_temp._phone();
  v_depois := public._comprovante_cmp_da_vigia(pg_temp._phone());
  insert into _resultado values ('N3 o vigia não pega o CMP adiado; passado o adiamento, pega',
    v_adiado is null and v_depois = pg_temp._id('N'),
    'adiado=' || coalesce((v_adiado = pg_temp._id('N'))::text, 'null') || ' depois=' || coalesce((v_depois = pg_temp._id('N'))::text, 'null'));
exception when others then
  insert into _resultado values ('N3 o vigia não pega o CMP adiado; passado o adiamento, pega', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ N4 a pergunta do dono que não saiu ════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._id('N');
  v_p jsonb;
  v_antes record;
  v_depois record;
  w record;
begin
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v);
  select situacao, perguntas_automaticas, adiado_ate into v_antes from public.comprovantes where id = v;
  perform public.comprovante_pergunta_nao_enviada((v_p->>'pergunta_id')::uuid);
  select x.status, x.motivo into w from public.whatsapp_perguntas x where x.id = (v_p->>'pergunta_id')::uuid;
  select situacao, perguntas_automaticas, adiado_ate, ultima_pergunta_em into v_depois from public.comprovantes where id = v;
  insert into _resultado values ('N4 a pergunta do dono ("cmp N") que não saiu também devolve o CMP à fila; contagem e adiamento iguais',
    v_p->>'perguntou' = 'true' and v_antes.situacao = 'perguntando'
    and w.status = 'cancelada' and w.motivo = 'nao_enviada' and v_depois.situacao = 'aguardando_vez'
    and v_depois.perguntas_automaticas = v_antes.perguntas_automaticas
    and v_depois.adiado_ate is not distinct from v_antes.adiado_ate
    and v_depois.ultima_pergunta_em = now() - interval '1 day' and pg_temp._abertas() = 0,
    'antes=' || coalesce(v_antes.situacao, '-') || ' pergunta=' || coalesce(w.status, '-') || '/' || coalesce(w.motivo, '-')
    || ' depois=' || coalesce(v_depois.situacao, '-') || '/' || coalesce(v_depois.perguntas_automaticas::text, '-')
    || ' abertas=' || pg_temp._abertas());
exception when others then
  insert into _resultado values ('N4 a pergunta do dono ("cmp N") que não saiu também devolve o CMP à fila; contagem e adiamento iguais',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ N5 ninguém "perguntando" sem pergunta ═════════════════════════════════════════════════
do $$
declare
  v_presos integer;
begin
  select count(*) into v_presos from public.comprovantes x
   where x.phone_normalized = pg_temp._phone() and x.situacao in ('perguntando', 'aguardando_sim')
     and not exists (select 1 from public.whatsapp_perguntas w where w.referencia_id = x.id and w.status = 'aberta');
  insert into _resultado values ('N5 nenhum CMP do telefone "perguntando"/"aguardando o sim" sem pergunta aberta',
    v_presos = 0, 'presos=' || v_presos);
exception when others then
  insert into _resultado values ('N5 nenhum CMP do telefone "perguntando"/"aguardando o sim" sem pergunta aberta', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ N6 F3: a pergunta do extrato do vigia que não saiu ════════════════════════════════════
do $$
declare
  v_val numeric := pg_temp._val();
  v uuid;
  v_ab jsonb;
  v_antes record;
  v_depois record;
  w record;
begin
  perform pg_temp._livrar();
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized, tipo_whatsapp,
                                   recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca, data_compra, lido_em,
                                   destino, quem_pagou, valor_confirmado, data_confirmada, forma_confirmada, gravado_em, gravado_por,
                                   aguardando_banco_desde, banco_regra, banco_perguntas, banco_ultima_pergunta_em)
  values (public._comprovante_proximo_numero(), 'aguardando_banco', 'dono', 'comprovante', 'webhook', pg_temp._dono(),
          'TESTE-1310-' || gen_random_uuid(), pg_temp._phone(), 'image', now(),
          md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text),
          'nfce', 'alta', v_val, 'alta', pg_temp._hoje(), now(), 'insumo', 'empresa', v_val, pg_temp._hoje(), 'debito',
          now(), pg_temp._dono(), now(), 'debito', 1, now())
  returning id into v;
  v_ab := public._pergunta_abrir(jsonb_build_object(
    'phone', pg_temp._phone(), 'origem', 'comprovante', 'tipo', 'pergunta', 'referencia_id', v,
    'referencia_codigo', (select codigo from public.comprovantes where id = v), 'passo', 'banco', 'opcoes', '[]'::jsonb,
    'dados', jsonb_build_object('motivo', 'vigia'), 'expira_em', now() + interval '2 hours'));
  select situacao, banco_perguntas, banco_ultima_pergunta_em into v_antes from public.comprovantes where id = v;
  perform public.comprovante_pergunta_nao_enviada((v_ab->>'id')::uuid);
  select x.status, x.motivo into w from public.whatsapp_perguntas x where x.id = (v_ab->>'id')::uuid;
  select situacao, banco_perguntas, banco_ultima_pergunta_em into v_depois from public.comprovantes where id = v;
  insert into _resultado values ('N6 F3: a pergunta do extrato do vigia que não saiu devolve banco_perguntas; espaçamento e situação ficam',
    v_ab->>'ok' = 'true' and w.status = 'cancelada' and w.motivo = 'nao_enviada'
    and v_antes.banco_perguntas = 1 and v_depois.banco_perguntas = 0
    and v_depois.banco_ultima_pergunta_em = v_antes.banco_ultima_pergunta_em
    and v_depois.situacao = 'aguardando_banco' and pg_temp._abertas() = 0,
    'pergunta=' || coalesce(w.status, '-') || '/' || coalesce(w.motivo, '-')
    || ' banco_perguntas=' || coalesce(v_antes.banco_perguntas::text, '-') || '->' || coalesce(v_depois.banco_perguntas::text, '-')
    || ' situacao=' || coalesce(v_depois.situacao, '-'));
exception when others then
  insert into _resultado values ('N6 F3: a pergunta do extrato do vigia que não saiu devolve banco_perguntas; espaçamento e situação ficam',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ N7 a do vigia que JÁ saiu ═════════════════════════════════════════════════════════════
do $$
declare
  v uuid := pg_temp._cmp(jsonb_build_object('forma', 'pix'));
  v_ab jsonb;
  v_pid uuid;
  v_antes record;
  v_depois record;
  w record;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v]);
  update public.comprovantes set perguntas_automaticas = 1 where id = v;
  v_ab := public._comprovante_abrir_pergunta(v, 'vigia', null);
  v_pid := (v_ab->'pergunta'->>'pergunta_id')::uuid;
  perform public.pergunta_marcar_enviada(v_pid, 'WA-' || v_pid);
  select perguntas_automaticas, adiado_ate into v_antes from public.comprovantes where id = v;
  perform public.comprovante_pergunta_nao_enviada(v_pid);
  select x.status, x.motivo, x.aberta_em into w from public.whatsapp_perguntas x where x.id = v_pid;
  select situacao, perguntas_automaticas, adiado_ate, ultima_pergunta_em into v_depois from public.comprovantes where id = v;
  insert into _resultado values ('N7 a do vigia que já saiu (enviada_em) fecha e volta à fila sem descontar nem adiar',
    v_antes.perguntas_automaticas = 2 and w.status = 'cancelada' and w.motivo = 'nao_enviada'
    and v_depois.situacao = 'aguardando_vez' and v_depois.perguntas_automaticas = 2
    and v_depois.adiado_ate is not distinct from v_antes.adiado_ate and v_depois.ultima_pergunta_em = w.aberta_em
    and pg_temp._abertas() = 0,
    'tentativas=' || coalesce(v_antes.perguntas_automaticas::text, '-') || '->' || coalesce(v_depois.perguntas_automaticas::text, '-')
    || ' situacao=' || coalesce(v_depois.situacao, '-') || ' adiado=' || coalesce(v_depois.adiado_ate::text, 'null'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('N7 a do vigia que já saiu (enviada_em) fecha e volta à fila sem descontar nem adiar',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ P1 privilégios ═════════════════════════════════════════════════════════════════════════
do $$
declare
  v_helper text := 'public._comprovante_tipo_na_os(public.comprovantes)';
  v_rpc text := 'public.comprovante_pergunta_nao_enviada(uuid)';
begin
  insert into _resultado values ('P1 _comprovante_tipo_na_os sem grant para ninguém; comprovante_pergunta_nao_enviada só service_role',
    not has_function_privilege('anon', v_helper, 'execute') and not has_function_privilege('authenticated', v_helper, 'execute')
    and not has_function_privilege('service_role', v_helper, 'execute')
    and not has_function_privilege('anon', v_rpc, 'execute') and not has_function_privilege('authenticated', v_rpc, 'execute')
    and has_function_privilege('service_role', v_rpc, 'execute'), '');
exception when others then
  insert into _resultado values ('P1 _comprovante_tipo_na_os sem grant para ninguém; comprovante_pergunta_nao_enviada só service_role',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
