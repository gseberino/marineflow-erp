import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Card } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { Cog, AlertTriangle } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';

// Espelha RULES de supabase/functions/task-automations/rules.ts (+ R9/R10 do motor)
const RULE_DEFS: { id: string; label: string; description: string; defaultEnabled: boolean; clientFacing?: boolean }[] = [
  { id: 'r1', label: 'OS aprovada sem agendamento', description: 'Cria tarefa "Agendar OS" quando uma OS aprovada fica 24h sem data.', defaultEnabled: true },
  { id: 'r2', label: 'OS parada', description: 'Cria tarefa quando uma OS em andamento fica 3 dias sem atualização.', defaultEnabled: true },
  { id: 'r3', label: 'Recebível vencendo (D-3)', description: 'Cria tarefa de cobrança para o financeiro; some sozinha quando o pagamento é registrado.', defaultEnabled: true },
  { id: 'r4', label: 'Recebível vencido', description: 'Tarefa urgente de cobrança para recebíveis em atraso.', defaultEnabled: true },
  { id: 'r5', label: 'Pagável vencendo (D-1)', description: 'Tarefa "Pagar fornecedor" na véspera do vencimento.', defaultEnabled: true },
  { id: 'r6', label: 'Orçamento sem resposta', description: 'Follow-up interno quando um orçamento enviado fica 3 dias sem resposta.', defaultEnabled: true },
  { id: 'r7', label: 'OC não recebida', description: 'Tarefa "Cobrar entrega" quando a ordem de compra passa do prazo.', defaultEnabled: true },
  { id: 'r8', label: 'Estoque abaixo do mínimo', description: 'Tarefa "Repor produto" enquanto o estoque estiver abaixo do mínimo.', defaultEnabled: true },
  { id: 'r11', label: 'Nota fiscal com pendência', description: 'Tarefa para o financeiro quando uma NF fica com erro/rejeitada.', defaultEnabled: true },
  { id: 'r12', label: 'Orçamento externo aguardando análise', description: 'Tarefa quando um orçamento submetido fica 2 dias sem análise.', defaultEnabled: true },
  { id: 'r10', label: 'Lembrete interno de OS (equipe)', description: 'WhatsApp interno ao técnico na véspera da OS agendada (só usuários com canal IA habilitado).', defaultEnabled: true },
  { id: 'r9', label: 'Lembrete de agendamento ao CLIENTE', description: 'WhatsApp ao cliente na véspera do atendimento. Envia mensagem real a clientes — ative com cuidado (respeita o modo de teste).', defaultEnabled: false, clientFacing: true },
];

export function TaskAutomationSettings() {
  const qc = useQueryClient();
  const { data: settings = {} } = useQuery({
    queryKey: ['task-automation-settings'],
    queryFn: async () => {
      const { data } = await supabase
        .from('app_settings')
        .select('key, value')
        .like('key', 'task_rule_%');
      return Object.fromEntries((data || []).map((s: any) => [s.key, s.value]));
    },
  });

  const toggle = useMutation({
    mutationFn: async ({ id, enabled }: { id: string; enabled: boolean }) => {
      const { error } = await supabase.from('app_settings').upsert(
        { key: `task_rule_${id}_enabled`, value: String(enabled) },
        { onConflict: 'key' },
      );
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['task-automation-settings'] }),
    onError: (e: any) => toast.error(e?.message || 'Erro ao salvar'),
  });

  const isEnabled = (def: (typeof RULE_DEFS)[number]) => {
    const v = (settings as Record<string, string>)[`task_rule_${def.id}_enabled`];
    if (v === undefined || v === '') return def.defaultEnabled;
    return v === 'true';
  };

  return (
    <Card className="p-5 space-y-4">
      <div className="flex items-center gap-2">
        <Cog className="h-5 w-5 text-primary" />
        <div>
          <h3 className="font-semibold text-sm">Automações de tarefas</h3>
          <p className="text-xs text-muted-foreground">
            O motor roda a cada 15 min: cria tarefas quando algo precisa de ação e as conclui sozinho quando a pendência se resolve.
          </p>
        </div>
      </div>
      <div className="space-y-3">
        {RULE_DEFS.map((def) => (
          <div key={def.id} className="flex items-start justify-between gap-4">
            <div className="min-w-0">
              <p className="text-sm font-medium flex items-center gap-1.5">
                {def.label}
                {def.clientFacing && <AlertTriangle className="h-3.5 w-3.5 text-amber-500" />}
              </p>
              <p className="text-xs text-muted-foreground">{def.description}</p>
            </div>
            <Switch
              checked={isEnabled(def)}
              onCheckedChange={(v) => toggle.mutate({ id: def.id, enabled: v })}
            />
          </div>
        ))}
      </div>
    </Card>
  );
}
