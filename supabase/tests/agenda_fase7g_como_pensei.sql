-- Prova de como pensei, do porquê de uma OS e da data dita com a relação, Fase 7g (pacote P3; migration 20261112100200; spec-fase7g §5.3, §6.2, §6.3, §8.3
-- agenda_fase7g_como_pensei.sql e o bloco R9: R9.3-1, R9.4-5, R9.5-11, R9.6, R9.7, R9.8, R9.12, R9.13).
-- bancada: depende de 20261112100200
--
-- O cenário: o do motor (scripts/bancada-agenda/cenario-motor.sql, qui 29/10/2026: A = Antônio OS-00201, 2 dias ter 03 e qua 04/11, Roberto e João, você abre e
-- fecha; B = Beatriz OS-00202, meio dia de diagnóstico qui 05/11 de manhã; C = Caio OS-00203, reserva condicionada à compra do cabo, qui 05 a ter 10/11), publicado
-- pela vigia às 16:30 com modo_porque em sombra (o porquê gravado pelo P2), e o Daniel (OS-00204, 1 dia, Roberto) quando o caso precisa. A semana que vem é a de
-- 02/11 (seg 02/11 é Finados).
--
--   C0  o catálogo: as 6 novas (volatilidade, definer, search_path) e as portas (as 4 internas só o service_role; as 2 leituras authenticated e service_role,
--       nunca anon); agenda_rascunho_marcar com a porta de antes
--   C1  como pensei: o texto da §6.3 byte a byte (ligado); em sombra, "Em teste: " antes de "Como pensei" e o resto igual; desligado, {modo: desligado}
--   C2  a ordem fixa das partes e as chaves do objeto
--   C3  o corte em texto_max (400): de baixo para cima pelas listas, sem tirar a 1ª linha de nenhuma parte
--   C4  _agenda_porque_da_os: marcada pelo gestor, por você, mudada, reservada, de fora sem e com pergunta, fora da carteira, sem o porquê guardado, OS que não existe
--   C5  determinismo: as 2 leituras 2×, o mesmo md5
--   C6  as portas de verdade: o técnico com login 42501, o admin com login lê, authenticated sem login 42501, o service_role lê
--   C7  a data dita (R9.4-5): a relação nas palavras do dono (_agenda_relacao_dita), a data com a relação, e da frase do dono até o *grava* ("passa o Daniel para
--       depois de quinta" marca sex 06/11; "não antes de quinta" marca a quinta); em sombra e desligado, o rascunho byte a byte; os outros 7 chamadores e
--       _agenda_data_conferida no md5 de antes
--   C8  o freio (R9.6): a 1ª linha e o "Eu marcaria" da última conta do gestor (só o que toca a semana; a conta de outro dia; sem conta); sem o freio nada disso
--   C9  "Preciso de você" (R9.7): a linha de agenda_perguntas_em_ordem como vem; o N de "Decisão N:" é o de agenda_decisoes_abertas (*agenda pendências*); a
--       sem número com "•"; a já escolhida fora; o resto em *agenda pendências*
--   C10 a folga nos 2 ramos (R9.7), contra a conta feita à mão do comentário do cenário (a âncora de fora): com o freio, por pessoa; com a regra teto_equipe, pela
--       equipe; o que as reservas usam muda de um ramo para o outro
--   C11 os riscos: o "compre até" (no prazo e vencido), a suposição que não foi o motivo da linha, a semana cheia; até 3, na ordem da data
--   C12 a parte que falha: incompleto, a linha "não consegui ler agora" e as outras partes inteiras
--   C13 as cópias: agenda_rascunho_marcar, tirados os blocos -- FASE 7g, é a da origem (md5 do R9.1); a migration só cria as 6 novas e recria só ela
--   C14 o peso (R9.8, R9.3-1): 1 painel, 1 grade, nenhuma _agenda_classe_agora nem agenda_meios_da_os por OS; a frase do viés só quando a 7e corrige
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7g_como_pensei.sql
--   Seguro em produção: termina em ROLLBACK. O que usa o cenário, a fixture ou a migration como texto só roda na bancada (fora dela sai PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- p_sql com o login de p_uid (authenticated) ou sem login (p_uid nulo) no papel p_papel: o resultado em texto, ou 'erro <estado>: <mensagem>'
create function pg_temp.como(p_papel text, p_uid uuid, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then json_build_object('role', p_papel)::text
                                                else json_build_object('role', p_papel, 'sub', p_uid)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    reset role;
    perform set_config('request.jwt.claims', '', true);
    return 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_estado text; v_msg text;
begin
  execute p_sql;
  return 'sem erro';
exception when others then
  get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  return v_estado || ' ' || v_msg;
end $f$;
-- Quantas vezes a função rodou nesta transação (track_functions = all, como em agenda_correcao_2910_p5.sql).
create function pg_temp.chamadas(p_nome text) returns bigint language sql as $f$
  select coalesce(sum(f.calls), 0)::bigint from pg_stat_xact_user_functions f where f.schemaname = 'public' and f.funcname = p_nome
$f$;
-- O *grava* na hora dada (a bancada fixa a hora por agenda.agora).
create function pg_temp.grava(p_autor uuid, p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.agora', pg_temp.em(p_dia, p_hora)::text, true);
  return public.agenda_rascunho_gravar(p_autor, p_dia);
end $f$;
-- Uma OS a mais no cenário (o molde de agenda_fase2_rascunho.sql): sinal pago, aprovada em 20/10, com os dias e a equipe.
create function pg_temp.os_extra(p_n text, p_cliente text, p_dias numeric, p_equipe jsonb, p_status text default 'approved') returns uuid language plpgsql as $f$
declare
  v_os uuid := pg_temp.os(p_n);
  v_cl uuid := ('c4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid;
  e jsonb;
begin
  insert into public.clients (id, type, name) values (v_cl, 'individual', p_cliente);
  insert into public.vessels (id, client_id, name, asset_type) values (('f4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid, v_cl, 'Lancha', 'Lancha');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
  values (v_os, 'OS-' || lpad(p_n, 5, '0'), v_cl, ('f4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid, p_status, 'approved', 'repair',
          timestamptz '2026-10-15 12:00-03', timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-20 12:00-03', 2160);
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (md5('cen:servico:' || p_n)::uuid, v_os, '5e000000-0000-4000-8000-000000000003', 'Revisão do sistema elétrico', 'unit', 1, 2160, 2160, timestamptz '2026-10-15 12:00-03');
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount, balance_amount, is_deposit)
  values (md5('cen:sinal:' || p_n)::uuid, v_cl, v_os, 'Sinal', date '2026-10-20', date '2026-10-20', 500, 'paid', 500, 0, true);
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em)
  values (v_os, p_dias, case when p_dias is not null then 'dono' end, case when p_dias is not null then timestamptz '2026-10-28 18:00-03' end, 'nunca',
          timestamptz '2026-10-28 18:00-03');
  for e in select x from jsonb_array_elements(coalesce(p_equipe, '[]'::jsonb)) x loop
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_os, (e ->> 'payee')::uuid, e ->> 'turnos');
  end loop;
  return v_os;
end $f$;
-- O cenário do motor publicado pela vigia na qui 29/10 às 16:30, com modo_porque = p_porque (o porquê gravado pelo P2), sem o freio e com o gestor desligado
-- (o "Eu marcaria" só entra no C8). modo_explicar fica como o caso pede.
create function pg_temp.publicado(p_porque text default 'sombra') returns void language plpgsql as $f$
begin
  execute current_setting('agenda_teste.cenario_motor');
  update public.agenda_config set modo_proposta = 'ligado', modo_vigia = 'ligado', modo_porque = p_porque, gestor_so_propor = false,
         modo_marcar_sozinho = 'desligado' where id;
  perform public.agenda_vigiar(date '2026-10-29', pg_temp.em(date '2026-10-29', '16:30'));
end $f$;
create function pg_temp.pensei(p_modo text default 'ligado', p_de date default null) returns jsonb language plpgsql as $f$
begin
  update public.agenda_config set modo_explicar = p_modo where id;
  return public.agenda_como_pensei(p_de, date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00'));
end $f$;
create function pg_temp.porque(p_os uuid) returns jsonb language sql as $f$
  select public._agenda_porque_da_os(p_os, date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00'))
$f$;
-- O Daniel (OS-00204) marcado pelo gestor na qui 05/11 à tarde com o João (e você abrindo), com o porquê gravado à mão na forma do P2 (o motor não chega a esse
-- porquê no cenário): a estimativa pelo orçamento (1 dia, R$ 2.160 de mão de obra), o prazo padrão do cabo, o local suposto e a 1 pessoa, o critério "único", e
-- a ação que o moveu (degrau dia, zona firme; a alocação guarda outro degrau, para provar que vale o da ação). A abertura tem o id menor e suposições [] (como o
-- P2 grava): a linha lê a de turno. Assim o texto inteiro do porquê é conhecido.
create function pg_temp.daniel_marcado() returns uuid language plpgsql as $f$
declare
  v_os   uuid := pg_temp.os_extra('204', 'Daniel', 1, '[]'::jsonb);
  v_ac   uuid := md5('7g:p3:acao:daniel')::uuid;
  v_al   uuid := 'ffffffff-0000-4000-8000-000000000204';
  v_ab   uuid := '00000000-0000-4000-8000-000000000204';
  c_pub  constant timestamptz := pg_temp.em(date '2026-10-29', '16:40');
begin
  insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, alocacoes_canceladas, payee_id, antes, depois,
                                   texto, desfazivel_ate, zona, degrau)
  values (v_ac, c_pub, date '2026-10-29', true, 'vigia', 'mover', v_os, array[v_os], array[v_al, v_ab], '{}', 'bb000000-0000-4000-8000-000000000003',
          '{"alocacoes": [], "fim": null}'::jsonb, '{"alocacoes": [], "fim": null}'::jsonb, 'Mudei Daniel para qui 05/11 com João.', c_pub + interval '24 hours',
          'firme', 'dia');
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, acao_id, duracao_fonte, criterio,
                                       motivos, criado_em, suposicoes, degrau)
  values (v_al, v_os, 'bb000000-0000-4000-8000-000000000003', date '2026-11-05', 'tarde', 'turno', 'execucao', 'publicada', 'motor', c_pub, v_ac, 'orcamento', 'unico',
          '[]', c_pub,
          '[{"codigo": "prazo_padrao_peca", "detalhe": {"itens": ["Cabo"], "du": 7}}, {"codigo": "local_suposto", "detalhe": {"local": "na MP Motorhomes", "fonte": "patio"}},
            {"codigo": "duracao_orcamento", "detalhe": {"dias": 1, "mo": 2160}}, {"codigo": "uma_pessoa", "detalhe": {}}]'::jsonb, 'pessoa'),
         (v_ab, v_os, 'bb000000-0000-4000-8000-000000000001', date '2026-11-05', 'tarde', 'abertura', 'execucao', 'publicada', 'motor', c_pub, v_ac, 'orcamento', null,
          '[]', c_pub, '[]'::jsonb, null);
  return v_os;
end $f$;
-- A Elisa (OS-00205) e o Hugo (OS-00208), marcados por você (origem dono) e sem suposição. A Elisa: compromisso sem fonte dita (o gatilho da 7a põe "sugerida"), 3
-- meios-dias distintos (seg 09, ter 10 e qua 11/11 à tarde com o João; você junto na seg 09 à tarde) e uma reserva ao lado (qui 12/11 à tarde): a duração é o tamanho
-- do compromisso, 1 dia e meio. O Hugo: só a reserva de agora em diante (sex 13/11 à tarde, João) e um compromisso já passado (ter 27/10 à tarde): reservada. A
-- reserva nunca tem fonte da duração (_agenda_alocacao_fonte a anula).
create function pg_temp.elisa_e_hugo() returns void language plpgsql as $f$
begin
  perform pg_temp.os_extra('205', 'Elisa', null, '[]'::jsonb);
  perform pg_temp.os_extra('208', 'Hugo', null, '[]'::jsonb);
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, reserva_de, estado, origem, publicada_em, motivos, criado_em, suposicoes)
  select md5('7g:p3:' || x.n || ':' || x.d || x.p)::uuid, pg_temp.os(x.n), x.p::uuid, x.d::date, 'tarde', 'turno', x.t, case when x.t = 'reserva' then 'teto' end,
         'publicada', x.o, pg_temp.em(date '2026-10-26', '16:30'), '[]', pg_temp.em(date '2026-10-26', '16:30'), '[]'::jsonb
    from (values ('205', '2026-11-09', 'bb000000-0000-4000-8000-000000000003', 'execucao', 'dono'), ('205', '2026-11-10', 'bb000000-0000-4000-8000-000000000003', 'execucao', 'dono'),
                 ('205', '2026-11-11', 'bb000000-0000-4000-8000-000000000003', 'execucao', 'dono'), ('205', '2026-11-09', 'bb000000-0000-4000-8000-000000000001', 'execucao', 'dono'),
                 ('205', '2026-11-12', 'bb000000-0000-4000-8000-000000000003', 'reserva', 'dono'),
                 ('208', '2026-11-13', 'bb000000-0000-4000-8000-000000000003', 'reserva', 'dono'), ('208', '2026-10-27', 'bb000000-0000-4000-8000-000000000003', 'execucao', 'motor'),
                 ('205', '2026-11-16', 'bb000000-0000-4000-8000-000000000003', 'execucao', 'dono')) x(n, d, p, t, o);
  -- o compromisso da Elisa que você tirou (seg 16/11): cancelado, não é do tamanho do bloco
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(date '2026-10-27', '10:00'), cancelada_motivo = 'dono'
   where service_order_id = pg_temp.os('205') and dia = date '2026-11-16';
end $f$;
-- Uma pergunta ligada à mão (o molde de agenda_fase7f_perguntas.sql): crítica com perda_em e opções, ou não crítica sem elas.
create function pg_temp.perg(p_tipo text, p_chave text, p_os uuid, p_perda date, p_criada timestamptz, p_escolhida smallint default null) returns uuid language sql as $f$
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, modo, criada_em, opcao_escolhida)
  values (p_tipo, p_chave, p_os, array[p_os], p_perda, 'Isso muda o plano. 1) Passa. 2) Fica.', '[{"n": 1, "texto": "Passa"}, {"n": 2, "texto": "Fica"}]', 1, 'ligado',
          p_criada, p_escolhida)
  returning id
$f$;

-- ── C0. O catálogo e as portas ───────────────────────────────────────────────────────────────────────
do $c0$
declare
  v_res jsonb := '[]'::jsonb;
  v     text;
begin
  select string_agg(format('%s:%s:%s:%s', p.proname, p.prosecdef, p.provolatile, coalesce(array_to_string(p.proconfig, ','), '-')), ' | ' order by p.proname collate "C") into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('_agenda_relacao_dita', '_agenda_data_com_relacao', '_agenda_porque_fonte', '_agenda_porque_linha', '_agenda_porque_da_os', 'agenda_como_pensei');
  v_res := pg_temp.ok(v_res, 'C0a as 6 novas: só as 2 leituras definer; a relação IMMUTABLE, o resto STABLE; search_path fixo',
    v = '_agenda_data_com_relacao:f:s:search_path=public | _agenda_porque_da_os:t:s:search_path=public | _agenda_porque_fonte:f:s:search_path=public | '
        || '_agenda_porque_linha:f:s:search_path=public | _agenda_relacao_dita:f:i:search_path=public | agenda_como_pensei:t:s:search_path=public', v);
  select string_agg(format('%s:%s:%s:%s', f, has_function_privilege('anon', f, 'execute'), has_function_privilege('authenticated', f, 'execute'),
                           has_function_privilege('service_role', f, 'execute')), ' | ' order by f collate "C") into v
    from unnest(array['public._agenda_relacao_dita(text, text)', 'public._agenda_data_com_relacao(jsonb, text, text, date)', 'public._agenda_porque_fonte(uuid, date)',
                      'public._agenda_porque_linha(uuid, jsonb, date)', 'public._agenda_porque_da_os(uuid, date, timestamptz)',
                      'public.agenda_como_pensei(date, date, timestamptz)']) f;
  v_res := pg_temp.ok(v_res, 'C0b as portas: as 4 internas só o service_role; as 2 leituras authenticated e service_role; anon nenhuma',
    v = 'public._agenda_data_com_relacao(jsonb, text, text, date):f:f:t | public._agenda_porque_da_os(uuid, date, timestamptz):f:t:t | '
        || 'public._agenda_porque_fonte(uuid, date):f:f:t | public._agenda_porque_linha(uuid, jsonb, date):f:f:t | public._agenda_relacao_dita(text, text):f:f:t | '
        || 'public.agenda_como_pensei(date, date, timestamptz):f:t:t', v);
  v := (select format('%s:%s:%s:%s', p.prosecdef, has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                      has_function_privilege('service_role', p.oid, 'execute'))
          from pg_proc p where p.oid = 'public.agenda_rascunho_marcar(uuid, text, text, text, text, text, text, date, timestamptz)'::regprocedure);
  v_res := pg_temp.ok(v_res, 'C0c agenda_rascunho_marcar recriada com a porta de antes (definer; authenticated e service_role; anon não)', v = 't:f:t:t', v);
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C0 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c0$;

-- ── C1, C2, C3 e C5. O texto, a ordem, o corte e o determinismo ──────────────────────────────────────
do $c1$
declare
  v_res jsonb := '[]'::jsonb;
  v_l   jsonb;
  v_s   jsonb;
  v_d   jsonb;
  v_c   jsonb;
  v     text;
  v_pos int[];
  -- o texto medido na 1ª rodada (passo1.out), conferido linha a linha contra o cenário: as 2 marcadas da vigia com a fonte dita e o 1 motivo gravado
  -- (bem_disponivel, a 1ª suposição com texto), a reserva do Caio com a condição gravada, o Daniel pronto e sem lugar, a folga da conta à mão (C10), o Roberto
  -- com 8 de 8 meios-dias, nenhuma pergunta
  c_texto constant text := 'Como pensei a semana de 02 a 06/11:' || E'\n' || 'Marquei: Antônio (OS-00201) ter 03 e qua 04/11 com Roberto e João — você disse 2 dias; o barco livre nesses dias (ninguém disse que está em uso). Beatriz (OS-00202) qui 05/11 com Roberto — você disse meio dia; o barco livre nesses dias (ninguém disse que está em uso).' || E'\n' || 'Reservei: Caio (OS-00203) qui 05 e sex 06/11 com Roberto, se "Cabo de bateria…" estiver na mão (compre até ter 03/11, fornecedor Premel) — o barco livre nesses dias (ninguém disse que está em uso).' || E'\n' || 'De fora: prontos sem lugar — Daniel.' || E'\n' || 'Folga: guardei 1 dia e meio da equipe para imprevisto (25% da semana); 1 dia já está com a reserva de Caio.' || E'\n' || 'Riscos: Roberto está com a semana cheia.' || E'\n' || 'Preciso de você: nada por agora.';
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C1 como pensei no cenário', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.os_extra('204', 'Daniel', 1, jsonb_build_array(jsonb_build_object('payee', 'bb000000-0000-4000-8000-000000000002', 'turnos', 'dia')));
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C1a ligado: o texto da §6.3 com o cenário, byte a byte', v_l ->> 'texto' = c_texto, v_l ->> 'texto');
    v_s := pg_temp.pensei('sombra');
    v_res := pg_temp.ok(v_res, 'C1b sombra: "Em teste: " antes de "Como pensei", o resto e o objeto iguais aos de ligado',
      v_s ->> 'texto' = 'Em teste: ' || (v_l ->> 'texto') and (v_s - 'texto' - 'modo') = (v_l - 'texto' - 'modo') and v_s ->> 'modo' = 'sombra', v_s ->> 'texto');
    v_d := pg_temp.pensei('desligado');
    v_res := pg_temp.ok(v_res, 'C1c desligado: só {modo: desligado}', v_d = '{"modo": "desligado"}'::jsonb, v_d::text);
    -- C2: as partes na ordem fixa, e as chaves
    v := v_l ->> 'texto';
    v_pos := array[strpos(v, E'Como pensei a semana de '), strpos(v, E'\nMarquei: '), strpos(v, E'\nReservei: '), strpos(v, E'\nDe fora: '), strpos(v, E'\nFolga: '),
                   strpos(v, E'\nRiscos: '), strpos(v, E'\nPreciso de você')];
    v_res := pg_temp.ok(v_res, 'C2a as 7 linhas de cabeça na ordem: Como pensei, Marquei, Reservei, De fora, Folga, Riscos, Preciso de você (cada uma uma vez)',
      v_pos[1] = 1 and (select bool_and(v_pos[i] > v_pos[i - 1]) from generate_series(2, 7) i)
      and (select bool_and((char_length(v) - char_length(replace(v, x, ''))) / char_length(x) = 1)
             from unnest(array['Como pensei a semana de ', E'\nMarquei: ', E'\nReservei: ', E'\nDe fora: ', E'\nFolga: ', E'\nRiscos: ', E'\nPreciso de você']) x),
      v_pos::text);
    v_res := pg_temp.ok(v_res, 'C2b as chaves: semana, marcadas, reservadas, fora, folga, riscos, precisa, texto, incompleto e modo (sem eu_marcaria nem falhas)',
      (select array_agg(k order by k collate "C") from jsonb_object_keys(v_l) k) = array['folga', 'fora', 'incompleto', 'marcadas', 'modo', 'precisa', 'reservadas', 'riscos', 'semana', 'texto']
      and v_l -> 'semana' = '{"de": "2026-11-02", "ate": "2026-11-08", "rotulo": "02 a 06/11"}'::jsonb and not (v_l ->> 'incompleto')::boolean,
      (v_l -> 'semana')::text);
    v_c := pg_temp.pensei('ligado', date '2026-11-04');
    v := pg_temp.erro_de('select public.agenda_como_pensei(null, null, now())');
    v_res := pg_temp.ok(v_res, 'C2c um dia no meio da semana (qua 04/11) dá a mesma semana (seg 02/11), o mesmo objeto; sem o dia de hoje: 22004',
      v_c = v_l and v like '22004 %', v);
    -- C5: determinismo
    v_c := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C5a como pensei 2×: o mesmo md5', md5(v_c::text) = md5(v_l::text), null);
    v_res := pg_temp.ok(v_res, 'C5b o porquê de uma OS 2×: o mesmo md5', md5(pg_temp.porque(pg_temp.os('201'))::text) = md5(pg_temp.porque(pg_temp.os('201'))::text), null);
    -- C3: o corte. Em 650, a lista de baixo que ainda tem mais de 1 é a das marcadas: sai a Beatriz, o resto igual. Em 400, depois das listas, as marcadas e as
    -- reservadas perdem o porquê e a condição; o que sobrar passa pelo corte duro.
    update public.agenda_config set texto_max = 650 where id;
    v_c := pg_temp.pensei('ligado');
    v := v_c ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C3a em 650: sai a última marcada ("(e mais 1 em *agenda semana que vem*)"), as outras linhas inteiras; o objeto não muda',
      char_length(v_l ->> 'texto') > 650 and char_length(v) <= 650
      and v = replace(v_l ->> 'texto', '. Beatriz (OS-00202) qui 05/11 com Roberto — você disse meio dia; o barco livre nesses dias (ninguém disse que está em uso).',
                      ' (e mais 1 em *agenda semana que vem*).')
      and (v_c - 'texto') = (v_l - 'texto'), char_length(v_l ->> 'texto') || ' → ' || char_length(v) || ' ' || v);
    update public.agenda_config set texto_max = 400 where id;
    v := pg_temp.pensei('ligado') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C3b em 400: as marcadas e as reservadas na forma curta (sem o porquê e a condição), e o texto em até 400',
      char_length(v) <= 400 and v like 'Como pensei a semana de 02 a 06/11:%'
      and v like E'%\nMarquei: Antônio (OS-00201) ter 03 e qua 04/11 com Roberto e João (e mais 1 em *agenda semana que vem*).\nReservei: Caio (OS-00203) qui 05 e sex 06/11 com Roberto.\n%',
      char_length(v) || ' ' || v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C1 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c1$;

-- ── C1x. De fora pelos grupos do painel; a marcação de antes do porquê; o corte das marcadas em como_pensei_itens_max ──────────
do $c1x$
declare
  v_res jsonb := '[]'::jsonb;
  v_l   jsonb;
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C1x de fora e o corte das marcadas', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    -- pronto sem lugar (Daniel), parado no cliente (Elisa), em outra semana (Fábio, qua 11/11), esperando peça (Gil: um item crítico em falta, sem fornecedor)
    perform pg_temp.os_extra('204', 'Daniel', 1, '[]'::jsonb);
    perform pg_temp.os_extra('205', 'Elisa', 1, '[]'::jsonb, 'awaiting_client');
    perform pg_temp.os_extra('206', 'Fábio', 1, '[]'::jsonb);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, motivos, criado_em)
    values (md5('7g:p3:fabio')::uuid, pg_temp.os('206'), 'bb000000-0000-4000-8000-000000000003', date '2026-11-11', 'tarde', 'turno', 'execucao', 'publicada', 'motor',
            pg_temp.em(date '2026-10-29', '16:30'), 'dono', '[]', pg_temp.em(date '2026-10-29', '16:30'));
    perform pg_temp.os_extra('207', 'Gil', 1, '[]'::jsonb);
    insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, conferido_em, atualizado_por)
    values (md5('7g:p3:gil:inversor')::uuid, pg_temp.os('207'), 'dono', 'Inversor 3 kW', 1, 0, true, 'falta', 'dono', pg_temp.em(date '2026-10-28', '18:00'),
            'aa000000-0000-4000-8000-000000000001');
    -- o Mário também espera peça (o 2º nome do grupo, sem o detalhe); o Kleber teve um dia no passado (ter 27/10) e nada de hoje em diante: é pronto sem lugar (o dia passado não o põe em outra semana)
    perform pg_temp.os_extra('213', 'Mário', 1, '[]'::jsonb);
    insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, conferido_em, atualizado_por)
    values (md5('7g:p3:mario:painel')::uuid, pg_temp.os('213'), 'dono', 'Painel solar', 1, 0, true, 'falta', 'dono', pg_temp.em(date '2026-10-28', '18:00'),
            'aa000000-0000-4000-8000-000000000001');
    perform pg_temp.os_extra('211', 'Kleber', 1, '[]'::jsonb);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, motivos, criado_em)
    values (md5('7g:p3:kleber')::uuid, pg_temp.os('211'), 'bb000000-0000-4000-8000-000000000003', date '2026-10-27', 'tarde', 'turno', 'execucao', 'publicada', 'motor',
            pg_temp.em(date '2026-10-26', '16:30'), 'dono', '[]', pg_temp.em(date '2026-10-26', '16:30'));
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C1xa De fora: os grupos na ordem da §5.3 (peça, você, cliente, sem lugar, outra semana, em espera), até 3 nomes, o 1º de cada um com o detalhe',
      v_l ->> 'texto' like E'%\nDe fora: esperando peça — Gil (1 item a comprar) e Mário; esperando o cliente — Elisa; prontos sem lugar — Daniel e Kleber; em outra semana — Fábio (a partir de qua 11/11).\n%'
      and (select string_agg(x ->> 'grupo', ',' order by o) from jsonb_array_elements(v_l -> 'fora') with ordinality t(x, o)) = 'peca,cliente,sem_lugar,outra_semana'
      and jsonb_array_length(v_l -> 'marcadas') = 2,
      v_l ->> 'texto' || ' | ' || coalesce((select (e - 'p')::text from jsonb_array_elements(public._agenda_painel(date '2026-10-29') -> 'oss') e where e ->> 'numero' = 'OS-00211'), '∅'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- 4 marcadas (o Antônio, a Beatriz, o Daniel na qui 05 à tarde e a Íris na sex 06 à tarde) com como_pensei_itens_max = 3 (o mínimo do CHECK)
    perform pg_temp.publicado('sombra');
    perform pg_temp.daniel_marcado();
    perform pg_temp.os_extra('209', 'Íris', 1, '[]'::jsonb);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, motivos, criado_em, suposicoes)
    values (md5('7g:p3:iris')::uuid, pg_temp.os('209'), 'bb000000-0000-4000-8000-000000000003', date '2026-11-06', 'tarde', 'turno', 'execucao', 'publicada', 'motor',
            pg_temp.em(date '2026-10-29', '16:30'), 'dono', '[]', pg_temp.em(date '2026-10-29', '16:30'), '[]'::jsonb);
    update public.agenda_config set como_pensei_itens_max = 3 where id;
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C1xb como_pensei_itens_max = 3: as 3 primeiras pelo 1º meio-dia e "(e mais 1 em *agenda semana que vem*)"; o objeto leva as 4',
      v_l ->> 'texto' like E'%\nMarquei: Antônio (OS-00201) %. Beatriz (OS-00202) %. Daniel (OS-00204) % (e mais 1 em *agenda semana que vem*).\n%'
      and v_l ->> 'texto' not like '%Íris%' and jsonb_array_length(v_l -> 'marcadas') = 4
      and (select string_agg(x ->> 'numero', ',' order by o) from jsonb_array_elements(v_l -> 'marcadas') with ordinality t(x, o)) = 'OS-00201,OS-00202,OS-00204,OS-00209',
      v_l ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.publicado('desligado');
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C1xc marcadas antes do porquê (suposições nulas): a linha diz "de antes de eu guardar o porquê", sem inventar a fonte',
      (select bool_and(x ->> 'porque' = 'de antes de eu guardar o porquê') from jsonb_array_elements(v_l -> 'marcadas') x)
      and jsonb_array_length(v_l -> 'marcadas') = 2 and v_l ->> 'texto' like E'%\nMarquei: Antônio (OS-00201) % — de antes de eu guardar o porquê. %', v_l ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C1x o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c1x$;

