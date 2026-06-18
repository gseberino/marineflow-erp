import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Progress } from '@/components/ui/progress';
import {
  Loader2, Send, AlertTriangle, Pause, Play, X, CalendarClock, CheckCircle2, XCircle,
} from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useReceivables } from '@/hooks/use-financial';
import { useClients } from '@/hooks/use-clients';
import { normalizePhoneE164 } from '@/lib/masks';
import { useWhatsAppTemplates, applyTemplateVariables } from '@/hooks/use-whatsapp-templates';
import { useI18n } from '@/i18n';
import { useQueryClient } from '@tanstack/react-query';
import { useCreateScheduledSend } from '@/hooks/use-scheduled-sends';
import {
  ScheduleSettings, defaultScheduleConfig, type ScheduleConfig,
} from '@/components/zapi/ScheduleSettings';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  /** Filtro inicial: 'overdue' (vencidas) ou 'upcoming' (vence em N dias) */
  initialFilter?: 'overdue' | 'upcoming' | 'all';
  /** Janela em dias para "upcoming" */
  upcomingDays?: number;
}

type RowStatus = 'queued' | 'sending' | 'ok' | 'fail' | 'skipped';
interface RowProgress {
  id: string;
  status: RowStatus;
  attempts: number;
  error?: string;
}

const THROTTLE_KEY = 'zapi.bulk.throttleMs';
const MAX_ATTEMPTS_KEY = 'zapi.bulk.maxAttempts';

