-- Prova da correção de 29/10 da Agenda de Produção, pacote P2 (migration 20261030100100): "quando tenho agenda livre" passa a
-- ter UMA resposta.
-- bancada: depende de 20261030100100
--
-- O defeito (auditoria de 29/10): com a agenda automática ligada e o plano com só a reserva do Lenine (qui 05, sex 06 e ter
-- 10/11, João e Roberto), *livre* dizia "Livre ela não está: há 7 serviços… de 3 a 6 semanas" e, logo depois, "Livre de
-- verdade (pela simulação da agenda): … a equipe já está livre"; e "um serviço de 2 dias, quando dá?" respondia "no fim da
-- fila, começa entre…" pela projeção da Fase 1, contando a OS travada como se ocupasse a equipe. Três respostas.
--
-- O cenário de HOJE é a fixture-2310.sql que a bancada sempre carrega (a carteira de 23/10, sem nenhuma resposta do dono, a
-- equipe pela semente das diárias, o dono sem os dias em campo) com os modos ligados e a vigia de qui 29/10 às 16:30: ela
-- publica exatamente o que produção publicou (só a reserva do Lenine, 12 meios-dias, João e Roberto). Por cima dela:
--   H  hoje: o *livre* (a resposta inteira, byte a byte; nenhuma das três respostas de antes), os números de cada semana, a
--      *agenda* e a *agenda semana que vem* (o livre uma vez só, logo depois do marcado; sem a fila em faixa), o serviço novo
--      (2 dias; com o Roberto; 1 dia; você e o Roberto; meio dia com o João, que não tem lugar; 5 dias; alguém sem os dias
--      na agenda), a coerência (nenhum serviço simulado pega de alguém mais do que o *livre* diz que ele tem livre) e a
--      equivalência com o motor (a OS de verdade com os mesmos dados cai nos mesmos dias, com as mesmas pessoas)
--   F  a carteira da Fase 2 (fixture-fase2.sql, a semana de 03 a 06/11 publicada; o dono com os dias em campo): o dono entra
--      na conta como "você", o que ocupa (4 OS), o pronto sem lugar, e a coerência
--   N  o que NÃO muda: fora de ligado (sombra e desligado) *livre*, *agenda* e o serviço novo são os de antes, byte a byte
--      (as definições de antes rodadas como pg_temp); agenda_semana continua com a fila em faixa no texto dela (quem troca é
--      a agenda_ver); nada é gravado; determinismo
-- Sempre (com ou sem as fixtures):
--   K  as cópias: agenda_simular e agenda_ver só acrescentam os blocos "-- CORREÇÃO 29/10 (P2):" (× a migration de onde
--      cada uma foi copiada; com as migrations como texto)
--   P  portas: anon não executa nenhuma das 6; a grade de agora só o service_role; o técnico não vê (42501); definer só a
--      agenda_livre_de_verdade e a agenda_encaixe_do_novo; todas STABLE (o texto dos meios-dias, IMMUTABLE)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_correcao_2910_p2.sql
--   Sem as fixtures (produção) os cenários saem PULADO e só P roda. Os cenários mexem em linhas só dentro de subtransações
--   desfeitas na hora; termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.igual(p_res jsonb, p_nome text, p_visto text, p_esperado text) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, p_visto is not distinct from p_esperado,
           case when p_visto is distinct from p_esperado then 'veio: ' || coalesce(p_visto, '(null)') end))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.modos(p_proposta text, p_vigia text) returns void language sql as $f$
  update public.agenda_config set modo_proposta = p_proposta, modo_vigia = p_vigia, modo_leitura = 'ligado' where id
$f$;
create function pg_temp.vigiar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_vigiar(p_dia, (p_dia + p_hora::time) at time zone 'America/Sao_Paulo')
$f$;
create function pg_temp.agora(p_dia date, p_hora text) returns void language sql as $f$
  select set_config('agenda.agora', ((p_dia + p_hora::time) at time zone 'America/Sao_Paulo')::text, true)
$f$;
-- A agenda_ver do dono pelo WhatsApp (service_role, sem login), como a palavra a chama (executar.ts → paraAgendaVer).
create function pg_temp.ver(p_foco text, p_periodo text, p_hoje date) returns text language sql as $f$
  select public.agenda_ver('aa000000-0000-4000-8000-000000000001', p_periodo, null, p_foco, null, null, false, p_hoje) ->> 'texto'
$f$;
-- O serviço novo (agenda_ver simular), como o modelo chama.
create function pg_temp.sim(p_simular jsonb, p_hoje date) returns jsonb language sql as $f$
  select public.agenda_ver('aa000000-0000-4000-8000-000000000001', null, null, null, null, p_simular, false, p_hoje)
$f$;
-- A linha n (1…) de um texto e quantas vezes um trecho aparece nele.
create function pg_temp.linha(p_t text, p_n int) returns text language sql immutable as $f$
  select (string_to_array(p_t, E'\n'))[p_n]
