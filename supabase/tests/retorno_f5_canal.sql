-- Retorno F5 (P5): o canal e as saídas do orçamento. A janela comercial, a classe comercial no canal (só com a origem do
-- orçamento e a F5 fora de desligado), o teto das iniciadas nos dois sentidos dentro do retorno, só a quem já escreveu, o
-- so_reativo, o orcamento_pegar (a parada, a agenda hoje, outra voz hoje, a cadência barrada e o "Fechado" não), o modo
-- efetivo, o retorno_pegar gerado sem o emissor do orçamento (risco A-8), cada motivo do canal sem 23514 com a próxima saída
-- pega na mesma chamada, a última trava, os efeitos (aprovação, letra, encerramento com perdido, "Fechado" com e sem caso), a
-- chave de sombra, o estado da reserva (com o espião do canal) e os efeitos que faltaram (bloco 8 do vigia). Roda só pela
-- bancada (grupo 8, F5_ONDA=4, F5_TESTES=retorno_f5_canal). Termina em ROLLBACK; cada cenário roda no seu sub-bloco, que se
-- desfaz sozinho (raise 'f5k_cenario'), e o canal_pode_enviar trocado por falso ou espião volta ao fim do sub-bloco. Só
-- confere as próprias linhas sintéticas: telefones inventados 55479000099xx (a chave sai do telefone: 000099xx), nomes
-- inventados (Ana, João, Pedro), documentos inventados (ORÇ-994xx), usuário de teste @teste.invalid. Nenhuma mensagem real é
-- lida; as mensagens são inventadas. Relógio: envio na ter 12/01/2027 10:00 com validade ter 19/01 (lembrete qui 14/01, até
-- sex 15/01; véspera seg 18/01; encerramento qua 20/01, até sex 22/01); o feriado é o de sex 20/11/2026.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());
-- O canal falso do nº 9b (o motivo que o canal devolve, por telefone) e o espião do nº 12b (o p_simular de cada chamada).
create temp table if not exists f5k_canal_falso (fone text primary key, motivo text not null, enviar_em timestamptz);
create temp table if not exists f5k_espiao (fone text, classe text, origem text, simular boolean, em timestamptz default clock_timestamp());

create or replace function pg_temp.f5k_cli(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

-- Uma mensagem inventada (recebida, por padrão), com a hora real igual à de gravação.
create or replace function pg_temp.f5k_msg(p_fone text, p_corpo text, p_em timestamptz, p_direcao text default 'inbound') returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real,
                                        occurred_at)
  values (p_direcao, p_fone, 'text', p_corpo, case when p_direcao = 'inbound' then 'received' else 'sent' end, '{"data": {}}'::jsonb,
          p_em, p_em)
  returning id
$f$;

-- O orçamento em rascunho, criado 2 dias antes de p_em.
create or replace function pg_temp.f5k_orc(p_cliente uuid, p_numero text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, quote_validity_days)
  values (p_numero, p_cliente, v_v, 'draft', 'draft', 'repair', p_em - interval '2 days', p_em - interval '2 days', 100, 7)
  returning id into v_id;
  return v_id;
end $f$;

-- O orçamento enviado ao cliente pela tela na ter 12/01 10:00, com validade ter 19/01, e a linha do envio.
create or replace function pg_temp.f5k_enviado(p_cliente uuid, p_fone text, p_numero text) returns uuid
language plpgsql as $f$
declare
  v_os uuid;
begin
  v_os := pg_temp.f5k_orc(p_cliente, p_numero, timestamptz '2027-01-12 10:00-03');
  update public.service_orders
     set quote_status = 'sent', orcamento_enviado_em = '2027-01-12 10:00-03', orcamento_enviado_via = 'tela',
         orcamento_enviado_chave = public._agenda_chave_telefone(p_fone), quote_validity_date = date '2027-01-19'
   where id = v_os;
  insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, marcou)
  values (v_os, p_cliente, 'tela', public._agenda_chave_telefone(p_fone), true, '2027-01-12 10:00-03', true);
  return v_os;
end $f$;

-- O cliente que conversou (uma mensagem dez dias antes) com o orçamento enviado e o acompanhamento nascido.
create or replace function pg_temp.f5k_cad(p_nome text, p_fone text, p_numero text) returns uuid
language plpgsql as $f$
declare
  v_c uuid;
  v_os uuid;
  v_r jsonb;
begin
  v_c := pg_temp.f5k_cli(p_nome, p_fone);
  perform pg_temp.f5k_msg(p_fone, 'Bom dia, tudo bem?', timestamptz '2027-01-02 10:00-03');
  v_os := pg_temp.f5k_enviado(v_c, p_fone, p_numero);
  v_r := public.orcamento_acompanhar(v_os, timestamptz '2027-01-12 10:01-03');
  if not coalesce((v_r ->> 'ok')::boolean, false) then
    raise exception 'f5k_cad: o acompanhamento de % não nasceu (%)', p_numero, v_r ->> 'motivo';
  end if;
  return (v_r ->> 'acompanhamento_id')::uuid;
end $f$;

create or replace function pg_temp.f5k_a(p_acomp uuid) returns public.orcamento_acompanhamentos
language sql as $f$
  select a from public.orcamento_acompanhamentos a where a.id = p_acomp
$f$;

create or replace function pg_temp.f5k_p(p_acomp uuid, p_passo text) returns public.orcamento_passos
language sql as $f$
  select p from public.orcamento_passos p where p.acompanhamento_id = p_acomp and p.passo = p_passo
$f$;

create or replace function pg_temp.f5k_s(p_saida uuid) returns public.retorno_saidas
language sql as $f$
  select s from public.retorno_saidas s where s.id = p_saida
$f$;

-- "estado/motivo" da saída e do passo.
create or replace function pg_temp.f5k_sx(p_saida uuid) returns text
language sql as $f$
  select s.estado || '/' || coalesce(s.motivo, '-') from public.retorno_saidas s where s.id = p_saida
$f$;

create or replace function pg_temp.f5k_px(p_acomp uuid, p_passo text) returns text
language sql as $f$
  select p.estado || '/' || coalesce(p.motivo, '-') from public.orcamento_passos p where p.acompanhamento_id = p_acomp and p.passo = p_passo
$f$;

-- A saída do passo, pela função da P3 (a mesma que o vigia chama).
create or replace function pg_temp.f5k_ag(p_acomp uuid, p_passo text, p_agora timestamptz, p_por text) returns uuid
language sql as $f$
  select public._orcamento_agendar_passo(p.id, p_agora, p_por)
    from public.orcamento_passos p where p.acompanhamento_id = p_acomp and p.passo = p_passo
$f$;

create or replace function pg_temp.f5k_ligar() returns void
language sql as $f$
  update public.retorno_config
     set modo = 'ligado', orcamento_modo = 'ligado', meio_dia_ligado = false, tipos_ligados = '{}', proximo_envio_em = null
   where id
$f$;

create or replace function pg_temp.f5k_nivel(p_nivel text) returns void
language sql as $f$
  update public.retorno_modelo_tipos set nivel = p_nivel where tipo in ('orc_lembrete', 'orc_vespera', 'orc_encerramento')
$f$;

-- O caso vivo do cliente (papel cliente, o mesmo telefone), aberto por uma mensagem inventada.
create or replace function pg_temp.f5k_caso(p_cliente uuid, p_fone text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_m uuid;
  v_id uuid;
begin
  v_m := pg_temp.f5k_msg(p_fone, 'Oi, tudo certo com o orçamento?', p_em);
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, modo)
  values (public._agenda_chave_telefone(p_fone), p_fone, 'cliente', '{}'::jsonb, p_cliente, v_m, v_m, p_em, p_em, p_em, p_em, 'recibo',
          'sombra')
  returning id into v_id;
  return v_id;
end $f$;

-- O aceite B (sem sinal) decidido com *sim <PIN>* e registrado: o "Fechado" nasce em retorno_saidas (orcamento_aceite_registrar).
create or replace function pg_temp.f5k_fechado(p_cliente uuid, p_fone text, p_os uuid, p_recebida timestamptz, p_agora timestamptz,
                                               p_abertura uuid default null) returns uuid
language plpgsql as $f$
declare
  v_m uuid;
  v_a uuid;
  v_r jsonb;
begin
  v_m := pg_temp.f5k_msg(p_fone, 'Pode fazer.', p_recebida);
  insert into public.orcamento_aceites (abertura_id, whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido,
                                        estado, total_visto, executado_em)
  values (p_abertura, v_m, p_cliente, public._agenda_chave_telefone(p_fone), array[p_os], p_os, 'pode fazer', 'detectado', 100,
          p_agora - interval '1 minute')
  returning id into v_a;
  v_r := public.orcamento_aceite_registrar(v_a, true, '{"escolha": "sem_sinal"}'::jsonb, null, false, p_agora);
  if v_r ->> 'fechado' is null then
    raise exception 'f5k_fechado: o registro não agendou o Fechado (%)', v_r ->> 'motivo';
  end if;
  return v_a;
