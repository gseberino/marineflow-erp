-- Retorno F3, rr-f3-2b (20/11/2026): o áudio já cria o orçamento, e o PIN serve só para mandar o PDF. Migration 20270214100100.
-- A impressão digital do ORÇ, a marca do áudio, o ORÇ do caso (áudio repetido não cria dois), a conferência do PIN e a linha do
-- rascunho no cartão com a impressão no hash. Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones 55479000099xx (chave
-- 000099xx, a regra dos dados de teste quando a chave sai do telefone); nomes inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f3a_igual(p_rot text, p_valor text, p_esp text) returns void
language plpgsql as $f$
begin
  if p_valor is distinct from p_esp then
    raise exception '%: %, esperava %', p_rot, coalesce(p_valor, '∅'), coalesce(p_esp, '∅');
  end if;
end $f$;

do $audio$
declare
  c_fone constant text := '5547900009931';
  v_chave text := public._agenda_chave_telefone(c_fone);
  v_dono uuid;
  v_cli uuid;
  v_un uuid;
  v_prod uuid;
  v_msg uuid;
  v_caso uuid;
  v_so uuid;
  v_pv uuid;
  v_r jsonb;
  v_imp text;
  v_imp2 text;
  v_marca text;
  v_h1 text;
  v_h2 text;
  v_item jsonb;
