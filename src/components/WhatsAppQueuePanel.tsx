import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { ScrollArea } from '@/components/ui/scroll-area';
import { toast } from '@/hooks/use-toast';
import { Gauge, Play, RefreshCw, Trash2, ShieldAlert } from 'lucide-react';
import { format } from 'date-fns';

const KEYS = {
  enabled: 'whatsapp_queue_enabled',
  maxPerRun: 'whatsapp_queue_max_per_run',
  delayMs: 'whatsapp_queue_delay_ms',
  maxPerHour: 'whatsapp_queue_max_per_hour',
};

function statusBadge(s: string) {
  const map: Record<string, { variant: any; label: string }> = {
    pending: { variant: 'secondary', label: 'Aguardando' },
    sending: { variant: 'default', label: 'Enviando' },
    sent: { variant: 'default', label: 'Enviado' },
    failed: { variant: 'destructive', label: 'Falhou' },
  };
  const { variant, label } = map[s] || { variant: 'outline', label: s };
  return <Badge variant={variant} className="text-xs">{label}</Badge>;
}

export function WhatsAppQueuePanel() {
  const qc = useQueryClient();
  const [enabled, setEnabled] = useState(true);
  const [maxPerRun, setMaxPerRun] = useState('5');
  const [delayMs, setDelayMs] = useState('1500');
  const [maxPerHour, setMaxPerHour] = useState('60');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [running, setRunning] = useState(false);

  useEffect(() => {
    (async () => {
      const { data } = await supabase
        .from('app_settings')
        .select('key, value')
        .in('key', Object.values(KEYS));
      const map = Object.fromEntries((data || []).map((r: any) => [r.key, r.value]));
      setEnabled((map[KEYS.enabled] ?? 'true') === 'true');
      setMaxPerRun(map[KEYS.maxPerRun] || '5');
      setDelayMs(map[KEYS.delayMs] || '1500');
      setMaxPerHour(map[KEYS.maxPerHour] || '60');
      setLoading(false);
    })();
  }, []);

  const { data: queueItems, refetch } = useQuery({
    queryKey: ['wa-queue-items'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('whatsapp_send_queue')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(50);
      if (error) throw error;
      return data || [];
    },
    refetchInterval: 10000,
  });

  const { data: stats } = useQuery({
    queryKey: ['wa-queue-stats'],
    queryFn: async () => {
      const since = new Date(Date.now() - 60 * 60_000).toISOString();
      const [pending, sending, sentLastHour, failed] = await Promise.all([
        supabase.from('whatsapp_send_queue').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
        supabase.from('whatsapp_send_queue').select('id', { count: 'exact', head: true }).eq('status', 'sending'),
        supabase.from('whatsapp_send_queue').select('id', { count: 'exact', head: true }).eq('status', 'sent').gte('sent_at', since),
        supabase.from('whatsapp_send_queue').select('id', { count: 'exact', head: true }).eq('status', 'failed').gte('updated_at', since),
      ]);
      return {
        pending: pending.count || 0,
        sending: sending.count || 0,
        sentLastHour: sentLastHour.count || 0,
        failedLastHour: failed.count || 0,
      };
    },
    refetchInterval: 10000,
  });

  const persistEnabled = async (next: boolean) => {
    try {
      const { error } = await supabase.from('app_settings').upsert(
        { key: KEYS.enabled, value: next ? 'true' : 'false', description: 'Liga/desliga o worker da fila WhatsApp.' },
        { onConflict: 'key' },
      );
      if (error) throw error;
      setEnabled(next);
      toast({
        title: next ? 'Fila ATIVADA' : 'Fila PAUSADA',
        description: next ? 'O worker voltará a processar envios na próxima execução.' : 'Mensagens permanecem na fila mas não serão enviadas.',
        variant: next ? 'default' : 'destructive',
      });
    } catch (e: any) {
      toast({ title: 'Erro', description: e.message, variant: 'destructive' });
    }
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const rows = [
        { key: KEYS.maxPerRun, value: maxPerRun, description: 'Quantas mensagens o worker envia por execução.' },
        { key: KEYS.delayMs, value: delayMs, description: 'Delay entre envios consecutivos (ms).' },
        { key: KEYS.maxPerHour, value: maxPerHour, description: 'Limite global de envios por hora (rate limit).' },
      ];
      for (const r of rows) {
        const { error } = await supabase.from('app_settings').upsert(r, { onConflict: 'key' });
        if (error) throw error;
      }
      toast({ title: 'Configurações da fila salvas' });
    } catch (e: any) {
      toast({ title: 'Erro ao salvar', description: e.message, variant: 'destructive' });
    } finally {
      setSaving(false);
    }
  };

  const handleRunNow = async () => {
    setRunning(true);
    try {
      const { data, error } = await supabase.functions.invoke('whatsapp-queue-worker', { body: {} });
      if (error) throw error;
      toast({
        title: 'Worker executado',
        description: `Processadas: ${data?.processed ?? 0}. Restante hora: ${data?.remaining_hourly_after ?? '-'}.`,
      });
      qc.invalidateQueries({ queryKey: ['wa-queue-items'] });
      qc.invalidateQueries({ queryKey: ['wa-queue-stats'] });
    } catch (e: any) {
      toast({ title: 'Erro', description: e.message, variant: 'destructive' });
    } finally {
      setRunning(false);
    }
  };

  const purgeMutation = useMutation({
    mutationFn: async (filter: 'pending' | 'failed') => {
      const { error } = await supabase
        .from('whatsapp_send_queue')
        .delete()
        .eq('status', filter);
      if (error) throw error;
    },
    onSuccess: (_d, filter) => {
      toast({ title: `Itens "${filter}" removidos da fila` });
      qc.invalidateQueries({ queryKey: ['wa-queue-items'] });
      qc.invalidateQueries({ queryKey: ['wa-queue-stats'] });
    },
    onError: (e: any) => toast({ title: 'Erro', description: e.message, variant: 'destructive' }),
  });

  if (loading) return <div className="text-sm text-muted-foreground">Carregando…</div>;

  const hourlyUsedPct = stats ? Math.min(100, (stats.sentLastHour / Math.max(1, parseInt(maxPerHour, 10))) * 100) : 0;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Gauge className="h-4 w-4" /> Fila de envio WhatsApp (rate limit)
        </CardTitle>
        <CardDescription>
          Todas as mensagens automáticas (lembretes, cobranças, notificações) passam por esta fila.
          O worker roda a cada minuto e respeita os limites abaixo para evitar disparos em massa que
          possam gerar bloqueio pela Meta.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Kill switch */}
        <div className={`rounded-lg border p-4 flex items-start justify-between gap-3 ${enabled ? 'border-primary/30 bg-primary/5' : 'border-destructive/40 bg-destructive/5'}`}>
          <div>
            <p className="text-sm font-semibold">{enabled ? 'Fila ativa' : 'Fila PAUSADA'}</p>
            <p className="text-xs text-muted-foreground mt-0.5">
              {enabled
                ? 'O worker está autorizado a processar a fila a cada minuto.'
                : 'Mensagens continuam sendo enfileiradas, mas nenhuma é enviada até reativar.'}
            </p>
          </div>
          <Switch checked={enabled} onCheckedChange={persistEnabled} />
        </div>

        {!enabled && (
          <Alert variant="destructive">
            <ShieldAlert className="h-4 w-4" />
            <AlertTitle>Modo de proteção</AlertTitle>
            <AlertDescription className="text-xs">
              Use enquanto investigar suspeita de bloqueio ou para drenar a fila manualmente. Reative quando for seguro.
            </AlertDescription>
          </Alert>
        )}

        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div className="rounded-lg border p-3"><div className="text-xs text-muted-foreground">Aguardando</div><div className="text-2xl font-semibold">{stats?.pending ?? 0}</div></div>
          <div className="rounded-lg border p-3"><div className="text-xs text-muted-foreground">Enviando</div><div className="text-2xl font-semibold">{stats?.sending ?? 0}</div></div>
          <div className="rounded-lg border p-3"><div className="text-xs text-muted-foreground">Enviadas (1h)</div><div className="text-2xl font-semibold">{stats?.sentLastHour ?? 0} / {maxPerHour}</div>
            <div className="h-1 mt-1 bg-muted rounded overflow-hidden"><div className="h-full bg-primary" style={{ width: `${hourlyUsedPct}%` }} /></div>
          </div>
          <div className="rounded-lg border p-3"><div className="text-xs text-muted-foreground">Falhas (1h)</div><div className="text-2xl font-semibold text-destructive">{stats?.failedLastHour ?? 0}</div></div>
        </div>

        {/* Settings */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="space-y-2">
            <Label htmlFor="q-max-run">Máx. por execução</Label>
            <Input id="q-max-run" type="number" min={1} value={maxPerRun} onChange={(e) => setMaxPerRun(e.target.value)} />
            <p className="text-xs text-muted-foreground">Padrão: 5. Quantas mensagens o worker envia por minuto.</p>
          </div>
          <div className="space-y-2">
            <Label htmlFor="q-delay">Delay entre envios (ms)</Label>
            <Input id="q-delay" type="number" min={0} value={delayMs} onChange={(e) => setDelayMs(e.target.value)} />
            <p className="text-xs text-muted-foreground">Padrão: 1500. Espaço mínimo entre cada envio dentro do mesmo lote.</p>
          </div>
          <div className="space-y-2">
            <Label htmlFor="q-max-hour">Máx. por hora (global)</Label>
            <Input id="q-max-hour" type="number" min={1} value={maxPerHour} onChange={(e) => setMaxPerHour(e.target.value)} />
            <p className="text-xs text-muted-foreground">Padrão: 60. Teto absoluto independente do número de jobs.</p>
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          <Button onClick={handleSave} disabled={saving}>{saving ? 'Salvando…' : 'Salvar limites'}</Button>
          <Button variant="outline" onClick={handleRunNow} disabled={running}>
            <Play className="h-4 w-4 mr-2" />{running ? 'Executando…' : 'Processar fila agora'}
          </Button>
          <Button variant="outline" onClick={() => refetch()}>
            <RefreshCw className="h-4 w-4 mr-2" />Atualizar
          </Button>
          <Button variant="outline" onClick={() => purgeMutation.mutate('pending')} disabled={!stats?.pending}>
            <Trash2 className="h-4 w-4 mr-2" />Limpar pendentes
          </Button>
          <Button variant="outline" onClick={() => purgeMutation.mutate('failed')} disabled={!stats?.failedLastHour}>
            <Trash2 className="h-4 w-4 mr-2" />Limpar falhas
          </Button>
        </div>

        {/* Itens recentes */}
        <div>
          <Label className="text-xs">Últimos 50 itens da fila</Label>
          <ScrollArea className="h-72 mt-2 border rounded">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[120px]">Quando</TableHead>
                  <TableHead className="w-[110px]">Status</TableHead>
                  <TableHead className="w-[140px]">Telefone</TableHead>
                  <TableHead className="w-[120px]">Origem</TableHead>
                  <TableHead>Mensagem</TableHead>
                  <TableHead className="w-[80px]">Tent.</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(queueItems || []).length === 0 ? (
                  <TableRow><TableCell colSpan={6} className="text-center text-muted-foreground py-6 text-sm">Fila vazia.</TableCell></TableRow>
                ) : (queueItems || []).map((q: any) => (
                  <TableRow key={q.id}>
                    <TableCell className="text-xs font-mono">{format(new Date(q.created_at), 'dd/MM HH:mm:ss')}</TableCell>
                    <TableCell>{statusBadge(q.status)}</TableCell>
                    <TableCell className="font-mono text-xs">{q.phone_normalized}</TableCell>
                    <TableCell className="text-xs">{q.source}</TableCell>
                    <TableCell className="text-xs max-w-md truncate">{q.message}</TableCell>
                    <TableCell className="text-xs text-center">{q.attempts}/{q.max_attempts}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </ScrollArea>
        </div>
      </CardContent>
    </Card>
  );
}
