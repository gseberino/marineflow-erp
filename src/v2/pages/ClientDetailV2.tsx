import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { FileText, Layers, Mail, MapPin, Pencil, Phone } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useClient } from '@/hooks/use-clients';
import { useVesselsForClient } from '@/hooks/use-vessels';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ClientFormDialog } from '@/components/ClientFormDialog';
// MF-AUD-050: o extrato do cliente vivia só no ClientDetail v1 — desde os redirects
// de 30/07 ficou alcançável apenas com ?legacy=1. O componente sempre funcionou;
// faltava a casa na V2.
import { ClientStatementDialog } from '@/components/ClientStatementDialog';
import { CobrarJuntasDialog } from '@/components/client/CobrarJuntasDialog';
import { RecordHistory } from '@/components/RecordHistory';
import { PagadoresDoCliente } from '@/components/PagadoresDoCliente';
import { EntityTasksPanel } from '@/components/agenda/EntityTasksPanel';
import { OpenLoopsPanel } from '@/components/agenda/OpenLoopsPanel';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import { serviceOrderStatusTone } from '@/v2/status-map';
import { IconeDaUnidade } from '@/components/service-order/FichaDaEmbarcacao';
import { camposDoTipo, comprimentoDoTipo, nomeDaUnidade } from '@/lib/unidade';
import {
  contaVencida, osComSaldo, osEntraNoCobrarJuntas, pagoDaConta, saldoDaConta,
} from '../../../supabase/functions/_shared/receivables/cobrar-juntas';
import '@/v2/tokens.css';

/* Onda A/C · Detalhe do Cliente v2 — paridade com ClientDetail v1
   (contato, embarcações, OS, financeiro, tarefas, histórico) com
   breadcrumb, DataTable (as tabelas v1 tinham min-w-[600px] + scroll
   lateral) e totais preservados. */

type SORow = {
  id: string; service_order_number: string; service_type?: string | null; status: string; grand_total?: number | null;
  /** Origem de um agrupamento (agrupar_orcamentos / agrupar_os): o valor dela já está no orçamento/OS que a reúne. */
  merged_into_id?: string | null;
};
type RecRow = {
  id: string; description: string; due_date: string; status?: string | null; amount: number;
  paid_amount?: number | null; balance_amount?: number | null; service_order_id?: string | null;
  /** Número da OS da conta (embed pela FK): a conta pode ser de OS de outro cliente (pagador). */
  numero_os?: string | null;
  /** Situação da OS da conta: só OS que já começou entra no "Cobrar juntas". */
  os?: { status?: string | null; merged_into_id?: string | null } | null;
};

