-- Prova das leituras do aprendizado da Agenda de Produção, Fase 6 (pacote P8; migration 20261029100800): o foco aprendizado
-- do agenda_ver, o cartão "Plano" da OS (a linha do fator de campo em Duração e a presença aprendida) e o foco fornecedores
-- com o prazo medido (spec-fase6 §5.8, §6.2 e §8.3).
-- bancada: depende de 20261029100800
--
--   L1 o foco aprendizado byte a byte: os 7 blocos em teste e ligado (todos os itens) depois das rodadas de qui 29/10 (o dia
--      do plano: a revisão e o planejador) e sex 30/10; o teto (texto_max 1.000: cada bloco encurta pelo fim e o fecho fica);
--      sem nada medido ("As OS: 0 de 6 OS medidas"); desligado (só o fecho); as respostas ao dono por áudio ou não
--      entendidas (30 dias); os dados (os blocos com o n de cada linha); a leitura desligada; o dia que falta
--   L2 o cartão: duracao.campo (em teste, ligado, desligado, a OS concluída) e presenca_dono.aprendida com o texto "pelo que
--      medi"; o resto do cartão igual ao de antes (20261028100600) em todas as OS, byte a byte
--   L3 determinismo: o mesmo foco e o mesmo cartão duas vezes (md5)
--   L4 quem vê: o técnico recebe 42501 no foco (pelo agenda_ver e direto); o anon não executa; a leitura nova é invoker e
--      STABLE, para authenticated e service_role
--   L5 o foco fornecedores: em teste, byte a byte o de antes; com o prazo medido em uso, o grupo "Medido (pelas notas que
--      chegaram):" (a Kamell não some do foco) e o resto igual
--   L6 as cópias: as 3 recriadas só acrescentam os blocos "-- FASE 6:" (× a migration de onde cada uma foi copiada); o
--      cabeçalho e as portas de antes
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase6_leituras.sql
--   L4 roda em qualquer lugar; L6 só com as migrations como texto; o resto só na bancada (a fixture-fase6; fora dela,
--   PULADO). Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.igual(p_res jsonb, p_nome text, p_tem text, p_quer text) returns jsonb language sql immutable as $f$
  select pg_temp.ok(p_res, p_nome, p_tem is not distinct from p_quer,
                    case when p_tem is distinct from p_quer then coalesce(p_tem, '(nulo)') end)
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- A hora de Brasília escrita como se fala: pg_temp.em('2026-10-30 16:05') = timestamptz '2026-10-30 16:05-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;

-- O modo e a lista do aprendizado; todos os itens.
create function pg_temp.modo(p_modo text, p_lista text[] default '{}') returns void language sql as $f$
  update public.agenda_config set modo_aprendizado = p_modo, aprendizado_ligados = p_lista where id
$f$;
create function pg_temp.todos() returns text[] language sql immutable as $f$
  select array['fator', 'mo', 'presenca', 'fornecedor', 'capacidade_dono', 'aviso_cliente', 'revisao']
$f$;
-- A rodada do aprendizado num instante ('2026-10-30 16:05').
create function pg_temp.rodar(p_quando text) returns jsonb language sql as $f$
  select public.agenda_aprender(left(p_quando, 10)::date, pg_temp.em(p_quando))
$f$;
-- O foco aprendizado de sex 30/10 (o texto e o resultado inteiro) e o foco fornecedores.
create function pg_temp.foco() returns jsonb language sql stable as $f$
  select public.agenda_ver(null, null, null, 'aprendizado', null, null, false, date '2026-10-30')
$f$;
create function pg_temp.txt() returns text language sql stable as $f$
  select pg_temp.foco() ->> 'texto'
$f$;
create function pg_temp.forn() returns text language sql stable as $f$
  select public.agenda_ver(null, null, null, 'fornecedores', null, null, false, date '2026-10-30') ->> 'texto'
