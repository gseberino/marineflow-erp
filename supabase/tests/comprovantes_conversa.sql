-- Prova: a conversa dos comprovantes (migration 20261011202000; usa 20261011201000 e 20261011203000).
--
--   T7  entrar na fila pré-preenche pela legenda ("empresa", "cupom OS N", nome do barco) e só
--       confirma sozinho o valor de selo alta/média
--   T8  ordem dos passos: débito + legenda com a OS → só "cobrar" e "confirmar"
--   T9  vigia: pausa do "sair", horário, conversa em andamento, espaçamento de 4 h e limite de 3
--   T10 "ok" no confirmar devolve ok_nao_aprova e nada é gravado; "1" no confirmar também não aprova
--   T11 sim com versão velha devolve resumo (versao_mudou); sim na versão certa grava
--   T12 comandos: pular, sair, lote antigo, cmp N (fila e cartão), feito, corrigir
--   T13 comprovantes_consultar e comprovantes_parecidos vazios para quem não é admin, cheios para o admin
--   (revisão de 11/10/2026)
--   T14 resposta mandada antes da pergunta (ou sem o envio confirmado) não vale; a pergunta é reapresentada
--   T15 corrigir: "corrigir cmp N …", o "qual?" logo depois de gravar, o que mudou, a categoria
--   T16 menus por contexto (corrigir, "a empresa" pela forma, a categoria do destino primeiro)
--   T17 nome do barco: palavra inteira com enchimento, OS concluída, recado que não é nome
--   T18 conversa desligada: sem "abertos" nas travas, sem BrasilAPI, a fila volta a ser da F1
--   T19 o CPF do MEI nunca fica no nome do fornecedor
--   T20 o texto solto depois da foto vira dica do CMP
--   T21 a abertura pergunta o CMP que chegou e conta o lote (os antigos à parte)
--   T22 comprovantes_ja_lancados: o financeiro sabe que já foi lançado, sem ver o CMP
--   T23 Dropbox: o fim de um "mover" velho não apaga o "cancelar" pedido no meio
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado P3 da spec da F2; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/comprovantes_conversa.sql --output json
--
-- Seguro em produção: cria um dono de teste (admin com created_at em 2000, que vira o
-- _comprovante_dono() só dentro da transação), OS/barcos/clientes de mentira, liga a conversa só
-- dentro da transação e termina em ROLLBACK. O T11 grava pela rota real (custo da HBR numa OS de
-- teste + anotação antes do banco com valor aleatório): tudo some no rollback. Sem id nem data fixa.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (dono uuid, phone text) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._telefone() returns text language sql volatile as $$
  select '55000' || lpad((floor(random() * 1000000000))::bigint::text, 9, '0')
$$;

do $$
declare
  v_dono uuid := gen_random_uuid();
  v_phone text := pg_temp._telefone();
begin
  insert into public.app_users (id, full_name, email, role, active, phone_normalized, ai_whatsapp_enabled, created_at)
  values (v_dono, 'Dono de teste F2', 'teste-f2-' || v_dono || '@teste.invalido', 'admin', true, v_phone, true,
          now() - interval '30 years');
  insert into public.app_settings (key, value) values ('comprovante_fluxo', 'dono')
  on conflict (key) do update set value = excluded.value;
  insert into public.app_settings (key, value) values ('comprovante_conversa', 'on')
  on conflict (key) do update set value = excluded.value;
  insert into _ctx values (v_dono, v_phone);
end $$;

create function pg_temp._dono() returns uuid language sql stable as $$ select dono from _ctx $$;
create function pg_temp._phone() returns text language sql stable as $$ select phone from _ctx $$;
create function pg_temp._hoje() returns date language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;
-- letras aleatórias (nome de barco que não existe em produção)
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;

-- OS de teste com cliente e barco próprios; número OS-9xxxxx livre
create function pg_temp._os(p_status text default 'open', p_barco text default null) returns uuid language plpgsql as $$
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
  insert into public.vessels (client_id, name) values (v_cli, coalesce(p_barco, 'Navio' || pg_temp._letras(8))) returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, invoicing_status,
                                     grand_total, operational_cost_total, labor_cost_total, travel_cost_total, check_out_at)
  values ('OS-' || v_num, v_cli, v_ves, p_status, 'not_invoiced', 0, 0, 0, 0,
          case when p_status in ('completed', 'invoiced') then now() end)
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
                                   data_compra, data_confianca, forma_pagamento, legenda, dica_da_legenda, lido_em)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(),
          'TESTE-F2-' || gen_random_uuid(), pg_temp._phone(), 'image', coalesce((p->>'recebido_em')::timestamptz, now()),
          md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text),
          coalesce(p->>'tipo', 'nfce'), 'alta', coalesce((p->>'valor')::numeric, round((1000 + random() * 8000)::numeric, 2)),
          coalesce(p->>'selo', 'alta'), coalesce((p->>'data')::date, pg_temp._hoje()), 'alta', p->>'forma',
          p->>'legenda', p->>'dica', now())
  returning id into v;
  return v;
end $$;

-- deixa o telefone livre: fecha a pergunta aberta e tira da fila o que sobrou do teste anterior
create function pg_temp._livrar() returns void language plpgsql as $$
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste'
   where phone_normalized = pg_temp._phone() and status = 'aberta';
  update public.comprovantes set situacao = 'cancelado', motivo_cancelamento = 'dono_cancelou', cancelado_em = now()
   where phone_normalized = pg_temp._phone() and situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
  update public.comprovantes_fila_do_telefone set pausada_ate = null, ultima_pergunta_fechada_em = null
   where phone_normalized = pg_temp._phone();
  -- as mensagens do dono de teste (as respostas simuladas) não contam como conversa em andamento
  delete from public.whatsapp_messages where phone_normalized = pg_temp._phone();
end $$;

-- a mensagem do dono (texto recebido) em p_quando; devolve o id (o que o edge manda ao responder)
create function pg_temp._msg(p_quando timestamptz default null) returns uuid language sql as $$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', pg_temp._phone(), 'text', 'teste', 'TESTE-F2-' || gen_random_uuid(), coalesce(p_quando, now() + interval '10 seconds'))
  returning id
$$;

-- como o edge: a pergunta foi enviada (whatsapp-send confirmou) e o dono respondeu DEPOIS dela
create function pg_temp._responder(p_pergunta jsonb, p_interp jsonb, p_versao integer default null) returns jsonb language plpgsql as $$
begin
  perform public.pergunta_marcar_enviada((p_pergunta->>'pergunta_id')::uuid, 'WA-' || (p_pergunta->>'pergunta_id'));
  return public.comprovante_responder(jsonb_build_object(
    'pergunta_id', p_pergunta->>'pergunta_id', 'message_id', pg_temp._msg(), 'interpretacao', p_interp, 'versao', p_versao));
