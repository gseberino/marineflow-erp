-- Prova da rodada do gestor da agenda, Fase 7a (pacote P7; migration 20261031100600), sobre a carteira REAL de 29/10 (o
-- replay; a presença do dono do Lenine e do Vanderlei como em produção: abre e fecha).
-- bancada: depende de 20261031100600
--
--   R0 as portas: a rodada e a palavra só pelo service_role (definer); os passos novos sem grant a ninguém; o foco e os ajudantes
--      de texto com authenticated e service_role, nunca anon; search_path fixo
--   R1 a rodada: tudo desligado = {rodou: false} e nada gravado; o 1º tique de dia útil a partir das 16:45 roda os diários (uma
--      vez: o tique seguinte não repete); antes das 16:45 e no sábado, só os de todo tique; o passo que ainda não existe é pulado;
--      o erro de um passo vai a app_error_logs (gestor:<passo>) e a rodada segue; o tempo estourado (query_canceled) registra,
--      grava a rodada (parou_no) e encerra, sem os diários (o tique seguinte tenta de novo); uma rodada por vez
--   R2 a sombra: o "eu marcaria assim" da carteira de 29/10 (Lenine e Vanderlei marcados, Giancarlo, Nelson e Flávio
--      perguntados, 6 fora), o texto da §6.1 com os números de agora; nada gravado em alocação, proposta, ação ou mensagem; a
--      variável agenda.gestor volta vazia; desligado = pulado
--   R3 o fechamento: a linha gestor (texto_sombra, perda 65, o modo da vigia) só com o gestor em teste; a linha compras pela
--      perda (80 urgente, 65 hoje/amanhã, 45 até 2 dias úteis, nenhuma depois); a pergunta com "eu digo os dias" não volta; as
--      vagas garantidas (0 em sombra com vaga_teria; 1; 2 com decisão de perda ≥ 80; até 2); desligado = as definições de antes
--      byte a byte (rodadas como pg_temp)
--   R4 o foco gestor nos estados: desligado, em teste, ligado e *gestor, só propor*; a lista dos focos com os 20
--   R5 agenda_gestor_dito: só o administrador; idempotente; a ação gestor desfazível; o desfaz volta; desfazer de novo, depois de
--      outra mudança ou fora do prazo, não
--   R6 _agenda_ver_plano: "(estimativa minha)" no dia marcado pela estimativa; sem alocação assim, a definição de antes byte a byte
--   R7 a saúde: a chave gestor com os zeros (entram no ok) e os números; cada violação forçada = 1; prazo_vencido_sem_mostrar só
--      se conta (fora do ok); a crítica com prazo é recusada pelo CHECK; o erro do fator só com as medidas que têm fator
--   R8 o job agenda-gestor pelo texto da migration: '7,22,37,52 10-23 * * 1-6', as duas instruções (statement_timeout de
--      gestor_tempo_max, sem número escrito; a rodada com _hoje_brt() e now()), só com pg_cron, desagenda antes
--   R9 as cópias: as 6 recriadas sem os blocos "-- FASE 7:" são o corpo da origem
--   R10 o desfaz das ações do gestor e de quem saiu da equipe: estimar volta os dias (e recusa se o dono já disse outros); dupla
--      volta a marca; o que era de quem saiu da equipe não volta (só ele = nada muda; parcial = volta o resto e diz quem)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_rodada.sql
--   Seguro em produção: R0 só lê; R8 e R9 saem PULADO sem as migrations como texto; R1 a R7 e R10 usam o replay e só rodam na
--   bancada (fora dela saem PULADO). Termina em ROLLBACK.
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

-- A OS pelo número e a pessoa pelo primeiro nome (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select p.id from public.payees p where p.name = p_nome order by p.id limit 1
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;

-- O replay de 29/10 com a presença do dono de produção (o Lenine e o Vanderlei: abre e fecha) e os 5 modos do gestor.
-- O replay roda uma vez por subtransação (a marca agenda_teste.ja_replay é local: o rollback do bloco a desfaz junto).
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

-- O que o gestor não pode escrever em sombra: as alocações, as propostas, as ações executadas e as mensagens.
create function pg_temp.escritas() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'alocacoes', (select md5(coalesce(string_agg(a.id::text || a.estado, ',' order by a.id), '')) from public.agenda_alocacoes a),
    'propostas', (select count(*) from public.agenda_propostas),
    'acoes', (select count(*) from public.agenda_acoes where executada),
    'equipe', (select count(*) from public.agenda_equipe_mensagens),
    'cliente', (select count(*) from public.agenda_cliente_mensagens),
    'fila', (select count(*) from public.whatsapp_send_queue))
$f$;

-- A função inteira (do "create or replace" ao "$function$;") e só o corpo, a partir do texto da migration.
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O corpo sem os blocos "-- FASE 7: … -- FASE 7: fim" (o fim lido pelo prefixo).
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

-- As definições de antes (o P7 copiou delas), como pg_temp: as linhas do fechamento (a revisão do lote), o fechamento (a
-- Fase 2, chamando as linhas de antes) e o plano (o P1 do lote).
create function pg_temp.criar_as_de_antes() returns boolean language plpgsql as $f$
declare
  v_rv text := coalesce(current_setting('agenda_teste.mig_correcao_revisao', true), '');
  v_f2 text := coalesce(current_setting('agenda_teste.mig_leituras_fase2', true), '');
  v_l1 text := coalesce(current_setting('agenda_teste.mig_correcao_leituras', true), '');
begin
  if v_rv = '' or v_f2 = '' or v_l1 = '' then
    return false;
  end if;
  if to_regprocedure('pg_temp.lf_antes(date)') is null then
    execute replace(pg_temp.inteira(v_rv, '_agenda_linhas_do_fechamento'),
                    'create or replace function public._agenda_linhas_do_fechamento(', 'create function pg_temp.lf_antes(');
    execute replace(replace(pg_temp.inteira(v_f2, 'agenda_textos_do_fechamento'),
                            'create or replace function public.agenda_textos_do_fechamento(', 'create function pg_temp.tf_antes('),
                    'public._agenda_linhas_do_fechamento(', 'pg_temp.lf_antes(');
    execute replace(pg_temp.inteira(v_l1, '_agenda_ver_plano'),
                    'create or replace function public._agenda_ver_plano(', 'create function pg_temp.vp_antes(');
  end if;
  return true;
end $f$;

-- ── R0. As portas (sem fixture) ───────────────────────────────────────────────────────────────────────────────
with f(assinatura, quem) as (values
  ('public.agenda_gestor_rodar(date, timestamp with time zone)', 'service_role'),
  ('public.agenda_gestor_dito(uuid, boolean, date, timestamp with time zone)', 'service_role'),
  ('public._agenda_gestor_sombra(date, timestamp with time zone)', 'ninguem'),
  ('public._agenda_gestor_perguntas(date, timestamp with time zone)', 'ninguem'),
  ('public._agenda_ver_gestor(date)', 'leitura'),
  ('public._agenda_plano_estimativa(jsonb, date)', 'leitura'),
  ('public._agenda_gestor_motivo_texto(text)', 'leitura'),
  ('public._agenda_gestor_motivo_ordem(text)', 'leitura'),
  ('public._agenda_gestor_faixa(date, date)', 'leitura'),
  ('public._agenda_gestor_pessoas(jsonb)', 'leitura'),
  ('public._agenda_gestor_compra_da_os(uuid, date)', 'leitura'),
  ('public._agenda_gestor_dupla_texto(jsonb)', 'leitura'))
insert into _resultado
select 'R0a as portas das 12 novas: a rodada e a palavra só pelo service_role; os passos sem grant a ninguém; o foco e os ajudantes de texto authenticated e service_role; nunca anon',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and case f.quem
                      when 'service_role' then has_function_privilege('service_role', f.assinatura, 'execute')
                                               and not has_function_privilege('authenticated', f.assinatura, 'execute')
                      when 'ninguem' then not has_function_privilege('service_role', f.assinatura, 'execute')
                                          and not has_function_privilege('authenticated', f.assinatura, 'execute')
                      else has_function_privilege('authenticated', f.assinatura, 'execute')
                           and has_function_privilege('service_role', f.assinatura, 'execute') end),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute'))
  from f;
insert into _resultado
select 'R0b a rodada e a palavra são definer e VOLATILE; os passos invoker e VOLATILE; o foco e os ajudantes invoker e não voláteis; search_path fixo',
       bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(case when p.proname in ('agenda_gestor_rodar', 'agenda_gestor_dito') then p.prosecdef and p.provolatile = 'v'
                         when p.proname in ('_agenda_gestor_sombra', '_agenda_gestor_perguntas') then not p.prosecdef and p.provolatile = 'v'
                         else not p.prosecdef and p.provolatile in ('s', 'i') end)
       and count(*) = 12,
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('agenda_gestor_rodar', 'agenda_gestor_dito', '_agenda_gestor_sombra', '_agenda_gestor_perguntas',
                     '_agenda_ver_gestor', '_agenda_plano_estimativa', '_agenda_gestor_motivo_texto', '_agenda_gestor_motivo_ordem',
                     '_agenda_gestor_faixa', '_agenda_gestor_pessoas', '_agenda_gestor_compra_da_os', '_agenda_gestor_dupla_texto');

