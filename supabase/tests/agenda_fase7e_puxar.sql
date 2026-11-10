-- Prova do puxar na véspera da Agenda de Produção, Fase 7e (pacote P4b; migration 20261111100350; spec-fase7e §5.3, §8.3 F5 e o bloco R7: R7.6, R7.7 inteira, R7.8, R7.12, R7.13).
-- bancada: depende de 20261111100350
--
--   P0 a porta da função e a migration (só cria ela)
--   P1 as saídas de cedo: sem dia e hora, desligado, cedo, não útil, já rodou
--   P2 quem pode ser puxado: ja_vem, o telefone que a rotina alcança (R7.7-6), a ficha que já saiu, o convite sem o SIM (R7.7-8), disponivel, o dono
--   P3 qual OS: a OS sem alocação (o caso que passaria vazio pelo atalho, R7.7-2), a reserva, o bem, o "não antes de", o dito ao cliente, o acesso e o pátio (conflito 9), o material, o desfeito, a ordem e o limite, a ficha presa no veto
--   P4 em teste só o diário (R7.7-1), com o freio também; a simulação do gestor fica só dentro do passo
--   P5 de verdade: a alocação nasce em D, releio depois; a reserva vira compromisso; uma vez por dia pela rodada inteira
--   P6 o erro: vai a app_error_logs (gestor:puxar), não lança e segue para a próxima OS; query_canceled não é engolido
--   P7 a OS na forma real (conferência do P4b): a "abre e fecha" pela regra (a ponta do dono em D) e a que pede o dono, com o dia declarado por ele e sem a rotina;
--      e 2 ou 3 por dia (2ª e 3ª conferências): em teste, a simulação de cada OS seguinte vê as já puxadas (num bloco que se desfaz, a fixada que elas cancelam com a chave, como o agenda_aplicar) e diz o mesmo que o de verdade (P7e a P7l)
--   P8 tudo ou nada por OS (P4c): a OS cuja proposta traz item crítico (a reserva fixada pelo dono que viola) fica fora com pede_decisao,
--      em teste e de verdade, sem perder o que tinha e sem proposta, pergunta nem alocação nova; a seguinte da fila é tentada; a mesma OS sem o item crítico continua puxada
--
-- ═══ COMO RODAR ═══  Na bancada: node scripts/bancada-agenda/rodar.mjs. Em produção, só DEPOIS de aplicar a migration, com o OK: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7e_puxar.sql
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
create function pg_temp.fx() returns boolean language sql stable as $f$ select coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' $f$;

-- ── P0. A porta (sem fixture) ───────────────────────────────────────────────────────────────────
insert into _resultado
select 'P0a o passo: definer, volatile, search_path fixo, sem porta para ninguém (anon, authenticated, service_role nem public); quem chama é agenda_gestor_rodar',
       p.prosecdef and p.provolatile = 'v' and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute')
       and not coalesce((select bool_or(a.grantee = 0) from aclexplode(p.proacl) a where a.privilege_type = 'EXECUTE'), false),
       p.proacl::text
  from pg_proc p where p.oid = 'public._agenda_gestor_puxar(date, timestamptz)'::regprocedure;
insert into _resultado
select 'P0b a migration cria só o puxar: o motor, a rodada do gestor, a exceção do lote e as de cliente ficam como o P4 e a 7f deixaram (R7.1, R7.R, pergunta 1 do orquestrador)',
       case when coalesce(current_setting('agenda_teste.mig_puxar_fase7e', true), '') = '' then true
            else (select coalesce(array_agg(distinct m[1]), '{}') from regexp_matches(current_setting('agenda_teste.mig_puxar_fase7e'), 'create or replace function public\.([a-z_0-9]+)\(', 'g') m) = array['_agenda_gestor_puxar'] end,
       case when coalesce(current_setting('agenda_teste.mig_puxar_fase7e', true), '') = '' then 'PULADO: sem a migration como texto (rode pela bancada)' end;

-- ── A fixture e os ajudantes ───────────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' then
    execute current_setting('agenda_teste.fase7e');
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = 'e7e00000-0000-4000-8000-000000000e00'
     where service_order_number not like 'OS-7E%' and service_order_number <> 'OS-E0' and merged_into_id is null;
    perform set_config('marineflow.agrupar_orcamentos', '', true);
  end if;
end
$carga$;

create function pg_temp.adm() returns uuid language sql stable as $f$ select id from public.app_users where role = 'admin' and active order by id limit 1 $f$;
-- Mexer no que as travas do plano não deixam mexer (só para montar a cena)
create function pg_temp.solto(p_sql text) returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  execute p_sql;
  set local session_replication_role = origin;
end $f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$ select id from public.payees where name = p_nome and active limit 1 $f$;
create function pg_temp.pr() returns date language sql immutable as $f$ select date '2027-02-10' $f$;  -- qua
create function pg_temp.ag(p_h text default '17:37') returns timestamptz language sql immutable as $f$ select (date '2027-02-10' + p_h::time) at time zone 'America/Sao_Paulo' $f$;
create function pg_temp.d() returns date language sql immutable as $f$ select date '2027-02-11' $f$;  -- qui: amanhã
create function pg_temp.rodar(p_h text default '17:37') returns jsonb language sql as $f$ select public._agenda_gestor_puxar(pg_temp.pr(), pg_temp.ag(p_h)) $f$;
-- Uma OS pronta (dias ditos pelo dono, material conferido, motorhome ao pátio com o bem já lá): tudo o que o puxar pede. Com dono_presenca 'nunca', que a carteira real não tem: a forma real é o P7
create function pg_temp.pronta(p_n int, p_dias numeric default 0.5, p_prio smallint default null) returns uuid language plpgsql as $f$
declare
  v_os uuid := md5('e7e:p:' || p_n)::uuid;
begin
  perform set_config('agenda.porta', 'on', true);
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
  values (v_os, 'OS-7EP' || lpad(p_n::text, 3, '0'), 'e7e00000-0000-4000-8000-000000000c02', 'e7e00000-0000-4000-8000-000000000b02', 'open', 'approved', 'repair',
          timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-02 10:00-03', 1000);
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (v_os, 'Reparo do quadro', 'visit', 1, 1000, 1000, timestamptz '2026-12-01 10:00-03');
  perform set_config('agenda.porta', 'off', true);
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em, prioridade_manual, entrada_em, entrada_fonte)
  values (v_os, p_dias, 'dono', timestamptz '2026-12-05 10:00-03', 'nunca', timestamptz '2026-12-05 10:00-03', p_prio, pg_temp.pr(), 'dono');
  return v_os;
end $f$;
create function pg_temp.aloca(p_os uuid, p_quem uuid, p_dia date, p_turno text default 'manha', p_tipo text default 'execucao', p_presenca text default 'turno') returns void language sql as $f$
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, reserva_de)
  values (p_os, p_quem, p_dia, p_turno, p_presenca, p_tipo, 'publicada', 'motor', timestamptz '2027-02-01 10:00-03', case when p_tipo = 'reserva' then 'teto' end)
$f$;
create function pg_temp.so_quem(p_quem uuid) returns void language plpgsql as $f$
begin
  update public.agenda_equipe_contato set recebe_rotina = false, parou_em = timestamptz '2027-01-01 10:00-03', parou_motivo = 'teste 7e P4b' where payee_id <> p_quem;
  update public.payees set phone = '5547900000999' where id = p_quem;
  if exists (select 1 from public.agenda_equipe_contato c where c.payee_id = p_quem) then
    update public.agenda_equipe_contato set recebe_rotina = true, parou_em = null, parou_motivo = null where payee_id = p_quem;
  else
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em) values (p_quem, true, 'dono', timestamptz '2027-01-01 10:00-03');
  end if;
end $f$;
-- A cena de base: o Rafael vem amanhã de manhã (na OS 900) e tem a tarde livre; a OS 901 é a próxima pronta. Urgência em teste, sem freio
create function pg_temp.cena() returns uuid language plpgsql as $f$
declare
  v_base uuid := pg_temp.pronta(900, 1);
  v_raf uuid := pg_temp.pessoa('Rafael');
begin
  update public.agenda_config set modo_urgencia = 'sombra', modo_proposta = 'ligado', gestor_so_propor = false, modo_marcar_sozinho = 'ligado', modo_equipe = 'ligado',
         modo_equipe_convite = 'desligado', puxar_quem = 'ja_vem', puxar_max_os = 1, marcar_sozinho_desde = null, modo_folga_semana = 'desligado' where id;
  perform pg_temp.so_quem(v_raf);
  perform pg_temp.aloca(v_base, v_raf, pg_temp.d(), 'manha');
  return pg_temp.pronta(901);
end $f$;
create function pg_temp.conta() returns text language sql stable as $f$
  select concat_ws('|', (select count(*) from public.agenda_propostas), (select count(*) from public.agenda_acoes), (select count(*) from public.agenda_alocacoes),
                        (select count(*) from public.agenda_perguntas), (select count(*) from public.agenda_equipe_mensagens), (select count(*) from public.agenda_cliente_mensagens))
$f$;
create function pg_temp.fora(p_r jsonb, p_os uuid) returns text language sql immutable as $f$
  select coalesce((select coalesce(e ->> 'motivo', 'puxada') from jsonb_array_elements(p_r -> 'por_os') e where (e ->> 'os')::uuid = p_os), 'nao_entrou')
$f$;
create function pg_temp.puxada(p_r jsonb, p_os uuid) returns boolean language sql immutable as $f$
  select coalesce((select e ->> 'resultado' = 'puxada' and (e ->> 'primeiro_dia')::date = date '2027-02-11' from jsonb_array_elements(p_r -> 'por_os') e where (e ->> 'os')::uuid = p_os), false)
$f$;

