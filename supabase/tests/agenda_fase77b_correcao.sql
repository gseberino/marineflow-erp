-- Prova da correção da revisão da Agenda de Produção, Fase 7b (migration 20261101100800): cada achado da revisão, com a régua de
-- antes reprovando (rodado sem a 20261101100800, as linhas X1 a X12 reprovam) e a de agora passando.
-- bancada: depende de 20261101100800
--
--   X0  as cópias e as portas: as 13 recriadas, tirados os blocos "-- FASE 7b: (correção da revisão da 7b", são o corpo da
--       definição de antes (as da própria 7b), com o número de blocos; as portas são as de antes
--   X1  o foco *agenda gestor* (achados 1, 9 e 15): com o texto_max de sempre, o bloco "Quem chamar" aparece (em teste e ligado) e
--       nenhuma linha da 7a some ("Fora:", "Se aprovar:"); a dupla que é só nota (o espaço confinado) continua com o "Pode precisar
--       de dupla", dizendo que *com dupla* é o tempo todo (achados 5 e 11)
--   X2  o *livre* (achados 15 e 25): a linha de quem chamar entra depois do corte, também com o *livre* comprido
--   X3  o rascunho (achados 2, 13, 16 e 21): "Alex saiu" (nao_vem, padrao, "seg a sáb") com a pergunta dos dias em teste vira o
--       rascunho da semana inteira (desligado, a recusa de antes); as datas ditas por extenso viram essas datas
--   X4  a semana dita pelo dono prende só a semana (achados 3 e 10): o padrão do Alex não muda; a opção 2 da pergunta dos dias cria o
--       padrão do dono e diz "toda semana"
--   X5  a resposta da equipe (achado 8): com modo_dias ligado e a ficha mandada depois da pergunta da semana, "não posso", "ok, sexta
--       tô lá", "sim, todos prontos" seguem o caminho de antes; a lista dos dias ("seg ter qui") é da semana
--   X6  a linha (n) do fechamento (achados 17 e 7): a dias_semana curta não conta como mostrada; a chamada da 7a ligada fica ligada
--       com o cadastro da 7b em teste
--   X7  o teto do dono (achado 14): em teste, o de antes (o plano da 7b em teste = o da 7b desligada, com a linha do dono)
--   X8  o *desfaz* da 2ª pessoa da dupla (achado 18): "tirei Mateus do Lenine …"; a recusa por sobreposição diz como voltar
--   X9  o passo dupla (achado 4): com o fim do serviço já avisado (a revisão não corta), a 2ª pessoa só dentro do teto
--   X10 o sábado do 7a em teste (achado 12): com modo_sabado sombra e a pergunta crítica sabado decidida, a manhã de sábado conta
--   X11 quem chamar (achados 19, 20, 22 e 25): a reserva não é "sem lugar"; os meios-dias de mais uma pessoa sem os do dono; a dupla
--       dita que só cabe depois do prazo diz isso; a parte prazo diz o que falar
--   X12 o motor (achados 22 e 23): o exemplo com todos os dias; a dupla dita com os dias do ajudante antes de a OS ficar pronta
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase77b_correcao.sql
--   Seguro em produção: termina em ROLLBACK. X0 (as portas) roda em qualquer banco; as cópias saem PULADO sem as migrations como
--   texto; o resto usa as fixtures e só roda na bancada (fora dela sai PULADO).
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
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O corpo de uma função numa migration (o texto entre "as $function$" e "$function$").
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O texto sem os blocos desta correção ("-- FASE 7b: (correção da revisão da 7b" … o "-- FASE 7b: fim" do mesmo nível; e, dentro de um
-- bloco da 7b de antes, "-- (correção da revisão da 7b, achado" … "-- (correção da revisão da 7b: fim)"): as linhas de abrir e de
-- fechar saem junto; os outros blocos "-- FASE 7b:" ficam.
create function pg_temp.sem_correcao(p text) returns text language plpgsql immutable as $f$
declare
  l      text;
  v_out  text[] := '{}';
  v_pil  boolean[] := '{}';
  v_corr boolean;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if l ~ '^\s*-- \(correção da revisão da 7b: fim\)' then
      v_pil := v_pil[1 : cardinality(v_pil) - 1];
      continue;
    end if;
    if l ~ '^\s*-- \(correção da revisão da 7b, achado' then
      v_pil := v_pil || true;
      continue;
    end if;
    if l ~ '^\s*-- FASE 7b: fim' then
      v_corr := v_pil[cardinality(v_pil)];
      v_pil := v_pil[1 : cardinality(v_pil) - 1];
      if not v_corr and not (true = any (v_pil)) then v_out := v_out || l; end if;
      continue;
    end if;
    if l ~ '^\s*-- FASE 7b:' then
      v_corr := l ~ '^\s*-- FASE 7b: \(correção da revisão da 7b';
      v_pil := v_pil || v_corr;
      if not v_corr and not (true = any (v_pil)) then v_out := v_out || l; end if;
      continue;
    end if;
    if not (true = any (v_pil)) then v_out := v_out || l; end if;
  end loop;
  return array_to_string(v_out, E'\n');
end $f$;
-- (correção 2 da 7b, achado 26) a 20261101100850 recria _agenda_ver_gestor de novo, com os blocos "-- FASE 7b: (correção 2, achado 26
-- da 7a) … -- FASE 7b: fim (correção 2)": o X0 os tira antes (tirados, o corpo é o desta correção, byte a byte)
create function pg_temp.sem_c2(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- (FASE 7b: )?\(correção 2, achado 26 da 7a\)' then 1
                                                when l ~ '^\s*-- (FASE 7b: fim \(correção 2\)|\(correção 2: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7b: fim \(correção 2\)|\(correção 2: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- (correção 3 da 7b) a 20261101100860 recria _agenda_linhas_do_fechamento e _agenda_gestor_dupla de novo, com os blocos "-- FASE 7b:
-- (correção 3) … -- FASE 7b: fim (correção 3)" e, dentro de um bloco da 7b de antes, "-- (correção 3) … -- (correção 3: fim)": o X0 os
-- tira antes (tirados, o corpo é o desta correção, byte a byte)
create function pg_temp.sem_c3(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- (FASE 7b: )?\(correção 3\)' then 1
                                                when l ~ '^\s*-- (FASE 7b: fim \(correção 3\)|\(correção 3: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7b: fim \(correção 3\)|\(correção 3: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7b', true), '') <> ''
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
-- a fixture da 7b numa das variantes (equipe: '' a da fixture, 'real' a de produção; dono: '' sem linha, 'campo' a linha seg–sex)
create function pg_temp.carregar(p_equipe text, p_dono text) returns void language plpgsql as $f$
begin
  perform set_config('agenda_teste.fase7b_equipe', coalesce(p_equipe, ''), true);
  perform set_config('agenda_teste.fase7b_dono', coalesce(p_dono, ''), true);
  execute current_setting('agenda_teste.fase7b');
