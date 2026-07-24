import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Card } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Cog, AlertTriangle, ListChecks, X } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';

/** Modelos de checklist por tipo de serviço (app_settings.task_checklist_templates). */
function ChecklistTemplatesEditor() {
  const qc = useQueryClient();
  const [draft, setDraft] = useState('');
  const { data: templates = [] } = useQuery({
    queryKey: ['task-checklist-templates'],
    queryFn: async () => {
      const { data } = await supabase.from('app_settings')
        .select('value').eq('key', 'task_checklist_templates').maybeSingle();
      try {
        const parsed = JSON.parse((data as any)?.value || '[]');
        return Array.isArray(parsed) ? parsed as { name: string; items: string[] }[] : [];
      } catch { return []; }
    },
  });

  const save = useMutation({
    mutationFn: async (next: { name: string; items: string[] }[]) => {
      const { error } = await supabase.from('app_settings').upsert(
        { key: 'task_checklist_templates', value: JSON.stringify(next) },
        { onConflict: 'key' },
      );
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['task-checklist-templates'] }),
    onError: (e: any) => toast.error(e?.message || 'Erro ao salvar'),
  });

  const addTemplate = () => {
    // Formato: "Nome do modelo: item 1; item 2; item 3"
    const [name, rest] = draft.split(':');
    const items = (rest || '').split(';').map((s) => s.trim()).filter(Boolean);
    if (!name?.trim() || items.length === 0) {
      toast.error('Use o formato "Nome: item 1; item 2; item 3"');
      return;
    }
    save.mutate([...templates.filter((t) => t.name !== name.trim()), { name: name.trim(), items }]);
    setDraft('');
  };

  return (
    <div className="rounded-md border p-3 space-y-2">
      <p className="text-sm font-medium flex items-center gap-1.5">
        <ListChecks className="h-4 w-4 text-primary" /> Modelos de checklist
      </p>
      <p className="text-xs text-muted-foreground">
        Aplicáveis em qualquer tarefa pelo dialog. Formato: <code>Revisão de motor: óleo; filtros; correia; teste</code>
      </p>
      {templates.map((t) => (
        <div key={t.name} className="flex items-center justify-between text-xs bg-muted/40 rounded px-2 py-1">
          <span><b>{t.name}</b> — {t.items.join(' · ')}</span>
          <Button size="icon" variant="ghost" className="h-5 w-5"
            onClick={() => save.mutate(templates.filter((x) => x.name !== t.name))}>
            <X className="h-3 w-3" />
          </Button>
        </div>
      ))}
      <div className="flex gap-2">
        <Input value={draft} onChange={(e) => setDraft(e.target.value)} className="h-8 text-xs"
          placeholder="Nome: item 1; item 2; item 3"
          onKeyDown={(e) => { if (e.key === 'Enter') addTemplate(); }} />
        <Button size="sm" variant="outline" onClick={addTemplate} disabled={save.isPending}>Adicionar</Button>
      </div>
    </div>
  );
}

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
  { id: 'r14', label: 'Plano de manutenção vencendo', description: 'Tarefa "Propor revisão" quando um plano de manutenção da embarcação entra na janela.', defaultEnabled: true },
  { id: 'r10', label: 'Lembrete interno de OS (equipe)', description: 'WhatsApp interno ao técnico na véspera da OS agendada (só usuários com canal IA habilitado).', defaultEnabled: true },
  { id: 'r9', label: 'Lembrete de agendamento ao CLIENTE', description: 'WhatsApp ao cliente na véspera do atendimento. Envia mensagem real a clientes — ative com cuidado (respeita o modo de teste).', defaultEnabled: false, clientFacing: true },
  { id: 'r13', label: 'Pesquisa pós-serviço ao CLIENTE', description: 'No dia seguinte à conclusão da OS, pergunta ao cliente como foi (nota 0-10) por WhatsApp. Envia a clientes — respeita o modo de teste.', defaultEnabled: false, clientFacing: true },
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
      <ChecklistTemplatesEditor />
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
