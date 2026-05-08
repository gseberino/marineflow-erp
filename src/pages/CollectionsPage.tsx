import { useEffect, useMemo, useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { KPICard } from '@/components/KPICard';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import {
  MoreHorizontal, MessageCircle, RefreshCw, CheckCircle, ClipboardList,
  History, FileText, Pencil, X, Plus, SlidersHorizontal, ArrowUpDown,
  AlertCircle, TrendingUp, Wallet, Clock, Phone, Download, ArrowUp, ArrowDown,
} from 'lucide-react';
import {
  useCollections, useMarkOverdueCollections, useCancelCollection, useSendCollectionWhatsApp,
  type CollectionFilters, type Collection, type CollectionStatus,
} from '@/hooks/use-collections';
import { useClients } from '@/hooks/use-clients';
import { CollectionStatusBadge, COLLECTION_STATUS_OPTIONS } from '@/components/collections/CollectionStatusBadge';
import { CreateCollectionDialog } from '@/components/collections/CreateCollectionDialog';
import { PaymentConfirmDialog } from '@/components/collections/PaymentConfirmDialog';
import { AddContactDialog } from '@/components/collections/AddContactDialog';
import { EditContactDialog } from '@/components/collections/EditContactDialog';
import { AutoRuleDialog } from '@/components/collections/AutoRuleDialog';
import { CollectionDetailSheet } from '@/components/collections/CollectionDetailSheet';
import { cn } from '@/lib/utils';

const fmtBRL = (v: number) =>
  v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

const todayISO = () => new Date().toISOString().slice(0, 10);

export default function CollectionsPage() {
  const [filters, setFilters] = useState<CollectionFilters>({
    sort_by: 'due_date', sort_dir: 'asc',
  });

  const [createOpen, setCreateOpen] = useState(false);
  const [ruleOpen, setRuleOpen] = useState(false);
  const [payTarget, setPayTarget] = useState<Collection | null>(null);
  const [contactTarget, setContactTarget] = useState<Collection | null>(null);
  const [editContactTarget, setEditContactTarget] = useState<Collection | null>(null);
  const [cancelTarget, setCancelTarget] = useState<Collection | null>(null);
  const [detailId, setDetailId] = useState<string | null>(null);

  const { data: collections = [], isLoading } = useCollections(filters);

  const handleSort = (col: CollectionFilters['sort_by']) => {
    setFilters(f => ({
      ...f,
      sort_by: col,
      sort_dir: f.sort_by === col && f.sort_dir !== 'desc' ? 'desc' : 'asc',
    }));
  };
  const SortIcon = ({ col }: { col: CollectionFilters['sort_by'] }) => {
    if (filters.sort_by !== col) return <ArrowUpDown className="h-3 w-3 ml-1 opacity-40" />;
    return filters.sort_dir === 'desc' ? <ArrowDown className="h-3 w-3 ml-1" /> : <ArrowUp className="h-3 w-3 ml-1" />;
  };
  const { data: clients } = useClients();
  const cancel = useCancelCollection();
  const send = useSendCollectionWhatsApp();
  const markOverdue = useMarkOverdueCollections();

  // Run once on mount to mark any past-due collections as overdue
  useEffect(() => { markOverdue.mutate(); }, []);

  const kpis = useMemo(() => {
    const open = collections.filter(c => ['pending', 'sent', 'viewed'].includes(c.status));
    const overdue = collections.filter(c => c.status === 'overdue');
    const totalOpen = open.reduce((s, c) => s + Number(c.amount), 0);
    const totalOverdue = overdue.reduce((s, c) => s + Number(c.amount), 0);
    const since = new Date(); since.setDate(since.getDate() - 30);
    const last30 = collections.filter(c => new Date(c.created_at) >= since);
    const paid30 = last30.filter(c => c.status === 'paid').length;
    const overdue30 = last30.filter(c => c.status === 'overdue').length;
    const recovery = paid30 + overdue30 > 0 ? (paid30 / (paid30 + overdue30)) * 100 : 0;
    const today = new Date();
    const avgDays = overdue.length === 0 ? 0 :
      Math.round(overdue.reduce((s, c) => {
        const d = (today.getTime() - new Date(c.due_date).getTime()) / 86400000;
        return s + Math.max(0, d);
      }, 0) / overdue.length);
    return { totalOpen, totalOverdue, recovery, avgDays };
  }, [collections]);

  const dueColor = (date: string, status: CollectionStatus) => {
    if (status === 'paid' || status === 'cancelled') return '';
    const t = todayISO();
    if (date < t) return 'text-red-600 font-medium';
    if (date === t) return 'text-amber-600 font-medium';
    return '';
  };

  const clearFilters = () => setFilters({ sort_by: 'due_date', sort_dir: 'asc' });

  const update = (patch: Partial<CollectionFilters>) => setFilters(f => ({ ...f, ...patch }));

  return (
    <div>
      <PageHeader title="Cobranças" description="Gerencie cobranças e régua automática">
        <Button variant="outline" size="sm" className="gap-1" onClick={() => {
          const rows = collections.map((c: any) => ({
            Cliente: c.client?.full_name_or_company_name || '—',
            'OS / Ref': c.service_order?.service_order_number || 'Avulso',
            'Valor': Number(c.amount).toFixed(2),
            'Vencimento': new Date(c.due_date).toLocaleDateString('pt-BR'),
            'Status': c.status,
            'Telefone': c.contact_phone || c.client?.phone || '',
            'Último Contato': c.last_contact_at ? new Date(c.last_contact_at).toLocaleDateString('pt-BR') : '',
          }));
          const csv = [Object.keys(rows[0] || {}).join(','), ...rows.map((r: any) => Object.values(r).map((v: any) => `"${String(v ?? '').replace(/"/g,'""')}"`).join(','))].join('\n');
          const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿'+csv], {type:'text/csv;charset=utf-8;'})); a.download = 'cobranças.csv'; a.click();
        }}>
          <Download className="h-3.5 w-3.5" /> Exportar CSV
        </Button>
        <Button variant="outline" onClick={() => setRuleOpen(true)}>
          <SlidersHorizontal className="h-4 w-4 mr-2" /> Configurar Régua
        </Button>
        <Button onClick={() => setCreateOpen(true)}>
          <Plus className="h-4 w-4 mr-2" /> Nova Cobrança
        </Button>
      </PageHeader>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <button onClick={() => update({ status: 'pending' })} className="text-left">
          <KPICard title="Total em Aberto" value={fmtBRL(kpis.totalOpen)}
            icon={Wallet} subtitle="Pendentes/Enviadas/Vistas"
            className="border-amber-500/30 hover:border-amber-500/60 transition-colors" />
        </button>
        <button onClick={() => update({ status: 'overdue' })} className="text-left">
          <KPICard title="Total Vencido" value={fmtBRL(kpis.totalOverdue)}
            icon={AlertCircle} subtitle="Em atraso"
            className="border-red-500/30 hover:border-red-500/60 transition-colors" />
        </button>
        <KPICard title="Taxa de Recuperação" value={`${kpis.recovery.toFixed(0)}%`}
          icon={TrendingUp} subtitle="Últimos 30 dias"
          className="border-green-500/30" />
        <KPICard title="Média em Atraso" value={`${kpis.avgDays} dias`}
          icon={Clock} subtitle="Cobranças vencidas"
          className="border-blue-500/30" />
      </div>

      <div className="rounded-xl border bg-card p-4 mb-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
        <div className="space-y-1">
          <Label className="text-xs">Buscar</Label>
          <Input placeholder="Cliente ou OS..." value={filters.search || ''}
            onChange={e => update({ search: e.target.value || undefined })} />
        </div>
        <div className="space-y-1 md:col-span-2 lg:col-span-4">
          <Label className="text-xs">Status</Label>
          <div className="flex flex-wrap gap-1.5">
            {[{ value: 'all', label: 'Todos' }, ...COLLECTION_STATUS_OPTIONS].map(opt => {
              const isActive = opt.value === 'all' ? !filters.status || filters.status === 'all' : filters.status === opt.value;
              return (
                <button
                  key={opt.value}
                  type="button"
                  onClick={() => update({ status: opt.value === 'all' || isActive ? undefined : opt.value })}
                  className={cn(
                    'px-2.5 py-0.5 rounded-full text-xs border transition-colors',
                    isActive
                      ? 'bg-primary/10 text-primary border-primary/50 font-medium'
                      : 'bg-background text-muted-foreground border-border hover:border-primary/50',
                  )}
                >
                  {opt.label}
                </button>
              );
            })}
          </div>
        </div>
        <div className="space-y-1">
          <Label className="text-xs">Cliente</Label>
          <Select value={filters.client_id || 'all'}
            onValueChange={v => update({ client_id: v === 'all' ? undefined : v })}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todos</SelectItem>
              {(clients || []).map(c => (
                <SelectItem key={c.id} value={c.id}>{c.full_name_or_company_name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1">
          <Label className="text-xs">Ordenar por</Label>
          <div className="flex gap-2">
            <Select value={filters.sort_by || 'due_date'} onValueChange={(v: any) => update({ sort_by: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="due_date">Vencimento</SelectItem>
                <SelectItem value="amount">Valor</SelectItem>
                <SelectItem value="client">Cliente</SelectItem>
                <SelectItem value="status">Status</SelectItem>
                <SelectItem value="created_at">Criação</SelectItem>
              </SelectContent>
            </Select>
            <Button variant="outline" size="icon"
              onClick={() => update({ sort_dir: filters.sort_dir === 'desc' ? 'asc' : 'desc' })}
              title={filters.sort_dir === 'desc' ? 'Decrescente' : 'Crescente'}>
              <ArrowUpDown className="h-4 w-4" />
            </Button>
          </div>
        </div>
        <div className="space-y-1">
          <Label className="text-xs">Vence de</Label>
          <Input type="date" value={filters.date_from || ''}
            onChange={e => update({ date_from: e.target.value || undefined })} />
        </div>
        <div className="space-y-1">
          <Label className="text-xs">Vence até</Label>
          <Input type="date" value={filters.date_to || ''}
            onChange={e => update({ date_to: e.target.value || undefined })} />
        </div>
        <div className="space-y-1">
          <Label className="text-xs">Valor mín</Label>
          <Input type="number" value={filters.amount_min ?? ''}
            onChange={e => update({ amount_min: e.target.value ? Number(e.target.value) : undefined })} />
        </div>
        <div className="space-y-1">
          <Label className="text-xs">Valor máx</Label>
          <div className="flex gap-2">
            <Input type="number" value={filters.amount_max ?? ''}
              onChange={e => update({ amount_max: e.target.value ? Number(e.target.value) : undefined })} />
            <Button variant="outline" size="sm" onClick={clearFilters}>Limpar</Button>
          </div>
        </div>
      </div>

      <div className="rounded-xl border bg-card overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="cursor-pointer select-none" onClick={() => handleSort('client')}>
                <span className="inline-flex items-center">Cliente <SortIcon col="client" /></span>
              </TableHead>
              <TableHead className="hidden sm:table-cell">OS / Ref</TableHead>
              <TableHead className="text-right cursor-pointer select-none" onClick={() => handleSort('amount')}>
                <span className="inline-flex items-center justify-end w-full">Valor <SortIcon col="amount" /></span>
              </TableHead>
              <TableHead className="cursor-pointer select-none" onClick={() => handleSort('due_date')}>
                <span className="inline-flex items-center">Vencimento <SortIcon col="due_date" /></span>
              </TableHead>
              <TableHead className="cursor-pointer select-none" onClick={() => handleSort('status')}>
                <span className="inline-flex items-center">Status <SortIcon col="status" /></span>
              </TableHead>
              <TableHead className="hidden md:table-cell">Contato</TableHead>
              <TableHead className="hidden lg:table-cell">Último contato</TableHead>
              <TableHead className="w-12"></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoading ? (
              <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Carregando...</TableCell></TableRow>
            ) : collections.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Nenhuma cobrança encontrada.</TableCell></TableRow>
            ) : collections.map(c => {
              const phone = c.contact_whatsapp || c.contact_phone || c.client?.whatsapp || c.client?.phone || '';
              return (
                <TableRow key={c.id} className="cursor-pointer" onClick={() => setDetailId(c.id)}>
                  <TableCell className="font-medium">{c.client?.full_name_or_company_name || '—'}</TableCell>
                  <TableCell className="text-sm hidden sm:table-cell">
                    {c.service_order?.service_order_number || <span className="text-muted-foreground">Avulso</span>}
                  </TableCell>
                  <TableCell className="text-right font-mono">{fmtBRL(Number(c.amount))}</TableCell>
                  <TableCell className={cn('text-sm', dueColor(c.due_date, c.status))}>
                    {new Date(c.due_date).toLocaleDateString('pt-BR')}
                  </TableCell>
                  <TableCell><CollectionStatusBadge status={c.status} /></TableCell>
                  <TableCell className="text-xs text-muted-foreground hidden md:table-cell">
                    {phone ? <span className="inline-flex items-center gap-1"><Phone className="h-3 w-3" />{phone}</span> : '—'}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground hidden lg:table-cell">
                    {c.last_contact_at ? new Date(c.last_contact_at).toLocaleDateString('pt-BR') : '—'}
                  </TableCell>
                  <TableCell onClick={e => e.stopPropagation()}>
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="icon" className="h-8 w-8">
                          <MoreHorizontal className="h-4 w-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem
                          onClick={() => send.mutate({ collection: c })}
                          className="text-green-600 focus:text-green-700">
                          <MessageCircle className="h-4 w-4 mr-2" /> Enviar WhatsApp
                        </DropdownMenuItem>
                        {c.status === 'sent' && (
                          <DropdownMenuItem onClick={() => send.mutate({ collection: c })}>
                            <RefreshCw className="h-4 w-4 mr-2" /> Reenviar lembrete
                          </DropdownMenuItem>
                        )}
                        <DropdownMenuItem onClick={() => setPayTarget(c)}>
                          <CheckCircle className="h-4 w-4 mr-2" /> Marcar como paga
                        </DropdownMenuItem>
                        <DropdownMenuItem onClick={() => setContactTarget(c)}>
                          <ClipboardList className="h-4 w-4 mr-2" /> Registrar contato
                        </DropdownMenuItem>
                        <DropdownMenuItem onClick={() => setDetailId(c.id)}>
                          <History className="h-4 w-4 mr-2" /> Ver histórico
                        </DropdownMenuItem>
                        {c.service_order_id && (
                          <DropdownMenuItem onClick={() => window.open(`/service-orders/${c.service_order_id}`, '_blank')}>
                            <FileText className="h-4 w-4 mr-2" /> Ver OS
                          </DropdownMenuItem>
                        )}
                        <DropdownMenuItem onClick={() => setEditContactTarget(c)}>
                          <Pencil className="h-4 w-4 mr-2" /> Alterar contato
                        </DropdownMenuItem>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem
                          onClick={() => setCancelTarget(c)}
                          className="text-destructive focus:text-destructive">
                          <X className="h-4 w-4 mr-2" /> Cancelar
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>

      <CreateCollectionDialog open={createOpen} onOpenChange={setCreateOpen} />
      <AutoRuleDialog open={ruleOpen} onOpenChange={setRuleOpen} />
      <PaymentConfirmDialog open={!!payTarget} onOpenChange={v => !v && setPayTarget(null)} collection={payTarget} />
      {contactTarget && (
        <AddContactDialog open={!!contactTarget} onOpenChange={v => !v && setContactTarget(null)} collectionId={contactTarget.id} />
      )}
      <EditContactDialog open={!!editContactTarget} onOpenChange={v => !v && setEditContactTarget(null)} collection={editContactTarget} />
      <CollectionDetailSheet collectionId={detailId} onClose={() => setDetailId(null)} />

      <AlertDialog open={!!cancelTarget} onOpenChange={v => !v && setCancelTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Cancelar cobrança?</AlertDialogTitle>
            <AlertDialogDescription>
              A cobrança de {cancelTarget?.client?.full_name_or_company_name} no valor de
              {' '}{cancelTarget && fmtBRL(Number(cancelTarget.amount))} será marcada como cancelada.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Voltar</AlertDialogCancel>
            <AlertDialogAction
              onClick={async () => {
                if (cancelTarget) await cancel.mutateAsync(cancelTarget.id);
                setCancelTarget(null);
              }}
            >Cancelar cobrança</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
