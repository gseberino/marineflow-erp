CREATE TABLE public.client_whatsapp_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  context text NOT NULL CHECK (context IN ('service_order','quote','billing')),
  message_body text,
  link_title text,
  link_description text,
  pdf_filename_pattern text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (client_id, context)
);

ALTER TABLE public.client_whatsapp_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "client_whatsapp_settings_all_auth"
  ON public.client_whatsapp_settings
  FOR ALL
  TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE INDEX idx_client_whatsapp_settings_client ON public.client_whatsapp_settings(client_id);

CREATE TRIGGER update_client_whatsapp_settings_updated_at
  BEFORE UPDATE ON public.client_whatsapp_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();