import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Card } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Cog, ListChecks, X, Wrench } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { CHAVE_CAMPANHA_TEMPORADA, CHAVE_LEMBRETES_REVISAO } from '@/hooks/use-planos-manutencao';
import { interruptorLigado } from '@/lib/planos-manutencao';

/**
 * Lembretes de revisão (07/10/2026). Decisão do dono: mensagem ao cliente sai SEMPRE com o "sim"
 * dele — o sistema prepara e pergunta no WhatsApp do dono. Por isso ligar não pede confirmação:
 * nada sai sozinho. Padrão 'on' (sem a chave = ligado), igual à função lembretes-de-revisao que lê
 * estas chaves.
 */
const INTERRUPTORES_DE_REVISAO = [
  {
    chave: CHAVE_LEMBRETES_REVISAO,
    label: 'Lembretes de revisão ao cliente (com seu sim)',
    description: 'De terça a quinta, às 9h05: para cada plano 21 dias antes do vencimento, 7 dias antes (se o cliente não respondeu) e 14 dias depois (se não respondeu e não há OS agendada), o sistema monta a mensagem e pergunta a você no WhatsApp "posso mandar?". No máximo 3 por vencimento; quem respondeu PARAR não recebe mais.',
  },
  {
    chave: CHAVE_CAMPANHA_TEMPORADA,
    label: 'Campanha de temporada set–out (com seu sim)',
    description: 'Entre 15/09 e 31/10, uma mensagem por cliente com serviço concluído e sem revisão vencendo de outubro a dezembro, oferecendo deixar a parte elétrica conferida antes do verão. Também só sai com o seu sim.',
  },
];

function RevisoesSettings() {
  const qc = useQueryClient();
  const { data: valores = {}, error } = useQuery({
    queryKey: ['revisoes-settings'],
    queryFn: async () => {
      const { data, error: e } = await supabase.from('app_settings').select('key, value')
        .in('key', INTERRUPTORES_DE_REVISAO.map((i) => i.chave));
      if (e) throw e;
      return Object.fromEntries((data || []).map((s: any) => [s.key, s.value])) as Record<string, string>;
    },
  });
  const salvar = useMutation({
    mutationFn: async ({ chave, ligado }: { chave: string; ligado: boolean }) => {
      const { error: e } = await supabase.from('app_settings').upsert(
        { key: chave, value: ligado ? 'on' : 'off' },
        { onConflict: 'key' },
      );
      if (e) throw e;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['revisoes-settings'] }),
    onError: (e: any) => toast.error(e?.message || 'Erro ao salvar'),
  });

  return (
    <div className="rounded-md border p-3 space-y-3">
      <p className="text-sm font-medium flex items-center gap-1.5">
        <Wrench className="h-4 w-4 text-primary" /> Revisões (planos de manutenção)
      </p>
      {error && <p className="text-xs text-destructive">Não deu para ler estes interruptores: {(error as Error).message}</p>}
      {INTERRUPTORES_DE_REVISAO.map((i) => (
        <div key={i.chave} className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <p className="text-sm font-medium">{i.label}</p>
            <p className="text-xs text-muted-foreground">{i.description}</p>
          </div>
          <Switch
            aria-label={i.label}
            checked={interruptorLigado(valores[i.chave])}
            disabled={!!error}
            onCheckedChange={(v) => salvar.mutate({ chave: i.chave, ligado: v })}
          />
        </div>
      ))}
    </div>
  );
}

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
          <Button aria-label="Remover este modelo de checklist" size="icon" variant="ghost" className="h-5 w-5"
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