$f$;
-- O cartão de uma OS em sex 30/10.
create function pg_temp.cartao(p_os uuid) returns jsonb language sql stable as $f$
  select public.os_plano_da_os(p_os, date '2026-10-30')
$f$;

-- Rodar SQL com o papel e o login de alguém (o molde de agenda_fase3_telas.sql); o erro vira "erro <sqlstate>: <texto>".
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- O corpo de uma função numa migration (entre "as $tag$" e o fecho) e a função inteira (do "create or replace" ao fecho).
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
  v_tag text;
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v_tag := (regexp_match(v, E'\nas (\\$[a-z]*\\$)\n'))[1];
  v := substr(v, position(E'\nas ' || v_tag || E'\n' in v) + length(E'\nas ' || v_tag));
  return left(v, position(E'\n' || v_tag || ';' in v));
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- As linhas fora dos blocos "-- FASE 6: … -- FASE 6: fim" (o fim é lido pelo prefixo, como nos testes de cópia de antes).
create function pg_temp.sem_fase6(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 6:' and l !~ '^\s*-- FASE 6: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 6: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- ── L1–L3 e L5 (a fixture-fase6) ────────────────────────────────────────────────────────────────────────
do $l$
declare
  v_res  jsonb := '[]'::jsonb;
  c_gia  constant uuid := '05000000-0000-4000-8000-000000000100';   -- Giancarlo: rv:energia, em andamento, sem plano publicado
  c_ana  constant uuid := '05000000-0000-4000-8000-000000000131';   -- Ana: rv:energia, concluída
  c_nel  constant uuid := 'c1000000-0000-4000-8000-000000000005';   -- o cliente Nelson (as respostas do L1)
  c_cab_teste constant text := 'O que a agenda aprendeu com o que aconteceu (em teste: nada disto muda o plano ainda):';
  c_medidas constant text := 'Medidas: 18 OS (11 valem; 3 sem os dias ditos no início; 1 sem check-in; 1 com os dias só estimados por mim; 1 sem conferência completa; 1 sem diária ligada).';
  c_audio0 constant text := 'Respostas de cliente que foram a você por áudio: nenhuma em 30 dias.';
  c_vigiar_gia constant text := 'Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).';
  v_mig5 text := coalesce(current_setting('agenda_teste.mig_telas_fase5', true), '');
  v_mig4 text := coalesce(current_setting('agenda_teste.mig_leituras_fase4', true), '');
  r   jsonb;
  v_t text;
  v_esp text;
  v_dif text;
  v_n int;
  v_md5 text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' or v_mig5 = '' or v_mig4 = '' then
    insert into _resultado values ('L1–L5 (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 ou as migrations como texto (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.fase6');
  -- as definições de antes, para o byte a byte (rodadas como pg_temp)
  execute replace(pg_temp.inteira(v_mig5, 'os_plano_da_os'), 'create or replace function public.os_plano_da_os(',
                  'create function pg_temp.plano_de_antes(');
  execute replace(pg_temp.inteira(v_mig4, '_agenda_ver_fornecedores'), 'create or replace function public._agenda_ver_fornecedores(',
                  'create function pg_temp.fornecedores_de_antes(');
  update public.agenda_config set modo_leitura = 'ligado', texto_max = 3000 where id;

  -- ── L1e/L1d: nada medido ainda; desligado ──────────────────────────────────────────────────────────
  begin
    perform pg_temp.modo('sombra');
    v_res := pg_temp.igual(v_res, 'L1e em teste e sem nada medido (a rodada ainda não rodou): o fator "As OS: 0 de 6" e "nenhuma OS concluída medida ainda"',
      pg_temp.txt(), c_cab_teste || E'\n'
        || '• As OS: 0 de 6 OS medidas; para perguntar o que falta, uso 1,5× o combinado (padrão).' || E'\n'
        || 'Medidas: nenhuma OS concluída medida ainda.' || E'\n' || c_audio0);
    perform pg_temp.rodar('2026-10-30 16:05');
    perform pg_temp.modo('desligado');
    v_res := pg_temp.igual(v_res, 'L1d desligado: só o cabeçalho e o fecho (o que a sombra gravou não aparece; as medidas sim, a rodada mede sempre)',
      pg_temp.txt(), 'O aprendizado está desligado: meço as OS concluídas, mas não calculo nem uso nada.' || E'\n' || c_medidas || E'\n' || c_audio0);
    v_res := pg_temp.ok(v_res, 'L2b desligado: o cartão sem a linha do fator (duracao.campo nulo) e sem a presença aprendida',
      pg_temp.cartao(c_gia) #> '{duracao,campo}' = 'null'::jsonb and pg_temp.cartao(c_gia) #> '{presenca_dono,aprendida}' = 'null'::jsonb,
      (pg_temp.cartao(c_gia) -> 'duracao')::text);
    -- o resto do cartão, em todas as OS, é o de antes (sem a linha nova e sem a chave nova)
    select count(*), string_agg(so.service_order_number, ', ' order by so.service_order_number) filter (where
             (pg_temp.cartao(so.id) #- '{duracao,campo}' #- '{presenca_dono,aprendida}')::text
             is distinct from pg_temp.plano_de_antes(so.id, date '2026-10-30')::text)
      into v_n, v_dif
      from public.service_orders so where so.service_order_number like 'OS-%';
    v_res := pg_temp.ok(v_res, 'L2e desligado: o cartão de todas as OS é o de antes, byte a byte (fora a linha e a chave novas, nulas)',
      v_dif is null and v_n > 30, format('%s OS; diferentes: %s', v_n, coalesce(v_dif, '—')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── Em teste: as rodadas de qui 29/10 (o dia do plano) e sex 30/10 ──────────────────────────────────
  begin
    perform pg_temp.modo('sombra');
    perform pg_temp.rodar('2026-10-29 16:05');
    perform pg_temp.rodar('2026-10-30 16:05');
    v_t := pg_temp.txt();
    v_esp := c_cab_teste || E'\n'
      || '• Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).' || E'\n'
      || '• Em teste: as OS em motorhome levam até 1,6× o combinado (9 OS); hoje seria 1,6×, e vale 1,5× (padrão).' || E'\n'
      || '• Em teste: as OS levam até 1,5× o combinado (11 OS); hoje seria 1,5×, e vale 1,5× (padrão).' || E'\n'
      || '• Você foi a 3 de 4 OS de energia em motorhome sem estar no plano: em teste, eu contaria com você o dia todo nelas.' || E'\n'
      || '• Kamell: 4 de 6 entregas no prazo; o atraso chega a 2 dias úteis (em teste).' || E'\n'
      || '• Em teste: Kamell leva até 6 dias úteis da saída da nota até a chegada (5 notas); hoje conto 4 dias úteis (padrão).' || E'\n'
      || '• Correa: 4 de 5 entregas medidas.' || E'\n'
      || '• Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano (5 semanas medidas). Hoje marco até 80% da sua semana; pelo medido seria 56% (em teste).' || E'\n'
      || '• Em teste: cada diária rendeu R$ 1.097 de mão de obra (10 OS com diária ligada); para estimar os dias pelo valor uso R$ 764 (padrão).' || E'\n'
      || '• Pontualidade: 5 de 7 OS ficaram prontas até o dia dito primeiro ao cliente; o atraso chega a 2 dias úteis.' || E'\n'
      || '• Avisos de atraso: em 5, o serviço terminou até 2 dias úteis depois do fim que eu disse (em teste: eu daria a faixa com 2 dias úteis a mais).' || E'\n'
      || '• O plano foi cumprido em 52%, 55% e 48% nas últimas 3 semanas (meta 70%). Em teste: eu perguntaria se passo a marcar até 70% da semana de cada pessoa (hoje 80%).' || E'\n'
      || '• Gatilhos de um planejador mais forte: 0 de 4 (11 OS ativas, 4 pessoas); medi 1 de 4 semanas.' || E'\n'
      || c_medidas || E'\n' || c_audio0;
    v_res := pg_temp.igual(v_res, 'L1a em teste, os 7 blocos byte a byte (o fator sem a chave do sistema que repete a fina e sem as que ainda medem; a presença sem a de todas que repete a fina; o Correa medindo; o fecho)',
      v_t, v_esp);
    r := pg_temp.foco();
    v_res := pg_temp.ok(v_res, 'L1g os dados: a rota, o modo, os 7 blocos na ordem, cada linha com o n e o mínimo, as medidas e as respostas',
      r ->> 'rota' = 'aprendizado' and (r ->> 'ok')::boolean and r #>> '{dados,modo}' = 'sombra'
      and jsonb_path_query_array(r -> 'dados', '$.blocos[*].nome')
          = '["fator", "presenca", "fornecedor", "capacidade", "mo", "cliente", "revisao"]'::jsonb
      and jsonb_path_query_array(r -> 'dados', '$.blocos[0].linhas[*].n') = '[7, 9, 11]'::jsonb
      and jsonb_path_query_array(r -> 'dados', '$.blocos[0].linhas[*].n_min') = '[6, 6, 6]'::jsonb
      and jsonb_path_query_array(r -> 'dados', '$.blocos[2].linhas[*].estado') = '["sombra", "sombra", "medindo"]'::jsonb
      and r #> '{dados,medidas}' = '{"total": 18, "validas": 11, "invalidas": {"sem_diaria": 1, "sem_inicio": 1, "dias_sugeridos": 1, "sem_dias_no_inicio": 3, "conferencia_incompleta": 1}}'::jsonb
      and r #> '{dados,respostas_ao_dono}' = '{"dias": 30, "audio": 0, "nao_entendidas": 0}'::jsonb,
      (r -> 'dados')::text);
    -- o teto de sempre (1.000): cada bloco encurta pelo fim ("• e mais N"), e o fecho fica
    update public.agenda_config set texto_max = 1000 where id;
    v_t := pg_temp.txt();
    v_res := pg_temp.ok(v_res, 'L1c com texto_max 1.000: cabe, começa pelo cabeçalho, cada bloco mostra a 1ª linha ("• e mais 2" no fator e nos fornecedores) e o fecho fica inteiro',
      char_length(v_t) <= 1000 and v_t like c_cab_teste || E'\n• Em teste: as OS de energia em motorhome%'
      and v_t like E'%(7 OS); hoje seria 1,7×, e vale 1,5× (padrão).\n• e mais 2\n• Você foi a 3 de 4%'
      and v_t like E'%(em teste).\n• e mais 2\n• Nas últimas 8 semanas%'
      and v_t like '%' || E'\n' || c_medidas || E'\n' || c_audio0
      and v_t not like '%Em teste: as OS em motorhome levam%', v_t);
    update public.agenda_config set texto_max = 3000 where id;

    -- L2: o cartão em teste
    r := pg_temp.cartao(c_gia);
    v_res := pg_temp.ok(v_res, 'L2a em teste: duracao.campo do Giancarlo (rv:energia) = a linha do fator da classe dele; a presença sem a aprendida (em teste nada é usado)',
      r #>> '{duracao,campo}' = c_vigiar_gia and r #> '{presenca_dono,aprendida}' = 'null'::jsonb
      and r #>> '{presenca_dono,texto}' = 'Você abre e fecha (pela regra)', (r -> 'duracao')::text || (r -> 'presenca_dono')::text);
    v_res := pg_temp.ok(v_res, 'L2c a OS concluída (Ana) não tem a linha do fator (nada a perguntar)',
      pg_temp.cartao(c_ana) #> '{duracao,campo}' = 'null'::jsonb, (pg_temp.cartao(c_ana) -> 'duracao')::text);
    select count(*), string_agg(so.service_order_number, ', ' order by so.service_order_number) filter (where
             (pg_temp.cartao(so.id) #- '{duracao,campo}' #- '{presenca_dono,aprendida}')::text
             is distinct from pg_temp.plano_de_antes(so.id, date '2026-10-30')::text)
      into v_n, v_dif
      from public.service_orders so where so.service_order_number like 'OS-%';
    v_res := pg_temp.ok(v_res, 'L2f em teste: o resto do cartão de todas as OS é o de antes, byte a byte',
      v_dif is null and v_n > 30, format('%s OS; diferentes: %s', v_n, coalesce(v_dif, '—')));

    -- L3: determinismo
    v_md5 := md5(pg_temp.foco()::text);
    v_res := pg_temp.ok(v_res, 'L3a o foco aprendizado duas vezes: o mesmo (md5)', md5(pg_temp.foco()::text) = v_md5, v_md5);
    v_md5 := md5(pg_temp.cartao(c_gia)::text);
    v_res := pg_temp.ok(v_res, 'L3b o cartão duas vezes: o mesmo (md5)', md5(pg_temp.cartao(c_gia)::text) = v_md5, v_md5);

    -- L5: o foco fornecedores em teste é o de antes
    v_res := pg_temp.ok(v_res, 'L5a em teste (o prazo da Kamell só calculado), o foco fornecedores é o de antes, byte a byte',
      pg_temp.forn() = pg_temp.fornecedores_de_antes(date '2026-10-30') ->> 'texto', pg_temp.forn());

    -- as respostas que foram ao dono (d8): áudio e não entendida em 30 dias; a de fora da janela e a em teste não contam
    insert into public.agenda_cliente_respostas (client_id, recebida_em, tipo_msg, intencao, efeito, modo, criada_em)
    values (c_nel, pg_temp.em('2026-10-20 10:00'), 'audio', 'audio', 'ao_dono', 'ligado', pg_temp.em('2026-10-20 10:00')),
           (c_nel, pg_temp.em('2026-10-29 18:00'), 'audio', 'audio', 'ao_dono', 'ligado', pg_temp.em('2026-10-29 18:00')),
           (c_nel, pg_temp.em('2026-10-25 09:00'), 'text', 'outro', 'ao_dono', 'ligado', pg_temp.em('2026-10-25 09:00')),
           (c_nel, pg_temp.em('2026-09-29 09:00'), 'audio', 'audio', 'ao_dono', 'ligado', pg_temp.em('2026-09-29 09:00')),
           (c_nel, pg_temp.em('2026-10-28 09:00'), 'audio', 'audio', 'sombra', 'sombra', pg_temp.em('2026-10-28 09:00'));
    v_res := pg_temp.ok(v_res, 'L1f as respostas de cliente que foram ao dono: 2 por áudio e 1 sem eu entender em 30 dias (a de 29/09 e a em teste não contam)',
      pg_temp.txt() like E'%\nRespostas de cliente que foram a você por áudio: 2 em 30 dias; sem eu entender: 1.'
      and pg_temp.foco() #> '{dados,respostas_ao_dono}' = '{"dias": 30, "audio": 2, "nao_entendidas": 1}'::jsonb,
      right(pg_temp.txt(), 120));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── Ligado, todos os itens: as rodadas de qui 29/10 e sex 30/10 ──────────────────────────────────────
  begin
    perform pg_temp.modo('ligado', pg_temp.todos());
    perform pg_temp.rodar('2026-10-29 16:05');
    perform pg_temp.rodar('2026-10-30 16:05');
    v_esp := 'O que a agenda aprendeu com o que aconteceu:' || E'\n'
      || '• As OS de energia em motorhome levam até 1,7× o combinado (7 OS): é o que uso desde qui 29/10.' || E'\n'
      || '• As OS em motorhome levam até 1,6× o combinado (9 OS): é o que uso desde qui 29/10.' || E'\n'
      || '• As OS levam até 1,5× o combinado (11 OS): é o que uso desde qui 29/10.' || E'\n'
      || '• Você foi a 3 de 4 OS sem estar no plano: perguntei se passo a contar com você o dia todo por padrão; espero a sua resposta.' || E'\n'
      || '• Você foi a 3 de 4 OS de energia em motorhome sem estar no plano: conto com você o dia todo nelas desde qui 29/10.' || E'\n'
      || '• Kamell: 4 de 6 entregas no prazo; o atraso chega a 2 dias úteis: conto a chegada 2 dias úteis depois do que o fornecedor diz (desde qui 29/10).' || E'\n'
      || '• Kamell leva até 6 dias úteis da saída da nota até a chegada (5 notas): é o prazo que uso desde qui 29/10.' || E'\n'
      || '• Correa: 4 de 5 entregas medidas.' || E'\n'
      || '• Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano (5 semanas medidas). Hoje marco até 80% da sua semana; pelo medido seriam 56%: a troca espera a sua resposta.' || E'\n'
      || '• Cada diária rendeu R$ 1.097 de mão de obra (10 OS com diária ligada), e hoje uso R$ 764 para estimar os dias pelo valor: a troca espera a sua resposta.' || E'\n'
      || '• Pontualidade: 5 de 7 OS ficaram prontas até o dia dito primeiro ao cliente; o atraso chega a 2 dias úteis.' || E'\n'
      || '• Avisos de atraso: em 5, o serviço terminou até 2 dias úteis depois do fim que eu disse: dou a faixa com 2 dias úteis a mais desde qui 29/10.' || E'\n'
      || '• O plano foi cumprido em 52%, 55% e 48% nas últimas 3 semanas (meta 70%): perguntei se passo a marcar até 70% da semana de cada pessoa (hoje 80%); espera a sua resposta.' || E'\n'
      || '• Gatilhos de um planejador mais forte: 0 de 4 (11 OS ativas, 4 pessoas); medi 1 de 4 semanas.' || E'\n'
      || c_medidas || E'\n' || c_audio0;
    v_res := pg_temp.igual(v_res, 'L1b ligado (todos os itens), os 7 blocos byte a byte: em uso, as perguntas primeiro em cada bloco (a presença no geral antes da da classe)',
      pg_temp.txt(), v_esp);

    -- L2: o cartão ligado — a linha em uso e a presença aprendida com o texto "pelo que medi"
    r := pg_temp.cartao(c_gia);
    v_res := pg_temp.ok(v_res, 'L2d ligado: o Giancarlo com a linha em uso e a presença aprendida ("Você fica o tempo todo (pelo que medi: …)"; o de antes diria "(você disse)")',
      r #>> '{duracao,campo}' = 'As OS de energia em motorhome levam até 1,7× o combinado (7 OS): é o que uso desde qui 29/10.'
      and r -> 'presenca_dono' = jsonb_build_object('valor', 'sempre', 'pela_regra', false,
            'aprendida', 'você foi a 3 de 4 OS de energia em motorhome',
            'texto', 'Você fica o tempo todo (pelo que medi: você foi a 3 de 4 OS de energia em motorhome)')
      and pg_temp.plano_de_antes(c_gia, date '2026-10-30') #>> '{presenca_dono,texto}' = 'Você fica o tempo todo (você disse)',
      (r -> 'duracao')::text || (r -> 'presenca_dono')::text);
    -- o que muda no cartão ligado é só a presença das OS com a aprendida (e a linha nova)
    select string_agg(so.service_order_number, ', ' order by so.service_order_number) filter (where
             ((pg_temp.cartao(so.id) #- '{duracao,campo}') - 'presenca_dono')::text
             is distinct from (pg_temp.plano_de_antes(so.id, date '2026-10-30') - 'presenca_dono')::text
             or ((pg_temp.cartao(so.id) #>> '{presenca_dono,aprendida}') is null
                 and ((pg_temp.cartao(so.id) -> 'presenca_dono') - 'aprendida')::text
                     is distinct from (pg_temp.plano_de_antes(so.id, date '2026-10-30') -> 'presenca_dono')::text)),
           count(*) filter (where pg_temp.cartao(so.id) #>> '{presenca_dono,aprendida}' is not null)
      into v_dif, v_n
      from public.service_orders so where so.service_order_number like 'OS-%';
    v_res := pg_temp.ok(v_res, 'L2g ligado: fora a linha nova e a presença das OS com a aprendida, o cartão de todas as OS é o de antes',
      v_dif is null and v_n >= 1, format('com a aprendida: %s; diferentes: %s', v_n, coalesce(v_dif, '—')));

    -- L5: o prazo medido da Kamell em uso vai ao grupo "Medido"; sem ele, o foco é o de antes
    v_t := pg_temp.forn();
    v_res := pg_temp.ok(v_res, 'L5b com o prazo medido em uso, a Kamell vai a "Medido (pelas notas que chegaram):" logo depois de "Você disse" (antes ela sumia do foco); o resto igual ao de antes',
      v_t like E'%Você disse: nenhum ainda.\nMedido (pelas notas que chegaram):\n• Kamell (Vila Velha/ES): outro estado, 6 dias úteis (medido em 5 notas).\nMeu chute (pela cidade ou pelo nome):\n%'
      and replace(v_t, E'Medido (pelas notas que chegaram):\n• Kamell (Vila Velha/ES): outro estado, 6 dias úteis (medido em 5 notas).\n', '')
          = pg_temp.fornecedores_de_antes(date '2026-10-30') ->> 'texto'
      and (pg_temp.fornecedores_de_antes(date '2026-10-30') ->> 'texto') not like '%Kamell (Vila Velha/ES)%', v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A leitura desligada, o dia que falta e o login sem papel ─────────────────────────────────────────
  begin
    perform pg_temp.modo('sombra');
    perform pg_temp.rodar('2026-10-30 16:05');
    v_res := pg_temp.ok(v_res, 'L2h um login sem "sub" e com o papel authenticated (não vê o aprendizado): o cartão sai sem a linha do fator, sem erro',
      pg_temp.como(null, 'authenticated',
        format($q$select public.os_plano_da_os(%L, date '2026-10-30') #> '{duracao,campo}'$q$, c_gia)) = 'null',
      pg_temp.como(null, 'authenticated', format($q$select (public.os_plano_da_os(%L, date '2026-10-30') -> 'duracao')::text$q$, c_gia)));
    begin
      perform public.agenda_ver(null, null, null, 'aprendizado', null, null, false, null);
      v_t := 'não lançou';
    exception when others then
      v_t := sqlstate;
    end;
    v_res := pg_temp.igual(v_res, 'L1h sem o dia de hoje: 22004', v_t, '22004');
    update public.agenda_config set modo_leitura = 'desligado' where id;
    r := pg_temp.foco();
    v_res := pg_temp.ok(v_res, 'L1i com a leitura desligada, o foco aprendizado diz que a agenda está desligada (como os outros)',
      r ->> 'rota' = 'desligada' and r ->> 'texto' = 'A agenda de produção está desligada agora.', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$l$;

-- ── L4. Quem vê (em qualquer lugar) ─────────────────────────────────────────────────────────────────────
insert into _resultado
select 'L4a o técnico recebe 42501 no foco aprendizado (pelo agenda_ver e direto); o anon não executa a leitura nova',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
         $q$select public.agenda_ver(null, null, null, 'aprendizado', null, null, false, date '2026-10-30')::text$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
         $q$select public._agenda_ver_aprendizado(date '2026-10-30')::text$q$) like 'erro 42501%'
       and pg_temp.como(null, 'anon', $q$select public._agenda_ver_aprendizado(date '2026-10-30')::text$q$) like 'erro 42501%',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
         $q$select public.agenda_ver(null, null, null, 'aprendizado', null, null, false, date '2026-10-30')::text$q$);
insert into _resultado
select 'L4b a leitura nova: invoker, STABLE, search_path fixo; authenticated e service_role executam, anon não',
       not p.prosecdef and p.provolatile = 's' and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
       and has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
       and not has_function_privilege('anon', p.oid, 'execute'),
       format('definer %s, volatilidade %s, %s', p.prosecdef, p.provolatile, p.proconfig)
  from pg_proc p where p.oid = to_regprocedure('public._agenda_ver_aprendizado(date)');
insert into _resultado
select 'L4c as recriadas com as portas de antes: authenticated e service_role, nunca anon; os_plano_da_os e o foco fornecedores definer, agenda_ver invoker',
       bool_and(has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                and not has_function_privilege('anon', p.oid, 'execute')
                and p.prosecdef = (p.proname in ('os_plano_da_os', '_agenda_ver_fornecedores'))
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(p.proname || ':' || p.prosecdef::text, ', ')
  from pg_proc p
 where p.oid in (to_regprocedure('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)'),
                 to_regprocedure('public.os_plano_da_os(uuid, date)'), to_regprocedure('public._agenda_ver_fornecedores(date)'));
insert into _resultado
select 'L4d o foco que não existe lança 22023 e a mensagem cita os 19 (com aprendizado)',
       pg_temp.como(null, 'service_role', $q$select public.agenda_ver(null, null, null, 'aprendeu', null, null, false, date '2026-10-30')::text$q$)
         like 'erro 22023: agenda_ver: foco "aprendeu" não existe (%, clientes ou aprendizado)',
       pg_temp.como(null, 'service_role', $q$select public.agenda_ver(null, null, null, 'aprendeu', null, null, false, date '2026-10-30')::text$q$);

-- ── L6. As cópias (com as migrations como texto) ────────────────────────────────────────────────────────
do $l6$
declare
  v_leit5 text := coalesce(current_setting('agenda_teste.mig_leituras_fase5', true), '');
  v_tela5 text := coalesce(current_setting('agenda_teste.mig_telas_fase5', true), '');
  v_leit4 text := coalesce(current_setting('agenda_teste.mig_leituras_fase4', true), '');
  rc record;
begin
  if v_leit5 = '' or v_tela5 = '' or v_leit4 = '' then
    insert into _resultado values ('L6 as cópias', true, 'PULADO: sem agenda_teste.mig_* (rode pela bancada)');
    return;
  end if;
  for rc in
    select * from (values
      ('agenda_ver', 'public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)', v_leit5, '20261028100500', 1),
      ('os_plano_da_os', 'public.os_plano_da_os(uuid, date)', v_tela5, '20261028100600', 4),
      ('_agenda_ver_fornecedores', 'public._agenda_ver_fornecedores(date)', v_leit4, '20261027100600', 3)
    ) t(nome, assinatura, fonte, versao, blocos)
  loop
    insert into _resultado
    select format('L6a a cópia de %s (de %s) só acrescenta os blocos "-- FASE 6: (P8)" (%s)', rc.nome, rc.versao, rc.blocos),
           pg_temp.sem_fase6(p.prosrc) = pg_temp.sem_fase6(pg_temp.corpo(rc.fonte, rc.nome))
           and cardinality(pg_temp.sem_fase6(p.prosrc)) > 5
           and (select count(*) from regexp_matches(p.prosrc, '-- FASE 6: \(P8\)', 'g')) = rc.blocos
           and (select count(*) from regexp_matches(p.prosrc, '-- FASE 6: fim', 'g'))
               = rc.blocos + (select count(*) from regexp_matches(pg_temp.corpo(rc.fonte, rc.nome), '-- FASE 6: fim', 'g')),
           format('%s linhas fora dos blocos (a fonte: %s); %s blocos do P8', cardinality(pg_temp.sem_fase6(p.prosrc)),
                  cardinality(pg_temp.sem_fase6(pg_temp.corpo(rc.fonte, rc.nome))),
                  (select count(*) from regexp_matches(p.prosrc, '-- FASE 6: \(P8\)', 'g')))
      from pg_proc p where p.oid = rc.assinatura::regprocedure;
  end loop;
end
$l6$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
