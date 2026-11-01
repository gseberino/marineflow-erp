-- Retorno F0b: whatsapp_esperando_resposta — só a saída do dono responde, robô não espera e o
-- número de 2 clientes não ganha o nome de um deles. E o detector de robô (_retorno_e_automatico).
-- Run: npx supabase db query --linked -f supabase/tests/retorno_f0b_esperando.sql
-- Termina em ROLLBACK: nada fica gravado.
begin;

do $$
declare
  v_longo text := 'Olá! No momento não podemos atender. Nosso horário é de segunda a sexta, das 8h às 18h. Retornaremos em breve.';
  v_c1 uuid; v_c2 uuid;
  v_linha record;
begin
  -- 1. Robô: mensagem modelo/botões/lista; texto longo 3 vezes em 30 dias. Conversa curta repetida não.
  if not public._retorno_e_automatico('5547900009101', '', '{"data": {"message": {"templateMessage": {}}}}', now())
     or not public._retorno_e_automatico('5547900009101', '', '{"data": {"message": {"buttonsMessage": {}}}}', now()) then
    raise exception '1: mensagem modelo ou com botões não é robô';
  end if;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at)
    select 'inbound', '5547900009102', 'text', b, 'received', '{"data": {"message": {"conversation": ""}}}', now() - make_interval(days => d)
      from (values (v_longo, 20), (v_longo, 10), ('bom dia', 9), ('bom dia', 8), ('bom dia', 7)) x(b, d);
  if public._retorno_e_automatico('5547900009102', v_longo, '{}', now()) then
    raise exception '1b: texto longo 2 vezes já virou robô';
  end if;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at)
    values ('inbound', '5547900009102', 'text', v_longo, 'received', '{"data": {}}', now() - interval '1 day');
  if not public._retorno_e_automatico('5547900009102', v_longo, '{}', now()) then
    raise exception '1c: texto longo 3 vezes em 30 dias não virou robô';
  end if;
  if public._retorno_e_automatico('5547900009102', 'bom dia', '{}', now()) then
    raise exception '1d: "bom dia" repetido virou robô';
  end if;
  -- o robô (a última recebida é o texto longo de 1 dia atrás) não aparece na lista
  if exists (select 1 from public.whatsapp_esperando_resposta(now() - interval '30 days', 500) w where w.phone = '5547900009102') then
    raise exception '1e: o robô está na lista de quem espera resposta';
  end if;

  -- 2. A saída automática não responde; a do dono responde.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at)
    values ('inbound', '5547900009103', 'text', 'Oi, o barco fica pronto quando?', 'received', '{"data": {}}', now() - interval '30 minutes'),
           ('outbound', '5547900009103', 'text', 'Lembramos que o pagamento…', 'sent', '{"via": "whatsapp-send", "origem": "sistema"}', now() - interval '20 minutes');
  if not exists (select 1 from public.whatsapp_esperando_resposta(now() - interval '7 days', 500) w where w.phone = '5547900009103') then
    raise exception '2: a saída automática tirou o cliente da lista';
  end if;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at, sent_by)
    values ('outbound', '5547900009103', 'text', 'Te respondo já', 'sent', '{"via": "whatsapp-send", "origem": "tela"}', now() - interval '10 minutes',
            (select id from public.app_users where active limit 1));
  if exists (select 1 from public.whatsapp_esperando_resposta(now() - interval '7 days', 500) w where w.phone = '5547900009103') then
    raise exception '2b: a saída do dono não tirou o cliente da lista';
  end if;

  -- 3. Número de 2 clientes: categoria cliente, sem o nome de nenhum.
  select id into v_c1 from public.clients where active and not generico order by id limit 1;
  select id into v_c2 from public.clients where active and not generico and id <> v_c1 order by id limit 1;
  update public.clients set whatsapp = '(47) 90000-9104' where id in (v_c1, v_c2);
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at)
    values ('inbound', '5547900009104', 'text', 'Alguma novidade?', 'received', '{"data": {}}', now() - interval '5 minutes');
  select * into v_linha from public.whatsapp_esperando_resposta(now() - interval '7 days', 500) w where w.phone = '5547900009104';
  if v_linha.categoria is distinct from 'cliente' or v_linha.contato not like '%(número de 2 clientes)'
     or v_linha.contato like '%' || (select name from public.clients where id = v_c1) || '%' then
    raise exception '3: número de 2 clientes: % / %', v_linha.categoria, v_linha.contato;
  end if;

  raise notice 'retorno_f0b_esperando: OK';
end $$;

rollback;