-- ── C4. O porquê de uma OS, em cada estado ───────────────────────────────────────────────────────────
do $c4$
declare
  v_res   jsonb := '[]'::jsonb;
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  p       jsonb;
  r       jsonb;
  v_q     uuid;
  v_n     int;
  v_lin   text;
  v       text;
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C4 o porquê de uma OS', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.daniel_marcado();
    p := pg_temp.porque(pg_temp.os('204'));
    v_res := pg_temp.ok(v_res, 'C4a marcada pelo gestor e mudada: o texto da §6.2 com a duração, o que contei, a pessoa, a mudança e o fecho; as chaves',
      p ->> 'estado' = 'marcada' and p ->> 'quem' = 'gestor' and p ->> 'quem_texto' = 'marcado pelo gestor' and p ->> 'fonte' = 'orcamento'
      and p ->> 'fonte_texto' = '1 dia pelo orçamento (R$ 2.160 de mão de obra; estimativa minha)' and p ->> 'criterio_texto' = 'só ele estava livre'
      and p ->> 'degrau_texto' = 'mudei o dia, dentro da semana combinada' and p ->> 'zona' = 'firme' and p -> 'motivo_fora' = 'null'::jsonb
      and p -> 'suposicoes' = '[{"codigo": "prazo_padrao_peca", "texto": "Cabo: contei 7 dias úteis de entrega (não sei de quem comprar)"}, {"codigo": "local_suposto", "texto": "na MP Motorhomes (supus pelo tipo do bem)"}, {"codigo": "uma_pessoa", "texto": "1 pessoa (dupla só quando o serviço pede)"}]'::jsonb
      and p ->> 'texto' = 'Daniel (OS-00204): marquei qui 05/11 com João. Duração: 1 dia pelo orçamento (R$ 2.160 de mão de obra; estimativa minha). Contei: Cabo: contei 7 dias úteis de entrega (não sei de quem comprar); na MP Motorhomes (supus pelo tipo do bem); 1 pessoa (dupla só quando o serviço pede). João: só ele estava livre. Última mudança: mudei o dia, dentro da semana combinada. Se algo estiver errado, me diga o certo.',
      p::text);
    p := pg_temp.porque(pg_temp.os('201'));
    v_res := pg_temp.ok(v_res, 'C4b marcada pelo gestor no cenário (a vigia, com o porquê gravado pelo P2): quem, a fonte dita, o critério da equipe dita',
      p ->> 'estado' = 'marcada' and p ->> 'quem' = 'gestor' and p ->> 'fonte' = 'dono' and p ->> 'texto' = 'Antônio (OS-00201): marquei ter 03 e qua 04/11 com Roberto e João. Duração: você disse 2 dias. Contei: o barco livre nesses dias (ninguém disse que está em uso). Roberto: quem você disse. Se algo estiver errado, me diga o certo.', p::text);
    p := pg_temp.porque(pg_temp.os('202'));
    v_res := pg_temp.ok(v_res, 'C4b2 no empate do 1º meio-dia (você e o Roberto na qui 05 de manhã), vale o técnico: o critério dele ("quem você disse"), não o seu (presença)',
      p ->> 'criterio_texto' = 'quem você disse' and p ->> 'texto' = 'Beatriz (OS-00202): marquei qui 05/11 com Roberto. Duração: você disse meio dia. Contei: o barco livre nesses dias (ninguém disse que está em uso). Roberto: quem você disse. Se algo estiver errado, me diga o certo.', p::text);
    p := pg_temp.porque(pg_temp.os('203'));
    v_res := pg_temp.ok(v_res, 'C4c reservada: "reservei" com a condição gravada da reserva',
      p ->> 'estado' = 'reservada' and p ->> 'texto' = 'Caio (OS-00203): reservei qui 05 a ter 10/11 com Roberto, se "Cabo de bateria…" estiver na mão (compre até ter 03/11, fornecedor Premel). Contei: o barco livre nesses dias (ninguém disse que está em uso). Roberto: quem você disse. Se algo estiver errado, me diga o certo.'
      and p -> 'fonte' = 'null'::jsonb, p::text);
    -- C4k: a reserva que você fez, pela sugerida (o tamanho do bloco: meios-dias distintos do mesmo lado), e as peças por dentro
    perform pg_temp.elisa_e_hugo();
    p := pg_temp.porque(pg_temp.os('205'));
    v_res := pg_temp.ok(v_res, 'C4k marcada por você sem fonte dita (sugerida): a duração é o tamanho do compromisso (3 meios-dias distintos; a reserva ao lado não entra)',
      p ->> 'estado' = 'marcada' and p ->> 'quem' = 'dono' and p ->> 'fonte' = 'sugerida'
      and p ->> 'texto' = 'Elisa (OS-00205): você marcou seg 09 a qua 11/11 com João. Duração: 1,5 dia (estimativa minha, só para reservar).', p::text);
    p := pg_temp.porque(pg_temp.os('208'));
    v_res := pg_temp.ok(v_res, 'C4k2 só reserva de agora em diante, sua: "você reservou", sem duração (a reserva não tem fonte); o compromisso passado não conta',
      p ->> 'estado' = 'reservada' and p ->> 'quem' = 'dono' and p ->> 'texto' = 'Hugo (OS-00208): você reservou sex 13/11 com João.', p::text);
    v := (select public._agenda_porque_fonte(a.id, date '2026-10-29')::text from public.agenda_alocacoes a
           where a.service_order_id = pg_temp.os('205') and a.dia = date '2026-11-10');
    v_res := pg_temp.ok(v_res, 'C4l _agenda_porque_fonte: a sugerida pelo tamanho do bloco (1,5 dia); a alocação que não existe dá nula',
      v::jsonb = '{"fonte": "sugerida", "dias": 1.5, "mo": null, "texto": "1,5 dia (estimativa minha, só para reservar)"}'::jsonb
      and public._agenda_porque_fonte(gen_random_uuid(), date '2026-10-29') is null, v);
    v := concat_ws(' | ', public._agenda_porque_linha(pg_temp.os('204'), '["ffffffff-0000-4000-8000-000000000204", "00000000-0000-4000-8000-000000000204"]', date '2026-10-29'),
                   coalesce(public._agenda_porque_linha(pg_temp.os('204'), '[{"id": "ffffffff-0000-4000-8000-000000000204"}]', date '2026-10-29'), '∅'),
                   coalesce(public._agenda_porque_linha(pg_temp.os('201'), '["ffffffff-0000-4000-8000-000000000204"]', date '2026-10-29'), '∅'),
                   coalesce(public._agenda_porque_linha(pg_temp.os('204'), '"ffffffff-0000-4000-8000-000000000204"', date '2026-10-29'), '∅'),
                   public._agenda_porque_linha(pg_temp.os('205'), jsonb_build_array((select a.id::text from public.agenda_alocacoes a
                                                                                     where a.service_order_id = pg_temp.os('205') and a.dia = date '2026-11-10')), date '2026-10-29'));
    v_res := pg_temp.ok(v_res, 'C4m _agenda_porque_linha: a da alocação de turno (não a abertura, de id menor), a fonte e 1 motivo; ids fora do formato, de outra OS ou fora de lista: nula; sem motivo, só a fonte (sem "; " no fim)',
      v = '1 dia pelo orçamento (R$ 2.160 de mão de obra; estimativa minha); Cabo: contei 7 dias úteis de entrega (não sei de quem comprar) | ∅ | ∅ | ∅ | 1,5 dia (estimativa minha, só para reservar)', v);
    v := pg_temp.erro_de('select public._agenda_porque_da_os(null, date ''2026-10-29'', now())');
    v_res := pg_temp.ok(v_res, 'C4n sem a OS: 22004', v like '22004 %', v);
    -- C4o: quem marcou é a ação também: a alocação do motor criada por uma ação do assistente (origens_do_dono) é sua
    perform pg_temp.os_extra('210', 'Jair', 1, '[]'::jsonb);
    insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, alocacoes_canceladas, payee_id, antes, depois,
                                     texto, desfazivel_ate)
    values (md5('7g:p3:acao:jair')::uuid, pg_temp.em(date '2026-10-29', '16:50'), date '2026-10-29', true, 'assistente', 'criar', pg_temp.os('210'), array[pg_temp.os('210')],
            array[md5('7g:p3:aloc:jair')::uuid], '{}', 'bb000000-0000-4000-8000-000000000003', '{"alocacoes": [], "fim": null}'::jsonb, '{"alocacoes": [], "fim": null}'::jsonb,
            'Marquei Jair.', pg_temp.em(date '2026-10-30', '16:50'));
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, acao_id, motivos, criado_em, suposicoes)
    values (md5('7g:p3:aloc:jair')::uuid, pg_temp.os('210'), 'bb000000-0000-4000-8000-000000000003', date '2026-11-17', 'tarde', 'turno', 'execucao', 'publicada', 'motor',
            pg_temp.em(date '2026-10-29', '16:50'), md5('7g:p3:acao:jair')::uuid, '[]', pg_temp.em(date '2026-10-29', '16:50'),
            '[{"codigo": "duracao_orcamento", "detalhe": {"dias": 1}}, {"codigo": "uma_pessoa", "detalhe": {}}]'::jsonb);
    p := pg_temp.porque(pg_temp.os('210'));
    v_res := pg_temp.ok(v_res, 'C4o a alocação do motor criada por uma ação do assistente é sua ("você marcou"): quem lê a ação que a criou',
      p ->> 'quem' = 'dono' and p ->> 'texto' = 'Jair (OS-00210): você marcou ter 17/11 com João. Duração: você disse 1 dia.', p::text);
    v := public._agenda_porque_linha(pg_temp.os('210'), jsonb_build_array(md5('7g:p3:aloc:jair')::uuid::text), date '2026-10-29');
    v_res := pg_temp.ok(v_res, 'C4o2 o 1 motivo é a 1ª suposição COM texto (a duração do orçamento, que vai pela fonte, não ocupa o lugar)',
      v = 'você disse 1 dia; 1 pessoa (dupla só quando o serviço pede)', v);
    -- C4m2: a alocação cancelada não dá a linha
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(date '2026-10-29', '16:55'), cancelada_motivo = 'dono'
     where id = 'ffffffff-0000-4000-8000-000000000204';
    v := coalesce(public._agenda_porque_linha(pg_temp.os('204'), '["ffffffff-0000-4000-8000-000000000204"]', date '2026-10-29'), '∅');
    v_res := pg_temp.ok(v_res, 'C4m2 _agenda_porque_linha de uma alocação cancelada: nula', v = '∅', v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.os_extra('204', 'Daniel', 1, jsonb_build_array(jsonb_build_object('payee', 'bb000000-0000-4000-8000-000000000002', 'turnos', 'dia')));
    p := pg_temp.porque(pg_temp.os('204'));
    v := public._agenda_classe_agora(pg_temp.os('204'), date '2026-10-29') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C4d de fora, sem pergunta: o motivo de agora (o texto da carteira, de _agenda_classe_agora)',
      p ->> 'estado' = 'fora' and v is not null and v <> '' and p ->> 'motivo_fora' = v and p ->> 'texto' = 'Daniel (OS-00204) ficou de fora: ' || v || '.'
      and p -> 'quem' = 'null'::jsonb, p::text);
    -- uma pergunta de outra OS (o Antônio), que vem antes na ordem: não é a do Daniel
    perform pg_temp.perg('nao_cabe', 'nao_cabe:c4a', pg_temp.os('201'), date '2026-11-05', pg_temp.em(date '2026-10-29', '08:00'));
    v_q := pg_temp.perg('nao_cabe', 'nao_cabe:c4', pg_temp.os('204'), date '2026-11-20', pg_temp.em(date '2026-10-29', '09:00'));
    v_lin := (select e ->> 'linha' from jsonb_array_elements(public.agenda_perguntas_em_ordem(date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00'))) e
               where e ->> 'id' = v_q::text);
    v_n := (select (e ->> 'n')::int from jsonb_array_elements(public.agenda_decisoes_abertas(pg_temp.em(date '2026-10-29', '17:00'))) e where e ->> 'id' = v_q::text);
    p := pg_temp.porque(pg_temp.os('204'));
    v_res := pg_temp.ok(v_res, 'C4e de fora, com pergunta: o motivo e a linha da pergunta aberta dela, com o número da Decisão de *agenda pendências*',
      v_lin like format('Decisão %s: %%', v_n) and p ->> 'texto' = 'Daniel (OS-00204) ficou de fora: ' || v || '. ' || v_lin, p ->> 'texto');
    -- fora da carteira: uma OS que o cenário cancelou
    p := pg_temp.porque((select so.id from public.service_orders so where so.status = 'cancelled' order by so.service_order_number limit 1));
    v_res := pg_temp.ok(v_res, 'C4f fora da carteira: "Essa OS não está mais na carteira (<status>)."',
      p ->> 'estado' = 'fora_da_carteira' and p ->> 'texto' = 'Essa OS não está mais na carteira (' || public._agenda_status_texto('cancelled') || ').', p::text);
    v := pg_temp.erro_de(format('select public._agenda_porque_da_os(%L, date %L, now())', gen_random_uuid(), '2026-10-29'));
    v_res := pg_temp.ok(v_res, 'C4g OS que não existe: P0002, "Não encontrei esse serviço."', v = 'P0002 Não encontrei esse serviço.', v);
    -- marcada por você e mudada: o *grava* do dono marca o Daniel na sexta; depois o dono passa o Antônio para o dia 12
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'sexta', null, null, 'marca o Daniel pra sexta', date '2026-10-29',
                                       pg_temp.em(date '2026-10-29', '17:00'));
    r := pg_temp.grava(c_admin, date '2026-10-29', '17:05');
    p := pg_temp.porque(pg_temp.os('204'));
    v_res := pg_temp.ok(v_res, 'C4h marcada por você: "você marcou", a duração dita, sem o que contei nem o fecho do gestor',
      (r ->> 'ok')::boolean and p ->> 'quem' = 'dono' and p ->> 'quem_texto' = 'marcado por você' and p ->> 'texto' = 'Daniel (OS-00204): você marcou sex 30/10 com Roberto. Duração: você disse 1 dia.', p::text);
    v := pg_temp.pensei('ligado', date '2026-10-26') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C4h3 em como pensei (a semana de 26/10), a marcada por você diz "(você marcou)"',
      v like E'%\nMarquei: %Daniel (OS-00204) sex 30/10 com Roberto (você marcou) — você disse 1 dia%', v);
    update public.os_planejamento set dias = 3 where service_order_id = pg_temp.os('204');
    p := pg_temp.porque(pg_temp.os('204'));
    v_res := pg_temp.ok(v_res, 'C4h2 a fonte do dono diz os dias que ele disse (os_planejamento), não o tamanho do que está marcado',
      p ->> 'texto' = 'Daniel (OS-00204): você marcou sex 30/10 com Roberto. Duração: você disse 3 dias.', p::text);
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Antônio', 'dia 12', null, null, 'passa o Antônio para o dia 12', date '2026-10-29',
                                       pg_temp.em(date '2026-10-29', '17:10'));
    r := pg_temp.grava(c_admin, date '2026-10-29', '17:15');
    p := pg_temp.porque(pg_temp.os('201'));
    v_res := pg_temp.ok(v_res, 'C4i mudada pelo dono: a última mudança diz o degrau gravado na ação (a data andou)',
      (r ->> 'ok')::boolean and p ->> 'quem' = 'dono' and p ->> 'degrau_texto' = 'a data de fim andou' and p ->> 'texto' like '%Última mudança: a data de fim andou.'
      and p ->> 'texto' not like '%Contei%' and p ->> 'texto' not like '%Se algo estiver errado%' and p ->> 'texto' not like '%: quem você disse.%'
      and jsonb_array_length(p -> 'suposicoes') > 0 and p ->> 'criterio_texto' is not null, p::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- sem o porquê guardado: publicado com modo_porque desligado (a coluna fica nula, como as marcações de antes da 7g)
    perform pg_temp.publicado('desligado');
    p := pg_temp.porque(pg_temp.os('201'));
    v_res := pg_temp.ok(v_res, 'C4j sem o porquê guardado: "Essa marcação é de antes de eu guardar o porquê" e a duração de hoje, sem o que contei',
      p ->> 'estado' = 'marcada' and p -> 'suposicoes' = '[]'::jsonb and p -> 'criterio_texto' = 'null'::jsonb
      and p ->> 'texto' like '%. Essa marcação é de antes de eu guardar o porquê; a duração de hoje: você disse 2 dias.' and p ->> 'texto' not like '%Contei%', p::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C4 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c4$;

-- ── C6. As portas de verdade ─────────────────────────────────────────────────────────────────────────
do $c6$
declare
  v_res     jsonb := '[]'::jsonb;
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tecnico constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_cp      constant text := $s$select (public.agenda_como_pensei(null, date '2026-10-29', now()) ->> 'modo')$s$;
  c_pq      text;
  v         text;
begin
  begin
    update public.agenda_config set modo_explicar = 'ligado' where id;
    c_pq := format($s$select public._agenda_porque_da_os(%L, date '2026-10-29', now()) ->> 'estado'$s$,
                   (select so.id from public.service_orders so order by so.service_order_number limit 1));
    v := pg_temp.como('authenticated', c_tecnico, c_cp) || ' | ' || pg_temp.como('authenticated', c_tecnico, c_pq);
    v_res := pg_temp.ok(v_res, 'C6a o técnico com login: 42501 nas 2 leituras, pela porta de cada uma (não por uma peça de dentro)',
      v = 'erro 42501: Como pensei a agenda é com o administrador ou o financeiro. | erro 42501: O porquê da agenda é com o administrador ou o financeiro.', v);
    v := pg_temp.como('authenticated', c_admin, c_cp) || ' | ' || pg_temp.como('authenticated', c_admin, c_pq);
    v_res := pg_temp.ok(v_res, 'C6b o administrador com login lê as 2', v not like '%erro%' and v like 'ligado | %', v);
    v := pg_temp.como('authenticated', null, c_cp) || ' | ' || pg_temp.como('authenticated', null, c_pq);
    v_res := pg_temp.ok(v_res, 'C6c authenticated sem login: 42501 nas 2, pela porta de cada uma',
      v = 'erro 42501: Como pensei a agenda é com o administrador ou o financeiro. | erro 42501: O porquê da agenda é com o administrador ou o financeiro.', v);
    v := pg_temp.como('service_role', null, c_cp) || ' | ' || pg_temp.como('service_role', null, c_pq);
    v_res := pg_temp.ok(v_res, 'C6d o service_role lê as 2', v not like '%erro%' and v like 'ligado | %', v);
    v := pg_temp.como('anon', null, c_cp) || ' | ' || pg_temp.como('anon', null, c_pq);
    v_res := pg_temp.ok(v_res, 'C6e anon: sem porta (42501 do privilégio) nas 2', v like 'erro 42501:%| erro 42501:%', v);
    v := pg_temp.como('authenticated', c_admin, $s$select public._agenda_porque_linha(gen_random_uuid(), '[]', date '2026-10-29')$s$);
    v_res := pg_temp.ok(v_res, 'C6f as internas: o admin com login não chama _agenda_porque_linha (42501)', v like 'erro 42501:%', v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C6 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c6$;

-- ── C7. A data dita com a relação ────────────────────────────────────────────────────────────────────
do $c7$
declare
  v_res   jsonb := '[]'::jsonb;
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  d29     constant date := date '2026-10-29';
  v       text;
  r       jsonb;
  r_d     jsonb;
  r_s     jsonb;
  r_l     jsonb;
  v_lin_d text;
  v_lin_s text;
  v_dt    jsonb;
begin
  -- C7a: a relação nas palavras do dono (só o texto: roda em qualquer lugar)
  select string_agg(format('[%s | %s] deu %s, esperava %s', t.tr, t.di, coalesce(public._agenda_relacao_dita(t.tr, t.di), '∅'), t.esp), '; ') into v
    from (values ('passa o Daniel para depois de quinta', 'quinta', 'depois'), ('passa o Daniel para depois de quinta', 'depois de quinta', 'depois'),
                 ('marca antes de sexta', 'sexta', 'antes'), ('a partir de segunda', 'segunda', 'a_partir'), ('até dia 27', 'dia 27', 'ate'), ('até o dia 27', '27', 'ate'),
                 ('não antes de quinta', 'quinta', '∅'), ('não antes de quinta', 'antes de quinta', '∅'), ('marca na quinta', 'quinta', '∅'),
                 ('quinta não, depois de quinta', 'quinta', 'depois'), ('depois de quinta, antes de quinta', 'quinta', '∅'), ('só depois do dia 10', 'dia 10', 'depois'),
                 ('depois de amanhã', 'amanhã', '∅'), ('marca o Daniel depois da quinta feira', 'quinta', 'depois'), ('desde terça', 'terça', 'a_partir'),
                 ('após sexta', 'sexta', 'depois'), ('até sexta compra o cabo e marca segunda', 'segunda', '∅'), ('marca de segunda a sexta', 'segunda', '∅'),
                 ('chocolate quinta', 'quinta', '∅'), ('', 'quinta', '∅'), ('marca quinta', '', '∅')) t(tr, di, esp)
   where coalesce(public._agenda_relacao_dita(t.tr, t.di), '∅') <> t.esp;
  v_res := pg_temp.ok(v_res, 'C7a a relação logo antes da data (depois, antes, a partir, até; com "dia"; o dito que já começa por ela); "não" logo antes, relações diferentes, longe da data e sem data: nenhuma', v is null, v);
  if public.agenda_feriado(date '2026-11-02') is null then
    v_res := pg_temp.ok(v_res, 'C7b a data com a relação', true, 'PULADO: sem os feriados (Finados em 02/11)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  -- C7b: a data com a relação aplicada (qui 29/10: quinta = 05/11; sexta = 30/10; segunda = 02/11; dia 27 = 27/11; dia 10 = 10/11)
  select string_agg(format('[%s | %s] deu %s', t.tr, t.di, x.j), '; ') into v
    from (values ('passa o Daniel para depois de quinta', 'quinta', '{"de": "2026-11-06", "ate": "2026-11-06", "texto": "sex 06/11", "relacao": "depois", "relacao_texto": "você disse depois de quinta"}'),
                 ('passa o Daniel para depois de quinta', 'depois de quinta', '{"de": "2026-11-06", "ate": "2026-11-06", "texto": "sex 06/11", "relacao": "depois", "relacao_texto": "você disse depois de quinta"}'),
                 ('marca antes de sexta', 'sexta', '{"de": "2026-10-29", "ate": "2026-10-29", "texto": "qui 29/10", "relacao": "antes", "relacao_texto": "você disse antes de sexta"}'),
                 ('a partir de segunda', 'segunda', '{"de": "2026-11-02", "ate": "2026-11-02", "texto": "seg 02/11", "relacao": "a_partir", "relacao_texto": "você disse a partir de segunda"}'),
                 ('até dia 27', 'dia 27', '{"de": "2026-10-29", "ate": "2026-11-27", "texto": "qui 29/10 a sex 27/11", "relacao": "ate", "relacao_texto": "você disse até o dia 27"}'),
                 ('só depois do dia 10', 'dia 10', '{"de": "2026-11-11", "ate": "2026-11-11", "texto": "qua 11/11", "relacao": "depois", "relacao_texto": "você disse depois do dia 10"}'),
                 ('depois da semana que vem', 'semana que vem', '{"de": "2026-11-09", "ate": "2026-11-09", "texto": "seg 09/11", "relacao": "depois", "relacao_texto": "você disse depois da semana que vem"}'),
                 ('até a semana que vem', 'semana que vem', '{"de": "2026-10-29", "ate": "2026-11-06", "texto": "qui 29/10 a sex 06/11", "relacao": "ate", "relacao_texto": "você disse até a semana que vem"}')) t(tr, di, esp)
    cross join lateral (select public._agenda_data_com_relacao(public._agenda_data_conferida(t.di, t.tr, d29, 'futuro'), t.tr, t.di, d29) as j) x
   where x.j <> public._agenda_data_conferida(t.di, t.tr, d29, 'futuro') || t.esp::jsonb;
  v_res := pg_temp.ok(v_res, 'C7b a data com a relação: depois = o dia útil seguinte; antes = o último antes; a partir = a data; até = de hoje; relacao e relacao_texto', v is null, v);
  select string_agg(format('[%s | %s]', t.tr, t.di), '; ') into v
    from (values ('marca na quinta', 'quinta'), ('não antes de quinta', 'quinta'), ('a quinta, depois de quinta, antes de quinta', 'quinta')) t(tr, di)
   where public._agenda_data_com_relacao(public._agenda_data_conferida(t.di, t.tr, d29, 'futuro'), t.tr, t.di, d29)
         is distinct from public._agenda_data_conferida(t.di, t.tr, d29, 'futuro');
  v_res := pg_temp.ok(v_res, 'C7c sem relação (e com "não antes de"), a data conferida byte a byte, sem relacao nem relacao_texto; a recusa passa igual',
    v is null and public._agenda_data_com_relacao('{"ok": false, "pergunta": "x"}', 'depois de quinta', 'quinta', d29) = '{"ok": false, "pergunta": "x"}'::jsonb
    and public._agenda_data_com_relacao(null, 'depois de quinta', 'quinta', d29) is null, v);
  -- C7i: os outros 7 chamadores e _agenda_data_conferida, no md5 de antes (o corpo sem CR): nenhum recriado
  select string_agg(p.proname, ', ') into v
    from pg_proc p join (values ('_agenda_data_conferida', 'c612818d86dc38807e035ddbff11fe8c'), ('_agenda_rascunho_marco', '0a5a371ba2cf4cba6e69d29c9325c975'),
                                ('_agenda_semana_dita', 'ba44e32e5c33fd881b5b080e3d1bf94f'), ('agenda_propor_dito', '1859d05939f0ba5959222664993d0eba'),
                                ('agenda_rascunho_andamento', '377c6d96ba6037948d3297db52001b0c'), ('agenda_rascunho_disponibilidade', '1b9f8c4fd4592392d8f1f856098eda42'),
                                ('agenda_rascunho_material', '27efbe522e28536b4a2d7691e23016ae'), ('agenda_rascunho_planejar', 'b739144b48cee2076d63beead80d8e56')) m(nome, h)
      on p.proname = m.nome and p.pronamespace = 'public'::regnamespace
   where md5(replace(p.prosrc, chr(13), '')) <> m.h;
  v_res := pg_temp.ok(v_res, 'C7i _agenda_data_conferida e os outros 7 chamadores dela no corpo de antes (md5): a relação só entra em agenda_rascunho_marcar',
    v is null and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%_agenda_data_com_relacao(%') = 1
    and (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%_agenda_data_com_relacao(%') = 'agenda_rascunho_marcar', v);
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    v_res := pg_temp.ok(v_res, 'C7d da frase do dono até o *grava*', true, 'PULADO: sem o cenário do motor (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  -- C7d: da frase do dono até o *grava* (ligado): "passa o Daniel para depois de quinta" (o modelo passa quinta) marca sex 06/11, não a quinta
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.os_extra('204', 'Daniel', 1, jsonb_build_array(jsonb_build_object('payee', 'bb000000-0000-4000-8000-000000000002', 'turnos', 'dia')));
    update public.agenda_config set modo_explicar = 'ligado' where id;
    r_l := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'quinta', null, null, 'passa o Daniel para depois de quinta', d29, pg_temp.em(d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'C7d ligado: o rascunho do dia útil depois de quinta (sex 06/11) e a releitura com "(você disse depois de quinta)"',
      (r_l ->> 'ok')::boolean
      and (select dados ->> 'de' = '2026-11-06' and dados ->> 'ate' = '2026-11-06' and dados ->> 'frase_pronta' like '%(você disse depois de quinta)%'
             from public.agenda_rascunho where chave = 'marcar:' || pg_temp.os('204') and estado = 'aberto')
      and r_l ->> 'releitura' = 'Entendi assim, confere?' || E'\n' || '• Marco na agenda: Daniel (OS-00204), sex 06 e ter 10/11, João (sex 06/11), Roberto (ter 10/11) (você disse depois de quinta).' || E'\n' || 'Responda *grava* ou corrija o que estiver errado.', r_l ->> 'releitura');
    r := pg_temp.grava(c_admin, d29, '17:05');
    v_res := pg_temp.ok(v_res, 'C7e o *grava* marca o Daniel a partir de sex 06/11 (nada na quinta)',
      (r ->> 'ok')::boolean and (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('204') and a.estado in ('publicada', 'fixada')) = date '2026-11-06',
      (select string_agg(a.dia::text || ' ' || a.turno, ', ' order by a.dia, a.turno) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('204') and a.estado in ('publicada', 'fixada')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- C7h: a relação entra antes do que sai da agenda ("(sai de …)"): o Antônio, que já está em ter 03 e qua 04, passa para depois de quinta
  begin
    perform pg_temp.publicado('sombra');
    update public.agenda_config set modo_explicar = 'ligado' where id;
    -- (depois de quinta não cabe: sex 06/11 é o dia, e o Roberto está na reserva do Caio; "depois do dia 9" é ter 10/11)
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Antônio', 'dia 9', null, null, 'passa o Antônio para depois do dia 9', d29, pg_temp.em(d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'C7h a relação entre parênteses logo depois dos dias e de quem vai, antes do "(sai de …)" (o Antônio sai de ter 03 e qua 04/11)',
      (r ->> 'ok')::boolean and r ->> 'releitura' = 'Entendi assim, confere?' || E'\n' || '• Marco na agenda: Antônio (OS-00201), ter 10 a qui 12/11, você abre e fecha, Roberto os 3 dias, João à tarde (você disse depois do dia 9) (sai de ter 03 e qua 04/11).' || E'\n' || 'Responda *grava* ou corrija o que estiver errado.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- C7f: sem relação, "não antes de quinta" e "de terça até quinta" (o até é o p_ate, que não passa pela relação): a quinta, como antes
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.os_extra('204', 'Daniel', 1, jsonb_build_array(jsonb_build_object('payee', 'bb000000-0000-4000-8000-000000000002', 'turnos', 'dia')));
    update public.agenda_config set modo_explicar = 'ligado' where id;
    v := '';
    for r_d in select jsonb_build_object('di', t.di, 'ate', t.ate, 'tr', t.tr, 'de', t.de, 'atd', t.atd)
                 from (values ('quinta', null, 'marca o Daniel na quinta', '2026-11-05', '2026-11-05'), ('quinta', null, 'o Daniel não antes de quinta', '2026-11-05', '2026-11-05'),
                              ('terça', 'quinta', 'marca o Daniel de terça até quinta', '2026-11-03', '2026-11-05')) t(di, ate, tr, de, atd) loop
      r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', r_d ->> 'di', r_d ->> 'ate', null, r_d ->> 'tr', d29, pg_temp.em(d29, '17:00'));
      if not coalesce((r ->> 'ok')::boolean, false) or r::text like '%você disse%'
         or not exists (select 1 from public.agenda_rascunho x where x.chave = 'marcar:' || pg_temp.os('204') and x.estado = 'aberto'
                         and x.dados ->> 'de' = r_d ->> 'de' and x.dados ->> 'ate' = r_d ->> 'atd' and x.dados ->> 'frase_pronta' not like '%você disse%') then
        v := v || format(' [%s | %s] %s', r_d ->> 'tr', r_d ->> 'di', r::text);
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'C7f ligado sem relação: "na quinta", "não antes de quinta" e o até de "de terça até quinta" (o p_ate) não ganham relação; a data é a de antes', v = '', v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- C7g: em sombra e desligado o rascunho é o de antes, byte a byte (o que devolve e a linha gravada), e a data é a quinta; ligado muda (o controle)
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.os_extra('204', 'Daniel', 1, jsonb_build_array(jsonb_build_object('payee', 'bb000000-0000-4000-8000-000000000002', 'turnos', 'dia')));
    update public.agenda_config set modo_explicar = 'desligado' where id;
    begin
      r_d := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'quinta', null, null, 'passa o Daniel para depois de quinta', d29, pg_temp.em(d29, '17:00'));
      v_lin_d := (select (to_jsonb(x) - 'id' - 'criado_em' - 'expira_em')::text from public.agenda_rascunho x where x.chave = 'marcar:' || pg_temp.os('204') and x.estado = 'aberto');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    update public.agenda_config set modo_explicar = 'sombra' where id;
    begin
      r_s := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'quinta', null, null, 'passa o Daniel para depois de quinta', d29, pg_temp.em(d29, '17:00'));
      v_lin_s := (select (to_jsonb(x) - 'id' - 'criado_em' - 'expira_em')::text from public.agenda_rascunho x where x.chave = 'marcar:' || pg_temp.os('204') and x.estado = 'aberto');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    update public.agenda_config set modo_explicar = 'ligado' where id;
    r_l := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'quinta', null, null, 'passa o Daniel para depois de quinta', d29, pg_temp.em(d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'C7g sombra = desligado, byte a byte (o que devolve e a linha do rascunho), com a quinta de antes (05/11) e sem relação; ligado difere (o controle)',
      r_d is not null and v_lin_d is not null and r_s = r_d and v_lin_s = v_lin_d and v_lin_d like '%"de": "2026-11-05"%' and r_d::text not like '%você disse%'
      and r_l is distinct from r_d, coalesce(v_lin_d, '∅'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C7 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c7$;

-- ── C8. O freio ──────────────────────────────────────────────────────────────────────────────────────
do $c8$
declare
  v_res jsonb := '[]'::jsonb;
  v_l   jsonb;
  v     text;
  c_s   constant jsonb := '{"itens": [{"os": "x", "cliente": "Daniel", "de": "2026-11-06", "ate": "2026-11-06", "pessoas": "Roberto", "dias": 1, "fonte": "orcamento"},
                                      {"os": "y", "cliente": "Elisa", "de": "2026-11-12", "ate": "2026-11-13", "pessoas": "João", "dias": 2, "fonte": "dono"}],
                           "reservas": [{"os": "z", "cliente": "Caio", "de": "2026-11-05", "ate": "2026-11-10", "pessoas": "Roberto"}], "puxar": [{"os": "w"}]}';
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C8 o freio', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    -- o freio de produção: o gestor ligado e freado
    update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = true where id;
    update public.agenda_gestor_dia set sombra = '{}'::jsonb where sombra <> '{}'::jsonb;
    v_l := pg_temp.pensei('ligado');
    v := v_l ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C8a com o freio, a 1ª linha diz *gestor, só propor*; sem a conta do gestor, "Eu marcaria: ainda não fiz a conta" logo depois do Marquei',
      split_part(v, E'\n', 1) = 'Você pediu *gestor, só propor*: eu só sugiro.' and split_part(v, E'\n', 2) = 'Como pensei a semana de 02 a 06/11:'
      and split_part(v, E'\n', 3) like 'Marquei: %' and split_part(v, E'\n', 4) = 'Eu marcaria: ainda não fiz a conta (faço todo dia útil no fim da tarde).', v);
    insert into public.agenda_gestor_dia (dia, calculado_em, modos, sombra) values (date '2026-10-29', pg_temp.em(date '2026-10-29', '16:45'), '{}', c_s)
    on conflict (dia) do update set sombra = excluded.sombra;
    -- uma conta mais velha (qua 28/10), com nada: vale a mais nova
    insert into public.agenda_gestor_dia (dia, calculado_em, modos, sombra) values (date '2026-10-28', pg_temp.em(date '2026-10-28', '16:45'), '{}', '{"itens": [], "reservas": []}')
    on conflict (dia) do update set sombra = excluded.sombra;
    v := pg_temp.pensei('ligado') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C8b o "Eu marcaria" da conta mais nova (a de hoje, não a de qua 28/10): só o que toca a semana (o item da sex 06/11 e a reserva de qui 05 a ter 10/11; o de 12/11 e o puxar ficam fora)',
      split_part(v, E'\n', 4) = 'Eu marcaria:' and split_part(v, E'\n', 5) = '• Daniel: sex 06/11, Roberto — 1 dia (estimativa minha).'
      and split_part(v, E'\n', 6) = '• Caio: reservaria qui 05 a ter 10/11, Roberto.' and v not like '%Elisa%', v);
    update public.agenda_gestor_dia set sombra = '{}'::jsonb where dia = date '2026-10-29';
    insert into public.agenda_gestor_dia (dia, calculado_em, modos, sombra) values (date '2026-10-28', pg_temp.em(date '2026-10-28', '16:45'), '{}', '{"itens": [], "reservas": []}')
    on conflict (dia) do update set sombra = excluded.sombra;
    v := pg_temp.pensei('ligado') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C8c a conta de outro dia, sem nada na semana: "Eu marcaria (pela conta de qua 28/10): nada nessa semana."',
      split_part(v, E'\n', 4) = 'Eu marcaria (pela conta de qua 28/10): nada nessa semana.', v);
    v := pg_temp.pensei('sombra') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C8d em sombra com o freio: a 1ª linha do freio e "Em teste: " antes de "Como pensei"',
      split_part(v, E'\n', 1) = 'Você pediu *gestor, só propor*: eu só sugiro.' and split_part(v, E'\n', 2) = 'Em teste: Como pensei a semana de 02 a 06/11:', v);
    update public.agenda_config set gestor_so_propor = false where id;
    v_l := pg_temp.pensei('ligado');
    v := v_l ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C8e sem o freio (o gestor marca): nem a 1ª linha nem o "Eu marcaria", e o objeto sem eu_marcaria',
      v like 'Como pensei a semana de 02 a 06/11:%' and v not like '%Você pediu%' and v not like '%Eu marcaria%' and not v_l ? 'eu_marcaria', v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- nada publicado, com o freio: "Marquei: nada ainda" nunca sai sozinho
    execute current_setting('agenda_teste.cenario_motor');
    update public.agenda_config set modo_proposta = 'ligado', modo_marcar_sozinho = 'ligado', gestor_so_propor = true where id;
    update public.agenda_gestor_dia set sombra = '{}'::jsonb where sombra <> '{}'::jsonb;
    insert into public.agenda_gestor_dia (dia, calculado_em, modos, sombra) values (date '2026-10-29', pg_temp.em(date '2026-10-29', '16:45'), '{}', c_s)
    on conflict (dia) do update set sombra = excluded.sombra;
    v_l := pg_temp.pensei('ligado');
    v := v_l ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C8f nada marcado com o freio: "Marquei: nada ainda nessa semana." e logo depois o que eu marcaria (R9.6, R9.12-9)',
      split_part(v, E'\n', 3) = 'Marquei: nada ainda nessa semana.' and split_part(v, E'\n', 4) = 'Eu marcaria:'
      and v_l #> '{eu_marcaria,linhas}' = '["• Daniel: sex 06/11, Roberto — 1 dia (estimativa minha).", "• Caio: reservaria qui 05 a ter 10/11, Roberto."]'::jsonb
      and v_l #>> '{eu_marcaria,conta_de}' = '2026-10-29', v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C8 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c8$;

-- ── C9. Preciso de você: o número é o da Decisão ─────────────────────────────────────────────────────
do $c9$
declare
  v_res jsonb := '[]'::jsonb;
  v_l   jsonb;
  v     text;
  v_da  jsonb;
  v_ord uuid[];
  v_q   uuid[] := '{}';
  v_esc uuid;
  e     jsonb;
  v_ruim text := '';
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C9 Preciso de você', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.os_extra('204', 'Daniel', 1, '[]'::jsonb);
    -- 2 críticas (a 2ª mais antiga, mas perde depois), 1 não crítica e 1 já escolhida
    v_q := v_q || pg_temp.perg('nao_cabe', 'nao_cabe:c9a', pg_temp.os('204'), date '2026-11-20', pg_temp.em(date '2026-10-29', '10:00'));
    v_q := v_q || pg_temp.perg('nao_cabe', 'nao_cabe:c9b', pg_temp.os('203'), date '2026-11-25', pg_temp.em(date '2026-10-29', '09:00'));
    v_q := v_q || pg_temp.perg('parada', 'parada:c9', pg_temp.os('201'), null, pg_temp.em(date '2026-10-29', '11:00'));
    v_esc := pg_temp.perg('nao_cabe', 'nao_cabe:c9d', pg_temp.os('202'), date '2026-11-18', pg_temp.em(date '2026-10-29', '08:00'), 1::smallint);
    v_l := pg_temp.pensei('ligado');
    v := v_l ->> 'texto';
    v_da := public.agenda_decisoes_abertas(pg_temp.em(date '2026-10-29', '17:00'));
    v_ord := array(select (y ->> 'id')::uuid from jsonb_array_elements(public.agenda_perguntas_em_ordem(date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00'))) y
                    where (y ->> 'id')::uuid <> v_esc order by (y ->> 'ordem')::int);
    for e in select x from jsonb_array_elements(v_l -> 'precisa') x loop
      if jsonb_typeof(e -> 'n') = 'number' then
        if not exists (select 1 from jsonb_array_elements(v_da) d where d ->> 'id' = e ->> 'id' and (d ->> 'n')::int = (e ->> 'n')::int)
           or e ->> 'linha' not like format('Decisão %s: %%', e ->> 'n') or strpos(v, E'\n· ' || (e ->> 'linha')) = 0 then
          v_ruim := v_ruim || ' numerada ' || (e ->> 'linha');
        end if;
      elsif strpos(v, E'\n• ' || (e ->> 'linha')) = 0 then
        v_ruim := v_ruim || ' sem número ' || (e ->> 'linha');
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'C9a cada linha numerada é "· Decisão N:" com o N de agenda_decisoes_abertas (*agenda pendências*), e a sem número vai com "•"',
      v_ruim = '' and jsonb_array_length(v_l -> 'precisa') = 3
      and (select count(*) from jsonb_array_elements(v_l -> 'precisa') x where jsonb_typeof(x -> 'n') = 'number') = 2
      and (select count(*) from jsonb_array_elements(v_l -> 'precisa') x where jsonb_typeof(x -> 'n') <> 'number') = 1, v_ruim || ' | ' || v);
    v_res := pg_temp.ok(v_res, 'C9b na ordem de agenda_perguntas_em_ordem, sem a já escolhida',
      array(select (x ->> 'id')::uuid from jsonb_array_elements(v_l -> 'precisa') with ordinality t(x, o) order by o) = v_ord[1:3]
      and not exists (select 1 from jsonb_array_elements(v_l -> 'precisa') x where (x ->> 'id')::uuid = v_esc), (v_l -> 'precisa')::text);
    v_res := pg_temp.ok(v_res, 'C9c o mesmo número em *agenda pendências* (_agenda_ver_decisoes): "1" responde a mesma pergunta',
      (select bool_and(strpos(public._agenda_ver_decisoes(date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00')) ->> 'texto', format('Decisão %s: ', x ->> 'n')) > 0)
         from jsonb_array_elements(v_l -> 'precisa') x where jsonb_typeof(x -> 'n') = 'number'), null);
    -- o corte com perguntas: a lista de baixo (Preciso de você) perde primeiro; com o teto 20 letras abaixo do texto inteiro, sai só a última pergunta e a Beatriz
    -- fica em Marquei; com 500, todas as perguntas saem e a linha diz quantas estão em *agenda pendências*
    update public.agenda_config set texto_max = char_length(v_l ->> 'texto') - 20 where id;
    v := pg_temp.pensei('ligado') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C9f o corte começa pelas perguntas (de baixo para cima): a última sai com "(e mais 1 em *agenda pendências*)", a Beatriz fica em Marquei',
      v like E'%\n(e mais 1 em *agenda pendências*)' and v like '%Beatriz (OS-00202)%' and char_length(v) <= char_length(v_l ->> 'texto') - 20
      and (char_length(v) - char_length(replace(v, E'\n· ', ''))) / 3 + (char_length(v) - char_length(replace(v, E'\n• ', ''))) / 3 = 2, v);
    update public.agenda_config set texto_max = 500 where id;
    v := pg_temp.pensei('ligado') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C9g em 500: as perguntas todas saem da lista e a linha diz quantas estão em *agenda pendências* (não "nada por agora")',
      v like E'%\nPreciso de você: 3 perguntas em *agenda pendências*.' and char_length(v) <= 500, v);
    update public.agenda_config set texto_max = 1000 where id;
    update public.agenda_config set como_pensei_perguntas = 2 where id;
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C9d com como_pensei_perguntas = 2: as 2 primeiras e "(e mais 1 em *agenda pendências*)"',
      jsonb_array_length(v_l -> 'precisa') = 2 and v_l ->> 'texto' like E'%\n(e mais 1 em *agenda pendências*)', v_l ->> 'texto');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = any (v_q);
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C9e sem pergunta: "Preciso de você: nada por agora."', v_l ->> 'texto' like E'%\nPreciso de você: nada por agora.' and v_l -> 'precisa' = '[]'::jsonb,
      v_l ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C9 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c9$;

-- ── C10. A folga nos 2 ramos, contra a conta à mão ───────────────────────────────────────────────────
-- A âncora (o comentário de cenario-motor.sql, conta de fora da grade): na semana de 02/11 (seg é Finados) o Roberto espera 8 meios-dias (teto80 = 6) e o João 4
-- (só à tarde; teto80 = 3); você fica fora da equipe. Uso: Roberto 5 de compromisso (A e B) + 3 de reserva (C); João 2 (A).
--   Ramo pessoa (o freio, sem a regra teto_equipe): folga = (8 − 6) + (4 − 3) = 3 meios = 1 dia e meio, 25% de 12; as reservas usam max(0, 8 − 6) + max(0, 2 − 3) = 2 = 1 dia.
--   Ramo equipe (sem o freio, com a regra): teto da equipe = floor(0,8 × 12) = 9; folga = 12 − 9 = 3; as reservas usam max(0, 10 − 9) = 1 = meio dia.
do $c10$
declare
  v_res jsonb := '[]'::jsonb;
  v_l   jsonb;
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C10 a folga', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = true, marcar_sozinho_desde = pg_temp.em(date '2026-10-29', '16:00'),
           marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
     where id;
    -- o Hugo tem uma reserva só em outra semana (sex 13/11): não é das reservas que a folga cita
    perform pg_temp.os_extra('208', 'Hugo', null, '[]'::jsonb);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, reserva_de, estado, origem, publicada_em, motivos, criado_em)
    values (md5('7g:p3:c10:hugo:13')::uuid, pg_temp.os('208'), 'bb000000-0000-4000-8000-000000000003', date '2026-11-13', 'tarde', 'turno', 'reserva', 'teto', 'publicada',
            'motor', pg_temp.em(date '2026-10-29', '16:30'), '[]', pg_temp.em(date '2026-10-29', '16:30'));
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C10a com o freio (sem a chave teto_equipe): Σ(teto100 − teto80) por pessoa e Σ max(0, uso − teto80); a conta à mão',
      not public._agenda_gestor_regra('teto_equipe') and v_l -> 'folga' = '{"ramo": "pessoa", "meios": 3, "usado": 2, "pct": 25, "base": 12}'::jsonb
      and v_l ->> 'texto' like E'%\nFolga: guardei 1 dia e meio da equipe para imprevisto (25% da semana); 1 dia já está com a reserva de Caio.\n%',
      (v_l -> 'folga')::text || ' ' || (v_l ->> 'texto'));
    -- o João acima do que ele vem (3 meios-dias a mais, 2 de manhã): o uso passa da folga, e o "já está" fica na folga (3 meios-dias, não 4)
    perform pg_temp.os_extra('206', 'Fábio', 1, '[]'::jsonb);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, motivos, criado_em)
    select md5('7g:p3:c10:fabio:' || x.d || x.t)::uuid, pg_temp.os('206'), 'bb000000-0000-4000-8000-000000000003', x.d::date, x.t, 'turno', 'execucao', 'publicada', 'motor',
           pg_temp.em(date '2026-10-29', '16:30'), 'dono', '[]', pg_temp.em(date '2026-10-29', '16:30')
      from (values ('2026-11-05', 'manha'), ('2026-11-06', 'manha'), ('2026-11-05', 'tarde')) x(d, t);
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C10h o uso acima da folga: o que já está tomado não passa da folga (1 dia e meio de 1 dia e meio)',
      v_l -> 'folga' = '{"ramo": "pessoa", "meios": 3, "usado": 3, "pct": 25, "base": 12}'::jsonb
      and v_l ->> 'texto' like E'%\nFolga: guardei 1 dia e meio da equipe para imprevisto (25% da semana); 1 dia e meio já está com a reserva de Caio.\n%',
      (v_l -> 'folga')::text || ' ' || (v_l ->> 'texto'));
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(date '2026-10-29', '16:50'), cancelada_motivo = 'dono'
     where service_order_id = pg_temp.os('206') and estado = 'publicada';
    update public.agenda_config set gestor_so_propor = false where id;
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C10b sem o freio, com a regra teto_equipe: Σ teto100 − teto_equipe e max(0, Σ uso − teto_equipe); a conta à mão (as reservas usam outro número)',
      public._agenda_gestor_regra('teto_equipe') and v_l -> 'folga' = '{"ramo": "teto_equipe", "meios": 3, "usado": 1, "pct": 25, "base": 12}'::jsonb
      and v_l ->> 'texto' like E'%\nFolga: guardei 1 dia e meio da equipe para imprevisto (25% da semana); meio dia já está com a reserva de Caio.\n%',
      (v_l -> 'folga')::text || ' ' || (v_l ->> 'texto'));
    v_l := pg_temp.pensei('ligado', date '2027-03-01');
    v_res := pg_temp.ok(v_res, 'C10c a semana fora da grade de agora: a folga diz que a semana ainda não está na grade',
      v_l ->> 'texto' like E'%\nFolga: essa semana ainda não está na grade.\n%' and v_l -> 'folga' = '{"ramo": null}'::jsonb, v_l ->> 'texto');
    -- com o freio, carga 1,0: teto80 = teto100, nenhuma folga; carga 0,5: Roberto 4 e João 2 de teto80, folga 6 (3 dias, 50%), as reservas usam 4 (2 dias, "estão")
    update public.agenda_config set gestor_so_propor = true, carga_max = 1.0 where id;
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C10d carga 1,0: "Folga: nenhuma nessa semana."',
      v_l ->> 'texto' like E'%\nFolga: nenhuma nessa semana.\n%' and v_l -> 'folga' = '{"ramo": "pessoa", "meios": 0, "usado": 0, "pct": 0, "base": 12}'::jsonb,
      (v_l -> 'folga')::text);
    update public.agenda_config set carga_max = 0.5 where id;
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C10e carga 0,5: 3 dias de folga (50%) e "2 dias já estão com a reserva de Caio"',
      v_l ->> 'texto' like E'%\nFolga: guardei 3 dias da equipe para imprevisto (50% da semana); 2 dias já estão com a reserva de Caio.\n%'
      and v_l -> 'folga' = '{"ramo": "pessoa", "meios": 6, "usado": 4, "pct": 50, "base": 12}'::jsonb, (v_l -> 'folga')::text || ' ' || (v_l ->> 'texto'));
    -- a 2ª reserva na semana (o Hugo, qui 05/11 à tarde com o João): "com as reservas de Caio e Hugo", na ordem do 1º dia (empate: o número da OS)
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, reserva_de, estado, origem, publicada_em, motivos, criado_em)
    values (md5('7g:p3:c10:hugo:05')::uuid, pg_temp.os('208'), 'bb000000-0000-4000-8000-000000000003', date '2026-11-05', 'tarde', 'turno', 'reserva', 'teto', 'publicada',
            'motor', pg_temp.em(date '2026-10-29', '16:30'), '[]', pg_temp.em(date '2026-10-29', '16:30'));
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C10g 2 reservas na semana: "2 dias e meio já estão com as reservas de Caio e Hugo"',
      v_l ->> 'texto' like E'%\nFolga: guardei 3 dias da equipe para imprevisto (50% da semana); 2 dias e meio já estão com as reservas de Caio e Hugo.\n%',
      (v_l -> 'folga')::text || ' ' || (v_l ->> 'texto'));
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(date '2026-10-29', '16:50'), cancelada_motivo = 'dono'
     where (service_order_id = pg_temp.os('203') or id = md5('7g:p3:c10:hugo:05')::uuid) and estado in ('publicada', 'fixada');
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C10f sem reserva na semana, o que passa do teto80 é compromisso: "meio dia já está ocupado"',
      v_l ->> 'texto' like E'%\nFolga: guardei 3 dias da equipe para imprevisto (50% da semana); meio dia já está ocupado.\n%', v_l ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C10 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c10$;

