-- Retorno F4 (P9): o PDF mandado à mão e o repassar. Só o eco do aparelho a número de parceiro (nunca o envio do
-- sistema), só o número do documento (nunca o nome do arquivo), ORC- vira ORÇ-, a marca d'água e os três modos, as letras
-- A, B e C (com o rascunho sem origem e o de outro parceiro), o repassar só a quem não tem telefone e o repassar aprovado em
-- sombra que renasce uma vez ao ligar. Roda só pela bancada (grupo 7, F4_ONDA=5, F4_TESTES=retorno_f4_mao). Termina em
-- ROLLBACK. Telefones de teste 55479000156xx e 55479000157xx; nomes e números de documento inventados (9876x). Relógio:
-- ter 12/01/2027 10:00.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f4m_cliente(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

-- A OS com o número dado (criada antes de hoje: parceiro_propor confere a regra 8 no relógio do banco).
create or replace function pg_temp.f4m_os(p_cliente uuid, p_numero text, p_status text default 'open', p_quote text default 'approved',
                                          p_origem_parceiro uuid default null) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, origem_parceiro_id)
  values (p_numero, p_cliente, v_v, p_status, p_quote, 'repair', '2026-10-01 10:00-03', '2026-10-01 10:00-03', 0, p_origem_parceiro)
  returning id into v_id;
  return v_id;
end $f$;

create or replace function pg_temp.f4m_liga(p_os uuid, p_parceiro uuid, p_papel text, p_aviso_em timestamptz default '2027-01-05 10:00-03',
                                            p_aviso text default 'mensagem') returns uuid
language sql as $f$
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem, aviso_ao_cliente, aviso_em,
                                      confirmado_em, pacote)
  select so.id, p_parceiro, so.client_id, p_papel, 'confirmado', 'dono',
         case when p_aviso_em is null then 'nao_avisado' else p_aviso end, p_aviso_em, timestamptz '2027-01-01 10:00-03',
         case when p_papel in ('contratante', 'pagador') then 'completo' else 'status' end
    from public.service_orders so where so.id = p_os
  returning id
$f$;

-- O documento que saiu: eco do aparelho (data, sem via) ou envio do sistema (com via e saida_humana).
create or replace function pg_temp.f4m_doc(p_fone text, p_arquivo text, p_em timestamptz, p_via boolean default false,
                                           p_tipo text default 'document') returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, raw_payload, saida_humana, occurred_at)
  values ('outbound', p_fone, p_tipo, null, 'teste-f4-mao-' || md5(p_fone || coalesce(p_arquivo, '') || p_em::text || random()::text),
          case when p_via
               then jsonb_build_object('via', 'whatsapp-send', 'data', jsonb_build_object('message', jsonb_build_object('documentMessage', jsonb_build_object('fileName', p_arquivo))))
               else jsonb_build_object('data', jsonb_build_object('source', 'unknown', 'message', jsonb_build_object('documentMessage', jsonb_build_object('fileName', p_arquivo))))
          end,
          case when p_via then true end, p_em)
  returning id
$f$;

create or replace function pg_temp.f4m_concluir(p_os uuid, p_em timestamptz) returns void
language sql as $f$
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, texto)
  values (p_em, (p_em at time zone 'America/Sao_Paulo')::date, true, 'dono', 'concluir', p_os, 'concluiu no teste')
$f$;

create or replace function pg_temp.f4m_envio(p_msg uuid) returns public.parceiro_envios_a_mao
language sql as $f$
  select e from public.parceiro_envios_a_mao e where e.whatsapp_message_id = p_msg
$f$;

