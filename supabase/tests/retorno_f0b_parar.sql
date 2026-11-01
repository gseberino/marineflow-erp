-- Retorno F0b: o PARAR de qualquer número vira opt-out (whatsapp_blocked_numbers, tipo opt_out).
-- Run: npx supabase db query --linked -f supabase/tests/retorno_f0b_parar.sql
-- Termina em ROLLBACK: nada fica gravado.
begin;

do $$
declare
  v_dono text := (select phone_normalized from public.app_users where active and phone_normalized is not null limit 1);
  v_n int;
begin
  -- 1. A regra é a mensagem inteira.
  if not (public._e_pedido_de_parar('PARAR') and public._e_pedido_de_parar('Pare!') and public._e_pedido_de_parar(' sair ')
          and public._e_pedido_de_parar('STOP') and public._e_pedido_de_parar('Descadastrar')
          and public._e_pedido_de_parar('Não quero mais mensagens') and public._e_pedido_de_parar('nao quero mais receber mensagem, por favor')
          and public._e_pedido_de_parar('Não quero mais mensagens automáticas.')) then
    raise exception '1: pedido de parar não reconhecido';
  end if;
  if public._e_pedido_de_parar('vou parar o carro aí às 14h') or public._e_pedido_de_parar('nunca mais faço com vocês')
     or public._e_pedido_de_parar('me tira uma dúvida') or public._e_pedido_de_parar('pode parar o serviço?')
     or public._e_pedido_de_parar('') or public._e_pedido_de_parar(null) or public._e_pedido_de_parar('não quero mais o orçamento') then
    raise exception '1b: frase que não é pedido de parar foi aceita';
  end if;

  -- 2. Recebida "PARAR" de um número qualquer: opt-out gravado, uma vez só, e o envio automático passa a ser barrado.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', '5547900009001', 'text', 'PARAR', 'received', '{"data": {"messageTimestamp": 1762000000}}');
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', '5547900009001', 'text', 'parar', 'received', '{"data": {"messageTimestamp": 1762000100}}');
  select count(*) into v_n from public.whatsapp_blocked_numbers where phone_normalized = '5547900009001' and tipo = 'opt_out';
  if v_n <> 1 then raise exception '2: opt-out gravado % vezes', v_n; end if;
  if public.canal_bloqueado('5547900009001') is distinct from 'bloqueado' then
    raise exception '2b: o número que pediu para parar não ficou barrado no automático';
  end if;

  -- 3. Frase com a palavra, a enviada e a equipe: nada.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload)
    values ('inbound', '5547900009002', 'text', 'vou parar aí amanhã', 'received', '{"data": {}}'),
           ('outbound', '5547900009003', 'text', 'PARAR', 'sent', '{"via": "whatsapp-send", "origem": "tela"}'),
           ('inbound', v_dono, 'text', 'PARAR', 'received', '{"data": {}}');
  select count(*) into v_n from public.whatsapp_blocked_numbers
   where phone_normalized in ('5547900009002', '5547900009003', v_dono) and tipo = 'opt_out';
  if v_n <> 0 then raise exception '3: frase, enviada ou equipe virou opt-out (%)', v_n; end if;

  raise notice 'retorno_f0b_parar: OK';
end $$;

rollback;