-- ── C11. Os riscos ───────────────────────────────────────────────────────────────────────────────────
do $c11$
declare
  v_res jsonb := '[]'::jsonb;
  v_l   jsonb;
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C11 os riscos', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.daniel_marcado();
    update public.os_material set compre_ate = date '2026-11-03', compre_ate_base = '{"prazo_fonte": "fornecedor"}', fornecedor_nome = 'Premel' where id = 'a4000000-0000-4000-8000-000000000203';
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C11a os 3 riscos na ordem da data: o "compre até" (ter 03/11), a suposição do Daniel que não foi o motivo da linha (o local; o 1 motivo é o prazo), a semana cheia do Roberto',
      v_l ->> 'texto' like E'%\nRiscos: compre Cabo de bateria 25mm (Premel) até ter 03/11 para Caio; Daniel — na MP Motorhomes (supus pelo tipo do bem); Roberto está com a semana cheia.\n%'
      and (select string_agg(x ->> 'tipo', ',' order by o) from jsonb_array_elements(v_l -> 'riscos') with ordinality t(x, o)) = 'compre_ate,suposicao,semana_cheia',
      v_l ->> 'texto');
    update public.os_material set compre_ate = date '2026-10-28' where id = 'a4000000-0000-4000-8000-000000000203';
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C11b o "compre até" vencido: "venceu qua 28/10 (compre hoje)"',
      v_l ->> 'texto' like E'%\nRiscos: o "compre até" de Cabo de bateria 25mm (Premel) para Caio venceu qua 28/10 (compre hoje); %', v_l ->> 'texto');
    update public.agenda_config set porque_motivos_max = 2 where id;
    v_l := pg_temp.pensei('ligado');
    v_res := pg_temp.ok(v_res, 'C11c com 2 motivos por linha, o local vai na linha do Daniel e sai dos riscos',
      v_l ->> 'texto' like '%Daniel (OS-00204) qui 05/11 com João — 1 dia pelo orçamento (R$ 2.160 de mão de obra; estimativa minha); Cabo: contei 7 dias úteis de entrega (não sei de quem comprar); na MP Motorhomes (supus pelo tipo do bem)%'
      and not exists (select 1 from jsonb_array_elements(v_l -> 'riscos') x where x ->> 'tipo' = 'suposicao'), v_l ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C11 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c11$;

-- ── C12. A parte que falha ───────────────────────────────────────────────────────────────────────────
do $c12$
declare
  v_res jsonb := '[]'::jsonb;
  v_ok  jsonb;
  v_l   jsonb;
  v_f   text;
  c_q   constant text := $q$ language plpgsql stable set search_path to 'public' as $b$ begin raise exception 'quebrada de propósito (C12)'; end $b$$q$;
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C12 a parte que falha', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.os_extra('204', 'Daniel', 1, '[]'::jsonb);
    v_ok := pg_temp.pensei('ligado');
    foreach v_f in array array['_agenda_painel(p_hoje date) returns jsonb', 'agenda_perguntas_em_ordem(p_hoje date, p_agora timestamp with time zone) returns jsonb',
                               '_agenda_grade_de_agora(p_hoje date) returns jsonb', '_agenda_porque_linha(p_os uuid, p_alocs jsonb, p_hoje date) returns text',
                               '_agenda_gestor_pessoas(p_alocs jsonb) returns text', '_agenda_suposicao_texto(p_codigo text, p_detalhe jsonb) returns text'] loop
      begin
        execute 'create or replace function public.' || v_f || c_q;
        v_l := pg_temp.pensei('ligado');
        v_res := pg_temp.ok(v_res, 'C12 ' || split_part(v_f, '(', 1) || ' falha: incompleto, a parte diz "não consegui ler agora" e as outras linhas são as de antes',
          (v_l ->> 'incompleto')::boolean
          and case split_part(v_f, '(', 1)
                when '_agenda_painel' then v_l -> 'falhas' = '["fora"]' and v_l ->> 'texto' like E'%\nDe fora: não consegui ler agora.\n%'
                when 'agenda_perguntas_em_ordem' then v_l -> 'falhas' = '["precisa"]' and v_l ->> 'texto' like E'%\nPreciso de você: não consegui ler agora.'
                when '_agenda_grade_de_agora' then v_l -> 'falhas' = '["folga"]' and v_l ->> 'texto' like E'%\nFolga: não consegui ler agora.\n%'
                when '_agenda_porque_linha' then v_l -> 'falhas' = '["porque"]'
                     and v_l ->> 'texto' like E'%\nMarquei: Antônio (OS-00201) ter 03 e qua 04/11 com Roberto e João — não consegui ler o porquê agora. Beatriz %'
                     and v_l ->> 'texto' like E'%\nReservei: Caio (OS-00203) qui 05 e sex 06/11 com Roberto, se "Cabo de bateria…" estiver na mão (compre até ter 03/11, fornecedor Premel) — não consegui ler o porquê agora.\n%'
                when '_agenda_suposicao_texto' then v_l -> 'falhas' = '["porque", "riscos"]' and v_l ->> 'texto' like E'%\nRiscos: não consegui ler agora.\n%'
                     and v_l ->> 'texto' like E'%\nMarquei: Antônio (OS-00201) ter 03 e qua 04/11 com Roberto e João — não consegui ler o porquê agora. Beatriz %'
                else v_l -> 'falhas' = '["marcadas", "reservadas"]' and v_l ->> 'texto' like E'%\nMarquei: não consegui ler agora.\n%'
                     and v_l ->> 'texto' like E'%\nReservei: não consegui ler agora.\n%' end
          and (select count(*) from unnest(string_to_array(v_l ->> 'texto', E'\n')) x where x not like '%não consegui ler%' and strpos(v_ok ->> 'texto', x) = 0) = 0,
          v_l ->> 'texto');
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
    end loop;
    -- o porquê que falha só numa marcada (o Antônio): a falha fica registrada pela parte das marcadas, mesmo com as reservas lidas
    begin
      execute $q$create or replace function public._agenda_porque_linha(p_os uuid, p_alocs jsonb, p_hoje date) returns text language plpgsql stable set search_path to 'public'
                 as $b$ begin if p_os = '05000000-0000-4000-8000-000000000201' then raise exception 'quebrada de propósito (C12)'; end if; return 'lida'; end $b$$q$;
      v_l := pg_temp.pensei('ligado');
      v_res := pg_temp.ok(v_res, 'C12 o porquê de uma marcada só falha: incompleto, "falhas" com porque, o item diz que não conseguiu ler o porquê e os outros têm o deles',
        (v_l ->> 'incompleto')::boolean and v_l -> 'falhas' = '["porque"]'
        and v_l ->> 'texto' like E'%\nMarquei: Antônio (OS-00201) ter 03 e qua 04/11 com Roberto e João — não consegui ler o porquê agora. Beatriz (OS-00202) qui 05/11 com Roberto — lida.\n%',
        v_l ->> 'texto');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- o "Eu marcaria" que falha (com o freio e a conta do gestor): a linha dele diz que não conseguiu ler, e o resto fica
    update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = true where id;
    insert into public.agenda_gestor_dia (dia, calculado_em, modos, sombra) values (date '2026-10-29', pg_temp.em(date '2026-10-29', '16:45'), '{}',
      '{"itens": [{"os": "x", "cliente": "Daniel", "de": "2026-11-06", "ate": "2026-11-06", "pessoas": "Roberto", "dias": 1, "fonte": "orcamento"}]}')
    on conflict (dia) do update set sombra = excluded.sombra;
    v_ok := pg_temp.pensei('ligado');
    begin
      execute 'create or replace function public._agenda_gestor_faixa(p_de date, p_ate date) returns text' || c_q;
      v_l := pg_temp.pensei('ligado');
      v_res := pg_temp.ok(v_res, 'C12 _agenda_gestor_faixa falha (com o freio): incompleto, "Eu marcaria: não consegui ler agora." e as outras linhas são as de antes',
        (v_l ->> 'incompleto')::boolean and v_l -> 'falhas' = '["eu_marcaria"]' and v_l ->> 'texto' like E'%\nEu marcaria: não consegui ler agora.\n%'
        and v_ok ->> 'texto' like E'%\nEu marcaria:\n• Daniel: sex 06/11, Roberto — 1 dia (estimativa minha).\n%'
        and (select count(*) from unnest(string_to_array(v_l ->> 'texto', E'\n')) x where x not like '%não consegui ler%' and strpos(v_ok ->> 'texto', x) = 0) = 0,
        v_l ->> 'texto');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C12 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c12$;

-- ── C13. As cópias ───────────────────────────────────────────────────────────────────────────────────
do $c13$
declare
  v_res  jsonb := '[]'::jsonb;
  v_mig  text := replace(coalesce(current_setting('agenda_teste.mig_como_pensei_fase7g', true), ''), chr(13), '');
  v_l    text[];
  v_fora text[] := '{}';
  v_den  boolean := false;
  x      text;
  v      text;
begin
  -- a viva, tirados os blocos -- FASE 7g: (7g P3 … -- FASE 7g: fim, é a da origem (20261025100400:761, md5 do R9.1)
  v_l := string_to_array((select replace(p.prosrc, chr(13), '') from pg_proc p where p.oid = 'public.agenda_rascunho_marcar(uuid, text, text, text, text, text, text, date, timestamptz)'::regprocedure), E'\n');
  foreach x in array v_l loop
    if not v_den and x ~ '^\s*-- FASE 7g: \(7g P3' then v_den := true; continue; end if;
    if v_den and x ~ '^\s*-- FASE 7g: fim' then v_den := false; continue; end if;
    continue when v_den;
    v_fora := v_fora || x;
  end loop;
  v_res := pg_temp.ok(v_res, 'C13a agenda_rascunho_marcar sem os blocos da 7g é a da origem (md5 d73ebf1c…, o do R9.1), e os blocos existem',
    md5(array_to_string(v_fora, E'\n')) = 'd73ebf1c9f55537b5ad20887bb144d39' and cardinality(v_fora) < cardinality(v_l), md5(array_to_string(v_fora, E'\n')));
  if v_mig = '' then
    v_res := pg_temp.ok(v_res, 'C13b as funções da migration', true, 'PULADO: sem agenda_teste.mig_como_pensei_fase7g (rode pela bancada)');
  else
    select string_agg(m[1], ',' order by m[1] collate "C") into v from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
    v_res := pg_temp.ok(v_res, 'C13b a migration cria as 6 novas e recria só agenda_rascunho_marcar (nem _agenda_data_conferida nem os outros 7 chamadores)',
      v = '_agenda_data_com_relacao,_agenda_porque_da_os,_agenda_porque_fonte,_agenda_porque_linha,_agenda_relacao_dita,agenda_como_pensei,agenda_rascunho_marcar', v);
  end if;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C13 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c13$;

-- ── C14. O peso ──────────────────────────────────────────────────────────────────────────────────────
do $c14$
declare
  v_res jsonb := '[]'::jsonb;
  v_c0  jsonb;
  v_c1  jsonb;
  v_l   jsonb;
  v_m   jsonb;
  v     text;
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C14 o peso', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    begin
      set local track_functions = 'all';
    exception when others then
      perform pg_temp.gravar(pg_temp.ok('[]', 'C14 o peso', true, 'PULADO: sem permissão para track_functions (rode pela bancada)'));
      return;
    end;
    perform pg_temp.publicado('sombra');
    update public.agenda_config set modo_explicar = 'ligado' where id;
    v_c0 := jsonb_build_object('painel', pg_temp.chamadas('_agenda_painel'), 'grade', pg_temp.chamadas('_agenda_grade_de_agora'), 'classe', pg_temp.chamadas('_agenda_classe_agora'),
                               'meios', pg_temp.chamadas('agenda_meios_da_os'), 'fonte', pg_temp.chamadas('_agenda_porque_fonte'));
    v_l := public.agenda_como_pensei(null, date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00'));
    v_c1 := jsonb_build_object('painel', pg_temp.chamadas('_agenda_painel'), 'grade', pg_temp.chamadas('_agenda_grade_de_agora'), 'classe', pg_temp.chamadas('_agenda_classe_agora'),
                               'meios', pg_temp.chamadas('agenda_meios_da_os'), 'fonte', pg_temp.chamadas('_agenda_porque_fonte'));
    v := (select string_agg(k || ' ' || ((v_c1 ->> k)::int - (v_c0 ->> k)::int), ', ' order by k) from jsonb_object_keys(v_c1) k);
    v_res := pg_temp.ok(v_res, 'C14a como pensei: 1 painel, 1 grade, nenhuma _agenda_classe_agora; agenda_meios_da_os só a do painel (nenhuma da fonte da duração: fonte dono sem viés)',
      v = 'classe 0, fonte 3, grade 1, meios 0, painel 1', v);
    -- R9.3-1: com o viés congelado na marcação (vies_marcado 1,2, a chave do dono), a linha leva a frase do viés da 7e: 1 chamada a mais, a do Antônio
    update public.os_planejamento set vies_marcado = 1.2, vies_marcado_chave = 'dono:c14', marcado_em = pg_temp.em(date '2026-10-29', '16:30') where service_order_id = pg_temp.os('201');
    v_m := public.agenda_meios_da_os(pg_temp.os('201'), date '2026-10-29');
    v_c0 := jsonb_build_object('meios', pg_temp.chamadas('agenda_meios_da_os'));
    v_l := public.agenda_como_pensei(null, date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00'));
    v_c1 := jsonb_build_object('meios', pg_temp.chamadas('agenda_meios_da_os'));
    v_res := pg_temp.ok(v_res, 'C14b com o viés congelado: a frase do viés da 7e (os dois números) na linha do Antônio, com 1 chamada de agenda_meios_da_os a mais',
      v_m ->> 'texto_vies' is not null and (v_c1 ->> 'meios')::int - (v_c0 ->> 'meios')::int = 1
      and (select x ->> 'porque' from jsonb_array_elements(v_l -> 'marcadas') x where (x ->> 'os')::uuid = pg_temp.os('201')) like (v_m ->> 'texto_vies') || '%',
      coalesce(v_m ->> 'texto_vies', '∅') || ' | ' || ((v_c1 ->> 'meios')::int - (v_c0 ->> 'meios')::int));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('C14 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$c14$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