// Espelha RULES de supabase/functions/task-automations/rules.ts (+ R10 do motor). Nenhuma regra daqui
// manda mensagem a cliente: R9 (lembrete automático de agendamento) e R13 (pesquisa pós-serviço)
// foram aposentadas em 23/10/2026 (decisão d13), e com elas o diálogo "digite LIGAR" que as guardava.
const RULE_DEFS: { id: string; label: string; description: string; defaultEnabled: boolean }[] = [
  { id: 'r1', label: 'OS aprovada sem agendamento', description: 'Cria tarefa "Agendar OS" quando uma OS aprovada ou aberta fica 24h sem data. Orçamento aprovado ainda sem sinal vira "receber o sinal e converter para agendar", com o botão "Abrir orçamento".', defaultEnabled: true },
  { id: 'r2', label: 'OS parada', description: 'Cria tarefa quando uma OS em andamento fica 3 dias sem atualização.', defaultEnabled: true },
  { id: 'r3', label: 'Recebível vencendo (D-3)', description: 'Cria tarefa de cobrança para o financeiro; some sozinha quando o pagamento é registrado.', defaultEnabled: true },
  { id: 'r4', label: 'Recebível vencido', description: 'Tarefa urgente de cobrança para recebíveis em atraso.', defaultEnabled: true },
  { id: 'r5', label: 'Pagável vencendo (D-1)', description: 'Tarefa "Pagar fornecedor" na véspera do vencimento.', defaultEnabled: true },
  { id: 'r6', label: 'Orçamento sem resposta', description: 'Follow-up interno quando um orçamento enviado fica 3 dias sem resposta.', defaultEnabled: true },
  { id: 'r19', label: 'Orçamento vencido: renovar ou rejeitar?', description: 'Tarefa quando um orçamento enviado ou aguardando aprovação passa da validade — a mesma data "até" impressa no PDF, no calendário de Brasília. Nada é rejeitado sozinho: você renova a validade no orçamento (a tarefa fecha sozinha) ou marca como rejeitado. Orçamento aprovado aguardando sinal nunca entra. Substitui a rejeição automática, que em setembro/2026 rejeitou R$ 133 mil em orçamentos sem avisar.', defaultEnabled: true },
  { id: 'r7', label: 'OC não recebida', description: 'Tarefa "Cobrar entrega" quando a ordem de compra passa do prazo. OC de OS concluída, faturada ou cancelada não é cobrada (e a tarefa dela fecha sozinha).', defaultEnabled: true },
  { id: 'r8', label: 'Estoque abaixo do mínimo', description: 'Tarefa "Repor produto" enquanto o estoque estiver abaixo do mínimo.', defaultEnabled: true },
  { id: 'r11', label: 'Nota fiscal com pendência', description: 'Tarefa para o financeiro quando uma NF fica com erro/rejeitada.', defaultEnabled: true },
  { id: 'r12', label: 'Orçamento externo aguardando análise', description: 'Tarefa quando um orçamento submetido fica 2 dias sem análise.', defaultEnabled: true },
  { id: 'r14', label: 'Plano de manutenção vencendo', description: 'Tarefa "Propor revisão: plano — embarcação ou veículo" quando o plano entra na janela (21 dias antes do vencimento), com escopo, valor estimado e último serviço nas notas. Fecha sozinha quando o serviço é registrado (OS concluída que casa com o plano, ou "Serviço feito"), quando o plano é adiado ou desligado. Os lembretes ao cliente são outra coisa: ficam logo abaixo, em Revisões.', defaultEnabled: true },
  { id: 'r18', label: 'Cotação criada e não enviada', description: 'Tarefa "Enviar a cotação" quando ela tem fornecedor escolhido mas o pedido nunca saiu. Existe por um caso real: três cotações ficaram 11 dias exibindo "enviada" sem que nenhuma mensagem tivesse sido despachada. Fecha sozinha assim que o envio acontece.', defaultEnabled: true },
  { id: 'r17', label: 'Cotação sem resposta do fornecedor', description: 'Tarefa "Cobrar resposta" quando uma cotação passa de 3 dias úteis do ENVIO sem nenhum preço registrado (a janela normal de resposta é de 3 a 5 dias úteis). Só vale para cotação de fato enviada — sem envio, quem tem pendência é você, e isso vira a tarefa acima. Some sozinha quando alguém responde ou a cotação é fechada. Nada é enviado ao fornecedor sem você mandar.', defaultEnabled: true },
  { id: 'r16', label: 'OS comprometida com item a comprar', description: 'Uma tarefa por OS (aprovada, aberta, agendada, em andamento ou aguardando peças, e também o orçamento aprovado ainda sem sinal) quando falta material para executar — conta o disponível (físico menos reservado) e desconta o que já está em ordem de compra aberta. É a rede do aviso que aparece na aprovação do orçamento: se você clicar em "Depois", a pendência volta aqui. Fecha sozinha quando a peça entra ou o pedido é feito.', defaultEnabled: true },
  { id: 'r10', label: 'Lembrete interno de OS (equipe)', description: 'WhatsApp interno ao técnico na véspera da OS agendada (só usuários com canal IA habilitado).', defaultEnabled: true },
  { id: 'r15', label: 'Confirmar agendamento com o cliente', description: 'Cria uma TAREFA sua na véspera ("confirmar com fulano o atendimento de amanhã"). Não envia nada sozinho: você dispara pelo botão "Pedir confirmação" no cartão da tarefa, um a um. Quando o cliente responde SIM, a OS fica confirmada e a tarefa se fecha sozinha. Substitui o envio automático ao cliente na véspera, que foi aposentado.', defaultEnabled: true },
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
              <p className="text-sm font-medium">{def.label}</p>
              <p className="text-xs text-muted-foreground">{def.description}</p>
            </div>
            <Switch
              checked={isEnabled(def)}
              aria-label={def.label}
              onCheckedChange={(v) => toggle.mutate({ id: def.id, enabled: v })}
            />
          </div>
        ))}
      </div>

      <RevisoesSettings />
    </Card>
  );
}
