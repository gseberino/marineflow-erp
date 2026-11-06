-- Retorno rápido (P16.4): a máscara do PIN em whatsapp_messages.
-- Run: npx supabase db query --linked -f supabase/tests/pin_mascarar.sql
-- Termina em ROLLBACK: nada fica gravado. O PIN é inventado (7391) e o hash é sintético, num usuário de teste: nenhuma
-- mensagem real é lida, nem por filtro.
begin;

do $$
declare
  v_equipe constant text := '5547900016001';
  v_sem_ai constant text := '5547900016002';
  v_inativo constant text := '5547900016004';
  v_cliente constant text := '5547900016003';
  -- O par (sal-a, 7391) é o mesmo de whatsapp-pin_test.ts: é ele que prova a paridade do gatilho com verifyPin.
  v_hash constant text := 'sal-a:00fe044f96335b6e8cc5890a19455da862d3380e679be60a7a75722a957b33af';
  v_carga constant jsonb := '{"data": {"key": {"id": "TESTE"}, "messageTimestamp": 1762000000, "message": {"conversation": "x"}}}';
  v_id uuid;
  v_id2 uuid;
  v_corpo text;
  v_raw jsonb;
  v_hora timestamptz;
  v_quem jsonb;
  v_n int;
  v_c record;
begin
  -- 0. A conta do hash é a mesma do TypeScript, nos 3 pares do teste de lá.
  if encode(sha256(convert_to('sal-a:7391', 'UTF8')), 'hex') <> '00fe044f96335b6e8cc5890a19455da862d3380e679be60a7a75722a957b33af'
     or encode(sha256(convert_to('3f0c2f5e-0000-4000-8000-000000000001:004821', 'UTF8')), 'hex') <> '01325accc9677860a5f56b2c53656b688c0c032183edcf277650631440aecb4a'
     or encode(sha256(convert_to('x:123', 'UTF8')), 'hex') <> '96d83a375baee82501356c68b3c0bf2133f902e74776e517d205f4e9da5a41ec' then
    raise exception '0: o hash em SQL não bate com o do TypeScript';
  end if;

  insert into auth.users (id, email)
    values ('b1600000-0000-4000-8000-000000000001', 'teste-pin-1@teste.invalid'),
           ('b1600000-0000-4000-8000-000000000002', 'teste-pin-2@teste.invalid'),
           ('b1600000-0000-4000-8000-000000000003', 'teste-pin-3@teste.invalid');
  insert into public.app_users (id, full_name, email, role, active, phone_normalized, ai_whatsapp_enabled, ai_whatsapp_pin_hash)
    values ('b1600000-0000-4000-8000-000000000001', 'TESTE PIN equipe', 'teste-pin-1@teste.invalid', 'technician', true, v_equipe, true, v_hash),
           ('b1600000-0000-4000-8000-000000000002', 'TESTE PIN sem IA', 'teste-pin-2@teste.invalid', 'technician', true, v_sem_ai, false, v_hash),
           ('b1600000-0000-4000-8000-000000000003', 'TESTE PIN inativo', 'teste-pin-3@teste.invalid', 'technician', false, v_inativo, true, v_hash)
    on conflict (id) do update
      set phone_normalized = excluded.phone_normalized, ai_whatsapp_enabled = excluded.ai_whatsapp_enabled,
          ai_whatsapp_pin_hash = excluded.ai_whatsapp_pin_hash, active = excluded.active;

  -- 1 a 4. Texto: entrada, saída esperada e se a carga perde o texto.
  for v_c in
    select * from (values
      ('sim 7391', 'sim ••••', true),
      ('Sim, 7391.', 'Sim, ••••.', true),
      ('🎤 Sim. 7391', '🎤 Sim. ••••', true),
      ('1 7391', '1 ••••', true),
      ('ok 7391', 'ok ••••', true),
      ('confirmo 7391', 'confirmo ••••', true),
      ('2 B 7391', '2 B ••••', true),
      ('manda o 7391 aí, por favor', 'manda o •••• aí, por favor', true),
      ('7391', '••••', true),
      ('7 3 9 1', '••••', true),
      ('é 7, 3, 9, 1', 'é ••••', true),
      ('7-3-9-1 pronto', '•••• pronto', true),
      ('sim 1234', 'sim ••••', true),
      ('s 123', 's ••••', true),
      ('13 peças', '13 peças', false),
      ('R$ 500', 'R$ 500', false),
      ('sim 3 peças', 'sim 3 peças', false),
      ('sim 235 reais', 'sim 235 reais', false),
      ('OS-00070 pronta às 14h', 'OS-00070 pronta às 14h', false),
      ('73910 não é o mesmo número', '73910 não é o mesmo número', false),
      ('Telefone 5547900016001', 'Telefone 5547900016001', false)
    ) as t(entrada, saida, tira_texto)
  loop
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, wa_message_id)
      values ('inbound', v_equipe, 'text', v_c.entrada, 'received', v_carga, 'teste-pin-' || md5(v_c.entrada))
      returning body, raw_payload into v_corpo, v_raw;
    if v_corpo is distinct from v_c.saida then
      raise exception '1: % virou %', v_c.entrada, v_corpo;
    end if;
    if v_c.tira_texto then
      if v_raw #> '{data,message}' is not null or (v_raw ->> 'pin_mascarado') is distinct from 'true' then
        raise exception '1: a carga de % ficou com o texto', v_c.entrada;
      end if;
      if v_raw #>> '{data,key,id}' is distinct from 'TESTE' or v_raw #>> '{data,messageTimestamp}' is distinct from '1762000000' then
        raise exception '1: a carga de % perdeu a chave ou a hora', v_c.entrada;
      end if;
    elsif v_raw is distinct from v_carga then
      raise exception '1: a carga de % mudou sem máscara', v_c.entrada;
    end if;
  end loop;

  -- 3. O mesmo texto vindo de cliente, de quem tem a IA desligada e de usuário inativo: nada muda.
  for v_c in select * from (values (v_cliente), (v_sem_ai), (v_inativo)) as t(tel) loop
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
      values ('inbound', v_c.tel, 'text', 'sim 7391', 'received', v_carga)
      returning body, raw_payload into v_corpo, v_raw;
    if v_corpo <> 'sim 7391' or v_raw <> v_carga then
      raise exception '3: a mensagem de % foi mascarada', v_c.tel;
    end if;
  end loop;

  -- 3b. Saída nunca passa pelo gatilho.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status)
    values ('outbound', v_equipe, 'text', 'sim 7391', 'sent') returning body into v_corpo;
  if v_corpo <> 'sim 7391' then raise exception '3b: saída mascarada'; end if;

  -- 5. A transcrição do áudio regrava body: mascara o corpo e deixa a carga, que o download do áudio usa.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', v_equipe, 'audio', '[audio]', 'received', '{"data": {"key": {"id": "AUDIO"}, "messageTimestamp": 1762000000, "message": {"audioMessage": {"url": "u"}}}}')
    returning id into v_id;
  update public.whatsapp_messages set body = '🎤 sim 7391' where id = v_id returning body, raw_payload into v_corpo, v_raw;
  if v_corpo <> '🎤 sim ••••' then raise exception '5: transcrição virou %', v_corpo; end if;
  if v_raw #> '{data,message,audioMessage}' is null then raise exception '5: a transcrição mexeu na carga'; end if;

  -- 6. Mídia perde só a legenda; documento com legenda, guardado como texto, mantém o arquivo do comprovante.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', v_equipe, 'image', 'sim 7391', 'received', '{"data": {"key": {"id": "IMG"}, "message": {"imageMessage": {"url": "u", "caption": "sim 7391"}}}}')
    returning raw_payload into v_raw;
  if v_raw #> '{data,message,imageMessage,caption}' is not null or v_raw #>> '{data,message,imageMessage,url}' <> 'u' then
    raise exception '6: imagem com a carga errada';
  end if;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', v_equipe, 'text', 'comprovante 7391', 'received',
      '{"data": {"key": {"id": "DOC"}, "message": {"documentWithCaptionMessage": {"message": {"documentMessage": {"url": "u", "caption": "comprovante 7391"}}}}}}')
    returning body, raw_payload into v_corpo, v_raw;
  if v_corpo <> 'comprovante ••••'
     or v_raw #> '{data,message,documentWithCaptionMessage,message,documentMessage,caption}' is not null
     or v_raw #>> '{data,message,documentWithCaptionMessage,message,documentMessage,url}' <> 'u' then
    raise exception '6: o documento com legenda perdeu o arquivo ou manteve a legenda';
  end if;

  -- 7. Erro na carga: a mensagem entra mascarada, sem a carga, e o erro fica no log, sem o corpo.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', v_equipe, 'text', 'sim 7391 ', 'received', '"carga fora do formato"')
    returning id, body, raw_payload into v_id2, v_corpo, v_raw;
  if v_id2 is null or v_corpo <> 'sim •••• ' or v_raw <> '{"pin_mascarado": true}'::jsonb then
    raise exception '7: a mensagem com carga ruim virou %', v_corpo;
  end if;
  select count(*) into v_n from public.app_error_logs
   where context = '_whatsapp_mascarar_pin' and action = 'mascarar_carga' and last_seen_at > now() - interval '1 minute';
  if v_n <> 1 then raise exception '7: erro não registrado (%)', v_n; end if;
  select count(*) into v_n from public.app_error_logs
   where context = '_whatsapp_mascarar_pin' and message ~ '7391';
  if v_n <> 0 then raise exception '7: o PIN foi ao log'; end if;

  -- 8. A F0b continua preenchendo a hora e a sombra com a carga já limpa.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', v_equipe, 'text', 'sim 7391', 'received', v_carga)
    returning hora_real, quem_sombra into v_hora, v_quem;
  if v_hora is null or v_quem is null then raise exception '8: hora_real % e quem_sombra %', v_hora, v_quem; end if;

  -- 9. Fechada para quem não é o banco.
  if has_function_privilege('anon', 'public._whatsapp_mascarar_pin()', 'execute')
     or has_function_privilege('authenticated', 'public._whatsapp_mascarar_pin()', 'execute')
     or has_function_privilege('anon', 'public._whatsapp_payload_sem_texto(jsonb, text)', 'execute')
     or has_function_privilege('authenticated', 'public._whatsapp_payload_sem_texto(jsonb, text)', 'execute') then
    raise exception '9: função aberta';
  end if;
  execute 'set local role anon';
  begin
    perform public._whatsapp_payload_sem_texto('{}'::jsonb, 'text');
    raise exception '9: anon executou a função';
  exception when insufficient_privilege then
    null;
  end;
  execute 'reset role';

  -- 10. A ordem: a máscara roda antes da hora_e_quem.
  if (select array_agg(t.tgname::text order by t.tgname) from pg_trigger t
       where t.tgrelid = 'public.whatsapp_messages'::regclass and not t.tgisinternal and t.tgtype & 2 = 2)
     is distinct from array['trg_whatsapp_mascarar_pin', 'trg_whatsapp_mensagem_hora_e_quem'] then
    raise exception '10: gatilhos before fora do esperado';
  end if;

  raise notice 'pin_mascarar: tudo certo';
end;
$$;

select 'pin_mascarar ok' as resultado;
rollback;
