-- Prova da rodada, da saúde e das leituras da Agenda de Produção, Fase 7e (pacote P7; migration 20261111100600; spec-fase7e §5.6, §6.2–6.4, §8.3 e o bloco R7: R7.1, R7.3, R7.5-17,
-- R7.5-18, R7.6, R7.8-2, R7.12, R7.13).
-- bancada: depende de 20261111100600
--
--   R0  as funções: a nova (_agenda_saude_margem: porta, tipo), a migration cria 1 e recria as 6 da R7.1; cada recriada viva = a da migration, e sem os blocos do P7 = a da origem, byte a byte
--   R1  a orquestração: medir_compras e congelar_marcacao sempre (com os 6 desligados e com o aprendizado desligado); cada passo da margem só com o interruptor dele (o cru) fora de desligado,
--       ou com linha em uso; a peça sem fornecedor com o tempo de compra; o viés antes da folga da semana; o passo que falha não derruba; R1b: 57014 num passo grava parou_no e o tique
--       seguinte não repete (na medição, na Fase 6 e na margem); o relógio aprender_tempo_max pula a margem e grava parou_no; contagens.modos_margem
--   R2  os estados pela rodada inteira (o viés da §8.2): em teste → ligado (com o freio o gravador anda e o leitor não usa) → em uso → *desfaz aprendizado dias* (a frase do dono) → travado
--   R3  o "o que mudou" (_agenda_mudancas): a palavra de cada item da margem; o viés só com uma linha dele no instante; as palavras novas em agenda_desfazer_dito e a recusa que as diz
--   R4  a saúde: margem existe em todos os modos e não muda de um para o outro; sem promessa_antes_do_plano (AG7-32); cada violação forçada acende o zero dela e só ele; zeros_ok no ok;
--       os zeros do puxar batem com o P4c; os itens da margem fora dos zeros e das métricas do aprendizado da Fase 6; sem nada da margem, a saúde de antes, byte a byte (fora a chave nova)
--   R5  o foco: o bloco 8 byte a byte em teste e em uso (§6.2, R7.3-1), as linhas de "nenhuma … ainda", a temporada; a ordem total (o empate da integração); o corte por texto_max;
--       com os 6 desligados, o foco de antes, byte a byte; pela palavra do dono (agenda_ver foco aprendizado)
--   R6  o cartão: duracao.estimativa (em uso, o marcado, o do dono, em teste, o arredondamento que apaga) e duracao.promessa (R7.3-1); desligado, o de antes, byte a byte
--   R7  com tudo em sombra e a rodada em teste gravada, o motor, a prontidão, a vigia e a rodada do cliente são os de antes (md5): a régua sem chave
--   R8  a correção da conferência do P7, cada caso contra uma âncora de fora: o cartão em teste (a OS marcada; o regime sem o freio, com o gestor ligado e em teste) contra
--       agenda_meios_da_os ligado de verdade; carga_semana_fora (fora de ligado de verdade, 0; ligado, a conta antes de prender); o *desfaz* do viés (a classe que entrou com o geral; o
--       "voltam a") contra o leitor do motor; o bloco 8 com o freio contra o leitor; o "o que mudou" com os ids trocados
--
-- ═══ COMO RODAR ═══  Na bancada: node scripts/bancada-agenda/rodar.mjs. Em produção, só DEPOIS de aplicar a migration, com o OK: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7e_rodada.sql
--   Tudo dentro de begin/rollback. O que usa fixture só roda na bancada (fora dela sai PULADO). Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- O corpo (prosrc) de uma função no texto de uma migration
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
  v_tag text;
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v_tag := (regexp_match(v, E'\nas (\\$[a-z]*\\$)\n'))[1];
  v := substr(v, position(E'\nas ' || v_tag || E'\n' in v) + length(E'\nas ' || v_tag));
  return left(v, position(E'\n' || v_tag || ';' in v));
end $f$;
-- A definição inteira (do create ao $function$;)
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- (7g P6) o corpo vivo sem os blocos e as marcas da 7g ("-- FASE 7g:" … "-- FASE 7g: fim" e "-- (7g …" … "-- (7g: fim)"), linha a linha: a 7g recria agenda_saude
-- (20261112100500) com a chave explicar numa marca, e o resto do corpo é o desta migration. Sem marca da 7g, o corpo como está.
create function pg_temp.sem_7g(p_t text) returns text language plpgsql immutable as $f$
declare
  l text;
  fora text[] := '{}';
  dentro boolean := false;
begin
  foreach l in array string_to_array(replace(p_t, E'\r\n', E'\n'), E'\n') loop
    if not dentro and l ~ '^\s*-- (FASE 7g:|\(7g )' and l !~ '^\s*-- (FASE 7g: fim|\(7g: fim\))' then dentro := true; continue; end if;
    if dentro then
      if l ~ '^\s*-- (FASE 7g: fim|\(7g: fim\))' then dentro := false; end if;
      continue;
    end if;
    fora := fora || l;
  end loop;
  return array_to_string(fora, E'\n');
end $f$;
-- Sem os blocos do P7 ("-- FASE 7e: (7e P7" … "-- FASE 7e: fim" e "-- (7e P7" … "-- (7e: fim)"), linha a linha, como o montador
create function pg_temp.sem_p7(p_t text) returns text language plpgsql immutable as $f$
declare
  l text;
  fora text[] := '{}';
  dentro boolean := false;
begin
  foreach l in array string_to_array(replace(p_t, E'\r\n', E'\n'), E'\n') loop
    if not dentro and l ~ '^\s*-- (FASE 7e: \(7e P7|\(7e P7)' then dentro := true; continue; end if;
    if dentro and l ~ '^\s*-- (FASE 7e: fim|\(7e: fim\))' then dentro := false; continue; end if;
    if dentro then continue; end if;
    fora := fora || l;
  end loop;
  return array_to_string(fora, E'\n');
end $f$;

-- ── R0. As funções (sem fixture) ────────────────────────────────────────────────────────────────────
insert into _resultado
select 'R0a _agenda_saude_margem existe, stable, definer, search_path fixo; porta para authenticated e service_role (agenda_saude é invoker), nunca anon nem public',
       p.provolatile = 's' and p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c = 'search_path=public')
       and has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
       and not has_function_privilege('anon', p.oid, 'execute')
       and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'),
       null
  from pg_proc p where p.oid = 'public._agenda_saude_margem(date, timestamptz)'::regprocedure;

insert into _resultado
select 'R0b as recriadas mantêm a porta e o tipo: agenda_aprender definer só service_role; agenda_saude invoker; os_plano_da_os definer; _agenda_ver_aprendizado invoker; agenda_desfazer_dito definer; nenhuma para anon',
       (select p.prosecdef from pg_proc p where p.oid = 'public.agenda_aprender(date, timestamptz)'::regprocedure)
       and has_function_privilege('service_role', 'public.agenda_aprender(date, timestamptz)', 'execute')
       and not has_function_privilege('authenticated', 'public.agenda_aprender(date, timestamptz)', 'execute')
       and not (select p.prosecdef from pg_proc p where p.oid = 'public.agenda_saude(date, timestamptz)'::regprocedure)
       and (select p.prosecdef from pg_proc p where p.oid = 'public.os_plano_da_os(uuid, date)'::regprocedure)
       and not (select p.prosecdef from pg_proc p where p.oid = 'public._agenda_ver_aprendizado(date)'::regprocedure)
       and (select p.prosecdef from pg_proc p where p.oid = 'public.agenda_desfazer_dito(uuid, text, text, date, timestamptz)'::regprocedure)
       and not exists (select 1 from unnest(array['public.agenda_aprender(date, timestamptz)', 'public.agenda_saude(date, timestamptz)', 'public.os_plano_da_os(uuid, date)',
                                                  'public._agenda_ver_aprendizado(date)', 'public._agenda_mudancas(date, date, boolean, boolean, timestamptz)',
                                                  'public.agenda_desfazer_dito(uuid, text, text, date, timestamptz)']) s
                        where has_function_privilege('anon', s::regprocedure, 'execute')),
       null;

do $r0$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_rodada_fase7e', true), '');
  v_dif text;
  f     record;
begin
  if v_mig = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'R0c as cópias', true, 'PULADO: sem agenda_teste.mig_rodada_fase7e (rode pela bancada)'));
    return;
  end if;
  select string_agg(distinct m[1], ',' order by m[1]) into v_dif
    from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
  -- (a conferência do P7) + _agenda_desfazer_aprendizado: o *desfaz* do viés volta a classe que entrou em uso com o geral, e diz o que o leitor usa depois
  v_res := pg_temp.ok(v_res, 'R0c a migration cria 1 (a saúde da margem) e recria só as 6 da R7.1 do P7 e o *desfaz* do aprendizado (a conferência): nada do motor, da vigia nem do gravador',
    v_dif = '_agenda_desfazer_aprendizado,_agenda_mudancas,_agenda_saude_margem,_agenda_ver_aprendizado,agenda_aprender,agenda_desfazer_dito,agenda_saude,os_plano_da_os', v_dif);
  for f in select * from (values
      ('agenda_aprender', 'public.agenda_aprender(date, timestamptz)', 'mig_correcao_calculo_fase6'),
      ('agenda_saude', 'public.agenda_saude(date, timestamptz)', 'mig_cliente_fase7f'),
      ('os_plano_da_os', 'public.os_plano_da_os(uuid, date)', 'mig_leituras_fase7d'),
      ('_agenda_ver_aprendizado', 'public._agenda_ver_aprendizado(date)', 'mig_correcao_textos_fase6'),
      ('_agenda_mudancas', 'public._agenda_mudancas(date, date, boolean, boolean, timestamptz)', 'mig_correcao_revisao'),
      ('agenda_desfazer_dito', 'public.agenda_desfazer_dito(uuid, text, text, date, timestamptz)', 'mig_correcao_textos_fase6'),
      ('_agenda_desfazer_aprendizado', 'public._agenda_desfazer_aprendizado(uuid, uuid, text, date, timestamptz)', 'mig_correcao_calculo_fase6')) x(nome, sig, origem)
  loop
    v_res := pg_temp.ok(v_res, format('R0d %s: a viva é a desta migration; sem os blocos do P7, é a da origem (agenda_teste.%s), byte a byte; e tem bloco', f.nome, f.origem),
      (select pg_temp.sem_7g(p.prosrc) from pg_proc p where p.oid = f.sig::regprocedure) = pg_temp.corpo(v_mig, f.nome)
      and pg_temp.sem_p7(pg_temp.corpo(v_mig, f.nome)) = pg_temp.corpo(current_setting('agenda_teste.' || f.origem), f.nome)
      and pg_temp.corpo(v_mig, f.nome) ~ '-- (FASE 7e: \(7e P7|\(7e P7)',
      format('%s × %s letras', length(pg_temp.sem_p7(pg_temp.corpo(v_mig, f.nome))), length(pg_temp.corpo(current_setting('agenda_teste.' || f.origem), f.nome))));
  end loop;
  -- a marca da 7e em agenda_saude vem depois do último "-- (7f: fim)" e antes do return (R7.5-17), nunca dentro de bloco da 7f
  v_res := pg_temp.ok(v_res, 'R0e agenda_saude: a marca da margem logo depois do último "-- (7f: fim)", antes de "return v_gr;"',
    pg_temp.corpo(v_mig, 'agenda_saude') ~ E'-- \\(7f: fim\\)\n  -- \\(7e P7; §5\\.6, R7\\.5-17; dentro do bloco do gestor[^\n]*\n(  [^\n]*\n)*  -- \\(7e: fim\\)\n  return v_gr;', null);
  perform pg_temp.gravar(v_res);
end
$r0$;

-- ── A fixture e os ajudantes ───────────────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' then
    execute current_setting('agenda_teste.fase7e');
    -- Só as OS-7E* e a OS-E0 contam (as outras fixtures saem do caminho, como nos testes do P2 e do P3); e, como no V1 do P3, os casos do P2 com razão própria (V1, Z1, R1) também saem:
    -- ficam as 8 OS do viés, as 2 do dono e as inválidas da §8.2 (o geral 1,11; rv:energia 1,17; rv:geral 0,99; barco:energia 1,16; o dono 1,02)
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = 'e7e00000-0000-4000-8000-000000000e00'
     where (service_order_number not like 'OS-7E%' and service_order_number <> 'OS-E0' and merged_into_id is null)
        or id in (md5('e7e:os:V1')::uuid, md5('e7e:os:Z1')::uuid, md5('e7e:os:R1')::uuid);
    perform set_config('marineflow.agrupar_orcamentos', '', true);
  end if;
end
$carga$;

create function pg_temp.fx() returns boolean language sql stable as $f$ select coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' $f$;
create function pg_temp.adm() returns uuid language sql stable as $f$ select id from public.app_users where role = 'admin' and active order by id limit 1 $f$;
-- Os 6 interruptores da margem; o aprendizado ligado; o freio
create function pg_temp.modos(p_modo text, p_freio boolean default true) returns void language sql as $f$
  update public.agenda_config
     set modo_vies = p_modo, modo_folga_semana = p_modo, modo_urgencia = p_modo, modo_promessa = p_modo, modo_tempo_compra = p_modo, modo_folga_compra = p_modo,
         modo_aprendizado = 'ligado', gestor_so_propor = p_freio, vies_corrige_dono = true
   where id
$f$;
-- A rodada das 16:05 de novo no mesmo dia (a de antes sai: a rodada roda uma vez por dia)
create function pg_temp.rodar(r_hoje date default date '2027-01-07', r_agora timestamptz default timestamptz '2027-01-07 16:05-03') returns jsonb language plpgsql as $f$
begin
  set local session_replication_role = replica; delete from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = r_hoje; set local session_replication_role = origin;
  return public.agenda_aprender(r_hoje, r_agora);
end $f$;
create function pg_temp.margem(p_s jsonb) returns jsonb language sql immutable as $f$ select p_s -> 'margem' $f$;
-- A versão de antes do P7 de uma função, como função temporária com outro nome (o byte a byte da sombra)
create function pg_temp.criar_antes(p_nome text, p_origem text, p_novo text) returns void language plpgsql as $f$
declare
  v_c text := pg_temp.inteira(current_setting('agenda_teste.' || p_origem), p_nome);
begin
  execute replace(v_c, format('create or replace function public.%s(', p_nome), format('create or replace function pg_temp.%s(', p_novo));
end $f$;

