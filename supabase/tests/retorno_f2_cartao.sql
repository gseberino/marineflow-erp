-- Retorno F2 (P7B): o cartão. Relógio fixo em ter 10/11/2026 15:00. Roda só pela bancada.
-- Termina em ROLLBACK, e o bloco se desfaz sozinho: as pendências e perguntas reais só são afastadas dentro da transação.
-- Telefones de teste 55479000094xx; a frase marcada é inventada. Nada aqui lê mensagem da equipe.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f2c_caso(p_fone text, p_papel text, p_aberta timestamptz, p_client uuid default null,
                                            p_body text default 'FRASE-MARCADA-F2 como tá o motorhome?', p_clientes uuid[] default '{}')
returns uuid
language plpgsql as $f$
declare
  v_msg uuid;
  v_id uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', p_fone, 'text', p_body, 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, clientes, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
  values (public._agenda_chave_telefone(p_fone), p_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_client, p_clientes, v_msg, v_msg,
          p_aberta, p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'sombra')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
  values (v_msg, v_id, public._agenda_chave_telefone(p_fone), p_aberta, p_aberta, 'x', true);
  return v_id;
end $f$;

do $cartao$
declare
  c_agora constant timestamptz := '2026-11-10 15:00:00-03';   -- terça
  v_dono uuid;
  v_phone text;
  v_r jsonb; v_r2 jsonb;
  v_t text;
  v_cl uuid; v_cl2 uuid; v_cl3 uuid;
  v_os uuid;
  v_casos uuid[] := '{}';
  v_caso uuid;
  v_cartao uuid;
  v_pend uuid;
  v_pend2 uuid;
  v_ses uuid;
  v_item uuid;
  v_n integer;
  i integer;
