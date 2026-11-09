-- Retorno F2 (P10): as saídas dos modelos. Relógio fixo em ter 10/11/2026 15:00. Roda só pela bancada.
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000098xx; frases inventadas.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f2s_caso(p_fone text, p_aberta timestamptz, p_client uuid, p_body text default 'como tá o motorhome?')
returns uuid
language plpgsql as $f$
declare
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', p_fone, 'text', p_body, 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
  values (public._agenda_chave_telefone(p_fone), p_fone, '47', 'cliente', '{"papel": "cliente"}', p_client, v_msg, v_msg,
          p_aberta, p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'ligado')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
  values (v_msg, v_id, public._agenda_chave_telefone(p_fone), p_aberta, p_aberta, 'x', true);
  return v_id;
end $f$;

-- O recibo do caso, agendado.
create or replace function pg_temp.f2s_recibo(p_caso uuid, p_enviar timestamptz)
returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, enviar_em, dedupe_key)
  select a.id, 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', p_enviar, 'retorno:' || a.id || ':recibo'
    from public.retorno_aberturas a where a.id = p_caso
  returning id
$f$;

create or replace function pg_temp.f2s_cliente_os(p_nome text, p_whats text, p_numero text)
returns uuid
language plpgsql as $f$
declare
  v_cl uuid;
  v_b uuid;
  v_os uuid;
begin
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_whats) returning id into v_cl;
  insert into public.vessels (client_id, name, asset_type) values (v_cl, 'Motorhome ' || p_numero, 'Motorhome') returning id into v_b;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
  values (p_numero, v_cl, v_b, 'awaiting_parts', 'approved', 'repair', '2026-10-01 12:00-03', '2026-10-01 12:00-03', '2026-10-01 12:00-03', 100)
  returning id into v_os;
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_em)
  values (v_os, 'dono', 'compressor', 1, 0, true, 'falta', 'dono', '2026-10-22 10:00-03');
  return v_cl;
end $f$;

-- Libera o espaçamento entre saídas e fecha as saídas abertas, para o próximo pegar pegar só a do teste.
create or replace function pg_temp.f2s_livre()
returns void
language sql as $f$
  update public.retorno_config set proximo_envio_em = null;
  update public.retorno_saidas set estado = 'cancelada', motivo = 'substituida', decidida_em = '2026-11-01 12:00-03' where estado in ('preparada', 'enviando');
$f$;

do $saidas$
declare
  c_agora constant timestamptz := '2026-11-10 15:00:00-03';   -- terça
  c_grupo constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'adiamento', 'fim_do_dia'];
  v_dono uuid;
  v_cl uuid;
  v_caso uuid;
  v_rec uuid;
  v_r jsonb;
  v_s public.retorno_saidas;
  v_mod uuid;
  v_ab public.retorno_aberturas;
