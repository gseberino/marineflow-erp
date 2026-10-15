-- Prova: agrupar e desagrupar orçamentos (migration 20261015180000_agrupar_orcamentos).
--
--   A1  caminho feliz: total = soma dos originais; linhas com desconto/source; peça do kit aponta para o serviço
--       DO NOVO; linhas na ordem dos originais; origens canceladas, sem link e apontando para o novo; novo com
--       link, sem validade fixa, autor, deslocamento do único que tinha, comissão/condição do PRINCIPAL
--       (comissão recalculada sobre o total novo); "antes" guardado; auditoria; envio agendado cancelado
--   B01–B18 bloqueios (a mensagem certa e NADA muda nas origens): embarcação, cliente, Desistência, assinado,
--       conta a receber, conta a pagar, nota fiscal, despesa, deslocamento em dois, repasse do cartão, origem já
--       agrupada, um só, repetido, principal fora, total esperado errado, total gravado desatualizado, técnico,
--       fora de rascunho
--   C1–C5 guardas do gatilho: origem agrupada não muda de situação/link nem é apagada; só as funções gravam
--       merged_into_id; quem nasce com merged_into_id nasce sem; campo livre da origem segue editável
--   D1–D3 portas: só admin/financeiro ativo; porta pública sem sessão pede login ANTES de gastar número;
--       privilégios (anon fora, _montar/_desfazer só service_role, tabelas só leitura)
--   E1–E7 desagrupar: originais voltam exatamente como estavam (e o envio agendado que o agrupar cancelou
--       volta para a fila); segunda vez recusa; reagrupar depois funciona; agrupado com dinheiro ligado /
--       virado OS / agrupado de novo recusa; técnico recusa
--   F1–F3 cancelar o agrupado pelo caminho normal (update ou cancel_service_order_cascade) é recusado;
--       orçamento comum segue cancelável; o desagrupar cancela o agrupado mesmo assim
--   F4–F6 agrupado que virou OS cancela pela cascata; agrupado assinado cancela; agrupado já desagrupado
--       não volta a valer (reabrir pelo status é recusado)
--   G1  sinal/recebível numa origem agrupada (insert direto e register_deposit_and_convert) é recusado e
--       nada fica gravado nela
--
-- ═══ COMO RODAR ═══ (só com OK nomeado; DEPOIS da migration aplicada — o arquivo usa a coluna e as funções dela)
--
--   npx supabase@2.111.0 db query --linked -f supabase/tests/agrupar_orcamentos.sql --output json
--   (a partir do repositório principal: o worktree não é linkado)
--
-- Seguro em produção: usuários (admin, financeiro, técnico, admin inativo), clientes, barcos, produto e
-- orçamentos de teste criados aqui (números ORÇ-9xxxxx livres); os agrupados recebem números fictícios
-- ORÇ-T… passados direto a _agrupar_orcamentos_montar, que assim NÃO gastam o document_number_seq; a porta
-- pública agrupar_orcamentos só roda no D2, onde falha antes de numerar (e o D2 confere isso). O envio de
-- WhatsApp agendado do A1 nasce e morre dentro da transação: nada sai. Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ids (nome text primary key, id uuid) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;

create function pg_temp._id(p_nome text) returns uuid language sql stable as $$
  select id from _ids where nome = p_nome
$$;

-- condição verdadeira -> null; falsa ou nula -> o nome (concat_ws dos nomes = detalhe; vazio = tudo certo)
create function pg_temp._se(p_ok boolean, p_nome text) returns text language sql immutable as $$
  select case when coalesce(p_ok, false) then null else p_nome end
$$;

create function pg_temp._usuario(p_role text, p_ativo boolean default true) returns uuid language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste agrupar (' || p_role || ')', 'teste-agrupar-' || v_id || '@teste.invalido', p_role, p_ativo);
  return v_id;
end $$;

create function pg_temp._cliente() returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Agrupar ' || pg_temp._letras(6))
  returning id into v_id;
  return v_id;
end $$;

create function pg_temp._barco(p_cli uuid) returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.vessels (client_id, name) values (p_cli, 'Barco' || pg_temp._letras(8)) returning id into v_id;
  return v_id;
end $$;

create function pg_temp._produto() returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.products (name, cost_price, sale_price)
  values ('Peça teste agrupar ' || pg_temp._letras(6), 40, 75) returning id into v_id;
  return v_id;
end $$;

-- número ORÇ-9xxxxx livre (origens de teste)
create function pg_temp._numero_livre() returns text language plpgsql as $$
declare
  v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number = 'ORÇ-' || v_num) loop
    v_num := v_num + 1;
  end loop;
  return 'ORÇ-' || v_num;
end $$;

-- número fictício do agrupado (passado a _montar: não gasta o document_number_seq)
create function pg_temp._numero_agrupado() returns text language sql volatile as $$
  select 'ORÇ-T' || upper(pg_temp._letras(6))
$$;

-- cabeçalho sem linhas; created_at = relógio, ou o dado (o A1 fixa: a ordem das origens é por created_at e
-- dois relógios seguidos podem empatar)
create function pg_temp._orc_vazio(p_cli uuid, p_ves uuid, p_status text default 'draft', p_quote_status text default 'draft',
                                   p_criado_em timestamptz default null)
returns uuid language plpgsql as $$
declare
  v_os uuid;
begin
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, created_at)
  values (pg_temp._numero_livre(), p_cli, p_ves, p_status, p_quote_status, coalesce(p_criado_em, clock_timestamp()))
  returning id into v_os;
  return v_os;
end $$;

-- linha de serviço no padrão da tela: line_total = qtd × preço − desconto (desconto = pct × bruto)
create function pg_temp._servico(p_os uuid, p_nome text, p_qtd numeric, p_preco numeric, p_desc_pct numeric default 0,
                                 p_criado_em timestamptz default null)
returns uuid language plpgsql as $$
declare
  v_id uuid;
  v_desc numeric := round(p_qtd * p_preco * p_desc_pct / 100, 2);
begin
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, discount_pct, discount_amount,
                                             created_at, updated_at)
  values (p_os, p_nome, 'hour', p_qtd, p_preco, round(p_qtd * p_preco, 2) - v_desc, p_desc_pct, v_desc,
          coalesce(p_criado_em, clock_timestamp()), coalesce(p_criado_em, clock_timestamp()))
  returning id into v_id;
  return v_id;
end $$;

-- orçamento comum de teste: 1 serviço (2 h × R$ 150), totais pelo banco
create function pg_temp._orc(p_cli uuid, p_ves uuid, p_status text default 'draft', p_quote_status text default 'draft')
returns uuid language plpgsql as $$
declare
  v_os uuid;
begin
  v_os := pg_temp._orc_vazio(p_cli, p_ves, p_status, p_quote_status);
  perform pg_temp._servico(v_os, 'Serviço de teste', 2, 150);
  perform public.recalc_so_totals(v_os);
  return v_os;
end $$;

-- dois orçamentos abertos do mesmo cliente e barco (o [1] criado antes do [2])
create function pg_temp._dupla() returns uuid[] language plpgsql as $$
declare
  v_cli uuid;
  v_ves uuid;
  v_a uuid;
  v_b uuid;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_a := pg_temp._orc(v_cli, v_ves);
  v_b := pg_temp._orc(v_cli, v_ves);
  return array[v_a, v_b];
end $$;