export function BulkBillingReminderDialog({
  open,
  onOpenChange,
  initialFilter = 'overdue',
  upcomingDays = 7,
}: Props) {
  const { data: receivables } = useReceivables();
  const { data: clients } = useClients();
  const { data: templates } = useWhatsAppTemplates('billing');
  const { formatCurrency, formatDate } = useI18n();
  const queryClient = useQueryClient();
  const createScheduled = useCreateScheduledSend();

  const [filter, setFilter] = useState<'overdue' | 'upcoming' | 'all'>(initialFilter);
  const [templateId, setTemplateId] = useState<string>('');
  const [customMessage, setCustomMessage] = useState<string>('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  // Throttle (ms) e retry
  const [throttleMs, setThrottleMs] = useState<number>(() => {
    try {
      const v = parseInt(localStorage.getItem(THROTTLE_KEY) || '2500', 10);
      return Number.isFinite(v) && v >= 500 && v <= 60000 ? v : 2500;
    } catch { return 2500; }
  });
  const [maxAttempts, setMaxAttempts] = useState<number>(() => {
    try {
      const v = parseInt(localStorage.getItem(MAX_ATTEMPTS_KEY) || '3', 10);
      return Number.isFinite(v) && v >= 1 && v <= 5 ? v : 3;
    } catch { return 3; }
  });

  useEffect(() => {
    try { localStorage.setItem(THROTTLE_KEY, String(throttleMs)); } catch {}
  }, [throttleMs]);
  useEffect(() => {
    try { localStorage.setItem(MAX_ATTEMPTS_KEY, String(maxAttempts)); } catch {}
  }, [maxAttempts]);

  // Estado de execução
  const [running, setRunning] = useState(false);
  const [paused, setPaused] = useState(false);
  const [progress, setProgress] = useState<Record<string, RowProgress>>({});
  const cancelRef = useRef(false);
  const pauseRef = useRef(false);

  // Agendamento opcional do lote
  const [schedule, setSchedule] = useState<ScheduleConfig>(defaultScheduleConfig());

  const clientById = useMemo(() => {
    const m = new Map<string, any>();
    (clients || []).forEach(c => m.set(c.id, c));
    return m;
  }, [clients]);

  const candidates = useMemo(() => {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const limitUpcoming = new Date(today); limitUpcoming.setDate(limitUpcoming.getDate() + upcomingDays);
    return (receivables || [])
      .filter((r: any) => r.status !== 'paid' && r.status !== 'cancelled')
      .filter((r: any) => {
        const due = new Date(r.due_date); due.setHours(0, 0, 0, 0);
        if (filter === 'overdue') return due < today;
        if (filter === 'upcoming') return due >= today && due <= limitUpcoming;
        return true;
      })
      .map((r: any) => {
        const client = clientById.get(r.client_id);
        const phoneRaw = client?.whatsapp || client?.phone || '';
        return {
          ...r,
          client_name: client?.name || 'Cliente',
          phone_normalized: normalizePhoneE164(phoneRaw),
          has_phone: !!normalizePhoneE164(phoneRaw),
        };
      });
  }, [receivables, clientById, filter, upcomingDays]);

  const eligible = candidates.filter(c => c.has_phone);

  // Template default ao abrir / quando mudar filtro
  useEffect(() => {
    if (!templates?.length || templateId) return;
    const preferKey = filter === 'overdue' ? 'vencida' : 'lembrete';
    const t = templates.find(x => x.name.toLowerCase().includes(preferKey)) || templates[0];
    if (t) { setTemplateId(t.id); setCustomMessage(t.body); }
  }, [templates, filter, templateId]);

  // Reset ao fechar
  useEffect(() => {
    if (!open) {
      cancelRef.current = false;
      pauseRef.current = false;
      setRunning(false);
      setPaused(false);
      setProgress({});
      setSchedule(defaultScheduleConfig());
    }
  }, [open]);

  const handleTemplateChange = (id: string) => {
    setTemplateId(id);
    const tpl = templates?.find(x => x.id === id);
    if (tpl) setCustomMessage(tpl.body);
  };

  const toggleAll = () => {
    if (selectedIds.size === eligible.length) setSelectedIds(new Set());
    else setSelectedIds(new Set(eligible.map(e => e.id)));
  };

  const renderForReceivable = (r: any) => applyTemplateVariables(customMessage, {
    cliente: r.client_name,
    descricao: r.description,
    valor: formatCurrency(Number(r.balance_amount ?? r.amount)),
    vencimento: formatDate(r.due_date),
    os: r.service_order_id ? `(OS vinculada)` : '',
    link: '',
  });

  // Helpers para pausar/cancelar dentro do loop
  async function waitWhilePaused() {
    while (pauseRef.current && !cancelRef.current) {
      await new Promise(r => setTimeout(r, 250));
    }
  }
  async function sleep(ms: number) {
    const step = 100;
    let elapsed = 0;
    while (elapsed < ms) {
      if (cancelRef.current) return;
      await waitWhilePaused();
      await new Promise(r => setTimeout(r, step));
      elapsed += step;
    }
  }

  function updateRow(id: string, patch: Partial<RowProgress>) {
    setProgress(prev => ({ ...prev, [id]: { ...(prev[id] || { id, status: 'queued', attempts: 0 }), ...patch, id } }));
  }

  async function sendOneWithRetry(r: any): Promise<boolean> {
    for (let attempt = 1; attempt <= Math.max(1, maxAttempts); attempt++) {
      if (cancelRef.current) return false;
      await waitWhilePaused();
      updateRow(r.id, { status: 'sending', attempts: attempt });
      try {
        const { data, error } = await supabase.functions.invoke('whatsapp-send', {
          body: {
            phone: r.phone_normalized,
            kind: 'text',
            message: renderForReceivable(r),
            receivable_id: r.id,
            service_order_id: r.service_order_id || undefined,
            context: 'billing_bulk',
            attempt,
          },
        });
        if (error || (data as any)?.error) {
          throw new Error((data as any)?.error || error?.message || 'Falha desconhecida');
        }
        updateRow(r.id, { status: 'ok' });
        return true;
      } catch (e: any) {
        const msg = e?.message || 'Erro';
        updateRow(r.id, { status: attempt < maxAttempts ? 'sending' : 'fail', error: msg });
        if (attempt < maxAttempts) {
          // Backoff exponencial entre tentativas (1s, 2s, 4s…)
          const delay = Math.min(8000, 1000 * Math.pow(2, attempt - 1));
          await sleep(delay);
        }
      }
    }
    return false;
  }

  // ============ Agendamento em lote ============
  async function handleScheduleBatch() {
    if (!selectedIds.size) { toast.error('Selecione ao menos uma cobrança.'); return; }
    const scheduledIso = new Date(schedule.scheduledAt).toISOString();
    if (new Date(scheduledIso).getTime() <= Date.now()) {
      toast.error('Escolha uma data/hora futura.');
      return;
    }
    const tId = toast.loading(`Agendando ${selectedIds.size} envio(s)…`);
    let ok = 0, fail = 0;
    for (const id of selectedIds) {
      const r = eligible.find(e => e.id === id);
      if (!r) continue;
      try {
        await createScheduled.mutateAsync({
          target_kind: 'receivable',
          receivable_id: r.id,
          service_order_id: r.service_order_id || null,
          client_id: r.client_id,
          phone: r.phone_normalized,
          message: renderForReceivable(r),
          send_mode: 'text',
          context: 'billing',
          scheduled_at: scheduledIso,
          recurrence_type: schedule.recurrenceType,
          recurrence_days_of_week:
            schedule.recurrenceType === 'weekly' ? schedule.daysOfWeek : undefined,
          recurrence_day_of_month:
            schedule.recurrenceType === 'monthly' ? schedule.dayOfMonth : undefined,
          recurrence_end_date: schedule.endDate
            ? new Date(schedule.endDate).toISOString()
            : null,
          auto_retry: true,
          max_attempts: maxAttempts,
        });
        ok++;
      } catch (e) {
        console.error('schedule bulk error', r.id, e);
        fail++;
      }
    }
    toast.success(`${ok} agendamento(s) criado(s)${fail ? `, ${fail} falha(s)` : ''}.`, { id: tId });
    if (!fail) onOpenChange(false);
  }

  // ============ Envio imediato com throttle ============
  async function handleSendNow() {
    if (!selectedIds.size) { toast.error('Selecione ao menos uma cobrança.'); return; }
    cancelRef.current = false;
    pauseRef.current = false;
    setPaused(false);
    setRunning(true);

    const queue = eligible.filter(e => selectedIds.has(e.id));
    const initial: Record<string, RowProgress> = {};
    queue.forEach(r => { initial[r.id] = { id: r.id, status: 'queued', attempts: 0 }; });
    setProgress(initial);

    const tId = toast.loading(`Enviando 0 / ${queue.length}…`);
    let ok = 0, fail = 0;

    for (let i = 0; i < queue.length; i++) {
      if (cancelRef.current) break;
      await waitWhilePaused();
      const r = queue[i];
      const success = await sendOneWithRetry(r);
      if (success) ok++; else fail++;
      toast.loading(`Enviando ${i + 1} / ${queue.length} (${ok} ok, ${fail} falhas)…`, { id: tId });
      // Throttle entre envios
      if (i < queue.length - 1 && !cancelRef.current) {
        await sleep(throttleMs);
      }
    }

    setRunning(false);
    setPaused(false);
    pauseRef.current = false;

    if (cancelRef.current) {
      toast.warning(`Envio cancelado. ${ok} enviada(s), ${fail} falha(s).`, { id: tId });
    } else {
      toast.success(`Concluído: ${ok} enviada(s)${fail ? `, ${fail} falha(s)` : ''}.`, { id: tId });
    }

    queryClient.invalidateQueries({ queryKey: ['whatsapp-send-status'] });
    queryClient.invalidateQueries({ queryKey: ['whatsapp-send-history'] });

    if (!fail && !cancelRef.current) {
      // Pequeno delay para o usuário ver o estado final antes de fechar
      setTimeout(() => onOpenChange(false), 800);
    }
  }

  function handlePauseToggle() {
    pauseRef.current = !pauseRef.current;
    setPaused(pauseRef.current);
  }
  function handleCancel() {
    cancelRef.current = true;
    pauseRef.current = false;
    setPaused(false);
  }

  // ====== Resumo de progresso ======
  const totalSelected = selectedIds.size;
  const counts = useMemo(() => {
    const list = Object.values(progress);
    return {
      ok: list.filter(r => r.status === 'ok').length,
      fail: list.filter(r => r.status === 'fail').length,
      sending: list.filter(r => r.status === 'sending').length,
      done: list.filter(r => r.status === 'ok' || r.status === 'fail').length,
    };
  }, [progress]);
  const percent = totalSelected ? Math.round((counts.done / totalSelected) * 100) : 0;

  return (
    <Dialog open={open} onOpenChange={v => !running && onOpenChange(v)}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Send className="h-5 w-5" /> Cobrança em massa via WhatsApp
          </DialogTitle>
          <DialogDescription>
            Selecione cobranças e envie via Z-API com throttle, retry automático e progresso ao vivo.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4">
          <div className="flex flex-wrap items-center gap-2">
            <Label className="!mb-0">Filtro:</Label>
            <Button size="sm" variant={filter === 'overdue' ? 'default' : 'outline'} disabled={running} onClick={() => { setFilter('overdue'); setSelectedIds(new Set()); }}>Vencidas</Button>
            <Button size="sm" variant={filter === 'upcoming' ? 'default' : 'outline'} disabled={running} onClick={() => { setFilter('upcoming'); setSelectedIds(new Set()); }}>A vencer ({upcomingDays}d)</Button>
            <Button size="sm" variant={filter === 'all' ? 'default' : 'outline'} disabled={running} onClick={() => { setFilter('all'); setSelectedIds(new Set()); }}>Todas pendentes</Button>
          </div>

          <div>
            <Label>Template</Label>
            <select
              className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
              value={templateId}
              disabled={running}
              onChange={e => handleTemplateChange(e.target.value)}
            >
              <option value="">— selecionar —</option>
              {(templates || []).map(t => (
                <option key={t.id} value={t.id}>{t.name}</option>
              ))}
            </select>
          </div>

          <div>
            <Label>Mensagem (use placeholders)</Label>
            <Textarea rows={4} value={customMessage} disabled={running} onChange={e => setCustomMessage(e.target.value)} />
            <p className="text-xs text-muted-foreground mt-1">Placeholders: {'{cliente}'} {'{descricao}'} {'{valor}'} {'{vencimento}'}</p>
          </div>

          {/* Configurações de envio */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 p-3 rounded-lg border bg-muted/20">
            <div>
              <Label className="text-xs">Intervalo entre mensagens (ms)</Label>
              <Input
                type="number"
                min={500}
                max={60000}
                step={500}
                value={throttleMs}
                disabled={running}
                onChange={e => setThrottleMs(Math.max(500, Math.min(60000, parseInt(e.target.value || '2500', 10) || 2500)))}
              />
              <p className="text-[11px] text-muted-foreground mt-1">
                Recomendado: 2000–5000ms para evitar bloqueio Z-API.
              </p>
            </div>
            <div>
              <Label className="text-xs">Tentativas por mensagem</Label>
              <Input
                type="number"
                min={1}
                max={5}
                value={maxAttempts}
                disabled={running}
                onChange={e => setMaxAttempts(Math.max(1, Math.min(5, parseInt(e.target.value || '3', 10) || 3)))}
              />
              <p className="text-[11px] text-muted-foreground mt-1">
                Backoff exponencial entre tentativas (1s → 2s → 4s…).
              </p>
            </div>
          </div>

          {/* Lista de elegíveis */}
          <div className="border rounded-lg overflow-hidden">
            <div className="flex items-center justify-between px-3 py-2 bg-muted/30 border-b">
              <div className="flex items-center gap-2">
                <Checkbox
                  checked={selectedIds.size === eligible.length && eligible.length > 0}
                  onCheckedChange={toggleAll}
                  disabled={running}
                />
                <span className="text-sm font-medium">
                  {selectedIds.size} de {eligible.length} selecionada(s)
                </span>
              </div>
              {candidates.length > eligible.length && (
                <span className="text-xs text-amber-700 inline-flex items-center gap-1">
                  <AlertTriangle className="h-3 w-3" />
                  {candidates.length - eligible.length} sem telefone
                </span>
              )}
            </div>
            <div className="max-h-[40vh] overflow-y-auto divide-y">
              {eligible.length === 0 && (
                <p className="p-6 text-sm text-muted-foreground text-center">Nenhuma cobrança elegível.</p>
              )}
              {eligible.map(r => {
                const p = progress[r.id];
                return (
                  <label key={r.id} className="flex items-start gap-3 p-3 hover:bg-muted/30 cursor-pointer">
                    <Checkbox
                      checked={selectedIds.has(r.id)}
                      disabled={running}
                      onCheckedChange={v => {
                        const next = new Set(selectedIds);
                        if (v) next.add(r.id); else next.delete(r.id);
                        setSelectedIds(next);
                      }}
                      className="mt-1"
                    />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2">
                        <p className="text-sm font-medium truncate">{r.client_name}</p>
                        {p && (
                          <span className="text-[11px] inline-flex items-center gap-1 shrink-0">
                            {p.status === 'ok' && <><CheckCircle2 className="h-3.5 w-3.5 text-success" /><span className="text-success">Enviado</span></>}
                            {p.status === 'fail' && <><XCircle className="h-3.5 w-3.5 text-destructive" /><span className="text-destructive">Falhou</span></>}
                            {p.status === 'sending' && <><Loader2 className="h-3.5 w-3.5 animate-spin" /><span className="text-muted-foreground">Tentativa {p.attempts}/{maxAttempts}</span></>}
                            {p.status === 'queued' && <span className="text-muted-foreground">Na fila</span>}
                          </span>
                        )}
                      </div>
                      <p className="text-xs text-muted-foreground truncate">{r.description}</p>
                      <p className="text-xs">
                        <span className="font-mono">{formatCurrency(Number(r.balance_amount ?? r.amount))}</span>
                        {' • '}
                        <span>{formatDate(r.due_date)}</span>
                        {' • '}
                        <span className="text-muted-foreground">{r.phone_normalized}</span>
                      </p>
                      {p?.error && p.status === 'fail' && (
                        <p className="text-[11px] text-destructive mt-1 truncate" title={p.error}>{p.error}</p>
                      )}
                    </div>
                  </label>
                );
              })}
            </div>
          </div>

          {/* Progresso */}
          {running || counts.done > 0 ? (
            <div className="space-y-2 p-3 rounded-lg border bg-muted/10">
              <div className="flex items-center justify-between text-sm">
                <span className="font-medium">
                  {counts.done} / {totalSelected} processadas
                </span>
                <span className="text-muted-foreground">
                  ✓ {counts.ok} • ✗ {counts.fail}{counts.sending ? ` • ⏳ ${counts.sending}` : ''}
                </span>
              </div>
              <Progress value={percent} />
              {running && (
                <div className="flex items-center gap-2 pt-1">
                  <Button size="sm" variant="outline" onClick={handlePauseToggle} className="gap-1">
                    {paused ? <><Play className="h-3.5 w-3.5" /> Retomar</> : <><Pause className="h-3.5 w-3.5" /> Pausar</>}
                  </Button>
                  <Button size="sm" variant="destructive" onClick={handleCancel} className="gap-1">
                    <X className="h-3.5 w-3.5" /> Cancelar
                  </Button>
                  {paused && <span className="text-xs text-warning">Pausado…</span>}
                </div>
              )}
            </div>
          ) : null}

          {/* Agendamento opcional do lote inteiro */}
          {!running && (
            <ScheduleSettings
              value={schedule}
              onChange={setSchedule}
              disabled={createScheduled.isPending}
            />
          )}
        </div>

        <DialogFooter className="gap-2 flex-wrap">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={running || createScheduled.isPending}>
            Fechar
          </Button>
          {schedule.enabled ? (
            <Button
              onClick={handleScheduleBatch}
              disabled={running || createScheduled.isPending || !selectedIds.size}
              className="gap-2"
            >
              {createScheduled.isPending
                ? <Loader2 className="h-4 w-4 animate-spin" />
                : <CalendarClock className="h-4 w-4" />}
              Agendar lote ({selectedIds.size})
            </Button>
          ) : (
            <Button
              onClick={handleSendNow}
              disabled={running || !selectedIds.size}
              className="gap-2"
            >
              {running ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
              Enviar agora ({selectedIds.size})
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
