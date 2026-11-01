-- Retorno F0b, parte 1: quem_escreve, hora_real, quem_sombra e o tipo do bloqueio.
-- Run: npx supabase db query --linked -f supabase/tests/retorno_f0b_quem_escreve.sql
-- Termina em ROLLBACK: nada fica gravado.
begin;

do $$
declare
  v_c1 uuid; v_c2 uuid; v_c3 uuid; v_c4 uuid; v_generico uuid;
  v_forn uuid; v_forn_inativo uuid;
  v_dono text := (select phone_normalized from public.app_users where active and phone_normalized is not null limit 1);
  q jsonb;
  v_msg record;
begin
  -- 0. DDD.
  if public._ddd_do_telefone('5547999990001') is distinct from '47' or public._ddd_do_telefone('(47) 99999-0001') is distinct from '47'
     or public._ddd_do_telefone('4733330001') is distinct from '47' or public._ddd_do_telefone('55999990001') is distinct from '55'
     or public._ddd_do_telefone('99999-0001') is not null or public._ddd_do_telefone(null) is not null then
    raise exception '0: DDD errado';
  end if;

  select id into v_c1 from public.clients where active and not generico order by id limit 1;
  select id into v_c2 from public.clients where active and not generico and id <> v_c1 order by id limit 1;
  select id into v_c3 from public.clients where active and not generico and id not in (v_c1, v_c2) order by id limit 1;
  select id into v_c4 from public.clients where active and not generico and id not in (v_c1, v_c2, v_c3) order by id limit 1;
  select id into v_generico from public.clients where generico limit 1;
  select id into v_forn from public.suppliers where active order by id limit 1;
  select id into v_forn_inativo from public.suppliers where not active order by id limit 1;

  -- 1. Sem número; e a equipe vem primeiro, mesmo com o número num cadastro de cliente.
  if public.quem_escreve(null)->>'papel' <> 'sem_numero' or public.quem_escreve('123')->>'papel' <> 'sem_numero' then
    raise exception '1: número vazio não deu sem_numero';
  end if;
  update public.clients set whatsapp = v_dono where id = v_c4;
  if public.quem_escreve(v_dono)->>'papel' <> 'equipe' then
    raise exception '1b: número da equipe não deu equipe';
  end if;
  update public.clients set whatsapp = null, phone = null where id = v_c4;

  -- 2. Um cliente ativo, cadastrado sem o 55: identifica, com o id, e só o id (nunca o nome).
  update public.clients set whatsapp = '(47) 90000-8001', phone = null where id = v_c1;
  q := public.quem_escreve('5547900008001');
  if q->>'papel' <> 'cliente' or (q->>'cliente_id')::uuid <> v_c1 or q ? 'nome' or q::text ilike '%name%' then
    raise exception '2: cliente único não identificado: %', q;
  end if;

  -- 3. Dois clientes no mesmo número: ambíguo, com os dois, sem cliente_id.
  update public.clients set phone = '47 90000-8001', whatsapp = null where id = v_c2;
  q := public.quem_escreve('5547900008001');
  if q->>'papel' <> 'cliente_ambiguo' or q->>'motivo' <> 'varios_clientes' or q ? 'cliente_id'
     or jsonb_array_length(q->'clientes') <> 2 then
    raise exception '3: número compartilhado não ficou ambíguo: %', q;
  end if;
  update public.clients set phone = null where id = v_c2;

  -- 4. DDD diferente: ambíguo (os 8 dígitos batem, a pessoa pode ser outra).
  update public.clients set whatsapp = '(11) 90000-8002' where id = v_c2;
  q := public.quem_escreve('5547900008002');
  if q->>'papel' <> 'cliente_ambiguo' or q->>'motivo' <> 'ddd_diferente' then
    raise exception '4: DDD diferente não ficou ambíguo: %', q;
  end if;

  -- 5. Cadastro só com 8–9 dígitos, sem DDD: propõe, nunca identifica.
  update public.clients set whatsapp = '90000-8003' where id = v_c3;
  q := public.quem_escreve('5547900008003');
  if q->>'papel' <> 'cliente_ambiguo' or q->>'motivo' <> 'cadastro_sem_ddd' then
    raise exception '5: cadastro sem DDD identificou: %', q;
  end if;

  -- 6. Inativo e "Cliente Final" não contam: sem outro cadastro, é número novo.
  update public.clients set whatsapp = '(47) 90000-8004', active = false where id = v_c4;
  update public.clients set phone = '(47) 90000-8005' where id = v_generico;
  if public.quem_escreve('5547900008004')->>'papel' <> 'novo' or public.quem_escreve('5547900008005')->>'papel' <> 'novo' then
    raise exception '6: cliente inativo ou Cliente Final identificou';
  end if;

  -- 7. Fornecedor só ativo; cliente ativo vence fornecedor.
  update public.suppliers set phone = '(47) 90000-8006' where id = v_forn;
  if public.quem_escreve('5547900008006')->>'papel' <> 'fornecedor' then
    raise exception '7: fornecedor ativo não deu fornecedor';
  end if;
  if v_forn_inativo is not null then
    update public.suppliers set phone = '(47) 90000-8007' where id = v_forn_inativo;
    if public.quem_escreve('5547900008007')->>'papel' <> 'novo' then
      raise exception '7b: fornecedor inativo contou';
    end if;
  end if;
  update public.suppliers set phone = '(47) 90000-8001' where id = v_forn;
  if public.quem_escreve('5547900008001')->>'papel' <> 'cliente' then
    raise exception '7c: fornecedor venceu o cliente';
  end if;

  -- 8. Gatilho: recebida do webhook com messageTimestamp → hora_real e quem_sombra.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', '5547900008001', 'text', 'teste F0b', 'received', '{"data": {"messageTimestamp": 1762000000}}')
    returning hora_real, quem_sombra, occurred_at into v_msg;
  if v_msg.hora_real is distinct from to_timestamp(1762000000) or v_msg.quem_sombra->>'papel' <> 'cliente' then
    raise exception '8: recebida sem hora_real ou quem_sombra: % %', v_msg.hora_real, v_msg.quem_sombra;
  end if;

  -- 9. Do webhook, sem número: hora_real nula (nunca "agora" em silêncio); em ms (fora da faixa): nula.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', '5547900008001', 'text', 'teste F0b', 'received', '{"data": {"messageTimestamp": "1762000000"}}')
    returning hora_real into v_msg;
  if v_msg.hora_real is not null then raise exception '9: timestamp em texto virou hora_real'; end if;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', '5547900008001', 'text', 'teste F0b', 'received', '{"data": {"messageTimestamp": 1762000000000}}')
    returning hora_real into v_msg;
  if v_msg.hora_real is not null then raise exception '9b: timestamp em ms virou hora_real'; end if;

  -- 10. Saída pelos nossos envios: hora da gravação; quem_sombra só nas recebidas.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('outbound', '5547900008001', 'text', 'teste F0b', 'sent', '{"via": "whatsapp-send", "origem": "sistema"}')
    returning hora_real, quem_sombra into v_msg;
  if v_msg.hora_real is distinct from now() or v_msg.quem_sombra is not null then
    raise exception '10: saída do whatsapp-send: % %', v_msg.hora_real, v_msg.quem_sombra;
  end if;

  -- 11. Bloqueio: tipo padrão spam, só spam ou opt_out.
  insert into public.whatsapp_blocked_numbers (phone_normalized, reason) values ('5547900008009', 'teste F0b')
    returning tipo into v_msg;
  if v_msg.tipo <> 'spam' then raise exception '11: tipo padrão não é spam'; end if;
  begin
    insert into public.whatsapp_blocked_numbers (phone_normalized, reason, tipo) values ('5547900008010', 'teste F0b', 'outro');
    raise exception '11b: tipo inválido aceito';
  exception when check_violation then null;
  end;

  -- 12. Só o servidor chama quem_escreve.
  if has_function_privilege('anon', 'public.quem_escreve(text)', 'execute')
     or has_function_privilege('authenticated', 'public.quem_escreve(text)', 'execute') then
    raise exception '12: quem_escreve aberta a anon/authenticated';
  end if;

  raise notice 'retorno_f0b_quem_escreve: OK';
end $$;

rollback;
