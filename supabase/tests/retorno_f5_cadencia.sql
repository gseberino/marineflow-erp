-- Retorno F5 (P3): a cadência do orçamento enviado (K7) e o vigia do orçamento. O calendário (a régua do plano, o feriado,
-- a validade curta e a ausência do dono), os inelegíveis (um por motivo, a marcação à mão sem nenhuma linha), acompanhar
-- duas vezes, parar na ordem, o passo parado, o dia (cartão, sozinho só com o aviso da véspera entregue, sombra, segura,
-- sábado, aviso zerado pelo refazer), o prazo do *sim*, o encerramento que não saiu, o refazer, a mensagem às 09:58, ninguém
-- olha o futuro, o modo desligado, a trava, o aceite que perdeu o objeto e a parte do vigia do 8b da P2 (o acompanhamento que
-- nasce e para na mesma rodada). Roda só pela bancada (grupo 8, F5_ONDA=3, F5_TESTES=retorno_f5_cadencia). Termina em
-- ROLLBACK; cada cenário roda no seu sub-bloco, que se desfaz sozinho (raise 'f5c_cenario'), e o vigia de um nunca vê o do
-- outro. Só confere as próprias linhas sintéticas: telefones inventados 55479000099xx (a chave sai do telefone: 000099xx),
-- nomes inventados (Ana, João, Pedro), documentos inventados (ORÇ-992xx e OS-992xx), usuário de teste @teste.invalid.
-- Nenhuma mensagem real é lida; as mensagens são inventadas. Relógio: ter 12/01/2027 10:00 (Brasília) para o vigia; o
-- calendário puro usa as datas da spec (ter 08/12/2026 e sex 13/11/2026, com o feriado de sex 20/11).
-- A trava (nº 14) é conferida no corpo da função: numa sessão só, pg_try_advisory_xact_lock é reentrante e a 2ª chamada
-- não pularia; a bancada não tem duas conexões.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f5c_cli(p_nome text, p_fone text, p_generico boolean default false) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp, generico) values ('individual', p_nome, p_fone, p_generico) returning id
$f$;

-- Uma mensagem inventada (recebida, por padrão), com a hora real igual à de gravação.
create or replace function pg_temp.f5c_msg(p_fone text, p_corpo text, p_em timestamptz, p_direcao text default 'inbound',
                                           p_tipo text default 'text', p_raw jsonb default '{"data": {}}'::jsonb) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real,
                                        occurred_at)
  values (p_direcao, p_fone, p_tipo, p_corpo, case when p_direcao = 'inbound' then 'received' else 'sent' end, p_raw, p_em, p_em)
  returning id
$f$;

-- O orçamento em rascunho, criado 2 dias antes de p_em.
create or replace function pg_temp.f5c_orc(p_cliente uuid, p_numero text, p_em timestamptz, p_status text default 'draft',
                                           p_quote text default 'draft') returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, quote_validity_days)
  values (p_numero, p_cliente, v_v, p_status, p_quote, 'repair', p_em - interval '2 days', p_em - interval '2 days', 100, 7)
  returning id into v_id;
  return v_id;
end $f$;

-- O envio como o whatsapp-send o marca: sent, a hora, a via, a chave e a validade (o gatilho guarda o que veio).
create or replace function pg_temp.f5c_enviar(p_os uuid, p_em timestamptz, p_chave text, p_validade date, p_via text default 'tela')
returns void
language sql as $f$
  update public.service_orders
     set quote_status = 'sent', orcamento_enviado_em = p_em, orcamento_enviado_via = p_via, orcamento_enviado_chave = p_chave,
         quote_validity_date = p_validade
   where id = p_os
$f$;

-- Um envio ao cliente em orcamento_envios (o que orcamento_registrar_envio grava).
create or replace function pg_temp.f5c_envio(p_os uuid, p_em timestamptz, p_chave text, p_marcou boolean default false) returns uuid
language sql as $f$
  insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, marcou)
  select so.id, so.client_id, 'tela', p_chave, true, p_em, p_marcou from public.service_orders so where so.id = p_os
  returning id
$f$;

-- O cliente pronto para a cadência: cadastro, uma conversa 10 dias antes, o orçamento enviado a ele pela tela.
create or replace function pg_temp.f5c_pronto(p_nome text, p_fone text, p_numero text, p_em timestamptz, p_validade date)
returns uuid
language plpgsql as $f$
declare
  v_c uuid;
  v_os uuid;
begin
  v_c := pg_temp.f5c_cli(p_nome, p_fone);
  perform pg_temp.f5c_msg(p_fone, 'Bom dia, tudo bem?', p_em - interval '10 days');
  v_os := pg_temp.f5c_orc(v_c, p_numero, p_em);
  perform pg_temp.f5c_enviar(v_os, p_em, public._agenda_chave_telefone(p_fone), p_validade);
  perform pg_temp.f5c_envio(v_os, p_em, public._agenda_chave_telefone(p_fone), true);
  return v_os;
end $f$;

create or replace function pg_temp.f5c_acomp(p_os uuid, p_agora timestamptz) returns uuid
language sql as $f$
  select (public.orcamento_acompanhar(p_os, p_agora) ->> 'acompanhamento_id')::uuid
$f$;

create or replace function pg_temp.f5c_a(p_acomp uuid) returns public.orcamento_acompanhamentos
language sql as $f$
  select a from public.orcamento_acompanhamentos a where a.id = p_acomp
$f$;

create or replace function pg_temp.f5c_p(p_acomp uuid, p_passo text) returns public.orcamento_passos
language sql as $f$
  select p from public.orcamento_passos p where p.acompanhamento_id = p_acomp and p.passo = p_passo
$f$;

create or replace function pg_temp.f5c_s(p_saida uuid) returns public.retorno_saidas
language sql as $f$
  select s from public.retorno_saidas s where s.id = p_saida
$f$;

-- Os passos de um acompanhamento em texto: "passo:estado[:motivo]", na ordem do dia.
create or replace function pg_temp.f5c_passos(p_acomp uuid) returns text
language sql as $f$
  select coalesce(string_agg(p.passo || ':' || p.estado || coalesce(':' || p.motivo, ''), ',' order by p.dia, p.passo), '')
    from public.orcamento_passos p where p.acompanhamento_id = p_acomp
$f$;

-- O calendário em texto: "passo:tipo:dia:ate", na ordem do dia.
create or replace function pg_temp.f5c_cal(p_enviado timestamptz, p_validade date) returns text
language sql as $f$
  select coalesce(string_agg(c.passo || ':' || c.tipo || ':' || to_char(c.dia, 'YYYY-MM-DD') || ':' || to_char(c.ate, 'YYYY-MM-DD'),
                             ',' order by c.dia), '')
    from public._orcamento_calendario(p_enviado, p_validade) c
$f$;

