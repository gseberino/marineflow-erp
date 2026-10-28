-- Prova da OS no aprendizado da Agenda de Produção, Fase 6 (pacote P2; migration 20261029100200): o fator de campo por classe,
-- o R$ por diária e a presença do dono aprendida.
-- bancada: depende de 20261029100900
--
--   O1 o fator por nível e o recuo: o P80 das medidas válidas em cada uma das 4 chaves (rv:energia 1,70; bem:rv 1,60; todas
--      1,50); as de barco ficam abaixo do mínimo e caem no nível todas; o prender em [fator_min, fator_max]; rodar 2× não
--      muda nada
--   O2 agenda_fator_de_campo em medindo, em teste e em uso (teria × fator); ligado sem o fator na lista continua em teste; a
--      troca pequena entra sozinha com a ação e o *desfaz*; o modo em sombra volta o padrão na hora
--   O3 o estouro da vigia: a mesma OS (6,5 meios-dias feitos de 4 combinados) pergunta com 1,5× (o padrão) e não pergunta com
--      1,7× (em uso); com um fator aprendido menor que o padrão (1,25×), a OS com 6 de 4 pergunta, e com o padrão não
--   O4 o R$ por diária: as medidas válidas com diarista (a só do dono fica de fora); a troca grande vira pergunta; a mão de obra
--      igualada a R$ 690 × as diárias entra sozinha; a duração "pelo valor" com R$ 690 (mo_fonte) e, em teste, a de antes
--   O5 a presença aprendida: 3 de 4 (desde a 1ª ida registrada) → o dia todo na classe e no sistema, pergunta no geral; o
--      "passou" não conta; a OS com plano publicado não muda (nem o motor dela); o que o dono disse e a regra d05 vêm antes; o
--      motor (agenda_meios_da_os) usa a aprendida; o técnico fica com a regra de hoje
--   O6 as cópias só acrescentam os blocos "-- FASE 6:"; a assinatura de os_presenca_do_dono (continua SQL, STABLE, invoker) e
--      das outras recriadas não muda; as portas; o técnico e o anon recebem 42501 no fator de campo
--   O7 em teste e com o modo ligado sem lista, os_duracao_sugerida e os_presenca_do_dono devolvem, byte a byte, o que as
--      definições de antes (20261024160400, rodadas como pg_temp) devolvem para todas as OS; o motor (agenda_meios_da_os) da
--      carteira também não muda
--   O8 os textos do R$ por diária e da presença em cada momento (spec §6.2/§6.3), sem jargão (em qualquer lugar)
--   O9 (correção C1, 20261029100900) a presença guardada na 1ª publicação (o motor, o cartão e o CHECK novo); a presença
--      geral só com mais de uma classe; a vigia conta as diárias fora do plano como a medida; a vigia sem o fator fora de
--      ligado e sem cair pelo erro dele
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase6_os.sql
--   Seguro em produção: tudo dentro de begin/rollback. O6 e O8 rodam em qualquer lugar (as cópias só com as migrations como texto);
--   O1 a O5 e O7 só na bancada (a fixture-fase6; fora dela, PULADO).
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

-- Roda p_sql como p_papel (com o login p_uid, ou sem login): o texto do resultado, ou 'erro <estado>: <mensagem>'.
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

create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-000000000' || lpad(p_n, 3, '0'))::uuid
$f$;

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
    if not v_bloco and l ~ '^\s*-- FASE 6:' and l !~ '^\s*-- FASE 6: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 6: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- As linhas de agenda_aprendizado de um item, uma por chave: "chave=calculado/n/estado".
create function pg_temp.linhas(p_item text) returns text language sql stable as $f$
  select string_agg(format('%s=%s/%s/%s', a.chave, coalesce(a.calculado::text, '-'), a.n, a.estado), ' ' order by a.chave)
    from public.agenda_aprendizado a where a.item = p_item
$f$;

-- O3: a OS-00100 (energia em motorhome) em andamento, com 2 dias ditos pelo dono (4 meios-dias) e o Roberto no plano de ter
-- 13 a sex 16/10, conferido: 6 meios-dias cumpridos e, com p_parcial, mais um parcial (6,5 feitos).
create function pg_temp.os100_em_andamento(p_parcial boolean) returns void language plpgsql as $f$
begin
  perform set_config('agenda.porta', 'on', true);
  update public.service_orders set status = 'in_progress', check_in_at = timestamptz '2026-10-13 08:00-03'
   where id = pg_temp.os('100');
  perform set_config('agenda.porta', 'off', true);
  update public.os_planejamento set dias = 2, estimativa_fonte = 'dono' where service_order_id = pg_temp.os('100');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em,
                                       resultado, motivo, resultado_via, resultado_em)
  select pg_temp.os('100'), 'bb000000-0000-4000-8000-000000000002', dia::date, turno, 'turno', 'execucao', 'publicada', 'motor',
         (dia::date - 1 + time '16:30') at time zone 'America/Sao_Paulo', resultado, motivo, 'dia_feito',
         (dia::date + time '17:30') at time zone 'America/Sao_Paulo'
    from (values ('2026-10-13', 'manha', 'cumprido', null), ('2026-10-13', 'tarde', 'cumprido', null),
                 ('2026-10-14', 'manha', 'cumprido', null), ('2026-10-14', 'tarde', 'cumprido', null),
                 ('2026-10-15', 'manha', 'cumprido', null), ('2026-10-15', 'tarde', 'cumprido', null),
                 ('2026-10-16', 'manha', 'parcial', 'imprevisto_tecnico')) a(dia, turno, resultado, motivo)
   where p_parcial or a.resultado = 'cumprido';
end $f$;

