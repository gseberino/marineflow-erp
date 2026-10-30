-- Prova da correção dos achados da revisão da Fase 7a (migration 20261031100980), sobre a carteira REAL de qui 29/10 (o replay; a
-- presença do dono do Lenine e do Vanderlei como em produção: abre e fecha), com e sem a equipe de 30/10 (Roberto, João e Mickael
-- fora; o Alex declarado pelo dono), e a fixture sintética da 7a onde o replay não tem o caso. Cada bloco diz o achado.
-- bancada: depende de 20261031100980
--
--   Z0  as portas das 5 funções novas
--   Z1  (achado 1) o aviso conta as ações do gestor — reparar, reestimar, estimar e a ficha segurada (equipe) — da vigia; a do dono
--       não; e o texto não repete o "*desfaz*" que a ação já diz
--   Z2  (achados 2, 11 e 22) a OS que a agenda pôs em aguardando peças ao tirá-la do plano pelo material não é "começada"; a que o
--       dono pôs, sim
--   Z3  (achado 3) o foco *agenda gestor*: o "Como eu conto" sempre no fim, nenhum título sem linha embaixo; _agenda_gestor_juntar
--   Z4  (achado 4) a chamada da equipe não cita quem só tem a diária cadastrada (o Mickael)
--   Z5  (achado 5) o "se aprovar" com 1 pessoa (a regra uma_pessoa), e o encaixe do novo também
--   Z6  (achado 6) o aviso diz o motivo do gestor (situacao, estimativa), não "outro motivo"
--   Z7  (achado 8) o comentário de modo_compre_ate diz o que o passo faz em teste
--   Z8  (achado 10) a memória da vigia: a situação não lê ações nem perguntas, a marca é a de sempre, a duração é lembrada na rodada
--       (uma conta por OS) e recalculada depois de uma escrita; a vigia ligada recalcula a prontidão menos
--   Z9  (achado 12) o job nos minutos ímpares; e as funções de antes da 7a que a migration recria: sem os blocos da Fase 7, o corpo
--       de antes da 7a
--   Z10 (achado 13) o prazo não trava o plano quando não tem o que aplicar
--   Z11 (achados 15 e 18) as perguntas do gestor numa linha só do fechamento (perda 75, a ficha primeiro, pergunta_ids), o registro
--       conta todas, o prazo vale depois; cada linha que perde hoje tem a sua vaga (até 3)
--   Z12 (achado 16) a dupla dita depois de marcar não corta os dias (pessoa-meio-dia); o orçamento que diminui corta
--   Z13 (achado 17) o *desfaz* do dono vale até a OS mudar: a revisão e o encaixe não a marcam de novo
--   Z14 (achado 19) o "compre até" de hoje vai como decisão (perda 80)
--   Z15 (achado 20) acima de 8 diárias, a pergunta não tem prazo nem opção padrão (o grande; a Kalmar que já começou)
--   Z16 (achado 21) a peça embutida não segura a OS: o orçamento aprovado com ela entra no encaixe
--   Z17 (achado 23) o *livre* com a regra teto_equipe: o dono fora da conta de técnico e o teto da equipe-semana
--   Z18 (achado 24) a suposição sem pergunta não vira linha vazia no aviso; a duração que o gestor pergunta trava a prontidão
--   Z19 (achados 9 e 15) a carteira de 29/10 com a equipe de 30/10 e o gestor ligado, sem resposta do dono: as perguntas chegam no
--       fechamento de sex, o prazo de ter 03/11 marca Nelson e MP; Lenine e Vanderlei marcados no 1º tique — 3 das 6 (o Giancarlo
--       espera o dono: mais de 8 diárias; o Flávio, o compressor; o Rodrigo-96, os dias do dono)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono: Z0 e Z7 leem; o resto usa o replay e só roda na bancada
--   (fora dela sai PULADO). Termina em ROLLBACK.
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
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select p.id from public.payees p where p.name = p_nome order by p.id limit 1
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.replay(p_modo text) returns void language plpgsql as $f$
begin
  if coalesce(current_setting('agenda_teste.ja_replay', true), '') <> 'on' then
    execute current_setting('agenda_teste.replay2910');
    insert into public.os_planejamento (service_order_id, dono_presenca)
    select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
    on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
    perform set_config('agenda_teste.ja_replay', 'on', true);
  end if;
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id;
end $f$;
-- a equipe de 30/10 (a correção da equipe em produção): Roberto, João e Mickael saem; o Alex, declarado pelo dono, todo dia útil
create function pg_temp.equipe_3010() returns void language plpgsql as $f$
begin
  update public.agenda_disponibilidade set substituida_em = timestamptz '2026-10-29 21:30-03' where substituida_em is null
     and payee_id in (select id from public.payees where name in ('Roberto', 'João', 'Mickael'));
  update public.agenda_equipe_contato set recebe_rotina = false, parou_em = timestamptz '2026-10-29 21:30-03',
         parou_motivo = 'saiu da equipe (o dono, 29/10)'
   where payee_id in (select id from public.payees where name in ('Roberto', 'João', 'Mickael')) and parou_em is null;
  insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho)
  select p.id, '{1,2,3,4,5}'::smallint[], null, 'disponivel', 'dono', 'você disse em 29/10', 'Alex todo dia útil'
    from public.payees p where p.name = 'Alex';
end $f$;
create function pg_temp.marcar(p_os uuid[], p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
declare
  v_os uuid[] := coalesce(p_os, (select array_agg(k.service_order_id) from public.os_carteira(p_hoje) k));
  v_p  jsonb;
begin
  v_p := public.agenda_propor('os', null, null, v_os, '{}'::jsonb, true, 'vigia', null, p_hoje, p_agora);
  return public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, p_hoje, p_agora);
end $f$;
-- O corpo de uma função numa migration (o texto entre "as $function$" e "$function$") e sem os blocos da Fase 7.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
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

