-- Retorno F2 (P9): o ditado amarrado ao caso. Relógio fixo em ter 10/11/2026 15:00. Roda só pela bancada.
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000092xx; a frase marcada é inventada.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

do $ditado$
declare
  c_agora constant timestamptz := '2026-11-10 15:00:00-03';
  v_dono uuid;
  v_cl uuid; v_ves uuid; v_os uuid;
  v_msg uuid;
  v_caso uuid;
  v_r jsonb;
  v_cartao uuid;
  v_ses uuid;
  v_item uuid;
begin
  begin
    select d.id into v_dono from public._comprovante_dono() d;
    update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
    update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}', cartao_ligado = true;

    -- Sem cartão: erro.
    v_r := public.retorno_ver_caso_para_modelo(1, v_dono, c_agora);
    if v_r ->> 'erro' is distinct from 'Não há cartão aberto.' then
      raise exception '1: sem cartão (%)', v_r;
    end if;

    insert into public.clients (type, name, whatsapp) values ('individual', 'Rodrigo Ditado Teste', '(47) 90000-9220') returning id into v_cl;
    insert into public.vessels (client_id, name, asset_type) values (v_cl, 'Motorhome Ditado', 'Motorhome') returning id into v_ves;
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
    values ('OS-09220', v_cl, v_ves, 'awaiting_parts', 'approved', 'repair', '2026-10-01 12:00-03', '2026-10-01 12:00-03', '2026-10-01 12:00-03', 100)
    returning id into v_os;
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_em)
    values (v_os, 'dono', 'compressor', 1, 0, true, 'falta', 'dono', '2026-10-22 10:00-03');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('inbound', '5547900009220', 'text', 'FRASE-MARCADA-F2 como tá o motorhome?', 'received', '{"data": {}}'::jsonb, c_agora - interval '1 hour', c_agora - interval '1 hour')
    returning id into v_msg;
    insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em, gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
    values (public._agenda_chave_telefone('5547900009220'), '5547900009220', '47', 'cliente', '{"papel": "cliente"}', v_cl, v_msg, v_msg,
            c_agora - interval '1 hour', c_agora - interval '1 hour', c_agora - interval '1 hour', c_agora - interval '1 hour', 'recibo', 'recibo_cliente', 'aberta', 'sombra')
    returning id into v_caso;
    insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
    values (v_msg, v_caso, public._agenda_chave_telefone('5547900009220'), c_agora - interval '1 hour', c_agora - interval '1 hour', 'x', true);

    v_r := public.retorno_cartao_abrir('puxar', c_agora);
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    select c.sessao_id into v_ses from public.retorno_cartoes c where c.id = v_cartao;
    update public.retorno_cartoes set enviado_em = c_agora where id = v_cartao;

    -- Outro autor não lê; n fora do cartão dá erro.
    if public.retorno_ver_caso_para_modelo(1, 'b1600000-0000-4000-8000-0000000009f5', c_agora) ->> 'erro' is null then
      raise exception '2a: outro autor leu';
    end if;
    if public.retorno_ver_caso_para_modelo(2, v_dono, c_agora) ->> 'erro' is null then
      raise exception '2b: n fora do cartão';
    end if;

    -- A leitura: recebidas, fatos sem previsão, e a amarração gravada.
    v_r := public.retorno_ver_caso_para_modelo(1, v_dono, c_agora);
    if v_r -> 'recebidas' -> 0 ->> 'texto' not like 'FRASE-MARCADA-F2%' or v_r ->> 'os' <> 'OS-09220' or not (v_r -> 'fatos' ->> 'aguarda_peca')::boolean then
      raise exception '3a: leitura (%)', v_r;
    end if;
    if v_r::text like '%previsao%' or v_r::text like '%compressor%' then
      raise exception '3b: previsão ou peça foram ao modelo (%)', v_r;
    end if;
    if (select s.client_id from public.ai_operator_sessions s where s.id = v_ses) is distinct from v_cl
       or (select s.service_order_id from public.ai_operator_sessions s where s.id = v_ses) is distinct from v_os
       or (select s.vessel_id from public.ai_operator_sessions s where s.id = v_ses) is distinct from v_ves
       or not coalesce((select (s.metadata ->> 'retorno_amarrada')::boolean from public.ai_operator_sessions s where s.id = v_ses), false) then
      raise exception '3c: amarração';
    end if;
    -- A resposta ao modelo não vai a ai_operator_messages por aqui.
    if exists (select 1 from public.ai_operator_messages m where m.content like '%FRASE-MARCADA%') then
      raise exception '3d: texto do cliente na conversa';
    end if;

    -- O destino sai do caso.
    v_r := public.retorno_destino_do_item(1, v_dono, c_agora);
    if v_r ->> 'phone' <> '5547900009220' or (v_r ->> 'abertura_id')::uuid <> v_caso or not (v_r ->> 'ok')::boolean then
      raise exception '4a: destino (%)', v_r;
    end if;
    -- O dono respondeu pelo celular: o destino diz que não pode.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('outbound', '5547900009220', 'text', 'já te respondo por aqui', 'sent', '{"data": {}}'::jsonb, c_agora + interval '5 minutes', c_agora + interval '5 minutes');
    v_r := public.retorno_destino_do_item(1, v_dono, c_agora + interval '6 minutes');
    if (v_r ->> 'ok')::boolean then
      raise exception '4b: resposta pelo celular não barrou (%)', v_r;
    end if;

    -- Respondido: item feito, caso fechado.
    select i.id into v_item from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1;
    perform public.retorno_caso_respondido(v_item, 'Bom dia, a peça chega amanhã', 'wa-1', c_agora + interval '7 minutes');
    if (select i.estado || '/' || i.ditado_via from public.retorno_cartao_itens i where i.id = v_item) is distinct from 'feito/assistente'
       or (select a.estado || '/' || a.cumprida_por from public.retorno_aberturas a where a.id = v_caso) is distinct from 'fechada/cartao' then
      raise exception '5: respondido';
    end if;

    -- O vigia solta a amarração sem cartão vivo.
    update public.retorno_cartoes set estado = 'decidido' where id = v_cartao;
    perform public.retorno_vigia_cartao(c_agora + interval '8 minutes');
    if (select s.client_id from public.ai_operator_sessions s where s.id = v_ses) is not null
       or (select s.metadata ? 'retorno_amarrada' from public.ai_operator_sessions s where s.id = v_ses) then
      raise exception '6: o vigia não limpou';
    end if;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_ditado', true, '{}');
end
$ditado$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
