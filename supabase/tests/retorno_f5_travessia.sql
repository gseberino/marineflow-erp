-- Retorno F5 (P14): a travessia do orçamento depois do envio, de ponta a ponta, pelas portas reais: orcamento_validade_do_envio
-- e orcamento_registrar_envio (o envio), orcamento_detectar_envio (o aparelho), orcamento_vigia (acompanhar, parar, o dia, o
-- prazo, o aceite e os dados), retorno_abrir (a mensagem do cliente na F1), retorno_cartao_abrir, retorno_decidir_dito e
-- retorno_cartao_executar (o cartão, a letra e o *sim*), orcamento_pegar, retorno_saida_autorizada e retorno_registrar_decisao
-- (a volta da edge), orcamento_aceite_registrar (a parte de TS do *1 B*, simulada), orcamento_dito (*segura*, *solta*,
-- *motivo*), orcamento_resumo_fechamento e orcamento_avisados (a tarde) e canal_pode_enviar (o teto). Os 21 cenários da P14, um
-- sub-bloco cada (raise 'f5t_cenario'), e o 1x (o encerramento com encerrar_marca_perdido). A outra metade (os leitores da
-- matriz 7.2, a camada sem modelo e o isolamento de _shared/orcamento/) é o CI: _shared/orcamento/travessia_test.ts.
-- Roda só pela bancada (grupo 8, F5_ONDA=9), de madrugada e como teste global (o prelúdio fecha os casos reais e cancela as
-- saídas pendentes reais até o rollback: o cartão lê o banco inteiro). Termina em ROLLBACK. Só confere as próprias linhas
-- sintéticas: telefones inventados 55479000099xx (a chave sai do telefone: 000099xx), nomes inventados (Ana, João, Pedro),
-- documentos inventados (ORÇ-999xx e OS-999xx), frases inventadas. Nenhuma mensagem real é lida. O *sim 7391* chega ao banco
-- como retorno_cartao_executar(cartão, dono): o PIN é conferido no TS antes; aqui ele nunca é lido nem comparado. O id do dono
-- vem de _comprovante_dono (só o id e o telefone, para a sessão).
-- Relógio fixo, o C8 da spec deslocado para jan/2027 com a mesma conta de dias (a do teste da cadência): o orçamento vai na
-- ter 12/01/2027 10:00 com validade ter 19/01 (lembrete qui 14/01, até sex 15/01; véspera seg 18/01; encerramento qua 20/01,
-- até sex 22/01). O retorno_abrir grava processada_em = now() (a hora da transação): o teste a põe na hora da mensagem.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f5t_cli(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

-- Uma mensagem inventada (recebida, por padrão), com a hora real igual à de gravação.
create or replace function pg_temp.f5t_msg(p_fone text, p_corpo text, p_em timestamptz, p_direcao text default 'inbound',
                                           p_tipo text default 'text') returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real,
                                        occurred_at)
  values (p_direcao, p_fone, p_tipo, p_corpo, case when p_direcao = 'inbound' then 'received' else 'sent' end,
          '{"data": {}}'::jsonb, p_em, p_em)
  returning id
$f$;

-- A mensagem do cliente pela porta da F1 (retorno_abrir: o caso, ou abertura nula no só agradecimento sem caso vivo), com a
-- hora de processamento posta na hora da mensagem. Devolve o id da mensagem.
create or replace function pg_temp.f5t_cliente_diz(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_m uuid;
begin
  v_m := pg_temp.f5t_msg(p_fone, p_corpo, p_em);
  perform public.retorno_abrir(v_m, false, p_em);
  update public.retorno_mensagens set processada_em = p_em where whatsapp_message_id = v_m;
  if not found then
    raise exception 'f5t_cliente_diz: o retorno_abrir não gravou a mensagem em retorno_mensagens';
  end if;
  return v_m;
end $f$;

-- O PDF que saiu do aparelho do dono (eco: data, sem via).
create or replace function pg_temp.f5t_eco(p_fone text, p_arquivo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, raw_payload, occurred_at, hora_real)
  values ('outbound', p_fone, 'document', null, 'teste-f5-travessia-' || md5(p_fone || p_arquivo || p_em::text),
          jsonb_build_object('data', jsonb_build_object('source', 'unknown', 'message',
                                                        jsonb_build_object('documentMessage', jsonb_build_object('fileName', p_arquivo)))),
          p_em, p_em)
  returning id
$f$;

-- O orçamento em rascunho, criado 2 dias antes de p_em.
create or replace function pg_temp.f5t_orc(p_cliente uuid, p_numero text, p_em timestamptz,
                                           p_desc text default 'Instalação de energia solar', p_total numeric default 9840) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || p_numero || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, problem_description,
                                     created_at, updated_at, grand_total, quote_validity_days)
  values (p_numero, p_cliente, v_v, 'draft', 'draft', 'repair', p_desc, p_em - interval '2 days', p_em - interval '2 days', p_total, 7)
  returning id into v_id;
  return v_id;
end $f$;

-- O envio pelo sistema (tela, assistente ou cartão): a validade contada do envio (K6, 1 minuto antes), o funil em sent com a
-- via e a chave (o que o whatsapp-send faz) e o registro do envio. Devolve a resposta da validade.
create or replace function pg_temp.f5t_enviar(p_os uuid, p_fone text, p_em timestamptz, p_via text default 'tela') returns jsonb
language plpgsql as $f$
declare
  v_r jsonb;
  v_reg jsonb;
begin
  v_r := public.orcamento_validade_do_envio(p_os, p_em - interval '1 minute');
  update public.service_orders
     set quote_status = 'sent', orcamento_enviado_em = p_em, orcamento_enviado_via = p_via,
         orcamento_enviado_chave = public._agenda_chave_telefone(p_fone)
   where id = p_os;
  v_reg := public.orcamento_registrar_envio(p_os, p_via, public._agenda_chave_telefone(p_fone), true, p_em);
  if (v_reg ->> 'ok')::boolean is not true then
    raise exception 'f5t_enviar: o registro do envio (%)', v_reg;
  end if;
  return v_r;
end $f$;

