-- Agenda & Tarefas 2.0 — Fase 8: planos de manutenção recorrente por embarcação
-- (padrão "memberships" do ServiceTitan, dimensionado para a HBR).
-- O motor (R14) cria a tarefa "Propor revisão" quando o plano entra na janela;
-- registrar novo serviço (last_service_at) ou desativar o plano auto-resolve.
CREATE TABLE public.maintenance_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vessel_id uuid NOT NULL REFERENCES public.vessels(id) ON DELETE CASCADE,
  name text NOT NULL,
  interval_months integer NOT NULL CHECK (interval_months BETWEEN 1 AND 60),
  scope text,
  estimated_value numeric,
  last_service_at date,
  advance_days integer NOT NULL DEFAULT 14 CHECK (advance_days BETWEEN 0 AND 90),
  active boolean NOT NULL DEFAULT true,
  notes text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX maintenance_plans_vessel ON public.maintenance_plans (vessel_id);
CREATE INDEX maintenance_plans_active ON public.maintenance_plans (active) WHERE active;

ALTER TABLE public.maintenance_plans ENABLE ROW LEVEL SECURITY;
-- Paridade com o resto do sistema (allow-all autenticado; RLS fina é dívida global)
CREATE POLICY authenticated_all_maintenance_plans ON public.maintenance_plans
  FOR ALL USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
