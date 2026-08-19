// [NFSE-PAGE] A casa da NFS-e — /fiscal/nfse (admin).
//
// Antes desta página a NFS-e vivia espalhada: emissão só pelo assistente "Faturar OS" e
// o histórico enterrado no fim da página de NF-e (3.500 linhas, marcada p/ decompor —
// MF-AUD-069). Aqui mora tudo: prontidão, emissão por OS, emissão avulsa e o histórico
// com número nacional, cancelamento e downloads — reusando a NfseSection inteira.
import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { NfseSection } from '@/components/fiscal/NfseSection';
import { FaturarOsDialog } from '@/components/fiscal/FaturarOsDialog';
import { NfseAvulsaDialog } from '@/components/fiscal/NfseAvulsaDialog';
import { EntityCombobox, type EntityOption } from '@/components/EntityCombobox';
import { useServiceOrders } from '@/hooks/use-service-orders';
import { useAmbienteFiscal } from '@/hooks/use-nfse';
import { statusConfig } from '@/lib/constants';
import { FilePlus2, Receipt } from 'lucide-react';

export default function NfsePage() {
  const { data: orders = [] } = useServiceOrders();
  const ambiente = useAmbienteFiscal();
  const [osId, setOsId] = useState('');
  const [faturarAberto, setFaturarAberto] = useState(false);
  const [avulsaAberta, setAvulsaAberta] = useState(false);

  // OS elegíveis: com serviço para faturar — draft (orçamento) e cancelada ficam fora.
  // Concluídas primeiro: é delas que a NFS-e normalmente nasce.
  const osOptions: EntityOption[] = useMemo(() => {
    const peso = (s: string) => (s === 'completed' ? 0 : s === 'invoiced' ? 1 : 2);
    return (orders as any[])
      .filter((o) => o.status !== 'draft' && o.status !== 'cancelled')
      .sort((a, b) => peso(a.status) - peso(b.status)
        || String(b.created_at ?? '').localeCompare(String(a.created_at ?? '')))
      .map((o) => ({
        value: o.id,
        label: `${o.service_order_number ?? o.id.slice(0, 8)} — ${o.clients?.name ?? 'sem cliente'}`,
        description: statusConfig[o.status as keyof typeof statusConfig]?.label ?? o.status,
        searchTerms: [o.clients?.name ?? ''],
      }));
  }, [orders]);

  const osSelecionada = (orders as any[]).find((o) => o.id === osId);

  return (
    <div className="mx-auto max-w-4xl space-y-6 p-4 md:p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Notas de Serviço (NFS-e)</h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Padrão nacional · Itajaí/SC. Serviço sai aqui; peça/produto sai na NF-e.
          </p>
        </div>
        <Button variant="outline" onClick={() => setAvulsaAberta(true)}>
          <FilePlus2 className="mr-2 h-4 w-4" />
          NFS-e avulsa (sem OS)
        </Button>
      </div>

      {/* FAIL-SAFE: só esconde o banner quando o servidor DISSE homologação — ambiente
          desconhecido é tratado como produção. */}
      {!ambiente.isLoading && ambiente.data !== 'homologacao' && (
        <div className="rounded-md border border-destructive/50 bg-destructive/5 p-2.5 text-sm font-medium text-destructive">
          ⚠ Ambiente de PRODUÇÃO — as emissões desta página são notas reais.
        </div>
      )}

      {/* Emitir a partir de uma OS: escolhe aqui e a seção abaixo passa a operar nela.
          O caminho completo (NFS-e + NF-e juntas, com checklist) é o assistente. */}
      <Card className="p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="min-w-64 flex-1">
            <Label>Ordem de Serviço</Label>
            <EntityCombobox
              value={osId}
              onChange={setOsId}
              options={osOptions}
              placeholder="Escolher OS para faturar…"
              className="mt-1"
            />
          </div>
          <Button
            disabled={!osId}
            onClick={() => setFaturarAberto(true)}
          >
            <Receipt className="mr-2 h-4 w-4" />
            Faturar OS (NFS-e + NF-e)
          </Button>
        </div>
        <p className="mt-2 text-xs text-muted-foreground">
          O botão abre o assistente com checklist dos DOIS documentos. O cartão "Emitir
          NFS-e da OS" logo abaixo emite só a nota de serviço.
        </p>
      </Card>

      <NfseSection serviceOrderId={osId || null} />

      <FaturarOsDialog
        open={faturarAberto}
        onOpenChange={setFaturarAberto}
        serviceOrderId={osId || null}
        orderNumber={osSelecionada?.service_order_number ?? null}
      />
      <NfseAvulsaDialog open={avulsaAberta} onOpenChange={setAvulsaAberta} />
    </div>
  );
}