end $f$;
-- o gestor da 7a (os 5 modos dele) e os 5 modos da 7b
create function pg_temp.modos(p_gestor text, p_7b text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_gestor, modo_encaixe_aprovacao = p_gestor, modo_revisao_diaria = p_gestor, modo_compre_ate = p_gestor,
         modo_vaga_fechamento = p_gestor, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_gestor = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         modo_dias = p_7b, modo_dupla = p_7b, modo_sabado = p_7b, modo_cadastro = p_7b, modo_chamar = p_7b
   where id;
$f$;
-- "no Lenine e no Vanderlei eu só abro e fecho" (o que o dono disse nas sondas da revisão; sem isso o Lenine, presença sempre, espera
-- os dias do dono)
create function pg_temp.abre_fecha() returns void language sql as $f$
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
$f$;
-- os meios-dias vigentes da OS ("dd/mm t Nome+Nome; …"; turno e reserva)
create function pg_temp.vivas(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(x.d || ' ' || x.t || ' ' || x.n || x.r, '; ' order by x.d, x.t), '-')
    from (select to_char(a.dia, 'DD/MM') as d, case when a.turno = 'manha' then 'm' else 't' end as t,
                 string_agg(public._agenda_nome_curto(py.name), '+' order by py.name) as n,
                 case when bool_or(a.tipo = 'reserva') then ' (reserva)' else '' end as r
            from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.presenca = 'turno'
           group by 1, 2) x
$f$;
create function pg_temp.marcar(p_os uuid[], p_dia date default date '2026-11-05') returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
begin
  v_p := public.agenda_propor('os', null, null, p_os, '{}'::jsonb, true, 'vigia', null, p_dia, pg_temp.em(p_dia, '16:45'));
  return public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, p_dia, pg_temp.em(p_dia, '16:45'));
end $f$;
-- a fala do dono pelo rascunho e o *grava*
create function pg_temp.disse(p_pessoa text, p_situacao text, p_dias text, p_padrao boolean, p_trecho text, p_semana text default null,
                              p_hoje date default date '2026-11-05') returns jsonb language sql as $f$
  select public.agenda_rascunho_disponibilidade(pg_temp.adm(), 'whatsapp', p_pessoa, p_situacao, p_dias, p_padrao, p_trecho, p_hoje, p_semana)
$f$;
create function pg_temp.padroes(p_payee uuid) returns text language sql stable as $f$
  select coalesce(string_agg(d.dias_semana::text || ':' || d.situacao || ':' || d.origem, ' ' order by d.criado_em, d.id), '-')
    from public.agenda_disponibilidade d
   where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null
$f$;

-- ── X0. As cópias e as portas ──────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  f      record;
  v_mig  text;
  v_novo text;
  v_n    int;
begin
  for f in select * from (values
      ('_agenda_ver_gestor', 'public._agenda_ver_gestor(date)', 'mig_quem_chamar_fase7b', '20261101100500', 8),
      ('agenda_livre_de_verdade', 'public.agenda_livre_de_verdade(date, timestamptz)', 'mig_quem_chamar_fase7b', '20261101100500', 3),
      ('_agenda_quem_chamar', 'public._agenda_quem_chamar(date, timestamptz)', 'mig_quem_chamar_fase7b', '20261101100500', 7),
      ('_agenda_gestor_dupla', 'public._agenda_gestor_dupla(date, timestamptz)', 'mig_quem_chamar_fase7b', '20261101100500', 3),
      ('agenda_rascunho_disponibilidade', 'public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text)',
       'mig_disponibilidade_fase7b', '20261101100100', 3),
      ('_agenda_equipe_dias_gravar', 'public._agenda_equipe_dias_gravar(uuid, date, smallint[], boolean, text, text, timestamptz, uuid, uuid, uuid)',
       'mig_disponibilidade_fase7b', '20261101100100', 2),
      ('agenda_decidir', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'mig_pergunta_fase7b', '20261101100200', 2),
      ('agenda_resposta_da_equipe', 'public.agenda_resposta_da_equipe(text, text, text, timestamptz)', 'mig_pergunta_fase7b', '20261101100200', 1),
      ('_agenda_linhas_do_fechamento', 'public._agenda_linhas_do_fechamento(date)', 'mig_pergunta_fase7b', '20261101100200', 2),
      ('agenda_desfazer', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'mig_pergunta_fase7b', '20261101100200', 3),
      ('_agenda_carga_da_pessoa', 'public._agenda_carga_da_pessoa(uuid)', 'mig_motor_fase7b', '20261101100300', 1),
      ('_agenda_contexto', 'public._agenda_contexto(date, date, date, uuid[], uuid[])', 'mig_motor_fase7b', '20261101100300', 1),
      ('agenda_propor', 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'mig_motor_fase7b', '20261101100300', 3))
      as x(nome, sig, mig, versao, blocos) loop
    v_mig := coalesce(current_setting('agenda_teste.' || f.mig, true), '');
    if v_mig = '' then
      insert into _resultado values (format('X0 %s: a cópia', f.nome), true, format('PULADO: sem agenda_teste.%s (rode pela bancada)', f.mig));
      continue;
    end if;
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    v_novo := pg_temp.sem_c2(v_novo);  -- (correção 2 da 7b, achado 26) os blocos da 20261101100850 saem antes
    v_novo := pg_temp.sem_c3(v_novo);  -- (correção 3 da 7b) e os da 20261101100860
    select count(*) into v_n from unnest(string_to_array(v_novo, E'\n')) l where l ~ '^\s*-- (FASE 7b: )?\(correção da revisão da 7b, achado';
    insert into _resultado values (
      format('X0 %s: sem os %s blocos da correção, é o corpo de %s', f.nome, f.blocos, f.versao),
      pg_temp.corpo(v_mig, f.nome) <> '' and pg_temp.sem_correcao(v_novo) = pg_temp.corpo(v_mig, f.nome) and v_n = f.blocos,
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(v_mig, f.nome)), length(pg_temp.sem_correcao(v_novo))));
  end loop;
