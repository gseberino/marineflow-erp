-- Retorno F2 (P8): decidir e executar o cartão. Relógio fixo em ter 10/11/2026 15:00. Roda só pela bancada.
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000095xx; a frase marcada é inventada.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f2d_caso(p_fone text, p_papel text, p_aberta timestamptz, p_client uuid default null,
                                            p_body text default 'como tá o motorhome?')
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
  values (public._agenda_chave_telefone(p_fone), p_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_client, v_msg, v_msg,
          p_aberta, p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'sombra')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
  values (v_msg, v_id, public._agenda_chave_telefone(p_fone), p_aberta, p_aberta, 'x', true);
  return v_id;
end $f$;

-- Cliente, barco, OS e peça em falta; o id do cliente. p_numero também nomeia a OS.
create or replace function pg_temp.f2d_cliente_os(p_nome text, p_whats text, p_numero text, p_material boolean default true)
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
  if p_material then
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_em)
    values (v_os, 'dono', 'compressor', 1, 0, true, 'falta', 'dono', '2026-10-22 10:00-03');
  end if;
  return v_cl;
end $f$;

-- Sem a confirmação de verdade, a pendência do cartão anterior ficaria viva e o telefone, ocupado.
create or replace function pg_temp.f2d_limpar()
returns void
language sql as $f$
  update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
$f$;

do $decidir$
declare
  c_agora constant timestamptz := '2026-11-10 15:00:00-03';   -- terça
  v_dono uuid;
  v_phone text;
  v_r jsonb;
  v_cl1 uuid; v_cl2 uuid; v_cl3 uuid;
  v_c1 uuid; v_c2 uuid; v_c3 uuid;
  v_cartao uuid;
  v_pend uuid;
  v_ses uuid;
  v_t text;
  v_item uuid;
  v_os uuid;
  v_saida uuid;
  v_n integer;
