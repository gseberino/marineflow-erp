-- Prova da revisão diária e da escada de reparo, Fase 7a (pacote P9, migration 20261031100750), sobre a carteira REAL de 29/10
-- (o replay), a sintética da 7a (o Wagner, o Xavier e a Yara com o João em ter 03 e qua 04/11, a ficha do João de ter 03/11
-- enfileirada, a Úrsula com 2 dias do dono, o Rodrigo do diagnóstico) e OS do próprio teste (Abel, Bento e Davi, com o Roberto
-- na semana de 16 e 23/11, longe de tudo).
-- bancada: depende de 20261031100750
--
--   V0 as portas e o que é (sem fixture): as contas e as perguntas da revisão invoker e sem grant; o conserto e o corte aplicados
--      definer e sem grant a ninguém; o passo invoker e sem grant; as 4 recriadas com as portas de antes
--   V1 a rodada: a revisão roda uma vez por dia útil, no 1º tique a partir das 16:45 (não antes, não no tique seguinte, não no
--      sábado); desligada ou fora de dia útil = {pulado}
--   V2 o reestimar: a OS pela estimativa com dias a mais perde os últimos (o fechamento do dono volta no novo último; a ação
--      reestimar; o dia avisado e o congelado ficam); com dias a menos, o encaixe acrescenta; os dias do dono com o orçamento
--      mudado = a pergunta (o texto, o prazo; sem resposta fica o do dono; o mesmo orçamento não pergunta de novo; o que muda de
--      novo pergunta de novo); a opção 2 aceita a conta e a agenda acompanha; o desfaz volta os dias do dono
--   V3 a escada: degrau 1 (outra pessoa no mesmo meio-dia), 2 (o outro turno), 3 (outro dia da semana, sem deixar mais dias
--      parados), o 4º vai ao motor; o pedido do cliente pula a escada; a onda vale (com o dia avisado acima do limite, tudo ao
--      motor, que pergunta); o desfaz da ação reparar volta como estava; uma OS consertada e outra ao motor na mesma chamada
--   V4 a proposta montada passa nas 14 regras (e a mesma, com a pessoa errada, não passa)
--   V5 o reavaliar: o diagnóstico feito, 1 dia útil depois, pergunta (sem prazo); as duas respostas
--   V6 em teste, tudo seco: nada gravado (plano, proposta, pergunta, ação), só o diário (sombra.revisao), que o "eu marcaria"
--      das 16:52 mantém
--   V7 as cópias: as 4 recriadas sem os blocos "-- FASE 7: (7a P9" são o corpo da origem; com o portão falso, agenda_replanejar
--      e agenda_aplicar dão o de antes, byte a byte
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_revisao.sql
--   Seguro em produção: V0 e V7a (as cópias saem PULADO sem as migrations como texto) só leem; V1 a V6 e V7b usam as fixtures e
--   só rodam na bancada (fora dela saem PULADO). Termina em ROLLBACK.
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
-- O plano (o vigente e o cancelado, sem ids): o que se compara entre as definições de antes e as de agora.
create function pg_temp.plano() returns text language sql stable as $f$
  select md5(coalesce(string_agg(concat_ws(' ', so.service_order_number, py.name, a.dia, a.turno, a.presenca, a.tipo, a.estado,
                                           a.fixado_por, a.cancelada_motivo),
                                 ',' order by so.service_order_number, a.dia, a.turno, py.name, a.presenca, a.estado, a.cancelada_motivo), ''))
    from public.agenda_alocacoes a join public.service_orders so on so.id = a.service_order_id join public.payees py on py.id = a.payee_id
   where a.estado in ('publicada', 'fixada', 'cancelada')
$f$;
-- As alocações de compromisso vigentes de uma OS: "Roberto 2026-11-03 manha", em ordem.
create function pg_temp.vig(p_os uuid) returns text language sql stable as $f$
  select string_agg(concat_ws(' ', py.name, a.dia, a.turno) || case when a.presenca <> 'turno' then ' ' || a.presenca else '' end,
                    ' | ' order by a.dia, a.turno = 'tarde', a.presenca <> 'turno', py.name)
    from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
$f$;
-- Uma OS do teste: aberta, aprovada, uma linha de serviço de R$ 382 por meio-dia (p_dias), sem o dono; com p_dono, os dias ditos.
create function pg_temp.nova_os(p_n text, p_nome text, p_dias numeric, p_dono boolean default true) returns uuid language plpgsql as $f$
declare v_cli uuid := md5('p9:cli:' || p_n)::uuid; v_bem uuid := md5('p9:bem:' || p_n)::uuid; v_os uuid := md5('p9:os:' || p_n)::uuid;
begin
  insert into public.clients (id, type, name) values (v_cli, 'individual', p_nome);
  insert into public.vessels (id, client_id, name, asset_type) values (v_bem, v_cli, 'Motorhome', 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                     created_at, updated_at, converted_to_os_at)
  values (v_os, 'OS-' || p_n, v_cli, v_bem, 'open', 'approved', 'repair', timestamptz '2026-10-20 10:00-03',
          timestamptz '2026-10-23 10:00-03', timestamptz '2026-10-23 10:00-03');
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, created_at, updated_at)
  values (md5('p9:srv:' || p_n)::uuid, v_os, null, 'Revisão elétrica', 'unit', 1, 382 * p_dias * 2, 382 * p_dias * 2,
          timestamptz '2026-10-20 10:00-03', timestamptz '2026-10-20 10:00-03');
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca)
  values (v_os, case when p_dono then p_dias end, case when p_dono then 'dono' end,
          case when p_dono then timestamptz '2026-10-23 10:00-03' end, 'nunca');
  return v_os;
