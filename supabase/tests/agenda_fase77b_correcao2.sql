-- Prova da correção 2 da Agenda de Produção, Fase 7b (migration 20261101100850): o achado 26 da revisão da 7b, que é da 7a. Com a
-- linha dos dias do dono (seg a sex), a revisão diária da 7a ligada não corta o serviço de presença "o tempo todo" por contar o dono
-- que vai junto como uma pessoa que trabalha, e o texto do corte nunca diz "o orçamento mudou" com o mesmo número antes e depois.
-- Rodado sem a 20261101100850 (o harness f7b/a26/rodar.mjs --sem-a26), as linhas W0, W1, W2, W3b e W5 reprovam; com a versão de
-- antes da revisão da correção 2 (f7b/a26/c3/migration.antes.sql), W0 (o corte), W2, W3b e W5.
-- bancada: depende de 20261101100850
--
--   W0  as cópias e as portas: as 3 recriadas, tirados os blocos "(correção 2, achado 26 da 7a)", são o corpo da definição de antes
--       (a mais nova: 100300, 100500 e 100800), com o número de blocos; as portas são as de antes
--   W1  o cenário real — só o Alex, a linha do dono de seg a sex, o Lenine (OS-00074) com você o tempo todo (a marina nova) — com a
--       7a ligada e a 7b desligada, em teste (o dado) e ligada (o ligar-fase7b: cadastro, dupla, chamar e sábado; os dias em teste):
--       a publicação de qui 05/11 16:30 marca o Lenine com o Alex e você nos 6 dias; a revisão de qui e a de sex (16:53) não cortam
--       nada (o que a estimativa pede = o que o plano tem, 12), nenhuma ação reestimar, os 24 meios-dias de turno ficam; com os 5
--       modos ligados por cima do plano já feito, o mesmo; o foco *agenda gestor* diz "Alex — 6 dias (estimativa minha)"
--   W2  o orçamento que muda de verdade (a mão de obra do Lenine cai para 2/3 depois de marcado): a revisão corta, com "o orçamento
--       mudou e agora estimo N dias (eram 6)", os últimos dias inteiros (o Alex e você juntos), e o N é o que fica — 2 dias com a 7b
--       desligada e com a 7b ligada ("estimo 4 dias": com a 7b ligada o total vem encurtado pela dupla, 6, e o texto dizia "estimo 3
--       dias" deixando 4 — revisão da correção 2, achado 2); com a 7b em teste, só ter 17/11 ("estimo 5 dias": a faixa da dupla do 7b
--       P4, entre o de 1 pessoa, 8, e o com a dupla acrescentada, 2 × 2 + 6 = 10, fica; o texto dizia "estimo 4 dias" deixando 5)
--   W3  a 2ª pessoa de verdade: (a) com a linha do dono e a 7b ligada, o Mateus que o dono chamou para ter 10/11 entra na dupla e a
--       revisão do dia seguinte corta só ter 17/11, com o texto da dupla ("com Mateus junto em ter 10/11, o serviço acaba antes"), não
--       "o orçamento mudou" (no Lenine você só abre e fecha, como em produção); (b) com a 7b desligada e com a 7b ligada e você junto
--       o tempo todo, alguém a mais no último dia (o plano sem meio-dia além da estimativa): o texto honesto ("o plano tem mais gente do
--       que a minha estimativa (6 dias com 1 pessoa)") e só a sobra sai — com a 7b ligada, o texto dizia "o orçamento mudou e agora
--       estimo 5 dias (eram 6)" com o orçamento intacto (revisão da correção 2, achado 2)
--   W4  sem o dono junto, as 3 são as de antes, byte a byte: sem a linha do dono, com a 7a desligada, em teste e ligada e a 7b
--       desligada, em teste e ligada, o "tem", o corte e o foco de cada OS da carteira = os das definições de antes; com a linha do
--       dono, só o Lenine muda (o Rodrigo do diagnóstico, OS-00096, e o resto ficam iguais)
--   W5  a presença mudada depois de marcar (revisão da correção 2, achado 1): o Lenine marcado com o Alex e você nos 6 dias e depois
--       você diz que lá só abre e fecha (o plano não é refeito; o molde de agora não tem você no turno): com a 7b desligada, em teste e
--       ligada, a revisão de qui e a de sex não cortam nada (tem 12 = precisa 12: você vai junto, o molde não o conta), nenhuma ação
--       reestimar, e o foco diz "Alex — 6 dias" — antes, a revisão tirava sex 13, seg 16 e ter 17/11 do Alex e de você, e o Alex
--       ficava com 3 dias num serviço de 6 ("são as mesmas diárias", falso)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase77b_correcao2.sql
--   Seguro em produção: termina em ROLLBACK. W0b (as portas) roda em qualquer banco; as cópias saem PULADO sem as migrations como
--   texto; o resto usa as fixtures e só roda na bancada (fora dela sai PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';
-- a equipe de produção (só o Alex e o dono): antes de carregar a fixture da 7b
select set_config('agenda_teste.fase7b_equipe', 'real', true);

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O corpo de uma função numa migration (o texto entre "as $function$" e "$function$") e a definição inteira.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- O texto sem os blocos desta correção: "-- FASE 7b: (correção 2, achado 26 da 7a) … -- FASE 7b: fim (correção 2)" e, dentro de um
-- bloco da 7b de antes, "-- (correção 2, achado 26 da 7a) … -- (correção 2: fim)" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_c2(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- (FASE 7b: )?\(correção 2, achado 26 da 7a\)' then 1
                                                when l ~ '^\s*-- (FASE 7b: fim \(correção 2\)|\(correção 2: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7b: fim \(correção 2\)|\(correção 2: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;

-- FASE 7d: (7d P4) o texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim": a 20261107100300 recria esta função de novo (só acréscimo), e a régua daqui
-- é de um bloco específico; ela sai antes, na viva (molde: B11d de agenda_fase7c_base.sql)
create function pg_temp.sem_7d(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7[defg]:' and l !~ '^\s*-- FASE 7[defg]: fim' then 1
                                                when l ~ '^\s*-- FASE 7[defg]: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7[defg]: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- FASE 7d: fim

-- ── W0. As cópias e as portas ──────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  f      record;
  v_mig  text;
  v_novo text;
  v_n    int;
begin
  for f in select * from (values
      ('_agenda_gestor_pessoa_meios', 'public._agenda_gestor_pessoa_meios(uuid, date, jsonb)', 'mig_motor_fase7b', '20261101100300', 3),
      ('_agenda_gestor_corte', 'public._agenda_gestor_corte(uuid, date, timestamptz)', 'mig_quem_chamar_fase7b', '20261101100500', 5),
      ('_agenda_ver_gestor', 'public._agenda_ver_gestor(date)', 'mig_correcao_fase7b', '20261101100800', 2))
      as x(nome, sig, mig, versao, blocos) loop
    v_mig := coalesce(current_setting('agenda_teste.' || f.mig, true), '');
    if v_mig = '' then
      insert into _resultado values (format('W0 %s: a cópia', f.nome), true, format('PULADO: sem agenda_teste.%s (rode pela bancada)', f.mig));
      continue;
    end if;
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    select count(*) into v_n from unnest(string_to_array(v_novo, E'\n')) l where l ~ '^\s*-- (FASE 7b: )?\(correção 2, achado 26 da 7a\)';
    insert into _resultado values (
      format('W0 %s: sem os %s blocos da correção 2, é o corpo de %s', f.nome, f.blocos, f.versao),
      pg_temp.corpo(v_mig, f.nome) <> '' and pg_temp.sem_c2(pg_temp.sem_7d(v_novo)) = pg_temp.corpo(v_mig, f.nome) and v_n = f.blocos,
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(v_mig, f.nome)), length(pg_temp.sem_c2(pg_temp.sem_7d(v_novo)))));
  end loop;
end
$copia$;
with f(sig, quem, vol) as (values
  ('public._agenda_gestor_pessoa_meios(uuid, date, jsonb)', 'ninguem', 's'),
  ('public._agenda_gestor_corte(uuid, date, timestamptz)', 'ninguem', 's'),
  ('public._agenda_ver_gestor(date)', 'leitura', 's'))
insert into _resultado
select 'W0b as 3 recriadas com as portas de antes (invoker, search_path fixo; a conta e o corte da revisão: ninguém; o foco: authenticated e service_role; nunca anon)',
       count(p.oid) = 3
       and bool_and(not p.prosecdef and p.provolatile = f.vol and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and case f.quem
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute') end),
       string_agg(format('%s %s definer=%s anon=%s auth=%s srv=%s', f.sig, p.provolatile, p.prosecdef,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── As fixtures (uma vez; cada caso abaixo roda numa subtransação desfeita) ────────────────────────────────────────
-- A fixture da 7b com a equipe de produção: só o Alex e o dono; o Lenine (OS-00074) com você o tempo todo (a regra da marina nova),
-- o Rodrigo (OS-00096) com o diagnóstico (seu) e o Vanderlei (OS-00069) com o comissionamento (seu). A linha do dono entra por caso.
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7b', true), '') = '' or coalesce(current_setting('agenda_teste.fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    return;
  end if;
  execute current_setting('agenda_teste.fase7b');
end
$carga$;

create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97101')
     and exists (select 1 from public.service_orders so where so.service_order_number = 'OS-00074')
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by created_at limit 1
$f$;
-- a linha dos dias do dono (seg a sex, origem dono), como a resposta à padrao_do_dono:sem_dias grava
create function pg_temp.linha_do_dono() returns void language plpgsql as $f$
begin
  perform set_config('agenda_teste.fase7b_dono', 'campo', true);
  execute current_setting('agenda_teste.fase7b');
  perform set_config('agenda_teste.fase7b_dono', '', true);
end $f$;
-- o gestor da 7a (os 5 modos dele) e os modos da 7b: desligado (como nasce), sombra (o dado 20261101100900), ligado (o
-- ligar-fase7b.sql: cadastro, dupla, chamar e sábado; os dias em teste) e ligado5 (os 5)
create function pg_temp.modos(p_7a text, p_7b text) returns void language plpgsql as $f$
begin
  update public.agenda_config
     set modo_marcar_sozinho = p_7a, modo_vaga_fechamento = p_7a, modo_encaixe_aprovacao = p_7a, modo_revisao_diaria = p_7a,
         modo_compre_ate = p_7a, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_7a = 'ligado' then timestamptz '2026-11-03 16:46-03' end
   where id;
  if p_7b in ('sombra', 'ligado', 'ligado5') and (select modo_dupla from public.agenda_config) = 'desligado' then
    execute current_setting('agenda_teste.mig_sombra_fase7b');
  end if;
  if p_7b = 'ligado' then
    update public.agenda_config set modo_cadastro = 'ligado', modo_dupla = 'ligado', modo_chamar = 'ligado', modo_sabado = 'ligado' where id;
  elsif p_7b = 'ligado5' then
    update public.agenda_config set modo_dias = 'ligado', modo_cadastro = 'ligado', modo_dupla = 'ligado', modo_chamar = 'ligado',
           modo_sabado = 'ligado' where id;
  end if;
end $f$;
-- a publicação da quinta (o tique das 16:30: a rotina e a vigia, como o task-automations)
create function pg_temp.publicar(p_dia date default date '2026-11-05') returns void language plpgsql as $f$
begin
  perform public.agenda_rotina_rodar(p_dia, pg_temp.em(p_dia, '16:30'));
  perform public.agenda_vigiar(p_dia, pg_temp.em(p_dia, '16:30'));
end $f$;
-- os meios-dias de turno vigentes da OS: "dd/mm t Nome+Nome; …"
create function pg_temp.vivas(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(x.d || ' ' || x.t || ' ' || x.n, '; ' order by x.d, x.t), '-')
    from (select to_char(a.dia, 'DD/MM') as d, case when a.turno = 'manha' then 'm' else 't' end as t,
                 string_agg(public._agenda_nome_curto(py.name), '+' order by py.name) as n
            from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
           group by 1, 2) x
$f$;
-- as ações reestimar (o corte da revisão) de uma OS, na ordem
create function pg_temp.reestimar(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(a.texto, ' | ' order by a.criada_em, a.id), '-')
    from public.agenda_acoes a where a.tipo = 'reestimar' and a.service_order_id = p_os
$f$;
-- algum texto "o orçamento mudou e agora estimo N (eram N)" com o mesmo número antes e depois, em qualquer ação ou diário
create function pg_temp.texto_falso() returns text language sql stable as $f$
  select coalesce(string_agg(t, ' | '), '') from (
    select a.texto as t from public.agenda_acoes a where a.tipo = 'reestimar'
    union all
    select c ->> 'texto' from public.agenda_gestor_dia g, jsonb_array_elements(coalesce(g.sombra #> '{revisao,cortes}', '[]'::jsonb)) c) x
   where (regexp_match(t, 'agora estimo (.+?) \(eram ([^)]+)\)')) is not null
     and regexp_replace((regexp_match(t, 'agora estimo (.+?) \(eram ([^)]+)\)'))[1], ' dias?$', '')
         = (regexp_match(t, 'agora estimo (.+?) \(eram ([^)]+)\)'))[2]
$f$;
-- a linha do "Marquei nos últimos 7 dias" do foco de uma OS
create function pg_temp.foco(p_cli text, p_dia date) returns text language sql stable as $f$
  select l from unnest(string_to_array(coalesce(public._agenda_ver_gestor(p_dia) ->> 'texto', ''), E'\n')) with ordinality u(l, o)
   where l like '• ' || p_cli || ':%' order by o limit 1
$f$;

-- ── W1. O cenário real: o Lenine com você o tempo todo e a linha do dono, a 7a ligada ─────────────────────────────────
do $w1$
declare
  v_res  jsonb := '[]'::jsonb;
  v_len  uuid;
  c      record;
  v_t0   text;
  v_t1   text;
  v_t2   text;
  v_pm   jsonb;
  v_foco text;
  v_reest text;
  v_falso text;
  v_out  text := '';
  v_bom  boolean := true;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('W1 (o Lenine com a linha do dono)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  for c in select * from (values ('desligado', 'desligado'), ('sombra', 'sombra'), ('ligado', 'ligado'), ('ligado5', 'desligado'))
                         t(modo, publica_com) loop
    begin
      perform pg_temp.linha_do_dono();
      perform pg_temp.modos('ligado', c.publica_com);
      perform pg_temp.publicar();
      v_t0 := pg_temp.vivas(v_len);
      -- com os 5 ligados (os dias também), o motor não põe o Lenine na sua metade da semana (a pendência do dono); o plano já feito
      -- com a 7b desligada fica, e a revisão não o corta
      if c.modo = 'ligado5' then perform pg_temp.modos('ligado', 'ligado5'); end if;
      perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
      v_t1 := pg_temp.vivas(v_len);
      perform public.agenda_gestor_rodar(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'));
      v_t2 := pg_temp.vivas(v_len);
      v_pm := public._agenda_gestor_pessoa_meios(v_len, date '2026-11-06', public.agenda_meios_da_os(v_len, date '2026-11-06'));
      v_foco := pg_temp.foco('Lenine', date '2026-11-06');
      v_reest := pg_temp.reestimar(v_len);
      v_falso := pg_temp.texto_falso();
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_bom := v_bom
      and v_t0 = '10/11 m Alex+Gustavo; 10/11 t Alex+Gustavo; 11/11 m Alex+Gustavo; 11/11 t Alex+Gustavo; 12/11 m Alex+Gustavo; 12/11 t Alex+Gustavo; 13/11 m Alex+Gustavo; 13/11 t Alex+Gustavo; 16/11 m Alex+Gustavo; 16/11 t Alex+Gustavo; 17/11 m Alex+Gustavo; 17/11 t Alex+Gustavo'
      and v_t1 = v_t0 and v_t2 = v_t0 and v_reest = '-' and v_falso = ''
      and v_pm ->> 'tem' = '12' and v_pm ->> 'precisa' = '12'
      and v_foco like '• Lenine: ter 10 a ter 17/11, Alex — 6 dias (estimativa minha).%';
    v_out := v_out || format('[%s: plano %s; qui %s; sex %s; tem %s precisa %s; reestimar %s; falso %s; foco %s] ', c.modo,
                             case when v_t0 like '10/11 m Alex+Gustavo%' then 'Alex+você 10–17/11 (' || (length(v_t0) - length(replace(v_t0, ';', '')) + 1) || ' meios)' else v_t0 end,
                             case when v_t1 = v_t0 then 'igual' else v_t1 end, case when v_t2 = v_t0 then 'igual' else v_t2 end,
                             v_pm ->> 'tem', v_pm ->> 'precisa', v_reest, nullif(v_falso, ''), v_foco);
  end loop;
  v_res := pg_temp.ok(v_res, 'W1 com a linha do dono e a 7a ligada (a 7b desligada, em teste, ligada e com os 5 ligados por cima do plano): o Lenine marcado com o Alex e você nos 6 dias continua inteiro depois da revisão de qui e de sex (tem 12 = precisa 12), nenhuma ação reestimar, nenhum "o orçamento mudou" com o mesmo número, e o foco diz "Alex — 6 dias"',
    v_bom, v_out);
  perform pg_temp.gravar(v_res);
end
$w1$;

-- ── W2. O orçamento que muda de verdade ───────────────────────────────────────────────────────────────────────────
do $w2$
declare
  v_res   jsonb := '[]'::jsonb;
  v_len   uuid;
  c       record;
  v_tot   text;
  v_reest text;
  v_vivas text;
  v_falso text;
  v_foco  text;
  v_out   text := '';
  v_bom   boolean := true;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('W2 (o orçamento que muda)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  -- (revisão da correção 2, achado 2) o número do texto é o que fica: com a 7b em teste, 5 dias (era "estimo 4 dias" deixando 5); com
  -- a 7b ligada, o total vem encurtado pela dupla (6) e o texto dizia "estimo 3 dias" deixando 4
  for c in select * from (values
      ('desligado', '8', 'Lenine (OS-00074): o orçamento mudou e agora estimo 4 dias (eram 6). Tirei seg 16/11 e ter 17/11.',
       '10/11 m Alex+Gustavo; 10/11 t Alex+Gustavo; 11/11 m Alex+Gustavo; 11/11 t Alex+Gustavo; 12/11 m Alex+Gustavo; 12/11 t Alex+Gustavo; 13/11 m Alex+Gustavo; 13/11 t Alex+Gustavo'),
      ('sombra', '8', 'Lenine (OS-00074): o orçamento mudou e agora estimo 5 dias (eram 6). Tirei ter 17/11.',
       '10/11 m Alex+Gustavo; 10/11 t Alex+Gustavo; 11/11 m Alex+Gustavo; 11/11 t Alex+Gustavo; 12/11 m Alex+Gustavo; 12/11 t Alex+Gustavo; 13/11 m Alex+Gustavo; 13/11 t Alex+Gustavo; 16/11 m Alex+Gustavo; 16/11 t Alex+Gustavo'),
      ('ligado', '6', 'Lenine (OS-00074): o orçamento mudou e agora estimo 4 dias (eram 6). Tirei seg 16/11 e ter 17/11.',
       '10/11 m Alex+Gustavo; 10/11 t Alex+Gustavo; 11/11 m Alex+Gustavo; 11/11 t Alex+Gustavo; 12/11 m Alex+Gustavo; 12/11 t Alex+Gustavo; 13/11 m Alex+Gustavo; 13/11 t Alex+Gustavo')) t(modo, total, texto, vivas) loop
    begin
      perform pg_temp.linha_do_dono();
      perform pg_temp.modos('ligado', c.modo);
      perform pg_temp.publicar();
      -- o dono muda o orçamento depois de marcado: a mão de obra cai para 2/3 (de 6 para 4 dias pela estimativa)
      update public.service_order_services set unit_price_snapshot = round(unit_price_snapshot * 2 / 3, 2),
             line_total = round(line_total * 2 / 3, 2)
       where service_order_id = v_len;
      v_tot := public.agenda_meios_da_os(v_len, date '2026-11-05') ->> 'total';
      perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
      v_reest := pg_temp.reestimar(v_len);
      v_vivas := pg_temp.vivas(v_len);
      v_falso := pg_temp.texto_falso();
      v_foco := pg_temp.foco('Lenine', date '2026-11-06');
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    -- o foco diz o mesmo número de dias que o texto (o que fica)
    v_bom := v_bom and v_tot = c.total and v_reest = c.texto and v_vivas = c.vivas and v_falso = ''
             and v_foco like '• Lenine: ter 10 a %, Alex — ' || (regexp_match(c.texto, 'estimo ([0-9,]+ dias?)'))[1] || ' (estimativa minha).%';
    v_out := v_out || format('[%s: total %s; reestimar %s; fica %s; foco %s] ', c.modo, v_tot, v_reest, v_vivas, v_foco);
  end loop;
  v_res := pg_temp.ok(v_res, 'W2 o orçamento do Lenine cai de 6 para 4 dias depois de marcado (a linha do dono, a 7a ligada): a revisão corta com "o orçamento mudou e agora estimo N dias (eram 6)" os últimos dias inteiros, o Alex e você juntos, e o N é o que fica (o foco diz o mesmo) — com a 7b desligada e ligada, seg 16 e ter 17/11, "estimo 4 dias" (a sobra é do técnico; sem a correção, saíam 4 dias; com a 7b ligada, o texto dizia "estimo 3 dias"); em teste, só ter 17/11, "estimo 5 dias" (a faixa da dupla do 7b P4 fica: 10 meios-dias)',
    v_bom, v_out);
  perform pg_temp.gravar(v_res);
end
$w2$;

-- ── W3. A 2ª pessoa de verdade ─────────────────────────────────────────────────────────────────────────────────────
do $w3$
declare
  v_res   jsonb := '[]'::jsonb;
  v_len   uuid;
  v_mat   uuid;
  v       jsonb;
  v_reest text;
  v_vivas text;
  v_falso text;
  v_a     text;
  v_b     text;
  c       record;
  v_bb    text := '';
  v_bok   boolean := true;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('W3 (a 2ª pessoa de verdade)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  -- (a) a dupla completada da 7b (a linha do dono; no Lenine você só abre e fecha, como em produção: com você o tempo todo o passo
  -- dupla não põe o ajudante, a regra 4 pede você no item — ver notas-fase77b.md, CORREÇÃO 2)
  begin
    perform pg_temp.linha_do_dono();
    insert into public.os_planejamento (service_order_id, dono_presenca) values (v_len, 'abre_e_fecha')
    on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.publicar();
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    insert into public.payees (name, kind, active, phone, created_at, updated_at)
    values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-06 08:00-03', timestamptz '2026-11-06 08:00-03');
    v := public.agenda_rascunho_disponibilidade(pg_temp.adm(), 'whatsapp', 'Mateus', 'vem', 'ter 10/11', false, 'o Mateus vem ter 10/11',
                                                date '2026-11-06', null);
    v := public.agenda_rascunho_gravar(pg_temp.adm(), date '2026-11-06');
    perform public.agenda_gestor_rodar(date '2026-11-06', pg_temp.em(date '2026-11-06', '08:07'));
    perform public.agenda_gestor_rodar(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'));
    v_a := concat_ws(' # ', pg_temp.reestimar(v_len), pg_temp.vivas(v_len), nullif(pg_temp.texto_falso(), ''));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'W3a a dupla completada da 7b continua (a linha do dono, a 7b ligada, "Mateus vem ter 10/11"): o passo dupla põe o Mateus com o Alex em ter 10/11 e a revisão do dia seguinte corta só ter 17/11, com o texto da dupla, não "o orçamento mudou"',
    v_a = 'Lenine (OS-00074): com Mateus junto em ter 10/11, o serviço acaba antes (são as mesmas diárias). Tirei ter 17/11. # 10/11 m Alex+Mateus; 10/11 t Alex+Mateus; 11/11 m Alex; 11/11 t Alex; 12/11 m Alex; 12/11 t Alex; 13/11 m Alex; 13/11 t Alex; 16/11 m Alex; 16/11 t Alex',
    v_a);
  -- (b) gente a mais no último dia, com a 7b desligada e com a 7b ligada: o plano não passa da estimativa em meios-dias de calendário
  -- (revisão da correção 2, achado 2: com a 7b ligada, o total vem encurtado pela dupla, 10, e o texto dizia "o orçamento mudou e agora
  -- estimo 5 dias (eram 6)" com o orçamento intacto)
  for c in select * from (values ('desligado'), ('ligado')) x(modo) loop
    begin
      perform pg_temp.linha_do_dono();
      perform pg_temp.modos('ligado', c.modo);
      perform pg_temp.publicar();
      insert into public.payees (name, kind, active, phone, created_at, updated_at)
      values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-05 16:40-03', timestamptz '2026-11-05 16:40-03')
      returning id into v_mat;
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
      select v_len, v_mat, date '2026-11-17', t, 'turno', 'execucao', 'publicada', 'dono', pg_temp.em(date '2026-11-05', '16:40')
        from unnest(array['manha', 'tarde']) t;
      perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
      v_b := concat_ws(' # ', pg_temp.reestimar(v_len), pg_temp.vivas(v_len), nullif(pg_temp.texto_falso(), ''));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_bok := v_bok and v_b = 'Lenine (OS-00074): o plano tem mais gente do que a minha estimativa (6 dias com 1 pessoa), então o serviço acaba antes (são as mesmas diárias). Tirei ter 17/11 à tarde. # 10/11 m Alex+Gustavo; 10/11 t Alex+Gustavo; 11/11 m Alex+Gustavo; 11/11 t Alex+Gustavo; 12/11 m Alex+Gustavo; 12/11 t Alex+Gustavo; 13/11 m Alex+Gustavo; 13/11 t Alex+Gustavo; 16/11 m Alex+Gustavo; 16/11 t Alex+Gustavo; 17/11 m Alex+Gustavo+Mateus';
    v_bb := v_bb || format('[7b %s: %s] ', c.modo, v_b);
  end loop;
  v_res := pg_temp.ok(v_res, 'W3b alguém a mais no último dia do Lenine (a 7b desligada e a 7b ligada, você junto o tempo todo): o plano não passa da estimativa em meios-dias, e o texto diz isso — "o plano tem mais gente do que a minha estimativa (6 dias com 1 pessoa)" —, nunca "o orçamento mudou e agora estimo 6 dias (eram 6)" nem, com a 7b ligada, "estimo 5 dias (eram 6)"; sai só a sobra (o meio-dia com 2 pessoas além de você)',
    v_bok, v_bb);
  perform pg_temp.gravar(v_res);
end
$w3$;

-- ── W4. Sem o dono junto, byte a byte ──────────────────────────────────────────────────────────────────────────────
-- o "tem" e o corte de cada OS da carteira e o foco (a linha do Lenine à parte), lidos agora
create function pg_temp.conta_w4() returns jsonb language plpgsql as $f$
declare
  v jsonb := '{}'::jsonb;
  r record;
  v_m jsonb;
begin
  for r in select k.service_order_id as os, k.numero from public.os_carteira(date '2026-11-06') k order by k.numero loop
    v_m := public.agenda_meios_da_os(r.os, date '2026-11-06');
    v := v || jsonb_build_object(r.numero, md5(public._agenda_gestor_pessoa_meios(r.os, date '2026-11-06', v_m)::text
                                               || public._agenda_gestor_corte(r.os, date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'))::text));
  end loop;
  return v || jsonb_build_object('foco', md5(coalesce((select string_agg(l, E'\n' order by o)
                                                         from unnest(string_to_array(public._agenda_ver_gestor(date '2026-11-06') ->> 'texto', E'\n'))
                                                              with ordinality u(l, o) where l not like '• Lenine:%'), '')),
                                 'foco_lenine', md5(coalesce(pg_temp.foco('Lenine', date '2026-11-06'), '')));
end $f$;
do $w4$
declare
  v_res   jsonb := '[]'::jsonb;
  c       record;
  g       text;
  v_novo  jsonb;
  v_antes jsonb;
  v_dif   text;
  v_esp   text;
  v_out   text := '';
  v_n     int := 0;
  v_bom   boolean := true;
  v_linhas text[];
begin
  if not pg_temp.carregada() or coalesce(current_setting('agenda_teste.mig_correcao_fase7b', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_motor_fase7b', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_quem_chamar_fase7b', true), '') = '' then
    insert into _resultado values ('W4 (sem o dono junto, byte a byte)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- uma publicação por caso (a 7a ligada, como em produção depois de ter 03/11); o gestor da 7a trocado depois, sem publicar de novo
  for c in select * from (values (false, 'desligado'), (false, 'sombra'), (false, 'ligado'), (true, 'desligado'), (true, 'sombra'))
                         t(dono, modo) loop
    v_linhas := '{}';
    begin
      if c.dono then perform pg_temp.linha_do_dono(); end if;
      perform pg_temp.modos('ligado', c.modo);
      perform pg_temp.publicar();
      foreach g in array array['desligado', 'sombra', 'ligado'] loop
        perform pg_temp.modos(g, c.modo);
        v_novo := pg_temp.conta_w4();
        begin
          execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7b'), '_agenda_gestor_pessoa_meios');
          execute pg_temp.inteira(current_setting('agenda_teste.mig_quem_chamar_fase7b'), '_agenda_gestor_corte');
          execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7b'), '_agenda_ver_gestor');
          v_antes := pg_temp.conta_w4();
          v_n := (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%correção 2, achado 26 da 7a%');
          raise exception 'desfaz' using errcode = 'P0099';
        exception when sqlstate 'P0099' then null;
        end;
        v_dif := (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_novo) k where v_novo -> k is distinct from v_antes -> k);
        v_esp := case when c.dono and g = 'ligado' then 'OS-00074, foco_lenine' end;
        v_bom := v_bom and v_n = 0 and v_novo is not null and v_antes is not null and v_dif is not distinct from v_esp;
        v_linhas := v_linhas || format('[%s, 7b %s, 7a %s: %s OS; muda %s%s%s]', case when c.dono then 'com a linha do dono' else 'sem a linha' end,
                                       c.modo, g, (select count(*) - 2 from jsonb_object_keys(v_novo)), coalesce(v_dif, 'nada'),
                                       case when v_n <> 0 then format(' (%s funções da correção 2 ainda)', v_n) else '' end,
                                       case when v_dif is distinct from v_esp then ' <- esperado: ' || coalesce(v_esp, 'nada') else '' end);
      end loop;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_out := v_out || array_to_string(v_linhas, ' ') || ' ';
  end loop;
  v_res := pg_temp.ok(v_res, 'W4 sem o dono junto, byte a byte: sem a linha do dono (a 7b desligada, em teste e ligada; a 7a desligada, em teste e ligada), o "tem", o corte de cada OS da carteira e o foco são os das definições de antes; com a linha do dono, só o Lenine (o tem, o corte e a linha dele no foco) muda, e só com a 7a ligada (em teste, a regra só vale dentro da revisão)',
    v_bom, v_out);
  perform pg_temp.gravar(v_res);
end
$w4$;

-- ── W5. A presença mudada depois de marcar (revisão da correção 2, achado 1) ──────────────────────────────────────────
do $w5$
declare
  v_res   jsonb := '[]'::jsonb;
  v_len   uuid;
  c       record;
  v_t0    text;
  v_t1    text;
  v_t2    text;
  v_m     jsonb;
  v_pm    jsonb;
  v_foco  text;
  v_reest text;
  v_out   text := '';
  v_bom   boolean := true;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('W5 (a presença mudada depois de marcar)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  for c in select * from (values ('desligado'), ('sombra'), ('ligado')) x(modo) loop
    begin
      perform pg_temp.linha_do_dono();
      perform pg_temp.modos('ligado', c.modo);
      perform pg_temp.publicar();
      v_t0 := pg_temp.vivas(v_len);
      -- você diz que no Lenine só abre e fecha (como o *grava* do rascunho planejar: o plano não é refeito)
      insert into public.os_planejamento (service_order_id, dono_presenca) values (v_len, 'abre_e_fecha')
      on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
      -- o tique das 16:45 (a rotina e a vigia) também não refaz
      perform public.agenda_rotina_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
      perform public.agenda_vigiar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
      perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
      v_t1 := pg_temp.vivas(v_len);
      perform public.agenda_gestor_rodar(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'));
      v_t2 := pg_temp.vivas(v_len);
      v_m := public.agenda_meios_da_os(v_len, date '2026-11-06');
      v_pm := public._agenda_gestor_pessoa_meios(v_len, date '2026-11-06', v_m);
      v_foco := pg_temp.foco('Lenine', date '2026-11-06');
      v_reest := pg_temp.reestimar(v_len);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_bom := v_bom
      and v_t0 = '10/11 m Alex+Gustavo; 10/11 t Alex+Gustavo; 11/11 m Alex+Gustavo; 11/11 t Alex+Gustavo; 12/11 m Alex+Gustavo; 12/11 t Alex+Gustavo; 13/11 m Alex+Gustavo; 13/11 t Alex+Gustavo; 16/11 m Alex+Gustavo; 16/11 t Alex+Gustavo; 17/11 m Alex+Gustavo; 17/11 t Alex+Gustavo'
      and v_t1 = v_t0 and v_t2 = v_t0 and v_reest = '-'
      and v_m -> 'dono_turno' = '{"manha": false, "tarde": false}'::jsonb
      and v_pm ->> 'tem' = '12' and v_pm ->> 'precisa' = '12'
      and v_foco like '• Lenine: ter 10 a ter 17/11, Alex — 6 dias (estimativa minha).%';
    v_out := v_out || format('[7b %s: plano %s; qui %s; sex %s; dono_turno %s; tem %s precisa %s; reestimar %s; foco %s] ', c.modo,
                             case when v_t0 like '10/11 m Alex+Gustavo%' then 'Alex+você 10–17/11' else v_t0 end,
                             case when v_t1 = v_t0 then 'igual' else v_t1 end, case when v_t2 = v_t0 then 'igual' else v_t2 end,
                             v_m -> 'dono_turno', v_pm ->> 'tem', v_pm ->> 'precisa', v_reest, v_foco);
  end loop;
  v_res := pg_temp.ok(v_res, 'W5 a presença mudada depois de marcar (a linha do dono, a 7a ligada; a 7b desligada, em teste e ligada): o Lenine marcado com o Alex e você nos 6 dias e depois "lá só abro e fecho" — o molde de agora não tem você no turno, o plano fica: a revisão de qui e a de sex não cortam nada (tem 12 = precisa 12: você vai junto), nenhuma ação reestimar, e o foco diz "Alex — 6 dias"',
    v_bom, v_out);
  perform pg_temp.gravar(v_res);
end
$w5$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
