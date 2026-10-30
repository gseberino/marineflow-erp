-- Prova do bem livre, Fase 7a (pacote P13, migration 20261031100950), sobre a carteira REAL de 29/10 (o replay; a presença do
-- dono do Lenine e do Vanderlei como em produção: abre e fecha) e duas OS do próprio teste (a Xênia, OS-97501, com a lancha
-- dela; a Yolanda, OS-97511, com o motorhome dela) — o gestor marca, supõe o bem livre e diz isso ao dono uma vez.
-- bancada: depende de 20261031100950
--
--   O0 as portas e o que é (sem fixture): o passo invoker, volátil, sem grant a ninguém (nem service_role), search_path fixo
--   O1 bem_livre uma vez por OS: marcados o Lenine (ter 03/11) e o Vanderlei (qui 12/11) pela estimativa, o passo pergunta ao
--      dono (o texto da §6.3, sem artigo; a chave bem_livre:<os>; sem opções, sem prazo, sem opção padrão, não crítica, em
--      ligado, 7 dias de validade); o tique seguinte não repete; a fechada (o cliente respondeu, pelo 7d) não volta; resolvida
--      sozinha quando o bem é dito pelo planejar, o acesso é confirmado, o serviço começa, a OS perde o dia ou sai da carteira;
--      não pergunta quando o 1º dia foi o dono quem pediu, com o bem já dito ou com o acesso confirmado (o "fora" que já passou
--      não conta; o acesso dito há mais da validade também não); a lancha é "o barco"; em teste e com *gestor, só propor*, nada
--      nasce (a limpeza continua)
--   O2 nenhuma mensagem ao cliente nasce aqui (nem à equipe, nem na fila), e o passo não mexe no plano (alocações, propostas,
--      ações executadas)
--   O3 as cópias: a migration só cria o passo (nenhuma função recriada); a rodada do gestor (a definição mais nova) tem o bem nos
--      passos de todo tique e o acha (nenhum "ainda não existe"): em todo tique, também antes das 16:45
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_bem.sql
--   Seguro em produção: O0 só lê; O3a sai PULADO sem a migration como texto; O1, O2 e o resto do O3 usam o replay e só rodam na
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
-- A OS pelo número (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O replay (uma vez por subtransação: a marca agenda_teste.ja_replay volta com ela; a fixture-2310 da bancada também tem uma
-- OS-00074), com a presença do dono do Lenine e do Vanderlei como em produção, e os 5 modos do gestor (ligado = o ligar de qui
-- 29/10 16:46).
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
-- O motor marca (as OS dadas, ou a carteira inteira) e aplica, como a vigia (origem vigia; as alocações nascem de origem motor).
create function pg_temp.marcar(p_os uuid[], p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
declare
  v_os uuid[] := coalesce(p_os, (select array_agg(k.service_order_id) from public.os_carteira(p_hoje) k));
  v_p  jsonb;
begin
  v_p := public.agenda_propor('os', null, null, v_os, '{}'::jsonb, true, 'vigia', null, p_hoje, p_agora);
  return public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, p_hoje, p_agora);
end $f$;
-- Uma OS do teste com 1 dia dito pelo dono (fonte dono: a estimativa não entra) e o bem dela (p_tipo: Motorhome, Lancha…; toda OS
-- tem bem: service_orders.vessel_id é not null).
create function pg_temp.os_do_teste(p_n int, p_nome text, p_tipo text) returns uuid language plpgsql as $f$
declare
  v_os  uuid := format('f7a00000-0000-4000-8000-0000000975%s1', p_n)::uuid;
  v_cli uuid := format('f7a00000-0000-4000-8000-0000000975%s2', p_n)::uuid;
  v_bem uuid := format('f7a00000-0000-4000-8000-0000000975%s3', p_n)::uuid;
begin
  insert into public.clients (id, type, name) values (v_cli, 'individual', p_nome);
  insert into public.vessels (id, client_id, name, asset_type) values (v_bem, v_cli, p_tipo, p_tipo);
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                     created_at, updated_at, converted_to_os_at)
  values (v_os, format('OS-975%s1', p_n), v_cli, v_bem, 'open', 'approved', 'repair',
          timestamptz '2026-10-25 10:00-03', timestamptz '2026-10-28 10:00-03', timestamptz '2026-10-28 10:00-03');
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, created_at)
  values (md5('p13:servico:' || p_n)::uuid, v_os, null, 'Revisão elétrica geral', 'unit', 1, 764, 764,
          timestamptz '2026-10-25 10:00-03');
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca)
  values (v_os, 1, 'dono', timestamptz '2026-10-28 10:00-03', 'nunca');
  return v_os;