-- captura de erro: null = passou; senão "sqlstate mensagem"
create function pg_temp._erro_montar(p_ids uuid[], p_base uuid, p_numero text, p_autor uuid, p_total numeric)
returns text language plpgsql as $$
begin
  perform public._agrupar_orcamentos_montar(p_ids, p_base, p_numero, p_autor, p_total);
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

create function pg_temp._erro_desfazer(p_agrupado uuid, p_autor uuid) returns text language plpgsql as $$
begin
  perform public._desagrupar_orcamentos_desfazer(p_agrupado, p_autor);
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

create function pg_temp._erro_sql(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

-- retrato do que importa nas origens (para provar "nada mudou")
create function pg_temp._retrato(p_ids uuid[]) returns text language sql stable as $$
  select string_agg(concat_ws('/', so.id, so.status, coalesce(so.quote_status, '-'), coalesce(so.share_token::text, '-'),
                              coalesce(so.merged_into_id::text, '-'), coalesce(so.grand_total::text, '-'),
                              coalesce(so.cancelled_at::text, '-'), coalesce(so.cancellation_reason, '-')),
                    ' | ' order by so.id)
    from public.service_orders so where so.id = any(p_ids)
$$;

-- bloqueio: _montar recusa com o trecho esperado, as origens ficam iguais e o agrupado não nasce
create function pg_temp._bloqueio(p_teste text, p_ids uuid[], p_base uuid, p_autor uuid, p_total numeric, p_trecho text)
returns void language plpgsql as $$
declare
  v_numero text := pg_temp._numero_agrupado();
  v_antes text;
  v_depois text;
  v_erro text;
  v_criou boolean;
begin
  v_antes := pg_temp._retrato(p_ids);
  v_erro := pg_temp._erro_montar(p_ids, p_base, v_numero, p_autor, p_total);
  v_depois := pg_temp._retrato(p_ids);
  v_criou := exists (select 1 from public.service_orders where service_order_number = v_numero);
  insert into _resultado values (p_teste,
    v_erro is not null and strpos(v_erro, p_trecho) > 0 and v_antes is not distinct from v_depois and not v_criou,
    coalesce(v_erro, 'sem erro: agrupou')
      || case when v_antes is distinct from v_depois then ' | AS ORIGENS MUDARAM' else '' end
      || case when v_criou then ' | O AGRUPADO NASCEU' else '' end);
end $$;

-- usuários de teste
insert into _ids values
  ('admin', pg_temp._usuario('admin')),
  ('financeiro', pg_temp._usuario('financial')),
  ('tecnico', pg_temp._usuario('technician')),
  ('admin_inativo', pg_temp._usuario('admin', false));

-- ═══ A1 caminho feliz ═══════════════════════════════════════════════════════════════════════
do $$
declare
  v_admin uuid;
  v_cli uuid;
  v_ves uuid;
  v_prod uuid;
  v_a uuid;
  v_b uuid;
  v_s uuid;
  v_token_a uuid := gen_random_uuid();
  v_token_b uuid;
  v_total_a numeric;
  v_total_b numeric;
  v_envio uuid;
  v_grupo uuid;
  r jsonb;
  v_novo uuid;
  n public.service_orders;
  v_falhas text;
begin
  v_admin := pg_temp._id('admin');
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_prod := pg_temp._produto();

  -- A: já enviado ao cliente (link conhecido), imposto R$ 64 no cabeçalho, comissão 3%;
  --    2 serviços: 2 h × 150 e 1 × 200 com 5% (R$ 10) de desconto na linha
  --    (datas fixas: A 2 h atrás, B 1 h atrás; linhas 1 s uma da outra — nada de empate no relógio)
  v_a := pg_temp._orc_vazio(v_cli, v_ves, 'draft', 'draft', now() - interval '2 hours');
  update public.service_orders
     set quote_status = 'sent', share_token = v_token_a, tax_amount = 64, commission_rate = 3,
         problem_description = 'Revisar o quadro elétrico'
   where id = v_a;
  perform pg_temp._servico(v_a, 'A1 Revisão do quadro', 2, 150, 0, now() - interval '2 hours');
  perform pg_temp._servico(v_a, 'A2 Troca de disjuntor', 1, 200, 5, now() - interval '2 hours' + interval '1 second');
  perform public.recalc_so_totals(v_a);

  -- B (principal, criado depois de A): comissão 5%, sem preset de condição, condição em texto, terceiros R$ 100,
  --    deslocamento R$ 150 / 30 km; 1 serviço S (3 × 180) + 2 peças: manual (2 × 75) e do kit de S (200 − 5%)
  v_b := pg_temp._orc_vazio(v_cli, v_ves, 'draft', 'draft', now() - interval '1 hour');
  update public.service_orders
     set subcontract_cost_total = 100, travel_cost_total = 150, travel_distance_km = 30, commission_rate = 5,
         payment_condition_preset_id = null, payment_conditions = '50% na aprovação, 50% na entrega',
         problem_description = 'Instalar o inversor'
   where id = v_b;
  v_s := pg_temp._servico(v_b, 'B1 Instalação do inversor', 3, 180, 0, now() - interval '1 hour');
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, discount_pct, discount_amount, source,
                                          service_order_service_id, created_at, updated_at)
  values (v_b, v_prod, 2, 40, 75, 80, 150, 0, 0, 'manual', null,
          now() - interval '1 hour' + interval '1 second', now() - interval '1 hour' + interval '1 second');
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, discount_pct, discount_amount, source,
                                          service_order_service_id, created_at, updated_at)
  values (v_b, v_prod, 1, 100, 200, 100, 190, 5, 10, 'kit', v_s,
          now() - interval '1 hour' + interval '2 seconds', now() - interval '1 hour' + interval '2 seconds');
  perform public.recalc_so_totals(v_b);

  -- envio de WhatsApp pendente com o link antigo de A (nunca sai: rollback)
  insert into public.whatsapp_scheduled_sends (target_kind, service_order_id, client_id, phone, message,
                                               scheduled_at, next_run_at, status)
  values ('service_order', v_a, v_cli, '550000000000', 'Teste agrupar: link do orçamento',
          now() + interval '1 day', now() + interval '1 day', 'pending')
  returning id into v_envio;

  select share_token into v_token_b from public.service_orders where id = v_b;
  select grand_total into v_total_a from public.service_orders where id = v_a;
  select grand_total into v_total_b from public.service_orders where id = v_b;

  r := public._agrupar_orcamentos_montar(array[v_a, v_b], v_b, pg_temp._numero_agrupado(), v_admin, v_total_a + v_total_b);
  v_novo := (r ->> 'service_order_id')::uuid;
  v_grupo := (r ->> 'agrupamento_id')::uuid;
  select * into n from public.service_orders where id = v_novo;

  v_falhas := concat_ws(', ',
    pg_temp._se(n.grand_total = v_total_a + v_total_b and (r ->> 'total_geral')::numeric = n.grand_total, 'total'),
    pg_temp._se(n.status = 'draft' and n.quote_status = 'draft' and n.merged_into_id is null
                and n.client_id = v_cli and n.vessel_id = v_ves, 'situação do novo'),
    pg_temp._se((select count(*) from public.service_order_services x where x.service_order_id = v_novo) = 3
                and (r ->> 'servicos')::int = 3, 'serviços'),
    pg_temp._se((select count(*) from public.service_order_parts p where p.service_order_id = v_novo) = 2
                and (r ->> 'pecas')::int = 2, 'peças'),
    pg_temp._se(exists (select 1 from public.service_order_services x
                         where x.service_order_id = v_novo and x.name_snapshot = 'A2 Troca de disjuntor'
                           and x.unit_price_snapshot = 200 and x.discount_pct = 5 and x.discount_amount = 10
                           and x.line_total = 190), 'desconto da linha'),
    pg_temp._se(exists (select 1 from public.service_order_parts p
                          join public.service_order_services x on x.id = p.service_order_service_id
                         where p.service_order_id = v_novo and p.source = 'kit' and p.discount_pct = 5
                           and p.discount_amount = 10 and p.line_total_sale = 190
                           and x.service_order_id = v_novo and x.name_snapshot = 'B1 Instalação do inversor')
                and exists (select 1 from public.service_order_parts p
                             where p.service_order_id = v_novo and p.source = 'manual'
                               and p.service_order_service_id is null and p.line_total_sale = 150),
                'peça do kit/source'),
    pg_temp._se((select string_agg(x.name_snapshot, ' > ' order by x.created_at)
                   from public.service_order_services x where x.service_order_id = v_novo)
                = 'A1 Revisão do quadro > A2 Troca de disjuntor > B1 Instalação do inversor', 'ordem das linhas'),
    pg_temp._se(n.problem_description like '%Revisar o quadro elétrico%Instalar o inversor%'
                and n.internal_notes like 'Reúne %', 'textos juntados'),
    pg_temp._se((select count(*) from public.service_orders so
                  where so.id in (v_a, v_b) and so.status = 'cancelled' and so.quote_status = 'draft'
                    and so.share_token is null and so.merged_into_id = v_novo
                    and so.cancellation_reason like 'Agrupado em ORÇ-T%') = 2, 'origens'),
    pg_temp._se(n.share_token is not null and n.quote_validity_date is null and n.created_by = v_admin,
                'link/validade/autor do novo'),
    pg_temp._se(n.travel_cost_total = 150 and n.travel_distance_km = 30 and n.subcontract_cost_total = 100
                and n.tax_amount = 64, 'deslocamento/terceiros/imposto'),
    pg_temp._se(n.commission_rate = 5 and n.commission_amount = round(n.grand_total * 5 / 100, 2)
                and (r ->> 'comissao')::numeric = n.commission_amount, 'comissão do principal'),
    pg_temp._se(n.payment_conditions = '50% na aprovação, 50% na entrega' and n.payment_condition_preset_id is null,
                'condição do principal'),
    pg_temp._se(exists (select 1 from public.orcamento_agrupamentos g
                         where g.id = v_grupo and g.agrupado_id = v_novo and g.desfeito_em is null
                           and g.criado_por = v_admin), 'agrupamento ativo'),
    pg_temp._se((select count(*) from public.orcamento_agrupamento_origens o where o.agrupamento_id = v_grupo) = 2
                and exists (select 1 from public.orcamento_agrupamento_origens o
                             where o.agrupamento_id = v_grupo and o.origem_id = v_a and o.ordem = 1
                               and o.quote_status_antes = 'sent' and o.share_token_antes = v_token_a
                               and o.grand_total_antes = v_total_a and o.cancelled_at_antes is null)
                and exists (select 1 from public.orcamento_agrupamento_origens o
                             where o.agrupamento_id = v_grupo and o.origem_id = v_b and o.ordem = 2
                               and o.quote_status_antes = 'draft' and o.share_token_antes = v_token_b
                               and o.grand_total_antes = v_total_b), '"antes" guardado'),
    pg_temp._se((select count(*) from public.audit_log l
                  where l.table_name = 'service_orders' and l.action = 'cancel'
                    and l.triggered_by_id = v_novo and l.record_id in (v_a, v_b)) = 2
                and (select count(*) from public.audit_log l
                      where l.table_name = 'service_orders' and l.action = 'update' and l.record_id = v_novo) = 1,
                'auditoria'),
    pg_temp._se((select w.status from public.whatsapp_scheduled_sends w where w.id = v_envio) = 'cancelled'
                and (r ->> 'envios_cancelados')::int = 1, 'envio agendado'));

  insert into _ids values ('a1_a', v_a), ('a1_b', v_b), ('a1_novo', v_novo);
  insert into _resultado values ('A1 caminho feliz: total = soma, linhas/kit/ordem, origens históricas, principal manda, "antes", auditoria, envio',
    v_falhas = '',
    case when v_falhas = '' then '' else 'falhou: ' || v_falhas || ' | ' end
    || 'novo=' || coalesce(n.service_order_number, 'null') || ' total=' || coalesce(n.grand_total::text, 'null')
    || ' (A ' || coalesce(v_total_a::text, 'null') || ' + B ' || coalesce(v_total_b::text, 'null') || ')'
    || ' comissão=' || coalesce(n.commission_amount::text, 'null'));
