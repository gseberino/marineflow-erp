-- Prova do "A OS-X terminou ou falta dia?" (23/11/2026, NOVO-testes-01, opção A do dono; migration 20270223100000_agenda_terminou_falta_dia.sql):
-- a OS em execução com o plano cumprido e sem dia futuro ganha a pergunta concluir terminou:<os> na rotina de 15 min, ela entra no resumo da manhã
-- pelo caminho da Opção A (via 'manha', contada pela fila), "terminou" é o *concluiu* que já existe, *falta dia* devolve a OS ao motor, e
-- agenda_saude().gestor.aprovada_sem_data enxerga a pergunta aberta também por os_ids.
-- bancada: depende de 20270223100000
--
--   P0  a forma e as portas (vale em produção): as 4 novas (definer/invoker, volatilidade, search_path, quem executa: as internas ninguém de fora; a
--       palavra authenticated e service_role, nunca anon); as 3 recriadas sem os blocos "-- TERMINOU:" (devolvidas as "--antes:") = os corpos de
--       produção de 23/11 (md5 sem CR); nenhum UPDATE/DELETE sem WHERE (pg_safeupdate)
--   P1  as recusas (vale em produção, nada grava): sem o dia ou a hora (22004); a palavra sem o administrador (42501) e com canal errado (22023)
--   A1  (fixture-fase5) Flávio (OS-00104, ter 03 e qua 04/11) passa a in_progress: qui 05/11 ele entra (último dia 04/11); qua 04/11 não (tem dia
--       hoje); com a OS agendada (scheduled) não
--   A2  a rotina (passo conclusao) abre 1 pergunta: concluir, terminou:<os>, ligado, a OS em service_order_id e os_ids, dia 04/11, sem prazo, sem
--       opções, não crítica, o texto combinado; o 2º tique não abre outra; com o motor em teste não abre
--   A3  a manhã: sem mensagem ao cliente (modo_cliente desligado) o bloco é "🔧 " + o texto e a pergunta vai em linhas[]; o registro via 'manha'
--       conta 1 vez e nada é decidido (a pergunta continua aberta, sem prazo)
--   A4  a saúde: com o encaixe ligado, a OS com a "terminou?" aberta não conta em aprovada_sem_data; só com a conferência (os_ids) também não; sem
--       pergunta nenhuma, conta
--   A5  *falta dia Flávio*: o 04/11 dele vira "em parte (estimativa)", o motor volta a ter o que encaixar e a pergunta fica respondida; o próximo
--       tique não reabre (a OS tem dia ou o que encaixar); *falta dia* sem pergunta aberta = "nenhuma", nada muda
--   A6  a pergunta fecha sozinha quando a OS volta a ter dia no plano e quando sai de em andamento
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_terminou_falta_dia.sql
--   Sem as fixtures (produção) A sai PULADO; P0 e P1 rodam e não gravam nada. Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
-- A hora de Brasília escrita como se fala: pg_temp.em('2026-11-05 07:30') = timestamptz '2026-11-05 07:30-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;
-- O corpo (prosrc, sem CR) de uma função pela assinatura.
create function pg_temp.src(p_assinatura text) returns text language sql stable as $f$
  select replace(p.prosrc, chr(13), '') from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os blocos "-- TERMINOU: … -- TERMINOU: fim", devolvendo as linhas "--antes:" de dentro deles: o corpo de antes. (Pacote 1 do
-- assistente, A3, 20270301120200: e os "-- P1 AGENDA: … -- P1 AGENDA: fim", pela mesma convenção; _agenda_rotina_conclusao ganhou 3 deles.)
create function pg_temp.sem_terminou(p text) returns text language sql immutable as $st$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ '^\s*-- (TERMINOU|P1 AGENDA):' and l !~ '^\s*-- (TERMINOU|P1 AGENDA): fim' then 1
                                         when l ~ '^\s*-- (TERMINOU|P1 AGENDA): fim' then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ '^\s*-- (TERMINOU|P1 AGENDA): fim' as fecha
                     from unnest(string_to_array(replace(p, chr(13), ''), E'\n')) with ordinality u(l, o)) x
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
$st$;
-- A porta de uma função: "definer volatilidade | anon authenticated service_role public" (EXECUTE; t ou f).
create function pg_temp.porta(p_assinatura text) returns text language sql stable as $f$
  select format('%s %s | %s %s %s %s', p.prosecdef, p.provolatile, has_function_privilege('anon', p.oid, 'execute'),
                has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute'),
                coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'), false))
    from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- UPDATE/DELETE sem WHERE no nível de cima (o detector da 20261112300000, resumido: sem comentários nem strings).
create function pg_temp.sem_where(p_corpo text) returns setof text language sql immutable as $f$
  with c as (
    select regexp_replace(regexp_replace(p_corpo, '--[^\n]*', '', 'g'), '''(?:[^'']|'''')*''', '''''', 'g') as corpo
  )
  select btrim(regexp_replace(m[1], '\s+', ' ', 'g'))
    from c, regexp_matches(c.corpo, '(?<![a-z0-9_.])((?:update|delete\s+from)\s+(?:only\s+)?(?!(?:set|of|on|or|loop|skip|nowait)\M)(?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*\M[^;]*)', 'gi') as m
   where m[1] !~* '\mwhere\M'
$f$;

-- ── P0. A forma e as portas ──────────────────────────────────────────────────────────────────────────────────────────────────────────
do $p0$
declare
  v_res jsonb := '[]'::jsonb;
  r     record;
begin
  for r in select * from (values
      ('public._agenda_terminou_candidatas(date)', 'f s | f f f f'),
      ('public._agenda_terminou_rodar(date,timestamptz)', 'f v | f f f f'),
      ('public._agenda_terminou_da_manha(jsonb,date,timestamptz)', 'f s | f f f f'),
      ('public.agenda_falta_dia_dito(uuid,text,text,date,timestamptz)', 't v | f t t f'),
      ('public.agenda_aprovacoes_da_manha(date,timestamptz)', 't s | f f t f'),
      ('public._agenda_rotina_conclusao(date,timestamptz)', 'f v | f f f f')
    ) x(f, porta)
  loop
    v_res := pg_temp.ok(v_res, format('P0a %s: a porta (definer, volatilidade | anon authenticated service_role public) e search_path=public', r.f),
      pg_temp.porta(r.f) = r.porta
      and exists (select 1 from pg_proc p, unnest(p.proconfig) c where p.oid = to_regprocedure(r.f) and replace(c, '"', '') = 'search_path=public'),
      coalesce(pg_temp.porta(r.f), 'NÃO EXISTE') || ' config '
      || coalesce((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure(r.f)), '-'));
    v_res := pg_temp.ok(v_res, format('P0b %s: nenhum UPDATE/DELETE sem WHERE (pg_safeupdate)', r.f),
      not exists (select 1 from pg_temp.sem_where(coalesce(pg_temp.src(r.f), ''))),
      (select string_agg(x, ' | ') from pg_temp.sem_where(coalesce(pg_temp.src(r.f), '')) x));
  end loop;
  -- as 3 recriadas, tirados os blocos "-- TERMINOU:" (e devolvidas as linhas "--antes:"), são as de produção de 23/11, byte a byte
  for r in select * from (values
      ('public.agenda_aprovacoes_da_manha(date,timestamptz)', '2b1ce097e178e73c5668fad5b44298e0'),
      ('public._agenda_rotina_conclusao(date,timestamptz)', 'ff5397d86f0ae999dda0b3f74a730170'),
      ('public.agenda_saude(date,timestamptz)', 'cd5841fef06b30a0e0802c9aabc232eb')
    ) x(f, m)
  loop
    v_res := pg_temp.ok(v_res, format('P0c %s sem os blocos TERMINOU = o corpo de produção de 23/11 (md5 sem CR %s…)', r.f, left(r.m, 8)),
      md5(pg_temp.sem_terminou(pg_temp.src(r.f))) = r.m and pg_temp.src(r.f) like '%-- TERMINOU:%',
      md5(pg_temp.sem_terminou(coalesce(pg_temp.src(r.f), ''))));
  end loop;
  v_res := pg_temp.ok(v_res, 'P0d o tipo concluir continua no CHECK de agenda_perguntas (nenhum tipo novo)',
    exists (select 1 from pg_constraint c where c.conrelid = 'public.agenda_perguntas'::regclass and c.conname = 'agenda_perguntas_tipo_check'
             and pg_get_constraintdef(c.oid) like '%''concluir''::text%'), null);
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── P1. As recusas (nada grava) ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $p1$
declare
  v_res jsonb := '[]'::jsonb;
  v_err text := '';
begin
  begin
    perform public._agenda_terminou_rodar(null, now());
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  begin
    perform public._agenda_terminou_da_manha('{}'::jsonb, current_date, null);
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  begin
    perform public.agenda_falta_dia_dito(null, 'Jorge', 'whatsapp', current_date, now());
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  begin
    perform public.agenda_falta_dia_dito((select u.id from public.app_users u where u.role = 'admin' and u.active order by u.created_at, u.id limit 1),
                                         'Jorge', 'sms', current_date, now());
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  v_res := pg_temp.ok(v_res, 'P1 as recusas: sem a hora (22004, 22004); a palavra sem o administrador (42501) e com canal errado (22023)',
    v_err = '22004;22004;42501;22023;', v_err);
  perform pg_temp.gravar(v_res);
end
$p1$;

-- ── A. A OS do Flávio com o plano cumprido (a fixture-fase5) ─────────────────────────────────────────────────────────────────────────
do $a$
declare
  v_res   jsonb := '[]'::jsonb;
  c_dono  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_os    constant uuid := '05000000-0000-4000-8000-000000000104';
  c_qui   constant date := date '2026-11-05';
  c_texto constant text := 'A OS-00104 (Flávio) terminou ou falta dia? Responda *concluiu OS-00104* ou *falta dia OS-00104*.';
  q       public.agenda_perguntas;
  r       jsonb;
  r1      jsonb;
  v_n     int;
  v_n1    int;
  v_fut   int;
  v_txt   text;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('A1–A6 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase5');
  perform set_config('agenda_teste.hoje', c_qui::text, true);
  -- o Flávio começou (a porta é o caminho de produção; aqui, o status direto, como as fixtures fazem)
  perform set_config('agenda.porta', 'on', true);
  update public.service_orders set status = 'in_progress' where id = c_os;
  perform set_config('agenda.porta', 'off', true);

  -- ── A1. Quem entra ──
  v_n := (select count(*) from public._agenda_terminou_candidatas(c_qui) x where x.service_order_id = c_os);
  v_txt := (select string_agg(x.numero || ' ' || x.curto || ' ' || x.ultimo_dia, ', ') from public._agenda_terminou_candidatas(c_qui) x);
  v_res := pg_temp.ok(v_res, 'A1a qui 05/11: Flávio (in_progress, ter 03 e qua 04/11, nada de hoje em diante, o plano cumprido) entra, último dia 04/11; só ele',
    v_n = 1 and v_txt = 'OS-00104 Flávio 2026-11-04', coalesce(v_txt, '(nenhuma)')
    || ' | passos ' || coalesce(public.agenda_meios_da_os(c_os, c_qui) ->> 'passos', '-'));
  v_res := pg_temp.ok(v_res, 'A1b qua 04/11 (o dia dele é hoje) não entra',
    not exists (select 1 from public._agenda_terminou_candidatas(c_qui - 1) x where x.service_order_id = c_os), null);
  begin
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'scheduled' where id = c_os;
    perform set_config('agenda.porta', 'off', true);
    v_res := pg_temp.ok(v_res, 'A1c a OS agendada (scheduled) não entra: só em execução de verdade',
      not exists (select 1 from public._agenda_terminou_candidatas(c_qui) x where x.service_order_id = c_os), null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A2. A rotina abre a pergunta ──
  begin
    update public.agenda_config set modo_proposta = 'sombra' where id;
    r := public._agenda_rotina_conclusao(c_qui, pg_temp.em('2026-11-05 00:15'));
    v_res := pg_temp.ok(v_res, 'A2a com o motor em teste a rotina não abre a pergunta',
      (r #>> '{terminou,abertas}')::int = 0
      and not exists (select 1 from public.agenda_perguntas x where x.chave = 'terminou:' || c_os), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  r := public._agenda_rotina_conclusao(c_qui, pg_temp.em('2026-11-05 00:15'));
  select * into q from public.agenda_perguntas x where x.chave = 'terminou:' || c_os and x.estado = 'aberta';
  v_res := pg_temp.ok(v_res, 'A2b a rotina (passo conclusao) abre 1 pergunta: concluir, terminou:<os>, ligado, a OS em service_order_id e os_ids, dia 04/11, sem prazo, sem opções, não crítica',
    (r #>> '{terminou,abertas}')::int = 1 and (r ->> 'concluidas')::int = 0 and q.id is not null and q.tipo = 'concluir' and q.modo = 'ligado'
    and q.service_order_id = c_os and q.os_ids = array[c_os] and q.dia = date '2026-11-04' and q.expira_em is null and q.veto_ate is null
    and q.opcao_padrao is null and q.opcoes = '[]'::jsonb and not coalesce(q.critica, false) and q.payee_id is null and q.mostrada_vezes = 0,
    r::text || ' | ' || coalesce(to_jsonb(q)::text, '(sem pergunta)'));
  v_res := pg_temp.ok(v_res, 'A2c o texto combinado: "A OS-00104 (Flávio) terminou ou falta dia? Responda *concluiu OS-00104* ou *falta dia OS-00104*."',
    q.texto = c_texto, q.texto);
  r1 := public._agenda_rotina_conclusao(c_qui, pg_temp.em('2026-11-05 00:30'));
  v_res := pg_temp.ok(v_res, 'A2d o 2º tique não abre outra nem fecha a de agora (1 por OS)',
    (r1 #>> '{terminou,abertas}')::int = 0 and (r1 #>> '{terminou,fechadas}')::int = 0
    and (select count(*) from public.agenda_perguntas x where x.chave = 'terminou:' || c_os) = 1, r1::text);

  -- ── A3. A manhã ──
  r := public.agenda_aprovacoes_da_manha(c_qui, pg_temp.em('2026-11-05 07:30'));
  v_res := pg_temp.ok(v_res, 'A3a a manhã sem mensagem ao cliente (modo_cliente desligado): o bloco "🔧 " + o texto, a pergunta em linhas[], total do cliente 0',
    r ->> 'texto' = '🔧 ' || c_texto and jsonb_array_length(r -> 'linhas') = 1 and r #>> '{linhas,0,pergunta_id}' = q.id::text
    and (r ->> 'total')::int = 0 and (r #>> '{terminou,total}')::int = 1, r::text);
  r := public._agenda_terminou_da_manha(jsonb_build_object('total', 2, 'texto', '📨 bloco do cliente',
         'linhas', jsonb_build_array(jsonb_build_object('pergunta_id', gen_random_uuid()), jsonb_build_object('pergunta_id', gen_random_uuid()))),
         c_qui, pg_temp.em('2026-11-05 07:30'));
  v_res := pg_temp.ok(v_res, 'A3b com o bloco do cliente: ele fica em cima, uma linha em branco, e o "terminou?" embaixo; as linhas do cliente primeiro',
    r ->> 'texto' = '📨 bloco do cliente' || E'\n\n' || '🔧 ' || c_texto and jsonb_array_length(r -> 'linhas') = 3
    and r #>> '{linhas,2,pergunta_id}' = q.id::text and (r ->> 'total')::int = 2, r::text);
  r := public._agenda_terminou_da_manha(jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null), c_qui, pg_temp.em('2026-11-05 00:10'));
  v_res := pg_temp.ok(v_res, 'A3c antes de a pergunta nascer, nada (o que veio, como veio)',
    r = jsonb_build_object('total', 0, 'linhas', '[]'::jsonb, 'texto', null), r::text);
  r := public.agenda_fechamento_registrar(c_qui, jsonb_build_array(jsonb_build_object('pergunta_id', q.id, 'acao_ids', '[]'::jsonb)), 'manha',
                                          pg_temp.em('2026-11-05 07:31'));
  select * into q from public.agenda_perguntas x where x.id = q.id;
  v_res := pg_temp.ok(v_res, 'A3d a manhã que saiu conta 1 vez (via manha) e nada é decidido: a pergunta continua aberta, sem prazo',
    (r ->> 'perguntas')::int = 1 and q.mostrada_vezes = 1 and q.mostrada_via = 'manha' and q.estado = 'aberta' and q.veto_ate is null
    and q.expira_em is null, r::text || ' | ' || to_jsonb(q)::text);
  r := public.agenda_aprovacoes_da_manha(c_qui + 1, pg_temp.em('2026-11-06 07:30'));
  v_res := pg_temp.ok(v_res, 'A3e sem resposta, ela volta na manhã seguinte',
    r ->> 'texto' = '🔧 ' || c_texto, r::text);

  -- ── A4. A saúde ──
  begin
    update public.agenda_config set modo_encaixe_aprovacao = 'ligado', gestor_so_propor = false where id;
    update public.service_orders set converted_to_os_at = pg_temp.em('2026-10-20 10:00') where id = c_os and converted_to_os_at is null;
    v_n := (public.agenda_saude(c_qui, pg_temp.em('2026-11-05 10:00')) #>> '{gestor,aprovada_sem_data}')::int;
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = q.id;
    v_n1 := (public.agenda_saude(c_qui, pg_temp.em('2026-11-05 10:00')) #>> '{gestor,aprovada_sem_data}')::int;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, texto, modo, criada_em)
    values ('conferencia', 'conferencia:2026-11-04:teste', null, array[c_os], date '2026-11-04', 'Agenda de hoje: Flávio. Foi isso?', 'ligado',
            pg_temp.em('2026-11-04 13:00'));
    v_fut := (public.agenda_saude(c_qui, pg_temp.em('2026-11-05 10:00')) #>> '{gestor,aprovada_sem_data}')::int;
    v_res := pg_temp.ok(v_res, 'A4 aprovada_sem_data (encaixe ligado): com a "terminou?" aberta o Flávio não conta; sem pergunta, conta (+1); só com a conferência (os_ids), não conta',
      v_n1 = v_n + 1 and v_fut = v_n, format('com a pergunta %s, sem %s, só a conferência %s', v_n, v_n1, v_fut));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A5. *falta dia* ──
  begin
    r := public.agenda_falta_dia_dito(c_dono, 'Flávio', 'whatsapp', c_qui, pg_temp.em('2026-11-05 08:00'));
    select * into q from public.agenda_perguntas x where x.id = q.id;
    v_fut := (select count(*) from public.agenda_alocacoes a where a.service_order_id = c_os and a.estado in ('publicada', 'fixada')
               and a.dia >= c_qui and a.resultado is null);
    v_res := pg_temp.ok(v_res, 'A5a *falta dia Flávio*: o 04/11 dele vira "em parte (estimativa)", a pergunta fica respondida (whatsapp, pelo dono) e o motor volta a ter o que encaixar',
      (r ->> 'ok')::boolean and r ->> 'status' = 'ok' and (r ->> 'pergunta')::int = 1
      and q.estado = 'respondida' and q.respondida_via = 'whatsapp' and q.respondida_por = c_dono and q.resposta = 'falta dia Flávio'
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = c_os and a.dia = date '2026-11-04'
                        and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                        and (a.resultado is distinct from 'parcial' or a.motivo is distinct from 'estimativa'))
      and (v_fut > 0 or coalesce((public.agenda_meios_da_os(c_os, c_qui) ->> 'passos')::int, 0) > 0),
      format('%s | dias de hoje em diante %s | passos %s', r ->> 'texto', v_fut, public.agenda_meios_da_os(c_os, c_qui) ->> 'passos'));
    v_res := pg_temp.ok(v_res, 'A5b o texto: o "Anotado" do banco e a dica de dizer quantos dias, sem nenhuma palavra de sistema',
      r ->> 'texto' like 'Anotado, %Flávio (OS-00104)%em parte (estimativa)%' and r ->> 'texto' like '%Se faltar mais de meio dia, diga quantos (ex.: "Flávio precisa de mais 2 dias").'
      and r ->> 'texto' !~* 'rpc|erro|função|null', r ->> 'texto');
    r1 := public._agenda_rotina_conclusao(c_qui, pg_temp.em('2026-11-05 08:15'));
    v_res := pg_temp.ok(v_res, 'A5c o tique seguinte não reabre a pergunta (a OS tem dia ou o que encaixar)',
      (r1 #>> '{terminou,abertas}')::int = 0
      and not exists (select 1 from public.agenda_perguntas x where x.chave = 'terminou:' || c_os and x.estado = 'aberta'), r1::text);
    r := public.agenda_falta_dia_dito(c_dono, null, 'whatsapp', c_qui, pg_temp.em('2026-11-05 08:20'));
    v_res := pg_temp.ok(v_res, 'A5d *falta dia* sem pergunta aberta: "nenhuma", nada muda',
      not (r ->> 'ok')::boolean and r ->> 'status' = 'nenhuma' and not (r ->> 'mudou')::boolean, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A6. Fecha sozinha ──
  begin
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select a.service_order_id, a.payee_id, date '2026-11-09', a.turno, a.presenca, a.tipo, 'publicada', 'dono', pg_temp.em('2026-11-05 09:00')
      from public.agenda_alocacoes a
     where a.service_order_id = c_os and a.dia = date '2026-11-04' and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
     order by a.id limit 1;
    r := public._agenda_rotina_conclusao(c_qui, pg_temp.em('2026-11-05 09:15'));
    select * into q from public.agenda_perguntas x where x.id = q.id;
    v_res := pg_temp.ok(v_res, 'A6a a OS voltou a ter dia no plano: a pergunta fecha (resolvida, com o motivo)',
      (r #>> '{terminou,fechadas}')::int = 1 and q.estado = 'resolvida' and q.resolvida_motivo = 'a OS voltou a ter dia no plano',
      r::text || ' | ' || q.estado || ' ' || coalesce(q.resolvida_motivo, ''));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'awaiting_parts' where id = c_os;
    perform set_config('agenda.porta', 'off', true);
    r := public._agenda_rotina_conclusao(c_qui, pg_temp.em('2026-11-05 09:15'));
    select * into q from public.agenda_perguntas x where x.id = q.id;
    v_res := pg_temp.ok(v_res, 'A6b a OS saiu de em andamento: a pergunta fecha, e a manhã não a mostra mais',
      q.estado = 'resolvida' and q.resolvida_motivo = 'a OS não está mais em andamento'
      and public.agenda_aprovacoes_da_manha(c_qui + 1, pg_temp.em('2026-11-06 07:30')) ->> 'texto' is null,
      r::text || ' | ' || q.estado || ' ' || coalesce(q.resolvida_motivo, ''));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$a$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
