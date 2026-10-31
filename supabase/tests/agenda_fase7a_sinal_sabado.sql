-- Prova do sinal, do sábado e do orçamento grande, Fase 7a (pacote P12, migration 20261031100900), sobre a carteira REAL de 29/10
-- (o replay) e a sintética da 7a (a Vera, OS-97005, com o sinal de R$ 1.000 combinado e não pago; o Roberto com o padrão de
-- sábado de manhã só com agenda_teste.fase7a_sabado) e uma OS do próprio teste (a Zilda, OS-97401: 2,5 dias ditos, sem o dono,
-- não antes de sex 13/11 e precisa até seg 16/11 — sem o sábado ela termina ter 17/11; com a manhã de sáb 14/11, seg 16/11).
-- bancada: depende de 20261031100900
--
--   S0 as portas e o que é (sem fixture): os 3 passos invoker, volúveis e sem grant a ninguém (nem service_role); as 3
--      recriadas com as portas de antes
--   S1 o sinal (AG7-09 "marco e cobro o sinal"): com a regra sinal_cobrar o sinal pendente não segura a OS (a Vera com os dias
--      ditos vai à classe 2, o MP à 4 estimativa; sem a regra, as duas esperando o sinal); o motor a marca e nasce a pergunta
--      sinal uma vez (o texto da §6.3, sem opções, sem prazo; o tique seguinte não repete); pago = a pergunta fecha ("o sinal
--      entrou"); nenhuma mensagem ao cliente; o dia marcado pelo dono ("está na agenda a partir de"); o orçamento esperando o
--      sinal sem recebível (o MP: sem o valor); em teste e com *gestor, só propor*, nada nasce
--   S2 o sábado (AG7-08): sem ninguém de sábado = 0; com o Roberto de sábado = a pergunta crítica (o texto da §6.3, as opções, sem
--      prazo, expira quando o sábado começa); a decisão 1 marca a manhã de sábado (o Roberto, sáb 14/11), grava a exceção "vem"
--      daquele sábado e a vigia seguinte não tira o dia (sem a exceção, tiraria: o porquê do desvio); a 2 não muda nada;
--      sabado_manha = nunca = 0 e a aberta resolvida; em teste, seco; o validador: com a variável aceita a manhã de quem tem o
--      padrão, nunca de quem não tem; sem ela, recusa (o de antes)
--   S3 os orçamentos: os 6 do real (os grandes em aberto mexidos em 30 dias), o texto, nenhuma alocação nem proposta, pela
--      agenda_encaixe_do_novo, o diário e o foco "Se aprovar:"; em teste, a conta da sombra (a variável desligada no fim)
--   S4 as cópias: as 3 recriadas sem os blocos "-- FASE 7: (7a P12" são o corpo da origem
--   S5 o de antes, byte a byte: a classe das 28 OS (o replay e a sintética) com o portão falso (desligado, sombra fora da
--      simulação, *gestor, só propor*, sem a regra) é a da definição de antes rodada como pg_temp (com controle: com a regra,
--      muda); o validador sem a variável (os itens da carteira e o do sábado) é o de antes
--   S6 a rodada acha os 3 passos (nenhum "ainda não existe"): o sinal em todo tique, o sábado e os orçamentos no diário
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_sinal_sabado.sql
--   Seguro em produção: S0 e S4 (as cópias saem PULADO sem as migrations como texto) só leem; S1, S2, S3, S5 e S6 usam as
--   fixtures e só rodam na bancada (fora dela saem PULADO). Termina em ROLLBACK.
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
-- A OS pelo número e a pessoa pelo nome (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select py.id from public.payees py where py.name = p_nome and py.active order by py.id limit 1
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- Os 5 modos do gestor (as regras todas, ou as ditas); ligado = o ligar de qui 29/10 16:46.
create function pg_temp.modos(p_modo text, p_regras text[] default null) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         marcar_regras = coalesce(p_regras, '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}')
   where id
$f$;
-- O replay e a sintética (uma vez por transação); com p_sabado, o Roberto com o padrão de sábado de manhã.
create function pg_temp.fixtures(p_sabado boolean default false) returns void language plpgsql as $f$
begin
  if pg_temp.os('OS-97006') is null then
    perform set_config('agenda_teste.fase7a_sabado', case when p_sabado then 'on' else '' end, true);
    execute current_setting('agenda_teste.replay2910');
    execute current_setting('agenda_teste.fase7a');
    perform set_config('agenda_teste.fase7a_sabado', '', true);
  end if;
end $f$;
-- A Zilda (OS-97401, do teste): 2,5 dias ditos, sem o dono, não antes de sex 13/11, precisa até seg 16/11.
create function pg_temp.zilda() returns uuid language plpgsql as $f$
declare
  v_os  uuid := 'f7a00000-0000-4000-8000-000000097401';
  v_cli uuid := 'f7a00000-0000-4000-8000-000000097402';
  v_bem uuid := 'f7a00000-0000-4000-8000-000000097403';
begin
  insert into public.clients (id, type, name) values (v_cli, 'individual', 'Zilda');
  insert into public.vessels (id, client_id, name, asset_type) values (v_bem, v_cli, 'Motorhome', 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                     created_at, updated_at, converted_to_os_at)
  values (v_os, 'OS-97401', v_cli, v_bem, 'open', 'approved', 'repair', timestamptz '2026-10-25 10:00-03',
          timestamptz '2026-10-28 10:00-03', timestamptz '2026-10-28 10:00-03');
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, created_at)
  values (md5('p12:zilda:servico')::uuid, v_os, null, 'Revisão elétrica geral', 'unit', 1, 1910, 1910,
          timestamptz '2026-10-25 10:00-03');
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, nao_antes_de,
                                      nao_antes_motivo, precisa_ate)
  values (v_os, 2.5, 'dono', timestamptz '2026-10-28 10:00-03', 'nunca', date '2026-11-13', 'o cliente chega sexta',
          date '2026-11-16');
  return v_os;
