import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { MultiFilterBar } from '@/components/MultiFilterBar';
import { useMultiFilter } from '@/hooks/use-multi-filter';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { ScrollArea } from '@/components/ui/scroll-area';
import { RefreshCw, Eye, MessageCircle, Wand2, Download } from 'lucide-react';
import { format } from 'date-fns';
import { toast } from 'sonner';

type WaMessage = {
  id: string;
  direction: string;
  phone_normalized: string;
  message_type: string;
  body: string | null;
  delivery_status: string | null;
  is_broadcast: boolean | null;
  client_id: string | null;
  lead_id: string | null;
  wa_message_id: string | null;
  raw_payload: any;
  occurred_at: string;
  created_at: string;
};

const MESSAGE_TYPES = [
  'all', 'text', 'image', 'audio', 'video', 'document', 'location', 'contact', 'other',
] as const;

const DELIVERY_STATUSES = [
  'all', 'received', 'sent', 'delivered', 'read', 'played', 'failed',
] as const;

const DIRECTIONS = ['all', 'inbound', 'outbound'] as const;

function statusVariant(status: string | null): 'default' | 'secondary' | 'destructive' | 'outline' {
  switch (status) {
    case 'failed': return 'destructive';
    case 'read':
    case 'delivered':
    case 'played': return 'default';
    case 'received':
    case 'sent': return 'secondary';
    default: return 'outline';
  }
}

function typeVariant(type: string): 'default' | 'secondary' | 'destructive' | 'outline' {
  if (type === 'other') return 'destructive';
  if (type === 'text') return 'default';
  return 'secondary';
}