-- ── P1. As saídas de cedo ───────────────────────────────────────────────────────────────────────
do $p1$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  v_os uuid;
  v_st text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P1 as saídas', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    v_os := pg_temp.cena();
    begin
      perform public._agenda_gestor_puxar(null, pg_temp.ag());
      v_st := 'nao lancou';
    exception when others then v_st := sqlstate;
    end;
    v_res := pg_temp.ok(v_res, 'P1a sem o dia: recusa 22004', v_st = '22004', v_st);
    begin
      perform public._agenda_gestor_puxar(pg_temp.pr(), null);
      v_st := 'nao lancou';
    exception when others then v_st := sqlstate;
    end;
    v_res := pg_temp.ok(v_res, 'P1a2 sem a hora: recusa 22004', v_st = '22004', v_st);
    update public.agenda_config set modo_urgencia = 'desligado' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P1b urgência desligada: {rodou: false, modo: desligado}, sem mais nada', r = '{"rodou": false, "modo": "desligado"}'::jsonb, r::text);
    update public.agenda_config set modo_urgencia = 'sombra', modo_proposta = 'desligado' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P1c agenda automática desligada: não roda', r = '{"rodou": false, "modo": "desligado"}'::jsonb, r::text);
    update public.agenda_config set modo_proposta = 'ligado' where id;
    r := pg_temp.rodar('17:29');
    v_res := pg_temp.ok(v_res, 'P1d 17:29: cedo', r = '{"rodou": false, "cedo": true}'::jsonb, r::text);
    -- o job roda com a sessão em UTC: a hora tem de ser a de Brasília, não a da sessão
    v_st := current_setting('TimeZone');
    perform set_config('TimeZone', 'UTC', true);
    r := pg_temp.rodar('17:29');
    perform set_config('TimeZone', v_st, true);
    v_res := pg_temp.ok(v_res, 'P1d4 com a sessão em UTC, 17:29 de Brasília continua cedo', r = '{"rodou": false, "cedo": true}'::jsonb, r::text);
    r := pg_temp.rodar('17:30');
    v_res := pg_temp.ok(v_res, 'P1d2 17:30 em ponto: roda (a hora é BRT, puxar_hora)', (r ->> 'rodou')::boolean, r::text);
    update public.agenda_config set puxar_hora = '18:00' where id;
    r := pg_temp.rodar('17:37');
    v_res := pg_temp.ok(v_res, 'P1d3 puxar_hora 18:00: 17:37 é cedo (o parâmetro vale)', r = '{"rodou": false, "cedo": true}'::jsonb, r::text);
    update public.agenda_config set puxar_hora = '17:30' where id;
    r := public._agenda_gestor_puxar(date '2027-02-13', (date '2027-02-13' + time '17:37') at time zone 'America/Sao_Paulo');
    v_res := pg_temp.ok(v_res, 'P1e sábado (não útil): {motivo: nao_util}', r = '{"rodou": false, "motivo": "nao_util"}'::jsonb, r::text);
    -- já rodou: uma rodada do dia com puxar.rodou = true segura; a de outro dia ou a que não rodou, não
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
    values (pg_temp.ag(), pg_temp.pr() - 1, pg_temp.ag(), 'ligado', 'ligado', '{"puxar": {"rodou": true}}', 0, 1, 'gestor', 'ligado', 'desligado');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P1f a rodada de ontem não segura hoje', (r ->> 'rodou')::boolean, r::text);
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
    values (pg_temp.ag(), pg_temp.pr(), pg_temp.ag(), 'ligado', 'ligado', '{"puxar": {"rodou": false, "cedo": true}}', 0, 1, 'gestor', 'ligado', 'desligado');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P1f2 a rodada de hoje que ficou "cedo" não segura', (r ->> 'rodou')::boolean, r::text);
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
    values (pg_temp.ag(), pg_temp.pr(), pg_temp.ag(), 'ligado', 'ligado', '{"puxar": {"rodou": true}}', 0, 1, 'vigia', 'ligado', 'desligado');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P1f3 só conta a rodada do gestor', (r ->> 'rodou')::boolean, r::text);
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
    values (pg_temp.ag(), pg_temp.pr(), pg_temp.ag(), 'ligado', 'ligado', '{"puxar": {"rodou": true, "celulas": 0}}', 0, 1, 'gestor', 'ligado', 'desligado');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P1g já rodou hoje: {ja_rodou: true}', r = '{"rodou": false, "ja_rodou": true}'::jsonb, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then
    v_res := pg_temp.ok(v_res, 'P1 sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$p1$;

-- ── P2. Quem pode ser puxado ────────────────────────────────────────────────────────────────────
do $p2$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  v_os uuid;
  v_raf uuid := pg_temp.pessoa('Rafael');
  v_dono uuid;
  v_bru uuid := pg_temp.pessoa('Bruno');
  v_mic uuid := pg_temp.pessoa('Mickael');
  v_cont text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P2 quem', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  v_dono := public._agenda_dono(null);
  begin
    v_os := pg_temp.cena();
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2a ja_vem: o Rafael vem de manhã e a tarde livre vira 1 célula; a OS sem alocação entra (o caso que o atalho do _agenda_combinar_da_os deixaria vazio, R7.7-2)',
      (r ->> 'celulas')::int = 1 and (r ->> 'candidatas')::int >= 1 and pg_temp.puxada(r, v_os), r::text);
    -- os dois turnos ocupados: sem célula
    perform pg_temp.aloca(md5('e7e:p:900')::uuid, v_raf, pg_temp.d(), 'tarde');
    update public.agenda_gestor_dia set sombra = '{}' where dia = pg_temp.pr();
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2b os dois turnos ocupados: nenhuma célula, rodou: true, celulas 0, e o diário não é escrito', r ->> 'rodou' = 'true' and (r ->> 'celulas')::int = 0 and (r ->> 'candidatas')::int = 0 and (r ->> 'puxadas')::int = 0
      and not exists (select 1 from public.agenda_gestor_dia g where g.dia = pg_temp.pr() and g.sombra ? 'puxar'), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P2a sem exceção', false, sqlerrm);
  end;

  begin
    v_os := pg_temp.cena();
    update public.payees set phone = null where id = v_raf;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2c sem telefone não puxa, mesmo com a linha de contato e recebe_rotina (o caso do Alex em produção, R7.7-6)', (r ->> 'celulas')::int = 0, r::text);
    update public.payees set phone = '5547900000999' where id = v_raf;
    update public.agenda_equipe_contato set recebe_rotina = false where payee_id = v_raf;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2d com telefone, mas recebe_rotina false: não puxa', (r ->> 'celulas')::int = 0, r::text);
    delete from public.agenda_equipe_contato where payee_id = v_raf;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2f sem linha de contato: não puxa', (r ->> 'celulas')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P2c sem exceção', false, sqlerrm);
  end;

  -- a ficha que já saiu (a pessoa não saberia: a rotina manda uma só)
  begin
    v_os := pg_temp.cena();
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em)
    values (v_raf, pg_temp.d(), 'ficha', 'ligado', 'teste 7e P4b', pg_temp.ag(), 'enfileirada', 'teste:ficha:' || pg_temp.d(), pg_temp.ag());
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2g a ficha de amanhã já registrada: a pessoa não conta', (r ->> 'celulas')::int = 0, r::text);
    perform pg_temp.solto(format($s$update public.agenda_equipe_mensagens set dia = %L where dedupe_key like 'teste:%%'$s$, pg_temp.d() + 1));
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2g2 a ficha de outro dia não conta', (r ->> 'celulas')::int = 1, r::text);
    perform pg_temp.solto($s$delete from public.agenda_equipe_mensagens where dedupe_key like 'teste:%'$s$);
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, leva_ficha_de, modo, texto, enviar_em, estado, dedupe_key, criada_em)
    values (v_raf, pg_temp.pr(), 'como_foi', pg_temp.d(), 'ligado', 'teste 7e P4b', pg_temp.ag(), 'enfileirada', 'teste:como:' || pg_temp.d(), pg_temp.ag());
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2h o "como foi" que já levou a ficha de amanhã: a pessoa não conta', (r ->> 'celulas')::int = 0, r::text);
    perform pg_temp.solto($s$update public.agenda_equipe_mensagens set modo = 'sombra' where dedupe_key like 'teste:%'$s$);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2h2 a mensagem em outro modo não conta (a chave da ficha é por modo, como em _agenda_rotina_ficha)', (r ->> 'celulas')::int = 1, r::text);
    update public.agenda_config set modo_equipe = 'sombra' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2h3 com a equipe em teste, a ficha registrada em teste é a que conta', (r ->> 'celulas')::int = 0, r::text);
    update public.agenda_config set modo_equipe = 'ligado' where id;
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P2g sem exceção', false, sqlerrm);
  end;

  -- o convite sem o SIM (R7.7-8)
  begin
    v_os := pg_temp.cena();
    update public.agenda_config set modo_equipe_convite = 'ligado' where id;
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em)
    values (v_raf, pg_temp.d(), 'convite', 'ligado', 'teste 7e P4b', pg_temp.ag(), 'enfileirada', 'teste:conv:' || pg_temp.d(), pg_temp.ag());
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2i convite de amanhã enfileirado e sem o SIM, com o convite ligado: em ja_vem não conta (R7.7-8)', (r ->> 'celulas')::int = 0, r::text);
    perform pg_temp.solto($s$update public.agenda_equipe_mensagens set estado = 'sem_resposta' where dedupe_key like 'teste:%'$s$);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2i2 sem_resposta: também não conta', (r ->> 'celulas')::int = 0, r::text);
    perform pg_temp.solto($s$update public.agenda_equipe_mensagens set estado = 'respondida', leitura = '{"convite": "nao"}' where dedupe_key like 'teste:%'$s$);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2i3 respondeu NÃO: não conta', (r ->> 'celulas')::int = 0, r::text);
    perform pg_temp.solto($s$update public.agenda_equipe_mensagens set leitura = '{"convite": "sim"}' where dedupe_key like 'teste:%'$s$);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2i4 respondeu SIM: conta', (r ->> 'celulas')::int = 1, r::text);
    perform pg_temp.solto($s$update public.agenda_equipe_mensagens set estado = 'recusada', recusa_motivo = 'teto', leitura = null where dedupe_key like 'teste:%'$s$);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2i5 convite recusado pelo registro (nem saiu): a mesma lista da ficha, conta', (r ->> 'celulas')::int = 1, r::text);
    perform pg_temp.solto(format($s$update public.agenda_equipe_mensagens set estado = 'enfileirada', recusa_motivo = null, dia = %L where dedupe_key like 'teste:%%'$s$, pg_temp.d() + 1));
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2i6 convite de outro dia: conta', (r ->> 'celulas')::int = 1, r::text);
    perform pg_temp.solto(format($s$update public.agenda_equipe_mensagens set dia = %L where dedupe_key like 'teste:%%'$s$, pg_temp.d()));
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2j com o freio o convite vira teste (_agenda_fala_modo): a regra é a da ficha, e a pessoa conta', (r ->> 'celulas')::int = 1, r::text);
    update public.agenda_config set gestor_so_propor = false, modo_equipe_convite = 'sombra' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2j2 convite em teste: conta', (r ->> 'celulas')::int = 1, r::text);
    update public.agenda_config set modo_equipe_convite = 'ligado' where id;
    perform pg_temp.solto($s$update public.agenda_equipe_mensagens set modo = 'sombra' where dedupe_key like 'teste:%'$s$);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2j3 convite gravado em teste não segura: só o que saiu de verdade', (r ->> 'celulas')::int = 1, r::text);
    perform pg_temp.solto($s$update public.agenda_equipe_mensagens set modo = 'ligado' where dedupe_key like 'teste:%'$s$);
    update public.agenda_config set puxar_quem = 'disponivel' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2k em disponivel o convite pendente não tira a pessoa (a puxada vira convite sozinha, R7.7-8)', (r ->> 'celulas')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P2i sem exceção', false, sqlerrm);
  end;

  -- ja_vem × disponivel
  begin
    v_os := pg_temp.cena();
    -- o Bruno: sem alocação amanhã, com o dia declarado por ele
    perform pg_temp.so_quem(v_bru);
    perform pg_temp.solto(format('delete from public.agenda_alocacoes where payee_id = %L', v_raf));
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_bru, daterange(pg_temp.d(), pg_temp.d(), '[]'), 'disponivel', 'diarista', 'teste 7e P4b', pg_temp.adm());
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2l ja_vem: quem não tem turno marcado em D não ganha dia (o João da §8.3)', (r ->> 'celulas')::int = 0, r::text);
    update public.agenda_config set puxar_quem = 'disponivel' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2m disponivel: quem declarou entra, com as 2 células', (r ->> 'celulas')::int = 2 and (r ->> 'puxadas')::int = 1, r::text);
    update public.agenda_disponibilidade set origem = 'historico', frequencia = 0.8 where payee_id = v_bru and nota = 'teste 7e P4b';
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2n o que veio do histórico não é declarado: não conta nem em disponivel', (r ->> 'celulas')::int = 0, r::text);
    update public.agenda_disponibilidade set origem = 'dono', frequencia = null where payee_id = v_bru and nota = 'teste 7e P4b';
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2n2 o dia que o dono declarou por ele: conta', (r ->> 'celulas')::int = 2, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P2l sem exceção', false, sqlerrm);
  end;

  -- a alocação que conta como "já vem"
  begin
    v_os := pg_temp.cena();
    perform pg_temp.solto(format('delete from public.agenda_alocacoes where payee_id = %L', v_raf));
    perform pg_temp.aloca(md5('e7e:p:900')::uuid, v_raf, pg_temp.d(), 'manha', 'reserva');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2o a reserva não é "já vem" (a pessoa pode nem vir)', (r ->> 'celulas')::int = 0, r::text);
    perform pg_temp.solto(format('delete from public.agenda_alocacoes where payee_id = %L', v_raf));
    perform pg_temp.aloca(md5('e7e:p:900')::uuid, v_raf, pg_temp.d(), 'manha');
    perform pg_temp.solto(format($s$update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = %L, cancelada_motivo = 'replanejado' where payee_id = %L$s$, pg_temp.ag(), v_raf));
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2o3 a alocação cancelada não é "já vem"', (r ->> 'celulas')::int = 0, r::text);
    perform pg_temp.solto(format('delete from public.agenda_alocacoes where payee_id = %L', v_raf));
    perform pg_temp.aloca(md5('e7e:p:900')::uuid, v_raf, pg_temp.d(), 'manha');
    perform pg_temp.solto(format($s$update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'congelamento' where payee_id = %L$s$, v_raf));
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2o5 a fixada também é "já vem"', (r ->> 'celulas')::int = 1, r::text);
    perform pg_temp.solto(format('delete from public.agenda_alocacoes where payee_id = %L', v_raf));
    perform pg_temp.aloca(md5('e7e:p:900')::uuid, v_raf, pg_temp.d() + 1, 'manha');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2o6 a alocação de outro dia não é "já vem" amanhã', (r ->> 'celulas')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P2o sem exceção', false, sqlerrm);
  end;

  -- a presença curta só existe para o dono: ele abrir e fechar não é "já vem"
  begin
    v_os := pg_temp.cena();
    perform pg_temp.so_quem(v_dono);
    perform pg_temp.solto(format('delete from public.agenda_alocacoes where payee_id = %L', v_raf));
    perform pg_temp.solto(format('delete from public.agenda_disponibilidade where payee_id = %L', v_dono));
    insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, frequencia, nota, criado_por)
    values (v_dono, array[1, 2, 3, 4, 5]::smallint[], 'disponivel', 'historico', 0.8, 'teste 7e P4b', pg_temp.adm());
    perform pg_temp.aloca(md5('e7e:p:900')::uuid, v_dono, pg_temp.d(), 'manha', 'execucao', 'abertura');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2o4 o dono só abrindo de manhã (presença curta, sem turno) e sem o dia declarado por ele: não conta', (r ->> 'celulas')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P2o4 sem exceção', false, sqlerrm);
  end;

  -- o dono: disponibilidade declarada em D, com a rotina alcançando
  begin
    v_os := pg_temp.cena();
    perform pg_temp.so_quem(v_dono);
    perform pg_temp.solto(format('delete from public.agenda_alocacoes where payee_id = %L', v_raf));
    perform pg_temp.solto(format('delete from public.agenda_disponibilidade where payee_id = %L', v_dono));
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2p o dono sem o dia declarado: não conta', (r ->> 'celulas')::int = 0, r::text);
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_dono, daterange(pg_temp.d(), pg_temp.d(), '[]'), 'disponivel', 'dono', 'teste 7e P4b', pg_temp.adm());
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2q o dono com o dia declarado (e contato da rotina): conta em ja_vem', (r ->> 'celulas')::int = 2, r::text);
    delete from public.agenda_equipe_contato where payee_id = v_dono;
    r := pg_temp.rodar();
    -- mudou de propósito na conferência do P4b: o dono não recebe ficha (quem o alcança é o aviso do gestor e o fechamento); exigir a rotina dele tirava toda OS que pede o dono
    v_res := pg_temp.ok(v_res, 'P2r o dono sem linha de contato (como em produção hoje), com o dia declarado: conta (§5.3; a rotina é regra da equipe)', (r ->> 'celulas')::int = 2, r::text);
    update public.payees set phone = null where id = v_dono;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2r2 o dono sem telefone e sem linha de contato: conta igual', (r ->> 'celulas')::int = 2, r::text);
    perform pg_temp.solto(format('delete from public.agenda_disponibilidade where payee_id = %L', v_dono));
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P2r3 o dono sem linha de contato e sem o dia declarado: não conta (só a ponta dele fica livre, e ponta não é célula)', (r ->> 'celulas')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P2p sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$p2$;

