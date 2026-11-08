-- Prova do pacote final da Fase 7f da Agenda de Produção (P9): a semana que mudou (o "Se mudar" do M12) no lugar do M6 remarcado, a saúde da comunicação com a equipe
-- e o cliente, e o dado que põe o previsto, o convite e as camadas em teste (migrations 20261109101200 e 20261109101900; spec-fase7f §5.6, §6.3, §6.5, §11 aceites 6
-- e 7, R8.5-20 a 25, R8.6, R8.8, R8.12, R8.13, R8.14; o pedido do fio, p9-pedido.md).
-- bancada: depende de 20261109101200
--
--   P0   sempre: a nova (assinatura, invoker, volatile, search_path, sem grant); as 5 recriadas com as portas de produção; o nulo
--   M1   a semana que mudou de verdade: o plano saiu da semana dita → a semana que mudou (o texto aprovado, literal), pedida, com a pergunta; NÃO o M6; a semana nova
--        só vira o prometido depois de enviada; o tique seguinte não recria; o *manda cliente* faz sair; de novo fora da semana nova; pedida mesmo com o tipo liberado
--   M2   quem não recebe: dentro da semana dita (nada); duas semanas, a semana que não saiu, sem a semana dita, esperando peça, o dono deu os dias (o caminho de hoje)
--   M3   em teste, com o freio e desligada: o M6 de hoje byte a byte (as 11) e a semana que mudou só registrada; o M6 vivo sai do caminho quando ela nasce de verdade
--   M4   a revalidação (sai; em teste; a semana nova também saiu; o prometido mudou) e o caminho de volta (o plano volta à semana dita; vai a outra; pela fila)
--   M5   o texto: limpo, a segunda da semana, o que falta = 22023, a 1ª mensagem; a varredura reprova o plantado
--   S    a saúde: os 7 zeros novos em 0, cada um com um caso plantado = 1 e o ok caindo; o que não conta; os números contra o que se plantou; só com o modo fora de desligado
--   D    o dado 20261109101900 numa subtransação: desligado → sombra nos 3; o resto igual; 2× igual; a trava (um ligado; sem a função do P9); o DESFAZER; só UPDATE
--   K9   as cópias só mudam nos blocos do P9; a migration cria e recria só o que diz; nada de dado
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela, só o P0 roda; o resto sai PULADO: usa a fixture da 7f e as OS do teste do P6, que nunca rodam em produção.
--
-- A fixture é a da 7f (fixture-fase7f.sql) e, por cima dela, as OS do cliente do teste do P6 (pg_temp.prepara, copiado de agenda_fase7f_cliente.sql): Otávio (OS-K1,
-- por estimativa, compra feita, o plano em 23 e 24/11) é quem ouve a semana de 23/11 e vê o plano andar. O relógio: seg 16/11/2026, 17:00 (a rodada do fechamento).
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
-- O texto sem os blocos e as marcas DESTE pacote ("-- FASE 7f: (7f P9 … -- FASE 7f: fim"). Os blocos da 7f de antes (o P6, o P7) ficam: a origem os tem.
create function pg_temp.sem_p9(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro boolean := false;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- (FASE 7f: \(7f P9|\(7f P9)' then
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
-- o código de uma migration, sem as linhas de comentário
create function pg_temp.codigo(p text) returns text language sql immutable as $f$
  select string_agg(l, E'\n' order by o) from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o) where l !~ '^\s*--'
$f$;
create function pg_temp.na_bancada9() returns boolean language sql stable as $f$
  select pg_temp.na_bancada() and coalesce(current_setting('agenda_teste.mig_mudou_fase7f', true), '') <> ''
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
-- A mensagem semana que mudou mais nova da OS
create function pg_temp.mudou(p_n text) returns public.agenda_cliente_mensagens language sql stable as $f$
  select m from public.agenda_cliente_mensagens m where m.service_order_id = pg_temp.os(p_n) and m.tipo = 'semana' and m.variante = 'mudou'
   order by m.criada_em desc, m.id desc limit 1
$f$;
create function pg_temp.n_mudou(p_n text, p_modo text default null) returns int language sql stable as $f$
  select count(*)::int from public.agenda_cliente_mensagens m where m.service_order_id = pg_temp.os(p_n) and m.tipo = 'semana' and m.variante = 'mudou'
     and (p_modo is null or m.modo = p_modo)
$f$;
create function pg_temp.m6(p_n text) returns public.agenda_cliente_mensagens language sql stable as $f$
  select m from public.agenda_cliente_mensagens m where m.service_order_id = pg_temp.os(p_n) and m.tipo = 'pode_atrasar' order by m.criada_em desc, m.id desc limit 1
$f$;
create function pg_temp.n_m6(p_n text) returns int language sql stable as $f$
  select count(*)::int from public.agenda_cliente_mensagens m where m.service_order_id = pg_temp.os(p_n) and m.tipo = 'pode_atrasar'
$f$;
-- O passo do atraso (a rodada do cliente chama este passo antes do material), num instante
create function pg_temp.atraso(p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.hoje', p_dia::text, true);
  return public._agenda_cliente_atraso(p_dia, pg_temp.em(p_dia, p_hora));
end $f$;
-- A saúde da comunicação num instante (a porta: sem usuário, o service_role/postgres da bancada)
create function pg_temp.saude(p_dia date default date '2026-11-16', p_hora text default '18:00') returns jsonb language sql stable as $f$
  select public._agenda_saude_comunicacao(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
-- Uma mensagem à equipe plantada (só para a saúde): ligada, no estado e na hora dados
create function pg_temp.equipe_msg(p_quem text, p_dia date, p_tipo text, p_enviar timestamptz, p_estado text default 'enfileirada', p_chave text default null,
                                   p_leitura jsonb default null, p_resposta_em timestamptz default null, p_modo text default 'ligado', p_dias date[] default null)
returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key, leitura, resposta_texto, resposta_em,
                                              dias, criada_em)
  values (pg_temp.p(p_quem), p_dia, p_tipo, p_modo, 'mensagem plantada do teste', p_enviar, p_estado, case when p_estado = 'recusada' then 'teto' end,
          coalesce(p_chave, format('agenda-equipe:%s:%s:%s:teste:%s', p_tipo, pg_temp.p(p_quem), p_dia, md5(random()::text))) || case when p_modo = 'sombra' then ':sombra' else '' end,
          p_leitura, case when p_resposta_em is not null then 'sim' end, p_resposta_em, p_dias, p_enviar - interval '1 hour')
  returning id into v;
  return v;
end $f$;
-- Uma mensagem ao cliente plantada (só para a saúde)
create function pg_temp.cliente_msg(p_n text, p_tipo text, p_variante text, p_dia date, p_enviada timestamptz, p_aprov text default 'livre',
                                    p_prom text default null, p_faixa_de date default null, p_faixa_ate date default null, p_base jsonb default '{}', p_modo text default 'ligado')
returns uuid language plpgsql as $f$
declare
  v uuid := gen_random_uuid();
begin
  insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de, faixa_ate, prometido_tipo, modo, texto, base,
                                               enviar_em, valida_ate, aprovacao, aprovada_em, estado, dedupe_key, enviada_em, criada_em, recusa_motivo)
  values (v, pg_temp.cli(p_n), pg_temp.os(p_n), p_tipo, p_variante, 'rodada', p_dia, p_faixa_de, p_faixa_ate, p_prom, p_modo, 'mensagem plantada do teste', p_base,
          coalesce(p_enviada, timestamptz '2026-11-12 09:00-03'), coalesce(p_enviada, timestamptz '2026-11-12 09:00-03') + interval '4 hours', p_aprov,
          case when p_aprov in ('aprovada', 'segurada') then coalesce(p_enviada, timestamptz '2026-11-12 09:00-03') - interval '1 hour' end,
          case when p_aprov = 'segurada' then 'recusada' when p_enviada is null then 'registrada' else 'enviada' end, 'agenda-cliente:teste:' || v, p_enviada,
          coalesce(p_enviada, timestamptz '2026-11-12 09:00-03') - interval '1 day', case when p_aprov = 'segurada' then 'segurada' end);
  return v;
end $f$;

-- ── P0. A forma e as portas (sem fixture) ───────────────────────────────────────────────────────────
insert into _resultado
select 'P0a a nova (_agenda_cliente_semana_mudou): invoker, volatile, search_path fixo, e ninguém de fora (nem o service_role)',
       p.oid is not null and not p.prosecdef and p.provolatile = 'v' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute')
       and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x where x.grantee = 0 and x.privilege_type = 'EXECUTE'),
       coalesce(p.oid::regprocedure::text, 'NÃO EXISTE')
  from (select to_regprocedure('public._agenda_cliente_semana_mudou(uuid, jsonb, date, timestamptz, timestamptz, timestamptz)') as oid) o
  left join pg_proc p on p.oid = o.oid;
-- as recriadas: a forma e as portas de produção (sql/wf7f9_md5_antes, dom 08/11)
with f(sig, definer, vol, autent, servico) as (values
  ('public._agenda_cliente_texto(text, text, uuid, jsonb, date)', false, 's', true, true),
  ('public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamp with time zone, timestamp with time zone, text, text, timestamp with time zone, uuid)', true, 'v', false, false),
  ('public._agenda_cliente_revalidar(uuid, timestamp with time zone)', true, 's', false, false),
  ('public._agenda_cliente_atraso(date, timestamp with time zone)', false, 'v', false, false),
  ('public._agenda_saude_comunicacao(date, timestamp with time zone)', true, 's', true, true))
insert into _resultado
select 'P0b as 5 recriadas com a forma e as portas de produção: anon e PUBLIC nunca; authenticated e service_role como antes; 1 assinatura por nome',
       count(p.oid) = 5
       and bool_and(p.prosecdef = f.definer and p.provolatile = f.vol and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and has_function_privilege('authenticated', p.oid, 'execute') = f.autent and has_function_privilege('service_role', p.oid, 'execute') = f.servico
                    and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x where x.grantee = 0 and x.privilege_type = 'EXECUTE')
                    and (select count(*) from pg_proc y where y.pronamespace = p.pronamespace and y.proname = p.proname) = 1),
       string_agg(f.sig, '; ') filter (where p.oid is null or p.prosecdef <> f.definer or p.provolatile <> f.vol)
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);
insert into _resultado
select 'P0c a nova lança 22004 sem a OS (a porta do nulo)', pg_temp.lanca($q$select public._agenda_cliente_semana_mudou(null, '{}', date '2026-11-16', now(), now(), now())$q$) = '22004', null;

