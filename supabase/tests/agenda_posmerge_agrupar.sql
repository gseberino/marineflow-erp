-- Prova do pós-merge (C) da Agenda de Produção (migration 20261029110000): agrupar e desagrupar OS conhecendo a agenda.
-- bancada: depende de 20261029110000
--
-- Sobre a carteira de 23/10 (scripts/bancada-agenda/fixture-2310.sql: o Nelson, o Veleiro, o Roberto, o João e o Mickael), com
-- duas OS novas do Nelson montadas aqui — OS-99001 (aprovada; a peça a caminho com previsão, meia diária publicada e outra
-- fixada pelo cliente, a data dita ao cliente em 05/11 e a 1ª em 02/11, um rascunho aberto) e OS-99002 (agendada; uma linha
-- de material do dono e uma de texto livre comprada, um meio-dia publicado, um plano aberto que conta com ela, a data dita
-- em 10/11 e uma mensagem ao cliente esperando a hora) — e a OS-99003 (com o dia 26/10 anotado como feito):
--   C  as cópias: sem os blocos "-- PÓS-MERGE: (C)", cada uma das 5 recriadas é o corpo da fonte (o desagrupar com a troca
--      declarada: a linha do status sai do UPDATE das origens) — sempre que a bancada passa as fontes como texto
--   M  o material das origens passa à nova, com a peça/serviço copiado e as previsões e o original como estavam
--   P  o plano: os meios-dias vigentes das origens saem com os_saiu (o fixado também), com a ação 'cancelar' de origem
--      sistema; o plano aberto que contava com elas fica obsoleto; o rascunho aberto, descartado
--   D  a data dita ao cliente passa à nova (a mais cedo, com a 1ª data dita); os avisos dizem as três coisas
--   X  a mensagem ao cliente que esperava a hora não sai para a OS cancelada (a revalidação devolve 'status')
--   I  o dia anotado como feito recusa o agrupar (e o desagrupar) como execução; a data dita DEPOIS de agrupar recusa o
--      desagrupar
--   U  o desagrupar: o status de antes volta pela porta (via desagrupar, ação 'status'), o material volta às origens e à
--      peça/serviço de antes, a agrupada sai do plano
--   G  a via desagrupar da porta só vale de dentro do desagrupar (sem a chave: 42501); com a chave, só para status de antes
--      de começar; as funções novas sem grant
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261029110000
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono (cria OS de teste e termina em ROLLBACK):
--     npx supabase db query --linked -f supabase/tests/agenda_posmerge_agrupar.sql
--   Sem as fontes como texto (produção), as cópias saem PULADO. Sem a fixture (o Nelson e o Roberto), os cenários quebram.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';
select set_config('agenda.hoje', '2026-10-27', true);

create function pg_temp.ok(p_nome text, p_ok boolean, p_detalhe text default null) returns void language sql as $f$
  insert into _resultado values (p_nome, coalesce(p_ok, false), case when not coalesce(p_ok, false) then p_detalhe end)
$f$;