-- ── P3. Qual OS ─────────────────────────────────────────────────────────────────────────────────
do $p3$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  v_os uuid; v_a uuid; v_b uuid; v_c uuid;
  v_raf uuid := pg_temp.pessoa('Rafael');
  v_loc uuid;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P3 qual OS', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  -- alocações que ela já tem
  begin
    v_os := pg_temp.cena();
    perform pg_temp.aloca(v_os, pg_temp.pessoa('Alex'), date '2027-02-15');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3a a OS que já tem alocação vigente não é candidata', pg_temp.fora(r, v_os) = 'nao_entrou' and (r ->> 'puxadas')::int = 0, r::text);
    perform pg_temp.solto(format($s$update public.agenda_alocacoes set tipo = 'reserva', reserva_de = 'teto' where service_order_id = %L$s$, v_os));
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3b a reserva não impede (ela vira compromisso)', pg_temp.fora(r, v_os) <> 'nao_entrou', r::text);
    perform pg_temp.solto(format($s$update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = %L, cancelada_motivo = 'replanejado', tipo = 'execucao', reserva_de = null where service_order_id = %L$s$, pg_temp.ag(), v_os));
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3b2 a alocação cancelada não conta', pg_temp.puxada(r, v_os), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P3a sem exceção', false, sqlerrm);
  end;

  -- o bem e o "não antes de"
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set nao_antes_de = pg_temp.d() + 1, nao_antes_motivo = 'teste' where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3c "não antes de" depois de D: fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set nao_antes_de = pg_temp.d() where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3c2 "não antes de" em D: entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set nao_antes_de = null, nao_antes_motivo = null, bem_indisponivel = datemultirange(daterange(pg_temp.d(), pg_temp.d(), '[]')) where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3d o bem indisponível em D: fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set bem_indisponivel = datemultirange(daterange(pg_temp.d() + 3, pg_temp.d() + 4, '[]')) where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3d2 indisponível em outro dia: entra', pg_temp.puxada(r, v_os), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P3c sem exceção', false, sqlerrm);
  end;

  -- o dito ao cliente (§5.3, passo 3)
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set prometido_tipo = 'firme', prometido_de = pg_temp.d() + 1, prometido_ate = pg_temp.d() + 1 where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3e dia firme dito em outra data: fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set prometido_de = pg_temp.d(), prometido_ate = pg_temp.d() where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3e2 dia firme dito em D: entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set prometido_de = null where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3e3 firme sem o início: vale o até (em D: entra), como a leitura da 7d', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set prometido_ate = pg_temp.d() + 1 where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3e4 firme sem o início, com o até em outro dia: fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set prometido_de = pg_temp.d(), prometido_ate = pg_temp.d() + 2 where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3e5 firme começando em D e terminando depois: o início é o que vale, entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set prometido_tipo = 'faixa', prometido_de = pg_temp.d() - 1, prometido_ate = pg_temp.d() + 1 where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3f faixa que contém D: entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set prometido_de = pg_temp.d() + 1, prometido_ate = pg_temp.d() + 3 where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3f2 faixa que não contém D: fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set prometido_de = pg_temp.d() - 3, prometido_ate = pg_temp.d() - 1 where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3f5 faixa que acaba antes de D: fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set prometido_tipo = 'condicional', prometido_de = null, prometido_ate = pg_temp.d() where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3f3 condicional em D, sem o início: entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set prometido_ate = pg_temp.d() + 1 where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3f4 condicional sem o início, com o até depois de D: fora (a faixa é só aquele dia)', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P3e sem exceção', false, sqlerrm);
  end;

  -- o pátio e o terceiro (conflito 9, R7.7-2)
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set entrada_em = null, entrada_fonte = null where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3g pátio sem a entrada: sem dado não puxa', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set entrada_em = pg_temp.d(), entrada_fonte = 'dono' where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3g2 entra só amanhã: ainda não está lá, fora (entrada_em <= hoje)', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set entrada_em = pg_temp.pr() where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3g3 entrou hoje: entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set entrada_em = null, entrada_fonte = null, bem_situacao = 'patio', bem_situacao_fonte = 'dono' where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3g4 sem a data, mas a situação dita é o pátio: entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set bem_situacao = 'com_cliente' where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3g5 a situação dita é "com o cliente": fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set entrada_em = pg_temp.pr() - 3, entrada_fonte = 'dono', bem_situacao = null, bem_situacao_fonte = null, retirada_em = pg_temp.d() where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3g6 sai em D: não dá para trabalhar lá (a máscara do local é do dia da retirada em diante)', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set retirada_em = pg_temp.d() + 1 where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3g7 sai depois de D: entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set retirada_em = null where service_order_id = v_os;
    -- a OS sem linha em os_planejamento: é o caso comum (4 de 131), e no pátio não tem a entrada
    delete from public.os_planejamento where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3g8 a OS sem linha em os_planejamento não lança e não puxa (sem dado)', pg_temp.fora(r, v_os) = 'nao_entrou' and (r ->> 'erros')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P3g sem exceção', false, sqlerrm);
  end;

  -- local de terceiro: troca o local resolvido
  begin
    v_os := pg_temp.cena();
    create or replace function public._agenda_local_resolvido(p_os uuid, p_hoje date) returns jsonb language sql stable as $x$
      select jsonb_build_object('tipo', current_setting('agenda_teste.tipo_local_p4b', true))
    $x$;
    perform set_config('agenda_teste.tipo_local_p4b', 'marina', true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3h marina sem acesso combinado: fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set acesso_ok_em = pg_temp.ag() - interval '89 days' where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3h2 acesso dentro da validade (89 dias): entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set acesso_ok_em = pg_temp.ag() - interval '90 days' where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3h3 acesso vencido (90 dias, cliente_acesso_validade_dias): fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.agenda_config set cliente_acesso_validade_dias = 120 where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3h4 a validade é o parâmetro (120 dias): entra', pg_temp.puxada(r, v_os), r::text);
    update public.agenda_config set cliente_acesso_validade_dias = 90 where id;
    update public.os_planejamento set acesso_ok_em = pg_temp.ag() where service_order_id = v_os;
    perform set_config('agenda_teste.tipo_local_p4b', 'estaleiro', true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3h5 estaleiro com acesso: entra', pg_temp.puxada(r, v_os), r::text);
    perform set_config('agenda_teste.tipo_local_p4b', 'casa_cliente', true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3h6 casa do cliente com acesso: entra', pg_temp.puxada(r, v_os), r::text);
    perform set_config('agenda_teste.tipo_local_p4b', 'outro', true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3h7 outro local com acesso: entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set entrada_em = null, entrada_fonte = null where service_order_id = v_os;
    perform set_config('agenda_teste.tipo_local_p4b', 'patio_parceiro', true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3h8 pátio de parceiro com acesso e sem o bem lá: fora (as duas regras)', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set entrada_em = pg_temp.pr(), entrada_fonte = 'dono', acesso_ok_em = null where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3h9 pátio de parceiro com o bem lá e sem acesso: fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set acesso_ok_em = pg_temp.ag() where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3h10 pátio de parceiro com as duas coisas: entra', pg_temp.puxada(r, v_os), r::text);
    perform set_config('agenda_teste.tipo_local_p4b', '', true);
    create or replace function public._agenda_local_resolvido(p_os uuid, p_hoje date) returns jsonb language sql stable as $x$ select '{"tipo": null, "fonte": "nenhum"}'::jsonb $x$;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3i não sei onde é (tipo nulo): não puxa', pg_temp.fora(r, v_os) = 'nao_entrou' and (r ->> 'erros')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P3h sem exceção', false, sqlerrm);
  end;

  -- a prontidão e o material
  begin
    v_os := pg_temp.cena();
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'awaiting_client' where id = v_os;
    perform set_config('agenda.porta', 'off', true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3j OS que não está pronta (aguardando cliente): fora', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'open' where id = v_os;
    perform set_config('agenda.porta', 'off', true);
    create or replace function public.os_prontidao(p_so_id uuid, p_hoje date default public._hoje_brt()) returns jsonb language sql stable as $x$
      select jsonb_build_object('estado', 'pronta', 'razao_critica', null, 'aprovada_em', '2026-12-02',
                                'material', jsonb_build_object('inicio_mat', nullif(current_setting('agenda_teste.mat_p4b', true), ''), 'inicio_mat_dito', nullif(current_setting('agenda_teste.mat_dito_p4b', true), '')))
    $x$;
    -- o motor lê a mesma função, mas o que importa aqui é o filtro: agenda_propor sai do caminho
    alter function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz) rename to agenda_propor_real_p4b;
    create function public.agenda_propor(p_escopo text, p_de date, p_ate date, p_os uuid[], p_restricoes jsonb, p_persistir boolean, p_origem text, p_autor uuid, p_hoje date, p_agora timestamptz)
      returns jsonb language sql as $x$ select jsonb_build_object('ok', true, 'itens', jsonb_build_array(jsonb_build_object('op', 'criar', 'os', p_os[1], 'tipo', 'execucao', 'alocacoes', jsonb_build_array(jsonb_build_object('dia', p_de, 'payee_id', (p_restricoes #>> '{puxar,pessoas,0}')))))) $x$;
    perform set_config('agenda_teste.mat_p4b', (pg_temp.d() + 1)::text, true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3k o material só dá para começar depois de D: fora (o P4 tirou o EST da prontidão)', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    perform set_config('agenda_teste.mat_p4b', pg_temp.d()::text, true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3k2 o material dá para começar em D: entra', pg_temp.puxada(r, v_os), r::text);
    perform set_config('agenda_teste.mat_dito_p4b', (pg_temp.d() + 1)::text, true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3k3 o dia dito do material é depois de D: fora (é por ele que _agenda_violacoes cancelaria)', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    perform set_config('agenda_teste.mat_p4b', '', true);
    perform set_config('agenda_teste.mat_dito_p4b', '', true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3k4 sem data de material (nulo = sem essa restrição): entra', pg_temp.puxada(r, v_os), r::text);
    -- a razão crítica ordena depois da prioridade
    v_a := pg_temp.pronta(902);
    create or replace function public.os_prontidao(p_so_id uuid, p_hoje date default public._hoje_brt()) returns jsonb language sql stable as $x$
      select jsonb_build_object('estado', 'pronta', 'razao_critica', case when p_so_id = md5('e7e:p:902')::uuid then 0.5 else 1 end, 'aprovada_em', '2026-12-02', 'material', '{}'::jsonb)
    $x$;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3k5 a razão crítica menor passa na frente do número (a ordem da fila do motor)', pg_temp.puxada(r, v_a) and (r ->> 'puxadas')::int = 1, r::text);
    -- o motor só deu reserva
    drop function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz);
    create function public.agenda_propor(p_escopo text, p_de date, p_ate date, p_os uuid[], p_restricoes jsonb, p_persistir boolean, p_origem text, p_autor uuid, p_hoje date, p_agora timestamptz)
      returns jsonb language sql as $x$ select jsonb_build_object('ok', true, 'itens', jsonb_build_array(jsonb_build_object('op', 'criar', 'os', p_os[1], 'tipo', 'reserva', 'alocacoes', jsonb_build_array(jsonb_build_object('dia', p_de, 'payee_id', (p_restricoes #>> '{puxar,pessoas,0}')))))) $x$;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3o2 o motor só deu reserva: não conta (só compromisso que comece em D)', pg_temp.fora(r, v_a) = 'sem_compromisso' and (r ->> 'puxadas')::int = 0, r::text);
    drop function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz);
    create function public.agenda_propor(p_escopo text, p_de date, p_ate date, p_os uuid[], p_restricoes jsonb, p_persistir boolean, p_origem text, p_autor uuid, p_hoje date, p_agora timestamptz)
      returns jsonb language sql as $x$ select jsonb_build_object('ok', true, 'itens', jsonb_build_array(jsonb_build_object('op', 'criar', 'os', p_os[1], 'tipo', 'execucao', 'alocacoes', jsonb_build_array(jsonb_build_object('dia', p_de + 1, 'payee_id', (p_restricoes #>> '{puxar,pessoas,0}')))))) $x$;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3o3 o compromisso começa depois de D: não conta', pg_temp.fora(r, v_a) = 'nao_coube_amanha' and (r ->> 'puxadas')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P3j sem exceção', false, sqlerrm);
  end;

  -- o que o dono desfez
  begin
    v_os := pg_temp.cena();
    create or replace function public._agenda_gestor_desfeito(p_os uuid, p_agora timestamptz) returns boolean language sql stable as $x$ select p_os = md5('e7e:p:901')::uuid $x$;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3l a OS que o dono desfez não volta sozinha (o molde do encaixe)', pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P3l sem exceção', false, sqlerrm);
  end;

  -- a ordem da fila e o limite
  begin
    v_os := pg_temp.cena();
    v_a := pg_temp.pronta(902, 0.5, 1::smallint);
    v_b := pg_temp.pronta(903);
    perform pg_temp.pronta(905);  -- número depois da 901, id antes dela: a ordem é pelo número
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3m a fila do motor: a prioridade do dono passa na frente do número; com puxar_max_os 1, só ela', pg_temp.puxada(r, v_a) and (r ->> 'puxadas')::int = 1 and (r ->> 'candidatas')::int >= 3 and pg_temp.fora(r, v_os) = 'nao_entrou', r::text);
    update public.os_planejamento set prioridade_manual = null where service_order_id = v_a;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3m2 sem prioridade: o número mais baixo primeiro', pg_temp.puxada(r, v_os) and (r ->> 'puxadas')::int = 1, r::text);
    update public.service_orders set converted_to_os_at = timestamptz '2026-11-20 10:00-03' where id = v_b;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3m3 aprovada há mais tempo passa na frente do número', pg_temp.puxada(r, v_b) and (r ->> 'puxadas')::int = 1, r::text);
    insert into public.receivables (service_order_id, client_id, description, issue_date, due_date, amount, paid_amount, balance_amount, status, is_deposit)
    values (v_a, 'e7e00000-0000-4000-8000-000000000c02', 'sinal', date '2026-12-05', date '2026-12-05', 100, 100, 0, 'paid', true);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3m4 com sinal pago passa na frente de quem foi aprovada antes', pg_temp.puxada(r, v_a) and (r ->> 'puxadas')::int = 1, r::text);
    -- 2 por dia, em teste: quem tem uma célula só não conta em duas OS (a simulação da 2ª vê a 1ª: P7e a P7k)
    update public.agenda_config set puxar_max_os = 2 where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3n em teste, com puxar_max_os 2 e uma célula só: conta 1, sem dizer que a mesma pessoa faria as duas', (r ->> 'puxadas')::int = 1, r::text);
    perform pg_temp.so_quem(v_raf);
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
    select pg_temp.pessoa('Bruno'), true, 'dono', timestamptz '2027-01-01 10:00-03' where not exists (select 1 from public.agenda_equipe_contato c where c.payee_id = pg_temp.pessoa('Bruno'));
    update public.agenda_equipe_contato set recebe_rotina = true, parou_em = null where payee_id = pg_temp.pessoa('Bruno');
    update public.payees set phone = '5547900000998' where id = pg_temp.pessoa('Bruno');
    perform pg_temp.aloca(md5('e7e:p:900')::uuid, pg_temp.pessoa('Bruno'), pg_temp.d(), 'manha');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3n2 duas pessoas com célula: as 2 OS em teste, uma para cada', (r ->> 'puxadas')::int = 2 and (r ->> 'celulas')::int = 2, r::text);
    update public.agenda_config set puxar_max_os = 1 where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3n3 puxar_max_os 1: só 1, mesmo com 2 pessoas', (r ->> 'puxadas')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P3m sem exceção', false, sqlerrm);
  end;

  -- o motor não dá compromisso em D
  begin
    v_os := pg_temp.cena();
    create or replace function public._agenda_local_mascara(p_os uuid, p_d_ini date, p_d_fim date, p_hoje date, p_local jsonb default null) returns jsonb language sql stable as $x$
      select jsonb_build_object('dias', '[]'::jsonb, 'meios', '[]'::jsonb, 'motivos', '[]'::jsonb, 'notas', '[]'::jsonb, 'sai', 0, 'ent', date '2027-02-12' - p_d_ini + 1)
    $x$;
    update public.agenda_config set modo_patio = 'ligado' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3o a máscara do local (a 7d, R7.7-3) empurra para depois de D: a simulação não aceita ("nao_coube_amanha"), e a OS não conta', pg_temp.fora(r, v_os) in ('nao_coube_amanha', 'sem_compromisso') and (r ->> 'puxadas')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P3o sem exceção', false, sqlerrm);
  end;

  -- a ficha presa na janela de veto do 7a-1
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set estimativa_fonte = 'orcamento' where service_order_id = v_os;
    update public.agenda_config set marcar_sozinho_desde = pg_temp.ag() - interval '5 days', ficha_veto_dias = 21 where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3p fonte orçamento na janela de veto: a ficha ficaria presa, fora', pg_temp.fora(r, v_os) = 'ficha_presa' and (r ->> 'puxadas')::int = 0, r::text);
    update public.agenda_config set marcar_sozinho_desde = pg_temp.ag() - interval '22 days' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3p2 passada a janela: entra', pg_temp.puxada(r, v_os), r::text);
    update public.agenda_config set marcar_sozinho_desde = (pg_temp.d() + 1)::timestamp at time zone 'America/Sao_Paulo' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3p3 D antes do início da janela: entra', pg_temp.puxada(r, v_os), r::text);
    update public.agenda_config set marcar_sozinho_desde = null where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3p4 o gestor nunca ligou: entra', pg_temp.puxada(r, v_os), r::text);
    update public.agenda_config set marcar_sozinho_desde = pg_temp.ag() - interval '5 days' where id;
    update public.os_planejamento set estimativa_fonte = 'dono' where service_order_id = v_os;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3p5 os dias ditos pelo dono, dentro da janela: entra', pg_temp.puxada(r, v_os), r::text);
    update public.os_planejamento set estimativa_fonte = 'orcamento' where service_order_id = v_os;
    update public.agenda_config set ficha_veto_dias = 3 where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3p7 a janela é o parâmetro (3 dias, passados): entra', pg_temp.puxada(r, v_os), r::text);
    update public.agenda_config set marcar_sozinho_desde = (pg_temp.d() - 3)::timestamp at time zone 'America/Sao_Paulo' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3p8 D é o dia em que a janela acaba (desde + 3 dias): já não está presa', pg_temp.puxada(r, v_os), r::text);
    update public.agenda_config set marcar_sozinho_desde = (pg_temp.d() - 2)::timestamp at time zone 'America/Sao_Paulo' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3p9 D ainda dentro (desde + 2 dias de 3): presa', pg_temp.fora(r, v_os) = 'ficha_presa', r::text);
    -- o dia do início da janela é o de Brasília: às 22:00 de D, com a sessão em UTC, já é D + 1 lá
    update public.agenda_config set ficha_veto_dias = 21, marcar_sozinho_desde = (pg_temp.d() + time '22:00') at time zone 'America/Sao_Paulo' where id;
    perform set_config('agenda_teste.tz_p4b', current_setting('TimeZone'), true);
    perform set_config('TimeZone', 'UTC', true);
    r := pg_temp.rodar();
    perform set_config('TimeZone', current_setting('agenda_teste.tz_p4b'), true);
    v_res := pg_temp.ok(v_res, 'P3p10 o início da janela é o dia de Brasília, mesmo com a sessão em UTC', pg_temp.fora(r, v_os) = 'ficha_presa', r::text);
    update public.agenda_config set ficha_veto_dias = 21, marcar_sozinho_desde = pg_temp.ag() - interval '5 days' where id;
    update public.os_planejamento set estimativa_fonte = 'orcamento' where service_order_id = v_os;
    alter function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz) rename to agenda_propor_real_p4b;
    create function public.agenda_propor(p_escopo text, p_de date, p_ate date, p_os uuid[], p_restricoes jsonb, p_persistir boolean, p_origem text, p_autor uuid, p_hoje date, p_agora timestamptz)
      returns jsonb language sql as $x$ select jsonb_build_object('ok', true, 'itens', jsonb_build_array(jsonb_build_object('op', 'criar', 'os', p_os[1], 'tipo', 'execucao', 'fonte', 'orcamento', 'alocacoes', jsonb_build_array(jsonb_build_object('dia', p_de, 'payee_id', public._agenda_dono(null)))))) $x$;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P3p6 a ficha do dono nunca fica presa (_agenda_ficha_liberada): entra', pg_temp.puxada(r, v_os), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P3p sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$p3$;

-- ── P4. Em teste, só o diário ───────────────────────────────────────────────────────────────────
do $p4$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  v_os uuid;
  v_raf uuid := pg_temp.pessoa('Rafael');
  v_antes text;
  v_s jsonb;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P4 em teste', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    v_os := pg_temp.cena();
    perform public._agenda_gestor_dia_gravar(pg_temp.pr(), 'sombra', '{"encaixe": [1], "revisao": {"x": 1}}'::jsonb, pg_temp.ag('16:52'));
    v_antes := pg_temp.conta();
    r := pg_temp.rodar();
    v_s := (select g.sombra -> 'puxar' from public.agenda_gestor_dia g where g.dia = pg_temp.pr());
    v_res := pg_temp.ok(v_res, 'P4a modo_urgencia em sombra: em_teste, e nada grava fora do diário (propostas, ações, alocações, perguntas, mensagens à equipe e ao cliente: R7.7-1)',
      (r ->> 'em_teste')::boolean and pg_temp.puxada(r, v_os) and pg_temp.conta() = v_antes, v_antes || ' depois ' || pg_temp.conta() || ' ' || r::text);
    v_res := pg_temp.ok(v_res, 'P4a2 o diário tem o puxar: o dia, as células, as candidatas, as puxadas, a OS e a hora (agenda_gestor_dia.sombra.puxar)',
      v_s ->> 'dia' = pg_temp.d()::text and (v_s ->> 'celulas')::int = 1 and (v_s ->> 'candidatas')::int >= 1 and (v_s ->> 'puxadas')::int = 1
      and v_s -> 'por_os' -> 0 ->> 'resultado' = 'puxada' and (v_s ->> 'calculado_em')::timestamptz = pg_temp.ag() and not (v_s ? 'rodou') and not (v_s ? 'em_teste'), coalesce(v_s::text, ''));
    v_res := pg_temp.ok(v_res, 'P4a3 o resto do diário do dia fica', (select g.sombra -> 'encaixe' = '[1]'::jsonb and g.sombra -> 'revisao' = '{"x": 1}'::jsonb from public.agenda_gestor_dia g where g.dia = pg_temp.pr()), null);
    v_res := pg_temp.ok(v_res, 'P4b a simulação do gestor não vaza para o resto da rodada (agenda.gestor volta a vazio)', coalesce(current_setting('agenda.gestor', true), '') = '', current_setting('agenda.gestor', true));
    v_res := pg_temp.ok(v_res, 'P4c o que sai na rodada tem as chaves da §5.3: rodou, celulas, candidatas, puxadas, em_teste, erros (e sem nome de cliente)',
      r ? 'rodou' and r ? 'celulas' and r ? 'candidatas' and r ? 'puxadas' and r ? 'em_teste' and r ? 'erros' and (r ->> 'erros')::int = 0 and r::text !~ 'cliente', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P4a sem exceção', false, sqlerrm);
  end;

  -- freio = só o diário
  begin
    v_os := pg_temp.cena();
    update public.agenda_config set modo_urgencia = 'ligado', gestor_so_propor = true where id;
    v_antes := pg_temp.conta();
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P4d ligado com o freio: em_teste (só o diário), nenhuma linha fora dele (R7.6)',
      (r ->> 'em_teste')::boolean and r ->> 'modo' = 'sombra' and pg_temp.puxada(r, v_os) and pg_temp.conta() = v_antes
      and (select g.sombra ? 'puxar' from public.agenda_gestor_dia g where g.dia = pg_temp.pr()), v_antes || ' depois ' || pg_temp.conta() || ' ' || r::text);
    update public.agenda_config set gestor_so_propor = false, modo_proposta = 'sombra' where id;
    v_antes := pg_temp.conta();
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P4e modo_proposta em sombra com a urgência ligada: em_teste', (r ->> 'em_teste')::boolean and r ->> 'modo' = 'ligado' and pg_temp.conta() = v_antes, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P4d sem exceção', false, sqlerrm);
  end;

  -- com o freio, a conta é a do gestor solto: a OS que só o gestor marcaria sozinho também sai em teste
  begin
    v_os := pg_temp.cena();
    update public.agenda_config set modo_urgencia = 'ligado', gestor_so_propor = true, marcar_regras = array['estimativa', 'mo_limpa', 'uma_pessoa', 'prazo_padrao', 'compra_firme', 'critico_por_valor', 'embutida_suposta', 'situacao', 'diagnostico', 'sem_peca'] where id;
    create or replace function public._agenda_gestor_regra(p_regra text) returns boolean language sql stable as $x$ select coalesce(current_setting('agenda.gestor', true), '') = 'sombra' $x$;
    create or replace function public.os_prontidao(p_so_id uuid, p_hoje date default public._hoje_brt()) returns jsonb language sql stable as $x$
      select jsonb_build_object('estado', case when public._agenda_gestor_regra('estimativa') then 'pronta' else 'esperando_voce' end, 'razao_critica', null, 'aprovada_em', '2026-12-02', 'material', '{}'::jsonb)
    $x$;
    alter function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz) rename to agenda_propor_real_p4b;
    create function public.agenda_propor(p_escopo text, p_de date, p_ate date, p_os uuid[], p_restricoes jsonb, p_persistir boolean, p_origem text, p_autor uuid, p_hoje date, p_agora timestamptz)
      returns jsonb language sql as $x$ select jsonb_build_object('ok', true, 'itens', jsonb_build_array(jsonb_build_object('op', 'criar', 'os', p_os[1], 'tipo', case when public._agenda_gestor_regra('estimativa') then 'execucao' else 'reserva' end, 'alocacoes', jsonb_build_array(jsonb_build_object('dia', p_de, 'payee_id', (p_restricoes #>> '{puxar,pessoas,0}')))))) $x$;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P4f com o freio, a prontidão e o motor correm com as regras do gestor valendo (a simulação do encaixe)', pg_temp.puxada(r, v_os), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P4f sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$p4$;

-- ── P5. De verdade ──────────────────────────────────────────────────────────────────────────────
do $p5$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  v_os uuid;
  v_raf uuid := pg_temp.pessoa('Rafael');
  v_antes bigint;
  v_cancel int;
  v_al record;
  v_l jsonb;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P5 de verdade', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    v_os := pg_temp.cena();
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    v_antes := (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada'));
    r := pg_temp.rodar();
    -- releio do banco, não da saída
    select a.* into v_al from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' limit 1;
    v_res := pg_temp.ok(v_res, 'P5a de verdade: em_teste falso, puxada; a alocação existe no banco: amanhã, à tarde, do Rafael, que já vinha',
      not (r ->> 'em_teste')::boolean and (r ->> 'puxadas')::int = 1 and v_al.dia = pg_temp.d() and v_al.turno = 'tarde' and v_al.payee_id = v_raf, coalesce(row_to_json(v_al)::text, 'sem alocação') || ' ' || r::text);
    v_res := pg_temp.ok(v_res, 'P5b nada foi cancelado no congelado: só somou 1 alocação', (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada')) = v_antes + 1
      and not exists (select 1 from public.agenda_alocacoes a where a.estado = 'cancelada' and a.cancelada_em = pg_temp.ag()), null);
    v_res := pg_temp.ok(v_res, 'P5c a ação ficou no registro, pela vigia (o aviso do gestor pega), com a proposta aplicada; o motivo da puxada, sem "urgente"',
      exists (select 1 from public.agenda_acoes a where a.service_order_id = v_os and a.executada and a.origem = 'vigia' and a.tipo in ('publicar', 'criar'))
      and exists (select 1 from public.agenda_propostas p where v_os = any (p.os_alvo) and p.criada_por = 'vigia' and p.estado in ('aplicada', 'aceita', 'parcial'))
      and v_al.motivos @> '["puxada para a folga que sobrou de amanhã"]'::jsonb and v_al.motivos::text !~ 'urgente', coalesce(v_al.motivos::text, '') || ' ' || (select coalesce(string_agg(a.tipo || '/' || a.origem, ','), '') from public.agenda_acoes a where a.service_order_id = v_os) || ' ' || (select coalesce(string_agg(p.estado, ','), '') from public.agenda_propostas p where v_os = any (p.os_alvo)));
    v_res := pg_temp.ok(v_res, 'P5d a ficha de amanhã alcança a pessoa: a rotina a tem no plano de D', v_raf in (select x from public._agenda_contatos_com_plano(pg_temp.d()) x), null);
    v_res := pg_temp.ok(v_res, 'P5k de verdade, sem simulação do gestor (agenda.gestor segue vazio)', coalesce(current_setting('agenda.gestor', true), '') = '', current_setting('agenda.gestor', true));
    v_res := pg_temp.ok(v_res, 'P5e de verdade não escreve o diário', not exists (select 1 from public.agenda_gestor_dia g where g.dia = pg_temp.pr() and g.sombra ? 'puxar'), null);
    v_res := pg_temp.ok(v_res, 'P5f a prontidão releida: a OS ficou fixada (amanhã está no congelado: o agenda_aplicar a fixa)', public.os_prontidao(v_os, pg_temp.pr()) ->> 'estado' = 'fixada', public.os_prontidao(v_os, pg_temp.pr()) ->> 'estado');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P5a sem exceção', false, sqlerrm);
  end;

  -- a reserva vira compromisso
  begin
    v_os := pg_temp.cena();
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    perform pg_temp.aloca(v_os, pg_temp.pessoa('Alex'), date '2027-02-15', 'manha', 'reserva');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P5g a OS com reserva vira compromisso em D', pg_temp.puxada(r, v_os)
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.dia = pg_temp.d() and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada')), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P5g sem exceção', false, sqlerrm);
  end;

  -- uma vez por dia, pela rodada inteira
  begin
    v_os := pg_temp.cena();
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    r := public.agenda_gestor_rodar(pg_temp.pr(), pg_temp.ag());
    select x.contagens into v_l from public.agenda_vigia_rodadas x where x.rotina = 'gestor' and x.p_agora = pg_temp.ag();
    v_res := pg_temp.ok(v_res, 'P5h o passo entra na rodada inteira do gestor (agenda_gestor_rodar, c_tique) e a contagem fica gravada', (v_l -> 'puxar' ->> 'rodou')::boolean and (v_l -> 'puxar' ->> 'puxadas')::int = 1, left(coalesce(v_l::text, ''), 500));
    r := public.agenda_gestor_rodar(pg_temp.pr(), pg_temp.ag('17:53'));
    select x.contagens into v_l from public.agenda_vigia_rodadas x where x.rotina = 'gestor' and x.p_agora = pg_temp.ag('17:53');
    v_res := pg_temp.ok(v_res, 'P5i o tique seguinte: já rodou, e a OS seguinte não é puxada', (v_l -> 'puxar' ->> 'ja_rodou')::boolean and (select count(*) from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') = 1, left(coalesce(v_l::text, ''), 300));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P5h sem exceção', false, sqlerrm);
  end;

  -- 2 OS de verdade, sem repetir a célula: a segunda vê a alocação da primeira
  begin
    v_os := pg_temp.cena();
    perform pg_temp.pronta(902);
    update public.agenda_config set modo_urgencia = 'ligado', puxar_max_os = 2 where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P5j de verdade, 2 por dia com uma célula: a 1ª entra e a 2ª não acha lugar em D (a grade é a de agora); nenhum choque',
      (r ->> 'puxadas')::int = 1 and (select count(*) from public.agenda_alocacoes a where a.payee_id = v_raf and a.dia = pg_temp.d() and a.turno = 'tarde' and a.estado in ('publicada', 'fixada')) = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P5j sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$p5$;

-- ── P6. O erro ──────────────────────────────────────────────────────────────────────────────────
do $p6$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  v_os uuid; v_b uuid;
  v_n int;
  v_st text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P6 o erro', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  -- o erro de uma OS não para a próxima
  begin
    v_os := pg_temp.cena();
    v_b := pg_temp.pronta(902);
    alter function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz) rename to agenda_propor_real_p4b;
    create function public.agenda_propor(p_escopo text, p_de date, p_ate date, p_os uuid[], p_restricoes jsonb, p_persistir boolean, p_origem text, p_autor uuid, p_hoje date, p_agora timestamptz)
      returns jsonb language plpgsql as $x$ begin
        if p_os[1] = md5('e7e:p:901')::uuid then raise exception 'a proposta saiu inválida' using errcode = 'P0001'; end if;
        return public.agenda_propor_real_p4b(p_escopo, p_de, p_ate, p_os, p_restricoes, p_persistir, p_origem, p_autor, p_hoje, p_agora);
      end $x$;
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P6a agenda_propor lança numa OS (R7.12-1): vai a app_error_logs (agenda, gestor:puxar), não lança, conta o erro e segue para a próxima OS',
      (r ->> 'rodou')::boolean and (r ->> 'erros')::int = 1 and pg_temp.fora(r, v_os) = 'erro' and pg_temp.puxada(r, v_b)
      and (select count(*) from public.app_error_logs where action = 'gestor:puxar' and message like '%OS-7EP901%') = 1 and (select count(*) from public.app_error_logs where action = 'gestor:puxar') = v_n + 1, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P6a sem exceção', false, sqlerrm);
  end;

  -- de verdade: não aplicou
  begin
    v_os := pg_temp.cena();
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    create or replace function public.agenda_aplicar(p_proposta uuid, p_os uuid[] default null, p_via text default 'motor', p_autor uuid default null, p_pergunta uuid default null,
                                                     p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
      returns jsonb language sql as $x$ select '{"ok": false, "texto": "não aplicou"}'::jsonb $x$;
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P6b a proposta que não aplica: não conta como puxada, vai a app_error_logs',
      (r ->> 'puxadas')::int = 0 and (r ->> 'erros')::int = 1 and pg_temp.fora(r, v_os) = 'nao_aplicou' and (select count(*) from public.app_error_logs where action = 'gestor:puxar') = v_n + 1, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P6b sem exceção', false, sqlerrm);
  end;

  -- o erro fora das OS
  begin
    v_os := pg_temp.cena();
    create or replace function public._agenda_modo_da_equipe() returns text language plpgsql stable as $x$ begin raise exception 'quebrou' using errcode = 'XX000'; end $x$;
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P6c o erro antes das OS: {rodou: true, erros: 1}, sem lançar, em app_error_logs', r = '{"rodou": true, "erros": 1}'::jsonb and (select count(*) from public.app_error_logs where action = 'gestor:puxar' and context = 'agenda') = v_n + 1, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P6c sem exceção', false, sqlerrm);
  end;

  -- o tempo estourado não é engolido: a rodada é quem cuida
  begin
    v_os := pg_temp.cena();
    create or replace function public._agenda_modo_da_equipe() returns text language plpgsql stable as $x$ begin raise exception 'canceling statement due to statement timeout' using errcode = '57014'; end $x$;
    begin
      r := pg_temp.rodar();
      v_st := 'nao lancou: ' || r::text;
    exception when query_canceled then v_st := 'query_canceled';
    end;
    v_res := pg_temp.ok(v_res, 'P6d o tempo estourado (query_canceled) passa adiante: a rodada grava parou_no', v_st = 'query_canceled', v_st);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P6d sem exceção', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$p6$;

-- ── P7. A OS na forma real (conferência do P4b) ───────────────────────────────────────────────────
-- A fixture do P1 a P6 cria a OS com dono_presenca 'nunca'; na carteira real, 0 de 10 são assim (8 "abre e fecha" pela regra 'padrão', 2 "sempre").
-- (1) a OS "abre e fecha": o motor dá a ponta do dono em D mesmo com ele fora das pessoas (só o turno fica sem capacidade), e o validador tem de aceitar;
-- (2) a OS que pede o dono o tempo todo: o dono com o dia declarado conta no "já vem" sem linha na rotina (ele não recebe ficha; em produção não tem a linha).
-- (3e) e (3g): depois da cena, o dono declara D (sem a rotina) e um 2º técnico (T2: da grade, com as duas células livres em D, nem o dono nem o Rafael) vem de manhã
-- na OS 900, com telefone e rotina: ele e o Rafael ficam só com a tarde livre (a montagem do bloco X da 3ª conferência)
create function pg_temp.tarde_so() returns uuid language plpgsql as $f$
declare
  v_t2 uuid;
  v_dono uuid := public._agenda_dono(null);
begin
  select g.payee_id into v_t2 from public.agenda_grade(pg_temp.d(), pg_temp.d(), pg_temp.pr()) g
   where not g.eh_dono and g.payee_id <> pg_temp.pessoa('Rafael') and g.livre group by g.payee_id having count(*) = 2 order by g.payee_id limit 1;
  update public.payees set phone = '5547900000998' where id = v_t2;
  if exists (select 1 from public.agenda_equipe_contato c where c.payee_id = v_t2) then
    update public.agenda_equipe_contato set recebe_rotina = true, parou_em = null, parou_motivo = null where payee_id = v_t2;
  else
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em) values (v_t2, true, 'dono', timestamptz '2027-01-01 10:00-03');
  end if;
  perform pg_temp.aloca(md5('e7e:p:900')::uuid, v_t2, pg_temp.d(), 'manha');
  delete from public.agenda_equipe_contato where payee_id = v_dono;
  insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
  values (v_dono, daterange(pg_temp.d(), pg_temp.d(), '[]'), 'disponivel', 'dono', 'teste 7e P4b', pg_temp.adm());
  return v_t2;
end $f$;
-- o que o passo em teste não pode deixar gravado: as contagens de pg_temp.conta() e a versão do plano (o gatilho da versão sobe a cada alocação vigente)
create function pg_temp.foto() returns text language sql stable as $f$ select pg_temp.conta() || '|v' || (select c.versao_plano from public.agenda_config c limit 1) $f$;
do $p7$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  r2 jsonb;
  v_os uuid;
  v_b uuid;
  v_c uuid;
  v_raf uuid := pg_temp.pessoa('Rafael');
  v_t2 uuid;
  v_dono uuid;
  v_n int;
  v_e0 text;
  v_e1 text;
  v_l jsonb;
  v_al text;
  v_k text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P7 a forma real', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  v_dono := public._agenda_dono(null);

  -- (1) em teste, pela rodada inteira das 17:37
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set dono_presenca = null where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'P7a0 a montagem: sem a presença dita, a OS fica "abre e fecha" pela regra; o dono, sem o dia declarado, tem só a ponta livre em D',
      public.os_prontidao(v_os, pg_temp.pr()) #>> '{presenca_dono,presenca}' = 'abre_e_fecha'
      and exists (select 1 from public.agenda_grade(pg_temp.d(), pg_temp.d(), pg_temp.pr()) g where g.payee_id = v_dono and g.turno = 'tarde' and g.curta_livre @> array['abertura'] and not g.livre),
      (public.os_prontidao(v_os, pg_temp.pr()) -> 'presenca_dono')::text);
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
    v_e0 := public.agenda_saude(pg_temp.pr(), pg_temp.ag('17:36')) #>> '{gestor,erros_24h}';
    perform public.agenda_gestor_rodar(pg_temp.pr(), pg_temp.ag());
    select x.contagens -> 'puxar' into v_l from public.agenda_vigia_rodadas x where x.rotina = 'gestor' and x.p_agora = pg_temp.ag();
    v_e1 := public.agenda_saude(pg_temp.pr(), pg_temp.ag('17:40')) #>> '{gestor,erros_24h}';
    v_res := pg_temp.ok(v_res, 'P7a a OS "abre e fecha", em teste, pela rodada das 17:37: puxada em D, sem erro (motor e validador concordam sobre a ponta do dono)',
      (v_l ->> 'em_teste')::boolean and (v_l ->> 'erros')::int = 0 and pg_temp.puxada(v_l, v_os), coalesce(v_l::text, 'sem a contagem'));
    v_res := pg_temp.ok(v_res, 'P7a2 nada em app_error_logs (gestor:puxar) e a saúde do gestor segue com 0 erro nas 24 h',
      (select count(*) from public.app_error_logs where action = 'gestor:puxar') = v_n and v_e1 = '0' and v_e0 = '0', v_n || ' erros antes; saúde ' || coalesce(v_e0, '?') || ' -> ' || coalesce(v_e1, '?'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7a sem exceção', false, sqlerrm);
  end;

  -- (1) de verdade: releio do banco
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set dono_presenca = null where service_order_id = v_os;
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
    perform public.agenda_gestor_rodar(pg_temp.pr(), pg_temp.ag());
    select x.contagens -> 'puxar' into v_l from public.agenda_vigia_rodadas x where x.rotina = 'gestor' and x.p_agora = pg_temp.ag();
    v_e1 := public.agenda_saude(pg_temp.pr(), pg_temp.ag('17:40')) #>> '{gestor,erros_24h}';
    select string_agg(concat_ws('/', a.dia, a.turno, case when a.payee_id = v_dono then 'dono' when a.payee_id = v_raf then 'rafael' else '?' end, a.presenca, a.estado), ',' order by a.dia, a.turno, a.presenca)
      into v_al from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada');
    v_res := pg_temp.ok(v_res, 'P7b de verdade: a OS "abre e fecha" puxada; no banco, o turno do Rafael em D à tarde e a ponta do dono em D',
      not (v_l ->> 'em_teste')::boolean and (v_l ->> 'puxadas')::int = 1 and (v_l ->> 'erros')::int = 0
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_raf and a.dia = pg_temp.d() and a.turno = 'tarde' and a.presenca = 'turno' and a.estado in ('publicada', 'fixada'))
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_dono and a.dia = pg_temp.d() and a.presenca in ('abertura', 'fechamento') and a.estado in ('publicada', 'fixada')),
      coalesce(v_al, 'sem alocação') || ' ' || coalesce(v_l::text, ''));
    v_res := pg_temp.ok(v_res, 'P7b2 de verdade, nada em app_error_logs (gestor:puxar) e a saúde do gestor com 0 erro',
      (select count(*) from public.app_error_logs where action = 'gestor:puxar') = v_n and v_e1 = '0', v_n || ' antes; saúde ' || coalesce(v_e1, '?'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7b sem exceção', false, sqlerrm);
  end;

  -- (2) a OS que pede o dono o tempo todo, com o dia de D declarado por ele e sem linha dele na rotina (como em produção)
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set dono_presenca = 'sempre' where service_order_id = v_os;
    delete from public.agenda_equipe_contato where payee_id = v_dono;
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_dono, daterange(pg_temp.d(), pg_temp.d(), '[]'), 'disponivel', 'dono', 'teste 7e P4b', pg_temp.adm());
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7c a OS "sempre" com o dono declarando D, sem a rotina dele: as 2 células do dono contam no "já vem" e a OS sai puxada em D',
      (r ->> 'celulas')::int = 3 and pg_temp.puxada(r, v_os) and (r ->> 'erros')::int = 0, r::text);
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    r := pg_temp.rodar();
    select string_agg(concat_ws('/', a.dia, a.turno, case when a.payee_id = v_dono then 'dono' when a.payee_id = v_raf then 'rafael' else '?' end, a.presenca, a.estado), ',' order by a.dia, a.turno, a.presenca)
      into v_al from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada');
    v_res := pg_temp.ok(v_res, 'P7d de verdade: no banco, o dono no turno da OS em D',
      (r ->> 'puxadas')::int = 1 and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_dono and a.dia = pg_temp.d() and a.presenca = 'turno' and a.estado in ('publicada', 'fixada')),
      coalesce(v_al, 'sem alocação') || ' ' || r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7c sem exceção', false, sqlerrm);
  end;

  -- (3) 2 por dia (2ª e 3ª conferências do P4b): em teste a 1ª OS não fica gravada; a simulação da 2ª a vê num bloco que se desfaz (o que a 1ª cancela sai, o que
  -- ela cria entra vigente), e assim não usa o meio-dia que a 1ª ocupou, nem pelo turno nem pela ponta do dono. Antes saía toda pessoa que a 1ª usou (o dono que
  -- declarou D saía pela ponta: 2ª conferência) e depois a conta era por célula (a 2ª caía no meio-dia que a ponta da 1ª já ocupava: 3ª conferência, o (3e)).
  -- Em cada montagem, o teste e o de verdade dizem o mesmo número. Nas de (3a) a (3c) a 2ª é um diagnóstico ("sempre" pela regra, e o dono o faz sozinho, como a
  -- OS#8 do replay da conferência); a "sempre" comum pede também um técnico (a regra uma_pessoa), e o Rafael não teria outra célula.
  -- (3a) a 1ª "abre e fecha" de 1 dia (o turno do Rafael em D à tarde, a abertura do dono em D, o fechamento depois de D), a 2ª o diagnóstico
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set dono_presenca = null, dias = 1 where service_order_id = v_os;
    v_b := pg_temp.pronta(902);
    update public.os_planejamento set dono_presenca = null where service_order_id = v_b;
    update public.service_orders set service_type = 'diagnosis' where id = v_b;
    delete from public.agenda_equipe_contato where payee_id = v_dono;
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_dono, daterange(pg_temp.d(), pg_temp.d(), '[]'), 'disponivel', 'dono', 'teste 7e P4b', pg_temp.adm());
    update public.agenda_config set puxar_max_os = 2 where id;
    v_res := pg_temp.ok(v_res, 'P7e0 a montagem: a 1ª "abre e fecha" e a 2ª "sempre" pela regra (diagnóstico)',
      public.os_prontidao(v_os, pg_temp.pr()) #>> '{presenca_dono,presenca}' = 'abre_e_fecha' and public.os_prontidao(v_b, pg_temp.pr()) #>> '{presenca_dono,presenca}' = 'sempre',
      (public.os_prontidao(v_b, pg_temp.pr()) -> 'presenca_dono')::text);
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7e em teste, 2 por dia, o dono com D declarado: a ponta dele na 1ª OS não o tira da 2ª (ele tem outra célula), 2 puxadas',
      (r ->> 'celulas')::int = 3 and (r ->> 'puxadas')::int = 2 and pg_temp.puxada(r, v_os) and pg_temp.puxada(r, v_b) and (r ->> 'erros')::int = 0, r::text);
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    r := pg_temp.rodar();
    select string_agg(concat_ws('/', case a.service_order_id when v_os then 'a' else 'b' end, a.dia, a.turno, case when a.payee_id = v_dono then 'dono' when a.payee_id = v_raf then 'rafael' else '?' end, a.presenca), ','
                      order by a.service_order_id = v_b, a.dia, a.turno, a.presenca)
      into v_al from public.agenda_alocacoes a where a.service_order_id in (v_os, v_b) and a.estado in ('publicada', 'fixada');
    v_res := pg_temp.ok(v_res, 'P7e2 de verdade, a mesma montagem: 2 puxadas; relido, em D o turno do Rafael e a abertura do dono na 1ª, o dono no turno da 2ª',
      (r ->> 'puxadas')::int = 2 and (r ->> 'erros')::int = 0
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_raf and a.dia = pg_temp.d() and a.presenca = 'turno' and a.estado in ('publicada', 'fixada'))
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_dono and a.dia = pg_temp.d() and a.presenca = 'abertura' and a.estado in ('publicada', 'fixada'))
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_dono and a.dia > pg_temp.d() and a.presenca = 'fechamento' and a.estado in ('publicada', 'fixada'))
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_b and a.payee_id = v_dono and a.dia = pg_temp.d() and a.presenca = 'turno' and a.estado in ('publicada', 'fixada')),
      coalesce(v_al, 'sem alocação') || ' ' || r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7e sem exceção', false, sqlerrm);
  end;

  -- (3b) a 1ª "abre e fecha" de meio dia: a abertura e o fechamento do dono no mesmo meio-dia de D gastam uma célula só
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set dono_presenca = null where service_order_id = v_os;
    v_b := pg_temp.pronta(902);
    update public.os_planejamento set dono_presenca = null where service_order_id = v_b;
    update public.service_orders set service_type = 'diagnosis' where id = v_b;
    delete from public.agenda_equipe_contato where payee_id = v_dono;
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_dono, daterange(pg_temp.d(), pg_temp.d(), '[]'), 'disponivel', 'dono', 'teste 7e P4b', pg_temp.adm());
    update public.agenda_config set puxar_max_os = 2 where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7f em teste, 2 por dia, a 1ª de meio dia: as duas pontas do dono no mesmo meio-dia de D são uma célula, e a 2ª sai puxada',
      (r ->> 'celulas')::int = 3 and (r ->> 'puxadas')::int = 2 and pg_temp.puxada(r, v_os) and pg_temp.puxada(r, v_b), r::text);
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    r := pg_temp.rodar();
    select string_agg(concat_ws('/', case a.service_order_id when v_os then 'a' else 'b' end, a.dia, a.turno, case when a.payee_id = v_dono then 'dono' when a.payee_id = v_raf then 'rafael' else '?' end, a.presenca), ','
                      order by a.service_order_id = v_b, a.dia, a.turno, a.presenca)
      into v_al from public.agenda_alocacoes a where a.service_order_id in (v_os, v_b) and a.estado in ('publicada', 'fixada');
    v_res := pg_temp.ok(v_res, 'P7f2 de verdade, a mesma montagem: 2 puxadas; relido, as duas pontas do dono na 1ª no mesmo meio-dia de D e o dono no turno da 2ª',
      (r ->> 'puxadas')::int = 2
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_dono and a.dia = pg_temp.d() and a.presenca in ('abertura', 'fechamento') and a.estado in ('publicada', 'fixada')) = 2
      and (select count(distinct a.turno) from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_dono and a.dia = pg_temp.d() and a.estado in ('publicada', 'fixada')) = 1
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_b and a.payee_id = v_dono and a.dia = pg_temp.d() and a.presenca = 'turno' and a.estado in ('publicada', 'fixada')),
      coalesce(v_al, 'sem alocação') || ' ' || r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7f sem exceção', false, sqlerrm);
  end;

  -- (3c) a guarda: o dono declara D, mas a manhã dele já tem turno marcado (na OS 900), e sobra só a tarde; a ponta dele na 1ª cai nessa tarde e a ocupa,
  -- então a 2ª não tem onde (de verdade, o motor não a põe em D). O teste não pode contar 2.
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set dono_presenca = null where service_order_id = v_os;
    v_b := pg_temp.pronta(902);
    update public.os_planejamento set dono_presenca = null where service_order_id = v_b;
    update public.service_orders set service_type = 'diagnosis' where id = v_b;
    delete from public.agenda_equipe_contato where payee_id = v_dono;
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_dono, daterange(pg_temp.d(), pg_temp.d(), '[]'), 'disponivel', 'dono', 'teste 7e P4b', pg_temp.adm());
    perform pg_temp.aloca(md5('e7e:p:900')::uuid, v_dono, pg_temp.d(), 'manha');
    update public.agenda_config set puxar_max_os = 2 where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7g em teste, a guarda: com só a tarde livre, a ponta do dono na 1ª OS gasta a célula dele, e a 2ª não conta (1 puxada, como de verdade)',
      (r ->> 'celulas')::int = 2 and (r ->> 'puxadas')::int = 1 and pg_temp.puxada(r, v_os) and not pg_temp.puxada(r, v_b), r::text);
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    r := pg_temp.rodar();
    select string_agg(concat_ws('/', case a.service_order_id when v_os then 'a' else 'b' end, a.dia, a.turno, case when a.payee_id = v_dono then 'dono' when a.payee_id = v_raf then 'rafael' else '?' end, a.presenca), ','
                      order by a.service_order_id = v_b, a.dia, a.turno, a.presenca)
      into v_al from public.agenda_alocacoes a where a.service_order_id in (v_os, v_b) and a.estado in ('publicada', 'fixada');
    v_res := pg_temp.ok(v_res, 'P7g2 de verdade, a mesma montagem: 1 puxada; relido, a ponta do dono da 1ª na tarde de D e nada da 2ª em D',
      (r ->> 'puxadas')::int = 1 and pg_temp.puxada(r, v_os) and not pg_temp.puxada(r, v_b)
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_dono and a.dia = pg_temp.d() and a.turno = 'tarde' and a.presenca in ('abertura', 'fechamento') and a.estado in ('publicada', 'fixada'))
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_b and a.dia = pg_temp.d() and a.estado in ('publicada', 'fixada')),
      coalesce(v_al, 'sem alocação') || ' ' || r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7g sem exceção', false, sqlerrm);
  end;

  -- (3d) a conta é de cada pessoa: o dono com D declarado (2 células, o 1º da grade) não segura na lista o Rafael, que gastou a dele na 1ª. As duas OS são só da
  -- equipe ('nunca', a fixture), então a 2ª não tem quem a faça em D.
  begin
    v_os := pg_temp.cena();
    v_b := pg_temp.pronta(902);
    delete from public.agenda_equipe_contato where payee_id = v_dono;
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_dono, daterange(pg_temp.d(), pg_temp.d(), '[]'), 'disponivel', 'dono', 'teste 7e P4b', pg_temp.adm());
    update public.agenda_config set puxar_max_os = 2 where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7h em teste, cada pessoa por si: o Rafael gastou a célula dele na 1ª (a simulação da 2ª a vê ocupada), mesmo com o dono ainda com 2; a 2ª (só da equipe) não conta',
      (r ->> 'celulas')::int = 3 and (r ->> 'puxadas')::int = 1 and pg_temp.puxada(r, v_os) and not pg_temp.puxada(r, v_b), r::text);
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7h2 de verdade, a mesma montagem: 1 puxada; relido, nada da 2ª em D',
      (r ->> 'puxadas')::int = 1 and pg_temp.puxada(r, v_os) and not pg_temp.puxada(r, v_b)
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_b and a.dia = pg_temp.d() and a.estado in ('publicada', 'fixada')),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7h sem exceção', false, sqlerrm);
  end;

  -- (3e) a colisão de meio-dia (3ª conferência, o bloco X dela): o dono declara D (2 células); o Rafael e o T2 só com a tarde. A 1ª ("abre e fecha", meio dia)
  -- cai na tarde: o turno de um técnico e as duas pontas do dono. A 2ª ("sempre" dita) pede o dono no turno e um técnico no mesmo meio-dia: a tarde do dono já
  -- está ocupada pela ponta e de manhã não há técnico. De verdade ela fica sem compromisso; com a conta por célula, o dono ainda "tinha" a manhã e o teste contava 2.
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set dono_presenca = null, prioridade_manual = 1 where service_order_id = v_os;
    v_b := pg_temp.pronta(902);
    update public.os_planejamento set dono_presenca = 'sempre', prioridade_manual = 2 where service_order_id = v_b;
    v_t2 := pg_temp.tarde_so();
    update public.agenda_config set puxar_max_os = 2 where id;
    select string_agg(concat_ws('/', case when g.payee_id = v_dono then 'dono' when g.payee_id = v_raf then 'rafael' when g.payee_id = v_t2 then 't2' else '?' end,
                                g.turno, case when g.livre then 'livre' else 'ocupado' end), ' ' order by g.eh_dono desc, g.payee_id, g.turno)
      into v_al from public.agenda_grade(pg_temp.d(), pg_temp.d(), pg_temp.pr()) g where g.payee_id in (v_dono, v_raf, v_t2);
    v_res := pg_temp.ok(v_res, 'P7i0 a montagem: a 1ª "abre e fecha" e a 2ª "sempre" (dita), as duas prontas; em D o dono livre nos 2 meios-dias, o Rafael e o T2 só à tarde',
      v_t2 is not null and public.os_prontidao(v_os, pg_temp.pr()) #>> '{presenca_dono,presenca}' = 'abre_e_fecha' and public.os_prontidao(v_b, pg_temp.pr()) #>> '{presenca_dono,presenca}' = 'sempre'
      and public.os_prontidao(v_os, pg_temp.pr()) ->> 'estado' = 'pronta' and public.os_prontidao(v_b, pg_temp.pr()) ->> 'estado' = 'pronta'
      and v_al = 'dono/manha/livre dono/tarde/livre ' || case when v_raf < v_t2 then 'rafael/manha/ocupado rafael/tarde/livre t2/manha/ocupado t2/tarde/livre' else 't2/manha/ocupado t2/tarde/livre rafael/manha/ocupado rafael/tarde/livre' end,
      coalesce(v_al, 'sem grade'));
    v_k := pg_temp.foto();
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7i em teste, a 2ª cairia no meio-dia que a ponta do dono ocupou na 1ª: a simulação dela vê a 1ª e não a põe em D (1 puxada, a 2ª sem compromisso)',
      (r ->> 'celulas')::int = 4 and (r ->> 'puxadas')::int = 1 and pg_temp.puxada(r, v_os) and pg_temp.fora(r, v_b) = 'sem_compromisso' and (r ->> 'erros')::int = 0, r::text);
    v_res := pg_temp.ok(v_res, 'P7i2 em teste nada fica gravado do bloco que a 2ª simulação usou: as contagens e a versão do plano iguais, nada em app_error_logs',
      pg_temp.foto() = v_k and (select count(*) from public.app_error_logs where action = 'gestor:puxar') = v_n, v_k || ' -> ' || pg_temp.foto());
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    r2 := pg_temp.rodar();
    select string_agg(concat_ws('/', case a.service_order_id when v_os then 'a' else 'b' end, a.dia, a.turno,
                                case when a.payee_id = v_dono then 'dono' when a.payee_id = v_raf then 'rafael' when a.payee_id = v_t2 then 't2' else '?' end, a.presenca), ','
                      order by a.service_order_id = v_b, a.dia, a.turno, a.presenca)
      into v_al from public.agenda_alocacoes a where a.service_order_id in (v_os, v_b) and a.estado in ('publicada', 'fixada');
    v_res := pg_temp.ok(v_res, 'P7i3 de verdade, a mesma montagem: 1 puxada, a 2ª sem compromisso; relido, a 1ª na tarde de D (um técnico e as pontas do dono) e nada da 2ª',
      (r2 ->> 'puxadas')::int = 1 and pg_temp.puxada(r2, v_os) and pg_temp.fora(r2, v_b) = 'sem_compromisso' and (r2 ->> 'erros')::int = 0
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_dono and a.dia = pg_temp.d() and a.turno = 'tarde' and a.presenca in ('abertura', 'fechamento') and a.estado in ('publicada', 'fixada')) = 2
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id in (v_raf, v_t2) and a.dia = pg_temp.d() and a.turno = 'tarde' and a.presenca = 'turno' and a.estado in ('publicada', 'fixada'))
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_b and a.estado in ('publicada', 'fixada')),
      coalesce(v_al, 'sem alocação') || ' ' || r2::text);
    v_res := pg_temp.ok(v_res, 'P7i4 o teste diz o mesmo que o de verdade: o número e o resultado de cada OS',
      r ->> 'puxadas' = r2 ->> 'puxadas' and pg_temp.fora(r, v_os) = pg_temp.fora(r2, v_os) and pg_temp.fora(r, v_b) = pg_temp.fora(r2, v_b),
      'teste ' || (r ->> 'puxadas') || ' (' || pg_temp.fora(r, v_os) || ', ' || pg_temp.fora(r, v_b) || '), de verdade ' || (r2 ->> 'puxadas') || ' (' || pg_temp.fora(r2, v_os) || ', ' || pg_temp.fora(r2, v_b) || ')');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7i sem exceção', false, sqlerrm);
  end;

  -- (3f) a 1ª tem uma reserva do Rafael em D+1 de manhã, e o compromisso dela (1 dia: D à tarde e D+1 de manhã) a promove. No bloco desfeito sai a reserva e entra o
  -- compromisso, como o agenda_aplicar faz; sem tirar a reserva, o compromisso bateria nela (ninguém em dois lugares) e a 2ª daria erro em teste.
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set dias = 1 where service_order_id = v_os;
    perform pg_temp.aloca(v_os, v_raf, pg_temp.d() + 1, 'manha', 'reserva');
    v_b := pg_temp.pronta(902);
    update public.agenda_config set puxar_max_os = 2 where id;
    v_k := pg_temp.foto();
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7j em teste, a 1ª com reserva que vira compromisso: a 2ª é simulada sem erro e fica fora de D, como de verdade; nada gravado',
      (r ->> 'puxadas')::int = 1 and pg_temp.puxada(r, v_os) and pg_temp.fora(r, v_b) = 'nao_coube_amanha' and (r ->> 'erros')::int = 0
      and (select count(*) from public.app_error_logs where action = 'gestor:puxar') = v_n and pg_temp.foto() = v_k, r::text || ' ' || v_k || ' -> ' || pg_temp.foto());
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    r2 := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7j2 de verdade, a mesma montagem: 1 puxada, a 2ª fora de D; relido, a reserva da 1ª cancelada (promovida) e o compromisso dela no lugar, e o teste disse o mesmo',
      (r2 ->> 'puxadas')::int = 1 and pg_temp.puxada(r2, v_os) and pg_temp.fora(r2, v_b) = 'nao_coube_amanha' and (r2 ->> 'erros')::int = 0
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.tipo = 'reserva' and a.estado = 'cancelada' and a.cancelada_motivo = 'promovida')
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.payee_id = v_raf and a.dia = pg_temp.d() + 1 and a.turno = 'manha' and a.tipo <> 'reserva' and a.estado in ('publicada', 'fixada'))
      and r ->> 'puxadas' = r2 ->> 'puxadas' and pg_temp.fora(r, v_b) = pg_temp.fora(r2, v_b),
      r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7j sem exceção', false, sqlerrm);
  end;

  -- (3g) 3 por dia, e a 1ª de mais de meio dia ("abre e fecha", 1,5 dia: D à tarde e D+1 inteiro), na montagem do (3e). A 2ª ('nunca', meio dia) cabe na tarde do
  -- outro técnico. A 3ª ("sempre" dita) pede o dono e um técnico juntos: a tarde do dono é a ponta da 1ª, e de manhã não há técnico. A simulação da 3ª tem de ver
  -- as duas de antes (a 1ª e a 2ª), não só a última.
  begin
    v_os := pg_temp.cena();
    update public.os_planejamento set dono_presenca = null, prioridade_manual = 1, dias = 1.5 where service_order_id = v_os;
    v_b := pg_temp.pronta(902);
    update public.os_planejamento set prioridade_manual = 2 where service_order_id = v_b;
    v_c := pg_temp.pronta(903);
    update public.os_planejamento set dono_presenca = 'sempre', prioridade_manual = 3 where service_order_id = v_c;
    v_t2 := pg_temp.tarde_so();
    update public.agenda_config set puxar_max_os = 3 where id;
    v_k := pg_temp.foto();
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7k em teste, 3 por dia com a 1ª de 1,5 dia: a 1ª e a 2ª puxadas, a 3ª sem compromisso (ela vê a ponta do dono da 1ª); nada gravado',
      (r ->> 'celulas')::int = 4 and (r ->> 'puxadas')::int = 2 and pg_temp.puxada(r, v_os) and pg_temp.puxada(r, v_b) and pg_temp.fora(r, v_c) = 'sem_compromisso'
      and (r ->> 'erros')::int = 0 and pg_temp.foto() = v_k, r::text);
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    r2 := pg_temp.rodar();
    select string_agg(concat_ws('/', case a.service_order_id when v_os then 'a' when v_b then 'b' else 'c' end, a.dia, a.turno,
                                case when a.payee_id = v_dono then 'dono' when a.payee_id = v_raf then 'rafael' when a.payee_id = v_t2 then 't2' else '?' end, a.presenca), ','
                      order by a.service_order_id = v_c, a.service_order_id = v_b, a.dia, a.turno, a.presenca)
      into v_al from public.agenda_alocacoes a where a.service_order_id in (v_os, v_b, v_c) and a.estado in ('publicada', 'fixada');
    v_res := pg_temp.ok(v_res, 'P7k2 de verdade, a mesma montagem: as mesmas 2 puxadas e a 3ª sem compromisso; relido, a 1ª em D e em D+1, a 2ª na tarde de D, nada da 3ª',
      (r2 ->> 'puxadas')::int = 2 and pg_temp.puxada(r2, v_os) and pg_temp.puxada(r2, v_b) and pg_temp.fora(r2, v_c) = 'sem_compromisso'
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.dia = pg_temp.d() + 1 and a.presenca = 'turno' and a.estado in ('publicada', 'fixada'))
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_b and a.dia = pg_temp.d() and a.turno = 'tarde' and a.estado in ('publicada', 'fixada'))
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_c and a.estado in ('publicada', 'fixada'))
      and r ->> 'puxadas' = r2 ->> 'puxadas' and pg_temp.fora(r, v_c) = pg_temp.fora(r2, v_c),
      coalesce(v_al, 'sem alocação') || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7k sem exceção', false, sqlerrm);
  end;

  -- (3h) a 1ª tem uma reserva do Rafael em D+1 de manhã que está fixada pelo congelamento, e o Rafael fica indisponível em D+1: a simulação da 1ª
  -- cancela a reserva (violada), e o agenda_aplicar a tira com a chave do fixado. O bloco desfeito tem de tirar do mesmo jeito; sem a chave, o gatilho recusava
  -- ("Esse meio-dia está fixado") e a 2ª dava erro em teste, com uma linha em app_error_logs, onde o de verdade não dá erro (retomada da 3ª correção).
  -- A mesma reserva fixada pelo dono deixa o compromisso da 1ª crítico (fixada_pelo_dono): é o tudo ou nada do P4c, no P8.
  foreach v_k in array array['congelamento'] loop
  begin
    v_os := pg_temp.cena();
    perform pg_temp.aloca(v_os, v_raf, pg_temp.d() + 1, 'manha', 'reserva');
    update public.agenda_alocacoes set estado = 'fixada', fixado_por = v_k where service_order_id = v_os and tipo = 'reserva';
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_raf, daterange(pg_temp.d() + 1, pg_temp.d() + 1, '[]'), 'indisponivel', 'dono', 'teste 7e P4b', pg_temp.adm());
    v_b := pg_temp.pronta(902);
    update public.agenda_config set puxar_max_os = 2 where id;
    v_e0 := pg_temp.foto();
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7l em teste, a 1ª com a reserva fixada (' || v_k || ') que viola: a 1ª puxada e a 2ª simulada sem erro; nada gravado, nada em app_error_logs, a chave do fixado não sobra',
      pg_temp.puxada(r, v_os) and (r ->> 'erros')::int = 0 and pg_temp.fora(r, v_b) <> 'erro'
      and (select count(*) from public.app_error_logs where action = 'gestor:puxar') = v_n and pg_temp.foto() = v_e0
      and current_setting('agenda.mexe_fixado', true) is distinct from 'on',
      r::text || ' ' || v_e0 || ' -> ' || pg_temp.foto() || ' chave=' || coalesce(current_setting('agenda.mexe_fixado', true), 'nula'));
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    r2 := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, 'P7l2 de verdade, a mesma montagem (' || v_k || '): sem erro, a reserva fixada da 1ª cancelada, e o teste disse o mesmo (o número e o resultado de cada OS)',
      (r2 ->> 'erros')::int = 0
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.tipo = 'reserva' and a.fixado_por = v_k and a.estado = 'cancelada')
      and r ->> 'puxadas' = r2 ->> 'puxadas' and pg_temp.fora(r, v_os) = pg_temp.fora(r2, v_os) and pg_temp.fora(r, v_b) = pg_temp.fora(r2, v_b),
      'teste ' || (r ->> 'puxadas') || ' (' || pg_temp.fora(r, v_os) || ', ' || pg_temp.fora(r, v_b) || '), de verdade ' || (r2 ->> 'puxadas') || ' (' || pg_temp.fora(r2, v_os) || ', ' || pg_temp.fora(r2, v_b) || ') ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P7l sem exceção (' || v_k || ')', false, sqlerrm);
  end;
  end loop;
  perform pg_temp.gravar(v_res);