-- ── R1. A rodada ────────────────────────────────────────────────────────────────────────────────────────────────
do $r1$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d29  constant date := date '2026-10-29';
  c_d30  constant date := date '2026-10-30';
  c_d31  constant date := date '2026-10-31';
  r      jsonb;
  v_n    int;
  v_l    jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('R1 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.replay('desligado');
    v_n := (select count(*) from public.agenda_vigia_rodadas where rotina = 'gestor');
    r := public.agenda_gestor_rodar(c_d29, pg_temp.em(c_d29, '16:52'));
    v_res := pg_temp.ok(v_res, 'R1a os 4 modos do gestor desligados: {rodou: false} e nenhuma linha de rodada',
      r ->> 'rodou' = 'false' and (select count(*) from public.agenda_vigia_rodadas where rotina = 'gestor') = v_n, r::text);
    -- só a vaga do fechamento ligada não faz a rodada rodar (ela é do fechamento)
    update public.agenda_config set modo_vaga_fechamento = 'ligado' where id;
    r := public.agenda_gestor_rodar(c_d29, pg_temp.em(c_d29, '16:52'));
    v_res := pg_temp.ok(v_res, 'R1b só a vaga do fechamento ligada: a rodada não roda', r ->> 'rodou' = 'false', r::text);

    perform pg_temp.replay('sombra');
    -- qui 29/10 10:07: só os de todo tique (antes das 16:45)
    r := public.agenda_gestor_rodar(c_d29, pg_temp.em(c_d29, '10:07'));
    v_res := pg_temp.ok(v_res, 'R1c antes das 16:45: só os passos de todo tique (vetos; o sinal, do 7a P12, roda e em teste pula; bem e puxar ainda não existem: pulados), nenhum diário',
      (r ->> 'rodou')::boolean and not (r ->> 'diaria')::boolean
      and r #> '{contagens,vetos}' ? 'aplicadas'
      and (select bool_and(r #>> array['contagens', p, 'motivo'] = 'ainda não existe') from unnest(array['encaixe', 'bem', 'puxar']) p)
      -- (7a P12: o passo sinal existe; em teste ele pula: o gestor não marca sozinho)
      and r #>> '{contagens,sinal,pulado}' = 'true' and r #>> '{contagens,sinal,motivo}' = 'o gestor não marca sozinho'
      and not (r -> 'contagens' ? 'sombra') and not (r -> 'contagens' ? 'perguntas') and not (r -> 'contagens' ? 'diaria'),
      left(r::text, 600));
    -- 16:52: o 1º tique a partir de gestor_hora_revisao roda os diários
    r := public.agenda_gestor_rodar(c_d29, pg_temp.em(c_d29, '16:52'));
    select x.contagens into v_l from public.agenda_vigia_rodadas x
     where x.rotina = 'gestor' and x.p_agora = pg_temp.em(c_d29, '16:52');
    -- (7a P11: o passo fichas existe e, sem o ligar do gestor — marcar_sozinho_desde nulo em teste —, pula)
    v_res := pg_temp.ok(v_res, 'R1d o 1º tique de dia útil a partir das 16:45 roda os diários: perguntas (em teste: pulado), equipe e sombra rodam; fichas (7a P11) pula sem o ligar do gestor; compre_ate e revisao (7a P9 e P10) rodam; orcamentos e sabado (7a P12) rodam — os 6 orçamentos pela conta da sombra, o sábado sem ninguém de sábado; a rodada grava "diaria"',
      (r ->> 'diaria')::boolean and v_l ? 'diaria' and v_l -> 'sombra' ? 'md5' and (v_l -> 'equipe' ->> 'criada')::boolean
      and v_l #>> '{perguntas,pulado}' = 'true'
      and v_l #>> '{fichas,pulado}' = 'true' and v_l #>> '{fichas,motivo}' like 'o gestor ainda não marca sozinho%'
      and v_l ? 'compre_ate' and v_l ? 'revisao'
      and v_l #>> '{orcamentos,orcamentos}' = '6' and v_l #>> '{orcamentos,simulacao}' = 'true'
      and v_l #>> '{sabado,quem_vem_sabado}' = '0' and v_l #>> '{sabado,perguntas}' = '0'
      and (v_l ->> 'erros') is null and v_l -> 'modos' ->> 'marcar' = 'sombra' and (v_l ->> 'acoes')::int = 0
      and (v_l ->> 'mudou')::boolean = false,
      left(v_l::text, 800));
    r := public.agenda_gestor_rodar(c_d29, pg_temp.em(c_d29, '17:07'));
    v_res := pg_temp.ok(v_res, 'R1e o tique seguinte do mesmo dia não repete os diários',
      not (r ->> 'diaria')::boolean and not (r -> 'contagens' ? 'sombra'), left(r::text, 300));
    -- sábado 31/10 16:52 (não é dia útil): só os de todo tique
    r := public.agenda_gestor_rodar(c_d31, pg_temp.em(c_d31, '16:52'));
    v_res := pg_temp.ok(v_res, 'R1f no sábado (não é dia útil) só os de todo tique', (r ->> 'rodou')::boolean and not (r ->> 'diaria')::boolean,
      left(r::text, 300));

    -- o erro de um passo vai a app_error_logs e a rodada segue (o puxar do 7e, de mentira, que falha)
    begin
      execute $p$create function public._agenda_gestor_puxar(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $b$
                 begin raise exception 'quebrou de propósito' using errcode = 'XX000'; end $b$$p$;
      v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
      r := public.agenda_gestor_rodar(c_d30, pg_temp.em(c_d30, '16:52'));
      v_res := pg_temp.ok(v_res, 'R1g o passo que falha (puxar) vai a app_error_logs (gestor:puxar) e a rodada segue: os diários rodam depois dele',
        (r ->> 'erros')::int = 1 and r -> 'falhas' -> 0 ->> 'passo' = 'puxar' and r -> 'falhas' -> 0 ->> 'sqlstate' = 'XX000'
        and (r ->> 'diaria')::boolean and r -> 'contagens' ? 'sombra'
        and (select count(*) from public.app_error_logs where action = 'gestor:puxar') = v_n + 1
        and (select x.erros from public.agenda_vigia_rodadas x where x.rotina = 'gestor' and x.p_agora = pg_temp.em(c_d30, '16:52')) = 1,
        left(r::text, 500));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    -- o tempo estourado (query_canceled): registra, grava a rodada (parou_no) e encerra, sem os diários
    begin
      execute $p$create function public._agenda_gestor_puxar(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $b$
                 begin raise exception 'canceling statement due to statement timeout' using errcode = '57014'; end $b$$p$;
      v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
      r := public.agenda_gestor_rodar(c_d30, pg_temp.em(c_d30, '16:52'));
      select x.contagens into v_l from public.agenda_vigia_rodadas x
       where x.rotina = 'gestor' and x.p_agora = pg_temp.em(c_d30, '16:52');
      v_res := pg_temp.ok(v_res, 'R1h o tempo estourado (query_canceled no puxar): registra em app_error_logs, grava a rodada com parou_no e encerra — sem os diários e sem "diaria" (o tique seguinte tenta de novo)',
        r ->> 'parou_no' = 'puxar' and not (r ->> 'diaria')::boolean and v_l ->> 'parou_no' = 'puxar' and not (v_l ? 'diaria')
        and not (v_l ? 'sombra') and not (v_l ? 'perguntas')
        and (select count(*) from public.app_error_logs where action = 'gestor:puxar') = v_n + 1,
        left(r::text, 500));
      -- o tique seguinte, já sem o problema, faz os diários
      execute $p$create or replace function public._agenda_gestor_puxar(p_hoje date, p_agora timestamptz) returns jsonb language sql as $b$
                 select '{"pulado": true, "motivo": "de mentira"}'::jsonb $b$$p$;
      r := public.agenda_gestor_rodar(c_d30, pg_temp.em(c_d30, '17:07'));
      v_res := pg_temp.ok(v_res, 'R1i o tique seguinte, sem o problema, roda os diários do dia', (r ->> 'diaria')::boolean, left(r::text, 300));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r1$;

-- ── R2. A sombra (spec §8.3 A, a parte do "eu marcaria assim"; o resto do cenário A é o agenda_fase7a_replay.sql) ───────
do $r2$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d29  constant date := date '2026-10-29';
  c_txt  constant text := 'Agenda em teste (nada mudou): eu marcaria assim — Lenine de ter 03 a ter 10/11, Roberto e João (6 dias, estimativa minha); Vanderlei de qui 12 a ter 24/11, Roberto e João (7,5 dias, estimativa minha; compre até hoje: 3 itens). Antes de marcar eu perguntaria: Giancarlo (10 diárias pela estimativa), Nelson (já começou?), Flávio (já começou?) (e mais 1). Continuam fora 5: esperando o cliente (3), orçamento sem virar OS, precisa de você em campo. *agenda gestor* mostra tudo.';
  -- (7a P12: o sinal combinado e não pago não segura mais a OS — AG7-09, "marco e cobro o sinal" —, e o MP, sem mão de obra
  -- separada, passa de "esperando o sinal" à pergunta "não tem mão de obra separada": o "(e mais 1)" e os 5 de fora)
  r      jsonb;
  v_e0   jsonb;
  v_s    jsonb;
  v_t    text;
  v_md5  text;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('R2 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.replay('desligado');
    r := public._agenda_gestor_sombra(c_d29, pg_temp.em(c_d29, '16:52'));
    v_res := pg_temp.ok(v_res, 'R2a desligado: a sombra é pulada e nada vai ao diário',
      (r ->> 'pulado')::boolean and not exists (select 1 from public.agenda_gestor_dia where dia = c_d29), r::text);

    perform pg_temp.replay('sombra');
    v_e0 := pg_temp.escritas();
    r := public._agenda_gestor_sombra(c_d29, pg_temp.em(c_d29, '16:52'));
    select g.sombra, g.texto_sombra into v_s, v_t from public.agenda_gestor_dia g where g.dia = c_d29;
    v_res := pg_temp.ok(v_res, 'R2b o texto do fechamento (spec §6.1, com os números de agora: o Vanderlei de qui 12 a ter 24/11 pelos 7 + 1 dias úteis) no diário e no retorno',
      v_t = c_txt and r ->> 'texto' = c_txt and char_length(v_t) <= 640, v_t);
    v_res := pg_temp.ok(v_res, 'R2c marcadas: Lenine (ter 03 a ter 10/11, 6 dias, 12 meios-dias, estimativa) e Vanderlei (qui 12 a ter 24/11, 7,5 dias, 15 meios-dias, 3 itens a comprar), as duas com nota de dupla',
      (select string_agg(format('%s %s %s %s %s %s %s %s', e ->> 'numero', e ->> 'de', e ->> 'ate', e ->> 'dias', e ->> 'meios', e ->> 'fonte',
                                coalesce(e ->> 'itens_a_comprar', '-'), jsonb_typeof(e -> 'alerta_dupla')), ' | ' order by o)
         from jsonb_array_elements(v_s -> 'itens') with ordinality t(e, o))
      = 'OS-00074 2026-11-03 2026-11-10 6 12 orcamento 0 object | OS-00069 2026-11-12 2026-11-24 7.5 15 orcamento 3 object',
      (select string_agg(format('%s %s %s %s %s %s %s %s', e ->> 'numero', e ->> 'de', e ->> 'ate', e ->> 'dias', e ->> 'meios', e ->> 'fonte',
                                coalesce(e ->> 'itens_a_comprar', '-'), jsonb_typeof(e -> 'alerta_dupla')), ' | ' order by o)
         from jsonb_array_elements(v_s -> 'itens') with ordinality t(e, o)));
    v_res := pg_temp.ok(v_res, 'R2d perguntadas: Giancarlo (estimativa grande), Nelson e Flávio (situação, começou sem rastro) e MP (sem mão de obra: o sinal não segura mais, 7a P12); fora: os 5 com o porquê em uma palavra',
      (select string_agg(e ->> 'numero' || ':' || split_part(e ->> 'chave', ':', 1) || ':' || split_part(e ->> 'chave', ':', 3), ' ' order by o)
         from jsonb_array_elements(v_s -> 'perguntas') with ordinality t(e, o)) = 'OS-00130:estimativa:grande OS-00112:situacao:comecada OS-00104:situacao:comecada ORÇ-00095:estimativa:sem_base'
      and (select string_agg(e ->> 'numero' || ':' || (e ->> 'grupo'), ' | ' order by e ->> 'numero')
             from jsonb_array_elements(v_s -> 'fora') e)
          = 'ORÇ-00083:orçamento sem virar OS | OS-00032:esperando o cliente | OS-00033:esperando o cliente | OS-00076:esperando o cliente | OS-00096:precisa de você em campo'
      and jsonb_array_length(v_s -> 'reservas') = 0,
      (select string_agg(e ->> 'numero' || ':' || (e ->> 'grupo'), ' | ' order by e ->> 'numero') from jsonb_array_elements(v_s -> 'fora') e));
    v_res := pg_temp.ok(v_res, 'R2e nada gravado em alocação, proposta, ação executada, mensagem à equipe ou ao cliente, nem na fila; a variável agenda.gestor volta vazia',
      pg_temp.escritas() = v_e0 and coalesce(current_setting('agenda.gestor', true), '') = '', (pg_temp.escritas())::text);
    -- de novo no mesmo dia: o mesmo md5 e o histórico não ganha entrada (nada mudou)
    v_md5 := v_s ->> 'md5';
    r := public._agenda_gestor_sombra(c_d29, pg_temp.em(c_d29, '17:07'));
    v_res := pg_temp.ok(v_res, 'R2f a conta é determinística: de novo, o mesmo md5 e o mesmo texto (o histórico só guarda o que mudou)',
      r ->> 'md5' = v_md5 and r ->> 'texto' = c_txt
      and (select jsonb_array_length(g.historico) from public.agenda_gestor_dia g where g.dia = c_d29) <= 1, r ->> 'md5');
    -- fora da simulação, com o gestor em teste, as regras continuam falsas (o motor e a prontidão de antes)
    v_res := pg_temp.ok(v_res, 'R2g fora da simulação, em teste, o portão das regras é falso (a duração do Lenine é a sugerida de antes)',
      not public._agenda_gestor_regra('estimativa') and public.agenda_meios_da_os(pg_temp.os('OS-00074'), c_d29) ->> 'fonte' = 'sugerida',
      public.agenda_meios_da_os(pg_temp.os('OS-00074'), c_d29) ->> 'fonte');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r2$;

-- ── R3. O fechamento: a linha gestor, a das compras, a pergunta escolhida e as vagas ───────────────────────────
do $r3$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d29  constant date := date '2026-10-29';
  r      jsonb;
  v_a    jsonb;
  v_b    jsonb;
  v_q    uuid;
  v_t    text;
  v_ok   boolean := true;
  rx     record;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' or not pg_temp.criar_as_de_antes() then
    insert into _resultado values ('R3 (o replay de 29/10)', true,
      'PULADO: sem agenda_teste.replay2910, mig_correcao_revisao, mig_leituras_fase2 ou mig_correcao_leituras (rode pela bancada)');
    return;
  end if;
  begin
    -- desligado: as definições de antes, byte a byte (as linhas e o fechamento)
    perform pg_temp.replay('desligado');
    v_a := public._agenda_linhas_do_fechamento(c_d29);
    v_b := pg_temp.lf_antes(c_d29);
    v_res := pg_temp.ok(v_res, 'R3a desligado: as linhas do fechamento e agenda_textos_do_fechamento byte a byte as de antes (sem gestor, sem compras, sem vagas)',
      md5(v_a::text) = md5(v_b::text)
      and md5(public.agenda_textos_do_fechamento(c_d29, c_d29 + 1)::text) = md5(pg_temp.tf_antes(c_d29, c_d29 + 1)::text)
      and not (public.agenda_textos_do_fechamento(c_d29, c_d29 + 1) ? 'vagas_garantidas'),
      md5(v_a::text) || ' / ' || md5(v_b::text));

    perform pg_temp.replay('sombra');
    perform public._agenda_gestor_sombra(c_d29, pg_temp.em(c_d29, '16:52'));
    v_a := public._agenda_linhas_do_fechamento(c_d29);
    v_res := pg_temp.ok(v_res, 'R3b em teste: a linha gestor com o texto_sombra de hoje, perda 65, ligada (a vigia está ligada: o dono lê); o resto como antes',
      exists (select 1 from jsonb_array_elements(v_a) x where x ->> 'tipo' = 'gestor' and (x ->> 'perda')::int = 65
                and x ->> 'modo' = 'ligado' and x ->> 'texto' = (select texto_sombra from public.agenda_gestor_dia where dia = c_d29))
      and md5((select jsonb_agg(x order by o) from jsonb_array_elements(v_a) with ordinality t(x, o) where x ->> 'tipo' <> 'gestor')::text)
          = md5(pg_temp.lf_antes(c_d29)::text),
      (select string_agg(x ->> 'tipo' || ' ' || (x ->> 'perda') || ' ' || (x ->> 'modo'), ' | ') from jsonb_array_elements(v_a) x));
    -- com o gestor ligado (ou desligado), a linha gestor não sai
    update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    v_res := pg_temp.ok(v_res, 'R3c com o gestor ligado, nada de "eu marcaria" no fechamento',
      not exists (select 1 from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_d29)) x where x ->> 'tipo' = 'gestor'));
    update public.agenda_config set modo_marcar_sozinho = 'sombra' where id;

    -- a vaga: em sombra 0 e vaga_teria; ligada 1; com decisão crítica de perda ≥ 80, 2; nunca mais de 2
    r := public.agenda_textos_do_fechamento(c_d29, c_d29 + 1);
    v_res := pg_temp.ok(v_res, 'R3d a vaga em teste: vagas_garantidas 0 e vaga_teria 1 (o Secretário põe no detalhe)',
      (r ->> 'vagas_garantidas')::int = 0 and (r ->> 'vaga_teria')::int = 1, r ->> 'vagas_garantidas' || ' / ' || coalesce(r ->> 'vaga_teria', '-'));
    update public.agenda_config set modo_vaga_fechamento = 'ligado' where id;
    r := public.agenda_textos_do_fechamento(c_d29, c_d29 + 1);
    v_res := pg_temp.ok(v_res, 'R3e a vaga ligada: 1 (fechamento_vagas_agenda), sem vaga_teria, e as linhas iguais às de _agenda_linhas_do_fechamento',
      (r ->> 'vagas_garantidas')::int = 1 and r -> 'vaga_teria' = 'null'::jsonb
      and r -> 'linhas' = public._agenda_linhas_do_fechamento(c_d29), r ->> 'vagas_garantidas');
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, versao_base, modo, criada_em)
    values ('nao_cabe', 'nao_cabe:teste-r3', pg_temp.os('OS-00112'), array[pg_temp.os('OS-00112')], c_d29 + 1,
            'Não cabe tudo até sex 30/10. Qual aceita atrasar? 1) Nelson atrasa; 2) Deixo o Nelson fora.',
            '[{"n": 1, "texto": "Nelson atrasa"}, {"n": 2, "texto": "Deixo fora"}]'::jsonb, 1,
            (select versao_plano from public.agenda_config), 'ligado', pg_temp.em(c_d29, '16:00'));
    r := public.agenda_textos_do_fechamento(c_d29, c_d29 + 1);
    v_res := pg_temp.ok(v_res, 'R3f com uma decisão crítica ligada de perda ≥ 80: 2 vagas',
      (r ->> 'vagas_garantidas')::int = 2, r ->> 'vagas_garantidas');
    update public.agenda_config set fechamento_vagas_agenda = 2 where id;
    r := public.agenda_textos_do_fechamento(c_d29, c_d29 + 1);
    v_res := pg_temp.ok(v_res, 'R3g nunca mais de 2 vagas', (r ->> 'vagas_garantidas')::int = 2, r ->> 'vagas_garantidas');
    update public.agenda_config set fechamento_vagas_agenda = 0 where id;
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where chave = 'nao_cabe:teste-r3';
    r := public.agenda_textos_do_fechamento(c_d29, c_d29 + 1);
    v_res := pg_temp.ok(v_res, 'R3h fechamento_vagas_agenda 0 e nenhuma decisão: 0 vagas', (r ->> 'vagas_garantidas')::int = 0, r ->> 'vagas_garantidas');
    update public.agenda_config set fechamento_vagas_agenda = 1 where id;

    -- as compras da semana (o P10 grava; aqui o diário à mão): a perda pela data
    v_ok := true;
    v_t := '';
    for rx in select * from (values
        ('[{"texto": "Compre hoje: Cerbo GX do Nelson, para começar ter 03/11.", "compre_ate": "2026-10-29", "urgente": true}]', 80),
        ('[{"texto": "Sem fornecedor (contei 7 dias úteis): 3 itens do Vanderlei — compre até sex 30/10.", "compre_ate": "2026-10-30", "urgente": false}]', 65),
        ('[{"texto": "Kamell: o cabo do Lenine — compre até ter 03/11.", "compre_ate": "2026-11-03", "urgente": false}]', 45),
        ('[{"texto": "Kamell: o cabo do Lenine — compre até qua 04/11.", "compre_ate": "2026-11-04", "urgente": false}]', -1)
      ) t(compras, perda) loop
      perform public._agenda_gestor_dia_gravar(c_d29, 'compras', rx.compras::jsonb, pg_temp.em(c_d29, '16:52'));
      if coalesce((select max((e ->> 'perda')::int) from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_d29)) e
                    where e ->> 'tipo' = 'compras' and e ->> 'modo' = 'sombra'
                      and e ->> 'texto' = 'Compras: ' || (rx.compras::jsonb -> 0 ->> 'texto')), -1) <> rx.perda then
        v_ok := false;
        v_t := v_t || format('[%s esperava %s] ', rx.compras::jsonb -> 0 ->> 'compre_ate', rx.perda);
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'R3i a linha compras pela perda: 80 com compra urgente, 65 com "compre até" hoje ou amanhã, 45 até 2 dias úteis, nenhuma depois; em teste (o compre_ate em sombra)',
      v_ok, nullif(v_t, ''));
    perform public._agenda_gestor_dia_gravar(c_d29, 'compras', '[]'::jsonb, pg_temp.em(c_d29, '16:52'));

    -- a pergunta do gestor em que o dono escolheu "eu digo os dias" não volta como linha pergunta
    update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    perform public._agenda_gestor_perguntas(c_d29, pg_temp.em(c_d29, '16:52'));
    select q.id into v_q from public.agenda_perguntas q
     where q.tipo = 'estimativa' and q.service_order_id = pg_temp.os('OS-00130') and q.estado = 'aberta' and q.modo = 'ligado';
    update public.agenda_perguntas set mostrada_vezes = 0 where tipo in ('situacao', 'estimativa');
    -- as outras perguntas do gestor somem para a linha ser a do Giancarlo
    update public.agenda_perguntas set mostrada_vezes = 9 where estado = 'aberta' and not critica and id <> v_q;
    v_a := public._agenda_linhas_do_fechamento(c_d29);
    perform public.agenda_decidir(v_q, 2::smallint, (select u.id from public.app_users u where u.role = 'admin' order by u.id limit 1),
                                  'whatsapp', 'eu digo os dias', c_d29, pg_temp.em(c_d29, '17:00'));
    v_b := public._agenda_linhas_do_fechamento(c_d29);
    v_res := pg_temp.ok(v_res, 'R3j a pergunta estimativa do Giancarlo sai como linha pergunta; depois do "eu digo os dias" (opção 2, fica aberta), não sai mais',
      exists (select 1 from jsonb_array_elements(v_a) x where x ->> 'tipo' = 'pergunta' and (x ->> 'pergunta_id')::uuid = v_q)
      and not exists (select 1 from jsonb_array_elements(v_b) x where (x ->> 'pergunta_id')::uuid = v_q)
      and (select estado = 'aberta' and opcao_escolhida = 2 from public.agenda_perguntas where id = v_q),
      (select string_agg(x ->> 'tipo', ',') from jsonb_array_elements(v_b) x));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r3$;