-- As linhas fora dos blocos "-- PÓS-MERGE: (C) … -- PÓS-MERGE: fim".
create function pg_temp.sem_blocos(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(p, E'\n') loop
    if not v_dentro and ltrim(l) like '-- PÓS-MERGE: (C)%' then v_dentro := true; continue; end if;
    if v_dentro then
      if ltrim(l) like '-- PÓS-MERGE: fim%' then v_dentro := false; end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;

-- O corpo (o que fica entre as duas marcas $…$) da função p_nome na migration p_mig.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
  v_i int := position('create or replace function public.' || p_nome || '(' in v);
  v_tag text;
begin
  if v_i = 0 then return null; end if;
  v := substr(v, v_i);
  v_tag := substring(v from E'\nas (\\$[a-z_]*\\$)\n');
  v := substr(v, position(E'\nas ' || v_tag in v) + length(E'\nas ' || v_tag));
  return left(v, position(v_tag in v) - 1);
end $f$;

-- ── C. As cópias ─────────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  v_porta text := current_setting('agenda_teste.mig_levantamento_fase3', true);
  v_agr   text := current_setting('agenda_teste.mig_agrupar_os', true);
  v_nome  text;
  v_fonte text;
  v_novo  text;
begin
  if coalesce(v_porta, '') = '' or coalesce(v_agr, '') = '' then
    insert into _resultado values ('C0 as cópias só mudam nos blocos "-- PÓS-MERGE: (C)"', true,
      'PULADO: sem agenda_teste.mig_levantamento_fase3/mig_agrupar_os (rode pela bancada)');
    return;
  end if;
  foreach v_nome in array array['os_transicionar_status', '_os_impedimento_para_agrupar', '_os_impedimento_para_desagrupar',
                                '_agrupar_os_montar', '_desagrupar_os_desfazer'] loop
    v_fonte := pg_temp.corpo(case when v_nome = 'os_transicionar_status' then v_porta else v_agr end, v_nome);
    if v_nome = '_desagrupar_os_desfazer' then
      v_fonte := replace(v_fonte,
        E'       set status = coalesce(o.status_antes, ''approved''),\n           quote_status = o.quote_status_antes,',
        E'       set\n           quote_status = o.quote_status_antes,');
    end if;
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = v_nome;
    perform pg_temp.ok(format('C1 %s: sem os blocos "-- PÓS-MERGE: (C)", é o corpo da fonte (com pelo menos um bloco)', v_nome),
      v_fonte is not null and position('-- PÓS-MERGE: (C)' in v_novo) > 0 and pg_temp.sem_blocos(v_novo) = v_fonte,
      format('fonte %s × novo sem blocos %s caracteres', length(v_fonte), length(pg_temp.sem_blocos(v_novo))));
  end loop;
end
$copia$;

-- ── Os cenários (um bloco só) ─────────────────────────────────────────────────────────────────────────────
do $cenarios$
declare
  c_admin  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_nelson constant uuid := 'c1000000-0000-4000-8000-000000000005';
  c_veleiro constant uuid := 'f1000000-0000-4000-8000-000000000005';
  c_rob    constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao   constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_mic    constant uuid := 'bb000000-0000-4000-8000-000000000004';
  c_a      constant uuid := 'a9000000-0000-4000-8000-000000000001';
  c_b      constant uuid := 'a9000000-0000-4000-8000-000000000002';
  c_c      constant uuid := 'a9000000-0000-4000-8000-000000000003';
  c_srv    constant uuid := '5e000000-0000-4000-8000-000000000010';
  c_bat    constant uuid := 'b1000000-0000-4000-8000-000000000011';
  c_disj   constant uuid := 'b1000000-0000-4000-8000-000000000013';
  v_peca_a uuid;
  v_serv_b uuid;
  v_mat_peca uuid;
  v_mat_livre uuid;
  v_mat_dono uuid;
  v_aloc uuid[];
  v_prop uuid;
  v_rasc uuid;
  v_msg  uuid;
  v_r    jsonb;
  v_novo uuid;
  v_novo2 uuid;
  v_txt  text;
  v_n    int;
  m      record;
  p      record;
begin
  -- ── o cenário ──
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                     converted_to_os_at, created_at)
  values (c_a, 'OS-99001', c_nelson, c_veleiro, 'approved', 'approved', 'repair', '2026-10-20 12:00-03', '2026-10-20 12:00-03'),
         (c_b, 'OS-99002', c_nelson, c_veleiro, 'scheduled', 'approved', 'repair', '2026-10-21 12:00-03', '2026-10-21 12:00-03'),
         (c_c, 'OS-99003', c_nelson, c_veleiro, 'approved', 'approved', 'repair', '2026-10-22 12:00-03', '2026-10-22 12:00-03');
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total)
  values (c_a, c_srv, 'Serviço elétrico', 'unit', 1, 320, 320), (c_c, c_srv, 'Serviço elétrico', 'unit', 1, 320, 320);
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total)
  values (c_b, c_srv, 'Troca dos terminais da bateria', 'unit', 1, 320, 320) returning id into v_serv_b;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (c_a, c_bat, 1, 2000, 3200, 2000, 3200) returning id into v_peca_a;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (c_b, c_disj, 2, 250, 420.36, 500, 840.72);
  perform public.recalc_so_totals(c_a);
  perform public.recalc_so_totals(c_b);
  perform public.recalc_so_totals(c_c);

  -- material: a peça da OS-99001 a caminho (previsão 05/11 do fornecedor: vira o original); na OS-99002, o que o dono disse
  -- (terminal, falta) e o texto livre do serviço, comprado
  insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria, situacao,
                                  fonte, comprado_em, previsao_ate, previsao_fonte)
  values (c_a, v_peca_a, 'peca', 'Bateria de lítio 12V 100Ah', 1, 'a_caminho', 'fornecedor', '2026-10-24', '2026-11-05', 'fornecedor')
  returning id into v_mat_peca;
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao, fonte)
  values (c_b, 'dono', 'Terminal 50mm', 4, 'falta', 'dono') returning id into v_mat_dono;
  insert into public.os_material (service_order_id, service_order_service_id, origem, descricao, quantidade_necessaria, situacao,
                                  fonte, comprado_em)
  values (c_b, v_serv_b, 'texto_livre', 'Terminais da bateria', 1, 'comprado', 'dono', '2026-10-26') returning id into v_mat_livre;

  -- o plano: OS-99001 ter 03/11 com o Roberto (manhã publicada, tarde fixada pelo cliente); OS-99002 qua 04/11 com o João;
  -- a OS-99003 com o dia 26/10 anotado como feito
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, fixado_por)
  values (c_a, c_rob, '2026-11-03', 'manha', 'publicada', null), (c_a, c_rob, '2026-11-03', 'tarde', 'fixada', 'cliente_confirmou'),
         (c_b, c_joao, '2026-11-04', 'manha', 'publicada', null);
  select array_agg(a.id order by a.dia, a.turno) into v_aloc from public.agenda_alocacoes a where a.service_order_id in (c_a, c_b);
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, resultado, resultado_via)
  values (c_c, c_mic, '2026-10-26', 'manha', 'publicada', 'cumprido', 'dia_feito');
  -- um plano aberto (em teste) que conta com a OS-99002, com o Mickael na qui 05/11
  insert into public.agenda_propostas (escopo, periodo, os_alvo, versao_base, modo, itens, parametros, criada_por, expira_em)
  values ('os', daterange('2026-11-02', '2026-11-07'), array[c_b], (public._agenda_cfg()).versao_plano, 'sombra',
          jsonb_build_array(jsonb_build_object('op', 'criar', 'os', c_b)), jsonb_build_object('p_hoje', '2026-10-27'), 'motor',
          now() + interval '1 day')
  returning id into v_prop;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, proposta_id)
  values (c_b, c_mic, '2026-11-05', 'manha', 'proposta', v_prop);
  -- o rascunho aberto do dono sobre a OS-99001
  insert into public.agenda_rascunho (autor, canal, tipo, chave, service_order_id, dados, texto, expira_em)
  values (c_admin, 'whatsapp', 'material', 'material:teste', c_a, '{}'::jsonb, 'chegou a bateria', now() + interval '1 day')
  returning id into v_rasc;
  -- a data dita ao cliente: na OS-99001 a 1ª foi 02/11 e a de agora é 05/11; na OS-99002, 10/11
  perform public._agenda_cliente_gravar_prometido(c_a, 'firme', null, '2026-11-02', 'dono', null, now() - interval '3 days', 'dia 2');
  perform public._agenda_cliente_gravar_prometido(c_a, 'firme', null, '2026-11-05', 'dono', null, now() - interval '2 days', 'dia 5');
  perform public._agenda_cliente_gravar_prometido(c_b, 'firme', null, '2026-11-10', 'dono', null, now() - interval '2 days', 'dia 10');
  -- a véspera ao cliente da OS-99002, esperando a hora (o Nelson com WhatsApp e a conversa sem exigência — d10 com 0 dias —,
  -- para a revalidação chegar ao status da OS)
  update public.clients set whatsapp = '47999887766' where id = c_nelson;
  update public.agenda_config set cliente_conversa_dias = 0;
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, dia_alvo, modo, texto, enviar_em,
                                               valida_ate, aprovacao, dedupe_key)
  values (c_nelson, c_b, 'vespera', 'rodada', '2026-11-04', 'sombra', 'Amanhã cedo o Gustavo vai ao Veleiro.',
          '2026-11-03 10:00-03', '2026-11-03 18:00-03', 'livre', 'teste:posmerge:vespera')
  returning id into v_msg;

  -- I1: o dia feito na agenda recusa o agrupar (a mesma frase da execução)
  v_txt := public._os_impedimento_para_agrupar(c_c);
  perform pg_temp.ok('I1 o dia anotado como feito na agenda recusa o agrupar como execução, com a frase do agrupar',
    v_txt like 'OS-99003 já começou a ser executada (dia anotado como feito na agenda (seg 26/10)). Agrupar só junta OS%', v_txt);
  perform pg_temp.ok('I2 as duas OS do cenário podem ser agrupadas',
    public._os_impedimento_para_agrupar(c_a) is null and public._os_impedimento_para_agrupar(c_b) is null,
    concat_ws(' | ', public._os_impedimento_para_agrupar(c_a), public._os_impedimento_para_agrupar(c_b)));

  -- ── o agrupar ──
  v_r := public._agrupar_os_montar(array[c_a, c_b], c_a, 'OS-99010', c_admin, null);
  v_novo := (v_r ->> 'service_order_id')::uuid;

  -- M: o material
  select count(*) into v_n from public.os_material x where x.service_order_id in (c_a, c_b);
  perform pg_temp.ok('M1 nenhuma linha de material ficou nas originais; as 3 estão na nova', v_n = 0
    and (select count(*) from public.os_material x where x.service_order_id = v_novo) = 3, format('%s nas originais', v_n));
  select x.*, sp.service_order_id as os_da_peca, sp.product_id as produto into m
    from public.os_material x join public.service_order_parts sp on sp.id = x.service_order_part_id where x.id = v_mat_peca;
  perform pg_temp.ok('M2 a peça a caminho aponta para a peça COPIADA na nova (o mesmo produto), não para a da origem',
    m.os_da_peca = v_novo and m.produto = c_bat and m.service_order_part_id <> v_peca_a, to_jsonb(m)::text);
  perform pg_temp.ok('M3 a situação, o fornecedor, a previsão e o original ficam como estavam',
    m.situacao = 'a_caminho' and m.fonte = 'fornecedor' and m.previsao_ate = date '2026-11-05'
    and m.previsao_original = date '2026-11-05' and m.comprado_em = date '2026-10-24', to_jsonb(m)::text);
  select x.*, ss.service_order_id as os_do_servico, ss.name_snapshot into m
    from public.os_material x join public.service_order_services ss on ss.id = x.service_order_service_id where x.id = v_mat_livre;
  perform pg_temp.ok('M4 o texto livre aponta para o serviço copiado na nova, comprado como estava',
    m.os_do_servico = v_novo and m.name_snapshot = 'Troca dos terminais da bateria' and m.situacao = 'comprado', to_jsonb(m)::text);
  perform pg_temp.ok('M5 o que o dono disse (sem vínculo) vai junto, em falta',
    (select x.service_order_id = v_novo and x.situacao = 'falta' from public.os_material x where x.id = v_mat_dono));
  perform pg_temp.ok('M6 cada coluna mudada fica em os_agrupamento_movidos (3 OS + 1 peça + 1 serviço) para o desagrupar',
    (select count(*) filter (where x.coluna = 'service_order_id') = 3 and count(*) filter (where x.coluna = 'service_order_part_id'
            and x.valor_antes = v_peca_a) = 1 and count(*) filter (where x.coluna = 'service_order_service_id'
            and x.valor_antes = v_serv_b) = 1
       from public.os_agrupamento_movidos x where x.tabela = 'os_material'));

  -- P: o plano
  perform pg_temp.ok('P1 os 3 meios-dias das originais saíram com os_saiu (o fixado pelo cliente também)',
    (select bool_and(a.estado = 'cancelada' and a.cancelada_motivo = 'os_saiu') and count(*) = 3
       from public.agenda_alocacoes a where a.id = any (v_aloc)));
  perform pg_temp.ok('P2 o dia feito da OS-99003 não foi tocado',
    (select a.estado = 'publicada' and a.resultado = 'cumprido' from public.agenda_alocacoes a where a.service_order_id = c_c));
  select string_agg(e.texto, ' || ' order by e.service_order_id) as textos, count(*) as n,
         bool_and(e.tipo = 'cancelar' and e.origem = 'sistema' and e.executada and e.motivo = 'os_saiu' and v_novo = any (e.os_ids)) as certo
    into p from public.agenda_acoes e where e.service_order_id in (c_a, c_b) and e.tipo = 'cancelar';
  perform pg_temp.ok('P3 uma ação cancelar (sistema) por origem, com os dias e a nova',
    p.n = 2 and p.certo and p.textos like 'Tirei do plano a OS-99001, agrupada na OS-99010: saíram ter 03/11. A OS-99010 entra no próximo planejamento.%'
    and p.textos like '%Tirei do plano a OS-99002, agrupada na OS-99010: saíram qua 04/11.%', p.textos);
  perform pg_temp.ok('P4 o plano aberto que contava com a OS-99002 ficou obsoleto e o meio-dia dele saiu',
    (select x.estado = 'obsoleta' and x.motivo_fim = 'a agenda mudou' from public.agenda_propostas x where x.id = v_prop)
    and not exists (select 1 from public.agenda_alocacoes a where a.proposta_id = v_prop));
  perform pg_temp.ok('P5 o rascunho aberto da OS-99001 ficou descartado',
    (select r.estado = 'descartado' from public.agenda_rascunho r where r.id = v_rasc));
  perform pg_temp.ok('P6 os_saiu não conta contra a capacidade do dono (ela só lê o cancelado por dono ou pessoa)',
    not exists (select 1 from public.agenda_alocacoes a where a.id = any (v_aloc) and a.cancelada_motivo in ('dono', 'pessoa')));

  -- D: a data dita ao cliente
  select x.* into p from public.os_planejamento x where x.service_order_id = v_novo;
  perform pg_temp.ok('D1 a nova ficou com a data dita mais cedo (05/11, da OS-99001), firme, da fonte dono, com a 1ª data (02/11)',
    p.prometido_tipo = 'firme' and p.prometido_ate = date '2026-11-05' and p.prometido_fonte = 'dono'
    and p.prometido_original_ate = date '2026-11-02' and p.prometido_primeiro_ate = date '2026-11-02', to_jsonb(p)::text);
  perform pg_temp.ok('D2 o histórico da nova diz de onde veio a data',
    (p.historico -> -1 ->> 'trecho') = 'Veio da OS-99001, agrupada na OS-99010.', (p.historico -> -1)::text);
  perform pg_temp.ok('D3 as originais guardam a delas (o desagrupar precisa)',
    (select x.prometido_ate = date '2026-11-05' from public.os_planejamento x where x.service_order_id = c_a)
    and (select x.prometido_ate = date '2026-11-10' from public.os_planejamento x where x.service_order_id = c_b));
  v_txt := (v_r -> 'avisos')::text;
  perform pg_temp.ok('D4 os avisos do agrupar dizem o material, os dias que saíram e a data dita',
    v_txt like '%O material das originais (3 linha(s): o que falta, o que está a caminho e as previsões) passou para a OS-99010.%'
    and v_txt like '%Saíram do plano da agenda os dias de OS-99001 (ter 03/11), OS-99002 (qua 04/11); a OS-99010 entra no próximo planejamento.%'
    and v_txt like '%A data dita ao cliente na OS-99001 (qui 05/11) passou para a OS-99010%', v_txt);

  -- X: a mensagem ao cliente que esperava não sai para a OS cancelada
  perform pg_temp.ok('X1 a véspera da OS-99002 não sai: a revalidação do envio devolve status (OS cancelada)',
    public._agenda_cliente_revalidar(v_msg, timestamptz '2026-11-03 10:00-03') = 'status',
    public._agenda_cliente_revalidar(v_msg, timestamptz '2026-11-03 10:00-03'));

  -- I3: logo depois de agrupar, desagrupar pode (a data que passou não é "depois de agrupar")
  perform pg_temp.ok('I3 a data dita que o agrupar passou não impede o desagrupar', public._os_impedimento_para_desagrupar(v_novo) is null,
    public._os_impedimento_para_desagrupar(v_novo));

  -- a nova entrou no plano (um meio-dia publicado do Roberto na qui 05/11), para o desagrupar tirar
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (v_novo, c_rob, '2026-11-05', 'manha', 'publicada');

  -- G1: a via desagrupar da porta sem a chave
  begin
    v_r := public.os_transicionar_status(c_a, 'approved', 'desagrupar', null, c_admin);
    perform pg_temp.ok('G1 sem a chave do desagrupar, a porta recusa tirar a OS de cancelada (42501)', false, v_r::text);
  exception when others then
    perform pg_temp.ok('G1 sem a chave do desagrupar, a porta recusa tirar a OS de cancelada (42501)',
      sqlstate = '42501' and sqlerrm = 'Uma OS cancelada só volta pelo "Desagrupar" da OS agrupada.', sqlstate || ' ' || sqlerrm);
  end;
  -- G2: com a chave, só para um status de antes de começar
  perform set_config('marineflow.desagrupar_os', c_a::text, true);
  v_r := public.os_transicionar_status(c_a, 'completed', 'desagrupar', null, c_admin);
  perform set_config('marineflow.desagrupar_os', '', true);
  perform pg_temp.ok('G2 com a chave, concluir pela via desagrupar é recusado e nada muda',
    v_r ->> 'ok' = 'false' and (select so.status = 'cancelled' from public.service_orders so where so.id = c_a), v_r::text);

  -- ── o desagrupar ──
  v_r := public._desagrupar_os_desfazer(v_novo, c_admin);
  perform pg_temp.ok('U1 as originais voltaram ao status de antes (aprovada e agendada), fora do agrupamento',
    (select so.status = 'approved' and so.merged_into_id is null from public.service_orders so where so.id = c_a)
    and (select so.status = 'scheduled' and so.merged_into_id is null from public.service_orders so where so.id = c_b));
  perform pg_temp.ok('U2 o status voltou pela porta: uma ação status (cancelada → antes, via desagrupar) por origem',
    (select count(*) = 2 and bool_and(e.status_antes = 'cancelled' and e.depois ->> 'via' = 'desagrupar' and e.origem = 'sistema'
                                    and e.autor = c_admin)
       from public.agenda_acoes e where e.service_order_id in (c_a, c_b) and e.tipo = 'status')
    and (select e.status_depois from public.agenda_acoes e where e.service_order_id = c_b and e.tipo = 'status') = 'scheduled');
  perform pg_temp.ok('U3 o material voltou às originais e à peça/serviço de antes; nada ficou na agrupada',
    (select x.service_order_id = c_a and x.service_order_part_id = v_peca_a and x.situacao = 'a_caminho'
            and x.previsao_original = date '2026-11-05' from public.os_material x where x.id = v_mat_peca)
    and (select x.service_order_id = c_b and x.service_order_service_id = v_serv_b from public.os_material x where x.id = v_mat_livre)
    and (select x.service_order_id = c_b from public.os_material x where x.id = v_mat_dono)
    and not exists (select 1 from public.os_material x where x.service_order_id = v_novo));
  perform pg_temp.ok('U4 a agrupada saiu do plano (os_saiu) com a ação cancelar dela',
    (select a.estado = 'cancelada' and a.cancelada_motivo = 'os_saiu' from public.agenda_alocacoes a where a.service_order_id = v_novo)
    and exists (select 1 from public.agenda_acoes e where e.service_order_id = v_novo and e.tipo = 'cancelar'
                  and e.texto like 'Tirei do plano a OS-99010, desagrupada (voltaram a valer OS-99001, OS-99002): saíram qui 05/11.%'));

  -- I4/I5: agrupar de novo; a data dita DEPOIS de agrupar recusa o desagrupar; o dia feito na agrupada também
  v_r := public._agrupar_os_montar(array[c_a, c_b], c_a, 'OS-99011', c_admin, null);
  v_novo2 := (v_r ->> 'service_order_id')::uuid;
  perform public._agenda_cliente_gravar_prometido(v_novo2, 'firme', null, '2026-11-12', 'dono', null, now() + interval '1 minute', 'dia 12');
  v_txt := public._os_impedimento_para_desagrupar(v_novo2);
  perform pg_temp.ok('I4 a data dita ao cliente DEPOIS de agrupar recusa o desagrupar, com a frase',
    v_txt = 'OS-99011 tem data dita ao cliente depois de agrupar (qui 12/11): desagrupar a deixaria numa OS cancelada e o cliente ficaria sem ela. Mantenha a OS-99011 agrupada.', v_txt);
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, resultado, resultado_via)
  values (v_novo2, c_mic, '2026-10-27', 'manha', 'publicada', 'cumprido', 'dia_feito');
  v_txt := public._os_impedimento_para_desagrupar(v_novo2);
  perform pg_temp.ok('I5 o dia anotado como feito na agrupada recusa o desagrupar como execução',
    v_txt = 'OS-99011 já começou a ser executada (dia anotado como feito na agenda (ter 27/10)): não dá mais para desagrupar. As originais ficam como histórico.', v_txt);
  begin
    v_r := public._desagrupar_os_desfazer(v_novo2, c_admin);
    perform pg_temp.ok('I6 o desagrupar recusado não desfaz nada', false, v_r::text);
  exception when others then
    perform pg_temp.ok('I6 o desagrupar recusado não desfaz nada',
      sqlerrm like 'OS-99011 já começou a ser executada%'
      and (select so.status = 'cancelled' and so.merged_into_id = v_novo2 from public.service_orders so where so.id = c_a), sqlerrm);
  end;
