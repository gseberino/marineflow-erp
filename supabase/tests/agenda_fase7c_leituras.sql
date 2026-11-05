-- Prova das leituras de quem faz o quê da Agenda de Produção, Fase 7c (pacote P6): o foco habilidades (quem faz o quê na equipe, o que
-- cada OS pede, o responsável, o que eu teria mudado em teste e as medidas; com uma OS, só o bloco dela), o foco no agenda_ver, a linha da
-- semana com o fora habilidade e o porquê "falta quem o serviço pede" no foco gestor e no aviso do gestor (migration 20261102100500;
-- spec-fase7c §5.6, §6.7, §8.3 agenda_fase7c_leituras.sql, R5.1-6, R5.3-6, R5.6).
-- bancada: depende de 20261102100500
--
--   L0  as portas: o foco definer, do painel e do service_role (a porta dentro), nunca anon; agenda_ver invoker com as de antes; as 4
--       recriadas com as portas de antes
--   L1real a equipe real (só o Alex e o dono): sem proposta, o foco inteiro byte a byte; a proposta "Alex instala sozinho" antes de vista
--       ("espero você ver a pergunta"), vista ("espero você até qui 05/11") e depois do prazo ("vale desde sex 06/11"), o R5.1-6; a OS
--       (Lenine) com o Alex fazendo sozinho o que ela pede
--   L1  a sintética (as etiquetas dos testes M e V): o foco byte a byte em desligado, em teste e ligado (só a 1ª linha muda: §6.7); em
--       teste com a rodada (a proposta em teste, a conferência: "Em teste, hoje eu teria mudado: Ivo, ter 10/11 à tarde (poria Alex).");
--       ligado com a pergunta vista (o prazo; a proposta junto do que o dono disse); as OS marcadas primeiro, o número junto quando o nome
--       se repete, o responsável que fez o 1º dia; o corte pelas linhas de OS ("e mais N OS"), a linha "Para corrigir" sempre no fim, o
--       conteúdo até texto_max e o teto de 1.500
--   L1os o bloco da OS (com p_os): o que pede e de onde veio; o fechamento do dono que cobre o último dia (e a conta de quem vai sozinho
--       sem ele); o responsável; quem vai; quem faz sozinho o que ela pede e quem precisa de alguém junto, com o porquê (o "por que o
--       João não vai sozinho no Lenine?" do H76); os meios-dias sem quem o serviço pede; o que eu teria mudado nela; a OS que não pede
--       nada; a que só o dono faz
--   L2  a linha da semana: o fora habilidade no "Fora:"; sem ele, a de antes (a 20261025100500 rodada como pg_temp), byte a byte
--   L3  o determinismo: o foco duas vezes, o mesmo md5
--   L4  quem lê: a técnica logada recebe 42501 no agenda_ver e direto; o anon não chama; o admin logado (o painel) e o service_role leem
--   L5  o porquê do que ficou de fora: habilidade = "falta quem o serviço pede" (foco gestor, antes de "sem lugar na agenda"; aviso do
--       gestor); os outros motivos byte a byte as de antes (a 20261031100985 rodada como pg_temp)
--   L6  as cópias: tirado o bloco "-- FASE 7c:" de cada uma, as 5 recriadas vivas e as da migration são a origem, byte a byte
--   L7  agenda_ver: o foco habilidades (rota habilidades; com a OS pelo nome; a OS que não existe; sem p_hoje 22004; a leitura desligada);
--       o foco que não existe continua com a mensagem dos 19
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7c_leituras.sql
--   Seguro em produção: termina em ROLLBACK. L0 e L5 rodam em qualquer banco; L6 sai PULADO sem as migrations como texto; o resto usa as
--   fixtures e só roda na bancada (fora dela sai PULADO).
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
-- O texto sem os blocos "-- FASE 7c: … -- FASE 7c: fim" e sem as marcas de dentro "-- (7c … -- (7c: fim)" (as linhas de abrir e de
-- fechar saem junto).
create function pg_temp.sem_7c(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when (l ~ '^\s*-- FASE 7[cd]:' and l !~ '^\s*-- FASE 7[cd]: fim')
                                                     or (l ~ '^\s*-- \(7[cd] ' and l !~ '^\s*-- \(7[cd]: fim\)') then 1
                                                when l ~ '^\s*-- (FASE 7[cd]: fim|\(7[cd]: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7[cd]: fim|\(7[cd]: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou 'erro <estado>: <mensagem>'.
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
-- o conteúdo do foco (sem a última linha, a "Para corrigir") e a última linha
create function pg_temp.conteudo(p text) returns text language sql immutable as $f$
  select left(p, length(p) - position(E'\n' in reverse(p)))
$f$;
create function pg_temp.ultima(p text) returns text language sql immutable as $f$
  select right(p, position(E'\n' in reverse(p)) - 1)
$f$;

-- ── L0. As portas (sem fixture) ────────────────────────────────────────────────────────────────────────────────
with f(sig, quem, definer, vol) as (values
  ('public._agenda_ver_habilidades(date, timestamptz, uuid)', 'leitura', true, 's'),
  ('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)', 'leitura', false, 's'),
  ('public._agenda_linha_da_semana(uuid, jsonb, boolean, date)', 'leitura', false, 's'),
  ('public._agenda_gestor_motivo_texto(text)', 'leitura', false, 'i'),
  ('public._agenda_gestor_motivo_ordem(text)', 'leitura', false, 'i'),
  ('public._agenda_aviso_fora_texto(jsonb, uuid[])', 'ninguem', false, 's'))
insert into _resultado
select 'L0a o foco novo e as 5 recriadas com as portas certas (o foco definer, do painel e do service_role, com a porta dentro; agenda_ver, a linha da semana e os 2 do foco gestor do painel e do service_role, como antes; o texto do aviso de ninguém, como antes; nunca anon; search_path fixo)',
       count(p.oid) = 6
       and bool_and(p.prosecdef = f.definer and p.provolatile = f.vol and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and case f.quem
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute')
                                              and has_function_privilege('service_role', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute')
                               and not has_function_privilege('service_role', p.oid, 'execute') end),
       string_agg(format('%s def=%s vol=%s anon=%s auth=%s srv=%s', f.sig, p.prosecdef, p.provolatile,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);
insert into _resultado
select 'L0b o anon não chama o foco (nem pelo agenda_ver)',
       pg_temp.como(null, 'anon', 'select public._agenda_ver_habilidades(date ''2026-11-04'', timestamptz ''2026-11-04 17:40-03'')::text') like 'erro 42501%'
       and pg_temp.como(null, 'anon', 'select public.agenda_ver(null, null, null, ''habilidades'', null, null, false, date ''2026-11-04'')::text') like 'erro 42501%',
       pg_temp.como(null, 'anon', 'select public._agenda_ver_habilidades(date ''2026-11-04'', timestamptz ''2026-11-04 17:40-03'')::text');

-- ── L5. O porquê do que ficou de fora (sem fixture) ────────────────────────────────────────────────────────────────
do $l5$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_correcao2_fase7a', true), '');
  v_ord text[];
  v_dif text;
  v_fora jsonb;
  m text;
begin
  v_ord := array(select x from unnest(array['esperando o cliente', 'orçamento sem virar OS', 'esperando o sinal', 'precisa de você em campo',
                                            'material', 'escopo em aberto', 'esperando o barco ou o motorhome', 'esperando a sua decisão',
                                            'falta saber os dias', 'falta a 2ª pessoa', 'você desfez (me diga os dias para eu marcar de novo)',
                                            'falta quem o serviço pede', 'sem lugar na agenda', 'outro motivo']) x
                  order by public._agenda_gestor_motivo_ordem(x), x);
  v_res := pg_temp.ok(v_res, 'L5a o fora habilidade no foco gestor: "falta quem o serviço pede", no grupo logo antes de "sem lugar na agenda" (depois de "você desfez")',
    public._agenda_gestor_motivo_texto('habilidade') = 'falta quem o serviço pede'
    and public._agenda_gestor_motivo_ordem('falta quem o serviço pede') = public._agenda_gestor_motivo_ordem('você desfez (me diga os dias para eu marcar de novo)') + 1
    and public._agenda_gestor_motivo_ordem('sem lugar na agenda') = public._agenda_gestor_motivo_ordem('falta quem o serviço pede') + 1
    and v_ord[12] = 'falta quem o serviço pede',
    format('%s · ordem %s', public._agenda_gestor_motivo_texto('habilidade'), array_to_string(v_ord, ' > ')));
  v_fora := '[{"os": null, "numero": "OS-97173", "cliente_curto": "Caio", "motivo": "habilidade"},
              {"os": null, "numero": "OS-97172", "cliente_curto": "Bia", "motivo": "sem_encaixe"}]'::jsonb;
  v_res := pg_temp.ok(v_res, 'L5b o fora habilidade no aviso do gestor: "Ficaram de fora 2: Caio (falta quem o serviço pede); Bia (sem lugar na equipe)." (não "outro motivo")',
    public._agenda_aviso_fora_texto(v_fora, '{}') = 'Ficaram de fora 2: Caio (falta quem o serviço pede); Bia (sem lugar na equipe).',
    public._agenda_aviso_fora_texto(v_fora, '{}'));
  if v_mig = '' then
    v_res := pg_temp.ok(v_res, 'L5c os outros motivos como antes', true, 'PULADO: sem agenda_teste.mig_correcao2_fase7a (rode pela bancada)');
  else
    execute replace(pg_temp.inteira(v_mig, '_agenda_gestor_motivo_texto'), 'create or replace function public._agenda_gestor_motivo_texto(',
                    'create function pg_temp.motivo_antes(');
    execute replace(pg_temp.inteira(v_mig, '_agenda_gestor_motivo_ordem'), 'create or replace function public._agenda_gestor_motivo_ordem(',
                    'create function pg_temp.ordem_antes(');
    execute replace(pg_temp.inteira(v_mig, '_agenda_aviso_fora_texto'), 'create or replace function public._agenda_aviso_fora_texto(',
                    'create function pg_temp.aviso_fora_antes(');
    foreach m in array array['cliente', 'orcamento', 'sinal', 'padrao_do_dono', 'so_com_voce', 'dono', 'material', 'compra', 'compre_ate',
                             'sem_previsao', 'conferir_material', 'material_nao_conferido', 'escopo', 'bem', 'espera', 'nao_cabe', 'situacao',
                             'estimativa', 'duracao', 'dupla', 'desfeito', 'sem_encaixe', 'sem_reserva', 'fixar_nao_cabe', 'depois',
                             'fixar_recusado', 'atrasado', 'comprado_sem_previsao', 'compra_sem_prazo', 'peca_embutida', 'nao_antes', 'parada',
                             'congelada', 'fora_da_carteira', 'nao_achei', 'qualquer_outro', ''] loop
      if public._agenda_gestor_motivo_texto(m) is distinct from pg_temp.motivo_antes(m)
         or public._agenda_aviso_fora_texto(jsonb_build_array(jsonb_build_object('numero', 'OS-97171', 'cliente_curto', 'Lia', 'motivo', m),
                                                              jsonb_build_object('numero', 'OS-97174', 'cliente_curto', 'Duda', 'motivo', 'cliente')), '{}')
            is distinct from pg_temp.aviso_fora_antes(jsonb_build_array(jsonb_build_object('numero', 'OS-97171', 'cliente_curto', 'Lia', 'motivo', m),
                                                                       jsonb_build_object('numero', 'OS-97174', 'cliente_curto', 'Duda', 'motivo', 'cliente')), '{}') then
        v_dif := concat_ws(', ', v_dif, m);
      end if;
    end loop;
    foreach m in array array['esperando o cliente', 'orçamento sem virar OS', 'esperando o sinal', 'precisa de você em campo', 'material',
                             'escopo em aberto', 'esperando o barco ou o motorhome', 'esperando a sua decisão', 'falta saber os dias',
                             'falta a 2ª pessoa', 'você desfez (me diga os dias para eu marcar de novo)', 'sem lugar na agenda', 'outro motivo',
                             'qualquer coisa'] loop
      -- a ordem relativa dos grupos de antes não muda (o novo entra entre dois; o "não está na lista" continua 99)
      if (public._agenda_gestor_motivo_ordem(m) = 99) <> (pg_temp.ordem_antes(m) = 99)
         or exists (select 1 from unnest(array['esperando o cliente', 'material', 'falta a 2ª pessoa', 'sem lugar na agenda', 'outro motivo']) y
                     where (public._agenda_gestor_motivo_ordem(m) < public._agenda_gestor_motivo_ordem(y))
                           <> (pg_temp.ordem_antes(m) < pg_temp.ordem_antes(y))) then
        v_dif := concat_ws(', ', v_dif, 'ordem ' || m);
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'L5c os outros motivos (os 36 de antes e um que não existe) saem como antes, byte a byte, no foco gestor e no aviso do gestor; a ordem dos grupos de antes não muda (as de 20261031100985 rodadas como pg_temp)',
      v_dif is null, coalesce(v_dif, 'todos iguais'));
  end if;
  perform pg_temp.gravar(v_res);
end
$l5$;

-- ── L6. As cópias (só com as migrations como texto) ─────────────────────────────────────────────────────────────
do $l6$
declare
  v_esta text := coalesce(current_setting('agenda_teste.mig_leituras_fase7c', true), '');
  r      record;
  v_novo text;
  v_fonte text;
  v_dif  text;
  v_n    int := 0;
begin
  if v_esta = '' or coalesce(current_setting('agenda_teste.mig_rodada_fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_leituras_fase2', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_correcao2_fase7a', true), '') = '' then
    insert into _resultado values ('L6 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('agenda_ver', 'public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)', 'agenda_teste.mig_rodada_fase7a'),
      ('_agenda_linha_da_semana', 'public._agenda_linha_da_semana(uuid, jsonb, boolean, date)', 'agenda_teste.mig_leituras_fase2'),
      ('_agenda_gestor_motivo_texto', 'public._agenda_gestor_motivo_texto(text)', 'agenda_teste.mig_correcao2_fase7a'),
      ('_agenda_gestor_motivo_ordem', 'public._agenda_gestor_motivo_ordem(text)', 'agenda_teste.mig_correcao2_fase7a'),
      ('_agenda_aviso_fora_texto', 'public._agenda_aviso_fora_texto(jsonb, uuid[])', 'agenda_teste.mig_correcao2_fase7a')
    ) t(nome, assinatura, guc)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    v_fonte := pg_temp.corpo(current_setting(r.guc), r.nome);
    if v_fonte = '' or pg_temp.sem_7c(v_novo) <> v_fonte or pg_temp.sem_7c(pg_temp.corpo(v_esta, r.nome)) <> v_fonte
       or v_novo <> pg_temp.corpo(v_esta, r.nome)
       or (select count(*) from regexp_matches(v_novo, '-- FASE 7c: fim', 'g')) <> 1 then
      v_dif := concat_ws(', ', v_dif, r.nome);
    end if;
    v_n := v_n + 1;
  end loop;
  insert into _resultado values ('L6 as 5 recriadas (agenda_ver de 20261031100600, a linha da semana de 20261025100500, os 2 do foco gestor e o texto do aviso de 20261031100985): a viva é a da migration, e tirado o bloco "-- FASE 7c:" (um em cada: só inserção) é a origem, byte a byte',
    v_n = 5 and v_dif is null, coalesce(v_dif, 'todas'));
end
$l6$;

-- ── As fixtures e os ajudantes ─────────────────────────────────────────────────────────────────────────────────
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7c', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7a', true), '') <> ''
     and coalesce(current_setting('agenda_teste.replay2910', true), '') <> ''
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
create function pg_temp.modos7c(p_hab text, p_lid text, p_prop text) returns void language sql as $f$
  update public.agenda_config set modo_habilidade = p_hab, modo_lider = p_lid, modo_habilidade_propor = p_prop where id
$f$;
create function pg_temp.foco(p_dia date, p_hora text, p_os text default null) returns jsonb language sql as $f$
  select public._agenda_ver_habilidades(p_dia, pg_temp.em(p_dia, p_hora), case when p_os is not null then pg_temp.os(p_os) end)
$f$;
create function pg_temp.pergunta_aberta() returns uuid language sql stable as $f$
  select q.id from public.agenda_perguntas q
   where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta'
   order by q.criada_em desc, q.id desc limit 1
$f$;
-- uma alocação publicada (o plano que já existia), de turno, como o motor publica
create function pg_temp.publicar(p_numero text, p_nome text, p_dia date, p_turno text, p_presenca text default 'turno') returns void
language plpgsql as $f$
begin
  perform set_config('agenda.hoje', '2026-11-04', true);
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  values (pg_temp.os(p_numero), case when p_nome = 'dono' then public._agenda_dono(null) else pg_temp.pessoa(p_nome) end, p_dia,
          p_turno, p_presenca, 'execucao', 'publicada', 'motor', timestamptz '2026-11-02 16:30-03');
end $f$;
-- as linhas de um texto que começam por p (a 1ª)
create function pg_temp.linha(p_texto text, p text) returns text language sql immutable as $f$
  select l from unnest(string_to_array(p_texto, E'\n')) with ordinality u(l, o) where l like p || '%' order by o limit 1
$f$;

-- O foco da equipe real sem proposta (desligado), byte a byte.
create function pg_temp.real_desligado() returns text language sql immutable as $f$
  select array_to_string(array[
    'Quem faz o quê (desligado: a agenda não usa):',
    '• Você: comissiona Victron sozinho; instala sozinho e ensina; sobe no teto (padrão).',
    '• Alex: pode tudo, menos comissionar (padrão).',
    'Quem não tem nada marcado pode tudo, menos comissionar.',
    'O que as OS pedem:',
    '• Robson: quem sobe no teto (pela linha "Serviço de Substituição de Claraboia de Teto").',
    '• MP: quem sobe no teto (pela linha "Kit 5 — Conectividade Starlink") e quem instala sozinho com 220 V ou banco de bateria, no último dia (pela linha "Desmontagem do Gerador (cortesia)").',
    '• Kalmar (OS-00032): quem instala sozinho com 220 V ou banco de bateria e quem comissiona Victron, no último dia (pela linha "Posicionamento, alinhamento, base, coxins e fixação do gera…").',
    '• e mais 11 OS.',
    'Nos últimos 30 dias: 0 vezes alguém sozinho em serviço que pede outra pessoa; 0 trocas de responsável; 0 meios-dias seus em serviço que outro faria.',
    'Para corrigir, me diga numa frase (ex.: "o Alex é ajudante").'], E'\n')
$f$;
-- O foco da sintética (as etiquetas dos testes M e V) em desligado, byte a byte (§6.7: em teste e ligado só a 1ª linha muda).
create function pg_temp.sintetica_desligado() returns text language sql immutable as $f$
  select array_to_string(array[
    'Quem faz o quê (desligado: a agenda não usa):',
    '• Você: comissiona Victron sozinho; instala sozinho e ensina; sobe no teto (padrão).',
    '• Alex: pode tudo, menos comissionar (padrão).',
    '• Bruno: é novo: nunca vai sozinho (eu marquei: começou em 20/10, 3 diárias; vale desde ter 03/11).',
    '• João: é ajudante: não vai sozinho em serviço de risco (eu marquei: entrou em 29/09, 15 diárias; vale desde ter 03/11).',
    '• Rafael: pode tudo, menos comissionar (padrão).',
    '• Roberto: instala sozinho (eu marquei: 32 diárias desde 23/08; vale desde ter 03/11); não sobe no teto (você disse).',
    'Quem não tem nada marcado pode tudo, menos comissionar.',
    'O que as OS pedem:',
    '• Ivo: quem instala sozinho com 220 V ou banco de bateria, no último dia (pela linha "Instalação de carregador e inversor").',
    '• e mais 20 OS.',
    'Nos últimos 30 dias: 1 vez alguém sozinho em serviço que pede outra pessoa; 0 trocas de responsável; 0 meios-dias seus em serviço que outro faria.',
    'Para corrigir, me diga numa frase (ex.: "o João instala sozinho").'], E'\n')
$f$;

-- ── L1real. A equipe real (só o Alex e o dono; antes da sintética: a variante é escolhida quando a 7b carrega) ───────────────
do $l1real$
declare
  v_res jsonb := '[]'::jsonb;
  t1 text;
  t2 text;
  t3 text;
  t4 text;
  t5 text;
  t6 text;
  q  uuid;
begin
  if not pg_temp.na_bancada() or exists (select 1 from public.service_orders where service_order_number = 'OS-97101') then
    insert into _resultado values ('L1real a equipe real', true, 'PULADO: sem as fixtures da 7b e da 7c (rode pela bancada)');
    return;
  end if;
  begin
    perform set_config('agenda_teste.fase7b_equipe', 'real', true);
    execute current_setting('agenda_teste.fase7c');
    perform set_config('agenda_teste.fase7b_equipe', '', true);
    t1 := pg_temp.foco(date '2026-11-04', '17:40') ->> 'texto';
    -- a rodada de qua 04/11 às 16:10 propõe (ligado); o fechamento das 17:30 a mostra; a de qui 05/11 grava o prazo; a de sex 06/11 a faz valer
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    perform public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    t2 := pg_temp.foco(date '2026-11-04', '16:20') ->> 'texto';
    q := pg_temp.pergunta_aberta();
    update public.agenda_perguntas set mostrada_em = pg_temp.em(date '2026-11-04', '17:30'), mostrada_vezes = 1 where id = q;
    t3 := pg_temp.foco(date '2026-11-04', '17:40') ->> 'texto';
    perform public._agenda_habilidade_vetos(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:10'));
    t4 := (pg_temp.foco(date '2026-11-05', '16:20') ->> 'texto') || ' | ' || coalesce((select veto_ate::text from public.agenda_perguntas where id = q), '-');
    perform public._agenda_habilidade_vetos(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:10'));
    t5 := pg_temp.foco(date '2026-11-06', '16:20') ->> 'texto';
    t6 := pg_temp.foco(date '2026-11-06', '16:20', 'OS-00074') ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  v_res := pg_temp.ok(v_res, 'L1real sem proposta (os modos da 7c como nascem): o foco inteiro byte a byte — você, o Alex pelo padrão ("pode tudo, menos comissionar"), o que as OS pedem pela linha (o número junto do Kalmar, que se repete; "e mais 11 OS"), as medidas e o "Para corrigir"',
    t1 = pg_temp.real_desligado(), t1);
  v_res := pg_temp.ok(v_res, 'L1real a proposta antes de vista (R5.1-6): "• Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil; espero você ver a pergunta)." no lugar do padrão; o resto igual',
    pg_temp.linha(t2, '• Alex:') = '• Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil; espero você ver a pergunta).'
    and replace(t2, pg_temp.linha(t2, '• Alex:'), '• Alex: pode tudo, menos comissionar (padrão).')
        = replace(pg_temp.real_desligado(), '(desligado: a agenda não usa)', '(em teste: ainda escalo como antes)'),
    pg_temp.linha(t2, '• Alex:'));
  v_res := pg_temp.ok(v_res, 'L1real vista no fechamento de qua 04/11 às 17:30: "…; espero você até qui 05/11)." (o prazo de _agenda_veto_ate antes de a rodada gravá-lo); com o prazo gravado na rodada de qui 05/11, o mesmo',
    pg_temp.linha(t3, '• Alex:') = '• Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil; espero você até qui 05/11).'
    and pg_temp.linha(t4, '• Alex:') = pg_temp.linha(t3, '• Alex:') and t4 like '% | 2026-11-05 %',
    pg_temp.linha(t3, '• Alex:') || ' · ' || pg_temp.linha(t4, '• Alex:') || ' · ' || right(t4, 30));
  v_res := pg_temp.ok(v_res, 'L1real depois do prazo (a rodada de sex 06/11): "• Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil; vale desde sex 06/11)."',
    pg_temp.linha(t5, '• Alex:') = '• Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil; vale desde sex 06/11).',
    pg_temp.linha(t5, '• Alex:'));
  v_res := pg_temp.ok(v_res, 'L1real o bloco do Lenine com a equipe real: pede 220 V no último dia (pela linha), sem responsável fixo, sem dia marcado, e o Alex faz sozinho o que ela pede',
    t6 = array_to_string(array[
      'Lenine (OS-00074) — quem faz o quê (em teste: ainda escalo como antes):',
      '• Pede quem instala sozinho com 220 V ou banco de bateria, no último dia (pela linha "Substituição baterias - chumbo para litio").',
      '• Sem responsável fixo.',
      '• Ainda sem dia marcado.',
      '• Faz sozinho o que ela pede: Alex.',
      'Para corrigir, me diga numa frase (ex.: "o responsável do Lenine é o Alex" ou "o Lenine não precisa de quem instala sozinho com 220 V ou banco de bateria").'], E'\n'),
    t6);
  perform pg_temp.gravar(v_res);
end
$l1real$;

-- A sintética com as etiquetas dos testes M e V, uma vez; cada caso abaixo roda numa subtransação desfeita.
do $carga$
begin
  if not pg_temp.na_bancada() then
    return;
  end if;
  perform set_config('agenda_teste.fase7c_etiquetas', 'mv', true);
  execute current_setting('agenda_teste.fase7c');
  perform set_config('agenda_teste.fase7c_etiquetas', '', true);
end
$carga$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97171')
     and exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97101')
$f$;

-- ── L1. O foco na sintética ─────────────────────────────────────────────────────────────────────────────────
do $l1$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  t_d   text;
  t_s   text;
  t_l   text;
  t_r   text;
  t_v   text;
  t_c   text;
  t_m   text;
  v_os  jsonb;
  v_n   int;
  v_tam text := '';
  v_ok  boolean := true;
  t     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('L1 o foco na sintética', true, 'PULADO: sem as fixtures da 7b e da 7c (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos7c('desligado', 'desligado', 'desligado');
    v := pg_temp.foco(date '2026-11-04', '17:40');
    t_d := v ->> 'texto';
    v_os := v #> '{dados,os}';
    v_n := jsonb_array_length(v #> '{dados,pessoas}');
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    t_s := pg_temp.foco(date '2026-11-04', '17:40') ->> 'texto';
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    t_l := pg_temp.foco(date '2026-11-04', '17:40') ->> 'texto';
    -- em teste com a rodada: a proposta em teste e a conferência (o fechamento do dono não cobre: a 179 viola no último meio-dia)
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    perform public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    perform public._agenda_habilidade_conferir(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    t_r := pg_temp.foco(date '2026-11-04', '17:40') ->> 'texto';
    -- com o teto menor, o corte vai até o padrão e o resumo das OS, e a linha "Para corrigir" fica
    update public.agenda_config set texto_max = 700 where id;
    t_c := pg_temp.foco(date '2026-11-04', '17:40') ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- ligado com a pergunta vista: a proposta do Rafael junto do que o dono disse dele (não sobe no teto)
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, trecho, vale_desde, criado_em)
    values (pg_temp.pessoa('Rafael'), 'altura', 0, 'dono', 'vale', 'você disse', 'o Rafael não sobe no teto',
            pg_temp.em(date '2026-11-03', '09:00'), pg_temp.em(date '2026-11-03', '09:00'));
    perform public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    update public.agenda_perguntas set mostrada_em = pg_temp.em(date '2026-11-04', '17:30'), mostrada_vezes = 1
     where id = pg_temp.pergunta_aberta();
    t_v := pg_temp.foco(date '2026-11-04', '17:40') ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o responsável que fez o 1º dia e o que o dono disse (o Edu e o Fábio, que pede o que o dono disse), os dois marcados na qui 12/11
    -- (vêm logo depois do Ivo, a marcada antes)
    update public.os_planejamento set lider_payee_id = pg_temp.pessoa('Alex'), lider_em = pg_temp.em(date '2026-11-04', '09:00'),
                                      lider_trecho = 'no Fábio o responsável é o Alex'
     where service_order_id = pg_temp.os('OS-97176');
    perform pg_temp.publicar('OS-97175', 'Roberto', date '2026-11-12', 'manha');
    perform pg_temp.publicar('OS-97176', 'Alex', date '2026-11-12', 'tarde');
    update public.agenda_config set texto_max = 1400 where id;
    t_m := pg_temp.foco(date '2026-11-04', '17:40') ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  v_res := pg_temp.ok(v_res, 'L1a desligado: o foco inteiro byte a byte (§6.7) — "(desligado: a agenda não usa)", você e as 5 pessoas da grade (a etiqueta do gestor com "vale desde ter 03/11", o que o dono disse "(você disse)", o padrão), o que vale para quem não tem nada, a OS marcada primeiro (a 179) e "e mais 20 OS", as medidas e o "Para corrigir" com o ajudante',
    t_d = pg_temp.sintetica_desligado(), t_d);
  v_res := pg_temp.ok(v_res, 'L1b em teste e ligado: só a 1ª linha muda — "(em teste: ainda escalo como antes):" e "(já escalo por isso):"',
    t_s = replace(pg_temp.sintetica_desligado(), '(desligado: a agenda não usa)', '(em teste: ainda escalo como antes)')
    and t_l = replace(pg_temp.sintetica_desligado(), '(desligado: a agenda não usa)', '(já escalo por isso)'),
    pg_temp.linha(t_s, 'Quem faz') || ' · ' || pg_temp.linha(t_l, 'Quem faz'));
  v_res := pg_temp.ok(v_res, 'L1c em teste com a rodada: a proposta em teste no lugar do padrão ("• Alex: instala sozinho (em teste, eu marcaria: você disse que ele vem todo dia útil)."; o Rafael ajudante), a etiqueta que vale fica (o Roberto); "Em teste, hoje eu teria mudado: Ivo, ter 10/11 à tarde (poria Alex)."; o corte tira as OS (uma linha só: "21 OS pedem alguém em especial") e a linha do padrão, nunca as medidas',
    t_r = array_to_string(array[
      'Quem faz o quê (em teste: ainda escalo como antes):',
      '• Você: comissiona Victron sozinho; instala sozinho e ensina; sobe no teto (padrão).',
      '• Alex: instala sozinho (em teste, eu marcaria: você disse que ele vem todo dia útil).',
      '• Bruno: é novo: nunca vai sozinho (eu marquei: começou em 20/10, 3 diárias; vale desde ter 03/11).',
      '• João: é ajudante: não vai sozinho em serviço de risco (eu marquei: entrou em 29/09, 15 diárias; vale desde ter 03/11).',
      '• Rafael: é ajudante: não vai sozinho em serviço de risco (em teste, eu marcaria: entrou em 01/09, ainda sem diária).',
      '• Roberto: instala sozinho (eu marquei: 32 diárias desde 23/08; vale desde ter 03/11); não sobe no teto (você disse).',
      'O que as OS pedem: 21 OS pedem alguém em especial (me pergunte por uma).',
      'Em teste, hoje eu teria mudado: Ivo, ter 10/11 à tarde (poria Alex).',
      'Nos últimos 30 dias: 1 vez alguém sozinho em serviço que pede outra pessoa; 0 trocas de responsável; 0 meios-dias seus em serviço que outro faria.',
      'Para corrigir, me diga numa frase (ex.: "o João instala sozinho").'], E'\n'),
    t_r);
  v_res := pg_temp.ok(v_res, 'L1d ligado com a pergunta vista: a proposta com o prazo e junto do que o dono disse — "• Rafael: é ajudante: não vai sozinho em serviço de risco (eu marquei: entrou em 01/09, ainda sem diária; espero você até qui 05/11); não sobe no teto (você disse)." e "• Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil; espero você até qui 05/11)."',
    pg_temp.linha(t_v, '• Rafael:') = '• Rafael: é ajudante: não vai sozinho em serviço de risco (eu marquei: entrou em 01/09, ainda sem diária; espero você até qui 05/11); não sobe no teto (você disse).'
    and pg_temp.linha(t_v, '• Alex:') = '• Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil; espero você até qui 05/11).',
    pg_temp.linha(t_v, '• Rafael:') || ' · ' || pg_temp.linha(t_v, '• Alex:'));
  v_res := pg_temp.ok(v_res, 'L1e as OS: as 21 da carteira que pedem alguém em especial, as marcadas primeiro (a 179; com a Edu e o Fábio marcados na qui 12/11, eles logo depois), depois pelo número; as que não pedem nada fora (a 174 e a 178, de 12 V; o Flávio); o que o dono disse ("(você disse)") e o responsável que o dono disse ou que fez o 1º dia ("Edu: …; responsável: Roberto (fez o 1º dia)."; "Fábio: …; responsável: Alex (você disse)."). O número junto do nome que se repete está no L1real (o Kalmar)',
    jsonb_array_length(v_os) = 21 and v_os -> 0 ->> 'numero' = 'OS-97179'
    and not exists (select 1 from jsonb_array_elements(v_os) x where x ->> 'numero' in ('OS-97174', 'OS-97178', 'OS-00104'))
    and v_os -> 1 ->> 'numero' = 'ORÇ-00083'
    and pg_temp.linha(t_m, '• Ivo:') is not null and pg_temp.linha(t_m, '• Robson:') is not null
    and position(pg_temp.linha(t_m, '• Edu:') in t_m) between position(pg_temp.linha(t_m, '• Ivo:') in t_m) and position(pg_temp.linha(t_m, '• Robson:') in t_m)
    and position('• Edu: quem instala sozinho com 220 V ou banco de bateria, no último dia (pela linha "Instalação de inversor 220 V"); responsável: Roberto (fez o 1º dia).' in t_m) > 0
    and position('• Fábio: quem instala sozinho com 220 V ou banco de bateria (você disse); responsável: Alex (você disse).' in t_m) > 0,
    concat_ws(' | ', jsonb_array_length(v_os), v_os -> 0 ->> 'numero', v_os -> 1 ->> 'numero', replace(t_m, E'\n', ' ⏎ ')));
  -- os tamanhos: o conteúdo até texto_max, a linha "Para corrigir" sempre a última, o teto de 1.500
  foreach t in array array[t_d, t_s, t_l, t_r, t_v, t_m] loop
    v_ok := v_ok and char_length(pg_temp.conteudo(t)) <= case when t = t_m then 1400 else 1000 end and char_length(t) <= 1500
            and pg_temp.ultima(t) like 'Para corrigir, me diga numa frase%';
    v_tam := v_tam || char_length(pg_temp.conteudo(t)) || '/' || char_length(t) || ' ';
  end loop;
  v_res := pg_temp.ok(v_res, 'L1f os tamanhos: o conteúdo até texto_max (1.000; 1.400 no L1e), a linha "Para corrigir" sempre a última, depois dele, e o teto de 1.500; com texto_max 700, saem as OS, o padrão e o resumo das OS (e só então o corte do fim), e o "Para corrigir" fica',
    v_ok and char_length(pg_temp.conteudo(t_c)) <= 700 and pg_temp.ultima(t_c) = 'Para corrigir, me diga numa frase (ex.: "o João instala sozinho").'
    and position('O que as OS pedem' in t_c) = 0 and position('Quem não tem nada marcado' in t_c) = 0,
    v_tam || '· 700: ' || char_length(pg_temp.conteudo(t_c)) || ' ' || replace(t_c, E'\n', ' ⏎ '));
  v_res := pg_temp.ok(v_res, 'L1g os dados: as 6 pessoas (você primeiro) com os níveis e o texto da linha; as 21 OS com as máscaras e o que pedem',
    v_n = 6 and (v #> '{dados,pessoas,0,eh_dono}')::boolean and v #>> '{dados,pessoas,0,texto}' like 'Você: %'
    and (select bool_and(x ? 'todos' and x ? 'ultimo' and x ? 'pede') from jsonb_array_elements(v_os) x),
    v_n::text);
  perform pg_temp.gravar(v_res);
end
$l1$;

-- ── L1os. O bloco da OS ─────────────────────────────────────────────────────────────────────────────────────
do $l1os$
declare
  v_res jsonb := '[]'::jsonb;
  t179 text;
  t179c text;
  tlen text;
  t175 text;
  t173 text;
  t174 text;
  v    jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('L1os o bloco da OS', true, 'PULADO: sem as fixtures da 7b e da 7c (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    t179 := pg_temp.foco(date '2026-11-04', '17:40', 'OS-97179') ->> 'texto';
    tlen := pg_temp.foco(date '2026-11-04', '17:40', 'OS-00074') ->> 'texto';
    t175 := pg_temp.foco(date '2026-11-04', '17:40', 'OS-97175') ->> 'texto';
    t173 := pg_temp.foco(date '2026-11-04', '17:40', 'OS-97173') ->> 'texto';
    t174 := pg_temp.foco(date '2026-11-04', '17:40', 'OS-97174') ->> 'texto';
    -- o fechamento que não cobre, em teste, com a conferência da rodada
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    perform public._agenda_habilidade_conferir(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    v := pg_temp.foco(date '2026-11-04', '17:40', 'OS-97179');
    t179c := v ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1os-a a 179 (o dono abre e fecha a ter 10/11): o que pede, "No último dia você fecha: isso cobre o que ele pede.", sem responsável fixo, quem vai pelo plano e, sem o último (coberto), "Qualquer um da equipe vai sozinho, menos Bruno (é novo: nunca vai sozinho)."',
    t179 = array_to_string(array[
      'Ivo (OS-97179) — quem faz o quê (já escalo por isso):',
      '• Pede quem instala sozinho com 220 V ou banco de bateria, no último dia (pela linha "Instalação de carregador e inversor").',
      '• No último dia você fecha: isso cobre o que ele pede.',
      '• Sem responsável fixo.',
      '• Quem vai (ter 10/11): você abre e fecha, João o dia todo.',
      '• Qualquer um da equipe vai sozinho, menos Bruno (é novo: nunca vai sozinho).',
      'Para corrigir, me diga numa frase (ex.: "o responsável do Ivo é o Alex" ou "o Ivo não precisa de quem instala sozinho com 220 V ou banco de bateria").'], E'\n'),
    t179);
  v_res := pg_temp.ok(v_res, 'L1os-b a 179 com o fechamento que não cobre, em teste: quem faz sozinho o que ela pede e quem precisa de alguém junto, o meio-dia marcado sem quem o serviço pede e o que eu teria mudado nela',
    t179c = array_to_string(array[
      'Ivo (OS-97179) — quem faz o quê (em teste: ainda escalo como antes):',
      '• Pede quem instala sozinho com 220 V ou banco de bateria, no último dia (pela linha "Instalação de carregador e inversor").',
      '• Sem responsável fixo.',
      '• Quem vai (ter 10/11): você abre e fecha, João o dia todo.',
      '• Fazem sozinhos o que ela pede: Alex, Rafael e Roberto. Precisam de alguém junto: Bruno (é novo: nunca vai sozinho) e João (é ajudante: não vai sozinho em serviço de risco).',
      '• ter 10/11 à tarde: João iria sozinho, e esse dia pede quem instala sozinho com 220 V ou banco de bateria.',
      'Em teste, hoje eu teria mudado: Ivo, ter 10/11 à tarde (poria Alex).',
      'Para corrigir, me diga numa frase (ex.: "o responsável do Ivo é o Alex" ou "o Ivo não precisa de quem instala sozinho com 220 V ou banco de bateria").'], E'\n')
    and (v #>> '{dados,os,faltas}')::int = 1 and jsonb_array_length(v #> '{dados,em_teste}') = 1,
    t179c);
  v_res := pg_temp.ok(v_res, 'L1os-c "por que o João não vai sozinho no Lenine?" (o H76): o Lenine pede 220 V no último dia, sem dia marcado, e "Precisam de alguém junto: Bruno (é novo: nunca vai sozinho) e João (é ajudante: não vai sozinho em serviço de risco)."',
    tlen = array_to_string(array[
      'Lenine (OS-00074) — quem faz o quê (já escalo por isso):',
      '• Pede quem instala sozinho com 220 V ou banco de bateria, no último dia (pela linha "Substituição baterias - chumbo para litio").',
      '• Sem responsável fixo.',
      '• Ainda sem dia marcado.',
      '• Fazem sozinhos o que ela pede: Alex, Rafael e Roberto. Precisam de alguém junto: Bruno (é novo: nunca vai sozinho) e João (é ajudante: não vai sozinho em serviço de risco).',
      'Para corrigir, me diga numa frase (ex.: "o responsável do Lenine é o Alex" ou "o Lenine não precisa de quem instala sozinho com 220 V ou banco de bateria").'], E'\n'),
    tlen);
  v_res := pg_temp.ok(v_res, 'L1os-d a 175 (o Roberto fez o 1º dia): "• Responsável: Roberto (fez o 1º dia, ter 03/11)."',
    pg_temp.linha(t175, '• Responsável:') = '• Responsável: Roberto (fez o 1º dia, ter 03/11).', t175);
  v_res := pg_temp.ok(v_res, 'L1os-e a 173 (comissionar Victron em todos os dias, pelo tipo do serviço): "Ninguém da equipe faz isso sozinho: fica com você no turno." e o porquê de cada um ("não comissiona")',
    pg_temp.linha(t173, '• Pede') = '• Pede quem comissiona Victron (pelo tipo do serviço).'
    and pg_temp.linha(t173, '• Ninguém') = '• Ninguém da equipe faz isso sozinho: fica com você no turno. Precisam de alguém junto: Alex (não comissiona), Bruno (é novo: nunca vai sozinho), João (não comissiona), Rafael (não comissiona) e Roberto (não comissiona).',
    t173);
  v_res := pg_temp.ok(v_res, 'L1os-f a 174 (12 V, não pede nada): "• Não pede ninguém em especial.", "Qualquer um da equipe vai sozinho, menos Bruno (é novo: nunca vai sozinho)." e o exemplo de pedir',
    pg_temp.linha(t174, '• Não pede') = '• Não pede ninguém em especial.'
    and pg_temp.linha(t174, '• Qualquer') = '• Qualquer um da equipe vai sozinho, menos Bruno (é novo: nunca vai sozinho).'
    and pg_temp.ultima(t174) = 'Para corrigir, me diga numa frase (ex.: "o responsável do Duda é o Alex" ou "o Duda pede quem sobe no teto").',
    t174);
  perform pg_temp.gravar(v_res);
end
$l1os$;

-- ── L2. A linha da semana com o fora habilidade ─────────────────────────────────────────────────────────────────
do $l2$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_leituras_fase2', true), '');
  v_p   uuid;
  v_p2  uuid;
  v_a   uuid;
  t1    text;
  t2    text;
  a1    text;
  a2    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('L2 a linha da semana', true, 'PULADO: sem as fixtures da 7b e da 7c (rode pela bancada)');
    return;
  end if;
  begin
    -- a semana publicada com o Lia, e de fora o Caio (habilidade) e o Duda (não cabe)
    insert into public.agenda_propostas (escopo, periodo, versao_base, modo, estado, fora, textos, parametros, criada_por, criada_em, expira_em)
    values ('semana', daterange(date '2026-11-09', date '2026-11-13', '[]'), 0, 'ligado', 'obsoleta',
            '[{"os": null, "numero": "OS-97173", "cliente_curto": "Caio", "motivo": "habilidade", "texto": "Caio (OS-97173): pede quem comissiona Victron em todos os dias e ninguém com isso fica livre junto nas próximas 6 semanas."},
              {"os": null, "numero": "OS-97174", "cliente_curto": "Duda", "motivo": "nao_cabe", "texto": "Duda (OS-97174): não cabe."}]'::jsonb,
            '{"titulo": "Semana de 09 a 13/11"}'::jsonb, '{"p_hoje": "2026-11-05"}'::jsonb, 'motor',
            pg_temp.em(date '2026-11-05', '16:30'), pg_temp.em(date '2026-11-06', '16:30'))
    returning id into v_p;
    insert into public.agenda_propostas (escopo, periodo, versao_base, modo, estado, fora, textos, parametros, criada_por, criada_em, expira_em)
    values ('semana', daterange(date '2026-11-09', date '2026-11-13', '[]'), 0, 'ligado', 'obsoleta',
            '[{"os": null, "numero": "OS-97174", "cliente_curto": "Duda", "motivo": "nao_cabe", "texto": "Duda (OS-97174): não cabe."}]'::jsonb,
            '{"titulo": "Semana de 09 a 13/11"}'::jsonb, '{"p_hoje": "2026-11-05"}'::jsonb, 'motor',
            pg_temp.em(date '2026-11-05', '16:30'), pg_temp.em(date '2026-11-06', '16:30'))
    returning id into v_p2;
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, proposta_id, texto, depois, criada_em)
    values (date '2026-11-05', true, 'vigia', 'publicar', pg_temp.os('OS-97171'), v_p, 'publiquei a semana (teste)',
            '{"alocacoes": [{"dia": "2026-11-09"}, {"dia": "2026-11-10"}, {"dia": "2026-11-11"}]}'::jsonb, pg_temp.em(date '2026-11-05', '16:30'))
    returning id into v_a;
    t1 := public._agenda_linha_da_semana(v_p, jsonb_build_array(v_a), true, date '2026-11-05');
    t2 := public._agenda_linha_da_semana(v_p2, jsonb_build_array(v_a), true, date '2026-11-05');
    if v_mig <> '' then
      execute replace(pg_temp.inteira(v_mig, '_agenda_linha_da_semana'), 'create or replace function public._agenda_linha_da_semana(',
                      'create function pg_temp.semana_antes(');
      a1 := pg_temp.semana_antes(v_p, jsonb_build_array(v_a), true, date '2026-11-05');
      a2 := pg_temp.semana_antes(v_p2, jsonb_build_array(v_a), true, date '2026-11-05');
    end if;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L2a o fora habilidade vai no "Fora:" da semana publicada, com o porquê do fora, na ordem da proposta',
    t1 = 'Agenda: publiquei a semana de 09 a 13/11: Lia (seg 09 a qua 11/11). Fora: Caio (pede quem comissiona Victron em todos os dias e ninguém com isso fica livre junto nas próximas 6 semanas) e Duda (preciso de você). *agenda plano* mostra tudo; *desfaz semana* volta.',
    t1);
  if v_mig = '' then
    v_res := pg_temp.ok(v_res, 'L2b sem o fora habilidade, a de antes', true, 'PULADO: sem agenda_teste.mig_leituras_fase2 (rode pela bancada)');
  else
    v_res := pg_temp.ok(v_res, 'L2b sem o fora habilidade, a linha é a de antes (a 20261025100500 rodada como pg_temp), byte a byte; a de antes deixava o Caio fora do "Fora:"',
      t2 = a2 and t2 = 'Agenda: publiquei a semana de 09 a 13/11: Lia (seg 09 a qua 11/11). Fora: Duda (preciso de você). *agenda plano* mostra tudo; *desfaz semana* volta.'
      and a1 = a2,
      concat_ws(' | ', t2, a2, a1));
  end if;
  perform pg_temp.gravar(v_res);
end
$l2$;

-- ── L3. O determinismo; L4. Quem lê; L7. O agenda_ver ─────────────────────────────────────────────────────────────
do $l3$
declare
  v_res jsonb := '[]'::jsonb;
  m1 text;
  m2 text;
  m3 text;
  m4 text;
  v  jsonb;
  t_tec text;
  t_tec2 text;
  t_adm text;
  t_srv text;
  t_ver text;
  t_os  text;
  t_nao text;
  t_sem text;
  t_desl text;
  t_foco text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('L3 L4 L7', true, 'PULADO: sem as fixtures da 7b e da 7c (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    perform public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    m1 := md5(pg_temp.foco(date '2026-11-04', '17:40')::text);
    m2 := md5(pg_temp.foco(date '2026-11-04', '17:40')::text);
    m3 := md5(pg_temp.foco(date '2026-11-04', '17:40', 'OS-97179')::text);
    m4 := md5(pg_temp.foco(date '2026-11-04', '17:40', 'OS-97179')::text);
    t_tec := pg_temp.como('c7c00000-0000-4000-8000-0000000ec006', 'authenticated',
               'select public.agenda_ver(null, null, null, ''habilidades'', null, null, false, date ''2026-11-04'')::text');
    t_tec2 := pg_temp.como('c7c00000-0000-4000-8000-0000000ec006', 'authenticated',
               'select public._agenda_ver_habilidades(date ''2026-11-04'', timestamptz ''2026-11-04 17:40-03'')::text');
    t_adm := pg_temp.como(pg_temp.adm(), 'authenticated',
               'select public.agenda_ver(null, null, null, ''habilidades'', ''Lenine'', null, false, date ''2026-11-04'') ->> ''texto''');
    t_srv := pg_temp.como(null, 'service_role',
               'select public.agenda_ver(null, null, null, ''habilidades'', null, null, false, date ''2026-11-04'') ->> ''texto''');
    v := public.agenda_ver(null, null, null, 'habilidades', null, null, false, date '2026-11-04');
    t_ver := (v ->> 'rota') || ' | ' || (v ->> 'ok') || ' | ' || pg_temp.linha(v ->> 'texto', 'Quem faz');
    v := public.agenda_ver(null, null, null, 'habilidades', 'Ivo', null, false, date '2026-11-04');
    t_os := (v ->> 'rota') || ' | ' || pg_temp.linha(v ->> 'texto', 'Ivo');
    v := public.agenda_ver(null, null, null, 'habilidades', 'Fulano de Tal', null, false, date '2026-11-04');
    t_nao := (v ->> 'rota') || ' | ' || (v ->> 'ok') || ' | ' || (v ->> 'texto');
    begin
      perform public.agenda_ver(null, null, null, 'habilidades', null, null, false, null);
      t_sem := 'passou';
    exception when others then
      t_sem := sqlstate || ': ' || sqlerrm;
    end;
    begin
      perform public.agenda_ver(null, null, null, 'quem_faz', null, null, false, date '2026-11-04');
      t_foco := 'passou';
    exception when others then
      t_foco := sqlstate || ': ' || sqlerrm;
    end;
    update public.agenda_config set modo_leitura = 'desligado' where id;
    t_desl := public.agenda_ver(null, null, null, 'habilidades', null, null, false, date '2026-11-04')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L3 o determinismo: o foco duas vezes (a equipe e a OS), o mesmo md5 (texto e dados)', m1 = m2 and m3 = m4, m1 || ' ' || m3);
  v_res := pg_temp.ok(v_res, 'L4a a técnica logada (login que não é admin nem financeiro) recebe 42501 "Quem faz o quê é com o administrador ou o financeiro." no agenda_ver e direto no foco',
    t_tec = 'erro 42501: Quem faz o quê é com o administrador ou o financeiro.' and t_tec2 = t_tec, t_tec || ' · ' || t_tec2);
  v_res := pg_temp.ok(v_res, 'L4b o admin logado (o painel, authenticated) e o service_role (o WhatsApp) leem pelo agenda_ver (o grant do foco: a §5.6 dizia "sem grant", e o agenda_ver é invoker)',
    t_adm like 'Lenine (OS-00074) — quem faz o quê (em teste: ainda escalo como antes):%' and t_srv like 'Quem faz o quê (em teste: ainda escalo como antes):%',
    left(t_adm, 80) || ' · ' || left(t_srv, 80));
  v_res := pg_temp.ok(v_res, 'L7a agenda_ver foco habilidades: rota habilidades; com a OS pelo nome, o bloco dela; a OS que não existe, a frase do resolvedor (rota os)',
    t_ver = 'habilidades | true | Quem faz o quê (em teste: ainda escalo como antes):'
    and t_os = 'habilidades | Ivo (OS-97179) — quem faz o quê (em teste: ainda escalo como antes):'
    and t_nao like 'os | false | %',
    concat_ws(' · ', t_ver, t_os, t_nao));
  v_res := pg_temp.ok(v_res, 'L7b sem p_hoje, 22004; a leitura desligada, a frase de sempre; o foco que não existe continua com a mensagem dos 19 (sem habilidades nem gestor nela)',
    t_sem = '22004: agenda_ver: sem o dia de hoje'
    and t_desl = '{"ok": false, "rota": "desligada", "texto": "A agenda de produção está desligada agora.", "desligada": true}'
    and t_foco = '22023: agenda_ver: foco "quem_faz" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores, clientes ou aprendizado)',
    concat_ws(' · ', t_sem, t_desl, t_foco));
  perform pg_temp.gravar(v_res);
end
$l3$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