exception when others then
  insert into _resultado values ('A1 caminho feliz: total = soma, linhas/kit/ordem, origens históricas, principal manda, "antes", auditoria, envio',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ B bloqueios ════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_cli uuid;
  v_ves uuid;
  v_a uuid;
  v_b uuid;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_a := pg_temp._orc(v_cli, v_ves);
  v_b := pg_temp._orc(v_cli, pg_temp._barco(v_cli));
  perform pg_temp._bloqueio('B01 embarcação diferente: recusa ("mesma embarcação") e nada muda',
    array[v_a, v_b], null, pg_temp._id('admin'), null, 'mesma embarcação');
exception when others then
  insert into _resultado values ('B01 embarcação diferente: recusa ("mesma embarcação") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_cli uuid;
  v_cli2 uuid;
  v_a uuid;
  v_b uuid;
begin
  v_cli := pg_temp._cliente();
  v_cli2 := pg_temp._cliente();
  v_a := pg_temp._orc(v_cli, pg_temp._barco(v_cli));
  v_b := pg_temp._orc(v_cli2, pg_temp._barco(v_cli2));
  perform pg_temp._bloqueio('B02 cliente diferente: recusa ("mesmo cliente") e nada muda',
    array[v_a, v_b], null, pg_temp._id('admin'), null, 'mesmo cliente');
exception when others then
  insert into _resultado values ('B02 cliente diferente: recusa ("mesmo cliente") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
begin
  v := pg_temp._dupla();
  update public.service_orders set quote_status = 'rejected' where id = v[2];
  perform pg_temp._bloqueio('B03 Desistência (quote_status rejected): recusa e nada muda',
    v, null, pg_temp._id('admin'), null, 'está como Reprovado');
exception when others then
  insert into _resultado values ('B03 Desistência (quote_status rejected): recusa e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
begin
  v := pg_temp._dupla();
  update public.service_orders set signed_at = now() where id = v[2];
  perform pg_temp._bloqueio('B04 assinado pelo cliente: recusa ("assinado") e nada muda',
    v, null, pg_temp._id('admin'), null, 'assinado');
exception when others then
  insert into _resultado values ('B04 assinado pelo cliente: recusa ("assinado") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_cli uuid;
begin
  v := pg_temp._dupla();
  select client_id into v_cli from public.service_orders where id = v[2];
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status)
  values (v_cli, v[2], 'Teste agrupar: sinal pendente', current_date, current_date + 7, 100, 'pending');
  perform pg_temp._bloqueio('B05 conta a receber pendente: recusa ("conta a receber") e nada muda',
    v, null, pg_temp._id('admin'), null, 'conta a receber');
exception when others then
  insert into _resultado values ('B05 conta a receber pendente: recusa ("conta a receber") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
begin
  v := pg_temp._dupla();
  insert into public.payables (description, issue_date, due_date, amount, linked_service_order_id, status)
  values ('Teste agrupar: conta a pagar ligada', current_date, current_date + 7, 50, v[2], 'pending');
  perform pg_temp._bloqueio('B06 conta a pagar pendente: recusa ("conta a pagar") e nada muda',
    v, null, pg_temp._id('admin'), null, 'conta a pagar');
exception when others then
  insert into _resultado values ('B06 conta a pagar pendente: recusa ("conta a pagar") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_cli uuid;
begin
  v := pg_temp._dupla();
  select client_id into v_cli from public.service_orders where id = v[2];
  -- NFS-e autorizada de homologação, sem payload: o gatilho de devolução não age (purpose <> '4')
  insert into public.issued_fiscal_documents (document_type, origin_type, origin_id, client_id, status)
  values ('nfse', 'service_order', v[2], v_cli, 'authorized');
  perform pg_temp._bloqueio('B07 nota fiscal autorizada: recusa ("nota fiscal") e nada muda',
    v, null, pg_temp._id('admin'), null, 'nota fiscal');
exception when others then
  insert into _resultado values ('B07 nota fiscal autorizada: recusa ("nota fiscal") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
begin
  v := pg_temp._dupla();
  insert into public.service_order_expenses (service_order_id, category, description, amount)
  values (v[2], 'material', 'Teste agrupar: despesa', 30);
  perform pg_temp._bloqueio('B08 despesa lançada: recusa ("despesas") e nada muda',
    v, null, pg_temp._id('admin'), null, 'despesas');
exception when others then
  insert into _resultado values ('B08 despesa lançada: recusa ("despesas") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
begin
  v := pg_temp._dupla();
  update public.service_orders set travel_cost_total = 80, travel_distance_km = 15 where id = any(v);
  perform public.recalc_so_totals(v[1]);
  perform public.recalc_so_totals(v[2]);
  perform pg_temp._bloqueio('B09 deslocamento em dois: recusa ("deslocamento") e nada muda',
    v, null, pg_temp._id('admin'), null, 'deslocamento');
exception when others then
  insert into _resultado values ('B09 deslocamento em dois: recusa ("deslocamento") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
begin
  v := pg_temp._dupla();
  update public.service_orders set card_fee_passthrough_enabled = true where id = v[2];
  perform public.recalc_so_totals(v[2]);
  perform pg_temp._bloqueio('B10 repasse da taxa do cartão: recusa ("taxa do cartão") e nada muda',
    v, null, pg_temp._id('admin'), null, 'taxa do cartão');
exception when others then
  insert into _resultado values ('B10 repasse da taxa do cartão: recusa ("taxa do cartão") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_cli uuid;
  v_ves uuid;
  v_c uuid;
begin
  v := pg_temp._dupla();
  select client_id, vessel_id into v_cli, v_ves from public.service_orders where id = v[1];
  v_c := pg_temp._orc(v_cli, v_ves);
  perform public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  perform pg_temp._bloqueio('B11 origem já agrupada: recusa ("já foi agrupado em") e nada muda',
    array[v[1], v_c], null, pg_temp._id('admin'), null, 'já foi agrupado em');
exception when others then
  insert into _resultado values ('B11 origem já agrupada: recusa ("já foi agrupado em") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
begin
  v := pg_temp._dupla();
  perform pg_temp._bloqueio('B12 um orçamento só: recusa ("pelo menos 2")',
    array[v[1]], null, pg_temp._id('admin'), null, 'pelo menos 2');
exception when others then
  insert into _resultado values ('B12 um orçamento só: recusa ("pelo menos 2")', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
begin
  v := pg_temp._dupla();
  perform pg_temp._bloqueio('B13 id repetido: recusa ("duas vezes")',
    array[v[1], v[1], v[2]], null, pg_temp._id('admin'), null, 'duas vezes');
exception when others then
  insert into _resultado values ('B13 id repetido: recusa ("duas vezes")', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_cli uuid;
  v_ves uuid;
  v_c uuid;
begin
  v := pg_temp._dupla();
  select client_id, vessel_id into v_cli, v_ves from public.service_orders where id = v[1];
  v_c := pg_temp._orc(v_cli, v_ves);
  perform pg_temp._bloqueio('B14 principal fora da lista: recusa ("principal") e nada muda',
    v, v_c, pg_temp._id('admin'), null, 'principal');
exception when others then
  insert into _resultado values ('B14 principal fora da lista: recusa ("principal") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_soma numeric;
begin
  v := pg_temp._dupla();
  select sum(grand_total) into v_soma from public.service_orders where id = any(v);
  perform pg_temp._bloqueio('B15 total esperado diferente do gravado: recusa ("mudaram") e nada muda',
    v, null, pg_temp._id('admin'), v_soma + 1, 'mudaram');
exception when others then
  insert into _resultado values ('B15 total esperado diferente do gravado: recusa ("mudaram") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
begin
  v := pg_temp._dupla();
  update public.service_orders set grand_total = grand_total + 7 where id = v[2];
  perform pg_temp._bloqueio('B16 total gravado desatualizado: recusa ("desatualizado") e nada muda',
    v, null, pg_temp._id('admin'), null, 'desatualizado');
exception when others then
  insert into _resultado values ('B16 total gravado desatualizado: recusa ("desatualizado") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
begin
  v := pg_temp._dupla();
  perform pg_temp._bloqueio('B17 técnico não agrupa: 42501 e nada muda',
    v, null, pg_temp._id('tecnico'), null, '42501');
exception when others then
  insert into _resultado values ('B17 técnico não agrupa: 42501 e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_cli uuid;
  v_ves uuid;
  v_a uuid;
  v_b uuid;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_a := pg_temp._orc(v_cli, v_ves);
  v_b := pg_temp._orc(v_cli, v_ves, 'open');
  perform pg_temp._bloqueio('B18 fora de rascunho (status open): recusa ("não é mais um orçamento em aberto") e nada muda',
    array[v_a, v_b], null, pg_temp._id('admin'), null, 'não é mais um orçamento em aberto');
exception when others then
  insert into _resultado values ('B18 fora de rascunho (status open): recusa ("não é mais um orçamento em aberto") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C guardas do gatilho ═══════════════════════════════════════════════════════════════════
do $$
declare
  v uuid[];
  v_erro text;
  v_erro2 text;
begin
  v := pg_temp._dupla();
  perform public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  -- o autosave do formulário velho manda status = 'draft'; um link novo também não pode nascer
  v_erro := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'draft', v[1]));
  v_erro2 := pg_temp._erro_sql(format('update public.service_orders set share_token = gen_random_uuid() where id = %L', v[1]));
  insert into _resultado values ('C1 origem agrupada não volta a rascunho nem ganha link ("não pode mais mudar")',
    strpos(coalesce(v_erro, ''), 'não pode mais mudar') > 0 and strpos(coalesce(v_erro2, ''), 'não pode mais mudar') > 0
    and exists (select 1 from public.service_orders where id = v[1] and status = 'cancelled' and share_token is null),
    'status: ' || coalesce(v_erro, 'PASSOU') || ' | link: ' || coalesce(v_erro2, 'PASSOU'));
exception when others then
  insert into _resultado values ('C1 origem agrupada não volta a rascunho nem ganha link ("não pode mais mudar")', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_erro text;
begin
  v := pg_temp._dupla();
  perform public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  v_erro := pg_temp._erro_sql(format('delete from public.service_orders where id = %L', v[1]));
  insert into _resultado values ('C2 origem agrupada não é apagada ("histórico")',
    strpos(coalesce(v_erro, ''), 'histórico') > 0 and exists (select 1 from public.service_orders where id = v[1]),
    coalesce(v_erro, 'APAGOU'));
exception when others then
  insert into _resultado values ('C2 origem agrupada não é apagada ("histórico")', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  r jsonb;
  v_novo uuid;
  v_cli uuid;
  v_ves uuid;
  v_c uuid;
  v_erro text;
  v_erro2 text;
begin
  v := pg_temp._dupla();
  select client_id, vessel_id into v_cli, v_ves from public.service_orders where id = v[1];
  v_c := pg_temp._orc(v_cli, v_ves);
  r := public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  v_novo := (r ->> 'service_order_id')::uuid;
  -- ligar uma OS comum a um agrupado, e soltar uma origem, só pelas funções
  v_erro := pg_temp._erro_sql(format('update public.service_orders set merged_into_id = %L where id = %L', v_novo, v_c));
  v_erro2 := pg_temp._erro_sql(format('update public.service_orders set merged_into_id = null where id = %L', v[1]));
  insert into _resultado values ('C3 merged_into_id só pelas funções ("Só as funções"): ligar OS comum e soltar origem',
    strpos(coalesce(v_erro, ''), 'Só as funções') > 0 and strpos(coalesce(v_erro2, ''), 'Só as funções') > 0
    and exists (select 1 from public.service_orders where id = v_c and merged_into_id is null)
    and exists (select 1 from public.service_orders where id = v[1] and merged_into_id = v_novo),
    'ligar: ' || coalesce(v_erro, 'PASSOU') || ' | soltar: ' || coalesce(v_erro2, 'PASSOU'));
exception when others then
  insert into _resultado values ('C3 merged_into_id só pelas funções ("Só as funções"): ligar OS comum e soltar origem', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  r jsonb;
  v_novo uuid;
  v_cli uuid;
  v_ves uuid;
  v_copia uuid;
  v_marca uuid;
begin
  v := pg_temp._dupla();
  select client_id, vessel_id into v_cli, v_ves from public.service_orders where id = v[1];
  r := public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  v_novo := (r ->> 'service_order_id')::uuid;
  -- o "Duplicar" copia o cabeçalho com spread: a cópia não pode nascer travada
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, merged_into_id)
  values (pg_temp._numero_livre(), v_cli, v_ves, 'draft', 'draft', v_novo)
  returning id, merged_into_id into v_copia, v_marca;
  insert into _resultado values ('C4 insert com merged_into_id preenchido grava NULL',
    v_copia is not null and v_marca is null
    and exists (select 1 from public.service_orders where id = v_copia and merged_into_id is null),
    'merged_into_id gravado=' || coalesce(v_marca::text, 'null'));
exception when others then
  insert into _resultado values ('C4 insert com merged_into_id preenchido grava NULL', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_erro text;
begin
  v := pg_temp._dupla();
  perform public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  v_erro := pg_temp._erro_sql(format('update public.service_orders set internal_notes = %L where id = %L',
                                     'Anotação depois de agrupado', v[1]));
  insert into _resultado values ('C5 campo livre (internal_notes) da origem agrupada segue editável',
    v_erro is null
    and exists (select 1 from public.service_orders where id = v[1] and internal_notes = 'Anotação depois de agrupado'
                  and status = 'cancelled' and merged_into_id is not null),
    coalesce(v_erro, 'editou'));
exception when others then
  insert into _resultado values ('C5 campo livre (internal_notes) da origem agrupada segue editável', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ D portas ═══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v uuid[];
  v_antes text;
  e_tec text;
  e_inativo text;
  e_desconhecido text;
  e_nulo text;
  v_intactas boolean;
  v_fin uuid;
begin
  v := pg_temp._dupla();
  v_antes := pg_temp._retrato(v);
  e_tec := pg_temp._erro_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('tecnico'), null);
  e_inativo := pg_temp._erro_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin_inativo'), null);
  e_desconhecido := pg_temp._erro_montar(v, null, pg_temp._numero_agrupado(), gen_random_uuid(), null);
  e_nulo := pg_temp._erro_montar(v, null, pg_temp._numero_agrupado(), null, null);
  v_intactas := pg_temp._retrato(v) = v_antes;
  -- depois das recusas, o financeiro agrupa os mesmos
  v_fin := (public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('financeiro'), null)
            ->> 'service_order_id')::uuid;
  insert into _resultado values ('D1 _montar: técnico, admin inativo, usuário desconhecido e sem autor dão 42501; financeiro agrupa',
    e_tec like '42501 %' and e_inativo like '42501 %' and e_desconhecido like '42501 %'
    and e_nulo like '42501 %Faça login%' and v_intactas and v_fin is not null,
    'técnico: ' || coalesce(e_tec, 'PASSOU') || ' | inativo: ' || coalesce(e_inativo, 'PASSOU')
    || ' | desconhecido: ' || coalesce(e_desconhecido, 'PASSOU') || ' | sem autor: ' || coalesce(e_nulo, 'PASSOU')
    || ' | financeiro: ' || coalesce(v_fin::text, 'não agrupou'));
exception when others then
  insert into _resultado values ('D1 _montar: técnico, admin inativo, usuário desconhecido e sem autor dão 42501; financeiro agrupa', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_antes text;
  v_lv1 bigint;
  v_lv2 bigint;
  v_ic1 boolean;
  v_ic2 boolean;
  v_erro text;
  v_erro2 text;
begin
  v := pg_temp._dupla();
  v_antes := pg_temp._retrato(v);
  -- sem sessão: auth.uid() nulo
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  select last_value, is_called into v_lv1, v_ic1 from public.document_number_seq;
  v_erro := pg_temp._erro_sql(format('select public.agrupar_orcamentos(%L::uuid[])', v));
  select last_value, is_called into v_lv2, v_ic2 from public.document_number_seq;
  v_erro2 := pg_temp._erro_sql(format('select public.desagrupar_orcamentos(%L::uuid)', v[1]));
  insert into _resultado values ('D2 porta pública sem sessão e sem p_autor: "Faça login" e o document_number_seq não anda',
    auth.uid() is null
    and strpos(coalesce(v_erro, ''), 'Faça login') > 0 and strpos(coalesce(v_erro2, ''), 'Faça login') > 0
    and v_lv1 = v_lv2 and v_ic1 = v_ic2 and pg_temp._retrato(v) = v_antes,
    'agrupar: ' || coalesce(v_erro, 'PASSOU') || ' | desagrupar: ' || coalesce(v_erro2, 'PASSOU')
    || ' | seq ' || v_lv1 || '/' || v_ic1 || ' -> ' || v_lv2 || '/' || v_ic2);
exception when others then
  insert into _resultado values ('D2 porta pública sem sessão e sem p_autor: "Faça login" e o document_number_seq não anda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_ag text := 'public.agrupar_orcamentos(uuid[], uuid, numeric, uuid)';
  v_des text := 'public.desagrupar_orcamentos(uuid, uuid)';
  v_mon text := 'public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric)';
  v_dfz text := 'public._desagrupar_orcamentos_desfazer(uuid, uuid)';
  v_vin text := 'public._orcamento_vinculos_que_prendem(uuid)';
  v_jun text := 'public._agrupar_orcamentos_juntar(text[], text[])';
  v_falhas text;
begin
  v_falhas := concat_ws(', ',
    pg_temp._se(not has_function_privilege('anon', v_ag, 'execute'), 'anon executa agrupar'),
    pg_temp._se(not has_function_privilege('anon', v_des, 'execute'), 'anon executa desagrupar'),
    pg_temp._se(not has_function_privilege('anon', v_mon, 'execute'), 'anon executa _montar'),
    pg_temp._se(not has_function_privilege('authenticated', v_mon, 'execute'), 'logado executa _montar'),
    pg_temp._se(not has_function_privilege('anon', v_dfz, 'execute'), 'anon executa _desfazer'),
    pg_temp._se(not has_function_privilege('authenticated', v_dfz, 'execute'), 'logado executa _desfazer'),
    pg_temp._se(not has_function_privilege('anon', v_vin, 'execute'), 'anon executa _vinculos'),
    pg_temp._se(not has_function_privilege('authenticated', v_vin, 'execute'), 'logado executa _vinculos'),
    pg_temp._se(not has_function_privilege('anon', v_jun, 'execute'), 'anon executa _juntar'),
    pg_temp._se(has_function_privilege('authenticated', v_ag, 'execute'), 'logado sem agrupar'),
    pg_temp._se(has_function_privilege('authenticated', v_des, 'execute'), 'logado sem desagrupar'),
    pg_temp._se(has_function_privilege('service_role', v_mon, 'execute'), 'service_role sem _montar'),
    pg_temp._se(has_function_privilege('service_role', v_dfz, 'execute'), 'service_role sem _desfazer'),
    pg_temp._se(not has_column_privilege('anon', 'public.service_orders', 'merged_into_id', 'select'), 'anon lê merged_into_id'),
    pg_temp._se(not has_table_privilege('anon', 'public.orcamento_agrupamentos', 'select'), 'anon lê agrupamentos'),
    pg_temp._se(not has_table_privilege('anon', 'public.orcamento_agrupamento_origens', 'select'), 'anon lê origens'),
    pg_temp._se(has_table_privilege('authenticated', 'public.orcamento_agrupamentos', 'select')
                and has_table_privilege('authenticated', 'public.orcamento_agrupamento_origens', 'select'), 'logado não lê o histórico'),
    pg_temp._se(not has_table_privilege('authenticated', 'public.orcamento_agrupamentos', 'insert, update, delete'),
                'logado escreve em agrupamentos'),
    pg_temp._se(not has_table_privilege('authenticated', 'public.orcamento_agrupamento_origens', 'insert, update, delete'),
                'logado escreve em origens'),
    pg_temp._se((select bool_and(c.relrowsecurity) from pg_class c
                  where c.oid in ('public.orcamento_agrupamentos'::regclass, 'public.orcamento_agrupamento_origens'::regclass)),
                'RLS desligada'),
    pg_temp._se((select count(*) from pg_trigger t
                  where t.tgrelid = 'public.service_orders'::regclass and not t.tgisinternal
                    and t.tgname in ('trg_orcamento_agrupado_guarda_ins', 'trg_orcamento_agrupado_guarda_upd',
                                     'trg_orcamento_agrupado_guarda_del', 'trg_orcamento_agrupado_guarda_destino')) = 4,
                'gatilhos da guarda'),
    pg_temp._se(exists (select 1 from pg_trigger t
                         where t.tgrelid = 'public.receivables'::regclass and not t.tgisinternal
                           and t.tgname = 'trg_receivables_origem_agrupada'), 'gatilho do recebível'),
    pg_temp._se(not has_function_privilege('anon', 'public._agrupar_orcamentos_reais(numeric)', 'execute'),
                'anon executa _reais'));
  insert into _resultado values ('D3 privilégios: anon fora, _montar/_desfazer só service_role, histórico só leitura, RLS e guarda ligadas',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas end);
exception when others then
  insert into _resultado values ('D3 privilégios: anon fora, _montar/_desfazer só service_role, histórico só leitura, RLS e guarda ligadas', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ E desagrupar ═══════════════════════════════════════════════════════════════════════════
do $$
declare
  v_admin uuid;
  v_a uuid;
  v_b uuid;
  v_novo uuid;
  v_grupo uuid;
  r jsonb;
  v_falhas text;
begin
  v_admin := pg_temp._id('admin');
  v_a := pg_temp._id('a1_a');
  v_b := pg_temp._id('a1_b');
  v_novo := pg_temp._id('a1_novo');
  if v_novo is null then
    raise exception 'o A1 não deixou o agrupado (veja a linha A1)';
  end if;
  select g.id into v_grupo from public.orcamento_agrupamentos g where g.agrupado_id = v_novo and g.desfeito_em is null;

  r := public._desagrupar_orcamentos_desfazer(v_novo, v_admin);

  v_falhas := concat_ws(', ',
    pg_temp._se((select count(*) from public.service_orders so
                   join public.orcamento_agrupamento_origens o on o.origem_id = so.id and o.agrupamento_id = v_grupo
                  where so.status = 'draft' and so.merged_into_id is null
                    and so.quote_status is not distinct from o.quote_status_antes
                    and so.share_token is not distinct from o.share_token_antes
                    and so.cancelled_at is not distinct from o.cancelled_at_antes
                    and so.cancellation_reason is not distinct from o.cancellation_reason_antes
                    and so.grand_total = o.grand_total_antes) = 2, 'origens como antes'),
    pg_temp._se(exists (select 1 from public.service_orders so where so.id = v_a and so.quote_status = 'sent'
                         and so.share_token is not null), 'A voltou como enviado e com o link'),
    pg_temp._se(exists (select 1 from public.service_orders so where so.id = v_novo and so.status = 'cancelled'
                         and so.share_token is null and so.merged_into_id is null
                         and so.cancellation_reason like 'Desagrupado%'), 'agrupado cancelado sem link'),
    pg_temp._se(exists (select 1 from public.orcamento_agrupamentos g where g.id = v_grupo
                         and g.desfeito_em is not null and g.desfeito_por = v_admin), 'agrupamento desfeito'),
    pg_temp._se((select count(*) from public.audit_log l
                  where l.table_name = 'service_orders' and l.action = 'reopen'
                    and l.triggered_by_id = v_novo and l.record_id in (v_a, v_b)) = 2
                and exists (select 1 from public.audit_log l
                             where l.table_name = 'service_orders' and l.action = 'cancel' and l.record_id = v_novo),
                'auditoria'),
    pg_temp._se(r -> 'origens_ids' = jsonb_build_array(v_a, v_b) and (r ->> 'agrupado_id')::uuid = v_novo, 'retorno'),
    -- o envio agendado de A que o agrupar cancelou (A1) volta para a fila: a hora dele ainda não passou
    pg_temp._se(exists (select 1 from public.whatsapp_scheduled_sends w
                         where w.service_order_id = v_a and w.message = 'Teste agrupar: link do orçamento'
                           and w.status = 'pending' and w.last_error is null)
                and (r ->> 'envios_reativados')::int = 1, 'envio agendado de volta'));
  insert into _resultado values ('E1 desagrupar o A1: originais voltam como estavam (situação, link, totais); agrupado cancelado; auditoria',
    v_falhas = '', case when v_falhas = '' then 'origens=' || (r ->> 'origens') else 'falhou: ' || v_falhas end);
exception when others then
  insert into _resultado values ('E1 desagrupar o A1: originais voltam como estavam (situação, link, totais); agrupado cancelado; auditoria', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_erro text;
begin
  if pg_temp._id('a1_novo') is null then
    raise exception 'o A1 não deixou o agrupado (veja a linha A1)';
  end if;
  v_erro := pg_temp._erro_desfazer(pg_temp._id('a1_novo'), pg_temp._id('admin'));
  insert into _resultado values ('E2 desagrupar de novo: recusa ("já foi desagrupado")',
    strpos(coalesce(v_erro, ''), 'já foi desagrupado') > 0, coalesce(v_erro, 'PASSOU'));
exception when others then
  insert into _resultado values ('E2 desagrupar de novo: recusa ("já foi desagrupado")', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_a uuid;
  v_b uuid;
  v_soma numeric;
  r jsonb;
  v_novo2 uuid;
  v_falhas text;
begin
  v_a := pg_temp._id('a1_a');
  v_b := pg_temp._id('a1_b');
  if v_a is null then
    raise exception 'o A1 não deixou as origens (veja a linha A1)';
  end if;
  select sum(grand_total) into v_soma from public.service_orders where id in (v_a, v_b);
  r := public._agrupar_orcamentos_montar(array[v_a, v_b], null, pg_temp._numero_agrupado(), pg_temp._id('admin'), v_soma);
  v_novo2 := (r ->> 'service_order_id')::uuid;
  v_falhas := concat_ws(', ',
    pg_temp._se(v_novo2 is not null and v_novo2 <> pg_temp._id('a1_novo'), 'novo agrupado'),
    pg_temp._se(exists (select 1 from public.orcamento_agrupamentos g where g.agrupado_id = v_novo2 and g.desfeito_em is null),
                'agrupamento ativo'),
    pg_temp._se(not exists (select 1 from public.orcamento_agrupamentos g
                             where g.agrupado_id = pg_temp._id('a1_novo') and g.desfeito_em is null), 'o antigo segue desfeito'),
    pg_temp._se((select count(*) from public.service_orders so where so.id in (v_a, v_b)
                  and so.status = 'cancelled' and so.merged_into_id = v_novo2) = 2, 'origens no novo'),
    pg_temp._se((select grand_total from public.service_orders where id = v_novo2) = v_soma, 'total'));
  insert into _resultado values ('E3 reagrupar as mesmas origens depois de desfeito funciona (novo agrupamento ativo)',
    v_falhas = '', case when v_falhas = '' then 'novo=' || (r ->> 'numero') || ' total=' || v_soma else 'falhou: ' || v_falhas end);
exception when others then
  insert into _resultado values ('E3 reagrupar as mesmas origens depois de desfeito funciona (novo agrupamento ativo)', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  r jsonb;
  v_g uuid;
  v_cli uuid;
  v_erro text;
begin
  v := pg_temp._dupla();
  r := public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  v_g := (r ->> 'service_order_id')::uuid;
  select client_id into v_cli from public.service_orders where id = v_g;
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status)
  values (v_cli, v_g, 'Teste agrupar: sinal do agrupado', current_date, current_date + 7, 100, 'pending');
  v_erro := pg_temp._erro_desfazer(v_g, pg_temp._id('admin'));
  insert into _resultado values ('E4 agrupado com conta a receber pendente: recusa ("Resolva isso antes de desagrupar") e nada muda',
    strpos(coalesce(v_erro, ''), 'Resolva isso antes de desagrupar') > 0
    and exists (select 1 from public.service_orders where id = v_g and status = 'draft')
    and (select count(*) from public.service_orders where id = any(v) and merged_into_id = v_g and status = 'cancelled') = 2,
    coalesce(v_erro, 'PASSOU'));
exception when others then
  insert into _resultado values ('E4 agrupado com conta a receber pendente: recusa ("Resolva isso antes de desagrupar") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  r jsonb;
  v_g uuid;
  v_erro text;
begin
  v := pg_temp._dupla();
  r := public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null);
  v_g := (r ->> 'service_order_id')::uuid;
  update public.service_orders set converted_to_os_at = now(), status = 'open' where id = v_g;
  v_erro := pg_temp._erro_desfazer(v_g, pg_temp._id('admin'));
  insert into _resultado values ('E5 agrupado que virou OS: recusa ("não dá mais para desagrupar") e nada muda',
    strpos(coalesce(v_erro, ''), 'não dá mais para desagrupar') > 0
    and (select count(*) from public.service_orders where id = any(v) and merged_into_id = v_g and status = 'cancelled') = 2,
    coalesce(v_erro, 'PASSOU'));
exception when others then
  insert into _resultado values ('E5 agrupado que virou OS: recusa ("não dá mais para desagrupar") e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_cli uuid;
  v_ves uuid;
  v_z uuid;
  v_g1 uuid;
  v_g2 uuid;
  v_erro text;
  v_volta text;
begin
  v := pg_temp._dupla();
  select client_id, vessel_id into v_cli, v_ves from public.service_orders where id = v[1];
  v_z := pg_temp._orc(v_cli, v_ves);
  v_g1 := (public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null)
           ->> 'service_order_id')::uuid;
  v_g2 := (public._agrupar_orcamentos_montar(array[v_g1, v_z], null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null)
           ->> 'service_order_id')::uuid;
  v_erro := pg_temp._erro_desfazer(v_g1, pg_temp._id('admin'));
  -- de fora para dentro funciona: desfaz o de fora, depois o de dentro, e os originais voltam
  perform public._desagrupar_orcamentos_desfazer(v_g2, pg_temp._id('admin'));
  perform public._desagrupar_orcamentos_desfazer(v_g1, pg_temp._id('admin'));
  select string_agg(status || '/' || coalesce(merged_into_id::text, '-'), ' ') into v_volta
    from public.service_orders where id in (v[1], v[2], v_z);
  insert into _resultado values ('E6 agrupado agrupado de novo: desfazer o de dentro recusa ("Desagrupe"); de fora para dentro funciona',
    strpos(coalesce(v_erro, ''), 'Desagrupe') > 0
    and (select count(*) from public.service_orders where id in (v[1], v[2], v_z) and status = 'draft' and merged_into_id is null) = 3
    and exists (select 1 from public.service_orders where id = v_g1 and status = 'cancelled' and merged_into_id is null),
    coalesce(v_erro, 'PASSOU') || ' | originais depois: ' || coalesce(v_volta, 'null'));
exception when others then
  insert into _resultado values ('E6 agrupado agrupado de novo: desfazer o de dentro recusa ("Desagrupe"); de fora para dentro funciona', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_g uuid;
  v_erro text;
begin
  v := pg_temp._dupla();
  v_g := (public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null)
          ->> 'service_order_id')::uuid;
  v_erro := pg_temp._erro_desfazer(v_g, pg_temp._id('tecnico'));
  insert into _resultado values ('E7 técnico não desagrupa: 42501 e o agrupamento segue ativo',
    v_erro like '42501 %'
    and exists (select 1 from public.orcamento_agrupamentos g where g.agrupado_id = v_g and g.desfeito_em is null)
    and exists (select 1 from public.service_orders where id = v_g and status = 'draft'),
    coalesce(v_erro, 'PASSOU'));
exception when others then
  insert into _resultado values ('E7 técnico não desagrupa: 42501 e o agrupamento segue ativo', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ F cancelar o agrupado pelo caminho normal ═══════════════════════════════════════════════
-- Cancelar o agrupado prenderia os originais para sempre (o desagrupar exige o agrupado em aberto):
-- a guarda do agrupado recusa e manda desagrupar primeiro. Orçamento comum segue cancelável.
do $$
declare
  v uuid[];
  v_g uuid;
  v_erro_direto text;
  v_erro_cascata text;
  v_comum uuid[];
  v_erro_comum text;
begin
  v := pg_temp._dupla();
  v_g := (public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null)
          ->> 'service_order_id')::uuid;
  v_erro_direto := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'cancelled', v_g));
  v_erro_cascata := pg_temp._erro_sql(format('select public.cancel_service_order_cascade(%L::uuid, %L)', v_g, 'teste'));
  insert into _resultado values ('F1 cancelar o agrupado (direto ou pela cascata) é recusado e nada muda',
    strpos(coalesce(v_erro_direto, ''), 'Desagrupar') > 0
    and strpos(coalesce(v_erro_cascata, ''), 'Desagrupar') > 0
    and exists (select 1 from public.service_orders where id = v_g and status = 'draft' and cancelled_at is null)
    and exists (select 1 from public.orcamento_agrupamentos g where g.agrupado_id = v_g and g.desfeito_em is null)
    and (select count(*) from public.service_orders where id = any(v) and merged_into_id = v_g and status = 'cancelled') = 2,
    coalesce(v_erro_direto, 'DIRETO PASSOU') || ' | ' || coalesce(v_erro_cascata, 'CASCATA PASSOU'));

  v_comum := pg_temp._dupla();
  v_erro_comum := pg_temp._erro_sql(format('select public.cancel_service_order_cascade(%L::uuid, %L)', v_comum[1], 'teste'));
  insert into _resultado values ('F2 orçamento comum segue cancelável pela cascata',
    v_erro_comum is null and exists (select 1 from public.service_orders where id = v_comum[1] and status = 'cancelled'),
    coalesce(v_erro_comum, 'ok'));

  -- desagrupado, o agrupado fica cancelado pelo próprio desagrupar (a guarda deixa passar só ali)
  perform public._desagrupar_orcamentos_desfazer(v_g, pg_temp._id('admin'));
  insert into _resultado values ('F3 desagrupar cancela o agrupado mesmo com a guarda',
    exists (select 1 from public.service_orders where id = v_g and status = 'cancelled' and share_token is null)
    and (select count(*) from public.service_orders where id = any(v) and status = 'draft' and merged_into_id is null) = 2,
    'ok');
exception when others then
  insert into _resultado values ('F1 cancelar o agrupado (direto ou pela cascata) é recusado e nada muda', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- Depois de virar OS (ou ser assinado) o desagrupar já não é possível: cancelar segue o caminho normal e os
-- originais ficam como histórico (senão a OS ficaria presa para sempre).
do $$
declare
  v uuid[];
  v_g uuid;
  v_erro text;
begin
  v := pg_temp._dupla();
  v_g := (public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null)
          ->> 'service_order_id')::uuid;
  update public.service_orders set converted_to_os_at = now(), status = 'open' where id = v_g;
  v_erro := pg_temp._erro_sql(format('select public.cancel_service_order_cascade(%L::uuid, %L)', v_g, 'teste'));
  insert into _resultado values ('F4 agrupado que virou OS cancela pela cascata; os originais seguem como histórico',
    v_erro is null
    and exists (select 1 from public.service_orders where id = v_g and status = 'cancelled')
    and (select count(*) from public.service_orders where id = any(v) and merged_into_id = v_g and status = 'cancelled') = 2,
    coalesce(v_erro, 'ok'));
exception when others then
  insert into _resultado values ('F4 agrupado que virou OS cancela pela cascata; os originais seguem como histórico', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_g uuid;
  v_erro text;
begin
  v := pg_temp._dupla();
  v_g := (public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null)
          ->> 'service_order_id')::uuid;
  update public.service_orders set signed_at = now() where id = v_g;
  v_erro := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'cancelled', v_g));
  insert into _resultado values ('F5 agrupado assinado cancela pelo caminho normal',
    v_erro is null and exists (select 1 from public.service_orders where id = v_g and status = 'cancelled'),
    coalesce(v_erro, 'ok'));
exception when others then
  insert into _resultado values ('F5 agrupado assinado cancela pelo caminho normal', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v uuid[];
  v_g uuid;
  v_erro text;
  v_erro_comum text;
  v_comum uuid;
begin
  v := pg_temp._dupla();
  v_g := (public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null)
          ->> 'service_order_id')::uuid;
  perform public._desagrupar_orcamentos_desfazer(v_g, pg_temp._id('admin'));
  -- aba velha do agrupado: o autosave manda status = 'draft'
  v_erro := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'draft', v_g));
  -- orçamento comum cancelado segue podendo voltar (a guarda só olha agrupado desfeito)
  v_comum := pg_temp._orc_vazio((select client_id from public.service_orders where id = v[1]),
                                (select vessel_id from public.service_orders where id = v[1]), 'cancelled');
  v_erro_comum := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'draft', v_comum));
  insert into _resultado values ('F6 agrupado já desagrupado não volta a valer (reabrir recusa "desagrupado"); cancelado comum reabre',
    v_erro like '42501 %' and strpos(v_erro, 'desagrupado') > 0
    and exists (select 1 from public.service_orders where id = v_g and status = 'cancelled')
    and (select count(*) from public.service_orders where id = any(v) and status = 'draft' and merged_into_id is null) = 2
    and v_erro_comum is null and exists (select 1 from public.service_orders where id = v_comum and status = 'draft'),
    coalesce(v_erro, 'REABRIU') || ' | comum: ' || coalesce(v_erro_comum, 'ok'));
exception when others then
  insert into _resultado values ('F6 agrupado já desagrupado não volta a valer (reabrir recusa "desagrupado"); cancelado comum reabre', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G dinheiro numa origem agrupada ═════════════════════════════════════════════════════════
do $$
declare
  v uuid[];
  v_g uuid;
  v_cli uuid;
  v_erro_direto text;
  v_erro_sinal text;
  v_erro_agrupado text;
begin
  v := pg_temp._dupla();
  v_g := (public._agrupar_orcamentos_montar(v, null, pg_temp._numero_agrupado(), pg_temp._id('admin'), null)
          ->> 'service_order_id')::uuid;
  select client_id into v_cli from public.service_orders where id = v[1];
  v_erro_direto := pg_temp._erro_sql(format(
    'insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status) '
    || 'values (%L, %L, %L, current_date, current_date + 7, 100, %L)', v_cli, v[1], 'Teste agrupar: sinal na origem', 'pending'));
  v_erro_sinal := pg_temp._erro_sql(format(
    'select public.register_deposit_and_convert(%L::uuid, 100, current_date, %L)', v[1], 'pix'));
  -- no agrupado o recebível entra normalmente
  v_erro_agrupado := pg_temp._erro_sql(format(
    'insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status) '
    || 'values (%L, %L, %L, current_date, current_date + 7, 100, %L)', v_cli, v_g, 'Teste agrupar: sinal no agrupado', 'pending'));
  insert into _resultado values ('G1 sinal/recebível na origem agrupada é recusado ("foi agrupado em") e nada fica nela; no agrupado entra',
    strpos(coalesce(v_erro_direto, ''), 'foi agrupado em') > 0
    and strpos(coalesce(v_erro_sinal, ''), 'foi agrupado em') > 0
    and not exists (select 1 from public.receivables where service_order_id = v[1])
    and (select count(*) from public.service_orders where id = any(v) and merged_into_id = v_g and status = 'cancelled') = 2
    and v_erro_agrupado is null,
    'direto: ' || coalesce(v_erro_direto, 'PASSOU') || ' | sinal: ' || coalesce(v_erro_sinal, 'PASSOU')
    || ' | agrupado: ' || coalesce(v_erro_agrupado, 'ok'));
exception when others then
  insert into _resultado values ('G1 sinal/recebível na origem agrupada é recusado ("foi agrupado em") e nada fica nela; no agrupado entra', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