end $f$;
create function pg_temp.aloc(p_os uuid, p_payee uuid, p_dia date, p_turno text, p_fonte text default null) returns void language sql as $f$
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte)
  values (p_os, p_payee, p_dia, p_turno, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-10-29 16:30-03', p_fonte)
$f$;
create function pg_temp.fora(p_payee uuid, p_de date, p_ate date, p_turno text default null) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota)
  values (p_payee, daterange(p_de, p_ate, '[]'), p_turno, 'indisponivel', 'dono', 'teste P9')
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
-- O corpo sem os blocos deste pacote ("-- FASE 7: (7a P9 … -- FASE 7: fim"; os das etapas de antes ficam).
create function pg_temp.sem_p9(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 7: \(7a P9' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 7: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;
-- O que o gestor não pode escrever em teste: o plano, as propostas, as perguntas e as ações.
create function pg_temp.escritas() returns text language sql stable as $f$
  select concat_ws(' / ', (select md5(coalesce(string_agg(a.id::text || a.estado, ',' order by a.id), '')) from public.agenda_alocacoes a),
                   (select count(*) from public.agenda_propostas), (select count(*) from public.agenda_perguntas),
                   (select count(*) from public.agenda_acoes))
$f$;

-- ── V0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura, quem, definer, vol) as (values
  ('public._agenda_gestor_reparo(uuid, date, timestamptz)', 'ninguem', false, 's'),
  ('public._agenda_gestor_corte(uuid, date, timestamptz)', 'ninguem', false, 's'),
  ('public._agenda_gestor_perguntas_da_revisao(uuid, date, timestamptz, boolean)', 'ninguem', false, 'v'),
  ('public._agenda_gestor_revisao(date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_gestor_reparar(uuid, date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_gestor_reestimar(uuid, date, timestamptz, uuid)', 'ninguem', true, 'v'),
  ('public.agenda_replanejar(uuid[], text, text, date, timestamptz, uuid)', 'servico', true, 'v'),
  ('public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz)', 'servico', true, 'v'),
  ('public._agenda_gestor_sombra(date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'ninguem', true, 'v'))
insert into _resultado
select 'V0a as portas: as contas da escada e do corte, as perguntas e o passo da revisão invoker e sem grant; o conserto e o corte aplicados definer e sem grant a ninguém (nem service_role); as 4 recriadas como eram (replanejar e aplicar só service_role; a sombra e o despacho para ninguém); nunca anon; volatilidade e definer como devem; search_path fixo',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and not has_function_privilege('authenticated', f.assinatura, 'execute')
                and has_function_privilege('service_role', f.assinatura, 'execute') = (f.quem = 'servico')
                and p.prosecdef = f.definer and p.provolatile::text = f.vol
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute')
                                              or has_function_privilege('service_role', f.assinatura, 'execute') <> (f.quem = 'servico')
                                              or p.prosecdef <> f.definer or p.provolatile::text <> f.vol)
  from f join pg_proc p on p.oid = f.assinatura::regprocedure;

-- ── V1 a V6: com as fixtures (o replay de 29/10 e a sintética, por cima) ──────────────────────────────────
do $fx$
declare
  v_res    jsonb := '[]'::jsonb;
  c_qui    constant date := date '2026-10-29';
  c_quia   constant timestamptz := timestamptz '2026-10-29 16:52-03';
  c_sex    constant date := date '2026-10-30';
  c_sexa   constant timestamptz := timestamptz '2026-10-30 10:07-03';
  c_sexr   constant timestamptz := timestamptz '2026-10-30 16:52-03';
  c_ursula constant text := 'Úrsula (OS-97004): o orçamento mudou depois que você disse 2 dias (agora são R$ 3.056 de mão de obra). Pela minha conta seriam 4 dias. Se você não me disser nada até sex 30/10 às 18:00, fico com os 2 dias. 1) Fique com 2 dias (recomendo); 2) Use 4 dias.';
  c_rodrigo constant text := 'O diagnóstico de Rodrigo (OS-00096) foi feito qua 04/11. 1) Terminou: use *concluiu Rodrigo*; 2) Achou mais serviço: me diga o que é e quantos dias.';
  v_adm    uuid;
  v_joao   uuid;
  v_rob    uuid;
  v_dono   uuid;
  v_len    uuid;
  v_urs    uuid;
  v_rod    uuid;
  v_w      uuid;
  v_abel   uuid;
  v_bento  uuid;
  v_davi   uuid;
  v_caio   uuid;
  v_q      uuid;
  v_q2     uuid;
  v_acao   uuid;
  v_pl0    text;
  v_n      int;
  v_n2     int;
  v_t      text;
  v_t2     text;
  v_t3     text;
  v_b      boolean;
  v_b2     boolean;
  r        jsonb;
  r2       jsonb;
  d        jsonb;
  x        record;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('V1 a V6 (as fixtures da 7a)', true,
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
  v_dono := public._agenda_dono(null);
  v_len := pg_temp.os('OS-00074');
  v_urs := pg_temp.os('OS-97004');
  v_rod := pg_temp.os('OS-00096');
  v_w := pg_temp.os('OS-97006');

  -- ── V1. Uma vez por dia útil, no 1º tique a partir das 16:45 ──────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado');
    r := public.agenda_gestor_rodar(c_qui, timestamptz '2026-10-29 16:37-03');
    v_b := not (r -> 'contagens' ? 'revisao');
    r := public.agenda_gestor_rodar(c_qui, c_quia);
    v_t := r #>> '{contagens,revisao,modo}';
    v_n := (r #>> '{contagens,revisao,encaixe,candidatas}')::int;
    r2 := public.agenda_gestor_rodar(c_qui, timestamptz '2026-10-29 17:07-03');
    v_b2 := not (r2 -> 'contagens' ? 'revisao');
    r := public.agenda_gestor_rodar(date '2026-10-31', timestamptz '2026-10-31 16:52-03');
    v_b2 := v_b2 and not (r -> 'contagens' ? 'revisao');
    -- a função sozinha: desligada e no sábado
    update public.agenda_config set modo_revisao_diaria = 'desligado' where id;
    r := public._agenda_gestor_revisao(c_qui, c_quia);
    update public.agenda_config set modo_revisao_diaria = 'ligado' where id;
    r2 := public._agenda_gestor_revisao(date '2026-10-31', timestamptz '2026-10-31 16:52-03');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V1a a revisão roda na rodada do gestor uma vez por dia útil: não às 16:37, sim no 1º tique a partir das 16:45 (16:52, ligada, com o encaixe), não no tique seguinte (17:07) nem no sábado; a função sozinha, desligada ou no sábado = {pulado}',
    v_b and v_t = 'ligado' and v_n > 0 and v_b2 and (r ->> 'pulado')::boolean and r ->> 'motivo' = 'desligado'
    and (r2 ->> 'pulado')::boolean and r2 ->> 'motivo' = 'não é dia útil',
    concat_ws(' | ', v_t, v_n, r::text, r2::text));

  -- ── V2. O reestimar ──────────────────────────────────────────────────────────────────────────────────────
  -- (a) a sobra: o Lenine marcado pela estimativa (6 dias, qua 04 a qua 11/11, abre e fecha) e o orçamento cai para 4 diárias
  begin
    perform pg_temp.modos('ligado');
    r := public._agenda_gestor_revisao(c_qui, c_quia);
    v_t := pg_temp.vig(v_len);
    update public.service_order_services
       set line_total = round(line_total * 3056 / 4560, 2), unit_price_snapshot = round(unit_price_snapshot * 3056 / 4560, 2)
     where service_order_id = v_len;
    r := public._agenda_gestor_revisao(c_sex, c_sexr);
    v_t2 := pg_temp.vig(v_len);
    select a.* into x from public.agenda_acoes a where a.service_order_id = v_len and a.tipo = 'reestimar';
    v_n := (select count(*) from public.agenda_alocacoes a where a.service_order_id = v_len and a.cancelada_motivo = 'reestimada');
    d := (select e from jsonb_array_elements(r #> '{reestimar,cortes}') e where (e ->> 'os')::uuid = v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V2a dias a mais pela estimativa (o orçamento do Lenine caiu para 4 diárias; o plano tem 6 dias): na revisão saem os 4 últimos meios-dias (ter 10 e qua 11/11) com o motivo reestimada, o fechamento do dono volta no novo último (seg 09/11 à tarde) e a ação reestimar ("Lenine (OS-00074): o orçamento mudou e agora estimo 4 dias (eram 6). Tirei ter 10/11 e qua 11/11."), da vigia e desfazível',
    v_t like 'Roberto 2026-11-04 manha | Gustavo 2026-11-04 manha abertura | %| Roberto 2026-11-11 tarde | Gustavo 2026-11-11 tarde fechamento'
    and v_t2 = 'Roberto 2026-11-04 manha | Gustavo 2026-11-04 manha abertura | Roberto 2026-11-04 tarde | Roberto 2026-11-05 manha | Roberto 2026-11-05 tarde | Roberto 2026-11-06 manha | Roberto 2026-11-06 tarde | Roberto 2026-11-09 manha | Roberto 2026-11-09 tarde | Gustavo 2026-11-09 tarde fechamento'
    and x.texto = 'Lenine (OS-00074): o orçamento mudou e agora estimo 4 dias (eram 6). Tirei ter 10/11 e qua 11/11.'
    and x.origem = 'vigia' and x.executada and x.desfazivel_ate is not null and v_n = 5
    and (d ->> 'reestimado')::boolean and d ->> 'texto' like 'Mudei: Lenine (OS-00074): o orçamento mudou%*desfaz Lenine* volta como estava.',
    concat_ws(' || ', v_t2, x.texto, v_n, d::text));
  -- o corte sozinho e o desfaz: volta como estava (os 4 meios-dias e o fechamento de qua 11/11)
  begin
    perform pg_temp.modos('ligado');
    r := public._agenda_gestor_revisao(c_qui, c_quia);
    v_t := pg_temp.vig(v_len);
    update public.service_order_services
       set line_total = round(line_total * 3056 / 4560, 2), unit_price_snapshot = round(unit_price_snapshot * 3056 / 4560, 2)
     where service_order_id = v_len;
    r := public._agenda_gestor_reestimar(v_len, c_sex, c_sexr);
    v_acao := (r ->> 'acao_ids')::jsonb ->> 0;
    r2 := public.agenda_desfazer(v_acao, v_adm, 'dono', c_sex, timestamptz '2026-10-30 17:10-03');
    v_t3 := pg_temp.vig(v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V2a2 o *desfaz* da ação reestimar volta como estava (os 4 meios-dias e o fechamento do dono em qua 11/11)',
    (r ->> 'reestimado')::boolean and coalesce((r2 ->> 'ok')::boolean, false) and v_t3 = v_t,
    concat_ws(' || ', left(r::text, 200), left(r2::text, 200), v_t3));
  -- (b) o que pode sair e o que não: o congelado (o Caio, pela estimativa, 1 dia de orçamento e 3 no plano, sem o dono) e o dia
  -- avisado (a ficha do Roberto de qua 11/11, no Lenine)
  begin
    perform pg_temp.modos('ligado');
    v_caio := pg_temp.nova_os('97203', 'Caio', 1, false);
    perform pg_temp.aloc(v_caio, v_rob, g::date, t, 'orcamento')
       from generate_series(date '2026-11-16', date '2026-11-18', interval '1 day') g, unnest(array['manha', 'tarde']) t;
    -- hoje é seg 16/11 de manhã (o congelado vai até ter 17/11): só qua 18/11 pode sair
    r2 := public._agenda_gestor_corte(v_caio, date '2026-11-16', timestamptz '2026-11-16 07:30-03');
    r := public._agenda_gestor_revisao(c_qui, c_quia);
    update public.service_order_services
       set line_total = round(line_total * 3056 / 4560, 2), unit_price_snapshot = round(unit_price_snapshot * 3056 / 4560, 2)
     where service_order_id = v_len;
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
    values (v_rob, date '2026-11-11', 'ficha', 'ligado', 'Amanhã: Lenine.', timestamptz '2026-11-10 19:30-03', 'enfileirada', 'p9:ficha:rob:1111');
    r := public._agenda_gestor_corte(v_len, c_sex, c_sexr);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V2b o corte para no 1º meio-dia que não pode sair: com hoje seg 16/11 o congelado (ter 17/11) fica e só qua 18/11 sai ("Caio (OS-97203): o orçamento mudou e agora estimo 1 dia (eram 3). Tirei qua 18/11."; ficam 2 meios-dias a mais); com a ficha de qua 11/11 do Lenine já enfileirada (o dia avisado à equipe), nada sai e o que sobra fica dito (ficou 4)',
    (r2 ->> 'cortar')::int = 2 and (r2 ->> 'ficou')::int = 2
    and r2 ->> 'texto' = 'Caio (OS-97203): o orçamento mudou e agora estimo 1 dia (eram 3). Tirei qua 18/11.'
    and (r ->> 'cortar')::int = 0 and r ->> 'motivo' = 'nada_pode_sair' and (r ->> 'ficou')::int = 4,
    left((r2 - 'itens')::text, 400) || ' | ' || left(r::text, 300));
  -- (c) a falta: o Davi (pela estimativa, 1 dia com o Roberto em seg 30/11) e o orçamento ganha outra linha (2 dias): o encaixe
  -- acrescenta o que falta
  begin
    perform pg_temp.modos('ligado');
    v_davi := pg_temp.nova_os('97204', 'Davi', 1, false);
    perform pg_temp.aloc(v_davi, v_rob, date '2026-11-30', 'manha', 'orcamento');
    perform pg_temp.aloc(v_davi, v_rob, date '2026-11-30', 'tarde', 'orcamento');
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                               unit_price_snapshot, line_total, created_at, updated_at)
    values (md5('p9:srv2:97204')::uuid, v_davi, null, 'Ajuste do quadro', 'unit', 1, 764, 764,
            timestamptz '2026-10-30 10:00-03', timestamptz '2026-10-30 10:00-03');
    r := public._agenda_gestor_revisao(c_sex, c_sexr);
    v_t := pg_temp.vig(v_davi);
    d := (select e from jsonb_array_elements(r #> '{encaixe,por_os}') e where (e ->> 'os')::uuid = v_davi);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V2c dias a menos pela estimativa (o orçamento do Davi ganhou outra linha: 2 diárias): ele entra no encaixe da revisão (faltando) e o motor acrescenta o dia que falta logo depois (ter 01/12, com quem está livre: o João)',
    v_t = 'Roberto 2026-11-30 manha | Roberto 2026-11-30 tarde | João 2026-12-01 manha | João 2026-12-01 tarde'
    and (d ->> 'faltava')::boolean and d ->> 'resultado' = 'marcada'
    and exists (select 1 from jsonb_array_elements(r #> '{reestimar,faltando}') e where (e ->> 'os')::uuid = v_davi),
    concat_ws(' || ', v_t, d::text, left((r -> 'reestimar')::text, 300)));
  -- (d) os dias do dono e o orçamento mudado depois (a Úrsula: 2 dias ditos em 22/10; a linha mexida depois; a conta dá 4)
  begin
    perform pg_temp.modos('ligado');
    update public.service_order_services set updated_at = timestamptz '2026-10-28 10:00-03' where service_order_id = v_urs;
    r := public._agenda_gestor_revisao(c_qui, c_quia);
    select q.* into x from public.agenda_perguntas q where q.tipo = 'reestimar' and q.service_order_id = v_urs;
    v_q := x.id;
    -- vista no fechamento das 17:30; sem resposta até sex 30/10 18:00, ficam os 2 dias do dono
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = timestamptz '2026-10-29 17:30-03', mostrada_via = 'fechamento'
     where id = v_q;
    r := public._agenda_gestor_vetos(c_sex, timestamptz '2026-10-30 18:07-03');
    select concat_ws(' | ', q.estado, q.opcao_escolhida, q.resolvida_motivo) into v_t from public.agenda_perguntas q where q.id = v_q;
    select concat_ws(' ', pl.dias, pl.estimativa_fonte) into v_t2 from public.os_planejamento pl where pl.service_order_id = v_urs;
    -- o mesmo orçamento: a revisão seguinte não pergunta de novo; o orçamento que muda de novo pergunta de novo
    r2 := public._agenda_gestor_revisao(date '2026-11-03', timestamptz '2026-11-03 16:52-03');
    v_n := (select count(*) from public.agenda_perguntas q where q.tipo = 'reestimar' and q.service_order_id = v_urs);
    update public.service_order_services set line_total = 3820, unit_price_snapshot = 3820, updated_at = timestamptz '2026-11-03 10:00-03'
     where service_order_id = v_urs;
    r2 := public._agenda_gestor_revisao(date '2026-11-04', timestamptz '2026-11-04 16:52-03');
    v_n2 := (select count(*) from public.agenda_perguntas q where q.tipo = 'reestimar' and q.service_order_id = v_urs and q.estado = 'aberta');
    v_t3 := (select q.texto from public.agenda_perguntas q where q.tipo = 'reestimar' and q.service_order_id = v_urs and q.estado = 'aberta');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V2d os dias do dono e o orçamento mudado depois (Úrsula): a pergunta reestimar com o texto da §6.3 (sem o valor de antes), o prazo sex 30/10 18:00 e a opção 1 sem resposta; vencida e vista, ficam os 2 dias do dono ("fiquei com os dias que você disse"); o mesmo orçamento não pergunta de novo; o orçamento que muda de novo pergunta de novo (5 dias)',
    x.texto = c_ursula and x.estado = 'aberta' and x.modo = 'ligado' and not x.critica and x.opcao_padrao = 1
    and x.veto_ate = timestamptz '2026-10-30 18:00-03' and x.recomendacao = 1
    and v_t = 'resolvida | 1 | sem resposta até sex 30/10 18:00: fiquei com os dias que você disse' and v_t2 = '2.0 dono'
    and v_n = 1 and v_n2 = 1 and v_t3 like 'Úrsula (OS-97004): o orçamento mudou depois que você disse 2 dias (agora são R$ 3.820 de mão de obra). Pela minha conta seriam 5 dias.%',
    concat_ws(' || ', x.texto, v_t, v_t2, v_n, v_n2, v_t3));
  -- (e) a opção 2: os dias da conta ficam aceitos e a agenda acompanha; o desfaz volta os do dono
  begin
    perform pg_temp.modos('ligado');
    v_bento := pg_temp.nova_os('97202', 'Bento', 1);
    perform pg_temp.aloc(v_bento, v_rob, date '2026-11-23', 'manha');
    perform pg_temp.aloc(v_bento, v_rob, date '2026-11-23', 'tarde');
    update public.service_order_services set line_total = 382, unit_price_snapshot = 382, updated_at = timestamptz '2026-10-29 10:00-03'
     where service_order_id = v_bento;
    r := public._agenda_gestor_revisao(c_qui, c_quia);
    select q.id into v_q from public.agenda_perguntas q where q.tipo = 'reestimar' and q.service_order_id = v_bento and q.estado = 'aberta';
    r := public.agenda_decidir(v_q, 2::smallint, v_adm, 'whatsapp', '2', c_qui, timestamptz '2026-10-29 17:40-03');
    select concat_ws(' ', pl.dias, pl.estimativa_fonte) into v_t from public.os_planejamento pl where pl.service_order_id = v_bento;
    v_t2 := pg_temp.vig(v_bento);
    select a.id into v_acao from public.agenda_acoes a where a.service_order_id = v_bento and a.tipo = 'estimar';
    v_n := (select count(*) from public.agenda_acoes a where a.service_order_id = v_bento and a.tipo = 'reestimar' and a.origem = 'dono');
    r2 := public.agenda_desfazer(v_acao, v_adm, 'dono', c_qui, timestamptz '2026-10-29 17:50-03');
    select concat_ws(' ', pl.dias, pl.estimativa_fonte) into v_t3 from public.os_planejamento pl where pl.service_order_id = v_bento;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V2e a opção 2 da pergunta reestimar (Bento: o dono disse 1 dia; o orçamento caiu para meio dia): os dias da conta ficam gravados com o sim do dono (0,5, a fonte orcamento) com a ação estimar do dono, a agenda acompanha na hora (o corte do dono tira seg 23/11 à tarde) e o desfaz da estimar volta o 1 dia do dono',
    r ->> 'texto' like 'Combinado, Bento: agora conto meio dia, pela minha conta do orçamento. *desfaz Bento* volta. Mudei: Bento (OS-97202): o orçamento mudou e agora estimo meio dia (eram 1). Tirei seg 23/11 à tarde.%'
    and v_t = '0.5 orcamento' and v_t2 = 'Roberto 2026-11-23 manha' and v_n = 1 and coalesce((r2 ->> 'ok')::boolean, false)
    and v_t3 = '1.0 dono',
    concat_ws(' || ', r ->> 'texto', v_t, v_t2, v_n, left(r2::text, 200), v_t3));

  -- ── V3. A escada de reparo ──────────────────────────────────────────────────────────────────────────────
  -- (a) degrau 1: o João não vem ter 03/11 de manhã (o Wagner): o Roberto no lugar, no mesmo meio-dia
  begin
    perform pg_temp.modos('ligado');
    perform pg_temp.fora(v_joao, date '2026-11-03', date '2026-11-03', 'manha');
    r := public.agenda_replanejar(array[v_w], 'pessoa', 'vigia', c_sex, c_sexa, null);
    v_t := pg_temp.vig(v_w);
    select a.* into x from public.agenda_acoes a where a.service_order_id = v_w and a.tipo = 'reparar';
    v_acao := x.id;
    v_b := exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_w and a.payee_id = v_rob
                    and a.estado = 'fixada' and a.fixado_por = 'congelamento' and a.duracao_fonte = 'dono')
           and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_w and a.payee_id = v_joao
                        and a.estado = 'cancelada' and a.cancelada_motivo = 'pessoa');
    v_n := (select count(*) from public.agenda_propostas p where p.escopo = 'replano' and p.criada_por = 'vigia'
              and p.parametros #>> '{gestor,tipo}' = 'reparar' and p.estado = 'aplicada');
    -- (g) o desfaz da ação reparar volta como estava
    r2 := public.agenda_desfazer(v_acao, v_adm, 'dono', c_sex, timestamptz '2026-10-30 10:30-03');
    v_t2 := pg_temp.vig(v_w);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V3a degrau 1 (pessoa): o João não vem ter 03/11 de manhã — o Roberto no mesmo meio-dia (fixado pelo congelado: ter 03/11 é o próximo dia útil; o evento real deixa), sem o motor; a ação reparar da vigia, desfazível, com a frase da §6.4; a proposta replano da vigia aplicada; o texto da volta diz o *desfaz*',
    r ->> 'texto' = 'Mudei: Wagner ter 03/11 de manhã: troquei João por Roberto (João não vem). *desfaz Wagner* volta como estava.'
    and v_t = 'Roberto 2026-11-03 manha' and v_b and x.texto = 'Wagner ter 03/11 de manhã: troquei João por Roberto (João não vem).'
    and x.origem = 'vigia' and x.executada and x.desfazivel_ate is not null and v_n = 1
    and jsonb_array_length(r -> 'escada') = 1 and r -> 'escada' -> 0 ->> 'degrau' = 'pessoa',
    concat_ws(' || ', r ->> 'texto', v_t, x.texto, v_n));
  v_res := pg_temp.ok(v_res, 'V3g o *desfaz* da ação reparar volta como estava (o João de novo em ter 03/11 de manhã; o Roberto sai)',
    coalesce((r2 ->> 'ok')::boolean, false) and v_t2 = 'João 2026-11-03 manha', concat_ws(' || ', left(r2::text, 300), v_t2));
  -- (b) degrau 2: o Abel (meio dia com o Roberto em qua 18/11 de manhã); o Roberto não vem de manhã e o João não vem no dia
  begin
    perform pg_temp.modos('ligado');
    v_abel := pg_temp.nova_os('97201', 'Abel', 0.5);
    perform pg_temp.aloc(v_abel, v_rob, date '2026-11-18', 'manha');
    perform pg_temp.fora(v_rob, date '2026-11-18', date '2026-11-18', 'manha');
    perform pg_temp.fora(v_joao, date '2026-11-18', date '2026-11-18');
    r := public.agenda_replanejar(array[v_abel], 'pessoa', 'vigia', c_sex, c_sexa, null);
    v_t := pg_temp.vig(v_abel);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V3b degrau 2 (turno): sem ninguém de manhã em qua 18/11, o Abel passa para a tarde do mesmo dia com o Roberto ("Abel qua 18/11: passei a manhã para a tarde, com Roberto.")',
    r ->> 'texto' = 'Mudei: Abel qua 18/11: passei a manhã para a tarde, com Roberto. *desfaz Abel* volta como estava.'
    and v_t = 'Roberto 2026-11-18 tarde' and r -> 'escada' -> 0 ->> 'degrau' = 'turno',
    concat_ws(' || ', r ->> 'texto', v_t));
  -- (c) degrau 3: o Bento (o Roberto em ter 17 e qui 19/11 de manhã); ninguém vem em ter 17/11
  begin
    perform pg_temp.modos('ligado');
    v_bento := pg_temp.nova_os('97202', 'Bento', 1);
    perform pg_temp.aloc(v_bento, v_rob, date '2026-11-17', 'manha');
    perform pg_temp.aloc(v_bento, v_rob, date '2026-11-19', 'manha');
    perform pg_temp.fora(v_rob, date '2026-11-17', date '2026-11-17');
    perform pg_temp.fora(v_joao, date '2026-11-17', date '2026-11-17');
    r2 := public._agenda_gestor_reparo(v_bento, c_sex, c_sexa);
    r := public.agenda_replanejar(array[v_bento], 'pessoa', 'vigia', c_sex, c_sexa, null);
    v_t := pg_temp.vig(v_bento);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V3c degrau 3 (dia): ninguém em ter 17/11 (nem de tarde) — o Bento passa para qua 18/11 de manhã com o mesmo Roberto (o dia que não deixa o serviço parado; seg 16/11 deixaria 2 dias parados no meio): "Bento: passei ter 17/11 de manhã para qua 18/11 de manhã (mesma semana; o fim não muda)."',
    r ->> 'texto' = 'Mudei: Bento: passei ter 17/11 de manhã para qua 18/11 de manhã (mesma semana; o fim não muda). *desfaz Bento* volta como estava.'
    and v_t = 'Roberto 2026-11-18 manha | Roberto 2026-11-19 manha' and r -> 'escada' -> 0 ->> 'degrau' = 'dia'
    and r2 ->> 'fim_antes' = '2026-11-19' and r2 ->> 'fim_depois' = '2026-11-19',
    concat_ws(' || ', r ->> 'texto', v_t, (r2 - 'itens')::text));
  -- (d) o 4º degrau é o motor: o Roberto não vem ter 03/11 e o João não vem de manhã — na semana do Wagner não há conserto
  begin
    perform pg_temp.modos('ligado');
    perform pg_temp.fora(v_rob, date '2026-11-03', date '2026-11-03');
    perform pg_temp.fora(v_joao, date '2026-11-03', date '2026-11-03', 'manha');
    r2 := public._agenda_gestor_reparo(v_w, c_sex, c_sexa);
    r := public.agenda_replanejar(array[v_w], 'pessoa', 'vigia', c_sex, c_sexa, null);
    v_n := (select count(*) from public.agenda_acoes a where a.service_order_id = v_w and a.tipo = 'reparar');
    v_t := (select a.tipo from public.agenda_acoes a where a.service_order_id = v_w and a.tipo not in ('status') order by a.criada_em desc limit 1);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V3d o 4º degrau é o motor: sem conserto na semana (a conta: sem_lugar, o meio-dia que sobrou), nenhuma ação reparar; o motor remarca como sempre (a ação dele, sem a escada na saída)',
    not (r2 ->> 'reparavel')::boolean and r2 ->> 'motivo' = 'sem_lugar' and jsonb_array_length(r2 -> 'sobrou') = 1
    and v_n = 0 and v_t = 'mover' and not (r ? 'escada') and (r ->> 'ok')::boolean,
    concat_ws(' || ', (r2 - 'itens')::text, v_n, v_t, left(r ->> 'texto', 200)));
  -- (e) o pedido do cliente pula a escada
  begin
    perform pg_temp.modos('ligado');
    perform pg_temp.fora(v_joao, date '2026-11-03', date '2026-11-03', 'manha');
    r := public.agenda_replanejar(array[v_w], 'o cliente pediu outro dia', 'vigia', c_sex, c_sexa, null);
    v_n := (select count(*) from public.agenda_acoes a where a.service_order_id = v_w and a.tipo = 'reparar');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V3e "o cliente pediu outro dia" vai direto ao motor (nenhuma ação reparar, sem escada na saída)',
    v_n = 0 and not (r ? 'escada'), concat_ws(' || ', v_n, left(r ->> 'texto', 200)));
  -- (f) a onda vale para a escada: com gestor_k_dias_avisados 0, o dia avisado do João (a ficha de ter 03/11) já passa do
  -- limite: nada é consertado e tudo vai ao motor, que pergunta
  begin
    perform pg_temp.modos('ligado');
    update public.agenda_config set gestor_k_dias_avisados = 0 where id;
    perform pg_temp.fora(v_joao, date '2026-11-03', date '2026-11-03', 'manha');
    v_pl0 := pg_temp.plano();
    r := public.agenda_replanejar(array[v_w], 'pessoa', 'vigia', c_sex, c_sexa, null);
    v_n := (select count(*) from public.agenda_acoes a where a.service_order_id = v_w and a.tipo = 'reparar');
    v_n2 := (select count(*) from public.agenda_perguntas q where q.tipo = 'onda' and q.estado = 'aberta');
    v_b := pg_temp.plano() = v_pl0;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V3f a onda vale para a escada: acima do limite de dias avisados mexidos, a escada não conserta nada e o motor pergunta (a pergunta crítica onda; o plano igual)',
    v_n = 0 and v_n2 = 1 and v_b and (r ->> 'onda')::boolean and not (r ? 'escada'),
    concat_ws(' || ', v_n, v_n2, v_b, left(r::text, 300)));
  -- (h) as duas juntas: o Wagner tem conserto (degrau 1) e o Abel não (ninguém na semana de 16/11): a escada conserta um, o
  -- motor remarca o outro, e a saída junta os dois (a escada primeiro)
  begin
    perform pg_temp.modos('ligado');
    v_abel := pg_temp.nova_os('97201', 'Abel', 0.5);
    perform pg_temp.aloc(v_abel, v_rob, date '2026-11-18', 'manha');
    perform pg_temp.fora(v_joao, date '2026-11-03', date '2026-11-03', 'manha');
    perform pg_temp.fora(v_rob, date '2026-11-16', date '2026-11-20');
    perform pg_temp.fora(v_joao, date '2026-11-16', date '2026-11-20');
    r := public.agenda_replanejar(array[v_w, v_abel], 'pessoa', 'vigia', c_sex, c_sexa, null);
    v_n := (select count(*) from public.agenda_acoes a where a.service_order_id = v_w and a.tipo = 'reparar');
    v_n2 := (select count(*) from public.agenda_acoes a where a.service_order_id = v_abel and a.tipo in ('mover', 'cancelar'));
    v_t := pg_temp.vig(v_w);
    v_b := (select bool_and(exists (select 1 from public.agenda_acoes a where a.id = x2::uuid))
              from jsonb_array_elements_text(r -> 'acoes') x2);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V3h as duas juntas: a escada conserta o Wagner (o Roberto no lugar do João), o motor remarca o Abel (sem ninguém na semana), e a saída junta os dois — o texto da escada primeiro, as ações das duas, a escada na saída',
    v_n = 1 and v_n2 = 1 and v_t = 'Roberto 2026-11-03 manha' and v_b and jsonb_array_length(r -> 'escada') = 1
    and jsonb_array_length(r -> 'acoes') >= 2
    and r ->> 'texto' like 'Mudei: Wagner ter 03/11 de manhã: troquei João por Roberto (João não vem). *desfaz Wagner* volta como estava. Mudei: Abel (OS-97201): %',
    concat_ws(' || ', v_n, v_n2, v_t, left(r::text, 500)));

  -- ── V4. A proposta montada passa nas 14 regras (e a errada não) ──────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado');
    perform pg_temp.fora(v_joao, date '2026-11-03', date '2026-11-03', 'manha');
    r := public._agenda_gestor_reparo(v_w, c_sex, c_sexa);
    d := public._agenda_validar_itens(r -> 'itens', '{"p_restricoes": {}}'::jsonb, c_sex, c_sexa, true, null);
    -- a mesma proposta com o Xavier do João no lugar do Roberto (o João não vem de manhã) e com o João da tarde (choque)
    r2 := public._agenda_validar_itens(
            jsonb_set(r -> 'itens', '{1,alocacoes,0,payee_id}', to_jsonb(v_joao)), '{"p_restricoes": {}}'::jsonb, c_sex, c_sexa, true, null);
    v_t := (select string_agg(e ->> 'regra', ',' order by e ->> 'regra') from jsonb_array_elements(r2) e);
    v_t2 := (select string_agg(i ->> 'op', ',' order by k) from jsonb_array_elements(r -> 'itens') with ordinality t(i, k));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V4a a proposta que a escada monta (um cancelar com a violada, motivo pessoa; um criar com o motivo "degrau pessoa", o evento real e a fonte da OS) passa nas 14 regras do motor; com o João, que não vem, no lugar do Roberto, a regra 1 recusa',
    jsonb_array_length(d) = 0 and v_t like '%1%' and v_t2 = 'cancelar,criar'
    and r -> 'itens' -> 1 -> 'motivos' = '["degrau pessoa"]'::jsonb and (r -> 'itens' -> 1 ->> 'evento_real')::boolean
    and r -> 'itens' -> 0 ->> 'motivo' = 'pessoa' and (r -> 'itens' -> 0 ->> 'violada')::boolean,
    concat_ws(' || ', d::text, v_t, v_t2));

  -- ── V5. O reavaliar ─────────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado');
    perform set_config('agenda.hoje', '2026-11-05', true);
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em,
                                         resultado, resultado_em, resultado_via)
    values (v_rod, v_rob, date '2026-11-04', 'manha', 'turno', 'diagnostico', 'publicada', 'motor', timestamptz '2026-10-29 16:30-03',
            'cumprido', timestamptz '2026-11-04 12:00-03', 'tela');
    r := public._agenda_gestor_perguntas_da_revisao(v_rod, date '2026-11-04', timestamptz '2026-11-04 16:52-03', true);
    r2 := public._agenda_gestor_revisao(date '2026-11-05', timestamptz '2026-11-05 16:52-03');
    select q.* into x from public.agenda_perguntas q where q.tipo = 'reavaliar' and q.service_order_id = v_rod;
    d := public.agenda_decidir(x.id, 1::smallint, v_adm, 'whatsapp', '1', date '2026-11-05', timestamptz '2026-11-05 17:40-03');
    v_t := (select q.estado from public.agenda_perguntas q where q.id = x.id);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V5a o reavaliar: o diagnóstico do Rodrigo feito qua 04/11 não pergunta no mesmo dia; na revisão de qui 05/11 (1 dia útil depois, ainda na carteira) a pergunta com o texto da §6.3, sem prazo e sem opção padrão; a resposta 1 diz "Use *concluiu Rodrigo*." e responde a pergunta',
    jsonb_typeof(r -> 'reavaliar') = 'null' and x.texto = c_rodrigo and x.veto_ate is null and x.opcao_padrao is null
    and x.modo = 'ligado' and x.chave = 'reavaliar:' || v_rod || ':2026-11-04'
    and d ->> 'texto' = 'Use *concluiu Rodrigo*.' and v_t = 'respondida' and (r2 ->> 'reavaliar')::int = 1,
    concat_ws(' || ', x.texto, d::text, v_t));
  begin
    perform pg_temp.modos('ligado');
    perform set_config('agenda.hoje', '2026-11-05', true);
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em,
                                         resultado, resultado_em, resultado_via)
    values (v_rod, v_rob, date '2026-11-04', 'manha', 'turno', 'diagnostico', 'publicada', 'motor', timestamptz '2026-10-29 16:30-03',
            'cumprido', timestamptz '2026-11-04 12:00-03', 'tela');
    r2 := public._agenda_gestor_revisao(date '2026-11-05', timestamptz '2026-11-05 16:52-03');
    select q.id into v_q from public.agenda_perguntas q where q.tipo = 'reavaliar' and q.service_order_id = v_rod;
    d := public.agenda_decidir(v_q, 2::smallint, v_adm, 'whatsapp', '2', date '2026-11-05', timestamptz '2026-11-05 17:40-03');
    r := public._agenda_gestor_decidir(v_q, 1::smallint, null, 'prazo', null, date '2026-11-05', timestamptz '2026-11-05 18:07-03');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V5b a resposta 2 pede o que mais tem e quantos dias ("Me diga o que mais tem para fazer e quantos dias (ex.: ''Rodrigo 2 dias''): eu marco."); a pergunta não tem prazo',
    d ->> 'texto' = 'Me diga o que mais tem para fazer e quantos dias (ex.: ''Rodrigo 2 dias''): eu marco.'
    and not (r ->> 'ok')::boolean,
    concat_ws(' || ', d::text, r::text));

  -- ── V6. Em teste, tudo seco ──────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('sombra');
    -- o "eu marcaria" da manhã já gravado não pode sumir
    perform public._agenda_gestor_dia_gravar(c_qui, 'sombra', '{"itens": [], "md5": "do-dia"}'::jsonb, timestamptz '2026-10-29 10:00-03');
    update public.service_order_services set updated_at = timestamptz '2026-10-28 10:00-03' where service_order_id = v_urs;
    v_t := pg_temp.escritas();
    r := public._agenda_gestor_revisao(c_qui, c_quia);
    v_b := pg_temp.escritas() = v_t and coalesce(current_setting('agenda.gestor', true), '') = '';
    select g.sombra into d from public.agenda_gestor_dia g where g.dia = c_qui;
    v_t2 := (select string_agg(format('%s:%s', e ->> 'numero', e ->> 'resultado'), ' ' order by e ->> 'numero')
               from jsonb_array_elements(d #> '{revisao,encaixe}') e);
    -- o "eu marcaria" das 16:52 (no mesmo tique, depois da revisão) mantém o sombra.revisao
    perform public._agenda_gestor_sombra(c_qui, c_quia);
    select g.sombra into r2 from public.agenda_gestor_dia g where g.dia = c_qui;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V6a em teste: a revisão inteira seca — o motor com as regras do gestor só ali dentro (Lenine e Vanderlei marcados; Rodrigo, Tânia e Úrsula fora), a pergunta da Úrsula só calculada, nada gravado no plano, nas propostas, nas perguntas nem nas ações; só o diário (sombra.revisao), sem apagar o resto; a variável da simulação desligada no fim; o "eu marcaria" das 16:52 mantém o sombra.revisao',
    v_b and (r ->> 'simulacao')::boolean and v_t2 = 'OS-00069:marcada OS-00074:marcada OS-00096:fora OS-97003:fora OS-97004:fora'
    and d ->> 'md5' = 'do-dia' and jsonb_array_length(d #> '{revisao,perguntas}') = 1
    and d #>> '{revisao,perguntas,0,texto}' = c_ursula
    and r2 ? 'revisao' and r2 -> 'revisao' = d -> 'revisao' and r2 ->> 'md5' <> 'do-dia',
    concat_ws(' || ', v_b, v_t2, left(d::text, 300)));

  perform pg_temp.gravar(v_res);
end
$fx$;

-- ── V7. As cópias e o portão falso ───────────────────────────────────────────────────────────────────────
do $copias$
declare
  v_res  jsonb := '[]'::jsonb;
  v_c2   text := coalesce(current_setting('agenda_teste.mig_conferencia_fase2', true), '');
  v_c6   text := coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '');
  v_p7   text := coalesce(current_setting('agenda_teste.mig_rodada_fase7a', true), '');
  v_p8   text := coalesce(current_setting('agenda_teste.mig_encaixe_fase7a', true), '');
  r      record;
  v_novo text;
  v_n    int;
begin
  if v_c2 = '' or v_c6 = '' or v_p7 = '' or v_p8 = '' then
    insert into _resultado values ('V7a as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('agenda_replanejar', 'public.agenda_replanejar(uuid[], text, text, date, timestamptz, uuid)', v_c2, '20261025100300', 3),
      ('agenda_aplicar', 'public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz)', v_c6, '20261029100900', 1),
      ('_agenda_gestor_sombra', 'public._agenda_gestor_sombra(date, timestamptz)', v_p7, '20261031100600', 1),
      ('_agenda_gestor_decidir', 'public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', v_p8, '20261031100700', 2)
    ) t(nome, assinatura, fonte, versao, blocos)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: \(7a P9', 'g');
    v_res := pg_temp.ok(v_res,
      format('V7a %s: sem os %s blocos "-- FASE 7: (7a P9", é o corpo de %s (a mais nova antes do P9)', r.nome, r.blocos, r.versao),
      v_n = r.blocos and pg_temp.corpo(r.fonte, r.nome) <> '' and pg_temp.sem_p9(v_novo) = pg_temp.corpo(r.fonte, r.nome),
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(r.fonte, r.nome)),
             length(pg_temp.sem_p9(v_novo))));
  end loop;
  perform pg_temp.gravar(v_res);
