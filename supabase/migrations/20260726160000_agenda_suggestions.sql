-- Agenda Autônoma — Fase 9: Caixa de Entrada de sugestões
-- Plano: plans/marineflow-agenda-autonoma.md
--
-- Princípio SUGERIR ≫ CRIAR: o detector NUNCA cria tarefa direto. Ele propõe, com a
-- FRASE ORIGINAL que gerou a proposta (evidência — mata alucinação e deixa o humano
-- decidir em 1 segundo). Aceitar/descartar alimenta a calibração da Fase 11.

CREATE TABLE public.agenda_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- O que a IA propõe
  title text NOT NULL,
  kind text NOT NULL DEFAULT 'task' CHECK (kind IN ('task','appointment')),
  suggested_due_at timestamptz,
  suggested_start_at timestamptz,
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),

  -- Por que ela propõe (obrigatório): trecho literal da conversa
  evidence text NOT NULL,
  evidence_at timestamptz,
  confidence numeric NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  detector text NOT NULL CHECK (detector IN ('promise','client_request','third_party_deadline','followup','voice_note')),

  -- De onde veio
  origin text NOT NULL DEFAULT 'whatsapp' CHECK (origin IN ('whatsapp','voice_app','manual_text')),
  source_message_id uuid REFERENCES public.whatsapp_messages(id) ON DELETE SET NULL,
  source_phone text,
  contact_label text,

  -- Vínculo com o ERP já resolvido pelo detector, quando dá
  related_entity_type text CHECK (related_entity_type IS NULL OR related_entity_type IN (
    'service_order','quote','external_quote','client','vessel',
    'receivable','payable','purchase_order','collection','stock_item')),
  related_entity_id uuid,
  client_id uuid REFERENCES public.clients(id) ON DELETE SET NULL,

  -- Para quem é a caixa de entrada (piloto: só o dono)
  target_user_id uuid REFERENCES public.app_users(id) ON DELETE CASCADE,

  -- Ciclo de vida
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','dismissed','expired')),
  resolved_at timestamptz,
  resolved_by uuid REFERENCES public.app_users(id),
  created_task_id uuid REFERENCES public.agenda_tasks(id) ON DELETE SET NULL,
  dismiss_reason text,

  created_at timestamptz NOT NULL DEFAULT now()
);

-- Uma sugestão viva por mensagem+título (o detector pode rodar de novo sobre a mesma janela)
CREATE UNIQUE INDEX agenda_suggestions_dedupe
  ON public.agenda_suggestions (source_message_id, md5(title))
  WHERE source_message_id IS NOT NULL AND status = 'pending';
CREATE INDEX agenda_suggestions_pending
  ON public.agenda_suggestions (target_user_id, created_at DESC) WHERE status = 'pending';
CREATE INDEX agenda_suggestions_detector_stats
  ON public.agenda_suggestions (detector, status);

ALTER TABLE public.agenda_suggestions ENABLE ROW LEVEL SECURITY;
-- Leitura/resolução pelo destinatário e por admin; escrita do detector é service-role
CREATE POLICY agenda_suggestions_select ON public.agenda_suggestions FOR SELECT
  USING (
    auth.uid() IS NOT NULL AND (
      target_user_id IS NULL
      OR target_user_id = auth.uid()
      OR EXISTS (SELECT 1 FROM public.app_users u
                  WHERE u.id = auth.uid() AND u.role = 'admin' AND u.active)
    )
  );
CREATE POLICY agenda_suggestions_update ON public.agenda_suggestions FOR UPDATE
  USING (
    auth.uid() IS NOT NULL AND (
      target_user_id IS NULL
      OR target_user_id = auth.uid()
      OR EXISTS (SELECT 1 FROM public.app_users u
                  WHERE u.id = auth.uid() AND u.role = 'admin' AND u.active)
    )
  ) WITH CHECK (auth.uid() IS NOT NULL);

-- Contatos que o detector NUNCA deve ler (decisão do usuário: escopo é todas as
-- conversas da HBR, com escape hatch por contato).
CREATE TABLE public.agenda_detector_exclusions (
  phone_normalized text PRIMARY KEY,
  label text,
  reason text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.agenda_detector_exclusions ENABLE ROW LEVEL SECURITY;
CREATE POLICY agenda_detector_exclusions_all ON public.agenda_detector_exclusions
  FOR ALL USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