begin
  begin
    select d.id into v_dono from public._comprovante_dono() d;
    update public.retorno_config
       set modo = 'ligado', tipos_ligados = c_grupo, cartao_ligado = true, variantes_ligadas = false, segura_tudo_ate = null, segura_recibos = false,
           proximo_envio_em = null, respostas_dia_max = 200;
    update public.retorno_modelo_tipos set nivel = 'sozinho' where tipo = 'modelo_aguarda_peca';

    -- 1. Sozinho: "como tá?" + fato: a saída do modelo nasce e o recibo é adiado, sem cancelar.
    v_cl := pg_temp.f2s_cliente_os('Rodrigo Saida Teste', '(47) 90000-9801', 'OS-09801');
    v_caso := pg_temp.f2s_caso('5547900009801', c_agora - interval '10 minutes', v_cl);
    v_rec := pg_temp.f2s_recibo(v_caso, c_agora - interval '1 minute');
    v_r := public._retorno_checar_antes(v_rec, c_agora);
    if v_r ->> 'acao' <> 'adiar' or v_r ->> 'motivo' <> 'aguarda_modelo' then
      raise exception '1a: reserva (%)', v_r;
    end if;
    select * into v_s from public.retorno_saidas s where s.abertura_id = v_caso and s.tipo = 'modelo_aguarda_peca';
    if not found or v_s.origem <> 'retorno_modelo' or v_s.classe <> 'resposta_imediata' or not (v_s.dados ->> 'sozinho')::boolean then
      raise exception '1b: a saída do modelo não nasceu';
    end if;
    update public.retorno_saidas set enviar_em = c_agora + interval '10 minutes' where id = v_rec;
    v_r := public.retorno_pegar(c_agora);
    if v_r ->> 'saida_id' is distinct from v_s.id::text or v_r ->> 'origem' <> 'retorno_modelo' then
      raise exception '1c: pegar (%)', v_r;
    end if;
    if v_r ->> 'texto' not like 'Oi, Rodrigo!%O serviço % está aguardando a chegada de uma peça. Assim que ela chegar, o Gustavo avisa você.' then
      raise exception '1d: texto (%)', v_r ->> 'texto';
    end if;
    if v_r -> 'validador' -> 'trechos_do_modelo' is null or v_r -> 'validador' ->> 'nome_permitido' <> 'Rodrigo' then
      raise exception '1e: contexto (%)', v_r -> 'validador';
    end if;
    -- ao ficar enviada: caso fechado, recibo cancelado, letra gravada
    perform public.retorno_registrar_decisao(v_s.id, 'enviada', '{"provider_message_id": "wa-1"}', c_agora + interval '1 minute');
    select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
    if v_ab.estado <> 'fechada' or v_ab.fechada_motivo <> 'conteudo' or v_ab.cumprida_por <> 'modelo' then
      raise exception '1f: caso (%, %, %)', v_ab.estado, v_ab.fechada_motivo, v_ab.cumprida_por;
    end if;
    if (select s.estado || '/' || s.motivo from public.retorno_saidas s where s.id = v_rec) is distinct from 'cancelada/caso_fechado' then
      raise exception '1g: o recibo de reserva não caiu';
    end if;
    if (select s.letra from public.retorno_saidas s where s.id = v_s.id) is distinct from 'Z'
       or (select s.letra_dia from public.retorno_saidas s where s.id = v_s.id) is distinct from date '2026-11-10' then
      raise exception '1h: letra';
    end if;
    if (select t.envios_sozinho from public.retorno_modelo_tipos t where t.tipo = 'modelo_aguarda_peca') <> 1 then
      raise exception '1i: envios_sozinho';
    end if;
    if not coalesce((select (s.dados ->> 'auditoria')::boolean from public.retorno_saidas s where s.id = v_s.id), false) then
      raise exception '1j: o 1º envio é amostra da auditoria';
    end if;

    -- 2. Reserva: modelo recusado, o recibo sai, e não nasce outro modelo.
    v_cl := pg_temp.f2s_cliente_os('Paulo Saida Teste', '(47) 90000-9802', 'OS-09802');
    v_caso := pg_temp.f2s_caso('5547900009802', c_agora - interval '10 minutes', v_cl);
    v_rec := pg_temp.f2s_recibo(v_caso, c_agora - interval '1 minute');
    perform public._retorno_checar_antes(v_rec, c_agora);
    update public.retorno_saidas set estado = 'recusada', motivo = 'validador', decidida_em = c_agora where abertura_id = v_caso and tipo = 'modelo_aguarda_peca';
    v_r := public._retorno_checar_antes(v_rec, c_agora + interval '1 minute');
    if v_r ->> 'acao' <> 'seguir' then
      raise exception '2a: o recibo não seguiu (%)', v_r;
    end if;
    if (select count(*) from public.retorno_saidas s where s.abertura_id = v_caso and s.tipo like 'modelo%') <> 1 then
      raise exception '2b: nasceu outro modelo';
    end if;
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id = v_caso;

    -- 3. Sem fato: recibo normal. 4. Promoção suspensa: recibo normal.
    v_cl := pg_temp.f2s_cliente_os('Marta Saida Teste', '(47) 90000-9803', 'OS-09803');
    delete from public.os_material m using public.service_orders so where so.id = m.service_order_id and so.client_id = v_cl;
    v_caso := pg_temp.f2s_caso('5547900009803', c_agora - interval '10 minutes', v_cl);
    v_rec := pg_temp.f2s_recibo(v_caso, c_agora - interval '1 minute');
    if public._retorno_checar_antes(v_rec, c_agora) ->> 'acao' <> 'seguir' then
      raise exception '3: sem fato';
    end if;
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id = v_caso;
    v_cl := pg_temp.f2s_cliente_os('Bruno Saida Teste', '(47) 90000-9804', 'OS-09804');
    v_caso := pg_temp.f2s_caso('5547900009804', c_agora - interval '10 minutes', v_cl);
    v_rec := pg_temp.f2s_recibo(v_caso, c_agora - interval '1 minute');
    update public.retorno_modelo_tipos set promocao_suspensa_ate = c_agora + interval '1 day' where tipo = 'modelo_aguarda_peca';
    if public._retorno_checar_antes(v_rec, c_agora) ->> 'acao' <> 'seguir' then
      raise exception '4: suspensa';
    end if;
    update public.retorno_modelo_tipos set promocao_suspensa_ate = null, nivel = 'cartao' where tipo = 'modelo_aguarda_peca';
    delete from public.retorno_saidas where id = v_rec;

    -- 5. Aprovada: não recompõe; opt-out não passa; envelhecida com o fato mudado cai.
    insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, dados, dedupe_key)
    select a.id, 'modelo_aguarda_peca', 'aprovado', 'retorno_modelo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'agendada', c_agora,
           jsonb_build_object('aprovada', true, 'aprovada_em', c_agora, 'texto_aprovado', 'Bruno, o texto que o dono aprovou com a peça aguardando.', 'hash', 'h'),
           'retorno:' || a.id || ':modelo:item'
      from public.retorno_aberturas a where a.id = v_caso
    returning id into v_mod;
    perform pg_temp.f2s_livre();
    v_r := public.retorno_pegar(c_agora);
    if v_r ->> 'saida_id' is distinct from v_mod::text or v_r ->> 'texto' is distinct from 'Bruno, o texto que o dono aprovou com a peça aguardando.' then
      raise exception '5a: aprovado recomposto (%)', v_r;
    end if;
    update public.retorno_saidas set estado = 'agendada', decidida_em = null, processando_ate = null, texto = null where id = v_mod;
    -- envelhecida com o fato mudado
    delete from public.os_material m using public.service_orders so where so.id = m.service_order_id and so.client_id = v_cl;
    v_r := public._retorno_checar_antes(v_mod, c_agora + interval '31 minutes');
    if v_r ->> 'motivo' is distinct from 'fato_mudou' then
      raise exception '5b: aprovada envelhecida (%)', v_r;
    end if;
    update public.retorno_saidas set dados = dados || jsonb_build_object('aprovada_em', c_agora + interval '20 minutes') where id = v_mod;
    v_r := public._retorno_checar_antes(v_mod, c_agora + interval '31 minutes');
    if v_r ->> 'motivo' = 'fato_mudou' then
      raise exception '5c: aprovada recente caiu (%)', v_r;
    end if;

    -- 6. Corrida: resposta do dono depois do sim cancela; o "ok" antes da aprovação não cancela.
    update public.retorno_saidas set dados = dados || jsonb_build_object('aprovada_em', c_agora) where id = v_mod;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('outbound', '5547900009804', 'text', 'ok', 'sent', '{"data": {}}'::jsonb, c_agora - interval '5 minutes', c_agora - interval '5 minutes');
    v_r := public._retorno_checar_antes(v_mod, c_agora + interval '1 minute');
    if v_r ->> 'motivo' = 'respondida_pelo_dono' then
      raise exception '6a: o ok de antes cancelou (%)', v_r;
    end if;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('outbound', '5547900009804', 'text', 'pode vir buscar', 'sent', '{"data": {}}'::jsonb, c_agora + interval '2 minutes', c_agora + interval '2 minutes');
    v_r := public._retorno_checar_antes(v_mod, c_agora + interval '3 minutes');
    if v_r ->> 'motivo' is distinct from 'respondida_pelo_dono' then
      raise exception '6b: a resposta depois não cancelou (%)', v_r;
    end if;
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id = v_caso;

    -- 9. Modo: modelo não promovido em sombra; segura tudo segura o aprovado e volta com *solta tudo*.
    v_cl := pg_temp.f2s_cliente_os('Ana Saida Teste', '(47) 90000-9805', 'OS-09805');
    v_caso := pg_temp.f2s_caso('5547900009805', c_agora - interval '10 minutes', v_cl);
    insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, dados, dedupe_key)
    select a.id, 'modelo_aguarda_peca', null, 'retorno_modelo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'agendada', c_agora, '{}',
           'retorno:' || a.id || ':modelo:semnada'
      from public.retorno_aberturas a where a.id = v_caso
    returning id into v_mod;
    v_r := public._retorno_modo_efetivo(v_mod, null, null, c_agora);
    if v_r ->> 'motivo' is distinct from 'modelo_nao_promovido' then
      raise exception '9a: não promovido (%)', v_r;
    end if;
    update public.retorno_saidas set dados = jsonb_build_object('aprovada', true, 'aprovada_em', c_agora, 'texto_aprovado', 'Ana, o texto que o dono aprovou com a peça aguardando.') where id = v_mod;
    if public._retorno_modo_efetivo(v_mod, 'aprovado', null, c_agora) ->> 'modo' is distinct from 'ligado' then
      raise exception '9b: aprovado não ligou';
    end if;
    update public.retorno_config set segura_tudo_ate = c_agora + interval '1 day';
    perform pg_temp.f2s_livre();
    perform public.retorno_pegar(c_agora);
    select * into v_s from public.retorno_saidas s where s.id = v_mod;
    if v_s.estado <> 'agendada' or v_s.enviar_em is distinct from c_agora + interval '1 day' or not (v_s.dados ->> 'segurada')::boolean then
      raise exception '9c: segura tudo (%, %, %)', v_s.estado, v_s.enviar_em, v_s.dados;
    end if;
    v_r := public.retorno_dito('{"comando": "solta", "alvo": "tudo"}', v_dono, c_agora + interval '1 hour');
    if v_r ->> 'texto' not like 'Soltei: o automático volta a sair. 1 que ficaram no meio%' then
      raise exception '9d: solta (%)', v_r;
    end if;
    update public.retorno_aberturas set ultima_em = c_agora - interval '13 hours' where id = v_caso;
    v_r := public._retorno_checar_antes(v_mod, c_agora + interval '1 hour');
    if v_r ->> 'motivo' is distinct from 'segura_tudo' then
      raise exception '9e: quem escreveu há 13 h (%)', v_r;
    end if;
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id = v_caso;

    -- 7. Variantes: desligadas, nada muda; ligadas, a do caso; promessa em outro dia fica com a da F1.
    v_cl := pg_temp.f2s_cliente_os('Clara Saida Teste', '(47) 90000-9806', 'OS-09806');
    v_caso := pg_temp.f2s_caso('5547900009806', c_agora - interval '10 minutes', v_cl, 'quando fica pronto?');
    insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, decidida_em, enviada_em, texto, dedupe_key)
    select a.id, 'saudacao_numero_novo', 'retorno_recibo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'enviada',
           c_agora - interval '2 days', c_agora - interval '2 days', c_agora - interval '2 days', 'Bom dia!', 'teste-f2-saidas:ouviu'
      from public.retorno_aberturas a where a.id = v_caso;
    v_rec := pg_temp.f2s_recibo(v_caso, c_agora);
    perform pg_temp.f2s_livre();
    update public.retorno_config set segura_tudo_ate = null, variantes_ligadas = false;
    v_r := public.retorno_pegar(c_agora);
    if v_r ->> 'saida_id' is distinct from v_rec::text or v_r ->> 'variante' is distinct from 'padrao' then
      raise exception '7a: variante desligada (%)', v_r;
    end if;
    update public.retorno_saidas set estado = 'agendada', decidida_em = null, processando_ate = null, texto = null, modo = 'ligado' where id = v_rec;
    update public.retorno_config set variantes_ligadas = true;
    perform pg_temp.f2s_livre();
    v_r := public.retorno_pegar(c_agora);
    if v_r ->> 'variante' is distinct from 'vou_confirmar'
       or v_r ->> 'texto' not like 'Oi, Clara! Vou confirmar com o Gustavo, e ele retorna para você %' then
      raise exception '7b: variante ligada (%)', v_r;
    end if;

    -- 8. Marcas: tem_proposta vem do banco.
    v_r := public._retorno_contexto_do_validador(v_rec, 'x', '{}', c_agora);
    if (v_r -> 'marcas' ->> 'tem_proposta')::boolean then
      raise exception '8a: tem_proposta sem orçamento';
    end if;
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, grand_total)
    select 'ORÇ-09806', so.client_id, so.vessel_id, 'draft', 'draft', 'repair', c_agora - interval '1 day', c_agora - interval '1 day', 100
      from public.service_orders so where so.client_id = v_cl limit 1;
    v_r := public._retorno_contexto_do_validador(v_rec, 'x', '{}', c_agora);
    if not (v_r -> 'marcas' ->> 'tem_proposta')::boolean then
      raise exception '8b: tem_proposta com orçamento';
    end if;

    -- 12. A aprovação do tipo conta na enviada, uma vez por dia.
    insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, decidida_em, texto, dados, dedupe_key)
    select a.id, 'modelo_pronto', 'aprovado', 'retorno_modelo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'enviando', c_agora, c_agora, 'Clara, o texto aprovado do modelo pronto.',
           jsonb_build_object('aprovada', true, 'aprovada_em', c_agora), 'teste-f2-saidas:aprovado'
      from public.retorno_aberturas a where a.id = v_caso
    returning id into v_mod;
    perform public.retorno_registrar_decisao(v_mod, 'enviada', '{"provider_message_id": "wa-2"}', c_agora + interval '1 minute');
    if (select t.aprovados_dias from public.retorno_modelo_tipos t where t.tipo = 'modelo_pronto') is distinct from array[date '2026-11-10']
       or (select t.aprovados_usos from public.retorno_modelo_tipos t where t.tipo = 'modelo_pronto') <> 1 then
      raise exception '12: aprovação';
    end if;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_saidas', true, '{}');
end
$saidas$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