export default function ClientDetailV2() {
  const { id } = useParams<{ id: string }>();
  const { t, formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();
  const { data: client, isLoading } = useClient(id);
  const { data: vessels } = useVesselsForClient(id);
  const [editOpen, setEditOpen] = useState(false);
  const [statementOpen, setStatementOpen] = useState(false);
  /** Cobrar juntas: aberto com estas OS marcadas (vazio = todas as que têm saldo). */
  const [cobrarJuntas, setCobrarJuntas] = useState<string[] | null>(null);

  const { data: orders } = useQuery({
    queryKey: ['service-orders', 'client', id],
    queryFn: async () => {
      if (!id) return [];
      const { data, error } = await supabase
        .from('service_orders').select('*').eq('client_id', id)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data as unknown as SORow[];
    },
    enabled: !!id,
  });
  // Contagem e total sem as origens agrupadas: o valor delas já está no agrupado (senão conta em dobro).
  // A tabela segue mostrando todas, como histórico.
  const ordensQueContam = (orders ?? []).filter((o) => !o.merged_into_id);

  const { data: clientReceivables } = useQuery({
    // Chave própria (com o número e a situação da OS): a ficha v1 usa ['receivables', 'client', id] com
    // select('*'), e o cache de uma serviria a outra sem os campos da OS. O prefixo ['receivables'] segue invalidando.
    queryKey: ['receivables', 'client', id, 'com-os'],
    queryFn: async () => {
      if (!id) return [];
      const { data, error } = await supabase
        .from('receivables').select('*, service_orders!receivables_service_order_id_fkey(service_order_number, status, merged_into_id)').eq('client_id', id)
        .order('due_date', { ascending: false });
      if (error) throw error;
      return ((data ?? []) as unknown as Array<RecRow & { service_orders?: { service_order_number?: string | null; status?: string | null; merged_into_id?: string | null } | null }>)
        .map(({ service_orders, ...r }) => ({ ...r, numero_os: service_orders?.service_order_number ?? null, os: service_orders ?? null }));
    },
    enabled: !!id,
  });

  if (isLoading) {
    return (
      <V2Shell>
        <div className="space-y-4">
          <Skeleton className="h-10 w-64" />
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-3">{[1, 2, 3].map((i) => <Skeleton key={i} className="h-28 rounded-lg" />)}</div>
        </div>
      </V2Shell>
    );
  }

  if (!client) {
    return (
      <V2Shell>
        <p className="py-20 text-center text-muted-foreground">
          {t.common.noResults} <Link to="/v2/clients" className="text-accent hover:underline">← {t.common.back}</Link>
        </p>
      </V2Shell>
    );
  }

  const osColumns: DataColumn<SORow>[] = [
    {
      key: 'number', header: t.serviceOrders.orderNumber, minWidth: 120, priority: 0,
      render: (o) => <span className="font-bold text-accent">{o.service_order_number}</span>,
    },
    {
      key: 'status', header: t.common.status, minWidth: 140, priority: 1,
      render: (o) => (
        <StatusChip dot tone={serviceOrderStatusTone[o.status] ?? 'neutral'}>
          {(t.status as Record<string, string>)[o.status] ?? o.status}
        </StatusChip>
      ),
    },
    {
      key: 'total', header: t.common.total, minWidth: 116, priority: 1, align: 'right',
      render: (o) => <span className="font-semibold">{formatCurrency(o.grand_total ?? 0)}</span>,
    },
    {
      key: 'type', header: t.common.type, minWidth: 120, priority: 2, detailLabel: 'Tipo',
      render: (o) => (
        <span className="text-muted-foreground">
          {o.service_type ? (t.serviceType as Record<string, string>)[o.service_type] ?? o.service_type : '—'}
        </span>
      ),
    },
  ];

  // "Vencido" pela data: o banco nunca grava 'overdue' (medido em 28/10/2026).
  const situacaoDa = (r: RecRow): string =>
    r.status !== 'cancelled' && contaVencida(r) ? 'overdue' : (r.status ?? 'pending');
  const recTone = (status?: string | null): StatusTone =>
    status === 'paid' ? 'success' : status === 'overdue' ? 'critical' : status === 'cancelled' ? 'neutral' : 'warning';

  const recColumns: DataColumn<RecRow>[] = [
    {
      key: 'description', header: t.common.description, minWidth: 200, priority: 0,
      render: (r) => <span className="truncate font-medium">{r.description}</span>,
    },
    {
      key: 'os', header: 'OS', minWidth: 100, priority: 1, detailLabel: 'OS',
      render: (r) => r.service_order_id
        ? <Link to={`/v2/service-orders/${r.service_order_id}`} onClick={(e) => e.stopPropagation()} className="font-medium text-accent hover:underline">{r.numero_os || 'OS'}</Link>
        : <span className="text-muted-foreground">—</span>,
    },
    {
      key: 'due', header: t.financial.dueDate, minWidth: 110, priority: 1,
      render: (r) => <span className="text-muted-foreground tabular-nums">{formatDate(r.due_date)}</span>,
    },
    {
      key: 'status', header: t.common.status, minWidth: 110, priority: 1,
      render: (r) => {
        const sit = situacaoDa(r);
        return (
          <StatusChip dot tone={recTone(sit)}>
            {(t.paymentStatus as Record<string, string>)[sit] ?? sit}
          </StatusChip>
        );
      },
    },
    {
      key: 'amount', header: t.common.amount, minWidth: 116, priority: 1, align: 'right',
      render: (r) => <span className="font-semibold">{formatCurrency(r.amount)}</span>,
    },
  ];

  // Totais pela regra de useSaldoEmAberto (a mesma da ficha na OS): cancelada fora, pago parcial
  // conta como pago, em aberto = soma dos saldos. Antes, o total somava as canceladas e o "Pago"
  // ignorava o pago parcial (spec-fechar-juntas 6.1).
  const contasQueContam = (clientReceivables ?? []).filter((r) => r.status !== 'cancelled');
  const cent = (v: number) => Math.round(v * 100) / 100;
  const recTotal = cent(contasQueContam.reduce((s, r) => s + Number(r.amount || 0), 0));
  const recPaid = cent(contasQueContam.reduce((s, r) => s + pagoDaConta(r), 0));
  const recOpen = cent(contasQueContam.reduce((s, r) => s + saldoDaConta(r), 0));
  // As OS com saldo, para o "Cobrar juntas" (uma mensagem com o saldo de várias OS).
  // Só contas de OS que já começaram (as que não começaram se juntam pelo Agrupar OS).
  const contasParaCobrar = (clientReceivables ?? []).filter((r) => osEntraNoCobrarJuntas(r.os));
  const osParaCobrar = osComSaldo(contasParaCobrar);
  const generico = client.generico === true;
  const abrirCobrarJuntas = (contaIds: string[]) => {
    const escolhidas = new Set(contaIds);
    const oss = [...new Set(contasParaCobrar
      .filter((r) => escolhidas.has(r.id) && r.service_order_id && saldoDaConta(r) > 0)
      .map((r) => r.service_order_id as string))];
    setCobrarJuntas(oss);
  };

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Cadastros' }, { label: t.clients.title, to: '/v2/clients' }, { label: client.name }]}
        title={client.name}
        description={`${client.type === 'company' ? t.common.company : t.common.individual}${client.city ? ` · ${client.city}${client.state ? `/${client.state}` : ''}` : ''}`}
        actions={
          <Button variant="outline" size="sm" className="gap-1.5" onClick={() => setEditOpen(true)}>
            <Pencil className="h-4 w-4" /> {t.common.edit}
          </Button>
        }
      >
        <div className="grid grid-cols-1 gap-3 lg:grid-cols-3">
          <div className="space-y-2.5 rounded-lg border bg-card p-4 text-sm">
            {/* clients.generico (dono, 28/10/2026): o cadastro de balcão, sem CPF/CNPJ. */}
            {generico && (
              <p className="space-y-1">
                <StatusChip tone="neutral">Cadastro genérico</StatusChip>
                <span className="block text-xs text-muted-foreground">Sem CPF/CNPJ: não entra em cobrança conjunta nem em agrupamento.</span>
              </p>
            )}
            {client.email && <p className="flex items-center gap-2"><Mail className="h-4 w-4 shrink-0 text-muted-foreground" /> <span className="truncate">{client.email}</span></p>}
            {client.phone && <p className="flex items-center gap-2"><Phone className="h-4 w-4 shrink-0 text-muted-foreground" /> {client.phone}</p>}
            {client.address_line_1 && <p className="flex items-center gap-2"><MapPin className="h-4 w-4 shrink-0 text-muted-foreground" /> <span className="truncate">{client.address_line_1}, {client.city}</span></p>}
            {client.cpf_cnpj && <p className="text-muted-foreground">{t.clients.doc}: {client.cpf_cnpj}</p>}
            {!client.email && !client.phone && !client.address_line_1 && !client.cpf_cnpj && <p className="text-muted-foreground">Sem dados de contato.</p>}
          </div>
          <KPIStat label={t.clients.vessels} value={String(vessels?.length ?? 0)} />
          <KPIStat label={t.clients.serviceOrders} value={String(ordensQueContam.length)} />
        </div>

        {/* Acima das abas, igual ao V1: o que está pendente com o cliente aparece ao abrir a
            tela, sem exigir um clique. Some sozinho quando não há nada. */}
        <OpenLoopsPanel entityType="client" entityId={id} title="Em aberto com este cliente" />

        <Tabs defaultValue="vessels">
          <TabsList className="flex h-auto w-full flex-wrap justify-start">
            <TabsTrigger value="vessels">{t.clients.vessels}</TabsTrigger>
            <TabsTrigger value="orders">{t.clients.serviceOrders}</TabsTrigger>
            <TabsTrigger value="financial">{t.clients.financial}</TabsTrigger>
            <TabsTrigger value="tasks">Tarefas</TabsTrigger>
            <TabsTrigger value="history">Histórico</TabsTrigger>
          </TabsList>

          <TabsContent value="vessels" className="mt-4">
            {(!vessels || vessels.length === 0) ? (
              <p className="rounded-lg border bg-card py-8 text-center text-muted-foreground">{t.vessels.noVessels}</p>
            ) : (
              <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                {vessels.map((v) => {
                  // Só os campos do tipo (dono, 22/10/2026): motorhome em metros, sem vaga de píer e
                  // sem "Sem marina"; equipamento sem comprimento.
                  const campos = camposDoTipo(v.asset_type);
                  const comprimento = comprimentoDoTipo(v.length_feet, v.asset_type);
                  const local = (v as { marinas?: { name?: string } }).marinas?.name;
                  const vaga = campos.nauticos ? (v as { current_dock_position?: string | null }).current_dock_position : null;
                  return (
                    <Link key={v.id} to={`/v2/vessels/${v.id}`} className="rounded-lg border bg-card p-4 transition-colors hover:border-primary/50">
                      <div className="mb-1 flex items-start justify-between gap-2">
                        <span className="min-w-0">
                          <span className="flex items-center gap-2 truncate font-semibold"><IconeDaUnidade tipo={v.asset_type} className="h-4 w-4 shrink-0 text-accent" />{nomeDaUnidade(v)}</span>
                          <span className="block truncate text-sm text-muted-foreground">{v.manufacturer} {v.model} {v.year ? `(${v.year})` : ''}</span>
                        </span>
                        {comprimento && <span className="shrink-0 text-sm font-medium tabular-nums">{comprimento}</span>}
                      </div>
                      <p className="truncate text-xs text-muted-foreground">
                        {local || (campos.nauticos ? t.vessels.noMarina : 'Local não informado')}
                        {vaga ? ` · ${vaga}` : ''}
                      </p>
                    </Link>
                  );
                })}
              </div>
            )}
          </TabsContent>

          <TabsContent value="orders" className="mt-4 space-y-2">
            <DataTable<SORow>
              rows={orders ?? []}
              rowKey={(o) => o.id}
              columns={osColumns}
              density="compact"
              onRowClick={(o) => navigate(`/v2/service-orders/${o.id}`)}
              emptyMessage={t.common.noResults}
            />
            {ordensQueContam.length > 0 && (
              <p className="rounded-lg border bg-muted/40 px-4 py-2 text-sm">
                Total ({ordensQueContam.length} OS): <b className="tabular-nums">{formatCurrency(ordensQueContam.reduce((s, o) => s + (o.grand_total ?? 0), 0))}</b>
              </p>
            )}
          </TabsContent>

          <TabsContent value="financial" className="mt-4 space-y-2">
            <DataTable<RecRow>
              rows={clientReceivables ?? []}
              rowKey={(r) => r.id}
              columns={recColumns}
              density="compact"
              emptyMessage={t.clients.noFinancialRecords}
              // Escolher as contas → "Cobrar juntas" com as OS delas (Fase 0 do Fechar juntas).
              selectable={osParaCobrar.length > 0}
              bulkBar={(keys, limpar) => {
                const comSaldo = contasParaCobrar.filter((r) => keys.includes(r.id) && r.service_order_id && saldoDaConta(r) > 0);
                return (
                  <>
                    <span className="min-w-0 flex-1 truncate">
                      {keys.length === 1 ? '1 conta escolhida' : `${keys.length} contas escolhidas`}
                      {comSaldo.length === 0 ? ' · nenhuma com saldo de OS já executada' : ''}
                    </span>
                    <Button
                      variant="secondary" size="sm" className="h-7 shrink-0 gap-1.5"
                      disabled={comSaldo.length === 0}
                      onClick={() => abrirCobrarJuntas(keys)}
                    >
                      <Layers className="h-3.5 w-3.5" /> Cobrar juntas
                    </Button>
                    <Button variant="ghost" size="sm" className="h-7 shrink-0 text-background hover:text-foreground" onClick={limpar}>
                      Limpar
                    </Button>
                  </>
                );
              }}
            />
            {contasQueContam.length > 0 && (
              <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border bg-muted/40 px-4 py-2 text-sm">
                <span>Total ({contasQueContam.length} lançamentos): <b className="tabular-nums">{formatCurrency(recTotal)}</b></span>
                <span className="flex flex-wrap items-center gap-4 text-xs">
                  <span className="text-success">Pago: <b className="tabular-nums">{formatCurrency(recPaid)}</b></span>
                  <span className="text-warning">Em aberto: <b className="tabular-nums">{formatCurrency(recOpen)}</b></span>
                  {osParaCobrar.length >= 2 && (
                    <Button variant="outline" size="sm" className="h-7 gap-1.5" onClick={() => setCobrarJuntas([])}>
                      <Layers className="h-3.5 w-3.5" /> Cobrar juntas
                    </Button>
                  )}
                  <Button variant="outline" size="sm" className="h-7 gap-1.5" onClick={() => setStatementOpen(true)}>
                    <FileText className="h-3.5 w-3.5" /> Enviar extrato
                  </Button>
                </span>
              </div>
            )}
            {/* Quem paga por este cliente (leva 8): só administrador e financeiro — CPF de terceiro é dado pessoal. */}
            <PagadoresDoCliente clientId={id} clientName={client.name} />
          </TabsContent>

          <TabsContent value="tasks" className="mt-4">
            <EntityTasksPanel entityType="client" entityId={id} title="Tarefas deste cliente" />
          </TabsContent>

          <TabsContent value="history" className="mt-4">
            <div className="rounded-lg border bg-card p-4">
              <RecordHistory tableName="clients" recordId={id} />
            </div>
          </TabsContent>
        </Tabs>
      </PageShell>

      <ClientFormDialog open={editOpen} onOpenChange={setEditOpen} client={client} />
      <ClientStatementDialog
        open={statementOpen}
        onOpenChange={setStatementOpen}
        clientName={client.name}
        clientPhone={(client as any).whatsapp || client.phone}
        items={(clientReceivables ?? []) as any}
      />
      <CobrarJuntasDialog
        open={cobrarJuntas !== null}
        onOpenChange={(v) => { if (!v) setCobrarJuntas(null); }}
        cliente={{
          id: client.id,
          name: client.name,
          generico,
          opt_out_whatsapp: (client as { opt_out_whatsapp?: boolean | null }).opt_out_whatsapp,
          whatsapp: (client as { whatsapp?: string | null }).whatsapp,
          phone: client.phone,
        }}
        contas={contasParaCobrar}
        osIniciais={cobrarJuntas ?? []}
      />
    </V2Shell>
  );
}
