-- Prova da correção de 29/10 da Agenda de Produção, pacote P5 (migration 20261030100400): o tempo da rodada da vigia.
-- bancada: depende de 20261030100400
--
-- O defeito (auditoria de 29/10, leitor "entrega"): a rodada da vigia subia de 1,8 s para 7,2 s (limite de 8 s, o
-- statement_timeout do papel authenticator do PostgREST) e estourou às 07:30 e às 23:00 de 29/10. A causa, medida na bancada
-- e em produção (só leitura): a mesma prontidão (os_prontidao) era recalculada por OS em cada passo (~37 contas por rodada
-- para 11 OS), e dentro de cada uma o prazo do fornecedor (_agenda_prazo_do_fornecedor, ~6 ms em produção) era calculado
-- ~25 vezes por item, porque o planejador copiava a chamada para cada uso.
--
-- O cenário de HOJE é a fixture-2310.sql que a bancada sempre carrega (as 11 OS de produção) com os modos ligados; e a
-- carteira da Fase 6 (agenda_teste.fase6, a mais cheia: fornecedores, compras, a equipe, o plano conferido). Por cima delas:
--   H  a rodada com e sem a memória faz e diz EXATAMENTE o mesmo: o que cada vigia devolve e o retrato do que ela grava
--      (ações, perguntas, alocações, propostas, rodadas, OS, planejamento, material, fila, erros, a versão do plano), numa
--      semana de tiques de hoje (a publicação de qui 16:30, os tiques sem nada, a reserva que vence), na da Fase 6 e na
--      promoção da reserva do Lenine depois da resposta do dono (o motor grava no meio da rodada)
--   M  a memória: num tique sem nada, uma conta por OS da carteira (as outras lembradas), e sem ela 3 vezes mais; a marca
--      anda com o que a prontidão lê (o planejamento da OS: recalcula, e igual à conta fresca) e com a escrita desfeita
--      (recalcula: nunca lembra o que pode ter mudado), e não anda com a pergunta (lembra); fecha no fim da rodada; com
--      vigia_memoria desligada ou sem os contadores da transação, não abre; o que a vigia devolve não ganha chave
--   T  o tempo de cada passo fica na linha da rodada (contagens.ms), um por passo que rodou
--   B  a barreira: o prazo do fornecedor uma vez por item da prontidão; a prontidão é a de antes, byte a byte, para toda OS,
--      nos dois cenários e em dois dias (a definição de 20261029100900 rodada como pg_temp)
-- Sempre (com ou sem as fixtures):
--   K  as cópias: os_prontidao e agenda_vigiar só acrescentam os blocos "-- CORREÇÃO 29/10 (P5):"
--   G  o que torna a memória certa: a conta da prontidão (todas as funções que ela chama) não lê relógio, variável de sessão
--      nem SQL dinâmico, não chama função volátil e não lê nenhuma das 5 tabelas que a marca ignora. FASE 7 (7a P2): a única
--      variável lida é a do portão do gestor (agenda.gestor, em _agenda_gestor_regra/_agenda_gestor_modo), e G3 prova que nada
--      da rodada da vigia a escreve (constante na rodada = a memória continua certa)
--   P  portas: as peças da memória, ninguém de fora (nem o service_role); as 2 recriadas com as portas de antes; com
--      agenda.rodada posta à mão, a prontidão de um login recusa (42501)
--   C  o interruptor: vigia_memoria, NOT NULL, ligado por padrão
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_correcao_2910_p5.sql
--   Sem as fixtures (produção) os cenários saem PULADO e só K, G, P e C rodam. Os cenários mexem em linhas só dentro de
--   subtransações desfeitas na hora; termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.modos(p_proposta text, p_vigia text) returns void language sql as $f$
  update public.agenda_config set modo_proposta = p_proposta, modo_vigia = p_vigia, modo_leitura = 'ligado' where id
