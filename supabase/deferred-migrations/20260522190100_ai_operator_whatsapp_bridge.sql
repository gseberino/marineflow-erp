-- ============================================================================
-- MarineFlow AI Operator — bridge passiva WhatsApp → ai_operator_channel_events
-- ============================================================================
-- Objetivo: enfileirar automaticamente mensagens inbound do WhatsApp na fila
-- do AI Operator SEM tocar no código do edge function `whatsapp-webhook`.
--
-- Estratégia: trigger AFTER INSERT em `whatsapp_messages` que cria um evento
-- correspondente em `ai_operator_channel_events`.
--
-- Segurança:
--   * Apenas mensagens INBOUND são enfileiradas (fromMe=false, direction='inbound').
--   * O enfileiramento NÃO dispara resposta automática ao cliente.
--   * Em caso de falha, o trigger NÃO falha a inserção da mensagem original
--     (RAISE WARNING + ignore).
--   * Provider é deduzido como 'zapi' por enquanto. Quando Evolution/n8n
--     começarem a alimentar whatsapp_messages, basta ajustar a função.
--   * Mídias (image/audio/document/etc.) também são enfileiradas — o processamento
--     multimodal (transcrição, OCR) é tarefa de ciclo posterior, mas a fila já
--     captura o material para que nada se perca.
--
-- Rollback (manual):
--   drop trigger if exists trg_whatsapp_messages_to_ai_operator on public.whatsapp_messages;
--   drop function if exists public.ai_operator_enqueue_whatsapp_message();
-- ============================================================================

create or replace function public.ai_operator_enqueue_whatsapp_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider text := 'zapi';
begin
  -- Só enfileira mensagens inbound (recebidas do cliente)
  if NEW.direction is distinct from 'inbound' then
    return NEW;
  end if;

  -- Não enfileira eventos de status/sistema
  if NEW.body is null or length(NEW.body) = 0 then
    return NEW;
  end if;

  begin
    insert into public.ai_operator_channel_events(
      channel,
      provider,
      external_event_id,
      external_thread_key,
      direction,
      payload,
      status
    ) values (
      'whatsapp',
      v_provider,
      NEW.id::text,
      NEW.phone_normalized,
      'inbound',
      jsonb_build_object(
        'whatsapp_message_id', NEW.id,
        'message_type', NEW.message_type,
        'body', NEW.body,
        'media_url', NEW.media_url,
        'client_id', NEW.client_id,
        'lead_id', NEW.lead_id,
        'zapi_message_id', NEW.zapi_message_id
      ),
      'queued'
    )
    on conflict (provider, external_event_id) do nothing;
  exception when others then
    -- Nunca falhar a inserção da mensagem original por causa do AI Operator
    raise warning 'ai_operator_enqueue_whatsapp_message failed: %', sqlerrm;
  end;

  return NEW;
end;
$$;

drop trigger if exists trg_whatsapp_messages_to_ai_operator on public.whatsapp_messages;
create trigger trg_whatsapp_messages_to_ai_operator
  after insert on public.whatsapp_messages
  for each row
  execute function public.ai_operator_enqueue_whatsapp_message();

comment on function public.ai_operator_enqueue_whatsapp_message() is
  'Bridge passiva: enfileira mensagens WhatsApp inbound em ai_operator_channel_events para processamento futuro pelo AI Operator. NÃO dispara resposta automática.';