end
$copias$;

do $portao$
declare
  v_res  jsonb := '[]'::jsonb;
  v_c2   text := coalesce(current_setting('agenda_teste.mig_conferencia_fase2', true), '');
  v_c6   text := coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '');
  c_sex  constant date := date '2026-10-30';
  c_sexa constant timestamptz := timestamptz '2026-10-30 10:07-03';
  v_dif  text;
  v_joao uuid;
  v_w    uuid;
  v_a    text;
  v_b    text;
  v_pid  uuid;
  r      record;
  x      jsonb;
begin
  if v_c2 = '' or v_c6 = '' or coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('V7b o portão falso', true, 'PULADO: sem as fixtures e as migrations como texto (rode pela bancada)');
    return;
  end if;
  if pg_temp.os('OS-97006') is null then
    execute current_setting('agenda_teste.replay2910');
    execute current_setting('agenda_teste.fase7a');
  end if;
  execute replace(pg_temp.inteira(v_c2, 'agenda_replanejar'), 'create or replace function public.agenda_replanejar(',
                  'create function pg_temp.replanejar_antes(');
  execute replace(pg_temp.inteira(v_c6, 'agenda_aplicar'), 'create or replace function public.agenda_aplicar(',
                  'create function pg_temp.aplicar_antes(');
  select id into v_joao from public.payees where name = 'João' and active;
  v_w := pg_temp.os('OS-97006');
  -- o João não vem ter 03/11 de manhã: a escada teria o que fazer
  perform pg_temp.fora(v_joao, date '2026-11-03', date '2026-11-03', 'manha');
  for r in select * from (values
             (1, 'desligado', 'desligado', false, null::text[], null::text),
             (2, 'sombra sem a simulação', 'sombra', false, null::text[], null::text),
             (3, '*gestor, só propor*', 'ligado', true, null::text[], null::text),
             (4, 'sem a regra escada', 'ligado', false,
              '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,sinal_cobrar}'::text[], null::text),
             (5, 'a revisão diária em teste', 'ligado', false, null::text[], 'sombra')
           ) t(o, nome, modo, so_propor, regras, revisao) order by o loop
    perform pg_temp.modos(r.modo, r.regras);
    update public.agenda_config set gestor_so_propor = r.so_propor, modo_revisao_diaria = coalesce(r.revisao, modo_revisao_diaria) where id;
    begin
      x := public.agenda_replanejar(array[v_w], 'pessoa', 'vigia', c_sex, c_sexa, null);
      v_a := (x - 'proposta_id' - 'acoes')::text || ' / ' || pg_temp.plano();
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    begin
      x := pg_temp.replanejar_antes(array[v_w], 'pessoa', 'vigia', c_sex, c_sexa, null);
      v_b := (x - 'proposta_id' - 'acoes')::text || ' / ' || pg_temp.plano();
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    if v_a is distinct from v_b then v_dif := concat_ws('; ', v_dif, r.nome || ' (replanejar): ' || left(v_a, 200) || ' <> ' || left(v_b, 200)); end if;
  end loop;
  -- agenda_aplicar: a proposta do motor (sem parametros.gestor) dá a mesma ação e o mesmo plano
  perform pg_temp.modos('ligado');
  begin
    v_pid := (public.agenda_propor('replano', null, null, array[v_w], '{}'::jsonb, true, 'vigia', null, c_sex, c_sexa) ->> 'proposta_id')::uuid;
    x := public.agenda_aplicar(v_pid, null, 'vigia', null, null, c_sex, c_sexa);
    v_a := (x - 'proposta_id' - 'acoes')::text || ' / ' || pg_temp.plano()
           || ' / ' || (select string_agg(a.tipo || ':' || a.texto, '; ' order by a.criada_em) from public.agenda_acoes a where a.proposta_id = v_pid);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_pid := (public.agenda_propor('replano', null, null, array[v_w], '{}'::jsonb, true, 'vigia', null, c_sex, c_sexa) ->> 'proposta_id')::uuid;
    x := pg_temp.aplicar_antes(v_pid, null, 'vigia', null, null, c_sex, c_sexa);
    v_b := (x - 'proposta_id' - 'acoes')::text || ' / ' || pg_temp.plano()
           || ' / ' || (select string_agg(a.tipo || ':' || a.texto, '; ' order by a.criada_em) from public.agenda_acoes a where a.proposta_id = v_pid);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  if v_a is distinct from v_b then v_dif := concat_ws('; ', v_dif, 'aplicar: ' || left(v_a, 200) || ' <> ' || left(v_b, 200)); end if;
  v_res := pg_temp.ok(v_res, 'V7b com o portão falso (desligado, sombra sem a simulação, *gestor, só propor*, sem a regra escada, a revisão diária em teste), agenda_replanejar dá o de antes, byte a byte (a saída e o plano); agenda_aplicar com a proposta do motor (sem parametros.gestor) também (a saída, o plano e as ações)',
    v_dif is null, coalesce(v_dif, '—'));
  perform pg_temp.gravar(v_res);
end
$portao$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