do $mao$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter
  v_dono uuid;
  v_p uuid; v_outro uuid;
  v_carla uuid; v_fabia uuid;
  v_n1 uuid;
  v_c uuid;
  v_os_ind uuid; v_os_con uuid; v_os_c uuid; v_os_livre uuid; v_os_novo uuid; v_os_rasc uuid; v_os_alheio uuid; v_os_reg uuid;
  v_os_r1 uuid; v_os_r2 uuid; v_os_r3 uuid; v_os_r4 uuid; v_os_r5 uuid;
  v_i_ind uuid; v_i_con uuid; v_i_c uuid; v_i_reg uuid; v_i_r1 uuid; v_i_r4 uuid; v_i_r5 uuid;
  v_m0 uuid; v_m_ind uuid; v_m_con uuid; v_m_via uuid; v_m_fora uuid; v_m_sem uuid; v_m_txt uuid; v_m_c uuid; v_m_livre uuid;
  v_m_novo uuid; v_m_rasc uuid; v_m_alheio uuid; v_m_reg uuid; v_m_nada uuid;
  v_e public.parceiro_envios_a_mao;
  v_oi public.os_interessados;
  v_r jsonb;
  v_n bigint;
  v_s uuid;
  v_rec record;
  v_n_fun integer := 0;
