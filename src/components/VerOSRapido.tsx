// Ver a OS sem sair da tela (pedido do dono, 28/09/2026).
//
// Na fila do Extrato a despesa se liga a uma OS escolhida numa lista "número · cliente". Quando o
// mesmo cliente tem mais de uma OS, o número sozinho não diz qual é — e a despesa na OS errada
// estraga a margem das duas. O botão abre a OS numa janela SÓ DE LEITURA: barco, o que foi pedido,
// serviços e peças. Mudar a OS continua sendo na tela dela (o link abre em outra aba, para não
// perder o que já foi respondido na fila).
//
// A leitura é a mesma da tela da OS (useServiceOrder): quem só pode ver a OS sem valores (técnico)
// continua vendo sem valores.
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { ExternalLink, Eye } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusChip } from '@/v2/components/StatusChip';
import { serviceOrderStatusTone } from '@/v2/status-map';
import { useI18n } from '@/i18n';
import { useServiceOrder } from '@/hooks/use-service-orders';

/** Só o que a janela lê da OS (vem do mesmo select da tela da OS). */
interface OsParaConferir {
  service_order_number?: string | null;
  status?: string | null;
  created_at?: string | null;
  scheduled_start_at?: string | null;
  check_out_at?: string | null;
  problem_description?: string | null;
  grand_total?: number | string | null;
  clients?: { name?: string | null } | null;
  vessels?: { name?: string | null; manufacturer?: string | null; model?: string | null } | null;
  marinas?: { name?: string | null } | null;
  service_order_services?: Array<{
    id: string; quantity?: number | null; name_snapshot?: string | null; services?: { name?: string | null } | null;
  }> | null;
  service_order_parts?: Array<{
    id: string; quantity?: number | null; notes?: string | null; products?: { name?: string | null } | null;
  }> | null;
  service_order_technicians?: Array<{ id: string; app_users?: { full_name?: string | null } | null }> | null;
}

/** Botão "Ver OS" — some quando não há OS escolhida. */
export function BotaoVerOS({ osId, rotulo = 'Ver OS' }: { osId: string | null | undefined; rotulo?: string }) {
  const [aberta, setAberta] = useState(false);
  if (!osId) return null;
  return (
    <>
      <Button
        type="button" size="sm" variant="ghost" className="h-7 shrink-0 gap-1 px-2 text-xs"
        onClick={() => setAberta(true)} aria-label={`${rotulo} (só leitura)`}
      >
        <Eye className="h-3.5 w-3.5" />
        {rotulo}
      </Button>
      {aberta && <JanelaDaOS osId={osId} onFechar={() => setAberta(false)} />}
    </>
  );
}

export function JanelaDaOS({ osId, onFechar }: { osId: string; onFechar: () => void }) {
  const { data, isLoading, error } = useServiceOrder(osId);
  const { t, formatCurrency, formatDate } = useI18n();
  const statusLabels = (t.status ?? {}) as Record<string, string>;
  const os = data as unknown as OsParaConferir | null | undefined;

  const barco = os?.vessels
    ? [os.vessels.name, os.vessels.manufacturer, os.vessels.model].filter(Boolean).join(' · ')
    : '';
  const tecnicos = (os?.service_order_technicians ?? [])
    .map((x) => x.app_users?.full_name).filter(Boolean).join(', ');
  const servicos = os?.service_order_services ?? [];
  const pecas = os?.service_order_parts ?? [];
  const temValor = os?.grand_total !== undefined && os?.grand_total !== null;

  const linhas: Array<[string, string]> = os ? [
    ['Cliente', os.clients?.name ?? '—'],
    ...(barco ? [['Barco / motorhome', barco] as [string, string]] : []),
    ...(os.marinas?.name ? [['Local', os.marinas.name] as [string, string]] : []),
    ...(os.created_at ? [['Aberta em', formatDate(os.created_at)] as [string, string]] : []),
    ...(os.scheduled_start_at ? [['Agendada para', formatDate(os.scheduled_start_at)] as [string, string]] : []),
    ...(os.check_out_at ? [['Saída do técnico', formatDate(os.check_out_at)] as [string, string]] : []),
    ...(tecnicos ? [['Técnicos', tecnicos] as [string, string]] : []),
    ...(temValor ? [['Valor da OS', formatCurrency(Number(os.grand_total))] as [string, string]] : []),
  ] : [];

  return (
    <Dialog open onOpenChange={(v) => { if (!v) onFechar(); }}>
      <DialogContent className="max-h-[85dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex flex-wrap items-center gap-2">
            {os?.service_order_number ?? 'OS'}
            {os?.status && (
              <StatusChip tone={serviceOrderStatusTone[os.status] ?? 'neutral'}>
                {statusLabels[os.status] ?? os.status}
              </StatusChip>
            )}
          </DialogTitle>
          <DialogDescription>Só para conferir se é a OS certa. Para mudar alguma coisa, abra a OS.</DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-4 w-2/3" />
            <Skeleton className="h-4 w-1/2" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : error || !os ? (
          <p className="text-sm text-destructive">Não consegui abrir esta OS agora.</p>
        ) : (
          <div className="space-y-3 text-sm">
            <dl className="grid grid-cols-1 gap-x-3 gap-y-1 sm:grid-cols-[auto,1fr]">
              {linhas.map(([rotulo, valor]) => (
                <div key={rotulo} className="contents">
                  <dt className="text-muted-foreground">{rotulo}</dt>
                  <dd className="min-w-0 break-words font-medium">{valor}</dd>
                </div>
              ))}
            </dl>

            {os.problem_description && (
              <section>
                <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">O que foi pedido</h4>
                <p className="mt-1 line-clamp-6 whitespace-pre-line break-words">{os.problem_description}</p>
              </section>
            )}

            {servicos.length > 0 && (
              <section>
                <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Serviços ({servicos.length})</h4>
                <ul className="mt-1 list-disc space-y-0.5 pl-5">
                  {servicos.map((s) => (
                    <li key={s.id} className="break-words">
                      {s.quantity && Number(s.quantity) !== 1 ? `${Number(s.quantity)}× ` : ''}
                      {s.services?.name ?? s.name_snapshot ?? 'Serviço'}
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {pecas.length > 0 && (
              <section>
                <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Peças ({pecas.length})</h4>
                <ul className="mt-1 list-disc space-y-0.5 pl-5">
                  {pecas.map((p) => (
                    <li key={p.id} className="break-words">
                      {p.quantity ? `${Number(p.quantity)}× ` : ''}
                      {p.products?.name ?? p.notes ?? 'Peça'}
                    </li>
                  ))}
                </ul>
              </section>
            )}
          </div>
        )}

        <div className="flex justify-end pt-1">
          <Button asChild size="sm" variant="outline" className="gap-1">
            <Link to={`/v2/service-orders/${osId}`} target="_blank" rel="noreferrer">
              <ExternalLink className="h-3.5 w-3.5" />
              Abrir a OS em outra aba
            </Link>
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