end
$cenarios$;

-- ── G. Portas ──────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.ok('G3 as 4 funções novas sem grant a ninguém (só as definer chamam), definer com search_path fixo',
  (select bool_and(not has_function_privilege(papel, f::regprocedure, 'execute'))
     from unnest(array['public._os_agenda_execucao(uuid)', 'public._agenda_os_saiu_por_agrupar(uuid, uuid, text, uuid)',
                       'public._agrupar_os_agenda(uuid, uuid[], uuid, uuid, text, jsonb, jsonb, uuid)',
                       'public._os_porta_desagrupar(uuid, text, uuid, date, timestamptz)']) f,
          unnest(array['anon', 'authenticated']) papel)
  and (select count(*) = 4 and bool_and(p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=%')
         from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('_os_agenda_execucao', '_agenda_os_saiu_por_agrupar', '_agrupar_os_agenda', '_os_porta_desagrupar')));
select pg_temp.ok('G4 a porta continua uma só (9 argumentos), para authenticated e service_role e nunca anon; o montar e o desfazer só service_role',
  (select count(*) = 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'os_transicionar_status')
  and has_function_privilege('authenticated', 'public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public._agrupar_os_montar(uuid[], uuid, text, uuid, numeric)', 'execute')
  and has_function_privilege('service_role', 'public._agrupar_os_montar(uuid[], uuid, text, uuid, numeric)', 'execute')
  and not has_function_privilege('authenticated', 'public._desagrupar_os_desfazer(uuid, uuid)', 'execute')
  and has_function_privilege('service_role', 'public._desagrupar_os_desfazer(uuid, uuid)', 'execute'));

select teste, ok, detalhe from _resultado order by teste;

rollback;