end $f$;
-- As alocações vigentes de uma OS: "dia turno presença pessoa".
create function pg_temp.alocs(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s %s %s', to_char(a.dia, 'DD/MM'), a.turno, py.name), ', '
                             order by a.dia, a.turno = 'tarde', py.name), '')
    from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
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
-- O corpo sem os blocos deste pacote ("-- FASE 7: (7a P12 … -- FASE 7: fim"; os das etapas de antes ficam).
create function pg_temp.sem_p12(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    -- (correção 2 da 7a, 20261031100985: a dupla sem a 2ª pessoa acrescentou 2 blocos "-- FASE 7: (7a correção 2" à
    -- _agenda_classe_da_os depois do P12; eles saem junto, e o resto continua sendo a cópia do P12 sobre a de antes)
    if not v_bloco and l ~ '^\s*-- FASE 7: \((7a P12|7a correção 2)' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 7: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;

-- ── S0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura, quem, definer, vol) as (values
  ('public._agenda_gestor_sinal(date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_gestor_sabado(date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_gestor_orcamentos(date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)', 'leitura', false, 's'),
  ('public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)', 'leitura', false, 's'),
  ('public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'ninguem', true, 'v'))
insert into _resultado
select 'S0 as portas: os 3 passos (sinal, sabado, orcamentos) invoker, volúveis e sem grant a ninguém (nem service_role); as 3 recriadas como eram (a classe e o validador para authenticated e service_role, STABLE; o despacho definer e sem grant); nunca anon; search_path fixo',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and has_function_privilege('authenticated', f.assinatura, 'execute') = (f.quem = 'leitura')
                and has_function_privilege('service_role', f.assinatura, 'execute') = (f.quem = 'leitura')
                and p.prosecdef = f.definer and p.provolatile::text = f.vol
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute') <> (f.quem = 'leitura')
                                              or has_function_privilege('service_role', f.assinatura, 'execute') <> (f.quem = 'leitura')
                                              or p.prosecdef <> f.definer or p.provolatile::text <> f.vol)
  from f join pg_proc p on p.oid = f.assinatura::regprocedure;

-- ── S1. O sinal ─────────────────────────────────────────────────────────────────────────────────────────────
do $s1$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-29';
  v_vera  uuid;
  v_mp    uuid;
  v_adm   uuid;
  v_p     jsonb;
  v_a     jsonb;
  r       jsonb;
  r2      jsonb;
  v_t     text;
  v_n     int;
  v_q     public.agenda_perguntas%rowtype;
  v_cli   int;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('S1 o sinal (as fixtures da 7a)', true, 'PULADO: sem agenda_teste.replay2910 e fase7a (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.fixtures();
    v_vera := pg_temp.os('OS-97005');
    v_mp := pg_temp.os('ORÇ-00095');
    select id into strict v_adm from public.app_users where role = 'admin' and active order by id limit 1;
    -- a Vera com os dias ditos (1 dia: a peça embutida não segura mais) e o sinal de R$ 1.000 pendente
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (v_vera, 1, 'dono', pg_temp.em(c_hoje, '10:00'))
    on conflict (service_order_id) do update set dias = 1, estimativa_fonte = 'dono', estimativa_em = pg_temp.em(c_hoje, '10:00');

    -- S1a a classe: com a regra o sinal não segura; sem ela (e com o gestor desligado), espera o sinal
    perform pg_temp.modos('ligado');
    v_t := (public._agenda_classe_agora(v_vera, c_hoje) ->> 'classe') || ':' || (public._agenda_classe_agora(v_vera, c_hoje) ->> 'motivo')
           || ' ' || (public._agenda_classe_agora(v_mp, c_hoje) ->> 'classe') || ':' || (public._agenda_classe_agora(v_mp, c_hoje) ->> 'motivo');
    perform pg_temp.modos('ligado', '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada}');
    v_t := v_t || ' | ' || (public._agenda_classe_agora(v_vera, c_hoje) ->> 'classe') || ':' || (public._agenda_classe_agora(v_vera, c_hoje) ->> 'motivo')
           || ' ' || (public._agenda_classe_agora(v_mp, c_hoje) ->> 'classe') || ':' || (public._agenda_classe_agora(v_mp, c_hoje) ->> 'motivo');
    perform pg_temp.modos('desligado');
    v_t := v_t || ' | ' || (public._agenda_classe_agora(v_vera, c_hoje) ->> 'classe') || ':' || (public._agenda_classe_agora(v_vera, c_hoje) ->> 'motivo');
    v_res := pg_temp.ok(v_res, 'S1a com a regra sinal_cobrar o sinal pendente não segura: a Vera (dias ditos) vai à classe 2 e o MP (só kits, sem mão de obra) à 4 estimativa; sem a regra, ou com o gestor desligado, as duas esperam o sinal',
      v_t = '2:pronta 4:estimativa | 4:sinal 4:sinal | 4:sinal', v_t);

    -- S1b o motor marca a Vera e o passo pergunta, uma vez
    perform pg_temp.modos('ligado');
    v_cli := (select count(*) from public.agenda_cliente_mensagens);
    v_p := public.agenda_propor('os', null, null, array[v_vera], '{}'::jsonb, true, 'vigia', null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    v_a := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    r := public._agenda_gestor_sinal(c_hoje, pg_temp.em(c_hoje, '16:52'));
    select * into v_q from public.agenda_perguntas q where q.tipo = 'sinal' and q.service_order_id = v_vera;
    v_res := pg_temp.ok(v_res, 'S1b o motor marca a Vera (ter 03/11) e o passo sinal abre a pergunta ao dono (o texto da §6.3; chave sinal:<os>; sem opções, sem prazo, sem opção padrão, não crítica, em ligado)',
      coalesce((v_a ->> 'ok')::boolean, false) and pg_temp.alocs(v_vera) <> ''
      and (r ->> 'novas')::int = 1 and (r ->> 'perguntas')::int = 1
      and v_q.texto = 'Marquei Vera (OS-97005) a partir de ter 03/11 e o sinal de R$ 1.000 ainda não entrou: cobre quando puder. Para o cliente eu não digo nada sobre isso.'
      and v_q.chave = 'sinal:' || v_vera and v_q.opcoes = '[]'::jsonb and v_q.veto_ate is null and v_q.opcao_padrao is null
      and not v_q.critica and v_q.modo = 'ligado' and v_q.estado = 'aberta',
      coalesce(v_q.texto, '-') || ' | ' || r::text || ' | ' || pg_temp.alocs(v_vera));
    r2 := public._agenda_gestor_sinal(c_hoje, pg_temp.em(c_hoje, '17:07'));
    v_res := pg_temp.ok(v_res, 'S1c uma vez: o tique seguinte não abre outra (a mesma aberta) e nenhuma mensagem ao cliente nasce (nem do motor, nem do passo)',
      (r2 ->> 'novas')::int = 0 and (r2 ->> 'perguntas')::int = 1
      and (select count(*) from public.agenda_perguntas q where q.tipo = 'sinal') = 1
      and (select count(*) from public.agenda_cliente_mensagens) = v_cli,
      r2::text);
    -- S1d o sinal entra: a pergunta fecha sozinha (em qualquer modo) e não volta
    update public.receivables set status = 'paid', paid_amount = amount, balance_amount = 0
     where service_order_id = v_vera and is_deposit;
    r := public._agenda_gestor_sinal(c_hoje, pg_temp.em(c_hoje, '17:22'));
    r2 := public._agenda_gestor_sinal(c_hoje, pg_temp.em(c_hoje, '17:37'));
    select * into v_q from public.agenda_perguntas q where q.tipo = 'sinal' and q.service_order_id = v_vera;
    v_res := pg_temp.ok(v_res, 'S1d o sinal pago: a pergunta fecha sozinha ("o sinal entrou") e não volta',
      v_q.estado = 'resolvida' and v_q.resolvida_motivo = 'o sinal entrou' and (r ->> 'resolvidas')::int = 1
      and (r2 ->> 'perguntas')::int = 0 and (select count(*) from public.agenda_perguntas q where q.tipo = 'sinal') = 1,
      v_q.estado || ' ' || coalesce(v_q.resolvida_motivo, '-') || ' | ' || r2::text);

    -- S1e o MP (o orçamento esperando o sinal, sem recebível): com os dias ditos, o motor o marca; a pergunta sem o valor
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (v_mp, 1, 'dono', pg_temp.em(c_hoje, '10:00'))
    on conflict (service_order_id) do update set dias = 1, estimativa_fonte = 'dono', estimativa_em = pg_temp.em(c_hoje, '10:00');
    v_p := public.agenda_propor('os', null, null, array[v_mp], '{}'::jsonb, true, 'vigia', null, c_hoje, pg_temp.em(c_hoje, '17:40'));
    v_a := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, c_hoje, pg_temp.em(c_hoje, '17:40'));
    r := public._agenda_gestor_sinal(c_hoje, pg_temp.em(c_hoje, '17:52'));
    select * into v_q from public.agenda_perguntas q where q.tipo = 'sinal' and q.service_order_id = v_mp;
    v_res := pg_temp.ok(v_res, 'S1e o orçamento esperando o sinal sem recebível (MP, ORÇ-00095) também é marcado e lembrado, sem o valor: "… e o sinal ainda não entrou: cobre quando puder. …"',
      pg_temp.alocs(v_mp) <> '' and v_q.texto ~ '^Marquei MP \(ORÇ-00095\) a partir de [a-z]{3} \d\d/\d\d e o sinal ainda não entrou: cobre quando puder\. Para o cliente eu não digo nada sobre isso\.$',
      coalesce(v_q.texto, '-') || ' | ' || pg_temp.alocs(v_mp));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- S1f o dia marcado pelo dono (o pedido dele, origem dono): "está na agenda a partir de"
  begin
    perform pg_temp.fixtures();
    perform pg_temp.modos('ligado');
    v_vera := pg_temp.os('OS-97005');
    select id into strict v_adm from public.app_users where role = 'admin' and active order by id limit 1;
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (v_vera, 1, 'dono', pg_temp.em(c_hoje, '10:00'))
    on conflict (service_order_id) do update set dias = 1, estimativa_fonte = 'dono', estimativa_em = pg_temp.em(c_hoje, '10:00');
    v_p := public.agenda_propor('os', null, null, array[v_vera],
                                jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', v_vera, 'de', '2026-11-04'))),
                                true, 'dono', v_adm, c_hoje, pg_temp.em(c_hoje, '16:52'));
    v_a := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'dono', v_adm, null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    r := public._agenda_gestor_sinal(c_hoje, pg_temp.em(c_hoje, '17:07'));
    select * into v_q from public.agenda_perguntas q where q.tipo = 'sinal' and q.service_order_id = v_vera;
    v_res := pg_temp.ok(v_res, 'S1f o dia que o dono pediu (qua 04/11): "Vera (OS-97005) está na agenda a partir de qua 04/11 e o sinal de R$ 1.000 ainda não entrou: …"',
      v_q.texto = 'Vera (OS-97005) está na agenda a partir de qua 04/11 e o sinal de R$ 1.000 ainda não entrou: cobre quando puder. Para o cliente eu não digo nada sobre isso.',
      coalesce(v_q.texto, '-') || ' | ' || pg_temp.alocs(v_vera));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- S1g em teste e com *gestor, só propor*, nada nasce: a Vera marcada (ligado) e o passo depois, em sombra e com a palavra
  begin
    perform pg_temp.fixtures();
    perform pg_temp.modos('ligado');
    v_vera := pg_temp.os('OS-97005');
    v_mp := pg_temp.os('ORÇ-00095');
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
    values (v_vera, 1, 'dono', pg_temp.em(c_hoje, '10:00'))
    on conflict (service_order_id) do update set dias = 1, estimativa_fonte = 'dono', estimativa_em = pg_temp.em(c_hoje, '10:00');
    v_p := public.agenda_propor('os', null, null, array[v_vera], '{}'::jsonb, true, 'vigia', null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    v_a := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    perform pg_temp.modos('sombra');
    r := public._agenda_gestor_sinal(c_hoje, pg_temp.em(c_hoje, '17:07'));
    perform pg_temp.modos('ligado');
    update public.agenda_config set gestor_so_propor = true, gestor_so_propor_em = pg_temp.em(c_hoje, '17:15') where id;
    r2 := public._agenda_gestor_sinal(c_hoje, pg_temp.em(c_hoje, '17:22'));
    v_t := public._agenda_classe_agora(v_mp, c_hoje) ->> 'motivo';
    v_res := pg_temp.ok(v_res, 'S1g a Vera marcada, mas em teste e com *gestor, só propor* o passo pula (nenhuma pergunta sinal) e a classe volta a esperar o sinal (o MP)',
      pg_temp.alocs(v_vera) <> '' and coalesce((r ->> 'pulado')::boolean, false) and coalesce((r2 ->> 'pulado')::boolean, false)
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'sinal') and v_t = 'sinal',
      r::text || ' | ' || r2::text || ' | ' || v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$s1$;

-- ── S2. O sábado ─────────────────────────────────────────────────────────────────────────────────────────────
do $s2$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-29';
  v_z     uuid;
  v_rob   uuid;
  v_joao  uuid;
  v_adm   uuid;
  r       jsonb;
  r2      jsonb;
  v_q     public.agenda_perguntas%rowtype;
  v_t     text;
  v_n     int;
  v_itens jsonb;
  v_cart  uuid[];
  v_cont  jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('S2 o sábado (as fixtures da 7a)', true, 'PULADO: sem agenda_teste.replay2910 e fase7a (rode pela bancada)');
    return;
  end if;
  -- S2a ninguém com o padrão de sábado (a equipe de 29/10): nenhuma pergunta
  begin
    perform pg_temp.fixtures(false);
    perform pg_temp.modos('ligado');
    v_z := pg_temp.zilda();
    r := public._agenda_gestor_sabado(c_hoje, pg_temp.em(c_hoje, '16:52'));
    v_res := pg_temp.ok(v_res, 'S2a sem ninguém com o padrão de sábado (a equipe de 29/10): 0 perguntas, nenhuma conta (a Zilda fica com a pergunta "não cabe" de sempre)',
      (r ->> 'quem_vem_sabado')::int = 0 and (r ->> 'perguntas')::int = 0 and (r ->> 'candidatas')::int = 0
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'sabado'),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  begin
    perform pg_temp.fixtures(true);
    perform pg_temp.modos('ligado');
    v_z := pg_temp.zilda();
    v_rob := pg_temp.pessoa('Roberto');
    v_joao := pg_temp.pessoa('João');
    select id into strict v_adm from public.app_users where role = 'admin' and active order by id limit 1;
    -- S2b com o Roberto de sábado: a pergunta crítica
    r := public._agenda_gestor_sabado(c_hoje, pg_temp.em(c_hoje, '16:52'));
    select * into v_q from public.agenda_perguntas q where q.tipo = 'sabado' and q.service_order_id = v_z;
    v_res := pg_temp.ok(v_res, 'S2b com o Roberto de sábado de manhã: a Zilda só fica pronta até seg 16/11 com a manhã de sáb 14/11 — a pergunta crítica (o texto da §6.3; chave sabado:<os>:<sábado>; opções 1 usa / 2 não usa; recomendação 1; sem prazo; expira quando o sábado começa ou em 7 dias)',
      v_q.texto = 'Para Zilda ficar pronto até seg 16/11 (o que o cliente pediu), preciso do sábado 14/11 de manhã com Roberto. Sábado custa mais. 1) Use o sábado (recomendo); 2) Não use: o serviço termina ter 17/11.'
      and v_q.chave = format('sabado:%s:2026-11-14', v_z) and v_q.critica and v_q.veto_ate is null and v_q.opcao_padrao is null
      and v_q.recomendacao = 1 and jsonb_array_length(v_q.opcoes) = 2 and v_q.opcoes #>> '{0,efeito,sabados,0}' = '2026-11-14'
      and v_q.opcoes #>> '{1,texto}' = 'Não use: o serviço termina ter 17/11' and v_q.modo = 'ligado'
      and v_q.expira_em = least(pg_temp.em(c_hoje, '16:52') + interval '7 days', lower(public.agenda_periodo(date '2026-11-14', 'manha')))
      and (r ->> 'novas')::int = 1 and (r ->> 'quem_vem_sabado')::int = 1,
      coalesce(v_q.texto, '-') || ' | ' || r::text);
    r2 := public._agenda_gestor_sabado(c_hoje, pg_temp.em(c_hoje, '17:07'));
    v_res := pg_temp.ok(v_res, 'S2c a conta do dia seguinte (a mesma) não abre outra: a mesma pergunta aberta',
      (r2 ->> 'novas')::int = 0 and (select count(*) from public.agenda_perguntas q where q.tipo = 'sabado') = 1
      and (select estado from public.agenda_perguntas q where q.id = v_q.id) = 'aberta',
      r2::text);
    -- S2d a decisão 1: a manhã de sábado com o Roberto, a exceção "vem" dele naquele sábado, a pergunta respondida
    r := public.agenda_decidir(v_q.id, 1::smallint, v_adm, 'whatsapp', '1', c_hoje, pg_temp.em(c_hoje, '17:40'));
    v_t := pg_temp.alocs(v_z);
    v_res := pg_temp.ok(v_res, 'S2d *1* (Use o sábado): a Zilda de sex 13 a seg 16/11 com a manhã de sáb 14/11 com o Roberto; a manhã fica dita na disponibilidade dele (a exceção "vem" de sáb 14/11, de manhã, origem dono); a pergunta respondida; o texto lembra de combinar',
      coalesce((r ->> 'ok')::boolean, false) and v_t like '%14/11 manha Roberto%' and v_t like '13/11 %' and v_t like '%16/11 %'
      and exists (select 1 from public.agenda_disponibilidade d
                   where d.payee_id = v_rob and d.substituida_em is null and d.periodo = daterange(date '2026-11-14', date '2026-11-14', '[]')
                     and d.turno = 'manha' and d.situacao = 'disponivel' and d.origem = 'dono')
      and (select estado from public.agenda_perguntas q where q.id = v_q.id) = 'respondida'
      and r ->> 'texto' like 'Combinado: uso o sábado 14/11 de manhã para Zilda. Mudei: Zilda (OS-97401): sex 13, sáb 14 e seg 16/11, %'
      and r ->> 'texto' like '% Combine o sábado com Roberto: a ficha da equipe só sai para dia útil.',
      v_t || ' | ' || coalesce(r ->> 'texto', r::text));
    -- S2e a vigia seguinte não tira o sábado (a exceção diz que ele vem); sem a exceção, tiraria ("quem ia não está mais livre")
    v_cart := array(select k.service_order_id from public.os_carteira(date '2026-10-30') k);
    r2 := public._agenda_violacoes(array[v_z], v_cart, false,
            jsonb_build_object(v_z::text, jsonb_build_object('pront', public.os_prontidao(v_z, date '2026-10-30'),
                                                             'meios', public.agenda_meios_da_os(v_z, date '2026-10-30'))),
            date '2026-10-30', date '2026-11-03');
    -- a conta do sábado do dia seguinte não pergunta de novo (a Zilda já cabe no prazo) e nada fica aberto
    v_cont := public._agenda_gestor_sabado(date '2026-10-30', pg_temp.em(date '2026-10-30', '16:52'));
    v_res := pg_temp.ok(v_res, 'S2e1 a conta do sábado de sex 30/10 (a Zilda marcada até seg 16/11) não pergunta de novo: nenhuma pergunta sabado aberta',
      (v_cont ->> 'perguntas')::int = 0 and (v_cont ->> 'novas')::int = 0
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'sabado' and q.estado = 'aberta')
      and pg_temp.alocs(v_z) = v_t,
      v_cont::text);
    update public.agenda_disponibilidade set substituida_em = pg_temp.em(c_hoje, '18:00')
     where payee_id = v_rob and periodo = daterange(date '2026-11-14', date '2026-11-14', '[]');
    v_cont := public._agenda_violacoes(array[v_z], v_cart, false,
            jsonb_build_object(v_z::text, jsonb_build_object('pront', public.os_prontidao(v_z, date '2026-10-30'),
                                                             'meios', public.agenda_meios_da_os(v_z, date '2026-10-30'))),
            date '2026-10-30', date '2026-11-03');
    v_res := pg_temp.ok(v_res, 'S2e a vigia de sex 30/10 não vê violação no sábado combinado; sem a exceção "vem" (o controle), a manhã de sábado seria tirada ("pessoa": a grade diz "sábado só quando vocês combinam")',
      r2 = '[]'::jsonb and exists (select 1 from jsonb_array_elements(v_cont) e
                                    where e ->> 'motivo' = 'pessoa' and e ->> 'dia' = '2026-11-14' and (e ->> 'violada')::boolean),
      r2::text || ' | ' || left(v_cont::text, 300));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- S2f a decisão 2, o nunca e o em teste
  begin
    perform pg_temp.fixtures(true);
    perform pg_temp.modos('ligado');
    v_z := pg_temp.zilda();
    select id into strict v_adm from public.app_users where role = 'admin' and active order by id limit 1;
    perform public._agenda_gestor_sabado(c_hoje, pg_temp.em(c_hoje, '16:52'));
    select * into v_q from public.agenda_perguntas q where q.tipo = 'sabado' and q.service_order_id = v_z;
    v_n := (select count(*) from public.agenda_alocacoes);
    r := public.agenda_decidir(v_q.id, 2::smallint, v_adm, 'whatsapp', '2', c_hoje, pg_temp.em(c_hoje, '17:40'));
    v_res := pg_temp.ok(v_res, 'S2f *2* (Não use): respondida, nada muda na agenda nem na disponibilidade ("Combinado: não uso o sábado para Zilda. O serviço termina ter 17/11.")',
      coalesce((r ->> 'ok')::boolean, false) and r ->> 'texto' = 'Combinado: não uso o sábado para Zilda. O serviço termina ter 17/11.'
      and (select estado from public.agenda_perguntas q where q.id = v_q.id) = 'respondida'
      and (select count(*) from public.agenda_alocacoes) = v_n and pg_temp.alocs(v_z) = ''
      and not exists (select 1 from public.agenda_disponibilidade d where d.periodo is not null and d.nota like 'sábado de manhã para%'),
      coalesce(r ->> 'texto', r::text));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- S2g sabado_manha = nunca: o passo pula e a aberta é resolvida
  begin
    perform pg_temp.fixtures(true);
    perform pg_temp.modos('ligado');
    v_z := pg_temp.zilda();
    perform public._agenda_gestor_sabado(c_hoje, pg_temp.em(c_hoje, '16:52'));
    v_n := (select count(*) from public.agenda_perguntas q where q.tipo = 'sabado' and q.estado = 'aberta');
    update public.agenda_config set sabado_manha = 'nunca' where id;
    r := public._agenda_gestor_sabado(c_hoje, pg_temp.em(c_hoje, '17:07'));
    v_res := pg_temp.ok(v_res, 'S2g com sabado_manha = nunca: o passo pula (0) e a pergunta aberta é resolvida ("não precisa mais")',
      v_n = 1 and coalesce((r ->> 'pulado')::boolean, false) and (r ->> 'resolvidas')::int = 1
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'sabado' and q.estado = 'aberta'),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- S2h em teste: a conta da sombra, seca (a pergunta só na saída do passo; a variável agenda.gestor volta vazia)
  begin
    perform pg_temp.fixtures(true);
    v_z := pg_temp.zilda();
    perform pg_temp.modos('sombra');
    r := public._agenda_gestor_sabado(c_hoje, pg_temp.em(c_hoje, '16:52'));
    v_res := pg_temp.ok(v_res, 'S2h em teste: seco — a pergunta da Zilda só na saída do passo, nada gravado, as variáveis agenda.gestor e agenda.sabado vazias no fim',
      coalesce((r ->> 'simulacao')::boolean, false) and (r ->> 'perguntas')::int = 1 and (r ->> 'novas')::int = 0
      and r #>> '{lista,0,texto}' like 'Para Zilda ficar pronto até seg 16/11 (o que o cliente pediu), preciso do sábado 14/11 de manhã com Roberto.%'
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'sabado')
      and coalesce(current_setting('agenda.gestor', true), '') = '' and coalesce(current_setting('agenda.sabado', true), '') = '',
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- S2i o validador: com a variável, a manhã de sábado de quem tem o padrão passa; de quem não tem, nunca; sem a variável, nada
  begin
    perform pg_temp.fixtures(true);
    perform pg_temp.modos('ligado');
    v_z := pg_temp.zilda();
    v_rob := pg_temp.pessoa('Roberto');
    v_joao := pg_temp.pessoa('João');
    v_itens := jsonb_build_array(jsonb_build_object('op', 'criar', 'os', v_z, 'numero', 'OS-97401', 'tipo', 'execucao',
                 'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_rob, 'nome', 'Roberto', 'dia', date '2026-11-14',
                                                                   'turno', 'manha', 'presenca', 'turno'))));
    v_t := (select count(*) from jsonb_array_elements(public._agenda_validar_itens(v_itens, '{}'::jsonb, c_hoje, pg_temp.em(c_hoje, '16:52'))) e
             where (e ->> 'regra')::int = 1)::text;
    perform set_config('agenda.sabado', 'on', true);
    v_t := v_t || ',' || (select count(*) from jsonb_array_elements(public._agenda_validar_itens(v_itens, '{}'::jsonb, c_hoje, pg_temp.em(c_hoje, '16:52'))) e
                          where (e ->> 'regra')::int = 1)::text;
    v_t := v_t || ',' || (select count(*) from jsonb_array_elements(public._agenda_validar_itens(
                 jsonb_set(jsonb_set(v_itens, '{0,alocacoes,0,payee_id}', to_jsonb(v_joao)), '{0,alocacoes,0,nome}', '"João"'),
                 '{}'::jsonb, c_hoje, pg_temp.em(c_hoje, '16:52'))) e where (e ->> 'regra')::int = 1)::text;
    v_t := v_t || ',' || (select count(*) from jsonb_array_elements(public._agenda_validar_itens(
                 jsonb_set(v_itens, '{0,alocacoes,0,turno}', '"tarde"'), '{}'::jsonb, c_hoje, pg_temp.em(c_hoje, '16:52'))) e
                          where (e ->> 'regra')::int = 1)::text;
    update public.agenda_config set sabado_manha = 'nunca' where id;
    v_t := v_t || ',' || (select count(*) from jsonb_array_elements(public._agenda_validar_itens(v_itens, '{}'::jsonb, c_hoje, pg_temp.em(c_hoje, '16:52'))) e
                          where (e ->> 'regra')::int = 1)::text;
    perform set_config('agenda.sabado', '', true);
    v_res := pg_temp.ok(v_res, 'S2i o validador (a regra 1): sem a variável recusa a manhã de sábado do Roberto (1, o de antes); com ela, aceita (0); o João, sem o padrão, nunca (1); a tarde, nunca (1); com sabado_manha = nunca, recusa (1)',
      v_t = '1,0,1,1,1', v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$s2$;

-- ── S3. Os orçamentos ─────────────────────────────────────────────────────────────────────────────────────
do $s3$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-29';
  r       jsonb;
  v_t     text;
  v_n     int;
  v_np    int;
  v_ok    boolean;
  e       jsonb;
  v_x     jsonb;
  v_foco  text;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('S3 os orçamentos (o replay)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.fixtures();
    perform pg_temp.modos('ligado');
    v_n := (select count(*) from public.agenda_alocacoes);
    v_np := (select count(*) from public.agenda_propostas);
    r := public._agenda_gestor_orcamentos(c_hoje, pg_temp.em(c_hoje, '16:52'));
    v_t := (select string_agg(x ->> 'numero', ',' order by o) from jsonb_array_elements(r -> 'lista') with ordinality t(x, o));
    v_res := pg_temp.ok(v_res, 'S3a os 6 orçamentos grandes do real (rascunho ou enviados, R$ 20.000 ou mais, mexidos em 30 dias), do maior para o menor; o ORÇ-00095 (esperando o sinal) e os menores ficam de fora',
      (r ->> 'orcamentos')::int = 6 and v_t = 'ORÇ-00117,ORÇ-00116,ORÇ-00126,ORÇ-00125,ORÇ-00122,ORÇ-00118', v_t);
    -- (correção da 7a, achado 5: com a regra uma_pessoa, as diárias repartidas por equipe_padrao — 1 —, como o gestor marcaria
    -- depois de aprovado; acima de 8 diárias, o texto diz que ele pergunta os dias antes)
    v_res := pg_temp.ok(v_res, 'S3b o texto: "Everton (ORÇ-00117, R$ 120.020): pela estimativa, 55,5 dias com 1 pessoa; … Se aprovar, pergunto os dias antes (mais de 8 diárias)." (as 55,5 diárias com equipe_padrao, a regra uma_pessoa: correção da 7a, achado 5); o que cabe diz "cabe a partir de …"',
      r #>> '{lista,0,texto}' like 'Everton (ORÇ-00117, R$ 120.020): pela estimativa, 55,5 dias com 1 pessoa; %. Se aprovar, pergunto os dias antes (mais de 8 diárias).'
      and (r #>> '{lista,0,diarias}')::numeric = 55.50 and (r #>> '{lista,0,pessoas}')::int = 1
      and r #>> '{lista,2,texto}' = format('MP (ORÇ-00126, R$ 34.480): pela estimativa, 7 dias com 1 pessoa; cabe a partir de %s.',
                                            public._dia_curto((r #>> '{lista,2,cabe_de}')::date)),
      r #>> '{lista,0,texto}' || ' | ' || (r #>> '{lista,2,texto}'));
    v_ok := true;
    for e in select x from jsonb_array_elements(r -> 'lista') x loop
      v_x := public.agenda_encaixe_do_novo((e ->> 'dias')::numeric, '[]'::jsonb, null, c_hoje);
      v_ok := v_ok and (v_x -> 'de') is not distinct from (e -> 'cabe_de') and (v_x ->> 'cabe')::boolean = (e ->> 'cabe')::boolean;
    end loop;
    v_res := pg_temp.ok(v_res, 'S3c o "cabe a partir de" é o da agenda_encaixe_do_novo (os dias, sem gente, sem presença dita, hoje); nenhuma alocação nem proposta nasce',
      v_ok and (select count(*) from public.agenda_alocacoes) = v_n and (select count(*) from public.agenda_propostas) = v_np, null);
    v_foco := public._agenda_ver_gestor(c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'S3d o diário do gestor (agenda_gestor_dia.orcamentos) = a lista, e o foco *agenda gestor* mostra "Se aprovar:" com o Everton',
      (select g.orcamentos from public.agenda_gestor_dia g where g.dia = c_hoje) = r -> 'lista'
      and v_foco like E'%\nSe aprovar:\n• Everton (ORÇ-00117, R$ 120.020): pela estimativa, 55,5 dias com 1 pessoa; %',
      v_foco);
    -- S3e em teste: a conta da sombra (a variável só dentro do passo); desligado = pulado
    perform pg_temp.modos('sombra');
    r := public._agenda_gestor_orcamentos(c_hoje, pg_temp.em(c_hoje, '17:07'));
    v_t := coalesce(current_setting('agenda.gestor', true), '');
    perform pg_temp.modos('desligado');
    v_x := public._agenda_gestor_orcamentos(c_hoje, pg_temp.em(c_hoje, '17:22'));
    v_res := pg_temp.ok(v_res, 'S3e em teste, a conta da sombra (simulacao; a variável agenda.gestor volta vazia), os mesmos 6; desligado, pula',
      coalesce((r ->> 'simulacao')::boolean, false) and (r ->> 'orcamentos')::int = 6 and v_t = ''
      and coalesce((v_x ->> 'pulado')::boolean, false) and (select count(*) from public.agenda_alocacoes) = v_n,
      r ->> 'simulacao' || ' ' || (r ->> 'orcamentos') || ' | ' || v_x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$s3$;

-- ── S4 e S5. As cópias e o de antes, byte a byte ───────────────────────────────────────────────────────────────
do $copias$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-29';
  v_p3   text := coalesce(current_setting('agenda_teste.mig_prontidao_fase7a', true), '');
  v_p11  text := coalesce(current_setting('agenda_teste.mig_protecoes_fase7a', true), '');
  v_p5   text := coalesce(current_setting('agenda_teste.mig_teto_fase7a', true), '');
  r      record;
  v_novo text;
  v_n    int;
  v_a    text;
  v_b    text;
  v_c    text;
  v_m    text;
  v_itens jsonb;
  v_os   uuid;
begin
  if v_p3 = '' or v_p11 = '' or v_p5 = '' then
    insert into _resultado values ('S4 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('_agenda_classe_da_os', 'public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)', v_p3, '20261031100200', 1),
      ('_agenda_gestor_decidir', 'public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', v_p11, '20261031100850', 2),
      ('_agenda_validar_itens', 'public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)', v_p5, '20261031100400', 1)
    ) t(nome, assinatura, fonte, versao, blocos)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: \(7a P12', 'g');
    v_res := pg_temp.ok(v_res,
      format('S4 %s: sem os %s blocos "-- FASE 7: (7a P12", é o corpo de %s (a mais nova antes do P12)', r.nome, r.blocos, r.versao),
      v_n = r.blocos and pg_temp.corpo(r.fonte, r.nome) <> '' and pg_temp.sem_p12(v_novo) = pg_temp.corpo(r.fonte, r.nome),
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(r.fonte, r.nome)),
             length(pg_temp.sem_p12(v_novo))));
  end loop;

  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('S5 o de antes (as fixtures da 7a)', true, 'PULADO: sem agenda_teste.replay2910 e fase7a (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  execute replace(pg_temp.inteira(v_p3, '_agenda_classe_da_os'), 'create or replace function public._agenda_classe_da_os(',
                  'create function pg_temp.classe_antes(');
  execute replace(pg_temp.inteira(v_p5, '_agenda_validar_itens'), 'create or replace function public._agenda_validar_itens(',
                  'create function pg_temp.validar_antes(');
  begin
    perform pg_temp.fixtures(true);
    v_os := pg_temp.zilda();
    -- S5a a classe das OS da carteira (o replay, a sintética e a Zilda) com o portão falso: a de antes, byte a byte
    v_a := '';
    v_b := '';
    foreach v_m in array array['desligado', 'sombra', 'so_propor', 'sem_regra'] loop
      perform pg_temp.modos(case when v_m in ('desligado', 'sombra') then v_m else 'ligado' end,
                            case when v_m = 'sem_regra' then '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada}'::text[] end);
      if v_m = 'so_propor' then
        update public.agenda_config set gestor_so_propor = true, gestor_so_propor_em = pg_temp.em(c_hoje, '10:00') where id;
      end if;
      select v_a || string_agg(k.numero || '=' || public._agenda_classe_da_os(x.pr, x.me, c_hoje)::text, '|' order by k.numero),
             v_b || string_agg(k.numero || '=' || pg_temp.classe_antes(x.pr, x.me, c_hoje)::text, '|' order by k.numero)
        into v_a, v_b
        from public.os_carteira(c_hoje) k
        cross join lateral (select public.os_prontidao(k.service_order_id, c_hoje) as pr,
                                   public.agenda_meios_da_os(k.service_order_id, c_hoje) as me) x;
    end loop;
    -- o controle: com a regra (ligado), a classe muda (a Vera e o MP)
    perform pg_temp.modos('ligado');
    select string_agg(k.numero, ',' order by k.numero) into v_c
      from public.os_carteira(c_hoje) k
      cross join lateral (select public.os_prontidao(k.service_order_id, c_hoje) as pr,
                                 public.agenda_meios_da_os(k.service_order_id, c_hoje) as me) x
     where public._agenda_classe_da_os(x.pr, x.me, c_hoje) is distinct from pg_temp.classe_antes(x.pr, x.me, c_hoje);
    v_res := pg_temp.ok(v_res, 'S5a com o portão falso (desligado, sombra fora da simulação, *gestor, só propor*, sem a regra sinal_cobrar), a classe das 20 OS da carteira (o replay, a sintética e a Zilda) é a da definição de antes, byte a byte; o controle: com a regra, mudam só as que esperavam o sinal (MP e Vera)',
      v_a = v_b and length(v_a) > 1000 and v_c = 'ORÇ-00095,OS-97005', md5(v_a) || ' / ' || md5(v_b) || ' | ' || coalesce(v_c, '-'));
    -- S5b o validador sem a variável: os itens de uma simulação da carteira e o item do sábado, o de antes, byte a byte
    v_itens := (public.agenda_propor('os', null, null, array(select k.service_order_id from public.os_carteira(c_hoje) k), '{}'::jsonb,
                                     false, 'motor', null, c_hoje, pg_temp.em(c_hoje, '16:52')) -> 'itens')
               || jsonb_build_array(jsonb_build_object('op', 'criar', 'os', v_os, 'numero', 'OS-97401', 'tipo', 'execucao',
                    'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', pg_temp.pessoa('Roberto'), 'nome', 'Roberto',
                                                                      'dia', date '2026-11-14', 'turno', 'manha', 'presenca', 'turno'))));
    v_a := public._agenda_validar_itens(v_itens, '{}'::jsonb, c_hoje, pg_temp.em(c_hoje, '16:52'))::text;
    v_b := pg_temp.validar_antes(v_itens, '{}'::jsonb, c_hoje, pg_temp.em(c_hoje, '16:52'))::text;
    v_res := pg_temp.ok(v_res, 'S5b sem a variável agenda.sabado, o validador é o de antes, byte a byte (os itens da carteira em simulação e a manhã de sábado do Roberto: a regra 1 recusa, como antes)',
      v_a = v_b and jsonb_array_length(v_itens) >= 3 and v_a like '%"regra": 1%', md5(v_a) || ' / ' || md5(v_b) || ' ' || left(v_a, 200));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$copias$;

-- ── S6. A rodada acha os 3 passos ───────────────────────────────────────────────────────────────────────────
do $s6$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-29';
  r      jsonb;
  r2     jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('S6 a rodada (o replay)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.fixtures();
    perform pg_temp.modos('ligado');
    r := public.agenda_gestor_rodar(c_hoje, pg_temp.em(c_hoje, '16:37'));
    r2 := public.agenda_gestor_rodar(c_hoje, pg_temp.em(c_hoje, '16:52'));
    v_res := pg_temp.ok(v_res, 'S6 a rodada acha os 3 passos: o sinal em todo tique (16:37, antes dos diários), o sábado e os orçamentos no 1º diário (16:52); nenhum "ainda não existe", nenhuma falha',
      r #>> '{contagens,sinal,modo}' = 'ligado' and not (r -> 'contagens') ? 'sabado' and not (r -> 'contagens') ? 'orcamentos'
      and coalesce((r2 ->> 'diaria')::boolean, false) and r2 #>> '{contagens,sinal,modo}' = 'ligado'
      and r2 #>> '{contagens,sabado,modo}' = 'ligado' and (r2 #>> '{contagens,orcamentos,orcamentos}')::int = 6
      and jsonb_array_length(r2 -> 'falhas') = 0 and jsonb_array_length(r -> 'falhas') = 0
      and not exists (select 1 from jsonb_each(r2 -> 'contagens') c where c.value ->> 'motivo' = 'ainda não existe' and c.key in ('sinal', 'sabado', 'orcamentos')),
      left(r::text, 300) || ' | ' || left(r2::text, 600));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$s6$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
