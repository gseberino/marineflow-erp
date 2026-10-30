-- Prova da rodada do aprendizado da Agenda de Produção, Fase 6 (pacote P6; migration 20261029100600): a rodada diária, a
-- decisão do dono, o *desfaz aprendizado*, a saúde, a revisão da carga pelo plano cumprido e os gatilhos de um planejador
-- mais forte.
-- bancada: depende de 20261029100950
--
--   R1 a orquestração: uma vez por dia, no 1º tique a partir de aprender_hora; em desligado só mede (nada aprendido, nada
--      perguntado); o passo que falha não derruba a rodada nem os outros passos (e o que ele escreveu antes de falhar sai), e
--      as rodadas das Fases 2 a 5 rodam depois dela como antes; em teste (e ligado sem a lista) tudo fica sombra e nada do que
--      o motor, a vigia, a prontidão e o cliente leem muda (antes × depois da rodada)
--   R2 os estados de cada item pela rodada inteira (ligado, todos os itens), nenhuma mensagem a ninguém, a revisão e o
--      planejador só no dia do plano, e a rodada do dia seguinte sem nada novo
--   R3 a ação no "o que mudou" (_agenda_mudancas, sem recriar) e o *desfaz aprendizado* (o lote, a trava, o "não tenho", o
--      prazo e a volta depois da trava)
--   R4 a decisão (1, 2 e 3; em teste e a opção que não existe recusam) e O RISCO: a carga só muda pela opção 1, com ação
--      desfazível, e nenhuma outra função escreve em agenda_config (pg_proc, as portas e a config antes × depois)
--   R5 a revisão: 3 semanas abaixo de 60% → pergunta 70% (o texto da spec); 2 não; o alto; em teste e sem "revisao" não pergunta
--   R6 o planejador mais forte: 0 de 4 com a fixture; forçado 2 gatilhos por 4 semanas → 1 pergunta, UMA vez (nem aberta, nem
--      respondida, nem depois da trava volta)
--   R7 a saúde: os 6 zeros com a rodada ligada e cada violação forçada aparece
--   R8 as cópias só acrescentam os blocos "-- FASE 6:" (o cabeçalho de cada uma igual) e as portas
--   R9 (correção C1, 20261029100900) a semanal depois do dia do plano quando não rodou (ou com outro modo ou lista); a
--      trava da rodada antes da linha na decisão e no *desfaz*; o índice da rodada
--   R10 (correção C2, 20261029100950) o *desfaz aprendizado <coisa>* por item (e o lote sozinho); o "o que mudou" uma
--       linha por item, sem o sufixo e com a frase uma vez; o botão da tela; sem "*desfaz * volta"; "a última" e o *desfaz*
--       sem nome sem o aprendizado; a pergunta do R$ por diária; as janelas da saúde pelo agenda_config
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase6_rodada.sql
--   Seguro em produção: tudo dentro de begin/rollback. R4a e R8 rodam em qualquer lugar (as cópias só com as migrations como
--   texto); o resto só na bancada (a fixture-fase6; fora dela, PULADO). Nenhuma mensagem sai.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- A hora de Brasília escrita como se fala: pg_temp.em('2026-10-30 16:05') = timestamptz '2026-10-30 16:05-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;

-- O modo e a lista do aprendizado.
create function pg_temp.modo(p_modo text, p_lista text[] default '{}') returns void language sql as $f$
  update public.agenda_config set modo_aprendizado = p_modo, aprendizado_ligados = p_lista where id
$f$;
create function pg_temp.todos() returns text[] language sql immutable as $f$
  select array['fator', 'mo', 'presenca', 'fornecedor', 'capacidade_dono', 'aviso_cliente', 'revisao']
$f$;

-- A rodada num instante ('2026-10-30 16:05').
create function pg_temp.rodar(p_quando text) returns jsonb language sql as $f$
  select public.agenda_aprender(left(p_quando, 10)::date, pg_temp.em(p_quando))
$f$;

create function pg_temp.linha(p_item text, p_chave text) returns public.agenda_aprendizado language sql stable as $f$
  select a from public.agenda_aprendizado a where a.item = p_item and a.chave = p_chave
$f$;
create function pg_temp.pergunta(p_item text, p_chave text) returns public.agenda_perguntas language sql stable as $f$
  select q from public.agenda_perguntas q
   where q.chave = format('aprendizado:%s:%s', p_item, p_chave) and q.estado = 'aberta'
$f$;
-- Os estados de agenda_aprendizado: "item:chave=estado" (sem os fornecedores, pelo nome curto).
create function pg_temp.estados() returns text language sql stable as $f$
  select coalesce(string_agg(a.item || ':' || coalesce(a.detalhe ->> 'nome', a.chave) || '=' || a.estado, ' '
                             order by a.item, coalesce(a.detalhe ->> 'nome', a.chave)), '')
    from public.agenda_aprendizado a
$f$;

-- O motor de sex 30/10 às 16:30, sem gravar: as células de cada item (sem os ids sorteados).
create function pg_temp.motor() returns text language sql as $f$
  select md5(coalesce(string_agg(concat_ws('|', i ->> 'numero', i ->> 'op', i ->> 'tipo',
           (select string_agg(concat_ws(' ', a ->> 'dia', a ->> 'turno', a ->> 'nome', a ->> 'presenca'), ','
                              order by a ->> 'dia', a ->> 'turno', a ->> 'nome', a ->> 'presenca')
              from jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) a)), ';'
           order by i ->> 'numero', i ->> 'op', i ->> 'tipo'), ''))
    from jsonb_array_elements(coalesce(public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null,
                                                            date '2026-10-30', timestamptz '2026-10-30 16:30-03') -> 'itens',
                                       '[]'::jsonb)) i
$f$;
-- O que o motor, a vigia, a prontidão e o cliente leem do aprendizado, de cada OS da carteira, de cada pessoa e de cada
-- fornecedor (o texto do foco fica de fora: ele é do aprendizado).
create function pg_temp.leituras(p_hoje date) returns text language sql stable as $f$
  select md5(concat_ws('#',
    (select string_agg(concat_ws('|', public.os_prontidao(k.service_order_id, p_hoje)::text,
                                 public.os_presenca_do_dono(k.service_order_id)::text,
                                 public.os_duracao_sugerida(k.service_order_id)::text,
                                 public._agenda_cliente_risco(k.service_order_id, p_hoje)::text,
                                 public.agenda_fator_de_campo(k.service_order_id, p_hoje) ->> 'fator'), ';'
                       order by k.service_order_id)
       from public.os_carteira(p_hoje) k),
    (select string_agg(public._agenda_carga_da_pessoa(p.id)::text, ';' order by p.id) from public.payees p),
    (select string_agg(public._agenda_prazo_do_fornecedor(s.id)::text, ';' order by s.id) from public.suppliers s),
    public._agenda_mo_por_diaria_real()::text))
$f$;
-- A config sem o contador do plano (o gatilho das alocações o sobe) e sem o modo/lista (o teste os muda).
create function pg_temp.config() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'versao_plano' - 'modo_aprendizado' - 'aprendizado_ligados' from public.agenda_config c where c.id
$f$;
-- O que uma rodada pode deixar para terceiros: as filas de mensagem.
create function pg_temp.filas() returns text language sql stable as $f$
  select concat_ws('|', (select count(*) from public.whatsapp_send_queue), (select count(*) from public.agenda_cliente_mensagens),
                   (select count(*) from public.agenda_equipe_mensagens), (select count(*) from public.agenda_fornecedor_mensagens))
$f$;

-- O corpo de uma função numa migration (entre "as $tag$" e o fecho).
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