-- ── O1 e O2. O fator de campo ───────────────────────────────────────────────────────────────────────────
do $o1$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-30';
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  v  jsonb;
  v2 jsonb;
  v3 jsonb;
  a  public.agenda_aprendizado;
  n0 int;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('O1 e O2 o fator de campo (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform public._agenda_aprender_medir(c_hoje);

    -- antes de qualquer rodada do fator: o padrão, pela chave mais larga
    v := public.agenda_fator_de_campo(pg_temp.os('100'), c_hoje);
    v_res := pg_temp.ok(v_res, 'O2a sem nada aprendido: o padrão (1,5×), chave todas, 0 medidas, o texto de medindo',
      (v ->> 'fator')::numeric = 1.5 and v ->> 'fonte' = 'padrao' and v ->> 'chave' = 'todas' and v ->> 'n' = '0'
      and v -> 'teria' = 'null'::jsonb and v ->> 'estado' = 'medindo' and v ->> 'classe' = 'rv:energia'
      and v ->> 'texto' = 'As OS: 0 de 6 OS medidas; para perguntar o que falta, uso 1,5× o combinado (padrão).',
      v::text);

    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v := public._agenda_aprender_fator(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O1a em teste: 11 chaves (4 com o mínimo de medidas em teste, 7 medindo), nenhuma ação nem pergunta',
      v = '{"chaves": 11, "estados": {"sombra": 4, "medindo": 7}, "acoes": 0, "perguntas": 0, "erros": 0}', v::text);
    v_res := pg_temp.ok(v_res, 'O1b o P80 de cada chave: rv:energia 1,70 (7), sistema:energia 1,70, bem:rv 1,60 (9), todas 1,50 (11); as de barco (2) e as de 1 OS medindo',
      pg_temp.linhas('fator') = 'barco:motor=1.40/2/medindo bem:barco=1.40/2/medindo bem:rv=1.60/9/sombra '
        || 'rv:conforto=1.00/1/medindo rv:diagnostico=1.00/1/medindo rv:energia=1.70/7/sombra '
        || 'sistema:conforto=1.00/1/medindo sistema:diagnostico=1.00/1/medindo sistema:energia=1.70/7/sombra '
        || 'sistema:motor=1.40/2/medindo todas=1.50/11/sombra',
      pg_temp.linhas('fator'));
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = 'rv:energia';
    v_res := pg_temp.ok(v_res, 'O1c a amostra de rv:energia: as 7 OS, a mais recente primeiro (OS-00136, 1,75), a mediana 1,50, o padrão 1,50',
      jsonb_array_length(a.amostra) = 7 and a.amostra #>> '{0,numero}' = 'OS-00136' and (a.amostra #>> '{0,fator}')::numeric = 1.75
      and (a.detalhe ->> 'p50')::numeric = 1.5 and a.padrao = 1.5 and a.n_min = 6 and a.nivel = 'fina' and a.em_uso is null,
      to_jsonb(a)::text);

    v := public.agenda_fator_de_campo(pg_temp.os('100'), c_hoje);
    v2 := public.agenda_fator_de_campo(pg_temp.os('032'), c_hoje);
    v3 := public.agenda_fator_de_campo(pg_temp.os('104'), c_hoje);
    v_res := pg_temp.ok(v_res, 'O1d o recuo: a OS de energia em motorhome pela classe fina (teria 1,7×), a de motor em barco pelo nível todas (teria 1,5×; 11 medidas), a de geladeira em motorhome pelo bem (teria 1,6×)',
      v ->> 'chave' = 'rv:energia' and v ->> 'nivel' = 'fina' and (v ->> 'teria')::numeric = 1.7 and v ->> 'n' = '7'
      and v2 ->> 'classe' = 'barco:motor' and v2 ->> 'chave' = 'todas' and v2 ->> 'nivel' = 'todas' and (v2 ->> 'teria')::numeric = 1.5
      and v2 ->> 'n' = '11'
      and v3 ->> 'classe' = 'rv:conforto' and v3 ->> 'chave' = 'bem:rv' and v3 ->> 'nivel' = 'bem' and (v3 ->> 'teria')::numeric = 1.6,
      v::text || ' / ' || v2::text || ' / ' || v3::text);
    v_res := pg_temp.ok(v_res, 'O2b em teste: teria 1,7×, mas o fator é o padrão (1,5×) e o texto diz "Em teste"',
      (v ->> 'fator')::numeric = 1.5 and v ->> 'fonte' = 'padrao' and v ->> 'estado' = 'sombra'
      and v ->> 'texto' = 'Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).',
      v::text);

    select count(*) into n0 from public.agenda_aprendizado y, jsonb_array_elements(y.historico) h where y.item = 'fator';
    v := public._agenda_aprender_fator(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O1e rodar de novo no mesmo dia não muda nada (os mesmos estados, nenhuma entrada nova no histórico)',
      v ->> 'estados' = '{"sombra": 4, "medindo": 7}'
      and (select count(*) from public.agenda_aprendizado y, jsonb_array_elements(y.historico) h where y.item = 'fator') = n0,
      v::text);

    -- ligado, mas sem o fator na lista: continua em teste
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{mo}' where id;
    v := public._agenda_aprender_fator(c_hoje, c_agora);
    v2 := public.agenda_fator_de_campo(pg_temp.os('100'), c_hoje);
    v_res := pg_temp.ok(v_res, 'O2c ligado sem "fator" na lista: tudo em teste, o fator de campo é o padrão',
      v ->> 'estados' = '{"sombra": 4, "medindo": 7}' and v ->> 'acoes' = '0' and v2 ->> 'fonte' = 'padrao'
      and (v2 ->> 'fator')::numeric = 1.5, v::text || ' / ' || v2::text);

    -- ligado com o fator: a troca pequena entra sozinha (1,5 → 1,7 é 0,2 ≤ fator_troca_max), com a ação desfazível
    update public.agenda_config set aprendizado_ligados = '{fator}' where id;
    v := public._agenda_aprender_fator(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O2d ligado com "fator": as 4 em uso, 3 ações (rv:energia, sistema:energia, bem:rv; todas fica igual ao padrão, sem ação), nenhuma pergunta',
      v = '{"chaves": 11, "estados": {"em_uso": 4, "medindo": 7}, "acoes": 3, "perguntas": 0, "erros": 0}', v::text);
    v := public.agenda_fator_de_campo(pg_temp.os('100'), c_hoje);
    v2 := public.agenda_fator_de_campo(pg_temp.os('104'), c_hoje);
    v3 := public.agenda_fator_de_campo(pg_temp.os('032'), c_hoje);
    v_res := pg_temp.ok(v_res, 'O2e em uso: energia em motorhome 1,7× (aprendido), geladeira em motorhome 1,6× (pelo bem), motor em barco 1,5× (todas, aprendido igual ao padrão)',
      (v ->> 'fator')::numeric = 1.7 and v ->> 'fonte' = 'aprendido' and v ->> 'estado' = 'em_uso'
      -- (correção C2, texto 1) a linha do fator em uso diz para que serve
      and v ->> 'texto' = 'As OS de energia em motorhome levam até 1,7× o combinado (7 OS): uso 1,7× desde sex 30/10 para perguntar o que falta (os dias do plano continuam os que você disse).'
      and (v2 ->> 'fator')::numeric = 1.6 and v2 ->> 'fonte' = 'aprendido'
      and (v3 ->> 'fator')::numeric = 1.5 and v3 ->> 'fonte' = 'aprendido' and v3 ->> 'chave' = 'todas',
      v::text || ' / ' || v2::text || ' / ' || v3::text);
    v_res := pg_temp.ok(v_res, 'O2f a ação de rv:energia no "o que mudou", com *desfaz aprendizado* (origem vigia, desfazível)',
      exists (select 1 from public.agenda_acoes x
               where x.tipo = 'aprendizado' and x.origem = 'vigia' and x.depois ->> 'chave' = 'rv:energia'
                 and x.desfazivel_ate > c_agora and (x.antes ->> 'valor')::numeric = 1.5 and x.antes -> 'em_uso' = 'null'::jsonb
                 and x.texto = 'Aprendi com as OS concluídas: as OS de energia em motorhome levam até 1,7× o combinado (7 OS). Passei a usar 1,7× no lugar de 1,5× para perguntar o que falta. *desfaz aprendizado* volta.')
      and (select count(*) from public.agenda_acoes x where x.tipo = 'aprendizado') = 3,
      (select string_agg(x.texto, ' | ') from public.agenda_acoes x where x.tipo = 'aprendizado'));

    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v := public.agenda_fator_de_campo(pg_temp.os('100'), c_hoje);
    v_res := pg_temp.ok(v_res, 'O2g o modo de volta a sombra: o fator de campo volta ao padrão na hora (o leitor confere o modo), sem rodar nada',
      (v ->> 'fator')::numeric = 1.5 and v ->> 'fonte' = 'padrao' and (v ->> 'teria')::numeric = 1.7, v::text);

    -- prender em [fator_min, fator_max]
    update public.agenda_config set fator_max = 1.60, fator_min = 1.45 where id;
    perform public._agenda_aprender_fator(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O1f o medido preso em [fator_min, fator_max]: com o máximo em 1,60, rv:energia fica 1,60; com o mínimo em 1,45, motor em barco (1,40) fica 1,45',
      (select calculado from public.agenda_aprendizado where item = 'fator' and chave = 'rv:energia') = 1.60
      and (select calculado from public.agenda_aprendizado where item = 'fator' and chave = 'barco:motor') = 1.45,
      pg_temp.linhas('fator'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$o1$;

-- ── O3. O estouro da vigia ──────────────────────────────────────────────────────────────────────────────
do $o3$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-30';
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  v   jsonb;
  v_m jsonb;
  v_q text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('O3 o estouro da vigia (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  -- a) o padrão (1,5×): 6,5 feitos de 4 combinados passa de 6 → pergunta
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.os100_em_andamento(true);
    v_m := public.agenda_meios_da_os(pg_temp.os('100'), c_hoje);
    perform public._agenda_aprender_medir(c_hoje);
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform public._agenda_aprender_fator(c_hoje, c_agora);
    v := public._agenda_vigia_estouro(c_hoje, c_agora);
    select q.texto into v_q from public.agenda_perguntas q where q.chave = 'estouro:' || pg_temp.os('100') || ':4';
    v_res := pg_temp.ok(v_res, 'O3a com o padrão (em teste, 1,5×): a OS com 6,5 meios-dias feitos de 4 combinados ganha a pergunta (estouro:<os>:4, o texto de sempre)',
      v_m ->> 'fonte' = 'dono' and v_m ->> 'total' = '4' and (v_m ->> 'cumpridos')::numeric = 6.5
      and v ->> 'criadas' = '1' and v_q like 'Giancarlo%O que falta?',
      v::text || ' / ' || coalesce(v_q, '-') || ' / ' || v_m::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- b) o fator em uso (1,7×): os mesmos 6,5 de 4 não passam de 6,8 → nenhuma pergunta
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.os100_em_andamento(true);
    perform public._agenda_aprender_medir(c_hoje);
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fator}' where id;
    perform public._agenda_aprender_fator(c_hoje, c_agora);
    v := public._agenda_vigia_estouro(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O3b com 1,7× em uso (energia em motorhome): a mesma OS não pergunta',
      v ->> 'criadas' = '0' and not exists (select 1 from public.agenda_perguntas q where q.chave like 'estouro:' || pg_temp.os('100') || ':%')
      and (public.agenda_fator_de_campo(pg_temp.os('100'), c_hoje) ->> 'fator')::numeric = 1.7,
      v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- c) um fator aprendido menor que o padrão: 6 de 4 é exatamente 1,5× (não pergunta com o padrão) e passa de 1,25× → pergunta
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.os100_em_andamento(false);
    perform public._agenda_aprender_medir(c_hoje);
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform public._agenda_aprender_fator(c_hoje, c_agora);
    v := public._agenda_vigia_estouro(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O3c com o padrão, 6 feitos de 4 (exatamente 1,5×) não perguntam', v ->> 'criadas' = '0', v::text);
    -- o medido de rv:energia como se fosse 1,25 (só aqui: a linha é escrita pelo gravador na rodada)
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fator}' where id;
    update public.agenda_aprendizado set calculado = 1.25, em_uso = 1.25, estado = 'em_uso', em_uso_desde = c_agora
     where item = 'fator' and chave = 'rv:energia';
    v := public._agenda_vigia_estouro(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O3d com 1,25× em uso: os mesmos 6 de 4 passam de 5 → pergunta',
      v ->> 'criadas' = '1' and exists (select 1 from public.agenda_perguntas q where q.chave = 'estouro:' || pg_temp.os('100') || ':4'),
      v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$o3$;

-- ── O4. O R$ por diária ─────────────────────────────────────────────────────────────────────────────────
do $o4$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-30';
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  v   jsonb;
  d0  jsonb;
  d1  jsonb;
  a   public.agenda_aprendizado;
  v_q public.agenda_perguntas;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('O4 o R$ por diária (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform public._agenda_aprender_medir(c_hoje);
    d0 := public.os_duracao_sugerida(pg_temp.os('100'));
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v := public._agenda_aprender_mo(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'mo' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'O4a as 10 medidas válidas com diarista (a 140, só do dono, fora): R$ 22.485 ÷ 20,5 diárias = R$ 1.096,83, em teste',
      v ->> 'estado' = 'sombra' and a.calculado = 1096.83 and a.n = 10 and a.padrao = 764 and a.n_min = 6
      and (a.detalhe ->> 'mo')::numeric = 22485 and (a.detalhe ->> 'diarias')::numeric = 20.5
      and not exists (select 1 from jsonb_array_elements(a.amostra) e where e ->> 'numero' in ('OS-00140', 'OS-00141', 'OS-00142', 'OS-00143'))
      and a.texto = 'Em teste: cada diária rendeu R$ 1.097 de mão de obra (10 OS com diária ligada); para estimar os dias pelo valor uso R$ 764 (padrão).',
      v::text || ' / ' || to_jsonb(a)::text);
    d1 := public.os_duracao_sugerida(pg_temp.os('100'));
    v_res := pg_temp.ok(v_res, 'O4b em teste a duração "pelo valor" é a de antes (R$ 764: 7,51 diárias no realista; sem mo_fonte)',
      d1 = d0 and (d1 ->> 'dp_realista')::numeric = 7.51 and not d1 ? 'mo_fonte' and public._agenda_mo_por_diaria_real() = 764,
      d1::text);

    -- ligado: 1.096,83 contra 764 é 43,6% (> mo_troca_max) → pergunta, e vale o de hoje
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{mo}' where id;
    v := public._agenda_aprender_mo(c_hoje, c_agora);
    select * into v_q from public.agenda_perguntas where id = (v ->> 'pergunta_id')::uuid;
    v_res := pg_temp.ok(v_res, 'O4c ligado, a troca grande (R$ 764 → R$ 1.097) vira pergunta crítica; até a resposta vale R$ 764',
      v ->> 'estado' = 'pergunta' and v_q.tipo = 'aprendizado' and v_q.critica and v_q.chave = 'aprendizado:mo:todas'
      -- (correção C2, texto 5) a conta inclui as OS em que o dono também trabalhou; a opção 1 sem o "(recomendo)"
      and v_q.texto = 'Medi a mão de obra por diária: cada diária rendeu R$ 1.097 (10 OS com diária ligada; inclui as OS em que você também trabalhou), e hoje eu uso R$ 764 para estimar os dias pelo valor. É uma troca grande. 1) Passo a usar R$ 1.097; 2) Fico com R$ 764.'
      and public._agenda_mo_por_diaria_real() = 764 and not public.os_duracao_sugerida(pg_temp.os('100')) ? 'mo_fonte',
      v::text || ' / ' || coalesce(v_q.texto, '-'));

    -- a mão de obra das 3 OS que não são de energia igualada a R$ 690 × as diárias delas (138: 1, 139: 2, 144: 1)
    update public.service_order_services s set unit_price_snapshot = x.v, line_total = x.v
      from (values ('138', 690), ('139', 1380), ('144', 690)) x(n, v)
     where s.service_order_id = pg_temp.os(x.n);
    perform public._agenda_aprender_medir(c_hoje);
    v := public._agenda_aprender_mo(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'mo' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'O4d com a mão de obra das 10 a R$ 690 por diária: entra sozinho (9,7% ≤ mo_troca_max), com a ação; a pergunta de antes sai',
      v ->> 'estado' = 'em_uso' and a.em_uso = 690 and a.calculado = 690 and v ->> 'acao_id' is not null
      and (select x.texto from public.agenda_acoes x where x.id = (v ->> 'acao_id')::uuid)
          = 'Cada diária rendeu R$ 690 de mão de obra (10 OS): passei a estimar os dias pelo valor com R$ 690 (era R$ 764). *desfaz aprendizado* volta.'
      and (select q.estado from public.agenda_perguntas q where q.id = v_q.id) = 'resolvida'
      and a.texto = 'Cada diária rendeu R$ 690 de mão de obra (10 OS com diária ligada): é o que uso para estimar os dias pelo valor desde sex 30/10.',
      v::text || ' / ' || to_jsonb(a)::text);
    d1 := public.os_duracao_sugerida(pg_temp.os('100'));
    v_res := pg_temp.ok(v_res, 'O4e a duração "pelo valor" com R$ 690: 5.739 ÷ 690 = 8,32 diárias no realista, mo_fonte aprendido; o resto igual',
      public._agenda_mo_por_diaria_real() = 690 and (d1 ->> 'dp_realista')::numeric = 8.32 and d1 ->> 'mo_fonte' = 'aprendido'
      and (d1 ->> 'mo_por_diaria')::numeric = 690
      and (d1 - 'dp_realista' - 'mo_fonte' - 'mo_por_diaria') = (d0 - 'dp_realista'),
      d1::text);
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v_res := pg_temp.ok(v_res, 'O4f o modo em sombra: a duração volta a ser a de antes na hora',
      public.os_duracao_sugerida(pg_temp.os('100')) = d0, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$o4$;

-- ── O5. A presença do dono ──────────────────────────────────────────────────────────────────────────────
do $o5$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-30';
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  v    jsonb;
  m0   jsonb;
  m69  text;
  m104 text;
  p100 jsonb;
  v_q  public.agenda_perguntas;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('O5 a presença do dono (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform public._agenda_aprender_medir(c_hoje);
    p100 := public.os_presenca_do_dono(pg_temp.os('100'));
    m0 := public.agenda_meios_da_os(pg_temp.os('100'), c_hoje);
    m69 := md5(public.agenda_meios_da_os(pg_temp.os('069'), c_hoje)::text || public.os_presenca_do_dono(pg_temp.os('069'))::text);
    m104 := md5(public.agenda_meios_da_os(pg_temp.os('104'), c_hoje)::text || public.os_presenca_do_dono(pg_temp.os('104'))::text);

    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v := public._agenda_aprender_presenca(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O5a em teste: desde a 1ª ida registrada (20/10), 3 de 4 OS de energia em motorhome → o dia todo, em rv:energia e sistema:energia; todas medindo (correção C1, item 7: uma classe só)',
      v = '{"desde": "2026-10-20", "chaves": 3, "estados": {"sombra": 2, "medindo": 1}, "acoes": 0, "perguntas": 0, "erros": 0}'
      and pg_temp.linhas('presenca') = 'rv:energia=1.00/4/sombra sistema:energia=1.00/4/sombra todas=-/4/medindo'
      and (select bool_and(a.detalhe ->> 'k' = '3' and a.padrao = 0) from public.agenda_aprendizado a where a.item = 'presenca'),
      v::text || ' / ' || pg_temp.linhas('presenca'));
    v_res := pg_temp.ok(v_res, 'O5b o texto do foco em teste (spec §6.2), e a presença da OS não muda',
      (select texto from public.agenda_aprendizado where item = 'presenca' and chave = 'rv:energia')
        = 'Você foi a 3 de 4 OS de energia em motorhome sem estar no plano: em teste, eu contaria com você o dia todo nelas.'
      and public.os_presenca_do_dono(pg_temp.os('100')) = p100 and p100 ->> 'fonte' = 'regra',
      (select texto from public.agenda_aprendizado where item = 'presenca' and chave = 'rv:energia'));

    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{presenca}' where id;
    v := public._agenda_aprender_presenca(c_hoje, c_agora);
    select * into v_q from public.agenda_perguntas where chave = 'aprendizado:presenca:todas' and estado = 'aberta';
    v_res := pg_temp.ok(v_res, 'O5c ligado: na classe e no sistema entra sozinha (2 ações); no geral, medindo e sem a pergunta (correção C1, item 7: as mesmas OS de uma classe só; a pergunta do geral, com mais de uma classe, é o O9g2)',
      v ->> 'estados' = '{"em_uso": 2, "medindo": 1}' and v ->> 'acoes' = '2' and v ->> 'perguntas' = '0'
      and (select x.texto from public.agenda_acoes x where x.tipo = 'aprendizado' and x.depois ->> 'chave' = 'rv:energia')
          = 'Você foi a 3 de 4 OS de energia em motorhome sem estar no plano: passei a contar com você o dia todo nas próximas dessas OS (as que você não disse como é). *desfaz aprendizado* volta ao abre e fecha.'
      and v_q.id is null,
      v::text || ' / ' || coalesce(v_q.texto, '-'));

    v := public.os_presenca_do_dono(pg_temp.os('100'));
    v_res := pg_temp.ok(v_res, 'O5d a OS de energia em motorhome sem plano publicado: o dia todo, pelo que a agenda aprendeu',
      v = '{"presenca": "sempre", "motivo": "você foi a 3 de 4 OS de energia em motorhome", "fonte": "aprendida"}', v::text);
    v := public.agenda_meios_da_os(pg_temp.os('100'), c_hoje);
    v_res := pg_temp.ok(v_res, 'O5e o motor usa a aprendida: o dono no turno inteiro dos 6 meios-dias (1 diarista a menos por turno), sem abrir e fechar',
      v ->> 'presenca' = 'sempre' and v ->> 'presenca_motivo' = 'você foi a 3 de 4 OS de energia em motorhome'
      and v -> 'dono_turno' = '{"manha": true, "tarde": true}' and v ->> 'abre' = 'false' and v ->> 'fecha' = 'false'
      and (select bool_and(k -> 'dono' = '["turno"]' and k ->> 'desejado' = '1') from jsonb_array_elements(v -> 'molde') k)
      and v ->> 'total' = m0 ->> 'total' and m0 ->> 'presenca' = 'abre_e_fecha',
      v::text);
    v := public.os_presenca_do_dono(pg_temp.os('112'));
    v_res := pg_temp.ok(v_res, 'O5f o recuo ao sistema: a OS de energia em barco (sem classe fina aprendida) pela de energia',
      v = '{"presenca": "sempre", "motivo": "você foi a 3 de 4 OS de energia", "fonte": "aprendida"}', v::text);
    v_res := pg_temp.ok(v_res, 'O5g o publicado não muda: a OS-00069 (energia em barco, 8 meios-dias publicados) e a OS-00104 (publicada) têm a presença e o motor de antes, byte a byte',
      md5(public.agenda_meios_da_os(pg_temp.os('069'), c_hoje)::text || public.os_presenca_do_dono(pg_temp.os('069'))::text) = m69
      and md5(public.agenda_meios_da_os(pg_temp.os('104'), c_hoje)::text || public.os_presenca_do_dono(pg_temp.os('104'))::text) = m104
      and public.os_presenca_do_dono(pg_temp.os('069')) ->> 'fonte' = 'regra',
      public.os_presenca_do_dono(pg_temp.os('069'))::text);
    -- a OS-00100 ganha um meio-dia publicado: deixa de usar a aprendida
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (pg_temp.os('100'), 'bb000000-0000-4000-8000-000000000004', date '2026-11-20', 'manha', 'turno', 'execucao', 'publicada',
            'motor', c_agora);
    v := public.os_presenca_do_dono(pg_temp.os('100'));
    v_res := pg_temp.ok(v_res, 'O5h a mesma OS com um meio-dia publicado volta à regra de hoje (o publicado não muda pelo aprendizado)',
      v = p100, v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O que o dono disse e a regra d05 vêm antes; o técnico fica com a regra; o "passou" não conta.
  begin
    execute current_setting('agenda_teste.fase6');
    perform public._agenda_aprender_medir(c_hoje);
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{presenca}' where id;
    perform public._agenda_aprender_presenca(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O5i o técnico (sem ler a config) recebe a presença da regra, sem erro; o administrador, a aprendida',
      pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
        format($q$select coalesce(public.os_presenca_do_dono(%L) ->> 'fonte', '-')$q$, pg_temp.os('100'))) in ('regra', '-')
      and pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
        format($q$select public.os_presenca_do_dono(%L) ->> 'fonte'$q$, pg_temp.os('100'))) = 'aprendida',
      pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
        format($q$select public.os_presenca_do_dono(%L)::text$q$, pg_temp.os('100'))));
    update public.os_planejamento set dono_presenca = 'abre_e_fecha' where service_order_id = pg_temp.os('100');
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set service_type = 'diagnosis' where id = pg_temp.os('112');
    perform set_config('agenda.porta', 'off', true);
    v_res := pg_temp.ok(v_res, 'O5j o que o dono disse (abre e fecha na OS-00100) e a regra d05 (diagnóstico na OS-00112) vêm antes da aprendida',
      public.os_presenca_do_dono(pg_temp.os('100')) = '{"presenca": "abre_e_fecha", "motivo": "você disse", "fonte": "dono"}'
      and public.os_presenca_do_dono(pg_temp.os('112')) = '{"presenca": "sempre", "motivo": "diagnóstico", "fonte": "regra"}',
      public.os_presenca_do_dono(pg_temp.os('100'))::text || ' / ' || public.os_presenca_do_dono(pg_temp.os('112'))::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute current_setting('agenda_teste.fase6');
    -- a ida da 136 vira "passou" (a conferência, sem dizer quanto): 2 de 4 → abre e fecha
    update public.agenda_intervencoes_do_dono set dita = 'passou' where service_order_id = pg_temp.os('136');
    perform public._agenda_aprender_medir(c_hoje);
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{presenca}' where id;
    v := public._agenda_aprender_presenca(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O5k o "passou" não conta: com a ida da 136 como passou, 2 de 4 (abaixo de presenca_intervencoes_min) → o abre e fecha, sem ação nem pergunta',
      pg_temp.linhas('presenca') = 'rv:energia=0.00/4/em_uso sistema:energia=0.00/4/em_uso todas=-/4/medindo'
      and v ->> 'acoes' = '0' and v ->> 'perguntas' = '0'
      and (select a.detalhe ->> 'k' from public.agenda_aprendizado a where a.item = 'presenca' and a.chave = 'rv:energia') = '2'
      and public.os_presenca_do_dono(pg_temp.os('100')) ->> 'fonte' = 'regra',
      v::text || ' / ' || pg_temp.linhas('presenca'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$o5$;

-- ── O6. As cópias, as assinaturas e as portas (em qualquer lugar) ────────────────────────────────────────
do $o6$
declare
  v_pro text := coalesce(current_setting('agenda_teste.mig_prontidao_fase1', true), '');
  v_vig text := coalesce(current_setting('agenda_teste.mig_conferencia_fase2', true), '');
  v_med text := coalesce(current_setting('agenda_teste.mig_medicao_fase6', true), '');
  rc record;
begin
  -- a assinatura, a língua, a volatilidade e a segurança das recriadas são as de antes
  insert into _resultado
  select format('O6a %s: a mesma assinatura (%s → %s), %s, volatilidade %s, invoker, search_path fixo', r.f, r.args, r.ret, r.lang, r.vol),
         p.oid is not null and pg_get_function_identity_arguments(p.oid) = r.args and pg_get_function_result(p.oid) = r.ret
         and l.lanname = r.lang and p.provolatile = r.vol and not p.prosecdef
         and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%',
         format('%s(%s) → %s, %s, %s, definer %s', p.proname, pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid),
                l.lanname, p.provolatile, p.prosecdef)
    from (values ('os_presenca_do_dono', 'p_so_id uuid', 'jsonb', 'sql', 's'),
                 ('os_duracao_sugerida', 'p_so_id uuid', 'jsonb', 'plpgsql', 's'),
                 ('_agenda_vigia_estouro', 'p_hoje date, p_agora timestamp with time zone', 'jsonb', 'plpgsql', 'v'),
                 ('_agenda_aprendizado_texto', 'p_item text, p_momento text, p_d jsonb', 'text', 'plpgsql', 'i')) r(f, args, ret, lang, vol)
    left join pg_proc p on p.oid = to_regprocedure('public.' || r.f || '(' ||
         case r.f when '_agenda_vigia_estouro' then 'date, timestamptz' when '_agenda_aprendizado_texto' then 'text, text, jsonb' else 'uuid' end || ')')
    left join pg_language l on l.oid = p.prolang;

  -- as portas: as leituras (novas e a classe de campo) para authenticated e service_role; os passos para ninguém; as recriadas
  -- como antes; nunca anon
  insert into _resultado
  select format('O6b %s: %s', f, quem),
         not has_function_privilege('anon', to_regprocedure(f), 'execute')
         and has_function_privilege('authenticated', to_regprocedure(f), 'execute') = (quem = 'leitura')
         and has_function_privilege('service_role', to_regprocedure(f), 'execute') = (quem = 'leitura')
         and (select not p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
                     and p.provolatile = case when quem = 'leitura' then p.provolatile else 'v' end
                from pg_proc p where p.oid = to_regprocedure(f)),
         null
    from (values ('public.agenda_fator_de_campo(uuid, date)', 'leitura'), ('public._agenda_mo_por_diaria_real()', 'leitura'),
                 ('public._agenda_presenca_aprendida(uuid)', 'leitura'), ('public._agenda_classe_de_campo(uuid)', 'leitura'),
                 ('public.os_duracao_sugerida(uuid)', 'leitura'), ('public.os_presenca_do_dono(uuid)', 'leitura'),
                 ('public._agenda_aprendizado_texto(text, text, jsonb)', 'leitura'),
                 ('public._agenda_aprender_fator(date, timestamptz)', 'interna'),
                 ('public._agenda_aprender_mo(date, timestamptz)', 'interna'),
                 ('public._agenda_aprender_presenca(date, timestamptz)', 'interna'),
                 ('public._agenda_vigia_estouro(date, timestamptz)', 'interna')) t(f, quem);
  insert into _resultado
  select 'O6c as leituras novas são STABLE (o fator de campo, o R$ por diária, a presença aprendida)',
         bool_and(p.provolatile = 's'), string_agg(p.proname || ':' || p.provolatile::text, ', ')
    from pg_proc p where p.oid in (to_regprocedure('public.agenda_fator_de_campo(uuid, date)'),
                                   to_regprocedure('public._agenda_mo_por_diaria_real()'),
                                   to_regprocedure('public._agenda_presenca_aprendida(uuid)'));
  insert into _resultado
  select 'O6d o técnico e o anon recebem 42501 no fator de campo (o que a agenda aprendeu é do administrador e do financeiro)',
         pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
           $q$select public.agenda_fator_de_campo('05000000-0000-4000-8000-000000000100', date '2026-10-30')::text$q$) like 'erro 42501%'
         and pg_temp.como(null, 'anon',
           $q$select public.agenda_fator_de_campo('05000000-0000-4000-8000-000000000100', date '2026-10-30')::text$q$) like 'erro 42501%'
         and pg_temp.como(null, 'authenticated',
           $q$select public.agenda_fator_de_campo('05000000-0000-4000-8000-000000000100', date '2026-10-30')::text$q$) like 'erro 42501%',
         pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
           $q$select public.agenda_fator_de_campo('05000000-0000-4000-8000-000000000100', date '2026-10-30')::text$q$);

  if v_pro = '' or v_vig = '' or v_med = '' then
    insert into _resultado values ('O6e as cópias', true, 'PULADO: sem agenda_teste.mig_* (rode pela bancada)');
    return;
  end if;
  for rc in
    select * from (values
      ('os_duracao_sugerida', 'public.os_duracao_sugerida(uuid)', v_pro, '20261024160400'),
      ('os_presenca_do_dono', 'public.os_presenca_do_dono(uuid)', v_pro, '20261024160400'),
      ('_agenda_vigia_estouro', 'public._agenda_vigia_estouro(date, timestamptz)', v_vig, '20261025100300'),
      ('_agenda_aprendizado_texto', 'public._agenda_aprendizado_texto(text, text, jsonb)', v_med, '20261029100100')
    ) t(nome, assinatura, fonte, versao)
  loop
    insert into _resultado
    select format('O6e a cópia de %s (de %s) só acrescenta os blocos "-- FASE 6:"', rc.nome, rc.versao),
           pg_temp.sem_fase6(p.prosrc) = pg_temp.sem_fase6(pg_temp.corpo(rc.fonte, rc.nome))
           and cardinality(pg_temp.sem_fase6(p.prosrc)) > 5
           and (select count(*) from regexp_matches(p.prosrc, '-- FASE 6:', 'g')) > 0,
           format('%s linhas fora dos blocos; %s marcas', cardinality(pg_temp.sem_fase6(p.prosrc)),
                  (select count(*) from regexp_matches(p.prosrc, '-- FASE 6:', 'g')))
      from pg_proc p where p.oid = rc.assinatura::regprocedure;
  end loop;
end
$o6$;

-- ── O7. Em teste, byte a byte o de antes ────────────────────────────────────────────────────────────────
do $o7$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-30';
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  v_pro text := coalesce(current_setting('agenda_teste.mig_prontidao_fase1', true), '');
  v_dif text;
  v_n   int;
  m_des text;
  m_som text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' or v_pro = '' then
    insert into _resultado values ('O7 em teste, o de antes (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    -- as definições de antes, como pg_temp, a partir do texto da migration de 20261024160400
    execute replace(pg_temp.inteira(v_pro, 'os_duracao_sugerida'), 'create or replace function public.os_duracao_sugerida(',
                    'create function pg_temp.duracao_de_antes(');
    execute replace(pg_temp.inteira(v_pro, 'os_presenca_do_dono'), 'create or replace function public.os_presenca_do_dono(',
                    'create function pg_temp.presenca_de_antes(');
    select md5(string_agg(public.agenda_meios_da_os(k.service_order_id, c_hoje)::text, '|' order by k.service_order_id))
      into m_des from public.os_carteira(c_hoje) k;
    perform public._agenda_aprender_medir(c_hoje);
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform public._agenda_aprender_fator(c_hoje, c_agora);
    perform public._agenda_aprender_mo(c_hoje, c_agora);
    perform public._agenda_aprender_presenca(c_hoje, c_agora);
    select count(*), string_agg(so.service_order_number, ', ') filter (where
             public.os_duracao_sugerida(so.id) is distinct from pg_temp.duracao_de_antes(so.id)
             or public.os_presenca_do_dono(so.id) is distinct from pg_temp.presenca_de_antes(so.id))
      into v_n, v_dif from public.service_orders so;
    select md5(string_agg(public.agenda_meios_da_os(k.service_order_id, c_hoje)::text, '|' order by k.service_order_id))
      into m_som from public.os_carteira(c_hoje) k;
    v_res := pg_temp.ok(v_res, 'O7a em teste (com tudo calculado: o fator, o R$ por diária e a presença), a duração e a presença de todas as OS são as de antes, byte a byte, e o motor da carteira também',
      v_dif is null and v_n > 30 and m_som = m_des, format('%s OS; diferentes: %s', v_n, coalesce(v_dif, '—')));
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{}' where id;
    perform public._agenda_aprender_mo(c_hoje, c_agora);
    perform public._agenda_aprender_presenca(c_hoje, c_agora);
    select string_agg(so.service_order_number, ', ') filter (where
             public.os_duracao_sugerida(so.id) is distinct from pg_temp.duracao_de_antes(so.id)
             or public.os_presenca_do_dono(so.id) is distinct from pg_temp.presenca_de_antes(so.id))
      into v_dif from public.service_orders so;
    v_res := pg_temp.ok(v_res, 'O7b ligado com a lista vazia: o mesmo (nada em uso)', v_dif is null, coalesce(v_dif, '—'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$o7$;

-- ── O8. Os textos do R$ por diária e da presença (em qualquer lugar: só a função) ───────────────────────
insert into _resultado
select 'O8 ' || t.nome, public._agenda_aprendizado_texto(t.item, t.momento, t.d::jsonb) = t.espera,
       public._agenda_aprendizado_texto(t.item, t.momento, t.d::jsonb)
  from (values
    ('a1 R$ por diária, medindo', 'mo', 'foco_medindo', '{"chave": "todas", "n": 4, "n_min": 6, "padrao": 764}',
     'Valor por diária: 4 de 6 OS com diária ligada medidas; para estimar os dias pelo valor uso R$ 764 (padrão).'),
    ('a2 R$ por diária, a troca esperando a resposta', 'mo', 'foco_pergunta', '{"chave": "todas", "calculado": 1096.83, "n": 10, "efetivo": 764}',
     'Cada diária rendeu R$ 1.097 de mão de obra (10 OS com diária ligada), e hoje uso R$ 764 para estimar os dias pelo valor: a troca espera a sua resposta.'),
    ('a3 R$ por diária, travado', 'mo', 'foco_travado', '{"chave": "todas", "calculado": 1096.83, "n": 10, "efetivo": 764, "travado_ate": "2026-11-27"}',
     'Cada diária rendeu R$ 1.097 de mão de obra (10 OS com diária ligada); para estimar os dias pelo valor fico com R$ 764 até sex 27/11, como você decidiu.'),
    ('a4 R$ por diária, desfeito (volta ao padrão)', 'mo', 'desfeito', '{"chave": "todas", "volta": null, "padrao": 764, "trava_dias": 28}',
     'Desfeito: para estimar os dias pelo valor volto a R$ 764 por diária. Não troco de novo por 28 dias, salvo se o medido mudar muito.'),
    ('a5 R$ por diária, fico com o de agora', 'mo', 'fico', '{"chave": "todas", "efetivo": 764}',
     'Combinado: fico com R$ 764 por diária. Volto a perguntar se o medido mudar muito.'),
    ('b1 presença, medindo', 'presenca', 'foco_medindo', '{"chave": "rv:energia", "n": 2, "n_min": 4}',
     'As OS de energia em motorhome: 2 de 4 OS medidas para saber se você fica o dia todo; conto com você para abrir e fechar (padrão).'),
    ('b2 presença no sistema, em uso', 'presenca', 'foco_em_uso', '{"chave": "sistema:energia", "n": 4, "em_uso": 1, "desde": "2026-10-30", "detalhe": {"k": 3}}',
     'Você foi a 3 de 4 OS de energia sem estar no plano: conto com você o dia todo nelas desde sex 30/10.'),
    ('b3 presença no geral, a pergunta (spec §6.3)', 'presenca', 'pergunta', '{"chave": "todas", "calculado": 1, "n": 8, "detalhe": {"k": 5}}',
     'Você foi a 5 de 8 OS sem estar no plano. Quer que eu conte com você o dia todo por padrão, e não só para abrir e fechar?'),
    ('b4 presença no geral, esperando a resposta', 'presenca', 'foco_pergunta', '{"chave": "todas", "calculado": 1, "n": 8, "detalhe": {"k": 5}}',
     'Você foi a 5 de 8 OS sem estar no plano: perguntei se passo a contar com você o dia todo por padrão; espero a sua resposta.'),
    ('b5 presença no geral, travada no abre e fecha', 'presenca', 'foco_travado', '{"chave": "todas", "calculado": 1, "n": 8, "efetivo": 0, "travado_ate": "2026-11-27", "detalhe": {"k": 5}}',
     'Você foi a 5 de 8 OS sem estar no plano; fico com o abre e fecha até sex 27/11, como você decidiu.'),
    ('b6 presença, a ação de volta ao abre e fecha', 'presenca', 'acao', '{"chave": "rv:energia", "calculado": 0, "n": 5, "detalhe": {"k": 1}}',
     'Você foi a 1 de 5 OS de energia em motorhome sem estar no plano: voltei a contar com você só para abrir e fechar nas próximas dessas OS (as que você não disse como é). *desfaz aprendizado* volta ao dia todo.'),
    ('b7 presença, desfeito', 'presenca', 'desfeito', '{"chave": "rv:energia", "volta": null, "trava_dias": 28}',
     'Desfeito: nas OS de energia em motorhome volto a contar com você só para abrir e fechar. Não troco de novo por 28 dias, salvo se o medido mudar muito.'),
    ('b8 presença, fico com o de agora', 'presenca', 'fico', '{"chave": "todas", "efetivo": 0}',
     'Combinado: fico com o abre e fecha. Volto a perguntar se o medido mudar muito.')
  ) t(nome, item, momento, d, espera);

insert into _resultado
select 'O8c nenhum jargão nos textos do R$ por diária e da presença (P80, percentil, amostra, fator de campo, "du")',
       bool_and(x !~* '(p80|percentil|amostra|fator de campo|\mdu\M)'), string_agg(x, ' | ') filter (where x ~* '(p80|percentil|amostra|fator de campo|\mdu\M)')
  from (select public._agenda_aprendizado_texto(i, m, '{"chave": "rv:energia", "calculado": 1, "em_uso": 1, "efetivo": 0, "padrao": 0, "n": 4, "n_min": 4, "desde": "2026-10-30", "travado_ate": "2026-11-27", "trava_dias": 28, "detalhe": {"k": 3}}') as x
          from unnest(array['mo', 'presenca']) i,
               unnest(array['foco_medindo', 'foco_sombra', 'foco_em_uso', 'foco_pergunta', 'foco_travado', 'acao', 'pergunta',
                            'opcao1', 'opcao2', 'opcao3', 'desfeito', 'fico']) m) t;

-- ── O9. A correção C1 (20261029100900): itens 3, 7 e 15; regressão B3 ────────────────────────────────────
-- (item 3) a presença guardada na 1ª publicação: publicado o 1º dia com o dono o dia todo, o resto da OS continua assim, e o
-- cartão diz que foi o que a agenda mediu quando planejou (o rev-f6 c2). (item 7) a presença geral só com mais de uma classe.
-- (item 15) com o fator aprendido em uso, a vigia conta as diárias ligadas fora do plano, como a medida. (B3) a vigia do
-- estouro não lê o fator fora de ligado, e o erro dele não a derruba.
do $o9$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-30';
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  v    jsonb;
  v_p  jsonb;
  v_ap jsonb;
  v_m  jsonb;
  v_q  text;
  v_c  numeric;
  v_n0 jsonb;
  v_err text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('O9 a correção C1 da OS (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;

  -- (item 3) a OS-00100 (energia em motorhome, sem plano) publicada pelo motor com a presença aprendida
  begin
    execute current_setting('agenda_teste.fase6');
    perform public._agenda_aprender_medir(c_hoje);
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{presenca}', modo_proposta = 'ligado' where id;
    perform public._agenda_aprender_presenca(c_hoje, c_agora);
    v_p := public.agenda_propor('os', null, null, array[pg_temp.os('100')], '{}'::jsonb, true, 'motor', null, c_hoje,
                                timestamptz '2026-10-30 16:30-03');
    v_ap := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'motor', null, null, c_hoje, timestamptz '2026-10-30 16:31-03');
    v_res := pg_temp.ok(v_res, 'O9a (C1, item 3) a 1ª publicação guarda a presença aprendida com que a OS entrou no plano (os_planejamento.presenca_publicada sempre, com o motivo)',
      v_ap ->> 'ok' = 'true'
      and (select to_jsonb(pl) ->> 'presenca_publicada' from public.os_planejamento pl where pl.service_order_id = pg_temp.os('100')) = 'sempre'
      and (select to_jsonb(pl) ->> 'presenca_publicada_motivo' from public.os_planejamento pl where pl.service_order_id = pg_temp.os('100'))
          = 'você foi a 3 de 4 OS de energia em motorhome',
      coalesce(v_ap ->> 'texto', '—'));
    v := public.os_presenca_do_dono(pg_temp.os('100'));
    v_m := public.agenda_meios_da_os(pg_temp.os('100'), c_hoje);
    v_res := pg_temp.ok(v_res, 'O9b (C1, item 3) publicado o plano, o resto da OS continua com você o dia todo (a presença guardada; o motor: dono no turno, sem abrir e fechar)',
      v ->> 'presenca' = 'sempre' and v ->> 'fonte' = 'aprendida' and v ->> 'motivo' = 'você foi a 3 de 4 OS de energia em motorhome'
      and v_m -> 'dono_turno' = '{"manha": true, "tarde": true}' and v_m ->> 'fecha' = 'false' and v_m ->> 'presenca' = 'sempre',
      v::text || ' / ' || v_m::text);
    v_res := pg_temp.ok(v_res, 'O9c (C1, item 3) o cartão diz que foi o que a agenda mediu quando planejou',
      public.os_plano_da_os(pg_temp.os('100'), c_hoje) #>> '{presenca_dono,texto}'
        = 'Você fica o tempo todo (pelo que medi quando planejei: você foi a 3 de 4 OS de energia em motorhome)',
      public.os_plano_da_os(pg_temp.os('100'), c_hoje) #>> '{presenca_dono,texto}');
    -- o publicado não muda pelo aprendizado: a aprendida de agora volta a abre e fecha (a ida da 136 vira "passou"), e a OS
    -- publicada fica como foi planejada
    update public.agenda_intervencoes_do_dono set dita = 'passou' where service_order_id = pg_temp.os('136');
    perform public._agenda_aprender_presenca(c_hoje, timestamptz '2026-10-30 16:40-03');
    v := public.os_presenca_do_dono(pg_temp.os('100'));
    v_res := pg_temp.ok(v_res, 'O9d (C1, item 3) a aprendida de agora volta ao abre e fecha, e a OS já publicada continua o dia todo (a guardada)',
      v ->> 'presenca' = 'sempre' and pg_temp.linhas('presenca') like 'rv:energia=0.00/4/%', v::text || ' / ' || pg_temp.linhas('presenca'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 7) a presença geral (todas) com as OS de uma classe só: medindo, sem a pergunta
  begin
    execute current_setting('agenda_teste.fase6');
    perform public._agenda_aprender_medir(c_hoje);
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform public._agenda_aprender_presenca(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O9e (C1, item 7) em teste, com as 4 OS de energia em motorhome (um sistema só), a presença geral fica medindo (sem calculado); a da classe e a do sistema, o dia todo',
      pg_temp.linhas('presenca') = 'rv:energia=1.00/4/sombra sistema:energia=1.00/4/sombra todas=-/4/medindo', pg_temp.linhas('presenca'));
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{presenca}' where id;
    v := public._agenda_aprender_presenca(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O9f (C1, item 7) ligado, a classe e o sistema entram sozinhos e NÃO sai a pergunta "conto com você o dia todo por padrão?"',
      v ->> 'acoes' = '2' and v ->> 'perguntas' = '0'
      and not exists (select 1 from public.agenda_perguntas q where q.chave = 'aprendizado:presenca:todas'), v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- o controle: uma ida a uma OS de diagnóstico (outro sistema), e a de todas passa a ter calculado
  begin
    execute current_setting('agenda_teste.fase6');
    insert into public.agenda_intervencoes_do_dono (service_order_id, dia, prevista, dita, classe, origem, trecho, criado_em)
    values (pg_temp.os('140'), date '2026-09-22', 'nenhuma', 'dia', 'execucao', 'conversa', 'fiquei o dia todo no diagnóstico',
            timestamptz '2026-09-22 18:00-03');
    perform public._agenda_aprender_medir(c_hoje);
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform public._agenda_aprender_presenca(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'O9g (C1, item 7) o controle: com as OS de mais de um sistema (energia, diagnóstico, conforto) e mais OS que a classe mais larga, a de todas tem calculado',
      pg_temp.linhas('presenca') like '%todas=1.00/6/sombra%', pg_temp.linhas('presenca'));
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{presenca}' where id;
    perform public._agenda_aprender_presenca(c_hoje, c_agora);
    v_q := (select q.texto from public.agenda_perguntas q where q.chave = 'aprendizado:presenca:todas' and q.estado = 'aberta' and q.critica
              and jsonb_array_length(q.opcoes) = 2);
    v_res := pg_temp.ok(v_res, 'O9g2 (C1, item 7) e ligado, a pergunta crítica do geral (a regra d05 inteira), com o texto de sempre',
      v_q = 'Você foi a 4 de 6 OS sem estar no plano. Quer que eu conte com você o dia todo por padrão, e não só para abrir e fechar? 1) Sim, o dia todo (recomendo pelo medido); 2) Não, continuo com o abre e fecha.',
      coalesce(v_q, '—'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 15) a OS-00100 em andamento com 6 de 4 meios-dias feitos e 1,7× em uso: sem diária fora do plano, não pergunta; com 2
  -- diárias do Roberto ligadas a ela em dia sem plano (4 meios-dias), a vigia conta 10 — o que a medida contaria
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.os100_em_andamento(false);
    perform public._agenda_aprender_medir(c_hoje);
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fator}' where id;
    perform public._agenda_aprender_fator(c_hoje, c_agora);
    insert into public.work_shifts (id, work_profile_id, data, tipo, fracao, valor_diaria, origem, status, registrado_por,
                                    aprovado_por, aprovado_em)
    select md5('c1:ws:' || d)::uuid, 'cc000000-0000-4000-8000-000000000002', d::date, 'diaria', 1, 180, 'painel', 'aprovado',
           'aa000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001', (d || ' 20:00-03')::timestamptz
      from unnest(array['2026-10-24', '2026-10-30']) d;
    insert into public.work_shift_os (shift_id, service_order_id)
    select md5('c1:ws:' || d)::uuid, pg_temp.os('100') from unnest(array['2026-10-24', '2026-10-30']) d;
    v := public._agenda_vigia_estouro(c_hoje, c_agora);
    select q.texto into v_q from public.agenda_perguntas q where q.chave = 'estouro:' || pg_temp.os('100') || ':4';
    v_res := pg_temp.ok(v_res, 'O9h (C1, item 15) com 1,7× em uso, os 6 meios-dias do plano mais os 4 das 2 diárias fora do plano (10 de 4) passam de 6,8 → a pergunta diz 5 dias',
      v ->> 'criadas' = '1' and v_q = 'Giancarlo (OS-00100) já teve 5 dias de serviço e o combinado era 2 dias. O que falta?',
      v::text || ' / ' || coalesce(v_q, '—'));
    -- a mesma OS concluída: a medida conta os mesmos 10 (os 6 do plano e os 4 fora dele)
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'completed', check_out_at = timestamptz '2026-10-30 12:00-03' where id = pg_temp.os('100');
    perform set_config('agenda.porta', 'off', true);
    perform public.agenda_medir_os(pg_temp.os('100'), c_hoje);
    select m.meios_cumpridos into v_c from public.agenda_medidas_os m where m.service_order_id = pg_temp.os('100');
    v_res := pg_temp.ok(v_res, 'O9i (C1, item 15) a medida da mesma OS conta os mesmos 10 meios-dias (6 do plano + 4 fora dele): a razão da vigia é a da medida',
      v_c = 10, coalesce(v_c::text, '—'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (B3) a classe de campo que lança (uma expressão de classe_sistemas que quebra, por exemplo)
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.os100_em_andamento(true);
    perform public._agenda_aprender_medir(c_hoje);
    create or replace function public._agenda_classe_de_campo(p_os uuid) returns jsonb
    language plpgsql stable as $x$ begin raise exception 'falha de teste na classe de campo'; end $x$;
    update public.agenda_config set modo_aprendizado = 'desligado' where id;
    begin
      v := public._agenda_vigia_estouro(c_hoje, c_agora);
      v_err := null;
    exception when others then
      v := null;
      v_err := sqlerrm;
    end;
    v_res := pg_temp.ok(v_res, 'O9j (C1, B3) em desligado a vigia do estouro nem lê o fator de campo: a classe que lança não a derruba, e a pergunta de sempre sai (6,5 de 4 com 1,5×)',
      v_err is null and v ->> 'criadas' = '1', coalesce(v_err, v::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.os100_em_andamento(true);
    perform public._agenda_aprender_medir(c_hoje);
    create or replace function public._agenda_classe_de_campo(p_os uuid) returns jsonb
    language plpgsql stable as $x$ begin raise exception 'falha de teste na classe de campo'; end $x$;
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fator}' where id;
    begin
      v := public._agenda_vigia_estouro(c_hoje, timestamptz '2026-10-30 16:20-03');
      v_err := null;
    exception when others then
      v := null;
      v_err := sqlerrm;
    end;
    v_res := pg_temp.ok(v_res, 'O9k (C1, B3) ligado com o fator: o erro vira o padrão (1,5×; a mesma pergunta) e vai a app_error_logs (agenda / vigia:estouro)',
      v_err is null and v ->> 'criadas' = '1'
      and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'vigia:estouro'),
      coalesce(v_err, v::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- o CHECK novo (presenca_publicada_coerente): a presença guardada é uma das três, e o motivo não vem sem ela
  begin
  execute current_setting('agenda_teste.fase6');
  begin
    update public.os_planejamento set presenca_publicada = 'talvez' where service_order_id = pg_temp.os('104');
    v_err := 'aceitou';
  exception when others then
    v_err := sqlerrm;
  end;
  begin
    update public.os_planejamento set presenca_publicada = null, presenca_publicada_motivo = 'sem a presença'
     where service_order_id = pg_temp.os('104');
    v_err := v_err || ' / aceitou';
  exception when others then
    v_err := v_err || ' / ' || sqlerrm;
  end;
  v_res := pg_temp.ok(v_res, 'O9l (C1, item 3) o CHECK presenca_publicada_coerente recusa a presença desconhecida e o motivo sem a presença',
    v_err like '%presenca_publicada_coerente% / %presenca_publicada_coerente%'
    and exists (select 1 from public.os_planejamento where service_order_id = pg_temp.os('104')), v_err);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$o9$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
