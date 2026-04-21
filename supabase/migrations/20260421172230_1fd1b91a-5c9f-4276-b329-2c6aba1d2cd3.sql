ALTER TABLE public.audit_log DROP CONSTRAINT IF EXISTS audit_log_action_check;
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_action_check
  CHECK (action = ANY (ARRAY[
    'update','cancel','reopen','reversal','cascade_update',
    'client_signature','whatsapp_send','whatsapp_send_api','whatsapp_received',
    'lead_created','lead_matched','lead_converted'
  ]));