-- ── R4. O foco gestor nos estados ─────────────────────────────────────────────────────────────────────────────
do $r4$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d29  constant date := date '2026-10-29';
  c_sombra constant text := E'O gestor está em teste desde qui 29/10: calcula o que marcaria, mas não muda nada.\nEu marcaria:\n• Lenine: ter 03 a ter 10/11, Roberto e João — 6 dias (estimativa minha). Pode precisar de dupla (banco de baterias): diga *Lenine com dupla*.\n• Vanderlei: qui 12 a ter 24/11, Roberto e João — 7,5 dias (estimativa minha); compre até hoje: 3 itens. Pode precisar de dupla (banco de baterias): diga *Vanderlei com dupla*.\nAntes de marcar eu perguntaria:\n• Giancarlo: 10 diárias pela estimativa.\n• Nelson: já começou?\n• Flávio: já começou?\n• MP: não tem mão de obra separada.\nFora: esperando o cliente: Kalmar (2) e Rodrigo; orçamento sem virar OS: Robson; precisa de você em campo: Rodrigo.\nSe aprovar:\n• Everton (ORÇ-00117, R$ 120.020): pela estimativa, 28 dias com 2 pessoas; não cabe até ter 15/12 com a equipe de agora.\n• Santo (ORÇ-00116, R$ 70.050): pela estimativa, 10,5 dias com 2 pessoas; não cabe até ter 15/12 com a equipe de agora.\n(e mais 5 linhas)';
  c_ligado constant text := E'Eu marco sozinho desde qui 29/10 e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz.\nMarquei nos últimos 7 dias:\n• Lenine: ter 03 a ter 10/11, Roberto e João — 6 dias (estimativa minha). Pode precisar de dupla (banco de baterias): diga *Lenine com dupla*.\n• Vanderlei: qui 12 a ter 24/11, Roberto e João — 7,5 dias (estimativa minha). Pode precisar de dupla (banco de baterias): diga *Vanderlei com dupla*.\nPerguntei antes de marcar:\n• Giancarlo: 10 diárias pela estimativa — sem resposta até sex 30/10 18:00, marco assim.\n• Nelson: já começou? — sem resposta até sex 30/10 18:00, marco assim.\n• Flávio: já começou? — sem resposta até sex 30/10 18:00, marco assim.\n• MP: não tem mão de obra separada — sem resposta até sex 30/10 18:00, marco assim.\nFora: esperando o cliente: Kalmar (2) e Rodrigo; orçamento sem virar OS: Robson; precisa de você em campo: Rodrigo.\nSe aprovar:\n(e mais 7 linhas)';
  -- (7a P12: o MP perguntado — o sinal não segura mais —, e o "Se aprovar:" dos orçamentos grandes, que a rodada das 16:52 grava
  -- no diário; o foco corta em texto_max pela linha inteira)
  c_conto constant text := 'Como eu conto: estimativa pelo valor do orçamento (R$ 764 de mão de obra por diária, sem deslocamento); 1 pessoa por serviço (dupla quando você marcar); peça sem fornecedor: 7 dias úteis; peça abaixo de R$ 300: separar na véspera; entre decidir e comprar: 1 dia útil (com o serviço a menos de 7 dias úteis, a compra é para hoje); pergunto antes acima de 8 diárias e quando o serviço já começou.';
  r      jsonb;
  v_p    jsonb;
  v_adm  uuid;
  v_t    text;
  v_err  text;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('R4 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.replay('desligado');
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
    r := public.agenda_ver(null, null, null, 'gestor', null, null, false, c_d29);
    v_res := pg_temp.ok(v_res, 'R4a desligado: o estado, a conta de como eu conto (com os parâmetros) e nada mais; rota gestor',
      r ->> 'texto' = 'O gestor da agenda está desligado: não marco nada sozinho.' || E'\n' || c_conto and r ->> 'rota' = 'gestor'
      and (r ->> 'ok')::boolean, r ->> 'texto');
    begin
      perform public.agenda_ver(null, null, null, 'xyz', null, null, false, c_d29);
    exception when sqlstate '22023' then
      v_err := sqlerrm;
    end;
    v_res := pg_temp.ok(v_res, 'R4b foco que não existe: o 22023 e a mensagem de antes (os 19: o bloco do gestor só trata o foco dele)',
      v_err like '%clientes ou aprendizado)%', v_err);

    perform pg_temp.replay('sombra');
    perform public.agenda_gestor_rodar(c_d29, pg_temp.em(c_d29, '16:52'));
    r := public.agenda_ver(null, null, null, 'gestor', null, null, false, c_d29);
    v_res := pg_temp.ok(v_res, 'R4c em teste: o estado desde o 1º dia do diário em teste, o "eu marcaria" pela conta das 16:52 (com a nota de dupla), as perguntas que faria e quem fica de fora; cortado em texto_max (1.000) pela linha inteira',
      r ->> 'texto' = c_sombra and char_length(r ->> 'texto') <= 1000, r ->> 'texto');

    -- ligado (o cenário B: o gestor marcou a carteira e perguntou antes)
    perform pg_temp.replay('ligado');
    v_p := public.agenda_propor('os', null, null, array(select k.service_order_id from public.os_carteira(c_d29) k), '{}'::jsonb, true,
                                'vigia', null, c_d29, pg_temp.em(c_d29, '16:52'));
    perform public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, c_d29, pg_temp.em(c_d29, '16:52'));
    perform public._agenda_gestor_perguntas(c_d29, pg_temp.em(c_d29, '16:52'));
    r := public.agenda_ver(null, null, null, 'gestor', null, null, false, c_d29);
    v_res := pg_temp.ok(v_res, 'R4d ligado: desde o ligar, o que marquei pela estimativa (as alocações vigentes de duracao_fonte orcamento), o que perguntei com o prazo e quem fica de fora pela última conta do motor',
      r ->> 'texto' = c_ligado, r ->> 'texto');

    perform public.agenda_gestor_dito(v_adm, true, c_d29, pg_temp.em(c_d29, '18:00'));
    r := public.agenda_ver(null, null, null, 'gestor', null, null, false, c_d29);
    v_t := split_part(r ->> 'texto', E'\n', 1);
    v_res := pg_temp.ok(v_res, 'R4e *gestor, só propor*: o estado diz desde quando e como voltar; o "eu marcaria" é o da última conta (a das 16:52)',
      v_t = 'Desde qui 29/10 você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta.'
      and split_part(r ->> 'texto', E'\n', 2) = 'Eu marcaria:'
      and split_part(r ->> 'texto', E'\n', 3) like '• Lenine: ter 03 a ter 10/11, Roberto e João — 6 dias (estimativa minha).%', r ->> 'texto');
    -- com leitura desligada, a frase de sempre
    update public.agenda_config set modo_leitura = 'desligado' where id;
    r := public.agenda_ver(null, null, null, 'gestor', null, null, false, c_d29);
    v_res := pg_temp.ok(v_res, 'R4f a leitura desligada: a frase de sempre', r ->> 'texto' = 'A agenda de produção está desligada agora.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r4$;

-- ── R5. agenda_gestor_dito ────────────────────────────────────────────────────────────────────────────────────
do $r5$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d29  constant date := date '2026-10-29';
  r      jsonb;
  r2     jsonb;
  v_adm  uuid;
  v_tec  uuid;
  v_err  text;
  v_n    int;
  a      public.agenda_acoes;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('R5 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.replay('ligado');
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
    select u.id into v_tec from public.app_users u where u.role <> 'admin' order by u.id limit 1;
    begin
      perform public.agenda_gestor_dito(v_tec, true, c_d29, pg_temp.em(c_d29, '18:00'));
    exception when sqlstate '42501' then
      v_err := sqlerrm;
    end;
    v_res := pg_temp.ok(v_res, 'R5a só o administrador diz a palavra (42501 para os outros) e nada muda',
      v_err = 'Só o administrador mexe na agenda.' and not (select gestor_so_propor from public.agenda_config), coalesce(v_err, 'passou'));
    v_n := (select count(*) from public.agenda_acoes where tipo = 'gestor');
    r := public.agenda_gestor_dito(v_adm, true, c_d29, pg_temp.em(c_d29, '18:00'));
    select * into a from public.agenda_acoes where id = (r ->> 'acao_id')::uuid;
    v_res := pg_temp.ok(v_res, 'R5b *gestor, só propor*: gravado (com a hora), a ação gestor do dono desfazível por 24 h, o texto da §6.4; os modos efetivos do gestor viram teste',
      (r ->> 'mudou')::boolean and (select gestor_so_propor and gestor_so_propor_em = pg_temp.em(c_d29, '18:00') from public.agenda_config)
      and a.tipo = 'gestor' and a.origem = 'dono' and a.executada and a.autor = v_adm
      and a.desfazivel_ate = pg_temp.em(c_d29, '18:00') + interval '24 hours'
      and a.antes ->> 'gestor_so_propor' = 'false' and a.depois ->> 'gestor_so_propor' = 'true'
      and r ->> 'texto' = 'Combinado: até você dizer *gestor, pode marcar*, eu só sugiro — não marco nem mudo nada sozinho do jeito novo (o que eu fazia antes de 29/10 continua).'
      and public._agenda_gestor_modo('marcar') = 'sombra' and public._agenda_gestor_modo('encaixe') = 'sombra'
      and public._agenda_gestor_modo('vaga') = 'ligado' and not public._agenda_gestor_regra('estimativa'),
      r::text);
    r2 := public.agenda_gestor_dito(v_adm, true, c_d29, pg_temp.em(c_d29, '18:05'));
    v_res := pg_temp.ok(v_res, 'R5c dizer de novo: "Já estava assim.", sem ação nova',
      r2 ->> 'texto' = 'Já estava assim.' and not (r2 ->> 'mudou')::boolean
      and (select count(*) from public.agenda_acoes where tipo = 'gestor') = v_n + 1, r2::text);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, v_adm, 'dono', c_d29, pg_temp.em(c_d29, '18:10'));
    v_res := pg_temp.ok(v_res, 'R5d *desfaz*: volta a marcar sozinho (gestor_so_propor e a hora de antes), a ação desfazer e a original desfeita',
      (r2 ->> 'ok')::boolean and r2 ->> 'texto' = 'Desfeito: voltei a marcar sozinho; o que eu marcar vem no seu fechamento, com *desfaz*.'
      and (select not gestor_so_propor and gestor_so_propor_em is null from public.agenda_config)
      and (select desfeita_em is not null and desfeita_pela = (r2 ->> 'acao_id')::uuid from public.agenda_acoes where id = (r ->> 'acao_id')::uuid)
      and public._agenda_gestor_modo('marcar') = 'ligado', r2::text);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, v_adm, 'dono', c_d29, pg_temp.em(c_d29, '18:11'));
    v_res := pg_temp.ok(v_res, 'R5e desfazer de novo: "Isso já foi desfeito."', r2 ->> 'texto' = 'Isso já foi desfeito.', r2::text);
    -- *pode marcar* depois de *só propor*, e o desfaz do só propor (de antes) recusado: o estado já mudou
    r := public.agenda_gestor_dito(v_adm, true, c_d29, pg_temp.em(c_d29, '18:20'));
    perform public.agenda_gestor_dito(v_adm, false, c_d29, pg_temp.em(c_d29, '18:30'));
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, v_adm, 'dono', c_d29, pg_temp.em(c_d29, '18:35'));
    v_res := pg_temp.ok(v_res, 'R5f o desfaz de um *só propor* que o dono já mudou é recusado (nada muda)',
      not (r2 ->> 'ok')::boolean and r2 ->> 'texto' like 'Não desfaço: depois disso você já mudou o gestor de novo.%'
      and not (select gestor_so_propor from public.agenda_config), r2::text);
    -- fora do prazo
    r := public.agenda_gestor_dito(v_adm, true, c_d29, pg_temp.em(c_d29, '18:40'));
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, v_adm, 'dono', c_d29 + 2, pg_temp.em(c_d29 + 2, '19:00'));
    v_res := pg_temp.ok(v_res, 'R5g depois de 24 h, o desfaz é recusado', not (r2 ->> 'ok')::boolean and r2 ->> 'texto' like 'Não dá mais para desfazer: passou o prazo.%',
      r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r5$;

-- ── R6. O plano: "(estimativa minha)" ───────────────────────────────────────────────────────────────────────────
do $r6$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d29  constant date := date '2026-10-29';
  v_p    jsonb;
  v_n    jsonb;
  v_a    jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' or not pg_temp.criar_as_de_antes() then
    insert into _resultado values ('R6 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 ou as migrations como texto (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.replay('ligado');
    v_n := public._agenda_ver_plano(c_d29, c_d29 + 12, c_d29, pg_temp.em(c_d29, '16:00'));
    v_a := pg_temp.vp_antes(c_d29, c_d29 + 12, c_d29, pg_temp.em(c_d29, '16:00'));
    v_res := pg_temp.ok(v_res, 'R6a sem alocação marcada pela estimativa (só as reservas do Lenine): byte a byte o plano de antes',
      md5(v_n::text) = md5(v_a::text), v_n ->> 'texto');
    v_p := public.agenda_propor('os', null, null, array(select k.service_order_id from public.os_carteira(c_d29) k), '{}'::jsonb, true,
                                'vigia', null, c_d29, pg_temp.em(c_d29, '16:52'));
    perform public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, c_d29, pg_temp.em(c_d29, '16:52'));
    v_n := public._agenda_ver_plano(c_d29, c_d29 + 9, c_d29, pg_temp.em(c_d29, '17:00'));
    v_a := pg_temp.vp_antes(c_d29, c_d29 + 9, c_d29, pg_temp.em(c_d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'R6b marcado pela estimativa: cada dia do Lenine termina "(estimativa minha)" depois das pessoas, também na continuação do bloco; tirado o sufixo, o plano de antes',
      v_n ->> 'texto' like E'%Ter 03/11: 08:00 Lenine (OS-00074), dia 1 de 6: você abre, João o dia todo (estimativa minha).\n%'
      and v_n ->> 'texto' like E'%Ter 10/11 (continua): 08:00 Lenine (OS-00074), dia 6 de 6: você fecha, Roberto o dia todo (estimativa minha).%'
      and (length(v_n ->> 'texto') - length(replace(v_n ->> 'texto', '(estimativa minha)', ''))) / length('(estimativa minha)') = 6
      and replace(v_n ->> 'texto', ' (estimativa minha)', '') = v_a ->> 'texto', v_n ->> 'texto');
    -- a alocação com os dias do dono (duracao_fonte dono) não ganha o sufixo
    update public.agenda_alocacoes set duracao_fonte = 'dono'
     where service_order_id = pg_temp.os('OS-00074') and estado in ('publicada', 'fixada') and dia = date '2026-11-03';
    v_n := public._agenda_ver_plano(c_d29, c_d29 + 9, c_d29, pg_temp.em(c_d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'R6c o dia com os dias do dono (duracao_fonte dono) não diz "(estimativa minha)"',
      v_n ->> 'texto' like E'%Ter 03/11: 08:00 Lenine (OS-00074), dia 1 de 6: você abre, João o dia todo.\n%', v_n ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r6$;

-- ── R7. A saúde ───────────────────────────────────────────────────────────────────────────────────────────────
do $r7$
declare
  v_res   jsonb := '[]'::jsonb;
  c_d29   constant date := date '2026-10-29';
  c_d30   constant date := date '2026-10-30';
  c_zeros constant text[] := array['zona_travada_mexida', 'dia_avisado_sem_pergunta', 'estimativa_sem_pergunta', 'prazo_em_critica',
                                   'prazo_em_dia_prometido', 'aprovada_sem_data', 'rodada_gestor_atrasada',
                                   'cliente_estimativa_sem_aprovacao', 'ficha_estimativa_sem_veto', 'onda_aplicada_sem_pergunta',
                                   'alocacao_sem_fonte', 'regra_em_sombra_aplicada', 'prazo_vencido_sem_mostrar'];
  r       jsonb;
  g       jsonb;
  v_t     text := '';
  v_ok    boolean := true;
  v_err   text;
  v_os    uuid;
  v_jo    uuid;
  v_pr    uuid;
  v_base  int;
  rx      record;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('R7 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.replay('sombra');
    perform public.agenda_gestor_rodar(c_d29, pg_temp.em(c_d29, '16:52'));
    r := public.agenda_saude(c_d29, pg_temp.em(c_d29, '17:00'));
    g := r -> 'gestor';
    v_res := pg_temp.ok(v_res, 'R7a em teste, com a rodada das 16:52: a chave gestor com os 13 zeros, zeros_ok, os modos, a última rodada, os diários de hoje e os números; o ok da saúde inclui os zeros',
      (select bool_and(g ? zz and (g ->> zz)::int = 0) from unnest(c_zeros) zz) and (g ->> 'zeros_ok')::boolean
      and g -> 'modos' ->> 'marcar' = 'sombra' and (g ->> 'diaria_hoje')::boolean and (g ->> 'rodadas_24h')::int = 1
      and g -> 'numeros' ? 'os_por_estimativa' and g -> 'numeros' -> 'compre_ate' ? 'empurrados' and (r ->> 'ok')::boolean,
      left(g::text, 900));

    -- a rodada atrasada: de manhã sem rodada em 40 min (dia útil, com um modo fora de desligado)
    r := public.agenda_saude(c_d30, pg_temp.em(c_d30, '10:00'));
    v_res := pg_temp.ok(v_res, 'R7b rodada_gestor_atrasada = 1 sem rodada do gestor em 40 min (sex 30/10 10:00), e o ok cai',
      (r #>> '{gestor,rodada_gestor_atrasada}')::int = 1 and not (r #>> '{gestor,zeros_ok}')::boolean and not (r ->> 'ok')::boolean,
      r #>> '{gestor,rodada_gestor_atrasada}');
    perform public.agenda_gestor_rodar(c_d30, pg_temp.em(c_d30, '09:52'));
    v_res := pg_temp.ok(v_res, 'R7c com a rodada das 09:52, às 10:00 não está atrasada',
      (public.agenda_saude(c_d30, pg_temp.em(c_d30, '10:00')) #>> '{gestor,rodada_gestor_atrasada}')::int = 0);

    -- a crítica com prazo não existe: o CHECK recusa
    begin
      insert into public.agenda_perguntas (tipo, chave, texto, versao_base, modo, criada_em, veto_ate)
      values ('dia_prometido', 'dia_prometido:teste-r7', 'É um dia que o cliente já ouviu.', 0, 'ligado', pg_temp.em(c_d29, '17:00'),
              pg_temp.em(c_d30, '18:00'));
    exception when sqlstate '23514' then
      v_err := 'recusada';
    end;
    v_res := pg_temp.ok(v_res, 'R7d a pergunta crítica (dia_prometido) com prazo é recusada pelo CHECK (prazo_em_critica e prazo_em_dia_prometido ficam 0)',
      v_err = 'recusada', coalesce(v_err, 'passou'));

    -- ligado (desde qui 29/10 16:46), com as perguntas do gestor das 16:52 e as rodadas de sex 30/10; o encaixe na aprovação em
    -- teste (o aprovada_sem_data só conta com ele ligado: a iteração dele o liga e mede a linha de base)
    perform pg_temp.replay('ligado');
    update public.agenda_config set modo_encaixe_aprovacao = 'sombra' where id;
    perform public.agenda_gestor_rodar(c_d29, pg_temp.em(c_d29, '16:52'));
    perform public.agenda_gestor_rodar(c_d30, pg_temp.em(c_d30, '16:52'));
    g := public.agenda_saude(c_d30, pg_temp.em(c_d30, '17:00')) -> 'gestor';
    v_res := pg_temp.ok(v_res, 'R7e ligado, com as perguntas das 16:52 e a rodada de sex 30/10 16:52: os zeros todos 0 e 4 perguntas com prazo abertas (com o MP: o sinal não segura mais, 7a P12)',
      (select bool_and((g ->> zz)::int = 0) from unnest(c_zeros) zz) and (g ->> 'zeros_ok')::boolean
      and (g #>> '{numeros,perguntas_com_prazo,abertas}')::int = 4, left(g::text, 700));

    v_os := pg_temp.os('OS-00130');
    v_jo := pg_temp.pessoa('João');
    select id into v_pr from public.agenda_propostas order by criada_em limit 1;
    for rx in select * from (values
        ('zona_travada_mexida'), ('dia_avisado_sem_pergunta'), ('estimativa_sem_pergunta'), ('aprovada_sem_data'),
        ('cliente_estimativa_sem_aprovacao'), ('ficha_estimativa_sem_veto'), ('onda_aplicada_sem_pergunta'), ('alocacao_sem_fonte'),
        ('regra_em_sombra_aplicada')) t(zero) loop
      begin
        v_base := 0;
        if rx.zero in ('zona_travada_mexida', 'dia_avisado_sem_pergunta') then
          -- a regra de _agenda_criticidade_da_acao (o P8 a estende) dizendo que a ação mexeu no dia que o cliente ouviu / a equipe sabia
          execute format($p$create or replace function public._agenda_criticidade_da_acao(p_acao uuid) returns text language sql stable
                            as $b$ select %L::text $b$$p$, case rx.zero when 'zona_travada_mexida' then 'dia_prometido' else 'dia_avisado' end);
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto)
          values (pg_temp.em(c_d30, '16:55'), c_d30, true, 'vigia', 'mover', v_os, array[v_os], 'Giancarlo: mudei de dia.');
        elsif rx.zero = 'estimativa_sem_pergunta' then
          -- o Giancarlo (10 diárias, acima de 8) marcado pela estimativa sem a pergunta
          insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, duracao_fonte)
          values (v_os, v_jo, date '2026-12-01', 'manha', 'turno', 'execucao', 'publicada', 'motor', 'orcamento');
        elsif rx.zero = 'aprovada_sem_data' then
          -- o Giancarlo virou OS sex 30/10 14:00 e ninguém olhou: sem dia, sem pergunta aberta, sem o motor dizer por que fica fora
          update public.agenda_config set modo_encaixe_aprovacao = 'ligado' where id;
          update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste'
           where service_order_id = v_os and estado = 'aberta';
          v_base := (public.agenda_saude(c_d30, pg_temp.em(c_d30, '17:00')) #>> '{gestor,aprovada_sem_data}')::int;
          perform set_config('agenda.porta', 'on', true);
          update public.service_orders set converted_to_os_at = pg_temp.em(c_d30, '14:00') where id = v_os;
          perform set_config('agenda.porta', 'off', true);
        elsif rx.zero = 'cliente_estimativa_sem_aprovacao' then
          insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate,
                                                       aprovacao, estado, dedupe_key, criada_em)
          select so.client_id, so.id, 'confirmar', 'rodada', 'ligado', 'Olá! Conseguimos encaixar o serviço.',
                 '{"dados": {"por_estimativa": true}}'::jsonb, pg_temp.em(c_d30, '17:30'), pg_temp.em(c_d30, '19:00'), 'livre',
                 'enfileirada', 'teste-r7', pg_temp.em(c_d30, '16:58')
            from public.service_orders so where so.id = v_os;
        elsif rx.zero = 'ficha_estimativa_sem_veto' then
          insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, duracao_fonte)
          values (v_os, v_jo, date '2026-12-02', 'manha', 'turno', 'execucao', 'publicada', 'motor', 'orcamento');
          insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
          values (v_jo, date '2026-12-02', 'ficha', 'ligado', 'Amanhã: Giancarlo o dia todo.', pg_temp.em(date '2026-12-01', '19:30'),
                  'enfileirada', 'teste-r7-ficha');
          update public.agenda_config set ficha_veto_dias = 60 where id;
        elsif rx.zero = 'onda_aplicada_sem_pergunta' then
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, texto)
          select pg_temp.em(c_d30, '16:55'), c_d30, true, 'vigia', 'mover', so.id, array[so.id], v_pr, 'mudei de dia.'
            from public.service_orders so where so.service_order_number in ('OS-00130', 'OS-00112', 'OS-00104');
        elsif rx.zero = 'alocacao_sem_fonte' then
          alter table public.agenda_alocacoes disable trigger agenda_alocacoes_fonte;
          insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, criado_em)
          values (v_os, v_jo, date '2026-12-03', 'manha', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(c_d30, '16:56'));
          alter table public.agenda_alocacoes enable trigger agenda_alocacoes_fonte;
        elsif rx.zero = 'regra_em_sombra_aplicada' then
          -- os dias gravados pelo "prazo" numa rodada em que o gestor que marca estava em teste
          update public.agenda_config set modo_marcar_sozinho = 'sombra' where id;
          perform public.agenda_gestor_rodar(c_d30, pg_temp.em(c_d30, '18:07'));
          update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
          perform public._agenda_gestor_gravar_dias(pg_temp.os('OS-00112'), 4, 'Sem resposta sobre Nelson: contei 4 dias.', null,
                                                    pg_temp.em(c_d30, '18:07'));
        end if;
        g := public.agenda_saude(c_d30, pg_temp.em(c_d30, '17:00')) -> 'gestor';
        if (g ->> rx.zero)::int <> v_base + 1 or (g ->> 'zeros_ok')::boolean then
          v_ok := false;
          v_t := v_t || format('[%s = %s (base %s), zeros_ok %s] ', rx.zero, g ->> rx.zero, v_base, g ->> 'zeros_ok');
        end if;
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
    end loop;
    v_res := pg_temp.ok(v_res, 'R7f cada violação forçada conta 1 e derruba zeros_ok (a zona travada e o dia avisado pela regra da criticidade, a estimativa grande marcada sem pergunta, a aprovada sem nada, a mensagem por estimativa sem o sim, a ficha por estimativa sem a pergunta, a onda sem pergunta, a alocação sem fonte, a regra aplicada em teste)',
      v_ok, nullif(v_t, ''));

    -- o prazo vencido (as perguntas nasceram na rodada de sex 30/10 16:52: os diários de qui já tinham rodado em teste; o prazo é o
    -- próximo dia útil, ter 03/11 — seg 02 é Finados — às 18:00): o Giancarlo, visto no fechamento de sex, é aplicado às 18:07
    -- (10 dias); o Nelson e o Flávio, nunca vistos, ficam abertos e só se contam (prazo_vencido_sem_mostrar 2, sem derrubar zeros_ok)
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.em(c_d30, '17:30'), mostrada_via = 'fechamento'
     where tipo = 'estimativa' and service_order_id = v_os and estado = 'aberta' and modo = 'ligado';
    r := public.agenda_gestor_rodar(date '2026-11-03', pg_temp.em(date '2026-11-03', '18:07'));
    g := public.agenda_saude(date '2026-11-03', pg_temp.em(date '2026-11-03', '18:10')) -> 'gestor';
    v_res := pg_temp.ok(v_res, 'R7g o prazo de ter 03/11 18:00: a rodada das 18:07 aplica a do Giancarlo (vista antes: 10 dias, pelo prazo) e deixa as 3 não vistas abertas (Nelson, Flávio e, desde o 7a P12, o MP); prazo_vencido_sem_mostrar = 3 só se conta (zeros_ok continua)',
      (r #>> '{contagens,vetos,aplicadas}')::int = 1 and (r #>> '{contagens,vetos,sem_mostrar}')::int = 3
      and (g ->> 'prazo_vencido_sem_mostrar')::int = 3 and (g ->> 'zeros_ok')::boolean
      and (g #>> '{numeros,perguntas_com_prazo,pelo_prazo_7d}')::int = 1
      and (select dias = 10 and estimativa_fonte = 'orcamento' from public.os_planejamento where service_order_id = v_os),
      left(r #>> '{contagens,vetos}', 300) || ' / ' || (g ->> 'prazo_vencido_sem_mostrar'));

    -- o erro do fator: só com as medidas que têm fator (a medida por estimativa é válida e não tem fator)
    v_res := pg_temp.ok(v_res, 'R7h o erro do fator das métricas do aprendizado lê só as medidas com fator ("m.valida and m.fator is not null")',
      position('where m.valida and m.fator is not null' in pg_get_functiondef('public.agenda_saude(date, timestamp with time zone)'::regprocedure)) > 0);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r7$;

-- ── R8. O job agenda-gestor, pelo texto da migration ───────────────────────────────────────────────────────────
do $r8$
declare
  v_mig text := replace(coalesce(current_setting('agenda_teste.mig_rodada_fase7a', true), ''), E'\r\n', E'\n');
  v_b   text;
begin
  if v_mig = '' then
    insert into _resultado values ('R8 (o job pelo texto)', true, 'PULADO: sem agenda_teste.mig_rodada_fase7a (rode pela bancada)');
    return;
  end if;
  v_b := substr(v_mig, position(E'do $cron$\n' in v_mig));
  v_b := left(v_b, position(E'\n$cron$;' in v_b));
  insert into _resultado values ('R8a o job: só com pg_cron (sem ele, nada), desagenda o de mesmo nome antes, agenda ''agenda-gestor'' em ''7,22,37,52 10-23 * * 1-6'' e confere 1 job',
    v_b like E'%if not exists (select 1 from pg_extension where extname = ''pg_cron'') then%return;%'
    and position('perform cron.unschedule(''agenda-gestor'');' in v_b) > 0
    and position('perform cron.schedule(''agenda-gestor'', ''7,22,37,52 10-23 * * 1-6'',' in v_b) > 0
    and position('<> 1 then' in v_b) > 0, left(v_b, 300));
  insert into _resultado values ('R8b o comando: duas instruções — o statement_timeout de gestor_tempo_max (em segundos, "45s"; nenhum número escrito) e a rodada com _hoje_brt() e now()',
    position('$job$select set_config(''statement_timeout'', (select ceil(extract(epoch from c.gestor_tempo_max))::int::text || ''s'' from public.agenda_config c where c.id), false); select public.agenda_gestor_rodar(public._hoje_brt(), now());$job$' in v_b) > 0
    and substring(v_b from '\$job\$(.*)\$job\$') !~ '[0-9]', substring(v_b from '\$job\$(.*)\$job\$'));
  insert into _resultado values ('R8c na bancada (sem pg_cron) a migration não agendou nada: o bloco saiu cedo',
    not exists (select 1 from pg_extension where extname = 'pg_cron'), null);
end
$r8$;

-- ── R9. As cópias ─────────────────────────────────────────────────────────────────────────────────────────────
do $r9$
declare
  v_p7 text := coalesce(current_setting('agenda_teste.mig_rodada_fase7a', true), '');
  r    record;
  v_ok boolean := true;
  v_t  text := '';
begin
  if v_p7 = '' or coalesce(current_setting('agenda_teste.mig_correcao_revisao', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_leituras_fase2', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_correcao_livre', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_rodada_fase6', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_correcao_leituras', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_correcao_textos_fase6', true), '') = '' then
    insert into _resultado values ('R9 (as cópias)', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('_agenda_linhas_do_fechamento', 'agenda_teste.mig_correcao_revisao'),
      ('agenda_textos_do_fechamento', 'agenda_teste.mig_leituras_fase2'),
      ('agenda_ver', 'agenda_teste.mig_correcao_livre'),
      ('agenda_desfazer', 'agenda_teste.mig_rodada_fase6'),
      ('_agenda_ver_plano', 'agenda_teste.mig_correcao_leituras'),
      ('agenda_saude', 'agenda_teste.mig_correcao_textos_fase6')) t(nome, origem) loop
    if pg_temp.sem_fase7(pg_temp.corpo(v_p7, r.nome)) <> pg_temp.corpo(current_setting(r.origem), r.nome)
       or pg_temp.corpo(v_p7, r.nome) = pg_temp.corpo(current_setting(r.origem), r.nome) then
      v_ok := false;
      v_t := v_t || r.nome || ' ';
    end if;
  end loop;
  insert into _resultado values ('R9a as 6 recriadas, sem os blocos "-- FASE 7:", são o corpo da origem (e cada uma tem bloco)', v_ok, nullif(v_t, ''));
  insert into _resultado values ('R9b o que está no banco é a função da migration do P7 (agenda_saude e agenda_desfazer com o bloco gestor)',
    position('-- FASE 7: (7a P7, spec §11) o bloco gestor' in pg_get_functiondef('public.agenda_saude(date, timestamp with time zone)'::regprocedure)) > 0
    and position('-- FASE 7: (7a P7, spec R3 e §5.7)' in pg_get_functiondef('public.agenda_desfazer(uuid, uuid, text, date, timestamp with time zone)'::regprocedure)) > 0,
    null);
end
$r9$;

-- ── R10. O desfaz das ações do gestor e de quem saiu da equipe ───────────────────────────────────────────────────
do $r10$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d30  constant date := date '2026-10-30';
  r      jsonb;
  v_adm  uuid;
  v_nel  uuid;
  v_len  uuid;
  v_a    uuid;
  v_soltar uuid;
  v_ids  uuid[];
  v_n    int;
  v_sai  text[];
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('R10 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.replay('ligado');
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
    v_nel := pg_temp.os('OS-00112');
    v_len := pg_temp.os('OS-00074');
    -- estimar: os dias que o gestor gravou pelo prazo voltam a nulo
    v_a := public._agenda_gestor_gravar_dias(v_nel, 4, 'Sem resposta sobre Nelson até sex 30/10 às 18:00: contei o serviço inteiro, 4 dias (estimativa minha). *desfaz Nelson* volta.',
                                             null, pg_temp.em(c_d30, '18:07'));
    r := public.agenda_desfazer(v_a, v_adm, 'dono', c_d30, pg_temp.em(c_d30, '18:30'));
    v_res := pg_temp.ok(v_res, 'R10a estimar: o desfaz volta os dias, a fonte e a hora de antes (nulos), com o histórico, a ação desfazer e a original desfeita',
      (r ->> 'ok')::boolean
      and r ->> 'texto' = 'Desfeito: o Nelson (OS-00112) volta sem os dias que eu contei (4 dias). Me diga quantos dias são.'
      and (select dias is null and estimativa_fonte is null and estimativa_em is null from public.os_planejamento where service_order_id = v_nel)
      and (select exists (select 1 from jsonb_array_elements(historico) h where h ->> 'motivo' = 'desfeito')
             from public.os_planejamento where service_order_id = v_nel)
      and (select desfeita_em is not null from public.agenda_acoes where id = v_a)
      and exists (select 1 from public.agenda_acoes where tipo = 'desfazer' and desfaz_a = v_a), r::text);
    -- estimar, mas o dono disse outros dias depois: recusa
    v_a := public._agenda_gestor_gravar_dias(v_nel, 4, 'Sem resposta sobre Nelson: contei 4 dias.', null, pg_temp.em(c_d30, '18:40'));
    update public.os_planejamento set dias = 3, estimativa_fonte = 'dono', estimativa_em = pg_temp.em(c_d30, '19:00') where service_order_id = v_nel;
    r := public.agenda_desfazer(v_a, v_adm, 'dono', c_d30, pg_temp.em(c_d30, '19:05'));
    v_res := pg_temp.ok(v_res, 'R10b estimar depois que o dono disse os dias: o desfaz recusa e não mexe nos dias dele',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'Não desfaço: depois disso os dias do Nelson mudaram (3 dias). Para mudar de novo, me diga os dias.'
      and (select dias = 3 and estimativa_fonte = 'dono' from public.os_planejamento where service_order_id = v_nel), r::text);
    -- dupla: o *sem dupla* desfeito volta a *com dupla*; o *com dupla* desfeito depois volta ao normal (nada dito)
    r := public.agenda_dupla_dita(v_adm, 'Lenine', true, c_d30, pg_temp.em(c_d30, '09:00'));
    v_a := (r ->> 'acao_id')::uuid;
    r := public.agenda_dupla_dita(v_adm, 'Lenine', false, c_d30, pg_temp.em(c_d30, '09:10'));
    r := public.agenda_desfazer((r ->> 'acao_id')::uuid, v_adm, 'dono', c_d30, pg_temp.em(c_d30, '09:20'));
    v_res := pg_temp.ok(v_res, 'R10c dupla: o desfaz do *sem dupla* volta a *com dupla* (a marca de antes)',
      (r ->> 'ok')::boolean and r ->> 'texto' = 'Desfeito: o Lenine (OS-00074) volta com dupla.'
      and (select dupla_dita = 'todos' from public.os_planejamento where service_order_id = v_len), r::text);
    r := public.agenda_desfazer(v_a, v_adm, 'dono', c_d30, pg_temp.em(c_d30, '09:30'));
    v_res := pg_temp.ok(v_res, 'R10d dupla: o desfaz do *com dupla* (o que está gravado é o depois dela) volta ao normal',
      (r ->> 'ok')::boolean and r ->> 'texto' = 'Desfeito: o Lenine (OS-00074) volta ao normal: 1 pessoa, e dupla só quando você marcar.'
      and (select dupla_dita is null and dupla_motivo is null from public.os_planejamento where service_order_id = v_len), r::text);
    r := public.agenda_dupla_dita(v_adm, 'Lenine', true, c_d30, pg_temp.em(c_d30, '09:40'));
    v_a := (r ->> 'acao_id')::uuid;
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2 where service_order_id = v_len;
    r := public.agenda_desfazer(v_a, v_adm, 'dono', c_d30, pg_temp.em(c_d30, '09:50'));
    v_res := pg_temp.ok(v_res, 'R10e dupla mudada depois da ação: o desfaz recusa e diz como mudar',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'Não desfaço: depois disso a dupla do Lenine mudou. Diga *Lenine com dupla* ou *Lenine sem dupla*.'
      and (select dupla_dita = 'inicio' from public.os_planejamento where service_order_id = v_len), r::text);

    -- quem saiu da equipe: a reserva do Lenine (João e Roberto) solta pela vigia
    v_ids := array(select a.id from public.agenda_alocacoes a where a.service_order_id = v_len and a.tipo = 'reserva' and a.estado = 'publicada');
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'pessoa' where id = any (v_ids);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_canceladas, texto,
                                     desfazivel_ate)
    values (pg_temp.em(c_d30, '00:15'), c_d30, true, 'vigia', 'soltar_reserva', v_len, array[v_len], v_ids,
            'Soltei a reserva do Lenine: quem ia não está mais livre.', pg_temp.em(c_d30, '00:15') + interval '24 hours')
    returning id into v_soltar;
    v_n := (select count(*) from public.agenda_alocacoes where service_order_id = v_len and estado in ('publicada', 'fixada'));
    -- (f) João e Roberto saíram: nada volta, nada muda
    begin
      update public.agenda_disponibilidade set substituida_em = pg_temp.em(c_d30, '00:11')
       where payee_id in (pg_temp.pessoa('João'), pg_temp.pessoa('Roberto')) and substituida_em is null;
      r := public.agenda_desfazer(v_soltar, v_adm, 'dono', c_d30, pg_temp.em(c_d30, '09:30'));
      v_res := pg_temp.ok(v_res, 'R10f o desfaz que só traria quem saiu da equipe (João e Roberto) não muda nada e diz por quê',
        not (r ->> 'ok')::boolean and r ->> 'status' = 'saiu_da_equipe'
        and r ->> 'texto' = 'Não dá para desfazer como estava: João e Roberto não estão mais na equipe, e era com eles que o Lenine estava. Nada mudou; ele volta à agenda com a equipe de agora.'
        and (select count(*) from public.agenda_alocacoes where service_order_id = v_len and estado in ('publicada', 'fixada')) = v_n
        and (select desfeita_em is null from public.agenda_acoes where id = v_soltar), r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- (g) só o Roberto saiu: os meios-dias do João voltam e o texto diz quem não voltou
    begin
      update public.agenda_disponibilidade set substituida_em = pg_temp.em(c_d30, '00:11')
       where payee_id = pg_temp.pessoa('Roberto') and substituida_em is null;
      r := public.agenda_desfazer(v_soltar, v_adm, 'dono', c_d30, pg_temp.em(c_d30, '09:40'));
      v_sai := array(select distinct public._agenda_nome_curto(py.name) from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                      where a.id = any (array(select jsonb_array_elements_text(r -> 'recriadas')::uuid)));
      v_res := pg_temp.ok(v_res, 'R10g só o Roberto saiu: o desfaz traz de volta os meios-dias do João (e só eles) e diz que os do Roberto não voltam',
        (r ->> 'ok')::boolean and r ->> 'texto' = 'Desfeito: a reserva do Lenine (OS-00074) volta como estava. Roberto não está mais na equipe: os dias dele não voltam.'
        and v_sai = array['João'] and jsonb_array_length(r -> 'recriadas') = 6, r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- (h) ninguém saiu: o desfaz de sempre (as 12 voltam)
    r := public.agenda_desfazer(v_soltar, v_adm, 'dono', c_d30, pg_temp.em(c_d30, '09:45'));
    v_res := pg_temp.ok(v_res, 'R10h ninguém saiu da equipe: o desfaz de sempre (as 12 reservas voltam, o texto de antes)',
      (r ->> 'ok')::boolean and jsonb_array_length(r -> 'recriadas') = 12
      and r ->> 'texto' = 'Desfeito: a reserva do Lenine (OS-00074) volta como estava.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r10$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