-- As linhas fora dos blocos "-- FASE 6: … -- FASE 6: fim" (o fim é lido pelo prefixo, como nos testes de cópia de antes).
create function pg_temp.sem_fase6(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_c6 boolean := false;  -- CORREÇÃO FASE 6 (C1): dentro de um bloco da correção da Fase 6
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    -- CORREÇÃO FASE 6: (C1) os blocos "-- CORREÇÃO FASE 6: … -- CORREÇÃO FASE 6: fim" também saem (a correção C1 da Fase 6
    -- recria a função copiando a definição mais nova: só acréscimo); o fim é lido pelo prefixo
    if not v_c6 and l ~ '^\s*-- CORREÇÃO FASE 6:' and l !~ '^\s*-- CORREÇÃO FASE 6: fim' then v_c6 := true; continue; end if;
    if v_c6 then
      if l ~ '^\s*-- CORREÇÃO FASE 6: fim' then v_c6 := false; end if;
      continue;
    end if;
    -- CORREÇÃO FASE 6: fim
    -- FASE 7 (7a P4): também os blocos "-- FASE 7: … fim" (agenda_decidir foi recriada de novo em 20261031100300, com o despacho
    -- das perguntas do gestor fora dos da Fase 6; o Q7a de agenda_fase7a_perguntas.sql confere a cópia)
    if not v_bloco and l ~ '^\s*-- FASE [67]:' and l !~ '^\s*-- FASE [67]: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE [67]: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- ── R1. A orquestração ──────────────────────────────────────────────────────────────────────────────────
do $r1$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  r2    jsonb;
  v_x   text;
  v_y   text;
  v_m   text;
  v_err text;
  v_k   int;
  v_ret jsonb := '{}'::jsonb;
  n     int;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('R1 a orquestração (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;

  -- (a) desligado (a linha como nasce): só mede
  begin
    execute current_setting('agenda_teste.fase6');
    r := pg_temp.rodar('2026-10-30 15:59');
    v_res := pg_temp.ok(v_res, 'R1a antes de aprender_hora (15:59) não roda: {rodou: false, cedo}, nenhuma linha de rodada nem medida',
      r ->> 'rodou' = 'false' and r ->> 'cedo' = 'true'
      and not exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender')
      and not exists (select 1 from public.agenda_medidas_os), r::text);
    r := pg_temp.rodar('2026-10-30 16:05');
    v_res := pg_temp.ok(v_res, 'R1b desligado: a rodada roda só a medição (congelar e medir: 18 OS, 11 válidas) e grava a linha dela (rotina aprender, modo desligado)',
      r ->> 'rodou' = 'true' and r ->> 'modo' = 'desligado' and (r ->> 'erros')::int = 0
      and (select array_agg(k order by k) from jsonb_object_keys(r -> 'contagens') k) = array['congelar', 'medir']
      and (r #>> '{contagens,medir,olhadas}')::int = 18 and (r #>> '{contagens,medir,validas}')::int = 11
      and (select count(*) from public.agenda_medidas_os) = 18
      and (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = date '2026-10-30'
                                                              and x.contagens ->> 'modo_aprendizado' = 'desligado') = 1,
      r::text);
    v_res := pg_temp.ok(v_res, 'R1c desligado: nada aprendido, nada perguntado, nenhuma ação do aprendizado',
      not exists (select 1 from public.agenda_aprendizado)
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'aprendizado')
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'aprendizado'), pg_temp.estados());
    r := pg_temp.rodar('2026-10-30 16:20');
    n := (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'aprender');
    r2 := pg_temp.rodar('2026-10-31 16:05');
    v_res := pg_temp.ok(v_res, 'R1d o 2º tique do dia não roda de novo ({ja_rodou}); amanhã roda',
      r ->> 'rodou' = 'false' and r ->> 'ja_rodou' = 'true' and n = 1 and r2 ->> 'rodou' = 'true'
      and (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'aprender') = 2, r::text || ' ' || r2::text);
    v_res := pg_temp.ok(v_res, 'R1e a linha da rodada não confunde as outras rodadas (sem as chaves material.prontas e backlog que a vigia e o fechamento procuram)',
      not exists (select 1 from public.agenda_vigia_rodadas x
                   where x.rotina = 'aprender' and (x.contagens -> 'material' ? 'prontas' or x.contagens ? 'backlog')), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (b) o passo que falha: a rodada segue, os outros passos rodam, o que ele escreveu antes de falhar sai
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('sombra');
    create or replace function public._agenda_aprender_capacidade(p_hoje date, p_agora timestamptz) returns jsonb
    language plpgsql as $x$ begin raise exception 'falha de teste na capacidade'; end $x$;
    create or replace function public._agenda_aprender_mo(p_hoje date, p_agora timestamptz) returns jsonb
    language plpgsql as $x$
    begin
      perform public._agenda_aprendizado_gravar('mo', 'todas', 'todas', 999, 99, '[]'::jsonb, 764, '{}'::jsonb, p_agora);
      raise exception 'falha de teste no mo, depois de gravar';
    end $x$;
    create or replace function public._agenda_aprender_congelar(p_hoje date) returns jsonb
    language plpgsql as $x$ begin raise exception 'falha de teste no congelar'; end $x$;
    r := pg_temp.rodar('2026-10-30 16:05');
    v_res := pg_temp.ok(v_res, 'R1f três passos que falham (congelar, mo e capacidade): a rodada não lança, conta 3 erros e diz quais',
      r ->> 'rodou' = 'true' and (r ->> 'erros')::int = 3
      and (select array_agg(e ->> 'passo' order by e ->> 'passo') from jsonb_array_elements(r -> 'falhas') e)
          = array['capacidade', 'congelar', 'mo'], r -> 'falhas' #>> '{}');
    v_res := pg_temp.ok(v_res, 'R1g os outros passos rodaram (medir, fator, presenca, fornecedor, cliente e, sem a rodada de quinta, a revisão e o planejador: correção C1, item 13) e gravaram em teste; o mo que gravou antes de falhar não deixou nada',
      (select array_agg(k order by k) from jsonb_object_keys(r -> 'contagens') k)
        = array['cliente', 'fator', 'fornecedor', 'medir', 'presenca', 'revisao', 'solver']
      and exists (select 1 from public.agenda_aprendizado a where a.item = 'fator' and a.estado = 'sombra')
      and exists (select 1 from public.agenda_aprendizado a where a.item = 'aviso_folga')
      and not exists (select 1 from public.agenda_aprendizado a where a.item in ('mo', 'capacidade_dono')), pg_temp.estados());
    v_res := pg_temp.ok(v_res, 'R1h cada falha foi a app_error_logs (agenda / aprender:<passo>) e a rodada ficou gravada com as falhas',
      (select count(*) from public.app_error_logs e where e.context = 'agenda'
                                                      and e.action in ('aprender:capacidade', 'aprender:mo', 'aprender:congelar')) = 3
      and (select jsonb_array_length(x.contagens -> 'falhas') from public.agenda_vigia_rodadas x where x.rotina = 'aprender') = 3
      and (select x.erros from public.agenda_vigia_rodadas x where x.rotina = 'aprender') = 3, null);
    -- as rodadas das Fases 2 a 5 depois dela, na mesma transação
    v_err := null;
    foreach v_m in array array['agenda_vigiar', 'agenda_rotina_rodar', 'agenda_material_vigiar', 'agenda_cliente_vigiar'] loop
      begin
        execute format('select public.%I($1, $2)', v_m) into r2 using date '2026-10-30', pg_temp.em('2026-10-30 16:15');
        v_ret := v_ret || jsonb_build_object(v_m, jsonb_typeof(r2));
      exception when others then
        v_err := concat_ws('; ', v_err, v_m || ': ' || sqlerrm);
      end;
    end loop;
    v_res := pg_temp.ok(v_res, 'R1i depois da rodada com falhas, a vigia, a rotina da equipe, a rodada do material e a do cliente rodam sem erro (cada uma devolve o resultado dela; a vigia grava a linha dela)',
      v_err is null and v_ret = '{"agenda_vigiar": "object", "agenda_rotina_rodar": "object", "agenda_material_vigiar": "object", "agenda_cliente_vigiar": "object"}'::jsonb
      and exists (select 1 from public.agenda_vigia_rodadas x where x.p_agora = pg_temp.em('2026-10-30 16:15') and x.rotina = 'vigia'),
      coalesce(v_err, v_ret::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (c) em teste e ligado sem a lista: tudo sombra, nada usado, nada do que o resto lê muda
  for v_k in 1 .. 2 loop
    begin
      execute current_setting('agenda_teste.fase6');
      if v_k = 1 then perform pg_temp.modo('sombra'); else perform pg_temp.modo('ligado', array['revisao']); end if;
      v_x := pg_temp.leituras(date '2026-10-30') || pg_temp.motor();
      r := pg_temp.rodar('2026-10-29 16:05');
      r2 := pg_temp.rodar('2026-10-30 16:05');
      v_y := pg_temp.leituras(date '2026-10-30') || pg_temp.motor();
      v_res := pg_temp.ok(v_res, format('R1j%s %s: a rodada de qui e a de sex gravam tudo em teste (medindo ou sombra; a carga, com "revisao" na lista, pergunta)', v_k,
                                        case v_k when 1 then 'em teste' else 'ligado só com "revisao"' end),
        (r ->> 'erros')::int = 0 and (r2 ->> 'erros')::int = 0
        and not exists (select 1 from public.agenda_aprendizado a
                         where a.estado not in ('medindo', 'sombra') and not (v_k = 2 and a.item = 'carga'))
        and exists (select 1 from public.agenda_aprendizado a where a.item = 'fator' and a.chave = 'rv:energia' and a.estado = 'sombra')
        and not exists (select 1 from public.agenda_acoes a where a.tipo = 'aprendizado')
        and (select count(*) from public.agenda_perguntas q where q.tipo = 'aprendizado') = case v_k when 1 then 0 else 1 end,
        pg_temp.estados());
      v_res := pg_temp.ok(v_res, format('R1k%s %s: o leitor devolve nulo em todas as chaves, e o que o motor, a vigia, a prontidão e o cliente leem (a prontidão, a presença, a duração, o risco e o fator de cada OS da carteira; a carga de cada pessoa; o prazo de cada fornecedor; o R$ por diária; as propostas do motor) é o mesmo antes e depois',
                                        v_k, case v_k when 1 then 'em teste' else 'ligado só com "revisao"' end),
        v_x = v_y and not exists (select 1 from public.agenda_aprendizado a where public._agenda_aprendido(a.item, a.chave) is not null),
        v_x || ' / ' || v_y);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  perform pg_temp.gravar(v_res);
end
$r1$;

-- ── R2. Os estados pela rodada inteira ──────────────────────────────────────────────────────────────────
do $r2$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  v_f0  text;
  n_a   int;
  n_q   int;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('R2 os estados (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', pg_temp.todos());
    v_f0 := pg_temp.filas();
    r := pg_temp.rodar('2026-10-30 16:05');
    v_res := pg_temp.ok(v_res, 'R2a sex 30/10, sem a rodada de quinta (o dia do plano): os 8 passos de todo dia e (correção C1, item 13) a revisão e o planejador, que a quinta não fez; nenhum erro',
      r ->> 'rodou' = 'true' and r ->> 'semanal' = 'true' and (r ->> 'erros')::int = 0
      and (select array_agg(k order by k) from jsonb_object_keys(r -> 'contagens') k)
          = array['capacidade', 'cliente', 'congelar', 'fator', 'fornecedor', 'medir', 'mo', 'presenca', 'revisao', 'solver'],
      r::text);
    v_res := pg_temp.ok(v_res, 'R2b os estados (ligado, todos os itens): o fator 1,7 entra sozinho nas classes com 6 OS (rv:energia, sistema:energia, bem:rv 1,6; todas 1,5 = o padrão), as de barco medindo; o R$ por diária (1.097 × 764) e a capacidade (0,56 × 0,80) perguntam; a presença entra na classe e, no geral, mede (correção C1, item 7: uma classe só); a carga pergunta (a revisão de sexta, item 13); a Kamell entra (atraso 2, prazo 6), a Correa medindo; a folga entra (2); a pontualidade só em teste',
      pg_temp.estados() = 'aviso_folga:todas=em_uso capacidade_dono:dono=pergunta carga:todas=pergunta cliente_pontualidade:todas=sombra fator:barco:motor=medindo fator:bem:barco=medindo fator:bem:rv=em_uso fator:rv:conforto=medindo fator:rv:diagnostico=medindo fator:rv:energia=em_uso fator:sistema:conforto=medindo fator:sistema:diagnostico=medindo fator:sistema:energia=em_uso fator:sistema:motor=medindo fator:todas=em_uso fornecedor_atraso:Correa=medindo fornecedor_atraso:Kamell=em_uso fornecedor_prazo:Kamell=em_uso mo:todas=pergunta presenca:rv:energia=em_uso presenca:sistema:energia=em_uso presenca:todas=medindo solver:gatilhos=medindo',
      pg_temp.estados());
    select count(*) into n_a from public.agenda_acoes a where a.tipo = 'aprendizado';
    select count(*) into n_q from public.agenda_perguntas q where q.tipo = 'aprendizado' and q.estado = 'aberta';
    v_res := pg_temp.ok(v_res, 'R2c 8 ações que entraram sozinhas (origem vigia, executadas, desfazíveis por 24 h) e 3 perguntas críticas (mo, capacidade e a carga; a presença no geral não pergunta mais: correção C1, item 7); o leitor devolve o que entrou',
      n_a = 8 and n_q = 3
      and not exists (select 1 from public.agenda_acoes a
                       where a.tipo = 'aprendizado' and not (a.origem = 'vigia' and a.executada and not a.critica
                                                             and a.desfazivel_ate = pg_temp.em('2026-10-31 16:05')))
      and (select bool_and(q.critica) from public.agenda_perguntas q where q.tipo = 'aprendizado')
      and public._agenda_aprendido('fator', 'rv:energia') = 1.70 and public._agenda_aprendido('aviso_folga', 'todas') = 2
      and public._agenda_aprendido('mo', 'todas') is null,
      format('%s ações, %s perguntas', n_a, n_q));
    v_res := pg_temp.ok(v_res, 'R2d nenhuma mensagem a ninguém (a fila do WhatsApp, as do cliente, da equipe e do fornecedor iguais)',
      pg_temp.filas() = v_f0, v_f0 || ' / ' || pg_temp.filas());
    r := pg_temp.rodar('2026-10-31 16:05');
    v_res := pg_temp.ok(v_res, 'R2e a rodada de sáb 31/10 (o mesmo medido) não troca nada: os mesmos estados, nenhuma ação nem pergunta nova',
      (r ->> 'erros')::int = 0
      and (select count(*) from public.agenda_acoes a where a.tipo = 'aprendizado') = n_a
      and (select count(*) from public.agenda_perguntas q where q.tipo = 'aprendizado') = n_q
      and pg_temp.estados() like 'aviso_folga:todas=em_uso capacidade_dono:dono=pergunta %', pg_temp.estados());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- no dia do plano (qui 29/10): a revisão e o planejador também
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', pg_temp.todos());
    r := pg_temp.rodar('2026-10-29 16:05');
    v_res := pg_temp.ok(v_res, 'R2f qui 29/10 (o dia do plano): os 10 passos; a carga pergunta 70% e o planejador mede (1 de 4 semanas)',
      r ->> 'semanal' = 'true' and (r ->> 'erros')::int = 0
      and (select array_agg(k order by k) from jsonb_object_keys(r -> 'contagens') k)
          = array['capacidade', 'cliente', 'congelar', 'fator', 'fornecedor', 'medir', 'mo', 'presenca', 'revisao', 'solver']
      and (pg_temp.linha('carga', 'todas')).estado = 'pergunta' and (pg_temp.linha('carga', 'todas')).calculado = 0.70
      and (pg_temp.linha('solver', 'gatilhos')).estado = 'medindo',
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r2$;

-- ── R3. O "o que mudou" e o *desfaz aprendizado* ────────────────────────────────────────────────────────
do $r3$
declare
  v_res jsonb := '[]'::jsonb;
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  r     jsonb;
  d     jsonb;
  v_m   jsonb;
  a     public.agenda_aprendizado;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('R3 o desfaz (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', pg_temp.todos());
    r := pg_temp.rodar('2026-10-30 16:05');
    v_m := public._agenda_mudancas(date '2026-10-30', date '2026-10-30', true, true, pg_temp.em('2026-10-30 17:30'));
    -- (correção C2, item 6 e texto 2) uma linha por item (o fator e a presença de várias classes juntos): 5 linhas com as 8
    -- ações; sem o "*desfaz aprendizado* volta." de cada ação (a frase vem uma vez, na 1ª linha: o R10i)
    v_res := pg_temp.ok(v_res, 'R3a o "o que mudou" das 17:30 (_agenda_mudancas) traz as 8 ações do aprendizado, desfazíveis, em 5 linhas (uma por item: correção C2), com o texto da spec (§6.3)',
      (select count(*) from jsonb_array_elements(v_m) e
        where e ->> 'desfazivel' = 'true'
          and exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado' and e -> 'acao_ids' ? x.id::text)) = 5
      and (select sum(jsonb_array_length(e -> 'acao_ids')) from jsonb_array_elements(v_m) e
            where exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado' and e -> 'acao_ids' ? x.id::text)) = 8
      and exists (select 1 from jsonb_array_elements(v_m) e, jsonb_array_elements_text(e -> 'itens') t
                   where t like 'Aprendi com as OS concluídas: as OS de energia em motorhome levam até 1,7× o combinado (7 OS). Passei a usar 1,7× no lugar de 1,5× para perguntar o que falta. Também nas OS de energia (1,7×) e nas em motorhome (1,6×).%')
      and exists (select 1 from jsonb_array_elements(v_m) e, jsonb_array_elements_text(e -> 'itens') t
                   where t like 'Kamell atrasou até 2 dias úteis em 6 entregas: passei a contar a chegada 2 dias úteis depois do que o fornecedor diz.%'),
      v_m::text);

    d := public.agenda_desfazer_dito(c_dono, 'aprendizado', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:40'));
    a := pg_temp.linha('fator', 'rv:energia');
    v_res := pg_temp.ok(v_res, 'R3b *desfaz aprendizado* desfaz o lote da rodada (as 8, tudo ou nada): o valor de antes volta (o padrão), a chave fica travada 28 dias com o medido recusado, e o leitor devolve nulo',
      d ->> 'ok' = 'true' and jsonb_array_length(d -> 'acoes') = 8
      and a.estado = 'travado' and a.em_uso is null and a.travado_valor = 1.70 and a.travado_ate = date '2026-11-27'
      and public._agenda_aprendido('fator', 'rv:energia') is null and public._agenda_aprendido('aviso_folga', 'todas') is null
      and (select count(*) from public.agenda_acoes x where x.tipo = 'aprendizado' and x.desfeita_em is not null) = 8
      and (select count(*) from public.agenda_acoes x where x.tipo = 'desfazer' and x.desfaz_a in
            (select y.id from public.agenda_acoes y where y.tipo = 'aprendizado')) = 8
      and (select count(*) from public.agenda_aprendizado y where y.estado = 'travado') = 8,
      d::text);
    v_res := pg_temp.ok(v_res, 'R3c o texto do desfeito (spec §6.3) e a linha do foco da chave travada',
      d ->> 'texto' like '%Desfeito: as OS de energia em motorhome voltam a 1,5× para perguntar o que falta. Não troco de novo por 28 dias, salvo se o medido mudar muito.%'
      and d ->> 'texto' like '%Desfeito: para Kamell volto a contar a chegada no dia que o fornecedor diz.%'
      and a.texto = 'As OS de energia em motorhome levam até 1,7× o combinado (7 OS); fico com 1,5× até sex 27/11, como você decidiu.',
      d ->> 'texto');
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:41'));
    v_res := pg_temp.ok(v_res, 'R3d de novo: "não tenho" (nada desfeito duas vezes)',
      d ->> 'ok' = 'false' and d ->> 'texto' = 'Não tenho mudança do aprendizado para desfazer agora.', d::text);
    r := pg_temp.rodar('2026-10-31 16:05');
    v_res := pg_temp.ok(v_res, 'R3e a rodada seguinte não troca de novo (a trava): as 8 continuam travadas, nenhuma ação nova',
      (select count(*) from public.agenda_aprendizado y where y.estado = 'travado') = 8
      and (select count(*) from public.agenda_acoes x where x.tipo = 'aprendizado') = 8, pg_temp.estados());
    r := pg_temp.rodar('2026-11-28 16:05');
    v_res := pg_temp.ok(v_res, 'R3f depois da trava (sáb 28/11), o medido volta a entrar sozinho (com uma ação nova)',
      (pg_temp.linha('fator', 'rv:energia')).estado = 'em_uso' and (pg_temp.linha('fator', 'rv:energia')).em_uso = 1.70
      and exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado' and x.dia = date '2026-11-28'
                                                       and x.antes ->> 'chave' = 'rv:energia'), pg_temp.estados());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- o prazo do *desfaz* e um item só pela ação
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', array['fator']);
    r := pg_temp.rodar('2026-10-30 16:05');
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado', 'whatsapp', date '2026-10-31', pg_temp.em('2026-10-31 16:06'));
    v_res := pg_temp.ok(v_res, 'R3g passado o prazo (desfazer_validade, 24 h), não há o que desfazer pelo *desfaz aprendizado*',
      d ->> 'ok' = 'false' and d ->> 'texto' = 'Não tenho mudança do aprendizado para desfazer agora.', d::text);
    d := public.agenda_desfazer((select x.id from public.agenda_acoes x where x.tipo = 'aprendizado' and x.antes ->> 'chave' = 'rv:energia'),
                                c_dono, 'dono', date '2026-10-31', pg_temp.em('2026-10-31 16:06'));
    v_res := pg_temp.ok(v_res, 'R3h e pela ação (agenda_desfazer), o mesmo: passou o prazo',
      d ->> 'ok' = 'false' and d ->> 'texto' = 'Não dá mais para desfazer esse aprendizado: passou o prazo.', d::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r3$;

-- ── R4. A decisão e o risco da escrita de parâmetro ─────────────────────────────────────────────────────
do $r4$
declare
  v_res jsonb := '[]'::jsonb;
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v_esc text;
  v_cha text;
begin
  -- (a) em qualquer lugar: quem escreve em agenda_config e quem chama a escrita da carga
  select string_agg(p.proname, ',' order by p.proname) into v_esc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosrc ~* '(update|insert\s+into|delete\s+from)\s+(public\.)?agenda_config\M';
  select string_agg(p.proname, ',' order by p.proname) into v_cha
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname <> '_agenda_aprendizado_carga' and p.prosrc ~ '_agenda_aprendizado_carga\s*\(';
  insert into _resultado values
    ('R4a O RISCO: só duas funções escrevem em agenda_config — o versao_plano do gatilho das alocações (Fase 2) e _agenda_aprendizado_carga (só carga_max e o atualizado_*)',
     v_esc = '_agenda_alocacoes_versao,_agenda_aprendizado_carga'
     and (select regexp_replace(p.prosrc, '\s+', ' ', 'g') ~ 'update public\.agenda_config set carga_max = p_para, atualizado_em = p_agora, atualizado_por = p_autor where id and carga_max = p_de;'
                 and (select count(*) from regexp_matches(p.prosrc, 'agenda_config', 'g')) = 1
            from pg_proc p where p.oid = 'public._agenda_aprendizado_carga(numeric, numeric, uuid, timestamptz)'::regprocedure)
     and (select regexp_replace(p.prosrc, '\s+', ' ', 'g') ~ 'update public\.agenda_config set versao_plano = versao_plano \+ 1 where id;'
                 and (select count(*) from regexp_matches(p.prosrc, 'agenda_config', 'g')) = 1
            from pg_proc p where p.oid = 'public._agenda_alocacoes_versao()'::regprocedure),
     v_esc),
    ('R4b quem chama a escrita da carga: só a decisão (no ramo da opção 1 da carga) e o *desfaz*; nenhuma porta para ela',
     v_cha = '_agenda_aprendizado_decidir,_agenda_desfazer_aprendizado'
     and (select (regexp_match(p.prosrc, 'if p_opcao = 1 then(.*?)elsif p_opcao = 2 then'))[1] ~ 'if r0\.item = ''carga'' then[^;]*;[^;]*;\s*if not public\._agenda_aprendizado_carga\('
                 and (select count(*) from regexp_matches(p.prosrc, '_agenda_aprendizado_carga\(', 'g')) = 1
            from pg_proc p where p.oid = 'public._agenda_aprendizado_decidir(uuid, smallint, uuid, text, text, date, timestamptz)'::regprocedure)
     and not has_function_privilege('anon', 'public._agenda_aprendizado_carga(numeric, numeric, uuid, timestamptz)', 'execute')
     and not has_function_privilege('authenticated', 'public._agenda_aprendizado_carga(numeric, numeric, uuid, timestamptz)', 'execute')
     and not has_function_privilege('service_role', 'public._agenda_aprendizado_carga(numeric, numeric, uuid, timestamptz)', 'execute'),
     v_cha);

  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('R4 a decisão (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;

  -- (b) as perguntas da rodada de sex 30/10: a do R$ por diária (1) e a da capacidade (2); em teste e a opção que não existe
  declare
    q   public.agenda_perguntas;
    d   jsonb;
    a   public.agenda_aprendizado;
    x   public.agenda_acoes;
    c0  jsonb;
  begin
    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.modo('ligado', pg_temp.todos());
      perform pg_temp.rodar('2026-10-30 16:05');
      c0 := pg_temp.config();
      q := pg_temp.pergunta('mo', 'todas');
      perform pg_temp.modo('sombra');
      d := public.agenda_decidir(q.id, 1::smallint, c_dono, 'whatsapp', '1', date '2026-10-30', pg_temp.em('2026-10-30 17:45'));
      v_res := pg_temp.ok(v_res, 'R4c em teste a decisão não muda nada (a pergunta continua aberta, a linha na pergunta)',
        d ->> 'ok' = 'false' and d ->> 'texto' like 'O aprendizado está em teste%'
        and (select estado from public.agenda_perguntas where id = q.id) = 'aberta'
        and (pg_temp.linha('mo', 'todas')).estado = 'pergunta', d::text);
      perform pg_temp.modo('ligado', pg_temp.todos());
      d := public.agenda_decidir(q.id, 3::smallint, c_dono, 'whatsapp', '3', date '2026-10-30', pg_temp.em('2026-10-30 17:45'));
      v_res := pg_temp.ok(v_res, 'R4d a opção que não existe (a 3 do R$ por diária, com o padrão valendo) recusa e lista as opções',
        d ->> 'ok' = 'false'
        and d ->> 'texto' = 'Essa opção não existe. As opções são: 1) Passo a usar R$ 1.097; 2) Fico com R$ 764.'
        and (select estado from public.agenda_perguntas where id = q.id) = 'aberta', d::text);
      d := public.agenda_decidir(q.id, 1::smallint, c_dono, 'whatsapp', '1', date '2026-10-30', pg_temp.em('2026-10-30 17:45'));
      a := pg_temp.linha('mo', 'todas');
      select * into x from public.agenda_acoes y where y.tipo = 'aprendizado' and y.origem = 'dono';
      v_res := pg_temp.ok(v_res, 'R4e opção 1: o medido passa a valer (R$ 1.097 na duração pelo valor), a pergunta fica respondida e fica a ação crítica com *desfaz* (origem dono); a config não muda',
        d ->> 'ok' = 'true' and a.estado = 'em_uso' and a.em_uso = 1096.83 and public._agenda_mo_por_diaria_real() = 1096.83
        and (select estado = 'respondida' and opcao_escolhida = 1 and respondida_por = c_dono from public.agenda_perguntas where id = q.id)
        and x.critica and x.pergunta_id = q.id and x.executada and x.desfazivel_ate = pg_temp.em('2026-10-31 17:45')
        and x.antes ->> 'em_uso' is null and (x.depois ->> 'em_uso')::numeric = 1096.83
        and pg_temp.config() = c0,
        d::text || ' ' || to_jsonb(a)::text);
      v_res := pg_temp.ok(v_res, 'R4f o texto da opção 1 e a linha do foco',
        d ->> 'texto' = 'Cada diária rendeu R$ 1.097 de mão de obra (10 OS): passei a estimar os dias pelo valor com R$ 1.097 (era R$ 764). *desfaz aprendizado* volta.'
        and x.texto = d ->> 'texto' and a.texto like 'Cada diária rendeu R$ 1.097 de mão de obra (10 OS com diária ligada): é o que uso para estimar os dias pelo valor desde sex 30/10.',
        a.texto);

      q := pg_temp.pergunta('capacidade_dono', 'dono');
      d := public.agenda_decidir(q.id, 2::smallint, c_dono, 'whatsapp', '2', date '2026-10-30', pg_temp.em('2026-10-30 17:46'));
      a := pg_temp.linha('capacidade_dono', 'dono');
      v_res := pg_temp.ok(v_res, 'R4g opção 2 (a capacidade): fico com 80% — a chave travada 28 dias com o medido (0,56), nada em uso, nenhuma ação, a config igual',
        d ->> 'ok' = 'true' and d ->> 'texto' = 'Combinado: fico com 80% da sua semana. Volto a perguntar se o medido mudar muito.'
        and a.estado = 'travado' and a.em_uso is null and a.travado_valor = 0.56 and a.travado_ate = date '2026-11-27'
        and public._agenda_carga_da_pessoa('bb000000-0000-4000-8000-000000000001') = 0.80
        and (select count(*) from public.agenda_acoes y where y.tipo = 'aprendizado' and y.origem = 'dono') = 1
        and pg_temp.config() = c0, d::text);
      perform pg_temp.rodar('2026-10-31 16:05');
      v_res := pg_temp.ok(v_res, 'R4h a rodada seguinte não pergunta de novo a capacidade (travada) nem o R$ por diária (em uso)',
        (pg_temp.linha('capacidade_dono', 'dono')).estado = 'travado' and (pg_temp.linha('mo', 'todas')).estado = 'em_uso'
        and pg_temp.pergunta('capacidade_dono', 'dono') is null and pg_temp.pergunta('mo', 'todas') is null, pg_temp.estados());
      d := public.agenda_decidir(q.id, 1::smallint, c_dono, 'whatsapp', '1', date '2026-10-31', pg_temp.em('2026-10-31 17:00'));
      v_res := pg_temp.ok(v_res, 'R4i a pergunta já respondida não decide de novo',
        d ->> 'ok' = 'false' and d ->> 'texto' = 'Essa pergunta já foi respondida ou resolvida.', d::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;

    -- (c) a opção 3 (volto ao padrão): o fator de rv:energia em uso (1,7) e um medido novo grande (2,4)
    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.modo('ligado', array['fator']);
      perform pg_temp.rodar('2026-10-30 16:05');
      perform public._agenda_aprendizado_gravar('fator', 'rv:energia', 'fina', 2.40, 7, '[]'::jsonb, 1.50, '{}'::jsonb,
                                                pg_temp.em('2026-10-30 16:10'));
      q := pg_temp.pergunta('fator', 'rv:energia');
      v_res := pg_temp.ok(v_res, 'R4j a troca grande (1,7 → 2,4) com o padrão (1,5) longe dos dois: a pergunta tem a opção 3, e o 1,7 continua valendo enquanto espera',
        q.texto = 'Medi as OS de energia em motorhome: levam até 2,4× o combinado (7 OS), e hoje eu uso 1,7×. É uma troca grande. 1) Passo a usar 2,4× (recomendo); 2) Fico com 1,7×; 3) Volto ao padrão.'
        and public._agenda_aprendido('fator', 'rv:energia') = 1.70, q.texto);
      d := public.agenda_decidir(q.id, 3::smallint, c_dono, 'whatsapp', '3', date '2026-10-30', pg_temp.em('2026-10-30 17:45'));
      a := pg_temp.linha('fator', 'rv:energia');
      select * into x from public.agenda_acoes y where y.tipo = 'aprendizado' and y.origem = 'dono';
      v_res := pg_temp.ok(v_res, 'R4k opção 3: volta o padrão (o leitor nulo = 1,5) E trava (o medido 2,4 não volta a perguntar), com a ação crítica e o *desfaz*',
        d ->> 'ok' = 'true'
        and d ->> 'texto' = 'Combinado: as OS de energia em motorhome voltam a 1,5× para perguntar o que falta. Não troco de novo por 28 dias, salvo se o medido mudar muito.'
        and a.estado = 'travado' and a.em_uso is null and a.travado_valor = 2.40 and public._agenda_aprendido('fator', 'rv:energia') is null
        and x.critica and (x.antes ->> 'em_uso')::numeric = 1.70 and x.depois ->> 'em_uso' is null
        and a.texto = 'As OS de energia em motorhome levam até 2,4× o combinado (7 OS); fico com 1,5× até sex 27/11, como você decidiu.',
        d::text || ' ' || a.texto);
      d := public.agenda_desfazer_dito(c_dono, 'aprendizado', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:50'));
      a := pg_temp.linha('fator', 'rv:energia');
      v_res := pg_temp.ok(v_res, 'R4l *desfaz aprendizado* depois da opção 3 (o lote mais novo é a decisão): o 1,7 volta, travado',
        d ->> 'ok' = 'true' and jsonb_array_length(d -> 'acoes') = 1 and a.em_uso = 1.70 and a.estado = 'travado'
        and public._agenda_aprendido('fator', 'rv:energia') = 1.70
        and d ->> 'texto' = 'Desfeito: as OS de energia em motorhome voltam a 1,7× para perguntar o que falta. Não troco de novo por 28 dias, salvo se o medido mudar muito.',
        d::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;

    -- (d) O RISCO: a carga — só pela opção 1, com ação desfazível; a rodada e as outras opções não escrevem na config
    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.modo('ligado', pg_temp.todos());
      c0 := pg_temp.config();
      perform pg_temp.rodar('2026-10-29 16:05');
      q := pg_temp.pergunta('carga', 'todas');
      v_res := pg_temp.ok(v_res, 'R4m a rodada inteira do dia do plano (ligado, todos os itens, a pergunta da carga aberta) não escreve na config',
        q.id is not null and pg_temp.config() = c0, null);
      d := public.agenda_decidir(q.id, 1::smallint, c_dono, 'whatsapp', '1', date '2026-10-29', pg_temp.em('2026-10-29 17:45'));
      select * into x from public.agenda_acoes y where y.tipo = 'aprendizado' and y.pergunta_id = q.id;
      v_res := pg_temp.ok(v_res, 'R4n opção 1 da carga: carga_max 0,80 → 0,70 (e só ela, com o atualizado_*), a ação crítica desfazível guarda as duas, e o motor passa a ler 70% para todos',
        d ->> 'ok' = 'true'
        and (select array_agg(k order by k) from jsonb_each(pg_temp.config()) e(k, v) where c0 -> k is distinct from v)
            = array['atualizado_em', 'atualizado_por', 'carga_max']
        and (select carga_max from public.agenda_config where id) = 0.70
        and x.critica and x.origem = 'dono' and x.desfazivel_ate = pg_temp.em('2026-10-30 17:45')
        and (x.antes ->> 'carga_max')::numeric = 0.80 and (x.depois ->> 'carga_max')::numeric = 0.70
        and public._agenda_carga_da_pessoa('bb000000-0000-4000-8000-000000000002') = 0.70
        and d ->> 'texto' = 'Passei a marcar até 70% da semana de cada pessoa (era 80%), como você decidiu. *desfaz aprendizado* volta.',
        d::text);
      d := public.agenda_desfazer_dito(c_dono, 'aprendizado', 'whatsapp', date '2026-10-29', pg_temp.em('2026-10-29 18:00'));
      v_res := pg_temp.ok(v_res, 'R4o *desfaz aprendizado* volta a carga: carga_max 0,80 (a config como antes, menos o atualizado_*), a chave travada com o 0,70 recusado',
        d ->> 'ok' = 'true' and (select carga_max from public.agenda_config where id) = 0.80
        and (pg_temp.config() - 'atualizado_em' - 'atualizado_por') = (c0 - 'atualizado_em' - 'atualizado_por')
        and (pg_temp.linha('carga', 'todas')).estado = 'travado' and (pg_temp.linha('carga', 'todas')).travado_valor = 0.70
        and d ->> 'texto' = 'Desfeito: volto a marcar até 80% da semana de cada pessoa. Não pergunto de novo por 28 dias, salvo se o plano cumprido mudar.',
        d::text);
      perform public._agenda_aprender_revisao(date '2026-10-29', pg_temp.em('2026-10-29 18:30'));
      v_res := pg_temp.ok(v_res, 'R4p a revisão de novo (o mesmo plano cumprido): a trava segura, sem pergunta nova',
        (pg_temp.linha('carga', 'todas')).estado = 'travado' and pg_temp.pergunta('carga', 'todas') is null
        and (select carga_max from public.agenda_config where id) = 0.80, pg_temp.estados());
      update public.agenda_config set carga_max = 0.75 where id;
      d := public.agenda_desfazer(x.id, c_dono, 'dono', date '2026-10-29', pg_temp.em('2026-10-29 18:40'));
      v_res := pg_temp.ok(v_res, 'R4q o *desfaz* já feito não desfaz de novo (nem escreve na config)',
        d ->> 'ok' = 'false' and (select carga_max from public.agenda_config where id) = 0.75, d::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;

    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.modo('ligado', pg_temp.todos());
      c0 := pg_temp.config();
      perform pg_temp.rodar('2026-10-29 16:05');
      q := pg_temp.pergunta('carga', 'todas');
      d := public.agenda_decidir(q.id, 2::smallint, c_dono, 'whatsapp', '2', date '2026-10-29', pg_temp.em('2026-10-29 17:45'));
      v_res := pg_temp.ok(v_res, 'R4r opção 2 da carga: a config igual, nenhuma ação, a chave travada',
        d ->> 'ok' = 'true' and d ->> 'texto' = 'Combinado: fico com 80%. Volto a perguntar em 28 dias se o plano cumprido continuar assim.'
        and pg_temp.config() = c0 and not exists (select 1 from public.agenda_acoes y where y.pergunta_id = q.id)
        and (pg_temp.linha('carga', 'todas')).estado = 'travado', d::text);
      -- a carga que o dono mudou à mão entre a decisão e o *desfaz*: o *desfaz* não a pisa
      q := null;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;

    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.modo('ligado', pg_temp.todos());
      perform pg_temp.rodar('2026-10-29 16:05');
      q := pg_temp.pergunta('carga', 'todas');
      d := public.agenda_decidir(q.id, 1::smallint, c_dono, 'whatsapp', '1', date '2026-10-29', pg_temp.em('2026-10-29 17:45'));
      update public.agenda_config set carga_max = 0.75 where id;
      d := public.agenda_desfazer_dito(c_dono, 'aprendizado', 'whatsapp', date '2026-10-29', pg_temp.em('2026-10-29 18:00'));
      v_res := pg_temp.ok(v_res, 'R4s a carga mudada à mão depois da decisão (0,75): o *desfaz* recusa e não pisa (fica 0,75)',
        d ->> 'ok' = 'false' and (select carga_max from public.agenda_config where id) = 0.75
        and d ->> 'texto' = 'A parte da semana de cada pessoa mudou depois (hoje 75%): não há o que desfazer nessa mudança.', d::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end;
  perform pg_temp.gravar(v_res);
end
$r4$;

-- ── R5. A revisão da carga ──────────────────────────────────────────────────────────────────────────────
do $r5$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  a     public.agenda_aprendizado;
  q     public.agenda_perguntas;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('R5 a revisão (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('sombra');
    r := public._agenda_aprender_revisao(date '2026-10-30', pg_temp.em('2026-10-30 16:05'));
    a := pg_temp.linha('carga', 'todas');
    v_res := pg_temp.ok(v_res, 'R5a em teste: as 8 semanas medidas (de 31/08 a 19/10), 3 seguidas abaixo de 60% (19/10 48%, 12/10 55%, 05/10 52%) → 70% calculado, nada perguntado',
      a.estado = 'sombra' and a.calculado = 0.70 and a.padrao = 0.80 and a.n = 8 and a.n_min = 3 and r ->> 'gatilho' = 'baixo'
      and a.detalhe ->> 'baixo_seguidas' = '3' and a.detalhe -> 'mostrar' = '[0.5200, 0.5455, 0.4762]'::jsonb
      and not exists (select 1 from public.agenda_perguntas qq where qq.tipo = 'aprendizado'), to_jsonb(a)::text);
    v_res := pg_temp.ok(v_res, 'R5b a linha do foco em teste (spec §6.2: "O plano foi cumprido em 52%, 55% e 48% nas últimas 3 semanas (meta 70%).")',
      a.texto = 'O plano foi cumprido em 52%, 55% e 48% nas últimas 3 semanas (meta 70%). Em teste: eu perguntaria se passo a marcar até 70% da semana de cada pessoa (hoje 80%).',
      a.texto);
    perform pg_temp.modo('ligado', array['fator', 'mo', 'presenca', 'fornecedor', 'capacidade_dono', 'aviso_cliente']);
    perform public._agenda_aprender_revisao(date '2026-10-30', pg_temp.em('2026-10-30 16:06'));
    v_res := pg_temp.ok(v_res, 'R5c ligado sem "revisao" na lista: em teste, sem pergunta',
      (pg_temp.linha('carga', 'todas')).estado = 'sombra' and pg_temp.pergunta('carga', 'todas') is null, null);
    perform pg_temp.modo('ligado', array['revisao']);
    perform public._agenda_aprender_revisao(date '2026-10-30', pg_temp.em('2026-10-30 16:07'));
    q := pg_temp.pergunta('carga', 'todas');
    v_res := pg_temp.ok(v_res, 'R5d com "revisao": a pergunta crítica com o texto da spec (§6.3) e só as opções 1 e 2; a carga não muda',
      q.texto = 'O plano foi cumprido abaixo de 60% em 3 semanas seguidas (52%, 55%, 48%). Recomendo marcar até 70% da semana de cada pessoa (hoje 80%). 1) Passo para 70% (recomendo); 2) Fico com 80%.'
      and q.critica and jsonb_array_length(q.opcoes) = 2 and (select carga_max from public.agenda_config where id) = 0.80
      and (pg_temp.linha('carga', 'todas')).estado = 'pergunta', q.texto);
    v_res := pg_temp.ok(v_res, 'R5e a linha do foco com a pergunta aberta',
      (pg_temp.linha('carga', 'todas')).texto = 'O plano foi cumprido em 52%, 55% e 48% nas últimas 3 semanas (meta 70%): perguntei se passo a marcar até 70% da semana de cada pessoa (hoje 80%); espera a sua resposta.',
      (pg_temp.linha('carga', 'todas')).texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- 2 semanas baixas não bastam: a de 05/10 passa a ter tudo cumprido
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', array['revisao']);
    update public.agenda_alocacoes set resultado = 'cumprido', motivo = null
     where service_order_id between '05000000-0000-4000-8000-000000000147' and '05000000-0000-4000-8000-000000000151'
       and dia between date '2026-10-05' and date '2026-10-09';
    r := public._agenda_aprender_revisao(date '2026-10-30', pg_temp.em('2026-10-30 16:05'));
    a := pg_temp.linha('carga', 'todas');
    v_res := pg_temp.ok(v_res, 'R5f 2 semanas abaixo de 60% (19 e 12/10; a de 05/10 em 100%): a de hoje vale (80%), nenhuma pergunta',
      a.detalhe ->> 'baixo_seguidas' = '2' and a.calculado = 0.80 and a.estado = 'em_uso' and r ->> 'gatilho' is null
      and pg_temp.pergunta('carga', 'todas') is null
      and a.texto = 'O plano foi cumprido em 100%, 55% e 48% nas últimas 3 semanas (meta 70%); marco até 80% da semana de cada pessoa.',
      to_jsonb(a)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- o alto: acima do limite por 4 semanas seguidas (com os limites mudados para a fixture caber)
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', array['revisao']);
    update public.agenda_config set ppc_baixo = 0.30, ppc_alto = 0.45 where id;
    r := public._agenda_aprender_revisao(date '2026-10-30', pg_temp.em('2026-10-30 16:05'));
    q := pg_temp.pergunta('carga', 'todas');
    v_res := pg_temp.ok(v_res, 'R5g o alto (acima de 45% nas 8 semanas, ≥ ppc_alto_semanas 4): pergunta 85% (nunca abaixo da de hoje), com o texto da spec',
      r ->> 'gatilho' = 'alto' and (pg_temp.linha('carga', 'todas')).calculado = 0.85
      and q.texto = 'O plano foi cumprido acima de 45% em 8 semanas seguidas: posso estar marcando pouco. 1) Passo para 85% (recomendo); 2) Fico com 80%.',
      q.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- só a partir do dia do plano (pela rodada; a de depois dele na semana, quando a semanal não rodou, é o R9 da correção C1)
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', array['revisao']);
    perform pg_temp.rodar('2026-10-26 16:05');
    v_res := pg_temp.ok(v_res, 'R5h a rodada de seg 26/10 (antes do dia do plano) não revisa nem mede o planejador',
      pg_temp.linha('carga', 'todas') is null and pg_temp.linha('solver', 'gatilhos') is null, pg_temp.estados());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r5$;

-- ── R6. O planejador mais forte: um aviso só, uma vez ───────────────────────────────────────────────────
do $r6$
declare
  v_res jsonb := '[]'::jsonb;
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  a     public.agenda_aprendizado;
  q     public.agenda_perguntas;
  d     jsonb;
  v_dia date;
  k     int;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('R6 o planejador (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', array['revisao']);
    perform public._agenda_aprender_solver(date '2026-10-29', pg_temp.em('2026-10-29 16:05'));
    a := pg_temp.linha('solver', 'gatilhos');
    v_res := pg_temp.ok(v_res, 'R6a com a fixture: 0 de 4 gatilhos (11 OS ativas, 4 pessoas na semana de 19/10, nenhuma ida curta, nenhum plano descartado; a habilidade não é medível), medindo (1 semana de 4)',
      a.estado = 'medindo' and a.calculado = 0 and a.n = 1 and a.n_min = 4
      and a.detalhe ->> 'os_ativas' = '11' and a.detalhe ->> 'pessoas' = '4' and a.detalhe ->> 'n_valem' = '0'
      and a.detalhe ->> 'habilidade' = 'nao_medivel' and a.detalhe ->> 'semana' = '2026-10-19'
      and a.texto = 'Gatilhos de um planejador mais forte: 0 de 4 (11 OS ativas, 4 pessoas); medi 1 de 4 semanas.', to_jsonb(a)::text);

    -- forçado: 2 gatilhos (mais de 5 OS ativas e de 2 pessoas) por 4 semanas seguidas
    update public.agenda_config set solver_os_ativas = 5, solver_pessoas = 2 where id;
    foreach v_dia in array array[date '2026-10-29', date '2026-11-05', date '2026-11-12'] loop
      perform public._agenda_aprender_solver(v_dia, (v_dia + time '16:05') at time zone 'America/Sao_Paulo');
    end loop;
    v_res := pg_temp.ok(v_res, 'R6b 3 semanas seguidas com 2 gatilhos ainda não perguntam (medindo, 3 de 4)',
      (pg_temp.linha('solver', 'gatilhos')).estado = 'medindo' and (pg_temp.linha('solver', 'gatilhos')).n = 3
      and not exists (select 1 from public.agenda_perguntas qq where qq.chave = 'aprendizado:solver:gatilhos'), pg_temp.estados());
    perform public._agenda_aprender_solver(date '2026-11-19', pg_temp.em('2026-11-19 16:05'));
    q := pg_temp.pergunta('solver', 'gatilhos');
    v_res := pg_temp.ok(v_res, 'R6c a 4ª semana: UMA pergunta crítica, com o texto da spec (§6.3) e só as opções 1 e 2',
      q.texto = 'Há 4 semanas a agenda passa de 5 OS ativas e de 2 pessoas: vale estudar um planejador mais forte. Nada muda sozinho. 1) Quero ver isso (recomendo); 2) Agora não.'
      and q.critica and jsonb_array_length(q.opcoes) = 2
      and (select count(*) from public.agenda_perguntas x where x.chave = 'aprendizado:solver:gatilhos') = 1, q.texto);
    foreach v_dia in array array[date '2026-11-26', date '2026-12-03'] loop
      perform public._agenda_aprender_solver(v_dia, (v_dia + time '16:05') at time zone 'America/Sao_Paulo');
    end loop;
    v_res := pg_temp.ok(v_res, 'R6d as semanas seguintes (com os gatilhos sumindo: sem pessoas no plano) não abrem outra nem fecham a aberta',
      (select count(*) from public.agenda_perguntas x where x.chave = 'aprendizado:solver:gatilhos') = 1
      and (pg_temp.pergunta('solver', 'gatilhos')).id = q.id, pg_temp.estados());
    d := public.agenda_decidir(q.id, 2::smallint, c_dono, 'whatsapp', '2', date '2026-12-03', pg_temp.em('2026-12-03 17:00'));
    v_res := pg_temp.ok(v_res, 'R6e "agora não": anotado, nenhuma ação',
      d ->> 'ok' = 'true' and d ->> 'texto' = 'Combinado: agora não. Não pergunto de novo.'
      and not exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado'), d::text);
    update public.agenda_config set solver_os_ativas = 5, solver_pessoas = 1 where id;
    k := 0;
    foreach v_dia in array array[date '2026-12-10', date '2026-12-17', date '2026-12-24', date '2026-12-31', date '2027-01-07',
                                 date '2027-01-14', date '2027-01-21'] loop
      perform public._agenda_aprender_solver(v_dia, (v_dia + time '16:05') at time zone 'America/Sao_Paulo');
      k := k + 1;
    end loop;
    a := pg_temp.linha('solver', 'gatilhos');
    v_res := pg_temp.ok(v_res, 'R6f nem depois da trava (28 dias), com os gatilhos de volta, pergunta de novo: 1 pergunta na história',
      (select count(*) from public.agenda_perguntas x where x.chave = 'aprendizado:solver:gatilhos') = 1
      and a.estado in ('em_uso', 'medindo') and a.texto like 'Gatilhos de um planejador mais forte:%', to_jsonb(a)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- a opção 1 e o modo em teste
  begin
    execute current_setting('agenda_teste.fase6');
    update public.agenda_config set solver_os_ativas = 5, solver_pessoas = 2 where id;
    perform pg_temp.modo('sombra');
    foreach v_dia in array array[date '2026-10-29', date '2026-11-05', date '2026-11-12', date '2026-11-19'] loop
      perform public._agenda_aprender_solver(v_dia, (v_dia + time '16:05') at time zone 'America/Sao_Paulo');
    end loop;
    a := pg_temp.linha('solver', 'gatilhos');
    v_res := pg_temp.ok(v_res, 'R6g em teste, com os 2 gatilhos por 4 semanas: sombra, sem pergunta, e o foco diz o que faria',
      a.estado = 'sombra' and a.calculado = 1
      and not exists (select 1 from public.agenda_perguntas x where x.chave = 'aprendizado:solver:gatilhos')
      and a.texto = 'Gatilhos de um planejador mais forte: 2 de 4 (11 OS ativas, 3 pessoas). Em teste: eu avisaria que vale estudar um planejador mais forte.',
      a.texto);
    perform pg_temp.modo('ligado', array['revisao']);
    perform public._agenda_aprender_solver(date '2026-11-19', pg_temp.em('2026-11-19 16:10'));
    q := pg_temp.pergunta('solver', 'gatilhos');
    d := public.agenda_decidir(q.id, 1::smallint, c_dono, 'whatsapp', '1', date '2026-11-19', pg_temp.em('2026-11-19 17:00'));
    perform public._agenda_aprender_solver(date '2026-11-26', pg_temp.em('2026-11-26 16:05'));
    v_res := pg_temp.ok(v_res, 'R6h "quero ver isso": anotado sem ação (nada muda na agenda), e a semana seguinte não pergunta de novo',
      d ->> 'ok' = 'true' and d ->> 'texto' = 'Combinado: anotei que você quer ver um planejador mais forte. Nada muda sozinho na agenda.'
      and not exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado')
      and (select count(*) from public.agenda_perguntas x where x.chave = 'aprendizado:solver:gatilhos') = 1
      and (pg_temp.linha('solver', 'gatilhos')).texto like '%. Você quis ver isso; nada muda sozinho.', (pg_temp.linha('solver', 'gatilhos')).texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r6$;

-- ── R7. A saúde ─────────────────────────────────────────────────────────────────────────────────────────
do $r7$
declare
  v_res jsonb := '[]'::jsonb;
  s     jsonb;
  s0    jsonb;
  v_ok0 text;
  v_viol record;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('R7 a saúde (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    s0 := public.agenda_saude(date '2026-10-30', pg_temp.em('2026-10-30 16:00'));
    v_res := pg_temp.ok(v_res, 'R7a antes de qualquer rodada: a chave aprendizado com os zeros (a rodada atrasada só conta depois da 1ª)',
      s0 #>> '{aprendizado,modo}' = 'desligado' and s0 #>> '{aprendizado,ultima_rodada}' is null
      and (select bool_and(s0 -> 'aprendizado' ->> k = '0')
             from unnest(array['em_uso_com_amostra_pequena', 'em_uso_fora_de_ligado', 'troca_grande_sem_pergunta', 'rodada_atrasada',
                               'medida_sem_classe', 'fator_fora_dos_limites']) k), (s0 -> 'aprendizado')::text);
    perform pg_temp.modo('ligado', pg_temp.todos());
    perform pg_temp.rodar('2026-10-30 16:05');
    s := public.agenda_saude(date '2026-10-30', pg_temp.em('2026-10-30 16:10'));
    v_res := pg_temp.ok(v_res, 'R7b depois da rodada ligada: os 6 zeros, os erros 0, a rodada de hoje, e o ok da saúde como antes da rodada',
      (select bool_and(s -> 'aprendizado' ->> k = '0')
         from unnest(array['em_uso_com_amostra_pequena', 'em_uso_fora_de_ligado', 'troca_grande_sem_pergunta', 'rodada_atrasada',
                           'medida_sem_classe', 'fator_fora_dos_limites', 'erros_24h']) k)
      and s #>> '{aprendizado,rodou_hoje}' = 'true' and s ->> 'ok' = s0 ->> 'ok'
      and s #>> '{aprendizado,metricas,trocas_30d,sozinhas}' = '8' and s #>> '{aprendizado,metricas,trocas_30d,perguntas}' = '3'
      and s #>> '{aprendizado,metricas,medidas,validas}' = '11' and s #>> '{aprendizado,metricas,itens,fator,chaves}' = '11',
      (s -> 'aprendizado')::text);
    v_res := pg_temp.ok(v_res, 'R7c a saúde de sáb 31/10 18:10 (26 h depois da rodada, sem outra): rodada atrasada = 1',
      public.agenda_saude(date '2026-10-31', pg_temp.em('2026-10-31 18:10')) #>> '{aprendizado,rodada_atrasada}' = '1'
      and public.agenda_saude(date '2026-10-31', pg_temp.em('2026-10-31 18:00')) #>> '{aprendizado,rodada_atrasada}' = '0', null);
    -- cada violação forçada, sozinha (numa subtransação), aparece como 1
    for v_viol in
      select * from (values
        ('em_uso_com_amostra_pequena', $v$update public.agenda_aprendizado set n = 2 where item = 'fator' and chave = 'rv:energia'$v$),
        ('troca_grande_sem_pergunta', $v$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate, criada_em)
                                        values (date '2026-10-30', true, 'vigia', 'aprendizado', 'troca forçada no teste',
                                                '{"item": "fator", "chave": "todas", "nivel": "todas", "valor": 1.5}', '{"item": "fator", "em_uso": 2.4}',
                                                timestamptz '2026-10-31 16:05-03', timestamptz '2026-10-30 16:05-03')$v$),
        ('fator_fora_dos_limites', $v$update public.agenda_aprendizado set calculado = 2.90 where item = 'fator' and chave = 'bem:barco'$v$),
        ('medida_sem_classe', $v$alter table public.agenda_medidas_os alter column classe_bem drop not null;
                                 alter table public.agenda_medidas_os disable trigger user;
                                 update public.agenda_medidas_os set classe_bem = null
                                  where service_order_id = '05000000-0000-4000-8000-000000000131'$v$),
        ('em_uso_fora_de_ligado', $v$update public.agenda_vigia_rodadas set contagens = contagens || '{"modo_aprendizado": "sombra"}'
                                      where rotina = 'aprender';
                                     update public.agenda_aprendizado set estado = 'medindo', em_uso = null
                                      where estado = 'em_uso' and not (item = 'fator' and chave = 'todas')$v$)
      ) as v(chave, sql)
    loop
      begin
        execute v_viol.sql;
        s := public.agenda_saude(date '2026-10-30', pg_temp.em('2026-10-30 16:10'));
        v_res := pg_temp.ok(v_res, format('R7d %s forçado = 1 (e os outros zeros continuam 0)', v_viol.chave),
          s -> 'aprendizado' ->> v_viol.chave = '1'
          and (select bool_and(s -> 'aprendizado' ->> k = '0')
                 from unnest(array['em_uso_com_amostra_pequena', 'em_uso_fora_de_ligado', 'troca_grande_sem_pergunta', 'rodada_atrasada',
                                   'medida_sem_classe', 'fator_fora_dos_limites']) k where k <> v_viol.chave),
          (s -> 'aprendizado')::text);
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
    end loop;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r7$;

-- ── R8. As cópias e as portas ───────────────────────────────────────────────────────────────────────────
do $r8$
declare
  v_res jsonb := '[]'::jsonb;
  f     record;
  v_src text;
  v_novo text;
begin
  for f in
    select * from (values
      ('agenda_decidir', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'agenda_teste.mig_rodada_fase5', true),
      ('agenda_saude', 'public.agenda_saude(date, timestamptz)', 'agenda_teste.mig_rodada_fase5', false),
      ('agenda_desfazer', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'agenda_teste.mig_respostas_fase5', true),
      ('agenda_desfazer_dito', 'public.agenda_desfazer_dito(uuid, text, text, date, timestamptz)', 'agenda_teste.mig_conferencia_fase2', true),
      ('_agenda_aprendizado_texto', 'public._agenda_aprendizado_texto(text, text, jsonb)', 'agenda_teste.mig_cliente_fase6', false)
    ) as t(nome, sig, mig, definer)
  loop
    v_src := coalesce(current_setting(f.mig, true), '');
    if v_src = '' then
      v_res := pg_temp.ok(v_res, format('R8a a cópia de %s', f.nome), true, 'PULADO: sem ' || f.mig || ' (rode pela bancada)');
      continue;
    end if;
    select p.prosrc into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    v_res := pg_temp.ok(v_res, format('R8a a cópia de %s só acrescenta os blocos "-- FASE 6:" (o resto é o corpo de %s), com o bloco do P6; o definer e o search_path de antes',
                                      f.nome, f.mig),
      pg_temp.sem_fase6(v_novo) = pg_temp.sem_fase6(pg_temp.corpo(v_src, f.nome))
      and v_novo ~ '-- FASE 6: (\(P6\) |o aprendizado)'
      and (select p.prosecdef = f.definer and array_to_string(p.proconfig, ',') like '%search_path=public%'
             from pg_proc p where p.oid = f.sig::regprocedure),
      format('%s × %s linhas', cardinality(pg_temp.sem_fase6(v_novo)), cardinality(pg_temp.sem_fase6(pg_temp.corpo(v_src, f.nome)))));
  end loop;
  v_res := pg_temp.ok(v_res, 'R8b os zeros do aprendizado entram no ok da saúde (pelo v_zeros4, como os das Fases 4 e 5)',
    (select p.prosrc ~ 'v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;\s*v_zeros4 := v_zeros4 and v_zeros6;'
       from pg_proc p where p.oid = 'public.agenda_saude(date, timestamptz)'::regprocedure), null);
  v_res := pg_temp.ok(v_res, 'R8c as portas: a rodada só service_role; os passos, a decisão, o *desfaz* e a carga sem grant a ninguém; nenhuma para anon; as recriadas como antes',
    has_function_privilege('service_role', 'public.agenda_aprender(date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_aprender(date, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_aprender(date, timestamptz)', 'execute')
    and not exists (select 1 from unnest(array['public._agenda_aprender_revisao(date, timestamptz)', 'public._agenda_aprender_solver(date, timestamptz)',
                                               'public._agenda_aprendizado_decidir(uuid, smallint, uuid, text, text, date, timestamptz)',
                                               'public._agenda_desfazer_aprendizado(uuid, uuid, text, date, timestamptz)',
                                               'public._agenda_aprendizado_carga(numeric, numeric, uuid, timestamptz)']) s,
                         unnest(array['anon', 'authenticated', 'service_role']) r
                    where has_function_privilege(r, s, 'execute'))
    and (select bool_and(p.prosecdef = (p.proname in ('agenda_aprender', '_agenda_aprendizado_decidir', '_agenda_desfazer_aprendizado',
                                                       '_agenda_aprendizado_carga'))
                         and array_to_string(p.proconfig, ',') like '%search_path=public%')
           from pg_proc p
          where p.pronamespace = 'public'::regnamespace
            and p.proname in ('agenda_aprender', '_agenda_aprender_revisao', '_agenda_aprender_solver', '_agenda_aprendizado_decidir',
                              '_agenda_desfazer_aprendizado', '_agenda_aprendizado_carga'))
    and has_function_privilege('service_role', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'execute')
    and has_function_privilege('service_role', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'execute')
    and has_function_privilege('authenticated', 'public.agenda_desfazer_dito(uuid, text, text, date, timestamptz)', 'execute')
    and has_function_privilege('authenticated', 'public.agenda_saude(date, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_saude(date, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_desfazer_dito(uuid, text, text, date, timestamptz)', 'execute'),
    null);
  perform pg_temp.gravar(v_res);
end
$r8$;

-- ── R9. A correção C1 (20261029100900): item 13; regressões B2 e B4 ──────────────────────────────────────
-- (item 13) a revisão e o planejador rodam no dia do plano OU depois dele na semana, enquanto não houve rodada semanal com o
-- modo e a lista de agora: a quinta que não rodou não espera a semana seguinte, e o dono que liga a revisão na sexta também
-- não. (B2) a decisão e o *desfaz* do aprendizado tomam a trava da rodada antes de travar a linha. (B4) o índice da rodada.
do $r9$
declare
  v_res jsonb := '[]'::jsonb;
  r    jsonb;
  f    text;
  v_src text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('R9 a correção C1 da rodada (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
  else
    -- a quinta 29/10 sem rodada nenhuma: a de sexta faz a semanal
    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.modo('ligado', '{revisao}');
      r := pg_temp.rodar('2026-10-30 16:05');
      v_res := pg_temp.ok(v_res, 'R9a (C1, item 13) ligado na sexta, sem a rodada de quinta (o dia do plano): a revisão e o planejador rodam na sexta, e a carga pergunta',
        r ->> 'semanal' = 'true' and r -> 'contagens' ? 'revisao' and r -> 'contagens' ? 'solver'
        and (pg_temp.linha('carga', 'todas')).estado = 'pergunta', r::text);
      r := pg_temp.rodar('2026-10-31 16:05');
      v_res := pg_temp.ok(v_res, 'R9b (C1, item 13) uma vez por semana: no sábado (a semanal já rodou na sexta, com o mesmo modo e a mesma lista) não roda de novo',
        r ->> 'semanal' = 'false' and not (r -> 'contagens' ? 'revisao'), r::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    -- a quinta rodou em teste; o dono liga a revisão na sexta: a de sexta faz a semanal de novo (com a lista de agora)
    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.modo('sombra');
      r := pg_temp.rodar('2026-10-29 16:05');
      perform pg_temp.modo('ligado', '{revisao}');
      r := pg_temp.rodar('2026-10-30 16:05');
      v_res := pg_temp.ok(v_res, 'R9c (C1, item 13) a quinta rodou em teste e o dono ligou a revisão na sexta: a sexta revisa (a pergunta da carga sai na sexta, sem esperar a quinta seguinte)',
        r ->> 'semanal' = 'true' and (pg_temp.linha('carga', 'todas')).estado = 'pergunta', r::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    -- a quinta rodou ligada com a mesma lista: a sexta não repete; e antes do dia do plano (seg 02/11) a semanal não roda
    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.modo('ligado', '{revisao}');
      r := pg_temp.rodar('2026-10-29 16:05');
      r := pg_temp.rodar('2026-10-30 16:05');
      v_res := pg_temp.ok(v_res, 'R9d (C1, item 13) a quinta rodou ligada com a mesma lista: a sexta não repete a revisão',
        r ->> 'semanal' = 'false', r::text);
      r := pg_temp.rodar('2026-11-02 16:05');
      v_res := pg_temp.ok(v_res, 'R9e (C1, item 13) na segunda da semana seguinte (antes do dia do plano) a semanal não roda',
        r ->> 'semanal' = 'false', r::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    perform pg_temp.gravar(v_res);
  end if;

  -- (B2) a trava da rodada antes da 1ª linha travada (em qualquer lugar: só o prosrc)
  foreach f in array array['public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)',
                           'public._agenda_aprendizado_decidir(uuid, smallint, uuid, text, text, date, timestamptz)',
                           'public._agenda_desfazer_aprendizado(uuid, uuid, text, date, timestamptz)'] loop
    v_src := (select p.prosrc from pg_proc p where p.oid = to_regprocedure(f));
    insert into _resultado values (format('R9f (C1, B2) %s toma a trava da rodada do aprendizado antes do 1º "for update"', f),
      position('pg_advisory_xact_lock(hashtext(''agenda_aprender''))' in coalesce(v_src, '')) > 0
      and position('pg_advisory_xact_lock(hashtext(''agenda_aprender''))' in v_src) < position('for update' in v_src),
      null);
  end loop;
  -- (B4) o índice da rodada
  insert into _resultado values ('R9g (C1, B4) agenda_vigia_rodadas tem o índice (rotina, p_hoje, p_agora desc)',
    exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'agenda_vigia_rodadas'
                                       and indexname = 'agenda_vigia_rodadas_rotina_dia'
                                       and indexdef like '%(rotina, p_hoje, p_agora DESC)%'),
    (select indexdef from pg_indexes where indexname = 'agenda_vigia_rodadas_rotina_dia'));
end
$r9$;

-- ── R10. A correção C2 (20261029100950): item 6, textos 2 e 5, regressões M1 e B1, item 12 ──────────────────
-- (item 6) *desfaz aprendizado <coisa>* desfaz só aquela coisa (as outras do lote continuam em uso) e o lote sozinho continua;
-- o "o que mudou" sai uma linha por item (texto 2), sem o sufixo em cada linha e com a frase UMA vez; a tela desfaz o item
-- inteiro. (M1) nenhum "*desfaz * volta como estava." no fechamento nem no foco mudanças. (B1) "a última" e o *desfaz* sem
-- nome não pegam o aprendizado, e a lista nunca sai vazia. (texto 5) a pergunta do R$ por diária. (item 12) as janelas da
-- saúde pelo agenda_config.
do $r10$
declare
  v_res jsonb := '[]'::jsonb;
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_kam  constant text := 'dd000000-0000-4000-8000-000000000002';
  r     jsonb;
  d     jsonb;
  v_m   jsonb;
  v_t   text;
  v_f   text;
  v_id  uuid;
  q     public.agenda_perguntas;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('R10 a correção C2 da rodada (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;

  -- (item 6) *desfaz aprendizado Kamell*: só os 2 da Kamell; depois *desfaz aprendizado* desfaz os 6 que sobraram
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', pg_temp.todos());
    r := pg_temp.rodar('2026-10-30 16:05');
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado kamell', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:40'));
    v_res := pg_temp.ok(v_res, 'R10a (C2, item 6) *desfaz aprendizado Kamell* desfaz só o atraso e o prazo da Kamell (2 ações, as 2 travadas); o fator, a presença e a folga continuam em uso',
      d ->> 'ok' = 'true' and jsonb_array_length(d -> 'acoes') = 2
      and (pg_temp.linha('fornecedor_atraso', c_kam)).estado = 'travado' and (pg_temp.linha('fornecedor_prazo', c_kam)).estado = 'travado'
      and (pg_temp.linha('fator', 'rv:energia')).estado = 'em_uso' and (pg_temp.linha('fator', 'rv:energia')).em_uso = 1.70
      and (pg_temp.linha('presenca', 'rv:energia')).estado = 'em_uso' and (pg_temp.linha('aviso_folga', 'todas')).em_uso = 2
      and (select count(*) from public.agenda_aprendizado y where y.estado = 'travado') = 2
      and d ->> 'texto' like 'Desfeito: para Kamell volto a contar a chegada no dia que o fornecedor diz.%'
      and d ->> 'texto' like '%Desfeito: para Kamell volto a contar 4 dias úteis da saída da nota até a chegada.%',
      d::text || ' ' || pg_temp.estados());
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado Kamell', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:41'));
    v_res := pg_temp.ok(v_res, 'R10b (C2, item 6) de novo *desfaz aprendizado Kamell*: "não tenho" (nada desfeito duas vezes)',
      d ->> 'ok' = 'false' and d ->> 'status' = 'nenhuma'
      and d ->> 'texto' = 'Não tenho mudança do aprendizado de Kamell para desfazer agora.', d::text);
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:42'));
    v_res := pg_temp.ok(v_res, 'R10c (C2, item 6) *desfaz aprendizado* sozinho continua o lote: desfaz as 6 que sobraram (todas travadas)',
      d ->> 'ok' = 'true' and jsonb_array_length(d -> 'acoes') = 6
      and (select count(*) from public.agenda_aprendizado y where y.estado = 'travado') = 8, d::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 6) os outros alvos: fator (as 3 classes), presença (com acento, como a tela escreve), folga, fornecedor, o valor
  -- (sem ação: "não tenho") e a coisa que não existe (nao_achei)
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', pg_temp.todos());
    r := pg_temp.rodar('2026-10-30 16:05');
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado fator', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:40'));
    v_res := pg_temp.ok(v_res, 'R10d (C2, item 6) *desfaz aprendizado fator*: as 3 classes do fator (travadas); a presença e a Kamell continuam em uso',
      d ->> 'ok' = 'true' and jsonb_array_length(d -> 'acoes') = 3
      and (select count(*) from public.agenda_aprendizado y where y.item = 'fator' and y.estado = 'travado') = 3
      and (pg_temp.linha('presenca', 'rv:energia')).estado = 'em_uso' and (pg_temp.linha('fornecedor_atraso', c_kam)).estado = 'em_uso',
      d::text);
    d := public.agenda_desfazer_dito(c_dono, 'o aprendizado presença', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:41'));
    v_f := d ->> 'ok' || ':' || coalesce(jsonb_array_length(d -> 'acoes'), 0);
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado folga', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:42'));
    v_f := v_f || ' ' || (d ->> 'ok') || ':' || coalesce(jsonb_array_length(d -> 'acoes'), 0);
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado fornecedor', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:43'));
    v_f := v_f || ' ' || (d ->> 'ok') || ':' || coalesce(jsonb_array_length(d -> 'acoes'), 0);
    v_res := pg_temp.ok(v_res, 'R10e (C2, item 6) "o aprendizado presença" (com acento e o "o") desfaz as 2 classes; "folga", a folga; "fornecedor", o atraso e o prazo (cada um trava só o que desfez: no fim, as 8)',
      v_f = 'true:2 true:1 true:2' and (select count(*) from public.agenda_aprendizado y where y.estado = 'travado') = 8,
      v_f || ' ' || pg_temp.estados());
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado diaria', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:44'));
    v_t := d ->> 'status' || ' | ' || (d ->> 'texto');
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado gerador', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:44'));
    v_t := v_t || ' | ' || (d ->> 'status') || ' | ' || (d ->> 'texto');
    v_res := pg_temp.ok(v_res, 'R10f (C2, item 6) o valor sem ação (é pergunta): "não tenho" com o nome dele; a coisa que não é item nem fornecedor: nao_achei, com as palavras',
      v_t = 'nenhuma | Não tenho mudança do aprendizado do valor por diária para desfazer agora. | nao_achei | Não achei isso no que eu aprendi. Diga *desfaz aprendizado* e fator, presença, valor, folga, capacidade ou o nome do fornecedor (ou só *desfaz aprendizado*, que volta tudo).',
      v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (M1, texto 2 e a frase uma vez) o cenário do r08 da revisão: a rodada ligada de sex 30/10 (fator, presença, fornecedor,
  -- aviso) e o fechamento das 17:30 e o foco mudanças
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('sombra');
    r := pg_temp.rodar('2026-10-29 16:05');
    perform pg_temp.modo('ligado', '{fator,presenca,fornecedor,aviso_cliente}');
    r := pg_temp.rodar('2026-10-30 16:05');
    v_t := public.agenda_textos_do_fechamento(date '2026-10-30', date '2026-10-30')::text;
    v_f := public.agenda_ver(c_dono, null, null, 'mudancas', null, null, false, date '2026-10-30') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'R10g (C2, regressão M1) nenhum "*desfaz * volta como estava." no fechamento das 17:30 nem no foco mudanças',
      v_t not like '%*desfaz *%' and v_f not like '%*desfaz *%' and v_f like '%Aprendi com as OS concluídas%', v_f);
    v_m := public._agenda_mudancas(date '2026-10-30', date '2026-10-30', true, true, pg_temp.em('2026-10-30 17:30'));
    select string_agg(e -> 'itens' ->> 0, ' || ' order by o) into v_f
      from jsonb_array_elements(v_m) with ordinality t(e, o)
     where exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado' and e -> 'acao_ids' ? x.id::text);
    v_res := pg_temp.ok(v_res, 'R10h (C2, texto 2) o "o que mudou" sai UMA linha por item: 5 linhas (fator, presença, atraso e prazo da Kamell, folga) com as 8 ações nelas; a do fator diz a fina e "Também nas OS de energia (1,7×) e nas em motorhome (1,6×).", a da presença "Também nas OS de energia."',
      (select count(*) from jsonb_array_elements(v_m) e
        where exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado' and e -> 'acao_ids' ? x.id::text)) = 5
      and (select sum(jsonb_array_length(e -> 'acao_ids')) from jsonb_array_elements(v_m) e
            where exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado' and e -> 'acao_ids' ? x.id::text)) = 8
      and v_f like '%Aprendi com as OS concluídas: as OS de energia em motorhome levam até 1,7× o combinado (7 OS). Passei a usar 1,7× no lugar de 1,5× para perguntar o que falta. Também nas OS de energia (1,7×) e nas em motorhome (1,6×).%'
      and v_f like '%Você foi a 3 de 4 OS de energia em motorhome sem estar no plano: passei a contar com você o dia todo nas próximas dessas OS (as que você não disse como é). Também nas OS de energia.%'
      and v_f like '%Kamell atrasou até 2 dias úteis em 6 entregas: passei a contar a chegada 2 dias úteis depois do que o fornecedor diz.%',
      v_f);
    v_res := pg_temp.ok(v_res, 'R10i (C2, item 6) as linhas perdem o "*desfaz aprendizado* volta." de cada ação, e a frase vem UMA vez, no fim da 1ª linha: "*desfaz aprendizado* volta tudo; *desfaz aprendizado <coisa>* volta só …" (no fechamento também)',
      (length(v_f) - length(replace(v_f, '*desfaz aprendizado*', ''))) / length('*desfaz aprendizado*') = 1
      and v_f ~ '^[^|]*\*desfaz aprendizado\* volta tudo; \*desfaz aprendizado [^*]+\* volta só (essa|o que é de [A-Za-z]+)\.( \|\||$)'
      and v_t like '%*desfaz aprendizado* volta tudo; *desfaz aprendizado %'
      and v_f not like '%*desfaz aprendizado* volta.%' and v_f not like '%volta ao abre e fecha%', v_f);
    -- a tela: o botão da linha do fator desfaz as 3 classes de uma vez
    select x.id into v_id from public.agenda_acoes x where x.tipo = 'aprendizado' and x.antes ->> 'chave' = 'sistema:energia'
                                                         and x.antes ->> 'item' = 'fator';
    -- (a tela tem login: o do dono)
    perform set_config('request.jwt.claim.sub', c_dono::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', c_dono, 'role', 'authenticated')::text, true);
    d := public.agenda_desfazer_pela_tela(v_id, date '2026-10-30', pg_temp.em('2026-10-30 17:50'));
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := pg_temp.ok(v_res, 'R10j (C2, item 6) na tela, o Desfazer da linha do fator desfaz o item inteiro daquele instante (as 3 classes), e o texto são os "Desfeito: …" (não "a publicação da semana")',
      d ->> 'ok' = 'true' and jsonb_array_length(d -> 'acoes') = 3
      and (select count(*) from public.agenda_aprendizado y where y.item = 'fator' and y.estado = 'travado') = 3
      and (pg_temp.linha('presenca', 'rv:energia')).estado = 'em_uso'
      and d ->> 'texto' like 'Desfeito: %' and d ->> 'texto' not like '%publicação%', d::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (B1) o cenário do r06: "a última" e o *desfaz* sem nome com o lote do aprendizado desfazível
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', '{fator,presenca,fornecedor,aviso_cliente}');
    r := pg_temp.rodar('2026-10-30 16:05');
    d := public.agenda_desfazer_dito(c_dono, 'a última', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 16:20'));
    v_res := pg_temp.ok(v_res, 'R10k (C2, regressão B1) *desfaz a última* não desfaz uma chave solta do aprendizado (a bem:rv continua 1,6 com a rv:energia em 1,7): desfaz a última mudança de outro tipo',
      d ->> 'ok' = 'true' and (pg_temp.linha('fator', 'bem:rv')).estado = 'em_uso' and (pg_temp.linha('fator', 'rv:energia')).em_uso = 1.70
      and not exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado' and x.desfeita_em is not null), d::text);
    d := public.agenda_acao_desfazivel(null, date '2026-10-30', pg_temp.em('2026-10-30 16:21'));
    v_res := pg_temp.ok(v_res, 'R10l (C2, regressão B1) *desfaz* sem nome: a lista "Qual?" sem as ações do aprendizado (nem os ids), cada opção com nome',
      d ->> 'status' = 'ambiguo' and d ->> 'texto' like 'Qual? %' and d ->> 'texto' not like 'Qual?  %' and d ->> 'texto' not like '% ou  (%'
      and jsonb_array_length(d -> 'acao_ids') > 1
      and not exists (select 1 from public.agenda_acoes x, jsonb_array_elements_text(d -> 'acao_ids') o
                       where x.tipo = 'aprendizado' and o = x.id::text), d::text);
    -- 16:40: as ações do plano (de ter 27/10) já não se desfazem; só sobra o aprendizado
    d := public.agenda_desfazer_dito(c_dono, null, 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 16:40'));
    v_t := d ->> 'status' || ' | ' || (d ->> 'texto');
    d := public.agenda_desfazer_dito(c_dono, 'a última', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 16:40'));
    v_t := v_t || ' | ' || (d ->> 'status') || ' | ' || (d ->> 'texto');
    v_res := pg_temp.ok(v_res, 'R10m (C2, regressão B1) só com o aprendizado desfazível, o *desfaz* sem nome e "a última" não viram "Qual?  Diga…" nem desfazem uma chave: dizem a palavra do aprendizado',
      v_t = 'nenhuma | Não tenho outra mudança minha para desfazer agora. O que eu aprendi sozinho volta com *desfaz aprendizado*. | nenhuma | Não tenho outra mudança minha para desfazer agora. O que eu aprendi sozinho volta com *desfaz aprendizado*.'
      and not exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado' and x.desfeita_em is not null), v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (texto 5) a pergunta do R$ por diária: sem "(recomendo)" e com "inclui as OS em que você também trabalhou"
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', pg_temp.todos());
    r := pg_temp.rodar('2026-10-30 16:05');
    q := pg_temp.pergunta('mo', 'todas');
    v_res := pg_temp.ok(v_res, 'R10n (C2, texto 5) a pergunta do R$ por diária diz que a conta inclui as OS em que o dono também trabalhou, e a opção 1 sai sem "(recomendo)" (a recomendação continua 1)',
      q.texto = 'Medi a mão de obra por diária: cada diária rendeu R$ 1.097 (10 OS com diária ligada; inclui as OS em que você também trabalhou), e hoje eu uso R$ 764 para estimar os dias pelo valor. É uma troca grande. 1) Passo a usar R$ 1.097; 2) Fico com R$ 764.'
      and q.recomendacao = 1 and q.texto not like '%recomendo%'
      and (select q2.texto from public.agenda_perguntas q2
            where q2.chave = 'aprendizado:capacidade_dono:dono' and q2.estado = 'aberta') like '%1) Passo a marcar até 56% (recomendo)%',
      q.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 12) as janelas da saúde: a rodada atrasada (aprender_atraso_h), a troca grande (aprender_saude_dias), as métricas
  -- (aprender_parar_dias) e o desfeito 2 vezes (aprender_trava_dias)
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', '{fator}');
    r := pg_temp.rodar('2026-10-30 16:05');
    -- 25h30 depois: com 26 h não está atrasada; com 25 h está
    v_t := (public.agenda_saude(date '2026-10-31', pg_temp.em('2026-10-31 17:35')) #>> '{aprendizado,rodada_atrasada}');
    update public.agenda_config set aprender_atraso_h = 25 where id;
    v_t := v_t || ' ' || (public.agenda_saude(date '2026-10-31', pg_temp.em('2026-10-31 17:35')) #>> '{aprendizado,rodada_atrasada}');
    update public.agenda_config set aprender_atraso_h = 26 where id;
    -- uma troca grande que entrou sozinha (o fator de 1,5 a 2,0: acima de fator_troca_max), 2 dias depois: com 7 dias
    -- aparece; com aprender_saude_dias 1, não
    alter table public.agenda_acoes disable trigger user;  -- (só a simulação: a ação gravada não se reescreve)
    update public.agenda_acoes set depois = jsonb_set(depois, '{em_uso}', '2.0')
     where tipo = 'aprendizado' and antes ->> 'chave' = 'rv:energia' and antes ->> 'item' = 'fator';
    alter table public.agenda_acoes enable trigger user;
    v_t := v_t || ' ' || (public.agenda_saude(date '2026-11-01', pg_temp.em('2026-11-01 16:05')) #>> '{aprendizado,troca_grande_sem_pergunta}');
    update public.agenda_config set aprender_saude_dias = 1 where id;
    v_t := v_t || ' ' || (public.agenda_saude(date '2026-11-01', pg_temp.em('2026-11-01 16:05')) #>> '{aprendizado,troca_grande_sem_pergunta}');
    -- as trocas que entraram sozinhas nas métricas: 8 dias depois, com 30 dias as 3 do fator contam; com 7, nenhuma
    v_t := v_t || ' ' || (public.agenda_saude(date '2026-11-07', pg_temp.em('2026-11-07 17:00')) #>> '{aprendizado,metricas,trocas_30d,sozinhas}');
    update public.agenda_config set aprender_parar_dias = 7 where id;
    v_t := v_t || ' ' || (public.agenda_saude(date '2026-11-07', pg_temp.em('2026-11-07 17:00')) #>> '{aprendizado,metricas,trocas_30d,sozinhas}');
    v_res := pg_temp.ok(v_res, 'R10o (C2, item 12) as janelas da saúde vêm de agenda_config: a rodada atrasada pelas horas (26 h: 0; 25 h: 1), a troca grande pelos dias (7: 1; 1: 0) e as trocas das métricas pelos dias (30: 3; 7: 0)',
      v_t = '0 1 1 0 3 0', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.modo('ligado', '{fator}');
    r := pg_temp.rodar('2026-10-30 16:05');
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:40'));
    r := pg_temp.rodar('2026-11-28 16:05');
    d := public.agenda_desfazer_dito(c_dono, 'aprendizado', 'whatsapp', date '2026-11-28', pg_temp.em('2026-11-28 16:40'));
    -- os 2 desfeitos do fator estão a 28 dias e 23 h: dentro de 28 dias não; dentro de 30, sim
    v_t := (public.agenda_saude(date '2026-11-28', pg_temp.em('2026-11-28 17:00')) #> '{aprendizado,metricas,desfeito_2x_em_4_semanas}')::text;
    update public.agenda_config set aprender_trava_dias = 30 where id;
    v_t := v_t || ' ' || (public.agenda_saude(date '2026-11-28', pg_temp.em('2026-11-28 17:00')) #> '{aprendizado,metricas,desfeito_2x_em_4_semanas}')::text;
    v_res := pg_temp.ok(v_res, 'R10p (C2, item 12) o item desfeito 2 vezes é contado dentro de aprender_trava_dias (28: nada; 30: o fator), e não nos 28 dias escritos na função',
      v_t = '[] ["fator"]', v_t || ' ' || d::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r10$;
select teste, ok, detalhe from _resultado order by teste;

rollback;