end
$copia$;
with f(sig, quem) as (values
  ('public._agenda_ver_gestor(date)', 'leitura'), ('public.agenda_livre_de_verdade(date, timestamptz)', 'leitura'),
  ('public._agenda_quem_chamar(date, timestamptz)', 'ninguem'), ('public._agenda_gestor_dupla(date, timestamptz)', 'ninguem'),
  ('public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text)', 'leitura'),
  ('public._agenda_equipe_dias_gravar(uuid, date, smallint[], boolean, text, text, timestamptz, uuid, uuid, uuid)', 'ninguem'),
  ('public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'servico'),
  ('public.agenda_resposta_da_equipe(text, text, text, timestamptz)', 'servico'),
  ('public._agenda_linhas_do_fechamento(date)', 'leitura'), ('public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'servico'),
  ('public._agenda_carga_da_pessoa(uuid)', 'leitura'), ('public._agenda_contexto(date, date, date, uuid[], uuid[])', 'servico'),
  ('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'servico'))
insert into _resultado
select 'X0b as 13 recriadas com as portas de antes (nunca anon; as leituras do painel com authenticated e service_role; o motor, a rodada e as palavras só com service_role; as internas com ninguém)',
       count(p.oid) = 13
       and bool_and(not has_function_privilege('anon', p.oid, 'execute')
                    and case f.quem
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          when 'servico' then not has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute') end),
       coalesce(string_agg(f.sig, '; ') filter (where p.oid is null), '-')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── X1. O foco *agenda gestor* ─────────────────────────────────────────────────────────────────────────────────
do $x1$
declare
  v_res jsonb := '[]'::jsonb;
  eq    text;
  m     text;
  v_txt jsonb := '{}'::jsonb;
  v_t   text;
  v_falt text;
  a     text;
  b     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X1 (o foco)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  -- o gestor da 7a ligado, a 7b desligada × em teste × ligada, com a fixture e com a equipe de produção (texto_max de sempre)
  foreach eq in array array['', 'real'] loop
    foreach m in array array['desligado', 'sombra', 'ligado'] loop
      begin
        perform pg_temp.carregar(eq, '');
        perform pg_temp.modos('ligado', m);
        perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
        v_t := public._agenda_ver_gestor(date '2026-11-05') ->> 'texto';
        raise exception 'desfaz' using errcode = 'P0099';
      exception when sqlstate 'P0099' then null;
      end;
      v_txt := v_txt || jsonb_build_object(coalesce(nullif(eq, ''), 'fixture') || ':' || m, v_t);
    end loop;
  end loop;
  -- as linhas da 7a que somem com a 7b (fora as que a 7b troca de propósito: a da dupla)
  select string_agg(format('%s/%s: %s', k.eq, k.m, l), ' ⏎ ') into v_falt
    from (select e.eq, e2.m from unnest(array['fixture', 'real']) e(eq) cross join unnest(array['sombra', 'ligado']) e2(m)) k
    cross join lateral unnest(string_to_array(v_txt ->> (k.eq || ':desligado'), E'\n')) l
   where l <> '' and l not like '%Pode precisar de dupla%'
     and not (l = any (string_to_array(v_txt ->> (k.eq || ':' || k.m), E'\n')));
  v_res := pg_temp.ok(v_res, 'X1a (achados 1, 9 e 15) com o gestor da 7a ligado e o texto_max de sempre, nenhuma linha da 7a some do foco quando a 7b entra (em teste ou ligada: o "Fora:" e o "(e mais N linhas)" de antes ficam), e o bloco de quem chamar aparece no fim, logo antes do "Como eu conto"',
    v_falt is null
    and v_txt ->> 'fixture:sombra' like '%' || E'\n' || 'Em teste: quem chamar%' || E'\n' || 'Como eu conto: %'
    and v_txt ->> 'real:sombra' like '%' || E'\n' || 'Em teste: quem chamar%' || E'\n' || 'Como eu conto: %'
    and v_txt ->> 'real:ligado' like '%' || E'\n' || 'Quem chamar%' || E'\n' || 'Como eu conto: %',
    coalesce(v_falt, '') || ' || ' || (v_txt ->> 'real:sombra'));
  v_res := pg_temp.ok(v_res, 'X1b (achados 5 e 11) a dupla que é só nota (o espaço confinado do Otávio) continua com o "Pode precisar de dupla", em teste e ligado: "diga *Otávio com dupla* (em dupla o tempo todo)"; com só o Alex, "chame um ajudante, me diga os dias dele e diga …"',
    v_txt ->> 'fixture:sombra' like '%Otávio: % Pode precisar de dupla (espaço apertado): diga *Otávio com dupla* (em dupla o tempo todo).%'
    and v_txt ->> 'real:ligado' like '%Otávio: % Pode precisar de dupla (espaço apertado): hoje só Alex está na equipe: para ir dupla, chame um ajudante, me diga os dias dele e diga *Otávio com dupla* (em dupla o tempo todo).%'
    and v_txt ->> 'real:desligado' like '%Otávio: % Pode precisar de dupla (espaço apertado): hoje só Alex está na equipe: para ir dupla, chame um ajudante e diga *Otávio com dupla*.%',
    (v_txt ->> 'fixture:sombra') || ' || ' || (v_txt ->> 'real:ligado'));
  -- o estado de produção (o gestor da 7a em teste), o dado da 7b (os 5 modos em teste), a semana da equipe (16:45) e a rodada do
  -- gestor (16:53), a fixture: o bloco aparece com o texto_max de sempre (o F1 da revisão)
  begin
    perform pg_temp.carregar('', '');
    perform pg_temp.abre_fecha();
    perform pg_temp.modos('sombra', 'desligado');
    execute replace(current_setting('agenda_teste.mig_sombra_fase7b'), E'\r\n', E'\n');
    perform public.agenda_equipe_semana(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    a := (select g.chamar ->> 'texto' from public.agenda_gestor_dia g where g.dia = date '2026-11-05');
    b := public._agenda_ver_gestor(date '2026-11-05') ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X1c (achado 1) com o gestor da 7a em teste (o de produção) e a 7b em teste, o foco mostra "Em teste: quem chamar" com as sugestões do diário, com o texto_max de sempre (antes, o corte do meio as escondia)',
    a like 'Quem chamar (só sugiro; quem chama é você):' || E'\n' || '• %'
    and b like '%' || E'\n' || 'Em teste: quem chamar (só sugiro; quem chama é você):' || E'\n' || '• %'
    and position(split_part(a, E'\n', 2) in b) > 0,
    coalesce(a, '-') || ' || ' || coalesce(b, '-'));
  perform pg_temp.gravar(v_res);
end
$x1$;

-- ── X2. O *livre* ──────────────────────────────────────────────────────────────────────────────────────────────
do $x2$
declare
  v_res jsonb := '[]'::jsonb;
  a     text;
  b     text;
  v_l   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X2 (o livre)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  -- a carteira real com a linha do dono, o Lenine e o Vanderlei "abre e fecha" e o prazo do Vanderlei em ter 01/12 (o sH da revisão:
  -- o prazo só fecha com um ajudante junto do Alex)
  begin
    perform pg_temp.carregar('real', 'campo');
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.abre_fecha();
    update public.os_planejamento set precisa_ate = date '2026-12-01' where service_order_id = pg_temp.os('OS-00069');
    perform public.agenda_vigiar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:30'));
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    v_l := (select g.chamar ->> 'texto_livre' from public.agenda_gestor_dia g where g.dia = date '2026-11-05');
    a := public.agenda_livre_de_verdade(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10')) ->> 'texto_completo';
    -- o *livre* comprido (o texto_max no mínimo, 400): o corte do fim tirava a linha de quem chamar
    update public.agenda_config set texto_max = 400 where id;
    b := public.agenda_livre_de_verdade(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10')) ->> 'texto_completo';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X2 (achados 15 e 25) a linha de quem chamar do *livre* diz o prazo que só fecha com um ajudante e o que falar ("Vanderlei só cumpre o prazo de ter 01/12 … Se chamar, diga: Vanderlei com dupla; Mateus vem …") e entra depois do corte do texto_max: com o texto_max de sempre e com o mínimo (400), o *livre* termina nela',
    v_l like 'Vanderlei só cumpre o prazo de ter 01/12 com um ajudante junto de Alex %. Se chamar, diga: Vanderlei com dupla; Mateus vem %.%'
    and right(a, length(v_l) + 1) = E'\n' || v_l and right(b, length(v_l) + 1) = E'\n' || v_l
    and b like '%(e mais %',
    concat_ws(' || ', v_l, right(a, 400), b));
  perform pg_temp.gravar(v_res);
end
$x2$;

-- ── X3. O rascunho: "fulano saiu" e as datas ditas por extenso ─────────────────────────────────────────────────
do $x3$
declare
  v_res jsonb := '[]'::jsonb;
  f     text;
  m     text;
  v     jsonb;
  a     text := '';
  b     text := '';
  c     text;
  d     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X3 (o rascunho)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  foreach m in array array['sombra', 'desligado'] loop
    begin
      perform pg_temp.carregar('real', '');
      update public.agenda_config set modo_dias = m where id;
      v := pg_temp.disse('Alex', 'nao_vem', 'seg a sáb', true, 'o Alex saiu');
      a := a || m || '=' || coalesce(v ->> 'item', v ->> 'motivo') || '; ';
      v := pg_temp.disse('Alex', 'nao_vem', 'seg a sex', true, 'o Alex não trabalha mais com a gente');
      a := a || m || '=' || coalesce(v ->> 'item', v ->> 'motivo') || '; ';
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'X3a (achados 2, 13 e 21) "o Alex saiu" (nao_vem, padrao, "seg a sáb", o que o prompt e a opção 2 da chamada ensinam) com a pergunta dos dias em teste vira o rascunho da semana inteira, como "não vem mais de segunda a sábado"; desligado, a recusa de antes (fora_do_trecho)',
    a = 'sombra=Alex: não vem de seg a sex (sábado eu só conto por data); sombra=Alex: não vem de seg a sex; desligado=fora_do_trecho; desligado=fora_do_trecho; ',
    a);
  -- as datas ditas por extenso (qui 05/11, a 7b ligada; o Mateus cadastrado, sem linha)
  begin
    perform pg_temp.carregar('real', '');
    update public.agenda_config set modo_dias = 'ligado', modo_dupla = 'ligado' where id;
    insert into public.payees (name, kind, active, phone, created_at, updated_at)
    values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-05 10:00-03', timestamptz '2026-11-05 10:00-03');
    foreach f in array array['qua 18/11 e qui 19/11', '18/11 e 19/11', 'quarta dia 18 e quinta dia 19', 'dia 18 e 19', 'qua e qui', 'qui 19 a qua 25/11'] loop
      v := pg_temp.disse('Mateus', 'vem', f, false, 'o Mateus vem ' || f);
      b := b || f || '=' || coalesce(v ->> 'item', v ->> 'texto') || '; ';
      delete from public.agenda_rascunho where true;
    end loop;
    v := pg_temp.disse('Mateus', 'vem', 'qui 18/11 e sex 19/11', false, 'o Mateus vem qui 18/11 e sex 19/11');
    c := v ->> 'texto';
    delete from public.agenda_rascunho where true;
    v := pg_temp.disse('Mateus', 'vem', '18/11 e 19/11', false, 'o Mateus vem 18/11 e 19/11');
    perform public.agenda_rascunho_gravar(pg_temp.adm(), date '2026-11-05');
    d := (select string_agg(lower(x.periodo)::text || ':' || x.situacao || ':' || x.origem, ' ' order by lower(x.periodo))
            from public.agenda_disponibilidade x where x.payee_id = pg_temp.pessoa('Mateus') and x.substituida_em is null)
         || ' | padrão ' || pg_temp.padroes(pg_temp.pessoa('Mateus'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X3b (achado 16) as datas de quem vem sob demanda ditas por extenso viram essas datas ("qua 18/11 e qui 19/11", "18/11 e 19/11", "quarta dia 18 e quinta dia 19", "dia 18 e 19" = qua 18 e qui 19/11); "qua e qui" continua a 1ª semana por vir e "qui 19 a qua 25/11" a faixa; o dia da semana que não bate é recusado; o *grava* põe só as duas datas, nunca padrão',
    replace(b, '. Mateus ainda não está na equipe da agenda: com *grava*, ele entra só nesses dias', '')
      = 'qua 18/11 e qui 19/11=Mateus: vem qua 18/11 e qui 19/11 (só nesses dias); 18/11 e 19/11=Mateus: vem qua 18/11 e qui 19/11 (só nesses dias); quarta dia 18 e quinta dia 19=Mateus: vem qua 18/11 e qui 19/11 (só nesses dias); dia 18 e 19=Mateus: vem qua 18/11 e qui 19/11 (só nesses dias); qua e qui=Mateus: vem qua 11/11 e qui 12/11 (só nesses dias); qui 19 a qua 25/11=Mateus: vem de qui 19/11 a qua 25/11; '
    and c = 'Os dias da semana e as datas não batem (qua 18/11 e qui 19/11): me diga de novo.'
    and d = '2026-11-18:disponivel:dono 2026-11-19:disponivel:dono | padrão -',
    concat_ws(' || ', b, c, d));
  perform pg_temp.gravar(v_res);
end
$x3$;

-- ── X4. A semana dita pelo dono prende só a semana; a opção 2 da pergunta dos dias cria o padrão do dono ───────────────
do $x4$
declare
  v_res jsonb := '[]'::jsonb;
  v_alex uuid;
  v_dono uuid;
  v     jsonb;
  a     text;
  b     text;
  c     text;
  v_q   uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X4 (a semana dita)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.carregar('real', '');
    update public.agenda_config set modo_dias = 'sombra' where id;
    v_alex := pg_temp.pessoa('Alex');
    a := pg_temp.padroes(v_alex);
    v := pg_temp.disse('Alex', 'vem', 'segunda e terça', false, 'o Alex só pode segunda e terça na semana que vem', 'semana que vem');
    v := public.agenda_rascunho_gravar(pg_temp.adm(), date '2026-11-05');
    b := pg_temp.padroes(v_alex) || ' | ' || (v ->> 'texto') || ' | '
         || (select string_agg(to_char(lower(x.periodo), 'DD/MM') || '=' || x.situacao, ' ' order by lower(x.periodo))
               from public.agenda_disponibilidade x where x.payee_id = v_alex and x.substituida_em is null and x.semana_dita = date '2026-11-09')
         || ' | ' || (public.agenda_capacidade_semanal(date '2026-11-05') ->> 'diarias_semana');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X4a (achados 3 e 10) "o Alex só pode segunda e terça na semana que vem" + *grava*, com a pergunta dos dias em teste: só a semana de 09/11 fica presa (seg e ter vem, qua a sex não); o padrão dele (seg a sex, origem dono) não muda e a capacidade semanal continua 5 diárias',
    a = '{1,2,3,4,5}:disponivel:dono' and b like '{1,2,3,4,5}:disponivel:dono | Gravado. Agora:' || E'\n' || '• Alex, semana de 09/11: vem seg e ter (e não vem de qua a sex). | 09/11=disponivel 10/11=disponivel 11/11=indisponivel 12/11=indisponivel 13/11=indisponivel | 5.00',
    concat_ws(' || ', a, b));
  -- a opção 2 ("Fico em campo de seg a sex") da pergunta dos dias do dono cria o padrão dele e diz que é toda semana; a variável
  -- volta a vazio
  begin
    perform pg_temp.carregar('real', '');
    perform pg_temp.modos('ligado', 'ligado');
    v_dono := public._agenda_dono(null);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where tipo = 'padrao_do_dono' and estado = 'aberta';
    perform public.agenda_equipe_semana(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    perform public.agenda_equipe_semana(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:00'));
    select q.id into v_q from public.agenda_perguntas q where q.tipo = 'dias_semana' and q.estado = 'aberta';
    v := public.agenda_decidir(v_q, 2::smallint, pg_temp.adm(), 'whatsapp', '2', date '2026-11-05', pg_temp.em(date '2026-11-05', '18:00'));
    c := (v ->> 'texto') || ' | ' || pg_temp.padroes(v_dono) || ' | ' || coalesce(nullif(current_setting('agenda.dias_padrao_do_dono', true), ''), 'vazia');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X4b (achados 3 e 10) a opção 2 da pergunta dos dias ("Fico em campo de seg a sex") cria o padrão do dono e a resposta diz que é toda semana; a variável agenda.dias_padrao_do_dono volta a vazio',
    c = 'Anotei: você fica em campo de seg a sex, toda semana a partir de agora. Se mudar, me diga. | {1,2,3,4,5}:disponivel:dono | vazia', c);
  perform pg_temp.gravar(v_res);
end
$x4$;

-- ── X5. A resposta da equipe com a pergunta da semana aberta ───────────────────────────────────────────────────
do $x5$
declare
  v_res  jsonb := '[]'::jsonb;
  v_raf  uuid;
  v_fone text;
  t      text;
  v      jsonb;
  a      text := '';
  b      text := '';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X5 (a resposta da equipe)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  -- o Rafael recebe a pergunta da semana (qui 16:45) e, depois, a ficha de sex 06/11 (19:30); responde às 20:10
  foreach t in array array['não posso', 'ok, sexta tô lá', 'sim, todos prontos', 'seg ter qui'] loop
    begin
      perform pg_temp.carregar('', '');
      update public.agenda_config set modo_equipe = 'ligado', modo_dias = 'ligado' where id;
      select id, phone into v_raf, v_fone from public.payees where name = 'Rafael' and active limit 1;
      perform public._agenda_equipe_registrar(v_raf, date '2026-11-16', 'dias', 'Oi, Rafael! Para a semana de 16/11 a 20/11, quais dias você pode vir?',
                                              pg_temp.em(date '2026-11-05', '16:45'));
      perform public._agenda_equipe_registrar(v_raf, date '2026-11-06', 'ficha', 'Amanhã (sex 06/11) você está no Lenine às 8h. Responda ok.',
                                              pg_temp.em(date '2026-11-05', '19:30'));
      v := public.agenda_resposta_da_equipe(v_fone, t, 'wa-x5-' || md5(t), pg_temp.em(date '2026-11-05', '20:10'));
      a := a || t || '=' || coalesce(v ->> 'tipo', '-') || '/'
           || (select m.estado from public.agenda_equipe_mensagens m where m.payee_id = v_raf and m.tipo = 'dias' order by m.criada_em desc limit 1)
           || '/' || pg_temp.padroes(v_raf) || '; ';
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'X5 (achado 8) com modo_dias ligado e a ficha mandada depois da pergunta da semana, "não posso" é o "não vou" da ficha, "ok, sexta tô lá" e "sim, todos prontos" confirmam a ficha — a pergunta da semana continua aberta e o padrão dele não muda; "seg ter qui" (só os dias) é da semana',
    a = 'não posso=nao_vou/enfileirada/{1,2,3,4,5}:disponivel:diarista; ok, sexta tô lá=ok/enfileirada/{1,2,3,4,5}:disponivel:diarista; sim, todos prontos=ok/enfileirada/{1,2,3,4,5}:disponivel:diarista; seg ter qui=dias/respondida/{1,2,4}:disponivel:diarista; ',
    a);
  perform pg_temp.gravar(v_res);
end
$x5$;

-- ── X6. A linha (n) do fechamento ──────────────────────────────────────────────────────────────────────────────
do $x6$
declare
  v_res jsonb := '[]'::jsonb;
  l     jsonb;
  v     jsonb;
  a     text;
  b     text;
  v_q   uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X6 (a linha da equipe)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  -- a chamada (nunca vista) e a dias_semana na mesma linha: a dias_semana vai curta e não conta como mostrada
  begin
    perform pg_temp.carregar('real', '');
    perform pg_temp.modos('ligado', 'ligado');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where tipo = 'padrao_do_dono' and estado = 'aberta';
    update public.agenda_config set dias_semana_motivos = '{sempre}' where id;
    perform public.agenda_equipe_semana(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
    l := public._agenda_linhas_do_fechamento(date '2026-11-05');
    select x into v from jsonb_array_elements(l) x where x ->> 'texto' like 'Agenda: Na agenda conto com Alex%';
    perform public.agenda_fechamento_registrar(date '2026-11-05', jsonb_build_array(v), 'fechamento', pg_temp.em(date '2026-11-05', '17:30'));
    a := (v ->> 'perda') || ' | ' || (select string_agg(q.tipo || ':' || q.mostrada_vezes, ' ' order by q.tipo) from public.agenda_perguntas q
                                       where q.tipo in ('equipe_cadastro', 'dias_semana') and q.estado = 'aberta')
         || ' | ' || coalesce((select x ->> 'texto' from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-06')) x
                                where x ->> 'tipo' = 'pergunta' and x ->> 'texto' like 'Agenda: %Também: %' limit 1), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X6a (achado 17) a dias_semana que vai só como "Também: os dias da semana de 16/11 (responda em *agenda pendências*)." não conta como mostrada (a chamada, inteira, conta): ela segue com mostrada_vezes 0 e a linha de amanhã continua com perda 75',
    a like '75 | dias_semana:0 equipe_cadastro:1 | %', a);
  -- a chamada da 7a (sem opções), aberta e ligada, com o cadastro da 7b em teste: a linha (n) dela fica ligada
  begin
    perform pg_temp.carregar('real', '');
    perform pg_temp.modos('ligado', 'sombra');
    insert into public.agenda_perguntas (tipo, chave, texto, opcoes, modo, criada_em)
    values ('equipe_cadastro', 'equipe_cadastro:chamada:2026-11-16', 'A equipe da semana de 16/11 mudou? Na agenda conto com Alex.', '[]'::jsonb,
            'ligado', pg_temp.em(date '2026-11-05', '16:52'))
    returning id into v_q;
    l := public._agenda_linhas_do_fechamento(date '2026-11-05');
    b := coalesce((select x ->> 'modo' || ' | ' || (x ->> 'texto') from jsonb_array_elements(l) x where x ->> 'pergunta_id' = v_q::text), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X6b (achado 7) a chamada da 7a (sem opções), aberta e ligada, com o cadastro da 7b em teste: a linha (n) dela sai ligada (o dono continua vendo; antes ia ao teste)',
    b like 'ligado | Agenda: A equipe da semana de 16/11 mudou?%', b);
  perform pg_temp.gravar(v_res);
end
$x6$;

-- ── X7. O teto do dono em teste ────────────────────────────────────────────────────────────────────────────────
do $x7$
declare
  v_res jsonb := '[]'::jsonb;
  m     text;
  v_len uuid;
  v_t   jsonb := '{}'::jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X7 (o teto do dono)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  -- a equipe de produção com a linha do dono, a 7a ligada; muda só o modo_dias
  foreach m in array array['desligado', 'sombra', 'ligado'] loop
    begin
      perform pg_temp.carregar('real', 'campo');
      perform pg_temp.modos('ligado', 'desligado');
      update public.agenda_config set modo_dias = m where id;
      v_len := pg_temp.os('OS-00074');
      perform public.agenda_vigiar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:30'));
      perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
      v_t := v_t || jsonb_build_object(m, public._agenda_carga_da_pessoa(public._agenda_dono(null))::text || ' | ' || pg_temp.vivas(v_len));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'X7 (achado 14) com a linha do dono e só o modo_dias em teste, o teto do dono e o plano são os da 7b desligada (o Lenine, presença sempre, marcado, não reserva); a meia capacidade (0,50) só com modo_dias ligado',
    split_part(v_t ->> 'sombra', ' | ', 1) = '0.80' and v_t ->> 'sombra' = v_t ->> 'desligado'
    and v_t ->> 'desligado' not like '%(reserva)%' and split_part(v_t ->> 'ligado', ' | ', 1) = '0.50',
    v_t::text);
  perform pg_temp.gravar(v_res);
end
$x7$;

-- ── X8. O *desfaz* da 2ª pessoa da dupla ───────────────────────────────────────────────────────────────────────
do $x8$
declare
  v_res  jsonb := '[]'::jsonb;
  v_len  uuid;
  v_acao uuid;
  v      jsonb;
  a      text;
  b      text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X8 (o desfaz da dupla)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.carregar('real', '');
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.abre_fecha();
    v_len := pg_temp.os('OS-00074');
    insert into public.payees (name, kind, active, phone, created_at, updated_at)
    values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-05 10:00-03', timestamptz '2026-11-05 10:00-03');
    perform pg_temp.marcar(array[v_len]);
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    perform pg_temp.disse('Mateus', 'vem', 'ter 10/11', false, 'o Mateus vem ter 10/11');
    perform public.agenda_rascunho_gravar(pg_temp.adm(), date '2026-11-05');
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'));
    select ac.id into v_acao from public.agenda_acoes ac where ac.tipo = 'reparar' and ac.service_order_id = v_len order by ac.criada_em desc limit 1;
    if v_acao is null then
      a := '(o passo dupla não pôs o Mateus) | ' || pg_temp.vivas(v_len);
    else
      v := public.agenda_desfazer(v_acao, pg_temp.adm(), 'dono', date '2026-11-05', pg_temp.em(date '2026-11-05', '17:30'));
      a := coalesce(v ->> 'texto', v::text) || ' | ' || pg_temp.vivas(v_len);
    end if;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X8a (achado 18) desfazer a 2ª pessoa que o gestor pôs na dupla diz que só ela saiu e o serviço continua marcado (não "sai da agenda")',
    a like 'Desfeito: tirei Mateus do Lenine (OS-00074) em ter 10/11 (manhã e tarde); o resto do serviço fica como estava. | 10/11 m Alex; 10/11 t Alex; %',
    a);
  -- depois da revisão (o fim cortado e outra OS no meio-dia que sobrou), a recusa diz como voltar
  begin
    perform pg_temp.carregar('real', 'campo');
    perform pg_temp.modos('ligado', 'ligado');
    v_len := pg_temp.os('OS-00074');
    insert into public.payees (name, kind, active, phone, created_at, updated_at)
    values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-05 10:00-03', timestamptz '2026-11-05 10:00-03');
    perform pg_temp.abre_fecha();
    perform public.agenda_vigiar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:30'));
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    perform pg_temp.disse('Mateus', 'vem', 'ter 10/11', false, 'o Mateus vem ter 10/11', null, date '2026-11-06');
    perform public.agenda_rascunho_gravar(pg_temp.adm(), date '2026-11-06');
    perform public.agenda_gestor_rodar(date '2026-11-06', pg_temp.em(date '2026-11-06', '08:07'));
    perform public.agenda_gestor_rodar(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'));
    select ac.id into v_acao from public.agenda_acoes ac where ac.tipo = 'reestimar' and ac.service_order_id = v_len order by ac.criada_em desc limit 1;
    b := coalesce((select ac.texto from public.agenda_acoes ac where ac.id = v_acao), '(sem corte)');
    if v_acao is not null then
      v := public.agenda_desfazer(v_acao, pg_temp.adm(), 'dono', date '2026-11-06', pg_temp.em(date '2026-11-06', '17:45'));
      b := b || ' | ' || coalesce(v ->> 'texto', v::text);
    end if;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X8b (achado 18) com a dupla completada, a revisão corta o fim ("com Mateus junto …, o serviço acaba antes") e, com outra OS no meio-dia que sobrou, a recusa do *desfaz* diz como voltar (desfazer antes o que ocupou o lugar)',
    b like 'Lenine (OS-00074): com Mateus junto em ter 10/11, o serviço acaba antes (são as mesmas diárias). Tirei %'
    and (b like '% | Desfeito: %'
         or b ~ ' \| Não dá para desfazer: o Alex já está no .+\. Com Mateus junto, o Lenine acaba antes; se quiser o dia de volta mesmo assim, diga \*desfaz .+\* e depois \*desfaz Lenine\*\.$'),
    b);
  perform pg_temp.gravar(v_res);
end
$x8$;

-- ── X9. O passo dupla com o fim do serviço já avisado ──────────────────────────────────────────────────────────
do $x9$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  v_ult date;
  x     jsonb;
  y     jsonb;
  a     text;
  b     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X9 (o passo dupla)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  -- o Lenine com o Alex (só ele na equipe) e o Mateus dito em ter 10/11: a semana de 09/11 cheia (o teto da equipe)
  foreach a in array array['cortavel', 'avisado'] loop
    begin
      perform pg_temp.carregar('real', '');
      perform pg_temp.modos('ligado', 'ligado');
      perform pg_temp.abre_fecha();
      v_len := pg_temp.os('OS-00074');
      insert into public.payees (name, kind, active, phone, created_at, updated_at)
      values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-05 10:00-03', timestamptz '2026-11-05 10:00-03');
      perform pg_temp.marcar(array[v_len]);
      v_ult := (select max(al.dia) from public.agenda_alocacoes al where al.service_order_id = v_len and al.estado in ('publicada', 'fixada')
                                                                   and al.tipo <> 'reserva');
      if a = 'avisado' then
        -- o último dia do serviço com a ficha do Alex na fila: a revisão do dia seguinte não o corta
        insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
        values (pg_temp.pessoa('Alex'), v_ult, 'ficha', 'ligado', 'Ficha de teste', pg_temp.em(v_ult - 1, '19:30'), 'enfileirada',
                'teste:X9:ficha:alex:' || v_ult);
      end if;
      insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
      values (pg_temp.pessoa('Mateus'), daterange(date '2026-11-10', date '2026-11-10', '[]'), null, 'disponivel', 'dono',
              'Você disse que vem (sob demanda)', pg_temp.em(date '2026-11-05', '17:01'));
      x := public._agenda_gestor_dupla(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'));
      y := (select pr.parametros -> 'p_restricoes' from public.agenda_propostas pr
             where pr.parametros #>> '{gestor,motivo}' = 'dupla_completa' order by pr.criada_em desc limit 1);
      b := coalesce(b || ' || ', '') || a || ': ' || coalesce(x ->> 'completadas', x::text) || ' | ' || coalesce(y::text, '-') || ' | ' || pg_temp.vivas(v_len);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'X9 (achado 4) com o fim do serviço cortável, a 2ª pessoa entra nos 2 meios-dias, acima da carga (a revisão do dia seguinte corta o fim); com o último dia já avisado à equipe (a revisão não corta), ela só entra até o teto da equipe-semana: o 1º meio-dia (o 2º passaria do teto: 10 meios-dias de serviço para 9), nunca acima do teto',
    b like 'cortavel: 1 | {"acima_da_carga": true} | 10/11 m Alex+Mateus; 10/11 t Alex+Mateus; 11/11 m Alex; %'
    and b like '% || avisado: 1 | % | 10/11 m Alex+Mateus; 10/11 t Alex; 11/11 m Alex; %',
    b);
  perform pg_temp.gravar(v_res);
end
$x9$;

-- ── X10. O sábado do 7a com modo_sabado em teste ───────────────────────────────────────────────────────────────
do $x10$
declare
  v_res jsonb := '[]'::jsonb;
  m     text;
  v_c   jsonb;
  v_sab int;
  a     text := '';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X10 (o sábado)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  -- o Rafael com o padrão de sábado de manhã; a decisão da pergunta crítica sabado liga agenda.sabado (na transação dela)
  foreach m in array array['desligado', 'sombra', 'ligado'] loop
    begin
      perform pg_temp.carregar('', '');
      update public.agenda_config set modo_sabado = m, sabado_manha = 'so_prazo' where id;
      insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, criado_em)
      values (pg_temp.pessoa('Rafael'), '{6}', 'manha', 'disponivel', 'diarista', 'Disse que pode sábado de manhã', pg_temp.em(date '2026-11-05', '10:00'));
      perform set_config('agenda.sabado', 'on', true);
      v_c := public._agenda_contexto(date '2026-11-09', date '2026-11-15', date '2026-11-05');
      perform set_config('agenda.sabado', '', true);
      v_sab := (date '2026-11-14' - date '2026-11-09') + 1;
      a := a || m || '=' || coalesce((v_c -> 'util' ->> (v_sab - 1)), '-') || '; ';
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'X10 (achado 12) com a pergunta crítica sabado do 7a decidida (agenda.sabado = on), a manhã do sáb 14/11 conta na grade com modo_sabado desligado e em teste (antes, em teste não contava); só ligado vale só o sábado da 7b',
    a = 'desligado=true; sombra=true; ligado=false; ', a);
  perform pg_temp.gravar(v_res);
end
$x10$;

-- ── X11. Quem chamar ───────────────────────────────────────────────────────────────────────────────────────────
do $x11$
declare
  v_res jsonb := '[]'::jsonb;
  v_tan uuid;
  v_len uuid;
  v_van uuid;
  q     jsonb;
  w     jsonb;
  a     text;
  b     text;
  c     text;
  v_pm  int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X11 (quem chamar)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  -- a equipe de produção com a linha do dono, a 7a e a 7b ligadas: a rodada da vigia (16:30) e a do gestor (16:53) reservam a Tânia
  -- acima da carga; quem chamar (o passo da mesma rodada) não a dá como "sem lugar"
  begin
    perform pg_temp.carregar('real', 'campo');
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.abre_fecha();
    v_tan := pg_temp.os('OS-97003');
    perform public.agenda_vigiar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:30'));
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    q := (select g.chamar from public.agenda_gestor_dia g where g.dia = date '2026-11-05');
    a := pg_temp.vivas(v_tan) || ' | ' || coalesce((q #> '{capacidade,sem_lugar}')::text, '-') || ' | ' || coalesce(q ->> 'texto', '-');
    -- os meios-dias de mais uma pessoa: nunca mais que o trabalho das OS que passam a caber
    v_pm := (select coalesce(sum(coalesce((public.agenda_meios_da_os((o ->> 'os')::uuid, date '2026-11-05') #>> '{dupla,pm}')::int,
                                          (public.agenda_meios_da_os((o ->> 'os')::uuid, date '2026-11-05') ->> 'total')::int)), 0)
               from jsonb_array_elements(coalesce(q #> '{capacidade,extra,os}', '[]'::jsonb)) o);
    b := coalesce(q #>> '{capacidade,extra,meios_total}', '-') || ' <= ' || v_pm;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X11a (achado 20) a Tânia, reservada acima da carga pela rodada do gestor, não aparece como "sem lugar" no quem chamar da mesma rodada',
    a like '%(reserva)%' and position(v_tan::text in a) = 0 and a not like '%Tânia%', a);
  v_res := pg_temp.ok(v_res, 'X11b (achado 19) os meios-dias de mais uma pessoa não passam do trabalho das OS que passam a caber (sem os turnos do dono)',
    b = '-' || ' <= 0' or (split_part(b, ' <= ', 1))::int <= (split_part(b, ' <= ', 2))::int, b);
  -- o Lenine (presença sempre) sem lugar: as reservas soltas (o "sem lugar" de verdade); com mais uma pessoa ele cabe, e os meios-dias
  -- são os do trabalho dele, sem os do dono
  begin
    perform pg_temp.carregar('real', 'campo');
    perform pg_temp.modos('ligado', 'ligado');
    v_len := pg_temp.os('OS-00074');
    perform public.agenda_vigiar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:30'));
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where tipo = 'reserva' and estado in ('publicada', 'fixada');
    w := public._agenda_quem_chamar(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:05'));
    c := coalesce((w #> '{capacidade,extra}')::text, '-') || ' | '
         || coalesce((select string_agg(s ->> 'cliente' || ':' || (s ->> 'pm'), ' ') from jsonb_array_elements(w #> '{capacidade,sem_lugar}') s), '-');
    v_pm := (select coalesce(sum((s ->> 'pm')::int), 0) from jsonb_array_elements(w #> '{capacidade,sem_lugar}') s
              where s ->> 'os' in (select o ->> 'os' from jsonb_array_elements(coalesce(w #> '{capacidade,extra,os}', '[]'::jsonb)) o));
    c := c || ' | ' || coalesce(w #>> '{capacidade,extra,meios_total}', '0') || ' <= ' || v_pm;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X11c (achado 19) com o Lenine (o dono "sempre") sem lugar e cabendo com mais uma pessoa, os meios-dias de mais uma pessoa não passam do trabalho das OS que passam a caber (antes, os turnos do dono entravam: o Lenine de 12 pedia 22)',
    (split_part(c, ' | ', 3) = '0 <= 0') or (split_part(split_part(c, ' | ', 3), ' <= ', 1))::int <= (split_part(split_part(c, ' | ', 3), ' <= ', 2))::int,
    c);
  perform pg_temp.gravar(v_res);
end
$x11$;

-- ── X12. O motor: o exemplo com todos os dias e a dupla dita antes de a OS ficar pronta ──────────────────────────
do $x12$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  v_van uuid;
  v     jsonb;
  a     text;
  b     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('X12 (o motor)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  -- o Lenine com a dupla do banco de baterias em 3 meios-dias (ter 10/11 de manhã e de tarde e qua 11/11 de manhã: dois dias): o
  -- exemplo diz os dois
  begin
    perform pg_temp.carregar('real', '');
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.abre_fecha();
    update public.agenda_config set dupla_gatilhos = jsonb_set(dupla_gatilhos, '{0,3}', '3'::jsonb) where id;
    v_len := pg_temp.os('OS-00074');
    v := public.agenda_propor('os', null, null, array[v_len], '{}'::jsonb, false, 'vigia', null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
    a := (select i ->> 'texto' from jsonb_array_elements(v -> 'itens') i where i ->> 'os' = v_len::text and i ->> 'op' = 'criar' limit 1);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X12a (achado 23) o exemplo da dupla de 1 pessoa diz todos os dias em que falta a 2ª pessoa ("ex.: Mateus vem ter 10 e qua 11/11"), não só o 1º',
    a like '%Nos 3 primeiros meios-dias (ter 10/11, manhã e tarde e qua 11/11 de manhã) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem ter 10 e qua 11/11).%',
    a);
  -- o Vanderlei com a dupla dita nos 2 primeiros meios-dias (pronto só depois) e o Mateus só em seg 09 e qui 12/11
  begin
    perform pg_temp.carregar('real', '');
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.abre_fecha();
    v_van := pg_temp.os('OS-00069');
    insert into public.payees (name, kind, active, phone, created_at, updated_at)
    values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-05 10:00-03', timestamptz '2026-11-05 10:00-03');
    insert into public.os_planejamento (service_order_id, dupla_dita, dupla_meios, dupla_motivo, dupla_em)
    values (v_van, 'inicio', 2, 'teste', pg_temp.em(date '2026-11-05', '10:00'))
    on conflict (service_order_id) do update set dupla_dita = 'inicio', dupla_meios = 2;
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
    select pg_temp.pessoa('Mateus'), daterange(d, d, '[]'), null, 'disponivel', 'dono', 'Você disse que vem (sob demanda)', pg_temp.em(date '2026-11-05', '17:01')
      from unnest(array[date '2026-11-09', date '2026-11-12']) d;
    v := public.agenda_propor('os', null, null, array[v_van], '{}'::jsonb, false, 'vigia', null, date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10'));
    b := coalesce((select f ->> 'motivo' || ' | ' || (f ->> 'texto') from jsonb_array_elements(v -> 'fora') f where f ->> 'os' = v_van::text), '-')
         || ' | pronto ' || coalesce(public.os_prontidao(v_van, date '2026-11-05') ->> 'est', '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'X12b (achado 22) a dupla dita que espera, com os dias de quem vem sob demanda todos antes de a OS ficar pronta: o porquê é a data ("…, antes de o serviço ficar pronto (…): me diga dias dele a partir de …"), não a falta de dias',
    b like 'dupla | Vanderlei (OS-00069): precisa de 2 pessoas em 2 meios-dias e Mateus só vem seg 09 e qui 12/11 (4 meios-dias), antes de o serviço ficar pronto (%): me diga dias dele a partir de % ou chame outro ajudante. | pronto %'
    or b like '- | pronto %',
    b);
  perform pg_temp.gravar(v_res);
end
$x12$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
