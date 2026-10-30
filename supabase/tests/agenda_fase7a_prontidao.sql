-- Prova da prontidão do gestor da agenda, Fase 7a (pacote P3): o material, a duração e a classe pelas regras do gestor
-- (migration 20261031100200), sobre a carteira REAL de 29/10 (o replay) e a sintética da 7a.
-- bancada: depende de 20261031100200
--
--   P0 as portas e o que é (sem fixture): as 4 recriadas com as portas de antes (a prontidão e a classe para authenticated e
--      service_role; o motor só service_role; a marca da memória para ninguém), nenhuma função nova, nenhuma definer nova
--   P1 crítico pelo valor (AG7-05): os 4 miúdos da carteira (porta-fusível, voltímetro, conector, Sikaflex) separam na véspera;
--      "Cabos Elétricos Diversos" (venda R$ 350, custo R$ 0) continua crítico; o fato do dono vence; o valor zerado = crítico
--   P2 prazo padrão (AG7-06): E vira D com 7 dias úteis ("sem fornecedor: contei 7 dias úteis"); o compressor do Flávio (pedido em
--      13/10, fornecedor sem cidade) vence em 22/10 e pergunta "chegou?"; só com a regra, a OS fica na reserva (compra)
--   P3 o "compre até" com o tempo interno (AG7-07) e o gravado (não desliza enquanto não vence; vencido = comprando hoje; só na OS
--      com compromisso; com o teto de empurrões, volta ao que era)
--   P4 sem peça suposta (Lenine) e a peça embutida suposta (não trava; com zero linhas, também conta como sem peça)
--   P5 a duração 'orcamento' (texto, sem a restrição "quantos dias?"), o texto do gestor quando ele pergunta antes, a restrição
--      situacao, a Kalmar (esperando o cliente) sem nada disso, os dias 'orcamento' gravados "(estimativa minha)"
--   P6 _agenda_classe_da_os: a carteira de 29/10 com tudo ligado (Lenine e Vanderlei classe 2; Giancarlo estimativa; Nelson
--      situacao; Flávio material; Kalmar e Rodrigo-76 cliente; Robson orçamento; MP estimativa — sem mão de obra; o sinal não
--      segura desde o 7a P12), a OS em andamento sem plano espera o
--      "quanto falta?", e compra_firme
--   P7 agenda_propor: o sufixo "(estimativa minha: 6 dias)." no compromisso; as recomendações das críticas do P8
--   P8 com o portão falso (desligado, sombra sem a simulação, *gestor, só propor*, sem as regras do P3), a prontidão, a classe e a
--      proposta das OS são as de antes, byte a byte (as definições de antes rodadas como pg_temp)
--   P9 as cópias: os_prontidao e _agenda_rodada_marca (de 20261030100400), _agenda_classe_da_os (de 20261025100200) e
--      agenda_propor (de 20261030100200) sem os blocos "-- FASE 7:"
--   P10 a memória da vigia: com a regra situacao a marca conta a pergunta e a ação (e nunca coincide com a de sempre); a
--      prontidão lembrada numa rodada recalcula depois de uma ação gravada nela
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_prontidao.sql
--   Seguro em produção: P0 e P9 (as cópias saem PULADO sem as migrations como texto) só leem; P1 a P8 e P10 usam as fixtures e só
--   rodam na bancada (fora dela saem PULADO). Termina em ROLLBACK.
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

-- Os itens da prontidão, um por linha: "curto nivel sit crítico data compre_ate".
create function pg_temp.itens(p_os uuid, p_hoje date) returns text language sql stable as $f$
  select string_agg(format('%s %s %s %s %s %s', e ->> 'curto', e ->> 'nivel', e ->> 'situacao', e ->> 'critico',
                           coalesce(e ->> 'data', '-'), coalesce(e ->> 'compre_ate', '-')), ' | ' order by o)
    from jsonb_array_elements(public.os_prontidao(p_os, p_hoje) #> '{material,itens}') with ordinality t(e, o)
$f$;
-- As restrições, "tipo:bloqueia".
create function pg_temp.restr(p_os uuid, p_hoje date) returns text language sql stable as $f$
  select string_agg((e ->> 'tipo') || ':' || (e ->> 'bloqueia'), ' ' order by o)
    from jsonb_array_elements(public.os_prontidao(p_os, p_hoje) -> 'restricoes') with ordinality t(e, o)
$f$;
create function pg_temp.texto(p_os uuid, p_hoje date, p_tipo text) returns text language sql stable as $f$
  select e ->> 'texto' from jsonb_array_elements(public.os_prontidao(p_os, p_hoje) -> 'restricoes') e where e ->> 'tipo' = p_tipo limit 1
$f$;
create function pg_temp.classe(p_os uuid, p_hoje date) returns jsonb language sql stable as $f$
  select public._agenda_classe_agora(p_os, p_hoje) - 'pront'
$f$;

-- ── P0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura, quem) as (values
  ('public.os_prontidao(uuid, date)', 'leitura'),
  ('public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)', 'leitura'),
  ('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'servico'),
  ('public._agenda_rodada_marca()', 'ninguem'))
insert into _resultado
select 'P0a as 4 recriadas com as portas de antes: a prontidão e a classe para authenticated e service_role; o motor só service_role; a marca da memória da vigia para ninguém; nunca anon',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and has_function_privilege('authenticated', f.assinatura, 'execute') = (f.quem = 'leitura')
                and has_function_privilege('service_role', f.assinatura, 'execute') = (f.quem <> 'ninguem')),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute') <> (f.quem = 'leitura')
                                              or has_function_privilege('service_role', f.assinatura, 'execute') <> (f.quem <> 'ninguem'))
  from f;
insert into _resultado
select 'P0b as 4 continuam como eram: a prontidão e a classe STABLE e invoker, a marca VOLATILE e invoker, o motor como o de antes; search_path fixo',
       bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(case p.proname when 'os_prontidao' then p.provolatile = 's' and not p.prosecdef
                                   when '_agenda_classe_da_os' then p.provolatile = 's' and not p.prosecdef
                                   when '_agenda_rodada_marca' then p.provolatile = 'v' and not p.prosecdef
                                   else true end) and count(*) = 4,
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from pg_proc p
 where p.oid in ('public.os_prontidao(uuid, date)'::regprocedure,
                 'public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)'::regprocedure,
                 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)'::regprocedure,
                 'public._agenda_rodada_marca()'::regprocedure);

