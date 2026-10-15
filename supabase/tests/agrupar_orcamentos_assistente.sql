-- Prova: a leitura do assistente para agrupar orçamentos e o agrupar que reabre o reprovado no "sim"
-- (migration 20261015181000_agrupar_orcamentos_assistente).
--
--   G1  ordem do mais NOVO para o mais antigo; reprovado aparece (reprovado=true, elegivel=false, motivo de
--       desistência, situação "Reprovado" como na tela) com reprovado_em do audit_log ou, sem ele, NULL (a
--       última alteração não é a data da reprovação); os em elaboração aparecem elegíveis e sem motivo
--   G2  inelegíveis aparecem com o motivo, na ordem do _agrupar_orcamentos_montar: assinado, repasse do
--       cartão, ligado a conta a receber, total gravado desatualizado; reprovado E assinado = desistência no
--       motivo e "assinado" em impedimento_se_voltar; reprovado sem outro impedimento: impedimento nulo;
--       deslocamento marcado
--   G3  origem já agrupada não aparece na lista (aparece em fora_da_lista: "já agrupado em ORÇ-T…"); o
--       agrupado aparece na lista (com as origens em "reune") e em agrupados_ativos (origens na ordem, pode
--       desagrupar); desagrupado, sai de agrupados_ativos
--   G4  cancelado e OS não aparecem na lista e aparecem em fora_da_lista com o porquê, do mais novo ao mais
--       antigo; filtro por cliente: orçamento de outro cliente no mesmo barco só aparece sem o filtro
--   G5  no máximo os 20 mais novos, com em_aberto = o total real; p_incluir traz também um antigo pedido
--   G6  portas sem sessão: técnico, admin inativo, usuário desconhecido e sem autor dão 42501; financeiro
--       lê; embarcação inexistente P0002; embarcação nula 22023
--   G7  privilégios: anon sem execute; authenticated e service_role com (a interna só service_role); a
--       leitura é stable; todas security definer com search_path vazio; o rascunho de 3 argumentos não existe
--   G8  com sessão vale a SESSÃO, não p_autor: técnico logado passando p_autor = admin dá 42501 (leitura e
--       agrupar reabrindo); admin logado passando p_autor = técnico lê
--   G9  agrupar reabrindo: reabrir fora dos escolhidos e reabrir quem não é reprovado recusam; recusa do
--       agrupar (conta a receber) deixa o reprovado reprovado e sem auditoria; no sucesso o reprovado sai
--       para Em elaboração (auditoria "update" rejected -> draft), entra, e o histórico guarda Reprovado;
--       desagrupar devolve-o como Reprovado
--
-- ═══ COMO RODAR ═══ (só com OK nomeado; DEPOIS das migrations 20261015180000 e 20261015181000 aplicadas)
--
--   npx supabase@2.111.0 db query --linked -f supabase/tests/agrupar_orcamentos_assistente.sql --output json
--   (a partir do repositório principal: o worktree não é linkado)
--
-- Seguro em produção: usuários, clientes, barcos e orçamentos de teste criados aqui (números ORÇ-9xxxxx
-- livres); os agrupados do G3 e do G9 recebem número fictício ORÇ-T… passado direto às funções internas
-- (não gasta o document_number_seq); a chamada à porta pública do G8 leva um total esperado impossível,
-- então mesmo um defeito na porta pararia antes de numerar. Nada sai (nenhum envio). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ids (nome text primary key, id uuid) on commit drop;

-- sem sessão: auth.uid() nulo (vale p_autor, como o assistente pelo service role)
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);

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
  values (v_id, 'Teste listar agrupar (' || p_role || ')', 'teste-listar-agrupar-' || v_id || '@teste.invalido', p_role, p_ativo);
  return v_id;
end $$;

create function pg_temp._cliente() returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Listar Agrupar ' || pg_temp._letras(6))
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

-- número ORÇ-9xxxxx livre
create function pg_temp._numero_livre() returns text language plpgsql as $$
declare
  v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number = 'ORÇ-' || v_num) loop
    v_num := v_num + 1;
  end loop;
  return 'ORÇ-' || v_num;
end $$;

-- orçamento com 1 serviço (2 h × R$ 150), totais pelo banco; created_at fixo (a ordem da lista é por ele)
create function pg_temp._orc(p_cli uuid, p_ves uuid, p_criado_em timestamptz, p_status text default 'draft',
                             p_quote_status text default 'draft')
returns uuid language plpgsql as $$
declare
  v_os uuid;
