-- Prova do atalho "agenda do mês" (migration 20270213100000_agenda_periodo_mes.sql): _agenda_periodo entende o mês (de hoje ao fim do mês) e o
-- mês que vem (o mês inteiro), no calendário de quem chama (p_hoje), sem mudar nada do que já entendia.
-- bancada: depende de 20270213100000
--
--   P0  a forma e as portas (vale em produção): o corpo vigente sem o bloco "-- AGENDA DO MÊS (20/11):" é a origem byte a byte (md5 sem CR
--       d3593412…, o de produção em 20/11 = 20261024160500:201); anon não executa; authenticated e service_role executam
--   M1  "mes", "este mês", "deste mês", "do mês", "agenda do mês" sem o "agenda" (o que o comando manda: mes) → de hoje (sex 20/11) a seg 30/11
--   M2  no último dia do mês, só hoje (a rota dia); fevereiro comum (28) e bissexto (29)
--   M3  "mês que vem", "próximo mês", "proximo_mes" (o comando) → o mês que vem inteiro, inclusive na virada do ano (15/12 → janeiro)
--   M4  o fuso da sessão não muda nada (UTC, Tóquio, Los Angeles)
--   A1  o que já era entendido responde igual: vazio, hoje, amanhã, semana, semana que vem, "30/11"; o incompreensível ainda lança 22007
--   V1  agenda_ver com periodo "mes" responde (ok, rota semana, "De sex 20/11 a seg 30/11"); antes respondia "Não entendi a data"
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_periodo_mes.sql
--   Não grava nada (só lê) e termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.per(p text, p_hoje date) returns text language sql stable as $f$
  select x.de::text || ' a ' || x.ate::text from public._agenda_periodo(p, p_hoje) x
$f$;
-- O corpo sem o bloco do mês (as linhas entre os dois marcadores, inclusive), sem CR.
create function pg_temp.sem_bloco(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, chr(13), ''), E'\n') loop
    if l ~ '^\s*-- AGENDA DO MÊS \(20/11\):' then
      v_dentro := l !~ ': fim\s*$';
      continue;
    end if;
    if not v_dentro then v_fora := v_fora || l; end if;
  end loop;
  return array_to_string(v_fora, E'\n');
end;
$f$;

-- ── P0. A forma e as portas ─────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'P0a sem o bloco do mês, o corpo é o de antes byte a byte',
       md5(pg_temp.sem_bloco(p.prosrc)) = 'd3593412a8964da4ce678aaf544c1886',
       md5(pg_temp.sem_bloco(p.prosrc))
  from pg_proc p where p.oid = 'public._agenda_periodo(text, date)'::regprocedure;

insert into _resultado
select 'P0b o bloco do mês está lá (a migration foi aplicada)',
       position('-- AGENDA DO MÊS (20/11):' in p.prosrc) > 0, null
  from pg_proc p where p.oid = 'public._agenda_periodo(text, date)'::regprocedure;

insert into _resultado
select 'P0c anon não executa; authenticated e service_role executam',
       not has_function_privilege('anon', 'public._agenda_periodo(text, date)', 'execute')
       and has_function_privilege('authenticated', 'public._agenda_periodo(text, date)', 'execute')
       and has_function_privilege('service_role', 'public._agenda_periodo(text, date)', 'execute'),
       null;

-- ── M. O mês ────────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'M1 "' || f || '" em sex 20/11 = de hoje a seg 30/11',
       pg_temp.per(f, date '2026-11-20') = '2026-11-20 a 2026-11-30',
       pg_temp.per(f, date '2026-11-20')
  from unnest(array['mes', 'Mês', 'este mês', 'Este mes', 'deste mês', 'desse mes', 'do mês', 'neste mês', 'o mês', 'mês todo',
                    'até o fim do mês', 'fim do mês']) f;

insert into _resultado
select 'M2a no último dia do mês, só hoje', pg_temp.per('mes', date '2026-11-30') = '2026-11-30 a 2026-11-30', pg_temp.per('mes', date '2026-11-30')
union all
select 'M2b fevereiro comum termina no 28', pg_temp.per('este mes', date '2027-02-10') = '2027-02-10 a 2027-02-28', pg_temp.per('este mes', date '2027-02-10')
union all
select 'M2c fevereiro bissexto termina no 29', pg_temp.per('este mes', date '2028-02-10') = '2028-02-10 a 2028-02-29', pg_temp.per('este mes', date '2028-02-10')
union all
select 'M2d dezembro termina no 31', pg_temp.per('do mes', date '2026-12-01') = '2026-12-01 a 2026-12-31', pg_temp.per('do mes', date '2026-12-01');