-- ── Z0. As portas das 5 funções novas ─────────────────────────────────────────────────────────────────────
with f(sig, porta) as (values
  ('public._agenda_gestor_desfeito(uuid, timestamptz)', 'ninguem'),
  ('public._agenda_gestor_pessoa_meios(uuid, date, jsonb)', 'ninguem'),
  ('public._agenda_rodada_duracao_lembrar(text)', 'ninguem'),
  ('public._agenda_rodada_duracao_guardar(text, bigint, jsonb)', 'ninguem'),
  ('public._agenda_gestor_juntar(text[], integer, text)', 'leitura'))
insert into _resultado
select 'Z0 as portas: o desfeito, a conta em pessoa-meio-dia e a memória da duração para ninguém (nem o service_role); o juntar do foco para authenticated e service_role; nunca anon; invoker, search_path fixo',
       count(*) = 5
       and bool_and(not has_function_privilege('anon', f.sig, 'execute') and not p.prosecdef
                    and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'
                    and case f.porta
                          when 'leitura' then has_function_privilege('authenticated', f.sig, 'execute')
                                              and has_function_privilege('service_role', f.sig, 'execute')
                          else not has_function_privilege('authenticated', f.sig, 'execute')
                               and not has_function_privilege('service_role', f.sig, 'execute') end),
       string_agg(f.sig, ', ') filter (where p.prosecdef or has_function_privilege('anon', f.sig, 'execute'))
  from f join pg_proc p on p.oid = f.sig::regprocedure;

-- ── Z7. O comentário de modo_compre_ate (achado 8) ───────────────────────────────────────────────────────
insert into _resultado
select 'Z7 (achado 8) o comentário de modo_compre_ate diz que em teste nada é gravado em os_material (só o diário), não "grava sem cobrar"',
       d like '%sombra = em teste: a conta e a cobrança só no diário (agenda_gestor_dia.compras), nada é gravado em os_material%'
       and d not like '%grava sem cobrar%', d
  from (select col_description('public.agenda_config'::regclass,
                               (select attnum from pg_attribute where attrelid = 'public.agenda_config'::regclass
                                  and attname = 'modo_compre_ate')) as d) x;

-- ── Z3a. _agenda_gestor_juntar (sem fixture) ─────────────────────────────────────────────────────────────
insert into _resultado
select 'Z3a (achado 3) o juntar do foco: o fim sempre entra; o corte nunca termina num título (a linha com ":") — ele sai junto; sem fim, é o _agenda_juntar',
       public._agenda_gestor_juntar(array['Estado.', 'Fora: a, b.', 'Se aprovar:', '• Everton', '• Santo'], 60, 'Como eu conto: X.')
         = E'Estado.\nFora: a, b.\n(e mais 3 linhas)\nComo eu conto: X.'
       and public._agenda_gestor_juntar(array['Estado.', 'Se aprovar:', '• Everton'], 200, 'Como eu conto: X.')
         = E'Estado.\nSe aprovar:\n• Everton\nComo eu conto: X.'
       and public._agenda_gestor_juntar(array['Estado.'], 5, 'Como eu conto: X.') = 'Como eu conto: X.'
       and public._agenda_gestor_juntar(array['a', 'b'], 100, null) = public._agenda_juntar(array['a', 'b'], 100),
       public._agenda_gestor_juntar(array['Estado.', 'Fora: a, b.', 'Se aprovar:', '• Everton', '• Santo'], 60, 'Como eu conto: X.');

-- ── Z6. O porquê do gestor no aviso (achado 6) ────────────────────────────────────────────────────────────
insert into _resultado
select 'Z6 (achado 6) o aviso: "Nelson (falta saber se já começou)" e "Giancarlo (falta saber quantos dias)", não "outro motivo"',
       t = 'Ficaram de fora 2: Nelson (falta saber se já começou); Giancarlo (falta saber quantos dias).', t
  from (select public._agenda_aviso_fora_texto(
                 '[{"os": "00000000-0000-4000-8000-000000000112", "numero": "OS-00112", "cliente_curto": "Nelson", "motivo": "situacao"},
                   {"os": "00000000-0000-4000-8000-000000000130", "numero": "OS-00130", "cliente_curto": "Giancarlo", "motivo": "estimativa"}]'::jsonb,
                 '{}'::uuid[]) as t) x;

-- ── Z9. O job e as cópias (achado 12; as de antes da 7a) ──────────────────────────────────────────────────
do $copias$
declare
  v_me   text := coalesce(current_setting('agenda_teste.mig_correcao_fase7a', true), '');
  r      record;
  v_novo text;
  v_dif  text;