-- A linha da fila que levou o fechamento da tarde (só status e sent_at contam para o vigia).
create or replace function pg_temp.f5c_fila(p_status text, p_sent timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_send_queue (phone_normalized, message, source, status, sent_at)
  values ('5547900009999', 'fechamento da tarde (teste F5)', 'manual', p_status, p_sent)
  returning id
$f$;

-- A conversão pela tela (o que tira o orçamento do funil aberto).
create or replace function pg_temp.f5c_converter(p_os uuid, p_em timestamptz, p_numero text) returns void
language sql as $f$
  update public.service_orders
     set status = 'open', converted_to_os_at = p_em, service_order_number = p_numero, quote_status = 'approved'
   where id = p_os
$f$;

-- A mensagem do aceite como o retorno_abrir a grava (sem caso), com a hora de processamento.
create or replace function pg_temp.f5c_rm(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_id uuid;
begin
  v_id := pg_temp.f5c_msg(p_fone, p_corpo, p_em);
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, sinais,
                                        pede_resposta, pede_motivo, audio_pendente, consumida, agenda_ao_dono, processada_em)
  values (v_id, null, public._agenda_chave_telefone(p_fone), p_em, p_em, md5(p_corpo), '{}'::jsonb, false, null, false, false,
          false, p_em);
  return v_id;
end $f$;

-- O PDF que saiu do aparelho do dono (eco: data, sem via).
create or replace function pg_temp.f5c_eco(p_fone text, p_arquivo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, raw_payload, occurred_at, hora_real)
  values ('outbound', p_fone, 'document', null, 'teste-f5-cadencia-' || md5(p_fone || p_arquivo || p_em::text),
          jsonb_build_object('data', jsonb_build_object('source', 'unknown', 'message',
                                                        jsonb_build_object('documentMessage', jsonb_build_object('fileName', p_arquivo)))),
          p_em, p_em)
  returning id
$f$;

do $cadencia$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter
  c_val constant date := date '2027-01-19';                  -- ter: lembrete 14/01, véspera 18/01, encerramento 20/01
  c_fone constant text := '5547900009911';
  c_chave constant text := '00009911';
  c_equipe constant uuid := 'b1600000-0000-4000-8000-0000000099e1';
  c_novas constant text[] := array['_orcamento_dia_util_mais', '_orcamento_dia_util_antes', '_orcamento_calendario',
                                   '_orcamento_refazer', '_orcamento_inelegivel', 'orcamento_acompanhar', '_orcamento_parar_motivo',
                                   '_orcamento_agendar_passo', 'orcamento_vigia'];
  v_ana uuid; v_joao uuid; v_pedro uuid; v_c uuid; v_p uuid;
  v_os uuid; v_os2 uuid; v_ac uuid; v_m uuid; v_q uuid; v_id uuid;
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_o4 uuid; v_o5 uuid; v_o6 uuid; v_o7 uuid; v_o8 uuid; v_o9 uuid; v_o10 uuid;
  v_a1 uuid; v_a2 uuid; v_a3 uuid; v_a4 uuid; v_a5 uuid; v_a6 uuid; v_a7 uuid; v_a8 uuid;
  v_a public.orcamento_acompanhamentos;
  v_ps public.orcamento_passos;
  v_s public.retorno_saidas;
  v_ac_row public.orcamento_aceites;
  v_r jsonb;
  v text;
  v_n integer;
  v_t timestamptz;
  v_rec record;
  v_n_fun integer := 0;
begin
  begin
  -- A configuração de cada rodada: a cadência em sombra (exige a validade do envio), as réguas do K7, o resto desligado.
  update public.retorno_config
     set validade_envio_ligada = true, orcamento_modo = 'sombra', orcamento_segura = false, envio_mao_modo = 'desligado',
         aceite_modo = 'desligado', encerrar_marca_perdido = false, cadencia_hora = '10:00', cadencia_inicio = '09:00',
         cadencia_fim = '17:00', cadencia_lembrete_du = 2, cadencia_encerra_du = 1, cadencia_dono_carencia = interval '2 hours',
         cadencia_conversa = interval '365 days', orcamento_envio_ate = null, orcamento_aceite_ate = null
   where id;
  update public.retorno_modelo_tipos set nivel = 'desligado' where tipo in ('orc_lembrete', 'orc_vespera', 'orc_encerramento');
  -- O calendário não depende de ausência real do dono nem de sábado útil: a régua da spec.
  update public.agenda_config set sabado_util = false where id;
  update public.agenda_disponibilidade d
     set substituida_em = now()
   where d.payee_id is null and d.situacao = 'indisponivel' and d.turno is null and d.substituida_em is null
     and d.periodo && daterange(date '2026-11-01', date '2027-03-01');

  -- ── 1. O calendário do plano: envio ter 08/12, V = ter 15/12 ──
  v := pg_temp.f5c_cal('2026-12-08 10:00-03', date '2026-12-15');
  if v is distinct from 'lembrete:orc_lembrete:2026-12-10:2026-12-11,vespera:orc_vespera:2026-12-14:2026-12-14,'
                        || 'encerramento:orc_encerramento:2026-12-16:2026-12-18' then
    raise exception '1: calendário do plano (%)', v;
  end if;
  -- O dia é o de Brasília: 23:30 de ter 08/12 ainda é 08/12.
  if pg_temp.f5c_cal('2026-12-08 23:30-03', date '2026-12-15') is distinct from v then
    raise exception '1b: 23:30 de Brasília mudou o dia do envio';
  end if;

  -- ── 2. Envio na sex 13/11, V = sex 20/11 (feriado) ──
  v := pg_temp.f5c_cal('2026-11-13 10:00-03', date '2026-11-20');
  if v is distinct from 'lembrete:orc_lembrete:2026-11-17:2026-11-18,vespera:orc_vespera:2026-11-19:2026-11-19,'
                        || 'encerramento:orc_encerramento:2026-11-23:2026-11-25' then
    raise exception '2: calendário com o feriado (%)', v;
  end if;

  -- ── 3. Validade digitada à mão: o lembrete no dia da véspera sai; a véspera no dia do envio sai ──
  v := pg_temp.f5c_cal('2026-11-13 10:00-03', date '2026-11-17');
  if v is distinct from 'vespera:orc_vespera:2026-11-16:2026-11-16,encerramento:orc_encerramento:2026-11-18:2026-11-23' then
    raise exception '3a: V = ter 17/11 (%)', v;
  end if;
  v := pg_temp.f5c_cal('2026-11-13 10:00-03', date '2026-11-16');
  if v is distinct from 'encerramento:orc_encerramento:2026-11-17:2026-11-19' then
    raise exception '3b: V = seg 16/11 (%)', v;
  end if;

  -- ── 4. A ausência do dono num dia: o dia não conta como útil ──
  begin
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, turno)
    values (null, daterange(date '2026-12-10', date '2026-12-10', '[]'), 'indisponivel', 'dono', null);
    if public._orcamento_dia_util_mais(date '2026-12-09', 1) is distinct from date '2026-12-11' then
      raise exception '4a: a ausência contou como dia útil';
    end if;
    v := pg_temp.f5c_cal('2026-12-08 10:00-03', date '2026-12-15');
    if v is distinct from 'lembrete:orc_lembrete:2026-12-11:2026-12-11,vespera:orc_vespera:2026-12-14:2026-12-14,'
                          || 'encerramento:orc_encerramento:2026-12-16:2026-12-18' then
      raise exception '4b: calendário com a ausência (%)', v;
    end if;
    if public._orcamento_dia_util_antes(date '2026-12-11') is distinct from date '2026-12-09' then
      raise exception '4c: o dia útil antes de sex 11/12 com a ausência na qui';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 5. Inelegível, um teste por motivo (e o elegível) ──
  begin
    v_ana := pg_temp.f5c_cli('Ana Cadência F5 Teste', '5547900009901');
    perform pg_temp.f5c_msg('5547900009901', 'Bom dia', c_t - interval '10 days');
    -- elegível
    v_os := pg_temp.f5c_orc(v_ana, 'ORÇ-99201', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009901', c_val);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is not null then
      raise exception '5a: o elegível deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    -- destino: a chave do envio não é do cadastro
    v_os := pg_temp.f5c_orc(v_ana, 'ORÇ-99202', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009977', c_val);
    v := public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    if v is distinct from 'destino' then
      raise exception '5b: destino fora do cadastro deu %', v;
    end if;
    -- a marcação à mão (só quote_status e a hora no SET): via marcado, chave nula → destino, e nenhuma linha (nenhum 23502)
    v_os := pg_temp.f5c_orc(v_ana, 'ORÇ-99203', c_t);
    update public.service_orders set quote_status = 'sent', orcamento_enviado_em = c_t, quote_validity_date = c_val where id = v_os;
    if (select so.orcamento_enviado_via from public.service_orders so where so.id = v_os) is distinct from 'marcado'
       or (select so.orcamento_enviado_chave from public.service_orders so where so.id = v_os) is not null then
      raise exception '5c: a marcação à mão não ficou marcado sem chave';
    end if;
    v_r := public.orcamento_acompanhar(v_os, c_t + interval '1 minute');
    if v_r is distinct from '{"ok": false, "motivo": "destino"}'::jsonb
       or exists (select 1 from public.orcamento_acompanhamentos a where a.service_order_id = v_os) then
      raise exception '5d: marcação à mão (%)', v_r;
    end if;
    -- sem validade, validade curta, histórico, funil, não é orçamento, envio depois de p_agora
    v_os := pg_temp.f5c_orc(v_ana, 'ORÇ-99204', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009901', null);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'sem_validade' then
      raise exception '5e: sem validade deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    v_os := pg_temp.f5c_orc(v_ana, 'ORÇ-99205', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009901', date '2027-01-13');
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'validade_curta' then
      raise exception '5f: validade curta deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    v_os := pg_temp.f5c_orc(v_ana, 'ORÇ-99206', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009901', c_val, 'historico');
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'historico' then
      raise exception '5g: via histórico deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    v_os := pg_temp.f5c_orc(v_ana, 'ORÇ-99207', c_t);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'funil' then
      raise exception '5h: rascunho não enviado deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    v_os := pg_temp.f5c_orc(v_ana, 'OS-99208', c_t, 'open', 'approved');
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'nao_e_orcamento' then
      raise exception '5i: OS deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    v_os := pg_temp.f5c_orc(v_ana, 'ORÇ-99209', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t + interval '1 hour', '00009901', c_val);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'sem_envio' then
      raise exception '5j: envio depois de p_agora deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    -- Cliente Final
    v_c := pg_temp.f5c_cli('Cliente Final Cadência F5 Teste', '5547900009902', true);
    perform pg_temp.f5c_msg('5547900009902', 'Bom dia', c_t - interval '10 days');
    v_os := pg_temp.f5c_orc(v_c, 'ORÇ-99210', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009902', c_val);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'cliente_final' then
      raise exception '5k: Cliente Final deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    -- cliente parceiro (a lista da configuração) e o orçamento pedido por um parceiro
    v_pedro := pg_temp.f5c_cli('Pedro Cadência F5 Teste', '5547900009903');
    perform pg_temp.f5c_msg('5547900009903', 'Bom dia', c_t - interval '10 days');
    update public.retorno_config set clientes_parceiros = clientes_parceiros || array[v_pedro] where id;
    v_os := pg_temp.f5c_orc(v_pedro, 'ORÇ-99211', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009903', c_val);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'parceiro_cliente' then
      raise exception '5l: cliente parceiro deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    insert into public.parceiros (nome, sigla, tipo) values ('Revenda Cadência F5 Teste', 'RCFT', 'revenda') returning id into v_p;
    v_os := pg_temp.f5c_orc(v_ana, 'ORÇ-99212', c_t);
    update public.service_orders set origem_parceiro_id = v_p where id = v_os;
    perform pg_temp.f5c_enviar(v_os, c_t, '00009901', c_val);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'parceiro_cliente' then
      raise exception '5m: orçamento pedido pelo parceiro deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    -- número compartilhado: a mesma chave em 2 cadastros
    v_joao := pg_temp.f5c_cli('João Cadência F5 Teste', '5547900009904');
    perform pg_temp.f5c_cli('João Segundo Cadência F5 Teste', '5547900009904');
    perform pg_temp.f5c_msg('5547900009904', 'Bom dia', c_t - interval '10 days');
    v_os := pg_temp.f5c_orc(v_joao, 'ORÇ-99213', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009904', c_val);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'numero_compartilhado' then
      raise exception '5n: número compartilhado deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    -- sem conversa em 365 dias
    v_c := pg_temp.f5c_cli('Pedro Calado Cadência F5 Teste', '5547900009905');
    perform pg_temp.f5c_msg('5547900009905', 'Bom dia', c_t - interval '400 days');
    v_os := pg_temp.f5c_orc(v_c, 'ORÇ-99214', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009905', c_val);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'sem_conversa' then
      raise exception '5o: sem conversa deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    -- opt-out no cadastro
    v_c := pg_temp.f5c_cli('Ana Opt Cadência F5 Teste', '5547900009906');
    update public.clients set opt_out_whatsapp = true where id = v_c;
    perform pg_temp.f5c_msg('5547900009906', 'Bom dia', c_t - interval '10 days');
    v_os := pg_temp.f5c_orc(v_c, 'ORÇ-99215', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009906', c_val);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'opt_out' then
      raise exception '5p: opt-out deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    -- equipe: o número é de alguém da equipe
    insert into public.app_users (id, full_name, email, role, active, phone)
    values (c_equipe, 'TESTE F5 equipe', 'teste-f5-cadencia-equipe@teste.invalid', 'technician', true, '5547900009907');
    v_c := pg_temp.f5c_cli('João Equipe Cadência F5 Teste', '5547900009907');
    perform pg_temp.f5c_msg('5547900009907', 'Bom dia', c_t - interval '10 days');
    v_os := pg_temp.f5c_orc(v_c, 'ORÇ-99216', c_t);
    perform pg_temp.f5c_enviar(v_os, c_t, '00009907', c_val);
    if public._orcamento_inelegivel(v_os, c_t + interval '1 minute') is distinct from 'equipe' then
      raise exception '5q: equipe deu %', public._orcamento_inelegivel(v_os, c_t + interval '1 minute');
    end if;
    -- Nenhum inelegível ganhou acompanhamento pelo acompanhar.
    for v_rec in select so.id from public.service_orders so where so.service_order_number ~ '^(ORÇ|OS)-992(0[2-9]|1[0-6])$' loop
      v_r := public.orcamento_acompanhar(v_rec.id, c_t + interval '1 minute');
      if (v_r ->> 'ok')::boolean is not false then
        raise exception '5r: um inelegível ganhou acompanhamento (%)', v_r;
      end if;
    end loop;
    if exists (select 1 from public.orcamento_acompanhamentos a join public.service_orders so on so.id = a.service_order_id
                where so.service_order_number ~ '^(ORÇ|OS)-992(0[2-9]|1[0-6])$') then
      raise exception '5s: linha de acompanhamento para inelegível';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 6. orcamento_acompanhar duas vezes: 1 acompanhamento, 3 passos ──
  begin
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99220', c_t, c_val);
    v_r := public.orcamento_acompanhar(v_os, c_t + interval '1 minute');
    v_r := public.orcamento_acompanhar(v_os, c_t + interval '2 minutes');
    v_ac := (v_r ->> 'acompanhamento_id')::uuid;
    if (v_r ->> 'ok')::boolean is not true
       or (select count(*) from public.orcamento_acompanhamentos a where a.service_order_id = v_os) is distinct from 1::bigint
       or (select count(*) from public.orcamento_passos p where p.acompanhamento_id = v_ac) is distinct from 3::bigint then
      raise exception '6a: duas vezes (%)', v_r;
    end if;
    if v_r -> 'passos' is distinct from
       '[{"passo": "lembrete", "dia": "2027-01-14", "ate": "2027-01-15"}, {"passo": "vespera", "dia": "2027-01-18", "ate": "2027-01-18"},
         {"passo": "encerramento", "dia": "2027-01-20", "ate": "2027-01-22"}]'::jsonb then
      raise exception '6b: os passos (%)', v_r -> 'passos';
    end if;
    v_a := pg_temp.f5c_a(v_ac);
    if v_a.modo is distinct from 'sombra' or v_a.estado is distinct from 'ativo' or v_a.chave is distinct from c_chave
       or v_a.enviado_em is distinct from c_t or v_a.validade_ate is distinct from c_val
       or pg_temp.f5c_passos(v_ac) is distinct from 'lembrete:previsto,vespera:previsto,encerramento:previsto' then
      raise exception '6c: o acompanhamento (%; %)', to_jsonb(v_a), pg_temp.f5c_passos(v_ac);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 7. Parar, um teste por motivo, na ordem ──
  -- 7a. O status mudou ganha de o cliente escreveu; o vigia conclui.
  begin
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99221', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    perform pg_temp.f5c_msg(c_fone, 'Recebi, obrigado', c_t + interval '1 hour');
    update public.service_orders set quote_status = 'approved' where id = v_os;
    v_r := public._orcamento_parar_motivo(v_ac, c_t + interval '2 hours');
    if v_r ->> 'motivo' is distinct from 'status_mudou' then
      raise exception '7a: status mudou × cliente escreveu (%)', v_r;
    end if;
    perform public.orcamento_vigia(c_t + interval '2 hours');
    v_a := pg_temp.f5c_a(v_ac);
    if v_a.estado is distinct from 'concluido' or v_a.parou_por is distinct from 'status_mudou'
       or pg_temp.f5c_passos(v_ac) is distinct from 'lembrete:cancelado,vespera:cancelado,encerramento:cancelado' then
      raise exception '7b: o vigia no status mudou (%; %)', to_jsonb(v_a), pg_temp.f5c_passos(v_ac);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- 7c. "Fechei com outra empresa" → encerrou, com o desfecho proposto fechou_com_outro e o id da mensagem.
  begin
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99222', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    v_m := pg_temp.f5c_msg(c_fone, 'Obrigado, mas fechei com outra empresa.', c_t + interval '1 hour');
    v_r := public._orcamento_parar_motivo(v_ac, c_t + interval '2 hours');
    if v_r ->> 'motivo' is distinct from 'encerrou' or v_r ->> 'msg_id' is distinct from v_m::text
       or v_r ->> 'desfecho' is distinct from 'fechou_com_outro' then
      raise exception '7c: fechei com outra empresa (%)', v_r;
    end if;
    perform public.orcamento_vigia(c_t + interval '2 hours');
    v_a := pg_temp.f5c_a(v_ac);
    if v_a.estado is distinct from 'parado' or v_a.parou_por is distinct from 'encerrou' or v_a.parou_msg_id is distinct from v_m
       or v_a.desfecho_proposto is distinct from 'fechou_com_outro' or v_a.parou_em is distinct from c_t + interval '1 hour' then
      raise exception '7d: o vigia no encerrou (%)', to_jsonb(v_a);
    end if;
    -- O texto da mensagem não foi gravado em lugar nenhum da F5.
    if row_to_json(v_a)::text ~* 'outra empresa' then
      raise exception '7e: o texto do cliente foi gravado';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- 7f. "Desisti do orçamento" → encerrou, desistiu.
  begin
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99223', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    perform pg_temp.f5c_msg(c_fone, 'Desisti do orçamento, obrigado', c_t + interval '1 hour');
    v_r := public._orcamento_parar_motivo(v_ac, c_t + interval '2 hours');
    if v_r ->> 'motivo' is distinct from 'encerrou' or v_r ->> 'desfecho' is distinct from 'desistiu' then
      raise exception '7f: desisti (%)', v_r;
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- 7g. "ok, obrigado" → cliente_escreveu (qualquer mensagem). PARAR → parar. Opt-out do cadastro → opt_out. Validade
  --     renovada → validade_mudou.
  begin
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99224', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    v_m := pg_temp.f5c_msg(c_fone, 'ok, obrigado', c_t + interval '1 hour');
    v_r := public._orcamento_parar_motivo(v_ac, c_t + interval '2 hours');
    if v_r ->> 'motivo' is distinct from 'cliente_escreveu' or v_r ->> 'msg_id' is distinct from v_m::text then
      raise exception '7g: ok, obrigado (%)', v_r;
    end if;
    update public.service_orders set quote_validity_date = date '2027-01-22' where id = v_os;
    v_r := public._orcamento_parar_motivo(v_ac, c_t + interval '2 hours');
    if v_r ->> 'motivo' is distinct from 'validade_mudou' then
      raise exception '7h: validade renovada (%)', v_r;
    end if;
    update public.service_orders set quote_validity_date = c_val where id = v_os;
    perform pg_temp.f5c_msg(c_fone, 'PARAR', c_t + interval '90 minutes');
    v_r := public._orcamento_parar_motivo(v_ac, c_t + interval '2 hours');
    if v_r ->> 'motivo' is distinct from 'parar' then
      raise exception '7i: PARAR (%)', v_r;
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99225', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    update public.clients set opt_out_whatsapp = true where id = (select so.client_id from public.service_orders so where so.id = v_os);
    v_r := public._orcamento_parar_motivo(v_ac, c_t + interval '2 hours');
    if v_r ->> 'motivo' is distinct from 'opt_out' then
      raise exception '7j: opt-out do cadastro (%)', v_r;
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- 7k. O documento do dono 30 min depois do envio não para; a saída do próprio retorno não conta; o texto do dono 3 h
  --     depois para (dono_falou).
  begin
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99226', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    perform pg_temp.f5c_msg(c_fone, null, c_t + interval '30 minutes', 'outbound', 'document');
    perform pg_temp.f5c_msg(c_fone, 'Oi! Recebi sua mensagem.', c_t + interval '3 hours', 'outbound', 'text',
                            '{"via": "whatsapp-send", "origem": "retorno"}'::jsonb);
    v_r := public._orcamento_parar_motivo(v_ac, c_t + interval '3 hours 10 minutes');
    if v_r is not null then
      raise exception '7k: o documento na carência ou a saída do retorno parou (%)', v_r;
    end if;
    v_m := pg_temp.f5c_msg(c_fone, 'Ana, conseguiu ver?', c_t + interval '3 hours 20 minutes', 'outbound');
    v_r := public._orcamento_parar_motivo(v_ac, c_t + interval '3 hours 30 minutes');
    if v_r ->> 'motivo' is distinct from 'dono_falou' or v_r ->> 'msg_id' is distinct from v_m::text then
      raise exception '7l: o texto do dono 3 h depois (%)', v_r;
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 8 e 12. Parado: passos cancelados e a saída agendada cancelada com o motivo; antes da mensagem, segue ativo ──
  begin
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99227', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    v_id := public._orcamento_agendar_passo((pg_temp.f5c_p(v_ac, 'lembrete')).id, c_t + interval '2 minutes', 'sombra');
    if v_id is null or (pg_temp.f5c_p(v_ac, 'lembrete')).estado is distinct from 'agendado' then
      raise exception '8a: o lembrete não foi agendado';
    end if;
    v_m := pg_temp.f5c_msg(c_fone, 'Vou ver com calma', c_t + interval '1 day');
    -- 12. Ninguém olha o futuro: antes da mensagem, nada para.
    if public._orcamento_parar_motivo(v_ac, c_t + interval '23 hours') is not null then
      raise exception '12a: a mensagem do futuro parou';
    end if;
    perform public.orcamento_vigia(c_t + interval '23 hours');
    if (pg_temp.f5c_a(v_ac)).estado is distinct from 'ativo' then
      raise exception '12b: o vigia antes da mensagem parou o acompanhamento';
    end if;
    perform public.orcamento_vigia(c_t + interval '1 day 1 hour');
    v_a := pg_temp.f5c_a(v_ac);
    v_s := pg_temp.f5c_s(v_id);
    if v_a.estado is distinct from 'parado' or v_a.parou_por is distinct from 'cliente_escreveu' or v_a.parou_msg_id is distinct from v_m
       or pg_temp.f5c_passos(v_ac) is distinct from 'lembrete:cancelado,vespera:cancelado,encerramento:cancelado'
       or v_s.estado is distinct from 'cancelada' or v_s.motivo is distinct from 'cliente_escreveu'
       or v_s.decidida_em is distinct from c_t + interval '1 day 1 hour' then
      raise exception '8b: parado (%; %; %)', to_jsonb(v_a), pg_temp.f5c_passos(v_ac), to_jsonb(v_s);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 9. O dia ──
  -- 9a. Tipo em cartão → aguarda_sim.
  begin
    update public.retorno_config set orcamento_modo = 'ligado' where id;
    update public.retorno_modelo_tipos set nivel = 'cartao' where tipo = 'orc_lembrete';
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99230', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    perform public.orcamento_vigia('2027-01-14 09:55-03');
    if (pg_temp.f5c_a(v_ac)).modo is distinct from 'ligado' or (pg_temp.f5c_p(v_ac, 'lembrete')).estado is distinct from 'aguarda_sim'
       or exists (select 1 from public.retorno_saidas s where s.emissor = 'orcamento' and s.dados ->> 'acompanhamento_id' = v_ac::text) then
      raise exception '9a: cartão (%)', pg_temp.f5c_passos(v_ac);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- 9b. Sozinho com o aviso entregue (avisado_em e a linha da fila em sent) → a saída das 10:00.
  begin
    update public.retorno_config set orcamento_modo = 'ligado' where id;
    update public.retorno_modelo_tipos set nivel = 'sozinho' where tipo = 'orc_lembrete';
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99231', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    v_q := pg_temp.f5c_fila('sent', '2027-01-13 17:31-03');
    update public.orcamento_passos p set avisado_em = '2027-01-13 17:30-03', aviso_fila = v_q
     where p.acompanhamento_id = v_ac and p.passo = 'lembrete';
    perform public.orcamento_vigia('2027-01-14 09:55-03');
    v_ps := pg_temp.f5c_p(v_ac, 'lembrete');
    v_s := pg_temp.f5c_s(v_ps.saida_id);
    if v_ps.estado is distinct from 'agendado' or v_s.id is null or v_s.estado is distinct from 'agendada'
       or v_s.enviar_em is distinct from '2027-01-14 10:00-03'::timestamptz or v_s.modo is distinct from 'ligado'
       or v_s.emissor is distinct from 'orcamento' or v_s.tipo is distinct from 'orc_lembrete'
       or v_s.origem is distinct from 'retorno_orcamento' or v_s.classe is distinct from 'comercial' or v_s.abertura_id is not null
       or v_s.chave is distinct from c_chave or v_s.phone_normalized is distinct from c_fone
       or v_s.client_id is distinct from (select so.client_id from public.service_orders so where so.id = v_os)
       or v_s.dedupe_key is distinct from 'orcamento:' || v_ac || ':lembrete:1'
       or v_s.dados ->> 'por' is distinct from 'sozinho' or (v_s.dados ->> 'sozinho')::boolean is not true
       or v_s.dados ->> 'passo_id' is distinct from v_ps.id::text or v_s.dados ->> 'os_id' is distinct from v_os::text then
      raise exception '9b: sozinho com o aviso entregue (%; %)', to_jsonb(v_ps), to_jsonb(v_s);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- 9c. Sozinho sem avisado_em → aguarda_sim; 9d. com avisado_em e a fila em pending ou failed → aguarda_sim.
  begin
    update public.retorno_config set orcamento_modo = 'ligado' where id;
    update public.retorno_modelo_tipos set nivel = 'sozinho' where tipo = 'orc_lembrete';
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99232', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    v_os2 := pg_temp.f5c_pronto('João Cadência F5 Teste', '5547900009912', 'ORÇ-99233', c_t, c_val);
    v_a1 := pg_temp.f5c_acomp(v_os2, c_t + interval '1 minute');
    v_o3 := pg_temp.f5c_pronto('Pedro Cadência F5 Teste', '5547900009913', 'ORÇ-99234', c_t, c_val);
    v_a2 := pg_temp.f5c_acomp(v_o3, c_t + interval '1 minute');
    update public.orcamento_passos p set avisado_em = '2027-01-13 17:30-03', aviso_fila = pg_temp.f5c_fila('pending', null)
     where p.acompanhamento_id = v_a1 and p.passo = 'lembrete';
    update public.orcamento_passos p set avisado_em = '2027-01-13 17:30-03', aviso_fila = pg_temp.f5c_fila('failed', null)
     where p.acompanhamento_id = v_a2 and p.passo = 'lembrete';
    perform public.orcamento_vigia('2027-01-14 09:55-03');
    if (pg_temp.f5c_p(v_ac, 'lembrete')).estado is distinct from 'aguarda_sim' then
      raise exception '9c: sozinho sem aviso (%)', pg_temp.f5c_passos(v_ac);
    end if;
    if (pg_temp.f5c_p(v_a1, 'lembrete')).estado is distinct from 'aguarda_sim'
       or (pg_temp.f5c_p(v_a2, 'lembrete')).estado is distinct from 'aguarda_sim' then
      raise exception '9d: sozinho com o fechamento enfileirado e não entregue (%; %)', pg_temp.f5c_passos(v_a1), pg_temp.f5c_passos(v_a2);
    end if;
    if exists (select 1 from public.retorno_saidas s
                where s.emissor = 'orcamento' and s.dados ->> 'acompanhamento_id' in (v_ac::text, v_a1::text, v_a2::text)) then
      raise exception '9e: sozinho sem o aviso entregue agendou saída';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- 9f. Sombra → a saída nasce em sombra (chave com :sombra); segura → nada; sábado → nada.
  begin
    update public.retorno_modelo_tipos set nivel = 'cartao' where tipo = 'orc_lembrete';
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99235', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    -- segura: nada
    update public.retorno_config set orcamento_segura = true where id;
    perform public.orcamento_vigia('2027-01-14 09:55-03');
    if (pg_temp.f5c_p(v_ac, 'lembrete')).estado is distinct from 'previsto' then
      raise exception '9f: segura orcamentos (%)', pg_temp.f5c_passos(v_ac);
    end if;
    update public.retorno_config set orcamento_segura = false where id;
    perform public.orcamento_vigia('2027-01-14 09:56-03');
    v_ps := pg_temp.f5c_p(v_ac, 'lembrete');
    v_s := pg_temp.f5c_s(v_ps.saida_id);
    if (pg_temp.f5c_a(v_ac)).modo is distinct from 'sombra' or v_ps.estado is distinct from 'agendado'
       or v_s.modo is distinct from 'sombra' or v_s.dedupe_key is distinct from 'orcamento:' || v_ac || ':lembrete:1:sombra'
       or v_s.dados ->> 'por' is distinct from 'sombra' or v_s.enviar_em is distinct from '2027-01-14 10:00-03'::timestamptz then
      raise exception '9g: sombra (%; %)', to_jsonb(v_ps), to_jsonb(v_s);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    -- Envio na qua 13/01: lembrete sex 15/01, até seg 18/01 (o prazo passa pelo sábado).
    update public.retorno_config set orcamento_modo = 'ligado' where id;
    update public.retorno_modelo_tipos set nivel = 'cartao' where tipo = 'orc_lembrete';
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99236', c_t + interval '1 day', date '2027-01-20');
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 day 1 minute');
    v_ps := pg_temp.f5c_p(v_ac, 'lembrete');
    if v_ps.dia is distinct from date '2027-01-15' or v_ps.ate is distinct from date '2027-01-18' then
      raise exception '9h: o lembrete que passa pelo sábado (%)', to_jsonb(v_ps);
    end if;
    perform public.orcamento_vigia('2027-01-16 10:00-03');
    if (pg_temp.f5c_p(v_ac, 'lembrete')).estado is distinct from 'previsto' then
      raise exception '9i: sábado (%)', pg_temp.f5c_passos(v_ac);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- 9j. O passo avisado e depois refeito para outro dia: avisado_em e aviso_fila nulos, e no dia novo vai ao cartão.
  begin
    update public.retorno_config set orcamento_modo = 'ligado' where id;
    update public.retorno_modelo_tipos set nivel = 'sozinho' where tipo = 'orc_lembrete';
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99237', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    update public.orcamento_passos p set avisado_em = c_t + interval '7 hours', aviso_fila = pg_temp.f5c_fila('sent', c_t + interval '7 hours')
     where p.acompanhamento_id = v_ac and p.passo = 'lembrete';
    -- O dono reenvia o PDF na qua 13/01 10:00 (pela tela): a saída humana para (dono_falou) e o reenvio refaz.
    perform pg_temp.f5c_msg(c_fone, null, c_t + interval '1 day', 'outbound', 'document',
                            '{"via": "whatsapp-send", "origem": "tela"}'::jsonb);
    perform pg_temp.f5c_envio(v_os, c_t + interval '1 day', c_chave);
    perform public.orcamento_vigia(c_t + interval '1 day 5 minutes');
    if (pg_temp.f5c_a(v_ac)).estado is distinct from 'parado' or (pg_temp.f5c_a(v_ac)).parou_por is distinct from 'dono_falou' then
      raise exception '9j: o reenvio não parou como dono_falou (%)', to_jsonb(pg_temp.f5c_a(v_ac));
    end if;
    perform public.orcamento_vigia(c_t + interval '1 day 10 minutes');
    v_a := pg_temp.f5c_a(v_ac);
    v_ps := pg_temp.f5c_p(v_ac, 'lembrete');
    if v_a.estado is distinct from 'ativo' or v_a.enviado_em is distinct from c_t + interval '1 day'
       or v_a.refeito_em is distinct from c_t + interval '1 day 10 minutes'
       or v_ps.estado is distinct from 'previsto' or v_ps.dia is distinct from date '2027-01-15'
       or v_ps.avisado_em is not null or v_ps.aviso_fila is not null then
      raise exception '9k: o refazer (%; %)', to_jsonb(v_a), to_jsonb(v_ps);
    end if;
    perform public.orcamento_vigia('2027-01-15 09:55-03');
    if (pg_temp.f5c_p(v_ac, 'lembrete')).estado is distinct from 'aguarda_sim' then
      raise exception '9l: o passo refeito sem aviso novo não foi ao cartão (%)', pg_temp.f5c_passos(v_ac);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 10. O prazo do *sim*: o lembrete espera até o dia ate; a véspera só no dia ──
  begin
    update public.retorno_config set orcamento_modo = 'ligado' where id;
    update public.retorno_modelo_tipos set nivel = 'cartao' where tipo in ('orc_lembrete', 'orc_vespera');
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99240', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    perform public.orcamento_vigia('2027-01-14 09:55-03');
    perform public.orcamento_vigia('2027-01-14 17:01-03');
    if (pg_temp.f5c_p(v_ac, 'lembrete')).estado is distinct from 'aguarda_sim' then
      raise exception '10a: às 17:01 do dia do lembrete (%)', pg_temp.f5c_passos(v_ac);
    end if;
    perform public.orcamento_vigia('2027-01-15 17:01-03');
    if pg_temp.f5c_passos(v_ac) is distinct from 'lembrete:pulado:sem_sim,vespera:previsto,encerramento:previsto' then
      raise exception '10b: às 17:01 do dia ate (%)', pg_temp.f5c_passos(v_ac);
    end if;
    perform public.orcamento_vigia('2027-01-18 09:55-03');
    if (pg_temp.f5c_p(v_ac, 'vespera')).estado is distinct from 'aguarda_sim' then
      raise exception '10c: a véspera no dia dela (%)', pg_temp.f5c_passos(v_ac);
    end if;
    perform public.orcamento_vigia('2027-01-18 17:01-03');
    if pg_temp.f5c_passos(v_ac) is distinct from 'lembrete:pulado:sem_sim,vespera:pulado:sem_sim,encerramento:previsto'
       or (pg_temp.f5c_a(v_ac)).estado is distinct from 'ativo' then
      raise exception '10d: a véspera às 17:01 do dia dela (%)', pg_temp.f5c_passos(v_ac);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- 10b. Aprovado às 18:00 do dia do lembrete: a saída nasce para as 10:00 do próximo dia comercial, com o texto aprovado;
  --      aprovado às 18:00 do dia ate: não há hora até o prazo (pulado/fora_da_janela, nada inserido).
  begin
    update public.retorno_config set orcamento_modo = 'ligado' where id;
    update public.retorno_modelo_tipos set nivel = 'cartao' where tipo = 'orc_lembrete';
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99241', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    perform public.orcamento_vigia('2027-01-14 09:55-03');
    update public.orcamento_passos p
       set texto_aprovado = 'Oi, Ana! Conseguiu ver o orçamento que o Gustavo te mandou?', aprovado_em = '2027-01-14 18:00-03'
     where p.acompanhamento_id = v_ac and p.passo = 'lembrete';
    v_id := public._orcamento_agendar_passo((pg_temp.f5c_p(v_ac, 'lembrete')).id, '2027-01-14 18:00-03', 'sim');
    v_s := pg_temp.f5c_s(v_id);
    if v_id is null or v_s.enviar_em is distinct from '2027-01-15 10:00-03'::timestamptz or v_s.dados ->> 'por' is distinct from 'sim'
       or v_s.dados ->> 'texto_aprovado' is distinct from 'Oi, Ana! Conseguiu ver o orçamento que o Gustavo te mandou?'
       or (pg_temp.f5c_p(v_ac, 'lembrete')).estado is distinct from 'agendado' then
      raise exception '10e: aprovado às 18:00 (%)', to_jsonb(v_s);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    update public.retorno_config set orcamento_modo = 'ligado' where id;
    update public.retorno_modelo_tipos set nivel = 'cartao' where tipo = 'orc_lembrete';
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99242', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    perform public.orcamento_vigia('2027-01-14 09:55-03');
    v_id := public._orcamento_agendar_passo((pg_temp.f5c_p(v_ac, 'lembrete')).id, '2027-01-15 18:00-03', 'sim');
    if v_id is not null or pg_temp.f5c_passos(v_ac) is distinct from 'lembrete:pulado:fora_da_janela,vespera:previsto,encerramento:previsto'
       or exists (select 1 from public.retorno_saidas s where s.emissor = 'orcamento' and s.dados ->> 'acompanhamento_id' = v_ac::text) then
      raise exception '10f: aprovado depois do prazo (%)', pg_temp.f5c_passos(v_ac);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- 10c. O encerramento que não saiu: encerrado sem mensagem, "sumiu" proposto, e o orçamento não muda (nem com
  --      encerrar_marca_perdido).
  begin
    update public.retorno_config set orcamento_modo = 'ligado', encerrar_marca_perdido = true where id;
    update public.retorno_modelo_tipos set nivel = 'cartao' where tipo in ('orc_lembrete', 'orc_vespera', 'orc_encerramento');
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99243', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    update public.orcamento_passos p set estado = 'pulado', motivo = 'sem_sim'
     where p.acompanhamento_id = v_ac and p.passo in ('lembrete', 'vespera');
    update public.orcamento_passos p set estado = 'aguarda_sim' where p.acompanhamento_id = v_ac and p.passo = 'encerramento';
    perform public.orcamento_vigia('2027-01-22 17:01-03');
    v_a := pg_temp.f5c_a(v_ac);
    if v_a.estado is distinct from 'encerrado' or v_a.encerramento is distinct from 'sem_mensagem'
       or v_a.desfecho_proposto is distinct from 'sumiu'
       or (pg_temp.f5c_p(v_ac, 'encerramento')).motivo is distinct from 'sem_sim'
       or (select so.quote_status from public.service_orders so where so.id = v_os) is distinct from 'sent'
       or (select so.motivo_perda from public.service_orders so where so.id = v_os) is not null then
      raise exception '10g: encerramento sem mensagem (%)', to_jsonb(v_a);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 10d. Refazer ──
  -- Parado por dono_falou; o dono reenvia com a validade de pé: ativo; o lembrete enviado não volta; a véspera que tinha
  -- saída cancelada (:vespera:1) nasce de novo com :vespera:2.
  begin
    update public.retorno_config set orcamento_modo = 'ligado' where id;
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99250', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    update public.orcamento_passos p set estado = 'enviado' where p.acompanhamento_id = v_ac and p.passo = 'lembrete';
    v_id := public._orcamento_agendar_passo((pg_temp.f5c_p(v_ac, 'vespera')).id, c_t + interval '2 minutes', 'sozinho');
    if (pg_temp.f5c_s(v_id)).dedupe_key is distinct from 'orcamento:' || v_ac || ':vespera:1' then
      raise exception '10h: a véspera não nasceu com :vespera:1 (%)', to_jsonb(pg_temp.f5c_s(v_id));
    end if;
    perform pg_temp.f5c_msg(c_fone, null, c_t + interval '1 day', 'outbound', 'document',
                            '{"via": "whatsapp-send", "origem": "assistente"}'::jsonb);
    perform pg_temp.f5c_envio(v_os, c_t + interval '1 day', c_chave);
    perform public.orcamento_vigia(c_t + interval '1 day 5 minutes');
    if (pg_temp.f5c_a(v_ac)).parou_por is distinct from 'dono_falou' or (pg_temp.f5c_s(v_id)).estado is distinct from 'cancelada'
       or (pg_temp.f5c_s(v_id)).motivo is distinct from 'dono_falou' then
      raise exception '10i: o reenvio parou como dono_falou e cancelou a véspera (%; %)', to_jsonb(pg_temp.f5c_a(v_ac)), to_jsonb(pg_temp.f5c_s(v_id));
    end if;
    perform public.orcamento_vigia(c_t + interval '1 day 10 minutes');
    v_a := pg_temp.f5c_a(v_ac);
    if v_a.estado is distinct from 'ativo' or v_a.enviado_em is distinct from c_t + interval '1 day' or v_a.parou_por is not null
       or pg_temp.f5c_passos(v_ac) is distinct from 'lembrete:enviado,vespera:previsto,encerramento:previsto'
       or (pg_temp.f5c_p(v_ac, 'vespera')).dia is distinct from date '2027-01-18' or (pg_temp.f5c_p(v_ac, 'vespera')).saida_id is not null then
      raise exception '10j: refeito (%; %)', to_jsonb(v_a), pg_temp.f5c_passos(v_ac);
    end if;
    v_id := public._orcamento_agendar_passo((pg_temp.f5c_p(v_ac, 'vespera')).id, '2027-01-18 09:55-03', 'sozinho');
    if v_id is null or (pg_temp.f5c_s(v_id)).dedupe_key is distinct from 'orcamento:' || v_ac || ':vespera:2'
       or (pg_temp.f5c_p(v_ac, 'vespera')).estado is distinct from 'agendado' then
      raise exception '10k: a véspera refeita não nasceu com :vespera:2 (%)', to_jsonb(pg_temp.f5c_s(v_id));
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- Parado por validade_mudou (renovou na tela) e reenviado: o mesmo, com a data nova.
  begin
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99251', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    update public.service_orders set quote_validity_date = date '2027-01-22' where id = v_os;
    perform public.orcamento_vigia(c_t + interval '1 hour');
    if (pg_temp.f5c_a(v_ac)).parou_por is distinct from 'validade_mudou' then
      raise exception '10l: a validade renovada não parou (%)', to_jsonb(pg_temp.f5c_a(v_ac));
    end if;
    perform pg_temp.f5c_envio(v_os, c_t + interval '1 day', c_chave);
    perform public.orcamento_vigia(c_t + interval '1 day 5 minutes');
    v_a := pg_temp.f5c_a(v_ac);
    if v_a.estado is distinct from 'ativo' or v_a.validade_ate is distinct from date '2027-01-22'
       or (pg_temp.f5c_p(v_ac, 'vespera')).dia is distinct from date '2027-01-21'
       or (pg_temp.f5c_p(v_ac, 'encerramento')).dia is distinct from date '2027-01-25' then
      raise exception '10m: refeito com a data nova (%; %)', to_jsonb(v_a), pg_temp.f5c_passos(v_ac);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  -- Parado por cliente_escreveu e reenviado: continua parado. Reenvio a menos de 2 dias da validade, ou com ela vencida:
  -- nada muda.
  begin
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99252', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    perform pg_temp.f5c_msg(c_fone, 'Vou ver e te falo', c_t + interval '1 hour');
    perform public.orcamento_vigia(c_t + interval '2 hours');
    perform pg_temp.f5c_envio(v_os, c_t + interval '1 day', c_chave);
    perform public.orcamento_vigia(c_t + interval '1 day 5 minutes');
    if (pg_temp.f5c_a(v_ac)).estado is distinct from 'parado' or (pg_temp.f5c_a(v_ac)).parou_por is distinct from 'cliente_escreveu' then
      raise exception '10n: parado por cliente_escreveu foi refeito (%)', to_jsonb(pg_temp.f5c_a(v_ac));
    end if;
    v_os2 := pg_temp.f5c_pronto('João Cadência F5 Teste', '5547900009912', 'ORÇ-99253', c_t, c_val);
    v_a1 := pg_temp.f5c_acomp(v_os2, c_t + interval '1 minute');
    perform pg_temp.f5c_msg('5547900009912', 'João, conseguiu ver?', c_t + interval '3 hours', 'outbound');
    perform public.orcamento_vigia(c_t + interval '3 hours 5 minutes');
    perform pg_temp.f5c_envio(v_os2, '2027-01-18 10:00-03', '00009912');
    perform public.orcamento_vigia('2027-01-18 10:05-03');
    if (pg_temp.f5c_a(v_a1)).estado is distinct from 'parado' or (pg_temp.f5c_a(v_a1)).refeito_em is not null then
      raise exception '10o: reenvio a menos de 2 dias da validade refez (%)', to_jsonb(pg_temp.f5c_a(v_a1));
    end if;
    perform pg_temp.f5c_envio(v_os2, '2027-01-20 10:00-03', '00009912');
    perform public.orcamento_vigia('2027-01-20 10:05-03');
    if (pg_temp.f5c_a(v_a1)).estado is distinct from 'parado' or (pg_temp.f5c_a(v_a1)).refeito_em is not null then
      raise exception '10p: reenvio com a validade vencida refez (%)', to_jsonb(pg_temp.f5c_a(v_a1));
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 11. A mensagem do cliente às 09:58 e o lembrete às 10:00: o vigia das 10:00 vê a mensagem e cancela ──
  begin
    update public.retorno_config set orcamento_modo = 'ligado' where id;
    update public.retorno_modelo_tipos set nivel = 'sozinho' where tipo = 'orc_lembrete';
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99254', c_t, c_val);
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '1 minute');
    update public.orcamento_passos p set avisado_em = '2027-01-13 17:30-03', aviso_fila = pg_temp.f5c_fila('sent', '2027-01-13 17:31-03')
     where p.acompanhamento_id = v_ac and p.passo = 'lembrete';
    perform public.orcamento_vigia('2027-01-14 09:55-03');
    v_id := (pg_temp.f5c_p(v_ac, 'lembrete')).saida_id;
    if v_id is null or (pg_temp.f5c_s(v_id)).estado is distinct from 'agendada' then
      raise exception '11a: o lembrete das 10:00 não foi agendado (%)', pg_temp.f5c_passos(v_ac);
    end if;
    v_m := pg_temp.f5c_msg(c_fone, 'Bom dia! Vi sim', '2027-01-14 09:58-03');
    perform public.orcamento_vigia('2027-01-14 10:00-03');
    if (pg_temp.f5c_a(v_ac)).estado is distinct from 'parado' or (pg_temp.f5c_a(v_ac)).parou_msg_id is distinct from v_m
       or (pg_temp.f5c_s(v_id)).estado is distinct from 'cancelada' or (pg_temp.f5c_s(v_id)).motivo is distinct from 'cliente_escreveu'
       or (pg_temp.f5c_p(v_ac, 'lembrete')).estado is distinct from 'cancelado' then
      raise exception '11b: a mensagem das 09:58 (%; %)', to_jsonb(pg_temp.f5c_a(v_ac)), to_jsonb(pg_temp.f5c_s(v_id));
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 13. orcamento_modo desligado: o vigia não cria acompanhamento nem mexe em passo ──
  begin
    update public.retorno_config set orcamento_modo = 'desligado' where id;
    v_os := pg_temp.f5c_pronto('Ana Cadência F5 Teste', c_fone, 'ORÇ-99255', c_t, c_val);
    v_r := public.orcamento_vigia(c_t + interval '5 minutes');
    if exists (select 1 from public.orcamento_acompanhamentos a where a.service_order_id = v_os)
       or v_r ->> 'modo' is distinct from 'desligado' then
      raise exception '13a: desligado criou acompanhamento (%)', v_r;
    end if;
    update public.retorno_config set orcamento_modo = 'sombra' where id;
    v_ac := pg_temp.f5c_acomp(v_os, c_t + interval '6 minutes');
    update public.retorno_config set orcamento_modo = 'desligado' where id;
    perform public.orcamento_vigia('2027-01-14 09:55-03');
    if pg_temp.f5c_passos(v_ac) is distinct from 'lembrete:previsto,vespera:previsto,encerramento:previsto'
       or exists (select 1 from public.retorno_saidas s where s.emissor = 'orcamento' and s.dados ->> 'acompanhamento_id' = v_ac::text) then
      raise exception '13b: desligado mexeu no passo (%)', pg_temp.f5c_passos(v_ac);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 14. A trava: uma rodada por vez (no corpo; numa sessão só a trava é reentrante) ──
  select p.prosrc into v from pg_proc p where p.oid = 'public.orcamento_vigia(timestamptz)'::regprocedure;
  if strpos(v, 'if not pg_try_advisory_xact_lock(hashtext(''orcamento:vigia'')) then') = 0
     or strpos(v, 'return jsonb_build_object(''ok'', true, ''pulou'', true);') = 0
     or strpos(v, 'pg_try_advisory_xact_lock') > strpos(v, 'orcamento_detectar_envio') then
    raise exception '14: a trava do vigia não está no começo do corpo';
  end if;

  -- ── 15. O aceite que perdeu o objeto (com a cadência desligada: o bloco 7 roda sempre) ──
  begin
    update public.retorno_config set orcamento_modo = 'desligado' where id;
    v_c := pg_temp.f5c_cli('Ana Aceite Cadência F5 Teste', '5547900009920');
    v_t := c_t + interval '3 hours';     -- a rodada do vigia
    v_o1 := pg_temp.f5c_orc(v_c, 'ORÇ-99260', c_t);
    v_o2 := pg_temp.f5c_orc(v_c, 'ORÇ-99261', c_t);
    v_o3 := pg_temp.f5c_orc(v_c, 'ORÇ-99262', c_t);
    v_o4 := pg_temp.f5c_orc(v_c, 'ORÇ-99263', c_t);
    v_o5 := pg_temp.f5c_orc(v_c, 'ORÇ-99264', c_t);
    v_o6 := pg_temp.f5c_orc(v_c, 'ORÇ-99265', c_t);
    v_o7 := pg_temp.f5c_orc(v_c, 'ORÇ-99266', c_t);
    v_o8 := pg_temp.f5c_orc(v_c, 'ORÇ-99267', c_t);
    v_o9 := pg_temp.f5c_orc(v_c, 'ORÇ-99268', c_t);
    v_o10 := pg_temp.f5c_orc(v_c, 'ORÇ-99269', c_t);
    for v_rec in select x.id from unnest(array[v_o1, v_o2, v_o3, v_o4, v_o5, v_o6, v_o7, v_o8, v_o9, v_o10]) as x(id) loop
      perform pg_temp.f5c_enviar(v_rec.id, c_t, '00009920', c_val);
      perform pg_temp.f5c_envio(v_rec.id, c_t, '00009920');
    end loop;
    -- duvida com 2 candidatos, os dois convertidos pela tela → caiu (sem_candidato)
    insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, sinal_lido, estado)
    values (pg_temp.f5c_rm('5547900009920', 'Pode fazer.', c_t + interval '1 hour'), v_c, '00009920', array[v_o1, v_o2],
            'pode fazer', 'duvida')
    returning id into v_a1;
    perform pg_temp.f5c_converter(v_o1, c_t + interval '2 hours', 'OS-99260');
    perform pg_temp.f5c_converter(v_o2, c_t + interval '2 hours', 'OS-99261');
    -- duvida com 2 candidatos, só um convertido → continua duvida
    insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, sinal_lido, estado)
    values (pg_temp.f5c_rm('5547900009920', 'Pode fazer!', c_t + interval '1 hour 1 minute'), v_c, '00009920', array[v_o3, v_o4],
            'pode fazer', 'duvida')
    returning id into v_a2;
    perform pg_temp.f5c_converter(v_o3, c_t + interval '2 hours', 'OS-99262');
    -- detectado com a ordem apagada (service_order_id nulo) → caiu
    insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado,
                                          total_visto)
    values (pg_temp.f5c_rm('5547900009920', 'Fechado!', c_t + interval '1 hour 2 minutes'), v_c, '00009920', array[v_o5], v_o5,
            'fechado', 'detectado', 100)
    returning id into v_a3;
    delete from public.service_orders where id = v_o5;
    -- detectado com executado_em há 1 min e a ordem já convertida → não muda
    insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado,
                                          total_visto, executado_em)
    values (pg_temp.f5c_rm('5547900009920', 'Pode seguir', c_t + interval '1 hour 3 minutes'), v_c, '00009920', array[v_o6], v_o6,
            'pode seguir', 'detectado', 100, v_t - interval '1 minute')
    returning id into v_a4;
    perform pg_temp.f5c_converter(v_o6, v_t - interval '30 seconds', 'OS-99265');
    -- detectado com executado_em há 31 min, convertido depois dele → sem_sinal sem registro, nenhuma saída
    insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado,
                                          total_visto, executado_em)
    values (pg_temp.f5c_rm('5547900009920', 'Aprovado', c_t + interval '1 hour 4 minutes'), v_c, '00009920', array[v_o7], v_o7,
            'aprovado', 'detectado', 100, v_t - interval '31 minutes')
    returning id into v_a5;
    perform pg_temp.f5c_converter(v_o7, v_t - interval '20 minutes', 'OS-99266');
    -- detectado com executado_em há 31 min, não convertido → executado_em nulo, continua detectado
    insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado,
                                          total_visto, executado_em)
    values (pg_temp.f5c_rm('5547900009920', 'Autorizo', c_t + interval '1 hour 5 minutes'), v_c, '00009920', array[v_o8], v_o8,
            'autorizo', 'detectado', 100, v_t - interval '31 minutes')
    returning id into v_a6;
    -- substituido e com_sinal com a ordem convertida → não mudam
    insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado,
                                          total_visto, resultado)
    values (pg_temp.f5c_rm('5547900009920', 'Vamos fazer', c_t + interval '1 hour 6 minutes'), v_c, '00009920', array[v_o9], v_o9,
            'vamos fazer', 'substituido', 100, jsonb_build_object('substituido_por', v_a6))
    returning id into v_a7;
    insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado,
                                          total_visto, decidido_em)
    values (pg_temp.f5c_rm('5547900009920', 'Pode marcar', c_t + interval '1 hour 7 minutes'), v_c, '00009920', array[v_o10], v_o10,
            'pode marcar', 'com_sinal', 100, c_t + interval '1 hour 30 minutes')
    returning id into v_a8;
    perform pg_temp.f5c_converter(v_o9, c_t + interval '2 hours', 'OS-99268');
    perform pg_temp.f5c_converter(v_o10, c_t + interval '2 hours', 'OS-99269');

    v_r := public.orcamento_vigia(v_t);
    select * into v_ac_row from public.orcamento_aceites a where a.id = v_a1;
    if v_ac_row.estado is distinct from 'caiu' or v_ac_row.resultado ->> 'motivo' is distinct from 'sem_candidato'
       or v_ac_row.resultado -> 'numeros' is distinct from '["OS-99260", "OS-99261"]'::jsonb
       or v_ac_row.resultado -> 'quote_status' is distinct from '["approved", "approved"]'::jsonb then
      raise exception '15a: duvida sem candidato (%; %)', to_jsonb(v_ac_row), v_r;
    end if;
    if (select a.estado from public.orcamento_aceites a where a.id = v_a2) is distinct from 'duvida' then
      raise exception '15b: duvida com 1 candidato ainda de pé caiu';
    end if;
    select * into v_ac_row from public.orcamento_aceites a where a.id = v_a3;
    if v_ac_row.estado is distinct from 'caiu' or v_ac_row.resultado ->> 'motivo' is distinct from 'sem_candidato'
       or v_ac_row.service_order_id is not null then
      raise exception '15c: detectado com a ordem apagada (%)', to_jsonb(v_ac_row);
    end if;
    select * into v_ac_row from public.orcamento_aceites a where a.id = v_a4;
    if v_ac_row.estado is distinct from 'detectado' or v_ac_row.executado_em is distinct from v_t - interval '1 minute' then
      raise exception '15d: detectado com executado_em há 1 min mudou (%)', to_jsonb(v_ac_row);
    end if;
    select * into v_ac_row from public.orcamento_aceites a where a.id = v_a5;
    if v_ac_row.estado is distinct from 'sem_sinal' or v_ac_row.decidido_em is distinct from v_t - interval '31 minutes'
       or v_ac_row.resultado ->> 'saida_nao_saiu' is distinct from 'sem_registro'
       or (v_ac_row.resultado ->> 'convertido')::boolean is not true or v_ac_row.resultado ->> 'numero' is distinct from 'OS-99266'
       or exists (select 1 from public.retorno_saidas s where s.dados ->> 'aceite_id' = v_a5::text) then
      raise exception '15e: executado há 31 min e convertido (%)', to_jsonb(v_ac_row);
    end if;
    select * into v_ac_row from public.orcamento_aceites a where a.id = v_a6;
    if v_ac_row.estado is distinct from 'detectado' or v_ac_row.executado_em is not null then
      raise exception '15f: executado há 31 min e não convertido (%)', to_jsonb(v_ac_row);
    end if;
    if (select a.estado from public.orcamento_aceites a where a.id = v_a7) is distinct from 'substituido'
       or (select a.estado from public.orcamento_aceites a where a.id = v_a8) is distinct from 'com_sinal' then
      raise exception '15g: estado final mudou';
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 16. A parte do vigia do 8b da P2: o PDF das 14:00, a resposta às 14:02 e a detecção às 14:05 criam o acompanhamento e
  --        o param na mesma rodada; o mesmo no caso noturno (PDF às 21:30, resposta às 21:40, detecção às 07:00) ──
  begin
    update public.retorno_config set envio_mao_modo = 'marcar', orcamento_envio_ate = c_t where id;
    v_c := pg_temp.f5c_cli('Ana Aparelho Cadência F5 Teste', c_fone);
    v_os := pg_temp.f5c_orc(v_c, 'ORÇ-99270', c_t);
    update public.service_orders set quote_validity_date = c_val where id = v_os;
    perform pg_temp.f5c_eco(c_fone, 'ORÇ-99270_Ana.pdf', c_t + interval '4 hours');
    v_m := pg_temp.f5c_msg(c_fone, 'Recebi, obrigada', c_t + interval '4 hours 2 minutes');
    v_r := public.orcamento_vigia(c_t + interval '4 hours 5 minutes');
    select * into v_a from public.orcamento_acompanhamentos a where a.service_order_id = v_os;
    if (select so.orcamento_enviado_em from public.service_orders so where so.id = v_os) is distinct from c_t + interval '4 hours'
       or v_a.id is null or v_a.estado is distinct from 'parado' or v_a.parou_por is distinct from 'cliente_escreveu'
       or v_a.parou_msg_id is distinct from v_m or v_a.enviado_em is distinct from c_t + interval '4 hours'
       or pg_temp.f5c_passos(v_a.id) is distinct from 'lembrete:cancelado,vespera:cancelado,encerramento:cancelado'
       or exists (select 1 from public.retorno_saidas s where s.emissor = 'orcamento' and s.dados ->> 'acompanhamento_id' = v_a.id::text) then
      raise exception '16a: 14:00, 14:02, 14:05 (%; %)', to_jsonb(v_a), v_r;
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;
  begin
    update public.retorno_config set envio_mao_modo = 'marcar', orcamento_envio_ate = c_t where id;
    v_c := pg_temp.f5c_cli('Ana Aparelho Cadência F5 Teste', c_fone);
    v_os := pg_temp.f5c_orc(v_c, 'ORÇ-99271', c_t);
    update public.service_orders set quote_validity_date = c_val where id = v_os;
    perform pg_temp.f5c_eco(c_fone, 'ORÇ-99271.pdf', c_t + interval '11 hours 30 minutes');
    v_m := pg_temp.f5c_msg(c_fone, 'Recebi, depois eu vejo', c_t + interval '11 hours 40 minutes');
    perform public.orcamento_vigia(c_t + interval '21 hours');
    select * into v_a from public.orcamento_acompanhamentos a where a.service_order_id = v_os;
    if v_a.id is null or v_a.enviado_em is distinct from c_t + interval '11 hours 30 minutes' or v_a.estado is distinct from 'parado'
       or v_a.parou_por is distinct from 'cliente_escreveu' or v_a.parou_msg_id is distinct from v_m then
      raise exception '16b: 21:30, 21:40, 07:00 (%)', to_jsonb(v_a);
    end if;
    raise exception 'f5c_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5c_cenario' then
      raise;
    end if;
  end;

  -- ── 17. As funções novas: SECURITY DEFINER com search_path; só orcamento_acompanhar e orcamento_vigia abertas à service_role;
  --        nenhuma função do orçamento aberta a anon ──
  foreach v in array c_novas loop
    for v_rec in
      select p.oid, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v
    loop
      v_n_fun := v_n_fun + 1;
      if v_rec.prosecdef is not true or not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
        raise exception '17a: % não é SECURITY DEFINER com search_path', v_rec.nome;
      end if;
      if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
        raise exception '17b: % aberta a anon ou authenticated', v_rec.nome;
      end if;
      if v in ('orcamento_acompanhar', 'orcamento_vigia') and not has_function_privilege('service_role', v_rec.oid, 'execute') then
        raise exception '17c: % sem o grant da service_role', v_rec.nome;
      end if;
    end loop;
  end loop;
  if v_n_fun is distinct from 9 then
    raise exception '17d: achei % das 9 funções novas', v_n_fun;
  end if;
  v_n_fun := 0;
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?orcamento'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_rec.oid, 'execute') then
      raise exception '17e: % aberta a anon', v_rec.nome;
    end if;
    if has_function_privilege('authenticated', v_rec.oid, 'execute') and v_rec.proname <> all (array['orcamento_validade_do_envio', 'orcamentos_para_agrupar']) then
      raise exception '17f: % aberta a authenticated', v_rec.nome;
    end if;
  end loop;
  if v_n_fun < 15 then
    raise exception '17g: a varredura das funções do orçamento achou só % (o filtro quebrou)', v_n_fun;
  end if;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_cadencia', true, '{}');
end
$cadencia$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
