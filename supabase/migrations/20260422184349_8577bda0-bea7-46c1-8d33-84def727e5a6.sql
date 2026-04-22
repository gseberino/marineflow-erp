CREATE TABLE public.agenda_tasks (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  technician_user_id UUID NOT NULL REFERENCES public.app_users(id) ON DELETE CASCADE,
  scheduled_start_at TIMESTAMPTZ NOT NULL,
  scheduled_end_at TIMESTAMPTZ,
  priority TEXT NOT NULL DEFAULT 'normal',
  status TEXT NOT NULL DEFAULT 'pending',
  location TEXT,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  notes TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.agenda_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_all_agenda_tasks"
  ON public.agenda_tasks FOR ALL
  TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE INDEX agenda_tasks_tech_start_idx
  ON public.agenda_tasks (technician_user_id, scheduled_start_at);

CREATE INDEX agenda_tasks_start_idx
  ON public.agenda_tasks (scheduled_start_at);

CREATE TRIGGER update_agenda_tasks_updated_at
  BEFORE UPDATE ON public.agenda_tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();