begin
  begin
  select d.id into v_dono from public._comprovante_dono() d;
  if v_dono is null then
    raise exception '0: sem o dono (_comprovante_dono) no banco';
  end if;
  update public.retorno_config
     set modo = 'sombra', parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}', pdf_mao_modo = 'desligado', parceiro_pdf_ate = null,
         proximo_envio_em = null, segura_tudo_ate = null, so_reativo = false, iniciadas_dia_max = 50
   where id;

  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Mão F4', 'RMA', 'revenda_e_patio') returning id into v_p;
  insert into public.parceiros (nome, sigla, tipo) values ('Outra Revenda Mão F4', 'OMF', 'revenda') returning id into v_outro;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Fábia', 'financeiro') returning id into v_fabia;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_documento)
    values (v_carla, '5547900015601', '00015601', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n1;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, uso)
    values (v_fabia, '5547900015602', '00015602', '47', 'confirmado', c_t - interval '30 days', 'financeiro');

  -- As OS: o ORÇ só indicado, a OS contratada, uma indicada para a letra C, uma sem vínculo, uma para criar o vínculo,
  -- o rascunho sem origem, o rascunho de outro parceiro e uma para o modo registrar.
  v_c := pg_temp.f4m_cliente('Ana Mao', '5547900015711');
  v_os_ind := pg_temp.f4m_os(v_c, 'ORÇ-98761');
  v_i_ind := pg_temp.f4m_liga(v_os_ind, v_p, 'indicou');
  v_c := pg_temp.f4m_cliente('Bia Mao', '5547900015712');
  v_os_con := pg_temp.f4m_os(v_c, 'OS-98762');
  v_i_con := pg_temp.f4m_liga(v_os_con, v_p, 'contratante');
  v_c := pg_temp.f4m_cliente('Caio Mao', '5547900015713');
  v_os_c := pg_temp.f4m_os(v_c, 'OS-98763');
  v_i_c := pg_temp.f4m_liga(v_os_c, v_p, 'indicou');
  v_c := pg_temp.f4m_cliente('Dora Mao', '5547900015714');
  v_os_livre := pg_temp.f4m_os(v_c, 'OS-98764');
  v_c := pg_temp.f4m_cliente('Davi Mao', '5547900015715');
  v_os_novo := pg_temp.f4m_os(v_c, 'OS-98765');
  v_c := pg_temp.f4m_cliente('Eva Mao', '5547900015716');
  v_os_rasc := pg_temp.f4m_os(v_c, 'ORÇ-98766', 'draft', 'draft');
  v_c := pg_temp.f4m_cliente('Enzo Mao', '5547900015717');
  v_os_alheio := pg_temp.f4m_os(v_c, 'ORÇ-98767', 'draft', 'draft', v_outro);
  v_c := pg_temp.f4m_cliente('Gil Mao', '5547900015718');
  v_os_reg := pg_temp.f4m_os(v_c, 'OS-98768');
  v_i_reg := pg_temp.f4m_liga(v_os_reg, v_p, 'indicou');

  -- ── 9a. Desligado: nada é gravado e a marca avança; ao ligar, o documento anterior à marca não vira linha ──
  v_m0 := pg_temp.f4m_doc('5547900015601', 'Orcamento_ORC-98761_Antigo.pdf', c_t - interval '2 hours');
  v_r := public.parceiro_detectar_pdf(c_t - interval '1 hour');
  if exists (select 1 from public.parceiro_envios_a_mao)
     or (select c.parceiro_pdf_ate from public.retorno_config c where c.id) is distinct from c_t - interval '1 hour' then
    raise exception '9a: desligado gravou ou não avançou a marca (%)', v_r;
  end if;
  update public.retorno_config set pdf_mao_modo = 'perguntar' where id;

  -- ── 1, 2, 3 e 7. Os documentos de hoje ──
  v_m_ind := pg_temp.f4m_doc('5547900015601', 'Orcamento_ORC-98761_Fulano.pdf', c_t - interval '50 minutes');
  v_m_con := pg_temp.f4m_doc('5547900015602', 'OS_OS-98762_Beltrano_Unidade.pdf', c_t - interval '40 minutes');
  v_m_via := pg_temp.f4m_doc('5547900015601', 'Orcamento_ORC-98763_Sicrano.pdf', c_t - interval '35 minutes', true);
  v_m_fora := pg_temp.f4m_doc('5547900015799', 'Orcamento_ORC-98764_Fulano.pdf', c_t - interval '30 minutes');
  v_m_sem := pg_temp.f4m_doc('5547900015601', 'Fotos_da_unidade.pdf', c_t - interval '25 minutes');
  v_m_txt := pg_temp.f4m_doc('5547900015601', 'Orcamento_ORC-98761_Fulano.pdf', c_t - interval '20 minutes', false, 'text');
  v_m_c := pg_temp.f4m_doc('5547900015601', 'OS_OS-98763_Ciclano.pdf', c_t - interval '15 minutes');
  v_m_livre := pg_temp.f4m_doc('5547900015601', 'OS_OS-98764_Fulana.pdf', c_t - interval '14 minutes');
  v_m_novo := pg_temp.f4m_doc('5547900015602', 'OS_OS-98765_Fulano.pdf', c_t - interval '13 minutes');
  v_m_rasc := pg_temp.f4m_doc('5547900015601', 'Orcamento_ORC-98766_Fulano.pdf', c_t - interval '12 minutes');
  v_m_alheio := pg_temp.f4m_doc('5547900015601', 'Orcamento_ORC-98767_Fulano.pdf', c_t - interval '11 minutes');
  v_m_nada := pg_temp.f4m_doc('5547900015601', 'Orcamento_ORC-98799_Fulano.pdf', c_t - interval '10 minutes');
  v_r := public.parceiro_detectar_pdf(c_t);
  -- 9a. o documento antes da marca não virou linha
  if (pg_temp.f4m_envio(v_m0)).id is not null then
    raise exception '9b: documento anterior à marca virou linha';
  end if;
  -- 1. só o número, nunca o nome; via e número de fora, ignorados
  v_e := pg_temp.f4m_envio(v_m_ind);
  if v_e.numero_doc is distinct from 'ORC-98761' or v_e.parceiro_id is distinct from v_p or v_e.enviado_em is distinct from c_t - interval '50 minutes' then
    raise exception '1a: o número do documento (%)', v_e;
  end if;
  if exists (select 1 from public.parceiro_envios_a_mao e where row_to_json(e)::text ~* '(fulano|beltrano|ciclano|orcamento_|\.pdf)') then
    raise exception '1b: o nome do arquivo foi gravado';
  end if;
  if (pg_temp.f4m_envio(v_m_via)).id is not null or (pg_temp.f4m_envio(v_m_fora)).id is not null then
    raise exception '1c: envio do sistema (via) ou a número de fora foi gravado';
  end if;
  -- 2. nome sem número e texto no lugar de documento: ignorados
  if (pg_temp.f4m_envio(v_m_sem)).id is not null or (pg_temp.f4m_envio(v_m_txt)).id is not null then
    raise exception '2: nome sem número ou texto foi gravado';
  end if;
  -- 7. ORC- acha o ORÇ-
  if v_e.service_order_id is distinct from v_os_ind then
    raise exception '7: ORC-98761 não achou o ORÇ-98761';
  end if;
  -- 3. perguntar: contratante registrada sem item; só indicou perguntada com item
  if v_e.situacao is distinct from 'perguntada'
     or not exists (select 1 from public.parceiro_fila f where f.chave = 'pdf_mao:' || v_e.id and f.tipo = 'pdf_mao' and f.referencia = v_e.id) then
    raise exception '3a: o indicou não virou pergunta (%)', v_e.situacao;
  end if;
  v_e := pg_temp.f4m_envio(v_m_con);
  if v_e.situacao is distinct from 'registrada' or v_e.numero_doc is distinct from 'OS-98762'
     or exists (select 1 from public.parceiro_fila f where f.chave = 'pdf_mao:' || v_e.id) then
    raise exception '3b: o contratante (%)', v_e.situacao;
  end if;
  -- OS não achada: ignorada, sem item
  v_e := pg_temp.f4m_envio(v_m_nada);
  if v_e.situacao is distinct from 'ignorada' or v_e.service_order_id is not null
     or exists (select 1 from public.parceiro_fila f where f.chave = 'pdf_mao:' || v_e.id) then
    raise exception '3c: OS não achada (%)', v_e.situacao;
  end if;

  -- ── 6. A marca d'água não reprocessa ──
  select count(*) into v_n from public.parceiro_envios_a_mao;
  perform public.parceiro_detectar_pdf(c_t + interval '1 minute');
  if (select count(*) from public.parceiro_envios_a_mao) is distinct from v_n
     or (select c.parceiro_pdf_ate from public.retorno_config c where c.id) is distinct from c_t + interval '1 minute' then
    raise exception '6: a marca reprocessou ou não andou';
  end if;

  -- ── 9b. registrar: so_registro, sem item ──
  update public.retorno_config set pdf_mao_modo = 'registrar' where id;
  v_m_reg := pg_temp.f4m_doc('5547900015601', 'OS_OS-98768_Fulano.pdf', c_t + interval '2 minutes');
  perform public.parceiro_detectar_pdf(c_t + interval '3 minutes');
  v_e := pg_temp.f4m_envio(v_m_reg);
  if v_e.situacao is distinct from 'so_registro' or exists (select 1 from public.parceiro_fila f where f.chave = 'pdf_mao:' || v_e.id) then
    raise exception '9c: registrar (%)', v_e.situacao;
  end if;
  update public.retorno_config set pdf_mao_modo = 'perguntar' where id;

  -- ── 4. As letras ──
  begin
    perform public.parceiro_decidir_pdf_mao((pg_temp.f4m_envio(v_m_ind)).id, 'A', gen_random_uuid(), c_t);
    raise exception '4a: quem não é o dono decidiu';
  exception when sqlstate '42501' then
    null;
  end;
  -- A sobre o vínculo indicou: contratante, pacote completo, base decisao_do_dono, com audit_log
  v_r := public.parceiro_decidir_pdf_mao((pg_temp.f4m_envio(v_m_ind)).id, 'a', v_dono, c_t + interval '5 minutes');
  select * into v_oi from public.os_interessados oi where oi.id = v_i_ind;
  if (v_r ->> 'ok')::boolean is not true or v_oi.papel is distinct from 'contratante' or v_oi.base is distinct from 'decisao_do_dono'
     or v_oi.pacote is distinct from 'completo' or v_oi.pessoa_id is distinct from v_carla
     or (pg_temp.f4m_envio(v_m_ind)).situacao is distinct from 'decidida'
     or not exists (select 1 from public.audit_log a where a.table_name = 'os_interessados' and a.record_id = v_i_ind and a.action = 'update') then
    raise exception '4b: letra A com vínculo (% % %)', v_r, v_oi.papel, v_oi.base;
  end if;
  -- C com vínculo: o papel e a base não mudam
  v_r := public.parceiro_decidir_pdf_mao((pg_temp.f4m_envio(v_m_c)).id, 'C', v_dono, c_t + interval '5 minutes');
  select * into v_oi from public.os_interessados oi where oi.id = v_i_c;
  if (v_r ->> 'ok')::boolean is not true or v_oi.papel is distinct from 'indicou' or v_oi.base is distinct from 'legitimo_interesse'
     or (pg_temp.f4m_envio(v_m_c)).situacao is distinct from 'decidida' then
    raise exception '4c: letra C com vínculo mudou o vínculo (% %)', v_oi.papel, v_oi.base;
  end if;
  -- C sem vínculo: nenhuma linha em os_interessados, nenhum aviso, nenhum painel
  v_r := public.parceiro_decidir_pdf_mao((pg_temp.f4m_envio(v_m_livre)).id, 'C', v_dono, c_t + interval '5 minutes');
  if (v_r ->> 'ok')::boolean is not true
     or exists (select 1 from public.os_interessados oi where oi.service_order_id = v_os_livre)
     or exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente'
                 and s.dados ->> 'client_id' = (select so.client_id::text from public.service_orders so where so.id = v_os_livre))
     or exists (select 1 from public.parceiro_paineis pp where pp.parceiro_id = v_p) then
    raise exception '4d: letra C sem vínculo criou alguma coisa';
  end if;
  -- B sem vínculo: propõe, confirma (com o aviso de sempre) e grava pagador com base decisao_do_dono
  v_r := public.parceiro_decidir_pdf_mao((pg_temp.f4m_envio(v_m_novo)).id, 'B', v_dono, c_t + interval '6 minutes');
  select * into v_oi from public.os_interessados oi where oi.service_order_id = v_os_novo and oi.parceiro_id = v_p;
  if (v_r ->> 'ok')::boolean is not true or v_oi.situacao is distinct from 'confirmado' or v_oi.papel is distinct from 'pagador'
     or v_oi.base is distinct from 'decisao_do_dono' or v_oi.origem is distinct from 'dono' or v_oi.pessoa_id is distinct from v_fabia
     or not exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente'
                     and s.dados ->> 'client_id' = v_oi.client_id::text and s.dados ->> 'parceiro_id' = v_p::text) then
    raise exception '4e: letra B sem vínculo (% % %)', v_r, v_oi.situacao, v_oi.papel;
  end if;
  -- A sobre o rascunho sem origem: a origem é gravada com audit_log, e o vínculo nasce confirmado (sem os_fora)
  v_r := public.parceiro_decidir_pdf_mao((pg_temp.f4m_envio(v_m_rasc)).id, 'A', v_dono, c_t + interval '7 minutes');
  select * into v_oi from public.os_interessados oi where oi.service_order_id = v_os_rasc and oi.parceiro_id = v_p;
  if (v_r ->> 'ok')::boolean is not true
     or (select so.origem_parceiro_id from public.service_orders so where so.id = v_os_rasc) is distinct from v_p
     or not exists (select 1 from public.audit_log a where a.table_name = 'service_orders' and a.record_id = v_os_rasc
                     and a.action = 'update' and a.changed_by = 'dono')
     or v_oi.situacao is distinct from 'confirmado' or v_oi.papel is distinct from 'contratante' then
    raise exception '4f: letra A no rascunho sem origem (%)', v_r;
  end if;
  -- A sobre o rascunho de outro parceiro: nada muda
  v_r := public.parceiro_decidir_pdf_mao((pg_temp.f4m_envio(v_m_alheio)).id, 'A', v_dono, c_t + interval '8 minutes');
  if v_r ->> 'motivo' is distinct from 'outro_parceiro' or (v_r ->> 'ok')::boolean is not false
     or (select so.origem_parceiro_id from public.service_orders so where so.id = v_os_alheio) is distinct from v_outro
     or exists (select 1 from public.os_interessados oi where oi.service_order_id = v_os_alheio)
     or (pg_temp.f4m_envio(v_m_alheio)).situacao is distinct from 'perguntada' then
    raise exception '4g: o rascunho de outro parceiro mudou (%)', v_r;
  end if;
  -- decidida não decide de novo; ignorada não tem letra
  if public.parceiro_decidir_pdf_mao((pg_temp.f4m_envio(v_m_ind)).id, 'B', v_dono, c_t) ->> 'motivo' is distinct from 'ja_decidida'
     or public.parceiro_decidir_pdf_mao((pg_temp.f4m_envio(v_m_nada)).id, 'A', v_dono, c_t) ->> 'motivo' is distinct from 'sem_os' then
    raise exception '4h: decidir de novo ou sem OS';
  end if;
  begin
    perform public.parceiro_decidir_pdf_mao((pg_temp.f4m_envio(v_m_alheio)).id, 'D', v_dono, c_t);
    raise exception '4i: letra fora da lista passou';
  exception when sqlstate '22023' then
    null;
  end;

  -- ── 5. O repassar: só cliente sem telefone, vínculo visível e pronto; idempotente; sem pronto, nenhum ──
  v_c := pg_temp.f4m_cliente('Fabi Mao', null);
  v_os_r1 := pg_temp.f4m_os(v_c, 'OS-98771', 'completed');
  perform pg_temp.f4m_concluir(v_os_r1, c_t - interval '5 hours');
  v_i_r1 := pg_temp.f4m_liga(v_os_r1, v_p, 'indicou', c_t - interval '3 days', 'pela_revenda');
  v_c := pg_temp.f4m_cliente('Gabi Mao', '5547900015721');                          -- com telefone: não
  v_os_r2 := pg_temp.f4m_os(v_c, 'OS-98772', 'completed');
  perform pg_temp.f4m_concluir(v_os_r2, c_t - interval '5 hours');
  perform pg_temp.f4m_liga(v_os_r2, v_p, 'indicou');
  v_c := pg_temp.f4m_cliente('Hilda Mao', null);                                    -- sem pronto: não
  v_os_r3 := pg_temp.f4m_os(v_c, 'OS-98773', 'open');
  perform pg_temp.f4m_liga(v_os_r3, v_p, 'indicou', c_t - interval '3 days', 'pela_revenda');
  v_c := pg_temp.f4m_cliente('Iris Mao', null);                                     -- vínculo não visível (sem aviso): não
  v_os_r4 := pg_temp.f4m_os(v_c, 'OS-98774', 'completed');
  perform pg_temp.f4m_concluir(v_os_r4, c_t - interval '5 hours');
  v_i_r4 := pg_temp.f4m_liga(v_os_r4, v_p, 'indicou', null);
  v_r := public.parceiro_repassar_rodada(c_t);
  perform public.parceiro_repassar_rodada(c_t + interval '1 minute');
  if (select count(*) from public.parceiro_fila f where f.tipo = 'repassar' and f.chave = 'repassar:' || v_os_r1 || ':' || v_p
        and f.referencia = v_os_r1 and f.dados ->> 'interessado_id' = v_i_r1::text) is distinct from 1::bigint
     or (select f.valido_ate from public.parceiro_fila f where f.chave = 'repassar:' || v_os_r1 || ':' || v_p)
        is distinct from c_t - interval '5 hours' + interval '48 hours' then
    raise exception '5a: o repassar da OS pronta de cliente sem telefone (%)', v_r;
  end if;
  if exists (select 1 from public.parceiro_fila f where f.tipo = 'repassar' and f.referencia in (v_os_r2, v_os_r3, v_os_r4)) then
    raise exception '5b: repassar com telefone, sem pronto ou sem vínculo visível';
  end if;

  -- ── 8. Sombra → ligado do repassar: o aprovado em sombra renasce uma vez; fora da regra de ouro ou pronto vencido, não ──
  v_s := public.parceiro_agendar('parceiro_repassar', 'padrao', v_n1, null,
           jsonb_build_object('os_ids', jsonb_build_array(v_os_r1), 'interessado_ids', jsonb_build_array(v_i_r1), 'service_order_id', v_os_r1),
           c_t, 'parceiro:repassar:' || v_os_r1 || ':pronto', 'aviso');
  if (select s.dedupe_key from public.retorno_saidas s where s.id = v_s) is distinct from 'parceiro:repassar:' || v_os_r1 || ':pronto:sombra' then
    raise exception '8a: o repassar em sombra não gravou a chave de sombra';
  end if;
  v_c := pg_temp.f4m_cliente('Joana Mao', null);                                    -- vetada depois do sim
  v_os_r5 := pg_temp.f4m_os(v_c, 'OS-98775', 'completed');
  perform pg_temp.f4m_concluir(v_os_r5, c_t - interval '5 hours');
  v_i_r5 := pg_temp.f4m_liga(v_os_r5, v_p, 'indicou', c_t - interval '3 days', 'pessoalmente');
  perform public.parceiro_agendar('parceiro_repassar', 'padrao', v_n1, null,
            jsonb_build_object('os_ids', jsonb_build_array(v_os_r5), 'interessado_ids', jsonb_build_array(v_i_r5), 'service_order_id', v_os_r5),
            c_t, 'parceiro:repassar:' || v_os_r5 || ':pronto', 'aviso');
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem) values (v_c, v_p, c_t, 'dono');
  update public.retorno_config set parceiro_modo = 'ligado', parceiro_tipos_ligados = array['parceiro_repassar']::text[] where id;
  perform public.parceiro_repassar_rodada(c_t + interval '10 minutes');
  perform public.parceiro_repassar_rodada(c_t + interval '11 minutes');
  if (select count(*) from public.retorno_saidas s where s.dedupe_key = 'parceiro:repassar:' || v_os_r1 || ':pronto') is distinct from 1::bigint
     or (select s.estado from public.retorno_saidas s where s.dedupe_key = 'parceiro:repassar:' || v_os_r1 || ':pronto') is distinct from 'agendada' then
    raise exception '8b: o repassar aprovado em sombra não renasceu uma vez';
  end if;
  if exists (select 1 from public.retorno_saidas s where s.dedupe_key = 'parceiro:repassar:' || v_os_r5 || ':pronto') then
    raise exception '8c: o repassar de OS fora da regra de ouro renasceu';
  end if;
  -- o pronto vencido (mais de 48 h) também não renasce
  delete from public.retorno_saidas where dedupe_key = 'parceiro:repassar:' || v_os_r1 || ':pronto';
  perform public.parceiro_repassar_rodada(c_t + interval '50 hours');
  if exists (select 1 from public.retorno_saidas s where s.dedupe_key = 'parceiro:repassar:' || v_os_r1 || ':pronto') then
    raise exception '8d: o repassar com o pronto vencido renasceu';
  end if;
  update public.retorno_config set parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}' where id;

  -- ── A varredura: a tabela fechada a anon, as funções da P9 fechadas a anon e authenticated ──
  if has_table_privilege('anon', 'public.parceiro_envios_a_mao', 'select')
     or has_table_privilege('authenticated', 'public.parceiro_envios_a_mao', 'insert')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.parceiro_envios_a_mao'::regclass) then
    raise exception 'grants: parceiro_envios_a_mao aberta';
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
  if to_regprocedure('public.parceiro_detectar_pdf(timestamptz)') is null
     or to_regprocedure('public.parceiro_decidir_pdf_mao(uuid, text, uuid, timestamptz)') is null
     or to_regprocedure('public.parceiro_repassar_rodada(timestamptz)') is null then
    raise exception 'grants: a varredura não achou as funções da P9 (%)', v_n_fun;
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_mao', true, '{}');
end
$mao$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