end $f$;

create or replace function pg_temp.f5k_saida_do_aceite(p_aceite uuid) returns uuid
language sql as $f$
  select s.id from public.retorno_saidas s
   where s.emissor = 'orcamento' and s.tipo = 'orc_fechado' and s.dados ->> 'aceite_id' = p_aceite::text
$f$;

create or replace function pg_temp.f5k_agenda(p_cliente uuid, p_os uuid, p_estado text, p_modo text, p_enviar timestamptz,
                                              p_enviada timestamptz default null) returns uuid
language sql as $f$
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate,
                                               aprovacao, estado, dedupe_key, enviada_em)
  values (p_cliente, p_os, 'confirmar', 'rodada', p_modo, 'mensagem de teste (F5 canal)', '{}'::jsonb, p_enviar,
          p_enviar + interval '8 hours', 'livre', p_estado,
          'teste-f5k:' || md5(p_cliente::text || p_estado || p_enviar::text || clock_timestamp()::text || random()::text), p_enviada)
  returning id
$f$;

-- Uma saída de outra voz ou de outra cadência à mesma chave (o aviso da F4, a comercial da F5).
create or replace function pg_temp.f5k_outra(p_fone text, p_emissor text, p_tipo text, p_origem text, p_classe text, p_estado text,
                                             p_em timestamptz) returns uuid
language sql as $f$
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, estado, enviar_em, decidida_em,
                                     enviada_em, texto, dedupe_key)
  values (p_emissor, p_tipo, p_origem, p_classe, public._agenda_chave_telefone(p_fone), p_fone, 'ligado', p_estado, p_em,
          case when p_estado = 'agendada' then null else p_em end, case when p_estado = 'enviada' then p_em end,
          'mensagem de teste (F5 canal)',
          p_emissor || ':teste-f5k:' || md5(p_fone || p_estado || p_em::text || clock_timestamp()::text || random()::text))
  returning id
$f$;

-- Nenhuma saída sintética do orçamento ficou agendada com enviar_em no passado.
create or replace function pg_temp.f5k_atrasadas(p_agora timestamptz) returns integer
language sql as $f$
  select count(*)::integer from public.retorno_saidas s
   where s.emissor = 'orcamento' and s.estado = 'agendada' and s.enviar_em <= p_agora and s.chave like '000099%'
$f$;

do $canal$
declare
  c_envio constant timestamptz := '2027-01-12 10:00-03';    -- ter
  c_qui constant timestamptz := '2027-01-14 10:00-03';      -- qui: o dia do lembrete (até sex 15/01)
  c_seg constant timestamptz := '2027-01-18 10:00-03';      -- seg: a véspera
  c_qua constant timestamptz := '2027-01-20 10:00-03';      -- qua: o encerramento
  c_texto_aprovado constant text :=
    'Oi, Ana! Conseguiu ver o orçamento que o Gustavo te mandou? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo a ele.';
  c_novas constant text[] := array['_orcamento_modo_efetivo', '_orcamento_checar_antes', '_orcamento_aplicar_efeitos',
                                   '_orcamento_pegar_fechar', 'orcamento_pegar', 'orcamento_saida_autorizada'];
  c_publicas constant text[] := array['orcamento_pegar', 'orcamento_saida_autorizada'];
  c_motivos_canal constant text[] := array['teto_iniciadas', 'sem_conversa', 'so_reativo', 'segura_tudo', 'pessoal', 'equipe',
                                           'opt_out', 'bloqueado', 'classe_nao_suportada', 'provedor', 'motivo_que_ninguem_conhece'];
  v_ana uuid; v_joao uuid; v_pedro uuid; v_c uuid;
  v_os uuid; v_os2 uuid;
  v_ac uuid; v_ac2 uuid;
  v_s1 uuid; v_s2 uuid; v_s3 uuid;
  v_aceite uuid;
  v_ab uuid;
  v_r jsonb;
  v_r2 jsonb;
  v_s public.retorno_saidas;
  v_ps public.orcamento_passos;
  v_a public.orcamento_acompanhamentos;
  v_ac_row public.orcamento_aceites;
  v_motivo text;
  v_esperado text;
  v text;
  v_n integer;
  v_t timestamptz;
  v_rec record;
  v_n_fun integer := 0;
