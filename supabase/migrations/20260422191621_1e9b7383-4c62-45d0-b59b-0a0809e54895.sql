DELETE FROM public.whatsapp_messages 
WHERE direction='inbound' 
  AND message_type='other' 
  AND raw_payload->>'type' IN ('MessageStatusCallback','DeliveryCallback','PresenceChatCallback','NotificationCallback','ConnectedCallback','DisconnectedCallback');