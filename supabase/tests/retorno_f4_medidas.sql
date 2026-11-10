-- Retorno F4 (P14): a medida do parceiro (retorno_f4_medidas), o fechamento das 17:30 (parceiro_resumo_fechamento) e a
-- retenção (parceiro_retencao_rodada, pelo parceiro_vigia às 04:00). Cada "0 esperado" fica 1 quando o cenário é forçado por
-- saída real, e 0 sem ele; o bloqueio do validador conta à parte; OS cancelada ou vínculo pausado depois do envio não vira
-- falso positivo; saída expirada não conta; o documento pelo sistema à contratante não conta; o eco com número e sem
-- detecção vai a doc_mao_sem_deteccao, fora da soma. A retenção troca cada coluna pelo marcador e anonimiza o provisório sem
-- OS de verdade, com parceiro_modo = 'desligado'. As medidas são lidas em diferença ao começo do teste (a visão lê o banco
-- inteiro). Roda só pela bancada (grupo 7, F4_ONDA=9). Termina em ROLLBACK. Telefones de teste 55479000172xx e 55479000173xx;
-- nomes, frases e números de documento inventados (9895x). Relógio: qua 13/01/2027 10:00.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f4md_cliente(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

create or replace function pg_temp.f4md_os(p_cliente uuid, p_numero text, p_status text default 'open', p_quote text default 'approved')
returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total)
  values (p_numero, p_cliente, v_v, p_status, p_quote, 'repair', '2026-10-01 10:00-03', '2026-10-01 10:00-03', 0)
  returning id into v_id;
  return v_id;
end $f$;

create or replace function pg_temp.f4md_liga(p_os uuid, p_parceiro uuid, p_papel text, p_aviso_em timestamptz) returns uuid
language sql as $f$
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem, aviso_ao_cliente, aviso_em,
                                      confirmado_em, pacote)
  select so.id, p_parceiro, so.client_id, p_papel, 'confirmado', 'dono',
         case when p_aviso_em is null then 'nao_avisado' else 'mensagem' end, p_aviso_em, timestamptz '2027-01-01 10:00-03',
         case when p_papel in ('contratante', 'pagador') then 'completo' else 'status' end
    from public.service_orders so where so.id = p_os
  returning id
$f$;

-- A saída ao parceiro, gravada como o envio a deixa (modo, estado, texto e dados).
create or replace function pg_temp.f4md_saida(p_tipo text, p_estado text, p_em timestamptz, p_texto text, p_dados jsonb, p_chave text,
                                              p_modo text default 'ligado', p_motivo text default null) returns uuid
language sql as $f$
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, estado, motivo, enviar_em, decidida_em,
                                     enviada_em, texto, dados, dedupe_key, criada_em)
  values ('parceiro', p_tipo,
          case when p_tipo in ('parceiro_aviso_cliente', 'parceiro_nao_mp_ok') then 'retorno_aviso' else 'retorno_parceiro' end,
          case when p_tipo = 'parceiro_painel' then 'resumo_parceiro' when p_tipo in ('parceiro_eco', 'parceiro_repassar') then 'aviso'
               else 'resposta_imediata' end,
          '00017201', '5547900017201', p_modo, p_estado, p_motivo, p_em, p_em, case when p_estado = 'enviada' then p_em end, p_texto,
          p_dados, 'teste-f4-medidas:' || p_chave, p_em)
  returning id
$f$;

-- O documento que saiu ao número da parceira: eco do aparelho (data, sem via) ou envio do sistema (com via).
create or replace function pg_temp.f4md_doc(p_arquivo text, p_em timestamptz, p_via boolean default false) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, raw_payload, occurred_at)
  values ('outbound', '5547900017201', 'document', null, 'teste-f4-medidas-' || md5(coalesce(p_arquivo, '') || p_em::text || random()::text),
          case when p_via
               then jsonb_build_object('via', 'whatsapp-send', 'data', jsonb_build_object('message', jsonb_build_object('documentMessage', jsonb_build_object('fileName', p_arquivo))))
               else jsonb_build_object('data', jsonb_build_object('source', 'unknown', 'message', jsonb_build_object('documentMessage', jsonb_build_object('fileName', p_arquivo))))
          end, p_em)
  returning id
$f$;

-- O caso do pedido (a mensagem recebida inventada, só para a FK).
create or replace function pg_temp.f4md_caso(p_fone text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_m uuid;
  v_a uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
    values ('inbound', p_fone, 'text', 'pedido inventado de teste', 'teste-f4-medidas-caso-' || md5(p_fone || p_em::text), p_em)
    returning id into v_m;
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, primeira_msg_id, aberta_em, gravada_em,
                                        ultima_em, ultima_gravada_em, nivel, tipo_recibo, modo)
    values (right(p_fone, 8), p_fone, 'parceiro', '{"papel": "parceiro"}', v_m, p_em, p_em, p_em, p_em, 'recibo', 'recibo_parceiro', 'sombra')
    returning id into v_a;
  return v_a;
