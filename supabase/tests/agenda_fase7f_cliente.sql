-- Prova do cliente da Agenda de Produção, Fase 7f (pacote P6): a semana prevista (M12) à OS marcada pela estimativa, sem dia exato; o dia exato num toque só, na
-- véspera; dentro da semana dita, a mudança de dia não vira mensagem ao cliente (migration 20261109101100; spec-fase7f §3.2, §5.6, §6.5, §8.3
-- agenda_fase7f_cliente.sql e R8.3-1 e 2, R8.5-20 a 25, R8.6, R8.7, R8.8, R8.12, R8.13).
-- bancada: depende de 20261109101100
--
--   C0   sempre: as 2 novas (assinatura, invoker, volatilidade, search_path, sem grant); as recriadas com as portas de produção; nada de dado
--   C1   a camada: estimativa × todas × desligado; sem plano; o dono deu os dias; a faixa pelo calendário (o feriado de 20/11; o sábado marcado; a semana de 5 dias);
--        duas semanas; o 1º dia antes da faixa
--   C2   a semana: compra feita = faixa; pendente = condicional; uma por semana e modo; duas semanas não sai (R8.3-2); o texto aprovado, byte a byte
--   C2b  quem não recebe: a OS começada (a OS-00074), a já na semana, a do dia firme, a da faixa já dita, a sem linha em os_planejamento (recebe), a esperando
--        peça, o orçamento, a longe, a do dia do dono
--   C3   o M1 na véspera (o toque único) com cliente_dia_exato_du 1; em D−2 com 2; sem material completo, nada; com o freio e em teste, o de antes
--   C4   dentro da semana dita: o M6, o M7/M3 e o M10 não vão ao cliente; fora dela, o de hoje
--   C5   a resposta: SIM à semana = ciência (não confirma dia); "terça não dá" = ao dono, como hoje
--   C6   a semana não conta como dia ouvido nem tira a véspera; conta na saúde (liberada), no preparar (recusa com saída) e no foco (em teste)
--   C8   as cópias só mudam nos blocos; a migration cria e recria só o que diz
--   C9   a ordem (depois do onde_fica, antes do pós-serviço); o teto antes (a semana cede); a recusada pelo teto tenta de novo; a segurada não
--   C10  a revalidação: o 1º dia saiu da faixa = desatualizada; o freio = em teste; a OS esperando peça = status; dentro, sai
--   C11  o freio e a sombra: desligado, em teste e ligado com o freio, as 11 de hoje iguais, nada novo na fila; o controle (ligado sem o freio) muda
--   C12  uma vez por dia, no 1º tique a partir das 17:00, sem ler nada antes; desligada, a rodada nem chama o passo
--   C13  o texto: sem valor, sem número de OS, sem nome de outro cliente, sem data de pronto; a varredura confere o tamanho e reprova um texto plantado
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela, só o C0 roda; o resto sai PULADO: usa a fixture da 7f, que nunca roda em produção.
--
-- A fixture é a da 7f (fixture-fase7f.sql): Nelson (a semana enviada, faixa dita), Lenine (o plano cruza a semana), Flávio (firme), Tadeu (por estimativa, sem a
-- compra: compra pendente). Por cima dela, as OS do cliente deste teste (pg_temp.prepara), cada uma com o seu técnico no plano (Tec401 a Tec407): Otávio (por estimativa, compra feita), Quirino (os
-- dias são do dono), Rui (já na semana), Sérgio (esperando peça), Ubiratan (longe) e Wagner (a semana do feriado de 20/11). O relógio: qua 11/11/2026.
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
create function pg_temp.lanca(p_sql text) returns text language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    return sqlstate;
  end;
  return 'ok';
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O texto sem os blocos e as marcas DESTE pacote ("-- FASE 7f: (7f P6 … -- FASE 7f: fim" e "-- (7f P6 … -- (7f: fim)"). Os blocos da 7f de antes (o P7 em
-- agenda_saude) ficam: a origem os tem.
create function pg_temp.sem_p6(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro boolean := false;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- (FASE 7f: \(7f P6|\(7f P6)' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro and l ~ '^\s*-- (FASE 7f: fim|\(7f: fim\))' then
      v_dentro := false;
      continue;
    end if;
    if not v_dentro then
      v_fora := v_fora || l;
    end if;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
-- (P9) o texto sem os blocos do P9: em 3 das 13 a viva tem, por cima, os blocos dele; sem o P9 no banco, é a própria
create function pg_temp.sem_p9(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro boolean := false;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    -- (7e P7: e os blocos e as marcas da 7e, que recria agenda_saude depois da 7f, só acrescentando; 7g P6: e os da 7g, do mesmo jeito)
    if not v_dentro and l ~ '^\s*-- (FASE 7f: \(7f P9|FASE 7e: \(7e |\(7e |FASE 7g: \(7g |\(7g )' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro and l ~ '^\s*-- (FASE 7[efg]: fim|\(7[eg]: fim\))' then
      v_dentro := false;
      continue;
    end if;
    if not v_dentro then
      v_fora := v_fora || l;
    end if;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
create function pg_temp.como(p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_papel)::text, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_cliente_fase7f', true), '') <> ''
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- As OS: as da fixture da 7f (F1 a F6 = 301 a 306) e as deste teste (K1 a K7 = 401 a 407)
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select case when p_n like '4%' then ('f7f60000-0000-4000-8000-000000097' || p_n) else ('f7f00000-0000-4000-8000-000000097' || p_n) end::uuid
$f$;
create function pg_temp.cli(p_n text) returns uuid language sql stable as $f$
  select so.client_id from public.service_orders so where so.id = pg_temp.os(p_n)
$f$;
create function pg_temp.fone(p_n text) returns text language sql stable as $f$
  select c.phone from public.service_orders so join public.clients c on c.id = so.client_id where so.id = pg_temp.os(p_n)
$f$;
create function pg_temp.p(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by created_at, id limit 1
$f$;
create function pg_temp.desfaz() returns void language plpgsql as $f$
begin
  raise exception using errcode = 'P0001', message = '__desfaz__';
end $f$;
-- O plano de uma OS do teste: o técnico dela (Tec<n>, ou quem o caso disser) nos dias dados (manhã e tarde), pela estimativa do orçamento, publicado
create function pg_temp.plano(p_n text, p_dias date[], p_fonte text default 'orcamento', p_quem text default null) returns void language plpgsql as $f$
declare
  v_hoje text := current_setting('agenda.hoje', true);
begin
  perform set_config('agenda.hoje', '2026-11-09', true);
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito', cancelada_em = timestamptz '2026-11-11 10:00-03'
   where service_order_id = pg_temp.os(p_n) and estado in ('publicada', 'fixada');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criado_em)
  select pg_temp.os(p_n), pg_temp.p(coalesce(p_quem, 'Tec' || p_n)), d, t, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-05 16:30-03', p_fonte,
         timestamptz '2026-11-05 16:30-03'
    from unnest(p_dias) d cross join (values ('manha'), ('tarde')) x(t);
  perform set_config('agenda.hoje', coalesce(v_hoje, ''), true);
end $f$;
-- O cenário: a fixture da 7f; a mensagem ao cliente ligada (sem a regra da conversa: os clientes da fixture nunca escreveram), a aprovação dos 3 dias de
-- produção; as camadas e o freio como o caso pede; a lista dos 11 de produção, com a semana só quando o caso pede (nunca é a de produção).
create function pg_temp.prepara(p_camadas text, p_freio boolean, p_lista boolean default false) returns void language plpgsql as $f$
declare
  r record;
begin
  execute current_setting('agenda_teste.fase7f');
  insert into public.app_settings (key, value) values ('company_name', 'HBR Marine Solutions') on conflict (key) do nothing;
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = 3, cliente_conversa_dias = 0, modo_proposta = 'ligado', modo_vigia = 'ligado',
         modo_cliente_camadas = p_camadas, gestor_so_propor = p_freio, gestor_so_propor_em = case when p_freio then timestamptz '2026-11-05 02:43+00' end,
         cliente_tipos_ligados = array['material_chegou', 'nova_data', 'pode_atrasar', 'confirmar', 'vespera', 'acesso', 'mudanca_no_dia', 'pronto',
                                       'pronto_lembrete', 'andamento', 'pos_servico']
                                 || case when p_lista then array['semana'] else '{}'::text[] end
   where id;
  if exists (select 1 from public.service_orders where id = pg_temp.os('401')) then
    return;
  end if;
  insert into public.payees (name, kind, active, created_at, updated_at)
  select 'Tec' || n, 'diarista', true, timestamptz '2026-09-01 10:00-03', timestamptz '2026-09-01 10:00-03'
    from unnest(array['401', '402', '403', '404', '405', '406', '407', '306']) n;
  for r in
    select * from (values
      ('401', '01', 'Otávio',   'Veleiro',   'Revisão do motor de popa',     'open'),
      ('402', '02', 'Quirino',  'Lancha',    'Troca do guincho',             'open'),
      ('403', '03', 'Rui',      'Motorhome', 'Revisão do gerador',           'open'),
      ('404', '04', 'Sérgio',   'Veleiro',   'Troca do enrolador',           'awaiting_parts'),
      ('405', '05', 'Ubiratan', 'Lancha',    'Instalação do radar',          'open'),
      ('406', '06', 'Wagner',   'Veleiro',   'Revisão da bomba de porão',    'open'),
      ('407', '07', 'Xavier',   'Lancha',    'Troca da bateria',             'draft')
    ) as t(n, c, nome, bem, servico, status)
  loop
    insert into public.clients (id, type, name, phone) values (('f7f60000-0000-4000-8000-0000000001' || r.c)::uuid, 'individual', r.nome, '55479000004' || r.c);
    insert into public.vessels (id, client_id, name, asset_type, access_notes)
    values (('f7f60000-0000-4000-8000-0000000002' || r.c)::uuid, ('f7f60000-0000-4000-8000-0000000001' || r.c)::uuid, r.bem, r.bem, 'A chave fica na marina');
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at)
    values (pg_temp.os(r.n), 'OS-K' || right(r.n, 1), ('f7f60000-0000-4000-8000-0000000001' || r.c)::uuid, ('f7f60000-0000-4000-8000-0000000002' || r.c)::uuid,
            r.status, 'approved', 'repair',
            timestamptz '2026-10-28 10:00-03', timestamptz '2026-10-30 10:00-03', timestamptz '2026-10-30 10:00-03');
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
    values (md5('f7f6:servico:' || r.n)::uuid, pg_temp.os(r.n), null, r.servico, 'unit', 1, 900, 900, timestamptz '2026-10-28 10:00-03');
  end loop;
  -- o material conferido (sem peça a comprar): a compra feita. O Quirino com os dias ditos pelo dono (estimativa_fonte dono): fora da camada.
  insert into public.os_planejamento (service_order_id, material_conferido_em, dias, estimativa_fonte, estimativa_em)
  select pg_temp.os(n), timestamptz '2026-11-10 10:00-03', case when n = '402' then 1 end, case when n = '402' then 'dono' end,
         case when n = '402' then timestamptz '2026-11-10 10:00-03' end
    from unnest(array['401', '402', '403', '404', '405', '406', '407']) n;
  perform pg_temp.plano('401', array[date '2026-11-23', date '2026-11-24']);
  perform pg_temp.plano('402', array[date '2026-11-24']);
  perform pg_temp.plano('403', array[date '2026-11-12', date '2026-11-13']);
  perform pg_temp.plano('404', array[date '2026-11-25']);
  perform pg_temp.plano('405', array[date '2026-12-07']);
  perform pg_temp.plano('406', array[date '2026-11-16', date '2026-11-17', date '2026-11-18']);
  perform pg_temp.plano('407', array[date '2026-11-26']);
end $f$;
-- A rodada do cliente (a do task-automations) num instante
create function pg_temp.rodada(p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.hoje', p_dia::text, true);
  return public.agenda_cliente_vigiar(p_dia, pg_temp.em(p_dia, p_hora));
end $f$;
create function pg_temp.passo(p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.hoje', p_dia::text, true);
  return public._agenda_cliente_semana(p_dia, pg_temp.em(p_dia, p_hora));
end $f$;
-- O texto da semana (C2): o tipo ou a variante que deixou de existir vira a linha que reprova, não o arquivo que quebra
create function pg_temp.texto_semana(p_var text, p_os uuid, p_dados jsonb, p_hoje date) returns text language plpgsql as $f$
begin
  return public._agenda_cliente_texto('semana', p_var, p_os, p_dados, p_hoje);
exception when others then
  return format('lançou %s: %s', sqlstate, sqlerrm);
end $f$;
-- O passo com o dublê da carteira (C12): a leitura que não devia acontecer vira a linha que reprova, não o arquivo que quebra
create function pg_temp.passo_sem_ler(p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  return pg_temp.passo(p_dia, p_hora);
exception when sqlstate 'P0098' then
  return jsonb_build_object('leu', sqlerrm);
end $f$;
-- A semana mais nova da OS
create function pg_temp.sem(p_n text) returns public.agenda_cliente_mensagens language sql stable as $f$
  select m from public.agenda_cliente_mensagens m where m.service_order_id = pg_temp.os(p_n) and m.tipo = 'semana' order by m.criada_em desc, m.id desc limit 1
$f$;
create function pg_temp.n_sem(p_n text) returns int language sql stable as $f$
  select count(*)::int from public.agenda_cliente_mensagens m where m.service_order_id = pg_temp.os(p_n) and m.tipo = 'semana'
$f$;
-- A mensagem saiu (o que o worker faz): a linha da fila vira sent e o gatilho do envio deixa a mensagem enviada e grava o prometido
create function pg_temp.saiu(p_msg uuid, p_quando timestamptz) returns void language sql as $f$
  update public.whatsapp_send_queue set status = 'sent', sent_at = p_quando, attempts = attempts + 1 where source_ref_id = p_msg
$f$;
-- A semana de p_n ligada, liberada (sem a aprovação), enfileirada e enviada qui 12/11 09:05: o prometido gravado pelo envio. Deixa a aprovação como estava.
create function pg_temp.semana_enviada(p_n text) returns public.agenda_cliente_mensagens language plpgsql as $f$
declare
  m public.agenda_cliente_mensagens;
  v_aprov smallint := (public._agenda_cfg()).cliente_aprovacao_dias;
begin
  update public.agenda_config set modo_cliente_camadas = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null, cliente_aprovacao_dias = 0,
         cliente_tipos_ligados = cliente_tipos_ligados || case when 'semana' = any (cliente_tipos_ligados) then '{}'::text[] else array['semana'] end
   where id;
  perform pg_temp.passo(date '2026-11-11', '17:00');
  m := pg_temp.sem(p_n);
  perform public._agenda_cliente_fila(date '2026-11-12', m.enviar_em);
  perform pg_temp.saiu(m.id, m.enviar_em + interval '1 minute');
  update public.agenda_config set cliente_aprovacao_dias = v_aprov where id;
  return pg_temp.sem(p_n);
end $f$;
-- O retrato do que vai ao cliente pelos 11 tipos de hoje (sem a semana e sem a ação dela): as mensagens, os textos, a hora, a aprovação, a fila e as ações
create function pg_temp.foto() returns text language sql stable as $f$
  select concat_ws(E'\n',
    (select string_agg(concat_ws('|', so.service_order_number, m.tipo, m.variante, m.modo, m.estado, m.aprovacao, m.recusa_motivo, m.enviar_em, m.dia_alvo, md5(m.texto),
                                 m.prometido_tipo, (m.pergunta_id is not null)::text), E'\n' order by so.service_order_number, m.tipo, m.modo, m.criada_em, m.enviar_em)
       from public.agenda_cliente_mensagens m join public.service_orders so on so.id = m.service_order_id where m.tipo <> 'semana'),
    (select string_agg(concat_ws('|', q.status, q.scheduled_for, md5(q.message)), E'\n' order by q.scheduled_for, md5(q.message))
       from public.whatsapp_send_queue q where q.source = 'agenda-cliente'),
    (select string_agg(concat_ws('|', a.tipo, a.executada, a.texto, a.contada_em is not null), E'\n' order by a.texto)
       from public.agenda_acoes a where a.tipo = 'cliente' and coalesce(a.depois ->> 'tipo', '') <> 'semana' and a.criada_em >= timestamptz '2026-11-11 00:00-03'),
    (select string_agg(x.l, E'\n' order by x.l)
       from (select concat_ws('|', q.tipo, regexp_replace(q.chave, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g'), q.estado, md5(q.texto)) as l
               from public.agenda_perguntas q where q.tipo in ('cliente_aprovar', 'cliente_aviso', 'cliente_resposta')) x))
$f$;
-- A varredura do texto ao cliente (§6.5, R8.12-4): não vazio; nada que o proibido pegue (valor, pagamento, OS, link, tamanho); sem data de pronto; sem o nome de
-- outro cliente das OS da fixture e do teste.
create function pg_temp.limpo(p_texto text, p_n text) returns boolean language sql stable as $f$
  select coalesce(length(btrim(p_texto)) > 0, false)
     and public._agenda_cliente_texto_proibido(p_texto) is null
     and p_texto !~* 'pronto até|fica pronto|tudo pronto'
     and not exists (select 1 from public.service_orders so join public.clients cl on cl.id = so.client_id
                      where (so.service_order_number like 'OS-F%' or so.service_order_number like 'OS-K%') and so.id <> pg_temp.os(p_n)
                        and p_texto ~ ('\m' || public._agenda_nome_curto(cl.name) || '\M'))
$f$;

-- ── C0. As portas e a forma (sem fixture) ───────────────────────────────────────────────────────────
with f(sig, vol) as (values
  ('public._agenda_cliente_camada(uuid, date)', 's'),
  ('public._agenda_cliente_semana(date, timestamp with time zone)', 'v'))
insert into _resultado
select 'C0a as 2 novas: invoker, a volatilidade, search_path fixo, e ninguém de fora (nem o service_role)',
       count(p.oid) = 2
       and bool_and(not p.prosecdef and p.provolatile = f.vol and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                    and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                    and not has_function_privilege('service_role', p.oid, 'execute')
                    and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x where x.grantee = 0 and x.privilege_type = 'EXECUTE')),
       string_agg(f.sig, '; ') filter (where p.oid is null or p.prosecdef or p.provolatile <> f.vol)
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- as recriadas: as portas e a forma de produção (sql/wf7f_p6_portas_prod, 08/11)
with f(sig, definer, vol, autent, servico) as (values
  ('public._agenda_cliente_texto(text, text, uuid, jsonb, date)', false, 's', true, true),
  ('public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamp with time zone, timestamp with time zone, text, text, timestamp with time zone, uuid)', true, 'v', false, false),
  ('public._agenda_cliente_confirmar(date, timestamp with time zone)', false, 'v', false, false),
  ('public._agenda_cliente_material(date, timestamp with time zone)', false, 'v', false, false),
  ('public.agenda_cliente_vigiar(date, timestamp with time zone)', true, 'v', false, true),
  ('public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamp with time zone)', true, 'v', false, true),
  ('public._agenda_cliente_revalidar(uuid, timestamp with time zone)', true, 's', false, false),
  ('public._agenda_cliente_tipo_texto(text)', false, 'i', true, true),
  ('public._agenda_cliente_o_que(text, date)', false, 's', true, true),
  ('public._agenda_cliente_a_mensagem(text, text, date)', false, 's', true, true),
  ('public._agenda_ver_clientes(uuid, date)', true, 's', true, true),
  ('public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamp with time zone)', true, 'v', true, true),
  ('public.agenda_saude(date, timestamp with time zone)', false, 's', true, true))
insert into _resultado
select 'C0b as 13 recriadas com a forma e as portas de produção: anon e PUBLIC nunca; authenticated e service_role como antes',
       count(p.oid) = 13
       and bool_and(p.prosecdef = f.definer and p.provolatile = f.vol and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and has_function_privilege('authenticated', p.oid, 'execute') = f.autent
                    and has_function_privilege('service_role', p.oid, 'execute') = f.servico
                    and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x where x.grantee = 0 and x.privilege_type = 'EXECUTE')),
       string_agg(f.sig, '; ') filter (where p.oid is null or p.prosecdef <> f.definer or p.provolatile <> f.vol
                                             or has_function_privilege('authenticated', p.oid, 'execute') <> f.autent
                                             or has_function_privilege('service_role', p.oid, 'execute') <> f.servico)
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

insert into _resultado
select 'C0c rodando: o anon, o técnico e o service_role não alcançam o passo nem a camada (42501)',
       pg_temp.como('anon', $q$select public._agenda_cliente_semana(date '2026-11-11', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('authenticated', $q$select public._agenda_cliente_semana(date '2026-11-11', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('service_role', $q$select public._agenda_cliente_semana(date '2026-11-11', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('service_role', $q$select public._agenda_cliente_camada(gen_random_uuid(), date '2026-11-11')::text$q$) like 'erro 42501%',
       null;

insert into _resultado
select 'C0d nenhum dado: a linha de agenda_config segue com as camadas desligadas e sem a semana na lista (o ligar é do dono, R8.14)',
       (select modo_cliente_camadas = 'desligado' and not ('semana' = any (cliente_tipos_ligados)) from public.agenda_config where id),
       (select modo_cliente_camadas || ' ' || cliente_tipos_ligados::text from public.agenda_config where id);

do $c$
declare
  v_mig text := coalesce(current_setting('agenda_teste.mig_cliente_fase7f', true), '');
begin
  if v_mig = '' then
    insert into _resultado values ('C0e a migration não escreve dado', true, 'PULADO: sem agenda_teste.mig_cliente_fase7f (rode pela bancada)');
    return;
  end if;
  insert into _resultado
  select 'C0e a migration não escreve dado: nada de alter table, nem update/insert em agenda_config, nem cliente_tipos_ligados; nenhum comando fora de função além de create, revoke, grant e comment',
         v_mig !~* '\malter table\M' and v_mig !~* 'update public\.agenda_config' and v_mig !~* 'insert into public\.agenda_config' and v_mig !~* 'set\s+cliente_tipos_ligados'
         and (select count(*) from regexp_matches(v_mig, '^(drop|update|insert|delete|alter|do)\M', 'gn')) = 0, null;
end
$c$;

-- ── C1. A camada ────────────────────────────────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  c   jsonb;
  h   date := date '2026-11-11';
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C1 a camada', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.prepara('desligado', false);
    c := public._agenda_cliente_camada(pg_temp.os('401'), h);
    r := pg_temp.ok(r, 'C1a desligadas: normal (desligado), sem ler o plano', c = '{"camada": "normal", "motivo": "desligado"}', c::text);
    update public.agenda_config set modo_cliente_camadas = 'sombra' where id;
    c := public._agenda_cliente_camada(pg_temp.os('401'), h);
    r := pg_temp.ok(r, 'C1b em teste, a OS pela estimativa, 23 e 24/11: semana de 23/11, faixa seg 23 a sex 27/11 (sábado fora: sabado_util falso), 2 dias',
      c ->> 'camada' = 'semana' and c ->> 'motivo' is null and c ->> 'semana' = '2026-11-23' and c ->> 'faixa_de' = '2026-11-23' and c ->> 'faixa_ate' = '2026-11-27'
      and (c ->> 'n_dias')::int = 2 and c ->> 'primeiro_dia' = '2026-11-23' and c ->> 'ultimo_dia' = '2026-11-24', c::text);
    c := public._agenda_cliente_camada(pg_temp.os('406'), h);
    r := pg_temp.ok(r, 'C1c a semana de 16/11 termina na quinta 19/11: sexta 20/11 é feriado (Consciência Negra), pelo calendário (R8.5-25)',
      public.agenda_feriado(date '2026-11-20') is not null and c ->> 'faixa_de' = '2026-11-16' and c ->> 'faixa_ate' = '2026-11-19' and (c ->> 'n_dias')::int = 3, c::text);
    c := public._agenda_cliente_camada(pg_temp.os('402'), h);
    r := pg_temp.ok(r, 'C1d os dias ditos pelo dono (estimativa_fonte dono): normal (nao_e_estimativa)', c ->> 'camada' = 'normal' and c ->> 'motivo' = 'nao_e_estimativa', c::text);
    update public.agenda_config set cliente_camadas_para = 'todas' where id;
    c := public._agenda_cliente_camada(pg_temp.os('402'), h);
    r := pg_temp.ok(r, 'C1e com cliente_camadas_para = todas, a do dono também é semana', c ->> 'camada' = 'semana' and c ->> 'faixa_ate' = '2026-11-27', c::text);
    update public.agenda_config set cliente_camadas_para = 'estimativa' where id;
    c := public._agenda_cliente_camada(pg_temp.os('305'), h);
    r := pg_temp.ok(r, 'C1f sem plano (o Giancarlo): normal (sem_plano)', c = '{"camada": "normal", "motivo": "sem_plano"}', c::text);
    c := public._agenda_cliente_camada(pg_temp.os('302'), h);
    r := pg_temp.ok(r, 'C1g o plano cruza a semana (o Lenine: 12 e 13/11, e 16/11): semana, duas_semanas, sem faixa (R8.3-2)',
      c ->> 'camada' = 'semana' and c ->> 'motivo' = 'duas_semanas' and not (c ? 'faixa_de') and c ->> 'ultimo_dia' = '2026-11-16', c::text);
    -- o sábado marcado entra na faixa (o texto do cartão: "segunda 16/11 a sábado 21/11")
    perform pg_temp.plano('406', array[date '2026-11-16', date '2026-11-17', date '2026-11-21']);
    c := public._agenda_cliente_camada(pg_temp.os('406'), h);
    r := pg_temp.ok(r, 'C1h o sábado marcado pelo plano entra: faixa seg 16 a sáb 21/11', c ->> 'faixa_de' = '2026-11-16' and c ->> 'faixa_ate' = '2026-11-21', c::text);
    -- o 1º dia marcado num dia que não é útil (o feriado) entra também
    perform pg_temp.plano('406', array[date '2026-11-20']);
    c := public._agenda_cliente_camada(pg_temp.os('406'), h);
    r := pg_temp.ok(r, 'C1i o 1º e último dia no feriado (20/11): a faixa vai de seg 16 a sex 20/11', c ->> 'faixa_de' = '2026-11-16' and c ->> 'faixa_ate' = '2026-11-20', c::text);
    update public.agenda_config set modo_cliente_camadas = 'ligado', gestor_so_propor = true, gestor_so_propor_em = now() where id;
    c := public._agenda_cliente_camada(pg_temp.os('401'), h);
    r := pg_temp.ok(r, 'C1j ligadas com o freio (= teste): a camada é lida igual', c ->> 'camada' = 'semana' and c ->> 'faixa_ate' = '2026-11-27', c::text);
    r := pg_temp.ok(r, 'C1k sem a OS ou o dia: 22004', pg_temp.lanca($q$select public._agenda_cliente_camada(null, date '2026-11-11')$q$) = '22004'
      and pg_temp.lanca($q$select public._agenda_cliente_camada(gen_random_uuid(), null)$q$) = '22004', null);
    -- a semana de 02/11: segunda é Finados; a faixa começa na terça, e a semana continua sendo "de 02/11"
    perform pg_temp.plano('406', array[date '2026-11-03', date '2026-11-04']);
    c := public._agenda_cliente_camada(pg_temp.os('406'), date '2026-10-28');
    r := pg_temp.ok(r, 'C1l a semana de 02/11 (segunda 02/11 é Finados): semana 02/11, faixa ter 03 a sex 06/11', c ->> 'semana' = '2026-11-02' and c ->> 'faixa_de' = '2026-11-03'
      and c ->> 'faixa_ate' = '2026-11-06', c::text);
    -- o 1º dia marcado no feriado do começo da semana (Finados) entra na faixa: ela começa nele, não no 1º dia útil
    perform pg_temp.plano('406', array[date '2026-11-02', date '2026-11-03']);
    c := public._agenda_cliente_camada(pg_temp.os('406'), date '2026-10-28');
    r := pg_temp.ok(r, 'C1m o plano marca a segunda de Finados (02/11) e a terça: faixa seg 02 a sex 06/11', c ->> 'faixa_de' = '2026-11-02'
      and c ->> 'faixa_ate' = '2026-11-06' and c ->> 'primeiro_dia' = '2026-11-02', c::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── C2. A semana e o texto ──────────────────────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  v   jsonb;
  m   public.agenda_cliente_mensagens;
  t   text;
  h   date := date '2026-11-11';
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C2 a semana', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  -- os textos, direto (o texto do cartão AG7-36, com o calendário)
  begin
    perform pg_temp.prepara('ligado', false, true);
    t := pg_temp.texto_semana('compra_feita', pg_temp.os('406'), '{"primeira": true, "faixa_de": "2026-11-16", "faixa_ate": "2026-11-21", "n": 3}', h);
    r := pg_temp.ok(r, 'C2a o texto do cartão (AG7-36), byte a byte: compra feita, 1ª mensagem, semana de 16/11 com o sábado marcado, 3 dias',
      t = 'Olá, Wagner! Aqui é o Gustavo, da HBR Marine Solutions. O serviço no seu veleiro está previsto para a semana de 16/11 (segunda 16/11 a sábado 21/11), com uns 3 dias de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.', t);
    t := pg_temp.texto_semana('compra_feita', pg_temp.os('406'), '{"primeira": false, "faixa_de": "2026-11-16", "faixa_ate": "2026-11-19", "n": 3}', h);
    r := pg_temp.ok(r, 'C2b a mensagem seguinte, a semana do feriado: "Wagner, o serviço … (segunda 16/11 a quinta 19/11) …"',
      t = 'Wagner, o serviço no seu veleiro está previsto para a semana de 16/11 (segunda 16/11 a quinta 19/11), com uns 3 dias de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.', t);
    t := pg_temp.texto_semana('compra_feita', pg_temp.os('406'), '{"primeira": false, "faixa_de": "2026-11-03", "faixa_ate": "2026-11-06", "n": 2}', h);
    r := pg_temp.ok(r, 'C2a2 a semana que começa na terça (segunda 02/11 é Finados): "semana de 02/11 (terça 03/11 a sexta 06/11)"',
      t = 'Wagner, o serviço no seu veleiro está previsto para a semana de 02/11 (terça 03/11 a sexta 06/11), com uns 2 dias de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.', t);
    t := pg_temp.texto_semana('compra_pendente', pg_temp.os('306'), '{"primeira": true, "faixa_de": "2026-11-23", "faixa_ate": "2026-11-27", "n": 3}', h);
    r := pg_temp.ok(r, 'C2c a peça pendente (o 2º exemplo do cartão): "… previsto para a semana de 23/11, se as peças chegarem a tempo, com uns 3 dias de trabalho. …", sem a faixa',
      t = 'Olá, Tadeu! Aqui é o Gustavo, da HBR Marine Solutions. O serviço no seu motorhome está previsto para a semana de 23/11, se as peças chegarem a tempo, com uns 3 dias de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.', t);
    t := pg_temp.texto_semana('compra_feita', pg_temp.os('402'), '{"primeira": false, "faixa_de": "2026-11-23", "faixa_ate": "2026-11-27", "n": 1}', h);
    r := pg_temp.ok(r, 'C2d 1 dia de trabalho: "com 1 dia" (o cartão só mostrou "uns 3 dias"); o bem feminino não muda "o serviço … está previsto"',
      t = 'Quirino, o serviço na sua lancha está previsto para a semana de 23/11 (segunda 23/11 a sexta 27/11), com 1 dia de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.', t);
    update public.os_planejamento set servico_cliente = 'a revisão do gerador' where service_order_id = pg_temp.os('403');
    t := pg_temp.texto_semana('compra_feita', pg_temp.os('403'), '{"primeira": false, "faixa_de": "2026-11-23", "faixa_ate": "2026-11-23", "n": 2}', h);
    r := pg_temp.ok(r, 'C2e o serviço com artigo feminino: "está prevista"; a faixa de 1 dia sem o "a"',
      t = 'Rui, a revisão do gerador está prevista para a semana de 23/11 (segunda 23/11), com uns 2 dias de trabalho. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.', t);
    r := pg_temp.ok(r, 'C2f o que falta lança 22023: a variante (duas_semanas, nenhuma; mudou só sem o P9 no banco), a faixa, a faixa invertida, a faixa em 2 semanas, os dias',
      pg_temp.lanca(format($q$select public._agenda_cliente_texto('semana', 'duas_semanas', %L, '{"faixa_de": "2026-11-23", "faixa_ate": "2026-11-27", "n": 3}', date '2026-11-11')$q$, pg_temp.os('401'))) = '22023'
      and (to_regprocedure('public._agenda_cliente_semana_mudou(uuid, jsonb, date, timestamptz, timestamptz, timestamptz)') is not null   -- (P9) com ela no banco, a variante mudou existe
           or pg_temp.lanca(format($q$select public._agenda_cliente_texto('semana', 'mudou', %L, '{"faixa_de": "2026-11-23", "faixa_ate": "2026-11-27", "n": 3}', date '2026-11-11')$q$, pg_temp.os('401'))) = '22023')
      and pg_temp.lanca(format($q$select public._agenda_cliente_texto('semana', null, %L, '{"faixa_de": "2026-11-23", "faixa_ate": "2026-11-27", "n": 3}', date '2026-11-11')$q$, pg_temp.os('401'))) = '22023'
      and pg_temp.lanca(format($q$select public._agenda_cliente_texto('semana', 'compra_feita', %L, '{"faixa_ate": "2026-11-27", "n": 3}', date '2026-11-11')$q$, pg_temp.os('401'))) = '22023'
      and pg_temp.lanca(format($q$select public._agenda_cliente_texto('semana', 'compra_feita', %L, '{"faixa_de": "2026-11-27", "faixa_ate": "2026-11-23", "n": 3}', date '2026-11-11')$q$, pg_temp.os('401'))) = '22023'
      and pg_temp.lanca(format($q$select public._agenda_cliente_texto('semana', 'compra_feita', %L, '{"faixa_de": "2026-11-20", "faixa_ate": "2026-11-23", "n": 3}', date '2026-11-11')$q$, pg_temp.os('401'))) = '22023'
      and pg_temp.lanca(format($q$select public._agenda_cliente_texto('semana', 'compra_feita', %L, '{"faixa_de": "2026-11-23", "faixa_ate": "2026-11-27", "n": 0}', date '2026-11-11')$q$, pg_temp.os('401'))) = '22023'
      and pg_temp.lanca(format($q$select public._agenda_cliente_texto('semana', 'compra_feita', %L, '{"faixa_de": "2026-11-23", "faixa_ate": "2026-11-27", "n": 2}', date '2026-11-11')$q$, pg_temp.os('401'))) = 'ok', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- o passo, ligado sem o freio e com a semana na lista (o depois do *ligar*): a compra feita e a pendente; a pergunta ao dono (3 dias de aprovação)
  begin
    perform pg_temp.prepara('ligado', false, true);
    v := pg_temp.passo(h, '17:00');
    m := pg_temp.sem('401');
    r := pg_temp.ok(r, 'C2g o Otávio (compra feita): a semana ligada de 23/11, faixa 23 a 27/11, prometido faixa, esperando o dono (cliente_aprovar), sai qui 12/11',
      m.id is not null and m.modo = 'ligado' and m.variante = 'compra_feita' and m.prometido_tipo = 'faixa' and m.faixa_de = date '2026-11-23' and m.faixa_ate = date '2026-11-27'
      and m.dia_alvo = date '2026-11-23' and m.modelo = 'M12' and m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'
      and (m.enviar_em at time zone 'America/Sao_Paulo')::date = date '2026-11-12'
      and m.dedupe_key = format('agenda-cliente:semana:%s:2026-11-23:2026-11-11', pg_temp.os('401'))
      and exists (select 1 from public.agenda_perguntas q where q.id = m.pergunta_id and q.tipo = 'cliente_aprovar'
                    and q.texto like '%Otávio (semana prevista), sai %: "Olá, Otávio! Aqui é o Gustavo, da HBR Marine Solutions. O serviço no seu veleiro está previsto para a semana de 23/11 (segunda 23/11 a sexta 27/11), com uns 2 dias de trabalho.%*manda cliente Otávio* ou *segura cliente Otávio*.'),
      coalesce(row_to_json(m)::text, v::text));
    m := pg_temp.sem('306');
    r := pg_temp.ok(r, 'C2h o Tadeu (sem os_planejamento, a placa solar faltando): compra pendente, prometido condicional, sem a faixa no texto',
      m.id is not null and m.variante = 'compra_pendente' and m.prometido_tipo = 'condicional' and m.texto like '%previsto para a semana de 23/11, se as peças chegarem a tempo, com 1 dia de trabalho.%'
      and not exists (select 1 from public.os_planejamento p where p.service_order_id = pg_temp.os('306')), coalesce(m.texto, v::text));
    r := pg_temp.ok(r, 'C2i duas semanas não sai (o Lenine, R8.3-2): nenhuma semana, contada em duas_semanas',
      pg_temp.n_sem('302') = 0 and (v #>> '{puladas,duas_semanas}')::int >= 1, v::text);
    r := pg_temp.ok(r, 'C2j a contagem: registradas 3 (Otávio, Tadeu e Wagner, a semana do feriado: segunda 16/11 a quinta 19/11), modo ligado, sem erro',
      (v ->> 'registradas')::int = 3 and v ->> 'modo' = 'ligado' and (v ->> 'erros_os')::int = 0 and pg_temp.n_sem('406') = 1
      and (pg_temp.sem('406')).texto like '%previsto para a semana de 16/11 (segunda 16/11 a quinta 19/11), com uns 3 dias de trabalho.%', v::text);
    -- uma por semana e modo: no dia seguinte, a mesma semana não volta
    v := pg_temp.passo(date '2026-11-12', '17:00');
    r := pg_temp.ok(r, 'C2k no dia seguinte, a mesma semana não nasce de novo (ja_tem), nem a do Tadeu', pg_temp.n_sem('401') = 1 and pg_temp.n_sem('306') = 1
      and (v #>> '{puladas,ja_tem}')::int >= 2, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── C2b. Quem não recebe ────────────────────────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  v   jsonb;
  h   date := date '2026-11-11';
  n   int;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C2b quem não recebe', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.prepara('ligado', false, true);
    v := pg_temp.passo(h, '17:00');
    r := pg_temp.ok(r, 'C2b1 o Rui (já na semana: qui 12 e sex 13/11; a mensagem sairia na quinta): nada (em_cima)', pg_temp.n_sem('403') = 0 and (v #>> '{puladas,em_cima}')::int >= 1, v::text);
    r := pg_temp.ok(r, 'C2b2 o Nelson (a faixa já dita, 16 a 21/11): nada (ja_ouviu)', pg_temp.n_sem('301') = 1 and (v #>> '{puladas,ja_ouviu}')::int >= 1, v::text);
    -- o laço conta cada OS uma vez (pulada ou registrada): o total é o da carteira fora dos 4 status e do dia firme (o Flávio entraria como +1)
    select count(*) into n from public.os_carteira(h) k left join public.os_planejamento p on p.service_order_id = k.service_order_id
     where k.status not in ('awaiting_parts', 'awaiting_client', 'in_progress', 'draft') and p.prometido_tipo is distinct from 'firme';
    r := pg_temp.ok(r, 'C2b3 o Flávio (dia firme dito): fora do laço, nada (nem contado: o laço vê só a carteira sem dia firme)', pg_temp.n_sem('304') = 0
      and (select sum(x.value::int) from jsonb_each_text(v -> 'puladas') x) + (v ->> 'registradas')::int + (v ->> 'erros_os')::int = n, format('laço %s; %s', n, v));
    r := pg_temp.ok(r, 'C2b4 o Sérgio (esperando peça) e o Xavier (orçamento): fora do laço, nada', pg_temp.n_sem('404') = 0 and pg_temp.n_sem('407') = 0, null);
    r := pg_temp.ok(r, 'C2b5 o Ubiratan (1º dia 07/12, a mais de 10 dias úteis): nada (longe)', pg_temp.n_sem('405') = 0 and (v #>> '{puladas,longe}')::int >= 1, v::text);
    r := pg_temp.ok(r, 'C2b6 o Quirino (os dias do dono): nada (fora_da_camada)', pg_temp.n_sem('402') = 0 and (v #>> '{puladas,fora_da_camada}')::int >= 1, v::text);
    r := pg_temp.ok(r, 'C2b7 o Vanderlei (o serviço começou ter 10/11): nada', pg_temp.n_sem('303') = 0, null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- a OS-00074 (o caso real de R8.5-21): começou, e o próximo dia ainda vem
  begin
    perform pg_temp.prepara('ligado', false, true);
    perform pg_temp.plano('406', array[date '2026-11-10', date '2026-11-16']);
    perform set_config('agenda.hoje', '2026-11-11', true);
    update public.agenda_alocacoes set resultado = 'cumprido', resultado_em = timestamptz '2026-11-10 18:00-03', resultado_via = 'dia_feito'
     where service_order_id = pg_temp.os('406') and dia = date '2026-11-10';
    v := pg_temp.passo(h, '17:00');
    r := pg_temp.ok(r, 'C2b8 a OS começada ter 10/11 com o próximo dia seg 16/11 (a forma da OS-00074): nada (comecou)', pg_temp.n_sem('406') = 0 and (v #>> '{puladas,comecou}')::int >= 1, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- o prometido nulo NÃO tira a OS (R8.5-20): o Otávio tem linha em os_planejamento com prometido nulo e recebe; o "<>" no lugar do "is distinct from" o tiraria
  begin
    perform pg_temp.prepara('ligado', false, true);
    v := pg_temp.passo(h, '17:00');
    r := pg_temp.ok(r, 'C2b9 prometido nulo (com linha: Otávio; sem linha: Tadeu) recebe a semana', pg_temp.n_sem('401') = 1 and pg_temp.n_sem('306') = 1
      and exists (select 1 from public.os_planejamento p where p.service_order_id = pg_temp.os('401') and p.prometido_tipo is null), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- em cima: cada uma das 2 guardas sozinha (a véspera; a semana já começada)
  begin
    perform pg_temp.prepara('ligado', false, true);
    v := pg_temp.passo(date '2026-11-13', '17:00');
    r := pg_temp.ok(r, 'C2b10 sex 13/11, o Wagner começa seg 16/11: a mensagem sairia sáb 14/11, antes da semana mas no dia da véspera: nada (em_cima)',
      pg_temp.n_sem('406') = 0 and (v #>> '{puladas,em_cima}')::int >= 1, v::text);
    perform pg_temp.plano('406', array[date '2026-11-19']);
    v := pg_temp.passo(date '2026-11-14', '17:00');
    r := pg_temp.ok(r, 'C2b11 sáb 14/11, o Wagner na qui 19/11: a mensagem sairia seg 16/11, antes da véspera (qua 18/11) mas com a semana já começada: nada (em_cima)',
      pg_temp.n_sem('406') = 0 and (v #>> '{puladas,em_cima}')::int >= 1, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── C3. O dia exato na véspera ──────────────────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  v   jsonb;
  m   public.agenda_cliente_mensagens;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C3 a véspera', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  -- o Wagner, seg 16/11 (compra feita, acesso conhecido): a Fase 5 manda o M1 em D−3 (qua 11/11 → qui 12/11); em camada, só a véspera (sáb 14/11)
  begin
    perform pg_temp.prepara('desligado', false);
    v := public._agenda_cliente_confirmar(date '2026-11-11', pg_temp.em(date '2026-11-11', '17:00'));
    select * into m from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('406') and x.tipo = 'confirmar';
    r := pg_temp.ok(r, 'C3a desligadas (o de antes): o M1 do Wagner sai qui 12/11 (D−3)', m.id is not null and (m.enviar_em at time zone 'America/Sao_Paulo')::date = date '2026-11-12'
      and m.variante in ('primeira', 'seguinte'), coalesce(row_to_json(m)::text, v::text));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', false, true);
    v := public._agenda_cliente_confirmar(date '2026-11-11', pg_temp.em(date '2026-11-11', '17:00'));
    r := pg_temp.ok(r, 'C3b ligadas, em camada: qua 11/11 nenhum M1 ao Wagner', not exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('406')
      and x.tipo in ('confirmar', 'vespera', 'acesso')), v::text);
    v := public._agenda_cliente_confirmar(date '2026-11-12', pg_temp.em(date '2026-11-12', '17:00'));
    r := pg_temp.ok(r, 'C3c qui 12/11: nada ainda', not exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('406')
      and x.tipo in ('confirmar', 'vespera', 'acesso')), v::text);
    v := public._agenda_cliente_confirmar(date '2026-11-13', pg_temp.em(date '2026-11-13', '17:00'));
    select * into m from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('406') and x.tipo in ('confirmar', 'vespera', 'acesso');
    r := pg_temp.ok(r, 'C3d sex 13/11 às 17:00: o toque único, a confirmação "unico" para sáb 14/11 (a véspera); um só',
      m.id is not null and m.tipo = 'confirmar' and m.variante = 'unico' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = date '2026-11-14'
      and m.dia_alvo = date '2026-11-16'
      and (select count(*) from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('406') and x.tipo in ('confirmar', 'vespera', 'acesso')) = 1,
      coalesce(row_to_json(m)::text, v::text));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', false, true);
    update public.agenda_config set cliente_dia_exato_du = 2 where id;
    v := public._agenda_cliente_confirmar(date '2026-11-12', pg_temp.em(date '2026-11-12', '17:00'));
    select * into m from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('406') and x.tipo = 'confirmar';
    r := pg_temp.ok(r, 'C3e com cliente_dia_exato_du = 2: o M1 sai sex 13/11 (2 dias de janela antes de D) e não é o "unico"',
      m.id is not null and (m.enviar_em at time zone 'America/Sao_Paulo')::date = date '2026-11-13' and m.variante <> 'unico', coalesce(row_to_json(m)::text, v::text));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- com o freio (ligado = teste) e em teste: o M1 de antes, em D−3
    perform pg_temp.prepara('ligado', true, true);
    v := public._agenda_cliente_confirmar(date '2026-11-11', pg_temp.em(date '2026-11-11', '17:00'));
    r := pg_temp.ok(r, 'C3f ligadas com o freio: o M1 de antes (D−3, qui 12/11)', exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('406')
      and x.tipo = 'confirmar' and (x.enviar_em at time zone 'America/Sao_Paulo')::date = date '2026-11-12'), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('sombra', false, true);
    v := public._agenda_cliente_confirmar(date '2026-11-11', pg_temp.em(date '2026-11-11', '17:00'));
    r := pg_temp.ok(r, 'C3g em teste: o M1 de antes', exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('406')
      and x.tipo = 'confirmar' and (x.enviar_em at time zone 'America/Sao_Paulo')::date = date '2026-11-12'), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a OS que não é camada (os dias do dono): o M1 em D−3 mesmo ligado
    perform pg_temp.prepara('ligado', false, true);
    perform pg_temp.plano('402', array[date '2026-11-16']);
    v := public._agenda_cliente_confirmar(date '2026-11-11', pg_temp.em(date '2026-11-11', '17:00'));
    r := pg_temp.ok(r, 'C3h fora da camada (o Quirino, os dias do dono), ligado: o M1 de antes', exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('402')
      and x.tipo = 'confirmar' and (x.enviar_em at time zone 'America/Sao_Paulo')::date = date '2026-11-12'), v::text);
    -- sem material completo: nada (a placa do Tadeu, a véspera dele é sáb 21/11)
    v := public._agenda_cliente_confirmar(date '2026-11-20', pg_temp.em(date '2026-11-20', '17:00'));
    r := pg_temp.ok(r, 'C3i sem o material completo (o Tadeu): nem a véspera', not exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('306')
      and x.tipo in ('confirmar', 'vespera', 'acesso')), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── C4. Dentro da semana dita ───────────────────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  v   jsonb;
  m   public.agenda_cliente_mensagens;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C4 dentro da semana', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  -- o M6 (o atraso): o Otávio ouviu a semana de 23/11 (prometido faixa 23 a 27/11)
  begin
    perform pg_temp.prepara('ligado', false, true);
    m := pg_temp.semana_enviada('401');
    r := pg_temp.ok(r, 'C4a o envio grava o prometido da semana: faixa, 23 a 27/11, fonte mensagem',
      m.estado = 'enviada' and exists (select 1 from public.os_planejamento p where p.service_order_id = pg_temp.os('401') and p.prometido_tipo = 'faixa'
                                         and p.prometido_de = date '2026-11-23' and p.prometido_ate = date '2026-11-27' and p.prometido_fonte = 'mensagem'
                                         and p.prometido_mensagem_id = m.id), row_to_json(m)::text);
    perform pg_temp.plano('401', array[date '2026-11-25', date '2026-11-26']);
    v := public._agenda_cliente_atraso(date '2026-11-16', pg_temp.em(date '2026-11-16', '17:00'));
    r := pg_temp.ok(r, 'C4b o plano andou DENTRO da semana (25 e 26/11): nenhum aviso de atraso (M6)',
      not exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('401') and x.tipo = 'pode_atrasar'), v::text);
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    v := public._agenda_cliente_atraso(date '2026-11-16', pg_temp.em(date '2026-11-16', '17:00'));
    -- (P9) com a semana que mudou no banco (20261109101200), o cliente que ouviu a semana recebe ela no lugar do M6; sem ela, o M6 de hoje. A função nova só por to_regprocedure, em texto
    r := pg_temp.ok(r, 'C4c o plano saiu da semana (30/11): o M6 de hoje (remarcado); com o P9 no banco, a semana que mudou no lugar dele',
      case when to_regprocedure('public._agenda_cliente_semana_mudou(uuid, jsonb, date, timestamptz, timestamptz, timestamptz)') is null
           then exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('401') and x.tipo = 'pode_atrasar' and x.variante = 'remarcado')
           else not exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('401') and x.tipo = 'pode_atrasar')
                and exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('401') and x.tipo = 'semana' and x.variante = 'mudou') end, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- o M3/M7 (o material chegou): o Tadeu ouviu a semana de 23/11 com a peça pendente (condicional); a placa chega
  begin
    perform pg_temp.prepara('ligado', false, true);
    m := pg_temp.semana_enviada('306');
    update public.os_planejamento set material_conferido_em = timestamptz '2026-11-16 08:00-03' where service_order_id = pg_temp.os('306');
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-11-16'
     where service_order_id = pg_temp.os('306');
    v := public._agenda_cliente_material(date '2026-11-16', pg_temp.em(date '2026-11-16', '10:00'));
    r := pg_temp.ok(r, 'C4d a peça chegou e o dia (23/11) está DENTRO da semana dita: nenhum M3 ("Podemos começar …?"), contado em dentro_da_semana',
      m.prometido_tipo = 'condicional' and not exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('306') and x.tipo in ('material_chegou', 'nova_data'))
      and (v ->> 'dentro_da_semana')::int = 1, v::text);
    perform pg_temp.plano('306', array[date '2026-11-30']);
    v := public._agenda_cliente_material(date '2026-11-16', pg_temp.em(date '2026-11-16', '10:15'));
    r := pg_temp.ok(r, 'C4e o dia novo FORA da semana dita (30/11): o M3 de hoje', exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('306')
      and x.tipo = 'material_chegou' and x.dia_alvo = date '2026-11-30'), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o mesmo cenário com as camadas em teste: o M3 de hoje, e a chave dentro_da_semana não aparece (byte a byte)
    perform pg_temp.prepara('ligado', false, true);
    m := pg_temp.semana_enviada('306');
    update public.agenda_config set modo_cliente_camadas = 'sombra' where id;
    update public.os_planejamento set material_conferido_em = timestamptz '2026-11-16 08:00-03' where service_order_id = pg_temp.os('306');
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-11-16'
     where service_order_id = pg_temp.os('306');
    v := public._agenda_cliente_material(date '2026-11-16', pg_temp.em(date '2026-11-16', '10:00'));
    r := pg_temp.ok(r, 'C4f em teste: o M3 de hoje dentro da semana, e sem a chave nova', exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('306')
      and x.tipo = 'material_chegou') and not (v ? 'dentro_da_semana'), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- o M10 (a mudança no dia): o Otávio ouviu só a semana; a equipe falta seg 23/11
  begin
    perform pg_temp.prepara('ligado', false, true);
    m := pg_temp.semana_enviada('401');
    perform pg_temp.plano('401', array[date '2026-11-23', date '2026-11-24', date '2026-11-25']);
    perform set_config('agenda.hoje', '2026-11-23', true);
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'pessoa', cancelada_em = timestamptz '2026-11-23 07:30-03'
     where service_order_id = pg_temp.os('401') and dia = date '2026-11-23' and estado = 'publicada';
    v := public._agenda_cliente_mudanca_no_dia(date '2026-11-23', pg_temp.em(date '2026-11-23', '08:00'));
    r := pg_temp.ok(r, 'C4g o dia que caiu está DENTRO da semana e o cliente só ouviu a semana: nenhuma mudança no dia (M10)',
      not exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('401') and x.tipo = 'mudanca_no_dia')
      and not public._agenda_cliente_ouviu(pg_temp.os('401'), date '2026-11-23', pg_temp.em(date '2026-11-23', '08:00')), v::text);
    -- o contraste: com o dia dito (a confirmação de seg 23/11 enviada), o M10 de hoje
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, prometido_tipo, modo, texto, base, enviar_em, valida_ate, aprovacao, estado,
                                                 dedupe_key, enviada_em, criada_em)
    values (pg_temp.cli('401'), pg_temp.os('401'), 'confirmar', 'unico', 'rodada', date '2026-11-23', 'firme', 'ligado', 'confirmação de teste', '{"dia_alvo": "2026-11-23"}',
            timestamptz '2026-11-21 09:00-03', timestamptz '2026-11-21 13:00-03', 'livre', 'enviada', 'agenda-cliente:teste:c4h', timestamptz '2026-11-21 09:00-03',
            timestamptz '2026-11-20 17:00-03');
    v := public._agenda_cliente_mudanca_no_dia(date '2026-11-23', pg_temp.em(date '2026-11-23', '08:15'));
    r := pg_temp.ok(r, 'C4h o contraste: o cliente que ouviu o dia (a confirmação) recebe o M10 de hoje',
      exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('401') and x.tipo = 'mudanca_no_dia'), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a faixa que o DONO disse (não a mensagem semana): o M3 de hoje, mesmo com as camadas ligadas (só a semana dita pela agenda segura o dia)
    perform pg_temp.prepara('ligado', false, true);
    perform public._agenda_cliente_gravar_prometido(pg_temp.os('306'), 'condicional', date '2026-11-23', date '2026-11-27', 'dono', null, pg_temp.em(date '2026-11-12', '10:00'));
    update public.os_planejamento set material_conferido_em = timestamptz '2026-11-16 08:00-03' where service_order_id = pg_temp.os('306');
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-11-16'
     where service_order_id = pg_temp.os('306');
    v := public._agenda_cliente_material(date '2026-11-16', pg_temp.em(date '2026-11-16', '10:00'));
    r := pg_temp.ok(r, 'C4i a faixa dita pelo dono (sem a mensagem semana): o M3 de hoje, sem a contagem dentro_da_semana',
      exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('306') and x.tipo = 'material_chegou')
      and not (v ? 'dentro_da_semana'), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── C5. A resposta do cliente ───────────────────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  v   jsonb;
  m   public.agenda_cliente_mensagens;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C5 a resposta', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.prepara('ligado', false, true);
    m := pg_temp.semana_enviada('401');
    v := public.agenda_resposta_do_cliente(pg_temp.fone('401'), 'Sim, combinado', gen_random_uuid(), 'text', 'confirma', null, pg_temp.em(date '2026-11-12', '10:00'));
    r := pg_temp.ok(r, 'C5a SIM à semana: ciência; a mensagem respondida; nenhum dia confirmado (client_confirmed_for nulo), nada ao dono',
      v ->> 'efeito' = 'ciencia' and v ->> 'mensagem_id' = m.id::text and (v ->> 'pergunta_id') is null
      and (select x.estado from public.agenda_cliente_mensagens x where x.id = m.id) = 'respondida'
      and (select so.client_confirmed_for is null and so.client_confirmed_at is null from public.service_orders so where so.id = pg_temp.os('401')), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', false, true);
    m := pg_temp.semana_enviada('401');
    v := public.agenda_resposta_do_cliente(pg_temp.fone('401'), 'terça não dá', gen_random_uuid(), 'text', 'remarcar', 'terça', pg_temp.em(date '2026-11-12', '10:00'));
    r := pg_temp.ok(r, 'C5b "terça não dá" à semana: ao dono, como hoje ("falou de outro dia"), sem remanejar o plano',
      v ->> 'efeito' = 'ao_dono' and (v ->> 'pergunta_id') is not null and v ->> 'texto' like 'Otávio respondeu "terça não dá" à semana prevista (semana de 23/11): falou de outro dia.%'
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('401') and a.estado = 'publicada') = 4, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── C6. A semana não é dia ouvido; as listas ────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  v   jsonb;
  m   public.agenda_cliente_mensagens;
  t   text;
  t2  text;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C6 as listas', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.prepara('ligado', false, true);
    m := pg_temp.semana_enviada('401');
    r := pg_temp.ok(r, 'C6a a semana enviada não conta como dia ouvido, em nenhum dia dela (NOVO-agenda-77)',
      not public._agenda_cliente_ouviu(pg_temp.os('401'), date '2026-11-23', pg_temp.em(date '2026-11-20', '10:00'))
      and not public._agenda_cliente_ouviu(pg_temp.os('401'), date '2026-11-24', pg_temp.em(date '2026-11-20', '10:00')), null);
    -- a véspera não é tirada pela semana enviada há menos de 2 dias (o c_perto só olha confirmar, material_chegou e nova_data)
    update public.agenda_cliente_mensagens set enviada_em = timestamptz '2026-11-20 09:05-03' where id = m.id;
    v := public._agenda_cliente_confirmar(date '2026-11-20', pg_temp.em(date '2026-11-20', '17:00'));
    r := pg_temp.ok(r, 'C6b a semana saída ontem não tira o toque da véspera (sáb 21/11)', exists (select 1 from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('401')
      and x.tipo in ('confirmar', 'vespera') and (x.enviar_em at time zone 'America/Sao_Paulo')::date = date '2026-11-21'), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('desligado', false);
    t := (public.agenda_saude(date '2026-11-11', pg_temp.em(date '2026-11-11', '17:30')) #> '{cliente,tipos_liberados}')::text;
    -- 3 dias aprovados de semana: liberada
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de, faixa_ate, prometido_tipo, modo, texto, base, enviar_em, valida_ate,
                                                 aprovacao, aprovada_em, estado, dedupe_key, enviada_em, criada_em)
    select pg_temp.cli('401'), pg_temp.os('401'), 'semana', 'compra_feita', 'rodada', date '2026-11-23', date '2026-11-23', date '2026-11-27', 'faixa', 'ligado', 'texto de teste ' || d, '{}',
           timestamptz '2026-11-01 09:00-03' + d * interval '1 day', timestamptz '2026-11-01 19:00-03' + d * interval '1 day', 'aprovada', timestamptz '2026-11-01 08:00-03' + d * interval '1 day',
           'enviada', 'agenda-cliente:teste:c6:' || d, timestamptz '2026-11-01 09:00-03' + d * interval '1 day', timestamptz '2026-10-31 17:00-03' + d * interval '1 day'
      from generate_series(0, 2) d;
    t2 := (public.agenda_saude(date '2026-11-11', pg_temp.em(date '2026-11-11', '17:30')) #> '{cliente,tipos_liberados}')::text;
    r := pg_temp.ok(r, 'C6c a saúde: a semana entra nos liberados só com os dias aprovados (contagem), nunca em cliente_tipos_ligados',
      t not like '%semana%' and t2 like '%"semana"%' and public._agenda_cliente_tipo_liberado('semana')
      and not exists (select 1 from public.agenda_config x where x.id and 'semana' = any (x.cliente_tipos_ligados)), t || ' → ' || t2);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', false, true);
    begin
      v := public.agenda_cliente_preparar((select id from public.app_users where role = 'admin' and active order by id limit 1), 'OS-K1', 'semana', false,
                                          'avisa o Otávio da semana', date '2026-11-11', pg_temp.em(date '2026-11-11', '10:00'));
    exception when others then
      v := jsonb_build_object('lancou', sqlstate, 'erro', sqlerrm);  -- a semana que deixou de existir: a linha reprova, o arquivo não quebra
    end;
    r := pg_temp.ok(r, 'C6d o preparar: a semana é um tipo que existe (não lança) e é recusada com a saída (a confirmação), sem registrar nada',
      v ->> 'ok' = 'false' and v ->> 'motivo' = 'semana' and v ->> 'texto' like 'A semana prevista eu mando sozinho, às 17:00%Para dizer o dia ao cliente agora, peça a confirmação.'
      and pg_temp.n_sem('401') = 0, v::text);
    r := pg_temp.ok(r, 'C6e o preparar: o tipo que não existe continua lançando 22023', pg_temp.lanca($q$select public.agenda_cliente_preparar((select id from public.app_users where role = 'admin' and active order by id limit 1), 'OS-K1', 'semana_x', false, 'x', date '2026-11-11', now())$q$) = '22023', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o foco *clientes*: "Ainda em teste" com a semana só com as camadas fora de desligado e sem sair de verdade
    perform pg_temp.prepara('desligado', false);
    t := public._agenda_ver_clientes(pg_temp.os('401'), date '2026-11-11') ->> 'texto';
    update public.agenda_config set modo_cliente_camadas = 'sombra' where id;
    t2 := public._agenda_ver_clientes(pg_temp.os('401'), date '2026-11-11') ->> 'texto';
    r := pg_temp.ok(r, 'C6f o foco: desligadas, a lista de "Ainda em teste" sem a semana; em teste, com "semana prevista"',
      t !~ 'semana prevista' and t2 ~ 'Ainda em teste \(não saem\): [^\n]*semana prevista', t2);
    update public.agenda_config set modo_cliente_camadas = 'ligado', gestor_so_propor = true, gestor_so_propor_em = now(),
                                    cliente_tipos_ligados = cliente_tipos_ligados || array['semana'] where id;
    t2 := public._agenda_ver_clientes(pg_temp.os('401'), date '2026-11-11') ->> 'texto';
    r := pg_temp.ok(r, 'C6g ligadas e na lista, mas com o freio: em teste', t2 ~ 'Ainda em teste \(não saem\): [^\n]*semana prevista', t2);
    update public.agenda_config set gestor_so_propor = false, gestor_so_propor_em = null where id;
    t2 := public._agenda_ver_clientes(pg_temp.os('401'), date '2026-11-11') ->> 'texto';
    r := pg_temp.ok(r, 'C6h ligadas de verdade e na lista: sai da lista de teste', t2 !~ 'semana prevista', t2);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- os nomes do tipo e da mensagem
    r := pg_temp.ok(r, 'C6i os nomes: "semana prevista", "a semana prevista do serviço (semana de 23/11)", "à semana prevista (semana de 23/11)" — a segunda, nunca o dia',
      public._agenda_cliente_tipo_texto('semana') = 'semana prevista'
      and public._agenda_cliente_o_que('semana', date '2026-11-25') = 'a semana prevista do serviço (semana de 23/11)'
      and public._agenda_cliente_o_que('semana', null) = 'a semana prevista do serviço'
      and public._agenda_cliente_a_mensagem('semana', 'compra_feita', date '2026-11-27') = 'à semana prevista (semana de 23/11)'
      and public._agenda_cliente_a_mensagem('semana', null, null) = 'à semana prevista', null);
  end;
  begin
    -- a resposta à semana em teste (a mensagem ao cliente inteira em teste): o foco diz o que eu teria feito — o SIM seria ciência, não "confirmado"
    perform pg_temp.prepara('ligado', false, true);
    update public.agenda_config set modo_cliente = 'sombra' where id;
    perform pg_temp.passo(date '2026-11-11', '17:00');
    perform public.agenda_resposta_do_cliente(pg_temp.fone('401'), 'Sim', gen_random_uuid(), 'text', 'confirma', null, pg_temp.em(date '2026-11-12', '10:00'));
    perform set_config('agenda.agora', '2026-11-12 12:00-03', true);
    t := public._agenda_ver_clientes(pg_temp.os('401'), date '2026-11-12') ->> 'texto';
    r := pg_temp.ok(r, 'C6j em teste, o SIM à semana: "eu teria anotado que ficou ciente" (nunca "eu teria confirmado")',
      t ~ 'Otávio respondeu "Sim" à semana prevista \(semana de 23/11\): eu teria anotado que ficou ciente' and t !~ 'eu teria confirmado', t);
    perform public.agenda_resposta_do_cliente(pg_temp.fone('401'), 'terça não dá', gen_random_uuid(), 'text', 'remarcar', 'terça', pg_temp.em(date '2026-11-12', '11:00'));
    perform set_config('agenda.agora', '2026-11-12 12:00-03', true);
    t := public._agenda_ver_clientes(pg_temp.os('401'), date '2026-11-12') ->> 'texto';
    r := pg_temp.ok(r, 'C6k em teste, "terça não dá" à semana: "eu teria passado a você" (nunca "tirado o dia e replanejado")',
      t ~ 'respondeu "terça não dá" à semana prevista \(semana de 23/11\): eu teria passado a você' and t !~ 'eu teria tirado o dia', t);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── C8. As cópias ───────────────────────────────────────────────────────────────────────────────────
do $c$
declare
  r     jsonb := '[]';
  v_mig text := coalesce(current_setting('agenda_teste.mig_cliente_fase7f', true), '');
  x     record;
  v_a   text;
  v_n   int;
begin
  if v_mig = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C8 as cópias', true, 'PULADO: sem agenda_teste.mig_cliente_fase7f (rode pela bancada)'));
    return;
  end if;
  for x in select * from (values
      ('_agenda_cliente_texto', 'public._agenda_cliente_texto(text, text, uuid, jsonb, date)', 'mig_cliente_fase7d', 3),
      ('_agenda_cliente_registrar', 'public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamp with time zone, timestamp with time zone, text, text, timestamp with time zone, uuid)', 'mig_protecoes_fase7a', 1),
      ('_agenda_cliente_confirmar', 'public._agenda_cliente_confirmar(date, timestamp with time zone)', 'mig_correcao_rodada_fase5', 2),
      ('_agenda_cliente_material', 'public._agenda_cliente_material(date, timestamp with time zone)', 'mig_correcao_rodada_fase5', 3),
      ('agenda_cliente_vigiar', 'public.agenda_cliente_vigiar(date, timestamp with time zone)', 'mig_cliente_fase7d', 2),
      ('agenda_resposta_do_cliente', 'public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamp with time zone)', 'mig_correcao_fase7d', 2),
      ('_agenda_cliente_revalidar', 'public._agenda_cliente_revalidar(uuid, timestamp with time zone)', 'mig_correcao_fase7d', 1),
      ('_agenda_cliente_tipo_texto', 'public._agenda_cliente_tipo_texto(text)', 'mig_cliente_fase7d', 1),
      ('_agenda_cliente_o_que', 'public._agenda_cliente_o_que(text, date)', 'mig_cliente_fase7d', 1),
      ('_agenda_cliente_a_mensagem', 'public._agenda_cliente_a_mensagem(text, text, date)', 'mig_respostas_fase5', 1),
      ('_agenda_ver_clientes', 'public._agenda_ver_clientes(uuid, date)', 'mig_cliente_fase7d', 2),
      ('agenda_cliente_preparar', 'public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamp with time zone)', 'mig_correcao_textos_fase6', 2),
      ('agenda_saude', 'public.agenda_saude(date, timestamp with time zone)', 'mig_leituras_fase7f', 1)) t(nome, sig, fonte, blocos)
  loop
    select count(*) into v_n from regexp_matches(replace(pg_temp.corpo(v_mig, x.nome), E'\r\n', E'\n'), '-- (FASE 7f: \(7f P6|\(7f P6)', 'g');
    r := pg_temp.ok(r, format('C8a %s: a viva é a desta migration; sem os %s blocos do P6, é o corpo da origem (agenda_teste.%s), byte a byte', x.nome, x.blocos, x.fonte),
      coalesce(current_setting('agenda_teste.' || x.fonte, true), '') <> ''
      and pg_temp.sem_p9(replace((select p.prosrc from pg_proc p where p.oid = x.sig::regprocedure), E'\r\n', E'\n')) = pg_temp.corpo(v_mig, x.nome)
      and v_n = x.blocos
      and pg_temp.sem_p6(pg_temp.corpo(v_mig, x.nome)) = replace(pg_temp.corpo(current_setting('agenda_teste.' || x.fonte, true), x.nome), E'\r\n', E'\n')
      and pg_temp.corpo(current_setting('agenda_teste.' || x.fonte, true), x.nome) <> '',
      format('blocos %s; origem %s letras; viva sem os blocos %s letras', v_n, length(pg_temp.corpo(current_setting('agenda_teste.' || x.fonte, true), x.nome)),
             length(pg_temp.sem_p6(pg_temp.corpo(v_mig, x.nome)))));
  end loop;
  select string_agg(distinct m[1], ',' order by m[1]) into v_a
    from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
  r := pg_temp.ok(r, 'C8b a migration cria as 2 novas e recria só as 13 que diz (o atraso, a mudança no dia, o "ouviu", o onde fica e a rodada comunicar ficam)',
    v_a = '_agenda_cliente_a_mensagem,_agenda_cliente_camada,_agenda_cliente_confirmar,_agenda_cliente_material,_agenda_cliente_o_que,_agenda_cliente_registrar,_agenda_cliente_revalidar,_agenda_cliente_semana,_agenda_cliente_texto,_agenda_cliente_tipo_texto,_agenda_ver_clientes,agenda_cliente_preparar,agenda_cliente_vigiar,agenda_resposta_do_cliente,agenda_saude',
    v_a);
  perform pg_temp.gravar(r);
end
$c$;

-- ── C9. A ordem, o teto e a recusada ────────────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  v   jsonb;
  m   public.agenda_cliente_mensagens;
  s   text := (select p.prosrc from pg_proc p where p.oid = 'public.agenda_cliente_vigiar(date, timestamp with time zone)'::regprocedure);
begin
  r := pg_temp.ok(r, 'C9a a rodada chama a semana DEPOIS do onde_fica e ANTES do pós-serviço (R8.5-22)',
    position('''onde_fica''' in s) > 0 and position('''onde_fica''' in s) < position('''semana''' in s) and position('''semana''' in s) < position('''pos_servico''' in s)
    and position('''confirmar''' in s) < position('''onde_fica''' in s), null);
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(r || pg_temp.ok('[]', 'C9 o teto', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  begin
    -- o teto antes: o Otávio já tem uma mensagem ligada para qui 12/11 (o dia em que a semana sairia): a semana cede, sem linha, e tenta no dia seguinte
    perform pg_temp.prepara('ligado', false, true);
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate, aprovacao, estado, dedupe_key, criada_em)
    values (pg_temp.cli('401'), pg_temp.os('401'), 'andamento', 'rodada', 'ligado', 'mensagem de teste', '{}', timestamptz '2026-11-12 09:30-03', timestamptz '2026-11-12 19:00-03',
            'livre', 'registrada', 'agenda-cliente:teste:c9b', timestamptz '2026-11-11 16:00-03');
    v := pg_temp.passo(date '2026-11-11', '17:00');
    r := pg_temp.ok(r, 'C9b o teto conferido antes: o cliente com mensagem no dia do envio não ganha a semana (cliente_ja_tem_mensagem), nenhuma linha',
      pg_temp.n_sem('401') = 0 and (v #>> '{puladas,cliente_ja_tem_mensagem}')::int = 1, v::text);
    v := pg_temp.passo(date '2026-11-12', '17:00');
    r := pg_temp.ok(r, 'C9c no dia seguinte, livre, a semana sai', pg_temp.n_sem('401') = 1, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a recusada pelo teto na fila não vira silêncio (R8.5-22): no dia seguinte, nasce de novo com outra chave
    perform pg_temp.prepara('ligado', false, true);
    update public.agenda_config set cliente_aprovacao_dias = 0 where id;
    perform pg_temp.passo(date '2026-11-11', '17:00');
    m := pg_temp.sem('401');
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'teto_dia' where id = m.id;
    v := pg_temp.passo(date '2026-11-12', '17:00');
    r := pg_temp.ok(r, 'C9d a recusada pelo teto tenta de novo no dia seguinte, com a chave do dia', pg_temp.n_sem('401') = 2
      and (pg_temp.sem('401')).dedupe_key = format('agenda-cliente:semana:%s:2026-11-23:2026-11-12', pg_temp.os('401')), v::text);
    -- a que o dono segurou não volta
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'segurada', aprovacao = 'segurada', aprovada_em = timestamptz '2026-11-13 08:00-03'
     where id = (pg_temp.sem('401')).id;
    v := pg_temp.passo(date '2026-11-13', '17:00');
    r := pg_temp.ok(r, 'C9e a que o dono segurou não nasce de novo (ja_tem)', pg_temp.n_sem('401') = 2 and (v #>> '{puladas,ja_tem}')::int >= 1, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a que venceu sem o dono responder também não volta (cada volta seria mais uma pergunta a ele)
    perform pg_temp.prepara('ligado', false, true);
    perform pg_temp.passo(date '2026-11-11', '17:00');
    m := pg_temp.sem('401');
    perform public._agenda_cliente_fila(date '2026-11-12', timestamptz '2026-11-12 20:00-03');
    v := pg_temp.passo(date '2026-11-13', '17:00');
    r := pg_temp.ok(r, 'C9f a que venceu sem o dono (aprovação vencida) não nasce de novo', (select x.aprovacao from public.agenda_cliente_mensagens x where x.id = m.id) = 'vencida'
      and pg_temp.n_sem('401') = 1, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- uma por modo: a de teste não segura a de verdade (quando as camadas ligam, a semana nasce ligada)
    perform pg_temp.prepara('sombra', false, true);
    perform pg_temp.passo(date '2026-11-11', '17:00');
    update public.agenda_config set modo_cliente_camadas = 'ligado' where id;
    v := pg_temp.passo(date '2026-11-12', '17:00');
    r := pg_temp.ok(r, 'C9g a semana em teste não segura a ligada: as 2 (sombra e ligado) da mesma semana',
      (select string_agg(x.modo, ',' order by x.modo) from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('401') and x.tipo = 'semana') = 'ligado,sombra', v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a semana de outra OS do mesmo cliente saiu nas últimas 24 h: a semana cede (molde do M11)
    perform pg_temp.prepara('ligado', false, true);
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de, faixa_ate, prometido_tipo, modo, texto, base, enviar_em,
                                                 valida_ate, aprovacao, estado, dedupe_key, enviada_em, criada_em)
    values (pg_temp.cli('401'), pg_temp.os('401'), 'semana', 'compra_feita', 'rodada', date '2026-11-16', date '2026-11-16', date '2026-11-19', 'faixa', 'ligado', 'semana de teste',
            '{}', timestamptz '2026-11-11 10:00-03', timestamptz '2026-11-11 19:00-03', 'livre', 'enviada', 'agenda-cliente:teste:c9i', timestamptz '2026-11-11 10:00-03',
            timestamptz '2026-11-10 17:00-03');
    v := pg_temp.passo(date '2026-11-11', '17:00');
    r := pg_temp.ok(r, 'C9h a semana saída ao mesmo cliente há menos de 24 h: a de agora cede (cliente_ja_tem_mensagem)',
      pg_temp.n_sem('401') = 1 and (v #>> '{puladas,cliente_ja_tem_mensagem}')::int >= 1, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── C10. A revalidação ──────────────────────────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  m   public.agenda_cliente_mensagens;
  a   timestamptz := timestamptz '2026-11-12 09:00-03';
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C10 a revalidação', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.prepara('ligado', false, true);
    perform pg_temp.passo(date '2026-11-11', '17:00');
    m := pg_temp.sem('401');
    perform set_config('agenda.hoje', '2026-11-12', true);
    r := pg_temp.ok(r, 'C10a dentro da faixa: sai (nulo)', public._agenda_cliente_revalidar(m.id, a) is null, public._agenda_cliente_revalidar(m.id, a));
    perform pg_temp.plano('401', array[date '2026-11-26', date '2026-11-27']);
    r := pg_temp.ok(r, 'C10b o plano andou dentro da semana (26 e 27/11): sai', public._agenda_cliente_revalidar(m.id, a) is null, public._agenda_cliente_revalidar(m.id, a));
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    r := pg_temp.ok(r, 'C10c o 1º dia saiu da faixa (30/11): desatualizada (R8.5-24)', public._agenda_cliente_revalidar(m.id, a) = 'desatualizada', public._agenda_cliente_revalidar(m.id, a));
    -- só o 1º dia fora (antes da faixa) e o último dentro: a regra do 1º dia sozinha
    perform pg_temp.plano('401', array[date '2026-11-19', date '2026-11-23']);
    r := pg_temp.ok(r, 'C10c2 o 1º dia veio para antes da faixa (19/11) e o último ficou nela (23/11): desatualizada', public._agenda_cliente_revalidar(m.id, a) = 'desatualizada', public._agenda_cliente_revalidar(m.id, a));
    perform pg_temp.plano('401', array[date '2026-11-27', date '2026-11-30']);
    r := pg_temp.ok(r, 'C10d o último dia saiu da faixa (passou a cruzar a semana): desatualizada', public._agenda_cliente_revalidar(m.id, a) = 'desatualizada', public._agenda_cliente_revalidar(m.id, a));
    perform pg_temp.plano('401', array[date '2026-11-23']);
    update public.agenda_config set gestor_so_propor = true, gestor_so_propor_em = now() where id;
    r := pg_temp.ok(r, 'C10e com o freio, a que estava pronta para sair não sai (tipo_em_teste)', public._agenda_cliente_revalidar(m.id, a) = 'tipo_em_teste', public._agenda_cliente_revalidar(m.id, a));
    update public.agenda_config set gestor_so_propor = false, gestor_so_propor_em = null, modo_cliente_camadas = 'sombra' where id;
    r := pg_temp.ok(r, 'C10f com as camadas em teste: tipo_em_teste', public._agenda_cliente_revalidar(m.id, a) = 'tipo_em_teste', public._agenda_cliente_revalidar(m.id, a));
    update public.agenda_config set modo_cliente_camadas = 'ligado' where id;
    update public.service_orders set status = 'awaiting_parts' where id = pg_temp.os('401');
    r := pg_temp.ok(r, 'C10g a OS passou a esperar peça: status', public._agenda_cliente_revalidar(m.id, a) = 'status', public._agenda_cliente_revalidar(m.id, a));
    update public.service_orders set status = 'open' where id = pg_temp.os('401');
    r := pg_temp.ok(r, 'C10h de volta: sai; o texto refeito é o registrado', public._agenda_cliente_revalidar(m.id, a) is null, public._agenda_cliente_revalidar(m.id, a));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- de ponta a ponta: a semana aprovada e o plano fora da faixa na hora de sair: a fila a recusa (desatualizada), nada sai
    perform pg_temp.prepara('ligado', false, true);
    update public.agenda_config set cliente_aprovacao_dias = 0 where id;
    perform pg_temp.passo(date '2026-11-11', '17:00');
    m := pg_temp.sem('401');
    perform pg_temp.plano('401', array[date '2026-11-30']);
    perform public._agenda_cliente_fila(date '2026-11-12', m.enviar_em);
    r := pg_temp.ok(r, 'C10i de ponta a ponta: a semana desatualizada na hora de sair é recusada, nada na fila',
      (select x.estado || ':' || coalesce(x.recusa_motivo, '') from public.agenda_cliente_mensagens x where x.id = m.id) = 'recusada:desatualizada'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = m.id and q.status in ('pending', 'sending', 'sent')),
      (select x.estado || ':' || coalesce(x.recusa_motivo, '') from public.agenda_cliente_mensagens x where x.id = m.id));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── C11. O freio e a sombra ─────────────────────────────────────────────────────────────────────────
do $c$
declare
  r     jsonb := '[]';
  c     record;
  v_ant text;
  v_f   text;
  v_k   jsonb := '{}';
  v_s   jsonb := '{}';
  v_q   jsonb := '{}';
  v_ac  jsonb := '{}';
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C11 o freio e a sombra', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  -- um dia de tiques de qua 11/11 (16:45, 17:00, 17:15, 19:30) e qui 12/11 (09:00, 09:15, 17:00) da rodada do cliente, em cada modo; o retrato dos 11 tipos de hoje
  for c in select * from (values ('desligado', false, false), ('sombra', false, false), ('ligado', true, true), ('ligado', true, false), ('controle', false, true)) t(modo, freio, lista)
  loop
    begin
      perform pg_temp.prepara(case when c.modo = 'controle' then 'ligado' else c.modo end, c.freio, c.lista);
      perform pg_temp.rodada(date '2026-11-11', '16:45');
      perform pg_temp.rodada(date '2026-11-11', '17:00');
      perform pg_temp.rodada(date '2026-11-11', '17:15');
      perform pg_temp.rodada(date '2026-11-11', '19:30');
      perform pg_temp.rodada(date '2026-11-12', '09:00');
      perform pg_temp.rodada(date '2026-11-12', '09:15');
      perform pg_temp.rodada(date '2026-11-12', '17:00');
      v_f := pg_temp.foto();
      if c.modo = 'desligado' then v_ant := v_f; end if;
      v_k := v_k || jsonb_build_object(c.modo || ':' || c.freio || ':' || c.lista, v_f = v_ant);
      v_s := v_s || jsonb_build_object(c.modo || ':' || c.freio || ':' || c.lista,
               (select coalesce(string_agg(so.service_order_number || ':' || m.modo || ':' || m.estado, ',' order by so.service_order_number, m.modo), '')
                  from public.agenda_cliente_mensagens m join public.service_orders so on so.id = m.service_order_id where m.tipo = 'semana' and so.service_order_number like 'OS-K%'
                                                                                                                          or (m.tipo = 'semana' and so.service_order_number = 'OS-F6')));
      v_q := v_q || jsonb_build_object(c.modo || ':' || c.freio || ':' || c.lista,
               (select count(*) from public.whatsapp_send_queue q join public.agenda_cliente_mensagens m on m.id = q.source_ref_id where m.tipo = 'semana'));
      v_ac := v_ac || jsonb_build_object(c.modo || ':' || c.freio || ':' || c.lista,
               (select count(*) from public.agenda_acoes a where a.tipo = 'cliente' and a.depois ->> 'tipo' = 'semana' and a.contada_em is null));
      perform pg_temp.desfaz();
    exception when sqlstate 'P0001' then
      if sqlerrm <> '__desfaz__' then raise; end if;
    end;
  end loop;
  r := pg_temp.ok(r, 'C11a desligadas: nenhuma semana, nada na fila', v_s ->> 'desligado:false:false' = '' and (v_q ->> 'desligado:false:false')::int = 0, v_s::text);
  r := pg_temp.ok(r, 'C11b em teste: as 11 de hoje iguais às desligadas (as mensagens, os textos, a hora, a aprovação, a fila, as ações, as perguntas)',
    (v_k ->> 'sombra:false:false')::boolean, null);
  r := pg_temp.ok(r, 'C11c em teste: só registra (as semanas em sombra, a ação contada: fora do fechamento), nada na fila',
    v_s ->> 'sombra:false:false' like '%OS-K1:sombra:registrada%' and v_s ->> 'sombra:false:false' not like '%:ligado:%' and (v_q ->> 'sombra:false:false')::int = 0
    and (v_ac ->> 'sombra:false:false')::int = 0, v_s ->> 'sombra:false:false');
  r := pg_temp.ok(r, 'C11d ligadas e na lista COM o freio (o caso real, R8.6): as 11 de hoje iguais, as semanas em teste, nada novo na fila',
    (v_k ->> 'ligado:true:true')::boolean and v_s ->> 'ligado:true:true' like '%OS-K1:sombra:registrada%' and v_s ->> 'ligado:true:true' not like '%:ligado:%'
    and (v_q ->> 'ligado:true:true')::int = 0, v_s ->> 'ligado:true:true');
  r := pg_temp.ok(r, 'C11e ligadas com o freio, fora da lista: o mesmo', (v_k ->> 'ligado:true:false')::boolean and (v_q ->> 'ligado:true:false')::int = 0, v_s ->> 'ligado:true:false');
  r := pg_temp.ok(r, 'C11e2 com o freio, as semanas em teste são as mesmas do teste (uma por OS e semana nos 2 dias: o freio não faz a semana nascer de novo a cada dia)',
    v_s ->> 'ligado:true:true' = v_s ->> 'sombra:false:false' and v_s ->> 'ligado:true:false' = v_s ->> 'sombra:false:false', v_s::text);
  r := pg_temp.ok(r, 'C11f o controle (ligadas, sem o freio, na lista): muda — a semana do Otávio ligada, e o M1 do Wagner sai da quinta para a véspera',
    not (v_k ->> 'controle:false:true')::boolean and v_s ->> 'controle:false:true' like '%OS-K1:ligado:%', v_s ->> 'controle:false:true');
  perform pg_temp.gravar(r);
end
$c$;

-- ── C12. Uma vez por dia, sem ler antes ─────────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  v   jsonb;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C12 uma vez por dia', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.prepara('sombra', false);
    -- o dublê: a carteira lança. Antes das 17:00 o passo não a lê; às 17:00 lê (e o dublê morde)
    create or replace function public.os_carteira(p_hoje date default public._hoje_brt())
     returns table (service_order_id uuid, numero text, status text, quote_status text, eh_orcamento boolean, cliente text, cliente_curto text, unidade text, valor numeric,
                    aprovada_em date, sinal_previsto numeric, sinal_pago numeric, sinal_pendente numeric, agendada_de date, agendada_ate date)
     language plpgsql stable as $d$ begin raise exception 'dublê: a carteira foi lida' using errcode = 'P0098'; end $d$;
    v := pg_temp.passo_sem_ler(date '2026-11-11', '16:45');
    r := pg_temp.ok(r, 'C12a antes das 17:00: {pulado: cedo}, sem ler a carteira', v = '{"pulado": "cedo"}', v::text);
    r := pg_temp.ok(r, 'C12b às 17:00 o passo lê (o dublê morde: o contraste)', pg_temp.lanca($q$select pg_temp.passo(date '2026-11-11', '17:00')$q$) = 'P0098', null);
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
    values (pg_temp.em(date '2026-11-11', '17:00'), date '2026-11-11', pg_temp.em(date '2026-11-11', '17:00'), 'ligado', 'ligado',
            '{"semana": {"registradas": 0, "modo": "sombra", "puladas": {}, "erros_os": 0}}', 0, 10, 'cliente', 'ligado', 'ligado');
    v := pg_temp.passo_sem_ler(date '2026-11-11', '17:15');
    r := pg_temp.ok(r, 'C12c depois de rodar no dia: {pulado: ja_rodou}, sem ler a carteira', v = '{"pulado": "ja_rodou"}', v::text);
    v := pg_temp.passo_sem_ler(date '2026-11-12', '16:59');
    r := pg_temp.ok(r, 'C12d no dia seguinte, antes das 17:00: cedo de novo', v = '{"pulado": "cedo"}', v::text);
    update public.agenda_config set modo_cliente_camadas = 'desligado' where id;
    v := pg_temp.passo_sem_ler(date '2026-11-12', '17:00');
    r := pg_temp.ok(r, 'C12e desligadas: {pulado: desligado}, sem ler a carteira', v = '{"pulado": "desligado"}', v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- desligadas, a rodada nem chama o passo: o dublê do passo lança, e a rodada não registra falha nem a chave
    perform pg_temp.prepara('desligado', false);
    create or replace function public._agenda_cliente_semana(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $d$
    begin raise exception 'dublê: o passo semana foi chamado' using errcode = 'P0098'; end $d$;
    v := pg_temp.rodada(date '2026-11-11', '17:00');
    r := pg_temp.ok(r, 'C12f desligadas: a rodada não chama o passo (sem a chave semana, sem falha)', not (v -> 'contagens' ? 'semana')
      and not exists (select 1 from jsonb_array_elements(v -> 'falhas') f where f ->> 'passo' = 'semana'), v::text);
    update public.agenda_config set modo_cliente_camadas = 'sombra' where id;
    v := pg_temp.rodada(date '2026-11-11', '17:15');
    r := pg_temp.ok(r, 'C12g em teste: a rodada chama o passo (o dublê morde: o contraste)', exists (select 1 from jsonb_array_elements(v -> 'falhas') f where f ->> 'passo' = 'semana'), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- de ponta a ponta: a rodada de 17:00 roda o passo e grava; a de 17:15 não relê
    perform pg_temp.prepara('sombra', false);
    v := pg_temp.rodada(date '2026-11-11', '17:00');
    r := pg_temp.ok(r, 'C12h a rodada das 17:00 grava a semana em contagens (registradas)', v #> '{contagens,semana}' ? 'registradas', (v -> 'contagens' -> 'semana')::text);
    v := pg_temp.rodada(date '2026-11-11', '17:15');
    r := pg_temp.ok(r, 'C12i a rodada das 17:15: ja_rodou', v #>> '{contagens,semana,pulado}' = 'ja_rodou', (v -> 'contagens' -> 'semana')::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── C13. O texto ao cliente ─────────────────────────────────────────────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  x   record;
  v_n int := 0;
  v_ruins text;
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C13 o texto', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.prepara('ligado', false, true);
    perform pg_temp.passo(date '2026-11-11', '17:00');
    perform pg_temp.plano('406', array[date '2026-11-23', date '2026-11-24', date '2026-11-28']);
    perform pg_temp.passo(date '2026-11-12', '17:00');
    for x in select m.texto, right(so.id::text, 3) as n from public.agenda_cliente_mensagens m join public.service_orders so on so.id = m.service_order_id where m.tipo = 'semana' loop
      v_n := v_n + 1;
      if not pg_temp.limpo(x.texto, x.n) then v_ruins := concat_ws(' | ', v_ruins, x.texto); end if;
    end loop;
    r := pg_temp.ok(r, 'C13a a varredura de todas as semanas geradas: há texto (≥ 3), e nenhum tem valor, número de OS, data de pronto, nome de outro cliente ou passa de 400',
      v_n >= 3 and v_ruins is null, format('%s textos; ruins: %s', v_n, coalesce(v_ruins, 'nenhum')));
    r := pg_temp.ok(r, 'C13b a varredura reprova o texto plantado: o vazio, o valor, o número de OS, o nome de outro cliente, a data de pronto',
      not pg_temp.limpo('', '401') and not pg_temp.limpo(null, '401')
      and not pg_temp.limpo('Otávio, o serviço custa R$ 900,00 e está previsto para a semana de 23/11.', '401')
      and not pg_temp.limpo('Otávio, a OS-K1 está prevista para a semana de 23/11.', '401')
      and not pg_temp.limpo('Otávio, depois do Wagner, o serviço está previsto para a semana de 23/11.', '401')
      and not pg_temp.limpo('Otávio, o serviço está previsto para a semana de 23/11, tudo pronto até sexta 27/11.', '401')
      and pg_temp.limpo('Otávio, o serviço está previsto para a semana de 23/11.', '401'), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

select teste, ok, detalhe from _resultado order by ok, teste;
rollback;