end
$p7$;

-- ── P8. Tudo ou nada por OS (P4c) ───────────────────────────────────────────────────────────────
-- O agenda_aplicar sem pergunta só leva os itens não críticos (_agenda_itens_escolhidos). Quando a proposta da OS puxada trazia item crítico (o que pede a decisão do
-- dono), de verdade ela contava como puxada sem compromisso, e o cancelar que viesse junto tirava o que ela tinha (a sonda Y2 da retomada da 3ª correção do P4b).
-- Agora ela fica fora com pede_decisao, em teste e de verdade, com as vigentes que tinha (os mesmos ids e estados), sem proposta nem pergunta, e a seguinte da fila
-- é tentada (como depois de qualquer OS fora). A mesma OS sem o item crítico continua puxada. As vigentes de uma OS, para comparar: id, estado e tipo.
create function pg_temp.vig(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(a.id::text || ':' || a.estado || ':' || a.tipo, ',' order by a.id), '-') from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')
$f$;
do $p8$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  r2 jsonb;
  p jsonb;
  v_os uuid;
  v_b uuid;
  v_raf uuid := pg_temp.pessoa('Rafael');
  v_n int;
  v_q int;
  v_e0 text;
  v_s0 text;
  v_max int;
  v_k text;
  v_e1 text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P8 tudo ou nada', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;

  -- (1) A (901) com uma reserva do Rafael em D+1 de manhã, fixada pelo dono, e o Rafael indisponível em D+1: a reserva viola, a simulação a cancela, e o compromisso
  -- de A na tarde de D sai crítico (fixada_pelo_dono). B (902) é a seguinte da fila. Com máximo 2 e com o padrão (1): antes, com 1, B nem era tentada.
  foreach v_max in array array[2, 1] loop
  begin
    v_os := pg_temp.cena();
    perform pg_temp.aloca(v_os, v_raf, pg_temp.d() + 1, 'manha', 'reserva');
    update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'dono' where service_order_id = v_os and tipo = 'reserva';
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_raf, daterange(pg_temp.d() + 1, pg_temp.d() + 1, '[]'), 'indisponivel', 'dono', 'teste 7e P4c', pg_temp.adm());
    v_b := pg_temp.pronta(902);
    update public.agenda_config set puxar_max_os = v_max where id;
    if v_max = 2 then
      perform set_config('agenda.gestor', 'sombra', true);
      p := public.agenda_propor('os', pg_temp.d(), null, array[v_os],
                                jsonb_build_object('puxar', jsonb_build_object('dia', pg_temp.d(), 'pessoas', jsonb_build_array(v_raf), 'os', v_os), 'acima_da_carga', true),
                                false, 'vigia', null, pg_temp.pr(), pg_temp.ag());
      perform set_config('agenda.gestor', '', true);
      v_res := pg_temp.ok(v_res, 'P8a0 a montagem: a simulação de A cancela a reserva fixada pelo dono (violada, não crítico) e o compromisso de A sai crítico (fixada_pelo_dono)',
        exists (select 1 from jsonb_array_elements(p -> 'itens') i where i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' and i ->> 'critica' = 'fixada_pelo_dono')
        and exists (select 1 from jsonb_array_elements(p -> 'itens') i where i ->> 'op' = 'cancelar' and i ->> 'critica' is null),
        (select string_agg(concat_ws('/', i ->> 'op', i ->> 'tipo', coalesce(i ->> 'critica', '-')), ' ') from jsonb_array_elements(p -> 'itens') i));
    end if;
    v_s0 := pg_temp.vig(v_os);
    v_e0 := pg_temp.foto();
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:puxar');
    r := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, format('P8a em teste, máximo %s: A fora com pede_decisao e B puxada em D; nada gravado, nada em app_error_logs', v_max),
      pg_temp.fora(r, v_os) = 'pede_decisao' and pg_temp.puxada(r, v_b) and (r ->> 'puxadas')::int = 1 and (r ->> 'erros')::int = 0
      and pg_temp.foto() = v_e0 and (select count(*) from public.app_error_logs where action = 'gestor:puxar') = v_n,
      r::text || ' ' || v_e0 || ' -> ' || pg_temp.foto());
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    v_q := (select count(*) from public.agenda_perguntas);
    r2 := pg_temp.rodar();
    v_res := pg_temp.ok(v_res, format('P8a2 de verdade, máximo %s, relido: A fora com pede_decisao e com as vigentes que tinha (a reserva fixada pelo dono), sem proposta nem pergunta; B puxada, com compromisso em D; o teste disse o mesmo', v_max),
      pg_temp.fora(r2, v_os) = 'pede_decisao' and pg_temp.vig(v_os) = v_s0
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.tipo = 'reserva' and a.estado = 'fixada' and a.fixado_por = 'dono')
      and not exists (select 1 from public.agenda_propostas pr where v_os = any (pr.os_alvo))
      and (select count(*) from public.agenda_perguntas) = v_q
      and pg_temp.puxada(r2, v_b)
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_b and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = pg_temp.d())
      and (r2 ->> 'erros')::int = 0 and r ->> 'puxadas' = r2 ->> 'puxadas' and pg_temp.fora(r, v_os) = pg_temp.fora(r2, v_os) and pg_temp.fora(r, v_b) = pg_temp.fora(r2, v_b),
      'A ' || pg_temp.fora(r2, v_os) || ' ' || v_s0 || ' -> ' || pg_temp.vig(v_os) || '; B ' || pg_temp.fora(r2, v_b) || '; perguntas ' || v_q || ' -> '
      || (select count(*) from public.agenda_perguntas) || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, format('P8a sem exceção (máximo %s)', v_max), false, sqlerrm);
  end;
  end loop;

  -- (2) A sozinha na fila (sem B), com a mesma reserva fixada pelo dono que viola: antes, de verdade, A contava como puxada, a reserva saía, nada entrava,
  -- e a proposta gravada abria a pergunta ao dono. Agora nada é gravado: as contagens e a versão do plano ficam como estavam.
  -- E a guarda (3): a mesma reserva publicada (não fixada) que viola não deixa nada crítico, e A continua puxada nos dois modos (a reserva sai e o compromisso entra).
  foreach v_k in array array['dono', 'publicada'] loop
  begin
    v_os := pg_temp.cena();
    perform pg_temp.aloca(v_os, v_raf, pg_temp.d() + 1, 'manha', 'reserva');
    if v_k = 'dono' then
      update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'dono' where service_order_id = v_os and tipo = 'reserva';
    end if;
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_raf, daterange(pg_temp.d() + 1, pg_temp.d() + 1, '[]'), 'indisponivel', 'dono', 'teste 7e P4c', pg_temp.adm());
    v_s0 := pg_temp.vig(v_os);
    v_e0 := pg_temp.foto();
    r := pg_temp.rodar();
    update public.agenda_config set modo_urgencia = 'ligado' where id;
    v_e1 := pg_temp.foto();
    r2 := pg_temp.rodar();
    if v_k = 'dono' then
      v_res := pg_temp.ok(v_res, 'P8b em teste, A sozinha com a reserva fixada pelo dono que viola: fora com pede_decisao, nada gravado',
        pg_temp.fora(r, v_os) = 'pede_decisao' and (r ->> 'puxadas')::int = 0 and (r ->> 'erros')::int = 0 and v_e1 = v_e0, r::text || ' ' || v_e0 || ' -> ' || v_e1);
      v_res := pg_temp.ok(v_res, 'P8b2 de verdade, relido: A fora com pede_decisao, com a reserva que tinha; nada gravado (propostas, ações, alocações, perguntas, mensagens, versão do plano); o teste disse o mesmo',
        pg_temp.fora(r2, v_os) = 'pede_decisao' and (r2 ->> 'puxadas')::int = 0 and (r2 ->> 'erros')::int = 0 and pg_temp.foto() = v_e1 and pg_temp.vig(v_os) = v_s0
        and r ->> 'puxadas' = r2 ->> 'puxadas' and pg_temp.fora(r, v_os) = pg_temp.fora(r2, v_os),
        r2::text || ' ' || v_e1 || ' -> ' || pg_temp.foto() || '; vigentes de A ' || v_s0 || ' -> ' || pg_temp.vig(v_os));
    else
      v_res := pg_temp.ok(v_res, 'P8c a guarda, A com a reserva publicada que viola: nada crítico, puxada em D em teste e de verdade; relido, a reserva saiu e o compromisso entrou',
        pg_temp.puxada(r, v_os) and pg_temp.puxada(r2, v_os)
        and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = pg_temp.d())
        and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva'),
        r::text || ' | ' || r2::text || ' | vigentes de A ' || v_s0 || ' -> ' || pg_temp.vig(v_os));
    end if;
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  when others then v_res := pg_temp.ok(v_res, 'P8b sem exceção (' || v_k || ')', false, sqlerrm);
  end;
  end loop;
  perform pg_temp.gravar(v_res);
end
$p8$;

select * from _resultado order by teste;
rollback;