end $f$;

create or replace function pg_temp.f4md_m() returns public.retorno_f4_medidas
language sql as $f$
  select m from public.retorno_f4_medidas m
$f$;

do $medidas$
declare
  c_t constant timestamptz := '2027-01-13 10:00-03';        -- qua
  c_velho constant timestamptz := '2026-06-01 10:00-03';     -- antes da retenção de 180 dias, vista de 13/01/2027
  v0 public.retorno_f4_medidas;
  m public.retorno_f4_medidas;
  v_p uuid;
  v_carla uuid;
  v_c uuid;
  v_ca uuid; v_cb uuid; v_cc uuid; v_cd uuid; v_ce uuid; v_cf uuid; v_cg uuid;
  v_os_a uuid; v_os_b uuid; v_os_c uuid; v_os_d uuid; v_os_e uuid; v_os_f uuid;
  v_i_a uuid; v_i_b uuid; v_i_c uuid; v_i_d uuid; v_i_e uuid; v_i_f uuid;
  v_s_velha uuid; v_s_agendada uuid;
  v_msg uuid;
  v_r jsonb;
  v_linhas jsonb;
  v_txt text;
  v_cartao uuid;
  v_item uuid;
  v_painel_velho uuid;
  v_x uuid; v_y uuid; v_z uuid; v_w uuid;
  v_ped_x uuid;
  v_os_y uuid; v_os_z uuid;
  v_vetos bigint;
  v_vinculos bigint;
  v_rec record;
  v_n_fun integer := 0;