-- ── P1 a P8 e P10: com as fixtures (o replay de 29/10 e a sintética, por cima) ──────────────────────────────
do $fx$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-29';
  c_agora constant timestamptz := timestamptz '2026-10-29 16:52-03';
  c_todas constant text[] := '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}';
  v_pr    text := coalesce(current_setting('agenda_teste.mig_correcao_desempenho', true), '');
  v_mot2  text := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  v_mot3  text := coalesce(current_setting('agenda_teste.mig_correcao_motor', true), '');
  v_carteira text[] := array['OS-00074', 'OS-00069', 'OS-00130', 'OS-00112', 'OS-00104', 'OS-00096', 'OS-00076', 'OS-00032',
                             'OS-00033', 'ORÇ-00083', 'ORÇ-00095'];
  v_ids   uuid[];
  v_adm   uuid;
  v_dif   text;
  v_novo  text;
  v_t     text;
  v_n     int;
  v_m0    text;
  v_m1    text;
  v_k0    bigint;
  v_k1    bigint;
  v_k2    bigint;
  v_lin   uuid;
  p       jsonb;
  e       jsonb;
  x       jsonb;
  r       record;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' or v_pr = '' or v_mot2 = '' or v_mot3 = '' then
    insert into _resultado values ('P1 a P8 e P10 (as fixtures da 7a)', true,
      'PULADO: sem agenda_teste.replay2910, fase7a, mig_correcao_desempenho, mig_motor_fase2 e mig_correcao_motor (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.replay2910');
  execute current_setting('agenda_teste.fase7a');
  -- as definições de antes, como pg_temp, a partir do texto das migrations de onde a 7a copiou
  execute replace(pg_temp.inteira(v_pr, 'os_prontidao'), 'create or replace function public.os_prontidao(',
                  'create function pg_temp.pront_antes(');
  execute replace(pg_temp.inteira(v_mot2, '_agenda_classe_da_os'), 'create or replace function public._agenda_classe_da_os(',
                  'create function pg_temp.classe_antes(');
  execute replace(pg_temp.inteira(v_mot3, 'agenda_propor'), 'create or replace function public.agenda_propor(',
                  'create function pg_temp.propor_antes(');
  select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
  v_ids := array(select pg_temp.os(n) from unnest(v_carteira) n);
  -- a presença do dono do Lenine e do Vanderlei como em produção (abre e fecha; o replay dá "sempre": notas do P2)
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select pg_temp.os(n), 'abre_e_fecha' from unnest(array['OS-00074', 'OS-00069']) n
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';

  -- ── P1. Crítico pelo valor ─────────────────────────────────────────────────────────────────────────────
  update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = false, marcar_regras = '{critico_por_valor}' where id;
  select string_agg(format('%s %s (%s)', so.service_order_number, it ->> 'curto', public._agenda_num((it ->> 'valor_unit')::numeric, 2)),
                    ' | ' order by so.service_order_number, it ->> 'curto') filter (where (it ->> 'separar_vespera')::boolean),
         count(*), count(*) filter (where (it ->> 'critico')::boolean),
         count(*) filter (where not (it ->> 'critico')::boolean and not (it ->> 'separar_vespera')::boolean)
    into v_novo, v_n, v_k0, v_k1
    from unnest(v_ids) i join public.service_orders so on so.id = i
   cross join lateral jsonb_array_elements(public.os_prontidao(i, c_hoje) #> '{material,itens}') it;
  v_res := pg_temp.ok(v_res, 'P1a a carteira de 29/10: das 19 linhas, 4 miúdos (porta-fusível do Vanderlei, voltímetro do Giancarlo, conector do Rodrigo, Sikaflex do Robson) separam na véspera; as outras 15 continuam críticas',
    v_n = 19 and v_k0 = 15 and v_k1 = 0
    and v_novo = 'ORÇ-00083 Sikaflex 221… (163,46) | OS-00069 Porta Fusível MIDI… (45,05) | OS-00076 Conector de cabo… (240) | OS-00130 Voltímetro 12V (98,8)',
    format('%s linhas, %s críticas; miúdos: %s', v_n, v_k0, coalesce(v_novo, '—')));
  e := (select y from jsonb_array_elements(public.os_prontidao(pg_temp.os('OS-00069'), c_hoje) #> '{material,itens}') y
         where y ->> 'curto' like 'Cabos Elétricos Diversos%');
  v_res := pg_temp.ok(v_res, 'P1b "Cabos Elétricos Diversos" (venda R$ 350, custo R$ 0) continua crítico: o limiar é pelo valor de VENDA',
    (e ->> 'critico')::boolean and not (e ->> 'separar_vespera')::boolean and (e ->> 'valor_unit')::numeric = 350, e::text);
  -- o fato do dono vence: o porta-fusível dito crítico pelo dono fica crítico (R$ 45); os cabos ditos não críticos, não críticos
  -- (numa subtransação desfeita: o resto do teste vê o material de produção)
  select y into e from jsonb_array_elements(public.os_prontidao(pg_temp.os('OS-00069'), c_hoje) #> '{material,itens}') y
   where y ->> 'curto' like 'Porta Fusível%';
  v_lin := (e ->> 'id')::uuid;
  begin
    update public.os_material set fonte = 'dono', critico = true where id = v_lin;
    update public.os_material set fonte = 'dono', critico = false
     where id = (select (y ->> 'id')::uuid from jsonb_array_elements(public.os_prontidao(pg_temp.os('OS-00069'), c_hoje) #> '{material,itens}') y
                  where y ->> 'curto' like 'Cabos Elétricos Diversos%');
    p := public.os_prontidao(pg_temp.os('OS-00069'), c_hoje);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  e := (select y from jsonb_array_elements(p #> '{material,itens}') y where y ->> 'curto' like 'Porta Fusível%');
  x := (select y from jsonb_array_elements(p #> '{material,itens}') y where y ->> 'curto' like 'Cabos Elétricos Diversos%');
  v_res := pg_temp.ok(v_res, 'P1c o fato do dono vence o valor: o porta-fusível (R$ 45) dito crítico fica crítico; os cabos (R$ 350) ditos não críticos ficam não críticos (nenhum separa "pela regra")',
    (e ->> 'critico')::boolean and not (e ->> 'separar_vespera')::boolean
    and not (x ->> 'critico')::boolean and not (x ->> 'separar_vespera')::boolean, e::text || ' | ' || x::text);
  -- o valor zerado (ninguém preencheu) conta como sem valor: crítico (o porta-fusível com o preço zerado, desfeito na hora)
  select y into e from jsonb_array_elements(public.os_prontidao(pg_temp.os('OS-00069'), c_hoje) #> '{material,itens}') y
   where y ->> 'curto' like 'Porta Fusível%';
  begin
    if e ->> 'origem' = 'peca' then
      update public.service_order_parts set unit_sale_snapshot = 0 where id = (e ->> 'linha')::uuid;
    else
      update public.service_order_services set unit_price_snapshot = 0 where id = (e ->> 'linha')::uuid;
    end if;
    p := public.os_prontidao(pg_temp.os('OS-00069'), c_hoje);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  x := (select y from jsonb_array_elements(p #> '{material,itens}') y where y ->> 'curto' like 'Porta Fusível%');
  v_res := pg_temp.ok(v_res, 'P1d sem valor (o preço zerado, que ninguém preencheu) = crítico, sem separar',
    (x ->> 'critico')::boolean and not (x ->> 'separar_vespera')::boolean and x -> 'valor_unit' = 'null'::jsonb
    and e ->> 'origem' in ('peca', 'texto_livre'), (e ->> 'origem') || ' | ' || x::text);
  update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
  select count(*) filter (where it ? 'separar_vespera' or it ? 'valor_unit' or not (it ->> 'critico')::boolean) into v_n
    from unnest(v_ids) i cross join lateral jsonb_array_elements(public.os_prontidao(i, c_hoje) #> '{material,itens}') it;
  v_res := pg_temp.ok(v_res, 'P1e sem o portão, tudo crítico como antes e o item sem as chaves novas', v_n = 0, v_n::text);

  -- ── P2. Prazo padrão ───────────────────────────────────────────────────────────────────────────────────
  update public.agenda_config set modo_marcar_sozinho = 'ligado', marcar_regras = '{prazo_padrao}' where id;
  v_t := pg_temp.itens(pg_temp.os('OS-00069'), c_hoje);
  e := public.os_prontidao(pg_temp.os('OS-00069'), c_hoje) #> '{material,itens,0}';
  v_res := pg_temp.ok(v_res, 'P2a Vanderlei: os 4 sem fornecedor viram D com 7 dias úteis — "se comprar hoje, chega por volta de ter 10/11", compre até 21/10; "sem fornecedor: contei 7 dias úteis"',
    v_t = 'Kit Cabos/ Conectores/… D falta true 2026-11-10 2026-10-21 | Porta Fusível MIDI… D falta true 2026-11-10 2026-10-21'
          || ' | Cabos Elétricos Diversos… D falta true 2026-11-10 2026-10-21 | Kit cabos eletricos… D falta true 2026-11-10 2026-10-21'
    and e ->> 'classe' = 'padrao' and e ->> 'prazo_du' = '7' and e ->> 'prazo_texto' = 'sem fornecedor: contei 7 dias úteis'
    and e ->> 'data_texto' = 'se comprar hoje, chega por volta de ter 10/11' and not (e ->> 'sem_data')::boolean
    and not e ? 'compra_firme',
    v_t || ' | ' || e::text);
  p := public.os_prontidao(pg_temp.os('OS-00069'), c_hoje);
  v_res := pg_temp.ok(v_res, 'P2b Vanderlei sai do "de quem e quando?" (sem previsão, que trava de vez) para o "compre até", com o material previsto: pronto a partir de qua 11/11, se comprar hoje',
    pg_temp.restr(pg_temp.os('OS-00069'), c_hoje) = 'compre_ate:true duracao:false'
    and p #>> '{material,estado}' = 'previsto' and p ->> 'est' = '2026-11-11'
    and pg_temp.texto(pg_temp.os('OS-00069'), c_hoje, 'compre_ate') = '4 itens a comprar: comprando hoje, "Kit Cabos/ Conectores/…" chega por volta de ter 10/11',
    pg_temp.restr(pg_temp.os('OS-00069'), c_hoje) || ' | ' || (p ->> 'estado_texto'));
  e := public.os_prontidao(pg_temp.os('OS-00104'), c_hoje) #> '{material,itens,0}';
  v_res := pg_temp.ok(v_res, 'P2c o compressor do Flávio (pedido em 13/10, fornecedor sem cidade): chega pelo prazo padrão, 22/10, e venceu: "chegou?", como antes',
    e ->> 'nivel' = 'D' and e ->> 'data' = '2026-10-22' and (e ->> 'atrasado')::boolean and e ->> 'classe' = 'padrao'
    and e ->> 'data_texto' = 'pedido em 13/10, deve chegar por volta de qui 22/10'
    and e ->> 'prazo_texto' = 'sem o prazo de Mateus: contei 7 dias úteis'
    and pg_temp.texto(pg_temp.os('OS-00104'), c_hoje, 'atrasado') = 'a previsão de "Compressor 12V de…" venceu em 22/10: chegou?'
    and pg_temp.classe(pg_temp.os('OS-00104'), c_hoje) ->> 'motivo' = 'material', e::text);
  x := pg_temp.classe(pg_temp.os('OS-00069'), c_hoje);
  v_res := pg_temp.ok(v_res, 'P2d só com o prazo padrão (sem compra_firme nem a estimativa) o Vanderlei sai do "nunca" (material) e vai à reserva (compra)',
    x ->> 'classe' = '3' and x ->> 'condicao_tipo' = 'compra' and pg_temp.classe_antes(pg_temp.pront_antes(pg_temp.os('OS-00069'), c_hoje),
      public.agenda_meios_da_os(pg_temp.os('OS-00069'), c_hoje), c_hoje, false, false) ->> 'motivo' = 'material', x::text);

  -- ── P3. O "compre até": o tempo interno e o gravado ─────────────────────────────────────────────────────────
  update public.agenda_config set marcar_regras = '{prazo_padrao,compra_firme}' where id;
  v_t := pg_temp.itens(pg_temp.os('OS-00069'), c_hoje);
  e := public.os_prontidao(pg_temp.os('OS-00069'), c_hoje) #> '{material,itens,0}';
  v_res := pg_temp.ok(v_res, 'P3a com o tempo interno (1 dia útil): Vanderlei chega qua 11/11 ("se comprar até sex 30/10"), compre até 20/10; compra_firme',
    v_t = 'Kit Cabos/ Conectores/… D falta true 2026-11-11 2026-10-20 | Porta Fusível MIDI… D falta true 2026-11-11 2026-10-20'
          || ' | Cabos Elétricos Diversos… D falta true 2026-11-11 2026-10-20 | Kit cabos eletricos… D falta true 2026-11-11 2026-10-20'
    and e ->> 'data_texto' = 'se comprar até sex 30/10, chega por volta de qua 11/11' and (e ->> 'compra_firme')::boolean
    and public.os_prontidao(pg_temp.os('OS-00069'), c_hoje) ->> 'est' = '2026-11-12', v_t || ' | ' || e::text);
  e := (select y from jsonb_array_elements(public.os_prontidao(pg_temp.os('OS-00112'), c_hoje) #> '{material,itens}') y
         where y ->> 'curto' like 'Central de controle%');
  v_res := pg_temp.ok(v_res, 'P3b o Cerbo do Nelson (Kamell, 4 dias úteis): chega sex 06/11 (era qui 05/11), compre até 23/10 (era 26/10); o prazo do fornecedor fica',
    e ->> 'data' = '2026-11-06' and e ->> 'compre_ate' = '2026-10-23' and e ->> 'classe' = 'outro_estado' and e ->> 'prazo_du' = '4'
    and e ->> 'prazo_texto' = 'outro estado, 4 dias úteis (pela cidade, chute meu)'
    and e ->> 'data_texto' = 'se comprar até sex 30/10, chega por volta de sex 06/11', e::text);
  -- o gravado (P10): numa OS com compromisso (Wagner, OS-97006: publicado ter 03/11), uma peça do dono sem fornecedor
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, critico, situacao, fonte,
                                  compre_ate, compre_ate_base, compre_ate_em)
  values (pg_temp.os('OS-97006'), 'dono', 'Disjuntor DC 125 A', 1, true, 'falta', 'dono',
          date '2026-10-30', '{"primeiro": "2026-11-12", "prazo_fonte": "padrao"}', c_agora)
  returning id into v_lin;
  e := (select y from jsonb_array_elements(public.os_prontidao(pg_temp.os('OS-97006'), c_hoje) #> '{material,itens}') y where (y ->> 'id')::uuid = v_lin);
  x := pg_temp.classe(pg_temp.os('OS-97006'), c_hoje);
  v_res := pg_temp.ok(v_res, 'P3c o "compre até" gravado (sex 30/10) numa OS com compromisso: vale o gravado e a data não anda — gravado + 1 + 7 = qui 12/11, "se comprar até sex 30/10"; a OS fica no compromisso',
    e ->> 'compre_ate' = '2026-10-30' and e ->> 'data' = '2026-11-12' and (e ->> 'compra_firme')::boolean
    and e ->> 'data_texto' = 'se comprar até sex 30/10, chega por volta de qui 12/11' and not (x ? 'condicao_tipo'), e::text || ' | ' || x::text);
  update public.os_material set compre_ate = date '2026-10-28' where id = v_lin;
  e := (select y from jsonb_array_elements(public.os_prontidao(pg_temp.os('OS-97006'), c_hoje) #> '{material,itens}') y where (y ->> 'id')::uuid = v_lin);
  v_res := pg_temp.ok(v_res, 'P3d o gravado vencido (qua 28/10): comprando hoje — hoje + 7 = ter 10/11, "se comprar hoje"; continua firme',
    e ->> 'compre_ate' = '2026-10-28' and e ->> 'data' = '2026-11-10' and (e ->> 'compra_firme')::boolean
    and e ->> 'data_texto' = 'se comprar hoje, chega por volta de ter 10/11', e::text);
  update public.os_material set empurrada_vezes = 2 where id = v_lin;
  e := (select y from jsonb_array_elements(public.os_prontidao(pg_temp.os('OS-97006'), c_hoje) #> '{material,itens}') y where (y ->> 'id')::uuid = v_lin);
  x := pg_temp.classe(pg_temp.os('OS-97006'), c_hoje);
  v_res := pg_temp.ok(v_res, 'P3e com 2 empurrões (compre_ate_empurroes_max) o item volta ao que era: sem o gravado, sem o tempo interno, sem compra_firme — a OS volta à reserva (compra)',
    e ->> 'compre_ate' = '2026-10-21' and e ->> 'data' = '2026-11-10' and not e ? 'compra_firme'
    and x ->> 'classe' = '3' and x ->> 'condicao_tipo' = 'compra', e::text || ' | ' || x::text);
  update public.os_material set empurrada_vezes = 0, compre_ate = date '2026-10-30' where id = v_lin;
  -- sem compromisso, o gravado não vale (o "compre até" vivo)
  update public.os_material set service_order_id = pg_temp.os('OS-00074') where id = v_lin;
  e := (select y from jsonb_array_elements(public.os_prontidao(pg_temp.os('OS-00074'), c_hoje) #> '{material,itens}') y where (y ->> 'id')::uuid = v_lin);
  delete from public.os_material where id = v_lin;
  v_res := pg_temp.ok(v_res, 'P3f sem compromisso (Lenine) o gravado não vale: o "compre até" vivo (20/10) e a chegada de quem compra amanhã (qua 11/11)',
    e ->> 'compre_ate' = '2026-10-20' and e ->> 'data' = '2026-11-11' and (e ->> 'compra_firme')::boolean, e::text);

  -- ── P4. Sem peça suposta e a peça embutida suposta ─────────────────────────────────────────────────────────
  update public.agenda_config set marcar_regras = '{sem_peca,embutida_suposta}' where id;
  p := public.os_prontidao(pg_temp.os('OS-00074'), c_hoje);
  v_res := pg_temp.ok(v_res, 'P4a Lenine (nenhuma linha de material): "marquei sem peça a comprar; se precisar, me diga", sem travar; o material fica completo (era "tem peça a comprar?")',
    p #>> '{material,estado}' = 'completo' and pg_temp.restr(pg_temp.os('OS-00074'), c_hoje) = 'duracao:false sem_peca_suposta:false'
    and pg_temp.texto(pg_temp.os('OS-00074'), c_hoje, 'sem_peca_suposta') = 'marquei sem peça a comprar; se precisar, me diga'
    and pg_temp.pront_antes(pg_temp.os('OS-00074'), c_hoje) #>> '{material,estado}' = 'nao_conferido', pg_temp.restr(pg_temp.os('OS-00074'), c_hoje));
  p := public.os_prontidao(pg_temp.os('OS-97002'), c_hoje);
  v_res := pg_temp.ok(v_res, 'P4b a peça embutida não trava ("… Contei que não; se tiver, me diga") e não deixa o material "não conferido": Sérgio (OS-97002, as baterias na mão) fica completo (era não conferido); Giancarlo diz o texto das 4 linhas',
    pg_temp.texto(pg_temp.os('OS-00130'), c_hoje, 'peca_embutida')
      = 'tem peça embutida em "Barramento e proteções…" ou "Restauração de mola…" (e mais 2)? Contei que não; se tiver, me diga'
    and pg_temp.texto(pg_temp.os('OS-97002'), c_hoje, 'peca_embutida') = 'tem peça embutida em "Instalação de banco…"? Contei que não; se tiver, me diga'
    and (select not (y ->> 'bloqueia')::boolean from jsonb_array_elements(p -> 'restricoes') y where y ->> 'tipo' = 'peca_embutida')
    and p #>> '{material,estado}' = 'completo' and pg_temp.pront_antes(pg_temp.os('OS-97002'), c_hoje) #>> '{material,estado}' = 'nao_conferido',
    pg_temp.restr(pg_temp.os('OS-97002'), c_hoje) || ' | ' || (p #>> '{material,estado}'));
  p := public.os_prontidao(pg_temp.os('OS-00032'), c_hoje);
  v_res := pg_temp.ok(v_res, 'P4c Kalmar OS-00032 (nenhuma linha, só a peça embutida): com as duas regras, conta como sem peça — material completo, sem repetir o "sem peça"',
    p #>> '{material,estado}' = 'completo' and pg_temp.restr(pg_temp.os('OS-00032'), c_hoje) = 'cliente:true peca_embutida:false duracao:false',
    pg_temp.restr(pg_temp.os('OS-00032'), c_hoje));
  update public.agenda_config set marcar_regras = '{embutida_suposta}' where id;
  p := public.os_prontidao(pg_temp.os('OS-00032'), c_hoje);
  v_res := pg_temp.ok(v_res, 'P4d só embutida_suposta: a Kalmar sem linha nenhuma fica "não conferida" (a regra sem_peca é que supõe); a pergunta da embutida não trava',
    p #>> '{material,estado}' = 'nao_conferido' and pg_temp.restr(pg_temp.os('OS-00032'), c_hoje) = 'cliente:true peca_embutida:false duracao:false',
    pg_temp.restr(pg_temp.os('OS-00032'), c_hoje) || ' | ' || (p #>> '{material,estado}'));

  -- ── P5. A duração 'orcamento' e o texto do gestor ──────────────────────────────────────────────────────────
  update public.agenda_config set marcar_regras = c_todas where id;
  p := public.os_prontidao(pg_temp.os('OS-00074'), c_hoje);
  v_res := pg_temp.ok(v_res, 'P5a Lenine: a duração é a estimativa do orçamento — fonte orcamento, 6 dias, "6 dias, 1 pessoa (estimativa minha, pelo valor do orçamento)"; "quantos dias?" não nasce',
    p #>> '{duracao,fonte}' = 'orcamento' and p #>> '{duracao,dias}' = '6'
    and p #>> '{duracao,texto}' = '6 dias, 1 pessoa (estimativa minha, pelo valor do orçamento)'
    and p #>> '{duracao,dias_realista}' = '6' and pg_temp.restr(pg_temp.os('OS-00074'), c_hoje) = 'sem_peca_suposta:false',
    (p -> 'duracao')::text);
  p := public.os_prontidao(pg_temp.os('OS-00069'), c_hoje);
  v_res := pg_temp.ok(v_res, 'P5b Vanderlei: 7,5 dias pela estimativa (fonte orcamento)',
    p #>> '{duracao,fonte}' = 'orcamento' and p #>> '{duracao,dias}' = '7.5'
    and p #>> '{duracao,texto}' = '7,5 dias, 1 pessoa (estimativa minha, pelo valor do orçamento)', (p -> 'duracao')::text);
  select string_agg(format('%s=%s', n, coalesce(pg_temp.texto(pg_temp.os(n), c_hoje, 'duracao'), '-')), ' | ' order by n) into v_novo
    from unnest(array['OS-00130', 'OS-00112', 'OS-97001', 'OS-97002', 'ORÇ-00095']) n;
  v_res := pg_temp.ok(v_res, 'P5c quando o gestor pergunta antes, "quantos dias?" diz o que ele faz sem resposta: grande (Giancarlo), começou sem rastro (Nelson), com rastro (Paulo), peça junto (Sérgio), sem mão de obra (MP)',
    -- (correção da 7a: acima de 8 diárias o gestor espera o dono, achado 20; a peça embutida não pergunta mais, achado 21)
    v_novo = 'ORÇ-00095=o orçamento não tem mão de obra separada: perguntei quantos dias; sem resposta, marco 1 dia'
             || ' | OS-00112=perguntei se já começou; sem resposta, conto 4 dias'
             || ' | OS-00130=pelo valor do orçamento são 10 diárias, mais de 8: perguntei antes de marcar e espero você dizer os dias'
             || ' | OS-97001=perguntei quanto falta; sem resposta, marco 1 dia para terminar'
             || ' | OS-97002=-',
    v_novo);
  p := public.os_prontidao(pg_temp.os('OS-00112'), c_hoje);
  e := (select y from jsonb_array_elements(p -> 'restricoes') y where y ->> 'tipo' = 'situacao');
  v_res := pg_temp.ok(v_res, 'P5d Nelson ganha a restrição situacao, que trava (o texto de _agenda_os_situacao), depois de "quantos dias?" na ordem',
    e ->> 'quem' = 'dono' and (e ->> 'bloqueia')::boolean and e ->> 'pergunta' = 'o serviço já começou?'
    and e ->> 'texto' = public._agenda_os_situacao(pg_temp.os('OS-00112'), c_hoje) ->> 'texto'
    and e ->> 'desde' = public._agenda_os_situacao(pg_temp.os('OS-00112'), c_hoje) ->> 'desde'
    -- (correção da 7a, achado 24: enquanto o gestor pergunta, a duração trava — a OS não é "pronta para começar")
    and pg_temp.restr(pg_temp.os('OS-00112'), c_hoje) = 'compre_ate:true duracao:true situacao:true', e::text);
  v_res := pg_temp.ok(v_res, 'P5e parada há mais de 30 dias (Vanderlei em 05/11): "perguntei se ainda é para fazer o serviço inteiro; sem resposta, conto 7,5 dias"; a situação pergunta "ainda é para fazer o serviço inteiro?"',
    pg_temp.texto(pg_temp.os('OS-00069'), date '2026-11-05', 'duracao') = 'perguntei se ainda é para fazer o serviço inteiro; sem resposta, conto 7,5 dias'
    and (select y ->> 'pergunta' from jsonb_array_elements(public.os_prontidao(pg_temp.os('OS-00069'), date '2026-11-05') -> 'restricoes') y
          where y ->> 'tipo' = 'situacao') = 'ainda é para fazer o serviço inteiro?',
    pg_temp.restr(pg_temp.os('OS-00069'), date '2026-11-05'));
  select string_agg(format('%s=%s', n, pg_temp.restr(pg_temp.os(n), c_hoje)), ' | ' order by n) into v_novo
    from unnest(array['OS-00032', 'OS-00033', 'OS-00076']) n;
  v_res := pg_temp.ok(v_res, 'P5f a OS presa antes pelo cliente (Kalmar ×2, Rodrigo-76, com check-in) não ganha "quanto falta?" nem o texto do gestor: o gestor não pergunta nem marca',
    v_novo = 'OS-00032=cliente:true peca_embutida:false duracao:false | OS-00033=cliente:true duracao:false sem_peca_suposta:false'
             || ' | OS-00076=cliente:true duracao:false'
    and pg_temp.texto(pg_temp.os('OS-00076'), c_hoje, 'duracao') = 'quantos dias e com quem? (chute: meio dia, 1 pessoa)', v_novo);
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
  values (pg_temp.os('OS-00112'), 4, 'orcamento', c_agora)
  on conflict (service_order_id) do update set dias = 4, estimativa_fonte = 'orcamento', estimativa_em = c_agora;
  v_t := public.os_prontidao(pg_temp.os('OS-00112'), c_hoje) #>> '{duracao,texto}';
  update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
  v_novo := public.os_prontidao(pg_temp.os('OS-00112'), c_hoje) #>> '{duracao,texto}';
  update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
  update public.os_planejamento set dias = null, estimativa_fonte = null, estimativa_em = null where service_order_id = pg_temp.os('OS-00112');
  v_res := pg_temp.ok(v_res, 'P5g os 4 dias de fonte orcamento GRAVADOS (a pergunta vencida, P4): "4 dias (estimativa minha)", não "(você disse)"; sem o portão, o de antes',
    v_t = '4 dias (estimativa minha)' and v_novo = '4 dias (você disse)', v_t || ' / ' || v_novo);

  -- ── P6. A classe ──────────────────────────────────────────────────────────────────────────────────────────
  select string_agg(format('%s=%s:%s', n, cl ->> 'classe', cl ->> 'motivo'), ' | ' order by n) into v_novo
    from unnest(v_carteira || array['OS-97001']) n cross join lateral (select pg_temp.classe(pg_temp.os(n), c_hoje) cl) z;
  -- (7a P12: com a regra sinal_cobrar o sinal não segura mais — AG7-09 —, e o MP, sem mão de obra separada, vai à estimativa)
  v_res := pg_temp.ok(v_res, 'P6a a carteira de 29/10 com tudo ligado: Lenine, Vanderlei e Rodrigo-96 no compromisso (2); Giancarlo estimativa, Nelson situacao, Flávio material, Kalmar ×2 e Rodrigo-76 cliente, Robson orçamento, MP estimativa (sem mão de obra; o sinal não segura desde o 7a P12); Paulo (em andamento sem plano) espera o "quanto falta?"',
    v_novo = 'ORÇ-00083=4:orcamento | ORÇ-00095=4:estimativa | OS-00032=4:cliente | OS-00033=4:cliente | OS-00069=2:pronta'
             || ' | OS-00074=2:pronta | OS-00076=4:cliente | OS-00096=2:pronta | OS-00104=4:material | OS-00112=4:situacao'
             || ' | OS-00130=4:estimativa | OS-97001=4:situacao',
    v_novo);
  v_res := pg_temp.ok(v_res, 'P6b o texto da classe é o do gestor: Nelson (o "já começou?") e Giancarlo (as 10 diárias)',
    pg_temp.classe(pg_temp.os('OS-00112'), c_hoje) ->> 'texto' = public._agenda_os_situacao(pg_temp.os('OS-00112'), c_hoje) ->> 'texto'
    and pg_temp.classe(pg_temp.os('OS-00130'), c_hoje) ->> 'texto'
        = 'pelo valor do orçamento são 10 diárias, mais de 8: perguntei antes de marcar e espero você dizer os dias', null);
  -- sem a estimativa, o "sem base" volta a ser 'duracao' e a situação não segura (as chaves não existem)
  update public.agenda_config set marcar_regras = array_remove(c_todas, 'estimativa') where id;
  select string_agg(format('%s=%s:%s', n, cl ->> 'classe', cl ->> 'motivo'), ' | ' order by n) into v_t
    from unnest(array['OS-00069', 'OS-00074', 'OS-00112', 'OS-00130', 'OS-97001']) n cross join lateral (select pg_temp.classe(pg_temp.os(n), c_hoje) cl) z;
  v_res := pg_temp.ok(v_res, 'P6c sem a regra estimativa: os dias só sugeridos deixam só reservar (Lenine, Vanderlei, Nelson, Giancarlo), e o Paulo em andamento volta ao compromisso de antes',
    v_t = 'OS-00069=3:duracao | OS-00074=3:duracao | OS-00112=3:duracao | OS-00130=3:duracao | OS-97001=1:em_execucao', v_t);
  update public.agenda_config set marcar_regras = array_remove(c_todas, 'compra_firme') where id;
  x := pg_temp.classe(pg_temp.os('OS-00069'), c_hoje);
  update public.agenda_config set marcar_regras = c_todas where id;
  v_res := pg_temp.ok(v_res, 'P6d sem compra_firme, o Vanderlei (peça a comprar) só reserva (compra); com ela, compromisso',
    x ->> 'classe' = '3' and x ->> 'condicao_tipo' = 'compra' and pg_temp.classe(pg_temp.os('OS-00069'), c_hoje) ->> 'classe' = '2', x::text);

  -- ── P7. agenda_propor: o sufixo e as críticas novas ────────────────────────────────────────────────────────
  x := public.agenda_propor('os', null, null, array[pg_temp.os('OS-00074'), pg_temp.os('OS-00069')], '{}'::jsonb, false, 'motor', null,
                            c_hoje, c_agora);
  select string_agg(i ->> 'texto', ' || ' order by i ->> 'numero') into v_novo
    from jsonb_array_elements(x -> 'itens') i where i ->> 'op' = 'criar';
  v_res := pg_temp.ok(v_res, 'P7a o compromisso pela estimativa termina "(estimativa minha: 6 dias)." (Lenine) e "(estimativa minha: 7,5 dias)." (Vanderlei)',
    (select count(*) from jsonb_array_elements(x -> 'itens') i where i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' and i ->> 'fonte' = 'orcamento') = 2
    and (select bool_and(i ->> 'texto' like format('%% (estimativa minha: %s).', public._agenda_dias((i ->> 'dias')::numeric)))
           from jsonb_array_elements(x -> 'itens') i where i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva')
    and not exists (select 1 from jsonb_array_elements(x -> 'itens') i
                     where i ->> 'op' = 'criar' and i ->> 'tipo' = 'reserva' and i ->> 'texto' like '%estimativa minha%')
    and v_novo like '%(estimativa minha: 6 dias).%' and v_novo like '%(estimativa minha: 7,5 dias).%', coalesce(v_novo, x::text));
  select replace(p2.prosrc, E'\r\n', E'\n') into v_t from pg_proc p2
   where p2.oid = 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)'::regprocedure;
  v_res := pg_temp.ok(v_res, 'P7b as recomendações das críticas da zona travada (P8): dia_avisado e dia_prometido, nos textos da spec (§6.3)',
    v_t like $l$%if v_tipo = 'dia_avisado' then
          v_rec_txt := 'A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia';
        elsif v_tipo = 'dia_prometido' then
          v_rec_txt := 'É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje';%$l$, null);

  -- ── P8. O portão falso: byte a byte ─────────────────────────────────────────────────────────────────────
  v_dif := null;
  for r in select * from (values
             (1, 'desligado', 'desligado', false, c_todas),
             (2, 'sombra sem a simulação', 'sombra', false, c_todas),
             (3, '*gestor, só propor*', 'ligado', true, c_todas),
             (4, 'sem as regras do P3 (só as da duração)', 'ligado', false, '{mo_limpa,uma_pessoa,diagnostico}'::text[])
           ) t(o, nome, modo, so_propor, regras) order by o loop
    update public.agenda_config set modo_marcar_sozinho = r.modo, gestor_so_propor = r.so_propor, marcar_regras = r.regras where id;
    select count(*), string_agg(so.service_order_number, ', ') filter (where public.os_prontidao(so.id, c_hoje)
                                                                              is distinct from pg_temp.pront_antes(so.id, c_hoje))
      into v_n, v_novo from public.service_orders so;
    if v_novo is not null then v_dif := concat_ws('; ', v_dif, r.nome || ' (prontidão): ' || v_novo); end if;
    select string_agg(so.service_order_number, ', ')
             filter (where public._agenda_classe_da_os(public.os_prontidao(so.id, c_hoje), public.agenda_meios_da_os(so.id, c_hoje), c_hoje, false, false)
                           is distinct from pg_temp.classe_antes(pg_temp.pront_antes(so.id, c_hoje), public.agenda_meios_da_os(so.id, c_hoje), c_hoje, false, false))
      into v_novo from public.service_orders so;
    if v_novo is not null then v_dif := concat_ws('; ', v_dif, r.nome || ' (classe): ' || v_novo); end if;
    select md5(public.agenda_propor('os', null, null, v_ids, '{}'::jsonb, false, 'motor', null, c_hoje, c_agora)::text),
           md5(pg_temp.propor_antes('os', null, null, v_ids, '{}'::jsonb, false, 'motor', null, c_hoje, c_agora)::text)
      into v_m0, v_m1;
    if v_m0 <> v_m1 then v_dif := concat_ws('; ', v_dif, r.nome || ' (proposta)'); end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'P8 com o portão falso (desligado, sombra sem a simulação, *gestor, só propor*, sem as regras do P3), a prontidão e a classe das 28 OS e a proposta das 11 são as de antes, byte a byte',
    v_dif is null and v_n = 28, format('%s OS; diferentes: %s', v_n, coalesce(v_dif, '—')));
  update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = false, marcar_regras = c_todas where id;

  -- ── P10. A memória da vigia ─────────────────────────────────────────────────────────────────────────────
  -- (as escritas de teste na Kalmar OS-00033, que espera o cliente: o Vanderlei do P10c fica sem atividade nova)
  update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
  v_k0 := public._agenda_rodada_marca();
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto)
  values (c_agora, c_hoje, false, 'vigia', 'criar', pg_temp.os('OS-00033'), array[pg_temp.os('OS-00033')], 'TESTE AG7A P3: ação 1');
  v_k1 := public._agenda_rodada_marca();
  update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
  v_k2 := public._agenda_rodada_marca();
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto)
  values (c_agora, c_hoje, false, 'vigia', 'criar', pg_temp.os('OS-00033'), array[pg_temp.os('OS-00033')], 'TESTE AG7A P3: ação 2');
  v_t := public._agenda_rodada_marca()::text;
  -- (correção da 7a, achado 10, 20261031100980: a situação da OS não lê mais as ações nem as perguntas — a parada conta a última
  -- mexida da agenda pelas alocações —, e a marca volta a ser a de sempre, com ou sem a regra situacao: a pergunta e a ação gravadas
  -- na rodada não fazem a vigia recalcular a prontidão de todas as OS)
  v_res := pg_temp.ok(v_res, 'P10a a marca não conta a ação, com ou sem a regra situacao (correção da 7a, achado 10: a de sempre, nunca negativa)',
    v_k0 >= 0 and v_k1 = v_k0 and v_k2 >= 0 and v_t::bigint = v_k2,
    format('sem a regra %s → %s; com a regra %s → %s', v_k0, v_k1, v_k2, v_t));
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, modo)
  values ('situacao', 'situacao:teste-p3', pg_temp.os('OS-00033'), array[pg_temp.os('OS-00033')], 'TESTE AG7A P3: já começou?', 'sombra');
  v_res := pg_temp.ok(v_res, 'P10b com a regra, a pergunta gravada também não move a marca (correção da 7a, achado 10)',
    public._agenda_rodada_marca() = v_t::bigint, v_t || ' → ' || public._agenda_rodada_marca());
  -- a prontidão lembrada numa rodada (agenda.rodada = o dia): Vanderlei em 05/11 está parado (situação pendente); a ação da agenda
  -- nele, na rodada, não muda a conta (é lembrada); a OS mexida (o que a prontidão lê) a recalcula, e a pendência sai
  perform public._agenda_rodada_abrir(date '2026-11-05');
  e := public.os_prontidao(pg_temp.os('OS-00069'), date '2026-11-05');
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto)
  values (timestamptz '2026-11-05 10:00-03', date '2026-11-05', false, 'vigia', 'criar', pg_temp.os('OS-00069'),
          array[pg_temp.os('OS-00069')], 'TESTE AG7A P3: ação na rodada');
  x := public.os_prontidao(pg_temp.os('OS-00069'), date '2026-11-05');
  update public.service_orders set updated_at = timestamptz '2026-11-05 10:00-03' where id = pg_temp.os('OS-00069');
  v_t := public.os_prontidao(pg_temp.os('OS-00069'), date '2026-11-05')::text;
  p := public._agenda_rodada_fechar();
  v_res := pg_temp.ok(v_res, 'P10c dentro da rodada da vigia: o Vanderlei parado tem a restrição situacao; a ação gravada nele na rodada não muda a conta (lembrada, igual); a OS mexida a recalcula e a pendência sai — igual à conta fresca',
    exists (select 1 from jsonb_array_elements(e -> 'restricoes') y where y ->> 'tipo' = 'situacao')
    and x = e
    and not exists (select 1 from jsonb_array_elements(v_t::jsonb -> 'restricoes') y where y ->> 'tipo' = 'situacao')
    and v_t::jsonb = public.os_prontidao(pg_temp.os('OS-00069'), date '2026-11-05') and (p ->> 'ligada')::boolean
    and (p ->> 'calculadas')::int = 2 and (p ->> 'lembradas')::int >= 1,
    p::text || ' | ' || pg_temp.restr(pg_temp.os('OS-00069'), date '2026-11-05'));

  perform pg_temp.gravar(v_res);
end
$fx$;

-- ── P9. As cópias ────────────────────────────────────────────────────────────────────────────────────────
do $copias$
declare
  v_pr   text := coalesce(current_setting('agenda_teste.mig_correcao_desempenho', true), '');
  v_mot2 text := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  v_mot3 text := coalesce(current_setting('agenda_teste.mig_correcao_motor', true), '');
  r      record;
  v_novo text;
  v_n    int;
begin
  if v_pr = '' or v_mot2 = '' or v_mot3 = '' then
    insert into _resultado values ('P9 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      -- (10 blocos do P3 + 1 da correção da 7a, 20261031100980: a OS que o gestor pergunta não é "pronta")
      ('os_prontidao', 'public.os_prontidao(uuid, date)', v_pr, '20261030100400', 11),
      -- (3 blocos do P3 + 1 do 7a P12, 20261031100900: o sinal que não trava; quem recria copia da mais nova)
      ('_agenda_classe_da_os', 'public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)', v_mot2, '20261025100200', 4),
      -- (2 blocos do P3 + 3 do 7a P8, 20261031100700: a zona travada; quem recria copia da mais nova)
      ('agenda_propor', 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', v_mot3, '20261030100200', 5),
      -- (correção da 7a, achado 10, 20261031100980: o bloco do P3 saiu — a marca é de novo a de 20261030100400)
      ('_agenda_rodada_marca', 'public._agenda_rodada_marca()', v_pr, '20261030100400', 0)
    ) t(nome, assinatura, fonte, versao, blocos)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: fim', 'g');
    insert into _resultado
    select format('P9 %s: sem os %s blocos "-- FASE 7:", é o corpo de %s (a mais nova antes da 7a P3)', r.nome, r.blocos, r.versao),
           v_n = r.blocos and pg_temp.corpo(r.fonte, r.nome) <> '' and pg_temp.sem_fase7(v_novo) = pg_temp.corpo(r.fonte, r.nome),
           format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(r.fonte, r.nome)),
                  length(pg_temp.sem_fase7(v_novo)));
  end loop;
end
$copias$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
