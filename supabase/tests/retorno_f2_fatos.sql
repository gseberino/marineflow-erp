-- Retorno F2 (P5): o fato confiável e quando o modelo cabe. Relógio fixo em ter 10/11/2026 15:00. Roda só pela bancada.
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000096xx; nomes e frases inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f2f_cliente(p_nome text, p_whats text)
returns uuid language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_whats) returning id
$f$;

create or replace function pg_temp.f2f_os(p_num text, p_cliente uuid, p_status text, p_criada timestamptz default '2026-10-01 12:00-03')
returns uuid language sql as $f$
  insert into public.service_orders (service_order_number, client_id, status, quote_status, service_type, created_at, updated_at,
                                     converted_to_os_at, grand_total)
  values (p_num, p_cliente, p_status, 'approved', 'repair', p_criada, p_criada, p_criada, 100)
  returning id
$f$;

create or replace function pg_temp.f2f_concluir(p_os uuid, p_em timestamptz, p_origem text default 'dono')
returns uuid language sql as $f$
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, texto)
  values (p_em, (p_em at time zone 'America/Sao_Paulo')::date, true, p_origem, 'concluir', p_os, 'concluiu no teste')
  returning id
$f$;

create or replace function pg_temp.f2f_material(p_os uuid, p_situacao text, p_critico boolean, p_fonte text, p_chegou date default null)
returns uuid language sql as $f$
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte,
                                  chegou_em, atualizado_em)
  values (p_os, 'dono', 'compressor de teste', 1, case when p_situacao = 'na_mao' then 1 else 0 end, p_critico, p_situacao, p_fonte, p_chegou,
          '2026-10-22 10:00-03')
  returning id
$f$;

create or replace function pg_temp.f2f_caso(p_fone text, p_papel text, p_em timestamptz, p_cliente uuid, p_nivel text default 'recibo')
returns uuid language plpgsql as $f$
declare
  v_id uuid;
begin
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
  select public._agenda_chave_telefone(p_fone), p_fone, '47', p_papel, jsonb_build_object('papel', p_papel), p_cliente, w.id, w.id,
         p_em, p_em, p_em, p_em, p_nivel, 'recibo_cliente', 'aberta', 'sombra'
    from public.whatsapp_messages w
   where w.phone_normalized = p_fone
   order by w.occurred_at
   limit 1
  returning id into v_id;
  return v_id;
end $f$;

create or replace function pg_temp.f2f_msg(p_fone text, p_body text, p_em timestamptz, p_caso uuid default null)
returns uuid language plpgsql as $f$
declare
  v_msg uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', p_fone, 'text', p_body, 'received', '{"data": {}}'::jsonb, p_em, p_em)
  returning id into v_msg;
  if p_caso is not null then
    insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
    values (v_msg, p_caso, public._agenda_chave_telefone(p_fone), p_em, p_em, 'x', true);
  end if;
  return v_msg;
end $f$;

-- Um caso novo com as frases dadas; o id.
create or replace function pg_temp.f2f_caso_com(p_fone text, p_cliente uuid, p_frases text[], p_em timestamptz)
returns uuid language plpgsql as $f$
declare
  v_caso uuid;
  v_f text;
  v_i integer := 0;
begin
  delete from public.retorno_mensagens m using public.whatsapp_messages w
   where w.id = m.whatsapp_message_id and w.phone_normalized = p_fone;
  delete from public.retorno_aberturas a where a.phone_normalized = p_fone;
  delete from public.whatsapp_messages w where w.phone_normalized = p_fone;
  perform pg_temp.f2f_msg(p_fone, p_frases[1], p_em);
  v_caso := pg_temp.f2f_caso(p_fone, 'cliente', p_em, p_cliente);
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
  select w.id, v_caso, public._agenda_chave_telefone(p_fone), p_em, p_em, 'x', true
    from public.whatsapp_messages w where w.phone_normalized = p_fone;
  foreach v_f in array p_frases[2:] loop
    v_i := v_i + 1;
    perform pg_temp.f2f_msg(p_fone, v_f, p_em + make_interval(mins => v_i), v_caso);
  end loop;
  return v_caso;
end $f$;

do $fatos$
declare
  c_agora constant timestamptz := '2026-11-10 15:00:00-03';   -- terça
  c_hoje constant date := '2026-11-10';
  c_fone constant text := '5547900009601';
  v_cl uuid; v_cl2 uuid;
  v_os uuid; v_os2 uuid;
  v_ac uuid;
  v_r jsonb;
  v_f jsonb;
  v_m uuid;
  v_payee uuid;
  v_caso uuid;
  v_n integer;
