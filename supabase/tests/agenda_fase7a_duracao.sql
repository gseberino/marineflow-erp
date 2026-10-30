-- Prova da duração do gestor da agenda, Fase 7a (pacote P2): a estimativa do orçamento como dias firmes (a fonte 'orcamento' em
-- agenda_meios_da_os), a mão de obra limpa (sem deslocamento), uma pessoa por serviço (a dupla só marcada), o diagnóstico de meio
-- dia, a situação da OS começada ou parada e o teto da estimativa (migration 20261031100100), sobre a carteira REAL de 29/10 (o
-- replay) e a sintética da 7a.
-- bancada: depende de 20261031100100
--
--   D0 as portas e o nome do serviço (sem fixture): anon nada; as 4 leituras novas e as 2 recriadas para authenticated e
--      service_role; a palavra da dupla só service_role e a única definer; o corte do nome do serviço
--   D1 os_duracao_sugerida das 20 OS do replay e das 8 sintéticas: com o portão falso (desligado, sombra sem a simulação, *gestor,
--      só propor*, as regras fora da lista) = a de antes, byte a byte; com o portão: Lenine 6 dias com 1 pessoa, Vanderlei 7,5,
--      Giancarlo 10, Rodrigo-76 sem o deslocamento (meio dia), Rodrigo-96 diagnóstico (meio dia); cada regra sozinha; o "frete" da
--      descrição da ORÇ-00123 não tira a mão de obra; sem nada além do deslocamento = sem base
--   D2 a dupla: a marcada (todos) = 2 pessoas; o aviso de dupla nas 4 que casam banco de baterias (e na Kalmar), pelo nome do
--      serviço; a Starlink da ORÇ-00119 não casa (o corte); a nota de dupla_notas; o que o dono disse não vira aviso
--   D3 _agenda_os_situacao: Nelson começou sem rastro → 4 dias; a sintética com rastro → 1 dia; o "quanto falta" nunca passa da
--      estimativa; parada há mais de 30 dias; respondida, com compromisso ou sem o portão = não pendente; a pergunta aberta
--   D4 _agenda_gestor_estimativa: cada motivo (dito, regra_desligada, situacao, sem_base, grande, embutida) e o que usa
--   D5 agenda_meios_da_os: o portão falso = a de antes (md5, a cópia de 20261025100200 como pg_temp); a fonte 'orcamento'; o
--      'orcamento' gravado lido como 'sugerida' com o portão falso; as chaves novas só com a regra
--   D6 _agenda_peca_embutida = a v_embut da os_prontidao nas 28 (paridade), com e sem o portão
--   D7 agenda_dupla_dita: o alvo, a marca, o histórico, a ação desfazível, "já estava", fora da carteira, não achado, só o
--      administrador, a linha nova de os_planejamento
--   D8 as cópias: os_duracao_sugerida (de 20261029100200) e agenda_meios_da_os (de 20261025100200) sem os blocos "-- FASE 7:"
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_duracao.sql
--   Seguro em produção: D0 só lê; D1 a D8 usam as fixtures e só rodam na bancada (fora dela saem PULADO). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Executa um comando e diz que porta o recusou ('aceitou' quando entrou, e desfaz; 'erro <estado>: <mensagem>' para o resto).
create function pg_temp.recusa(p_sql text) returns text language plpgsql as $f$
declare
  v_nome text; v_estado text; v_msg text;
begin
  begin
    execute p_sql;
    raise exception using errcode = 'P0001', message = '__aceitou__';
  exception when others then
    get stacked diagnostics v_nome = constraint_name, v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg = '__aceitou__' then return 'aceitou'; end if;
    if v_estado in ('23514', '23505', '23503', '23502', '23P01') then return coalesce(nullif(v_nome, ''), v_estado); end if;
    return 'erro ' || v_estado || ': ' || v_msg;
  end;
end $f$;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- A OS pelo número (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;

-- A função inteira (do "create or replace" ao "$function$;") e só o corpo, a partir do texto da migration.
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;

-- O corpo sem os blocos "-- FASE 7: … -- FASE 7: fim" (o fim lido pelo prefixo).
create function pg_temp.sem_fase7(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 7:' and l !~ '^\s*-- FASE 7: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 7: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;

-- ── D0. As portas e o nome do serviço (sem fixture) ───────────────────────────────────────────────────────
with f(assinatura, quem) as (values
  ('public._agenda_nome_do_servico(text)', 'leitura'),
  ('public._agenda_peca_embutida(uuid)', 'leitura'),
  ('public._agenda_os_situacao(uuid, date)', 'leitura'),
  ('public._agenda_gestor_estimativa(uuid, date)', 'leitura'),
  ('public.os_duracao_sugerida(uuid)', 'leitura'),
  ('public.agenda_meios_da_os(uuid, date)', 'leitura'),
  ('public.agenda_dupla_dita(uuid, text, boolean, date, timestamptz)', 'servico'))
insert into _resultado
select 'D0a anon nada; as leituras novas e as recriadas para authenticated e service_role; a palavra da dupla só service_role',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and has_function_privilege('authenticated', f.assinatura, 'execute') = (f.quem = 'leitura')
                and has_function_privilege('service_role', f.assinatura, 'execute')),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute') <> (f.quem = 'leitura')
                                              or not has_function_privilege('service_role', f.assinatura, 'execute'))
  from f;

insert into _resultado
select 'D0b só a palavra da dupla é security definer (e VOLATILE); as leituras são invoker, STABLE (o nome do serviço IMMUTABLE), com search_path fixo',
       bool_and(p.prosecdef = (p.proname = 'agenda_dupla_dita'))
       and bool_and(p.provolatile = case p.proname when 'agenda_dupla_dita' then 'v' when '_agenda_nome_do_servico' then 'i' else 's' end)
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%') and count(*) = 7,
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('_agenda_nome_do_servico', '_agenda_peca_embutida', '_agenda_os_situacao', '_agenda_gestor_estimativa',
                     'os_duracao_sugerida', 'agenda_meios_da_os', 'agenda_dupla_dita');