begin
  if v_me = '' then
    insert into _resultado values ('Z9 o job e as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  insert into _resultado values ('Z9a (achado 12) o job agenda-gestor reagendado nos minutos ímpares (7, 23, 37, 53: fora dos minutos pares do comprovantes-vigia e dos :00/:15/:30/:45 da vigia), pelo nome, só com pg_cron, com o mesmo comando',
    v_me like '%perform cron.schedule(''agenda-gestor'', ''7,23,37,53 10-23 * * 1-6'',%'
    and v_me like '%if not exists (select 1 from pg_extension where extname = ''pg_cron'') then%'
    and v_me like '%select public.agenda_gestor_rodar(public._hoje_brt(), now());$job$);%'
    and v_me not like '%perform cron.schedule(''agenda-gestor'', ''7,22,37,52%', null);
  -- as recriadas de antes da 7a: sem os blocos "-- FASE 7:" (os dos pacotes e os da correção), o corpo de antes da 7a, byte a byte
  for r in select * from (values
      ('agenda_fechamento_registrar', 'public.agenda_fechamento_registrar(date, jsonb, text, timestamptz)', 'agenda_teste.mig_conferencia_fase2'),
      ('agenda_aviso_pecas', 'public.agenda_aviso_pecas(date, timestamptz)', 'agenda_teste.mig_correcao_revisao'),
      ('agenda_livre_de_verdade', 'public.agenda_livre_de_verdade(date, timestamptz)', 'agenda_teste.mig_correcao_revisao'),
      ('_agenda_linhas_do_fechamento', 'public._agenda_linhas_do_fechamento(date)', 'agenda_teste.mig_correcao_revisao'),
      ('agenda_encaixe_do_novo', 'public.agenda_encaixe_do_novo(numeric, jsonb, text, date)', 'agenda_teste.mig_correcao_livre'),
      ('_agenda_aprontar_de', 'public._agenda_aprontar_de(jsonb, integer)', 'agenda_teste.mig_leituras_fase1'),
      ('agenda_textos_do_fechamento', 'public.agenda_textos_do_fechamento(date, date)', 'agenda_teste.mig_leituras_fase2'),
      ('_agenda_mudanca_texto', 'public._agenda_mudanca_texto(jsonb, boolean)', 'agenda_teste.mig_correcao_textos_fase6'),
      ('_agenda_rodada_marca', 'public._agenda_rodada_marca()', 'agenda_teste.mig_correcao_desempenho'),
      ('os_prontidao', 'public.os_prontidao(uuid, date)', 'agenda_teste.mig_correcao_desempenho'),
      ('os_duracao_sugerida', 'public.os_duracao_sugerida(uuid)', 'agenda_teste.mig_os_fase6')
    ) t(nome, assinatura, guc)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    if coalesce(current_setting(r.guc, true), '') = '' or pg_temp.corpo(current_setting(r.guc, true), r.nome) = ''
       or pg_temp.sem_fase7(v_novo) <> pg_temp.corpo(current_setting(r.guc, true), r.nome)
       or position(format('create or replace function public.%s(', r.nome) in v_me) = 0 then
      v_dif := concat_ws(', ', v_dif, r.nome);
    end if;
  end loop;
  insert into _resultado values ('Z9b as 11 recriadas de antes da 7a (o registro e as peças do aviso, o livre, as linhas e os textos do fechamento, o encaixe do novo, a rodada de aprontar, o texto da mudança, a marca da memória, a prontidão e a duração): sem os blocos da Fase 7, o corpo de antes da 7a, byte a byte',
    v_dif is null, coalesce(v_dif, 'todas'));
end
$copias$;