begin
  begin
    select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
    update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
    update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
    update public.retorno_config set modo = 'ligado', tipos_ligados = '{}', cartao_ligado = true, cartao_max_itens = 3;
    update public.retorno_modelo_tipos set nivel = 'cartao';

    v_cl1 := pg_temp.f2d_cliente_os('Rodrigo Decide Teste', '(47) 90000-9501', 'OS-09501');
    v_cl2 := pg_temp.f2d_cliente_os('Paulo Decide Teste', '(47) 90000-9502', 'OS-09502');
    v_cl3 := pg_temp.f2d_cliente_os('Marta Decide Teste', '(47) 90000-9503', 'OS-09503', false);
    v_c1 := pg_temp.f2d_caso('5547900009501', 'cliente', c_agora - interval '3 hours', v_cl1);
    v_c2 := pg_temp.f2d_caso('5547900009502', 'cliente', c_agora - interval '2 hours', v_cl2);
    v_c3 := pg_temp.f2d_caso('5547900009503', 'cliente', c_agora - interval '1 hour', v_cl3, 'FRASE-MARCADA-F2 posso buscar o motorhome?');

    v_r := public.retorno_cartao_abrir('puxar', c_agora);
    if v_r ->> 'acao' <> 'cartao' then
      raise exception '0: não abriu (%)', v_r;
    end if;
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    select c.pendencia_id, c.sessao_id into v_pend, v_ses from public.retorno_cartoes c where c.id = v_cartao;
    update public.retorno_cartoes set enviado_em = c_agora where id = v_cartao;

    -- Autor errado.
    v_r := public.retorno_decidir_dito('{"comando": "so", "ns": [1]}', 'b1600000-0000-4000-8000-0000000009f3', c_agora);
    if v_r is distinct from '{"ok": false, "motivo": "nao_e_o_dono"}'::jsonb then
      raise exception '1a: outro autor (%)', v_r;
    end if;
    -- n fora do cartão
    v_r := public.retorno_decidir_dito('{"comando": "ditar", "n": 3, "texto": "x"}', v_dono, c_agora);
    if v_r ->> 'texto' is not null and (select count(*) from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 3) = 0 then
      raise exception '1b: n fora do cartão (%)', v_r;
    end if;
    update public.retorno_cartao_itens set texto_ditado = null, ditado_via = null where cartao_id = v_cartao;
    v_r := public.retorno_decidir_dito('{"comando": "so", "ns": [1, 2]}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Fica 1 e 2. *sim <PIN>* manda. *retorno* volta ao cartão inteiro.' or not (v_r ->> 'precisa_pin')::boolean then
      raise exception '1c: só (%)', v_r;
    end if;

    -- 4. só 3: nenhum item muda de estado até o sim; retorno restaura.
    v_r := public.retorno_decidir_dito('{"comando": "so", "ns": [1]}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Fica só o 1. *sim <PIN>* manda. *retorno* volta ao cartão inteiro.' then
      raise exception '4a: só 1 (%)', v_r;
    end if;
    if exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado <> 'vivo') then
      raise exception '4b: só mudou o estado';
    end if;
    perform public.retorno_cartao_abrir('puxar', c_agora);
    if exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and not i.selecionado) then
      raise exception '4c: retorno não restaurou';
    end if;
    v_r := public.retorno_decidir_dito('{"comando": "sem", "ns": [2]}', v_dono, c_agora);
    if v_r ->> 'texto' not like 'Fica %' or (select i.selecionado from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 2) then
      raise exception '4d: sem (%)', v_r;
    end if;
    perform public.retorno_cartao_abrir('puxar', c_agora);

    -- *1 C* sem data pede a data; letra que o item não tem.
    v_r := public.retorno_decidir_dito('{"comando": "escolher", "n": 1, "letra": "C", "resto": null}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Diga a previsão: *1 C dia 14*.' then
      raise exception '1d: previsão sem data (%)', v_r;
    end if;
    v_r := public.retorno_decidir_dito('{"comando": "escolher", "n": 1, "letra": "Z", "resto": null}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'O caso 1 não tem a opção Z, e nada foi feito.' then
      raise exception '1e: letra (%)', v_r;
    end if;

    -- 5. Ditado substitui modelo.
    v_r := public.retorno_decidir_dito('{"comando": "ditar", "n": 2, "texto": "Pode buscar amanhã, são R$ 300"}', v_dono, c_agora);
    if v_r ->> 'texto' not like 'Vou mandar a Paulo, exatamente: ''Pode buscar amanhã, são R$ 300''. (tem valor no texto)%' then
      raise exception '5a: dita (%)', v_r;
    end if;
    if (v_r -> 'historico')::text like '%Pode buscar%' then
      raise exception '5b: o ditado foi ao historico';
    end if;
    v_r := public.retorno_decidir_dito('{"comando": "ditar", "n": 2, "texto": ""}', v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Diga o texto: *dita 2 pode buscar amanhã*.' then
      raise exception '5c: dita vazio (%)', v_r;
    end if;

    -- Retirada: letra responde com o modelo, e o item 3 tem A e B.
    v_r := public.retorno_decidir_dito('{"comando": "escolher", "n": 3, "letra": "A", "resto": null}', v_dono, c_agora);
    if v_r ->> 'texto' not like 'Vou mandar a Marta: %liberado para retirada%*sim <PIN>* manda.' then
      raise exception '6a: retirada (%)', v_r;
    end if;
    if (select i.modelo_tipo from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 3) is distinct from 'modelo_liberado' then
      raise exception '6b: tipo da retirada';
    end if;

    -- 4e. Executa: 1 modelo, 1 ditado, 1 retirada. Texto da saída igual ao mostrado, byte a byte.
    select i.texto_mostrado into v_t from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1;
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora + interval '1 minute');
    if not (v_r ->> 'ok')::boolean or (v_r ->> 'vai_sair')::integer <> 3 or jsonb_array_length(v_r -> 'ditados') <> 1 then
      raise exception '4e: executar (%)', v_r;
    end if;
    if v_r ->> 'aviso' is distinct from 'Vai sair 3: Rodrigo, Paulo, Marta.' then
      raise exception '4f: aviso (%)', v_r ->> 'aviso';
    end if;
    if v_r ->> 'aviso' like '%FRASE-MARCADA%' then
      raise exception '4g: texto do cliente no aviso';
    end if;
    if (v_r -> 'ditados' -> 0 ->> 'phone') is distinct from '5547900009502' then
      raise exception '4h: telefone do ditado';
    end if;
    if (select s.dados ->> 'texto_aprovado' from public.retorno_saidas s where s.abertura_id = v_c1) is distinct from v_t then
      raise exception '4i: texto aprovado diferente do mostrado';
    end if;
    if exists (select 1 from public.retorno_saidas s where s.abertura_id = v_c2) then
      raise exception '4j: ditado criou saída de modelo';
    end if;
    if not (select (s.dados ->> 'marca_liberado')::boolean from public.retorno_saidas s where s.abertura_id = v_c3)
       or (select so.liberado_retirada_em from public.service_orders so where so.client_id = v_cl3) is distinct from c_agora + interval '1 minute' then
      raise exception '4k: a marca do libera não gravou';
    end if;
    if (select c.estado from public.retorno_cartoes c where c.id = v_cartao) <> 'decidido' then
      raise exception '4l: cartão não decidido';
    end if;
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora + interval '2 minutes');
    if v_r ->> 'aviso' is distinct from 'Esse cartão já foi decidido.' then
      raise exception '4m: 2ª execução (%)', v_r;
    end if;
    if (select count(*) from public.retorno_toques t where t.cartao_id = v_cartao and t.palavra = 'sim_pin') <> 1 then
      raise exception '4n: toque do sim';
    end if;
    -- A aprovação do tipo não conta aqui.
    if (select cardinality(t.aprovados_dias) from public.retorno_modelo_tipos t where t.tipo = 'modelo_aguarda_peca') <> 0 then
      raise exception '12: aprovação contou na execução';
    end if;

    -- 10. retorno_item_enviado: ok fecha o caso e cancela a agendada; falha mantém o relógio.
    select i.id into v_item from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 2;
    insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, modo, enviar_em, dedupe_key)
    values (v_c2, 'adiamento', public._agenda_chave_telefone('5547900009502'), '5547900009502', 'sombra', c_agora + interval '1 hour', 'teste-f2-decidir:1')
    returning id into v_saida;
    v_r := public.retorno_item_enviado(v_item, false, null, c_agora + interval '3 minutes');
    if (select i.estado from public.retorno_cartao_itens i where i.id = v_item) <> 'fora'
       or (select a.estado from public.retorno_aberturas a where a.id = v_c2) = 'fechada' then
      raise exception '10a: falha do ditado';
    end if;
    v_r := public.retorno_item_enviado(v_item, true, 'wa-1', c_agora + interval '4 minutes');
    if (select a.estado || '/' || a.fechada_motivo || '/' || a.cumprida_por from public.retorno_aberturas a where a.id = v_c2) is distinct from 'fechada/conteudo/cartao' then
      raise exception '10b: ok do ditado';
    end if;
    if (select s.estado || '/' || s.motivo from public.retorno_saidas s where s.id = v_saida) is distinct from 'cancelada/caso_fechado' then
      raise exception '10c: a agendada não caiu';
    end if;

    -- 6. dedupe: outro cartão do mesmo caso com a 1ª saída agendada não cria outra; com ela recusada, cria.
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id in (v_c2, v_c3);
    update public.retorno_saidas set dados = dados where abertura_id = v_c1;
    delete from public.retorno_cartao_itens where cartao_id = v_cartao;
    perform pg_temp.f2d_limpar();
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '5 minutes');
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    update public.retorno_cartoes set enviado_em = c_agora + interval '5 minutes' where id = v_cartao;
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora + interval '6 minutes');
    if (v_r ->> 'vai_sair')::integer <> 0 or v_r ->> 'aviso' not like '%o 1 já está saindo%' then
      raise exception '6c: dedupe com a 1ª agendada (%)', v_r;
    end if;
    update public.retorno_saidas set estado = 'recusada', motivo = 'validador', decidida_em = c_agora where abertura_id = v_c1;
    delete from public.retorno_cartao_itens where cartao_id = v_cartao;
    perform pg_temp.f2d_limpar();
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '7 minutes');
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    update public.retorno_cartoes set enviado_em = c_agora + interval '7 minutes' where id = v_cartao;
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora + interval '8 minutes');
    if (v_r ->> 'vai_sair')::integer <> 1 or (select count(*) from public.retorno_saidas s where s.abertura_id = v_c1) <> 2 then
      raise exception '6d: dedupe com a 1ª recusada (%)', v_r;
    end if;
    update public.retorno_saidas set estado = 'recusada', motivo = 'validador', decidida_em = c_agora where abertura_id = v_c1 and estado = 'agendada';

    -- Com o retorno em sombra, o sim não cria nada.
    update public.retorno_config set modo = 'sombra';
    delete from public.retorno_cartao_itens where cartao_id = v_cartao;
    perform pg_temp.f2d_limpar();
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '9 minutes');
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    update public.retorno_cartoes set enviado_em = c_agora + interval '9 minutes' where id = v_cartao;
    v_n := (select count(*) from public.retorno_saidas s where s.abertura_id = v_c1);
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora + interval '10 minutes');
    if (v_r ->> 'vai_sair')::integer <> 0 or v_r ->> 'aviso' not like '%O retorno está em teste: não mandei.%'
       or (select count(*) from public.retorno_saidas s where s.abertura_id = v_c1) <> v_n then
      raise exception '13: sombra (%)', v_r;
    end if;
    update public.retorno_config set modo = 'ligado';

    -- 2. Trava por hash: o fato muda entre o cartão e o sim.
    update public.retorno_saidas set estado = 'recusada', motivo = 'validador', decidida_em = c_agora - interval '2 days', enviar_em = c_agora - interval '2 days' where abertura_id = v_c1;
    delete from public.retorno_cartao_itens where cartao_id = v_cartao;
    perform pg_temp.f2d_limpar();
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '11 minutes');
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    update public.retorno_cartoes set enviado_em = c_agora + interval '11 minutes' where id = v_cartao;
    select so.id into v_os from public.service_orders so where so.client_id = v_cl1;
    delete from public.os_material where service_order_id = v_os;
    v_n := (select count(*) from public.retorno_saidas s where s.abertura_id = v_c1);
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora + interval '12 minutes');
    if v_r ->> 'aviso' not like '%o 1 mudou desde o cartão%' or (select count(*) from public.retorno_saidas s where s.abertura_id = v_c1) <> v_n then
      raise exception '2: hash (%)', v_r;
    end if;
    if (select i.estado || '/' || i.caiu_motivo from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1) is distinct from 'caiu/fato_mudou' then
      raise exception '2b: estado do item';
    end if;

    -- 7. *1 B*: sem rascunho, grava na_mao; com rascunho aberto, recusa.
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_em)
    values (v_os, 'dono', 'compressor', 1, 0, true, 'falta', 'dono', '2026-10-22 10:00-03');
    delete from public.retorno_cartao_itens where cartao_id = v_cartao;
    perform pg_temp.f2d_limpar();
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '13 minutes');
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    update public.retorno_cartoes set enviado_em = c_agora + interval '13 minutes' where id = v_cartao;
    -- com rascunho aberto do dono, recusa e não grava
    perform public.agenda_rascunho_material(v_dono, 'whatsapp', 'OS-09502', array['tudo'], 'na_mao', null, null, null, false, 'teste do rascunho', date '2026-11-10');
    if exists (select 1 from public.agenda_rascunho r where r.autor = v_dono and r.estado = 'aberto' and r.expira_em > c_agora) then
      v_r := public.retorno_decidir_dito('{"comando": "escolher", "n": 1, "letra": "B", "resto": null}', v_dono, c_agora + interval '14 minutes');
      if v_r ->> 'texto' is distinct from 'Tem um rascunho aberto: mande *grava* ou *descarta* antes.' then
        raise exception '7a: rascunho aberto (%)', v_r;
      end if;
      if (select m.situacao from public.os_material m where m.service_order_id = v_os) <> 'falta' then
        raise exception '7b: gravou com rascunho aberto';
      end if;
      update public.agenda_rascunho r set estado = 'descartado' where r.autor = v_dono and r.estado = 'aberto';
    end if;
    v_r := public.retorno_decidir_dito('{"comando": "escolher", "n": 1, "letra": "B", "resto": null}', v_dono, c_agora + interval '14 minutes');
    if v_r ->> 'texto' not like 'Anotei: chegou hoje.%' then
      raise exception '7c: letra B (%)', v_r;
    end if;
    if not exists (select 1 from public.os_material m where m.service_order_id = v_os and m.situacao = 'na_mao' and m.fonte = 'dono' and m.chegou_em is not null) then
      raise exception '7d: a peça não ficou na mão';
    end if;

    -- 11. Canal bloqueado: *dita* de quem pediu para parar cai no sim, sem envio.
    update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
    perform pg_temp.f2d_limpar();
    update public.retorno_cartoes set estado = 'decidido' where estado = 'vivo';
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id = v_c1;
    v_c2 := pg_temp.f2d_caso('5547900009504', 'cliente', c_agora + interval '14 minutes', v_cl2, 'preciso falar sobre a lancha');
    update public.clients set whatsapp = '(47) 90000-9504' where id = v_cl2;
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '15 minutes');
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    update public.retorno_cartoes set enviado_em = c_agora + interval '15 minutes' where id = v_cartao;
    perform public.retorno_decidir_dito('{"comando": "ditar", "n": 1, "texto": "Pode buscar amanhã"}', v_dono, c_agora + interval '16 minutes');
    insert into public.whatsapp_blocked_numbers (phone_normalized, tipo) values ('5547900009504', 'opt_out');
    v_r := public.retorno_cartao_executar(v_cartao, v_dono, c_agora + interval '17 minutes');
    if jsonb_array_length(v_r -> 'ditados') <> 0 or v_r ->> 'aviso' not like '%o 1 pediu para não receber mensagem automática%' then
      raise exception '11: canal bloqueado (%)', v_r;
    end if;
    perform pg_temp.f2d_limpar();

    update public.retorno_cartoes set estado = 'decidido' where estado = 'vivo';
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id = v_c2;
    -- 8. Ambíguo: *1 A* põe o cliente só neste caso, sem vincular o lead.
    insert into public.clients (type, name) values ('individual', 'Ana Dupla Decide') returning id into v_cl1;
    insert into public.clients (type, name) values ('individual', 'Bruno Dupla Decide') returning id into v_cl3;
    v_c3 := pg_temp.f2d_caso('5547900009505', 'cliente_ambiguo', c_agora + interval '17 minutes', null, 'preciso falar com alguém');
    update public.retorno_aberturas set clientes = array[v_cl1, v_cl3] where id = v_c3;
    insert into public.whatsapp_leads (phone_normalized, status) values ('5547900009505', 'pending');
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '18 minutes');
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    if v_r ->> 'texto' not like '%*1 A* = Ana · *1 B* = Bruno%' then
      raise exception '8a: opções do ambíguo (%)', v_r ->> 'texto';
    end if;
    v_r := public.retorno_decidir_dito('{"comando": "escolher", "n": 1, "letra": "A", "resto": null}', v_dono, c_agora + interval '19 minutes');
    if (select a.client_id from public.retorno_aberturas a where a.id = v_c3) is distinct from v_cl1
       or (select a.papel from public.retorno_aberturas a where a.id = v_c3) <> 'cliente' then
      raise exception '8b: não pôs o cliente (%)', v_r;
    end if;
    if (select l.linked_client_id from public.whatsapp_leads l where l.phone_normalized = '5547900009505') is not null then
      raise exception '8c: vinculou o lead';
    end if;
    perform pg_temp.f2d_limpar();
    update public.retorno_cartoes set estado = 'decidido' where estado = 'vivo';
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id in (v_c2, v_c3);

    -- 9. *1 D* desfaz só o cadastro provisório deste caso.
    v_c3 := pg_temp.f2d_caso('5547900009506', 'numero_novo', c_agora + interval '19 minutes');
    insert into public.clients (type, name, provisorio, origem) values ('individual', 'Provisorio Um', true, 'retorno') returning id into v_cl1;
    insert into public.clients (type, name, provisorio, origem) values ('individual', 'Provisorio Dois', true, 'retorno') returning id into v_cl3;
    insert into public.audit_log (table_name, record_id, action, changed_by, new_value, reason)
    values ('clients', v_cl1, 'lead_converted', 'retorno', jsonb_build_object('provisorio', true, 'caso', v_c3), 'Cadastro provisório de teste');
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '20 minutes');
    if v_r ->> 'texto' not like '%*1 D* = desfaz o cadastro%' then
      raise exception '9a: opção D (%)', v_r ->> 'texto';
    end if;
    v_r := public.retorno_decidir_dito('{"comando": "escolher", "n": 1, "letra": "D", "resto": null}', v_dono, c_agora + interval '21 minutes');
    if v_r ->> 'texto' is distinct from 'Cadastro provisório desfeito. Nada foi apagado.'
       or (select c.active from public.clients c where c.id = v_cl1) or not (select c.active from public.clients c where c.id = v_cl3) then
      raise exception '9b: desfaz (%)', v_r;
    end if;

    -- 8. anon não chama.
    begin
      set local role anon;
      perform public.retorno_decidir_dito('{"comando": "so", "ns": [1]}', v_dono, c_agora);
      reset role;
      raise exception '14: anon chamou';
    exception when insufficient_privilege then
      reset role;
    end;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_decidir', true, '{}');
end
$decidir$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