insert into _resultado
select 'M3a "' || f || '" em sex 20/11 = 01/12 a 31/12',
       pg_temp.per(f, date '2026-11-20') = '2026-12-01 a 2026-12-31',
       pg_temp.per(f, date '2026-11-20')
  from unnest(array['mês que vem', 'mes que vem', 'próximo mês', 'proximo_mes', 'do mês que vem', 'do próximo mês', 'o mês que vem',
                    'mês seguinte']) f;

insert into _resultado
select 'M3b na virada do ano: 15/12 → janeiro inteiro', pg_temp.per('mes que vem', date '2026-12-15') = '2027-01-01 a 2027-01-31',
       pg_temp.per('mes que vem', date '2026-12-15')
union all
select 'M3c em 31/01 o mês que vem é fevereiro inteiro (28)', pg_temp.per('proximo mes', date '2027-01-31') = '2027-02-01 a 2027-02-28',
       pg_temp.per('proximo mes', date '2027-01-31');

-- ── M4. O fuso da sessão não muda nada ──────────────────────────────────────────────────────────────────
set local timezone = 'UTC';
insert into _resultado select 'M4a UTC', pg_temp.per('mes', date '2026-11-20') || ' | ' || pg_temp.per('mes que vem', date '2026-11-20')
  = '2026-11-20 a 2026-11-30 | 2026-12-01 a 2026-12-31', null;
set local timezone = 'Asia/Tokyo';
insert into _resultado select 'M4b Tóquio', pg_temp.per('mes', date '2026-11-20') || ' | ' || pg_temp.per('mes que vem', date '2026-11-20')
  = '2026-11-20 a 2026-11-30 | 2026-12-01 a 2026-12-31', null;
set local timezone = 'America/Los_Angeles';
insert into _resultado select 'M4c Los Angeles', pg_temp.per('mes', date '2026-11-20') || ' | ' || pg_temp.per('mes que vem', date '2026-11-20')
  = '2026-11-20 a 2026-11-30 | 2026-12-01 a 2026-12-31', null;
set local timezone = 'America/Sao_Paulo';

-- ── A. O que já era entendido responde igual ────────────────────────────────────────────────────────────
insert into _resultado
select 'A1 "' || coalesce(f, '(nulo)') || '" responde como antes',
       coalesce(pg_temp.per(f, date '2026-11-20'), '(nulo)') = esperado,
       coalesce(pg_temp.per(f, date '2026-11-20'), '(nulo)')
  from (values (null::text, '(nulo)'), ('', '(nulo)'), ('hoje', '2026-11-20 a 2026-11-20'), ('amanhã', '2026-11-21 a 2026-11-21'),
               ('semana', '2026-11-16 a 2026-11-21'), ('da semana', '2026-11-16 a 2026-11-21'),
               ('proxima_semana', '2026-11-23 a 2026-11-28'), ('semana que vem', '2026-11-23 a 2026-11-28'),
               ('30/11', '2026-11-30 a 2026-11-30')) t(f, esperado);

do $$
begin
  perform public._agenda_periodo('mes do cachorro louco', date '2026-11-20');
  insert into _resultado values ('A2 o incompreensível ainda lança 22007', false, 'não lançou');
exception when sqlstate '22007' then
  insert into _resultado values ('A2 o incompreensível ainda lança 22007', true, sqlerrm);
end;
$$;

-- ── V. Pela porta de sempre (agenda_ver) ────────────────────────────────────────────────────────────────
insert into _resultado
select 'V1 agenda_ver periodo "mes" responde a partir de hoje até o fim do mês (antes: "Não entendi a data")',
       coalesce((r ->> 'ok')::boolean, false) and r ->> 'texto' like 'De sex 20/11 a seg 30/11%',
       left(r ->> 'texto', 120)
  from (select public.agenda_ver(p_periodo => 'mes', p_hoje => date '2026-11-20') r) x;

insert into _resultado
select 'V2 agenda_ver periodo "proximo_mes" responde o mês que vem',
       coalesce((r ->> 'ok')::boolean, false) and r ->> 'texto' like 'De ter 01/12 a qui 31/12%',
       left(r ->> 'texto', 120)
  from (select public.agenda_ver(p_periodo => 'proximo_mes', p_hoje => date '2026-11-20') r) x;

select teste, ok, detalhe from _resultado order by teste;

rollback;