$f$;
create function pg_temp.vezes(p_t text, p_trecho text) returns int language sql immutable as $f$
  select (char_length(p_t) - char_length(replace(p_t, p_trecho, ''))) / greatest(char_length(p_trecho), 1)
$f$;
-- A coerência: o que o serviço simulado pega de cada pessoa em cada semana (meios_por_semana) não passa do que o livre diz
-- que ela tem livre naquela semana (semanas[].pessoas[].meios). Devolve as quebras ("Roberto 2/11: 4 > 3"), vazio = coerente.
create function pg_temp.quebras(p_enc jsonb, p_livre jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(format('%s %s: %s > %s', l.p ->> 'nome', m ->> 'seg', m ->> 'meios', l.p ->> 'meios'), '; '), '')
    from jsonb_array_elements(coalesce(p_enc -> 'meios_por_semana', '[]'::jsonb)) m
    join lateral (select p from jsonb_array_elements(p_livre -> 'semanas') s, jsonb_array_elements(s -> 'pessoas') p
                   where s ->> 'seg' = m ->> 'seg' and p ->> 'payee_id' = m ->> 'payee_id') l on true
   where (m ->> 'meios')::int > (l.p ->> 'meios')::int
$f$;
-- O retrato de TODAS as tabelas agenda_* (linhas e md5 de cada uma), para provar que nada é gravado.
create function pg_temp.retrato() returns jsonb language plpgsql as $f$
declare
  t text;
  v jsonb := '{}'::jsonb;
  n bigint;
  h text;