export default function WhatsAppLogsPage() {
  const { filters, toggle, setField, clearAll, activeCount } = useMultiFilter({
    search: '',
    direction: [] as string[],
    messageType: [] as string[],
    deliveryStatus: [] as string[],
  });
  const [selected, setSelected] = useState<WaMessage | null>(null);
  const [reprocessing, setReprocessing] = useState(false);

  const { search, direction, messageType, deliveryStatus } = filters as {
    search: string; direction: string[]; messageType: string[]; deliveryStatus: string[];
  };

  const { data, isLoading, refetch, isFetching } = useQuery({
    queryKey: ['wa-logs', direction, messageType, deliveryStatus, search],
    queryFn: async () => {
      let q = supabase
        .from('whatsapp_messages')
        .select('*')
        .order('occurred_at', { ascending: false })
        .limit(500);

      if (direction.length) q = (q as any).in('direction', direction);
      if (messageType.length) q = (q as any).in('message_type', messageType);
      if (deliveryStatus.length) q = (q as any).in('delivery_status', deliveryStatus);
      if (search.trim()) {
        const digits = search.replace(/\D/g, '');
        if (digits.length >= 6) {
          q = q.ilike('phone_normalized', `%${digits}%`);
        } else {
          q = q.ilike('body', `%${search.trim()}%`);
        }
      }

      const { data, error } = await q;
      if (error) throw error;
      return (data || []) as WaMessage[];
    },
    refetchInterval: 30000,
  });

  const reprocessUnknown = async () => {
    if (!confirm('Reprocessar todas as mensagens marcadas como "não reconhecidas" usando o parser atualizado?')) return;
    setReprocessing(true);
    try {
      const { data, error } = await supabase.functions.invoke('whatsapp-reprocess-messages', { body: {} });
      if (error) throw error;
      const r = data as any;
      toast.success(`Reprocessadas: ${r.updated} atualizadas, ${r.still_unknown} continuam sem identificação.`);
      refetch();
    } catch (e: any) {
      toast.error(e?.message || 'Falha ao reprocessar.');
    } finally {
      setReprocessing(false);
    }
  };

  const stats = useMemo(() => {
    const list = data || [];
    const total = list.length;
    const unknown = list.filter((m) => m.message_type === 'other').length;
    const failed = list.filter((m) => m.delivery_status === 'failed').length;
    const inbound = list.filter((m) => m.direction === 'inbound').length;
    const outbound = list.filter((m) => m.direction === 'outbound').length;
    return { total, unknown, failed, inbound, outbound };
  }, [data]);

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <PageHeader
          title="Logs do Webhook WhatsApp"
          description="Veja toda mensagem que entrou ou saiu via WhatsApp. Filtre por tipo e status para diagnosticar 'mensagens não reconhecidas'."
        />
        <Button onClick={reprocessUnknown} disabled={reprocessing} variant="outline">
          <Wand2 className={`h-4 w-4 mr-2 ${reprocessing ? 'animate-spin' : ''}`} />
          {reprocessing ? 'Reprocessando…' : 'Reprocessar não reconhecidas'}
        </Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        <Card><CardContent className="pt-4"><div className="text-xs text-muted-foreground">Total</div><div className="text-2xl font-semibold">{stats.total}</div></CardContent></Card>
        <Card><CardContent className="pt-4"><div className="text-xs text-muted-foreground">Recebidas</div><div className="text-2xl font-semibold">{stats.inbound}</div></CardContent></Card>
        <Card><CardContent className="pt-4"><div className="text-xs text-muted-foreground">Enviadas</div><div className="text-2xl font-semibold">{stats.outbound}</div></CardContent></Card>
        <Card><CardContent className="pt-4"><div className="text-xs text-muted-foreground">Não reconhecidas</div><div className="text-2xl font-semibold text-destructive">{stats.unknown}</div></CardContent></Card>
        <Card><CardContent className="pt-4"><div className="text-xs text-muted-foreground">Falhas</div><div className="text-2xl font-semibold text-destructive">{stats.failed}</div></CardContent></Card>
      </div>

      <MultiFilterBar
        search={search}
        onSearchChange={v => setField('search', v)}
        searchPlaceholder="Buscar por telefone (dígitos) ou texto da mensagem…"
        filters={filters}
        activeCount={activeCount}
        onToggle={toggle}
        onSetField={setField}
        onClearAll={clearAll}
        presetType="whatsapp_logs"
        groups={[
          {
            type: 'multi',
            field: 'direction',
            label: 'Direção',
            options: [
              { value: 'inbound', label: 'Recebida' },
              { value: 'outbound', label: 'Enviada' },
            ],
          },
          {
            type: 'multi',
            field: 'messageType',
            label: 'Tipo',
            options: MESSAGE_TYPES.filter(t => t !== 'all').map(t => ({ value: t, label: t })),
          },
          {
            type: 'multi',
            field: 'deliveryStatus',
            label: 'Status de entrega',
            options: DELIVERY_STATUSES.filter(s => s !== 'all').map(s => ({ value: s, label: s })),
          },
        ]}
        extra={
          <>
            <Button variant="outline" size="sm" className="gap-1" onClick={() => {
              const list = data || [];
              if (!list.length) return;
              const rows = list.map(m => ({
                'Data/Hora': m.occurred_at ? format(new Date(m.occurred_at), 'dd/MM/yyyy HH:mm') : '',
                'Direção': m.direction === 'inbound' ? 'Recebida' : 'Enviada',
                'Telefone': m.phone_normalized || '',
                'Tipo': m.message_type || '',
                'Status Entrega': m.delivery_status || '',
                'Broadcast': m.is_broadcast ? 'Sim' : 'Não',
                'Mensagem': (m.body || '').substring(0, 200),
              }));
              const csv = [Object.keys(rows[0]).join(','), ...rows.map(r => Object.values(r).map(v => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))].join('\n');
              const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' })); a.download = 'whatsapp_logs.csv'; a.click();
            }}>
              <Download className="h-3.5 w-3.5" /> CSV
            </Button>
            <Button variant="outline" size="icon" onClick={() => refetch()} disabled={isFetching} title="Atualizar">
              <RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />
            </Button>
          </>
        }
      />

      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle className="text-base flex items-center gap-2">
            <MessageCircle className="h-4 w-4" /> Mensagens (últimas 500)
          </CardTitle>
        </CardHeader>
        <CardContent>
          <ScrollArea className="h-[60vh]">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[140px]">Data/Hora</TableHead>
                  <TableHead className="w-[80px]">Direção</TableHead>
                  <TableHead className="w-[140px] hidden sm:table-cell">Telefone</TableHead>
                  <TableHead className="w-[100px] hidden sm:table-cell">Tipo</TableHead>
                  <TableHead className="w-[110px]">Status</TableHead>
                  <TableHead>Corpo</TableHead>
                  <TableHead className="w-[60px]"></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {isLoading ? (
                  <TableRow><TableCell colSpan={7} className="text-center text-muted-foreground py-8">Carregando...</TableCell></TableRow>
                ) : (data || []).length === 0 ? (
                  <TableRow><TableCell colSpan={7} className="text-center text-muted-foreground py-8">Nenhuma mensagem encontrada com os filtros atuais.</TableCell></TableRow>
                ) : (data || []).map((m) => (
                  <TableRow key={m.id} className="cursor-pointer" onClick={() => setSelected(m)}>
                    <TableCell className="text-xs font-mono">{format(new Date(m.occurred_at), 'dd/MM HH:mm:ss')}</TableCell>
                    <TableCell>
                      <Badge variant={m.direction === 'inbound' ? 'default' : 'secondary'} className="text-xs">
                        {m.direction === 'inbound' ? '←' : '→'} {m.direction}
                      </Badge>
                    </TableCell>
                    <TableCell className="font-mono text-xs hidden sm:table-cell">{m.phone_normalized}</TableCell>
                    <TableCell className="hidden sm:table-cell">
                      <Badge variant={typeVariant(m.message_type)} className="text-xs">{m.message_type}</Badge>
                    </TableCell>
                    <TableCell>
                      <Badge variant={statusVariant(m.delivery_status)} className="text-xs">{m.delivery_status || '—'}</Badge>
                    </TableCell>
                    <TableCell className="max-w-md truncate text-sm">{m.body || <span className="text-muted-foreground italic">vazio</span>}</TableCell>
                    <TableCell>
                      <Button variant="ghost" size="icon" onClick={(e) => { e.stopPropagation(); setSelected(m); }}>
                        <Eye className="h-4 w-4" />
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </ScrollArea>
        </CardContent>
      </Card>

      {/* Detail Dialog */}
      <Dialog open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
        <DialogContent className="max-w-3xl max-h-[85vh]">
          <DialogHeader>
            <DialogTitle>Detalhes da mensagem</DialogTitle>
          </DialogHeader>
          {selected && (
            <ScrollArea className="max-h-[70vh] pr-4">
              <div className="space-y-3 text-sm">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div><div className="text-xs text-muted-foreground">ID</div><div className="font-mono text-xs break-all">{selected.id}</div></div>
                  <div><div className="text-xs text-muted-foreground">Provider ID</div><div className="font-mono text-xs break-all">{selected.wa_message_id || '—'}</div></div>
                  <div><div className="text-xs text-muted-foreground">Data</div><div>{format(new Date(selected.occurred_at), 'dd/MM/yyyy HH:mm:ss')}</div></div>
                  <div><div className="text-xs text-muted-foreground">Telefone</div><div className="font-mono">{selected.phone_normalized}</div></div>
                  <div><div className="text-xs text-muted-foreground">Direção</div><Badge>{selected.direction}</Badge></div>
                  <div><div className="text-xs text-muted-foreground">Tipo</div><Badge variant={typeVariant(selected.message_type)}>{selected.message_type}</Badge></div>
                  <div><div className="text-xs text-muted-foreground">Status</div><Badge variant={statusVariant(selected.delivery_status)}>{selected.delivery_status || '—'}</Badge></div>
                  <div><div className="text-xs text-muted-foreground">Broadcast</div><div>{selected.is_broadcast ? 'Sim' : 'Não'}</div></div>
                </div>
                <div>
                  <div className="text-xs text-muted-foreground mb-1">Corpo</div>
                  <div className="bg-muted p-3 rounded text-sm whitespace-pre-wrap break-words">{selected.body || '(vazio)'}</div>
                </div>
                {selected.message_type === 'other' && (
                  <div className="bg-destructive/10 border border-destructive/30 rounded p-3 text-xs">
                    <strong>Por que &ldquo;não reconhecida&rdquo;?</strong> O webhook não encontrou nenhum dos campos esperados (text, image, audio, video, document, location, contact). Veja o payload bruto abaixo — geralmente é um callback do provider (status, presença, ack) que não traz conteúdo de mensagem.
                  </div>
                )}
                <div>
                  <div className="text-xs text-muted-foreground mb-1">Payload bruto</div>
                  <pre className="bg-muted p-3 rounded text-xs overflow-auto max-h-80">{JSON.stringify(selected.raw_payload, null, 2)}</pre>
                </div>
              </div>
            </ScrollArea>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