begin
  begin
    update public.agenda_config set prazo_sem_fornecedor_du = 7;
    v_cl := pg_temp.f2f_cliente('Rodrigo Fato Teste', '(47) 90000-9601');

    -- 1. OS concluída por lote, sem a palavra: pronto nulo, concluida_sem_palavra preenchido.
    v_os := pg_temp.f2f_os('OS-09601', v_cl, 'completed', '2026-10-20 12:00-03');
    v_r := public.retorno_fatos_do_contato(c_fone, c_agora);
    if v_r ->> 'papel' <> 'cliente' or (v_r ->> 'client_id')::uuid is distinct from v_cl or jsonb_array_length(v_r -> 'os') <> 1 then
      raise exception '1a: contato (%)', v_r;
    end if;
    v_f := v_r -> 'os' -> 0 -> 'fatos';
    if v_f -> 'pronto' <> 'null'::jsonb or v_f -> 'concluida_sem_palavra' ->> 'desde' is distinct from '2026-10-20' then
      raise exception '1b: lote virou pronto (%)', v_f;
    end if;

    -- 2. A palavra: 47 h conta, 49 h não; desfeita não; pela tela não.
    update public.service_orders set updated_at = '2026-09-01 12:00-03' where id = v_os;
    v_ac := pg_temp.f2f_concluir(v_os, c_agora - interval '47 hours');
    v_f := public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos';
    if v_f -> 'pronto' ->> 'fonte' is distinct from 'dono' or (v_f -> 'pronto' ->> 'idade_h')::integer <> 47 then
      raise exception '2a: pronto de 47 h (%)', v_f;
    end if;
    if jsonb_array_length(public.retorno_fatos_do_contato(c_fone, c_agora + interval '2 hours') -> 'os') <> 0 then
      raise exception '2b: pronto de 49 h';
    end if;
    update public.agenda_acoes set desfeita_em = c_agora - interval '1 hour', desfeita_pela = id where id = v_ac;
    if jsonb_array_length(public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os') <> 0 then
      raise exception '2c: pronto desfeito';
    end if;
    update public.agenda_acoes set origem = 'tela', desfeita_em = null, desfeita_pela = null where id = v_ac;
    if jsonb_array_length(public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os') <> 0 then
      raise exception '2d: pronto pela tela';
    end if;
    -- Ninguém olha o futuro.
    update public.agenda_acoes set origem = 'dono', criada_em = c_agora + interval '1 hour' where id = v_ac;
    if jsonb_array_length(public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os') <> 0 then
      raise exception '2e: palavra do futuro';
    end if;
    delete from public.agenda_acoes where id = v_ac;

    -- 3. Em serviço: check-in de 23 h conta, de 25 h não.
    update public.service_orders set status = 'in_progress', check_in_at = c_agora - interval '23 hours' where id = v_os;
    v_f := public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos';
    if v_f -> 'em_servico' ->> 'fonte' is distinct from 'check_in' then
      raise exception '3a: check-in (%)', v_f;
    end if;
    update public.service_orders set check_in_at = c_agora - interval '25 hours' where id = v_os;
    if public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos' -> 'em_servico' <> 'null'::jsonb then
      raise exception '3b: check-in velho';
    end if;
    -- A alocação com a confirmação do técnico conta; substituída não; sem confirmação não.
    select p.id into v_payee from public.payees p limit 1;
    if v_payee is null then
      insert into public.payees (name) values ('Tecnico Fato Teste') returning id into v_payee;
    end if;
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, estado, tipo)
    values (v_os, v_payee, c_hoje, 'publicada', 'normal');
    if public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos' -> 'em_servico' <> 'null'::jsonb then
      raise exception '3c: alocação sem confirmação';
    end if;
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, criado_em)
    values (v_payee, daterange(c_hoje, c_hoje + 1), 'confirmada', 'dono', c_agora - interval '2 hours')
    returning id into v_ac;
    if public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos' -> 'em_servico' ->> 'fonte' is distinct from 'tecnico' then
      raise exception '3d: alocação confirmada';
    end if;
    update public.agenda_disponibilidade set substituida_em = c_agora where id = v_ac;
    if public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos' -> 'em_servico' <> 'null'::jsonb then
      raise exception '3e: confirmação substituída';
    end if;
    delete from public.agenda_alocacoes where service_order_id = v_os;

    -- 4. Peça: estoque não conta; nota de 7 dias conta, de 8 não; faltam_outras.
    v_m := pg_temp.f2f_material(v_os, 'na_mao', true, 'estoque', c_hoje - 1);
    if public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos' -> 'peca_chegou' <> 'null'::jsonb then
      raise exception '4a: estoque virou chegada';
    end if;
    update public.os_material set fonte = 'nfe', chegou_em = c_hoje - 7 where id = v_m;
    v_f := public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos';
    if v_f -> 'peca_chegou' ->> 'fonte' is distinct from 'nfe' or (v_f -> 'peca_chegou' ->> 'faltam_outras')::boolean then
      raise exception '4b: nota de 7 dias (%)', v_f;
    end if;
    update public.os_material set chegou_em = c_hoje - 8 where id = v_m;
    if public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos' -> 'peca_chegou' <> 'null'::jsonb then
      raise exception '4c: nota de 8 dias';
    end if;
    update public.os_material set chegou_em = c_hoje - 1 where id = v_m;

    -- 5. Aguardando: não crítica não conta; previsão padrão de 7 dias úteis; previsão dada.
    v_m := pg_temp.f2f_material(v_os, 'falta', false, 'dono');
    if public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos' -> 'aguarda_peca' <> 'null'::jsonb then
      raise exception '5a: não crítica';
    end if;
    update public.os_material set critico = true where id = v_m;
    v_f := public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos';
    if not (v_f -> 'peca_chegou' ->> 'faltam_outras')::boolean then
      raise exception '5b: faltam_outras (%)', v_f;
    end if;
    if (v_f -> 'previsao' ->> 'padrao')::boolean is distinct from true
       or (v_f -> 'previsao' ->> 'ate')::date is distinct from public.agenda_somar_du(c_hoje, 7) then
      raise exception '5c: previsão padrão (%)', v_f -> 'previsao';
    end if;
    update public.os_material set situacao = 'a_caminho', previsao_ate = '2026-11-14', previsao_fonte = 'fornecedor' where id = v_m;
    v_f := public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os' -> 0 -> 'fatos';
    if v_f -> 'previsao' ->> 'ate' is distinct from '2026-11-14' or (v_f -> 'previsao' ->> 'padrao')::boolean then
      raise exception '5d: previsão dada (%)', v_f -> 'previsao';
    end if;
    delete from public.os_material where service_order_id = v_os;

    -- 6. Quem não é cliente não traz OS.
    v_cl2 := pg_temp.f2f_cliente('Marcos Fato Teste', '(47) 90000-9602');
    insert into public.clients (type, name, phone) values ('individual', 'Marta Fato Teste', '(47) 90000-9602');
    v_r := public.retorno_fatos_do_contato('5547900009602', c_agora);
    if v_r ->> 'papel' <> 'cliente_ambiguo' or not (v_r ->> 'ambiguo')::boolean or jsonb_array_length(v_r -> 'os') <> 0 then
      raise exception '6a: número de 2 clientes (%)', v_r;
    end if;
    insert into public.suppliers (name, phone) values ('Fornecedor Fato Teste', '(47) 90000-9603');
    if jsonb_array_length(public.retorno_fatos_do_contato('5547900009603', c_agora) -> 'os') <> 0 then
      raise exception '6b: fornecedor trouxe OS';
    end if;

    -- 7. Liberada: há 13 dias está, há 15 não; entregue não.
    v_os2 := pg_temp.f2f_os('OS-09602', v_cl, 'invoiced');
    update public.service_orders set status = 'cancelled' where id = v_os;
    update public.service_orders set liberado_retirada_em = c_agora - interval '13 days' where id = v_os2;
    v_r := public.retorno_fatos_do_contato(c_fone, c_agora);
    if jsonb_array_length(v_r -> 'os') <> 1 or v_r -> 'os' -> 0 -> 'fatos' -> 'liberado' = 'null'::jsonb then
      raise exception '7a: liberada há 13 dias (%)', v_r;
    end if;
    update public.service_orders set liberado_retirada_em = c_agora - interval '15 days' where id = v_os2;
    if jsonb_array_length(public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os') <> 0 then
      raise exception '7b: liberada há 15 dias';
    end if;
    update public.service_orders set liberado_retirada_em = c_agora - interval '1 day', delivered_at = c_agora - interval '1 hour' where id = v_os2;
    if jsonb_array_length(public.retorno_fatos_do_contato(c_fone, c_agora) -> 'os') <> 0 then
      raise exception '7c: entregue segue liberada';
    end if;
    update public.service_orders set delivered_at = null, liberado_retirada_em = null, status = 'in_progress' where id = v_os2;

    -- 8. Regras do modelo, uma a uma. v_os2 é a OS viva.
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_em)
    values (v_os2, 'dono', 'compressor de teste', 1, 0, true, 'falta', 'dono', '2026-10-22 10:00-03');

    v_caso := pg_temp.f2f_caso_com(c_fone, v_cl, array['como tá o motorhome?'], c_agora - interval '1 hour');
    v_r := public._retorno_modelo_do_caso(v_caso, c_agora);
    if v_r ->> 'modelo' is distinct from 'modelo_aguarda_peca' then
      raise exception '8a: como tá (%)', v_r;
    end if;
    if (v_r -> 'fato')::text like '%previsao%' or (v_r -> 'fato')::text like '%compressor%' then
      raise exception '8b: o fato do modelo levou previsão ou descrição (%)', v_r -> 'fato';
    end if;
    v_caso := pg_temp.f2f_caso_com(c_fone, v_cl, array['como tá o motorhome?', 'e preciso trocar a bateria'], c_agora - interval '1 hour');
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'sinal' then
      raise exception '8c: pedido misturado (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    v_caso := pg_temp.f2f_caso_com(c_fone, v_cl, array['oi, bom dia', 'como tá o motorhome?'], c_agora - interval '1 hour');
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'modelo' is distinct from 'modelo_aguarda_peca' then
      raise exception '8d: saudação junto (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    v_caso := pg_temp.f2f_caso_com(c_fone, v_cl, array['como tá o motorhome?', 'quero ver uma coisa'], c_agora - interval '1 hour');
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'outro_pedido' then
      raise exception '8e: outro pedido (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    v_caso := pg_temp.f2f_caso_com(c_fone, v_cl, array['obrigado pelo atendimento'], c_agora - interval '1 hour');
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'sem_intencao' then
      raise exception '8f: sem intenção (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    v_caso := pg_temp.f2f_caso_com(c_fone, v_cl, array['como tá o motorhome?', 'a peça chegou?'], c_agora - interval '1 hour');
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'misturado' then
      raise exception '8g: misturado (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    v_caso := pg_temp.f2f_caso_com(c_fone, v_cl, array['como tá o motorhome?'], c_agora - interval '1 hour');
    update public.retorno_aberturas set papel = 'cliente_ambiguo' where id = v_caso;
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'papel' then
      raise exception '8h: papel';
    end if;
    update public.retorno_aberturas set papel = 'cliente', nivel = 'passagem' where id = v_caso;
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'passagem' then
      raise exception '8i: passagem';
    end if;
    update public.retorno_aberturas set nivel = 'recibo' where id = v_caso;
    -- 2 OS vivas, depois nenhuma
    update public.service_orders set status = 'in_progress' where id = v_os;
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'os_varias' then
      raise exception '8j: 2 OS (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    update public.service_orders set status = 'cancelled' where id in (v_os, v_os2);
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'os_0' then
      raise exception '8k: 0 OS (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    update public.service_orders set status = 'in_progress' where id = v_os2;
    delete from public.os_material where service_order_id = v_os2;
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'sem_fato' then
      raise exception '8l: sem fato (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    -- a agenda já disse; o modelo já saiu
    v_m := pg_temp.f2f_material(v_os2, 'falta', true, 'dono');
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, modelo, modo, texto, base, enviar_em, estado, enviada_em, dedupe_key)
    values (v_cl, v_os2, 'pode_atrasar', 'M', 'ligado', 'texto do teste', '{}', c_agora - interval '2 hours', 'enviada', c_agora - interval '2 hours', 'teste-f2-fatos:1');
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'agenda_ja_disse' then
      raise exception '8m: agenda já disse (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    delete from public.agenda_cliente_mensagens where service_order_id = v_os2;
    insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, modo, estado, decidida_em, enviada_em, enviar_em, texto, dedupe_key)
    values (v_caso, 'modelo_aguarda_peca', 'retorno_modelo', 'resposta_imediata', public._agenda_chave_telefone(c_fone), c_fone, 'ligado', 'enviada',
            c_agora - interval '2 hours', c_agora - interval '2 hours', c_agora - interval '2 hours', 'Texto do modelo.', 'teste-f2-fatos:2');
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'repete' then
      raise exception '8n: repete (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    delete from public.retorno_saidas where abertura_id = v_caso;
    -- a peça chegou e o cliente pergunta como está: M02b
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = 1, chegou_em = c_hoje - 1 where id = v_m;
    v_r := public._retorno_modelo_do_caso(v_caso, c_agora);
    if v_r ->> 'modelo' is distinct from 'modelo_peca_chegou' or v_r ->> 'intencao' <> 'status' then
      raise exception '8o: peça + status (%)', v_r;
    end if;
    -- posso retirar? só com o libera
    v_caso := pg_temp.f2f_caso_com(c_fone, v_cl, array['posso retirar hoje?'], c_agora - interval '1 hour');
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'motivo' is distinct from 'sem_intencao' then
      raise exception '8p: retirada sem bem e sem libera (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;
    update public.service_orders set liberado_retirada_em = c_agora - interval '1 hour' where id = v_os2;
    if public._retorno_modelo_do_caso(v_caso, c_agora) ->> 'modelo' is distinct from 'modelo_liberado' then
      raise exception '8q: retirada com libera (%)', public._retorno_modelo_do_caso(v_caso, c_agora);
    end if;

    -- 9. anon não chama.
    begin
      set local role anon;
      perform public.retorno_fatos_do_contato(c_fone, c_agora);
      reset role;
      raise exception '9: anon chamou o fato';
    exception when insufficient_privilege then
      reset role;
    end;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_fatos', true, '{}');
end
$fatos$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