-- ── Z1 a Z19. Com o replay ───────────────────────────────────────────────────────────────────────────────
do $z$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-29';
  c_sex  constant date := date '2026-10-30';
  c_ter  constant date := date '2026-11-03';
  v_adm  uuid;
  v_len  uuid;
  v_van  uuid;
  v_nel  uuid;
  v_gia  uuid;
  v_jo   uuid;
  v_ids  uuid[];
  v_a    uuid;
  v_t    text;
  v_t2   text;
  v_n    int;
  v_n2   int;
  r      jsonb;
  r2     jsonb;
  x      jsonb;
  v_q    public.agenda_perguntas;
  v_lin  jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('Z1–Z19 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  perform pg_temp.replay('ligado');
  select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
  v_len := pg_temp.os('OS-00074');
  v_van := pg_temp.os('OS-00069');
  v_nel := pg_temp.os('OS-00112');
  v_gia := pg_temp.os('OS-00130');
  v_jo := pg_temp.pessoa('João');

  -- ── Z1. O aviso conta as ações do gestor (achado 1) ──
  begin
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto, depois)
    values (pg_temp.em(c_hoje, '10:00'), c_hoje, true, 'vigia', 'reparar', v_len, array[v_len], 'Lenine ter 03/11 de manhã: troquei João por Roberto (João não vem).', '{}'),
           (pg_temp.em(c_hoje, '10:01'), c_hoje, true, 'vigia', 'reestimar', v_van, array[v_van], 'Vanderlei (OS-00069): o orçamento mudou e agora estimo 4 dias (eram 6). Tirei ter 10/11.', '{}'),
           (pg_temp.em(c_hoje, '10:02'), c_hoje, true, 'vigia', 'estimar', v_nel, array[v_nel], 'Sem resposta sobre Nelson até sex 30/10 às 18:00: contei o serviço inteiro, 4 dias (estimativa minha). *desfaz Nelson* volta.', '{}'),
           (pg_temp.em(c_hoje, '10:03'), c_hoje, true, 'vigia', 'equipe', v_len, array[v_len], 'Não mandei a ficha de qui 05/11 a Roberto (Lenine): o dia é pela minha estimativa e você não viu a pergunta antes das 19:30. Fale com Roberto.', '{"motivo": "ficha_segurada"}'),
           (pg_temp.em(c_hoje, '10:04'), c_hoje, true, 'dono', 'estimar', v_gia, array[v_gia], 'Combinado, Giancarlo: contei 10 dias (estimativa minha). *desfaz Giancarlo* volta.', '{}');
    r := public._agenda_aviso_mudancas(c_hoje);
    select string_agg(a.tipo || ':' || a.origem, ' ' order by a.criada_em) into v_t
      from public.agenda_acoes a
     where a.id in (select y::uuid from jsonb_array_elements(r) g, jsonb_array_elements_text(g -> 'acao_ids') y)
       and a.texto not like 'TESTE%' and a.criada_em between pg_temp.em(c_hoje, '10:00') and pg_temp.em(c_hoje, '10:05');
    v_t2 := (select g ->> 'texto' from jsonb_array_elements(r) g
              where exists (select 1 from jsonb_array_elements_text(g -> 'acao_ids') y, public.agenda_acoes a
                             where a.id = y::uuid and a.tipo = 'estimar' and a.origem = 'vigia'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z1 (achado 1) o aviso conta as ações do gestor da vigia — reparar, reestimar, estimar e a ficha segurada (equipe) —, não a do dono; e o "*desfaz Nelson* volta" que a ação já diz não sai duas vezes',
    v_t = 'reparar:vigia reestimar:vigia estimar:vigia equipe:vigia'
    and v_t2 like 'Sem resposta sobre Nelson até sex 30/10 às 18:00: contei o serviço inteiro, 4 dias (estimativa minha). *desfaz Nelson* volta.'
    and v_t2 not like '%volta como estava%',
    coalesce(v_t, '-') || ' | ' || coalesce(v_t2, '-'));

  -- ── Z2. O aguardando peças que a agenda pôs (achados 2, 11 e 22) ──
  begin
    update public.service_orders set status = 'awaiting_parts' where id = v_van;
    -- a retirada do plano pelo material (a remarcação cancela as violadas pelo material e as outras como replanejadas, juntas)
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, criado_em, cancelada_em,
                                         cancelada_motivo)
    values (v_van, v_jo, date '2026-11-12', 'manha', 'turno', 'execucao', 'cancelada', 'motor', pg_temp.em(c_hoje, '09:00'),
            pg_temp.em(c_hoje, '10:00'), 'material'),
           (v_van, v_jo, date '2026-11-12', 'tarde', 'turno', 'execucao', 'cancelada', 'motor', pg_temp.em(c_hoje, '09:00'),
            pg_temp.em(c_hoje, '10:00'), 'replanejado');
    r := public._agenda_os_situacao(v_van, c_sex);
    r2 := public._agenda_gestor_perguntas_da_os(v_van, c_sex, pg_temp.em(c_sex, '16:53'), true);
    -- o dono tirou depois por outro motivo: a última retirada não é pelo material, e a OS volta a perguntar
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, criado_em, cancelada_em,
                                         cancelada_motivo)
    values (v_van, v_jo, date '2026-11-13', 'manha', 'turno', 'execucao', 'cancelada', 'dono', pg_temp.em(c_hoje, '09:00'),
            pg_temp.em(c_hoje, '11:00'), 'dono');
    x := public._agenda_os_situacao(v_van, c_sex);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z2 (achados 2, 11 e 22) o Vanderlei que a agenda pôs em aguardando peças ao tirá-lo do plano pelo material não é "começado" (sem a pergunta "já começou?"); tirado depois por outro motivo, volta a perguntar; o Nelson, que o dono pôs em aguardando peças, continua perguntando',
    not (r ->> 'pendente')::boolean and not (r2 ? 'chave')
    and (x ->> 'pendente')::boolean and x ->> 'tipo' = 'comecada'
    and (public._agenda_os_situacao(v_nel, c_hoje) ->> 'tipo') = 'comecada',
    r::text || ' | ' || coalesce(r2 ->> 'por', '-') || ' | ' || coalesce(x ->> 'tipo', '-'));

  -- ── Z3. O foco gestor (achado 3) ──
  begin
    perform pg_temp.marcar(null, c_hoje, pg_temp.em(c_hoje, '16:53'));
    perform public._agenda_gestor_perguntas(c_hoje, pg_temp.em(c_hoje, '16:53'));
    perform public._agenda_gestor_orcamentos(c_hoje, pg_temp.em(c_hoje, '16:53'));
    v_t := public.agenda_ver(null, null, null, 'gestor', null, null, false, c_hoje) ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  select count(*) into v_n
    from (select l, lead(l) over (order by o) as prox
            from unnest(string_to_array(v_t, E'\n')) with ordinality u(l, o)) z
   where right(z.l, 1) = ':' and coalesce(z.prox, '') not like '• %';
  v_res := pg_temp.ok(v_res, 'Z3 (achado 3) o foco gestor, ligado com a carteira marcada, as perguntas e os orçamentos: a última linha é o "Como eu conto" (com os parâmetros), nenhum título sem linha embaixo, e o resto cabe em texto_max',
    split_part(v_t, E'\n', array_length(string_to_array(v_t, E'\n'), 1)) like 'Como eu conto: estimativa pelo valor do orçamento (R$ % de mão de obra por diária, sem deslocamento);%'
    and v_n = 0
    and char_length(v_t) - char_length(split_part(v_t, E'\n', array_length(string_to_array(v_t, E'\n'), 1))) - 1
        <= (select texto_max from public.agenda_config where id),
    v_t);

  -- ── Z4. A chamada da equipe sem o Mickael (achado 4) ──
  begin
    r := public._agenda_gestor_equipe(c_hoje, pg_temp.em(c_hoje, '16:53'));
    perform pg_temp.equipe_3010();
    r2 := public._agenda_gestor_equipe(c_hoje, pg_temp.em(c_hoje, '17:08'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z4 (achado 4) a chamada da semana de 09/11 (só a semente) não cita o Mickael, que só tem a diária cadastrada; com a equipe declarada pelo dono (Alex), nada a perguntar',
    (r ->> 'criada')::boolean and r ->> 'texto' not like '%Mickael%' and (r ->> 'sumidos')::int = 0
    and not (r2 ->> 'criada')::boolean and r2 ->> 'motivo' in ('a equipe está dita', 'já perguntei desta semana'),
    coalesce(r ->> 'texto', '-') || ' | ' || r2::text);

  -- ── Z5. O "se aprovar" com 1 pessoa (achado 5) ──
  begin
    r := public._agenda_gestor_orcamentos(c_hoje, pg_temp.em(c_hoje, '16:53'));
    x := public.agenda_encaixe_do_novo(5, '[]'::jsonb, null, c_hoje);
    update public.agenda_config set marcar_regras = array_remove(marcar_regras, 'uma_pessoa') where id;
    r2 := public.agenda_encaixe_do_novo(5, '[]'::jsonb, null, c_hoje);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z5 (achado 5) o "se aprovar" reparte as diárias por equipe_padrao (1: o Everton, 55,5 diárias = 55,5 dias com 1 pessoa, e diz que pergunta os dias antes); o encaixe do novo com 1 pessoa cabe (seg 09/11), com 2 (equipe_sugerida, sem a regra) não',
    (r #>> '{lista,0,pessoas}')::int = 1
    and r #>> '{lista,0,texto}' like 'Everton (ORÇ-00117, R$ 120.020): pela estimativa, 55,5 dias com 1 pessoa; %. Se aprovar, pergunto os dias antes (mais de 8 diárias).'
    and (x ->> 'cabe')::boolean and x ->> 'de' = '2026-11-09' and not (r2 ->> 'cabe')::boolean,
    coalesce(r #>> '{lista,0,texto}', '-') || ' | ' || coalesce(x ->> 'texto', '-') || ' | ' || coalesce(r2 ->> 'texto', '-'));

  -- ── Z8. A memória da vigia (achado 10) ──
  begin
    perform public._agenda_rodada_abrir(c_hoje);
    r := public.os_duracao_sugerida(v_len);
    r2 := public.os_duracao_sugerida(v_len);
    x := public.os_duracao_sugerida(v_len);
    -- uma escrita no que a duração lê: a conta seguinte é nova (e muda, com a linha mais cara)
    update public.service_order_services set line_total = line_total * 2 where service_order_id = v_len;
    v_lin := public.os_duracao_sugerida(v_len);
    r2 := r2 || jsonb_build_object('_memoria', public._agenda_rodada_fechar());
    v_t := (v_lin = public.os_duracao_sugerida(v_len))::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z8a (achado 10) na rodada da vigia, com o gestor ligado, a duração do Lenine é calculada uma vez e lembrada (as 3 iguais à conta fresca); depois de uma escrita no orçamento dela, é calculada de novo (e igual à conta fresca)',
    r = (r2 - '_memoria') and r = x and r = public.os_duracao_sugerida(v_len)
    and (r2 #>> '{_memoria,duracao_calculadas}')::int = 2 and (r2 #>> '{_memoria,duracao_lembradas}')::int = 2
    and v_lin <> r and v_t = 'true',
    (r2 -> '_memoria')::text);
  begin
    update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
    perform public._agenda_rodada_abrir(c_hoje);
    perform public.os_duracao_sugerida(v_len);
    perform public.os_duracao_sugerida(v_len);
    r := public._agenda_rodada_fechar();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z8b com o gestor desligado, a duração não usa a memória (a conta de antes, barata)',
    not (r ? 'duracao_calculadas') and not (r ? 'duracao_lembradas'), r::text);
  -- a vigia ligada das 17:00: a prontidão de cada OS é recalculada só quando a rodada grava no que ela lê (não a cada pergunta ou
  -- ação): menos de 2 contas por OS da carteira (com o 7a P3, cada pergunta e ação gravada recalculava todas)
  begin
    r := public.agenda_vigiar(c_hoje, pg_temp.em(c_hoje, '17:00'));
    -- (a memória fica só na linha da rodada)
    v_t := (select (x.contagens -> 'memoria')::text from public.agenda_vigia_rodadas x where x.contagens ? 'memoria'
             order by x.rodou_em desc limit 1);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  select count(*) into v_n from public.os_carteira(c_hoje);
  v_res := pg_temp.ok(v_res, 'Z8c (achado 10) a vigia ligada das 17:00 com a carteira de 29/10: a prontidão é calculada menos de 2 vezes por OS da carteira, e a duração, lembrada',
    (v_t::jsonb ->> 'ligada')::boolean and (v_t::jsonb ->> 'calculadas')::int < 2 * v_n
    and (v_t::jsonb ->> 'duracao_lembradas')::int > 0,
    v_t || ' (carteira ' || v_n || ')');

  -- ── Z10. O prazo não trava sem o que aplicar (achado 13) ──
  begin
    select count(*) into v_n from pg_locks l where l.locktype = 'advisory' and l.pid = pg_backend_pid();
    r := public._agenda_gestor_vetos(c_hoje, pg_temp.em(c_hoje, '18:07'));
    v_n := (select count(*) from pg_locks l where l.locktype = 'advisory' and l.pid = pg_backend_pid()) - v_n;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform public._agenda_gestor_perguntas(c_hoje, pg_temp.em(c_hoje, '16:53'));
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.em(c_hoje, '17:30'), mostrada_via = 'fechamento'
     where estado = 'aberta' and modo = 'ligado' and tipo = 'situacao' and service_order_id = v_nel;
    select count(*) into v_n2 from pg_locks l where l.locktype = 'advisory' and l.pid = pg_backend_pid();
    r2 := public._agenda_gestor_vetos(c_sex, pg_temp.em(c_sex, '18:07'));
    v_n2 := (select count(*) from pg_locks l where l.locktype = 'advisory' and l.pid = pg_backend_pid()) - v_n2;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z10 (achado 13) o passo do prazo sem pergunta vencida não pega trava nenhuma (o *grava* e o *desfaz* do dono não esperam a rodada); com uma a aplicar, as duas travas (agenda_plano e agenda_vetos)',
    (r ->> 'aplicadas')::int = 0 and v_n = 0 and (r2 ->> 'aplicadas')::int = 1 and v_n2 >= 1,
    format('sem nada: %s travas novas; com o Nelson: %s travas novas, %s', v_n, v_n2, r2::text));

  -- ── Z11. As perguntas do gestor numa linha só do fechamento (achados 15 e 18) ──
  begin
    perform public._agenda_gestor_perguntas(c_hoje, pg_temp.em(c_hoje, '16:53'));
    -- a ficha de amanhã de um dia pela estimativa (o P11): a 1ª da linha, por inteiro
    perform public._agenda_gestor_perguntar('ficha_estimativa', format('ficha_estimativa:%s:%s', v_jo, c_sex), v_len,
      'Hoje às 19:30 a ficha de amanhã vai para João: Lenine, sex 30/10 o dia todo — dia 1 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.',
      '[{"n": 1, "texto": "Mande"}, {"n": 2, "texto": "Segure a ficha"}]'::jsonb, 1::smallint, pg_temp.em(c_hoje, '19:30'),
      1::smallint, 'ligado', pg_temp.em(c_hoje, '16:53'));
    v_lin := (select jsonb_agg(l) from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_hoje)) l
               where l ->> 'modo' = 'ligado' and l ->> 'tipo' = 'pergunta' and l ? 'pergunta_ids');
    x := v_lin -> 0;
    v_ids := array(select y::uuid from jsonb_array_elements_text(x -> 'pergunta_ids') y);
    r := public.agenda_fechamento_registrar(c_hoje, jsonb_build_array(jsonb_build_object('pergunta_id', x ->> 'pergunta_id',
                                                                                        'acao_ids', '[]'::jsonb,
                                                                                        'pergunta_ids', x -> 'pergunta_ids')),
                                            'fechamento', pg_temp.em(c_hoje, '17:31'));
    select count(*) into v_n from public.agenda_perguntas q where q.id = any (v_ids) and q.mostrada_vezes = 1
       and q.mostrada_em = pg_temp.em(c_hoje, '17:31');
    -- as vagas: a linha das perguntas (75) + a compra de hoje (80) + a decisão crítica (100) = 3 linhas que perdem hoje
    perform public._agenda_gestor_dia_gravar(c_hoje, 'compras',
      '[{"texto": "Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — compre até hoje.", "compre_ate": "2026-10-29", "urgente": false}]'::jsonb,
      pg_temp.em(c_hoje, '16:53'));
    insert into public.agenda_perguntas (tipo, chave, texto, versao_base, modo, perda_em, criada_em, recomendacao, opcoes)
    values ('onda', 'onda:teste-z11', 'Mudou muita coisa de uma vez: eu mudaria 3 serviços. 1) Faço tudo; 2) Só hoje e amanhã; 3) Não mudo nada.',
            0, 'ligado', c_sex, pg_temp.em(c_hoje, '16:53'), 1, '[{"n": 1, "texto": "Faço tudo"}, {"n": 2, "texto": "Só hoje e amanhã"}, {"n": 3, "texto": "Não mudo nada"}]');
    v_n2 := (public.agenda_textos_do_fechamento(c_hoje, c_sex) ->> 'vagas_garantidas')::int;
    -- o prazo (a ficha de hoje, com o prazo das 19:30, também vence: vale a 1, mande)
    r2 := public._agenda_gestor_vetos(c_sex, pg_temp.em(c_sex, '18:07'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z11a (achados 15 e 18) uma linha só com as perguntas do gestor que esperam o dono: perda 75, a ficha de hoje primeiro e por inteiro, depois as com prazo (Nelson, Flávio, MP) agrupadas pelo prazo, e o Giancarlo (sem prazo) em "Espero você"; pergunta_ids com as 5',
    jsonb_array_length(v_lin) = 1 and (x ->> 'perda')::int = 75
    and x ->> 'texto' like 'Agenda: Hoje às 19:30 a ficha de amanhã vai para João: Lenine, sex 30/10 o dia todo — dia 1 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele. Também, sem resposta até sex 30/10 18:00: %'
    and x ->> 'texto' like '%Nelson (OS-00112) 4 dias%' and x ->> 'texto' like '%Espero você: Giancarlo (OS-00130).'
    and cardinality(v_ids) = 5 and char_length(x ->> 'texto') <= 640,
    coalesce(x::text, '-'));
  v_res := pg_temp.ok(v_res, 'Z11b o fechamento que sai conta as 5 como mostradas (o registro com pergunta_ids); o prazo de sex 18:07 aplica as 3 dos dias (Nelson, Flávio e MP) — antes, nenhuma chegava ao dono e nada era aplicado',
    v_n = 5 and (r ->> 'perguntas')::int = 5 and (r2 ->> 'aplicadas')::int = 3 and (r2 ->> 'sem_mostrar')::int = 0
    and r2 -> 'os' @> jsonb_build_array(v_nel, pg_temp.os('OS-00104'), pg_temp.os('ORÇ-00095')),
    format('mostradas %s; registro %s; prazo %s', v_n, r::text, r2::text));
  v_res := pg_temp.ok(v_res, 'Z11c cada linha ligada que perde hoje tem a sua vaga, até 3: a decisão crítica (100), a compra de hoje (80) e as perguntas do gestor (75) = 3 vagas garantidas',
    v_n2 = 3, coalesce(v_n2::text, '-'));

  -- ── Z12. A dupla dita depois de marcar (achado 16) ──
  begin
    perform pg_temp.marcar(array[v_len], c_hoje, pg_temp.em(c_hoje, '16:53'));
    select count(*) into v_n from public.agenda_alocacoes a
     where a.service_order_id = v_len and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno';
    perform public.agenda_dupla_dita(v_adm, 'Lenine', true, c_hoje, pg_temp.em(c_hoje, '17:00'));
    r := public._agenda_gestor_corte(v_len, c_sex, pg_temp.em(c_sex, '16:53'));
    r2 := public._agenda_gestor_pessoa_meios(v_len, c_sex, public.agenda_meios_da_os(v_len, c_sex));
    x := public._agenda_gestor_revisao(c_sex, pg_temp.em(c_sex, '16:53'));
    select count(*) into v_n2 from public.agenda_alocacoes a
     where a.service_order_id = v_len and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno';
    -- o orçamento que diminui (sem a dupla) ainda corta
    update public.os_planejamento set dupla_dita = null, dupla_em = null, dupla_motivo = null, dupla_meios = null where service_order_id = v_len;
    update public.service_order_services set line_total = round(line_total * 2 / 3, 2) where service_order_id = v_len;
    v_lin := public._agenda_gestor_corte(v_len, c_sex, pg_temp.em(c_sex, '16:53'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z12 (achado 16) o Lenine marcado com 1 pessoa (12 meios-dias) e depois *Lenine com dupla*: a estimativa (3 dias × 2 pessoas) pede o que o plano tem (12 pessoa-meios-dias) — o corte não tira nada e a revisão não corta; com o orçamento menor (4 dias), o corte tira 4 meios-dias',
    v_n = 12 and (r ->> 'cortar')::int = 0 and (r2 ->> 'precisa')::int = 12 and (r2 ->> 'tem')::numeric = 12
    and (r2 ->> 'pessoas')::int = 2 and v_n2 = 12
    and not exists (select 1 from jsonb_array_elements(x #> '{reestimar,cortes}') c where (c ->> 'os')::uuid = v_len)
    and (v_lin ->> 'cortar')::int = 4,
    format('turnos %s → %s; corte %s; pessoa-meios %s; orçamento menor: %s', v_n, v_n2, r ->> 'cortar', r2::text, v_lin ->> 'texto'));

  -- ── Z13. O *desfaz* do dono vale (achado 17) ──
  begin
    perform pg_temp.marcar(array[v_len], c_hoje, pg_temp.em(c_hoje, '16:53'));
    select a.id into v_a from public.agenda_acoes a
     where a.service_order_id = v_len and a.executada and a.origem = 'vigia' and a.tipo in ('criar', 'promover_reserva', 'mover')
     order by a.criada_em desc, a.id desc limit 1;
    r := public.agenda_desfazer(v_a, v_adm, 'dono', c_sex, pg_temp.em(c_sex, '09:40'));
    v_t := public._agenda_gestor_desfeito(v_len, pg_temp.em(c_sex, '16:53'))::text;
    perform public._agenda_gestor_revisao(c_sex, pg_temp.em(c_sex, '16:53'));
    v_n := (select count(*) from public.agenda_alocacoes a where a.service_order_id = v_len and a.estado in ('publicada', 'fixada')
              and a.tipo <> 'reserva' and a.dia >= c_sex);
    -- o dono mexe na OS (o planejamento), meia hora depois: a trava sai
    update public.os_planejamento set atualizado_em = clock_timestamp() + interval '1 hour', dono_presenca = 'abre_e_fecha'
     where service_order_id = v_len;
    v_t2 := public._agenda_gestor_desfeito(v_len, clock_timestamp() + interval '2 hours')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z13 (achado 17) o dono desfaz a marcação do gestor (o Lenine sai da agenda): a revisão das 16:53 não o marca de novo (o *desfaz* vale até a OS mudar); o dono mexendo na OS, a trava sai',
    (r ->> 'ok')::boolean and v_t = 'true' and v_n = 0 and v_t2 = 'false',
    coalesce(r ->> 'texto', r::text) || ' | desfeito ' || coalesce(v_t, '-') || ' | marcados ' || coalesce(v_n::text, '-') || ' | depois ' || coalesce(v_t2, '-'));

  -- ── Z14. A compra de hoje vai como decisão (achado 19) ──
  begin
    perform public._agenda_gestor_dia_gravar(c_hoje, 'compras',
      '[{"texto": "Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — compre até hoje.", "compre_ate": "2026-10-29", "urgente": false}]'::jsonb,
      pg_temp.em(c_hoje, '16:53'));
    v_n := (select (l ->> 'perda')::int from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_hoje)) l where l ->> 'tipo' = 'compras');
    perform public._agenda_gestor_dia_gravar(c_hoje, 'compras',
      '[{"texto": "Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — compre até amanhã.", "compre_ate": "2026-10-30", "urgente": false}]'::jsonb,
      pg_temp.em(c_hoje, '16:54'));
    v_n2 := (select (l ->> 'perda')::int from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_hoje)) l where l ->> 'tipo' = 'compras');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z14 (achado 19) a linha das compras com "compre até" hoje vai como decisão (perda 80: ela tem a vaga dela); com "compre até" amanhã, 65 (como antes)',
    v_n = 80 and v_n2 = 65, format('%s / %s', v_n, v_n2));

  -- ── Z15. Acima de 8 diárias, sem prazo (achado 20) ──
  begin
    r := public._agenda_gestor_perguntas_da_os(v_gia, c_hoje, pg_temp.em(c_hoje, '16:53'), true);
    -- a Kalmar (OS-00032, 18,3 diárias, check-in em junho) volta do cliente: "já começou em …: quanto falta?", sem o "1 dia"
    update public.service_orders set status = 'approved' where id = pg_temp.os('OS-00032');
    r2 := public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00032'), c_ter, pg_temp.em(c_ter, '10:07'), true);
    x := public._agenda_gestor_perguntas_da_os(v_nel, c_hoje, pg_temp.em(c_hoje, '16:53'), true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z15 (achado 20) acima de 8 diárias o gestor não marca sozinho: o Giancarlo (10) e a Kalmar que já começou (18,3; antes "marco 1 dia para terminar") sem prazo, sem opção padrão, recomendando "eu digo"; o Nelson (4 dias) com o prazo de sempre',
    r -> 'veto_ate' = 'null'::jsonb and r -> 'opcao_padrao' = 'null'::jsonb and (r ->> 'recomendacao')::int = 2
    and r ->> 'texto' like '%É mais de 8 diárias: não marco sozinho. Me diga os dias.%'
    and r2 ->> 'variante' = 'rastro' and r2 -> 'veto_ate' = 'null'::jsonb and r2 -> 'opcao_padrao' = 'null'::jsonb
    and r2 ->> 'texto' like 'Kalmar (OS-00032) já começou em %: quanto falta? Pelo orçamento o serviço inteiro dá % diárias, mais de 8: não marco sozinho, espero você dizer quanto falta.%'
    and r2 ->> 'texto' not like '%marco 1 dia%'
    and x ->> 'veto_ate' is not null and (x ->> 'opcao_padrao')::int = 1,
    coalesce(r ->> 'texto', '-') || ' | ' || coalesce(r2 ->> 'texto', r2::text));

  -- ── Z16. A peça embutida não segura (achado 21) ──
  begin
    -- o orçamento do César (ORÇ-00119), aprovado e convertido: "pode ter peça junto" não segura mais a data
    update public.service_orders set status = 'open', quote_status = 'approved', converted_to_os_at = pg_temp.em(c_ter, '10:00'),
                                     signed_at = pg_temp.em(c_ter, '10:00')
     where id = pg_temp.os('ORÇ-00119');
    r := public._agenda_gestor_estimativa(pg_temp.os('ORÇ-00119'), c_ter);
    r2 := public._agenda_classe_agora(pg_temp.os('ORÇ-00119'), c_ter) - 'pront';
    x := public._agenda_gestor_perguntas_da_os(pg_temp.os('ORÇ-00119'), c_ter, pg_temp.em(c_ter, '10:07'), true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z16 (achado 21) o César (ORÇ-00119), aprovado com "pode ter peça junto": a estimativa vale (embutida_suposta), a classe não é a 4 da estimativa e nenhuma pergunta antes de marcar',
    (r ->> 'usa')::boolean and (r ->> 'embutida_suposta')::boolean and jsonb_array_length(r -> 'embutida') > 0
    and coalesce(r2 ->> 'motivo', '') <> 'estimativa' and not (x ? 'chave'),
    r::text || ' | ' || r2::text);

  -- ── Z17. O *livre* com o teto da equipe (achado 23) ──
  begin
    perform pg_temp.equipe_3010();
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho)
    select public._agenda_dono(null), '{1,2,3,4,5}'::smallint[], null, 'disponivel', 'dono', 'você disse em 29/10', 'em campo seg a sex';
    perform pg_temp.marcar(array[v_len, v_van], c_sex, pg_temp.em(c_sex, '08:07'));
    r := public.agenda_livre_de_verdade(c_sex, pg_temp.em(c_sex, '12:00'));
    update public.agenda_config set marcar_regras = array_remove(marcar_regras, 'teto_equipe') where id;
    r2 := public.agenda_livre_de_verdade(c_sex, pg_temp.em(c_sex, '12:00'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  select count(*) into v_n from jsonb_array_elements(r -> 'semanas') s, jsonb_array_elements(s -> 'pessoas') p
   where (p ->> 'eh_dono')::boolean;
  select count(*) into v_n2 from jsonb_array_elements(r2 -> 'semanas') s, jsonb_array_elements(s -> 'pessoas') p
   where (p ->> 'eh_dono')::boolean;
  v_res := pg_temp.ok(v_res, 'Z17 (achado 23) o *livre* com a linha do dono e a regra teto_equipe: o dono não entra como técnico ("Você não entra na conta…"); sem a regra, o de antes (o dono na conta)',
    v_n = 0 and v_n2 > 0 and r ->> 'texto_completo' like '%Você não entra na conta: em campo você acompanha, abre e fecha (o diagnóstico é com você).%'
    and r ->> 'texto' not like '%você %dia%',
    coalesce(r ->> 'texto', '-') || ' | ' || coalesce(r2 ->> 'texto', '-'));

  -- ── Z18. A linha vazia no aviso e a duração que trava (achado 24) ──
  begin
    v_t := public.agenda_aprontar(c_hoje) ->> 'texto';
    r := public.os_prontidao(v_gia, c_hoje);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z18 (achado 24) a rodada de aprontar (as perguntas do aviso) não tem a linha vazia do Lenine (só a suposição "sem peça", que não pergunta); o Giancarlo, que o gestor pergunta antes de marcar, não é "pronto": a duração trava',
    v_t not like E'%: \n%' and v_t not like '%: ' and v_t not like '%Lenine (OS-00074): ' || E'\n%'
    and (select (e ->> 'bloqueia')::boolean from jsonb_array_elements(r -> 'restricoes') e where e ->> 'tipo' = 'duracao')
    and r ->> 'estado' <> 'pronta',
    v_t || ' | ' || (r ->> 'estado'));

  -- ── Z19. A semana com a equipe de 30/10 e o gestor ligado, sem resposta do dono (achados 9 e 15) ──
  begin
    perform pg_temp.equipe_3010();
    update public.agenda_config set marcar_sozinho_desde = pg_temp.em(c_sex, '08:00') where id;
    perform public.agenda_gestor_rodar(c_sex, pg_temp.em(c_sex, '08:07'));
    perform public.agenda_gestor_rodar(c_sex, pg_temp.em(c_sex, '16:53'));
    -- o fechamento das 17:30 sai com as linhas que cabem nas vagas (o Secretário cheio: só as garantidas)
    r := public.agenda_textos_do_fechamento(c_sex, c_ter);
    v_lin := (select jsonb_agg(l order by (l ->> 'perda')::int desc, l ->> 'tipo', l ->> 'texto')
                from (select l from jsonb_array_elements(r -> 'linhas') l where l ->> 'modo' = 'ligado'
                       order by (l ->> 'perda')::int desc, l ->> 'tipo', l ->> 'texto' limit (r ->> 'vagas_garantidas')::int) s);
    perform public.agenda_fechamento_registrar(c_sex, (select jsonb_agg(jsonb_build_object('pergunta_id', l ->> 'pergunta_id',
                                                                                         'acao_ids', coalesce(l -> 'acao_ids', '[]'),
                                                                                         'pergunta_ids', coalesce(l -> 'pergunta_ids', '[]')))
                                                         from jsonb_array_elements(v_lin) l),
                                               'fechamento', pg_temp.em(c_sex, '17:31'));
    x := public.agenda_gestor_rodar(c_ter, pg_temp.em(c_ter, '18:07'));
    select string_agg(n, ',' order by n) into v_t
      from unnest(array['OS-00074', 'OS-00069', 'OS-00130', 'OS-00112', 'OS-00104', 'OS-00096']) n
     where public._agenda_os_tem_dia(pg_temp.os(n), c_ter);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'Z19 (achados 9 e 15) a carteira de 29/10, a equipe de 30/10 (o Alex) e o gestor ligado sex 08:00, sem resposta do dono: o fechamento de sex leva as perguntas do gestor numa vaga própria; o prazo de ter 03/11 18:07 aplica Nelson, Flávio e MP; com mão de obra e sem espera do cliente, 3 das 6 com data (Lenine, Vanderlei e Nelson; o Giancarlo espera o dono — mais de 8 diárias —, o Flávio, o compressor, e o Rodrigo-96, os seus dias em campo). Antes da correção, 2 das 6 e nenhuma pergunta vista',
    exists (select 1 from jsonb_array_elements(v_lin) l where l ->> 'tipo' = 'pergunta' and (l ->> 'perda')::int = 75)
    and (x #>> '{contagens,vetos,aplicadas}')::int = 3 and v_t = 'OS-00069,OS-00074,OS-00112',
    coalesce(v_t, '-') || ' | vetos ' || coalesce(x #>> '{contagens,vetos}', '-') || ' | linhas ' || coalesce(left(v_lin::text, 600), '-'));

  perform pg_temp.gravar(v_res);
end
$z$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