begin
  for t in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname = 'public' and c.relkind = 'r' and c.relname like 'agenda\_%' order by 1 loop
    execute format('select count(*), md5(coalesce(string_agg(x::text, ''|'' order by x::text), '''')) from public.%I x', t) into n, h;
    v := v || jsonb_build_object(t, jsonb_build_object('n', n, 'md5', h));
  end loop;
  return v;
end $f$;
-- Uma consulta como um papel (e um login): o texto que volta ou "erro <sqlstate>: <mensagem>".
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

-- O corpo (entre as duas marcas $…$) e a função inteira (do "create or replace" ao fecho) de p_nome na migration p_mig.
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
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- As linhas fora dos blocos "-- CORREÇÃO 29/10 (P2): … -- CORREÇÃO 29/10 (P2): fim".
create function pg_temp.sem_blocos(p text) returns text language plpgsql immutable as $f$
declare
  v_rev boolean := false;  -- CORREÇÃO 29/10 (revisão): dentro de um bloco da revisão do lote
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and ltrim(l) like '-- CORREÇÃO 29/10 (P2):%' and ltrim(l) not like '-- CORREÇÃO 29/10 (P2): fim%' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro then
      if ltrim(l) like '-- CORREÇÃO 29/10 (P2): fim%' then v_dentro := false; end if;
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

-- As definições de ANTES de agenda_simular (20261024160500) e de agenda_ver (20261029100800), rodadas como pg_temp: a régua do
-- que não muda fora de ligado. A agenda_ver de antes chama a agenda_simular de antes.
do $antes$
declare
  v_f1 text := coalesce(current_setting('agenda_teste.mig_leituras_fase1', true), '');
  v_f6 text := coalesce(current_setting('agenda_teste.mig_leituras_fase6', true), '');
begin
  if v_f1 = '' or v_f6 = '' then return; end if;
  execute replace(pg_temp.inteira(v_f1, 'agenda_simular'), 'create or replace function public.agenda_simular(',
                  'create function pg_temp.simular_antes(');
  execute replace(replace(pg_temp.inteira(v_f6, 'agenda_ver'), 'create or replace function public.agenda_ver(',
                          'create function pg_temp.ver_antes('),
                  'public.agenda_simular(', 'pg_temp.simular_antes(');
end
$antes$;

-- ── Os cenários ─────────────────────────────────────────────────────────────────────────────────────────
do $cenarios$
declare
  v_fix   boolean := coalesce(current_setting('agenda_teste.fase2', true), '') <> ''
                     and coalesce(current_setting('agenda_teste.mig_leituras_fase1', true), '') <> ''
                     and coalesce(current_setting('agenda_teste.mig_leituras_fase6', true), '') <> ''
                     and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002')
                     and exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000074');
  c_hoje  constant date := date '2026-10-29';
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_rob   constant text := 'bb000000-0000-4000-8000-000000000002';
  c_joao  constant text := 'bb000000-0000-4000-8000-000000000003';
  c_linha constant text := 'Livre de verdade: na semana de 03/11, Roberto 1 dia e meio, João nada; na de 09/11, Roberto 3 dias, João 1 dia.';
  c_fim   constant text := ' É simulação: não marca nada.';
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  x       jsonb;
  v_lv    jsonb;
  v_t     text;
  v_t2    text;
  v_q     text := '';
  v_max   int;
  v_ret   jsonb;
  v_modo  text;
begin
  if not v_fix then
    insert into _resultado values ('H–N cenários da correção P2', true,
      'PULADO: sem as fixtures (fixture-2310, agenda_teste.fase2, mig_leituras_fase1 e mig_leituras_fase6): rode pela bancada');
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  v_max := (select texto_max from public.agenda_config where id);

  -- ── H. Hoje: a carteira de 23/10 sem resposta nenhuma, a vigia de qui 29/10 às 16:30 com tudo ligado ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(c_hoje, '16:30');
    perform pg_temp.agora(c_hoje, '17:40');
    v_res := pg_temp.igual(v_res, 'H0 a vigia publica o que produção publicou: só a reserva do Lenine, qui 05, sex 06 e ter 10/11, João e Roberto (12 meios-dias)',
      (select string_agg(format('%s %s %s', a.dia, py.name, a.turno), ', ' order by a.dia, py.name, a.turno)
         from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
        where a.estado = 'publicada' and a.tipo = 'reserva' and a.service_order_id = '05000000-0000-4000-8000-000000000074')
      || ' | ' || (select count(*) from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada'))::text,
      '2026-11-05 João manha, 2026-11-05 João tarde, 2026-11-05 Roberto manha, 2026-11-05 Roberto tarde, '
      || '2026-11-06 João manha, 2026-11-06 João tarde, 2026-11-06 Roberto manha, 2026-11-06 Roberto tarde, '
      || '2026-11-10 João manha, 2026-11-10 João tarde, 2026-11-10 Roberto manha, 2026-11-10 Roberto tarde | 12');

    v_t := pg_temp.ver('livre', null, c_hoje);
    v_res := pg_temp.igual(v_res, 'H1 *livre* qui 29/10: UMA resposta — quem ainda pega serviço em cada semana, você fora da conta, o que ocupa, o que não ocupa e o serviço novo',
      v_t,
      'Livre de verdade (pelo plano de agora e pelos dias que cada um vem):' || E'\n'
      || '• Semana de 03 a 06/11 (seg 02 é Finados): Roberto 1 dia e meio, João nada.' || E'\n'
      || '• Semana de 09 a 13/11: Roberto 3 dias, João 1 dia.' || E'\n'
      || '• Semana de 16 a 19/11 (sex 20 é Consciência Negra): Roberto 2 dias e meio, João 1 dia.' || E'\n'
      || 'Você fica de fora da conta: não sei em que dias você fica em campo (é só me dizer, por exemplo, "fico em campo de segunda a sexta").' || E'\n'
      || 'Ocupa a equipe: Lenine (reserva, qui 05, sex 06 e ter 10/11, com João e Roberto).' || E'\n'
      || 'Não ocupam ninguém até destravar: Vanderlei, Flávio, Nelson e mais 3; 4 parados no cliente.' || E'\n'
      || 'Para um serviço novo, me diga quantos dias e com quem, que eu digo o 1º dia que cabe.');
    v_res := pg_temp.ok(v_res, 'H2 *livre*: nenhuma das três respostas de antes (a fila em faixa, "a equipe já está livre", "no fim da fila") e dentro do teto',
      v_t not like '%Livre ela não está%' and v_t not like '%já está livre%' and v_t not like '%semanas no ritmo%'
      and v_t not like '%fim da fila%' and v_t not like '%pela simulação%' and char_length(v_t) <= v_max, v_t);
    v_lv := public.agenda_livre_de_verdade(c_hoje, now());
    v_res := pg_temp.igual(v_res, 'H3 os números: os meios-dias que cada um ainda pega = o menor entre teto80 − compromisso, teto100 − compromisso − reserva e os livres na grade (a reserva do Lenine toma a semana do João)',
      (select string_agg(format('%s %s=%s (teto %s, reserva %s, livres %s)', s ->> 'seg', p ->> 'nome', p ->> 'meios', p ->> 'teto',
                                p ->> 'reserva', p ->> 'celulas'), '; ' order by so, po)
         from jsonb_array_elements(v_lv -> 'semanas') with ordinality t(s, so), jsonb_array_elements(s -> 'pessoas') with ordinality u(p, po)),
      '2026-11-02 Roberto=3 (teto 6, reserva 4, livres 4); 2026-11-02 João=0 (teto 3, reserva 4, livres 4); '
      || '2026-11-09 Roberto=6 (teto 7, reserva 2, livres 8); 2026-11-09 João=2 (teto 3, reserva 2, livres 6); '
      || '2026-11-16 Roberto=5 (teto 5, reserva 0, livres 8); 2026-11-16 João=2 (teto 2, reserva 0, livres 6)');
    v_res := pg_temp.ok(v_res, 'H4 os dados: o 1º dia que a agenda ainda pode mudar (ter 03/11), você fora da conta, o Lenine no que ocupa, os 6 travados e os 4 parados',
      v_lv ->> 'de' = '2026-11-03' and (v_lv ->> 'voce_fora')::boolean and v_lv ->> 'texto' = c_linha
      and jsonb_array_length(v_lv -> 'ocupa') = 1 and v_lv #>> '{ocupa,0,numero}' = 'OS-00074' and (v_lv #>> '{ocupa,0,reserva}')::boolean
      and v_lv #> '{nao_ocupam,travados}' = '["OS-00069", "OS-00104", "OS-00112", "OS-00100", "ORÇ-00083", "OS-00096"]'::jsonb
      and (v_lv #>> '{nao_ocupam,parados}')::int = 4, (v_lv - 'texto_completo')::text);

    v_t := pg_temp.ver(null, 'semana', c_hoje);
    v_res := pg_temp.igual(v_res, 'H5 *agenda* qui 29/10: o livre (a linha do plano) logo depois do marcado, no lugar da fila em faixa',
      pg_temp.linha(v_t, 3), c_linha);
    v_res := pg_temp.ok(v_res, 'H6 *agenda*: o livre uma vez só, sem a fila em faixa nem a simulação de antes, com as listas e a oferta, dentro do teto',
      pg_temp.vezes(v_t, 'Livre de verdade') = 1 and v_t not like '%Livre ela não está%' and v_t not like '%pela simulação%'
      and pg_temp.linha(v_t, 2) = 'A semana que vem (seg 02/11 a sáb 07/11): Lenine (reserva, qui 05, sex 06 e ter 10/11).'
      and v_t like '%' || E'\n' || 'Prontos para começar: nenhum.%' and v_t like '%' || E'\n' || 'Para marcar mais que a reserva para Lenine na semana que vem,%'
      and char_length(v_t) <= v_max, v_t);
    v_t := pg_temp.ver(null, 'proxima_semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'H7 *agenda semana que vem*: o livre logo depois do marcado, uma vez só, sem a fila em faixa',
      pg_temp.linha(v_t, 2) = c_linha and pg_temp.vezes(v_t, 'Livre de verdade') = 1 and v_t not like '%Livre ela não está%', v_t);

    -- o serviço novo, no encaixe do motor sobre o plano de agora
    v_res := pg_temp.igual(v_res, 'H8 "um serviço de 2 dias, quando dá?": 2 pessoas (a equipe sugerida), sex 13 e ter 17/11 (o João só tem lugar 1 dia por semana)',
      pg_temp.sim('{"dias": 2}', c_hoje) ->> 'texto',
      'Um serviço de 2 dias (conto 2 pessoas, 4 diárias, porque você não disse com quem): pelo plano de agora, cabe em sex 13 e ter 17/11, com João e Roberto; você abre e fecha.' || c_fim);
    v_res := pg_temp.igual(v_res, 'H9 com o Roberto: seg 09 e qua 11/11 (ter 03 e qua 04 não dão: a reserva do Lenine segura qui 05 e sex 06, e parar 2 dias não pode)',
      pg_temp.sim('{"dias": 2, "com_quem": ["Roberto"]}', c_hoje) ->> 'texto',
      'Um serviço de 2 dias com Roberto (são 2 diárias de equipe): pelo plano de agora, cabe em seg 09 e qua 11/11, com Roberto; você abre e fecha.' || c_fim);
    v_res := pg_temp.igual(v_res, 'H10 1 dia com o Roberto: ter 03/11 (o 1º dia que a agenda ainda pode mudar)',
      pg_temp.sim('{"dias": 1, "com_quem": ["Roberto"]}', c_hoje) ->> 'texto',
      'Um serviço de 1 dia com Roberto (é 1 diária de equipe): pelo plano de agora, cabe em ter 03/11, com Roberto; você abre e fecha.' || c_fim);
    v_res := pg_temp.igual(v_res, 'H11 você e o Roberto: com você o tempo todo o motor não marca (sem os seus dias em campo) e diz como cabe com você abrindo e fechando',
      pg_temp.sim('{"dias": 2, "com_quem": ["eu", "Roberto"]}', c_hoje) ->> 'texto',
      'Um serviço de 2 dias com você e Roberto (são 2 diárias de equipe; você não entra nessa conta): com você o tempo todo não consigo encaixar: '
      || 'não sei em que dias você fica em campo. Com você só abrindo e fechando, pelo plano de agora, cabe em seg 09 e qua 11/11, com Roberto; você abre e fecha.' || c_fim);
    v_res := pg_temp.igual(v_res, 'H12 meio dia com o João: a semana dele está tomada pela reserva, e o motor põe o Roberto no lugar (a frase diz)',
      pg_temp.sim('{"dias": 0.5, "com_quem": ["João"]}', c_hoje) ->> 'texto',
      'Um serviço de meio dia com João (é meia diária de equipe): pelo plano de agora, cabe em ter 03/11, com Roberto (no lugar de João); você abre e fecha.' || c_fim);
    v_res := pg_temp.igual(v_res, 'H13 5 dias: não cabe até o fim do horizonte, nem acima da carga de sempre',
      pg_temp.sim('{"dias": 5}', c_hoje) ->> 'texto',
      'Um serviço de 5 dias (conto 2 pessoas, 10 diárias, porque você não disse com quem): não cabe até ter 15/12 com a equipe de agora, nem acima da carga de sempre.' || c_fim);
    v_res := pg_temp.igual(v_res, 'H14 alguém sem os dias na agenda (o Mickael): não dá para encaixar, e a frase diz por quê',
      pg_temp.sim('{"dias": 2, "com_quem": ["Mickael"]}', c_hoje) ->> 'texto',
      'Um serviço de 2 dias com Mickael (são 2 diárias de equipe): não sei em que dias Mickael vem, então não consigo encaixar.' || c_fim);
    -- a coerência: nenhum serviço simulado pega de alguém mais do que o livre diz
    for x in select y from jsonb_array_elements('[{"dias": 0.5}, {"dias": 1}, {"dias": 2}, {"dias": 3}, {"dias": 1, "com_quem": ["Roberto"]},
                                                 {"dias": 2, "com_quem": ["Roberto"]}, {"dias": 1.5, "com_quem": ["João"]},
                                                 {"dias": 2, "com_quem": ["João", "Roberto"]}]'::jsonb) y loop
      r := pg_temp.sim(x, c_hoje);
      if not coalesce((r #>> '{dados,encaixe,cabe}')::boolean, false) then
        v_q := v_q || format('[%s não coube] ', x);
      end if;
      v_q := v_q || coalesce(nullif(pg_temp.quebras(r #> '{dados,encaixe}', v_lv), ''), '');
    end loop;
    v_res := pg_temp.ok(v_res, 'H15 coerência: 8 serviços simulados cabem, e nenhum pega de alguém, em semana nenhuma, mais do que o *livre* diz que ele tem livre',
      v_q = '', v_q);

    -- a equivalência com o motor: a OS de verdade com os mesmos dados (2 dias, o Roberto o dia todo, você abre e fecha, nada a
    -- comprar, o sinal pago) cai nos mesmos dias e com as mesmas pessoas na agenda_propor (escopo 'os', sem gravar)
    insert into public.clients (id, type, name) values ('c4000000-0000-4000-8000-000000000901', 'individual', 'Daniel');
    insert into public.vessels (id, client_id, name, asset_type)
    values ('f4000000-0000-4000-8000-000000000901', 'c4000000-0000-4000-8000-000000000901', 'Lancha D', 'Lancha');
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                       created_at, updated_at, converted_to_os_at, grand_total)
    values ('05000000-0000-4000-8000-000000000901', 'OS-00901', 'c4000000-0000-4000-8000-000000000901', 'f4000000-0000-4000-8000-000000000901',
            'approved', 'approved', 'repair', timestamptz '2026-10-28 12:00-03', timestamptz '2026-10-28 12:00-03',
            timestamptz '2026-10-28 12:00-03', 2160);
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                               unit_price_snapshot, line_total, created_at)
    values (md5('p2:servico:901')::uuid, '05000000-0000-4000-8000-000000000901', '5e000000-0000-4000-8000-000000000003',
            'Revisão do sistema elétrico', 'unit', 1, 2160, 2160, timestamptz '2026-10-28 12:00-03');
    insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status,
                                    paid_amount, balance_amount, is_deposit)
    values (md5('p2:sinal:901')::uuid, 'c4000000-0000-4000-8000-000000000901', '05000000-0000-4000-8000-000000000901', 'Sinal OS-00901',
            date '2026-10-28', date '2026-10-28', 500, 'paid', 500, 0, true);
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em,
                                        trecho, atualizado_por)
    values ('05000000-0000-4000-8000-000000000901', 2, 'dono', timestamptz '2026-10-28 18:00-03', 'abre_e_fecha',
            timestamptz '2026-10-28 18:00-03', 'dois dias com o Roberto, eu abro e fecho', c_admin);
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos)
    values ('05000000-0000-4000-8000-000000000901', c_rob::uuid, 'dia');
    r := public.agenda_propor('os', null, null, array['05000000-0000-4000-8000-000000000901'::uuid], '{}'::jsonb, false, 'motor', null,
                              c_hoje, (c_hoje + time '17:40') at time zone 'America/Sao_Paulo');
    x := public.agenda_encaixe_do_novo(2, jsonb_build_array(jsonb_build_object('payee_id', c_rob, 'nome', 'Roberto', 'eh_dono', false, 'turnos', 'dia')),
                                       'abre_e_fecha', c_hoje);
    v_t := (select string_agg(format('%s %s %s %s', a ->> 'dia', a ->> 'nome', a ->> 'turno', a ->> 'presenca'), ', '
                              order by a ->> 'dia', a ->> 'turno', a ->> 'presenca', a ->> 'nome')
              from jsonb_array_elements(r -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
             where i ->> 'op' = 'criar' and i ->> 'os' = '05000000-0000-4000-8000-000000000901');
    v_res := pg_temp.ok(v_res, 'H16 equivalência com o motor: a OS de verdade com os mesmos dados cai nos mesmos dias (seg 09 e qua 11/11), com o Roberto e você abrindo e fechando',
      (public.os_prontidao('05000000-0000-4000-8000-000000000901', c_hoje) ->> 'estado') = 'pronta'
      and v_t = '2026-11-09 Gustavo manha abertura, 2026-11-09 Roberto manha turno, 2026-11-09 Roberto tarde turno, '
                || '2026-11-11 Roberto manha turno, 2026-11-11 Gustavo tarde fechamento, 2026-11-11 Roberto tarde turno'
      and x -> 'dias' = '["2026-11-09", "2026-11-11"]'::jsonb and x ->> 'pessoas' = 'Roberto' and x ->> 'pontas' = 'você abre e fecha',
      coalesce(v_t, '(sem item)') || ' | ' || (x - 'texto')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── F. A carteira da Fase 2 (a semana de 03 a 06/11 publicada; o dono com os dias em campo) ──
  begin
    execute current_setting('agenda_teste.fase2');
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(c_hoje, '16:30');
    perform pg_temp.agora(c_hoje, '17:40');
    v_t := pg_temp.ver('livre', null, c_hoje);
    v_res := pg_temp.igual(v_res, 'F1 *livre* com o dono em campo: "você" entra na conta, o que ocupa (o nome com o número quando se repete), o pronto que ainda não tem lugar',
      v_t,
      'Livre de verdade (pelo plano de agora e pelos dias que cada um vem):' || E'\n'
      || '• Semana de 03 a 06/11 (seg 02 é Finados): você 1 dia e meio, João nada, Roberto nada.' || E'\n'
      || '• Semana de 09 a 13/11: você 3 dias e meio, Roberto 3 dias, João 1 dia e meio.' || E'\n'
      || '• Semana de 16 a 19/11 (sex 20 é Consciência Negra): você 3 dias, Roberto 2 dias e meio, João 1 dia.' || E'\n'
      || 'Ocupa a equipe: Vanderlei (ter 03 a qui 05/11, com Roberto), Rodrigo OS-00096 (ter 03/11, com você), Lenine (qua 04 a seg 09/11, com João e Roberto) e mais 1 (*agenda plano* mostra tudo).' || E'\n'
      || 'Não ocupam ninguém até destravar: Robson ORÇ-00083; 4 parados no cliente.' || E'\n'
      || 'Prontos, mas ainda sem lugar no plano (não entram na conta): Nelson e Giancarlo.' || E'\n'
      || 'Para um serviço novo, me diga quantos dias e com quem, que eu digo o 1º dia que cabe.');
    v_lv := public.agenda_livre_de_verdade(c_hoje, now());
    v_q := '';
    for x in select y from jsonb_array_elements('[{"dias": 1}, {"dias": 2}, {"dias": 2, "com_quem": ["eu", "Roberto"]},
                                                 {"dias": 1, "com_quem": ["João"]}, {"dias": 3, "com_quem": ["Roberto"]}]'::jsonb) y loop
      r := pg_temp.sim(x, c_hoje);
      if not coalesce((r #>> '{dados,encaixe,cabe}')::boolean, false) then
        v_q := v_q || format('[%s não coube] ', x);
      end if;
      v_q := v_q || coalesce(nullif(pg_temp.quebras(r #> '{dados,encaixe}', v_lv), ''), '');
    end loop;
    v_res := pg_temp.ok(v_res, 'F2 coerência na carteira da Fase 2: 5 serviços simulados (você no turno também) cabem dentro do livre de cada um',
      v_q = '', v_q);
    v_res := pg_temp.igual(v_res, 'F3 você e o Roberto, com você em campo: o motor põe você no turno',
      pg_temp.sim('{"dias": 2, "com_quem": ["eu", "Roberto"]}', c_hoje) ->> 'texto',
      'Um serviço de 2 dias com você e Roberto (são 4 diárias de equipe: você 2 e Roberto 2): pelo plano de agora, cabe em seg 09 a qua 11/11 (começa à tarde), com você e Roberto.' || c_fim);
    v_t := pg_temp.ver(null, 'semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'F4 *agenda* da Fase 2: o livre na 3ª linha, uma vez só, e as linhas do P1 no lugar (o resto desta semana, a semana que vem montada, a oferta)',
      pg_temp.linha(v_t, 3) = 'Livre de verdade: na semana de 03/11, você 1 dia e meio, João nada, Roberto nada; na de 09/11, você 3 dias e meio, Roberto 3 dias, João 1 dia e meio.'
      and pg_temp.vezes(v_t, 'Livre de verdade') = 1 and v_t not like '%Livre ela não está%'
      and pg_temp.linha(v_t, 1) like 'De hoje a sáb 31/10 não tem mais nada marcado%'
      and pg_temp.linha(v_t, 2) like 'A semana que vem (seg 02/11 a sáb 07/11): Vanderlei%', v_t);
    -- (a 1ª semana pela metade: na sexta 30/10 o congelado vai até ter 03/11)
    v_res := pg_temp.igual(v_res, 'F5 sex 30/10: a 1ª semana começa no 1º dia que a agenda ainda pode mudar ("De qua 04 a sex 06/11")',
      public.agenda_livre_de_verdade(date '2026-10-30', now()) #>> '{semanas,0,texto}',
      '• De qua 04 a sex 06/11: você 1 dia e meio, João nada, Roberto nada.');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── N. O que NÃO muda ──
  begin
    -- fora de ligado: *livre*, *agenda* e o serviço novo são os de antes, byte a byte (as definições de antes como pg_temp)
    foreach v_modo in array array['sombra', 'desligado'] loop
      perform pg_temp.modos(v_modo, v_modo);
      v_t := concat_ws(' || ', pg_temp.ver('livre', null, c_hoje), pg_temp.ver(null, 'semana', c_hoje), pg_temp.ver(null, 'proxima_semana', c_hoje),
                       pg_temp.sim('{"dias": 2}', c_hoje)::text, pg_temp.sim('{"dias": 2, "com_quem": ["eu", "Roberto"]}', c_hoje)::text);
      v_t2 := concat_ws(' || ',
                pg_temp.ver_antes(c_admin, null, null, 'livre', null, null, false, c_hoje) ->> 'texto',
                pg_temp.ver_antes(c_admin, 'semana', null, null, null, null, false, c_hoje) ->> 'texto',
                pg_temp.ver_antes(c_admin, 'proxima_semana', null, null, null, null, false, c_hoje) ->> 'texto',
                pg_temp.ver_antes(c_admin, null, null, null, null, '{"dias": 2}', false, c_hoje)::text,
                pg_temp.ver_antes(c_admin, null, null, null, null, '{"dias": 2, "com_quem": ["eu", "Roberto"]}', false, c_hoje)::text);
      v_res := pg_temp.igual(v_res, format('N1 %s: *livre*, *agenda*, *agenda semana que vem* e o serviço novo são os de antes, byte a byte', v_modo),
        v_t, v_t2);
    end loop;
    v_res := pg_temp.ok(v_res, 'N2 fora de ligado o livre de verdade é {fonte: projecao}, e o serviço novo continua "É projeção: não reserva nada."',
      public.agenda_livre_de_verdade(c_hoje, now()) ->> 'fonte' = 'projecao'
      and pg_temp.sim('{"dias": 2}', c_hoje) ->> 'texto' like '%no fim da fila, começa %. É projeção: não reserva nada.', null);
    -- ligado: agenda_semana continua com a fila em faixa no texto dela (quem troca as linhas é a agenda_ver)
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(c_hoje, '16:30');
    perform pg_temp.agora(c_hoje, '17:40');
    v_res := pg_temp.ok(v_res, 'N3 agenda_semana não muda: em ligado o texto dela ainda tem a fila em faixa (a troca é só na agenda_ver)',
      public.agenda_semana(null, null, c_hoje) ->> 'texto' like '%' || E'\n' || 'Livre ela não está: há 7 serviços aprovados%', null);
    -- nada é gravado; o mesmo texto duas vezes
    v_ret := pg_temp.retrato();
    v_t := concat_ws(' || ', pg_temp.ver('livre', null, c_hoje), pg_temp.ver(null, 'semana', c_hoje),
                     pg_temp.sim('{"dias": 2}', c_hoje) ->> 'texto', pg_temp.sim('{"dias": 3, "com_quem": ["Roberto"]}', c_hoje) ->> 'texto',
                     public.agenda_tela_semana('2026-11-03', c_hoje, (c_hoje + time '17:40') at time zone 'America/Sao_Paulo') ->> 'livre_de_verdade');
    v_t2 := concat_ws(' || ', pg_temp.ver('livre', null, c_hoje), pg_temp.ver(null, 'semana', c_hoje),
                      pg_temp.sim('{"dias": 2}', c_hoje) ->> 'texto', pg_temp.sim('{"dias": 3, "com_quem": ["Roberto"]}', c_hoje) ->> 'texto',
                      public.agenda_tela_semana('2026-11-03', c_hoje, (c_hoje + time '17:40') at time zone 'America/Sao_Paulo') ->> 'livre_de_verdade');
    v_res := pg_temp.ok(v_res, 'N4 nada é gravado (nenhuma tabela agenda_* muda: linhas e md5) e o mesmo texto duas vezes',
      pg_temp.retrato() = v_ret and md5(v_t) = md5(v_t2), null);
    v_res := pg_temp.igual(v_res, 'N5 a tela (Agenda › Semana) mostra a mesma linha do livre que a *agenda*',
      public.agenda_tela_semana('2026-11-03', c_hoje, (c_hoje + time '17:40') at time zone 'America/Sao_Paulo') ->> 'livre_de_verdade', c_linha);
    v_res := pg_temp.ok(v_res, 'N6 o livre custa menos de 2 s na bancada',
      (public.agenda_livre_de_verdade(c_hoje, now()) ->> 'ms')::int < 2000, public.agenda_livre_de_verdade(c_hoje, now()) ->> 'ms');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$cenarios$;

-- ── K. As cópias ─────────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  v_f1   text := coalesce(current_setting('agenda_teste.mig_leituras_fase1', true), '');
  v_f6   text := coalesce(current_setting('agenda_teste.mig_leituras_fase6', true), '');
  v_nome text;
  v_sig  text;
  v_fonte text;
  v_novo text;
begin
  if v_f1 = '' or v_f6 = '' then
    insert into _resultado values ('K0 as cópias só acrescentam os blocos "-- CORREÇÃO 29/10 (P2):"', true,
      'PULADO: sem agenda_teste.mig_leituras_fase1/mig_leituras_fase6 (rode pela bancada)');
    return;
  end if;
  foreach v_sig in array array['agenda_simular(numeric, jsonb, text, uuid, date)',
                               'agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)'] loop
    v_nome := split_part(v_sig, '(', 1);
    v_fonte := pg_temp.corpo(case when v_nome = 'agenda_ver' then v_f6 else v_f1 end, v_nome);
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = ('public.' || v_sig)::regprocedure;
    insert into _resultado values (
      format('K1 %s: sem os blocos "-- CORREÇÃO 29/10 (P2):", é o corpo de %s (com %s blocos)', v_nome,
             case when v_nome = 'agenda_ver' then '20261029100800' else '20261024160500' end,
             case when v_nome = 'agenda_ver' then 2 else 2 end),
      v_fonte is not null and pg_temp.sem_blocos(v_novo) = v_fonte
      and (select count(*) from regexp_matches(v_novo, '-- CORREÇÃO 29/10 \(P2\): fim', 'g')) = 2,
      format('fonte %s × novo sem blocos %s caracteres', length(v_fonte), length(pg_temp.sem_blocos(v_novo))));
  end loop;
end
$copia$;

-- ── P. Portas (sempre) ───────────────────────────────────────────────────────────────────────────────────
with f(sig) as (values
  ('public._agenda_meios_texto(integer)'), ('public._agenda_grade_de_agora(date)'),
  ('public.agenda_livre_de_verdade(date, timestamptz)'), ('public.agenda_encaixe_do_novo(numeric, jsonb, text, date)'),
  ('public.agenda_simular(numeric, jsonb, text, uuid, date)'), ('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)'))
insert into _resultado
select 'P1 anon não executa nenhuma das 6', not bool_or(has_function_privilege('anon', sig, 'execute')),
       string_agg(sig, ', ') filter (where has_function_privilege('anon', sig, 'execute'))
  from f
union all
select 'P2 o service_role executa as 6; authenticated (o painel) executa as 5 leituras, não a grade de agora (peça do motor)',
       bool_and(has_function_privilege('service_role', sig, 'execute')
                and has_function_privilege('authenticated', sig, 'execute') = (sig <> 'public._agenda_grade_de_agora(date)')),
       string_agg(sig, ', ') filter (where not (has_function_privilege('service_role', sig, 'execute')
                                               and has_function_privilege('authenticated', sig, 'execute') = (sig <> 'public._agenda_grade_de_agora(date)')))
  from f
union all
select 'P3 definer só o livre de verdade e o encaixe do serviço novo (conferem quem vê); o texto dos meios-dias IMMUTABLE, as outras STABLE; search_path fixo',
       bool_and(p.prosecdef = (p.proname in ('agenda_livre_de_verdade', 'agenda_encaixe_do_novo'))
                and p.provolatile = case when p.proname = '_agenda_meios_texto' then 'i' else 's' end
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'),
       string_agg(f.sig, ', ') filter (where p.prosecdef <> (p.proname in ('agenda_livre_de_verdade', 'agenda_encaixe_do_novo'))
                                          or p.provolatile <> case when p.proname = '_agenda_meios_texto' then 'i' else 's' end
                                          or coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=public%')
  from f join pg_proc p on p.oid = f.sig::regprocedure;

do $quem$
declare
  c_tec constant uuid := 'aa000000-0000-4000-8000-000000000002';
  v_l text;
  v_e text;
begin
  update public.agenda_config set modo_proposta = 'ligado' where id;
  v_l := pg_temp.como(c_tec, 'authenticated', $q$select public.agenda_livre_de_verdade('2026-10-29', '2026-10-29 17:40-03')::text$q$);
  v_e := pg_temp.como(c_tec, 'authenticated', $q$select public.agenda_encaixe_do_novo(2, '[]'::jsonb, null, '2026-10-29')::text$q$);
  insert into _resultado values ('P4 o técnico (com login, sem ser administrador nem financeiro) não vê o livre nem o encaixe (42501)',
    v_l like 'erro 42501: A agenda de produção é com o administrador.%' and v_e like 'erro 42501: A agenda de produção é com o administrador.%',
    v_l || ' | ' || v_e);
  insert into _resultado values ('P5 o service_role (o assistente pelo WhatsApp) vê os dois',
    pg_temp.como(null, 'service_role', $q$select public.agenda_livre_de_verdade('2026-10-29', '2026-10-29 17:40-03') ->> 'fonte'$q$) = 'simulacao'
    and pg_temp.como(null, 'service_role', $q$select (public.agenda_encaixe_do_novo(2, '[]'::jsonb, null, '2026-10-29') ->> 'ok')$q$) = 'true',
    null);
end
$quem$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