-- O cliente que conversou (uma mensagem dez dias antes) com o orçamento enviado a ele pela tela.
create or replace function pg_temp.f5t_pronto(p_nome text, p_fone text, p_numero text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_c uuid;
  v_os uuid;
begin
  v_c := pg_temp.f5t_cli(p_nome, p_fone);
  perform pg_temp.f5t_msg(p_fone, 'Bom dia, tudo bem?', p_em - interval '10 days');
  v_os := pg_temp.f5t_orc(v_c, p_numero, p_em);
  perform pg_temp.f5t_enviar(v_os, p_fone, p_em);
  return v_os;
end $f$;

create or replace function pg_temp.f5t_a(p_os uuid) returns public.orcamento_acompanhamentos
language sql as $f$
  select a from public.orcamento_acompanhamentos a where a.service_order_id = p_os
$f$;

-- "estado/motivo" do passo do orçamento.
create or replace function pg_temp.f5t_px(p_os uuid, p_passo text) returns text
language sql as $f$
  select p.estado || '/' || coalesce(p.motivo, '-')
    from public.orcamento_passos p join public.orcamento_acompanhamentos a on a.id = p.acompanhamento_id
   where a.service_order_id = p_os and p.passo = p_passo
$f$;

-- O calendário: "passo:dia:ate", na ordem do dia.
create or replace function pg_temp.f5t_cal(p_os uuid) returns text
language sql as $f$
  select coalesce(string_agg(p.passo || ':' || to_char(p.dia, 'YYYY-MM-DD') || ':' || to_char(p.ate, 'YYYY-MM-DD'), ',' order by p.dia), '')
    from public.orcamento_passos p join public.orcamento_acompanhamentos a on a.id = p.acompanhamento_id
   where a.service_order_id = p_os
$f$;

-- As saídas do orçamento à chave, em texto: "tipo:estado", na ordem de enviar_em (criada_em é a hora da transação, a
-- mesma em todas).
create or replace function pg_temp.f5t_saidas(p_chave text) returns text
language sql as $f$
  select coalesce(string_agg(s.tipo || ':' || s.estado, ',' order by s.enviar_em, s.tipo), '')
    from public.retorno_saidas s where s.emissor = 'orcamento' and s.chave = p_chave
$f$;

-- A configuração de cada cenário: o retorno no modo dado, a F5 ligada com o cartão, os 3 tipos da cadência no nível dado, o
-- resto no padrão seguro (dúvidas 1, 3, 7 e 8), as marcas d'água em 01/01/2027 e a janela do K7.
create or replace function pg_temp.f5t_ligar(p_modo text, p_nivel text) returns void
language plpgsql as $f$
begin
  update public.retorno_config
     set modo = p_modo, tipos_ligados = '{}', cartao_ligado = true, cartao_max_itens = 3, carona_ligada = false, carona_em = null,
         meio_dia_ligado = false, previa_modo = 'desligado', previa_ditado_ligado = false, orcamento_modo = 'ligado',
         validade_envio_ligada = true, aceite_modo = 'cartao', aceite_audio = false, dados_nota_ligado = false,
         orcamento_segura = false, encerrar_marca_perdido = false, motivo_marca_aberto = false, envio_mao_modo = 'desligado',
         orcamento_envio_ate = '2027-01-01 00:00-03', orcamento_aceite_ate = '2027-01-01 00:00-03', cadencia_hora = '10:00',
         cadencia_inicio = '09:00', cadencia_fim = '17:00', segura_tudo_ate = null, so_reativo = false, proximo_envio_em = null,
         parceiro_modo = 'desligado'
   where id;
  update public.retorno_modelo_tipos set nivel = p_nivel where tipo in ('orc_lembrete', 'orc_vespera', 'orc_encerramento');
end $f$;

create or replace function pg_temp.f5t_limpar() returns void
language sql as $f$
  update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
  update public.retorno_cartoes set estado = 'decidido', decidido_em = now(), decidido_por = 'nao' where estado = 'vivo';
$f$;

-- O cartão vivo, aberto pelo *retorno*.
create or replace function pg_temp.f5t_cartao(p_agora timestamptz) returns uuid
language plpgsql as $f$
declare
  v_r jsonb;
begin
  perform pg_temp.f5t_limpar();
  v_r := public.retorno_cartao_abrir('puxar', p_agora);
  if v_r ->> 'acao' is distinct from 'cartao' then
    raise exception 'o cartão não abriu: %', v_r;
  end if;
  return (v_r ->> 'cartao_id')::uuid;
end $f$;

create or replace function pg_temp.f5t_dito(p_cmd jsonb, p_agora timestamptz) returns jsonb
language sql as $f$
  select public.retorno_decidir_dito(p_cmd, (select d.id from public._comprovante_dono() d), p_agora)
$f$;

-- O *sim 7391*: o TS confere o PIN e chama a execução com o dono.
create or replace function pg_temp.f5t_sim(p_cartao uuid, p_agora timestamptz) returns jsonb
language sql as $f$
  select public.retorno_cartao_executar(p_cartao, (select d.id from public._comprovante_dono() d), p_agora)
$f$;

create or replace function pg_temp.f5t_item_passo(p_cartao uuid, p_os uuid, p_passo text) returns public.retorno_cartao_itens
language sql as $f$
  select i from public.retorno_cartao_itens i
    join public.orcamento_passos p on p.id = i.passo_id
    join public.orcamento_acompanhamentos a on a.id = p.acompanhamento_id
   where i.cartao_id = p_cartao and a.service_order_id = p_os and p.passo = p_passo
$f$;

create or replace function pg_temp.f5t_item_aceite(p_cartao uuid, p_aceite uuid, p_tipo text default 'aceite') returns public.retorno_cartao_itens
language sql as $f$
  select i from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.aceite_id = p_aceite and i.tipo_item = p_tipo
$f$;

create or replace function pg_temp.f5t_ac(p_msg uuid) returns public.orcamento_aceites
language sql as $f$
  select a from public.orcamento_aceites a where a.whatsapp_message_id = p_msg
$f$;

create or replace function pg_temp.f5t_texto(p_cartao uuid) returns text
language sql as $f$
  select c.texto from public.retorno_cartoes c where c.id = p_cartao
$f$;

-- A volta da edge (retorno-recibos → whatsapp-send): o orcamento_pegar, a última trava no instante do envio e a decisão
-- (enviada, se a saída foi pega ligada; sombra, se em sombra). Devolve o item pego, ou nulo.
create or replace function pg_temp.f5t_sair(p_agora timestamptz) returns jsonb
language plpgsql as $f$
declare
  v_item jsonb;
  v_r jsonb;
begin
  v_item := public.orcamento_pegar(p_agora);
  if v_item is null then
    return null;
  end if;
  if v_item ->> 'modo' = 'ligado' then
    v_r := public.retorno_saida_autorizada((v_item ->> 'saida_id')::uuid, v_item ->> 'phone', p_agora + interval '20 seconds');
    if (v_r ->> 'pode')::boolean is not true then
      raise exception 'f5t_sair: a última trava barrou (%)', v_r;
    end if;
    v_r := public.retorno_registrar_decisao((v_item ->> 'saida_id')::uuid, 'enviada',
                                            jsonb_build_object('provider_message_id', 'teste-f5t-' || (v_item ->> 'saida_id')),
                                            p_agora + interval '40 seconds');
  else
    v_r := public.retorno_registrar_decisao((v_item ->> 'saida_id')::uuid, 'sombra', '{}'::jsonb, p_agora + interval '40 seconds');
  end if;
  if (v_r ->> 'ok')::boolean is not true then
    raise exception 'f5t_sair: a decisão (%)', v_r;
  end if;
  return v_item;
end $f$;

-- O dia de um passo no cartão: o vigia às 09:00 (aguarda_sim), o *retorno* às 09:30 (o item do passo), o *sim* às 09:40
-- (agendado para as 10:00) e a saída às 10:00. Devolve o item pego.
create or replace function pg_temp.f5t_dia(p_os uuid, p_passo text, p_dia date) returns jsonb
language plpgsql as $f$
declare
  v_cartao uuid;
  v_i public.retorno_cartao_itens;
  v_item jsonb;
begin
  perform public.orcamento_vigia((p_dia + time '09:00') at time zone 'America/Sao_Paulo');
  if pg_temp.f5t_px(p_os, p_passo) is distinct from 'aguarda_sim/-' then
    raise exception 'f5t_dia: o % não ficou à espera do sim em % (%)', p_passo, p_dia, pg_temp.f5t_px(p_os, p_passo);
  end if;
  v_cartao := pg_temp.f5t_cartao((p_dia + time '09:30') at time zone 'America/Sao_Paulo');
  v_i := pg_temp.f5t_item_passo(v_cartao, p_os, p_passo);
  if v_i.id is null or v_i.tipo_item is distinct from 'cadencia' then
    raise exception 'f5t_dia: o % não entrou no cartão de % (%)', p_passo, p_dia, pg_temp.f5t_texto(v_cartao);
  end if;
  perform pg_temp.f5t_sim(v_cartao, (p_dia + time '09:40') at time zone 'America/Sao_Paulo');
  if pg_temp.f5t_px(p_os, p_passo) is distinct from 'agendado/-' then
    raise exception 'f5t_dia: o % não ficou agendado com o sim (%)', p_passo, pg_temp.f5t_px(p_os, p_passo);
  end if;
  v_item := pg_temp.f5t_sair((p_dia + time '10:00') at time zone 'America/Sao_Paulo');
  if v_item is null or v_item ->> 'tipo' is distinct from 'orc_' || p_passo then
    raise exception 'f5t_dia: a saída do % às 10:00 (%)', p_passo, v_item - 'texto' - 'validador';
  end if;
  return v_item;
end $f$;

-- Uma mensagem da agenda ao cliente (tipo, estado e modo dados), criada em p_criada.
create or replace function pg_temp.f5t_agenda(p_cliente uuid, p_os uuid, p_tipo text, p_estado text, p_modo text, p_enviar timestamptz,
                                              p_enviada timestamptz, p_criada timestamptz) returns uuid
language sql as $f$
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate,
                                               aprovacao, estado, dedupe_key, enviada_em, criada_em)
  values (p_cliente, p_os, p_tipo, 'rodada', p_modo, 'mensagem de teste (F5 travessia)', '{}'::jsonb, p_enviar,
          p_enviar + interval '8 hours', 'livre', p_estado,
          'teste-f5t:' || md5(p_cliente::text || p_estado || p_enviar::text || clock_timestamp()::text || random()::text), p_enviada,
          p_criada)
  returning id
$f$;

