-- Prova do encaixe na aprovação, da onda e da zona travada, Fase 7a (pacote P8, migration 20261031100700), sobre a carteira REAL de
-- 29/10 (o replay) e a sintética da 7a (Wagner, Xavier e Yara com o João em ter 03/11 e qua 04/11, a ficha do João de ter 03/11
-- enfileirada, a Úrsula com o prometido firme). O cenário C do replay (o prazo vence e o encaixe do mesmo tique) está em
-- agenda_fase7a_replay.sql.
-- bancada: depende de 20261031100700
--
--   E0 as portas e o que é (sem fixture): a conta da zona e a da onda só do service_role; a pergunta da onda (definer) e o passo do
--      encaixe (invoker) para ninguém; as 5 recriadas com as portas de antes
--   E1 as candidatas do encaixe: a conversão (o agrupar, sem status_change), a assinatura, o status_change, o planejamento e o
--      material mudados; fora a já tentada pela vigia, a de antes da marca d'água e a que já tem dia; a marca d'água do encaixe que
--      rodou; desligado = pulado
--   E2 ligado marca (o Lenine com a reserva promovida, o Vanderlei; o Giancarlo, de fora, ganha a pergunta do gestor) e a contagem
--      por OS ("da aprovação ao 1º dia"); em teste, o mesmo motor sem gravar nada: só o diário (sombra.encaixe), sem apagar o resto
--   E3 a onda: 3 OS com dia mudado = nada aplicado, a proposta aberta e a pergunta crítica (o texto da §6.3, a chave da versão, uma
--      só); 2 OS não; a troca de pessoa no mesmo meio-dia, a reserva promovida e a OS nova não contam (a conta); a OS que já é
--      pergunta crítica fica fora da conta; sem a regra, aplica
--   E4 a zona travada: na regra (_agenda_criticidade: o dia avisado à equipe, o dia que o cliente ouviu, o fim que passa do
--      prometido firme; o que ficou impossível não conta; _agenda_zona_fora), no motor (a Úrsula: dia_prometido com a recomendação do
--      P3) e na saúde (_agenda_criticidade_da_acao: a ação que tirou o dia avisado conta em dia_avisado_sem_pergunta)
--   E5 a decisão da onda: 1 refaz a conta e aplica tudo (ações críticas, com a pergunta); 2 só o de hoje e amanhã; 3 descarta e o
--      "não mudo nada" vale até a agenda mudar; a agenda mudou desde a pergunta = resolve
--   E6 as cópias: as 5 recriadas sem os blocos "-- FASE 7: (7a P8" são o corpo da origem; com o portão falso, _agenda_criticidade e o
--      motor dão o de antes, byte a byte
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_encaixe.sql
--   Seguro em produção: E0 e E6 (as cópias saem PULADO sem as migrations como texto) só leem; E1 a E5 usam as fixtures e só rodam
--   na bancada (fora dela saem PULADO). Termina em ROLLBACK.
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
-- A OS pelo número (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
-- Os modos do gestor (os 5) e as regras.
create function pg_temp.modos(p_modo text, p_regras text[] default null) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         marcar_regras = coalesce(p_regras, '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}')
   where id
$f$;
-- O plano (md5 do vigente e do cancelado; a alocação de proposta não é plano): o que nada pode ter mudado.
create function pg_temp.plano() returns text language sql stable as $f$
  select md5(coalesce(string_agg(a.id::text || a.estado, ',' order by a.id), '')) from public.agenda_alocacoes a
   where a.estado in ('publicada', 'fixada', 'cancelada')
$f$;
-- O dia de compromisso de cada OS, "OS-00074:2026-11-03", em ordem.
create function pg_temp.dias(p_numeros text[]) returns text language sql stable as $f$
  select string_agg(n || ':' || coalesce((select min(a.dia)::text from public.agenda_alocacoes a
                                           where a.service_order_id = pg_temp.os(n) and a.estado in ('publicada', 'fixada')
                                             and a.tipo <> 'reserva' and a.presenca = 'turno'), '-'), ' ' order by n)
    from unnest(p_numeros) n
$f$;
-- A função inteira e o corpo, a partir do texto da migration.
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
-- O corpo sem os blocos deste pacote ("-- FASE 7: (7a P8 … -- FASE 7: fim"; os das etapas de antes ficam) e dos pacotes que
-- recriam depois a mesma função (7a P9: _agenda_gestor_decidir, com o reestimar e o reavaliar).
create function pg_temp.sem_p8(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 7: \(7a P(8|9)' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 7: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;

-- ── E0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura, quem, definer, vol) as (values
  ('public._agenda_zona_fora(jsonb, uuid, jsonb)', 'servico', false, 'i'),
  ('public._agenda_gestor_onda_conta(jsonb)', 'servico', false, 's'),
  ('public._agenda_gestor_onda(uuid, date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_gestor_encaixe(date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_criticidade(uuid, date, date, date, date, date, uuid[], uuid[])', 'leitura', false, 's'),
  ('public._agenda_criticidade_da_acao(uuid)', 'leitura', false, 's'),
  ('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'servico', true, 'v'),
  ('public._agenda_propor_e_aplicar(text, uuid[], text, uuid, date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'ninguem', true, 'v'))
insert into _resultado
select 'E0a as portas: a conta da zona e a da onda só do service_role; a pergunta da onda (definer) e o encaixe para ninguém; as 5 recriadas como eram (as duas criticidades para authenticated e service_role; o motor só service_role; propor-e-aplicar e o despacho para ninguém); nunca anon; volatilidade e definer como devem; search_path fixo',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and has_function_privilege('authenticated', f.assinatura, 'execute') = (f.quem = 'leitura')
                and has_function_privilege('service_role', f.assinatura, 'execute') = (f.quem in ('leitura', 'servico'))
                and p.prosecdef = f.definer and p.provolatile::text = f.vol
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute') <> (f.quem = 'leitura')
                                              or has_function_privilege('service_role', f.assinatura, 'execute') <> (f.quem in ('leitura', 'servico'))
                                              or p.prosecdef <> f.definer or p.provolatile::text <> f.vol)
  from f join pg_proc p on p.oid = f.assinatura::regprocedure;

-- ── E1 a E5: com as fixtures (o replay de 29/10 e a sintética, por cima) ──────────────────────────────────
do $fx$
declare
  v_res    jsonb := '[]'::jsonb;
  c_hoje   constant date := date '2026-10-29';
  c_agora  constant timestamptz := timestamptz '2026-10-29 16:52-03';
  c_sex    constant date := date '2026-10-30';
  c_sexa   constant timestamptz := timestamptz '2026-10-30 10:07-03';
  c_onda   constant text := 'Mudou muita coisa de uma vez (João não vem): eu mudaria 3 serviços (Wagner, Xavier e Yara) e 1 dia que a equipe já sabia. Não fiz nada ainda. 1) Faço tudo como montei (recomendo; *agenda plano* mostra); 2) Mudo só o de hoje e amanhã; 3) Não mudo nada: você me diz.';
  v_tres   uuid[];
  v_adm    uuid;
  v_joao   uuid;
  v_rob    uuid;
  v_w      uuid;
  v_alw    uuid;
  v_nova   uuid;
  v_acao   uuid;
  v_q      uuid;
  v_q2     uuid;
  v_pl0    text;
  v_v0     bigint;
  v_n      int;
  v_n2     int;
  v_t      text;
  v_t2     text;
  v_b      boolean;
  v_b2     boolean;
  r        jsonb;
  r2       jsonb;
  d        jsonb;
  x        record;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('E1 a E5 (as fixtures da 7a)', true,
      'PULADO: sem agenda_teste.replay2910 e agenda_teste.fase7a (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.replay2910');
  execute current_setting('agenda_teste.fase7a');
  -- a presença do dono do Lenine e do Vanderlei como em produção (abre e fecha; o replay dá "sempre": notas do P2)
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select pg_temp.os(n), 'abre_e_fecha' from unnest(array['OS-00074', 'OS-00069']) n
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
  select id into v_joao from public.payees where name = 'João' and active;
  select id into v_rob from public.payees where name = 'Roberto' and active;
  v_tres := array[pg_temp.os('OS-97006'), pg_temp.os('OS-97007'), pg_temp.os('OS-97008')];
  v_w := pg_temp.os('OS-97006');
  v_alw := (select a.id from public.agenda_alocacoes a where a.service_order_id = v_w and a.estado = 'publicada');

  -- ── E1. As candidatas ─────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado');
    update public.agenda_config set modo_encaixe_aprovacao = 'desligado' where id;
    r := public._agenda_gestor_encaixe(c_hoje, c_agora);
    v_b := (r ->> 'pulado')::boolean and r ->> 'motivo' = 'desligado';
    update public.agenda_config set modo_encaixe_aprovacao = 'sombra' where id;
    -- o que é novo desde a marca d'água (sem encaixe antes: um dia antes, ter 28/10 16:47)
    insert into public.ai_lifecycle_events (entity_type, entity_id, entity_number, event_type, old_value, new_value, created_at) values
      ('service_order', pg_temp.os('OS-00096'), 'OS-00096', 'status_change', 'draft', 'approved', timestamptz '2026-10-29 10:00-03'),
      ('service_order', pg_temp.os('OS-00032'), 'OS-00032', 'status_change', 'awaiting_client', 'open', timestamptz '2026-10-29 15:00-03'),
      ('service_order', pg_temp.os('OS-00033'), 'OS-00033', 'status_change', 'awaiting_client', 'open', timestamptz '2026-10-28 10:00-03'),
      ('service_order', v_w, 'OS-97006', 'status_change', 'draft', 'open', timestamptz '2026-10-29 12:00-03');
    update public.service_orders set signed_at = timestamptz '2026-10-29 09:00-03' where id = pg_temp.os('ORÇ-00083');
    update public.os_planejamento set atualizado_em = timestamptz '2026-10-29 12:00-03' where service_order_id = pg_temp.os('OS-00069');
    update public.os_material set fonte = 'dono', atualizado_em = timestamptz '2026-10-29 11:00-03'
     where id = (select m.id from public.os_material m where m.service_order_id = pg_temp.os('OS-00112') order by m.id limit 1);
    -- a Kalmar OS-00032 que a vigia acabou de tentar (proposta dela, na mesma versão do plano, na última hora)
    perform public.agenda_propor('os', null, null, array[pg_temp.os('OS-00032')], '{}'::jsonb, true, 'vigia', null, c_hoje,
                                 timestamptz '2026-10-29 16:30-03');
    v_pl0 := pg_temp.plano();
    v_n := (select count(*) from public.agenda_propostas);
    r := public._agenda_gestor_encaixe(c_hoje, c_agora);
    select string_agg(e ->> 'numero', ' ' order by e ->> 'numero') into v_t from jsonb_array_elements(r -> 'por_os') e;
    -- a marca d'água: o encaixe das 16:52 rodou (a linha da rodada, rotina gestor); às 17:07 só o que veio depois dele
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, rotina, modo_equipe, modo_diaria)
    select c_agora, c_hoje, c_agora, c.modo_proposta, c.modo_vigia, jsonb_build_object('encaixe', r), 'gestor', c.modo_equipe, c.modo_diaria
      from public.agenda_config c where c.id;
    insert into public.ai_lifecycle_events (entity_type, entity_id, entity_number, event_type, old_value, new_value, created_at)
    values ('service_order', pg_temp.os('OS-00076'), 'OS-00076', 'status_change', 'draft', 'open', timestamptz '2026-10-29 17:00-03');
    r2 := public._agenda_gestor_encaixe(c_hoje, timestamptz '2026-10-29 17:07-03');
    select string_agg(e ->> 'numero', ' ' order by e ->> 'numero') into v_t2 from jsonb_array_elements(r2 -> 'por_os') e;
    v_b2 := pg_temp.plano() = v_pl0 and (select count(*) from public.agenda_propostas) = v_n;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E1a desligado = {pulado}; as candidatas: a conversão do agrupar sem status_change (Giancarlo OS-00130), a assinatura (Robson ORÇ-00083), o status_change (Rodrigo OS-00096), o planejamento (Vanderlei) e o material do dono (Nelson) mudados; fora a Kalmar que a vigia acabou de tentar, a Kalmar OS-00033 de antes da marca d''água e o Wagner que já tem dia',
    v_b and v_t = 'ORÇ-00083 OS-00069 OS-00096 OS-00112 OS-00130' and (r ->> 'candidatas')::int = 5
    and (r ->> 'de')::timestamptz = timestamptz '2026-10-28 16:47-03' and (r ->> 'ate')::timestamptz = c_agora,
    coalesce(v_t, '-') || ' | de ' || coalesce(r ->> 'de', '-'));
  v_res := pg_temp.ok(v_res, 'E1b a marca d''água: o encaixe seguinte (17:07) parte do "até" do que rodou (16:52, menos 5 min) e só pega o que veio depois (Rodrigo OS-00076, 17:00); em teste nada é gravado no plano nem nas propostas',
    v_t2 = 'OS-00076' and (r2 ->> 'de')::timestamptz = timestamptz '2026-10-29 16:47-03' and (r2 ->> 'simulacao')::boolean
    and v_b2,
    coalesce(v_t2, '-') || ' | de ' || coalesce(r2 ->> 'de', '-'));

  -- ── E2. Ligado marca; em teste só o diário ─────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado');
    update public.os_planejamento set atualizado_em = timestamptz '2026-10-29 16:00-03'
     where service_order_id in (pg_temp.os('OS-00074'), pg_temp.os('OS-00069'));
    r := public._agenda_gestor_encaixe(c_hoje, c_agora);
    select string_agg(format('%s:%s:%s', e ->> 'numero', e ->> 'resultado', coalesce(e ->> 'primeiro_dia', '-')), ' ' order by e ->> 'numero')
      into v_t from jsonb_array_elements(r -> 'por_os') e;
    v_n := (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('OS-00074') and a.tipo = 'reserva'
              and a.cancelada_motivo = 'promovida');
    v_n2 := (select count(*) from public.agenda_perguntas q where q.service_order_id = pg_temp.os('OS-00130') and q.tipo = 'estimativa'
               and q.estado = 'aberta' and q.modo = 'ligado');
    v_b := not exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E2a ligado: o encaixe marca o Lenine (a reserva promovida: qua 04/11 — na sintética o João está com o Wagner e o Xavier em ter 03/11) e o Vanderlei (qui 12/11); o Giancarlo, de fora pela estimativa, ganha a pergunta do gestor; a reserva promovida e a OS nova não fazem onda',
    v_t = 'OS-00069:marcada:2026-11-12 OS-00074:marcada:2026-11-04 OS-00130:pergunta:-' and v_n = 12 and v_n2 = 1 and v_b
    and (r ->> 'marcadas')::int = 2 and (r ->> 'perguntas')::int = 1 and not (r ->> 'onda')::boolean
    and (select (e ->> 'aprovada_em')::timestamptz from jsonb_array_elements(r -> 'por_os') e where e ->> 'numero' = 'OS-00130')
        = timestamptz '2026-10-28 20:29:43.349549+00',
    coalesce(v_t, '-') || ' | ' || left(r::text, 400));
  begin
    perform pg_temp.modos('sombra');
    update public.os_planejamento set atualizado_em = timestamptz '2026-10-29 16:00-03'
     where service_order_id in (pg_temp.os('OS-00074'), pg_temp.os('OS-00069'));
    -- o "eu marcaria assim" do dia já gravado não pode sumir
    perform public._agenda_gestor_dia_gravar(c_hoje, 'sombra', '{"itens": [], "md5": "do-dia"}'::jsonb, c_agora);
    v_pl0 := pg_temp.plano();
    v_n := (select count(*) from public.agenda_propostas) + (select count(*) from public.agenda_perguntas)
           + (select count(*) from public.agenda_acoes);
    r := public._agenda_gestor_encaixe(c_hoje, c_agora);
    select g.sombra into d from public.agenda_gestor_dia g where g.dia = c_hoje;
    select string_agg(format('%s:%s', e ->> 'numero', e ->> 'resultado'), ' ' order by e ->> 'numero')
      into v_t from jsonb_array_elements(d -> 'encaixe' -> 0 -> 'por_os') e;
    v_b := pg_temp.plano() = v_pl0
           and (select count(*) from public.agenda_propostas) + (select count(*) from public.agenda_perguntas)
               + (select count(*) from public.agenda_acoes) = v_n
           and coalesce(current_setting('agenda.gestor', true), '') = '';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E2b em teste: o mesmo motor com as regras do gestor (o Lenine e o Vanderlei marcados, o Giancarlo perguntado), sem gravar plano, proposta, pergunta nem ação; só o diário (sombra.encaixe), sem apagar o "eu marcaria" do dia; a variável da simulação desligada no fim',
    v_b and v_t = 'OS-00069:marcada OS-00074:marcada OS-00130:pergunta' and d ->> 'md5' = 'do-dia'
    and jsonb_array_length(d -> 'encaixe') = 1 and (r ->> 'simulacao')::boolean,
    coalesce(v_t, '-') || ' | ' || left(coalesce(d::text, '-'), 300));

  -- ── E3. A onda ────────────────────────────────────────────────────────────────────────────────────────
  -- (sex 30/10 10:07; o João e o Roberto fora: as 3 OS do João mudam de dia)
  begin
    perform pg_temp.modos('ligado');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota) values
      (v_joao, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8'),
      (v_rob, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8');
    v_pl0 := pg_temp.plano();
    v_v0 := (public._agenda_cfg()).versao_plano;
    r := public.agenda_replanejar(v_tres, 'teste P8', 'vigia', c_sex, c_sexa, null);
    select q.* into x from public.agenda_perguntas q where q.tipo = 'onda';
    v_b := pg_temp.plano() = v_pl0 and (public._agenda_cfg()).versao_plano = v_v0
           and exists (select 1 from public.agenda_propostas p where p.id = (r ->> 'proposta_id')::uuid and p.estado = 'aberta'
                         and p.modo = 'ligado');
    -- a mesma conta de novo (a vigia, uma hora depois): a mesma pergunta
    r2 := public.agenda_replanejar(v_tres, 'teste P8', 'vigia', c_sex, c_sexa + interval '1 hour', null);
    v_n := (select count(*) from public.agenda_perguntas q where q.tipo = 'onda');
    v_n2 := (public.agenda_saude(c_sex, c_sexa + interval '1 hour') -> 'gestor' ->> 'onda_aplicada_sem_pergunta')::int;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E3a 3 OS com dia mudado (o João não vem em ter 03 e qua 04/11): nada aplicado (o plano e a versão iguais), a proposta aberta e a pergunta crítica onda com o texto da §6.3, a chave da versão, as 3 OS, a proposta e a recomendação 1; a mesma conta uma hora depois não pergunta de novo; a saúde não acusa',
    v_b and not (r ->> 'ok')::boolean and (r ->> 'onda')::boolean and x.texto = c_onda and x.critica and x.estado = 'aberta'
    and x.modo = 'ligado' and x.chave = 'onda:v' || v_v0 and x.os_ids @> v_tres and cardinality(x.os_ids) = 3
    and x.proposta_id = (r ->> 'proposta_id')::uuid and x.recomendacao = 1 and jsonb_array_length(x.opcoes) = 3 and x.veto_ate is null
    and r ->> 'texto' like 'Não mudei nada: mudou muita coisa de uma vez, e eu te pergunto antes. Preciso de você: Mudou muita coisa%'
    and (r2 ->> 'onda')::boolean and (r2 ->> 'pergunta_id')::uuid = x.id and v_n = 1 and v_n2 = 0,
    coalesce(x.texto, '-') || ' | ' || left(r::text, 300));
  begin
    perform pg_temp.modos('ligado');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota) values
      (v_joao, daterange('2026-11-03', '2026-11-03', '[]'), 'indisponivel', 'dono', 'teste P8'),
      (v_rob, daterange('2026-11-03', '2026-11-03', '[]'), 'indisponivel', 'dono', 'teste P8');
    r := public.agenda_replanejar(v_tres, 'teste P8', 'vigia', c_sex, c_sexa, null);
    v_t := pg_temp.dias(array['OS-97006', 'OS-97007', 'OS-97008']);
    v_n := (select count(*) from public.agenda_perguntas q where q.tipo = 'onda');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E3b 2 OS com dia mudado (os dois fora só em ter 03/11) e 1 dia avisado: não é onda — aplica (o Wagner e o Xavier saem de ter 03/11; a Yara fica)',
    (r ->> 'ok')::boolean and r ->> 'onda' is null and v_n = 0 and v_t like 'OS-97006:2026-%' and v_t not like 'OS-97006:2026-11-03%'
    and v_t like '%OS-97008:2026-11-04', v_t || ' | ' || left(r ->> 'texto', 300));
  begin
    -- a conta, item a item: a troca de pessoa no mesmo meio-dia, a reserva promovida e a OS nova não contam; o dia conta uma vez
    r := public._agenda_gestor_onda_conta(jsonb_build_array(
      jsonb_build_object('op', 'cancelar', 'os', v_tres[1], 'tipo', 'execucao', 'motivo', 'pessoa', 'violada', true,
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_joao, 'nome', 'João', 'dia', '2026-11-03', 'turno', 'manha', 'presenca', 'turno'))),
      jsonb_build_object('op', 'criar', 'os', v_tres[1], 'tipo', 'execucao',
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_rob, 'dia', '2026-11-03', 'turno', 'manha', 'presenca', 'turno'))),
      jsonb_build_object('op', 'cancelar', 'os', pg_temp.os('OS-00074'), 'tipo', 'reserva', 'motivo', 'promovida', 'violada', false,
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_rob, 'dia', '2026-11-05', 'turno', 'manha', 'presenca', 'turno'))),
      jsonb_build_object('op', 'criar', 'os', pg_temp.os('OS-00074'), 'tipo', 'execucao',
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_rob, 'dia', '2026-11-06', 'turno', 'manha', 'presenca', 'turno'))),
      jsonb_build_object('op', 'criar', 'os', pg_temp.os('OS-00069'), 'tipo', 'execucao',
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_rob, 'dia', '2026-11-12', 'turno', 'manha', 'presenca', 'turno')))));
    -- 3 OS do João que mudam de dia (o dia avisado de ter 03/11 em duas delas conta 1 dia); a 3ª com item crítico fica fora
    r2 := public._agenda_gestor_onda_conta(jsonb_build_array(
      jsonb_build_object('op', 'cancelar', 'os', v_tres[1], 'tipo', 'execucao', 'motivo', 'pessoa', 'violada', true,
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_joao, 'nome', 'João', 'dia', '2026-11-03', 'turno', 'manha', 'presenca', 'turno'))),
      jsonb_build_object('op', 'criar', 'os', v_tres[1], 'tipo', 'execucao',
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_rob, 'dia', '2026-11-05', 'turno', 'manha', 'presenca', 'turno'))),
      jsonb_build_object('op', 'cancelar', 'os', v_tres[2], 'tipo', 'execucao', 'motivo', 'pessoa', 'violada', true,
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_joao, 'nome', 'João', 'dia', '2026-11-03', 'turno', 'tarde', 'presenca', 'turno'))),
      jsonb_build_object('op', 'criar', 'os', v_tres[2], 'tipo', 'execucao', 'evento_real', true,
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_rob, 'dia', '2026-11-05', 'turno', 'tarde', 'presenca', 'turno'))),
      jsonb_build_object('op', 'cancelar', 'os', v_tres[3], 'tipo', 'execucao', 'motivo', 'pessoa', 'violada', true,
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_joao, 'nome', 'João', 'dia', '2026-11-04', 'turno', 'manha', 'presenca', 'turno'))),
      jsonb_build_object('op', 'criar', 'os', v_tres[3], 'tipo', 'execucao', 'critica', 'atraso_longo',
                         'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_rob, 'dia', '2026-11-16', 'turno', 'manha', 'presenca', 'turno')))));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E3c a conta: a troca de pessoa no mesmo meio-dia (o João pelo Roberto, ter 03/11 de manhã), a reserva promovida e a OS nova não contam como dia mudado (o dia avisado do João que sai sem voltar igual conta: 1); com 3 OS do João, as 2 sem item crítico contam, ter 03/11 conta 1 vez, o porquê é "João não vem" e a de evento real vai à parte',
    (r ->> 'os_n')::int = 0 and (r ->> 'dias_n')::int = 1 and r -> 'dias' -> 0 ->> 'quem' = 'equipe'
    and (r2 ->> 'os_n')::int = 2 and (r2 ->> 'dias_n')::int = 1 and r2 ->> 'motivo' = 'João não vem'
    and r2 -> 'nomes' = '["Wagner", "Xavier"]'::jsonb and r2 -> 'evento_real' = jsonb_build_array(v_tres[2]),
    r::text || ' | ' || r2::text);
  begin
    perform pg_temp.modos('ligado', '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,escada,sinal_cobrar}');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota) values
      (v_joao, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8'),
      (v_rob, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8');
    r := public.agenda_replanejar(v_tres, 'teste P8', 'vigia', c_sex, c_sexa, null);
    v_n := (select count(*) from public.agenda_perguntas q where q.tipo = 'onda');
    v_t := pg_temp.dias(array['OS-97006', 'OS-97007', 'OS-97008']);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E3d sem a regra onda (fora de marcar_regras), as mesmas 3 OS são aplicadas como antes, sem pergunta',
    (r ->> 'ok')::boolean and r ->> 'onda' is null and v_n = 0 and v_t not like '%2026-11-03%' and v_t not like '%2026-11-04%',
    v_t || ' | ' || left(r ->> 'texto', 200));

  -- ── E4. A zona travada ────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado');
    -- a Úrsula com o Roberto em seg 09/11 de manhã (o prometido firme é de seg 09 a ter 10/11)
    v_nova := gen_random_uuid();
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_nova, pg_temp.os('OS-97004'), v_rob, date '2026-11-09', 'manha', 'turno', 'execucao', 'publicada', 'motor',
            timestamptz '2026-10-29 16:30-03');
    v_t := concat_ws(' | ',
      -- o dia avisado à equipe (a ficha do João de ter 03/11) sem ficar impossível; com ele em p_violadas, não conta
      coalesce(public._agenda_criticidade(v_w, date '2026-11-03', date '2026-11-03', date '2026-11-03', date '2026-11-03', c_sex, array[v_alw], '{}'), '-'),
      coalesce(public._agenda_criticidade(v_w, date '2026-11-03', date '2026-11-03', date '2026-11-03', date '2026-11-03', c_sex, array[v_alw], array[v_alw]), '-'),
      -- o dia que o cliente ouviu (o prometido firme cobre seg 09/11)
      coalesce(public._agenda_criticidade(pg_temp.os('OS-97004'), null, null, date '2026-11-09', date '2026-11-09', c_sex, array[v_nova], '{}'), '-'),
      -- o fim que passa do prometido firme (ter 10 → qua 11/11), e o que já passava dele não
      coalesce(public._agenda_criticidade(pg_temp.os('OS-97004'), date '2026-11-10', date '2026-11-09', date '2026-11-11', date '2026-11-09', c_sex, '{}', '{}'), '-'),
      coalesce(public._agenda_criticidade(pg_temp.os('OS-97004'), date '2026-11-11', date '2026-11-09', date '2026-11-12', date '2026-11-09', c_sex, '{}', '{}'), '-'));
    perform pg_temp.modos('desligado');
    v_t2 := concat_ws(' | ',
      coalesce(public._agenda_criticidade(v_w, date '2026-11-03', date '2026-11-03', date '2026-11-03', date '2026-11-03', c_sex, array[v_alw], '{}'), '-'),
      coalesce(public._agenda_criticidade(pg_temp.os('OS-97004'), null, null, date '2026-11-09', date '2026-11-09', c_sex, array[v_nova], '{}'), '-'),
      coalesce(public._agenda_criticidade(pg_temp.os('OS-97004'), date '2026-11-10', date '2026-11-09', date '2026-11-11', date '2026-11-09', c_sex, '{}', '{}'), '-'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E4a a regra: o dia que a equipe já recebeu na ficha que sairia = dia_avisado (o que ficou impossível, em p_violadas, não conta); o dia que o cliente ouviu = dia_prometido; o fim que passaria do prometido firme = dia_prometido (o que já passava, não); com o gestor desligado, nada disso',
    v_t = 'dia_avisado | - | dia_prometido | dia_prometido | -' and v_t2 = '- | - | -', v_t || ' || ' || v_t2);
  -- a conta do que fica fora da zona: a violada, o resto do meio-dia dela, a que volta igual; nunca o fixado pelo dono
  r := jsonb_build_array(
    jsonb_build_object('alocacao_id', 'a0000000-0000-4000-8000-000000000001', 'os', v_w, 'violada', true, 'dia', '2026-11-03', 'turno', 'manha', 'payee_id', v_joao, 'presenca', 'turno', 'estado', 'publicada'),
    jsonb_build_object('alocacao_id', 'a0000000-0000-4000-8000-000000000002', 'os', v_w, 'violada', false, 'dia', '2026-11-03', 'turno', 'manha', 'payee_id', v_rob, 'presenca', 'turno', 'estado', 'publicada'),
    jsonb_build_object('alocacao_id', 'a0000000-0000-4000-8000-000000000003', 'os', v_w, 'violada', false, 'dia', '2026-11-04', 'turno', 'tarde', 'payee_id', v_rob, 'presenca', 'turno', 'estado', 'publicada'),
    jsonb_build_object('alocacao_id', 'a0000000-0000-4000-8000-000000000004', 'os', v_w, 'violada', false, 'dia', '2026-11-05', 'turno', 'manha', 'payee_id', v_rob, 'presenca', 'turno', 'estado', 'publicada'),
    jsonb_build_object('alocacao_id', 'a0000000-0000-4000-8000-000000000005', 'os', v_w, 'violada', true, 'dia', '2026-11-06', 'turno', 'manha', 'payee_id', v_rob, 'presenca', 'turno', 'estado', 'fixada', 'fixado_por', 'dono'),
    jsonb_build_object('alocacao_id', 'a0000000-0000-4000-8000-000000000006', 'os', v_tres[2], 'violada', true, 'dia', '2026-11-03', 'turno', 'tarde', 'payee_id', v_joao, 'presenca', 'turno', 'estado', 'publicada'));
  v_t := array_to_string(public._agenda_zona_fora(r, v_w, jsonb_build_array(
           jsonb_build_object('payee_id', v_rob, 'dia', '2026-11-04', 'turno', 'tarde', 'presenca', 'turno'))), ',');
  v_res := pg_temp.ok(v_res, 'E4b _agenda_zona_fora: fica fora da conta a violada, o resto do meio-dia dela e a que volta igual no encaixe novo; a que muda sem ter ficado impossível e o fixado pelo dono ficam na conta; outra OS não entra',
    v_t = 'a0000000-0000-4000-8000-000000000001,a0000000-0000-4000-8000-000000000002,a0000000-0000-4000-8000-000000000003', v_t);
  begin
    -- no motor: a Úrsula com o Roberto em qua 11 e qui 12/11, o prometido firme de qua 11 a qui 12/11; os dois fora em qua 11/11
    perform pg_temp.modos('ligado');
    update public.os_planejamento set prometido_de = date '2026-11-11', prometido_ate = date '2026-11-12', prometido_original_ate = date '2026-11-12'
     where service_order_id = pg_temp.os('OS-97004');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select gen_random_uuid(), pg_temp.os('OS-97004'), v_rob, x2.d, x2.t, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-10-29 16:30-03'
      from (values (date '2026-11-11', 'manha'), (date '2026-11-11', 'tarde'), (date '2026-11-12', 'manha'), (date '2026-11-12', 'tarde')) x2(d, t);
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota) values
      (v_joao, daterange('2026-11-11', '2026-11-11', '[]'), 'indisponivel', 'dono', 'teste P8'),
      (v_rob, daterange('2026-11-11', '2026-11-11', '[]'), 'indisponivel', 'dono', 'teste P8');
    r := public.agenda_replanejar(array[pg_temp.os('OS-97004')], 'teste P8', 'vigia', c_sex, c_sexa, null);
    select q.tipo, q.texto into v_t, v_t2 from public.agenda_perguntas q
     where q.estado = 'aberta' and q.service_order_id = pg_temp.os('OS-97004') and q.critica;
    v_n := (select count(*) from public.agenda_perguntas q where q.tipo = 'onda');
    -- sem a regra zona_travada, a mesma OS segue sozinha (1 dia de atraso não é crítico pelas regras de antes)
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E4c no motor: a Úrsula (o prometido firme de qua 11 a qui 12/11; o Roberto e o João fora em qua 11/11) só termina sex 13/11 — vira a crítica dia_prometido, com a recomendação do P3 ("É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje"); a OS que já é pergunta crítica não vira onda',
    v_t = 'dia_prometido' and v_t2 like 'Úrsula (OS-97004) só dá para terminar em sex 13/11%É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje.'
    and v_n = 0, coalesce(v_t, '-') || ': ' || coalesce(v_t2, '-') || ' | ' || left(r::text, 300));
  begin
    perform pg_temp.modos('ligado', '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,escada,sinal_cobrar}');
    update public.os_planejamento set prometido_de = date '2026-11-11', prometido_ate = date '2026-11-12', prometido_original_ate = date '2026-11-12'
     where service_order_id = pg_temp.os('OS-97004');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select gen_random_uuid(), pg_temp.os('OS-97004'), v_rob, x2.d, x2.t, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-10-29 16:30-03'
      from (values (date '2026-11-11', 'manha'), (date '2026-11-11', 'tarde'), (date '2026-11-12', 'manha'), (date '2026-11-12', 'tarde')) x2(d, t);
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota) values
      (v_joao, daterange('2026-11-11', '2026-11-11', '[]'), 'indisponivel', 'dono', 'teste P8'),
      (v_rob, daterange('2026-11-11', '2026-11-11', '[]'), 'indisponivel', 'dono', 'teste P8');
    r := public.agenda_replanejar(array[pg_temp.os('OS-97004')], 'teste P8', 'vigia', c_sex, c_sexa, null);
    v_n := (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.service_order_id = pg_temp.os('OS-97004') and q.critica);
    v_t := pg_temp.dias(array['OS-97004']);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E4d sem a zona travada (e sem a onda, que contaria os 2 dias que o cliente ouviu), a mesma Úrsula segue sozinha, sem pergunta (o de antes)',
    (r ->> 'ok')::boolean and v_n = 0 and v_t <> 'OS-97004:-', v_t || ' | ' || left(r ->> 'texto', 200));
  begin
    -- na saúde: a ação da vigia (depois do OK de ligar) que tirou o dia do João de ter 03/11 (já avisado na ficha) sem ele ter
    -- ficado impossível e marcou o Wagner em seg 09/11
    perform pg_temp.modos('ligado');
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado', cancelada_em = c_sexa where id = v_alw;
    v_nova := gen_random_uuid();
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_nova, v_w, v_joao, date '2026-11-09', 'manha', 'turno', 'execucao', 'publicada', 'motor', c_sexa);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas,
                                     alocacoes_canceladas, antes, depois, texto)
    values (c_sexa, c_sex, true, 'vigia', 'mover', v_w, array[v_w], array[v_nova], array[v_alw],
            '{"fim": "2026-11-03"}'::jsonb, '{"fim": "2026-11-09"}'::jsonb, 'TESTE P8: Wagner de ter 03/11 para seg 09/11.')
    returning id into v_acao;
    v_t := coalesce(public._agenda_criticidade_da_acao(v_acao), '-');
    d := public.agenda_saude(c_sex, c_sexa);
    -- a mesma ação feita antes do OK de ligar não conta (a regra não valia)
    update public.agenda_config set marcar_sozinho_desde = c_sexa + interval '1 minute' where id;
    v_t2 := coalesce(public._agenda_criticidade_da_acao(v_acao), '-');
    perform pg_temp.modos('desligado');
    v_t2 := v_t2 || ' ' || coalesce(public._agenda_criticidade_da_acao(v_acao), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E4e na saúde: a ação que tirou o dia avisado à equipe sem pergunta = dia_avisado (_agenda_criticidade_da_acao) e conta em dia_avisado_sem_pergunta (o ok cai); antes do OK de ligar, ou com o gestor desligado, não',
    v_t = 'dia_avisado' and (d -> 'gestor' ->> 'dia_avisado_sem_pergunta')::int = 1 and not (d -> 'gestor' ->> 'zeros_ok')::boolean
    and v_t2 = '- -', v_t || ' | ' || v_t2 || ' | ' || coalesce(d -> 'gestor' ->> 'dia_avisado_sem_pergunta', '-'));

  -- ── E5. A decisão da onda ─────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota) values
      (v_joao, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8'),
      (v_rob, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8');
    r := public.agenda_replanejar(v_tres, 'teste P8', 'vigia', c_sex, c_sexa, null);
    v_q := (r ->> 'pergunta_id')::uuid;
    d := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', '1', c_sex, c_sexa + interval '10 minutes');
    v_t := pg_temp.dias(array['OS-97006', 'OS-97007', 'OS-97008']);
    select q.estado, q.opcao_escolhida into x from public.agenda_perguntas q where q.id = v_q;
    v_b := x.estado = 'respondida' and x.opcao_escolhida = 1
           and (select count(*) = 3 and bool_and(a.critica and a.pergunta_id = v_q and a.origem = 'dono')
                  from public.agenda_acoes a where a.pergunta_id = v_q and a.executada);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E5a a onda, 1 (faço tudo): a conta refeita e aplicada — as 3 OS saem de ter 03 e qua 04/11 —, a pergunta respondida e as 3 ações críticas com ela (origem dono)',
    (d ->> 'ok')::boolean and d ->> 'texto' like 'Feito: %' and v_b and v_t not like '%2026-11-03%' and v_t not like '%2026-11-04%',
    v_t || ' | ' || left(d::text, 300));
  begin
    perform pg_temp.modos('ligado');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota) values
      (v_joao, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8'),
      (v_rob, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8');
    r := public.agenda_replanejar(v_tres, 'teste P8', 'vigia', c_sex, c_sexa, null);
    v_q := (r ->> 'pergunta_id')::uuid;
    d := public.agenda_decidir(v_q, 2::smallint, v_adm, 'whatsapp', '2', c_sex, c_sexa + interval '10 minutes');
    v_t := pg_temp.dias(array['OS-97006', 'OS-97007', 'OS-97008']);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E5b a onda, 2 (só hoje e amanhã: ter 03/11 está no congelado de sex 30/10): o Wagner e o Xavier mudam; a Yara (qua 04/11) fica para a rodada seguinte',
    (d ->> 'ok')::boolean and v_t like 'OS-97006:2026-%' and v_t not like 'OS-97006:2026-11-03%'
    and v_t like '% OS-97008:2026-11-04' and v_t not like '%OS-97007:2026-11-03%', v_t || ' | ' || left(d::text, 300));
  begin
    perform pg_temp.modos('ligado');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota) values
      (v_joao, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8'),
      (v_rob, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8');
    r := public.agenda_replanejar(v_tres, 'teste P8', 'vigia', c_sex, c_sexa, null);
    v_q := (r ->> 'pergunta_id')::uuid;
    v_pl0 := pg_temp.plano();
    d := public.agenda_decidir(v_q, 3::smallint, v_adm, 'whatsapp', '3', c_sex, c_sexa + interval '10 minutes');
    v_b := pg_temp.plano() = v_pl0
           and (select p.estado from public.agenda_propostas p where p.id = (r ->> 'proposta_id')::uuid) = 'descartada'
           and (select q.estado from public.agenda_perguntas q where q.id = v_q) = 'respondida';
    -- a vigia uma hora depois (a mesma versão do plano): não pergunta de novo e não aplica
    r2 := public.agenda_replanejar(v_tres, 'teste P8', 'vigia', c_sex, c_sexa + interval '70 minutes', null);
    v_b := v_b and pg_temp.plano() = v_pl0 and (r2 ->> 'onda')::boolean
           and r2 ->> 'texto' = 'Não mudei nada: você me disse para esperar até a agenda mudar.'
           and (select count(*) from public.agenda_perguntas q where q.tipo = 'onda') = 1;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E5c a onda, 3 (não mudo nada): a proposta descartada, nada no plano; a vigia na mesma versão do plano não pergunta de novo nem aplica ("você me disse para esperar")',
    v_b and (d ->> 'ok')::boolean
    and d ->> 'texto' = 'Combinado: não mudei nada. Me diga o que mudar (*agenda plano* mostra o que está marcado).',
    left(d::text, 200) || ' | ' || left(coalesce(r2::text, '-'), 200));
  begin
    perform pg_temp.modos('ligado');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota) values
      (v_joao, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8'),
      (v_rob, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8');
    r := public.agenda_replanejar(v_tres, 'teste P8', 'vigia', c_sex, c_sexa, null);
    v_q := (r ->> 'pergunta_id')::uuid;
    -- a agenda muda (o Lenine encaixado) antes da resposta
    perform public.agenda_replanejar(array[pg_temp.os('OS-00074')], 'teste P8', 'motor', c_sex, c_sexa + interval '5 minutes', null);
    v_pl0 := pg_temp.plano();
    d := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', '1', c_sex, c_sexa + interval '10 minutes');
    v_b := pg_temp.plano() = v_pl0 and (select q.estado from public.agenda_perguntas q where q.id = v_q) = 'resolvida';
    -- o encaixe ligado resolve a onda aberta de versão que passou (a de antes, de outra conta)
    r := public.agenda_replanejar(v_tres, 'teste P8', 'vigia', c_sex, c_sexa + interval '12 minutes', null);
    v_q2 := (r ->> 'pergunta_id')::uuid;
    perform public.agenda_replanejar(array[pg_temp.os('OS-00069')], 'teste P8', 'motor', c_sex, c_sexa + interval '13 minutes', null);
    r2 := public._agenda_gestor_encaixe(c_sex, c_sexa + interval '15 minutes');
    v_b := v_b and (select q.estado from public.agenda_perguntas q where q.id = v_q2) = 'resolvida'
           and (r2 ->> 'ondas_vencidas')::int = 1;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'E5d a agenda mudou desde a pergunta da onda: a resposta não muda nada e a pergunta resolve ("refaço a conta"); o encaixe resolve a onda aberta de uma versão que já passou',
    v_b and not (d ->> 'ok')::boolean and (d ->> 'mudou')::boolean
    and d ->> 'texto' = 'A agenda mudou desde a pergunta: não mudei nada agora. Na próxima rodada eu refaço a conta e, se ainda for muita mudança, te pergunto de novo.',
    left(d::text, 300) || ' | ' || left(coalesce(r2::text, '-'), 200));

  perform pg_temp.gravar(v_res);
end
$fx$;

-- ── E6. As cópias e o portão falso ───────────────────────────────────────────────────────────────────────
do $copias$
declare
  v_res  jsonb := '[]'::jsonb;
  v_m2   text := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  v_c2   text := coalesce(current_setting('agenda_teste.mig_conferencia_fase2', true), '');
  v_p3   text := coalesce(current_setting('agenda_teste.mig_prontidao_fase7a', true), '');
  v_p4   text := coalesce(current_setting('agenda_teste.mig_perguntas_fase7a', true), '');
  r      record;
  v_novo text;
  v_n    int;
begin
  if v_m2 = '' or v_c2 = '' or v_p3 = '' or v_p4 = '' then
    insert into _resultado values ('E6 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('_agenda_criticidade', 'public._agenda_criticidade(uuid, date, date, date, date, date, uuid[], uuid[])', v_m2, '20261025100200', 3),
      ('_agenda_criticidade_da_acao', 'public._agenda_criticidade_da_acao(uuid)', v_c2, '20261025100300', 2),
      ('agenda_propor', 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', v_p3, '20261031100200', 3),
      ('_agenda_propor_e_aplicar', 'public._agenda_propor_e_aplicar(text, uuid[], text, uuid, date, timestamptz)', v_c2, '20261025100300', 2),
      ('_agenda_gestor_decidir', 'public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', v_p4, '20261031100300', 2)
    ) t(nome, assinatura, fonte, versao, blocos)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: \(7a P8', 'g');
    v_res := pg_temp.ok(v_res,
      format('E6a %s: sem os %s blocos "-- FASE 7: (7a P8", é o corpo de %s (a mais nova antes do P8)', r.nome, r.blocos, r.versao),
      v_n = r.blocos and pg_temp.corpo(r.fonte, r.nome) <> '' and pg_temp.sem_p8(v_novo) = pg_temp.corpo(r.fonte, r.nome),
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(r.fonte, r.nome)),
             length(pg_temp.sem_p8(v_novo))));
  end loop;
  perform pg_temp.gravar(v_res);
end
$copias$;

do $portao$
declare
  v_res  jsonb := '[]'::jsonb;
  v_m2   text := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  v_c2   text := coalesce(current_setting('agenda_teste.mig_conferencia_fase2', true), '');
  v_p3   text := coalesce(current_setting('agenda_teste.mig_prontidao_fase7a', true), '');
  c_sex  constant date := date '2026-10-30';
  c_sexa constant timestamptz := timestamptz '2026-10-30 10:07-03';
  v_dif  text;
  v_n    int;
  v_tres uuid[];
  v_joao uuid;
  v_rob  uuid;
  r      record;
begin
  if v_m2 = '' or v_c2 = '' or v_p3 = '' or coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('E6b o portão falso', true, 'PULADO: sem as fixtures e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- (o replay e a sintética já estão carregados se o bloco de cima rodou; senão, carrega)
  if pg_temp.os('OS-97006') is null then
    execute current_setting('agenda_teste.replay2910');
    execute current_setting('agenda_teste.fase7a');
  end if;
  execute replace(pg_temp.inteira(v_m2, '_agenda_criticidade'), 'create or replace function public._agenda_criticidade(',
                  'create function pg_temp.crit_antes(');
  execute replace(pg_temp.inteira(v_c2, '_agenda_criticidade_da_acao'), 'create or replace function public._agenda_criticidade_da_acao(',
                  'create function pg_temp.crit_acao_antes(');
  execute replace(pg_temp.inteira(v_p3, 'agenda_propor'), 'create or replace function public.agenda_propor(',
                  'create function pg_temp.propor_antes(');
  select id into v_joao from public.payees where name = 'João' and active;
  select id into v_rob from public.payees where name = 'Roberto' and active;
  v_tres := array[pg_temp.os('OS-97006'), pg_temp.os('OS-97007'), pg_temp.os('OS-97008')];
  -- a falta do João (a zona e a onda teriam o que fazer) e uma ação com o dia avisado
  insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota) values
    (v_joao, daterange('2026-11-03', '2026-11-04', '[]'), 'indisponivel', 'dono', 'teste P8');
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado', cancelada_em = c_sexa
   where service_order_id = v_tres[2];
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas,
                                   alocacoes_canceladas, antes, depois, texto)
  select c_sexa, c_sex, true, 'vigia', 'cancelar', v_tres[2], array[v_tres[2]], '{}',
         array(select a2.id from public.agenda_alocacoes a2 where a2.service_order_id = v_tres[2]),
         '{"fim": "2026-11-03"}'::jsonb, '{}'::jsonb, 'TESTE P8: Xavier sai de ter 03/11.';
  for r in select * from (values
             (1, 'desligado', 'desligado', false, null::text[]),
             (2, 'sombra sem a simulação', 'sombra', false, null::text[]),
             (3, '*gestor, só propor*', 'ligado', true, null::text[]),
             (4, 'sem a zona travada e a onda', 'ligado', false,
              '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,escada,sinal_cobrar}'::text[])
           ) t(o, nome, modo, so_propor, regras) order by o loop
    perform pg_temp.modos(r.modo, r.regras);
    update public.agenda_config set gestor_so_propor = r.so_propor where id;
    -- a criticidade: todas as alocações de compromisso como canceladas, com e sem violadas, o fim andando 0, 2 e 9 dias
    select count(*) filter (where public._agenda_criticidade(a2.service_order_id, a2.dia, a2.dia, a2.dia + k, a2.dia + k, c_sex,
                                                             array[a2.id], case when k = 2 then array[a2.id] else '{}' end)
                                  is distinct from pg_temp.crit_antes(a2.service_order_id, a2.dia, a2.dia, a2.dia + k, a2.dia + k, c_sex,
                                                                      array[a2.id], case when k = 2 then array[a2.id] else '{}' end))
      into v_n
      from public.agenda_alocacoes a2, unnest(array[0, 2, 9]) k
     where a2.tipo <> 'reserva';
    if v_n > 0 then v_dif := concat_ws('; ', v_dif, r.nome || ' (criticidade): ' || v_n); end if;
    select count(*) into v_n from public.agenda_acoes x
     where public._agenda_criticidade_da_acao(x.id) is distinct from pg_temp.crit_acao_antes(x.id);
    if v_n > 0 then v_dif := concat_ws('; ', v_dif, r.nome || ' (ação): ' || v_n); end if;
    if md5((public.agenda_propor('replano', null, null, v_tres, '{}'::jsonb, false, 'vigia', null, c_sex, c_sexa) - 'proposta_id')::text)
       <> md5((pg_temp.propor_antes('replano', null, null, v_tres, '{}'::jsonb, false, 'vigia', null, c_sex, c_sexa) - 'proposta_id')::text) then
      v_dif := concat_ws('; ', v_dif, r.nome || ' (motor)');
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'E6b com o portão falso (desligado, sombra sem a simulação, *gestor, só propor*, sem a zona travada e a onda), _agenda_criticidade, _agenda_criticidade_da_acao e o motor (o replano das 3 OS do João que falta) dão o de antes, byte a byte',
    v_dif is null, coalesce(v_dif, '—'));
  perform pg_temp.gravar(v_res);
end
$portao$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