begin
  begin
  -- A configuração de cada rodada: o retorno e a cadência em sombra (a cadência exige a validade do envio), as réguas do K7,
  -- o resto desligado; os 3 tipos da cadência desligados.
  update public.retorno_config
     set modo = 'sombra', orcamento_modo = 'sombra', validade_envio_ligada = true, aceite_modo = 'desligado', aceite_audio = false,
         dados_nota_ligado = false, orcamento_segura = false, encerrar_marca_perdido = false, motivo_marca_aberto = false,
         envio_mao_modo = 'desligado', cadencia_hora = '10:00', cadencia_inicio = '09:00', cadencia_fim = '17:00',
         cadencia_lembrete_du = 2, cadencia_encerra_du = 1, cadencia_dono_carencia = interval '2 hours',
         cadencia_conversa = interval '365 days', parceiro_modo = 'desligado', tipos_ligados = '{}', proximo_envio_em = null,
         segura_tudo_ate = null, so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null, iniciadas_dia_max = 12,
         respostas_dia_max = 40
   where id;
  perform pg_temp.f5k_nivel('desligado');
  -- O calendário não depende de ausência real do dono nem de sábado útil: a régua da spec.
  update public.agenda_config set sabado_util = false where id;
  update public.agenda_disponibilidade d
     set substituida_em = now()
   where d.payee_id is null and d.situacao = 'indisponivel' and d.turno is null and d.substituida_em is null
     and d.periodo && daterange(date '2026-11-01', date '2027-03-01');

  -- ── 1. A janela comercial (com a F5 em sombra) ──
  v_r := public._retorno_janela('comercial', '2027-01-18 10:00-03', '00009921');
  if (v_r ->> 'dentro')::boolean is not true then
    raise exception '1a: seg 10:00 fora da janela comercial (%)', v_r;
  end if;
  v_r := public._retorno_janela('comercial', '2027-01-16 10:00-03', '00009921');
  if (v_r ->> 'dentro')::boolean is not false or v_r -> 'enviar_em' is distinct from 'null'::jsonb then
    raise exception '1b: sáb (%)', v_r;
  end if;
  v_r := public._retorno_janela('comercial', '2027-01-18 08:30-03', '00009921');
  if (v_r ->> 'dentro')::boolean is not false or (v_r ->> 'enviar_em')::timestamptz is distinct from '2027-01-18 09:00-03'::timestamptz then
    raise exception '1c: seg 08:30 (%)', v_r;
  end if;
  v_r := public._retorno_janela('comercial', '2027-01-18 17:00-03', '00009921');
  if (v_r ->> 'dentro')::boolean is not false or v_r -> 'enviar_em' is distinct from 'null'::jsonb then
    raise exception '1d: seg 17:00 (%)', v_r;
  end if;
  v_r := public._retorno_janela('comercial', '2026-11-20 10:00-03', '00009921');
  if (v_r ->> 'dentro')::boolean is not false or v_r -> 'enviar_em' is distinct from 'null'::jsonb then
    raise exception '1e: feriado de sex 20/11 (%)', v_r;
  end if;
  -- Com a F5 desligada a classe comercial não existe; e o aviso da F4 continua de fora com a F4 desligada.
  update public.retorno_config set orcamento_modo = 'desligado' where id;
  v_r := public._retorno_janela('comercial', '2027-01-18 10:00-03', '00009921');
  if (v_r ->> 'dentro')::boolean is not false or v_r -> 'enviar_em' is distinct from 'null'::jsonb then
    raise exception '1f: comercial com a F5 desligada (%)', v_r;
  end if;
  update public.retorno_config set orcamento_modo = 'sombra' where id;
  v_r := public._retorno_janela('aviso', '2027-01-18 10:00-03', '00009921');
  if (v_r ->> 'dentro')::boolean is not false then
    raise exception '1g: o aviso da F4 com a F4 desligada mudou (%)', v_r;
  end if;

  -- ── 2. A classe comercial no canal: só com a origem do orçamento e a F5 fora de desligado ──
  begin
    v_ana := pg_temp.f5k_cli('Ana Canal F5 Teste', '5547900009921');
    perform pg_temp.f5k_msg('5547900009921', 'Bom dia', c_qui - interval '10 days');
    update public.retorno_config set orcamento_modo = 'desligado' where id;
    v_r := public.canal_pode_enviar('5547900009921', 'comercial', 'retorno_orcamento', c_qui);
    if v_r ->> 'motivo' is distinct from 'classe_nao_suportada' then
      raise exception '2a: comercial com a F5 desligada (%)', v_r;
    end if;
    update public.retorno_config set orcamento_modo = 'sombra' where id;
    v_r := public.canal_pode_enviar('5547900009921', 'comercial', 'retorno_recibo', c_qui);
    if v_r ->> 'motivo' is distinct from 'classe_nao_suportada' then
      raise exception '2b: comercial com a origem do recibo (%)', v_r;
    end if;
    v_r := public.canal_pode_enviar('5547900009921', 'comercial', null, c_qui);
    if v_r ->> 'motivo' is distinct from 'classe_nao_suportada' then
      raise exception '2c: comercial sem origem (%)', v_r;
    end if;
    v_r := public.canal_pode_enviar('5547900009921', 'comercial', 'retorno_orcamento', c_qui);
    if (v_r ->> 'pode')::boolean is not true then
      raise exception '2d: comercial com a origem do orçamento (%)', v_r;
    end if;
    -- A resposta imediata com a origem do orçamento (o "Fechado") segue a regra de sempre.
    v_r := public.canal_pode_enviar('5547900009921', 'resposta_imediata', 'retorno_orcamento', c_qui);
    if (v_r ->> 'pode')::boolean is not true then
      raise exception '2e: o Fechado no canal (%)', v_r;
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 3. O teto das iniciadas, nos dois sentidos dentro do retorno (11 da agenda + 1 aviso; 11 da agenda + 1 comercial) ──
  begin
    v_ana := pg_temp.f5k_cli('Ana Canal F5 Teste', '5547900009923');
    perform pg_temp.f5k_msg('5547900009923', 'Bom dia', c_seg - interval '10 days');
    v_os := pg_temp.f5k_orc(v_ana, 'ORÇ-99423', c_seg - interval '3 days');
    for v_n in 1 .. 11 loop
      perform pg_temp.f5k_agenda(v_ana, v_os, 'enviada', 'ligado', c_seg - interval '3 hours', c_seg - interval '3 hours');
    end loop;
    -- só as 11 da agenda: a comercial ainda cabe
    v_r := public.canal_pode_enviar('5547900009923', 'comercial', 'retorno_orcamento', c_seg);
    if (v_r ->> 'pode')::boolean is not true then
      raise exception '3a: com 11 da agenda a comercial não cabia mais (%)', v_r;
    end if;
    begin
      perform pg_temp.f5k_outra('5547900009924', 'parceiro', 'parceiro_aviso_cliente', 'retorno_aviso', 'aviso', 'enviada',
                                c_seg - interval '1 hour');
      v_r := public.canal_pode_enviar('5547900009923', 'comercial', 'retorno_orcamento', c_seg);
      if v_r ->> 'motivo' is distinct from 'teto_iniciadas' or v_r -> 'enviar_em' is distinct from 'null'::jsonb then
        raise exception '3b: 11 da agenda + 1 aviso e a comercial passou (%)', v_r;
      end if;
      raise exception 'f5k_cenario' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
        raise;
      end if;
    end;
    -- O outro sentido: a comercial enviada conta no teto do aviso da F4.
    update public.retorno_config set parceiro_modo = 'sombra' where id;
    v_r := public.canal_pode_enviar('5547900009923', 'aviso', 'retorno_aviso', c_seg);
    if v_r ->> 'motivo' is not distinct from 'teto_iniciadas' then
      raise exception '3c: com 11 da agenda o aviso já não cabia (%)', v_r;
    end if;
    perform pg_temp.f5k_outra('5547900009924', 'orcamento', 'orc_lembrete', 'retorno_orcamento', 'comercial', 'enviada',
                              c_seg - interval '1 hour');
    v_r := public.canal_pode_enviar('5547900009923', 'aviso', 'retorno_aviso', c_seg);
    if v_r ->> 'motivo' is distinct from 'teto_iniciadas' then
      raise exception '3d: 11 da agenda + 1 comercial e o aviso passou (%)', v_r;
    end if;
    -- A comercial não entra no teto das respostas.
    update public.retorno_config set respostas_dia_max = 0, parceiro_modo = 'desligado', iniciadas_dia_max = 50 where id;
    v_r := public.canal_pode_enviar('5547900009923', 'comercial', 'retorno_orcamento', c_seg);
    if (v_r ->> 'pode')::boolean is not true then
      raise exception '3e: a comercial caiu no teto das respostas (%)', v_r;
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 4. Só a quem já escreveu (365 dias) ──
  begin
    perform pg_temp.f5k_cli('João Canal F5 Teste', '5547900009925');
    v_r := public.canal_pode_enviar('5547900009925', 'comercial', 'retorno_orcamento', c_qui);
    if v_r ->> 'motivo' is distinct from 'sem_conversa' then
      raise exception '4a: sem recebida nenhuma (%)', v_r;
    end if;
    perform pg_temp.f5k_msg('5547900009925', 'Bom dia', c_qui - interval '400 days');
    v_r := public.canal_pode_enviar('5547900009925', 'comercial', 'retorno_orcamento', c_qui);
    if v_r ->> 'motivo' is distinct from 'sem_conversa' then
      raise exception '4b: só uma recebida de 400 dias atrás (%)', v_r;
    end if;
    -- A saída do próprio número não conta como conversa.
    perform pg_temp.f5k_msg('5547900009925', 'Bom dia, João', c_qui - interval '2 days', 'outbound');
    v_r := public.canal_pode_enviar('5547900009925', 'comercial', 'retorno_orcamento', c_qui);
    if v_r ->> 'motivo' is distinct from 'sem_conversa' then
      raise exception '4c: uma enviada contou como conversa (%)', v_r;
    end if;
    perform pg_temp.f5k_msg('5547900009925', 'Bom dia', c_qui - interval '30 days');
    v_r := public.canal_pode_enviar('5547900009925', 'comercial', 'retorno_orcamento', c_qui);
    if (v_r ->> 'pode')::boolean is not true then
      raise exception '4d: com uma recebida de 30 dias atrás (%)', v_r;
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 5. so_reativo barra a comercial ──
  begin
    perform pg_temp.f5k_cli('Pedro Canal F5 Teste', '5547900009926');
    perform pg_temp.f5k_msg('5547900009926', 'Bom dia', c_qui - interval '10 days');
    update public.retorno_config set so_reativo = true, so_reativo_motivo = 'erros', so_reativo_desde = c_qui - interval '1 hour' where id;
    v_r := public.canal_pode_enviar('5547900009926', 'comercial', 'retorno_orcamento', c_qui);
    if v_r ->> 'motivo' is distinct from 'so_reativo' then
      raise exception '5: so_reativo (%)', v_r;
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 6. orcamento_pegar: o cliente escreveu depois do agendamento ──
  begin
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009927', 'ORÇ-99427');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
    if pg_temp.f5k_sx(v_s1) is distinct from 'agendada/-' or (pg_temp.f5k_s(v_s1)).enviar_em is distinct from c_qui then
      raise exception '6a: o lembrete não ficou agendado às 10:00 (%)', pg_temp.f5k_sx(v_s1);
    end if;
    perform pg_temp.f5k_msg('5547900009927', 'Oi, ainda estou vendo', c_qui - interval '30 minutes');
    v_r := public.orcamento_pegar(c_qui);
    if v_r is not null then
      raise exception '6b: o pegar devolveu a saída do cliente que escreveu';
    end if;
    if pg_temp.f5k_sx(v_s1) is distinct from 'cancelada/cliente_escreveu' then
      raise exception '6c: a saída (%)', pg_temp.f5k_sx(v_s1);
    end if;
    if pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'cancelado/-' then
      raise exception '6d: o passo (%)', pg_temp.f5k_px(v_ac, 'lembrete');
    end if;
    if ((pg_temp.f5k_s(v_s1)).dados ? 'efeitos_f5') is not true then
      raise exception '6e: a recusa antes de preparar não aplicou os efeitos';
    end if;
    if pg_temp.f5k_atrasadas(c_qui) is distinct from 0 then
      raise exception '6f: ficou saída agendada no passado';
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 7. A agenda hoje e outra voz hoje: só a cadência é barrada ──
  begin
    -- 7a. A agenda mandou hoje às 08:00 a este cliente.
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009928', 'ORÇ-99428');
    v_a := pg_temp.f5k_a(v_ac);
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
    perform pg_temp.f5k_agenda(v_a.client_id, v_a.service_order_id, 'enviada', 'ligado', c_qui - interval '2 hours',
                               c_qui - interval '2 hours');
    if public.orcamento_pegar(c_qui) is not null then
      raise exception '7a: saiu com a agenda tendo falado hoje';
    end if;
    if pg_temp.f5k_sx(v_s1) is distinct from 'cancelada/agenda_hoje' or pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'pulado/agenda_hoje' then
      raise exception '7a: % e %', pg_temp.f5k_sx(v_s1), pg_temp.f5k_px(v_ac, 'lembrete');
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;
  begin
    -- 7b. A agenda registrada em modo ligado para as 14:00 de hoje; o lembrete às 10:00.
    v_ac := pg_temp.f5k_cad('João Canal F5 Teste', '5547900009929', 'ORÇ-99429');
    v_a := pg_temp.f5k_a(v_ac);
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
    perform pg_temp.f5k_agenda(v_a.client_id, v_a.service_order_id, 'registrada', 'ligado', c_qui + interval '4 hours');
    if public.orcamento_pegar(c_qui) is not null or pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'pulado/agenda_hoje' then
      raise exception '7b: agenda registrada para hoje (%)', pg_temp.f5k_px(v_ac, 'lembrete');
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;
  begin
    -- 7c. O aviso da F4 enviado hoje à mesma chave.
    v_ac := pg_temp.f5k_cad('Pedro Canal F5 Teste', '5547900009930', 'ORÇ-99430');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
    perform pg_temp.f5k_outra('5547900009930', 'parceiro', 'parceiro_aviso_cliente', 'retorno_aviso', 'aviso', 'enviada',
                              c_qui - interval '2 hours');
    if public.orcamento_pegar(c_qui) is not null or pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'pulado/outra_voz_hoje'
       or pg_temp.f5k_sx(v_s1) is distinct from 'cancelada/outra_voz_hoje' then
      raise exception '7c: aviso da F4 hoje (%, %)', pg_temp.f5k_sx(v_s1), pg_temp.f5k_px(v_ac, 'lembrete');
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;
  begin
    -- 7d. Outra comercial já enviada hoje à mesma chave; e *segura orcamentos*.
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009931', 'ORÇ-99431');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
    perform pg_temp.f5k_outra('5547900009931', 'orcamento', 'orc_lembrete', 'retorno_orcamento', 'comercial', 'enviada',
                              c_qui - interval '3 hours');
    if public.orcamento_pegar(c_qui) is not null or pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'pulado/comercial_hoje' then
      raise exception '7d: outra comercial hoje (%)', pg_temp.f5k_px(v_ac, 'lembrete');
    end if;
    v_ac2 := pg_temp.f5k_cad('João Canal F5 Teste', '5547900009932', 'ORÇ-99432');
    v_s2 := pg_temp.f5k_ag(v_ac2, 'lembrete', c_qui - interval '1 hour', 'sombra');
    update public.retorno_config set orcamento_segura = true where id;
    if public.orcamento_pegar(c_qui) is not null or pg_temp.f5k_px(v_ac2, 'lembrete') is distinct from 'pulado/segurado'
       or pg_temp.f5k_sx(v_s2) is distinct from 'cancelada/segurado' then
      raise exception '7d: segura orcamentos (%, %)', pg_temp.f5k_sx(v_s2), pg_temp.f5k_px(v_ac2, 'lembrete');
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 7b. Só a cadência é barrada: o "Fechado" sai com *segura orcamentos* e com a agenda hoje; recusado pelo canal, o aceite
  --        volta ao cartão com o motivo ──
  begin
    v_pedro := pg_temp.f5k_cli('Pedro Canal F5 Teste', '5547900009933');
    perform pg_temp.f5k_msg('5547900009933', 'Bom dia', c_envio - interval '10 days');
    v_os := pg_temp.f5k_enviado(v_pedro, '5547900009933', 'ORÇ-99433');
    v_aceite := pg_temp.f5k_fechado(v_pedro, '5547900009933', v_os, c_qui - interval '1 hour', c_qui - interval '58 minutes');
    v_s1 := pg_temp.f5k_saida_do_aceite(v_aceite);
    update public.retorno_config set orcamento_segura = true where id;
    perform pg_temp.f5k_agenda(v_pedro, v_os, 'enviada', 'ligado', c_qui - interval '3 hours', c_qui - interval '3 hours');
    v_r := public.orcamento_pegar(c_qui - interval '55 minutes');
    if v_r is null or (v_r ->> 'saida_id')::uuid is distinct from v_s1 or v_r ->> 'tipo' is distinct from 'orc_fechado'
       or v_r ->> 'classe' is distinct from 'resposta_imediata' or v_r ->> 'origem' is distinct from 'retorno_orcamento'
       or v_r ->> 'modo' is distinct from 'sombra' or v_r ->> 'dedupe_key' is distinct from 'orcamento:aceite:' || v_aceite || ':fechado:sombra' then
      raise exception '7b-1: o Fechado com segura e agenda hoje (%)', v_r - 'texto' - 'validador';
    end if;
    if (v_r ->> 'texto' ~ '^Fechado, Pedro! ' and strpos(v_r ->> 'texto', '12/01') > 0) is not true then
      raise exception '7b-2: o texto do Fechado não é o modelo com o nome e o dia do envio';
    end if;
    if (v_r -> 'validador' ->> 'audiencia') is distinct from 'cliente'
       or (v_r -> 'validador' -> 'marcas' ->> 'aceite_registrado')::boolean is not true then
      raise exception '7b-3: o contexto do validador do Fechado';
    end if;
    if pg_temp.f5k_sx(v_s1) is distinct from 'preparada/-' then
      raise exception '7b-4: a reserva do Fechado em sombra (%)', pg_temp.f5k_sx(v_s1);
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;
  begin
    v_pedro := pg_temp.f5k_cli('Pedro Canal F5 Teste', '5547900009933');
    perform pg_temp.f5k_msg('5547900009933', 'Bom dia', c_envio - interval '10 days');
    v_os := pg_temp.f5k_enviado(v_pedro, '5547900009933', 'ORÇ-99433');
    update public.retorno_config set aceite_modo = 'cartao' where id;
    v_aceite := pg_temp.f5k_fechado(v_pedro, '5547900009933', v_os, c_qui - interval '1 hour', c_qui - interval '58 minutes');
    v_s1 := pg_temp.f5k_saida_do_aceite(v_aceite);
    -- O canal recusa (teto das respostas zerado: teto_dia, que a tabela de-para leva a 'canal').
    update public.retorno_config set respostas_dia_max = 0 where id;
    if public.orcamento_pegar(c_qui - interval '55 minutes') is not null then
      raise exception '7b-5: o Fechado recusado pelo canal foi devolvido';
    end if;
    select * into v_ac_row from public.orcamento_aceites a where a.id = v_aceite;
    if pg_temp.f5k_sx(v_s1) is distinct from 'recusada/canal' or v_ac_row.resultado ->> 'saida_nao_saiu' is distinct from 'canal'
       or v_ac_row.resultado ->> 'saida_nao_saiu_tipo' is distinct from 'orc_fechado' or v_ac_row.estado is distinct from 'sem_sinal' then
      raise exception '7b-6: o Fechado recusado (%, %)', pg_temp.f5k_sx(v_s1), v_ac_row.resultado;
    end if;
    if not exists (select 1 from public._orcamento_cartao_aceites(c_qui) x where x.aceite_id = v_aceite and x.tipo_item = 'aceite') then
      raise exception '7b-7: o aceite do Fechado que não saiu não voltou à lista do cartão';
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 8. O modo efetivo ──
  begin
    perform pg_temp.f5k_ligar();
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009934', 'ORÇ-99434');
    if (pg_temp.f5k_a(v_ac)).modo is distinct from 'ligado' then
      raise exception '8: o acompanhamento não nasceu ligado';
    end if;
    perform pg_temp.f5k_nivel('sozinho');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sozinho');
    if public._orcamento_modo_efetivo(v_s1, c_qui) is distinct from 'ligado' then
      raise exception '8a: sozinho com tudo ligado deu %', public._orcamento_modo_efetivo(v_s1, c_qui);
    end if;
    update public.retorno_config set modo = 'sombra' where id;
    if public._orcamento_modo_efetivo(v_s1, c_qui) is distinct from 'sombra' then
      raise exception '8b: o retorno em sombra e a saída ligada';
    end if;
    perform pg_temp.f5k_ligar();
    perform pg_temp.f5k_nivel('cartao');
    if public._orcamento_modo_efetivo(v_s1, c_qui) is distinct from 'sombra' then
      raise exception '8c: nivel cartao sem por = sim e a saída ligada';
    end if;
    update public.retorno_saidas s set dados = s.dados || '{"por": "sim"}'::jsonb where s.id = v_s1;
    if public._orcamento_modo_efetivo(v_s1, c_qui) is distinct from 'ligado' then
      raise exception '8d: nivel cartao com por = sim deu sombra';
    end if;
    update public.retorno_config set orcamento_modo = 'sombra' where id;
    if public._orcamento_modo_efetivo(v_s1, c_qui) is distinct from 'sombra' then
      raise exception '8e: a F5 em sombra e a saída ligada';
    end if;
    -- A saída que nasceu em sombra (a chave com :sombra) nunca liga.
    perform pg_temp.f5k_ligar();
    v_s2 := pg_temp.f5k_ag(v_ac, 'vespera', c_seg - interval '1 hour', 'sombra');
    perform pg_temp.f5k_nivel('sozinho');
    if ((pg_temp.f5k_s(v_s2)).dedupe_key ~ ':sombra$') is not true or public._orcamento_modo_efetivo(v_s2, c_seg) is distinct from 'sombra' then
      raise exception '8f: a saída nascida em sombra (%)', (pg_temp.f5k_s(v_s2)).dedupe_key;
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 9. Regressão do retorno_pegar gerado: a cadência (sem caso) e o "Fechado" (com caso) ficam para o orcamento_pegar ──
  begin
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009935', 'ORÇ-99435');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
    v_pedro := pg_temp.f5k_cli('Pedro Canal F5 Teste', '5547900009936');
    perform pg_temp.f5k_msg('5547900009936', 'Bom dia', c_envio - interval '10 days');
    v_os := pg_temp.f5k_enviado(v_pedro, '5547900009936', 'ORÇ-99436');
    v_ab := pg_temp.f5k_caso(v_pedro, '5547900009936', c_qui - interval '3 hours');
    v_aceite := pg_temp.f5k_fechado(v_pedro, '5547900009936', v_os, c_qui - interval '2 hours', c_qui - interval '119 minutes', v_ab);
    v_s2 := pg_temp.f5k_saida_do_aceite(v_aceite);
    if (pg_temp.f5k_s(v_s2)).abertura_id is distinct from v_ab then
      raise exception '9: o Fechado não ficou com o caso';
    end if;
    -- O retorno_pegar roda até esvaziar (o que houver da F1–F3 é dele, e a volta é desfeita no fim do sub-bloco).
    v_n := 0;
    loop
      v_n := v_n + 1;
      exit when public.retorno_pegar(c_qui + interval '5 minutes') is null or v_n >= 40;
    end loop;
    if public.parceiro_pegar(c_qui + interval '5 minutes') is not null then
      raise exception '9a: o parceiro_pegar devolveu algo com a F4 desligada';
    end if;
    if pg_temp.f5k_sx(v_s1) is distinct from 'agendada/-' or pg_temp.f5k_sx(v_s2) is distinct from 'agendada/-'
       or (pg_temp.f5k_s(v_s1)).processando_ate is not null or (pg_temp.f5k_s(v_s2)).processando_ate is not null then
      raise exception '9b: o retorno_pegar ou o parceiro_pegar mexeu na saída do orçamento (%, %)', pg_temp.f5k_sx(v_s1), pg_temp.f5k_sx(v_s2);
    end if;
    -- Uma saída do retorno devida, no mesmo caso: o orcamento_pegar não a devolve.
    insert into public.retorno_saidas (emissor, abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado,
                                       enviar_em, dedupe_key)
    values ('retorno', v_ab, 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', '00009936', '5547900009936', v_pedro, 'sombra',
            'agendada', c_qui - interval '3 hours', 'retorno:teste-f5k-9:' || v_ab)
    returning id into v_s3;
    v_r := public.orcamento_pegar(c_qui + interval '5 minutes');
    v_r2 := public.orcamento_pegar(c_qui + interval '5 minutes');
    if (v_r ->> 'saida_id')::uuid is distinct from v_s2 or (v_r2 ->> 'saida_id')::uuid is distinct from v_s1 then
      raise exception '9c: o orcamento_pegar não pegou as duas, na ordem enviar_em (% / %)', v_r ->> 'saida_id', v_r2 ->> 'saida_id';
    end if;
    if (v_r ->> 'dedupe_key' ~ '^orcamento:') is not true or (v_r2 ->> 'dedupe_key' ~ '^orcamento:') is not true
       or v_r ->> 'origem' is distinct from 'retorno_orcamento' or v_r2 ->> 'origem' is distinct from 'retorno_orcamento'
       or v_r2 ->> 'classe' is distinct from 'comercial' then
      raise exception '9d: o formato do item do orçamento';
    end if;
    if public.orcamento_pegar(c_qui + interval '5 minutes') is not null or pg_temp.f5k_sx(v_s3) is distinct from 'agendada/-' then
      raise exception '9e: o orcamento_pegar pegou a saída do retorno';
    end if;
    -- O filtro do emissor no corpo gerado: o parceiro e o orçamento ficam de fora; a 'fila' não é excluída pelo emissor.
    select p.prosrc into v from pg_proc p where p.oid = 'public.retorno_pegar(timestamptz)'::regprocedure;
    if strpos(v, 'and s.emissor not in (''parceiro'', ''orcamento'')') = 0 or strpos(v, 's.emissor <> ''parceiro''') > 0 then
      raise exception '9f: o filtro do emissor do retorno_pegar gerado (risco A-8)';
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 9b. Cada motivo do canal grava sem 23514: a saída recusada, o passo pulado com o mesmo motivo, e a próxima saída da fila
  --        pega na mesma chamada (o canal falso responde pelo telefone; o resto passa) ──
  begin
    create or replace function public.canal_pode_enviar(p_fone text, p_classe text, p_origem text,
                                                        p_agora timestamptz default now(),
                                                        p_simular boolean default false,
                                                        p_tipo text default null)
    returns jsonb
    language plpgsql
    stable
    security definer
    set search_path = public
    as $falso$
    declare
      v_f record;
    begin
      select f.motivo, f.enviar_em into v_f from pg_temp.f5k_canal_falso f where f.fone = p_fone;
      if found then
        return jsonb_build_object('pode', false, 'motivo', v_f.motivo, 'enviar_em', v_f.enviar_em);
      end if;
      return jsonb_build_object('pode', true, 'motivo', null, 'enviar_em', null);
    end;
    $falso$;
    foreach v_motivo in array c_motivos_canal loop
      begin
        v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009937', 'ORÇ-99437');
        v_ac2 := pg_temp.f5k_cad('João Canal F5 Teste', '5547900009938', 'ORÇ-99438');
        v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
        v_s2 := pg_temp.f5k_ag(v_ac2, 'lembrete', c_qui - interval '1 hour', 'sombra');
        update public.retorno_saidas s set enviar_em = c_qui - interval '1 minute' where s.id = v_s1;
        delete from pg_temp.f5k_canal_falso where fone is not null;
        insert into pg_temp.f5k_canal_falso (fone, motivo, enviar_em) values ('5547900009937', v_motivo, null);
        v_r := public.orcamento_pegar(c_qui);
        v_esperado := (case when v_motivo = 'motivo_que_ninguem_conhece' then 'canal' else v_motivo end);
        if (v_r ->> 'saida_id')::uuid is distinct from v_s2 then
          raise exception '9b-%: a próxima saída não foi pega na mesma chamada', v_motivo;
        end if;
        if pg_temp.f5k_sx(v_s1) is distinct from 'recusada/' || v_esperado
           or pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'pulado/' || v_esperado then
          raise exception '9b-%: % e %', v_motivo, pg_temp.f5k_sx(v_s1), pg_temp.f5k_px(v_ac, 'lembrete');
        end if;
        if pg_temp.f5k_atrasadas(c_qui) is distinct from 0 then
          raise exception '9b-%: ficou saída agendada no passado', v_motivo;
        end if;
        raise exception 'f5k_motivo' using errcode = 'P0001';
      exception when others then
        if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_motivo' then
          raise;
        end if;
      end;
    end loop;

    -- O texto que falta (o aprovado sem texto) e o cadastro sem nome: recusada, passo pulado, e a próxima segue.
    begin
      delete from pg_temp.f5k_canal_falso where fone is not null;
      v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009937', 'ORÇ-99437');
      v_ac2 := pg_temp.f5k_cad('João Canal F5 Teste', '5547900009938', 'ORÇ-99438');
      v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sim');   -- sem texto_aprovado no passo
      v_s2 := pg_temp.f5k_ag(v_ac2, 'lembrete', c_qui - interval '1 hour', 'sombra');
      update public.retorno_saidas s set enviar_em = c_qui - interval '1 minute' where s.id = v_s1;
      v_r := public.orcamento_pegar(c_qui);
      if (v_r ->> 'saida_id')::uuid is distinct from v_s2 or pg_temp.f5k_sx(v_s1) is distinct from 'recusada/texto'
         or pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'pulado/texto' then
        raise exception '9b-texto: % e %', pg_temp.f5k_sx(v_s1), pg_temp.f5k_px(v_ac, 'lembrete');
      end if;
      raise exception 'f5k_motivo' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_motivo' then
        raise;
      end if;
    end;
    begin
      v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009937', 'ORÇ-99437');
      v_ac2 := pg_temp.f5k_cad('João Canal F5 Teste', '5547900009938', 'ORÇ-99438');
      v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
      v_s2 := pg_temp.f5k_ag(v_ac2, 'lembrete', c_qui - interval '1 hour', 'sombra');
      update public.retorno_saidas s set enviar_em = c_qui - interval '1 minute' where s.id = v_s1;
      -- Empresa sem nome fantasia: _retorno_nome dá nulo (R1-22), e nenhum texto da F5 vai sem nome.
      update public.clients c set type = 'company', display_name = null where c.id = (pg_temp.f5k_a(v_ac)).client_id;
      v_r := public.orcamento_pegar(c_qui);
      if (v_r ->> 'saida_id')::uuid is distinct from v_s2 or pg_temp.f5k_sx(v_s1) is distinct from 'recusada/sem_nome'
         or pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'pulado/sem_nome' then
        raise exception '9b-sem_nome: % e %', pg_temp.f5k_sx(v_s1), pg_temp.f5k_px(v_ac, 'lembrete');
      end if;
      raise exception 'f5k_motivo' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_motivo' then
        raise;
      end if;
    end;

    -- Fora da janela: com abertura hoje, continua agendada com o enviar_em novo; sem abertura, o lembrete vai ao próximo dia
    -- comercial do prazo (sex 15/01 10:00) e a véspera (prazo = o dia) cai.
    begin
      delete from pg_temp.f5k_canal_falso where fone is not null;
      v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009937', 'ORÇ-99437');
      v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
      insert into pg_temp.f5k_canal_falso (fone, motivo, enviar_em) values ('5547900009937', 'fora_da_janela', c_qui + interval '6 hours');
      if public.orcamento_pegar(c_qui) is not null or pg_temp.f5k_sx(v_s1) is distinct from 'agendada/-'
         or (pg_temp.f5k_s(v_s1)).enviar_em is distinct from c_qui + interval '6 hours'
         or pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'agendado/-' then
        raise exception '9b-fora: com abertura hoje (%, %)', pg_temp.f5k_sx(v_s1), (pg_temp.f5k_s(v_s1)).enviar_em;
      end if;
      update pg_temp.f5k_canal_falso set enviar_em = null where fone = '5547900009937';
      update public.retorno_saidas s set enviar_em = c_qui + interval '5 hours' where s.id = v_s1;
      if public.orcamento_pegar(c_qui + interval '6 hours') is not null
         or (pg_temp.f5k_s(v_s1)).enviar_em is distinct from '2027-01-15 10:00-03'::timestamptz then
        raise exception '9b-fora: sem abertura hoje, o lembrete não foi ao próximo dia do prazo (%)', (pg_temp.f5k_s(v_s1)).enviar_em;
      end if;
      update public.orcamento_passos p set estado = 'previsto', saida_id = null
       where p.acompanhamento_id = v_ac and p.passo = 'vespera';
      v_s2 := pg_temp.f5k_ag(v_ac, 'vespera', c_seg - interval '1 hour', 'sombra');
      if public.orcamento_pegar(c_seg) is not null or pg_temp.f5k_sx(v_s2) is distinct from 'cancelada/fora_da_janela'
         or pg_temp.f5k_px(v_ac, 'vespera') is distinct from 'pulado/fora_da_janela' then
        raise exception '9b-fora: a véspera sem abertura (%, %)', pg_temp.f5k_sx(v_s2), pg_temp.f5k_px(v_ac, 'vespera');
      end if;
      if pg_temp.f5k_atrasadas(c_seg) is distinct from 0 then
        raise exception '9b-fora: ficou saída agendada no passado';
      end if;
      raise exception 'f5k_motivo' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_motivo' then
        raise;
      end if;
    end;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 10. A última trava ──
  begin
    perform pg_temp.f5k_ligar();
    perform pg_temp.f5k_nivel('sozinho');
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009939', 'ORÇ-99439');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sozinho');
    v_r := public.orcamento_pegar(c_qui);
    if v_r ->> 'modo' is distinct from 'ligado' or pg_temp.f5k_sx(v_s1) is distinct from 'enviando/-' then
      raise exception '10a: a reserva ligada (%, %)', v_r ->> 'modo', pg_temp.f5k_sx(v_s1);
    end if;
    v_r := public.orcamento_saida_autorizada(v_s1, '5547900009940', c_qui + interval '30 seconds');
    if (v_r ->> 'pode')::boolean is not false or v_r ->> 'motivo' is distinct from 'telefone' then
      raise exception '10b: telefone de outra chave (%)', v_r;
    end if;
    v_r := public.retorno_saida_autorizada(v_s1, '5547900009939', c_qui + interval '30 seconds');
    if (v_r ->> 'pode')::boolean is not true then
      raise exception '10c: pelo retorno_saida_autorizada (T-AUT-1), com tudo certo (%)', v_r;
    end if;
    -- O cliente escreveu entre o pegar e o envio: o acompanhamento parou.
    perform pg_temp.f5k_msg('5547900009939', 'Oi! Vi agora o orçamento', c_qui + interval '40 seconds');
    v_r := public.orcamento_saida_autorizada(v_s1, '5547900009939', c_qui + interval '1 minute');
    if (v_r ->> 'pode')::boolean is not false or v_r ->> 'motivo' is distinct from 'cliente_escreveu' then
      raise exception '10d: o acompanhamento parado entre o pegar e o envio (%)', v_r;
    end if;
    v_r := public.retorno_saida_autorizada(v_s1, '5547900009939', c_qui + interval '1 minute');
    if (v_r ->> 'pode')::boolean is not false then
      raise exception '10e: o retorno_saida_autorizada deixou passar (%)', v_r;
    end if;
    -- A reserva vencida.
    v_r := public.orcamento_saida_autorizada(v_s1, '5547900009939', c_qui + interval '3 minutes');
    if v_r ->> 'motivo' is distinct from 'reserva_vencida' then
      raise exception '10f: a reserva vencida (%)', v_r;
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 11. Os efeitos ──
  begin
    -- 11a. O lembrete aprovado no cartão (por = sim) sai com o texto aprovado e conta a aprovação do dia.
    perform pg_temp.f5k_ligar();
    perform pg_temp.f5k_nivel('cartao');
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009941', 'ORÇ-99441');
    update public.orcamento_passos p set estado = 'aguarda_sim', texto_aprovado = c_texto_aprovado
     where p.acompanhamento_id = v_ac and p.passo = 'lembrete';
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sim');
    v_r := public.orcamento_pegar(c_qui);
    if v_r ->> 'texto' is distinct from c_texto_aprovado or v_r ->> 'variante' is distinct from 'aprovado' or v_r ->> 'modo' is distinct from 'ligado' then
      raise exception '11a: o texto aprovado (%, %)', v_r ->> 'variante', v_r ->> 'modo';
    end if;
    v_r := public.retorno_registrar_decisao(v_s1, 'enviada', '{"provider_message_id": "teste-f5k-11a"}'::jsonb, c_qui + interval '1 minute');
    if (v_r ->> 'ok')::boolean is not true then
      raise exception '11a: a decisão enviada (%)', v_r;
    end if;
    if pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'enviado/-'
       or (date '2027-01-14' = any ((select t.aprovados_dias from public.retorno_modelo_tipos t where t.tipo = 'orc_lembrete')::date[])) is not true then
      raise exception '11a: o passo e a aprovação do dia (%)', pg_temp.f5k_px(v_ac, 'lembrete');
    end if;
    if (pg_temp.f5k_s(v_s1)).letra is not null then
      raise exception '11a: o aprovado ganhou letra do "Mandei sozinho"';
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;
  begin
    -- 11b. O sozinho enviado ganha a letra (Z a V) e soma envios_sozinho.
    perform pg_temp.f5k_ligar();
    perform pg_temp.f5k_nivel('sozinho');
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009942', 'ORÇ-99442');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sozinho');
    select t.envios_sozinho into v_n from public.retorno_modelo_tipos t where t.tipo = 'orc_lembrete';
    v_r := public.orcamento_pegar(c_qui);
    v_r := public.retorno_registrar_decisao(v_s1, 'enviada', '{}'::jsonb, c_qui + interval '1 minute');
    v_s := pg_temp.f5k_s(v_s1);
    if v_s.letra is null or v_s.letra_dia is distinct from date '2027-01-14'
       or (select t.envios_sozinho from public.retorno_modelo_tipos t where t.tipo = 'orc_lembrete') is distinct from v_n + 1
       or coalesce((v_s.dados ->> 'sozinho')::boolean, false) is not true then
      raise exception '11b: a letra do sozinho (%, %)', v_s.letra, v_s.letra_dia;
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;
  begin
    -- 11c. O encerramento enviado encerra; com encerrar_marca_perdido, rejected/sumiu com audit_log, e o acompanhamento continua
    --      encerrado (nenhum 23514); a marca efeitos_f5 entra, e o bloco 8 do vigia não volta a ela.
    perform pg_temp.f5k_ligar();
    perform pg_temp.f5k_nivel('sozinho');
    update public.retorno_config set encerrar_marca_perdido = true where id;
    v_ac := pg_temp.f5k_cad('Pedro Canal F5 Teste', '5547900009943', 'ORÇ-99443');
    v_a := pg_temp.f5k_a(v_ac);
    v_s1 := pg_temp.f5k_ag(v_ac, 'encerramento', c_qua - interval '1 hour', 'sozinho');
    v_r := public.orcamento_pegar(c_qua);
    if v_r ->> 'tipo' is distinct from 'orc_encerramento' or v_r ->> 'modo' is distinct from 'ligado' then
      raise exception '11c: o encerramento não foi pego ligado (%)', v_r - 'texto' - 'validador';
    end if;
    v_r := public.retorno_registrar_decisao(v_s1, 'enviada', '{}'::jsonb, c_qua + interval '1 minute');
    v_a := pg_temp.f5k_a(v_ac);
    if v_a.estado is distinct from 'encerrado' or v_a.encerramento is distinct from 'enviado' or v_a.desfecho_proposto is distinct from 'sumiu' then
      raise exception '11c: o acompanhamento (%, %)', v_a.estado, v_a.encerramento;
    end if;
    if (select so.quote_status || '/' || coalesce(so.motivo_perda, '-') || '/' || coalesce(so.motivo_perda_por, '-')
          from public.service_orders so where so.id = v_a.service_order_id) is distinct from 'rejected/sumiu/cadencia' then
      raise exception '11c: o orçamento não ficou perdido (sumiu) pela cadência';
    end if;
    if not exists (select 1 from public.audit_log l
                    where l.table_name = 'service_orders' and l.record_id = v_a.service_order_id
                      and l.new_value ->> 'motivo_perda' = 'sumiu' and l.previous_value ->> 'quote_status' = 'sent') then
      raise exception '11c: sem audit_log do perdido';
    end if;
    if ((pg_temp.f5k_s(v_s1)).dados ? 'efeitos_f5') is not true then
      raise exception '11c: sem a marca efeitos_f5';
    end if;
    v_r := public.orcamento_vigia(c_qua + interval '5 minutes');
    if (v_r ->> 'efeitos')::integer is distinct from 0 or (pg_temp.f5k_a(v_ac)).estado is distinct from 'encerrado' then
      raise exception '11c: o bloco 8 do vigia voltou à saída (%)', v_r -> 'efeitos';
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;
  begin
    -- 11d. O "Fechado" enviado: com caso, o caso fica cumprido; sem caso, só saida_fechado_id.
    perform pg_temp.f5k_ligar();
    update public.retorno_config set aceite_modo = 'cartao' where id;
    v_pedro := pg_temp.f5k_cli('Pedro Canal F5 Teste', '5547900009944');
    perform pg_temp.f5k_msg('5547900009944', 'Bom dia', c_envio - interval '10 days');
    v_os := pg_temp.f5k_enviado(v_pedro, '5547900009944', 'ORÇ-99444');
    v_ab := pg_temp.f5k_caso(v_pedro, '5547900009944', c_qui - interval '3 hours');
    v_aceite := pg_temp.f5k_fechado(v_pedro, '5547900009944', v_os, c_qui - interval '2 hours', c_qui - interval '119 minutes', v_ab);
    v_s1 := pg_temp.f5k_saida_do_aceite(v_aceite);
    v_r := public.orcamento_pegar(c_qui - interval '118 minutes');
    if v_r ->> 'modo' is distinct from 'ligado' then
      raise exception '11d: o Fechado não foi pego ligado (%)', v_r ->> 'modo';
    end if;
    v_r := public.retorno_registrar_decisao(v_s1, 'enviada', '{}'::jsonb, c_qui - interval '117 minutes');
    select * into v_ac_row from public.orcamento_aceites a where a.id = v_aceite;
    if v_ac_row.saida_fechado_id is distinct from v_s1 or v_ac_row.resultado ? 'saida_nao_saiu'
       or (select a.cumprida_por from public.retorno_aberturas a where a.id = v_ab) is distinct from 'cartao' then
      raise exception '11d: o Fechado com caso (%)', v_ac_row.resultado;
    end if;
    -- Sem caso.
    v_joao := pg_temp.f5k_cli('João Canal F5 Teste', '5547900009945');
    perform pg_temp.f5k_msg('5547900009945', 'Bom dia', c_envio - interval '10 days');
    v_os2 := pg_temp.f5k_enviado(v_joao, '5547900009945', 'ORÇ-99445');
    update public.retorno_config set proximo_envio_em = null where id;
    v_aceite := pg_temp.f5k_fechado(v_joao, '5547900009945', v_os2, c_qui - interval '1 hour', c_qui - interval '59 minutes');
    v_s2 := pg_temp.f5k_saida_do_aceite(v_aceite);
    v_r := public.orcamento_pegar(c_qui - interval '58 minutes');
    v_r := public.retorno_registrar_decisao(v_s2, 'enviada', '{}'::jsonb, c_qui - interval '57 minutes');
    select * into v_ac_row from public.orcamento_aceites a where a.id = v_aceite;
    if v_ac_row.saida_fechado_id is distinct from v_s2 or v_ac_row.abertura_id is not null then
      raise exception '11d: o Fechado sem caso';
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 12. A chave de sombra ──
  begin
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009946', 'ORÇ-99446');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
    if (pg_temp.f5k_s(v_s1)).dedupe_key is distinct from 'orcamento:' || v_ac || ':lembrete:1:sombra' then
      raise exception '12a: a chave do passo agendado em sombra (%)', (pg_temp.f5k_s(v_s1)).dedupe_key;
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;
  begin
    -- O agendado ligado que o orcamento_pegar decide em sombra (o retorno em sombra) é reservado com ':sombra'.
    perform pg_temp.f5k_ligar();
    perform pg_temp.f5k_nivel('sozinho');
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009946', 'ORÇ-99446');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sozinho');
    if (pg_temp.f5k_s(v_s1)).dedupe_key is distinct from 'orcamento:' || v_ac || ':lembrete:1' then
      raise exception '12b: a chave do agendado ligado (%)', (pg_temp.f5k_s(v_s1)).dedupe_key;
    end if;
    update public.retorno_config set modo = 'sombra' where id;
    v_r := public.orcamento_pegar(c_qui);
    if v_r ->> 'dedupe_key' is distinct from 'orcamento:' || v_ac || ':lembrete:1:sombra' or v_r ->> 'modo' is distinct from 'sombra'
       or exists (select 1 from public.retorno_saidas s where s.dedupe_key = 'orcamento:' || v_ac || ':lembrete:1') then
      raise exception '12b: a reserva em sombra não trocou a chave (%)', v_r ->> 'dedupe_key';
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 12b. O estado da reserva, com o espião do canal (o p_simular de cada chamada) ──
  begin
    create or replace function public.canal_pode_enviar(p_fone text, p_classe text, p_origem text,
                                                        p_agora timestamptz default now(),
                                                        p_simular boolean default false,
                                                        p_tipo text default null)
    returns jsonb
    language plpgsql
    volatile
    security definer
    set search_path = public
    as $espiao$
    begin
      insert into pg_temp.f5k_espiao (fone, classe, origem, simular) values (p_fone, p_classe, p_origem, p_simular);
      return jsonb_build_object('pode', true, 'motivo', null, 'enviar_em', null);
    end;
    $espiao$;
    -- Tudo ligado: enviando, ligado, a reserva de 2 minutos, o espaçamento andou, e o canal real (p_simular falso).
    perform pg_temp.f5k_ligar();
    perform pg_temp.f5k_nivel('sozinho');
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009947', 'ORÇ-99447');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sozinho');
    delete from pg_temp.f5k_espiao where fone is not null;
    v_r := public.orcamento_pegar(c_qui);
    v_s := pg_temp.f5k_s(v_s1);
    if v_s.estado is distinct from 'enviando' or v_s.modo is distinct from 'ligado' or v_s.processando_ate is distinct from c_qui + interval '2 minutes'
       or (select c.proximo_envio_em from public.retorno_config c where c.id) is null
       or (select c.proximo_envio_em from public.retorno_config c where c.id) <= c_qui then
      raise exception '12b-1: a reserva ligada (%, %, %)', v_s.estado, v_s.modo, v_s.processando_ate;
    end if;
    if (select count(*) from pg_temp.f5k_espiao e where e.fone = '5547900009947' and e.simular is false
                                                      and e.classe = 'comercial' and e.origem = 'retorno_orcamento') is distinct from 1::bigint then
      raise exception '12b-2: ligada, o canal não foi chamado com p_simular falso';
    end if;
    v_r := public.retorno_registrar_decisao(v_s1, 'enviada', '{}'::jsonb, c_qui + interval '1 minute');
    if (v_r ->> 'ok')::boolean is not true or pg_temp.f5k_sx(v_s1) is distinct from 'enviada/-' then
      raise exception '12b-3: a decisão enviada da reserva ligada (%)', v_r;
    end if;
    -- O retorno em sombra: preparada, sombra, o espaçamento não muda, e o canal simula.
    update public.retorno_config set modo = 'sombra', proximo_envio_em = null where id;
    v_ac2 := pg_temp.f5k_cad('João Canal F5 Teste', '5547900009948', 'ORÇ-99448');
    v_s2 := pg_temp.f5k_ag(v_ac2, 'lembrete', c_qui - interval '1 hour', 'sozinho');
    v_r := public.orcamento_pegar(c_qui);
    v_s := pg_temp.f5k_s(v_s2);
    if v_s.estado is distinct from 'preparada' or v_s.modo is distinct from 'sombra' or v_s.processando_ate is distinct from c_qui + interval '2 minutes'
       or (select c.proximo_envio_em from public.retorno_config c where c.id) is not null then
      raise exception '12b-4: a reserva em sombra (%, %)', v_s.estado, v_s.modo;
    end if;
    if (select count(*) from pg_temp.f5k_espiao e where e.fone = '5547900009948' and e.simular is true) is distinct from 1::bigint then
      raise exception '12b-5: em sombra, o canal não foi chamado com p_simular verdadeiro';
    end if;
    v_r := public.retorno_registrar_decisao(v_s2, 'sombra', '{}'::jsonb, c_qui + interval '1 minute');
    if (v_r ->> 'ok')::boolean is not true or pg_temp.f5k_sx(v_s2) is distinct from 'sombra/-' or pg_temp.f5k_px(v_ac2, 'lembrete') is distinct from 'sombra/-' then
      raise exception '12b-6: a decisão sombra (%)', v_r;
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 13. Os efeitos que faltaram (bloco 8 do orcamento_vigia): a saída que o retorno_vigia decidiu sozinho ──
  begin
    -- 13a. A enviando presa que o passo 9 do retorno_vigia passa a incerta: o passo vai a enviado; a 2ª rodada não faz nada.
    perform pg_temp.f5k_ligar();
    perform pg_temp.f5k_nivel('sozinho');
    v_ac := pg_temp.f5k_cad('Ana Canal F5 Teste', '5547900009949', 'ORÇ-99449');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sozinho');
    v_r := public.orcamento_pegar(c_qui);
    update public.retorno_saidas s set estado = 'incerta', processando_ate = null where s.id = v_s1 and s.estado = 'enviando';
    v_r := public.orcamento_vigia(c_qui + interval '10 minutes');
    if (v_r ->> 'efeitos')::integer is distinct from 1 or pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'enviado/-'
       or ((pg_temp.f5k_s(v_s1)).dados ? 'efeitos_f5') is not true or (pg_temp.f5k_s(v_s1)).letra is null then
      raise exception '13a: a incerta pelo bloco 8 (%, %)', v_r -> 'efeitos', pg_temp.f5k_px(v_ac, 'lembrete');
    end if;
    v_t := ((pg_temp.f5k_s(v_s1)).dados ->> 'efeitos_f5')::timestamptz;
    v_r := public.orcamento_vigia(c_qui + interval '15 minutes');
    if (v_r ->> 'efeitos')::integer is distinct from 0 or ((pg_temp.f5k_s(v_s1)).dados ->> 'efeitos_f5')::timestamptz is distinct from v_t then
      raise exception '13a: a 2ª rodada voltou à saída (%)', v_r -> 'efeitos';
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;
  begin
    -- 13b. A preparada presa duas vezes (recusada/erro pelo retorno_vigia): o passo fica pulado/erro.
    v_ac := pg_temp.f5k_cad('João Canal F5 Teste', '5547900009949', 'ORÇ-99449');
    v_s1 := pg_temp.f5k_ag(v_ac, 'lembrete', c_qui - interval '1 hour', 'sombra');
    v_r := public.orcamento_pegar(c_qui);
    update public.retorno_saidas s set estado = 'recusada', motivo = 'erro', processando_ate = null where s.id = v_s1 and s.estado = 'preparada';
    v_r := public.orcamento_vigia(c_qui + interval '10 minutes');
    if pg_temp.f5k_px(v_ac, 'lembrete') is distinct from 'pulado/erro' then
      raise exception '13b: a preparada presa (%)', pg_temp.f5k_px(v_ac, 'lembrete');
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;
  begin
    -- 13c. O "Fechado" incerto: saida_nao_saiu = incerta, e o caso cumprido.
    perform pg_temp.f5k_ligar();
    update public.retorno_config set aceite_modo = 'cartao' where id;
    v_pedro := pg_temp.f5k_cli('Pedro Canal F5 Teste', '5547900009949');
    perform pg_temp.f5k_msg('5547900009949', 'Bom dia', c_envio - interval '10 days');
    v_os := pg_temp.f5k_enviado(v_pedro, '5547900009949', 'ORÇ-99449');
    v_ab := pg_temp.f5k_caso(v_pedro, '5547900009949', c_qui - interval '3 hours');
    v_aceite := pg_temp.f5k_fechado(v_pedro, '5547900009949', v_os, c_qui - interval '2 hours', c_qui - interval '119 minutes', v_ab);
    v_s1 := pg_temp.f5k_saida_do_aceite(v_aceite);
    v_r := public.orcamento_pegar(c_qui - interval '118 minutes');
    update public.retorno_saidas s set estado = 'incerta', processando_ate = null where s.id = v_s1 and s.estado = 'enviando';
    v_r := public.orcamento_vigia(c_qui);
    select * into v_ac_row from public.orcamento_aceites a where a.id = v_aceite;
    if v_ac_row.resultado ->> 'saida_nao_saiu' is distinct from 'incerta' or v_ac_row.saida_fechado_id is distinct from v_s1
       or (select a.cumprida_por from public.retorno_aberturas a where a.id = v_ab) is distinct from 'cartao' then
      raise exception '13c: o Fechado incerto (%)', v_ac_row.resultado;
    end if;
    raise exception 'f5k_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5k_cenario' then
      raise;
    end if;
  end;

  -- ── 14. As funções novas: SECURITY DEFINER com search_path; só orcamento_pegar e orcamento_saida_autorizada abertas à
  --        service_role; as geradas com os grants de antes; nenhuma aberta a anon ou authenticated ──
  foreach v in array c_novas loop
    for v_rec in
      select p.oid, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v
    loop
      v_n_fun := v_n_fun + 1;
      if v_rec.prosecdef is not true or not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
        raise exception '14a: % não é SECURITY DEFINER com search_path', v_rec.nome;
      end if;
      if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
        raise exception '14b: % aberta a anon ou authenticated', v_rec.nome;
      end if;
      -- A interna leva só o revoke (spec, regras gerais): no Supabase a service_role tem EXECUTE pelo padrão do esquema,
      -- como todas as _retorno_*/_parceiro_* em produção (conferido 13/11). O que se exige é a pública aberta a ela.
      if v = any (c_publicas) and not has_function_privilege('service_role', v_rec.oid, 'execute') then
        raise exception '14c: o grant da service_role em %', v_rec.nome;
      end if;
    end loop;
  end loop;
  if v_n_fun is distinct from 6 then
    raise exception '14d: achei % das 6 funções novas', v_n_fun;
  end if;
  for v_rec in
    select x.f, x.servico, p.oid
      -- servico = o grant da service_role em produção antes da F5 (13/11: a interna _retorno_janela também tem, pelo padrão)
      from (values ('public._retorno_janela(text, timestamptz, text)', true),
                   ('public.canal_pode_enviar(text, text, text, timestamptz, boolean, text)', true),
                   ('public.retorno_pegar(timestamptz)', true),
                   ('public.retorno_saida_autorizada(uuid, text, timestamptz)', true),
                   ('public.retorno_registrar_decisao(uuid, text, jsonb, timestamptz)', true)) as x(f, servico)
      join pg_proc p on p.oid = to_regprocedure(x.f)
  loop
    if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute')
       or has_function_privilege('service_role', v_rec.oid, 'execute') is distinct from v_rec.servico then
      raise exception '14e: os grants de %', v_rec.f;
    end if;
  end loop;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_canal', true, '{}');
end
$canal$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