-- Uma saída de outra voz à chave (o aviso da F4, a comercial da F5), já enviada.
create or replace function pg_temp.f5t_outra(p_fone text, p_emissor text, p_tipo text, p_origem text, p_classe text, p_em timestamptz)
returns uuid
language sql as $f$
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, estado, enviar_em, decidida_em,
                                     enviada_em, texto, dedupe_key)
  values (p_emissor, p_tipo, p_origem, p_classe, public._agenda_chave_telefone(p_fone), p_fone, 'ligado', 'enviada', p_em, p_em, p_em,
          'mensagem de teste (F5 travessia)',
          p_emissor || ':teste-f5t:' || md5(p_fone || p_em::text || clock_timestamp()::text || random()::text))
  returning id
$f$;

-- A linha da fila que levou o fechamento da tarde (só status e sent_at contam para o vigia).
create or replace function pg_temp.f5t_fila(p_status text, p_sent timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_send_queue (phone_normalized, message, source, status, sent_at)
  values ('5547900009999', 'fechamento da tarde (teste F5 travessia)', 'manual', p_status, p_sent)
  returning id
$f$;

-- A conversão que a ferramenta faz (converter_sem_sinal, via dono), simulada como os testes da P7: o rascunho vira OS.
create or replace function pg_temp.f5t_converter(p_os uuid, p_em timestamptz, p_numero text) returns void
language sql as $f$
  update public.service_orders
     set status = 'open', converted_to_os_at = p_em, service_order_number = p_numero, quote_status = 'approved'
   where id = p_os
$f$;

create or replace function pg_temp.f5t_igual(p_rot text, p_valor text, p_esp text) returns void
language plpgsql as $f$
begin
  if p_valor is distinct from p_esp then
    raise exception '%: %, esperava %', p_rot, coalesce(p_valor, '∅'), coalesce(p_esp, '∅');
  end if;
end $f$;

create or replace function pg_temp.f5t_tem(p_rot text, p_texto text, p_trecho text) returns void
language plpgsql as $f$
begin
  if p_texto is null or strpos(p_texto, p_trecho) = 0 then
    raise exception '%: sem o trecho "%" em: %', p_rot, p_trecho, coalesce(p_texto, '∅');
  end if;
end $f$;

do $travessia$
declare
  c_ter constant timestamptz := '2027-01-12 10:00-03';     -- o envio
  c_val constant date := date '2027-01-19';                 -- ter: vale até
  c_qua constant timestamptz := '2027-01-13 14:05-03';      -- a mensagem do cliente
  v_dono uuid;
  v_phone text;
  v_modo text;
  v_c uuid; v_c2 uuid; v_p uuid; v_pessoa uuid;
  v_os uuid; v_os2 uuid;
  v_m uuid; v_k uuid;
  v_cartao uuid;
  v_i public.retorno_cartao_itens;
  v_a public.orcamento_acompanhamentos;
  v_ac public.orcamento_aceites;
  v_so record;
  v_item jsonb;
  v_r jsonb;
  v_q uuid;
  v_t timestamptz;
  v_n integer;
begin
  begin
  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
  if v_dono is null then
    raise exception '0: sem o dono (_comprovante_dono): o cartão não abre';
  end if;
  update public.ai_operator_sessions set metadata = metadata - 'pendencias_guardadas' where external_thread_key = v_phone;
  perform pg_temp.f5t_limpar();
  -- O calendário não depende de ausência real do dono nem de sábado útil.
  update public.agenda_config set sabado_util = false where id;
  update public.agenda_disponibilidade d
     set substituida_em = now()
   where d.payee_id is null and d.situacao = 'indisponivel' and d.turno is null and d.substituida_em is null
     and d.periodo && daterange(date '2027-01-01', date '2027-02-01');

  -- ── 1. O C8 inteiro: envio ter 12/01 → lembrete no cartão qui 14/01 → *sim* → enviado (o retorno ligado) → véspera seg
  --       18/01 → encerramento qua 20/01 → desfecho conforme encerrar_marca_perdido (o padrão: não marca) ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Ana Travessia F5 Teste', '5547900009901', 'ORÇ-99901', c_ter);
    select so.quote_validity_date, so.orcamento_enviado_em, so.orcamento_enviado_via, so.orcamento_enviado_chave into v_so
      from public.service_orders so where so.id = v_os;
    if v_so.quote_validity_date is distinct from c_val or v_so.orcamento_enviado_em is distinct from c_ter
       or v_so.orcamento_enviado_via is distinct from 'tela' or v_so.orcamento_enviado_chave is distinct from '00009901' then
      raise exception '1a: o envio (K6 e o 1º envio) (%)', row_to_json(v_so);
    end if;
    if (select count(*) from public.orcamento_envios e where e.service_order_id = v_os and e.ao_cliente and e.via = 'tela') is distinct from 1::bigint then
      raise exception '1a: o registro do envio';
    end if;
    v_r := public.orcamento_vigia(c_ter + interval '5 minutes');
    v_a := pg_temp.f5t_a(v_os);
    if v_a.id is null or v_a.estado is distinct from 'ativo' or v_a.modo is distinct from 'ligado' or v_a.validade_ate is distinct from c_val then
      raise exception '1b: o acompanhamento (%)', v_r;
    end if;
    perform pg_temp.f5t_igual('1b o calendário', pg_temp.f5t_cal(v_os),
      'lembrete:2027-01-14:2027-01-15,vespera:2027-01-18:2027-01-18,encerramento:2027-01-20:2027-01-22');
    v_item := pg_temp.f5t_dia(v_os, 'lembrete', date '2027-01-14');
    perform pg_temp.f5t_igual('1c o lembrete', pg_temp.f5t_px(v_os, 'lembrete'), 'enviado/-');
    perform pg_temp.f5t_igual('1c ligado', v_item ->> 'modo', 'ligado');
    v_item := pg_temp.f5t_dia(v_os, 'vespera', date '2027-01-18');
    perform pg_temp.f5t_igual('1d a véspera', pg_temp.f5t_px(v_os, 'vespera'), 'enviado/-');
    v_item := pg_temp.f5t_dia(v_os, 'encerramento', date '2027-01-20');
    perform pg_temp.f5t_igual('1e o encerramento', pg_temp.f5t_px(v_os, 'encerramento'), 'enviado/-');
    v_a := pg_temp.f5t_a(v_os);
    if v_a.estado is distinct from 'encerrado' or v_a.encerramento is distinct from 'enviado' or v_a.desfecho_proposto is distinct from 'sumiu' then
      raise exception '1f: o acompanhamento depois do encerramento (%, %, %)', v_a.estado, v_a.encerramento, v_a.desfecho_proposto;
    end if;
    perform pg_temp.f5t_igual('1g as saídas', pg_temp.f5t_saidas('00009901'),
      'orc_lembrete:enviada,orc_vespera:enviada,orc_encerramento:enviada');
    -- Dúvida 1 sem resposta (encerrar_marca_perdido falso): o orçamento não vira perdido.
    if (select so.quote_status || '/' || coalesce(so.motivo_perda, '-') from public.service_orders so where so.id = v_os) is distinct from 'sent/-' then
      raise exception '1h: o encerramento marcou perdido com a dúvida 1 no padrão';
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;
  -- 1x. Com encerrar_marca_perdido (a dúvida 1 respondida "sim"): o encerramento enviado marca perdido (sumiu, pela cadência),
  --     e o acompanhamento continua encerrado.
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    update public.retorno_config set encerrar_marca_perdido = true where id;
    v_os := pg_temp.f5t_pronto('Pedro Travessia F5 Teste', '5547900009902', 'ORÇ-99902', c_ter);
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    update public.orcamento_passos p set estado = 'enviado'
      from public.orcamento_acompanhamentos a
     where a.id = p.acompanhamento_id and a.service_order_id = v_os and p.passo in ('lembrete', 'vespera');
    perform pg_temp.f5t_dia(v_os, 'encerramento', date '2027-01-20');
    if (select so.quote_status || '/' || coalesce(so.motivo_perda, '-') || '/' || coalesce(so.motivo_perda_por, '-')
          from public.service_orders so where so.id = v_os) is distinct from 'rejected/sumiu/cadencia' then
      raise exception '1x: o encerramento com a dúvida 1 em sim não marcou perdido (sumiu)';
    end if;
    perform pg_temp.f5t_igual('1x o acompanhamento', (pg_temp.f5t_a(v_os)).estado, 'encerrado');
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 2. "ok, obrigado" na qua 13/01: a cadência para (qualquer mensagem, K7), e nada mais sai ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Ana Obrigado F5 Teste', '5547900009903', 'ORÇ-99903', c_ter);
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    v_m := pg_temp.f5t_msg('5547900009903', 'ok, obrigado', '2027-01-13 11:00-03');
    perform public.orcamento_vigia('2027-01-14 09:00-03');
    v_a := pg_temp.f5t_a(v_os);
    if v_a.estado is distinct from 'parado' or v_a.parou_por is distinct from 'cliente_escreveu' or v_a.parou_msg_id is distinct from v_m then
      raise exception '2a: o acompanhamento (%, %)', v_a.estado, v_a.parou_por;
    end if;
    perform pg_temp.f5t_igual('2b o lembrete', pg_temp.f5t_px(v_os, 'lembrete'), 'cancelado/-');
    perform pg_temp.f5t_limpar();
    v_r := public.retorno_cartao_abrir('puxar', '2027-01-14 09:30-03');
    if exists (select 1 from public.retorno_cartao_itens i join public.orcamento_passos p on p.id = i.passo_id
                 join public.orcamento_acompanhamentos a on a.id = p.acompanhamento_id where a.service_order_id = v_os) then
      raise exception '2c: o passo parado entrou no cartão';
    end if;
    if public.orcamento_pegar('2027-01-14 10:00-03') is not null or pg_temp.f5t_saidas('00009903') <> '' then
      raise exception '2d: saiu mensagem depois do "ok, obrigado" (%)', pg_temp.f5t_saidas('00009903');
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 3. "fechei com outra empresa": encerrou, com fechou_com_outro proposto, e nada sai. O fechamento mostra o orçamento
  --       vencido sem desfecho, e *motivo 99904 B* (com motivo_marca_aberto) o marca perdido (fechou com outro) ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Pedro Outra Empresa F5 Teste', '5547900009904', 'ORÇ-99904', c_ter);
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    v_m := pg_temp.f5t_msg('5547900009904', 'Fechei com outra empresa, obrigado', '2027-01-13 11:00-03');
    perform public.orcamento_vigia('2027-01-14 09:00-03');
    v_a := pg_temp.f5t_a(v_os);
    if v_a.estado is distinct from 'parado' or v_a.parou_por is distinct from 'encerrou'
       or v_a.desfecho_proposto is distinct from 'fechou_com_outro' or v_a.parou_msg_id is distinct from v_m then
      raise exception '3a: o acompanhamento (%, %, %)', v_a.estado, v_a.parou_por, v_a.desfecho_proposto;
    end if;
    if public.orcamento_pegar('2027-01-14 10:00-03') is not null or pg_temp.f5t_saidas('00009904') <> '' then
      raise exception '3b: saiu mensagem depois do "fechei com outra empresa"';
    end if;
    v_r := public.orcamento_resumo_fechamento('2027-01-21 17:30-03');
    perform pg_temp.f5t_tem('3c o fechamento', v_r ->> 'linhas', 'Enviados vencidos sem desfecho');
    perform pg_temp.f5t_tem('3c o orçamento', v_r ->> 'linhas', 'ORÇ-99904');
    update public.retorno_config set motivo_marca_aberto = true where id;
    v_r := public.orcamento_dito('{"comando": "motivo", "numero": 99904, "letra": "B"}'::jsonb, v_dono, '2027-01-21 17:40-03');
    if (v_r ->> 'ok')::boolean is not true
       or (select so.quote_status || '/' || coalesce(so.motivo_perda, '-') || '/' || coalesce(so.motivo_perda_por, '-')
             from public.service_orders so where so.id = v_os) is distinct from 'rejected/fechou_com_outro/dono' then
      raise exception '3d: *motivo 99904 B* (%)', v_r;
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 4. PARAR: o opt-out da F0b vale (o número bloqueado), a cadência para, e nada sai ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('João Parar F5 Teste', '5547900009905', 'ORÇ-99905', c_ter);
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    perform pg_temp.f5t_msg('5547900009905', 'PARAR', '2027-01-13 11:00-03');
    if not exists (select 1 from public.whatsapp_blocked_numbers b where public._agenda_chave_telefone(b.phone_normalized) = '00009905')
       or public.canal_bloqueado('5547900009905') is null then
      raise exception '4a: o PARAR não entrou no opt-out da F0b';
    end if;
    perform public.orcamento_vigia('2027-01-14 09:00-03');
    v_a := pg_temp.f5t_a(v_os);
    if v_a.estado is distinct from 'parado' or v_a.parou_por is distinct from 'parar' then
      raise exception '4b: o acompanhamento (%, %)', v_a.estado, v_a.parou_por;
    end if;
    if public.orcamento_pegar('2027-01-14 10:00-03') is not null or pg_temp.f5t_saidas('00009905') <> '' then
      raise exception '4c: saiu mensagem depois do PARAR';
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 5. O dono escreve ao cliente na qua 13/01 (depois da carência de 2 h): dono_falou ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Ana Dono F5 Teste', '5547900009906', 'ORÇ-99906', c_ter);
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    v_m := pg_temp.f5t_msg('5547900009906', 'Ana, conseguiu ver o orçamento?', '2027-01-13 15:00-03', 'outbound');
    perform public.orcamento_vigia('2027-01-14 09:00-03');
    v_a := pg_temp.f5t_a(v_os);
    if v_a.estado is distinct from 'parado' or v_a.parou_por is distinct from 'dono_falou' or v_a.parou_msg_id is distinct from v_m then
      raise exception '5a: o acompanhamento (%, %)', v_a.estado, v_a.parou_por;
    end if;
    if pg_temp.f5t_saidas('00009906') <> '' then
      raise exception '5b: saiu mensagem depois de o dono escrever';
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 6. *segura 99907* na véspera do lembrete promovido → nada sai; *solta 99907* → a véspera segue ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    update public.retorno_modelo_tipos set nivel = 'sozinho' where tipo = 'orc_lembrete';
    v_os := pg_temp.f5t_pronto('Ana Segura F5 Teste', '5547900009907', 'ORÇ-99907', c_ter);
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    -- O fechamento de qua 13/01 avisa que amanhã sai sozinho, numa linha fixa, e vai à fila.
    v_r := public.orcamento_resumo_fechamento('2027-01-13 17:30-03');
    perform pg_temp.f5t_igual('6a a linha fixa', v_r -> 'fixas' ->> 0,
      'Orçamentos: amanhã sai sozinho o lembrete do ORÇ-99907 (Ana) · *segura 99907*');
    if jsonb_array_length(v_r -> 'avisar') is distinct from 1 then
      raise exception '6a: o passo a avisar (%)', v_r -> 'avisar';
    end if;
    v_q := pg_temp.f5t_fila('sent', '2027-01-13 17:31-03');
    v_n := public.orcamento_avisados(array[(v_r -> 'avisar' ->> 0)::uuid], v_q, '2027-01-13 17:31-03');
    perform pg_temp.f5t_igual('6b avisados', v_n::text, '1');
    -- *segura 99907*: o acompanhamento segurado, e o lembrete não sai.
    v_r := public.orcamento_dito('{"comando": "segura", "numero": 99907}'::jsonb, v_dono, '2027-01-13 18:00-03');
    if (v_r ->> 'ok')::boolean is not true then
      raise exception '6c: *segura 99907* (%)', v_r;
    end if;
    v_a := pg_temp.f5t_a(v_os);
    if v_a.estado is distinct from 'parado' or v_a.parou_por is distinct from 'segurado' then
      raise exception '6d: o acompanhamento segurado (%, %)', v_a.estado, v_a.parou_por;
    end if;
    perform public.orcamento_vigia('2027-01-14 10:05-03');
    if pg_temp.f5t_saidas('00009907') <> '' or public.orcamento_pegar('2027-01-14 10:10-03') is not null then
      raise exception '6e: saiu o lembrete segurado (%)', pg_temp.f5t_saidas('00009907');
    end if;
    -- *solta 99907* na sex 15/01: o lembrete do dia que passou fica pulado (segurado); a véspera volta a previsto e segue.
    v_r := public.orcamento_dito('{"comando": "solta", "numero": 99907}'::jsonb, v_dono, '2027-01-15 09:00-03');
    if (v_r ->> 'ok')::boolean is not true or (pg_temp.f5t_a(v_os)).estado is distinct from 'ativo' then
      raise exception '6f: *solta 99907* (%)', v_r;
    end if;
    perform pg_temp.f5t_igual('6g o lembrete', pg_temp.f5t_px(v_os, 'lembrete'), 'pulado/segurado');
    perform pg_temp.f5t_igual('6h a véspera', pg_temp.f5t_px(v_os, 'vespera'), 'previsto/-');
    perform public.orcamento_vigia('2027-01-18 09:00-03');
    perform pg_temp.f5t_igual('6i a véspera segue', pg_temp.f5t_px(v_os, 'vespera'), 'aguarda_sim/-');
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 7. O C9 inteiro: "Pode fazer." → item → *1 B* + *sim* → (a parte de TS, simulada) orcamento_aceite_registrar → o
  --       "Fechado" em sombra com o retorno em sombra; com tudo ligado, enviado, e o caso cumprido ──
  foreach v_modo in array array['sombra', 'ligado'] loop
    begin
      perform pg_temp.f5t_ligar(v_modo, 'cartao');
      v_os := pg_temp.f5t_pronto('Ana Aceite F5 Teste', '5547900009908', 'ORÇ-99908', c_ter);
      v_m := pg_temp.f5t_cliente_diz('5547900009908', 'Pode fazer.', c_qua);
      v_k := (select rm.abertura_id from public.retorno_mensagens rm where rm.whatsapp_message_id = v_m);
      if v_k is null then
        raise exception '7a (%): o "Pode fazer." não abriu caso na F1', v_modo;
      end if;
      perform public.orcamento_vigia(c_qua + interval '5 minutes');
      v_ac := pg_temp.f5t_ac(v_m);
      if v_ac.estado is distinct from 'detectado' or v_ac.service_order_id is distinct from v_os or v_ac.abertura_id is distinct from v_k then
        raise exception '7b (%): o aceite (%)', v_modo, to_jsonb(v_ac) - 'resultado';
      end if;
      v_cartao := pg_temp.f5t_cartao(c_qua + interval '15 minutes');
      v_i := pg_temp.f5t_item_aceite(v_cartao, v_ac.id);
      if v_i.id is null or not (v_i.opcoes @> '[{"letra": "B"}]'::jsonb) then
        raise exception '7c (%): o item do aceite no cartão (%)', v_modo, pg_temp.f5t_texto(v_cartao);
      end if;
      perform pg_temp.f5t_tem('7c (' || v_modo || ') era aprovação?', pg_temp.f5t_texto(v_cartao), 'Era aprovação?');
      perform pg_temp.f5t_dito(jsonb_build_object('comando', 'escolher', 'n', v_i.n, 'letra', 'B', 'resto', null), c_qua + interval '20 minutes');
      v_r := pg_temp.f5t_sim(v_cartao, c_qua + interval '25 minutes');
      if v_r -> 'aceites' -> 0 ->> 'escolha' is distinct from 'sem_sinal' or v_r -> 'aceites' -> 0 ? 'feito'
         or v_r -> 'aceites' -> 0 ->> 'msg_id' is distinct from v_m::text then
        raise exception '7d (%): o *1 B* com *sim* (%)', v_modo, v_r -> 'aceites';
      end if;
      -- A ferramenta converte (via dono, com o id da mensagem) e registra: simulada aqui.
      perform pg_temp.f5t_converter(v_os, c_qua + interval '26 minutes', 'OS-99908');
      v_r := public.orcamento_aceite_registrar(v_ac.id, true,
                                               jsonb_build_object('escolha', 'sem_sinal', 'numero', 'OS-99908', 'convertido', true),
                                               v_dono, false, c_qua + interval '26 minutes');
      if (v_r ->> 'ok')::boolean is not true or v_r ->> 'fechado' is null then
        raise exception '7e (%): o registro do aceite (%)', v_modo, v_r;
      end if;
      v_item := pg_temp.f5t_sair(c_qua + interval '27 minutes');
      if v_item ->> 'tipo' is distinct from 'orc_fechado' or v_item ->> 'modo' is distinct from v_modo then
        raise exception '7f (%): o "Fechado" (%)', v_modo, v_item - 'texto' - 'validador';
      end if;
      v_ac := pg_temp.f5t_ac(v_m);
      perform pg_temp.f5t_igual('7g (' || v_modo || ') o aceite', v_ac.estado, 'sem_sinal');
      if v_modo = 'sombra' then
        if v_ac.saida_fechado_id is not null
           or (select a.cumprida_em from public.retorno_aberturas a where a.id = v_k) is not null then
          raise exception '7h: o "Fechado" em sombra cumpriu o caso';
        end if;
        perform pg_temp.f5t_igual('7h a saída em sombra', pg_temp.f5t_saidas('00009908'), 'orc_fechado:sombra');
      else
        if v_ac.saida_fechado_id is distinct from (v_item ->> 'saida_id')::uuid
           or (select a.cumprida_por from public.retorno_aberturas a where a.id = v_k) is distinct from 'cartao' then
          raise exception '7i: o "Fechado" enviado não cumpriu o caso';
        end if;
        perform pg_temp.f5t_igual('7i a saída enviada', pg_temp.f5t_saidas('00009908'), 'orc_fechado:enviada');
      end if;
      raise exception 'f5t_cenario' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
        raise;
      end if;
    end;
  end loop;

  -- ── 8. Dois orçamentos enviados: duvida, sem letra ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Ana Dois F5 Teste', '5547900009909', 'ORÇ-99909', c_ter);
    v_c := (select so.client_id from public.service_orders so where so.id = v_os);
    v_os2 := pg_temp.f5t_orc(v_c, 'ORÇ-99959', c_ter, 'Troca das baterias da lancha', 3200);
    perform pg_temp.f5t_enviar(v_os2, '5547900009909', c_ter + interval '1 hour');
    v_m := pg_temp.f5t_cliente_diz('5547900009909', 'Pode fazer.', c_qua);
    perform public.orcamento_vigia(c_qua + interval '5 minutes');
    v_ac := pg_temp.f5t_ac(v_m);
    if v_ac.estado is distinct from 'duvida' or cardinality(v_ac.candidatos) is distinct from 2 or v_ac.service_order_id is not null then
      raise exception '8a: o aceite com dois orçamentos (%)', to_jsonb(v_ac) - 'resultado';
    end if;
    v_cartao := pg_temp.f5t_cartao(c_qua + interval '15 minutes');
    v_i := pg_temp.f5t_item_aceite(v_cartao, v_ac.id);
    perform pg_temp.f5t_igual('8b sem letra', v_i.opcoes::text, '[]');
    perform pg_temp.f5t_tem('8c a dúvida é do dono', pg_temp.f5t_texto(v_cartao), 'A dúvida é sua');
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 9. A agenda esperando a resposta do cliente: agenda, sem letra, com a OS da agenda ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Pedro Agenda F5 Teste', '5547900009910', 'ORÇ-99910', c_ter);
    v_c := (select so.client_id from public.service_orders so where so.id = v_os);
    v_os2 := pg_temp.f5t_orc(v_c, 'OS-99960', c_ter - interval '10 days', 'Revisão do motor de popa', 1500);
    update public.service_orders set status = 'open', quote_status = 'approved', converted_to_os_at = c_ter - interval '9 days'
     where id = v_os2;
    perform pg_temp.f5t_agenda(v_c, v_os2, 'confirmar', 'enviada', 'ligado', '2027-01-13 09:00-03', '2027-01-13 09:00-03',
                               '2027-01-13 08:00-03');
    v_m := pg_temp.f5t_cliente_diz('5547900009910', 'Pode marcar', c_qua);
    perform public.orcamento_vigia(c_qua + interval '5 minutes');
    v_ac := pg_temp.f5t_ac(v_m);
    if v_ac.estado is distinct from 'agenda' or v_ac.resultado ->> 'os_agenda' is distinct from 'OS-99960' then
      raise exception '9a: o aceite com a agenda esperando (%)', to_jsonb(v_ac);
    end if;
    v_cartao := pg_temp.f5t_cartao(c_qua + interval '15 minutes');
    perform pg_temp.f5t_igual('9b sem letra', (pg_temp.f5t_item_aceite(v_cartao, v_ac.id)).opcoes::text, '[]');
    perform pg_temp.f5t_tem('9c a linha da agenda', pg_temp.f5t_texto(v_cartao), 'A agenda também espera resposta do cliente sobre a OS-99960.');
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 10. "se fizer por 4 mil eu fecho": negociação, nada ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    perform pg_temp.f5t_pronto('João Negocia F5 Teste', '5547900009911', 'ORÇ-99911', c_ter);
    v_m := pg_temp.f5t_cliente_diz('5547900009911', 'se fizer por 4 mil eu fecho', c_qua);
    perform public.orcamento_vigia(c_qua + interval '5 minutes');
    if (pg_temp.f5t_ac(v_m)).id is not null then
      raise exception '10: a condicional virou aceite';
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 11. O cliente que é parceiro (a revenda cadastrada como cliente) e o orçamento pedido pelo parceiro (C13): inelegíveis ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Pedro Revenda F5 Teste', '5547900009912', 'ORÇ-99912', c_ter);
    v_c := (select so.client_id from public.service_orders so where so.id = v_os);
    update public.retorno_config set clientes_parceiros = clientes_parceiros || array[v_c] where id;
    insert into public.parceiros (nome, sigla, tipo) values ('Revenda Travessia F5 Teste', 'RTFT', 'revenda') returning id into v_p;
    v_os2 := pg_temp.f5t_pronto('Ana C13 F5 Teste', '5547900009914', 'ORÇ-99962', c_ter);
    update public.service_orders set origem_parceiro_id = v_p where id = v_os2;
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    if (pg_temp.f5t_a(v_os)).id is not null or (pg_temp.f5t_a(v_os2)).id is not null then
      raise exception '11a: o orçamento do parceiro ganhou cadência';
    end if;
    perform pg_temp.f5t_igual('11b o cliente parceiro', public._orcamento_inelegivel(v_os, c_ter + interval '5 minutes'), 'parceiro_cliente');
    perform pg_temp.f5t_igual('11c o C13', public._orcamento_inelegivel(v_os2, c_ter + interval '5 minutes'), 'parceiro_cliente');
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 12. O número compartilhado (dois cadastros, o mesmo número; o caso dos 13 números da travessia da F4, com números
  --        inventados): o aceite não nasce sem papel cliente e um cadastro, e a cadência não abre (numero_compartilhado) ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Ana Compartilhado F5 Teste', '5547900009913', 'ORÇ-99913', c_ter);
    v_c2 := pg_temp.f5t_cli('João Compartilhado F5 Teste', '5547900009913');
    v_os2 := pg_temp.f5t_orc(v_c2, 'ORÇ-99963', c_ter, 'Troca das baterias da lancha', 3200);
    perform pg_temp.f5t_enviar(v_os2, '5547900009913', c_ter + interval '1 hour');
    perform public.orcamento_vigia(c_ter + interval '2 hours');
    if (pg_temp.f5t_a(v_os)).id is not null or (pg_temp.f5t_a(v_os2)).id is not null then
      raise exception '12a: a cadência abriu para o número compartilhado';
    end if;
    perform pg_temp.f5t_igual('12b inelegível', public._orcamento_inelegivel(v_os, c_ter + interval '2 hours'), 'numero_compartilhado');
    v_m := pg_temp.f5t_cliente_diz('5547900009913', 'Pode fazer.', c_qua);
    perform public.orcamento_vigia(c_qua + interval '5 minutes');
    if (pg_temp.f5t_ac(v_m)).id is not null
       or exists (select 1 from public.orcamento_aceites a where a.chave = '00009913') then
      raise exception '12c: o aceite nasceu no número compartilhado';
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 13. O PDF do aparelho a um número confirmado de parceiro (com o envio à mão marcando): nada ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    update public.retorno_config set envio_mao_modo = 'marcar' where id;
    insert into public.parceiros (nome, sigla, tipo) values ('Revenda PDF Travessia F5 Teste', 'RPTF', 'revenda') returning id into v_p;
    insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_pessoa;
    insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_documento)
      values (v_pessoa, '5547900009915', '00009915', '47', 'confirmado', c_ter - interval '30 days', true);
    v_c := pg_temp.f5t_cli('Ana PDF Parceiro F5 Teste', '5547900009965');
    perform pg_temp.f5t_msg('5547900009965', 'Bom dia, tudo bem?', c_ter - interval '10 days');
    v_os := pg_temp.f5t_orc(v_c, 'ORÇ-99915', c_ter);
    perform pg_temp.f5t_eco('5547900009915', 'ORÇ-99915.pdf', c_ter);
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    if exists (select 1 from public.orcamento_envios e where e.service_order_id = v_os)
       or (select so.quote_status from public.service_orders so where so.id = v_os) is distinct from 'draft'
       or (pg_temp.f5t_a(v_os)).id is not null then
      raise exception '13: o PDF ao número de parceiro foi registrado ou marcado';
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 14. O teto do retorno: 12 iniciadas no dia (agenda + F4 + F5) → a 13ª da F4 ou da F5 não sai. A agenda não lê o
  --        retorno no teto dela (pedido A-5): este cenário não exige que a 13ª da agenda seja barrada ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    update public.retorno_config set parceiro_modo = 'sombra' where id;
    v_os := pg_temp.f5t_pronto('Pedro Teto F5 Teste', '5547900009916', 'ORÇ-99916', c_ter);
    v_c := (select so.client_id from public.service_orders so where so.id = v_os);
    v_t := '2027-01-14 08:00-03';
    for v_n in 1 .. 5 loop
      perform pg_temp.f5t_agenda(v_c, v_os, 'andamento', 'enviada', 'ligado', v_t, v_t, v_t - interval '1 hour');
    end loop;
    for v_n in 1 .. 3 loop
      perform pg_temp.f5t_outra('5547900009917', 'parceiro', 'parceiro_aviso_cliente', 'retorno_aviso', 'aviso',
                                v_t + v_n * interval '1 minute');
      perform pg_temp.f5t_outra('5547900009918', 'orcamento', 'orc_lembrete', 'retorno_orcamento', 'comercial',
                                v_t + v_n * interval '2 minutes');
    end loop;
    -- 11 iniciadas: a 12ª ainda cabe.
    v_r := public.canal_pode_enviar('5547900009916', 'comercial', 'retorno_orcamento', '2027-01-14 11:00-03');
    if (v_r ->> 'pode')::boolean is not true then
      raise exception '14a: com 11 iniciadas a comercial não cabia (%)', v_r;
    end if;
    perform pg_temp.f5t_agenda(v_c, v_os, 'andamento', 'enviada', 'ligado', v_t + interval '1 hour', v_t + interval '1 hour', v_t);
    -- 12 iniciadas: a 13ª não sai, nem da F5 nem da F4.
    v_r := public.canal_pode_enviar('5547900009916', 'comercial', 'retorno_orcamento', '2027-01-14 11:00-03');
    perform pg_temp.f5t_igual('14b a 13ª da F5', v_r ->> 'motivo', 'teto_iniciadas');
    v_r := public.canal_pode_enviar('5547900009916', 'aviso', 'retorno_aviso', '2027-01-14 11:00-03');
    perform pg_temp.f5t_igual('14c a 13ª da F4', v_r ->> 'motivo', 'teto_iniciadas');
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 15. Os dados da nota com o retorno ligado e o "Fechado" enviado: *1 C* pede os dados → a resposta com CPF e CEP (o caso
  --        já cumprido) → o item dados_nota → A → só os campos vazios gravados ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    update public.retorno_config set dados_nota_ligado = true where id;
    v_os := pg_temp.f5t_pronto('Ana Nota F5 Teste', '5547900009919', 'ORÇ-99919', c_ter);
    v_c := (select so.client_id from public.service_orders so where so.id = v_os);
    update public.clients set postal_code = '88000-000' where id = v_c;   -- o CEP já está na ficha: não é sobrescrito
    v_m := pg_temp.f5t_cliente_diz('5547900009919', 'Pode fazer.', c_qua);
    v_k := (select rm.abertura_id from public.retorno_mensagens rm where rm.whatsapp_message_id = v_m);
    perform public.orcamento_vigia(c_qua + interval '5 minutes');
    v_ac := pg_temp.f5t_ac(v_m);
    v_cartao := pg_temp.f5t_cartao(c_qua + interval '15 minutes');
    v_i := pg_temp.f5t_item_aceite(v_cartao, v_ac.id);
    if v_i.id is null or not (v_i.opcoes @> '[{"letra": "C"}]'::jsonb) then
      raise exception '15a: o aceite sem a letra C (%)', pg_temp.f5t_texto(v_cartao);
    end if;
    perform pg_temp.f5t_dito(jsonb_build_object('comando', 'escolher', 'n', v_i.n, 'letra', 'C', 'resto', null), c_qua + interval '20 minutes');
    v_r := pg_temp.f5t_sim(v_cartao, c_qua + interval '25 minutes');
    -- C: aprovado, aguardando o sinal, registrado no banco no mesmo *sim*; o "Fechado" e, 2 minutos depois, o pedido de dados.
    v_ac := pg_temp.f5t_ac(v_m);
    if v_ac.estado is distinct from 'com_sinal' or (select so.quote_status from public.service_orders so where so.id = v_os) is distinct from 'awaiting_deposit' then
      raise exception '15b: o *1 C* com *sim* (%)', v_r -> 'aceites';
    end if;
    v_item := pg_temp.f5t_sair(c_qua + interval '26 minutes');
    perform pg_temp.f5t_igual('15c o Fechado', v_item ->> 'tipo', 'orc_fechado');
    v_item := pg_temp.f5t_sair(c_qua + interval '28 minutes');
    perform pg_temp.f5t_igual('15d o pedido de dados', v_item ->> 'tipo', 'orc_dados_nota');
    v_ac := pg_temp.f5t_ac(v_m);
    if v_ac.saida_fechado_id is null or v_ac.saida_dados_id is null or v_ac.dados_estado is distinct from 'esperando'
       or (select a.cumprida_em from public.retorno_aberturas a where a.id = v_k) is null then
      raise exception '15e: depois do "Fechado" e do pedido (%)', to_jsonb(v_ac) - 'resultado';
    end if;
    -- A resposta da Ana, no caso já cumprido.
    perform pg_temp.f5t_msg('5547900009919', 'Meu CPF é 529.982.247-25 e o CEP 88330-000', c_qua + interval '1 hour');
    perform public.orcamento_vigia(c_qua + interval '1 hour 5 minutes');
    perform pg_temp.f5t_igual('15f lidos', (pg_temp.f5t_ac(v_m)).dados_estado, 'lidos');
    v_cartao := pg_temp.f5t_cartao(c_qua + interval '1 hour 10 minutes');
    v_i := pg_temp.f5t_item_aceite(v_cartao, v_ac.id, 'dados_nota');
    if v_i.id is null then
      raise exception '15g: o item dados_nota não entrou no cartão (%)', pg_temp.f5t_texto(v_cartao);
    end if;
    perform pg_temp.f5t_dito(jsonb_build_object('comando', 'escolher', 'n', v_i.n, 'letra', 'A', 'resto', null),
                             c_qua + interval '1 hour 12 minutes');
    perform pg_temp.f5t_sim(v_cartao, c_qua + interval '1 hour 15 minutes');
    if (select c.cpf_cnpj || '|' || c.postal_code from public.clients c where c.id = v_c) is distinct from '529.982.247-25|88000-000'
       or (pg_temp.f5t_ac(v_m)).dados_estado is distinct from 'gravados' then
      raise exception '15h: a ficha (só o vazio) ou o estado dos dados';
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 16. "Fechado!" sem caso: o caso anterior do cliente já fechado; o aceite nasce com abertura nula, entra com letras, e o
  --        "Fechado" sai sem caso a cumprir ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Pedro Fechado F5 Teste', '5547900009920', 'ORÇ-99920', c_ter);
    v_m := pg_temp.f5t_cliente_diz('5547900009920', 'Oi, recebi o orçamento', c_ter + interval '30 minutes');
    v_k := (select rm.abertura_id from public.retorno_mensagens rm where rm.whatsapp_message_id = v_m);
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_ter + interval '4 hours', fechada_motivo = 'dono' where id = v_k;
    v_m := pg_temp.f5t_cliente_diz('5547900009920', 'Fechado!', c_qua);
    if (select rm.abertura_id from public.retorno_mensagens rm where rm.whatsapp_message_id = v_m) is not null then
      raise exception '16a: "Fechado!" abriu caso';
    end if;
    perform public.orcamento_vigia(c_qua + interval '5 minutes');
    v_ac := pg_temp.f5t_ac(v_m);
    if v_ac.estado is distinct from 'detectado' or v_ac.abertura_id is not null then
      raise exception '16b: o aceite sem caso (%)', to_jsonb(v_ac) - 'resultado';
    end if;
    v_cartao := pg_temp.f5t_cartao(c_qua + interval '15 minutes');
    v_i := pg_temp.f5t_item_aceite(v_cartao, v_ac.id);
    if v_i.id is null or not (v_i.opcoes @> '[{"letra": "B"}]'::jsonb) then
      raise exception '16c: o item sem caso sem a letra B (%)', pg_temp.f5t_texto(v_cartao);
    end if;
    perform pg_temp.f5t_dito(jsonb_build_object('comando', 'escolher', 'n', v_i.n, 'letra', 'B', 'resto', null), c_qua + interval '20 minutes');
    perform pg_temp.f5t_sim(v_cartao, c_qua + interval '25 minutes');
    perform pg_temp.f5t_converter(v_os, c_qua + interval '26 minutes', 'OS-99920');
    v_r := public.orcamento_aceite_registrar(v_ac.id, true,
                                             jsonb_build_object('escolha', 'sem_sinal', 'numero', 'OS-99920', 'convertido', true),
                                             v_dono, false, c_qua + interval '26 minutes');
    v_item := pg_temp.f5t_sair(c_qua + interval '27 minutes');
    if v_item ->> 'tipo' is distinct from 'orc_fechado' or (pg_temp.f5t_ac(v_m)).saida_fechado_id is distinct from (v_item ->> 'saida_id')::uuid then
      raise exception '16d: o "Fechado" sem caso (%)', v_r;
    end if;
    if (select a.cumprida_em from public.retorno_aberturas a where a.id = v_k) is not null then
      raise exception '16e: o caso anterior, já fechado, ficou cumprido';
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 17. Duas vozes: o lembrete das 10:00 e a mensagem 'pronto' da agenda, registrada às 09:50 para as 14:00, ao mesmo
  --        cliente → só uma sai no dia (o lembrete é pulado; o outro sentido é o pedido A-1, não exigido aqui) ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Ana Duas Vozes F5 Teste', '5547900009921', 'ORÇ-99921', c_ter);
    v_c := (select so.client_id from public.service_orders so where so.id = v_os);
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    perform public.orcamento_vigia('2027-01-14 09:00-03');
    v_cartao := pg_temp.f5t_cartao('2027-01-14 09:30-03');
    perform pg_temp.f5t_sim(v_cartao, '2027-01-14 09:40-03');
    perform pg_temp.f5t_igual('17a o lembrete', pg_temp.f5t_px(v_os, 'lembrete'), 'agendado/-');
    v_os2 := pg_temp.f5t_orc(v_c, 'OS-99971', c_ter - interval '10 days', 'Revisão do motor de popa', 1500);
    update public.service_orders set status = 'open', quote_status = 'approved', converted_to_os_at = c_ter - interval '9 days'
     where id = v_os2;
    perform pg_temp.f5t_agenda(v_c, v_os2, 'pronto', 'registrada', 'ligado', '2027-01-14 14:00-03', null, '2027-01-14 09:50-03');
    if pg_temp.f5t_sair('2027-01-14 10:00-03') is not null then
      raise exception '17b: o lembrete saiu no dia da mensagem da agenda';
    end if;
    perform pg_temp.f5t_igual('17c o passo', pg_temp.f5t_px(v_os, 'lembrete'), 'pulado/agenda_hoje');
    perform pg_temp.f5t_igual('17d a saída', pg_temp.f5t_saidas('00009921'), 'orc_lembrete:cancelada');
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 18. O PDF do aparelho à noite: eco às 21:30, a resposta do cliente às 21:40, a detecção às 07:00 com marcar → o
  --        acompanhamento nasce e para (cliente_escreveu), e nenhum lembrete ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    update public.retorno_config set envio_mao_modo = 'marcar', orcamento_envio_ate = '2027-01-12 20:00-03' where id;
    v_c := pg_temp.f5t_cli('João Noite F5 Teste', '5547900009922');
    perform pg_temp.f5t_msg('5547900009922', 'Bom dia, tudo bem?', c_ter - interval '10 days');
    v_os := pg_temp.f5t_orc(v_c, 'ORÇ-99922', c_ter);
    update public.service_orders set quote_validity_date = c_val where id = v_os;   -- a validade que o PDF já levava
    perform pg_temp.f5t_eco('5547900009922', 'ORÇ-99922.pdf', '2027-01-12 21:30-03');
    v_m := pg_temp.f5t_msg('5547900009922', 'Recebi, vou olhar com calma', '2027-01-12 21:40-03');
    perform public.orcamento_vigia('2027-01-13 07:00-03');
    select so.quote_status, so.orcamento_enviado_em, so.orcamento_enviado_via into v_so from public.service_orders so where so.id = v_os;
    if v_so.quote_status is distinct from 'sent' or v_so.orcamento_enviado_em is distinct from '2027-01-12 21:30-03'::timestamptz
       or v_so.orcamento_enviado_via is distinct from 'aparelho' then
      raise exception '18a: o PDF do aparelho (a hora do eco) (%)', row_to_json(v_so);
    end if;
    v_a := pg_temp.f5t_a(v_os);
    if v_a.estado is distinct from 'parado' or v_a.parou_por is distinct from 'cliente_escreveu' or v_a.parou_msg_id is distinct from v_m then
      raise exception '18b: o acompanhamento (%, %)', v_a.estado, v_a.parou_por;
    end if;
    if pg_temp.f5t_saidas('00009922') <> '' then
      raise exception '18c: saiu lembrete';
    end if;
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 19. Duplicar: a cópia de um orçamento enviado, mandada no dia seguinte → 7 dias do envio novo e acompanhamento novo ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Pedro Cópia F5 Teste', '5547900009923', 'ORÇ-99923', c_ter);
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    -- A cópia como useDuplicateServiceOrder e duplicate_service_order a fazem: as colunas da F5 não vão (P11.7, P12.1).
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, problem_description,
                                       created_at, updated_at, grand_total, quote_validity_days)
    select 'ORÇ-99973', so.client_id, so.vessel_id, 'draft', 'draft', so.service_type, so.problem_description,
           '2027-01-13 09:00-03', '2027-01-13 09:00-03', so.grand_total, so.quote_validity_days
      from public.service_orders so where so.id = v_os
    returning id into v_os2;
    v_r := pg_temp.f5t_enviar(v_os2, '5547900009923', '2027-01-13 10:00-03');
    if v_r ->> 'data' is distinct from '2027-01-20'
       or (select so.quote_validity_date from public.service_orders so where so.id = v_os2) is distinct from date '2027-01-20' then
      raise exception '19a: a validade da cópia (%)', v_r;
    end if;
    perform public.orcamento_vigia('2027-01-13 10:05-03');
    v_a := pg_temp.f5t_a(v_os2);
    if v_a.id is null or v_a.validade_ate is distinct from date '2027-01-20' or v_a.enviado_em is distinct from '2027-01-13 10:00-03'::timestamptz
       or v_a.id = (pg_temp.f5t_a(v_os)).id then
      raise exception '19b: o acompanhamento da cópia (%)', to_jsonb(v_a);
    end if;
    perform pg_temp.f5t_igual('19c o lembrete da cópia', split_part(pg_temp.f5t_cal(v_os2), ',', 1), 'lembrete:2027-01-15:2027-01-18');
    perform pg_temp.f5t_igual('19d o original', (pg_temp.f5t_a(v_os)).validade_ate::text, '2027-01-19');
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 20. O encerramento sem *sim*: o dono não abre o cartão até o fim do prazo → encerrado/sem_mensagem, e a linha 3 do
  --        fechamento o mostra ──
  begin
    perform pg_temp.f5t_ligar('ligado', 'cartao');
    v_os := pg_temp.f5t_pronto('Ana Sem Sim F5 Teste', '5547900009924', 'ORÇ-99924', c_ter);
    perform public.orcamento_vigia(c_ter + interval '5 minutes');
    foreach v_t in array array['2027-01-14 09:00-03', '2027-01-15 17:05-03', '2027-01-18 09:00-03', '2027-01-18 17:05-03',
                               '2027-01-20 09:00-03', '2027-01-22 17:05-03']::timestamptz[] loop
      perform public.orcamento_vigia(v_t);
    end loop;
    perform pg_temp.f5t_igual('20a o lembrete', pg_temp.f5t_px(v_os, 'lembrete'), 'pulado/sem_sim');
    perform pg_temp.f5t_igual('20b a véspera', pg_temp.f5t_px(v_os, 'vespera'), 'pulado/sem_sim');
    perform pg_temp.f5t_igual('20c o encerramento', pg_temp.f5t_px(v_os, 'encerramento'), 'pulado/sem_sim');
    v_a := pg_temp.f5t_a(v_os);
    if v_a.estado is distinct from 'encerrado' or v_a.encerramento is distinct from 'sem_mensagem' or v_a.desfecho_proposto is distinct from 'sumiu' then
      raise exception '20d: o acompanhamento (%, %)', v_a.estado, v_a.encerramento;
    end if;
    if (select so.quote_status from public.service_orders so where so.id = v_os) is distinct from 'sent' or pg_temp.f5t_saidas('00009924') <> '' then
      raise exception '20e: o encerramento sem mensagem marcou perdido ou mandou algo';
    end if;
    v_r := public.orcamento_resumo_fechamento('2027-01-22 17:30-03');
    perform pg_temp.f5t_tem('20f a linha 3', v_r ->> 'linhas',
      'Encerrado sem mensagem (não saiu: sem o seu sim): ORÇ-99924 (Ana) · para marcar como perdido, use a tela ou o assistente');
    raise exception 'f5t_cenario' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
      raise;
    end if;
  end;

  -- ── 21. Sozinho sem aviso: o tipo promovido, e o fechamento da véspera que não saiu (a) ou que foi à fila com a linha fixa
  --        e não foi entregue (b, a linha da fila em failed às 19:30) → o passo vai ao cartão, e nada sai sozinho. Com a
  --        linha em sent (c), sai sozinho ──
  foreach v_modo in array array['sem_fechamento', 'failed', 'sent'] loop
    begin
      perform pg_temp.f5t_ligar('ligado', 'sozinho');
      v_os := pg_temp.f5t_pronto('Pedro Sozinho F5 Teste', '5547900009925', 'ORÇ-99925', c_ter);
      perform public.orcamento_vigia(c_ter + interval '5 minutes');
      if v_modo <> 'sem_fechamento' then
        v_r := public.orcamento_resumo_fechamento('2027-01-13 17:30-03');
        perform pg_temp.f5t_tem('21 a linha fixa', v_r -> 'fixas' ->> 0, 'amanhã sai sozinho o lembrete do ORÇ-99925 (Pedro)');
        v_q := pg_temp.f5t_fila(v_modo, case when v_modo = 'sent' then timestamptz '2027-01-13 17:32-03' end);
        perform public.orcamento_avisados(array(select jsonb_array_elements_text(v_r -> 'avisar')::uuid), v_q, '2027-01-13 17:31-03');
      end if;
      perform public.orcamento_vigia('2027-01-14 09:00-03');
      if v_modo = 'sent' then
        if pg_temp.f5t_px(v_os, 'lembrete') is distinct from 'agendado/-'
           or not exists (select 1 from public.retorno_saidas s where s.emissor = 'orcamento' and s.chave = '00009925'
                                                               and s.estado = 'agendada' and s.dados ->> 'por' = 'sozinho') then
          raise exception '21c: com o aviso entregue, o lembrete não saiu sozinho (%)', pg_temp.f5t_px(v_os, 'lembrete');
        end if;
      else
        perform pg_temp.f5t_igual('21 (' || v_modo || ') ao cartão', pg_temp.f5t_px(v_os, 'lembrete'), 'aguarda_sim/-');
        if pg_temp.f5t_saidas('00009925') <> '' then
          raise exception '21 (%): saiu sozinho sem o aviso entregue', v_modo;
        end if;
        v_cartao := pg_temp.f5t_cartao('2027-01-14 09:30-03');
        if (pg_temp.f5t_item_passo(v_cartao, v_os, 'lembrete')).id is null then
          raise exception '21 (%): o passo não entrou no cartão', v_modo;
        end if;
      end if;
      raise exception 'f5t_cenario' using errcode = 'P0001';
    exception when others then
      if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'f5t_cenario' then
        raise;
      end if;
    end;
  end loop;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_travessia', true, '{}');
end
$travessia$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