begin
  begin
  update public.retorno_config
     set modo = 'sombra', parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}', parceiro_retencao = interval '180 days',
         parceiro_aviso_espera = interval '24 hours', pdf_mao_modo = 'desligado'
   where id;
  v0 := pg_temp.f4md_m();
  if v0.vinculos_confirmados is null or v0.valor_ou_doc_ao_parceiro is null or v0.os_sem_aviso_no_painel is null then
    raise exception '0: a medida devolveu nulo antes do teste (%)', to_jsonb(v0);
  end if;

  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Medidas F4', 'RMD', 'revenda_e_patio') returning id into v_p;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_documento, recebe_painel)
    values (v_carla, '5547900017201', '00017201', '47', 'confirmado', c_t - interval '30 days', true, true);

  -- Os vínculos: a com aviso; b sem aviso; c anfitriã; d sem aviso e sem telefone; e com veto; f contratante.
  v_ca := pg_temp.f4md_cliente('Ana Medida', '5547900017301');
  v_os_a := pg_temp.f4md_os(v_ca, 'OS-98951');
  v_i_a := pg_temp.f4md_liga(v_os_a, v_p, 'indicou', c_t - interval '5 days');
  v_cb := pg_temp.f4md_cliente('Bia Medida', '5547900017302');
  v_os_b := pg_temp.f4md_os(v_cb, 'OS-98952');
  v_i_b := pg_temp.f4md_liga(v_os_b, v_p, 'indicou', null);
  v_cc := pg_temp.f4md_cliente('Caio Medida', '5547900017303');
  v_os_c := pg_temp.f4md_os(v_cc, 'OS-98953');
  v_i_c := pg_temp.f4md_liga(v_os_c, v_p, 'anfitria', c_t - interval '5 days');
  v_cd := pg_temp.f4md_cliente('Dora Medida', null);
  v_os_d := pg_temp.f4md_os(v_cd, 'OS-98954');
  v_i_d := pg_temp.f4md_liga(v_os_d, v_p, 'indicou', null);
  v_ce := pg_temp.f4md_cliente('Enzo Medida', '5547900017305');
  v_os_e := pg_temp.f4md_os(v_ce, 'OS-98955');
  v_i_e := pg_temp.f4md_liga(v_os_e, v_p, 'indicou', c_t - interval '5 days');
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem) values (v_ce, v_p, c_t - interval '2 days', 'nao_mp');
  v_cf := pg_temp.f4md_cliente('Fábio Medida', '5547900017306');
  v_os_f := pg_temp.f4md_os(v_cf, 'ORÇ-98956', 'draft', 'draft');
  v_i_f := pg_temp.f4md_liga(v_os_f, v_p, 'contratante', c_t - interval '5 days');

  m := pg_temp.f4md_m();
  if m.vinculos_confirmados - v0.vinculos_confirmados is distinct from 5::bigint
     or m.vinculos_sem_aviso - v0.vinculos_sem_aviso is distinct from 2::bigint
     or m.base_fraca - v0.base_fraca is distinct from 1::bigint
     or m.nao_mp - v0.nao_mp is distinct from 1::bigint then
    raise exception '1: vínculos, sem aviso, base fraca ou NÃO MP (%)', to_jsonb(m);
  end if;

  -- ── 2. Os três "0 esperados" das saídas que citam vínculo ──
  -- O painel certo: a visível, com a visibilidade gravada no envio. Nada conta.
  perform pg_temp.f4md_saida('parceiro_painel', 'enviada', c_t - interval '1 day', 'Pátio de teste f4 medidas',
    jsonb_build_object('os_ids', jsonb_build_array(v_os_a), 'interessado_ids', jsonb_build_array(v_i_a),
                       'visibilidade', jsonb_build_array(jsonb_build_object('interessado_id', v_i_a, 'visivel', true, 'motivo', 'ok'))), 'p-ok');
  m := pg_temp.f4md_m();
  if m.os_sem_aviso_no_painel - v0.os_sem_aviso_no_painel is distinct from 0::bigint
     or m.veto_ignorado - v0.veto_ignorado is distinct from 0::bigint
     or m.anfitria_no_painel - v0.anfitria_no_painel is distinct from 0::bigint then
    raise exception '2a: o painel certo contou (%)', to_jsonb(m);
  end if;
  -- OS cancelada e vínculo pausado DEPOIS do envio: continua 0 (só o gravado no envio conta)
  update public.service_orders so set status = 'cancelled' where so.id = v_os_a;
  update public.os_interessados oi set situacao = 'pausado' where oi.id = v_i_a;
  m := pg_temp.f4md_m();
  if m.os_sem_aviso_no_painel - v0.os_sem_aviso_no_painel is distinct from 0::bigint
     or m.veto_ignorado - v0.veto_ignorado is distinct from 0::bigint then
    raise exception '2b: OS cancelada ou vínculo pausado depois do envio virou falso positivo (%)', to_jsonb(m);
  end if;
  update public.os_interessados oi set situacao = 'confirmado' where oi.id = v_i_a;

  -- Sem aviso: o painel que cita o vínculo sem aviso (mesmo com a visibilidade gravada como visível) conta 1.
  perform pg_temp.f4md_saida('parceiro_painel', 'enviada', c_t - interval '1 day', 'Pátio de teste f4 medidas sem aviso',
    jsonb_build_object('os_ids', jsonb_build_array(v_os_b), 'interessado_ids', jsonb_build_array(v_i_b),
                       'visibilidade', jsonb_build_array(jsonb_build_object('interessado_id', v_i_b, 'visivel', true))), 'p-sem-aviso');
  -- A visibilidade gravada sem visivel = true também conta (incerta é saída real).
  perform pg_temp.f4md_saida('parceiro_patio', 'incerta', c_t - interval '20 hours', 'Pátio de teste f4 medidas sem visibilidade',
    jsonb_build_object('os_ids', jsonb_build_array(v_os_a), 'interessado_ids', jsonb_build_array(v_i_a)), 'p-sem-vis');
  -- Veto: o eco citando o vínculo vetado antes do envio conta 1.
  perform pg_temp.f4md_saida('parceiro_eco', 'enviada', c_t - interval '1 day', 'Eco de teste f4 medidas',
    jsonb_build_object('os_ids', jsonb_build_array(v_os_e), 'interessado_ids', jsonb_build_array(v_i_e),
                       'visibilidade', jsonb_build_array(jsonb_build_object('interessado_id', v_i_e, 'visivel', true))), 'p-veto');
  -- Anfitriã: o pátio citando a linha da anfitriã conta 1.
  perform pg_temp.f4md_saida('parceiro_patio', 'enviada', c_t - interval '1 day', 'Pátio de teste f4 medidas anfitria',
    jsonb_build_object('os_ids', jsonb_build_array(v_os_c), 'interessado_ids', jsonb_build_array(v_i_c),
                       'visibilidade', jsonb_build_array(jsonb_build_object('interessado_id', v_i_c, 'visivel', true))), 'p-anfitria');
  -- O que não conta: a sombra, o recibo sem o bloco do pátio, e a saída já expirada pela retenção.
  perform pg_temp.f4md_saida('parceiro_painel', 'sombra', c_t - interval '1 day', 'Pátio em sombra de teste f4 medidas',
    jsonb_build_object('os_ids', jsonb_build_array(v_os_b), 'interessado_ids', jsonb_build_array(v_i_b)), 'p-sombra', 'sombra');
  perform pg_temp.f4md_saida('parceiro_recibo', 'enviada', c_t - interval '1 day', 'Recibo de teste f4 medidas',
    jsonb_build_object('os_ids', jsonb_build_array(v_os_b), 'interessado_ids', jsonb_build_array(v_i_b), 'bloco_patio', false), 'p-recibo');
  perform pg_temp.f4md_saida('parceiro_painel', 'enviada', c_t - interval '1 day', '[expirado]', '{}'::jsonb, 'p-expirada');
  m := pg_temp.f4md_m();
  if m.os_sem_aviso_no_painel - v0.os_sem_aviso_no_painel is distinct from 2::bigint then
    raise exception '2c: os_sem_aviso_no_painel % (esperava +2)', m.os_sem_aviso_no_painel - v0.os_sem_aviso_no_painel;
  end if;
  if m.veto_ignorado - v0.veto_ignorado is distinct from 1::bigint then
    raise exception '2d: veto_ignorado % (esperava +1)', m.veto_ignorado - v0.veto_ignorado;
  end if;
  if m.anfitria_no_painel - v0.anfitria_no_painel is distinct from 1::bigint then
    raise exception '2e: anfitria_no_painel % (esperava +1)', m.anfitria_no_painel - v0.anfitria_no_painel;
  end if;
  -- o recibo COM o bloco do pátio é de citação: o sem aviso sobe 1
  perform pg_temp.f4md_saida('parceiro_recibo', 'enviada', c_t - interval '1 day', 'Recibo com bloco de teste f4 medidas',
    jsonb_build_object('os_ids', jsonb_build_array(v_os_b), 'interessado_ids', jsonb_build_array(v_i_b), 'bloco_patio', true,
                       'visibilidade', jsonb_build_array(jsonb_build_object('interessado_id', v_i_b, 'visivel', true))), 'p-recibo-bloco');
  m := pg_temp.f4md_m();
  if m.os_sem_aviso_no_painel - v0.os_sem_aviso_no_painel is distinct from 3::bigint then
    raise exception '2f: o recibo com o bloco do pátio não contou (%)', m.os_sem_aviso_no_painel - v0.os_sem_aviso_no_painel;
  end if;

  -- ── 3. valor_ou_doc_ao_parceiro, só por saída real; o bloqueio do validador fica à parte ──
  m := pg_temp.f4md_m();
  if m.valor_ou_doc_ao_parceiro - v0.valor_ou_doc_ao_parceiro is distinct from 0::bigint then
    raise exception '3a: valor_ou_doc_ao_parceiro antes do cenário (%)', to_jsonb(m);
  end if;
  -- PDF ao "indicou" pelo sistema: o registro com papel=indicou conta; papel=contratante não; sem o padrão conta (papel nulo).
  insert into public.ai_comms_log (tipo, audiencia, entity_kind, phone, message_preview, status) values
    ('os_link', 'parceiro', 'service_order', '5547900017201', '[pdf parceiro] papel=indicou', 'sent'),
    ('os_link', 'parceiro', 'service_order', '5547900017201', '[pdf parceiro] papel=contratante', 'sent'),
    ('os_link', 'parceiro', 'service_order', '5547900017201', 'registro sem o padrão', 'sent'),
    ('os_link', 'parceiro', 'service_order', '5547900017201', '[pdf parceiro] papel=indicou', 'blocked');
  m := pg_temp.f4md_m();
  if m.valor_ou_doc_ao_parceiro - v0.valor_ou_doc_ao_parceiro is distinct from 2::bigint then
    raise exception '3b: ai_comms_log contou % (esperava +2: indicou e sem padrão)', m.valor_ou_doc_ao_parceiro - v0.valor_ou_doc_ao_parceiro;
  end if;
  -- O texto real com valor conta; o mesmo texto bloqueado pelo validador vai só a bloqueios_do_validador.
  perform pg_temp.f4md_saida('parceiro_recado', 'enviada', c_t - interval '3 hours', 'Recado inventado com a chave pix de teste', '{}'::jsonb, 'v-pix');
  perform pg_temp.f4md_saida('parceiro_recado', 'recusada', c_t - interval '2 hours', 'Recado inventado com R$ 500 de teste', '{}'::jsonb, 'v-bloq',
                             'ligado', 'validador');
  m := pg_temp.f4md_m();
  if m.valor_ou_doc_ao_parceiro - v0.valor_ou_doc_ao_parceiro is distinct from 3::bigint then
    raise exception '3c: a saída com valor (ou o bloqueio) contou errado (%)', m.valor_ou_doc_ao_parceiro - v0.valor_ou_doc_ao_parceiro;
  end if;
  if m.bloqueios_do_validador - v0.bloqueios_do_validador is distinct from 1::bigint then
    raise exception '3d: bloqueios_do_validador % (esperava +1)', m.bloqueios_do_validador - v0.bloqueios_do_validador;
  end if;

  -- O documento: pelo sistema (com via) à contratante, com o registro papel=contratante, não conta nada.
  perform pg_temp.f4md_doc('Orcamento_ORC-98956.pdf', c_t - interval '90 minutes', true);
  -- O eco com número no nome e sem detecção: fora da soma, em doc_mao_sem_deteccao.
  perform pg_temp.f4md_doc('Orcamento_ORC-98957_Fulano.pdf', c_t - interval '80 minutes');
  m := pg_temp.f4md_m();
  if m.valor_ou_doc_ao_parceiro - v0.valor_ou_doc_ao_parceiro is distinct from 3::bigint
     or m.doc_mao_sem_deteccao - v0.doc_mao_sem_deteccao is distinct from 1::bigint then
    raise exception '3e: o documento pelo sistema ou o eco sem detecção contou na soma (%)', to_jsonb(m);
  end if;
  -- O eco sem número no nome: na soma e em doc_sem_numero_no_nome.
  perform pg_temp.f4md_doc('Fotos_da_unidade.pdf', c_t - interval '70 minutes');
  m := pg_temp.f4md_m();
  if m.valor_ou_doc_ao_parceiro - v0.valor_ou_doc_ao_parceiro is distinct from 4::bigint
     or m.doc_sem_numero_no_nome - v0.doc_sem_numero_no_nome is distinct from 1::bigint then
    raise exception '3f: o eco sem número no nome (%)', to_jsonb(m);
  end if;
  -- O PDF à mão detectado: só registro (indicou) e decidida em C contam; registrada e decidida com papel comercial, não.
  v_msg := pg_temp.f4md_doc('OS_OS-98951_Fulano.pdf', c_t - interval '60 minutes');
  insert into public.parceiro_envios_a_mao (whatsapp_message_id, parceiro_id, service_order_id, numero_doc, enviado_em, situacao)
    values (v_msg, v_p, v_os_a, 'OS-98951', c_t - interval '60 minutes', 'so_registro');
  v_msg := pg_temp.f4md_doc('OS_OS-98955_Fulano.pdf', c_t - interval '50 minutes');
  insert into public.parceiro_envios_a_mao (whatsapp_message_id, parceiro_id, service_order_id, numero_doc, enviado_em, situacao, decidido_em)
    values (v_msg, v_p, v_os_e, 'OS-98955', c_t - interval '50 minutes', 'decidida', c_t - interval '40 minutes');
  v_msg := pg_temp.f4md_doc('Orcamento_ORC-98956_Fulano.pdf', c_t - interval '30 minutes');
  insert into public.parceiro_envios_a_mao (whatsapp_message_id, parceiro_id, service_order_id, numero_doc, enviado_em, situacao)
    values (v_msg, v_p, v_os_f, 'ORC-98956', c_t - interval '30 minutes', 'registrada');
  v_msg := pg_temp.f4md_doc('Orcamento_ORC-98956_Fulano_2.pdf', c_t - interval '20 minutes');
  insert into public.parceiro_envios_a_mao (whatsapp_message_id, parceiro_id, service_order_id, numero_doc, enviado_em, situacao, decidido_em)
    values (v_msg, v_p, v_os_f, 'ORC-98956', c_t - interval '20 minutes', 'decidida', c_t - interval '10 minutes');
  m := pg_temp.f4md_m();
  if m.valor_ou_doc_ao_parceiro - v0.valor_ou_doc_ao_parceiro is distinct from 6::bigint then
    raise exception '3g: o PDF à mão contou % (esperava +6 no total)', m.valor_ou_doc_ao_parceiro - v0.valor_ou_doc_ao_parceiro;
  end if;
  if m.doc_mao_sem_deteccao - v0.doc_mao_sem_deteccao is distinct from 1::bigint then
    raise exception '3h: o eco detectado foi a doc_mao_sem_deteccao (%)', m.doc_mao_sem_deteccao - v0.doc_mao_sem_deteccao;
  end if;

  -- ── 4. Painéis: enviados, sem edição nos 10 últimos e as linhas fora, por motivo ──
  insert into public.parceiro_paineis (parceiro_id, dia, estado, mudou, linhas, impressao, editado, criado_em) values
    (v_p, '2027-01-08', 'enviado', true, jsonb_build_array(
       jsonb_build_object('n', 1, 'interessado_id', v_i_a, 'service_order_id', v_os_a, 'estado', 'em_servico', 'desde', null),
       jsonb_build_object('n', null, 'interessado_id', v_i_b, 'service_order_id', v_os_b, 'estado', null, 'fora_por', 'sem_fato')),
     'teste', false, '2027-01-08 17:30-03'),
    (v_p, '2027-01-11', 'enviado', true, jsonb_build_array(
       jsonb_build_object('n', 1, 'interessado_id', v_i_a, 'service_order_id', v_os_a, 'estado', 'em_servico', 'desde', null),
       jsonb_build_object('n', null, 'interessado_id', v_i_e, 'service_order_id', v_os_e, 'estado', 'andamento', 'fora_por', 'tirada')),
     'teste', true, '2027-01-11 17:30-03'),
    (v_p, '2027-01-12', 'enviado', true, jsonb_build_array(
       jsonb_build_object('n', 1, 'interessado_id', v_i_a, 'service_order_id', v_os_a, 'estado', 'em_servico', 'desde', null),
       jsonb_build_object('n', null, 'interessado_id', v_i_d, 'service_order_id', v_os_d, 'estado', null, 'fora_por', 'sem_fato')),
     'teste', false, '2027-01-12 17:30-03');
  m := pg_temp.f4md_m();
  if m.painel_enviados - v0.painel_enviados is distinct from 3::bigint then
    raise exception '4a: painel_enviados (%)', m.painel_enviados - v0.painel_enviados;
  end if;
  if v0.painel_enviados = 0 and m.painel_sem_edicao_10 is distinct from 2::bigint then
    raise exception '4b: painel_sem_edicao_10 % (esperava 2)', m.painel_sem_edicao_10;
  end if;
  if coalesce((m.linhas_fora_painel ->> 'sem_fato')::bigint, 0) - coalesce((v0.linhas_fora_painel ->> 'sem_fato')::bigint, 0) is distinct from 2::bigint
     or coalesce((m.linhas_fora_painel ->> 'tirada')::bigint, 0) - coalesce((v0.linhas_fora_painel ->> 'tirada')::bigint, 0) is distinct from 1::bigint then
    raise exception '4c: linhas_fora_painel por motivo (%)', m.linhas_fora_painel;
  end if;

  -- ── 5. O fechamento das 17:30: só a sigla e contagens; desligado, nada ──
  -- O painel de hoje esperando o dono: 2 linhas, 1 igual à do último enviado (12/01) e 1 nova.
  insert into public.parceiro_paineis (parceiro_id, dia, estado, mudou, linhas, impressao, criado_em) values
    (v_p, '2027-01-13', 'aguardando', true, jsonb_build_array(
       jsonb_build_object('n', 1, 'interessado_id', v_i_a, 'service_order_id', v_os_a, 'estado', 'em_servico', 'desde', null),
       jsonb_build_object('n', 2, 'interessado_id', v_i_e, 'service_order_id', v_os_e, 'estado', 'andamento', 'desde', '2027-01-10'),
       jsonb_build_object('n', null, 'interessado_id', v_i_b, 'service_order_id', v_os_b, 'estado', null, 'fora_por', 'sem_fato')),
     'teste', c_t - interval '1 hour');
  v_cg := pg_temp.f4md_cliente('Gil Medida', '5547900017307');
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem) values (v_cg, v_p, c_t - interval '1 hour', 'nao_mp');
  update public.os_interessados oi set retido_em = c_t - interval '3 hours' where oi.id = v_i_f;
  perform public._parceiro_fila_por('pergunta', v_p, gen_random_uuid(), 'pergunta:teste-f4-medidas', null, '{}'::jsonb);
  v_r := public.parceiro_resumo_fechamento(c_t);
  v_linhas := v_r -> 'linhas';
  if jsonb_typeof(v_linhas) is distinct from 'array' then
    raise exception '5a: o fechamento sem lista (%)', v_r;
  end if;
  if not (v_linhas @> to_jsonb(array[
           'Pátio da RMD: 2 veículos, 1 mudou · *parceiro* para liberar',
           'NÃO RMD: 1 cliente hoje',
           format('Vínculos sem aviso: %s', v0.vinculos_sem_aviso + 2),
           format('Respostas ao aviso para decidir: %s', 1) || ' · *parceiro*',
           'RMD: 1 pergunta esperando · *parceiro*']::text[])) then
    raise exception '5b: as linhas do fechamento (%)', v_linhas;
  end if;
  v_txt := v_linhas::text;
  if v_txt ~ '[0-9]{8}' or v_txt ~* 'medida|ana |bia |dora|enzo|gil |caio|f[aá]bio' then
    raise exception '5c: o fechamento trouxe nome de cliente ou telefone (%)', v_txt;
  end if;
  -- o fechamento pede, não abre: nenhum cartão nasceu
  if exists (select 1 from public.parceiro_cartoes c where c.criado_em >= c_t - interval '1 day') then
    raise exception '5d: o fechamento abriu um cartão';
  end if;
  update public.retorno_config set parceiro_modo = 'desligado' where id;
  if public.parceiro_resumo_fechamento(c_t) is distinct from '{"linhas": []}'::jsonb then
    raise exception '5e: desligado, o fechamento trouxe linhas (%)', public.parceiro_resumo_fechamento(c_t);
  end if;

  -- ── 6. A retenção, pelo parceiro_vigia às 04:00, com parceiro_modo = 'desligado' ──
  -- Antes: a saída antiga que cita o vínculo sem aviso conta em os_sem_aviso (ainda tem os dados do envio).
  v_s_velha := pg_temp.f4md_saida('parceiro_painel', 'enviada', c_velho, 'Pátio antigo de teste f4 medidas',
    jsonb_build_object('os_ids', jsonb_build_array(v_os_b), 'interessado_ids', jsonb_build_array(v_i_b),
                       'visibilidade', jsonb_build_array(jsonb_build_object('interessado_id', v_i_b, 'visivel', true))), 'r-velha');
  v_s_agendada := pg_temp.f4md_saida('parceiro_recado', 'agendada', c_velho, null, '{"x": 1}'::jsonb, 'r-agendada');
  m := pg_temp.f4md_m();
  if m.os_sem_aviso_no_painel - v0.os_sem_aviso_no_painel is distinct from 4::bigint then
    raise exception '6a: a saída antiga não contou antes da retenção (%)', m.os_sem_aviso_no_painel - v0.os_sem_aviso_no_painel;
  end if;
  insert into public.parceiro_paineis (parceiro_id, dia, estado, mudou, linhas, impressao, criado_em)
    values (v_p, '2026-06-01', 'enviado', true,
            jsonb_build_array(jsonb_build_object('n', 1, 'interessado_id', v_i_a, 'service_order_id', v_os_a, 'estado', 'em_servico')),
            'teste', c_velho)
    returning id into v_painel_velho;
  insert into public.parceiro_cartoes (gatilho, dia, estado, hash, texto, criado_em, expira_em, dados)
    values ('puxar', '2026-06-01', 'decidido', 'h', 'Cartão antigo de teste f4 medidas', c_velho, c_velho + interval '24 hours', '{"x": 1}')
    returning id into v_cartao;
  insert into public.parceiro_cartao_itens (cartao_id, n, tipo, hash, texto_mostrado, opcoes, retrato, estado)
    values (v_cartao, 1, 'vinculo', 'h', 'Item antigo de teste f4 medidas', '[{"letra": "A"}]', '{"ver": ["linha antiga"]}', 'feito')
    returning id into v_item;
  -- Os provisórios nascidos pela MP: x sem OS, y só com rascunho (ativo), z com OS de verdade, w não provisório.
  insert into public.clients (type, name, whatsapp, provisorio, origem, active) values ('individual', 'Xica Provisoria', '5547900017311', true, 'retorno', false)
    returning id into v_x;
  insert into public.vessels (client_id, name, asset_type, active) values (v_x, 'Daily', 'Veículo', false);
  insert into public.clients (type, name, whatsapp, provisorio, origem, active) values ('individual', 'Yara Provisoria', '5547900017312', true, 'retorno', true)
    returning id into v_y;
  v_os_y := pg_temp.f4md_os(v_y, 'ORÇ-98957', 'draft', 'draft');
  insert into public.clients (type, name, whatsapp, provisorio, origem, active) values ('individual', 'Zeca Provisorio', '5547900017313', true, 'retorno', true)
    returning id into v_z;
  v_os_z := pg_temp.f4md_os(v_z, 'OS-98958', 'open');
  insert into public.clients (type, name, whatsapp, provisorio, active) values ('individual', 'Wanda Cadastrada', '5547900017314', false, true)
    returning id into v_w;
  insert into public.parceiro_pedidos (abertura_id, parceiro_id, primeiro_nome, veiculo, whatsapp_informado, client_id, estado, cadastro_simulado, criado_em)
    values (pg_temp.f4md_caso('5547900017201', c_velho), v_p, 'Xica', 'Daily', '5547900017311', v_x, 'decidido', '{"acao": "criaria"}', c_velho)
    returning id into v_ped_x;
  insert into public.parceiro_pedidos (abertura_id, parceiro_id, primeiro_nome, client_id, estado, criado_em)
    values (pg_temp.f4md_caso('5547900017202', c_velho), v_p, 'Yara', v_y, 'decidido', c_velho),
           (pg_temp.f4md_caso('5547900017203', c_velho), v_p, 'Zeca', v_z, 'decidido', c_velho),
           (pg_temp.f4md_caso('5547900017204', c_velho), v_p, 'Wanda', v_w, 'decidido', c_velho);
  select count(*) into v_vetos from public.parceiro_vetos where parceiro_id = v_p;
  select count(*) into v_vinculos from public.os_interessados where parceiro_id = v_p;

  v_r := public.parceiro_vigia(timestamptz '2027-01-13 04:00-03');
  if v_r -> 'passos' -> 'retencao' is null or (v_r -> 'passos' -> 'retencao' ->> 'ok') is distinct from 'true' then
    raise exception '6b: o vigia das 04:00 não rodou a retenção em desligado (%)', v_r;
  end if;
  if (select pp.linhas from public.parceiro_paineis pp where pp.id = v_painel_velho) is distinct from '[]'::jsonb then
    raise exception '6c: o painel antigo ficou com as linhas';
  end if;
  if exists (select 1 from public.parceiro_cartao_itens i where i.id = v_item
              and (i.texto_mostrado is not null or i.retrato is distinct from '{}'::jsonb or i.opcoes is distinct from '[]'::jsonb)) then
    raise exception '6d: o item do cartão antigo ficou com o texto';
  end if;
  if exists (select 1 from public.parceiro_cartoes c where c.id = v_cartao
              and (c.texto is distinct from '[expirado]' or c.dados is distinct from '{}'::jsonb)) then
    raise exception '6e: o cartão antigo ficou com o texto';
  end if;
  if exists (select 1 from public.retorno_saidas s where s.id = v_s_velha
              and (s.texto is distinct from '[expirado]' or s.dados is distinct from '{}'::jsonb)) then
    raise exception '6f: a saída antiga ficou com o texto';
  end if;
  if (select s.dados from public.retorno_saidas s where s.id = v_s_agendada) is distinct from '{"x": 1}'::jsonb then
    raise exception '6g: a retenção mexeu na saída que ainda não terminou';
  end if;
  if exists (select 1 from public.parceiro_pedidos pp where pp.id = v_ped_x
              and (pp.primeiro_nome is not null or pp.veiculo is not null or pp.whatsapp_informado is not null or pp.cadastro_simulado is not null)) then
    raise exception '6h: o pedido antigo ficou com nome, veículo, número ou simulação';
  end if;
  if exists (select 1 from public.clients c where c.id in (v_x, v_y)
              and (c.active is not false or c.name is distinct from 'Cliente pela MP (expirado)' or c.whatsapp is not null or c.phone is not null)) then
    raise exception '6i: o provisório sem OS de verdade não foi anonimizado';
  end if;
  if exists (select 1 from public.vessels v where v.client_id in (v_x, v_y)
              and (v.active is not false or v.name is distinct from 'Veículo (expirado)')) then
    raise exception '6j: a unidade do provisório não foi anonimizada';
  end if;
  if (select c.name from public.clients c where c.id = v_z) is distinct from 'Zeca Provisorio'
     or (select c.active from public.clients c where c.id = v_z) is not true then
    raise exception '6k: o provisório com OS de verdade foi mexido';
  end if;
  if (select c.name from public.clients c where c.id = v_w) is distinct from 'Wanda Cadastrada' then
    raise exception '6l: o cliente que não é provisório foi mexido';
  end if;
  if (select so.client_id from public.service_orders so where so.id = v_os_y) is distinct from v_y then
    raise exception '6m: o rascunho perdeu o cliente';
  end if;
  if (select count(*) from public.parceiro_vetos where parceiro_id = v_p) is distinct from v_vetos
     or (select count(*) from public.os_interessados where parceiro_id = v_p) is distinct from v_vinculos then
    raise exception '6n: a retenção apagou veto ou vínculo';
  end if;
  -- Depois: a saída expirada sai do os_sem_aviso (não vira falso positivo).
  m := pg_temp.f4md_m();
  if m.os_sem_aviso_no_painel - v0.os_sem_aviso_no_painel is distinct from 3::bigint then
    raise exception '6o: a saída expirada ainda conta em os_sem_aviso_no_painel (%)', m.os_sem_aviso_no_painel - v0.os_sem_aviso_no_painel;
  end if;
  -- Os painéis e saídas de 2027 não foram tocados.
  if exists (select 1 from public.parceiro_paineis pp where pp.parceiro_id = v_p and pp.dia >= '2027-01-01' and pp.linhas = '[]'::jsonb) then
    raise exception '6p: a retenção apagou painel novo';
  end if;
  -- Fora das 04:00, o vigia não roda a retenção.
  v_r := public.parceiro_vigia(timestamptz '2027-01-13 05:00-03');
  if v_r -> 'passos' -> 'retencao' is not null then
    raise exception '6q: a retenção rodou fora das 04:00 (%)', v_r;
  end if;

  -- ── A varredura: a visão com security_invoker e fechada a anon e authenticated; as funções da P14 fechadas ──
  if not exists (select 1 from pg_class c where c.oid = 'public.retorno_f4_medidas'::regclass
                  and coalesce(c.reloptions, '{}') @> array['security_invoker=on']) then
    raise exception 'grants: retorno_f4_medidas sem security_invoker';
  end if;
  if has_table_privilege('anon', 'public.retorno_f4_medidas', 'select')
     or has_table_privilege('authenticated', 'public.retorno_f4_medidas', 'select')
     or not has_table_privilege('service_role', 'public.retorno_f4_medidas', 'select') then
    raise exception 'grants: retorno_f4_medidas aberta a anon/authenticated ou fechada ao service_role';
  end if;
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?parceiro_'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
      raise exception 'grants: % aberta a anon/authenticated', v_rec.nome;
    end if;
    if v_rec.proname !~ '^_' and not has_function_privilege('service_role', v_rec.oid, 'execute') then
      raise exception 'grants: % sem execute para o service_role', v_rec.nome;
    end if;
    if v_rec.prosecdef and not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
      raise exception 'grants: % é SECURITY DEFINER sem search_path', v_rec.nome;
    end if;
  end loop;
  if to_regprocedure('public.parceiro_resumo_fechamento(timestamptz)') is null
     or to_regprocedure('public.parceiro_retencao_rodada(timestamptz)') is null then
    raise exception 'grants: a varredura não achou as funções da P14 (%)', v_n_fun;
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_medidas', true, '{}');
end
$medidas$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
