-- Prova do feriado do município do local nas duas fontes, Agenda de Produção, Fase 7d (pacote P2; migration 20261107100100; spec-fase7d
-- §5.2, §8.3 e R6.2, R6.3-9).
-- bancada: depende de 20261107100100
--
--   F0  as portas: as 2 funções IMMUTABLE, invoker, com search_path fixo; revoke de public E de anon, provado no catálogo e rodando
--   F1  a paridade com o TS, dia a dia: agenda_feriado_municipal e agenda_feriado_do_local = os JSON gerados de feriados.ts nos 3.652 dias
--   F2  as grafias: as de Balneário Camboriú casam; Camboriú, que é OUTRO município, e o que não é nome de município não casam
--   F3  o que fica fora de propósito: 11/08, Carnaval, Corpus Christi, 28/05, 24/12 e 31/12, em BC, Itajaí e Florianópolis
--   F4  o calendário da HBR não mudou: agenda_feriado = o C1 de antes (110), o corpo é o da Fase 1, 20/07 continua dia útil
--   F5  o da HBR vale em qualquer lugar e vem primeiro; entradas nulas
--   F6  nada de antes muda: a migration só cria as 2, e nenhuma função do motor chama as 2 (até o P3)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, depois de aplicar a migration, com o OK nomeado: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7d_feriados.sql
--   Seguro em produção: só lê e termina em ROLLBACK. F1, F4a, F4b e F6a usam os JSON e a migration como texto e só rodam na bancada (fora
--   dela saem PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- ── F0. As portas ───────────────────────────────────────────────────────────────────────────────────
with f(sig) as (values
  ('public.agenda_feriado_municipal(date, text)'),
  ('public.agenda_feriado_do_local(date, text)'))
insert into _resultado
select 'F0a as 2 funções: IMMUTABLE, invoker, devolvem text, search_path fixo; revoke de public e de anon; authenticated e service_role executam',
       count(p.oid) = 2
       and bool_and(not p.prosecdef and p.provolatile = 'i' and p.prorettype = 'text'::regtype
                    and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'  -- sem o coalesce, o null some no bool_and
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and p.proacl is not null
                    and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
                    and has_function_privilege('authenticated', p.oid, 'execute')
                    and has_function_privilege('service_role', p.oid, 'execute')),
       string_agg(format('%s %s definer=%s anon=%s auth=%s srv=%s', f.sig, p.provolatile, p.prosecdef,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

do $f0$
declare
  v_auth text;
  v_anon_mun text := 'passou';
  v_anon_loc text := 'passou';
begin
  set local role authenticated;
  v_auth := public.agenda_feriado_do_local(date '2027-07-20', 'Balneário Camboriú');
  begin
    set local role anon;
    perform public.agenda_feriado_municipal(date '2027-07-20', 'Balneário Camboriú');
  exception when insufficient_privilege then v_anon_mun := '42501';
  end;
  begin
    set local role anon;
    perform public.agenda_feriado_do_local(date '2027-07-20', 'Balneário Camboriú');
  exception when insufficient_privilege then v_anon_loc := '42501';
  end;
  reset role;
  insert into _resultado values ('F0b rodando: o painel lê (authenticated, invoker: _agenda_normal e agenda_feriado abrem para ele); anon 42501 nas 2',
    v_auth = 'aniversário de Balneário Camboriú' and v_anon_mun = '42501' and v_anon_loc = '42501',
    format('authenticated=%s; anon=%s, %s', v_auth, v_anon_mun, v_anon_loc));
end
$f0$;

-- ── F1. A paridade com o TS: os JSON são gerados de feriados.ts; o deno prova TS = JSON, aqui SQL = JSON ───────────
do $f1$
declare
  v_json jsonb := nullif(current_setting('agenda_teste.feriados_municipais', true), '')::jsonb;
  v_hbr jsonb := nullif(current_setting('agenda_teste.feriados', true), '')::jsonb;
  v_de date;
  v_dias int;
  v_municipios int;
  v_entradas int;
  v_total int; v_dif int; v_primeira text; v_nomes int;
  v_fora text;
begin
  if v_json is null or v_hbr is null then
    insert into _resultado values ('F1 agenda_feriado_municipal = feriados_municipais_2026_2035.json (3.652 dias × municípios do JSON)', true,
      'PULADO: sem o JSON nesta sessão; a paridade roda na bancada (node scripts/bancada-agenda/rodar.mjs)');
    return;
  end if;
  v_de := (v_json ->> 'de')::date;
  v_dias := (v_json ->> 'ate')::date - v_de + 1;
  select count(*), coalesce(sum((select count(*) from jsonb_object_keys(m.dias))), 0) into v_municipios, v_entradas
    from jsonb_each(v_json -> 'municipios') m(municipio, dias);

  -- A comparação de hoje: o que o banco diz em cada dia × o que o JSON diz, nos dois sentidos (dia sem chave no JSON = sem feriado).
  select count(*),
         count(*) filter (where a.banco is distinct from a.arquivo),
         min(a.municipio || ' ' || a.dia) filter (where a.banco is distinct from a.arquivo),
         count(a.banco)
    into v_total, v_dif, v_primeira, v_nomes
    from (select m.municipio, to_char(x.d, 'YYYY-MM-DD') as dia,
                 public.agenda_feriado_municipal(x.d, m.municipio) as banco,
                 m.dias ->> to_char(x.d, 'YYYY-MM-DD') as arquivo
            from jsonb_each(v_json -> 'municipios') m(municipio, dias)
            cross join generate_series(0, v_dias - 1) g(i)
            cross join lateral (select v_de + g.i as d) x) a;
  insert into _resultado values ('F1a agenda_feriado_municipal = feriados_municipais_2026_2035.json (3.652 dias × municípios do JSON)',
    v_dias = 3652 and v_dias = (v_json ->> 'dias')::int and v_municipios >= 1 and v_total = v_dias * v_municipios and v_dif = 0 and v_nomes = v_entradas,
    format('%s dias × %s município(s) = %s comparações, %s feriados no banco, %s no JSON, %s diferentes%s',
           v_dias, v_municipios, v_total, v_nomes, v_entradas, v_dif, coalesce(' (o 1º: ' || v_primeira || ')', '')));

  -- O conteúdo de hoje: 1 município, 10 entradas, uma por ano, todas 20/07, com o nome.
  insert into _resultado
  select 'F1b o JSON: Balneário Camboriú com 10 entradas, uma por ano, todas 20/07 com o mesmo nome',
         v_municipios = 1 and count(*) = 10 and count(distinct left(e.key, 4)) = 10
         and bool_and(substr(e.key, 5) = '-07-20' and e.value = 'aniversário de Balneário Camboriú'),
         format('%s entradas: %s .. %s', count(*), min(e.key), max(e.key))
    from jsonb_each_text(v_json -> 'municipios' -> 'balneario camboriu') e;

  -- agenda_feriado_do_local = o da HBR e, se não houver, o do município, nos mesmos dias; onde o município não tem feriado, só o da HBR.
  select count(*),
         count(*) filter (where a.banco is distinct from a.arquivo),
         min(a.municipio || ' ' || a.dia) filter (where a.banco is distinct from a.arquivo),
         count(a.banco)
    into v_total, v_dif, v_primeira, v_nomes
    from (select l.municipio, to_char(x.d, 'YYYY-MM-DD') as dia,
                 public.agenda_feriado_do_local(x.d, l.municipio) as banco,
                 coalesce(v_hbr -> 'feriados' ->> to_char(x.d, 'YYYY-MM-DD'),
                          v_json -> 'municipios' -> public._agenda_normal(l.municipio) ->> to_char(x.d, 'YYYY-MM-DD')) as arquivo
            from (values ('Balneário Camboriú'), ('Itajaí'), ('Florianópolis')) l(municipio)
            cross join generate_series(0, v_dias - 1) g(i)
            cross join lateral (select v_de + g.i as d) x) a;
  insert into _resultado values ('F1c agenda_feriado_do_local = os 2 JSON nos 3.652 dias, em BC (120), Itajaí (110) e Florianópolis (110)',
    v_total = v_dias * 3 and v_dif = 0 and v_nomes = 340,
    format('%s comparações, %s feriados, %s diferentes%s', v_total, v_nomes, v_dif, coalesce(' (o 1º: ' || v_primeira || ')', '')));

  -- Município fora do JSON nunca tem feriado municipal: a região inteira, mais os de fora que a spec cita. Pega entrada só no SQL.
  select string_agg(distinct l.municipio, ', ') into v_fora
    from (select unnest(c.municipios_locais) as municipio from public.agenda_config c where c.id
          union select unnest(array['Camboriu', 'Florianópolis', 'Porto Belo', 'Itapema', 'Guaratuba', 'Pontal do Paraná', 'Bombinhas'])) l
    cross join generate_series(0, v_dias - 1) g(i)
   where not (v_json -> 'municipios') ? public._agenda_normal(l.municipio)
     and public.agenda_feriado_municipal(v_de + g.i, l.municipio) is not null;
  insert into _resultado values ('F1d nenhum município fora do JSON tem feriado municipal nos 3.652 dias: a região inteira e os de fora que a spec cita',
    v_fora is null, v_fora);
end
$f1$;

-- ── F2. As grafias ──────────────────────────────────────────────────────────────────────────────────
-- A mesma lista de feriados-municipais-paridade_test.ts. As duas primeiras são as de produção (wf7dd_p2_grafias, 05/11).
with g(grafia) as (values
  ('Balneário Camboriú'), ('Balneario Camboriu'), ('BALNEÁRIO CAMBORIÚ'), ('balneário  camboriú'), ('  Balneario-Camboriu. '),
  (normalize('Balneário Camboriú', nfd)))
insert into _resultado
select 'F2a as grafias de Balneário Camboriú casam (as 2 de produção, maiúscula, espaço, pontuação e acento decomposto), nas 2 funções',
       count(*) = 6 and bool_and(coalesce(public.agenda_feriado_municipal(date '2027-07-20', g.grafia) = 'aniversário de Balneário Camboriú'
                                          and public.agenda_feriado_do_local(date '2027-07-20', g.grafia) = 'aniversário de Balneário Camboriú', false)),
       string_agg(g.grafia, ' | ') filter (where public.agenda_feriado_municipal(date '2027-07-20', g.grafia) is null)
  from g;

with g(grafia) as (values
  ('Camboriú'), ('Camboriu'), ('CAMBORIÚ'), ('Balneário'), ('Balneário Camboriú/SC'), ('Balneário/Camboriú'), ('Balneário Camboriú SC'),
  ('Camboriú Balneário'), ('BC'), (''), ('   '))
insert into _resultado
select 'F2b não casam: Camboriú, que é OUTRO município (10 clientes em produção), e o que não é o nome do município',
       count(*) = 11 and bool_and(public.agenda_feriado_municipal(date '2027-07-20', g.grafia) is null
                                  and public.agenda_feriado_do_local(date '2027-07-20', g.grafia) is null),
       string_agg(g.grafia, ' | ') filter (where public.agenda_feriado_municipal(date '2027-07-20', g.grafia) is not null)
  from g;

-- ── F3. O que fica fora de propósito ────────────────────────────────────────────────────────────────
with dias(oque, d) as (
  select 'Carnaval', public.agenda_pascoa(a) - 47 from generate_series(2026, 2035) a
  union all select 'Corpus Christi', public.agenda_pascoa(a) + 60 from generate_series(2026, 2035) a
  union all select '11/08', make_date(a, 8, 11) from generate_series(2026, 2035) a
  union all select '28/05', make_date(a, 5, 28) from generate_series(2026, 2035) a
  union all select '24/12', make_date(a, 12, 24) from generate_series(2026, 2035) a
  union all select '31/12', make_date(a, 12, 31) from generate_series(2026, 2035) a
), m(municipio) as (values ('Balneário Camboriú'), ('Itajaí'), ('Florianópolis')), c as (
  select d.oque, d.d, m.municipio from dias d cross join m
)
insert into _resultado
select 'F3a 11/08, Carnaval, Corpus Christi, 28/05, 24/12 e 31/12: agenda_feriado_municipal nula em BC, Itajaí e Florianópolis, nos 10 anos',
       count(*) = 180 and bool_and(public.agenda_feriado_municipal(c.d, c.municipio) is null),
       string_agg(format('%s %s', c.oque, c.municipio), ', ') filter (where public.agenda_feriado_municipal(c.d, c.municipio) is not null)
  from c
union all
-- Corpus Christi de 2028 cai em 15/06: naquele dia o do local é o da HBR, e só por isso a linha compara com agenda_feriado, não com null.
select 'F3b os mesmos dias em agenda_feriado_do_local: só o da HBR, e o único encontro é o Corpus Christi de 2028, que cai em 15/06',
       count(*) = 180 and bool_and(public.agenda_feriado_do_local(c.d, c.municipio) is not distinct from public.agenda_feriado(c.d))
       and count(*) filter (where public.agenda_feriado_do_local(c.d, c.municipio) is not null) = 3
       and bool_and(public.agenda_feriado_do_local(c.d, c.municipio) is null or (c.d = date '2028-06-15' and c.oque = 'Corpus Christi')),
       string_agg(format('%s %s %s', c.d, c.municipio, public.agenda_feriado_do_local(c.d, c.municipio)), ', ')
         filter (where public.agenda_feriado_do_local(c.d, c.municipio) is not null)
  from c;

insert into _resultado values
  ('F3c os exemplos da spec: 11/08/2026 em Itajaí e Florianópolis; Carnaval, Corpus Christi e 28/05 de 2026 em BC',
   public.agenda_feriado_municipal(date '2026-08-11', 'Itajaí') is null
   and public.agenda_feriado_do_local(date '2026-08-11', 'Florianópolis') is null
   and public.agenda_feriado_do_local(date '2026-02-17', 'Balneário Camboriú') is null
   and public.agenda_feriado_do_local(date '2026-06-04', 'Balneário Camboriú') is null
   and public.agenda_feriado_do_local(date '2026-05-28', 'Balneário Camboriú') is null, null);

-- ── F4. O calendário da HBR não mudou ───────────────────────────────────────────────────────────────
do $f4$
declare
  v_json jsonb := nullif(current_setting('agenda_teste.feriados', true), '')::jsonb;
  v_mig text := nullif(current_setting('agenda_teste.mig_calendario_fase1', true), '');
  v_dias int; v_dif int; v_primeira text; v_feriados int;
begin
  if v_json is null then
    insert into _resultado values ('F4a agenda_feriado = o C1 de antes: feriados_2026_2035.json nos 3.652 dias, 110 feriados', true,
      'PULADO: sem o JSON nesta sessão; a paridade roda na bancada (node scripts/bancada-agenda/rodar.mjs)');
  else
    select count(*),
           count(*) filter (where public.agenda_feriado(x.d) is distinct from v_json -> 'feriados' ->> to_char(x.d, 'YYYY-MM-DD')),
           min(to_char(x.d, 'YYYY-MM-DD')) filter (where public.agenda_feriado(x.d) is distinct from v_json -> 'feriados' ->> to_char(x.d, 'YYYY-MM-DD')),
           count(*) filter (where public.agenda_feriado(x.d) is not null)
      into v_dias, v_dif, v_primeira, v_feriados
      from generate_series(0, (v_json ->> 'ate')::date - (v_json ->> 'de')::date) g(i)
      cross join lateral (select (v_json ->> 'de')::date + g.i as d) x;
    insert into _resultado values ('F4a agenda_feriado = o C1 de antes: feriados_2026_2035.json nos 3.652 dias, 110 feriados',
      v_dias = 3652 and v_dif = 0 and v_feriados = 110 and (select count(*) from jsonb_object_keys(v_json -> 'feriados')) = 110
      and not (v_json -> 'feriados') ? '2027-07-20',
      format('%s dias, %s feriados, %s diferentes%s', v_dias, v_feriados, v_dif, coalesce(' (o 1º: ' || v_primeira || ')', '')));
  end if;

  if v_mig is null then
    insert into _resultado values ('F4b o corpo de agenda_feriado é o da Fase 1, e ninguém o recriou', true, 'PULADO: a migration como texto só existe na bancada');
  else
    insert into _resultado values ('F4b o corpo de agenda_feriado é o da Fase 1, e ninguém o recriou',
      (select position(p.prosrc in v_mig) > 0 and pg_get_function_identity_arguments(p.oid) = 'p_dia date'
         from pg_proc p where p.oid = 'public.agenda_feriado(date)'::regprocedure), null);
  end if;
end
$f4$;

insert into _resultado values
  ('F4c 20/07 continua dia útil para a HBR: agenda_feriado nula, agenda_dia_util e agenda_somar_du como antes; só o local vê',
   public.agenda_feriado(date '2027-07-20') is null
   and public.agenda_dia_util(date '2027-07-20')
   and public.agenda_somar_du(date '2027-07-19', 1) = date '2027-07-20'
   and public.agenda_feriado_do_local(date '2027-07-20', 'Balneário Camboriú') is not null, null);

-- ── F5. O da HBR vale em qualquer lugar ─────────────────────────────────────────────────────────────
insert into _resultado values
  ('F5a agenda_feriado_do_local(2027-06-15, BC) = aniversário de Itajaí: o da HBR vale em qualquer lugar, com ou sem município',
   public.agenda_feriado_do_local(date '2027-06-15', 'Balneário Camboriú') = 'aniversário de Itajaí'
   and public.agenda_feriado_do_local(date '2027-06-15', 'Florianópolis') = 'aniversário de Itajaí'
   and public.agenda_feriado_do_local(date '2027-06-15', null) = 'aniversário de Itajaí'
   and public.agenda_feriado_municipal(date '2027-06-15', 'Balneário Camboriú') is null,
   public.agenda_feriado_do_local(date '2027-06-15', 'Balneário Camboriú')),
  ('F5b 20/07 em BC tem o nome; no dia seguinte e na véspera, nada; em Itajaí, nada',
   public.agenda_feriado_do_local(date '2027-07-20', 'Balneário Camboriú') = 'aniversário de Balneário Camboriú'
   and public.agenda_feriado_do_local(date '2027-07-19', 'Balneário Camboriú') is null
   and public.agenda_feriado_do_local(date '2027-07-21', 'Balneário Camboriú') is null
   and public.agenda_feriado_do_local(date '2027-07-20', 'Itajaí') is null, null),
  ('F5c entrada nula: sem dia ou sem município, null, sem erro',
   public.agenda_feriado_municipal(null, 'Balneário Camboriú') is null
   and public.agenda_feriado_municipal(date '2027-07-20', null) is null
   and public.agenda_feriado_municipal(null, null) is null
   and public.agenda_feriado_do_local(null, 'Balneário Camboriú') is null
   and public.agenda_feriado_do_local(date '2027-07-20', null) is null, null);

-- Hoje nenhum dia tem os dois feriados, então a ordem do coalesce não aparece em nenhum resultado: confere-se pelo texto.
insert into _resultado
select 'F5d o da HBR vem primeiro: a ordem do coalesce, pelo texto (hoje nenhum dia tem os dois)',
       p.prosrc like '%coalesce(public.agenda_feriado(p_dia), public.agenda_feriado_municipal(p_dia, p_municipio))%', null
  from pg_proc p where p.oid = 'public.agenda_feriado_do_local(date, text)'::regprocedure;

-- ── F6. Nada de antes muda ──────────────────────────────────────────────────────────────────────────
do $f6$
declare
  v_mig text := nullif(current_setting('agenda_teste.mig_feriados_fase7d', true), '');
  v_t text;
begin
  if v_mig is null then
    insert into _resultado values ('F6a a migration só cria as 2 funções: nenhuma recriada, nenhuma tabela, nenhum dado', true, 'PULADO: a migration como texto só existe na bancada');
  else
    select string_agg(m[1], ',' order by m[1]) into v_t
      from regexp_matches(regexp_replace(v_mig, '--[^\n]*', '', 'g'),
                          '\m(?:create(?: or replace)? function public\.\w+|alter table|create table|insert into|update public|delete from)', 'gi') a(x)
      cross join lateral (select array[a.x[1]]) b(m);
    insert into _resultado values ('F6a a migration só cria as 2 funções: nenhuma recriada, nenhuma tabela, nenhum dado',
      v_t = 'create or replace function public.agenda_feriado_do_local,create or replace function public.agenda_feriado_municipal', v_t);
  end if;

  -- Nada do motor nem da vigia chama as 2 neste pacote. Vale até a migration de quem passa a chamar: o P3 cria a máscara, e esta linha sai sozinha.
  if not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_agenda_local_mascara') then
    select string_agg(p.proname, ',' order by p.proname) into v_t
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.prosrc ~ '(agenda_feriado_municipal|agenda_feriado_do_local)'
       and p.proname not in ('agenda_feriado_municipal', 'agenda_feriado_do_local');
    insert into _resultado values ('F6b nenhuma função chama as 2 neste pacote: nada no caminho da vigia nem do motor (a linha sai sozinha com a máscara do P3)',
      v_t is null, v_t);
  end if;
end
$f6$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