end $$;

-- ═══ T7 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_barco text := 'Navio' || pg_temp._letras(8);
  v_os_barco uuid := pg_temp._os('in_progress', v_barco);
  v_emp uuid := pg_temp._cmp(jsonb_build_object('legenda', 'empresa almoço'));
  v_cup uuid := pg_temp._cmp(jsonb_build_object('legenda', 'cupom OS ' || pg_temp._os_num(v_os), 'dica', 'cupom OS ' || pg_temp._os_num(v_os)));
  v_bar uuid := pg_temp._cmp(jsonb_build_object('legenda', 'gasolina do ' || v_barco));
  v_baixa uuid := pg_temp._cmp(jsonb_build_object('selo', 'baixa'));
  v_media uuid := pg_temp._cmp(jsonb_build_object('selo', 'media', 'forma', 'pix'));
  v_r jsonb;
  e record; c record; b record; lb record; m record;
begin
  perform pg_temp._livrar();
  v_r := public.comprovante_conversa_entrar(array[v_emp, v_cup, v_bar, v_baixa, v_media]);
  select destino, destino_os_id, situacao into e from public.comprovantes where id = v_emp;
  select destino, destino_os_id into c from public.comprovantes where id = v_cup;
  select destino, destino_os_id into b from public.comprovantes where id = v_bar;
  select valor_confirmado, data_confirmada into lb from public.comprovantes where id = v_baixa;
  select valor_confirmado, valor, forma_confirmada into m from public.comprovantes where id = v_media;
  insert into _resultado values ('T7 entrar pré-preenche pela legenda e confirma só o valor alta/média',
    jsonb_array_length(v_r->'entraram') = 5 and e.situacao = 'aguardando_vez' and e.destino = 'empresa' and e.destino_os_id is null
    and c.destino = 'os' and c.destino_os_id = v_os and b.destino = 'os' and b.destino_os_id = v_os_barco
    and lb.valor_confirmado is null and lb.data_confirmada = pg_temp._hoje()
    and m.valor_confirmado = m.valor and m.forma_confirmada = 'pix'
    -- de novo não entra (já está na fila)
    and jsonb_array_length(public.comprovante_conversa_entrar(array[v_emp])->'entraram') = 0,
    'entraram=' || jsonb_array_length(v_r->'entraram') || ' empresa=' || coalesce(e.destino, '-') || ' cupom=' || coalesce(c.destino, '-')
    || ' barco=' || coalesce(b.destino, '-') || '/' || coalesce((b.destino_os_id = v_os_barco)::text, '-')
    || ' baixa=' || coalesce(lb.valor_confirmado::text, 'null'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T7 entrar pré-preenche pela legenda e confirma só o valor alta/média', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T8 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_cmp uuid := pg_temp._cmp(jsonb_build_object('forma', 'debito', 'legenda', 'OS ' || pg_temp._os_num(v_os), 'dica', 'OS ' || pg_temp._os_num(v_os)));
  v_p jsonb;
  v_r jsonb;
  v_efeitos text;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'abertura', null);
  v_r := pg_temp._responder(v_p, jsonb_build_object('tipo', 'opcao', 'n', 2));
  select string_agg(e->>'tipo', ',' order by o) into v_efeitos
    from jsonb_array_elements(v_r->'proxima'->'plano'->'efeitos') with ordinality as t(e, o);
  insert into _resultado values ('T8 débito + legenda com a OS: só cobrar e confirmar',
    v_p->>'passo' = 'cobrar' and jsonb_array_length(v_p->'opcoes') = 2 and (v_p->'primeira_do_lote'->>'n')::integer = 1
    and v_r->>'resultado' = 'resumo' and v_r->'proxima'->>'passo' = 'confirmar'
    and v_efeitos = 'despesa_os,anotar'
    and (v_r->'proxima'->'plano'->'efeitos'->0->>'billable')::boolean = false
    and (v_r->'proxima'->>'versao')::integer = (select resumo_versao from public.comprovantes where id = v_cmp)
    -- a pasta do barco só com pasta registrada ou pasta-base configurada (senão a do mês): o resumo diz onde vai de fato
    and v_r->'proxima'->>'pasta' like case when public._comprovante_usa_pasta_do_barco(public._comprovante_os_info(v_os))
                                           then '%/1- DOC''s/Compras' else 'COMPROVANTES/%' end
    and (select situacao from public.comprovantes where id = v_cmp) = 'aguardando_sim',
    'passo1=' || coalesce(v_p->>'passo', '-') || ' resultado=' || coalesce(v_r->>'resultado', '-')
    || ' passo2=' || coalesce(v_r->'proxima'->>'passo', '-') || ' efeitos=' || coalesce(v_efeitos, '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T8 débito + legenda com a OS: só cobrar e confirmar', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T9 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_agora timestamp := now() at time zone 'America/Sao_Paulo';
  v_dentro boolean;
  v_cmp uuid := pg_temp._cmp();
  v_pausa jsonb;
  v_pausa_abertura jsonb;
  v_hora jsonb;
  v_andamento jsonb;
  v_lista jsonb;
  v_esp1 uuid;
  v_esp2 uuid;
  v_lim uuid;
  v_adiado uuid;
  v_vigia jsonb;
  v_auto smallint;
  v_detalhe text;
begin
  perform pg_temp._livrar();
  v_dentro := extract(isodow from v_agora) <> 7 and v_agora::time >= time '08:00' and v_agora::time < time '20:00';
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  -- pausa do "sair": o vigia não pergunta e a lista do vigia não traz o telefone; um comprovante
  -- NOVO (abertura) é ação do dono: acaba a pausa e pergunta
  perform public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'sair'));
  v_pausa := public.comprovante_proxima_pergunta(pg_temp._phone(), 'vigia', null);
  v_lista := public.comprovantes_vigia_conversa(10);
  v_pausa_abertura := public.comprovante_proxima_pergunta(pg_temp._phone(), 'abertura', v_cmp);
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now() where phone_normalized = pg_temp._phone() and status = 'aberta';
  update public.comprovantes set situacao = 'aguardando_vez', ultima_pergunta_em = null where id = v_cmp;
  update public.comprovantes_fila_do_telefone set pausada_ate = null where phone_normalized = pg_temp._phone();
  -- horário
  v_hora := public.comprovante_proxima_pergunta(pg_temp._phone(), 'vigia', null);
  if v_hora->>'perguntou' = 'true' then
    update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now() where phone_normalized = pg_temp._phone() and status = 'aberta';
    update public.comprovantes set situacao = 'aguardando_vez' where id = v_cmp;
  end if;
  select perguntas_automaticas into v_auto from public.comprovantes where id = v_cmp;
  -- conversa em andamento (texto do dono há menos de 2 min): a abertura também espera
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', pg_temp._phone(), 'text', 'teste', 'TESTE-F2-' || gen_random_uuid(), now());
  v_andamento := public.comprovante_proxima_pergunta(pg_temp._phone(), 'abertura', null);
  -- espaçamento (4 h) e limite (3), pela escolha do vigia (sem depender da hora do teste)
  update public.comprovantes set perguntas_automaticas = 1 where id = v_cmp;
  insert into public.comprovantes_fila_do_telefone as f (phone_normalized, ultima_pergunta_fechada_em)
  values (pg_temp._phone(), now() - interval '1 hour')
  on conflict (phone_normalized) do update set ultima_pergunta_fechada_em = now() - interval '1 hour';
  v_esp1 := public._comprovante_cmp_da_vigia(pg_temp._phone());
  update public.comprovantes_fila_do_telefone set ultima_pergunta_fechada_em = now() - interval '5 hours'
   where phone_normalized = pg_temp._phone();
  v_esp2 := public._comprovante_cmp_da_vigia(pg_temp._phone());
  -- "pular"/"deixar para depois": o vigia não volta a ele antes do adiamento (4 h)
  update public.comprovantes set perguntas_automaticas = 0, adiado_ate = now() + interval '4 hours' where id = v_cmp;
  v_adiado := public._comprovante_cmp_da_vigia(pg_temp._phone());
  update public.comprovantes set adiado_ate = null where id = v_cmp;
  update public.comprovantes set perguntas_automaticas = 3 where id = v_cmp;
  v_lim := public._comprovante_cmp_da_vigia(pg_temp._phone());
  v_vigia := public.comprovante_proxima_pergunta(pg_temp._phone(), 'vigia', null);

  v_detalhe := 'dentro=' || v_dentro || ' pausa=' || coalesce(v_pausa->>'motivo', '-') || '/' || coalesce(v_pausa_abertura->>'motivo', v_pausa_abertura->>'perguntou')
    || ' hora=' || coalesce(v_hora->>'motivo', v_hora->>'perguntou') || ' auto=' || v_auto
    || ' andamento=' || coalesce(v_andamento->>'motivo', '-') || ' esp=' || (v_esp1 is null) || '/' || (v_esp2 = v_cmp)
    || ' limite=' || (v_lim is null) || ' adiado=' || (v_adiado is null) || ' vigia=' || coalesce(v_vigia->>'motivo', '-');
  insert into _resultado values ('T9 vigia: pausa, horário, conversa em andamento, espaçamento de 4 h, adiamento e limite de 3',
    v_pausa->>'motivo' = 'pausada' and v_pausa_abertura->>'perguntou' = 'true'
    and not (v_lista->'perguntar' @> to_jsonb(pg_temp._phone()))
    and case when v_dentro then v_hora->>'perguntou' = 'true' and v_auto = 1
             else v_hora->>'motivo' = 'fora_do_horario' and v_auto = 0 end
    and v_andamento->>'motivo' = 'conversa_em_andamento'
    and v_esp1 is null and v_esp2 = v_cmp and v_lim is null and v_adiado is null
    and v_vigia->>'motivo' = case when v_dentro then 'conversa_em_andamento' else 'fora_do_horario' end,
    v_detalhe);
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T9 vigia: pausa, horário, conversa em andamento, espaçamento de 4 h e limite de 3', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T10 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_cmp uuid := pg_temp._cmp(jsonb_build_object('forma', 'debito'));
  v_p jsonb;
  v_ok jsonb;
  v_um jsonb;
  v_desp integer;
  v_anot integer;
begin
  perform pg_temp._livrar();
  delete from public.whatsapp_messages where phone_normalized = pg_temp._phone();
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  update public.comprovantes set destino = 'os', destino_os_id = v_os, cobrar_cliente = false where id = v_cmp;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  v_ok := pg_temp._responder(v_p, jsonb_build_object('tipo', 'ok'));
  v_um := pg_temp._responder(v_p, jsonb_build_object('tipo', 'opcao', 'n', 1));
  select count(*) into v_desp from public.service_order_expenses where service_order_id = v_os;
  select count(*) into v_anot from public.anotacoes_do_extrato where descricao like (select codigo from public.comprovantes where id = v_cmp) || ' ·%';
  insert into _resultado values ('T10 ok e "1" no confirmar não aprovam; nada é gravado',
    v_p->>'passo' = 'confirmar' and v_ok->>'resultado' = 'ok_nao_aprova' and v_um->>'resultado' = 'invalida'
    and v_desp = 0 and v_anot = 0
    and (select situacao from public.comprovantes where id = v_cmp) = 'aguardando_sim'
    and (select gravado_em from public.comprovantes where id = v_cmp) is null
    and (select status from public.whatsapp_perguntas where id = (v_p->>'pergunta_id')::uuid) = 'aberta',
    'passo=' || coalesce(v_p->>'passo', '-') || ' ok=' || coalesce(v_ok->>'resultado', '-') || ' um=' || coalesce(v_um->>'resultado', '-')
    || ' despesas=' || v_desp || ' anotacoes=' || v_anot);
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T10 ok e "1" no confirmar não aprovam; nada é gravado', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T11 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_cmp uuid := pg_temp._cmp(jsonb_build_object('forma', 'debito'));
  v_p jsonb;
  v_velha jsonb;
  v_sim jsonb;
  v_sit text;
  v_desp record;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  update public.comprovantes set destino = 'os', destino_os_id = v_os, cobrar_cliente = false where id = v_cmp;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  v_velha := pg_temp._responder(v_p, jsonb_build_object('tipo', 'sim'), (v_p->>'versao')::integer - 1);
  v_sim := pg_temp._responder(v_velha->'proxima', jsonb_build_object('tipo', 'sim'));
  select situacao into v_sit from public.comprovantes where id = v_cmp;
  select count(*) as n, bool_and(not billable_to_client) as custo into v_desp
    from public.service_order_expenses where service_order_id = v_os;
  insert into _resultado values ('T11 sim com versão velha mostra o resumo de novo; na versão certa grava',
    v_velha->>'resultado' = 'resumo' and v_velha->>'motivo' = 'versao_mudou' and v_velha->'proxima'->>'passo' = 'confirmar'
    and v_velha->'proxima'->>'pergunta_id' <> v_p->>'pergunta_id'
    and v_sim->>'resultado' = 'gravado' and v_sit = 'gravado' and v_desp.n = 1 and v_desp.custo
    and v_sim->'gravacao'->>'situacao' = 'gravado',
    'velha=' || coalesce(v_velha->>'resultado', '-') || '/' || coalesce(v_velha->>'motivo', '-')
    || ' sim=' || coalesce(v_sim->>'resultado', '-') || ' ' || coalesce(v_sim->>'motivo', '') || ' situacao=' || coalesce(v_sit, '-')
    || ' despesas=' || v_desp.n);
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T11 sim com versão velha mostra o resumo de novo; na versão certa grava', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T12 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_a uuid := pg_temp._cmp();
  v_b uuid := pg_temp._cmp();
  v_velho1 uuid;
  v_velho2 uuid;
  v_p jsonb;
  v_pular jsonb;
  v_sair jsonb;
  v_lote jsonb;
  v_cmp_fila jsonb;
  v_cartao jsonb;
  v_feito jsonb;
  v_corr jsonb;
  v_nao jsonb;
  v_codigo_a text;
  v_num_b integer;
  v_fila_a timestamptz;
  v_fila_b timestamptz;
  v_falhas text[];
  v_pausa timestamptz;
begin
  perform pg_temp._livrar();
  delete from public.whatsapp_messages where phone_normalized = pg_temp._phone();
  perform public.comprovante_conversa_entrar(array[v_a, v_b]);
  select codigo into v_codigo_a from public.comprovantes where id = v_a;
  select numero into v_num_b from public.comprovantes where id = v_b;
  -- pular: o A vai para o fim, a próxima pergunta é do B
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'pendentes', null);
  v_pular := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'pular'));
  select fila_ordem into v_fila_a from public.comprovantes where id = v_a;
  select fila_ordem into v_fila_b from public.comprovantes where id = v_b;
  -- corrigir valor no CMP da pergunta aberta (o B)
  v_corr := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'corrigir', 'campo', 'valor', 'valor', '12.34'));
  -- sair: pausa 12 h
  v_sair := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'sair'));
  select pausada_ate into v_pausa from public.comprovantes_fila_do_telefone where phone_normalized = pg_temp._phone();
  -- lote antigo (ação do dono: limpa a pausa): CMPs lidos que nunca entraram na fila (antigos)
  v_velho1 := pg_temp._cmp(jsonb_build_object('recebido_em', now() - interval '20 days'));
  v_velho2 := pg_temp._cmp(jsonb_build_object('recebido_em', now() - interval '19 days'));
  v_lote := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'lote_antigo'));
  -- cmp N de quem está na fila: vira a pergunta
  v_cmp_fila := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'cmp', 'numero', v_num_b));
  -- cmp N de gravado: cartão; feito tira a pendência
  update public.comprovantes
     set situacao = 'gravado', gravado_em = now(), destino = 'estoque', pendencias = array['dar_entrada'],
         efeitos = '[{"tipo":"pendencia","qual":"dar_entrada"}]'::jsonb
   where id = v_velho1;
  v_cartao := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'cmp',
                'numero', (select numero from public.comprovantes where id = v_velho1)));
  v_feito := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'feito',
                'numero', (select numero from public.comprovantes where id = v_velho1)));
  v_nao := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'cmp', 'numero', 99999999));

  select array_agg(nome) into v_falhas from (values
    ('pular', v_pular->>'resultado' = 'pulado' and v_pular->>'codigo' = v_codigo_a),
    ('pular_proxima_e_o_b', v_pular->'pergunta'->'cmp'->>'id' = v_b::text),
    ('pular_fim_da_fila', v_fila_a > v_fila_b),
    ('corrigir_valor', v_corr->>'resultado' = 'pergunta' and (select valor_confirmado from public.comprovantes where id = v_b) = 12.34),
    ('sair', v_sair->>'resultado' = 'pausado' and (v_sair->>'fila')::integer = 2),
    ('sair_pausa_12h', v_pausa > now() + interval '11 hours'),
    ('acao_do_dono_limpa_a_pausa', (select pausada_ate from public.comprovantes_fila_do_telefone where phone_normalized = pg_temp._phone()) is null),
    ('lote', v_lote->>'resultado' = 'lote' and jsonb_array_length(v_lote->'entraram') = 2 and (v_lote->>'restam')::integer = 0),
    ('lote_pergunta', coalesce(v_lote->'pergunta', 'null'::jsonb) <> 'null'::jsonb),
    ('cmp_da_fila', v_cmp_fila->>'resultado' = 'pergunta' and v_cmp_fila->'pergunta'->'cmp'->>'id' = v_b::text),
    ('cartao', v_cartao->>'resultado' = 'cartao' and v_cartao->'cmp'->>'situacao' = 'gravado'),
    ('feito', v_feito->>'resultado' = 'feito' and v_feito->'resolvidas' = '["dar_entrada"]'::jsonb
              and (select cardinality(pendencias) from public.comprovantes where id = v_velho1) = 0),
    ('nao_existe', v_nao->>'resultado' = 'nao_existe')
  ) as t(nome, ok) where not coalesce(ok, false);
  insert into _resultado values ('T12 comandos: pular, corrigir, sair, lote antigo, cmp N, feito',
    v_falhas is null,
    coalesce('falhou: ' || array_to_string(v_falhas, ', ') || ' | ', '')
    || 'pular=' || coalesce(v_pular->>'resultado', '-') || ' corrigir=' || coalesce(v_corr->>'resultado', '-')
    || ' sair=' || coalesce(v_sair->>'resultado', '-') || '/' || coalesce(v_sair->>'fila', '-')
    || ' lote=' || coalesce(jsonb_array_length(v_lote->'entraram')::text, '-') || '/' || coalesce(v_lote->>'restam', '-')
    || ' cmp=' || coalesce(v_cmp_fila->>'resultado', '-')
    || ' cartao=' || coalesce(v_cartao->>'resultado', '-') || ' feito=' || coalesce(v_feito->>'resolvidas', '-')
    || ' nao=' || coalesce(v_nao->>'resultado', '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T12 comandos: pular, corrigir, sair, lote antigo, cmp N, feito', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T13 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_valor numeric := round((1000 + random() * 8000)::numeric, 2);
  v_cmp uuid := pg_temp._cmp(jsonb_build_object('valor', v_valor));
  v_tec uuid := gen_random_uuid();
  v_tec_c jsonb;
  v_tec_p jsonb;
  v_adm_c jsonb;
  v_adm_p jsonb;
  v_srv_c jsonb;
  v_codigo text;
begin
  select codigo into v_codigo from public.comprovantes where id = v_cmp;
  insert into public.app_users (id, full_name, email, role, active, created_at)
  values (v_tec, 'Técnico de teste F2', 'teste-f2-' || v_tec || '@teste.invalido', 'technician', true, now());
  -- quem não é admin: vazio, nunca erro (pelo painel e pelo autor)
  perform set_config('request.jwt.claim.sub', v_tec::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_tec, 'role', 'authenticated')::text, true);
  v_tec_c := public.comprovantes_consultar(jsonb_build_object('codigo', v_codigo));
  v_tec_p := public.comprovantes_parecidos(v_valor, pg_temp._hoje(), null, null);
  -- o admin logado
  perform set_config('request.jwt.claim.sub', pg_temp._dono()::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp._dono(), 'role', 'authenticated')::text, true);
  v_adm_c := public.comprovantes_consultar(jsonb_build_object('codigo', v_codigo));
  v_adm_p := public.comprovantes_parecidos(v_valor, pg_temp._hoje(), null, null);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  -- pelo servidor (WhatsApp), com o autor
  v_srv_c := public.comprovantes_consultar(jsonb_build_object('numero', (select numero from public.comprovantes where id = v_cmp),
                                                               'autor', pg_temp._dono()));
  insert into _resultado values ('T13 consultar/parecidos: vazios para quem não é admin, cheios para o admin',
    (v_tec_c->>'total')::integer = 0 and jsonb_array_length(v_tec_p->'abertos') = 0
    and (v_adm_c->>'total')::integer = 1 and v_adm_c->'itens'->0->>'codigo' = v_codigo
    and not (v_adm_c->'itens'->0 ? 'leitura') and not (v_adm_c->'itens'->0 ? 'legenda')
    and jsonb_array_length(v_adm_p->'abertos') >= 1 and v_adm_p->'abertos' @> jsonb_build_array(jsonb_build_object('codigo', v_codigo))
    and (v_srv_c->>'total')::integer = 1
    and (public.comprovantes_consultar(jsonb_build_object('codigo', v_codigo, 'autor', v_tec))->>'total')::integer = 0,
    'tecnico=' || (v_tec_c->>'total') || '/' || jsonb_array_length(v_tec_p->'abertos')
    || ' admin=' || (v_adm_c->>'total') || '/' || jsonb_array_length(v_adm_p->'abertos') || ' servidor=' || (v_srv_c->>'total'));
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('T13 consultar/parecidos: vazios para quem não é admin, cheios para o admin', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T14 (revisão de 11/10/2026): só vale a resposta mandada DEPOIS de a pergunta chegar ═══════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_cmp uuid := pg_temp._cmp(jsonb_build_object('forma', 'debito'));
  v_p jsonb;
  v_nao_enviada jsonb;
  v_antes jsonb;
  v_sem_msg jsonb;
  v_ok boolean;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  update public.comprovantes set destino = 'os', destino_os_id = v_os, cobrar_cliente = false where id = v_cmp;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  -- o envio da pergunta ainda não foi confirmado: o "sim" que chegou não é resposta a ela
  v_nao_enviada := public.comprovante_responder(jsonb_build_object('pergunta_id', v_p->>'pergunta_id',
                     'message_id', pg_temp._msg(), 'interpretacao', '{"tipo":"sim"}'::jsonb));
  perform public.pergunta_marcar_enviada((v_p->>'pergunta_id')::uuid, 'WA-T14');
  -- mandado ANTES da pergunta (o "sim" digitado antes de o resumo sair)
  v_antes := public.comprovante_responder(jsonb_build_object('pergunta_id', v_p->>'pergunta_id',
               'message_id', pg_temp._msg(now() - interval '1 minute'), 'interpretacao', '{"tipo":"sim"}'::jsonb));
  -- sem a mensagem, no confirmar, o sim também não vale
  v_sem_msg := public.comprovante_responder(jsonb_build_object('pergunta_id', v_p->>'pergunta_id',
                 'message_id', null, 'interpretacao', '{"tipo":"sim"}'::jsonb));
  v_ok := v_p->>'passo' = 'confirmar'
    and v_nao_enviada->>'resultado' = 'invalida' and v_nao_enviada->>'motivo' = 'resposta_anterior_a_pergunta'
    and v_antes->>'resultado' = 'invalida' and v_antes->>'motivo' = 'resposta_anterior_a_pergunta'
    and v_antes->'proxima'->>'pergunta_id' = v_p->>'pergunta_id'
    and v_sem_msg->>'resultado' = 'invalida' and v_sem_msg->>'motivo' = 'resposta_anterior_a_pergunta'
    and (select situacao from public.comprovantes where id = v_cmp) = 'aguardando_sim'
    and not exists (select 1 from public.service_order_expenses where service_order_id = v_os)
    and (select status from public.whatsapp_perguntas where id = (v_p->>'pergunta_id')::uuid) = 'aberta';
  insert into _resultado values ('T14 resposta de antes da pergunta (ou sem envio confirmado) não grava; a pergunta é reapresentada',
    v_ok, 'nao_enviada=' || coalesce(v_nao_enviada->>'motivo', '-') || ' antes=' || coalesce(v_antes->>'motivo', '-')
    || ' sem_msg=' || coalesce(v_sem_msg->>'motivo', '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T14 resposta de antes da pergunta (ou sem envio confirmado) não grava; a pergunta é reapresentada', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T15: corrigir depois de gravar — o CMP dito, o "qual?" e a categoria ═════════════════════
do $$
declare
  v_a uuid := pg_temp._cmp(jsonb_build_object('forma', 'debito'));
  v_b uuid := pg_temp._cmp(jsonb_build_object('forma', 'debito'));
  v_num_a integer;
  v_num_b integer;
  v_p jsonb;
  v_g jsonb;
  v_qual jsonb;
  v_expl jsonb;
  v_ja jsonb;
  v_cat jsonb;
  v_falhas text[];
  v_b_depois_do_qual numeric;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v_a, v_b]);
  update public.comprovantes set destino = 'empresa', categoria = 'Outras despesas' where id in (v_a, v_b);
  -- tudo aqui roda numa transação (o mesmo now()): os gravados dos testes anteriores ficam para trás
  update public.comprovantes set gravado_em = gravado_em - interval '1 hour'
   where phone_normalized = pg_temp._phone() and gravado_em is not null;
  select numero into v_num_a from public.comprovantes where id = v_a;
  select numero into v_num_b from public.comprovantes where id = v_b;
  update public.comprovantes set fila_ordem = now() + interval '1 day' where id = v_b;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_a);
  v_g := pg_temp._responder(v_p, '{"tipo":"sim"}'::jsonb);
  -- logo depois do "gravado… Próximo:", "corrigir valor 70" sem dizer o CMP: pergunta qual
  v_qual := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'corrigir',
              'campo', 'valor', 'valor', '70.00'));
  select valor_confirmado into v_b_depois_do_qual from public.comprovantes where id = v_b;
  -- dizendo o CMP: corrige ESTE e diz o que mudou
  v_expl := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'corrigir',
              'campo', 'valor', 'valor', '70.00', 'cmp', v_num_b));
  v_ja := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'corrigir',
            'campo', 'valor', 'valor', '71.00', 'cmp', v_num_a));
  v_cat := public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'corrigir',
             'campo', 'categoria', 'categoria', 'alimentacao de campo', 'cmp', v_num_b));
  select array_agg(nome) into v_falhas from (values
    ('gravou_a', v_g->>'resultado' = 'gravado' and v_g->'proxima'->'cmp'->>'id' = v_b::text),
    ('qual', v_qual->>'resultado' = 'qual_cmp' and v_qual->>'gravado' = (select codigo from public.comprovantes where id = v_a)
             and v_qual->>'aberto' = (select codigo from public.comprovantes where id = v_b)),
    ('qual_nao_mudou', v_b_depois_do_qual <> 70),
    ('explicito', v_expl->>'resultado' = 'pergunta' and v_expl->'corrigido'->>'campo' = 'valor'
                  and v_expl->'corrigido'->>'valor' = '70.00' and (select valor_confirmado from public.comprovantes where id = v_b) = 70),
    ('ja_gravado', v_ja->>'resultado' = 'ja_gravado'),
    ('categoria', v_cat->>'resultado' = 'pergunta' and v_cat->'corrigido'->>'valor' = 'Alimentação de campo'
                  and (select categoria from public.comprovantes where id = v_b) = 'Alimentação de campo')
  ) as t(nome, ok) where not coalesce(ok, false);
  insert into _resultado values ('T15 corrigir: o CMP dito, "qual?" logo depois de gravar, o que mudou, a categoria',
    v_falhas is null, coalesce('falhou: ' || array_to_string(v_falhas, ', ') || ' | ', '')
    || 'gravou=' || coalesce(v_g->>'resultado', '-') || ' qual=' || coalesce(v_qual->>'resultado', '-')
    || ' explicito=' || coalesce(v_expl->>'resultado', '-') || ' ja=' || coalesce(v_ja->>'resultado', '-')
    || ' categoria=' || coalesce(v_cat->>'resultado', '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T15 corrigir: o CMP dito, "qual?" logo depois de gravar, o que mudou, a categoria', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T16: os menus mudam com o contexto ══════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_os_cmp uuid := pg_temp._cmp(jsonb_build_object('forma', 'pix'));
  v_pes uuid := pg_temp._cmp(jsonb_build_object('forma', 'pix'));
  v_din uuid := pg_temp._cmp(jsonb_build_object('forma', 'dinheiro'));
  c public.comprovantes;
  v_corr_os text;
  v_corr_pes text;
  v_quem_pix text;
  v_quem_din text;
  v_cat_os text;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v_os_cmp, v_pes, v_din]);
  update public.comprovantes set destino = 'os', destino_os_id = v_os where id in (v_os_cmp, v_din);
  update public.comprovantes set destino = 'pessoal' where id = v_pes;
  select * into c from public.comprovantes where id = v_os_cmp;
  select string_agg(o->>'valor', ',' order by (o->>'n')::int) into v_corr_os from jsonb_array_elements(public._comprovante_opcoes_do_passo(c, 'corrigir')) o;
  select o->>'rotulo' into v_quem_pix from jsonb_array_elements(public._comprovante_opcoes_do_passo(c, 'quem_pagou')) o where o->>'valor' = 'empresa';
  select o->>'rotulo' into v_cat_os from jsonb_array_elements(public._comprovante_opcoes_do_passo(c, 'categoria')) o where (o->>'n')::int = 1;
  select * into c from public.comprovantes where id = v_pes;
  select string_agg(o->>'valor', ',' order by (o->>'n')::int) into v_corr_pes from jsonb_array_elements(public._comprovante_opcoes_do_passo(c, 'corrigir')) o;
  select * into c from public.comprovantes where id = v_din;
  select o->>'rotulo' into v_quem_din from jsonb_array_elements(public._comprovante_opcoes_do_passo(c, 'quem_pagou')) o where o->>'valor' = 'empresa';
  insert into _resultado values ('T16 menus por contexto: corrigir sem "cobrar" fora de OS; "empresa" pela forma; categoria da OS primeiro',
    v_corr_os = 'valor,data,para_que,como_pagou,quem_pagou,cobrar,categoria,cancelar,depois'
    and v_corr_pes = 'valor,data,para_que,cancelar,depois'
    and v_quem_pix = 'A empresa (conta da empresa)' and v_quem_din = 'A empresa (dinheiro do Caixa)'
    and v_cat_os = 'Peças e materiais',
    'os=' || coalesce(v_corr_os, '-') || ' pessoal=' || coalesce(v_corr_pes, '-') || ' quem=' || coalesce(v_quem_pix, '-')
    || '/' || coalesce(v_quem_din, '-') || ' categoria1=' || coalesce(v_cat_os, '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T16 menus por contexto: corrigir sem "cobrar" fora de OS; "empresa" pela forma; categoria da OS primeiro', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T17: o nome do barco — palavra inteira, com enchimento, OS fechada, recado que não é nome ═══
do $$
declare
  v_letras text := pg_temp._letras(7);
  v_barco text := 'Ponta ' || v_letras;
  v_os uuid := pg_temp._os('open', v_barco);
  v_letras_f text := pg_temp._letras(7);
  v_fechada uuid := pg_temp._os('completed', 'Cais ' || v_letras_f);
  v_cmp uuid := pg_temp._cmp(jsonb_build_object('forma', 'pix'));
  v_p jsonb;
  v_r1 jsonb;
  v_r2 jsonb;
  v_r3 jsonb;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  -- recado para o assistente no passo "para quê": não acha (e nada muda)
  v_r1 := pg_temp._responder(v_p, jsonb_build_object('tipo', 'nome', 'texto', 'saldo nubank'));
  -- "do <barco>" (com enchimento e só uma palavra do nome)
  v_r2 := pg_temp._responder(v_p, jsonb_build_object('tipo', 'nome', 'texto', 'do ' || v_letras));
  -- a OS concluída também é achada pelo nome
  update public.comprovantes set destino = null, destino_os_id = null, passo = null where id = v_cmp;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  v_r3 := pg_temp._responder(v_p, jsonb_build_object('tipo', 'nome', 'texto', 'cais ' || v_letras_f));
  insert into _resultado values ('T17 nome do barco: palavra inteira com enchimento, OS concluída, recado não vira nome',
    v_p->>'passo' = 'para_que'
    and v_r1->>'resultado' = 'invalida' and v_r1->>'motivo' = 'nome_nao_achado'
    and v_r2->>'resultado' = 'proximo' and v_r2->'cmp'->>'destino' = 'os' and v_r2->'cmp'->'os'->>'id' = v_os::text
    and v_r3->'cmp'->'os'->>'id' = v_fechada::text,
    'r1=' || coalesce(v_r1->>'motivo', v_r1->>'resultado') || ' r2=' || coalesce(v_r2->'cmp'->'os'->>'numero', v_r2->>'motivo', '-')
    || ' r3=' || coalesce(v_r3->'cmp'->'os'->>'numero', v_r3->>'motivo', '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T17 nome do barco: palavra inteira com enchimento, OS concluída, recado não vira nome', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T18: conversa desligada — nada muda para o dono ══════════════════════════════════════════
do $$
declare
  v_valor numeric := round((1000 + random() * 8000)::numeric, 2);
  v_lido uuid := pg_temp._cmp(jsonb_build_object('valor', v_valor));
  v_fila uuid := pg_temp._cmp();
  v_on jsonb;
  v_off jsonb;
  v_cnpj jsonb;
  v_ja jsonb;
  v_depois record;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v_fila]);
  update public.comprovantes set destino = 'empresa' where id = v_fila;
  v_on := public.comprovantes_parecidos(v_valor, pg_temp._hoje(), null, pg_temp._dono());
  update public.app_settings set value = 'off' where key = 'comprovante_conversa';
  v_off := public.comprovantes_parecidos(v_valor, pg_temp._hoje(), null, pg_temp._dono());
  v_cnpj := public.comprovantes_cnpj_a_consultar(null, 3);
  v_ja := public.comprovantes_ja_lancados(v_valor, pg_temp._hoje(), null, array['caixa'], pg_temp._dono());
  perform public._comprovantes_manutencao();
  select situacao, fila_desde, destino into v_depois from public.comprovantes where id = v_fila;
  update public.app_settings set value = 'on' where key = 'comprovante_conversa';
  insert into _resultado values ('T18 conversa desligada: sem "abertos" nas travas, sem BrasilAPI, a fila volta a ser da F1',
    jsonb_array_length(v_on->'abertos') >= 1 and jsonb_array_length(v_off->'abertos') = 0
    and v_cnpj = '[]'::jsonb and (v_ja->>'aberto')::boolean = false
    and v_depois.situacao = 'lido' and v_depois.fila_desde is null and v_depois.destino = 'empresa',
    'on=' || jsonb_array_length(v_on->'abertos') || ' off=' || jsonb_array_length(v_off->'abertos') || ' cnpj=' || v_cnpj::text
    || ' fila=' || coalesce(v_depois.situacao, '-'));
  perform pg_temp._livrar();
exception when others then
  update public.app_settings set value = 'on' where key = 'comprovante_conversa';
  insert into _resultado values ('T18 conversa desligada: sem "abertos" nas travas, sem BrasilAPI, a fila volta a ser da F1', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T19: o CPF do MEI nunca fica no nome do fornecedor ═══════════════════════════════════════
do $$
declare
  v_cnpj text := '7' || lpad((floor(random() * 1e12))::bigint::text, 13, '0');
  v_cmp uuid := pg_temp._cmp();
  v_k record;
  v_receita text;
begin
  update public.comprovantes set emitente_cnpj = v_cnpj, cnpj_confianca = 'alta', supplier_id = null where id = v_cmp;
  perform public.comprovante_cnpj_cache(v_cnpj, jsonb_build_object('encontrado', true,
    'razao_social', 'FULANO DA SILVA 12345678900', 'nome_fantasia', ''));
  select razao_social, nome_fantasia into v_k from public.cnpj_consultas where cnpj = v_cnpj;
  select fornecedor_receita into v_receita from public.comprovantes where id = v_cmp;
  insert into _resultado values ('T19 nome da Receita sem CPF (MEI): cache, CMP e o limpador',
    v_k.razao_social = 'FULANO DA SILVA' and v_k.nome_fantasia is null and v_receita = 'FULANO DA SILVA'
    and public._comprovante_sem_cpf('12.345.678 FULANO DE TAL') = 'FULANO DE TAL'
    and public._comprovante_sem_cpf('MARIA 123.456.789-09 ME') = 'MARIA ME'
    and public._comprovante_sem_cpf('Auto Posto Exemplo') = 'Auto Posto Exemplo',
    'razao=' || coalesce(v_k.razao_social, '-') || ' receita=' || coalesce(v_receita, '-'));
exception when others then
  insert into _resultado values ('T19 nome da Receita sem CPF (MEI): cache, CMP e o limpador', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T20: o texto solto depois da foto vira dica do CMP (e não conversa em andamento) ═══════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_cmp uuid := pg_temp._cmp();
  v_msg uuid;
  v_r jsonb;
  c record;
begin
  perform pg_temp._livrar();
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  v_msg := pg_temp._msg(now());
  v_r := public.comprovante_acrescentar_dica(v_cmp, 'essa é da OS ' || pg_temp._os_num(v_os), v_msg);
  select destino, destino_os_id, mensagens_de_dica into c from public.comprovantes where id = v_cmp;
  insert into _resultado values ('T20 dica depois da foto: pré-preenche a OS e não conta como conversa em andamento',
    (v_r->>'ok')::boolean and c.destino = 'os' and c.destino_os_id = v_os and v_msg = any (c.mensagens_de_dica)
    and not public._comprovante_conversa_em_andamento(pg_temp._phone()),
    'ok=' || coalesce(v_r->>'ok', '-') || ' destino=' || coalesce(c.destino, '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T20 dica depois da foto: pré-preenche a OS e não conta como conversa em andamento', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T21: a abertura pergunta o CMP que acabou de chegar e conta o lote (os antigos à parte) ═══
do $$
declare
  v_velho uuid := pg_temp._cmp();
  v_n1 uuid := pg_temp._cmp();
  v_n2 uuid := pg_temp._cmp();
  v_p jsonb;
begin
  perform pg_temp._livrar();
  -- tudo aqui roda numa transação (o mesmo now()): os CMPs dos testes anteriores ficam para trás
  update public.comprovantes
     set fila_desde = fila_desde - interval '1 day', gravado_em = gravado_em - interval '1 day',
         cancelado_em = cancelado_em - interval '1 day'
   where phone_normalized = pg_temp._phone() and id not in (v_velho, v_n1, v_n2);
  perform public.comprovante_conversa_entrar(array[v_velho]);
  update public.comprovantes set fila_desde = now() - interval '2 days', fila_ordem = now() - interval '2 days',
                                 ultima_pergunta_em = now() - interval '2 days'
   where id = v_velho;
  perform public.comprovante_conversa_entrar(array[v_n1, v_n2]);
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'abertura', v_n1);
  insert into _resultado values ('T21 abertura: o CMP novo (não o antigo da fila), "1 de 2" no lote, antigos à parte',
    v_p->'cmp'->>'id' = v_n1::text and (v_p->>'posicao')::int = 1 and (v_p->>'total')::int = 2
    and (v_p->'primeira_do_lote'->>'n')::int = 2 and (v_p->'primeira_do_lote'->>'antigos')::int = 1,
    'cmp=' || coalesce((v_p->'cmp'->>'id' = v_n1::text)::text, '-') || ' ' || coalesce(v_p->>'posicao', '-') || ' de '
    || coalesce(v_p->>'total', '-') || ' lote=' || coalesce((v_p->'primeira_do_lote')::text, '-'));
  perform pg_temp._livrar();
exception when others then
  insert into _resultado values ('T21 abertura: o CMP novo (não o antigo da fila), "1 de 2" no lote, antigos à parte', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T22: a trava de quem lança (financeiro): só sim/não, sem nada do comprovante ══════════════
do $$
declare
  v_valor numeric := round((1000 + random() * 8000)::numeric, 2);
  v_cmp uuid := pg_temp._cmp(jsonb_build_object('valor', v_valor));
  v_fin uuid := gen_random_uuid();
  v_tec uuid := gen_random_uuid();
  v_r_fin jsonb;
  v_r_tec jsonb;
  v_p_fin jsonb;
begin
  insert into public.app_users (id, full_name, email, role, active, created_at) values
    (v_fin, 'Financeiro de teste F2', 'teste-f2-' || v_fin || '@teste.invalido', 'financial', true, now()),
    (v_tec, 'Técnico de teste F2', 'teste-f2-' || v_tec || '@teste.invalido', 'technician', true, now());
  update public.comprovantes
     set situacao = 'gravado', gravado_em = now(), destino = 'empresa', valor_confirmado = v_valor,
         data_confirmada = pg_temp._hoje(), efeitos = '[{"tipo":"caixa","payable_id":null}]'::jsonb
   where id = v_cmp;
  v_r_fin := public.comprovantes_ja_lancados(v_valor, pg_temp._hoje(), null, array['caixa'], v_fin);
  v_r_tec := public.comprovantes_ja_lancados(v_valor, pg_temp._hoje(), null, array['caixa'], v_tec);
  v_p_fin := public.comprovantes_parecidos(v_valor, pg_temp._hoje(), null, v_fin);
  insert into _resultado values ('T22 comprovantes_ja_lancados: o financeiro sabe que já foi lançado, sem ver o CMP; técnico nada',
    (v_r_fin->>'ja_lancado')::boolean and not (v_r_tec->>'ja_lancado')::boolean
    and not (v_r_fin ? 'codigo') and jsonb_array_length(v_p_fin->'gravados') = 0,
    'fin=' || v_r_fin::text || ' tec=' || v_r_tec::text);
exception when others then
  insert into _resultado values ('T22 comprovantes_ja_lancados: o financeiro sabe que já foi lançado, sem ver o CMP; técnico nada', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T23: o "movido" de um movimento velho não apaga o "cancelar" pedido no meio ════════════════
do $$
declare
  v_cmp uuid := pg_temp._cmp();
  v_m1 record;
  v_f jsonb;
  v_m2 record;
begin
  update public.comprovantes
     set situacao = 'cancelado', motivo_cancelamento = 'dono_cancelou', cancelado_em = now(),
         dropbox_pendente = 'cancelar', dropbox_mover_proxima_em = now() + interval '3 minutes'
   where id = v_cmp;
  -- o move_v2 do "mover" (pedido antes do cancelamento) termina agora
  perform public.comprovante_dropbox_movido(v_cmp, 'id:ensaioT23a', '/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/a.jpg', 'rev1', 'mover');
  select dropbox_pendente, dropbox_mover_proxima_em, dropbox_id into v_m1 from public.comprovantes where id = v_cmp;
  -- a falha de um movimento velho também não conta
  v_f := public.comprovante_dropbox_mover_falhou(v_cmp, 'erro do mover velho', 'mover');
  -- o "cancelar" termina: aí sim zera
  perform public.comprovante_dropbox_movido(v_cmp, 'id:ensaioT23a', '/MANAGEMENT/FINANCIALS/COMPROVANTES/_CANCELADOS/a CANCELADO.jpg', 'rev2', 'cancelar');
  select dropbox_pendente, dropbox_caminho into v_m2 from public.comprovantes where id = v_cmp;
  insert into _resultado values ('T23 Dropbox: o fim de um "mover" velho não apaga o "cancelar"; o do "cancelar" zera',
    v_m1.dropbox_pendente = 'cancelar' and v_m1.dropbox_mover_proxima_em <= now() and v_m1.dropbox_id = 'id:ensaioT23a'
    and (v_f->>'ignorado')::boolean
    and v_m2.dropbox_pendente is null and v_m2.dropbox_caminho like '%_CANCELADOS%',
    'depois_do_mover=' || coalesce(v_m1.dropbox_pendente, 'null') || ' falha=' || coalesce(v_f->>'ignorado', '-')
    || ' depois_do_cancelar=' || coalesce(v_m2.dropbox_pendente, 'null'));
exception when others then
  insert into _resultado values ('T23 Dropbox: o fim de um "mover" velho não apaga o "cancelar"; o do "cancelar" zera', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