-- ── M1. A semana que mudou, de verdade ──────────────────────────────────────────────────────────────
do $c$
declare
  r    jsonb := '[]';
  v    jsonb;
  s    public.agenda_cliente_mensagens;
  m    public.agenda_cliente_mensagens;
  q    public.agenda_perguntas;
  t    text;
  c_txt constant text := 'Otávio, o serviço no seu veleiro precisou passar para a semana de 30/11. Desculpe pela mudança. O dia certo eu confirmo na véspera. Se algum dia dessa semana não der, me diga.';
begin
  if not pg_temp.na_bancada9() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M1 a semana que mudou', true, 'PULADO: sem agenda_teste.fase7f ou a migration como texto (rode pela bancada)'));
    return;
  end if;
  -- o Otávio ouviu a semana de 23/11 (a semana enviada qui 12/11: prometido faixa 23 a 27/11); o plano vai para 30/11 e 01/12; as camadas ligadas, sem o freio
  begin
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    v := pg_temp.atraso(date '2026-11-16', '17:00');
    m := pg_temp.mudou('401');
    r := pg_temp.ok(r, 'M1a o plano saiu da semana dita: nasce a semana que mudou (semana/mudou), ligada, faixa da semana nova (30/11 a 04/12), prometido faixa',
      m.id is not null and m.modo = 'ligado' and m.faixa_de = date '2026-11-30' and m.faixa_ate = date '2026-12-04' and m.dia_alvo = date '2026-11-30'
      and m.prometido_tipo = 'faixa' and m.dedupe_key = format('agenda-cliente:semana:%s:mudou:2026-11-30', pg_temp.os('401')), row_to_json(m)::text);
    r := pg_temp.ok(r, 'M1b o texto é o "Se mudar" aprovado (AG7-36), literal, só com o nome, o serviço e a semana', m.texto = c_txt, m.texto);
    r := pg_temp.ok(r, 'M1c e NÃO o M6 remarcado com o dia (nenhum pode_atrasar nesta OS)', pg_temp.n_m6('401') = 0, v::text);
    r := pg_temp.ok(r, 'M1d nasce pedida, esperando o dono (aguardando_dono), com a pergunta cliente_aprovar',
      m.aprovacao = 'pedida' and m.estado = 'aguardando_dono' and m.pergunta_id is not null, m.aprovacao || '/' || m.estado);
    select * into q from public.agenda_perguntas x where x.id = m.pergunta_id;
    r := pg_temp.ok(r, 'M1e a pergunta ao dono diz o que ele ouviu e o que passa a ouvir, com a mensagem pronta e as palavras',
      q.tipo = 'cliente_aprovar' and q.modo = 'ligado' and q.estado = 'aberta'
      and q.texto ~ ('^Vou mudar o que Otávio ouviu: era a semana de 23/11, fica a semana de 30/11\. Mensagem pronta, sai .+: "' || regexp_replace(c_txt, '([.()])', '\\\1', 'g')
                     || '"\. \*manda cliente Otávio\* ou \*segura cliente Otávio\*\.$'), q.texto);
    r := pg_temp.ok(r, 'M1f as contagens do passo: semana_mudou 1 (só quando houve)', (v ->> 'semana_mudou')::int = 1 and (v ->> 'semana_mudou_teste')::int = 0, v::text);
    r := pg_temp.ok(r, 'M1g a semana nova ainda NÃO é o prometido (só depois de enviada): o prometido segue 23 a 27/11, da semana de antes',
      exists (select 1 from public.os_planejamento p where p.service_order_id = pg_temp.os('401') and p.prometido_de = date '2026-11-23' and p.prometido_ate = date '2026-11-27'
                and p.prometido_mensagem_id = s.id), null);
    -- o tique seguinte não recria nem pergunta de novo
    v := pg_temp.atraso(date '2026-11-16', '17:15');
    r := pg_temp.ok(r, 'M1h o tique seguinte não recria (a chave) nem abre outra pergunta, e o M6 continua sem nascer',
      pg_temp.n_mudou('401') = 1 and pg_temp.n_m6('401') = 0 and (select count(*) from public.agenda_perguntas x where x.tipo = 'cliente_aprovar' and x.service_order_id = pg_temp.os('401') and x.estado = 'aberta') = 1
      and not (v ? 'semana_mudou'), v::text);
    -- o dono manda: a mensagem sai, e só então a semana nova vira o prometido
    v := public.agenda_cliente_decidir_dito(pg_temp.adm(), 'manda', 'Otávio', 'whatsapp', date '2026-11-16', pg_temp.em(date '2026-11-16', '18:00'));
    m := pg_temp.mudou('401');
    perform public._agenda_cliente_fila(date '2026-11-17', m.enviar_em);
    perform pg_temp.saiu(m.id, m.enviar_em + interval '1 minute');
    m := pg_temp.mudou('401');
    r := pg_temp.ok(r, 'M1i com o *manda cliente*, ela sai (aprovada, enviada) e a semana nova vira o prometido: faixa 30/11 a 04/12, pela mensagem que mudou',
      m.aprovacao = 'aprovada' and m.estado = 'enviada'
      and exists (select 1 from public.os_planejamento p where p.service_order_id = pg_temp.os('401') and p.prometido_tipo = 'faixa'
                    and p.prometido_de = date '2026-11-30' and p.prometido_ate = date '2026-12-04' and p.prometido_mensagem_id = m.id), v::text || ' | ' || m.estado);
    -- a saúde: a semana que mudou saiu com o dono (aprovada): promessa_mudou_sem_dono 0; a semana não é dia ouvido
    r := pg_temp.ok(r, 'M1j a saúde: promessa_mudou_sem_dono 0 e semana_como_dia_ouvido 0 com a semana que mudou enviada pelo dono',
      (pg_temp.saude(date '2026-11-17') ->> 'promessa_mudou_sem_dono')::int = 0 and (pg_temp.saude(date '2026-11-17') ->> 'semana_como_dia_ouvido')::int = 0
      and not public._agenda_cliente_ouviu(pg_temp.os('401'), date '2026-11-30', pg_temp.em(date '2026-11-17', '10:00')), null);
    -- e o plano anda de novo, para fora da semana nova (07/12): outra semana que mudou, contra a semana nova dita
    perform pg_temp.plano('401', array[date '2026-12-07']);
    v := pg_temp.atraso(date '2026-11-18', '17:00');
    r := pg_temp.ok(r, 'M1k o plano saiu também da semana nova: outra semana que mudou ("era a semana de 30/11, fica a semana de 07/12"), pedida',
      pg_temp.n_mudou('401') = 2 and (pg_temp.mudou('401')).faixa_de = date '2026-12-07' and (pg_temp.mudou('401')).aprovacao = 'pedida'
      and exists (select 1 from public.agenda_perguntas x where x.id = (pg_temp.mudou('401')).pergunta_id and x.texto like 'Vou mudar o que Otávio ouviu: era a semana de 30/11, fica a semana de 07/12.%')
      and pg_temp.n_m6('401') = 0, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- mesmo com o tipo semana liberado (a d11: sem os 3 dias de aprovação), a semana que mudou nasce pedida; a semana de antes saiu livre
    perform pg_temp.prepara('ligado', false, true);
    update public.agenda_config set cliente_aprovacao_dias = 0 where id;
    s := pg_temp.semana_enviada('401');
    update public.agenda_config set cliente_aprovacao_dias = 0 where id;
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    v := pg_temp.atraso(date '2026-11-16', '17:00');
    r := pg_temp.ok(r, 'M1l com o tipo semana liberado (cliente_aprovacao_dias 0), a semana de antes saiu livre e a que mudou nasce pedida (o *manda cliente* sempre)',
      s.aprovacao = 'livre' and public._agenda_cliente_tipo_liberado('semana') and (pg_temp.mudou('401')).aprovacao = 'pedida'
      and (pg_temp.mudou('401')).estado = 'aguardando_dono', s.aprovacao || ' / ' || (pg_temp.mudou('401')).aprovacao);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── M2. Quem não recebe a semana que mudou: o M6 de hoje ou nada ────────────────────────────────────
do $c$
declare
  r jsonb := '[]';
  v jsonb;
  s public.agenda_cliente_mensagens;
begin
  if not pg_temp.na_bancada9() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M2 quem não recebe', true, 'PULADO: rode pela bancada'));
    return;
  end if;
  begin
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    perform pg_temp.plano('401', array[date '2026-11-25', date '2026-11-26']);
    v := pg_temp.atraso(date '2026-11-16', '17:00');
    r := pg_temp.ok(r, 'M2a o plano andou DENTRO da semana dita (25 e 26/11): nada sai (nem a semana que mudou, nem o M6)',
      pg_temp.n_mudou('401') = 0 and pg_temp.n_m6('401') = 0 and not (v ? 'semana_mudou'), v::text);
    -- duas semanas (27 e 30/11): o texto de duas semanas não teve o OK (R8.3-2): o M6 de hoje
    perform pg_temp.plano('401', array[date '2026-11-27', date '2026-11-30']);
    v := pg_temp.atraso(date '2026-11-16', '17:15');
    r := pg_temp.ok(r, 'M2b o plano cruza a semana (27 e 30/11): o M6 de hoje (remarcado), sem a semana que mudou',
      pg_temp.n_mudou('401') = 0 and (pg_temp.m6('401')).variante = 'remarcado', v::text);
    -- e todo depois da semana dita (04 e 07/12, duas semanas): também o M6 de hoje, com o dia novo; sem a guarda, a semana que mudou iria sem a faixa e a OS cairia em erro
    perform pg_temp.plano('401', array[date '2026-12-04', date '2026-12-07']);
    v := pg_temp.atraso(date '2026-11-16', '17:30');
    r := pg_temp.ok(r, 'M2b2 o plano cruza a semana, todo depois da dita (04 e 07/12): o M6 de hoje, com o dia novo, sem erro e sem a semana que mudou',
      pg_temp.n_mudou('401') = 0 and (pg_temp.m6('401')).dia_alvo = date '2026-12-04' and (v ->> 'erros_os')::int = 0, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a semana nova é a mesma semana (o sábado 28/11 marcado: o fim passou do último dia útil da semana dita): o M6 de hoje
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    perform pg_temp.plano('401', array[date '2026-11-23', date '2026-11-28']);
    v := pg_temp.atraso(date '2026-11-16', '17:00');
    r := pg_temp.ok(r, 'M2c o plano ainda na semana dita, até o sábado 28/11 marcado: não é outra semana (mesma_semana): nenhuma semana que mudou; segue o caminho de hoje',
      pg_temp.n_mudou('401') = 0
      and public._agenda_cliente_semana_mudou(pg_temp.os('401'), public._agenda_cliente_risco(pg_temp.os('401'), date '2026-11-16'), date '2026-11-16',
                                              pg_temp.em(date '2026-11-16', '17:30'), pg_temp.em(date '2026-11-17', '09:00'), null) ->> 'motivo' = 'mesma_semana', v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- quem não ouviu a semana (o dia firme dito pelo dono): o M6 de hoje, com o dia
    perform pg_temp.prepara('ligado', false, true);
    perform public._agenda_cliente_gravar_prometido(pg_temp.os('401'), 'firme', date '2026-11-23', date '2026-11-24', 'dono', null, pg_temp.em(date '2026-11-12', '10:00'));
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    v := pg_temp.atraso(date '2026-11-16', '17:00');
    r := pg_temp.ok(r, 'M2d sem a semana enviada (o dia firme do dono): o M6 de hoje (remarcado, com o dia), sem a semana que mudou',
      pg_temp.n_mudou('401') = 0 and (pg_temp.m6('401')).variante = 'remarcado' and (pg_temp.m6('401')).dia_alvo = date '2026-11-30', v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a semana registrada e NÃO enviada (o dono não mandou): não é semana dita, e o prometido não existe; nada a avisar
    perform pg_temp.prepara('ligado', false, true);
    perform pg_temp.passo(date '2026-11-11', '17:00');
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    v := pg_temp.atraso(date '2026-11-16', '17:00');
    r := pg_temp.ok(r, 'M2e a semana que não saiu não é dita: nem a semana que mudou, nem o M6 (sem prometido)',
      pg_temp.n_mudou('401') = 0 and pg_temp.n_m6('401') = 0, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a OS esperando peça (o filtro da semana, R8.5-21): o M6 de hoje
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    update public.service_orders set status = 'awaiting_parts' where id = pg_temp.os('401');
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    v := pg_temp.atraso(date '2026-11-16', '17:00');
    r := pg_temp.ok(r, 'M2f a OS esperando peça: o M6 de hoje, sem a semana que mudou (status)',
      pg_temp.n_mudou('401') = 0 and pg_temp.n_m6('401') = 1, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a OS que deixou de ser marcada pela estimativa (o dono deu os dias): o dia já é seguro, o M6 de hoje
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01'], 'dono');
    update public.os_planejamento set dias = 2, estimativa_fonte = 'dono', estimativa_em = timestamptz '2026-11-15 10:00-03' where service_order_id = pg_temp.os('401');
    v := pg_temp.atraso(date '2026-11-16', '17:00');
    r := pg_temp.ok(r, 'M2g o dono deu os dias (fora da camada): o M6 de hoje',
      pg_temp.n_mudou('401') = 0 and (pg_temp.m6('401')).variante = 'remarcado', v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── M3. Em teste, com o freio e desligada: o M6 de hoje, byte a byte ────────────────────────────────
do $c$
declare
  r   jsonb := '[]';
  v   jsonb;
  vd  jsonb;
  s   public.agenda_cliente_mensagens;
  f_d text;
  f_x text;
  modo text;
begin
  if not pg_temp.na_bancada9() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M3 em teste', true, 'PULADO: rode pela bancada'));
    return;
  end if;
  -- a régua: as camadas desligadas depois da semana enviada (o que a publicação faz se voltar atrás): o M6 de hoje, e a foto das 11
  begin
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    update public.agenda_config set modo_cliente_camadas = 'desligado' where id;
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    vd := pg_temp.atraso(date '2026-11-16', '17:00');
    f_d := pg_temp.foto();
    r := pg_temp.ok(r, 'M3a desligadas: o M6 de hoje (remarcado), nenhuma semana que mudou, as contagens sem chave nova',
      pg_temp.n_mudou('401') = 0 and (pg_temp.m6('401')).variante = 'remarcado' and not (vd ? 'semana_mudou') and not (vd ? 'semana_mudou_teste'), vd::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  foreach modo in array array['sombra', 'freio'] loop
    begin
      perform pg_temp.prepara('ligado', false, true);
      s := pg_temp.semana_enviada('401');
      if modo = 'sombra' then
        update public.agenda_config set modo_cliente_camadas = 'sombra' where id;
      else
        update public.agenda_config set gestor_so_propor = true, gestor_so_propor_em = timestamptz '2026-11-05 02:43+00' where id;
      end if;
      perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
      v := pg_temp.atraso(date '2026-11-16', '17:00');
      f_x := pg_temp.foto();
      r := pg_temp.ok(r, format('M3b %s: o M6 de hoje sai como desligado, byte a byte (as 11: as mensagens, o texto, a hora, a aprovação, a fila, as ações, as perguntas)',
                                case modo when 'sombra' then 'em teste' else 'ligadas com o freio' end),
        f_x = f_d and (pg_temp.m6('401')).variante = 'remarcado', case when f_x <> f_d then f_x end);
      r := pg_temp.ok(r, format('M3c %s: a semana que mudou só se registra — ":sombra", livre, sem pergunta ao dono, nada na fila, a ação contada',
                                case modo when 'sombra' then 'em teste' else 'com o freio' end),
        pg_temp.n_mudou('401', 'ligado') = 0 and pg_temp.n_mudou('401', 'sombra') = 1
        and (pg_temp.mudou('401')).dedupe_key like '%:sombra' and (pg_temp.mudou('401')).aprovacao = 'livre' and (pg_temp.mudou('401')).pergunta_id is null
        and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = (pg_temp.mudou('401')).id)
        and exists (select 1 from public.agenda_acoes a where a.id = (pg_temp.mudou('401')).acao_id and a.contada_em is not null and not a.executada),
        row_to_json(pg_temp.mudou('401'))::text);
      r := pg_temp.ok(r, format('M3d %s: as contagens dizem só o registro em teste (semana_mudou_teste 1, semana_mudou 0); o resto igual ao desligado',
                                case modo when 'sombra' then 'em teste' else 'com o freio' end),
        (v ->> 'semana_mudou_teste')::int = 1 and (v ->> 'semana_mudou')::int = 0
        and (v - 'semana_mudou' - 'semana_mudou_teste' - 'semana_mudou_desatualizadas') = vd, v::text || ' × ' || vd::text);
      v := pg_temp.atraso(date '2026-11-16', '17:15');
      r := pg_temp.ok(r, format('M3f %s: no tique seguinte o M6 continua vivo (só a de verdade o tira do caminho), e a de teste não se repete',
                                case modo when 'sombra' then 'em teste' else 'com o freio' end),
        (pg_temp.m6('401')).estado = 'aguardando_dono' and pg_temp.n_m6('401') = 1 and pg_temp.n_mudou('401', 'sombra') = 1, v::text);
      perform pg_temp.desfaz();
    exception when sqlstate 'P0001' then
      if sqlerrm <> '__desfaz__' then raise; end if;
    end;
  end loop;
  begin
    -- o M6 vivo (registrado com as camadas desligadas) sai do caminho quando a semana que mudou nasce de verdade
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    update public.agenda_config set modo_cliente_camadas = 'desligado' where id;
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    v := pg_temp.atraso(date '2026-11-16', '17:00');
    update public.agenda_config set modo_cliente_camadas = 'ligado' where id;
    v := pg_temp.atraso(date '2026-11-16', '17:15');
    r := pg_temp.ok(r, 'M3e o M6 vivo (de antes de as camadas ligarem) sai do caminho (desatualizada) quando a semana que mudou nasce de verdade: nunca os dois',
      pg_temp.n_mudou('401', 'ligado') = 1 and (pg_temp.m6('401')).estado = 'recusada' and (pg_temp.m6('401')).recusa_motivo = 'desatualizada', v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── M4. A revalidação e o caminho de volta ──────────────────────────────────────────────────────────
do $c$
declare
  r jsonb := '[]';
  v jsonb;
  s public.agenda_cliente_mensagens;
  m public.agenda_cliente_mensagens;
begin
  if not pg_temp.na_bancada9() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M4 a revalidação', true, 'PULADO: rode pela bancada'));
    return;
  end if;
  begin
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    perform pg_temp.atraso(date '2026-11-16', '17:00');
    m := pg_temp.mudou('401');
    r := pg_temp.ok(r, 'M4a a semana que mudou, como nasceu: a revalidação deixa sair (null)', public._agenda_cliente_revalidar(m.id, pg_temp.em(date '2026-11-17', '09:00')) is null,
      public._agenda_cliente_revalidar(m.id, pg_temp.em(date '2026-11-17', '09:00')));
    update public.agenda_config set modo_cliente_camadas = 'sombra' where id;
    r := pg_temp.ok(r, 'M4b as camadas de volta a teste: a que esperava não sai (tipo_em_teste)',
      public._agenda_cliente_revalidar(m.id, pg_temp.em(date '2026-11-17', '09:00')) = 'tipo_em_teste', null);
    update public.agenda_config set modo_cliente_camadas = 'ligado' where id;
    perform pg_temp.plano('401', array[date '2026-12-07']);
    r := pg_temp.ok(r, 'M4c a semana nova também saiu (o plano em 07/12): desatualizada', public._agenda_cliente_revalidar(m.id, pg_temp.em(date '2026-11-17', '09:00')) = 'desatualizada',
      public._agenda_cliente_revalidar(m.id, pg_temp.em(date '2026-11-17', '09:00')));
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    perform public._agenda_cliente_gravar_prometido(pg_temp.os('401'), 'firme', date '2026-11-30', date '2026-12-01', 'dono', null, pg_temp.em(date '2026-11-16', '18:00'));
    r := pg_temp.ok(r, 'M4d o prometido mudou depois que ela nasceu (o dono disse o dia): desatualizada (regra própria)',
      public._agenda_cliente_revalidar(m.id, pg_temp.em(date '2026-11-17', '09:00')) = 'desatualizada', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o caminho de volta: a que espera o dono sai do caminho quando o plano volta à semana dita, e a de outra semana nasce no lugar
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    perform pg_temp.atraso(date '2026-11-16', '17:00');
    m := pg_temp.mudou('401');
    perform pg_temp.plano('401', array[date '2026-11-24', date '2026-11-25']);
    v := pg_temp.atraso(date '2026-11-16', '17:15');
    r := pg_temp.ok(r, 'M4e o plano voltou à semana dita: a semana que mudou sai do caminho (recusada, desatualizada), contada; nada novo ao cliente',
      (select x.estado || ':' || coalesce(x.recusa_motivo, '') from public.agenda_cliente_mensagens x where x.id = m.id) = 'recusada:desatualizada'
      and (v ->> 'semana_mudou_desatualizadas')::int = 1 and pg_temp.n_m6('401') = 0, v::text);
    perform pg_temp.plano('401', array[date '2026-12-07', date '2026-12-08']);
    v := pg_temp.atraso(date '2026-11-16', '17:30');
    r := pg_temp.ok(r, 'M4f e o plano em outra semana (07/12): outra semana que mudou, para 07/12, pedida',
      pg_temp.n_mudou('401') = 2 and (pg_temp.mudou('401')).faixa_de = date '2026-12-07' and (pg_temp.mudou('401')).estado = 'aguardando_dono', v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- de ponta a ponta pela fila: aprovada, e o plano voltou à semana dita antes de sair: a fila a recusa, nada sai, o prometido fica o de antes
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    perform pg_temp.atraso(date '2026-11-16', '17:00');
    perform public.agenda_cliente_decidir_dito(pg_temp.adm(), 'manda', 'Otávio', 'whatsapp', date '2026-11-16', pg_temp.em(date '2026-11-16', '18:00'));
    m := pg_temp.mudou('401');
    perform pg_temp.plano('401', array[date '2026-11-24']);
    perform public._agenda_cliente_fila(date '2026-11-17', m.enviar_em);
    r := pg_temp.ok(r, 'M4g de ponta a ponta: a aprovada que perdeu o sentido na hora de sair é recusada, nada na fila, o prometido fica o da semana dita',
      (select x.estado from public.agenda_cliente_mensagens x where x.id = m.id) = 'recusada'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source_ref_id = m.id and q.status in ('pending', 'sending', 'sent'))
      and exists (select 1 from public.os_planejamento p where p.service_order_id = pg_temp.os('401') and p.prometido_mensagem_id = s.id),
      (select x.estado || ':' || coalesce(x.recusa_motivo, '') from public.agenda_cliente_mensagens x where x.id = m.id));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── M6. A função nova, chamada direto: cada saída ───────────────────────────────────────────────────
do $c$
declare
  r  jsonb := '[]';
  v  jsonb;
  s  public.agenda_cliente_mensagens;
  m  public.agenda_cliente_mensagens;
  c_risco constant jsonb := '{"risco": true, "variante": "remarcado", "faixa_de": "2026-11-30", "faixa_ate": "2026-12-01"}';
begin
  if not pg_temp.na_bancada9() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M6 as saídas', true, 'PULADO: rode pela bancada'));
    return;
  end if;
  begin
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    perform set_config('agenda.hoje', '2026-11-16', true);
    r := pg_temp.ok(r, 'M6a sem risco: não aplica (sem_risco)',
      public._agenda_cliente_semana_mudou(pg_temp.os('401'), '{"risco": false, "variante": "remarcado"}', date '2026-11-16', pg_temp.em(date '2026-11-16', '17:00'), pg_temp.em(date '2026-11-17', '09:00'), null) ->> 'motivo' = 'sem_risco', null);
    r := pg_temp.ok(r, 'M6b a peça e a execução: não aplica (sem_risco), o M6 de hoje',
      public._agenda_cliente_semana_mudou(pg_temp.os('401'), '{"risco": true, "variante": "peca"}', date '2026-11-16', pg_temp.em(date '2026-11-16', '17:00'), pg_temp.em(date '2026-11-17', '09:00'), null) ->> 'motivo' = 'sem_risco'
      and public._agenda_cliente_semana_mudou(pg_temp.os('401'), null, date '2026-11-16', pg_temp.em(date '2026-11-16', '17:00'), pg_temp.em(date '2026-11-17', '09:00'), null) ->> 'motivo' = 'sem_risco', null);
    update public.agenda_config set modo_cliente_camadas = 'desligado' where id;
    r := pg_temp.ok(r, 'M6c as camadas desligadas: não aplica (desligado)',
      public._agenda_cliente_semana_mudou(pg_temp.os('401'), c_risco, date '2026-11-16', pg_temp.em(date '2026-11-16', '17:00'), pg_temp.em(date '2026-11-17', '09:00'), null) ->> 'motivo' = 'desligado', null);
    update public.agenda_config set modo_cliente_camadas = 'ligado' where id;
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o prometido apontando para uma semana que NÃO saiu (gravado à mão), e o prometido firme apontando para uma semana que saiu: a semana não é a "dita"
    perform pg_temp.prepara('ligado', false, true);
    perform pg_temp.passo(date '2026-11-11', '17:00');
    m := pg_temp.sem('401');
    perform public._agenda_cliente_gravar_prometido(pg_temp.os('401'), 'faixa', date '2026-11-23', date '2026-11-27', 'mensagem', m.id, pg_temp.em(date '2026-11-12', '10:00'));
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    perform set_config('agenda.hoje', '2026-11-16', true);
    r := pg_temp.ok(r, 'M6d o prometido de uma semana que não saiu: não aplica (sem_semana_dita)',
      public._agenda_cliente_semana_mudou(pg_temp.os('401'), c_risco, date '2026-11-16', pg_temp.em(date '2026-11-16', '17:00'), pg_temp.em(date '2026-11-17', '09:00'), null) ->> 'motivo' = 'sem_semana_dita', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    perform public._agenda_cliente_gravar_prometido(pg_temp.os('401'), 'firme', date '2026-11-23', date '2026-11-24', 'mensagem', s.id, pg_temp.em(date '2026-11-13', '10:00'));
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    perform set_config('agenda.hoje', '2026-11-16', true);
    r := pg_temp.ok(r, 'M6e o prometido firme (mesmo apontando para a semana): não aplica (sem_semana_dita), o M6 de hoje',
      public._agenda_cliente_semana_mudou(pg_temp.os('401'), c_risco, date '2026-11-16', pg_temp.em(date '2026-11-16', '17:00'), pg_temp.em(date '2026-11-17', '09:00'), null) ->> 'motivo' = 'sem_semana_dita', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- sem a compra feita (o material sem conferir): a promessa nova é condicional, e o texto é o mesmo (o cartão só mostrou um "Se mudar")
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    update public.os_planejamento set material_conferido_em = null where service_order_id = pg_temp.os('401');
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    v := pg_temp.atraso(date '2026-11-16', '17:00');
    m := pg_temp.mudou('401');
    r := pg_temp.ok(r, 'M6f sem a compra feita: a semana que mudou nasce condicional (o que vira o prometido quando sair), com o mesmo texto aprovado',
      m.prometido_tipo = 'condicional' and m.texto like 'Otávio, o serviço no seu veleiro precisou passar para a semana de 30/11.%', coalesce(m.prometido_tipo, 'sem') || ' | ' || v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- com um motivo crítico passado ao registro: a mudança da promessa continua pedida (nunca a pergunta crítica)
    perform pg_temp.prepara('ligado', false, true);
    v := public._agenda_cliente_registrar('semana', 'mudou', pg_temp.os('401'), date '2026-11-30',
           '{"dia": "2026-11-30", "faixa_de": "2026-11-30", "faixa_ate": "2026-12-04", "n": 2, "dito_de": "2026-11-23", "dito_ate": "2026-11-27", "chave": "mudou:critica", "prometido_tipo": "faixa"}',
           pg_temp.em(date '2026-11-17', '09:00'), null, 'rodada', 'teto', pg_temp.em(date '2026-11-16', '17:00'));
    r := pg_temp.ok(r, 'M6g com motivo crítico, a semana que mudou nasce pedida (o *manda cliente*), não crítica', v ->> 'aprovacao' = 'pedida' and v ->> 'estado' = 'aguardando_dono', v::text);
    r := pg_temp.ok(r, 'M6h sem a semana dita no registro: 22023 (nunca a pergunta pela metade)',
      pg_temp.lanca($q$select public._agenda_cliente_registrar('semana', 'mudou', pg_temp.os('402'), date '2026-11-30',
           '{"dia": "2026-11-30", "faixa_de": "2026-11-30", "faixa_ate": "2026-12-04", "n": 2, "chave": "mudou:sem", "prometido_tipo": "faixa"}',
           pg_temp.em(date '2026-11-17', '09:00'), null, 'rodada', null, pg_temp.em(date '2026-11-16', '17:00'))$q$) = '22023', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a viva, com o plano indo direto a outra semana (sem voltar à dita): sai do caminho e a nova nasce
    perform pg_temp.prepara('ligado', false, true);
    s := pg_temp.semana_enviada('401');
    perform pg_temp.plano('401', array[date '2026-11-30', date '2026-12-01']);
    perform pg_temp.atraso(date '2026-11-16', '17:00');
    m := pg_temp.mudou('401');
    perform pg_temp.plano('401', array[date '2026-12-07', date '2026-12-08']);
    v := pg_temp.atraso(date '2026-11-16', '17:15');
    r := pg_temp.ok(r, 'M6i o plano foi direto a outra semana (07/12): a de 30/11 sai do caminho (desatualizada) e a nova nasce, uma pergunta aberta só',
      (select x.estado || ':' || coalesce(x.recusa_motivo, '') from public.agenda_cliente_mensagens x where x.id = m.id) = 'recusada:desatualizada'
      and (pg_temp.mudou('401')).faixa_de = date '2026-12-07' and (v ->> 'semana_mudou_desatualizadas')::int = 1
      and (select count(*) from public.agenda_perguntas x where x.tipo = 'cliente_aprovar' and x.service_order_id = pg_temp.os('401') and x.estado = 'aberta') = 1, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── M5. O texto ─────────────────────────────────────────────────────────────────────────────────────
do $c$
declare
  r jsonb := '[]';
  t text;
begin
  if not pg_temp.na_bancada9() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M5 o texto', true, 'PULADO: rode pela bancada'));
    return;
  end if;
  begin
    perform pg_temp.prepara('ligado', false, true);
    t := pg_temp.texto_semana('mudou', pg_temp.os('401'), '{"faixa_de": "2026-11-30", "primeira": false}', date '2026-11-16');
    r := pg_temp.ok(r, 'M5a o texto limpo: sem valor, sem número de OS, sem nome de outro cliente, sem data de pronto, sem dia exato, até 400 letras',
      pg_temp.limpo(t, '401') and length(t) <= 400 and t !~ '\(\d\d/\d\d\)' and t !~* '(segunda|terça|quarta|quinta|sexta|sábado),? \(?\d', t);
    r := pg_temp.ok(r, 'M5b a semana nova é a segunda da semana de faixa_de (quarta 02/12 → "semana de 30/11")',
      pg_temp.texto_semana('mudou', pg_temp.os('401'), '{"faixa_de": "2026-12-02", "primeira": false}', date '2026-11-16') like '%para a semana de 30/11. Desculpe pela mudança.%', null);
    r := pg_temp.ok(r, 'M5c sem a semana nova: 22023 (nunca o texto pela metade)',
      pg_temp.texto_semana('mudou', pg_temp.os('401'), '{"primeira": false}', date '2026-11-16') like 'lançou 22023:%', null);
    r := pg_temp.ok(r, 'M5d a variante que não existe na semana continua 22023',
      pg_temp.texto_semana('mudou_x', pg_temp.os('401'), '{"faixa_de": "2026-11-30"}', date '2026-11-16') like 'lançou 22023:%', null);
    t := pg_temp.texto_semana('mudou', pg_temp.os('401'), '{"faixa_de": "2026-11-30", "primeira": true}', date '2026-11-16');
    r := pg_temp.ok(r, 'M5e na 1ª mensagem (nunca, na prática): "Olá, <nome>! <a abertura de sempre> O serviço …", com a maiúscula',
      t like 'Olá, Otávio! Aqui é %. O serviço no seu veleiro precisou passar para a semana de 30/11.%', t);
    -- a varredura reprova o plantado (R8.12-4)
    r := pg_temp.ok(r, 'M5f a varredura reprova o texto plantado (vazio, com valor, com o número da OS)',
      not pg_temp.limpo('', '401') and not pg_temp.limpo('Otávio, o serviço precisou passar para a semana de 30/11. Valor R$ 900,00.', '401')
      and not pg_temp.limpo('Otávio, a OS-K1 precisou passar para a semana de 30/11.', '401'), null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── S. A saúde da comunicação: a equipe e o cliente ─────────────────────────────────────────────────
do $c$
declare
  r     jsonb := '[]';
  z0    jsonb;
  z     jsonb;
  n0    jsonb;
  n1    jsonb;
  k     text;
  c_zeros constant text[] := array['equipe_fora_da_janela', 'equipe_acima_do_teto', 'ficha_sem_sim', 'mudanca_19h_repetida', 'dia_exato_cedo',
                                   'promessa_mudou_sem_dono', 'semana_como_dia_ouvido'];
begin
  if not pg_temp.na_bancada9() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'S a saúde', true, 'PULADO: rode pela bancada'));
    return;
  end if;
  begin
    perform pg_temp.prepara('sombra', true, false);
    update public.agenda_config set modo_equipe_previsto = 'sombra', modo_equipe_convite = 'sombra' where id;
    z0 := pg_temp.saude();
    r := pg_temp.ok(r, 'S1 os 7 zeros novos existem e valem 0 na fixture (a equipe e o cliente da 7f, sem nada ligado), e zeros_ok',
      (select count(*) from unnest(c_zeros) x where z0 ->> x = '0') = 7 and (z0 ->> 'zeros_ok')::boolean, (select jsonb_object_agg(x, z0 -> x) from unnest(c_zeros) x)::text);
    -- cada zero com um caso plantado (cada um numa subtransação): vale 1 e derruba o zeros_ok
    for k in select unnest(c_zeros) loop
      begin
        case k
          when 'equipe_fora_da_janela' then
            perform pg_temp.equipe_msg('Tec401', date '2026-11-16', 'previsto', pg_temp.em(date '2026-11-15', '10:00'));   -- domingo
          when 'equipe_acima_do_teto' then
            perform pg_temp.equipe_msg('Tec401', date '2026-11-13', 'ficha', pg_temp.em(date '2026-11-12', '19:30'));
            perform pg_temp.equipe_msg('Tec401', date '2026-11-12', 'como_foi', pg_temp.em(date '2026-11-12', '17:00'));
            perform pg_temp.equipe_msg('Tec401', date '2026-11-16', 'previsto', pg_temp.em(date '2026-11-12', '19:31'));
          when 'ficha_sem_sim' then
            perform pg_temp.equipe_msg('Tec402', date '2026-11-13', 'convite', pg_temp.em(date '2026-11-11', '10:00'));
            perform pg_temp.equipe_msg('Tec402', date '2026-11-13', 'ficha', pg_temp.em(date '2026-11-12', '19:30'));
          when 'mudanca_19h_repetida' then
            perform pg_temp.equipe_msg('Tec403', date '2026-11-16', 'mudanca', pg_temp.em(date '2026-11-12', '19:30'), 'enfileirada', format('agenda-equipe:mudanca:%s:2026-11-12:19h', pg_temp.p('Tec403')));
            perform pg_temp.equipe_msg('Tec403', date '2026-11-17', 'mudanca', pg_temp.em(date '2026-11-12', '19:31'), 'enfileirada', format('agenda-equipe:mudanca:%s:2026-11-12:x:19h', pg_temp.p('Tec403')));
          when 'dia_exato_cedo' then
            perform pg_temp.cliente_msg('401', 'semana', 'compra_feita', date '2026-11-23', timestamptz '2026-11-12 09:05-03', 'livre', 'faixa', date '2026-11-23', date '2026-11-27');
            perform pg_temp.cliente_msg('401', 'confirmar', 'unico', date '2026-11-23', timestamptz '2026-11-18 09:00-03', 'livre', 'firme', null, null,
                                        '{"dados": {"por_estimativa": true}}');
          when 'promessa_mudou_sem_dono' then
            perform pg_temp.cliente_msg('401', 'semana', 'mudou', date '2026-11-30', timestamptz '2026-11-17 09:00-03', 'livre', 'faixa', date '2026-11-30', date '2026-12-04');
          when 'semana_como_dia_ouvido' then
            perform pg_temp.cliente_msg('401', 'semana', 'compra_feita', date '2026-11-23', timestamptz '2026-11-12 09:05-03', 'livre', 'firme', date '2026-11-23', date '2026-11-27');
        end case;
        z := pg_temp.saude();
        r := pg_temp.ok(r, format('S2 %s com um caso plantado vale 1 e derruba o zeros_ok (e o ok de agenda_saude)', k),
          (z ->> k)::int = 1 and not (z ->> 'zeros_ok')::boolean
          and not coalesce((public.agenda_saude(date '2026-11-16', pg_temp.em(date '2026-11-16', '18:00')) ->> 'ok')::boolean, false)
          and (select count(*) from unnest(c_zeros) x where x <> k and z ->> x = '0') = 6, (select jsonb_object_agg(x, z -> x) from unnest(c_zeros) x)::text);
        perform pg_temp.desfaz();
      exception when sqlstate 'P0001' then
        if sqlerrm <> '__desfaz__' then raise; end if;
      end;
    end loop;
    -- o que NÃO conta: em teste, recusada, a ficha depois do SIM, o M1 na véspera, a semana que mudou aprovada, a semana em faixa
    begin
      perform pg_temp.equipe_msg('Tec401', date '2026-11-16', 'previsto', pg_temp.em(date '2026-11-15', '10:00'), 'registrada', null, null, null, 'sombra');
      perform pg_temp.equipe_msg('Tec404', date '2026-11-16', 'previsto', pg_temp.em(date '2026-11-15', '10:00'), 'recusada');
      perform pg_temp.equipe_msg('Tec402', date '2026-11-13', 'convite', pg_temp.em(date '2026-11-11', '10:00'), 'respondida', null, '{"convite": "sim"}',
                                 pg_temp.em(date '2026-11-11', '11:00'));
      perform pg_temp.equipe_msg('Tec405', date '2026-11-13', 'ficha', pg_temp.em(date '2026-11-12', '19:30'));   -- 3 mensagens de antes no mesmo dia, sem nenhuma da 7f: não conta
      perform pg_temp.equipe_msg('Tec405', date '2026-11-12', 'como_foi', pg_temp.em(date '2026-11-12', '17:00'));
      perform pg_temp.equipe_msg('Tec405', date '2026-11-12', 'confirmar', pg_temp.em(date '2026-11-12', '07:45'));
      perform pg_temp.equipe_msg('Tec402', date '2026-11-13', 'ficha', pg_temp.em(date '2026-11-12', '19:30'));
      perform pg_temp.cliente_msg('401', 'semana', 'compra_feita', date '2026-11-23', timestamptz '2026-11-12 09:05-03', 'livre', 'faixa', date '2026-11-23', date '2026-11-27');
      perform pg_temp.cliente_msg('401', 'confirmar', 'unico', date '2026-11-23', timestamptz '2026-11-21 09:00-03', 'livre', 'firme', null, null, '{"dados": {"por_estimativa": true}}');
      perform pg_temp.cliente_msg('401', 'semana', 'mudou', date '2026-11-30', timestamptz '2026-11-24 09:00-03', 'aprovada', 'faixa', date '2026-11-30', date '2026-12-04');
      z := pg_temp.saude();
      r := pg_temp.ok(r, 'S3 não contam: a mensagem em teste, a recusada, o dia cheio sem mensagem da 7f, a ficha depois do SIM, o M1 na véspera (sáb 21/11 para seg 23/11), a semana que mudou aprovada, a semana em faixa',
        (select count(*) from unnest(c_zeros) x where z ->> x = '0') = 7 and (z ->> 'zeros_ok')::boolean, (select jsonb_object_agg(x, z -> x) from unnest(c_zeros) x)::text);
      perform pg_temp.desfaz();
    exception when sqlstate 'P0001' then
      if sqlerrm <> '__desfaz__' then raise; end if;
    end;
    -- os números contra uma contagem independente: o que se plantou (a verdade conhecida) é o que os números somam, antes × depois
    begin
      n0 := pg_temp.saude() -> 'numeros';
      perform pg_temp.equipe_msg('Tec401', date '2026-11-16', 'previsto', pg_temp.em(date '2026-11-12', '19:30'));
      perform pg_temp.equipe_msg('Tec402', date '2026-11-16', 'previsto', pg_temp.em(date '2026-11-12', '19:30'), 'respondida');
      perform pg_temp.equipe_msg('Tec403', date '2026-11-13', 'convite', pg_temp.em(date '2026-11-11', '10:00'), 'respondida', null, '{"convite": "sim"}', pg_temp.em(date '2026-11-11', '11:00'));
      perform pg_temp.equipe_msg('Tec404', date '2026-11-13', 'convite', pg_temp.em(date '2026-11-11', '10:00'), 'respondida', null, '{"tipo": "nao_vou", "convite": "nao"}', pg_temp.em(date '2026-11-11', '11:00'));
      perform pg_temp.equipe_msg('Tec405', date '2026-11-13', 'convite', pg_temp.em(date '2026-11-11', '10:00'), 'sem_resposta');
      perform pg_temp.equipe_msg('Tec401', date '2026-11-13', 'convite', pg_temp.em(date '2026-11-11', '10:00'), 'respondida', null, '{"tipo": "nao_vou", "convite": "nao"}', pg_temp.em(date '2026-11-11', '11:30'));
      perform pg_temp.equipe_msg('Tec406', date '2026-11-17', 'mudanca', pg_temp.em(date '2026-11-12', '19:30'), 'enfileirada', format('agenda-equipe:mudanca:%s:2026-11-12:19h', pg_temp.p('Tec406')));
      perform pg_temp.equipe_msg('Tec407', date '2026-11-16', 'previsto', pg_temp.em(date '2026-11-12', '19:30'), 'registrada', null, null, null, 'sombra');
      perform pg_temp.equipe_msg('Tec306', date '2026-11-16', 'previsto', pg_temp.em(date '2026-11-12', '19:30'), 'recusada');
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_em)
      values (pg_temp.p('Tec404'), daterange(date '2026-11-13', date '2026-11-13', '[]'), 'indisponivel', 'diarista', 'não vou (teste)', pg_temp.em(date '2026-11-11', '11:05'));
      perform pg_temp.cliente_msg('401', 'semana', 'compra_feita', date '2026-11-23', timestamptz '2026-11-12 09:05-03', 'livre', 'faixa', date '2026-11-23', date '2026-11-27');
      perform pg_temp.cliente_msg('402', 'semana', 'compra_pendente', date '2026-11-23', null, 'segurada', 'condicional', date '2026-11-23', date '2026-11-27');
      perform pg_temp.cliente_msg('403', 'semana', 'compra_feita', date '2026-11-23', null, 'livre', 'faixa', date '2026-11-23', date '2026-11-27', '{}', 'sombra');
      perform pg_temp.cliente_msg('405', 'semana', 'mudou', date '2026-11-30', timestamptz '2026-11-16 09:00-03', 'aprovada', 'faixa', date '2026-11-30', date '2026-12-04');
      perform pg_temp.cliente_msg('406', 'pode_atrasar', 'remarcado', date '2026-11-30', timestamptz '2026-11-16 09:00-03', 'aprovada', 'firme');
      n1 := pg_temp.saude() -> 'numeros';
      r := pg_temp.ok(r, 'S4 numeros.equipe soma o plantado: previstos +2, mudanças +1 (das 19:30 +1), convites +4 (SIM +1, NÃO +2, sem resposta +1), recusadas +1, em teste +1, "não vou" depois do convite +1',
        (select jsonb_object_agg(k2, (n1 #>> array['equipe', k2])::int - coalesce((n0 #>> array['equipe', k2])::int, 0)) from jsonb_object_keys(n1 -> 'equipe') k2)
        = '{"previstos": 2, "mudancas": 1, "mudancas_19h": 1, "convites": 4, "convites_sim": 1, "convites_nao": 2, "convites_sem_resposta": 1, "recusadas": 1, "em_teste": 1, "nao_depois_de_mudanca": 1}'::jsonb,
        (n0 ->> 'equipe') || ' → ' || (n1 ->> 'equipe'));
      r := pg_temp.ok(r, 'S5 numeros.cliente soma o plantado: semanas registradas +2, enviadas +1, seguradas +1, em teste +1; a semana que mudou registrada, mandada e enviada +1; mudanças ao cliente +2',
        (n1 #>> '{cliente,semanas,registradas}')::int - (n0 #>> '{cliente,semanas,registradas}')::int = 2
        and (n1 #>> '{cliente,semanas,enviadas}')::int - (n0 #>> '{cliente,semanas,enviadas}')::int = 1
        and (n1 #>> '{cliente,semanas,seguradas}')::int - (n0 #>> '{cliente,semanas,seguradas}')::int = 1
        and (n1 #>> '{cliente,semanas,vencidas}')::int - (n0 #>> '{cliente,semanas,vencidas}')::int = 0
        and (n1 #>> '{cliente,semanas,em_teste}')::int - (n0 #>> '{cliente,semanas,em_teste}')::int = 1
        and (n1 #>> '{cliente,semana_mudou,registradas}')::int - (n0 #>> '{cliente,semana_mudou,registradas}')::int = 1
        and (n1 #>> '{cliente,semana_mudou,mandadas}')::int - (n0 #>> '{cliente,semana_mudou,mandadas}')::int = 1
        and (n1 #>> '{cliente,semana_mudou,enviadas}')::int - (n0 #>> '{cliente,semana_mudou,enviadas}')::int = 1
        and (n1 #>> '{cliente,mudancas_ao_cliente}')::int - (n0 #>> '{cliente,mudancas_ao_cliente}')::int = 2,
        (n0 ->> 'cliente') || ' → ' || (n1 ->> 'cliente'));
      -- e por um caminho que não é o da função: as chaves (dedupe_key), contadas uma a uma
      r := pg_temp.ok(r, 'S5b a contagem independente pelas chaves: os previstos ligados não recusados da semana = numeros.equipe.previstos',
        (n1 #>> '{equipe,previstos}')::int = (select count(*) from public.agenda_equipe_mensagens e
                                               where split_part(e.dedupe_key, ':', 2) = 'previsto' and right(e.dedupe_key, 7) <> ':sombra' and e.estado <> 'recusada'
                                                 and e.criada_em > pg_temp.em(date '2026-11-16', '18:00') - interval '7 days'), n1 ->> 'equipe');
      perform pg_temp.desfaz();
    exception when sqlstate 'P0001' then
      if sqlerrm <> '__desfaz__' then raise; end if;
    end;
    -- os números só com o modo deles fora de desligado (como os outros números)
    update public.agenda_config set modo_equipe_previsto = 'desligado', modo_equipe_convite = 'desligado' where id;
    z := pg_temp.saude() -> 'numeros';
    r := pg_temp.ok(r, 'S6 o previsto e o convite desligados: sem numeros.equipe; as camadas em teste: com numeros.cliente', not (z ? 'equipe') and z ? 'cliente', z::text);
    update public.agenda_config set modo_cliente_camadas = 'desligado', modo_equipe_convite = 'sombra' where id;
    z := pg_temp.saude() -> 'numeros';
    r := pg_temp.ok(r, 'S6b as camadas desligadas: sem numeros.cliente; o convite em teste: com numeros.equipe', z ? 'equipe' and not (z ? 'cliente'), z::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── D. O dado (20261109101900), numa subtransação desfeita ──────────────────────────────────────────
do $c$
declare
  r      jsonb := '[]';
  v_mig  text := replace(coalesce(current_setting('agenda_teste.mig_sombra_final_fase7f', true), ''), E'\r\n', E'\n');
  v_desf text;
  v_l    jsonb;
  v_l2   jsonb;
  v_resto jsonb;
  v_err  text;
  v_ret  record;
begin
  if v_mig = '' or not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'D o dado', true, 'PULADO: sem agenda_teste.mig_sombra_final_fase7f (rode pela bancada)'));
    return;
  end if;
  v_desf := (select string_agg(substr(l, 6), E'\n' order by o)
               from (select l, o, sum(case when l like '-- DESFAZER-INICIO%' then 1 when l like '-- DESFAZER-FIM%' then -1 else 0 end) over (order by o) as dentro
                       from unnest(string_to_array(v_mig, E'\n')) with ordinality u(l, o)) x
              where dentro = 1 and l not like '-- DESFAZER-INICIO%');
  begin
    execute current_setting('agenda_teste.fase7f');
    update public.agenda_config set modo_bloco_agenda = 'sombra', modo_veto = 'sombra', modo_lote_dono = 'sombra', modo_equipe_previsto = 'desligado',
           modo_equipe_convite = 'desligado', modo_cliente_camadas = 'desligado', gestor_so_propor = true, cliente_tipos_ligados = array_remove(cliente_tipos_ligados, 'semana'),
           atualizado_em = timestamptz '2026-11-01 12:00-03', atualizado_por = (select id from public.app_users order by id limit 1)
     where id;
    v_resto := (select to_jsonb(c) - 'modo_equipe_previsto' - 'modo_equipe_convite' - 'modo_cliente_camadas' - 'atualizado_em' - 'atualizado_por' from public.agenda_config c where c.id);
    execute v_mig;
    v_l := (select to_jsonb(c) from public.agenda_config c where c.id);
    r := pg_temp.ok(r, 'D1 os 3 da equipe e do cliente de desligado para sombra (previsto, convite, camadas)',
      v_l ->> 'modo_equipe_previsto' = 'sombra' and v_l ->> 'modo_equipe_convite' = 'sombra' and v_l ->> 'modo_cliente_camadas' = 'sombra', v_l::text);
    r := pg_temp.ok(r, 'D2 o resto da linha não muda (bloco, prazo e lote em sombra, o freio, a lista sem semana, os modos de antes); atualizado_por nulo e a hora nova',
      (v_l - 'modo_equipe_previsto' - 'modo_equipe_convite' - 'modo_cliente_camadas' - 'atualizado_em' - 'atualizado_por') = v_resto and v_l ->> 'atualizado_por' is null
      and (v_l ->> 'atualizado_em')::timestamptz <> timestamptz '2026-11-01 12:00-03' and not (v_l -> 'cliente_tipos_ligados') ? 'semana' and (v_l ->> 'gestor_so_propor')::boolean, null);
    execute v_mig;
    v_l2 := (select to_jsonb(c) from public.agenda_config c where c.id);
    r := pg_temp.ok(r, 'D3 idempotente: a 2ª vez não muda nada (nem a hora)', v_l2 = v_l, null);
    -- a trava: um ligado
    update public.agenda_config set modo_equipe_convite = 'ligado', modo_equipe_previsto = 'desligado' where id;
    v_l := (select to_jsonb(c) from public.agenda_config c where c.id);
    begin
      execute v_mig;
      v_err := 'passou';
    exception when others then
      v_err := sqlstate || ': ' || sqlerrm;
    end;
    r := pg_temp.ok(r, 'D4 a trava: com um dos 3 ligado, recusa (P0001) e nada muda (nem o desligado vai a sombra)',
      v_err like 'P0001: O dado 20261109101900 põe em teste e não rebaixa um ligado%' and (select to_jsonb(c) from public.agenda_config c where c.id) = v_l, v_err);
    update public.agenda_config set modo_equipe_convite = 'desligado' where id;
    -- a trava: sem as funções do P9
    begin
      drop function public._agenda_cliente_semana_mudou(uuid, jsonb, date, timestamptz, timestamptz, timestamptz);
      begin
        execute v_mig;
        v_err := 'passou';
      exception when others then
        v_err := sqlstate || ': ' || sqlerrm;
      end;
      raise exception using errcode = 'P0002', message = v_err;
    exception when sqlstate 'P0002' then
      v_err := sqlerrm;
    end;
    r := pg_temp.ok(r, 'D5 a trava: sem a função do P9 (a estrutura antes do dado), recusa e diz qual falta',
      v_err like 'P0001: O dado 20261109101900 vem depois de 20261109101000, 101100 e 101200: faltam public._agenda_cliente_semana_mudou%'
      and to_regprocedure('public._agenda_cliente_semana_mudou(uuid, jsonb, date, timestamptz, timestamptz, timestamptz)') is not null, v_err);
    -- o DESFAZER: volta os 3 a desligado, diz quem fica ligado, não mexe no resto
    execute v_mig;
    update public.agenda_config set modo_equipe_convite = 'ligado' where id;
    v_resto := (select to_jsonb(c) - 'modo_equipe_previsto' - 'modo_equipe_convite' - 'modo_cliente_camadas' - 'atualizado_em' - 'atualizado_por' from public.agenda_config c where c.id);
    execute v_desf into v_ret;
    v_l := (select to_jsonb(c) from public.agenda_config c where c.id);
    r := pg_temp.ok(r, 'D6 o DESFAZER do cabeçalho: os em sombra voltam a desligado, o ligado fica e é dito (ficam_ligados), o resto da linha igual',
      v_ret.modos_desligados = 1 and v_ret.ficam_ligados = 'modo_equipe_convite' and v_l ->> 'modo_equipe_previsto' = 'desligado'
      and v_l ->> 'modo_cliente_camadas' = 'desligado' and v_l ->> 'modo_equipe_convite' = 'ligado'
      and (v_l - 'modo_equipe_previsto' - 'modo_equipe_convite' - 'modo_cliente_camadas' - 'atualizado_em' - 'atualizado_por') = v_resto,
      row_to_json(v_ret)::text);
    v_l := (select to_jsonb(c) from public.agenda_config c where c.id);
    update public.agenda_config set modo_equipe_convite = 'desligado', atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_l := (select to_jsonb(c) from public.agenda_config c where c.id);
    execute v_desf into v_ret;
    r := pg_temp.ok(r, 'D7 o DESFAZER com os 3 já desligados não muda nada (nem a hora)', v_ret.modos_desligados = 0 and (select to_jsonb(c) from public.agenda_config c where c.id) = v_l,
      row_to_json(v_ret)::text);
    r := pg_temp.ok(r, 'D8 o arquivo do dado: só UPDATE de agenda_config (e o SELECT do fim e a trava); nenhum INSERT, DELETE, cliente_tipos_ligados ou gestor_so_propor escrito',
      pg_temp.codigo(v_mig) !~* '\m(insert|delete|truncate)\M' and (select count(*) from regexp_matches(pg_temp.codigo(v_mig), '^update public\.', 'gn')) = 1
      and pg_temp.codigo(v_mig) !~ 'cliente_tipos_ligados\s*=' and pg_temp.codigo(v_mig) !~ 'gestor_so_propor\s*=', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$c$;

-- ── K9. As cópias ───────────────────────────────────────────────────────────────────────────────────
do $c$
declare
  r     jsonb := '[]';
  v_mig text := coalesce(current_setting('agenda_teste.mig_mudou_fase7f', true), '');
  x     record;
  v_a   text;
  v_n   int;
begin
  if v_mig = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'K9 as cópias', true, 'PULADO: sem agenda_teste.mig_mudou_fase7f (rode pela bancada)'));
    return;
  end if;
  for x in select * from (values
      ('_agenda_cliente_texto', 'public._agenda_cliente_texto(text, text, uuid, jsonb, date)', 'mig_cliente_fase7f', 1),
      ('_agenda_cliente_registrar', 'public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamp with time zone, timestamp with time zone, text, text, timestamp with time zone, uuid)', 'mig_cliente_fase7f', 1),
      ('_agenda_cliente_revalidar', 'public._agenda_cliente_revalidar(uuid, timestamp with time zone)', 'mig_cliente_fase7f', 1),
      ('_agenda_cliente_atraso', 'public._agenda_cliente_atraso(date, timestamp with time zone)', 'mig_correcao_rodada_fase5', 4),
      ('_agenda_saude_comunicacao', 'public._agenda_saude_comunicacao(date, timestamp with time zone)', 'mig_leituras_fase7f', 2)) t(nome, sig, fonte, blocos)
  loop
    select count(*) into v_n from regexp_matches(replace(pg_temp.corpo(v_mig, x.nome), E'\r\n', E'\n'), '-- (FASE 7f: \(7f P9|\(7f P9)', 'g');
    r := pg_temp.ok(r, format('K9a %s: a viva é a desta migration; sem os %s blocos do P9, é o corpo da origem (agenda_teste.%s), byte a byte', x.nome, x.blocos, x.fonte),
      coalesce(current_setting('agenda_teste.' || x.fonte, true), '') <> ''
      and replace((select p.prosrc from pg_proc p where p.oid = x.sig::regprocedure), E'\r\n', E'\n') = pg_temp.corpo(v_mig, x.nome)
      and v_n = x.blocos
      and pg_temp.sem_p9(pg_temp.corpo(v_mig, x.nome)) = replace(pg_temp.corpo(current_setting('agenda_teste.' || x.fonte, true), x.nome), E'\r\n', E'\n')
      and pg_temp.corpo(current_setting('agenda_teste.' || x.fonte, true), x.nome) <> '',
      format('blocos %s; origem %s letras; viva sem os blocos %s letras', v_n, length(pg_temp.corpo(current_setting('agenda_teste.' || x.fonte, true), x.nome)),
             length(pg_temp.sem_p9(pg_temp.corpo(v_mig, x.nome)))));
  end loop;
  select string_agg(distinct m[1], ',' order by m[1]) into v_a
    from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
  r := pg_temp.ok(r, 'K9b a migration cria a nova e recria só as 5 que diz (o risco, o "ouviu", o prometer, a semana do P6 e agenda_saude ficam)',
    v_a = '_agenda_cliente_atraso,_agenda_cliente_registrar,_agenda_cliente_revalidar,_agenda_cliente_semana_mudou,_agenda_cliente_texto,_agenda_saude_comunicacao', v_a);
  r := pg_temp.ok(r, 'K9c nada de dado nem de estrutura fora das funções: sem update/insert/delete, sem alter table, sem cliente_tipos_ligados escrito (só as portas e os comentários)',
    regexp_replace(pg_temp.codigo(v_mig), '\$function\$.*?\$function\$', '', 'g') !~* '\m(alter table|insert into|update public\.|delete from)\M'
    and regexp_replace(pg_temp.codigo(v_mig), '\$function\$.*?\$function\$', '', 'g') ~ 'revoke all on function'
    and pg_temp.codigo(v_mig) !~ 'cliente_tipos_ligados\s*=', null);
  perform pg_temp.gravar(r);
end
$c$;

select teste, ok, detalhe from _resultado order by ok, teste;
rollback;
