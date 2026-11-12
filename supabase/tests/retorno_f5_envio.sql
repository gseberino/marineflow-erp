-- Retorno F5 (P2): o envio do orçamento e a validade contada do envio. Os dois gatilhos do funil (o AFTER dispara com só
-- quote_status no SET), a validade do envio (prévia, gravar, o dia que virou, já enviado, vencida, desligada, funil, cargo),
-- _orcamento_ultimo_dia, o registro de todo envio pelo sistema e a detecção do PDF mandado do aparelho (ORC- e ORÇ-, hora do
-- eco, marca d'água, parceiro de fora). Roda só pela bancada (grupo 8, F5_ONDA=2, F5_TESTES=retorno_f5_envio). Termina em
-- ROLLBACK, e o bloco se desfaz sozinho. Só confere as próprias linhas sintéticas: telefones inventados 55479000150xx (a chave
-- sai do telefone: 000150xx), nomes inventados (Ana, João, Pedro), números de documento inventados (ORÇ-991xx), usuários de
-- teste com e-mail @teste.invalid. Nenhuma mensagem real é lida; os ecos são inventados e não têm corpo. Relógio: ter
-- 12/01/2027 10:00 (Brasília). A parte do vigia do 8b (o acompanhamento que nasce e para na mesma rodada) mora na P3.2.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f5e_cli(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

create or replace function pg_temp.f5e_orc(p_cliente uuid, p_numero text, p_status text default 'draft', p_quote text default 'draft',
                                           p_criado timestamptz default '2027-01-10 10:00-03', p_dias integer default 7) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, quote_validity_days)
  values (p_numero, p_cliente, v_v, p_status, p_quote, 'repair', p_criado, p_criado, 100, p_dias)
  returning id into v_id;
  return v_id;
end $f$;

-- O documento que saiu do aparelho do dono (eco: data, sem via). p_hora_real nula: a hora é a de gravação.
create or replace function pg_temp.f5e_eco(p_fone text, p_arquivo text, p_hora_real timestamptz, p_gravada timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, raw_payload, occurred_at, hora_real)
  values ('outbound', p_fone, 'document', null, 'teste-f5-envio-' || md5(p_fone || p_arquivo || p_gravada::text || random()::text),
          jsonb_build_object('data', jsonb_build_object('source', 'unknown', 'message',
                                                        jsonb_build_object('documentMessage', jsonb_build_object('fileName', p_arquivo)))),
          p_gravada, p_hora_real)
  returning id
$f$;

create or replace function pg_temp.f5e_n(p_os uuid) returns integer
language sql as $f$
  select count(*)::integer from public.orcamento_envios e where e.service_order_id = p_os
$f$;

-- Roda p_sql (um select de uma coluna) como p_papel, com o login p_uid; devolve o valor ou 'erro SQLSTATE'.
create or replace function pg_temp.f5e_como(p_papel text, p_uid uuid, p_sql text) returns text
language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

do $envio$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter
  c_fone_ana constant text := '5547900015001';
  c_chave_ana constant text := '00015001';
  c_fone_parceiro constant text := '5547900015090';
  c_tec constant uuid := 'b1600000-0000-4000-8000-0000000015e1';
  c_vend constant uuid := 'b1600000-0000-4000-8000-0000000015e2';
  c_adm constant uuid := 'b1600000-0000-4000-8000-0000000015e3';
  c_novas constant text[] := array['_orcamento_quote_status_antes', '_orcamento_envio_depois', '_orcamento_ultimo_dia',
                                   'orcamento_validade_do_envio', 'orcamento_registrar_envio', 'orcamento_detectar_envio'];
  -- Funções do orçamento abertas a authenticated de propósito: orcamento_validade_do_envio (confere o cargo) e
  -- orcamentos_para_agrupar (anterior à F5). Nenhuma aberta a anon.
  c_abertas constant text[] := array['orcamento_validade_do_envio', 'orcamentos_para_agrupar'];
  v_ana uuid; v_joao uuid; v_pedro uuid;
  v_p uuid; v_carla uuid;
  v_r1 uuid; v_r2 uuid; v_r3 uuid; v_r4 uuid; v_r5 uuid; v_r6 uuid; v_r7 uuid; v_r8 uuid; v_r8b uuid; v_r9 uuid; v_r10 uuid;
  v_r11 uuid; v_r12 uuid; v_r13 uuid; v_r14 uuid; v_r15 uuid; v_r16 uuid; v_r17 uuid; v_r18 uuid; v_r19 uuid; v_r20 uuid;
  v_os uuid; v_u uuid;
  v_m uuid; v_m10 uuid; v_m10b uuid; v_m8 uuid; v_m8b uuid; v_m_os uuid; v_m_sem uuid; v_m14 uuid; v_m15 uuid;
  v_ms uuid[] := '{}';
  v_so record;
  v_e public.orcamento_envios;
  v_r jsonb;
  v text;
  v_hoje_real date := (now() at time zone 'America/Sao_Paulo')::date;
  v_rec record;
  v_n integer;
  v_n_fun integer := 0;
begin
  begin
  update public.retorno_config
     set validade_envio_ligada = false, envio_mao_modo = 'desligado', orcamento_envio_ate = null, validade_orcamento_dias = 7
   where id;
  v_ana := pg_temp.f5e_cli('Ana Envio F5 Teste', c_fone_ana);
  v_joao := pg_temp.f5e_cli('João Envio F5 Teste', '5547900015002');
  v_pedro := pg_temp.f5e_cli('Pedro Envio F5 Teste', '5547900015003');

  -- ── 10. A 1ª chamada com a marca nula só avança a marca; desligada também; ao ligar, nada do passado vira envio ──
  update public.retorno_config set envio_mao_modo = 'registrar' where id;
  v_r10 := pg_temp.f5e_orc(v_ana, 'ORÇ-99110');
  v_m10 := pg_temp.f5e_eco(c_fone_ana, 'ORC-99110.pdf', c_t - interval '3 hours', c_t - interval '3 hours');
  v_r := public.orcamento_detectar_envio(c_t - interval '2 hours');
  if (v_r ->> 'registrados')::integer is distinct from 0
     or (select c.orcamento_envio_ate from public.retorno_config c where c.id) is distinct from c_t - interval '2 hours' then
    raise exception '10a: a 1ª chamada gravou ou não avançou a marca (%)', v_r;
  end if;
  perform public.orcamento_detectar_envio(c_t - interval '90 minutes');
  if pg_temp.f5e_n(v_r10) is distinct from 0 then
    raise exception '10b: o PDF de antes da marca virou envio';
  end if;
  update public.retorno_config set envio_mao_modo = 'desligado' where id;
  v_m10b := pg_temp.f5e_eco(c_fone_ana, 'ORC-99110.pdf', c_t - interval '80 minutes', c_t - interval '80 minutes');
  v_r := public.orcamento_detectar_envio(c_t - interval '70 minutes');
  if v_r ->> 'modo' is distinct from 'desligado' or pg_temp.f5e_n(v_r10) is distinct from 0
     or (select c.orcamento_envio_ate from public.retorno_config c where c.id) is distinct from c_t - interval '70 minutes' then
    raise exception '10c: desligada gravou ou não avançou a marca (%)', v_r;
  end if;
  update public.retorno_config set envio_mao_modo = 'registrar' where id;
  perform public.orcamento_detectar_envio(c_t - interval '60 minutes');
  if pg_temp.f5e_n(v_r10) is distinct from 0 then
    raise exception '10d: ao ligar, o PDF de quando estava desligada virou envio';
  end if;

  -- ── 8. Detecção: registrar grava o envio e não mexe na ordem; marcar passa a "enviado" com a hora do eco ──
  v_r8 := pg_temp.f5e_orc(v_ana, 'ORÇ-99108');
  v_m8 := pg_temp.f5e_eco(c_fone_ana, 'ORC-99108_Ana_Ducato.pdf', c_t - interval '30 minutes', c_t - interval '30 minutes');
  perform public.orcamento_detectar_envio(c_t - interval '20 minutes');
  select * into v_e from public.orcamento_envios e where e.whatsapp_message_id = v_m8;
  if not found or v_e.service_order_id is distinct from v_r8 or v_e.via is distinct from 'aparelho' or v_e.ao_cliente is not true
     or v_e.chave is distinct from c_chave_ana or v_e.em is distinct from c_t - interval '30 minutes' or v_e.marcou is not false
     or v_e.client_id is distinct from v_ana then
    raise exception '8a: registrar: o envio do aparelho (%)', v_e;
  end if;
  select so.quote_status, so.orcamento_enviado_em into v_so from public.service_orders so where so.id = v_r8;
  if v_so.quote_status is distinct from 'draft' or v_so.orcamento_enviado_em is not null then
    raise exception '8b: registrar mudou a ordem (%)', v_so;
  end if;
  update public.retorno_config set envio_mao_modo = 'marcar' where id;
  v_r8b := pg_temp.f5e_orc(v_ana, 'ORÇ-99118');
  v_m8b := pg_temp.f5e_eco(c_fone_ana, 'ORC-99118_Ana.pdf', c_t - interval '15 minutes', c_t - interval '14 minutes');
  v_r := public.orcamento_detectar_envio(c_t - interval '10 minutes');
  select so.quote_status, so.orcamento_enviado_em, so.orcamento_enviado_via, so.orcamento_enviado_chave into v_so
    from public.service_orders so where so.id = v_r8b;
  if v_so.quote_status is distinct from 'sent' or v_so.orcamento_enviado_via is distinct from 'aparelho'
     or v_so.orcamento_enviado_chave is distinct from c_chave_ana
     or v_so.orcamento_enviado_em is distinct from c_t - interval '15 minutes' then
    raise exception '8c: marcar: a ordem (%; %)', v_so, v_r;
  end if;
  if (v_r ->> 'marcados')::integer is distinct from 1 then
    raise exception '8d: marcados (%)', v_r;
  end if;
  if pg_temp.f5e_n(v_r8b) is distinct from 1
     or not exists (select 1 from public.orcamento_envios e where e.service_order_id = v_r8b and e.whatsapp_message_id = v_m8b
                                                            and e.via = 'aparelho' and e.marcou) then
    raise exception '8e: marcar: esperava 1 linha (a do aparelho, marcou), achei %', pg_temp.f5e_n(v_r8b);
  end if;
  if not exists (select 1 from public.audit_log a where a.table_name = 'service_orders' and a.record_id = v_r8b
                                                 and a.changed_by = 'retorno-f5' and a.new_value ->> 'quote_status' = 'sent') then
    raise exception '8f: marcar sem audit_log';
  end if;
  -- O nome do arquivo não aparece em lugar nenhum: nem nas linhas de envio, nem no audit_log.
  if exists (select 1 from public.orcamento_envios e where e.service_order_id in (v_r8, v_r8b)
                                                       and row_to_json(e)::text ~* '(ana|ducato|\.pdf)')
     or exists (select 1 from public.audit_log a where a.record_id = v_r8b and a.changed_by = 'retorno-f5'
                                               and concat_ws(' ', a.previous_value::text, a.new_value::text, a.reason) ~* '(ana|ducato|\.pdf)') then
    raise exception '8g: o nome do arquivo foi gravado';
  end if;

  -- ── 8a. O nome com cedilha (o "Baixar" da tela sai com ORÇ-); OS- não é orçamento; sem hífen não tem número ──
  update public.retorno_config set envio_mao_modo = 'registrar' where id;
  v_r9 := pg_temp.f5e_orc(v_ana, 'ORÇ-99109');
  v_ms := array[pg_temp.f5e_eco(c_fone_ana, 'ORÇ-99109_Ana.pdf', c_t - interval '9 minutes', c_t - interval '9 minutes'),
                pg_temp.f5e_eco(c_fone_ana, 'orç-99109.pdf', c_t - interval '8 minutes', c_t - interval '8 minutes'),
                pg_temp.f5e_eco(c_fone_ana, 'Orcamento-ORÇ-99109.pdf', c_t - interval '7 minutes', c_t - interval '7 minutes')];
  v_m_os := pg_temp.f5e_eco(c_fone_ana, 'OS-99109.pdf', c_t - interval '6 minutes', c_t - interval '6 minutes');
  v_m_sem := pg_temp.f5e_eco(c_fone_ana, 'ORC99109.pdf', c_t - interval '5 minutes', c_t - interval '5 minutes');
  v_r := public.orcamento_detectar_envio(c_t - interval '4 minutes');
  foreach v_m in array v_ms loop
    if not exists (select 1 from public.orcamento_envios e where e.whatsapp_message_id = v_m and e.service_order_id = v_r9) then
      raise exception '8h: um nome com ORÇ- não achou o ORÇ-99109 (%)', v_r;
    end if;
  end loop;
  if exists (select 1 from public.orcamento_envios e where e.whatsapp_message_id in (v_m_os, v_m_sem)) then
    raise exception '8i: OS- ou o nome sem hífen virou envio';
  end if;
  if (coalesce((v_r ->> 'sem_numero')::integer, 0) >= 2) is not true then
    raise exception '8j: sem_numero não contou OS- e sem hífen (%)', v_r;
  end if;

  -- ── 9. Destino de parceiro confirmado e cliente parceiro: nada é gravado (detecção e registro) ──
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Envio F5 Teste', 'REFQ', 'revenda') returning id into v_p;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_documento)
    values (v_carla, c_fone_parceiro, '00015090', '47', 'confirmado', c_t - interval '30 days', true);
  update public.retorno_config set clientes_parceiros = clientes_parceiros || array[v_pedro] where id;
  v_r14 := pg_temp.f5e_orc(v_ana, 'ORÇ-99114');
  v_r15 := pg_temp.f5e_orc(v_pedro, 'ORÇ-99115');
  v_m14 := pg_temp.f5e_eco(c_fone_parceiro, 'ORC-99114.pdf', c_t - interval '3 minutes', c_t - interval '3 minutes');
  v_m15 := pg_temp.f5e_eco('5547900015003', 'ORC-99115.pdf', c_t - interval '2 minutes', c_t - interval '2 minutes');
  perform public.orcamento_detectar_envio(c_t - interval '1 minute');
  if pg_temp.f5e_n(v_r14) is distinct from 0 or pg_temp.f5e_n(v_r15) is distinct from 0 then
    raise exception '9a: o PDF ao parceiro ou do cliente parceiro virou envio';
  end if;
  v_r := public.orcamento_registrar_envio(v_r14, 'assistente', '00015090', false, c_t);
  if v_r ->> 'ignorado' is distinct from 'parceiro' or pg_temp.f5e_n(v_r14) is distinct from 0 then
    raise exception '9b: registro ao número do parceiro (%)', v_r;
  end if;
  v_r := public.orcamento_registrar_envio(v_r15, 'tela', '00015003', true, c_t);
  if v_r ->> 'ignorado' is distinct from 'cliente_parceiro' or pg_temp.f5e_n(v_r15) is distinct from 0 then
    raise exception '9c: registro do orçamento de cliente parceiro (%)', v_r;
  end if;

  -- ── 8b. A hora do eco, não a da detecção: o PDF das 14:00 detectado às 14:05; o das 21:30 só às 07:00 ──
  update public.retorno_config set envio_mao_modo = 'marcar' where id;
  v_r11 := pg_temp.f5e_orc(v_ana, 'ORÇ-99111');
  perform pg_temp.f5e_eco(c_fone_ana, 'ORÇ-99111.pdf', c_t + interval '4 hours', c_t + interval '4 hours 30 seconds');
  perform public.orcamento_detectar_envio(c_t + interval '4 hours 5 minutes');
  if (select so.orcamento_enviado_em from public.service_orders so where so.id = v_r11) is distinct from c_t + interval '4 hours' then
    raise exception '8k: o PDF das 14:00 detectado às 14:05 não ficou com 14:00';
  end if;
  v_r12 := pg_temp.f5e_orc(v_ana, 'ORÇ-99112');
  perform pg_temp.f5e_eco(c_fone_ana, 'ORÇ-99112.pdf', c_t + interval '11 hours 30 minutes', c_t + interval '11 hours 30 minutes');
  perform public.orcamento_detectar_envio(c_t + interval '21 hours');
  if (select so.orcamento_enviado_em from public.service_orders so where so.id = v_r12) is distinct from c_t + interval '11 hours 30 minutes'
     or (select e.em from public.orcamento_envios e where e.service_order_id = v_r12) is distinct from c_t + interval '11 hours 30 minutes' then
    raise exception '8l: o PDF das 21:30 detectado às 07:00 não ficou com 21:30';
  end if;
  -- Sem a hora real no eco, vale a de gravação.
  v_r13 := pg_temp.f5e_orc(v_ana, 'ORÇ-99113');
  perform pg_temp.f5e_eco(c_fone_ana, 'ORÇ-99113.pdf', null, c_t + interval '21 hours 10 minutes');
  perform public.orcamento_detectar_envio(c_t + interval '21 hours 20 minutes');
  if (select so.orcamento_enviado_em from public.service_orders so where so.id = v_r13) is distinct from c_t + interval '21 hours 10 minutes' then
    raise exception '8m: sem hora real, a hora do envio não é a de gravação';
  end if;
  update public.retorno_config set envio_mao_modo = 'desligado' where id;

  -- ── 1. Marcação à mão: só quote_status no SET; o AFTER dispara e grava 1 envio 'marcado', sem chave ──
  v_r1 := pg_temp.f5e_orc(v_ana, 'ORÇ-99101');
  update public.service_orders set quote_status = 'sent' where id = v_r1;
  select so.orcamento_enviado_em, so.orcamento_enviado_via, so.orcamento_enviado_chave into v_so from public.service_orders so where so.id = v_r1;
  if v_so.orcamento_enviado_em is distinct from now() or v_so.orcamento_enviado_via is distinct from 'marcado'
     or v_so.orcamento_enviado_chave is not null then
    raise exception '1a: marcação à mão (%)', v_so;
  end if;
  select * into v_e from public.orcamento_envios e where e.service_order_id = v_r1;
  if pg_temp.f5e_n(v_r1) is distinct from 1 or v_e.via is distinct from 'marcado' or v_e.chave is not null or v_e.ao_cliente is not false
     or v_e.marcou is not true or v_e.em is distinct from now() or v_e.client_id is distinct from v_ana then
    raise exception '1b: a linha da marcação à mão (% linhas: %)', pg_temp.f5e_n(v_r1), v_e;
  end if;

  -- ── 1b. Só a hora e a via 'historico' (como a migration de dado): o AFTER dispara e não grava ──
  v_r2 := pg_temp.f5e_orc(v_ana, 'ORÇ-99102');
  update public.service_orders set orcamento_enviado_em = c_t - interval '1 day', orcamento_enviado_via = 'historico' where id = v_r2;
  if pg_temp.f5e_n(v_r2) is distinct from 0
     or (select so.quote_status from public.service_orders so where so.id = v_r2) is distinct from 'draft' then
    raise exception '1c: a via historico gravou envio ou mexeu no funil';
  end if;

  -- ── 2. Com a via e a chave no mesmo update (o whatsapp-send): nada no gatilho; quem grava é orcamento_registrar_envio ──
  v_r3 := pg_temp.f5e_orc(v_ana, 'ORÇ-99103');
  update public.service_orders
     set quote_status = 'sent', orcamento_enviado_em = c_t, orcamento_enviado_via = 'tela', orcamento_enviado_chave = c_chave_ana
   where id = v_r3;
  select so.orcamento_enviado_em, so.orcamento_enviado_via, so.orcamento_enviado_chave into v_so from public.service_orders so where so.id = v_r3;
  if v_so.orcamento_enviado_em is distinct from c_t or v_so.orcamento_enviado_via is distinct from 'tela'
     or v_so.orcamento_enviado_chave is distinct from c_chave_ana or pg_temp.f5e_n(v_r3) is distinct from 0 then
    raise exception '2a: envio pela tela (%; % linhas)', v_so, pg_temp.f5e_n(v_r3);
  end if;
  v_r := public.orcamento_registrar_envio(v_r3, 'tela', c_chave_ana, true, c_t);
  select * into v_e from public.orcamento_envios e where e.service_order_id = v_r3;
  if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'ao_cliente')::boolean is not true or v_r ->> 'id' is null
     or pg_temp.f5e_n(v_r3) is distinct from 1 or v_e.via is distinct from 'tela' or v_e.ao_cliente is not true
     or v_e.marcou is not true or v_e.em is distinct from c_t or v_e.chave is distinct from c_chave_ana then
    raise exception '2b: orcamento_registrar_envio (%; %)', v_r, v_e;
  end if;
  -- O telefone inteiro no lugar da chave dá a mesma chave.
  v_r := public.orcamento_registrar_envio(v_r3, 'assistente', c_fone_ana, false, c_t + interval '1 minute');
  if (v_r ->> 'ao_cliente')::boolean is not true
     or not exists (select 1 from public.orcamento_envios e where e.service_order_id = v_r3 and e.via = 'assistente' and e.chave = c_chave_ana) then
    raise exception '2c: o telefone inteiro não virou a chave (%)', v_r;
  end if;

  -- ── 3. A 2ª passagem a "enviado" não muda o 1º envio (hora, via e chave) ──
  update public.service_orders set quote_status = 'draft' where id = v_r3;
  update public.service_orders
     set quote_status = 'sent', orcamento_enviado_em = c_t + interval '2 days', orcamento_enviado_via = 'assistente',
         orcamento_enviado_chave = '00015099'
   where id = v_r3;
  select so.quote_status, so.orcamento_enviado_em, so.orcamento_enviado_via, so.orcamento_enviado_chave into v_so
    from public.service_orders so where so.id = v_r3;
  if v_so.quote_status is distinct from 'sent' or v_so.orcamento_enviado_em is distinct from c_t
     or v_so.orcamento_enviado_via is distinct from 'tela' or v_so.orcamento_enviado_chave is distinct from c_chave_ana then
    raise exception '3a: a 2ª passagem mudou o 1º envio (%)', v_so;
  end if;

  -- ── 4. A validade do envio, ligada: às 23:30 de ter 12/01 → ter 19/01, igual a _retorno_validade_do_envio ──
  update public.retorno_config set validade_envio_ligada = true where id;
  v_r4 := pg_temp.f5e_orc(v_ana, 'ORÇ-99104');
  v_r := public.orcamento_validade_do_envio(v_r4, '2027-01-12 23:30-03');
  if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'fixou')::boolean is not true or v_r ->> 'data' is distinct from '2027-01-19'
     or v_r ->> 'data' is distinct from public._retorno_validade_do_envio('2027-01-12 23:30-03')::text
     or (v_r ->> 'dias')::integer is distinct from 7 or v_r ? 'motivo' then
    raise exception '4a: validade do envio (%)', v_r;
  end if;
  if v_r ->> 'legenda' is distinct from 'Segue o ORÇ-99104, conforme solicitado. Ele vale até terça (19/01). Qualquer dúvida, estamos à disposição.'
     or v_r ->> 'linha' is distinct from 'Ele vale até terça (19/01).'
     or v_r -> 'contexto' -> 'os_permitidas' is distinct from '["ORÇ-99104"]'::jsonb
     or v_r -> 'contexto' ->> 'audiencia' is distinct from 'cliente' then
    raise exception '4b: legenda, linha ou contexto (%)', v_r;
  end if;
  select so.quote_validity_date, so.quote_validity_days into v_so from public.service_orders so where so.id = v_r4;
  if v_so.quote_validity_date is distinct from date '2027-01-19' or v_so.quote_validity_days is distinct from 7 then
    raise exception '4c: a data não foi gravada (%)', v_so;
  end if;

  -- ── 4b. Prévia: a mesma data, nada gravado ──
  v_r5 := pg_temp.f5e_orc(v_ana, 'ORÇ-99105', 'draft', 'draft', '2027-01-10 10:00-03', 3);
  v_r := public.orcamento_validade_do_envio(v_r5, '2027-01-12 23:30-03', false);
  if v_r ->> 'motivo' is distinct from 'previa' or (v_r ->> 'fixou')::boolean is not false or v_r ->> 'data' is distinct from '2027-01-19'
     or v_r ->> 'linha' is distinct from 'Ele vale até terça (19/01).' then
    raise exception '4d: prévia (%)', v_r;
  end if;
  select so.quote_validity_date, so.quote_validity_days into v_so from public.service_orders so where so.id = v_r5;
  if v_so.quote_validity_date is not null or v_so.quote_validity_days is distinct from 3 then
    raise exception '4e: a prévia gravou (%)', v_so;
  end if;

  -- ── 4c. O dia virou entre o que o dono leu e o envio: mudou, nada gravado; com a data certa, grava ──
  v_r := public.orcamento_validade_do_envio(v_r5, '2027-01-13 00:10-03', true, '2027-01-19');
  if v_r ->> 'motivo' is distinct from 'mudou' or v_r ->> 'data' is distinct from '2027-01-20' or v_r ->> 'antes' is distinct from '2027-01-19'
     or (v_r ->> 'fixou')::boolean is not false
     or (select so.quote_validity_date from public.service_orders so where so.id = v_r5) is not null then
    raise exception '4f: o dia virou (%)', v_r;
  end if;
  v_r := public.orcamento_validade_do_envio(v_r5, '2027-01-13 00:10-03', true, '2027-01-20');
  if (v_r ->> 'fixou')::boolean is not true
     or (select so.quote_validity_date from public.service_orders so where so.id = v_r5) is distinct from date '2027-01-20' then
    raise exception '4g: com a data esperada certa não gravou (%)', v_r;
  end if;

  -- ── 5. Depois do envio não renova (D13); com a data já passada, vencida e sem linha ──
  update public.service_orders
     set quote_status = 'sent', orcamento_enviado_em = '2027-01-13 09:00-03', orcamento_enviado_via = 'tela', orcamento_enviado_chave = c_chave_ana
   where id = v_r4;
  v_r := public.orcamento_validade_do_envio(v_r4, '2027-01-14 10:00-03');
  if v_r ->> 'motivo' is distinct from 'ja_enviado' or (v_r ->> 'fixou')::boolean is not false or v_r ->> 'data' is distinct from '2027-01-19'
     or v_r ->> 'linha' is distinct from 'Ele vale até terça (19/01).'
     or (select so.quote_validity_date from public.service_orders so where so.id = v_r4) is distinct from date '2027-01-19' then
    raise exception '5a: já enviado (%)', v_r;
  end if;
  v_r := public.orcamento_validade_do_envio(v_r4, '2027-01-20 10:00-03');
  if v_r ->> 'motivo' is distinct from 'vencida' or v_r ->> 'data' is distinct from '2027-01-19' or v_r ? 'legenda' or v_r ? 'linha' then
    raise exception '5b: vencida (%)', v_r;
  end if;
  -- A ordem que não é orçamento: a data de _orcamento_ultimo_dia (criada ontem, 15 dias), sem renovar.
  v_os := pg_temp.f5e_orc(v_ana, 'OS-99106', 'open', 'approved', c_t - interval '1 day', 15);
  v_r := public.orcamento_validade_do_envio(v_os, c_t);
  if v_r ->> 'motivo' is distinct from 'ja_enviado' or v_r ->> 'data' is distinct from '2027-01-26' then
    raise exception '5c: OS (%)', v_r;
  end if;

  -- ── 5d. _orcamento_ultimo_dia: data fixa; senão emissão (Brasília) + o 1º nível que serve (1 a 3650), reserva de 15 ──
  update public.app_settings set value = '5' where key = 'quote_validity_days';
  if not found then
    insert into public.app_settings (key, value) values ('quote_validity_days', '5');
  end if;
  v_u := pg_temp.f5e_orc(v_ana, 'ORÇ-99119', 'draft', 'draft', '2027-01-11 01:30+00', 3);   -- 10/01 22:30 em Brasília
  for v_rec in
    select x.dias, x.data_fixa, x.config, x.esperado
      from (values (3, null::date, '5', '2027-01-13'), (0, null, '5', '2027-01-15'), (4000, null, '5', '2027-01-15'),
                   (null, null, '5', '2027-01-15'), (0, null, 'abc', '2027-01-25'), (0, null, '2.9', '2027-01-12'),
                   (0, null, '0', '2027-01-25'), (3, '2027-02-01', '5', '2027-02-01')) as x(dias, data_fixa, config, esperado)
  loop
    update public.app_settings set value = v_rec.config where key = 'quote_validity_days';
    update public.service_orders set quote_validity_days = v_rec.dias, quote_validity_date = v_rec.data_fixa where id = v_u;
    if public._orcamento_ultimo_dia(v_u)::text is distinct from v_rec.esperado then
      raise exception '5d: dias %, data %, padrão %: deu %, esperava %', v_rec.dias, v_rec.data_fixa, v_rec.config,
        public._orcamento_ultimo_dia(v_u), v_rec.esperado;
    end if;
  end loop;
  if public._orcamento_ultimo_dia(gen_random_uuid()) is not null then
    raise exception '5e: ordem que não existe deu data';
  end if;

  -- ── 6. Desligada: nada muda; 6b. funil fora de rascunho/aguardando: nada muda ──
  update public.retorno_config set validade_envio_ligada = false where id;
  v_r6 := pg_temp.f5e_orc(v_ana, 'ORÇ-99116');
  v_r := public.orcamento_validade_do_envio(v_r6, c_t);
  if v_r is distinct from '{"ok": true, "fixou": false, "motivo": "desligada"}'::jsonb
     or (select so.quote_validity_date from public.service_orders so where so.id = v_r6) is not null then
    raise exception '6a: desligada (%)', v_r;
  end if;
  update public.retorno_config set validade_envio_ligada = true where id;
  v_r7 := pg_temp.f5e_orc(v_ana, 'ORÇ-99117', 'draft', 'approved');
  v_r := public.orcamento_validade_do_envio(v_r7, c_t);
  if v_r ->> 'motivo' is distinct from 'funil' or (v_r ->> 'fixou')::boolean is not false
     or (select so.quote_validity_date from public.service_orders so where so.id = v_r7) is not null then
    raise exception '6b: funil (%)', v_r;
  end if;

  -- ── 7. "Perdido" carimba a hora do motivo (a que veio fica); reabrir apaga os 4 campos ──
  v_r16 := pg_temp.f5e_orc(v_ana, 'ORÇ-99126');
  update public.service_orders set quote_status = 'rejected', motivo_perda = 'preco', motivo_perda_por = 'tela', motivo_perda_nota = 'caro'
   where id = v_r16;
  if (select so.motivo_perda_em from public.service_orders so where so.id = v_r16) is distinct from now() then
    raise exception '7a: rejected não carimbou motivo_perda_em';
  end if;
  v_r17 := pg_temp.f5e_orc(v_ana, 'ORÇ-99127');
  update public.service_orders set quote_status = 'rejected', motivo_perda = 'sumiu', motivo_perda_em = c_t - interval '1 hour' where id = v_r17;
  if (select so.motivo_perda_em from public.service_orders so where so.id = v_r17) is distinct from c_t - interval '1 hour' then
    raise exception '7b: o gatilho sobrescreveu a hora do motivo que veio';
  end if;
  update public.service_orders set quote_status = 'draft' where id = v_r16;
  select so.motivo_perda, so.motivo_perda_em, so.motivo_perda_por, so.motivo_perda_nota into v_so from public.service_orders so where so.id = v_r16;
  if v_so.motivo_perda is not null or v_so.motivo_perda_em is not null or v_so.motivo_perda_por is not null or v_so.motivo_perda_nota is not null then
    raise exception '7c: reabrir não apagou o motivo (%)', v_so;
  end if;

  -- ── 11. Quem chama: anon não executa; cargo sem direito recusa sem escrever; vendedor fixa; p_agora de login é ignorado ──
  insert into public.app_users (id, full_name, email, role, active) values
    (c_tec, 'TESTE F5 técnico', 'teste-f5-envio-tecnico@teste.invalid', 'technician', true),
    (c_vend, 'TESTE F5 vendedor', 'teste-f5-envio-vendedor@teste.invalid', 'seller', true),
    (c_adm, 'TESTE F5 admin', 'teste-f5-envio-admin@teste.invalid', 'admin', true);
  v_r18 := pg_temp.f5e_orc(v_ana, 'ORÇ-99128');
  v_r19 := pg_temp.f5e_orc(v_ana, 'ORÇ-99129');
  v := pg_temp.f5e_como('anon', null, format('select public.orcamento_validade_do_envio(%L::uuid)::text', v_r18));
  if v is distinct from 'erro 42501' then
    raise exception '11a: anon chamou (%)', v;
  end if;
  v := pg_temp.f5e_como('authenticated', c_tec, format('select public.orcamento_validade_do_envio(%L::uuid)::text', v_r18));
  if v::jsonb is distinct from '{"ok": false, "motivo": "cargo"}'::jsonb
     or (select so.quote_validity_date from public.service_orders so where so.id = v_r18) is not null then
    raise exception '11b: técnico (%)', v;
  end if;
  v := pg_temp.f5e_como('authenticated', null, format('select public.orcamento_validade_do_envio(%L::uuid)::text', v_r18));
  if v::jsonb is distinct from '{"ok": false, "motivo": "cargo"}'::jsonb then
    raise exception '11c: authenticated sem login (%)', v;
  end if;
  v := pg_temp.f5e_como('authenticated', c_vend, format('select public.orcamento_validade_do_envio(%L::uuid)::text', v_r18));
  if (v::jsonb ->> 'fixou')::boolean is not true or v::jsonb ->> 'data' is distinct from (v_hoje_real + 7)::text
     or (select so.quote_validity_date from public.service_orders so where so.id = v_r18) is distinct from v_hoje_real + 7 then
    raise exception '11d: vendedor (%)', v;
  end if;
  v := pg_temp.f5e_como('authenticated', c_adm,
         format('select public.orcamento_validade_do_envio(%L::uuid, %L::timestamptz)::text', v_r19, '2030-06-04 10:00-03'));
  if (v::jsonb ->> 'fixou')::boolean is not true or v::jsonb ->> 'data' is distinct from (v_hoje_real + 7)::text then
    raise exception '11e: admin com p_agora em 2030: o p_agora não foi ignorado (%)', v;
  end if;
  update public.app_users set active = false where id = c_adm;
  v := pg_temp.f5e_como('authenticated', c_adm, format('select public.orcamento_validade_do_envio(%L::uuid)::text', v_r19));
  if v::jsonb is distinct from '{"ok": false, "motivo": "cargo"}'::jsonb then
    raise exception '11f: admin inativo (%)', v;
  end if;

  -- ── 12. Todo envio, a qualquer número: outro número (ao_cliente falso, funil igual); reenvio com o funil já em sent;
  --        OS: ignorado; via fora da lista; o mesmo envio duas vezes ──
  v_r20 := pg_temp.f5e_orc(v_ana, 'ORÇ-99120');
  v_r := public.orcamento_registrar_envio(v_r20, 'assistente', '00015077', false, c_t);
  if (v_r ->> 'ao_cliente')::boolean is not false or pg_temp.f5e_n(v_r20) is distinct from 1
     or (select so.quote_status from public.service_orders so where so.id = v_r20) is distinct from 'draft' then
    raise exception '12a: outro número (%)', v_r;
  end if;
  update public.service_orders
     set quote_status = 'sent', orcamento_enviado_em = c_t + interval '1 hour', orcamento_enviado_via = 'assistente',
         orcamento_enviado_chave = c_chave_ana
   where id = v_r20;
  v_r := public.orcamento_registrar_envio(v_r20, 'assistente', c_chave_ana, false, c_t + interval '1 day');
  if (v_r ->> 'ao_cliente')::boolean is not true or pg_temp.f5e_n(v_r20) is distinct from 2
     or not exists (select 1 from public.orcamento_envios e where e.service_order_id = v_r20 and e.em = c_t + interval '1 day'
                                                          and e.ao_cliente and not e.marcou) then
    raise exception '12b: reenvio com o funil em sent (%)', v_r;
  end if;
  v_r := public.orcamento_registrar_envio(v_os, 'tela', c_chave_ana, true, c_t);
  if v_r is distinct from '{"ok": true, "ignorado": "nao_e_orcamento"}'::jsonb or pg_temp.f5e_n(v_os) is distinct from 0 then
    raise exception '12c: OS (%)', v_r;
  end if;
  v_r := public.orcamento_registrar_envio(v_r20, 'whatsapp', c_chave_ana, false, c_t);
  if v_r is distinct from '{"ok": false, "motivo": "via"}'::jsonb then
    raise exception '12d: via fora da lista (%)', v_r;
  end if;
  v_r := public.orcamento_registrar_envio(v_r20, 'assistente', c_chave_ana, false, c_t + interval '1 day');
  if v_r ->> 'ignorado' is distinct from 'repetido' or pg_temp.f5e_n(v_r20) is distinct from 2 then
    raise exception '12e: o mesmo envio duas vezes (%)', v_r;
  end if;

  -- ── 13. Grants, gatilhos e a varredura das funções do orçamento pelo nome ──
  foreach v in array c_novas loop
    for v_rec in
      select p.oid, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v
    loop
      v_n_fun := v_n_fun + 1;
      if v_rec.prosecdef is not true or not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
        raise exception '13a: % não é SECURITY DEFINER com search_path', v_rec.nome;
      end if;
    end loop;
  end loop;
  if v_n_fun is distinct from 6 then
    raise exception '13b: achei % das 6 funções novas', v_n_fun;
  end if;
  if not has_function_privilege('authenticated', 'public.orcamento_validade_do_envio(uuid, timestamptz, boolean, date)', 'execute')
     or not has_function_privilege('service_role', 'public.orcamento_validade_do_envio(uuid, timestamptz, boolean, date)', 'execute')
     or has_function_privilege('authenticated', 'public.orcamento_registrar_envio(uuid, text, text, boolean, timestamptz)', 'execute')
     or not has_function_privilege('service_role', 'public.orcamento_registrar_envio(uuid, text, text, boolean, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.orcamento_detectar_envio(timestamptz)', 'execute')
     or not has_function_privilege('service_role', 'public.orcamento_detectar_envio(timestamptz)', 'execute') then
    raise exception '13c: grants das funções públicas do envio';
  end if;
  select count(*) into v_n from pg_trigger t
   where t.tgrelid = 'public.service_orders'::regclass and not t.tgisinternal
     and ((t.tgname = 'trg_orcamento_quote_status' and pg_get_triggerdef(t.oid) ~ 'BEFORE UPDATE OF quote_status')
       or (t.tgname = 'trg_orcamento_envio_depois' and pg_get_triggerdef(t.oid) ~ 'AFTER UPDATE OF quote_status, orcamento_enviado_em'));
  if v_n is distinct from 2 then
    raise exception '13d: os dois gatilhos do funil (% de 2)', v_n;
  end if;
  v_n_fun := 0;
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?orcamento'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_rec.oid, 'execute') then
      raise exception '13e: % aberta a anon', v_rec.nome;
    end if;
    if has_function_privilege('authenticated', v_rec.oid, 'execute') and v_rec.proname <> all (c_abertas) then
      raise exception '13f: % aberta a authenticated', v_rec.nome;
    end if;
    if v_rec.prosecdef and not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
      raise exception '13g: % é SECURITY DEFINER sem search_path', v_rec.nome;
    end if;
  end loop;
  if v_n_fun < 6 then
    raise exception '13h: a varredura das funções do orçamento achou só % (o filtro quebrou)', v_n_fun;
  end if;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_envio', true, '{}');
end
$envio$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