$f$;
-- O corpo (entre as duas marcas $…$) de p_nome na migration p_mig.
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
-- A função inteira (do "create or replace" ao "$function$;") de p_nome na migration p_mig.
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- As linhas fora dos blocos "-- CORREÇÃO 29/10 (P5): … -- CORREÇÃO 29/10 (P5): fim".
create function pg_temp.sem_blocos(p text) returns text language plpgsql immutable as $f$
declare
  v_rev boolean := false;  -- CORREÇÃO 29/10 (revisão): dentro de um bloco da revisão do lote
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and ltrim(l) like '-- CORREÇÃO 29/10 (P5):%' and ltrim(l) not like '-- CORREÇÃO 29/10 (P5): fim%' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro then
      if ltrim(l) like '-- CORREÇÃO 29/10 (P5): fim%' then v_dentro := false; end if;
      continue;
    end if;
    -- CORREÇÃO 29/10 (revisão): os blocos da revisão do lote (20261030100500) também saem, e a linha que um deles
    -- trocou ("-- antes: <a linha>", com o mesmo recuo) volta ao lugar
    if not v_rev and l ~ '^\s*-- CORREÇÃO 29/10 \(revisão\):' and l !~ '^\s*-- CORREÇÃO 29/10 \(revisão\): fim' then
      v_rev := true; continue;
    end if;
    if v_rev then
      if l ~ '^\s*-- CORREÇÃO 29/10 \(revisão\): fim' then v_rev := false;
      elsif l ~ '^\s*-- antes: ' then v_fora := v_fora || regexp_replace(l, '^(\s*)-- antes: ', '\1');
      end if;
      continue;
    end if;
    -- CORREÇÃO 29/10 (revisão): fim
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
-- FASE 7 (7a P3): as linhas fora dos blocos "-- FASE 7: … -- FASE 7: fim" (a 20261031100200 recriou os_prontidao): só para a
-- cópia (K1). O G1 continua com o sem_blocos, que deixa os blocos da 7a à vista (a conta da prontidão é a que roda).
create function pg_temp.sem_fase7(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- FASE 7:' and l !~ '^\s*-- FASE 7: fim' then v_dentro := true; continue; end if;
    if v_dentro then
      if l ~ '^\s*-- FASE 7: fim' then v_dentro := false; end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
-- FASE 7 (7a P3): fim
-- CORREÇÃO DA 7a (revisão, achado 10): os blocos "-- FASE 7: (7a correção, memória da rodada …" (a memória da duração na rodada
-- da vigia, em os_duracao_sugerida desde 20261031100980) são a memória, como os "-- CORREÇÃO 29/10 (P5):" da prontidão: saem antes
-- do G1 (a conta é a que roda dentro, com a memória em pausa).
create function pg_temp.sem_memoria(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(pg_temp.sem_blocos(p), E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- FASE 7: \(7a correção, memória da rodada' then v_dentro := true; continue; end if;
    if v_dentro then
      if l ~ '^\s*-- FASE 7: fim' then v_dentro := false; end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
-- CORREÇÃO DA 7a (revisão, achado 10): fim
-- O texto sem os ids que a rodada gera (cada execução sorteia os seus): todo uuid que não é do molde das fixtures
-- (xxxx0000-0000-4000-8000-…) vira U. As duas variantes partem do mesmo estado, então o resto tem de bater letra a letra.
create function pg_temp.normal(p text) returns text language sql immutable as $f$
  select regexp_replace(p, '(?![0-9a-f]{4}0000-0000-4000-8000-)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g')
$f$;
-- O retrato do que a vigia pode gravar: cada linha sem o id e sem as horas de relógio de parede (criada_em de ação e
-- rodou_em/duracao_ms e o tempo e a memória da rodada), normalizada, em ordem.
create function pg_temp.retrato() returns text language plpgsql as $f$
declare
  t text;
  v text := '';
  l text[];
begin
  foreach t in array array['agenda_acoes', 'agenda_perguntas', 'agenda_alocacoes', 'agenda_propostas', 'agenda_vigia_rodadas',
                           'agenda_dono_avisos', 'whatsapp_send_queue', 'app_error_logs', 'service_orders', 'os_planejamento',
                           'os_material', 'agenda_config'] loop
    execute format($q$select array_agg(pg_temp.normal((to_jsonb(x) - 'id' - 'criada_em' - 'rodou_em' - 'duracao_ms' - 'first_seen_at'
                                                      - 'last_seen_at' - 'vigia_memoria' #- '{contagens,ms}' #- '{contagens,memoria}')::text))
                         from public.%I x$q$, t) into l;
    v := v || t || ' ' || coalesce(cardinality(l), 0) || ': '
         || coalesce((select string_agg(y, ' | ' order by y) from unnest(l) y), '') || E'\n';
  end loop;
  return v;
end $f$;
-- Uma sequência de tiques num cenário, com ou sem a memória, numa subtransação desfeita: o que cada vigia devolveu
-- (normalizado) e o retrato do fim. p_passos: [["2026-10-29", "16:30"], ["sql", "<comando>"], …].
create function pg_temp.cenario(p_prep text, p_passos jsonb, p_memoria boolean) returns text language plpgsql as $f$
declare
  v text := '';
  s jsonb;
begin
  begin
    if p_prep is not null then execute p_prep; end if;
    update public.agenda_config set vigia_memoria = p_memoria where id;
    for s in select x from jsonb_array_elements(p_passos) x loop
      if s ->> 0 = 'sql' then
        execute s ->> 1;
      else
        v := v || (s ->> 0) || ' ' || (s ->> 1) || ' → '
             || pg_temp.normal(public.agenda_vigiar((s ->> 0)::date, pg_temp.em((s ->> 0)::date, s ->> 1))::text) || E'\n';
      end if;
    end loop;
    v := v || pg_temp.retrato();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  return v;
end $f$;
-- A 1ª linha diferente entre dois textos (para o detalhe).
create function pg_temp.primeira_diferenca(a text, b text) returns text language sql immutable as $f$
  select coalesce((select format('linha %s: %s ≠ %s', i, left(coalesce(x, '(fim)'), 300), left(coalesce(y, '(fim)'), 300))
                     from generate_series(1, greatest(cardinality(string_to_array(a, E'\n')), cardinality(string_to_array(b, E'\n')))) i,
                          lateral (select (string_to_array(a, E'\n'))[i] as x, (string_to_array(b, E'\n'))[i] as y) z
                    where x is distinct from y order by i limit 1), 'iguais')
$f$;
-- Quantas vezes a função rodou nesta transação (os contadores da sessão; track_functions = all).
create function pg_temp.chamadas(p_nome text) returns bigint language sql as $f$
  select coalesce(sum(f.calls), 0)::bigint from pg_stat_xact_user_functions f where f.schemaname = 'public' and f.funcname = p_nome
$f$;
-- Os resultados de um cenário, numa variável (o que é gravado numa subtransação desfeita some com ela).
create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
-- Uma consulta como um login (p_uid; null = sem usuário) e um papel: o texto que volta ou "erro <sqlstate>".
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims', case when p_uid is null then json_build_object('role', p_papel)::text
                                                 else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- ── Os cenários ─────────────────────────────────────────────────────────────────────────────────────────
do $cenarios$
declare
  v_fix   boolean := exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000003')
                     and exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000074');
  v_f6    text := coalesce(current_setting('agenda_teste.fase6', true), '');
  v_c6    text := coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '');
  c_hoje   constant date := date '2026-10-29';
  c_lenine constant uuid := '05000000-0000-4000-8000-000000000074';
  c_ven    constant uuid := '05000000-0000-4000-8000-000000000069';
  c_ligar  constant text := $q$update public.agenda_config set modo_proposta = 'ligado', modo_vigia = 'ligado', modo_leitura = 'ligado' where id$q$;
  c_semana constant jsonb := '[["2026-10-29", "16:30"], ["2026-10-29", "16:45"], ["2026-10-29", "17:00"], ["2026-10-30", "09:00"],
                                ["2026-11-03", "08:00"], ["2026-11-03", "17:30"], ["2026-11-04", "12:00"], ["2026-11-05", "08:00"],
                                ["2026-11-05", "16:30"]]';
  c_semana6 constant jsonb := '[["2026-10-30", "08:00"], ["2026-10-30", "17:00"], ["2026-11-03", "08:00"], ["2026-11-03", "12:00"],
                                 ["2026-11-03", "17:30"], ["2026-11-04", "17:30"], ["2026-11-05", "16:30"], ["2026-11-05", "17:00"]]';
  c_promo  constant jsonb := jsonb_build_array(jsonb_build_array('2026-10-29', '16:30'),
    jsonb_build_array('sql', $q$insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, material_conferido_em, trecho, atualizado_por)
      values ('05000000-0000-4000-8000-000000000074', 3, 'dono', timestamptz '2026-10-29 17:00-03', timestamptz '2026-10-29 17:00-03',
              'não tem peça a comprar, leva 3 dias', 'aa000000-0000-4000-8000-000000000001')
      on conflict (service_order_id) do update set dias = excluded.dias, estimativa_fonte = excluded.estimativa_fonte,
        estimativa_em = excluded.estimativa_em, material_conferido_em = excluded.material_conferido_em$q$),
    jsonb_build_array('2026-10-29', '17:15'), jsonb_build_array('2026-10-29', '17:30'), jsonb_build_array('2026-10-30', '09:00'));
  a       text;
  b       text;
  r       jsonb;
  x       jsonb;
  v_m     jsonb;
  v_ms    jsonb;
  v_n     bigint;
  v_n2    bigint;
  v_cart  int;
  v_t     text;
  v_ok    boolean;
  v_det   text;
  v_os    uuid;
  v_d     date;
  v_p1    jsonb;
  v_p0    jsonb;
  v_p2    jsonb;
  v_res   jsonb := '[]'::jsonb;
begin
  if not v_fix then
    insert into _resultado values ('H–B cenários da correção P5', true, 'PULADO: sem a fixture-2310 (rode pela bancada)');
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  -- a definição de ANTES de os_prontidao (a de 20261029100900), para o byte a byte e para a conta fresca
  if v_c6 = '' then
    insert into _resultado values ('B a prontidão de antes', true, 'PULADO: sem agenda_teste.mig_correcao_calculo_fase6 (rode pela bancada)');
    return;
  end if;
  execute replace(pg_temp.inteira(v_c6, 'os_prontidao'), 'create or replace function public.os_prontidao(',
                  'create function pg_temp.pront_antes(');
  perform set_config('track_functions', 'all', true);

  -- ── H. Com e sem a memória: o mesmo, letra a letra ──
  a := pg_temp.cenario(c_ligar, c_semana, true);
  b := pg_temp.cenario(c_ligar, c_semana, false);
  v_res := pg_temp.ok(v_res, 'H1 hoje, uma semana de tiques (a publicação de qui 16:30, os tiques sem nada, a reserva que vence, a publicação seguinte): com e sem a memória, o mesmo que a vigia devolve e o mesmo retrato do que ela grava',
    a = b and a like '%"publicou": true%' and a like '%agenda_alocacoes %', pg_temp.primeira_diferenca(a, b));
  a := pg_temp.cenario(c_ligar, c_promo, true);
  b := pg_temp.cenario(c_ligar, c_promo, false);
  v_res := pg_temp.ok(v_res, 'H2 a promoção da reserva do Lenine depois da resposta do dono (o motor grava no meio da rodada): com e sem a memória, o mesmo',
    a = b and a like '%"promovidas": 1%', pg_temp.primeira_diferenca(a, b));
  if v_f6 = '' then
    insert into _resultado values ('H3 a carteira da Fase 6', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
  else
    a := pg_temp.cenario(v_f6 || '; ' || c_ligar, c_semana6, true);
    b := pg_temp.cenario(v_f6 || '; ' || c_ligar, c_semana6, false);
    v_res := pg_temp.ok(v_res, 'H3 a carteira da Fase 6 (fornecedores, compras, a equipe, o plano conferido), uma semana de tiques: com e sem a memória, o mesmo',
      a = b and a like '%agenda_perguntas %', pg_temp.primeira_diferenca(a, b));
  end if;

  -- ── M e T. A memória numa rodada sem nada (qui 17:00, depois da publicação das 16:30) ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform public.agenda_vigiar(c_hoje, pg_temp.em(c_hoje, '16:30'));
    v_cart := (select count(*) from public.os_carteira(c_hoje));
    v_n := pg_temp.chamadas('os_prontidao');
    r := public.agenda_vigiar(c_hoje, pg_temp.em(c_hoje, '17:00'));
    v_n := pg_temp.chamadas('os_prontidao') - v_n;
    select x.contagens -> 'memoria', x.contagens -> 'ms' into v_m, v_ms
      from public.agenda_vigia_rodadas x where x.rotina = 'vigia' and x.p_agora = pg_temp.em(c_hoje, '17:00');
    update public.agenda_config set vigia_memoria = false where id;
    v_n2 := pg_temp.chamadas('os_prontidao');
    x := public.agenda_vigiar(c_hoje, pg_temp.em(c_hoje, '17:15'));
    v_n2 := pg_temp.chamadas('os_prontidao') - v_n2;
    v_res := pg_temp.ok(v_res, 'M1 num tique sem nada, a memória faz UMA conta da prontidão por OS da carteira e lembra o resto; sem ela, 3 vezes mais contas ou mais',
      (v_m ->> 'ligada')::boolean and (v_m ->> 'calculadas')::int = v_cart and (v_m ->> 'lembradas')::int >= 2 * v_cart
      and v_n = (v_m ->> 'calculadas')::int + (v_m ->> 'calculadas')::int + (v_m ->> 'lembradas')::int
      and v_n2 >= 3 * v_cart,
      format('carteira %s; com a memória %s (contas %s, lembradas %s, chamadas %s); sem ela %s contas', v_cart, v_m,
             v_m ->> 'calculadas', v_m ->> 'lembradas', v_n, v_n2));
    v_res := pg_temp.ok(v_res, 'M2 o que a vigia devolve não ganha chave (sem ms, sem memoria); a memória fecha no fim da rodada (agenda.rodada vazia)',
      not (r -> 'contagens' ? 'ms') and not (r -> 'contagens' ? 'memoria') and r -> 'contagens' ? 'material'
      and coalesce(current_setting('agenda.rodada', true), '') = '' and coalesce(current_setting('agenda.rodada_pront', true), '') = '',
      (r -> 'contagens')::text);
    v_res := pg_temp.ok(v_res, 'T1 a linha da rodada guarda o tempo de cada um dos 15 passos (16 com o equipe_sem_dias da revisão, 20261030100500; ms, inteiro, nenhum negativo, a soma cabe na duração)',
      (select count(*) = 15 + case when to_regprocedure('public._agenda_vigia_equipe_sem_dias(date, timestamptz)') is null then 0 else 1 end and bool_and(jsonb_typeof(e.value) = 'number' and (e.value)::int >= 0) from jsonb_each(v_ms) e)
      and (select sum((e.value)::int) from jsonb_each(v_ms) e)
          <= (select x.duracao_ms + 15 from public.agenda_vigia_rodadas x where x.rotina = 'vigia' and x.p_agora = pg_temp.em(c_hoje, '17:00')),
      v_ms::text);
    v_res := pg_temp.ok(v_res, 'M3 com vigia_memoria desligada a memória não abre (memoria.ligada false, nenhuma conta lembrada) e a vigia devolve o mesmo',
      (select x.contagens -> 'memoria' from public.agenda_vigia_rodadas x where x.rotina = 'vigia' and x.p_agora = pg_temp.em(c_hoje, '17:15'))
        = '{"ligada": false}'::jsonb
      and pg_temp.normal((r - 'acordes')::text) = pg_temp.normal((x - 'acordes')::text),
      (select (x.contagens -> 'memoria')::text from public.agenda_vigia_rodadas x where x.rotina = 'vigia' and x.p_agora = pg_temp.em(c_hoje, '17:15')));
    update public.agenda_config set vigia_memoria = true where id;
    perform set_config('track_counts', 'off', true);
    perform public.agenda_vigiar(c_hoje, pg_temp.em(c_hoje, '17:30'));
    perform set_config('track_counts', 'on', true);
    v_res := pg_temp.ok(v_res, 'M4 sem os contadores da transação (track_counts desligado) a marca não andaria: a memória não abre',
      (select x.contagens -> 'memoria' from public.agenda_vigia_rodadas x where x.rotina = 'vigia' and x.p_agora = pg_temp.em(c_hoje, '17:30'))
        = '{"ligada": false}'::jsonb, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── M. A marca: lembra só enquanto nada do que a prontidão lê foi gravado ──
  begin
    perform public._agenda_rodada_abrir(c_hoje);
    v_p1 := public.os_prontidao(c_ven, c_hoje);
    v_p2 := public.os_prontidao(c_ven, c_hoje);
    v_p0 := pg_temp.pront_antes(c_ven, c_hoje);
    v_t := current_setting('agenda.rodada_conta', true);
    insert into public.agenda_perguntas (tipo, chave, texto, modo, criada_em)
    values ('chegou', 'chegou:p5', 'Chegou?', 'ligado', pg_temp.em(c_hoje, '17:00'));
    perform public.os_prontidao(c_ven, c_hoje);
    v_t := v_t || ' → ' || current_setting('agenda.rodada_conta', true);
    insert into public.os_planejamento (service_order_id, nao_antes_de, nao_antes_motivo) values (c_ven, date '2026-11-20', 'o barco só volta dia 20')
    on conflict (service_order_id) do update set nao_antes_de = excluded.nao_antes_de, nao_antes_motivo = excluded.nao_antes_motivo;
    x := public.os_prontidao(c_ven, c_hoje);
    v_t := v_t || ' → ' || current_setting('agenda.rodada_conta', true);
    begin
      update public.os_planejamento set trecho = trecho where service_order_id = c_ven;
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    r := public.os_prontidao(c_ven, c_hoje);
    v_t := v_t || ' → ' || current_setting('agenda.rodada_conta', true);
    v_m := public._agenda_rodada_fechar();
    v_res := pg_temp.ok(v_res, 'M5 a marca: a 2ª prontidão é lembrada (a mesma); a pergunta gravada não a muda (lembra); o planejamento da OS muda: recalcula, com o "não antes de" novo e igual à conta fresca; a escrita desfeita também recalcula (nunca lembra o que pode ter mudado)',
      v_p1 = v_p2 and v_p1 = v_p0
      and v_t = '{"lembradas": 1, "calculadas": 1} → {"lembradas": 2, "calculadas": 1} → {"lembradas": 2, "calculadas": 2} → {"lembradas": 2, "calculadas": 3}'
      and x ->> 'est_sem_material' = '2026-11-20' and x <> v_p1 and x = pg_temp.pront_antes(c_ven, c_hoje) and r = x
      and v_m = '{"ligada": true, "lembradas": 2, "calculadas": 3}'::jsonb,
      v_t || ' | ' || coalesce(x ->> 'est_sem_material', '(sem)') || ' | ' || v_m::text);
    v_res := pg_temp.ok(v_res, 'M6 fechada a memória, a prontidão volta a ser calculada como sempre (nenhuma conta passa pela memória)',
      public.os_prontidao(c_ven, c_hoje) = pg_temp.pront_antes(c_ven, c_hoje)
      and coalesce(current_setting('agenda.rodada_conta', true), '') = '', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── B. A barreira: o prazo do fornecedor uma vez por item; a prontidão de antes, byte a byte ──
  begin
    v_ok := true;
    v_det := null;
    for v_os in select k.service_order_id from public.os_carteira(c_hoje) k order by k.numero collate "C" loop
      v_n := pg_temp.chamadas('_agenda_prazo_do_fornecedor');
      r := public.os_prontidao(v_os, c_hoje);
      v_n := pg_temp.chamadas('_agenda_prazo_do_fornecedor') - v_n;
      if v_n <> jsonb_array_length(coalesce(r #> '{material,itens}', '[]'::jsonb)) then
        v_ok := false;
        v_det := coalesce(v_det || '; ', '') || format('%s: %s itens, %s contas', v_os, jsonb_array_length(coalesce(r #> '{material,itens}', '[]'::jsonb)), v_n);
      end if;
    end loop;
    v_n := pg_temp.chamadas('_agenda_prazo_do_fornecedor');
    perform pg_temp.pront_antes(c_ven, c_hoje);
    v_n := pg_temp.chamadas('_agenda_prazo_do_fornecedor') - v_n;
    v_res := pg_temp.ok(v_res, 'B1 o prazo do fornecedor é calculado uma vez por item da prontidão, em toda OS da carteira de hoje (antes: o Vanderlei, 4 itens, ' || v_n || ' contas)',
      v_ok and v_n > 4 * jsonb_array_length(public.os_prontidao(c_ven, c_hoje) #> '{material,itens}'), v_det);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_ok := true;
  v_det := null;
  foreach v_d in array array[date '2026-10-29', date '2026-11-05'] loop
    for v_os in select so.id from public.service_orders so order by so.service_order_number loop
      if public.os_prontidao(v_os, v_d)::text is distinct from pg_temp.pront_antes(v_os, v_d)::text then
        v_ok := false;
        v_det := coalesce(v_det || '; ', '') || v_os || ' em ' || v_d;
      end if;
    end loop;
  end loop;
  v_res := pg_temp.ok(v_res, 'B2 hoje: a prontidão de toda OS é a de antes (20261029100900), byte a byte, em qui 29/10 e qui 05/11',
    v_ok and (select count(*) from public.service_orders) >= 11, v_det);
  if v_f6 <> '' then
    begin
      execute v_f6;
      v_ok := true;
      v_det := null;
      foreach v_d in array array[date '2026-10-30', date '2026-11-05'] loop
        for v_os in select so.id from public.service_orders so order by so.service_order_number loop
          if public.os_prontidao(v_os, v_d)::text is distinct from pg_temp.pront_antes(v_os, v_d)::text then
            v_ok := false;
            v_det := coalesce(v_det || '; ', '') || v_os || ' em ' || v_d;
          end if;
        end loop;
      end loop;
      v_res := pg_temp.ok(v_res, 'B3 a carteira da Fase 6 (com fornecedores, OC e notas): a prontidão de toda OS é a de antes, byte a byte, em sex 30/10 e qui 05/11',
        v_ok and (select count(*) from public.service_orders) > 20, v_det);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  else
    insert into _resultado values ('B3 a carteira da Fase 6', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
  end if;

  -- ── N. Desligada, a vigia nem abre a memória ──
  begin
    perform pg_temp.modos('desligado', 'desligado');
    r := public.agenda_vigiar(c_hoje, pg_temp.em(c_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'N1 com os dois modos desligados, {rodou: false} e a memória nem abre (agenda.rodada vazia)',
      r ->> 'rodou' = 'false' and coalesce(current_setting('agenda.rodada', true), '') = '', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$cenarios$;

-- ── K. As cópias ─────────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  v_c6 text := coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '');
  v_f2 text := coalesce(current_setting('agenda_teste.mig_conferencia_fase2', true), '');
  v_novo text;
begin
  if v_c6 = '' or v_f2 = '' then
    insert into _resultado values ('K as cópias só acrescentam os blocos "-- CORREÇÃO 29/10 (P5):"', true,
      'PULADO: sem agenda_teste.mig_correcao_calculo_fase6 / mig_conferencia_fase2 (rode pela bancada)');
    return;
  end if;
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public.os_prontidao(uuid, date)'::regprocedure;
  -- FASE 7 (7a P3): os_prontidao foi recriada de novo em 20261031100200 (só acréscimo, nos blocos "-- FASE 7:"), que saem antes
  insert into _resultado values ('K1 os_prontidao: sem os 3 blocos "-- CORREÇÃO 29/10 (P5):" (a memória e a barreira) e sem os da 7a P3, é o corpo de 20261029100900',
    pg_temp.sem_blocos(pg_temp.sem_fase7(v_novo)) = pg_temp.corpo(v_c6, 'os_prontidao')
    and (select count(*) from regexp_matches(v_novo, '-- CORREÇÃO 29/10 \(P5\): fim', 'g')) = 3,
    format('fonte %s × novo sem blocos %s caracteres', length(pg_temp.corpo(v_c6, 'os_prontidao')),
           length(pg_temp.sem_blocos(pg_temp.sem_fase7(v_novo)))));
  -- FASE 7 (7a P3): fim
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public.agenda_vigiar(date, timestamptz)'::regprocedure;
  insert into _resultado values ('K2 agenda_vigiar: sem os 6 blocos "-- CORREÇÃO 29/10 (P5):" (abrir, o tempo de cada passo, fechar), é o corpo de 20261025100300',
    pg_temp.sem_blocos(v_novo) = pg_temp.corpo(v_f2, 'agenda_vigiar')
    and (select count(*) from regexp_matches(v_novo, '-- CORREÇÃO 29/10 \(P5\): fim', 'g')) = 6,
    format('fonte %s × novo sem blocos %s caracteres', length(pg_temp.corpo(v_f2, 'agenda_vigiar')), length(pg_temp.sem_blocos(v_novo))));
end
$copia$;

-- ── G. O que torna a memória certa (sempre) ──────────────────────────────────────────────────────────────
-- A conta da prontidão inteira: os_prontidao (sem os blocos da memória) e tudo o que ela chama, pelo nome, até o fim.
with recursive g(oid) as (
  select 'public.os_prontidao(uuid, date)'::regprocedure::oid
  union
  select p2.oid
    from g join pg_proc p on p.oid = g.oid
    -- (correção da 7a, achado 10: sem a memória da duração, sem_memoria = sem_blocos + os blocos da memória da rodada)
    cross join lateral regexp_matches(regexp_replace(pg_temp.sem_memoria(p.prosrc), '--[^\n]*', '', 'g'), '([a-z_][a-z0-9_]*)\s*\(', 'g') m
    join pg_proc p2 on p2.proname = m[1] and p2.pronamespace = 'public'::regnamespace
),
corpos as (
  select p.proname, p.provolatile,
         -- FASE 7 (7a P2): o portão do gestor (_agenda_gestor_regra, _agenda_gestor_modo) lê a variável da simulação da sombra,
         -- agenda.gestor; os_duracao_sugerida o chama desde 20261031100100. Só essa leitura, só no portão, sai da conta: a
         -- variável é da transação e nada da rodada da vigia a escreve (G3), então fica constante enquanto a memória vale.
         case when p.proname in ('_agenda_gestor_regra', '_agenda_gestor_modo')
              then regexp_replace(regexp_replace(pg_temp.sem_memoria(p.prosrc), '--[^\n]*', '', 'g'),
                                  'current_setting\(''agenda\.gestor'', true\)', '', 'g')
              -- (correção da 7a, achado 10, 20261031100980: a situação da OS não lê mais a ação nem a pergunta — a exceção do 7a P3
              -- saiu, e o G1 volta a ser estrito com as 5 tabelas)
              else regexp_replace(pg_temp.sem_memoria(p.prosrc), '--[^\n]*', '', 'g') end as src
         -- FASE 7 (7a P2): fim
    from g join pg_proc p on p.oid = g.oid
),
vistas as (
  select c.relname, pg_get_viewdef(c.oid) as def
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('v', 'm')
     and exists (select 1 from corpos k where k.src ~ ('\m' || c.relname || '\M'))
)
insert into _resultado
select 'G1 a conta da prontidão (' || count(*) || ' funções) não lê relógio, variável de sessão nem SQL dinâmico, não chama função volátil e não lê as 5 tabelas que a marca ignora (nem pelas views)',
       count(*) > 20
       and bool_and(provolatile <> 'v')
       and bool_and(src !~* '\m(clock_timestamp|statement_timestamp|timeofday|random|current_setting|set_config|txid_current|nextval)\s*\(')
       and bool_and(src !~* '\mexecute\M')
       and bool_and(src !~ '\m(agenda_perguntas|agenda_acoes|agenda_propostas|agenda_vigia_rodadas|app_error_logs)\M')
       and not exists (select 1 from vistas v where v.def ~ '\m(agenda_perguntas|agenda_acoes|agenda_propostas|agenda_vigia_rodadas|app_error_logs)\M'),
       string_agg(proname, ', ' order by proname) filter (where provolatile = 'v'
                    or src ~* '\m(clock_timestamp|statement_timestamp|timeofday|random|current_setting|set_config|txid_current|nextval)\s*\('
                    or src ~* '\mexecute\M'
                    or src ~ '\m(agenda_perguntas|agenda_acoes|agenda_propostas|agenda_vigia_rodadas|app_error_logs)\M')
  from corpos;
-- FASE 7 (7a P2): a variável do portão do gestor não muda dentro da rodada da vigia — nada que agenda_vigiar chama (pelo nome, até
-- o fim; os passos, que ela chama por format('_agenda_vigia_' || passo), entram pelo prefixo) escreve agenda.gestor (quem escreve
-- é a simulação da sombra do gestor, num job próprio). O dia em que a vigia chamar a sombra, a memória da prontidão passa a
-- precisar da variável na marca, e este teste avisa.
with recursive g(oid) as (
  select p.oid from pg_proc p
   where p.pronamespace = 'public'::regnamespace and (p.proname = 'agenda_vigiar' or p.proname like '\_agenda\_vigia\_%')
  union
  select p2.oid
    from g join pg_proc p on p.oid = g.oid
    cross join lateral regexp_matches(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'), '([a-z_][a-z0-9_]*)\s*\(', 'g') m
    join pg_proc p2 on p2.proname = m[1] and p2.pronamespace = 'public'::regnamespace
)
insert into _resultado
select 'G3 nada da rodada da vigia (' || count(*) || ' funções) escreve a variável do portão do gestor (agenda.gestor): ela fica constante enquanto a memória vale',
       count(*) > 50
       and bool_and(regexp_replace(p.prosrc, '--[^\n]*', '', 'g') !~* 'set_config\(\s*''agenda\.gestor''')
       and exists (select 1 from g g2 where g2.oid = 'public.os_prontidao(uuid, date)'::regprocedure::oid),
       string_agg(p.proname, ', ') filter (where regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'set_config\(\s*''agenda\.gestor''')
  from g join pg_proc p on p.oid = g.oid;
-- FASE 7 (7a P2): fim
insert into _resultado
select 'G2 a marca ignora exatamente as 5 tabelas (a pergunta, a ação, a proposta, a linha da rodada, o erro); todas existem em public',
       p.prosrc like '%c.relname not in (''agenda_perguntas'', ''agenda_acoes'', ''agenda_propostas'', ''agenda_vigia_rodadas'', ''app_error_logs'')%'
       and (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
              and c.relname in ('agenda_perguntas', 'agenda_acoes', 'agenda_propostas', 'agenda_vigia_rodadas', 'app_error_logs')) = 5,
       null
  from pg_proc p where p.oid = 'public._agenda_rodada_marca()'::regprocedure;
-- CORREÇÃO DA 7a (revisão, achado 10; antes, o G4 do 7a P3): a situação da OS (a prontidão a chama pela estimativa do gestor) não lê
-- mais a última ação nem a pergunta aberta, e a marca voltou a ser a de sempre (sem o termo de agenda_acoes e agenda_perguntas, que
-- fazia a vigia recalcular a prontidão de todas as OS a cada pergunta ou ação gravada na rodada: 4 vezes mais lenta com o gestor
-- ligado). O G1 (estrito de novo) prova o resto. Antes da 7a P3 (a prontidão não chama a estimativa), não há o que conferir.
with x as (
  select (select prosrc from pg_proc where oid = to_regprocedure('public.os_prontidao(uuid, date)')) as pront,
         (select regexp_replace(prosrc, '--[^\n]*', '', 'g') from pg_proc where oid = to_regprocedure('public._agenda_os_situacao(uuid, date)')) as sit,
         (select prosrc from pg_proc where oid = to_regprocedure('public._agenda_rodada_marca()')) as marca
)
insert into _resultado
select 'G4 (correção da 7a, achado 10) a situação da OS não lê a ação nem a pergunta, e a marca é a de sempre (sem o termo do 7a P3)',
       case when coalesce(x.pront, '') !~ '_agenda_gestor_estimativa\(' then true
            else x.sit !~ '\m(agenda_acoes|agenda_perguntas)\M'
                 and x.marca not like '%_agenda_gestor_regra%' and x.marca not like '%d.relname%' end,
       case when coalesce(x.pront, '') !~ '_agenda_gestor_estimativa\(' then 'a prontidão ainda não chama a estimativa do gestor' end
  from x;
-- FASE 7 (7a P3): fim

-- ── P. Portas (sempre) ───────────────────────────────────────────────────────────────────────────────────
with f(sig) as (values ('public._agenda_rodada_marca()'), ('public._agenda_rodada_contar(text)'), ('public._agenda_rodada_abrir(date)'),
                       ('public._agenda_rodada_fechar()'), ('public._agenda_rodada_lembrar(uuid)'),
                       ('public._agenda_rodada_guardar(uuid, bigint, jsonb)'))
insert into _resultado
select 'P1 as 6 peças da memória: ninguém de fora (nem anon, nem authenticated, nem o service_role); invoker; search_path fixo',
       count(*) = 6
       and bool_and(not has_function_privilege('anon', f.sig, 'execute') and not has_function_privilege('authenticated', f.sig, 'execute')
                    and not has_function_privilege('service_role', f.sig, 'execute') and not p.prosecdef
                    and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'),
       string_agg(f.sig, ', ') filter (where p.prosecdef or has_function_privilege('service_role', f.sig, 'execute'))
  from f join pg_proc p on p.oid = f.sig::regprocedure;
insert into _resultado
select 'P2 as 2 recriadas com as portas de antes: os_prontidao para quem tem login e o service_role (nunca anon), invoker; agenda_vigiar só o service_role, definer',
       not has_function_privilege('anon', 'public.os_prontidao(uuid, date)', 'execute')
       and has_function_privilege('authenticated', 'public.os_prontidao(uuid, date)', 'execute')
       and has_function_privilege('service_role', 'public.os_prontidao(uuid, date)', 'execute')
       and not (select prosecdef from pg_proc where oid = 'public.os_prontidao(uuid, date)'::regprocedure)
       and not has_function_privilege('anon', 'public.agenda_vigiar(date, timestamptz)', 'execute')
       and not has_function_privilege('authenticated', 'public.agenda_vigiar(date, timestamptz)', 'execute')
       and has_function_privilege('service_role', 'public.agenda_vigiar(date, timestamptz)', 'execute')
       and (select prosecdef from pg_proc where oid = 'public.agenda_vigiar(date, timestamptz)'::regprocedure),
       null;
do $p3$
declare
  v_a text;
  v_b text;
begin
  v_a := pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated', $q$select jsonb_typeof(public.os_prontidao('05000000-0000-4000-8000-000000000069', date '2026-10-29'))$q$);
  perform set_config('agenda.rodada', '2026-10-29', true);
  v_b := pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated', $q$select jsonb_typeof(public.os_prontidao('05000000-0000-4000-8000-000000000069', date '2026-10-29'))$q$);
  perform set_config('agenda.rodada', '', true);
  insert into _resultado values ('P3 um login: fora da rodada a prontidão sai como sempre (nem passa pela memória); com agenda.rodada posta à mão, recusa (42501): a memória só existe dentro da vigia',
    v_a = 'object' and v_b = 'erro 42501', coalesce(v_a, '(null)') || ' / ' || coalesce(v_b, '(null)'));
end
$p3$;

-- ── C. O interruptor (sempre) ────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'C1 agenda_config.vigia_memoria: boolean, NOT NULL, DEFAULT true; a linha ligada',
       a.atttypid = 'boolean'::regtype and a.attnotnull and pg_get_expr(d.adbin, d.adrelid) = 'true'
       and (select c.vigia_memoria from public.agenda_config c where c.id),
       null
  from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'vigia_memoria' and not a.attisdropped;

select teste, ok, detalhe from _resultado order by teste;

rollback;