begin
  begin
    select d.id into v_dono from public._comprovante_dono() d;
    update public.retorno_config set previa_ditado_ligado = false, previa_modo = 'desligado' where id;

    insert into public.clients (type, name, whatsapp) values ('individual', 'Teodoro Audio Teste', c_fone) returning id into v_cli;
    insert into public.vessels (client_id, name, asset_type) values (v_cli, 'Brisa Audio', 'Lancha') returning id into v_un;
    insert into public.products (name, stock_quantity, sale_price, active) values ('Produto Audio Teste', 0, 10, true) returning id into v_prod;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('inbound', c_fone, 'text', 'preciso trocar as baterias da lancha, quanto custa?', 'received', '{"data": {}}'::jsonb, now() - interval '2 hours', now() - interval '2 hours')
    returning id into v_msg;
    insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, clientes, primeira_msg_id, ultima_msg_id, aberta_em,
                                          gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
    values (v_chave, c_fone, '47', 'cliente', '{"papel": "cliente"}', v_cli, '{}', v_msg, v_msg, now() - interval '2 hours',
            now() - interval '2 hours', now() - interval '2 hours', now() - interval '2 hours', 'recibo', 'recibo_cliente', 'aberta', 'sombra')
    returning id into v_caso;
    insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, sinais, pede_resposta)
    values (v_msg, v_caso, v_chave, now() - interval '2 hours', now() - interval '2 hours', md5('x'),
            public._retorno_sinais('preciso trocar as baterias da lancha, quanto custa?'), true);
    -- O ORÇ que o áudio criou (rascunho, com a origem do ditado) e a proposta que virou ORÇ.
    insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, problem_description,
                                       created_at, updated_at, grand_total, origem, origem_chave8)
    values ('TF3A-01', v_cli, v_un, 'draft', 'draft', 'repair', 'Baterias', now() - interval '1 hour', now() - interval '1 hour', 2000, 'retorno_ditado', v_chave)
    returning id into v_so;
    insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale)
    values (v_so, v_prod, 2, 1, 1000, 2, 2000);
    insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, familias, titulo, estado, modo, total, linhas_n, hash, service_order_id)
    values (v_caso, v_chave, v_cli, v_un, 'ditado', array['bateria'], 'Baterias', 'virou_orc', 'ligado', 2000, 1, 'hash-teste', v_so)
    returning id into v_pv;

    -- ═══ 1. A impressão: estável, muda com preço, quantidade e título, não muda com a validade (o envio a grava).
    v_imp := public._retorno_orc_impressao(v_so);
    perform pg_temp.f3a_igual('1a estável', public._retorno_orc_impressao(v_so), v_imp);
    update public.service_orders set quote_validity_days = 30 where id = v_so;
    perform pg_temp.f3a_igual('1b validade fora', public._retorno_orc_impressao(v_so), v_imp);
    update public.service_order_parts set unit_sale_snapshot = 1100 where service_order_id = v_so;
    if public._retorno_orc_impressao(v_so) = v_imp then raise exception '1c: o preço não mudou a impressão'; end if;
    update public.service_order_parts set unit_sale_snapshot = 1000 where service_order_id = v_so;
    perform pg_temp.f3a_igual('1d volta', public._retorno_orc_impressao(v_so), v_imp);
    update public.service_orders set problem_description = 'Outro título' where id = v_so;
    if public._retorno_orc_impressao(v_so) = v_imp then raise exception '1e: o título não mudou a impressão'; end if;
    update public.service_orders set problem_description = 'Baterias' where id = v_so;
    perform pg_temp.f3a_igual('1f nulo sem ORÇ', public._retorno_orc_impressao(gen_random_uuid()), null);
    v_r := public._retorno_orc_linhas(v_so);
    perform pg_temp.f3a_igual('1g linhas', jsonb_array_length(v_r)::text || ' ' || (v_r -> 0 ->> 'nome') || ' '
                              || ((v_r -> 0 ->> 'quantidade')::numeric = 2)::text || ' ' || ((v_r -> 0 ->> 'preco')::numeric = 1000)::text,
                              '1 Produto Audio Teste true true');

    -- ═══ 2. A marca: só o dono; a 1ª hora fica; devolve número, total e impressão.
    perform pg_temp.f3a_igual('2a outro autor', public.retorno_orc_do_audio_marcar(v_pv, v_so, gen_random_uuid()) ->> 'motivo', 'nao_e_o_dono');
    perform pg_temp.f3a_igual('2b ORÇ de outra proposta', public.retorno_orc_do_audio_marcar(v_pv, gen_random_uuid(), v_dono) ->> 'motivo', 'sem_proposta');
    v_r := public.retorno_orc_do_audio_marcar(v_pv, v_so, v_dono, now() - interval '50 minutes');
    perform pg_temp.f3a_igual('2c ok', v_r ->> 'ok', 'true');
    perform pg_temp.f3a_igual('2d número', v_r ->> 'numero', 'TF3A-01');
    perform pg_temp.f3a_igual('2e impressão', v_r ->> 'impressao', v_imp);
    v_marca := (select p.dados ->> 'orc_pelo_audio_em' from public.retorno_previa p where p.id = v_pv);
    if v_marca is null then raise exception '2f: sem a marca orc_pelo_audio_em'; end if;
    perform public.retorno_orc_do_audio_marcar(v_pv, v_so, v_dono, now());
    perform pg_temp.f3a_igual('2g a 1ª hora fica', (select p.dados ->> 'orc_pelo_audio_em' from public.retorno_previa p where p.id = v_pv), v_marca);

    -- ═══ 3. O ORÇ do caso: áudio repetido acha este; com PDF, enviado, juntado ou de outro autor, não.
    v_r := public.retorno_orc_do_audio_do_caso(v_caso, v_dono);
    perform pg_temp.f3a_igual('3a acha', v_r ->> 'service_order_id', v_so::text);
    perform pg_temp.f3a_igual('3b impressão', v_r ->> 'impressao', v_imp);
    perform pg_temp.f3a_igual('3c linhas', jsonb_array_length(v_r -> 'linhas')::text, '1');
    perform pg_temp.f3a_igual('3d outro autor', public.retorno_orc_do_audio_do_caso(v_caso, gen_random_uuid())::text, null);
    update public.service_orders set quote_status = 'sent' where id = v_so;
    perform pg_temp.f3a_igual('3e enviado', public.retorno_orc_do_audio_do_caso(v_caso, v_dono)::text, null);
    update public.service_orders set quote_status = 'draft' where id = v_so;
    update public.retorno_previa set pdf_em = now() where id = v_pv;
    perform pg_temp.f3a_igual('3f com PDF', public.retorno_orc_do_audio_do_caso(v_caso, v_dono)::text, null);
    update public.retorno_previa set pdf_em = null where id = v_pv;

    -- ═══ 4. A conferência do PIN: desligado, ok, mudou (preço, telefone, caso fechado), enviado.
    perform pg_temp.f3a_igual('4a desligado', public.retorno_orc_do_audio_conferir(v_caso, v_so, v_imp, c_fone, v_dono) ->> 'motivo', 'desligado');
    update public.retorno_config set previa_ditado_ligado = true where id;
    v_r := public.retorno_orc_do_audio_conferir(v_caso, v_so, v_imp, c_fone, v_dono);
    perform pg_temp.f3a_igual('4b ok', v_r ->> 'ok', 'true');
    perform pg_temp.f3a_igual('4c sem cartão, item nulo', v_r ->> 'item_id', null);
    perform pg_temp.f3a_igual('4d outro autor', public.retorno_orc_do_audio_conferir(v_caso, v_so, v_imp, c_fone, gen_random_uuid()) ->> 'motivo', 'mudou');
    perform pg_temp.f3a_igual('4e outro telefone', public.retorno_orc_do_audio_conferir(v_caso, v_so, v_imp, '5547900009932', v_dono) ->> 'motivo', 'mudou');
    update public.service_order_parts set quantity = 3 where service_order_id = v_so;
    perform pg_temp.f3a_igual('4f ORÇ mudou na tela', public.retorno_orc_do_audio_conferir(v_caso, v_so, v_imp, c_fone, v_dono) ->> 'motivo', 'mudou');
    update public.service_order_parts set quantity = 2 where service_order_id = v_so;
    perform pg_temp.f3a_igual('4g voltou', public.retorno_orc_do_audio_conferir(v_caso, v_so, v_imp, c_fone, v_dono) ->> 'ok', 'true');
    update public.retorno_previa set pdf_em = now() where id = v_pv;
    perform pg_temp.f3a_igual('4h PDF já saiu', public.retorno_orc_do_audio_conferir(v_caso, v_so, v_imp, c_fone, v_dono) ->> 'motivo', 'enviado');
    update public.retorno_previa set pdf_em = null where id = v_pv;
    update public.service_orders set quote_status = 'sent' where id = v_so;
    perform pg_temp.f3a_igual('4i enviado pela tela', public.retorno_orc_do_audio_conferir(v_caso, v_so, v_imp, c_fone, v_dono) ->> 'motivo', 'enviado');
    update public.service_orders set quote_status = 'draft' where id = v_so;
    update public.retorno_aberturas set estado = 'fechada', fechada_em = now(), fechada_motivo = 'conteudo' where id = v_caso;
    perform pg_temp.f3a_igual('4j caso fechado', public.retorno_orc_do_audio_conferir(v_caso, v_so, v_imp, c_fone, v_dono) ->> 'motivo', 'mudou');
    update public.retorno_aberturas set estado = 'aberta', fechada_em = null, fechada_motivo = null where id = v_caso;

    -- ═══ 5. O cartão: a linha do rascunho (acao_sim pdf) tem a impressão no hash; mudar o preço muda o hash.
    v_item := public._retorno_item_montar(v_caso, 1::smallint, now());
    perform pg_temp.f3a_igual('5a ramo do PDF', v_item ->> 'acao_sim', 'pdf');
    perform pg_temp.f3a_igual('5b o ORÇ do item', v_item ->> 'service_order_id', v_so::text);
    v_h1 := v_item ->> 'hash';
    perform pg_temp.f3a_igual('5c estável', public._retorno_item_montar(v_caso, 1::smallint, now()) ->> 'hash', v_h1);
    update public.service_order_parts set unit_sale_snapshot = 1000.5 where service_order_id = v_so;
    update public.service_orders set grand_total = 2000 where id = v_so;   -- o total igual: antes, só o total entrava no hash
    v_h2 := public._retorno_item_montar(v_caso, 1::smallint, now()) ->> 'hash';
    if v_h2 = v_h1 then raise exception '5d: o preço mudou com o mesmo total e o hash do item não mudou'; end if;

    -- ═══ 6. Fechado ao anônimo e ao painel; o service_role chama as três de chamar.
    if has_function_privilege('anon', 'public.retorno_orc_do_audio_conferir(uuid, uuid, text, text, uuid, timestamptz)', 'execute')
       or has_function_privilege('authenticated', 'public.retorno_orc_do_audio_conferir(uuid, uuid, text, text, uuid, timestamptz)', 'execute')
       or has_function_privilege('anon', 'public.retorno_orc_do_audio_marcar(uuid, uuid, uuid, timestamptz)', 'execute')
       or has_function_privilege('anon', 'public.retorno_orc_do_audio_do_caso(uuid, uuid, timestamptz)', 'execute')
       or has_function_privilege('anon', 'public._retorno_orc_impressao(uuid)', 'execute')
       or has_function_privilege('anon', 'public._retorno_orc_linhas(uuid)', 'execute') then
      raise exception '6a: função aberta ao anon ou ao authenticated';
    end if;
    if not has_function_privilege('service_role', 'public.retorno_orc_do_audio_conferir(uuid, uuid, text, text, uuid, timestamptz)', 'execute')
       or not has_function_privilege('service_role', 'public.retorno_orc_do_audio_marcar(uuid, uuid, uuid, timestamptz)', 'execute')
       or not has_function_privilege('service_role', 'public.retorno_orc_do_audio_do_caso(uuid, uuid, timestamptz)', 'execute') then
      raise exception '6b: service_role sem execute';
    end if;

    raise exception 'retorno_f3_audio_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_audio_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f3_audio', true, '{}');
end
$audio$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
