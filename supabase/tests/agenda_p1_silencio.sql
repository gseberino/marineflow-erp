-- Prova do A2 do pacote 1 do assistente (decisão do dono de 24/11/2026; migration 20270301120300_agenda_p1_silencio_mantem.sql): com
-- agenda_config.equipe_silencio_acao = 'manter', o silêncio das 9h não tira o dia do técnico; avisa o dono (o acorde) e pede de novo ao técnico
-- (no máximo 1 por pessoa e dia, em todo dia de silêncio). Com 'tirar' (o padrão), o de antes. E os 2 consertos (20270301120310_agenda_p1_
-- silencio_consertos.sql): (A) o acorde do silêncio que manteve o dia fica fora da cota acordes_dia_max em agenda_rotina_rodar; (B) o "ok" puro
-- ao "como foi" num dia que não é o último do plano não abre a pergunta "disse que terminou… mas o plano tinha mais N dias" (com qualquer chave).
-- bancada: depende de 20270301120310
--
--   P0  a forma (vale em produção, nada grava): as portas das 4 recriadas (silêncio, acordes e conclusão invoker, ninguém de fora: anon,
--       authenticated, service_role e PUBLIC sem EXECUTE; a rodada definer, só service_role); nenhum UPDATE/DELETE sem WHERE; tirados os
--       blocos "-- P1 AGENDA: (A2", cada corpo é o de antes (md5 do corpo sem CR: silêncio 3fd0c50d…, acordes ae015c82…, os de produção de
--       24/11; conclusão 3fcde03f…, o da 20270301120200, em produção desde 26/11; rodada c418e862…, a de produção); o ramo novo só com
--       'manter', e ele não chama o replano nem grava disponibilidade; a chave nasce 'tirar'; os comentários ganharam o trecho do A2
--   Sobre a fixture-fase3 (o Roberto, telefone sintético 5547900000001, no Vanderlei, OS-00069, de ter 03 a qui 05/11 o dia todo; o Gustavo,
--   o dono, abre e fecha), a confirmação das 07:45 "saída" às 07:46:
--   S1  'tirar' (o padrão): o de hoje — indisponível, replano, a confirmação sem_resposta, o acorde "Mudei a agenda de hoje", nenhum 2º pedido
--   S2  'manter', 09:00 sem resposta: nenhuma disponibilidade nova, nenhum replano, as alocações intactas; 1 ação silencio_manteve com o texto
--       exato (1ª variante, "Pedi de novo a ele."); 1 resposta enfileirada de chave agenda-equipe:resposta:<pessoa>:reconfirmar:<dia> com o
--       texto exato e a fila; a confirmação continua enfileirada. S2b sem dia dele no plano de hoje: nada. S2c com mensagem dele depois do
--       envio: nada (não é silêncio, como antes)
--   S3  o tique das 09:15: nada novo (nem ação, nem mensagem, nem acorde)
--   S4  "ok" às 10:00: responde à confirmação (respondida, disponibilidade confirmada), não ao 2º pedido nem ao "como foi"
--   S5  "não vou" às 10:00: o caminho de hoje (indisponível, replano, a ação nao_vou com acorde "avisou que não vem"); S5c (conserto A) com o
--       acorde das 9h já contado, o do "não vou" sai no mesmo dia (o do silêncio não gasta a cota acordes_dia_max = 1)
--   S6  17:00: o "como foi" sai (1 proativa antes dele) e leva a ficha de amanhã; 19:30 nada; no dia, 3 mensagens à equipe (confirmação,
--       2º pedido, "como foi"); 22:00 a confirmação vira sem_resposta e o 2º pedido fica como está
--   S7  (decisão de 26/11: a regra "não pede de novo se ontem também ficou sem resposta" saiu) ontem com 2º pedido e sem resposta: hoje sai
--       outro 2º pedido, 1 só
--   S8  sem telefone: o 2º pedido recusado (sem_telefone) e o texto na 2ª variante ("Não consegui pedir de novo."); S8b no teto de respostas
--       (4 no dia): recusado (teto), 2ª variante; S8c a ficha do dia segurada (_agenda_ficha_liberada falso): não pede, 2ª variante; S8d o
--       registro que dá erro: o aviso ao dono sai (2ª variante) e o erro vai para app_error_logs
--   S9  o acorde de _agenda_rotina_acordes_da_equipe sai com o texto da ação inteiro, marca a própria ação e, contado, não volta
--   S10 duas manhãs seguidas de silêncio com 'manter' (a fixture; o replay das manhãs reais de 18/11 e 24/11 não existe na bancada): 0 meios-dias
--       tirados, 2 segundos pedidos, 2 acordes, 2 "como foi"
--   C   (crítica de risco) o "ok" que chega DEPOIS do "como foi" das 17:00 responde ao "como foi" ("tudo como o previsto e terminou"): no último
--       dia do plano, com o A3 no ar (equipe_terminei_conclui = false), vira a pergunta "terminou ou falta dia?" ao dono e a OS NÃO conclui;
--       C0 o mesmo "ok" às 10:00 responde à confirmação e não vira pergunta; C2 o controle: com equipe_terminei_conclui = true, a OS concluiria
--       (por isso ligar só com o A3 no ar)
--   S11 (conserto A) um acorde que já saiu antes das 9h e o silêncio com 'manter': os dois saem no dia (o do silêncio não é cortado pela cota);
--       S11b o controle: com 'tirar', o acorde do silêncio (o replano) é cortado pela cota como antes
--   B   (conserto B, com a chave no padrão 'tirar': vale com qualquer chave) na qua 04/11, que não é o último dia: B1 o "ok" puro (e B1b o "tudo
--       certo", também tipo ok) ao "como foi" não abre pergunta nenhuma, nem nos tiques seguintes, e a diária e os meios-dias ficam como hoje
--       (lançada, cumpridos); B2 o "ok, terminei" e B2b o "terminei" seguem com a pergunta de hoje; B3 o último dia (qui 05/11) com o "ok" puro
--       é o do A3 (a pergunta "respondeu *ok*", a OS não conclui); B4 o último dia do PLANO com a estimativa sobrando (sem dia depois): o "ok"
--       puro segue com a pergunta de hoje ("… mas o plano tinha mais serviço do que você disse"), como o A3 o deixou
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_p1_silencio.sql
--   Sem a fixture (produção) S e C saem PULADO; P0 roda e não grava nada. Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O corpo (prosrc, sem CR) de uma função pela assinatura.
create function pg_temp.src(p_assinatura text) returns text language sql stable as $f$
  select replace(p.prosrc, chr(13), '') from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os blocos "-- <marca>: … -- <marca>: fim" (p_marca é uma alternância de regex), devolvendo as linhas "--antes:" de dentro deles: o
-- corpo de antes (o mesmo removedor de agenda_p1_terminei.sql).
create function pg_temp.sem_blocos(p text, p_marca text) returns text language sql immutable as $st$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ ('^\s*-- (' || p_marca || '):') and l !~ ('^\s*-- (' || p_marca || '): fim') then 1
                                         when l ~ ('^\s*-- (' || p_marca || '): fim') then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ ('^\s*-- (' || p_marca || '): fim') as fecha
                     from unnest(string_to_array(replace(p, chr(13), ''), E'\n')) with ordinality u(l, o)) x
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
$st$;
-- Só o que está DENTRO dos blocos "-- P1 AGENDA:" (as linhas de abrir e de fechar incluídas).
create function pg_temp.so_blocos(p text) returns text language sql immutable as $st$
  select array_to_string(array(
           select l
             from (select l, o, sum(case when l ~ '^\s*-- P1 AGENDA:' and l !~ '^\s*-- P1 AGENDA: fim' then 1
                                         when l ~ '^\s*-- P1 AGENDA: fim' then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ '^\s*-- P1 AGENDA: fim' as fecha
                     from unnest(string_to_array(replace(p, chr(13), ''), E'\n')) with ordinality u(l, o)) x
            where dentro > 0 or fecha
            order by o), E'\n')
$st$;
-- Tira só os blocos do A2 ("-- P1 AGENDA: (A2, …" até o "-- P1 AGENDA: fim" seguinte), devolvendo as linhas "--antes:" de dentro deles; os
-- outros blocos "-- P1 AGENDA:" (os do A3 em _agenda_rotina_conclusao) ficam. Os blocos do A2 não se aninham em outros.
create function pg_temp.sem_a2(p text) returns text language plpgsql immutable as $st$
declare
  l      text;
  fora   text[] := '{}';
  dentro boolean := false;
begin
  foreach l in array string_to_array(replace(p, chr(13), ''), E'\n') loop
    if not dentro and l ~ '^\s*-- P1 AGENDA: \(A2,' then dentro := true; continue; end if;
    if dentro then
      if l ~ '^\s*-- P1 AGENDA: fim' then dentro := false;
      elsif l ~ '^--antes:' then fora := fora || substr(l, 9);
      end if;
      continue;
    end if;
    fora := fora || l;
  end loop;
  return array_to_string(fora, E'\n');
end $st$;
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
-- A rotina inteira (o passo inteiro), a resposta do Roberto (o telefone sintético da fixture-fase3) e o worker que manda (as linhas da fila
-- agenda-equipe pendentes até a hora dada saem: na bancada ninguém manda).
create function pg_temp.rodar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_rotina_rodar(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
create function pg_temp.resp(p_texto text, p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_resposta_da_equipe('5547900000001', p_texto, md5(p_texto || p_dia || p_hora), pg_temp.em(p_dia, p_hora))
$f$;
create function pg_temp.saiu(p_dia date, p_hora text) returns void language sql as $f$
  update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(p_dia, p_hora)
   where source = 'agenda-equipe' and status = 'pending' and scheduled_for <= pg_temp.em(p_dia, p_hora)
$f$;
-- A ação equipe de um motivo, da pessoa, no dia (a mais nova).
create function pg_temp.acao(p_payee uuid, p_dia date, p_motivo text) returns public.agenda_acoes language sql stable as $f$
  select * from public.agenda_acoes e
   where e.tipo = 'equipe' and e.payee_id = p_payee and e.dia = p_dia and e.depois ->> 'motivo' = p_motivo
   order by e.criada_em desc, e.id desc limit 1
$f$;
-- O 2º pedido da pessoa no dia (pela chave).
create function pg_temp.pedido(p_payee uuid, p_dia date) returns public.agenda_equipe_mensagens language sql stable as $f$
  select * from public.agenda_equipe_mensagens r where r.dedupe_key = format('agenda-equipe:resposta:%s:reconfirmar:%s', p_payee, p_dia)
$f$;
-- A mensagem de um tipo da pessoa no dia (a mais nova).
create function pg_temp.msg(p_payee uuid, p_tipo text, p_dia date) returns public.agenda_equipe_mensagens language sql stable as $f$
  select * from public.agenda_equipe_mensagens where payee_id = p_payee and tipo = p_tipo and dia = p_dia order by criada_em desc, id desc limit 1
$f$;
-- As alocações vigentes da pessoa de um dia em diante ("dia turno OS", em ordem): a prova de que o plano não mudou.
create function pg_temp.plano(p_payee uuid, p_de date) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s %s %s', a.dia, a.turno, a.service_order_id), ', ' order by a.dia, a.turno, a.service_order_id), '(nada)')
    from public.agenda_alocacoes a
   where a.payee_id = p_payee and a.dia >= p_de and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
$f$;
-- O acorde ao dono pelo envio de sempre (o task-automations, que a bancada não roda): a ação contada pelo acorde.
create function pg_temp.acordou(p_acao uuid, p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_acorde_registrado(p_acao, null, true, pg_temp.em(p_dia, p_hora))
$f$;

-- ── P0. A forma (vale em produção; nada grava) ───────────────────────────────────────────────────────────────────────────────────────
do $p0$
declare
  v_res jsonb := '[]'::jsonb;
  c_s   constant text := 'public._agenda_rotina_silencio(date,timestamptz)';
  c_a   constant text := 'public._agenda_rotina_acordes_da_equipe(date,timestamptz)';
  r     record;
  v_s   text;
  v_a   text;
  v_bl  text;
begin
  for r in select * from (values (c_s), (c_a)) x(f) loop
    v_res := pg_temp.ok(v_res, format('P0a %s: a porta de antes (invoker, volátil | anon authenticated service_role public = ninguém) e search_path=public', r.f),
      pg_temp.porta(r.f) = 'f v | f f f f'
      and exists (select 1 from pg_proc p, unnest(p.proconfig) c where p.oid = to_regprocedure(r.f) and replace(c, '"', '') = 'search_path=public'),
      coalesce(pg_temp.porta(r.f), 'NÃO EXISTE') || ' config '
      || coalesce((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure(r.f)), '-'));
    v_res := pg_temp.ok(v_res, format('P0b %s: nenhum UPDATE/DELETE sem WHERE (pg_safeupdate)', r.f),
      not exists (select 1 from pg_temp.sem_where(coalesce(pg_temp.src(r.f), ''))),
      (select string_agg(x, ' | ') from pg_temp.sem_where(coalesce(pg_temp.src(r.f), '')) x));
  end loop;
  v_res := pg_temp.ok(v_res, 'P0a public.agenda_rotina_rodar(date,timestamptz), quem as chama: a porta de antes (definer | só service_role)',
    pg_temp.porta('public.agenda_rotina_rodar(date,timestamptz)') = 't v | f f t f', pg_temp.porta('public.agenda_rotina_rodar(date,timestamptz)'));
  v_s := coalesce(pg_temp.src(c_s), '');
  v_a := coalesce(pg_temp.src(c_a), '');
  v_res := pg_temp.ok(v_res, 'P0c _agenda_rotina_silencio: sem os 2 blocos "-- P1 AGENDA:" o corpo é o de produção de 24/11/2026 (md5 sem CR 3fd0c50d…, o de 20261026100300)',
    md5(pg_temp.sem_blocos(v_s, 'P1 AGENDA')) = '3fd0c50deda251310c23a739ea1c9d4d' and md5(v_s) <> '3fd0c50deda251310c23a739ea1c9d4d'
    and (select count(*) from regexp_matches(v_s, '-- P1 AGENDA: fim', 'g')) = 2,
    format('%s / %s blocos', md5(pg_temp.sem_blocos(v_s, 'P1 AGENDA')), (select count(*) from regexp_matches(v_s, '-- P1 AGENDA: fim', 'g'))));
  v_res := pg_temp.ok(v_res, 'P0c _agenda_rotina_acordes_da_equipe: sem o bloco "-- P1 AGENDA:" o corpo é o de produção de 24/11/2026 (md5 sem CR ae015c82…, o de 20261109101000)',
    md5(pg_temp.sem_blocos(v_a, 'P1 AGENDA')) = 'ae015c82c843ab919bb4f4904e3509e9' and md5(v_a) <> 'ae015c82c843ab919bb4f4904e3509e9'
    and (select count(*) from regexp_matches(v_a, '-- P1 AGENDA: fim', 'g')) = 1,
    format('%s / %s blocos', md5(pg_temp.sem_blocos(v_a, 'P1 AGENDA')), (select count(*) from regexp_matches(v_a, '-- P1 AGENDA: fim', 'g'))));
  v_bl := pg_temp.so_blocos(v_s);
  v_res := pg_temp.ok(v_res, 'P0d o ramo novo só vale com equipe_silencio_acao = ''manter'' (fora dos blocos ninguém lê a chave); nele nada chama o replano, grava disponibilidade nem muda o estado da confirmação; o 2º pedido é tipo ''resposta'' de chave reconfirmar:<dia>',
    v_s like '%if cf.equipe_silencio_acao = ''manter'' then%'
    and pg_temp.sem_blocos(v_s, 'P1 AGENDA') not like '%equipe_silencio_acao%' and pg_temp.sem_blocos(v_a, 'P1 AGENDA') not like '%equipe_silencio_acao%'
    and v_bl !~ 'agenda_replanejar|agenda_disponibilidade|update public\.agenda_equipe_mensagens'
    and v_bl ~ 'public\._agenda_equipe_registrar\(m\.payee_id, p_hoje, ''resposta'','
    and v_bl like '%''reconfirmar:'' || p_hoje::text%',
    null);
  v_res := pg_temp.ok(v_res, 'P0e a chave agenda_config.equipe_silencio_acao existe e nasce ''tirar'' (o de antes); o valor de agora (só mostra)',
    exists (select 1 from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'equipe_silencio_acao' and not a.attisdropped
               and pg_get_expr(d.adbin, d.adrelid) = '''tirar''::text'),
    (select 'agora: ' || string_agg(cfg.equipe_silencio_acao, ', ') from public.agenda_config cfg));
  v_res := pg_temp.ok(v_res, 'P0f os comentários das 2 ganharam o trecho do A2 uma vez (o de antes fica à frente)',
    (select count(*) from regexp_matches(coalesce(obj_description(to_regprocedure(c_s), 'pg_proc'), ''), 'P1 AGENDA \(A2, 24/11/2026', 'g')) = 1
    and (select count(*) from regexp_matches(coalesce(obj_description(to_regprocedure(c_a), 'pg_proc'), ''), 'P1 AGENDA \(A2, 24/11/2026', 'g')) = 1
    and obj_description(to_regprocedure(c_a), 'pg_proc') like 'Agenda de Produção (Fase 3, P4)%',
    left(coalesce(obj_description(to_regprocedure(c_s), 'pg_proc'), '(sem)'), 60));
  -- 20270301120310: os consertos A (agenda_rotina_rodar) e B (_agenda_rotina_conclusao)
  v_s := coalesce(pg_temp.src('public._agenda_rotina_conclusao(date,timestamptz)'), '');
  v_a := coalesce(pg_temp.src('public.agenda_rotina_rodar(date,timestamptz)'), '');
  v_res := pg_temp.ok(v_res, 'P0g public._agenda_rotina_conclusao(date,timestamptz): a porta de antes (invoker, volátil | ninguém de fora) e nenhum UPDATE/DELETE sem WHERE; agenda_rotina_rodar também sem',
    pg_temp.porta('public._agenda_rotina_conclusao(date,timestamptz)') = 'f v | f f f f'
    and not exists (select 1 from pg_temp.sem_where(v_s)) and not exists (select 1 from pg_temp.sem_where(v_a)),
    pg_temp.porta('public._agenda_rotina_conclusao(date,timestamptz)'));
  v_res := pg_temp.ok(v_res, 'P0h _agenda_rotina_conclusao: sem o bloco "-- P1 AGENDA: (A2" o corpo é o de 20270301120200, em produção desde 26/11 (md5 sem CR 3fcde03f…); sem todos os "-- P1 AGENDA:", o de 24/11 (ae91e221…); 1 bloco do A2 e os 3 do A3',
    md5(pg_temp.sem_a2(v_s)) = '3fcde03f330c85e6d0fe93a20b4dd2e8' and md5(v_s) <> '3fcde03f330c85e6d0fe93a20b4dd2e8'
    and md5(pg_temp.sem_blocos(v_s, 'P1 AGENDA')) = 'ae91e2216c9eede4ce794e7a9ba86b2f'
    and (select count(*) from regexp_matches(v_s, '-- P1 AGENDA: \(A2,', 'g')) = 1
    and (select count(*) from regexp_matches(v_s, '-- P1 AGENDA: \(A3,', 'g')) = 3,
    format('%s / %s', md5(pg_temp.sem_a2(v_s)), md5(pg_temp.sem_blocos(v_s, 'P1 AGENDA'))));
  v_res := pg_temp.ok(v_res, 'P0i o conserto B é uma linha só, no ramo do plano com mais dias: a mensagem de leitura tipo ok (o "ok" puro) não abre a pergunta',
    btrim(regexp_replace(substring(v_s from '-- P1 AGENDA: \(A2, 26/11/2026, conserto B\).*?-- P1 AGENDA: fim'), '--[^\n]*', '', 'g'), E' \n')
      = 'continue when m.leitura ->> ''tipo'' = ''ok'' and cardinality(v_fut) > 0;'
    and position('continue when m.leitura ->> ''tipo'' = ''ok'' and cardinality(v_fut) > 0;' || E'\n      -- P1 AGENDA: fim\n      if public._agenda_equipe_perguntar(''concluir'', format(''concluir:%s:%s'', v_x, p_hoje)' in v_s) > 0,
    btrim(regexp_replace(substring(v_s from '-- P1 AGENDA: \(A2, 26/11/2026, conserto B\).*?-- P1 AGENDA: fim'), '--[^\n]*', '', 'g'), E' \n'));
  v_res := pg_temp.ok(v_res, 'P0j agenda_rotina_rodar: sem os 2 blocos "-- P1 AGENDA: (A2" (devolvidas as linhas "--antes:") o corpo é o de produção (md5 sem CR c418e862…, o de 20261026100300)',
    md5(pg_temp.sem_a2(v_a)) = 'c418e86267bf6e6021e3e1ff855f1013' and md5(v_a) <> 'c418e86267bf6e6021e3e1ff855f1013'
    and (select count(*) from regexp_matches(v_a, '-- P1 AGENDA: \(A2,', 'g')) = 2,
    md5(pg_temp.sem_a2(v_a)));
  v_res := pg_temp.ok(v_res, 'P0k o conserto A só mexe na cota dos acordes: fora dela fica a ação silencio_manteve; continua "só com a vigia ligada e a ação executada"',
    pg_temp.so_blocos(v_a) like '%a.depois ->> ''motivo'' is distinct from ''silencio_manteve''%'
    and pg_temp.so_blocos(v_a) like '%where q.ord <= v_cota or q.fora_da_cota;%'
    and pg_temp.so_blocos(v_a) like '%and a.executada)) q%'
    and pg_temp.sem_blocos(v_a, 'P1 AGENDA') like '%if cf.modo_vigia = ''ligado'' and jsonb_array_length(v_acordes) > 0 then%',
    null);
  v_res := pg_temp.ok(v_res, 'P0l os comentários da conclusão e da rodada ganharam o trecho do conserto uma vez (o de antes fica à frente)',
    (select count(*) from regexp_matches(coalesce(obj_description(to_regprocedure('public._agenda_rotina_conclusao(date,timestamptz)'), 'pg_proc'), ''), 'P1 AGENDA \(A2, conserto B', 'g')) = 1
    and (select count(*) from regexp_matches(coalesce(obj_description(to_regprocedure('public.agenda_rotina_rodar(date,timestamptz)'), 'pg_proc'), ''), 'P1 AGENDA \(A2, conserto A', 'g')) = 1
    and obj_description(to_regprocedure('public.agenda_rotina_rodar(date,timestamptz)'), 'pg_proc') like 'Agenda de Produção (Fase 3, P4)%'
    and obj_description(to_regprocedure('public._agenda_rotina_conclusao(date,timestamptz)'), 'pg_proc') like '%P1 AGENDA (A3, 24/11/2026%P1 AGENDA (A2, conserto B%',
    null);
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── S e C. O Roberto no Vanderlei (a fixture-fase3) ──────────────────────────────────────────────────────────────────────────────────
do $s$
declare
  v_res     jsonb := '[]'::jsonb;
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_gustavo constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_vand    constant uuid := '05000000-0000-4000-8000-000000000069';
  d03       constant date := date '2026-11-03';
  d04       constant date := date '2026-11-04';
  d05       constant date := date '2026-11-05';
  c_dono1   constant text := 'O Roberto não respondeu à confirmação de hoje até as 9h (não sei se a mensagem chegou). Mantive o dia dele: Vanderlei (OS-00069). Pedi de novo a ele. Se ele não for, me avise que eu refaço a agenda.';
  c_dono2   constant text := 'O Roberto não respondeu à confirmação de hoje até as 9h (não sei se a mensagem chegou). Mantive o dia dele: Vanderlei (OS-00069). Não consegui pedir de novo. Se ele não for, me avise que eu refaço a agenda.';
  c_pedido  constant text := 'Roberto, ainda não vi sua resposta de hoje cedo. Hoje é Vanderlei às 8h. Tá confirmado? Responda *ok* se vem ou *não vou* se não der.';
  c_como_foi constant text := 'Como foi hoje? Ficou manhã e tarde? Terminou o previsto? Se foi tudo como o previsto, responde OK.';
  c_ok      constant text := 'O Roberto respondeu *ok* ao "como foi hoje?" no último dia da OS-00069 (Vanderlei). Responda *concluiu OS-00069* para fechar, ou *falta dia OS-00069* se ainda tem serviço.';
  c_chave   constant text := 'terminou:05000000-0000-4000-8000-000000000069';
  r         jsonb;
  r1        jsonb;
  r2        jsonb;
  a         public.agenda_acoes;
  a2        public.agenda_acoes;
  p         public.agenda_equipe_mensagens;
  p2        public.agenda_equipe_mensagens;
  c         public.agenda_equipe_mensagens;
  v_plano   text;
  v_n_disp  int;
  v_n_acoes int;
  v_n_msgs  int;
  v_txt     text;
  v_id      uuid;
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('S1–S10 e C (fixture-fase3)', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase3');
  -- O registrar_diaria recusa "dia no futuro" pelo relógio de verdade (_hoje_brt): aqui o "hoje" do teste vale também para ele (como em
  -- agenda_fase3_equipe_diarias.sql). Dentro da transação: o ROLLBACK do fim desfaz.
  create or replace function public._hoje_brt() returns date language sql stable set search_path to 'public' as $h$
    select coalesce(nullif(current_setting('agenda_teste.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date)
  $h$;
  perform set_config('agenda_teste.hoje', '2026-11-08', true);
  update public.agenda_config set modo_equipe = 'ligado', modo_diaria = 'ligado' where id;

  v_res := pg_temp.ok(v_res, 'S0 o ponto de partida: a chave nasce ''tirar'', a equipe, o motor e a vigia ligados, o Roberto no Vanderlei de ter 03 a qui 05/11, de manhã e de tarde',
    (select cfg.equipe_silencio_acao = 'tirar' and cfg.modo_equipe = 'ligado' and cfg.modo_proposta = 'ligado' and cfg.modo_vigia = 'ligado'
       from public.agenda_config cfg)
    and pg_temp.plano(c_roberto, d03) like format('2026-11-03 manha %1$s, 2026-11-03 tarde %1$s, 2026-11-04 manha %1$s, 2026-11-04 tarde %1$s, 2026-11-05 manha %1$s, 2026-11-05 tarde %1$s%%', c_vand),
    pg_temp.plano(c_roberto, d03));

  -- ── S1. 'tirar' (o padrão): o de hoje ──
  begin
    perform pg_temp.rodar(d03, '07:45');
    perform pg_temp.saiu(d03, '07:46');
    r := pg_temp.rodar(d03, '09:00');
    v_res := pg_temp.ok(v_res, 'S1 ''tirar'' (o padrão), 09:00 sem resposta: o de hoje — indisponível (agente), a ação silencio, o replano tira o Roberto de hoje, a confirmação sem_resposta, o acorde "Mudei a agenda de hoje" e nenhum 2º pedido nem silencio_manteve',
      (r #>> '{contagens,silencio,silencio}')::int = 1
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel' and d.origem = 'agente'
                                                              and d.periodo @> d03 and d.substituida_em is null)
      and (pg_temp.acao(c_roberto, d03, 'silencio')).id is not null and (pg_temp.acao(c_roberto, d03, 'silencio_manteve')).id is null
      and pg_temp.plano(c_roberto, d03) not like '2026-11-03%'
      and (pg_temp.msg(c_roberto, 'confirmar', d03)).estado = 'sem_resposta'
      and (pg_temp.pedido(c_roberto, d03)).id is null
      and not exists (select 1 from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'resposta')
      and jsonb_array_length(r -> 'acordes') = 1
      and r -> 'acordes' -> 0 ->> 'texto' like 'O Roberto não respondeu à confirmação de hoje até as 9h. Mudei a agenda de hoje:%',
      r -> 'acordes' -> 0 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S2, S3, S9, S6. 'manter': o dia fica, o dono é avisado, o técnico recebe o 2º pedido ──
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    perform pg_temp.rodar(d03, '07:45');
    perform pg_temp.saiu(d03, '07:46');
    v_plano := pg_temp.plano(c_roberto, d03);
    v_n_disp := (select count(*) from public.agenda_disponibilidade d where d.payee_id = c_roberto);
    v_n_acoes := (select count(*) from public.agenda_acoes);
    r := pg_temp.rodar(d03, '09:00');
    a := pg_temp.acao(c_roberto, d03, 'silencio_manteve');
    p := pg_temp.pedido(c_roberto, d03);
    c := pg_temp.msg(c_roberto, 'confirmar', d03);
    v_res := pg_temp.ok(v_res, 'S2a ''manter'', 09:00 sem resposta: nada tira o dia — nenhuma disponibilidade nova, nenhum replano (só 1 ação nova), as alocações intactas e a confirmação continua enfileirada',
      (r #>> '{contagens,silencio,silencio}')::int = 1 and (r ->> 'erros')::int = 0
      and (select count(*) from public.agenda_disponibilidade d where d.payee_id = c_roberto) = v_n_disp
      and (select count(*) from public.agenda_acoes) = v_n_acoes + 1
      and pg_temp.plano(c_roberto, d03) = v_plano
      and c.estado = 'enfileirada' and c.resposta_em is null,
      format('silencio %s | disp %s→%s | ações %s→%s | confirmação %s | erros %s', r #>> '{contagens,silencio,silencio}', v_n_disp,
             (select count(*) from public.agenda_disponibilidade d where d.payee_id = c_roberto), v_n_acoes, (select count(*) from public.agenda_acoes),
             c.estado, r ->> 'erros'));
    v_res := pg_temp.ok(v_res, 'S2b a ação silencio_manteve: equipe, origem equipe, executada, hoje, do Roberto, OS-00069 em service_order_id e os_ids, com acorde, a confirmação e o 2º pedido (enfileirada) no depois',
      a.id is not null and a.tipo = 'equipe' and a.origem = 'equipe' and a.executada and a.dia = d03 and a.payee_id = c_roberto
      and a.service_order_id = c_vand and a.os_ids = array[c_vand]
      and a.depois ->> 'dia' = '2026-11-03' and (a.depois ->> 'acorde')::boolean and a.depois ->> 'mensagem' = c.id::text
      and a.depois ->> 'segundo_pedido' = p.id::text and a.depois ->> 'segundo_pedido_estado' = 'enfileirada'
      and a.depois -> 'segundo_pedido_motivo' = 'null'::jsonb and not a.depois ? 'replano_acoes',
      coalesce(a.depois::text, '(sem ação)'));
    v_res := pg_temp.ok(v_res, 'S2c o texto ao dono, exato (1ª variante): "' || c_dono1 || '"', a.texto = c_dono1, a.texto);
    v_res := pg_temp.ok(v_res, 'S2d o 2º pedido: tipo resposta (não é tipo novo), dia de hoje, ligado, enfileirada às 09:00, chave agenda-equipe:resposta:<pessoa>:reconfirmar:2026-11-03 (responde_wa_id reconfirmar:2026-11-03), sem leitura',
      p.id is not null and p.tipo = 'resposta' and p.dia = d03 and p.modo = 'ligado' and p.estado = 'enfileirada'
      and p.enviar_em = pg_temp.em(d03, '09:00') and p.dedupe_key = format('agenda-equipe:resposta:%s:reconfirmar:2026-11-03', c_roberto)
      and p.responde_wa_id = 'reconfirmar:2026-11-03' and p.leitura is null and p.resposta_em is null,
      coalesce(to_jsonb(p) - 'texto', '{}'::jsonb)::text);
    v_res := pg_temp.ok(v_res, 'S2e o texto ao técnico, exato: "' || c_pedido || '" (sem valor nem número de OS)',
      p.texto = c_pedido and position('R$' in p.texto) = 0 and position('OS-' in p.texto) = 0, p.texto);
    v_res := pg_temp.ok(v_res, 'S2f na fila de sempre: agenda-equipe, o telefone dele, 09:00, a chave da mensagem (a trava da fila exige), o texto dele; conta no teto de respostas (1), não no de proativas (1: a confirmação)',
      (select count(*) = 1 and bool_and(q.phone_normalized = '5547900000001' and q.scheduled_for = pg_temp.em(d03, '09:00') and q.status = 'pending'
                                          and q.dedupe_key = p.dedupe_key and q.message = c_pedido and q.id = p.fila_id)
         from public.whatsapp_send_queue q where q.source = 'agenda-equipe' and q.source_ref_id = p.id)
      and public._agenda_equipe_no_dia(c_roberto, d03, true, null) = 1 and public._agenda_equipe_no_dia(c_roberto, d03, false, null) = 1,
      (select jsonb_agg(to_jsonb(q) - 'id')::text from public.whatsapp_send_queue q where q.source_ref_id = p.id));
    v_res := pg_temp.ok(v_res, 'S9a o acorde ao dono no mesmo tique: 1, com o texto da ação inteiro, a própria ação (acao_id e chave agenda:<ação>), o assunto equipe:<pessoa> e a perda hoje',
      jsonb_array_length(r -> 'acordes') = 1 and r -> 'acordes' -> 0 ->> 'texto' = c_dono1
      and r -> 'acordes' -> 0 ->> 'acao_id' = a.id::text and r -> 'acordes' -> 0 ->> 'chave' = 'agenda:' || a.id
      and r -> 'acordes' -> 0 ->> 'assunto' = 'equipe:' || c_roberto and r -> 'acordes' -> 0 ->> 'perda_em' = '2026-11-03'
      and r -> 'acordes' -> 0 ->> 'os' = c_vand::text,
      (r -> 'acordes')::text);
    r1 := public._agenda_rotina_acordes_da_equipe(d03, pg_temp.em(d03, '09:01'));
    v_res := pg_temp.ok(v_res, 'S9b o passo sozinho (_agenda_rotina_acordes_da_equipe), antes de o acorde ser contado: o mesmo acorde, a frase inteira (sem "A agenda automática não está ligada")',
      (r1 ->> 'acordes_da_equipe')::int = 1 and r1 -> 'acordes' -> 0 ->> 'texto' = c_dono1
      and r1 -> 'acordes' -> 0 ->> 'texto' not like '%agenda automática%', (r1 -> 'acordes')::text);
    r1 := pg_temp.acordou(a.id, d03, '09:01');
    v_n_msgs := (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto);
    v_n_acoes := (select count(*) from public.agenda_acoes);
    r := pg_temp.rodar(d03, '09:15');
    v_res := pg_temp.ok(v_res, 'S3/S9c o tique das 09:15 (o acorde das 09:00 contado): nada novo — nem ação, nem mensagem, nem acorde; o 2º pedido é o mesmo',
      (r #>> '{contagens,silencio,silencio}')::int = 0 and jsonb_array_length(r -> 'acordes') = 0
      and (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto) = v_n_msgs
      and (select count(*) from public.agenda_acoes) = v_n_acoes
      and (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'resposta') = 1
      and (select e.contada_via = 'acorde' and e.contada_em is not null from public.agenda_acoes e where e.id = a.id),
      format('silencio %s | acordes %s | mensagens %s→%s | ações %s→%s', r #>> '{contagens,silencio,silencio}', jsonb_array_length(r -> 'acordes'),
             v_n_msgs, (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto), v_n_acoes,
             (select count(*) from public.agenda_acoes)));
    r := pg_temp.rodar(d03, '11:45');
    v_res := pg_temp.ok(v_res, 'S3b nem às 11:45 (o último tique da manhã): uma ação e um pedido por pessoa e dia',
      (r #>> '{contagens,silencio,silencio}')::int = 0
      and (select count(*) from public.agenda_acoes e where e.payee_id = c_roberto and e.depois ->> 'motivo' = 'silencio_manteve') = 1
      and (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'resposta') = 1, r #>> '{contagens,silencio}');
    -- S6: o "como foi" das 17:00, a ficha das 19:30 calada e a confirmação que vence às 21:45
    perform pg_temp.saiu(d03, '09:01');
    v_n_msgs := public._agenda_equipe_no_dia(c_roberto, d03, false, null);
    r := pg_temp.rodar(d03, '17:00');
    p2 := pg_temp.msg(c_roberto, 'como_foi', d03);
    v_res := pg_temp.ok(v_res, 'S6a 17:00: o "como foi hoje?" sai (1 proativa antes dele: a confirmação) e leva a ficha de qua 04/11 (o dia ficou no plano)',
      v_n_msgs = 1 and p2.estado = 'enfileirada' and p2.leva_ficha_de = d04
      and p2.texto = c_como_foi || ' Amanhã (qua 04/11): 8h no barco do Vanderlei.',
      format('proativas antes %s | %s', v_n_msgs, coalesce(to_jsonb(p2)::text, '(sem como foi)')));
    r := pg_temp.rodar(d03, '19:30');
    v_res := pg_temp.ok(v_res, 'S6b 19:30: nada (a ficha de amanhã foi no "como foi"); no dia de silêncio o Roberto recebeu 3 mensagens: a confirmação, o 2º pedido e o "como foi"',
      (pg_temp.msg(c_roberto, 'ficha', d04)).id is null
      and (select string_agg(m.tipo, ', ' order by m.enviar_em) from public.agenda_equipe_mensagens m
            where m.payee_id = c_roberto and (m.enviar_em at time zone 'America/Sao_Paulo')::date = d03 and m.fila_id is not null)
          = 'confirmar, resposta, como_foi',
      (select string_agg(m.tipo || ' ' || m.estado, ', ' order by m.enviar_em) from public.agenda_equipe_mensagens m
        where m.payee_id = c_roberto and (m.enviar_em at time zone 'America/Sao_Paulo')::date = d03));
    r := pg_temp.rodar(d03, '22:00');
    v_res := pg_temp.ok(v_res, 'S6c 22:00 (o 1º tique depois das 07:45 + 14 h): a confirmação sem resposta vira sem_resposta; o 2º pedido (resposta) fica como está',
      (pg_temp.msg(c_roberto, 'confirmar', d03)).estado = 'sem_resposta' and (pg_temp.pedido(c_roberto, d03)).estado = 'enfileirada'
      and pg_temp.plano(c_roberto, d03) = v_plano,
      (pg_temp.msg(c_roberto, 'confirmar', d03)).estado);
    -- S7, S10: a manhã seguinte, de novo sem resposta
    perform pg_temp.saiu(d03, '21:46');
    r := pg_temp.rodar(d04, '07:45');
    perform pg_temp.saiu(d04, '07:46');
    r := pg_temp.rodar(d04, '09:00');
    a2 := pg_temp.acao(c_roberto, d04, 'silencio_manteve');
    v_res := pg_temp.ok(v_res, 'S7 ontem com 2º pedido e sem resposta (a regra "não pede de novo" saiu, decisão de 26/11): hoje sai outro 2º pedido, 1 só, com a chave de hoje, e o texto ao dono na 1ª variante',
      (pg_temp.msg(c_roberto, 'confirmar', d04)).estado = 'enfileirada'
      and (pg_temp.pedido(c_roberto, d04)).estado = 'enfileirada' and (pg_temp.pedido(c_roberto, d04)).texto = c_pedido
      and (select count(*) from public.agenda_equipe_mensagens m
            where m.payee_id = c_roberto and m.tipo = 'resposta' and m.dia = d04 and m.dedupe_key like '%:reconfirmar:%') = 1
      and a2.texto = c_dono1 and a2.depois ->> 'segundo_pedido_estado' = 'enfileirada' and jsonb_array_length(r -> 'acordes') = 1,
      format('pedido de hoje %s | ação %s | acordes %s', (pg_temp.pedido(c_roberto, d04)).estado, a2.texto, jsonb_array_length(r -> 'acordes')));
    r1 := pg_temp.acordou(a2.id, d04, '09:01');
    perform pg_temp.saiu(d04, '09:01');
    r := pg_temp.rodar(d04, '09:15');
    r := pg_temp.rodar(d04, '17:00');
    v_res := pg_temp.ok(v_res, 'S10 duas manhãs seguidas de silêncio com ''manter'': 0 meios-dias tirados, 2 segundos pedidos (1 por dia), 2 acordes ao dono, 2 "como foi"',
      pg_temp.plano(c_roberto, d03) = v_plano
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel')
      and (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.dedupe_key like '%:reconfirmar:%') = 2
      and (select count(*) from public.agenda_acoes e where e.payee_id = c_roberto and e.depois ->> 'motivo' = 'silencio_manteve' and e.contada_via = 'acorde') = 2
      and (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'como_foi' and m.estado = 'enfileirada') = 1
      and (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'como_foi') = 2
      and not exists (select 1 from public.agenda_acoes e where e.payee_id = c_roberto and e.depois ->> 'motivo' = 'silencio'),
      format('plano %s | pedidos %s | acordes %s | como foi %s', pg_temp.plano(c_roberto, d03) = v_plano,
             (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.dedupe_key like '%:reconfirmar:%'),
             (select count(*) from public.agenda_acoes e where e.payee_id = c_roberto and e.depois ->> 'motivo' = 'silencio_manteve' and e.contada_via = 'acorde'),
             (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'como_foi')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S2b/S2c. Sem dia dele no plano de hoje; e a mensagem dele depois do envio ──
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    perform pg_temp.rodar(d03, '07:45');
    perform pg_temp.saiu(d03, '07:46');
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where payee_id = c_roberto and dia = d03 and estado in ('publicada', 'fixada');
    v_n_acoes := (select count(*) from public.agenda_acoes);
    r := pg_temp.rodar(d03, '09:00');
    v_res := pg_temp.ok(v_res, 'S2g ''manter'' sem dia dele no plano de hoje (o dono o tirou depois das 07:45): nada — nem ação, nem 2º pedido, nem disponibilidade; a confirmação continua enfileirada',
      (r #>> '{contagens,silencio,silencio}')::int = 0 and (select count(*) from public.agenda_acoes) = v_n_acoes
      and (pg_temp.pedido(c_roberto, d03)).id is null and (pg_temp.msg(c_roberto, 'confirmar', d03)).estado = 'enfileirada'
      and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel'),
      r #>> '{contagens,silencio}');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    perform pg_temp.rodar(d03, '07:45');
    perform pg_temp.saiu(d03, '07:46');
    insert into public.whatsapp_messages (direction, phone_normalized, body, created_at)
    values ('inbound', '5547900000001', 'tô indo', pg_temp.em(d03, '08:30'));
    r := pg_temp.rodar(d03, '09:00');
    v_res := pg_temp.ok(v_res, 'S2h ''manter'' com uma mensagem dele depois do envio (só em whatsapp_messages): não é silêncio, como antes — nada',
      (r #>> '{contagens,silencio,silencio}')::int = 0 and (pg_temp.acao(c_roberto, d03, 'silencio_manteve')).id is null
      and (pg_temp.pedido(c_roberto, d03)).id is null, r #>> '{contagens,silencio}');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S4. "ok" às 10:00 ──
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    perform pg_temp.rodar(d03, '07:45');
    perform pg_temp.saiu(d03, '07:46');
    perform pg_temp.rodar(d03, '09:00');
    perform pg_temp.saiu(d03, '09:01');
    r := pg_temp.resp('ok', d03, '10:00');
    c := pg_temp.msg(c_roberto, 'confirmar', d03);
    p := pg_temp.pedido(c_roberto, d03);
    v_res := pg_temp.ok(v_res, 'S4 "ok" às 10:00: responde à CONFIRMAÇÃO das 07:45 (respondida, leitura ok, disponibilidade confirmada "Confirmou de manhã: ok"), não ao 2º pedido (que fica como está) nem ao "como foi"; nenhuma resposta automática',
      (r ->> 'consumiu')::boolean and r ->> 'tipo' = 'ok' and r ->> 'resposta' is null
      and c.estado = 'respondida' and c.resposta_texto = 'ok' and c.leitura ->> 'tipo' = 'ok' and c.resposta_em = pg_temp.em(d03, '10:00')
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'confirmada' and d.origem = 'diarista'
                                                              and d.periodo @> d03 and d.substituida_em is null and d.nota = 'Confirmou de manhã: ok')
      and p.estado = 'enfileirada' and p.resposta_em is null and p.leitura is null
      and (pg_temp.msg(c_roberto, 'como_foi', d03)).id is null
      and (select count(*) from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'resposta') = 1,
      r::text || ' | confirmação ' || c.estado);
    r := pg_temp.rodar(d03, '10:15');
    v_res := pg_temp.ok(v_res, 'S4b e o tique seguinte não faz nada com a confirmação respondida (nem ação, nem pedido)',
      (r #>> '{contagens,silencio,silencio}')::int = 0
      and (select count(*) from public.agenda_acoes e where e.payee_id = c_roberto and e.depois ->> 'motivo' like 'silencio%') = 1, r #>> '{contagens,silencio}');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S5. "não vou" às 10:00 ──
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    perform pg_temp.rodar(d03, '07:45');
    perform pg_temp.saiu(d03, '07:46');
    perform pg_temp.rodar(d03, '09:00');
    a := pg_temp.acao(c_roberto, d03, 'silencio_manteve');
    perform pg_temp.saiu(d03, '09:01');
    r := pg_temp.resp('hoje não vou', d03, '10:00');
    a2 := pg_temp.acao(c_roberto, d03, 'nao_vou');
    v_res := pg_temp.ok(v_res, 'S5a "não vou" às 10:00 (depois do 2º pedido): o caminho de hoje — responde à confirmação, indisponível (diarista), o replano tira o Roberto de hoje, a ação nao_vou com acorde e "Tá bom, aviso o Gustavo."',
      (r ->> 'consumiu')::boolean and r ->> 'tipo' = 'nao_vou' and (r ->> 'dia')::date = d03 and r ->> 'resposta' = 'Tá bom, aviso o Gustavo.'
      and (pg_temp.msg(c_roberto, 'confirmar', d03)).estado = 'respondida'
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = c_roberto and d.situacao = 'indisponivel' and d.origem = 'diarista'
                                                              and d.periodo @> d03 and d.substituida_em is null)
      and pg_temp.plano(c_roberto, d03) not like '2026-11-03%'
      and a2.id is not null and (a2.depois ->> 'acorde')::boolean and jsonb_array_length(a2.depois -> 'replano_acoes') > 0,
      r::text);
    -- o acorde das 09:00 saiu (o envio de sempre o conta)
    r1 := pg_temp.acordou(a.id, d03, '09:02');
    r2 := public._agenda_rotina_acordes_da_equipe(d03, pg_temp.em(d03, '10:15'));
    v_res := pg_temp.ok(v_res, 'S5b o passo dos acordes monta o do "não vou" como hoje: "O Roberto avisou que não vem hoje (ter 03/11). Mudei a agenda de hoje: …" (o das 09:00, contado, não volta)',
      (r2 ->> 'acordes_da_equipe')::int = 1 and r2 -> 'acordes' -> 0 ->> 'texto' like 'O Roberto avisou que não vem hoje (ter 03/11). Mudei a agenda de hoje:%'
      and r2 -> 'acordes' -> 0 ->> 'acao_id' <> a.id::text,
      (r2 -> 'acordes')::text);
    r := pg_temp.rodar(d03, '10:15');
    v_res := pg_temp.ok(v_res, 'S5c (conserto A) com o acorde das 09:00 já contado e a cota do dia em 1 (acordes_dia_max), o do "não vou" sai no MESMO dia: o do silêncio não gasta a cota',
      jsonb_array_length(r -> 'acordes') = 1 and r -> 'acordes' -> 0 ->> 'texto' like 'O Roberto avisou que não vem hoje (ter 03/11). Mudei a agenda de hoje:%'
      and r -> 'acordes' -> 0 ->> 'acao_id' = r2 -> 'acordes' -> 0 ->> 'acao_id'
      and (select cfg.acordes_dia_max from public.agenda_config cfg) = 1
      and (select count(*) from public.agenda_acoes e where e.dia = d03 and e.contada_via = 'acorde') = 1,
      format('rodada %s | passo %s | %s', jsonb_array_length(r -> 'acordes'), r2 ->> 'acordes_da_equipe', r -> 'acordes' -> 0 ->> 'texto'));
    -- e o do "não vou", contado, gasta a cota: um 3º acorde comum no mesmo dia continua cortado
    if r -> 'acordes' -> 0 ->> 'acao_id' is not null then
      r1 := pg_temp.acordou((r -> 'acordes' -> 0 ->> 'acao_id')::uuid, d03, '10:16');
    end if;
    v_res := pg_temp.ok(v_res, 'S5d a cota continua valendo para os outros: contado o do "não vou", a cota do dia fica em 0 (o do silêncio não entra na conta)',
      (select cfg.acordes_dia_max from public.agenda_config cfg)
        - (select count(*) from public.agenda_acoes e where e.dia = d03 and e.contada_via = 'acorde' and e.depois ->> 'motivo' is distinct from 'silencio_manteve') = 0
      and (select count(*) from public.agenda_acoes e where e.dia = d03 and e.contada_via = 'acorde') = 2,
      (select string_agg(coalesce(e.depois ->> 'motivo', e.tipo), ', ' order by e.contada_em) from public.agenda_acoes e where e.dia = d03 and e.contada_via = 'acorde'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S8. O 2º pedido que não sai: sem telefone, no teto, a ficha segurada ──
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    perform pg_temp.rodar(d03, '07:45');
    perform pg_temp.saiu(d03, '07:46');
    update public.payees set phone = null where id = c_roberto;
    v_plano := pg_temp.plano(c_roberto, d03);
    r := pg_temp.rodar(d03, '09:00');
    a := pg_temp.acao(c_roberto, d03, 'silencio_manteve');
    p := pg_temp.pedido(c_roberto, d03);
    v_res := pg_temp.ok(v_res, 'S8a sem telefone: o 2º pedido registrado e recusado (sem_telefone), nada na fila; a ação diz "Não consegui pedir de novo." (2ª variante) e o dia fica',
      p.estado = 'recusada' and p.recusa_motivo = 'sem_telefone' and p.fila_id is null
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = p.id)
      and a.texto = c_dono2 and a.depois ->> 'segundo_pedido' = p.id::text and a.depois ->> 'segundo_pedido_estado' = 'recusada'
      and a.depois ->> 'segundo_pedido_motivo' = 'sem_telefone' and pg_temp.plano(c_roberto, d03) = v_plano
      and jsonb_array_length(r -> 'acordes') = 1 and r -> 'acordes' -> 0 ->> 'texto' = c_dono2,
      coalesce(a.texto, '(sem ação)') || ' | ' || coalesce(p.estado || '/' || p.recusa_motivo, '(sem pedido)'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    perform pg_temp.rodar(d03, '07:45');
    perform pg_temp.saiu(d03, '07:46');
    -- 4 respostas no dia (o teto de respostas, equipe_respostas_dia_max), sem mensagem dele em whatsapp_messages
    for v_n_msgs in 1 .. (select cfg.equipe_respostas_dia_max from public.agenda_config cfg) loop
      r1 := public._agenda_equipe_registrar(c_roberto, d03, 'resposta', format('Teste do teto de respostas %s.', v_n_msgs),
                                            pg_temp.em(d03, format('08:%s', lpad((v_n_msgs * 5)::text, 2, '0'))), null, 'teto:' || v_n_msgs);
    end loop;
    r := pg_temp.rodar(d03, '09:00');
    a := pg_temp.acao(c_roberto, d03, 'silencio_manteve');
    p := pg_temp.pedido(c_roberto, d03);
    v_res := pg_temp.ok(v_res, 'S8b no teto de respostas do dia (4 já na fila): o 2º pedido recusado (teto) e a 2ª variante',
      public._agenda_equipe_no_dia(c_roberto, d03, true, null) = (select cfg.equipe_respostas_dia_max from public.agenda_config cfg)
      and p.estado = 'recusada' and p.recusa_motivo = 'teto' and a.texto = c_dono2 and a.depois ->> 'segundo_pedido_motivo' = 'teto',
      coalesce(a.texto, '(sem ação)') || ' | ' || coalesce(p.estado || '/' || p.recusa_motivo, '(sem pedido)'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    perform pg_temp.rodar(d03, '07:45');
    perform pg_temp.saiu(d03, '07:46');
    -- a ficha do dia segurada depois das 07:45 (a regra trocada só aqui por uma que diz "não": a subtransação a desfaz)
    create or replace function public._agenda_ficha_liberada(p_payee uuid, p_dia date, p_agora timestamptz) returns boolean
      language sql stable set search_path to 'public' as $fl$ select false $fl$;
    r := pg_temp.rodar(d03, '09:00');
    a := pg_temp.acao(c_roberto, d03, 'silencio_manteve');
    v_res := pg_temp.ok(v_res, 'S8c a ficha do dia segurada (_agenda_ficha_liberada falso, a regra da confirmação da manhã): não pede de novo (nada registrado), a 2ª variante, o motivo ficha_segurada no depois, e o dia fica',
      (pg_temp.pedido(c_roberto, d03)).id is null
      and not exists (select 1 from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'resposta')
      and a.texto = c_dono2 and a.depois ->> 'segundo_pedido_estado' = 'nao_pedi' and a.depois ->> 'segundo_pedido_motivo' = 'ficha_segurada'
      and a.depois -> 'segundo_pedido' = 'null'::jsonb and pg_temp.plano(c_roberto, d03) like '2026-11-03 manha%',
      coalesce(a.depois::text, '(sem ação)'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    perform pg_temp.rodar(d03, '07:45');
    perform pg_temp.saiu(d03, '07:46');
    -- o registro que falha (trocado só aqui por um que lança erro; a subtransação o desfaz)
    create or replace function public._agenda_equipe_registrar(p_payee uuid, p_dia date, p_tipo text, p_texto text, p_enviar_em timestamptz,
      p_leva_ficha_de date default null::date, p_responde text default null::text, p_dias date[] default null::date[],
      p_alocacoes uuid[] default null::uuid[], p_chave text default null::text) returns jsonb
      language plpgsql set search_path to 'public' as $er$ begin raise exception 'registro quebrado de propósito (teste S8d)'; end $er$;
    r := pg_temp.rodar(d03, '09:00');
    a := pg_temp.acao(c_roberto, d03, 'silencio_manteve');
    v_res := pg_temp.ok(v_res, 'S8d o registro do 2º pedido que dá erro não segura o aviso ao dono: a ação sai com a 2ª variante (motivo erro), o passo não falha e o erro vai para app_error_logs (rotina:silencio)',
      (r ->> 'erros')::int = 0 and (r #>> '{contagens,silencio,silencio}')::int = 1
      and a.texto = c_dono2 and a.depois ->> 'segundo_pedido_estado' = 'nao_pedi' and a.depois ->> 'segundo_pedido_motivo' = 'erro'
      and jsonb_array_length(r -> 'acordes') = 1
      and exists (select 1 from public.app_error_logs l where l.context = 'agenda' and l.action = 'rotina:silencio'
                                                     and l.message like 'agenda: o 2º pedido do silêncio à equipe falhou: registro quebrado de propósito%'),
      coalesce(a.depois::text, '(sem ação)') || ' | erros ' || (r ->> 'erros'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── C. O "ok" depois do "como foi" das 17:00, no último dia do plano (qui 05/11; só o técnico: o meio-dia do Gustavo sai, como em
  -- agenda_p1_terminei.sql T1/T2) ──
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d05, '07:45');
    perform pg_temp.saiu(d05, '07:46');
    r := pg_temp.rodar(d05, '09:00');
    perform pg_temp.saiu(d05, '09:01');
    v_res := pg_temp.ok(v_res, 'C1a qui 05/11 (o último dia do plano), A3 no ar (equipe_terminei_conclui = false): às 09:00 o silêncio manteve o dia e pediu de novo',
      not (select cfg.equipe_terminei_conclui from public.agenda_config cfg)
      and (pg_temp.acao(c_roberto, d05, 'silencio_manteve')).texto = c_dono1 and (pg_temp.pedido(c_roberto, d05)).estado = 'enfileirada',
      (pg_temp.acao(c_roberto, d05, 'silencio_manteve')).texto);
    perform pg_temp.rodar(d05, '17:00');
    r := pg_temp.resp('ok', d05, '17:15');
    c := pg_temp.msg(c_roberto, 'confirmar', d05);
    p2 := pg_temp.msg(c_roberto, 'como_foi', d05);
    v_res := pg_temp.ok(v_res, 'C1b o "ok" das 17:15 (depois do "como foi" das 17:00) responde ao "COMO FOI", não à confirmação nem ao 2º pedido: "tudo como o previsto e terminou"',
      (r ->> 'consumiu')::boolean and p2.estado = 'respondida' and p2.leitura ->> 'tipo' = 'ok' and (p2.leitura ->> 'terminou')::boolean
      and c.estado = 'enfileirada' and c.resposta_em is null and (pg_temp.pedido(c_roberto, d05)).resposta_em is null,
      format('como foi %s %s | confirmação %s', p2.estado, p2.leitura, c.estado));
    r := pg_temp.rodar(d05, '17:30');
    v_res := pg_temp.ok(v_res, 'C1c no tique seguinte, a OS NÃO conclui (em andamento, sem ação concluir) e nasce a pergunta "terminou ou falta dia?" ao dono com o texto do "ok": "' || c_ok || '"',
      (select so.status = 'in_progress' and so.check_out_at is null from public.service_orders so where so.id = c_vand)
      and not exists (select 1 from public.agenda_acoes x where x.tipo = 'concluir' and x.service_order_id = c_vand)
      and (r #>> '{contagens,conclusao,concluidas}')::int = 0 and (r #>> '{contagens,conclusao,perguntas}')::int = 1
      and exists (select 1 from public.agenda_perguntas q where q.chave = c_chave and q.estado = 'aberta' and q.payee_id = c_roberto and q.texto = c_ok),
      (r #> '{contagens,conclusao}')::text || ' | ' || (select so.status from public.service_orders so where so.id = c_vand)
      || ' | ' || coalesce((select string_agg(q.estado || ': ' || q.texto, ' ; ') from public.agenda_perguntas q where q.chave = c_chave), '(sem pergunta)'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter' where id;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d05, '07:45');
    perform pg_temp.saiu(d05, '07:46');
    perform pg_temp.rodar(d05, '09:00');
    perform pg_temp.saiu(d05, '09:01');
    r := pg_temp.resp('ok', d05, '10:00');
    r1 := pg_temp.rodar(d05, '10:15');
    v_res := pg_temp.ok(v_res, 'C0 o mesmo "ok" às 10:00 (antes do "como foi"): responde à confirmação; nenhuma pergunta terminou:<os>, a OS não conclui',
      (pg_temp.msg(c_roberto, 'confirmar', d05)).estado = 'respondida' and (pg_temp.msg(c_roberto, 'como_foi', d05)).id is null
      and not exists (select 1 from public.agenda_perguntas q where q.chave = c_chave)
      and (select so.status from public.service_orders so where so.id = c_vand) <> 'completed',
      (pg_temp.msg(c_roberto, 'confirmar', d05)).estado);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_config set equipe_silencio_acao = 'manter', equipe_terminei_conclui = true where id;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d05, '07:45');
    perform pg_temp.saiu(d05, '07:46');
    perform pg_temp.rodar(d05, '09:00');
    perform pg_temp.saiu(d05, '09:01');
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('ok', d05, '17:15');
    r := pg_temp.rodar(d05, '17:30');
    v_res := pg_temp.ok(v_res, 'C2 o controle (por que ligar só com o A3 no ar): com equipe_terminei_conclui = true, o mesmo "ok" das 17:15 CONCLUI a OS pela equipe',
      (select so.status from public.service_orders so where so.id = c_vand) = 'completed'
      and exists (select 1 from public.agenda_acoes x where x.tipo = 'concluir' and x.service_order_id = c_vand and x.origem = 'equipe')
      and (r #>> '{contagens,conclusao,concluidas}')::int = 1,
      (r #> '{contagens,conclusao}')::text || ' | ' || (select so.status from public.service_orders so where so.id = c_vand));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S11. (conserto A) Um acorde que já saiu antes das 9h e o silêncio: os dois saem no dia ──
  for v_txt in select x from unnest(array['manter', 'tirar']) x loop
    begin
      update public.agenda_config set equipe_silencio_acao = v_txt where id;
      perform pg_temp.rodar(d03, '07:45');
      perform pg_temp.saiu(d03, '07:46');
      -- um acorde da agenda que saiu às 08:30 (outro assunto do dia: a ação já executada e contada pelo envio de sempre)
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
      values (pg_temp.em(d03, '08:29'), d03, true, 'equipe', 'equipe', c_vand, array[c_vand], c_gustavo,
              jsonb_build_object('motivo', 'teste_acorde_das_8h', 'dia', d03), 'Um acorde de outro assunto, às 08:30.')
      returning id into v_id;
      r1 := pg_temp.acordou(v_id, d03, '08:30');
      r := pg_temp.rodar(d03, '09:00');
      if v_txt = 'manter' then
        v_res := pg_temp.ok(v_res, 'S11 (conserto A) ''manter'', com um acorde que já saiu às 08:30 (a cota do dia, 1, gasta): o "Mantive o dia dele" sai às 09:00 mesmo assim — os dois no dia',
          (select count(*) from public.agenda_acoes e where e.dia = d03 and e.contada_via = 'acorde') = 1
          and jsonb_array_length(r -> 'acordes') = 1 and r -> 'acordes' -> 0 ->> 'texto' = c_dono1,
          coalesce((r -> 'acordes')::text, '(nenhum)'));
      else
        v_res := pg_temp.ok(v_res, 'S11b o controle: com ''tirar'' (o padrão) e o mesmo acorde das 08:30, o acorde do silêncio (o replano) é cortado pela cota, como antes',
          (pg_temp.acao(c_roberto, d03, 'silencio')).id is not null and jsonb_array_length(r -> 'acordes') = 0
          and (select count(*) from public.agenda_acoes e where e.dia = d03 and e.contada_via = 'acorde') = 1,
          coalesce((r -> 'acordes')::text, '(nenhum)'));
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;

  -- ── B. (conserto B, com a chave no padrão 'tirar': vale com qualquer chave) O "como foi" na qua 04/11, que não é o último dia ──
  for v_txt in select x from unnest(array['ok', 'tudo certo', 'ok, terminei', 'terminei']) x loop
    begin
      perform pg_temp.rodar(d04, '17:00');
      r2 := pg_temp.resp(v_txt, d04, '17:15');
      r := pg_temp.rodar(d04, '17:30');
      r1 := pg_temp.rodar(d04, '17:45');
      p2 := pg_temp.msg(c_roberto, 'como_foi', d04);
      if v_txt in ('ok', 'tudo certo') then
        v_res := pg_temp.ok(v_res, format('B1%s o "%s" puro ao "como foi" num dia que não é o último: nenhuma pergunta (nem "disse que terminou", nem nos tiques seguintes); o leitor como hoje (tipo ok, terminou por padrão); a diária lançada e os meios-dias cumpridos, como hoje',
                                          case when v_txt = 'ok' then '' else 'b' end, v_txt),
          (r2 ->> 'consumiu')::boolean and p2.estado = 'respondida' and p2.leitura ->> 'tipo' = 'ok' and (p2.leitura ->> 'terminou')::boolean
          and (r #>> '{contagens,conclusao,perguntas}')::int = 0 and (r1 #>> '{contagens,conclusao,perguntas}')::int = 0
          and not exists (select 1 from public.agenda_perguntas q where q.service_order_id = c_vand and q.tipo = 'concluir')
          and not exists (select 1 from public.agenda_perguntas q where q.payee_id = c_roberto and q.texto like '%terminou%')
          and exists (select 1 from public.agenda_acoes x where x.tipo = 'diaria' and x.payee_id = c_roberto and x.executada
                                                         and x.texto like 'Roberto, qua 04/11: dia inteiro no Vanderlei (OS-00069)%')
          and (select string_agg(x.turno || ' ' || coalesce(x.resultado, '-'), ', ' order by x.turno) from public.agenda_alocacoes x
                where x.payee_id = c_roberto and x.dia = d04 and x.estado in ('publicada', 'fixada')) = 'manha cumprido, tarde cumprido',
          format('leitura %s | perguntas %s/%s | %s', p2.leitura ->> 'tipo', r #>> '{contagens,conclusao,perguntas}', r1 #>> '{contagens,conclusao,perguntas}',
                 coalesce((select string_agg(q.texto, ' ; ') from public.agenda_perguntas q where q.service_order_id = c_vand), '(nenhuma pergunta)')));
      else
        v_res := pg_temp.ok(v_res, format('B2%s "%s" num dia que não é o último: a pergunta de hoje, igual ("O Roberto disse que terminou o Vanderlei (OS-00069), mas o plano tinha mais 1 dia (qui 05/11). *concluiu Vanderlei* fecha a OS."), e a OS não conclui',
                                          case when v_txt = 'ok, terminei' then '' else 'b' end, v_txt),
          p2.leitura ->> 'tipo' = 'turnos' and (p2.leitura ->> 'terminou')::boolean
          and (r #>> '{contagens,conclusao,perguntas}')::int = 1
          and exists (select 1 from public.agenda_perguntas q
                       where q.tipo = 'concluir' and q.estado = 'aberta' and q.service_order_id = c_vand
                         and q.texto = 'O Roberto disse que terminou o Vanderlei (OS-00069), mas o plano tinha mais 1 dia (qui 05/11). *concluiu Vanderlei* fecha a OS.')
          and (select so.status from public.service_orders so where so.id = c_vand) <> 'completed',
          format('leitura %s | %s', p2.leitura ->> 'tipo', coalesce((select string_agg(q.texto, ' ; ') from public.agenda_perguntas q where q.service_order_id = c_vand), '(nenhuma pergunta)')));
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  begin
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('ok', d05, '17:15');
    r := pg_temp.rodar(d05, '17:30');
    v_res := pg_temp.ok(v_res, 'B3 o último dia (qui 05/11, só o técnico) com o "ok" puro e a chave no padrão: o do A3, igual — a pergunta "respondeu *ok*" e a OS não conclui',
      (select so.status = 'in_progress' from public.service_orders so where so.id = c_vand)
      and (r #>> '{contagens,conclusao,perguntas}')::int = 1 and (r #>> '{contagens,conclusao,concluidas}')::int = 0
      and exists (select 1 from public.agenda_perguntas q where q.chave = c_chave and q.estado = 'aberta' and q.texto = c_ok),
      (r #> '{contagens,conclusao}')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o plano acaba na qua 04/11 (os meios-dias de qui 05/11 saem) e a estimativa ainda tem meios-dias: sem dia depois, v_rest > 0
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d04, '17:00');
    perform pg_temp.resp('ok', d04, '17:15');
    r := pg_temp.rodar(d04, '17:30');
    v_res := pg_temp.ok(v_res, 'B4 o último dia do PLANO com a estimativa sobrando (qua 04/11, sem dia depois): o "ok" puro segue com a pergunta de hoje, como o A3 o deixou ("… mas o plano tinha mais serviço do que você disse")',
      (r #>> '{contagens,conclusao,perguntas}')::int = 1 and (r #>> '{contagens,conclusao,concluidas}')::int = 0
      and (public.agenda_meios_da_os(c_vand, d05) ->> 'restantes')::numeric > 0
      and exists (select 1 from public.agenda_perguntas q
                   where q.tipo = 'concluir' and q.estado = 'aberta' and q.service_order_id = c_vand
                     and q.texto = 'O Roberto disse que terminou o Vanderlei (OS-00069), mas o plano tinha mais serviço do que você disse. *concluiu Vanderlei* fecha a OS.'),
      (r #> '{contagens,conclusao}')::text || ' | '
      || coalesce((select string_agg(q.texto, ' ; ') from public.agenda_perguntas q where q.service_order_id = c_vand), '(nenhuma pergunta)'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  raise exception 'desfaz' using errcode = 'P0096';
  exception when sqlstate 'P0096' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