insert into _resultado
select 'D0c o nome do serviço: o trecho antes do 1º " — ", " – ", ":" ou "(", normalizado; o hífen comum não corta; nulo = vazio',
       string_agg(coalesce(public._agenda_nome_do_servico(t.nome), '<nulo>'), ' | ' order by t.o)
         = 'instalacao starlink | substituicao baterias chumbo para litio | instalacao do sistema de energia | mao de obra'
           || ' | religacao do inversor | retirada e reinstalacao do tm41 | deslocamento tecnico | ',
       string_agg(coalesce(public._agenda_nome_do_servico(t.nome), '<nulo>'), ' | ' order by t.o)
  from (values (1, 'Instalação Starlink — fixação da antena no teto, alimentado pelo banco de baterias'),
               (2, 'SUBSTITUIÇÃO BATERIAS - CHUMBO PARA LITIO'),
               (3, 'Instalação do sistema de energia – baterias, inversor, carregador'),
               (4, 'Mão de obra: deslocamento até a marina'),
               (5, 'Religação do Inversor (cabos já prontos - remoção/fixação)'),
               (6, 'Retirada e reinstalação do TM41 — retirada, embalagem e envio à Technomaster, frete de ida e volta'),
               (7, 'Deslocamento técnico'),
               (8, null)) t(o, nome);

insert into _resultado
select 'D0d sem o dia de hoje, a situação e a estimativa recusam (22004); a palavra da dupla também (sem o dia, a hora ou o com/sem)',
       pg_temp.recusa('select public._agenda_os_situacao(gen_random_uuid(), null)') like 'erro 22004:%'
       and pg_temp.recusa('select public._agenda_gestor_estimativa(gen_random_uuid(), null)') like 'erro 22004:%'
       and pg_temp.recusa('select public.agenda_dupla_dita(null, ''x'', true, null, now())') like 'erro 22004:%'
       and pg_temp.recusa('select public.agenda_dupla_dita(null, ''x'', null, current_date, now())') like 'erro 22004:%',
       pg_temp.recusa('select public._agenda_os_situacao(gen_random_uuid(), null)');