end $f$;
-- As escritas que o passo não pode fazer: o plano e as mensagens.
create function pg_temp.escritas() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'alocacoes', (select md5(coalesce(string_agg(a.id::text || a.estado, ',' order by a.id), '')) from public.agenda_alocacoes a),
    'propostas', (select count(*) from public.agenda_propostas),
    'acoes', (select count(*) from public.agenda_acoes where executada),
    'equipe', (select count(*) from public.agenda_equipe_mensagens),
    'cliente', (select count(*) from public.agenda_cliente_mensagens),
    'fila', (select count(*) from public.whatsapp_send_queue))
$f$;
-- A pergunta bem_livre de uma OS (a mais nova).
create function pg_temp.pergunta(p_os uuid) returns public.agenda_perguntas language sql stable as $f$
  select q.* from public.agenda_perguntas q where q.tipo = 'bem_livre' and q.service_order_id = p_os
   order by q.criada_em desc, q.id desc limit 1
$f$;

-- ── O0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
insert into _resultado
select 'O0 as portas: o passo bem invoker, volátil, sem grant a ninguém (nem service_role, nem authenticated); nunca anon; search_path fixo',
       not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute') and not p.prosecdef and p.provolatile = 'v'
       and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%',
       p.prosecdef::text || ' ' || p.provolatile::text || ' ' || coalesce(array_to_string(p.proconfig, ','), '-')
  from pg_proc p where p.oid = 'public._agenda_gestor_bem(date, timestamptz)'::regprocedure;