begin
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, created_at)
  values (pg_temp._numero_livre(), p_cli, p_ves, p_status, p_quote_status, p_criado_em)
  returning id into v_os;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, discount_pct, discount_amount,
                                             created_at, updated_at)
  values (v_os, 'Serviço de teste', 'hour', 2, 150, 300, 0, 0, p_criado_em, p_criado_em);
  perform public.recalc_so_totals(v_os);
  return v_os;
end $$;

create function pg_temp._numero(p_os uuid) returns text language sql stable as $$
  select service_order_number from public.service_orders where id = p_os
$$;

-- o item da lista de um orçamento (null = não está na lista)
create function pg_temp._item(p_lista jsonb, p_os uuid) returns jsonb language sql immutable as $$
  select e from jsonb_array_elements(p_lista -> 'orcamentos') e where e ->> 'id' = p_os::text
$$;

-- os números na ordem em que a lista devolve
create function pg_temp._numeros(p_lista jsonb) returns text language sql immutable as $$
  select string_agg(e ->> 'numero', ' > ' order by i)
    from jsonb_array_elements(p_lista -> 'orcamentos') with ordinality as x(e, i)
$$;

-- fora_da_lista: o item de um número e os números na ordem devolvida
create function pg_temp._fora(p_lista jsonb, p_numero text) returns jsonb language sql immutable as $$
  select e from jsonb_array_elements(p_lista -> 'fora_da_lista') e where e ->> 'numero' = p_numero
$$;

create function pg_temp._numeros_fora(p_lista jsonb) returns text language sql immutable as $$
  select string_agg(e ->> 'numero', ' > ' order by i)
    from jsonb_array_elements(p_lista -> 'fora_da_lista') with ordinality as x(e, i)
$$;

-- captura de erro: null = passou; senão "sqlstate mensagem"
create function pg_temp._erro_listar(p_ves uuid, p_cli uuid, p_autor uuid) returns text language plpgsql as $$
begin
  perform public.orcamentos_para_agrupar(p_ves, p_cli, p_autor);
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

-- usuários de teste
insert into _ids values
  ('admin', pg_temp._usuario('admin')),
  ('financeiro', pg_temp._usuario('financial')),
  ('tecnico', pg_temp._usuario('technician')),
  ('admin_inativo', pg_temp._usuario('admin', false));

