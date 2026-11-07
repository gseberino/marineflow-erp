-- Prova da mensagem M11 "onde fica" da Agenda de Produção, Fase 7d (pacote P6; migration 20261107100500; spec-fase7d §5.6, §6.1, §6.3, §8.3
-- agenda_fase7d_cliente.sql, R2, R6.0, R6.3-4, R6.3-5, R6.7a, R6.7b, R6.8-7, R6.9-5).
-- bancada: depende de 20261107100500
--
--   K0  as portas: as 5 novas e as recriadas
--   K1  o M11 byte a byte (barco, 1ª e seguinte, com uso e prazo; motorhome; bem feminino) e o teto de 400 (R6.9-5): o maior {servico} da fixture e o maior real
--   K2  quem recebe: onde_fica_desde (R6.7a-1), a guarda, sinal por sinal (R6.7a-2), as portas de tempo, o que já foi dito, o freio (R6.7b), o M11 cede o dia ao M1
--   K3  fora da lista = em teste; ligado + 3 dias = espera o dono; liberado = a fila; nada sai com a lista de produção
--   K4  a resposta: site_access + a pergunta local com a leitura; sem leitura; áudio ao dono; não conta como acesso (R6.3-5); bem_livre resolvida; em teste
--   K5  o decidir local: a 1 grava, com *desfaz*, sem mexer no plano; a 2 só responde; a conversa (agenda_decisoes_abertas)
--   K6  a revalidação (R6.7a-3): a OS é relida na hora de sair, sinal por sinal; o que já foi dito = desatualizada
--   K7  as cópias: as recriadas só mudam nos blocos "-- FASE 7d:", vivas e na migration
--   K8  o bloqueio do retorno (R6.0): a migration 20261105100000 DE VERDADE por baixo do M11, com o contraste sem o gatilho
--   K9  o peso (R6.8-7): sem candidato, nenhuma das 4 leituras; o contraste com um candidato
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7d_cliente.sql
--   Seguro em produção: termina em ROLLBACK. As portas rodam em qualquer banco; o resto usa as fixtures e só roda na bancada (fora dela sai PULADO).
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
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim".
create function pg_temp.sem_7d(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro boolean := false;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- FASE 7[df]:' and l !~ '^\s*-- FASE 7[df]: fim' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro and l ~ '^\s*-- FASE 7[df]: fim' then
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

-- ── K0. As portas (sem fixture) ───────────────────────────────────────────────────────────────────
with f(sig, definer, vol) as (values
  ('public._agenda_cliente_ja_atendida(uuid)', false, 's'),
  ('public._agenda_cliente_onde_falta(uuid, date)', false, 's'),
  ('public._agenda_cliente_onde_fica(date, timestamp with time zone)', true, 'v'),
  ('public._agenda_local_proposto(uuid, text, date)', false, 's'),
  ('public._agenda_cliente_anotar_onde(uuid, uuid, text, date, timestamp with time zone)', false, 'v'))
insert into _resultado
select 'K0a as 5 novas: a volatilidade, definer só no passo, search_path fixo, e ninguém de fora (nem o service_role)',
       count(p.oid) = 5
       and bool_and(p.prosecdef = f.definer and p.provolatile = f.vol
                    and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                    and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
                    and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                    and not has_function_privilege('service_role', p.oid, 'execute')),
       string_agg(f.sig, '; ') filter (where p.oid is null or p.prosecdef <> f.definer or p.provolatile <> f.vol
                                             or coalesce(array_to_string(p.proconfig, ','), '') <> 'search_path=public'
                                             or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                             or has_function_privilege('service_role', p.oid, 'execute'))
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

insert into _resultado
select 'K0b rodando: o anon, o técnico e o service_role não alcançam o passo nem a resposta anotada (42501)',
       pg_temp.como('anon', $q$select public._agenda_cliente_onde_fica(date '2027-07-16', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('authenticated', $q$select public._agenda_cliente_onde_fica(date '2027-07-16', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('service_role', $q$select public._agenda_cliente_onde_fica(date '2027-07-16', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('service_role', $q$select public._agenda_cliente_anotar_onde(gen_random_uuid(), gen_random_uuid(), 'x', date '2027-07-16', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('anon', $q$select public._agenda_local_proposto(gen_random_uuid(), 'x', date '2027-07-16')::text$q$) like 'erro 42501%',
       null;

insert into _resultado
select 'K0c as recriadas seguem com as portas: a rodada e a resposta só do service_role, a revalidação de ninguém, o texto também não',
       has_function_privilege('service_role', 'public.agenda_cliente_vigiar(date, timestamp with time zone)', 'execute')
       and not has_function_privilege('authenticated', 'public.agenda_cliente_vigiar(date, timestamp with time zone)', 'execute')
       and not has_function_privilege('anon', 'public.agenda_cliente_vigiar(date, timestamp with time zone)', 'execute')
       and has_function_privilege('service_role', 'public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamp with time zone)', 'execute')
       and not has_function_privilege('anon', 'public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamp with time zone)', 'execute')
       and not has_function_privilege('anon', 'public._agenda_cliente_revalidar(uuid, timestamp with time zone)', 'execute')
       and not has_function_privilege('service_role', 'public._agenda_cliente_revalidar(uuid, timestamp with time zone)', 'execute'),
       null;

-- ── As fixtures ───────────────────────────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7d', true), '') = '' or coalesce(current_setting('agenda_teste.fase7c', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7b', true), '') = '' then
    return;
  end if;
  execute current_setting('agenda_teste.fase7d');
  -- a mensagem ao cliente precisa da empresa e do dono da fixture da Fase 5
  insert into public.app_settings (key, value) values ('company_name', 'HBR Marine Solutions') on conflict (key) do nothing;
end
$carga$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-J1')
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
create function pg_temp.cli(p_os text) returns uuid language sql stable as $f$
  select so.client_id from public.service_orders so where so.service_order_number = p_os
$f$;
create function pg_temp.fone(p_os text) returns text language sql stable as $f$
  select c.phone from public.service_orders so join public.clients c on c.id = so.client_id where so.service_order_number = p_os
$f$;
-- O M11 pronto para rodar: modo_cliente ligado, sem a aprovação dos 3 dias, sem a regra da conversa, sem o freio. p_ligado = onde_fica na lista (nunca é o de produção:
-- em produção a lista tem os 11; o K3 prova isso).
create function pg_temp.prepara(p_desde date, p_ligado boolean default true) returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = 0, cliente_conversa_dias = 0, gestor_so_propor = false, gestor_so_propor_em = null,
         onde_fica_desde = p_desde,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data', 'pronto',
                                       'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
                                 || case when p_ligado then array['onde_fica'] else '{}'::text[] end
   where id
$f$;
create function pg_temp.passo(p_hoje date default date '2027-07-16', p_hora text default '16:20') returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  return public._agenda_cliente_onde_fica(p_hoje, pg_temp.em(p_hoje, p_hora));
end $f$;
-- As OS que têm o M11, pelo número, na ordem
create function pg_temp.quem() returns text language sql stable as $f$
  select coalesce(string_agg(so.service_order_number, ',' order by so.service_order_number collate "C"), '')
    from public.agenda_cliente_mensagens m join public.service_orders so on so.id = m.service_order_id
   where m.tipo = 'onde_fica'
$f$;
create function pg_temp.m(p_os text) returns public.agenda_cliente_mensagens language sql stable as $f$
  select m from public.agenda_cliente_mensagens m where m.service_order_id = pg_temp.os(p_os) and m.tipo = 'onde_fica' order by m.criada_em desc limit 1
$f$;
create function pg_temp.fila(p_msg uuid) returns public.whatsapp_send_queue language sql stable as $f$
  select q from public.whatsapp_send_queue q where q.source_ref_id = p_msg
$f$;
-- A linha da fila saiu (o que o worker faz): o gatilho do envio deixa a mensagem enviada
create function pg_temp.saiu(p_msg uuid, p_quando timestamptz) returns void language sql as $f$
  update public.whatsapp_send_queue set status = 'sent', sent_at = p_quando where source_ref_id = p_msg
$f$;
create function pg_temp.resp(p_os text, p_body text, p_int text, p_agora timestamptz, p_tipo text default 'text') returns jsonb language sql as $f$
  select public.agenda_resposta_do_cliente(pg_temp.fone(p_os), p_body, gen_random_uuid(), p_tipo, p_int, null, p_agora)
$f$;
-- O M11 de p_os registrado, enfileirado e saído às 16:20 de sex 16/07
create function pg_temp.mandado(p_os text) returns public.agenda_cliente_mensagens language plpgsql as $f$
declare
  v_m public.agenda_cliente_mensagens;
begin
  perform pg_temp.passo();
  v_m := pg_temp.m(p_os);
  perform pg_temp.saiu(v_m.id, v_m.enviar_em + interval '1 minute');
  return pg_temp.m(p_os);
end $f$;
-- A publicada não muda de dia: cancela e cria outra, com as mesmas pessoas e turnos
create function pg_temp.mover(p_os text, p_dia date) returns void language plpgsql as $f$
declare
  v_ids uuid[];
begin
  select array_agg(a.id) into v_ids from public.agenda_alocacoes a where a.service_order_id = pg_temp.os(p_os) and a.estado in ('publicada', 'fixada');
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = any (v_ids);
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  select a.service_order_id, a.payee_id, p_dia, a.turno, a.presenca, a.tipo, 'publicada', a.origem, a.publicada_em
    from public.agenda_alocacoes a where a.id = any (v_ids);
end $f$;
-- A fixture sem o que atrapalha: as portas de J11 e J12, as únicas abertas em 16/07 com onde_fica_desde em junho. O M11 do J2 pede a situação limpa e a aprovação de ontem.
create function pg_temp.j2_sem_situacao() returns void language sql as $f$
  update public.os_planejamento set bem_situacao = null, bem_situacao_fonte = null, bem_situacao_em = null, descer_quem = null
   where service_order_id = pg_temp.os('OS-J2');
  update public.service_orders set converted_to_os_at = timestamptz '2027-07-15 10:00-03' where id = pg_temp.os('OS-J2');
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where service_order_id = pg_temp.os('OS-J2');
$f$;

-- ── K1. O M11 byte a byte e o teto ────────────────────────────────────────────────────────────────
do $k1$
declare
  v_res  jsonb := '[]'::jsonb;
  v_h    date := date '2027-07-16';
  v_t    text;
  v_exp  text;
  m      public.agenda_cliente_mensagens;
  r      jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K1 o M11 byte a byte', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_t := public._agenda_cliente_texto('onde_fica', 'barco', pg_temp.os('OS-J2'), '{"primeira":true,"uso":true,"prazo":true}', v_h);
  v_exp := 'Olá, Nelson! Aqui é o Gustavo, da HBR Marine Solutions. Para eu deixar o serviço no seu veleiro encaminhado: o seu veleiro está em qual marina, e fica na água ou em seco? Quando precisa descer ou subir, quem faz: você, o marinheiro ou a marina? Se for usar o seu veleiro nas próximas semanas, me diga os dias, que eu marco o serviço fora deles. Precisa do serviço pronto até alguma data? Pode responder por aqui mesmo, até por áudio.';
  v_res := pg_temp.ok(v_res, 'K1a o barco, 1ª mensagem, com uso e prazo: o exemplo da §6.1, byte a byte, 433 letras', v_t = v_exp and char_length(v_t) = 433, v_t);
  v_t := public._agenda_cliente_texto('onde_fica', 'motorhome', pg_temp.os('OS-J1'), '{"primeira":false,"uso":true}', v_h);
  v_exp := 'Lenine, para eu deixar o serviço no seu motorhome encaminhado: o seu motorhome vem para o nosso pátio, ou o serviço é onde ele está? Em que dia ele pode vir? Se for viajar com ele nas próximas semanas, me diga quando, que eu marco o serviço fora desses dias. Pode responder por aqui mesmo, até por áudio.';
  v_res := pg_temp.ok(v_res, 'K1b o motorhome, mensagem seguinte: o exemplo da §6.1, byte a byte', v_t = v_exp, v_t);
  v_t := public._agenda_cliente_texto('onde_fica', 'barco', pg_temp.os('OS-J12'), '{"primeira":false}', v_h);
  v_res := pg_temp.ok(v_res, 'K1c o barco sem as partes opcionais',
    v_t = 'Beto, para eu deixar o serviço na sua lancha encaminhado: a sua lancha está em qual marina, e fica na água ou em seco? Quando precisa descer ou subir, quem faz: você, o marinheiro ou a marina? Pode responder por aqui mesmo, até por áudio.', v_t);
  v_t := public._agenda_cliente_texto('onde_fica', 'barco', pg_temp.os('OS-J12'), '{"primeira":false,"uso":true}', v_h);
  v_res := pg_temp.ok(v_res, 'K1d o {uso} do barco, bem feminino', v_t like '%a marina? Se for usar a sua lancha nas próximas semanas, me diga os dias, que eu marco o serviço fora deles. Pode responder%', v_t);
  v_t := public._agenda_cliente_texto('onde_fica', 'barco', pg_temp.os('OS-J12'), '{"primeira":false,"prazo":true}', v_h);
  v_res := pg_temp.ok(v_res, 'K1e o {prazo} sozinho', v_t like '%a marina? Precisa do serviço pronto até alguma data? Pode responder%', v_t);
  begin
    update public.vessels set name = 'Van', asset_type = 'Van' where id = (select vessel_id from public.service_orders where id = pg_temp.os('OS-J1'));
    v_t := public._agenda_cliente_texto('onde_fica', 'motorhome', pg_temp.os('OS-J1'), '{"primeira":false,"uso":true}', v_h);
    v_res := pg_temp.ok(v_res, 'K1f o rv feminino: "ela" nas 3 partes',
      v_t = 'Lenine, para eu deixar o serviço na sua van encaminhado: a sua van vem para o nosso pátio, ou o serviço é onde ela está? Em que dia ela pode vir? Se for viajar com ela nas próximas semanas, me diga quando, que eu marco o serviço fora desses dias. Pode responder por aqui mesmo, até por áudio.', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K1g os textos passam pelo proibido, salvo o tamanho do exemplo de 433',
    public._agenda_cliente_texto_proibido(public._agenda_cliente_texto('onde_fica', 'barco', pg_temp.os('OS-J2'), '{"primeira":false,"uso":true}', v_h)) is null
    and public._agenda_cliente_texto_proibido(public._agenda_cliente_texto('onde_fica', 'barco', pg_temp.os('OS-J2'), '{"primeira":true,"uso":true,"prazo":true}', v_h)) = 'tamanho', null);
  begin
    v_t := public._agenda_cliente_texto('onde_fica', 'jetski', pg_temp.os('OS-J2'), '{}', v_h);
    v_res := pg_temp.ok(v_res, 'K1h a variante que não existe lança', false, v_t);
  exception when sqlstate '22023' then
    v_res := pg_temp.ok(v_res, 'K1h a variante que não existe lança', sqlerrm like 'Variante jetski não existe%', sqlerrm);
  end;
  begin
    v_t := public._agenda_cliente_texto('onde_fica', null, pg_temp.os('OS-J2'), '{}', v_h);
    v_res := pg_temp.ok(v_res, 'K1i sem a variante lança', false, v_t);
  exception when sqlstate '22023' then
    v_res := pg_temp.ok(v_res, 'K1i sem a variante lança', true, null);
  end;

  -- O teto (R6.9-5): o barco, na temporada, 1ª mensagem. Sem a guarda, o registrar lançaria.
  begin
    perform pg_temp.prepara(date '2026-11-01');
    r := pg_temp.passo(date '2026-11-30');
    m := pg_temp.m('OS-D2');
    v_res := pg_temp.ok(v_res, 'K1j a temporada, 1ª mensagem: acima de 400 sai sem o {prazo}, com o {uso}, sem erro',
      m.id is not null and char_length(m.texto) <= 400 and m.texto not like '%Precisa do serviço%' and m.texto like '%Se for usar a sua lancha nas próximas semanas%'
      and (m.base #>> '{dados,prazo}')::boolean = false and (m.base #>> '{dados,uso}')::boolean = true and (r ->> 'erros')::int = 0
      and m.texto = public._agenda_cliente_texto('onde_fica', 'barco', pg_temp.os('OS-D2'), (m.base -> 'dados') || '{"primeira":true}', date '2026-11-30'), r::text || ' ' || coalesce(m.texto, ''));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- A mensagem seguinte cabe com as 2 partes: o {prazo} só sai por tamanho
    perform pg_temp.prepara(date '2026-11-01');
    update public.agenda_config set cliente_dia_max = 2, cliente_semana_max = 5 where id;
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate, aprovacao, estado, dedupe_key, enviada_em, criada_em)
    values (pg_temp.cli('OS-D3'), pg_temp.os('OS-D3'), 'vespera', 'rodada', 'ligado', 'mensagem de teste', '{}', timestamptz '2026-10-01 09:00-03',
            timestamptz '2026-10-01 19:00-03', 'livre', 'enviada', 'agenda-cliente:teste:' || gen_random_uuid(), timestamptz '2026-10-01 09:00-03', timestamptz '2026-10-01 08:00-03');
    perform pg_temp.passo(date '2026-11-30');
    m := pg_temp.m('OS-D3');
    v_res := pg_temp.ok(v_res, 'K1k a mensagem seguinte, na temporada: cabe com as 2 partes', (m.base #>> '{dados,prazo}')::boolean and (m.base #>> '{dados,uso}')::boolean and not (m.base #>> '{primeira}')::boolean
      and m.texto like 'Saulo, para eu deixar %Se for usar %Precisa do serviço pronto até alguma data? Pode responder%' and char_length(m.texto) <= 400, m.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- Fora da temporada, o barco não pergunta os dias de uso; com o prazo dito, não pergunta o prazo; o motorhome pergunta a viagem sempre, e nunca o prazo
    perform pg_temp.prepara(date '2027-06-01');
    update public.os_planejamento set precisa_ate = date '2027-08-20' where service_order_id = pg_temp.os('OS-J12');
    perform pg_temp.passo();
    m := pg_temp.m('OS-J12');
    v_res := pg_temp.ok(v_res, 'K1p o barco fora da temporada e com o prazo dito: sem as 2 partes', not (m.base #>> '{dados,uso}')::boolean and not (m.base #>> '{dados,prazo}')::boolean
      and m.texto not like '%Se for usar%' and m.texto not like '%Precisa do serviço%', m.texto);
    m := pg_temp.m('OS-J11');
    v_res := pg_temp.ok(v_res, 'K1q o motorhome: a viagem sempre, o prazo nunca', (m.base #>> '{dados,uso}')::boolean and not (m.base #>> '{dados,prazo}')::boolean and m.texto like '%Se for viajar com ele%', m.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.passo();
    m := pg_temp.m('OS-J12');
    v_res := pg_temp.ok(v_res, 'K1r o barco fora da temporada, sem o prazo dito: pergunta o prazo', not (m.base #>> '{dados,uso}')::boolean and (m.base #>> '{dados,prazo}')::boolean and m.texto like '%Precisa do serviço pronto até alguma data?%', m.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- "Perguntei ao cliente os dias de uso" só com o M11 que levava o {uso}: dizer que perguntou sem ter perguntado seria plano falso
  begin
    perform pg_temp.prepara(date '2026-11-01');
    perform pg_temp.passo(date '2026-11-30');
    m := pg_temp.m('OS-D2');
    perform pg_temp.saiu(m.id, m.enviar_em + interval '1 minute');
    v_res := pg_temp.ok(v_res, 'K1s o M11 saiu com o {uso}: "perguntei"', (m.base #>> '{dados,uso}')::boolean
      and (public._agenda_estado_do_bem(pg_temp.os('OS-D2'), date '2026-11-30') -> 'suposicoes')::text like '%temporada: perguntei ao cliente os dias de uso%',
      (public._agenda_estado_do_bem(pg_temp.os('OS-D2'), date '2026-11-30') -> 'suposicoes')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2026-11-01');
    update public.vessels set name = 'MH Overlander - VW Delivery' where id = (select vessel_id from public.service_orders where id = pg_temp.os('OS-D2'));
    perform pg_temp.passo(date '2026-11-30');
    m := pg_temp.m('OS-D2');
    perform pg_temp.saiu(m.id, m.enviar_em + interval '1 minute');
    v_res := pg_temp.ok(v_res, 'K1t o M11 saiu sem o {uso} (o teto): "ainda não sei", nunca "perguntei"', not (m.base #>> '{dados,uso}')::boolean and (pg_temp.m('OS-D2')).estado = 'enviada'
      and (public._agenda_estado_do_bem(pg_temp.os('OS-D2'), date '2026-11-30') -> 'suposicoes')::text like '%temporada: ainda não sei os dias de uso%',
      (public._agenda_estado_do_bem(pg_temp.os('OS-D2'), date '2026-11-30') -> 'suposicoes')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- O maior {servico} da fixture: todas as OS J e D na temporada, 1ª mensagem. Nenhuma lança, nenhuma passa de 400
  begin
    perform pg_temp.prepara(date '2027-01-01', false);
    update public.agenda_config set temporada_meses = '{7}' where id;
    update public.service_orders set converted_to_os_at = timestamptz '2027-07-15 10:00-03'
     where service_order_number like 'OS-J%' or service_order_number like 'OS-D%';
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito'
     where service_order_id in (select id from public.service_orders where service_order_number like 'OS-J%' or service_order_number like 'OS-D%');
    update public.os_planejamento set bem_situacao = null, bem_situacao_fonte = null, bem_situacao_em = null
     where service_order_id in (select id from public.service_orders where service_order_number like 'OS-J%' or service_order_number like 'OS-D%');
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K1l a fixture inteira na temporada: 17 OS, nenhuma lança, nenhuma passa de 400',
      (r ->> 'registradas')::int = 17 and (r ->> 'erros')::int = 0 and r -> 'puladas' = '{}'::jsonb
      and (select max(char_length(x.texto)) from public.agenda_cliente_mensagens x where x.tipo = 'onde_fica') <= 400, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- O maior {servico} real da carteira (wf7dd_p6_servico, 05/11: "o serviço no MH Overlander - VW Delivery", 40 letras, sem servico_cliente em nenhuma OS), com o maior
  -- nome de cliente junto: nas 2 variantes, na temporada, 1ª mensagem
  begin
    perform pg_temp.prepara(date '2027-06-01', false);
    update public.agenda_config set temporada_meses = '{7}' where id;
    update public.clients set name = 'Vanderlei' where id = pg_temp.cli('OS-J12');
    update public.vessels set name = 'MH Overlander - VW Delivery' where id in (select vessel_id from public.service_orders where id in (pg_temp.os('OS-J11'), pg_temp.os('OS-J12')));
    r := pg_temp.passo();
    m := pg_temp.m('OS-J12');
    v_res := pg_temp.ok(v_res, 'K1m o maior {servico} real, no barco: sem o {prazo} ainda passa de 400, sai sem o {uso} também, e cabe',
      char_length(public._agenda_cliente_texto('onde_fica', 'barco', pg_temp.os('OS-J12'), '{"primeira":true,"uso":true,"prazo":true}', date '2027-07-16')) > 400
      and char_length(public._agenda_cliente_texto('onde_fica', 'barco', pg_temp.os('OS-J12'), '{"primeira":true,"uso":true}', date '2027-07-16')) > 400
      and m.id is not null and char_length(m.texto) <= 400 and m.texto not like '%Precisa do serviço%' and m.texto not like '%Se for usar%'
      and m.texto like 'Olá, Vanderlei! Aqui é o Gustavo, da HBR Marine Solutions. Para eu deixar o serviço no MH Overlander - VW Delivery encaminhado: o MH Overlander - VW Delivery está em qual marina,%',
      format('%s letras: %s', char_length(m.texto), m.texto));
    m := pg_temp.m('OS-J11');
    v_res := pg_temp.ok(v_res, 'K1n o maior {servico} real, no motorhome: cabe com o {uso}',
      m.id is not null and char_length(m.texto) <= 400 and m.texto like '%Se for viajar com ele nas próximas semanas%', format('%s letras: %s', char_length(m.texto), m.texto));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- Nem assim: o servico_cliente de 80 letras (o limite do CHECK) e o bem de nome longo. Pula, sem exceção e sem mensagem
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.os_planejamento set servico_cliente = 'a revisão completa do sistema elétrico, do banco de baterias e dos equipamentos' where service_order_id = pg_temp.os('OS-J12');
    update public.vessels set name = 'Embarcação de recreio de nome muito comprido que ninguém escreve inteiro nunca' where id = (select vessel_id from public.service_orders where id = pg_temp.os('OS-J12'));
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K1o ainda acima de 400 sem as 2 partes: {tamanho}, sem mensagem e sem erro',
      pg_temp.m('OS-J12') is null and (r #>> '{puladas,tamanho}')::int = 1 and (r ->> 'erros')::int = 0 and (r ->> 'registradas')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$k1$;

-- ── K2. Quem recebe ───────────────────────────────────────────────────────────────────────────────
do $k2$
declare
  v_res  jsonb := '[]'::jsonb;
  r      jsonb;
  r2     jsonb;
  m      public.agenda_cliente_mensagens;
  v_n    int;
  v_sinal record;
  v_alex uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K2 quem recebe', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  select id into v_alex from public.payees where name = 'Alex' and active;

  begin
    perform pg_temp.prepara(null);
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2a onde_fica_desde nula = ninguém, nas duas portas, com o tipo ligado', pg_temp.quem() = '' and (r ->> 'registradas')::int = 0 and r -> 'puladas' = '{}'::jsonb, r::text);
    perform pg_temp.prepara(null, false);
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2b onde_fica_desde nula = ninguém também em teste', pg_temp.quem() = '', r::text);
    perform pg_temp.prepara(date '2027-07-17');
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2c aprovada antes de onde_fica_desde: nem J11 (porta da aprovação) nem J12 (porta do 1º dia); ninguém nem é contado', pg_temp.quem() = '' and r -> 'puladas' = '{}'::jsonb, r::text);
    perform pg_temp.prepara(date '2027-07-15', false);
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2d aprovada no próprio onde_fica_desde entra; a de antes, não, também em teste', pg_temp.quem() = 'OS-J11', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  begin
    perform pg_temp.prepara(date '2027-06-01');
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2e as 2 portas: J11 pela aprovação, J12 pelo 1º dia; J13 (1º dia a 1 dia útil) e J14 (fora das 2) não',
      pg_temp.quem() = 'OS-J11,OS-J12' and (r ->> 'registradas')::int = 2 and (r #>> '{puladas,fora_da_janela}')::int >= 2, r::text);
    r2 := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2f de novo: uma por OS na vida, e a que já tem o M11 nem é olhada', (r2 ->> 'registradas')::int = 0 and not (r2 -> 'puladas' ? 'ja_existe') and not (r2 -> 'puladas' ? 'cliente_ja_tem_mensagem') and pg_temp.quem() = 'OS-J11,OS-J12', r2::text);
    v_res := pg_temp.ok(v_res, 'K2g a chave é a da vida da OS, e o modelo é o M11', (pg_temp.m('OS-J11')).dedupe_key = format('agenda-cliente:onde_fica:%s:unica', pg_temp.os('OS-J11')) and (pg_temp.m('OS-J11')).modelo = 'M11', (pg_temp.m('OS-J11')).dedupe_key);
    v_res := pg_temp.ok(v_res, 'K2h a variante vem da classe do bem; o M11 não é promessa', (pg_temp.m('OS-J11')).variante = 'motorhome' and (pg_temp.m('OS-J12')).variante = 'barco' and (pg_temp.m('OS-J11')).prometido_tipo is null, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- As portas de tempo, nos limites
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.service_orders set converted_to_os_at = timestamptz '2027-07-02 10:00-03' where id = pg_temp.os('OS-J8');
    update public.service_orders set converted_to_os_at = timestamptz '2027-07-01 10:00-03' where id = pg_temp.os('OS-J7');
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2i a porta da aprovação: há 14 dias entra (J8), há 15 não (J7)', pg_temp.quem() like '%OS-J8%' and pg_temp.quem() not like '%OS-J7%', pg_temp.quem());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    -- J13: 1º dia ter 20/07 = 2 dias úteis; J14: qua 21/07 = 3; J9: 06/08 = 21 dias corridos; J10: 09/08 = 24; J8 só com reserva em 22/07
    perform pg_temp.mover('OS-J13', date '2027-07-20');
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, reserva_de, condicao, condicao_tipo, condicao_ate)
    select pg_temp.os(t.os), v_alex, t.d, 'manha', 'turno', t.tp, 'publicada', 'motor', pg_temp.em(date '2027-07-08', '16:30'),
           case when t.tp = 'reserva' then 'condicionada' end, case when t.tp = 'reserva' then 'se o material chegar' end,
           case when t.tp = 'reserva' then 'material' end, case when t.tp = 'reserva' then date '2027-07-20' end
      from (values ('OS-J14', date '2027-07-21', 'execucao'), ('OS-J9', date '2027-08-06', 'execucao'), ('OS-J10', date '2027-08-09', 'execucao'),
                   ('OS-J8', date '2027-07-22', 'reserva')) t(os, d, tp);
    update public.os_planejamento set bem_situacao = null, bem_situacao_fonte = null, bem_situacao_em = null where service_order_id = pg_temp.os('OS-J9');
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2j a porta do 1º dia: a 2 dias úteis não (J13), a 3 sim (J14), a 21 dias sim (J9), a 24 não (J10), a reserva vale (J8)',
      pg_temp.quem() = 'OS-J11,OS-J12,OS-J14,OS-J8,OS-J9', pg_temp.quem() || ' ' || r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A guarda, sinal por sinal, em J11 (sem cada um, ela recebe: K2e)
  for v_sinal in select * from (values
      ('K2k1', 'orçamento (draft)', 'orcamento', $q$update public.service_orders set status = 'draft', quote_status = 'approved' where id = pg_temp.os('OS-J11')$q$),
      ('K2k2', 'in_progress', 'status', $q$update public.service_orders set status = 'in_progress' where id = pg_temp.os('OS-J11')$q$),
      ('K2k3', 'awaiting_client', 'status', $q$update public.service_orders set status = 'awaiting_client' where id = pg_temp.os('OS-J11')$q$),
      ('K2k4', 'check-in', 'check_in', $q$update public.service_orders set check_in_at = timestamptz '2027-07-15 09:00-03' where id = pg_temp.os('OS-J11')$q$),
      ('K2k5', 'check-out', 'check_out', $q$update public.service_orders set check_out_at = timestamptz '2027-07-15 09:00-03' where id = pg_temp.os('OS-J11')$q$),
      ('K2k6', 'entregue', 'entregue', $q$set local agenda.porta = 'on'; update public.service_orders set check_out_at = timestamptz '2027-07-15 09:00-03', delivered_at = timestamptz '2027-07-15 09:00-03' where id = pg_temp.os('OS-J11'); set local agenda.porta = 'off'$q$),
      ('K2k7', 'alocação com resultado', 'resultado',
       $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, resultado)
          select pg_temp.os('OS-J11'), p.id, date '2026-10-20', 'manha', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(date '2026-10-08', '16:30'), 'cumprido'
            from public.payees p where p.name = 'Alex' and p.active$q$),
      ('K2k8', 'linha em work_shift_os', 'turno', $q$insert into public.work_shift_os (shift_id, service_order_id) values (gen_random_uuid(), pg_temp.os('OS-J11'))$q$),
      ('K2k9', 'paga inteira', 'paga',
       $q$update public.service_orders set grand_total = 1000 where id = pg_temp.os('OS-J11');
          insert into public.receivables (service_order_id, client_id, amount, paid_amount, status, issue_date, due_date, description, is_deposit)
          values (pg_temp.os('OS-J11'), pg_temp.cli('OS-J11'), 600, 600, 'paid', date '2027-07-01', date '2027-07-10', 'parcela', true),
                 (pg_temp.os('OS-J11'), pg_temp.cli('OS-J11'), 400, 400, 'paid', date '2027-07-01', date '2027-07-11', 'parcela', false)$q$)
    ) t(id, nome, motivo, sql)
  loop
    begin
      perform pg_temp.prepara(date '2027-06-01');
      execute v_sinal.sql;
      r := pg_temp.passo();
      v_res := pg_temp.ok(v_res, format('%s a guarda tira a OS: %s', v_sinal.id, v_sinal.nome),
        pg_temp.quem() = 'OS-J12' and (r #>> array['puladas', v_sinal.motivo])::int = 1 and (r ->> 'erros')::int = 0, r::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.service_orders set grand_total = 1000 where id = pg_temp.os('OS-J11');
    insert into public.receivables (service_order_id, client_id, amount, paid_amount, status, issue_date, due_date, description, is_deposit)
    values (pg_temp.os('OS-J11'), pg_temp.cli('OS-J11'), 500, 500, 'paid', date '2027-07-01', date '2027-07-10', 'sinal', true),
           (pg_temp.os('OS-J11'), pg_temp.cli('OS-J11'), 500, 0, 'pending', date '2027-07-01', date '2027-08-10', 'saldo', false),
           (pg_temp.os('OS-J11'), pg_temp.cli('OS-J11'), 500, 500, 'cancelled', date '2027-07-01', date '2027-07-10', 'cancelada', false);
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2l o sinal pago não é "paga inteira", e a cobrança cancelada não soma', pg_temp.quem() = 'OS-J11,OS-J12', pg_temp.quem());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.service_orders set grand_total = 0 where id = pg_temp.os('OS-J11');
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2m o total 0 não é "paga inteira"', pg_temp.quem() = 'OS-J11,OS-J12', pg_temp.quem());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (pg_temp.os('OS-J11'), v_alex, date '2027-07-16', 'manha', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(date '2027-07-08', '16:30'));
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2n o plano que começa hoje: a porta da aprovação não pergunta "para eu deixar encaminhado"', pg_temp.quem() = 'OS-J12' and (r #>> '{puladas,plano_comecou}')::int = 1, r::text);
    perform pg_temp.mover('OS-J11', date '2027-07-15');
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2o o plano que já começou, sem nenhuma marca: também não', pg_temp.quem() = 'OS-J12' and (r #>> '{puladas,plano_comecou}')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O que já foi dito
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.os_planejamento set bem_situacao = 'agua', bem_situacao_fonte = 'dono', bem_situacao_em = pg_temp.em(date '2027-07-10', '10:00') where service_order_id = pg_temp.os('OS-J12');
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2p o barco pela OS, com a situação dita: nada a perguntar', pg_temp.quem() = 'OS-J11' and (r #>> '{puladas,nada_a_perguntar}')::int >= 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.service_orders set converted_to_os_at = timestamptz '2027-07-15 10:00-03' where id = pg_temp.os('OS-J14');
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2q J14, o local dito sem a situação: ainda falta a situação do barco, e entra', pg_temp.quem() like '%OS-J14%', pg_temp.quem());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.service_orders set converted_to_os_at = timestamptz '2027-07-15 10:00-03' where id = pg_temp.os('OS-J14');
    update public.os_planejamento set bem_situacao = 'seco', bem_situacao_fonte = 'dono', bem_situacao_em = pg_temp.em(date '2027-07-10', '10:00') where service_order_id = pg_temp.os('OS-J14');
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2r J14, o local e a situação ditos: não recebe', pg_temp.quem() not like '%OS-J14%', pg_temp.quem());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.os_planejamento set entrada_em = date '2027-07-20', entrada_fonte = 'dono',
           local_id = (select id from public.agenda_locais where tipo = 'patio_hbr'), local_fonte = 'dono', local_em = pg_temp.em(date '2027-07-10', '10:00')
     where service_order_id = pg_temp.os('OS-J11');
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2s o motorhome no pátio com a entrada dita: não recebe', pg_temp.quem() = 'OS-J12', pg_temp.quem());
    update public.os_planejamento set entrada_em = null, entrada_fonte = null where service_order_id = pg_temp.os('OS-J11');
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2t o motorhome no pátio dito, sem a entrada: recebe', pg_temp.quem() = 'OS-J11,OS-J12', pg_temp.quem());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.os_planejamento set local_id = (select id from public.agenda_locais where nome = 'Marina Itajaí'), local_fonte = 'dono', local_em = pg_temp.em(date '2027-07-10', '10:00')
     where service_order_id = pg_temp.os('OS-J11');
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2u o motorhome com o local dito fora do pátio: não recebe', pg_temp.quem() = 'OS-J12', pg_temp.quem());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.vessels set name = 'Reboque', asset_type = 'Outro' where id = (select vessel_id from public.service_orders where id = pg_temp.os('OS-J11'));
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2v o bem que não é barco nem rv: não recebe', pg_temp.quem() = 'OS-J12', pg_temp.quem());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.vessels set marina_id = null where id = (select vessel_id from public.service_orders where id = pg_temp.os('OS-J13'));
    update public.clients set city = null where id = pg_temp.cli('OS-J13');
    update public.service_orders set converted_to_os_at = timestamptz '2027-07-15 10:00-03' where id = pg_temp.os('OS-J13');
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where service_order_id = pg_temp.os('OS-J13');
    update public.os_planejamento set bem_situacao = 'seco', bem_situacao_fonte = 'dono', bem_situacao_em = pg_temp.em(date '2027-07-10', '10:00') where service_order_id = pg_temp.os('OS-J13');
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2w a fonte nenhum (suposicao é falso nela): a situação dita não basta, e entra', (public._agenda_local_resolvido(pg_temp.os('OS-J13'), date '2027-07-16') ->> 'fonte') = 'nenhum' and pg_temp.quem() like '%OS-J13%', pg_temp.quem());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.vessels set marina_id = null where id = (select vessel_id from public.service_orders where id = pg_temp.os('OS-J8'));
    update public.service_orders set converted_to_os_at = timestamptz '2027-07-15 10:00-03' where id = pg_temp.os('OS-J8');
    update public.os_planejamento set bem_situacao = 'seco', bem_situacao_fonte = 'dono', bem_situacao_em = pg_temp.em(date '2027-07-10', '10:00') where service_order_id = pg_temp.os('OS-J8');
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2x o local como suposição (a cidade do cliente): a situação dita não basta, e entra', (public._agenda_local_resolvido(pg_temp.os('OS-J8'), date '2027-07-16') ->> 'fonte') = 'cidade' and pg_temp.quem() like '%OS-J8%', pg_temp.quem());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O freio
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2y o freio: {pulado: gestor_so_propor}, nada registrado, em ligado', r = '{"pulado": "gestor_so_propor"}'::jsonb and pg_temp.quem() = '', r::text);
    perform pg_temp.prepara(date '2027-06-01', false);
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2z o freio também em teste', r = '{"pulado": "gestor_so_propor"}'::jsonb and pg_temp.quem() = '', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O teto: o M11 cede o dia
  begin
    perform pg_temp.prepara(date '2027-06-01');
    -- J11 já tem a confirmação marcada para hoje, ainda só registrada: o M11 não toma o dia
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, dia_alvo, modo, texto, base, enviar_em, valida_ate, aprovacao, estado, dedupe_key, criada_em)
    values (pg_temp.cli('OS-J11'), pg_temp.os('OS-J11'), 'confirmar', 'rodada', date '2027-07-22', 'ligado', 'mensagem de teste', '{}', pg_temp.em(date '2027-07-16', '17:00'),
            pg_temp.em(date '2027-07-16', '19:00'), 'livre', 'registrada', 'agenda-cliente:teste:' || gen_random_uuid(), pg_temp.em(date '2027-07-16', '09:00'));
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2z1 o cliente já tem mensagem no dia, mesmo ainda não enfileirada: o M11 cede, sem registrar (a chave é única, e a recusa seria de vez)',
      pg_temp.quem() = 'OS-J12' and (r #>> '{puladas,cliente_ja_tem_mensagem}')::int = 1, r::text);
    r := pg_temp.passo(date '2027-07-17', '09:15');
    v_res := pg_temp.ok(v_res, 'K2z2 no dia seguinte o M11 sai', pg_temp.quem() = 'OS-J11,OS-J12' and (pg_temp.m('OS-J11')).estado = 'enfileirada', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- A rodada inteira: J12 tem o M1 hoje. Com o M11 antes de confirmar, o M1 seria recusado de vez por teto_dia
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.mover('OS-J12', date '2027-07-21');
    update public.os_planejamento set dias = 1, material_conferido_em = pg_temp.em(date '2027-07-10', '10:00') where service_order_id = pg_temp.os('OS-J12');
    perform set_config('agenda.hoje', '2027-07-16', true);
    r := public.agenda_cliente_vigiar(date '2027-07-16', pg_temp.em(date '2027-07-16', '08:30'));
    select count(*) into v_n from public.agenda_cliente_mensagens x where x.service_order_id = pg_temp.os('OS-J12') and x.tipo = 'confirmar' and x.estado <> 'recusada';
    v_res := pg_temp.ok(v_res, 'K2z3 a confirmação e o M11 no mesmo tique: a confirmação sai, o M11 espera, ninguém é recusado',
      v_n = 1 and pg_temp.m('OS-J12') is null and (r #>> '{contagens,onde_fica,puladas,cliente_ja_tem_mensagem}')::int = 1
      and not exists (select 1 from public.agenda_cliente_mensagens x where x.recusa_motivo in ('teto_dia', 'teto_semana')), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    -- Vanderlei, 2 motorhomes aprovados ontem: um M11 por dia, e o outro 24 h depois
    update public.service_orders set converted_to_os_at = timestamptz '2027-07-15 10:00-03' where id in (pg_temp.os('OS-J3'), pg_temp.os('OS-J5'));
    perform pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2z4 2 OS do mesmo cliente: um M11 no dia', (select count(*) from public.agenda_cliente_mensagens x where x.client_id = pg_temp.cli('OS-J3') and x.tipo = 'onde_fica') = 1, pg_temp.quem());
    perform pg_temp.saiu((pg_temp.m('OS-J3')).id, pg_temp.em(date '2027-07-16', '16:21'));
    r := pg_temp.passo(date '2027-07-17', '09:15');
    v_res := pg_temp.ok(v_res, 'K2z5 o 2º espera as 24 h do mesmo tipo (a revalidação o recusaria de vez)', pg_temp.m('OS-J5') is null and (r #>> '{puladas,cliente_ja_tem_mensagem}')::int = 1, r::text);
    r := pg_temp.passo(date '2027-07-19', '09:15');
    v_res := pg_temp.ok(v_res, 'K2z6 passadas as 24 h, ele sai', (pg_temp.m('OS-J5')).estado = 'enfileirada', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.agenda_config set cliente_semana_max = 1 where id;
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate, aprovacao, estado, dedupe_key, enviada_em, criada_em)
    values (pg_temp.cli('OS-J11'), pg_temp.os('OS-J11'), 'vespera', 'rodada', 'ligado', 'mensagem de teste', '{}', pg_temp.em(date '2027-07-13', '09:00'),
            pg_temp.em(date '2027-07-13', '19:00'), 'livre', 'enviada', 'agenda-cliente:teste:' || gen_random_uuid(), pg_temp.em(date '2027-07-13', '09:00'), pg_temp.em(date '2027-07-13', '08:00'));
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2z7 o teto da semana cheio: o M11 cede, em vez de ser recusado de vez', pg_temp.m('OS-J11') is null and (r #>> '{puladas,cliente_ja_tem_mensagem}')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- O erro de uma OS não derruba as outras
    perform pg_temp.prepara(date '2027-06-01');
    update public.os_planejamento set servico_cliente = 'o serviço de R$ 1000' where service_order_id = pg_temp.os('OS-J11');
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K2z8 a OS cujo texto o registrar recusa vai ao log, e o passo segue para as outras', pg_temp.quem() = 'OS-J12' and (r ->> 'erros')::int = 1
      and exists (select 1 from public.app_error_logs e where e.action = 'cliente:onde_fica:os'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$k2$;

-- ── K3. Em teste, a aprovação, a fila ─────────────────────────────────────────────────────────────
do $k3$
declare
  v_res  jsonb := '[]'::jsonb;
  r      jsonb;
  m      public.agenda_cliente_mensagens;
  q      public.whatsapp_send_queue;
  a      public.agenda_acoes;
  c      public.agenda_config;
  v_t    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K3 em teste e a fila', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  select * into c from public.agenda_config where id;
  begin
    -- A produção: modo_cliente ligado com os 11 tipos, sem onde_fica
    perform pg_temp.prepara(date '2027-06-01', false);
    r := public.agenda_cliente_vigiar(date '2027-07-16', pg_temp.em(date '2027-07-16', '16:20'));
    m := pg_temp.m('OS-J11');
    q := pg_temp.fila(m.id);
    v_res := pg_temp.ok(v_res, 'K3a fora da lista = em teste: a linha com :sombra, o modelo M11, nada na fila', m.modo = 'sombra' and m.modelo = 'M11' and m.dedupe_key like '%:sombra' and q.id is null
      and m.estado = 'registrada' and not exists (select 1 from public.whatsapp_send_queue x where x.source = 'agenda-cliente'), m::text);
    select * into a from public.agenda_acoes x where x.id = m.acao_id;
    v_res := pg_temp.ok(v_res, 'K3b a ação "Em teste", sem executar', a.executada = false and a.tipo = 'cliente' and a.texto like 'Em teste: eu teria mandado para Carla a pergunta de onde fica o bem (sairia %', a.texto);
    v_res := pg_temp.ok(v_res, 'K3c a rodada conta o passo, e a resposta do cliente nem acha a mensagem (modo_cliente ligado)',
      (r #>> '{contagens,onde_fica,registradas}')::int = 2
      and (pg_temp.resp('OS-J11', 'na marina itajai', 'outro', pg_temp.em(date '2027-07-16', '18:00'))) ->> 'consumiu' = 'false', r::text);
    v_t := (public._agenda_ver_clientes(pg_temp.os('OS-J11'), date '2027-07-16')) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'K3d *agenda clientes*: o tipo ainda em teste e o que eu teria mandado', v_t like '%Ainda em teste (não saem): onde fica o bem.%' and v_t like '%Em teste, eu teria mandado:%Carla: a pergunta de onde fica o bem%', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.agenda_config set cliente_aprovacao_dias = 3 where id;
    r := pg_temp.passo();
    m := pg_temp.m('OS-J11');
    v_res := pg_temp.ok(v_res, 'K3e ligado nos 3 primeiros dias: espera o dono, com a mensagem inteira na pergunta; nada na fila',
      m.modo = 'ligado' and m.aprovacao = 'pedida' and m.estado = 'aguardando_dono' and pg_temp.fila(m.id) is null
      and (select x.tipo from public.agenda_perguntas x where x.id = m.pergunta_id) = 'cliente_aprovar'
      and (select x.texto from public.agenda_perguntas x where x.id = m.pergunta_id) like 'Mensagem para Carla (onde fica o bem), sai %*manda cliente Carla* ou *segura cliente Carla*.', r::text);
    r := public._agenda_cliente_decidir(m.pergunta_id, 1::smallint, pg_temp.adm(), 'whatsapp', 'manda', pg_temp.em(date '2027-07-16', '16:30'));
    m := pg_temp.m('OS-J11');
    q := pg_temp.fila(m.id);
    v_res := pg_temp.ok(v_res, 'K3f o sim do dono: aprovada e na fila', m.aprovacao = 'aprovada' and m.estado = 'enfileirada' and q.source = 'agenda-cliente' and q.message = m.texto, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    r := pg_temp.passo();
    m := pg_temp.m('OS-J11');
    q := pg_temp.fila(m.id);
    v_res := pg_temp.ok(v_res, 'K3g liberado: livre e na fila, com o texto, a chave e o telefone dela', m.aprovacao = 'livre' and m.estado = 'enfileirada' and q.source = 'agenda-cliente' and q.message = m.texto
      and q.dedupe_key = m.dedupe_key and q.phone_normalized = pg_temp.fone('OS-J11'), q::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    r := pg_temp.passo(date '2027-07-16', '19:30');
    m := pg_temp.m('OS-J11');
    v_res := pg_temp.ok(v_res, 'K3h depois da janela: fica para a próxima abertura, sem ir à fila agora',
      m.estado = 'registrada' and pg_temp.fila(m.id) is null and (m.enviar_em at time zone 'America/Sao_Paulo')::date = date '2027-07-17' and (m.enviar_em at time zone 'America/Sao_Paulo')::time >= time '08:00', m.enviar_em::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.clients set phone = null, whatsapp = null where id = pg_temp.cli('OS-J11');
    update public.clients set opt_out_whatsapp = true where id = pg_temp.cli('OS-J12');
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K3i sem telefone e com opt-out: registrada e recusada com o motivo, nada na fila',
      (pg_temp.m('OS-J11')).estado = 'recusada' and (pg_temp.m('OS-J11')).recusa_motivo = 'sem_telefone' and (pg_temp.m('OS-J12')).recusa_motivo = 'opt_out'
      and not exists (select 1 from public.whatsapp_send_queue x where x.source = 'agenda-cliente'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.agenda_config set cliente_conversa_dias = 365 where id;
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K3j quem nunca escreveu para a HBR não recebe', (pg_temp.m('OS-J11')).recusa_motivo = 'sem_conversa', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01', false);
    perform pg_temp.passo();
    perform pg_temp.prepara(date '2027-06-01');
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K3k a linha em teste não segura a de verdade: quando o tipo entrar na lista, a OS recebe', (r ->> 'registradas')::int = 2
      and (select count(*) from public.agenda_cliente_mensagens x where x.tipo = 'onde_fica' and x.modo = 'sombra') = 2
      and (select count(*) from public.agenda_cliente_mensagens x where x.tipo = 'onde_fica' and x.modo = 'ligado') = 2, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$k3$;

-- ── K4. A resposta ────────────────────────────────────────────────────────────────────────────────
do $k4$
declare
  v_res  jsonb := '[]'::jsonb;
  r      jsonb;
  r2     jsonb;
  m      public.agenda_cliente_mensagens;
  q      public.agenda_perguntas;
  a      public.agenda_acoes;
  v_agora timestamptz := pg_temp.em(date '2027-07-16', '18:00');
  v_t    text;
  v_ok   timestamptz := pg_temp.em(date '2027-07-01', '10:00');
  v_tr   record;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K4 a resposta', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;

  -- A leitura, frase por frase
  for v_tr in select * from (values
      ('K4a', 'OS-J2', 'na marina itajai, fica na garagem, quem desce é a marina', 'Marina Itajaí', 'garagem_seca', 'a marina', 'Marina Itajaí, em seco (garagem), quem desce: a marina'),
      ('K4b', 'OS-J2', 'Na Marina de Itajaí, na água. O marinheiro desce', 'Marina Itajaí', 'agua', 'o marinheiro', 'Marina Itajaí, na água, quem desce: o marinheiro'),
      ('K4c', 'OS-J14', 'tá na tedesco em seco, eu mesmo desco', 'Tedesco Marina Garden Plaza', 'garagem_seca', 'o cliente', 'Tedesco Marina Garden Plaza, em seco (garagem), quem desce: o cliente'),
      ('K4d', 'OS-J6', 'está em seco', null, 'seco', null, 'em seco'),
      ('K4e', 'OS-J11', 'levo aí no pátio de vocês', 'MP Motorhomes', 'patio', null, 'MP Motorhomes, no pátio'),
      ('K4f', 'OS-J12', 'fica no pier', null, 'agua', null, 'na água'),
      ('K4g', 'OS-J12', 'na marina do joão', null, null, null, null),
      ('K4h', 'OS-J12', 'fico no aguardo, obrigado', null, null, null, null),
      ('K4i', 'OS-J12', 'marina itajai ou tedesco, não lembro', null, null, null, null),
      ('K4j', 'OS-J12', 'o secador quebrou', null, null, null, null),
      ('K4j4', 'OS-J6', 'na tedesco, em seco', 'Tedesco Marina Garden Plaza', 'garagem_seca', null, 'Tedesco Marina Garden Plaza, em seco (garagem)'),
      ('K4j5', 'OS-J12', 'no iate clube caioba, em seco', 'Iate Clube Caiobá', 'seco', null, 'Iate Clube Caiobá, em seco'),
      ('K4j6', 'OS-J12', 'fica em seco', null, 'garagem_seca', null, 'em seco (garagem)')
    ) t(id, os, frase, loc, sit, quem, ent)
  loop
    r := public._agenda_local_proposto(pg_temp.os(v_tr.os), v_tr.frase, date '2027-07-16');
    v_res := pg_temp.ok(v_res, format('%s a leitura de "%s"', v_tr.id, v_tr.frase),
      r ->> 'local_nome' is not distinct from v_tr.loc and r ->> 'situacao' is not distinct from v_tr.sit and r ->> 'descer_quem' is not distinct from v_tr.quem
      and r ->> 'entendi' is not distinct from v_tr.ent, r::text);
  end loop;

  begin
    update public.agenda_locais set apelidos = '{}' where nome = 'Iate Clube Caiobá';
    r := public._agenda_local_proposto(pg_temp.os('OS-J12'), 'no iate clube caioba', date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'K4j2 o nome do local vale sem apelido', r ->> 'local_nome' = 'Iate Clube Caiobá', r::text);
    update public.agenda_locais set ativo = false where nome = 'Iate Clube Caiobá';
    r := public._agenda_local_proposto(pg_temp.os('OS-J12'), 'no iate clube caioba', date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'K4j3 o local inativo não entra', r ->> 'local_id' is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.j2_sem_situacao();
    update public.agenda_config set modo_vigia = 'ligado' where id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, modo, criada_em)
    values ('bem_livre', 'bem_livre:' || pg_temp.os('OS-J2'), pg_temp.os('OS-J2'), array[pg_temp.os('OS-J2')], 'O veleiro está livre?', '[]', 'ligado', pg_temp.em(date '2027-07-15', '16:00'));
    m := pg_temp.mandado('OS-J2');
    v_res := pg_temp.ok(v_res, 'K4k o M11 saiu', m.estado = 'enviada' and m.enviada_em is not null, m::text);
    r := pg_temp.resp('OS-J2', 'na marina itajai, fica na garagem, quem desce é a marina', 'outro', v_agora);
    v_res := pg_temp.ok(v_res, 'K4l a resposta: consumiu, efeito anotou_acesso, a mensagem fica respondida', (r ->> 'consumiu')::boolean and r ->> 'efeito' = 'anotou_acesso'
      and (pg_temp.m('OS-J2')).estado = 'respondida', r::text);
    v_res := pg_temp.ok(v_res, 'K4m a linha em site_access', (select so.site_access from public.service_orders so where so.id = pg_temp.os('OS-J2')) = 'Cliente (16/07): na marina itajai, fica na garagem, quem desce é a marina',
      (select so.site_access from public.service_orders so where so.id = pg_temp.os('OS-J2')));
    select * into a from public.agenda_acoes x where x.id = (r ->> 'acao_id')::uuid;
    v_res := pg_temp.ok(v_res, 'K4n a ação do cliente, desfazível, com efeito anotou_acesso', a.tipo = 'cliente' and a.origem = 'cliente' and a.executada and a.depois ->> 'efeito' = 'anotou_acesso' and a.desfazivel_ate is not null
      and a.texto = 'Anotei o que Nelson disse sobre onde fica o veleiro: "na marina itajai, fica na garagem, quem desce é a marina".', a.texto);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'K4o a pergunta local com a leitura: o texto da §6.3, byte a byte',
      q.tipo = 'local' and not q.critica and q.modo = 'ligado' and q.estado = 'aberta' and q.recomendacao = 1 and q.expira_em = v_agora + interval '7 days' and q.id = (r ->> 'pergunta_id')::uuid
      and q.texto = 'Nelson respondeu onde fica o veleiro: "na marina itajai, fica na garagem, quem desce é a marina". Entendi: Marina Itajaí, em seco (garagem), quem desce: a marina. 1) Gravo assim (recomendo); 2) Não gravo, eu te digo como é.', q.texto);
    v_res := pg_temp.ok(v_res, 'K4p R6.3-5: acesso_ok_em continua nulo, antes e depois na ação', (select p.acesso_ok_em from public.os_planejamento p where p.service_order_id = pg_temp.os('OS-J2')) is null
      and a.antes ? 'acesso_ok_em' and a.antes -> 'acesso_ok_em' = a.depois -> 'acesso_ok_em', a.depois::text);
    v_res := pg_temp.ok(v_res, 'K4q a pergunta bem_livre fica resolvida, com o motivo', (select x.estado || '|' || x.resolvida_motivo from public.agenda_perguntas x where x.chave = 'bem_livre:' || pg_temp.os('OS-J2')) = 'resolvida|o cliente respondeu onde fica', null);
    v_res := pg_temp.ok(v_res, 'K4r nada gravado no planejamento antes do sim do dono', (select p.local_id is null and p.bem_situacao is null and p.descer_quem is null from public.os_planejamento p where p.service_order_id = pg_temp.os('OS-J2')), null);
    perform set_config('agenda.agora', (v_agora + interval '1 minute')::text, true);
    v_t := (public._agenda_ver_clientes(pg_temp.os('OS-J2'), date '2027-07-16')) ->> 'texto';
    perform set_config('agenda.agora', '', true);
    v_res := pg_temp.ok(v_res, 'K4s *agenda clientes* não diz "o acesso"', v_t like '%disse onde fica, e eu anotei e perguntei a você%' and v_t not like '%disse o acesso%', v_t);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:30'));
    v_res := pg_temp.ok(v_res, 'K4t o *desfaz* já conhece: o site_access volta, acesso_ok_em segue como estava', (r2 ->> 'ok')::boolean
      and (select so.site_access from public.service_orders so where so.id = pg_temp.os('OS-J2')) is null
      and (select p.acesso_ok_em from public.os_planejamento p where p.service_order_id = pg_temp.os('OS-J2')) is null, r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Com acesso_ok_em já gravado: ele não anda, nem para frente nem para trás
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.os_planejamento set acesso_ok_em = v_ok where service_order_id = pg_temp.os('OS-J12');
    m := pg_temp.mandado('OS-J12');
    r := pg_temp.resp('OS-J12', 'na marina itajai', 'acesso', v_agora);
    v_res := pg_temp.ok(v_res, 'K4u a intenção acesso também vai a anotar_onde, e acesso_ok_em não anda', r ->> 'efeito' = 'anotou_acesso' and (select p.acesso_ok_em from public.os_planejamento p where p.service_order_id = pg_temp.os('OS-J12')) = v_ok, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A crítica de véspera nasce mesmo com a resposta anotada: o item acesso segue por combinar
  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.agenda_config set modo_proposta = 'ligado', modo_vigia = 'ligado', modo_local_autorizacao = 'ligado' where id;
    m := pg_temp.mandado('OS-J12');
    r := pg_temp.resp('OS-J12', 'na marina itajai, na água', 'outro', v_agora);
    perform pg_temp.mover('OS-J12', date '2027-07-20');
    perform set_config('agenda.hoje', '2027-07-19', true);
    r2 := public._agenda_local_combinar(date '2027-07-19', pg_temp.em(date '2027-07-19', '16:20'));
    v_res := pg_temp.ok(v_res, 'K4v a resposta não conta como acesso: em D-1 a crítica acesso nasce', (select count(*) from public.agenda_perguntas x where x.tipo = 'acesso' and x.service_order_id = pg_temp.os('OS-J12')) = 1, r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Sem leitura
  begin
    perform pg_temp.prepara(date '2027-06-01');
    m := pg_temp.mandado('OS-J12');
    r := pg_temp.resp('OS-J12', 'na marina do joão', 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J12');
    v_res := pg_temp.ok(v_res, 'K4w sem leitura: o texto da §6.3, só a opção 2, sem recomendação',
      q.texto = 'Beto respondeu onde fica a lancha: "na marina do joão". Não achei esse lugar no cadastro. Me diga onde é, por exemplo: "o serviço do Beto é na Marina Itajaí".'
      and jsonb_array_length(q.opcoes) = 1 and (q.opcoes -> 0 ->> 'n')::int = 2 and q.recomendacao is null, q.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    m := pg_temp.mandado('OS-J11');
    r := pg_temp.resp('OS-J11', 'está no sítio do meu irmão', 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J11');
    -- (correção O19) o mesmo exemplo no motorhome: lugar, não data
    v_res := pg_temp.ok(v_res, 'K4x sem leitura, no motorhome: o exemplo é de lugar (correção O19)', q.texto like 'Carla respondeu onde fica o motorhome: "está no sítio do meu irmão". Não achei esse lugar no cadastro. Me diga onde é, por exemplo: "o serviço do Carla é na Marina Itajaí".', q.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O que não vai a anotar_onde
  begin
    perform pg_temp.prepara(date '2027-06-01');
    m := pg_temp.mandado('OS-J11');
    r := pg_temp.resp('OS-J11', '[audio]', 'outro', v_agora, 'audio');
    v_res := pg_temp.ok(v_res, 'K4y o áudio vai ao dono: nada no site_access, nenhuma pergunta local', r ->> 'efeito' = 'ao_dono' and r ->> 'intencao' = 'audio' and (r ->> 'consumiu')::boolean
      and (select so.site_access from public.service_orders so where so.id = pg_temp.os('OS-J11')) is null
      and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'local')
      and (select x.tipo from public.agenda_perguntas x where x.id = (r ->> 'pergunta_id')::uuid) = 'cliente_resposta', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    m := pg_temp.mandado('OS-J11');
    r := pg_temp.resp('OS-J11', 'uma foto', 'outro', v_agora, 'image');
    v_res := pg_temp.ok(v_res, 'K4z a foto vai ao dono', r ->> 'efeito' = 'ao_dono' and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'local'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  for v_tr in select * from (values ('K4z1', 'opt_out', 'PARAR'), ('K4z2', 'disputa', 'que absurdo, vocês não fizeram nada'), ('K4z3', 'negociacao', 'faz um desconto?'), ('K4z4', 'acordo', 'combinado então')) t(id, intencao, frase) loop
    begin
      perform pg_temp.prepara(date '2027-06-01');
      m := pg_temp.mandado('OS-J11');
      r := pg_temp.resp('OS-J11', v_tr.frase, v_tr.intencao, v_agora);
      v_res := pg_temp.ok(v_res, format('%s %s segue o caminho de sempre: sem pergunta local e sem site_access', v_tr.id, v_tr.intencao),
        r ->> 'efeito' = case v_tr.intencao when 'opt_out' then 'opt_out' else 'ao_dono' end and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'local')
        and (select so.site_access from public.service_orders so where so.id = pg_temp.os('OS-J11')) is null, r::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  for v_tr in select * from (values ('K4z5', 'pergunta', 'pode ficar na marina?'), ('K4z6', 'confirma', 'fica no pátio'), ('K4z7', 'data', 'na marina, dia 20')) t(id, intencao, frase) loop
    begin
      perform pg_temp.prepara(date '2027-06-01');
      m := pg_temp.mandado('OS-J11');
      r := pg_temp.resp('OS-J11', v_tr.frase, v_tr.intencao, v_agora);
      v_res := pg_temp.ok(v_res, format('%s %s vai a anotar_onde', v_tr.id, v_tr.intencao), r ->> 'efeito' = 'anotou_acesso' and exists (select 1 from public.agenda_perguntas x where x.tipo = 'local'), r::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;

  begin
    perform pg_temp.prepara(date '2027-06-01');
    update public.service_orders set site_access = 'portão azul' where id = pg_temp.os('OS-J12');
    perform pg_temp.mandado('OS-J12');
    r := pg_temp.resp('OS-J12', 'fica na agua', 'outro', v_agora);
    v_res := pg_temp.ok(v_res, 'K4z10 o que havia em site_access fica, e a linha entra no fim', (select so.site_access from public.service_orders so where so.id = pg_temp.os('OS-J12')) = E'portão azul\nCliente (16/07): fica na agua',
      (select so.site_access from public.service_orders so where so.id = pg_temp.os('OS-J12')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.mandado('OS-J12');
    r := pg_temp.resp('OS-J12', 'fica na agua ' || repeat('e mais uma coisa ', 40), 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J12');
    v_res := pg_temp.ok(v_res, 'K4z11 a resposta longa: a pergunta guarda as opções inteiras', char_length(q.texto) <= 600 and q.texto like '%1) Gravo assim (recomendo); 2) Não gravo, eu te digo como é.', q.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- A resposta a outra mensagem não vai a anotar_onde
    perform pg_temp.prepara(date '2027-06-01');
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate, aprovacao, estado, dedupe_key, enviada_em, criada_em)
    values (pg_temp.cli('OS-J11'), pg_temp.os('OS-J11'), 'pronto', 'rodada', 'ligado', 'mensagem de teste', '{}', v_agora - interval '1 hour', v_agora, 'livre', 'enviada',
            'agenda-cliente:teste:' || gen_random_uuid(), v_agora - interval '1 hour', v_agora - interval '2 hours');
    r := pg_temp.resp('OS-J11', 'na marina itajai', 'outro', v_agora);
    v_res := pg_temp.ok(v_res, 'K4z12 a resposta a outra mensagem segue o caminho de sempre', r ->> 'efeito' = 'ao_dono' and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'local'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Em teste (modo_cliente sombra): só registra, e consumiu false
  begin
    perform pg_temp.prepara(date '2027-06-01', false);
    update public.agenda_config set modo_cliente = 'sombra' where id;
    perform pg_temp.passo();
    r := pg_temp.resp('OS-J11', 'na marina itajai', 'outro', v_agora);
    v_res := pg_temp.ok(v_res, 'K4z8 em teste: registra, consumiu false, nada anotado', not (r ->> 'consumiu')::boolean and r ->> 'efeito' = 'sombra'
      and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'local') and (select so.site_access from public.service_orders so where so.id = pg_temp.os('OS-J11')) is null, r::text);
    perform set_config('agenda.agora', v_agora::text, true);
    v_t := (public._agenda_ver_clientes(pg_temp.os('OS-J11'), date '2027-07-16')) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'K4z9 *agenda clientes* em teste diz o que eu teria feito', v_t like '%eu teria anotado onde fica e perguntado a você%', v_t);
    perform set_config('agenda.agora', '', true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$k4$;

-- ── K5. O decidir local ───────────────────────────────────────────────────────────────────────────
do $k5$
declare
  v_res  jsonb := '[]'::jsonb;
  r      jsonb;
  r2     jsonb;
  q      public.agenda_perguntas;
  a      public.agenda_acoes;
  pl     public.os_planejamento;
  v_agora timestamptz := pg_temp.em(date '2027-07-16', '18:00');
  v_h    date := date '2027-07-16';
  v_md5  text;
  v_t    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K5 o decidir local', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.j2_sem_situacao();
    perform pg_temp.mandado('OS-J2');
    perform pg_temp.resp('OS-J2', 'na marina itajai, fica na garagem, quem desce é a marina', 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J2');
    select md5(string_agg(a2.id::text || a2.dia || a2.turno || a2.estado, ',' order by a2.id)) into v_md5 from public.agenda_alocacoes a2;
    r := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', v_h, v_agora);
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'K5a a opção 1 grava o local, a situação e quem desce, com a fonte cliente e o texto da §6.3', (r ->> 'ok')::boolean
      and pl.local_id = (select id from public.agenda_locais where nome = 'Marina Itajaí') and pl.local_fonte = 'cliente' and pl.local_em = v_agora
      and pl.bem_situacao = 'garagem_seca' and pl.bem_situacao_fonte = 'cliente' and pl.bem_situacao_em = v_agora and pl.descer_quem = 'a marina'
      and r ->> 'texto' = 'Gravei o que Nelson disse: o veleiro está na Marina Itajaí, em seco, e quem desce é a marina. *desfaz* volta.', r::text);
    select * into a from public.agenda_acoes x where x.id = (r ->> 'acao_id')::uuid;
    v_res := pg_temp.ok(v_res, 'K5b a ação local, do dono, desfazível; a pergunta fica respondida', a.tipo = 'local' and a.origem = 'dono' and a.executada and a.desfazivel_ate is not null and a.pergunta_id = q.id
      and a.depois ->> 'efeito' = 'local' and a.depois ->> 'local_fonte' = 'cliente' and a.depois ->> 'bem_situacao_fonte' = 'cliente'
      and (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'respondida', a::text);
    v_res := pg_temp.ok(v_res, 'K5c não mexe no plano', v_md5 = (select md5(string_agg(a2.id::text || a2.dia || a2.turno || a2.estado, ',' order by a2.id)) from public.agenda_alocacoes a2)
      and not exists (select 1 from public.agenda_acoes x where x.tipo in ('replanejar', 'replano') and x.service_order_id = pg_temp.os('OS-J2')), null);
    v_res := pg_temp.ok(v_res, 'K5d a cadeia do local passa a dizer: o cliente disse', (public._agenda_local_resolvido(pg_temp.os('OS-J2'), v_h)) ->> 'fonte' = 'cliente', null);
    v_res := pg_temp.ok(v_res, 'K5e o histórico guarda', (select x.historico -> -1 ->> 'motivo' from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) = 'você respondeu: local', null);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', v_h, v_agora + interval '10 minutes');
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'K5f o *desfaz* volta as colunas, com o texto da §6.3', (r2 ->> 'ok')::boolean and pl.local_id is null and pl.local_fonte is null and pl.local_em is null
      and pl.bem_situacao is null and pl.bem_situacao_fonte is null and pl.bem_situacao_em is null and pl.descer_quem is null
      and r2 ->> 'texto' = 'Desfeito: o local do serviço de Nelson voltou a ser o que eu supunha.', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- O que a ação não escreveu continua; e o *desfaz* que acha outro valor recusa
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.mandado('OS-J12');
    update public.os_planejamento set descer_quem = 'o Zé' where service_order_id = pg_temp.os('OS-J12');
    perform pg_temp.resp('OS-J12', 'fica na agua', 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J12');
    r := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', v_h, v_agora);
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J12');
    v_res := pg_temp.ok(v_res, 'K5g a leitura parcial grava só o que achou', pl.bem_situacao = 'agua' and pl.local_id is null and pl.descer_quem = 'o Zé'
      and r ->> 'texto' = 'Gravei o que Beto disse: a lancha está na água. *desfaz* volta.', r::text);
    update public.os_planejamento set bem_situacao = 'seco', bem_situacao_fonte = 'dono' where service_order_id = pg_temp.os('OS-J12');
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', v_h, v_agora + interval '10 minutes');
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J12');
    v_res := pg_temp.ok(v_res, 'K5h o *desfaz* recusa se o que ela gravou mudou depois', not (r2 ->> 'ok')::boolean and pl.bem_situacao = 'seco', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.mandado('OS-J12');
    perform pg_temp.resp('OS-J12', 'só quem desce: o marinheiro', 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J12');
    r := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', v_h, v_agora);
    v_res := pg_temp.ok(v_res, 'K5i só quem desce', r ->> 'texto' = 'Gravei o que Beto disse: quem desce é o marinheiro. *desfaz* volta.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.j2_sem_situacao();
    perform pg_temp.mandado('OS-J2');
    perform pg_temp.resp('OS-J2', 'na marina itajai', 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J2');
    r := public.agenda_decidir(q.id, 2::smallint, pg_temp.adm(), 'whatsapp', '2', v_h, v_agora);
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'K5j a opção 2 só responde: nada gravado, o texto da §6.3', (r ->> 'ok')::boolean and r ->> 'texto' = 'Certo, não gravei. Quando souber, me diga onde é.'
      and pl.local_id is null and pl.bem_situacao is null and pl.descer_quem is null and not (r ? 'acao_id')
      and (select x.estado || x.opcao_escolhida from public.agenda_perguntas x where x.id = q.id) = 'respondida2', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.mandado('OS-J12');
    perform pg_temp.resp('OS-J12', 'na marina do joão', 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J12');
    r := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', v_h, v_agora);
    v_res := pg_temp.ok(v_res, 'K5k sem leitura não há opção 1: recusa, nada grava', not (r ->> 'ok')::boolean and r ->> 'texto' like 'Essa opção não existe.%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.mandado('OS-J12');
    perform pg_temp.resp('OS-J12', 'fica na agua', 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J12');
    update public.agenda_config set gestor_so_propor = true where id;
    r := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', v_h, v_agora);
    v_res := pg_temp.ok(v_res, 'K5l com o freio, a pergunta local segue respondível (R6.7b)', (r ->> 'ok')::boolean and (select x.bem_situacao from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J12')) = 'agua', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.mandado('OS-J12');
    perform pg_temp.resp('OS-J12', 'fica na agua', 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J12');
    update public.agenda_config set modo_cliente = 'sombra' where id;
    r := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', v_h, v_agora);
    v_res := pg_temp.ok(v_res, 'K5m com o modo cru fora de ligado: recusa', not (r ->> 'ok')::boolean and r ->> 'texto' like '%em teste%' and (select x.bem_situacao from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J12')) is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A conversa: a local tem resposta pelo mesmo caminho da combinar
  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.mandado('OS-J12');
    perform pg_temp.resp('OS-J12', 'fica na agua', 'outro', v_agora);
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J12');
    v_res := pg_temp.ok(v_res, 'K5n agenda_decisoes_abertas leva a local, com as opções', (select count(*) from jsonb_array_elements(public.agenda_decisoes_abertas(v_agora)) e where e ->> 'tipo' = 'local' and e ->> 'id' = q.id::text and jsonb_array_length(e -> 'opcoes') = 2) = 1,
      public.agenda_decisoes_abertas(v_agora)::text);
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, modo, criada_em)
    values ('duracao', 'duracao:teste', pg_temp.os('OS-J12'), array[pg_temp.os('OS-J12')], 'Quanto tempo leva?', '[]', 'ligado', v_agora);
    v_res := pg_temp.ok(v_res, 'K5o os outros tipos não crítica continuam fora', (select count(*) from jsonb_array_elements(public.agenda_decisoes_abertas(v_agora)) e where e ->> 'tipo' = 'duracao') = 0, null);
    v_t := (public._agenda_ver_decisoes(v_h, v_agora)) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'K5p _agenda_ver_decisoes numera a local e não a repete em "Também quero saber"', v_t like '%Decisão 1: Beto respondeu onde fica a lancha%' and v_t not like '%Também quero saber: Beto%' and v_t like '%Também quero saber: Quanto tempo leva?%', v_t);
    r := public.agenda_rascunho_aplicar(pg_temp.adm(), 'whatsapp', null, null, '1', '1', 'grava assim', v_h, v_agora);
    r2 := public.agenda_rascunho_gravar(pg_temp.adm(), v_h);
    v_res := pg_temp.ok(v_res, 'K5q o *grava* chega a agenda_decidir: a resposta pela conversa grava', (select x.bem_situacao from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J12')) = 'agua'
      and (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'respondida', r::text || ' ' || r2::text);
    v_res := pg_temp.ok(v_res, 'K5r respondida, ela sai da lista', (select count(*) from jsonb_array_elements(public.agenda_decisoes_abertas(v_agora)) e where e ->> 'tipo' = 'local') = 0, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.mandado('OS-J12');
    perform pg_temp.resp('OS-J12', 'fica na agua', 'outro', v_agora);
    v_res := pg_temp.ok(v_res, 'K5s vencida em 7 dias, ela sai da lista', (select count(*) from jsonb_array_elements(public.agenda_decisoes_abertas(v_agora + interval '8 days')) e where e ->> 'tipo' = 'local') = 0, null);
    perform set_config('agenda.hoje', v_h::text, true);
    update public.agenda_perguntas set estado = 'descartada' where tipo <> 'local' and estado = 'aberta';
    v_res := pg_temp.ok(v_res, 'K5t no fechamento ela é pergunta de perda 30, a mais baixa (nada espera por ela)',
      (select (e ->> 'perda')::int from jsonb_array_elements(public._agenda_linhas_do_fechamento(v_h)) e where e ->> 'texto' like 'Agenda: Beto respondeu onde fica%') = 30, public._agenda_linhas_do_fechamento(v_h)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$k5$;

-- ── K6. A revalidação ─────────────────────────────────────────────────────────────────────────────
do $k6$
declare
  v_res  jsonb := '[]'::jsonb;
  m      public.agenda_cliente_mensagens;
  v_agora timestamptz := pg_temp.em(date '2027-07-16', '17:30');
  v_s    record;
  r      jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K6 a revalidação', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  for v_s in select * from (values
      ('K6b', 'in_progress', 'status', $q$update public.service_orders set status = 'in_progress' where id = pg_temp.os('OS-J11')$q$),
      ('K6c', 'awaiting_client', 'status', $q$update public.service_orders set status = 'awaiting_client' where id = pg_temp.os('OS-J11')$q$),
      ('K6d', 'completed', 'status', $q$update public.service_orders set status = 'completed' where id = pg_temp.os('OS-J11')$q$),
      ('K6e', 'invoiced (a faturada vale como concluída)', 'status', $q$update public.service_orders set status = 'invoiced' where id = pg_temp.os('OS-J11')$q$),
      ('K6f', 'delivered_at', 'status', $q$set local agenda.porta = 'on'; update public.service_orders set check_out_at = timestamptz '2027-07-16 17:00-03', delivered_at = timestamptz '2027-07-16 17:00-03' where id = pg_temp.os('OS-J11'); set local agenda.porta = 'off'$q$),
      ('K6g', 'check-in', 'status', $q$update public.service_orders set check_in_at = timestamptz '2027-07-16 17:00-03' where id = pg_temp.os('OS-J11')$q$),
      ('K6h', 'check-out', 'status', $q$update public.service_orders set check_out_at = timestamptz '2027-07-16 17:00-03' where id = pg_temp.os('OS-J11')$q$),
      ('K6i', 'alocação com resultado', 'status',
       $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, resultado)
          select pg_temp.os('OS-J11'), p.id, date '2026-10-20', 'manha', 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(date '2026-10-08', '16:30'), 'cumprido'
            from public.payees p where p.name = 'Alex' and p.active$q$),
      ('K6j', 'paga inteira', 'status',
       $q$update public.service_orders set grand_total = 1000 where id = pg_temp.os('OS-J11');
          insert into public.receivables (service_order_id, client_id, amount, paid_amount, status, issue_date, due_date, description, is_deposit)
          values (pg_temp.os('OS-J11'), pg_temp.cli('OS-J11'), 1000, 1000, 'paid', date '2027-07-01', date '2027-07-10', 'parcela', true)$q$),
      ('K6p', 'linha em work_shift_os', 'status', $q$insert into public.work_shift_os (shift_id, service_order_id) values (gen_random_uuid(), pg_temp.os('OS-J11'))$q$),
      ('K6k', 'o local e a situação ditos', 'desatualizada',
       $q$update public.os_planejamento set local_id = (select id from public.agenda_locais where nome = 'Marina Itajaí'), local_fonte = 'dono', local_em = now(),
                 bem_situacao = 'agua', bem_situacao_fonte = 'dono', bem_situacao_em = now() where service_order_id = pg_temp.os('OS-J11')$q$),
      ('K6l', 'o motorhome no pátio dito, com a entrada', 'desatualizada',
       $q$update public.os_planejamento set local_id = (select id from public.agenda_locais where tipo = 'patio_hbr'), local_fonte = 'cliente', local_em = now(),
                 entrada_em = date '2027-07-20', entrada_fonte = 'cliente' where service_order_id = pg_temp.os('OS-J11')$q$)
    ) t(id, nome, motivo, sql)
  loop
    begin
      perform pg_temp.prepara(date '2027-06-01');
      update public.agenda_config set cliente_aprovacao_dias = 3 where id;
      perform pg_temp.passo();
      m := pg_temp.m('OS-J11');
      if v_s.id = 'K6b' then
        v_res := pg_temp.ok(v_res, 'K6a a mensagem de pé: a revalidação deixa sair, e o pode_sair não recusa por ela', public._agenda_cliente_revalidar(m.id, v_agora) is null, public._agenda_cliente_revalidar(m.id, v_agora));
      end if;
      execute v_s.sql;
      v_res := pg_temp.ok(v_res, format('%s revalidar, na hora de sair: %s = %s', v_s.id, v_s.nome, v_s.motivo), public._agenda_cliente_revalidar(m.id, v_agora) = v_s.motivo, public._agenda_cliente_revalidar(m.id, v_agora));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  begin
    -- Barco: o local pela OS e a situação dita depois do registro
    perform pg_temp.prepara(date '2027-06-01');
    update public.agenda_config set cliente_aprovacao_dias = 3 where id;
    perform pg_temp.passo();
    m := pg_temp.m('OS-J12');
    update public.os_planejamento set bem_situacao = 'agua', bem_situacao_fonte = 'dono', bem_situacao_em = v_agora where service_order_id = pg_temp.os('OS-J12');
    v_res := pg_temp.ok(v_res, 'K6m o barco com a situação dita depois: desatualizada', public._agenda_cliente_revalidar(m.id, v_agora) = 'desatualizada', null);
    -- O sim do dono depois disso não manda: a recusa vem pelo enfileirar
    r := public._agenda_cliente_decidir(m.pergunta_id, 1::smallint, pg_temp.adm(), 'whatsapp', 'manda', v_agora);
    m := pg_temp.m('OS-J12');
    v_res := pg_temp.ok(v_res, 'K6n o sim do dono depois disso não manda: recusada, nada na fila', m.estado = 'recusada' and m.recusa_motivo = 'desatualizada' and pg_temp.fila(m.id) is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- Na porta do worker: a linha na fila, a OS entregue antes de sair
    perform pg_temp.prepara(date '2027-06-01');
    perform pg_temp.passo();
    m := pg_temp.m('OS-J11');
    set local agenda.porta = 'on';
    update public.service_orders set check_out_at = pg_temp.em(date '2027-07-16', '16:30'), delivered_at = pg_temp.em(date '2027-07-16', '16:30') where id = pg_temp.os('OS-J11');
    set local agenda.porta = 'off';
    r := public.agenda_cliente_pode_sair((pg_temp.fila(m.id)).id, pg_temp.em(date '2027-07-16', '16:40'));
    v_res := pg_temp.ok(v_res, 'K6o o worker também não manda: a 3ª trava relê a OS', not (r ->> 'pode')::boolean and r ->> 'motivo' = 'status', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.prepara(date '2027-06-01');
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate, aprovacao, estado, dedupe_key, criada_em)
    values (pg_temp.cli('OS-J11'), pg_temp.os('OS-J11'), 'andamento', 'rodada', 'ligado', 'mensagem de teste', '{}', v_agora, v_agora + interval '1 hour', 'livre', 'registrada',
            'agenda-cliente:teste:k6q', v_agora - interval '1 hour');
    update public.service_orders set status = 'in_progress' where id = pg_temp.os('OS-J11');
    v_res := pg_temp.ok(v_res, 'K6q os sinais do M11 não valem para os outros tipos: o andamento de uma OS em execução segue (recusa só pelo texto de teste)', public._agenda_cliente_revalidar(
      (select x.id from public.agenda_cliente_mensagens x where x.dedupe_key = 'agenda-cliente:teste:k6q'), v_agora) = 'desatualizada',
      public._agenda_cliente_revalidar((select x.id from public.agenda_cliente_mensagens x where x.dedupe_key = 'agenda-cliente:teste:k6q'), v_agora));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$k6$;

-- ── K7. As cópias ─────────────────────────────────────────────────────────────────────────────────
do $k7$
declare
  v_res  jsonb := '[]'::jsonb;
  c      record;
  v_mig  text;
  v_org  text;
  v_txt  text;
  v_viva text;
  v_dif  text;
begin
  if coalesce(current_setting('agenda_teste.mig_cliente_fase7d', true), '') = '' or coalesce(current_setting('agenda_teste.mig_acabamento_fase6', true), '') = '' then
    insert into _resultado values ('K7 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_mig := current_setting('agenda_teste.mig_cliente_fase7d');
  for c in select * from (values
      ('_agenda_cliente_texto', current_setting('agenda_teste.mig_acabamento_fase6')),
      ('_agenda_cliente_tipo_texto', current_setting('agenda_teste.mig_envio_fase5')),
      ('_agenda_cliente_o_que', current_setting('agenda_teste.mig_envio_fase5')),
      ('_agenda_cliente_revalidar', current_setting('agenda_teste.mig_correcao_rodada_fase5')),
      ('agenda_cliente_vigiar', current_setting('agenda_teste.mig_rodada_fase5')),
      ('agenda_resposta_do_cliente', current_setting('agenda_teste.mig_acabamento_fase6')),
      ('_agenda_cliente_teria_feito', current_setting('agenda_teste.mig_acabamento_fase6')),
      ('_agenda_ver_clientes', current_setting('agenda_teste.mig_acabamento_fase6')),
      ('_agenda_local_restaurar', current_setting('agenda_teste.mig_combinar_fase7d'))) t(nome, origem) loop
    v_org := pg_temp.corpo(c.origem, c.nome);
    v_txt := pg_temp.corpo(v_mig, c.nome);
    select replace(p.prosrc, E'\r\n', E'\n') into v_viva from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = c.nome;
    if v_org = '' or v_txt = '' or pg_temp.sem_7d(v_txt) <> pg_temp.sem_7d(v_org) or pg_temp.sem_7d(v_viva) <> pg_temp.sem_7d(v_org) or v_txt = v_org then
      v_dif := concat_ws('; ', v_dif, c.nome);
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'K7a as 9 recriadas por bloco só mudam nos blocos "-- FASE 7d:", vivas e na migration', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'K7b _agenda_local_decidir: fora do bloco da local, só a linha do tipo',
    replace(pg_temp.sem_7d(pg_temp.corpo(v_mig, '_agenda_local_decidir')), $$not in ('combinar', 'acesso', 'local')$$, $$not in ('combinar', 'acesso')$$)
    = pg_temp.sem_7d(pg_temp.corpo(current_setting('agenda_teste.mig_combinar_fase7d'), '_agenda_local_decidir')), null);
  v_res := pg_temp.ok(v_res, 'K7c agenda_decisoes_abertas: só a linha do where', replace(pg_temp.corpo(v_mig, 'agenda_decisoes_abertas'), $$q.tipo in ('combinar', 'local')$$, $$q.tipo = 'combinar'$$)
    = pg_temp.corpo(current_setting('agenda_teste.mig_combinar_fase7d'), 'agenda_decisoes_abertas'), null);
  v_res := pg_temp.ok(v_res, 'K7d a migration não recria o registrar, o enfileirar, a fila, o dinheiro nem as 3 que a sessão do retorno chama',
    pg_temp.corpo(v_mig, '_agenda_cliente_registrar') = '' and pg_temp.corpo(v_mig, '_agenda_cliente_enfileirar') = '' and pg_temp.corpo(v_mig, '_agenda_fila_do_cliente') = ''
    and pg_temp.corpo(v_mig, 'handle_quote_deposit_payment') = '' and pg_temp.corpo(v_mig, '_agenda_cliente_dia') = '' and pg_temp.corpo(v_mig, '_agenda_nome_curto') = ''
    and pg_temp.corpo(v_mig, '_agenda_chave_telefone') = '', null);
  v_res := pg_temp.ok(v_res, 'K7e a migration não escreve dado: nada de update, insert fora de função, e cliente_tipos_ligados não recebe onde_fica',
    v_mig !~* '(^|\n)\s*(update|insert into|delete from)\s+public\.agenda_config' and v_mig !~* 'set\s+cliente_tipos_ligados', null);
  v_res := pg_temp.ok(v_res, 'K7f R6.3-5: _agenda_cliente_anotar_onde não chama anotar_acesso nem grava acesso_ok_em',
    (select p.prosrc from pg_proc p where p.oid = 'public._agenda_cliente_anotar_onde(uuid, uuid, text, date, timestamp with time zone)'::regprocedure) !~ '_agenda_cliente_anotar_acesso\('
    and (select p.prosrc from pg_proc p where p.oid = 'public._agenda_cliente_anotar_onde(uuid, uuid, text, date, timestamp with time zone)'::regprocedure) !~ 'set\s+acesso_ok_em', null);
  v_res := pg_temp.ok(v_res, 'K7g a lista de produção segue sem onde_fica na linha da bancada, e o CHECK aceita', not exists (select 1 from public.agenda_config x where x.id and 'onde_fica' = any (x.cliente_tipos_ligados)), null);
  perform pg_temp.gravar(v_res);
end
$k7$;

-- ── K8. O bloqueio do retorno, de verdade (R6.0) ──────────────────────────────────────────────────
do $k8$
declare
  v_res  jsonb := '[]'::jsonb;
  r      jsonb;
  m      public.agenda_cliente_mensagens;
  q      public.whatsapp_send_queue;
begin
  if not pg_temp.carregada() or coalesce(current_setting('agenda_teste.mig_retorno_f0a', true), '') = '' then
    insert into _resultado values ('K8 o bloqueio do retorno', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.mig_retorno_f0a');
    v_res := pg_temp.ok(v_res, 'K8a a migration do retorno roda aqui, inteira, e o gatilho está na fila, antes do de idempotência e depois do da agenda',
      (select string_agg(t.tgname, ',' order by t.tgname) from pg_trigger t where t.tgrelid = 'public.whatsapp_send_queue'::regclass and not t.tgisinternal and t.tgname ~ 'cliente_final|fila_do_cliente$')
      = 'trg_agenda_fila_do_cliente,trg_whatsapp_send_queue_cliente_final', null);
    -- O caminho inteiro: o passo → o registrar → o enfileirar → a fila, com a fonte exata
    perform pg_temp.prepara(date '2027-06-01');
    r := pg_temp.passo();
    m := pg_temp.m('OS-J11');
    q := pg_temp.fila(m.id);
    v_res := pg_temp.ok(v_res, 'K8b o M11 de um cliente comum passa pelo gatilho, com source = agenda-cliente, a única fonte agenda-% que ele olha', q.source = 'agenda-cliente' and q.status = 'pending' and m.estado = 'enfileirada', q::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute current_setting('agenda_teste.mig_retorno_f0a');
    perform pg_temp.prepara(date '2027-06-01');
    update public.clients set generico = true where id = pg_temp.cli('OS-J11');
    r := pg_temp.passo();
    m := pg_temp.m('OS-J11');
    v_res := pg_temp.ok(v_res, 'K8c o "Cliente Final": o gatilho recusa, a mensagem fica recusada sem_telefone, nada na fila, e a outra OS sai',
      m.estado = 'recusada' and m.recusa_motivo = 'sem_telefone' and pg_temp.fila(m.id) is null and (pg_temp.m('OS-J12')).estado = 'enfileirada' and (r ->> 'erros')::int = 0, m::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- O contraste: sem o gatilho, o mesmo cliente passa. É ele quem recusa
    perform pg_temp.prepara(date '2027-06-01');
    update public.clients set generico = true where id = pg_temp.cli('OS-J11');
    r := pg_temp.passo();
    m := pg_temp.m('OS-J11');
    v_res := pg_temp.ok(v_res, 'K8d o contraste: sem o gatilho, o "Cliente Final" iria para a fila', m.estado = 'enfileirada' and (pg_temp.fila(m.id)).source = 'agenda-cliente', m::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute current_setting('agenda_teste.mig_retorno_f0a');
    perform pg_temp.prepara(date '2027-06-01');
    insert into public.whatsapp_blocked_numbers (phone_normalized, reason) values (pg_temp.fone('OS-J11'), 'teste');
    r := pg_temp.passo();
    m := pg_temp.m('OS-J11');
    v_res := pg_temp.ok(v_res, 'K8e o número bloqueado: a agenda recusa antes da fila (opt_out), e o gatilho concorda', m.recusa_motivo = 'opt_out' and pg_temp.fila(m.id) is null and public.canal_bloqueado(pg_temp.fone('OS-J11')) = 'bloqueado', m::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute current_setting('agenda_teste.mig_retorno_f0a');
    perform pg_temp.prepara(date '2027-06-01');
    update public.agenda_config set cliente_aprovacao_dias = 3 where id;
    update public.clients set generico = true where id = pg_temp.cli('OS-J11');
    perform pg_temp.passo();
    m := pg_temp.m('OS-J11');
    r := public._agenda_cliente_decidir(m.pergunta_id, 1::smallint, pg_temp.adm(), 'whatsapp', 'manda', pg_temp.em(date '2027-07-16', '16:30'));
    m := pg_temp.m('OS-J11');
    v_res := pg_temp.ok(v_res, 'K8f nem com o sim do dono: o gatilho recusa o que passa pelo enfileirar', m.estado = 'recusada' and m.recusa_motivo = 'sem_telefone' and pg_temp.fila(m.id) is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K8g pelo texto: só _agenda_cliente_enfileirar grava a fila do cliente, e com a fonte literal',
    (select string_agg(p.proname, ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prosrc ~ 'insert into public\.whatsapp_send_queue' and p.prosrc ~ $$'agenda-cliente', m\.id$$) = '_agenda_cliente_enfileirar'
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname in ('_agenda_cliente_onde_fica', '_agenda_cliente_anotar_onde', '_agenda_local_decidir') and p.prosrc ~ 'whatsapp_send_queue'), null);
  perform pg_temp.gravar(v_res);
end
$k8$;

-- ── K9. O peso (R6.8-7) ───────────────────────────────────────────────────────────────────────────
do $k9$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-16';
  v_ag  timestamptz := pg_temp.em(date '2027-07-16', '16:20');
  v     jsonb;
  v_n   bigint;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K9 o peso', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    create temp sequence k9_chamadas;
    create or replace function public._agenda_local_resolvido(p_os uuid, p_hoje date) returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $x$
    begin perform nextval('k9_chamadas'); raise exception 'K9: _agenda_local_resolvido chamada'; end $x$;
    create or replace function public._agenda_local_mascara(p_os uuid, p_d_ini date, p_d_fim date, p_hoje date, p_local jsonb default null) returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $x$
    begin perform nextval('k9_chamadas'); raise exception 'K9: _agenda_local_mascara chamada'; end $x$;
    create or replace function public._agenda_viagem_da_os(p_os uuid, p_hoje date, p_local jsonb default null) returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $x$
    begin perform nextval('k9_chamadas'); raise exception 'K9: _agenda_viagem_da_os chamada'; end $x$;
    create or replace function public._agenda_estado_do_bem(p_os uuid, p_hoje date) returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $x$
    begin perform nextval('k9_chamadas'); raise exception 'K9: _agenda_estado_do_bem chamada'; end $x$;
    -- Hoje na produção depois do dado: onde_fica_desde gravada, e as OS da carteira aprovadas antes dela
    perform pg_temp.prepara(date '2027-07-17', false);
    v := public.agenda_cliente_vigiar(v_h, v_ag);
    select last_value - 1 + case when is_called then 1 else 0 end into v_n from k9_chamadas;
    v_res := pg_temp.ok(v_res, 'K9a onde_fica_desde gravada e nenhuma OS depois dela: a rodada do cliente não chama nenhuma das 4 leituras', v_n = 0 and (v #>> '{contagens,onde_fica,erros}')::int = 0, format('chamadas %s', v_n));
    -- Com a data nula
    perform pg_temp.prepara(null, false);
    v := public.agenda_cliente_vigiar(v_h, v_ag);
    select last_value - 1 + case when is_called then 1 else 0 end into v_n from k9_chamadas;
    v_res := pg_temp.ok(v_res, 'K9b sem a data: nenhuma chamada', v_n = 0, format('chamadas %s', v_n));
    -- Com o freio e candidatas
    perform pg_temp.prepara(date '2027-06-01', false);
    update public.agenda_config set gestor_so_propor = true where id;
    v := public.agenda_cliente_vigiar(v_h, v_ag);
    select last_value - 1 + case when is_called then 1 else 0 end into v_n from k9_chamadas;
    v_res := pg_temp.ok(v_res, 'K9c com o freio e 2 candidatas: nenhuma chamada', v_n = 0 and v #>> '{contagens,onde_fica,pulado}' = 'gestor_so_propor', format('chamadas %s', v_n));
    -- Sem a data e com o freio, nem a carteira é lida
    create or replace function public.os_carteira(p_hoje date default public._hoje_brt())
     returns table (service_order_id uuid, numero text, status text, quote_status text, eh_orcamento boolean, cliente text, cliente_curto text, unidade text, valor numeric,
                    aprovada_em date, sinal_previsto numeric, sinal_pago numeric, sinal_pendente numeric, agendada_de date, agendada_ate date)
     language plpgsql stable set search_path to 'public', 'pg_temp' as $x$
    begin perform nextval('k9_chamadas'); raise exception 'K9: os_carteira chamada'; end $x$;
    select last_value - 1 + case when is_called then 1 else 0 end into v_n from k9_chamadas;
    perform pg_temp.prepara(null, false);
    v := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K9e sem a data, o passo nem lê a carteira', v = '{"erros": 0, "puladas": {}, "registradas": 0}'::jsonb, v::text);
    perform pg_temp.prepara(date '2027-06-01', false);
    update public.agenda_config set gestor_so_propor = true where id;
    v := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'K9f com o freio, o passo nem lê a carteira', v = '{"pulado": "gestor_so_propor"}'::jsonb, v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    drop sequence if exists k9_chamadas;
    create temp sequence k9_chamadas;
    create or replace function public._agenda_local_resolvido(p_os uuid, p_hoje date) returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $x$
    begin perform nextval('k9_chamadas'); raise exception 'K9: _agenda_local_resolvido chamada'; end $x$;
    -- O contraste: com candidata de verdade, a versão que lança é chamada, e a OS vai ao log, sem derrubar a rodada
    perform pg_temp.prepara(date '2027-06-01', false);
    v := public.agenda_cliente_vigiar(v_h, v_ag);
    select last_value - 1 + case when is_called then 1 else 0 end into v_n from k9_chamadas;
    v_res := pg_temp.ok(v_res, 'K9d o contraste: com as candidatas, a leitura é chamada (senão a prova não prova nada), e a rodada segue', v_n >= 2 and (v #>> '{contagens,onde_fica,erros}')::int >= 2 and (v ->> 'erros')::int = 0, v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$k9$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