-- ── O1 e O2. A pergunta, uma vez por OS; e nada ao cliente ──────────────────────────────────────────────────────────
do $o1$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-29';
  c_len  constant text := 'Lenine (OS-00074): marquei a partir de ter 03/11 contando que o motorhome está livre e no lugar de sempre. Se ele estiver em uso ou em outro lugar, me diga até quando (ex.: ''motorhome de Lenine fora até 20/11'').';
  c_van  constant text := 'Vanderlei (OS-00069): marquei a partir de qui 12/11 contando que o motorhome está livre e no lugar de sempre. Se ele estiver em uso ou em outro lugar, me diga até quando (ex.: ''motorhome de Vanderlei fora até 04/12'').';
  v_len  uuid;
  v_van  uuid;
  v_adm  uuid;
  v_a    jsonb;
  r      jsonb;
  r2     jsonb;
  v_q    public.agenda_perguntas;
  v_q2   public.agenda_perguntas;
  v_esc  jsonb;
  v_t    text;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('O1 o bem livre (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    insert into _resultado values ('O2 nada ao cliente (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;

  -- O1a–O1c e O2: a carteira marcada às 16:52 (cenário B) e o passo
  begin
    perform pg_temp.replay('ligado');
    v_len := pg_temp.os('OS-00074');
    v_van := pg_temp.os('OS-00069');
    v_a := pg_temp.marcar(null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    v_esc := pg_temp.escritas();
    r := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:07'));
    v_q := pg_temp.pergunta(v_len);
    v_q2 := pg_temp.pergunta(v_van);
    v_res := pg_temp.ok(v_res, 'O1a marcados o Lenine (ter 03/11) e o Vanderlei (qui 12/11) pela estimativa, o passo pergunta ao dono do bem de cada um: o texto da §6.3 (sem artigo: "motorhome de Lenine"; o exemplo = o último dia marcado + 10), a chave bem_livre:<os>, sem opções, sem prazo, sem opção padrão nem recomendação, não crítica, em ligado, 7 dias de validade; só as 2 (as outras OS não têm dia)',
      coalesce((v_a ->> 'ok')::boolean, false)
      and (r ->> 'novas')::int = 2 and (r ->> 'perguntas')::int = 2 and (r ->> 'resolvidas')::int = 0 and r ->> 'modo' = 'ligado'
      and v_q.texto = c_len and v_q2.texto = c_van
      and v_q.chave = 'bem_livre:' || v_len and v_q2.chave = 'bem_livre:' || v_van
      and v_q.opcoes = '[]'::jsonb and v_q.veto_ate is null and v_q.opcao_padrao is null and v_q.recomendacao is null
      and not v_q.critica and v_q.modo = 'ligado' and v_q.estado = 'aberta'
      and v_q.os_ids = array[v_len] and v_q.expira_em = pg_temp.em(c_hoje, '17:07') + interval '7 days'
      and (select count(*) from public.agenda_perguntas q where q.tipo = 'bem_livre') = 2,
      coalesce(v_q.texto, '-') || ' | ' || coalesce(v_q2.texto, '-') || ' | ' || left(r::text, 300));
    r2 := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:22'));
    v_res := pg_temp.ok(v_res, 'O1b uma vez: o tique seguinte não abre outra (as mesmas 2 abertas)',
      (r2 ->> 'novas')::int = 0 and (r2 ->> 'perguntas')::int = 2
      and (select count(*) from public.agenda_perguntas q where q.tipo = 'bem_livre') = 2,
      r2::text);
    -- a fechada não volta: o cliente respondeu onde fica (o que o 7d faz com o M11)
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'o cliente respondeu onde fica' where id = v_q.id;
    r2 := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:37'));
    r2 := public._agenda_gestor_bem(date '2026-10-30', pg_temp.em(date '2026-10-30', '10:07'));
    v_res := pg_temp.ok(v_res, 'O1c a fechada não volta na mesma chave: o Lenine, resolvido como o 7d resolve ("o cliente respondeu onde fica"), não é perguntado de novo (nem no dia seguinte); o Vanderlei continua aberto',
      (r2 ->> 'novas')::int = 0 and (r2 ->> 'perguntas')::int = 1 and r2 -> 'os' -> 0 ->> 'numero' = 'OS-00069'
      and (select count(*) from public.agenda_perguntas q where q.tipo = 'bem_livre' and q.service_order_id = v_len) = 1
      and (pg_temp.pergunta(v_len)).estado = 'resolvida',
      r2::text);
    v_res := pg_temp.ok(v_res, 'O2 nenhuma mensagem nasce aqui — nem ao cliente (agenda_cliente_mensagens), nem à equipe, nem na fila do WhatsApp — e o passo não mexe no plano (as alocações, as propostas e as ações executadas iguais às de depois do motor)',
      pg_temp.escritas() = v_esc, v_esc::text || ' → ' || pg_temp.escritas()::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- O1d: a resolução sozinha (cada uma na sua subtransação, sobre as 2 abertas)
  begin
    perform pg_temp.replay('ligado');
    v_len := pg_temp.os('OS-00074');
    v_van := pg_temp.os('OS-00069');
    select id into strict v_adm from public.app_users where role = 'admin' and active order by id limit 1;
    v_a := pg_temp.marcar(null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    r := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:07'));
    v_t := '';
    -- o dono diz pelo planejar "motorhome do Vanderlei fora até 20/11" (o *grava*): resolvida; o Lenine continua
    begin
      perform public._agenda_aplicar_planejar(v_adm, v_van, jsonb_build_object('bem', jsonb_build_object('de', '2026-10-29', 'livre_em', '2026-11-21')),
                                              'motorhome do Vanderlei fora até 20/11', c_hoje);
      r2 := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:22'));
      v_t := v_t || 'dito=' || (r2 ->> 'resolvidas') || ':' || coalesce((pg_temp.pergunta(v_van)).resolvida_motivo, '-')
             || ':' || (pg_temp.pergunta(v_len)).estado;
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    -- o acesso confirmado (pelo cliente, na Fase 5) agora: resolvida; dito há mais da validade (90 dias), não
    begin
      update public.os_planejamento set acesso_ok_em = pg_temp.em(c_hoje, '17:10') - interval '120 days' where service_order_id = v_len;
      r2 := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:22'));
      v_t := v_t || ' | acesso_velho=' || (r2 ->> 'resolvidas') || ':' || (pg_temp.pergunta(v_len)).estado;
      update public.os_planejamento set acesso_ok_em = pg_temp.em(c_hoje, '17:10') where service_order_id = v_len;
      r2 := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:37'));
      v_t := v_t || ' | acesso=' || (r2 ->> 'resolvidas') || ':' || coalesce((pg_temp.pergunta(v_len)).resolvida_motivo, '-');
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    -- o serviço começou (o check-in)
    begin
      update public.service_orders set check_in_at = pg_temp.em(c_hoje, '17:15') where id = v_len;
      r2 := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:22'));
      v_t := v_t || ' | comecou=' || (r2 ->> 'resolvidas') || ':' || coalesce((pg_temp.pergunta(v_len)).resolvida_motivo, '-');
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    -- a OS perdeu o dia (os meios-dias cancelados)
    begin
      update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(c_hoje, '17:15'), cancelada_motivo = 'replanejado'
       where service_order_id = v_len and estado = 'publicada';
      r2 := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:22'));
      v_t := v_t || ' | sem_dia=' || (r2 ->> 'resolvidas') || ':' || coalesce((pg_temp.pergunta(v_len)).resolvida_motivo, '-');
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    -- a OS saiu da carteira (cancelada) — também em teste (a limpeza é em qualquer modo)
    begin
      update public.service_orders set status = 'cancelled' where id = v_van;
      update public.agenda_config set modo_marcar_sozinho = 'sombra' where id;
      r2 := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:22'));
      v_t := v_t || ' | saiu=' || (r2 ->> 'resolvidas') || ':' || coalesce((pg_temp.pergunta(v_van)).resolvida_motivo, '-')
             || ':' || coalesce(r2 ->> 'pulado', 'false');
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_res := pg_temp.ok(v_res, 'O1d a pergunta aberta some sozinha quando não vale mais: o bem dito pelo planejar ("já foi dito até quando o motorhome fica fora"; a outra continua), o acesso confirmado (dentro da validade; o de 120 dias atrás não conta), o serviço começou (o check-in), a OS perdeu o dia, a OS saiu da carteira (também em teste: a limpeza é em qualquer modo, e o passo pula)',
      v_t = 'dito=1:já foi dito até quando o motorhome fica fora:aberta | acesso_velho=0:aberta | acesso=1:o acesso foi confirmado'
            || ' | comecou=1:o serviço já começou | sem_dia=1:a OS não está mais marcada na agenda | saiu=1:a OS saiu da carteira:true',
      v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- O1e: quando NÃO pergunta (o acesso confirmado) e quando pergunta mesmo assim (o "fora" que já passou não conta)
  begin
    perform pg_temp.replay('ligado');
    v_len := pg_temp.os('OS-00074');
    v_van := pg_temp.os('OS-00069');
    -- o Lenine com o acesso confirmado hoje; o Vanderlei com o motorhome fora de 01 a 05/10 (já passou)
    update public.os_planejamento set acesso_ok_em = pg_temp.em(c_hoje, '10:00') where service_order_id = v_len;
    update public.os_planejamento set bem_indisponivel = datemultirange(daterange(date '2026-10-01', date '2026-10-06', '[)'))
     where service_order_id = v_van;
    v_a := pg_temp.marcar(null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    r := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:07'));
    v_res := pg_temp.ok(v_res, 'O1e os 2 marcados: não pergunta com o acesso confirmado (Lenine); o motorhome fora que já passou (Vanderlei, 01 a 05/10) não conta: ele é perguntado',
      public._agenda_os_tem_dia(v_len, c_hoje) and public._agenda_os_tem_dia(v_van, c_hoje)
      and (r ->> 'perguntas')::int = 1 and r -> 'os' -> 0 ->> 'numero' = 'OS-00069' and pg_temp.pergunta(v_len) is null,
      left(r::text, 400));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- O1f: o 1º dia pedido pelo dono não pergunta (quem escolheu o dia sabe do bem); a lancha é "o barco"
  declare
    v_xen uuid; v_yol uuid; v_p jsonb; v_qx public.agenda_perguntas;
  begin
    perform pg_temp.replay('ligado');
    select id into strict v_adm from public.app_users where role = 'admin' and active order by id limit 1;
    v_xen := pg_temp.os_do_teste(0, 'Xênia', 'Lancha');
    v_yol := pg_temp.os_do_teste(1, 'Yolanda', 'Motorhome');
    -- a Yolanda com o dia pedido pelo dono (qua 04/11); a Xênia pelo motor
    v_p := public.agenda_propor('os', null, null, array[v_yol],
                                jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', v_yol, 'de', '2026-11-04'))),
                                true, 'dono', v_adm, c_hoje, pg_temp.em(c_hoje, '16:40'));
    v_a := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'dono', v_adm, null, c_hoje, pg_temp.em(c_hoje, '16:40'));
    v_a := pg_temp.marcar(array[v_xen], c_hoje, pg_temp.em(c_hoje, '16:52'));
    r := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:07'));
    v_qx := pg_temp.pergunta(v_xen);
    v_res := pg_temp.ok(v_res, 'O1f o 1º dia pedido pelo dono (Yolanda, OS-97511, qua 04/11) não pergunta: quem escolheu o dia sabe do bem; a Xênia (OS-97501), marcada pelo motor, é perguntada, e a lancha dela é "o barco"',
      public._agenda_os_tem_dia(v_yol, c_hoje) and public._agenda_os_tem_dia(v_xen, c_hoje)
      and (r ->> 'perguntas')::int = 1 and r -> 'os' -> 0 ->> 'numero' = 'OS-97501' and pg_temp.pergunta(v_yol) is null
      and v_qx.texto ~ '^Xênia \(OS-97501\): marquei a partir de [a-z]{3} \d\d/\d\d contando que o barco está livre e no lugar de sempre\. Se ele estiver em uso ou em outro lugar, me diga até quando \(ex\.: ''barco de Xênia fora até \d\d/\d\d''\)\.$',
      coalesce(v_qx.texto, '-') || ' | ' || left(r::text, 400));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- O1g: o bem já dito de hoje em diante antes de marcar (o Vanderlei fora de 01 a 05/12, depois do serviço): não pergunta
  begin
    perform pg_temp.replay('ligado');
    v_van := pg_temp.os('OS-00069');
    update public.os_planejamento set bem_indisponivel = datemultirange(daterange(date '2026-12-01', date '2026-12-06', '[)'))
     where service_order_id = v_van;
    v_a := pg_temp.marcar(null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    r := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:07'));
    v_res := pg_temp.ok(v_res, 'O1g com o bem já dito de hoje em diante (o Vanderlei fora de 01 a 05/12), ele é marcado e não é perguntado (só o Lenine)',
      public._agenda_os_tem_dia(v_van, c_hoje) and (r ->> 'perguntas')::int = 1 and r -> 'os' -> 0 ->> 'numero' = 'OS-00074'
      and pg_temp.pergunta(v_van) is null,
      left(r::text, 400));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- O1h: em teste e com *gestor, só propor*, nada nasce (a carteira marcada com o gestor ligado; o passo depois)
  begin
    perform pg_temp.replay('ligado');
    v_a := pg_temp.marcar(null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    perform pg_temp.replay('sombra');
    r := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:07'));
    perform pg_temp.replay('ligado');
    update public.agenda_config set gestor_so_propor = true, gestor_so_propor_em = pg_temp.em(c_hoje, '17:15') where id;
    r2 := public._agenda_gestor_bem(c_hoje, pg_temp.em(c_hoje, '17:22'));
    v_res := pg_temp.ok(v_res, 'O1h a carteira marcada, mas em teste e com *gestor, só propor* o passo pula: nenhuma pergunta bem_livre',
      r ->> 'pulado' = 'true' and r ->> 'modo' = 'sombra' and r2 ->> 'pulado' = 'true' and r2 ->> 'modo' = 'sombra'
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'bem_livre'),
      r::text || ' | ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$o1$;

-- ── O3. As cópias e a rodada ─────────────────────────────────────────────────────────────────────────────────
do $o3$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-29';
  v_mig  text := replace(coalesce(current_setting('agenda_teste.mig_bem_fase7a', true), ''), E'\r\n', E'\n');
  v_def  text := pg_get_functiondef('public.agenda_gestor_rodar(date, timestamptz)'::regprocedure);
  v_fns  text;
  v_fora text;
  v_a    jsonb;
  r      jsonb;
begin
  if v_mig = '' then
    insert into _resultado values ('O3a a migration só cria o passo', true, 'PULADO: sem agenda_teste.mig_bem_fase7a (rode pela bancada)');
  else
    v_fns := (select string_agg(m[1], ',' order by o)
                from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') with ordinality x(m, o));
    -- fora do corpo da função e dos comentários, nada de tabela, lista, cron ou dado
    v_fora := regexp_replace(regexp_replace(v_mig, '\$function\$.*?\$function\$', '', 'g'), '--[^\n]*', '', 'g');
    v_res := pg_temp.ok(v_res, 'O3a a migration só cria o passo _agenda_gestor_bem: nenhuma função recriada (sem corpo copiado), nenhuma tabela, coluna, lista, cron nem dado',
      v_fns = '_agenda_gestor_bem'
      and v_fora !~* '\m(alter|create)\s+table\M' and v_fora !~* '_agenda_ampliar_lista\(' and v_fora !~* 'cron\.'
      and v_fora !~* '(?n)^\s*(insert|update|delete)\M'
      and (select count(*) from regexp_matches(v_fora, '(?n)^\s*(comment on|revoke|grant|create or replace)\M', 'gi')) = 3,
      v_fns || ' | ' || left(regexp_replace(v_fora, '\s+', ' ', 'g'), 300));
  end if;
  v_res := pg_temp.ok(v_res, 'O3b a rodada do gestor (a definição mais nova) tem o bem nos passos de todo tique, logo depois do encaixe',
    v_def ~ 'c_tique\s+constant text\[\] := array\[''vetos'', ''encaixe'', ''bem'', ''sinal'', ''puxar''\]', null);

  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('O3c a rodada acha o passo (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  begin
    perform pg_temp.replay('ligado');
    v_a := pg_temp.marcar(null, c_hoje, pg_temp.em(c_hoje, '16:52'));
    -- o tique seguinte (antes das 16:45 do dia seguinte: sex 30/10 10:07, só os de todo tique) pergunta pelos 2 marcados
    r := public.agenda_gestor_rodar(date '2026-10-30', pg_temp.em(date '2026-10-30', '10:07'));
    v_res := pg_temp.ok(v_res, 'O3c a rodada acha o passo bem (nenhum "ainda não existe") e o roda em todo tique, também antes das 16:45: sex 30/10 10:07 abre as 2 perguntas (Lenine e Vanderlei), sem falha',
      (r ->> 'rodou')::boolean and not (r ->> 'diaria')::boolean
      and r #>> '{contagens,bem,novas}' = '2' and r #>> '{contagens,bem,perguntas}' = '2'
      and coalesce(r #>> '{contagens,bem,motivo}', '') <> 'ainda não existe' and (r ->> 'erros')::int = 0,
      left(r::text, 600));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$o3$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