begin
  begin
    select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
    update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
    update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
    update public.ai_operator_sessions set metadata = metadata - 'pendencias_guardadas' where external_thread_key = v_phone;
    update public.retorno_config set modo = 'sombra', tipos_ligados = '{}', cartao_ligado = true, cartao_max_itens = 3;

    -- 4. Antes: com o cartão desligado, lista, sem pendência e sem ponteiro.
    insert into public.clients (type, name, whatsapp) values ('individual', 'Rodrigo Cartao Teste', '(47) 90000-9401') returning id into v_cl;
    v_caso := pg_temp.f2c_caso('5547900009401', 'cliente', c_agora - interval '2 hours', v_cl);
    update public.retorno_config set cartao_ligado = false;
    v_r := public.retorno_cartao_abrir('puxar', c_agora);
    if v_r ->> 'acao' <> 'lista' or v_r ->> 'texto' not like '%*ver 1* · *resolvido 1* · *pessoal 1*' then
      raise exception '4a: desligado (%)', v_r;
    end if;
    if exists (select 1 from public.ai_operator_pending_actions p where p.action_name = 'retorno_executar_cartao') then
      raise exception '4b: pendência com o cartão desligado';
    end if;
    update public.retorno_config set cartao_ligado = true;

    -- 1. Um cartão por vez: 5 casos, 3 itens e "e mais 2".
    v_casos := array[v_caso];
    for i in 2 .. 5 loop
      insert into public.clients (type, name, whatsapp) values ('individual', 'Cliente' || i || ' Cartao Teste', '(47) 90000-940' || i) returning id into v_cl2;
      v_casos := v_casos || pg_temp.f2c_caso('554790000940' || i, 'cliente', c_agora - make_interval(hours => 2) + make_interval(mins => i), v_cl2);
    end loop;
    v_r := public.retorno_cartao_abrir('puxar', c_agora);
    if v_r ->> 'acao' <> 'cartao' then
      raise exception '1a: não abriu (%)', v_r;
    end if;
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    select c.pendencia_id, c.sessao_id into v_pend, v_ses from public.retorno_cartoes c where c.id = v_cartao;
    if (select count(*) from public.retorno_cartao_itens i where i.cartao_id = v_cartao) <> 3
       or (select c.estado from public.retorno_cartoes c where c.id = v_cartao) <> 'vivo'
       or v_r ->> 'texto' not like 'Retorno · 5 esperando%' or v_r ->> 'texto' not like '%e mais 2: *retorno*%' then
      raise exception '1b: cartão (%)', v_r ->> 'texto';
    end if;
    if (select s.metadata ->> 'pending_confirm_action_id' from public.ai_operator_sessions s where s.id = v_ses) is distinct from v_pend::text then
      raise exception '1c: ponteiro';
    end if;
    update public.retorno_cartao_itens set selecionado = false where cartao_id = v_cartao;
    v_r2 := public.retorno_cartao_abrir('puxar', c_agora + interval '1 minute');
    if v_r2 ->> 'acao' <> 'reapresenta' or (v_r2 ->> 'cartao_id')::uuid <> v_cartao then
      raise exception '1d: reapresenta (%)', v_r2;
    end if;
    if exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and not i.selecionado) then
      raise exception '1e: não restaurou a seleção';
    end if;
    if (select count(*) from public.ai_operator_pending_actions p where p.action_name = 'retorno_executar_cartao') <> 1 then
      raise exception '1f: pendência nova na reapresentação';
    end if;
    -- meio-dia com cartão vivo: a linha que sustenta a promessa, sem itens
    v_r2 := public.retorno_cartao_abrir('meio_dia', c_agora);
    if v_r2 ->> 'acao' <> 'lista' or v_r2 ->> 'texto' not like 'Retorno · meio-dia: 0 promessa(s) até as 14h.%' then
      raise exception '1g: meio-dia com cartão vivo (%)', v_r2;
    end if;
    if exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = (v_r2 ->> 'cartao_id')::uuid) then
      raise exception '1h: so_aviso com itens';
    end if;

    -- 6. Fora do histórico: pendência, conversa e auditoria sem o texto do cliente.
    select count(*) into v_n from public.ai_operator_pending_actions p
     where p.id = v_pend and (p.summary like '%FRASE-MARCADA%' or p.title like '%FRASE-MARCADA%' or p.payload::text like '%FRASE-MARCADA%');
    if v_n <> 0 then
      raise exception '6a: texto do cliente na pendência';
    end if;
    if (select p.summary from public.ai_operator_pending_actions p where p.id = v_pend) not like 'Cartão do retorno: 3 casos (%). Mande *retorno* para ver.' then
      raise exception '6b: summary';
    end if;
    select count(*) into v_n from public.ai_operator_messages m where m.content like '%FRASE-MARCADA%';
    if v_n <> 0 then
      raise exception '6c: texto do cliente na conversa (%)', v_n;
    end if;
    select count(*) into v_n from public.ai_operator_messages m where m.session_id = v_ses and m.content like 'Cartão do retorno aberto (pendência %';
    if v_n <> 1 then
      raise exception '6d: o par não foi gravado (%)', v_n;
    end if;
    select count(*) into v_n from public.ai_operator_audit a where a.pending_action_id = v_pend and a.event_type = 'retorno:cartao:proposto' and a.payload::text not like '%FRASE-MARCADA%';
    if v_n <> 1 then
      raise exception '6e: auditoria';
    end if;

    -- 10. Queda. Item 1 do cartão vivo.
    update public.retorno_cartoes set enviado_em = c_agora where id = v_cartao;
    select i.id into v_item from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1;
    v_caso := (select i.abertura_id from public.retorno_cartao_itens i where i.id = v_item);
    if (public._retorno_item_conferir(v_item, c_agora + interval '5 minutes', false) ->> 'ok')::boolean is distinct from true then
      raise exception '10a: item são caiu';
    end if;
    -- "ok, já vejo" ANTES do cartão não derruba
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at, sent_by)
    select 'outbound', a.phone_normalized, 'text', 'ok', 'sent', '{"data": {}}'::jsonb, c_agora - interval '5 minutes', c_agora - interval '5 minutes', null
      from public.retorno_aberturas a where a.id = v_caso;
    if (public._retorno_item_conferir(v_item, c_agora + interval '5 minutes', false) ->> 'ok')::boolean is distinct from true then
      raise exception '10b: eco de antes do cartão derrubou';
    end if;
    -- depois do cartão derruba, e o eco do futuro não
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at, sent_by)
    select 'outbound', a.phone_normalized, 'text', 'já resolvi', 'sent', '{"data": {}}'::jsonb, c_agora + interval '10 minutes', c_agora + interval '10 minutes', null
      from public.retorno_aberturas a where a.id = v_caso;
    if (public._retorno_item_conferir(v_item, c_agora + interval '5 minutes', false) ->> 'ok')::boolean is distinct from true then
      raise exception '10c: eco do futuro derrubou';
    end if;
    v_r := public._retorno_item_conferir(v_item, c_agora + interval '11 minutes', false);
    if v_r ->> 'motivo' is distinct from 'respondida_pelo_dono' or v_r ->> 'texto' is distinct from 'o 1 caiu: você já respondeu às 15:10; não mandei' then
      raise exception '10d: resposta depois (%)', v_r;
    end if;
    -- caso fechado
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id = v_caso;
    if public._retorno_item_conferir(v_item, c_agora + interval '11 minutes', false) ->> 'motivo' is distinct from 'caso_fechado' then
      raise exception '10e: caso fechado';
    end if;
    -- canal bloqueado: pessoal e nível nada
    select i.id into v_item from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 2;
    v_caso := (select i.abertura_id from public.retorno_cartao_itens i where i.id = v_item);
    insert into public.whatsapp_leads (phone_normalized, status, lead_tipo)
    select a.phone_normalized, 'discarded', 'pessoal' from public.retorno_aberturas a where a.id = v_caso;
    if public._retorno_item_conferir(v_item, c_agora + interval '11 minutes', false) ->> 'motivo' is distinct from 'canal_bloqueado' then
      raise exception '10f: canal';
    end if;
    -- número que deixou de ser do cliente
    select i.id into v_item from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 3;
    update public.clients c set whatsapp = '(47) 90000-9499'
      from public.retorno_cartao_itens i join public.retorno_aberturas a on a.id = i.abertura_id
     where i.id = v_item and c.id = a.client_id;
    if public._retorno_item_conferir(v_item, c_agora + interval '11 minutes', false) ->> 'motivo' is distinct from 'telefone_mudou' then
      raise exception '10g: telefone (%)', public._retorno_item_conferir(v_item, c_agora + interval '11 minutes', false);
    end if;

    -- 11. Envio que falha: cartão falhou, pendência rejeitada, ponteiro vazio, e abre de novo.
    v_r := public.retorno_cartao_enviado(v_cartao, false, null, c_agora + interval '12 minutes');
    if (select c.estado from public.retorno_cartoes c where c.id = v_cartao) <> 'falhou'
       or (select p.status from public.ai_operator_pending_actions p where p.id = v_pend) <> 'rejected'
       or (select s.metadata ->> 'pending_confirm_action_id' from public.ai_operator_sessions s where s.id = v_ses) is not null then
      raise exception '11a: falha de envio';
    end if;

    -- 3. Ocupado: pergunta aberta dá lista com C12, e o registro não é substituído.
    delete from public.retorno_cartao_itens i where i.cartao_id = v_cartao;
    insert into public.ai_operator_pending_actions (session_id, action_name, risk_level, title, summary, payload, status, expires_at)
    values (v_ses, 'outra_acao', 'high', 'Outra coisa', 'Outra coisa', '{}', 'pending', c_agora + interval '10 days')
    returning id into v_pend2;
    insert into public.whatsapp_perguntas (phone_normalized, origem, tipo, referencia_id, referencia_codigo, expira_em)
    values (v_phone, 'assistente', 'confirmacao', v_pend2, 'outra coisa', c_agora + interval '10 days');
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '13 minutes');
    if v_r ->> 'acao' <> 'lista' or v_r ->> 'texto' not like '%Tem um pedido aberto antes deste: responda a ele e mande *retorno* de novo.' then
      raise exception '3a: ocupado (%)', v_r;
    end if;
    if not exists (select 1 from public.whatsapp_perguntas w where w.phone_normalized = v_phone and w.status = 'aberta' and w.referencia_codigo = 'outra coisa') then
      raise exception '3b: substituiu a pergunta aberta';
    end if;
    update public.ai_operator_pending_actions set status = 'expired' where id = v_pend2;
    update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where phone_normalized = v_phone and status = 'aberta';

    -- 5. Modelo: o texto do cartão, literal, com hash não nulo.
    delete from public.retorno_aberturas where phone_normalized like '554790000940%';
    update public.retorno_modelo_tipos set nivel = 'cartao' where tipo = 'modelo_aguarda_peca';
    insert into public.clients (type, name, whatsapp) values ('individual', 'Rodrigo Modelo Teste', '(47) 90000-9411') returning id into v_cl;
    insert into public.vessels (client_id, name, asset_type) values (v_cl, 'Brisaleve', 'Motorhome') returning id into v_cl2;
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
    values ('OS-09411', v_cl, v_cl2, 'awaiting_parts', 'approved', 'repair', '2026-10-01 12:00-03', '2026-10-01 12:00-03', '2026-10-01 12:00-03', 100)
    returning id into v_os;
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_em)
    values (v_os, 'dono', 'o compressor', 1, 0, true, 'falta', 'dono', '2026-10-22 10:00-03');
    v_caso := pg_temp.f2c_caso('5547900009411', 'cliente', c_agora - interval '1 hour', v_cl, 'como tá o motorhome?');
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '14 minutes');
    v_t := (select c.dados -> 'linhas' ->> '1' from public.retorno_cartoes c where c.id = (v_r ->> 'cartao_id')::uuid);
    if v_r ->> 'texto' not like '%1. Rodrigo · OS-09411 · Brisaleve · 14:00 · sem promessa · ''como tá o motorhome?''%' then
      raise exception '5a: linha (%)', v_r ->> 'texto';
    end if;
    if v_r ->> 'texto' not like '%O que sei: aguardando o compressor (em falta, previsão padrão %, 7 dias úteis)%' then
      raise exception '5b: fato (%)', v_r ->> 'texto';
    end if;
    if v_r ->> 'texto' not like '%Modelo: ''Oi, Rodrigo (mensagem automática da HBR). O serviço % está aguardando a chegada de uma peça para seguirmos. O Gustavo te avisa quando ela chegar.''%' then
      raise exception '5c: modelo (%)', v_r ->> 'texto';
    end if;
    if v_r ->> 'texto' not like '%*1 B* = a peça chegou · *1 C* = dite a previsão%' then
      raise exception '5d: opções (%)', v_r ->> 'texto';
    end if;
    if v_r ->> 'texto' not like '%*sim <PIN>* faz o 1 · *só 1* · *ver 1* · *não* · ou dite por áudio%' then
      raise exception '5e: rodapé (%)', v_r ->> 'texto';
    end if;
    if (select i.hash from public.retorno_cartao_itens i where i.cartao_id = (v_r ->> 'cartao_id')::uuid) is null then
      raise exception '5f: hash nulo';
    end if;
    -- O hash remontado é o mesmo enquanto o fato não muda; mudou, o item cai só com p_executar.
    select i.id into v_item from public.retorno_cartao_itens i where i.cartao_id = (v_r ->> 'cartao_id')::uuid;
    if (public._retorno_item_conferir(v_item, c_agora + interval '15 minutes', true) ->> 'ok')::boolean is distinct from true then
      raise exception '10h: hash igual caiu (%)', public._retorno_item_conferir(v_item, c_agora + interval '15 minutes', true);
    end if;
    delete from public.os_material where service_order_id = v_os;
    if public._retorno_item_conferir(v_item, c_agora + interval '15 minutes', true) ->> 'motivo' is distinct from 'fato_mudou' then
      raise exception '10i: fato mudou';
    end if;
    if (public._retorno_item_conferir(v_item, c_agora + interval '15 minutes', false) ->> 'ok')::boolean is distinct from true then
      raise exception '10j: a regra 3 rodou no vigia';
    end if;
    update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';

    -- 7. Sessão: de 3 h usa a mesma; de 5 h cria outra, levando pendencias_guardadas.
    update public.ai_operator_sessions set status = 'closed' where external_thread_key = v_phone;
    insert into public.ai_operator_sessions (channel, status, external_thread_key, last_activity_at, metadata)
    values ('whatsapp', 'open', v_phone, c_agora - interval '3 hours', '{"pendencias_guardadas": ["x"], "antiga": 1}')
    returning id into v_ses;
    if public._retorno_sessao_do_dono(v_dono, v_phone, c_agora) <> v_ses then
      raise exception '7a: sessão de 3 h';
    end if;
    update public.ai_operator_sessions set last_activity_at = c_agora - interval '5 hours' where id = v_ses;
    v_cl3 := public._retorno_sessao_do_dono(v_dono, v_phone, c_agora);
    if v_cl3 = v_ses or (select s.metadata -> 'pendencias_guardadas' from public.ai_operator_sessions s where s.id = v_cl3) is distinct from '["x"]'::jsonb then
      raise exception '7b: sessão nova';
    end if;

    -- 9. Ambíguo: sem OS, sem fato, sem modelo; as letras dão os nomes curtos.
    insert into public.clients (type, name) values ('individual', 'Ana Dupla Teste') returning id into v_cl2;
    insert into public.clients (type, name) values ('individual', 'Bruno Dupla Teste') returning id into v_cl3;
    v_caso := pg_temp.f2c_caso('5547900009412', 'cliente_ambiguo', c_agora - interval '1 hour', null, 'como tá o motorhome?', array[v_cl2, v_cl3]);
    v_r := public._retorno_item_montar(v_caso, 2::smallint, c_agora);
    if v_r ->> 'tipo_item' <> 'ambiguo' or v_r ->> 'modelo_tipo' is not null or v_r ->> 'service_order_id' is not null
       or (v_r -> 'opcoes' -> 0 ->> 'rotulo') is distinct from 'Ana' or (v_r -> 'opcoes' -> 1 ->> 'letra') is distinct from 'B' then
      raise exception '9: ambíguo (%)', v_r;
    end if;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_cartao', true, '{}');
end
$cartao$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