-- ── R1. A orquestração ──────────────────────────────────────────────────────────────────────────────
do $r1$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  r2    jsonb;
  c     jsonb;
  c_hoje constant date := date '2027-01-07';
  c_agora constant timestamptz := timestamptz '2027-01-07 16:05-03';
  c_margem constant text[] := array['vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'];
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'R1 a orquestração', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    -- os 6 desligados: a medição de antes, mais as 2 que rodam sempre; nenhum passo da margem, nenhuma linha da margem
    perform pg_temp.modos('desligado');
    r := pg_temp.rodar();
    c := r -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1a os 6 desligados: congelar, medir, medir_compras e congelar_marcacao rodam; nenhum dos 6 da margem; nenhuma linha da margem; sem parou_no',
      c ?& array['congelar', 'medir', 'medir_compras', 'congelar_marcacao'] and not c ?| c_margem and not c ? 'parou_no' and (r ->> 'erros')::int = 0
      and not exists (select 1 from public.agenda_aprendizado a where a.item = any (c_margem)),
      c::text);
    v_res := pg_temp.ok(v_res, 'R1a2 contagens.modos_margem: os 6 interruptores da linha, também desligados (e gravados na rodada)',
      c -> 'modos_margem' = '{"vies":"desligado","folga_semana":"desligado","urgencia":"desligado","promessa":"desligado","tempo_compra":"desligado","folga_compra":"desligado"}'::jsonb
      and (select x.contagens -> 'modos_margem' = c -> 'modos_margem' from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = c_hoje),
      (c -> 'modos_margem')::text);
    -- a ordem dos passos: medir_compras e congelar_marcacao depois de medir e antes do fornecedor da Fase 6 (que já lê as compras)
    v_res := pg_temp.ok(v_res, 'R1a3 medir_compras rodou de verdade (as medidas de compra da fixture) e congelar_marcacao devolveu a contagem',
      (c -> 'medir_compras') ? 'olhadas' and (c -> 'congelar_marcacao') ? 'congeladas', (c -> 'medir_compras')::text || ' ' || (c -> 'congelar_marcacao')::text);
    -- em teste: os 6 rodam (a peça sem fornecedor com o tempo de compra)
    perform pg_temp.modos('sombra');
    r := pg_temp.rodar();
    c := r -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1b os 6 em sombra: os 6 passos da margem rodam, sem erro', c ?& c_margem and (r ->> 'erros')::int = 0, c::text);
    -- só o tempo de compra fora de desligado: ele e a peça sem fornecedor
    perform pg_temp.modos('desligado');
    update public.agenda_config set modo_tempo_compra = 'sombra' where id;
    c := pg_temp.rodar() -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1c só modo_tempo_compra em sombra: rodam tempo_compra e prazo_sem_fornecedor (a família das compras), e nenhum outro da margem',
      c ?& array['tempo_compra', 'prazo_sem_fornecedor'] and not c ?| array['vies', 'folga_semana', 'promessa', 'folga_compra']
      and c -> 'modos_margem' = '{"vies":"desligado","folga_semana":"desligado","urgencia":"desligado","promessa":"desligado","tempo_compra":"sombra","folga_compra":"desligado"}'::jsonb, c::text);
    -- a promessa pelo modo cru: o efetivo dela é sombra sempre, e com modo_promessa desligado ela não roda
    perform pg_temp.modos('desligado');
    update public.agenda_config set modo_promessa = 'sombra' where id;
    c := pg_temp.rodar() -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1d a promessa roda com modo_promessa em sombra e só ela; com ele desligado (R1a) não roda, embora _agenda_margem_modo(promessa) seja sombra sempre',
      c ? 'promessa' and not c ?| array['vies', 'folga_semana', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'] and public._agenda_margem_modo('promessa') = 'sombra'
      and c #>> '{modos_margem,promessa}' = 'sombra' and c #>> '{modos_margem,urgencia}' = 'desligado', c::text);
    -- o aprendizado desligado: nada da margem, mesmo com os 6 em sombra; a medição roda
    perform pg_temp.modos('sombra');
    update public.agenda_config set modo_aprendizado = 'desligado' where id;
    c := pg_temp.rodar() -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1e modo_aprendizado desligado: nenhum passo da margem (nem da Fase 6); a medição e as 2 novas rodam',
      not c ?| c_margem and c ?& array['congelar', 'medir', 'medir_compras', 'congelar_marcacao'] and not c ? 'fator', c::text);
    -- o viés antes da folga da semana (ela lê o medido dele): a folga, trocada por uma que diz se o viés já foi calculado nesta rodada
    perform pg_temp.modos('sombra');
    execute $x$create or replace function public._agenda_aprender_folga_semana(p_hoje date, p_agora timestamptz) returns jsonb language sql as
      $g$ select jsonb_build_object('viu_vies', exists (select 1 from public.agenda_aprendizado a where a.item = 'vies' and a.chave = 'estimativa:todas' and a.calculado_em = p_agora)) $g$$x$;
    set local session_replication_role = replica; delete from public.agenda_aprendizado where item = 'vies'; set local session_replication_role = origin;
    c := pg_temp.rodar() -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1f o viés roda antes da folga da semana: quando a folga roda, o viés desta rodada já está gravado', (c #>> '{folga_semana,viu_vies}')::boolean, (c -> 'folga_semana')::text);
    -- o passo que falha não derruba: a promessa lança, o tempo de compra (depois dela) roda; o erro vai a app_error_logs (aprender:promessa)
    execute $x$create or replace function public._agenda_aprender_promessa(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as
      $g$ begin raise exception 'estouro da promessa'; end $g$$x$;
    r := pg_temp.rodar();
    c := r -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1g a promessa lança: erros 1, falhas com o passo promessa, aprender:promessa no log; os de depois (tempo_compra, folga_compra, prazo_sem_fornecedor) rodam; sem parou_no',
      (r ->> 'erros')::int = 1 and r -> 'falhas' -> 0 ->> 'passo' = 'promessa' and not c ? 'promessa' and c ?& array['tempo_compra', 'folga_compra', 'prazo_sem_fornecedor']
      and not c ? 'parou_no' and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:promessa'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- R1b (R7.13): 57014 num passo grava parou_no e não repete; em cada lugar da rodada
  declare
    x record;
  begin
    for x in select * from (values ('_agenda_aprender_medir_compras', 'medir_compras', '(p_hoje date)'), ('_agenda_aprender_fator', 'fator', '(p_hoje date, p_agora timestamptz)'),
                                   ('_agenda_aprender_folga_semana', 'folga_semana', '(p_hoje date, p_agora timestamptz)')) t(fn, passo, args) loop
      begin
        perform pg_temp.modos('sombra');
        execute format($x$create or replace function public.%s%s returns jsonb language plpgsql as $g$ begin raise exception 'o tempo acabou' using errcode = '57014'; end $g$$x$, x.fn, x.args);
        r := pg_temp.rodar();
        c := r -> 'contagens';
        r2 := public.agenda_aprender(c_hoje, c_agora + interval '15 minutes');
        v_res := pg_temp.ok(v_res, format('R1h 57014 em %s: a rodada grava (rodou, a linha do dia com parou_no = %s), erros 1 com o sqlstate, o log com o passo; o que vem depois não roda; o tique seguinte não repete (ja_rodou)', x.passo, x.passo),
          (r ->> 'rodou')::boolean and c ->> 'parou_no' = x.passo and (r ->> 'erros')::int = 1 and r -> 'falhas' -> 0 ->> 'sqlstate' = '57014'
          and (select count(*) = 1 and bool_and(y.contagens ->> 'parou_no' = x.passo) from public.agenda_vigia_rodadas y where y.rotina = 'aprender' and y.p_hoje = c_hoje)
          and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:' || x.passo)
          and not c ?| case x.passo when 'medir_compras' then array['congelar_marcacao', 'fator', 'vies'] when 'fator' then array['mo', 'presenca', 'vies', 'promessa'] else array['promessa', 'tempo_compra'] end
          and case x.passo when 'folga_semana' then c ? 'vies' else true end
          and (r2 ->> 'rodou')::boolean is false and (r2 ->> 'ja_rodou')::boolean,
          format('%s | depois: %s', c::text, r2::text));
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
    end loop;
  end;

  -- o relógio: com aprender_tempo_max a zero (o CHECK sai só aqui dentro), a margem inteira fica para amanhã e a rodada diz onde parou; a Fase 6 rodou
  begin
    perform pg_temp.modos('sombra');
    alter table public.agenda_config drop constraint agenda_config_aprender_tempo_max_check;
    update public.agenda_config set aprender_tempo_max = interval '0 seconds' where id;
    r := pg_temp.rodar();
    c := r -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1i o relógio estourado: nenhum passo da margem, parou_no = vies (o 1º), sem erro nem log; a Fase 6 e a medição rodaram',
      not c ?| c_margem and c ->> 'parou_no' = 'vies' and (r ->> 'erros')::int = 0 and c ?& array['fator', 'medir_compras', 'congelar_marcacao']
      and not exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action like 'aprender:vies%'), c::text);
    update public.agenda_config set aprender_tempo_max = interval '20 seconds' where id;
    c := pg_temp.rodar() -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1i2 com o relógio de 20 s, a mesma rodada roda a margem inteira e sem parou_no', c ?& c_margem and not c ? 'parou_no', c::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- a linha em uso com o interruptor desligado volta ao "em teste" na rodada seguinte (o passo roda só por ela); sem linha em uso, não roda
  begin
    perform pg_temp.modos('desligado');
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, em_uso_desde, estado, calculado_em)
    values ('tempo_compra', 'todas', 'geral', 1, 3, 4, 3, 3, c_agora - interval '3 days', 'em_uso', c_agora - interval '3 days');
    c := pg_temp.rodar() -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1j o tempo de compra em uso com o interruptor desligado: o passo roda por ele (e só ele e a peça sem fornecedor ficam de fora) e a linha sai de uso',
      c ? 'tempo_compra' and not c ? 'prazo_sem_fornecedor' and not c ? 'vies'
      and (select em_uso is null and estado in ('sombra', 'medindo') from public.agenda_aprendizado where item = 'tempo_compra' and chave = 'todas'),
      (select format('%s %s', estado, em_uso) from public.agenda_aprendizado where item = 'tempo_compra' and chave = 'todas'));
    c := pg_temp.rodar() -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1j2 na rodada seguinte, sem linha em uso e com o interruptor desligado, ele não roda mais', not c ? 'tempo_compra', c::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- o erro comum num dos 2 passos que rodam sempre: conta, vai ao log (aprender:medir_compras) e o outro roda
  begin
    perform pg_temp.modos('desligado');
    execute $x$create or replace function public._agenda_aprender_medir_compras(p_hoje date) returns jsonb language plpgsql as
      $g$ begin raise exception 'estouro das compras'; end $g$$x$;
    r := pg_temp.rodar();
    c := r -> 'contagens';
    v_res := pg_temp.ok(v_res, 'R1k medir_compras lança (erro comum): erros 1, a falha com o passo, aprender:medir_compras no log; congelar_marcacao e a Fase 6 rodam; sem parou_no',
      (r ->> 'erros')::int = 1 and r -> 'falhas' -> 0 ->> 'passo' = 'medir_compras' and not c ? 'medir_compras' and c ?& array['congelar_marcacao', 'fator']
      and not c ? 'parou_no' and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:medir_compras'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r1$;

-- ── R2 e R3. Os estados pela rodada inteira; o "o que mudou" e as palavras ─────────────────────────
do $r2$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  d     jsonb;
  v_m   jsonb;
  v_t   text;
  c_hoje constant date := date '2027-01-07';
  c_agora constant timestamptz := timestamptz '2027-01-07 16:05-03';
  n_acoes int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'R2 os estados pela rodada', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    -- em teste: o viés da §8.2 medido, nada em uso, nenhuma ação
    perform pg_temp.modos('sombra');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'R2a em teste (a rodada inteira): o geral 1,11 e rv:energia 1,17 em sombra, sem em uso nem ação da margem',
      (select estado = 'sombra' and calculado = 1.11 and em_uso is null from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas')
      and (select estado = 'sombra' and calculado = 1.17 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:energia')
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'aprendizado' and a.antes ->> 'item' = 'vies'),
      (r -> 'contagens' -> 'vies')::text);
    -- ligado, com o freio: o gravador anda (o modo cru, R7.6), o leitor não usa (o efetivo é sombra)
    perform pg_temp.modos('ligado', true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'R2b ligado com o freio: a rodada põe o geral em uso (1,00 → 1,11, um passo) e rv:energia (1,17); _agenda_margem_em_uso é nulo com o freio e 1,11 sem ele',
      (select estado = 'em_uso' and em_uso = 1.11 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas')
      and (select em_uso = 1.17 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:energia')
      and public._agenda_margem_em_uso('vies', 'estimativa:todas') is null,
      (r -> 'contagens' -> 'vies')::text);
    update public.agenda_config set gestor_so_propor = false where id;
    v_res := pg_temp.ok(v_res, 'R2b2 sem o freio, o leitor usa o que a rodada pôs', public._agenda_margem_em_uso('vies', 'estimativa:todas') = 1.11, null);
    -- o "o que mudou" das 17:30: as ações da margem com o texto da §6.3; o viés tem várias linhas no instante (o geral e as classes): sem palavra
    v_m := public._agenda_mudancas(c_hoje, c_hoje, true, true, c_agora + interval '85 minutes');
    v_t := (select string_agg(x, ' | ' order by o, k) from jsonb_array_elements(v_m) with ordinality e(g, o), jsonb_array_elements_text(g -> 'itens') with ordinality i(x, k));
    v_res := pg_temp.ok(v_res, 'R3a o "o que mudou": o viés entra com o texto da ação (§6.3: "Aprendi com as OS concluídas: …"), e com várias linhas do viés no mesmo instante ninguém diz "*desfaz aprendizado dias* volta só essa"',
      v_t like '%Aprendi com as OS concluídas: as OS levam 1,11× o que eu estimo pelo orçamento (8 OS). Passei a marcar os dias delas com 1,11× (era 1,00×), só nos serviços que eu ainda não marquei.%'
      and v_t not like '%aprendizado dias%', left(v_t, 900));
    -- *desfaz aprendizado dias*: a frase do dono, como o WhatsApp manda (o alvo "aprendizado dias"), até o que fica gravado
    n_acoes := (select count(*) from public.agenda_acoes a where a.tipo = 'aprendizado' and a.antes ->> 'item' <> 'vies' and a.desfeita_em is null);
    d := public.agenda_desfazer_dito(pg_temp.adm(), 'aprendizado dias', 'whatsapp', c_hoje, c_agora + interval '90 minutes');
    v_res := pg_temp.ok(v_res, 'R2c *desfaz aprendizado dias* (a frase do dono): ok, desfaz só as ações do viés (as dos outros itens ficam), e o geral fica travado no que valia antes (o padrão)',
      (d ->> 'ok')::boolean and (d ->> 'mudou')::boolean
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'aprendizado' and a.antes ->> 'item' = 'vies' and a.desfeita_em is null and a.executada)
      and (select count(*) from public.agenda_acoes a where a.tipo = 'aprendizado' and a.antes ->> 'item' <> 'vies' and a.desfeita_em is null) = n_acoes
      and (select estado = 'travado' and em_uso is null from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas'),
      d::text);
    -- a rodada seguinte respeita a trava (o medido não andou)
    r := pg_temp.rodar(c_hoje + 1, c_agora + interval '1 day');
    v_res := pg_temp.ok(v_res, 'R2d a rodada do dia seguinte: o geral continua travado e sem ação nova',
      (select estado = 'travado' from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas')
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'aprendizado' and a.antes ->> 'item' = 'vies' and a.dia = c_hoje + 1), (r -> 'contagens' -> 'vies')::text);
    -- de novo: nada mais do viés para desfazer, e a palavra diz isso
    d := public.agenda_desfazer_dito(pg_temp.adm(), 'aprendizado dias', 'whatsapp', c_hoje + 1, c_agora + interval '1 day 1 hour');
    v_res := pg_temp.ok(v_res, 'R2e *desfaz aprendizado dias* de novo: "Não tenho mudança do aprendizado dos dias das OS para desfazer agora."',
      not (d ->> 'ok')::boolean and d ->> 'texto' = 'Não tenho mudança do aprendizado dos dias das OS para desfazer agora.', d::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- R3: a palavra de cada item (ações postas à mão, como o gravador as grava: origem vigia, executada, desfazível)
  begin
    perform pg_temp.modos('ligado', false);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate)
    values (c_agora - interval '1 day', c_hoje - 1, true, 'vigia', 'aprendizado', 'Aprendi com as OS concluídas: as OS levam 1,11× o que eu estimo pelo orçamento (8 OS). *desfaz aprendizado* volta.',
            '{"item": "vies", "chave": "estimativa:todas", "nivel": "todas", "em_uso": null, "valor": 1, "estado": "sombra"}', '{"item": "vies", "chave": "estimativa:todas", "nivel": "todas", "em_uso": 1.11, "n": 8, "alvo": 1.11}',
            c_agora + interval '6 days'),
           (c_agora, c_hoje, true, 'vigia', 'aprendizado', 'Medi 8 semanas de serviço marcado: as OS variaram menos do que eu contava. *desfaz aprendizado* volta.',
            '{"item": "folga_semana", "chave": "equipe", "nivel": "geral", "em_uso": null, "valor": 0.15, "estado": "sombra"}', '{"item": "folga_semana", "chave": "equipe", "nivel": "geral", "em_uso": 0.11, "n": 8, "alvo": 0.11}',
            c_agora + interval '7 days'),
           (c_agora, c_hoje, true, 'vigia', 'aprendizado', 'Medi o seu tempo da aprovação até a compra (4 OS). *desfaz aprendizado* volta.',
            '{"item": "tempo_compra", "chave": "todas", "nivel": "geral", "em_uso": null, "valor": 1, "estado": "sombra"}', '{"item": "tempo_compra", "chave": "todas", "nivel": "geral", "em_uso": 2, "n": 4, "alvo": 2}',
            c_agora + interval '7 days');
    v_m := public._agenda_mudancas(c_hoje - 1, c_hoje, true, false, c_agora + interval '1 hour');
    v_t := (select string_agg(x, ' | ' order by o, k) from jsonb_array_elements(v_m) with ordinality e(g, o), jsonb_array_elements_text(g -> 'itens') with ordinality i(x, k));
    v_res := pg_temp.ok(v_res, 'R3b o viés sozinho no instante dele (ontem) é a 1ª linha desfazível: "*desfaz aprendizado* volta tudo; *desfaz aprendizado dias* volta só essa."',
      v_t like '%Aprendi com as OS concluídas: as OS levam 1,11× o que eu estimo pelo orçamento (8 OS). *desfaz aprendizado* volta tudo; *desfaz aprendizado dias* volta só essa.%', left(v_t, 900));
    set local session_replication_role = replica; delete from public.agenda_acoes where antes ->> 'item' = 'vies'; set local session_replication_role = origin;
    v_m := public._agenda_mudancas(c_hoje - 1, c_hoje, true, false, c_agora + interval '1 hour');
    v_t := (select string_agg(x, ' | ' order by o, k) from jsonb_array_elements(v_m) with ordinality e(g, o), jsonb_array_elements_text(g -> 'itens') with ordinality i(x, k));
    v_res := pg_temp.ok(v_res, 'R3c a folga da semana e o tempo de compra no mesmo instante: a 1ª pela ordem fixa (a folga) diz "*desfaz aprendizado semana* volta só essa"',
      v_t like '%*desfaz aprendizado* volta tudo; *desfaz aprendizado semana* volta só essa.%' and v_t not like '%aprendizado compra%', left(v_t, 900));
    set local session_replication_role = replica; delete from public.agenda_acoes where antes ->> 'item' = 'folga_semana'; set local session_replication_role = origin;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate)
    values (c_agora + interval '1 minute', c_hoje, true, 'vigia', 'aprendizado', 'Cada diária rendeu R$ 800 de mão de obra (3 OS). *desfaz aprendizado* volta.',
            '{"item": "mo", "chave": "todas", "nivel": "todas", "em_uso": null, "valor": 764, "estado": "sombra"}', '{"item": "mo", "chave": "todas", "nivel": "todas", "em_uso": 800, "n": 3}',
            c_agora + interval '7 days');
    v_m := public._agenda_mudancas(c_hoje, c_hoje, true, false, c_agora + interval '1 hour');
    v_t := (select string_agg(x, ' | ' order by o, k) from jsonb_array_elements(v_m) with ordinality e(g, o), jsonb_array_elements_text(g -> 'itens') with ordinality i(x, k));
    v_res := pg_temp.ok(v_res, 'R3d o tempo de compra antes de um item da Fase 6 (o valor, 1 minuto depois): a palavra fica com o mais antigo: "*desfaz aprendizado compra* volta só essa."',
      v_t like '%Medi o seu tempo da aprovação até a compra (4 OS). *desfaz aprendizado* volta tudo; *desfaz aprendizado compra* volta só essa.%'
      and v_t not like '%aprendizado valor%', left(v_t, 900));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- as palavras novas e a recusa
  begin
    d := public.agenda_desfazer_dito(pg_temp.adm(), 'aprendizado semana', 'whatsapp', c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'R3e *desfaz aprendizado semana* sem ação: "Não tenho mudança do aprendizado da folga da semana para desfazer agora."',
      d ->> 'texto' = 'Não tenho mudança do aprendizado da folga da semana para desfazer agora.' and d ->> 'status' = 'nenhuma', d::text);
    d := public.agenda_desfazer_dito(pg_temp.adm(), 'o aprendizado compra', 'whatsapp', c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'R3f *desfaz o aprendizado compra* sem ação: "… do seu tempo de compra …"',
      d ->> 'texto' = 'Não tenho mudança do aprendizado do seu tempo de compra para desfazer agora.', d::text);
    d := public.agenda_desfazer_dito(pg_temp.adm(), 'aprendizado folga', 'whatsapp', c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'R3g "folga" continua sendo a do aviso de atraso', d ->> 'texto' = 'Não tenho mudança do aprendizado da folga do aviso de atraso para desfazer agora.', d::text);
    d := public.agenda_desfazer_dito(pg_temp.adm(), 'aprendizado xyzw', 'whatsapp', c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'R3h a coisa que não existe: a recusa de antes, com a saída (*desfaz aprendizado* sozinho volta tudo); as palavras novas não mudam a recusa',
      d ->> 'status' = 'nao_achei'
      and d ->> 'texto' = 'Não achei isso no que eu aprendi. Diga *desfaz aprendizado* e fator, presença, valor, folga, capacidade ou o nome do fornecedor (ou só *desfaz aprendizado*, que volta tudo).',
      d::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r2$;

-- ── R4. A saúde ─────────────────────────────────────────────────────────────────────────────────────
do $r4$
declare
  v_res jsonb := '[]'::jsonb;
  s     jsonb;
  m     jsonb;
  v_ref text;
  v     record;
  c_hoje constant date := date '2027-01-07';
  c_agora constant timestamptz := timestamptz '2027-01-07 16:05-03';
  c_zeros constant text[] := array['passo_maior_que_o_limite', 'fora_dos_limites', 'em_uso_com_interruptor_fora', 'carga_semana_fora', 'puxar_cancelou', 'puxar_duas_vezes',
                                   'rodada_puxar_atrasada', 'medida_compra_sem_aprovacao'];
  v_os  uuid := 'e7e00000-0000-4000-8000-000000000e00';
  v_pr  uuid;
  v_al  uuid;
  v_al2 uuid;
  v_dif text;
  k     text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'R4 a saúde', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.modos('desligado');
    s := public.agenda_saude(c_hoje, c_agora);
    m := s -> 'margem';
    v_res := pg_temp.ok(v_res, 'R4a a chave margem: os 8 zeros da §5.6 em 0 (sem o promessa_antes_do_plano: AG7-32), zeros_ok, os números; sem os modos',
      m ?& c_zeros and not m ? 'promessa_antes_do_plano' and not m ? 'modos' and (m ->> 'zeros_ok')::boolean and m ? 'numeros'
      and (select bool_and(m ->> z = '0') from unnest(c_zeros) z)
      and (select count(*) from jsonb_object_keys(m) j) = cardinality(c_zeros) + 2,
      m::text);
    -- a chave não muda de um modo para o outro (antes da hora do puxar, sem nada da margem)
    v_ref := md5(m::text);
    v_dif := null;
    foreach k in array array['sombra', 'ligado'] loop
      perform pg_temp.modos(k);
      if md5((public.agenda_saude(c_hoje, c_agora) -> 'margem')::text) is distinct from v_ref then v_dif := coalesce(v_dif || ', ', '') || k; end if;
    end loop;
    perform pg_temp.modos('sombra', false);
    if md5((public.agenda_saude(c_hoje, c_agora) -> 'margem')::text) is distinct from v_ref then v_dif := coalesce(v_dif || ', ', '') || 'sombra sem o freio'; end if;
    v_res := pg_temp.ok(v_res, 'R4b margem igual (md5) com os 6 desligados, em sombra e ligados com o freio, e em sombra sem o freio', v_dif is null, v_dif);
    -- sem nada da margem, a saúde é a de antes, byte a byte, fora a chave nova (a versão de antes do P7 como função temporária)
    perform pg_temp.criar_antes('agenda_saude', 'mig_cliente_fase7f', 'saude_antes');
    v_dif := null;
    foreach k in array array['desligado', 'sombra', 'ligado'] loop
      perform pg_temp.modos(k);
      -- (7g P6: e sem a chave explicar, que a 7g soma depois, como a margem)
      if (public.agenda_saude(c_hoje, c_agora) - 'margem' - 'explicar')::text is distinct from pg_temp.saude_antes(c_hoje, c_agora)::text then v_dif := coalesce(v_dif || ', ', '') || k; end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'R4c sem linha nem ação da margem: agenda_saude sem a chave margem = a de antes do P7, byte a byte, nos 3 modos (o ok também)', v_dif is null, v_dif);
    v_res := pg_temp.ok(v_res, 'R4d o zeros_ok da margem entra no ok, depois de todos (a linha de agenda_saude)',
      (select p.prosrc ~ E'''margem'', public\\._agenda_saude_margem\\(p_hoje, p_agora\\)\\);\n  v_gr := jsonb_set\\(v_gr, ''\\{ok\\}'', to_jsonb\\(coalesce\\(\\(v_gr ->> ''ok''\\)::boolean, false\\)\n\\s+and coalesce\\(\\(v_gr #>> ''\\{margem,zeros_ok\\}''\\)::boolean, true\\)\\)\\);'
         from pg_proc p where p.oid = 'public.agenda_saude(date, timestamptz)'::regprocedure), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- cada violação forçada acende o zero dela e só ele (e zeros_ok cai); cada uma num bloco desfeito
  for v in select * from (values ('passo_maior_que_o_limite', 2), ('fora_dos_limites', 1), ('em_uso_com_interruptor_fora', 1), ('carga_semana_fora', 6), ('puxar_cancelou', 1),
                                 ('puxar_duas_vezes', 1), ('rodada_puxar_atrasada', 1), ('medida_compra_sem_aprovacao', 1)) t(chave, n) loop
    begin
      perform pg_temp.modos('desligado');
      s := null;
      if v.chave = 'passo_maior_que_o_limite' then
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate)
        values (c_agora - interval '1 day', c_hoje - 1, true, 'vigia', 'aprendizado', 'um passo de 0,45 (maior que 0,30)',
                '{"item": "vies", "chave": "estimativa:todas", "nivel": "todas", "em_uso": null, "valor": 1, "estado": "sombra"}', '{"item": "vies", "chave": "estimativa:todas", "em_uso": 1.45}', c_agora + interval '6 days'),
               -- o controle: um passo no limite (0,30) e a volta da folga (0,05) não acendem
               (c_agora - interval '1 day', c_hoje - 1, true, 'vigia', 'aprendizado', 'um passo de 0,30, no limite',
                '{"item": "vies", "chave": "estimativa:rv:energia", "nivel": "fina", "em_uso": 1.1, "valor": 1.1, "estado": "em_uso"}', '{"item": "vies", "chave": "estimativa:rv:energia", "em_uso": 1.4}', c_agora + interval '6 days'),
               (c_agora - interval '1 day', c_hoje - 1, true, 'vigia', 'aprendizado', 'a folga volta 0,05',
                '{"item": "folga_semana", "chave": "equipe", "nivel": "geral", "em_uso": 0.3, "valor": 0.3, "estado": "em_uso"}', '{"item": "folga_semana", "chave": "equipe", "em_uso": 0.25}', c_agora + interval '6 days'),
               -- a 2ª que acende: a folga com um passo de 0,10 (o limite dela é 0,05, não o 0,30 do viés)
               (c_agora - interval '1 day', c_hoje - 1, true, 'vigia', 'aprendizado', 'a folga anda 0,10',
                '{"item": "folga_semana", "chave": "equipe", "nivel": "geral", "em_uso": 0.25, "valor": 0.25, "estado": "em_uso"}', '{"item": "folga_semana", "chave": "equipe", "em_uso": 0.15}', c_agora + interval '6 days'),
               -- o controle do arredondamento: de 1,166 (o valor com mais casas) a 1,47 (o em uso gravado com 2) são 0,304, que em 2 casas é o limite (0,30): não acende
               (c_agora - interval '1 day', c_hoje - 1, true, 'vigia', 'aprendizado', 'um passo de 0,30 em 2 casas',
                '{"item": "vies", "chave": "estimativa:barco:geral", "nivel": "fina", "em_uso": null, "valor": 1.166, "estado": "sombra"}', '{"item": "vies", "chave": "estimativa:barco:geral", "em_uso": 1.47}', c_agora + interval '6 days'),
               -- o controle da janela: o passo grande de 8 dias atrás não conta
               (c_agora - interval '8 days', c_hoje - 8, true, 'vigia', 'aprendizado', 'um passo grande antigo',
                '{"item": "vies", "chave": "estimativa:rv:geral", "nivel": "fina", "em_uso": null, "valor": 1, "estado": "sombra"}', '{"item": "vies", "chave": "estimativa:rv:geral", "em_uso": 1.6}', c_agora - interval '1 day');
      elsif v.chave = 'fora_dos_limites' then
        insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, estado, calculado_em)
        values ('vies', 'estimativa:todas', 'todas', 1, 1, 8, 2.8, 'sombra', c_agora),
               -- os controles: o viés de 0,80 está dentro dos limites dele (fora dos do prazo real); o prazo real de 1,00 está dentro dos dele (fora dos do viés não)
               ('vies', 'estimativa:rv:energia', 'fina', 1, 1, 4, 0.8, 'sombra', c_agora),
               ('promessa', 'todas', 'todas', 1.5, 1, 8, 1.0, 'sombra', c_agora);
      elsif v.chave = 'em_uso_com_interruptor_fora' then
        -- o controle: a mesma linha recalculada há menos de aprender_atraso_h não acende (a rodada a limpa no dia)
        insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, em_uso_desde, estado, calculado_em)
        values ('vies', 'estimativa:todas', 'todas', 1, 1, 8, 1.11, 1.11, c_agora - interval '30 hours', 'em_uso', c_agora - interval '30 hours'),
               ('vies', 'estimativa:rv:energia', 'fina', 1.11, 1, 4, 1.17, 1.17, c_agora - interval '2 hours', 'em_uso', c_agora - interval '2 hours');
        -- e o item com o interruptor ligado não é "interruptor fora", mesmo atrasado (a rodada que não passou é outro aviso)
        update public.agenda_config set modo_tempo_compra = 'ligado' where id;
        insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, em_uso_desde, estado, calculado_em)
        values ('tempo_compra', 'todas', 'todas', 1, 1, 5, 2, 2, c_agora - interval '30 hours', 'em_uso', c_agora - interval '30 hours');
      elsif v.chave = 'carga_semana_fora' then
        -- (a conferência do P7) só com a folga da semana ligada de verdade (sem o freio): a conta 0,80 − a temporada fica abaixo do mínimo 0,85 nas 6 semanas
        perform pg_temp.modos('ligado', false);
        update public.agenda_config set carga_semana_min = 0.85 where id;
      elsif v.chave = 'puxar_cancelou' then
        insert into public.agenda_propostas (escopo, periodo, os_alvo, modo, estado, versao_base, itens, parametros, expira_em, criada_por)
        values ('os', daterange(c_hoje, c_hoje + 10, '[]'), array[v_os], 'ligado', 'aberta', (select versao_plano from public.agenda_config where id), '[]'::jsonb,
                jsonb_build_object('p_hoje', c_hoje, 'p_restricoes', jsonb_build_object('puxar', jsonb_build_object('dia', c_hoje + 1, 'os', v_os))), c_agora + interval '1 day', 'vigia')
        returning id into v_pr;
        insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, reserva_de, publicada_em)
        values (v_os, 'e7e00000-0000-4000-8000-00000000aa02', date '2027-03-01', 'manha', 'turno', 'reserva', 'publicada', 'motor', 'teto', c_agora - interval '2 days') returning id into v_al;
        insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
        values (v_os, 'e7e00000-0000-4000-8000-00000000aa02', date '2027-03-02', 'manha', 'turno', 'execucao', 'publicada', 'motor', c_agora) returning id into v_al2;
        -- o que o P4c deixa (a reserva publicada da própria OS vira compromisso: 0) e a reserva FIXADA cancelada (o defeito que ele consertou: 1)
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, alocacoes_criadas, alocacoes_canceladas, antes, depois, texto)
        values (c_agora, c_hoje, true, 'vigia', 'criar', v_os, array[v_os], v_pr, array[v_al2], array[v_al],
                jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('alocacao_id', v_al, 'estado', 'publicada'))), '{}'::jsonb, 'puxada: a reserva vira compromisso'),
               (c_agora, c_hoje, true, 'vigia', 'criar', v_os, array[v_os], v_pr, array[v_al2], array[v_al],
                jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('alocacao_id', v_al, 'estado', 'fixada', 'fixado_por', 'dono'))), '{}'::jsonb, 'puxada: cancelou a fixada'),
               -- o controle: a ação do puxar que não criou nem cancelou nada não cancelou (0)
               (c_agora, c_hoje, true, 'vigia', 'criar', v_os, array[v_os], v_pr, '{}'::uuid[], '{}'::uuid[], '{}'::jsonb, '{}'::jsonb, 'puxada: nada');
      elsif v.chave = 'puxar_duas_vezes' then
        insert into public.agenda_vigia_rodadas (p_hoje, p_agora, modo_proposta, modo_vigia, contagens, rotina)
        values (c_hoje - 1, c_agora - interval '1 day', 'ligado', 'ligado', '{"puxar": {"rodou": true, "puxadas": 1}}', 'gestor'),
               (c_hoje - 1, c_agora - interval '1 day' + interval '16 minutes', 'ligado', 'ligado', '{"puxar": {"rodou": true, "puxadas": 0}}', 'gestor'),
               -- o controle: o tique seguinte do mesmo dia com "já rodou" não conta
               (c_hoje - 1, c_agora - interval '1 day' + interval '32 minutes', 'ligado', 'ligado', '{"puxar": {"rodou": false, "ja_rodou": true}}', 'gestor'),
               -- e o dia de antes, com o puxar uma vez e um "já rodou": 1 rodada só, não conta
               (c_hoje - 2, c_agora - interval '2 days', 'ligado', 'ligado', '{"puxar": {"rodou": true, "puxadas": 0}}', 'gestor'),
               (c_hoje - 2, c_agora - interval '2 days' + interval '16 minutes', 'ligado', 'ligado', '{"puxar": {"rodou": false, "ja_rodou": true}}', 'gestor');
      elsif v.chave = 'rodada_puxar_atrasada' then
        update public.agenda_config set modo_urgencia = 'sombra', modo_proposta = 'ligado', modo_marcar_sozinho = 'ligado' where id;
        s := public.agenda_saude(c_hoje, timestamptz '2027-01-07 18:45-03');
      elsif v.chave = 'medida_compra_sem_aprovacao' then
        perform set_config('agenda.porta', 'on', true);
        insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at)
        values (md5('e7e:p7:orc')::uuid, 'ORC-7E-P7', 'e7e00000-0000-4000-8000-000000000c00', 'e7e00000-0000-4000-8000-000000000b00', 'draft', 'draft', 'repair', c_agora - interval '20 days', c_agora - interval '20 days');
        insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_por)
        values (md5('e7e:p7:orc:m')::uuid, md5('e7e:p7:orc')::uuid, 'dono', 'Peça', 1, 0, true, 'comprado', null, pg_temp.adm());
        insert into public.agenda_medidas_compra (os_material_id, service_order_id, sem_fornecedor, entrega, aprovada_em, precisou_em, comprado_em, comprado_fonte,
                                                  valida_tempo, valida_prazo, valida_folga, medida_em)
        values (md5('e7e:p7:orc:m')::uuid, md5('e7e:p7:orc')::uuid, true, 'linha:orc', c_hoje - 20, c_hoje - 20, c_hoje - 15, 'dono', true, false, false, c_agora);
        -- os controles: a medida da OS aberta com orçamento aprovado (OS-E0) e a da OS ainda em rascunho com o orçamento já aprovado não acendem
        insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at)
        values (md5('e7e:p7:orc2')::uuid, 'ORC-7E-P7b', 'e7e00000-0000-4000-8000-000000000c00', 'e7e00000-0000-4000-8000-000000000b00', 'draft', 'approved', 'repair', c_agora - interval '20 days', c_agora - interval '20 days');
        insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_por)
        values (md5('e7e:p7:orc2:m')::uuid, md5('e7e:p7:orc2')::uuid, 'dono', 'Peça', 1, 0, true, 'comprado', null, pg_temp.adm());
        insert into public.agenda_medidas_compra (os_material_id, service_order_id, sem_fornecedor, entrega, aprovada_em, precisou_em, comprado_em, comprado_fonte,
                                                  valida_tempo, valida_prazo, valida_folga, medida_em)
        values (md5('e7e:p7:orc2:m')::uuid, md5('e7e:p7:orc2')::uuid, true, 'linha:orc2', c_hoje - 20, c_hoje - 20, c_hoje - 15, 'dono', true, false, false, c_agora),
               (md5('e7e:material:m1')::uuid, v_os, true, 'linha:e0', c_hoje - 20, c_hoje - 20, c_hoje - 15, 'dono', true, false, false, c_agora);
      end if;
      s := coalesce(s, public.agenda_saude(c_hoje, c_agora));
      m := s -> 'margem';
      v_res := pg_temp.ok(v_res, format('R4e %s forçado = %s (e os outros zeros da margem continuam 0; zeros_ok cai)', v.chave, v.n),
        (m ->> v.chave)::int = v.n and not (m ->> 'zeros_ok')::boolean
        and (select bool_and(m ->> z = '0') from unnest(c_zeros) z where z <> v.chave),
        m::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;

  -- o em uso com o interruptor fora, com o aprendizado desligado: a rodada não roda nada do aprendizado e o leitor não usa a linha; não acusa (senão acusaria para sempre)
  begin
    perform pg_temp.modos('desligado');
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, em_uso_desde, estado, calculado_em)
    values ('vies', 'estimativa:todas', 'todas', 1, 1, 8, 1.11, 1.11, c_agora - interval '30 hours', 'em_uso', c_agora - interval '30 hours');
    v_res := pg_temp.ok(v_res, 'R4i a linha em uso com o interruptor desligado há 30 h: 1 com o aprendizado ligado; 0 com ele desligado (a rodada não a limparia)',
      (public.agenda_saude(c_hoje, c_agora) #>> '{margem,em_uso_com_interruptor_fora}')::int = 1, null);
    update public.agenda_config set modo_aprendizado = 'desligado' where id;
    v_res := pg_temp.ok(v_res, 'R4i2 o mesmo, com o aprendizado desligado: 0', (public.agenda_saude(c_hoje, c_agora) #>> '{margem,em_uso_com_interruptor_fora}')::int = 0, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- o puxar de verdade, pela 2ª reserva (a publicada da própria OS que vira compromisso): 0; e o "puxou sem criar nada": 1
  begin
    perform pg_temp.modos('desligado');
    insert into public.agenda_propostas (escopo, periodo, os_alvo, modo, estado, versao_base, itens, parametros, expira_em, criada_por)
    values ('os', daterange(c_hoje, c_hoje + 10, '[]'), array[v_os], 'ligado', 'aberta', (select versao_plano from public.agenda_config where id), '[]'::jsonb,
            jsonb_build_object('p_hoje', c_hoje, 'p_restricoes', jsonb_build_object('puxar', jsonb_build_object('dia', c_hoje + 1, 'os', v_os))), c_agora + interval '1 day', 'vigia')
    returning id into v_pr;
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, reserva_de, publicada_em)
    values (v_os, 'e7e00000-0000-4000-8000-00000000aa02', date '2027-03-01', 'manha', 'turno', 'reserva', 'publicada', 'motor', 'teto', c_agora - interval '2 days') returning id into v_al;
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_os, 'e7e00000-0000-4000-8000-00000000aa02', date '2027-03-02', 'manha', 'turno', 'execucao', 'publicada', 'motor', c_agora) returning id into v_al2;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, alocacoes_criadas, alocacoes_canceladas, antes, depois, texto)
    values (c_agora, c_hoje, true, 'vigia', 'criar', v_os, array[v_os], v_pr, array[v_al2], array[v_al],
            jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('alocacao_id', v_al, 'estado', 'publicada'))), '{}'::jsonb, 'puxada: a reserva vira compromisso');
    m := public.agenda_saude(c_hoje, c_agora) -> 'margem';
    v_res := pg_temp.ok(v_res, 'R4f o puxar como o P4c o deixa (a OS puxada com o compromisso novo, a reserva publicada dela cancelada): puxar_cancelou 0; puxadas_28d 1',
      (m ->> 'puxar_cancelou')::int = 0 and (m #>> '{numeros,puxadas_28d}')::int = 1, m::text);
    set local session_replication_role = replica; update public.agenda_acoes set alocacoes_criadas = '{}' where proposta_id = v_pr; set local session_replication_role = origin;
    m := public.agenda_saude(c_hoje, c_agora) -> 'margem';
    v_res := pg_temp.ok(v_res, 'R4f2 a mesma ação sem criar nada (a OS "puxada" sem compromisso: o defeito do P4c): puxar_cancelou 1; e ela não conta como puxada', (m ->> 'puxar_cancelou')::int = 1 and (m #>> '{numeros,puxadas_28d}')::int = 0, m::text);
    set local session_replication_role = replica; update public.agenda_acoes set alocacoes_criadas = array[v_al2], alocacoes_canceladas = array[v_al2] where proposta_id = v_pr; set local session_replication_role = origin;
    m := public.agenda_saude(c_hoje, c_agora) -> 'margem';
    v_res := pg_temp.ok(v_res, 'R4f3 a ação do puxar que cancela um compromisso (não reserva): puxar_cancelou 1', (m ->> 'puxar_cancelou')::int = 1, m::text);
    -- a ação de uma proposta que não é do puxar não conta
    set local session_replication_role = replica; update public.agenda_acoes set alocacoes_criadas = '{}', alocacoes_canceladas = array[v_al] where proposta_id = v_pr; set local session_replication_role = origin;
    set local session_replication_role = replica; update public.agenda_propostas set parametros = jsonb_build_object('p_hoje', c_hoje, 'p_restricoes', '{}'::jsonb) where id = v_pr; set local session_replication_role = origin;
    m := public.agenda_saude(c_hoje, c_agora) -> 'margem';
    v_res := pg_temp.ok(v_res, 'R4f4 a mesma ação, de uma proposta que não é do puxar: 0', (m ->> 'puxar_cancelou')::int = 0, m::text);
    -- o atraso do puxar: antes de puxar_hora + 1 h, 0; em dia não útil, 0; com o puxar desligado, 0; com a rodada do gestor que rodou o puxar, 0
    update public.agenda_config set modo_urgencia = 'sombra', modo_proposta = 'ligado', modo_marcar_sozinho = 'ligado' where id;
    v_res := pg_temp.ok(v_res, 'R4g rodada_puxar_atrasada: 0 às 18:29 (puxar_hora 17:30 + 1 h), 1 às 18:31; 0 no sábado; 0 com o puxar desligado',
      (public.agenda_saude(c_hoje, timestamptz '2027-01-07 18:29-03') #>> '{margem,rodada_puxar_atrasada}')::int = 0
      and (public.agenda_saude(c_hoje, timestamptz '2027-01-07 18:31-03') #>> '{margem,rodada_puxar_atrasada}')::int = 1
      and (public.agenda_saude(date '2027-01-09', timestamptz '2027-01-09 18:45-03') #>> '{margem,rodada_puxar_atrasada}')::int = 0, null);
    insert into public.agenda_vigia_rodadas (p_hoje, p_agora, modo_proposta, modo_vigia, contagens, rotina)
    values (c_hoje, timestamptz '2027-01-07 17:37-03', 'ligado', 'ligado', '{"puxar": {"rodou": true, "em_teste": true, "puxadas": 1}}', 'gestor');
    v_res := pg_temp.ok(v_res, 'R4g2 com a rodada do gestor de hoje que rodou o puxar (em teste): 0; e o número em teste conta 1',
      (public.agenda_saude(c_hoje, timestamptz '2027-01-07 18:45-03') #>> '{margem,rodada_puxar_atrasada}')::int = 0
      and (public.agenda_saude(c_hoje, timestamptz '2027-01-07 18:45-03') #>> '{margem,numeros,puxadas_em_teste_28d}')::int = 1, null);
    update public.agenda_config set modo_urgencia = 'desligado' where id;
    v_res := pg_temp.ok(v_res, 'R4g3 com o puxar desligado, 0 (sem rodada nenhuma)', (public.agenda_saude(date '2027-01-08', timestamptz '2027-01-08 18:45-03') #>> '{margem,rodada_puxar_atrasada}')::int = 0, null);
    update public.agenda_config set modo_urgencia = 'sombra', modo_marcar_sozinho = 'desligado', modo_encaixe_aprovacao = 'desligado', modo_revisao_diaria = 'desligado', modo_compre_ate = 'desligado' where id;
    v_res := pg_temp.ok(v_res, 'R4g4 com o gestor parado (marcar, encaixe, revisão e compre até desligados), o puxar não tem rodada que o chame: 0; com um deles ligado, 1',
      (public.agenda_saude(date '2027-01-08', timestamptz '2027-01-08 18:45-03') #>> '{margem,rodada_puxar_atrasada}')::int = 0, null);
    update public.agenda_config set modo_compre_ate = 'ligado' where id;
    v_res := pg_temp.ok(v_res, 'R4g5 com só o compre até ligado, o gestor roda e o atraso do puxar acende (1)',
      (public.agenda_saude(date '2027-01-08', timestamptz '2027-01-08 18:45-03') #>> '{margem,rodada_puxar_atrasada}')::int = 1, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- os itens da margem saem dos zeros e das métricas do aprendizado da Fase 6 (e ficam na margem); o controle: um item da Fase 6 continua contando
  begin
    perform pg_temp.modos('ligado', false);
    insert into public.agenda_vigia_rodadas (p_hoje, p_agora, modo_proposta, modo_vigia, contagens, rotina)
    values (c_hoje, c_agora - interval '1 hour', 'ligado', 'ligado', jsonb_build_object('modo_aprendizado', 'ligado', 'ligados', '["fator"]'::jsonb), 'aprender');
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, em_uso_desde, estado, calculado_em)
    values ('vies', 'estimativa:todas', 'todas', 1, 1, 8, 1.11, 1.11, c_agora, 'em_uso', c_agora),
           -- a folga da semana que volta ao padrão por passo, sem medida (R7.4): em uso, calculado nulo, n abaixo do mínimo
           ('folga_semana', 'equipe', 'geral', 0.15, 8, 3, null, 0.2, c_agora, 'em_uso', c_agora);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate)
    values (c_agora - interval '30 minutes', c_hoje, true, 'vigia', 'aprendizado', 'o passo do viés',
            '{"item": "vies", "chave": "estimativa:todas", "nivel": "todas", "em_uso": null, "valor": 1, "estado": "sombra"}', '{"item": "vies", "chave": "estimativa:todas", "em_uso": 1.11}', c_agora + interval '6 days');
    s := public.agenda_saude(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'R4h com a margem em uso: em_uso_fora_de_ligado, troca_grande_sem_pergunta e em_uso_com_amostra_pequena da Fase 6 não a contam (0); metricas.itens sem os itens da margem; a margem os tem',
      s #>> '{aprendizado,em_uso_fora_de_ligado}' = '0' and s #>> '{aprendizado,troca_grande_sem_pergunta}' = '0' and s #>> '{aprendizado,em_uso_com_amostra_pequena}' = '0'
      and not (s #> '{aprendizado,metricas,itens}') ?| array['vies', 'folga_semana']
      and (s #> '{margem,numeros,itens}') ?& array['vies', 'folga_semana'] and (s #>> '{margem,numeros,trocas_28d,passos}')::int = 1,
      (s -> 'aprendizado')::text);
    -- a versão de antes do P7 contava os 3 (o que este pacote consertou)
    perform pg_temp.criar_antes('agenda_saude', 'mig_cliente_fase7f', 'saude_antes2');
    s := pg_temp.saude_antes2(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'R4h2 o controle: a agenda_saude de antes do P7 contava os 3 (o viés e a folga fora de ligado: 2; a troca do viés: 1; a folga sem amostra: 1) e listava os itens da margem nas métricas',
      s #>> '{aprendizado,em_uso_fora_de_ligado}' = '2' and s #>> '{aprendizado,troca_grande_sem_pergunta}' = '1' and s #>> '{aprendizado,em_uso_com_amostra_pequena}' = '1'
      and (s #> '{aprendizado,metricas,itens}') ?& array['vies', 'folga_semana'], (s -> 'aprendizado')::text);
    -- um item da Fase 6 nas mesmas condições continua contando
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, em_uso_desde, estado, calculado_em)
    values ('mo', 'todas', 'todas', 764, 3, 1, 800, 800, c_agora, 'em_uso', c_agora);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate)
    values (c_agora - interval '20 minutes', c_hoje, true, 'vigia', 'aprendizado', 'a troca grande do valor',
            '{"item": "mo", "chave": "todas", "nivel": "todas", "em_uso": null, "valor": 764, "estado": "sombra"}', '{"item": "mo", "chave": "todas", "em_uso": 1500}', c_agora + interval '6 days');
    s := public.agenda_saude(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'R4h3 o controle: o valor por diária em uso com amostra pequena, fora da lista e com a troca grande conta 1 nos 3 (a Fase 6 continua acusando); a troca dele não é passo da margem (passos continua 1)',
      s #>> '{aprendizado,em_uso_fora_de_ligado}' = '1' and s #>> '{aprendizado,troca_grande_sem_pergunta}' = '1' and s #>> '{aprendizado,em_uso_com_amostra_pequena}' = '1'
      and (s #>> '{margem,numeros,trocas_28d,passos}')::int = 1,
      (s -> 'aprendizado')::text || ' | ' || (s #> '{margem,numeros,trocas_28d}')::text);
    update public.agenda_aprendizado set calculado = 0.2 where item = 'folga_semana';
    s := public.agenda_saude(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'R4h4 a folga da semana em uso com amostra pequena e COM medido não é a volta ao padrão: em_uso_com_amostra_pequena conta ela também (2)',
      s #>> '{aprendizado,em_uso_com_amostra_pequena}' = '2', (s -> 'aprendizado')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r4$;

-- ── R5. O foco aprendizado ──────────────────────────────────────────────────────────────────────────
do $r5$
declare
  v_res jsonb := '[]'::jsonb;
  f     jsonb;
  f2    jsonb;
  l8    jsonb;
  v_t   text;
  v_n   int;
  c_hoje constant date := date '2027-01-07';
  c_agora constant timestamptz := timestamptz '2027-01-07 16:05-03';
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'R5 o foco', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  perform pg_temp.criar_antes('_agenda_ver_aprendizado', 'mig_correcao_textos_fase6', 'ver_antes');
  begin
    -- com os 6 desligados e sem linha da margem: o foco de antes, byte a byte; também depois da rodada (que com os 6 desligados não grava linha da margem)
    perform pg_temp.modos('desligado');
    perform pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'R5a os 6 desligados, depois da rodada: o foco é o de antes do P7, byte a byte (o texto e os dados)',
      public._agenda_ver_aprendizado(c_hoje)::text = pg_temp.ver_antes(c_hoje)::text, null);
    -- em teste, sem medida nenhuma da margem: as linhas de "nenhuma … ainda" (§6.2, R7.3-1), uma por item, na ordem
    perform pg_temp.modos('sombra');
    set local session_replication_role = replica; delete from public.agenda_aprendizado where item in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'); set local session_replication_role = origin;
    update public.agenda_config set texto_max = 3000 where id;
    f := public._agenda_ver_aprendizado(c_hoje);
    l8 := (select x -> 'linhas' from jsonb_array_elements(f #> '{dados,blocos}') x where (x ->> 'bloco')::int = 8);
    v_res := pg_temp.ok(v_res, 'R5b em teste sem medida: o bloco 8 "margem" com as linhas de "nenhuma … ainda", byte a byte, na ordem (viés, folga, temporada, prazo real, compra, folga da compra, peça sem fornecedor)',
      (select x ->> 'nome' from jsonb_array_elements(f #> '{dados,blocos}') x where (x ->> 'bloco')::int = 8) = 'margem'
      and (select jsonb_agg(e ->> 'texto' order by o) from jsonb_array_elements(l8) with ordinality t(e, o)) = jsonb_build_array(
        'Estimativa pelo valor: nenhuma OS medida ainda; marco os dias como saem do orçamento.',
        'Folga da semana: nenhuma semana com serviço marcado medida ainda; guardo 20% da semana da equipe (15% para o serviço que passa do previsto e 5% para urgência e falta).',
        'Em teste: na semana de 11/01 eu guardaria mais 10% para urgência (temporada de barco) e marcaria até 70% da semana da equipe, e não 80%.',
        'Prazo real: nenhuma OS medida ainda. Só para você: ao cliente não digo data de pronto.',
        'Seu tempo para comprar: nenhuma OS medida ainda (da aprovação até a compra); no "compre até" conto 1 dia útil (padrão).',
        'OS marcadas antes da compra: nenhuma medida ainda; dou 1 dia útil entre a chegada da peça e o 1º dia, como em todas.',
        'Peças compradas sem fornecedor dito antes: nenhuma compra medida ainda; conto 7 dias úteis (padrão).')
      and f ->> 'texto' like '%• Estimativa pelo valor: nenhuma OS medida ainda; marco os dias como saem do orçamento.%',
      l8::text);
    -- os blocos 1–7 não mudam: tirado o bloco 8, os dados e o texto são os de antes
    f2 := pg_temp.ver_antes(c_hoje);
    v_res := pg_temp.ok(v_res, 'R5c em teste: tirado o bloco 8, os blocos de antes iguais (os dados), e o texto de antes é o de agora sem as linhas do bloco 8',
      (select jsonb_agg(x order by o) from jsonb_array_elements(f #> '{dados,blocos}') with ordinality t(x, o) where (x ->> 'bloco')::int <> 8) = f2 #> '{dados,blocos}'
      and (select string_agg(l, E'\n' order by o) from regexp_split_to_table(f ->> 'texto', E'\n') with ordinality t(l, o)
            where l not in (select '• ' || (e ->> 'texto') from jsonb_array_elements(l8) e)) = f2 ->> 'texto',
      null);
    -- pela palavra do dono: *agenda aprendizado* é agenda_ver foco aprendizado
    v_res := pg_temp.ok(v_res, 'R5d pela palavra do dono (agenda_ver foco aprendizado, o que *agenda aprendizado* chama): o mesmo texto, com o bloco 8',
      (public.agenda_ver(null, null, null, 'aprendizado', null, null, false, c_hoje) ->> 'texto') = f ->> 'texto', null);
    -- a semana sem temporada e sem folga medida: em teste eu marcaria os mesmos 80%, e a linha da temporada não sai (lição 5); num bloco desfeito
    begin
      update public.agenda_config set folga_temporada_barco = array_fill(0::numeric, array[12]), folga_temporada_rv = array_fill(0::numeric, array[12]) where id;
      f2 := public._agenda_ver_aprendizado(c_hoje);
      v_res := pg_temp.ok(v_res, 'R5k em teste, a semana sem temporada e sem folga medida (marcaria os mesmos 80%): sem a linha da temporada; as outras do bloco 8 iguais',
        (select jsonb_agg(e ->> 'texto' order by o) from jsonb_array_elements((select x -> 'linhas' from jsonb_array_elements(f2 #> '{dados,blocos}') x where (x ->> 'bloco')::int = 8))
                                                       with ordinality t(e, o))
          = (select jsonb_agg(e ->> 'texto' order by o) from jsonb_array_elements(l8) with ordinality t(e, o) where e ->> 'item' <> 'temporada')
        and (select count(*) from jsonb_array_elements(l8) e where e ->> 'item' = 'temporada') = 1,
        (select string_agg(e ->> 'texto', ' | ') from jsonb_array_elements(f2 #> '{dados,blocos}') x, jsonb_array_elements(x -> 'linhas') e where (x ->> 'bloco')::int = 8));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- a rodada em teste com o viés da §8.2: as linhas em teste do viés, byte a byte (§6.2); a classe que repete o geral não sai; a do dono sai
    perform pg_temp.rodar();
    f := public._agenda_ver_aprendizado(c_hoje);
    l8 := (select x -> 'linhas' from jsonb_array_elements(f #> '{dados,blocos}') x where (x ->> 'bloco')::int = 8);
    v_t := (select string_agg(e ->> 'texto', ' | ' order by o) from jsonb_array_elements(l8) with ordinality t(e, o) where e ->> 'item' = 'vies');
    v_res := pg_temp.ok(v_res, 'R5e em teste, depois da rodada: o viés da §8.2 byte a byte, o geral, as classes (n maior primeiro) e o do dono por último',
      v_t = 'Em teste: as OS levam 1,11× o que eu estimo pelo orçamento (8 OS medidas). Hoje marco os dias como saem do orçamento.'
            || ' | Em teste: as OS de energia em motorhome levam 1,17× o que eu estimo pelo orçamento (4 OS medidas; junto com o geral das OS). Hoje marco os dias como saem do orçamento.'
            || ' | Em teste: as OS de outros serviços em motorhome levam 0,99× o que eu estimo pelo orçamento (3 OS medidas; junto com o geral das OS). Hoje marco os dias como saem do orçamento.'
            || ' | Em teste: as OS de energia em barco levam 1,16× o que eu estimo pelo orçamento (1 OS medidas; junto com o geral das OS). Hoje marco os dias como saem do orçamento.'
            || ' | Em teste: nos dias que você diz, as OS levam 1,02× o que você combinou (2 OS medidas). Hoje conto os seus dias como você disse.'
      and (select count(*) from jsonb_array_elements(l8) e where e ->> 'item' = 'promessa') = 1
      and (select count(*) from public.agenda_aprendizado a where a.item = 'promessa') > 1,
      v_t);
    -- em uso (ligado, sem o freio): o geral no alvo, a classe a caminho não, todas no alvo (um passo cabe)
    perform pg_temp.modos('ligado', false);
    perform pg_temp.rodar();
    f := public._agenda_ver_aprendizado(c_hoje);
    l8 := (select x -> 'linhas' from jsonb_array_elements(f #> '{dados,blocos}') x where (x ->> 'bloco')::int = 8);
    v_res := pg_temp.ok(v_res, 'R5f em uso (ligado, sem o freio): "As OS levam 1,11× o que eu estimo pelo orçamento (8 OS medidas): marco os dias delas com 1,11× desde qui 07/01." (§6.2)',
      exists (select 1 from jsonb_array_elements(l8) e
               where e ->> 'texto' = 'As OS levam 1,11× o que eu estimo pelo orçamento (8 OS medidas): marco os dias delas com 1,11× desde qui 07/01.' and e ->> 'estado' = 'em_uso')
      and exists (select 1 from jsonb_array_elements(l8) e where e ->> 'item' = 'temporada'
                    and e ->> 'texto' = 'Temporada: na semana de 11/01 guardo mais 10% para urgência (temporada de barco): marco até 70% da semana da equipe.'),
      (select string_agg(e ->> 'texto', ' | ') from jsonb_array_elements(l8) e));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- a ordem total: as 3 linhas das compras (chave todas, nível geral, o mesmo estado e n) gravadas em ordens físicas diferentes dão o mesmo foco; o de antes do P7 dava foco diferente
  declare
    a1 text; a2 text; b1 text; b2 text;
  begin
    perform pg_temp.modos('sombra');
    update public.agenda_config set texto_max = 3000 where id;
    set local session_replication_role = replica; delete from public.agenda_aprendizado where item in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'); set local session_replication_role = origin;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, estado, texto, calculado_em) values
      ('prazo_sem_fornecedor', 'todas', 'geral', 7, 3, 1, 'medindo', 'Peças compradas sem fornecedor dito antes: 1 de 3 compras medidas; conto 7 dias úteis (padrão).', c_agora),
      ('folga_compra', 'todas', 'geral', 0, 3, 1, 'medindo', 'OS marcadas antes da compra: 1 de 3 medidas; dou 1 dia útil entre a chegada da peça e o 1º dia, como em todas.', c_agora),
      ('tempo_compra', 'todas', 'geral', 1, 3, 1, 'medindo', 'Seu tempo para comprar: 1 de 3 OS medidas (da aprovação até a compra); no "compre até" conto 1 dia útil (padrão).', c_agora);
    a1 := public._agenda_ver_aprendizado(c_hoje)::text;
    b1 := pg_temp.ver_antes(c_hoje)::text;
    set local session_replication_role = replica; delete from public.agenda_aprendizado where item in ('tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'); set local session_replication_role = origin;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, estado, texto, calculado_em) values
      ('tempo_compra', 'todas', 'geral', 1, 3, 1, 'medindo', 'Seu tempo para comprar: 1 de 3 OS medidas (da aprovação até a compra); no "compre até" conto 1 dia útil (padrão).', c_agora),
      ('folga_compra', 'todas', 'geral', 0, 3, 1, 'medindo', 'OS marcadas antes da compra: 1 de 3 medidas; dou 1 dia útil entre a chegada da peça e o 1º dia, como em todas.', c_agora),
      ('prazo_sem_fornecedor', 'todas', 'geral', 7, 3, 1, 'medindo', 'Peças compradas sem fornecedor dito antes: 1 de 3 compras medidas; conto 7 dias úteis (padrão).', c_agora);
    a2 := public._agenda_ver_aprendizado(c_hoje)::text;
    b2 := pg_temp.ver_antes(c_hoje)::text;
    v_res := pg_temp.ok(v_res, 'R5g a ordem total: as 3 linhas das compras gravadas em 2 ordens físicas dão o mesmo foco, na ordem do item (compra, folga da compra, peça sem fornecedor)',
      a1 = a2 and position('Seu tempo para comprar' in a1) < position('OS marcadas antes da compra' in a1)
      and position('OS marcadas antes da compra' in a1) < position('Peças compradas sem fornecedor' in a1), null);
    v_res := pg_temp.ok(v_res, 'R5g2 o controle: o foco de antes do P7, com as mesmas linhas, muda com a ordem física (o empate que a conferência da integração reproduziu)', b1 <> b2, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- o corte por texto_max: as linhas do bloco 8 saem antes das dos blocos 1–7, salvo as em uso
  begin
    perform pg_temp.modos('ligado', false);
    update public.agenda_config set texto_max = 3000 where id;
    perform pg_temp.rodar();
    f := public._agenda_ver_aprendizado(c_hoje);
    v_n := char_length(f ->> 'texto');
    -- o teto um pouco abaixo do texto inteiro: tem de sair 1 linha, e ela é do bloco 8 (a última dele que não está em uso)
    update public.agenda_config set texto_max = v_n - 5 where id;
    f2 := public._agenda_ver_aprendizado(c_hoje);
    l8 := (select x -> 'linhas' from jsonb_array_elements(f #> '{dados,blocos}') x where (x ->> 'bloco')::int = 8);
    v_res := pg_temp.ok(v_res, 'R5h o corte: com o teto logo abaixo do texto, sai uma linha do bloco 8 que não está em uso ("• e mais 1" no bloco 8); todas as linhas dos blocos 1–7 ficam; as em uso do bloco 8 ficam',
      position('e mais' in f ->> 'texto') = 0
      and char_length(f2 ->> 'texto') <= v_n - 5
      and (select bool_and(position('• ' || (e ->> 'texto') in f2 ->> 'texto') > 0)
             from jsonb_array_elements(f #> '{dados,blocos}') x, jsonb_array_elements(x -> 'linhas') e where (x ->> 'bloco')::int <> 8)
      and (select bool_and(position('• ' || (e ->> 'texto') in f2 ->> 'texto') > 0) from jsonb_array_elements(l8) e where e ->> 'estado' in ('em_uso', 'travado'))
      and (select count(*) = 1 from jsonb_array_elements(l8) e where position('• ' || (e ->> 'texto') in f2 ->> 'texto') = 0)
      and f2 ->> 'texto' like '%• e mais 1%',
      format('%s → %s letras', v_n, char_length(f2 ->> 'texto')));
    -- o teto que tira exatamente as linhas do bloco 8 que não estão em uso: saem todas elas, nenhuma em uso, nenhuma dos blocos 1–7
    v_n := char_length(f ->> 'texto')
           - (select sum(char_length('• ' || (e ->> 'texto')) + 1) from jsonb_array_elements(l8) e where e ->> 'estado' not in ('em_uso', 'travado'))::int
           + char_length('• e mais ' || (select count(*) from jsonb_array_elements(l8) e where e ->> 'estado' not in ('em_uso', 'travado'))) + 1;
    if v_n >= 400 then
      update public.agenda_config set texto_max = v_n where id;
      f2 := public._agenda_ver_aprendizado(c_hoje);
      v_res := pg_temp.ok(v_res, 'R5h2 o teto que tira todas as linhas do bloco 8 que não estão em uso: elas saem, as em uso ficam (as do viés e a da temporada), e os blocos 1–7 inteiros',
        (select bool_and(position('• ' || (e ->> 'texto') in f2 ->> 'texto') > 0)
               from jsonb_array_elements(f #> '{dados,blocos}') x, jsonb_array_elements(x -> 'linhas') e where (x ->> 'bloco')::int <> 8)
        and (select bool_and(position('• ' || (e ->> 'texto') in f2 ->> 'texto') > 0) from jsonb_array_elements(l8) e where e ->> 'estado' in ('em_uso', 'travado'))
        and (select bool_and(position('• ' || (e ->> 'texto') in f2 ->> 'texto') = 0) from jsonb_array_elements(l8) e where e ->> 'estado' not in ('em_uso', 'travado'))
        and (select count(*) from jsonb_array_elements(l8) e where e ->> 'estado' in ('em_uso', 'travado')) >= 2,
        format('teto %s → %s letras', v_n, char_length(f2 ->> 'texto')));
      -- um pouco abaixo desse teto: a próxima linha que sai é dos blocos 1–7, e as em uso do bloco 8 continuam
      if v_n - 5 >= 400 then
        update public.agenda_config set texto_max = v_n - 5 where id;
        f2 := public._agenda_ver_aprendizado(c_hoje);
        v_res := pg_temp.ok(v_res, 'R5h3 um pouco abaixo desse teto: a próxima linha que sai é dos blocos 1–7; as em uso do bloco 8 ficam',
          (select bool_and(position('• ' || (e ->> 'texto') in f2 ->> 'texto') > 0) from jsonb_array_elements(l8) e where e ->> 'estado' in ('em_uso', 'travado'))
          and exists (select 1 from jsonb_array_elements(f #> '{dados,blocos}') x, jsonb_array_elements(x -> 'linhas') e
                       where (x ->> 'bloco')::int <> 8 and position('• ' || (e ->> 'texto') in f2 ->> 'texto') = 0),
          format('teto %s → %s letras', v_n - 5, char_length(f2 ->> 'texto')));
      else
        v_res := pg_temp.ok(v_res, 'R5h3 um pouco abaixo do teto do R5h2', false, format('o teto daria %s, abaixo do mínimo de texto_max (400)', v_n - 5));
      end if;
    else
      v_res := pg_temp.ok(v_res, 'R5h2 o teto que tira as linhas do bloco 8 que não estão em uso', false, format('o teto daria %s, abaixo do mínimo de texto_max (400)', v_n));
    end if;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- em teste, o teto que tira o bloco 8 inteiro: sai ele todo (com a 1ª linha dele) antes de qualquer linha dos blocos 1–7, e vira "(e mais N linhas)" no fim do corpo
  begin
    perform pg_temp.modos('sombra');
    update public.agenda_config set texto_max = 3000 where id;
    perform pg_temp.rodar();
    f := public._agenda_ver_aprendizado(c_hoje);
    l8 := (select x -> 'linhas' from jsonb_array_elements(f #> '{dados,blocos}') x where (x ->> 'bloco')::int = 8);
    v_n := char_length(f ->> 'texto') - (select sum(char_length('• ' || (e ->> 'texto')) + 1) from jsonb_array_elements(l8) e)::int
           + char_length(format('(e mais %s linhas)', jsonb_array_length(l8))) + 1;
    if v_n >= 400 and position('e mais' in f ->> 'texto') = 0 then
      update public.agenda_config set texto_max = v_n where id;
      f2 := public._agenda_ver_aprendizado(c_hoje);
      v_res := pg_temp.ok(v_res, 'R5j em teste, o teto que tira o bloco 8 inteiro: os blocos 1–7 ficam inteiros, nenhuma linha do bloco 8 fica, e o fim do corpo diz "(e mais N linhas)"',
        (select bool_and(position('• ' || (e ->> 'texto') in f2 ->> 'texto') > 0)
               from jsonb_array_elements(f #> '{dados,blocos}') x, jsonb_array_elements(x -> 'linhas') e where (x ->> 'bloco')::int <> 8)
        and (select bool_and(position('• ' || (e ->> 'texto') in f2 ->> 'texto') = 0) from jsonb_array_elements(l8) e)
        and f2 ->> 'texto' like format('%%(e mais %s linhas)%%', jsonb_array_length(l8)),
        format('teto %s → %s letras', v_n, char_length(f2 ->> 'texto')));
    else
      v_res := pg_temp.ok(v_res, 'R5j em teste, o teto que tira o bloco 8 inteiro', false, format('o teto daria %s (mínimo 400), ou o foco já vinha cortado', v_n));
    end if;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- cada item com o interruptor dele: só o viés em teste; a classe que repete a geral não sai, a que ainda mede não sai, a do dono que não é a geral não sai
  begin
    perform pg_temp.modos('desligado');
    update public.agenda_config set modo_vies = 'sombra', texto_max = 3000 where id;
    set local session_replication_role = replica; delete from public.agenda_aprendizado where item in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'); set local session_replication_role = origin;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, estado, texto, calculado_em) values
      ('vies', 'estimativa:todas', 'todas', 1, 1, 8, 1.11, 'sombra', 'linha do geral', c_agora),
      ('vies', 'estimativa:rv:energia', 'fina', 1, 1, 4, 1.11, 'sombra', 'a classe que repete o geral', c_agora),
      ('vies', 'estimativa:rv:geral', 'fina', 1, 1, 3, 0.99, 'sombra', 'a classe que não repete', c_agora),
      ('vies', 'estimativa:barco:energia', 'fina', 1, 1, 0, null, 'medindo', 'a classe que ainda mede', c_agora),
      ('vies', 'dono:todas', 'todas', 1, 1, 2, 1.02, 'sombra', 'a linha do dono', c_agora),
      ('vies', 'dono:rv:diagnostico', 'fina', 1, 1, 2, 1.04, 'sombra', 'a classe do dono', c_agora),
      ('tempo_compra', 'todas', 'geral', 1, 3, 1, null, 'medindo', 'o tempo de compra com o interruptor desligado', c_agora);
    f := public._agenda_ver_aprendizado(c_hoje);
    l8 := (select x -> 'linhas' from jsonb_array_elements(f #> '{dados,blocos}') x where (x ->> 'bloco')::int = 8);
    v_res := pg_temp.ok(v_res, 'R5i só o viés em teste: o bloco 8 só com ele — a geral, a classe que não repete, a do dono (nessa ordem); sem a que repete a geral, a que ainda mede, a classe do dono, nem o tempo de compra desligado',
      (select jsonb_agg(e ->> 'texto' order by o) from jsonb_array_elements(l8) with ordinality t(e, o)) = '["linha do geral", "a classe que não repete", "a linha do dono"]'::jsonb,
      l8::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r5$;

-- ── R6. O cartão da OS ──────────────────────────────────────────────────────────────────────────────
do $r6$
declare
  v_res jsonb := '[]'::jsonb;
  c     jsonb;
  c0    jsonb;
  v_os  uuid;
  v_d   date;
  k     int;
  c_hoje constant date := date '2027-01-07';
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'R6 o cartão', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  perform pg_temp.criar_antes('os_plano_da_os', 'mig_leituras_fase7d', 'plano_antes');
  begin
    -- uma OS aberta de energia em motorhome, pela estimativa (R$ 3.820: 5 diárias de R$ 764 → 2,5 dias com 2 pessoas)
    v_os := md5('e7e:p7:cartao')::uuid;
    perform set_config('agenda.porta', 'on', true);
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
    values (v_os, 'OS-7EP7', 'e7e00000-0000-4000-8000-000000000c02', 'e7e00000-0000-4000-8000-000000000b02', 'approved', 'approved', 'repair',
            timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-02 10:00-03', 3820);
    insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
    values (v_os, 'Instalação de inversor e baterias', 'visit', 1, 3820, 3820, timestamptz '2026-12-01 10:00-03');
    perform set_config('agenda.porta', 'off', true);
    -- desligado: o de antes, byte a byte
    perform pg_temp.modos('desligado');
    v_res := pg_temp.ok(v_res, 'R6a os 6 desligados: o cartão é o de antes do P7, byte a byte', public.os_plano_da_os(v_os, c_hoje)::text = pg_temp.plano_antes(v_os, c_hoje)::text, null);
    -- em teste, sem medido: nada a dizer, o de antes
    perform pg_temp.modos('sombra');
    v_res := pg_temp.ok(v_res, 'R6b em teste sem viés medido: sem estimativa nem promessa, o de antes, byte a byte', public.os_plano_da_os(v_os, c_hoje)::text = pg_temp.plano_antes(v_os, c_hoje)::text, null);
    -- em teste com o viés da classe medido (1,17, em sombra): "Em teste: … eu marcaria …"
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, estado, calculado_em)
    values ('vies', 'estimativa:rv:energia', 'fina', 1, 1, 4, 1.17, 'sombra', now()), ('vies', 'estimativa:todas', 'todas', 1, 1, 8, 1.11, 'sombra', now());
    c := public.os_plano_da_os(v_os, c_hoje);
    c0 := pg_temp.plano_antes(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'R6c em teste com o viés da classe (1,17): duracao.estimativa = "Em teste: com o que as OS de energia em motorhome costumam levar, eu marcaria … (hoje …)." e o resto igual',
      c #>> '{duracao,estimativa}' like 'Em teste: com o que as OS de energia em motorhome costumam levar, eu marcaria % (hoje %).'
      and (c -> 'duracao') - 'estimativa' = c0 -> 'duracao' and c - 'duracao' = c0 - 'duracao' and not (c -> 'duracao') ? 'promessa',
      c #>> '{duracao,estimativa}');
    -- o arredondamento que apaga: 1,02 não muda o número, e não há linha
    update public.agenda_aprendizado set calculado = 1.02 where item = 'vies';
    v_res := pg_temp.ok(v_res, 'R6d em teste com 1,02 (o número não muda): sem estimativa (lição 5), o cartão de antes', public.os_plano_da_os(v_os, c_hoje)::text = pg_temp.plano_antes(v_os, c_hoje)::text,
      public.os_plano_da_os(v_os, c_hoje) #>> '{duracao,estimativa}');
    -- o diagnóstico (R7.5-8): o viés não vale nele, e em teste não digo que marcaria outro número
    perform set_config('agenda.porta', 'on', true);
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
    values (md5('e7e:p7:diag')::uuid, 'OS-7EP7D', 'e7e00000-0000-4000-8000-000000000c02', 'e7e00000-0000-4000-8000-000000000b02', 'approved', 'approved', 'diagnosis',
            timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-02 10:00-03', 3820);
    insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
    values (md5('e7e:p7:diag')::uuid, 'Diagnóstico técnico no local', 'visit', 1, 3820, 3820, timestamptz '2026-12-01 10:00-03');
    perform set_config('agenda.porta', 'off', true);
    update public.agenda_aprendizado set calculado = 1.40 where item = 'vies';
    v_res := pg_temp.ok(v_res, 'R6d3 em teste, o diagnóstico (R7.5-8) com o viés medido 1,40: sem "Em teste" (o viés não vale nele): o cartão de antes',
      public.os_plano_da_os(md5('e7e:p7:diag')::uuid, c_hoje)::text = pg_temp.plano_antes(md5('e7e:p7:diag')::uuid, c_hoje)::text,
      public.os_plano_da_os(md5('e7e:p7:diag')::uuid, c_hoje) #>> '{duracao,estimativa}');
    -- ligado de verdade, sem o freio, com o viés medido que ainda não está em uso: não é teste, e o motor não o usa; nada a dizer
    perform pg_temp.modos('ligado', false);
    update public.agenda_aprendizado set calculado = 1.17 where item = 'vies';
    v_res := pg_temp.ok(v_res, 'R6d2 ligado, sem o freio, com o viés medido (1,17) que ainda não está em uso: sem "Em teste" (não é teste) nem estimativa: o cartão de antes',
      public.os_plano_da_os(v_os, c_hoje)::text = pg_temp.plano_antes(v_os, c_hoje)::text, public.os_plano_da_os(v_os, c_hoje) #>> '{duracao,estimativa}');
    -- em uso (ligado, sem o freio, o aprendizado ligado): os 2 números, como o motor marca
    perform pg_temp.modos('ligado', false);
    update public.agenda_aprendizado set calculado = 1.17, em_uso = 1.17, estado = 'em_uso', em_uso_desde = now() where item = 'vies' and chave = 'estimativa:rv:energia';
    c := public.os_plano_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'R6e em uso: "Estimativa minha: … pelo valor do orçamento × 1,17 (as OS de energia em motorhome costumam levar mais) = …." (§6.4)',
      c #>> '{duracao,estimativa}' like 'Estimativa minha: % pelo valor do orçamento × 1,17 (as OS de energia em motorhome costumam levar mais) = %.'
      and c #>> '{duracao,estimativa}' not like '%quando marquei%',
      c #>> '{duracao,estimativa}');
    -- o viés abaixo de 1 (0,80): "costumam levar um pouco menos"
    update public.agenda_aprendizado set calculado = 0.80, em_uso = 0.80 where item = 'vies' and chave = 'estimativa:rv:energia';
    c := public.os_plano_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'R6e2 em uso com 0,80: "Estimativa minha: … × 0,8 (as OS de energia em motorhome costumam levar um pouco menos) = …."',
      c #>> '{duracao,estimativa}' like 'Estimativa minha: % pelo valor do orçamento × 0,8 (as OS de energia em motorhome costumam levar um pouco menos) = %.',
      c #>> '{duracao,estimativa}');
    update public.agenda_aprendizado set calculado = 1.17, em_uso = 1.17 where item = 'vies' and chave = 'estimativa:rv:energia';
    -- marcado: o valor congelado na marcação vale, com o interruptor desligado também (R7.14)
    insert into public.os_planejamento (service_order_id, marcado_em, vies_marcado, vies_marcado_chave, atualizado_em)
    values (v_os, c_hoje - 3, 1.30, 'estimativa:rv:energia', timestamptz '2026-12-01 10:00-03')
    on conflict (service_order_id) do update set marcado_em = excluded.marcado_em, vies_marcado = excluded.vies_marcado, vies_marcado_chave = excluded.vies_marcado_chave;
    perform pg_temp.modos('desligado');
    c := public.os_plano_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'R6f marcado com 1,30 e o interruptor desligado: o motor ainda usa o congelado, e o cartão diz "… × 1,30 (…) = … (o que valia quando marquei)."',
      c #>> '{duracao,estimativa}' like 'Estimativa minha: % × 1,3 (as OS de energia em motorhome costumam levar mais) = % (o que valia quando marquei).',
      c #>> '{duracao,estimativa}');
    -- os dias do dono: o texto do P3, os 2 números (AG7-33)
    perform pg_temp.modos('ligado', false);
    set local session_replication_role = replica; delete from public.os_planejamento where service_order_id = v_os; set local session_replication_role = origin;
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, atualizado_em)
    values (v_os, 3, 'dono', timestamptz '2026-12-05 10:00-03', timestamptz '2026-12-05 10:00-03');
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em, em_uso_desde)
    values ('vies', 'dono:rv:energia', 'fina', 1, 1, 5, 1.2, 1.2, 'em_uso', now(), now());
    c := public.os_plano_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'R6g os dias do dono: "Você disse 3 dias; contei 3,5 (nos serviços assim, os seus dias levaram 1,2×; 5 OS)." (R7.3-2)',
      c #>> '{duracao,estimativa}' = 'Você disse 3 dias; contei 3,5 (nos serviços assim, os seus dias levaram 1,2×; 5 OS).', c #>> '{duracao,estimativa}');
    -- os dias do dono em teste, com a classe medida (1,17): o número é dele; sem "Em teste" com o viés das OS
    perform pg_temp.modos('sombra');
    set local session_replication_role = replica; delete from public.agenda_aprendizado where item = 'vies'; set local session_replication_role = origin;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, estado, calculado_em)
    values ('vies', 'estimativa:rv:energia', 'fina', 1, 1, 4, 1.17, 'sombra', now()), ('vies', 'estimativa:todas', 'todas', 1, 1, 8, 1.17, 'sombra', now());
    v_res := pg_temp.ok(v_res, 'R6g2 os dias do dono em teste (3 dias; a classe mediu 1,17): sem "Em teste" (o número é dele): o cartão de antes',
      public.os_plano_da_os(v_os, c_hoje)::text = pg_temp.plano_antes(v_os, c_hoje)::text, public.os_plano_da_os(v_os, c_hoje) #>> '{duracao,estimativa}');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- o prazo real: só para o dono, só com o fator medido e com dia a mais
  begin
    v_os := md5('e7e:p7:cartao2')::uuid;
    perform set_config('agenda.porta', 'on', true);
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
    values (v_os, 'OS-7EP7B', 'e7e00000-0000-4000-8000-000000000c02', 'e7e00000-0000-4000-8000-000000000b02', 'approved', 'approved', 'repair',
            timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-02 10:00-03', 3820);
    perform set_config('agenda.porta', 'off', true);
    -- o plano: 5 dias úteis a partir de seg 08/02, de manhã e à tarde
    v_d := date '2027-02-08';
    for k in 1 .. 5 loop
      while not public.agenda_dia_util(v_d) loop v_d := v_d + 1; end loop;
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
      values (v_os, 'e7e00000-0000-4000-8000-00000000aa02', v_d, 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-01-07 10:00-03'),
             (v_os, 'e7e00000-0000-4000-8000-00000000aa02', v_d, 'tarde', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-01-07 10:00-03');
      v_d := v_d + 1;
    end loop;
    perform pg_temp.modos('sombra');
    c0 := pg_temp.plano_antes(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'R6h o prazo real sem OS medida (o fator é o padrão: "pela folga do histórico" seria falso): sem promessa, o cartão de antes',
      public.os_plano_da_os(v_os, c_hoje)::text = c0::text, null);
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, estado, calculado_em)
    values ('promessa', 'todas', 'todas', 1.5, 1, 8, 1.40, 'sombra', now());
    c := public.os_plano_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'R6i com o prazo real medido (1,40; 8 OS): 5 dias úteis → 7; "Pela folga do histórico, pronto até ter 16/02 (só para você: ao cliente não digo data de pronto)." (R7.3-1); o resto igual',
      c #>> '{duracao,promessa}' = 'Pela folga do histórico, pronto até ' || public._dia_curto(public.agenda_somar_du(date '2027-02-08', 6)) || ' (só para você: ao cliente não digo data de pronto).'
      and (c -> 'duracao') - 'promessa' = c0 -> 'duracao' and c - 'duracao' = c0 - 'duracao', c #>> '{duracao,promessa}');
    update public.agenda_config set modo_promessa = 'desligado' where id;
    v_res := pg_temp.ok(v_res, 'R6j com modo_promessa desligado: sem promessa', not (public.os_plano_da_os(v_os, c_hoje) -> 'duracao') ? 'promessa', null);
    update public.agenda_config set modo_promessa = 'sombra' where id;
    -- a OS concluída: nada (o controle: a mesma OS aberta, com o prazo real medido, tem a promessa); num bloco desfeito
    begin
      c := public.os_plano_da_os(v_os, c_hoje);
      update public.service_orders set status = 'completed' where id = v_os;
      v_res := pg_temp.ok(v_res, 'R6l a OS concluída: sem as 2 linhas (o controle: aberta, a promessa estava lá)',
        (c -> 'duracao') ? 'promessa' and not (public.os_plano_da_os(v_os, c_hoje) -> 'duracao') ?| array['promessa', 'estimativa'], c #>> '{duracao,promessa}');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- a folga que não acrescenta dia: 1 dia útil × 1,40 = 1
    set local session_replication_role = replica; delete from public.agenda_alocacoes where service_order_id = v_os and dia > date '2027-02-08'; set local session_replication_role = origin;
    v_res := pg_temp.ok(v_res, 'R6k plano de 1 dia útil × 1,40 = 1 (a folga não acrescenta dia): sem promessa (lição 5)', not (public.os_plano_da_os(v_os, c_hoje) -> 'duracao') ? 'promessa', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r6$;

-- ── R8. A correção da conferência do P7 ─────────────────────────────────────────────────────────────
-- Os defeitos que a conferência reproduziu no replay real (f7e/p7conf; antes e depois em f7e/p7c/rep.mjs), aqui na fixture, cada um contra uma âncora de fora: (a) o cartão em teste na OS
-- marcada; (b) o cartão em teste no regime em que o viés vale (sem o freio: com o gestor ligado, as regras dele), contra agenda_meios_da_os ligado de verdade; (c) carga_semana_fora; (d) o
-- *desfaz* do viés: a classe que entrou em uso com o geral e o "voltam a", contra o leitor do motor; (e) o bloco 8 com o freio, contra o leitor; (f) a ordem do "o que mudou" no empate.
do $r8$
declare
  v_res jsonb := '[]'::jsonb;
  c     jsonb;
  c0    jsonb;
  d     jsonb;
  s     jsonb;
  f     jsonb;
  l8    jsonb;
  x1    jsonb;
  x2    jsonb;
  v_os  uuid := md5('e7e:p7c:cartao')::uuid;
  v_anc numeric;
  v_sem numeric;
  v_hj  numeric;
  v_hs  numeric;
  v_esp text;
  v_t   text;
  v_g   uuid;
  v_k   uuid;
  v_dif text;
  v     record;
  c_hoje constant date := date '2027-01-07';
  c_agora constant timestamptz := timestamptz '2027-01-07 16:05-03';
  c_t   constant timestamptz := timestamptz '2027-01-07 16:05-03';
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'R8 a correção da conferência do P7', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  perform pg_temp.criar_antes('os_plano_da_os', 'mig_leituras_fase7d', 'plano_antes8');
  begin
    -- a OS do cartão, como a do R6: energia em motorhome, aberta, R$ 3.820 pela estimativa
    perform set_config('agenda.porta', 'on', true);
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
    values (v_os, 'OS-7EP7C', 'e7e00000-0000-4000-8000-000000000c02', 'e7e00000-0000-4000-8000-000000000b02', 'approved', 'approved', 'repair',
            timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-02 10:00-03', 3820);
    insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
    values (v_os, 'Instalação de inversor e baterias', 'visit', 1, 3820, 3820, timestamptz '2026-12-01 10:00-03');
    perform set_config('agenda.porta', 'off', true);

    -- (a) a OS marcada com o viés congelado (1,00, sem chave): o motor fica com ele ligado de verdade; o cartão em teste não diz "eu marcaria"
    perform pg_temp.modos('sombra');
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, estado, calculado_em)
    values ('vies', 'estimativa:rv:energia', 'fina', 1, 1, 4, 1.40, 'sombra', c_agora), ('vies', 'estimativa:todas', 'todas', 1, 1, 8, 1.40, 'sombra', c_agora);
    c0 := public.os_plano_da_os(v_os, c_hoje);
    insert into public.os_planejamento (service_order_id, marcado_em, vies_marcado, atualizado_em) values (v_os, c_hoje - 3, 1.00, timestamptz '2026-12-01 10:00-03');
    c := public.os_plano_da_os(v_os, c_hoje);
    begin
      perform pg_temp.modos('ligado', false);
      v_sem := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      update public.agenda_aprendizado set estado = 'em_uso', em_uso = calculado, em_uso_desde = c_agora where item = 'vies';
      v_anc := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      -- o controle que morde: a mesma OS sem a marcação, ligada de verdade, muda de dias com o viés
      set local session_replication_role = replica; delete from public.os_planejamento where service_order_id = v_os; set local session_replication_role = origin;
      v_hs := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_res := pg_temp.ok(v_res, 'R8a a OS marcada com o viés congelado 1,00: sem "Em teste: … eu marcaria" (o cartão de antes, byte a byte); ligado de verdade, o motor fica nos mesmos dias com e sem o viés em uso (a âncora). Os controles: sem a marcação, o cartão em teste diz "eu marcaria" e o motor ligado muda',
      not (c -> 'duracao') ? 'estimativa' and c::text = pg_temp.plano_antes8(v_os, c_hoje)::text and v_anc = v_sem
      and c0 #>> '{duracao,estimativa}' like 'Em teste: %eu marcaria %' and v_hs <> v_sem,
      format('%s | ligado: sem o viés %s, com %s; sem a marcação, com o viés %s | sem a marcação, o cartão: %s', c #>> '{duracao,estimativa}', v_sem, v_anc, v_hs, c0 #>> '{duracao,estimativa}'));
    -- o congelado de outra conta (o dos dias do dono, dono:) não vale para a estimativa (agenda_meios_da_os usa o de agora): o cartão em teste diz "eu marcaria", e ligado o motor muda
    update public.os_planejamento set vies_marcado = 1.20, vies_marcado_chave = 'dono:rv:energia' where service_order_id = v_os;
    c := public.os_plano_da_os(v_os, c_hoje);
    begin
      perform pg_temp.modos('ligado', false);
      v_sem := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      update public.agenda_aprendizado set estado = 'em_uso', em_uso = calculado, em_uso_desde = c_agora where item = 'vies';
      v_anc := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_res := pg_temp.ok(v_res, 'R8a2 a OS marcada com o congelado dos dias do dono (dono:rv:energia 1,20) e os dias pela estimativa: o congelado não vale para ela, o cartão em teste diz "eu marcaria" o que o motor ligado marca',
      c #>> '{duracao,estimativa}' like 'Em teste: %eu marcaria ' || public._agenda_dias(v_anc) || ' (%' and v_anc <> v_sem,
      format('%s | ligado: sem o viés %s, com %s', c #>> '{duracao,estimativa}', v_sem, v_anc));
    set local session_replication_role = replica; delete from public.os_planejamento where service_order_id = v_os; set local session_replication_role = origin;

    -- (b) o gestor ligado com o freio (como em produção): sem o freio, as regras dele mudam a sugestão (uma pessoa: os dias dobram). O "eu marcaria" é o que o motor ligado de verdade marca
    update public.agenda_aprendizado set calculado = 1.17 where item = 'vies';
    perform pg_temp.modos('sombra');
    update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    c := public.os_plano_da_os(v_os, c_hoje);
    v_hj := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
    begin
      update public.agenda_config set gestor_so_propor = false where id;
      v_hs := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      perform pg_temp.modos('ligado', false);
      update public.agenda_aprendizado set estado = 'em_uso', em_uso = calculado, em_uso_desde = c_agora where item = 'vies';
      v_anc := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_esp := format('Em teste: com o que as OS de energia em motorhome costumam levar, eu marcaria %s (%s).', public._agenda_dias(v_anc),
                    case when v_hs = v_hj then 'hoje ' || public._agenda_num(v_hj, 1) else 'sem isso, ' || public._agenda_num(v_hs, 1) || '; hoje ' || public._agenda_num(v_hj, 1) end);
    v_res := pg_temp.ok(v_res, 'R8b o gestor ligado e o freio: o "eu marcaria" é o que o motor ligado de verdade marca (agenda_meios_da_os sem o freio, com o viés em uso), e o texto diz também o de sem o viés naquele regime e o de hoje, que as regras do gestor fazem diferentes',
      c #>> '{duracao,estimativa}' = v_esp and v_hs <> v_hj and v_anc <> v_hs and (c -> 'duracao') - 'estimativa' = pg_temp.plano_antes8(v_os, c_hoje) -> 'duracao',
      format('%s | esperado: %s', c #>> '{duracao,estimativa}', v_esp));
    -- o viés que não muda o número no regime dele (1,02: 5 dias × 1,02 = 5), com o de hoje diferente (as regras do gestor): sem linha (lição 5); o motor ligado de verdade fica igual
    update public.agenda_aprendizado set calculado = 1.02 where item = 'vies';
    c := public.os_plano_da_os(v_os, c_hoje);
    begin
      update public.agenda_config set gestor_so_propor = false where id;
      v_hs := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      perform pg_temp.modos('ligado', false);
      update public.agenda_aprendizado set estado = 'em_uso', em_uso = calculado, em_uso_desde = c_agora where item = 'vies';
      v_anc := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_res := pg_temp.ok(v_res, 'R8b3 o gestor ligado e o freio, o viés 1,02 (não muda o número sem o freio: o motor ligado de verdade marca o mesmo), e o de hoje diferente: sem "Em teste" (o cartão de antes, byte a byte)',
      c::text = pg_temp.plano_antes8(v_os, c_hoje)::text and v_anc = v_hs and v_hs <> v_hj,
      format('%s | ligado: sem o viés %s, com %s; hoje %s', c #>> '{duracao,estimativa}', v_hs, v_anc, v_hj));
    update public.agenda_aprendizado set calculado = 1.17 where item = 'vies';
    -- sem o gestor ligado, sem o freio as regras dele também ficam de fora: a conta é a de hoje, e o texto, o de sempre
    update public.agenda_config set modo_marcar_sozinho = 'sombra' where id;
    c := public.os_plano_da_os(v_os, c_hoje);
    v_hj := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
    begin
      update public.agenda_config set gestor_so_propor = false where id;
      v_hs := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      perform pg_temp.modos('ligado', false);
      update public.agenda_aprendizado set estado = 'em_uso', em_uso = calculado, em_uso_desde = c_agora where item = 'vies';
      v_anc := (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric;
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_esp := format('Em teste: com o que as OS de energia em motorhome costumam levar, eu marcaria %s (hoje %s).', public._agenda_dias(v_anc), public._agenda_num(v_hj, 1));
    v_res := pg_temp.ok(v_res, 'R8b2 o gestor em teste (modo_marcar_sozinho sombra): sem o freio as regras dele não entram, a conta é a de hoje, "eu marcaria … (hoje …)" bate com o motor ligado de verdade',
      c #>> '{duracao,estimativa}' = v_esp and v_hs = v_hj and v_anc <> v_hj, format('%s | esperado: %s', c #>> '{duracao,estimativa}', v_esp));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (c) carga_semana_fora: fora de ligado de verdade, 0 para qualquer carga_max do CHECK (0,50 a 1,00)
  begin
    v_dif := null;
    for v in select * from (values ('desligado', true, 1.00), ('desligado', true, 0.50), ('sombra', true, 1.00), ('sombra', true, 0.50), ('sombra', false, 1.00),
                                   ('ligado', true, 1.00), ('ligado', true, 0.50)) t(modo, freio, carga) loop
      perform pg_temp.modos(v.modo, v.freio);
      update public.agenda_config set carga_max = v.carga where id;
      s := public.agenda_saude(c_hoje, c_agora);
      if (s #>> '{margem,carga_semana_fora}')::int <> 0 or not (s #>> '{margem,zeros_ok}')::boolean then
        v_dif := coalesce(v_dif || '; ', '') || format('%s, freio %s, carga_max %s: %s', v.modo, v.freio, v.carga, s #>> '{margem,carga_semana_fora}');
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'R8c fora de ligado de verdade (desligado, em teste, ligado com o freio), carga_semana_fora = 0 com carga_max 0,50 e 1,00: a carga é a que o dono escolheu', v_dif is null, v_dif);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- ligado de verdade: a conta antes de prender (a folga em uso e a temporada entram nela)
  for v in select * from (values
      ('R8c2 ligado sem o freio, a folga em uso 0,30 e a temporada de janeiro e fevereiro (10%): a conta 0,80 + 0,15 − 0,30 − 0,10 = 0,55 fica abaixo do mínimo 0,60 nas 6 semanas e acende; a carga sai presa em 0,60', 0.80, true, true, 6, 0.60),
      ('R8c3 o controle da folga: sem a folga em uso (o padrão), a conta 0,70 fica dentro: 0', 0.80, false, true, 0, 0.70),
      ('R8c4 o controle da temporada: com a folga 0,30 e sem temporada, a conta 0,65 fica dentro: 0', 0.80, true, false, 0, 0.65),
      ('R8c5 carga_max 1,00 sem folga nem temporada: a conta passa do máximo 0,95 e acende; a carga sai presa em 0,95', 1.00, false, false, 6, 0.95)) t(nome, carga, folga, temporada, n, presa) loop
    begin
      perform pg_temp.modos('ligado', false);
      update public.agenda_config set carga_max = v.carga where id;
      if not v.temporada then
        update public.agenda_config set folga_temporada_barco = array_fill(0::numeric, array[12]), folga_temporada_rv = array_fill(0::numeric, array[12]) where id;
      end if;
      if v.folga then
        insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, em_uso_desde, estado, calculado_em)
        values ('folga_semana', 'equipe', 'geral', 0.15, 8, 8, 0.30, 0.30, c_agora, 'em_uso', c_agora)
        on conflict (item, chave) do update set estado = 'em_uso', calculado = 0.30, em_uso = 0.30, em_uso_desde = c_agora, n = 8, travado_ate = null;
      end if;
      s := public.agenda_saude(c_hoje, c_agora);
      v_res := pg_temp.ok(v_res, v.nome,
        (s #>> '{margem,carga_semana_fora}')::int = v.n and (s #>> '{margem,zeros_ok}')::boolean = (v.n = 0)
        and (public._agenda_carga_da_semana(c_hoje - (extract(isodow from c_hoje)::int - 1)) ->> 'carga')::numeric = v.presa,
        format('carga_semana_fora %s; a carga da semana %s', s #>> '{margem,carga_semana_fora}', public._agenda_carga_da_semana(c_hoje - (extract(isodow from c_hoje)::int - 1)) ->> 'carga'));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;

  -- (d) o *desfaz* do viés: a rodada do gravador no mesmo instante põe o geral em uso (1,00 → 1,25, com ação), rv:energia (1,29, com ação) e rv:geral, cujo medido é o próprio geral
  -- (1,25: entra em uso sem ação). barco:energia estava travada com 1,25 e a trava venceu: volta a uso no mesmo instante, também sem ação, mas o valor é o de antes (não veio do geral)
  for v in select * from (values ('dias', 'aprendizado dias', false), ('tudo', 'aprendizado', false), ('freio', 'aprendizado dias', true), ('tela', null, false), ('classe', null, false)) t(caso, alvo, freio) loop
    begin
      perform pg_temp.modos('ligado', v.freio);
      set local session_replication_role = replica; delete from public.agenda_aprendizado where item = 'vies'; delete from public.agenda_acoes where antes ->> 'item' = 'vies'; set local session_replication_role = origin;
      insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, em_uso_desde, estado, travado_ate, travado_valor, calculado_em)
      values ('vies', 'estimativa:barco:energia', 'fina', 1.25, 1, 2, 1.25, 1.25, c_t - interval '30 days', 'travado', c_hoje - 1, 1.25, c_t - interval '30 days');
      perform public._agenda_aprendizado_gravar('vies', 'estimativa:todas', 'todas', 1.25, 8, '[]'::jsonb, 1, '{}'::jsonb, c_t);
      perform public._agenda_aprendizado_gravar('vies', 'estimativa:rv:energia', 'fina', 1.29, 2, '[]'::jsonb, 1.25, '{}'::jsonb, c_t);
      perform public._agenda_aprendizado_gravar('vies', 'estimativa:rv:geral', 'fina', 1.25, 3, '[]'::jsonb, 1.25, '{}'::jsonb, c_t);
      perform public._agenda_aprendizado_gravar('vies', 'estimativa:barco:energia', 'fina', 1.25, 2, '[]'::jsonb, 1.25, '{}'::jsonb, c_t);
      -- e 2 que não são do geral: barco:geral chega a 1,25 pela ação dela (vinha de 1,00), e o do dono (outro grupo) entra em uso com 1,25 sem ação
      perform public._agenda_aprendizado_gravar('vies', 'estimativa:barco:geral', 'fina', 1.25, 2, '[]'::jsonb, 1, '{}'::jsonb, c_t);
      perform public._agenda_aprendizado_gravar('vies', 'dono:rv:energia', 'fina', 1.25, 2, '[]'::jsonb, 1.25, '{}'::jsonb, c_t);
      v_g := (select id from public.agenda_acoes where tipo = 'aprendizado' and antes ->> 'chave' = 'estimativa:todas');
      v_k := (select id from public.agenda_acoes where tipo = 'aprendizado' and antes ->> 'chave' = 'estimativa:rv:energia');
      if v.caso = 'dias' then
        -- o pré-requisito: a fixture tem a classe em uso sem ação (rv:geral), a que volta da trava sem ação (barco:energia), a do dono sem ação e 3 ações
        v_res := pg_temp.ok(v_res, 'R8d0 a montagem: o geral 1,25, rv:energia 1,29 e barco:geral 1,25 em uso com ação; rv:geral, barco:energia e o dono rv:energia em uso com 1,25 sem ação, no mesmo instante',
          (select count(*) from public.agenda_acoes where tipo = 'aprendizado' and antes ->> 'item' = 'vies') = 3
          and (select bool_and(estado = 'em_uso' and em_uso = 1.25 and em_uso_desde = c_t)
                 from public.agenda_aprendizado where chave in ('estimativa:rv:geral', 'estimativa:barco:energia', 'estimativa:todas', 'estimativa:barco:geral', 'dono:rv:energia'))
          and (select count(*) from public.agenda_aprendizado where item = 'vies' and acao_id is null and estado = 'em_uso') = 3
          and v_g is not null and v_k is not null,
          (select string_agg(chave || ' ' || estado || ' ' || coalesce(em_uso::text, '-'), ' | ' order by chave) from public.agenda_aprendizado where item = 'vies'));
      end if;
      if v.caso in ('dias', 'tudo', 'freio') then
        d := public.agenda_desfazer_dito(pg_temp.adm(), v.alvo, 'whatsapp', c_hoje, c_t + interval '10 minutes');
        v_t := d ->> 'texto';
        v_res := pg_temp.ok(v_res, format('R8d %s (%s): o geral, rv:energia e rv:geral (a classe que entrou com o geral) sem nada em uso e travados; o leitor do motor sem viés nas 3; barco:energia (o valor dela, de antes) continua; o texto diz 1,00× nas 2, o geral antes da classe, e nunca 1,25×',
                                         '*desfaz ' || v.alvo || '*', case when v.freio then 'com o freio' else 'sem o freio' end),
          (d ->> 'ok')::boolean
          and (select bool_and(estado = 'travado' and em_uso is null) from public.agenda_aprendizado where chave in ('estimativa:todas', 'estimativa:rv:energia', 'estimativa:rv:geral'))
          and (select estado = 'em_uso' and em_uso = 1.25 from public.agenda_aprendizado where chave = 'estimativa:barco:energia')
          and public._agenda_margem_em_uso('vies', 'estimativa:todas') is null and public._agenda_margem_em_uso('vies', 'estimativa:rv:energia') is null
          and public._agenda_margem_em_uso('vies', 'estimativa:rv:geral') is null
          and v_t like 'Desfeito: as OS voltam a 1,00× o que sai do orçamento,% Desfeito: as OS de energia em motorhome voltam a 1,00× o que sai do orçamento,%'
          and v_t not like '%1,25×%'
          and (select texto from public.agenda_acoes where tipo = 'desfazer' and desfaz_a = v_k) like 'Desfeito: as OS de energia em motorhome voltam a 1,00×%'
          and (select texto from public.agenda_aprendizado where chave = 'estimativa:rv:energia') like '%fico com 1,00× até %'
          and (select texto like '%fico com 1,00× até %' and travado_ate = c_hoje + 28 and historico -> -1 ->> 'desfeita' = v_g::text
                 from public.agenda_aprendizado where chave = 'estimativa:rv:geral')
          and (select estado = 'em_uso' and em_uso = 1.25 from public.agenda_aprendizado where chave = 'dono:rv:energia')
          -- e o foco: a linha do geral travada sem valor em uso diz o que vale (o padrão, que o leitor usa), com ou sem o freio
          and (select e ->> 'texto' from jsonb_array_elements((select x -> 'linhas' from jsonb_array_elements(public._agenda_ver_aprendizado(c_hoje) #> '{dados,blocos}') x
                                                                where (x ->> 'bloco')::int = 8)) e
                where e ->> 'chave' = 'estimativa:todas') like '%fico com 1,00× até %',
          format('%s | %s', v_t, (select string_agg(chave || ' ' || estado || ' ' || coalesce(em_uso::text, '-'), ' | ' order by chave) from public.agenda_aprendizado where item = 'vies')));
      elsif v.caso = 'tela' then
        -- só o geral (a linha dele no "o que mudou"): a classe que entrou com ele volta junto; rv:energia, com o valor dela (a ação dela), continua
        d := public.agenda_desfazer(v_g, pg_temp.adm(), 'tela', c_hoje, c_t + interval '10 minutes');
        v_res := pg_temp.ok(v_res, 'R8d2 o *desfaz* só do geral (a tela): rv:geral volta junto (travada, sem nada em uso); rv:energia, com a ação dela, barco:energia (de antes), barco:geral (1,25 pela ação dela) e o do dono continuam; "as OS voltam a 1,00×"',
          (d ->> 'ok')::boolean and d ->> 'texto' like 'Desfeito: as OS voltam a 1,00×%'
          and (select estado = 'travado' and em_uso is null from public.agenda_aprendizado where chave = 'estimativa:rv:geral')
          and (select estado = 'em_uso' and em_uso = 1.29 from public.agenda_aprendizado where chave = 'estimativa:rv:energia')
          and (select bool_and(estado = 'em_uso' and em_uso = 1.25) from public.agenda_aprendizado where chave in ('estimativa:barco:energia', 'estimativa:barco:geral', 'dono:rv:energia')),
          format('%s | %s', d ->> 'texto', (select string_agg(chave || ' ' || estado || ' ' || coalesce(em_uso::text, '-'), ' | ' order by chave) from public.agenda_aprendizado where item = 'vies')));
      else
        -- só a classe, com o geral em uso: ela passa a usar o geral, 1,25, e o texto diz isso; rv:geral não muda
        d := public.agenda_desfazer(v_k, pg_temp.adm(), 'tela', c_hoje, c_t + interval '10 minutes');
        v_res := pg_temp.ok(v_res, 'R8d3 o *desfaz* só de rv:energia, com o geral em uso: "voltam a 1,25×" (o geral, que o leitor passa a usar nela); rv:geral continua em uso',
          (d ->> 'ok')::boolean and d ->> 'texto' like 'Desfeito: as OS de energia em motorhome voltam a 1,25×%'
          and public._agenda_margem_em_uso('vies', 'estimativa:rv:energia') is null and public._agenda_margem_em_uso('vies', 'estimativa:todas') = 1.25
          and (select estado = 'em_uso' and em_uso = 1.25 from public.agenda_aprendizado where chave = 'estimativa:rv:geral'),
          d ->> 'texto');
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- o 2º passo da classe (1,10 ontem, 1,29 hoje) desfeito: a linha volta a 1,10; sem o freio o leitor usa 1,10 e o texto diz 1,10; com o freio o leitor não usa nada e o texto diz 1,00
  for v in select * from (values (false, '1,10×'), (true, '1,00×')) t(freio, volta) loop
    begin
      perform pg_temp.modos('ligado', v.freio);
      set local session_replication_role = replica; delete from public.agenda_aprendizado where item = 'vies'; delete from public.agenda_acoes where antes ->> 'item' = 'vies'; set local session_replication_role = origin;
      perform public._agenda_aprendizado_gravar('vies', 'estimativa:rv:energia', 'fina', 1.10, 2, '[]'::jsonb, 1, '{}'::jsonb, c_t - interval '1 day');
      perform public._agenda_aprendizado_gravar('vies', 'estimativa:rv:energia', 'fina', 1.29, 2, '[]'::jsonb, 1, '{}'::jsonb, c_t);
      v_k := (select id from public.agenda_acoes where tipo = 'aprendizado' and antes ->> 'chave' = 'estimativa:rv:energia' and criada_em = c_t);
      d := public.agenda_desfazer(v_k, pg_temp.adm(), 'tela', c_hoje, c_t + interval '10 minutes');
      v_res := pg_temp.ok(v_res, format('R8d4 o 2º passo da classe desfeito %s: a linha volta a 1,10 (travada); o leitor do motor dá %s, e o texto diz "voltam a %s"',
                                       case when v.freio then 'com o freio' else 'sem o freio' end, case when v.freio then 'nada (1,00)' else '1,10' end, v.volta),
        (d ->> 'ok')::boolean and d ->> 'texto' like 'Desfeito: as OS de energia em motorhome voltam a ' || v.volta || '%'
        and (select estado = 'travado' and em_uso = 1.10 from public.agenda_aprendizado where chave = 'estimativa:rv:energia')
        and public._agenda_margem_em_uso('vies', 'estimativa:rv:energia') is not distinct from case when v.freio then null else 1.10 end,
        d ->> 'texto');
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;

  -- (e) o bloco 8 com o freio: o gravador anda pelo modo cru (em uso), o leitor do motor não usa; a linha diz "Em teste", como o cartão e a temporada
  begin
    perform pg_temp.modos('ligado', true);
    update public.agenda_config set texto_max = 3000 where id;
    set local session_replication_role = replica; delete from public.agenda_aprendizado where item in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'); set local session_replication_role = origin;
    perform public._agenda_aprendizado_gravar('vies', 'estimativa:todas', 'todas', 1.25, 8, '[]'::jsonb, 1, '{}'::jsonb, c_t);
    perform public._agenda_aprendizado_gravar('folga_semana', 'equipe', 'geral', 0.20, 8, '[]'::jsonb, 0.15, '{"residuos": 8, "residuos_min": 7}'::jsonb, c_t);
    perform public._agenda_aprendizado_gravar('tempo_compra', 'todas', 'geral', 2, 5, '[]'::jsonb, 1, '{"percentil": 2}'::jsonb, c_t);
    -- e 2 classes do viés: rv:energia em uso pelo gravador (n 2) e barco:geral só medida, em teste (n 5); a ordem do bloco 8 vai pelo estado que vale
    perform public._agenda_aprendizado_gravar('vies', 'estimativa:rv:energia', 'fina', 1.29, 2, '[]'::jsonb, 1.25, '{}'::jsonb, c_t);
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, estado, texto, calculado_em)
    values ('vies', 'estimativa:barco:geral', 'fina', 1.25, 1, 5, 0.90, 'sombra', 'Em teste: a classe só medida.', c_t);
    f := public._agenda_ver_aprendizado(c_hoje);
    l8 := (select x -> 'linhas' from jsonb_array_elements(f #> '{dados,blocos}') x where (x ->> 'bloco')::int = 8);
    v_res := pg_temp.ok(v_res, 'R8e com o freio, o viés (o geral e rv:energia), a folga da semana e o tempo de compra em uso pelo gravador (o modo cru) e nulos no leitor: as 4 linhas dizem "Em teste: …" (estado sombra, sem em uso), nenhuma diz que marca, guarda ou conta; a do geral, byte a byte; as classes pelo n (barco:geral, 5, antes de rv:energia, 2), as duas em teste',
      (select count(*) from public.agenda_aprendizado where item in ('vies', 'folga_semana', 'tempo_compra') and estado = 'em_uso' and em_uso is not null) = 4
      and public._agenda_margem_em_uso('vies', 'estimativa:todas') is null and public._agenda_margem_em_uso('folga_semana', 'equipe') is null
      and public._agenda_margem_em_uso('tempo_compra', 'todas') is null and public._agenda_margem_em_uso('vies', 'estimativa:rv:energia') is null
      and (select count(*) filter (where e ->> 'texto' like 'Em teste: %' and e ->> 'estado' = 'sombra' and e -> 'em_uso' = 'null'::jsonb) = 4 and count(*) = 4
             from jsonb_array_elements(l8) e join public.agenda_aprendizado a on a.item = e ->> 'item' and a.chave = e ->> 'chave' and a.em_uso is not null)
      and (select e ->> 'texto' from jsonb_array_elements(l8) e where e ->> 'chave' = 'estimativa:todas')
          = 'Em teste: as OS levam 1,25× o que eu estimo pelo orçamento (8 OS medidas). Hoje marco os dias como saem do orçamento.'
      and (select o from jsonb_array_elements(l8) with ordinality t(e, o) where e ->> 'chave' = 'estimativa:barco:geral')
          < (select o from jsonb_array_elements(l8) with ordinality t(e, o) where e ->> 'chave' = 'estimativa:rv:energia')
      and f ->> 'texto' not like '%desde qui 07/01%',
      (select string_agg(format('[%s/%s/%s] %s', e ->> 'chave', e ->> 'estado', e ->> 'em_uso', e ->> 'texto'), ' | ') from jsonb_array_elements(l8) e));
    -- sem o freio, o leitor usa: as linhas de antes (o texto do gravador, em uso), e a em uso antes da em teste
    update public.agenda_config set gestor_so_propor = false where id;
    f := public._agenda_ver_aprendizado(c_hoje);
    l8 := (select x -> 'linhas' from jsonb_array_elements(f #> '{dados,blocos}') x where (x ->> 'bloco')::int = 8);
    v_res := pg_temp.ok(v_res, 'R8e2 sem o freio, as mesmas 4 linhas são as do gravador, em uso, como antes ("marco os dias delas com 1,25× desde qui 07/01"); rv:energia (em uso) antes de barco:geral (em teste)',
      (select count(*) filter (where e ->> 'texto' = a.texto and e ->> 'estado' = 'em_uso' and (e ->> 'em_uso')::numeric = a.em_uso) = 4 and count(*) = 4
         from jsonb_array_elements(l8) e join public.agenda_aprendizado a on a.item = e ->> 'item' and a.chave = e ->> 'chave' and a.em_uso is not null)
      and (select o from jsonb_array_elements(l8) with ordinality t(e, o) where e ->> 'chave' = 'estimativa:rv:energia')
          < (select o from jsonb_array_elements(l8) with ordinality t(e, o) where e ->> 'chave' = 'estimativa:barco:geral')
      and f ->> 'texto' like '%marco os dias delas com 1,25× desde qui 07/01.%',
      (select string_agg(format('[%s/%s] %s', e ->> 'chave', e ->> 'estado', e ->> 'texto'), ' | ') from jsonb_array_elements(l8) e));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (f) o "o que mudou" com 3 linhas do viés e 1 do tempo de compra no mesmo instante: trocar os ids não muda a lista
  begin
    perform pg_temp.modos('ligado', false);
    for v in select * from (values (1), (2)) t(k) loop
      set local session_replication_role = replica; delete from public.agenda_acoes where tipo = 'aprendizado'; set local session_replication_role = origin;
      insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, texto, antes, depois, desfazivel_ate)
      values (case v.k when 1 then '00000000-0000-4000-8000-0000000000e1'::uuid else 'ffffffff-0000-4000-8000-0000000000e1'::uuid end, c_t, c_hoje, true, 'vigia', 'aprendizado',
              'Aprendi: as OS vão a 1,2. *desfaz aprendizado* volta.',
              '{"item": "vies", "chave": "estimativa:todas", "nivel": "todas", "em_uso": null, "valor": 1, "estado": "sombra"}', '{"item": "vies", "chave": "estimativa:todas", "nivel": "todas", "em_uso": 1.2, "n": 5}', c_t + interval '7 days'),
             (case v.k when 1 then '00000000-0000-4000-8000-0000000000e2'::uuid else 'eeeeeeee-0000-4000-8000-0000000000e2'::uuid end, c_t, c_hoje, true, 'vigia', 'aprendizado',
              'Aprendi: energia em motorhome vai a 1,3. *desfaz aprendizado* volta.',
              '{"item": "vies", "chave": "estimativa:rv:energia", "nivel": "fina", "em_uso": null, "valor": 1, "estado": "sombra"}', '{"item": "vies", "chave": "estimativa:rv:energia", "nivel": "fina", "em_uso": 1.3, "n": 5}', c_t + interval '7 days'),
             (case v.k when 1 then '00000000-0000-4000-8000-0000000000e3'::uuid else 'dddddddd-0000-4000-8000-0000000000e3'::uuid end, c_t, c_hoje, true, 'vigia', 'aprendizado',
              'Aprendi: barco vai a 0,9. *desfaz aprendizado* volta.',
              '{"item": "vies", "chave": "estimativa:barco:geral", "nivel": "fina", "em_uso": null, "valor": 1, "estado": "sombra"}', '{"item": "vies", "chave": "estimativa:barco:geral", "nivel": "fina", "em_uso": 0.9, "n": 5}', c_t + interval '7 days'),
             (case v.k when 1 then '00000000-0000-4000-8000-0000000000e4'::uuid else 'aaaaaaaa-0000-4000-8000-0000000000e4'::uuid end, c_t, c_hoje, true, 'vigia', 'aprendizado',
              'Aprendi: o tempo de compra vai a 2. *desfaz aprendizado* volta.',
              '{"item": "tempo_compra", "chave": "todas", "nivel": "geral", "em_uso": null, "valor": 1, "estado": "sombra"}', '{"item": "tempo_compra", "chave": "todas", "nivel": "geral", "em_uso": 2, "n": 5}', c_t + interval '7 days');
      d := public._agenda_mudancas(c_hoje, c_hoje, true, false, c_t + interval '1 hour');
      if v.k = 1 then x1 := d; else x2 := d; end if;
    end loop;
    v_t := (select string_agg(x, ' | ' order by o, k) from jsonb_array_elements(x1) with ordinality e(g, o), jsonb_array_elements_text(g -> 'itens') with ordinality i(x, k));
    v_res := pg_temp.ok(v_res, 'R8f 3 linhas do viés e 1 do tempo de compra no mesmo instante, com os ids trocados: a mesma lista (os textos, na mesma ordem); o viés na ordem do foco: o geral, depois as classes pela chave',
      (select jsonb_agg(g -> 'itens' order by o) from jsonb_array_elements(x1) with ordinality e(g, o)) = (select jsonb_agg(g -> 'itens' order by o) from jsonb_array_elements(x2) with ordinality e(g, o))
      and position('as OS vão a 1,2' in v_t) < position('barco vai a 0,9' in v_t) and position('barco vai a 0,9' in v_t) < position('energia em motorhome vai a 1,3' in v_t)
      and position('as OS vão a 1,2' in v_t) > 0,
      v_t || ' || ' || (select string_agg(x, ' | ' order by o, k) from jsonb_array_elements(x2) with ordinality e(g, o), jsonb_array_elements_text(g -> 'itens') with ordinality i(x, k)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r8$;

-- ── R7. A régua sem chave: com tudo em sombra e a rodada em teste gravada, o motor, a prontidão, a vigia e a rodada do cliente são os de antes ──
-- A âncora de fora: a rodada de ANTES do P7 (a agenda_aprender da origem, como função temporária) com os 6 desligados × a rodada do P7 com os 6 em sombra; depois de cada uma, as mesmas
-- leituras e rodadas. Só muda o que a 7e acrescenta de propósito (a margem medida, as compras, o congelado da marcação), e nada disso chega ao motor, à prontidão, à vigia nem ao cliente.
-- O que é volátil sai da comparação: os tempos (ms, duração) e os ids gerados (uuid). As rodadas contam o que gravaram (perguntas, ações, mensagens, propostas, alocações), pela diferença.
create function pg_temp.limpa(p jsonb) returns jsonb language plpgsql immutable as $f$
begin
  return case jsonb_typeof(p)
    when 'object' then coalesce((select jsonb_object_agg(e.k, pg_temp.limpa(e.v)) from jsonb_each(p) e(k, v) where e.k !~ '^(ms|duracao|duracao_ms|tempo)$'), '{}'::jsonb)
    when 'array' then coalesce((select jsonb_agg(pg_temp.limpa(a.v) order by a.o) from jsonb_array_elements(p) with ordinality a(v, o)), '[]'::jsonb)
    else p end;
end $f$;
create function pg_temp.semid(p jsonb) returns text language sql immutable as $f$
  select regexp_replace(pg_temp.limpa(p)::text, '"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"', '"U"', 'g')
$f$;
create function pg_temp.conta() returns text language sql stable as $f$
  select concat_ws(':', (select count(*) from public.agenda_perguntas), (select count(*) from public.agenda_acoes), (select count(*) from public.agenda_equipe_mensagens),
                   (select count(*) from public.agenda_cliente_mensagens), (select count(*) from public.agenda_propostas),
                   (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada')))
$f$;
create function pg_temp.r7_foto(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
declare
  v  jsonb := '{}';
  c0 text;
begin
  v := v || jsonb_build_object('agenda_propor', md5(pg_temp.semid(public.agenda_propor('semana', date '2027-01-11', date '2027-01-16', null, '{}'::jsonb, false, 'vigia', null, p_hoje, p_agora))));
  v := v || jsonb_build_object('os_prontidao', (select md5(string_agg(pg_temp.semid(public.os_prontidao(so.id, p_hoje)), '|' order by so.service_order_number))
                                                  from public.service_orders so where so.merged_into_id is null and so.status not in ('completed', 'invoiced', 'cancelled')));
  v := v || jsonb_build_object('agenda_meios_da_os', (select md5(string_agg(coalesce(pg_temp.semid(public.agenda_meios_da_os(so.id, p_hoje)), '-'), '|' order by so.service_order_number))
                                                        from public.service_orders so where so.merged_into_id is null and so.status not in ('completed', 'invoiced', 'cancelled')));
  begin
    c0 := pg_temp.conta();
    v := v || jsonb_build_object('agenda_vigiar', md5(pg_temp.semid(public.agenda_vigiar(p_hoje, p_agora)) || c0 || '→' || pg_temp.conta()));
    raise exception 'desfaz' using errcode = 'P0097';
  exception when sqlstate 'P0097' then null;
  end;
  begin
    c0 := pg_temp.conta();
    v := v || jsonb_build_object('agenda_cliente_vigiar', md5(pg_temp.semid(public.agenda_cliente_vigiar(p_hoje, p_agora)) || c0 || '→' || pg_temp.conta()));
    raise exception 'desfaz' using errcode = 'P0097';
  exception when sqlstate 'P0097' then null;
  end;
  return v;
end $f$;

do $r7$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  c_agora constant timestamptz := timestamptz '2027-01-07 16:05-03';
  v_a  jsonb;
  v_b  jsonb;
  v_ra jsonb;
  v_rb jsonb;
  v_n  int;
  v_dif text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'R7 a régua sem chave', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  perform pg_temp.criar_antes('agenda_aprender', 'mig_correcao_calculo_fase6', 'aprender_antes');
  -- a: a rodada de antes do P7, os 6 desligados
  begin
    perform pg_temp.modos('desligado');
    set local session_replication_role = replica; delete from public.agenda_vigia_rodadas where rotina = 'aprender' and p_hoje = c_hoje; set local session_replication_role = origin;
    v_ra := pg_temp.aprender_antes(c_hoje, c_agora);
    v_a := pg_temp.r7_foto(c_hoje, c_agora);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- b: a rodada do P7, os 6 em sombra (a margem medida, as compras, o congelado da marcação)
  begin
    perform pg_temp.modos('sombra');
    v_rb := pg_temp.rodar();
    v_n := (select count(*) from public.agenda_aprendizado a where a.item in ('vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'));
    v_b := pg_temp.r7_foto(c_hoje, c_agora);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  select string_agg(x.key, ', ') into v_dif from jsonb_each_text(v_a) x where x.value is distinct from v_b ->> x.key;
  v_res := pg_temp.ok(v_res, 'R7a a rodada de antes com os 6 desligados × a do P7 com os 6 em sombra: o motor da semana, a prontidão e os meios de cada OS, a vigia e a rodada do cliente iguais (md5, com o que gravam)',
    v_dif is null and (select count(*) from jsonb_object_keys(v_a)) = 5 and (select count(*) from jsonb_object_keys(v_b)) = 5, coalesce(v_dif, v_a::text));
  v_res := pg_temp.ok(v_res, 'R7b o controle de que a rodada do P7 rodou de verdade em b: a margem gravou linhas e a rodada tem os passos novos (e a de antes, não)',
    v_n > 0 and (v_rb -> 'contagens') ?& array['medir_compras', 'congelar_marcacao', 'vies', 'modos_margem'] and not (v_ra -> 'contagens') ?| array['medir_compras', 'vies', 'modos_margem'],
    format('%s linhas da margem; b %s', v_n, (v_rb -> 'contagens')::text));
  perform pg_temp.gravar(v_res);
end
$r7$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