-- ═══ G1 ordem e reprovados ═════════════════════════════════════════════════════════════════
do $$
declare
  v_cli uuid;
  v_ves uuid;
  v_a uuid;
  v_b uuid;
  v_c uuid;
  v_d uuid;
  v_quando timestamptz := now() - interval '90 minutes';
  r jsonb;
  ib jsonb;
  ic jsonb;
  ia jsonb;
  v_falhas text;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_a := pg_temp._orc(v_cli, v_ves, now() - interval '4 hours');
  v_b := pg_temp._orc(v_cli, v_ves, now() - interval '3 hours', 'draft', 'rejected');
  v_c := pg_temp._orc(v_cli, v_ves, now() - interval '2 hours', 'draft', 'rejected');
  v_d := pg_temp._orc(v_cli, v_ves, now() - interval '1 hour');
  -- a tela grava a reprovação assim (action 'update', new_value só com a situação nova)
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, changed_at)
  values ('service_orders', v_b, 'update', 'Teste listar agrupar', null, jsonb_build_object('quote_status', 'rejected'), v_quando);

  r := public.orcamentos_para_agrupar(v_ves, v_cli, pg_temp._id('admin'));
  ia := pg_temp._item(r, v_a);
  ib := pg_temp._item(r, v_b);
  ic := pg_temp._item(r, v_c);

  v_falhas := concat_ws(', ',
    pg_temp._se(pg_temp._numeros(r) = concat_ws(' > ', pg_temp._numero(v_d), pg_temp._numero(v_c), pg_temp._numero(v_b), pg_temp._numero(v_a)),
                'ordem (mais novo primeiro)'),
    pg_temp._se((r ->> 'em_aberto')::int = 4 and (r ->> 'mostrando')::int = 4, 'contagem'),
    pg_temp._se(r -> 'embarcacao' ->> 'id' = v_ves::text and r -> 'cliente' ->> 'id' = v_cli::text, 'embarcação/cliente'),
    pg_temp._se((ib ->> 'reprovado')::boolean and not (ib ->> 'elegivel')::boolean
                and ib ->> 'motivo' = 'reprovado pelo cliente (desistência)'
                and ib ->> 'situacao' = 'Reprovado' and ib ->> 'quote_status' = 'rejected'
                and ib -> 'impedimento_se_voltar' = 'null'::jsonb, 'reprovado B'),
    pg_temp._se((ib ->> 'reprovado_em')::timestamptz = v_quando
                and ib ->> 'reprovado_em_data' = to_char(v_quando at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
                'reprovado_em pelo audit_log'),
    pg_temp._se((ic ->> 'reprovado')::boolean and ic -> 'reprovado_em' = 'null'::jsonb and ic -> 'reprovado_em_data' = 'null'::jsonb,
                'reprovado sem audit: data nula (não registrada)'),
    pg_temp._se(not (ia ->> 'reprovado')::boolean and (ia ->> 'elegivel')::boolean and ia -> 'motivo' = 'null'::jsonb
                and ia -> 'reprovado_em' = 'null'::jsonb and ia ->> 'situacao' = 'Em elaboração'
                and ia -> 'impedimento_se_voltar' = 'null'::jsonb
                and (ia ->> 'total')::numeric = 300 and not (ia ->> 'tem_deslocamento')::boolean, 'em elaboração elegível'),
    pg_temp._se(jsonb_array_length(r -> 'fora_da_lista') = 0, 'fora_da_lista deveria vir vazio'));
  insert into _resultado values ('G1 ordem do mais novo; reprovado aparece com desistência e reprovado_em (audit ou nulo)',
    v_falhas = '', case when v_falhas = '' then 'lista: ' || pg_temp._numeros(r) else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('G1 ordem do mais novo; reprovado aparece com desistência e reprovado_em (audit ou nulo)',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G2 inelegíveis com o motivo ═══════════════════════════════════════════════════════════
do $$
declare
  v_cli uuid;
  v_ves uuid;
  v_ok uuid;
  v_assinado uuid;
  v_cartao uuid;
  v_receber uuid;
  v_velho uuid;
  v_rep_assinado uuid;
  v_desloc uuid;
  r jsonb;
  v_falhas text;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_ok := pg_temp._orc(v_cli, v_ves, now() - interval '7 hours');
  v_assinado := pg_temp._orc(v_cli, v_ves, now() - interval '6 hours');
  update public.service_orders set signed_at = now() where id = v_assinado;
  v_cartao := pg_temp._orc(v_cli, v_ves, now() - interval '5 hours');
  update public.service_orders set card_fee_passthrough_enabled = true where id = v_cartao;
  perform public.recalc_so_totals(v_cartao);
  v_receber := pg_temp._orc(v_cli, v_ves, now() - interval '4 hours');
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status)
  values (v_cli, v_receber, 'Teste listar agrupar: sinal pendente', current_date, current_date + 7, 100, 'pending');
  v_velho := pg_temp._orc(v_cli, v_ves, now() - interval '3 hours');
  update public.service_orders set grand_total = grand_total + 7 where id = v_velho;
  v_rep_assinado := pg_temp._orc(v_cli, v_ves, now() - interval '2 hours', 'draft', 'rejected');
  update public.service_orders set signed_at = now() where id = v_rep_assinado;
  v_desloc := pg_temp._orc(v_cli, v_ves, now() - interval '1 hour');
  update public.service_orders set travel_cost_total = 80, travel_distance_km = 15 where id = v_desloc;
  perform public.recalc_so_totals(v_desloc);

  r := public.orcamentos_para_agrupar(v_ves, null, pg_temp._id('financeiro'));

  v_falhas := concat_ws(', ',
    pg_temp._se((pg_temp._item(r, v_ok) ->> 'elegivel')::boolean, 'o comum ficou inelegível'),
    pg_temp._se(not (pg_temp._item(r, v_assinado) ->> 'elegivel')::boolean
                and pg_temp._item(r, v_assinado) ->> 'motivo' = 'assinado pelo cliente'
                and pg_temp._item(r, v_assinado) -> 'impedimento_se_voltar' = 'null'::jsonb, 'assinado'),
    pg_temp._se(not (pg_temp._item(r, v_cartao) ->> 'elegivel')::boolean
                and pg_temp._item(r, v_cartao) ->> 'motivo' = 'repassa a taxa do cartão', 'repasse do cartão'),
    pg_temp._se(not (pg_temp._item(r, v_receber) ->> 'elegivel')::boolean
                and pg_temp._item(r, v_receber) ->> 'motivo' like 'ligado a: %conta a receber%', 'conta a receber'),
    pg_temp._se(not (pg_temp._item(r, v_velho) ->> 'elegivel')::boolean
                and pg_temp._item(r, v_velho) ->> 'motivo' = 'total gravado desatualizado', 'total desatualizado'),
    pg_temp._se(pg_temp._item(r, v_rep_assinado) ->> 'motivo' = 'reprovado pelo cliente (desistência)'
                and pg_temp._item(r, v_rep_assinado) ->> 'impedimento_se_voltar' = 'assinado pelo cliente',
                'reprovado e assinado = desistência no motivo e assinado em impedimento_se_voltar'),
    pg_temp._se((pg_temp._item(r, v_desloc) ->> 'tem_deslocamento')::boolean
                and (pg_temp._item(r, v_desloc) ->> 'elegivel')::boolean, 'deslocamento marcado (e elegível)'),
    pg_temp._se((r ->> 'em_aberto')::int = 7, 'contagem'));
  insert into _resultado values ('G2 inelegíveis com o motivo (assinado, cartão, conta a receber, total velho; reprovado com impedimento_se_voltar)',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('G2 inelegíveis com o motivo (assinado, cartão, conta a receber, total velho; reprovado com impedimento_se_voltar)',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G3 agrupados ══════════════════════════════════════════════════════════════════════════
do $$
declare
  v_cli uuid;
  v_ves uuid;
  v_a uuid;
  v_b uuid;
  v_c uuid;
  v_novo uuid;
  r jsonb;
  r2 jsonb;
  v_ag jsonb;
  v_origens jsonb;
  v_falhas text;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_a := pg_temp._orc(v_cli, v_ves, now() - interval '3 hours');
  v_b := pg_temp._orc(v_cli, v_ves, now() - interval '2 hours');
  v_c := pg_temp._orc(v_cli, v_ves, now() - interval '1 hour');
  v_novo := (public._agrupar_orcamentos_montar(array[v_a, v_b], null, 'ORÇ-T' || upper(pg_temp._letras(6)),
                                                pg_temp._id('admin'), null) ->> 'service_order_id')::uuid;
  v_origens := jsonb_build_array(pg_temp._numero(v_a), pg_temp._numero(v_b));

  r := public.orcamentos_para_agrupar(v_ves, v_cli, pg_temp._id('admin'));
  select e into v_ag from jsonb_array_elements(r -> 'agrupados_ativos') e where e ->> 'id' = v_novo::text;

  perform public._desagrupar_orcamentos_desfazer(v_novo, pg_temp._id('admin'));
  r2 := public.orcamentos_para_agrupar(v_ves, v_cli, pg_temp._id('admin'));

  v_falhas := concat_ws(', ',
    pg_temp._se(pg_temp._item(r, v_a) is null and pg_temp._item(r, v_b) is null, 'origem agrupada apareceu'),
    pg_temp._se(pg_temp._fora(r, pg_temp._numero(v_a)) ->> 'por_que' = 'já agrupado em ' || pg_temp._numero(v_novo)
                and pg_temp._fora(r, pg_temp._numero(v_b)) ->> 'por_que' = 'já agrupado em ' || pg_temp._numero(v_novo),
                'origem agrupada em fora_da_lista'),
    pg_temp._se(pg_temp._item(r, v_novo) -> 'reune' = v_origens and (pg_temp._item(r, v_novo) ->> 'elegivel')::boolean,
                'agrupado na lista com "reune"'),
    pg_temp._se(pg_temp._item(r, v_c) is not null and pg_temp._item(r, v_c) -> 'reune' = 'null'::jsonb, 'orçamento comum'),
    pg_temp._se((r ->> 'em_aberto')::int = 2, 'contagem (agrupado + o comum)'),
    pg_temp._se(jsonb_array_length(r -> 'agrupados_ativos') = 1 and v_ag -> 'origens' = v_origens
                and (v_ag ->> 'pode_desagrupar')::boolean and v_ag ->> 'numero' like 'ORÇ-T%', 'agrupados_ativos'),
    pg_temp._se(jsonb_array_length(r2 -> 'agrupados_ativos') = 0
                and pg_temp._item(r2, v_a) is not null and pg_temp._item(r2, v_b) is not null
                and pg_temp._item(r2, v_novo) is null
                and pg_temp._fora(r2, pg_temp._numero(v_novo)) ->> 'por_que' = 'cancelado', 'depois de desagrupar'));
  insert into _resultado values ('G3 origem agrupada fora (e em fora_da_lista); agrupado na lista e em agrupados_ativos; desagrupado volta ao normal',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || r::text end);
exception when others then
  insert into _resultado values ('G3 origem agrupada fora (e em fora_da_lista); agrupado na lista e em agrupados_ativos; desagrupado volta ao normal',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G4 fora da lista e filtro por cliente ═════════════════════════════════════════════════
do $$
declare
  v_cli uuid;
  v_cli2 uuid;
  v_ves uuid;
  v_aberto uuid;
  v_cancelado uuid;
  v_os uuid;
  v_convertido uuid;
  v_outro uuid;
  r_com jsonb;
  r_sem jsonb;
  v_falhas text;
begin
  v_cli := pg_temp._cliente();
  v_cli2 := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_aberto := pg_temp._orc(v_cli, v_ves, now() - interval '5 hours');
  v_cancelado := pg_temp._orc(v_cli, v_ves, now() - interval '4 hours', 'cancelled');
  v_os := pg_temp._orc(v_cli, v_ves, now() - interval '3 hours', 'open');
  v_convertido := pg_temp._orc(v_cli, v_ves, now() - interval '2 hours');
  update public.service_orders set converted_to_os_at = now() where id = v_convertido;
  v_outro := pg_temp._orc(v_cli2, v_ves, now() - interval '1 hour');

  r_com := public.orcamentos_para_agrupar(v_ves, v_cli, pg_temp._id('admin'));
  r_sem := public.orcamentos_para_agrupar(v_ves, null, pg_temp._id('admin'));

  v_falhas := concat_ws(', ',
    pg_temp._se(pg_temp._numeros(r_com) = pg_temp._numero(v_aberto), 'com filtro: só o aberto do cliente'),
    pg_temp._se(pg_temp._numeros(r_sem) = pg_temp._numero(v_outro) || ' > ' || pg_temp._numero(v_aberto),
                'sem filtro: o de outro cliente no mesmo barco aparece'),
    pg_temp._se(pg_temp._item(r_sem, v_outro) ->> 'cliente_id' = v_cli2::text, 'cliente de cada orçamento'),
    pg_temp._se(r_sem -> 'cliente' ->> 'id' = v_cli::text, 'sem filtro: cliente = o dono do barco'),
    pg_temp._se(pg_temp._numeros_fora(r_com) = concat_ws(' > ', pg_temp._numero(v_convertido), pg_temp._numero(v_os), pg_temp._numero(v_cancelado)),
                'fora_da_lista do mais novo ao mais antigo'),
    pg_temp._se(pg_temp._fora(r_com, pg_temp._numero(v_convertido)) ->> 'por_que' = 'virou OS'
                and pg_temp._fora(r_com, pg_temp._numero(v_os)) ->> 'por_que' = 'virou OS'
                and pg_temp._fora(r_com, pg_temp._numero(v_cancelado)) ->> 'por_que' = 'cancelado'
                and (pg_temp._fora(r_com, pg_temp._numero(v_cancelado)) ->> 'total') is not null, 'porquê de cada um'));
  insert into _resultado values ('G4 cancelado, OS e convertido fora (e em fora_da_lista com o porquê); filtro por cliente',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | com: ' || coalesce(pg_temp._numeros(r_com), '-')
                                                       || ' | sem: ' || coalesce(pg_temp._numeros(r_sem), '-')
                                                       || ' | fora: ' || coalesce((r_com -> 'fora_da_lista')::text, '-') end);
exception when others then
  insert into _resultado values ('G4 cancelado, OS e convertido fora (e em fora_da_lista com o porquê); filtro por cliente', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G5 no máximo 20 + p_incluir ═══════════════════════════════════════════════════════════
do $$
declare
  v_cli uuid;
  v_ves uuid;
  v_mais_novo uuid;
  v_mais_velho uuid;
  r jsonb;
  r2 jsonb;
  i integer;
  v_id uuid;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  for i in 1..22 loop
    v_id := pg_temp._orc(v_cli, v_ves, now() - make_interval(hours => 30 - i));
    if i = 1 then v_mais_velho := v_id; end if;
    if i = 22 then v_mais_novo := v_id; end if;
  end loop;
  r := public.orcamentos_para_agrupar(v_ves, v_cli, pg_temp._id('admin'));
  r2 := public.orcamentos_para_agrupar(v_ves, v_cli, pg_temp._id('admin'), array[v_mais_velho, gen_random_uuid()]);
  insert into _resultado values ('G5 no máximo os 20 mais novos, em_aberto = total real; p_incluir traz o antigo pedido',
    (r ->> 'em_aberto')::int = 22 and (r ->> 'mostrando')::int = 20 and jsonb_array_length(r -> 'orcamentos') = 20
    and r -> 'orcamentos' -> 0 ->> 'id' = v_mais_novo::text and pg_temp._item(r, v_mais_velho) is null
    and (r2 ->> 'mostrando')::int = 21 and pg_temp._item(r2, v_mais_velho) is not null
    and r2 -> 'orcamentos' -> 0 ->> 'id' = v_mais_novo::text and r2 -> 'orcamentos' -> 20 ->> 'id' = v_mais_velho::text,
    'em_aberto=' || (r ->> 'em_aberto') || ' mostrando=' || (r ->> 'mostrando') || ' com p_incluir=' || (r2 ->> 'mostrando'));
exception when others then
  insert into _resultado values ('G5 no máximo os 20 mais novos, em_aberto = total real; p_incluir traz o antigo pedido', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G6 portas (sem sessão) ════════════════════════════════════════════════════════════════
do $$
declare
  v_cli uuid;
  v_ves uuid;
  e_tec text;
  e_inativo text;
  e_desconhecido text;
  e_nulo text;
  e_fin text;
  e_barco text;
  e_sem_barco text;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  perform pg_temp._orc(v_cli, v_ves, now() - interval '1 hour');
  e_tec := pg_temp._erro_listar(v_ves, null, pg_temp._id('tecnico'));
  e_inativo := pg_temp._erro_listar(v_ves, null, pg_temp._id('admin_inativo'));
  e_desconhecido := pg_temp._erro_listar(v_ves, null, gen_random_uuid());
  e_nulo := pg_temp._erro_listar(v_ves, null, null);
  e_fin := pg_temp._erro_listar(v_ves, null, pg_temp._id('financeiro'));
  e_barco := pg_temp._erro_listar(gen_random_uuid(), null, pg_temp._id('admin'));
  e_sem_barco := pg_temp._erro_listar(null, null, pg_temp._id('admin'));
  insert into _resultado values ('G6 técnico, inativo, desconhecido e sem autor: 42501; financeiro lê; barco inexistente P0002; nulo 22023',
    auth.uid() is null
    and e_tec like '42501 %' and e_inativo like '42501 %' and e_desconhecido like '42501 %'
    and e_nulo like '42501 %Faça login%' and e_fin is null
    and e_barco like 'P0002 %' and e_sem_barco like '22023 %',
    'técnico: ' || coalesce(e_tec, 'PASSOU') || ' | inativo: ' || coalesce(e_inativo, 'PASSOU')
    || ' | desconhecido: ' || coalesce(e_desconhecido, 'PASSOU') || ' | sem autor: ' || coalesce(e_nulo, 'PASSOU')
    || ' | financeiro: ' || coalesce(e_fin, 'leu') || ' | barco: ' || coalesce(e_barco, 'PASSOU')
    || ' | nulo: ' || coalesce(e_sem_barco, 'PASSOU'));
exception when others then
  insert into _resultado values ('G6 técnico, inativo, desconhecido e sem autor: 42501; financeiro lê; barco inexistente P0002; nulo 22023',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G7 privilégios ════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f text := 'public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[])';
  v_int text := 'public._agrupar_orcamentos_reabrindo(uuid[], uuid[], uuid, text, uuid, numeric)';
  v_pub text := 'public.agrupar_orcamentos_reabrindo(uuid[], uuid[], uuid, numeric, uuid)';
  p pg_proc;
  f_int pg_proc;
  f_pub pg_proc;
  v_falhas text;
begin
  select * into p from pg_proc where oid = v_f::regprocedure;
  select * into f_int from pg_proc where oid = v_int::regprocedure;
  select * into f_pub from pg_proc where oid = v_pub::regprocedure;
  v_falhas := concat_ws(', ',
    pg_temp._se(not has_function_privilege('anon', v_f, 'execute'), 'anon executa a leitura'),
    pg_temp._se(has_function_privilege('authenticated', v_f, 'execute'), 'logado sem execute na leitura'),
    pg_temp._se(has_function_privilege('service_role', v_f, 'execute'), 'service_role sem execute na leitura'),
    pg_temp._se(p.provolatile = 's', 'a leitura não é stable (poderia gravar)'),
    pg_temp._se(p.prosecdef and f_int.prosecdef and f_pub.prosecdef, 'alguma não é security definer'),
    pg_temp._se((p.proconfig @> array['search_path=""'] or p.proconfig @> array['search_path='])
                and (f_int.proconfig @> array['search_path=""'] or f_int.proconfig @> array['search_path='])
                and (f_pub.proconfig @> array['search_path=""'] or f_pub.proconfig @> array['search_path=']), 'search_path não é vazio'),
    pg_temp._se(to_regprocedure('public.orcamentos_para_agrupar(uuid, uuid, uuid)') is null, 'o rascunho de 3 argumentos ainda existe'),
    pg_temp._se(not has_function_privilege('anon', v_int, 'execute') and not has_function_privilege('authenticated', v_int, 'execute')
                and has_function_privilege('service_role', v_int, 'execute'), 'a interna fora do service_role'),
    pg_temp._se(not has_function_privilege('anon', v_pub, 'execute') and has_function_privilege('authenticated', v_pub, 'execute')
                and has_function_privilege('service_role', v_pub, 'execute'), 'a porta do agrupar reabrindo'));
  insert into _resultado values ('G7 privilégios: anon fora, authenticated e service_role dentro (interna só service_role); stable, security definer, search_path vazio',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | proconfig=' || coalesce(p.proconfig::text, 'null') end);
exception when others then
  insert into _resultado values ('G7 privilégios: anon fora, authenticated e service_role dentro (interna só service_role); stable, security definer, search_path vazio',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G8 com sessão vale a sessão, não p_autor ══════════════════════════════════════════════
do $$
declare
  v_cli uuid;
  v_ves uuid;
  v_a uuid;
  v_b uuid;
  e_tec_listar text;
  e_tec_reabrir text;
  e_admin_listar text;
  v_situacao text;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_a := pg_temp._orc(v_cli, v_ves, now() - interval '2 hours');
  v_b := pg_temp._orc(v_cli, v_ves, now() - interval '1 hour', 'draft', 'rejected');

  -- técnico logado passando p_autor = admin
  perform set_config('request.jwt.claim.sub', pg_temp._id('tecnico')::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp._id('tecnico'), 'role', 'authenticated')::text, true);
  e_tec_listar := pg_temp._erro_listar(v_ves, null, pg_temp._id('admin'));
  -- total esperado impossível (-1): mesmo uma porta com defeito pararia antes de numerar
  e_tec_reabrir := pg_temp._erro_sql(format('select public.agrupar_orcamentos_reabrindo(%L::uuid[], %L::uuid[], null, -1, %L::uuid)',
                                            array[v_a, v_b], array[v_b], pg_temp._id('admin')));
  -- admin logado passando p_autor = técnico
  perform set_config('request.jwt.claim.sub', pg_temp._id('admin')::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp._id('admin'), 'role', 'authenticated')::text, true);
  e_admin_listar := pg_temp._erro_listar(v_ves, null, pg_temp._id('tecnico'));
  -- volta a "sem sessão"
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  select quote_status into v_situacao from public.service_orders where id = v_b;
  insert into _resultado values ('G8 com sessão vale a sessão: técnico logado com p_autor=admin dá 42501 (ler e agrupar reabrindo); admin logado com p_autor=técnico lê',
    e_tec_listar like '42501 %' and e_tec_reabrir like '42501 %' and e_admin_listar is null
    and v_situacao = 'rejected' and auth.uid() is null,
    'técnico lendo: ' || coalesce(e_tec_listar, 'PASSOU') || ' | técnico reabrindo: ' || coalesce(e_tec_reabrir, 'PASSOU')
    || ' | admin lendo: ' || coalesce(e_admin_listar, 'leu') || ' | situação do reprovado: ' || coalesce(v_situacao, '-'));
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('G8 com sessão vale a sessão: técnico logado com p_autor=admin dá 42501 (ler e agrupar reabrindo); admin logado com p_autor=técnico lê',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ G9 agrupar reabrindo o reprovado ══════════════════════════════════════════════════════
do $$
declare
  v_cli uuid;
  v_ves uuid;
  v_a uuid;
  v_b uuid;
  v_c uuid;
  v_novo uuid;
  r jsonb;
  v_erro_fora text;
  v_erro_nao_rep text;
  v_erro_vinculo text;
  v_sit_depois_da_recusa text;
  v_audit_depois_da_recusa integer;
  v_falhas text;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  v_a := pg_temp._orc(v_cli, v_ves, now() - interval '3 hours');
  v_b := pg_temp._orc(v_cli, v_ves, now() - interval '2 hours', 'draft', 'rejected');
  v_c := pg_temp._orc(v_cli, v_ves, now() - interval '1 hour');

  -- reabrir fora dos escolhidos; reabrir quem não é reprovado
  v_erro_fora := pg_temp._erro_sql(format('select public._agrupar_orcamentos_reabrindo(%L::uuid[], %L::uuid[], null, %L, %L::uuid, null)',
                                          array[v_a, v_c], array[v_b], 'ORÇ-T' || upper(pg_temp._letras(6)), pg_temp._id('admin')));
  v_erro_nao_rep := pg_temp._erro_sql(format('select public._agrupar_orcamentos_reabrindo(%L::uuid[], %L::uuid[], null, %L, %L::uuid, null)',
                                             array[v_a, v_b], array[v_a], 'ORÇ-T' || upper(pg_temp._letras(6)), pg_temp._id('admin')));
  -- o agrupar recusa (c com conta a receber): o reprovado continua reprovado, sem a linha da auditoria
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status)
  values (v_cli, v_c, 'Teste agrupar reabrindo: sinal pendente', current_date, current_date + 7, 100, 'pending');
  v_erro_vinculo := pg_temp._erro_sql(format('select public._agrupar_orcamentos_reabrindo(%L::uuid[], %L::uuid[], null, %L, %L::uuid, null)',
                                             array[v_b, v_c], array[v_b], 'ORÇ-T' || upper(pg_temp._letras(6)), pg_temp._id('admin')));
  select quote_status into v_sit_depois_da_recusa from public.service_orders where id = v_b;
  select count(*) into v_audit_depois_da_recusa from public.audit_log
   where table_name = 'service_orders' and record_id = v_b and action = 'update' and new_value ->> 'quote_status' = 'draft';

  -- sucesso: a + b, reabrindo b
  r := public._agrupar_orcamentos_reabrindo(array[v_a, v_b], array[v_b], null, 'ORÇ-T' || upper(pg_temp._letras(6)),
                                            pg_temp._id('admin'), null);
  v_novo := (r ->> 'service_order_id')::uuid;

  v_falhas := concat_ws(', ',
    pg_temp._se(v_erro_fora like '22023 %entre os escolhidos%', 'reabrir fora dos escolhidos: ' || coalesce(v_erro_fora, 'PASSOU')),
    pg_temp._se(v_erro_nao_rep like '22023 %Reprovado%', 'reabrir quem não é reprovado: ' || coalesce(v_erro_nao_rep, 'PASSOU')),
    pg_temp._se(v_erro_vinculo like '22023 %ligado a%', 'recusa do agrupar: ' || coalesce(v_erro_vinculo, 'PASSOU')),
    pg_temp._se(v_sit_depois_da_recusa = 'rejected' and v_audit_depois_da_recusa = 0, 'a recusa deixou o reprovado reaberto'),
    pg_temp._se(r -> 'reabertos' = jsonb_build_array(pg_temp._numero(v_b)), 'reabertos'),
    pg_temp._se((select so.status = 'cancelled' and so.merged_into_id = v_novo from public.service_orders so where so.id = v_b),
                'o reaberto entrou no agrupamento'),
    pg_temp._se((select x.quote_status_antes from public.orcamento_agrupamento_origens x
                  where x.agrupamento_id = (r ->> 'agrupamento_id')::uuid and x.origem_id = v_b) = 'rejected'
                and (select x.quote_status_antes from public.orcamento_agrupamento_origens x
                      where x.agrupamento_id = (r ->> 'agrupamento_id')::uuid and x.origem_id = v_a) = 'draft',
                'o histórico guarda Reprovado (e Em elaboração para o outro)'),
    pg_temp._se((select count(*) from public.audit_log a
                  where a.table_name = 'service_orders' and a.record_id = v_b and a.action = 'update'
                    and a.previous_value ->> 'quote_status' = 'rejected' and a.new_value ->> 'quote_status' = 'draft') = 1,
                'auditoria rejected -> draft'));

  -- desagrupar devolve o reaberto como Reprovado
  perform public._desagrupar_orcamentos_desfazer(v_novo, pg_temp._id('admin'));
  v_falhas := concat_ws(', ', nullif(v_falhas, ''),
    pg_temp._se((select so.status = 'draft' and so.quote_status = 'rejected' and so.merged_into_id is null
                   from public.service_orders so where so.id = v_b), 'desagrupado não voltou como Reprovado'),
    pg_temp._se((select so.status = 'draft' and so.quote_status = 'draft' from public.service_orders so where so.id = v_a),
                'o outro não voltou como Em elaboração'));
  insert into _resultado values ('G9 agrupar reabrindo: recusas, atomicidade, reprovado entra só no "sim", histórico e desagrupar devolvem Reprovado',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas || ' | ' || coalesce(r::text, '-') end);
exception when others then
  insert into _resultado values ('G9 agrupar reabrindo: recusas, atomicidade, reprovado entra só no "sim", histórico e desagrupar devolvem Reprovado',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