-- ── D1 a D8: com as fixtures (o replay de 29/10 e a sintética, por cima) ───────────────────────────────────
do $fx$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-29';
  c_agora constant timestamptz := timestamptz '2026-10-29 16:52-03';
  v_os6   text := coalesce(current_setting('agenda_teste.mig_os_fase6', true), '');
  v_mot2  text := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  v_dif   text;
  v_n     int;
  v_m0    text;
  v_m1    text;
  d       jsonb;
  e       jsonb;
  m       jsonb;
  x       jsonb;
  v_q     uuid;
  v_adm   uuid;
  v_tec   uuid;
  v_acoes int;
  v_fonte text;
  v_novo  text;
  r       record;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' or v_os6 = '' or v_mot2 = '' then
    insert into _resultado values ('D1 a D8 (as fixtures da 7a)', true,
      'PULADO: sem agenda_teste.replay2910, agenda_teste.fase7a, mig_os_fase6 e mig_motor_fase2 (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.replay2910');
  execute current_setting('agenda_teste.fase7a');
  -- as definições de antes, como pg_temp, a partir do texto das migrations de onde a 7a copiou
  execute replace(pg_temp.inteira(v_os6, 'os_duracao_sugerida'), 'create or replace function public.os_duracao_sugerida(',
                  'create function pg_temp.duracao_de_antes(');
  execute replace(pg_temp.inteira(v_mot2, 'agenda_meios_da_os'), 'create or replace function public.agenda_meios_da_os(',
                  'create function pg_temp.meios_de_antes(');
  select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
  select u.id into v_tec from public.app_users u where u.role = 'technician' order by u.id limit 1;

  -- ── D1. os_duracao_sugerida ─────────────────────────────────────────────────────────────────────────
  -- (a) com o portão falso, em cada jeito de ele ser falso: a de antes, byte a byte (todas as OS)
  v_dif := null;
  for r in select * from (values
             (1, 'desligado (a linha de produção)', 'desligado', false, null::text[]),
             (2, 'sombra sem a simulação', 'sombra', false, null::text[]),
             (3, 'ligado com *gestor, só propor*', 'ligado', true, null::text[]),
             (4, 'ligado sem regra nenhuma na lista', 'ligado', false, '{}'::text[]),
             (5, 'ligado só com as regras que não são da duração', 'ligado', false, '{estimativa,situacao,sem_peca,embutida_suposta}'::text[])
           ) t(o, nome, modo, so_propor, regras) order by o loop
    update public.agenda_config
       set modo_marcar_sozinho = r.modo, gestor_so_propor = r.so_propor,
           marcar_regras = coalesce(r.regras, '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}')
     where id;
    select count(*), string_agg(so.service_order_number, ', ') filter (where public.os_duracao_sugerida(so.id)
                                                                              is distinct from pg_temp.duracao_de_antes(so.id))
      into v_n, v_novo from public.service_orders so;
    if v_novo is not null then v_dif := concat_ws('; ', v_dif, r.nome || ': ' || v_novo); end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'D1a com o portão falso (desligado, sombra sem a simulação, *gestor, só propor*, sem as regras da duração), a duração das 28 OS é a de antes, byte a byte',
    v_dif is null and v_n = 28, format('%s OS; diferentes: %s', v_n, coalesce(v_dif, '—')));
  -- a simulação da sombra liga o portão (agenda.gestor = 'sombra'), só dentro dela
  update public.agenda_config set modo_marcar_sozinho = 'sombra', gestor_so_propor = false,
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id;
  perform set_config('agenda.gestor', 'sombra', true);
  d := public.os_duracao_sugerida(pg_temp.os('OS-00074'));
  perform set_config('agenda.gestor', '', true);
  v_res := pg_temp.ok(v_res, 'D1b dentro da simulação da sombra (agenda.gestor = sombra) as regras valem; fora dela, não',
    d ->> 'dias_realista' = '6' and d ->> 'pessoas' = '1'
    and public.os_duracao_sugerida(pg_temp.os('OS-00074')) = pg_temp.duracao_de_antes(pg_temp.os('OS-00074')),
    d::text);

  -- (c) com o portão (ligado e as 15 regras)
  update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
  d := public.os_duracao_sugerida(pg_temp.os('OS-00074'));
  v_res := pg_temp.ok(v_res, 'D1c Lenine (OS-00074): 6 dias com 1 pessoa (R$ 4.560 ÷ 764 = 5,97 diárias; eram 3 dias com 2), "regra"',
    d ->> 'dias_realista' = '6' and d ->> 'pessoas' = '1' and d ->> 'dp_realista' = '5.97' and d ->> 'diarias_realista' = '6'
    and d ->> 'texto' = '3 a 6 dias, 1 pessoa (estimativa minha, pelo valor)' and d ->> 'pessoas_motivo' = 'regra'
    and not d ? 'fora_da_mo' and not d ? 'diagnostico', d::text);
  d := public.os_duracao_sugerida(pg_temp.os('OS-00069'));
  e := public.os_duracao_sugerida(pg_temp.os('OS-00130'));
  v_res := pg_temp.ok(v_res, 'D1d Vanderlei (OS-00069) 7,5 dias e Giancarlo (OS-00130) 10 dias, cada um com 1 pessoa',
    d ->> 'dias_realista' = '7.5' and d ->> 'pessoas' = '1' and d ->> 'dp_realista' = '7.33'
    and e ->> 'dias_realista' = '10' and e ->> 'pessoas' = '1' and e ->> 'dp_realista' = '9.87' and e ->> 'diarias_realista' = '10',
    d::text || ' | ' || e::text);
  d := public.os_duracao_sugerida(pg_temp.os('OS-00076'));
  v_res := pg_temp.ok(v_res, 'D1e Rodrigo (OS-00076) sem o "Deslocamento técnico": mão de obra R$ 300 e 1,5 h (eram R$ 500 e 2,5 h), meio dia; fora_da_mo diz o que saiu',
    d ->> 'dias_realista' = '0.5' and d ->> 'mo' = '300.00' and d ->> 'horas' = '1.5'
    and jsonb_array_length(d -> 'fora_da_mo') = 1 and d #>> '{fora_da_mo,0,nome}' = 'Deslocamento técnico'
    and (d #>> '{fora_da_mo,0,valor}')::numeric = 200 and (d #>> '{fora_da_mo,0,horas}')::numeric = 1
    and (d #>> '{fora_da_mo,0,linha}')::uuid = (select s.id from public.service_order_services s
                                                 where s.service_order_id = pg_temp.os('OS-00076') and s.name_snapshot = 'Deslocamento técnico')
    and (pg_temp.duracao_de_antes(pg_temp.os('OS-00076')) ->> 'mo') = '500.00', d::text);
  d := public.os_duracao_sugerida(pg_temp.os('OS-00096'));
  v_res := pg_temp.ok(v_res, 'D1f Rodrigo (OS-00096) é diagnóstico (a linha de maior valor): meio dia com 1 pessoa, "meio dia de diagnóstico; depois eu reavalio"',
    d ->> 'dias_realista' = '0.5' and d ->> 'dias_otimista' = '0.5' and d ->> 'sugerida' = '0.5' and d ->> 'pessoas' = '1'
    and (d ->> 'diagnostico')::boolean and d ->> 'texto' = 'meio dia de diagnóstico; depois eu reavalio'
    and d ->> 'diarias_realista' = '0.5', d::text);
  d := public.os_duracao_sugerida(pg_temp.os('ORÇ-00123'));
  v_res := pg_temp.ok(v_res, 'D1g o "frete de ida e volta" da DESCRIÇÃO da ORÇ-00123 não tira a retirada e a reinstalação do TM41 da mão de obra (o corte do nome do serviço); pela linha inteira, sairia',
    not d ? 'fora_da_mo' and d ->> 'mo' = '3140.00'
    and exists (select 1 from public.service_order_services s, public.agenda_config c
                 where s.service_order_id = pg_temp.os('ORÇ-00123') and c.id
                   and public._agenda_normal(s.name_snapshot) ~ c.mo_fora_regex
                   and public._agenda_nome_do_servico(s.name_snapshot) !~ c.mo_fora_regex), d::text);
  d := public.os_duracao_sugerida(pg_temp.os('OS-97003'));
  v_res := pg_temp.ok(v_res, 'D1h a sintética da Tânia (OS-97003): o deslocamento por hora (2 h, R$ 400) sai; sobra R$ 764 = 1 dia',
    d ->> 'dias_realista' = '1' and d -> 'fora_da_mo' -> 0 ->> 'nome' = 'Deslocamento técnico'
    and (d #>> '{fora_da_mo,0,valor}')::numeric = 400 and (d #>> '{fora_da_mo,0,horas}')::numeric = 2, d::text);
  -- cada regra sozinha
  update public.agenda_config set marcar_regras = '{mo_limpa}' where id;
  d := public.os_duracao_sugerida(pg_temp.os('OS-00076'));
  v_res := pg_temp.ok(v_res, 'D1i só mo_limpa: o deslocamento sai e as pessoas são as de antes (sem pessoas_motivo); o Lenine e o diagnóstico ficam como antes',
    d ? 'fora_da_mo' and not d ? 'pessoas_motivo' and d ->> 'mo' = '300.00'
    and public.os_duracao_sugerida(pg_temp.os('OS-00074')) = pg_temp.duracao_de_antes(pg_temp.os('OS-00074'))
    and public.os_duracao_sugerida(pg_temp.os('OS-00096')) = pg_temp.duracao_de_antes(pg_temp.os('OS-00096')), d::text);
  update public.agenda_config set marcar_regras = '{uma_pessoa}' where id;
  d := public.os_duracao_sugerida(pg_temp.os('OS-00076'));
  v_res := pg_temp.ok(v_res, 'D1j só uma_pessoa: Lenine 6 dias com 1 pessoa; o deslocamento do Rodrigo fica na conta',
    public.os_duracao_sugerida(pg_temp.os('OS-00074')) ->> 'dias_realista' = '6'
    and not d ? 'fora_da_mo' and d ->> 'mo' = '500.00' and d ->> 'pessoas_motivo' = 'regra', d::text);
  update public.agenda_config set marcar_regras = '{diagnostico}' where id;
  v_res := pg_temp.ok(v_res, 'D1k só diagnostico: o Rodrigo-96 é meio dia de diagnóstico; o Lenine fica como antes',
    (public.os_duracao_sugerida(pg_temp.os('OS-00096')) ->> 'diagnostico')::boolean
    and public.os_duracao_sugerida(pg_temp.os('OS-00074')) = pg_temp.duracao_de_antes(pg_temp.os('OS-00074')), null);
  update public.agenda_config
     set marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id;
  -- sem nada além do deslocamento = sem base, dizendo o que saiu
  begin
    delete from public.service_order_services s
     where s.service_order_id = pg_temp.os('OS-00076') and s.name_snapshot <> 'Deslocamento técnico';
    d := public.os_duracao_sugerida(pg_temp.os('OS-00076'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'D1l a OS que só tem o deslocamento fica "sem base" (quantos dias?), dizendo o que saiu',
    (d ->> 'sem_base')::boolean and d ->> 'texto' = 'sem base para estimar: quantos dias?' and jsonb_array_length(d -> 'fora_da_mo') = 1
    and (d ->> 'mo')::numeric = 0 and (d ->> 'horas')::numeric = 0, d::text);

  -- ── D2. A dupla ─────────────────────────────────────────────────────────────────────────────────────────
  d := public.os_duracao_sugerida(pg_temp.os('OS-97002'));
  v_res := pg_temp.ok(v_res, 'D2a a dupla marcada (Sérgio, OS-97002, dupla_dita = todos): 2 pessoas (equipe_sugerida), "dupla_marcada", sem aviso',
    d ->> 'pessoas' = '2' and d ->> 'pessoas_motivo' = 'dupla_marcada' and d ->> 'dias_realista' = '2' and not d ? 'alerta_dupla', d::text);
  select string_agg(format('%s=%s:%s:%s', t.n, a ->> 'motivo', a ->> 'onde', a ->> 'trecho'), ' | ' order by t.n) into v_novo
    from unnest(array['OS-00069', 'OS-00074', 'OS-00112', 'OS-00130']) t(n)
   cross join lateral (select public.os_duracao_sugerida(pg_temp.os(t.n)) -> 'alerta_dupla' a) z;
  v_res := pg_temp.ok(v_res, 'D2b o aviso de dupla nas 4 que casam banco de baterias (Vanderlei, Lenine, Nelson, Giancarlo), pelo nome do serviço, com o trecho que casou; continuam com 1 pessoa',
    v_novo = 'OS-00069=banco_cc:inicio:lifepo | OS-00074=banco_cc:inicio:baterias chumbo | OS-00112=banco_cc:inicio:baterias de chumbo | OS-00130=banco_cc:inicio:barramento'
    and (select bool_and(public.os_duracao_sugerida(pg_temp.os(n)) ->> 'pessoas' = '1')
           from unnest(array['OS-00069', 'OS-00074', 'OS-00112', 'OS-00130']) n)
    and public.os_duracao_sugerida(pg_temp.os('OS-00074')) #>> '{alerta_dupla,nome}' = 'SUBSTITUIÇÃO BATERIAS - CHUMBO PARA LITIO'
    and (public.os_duracao_sugerida(pg_temp.os('OS-00074')) #>> '{alerta_dupla,linha}')::uuid
        = (select s.id from public.service_order_services s where s.service_order_id = pg_temp.os('OS-00074')
             and s.name_snapshot = 'SUBSTITUIÇÃO BATERIAS - CHUMBO PARA LITIO'), v_novo);
  v_res := pg_temp.ok(v_res, 'D2c a Kalmar casa pelo 1º gatilho da lista: OS-00032 o 220 V ("sistema eletrico ac", antes do içamento do gerador), OS-00033 a parelha de motores',
    public.os_duracao_sugerida(pg_temp.os('OS-00032')) #>> '{alerta_dupla,motivo}' = 'ca_energizado'
    and public.os_duracao_sugerida(pg_temp.os('OS-00032')) #>> '{alerta_dupla,onde}' = 'fim'
    and public.os_duracao_sugerida(pg_temp.os('OS-00033')) #>> '{alerta_dupla,motivo}' = 'icamento'
    and public.os_duracao_sugerida(pg_temp.os('OS-00033')) #>> '{alerta_dupla,trecho}' = 'parelha de motores', null);
  select string_agg(n, ', ') into v_novo
    from unnest(array['OS-00104', 'OS-00096', 'OS-00076', 'ORÇ-00083', 'ORÇ-00119']) n
   where public.os_duracao_sugerida(pg_temp.os(n)) ? 'alerta_dupla';
  v_res := pg_temp.ok(v_res, 'D2d sem aviso: Flávio (12V), Rodrigo ×2, Robson e a Starlink da ORÇ-00119 — que pela linha inteira ("… alimentado pelo banco de baterias …") casaria',
    v_novo is null
    and exists (select 1 from public.service_order_services s, public.agenda_config c, jsonb_array_elements(c.dupla_gatilhos) g
                 where s.service_order_id = pg_temp.os('ORÇ-00119') and c.id and s.name_snapshot like 'Instalação Starlink%'
                   and public._agenda_normal(s.name_snapshot) ~ ('\m(' || (g ->> 1) || ')'))
    and not exists (select 1 from public.service_order_services s, public.agenda_config c, jsonb_array_elements(c.dupla_gatilhos) g
                     where s.service_order_id = pg_temp.os('ORÇ-00119') and c.id
                       and public._agenda_nome_do_servico(s.name_snapshot) ~ ('\m(' || (g ->> 1) || ')')),
    coalesce(v_novo, '—'));
  update public.agenda_config set dupla_notas = '[["confinado","refrigeracao"]]' where id;
  x := public.os_duracao_sugerida(pg_temp.os('OS-00104')) -> 'alerta_dupla';
  update public.agenda_config set dupla_notas = '[["confinado","casa de maquinas|paiol|poro\\M|compartimento d[ae] bateria"]]' where id;
  v_res := pg_temp.ok(v_res, 'D2e sem gatilho, a 1ª nota de dupla_notas que casar vira o aviso (nota: true, sem onde)',
    x ->> 'motivo' = 'confinado' and (x ->> 'nota')::boolean and x ->> 'onde' is null and x ->> 'trecho' = 'refrigeracao'
    and not public.os_duracao_sugerida(pg_temp.os('OS-00104')) ? 'alerta_dupla', x::text);
  update public.os_planejamento set dupla_dita = 'nao' where service_order_id = pg_temp.os('OS-00074');
  if not found then
    insert into public.os_planejamento (service_order_id, dupla_dita) values (pg_temp.os('OS-00074'), 'nao');
  end if;
  d := public.os_duracao_sugerida(pg_temp.os('OS-00074'));
  update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2 where service_order_id = pg_temp.os('OS-00074');
  e := public.os_duracao_sugerida(pg_temp.os('OS-00074'));
  update public.os_planejamento set dupla_dita = null, dupla_meios = null where service_order_id = pg_temp.os('OS-00074');
  v_res := pg_temp.ok(v_res, 'D2f o que o dono disse não vira aviso: "sem dupla" (nao) e a dupla por meio-dia do 7b (inicio) = 1 pessoa, sem alerta_dupla',
    d ->> 'pessoas' = '1' and not d ? 'alerta_dupla' and d ->> 'pessoas_motivo' = 'regra'
    and e ->> 'pessoas' = '1' and not e ? 'alerta_dupla'
    and public.os_duracao_sugerida(pg_temp.os('OS-00074')) ? 'alerta_dupla', d::text || ' | ' || e::text);

  -- ── D3. A situação da OS ────────────────────────────────────────────────────────────────────────────────
  x := public._agenda_os_situacao(pg_temp.os('OS-00112'), c_hoje);
  v_res := pg_temp.ok(v_res, 'D3a Nelson (OS-00112, aguardando peças sem check-in nem diária): começou sem rastro → o serviço inteiro, 4 dias',
    (x ->> 'pendente')::boolean and x ->> 'tipo' = 'comecada' and not (x ->> 'rastro')::boolean and x ->> 'proposta_dias' = '4'
    and x ->> 'status' = 'awaiting_parts' and x ->> 'curto' = 'já começou?'
    and x ->> 'texto' = 'falta você dizer se o serviço já começou (está como "aguardando peças", sem check-in nem diária ligada); sem resposta, conto o serviço inteiro (4 dias, estimativa minha)'
    and x ->> 'pergunta_id' is null, x::text);
  x := public._agenda_os_situacao(pg_temp.os('OS-97001'), c_hoje);
  v_res := pg_temp.ok(v_res, 'D3b a sintética do Paulo (OS-97001, check-in 26/10 e a diária do Roberto de 27/10): com rastro → 1 dia para terminar, desde o check-in',
    (x ->> 'pendente')::boolean and x ->> 'tipo' = 'comecada' and (x ->> 'rastro')::boolean and x ->> 'proposta_dias' = '1'
    and x ->> 'desde' = '2026-10-26'
    and x ->> 'texto' = 'falta você dizer quanto falta (começou em 26/10); sem resposta, marco 1 dia para terminar', x::text);
  x := public._agenda_os_situacao(pg_temp.os('OS-00076'), c_hoje);
  v_res := pg_temp.ok(v_res, 'D3c o "quanto falta" nunca passa da estimativa inteira: Rodrigo (OS-00076, check-in 08/08) é meio dia ao todo → meio dia',
    (x ->> 'pendente')::boolean and (x ->> 'rastro')::boolean and x ->> 'proposta_dias' = '0.5'
    and x ->> 'texto' = 'falta você dizer quanto falta (começou em 08/08); sem resposta, marco meio dia para terminar', x::text);
  x := public._agenda_os_situacao(pg_temp.os('OS-00069'), date '2026-11-05');
  v_res := pg_temp.ok(v_res, 'D3d Vanderlei (OS-00069, atualizado em 03/10): em 29/10 são 26 dias (não está parado); em 05/11, parado há mais de 30 dias → o serviço inteiro, 7,5 dias',
    not (public._agenda_os_situacao(pg_temp.os('OS-00069'), c_hoje) ->> 'pendente')::boolean
    and (x ->> 'pendente')::boolean and x ->> 'tipo' = 'parada' and x ->> 'desde' = '2026-10-03' and x ->> 'proposta_dias' = '7.5'
    and x ->> 'curto' = 'parado desde 03/10'
    and x ->> 'texto' = 'falta você dizer se ainda é para fazer o serviço inteiro (parado desde 03/10); sem resposta, conto o serviço inteiro (7,5 dias, estimativa minha)',
    x::text);
  -- a parada com compromisso vigente não pergunta (Wagner, OS-97006, publicado ter 03/11; sem os dias ditos para o teste)
  update public.os_planejamento set dias = null, estimativa_fonte = null where service_order_id = pg_temp.os('OS-97006');
  v_res := pg_temp.ok(v_res, 'D3e parada há mais de 30 dias: a Vera (OS-97005) pergunta; o Wagner (OS-97006), com compromisso vigente, não',
    (public._agenda_os_situacao(pg_temp.os('OS-97005'), date '2026-12-15') ->> 'tipo') = 'parada'
    and not (public._agenda_os_situacao(pg_temp.os('OS-97006'), date '2026-12-15') ->> 'pendente')::boolean, null);
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, modo)
  values ('situacao', 'situacao:' || pg_temp.os('OS-00112'), pg_temp.os('OS-00112'), array[pg_temp.os('OS-00112')],
          'TESTE AG7A: o Nelson já começou?', 'ligado')
  returning id into v_q;
  v_res := pg_temp.ok(v_res, 'D3f a pergunta situacao aberta da OS vem em pergunta_id',
    (public._agenda_os_situacao(pg_temp.os('OS-00112'), c_hoje) ->> 'pergunta_id')::uuid = v_q, null);
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
  values (pg_temp.os('OS-00112'), 3, 'dono', c_agora)
  on conflict (service_order_id) do update set dias = 3, estimativa_fonte = 'dono', estimativa_em = c_agora;
  v_res := pg_temp.ok(v_res, 'D3g respondida (os dias ditos) = não pendente; sem o portão (desligado, ou situacao fora da lista) = não pendente',
    public._agenda_os_situacao(pg_temp.os('OS-00112'), c_hoje) = '{"pendente": false}'::jsonb, null);
  update public.os_planejamento set dias = null, estimativa_fonte = null, estimativa_em = null
   where service_order_id = pg_temp.os('OS-00112');
  update public.agenda_config set marcar_regras = array_remove(marcar_regras, 'situacao') where id;
  x := public._agenda_os_situacao(pg_temp.os('OS-00112'), c_hoje);
  update public.agenda_config set marcar_regras = marcar_regras || '{situacao}'::text[], modo_marcar_sozinho = 'desligado' where id;
  v_res := pg_temp.ok(v_res, 'D3h sem o portão situacao (fora da lista, ou o modo desligado) a OS não fica pendente',
    x = '{"pendente": false}'::jsonb and public._agenda_os_situacao(pg_temp.os('OS-00112'), c_hoje) = '{"pendente": false}'::jsonb,
    x::text);
  update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;

  -- ── D4. A estimativa do gestor ─────────────────────────────────────────────────────────────────────────
  e := public._agenda_gestor_estimativa(pg_temp.os('OS-00074'), c_hoje);
  v_res := pg_temp.ok(v_res, 'D4a usa: Lenine, 6 dias com 1 pessoa (5,97 diárias), "6 dias, 1 pessoa (estimativa minha, pelo valor do orçamento)", com o aviso de dupla',
    (e ->> 'usa')::boolean and e -> 'motivo' = 'null'::jsonb and e ->> 'dias' = '6' and e ->> 'dp' = '5.97' and e ->> 'pessoas' = '1'
    and e ->> 'texto' = '6 dias, 1 pessoa (estimativa minha, pelo valor do orçamento)' and e #>> '{alerta_dupla,motivo}' = 'banco_cc'
    and e -> 'embutida' = '[]'::jsonb and e ?& array['usa', 'motivo', 'dias', 'dp', 'pessoas', 'texto', 'proposta_dias', 'alerta_dupla', 'embutida'],
    e::text);
  v_res := pg_temp.ok(v_res, 'D4b dito: os dias que o dono disse vencem a estimativa (a sintética da Úrsula, OS-97004)',
    public._agenda_gestor_estimativa(pg_temp.os('OS-97004'), c_hoje) = '{"usa": false, "motivo": "dito"}'::jsonb, null);
  e := public._agenda_gestor_estimativa(pg_temp.os('OS-00112'), c_hoje);
  v_res := pg_temp.ok(v_res, 'D4c situacao: Nelson, "já começou?", com a proposta da situação (4 dias)',
    not (e ->> 'usa')::boolean and e ->> 'motivo' = 'situacao' and e ->> 'proposta_dias' = '4' and e ->> 'texto' = 'já começou?'
    and e #>> '{situacao,tipo}' = 'comecada' and e ->> 'dias' = '4', e::text);
  v_res := pg_temp.ok(v_res, 'D4d a situação vem antes do tamanho: a Kalmar (OS-00032, 18,3 diárias, check-in em junho) é situacao, não grande',
    public._agenda_gestor_estimativa(pg_temp.os('OS-00032'), c_hoje) ->> 'motivo' = 'situacao', null);
  e := public._agenda_gestor_estimativa(pg_temp.os('ORÇ-00095'), c_hoje);
  v_res := pg_temp.ok(v_res, 'D4e sem_base: MP (ORÇ-00095, só kits), "não tem mão de obra separada", proposta 1 dia (sem_mo_dias)',
    not (e ->> 'usa')::boolean and e ->> 'motivo' = 'sem_base' and e ->> 'proposta_dias' = '1' and e -> 'dias' = 'null'::jsonb
    and e ->> 'texto' = 'não tem mão de obra separada', e::text);
  e := public._agenda_gestor_estimativa(pg_temp.os('OS-00130'), c_hoje);
  v_res := pg_temp.ok(v_res, 'D4f grande: Giancarlo (OS-00130), 9,87 diárias acima de 8 → "10 diárias pela estimativa", proposta 10 dias',
    not (e ->> 'usa')::boolean and e ->> 'motivo' = 'grande' and e ->> 'proposta_dias' = '10' and e ->> 'dp' = '9.87'
    and e ->> 'texto' = '10 diárias pela estimativa' and e #>> '{alerta_dupla,motivo}' = 'banco_cc', e::text);
  e := public._agenda_gestor_estimativa(pg_temp.os('OS-97005'), c_hoje);
  update public.agenda_config set marcar_regras = array_remove(marcar_regras, 'embutida_suposta') where id;
  x := public._agenda_gestor_estimativa(pg_temp.os('OS-97005'), c_hoje);
  update public.agenda_config set marcar_regras = marcar_regras || '{embutida_suposta}'::text[] where id;
  v_res := pg_temp.ok(v_res, 'D4g embutida: a Vera (OS-97005) pode ter peça junto → pergunta; sem a regra embutida_suposta, usa a estimativa (a prontidão é que segura)',
    not (e ->> 'usa')::boolean and e ->> 'motivo' = 'embutida' and e ->> 'texto' = 'pode ter peça junto'
    and jsonb_array_length(e -> 'embutida') > 0 and e ->> 'proposta_dias' = e ->> 'dias'
    and (x ->> 'usa')::boolean and jsonb_array_length(x -> 'embutida') > 0, e::text || ' | ' || x::text);
  e := public._agenda_gestor_estimativa(pg_temp.os('OS-00096'), c_hoje);
  v_res := pg_temp.ok(v_res, 'D4h o diagnóstico usa a estimativa com o texto dele (meio dia de diagnóstico; depois eu reavalio)',
    (e ->> 'usa')::boolean and e ->> 'dias' = '0.5' and e ->> 'texto' = 'meio dia de diagnóstico; depois eu reavalio', e::text);
  update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
  v_res := pg_temp.ok(v_res, 'D4i regra_desligada: com o modo desligado, nada se estima',
    public._agenda_gestor_estimativa(pg_temp.os('OS-00074'), c_hoje) = '{"usa": false, "motivo": "regra_desligada"}'::jsonb, null);
  update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;

  -- ── D5. agenda_meios_da_os ───────────────────────────────────────────────────────────────────────────────
  -- (a presença do Lenine em produção é abre e fecha; no replay a regra d05 dá "marina nova", porque as OS concluídas da marina
  -- dele não estão na fixture: o teste diz a presença, como o dono diria)
  update public.os_planejamento set dono_presenca = 'abre_e_fecha' where service_order_id = pg_temp.os('OS-00074');
  m := public.agenda_meios_da_os(pg_temp.os('OS-00074'), c_hoje);
  update public.os_planejamento set dono_presenca = null where service_order_id = pg_temp.os('OS-00074');
  v_res := pg_temp.ok(v_res, 'D5a com a regra: Lenine com a fonte orcamento — 6 dias, 12 meios-dias de 1 pessoa (você abre e fecha); estimativa_motivo nulo',
    m ->> 'fonte' = 'orcamento' and m ->> 'dias' = '6' and m ->> 'total' = '12' and m ->> 'pessoas_sugeridas' = '1'
    and m -> 'estimativa_motivo' = 'null'::jsonb and not (m ->> 'situacao_pendente')::boolean
    and jsonb_array_length(m -> 'molde') = 12 and m #> '{molde,0,dono}' = '["abertura"]'::jsonb
    and m #> '{molde,11,dono}' = '["fechamento"]'::jsonb
    and (select bool_and((t ->> 'desejado')::int = 1) from jsonb_array_elements(m -> 'molde') t), m::text);
  select string_agg(format('%s=%s:%s:%s:%s', n, mm ->> 'fonte', coalesce(mm ->> 'dias', '<NULL>'),
                           coalesce(mm ->> 'estimativa_motivo', '<NULL>'), mm ->> 'situacao_pendente'),
                    ' | ' order by n) into v_novo
    from unnest(array['OS-00069', 'OS-00130', 'OS-00112', 'OS-00104', 'ORÇ-00095', 'OS-00096']) n
   cross join lateral (select public.agenda_meios_da_os(pg_temp.os(n), c_hoje) mm) z;
  v_res := pg_temp.ok(v_res, 'D5b Vanderlei e o diagnóstico com orcamento; Giancarlo, Nelson, Flávio e MP continuam sugerida, com o porquê',
    v_novo = 'ORÇ-00095=sugerida:<NULL>:sem_base:false | OS-00069=orcamento:7.5:<NULL>:false | OS-00096=orcamento:0.5:<NULL>:false'
             || ' | OS-00104=sugerida:3.5:situacao:true | OS-00112=sugerida:4:situacao:true | OS-00130=sugerida:10:grande:false',
    v_novo);
  m := public.agenda_meios_da_os(pg_temp.os('OS-97004'), c_hoje);
  v_res := pg_temp.ok(v_res, 'D5c os dias do dono: fonte dono e a saída de antes, sem as chaves novas',
    m ->> 'fonte' = 'dono' and m ->> 'dias' = '2' and not m ? 'estimativa_motivo' and not m ? 'situacao_pendente'
    and m = pg_temp.meios_de_antes(pg_temp.os('OS-97004'), c_hoje), m::text);
  -- as chaves: as de antes + as 2 novas
  update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
  m := public.agenda_meios_da_os(pg_temp.os('OS-00074'), c_hoje);
  update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
  v_res := pg_temp.ok(v_res, 'D5d com a regra a saída tem as chaves de antes mais estimativa_motivo e situacao_pendente (a cópia da saída não perdeu nenhuma)',
    (select array_agg(k order by k) from jsonb_object_keys(public.agenda_meios_da_os(pg_temp.os('OS-00074'), c_hoje)) k)
    = (select array_agg(k order by k) from (select jsonb_object_keys(m) k union all select 'estimativa_motivo' union all select 'situacao_pendente') z),
    null);
  -- o 'orcamento' gravado (o prazo vencido do P4) com o portão falso é lido como 'sugerida'
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
  values (pg_temp.os('OS-00112'), 4, 'orcamento', c_agora)
  on conflict (service_order_id) do update set dias = 4, estimativa_fonte = 'orcamento', estimativa_em = c_agora;
  m := public.agenda_meios_da_os(pg_temp.os('OS-00112'), c_hoje);
  update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
  x := public.agenda_meios_da_os(pg_temp.os('OS-00112'), c_hoje);
  update public.agenda_config set modo_marcar_sozinho = 'ligado', marcar_regras = array_remove(marcar_regras, 'estimativa') where id;
  e := public.agenda_meios_da_os(pg_temp.os('OS-00112'), c_hoje);
  update public.agenda_config set marcar_regras = marcar_regras || '{estimativa}'::text[] where id;
  update public.os_planejamento set dias = null, estimativa_fonte = null, estimativa_em = null
   where service_order_id = pg_temp.os('OS-00112');
  v_res := pg_temp.ok(v_res, 'D5e os 4 dias de fonte orcamento GRAVADOS: com a regra, orcamento; com o portão falso (desligado, ou sem a regra estimativa), sugerida com os mesmos 4 dias',
    m ->> 'fonte' = 'orcamento' and m ->> 'dias' = '4' and not m ? 'estimativa_motivo'
    and x ->> 'fonte' = 'sugerida' and x ->> 'dias' = '4' and e ->> 'fonte' = 'sugerida' and e ->> 'dias' = '4',
    (m ->> 'fonte') || ' / ' || (x ->> 'fonte') || ' / ' || (e ->> 'fonte'));
  -- (f) o portão falso: a de antes, byte a byte (todas as OS; a cópia de 20261025100200 como pg_temp)
  v_dif := null;
  for r in select * from (values (1, 'desligado', 'desligado', false, true), (2, 'sombra sem a simulação', 'sombra', false, true),
                                 (3, '*gestor, só propor*', 'ligado', true, true), (4, 'sem a regra estimativa', 'ligado', false, false)) t(o, nome, modo, so_propor, com_est)
           order by o loop
    update public.agenda_config
       set modo_marcar_sozinho = r.modo, gestor_so_propor = r.so_propor,
           marcar_regras = case when r.com_est then marcar_regras || case when 'estimativa' = any (marcar_regras) then '{}'::text[] else '{estimativa}' end
                                else array_remove(marcar_regras, 'estimativa') end
     where id;
    select md5(string_agg(public.agenda_meios_da_os(so.id, c_hoje)::text, '|' order by so.id)),
           md5(string_agg(pg_temp.meios_de_antes(so.id, c_hoje)::text, '|' order by so.id))
      into v_m0, v_m1 from public.service_orders so;
    if v_m0 <> v_m1 then v_dif := concat_ws('; ', v_dif, r.nome); end if;
  end loop;
  update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = false,
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id;
  v_res := pg_temp.ok(v_res, 'D5f com o portão falso (desligado, sombra sem a simulação, *gestor, só propor*, sem a regra estimativa) os meios-dias das 28 OS são os de antes, byte a byte',
    v_dif is null, coalesce(v_dif, '—'));

  -- ── D6. A peça embutida: a mesma conta da prontidão ───────────────────────────────────────────────────────
  update public.os_planejamento set material_conferido_em = c_agora where service_order_id = pg_temp.os('OS-00104');
  if not found then
    insert into public.os_planejamento (service_order_id, material_conferido_em) values (pg_temp.os('OS-00104'), c_agora);
  end if;
  select count(*), string_agg(so.service_order_number, ', ') filter (where public._agenda_peca_embutida(so.id)
                                                                            is distinct from public.os_prontidao(so.id, c_hoje) #> '{material,embutidas}')
    into v_n, v_dif from public.service_orders so;
  update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
  select string_agg(so.service_order_number, ', ') filter (where public._agenda_peca_embutida(so.id)
                                                                  is distinct from public.os_prontidao(so.id, c_hoje) #> '{material,embutidas}')
    into v_novo from public.service_orders so;
  update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
  v_res := pg_temp.ok(v_res, 'D6 _agenda_peca_embutida é a v_embut da os_prontidao nas 28 OS, com e sem o portão (e o "não tem peça a comprar" do Flávio a esvazia nas duas)',
    v_dif is null and v_novo is null and v_n = 28
    and public._agenda_peca_embutida(pg_temp.os('OS-00104')) = '[]'::jsonb
    and jsonb_array_length(public._agenda_peca_embutida(pg_temp.os('OS-97005'))) > 0
    and jsonb_array_length(public._agenda_peca_embutida(pg_temp.os('OS-00130'))) > 0,
    format('%s OS; diferentes ligado: %s; desligado: %s', v_n, coalesce(v_dif, '—'), coalesce(v_novo, '—')));

  -- ── D7. A palavra da dupla ───────────────────────────────────────────────────────────────────────────────
  select count(*) into v_acoes from public.agenda_acoes where tipo = 'dupla';
  x := public.agenda_dupla_dita(v_adm, 'Lenine', true, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'D7a *Lenine com dupla*: o texto, a marca todos (meios nulo, o motivo, a hora) e a duração passa a 2 pessoas',
    (x ->> 'ok')::boolean and (x ->> 'mudou')::boolean and x ->> 'dupla_dita' = 'todos'
    and x ->> 'texto' = 'Lenine com dupla: nas próximas vezes que eu marcar, vão 2 pessoas em cada meio-dia. *desfaz Lenine* volta.'
    and exists (select 1 from public.os_planejamento pl where pl.service_order_id = pg_temp.os('OS-00074')
                  and pl.dupla_dita = 'todos' and pl.dupla_meios is null and pl.dupla_motivo = 'você disse: Lenine com dupla'
                  and pl.dupla_em = c_agora and pl.dias is null and pl.atualizado_por = v_adm)
    and public.os_duracao_sugerida(pg_temp.os('OS-00074')) ->> 'pessoas' = '2'
    and public.os_duracao_sugerida(pg_temp.os('OS-00074')) ->> 'pessoas_motivo' = 'dupla_marcada'
    and public.os_duracao_sugerida(pg_temp.os('OS-00074')) ->> 'dias_realista' = '3', x::text);
  v_res := pg_temp.ok(v_res, 'D7b a ação dupla (origem dono, executada, desfazível por desfazer_validade, com antes e depois) e o histórico da OS',
    exists (select 1 from public.agenda_acoes a
             where a.id = (x ->> 'acao_id')::uuid and a.tipo = 'dupla' and a.origem = 'dono' and a.executada
               and a.service_order_id = pg_temp.os('OS-00074') and a.os_ids = array[pg_temp.os('OS-00074')]
               and a.desfazivel_ate = c_agora + interval '24 hours' and a.autor = v_adm and a.criada_em = c_agora
               and a.antes ->> 'dupla_dita' is null and a.depois ->> 'dupla_dita' = 'todos' and a.texto = x ->> 'texto')
    and (select pl.historico -> -1 ->> 'por' = 'dono' and pl.historico -> -1 #>> '{depois,dupla_dita}' = 'todos'
                and pl.historico -> -1 -> 'antes' ? 'dupla_dita' and pl.historico -> -1 ->> 'trecho' = 'Lenine com dupla'
           from public.os_planejamento pl where pl.service_order_id = pg_temp.os('OS-00074')), null);
  x := public.agenda_dupla_dita(v_adm, 'lenine', true, c_hoje, c_agora + interval '1 minute');
  v_res := pg_temp.ok(v_res, 'D7c dizer de novo: "Lenine já estava com dupla.", sem gravar nada',
    (x ->> 'ok')::boolean and not (x ->> 'mudou')::boolean and x ->> 'texto' = 'Lenine já estava com dupla.'
    and (select count(*) from public.agenda_acoes where tipo = 'dupla') = v_acoes + 1, x::text);
  x := public.agenda_dupla_dita(v_adm, 'OS-00074', false, c_hoje, c_agora + interval '2 minutes');
  v_res := pg_temp.ok(v_res, 'D7d *Lenine sem dupla* (pelo número): nao, "volto a 1 pessoa", outra ação; a duração volta a 1 pessoa, sem aviso',
    (x ->> 'mudou')::boolean and x ->> 'dupla_dita' = 'nao' and x ->> 'texto' = 'Lenine sem dupla: volto a 1 pessoa.'
    and (select count(*) from public.agenda_acoes where tipo = 'dupla') = v_acoes + 2
    and public.os_duracao_sugerida(pg_temp.os('OS-00074')) ->> 'pessoas' = '1'
    and not public.os_duracao_sugerida(pg_temp.os('OS-00074')) ? 'alerta_dupla'
    and (select a.antes ->> 'dupla_dita' = 'todos' from public.agenda_acoes a where a.id = (x ->> 'acao_id')::uuid), x::text);
  e := public.agenda_acao_desfazivel('Lenine', c_hoje, c_agora + interval '3 minutes');
  v_res := pg_temp.ok(v_res, 'D7e o *desfaz Lenine* acha a última ação dupla (o ramo que a volta é do P7)',
    e ->> 'status' = 'ok' and (e ->> 'acao_id')::uuid = (x ->> 'acao_id')::uuid and e ->> 'texto' = 'Lenine sem dupla: volto a 1 pessoa.',
    e::text);
  x := public.agenda_dupla_dita(v_adm, 'Fulano de Tal', true, c_hoje, c_agora);
  e := public.agenda_dupla_dita(v_adm, 'ORÇ-00117', true, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'D7f não achado e fora da carteira (ORÇ-00117, rascunho): ok false, o texto do resolvedor, nada gravado',
    not (x ->> 'ok')::boolean and x ->> 'status' = 'nao_achei' and x ->> 'texto' like 'Não encontrei "Fulano%'
    and not (e ->> 'ok')::boolean and e ->> 'status' = 'fora_da_carteira'
    and not exists (select 1 from public.os_planejamento pl where pl.service_order_id = pg_temp.os('ORÇ-00117'))
    and (select count(*) from public.agenda_acoes where tipo = 'dupla') = v_acoes + 2, x::text || ' | ' || e::text);
  v_res := pg_temp.ok(v_res, 'D7g só o administrador: o técnico recebe 42501',
    pg_temp.recusa(format('select public.agenda_dupla_dita(%L, %L, true, %L, %L)', v_tec, 'Lenine', c_hoje, c_agora))
      = 'erro 42501: Só o administrador mexe na agenda.',
    pg_temp.recusa(format('select public.agenda_dupla_dita(%L, %L, true, %L, %L)', v_tec, 'Lenine', c_hoje, c_agora)));
  v_n := (select count(*) from public.os_planejamento pl where pl.service_order_id = pg_temp.os('ORÇ-00083'));
  x := public.agenda_dupla_dita(v_adm, 'ORÇ-00083', true, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'D7h a OS sem planejamento ganha a linha (dias nulo) com a marca (Robson, ORÇ-00083)',
    v_n = 0 and (x ->> 'mudou')::boolean
    and exists (select 1 from public.os_planejamento pl where pl.service_order_id = pg_temp.os('ORÇ-00083')
                  and pl.dupla_dita = 'todos' and pl.dias is null and pl.estimativa_fonte is null), x::text);

  -- ── D8. As cópias ─────────────────────────────────────────────────────────────────────────────────────────
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public.os_duracao_sugerida(uuid)'::regprocedure;
  v_fonte := pg_temp.corpo(v_os6, 'os_duracao_sugerida');
  select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: fim', 'g');
  v_res := pg_temp.ok(v_res, 'D8a os_duracao_sugerida: sem os 5 blocos "-- FASE 7:", é o corpo de 20261029100200 (a mais nova antes da 7a)',
    v_n = 5 and v_fonte <> '' and pg_temp.sem_fase7(v_novo) = v_fonte,
    format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(v_fonte), length(pg_temp.sem_fase7(v_novo))));
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public.agenda_meios_da_os(uuid, date)'::regprocedure;
  v_fonte := pg_temp.corpo(v_mot2, 'agenda_meios_da_os');
  select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: fim', 'g');
  v_res := pg_temp.ok(v_res, 'D8b agenda_meios_da_os: sem os 3 blocos "-- FASE 7:", é o corpo de 20261025100200 (a única antes da 7a)',
    v_n = 3 and v_fonte <> '' and pg_temp.sem_fase7(v_novo) = v_fonte,
    format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(v_fonte), length(pg_temp.sem_fase7(v_novo))));

  perform pg_temp.gravar(v_res);
end
$fx$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
