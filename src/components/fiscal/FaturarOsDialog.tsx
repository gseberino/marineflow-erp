// [FATURAR-OS] Assistente "Faturar OS" — NFS-e (serviços) + NF-e (peças) em um clique.
//
// Componente separado da FiscalEmission de propósito (mesma razão do NfseSection: a página
// tem 3.500+ linhas e está marcada para decompor, MF-AUD-069).
//
// O desenho copia o padrão vencedor dos ERPs de mercado (pesquisa 13/08/2026 — SIGE Cloud,
// Omie): nenhum ERP emite "nota única" para OS mista; o um-clique é um assistente com
// (1) checklist bloqueante ANTES — aqui, a action billing_preflight, que valida os dois
//     payloads sem emitir, sem numeração e sem cota, e diz QUAL dado falta;
// (2) emissão em etapas INDEPENDENTES — NFS-e autorizada não é desfeita se a NF-e falhar
//     (cancelamento de NFS-e tem prazo municipal curto; rollback automático é armadilha);
// (3) status POR DOCUMENTO depois, com repetição individual.
import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { useI18n } from '@/i18n';
import { supabase } from '@/integrations/supabase/client';
import { useNfseHealth, useEmitirNfse } from '@/hooks/use-nfse';
import {
  useBillingPreflight, useEmitirNfeDaOs, atualizarInvoicingStatus,
  type PreflightDocumento, type DocumentoDaOs,
} from '@/hooks/use-faturar-os';
import {
  AlertTriangle, CheckCircle2, FileText, Loader2, Package, Wrench, ExternalLink, RefreshCw,
} from 'lucide-react';
import { toast } from 'sonner';
import { useQueryClient } from '@tanstack/react-query';

type ResultadoEmissao =
  | { fase: 'idle' }
  | { fase: 'emitindo' }
  | { fase: 'ok'; reused?: boolean }
  | { fase: 'erro'; mensagem: string };

const STATUS_VIVO = ['draft', 'queued', 'processing', 'authorized'];

export function FaturarOsDialog({ open, onOpenChange, serviceOrderId, orderNumber }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  serviceOrderId: string | null;
  orderNumber?: string | null;
}) {
  const { formatCurrency } = useI18n();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const preflight = useBillingPreflight(serviceOrderId, open);
  // Só consulta a Contora com o diálogo aberto — este componente fica montado (fechado)
  // nas listas, e cada health é um round-trip real ao provedor.
  const health = useNfseHealth(open);
  const emitirNfse = useEmitirNfse();
  const emitirNfe = useEmitirNfeDaOs();

  const [resNfse, setResNfse] = useState<ResultadoEmissao>({ fase: 'idle' });
  const [resNfe, setResNfe] = useState<ResultadoEmissao>({ fase: 'idle' });

  // Reabrir o assistente para OUTRA OS (ou de novo para a mesma) zera o placar.
  useEffect(() => {
    if (open) {
      setResNfse({ fase: 'idle' });
      setResNfe({ fase: 'idle' });
    }
  }, [open, serviceOrderId]);

  const d = preflight.data;
  const docs = d?.documentos ?? [];
  const docVivo = (tipo: string): DocumentoDaOs | undefined =>
    docs.find((x) => x.document_type === tipo && STATUS_VIVO.includes(x.status));

  const nfseJaEmitida = !!docVivo('nfse');
  const nfeJaEmitida = !!docVivo('nfe');

  const nfseSaudavel = health.data?.pronto === true;
  const podeEmitirNfse = !!d?.nfse.aplicavel && !!d?.nfse.pronto && nfseSaudavel
    && !nfseJaEmitida && resNfse.fase !== 'ok';
  const podeEmitirNfe = !!d?.nfe.aplicavel && !!d?.nfe.pronto
    && !nfeJaEmitida && resNfe.fase !== 'ok';

  const emitindo = resNfse.fase === 'emitindo' || resNfe.fase === 'emitindo';

  const aposEmissao = async () => {
    if (!serviceOrderId || !d) return;
    try {
      await atualizarInvoicingStatus(serviceOrderId, {
        nfse: d.nfse.aplicavel,
        nfe: d.nfe.aplicavel,
      });
    } catch {
      // best-effort: o marcador não pode impedir a emissão de aparecer
    }
    qc.invalidateQueries({ queryKey: ['service-orders'] });
    qc.invalidateQueries({ queryKey: ['nfse-documentos'] });
    qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
    await preflight.refetch();
  };

  const rodarNfse = async (): Promise<boolean> => {
    if (!serviceOrderId) return false;
    setResNfse({ fase: 'emitindo' });
    try {
      await emitirNfse.mutateAsync({ serviceOrderId });
      setResNfse({ fase: 'ok' });
      return true;
    } catch (e) {
      setResNfse({ fase: 'erro', mensagem: e instanceof Error ? e.message : String(e) });
      return false;
    }
  };

  const rodarNfe = async (): Promise<boolean> => {
    if (!serviceOrderId) return false;
    setResNfe({ fase: 'emitindo' });
    try {
      await emitirNfe.mutateAsync({ serviceOrderId });
      setResNfe({ fase: 'ok' });
      return true;
    } catch (e) {
      setResNfe({ fase: 'erro', mensagem: e instanceof Error ? e.message : String(e) });
      return false;
    }
  };

  // O "um clique": emite os documentos aplicáveis em sequência, cada um por si.
  const emitirTudo = async () => {
    const fazerNfse = podeEmitirNfse;
    const fazerNfe = podeEmitirNfe;
    let okNfse = !fazerNfse;
    let okNfe = !fazerNfe;
    if (fazerNfse) okNfse = await rodarNfse();
    if (fazerNfe) okNfe = await rodarNfe();
    await aposEmissao();
    if (okNfse && okNfe) {
      toast.success('Documentos da OS enviados para emissão. Acompanhe o status de cada um.');
    } else {
      toast.warning('Parte dos documentos falhou — veja o erro no cartão e repita só o que faltou.');
    }
  };

  // Caminho de conferência campo a campo da NF-e: a página de emissão pré-preenchida
  // (o fluxo invoiceFrom que já existia). Serve para editar impostos/desconto por item.
  const abrirEmissaoDetalhada = async () => {
    if (!serviceOrderId) return;
    try {
      const [{ data: so }, { data: parts }] = await Promise.all([
        supabase.from('service_orders')
          .select('id, client_id, customer_po_number, customer_buyer_name, requested_by_name, service_order_number')
          .eq('id', serviceOrderId).maybeSingle(),
        supabase.from('service_order_parts')
          .select('product_id, quantity, unit_sale_snapshot')
          .eq('service_order_id', serviceOrderId),
      ]);
      const items = (parts ?? [])
        .filter((p) => p.product_id)
        .map((p) => ({
          productId: p.product_id as string,
          quantity: Number(p.quantity) || 0,
          unitPrice: Number(p.unit_sale_snapshot) || 0,
        }));
      if (!items.length) {
        toast.error('Esta OS não tem produtos para a NF-e.');
        return;
      }
      onOpenChange(false);
      navigate('/fiscal/emissao', {
        state: {
          invoiceFrom: {
            serviceOrderId,
            clientId: so?.client_id ?? null,
            items,
            purchaseOrder: so?.customer_po_number || '',
            buyerName: so?.customer_buyer_name || so?.requested_by_name || '',
            orderNumber: so?.service_order_number || null,
          },
        },
      });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Erro ao preparar a emissão detalhada');
    }
  };

  const resumoNfse = d?.nfse.resumo as
    | { servicos_na_nota?: number; total_servicos?: number; codigo_de_tributacao?: string; origem_do_codigo?: string }
    | undefined;
  const resumoNfe = d?.nfe.resumo as
    | { pecas_na_nota?: number; total_pecas?: number; itens_ignorados_sem_cadastro?: number }
    | undefined;

  const pendenciasNfseConta = useMemo(() => {
    if (!d?.nfse.aplicavel) return [];
    return [
      ...(health.data?.pendencias_locais ?? []),
      ...(health.data?.contora?.pending ?? []),
    ];
  }, [d?.nfse.aplicavel, health.data]);

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!emitindo) onOpenChange(o); }}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle>Faturar OS {orderNumber ?? d?.os.numero ?? ''}</DialogTitle>
          <DialogDescription>
            Serviço sai na <strong>NFS-e</strong> (prefeitura) e peça sai na <strong>NF-e</strong>{' '}
            (SEFAZ) — dois documentos, numerações separadas, como a lei manda para OS mista.
          </DialogDescription>
        </DialogHeader>

        {d?.ambiente === 'producao' && (
          <div className="rounded-md border border-destructive/50 bg-destructive/5 p-2 text-sm font-medium text-destructive">
            ⚠ Ambiente de PRODUÇÃO — os documentos emitidos aqui são notas reais.
          </div>
        )}

        {preflight.isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-28 w-full" />
            <Skeleton className="h-28 w-full" />
          </div>
        ) : preflight.error ? (
          <Card className="border-destructive/40 p-4">
            <p className="text-sm text-destructive break-words">
              Não deu para verificar a OS: {preflight.error.message}
            </p>
          </Card>
        ) : d ? (
          <div className="space-y-3">
            <CartaoDocumento
              icone={<Wrench className="h-4 w-4" />}
              titulo="NFS-e — serviços"
              doc={d.nfse}
              docExistente={docVivo('nfse')}
              resultado={resNfse}
              linhaResumo={resumoNfse
                ? `${resumoNfse.servicos_na_nota} serviço(s) · ${formatCurrency(Number(resumoNfse.total_servicos ?? 0))} · código ${resumoNfse.codigo_de_tributacao}${resumoNfse.origem_do_codigo === 'verbo' ? ' (herdado do verbo)' : ''}`
                : null}
              pendenciasExtra={pendenciasNfseConta}
              aguardandoConta={d.nfse.aplicavel && health.isLoading}
              onEmitir={podeEmitirNfse ? async () => { await rodarNfse(); await aposEmissao(); } : undefined}
            />

            <CartaoDocumento
              icone={<Package className="h-4 w-4" />}
              titulo="NF-e — peças"
              doc={d.nfe}
              docExistente={docVivo('nfe')}
              resultado={resNfe}
              linhaResumo={resumoNfe
                ? `${resumoNfe.pecas_na_nota} peça(s) · ${formatCurrency(Number(resumoNfe.total_pecas ?? 0))}${Number(resumoNfe.itens_ignorados_sem_cadastro ?? 0) > 0 ? ` · ${resumoNfe.itens_ignorados_sem_cadastro} item(ns) fora por falta de cadastro` : ''}`
                : null}
              onEmitir={podeEmitirNfe ? async () => { await rodarNfe(); await aposEmissao(); } : undefined}
              rodape={d.nfe.aplicavel ? (
                <button
                  type="button"
                  className="inline-flex items-center gap-1 text-xs text-muted-foreground underline-offset-2 hover:underline"
                  onClick={abrirEmissaoDetalhada}
                >
                  <ExternalLink className="h-3 w-3" />
                  Conferir campo a campo na página de emissão (impostos, desconto, parcelas)
                </button>
              ) : null}
            />

            <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
              <Button
                variant="outline" size="sm"
                onClick={() => {
                  // Reverifica TAMBÉM a saúde da conta (o gate da NFS-e) — só refazer o
                  // preflight deixava uma pendência de conta resolvida presa no cache.
                  qc.invalidateQueries({ queryKey: ['nfse-health'] });
                  preflight.refetch();
                }}
                disabled={preflight.isFetching || emitindo}
              >
                <RefreshCw className={`mr-1.5 h-4 w-4 ${preflight.isFetching ? 'animate-spin' : ''}`} />
                Reverificar pendências
              </Button>
              <div className="flex gap-2">
                <Button variant="outline" onClick={() => onOpenChange(false)} disabled={emitindo}>
                  Agora não
                </Button>
                <Button
                  onClick={emitirTudo}
                  disabled={emitindo || (!podeEmitirNfse && !podeEmitirNfe)}
                >
                  {emitindo
                    ? <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    : <FileText className="mr-2 h-4 w-4" />}
                  {podeEmitirNfse && podeEmitirNfe
                    ? 'Emitir NFS-e + NF-e'
                    : podeEmitirNfse
                      ? 'Emitir NFS-e'
                      : podeEmitirNfe
                        ? 'Emitir NF-e'
                        : 'Nada a emitir'}
                </Button>
              </div>
            </div>
          </div>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}

function CartaoDocumento({ icone, titulo, doc, docExistente, resultado, linhaResumo, pendenciasExtra = [], aguardandoConta = false, onEmitir, rodape }: {
  icone: React.ReactNode;
  titulo: string;
  doc: PreflightDocumento;
  docExistente?: DocumentoDaOs;
  resultado: ResultadoEmissao;
  linhaResumo?: string | null;
  pendenciasExtra?: string[];
  aguardandoConta?: boolean;
  onEmitir?: () => void | Promise<void>;
  rodape?: React.ReactNode;
}) {
  if (!doc.aplicavel) {
    return (
      <Card className="p-3 opacity-70">
        <div className="flex items-center gap-2 text-sm">
          {icone}
          <span className="font-medium">{titulo}</span>
          <Badge variant="outline" className="ml-auto shrink-0">não se aplica</Badge>
        </div>
        <p className="mt-1 text-xs text-muted-foreground">{doc.motivo}</p>
      </Card>
    );
  }

  const emitida = !!docExistente || resultado.fase === 'ok';
  // AVISO informa sem pintar o cartão de pendência — mesma convenção do servidor.
  const pendenciasBloqueantes = pendenciasExtra.filter((p) => !p.startsWith('AVISO:'));
  const comErro = !!doc.erro || resultado.fase === 'erro' || pendenciasBloqueantes.length > 0;

  return (
    <Card className={`p-3 ${emitida ? 'border-success/40' : comErro ? 'border-amber-500/40' : ''}`}>
      <div className="flex items-center gap-2 text-sm">
        {icone}
        <span className="font-medium">{titulo}</span>
        <span className="ml-auto shrink-0">
          {emitida ? (
            <Badge className="bg-success/15 text-success">
              {docExistente
                ? `emitida — nº ${docExistente.provider_status?.nfse_number ?? docExistente.provider_status?.display_number ?? docExistente.number ?? '…'} · ${docExistente.status}${docExistente.environment === 'homologacao' ? ' · homolog.' : ''}`
                : 'enviada para emissão'}
            </Badge>
          ) : resultado.fase === 'emitindo' ? (
            <Badge variant="outline"><Loader2 className="mr-1 h-3 w-3 animate-spin" />emitindo…</Badge>
          ) : doc.pronto && !comErro ? (
            <Badge variant="outline" className="text-success"><CheckCircle2 className="mr-1 h-3 w-3" />pronta para emitir</Badge>
          ) : (
            <Badge variant="outline" className="text-amber-600"><AlertTriangle className="mr-1 h-3 w-3" />pendências</Badge>
          )}
        </span>
      </div>

      {linhaResumo && <p className="mt-1.5 text-sm">{linhaResumo}</p>}

      {aguardandoConta && (
        <p className="mt-1.5 text-xs text-muted-foreground">Verificando a conta na Contora…</p>
      )}

      {resultado.fase === 'erro' && (
        <div className="mt-2 rounded-md border border-destructive/40 bg-destructive/5 p-2">
          <p className="text-sm text-destructive break-words">{resultado.mensagem}</p>
          {onEmitir && (
            <Button size="sm" variant="outline" className="mt-2" onClick={onEmitir}>
              Tentar de novo
            </Button>
          )}
        </div>
      )}

      {resultado.fase !== 'erro' && doc.erro && !emitida && (
        <div className="mt-2 rounded-md border border-amber-500/40 bg-amber-500/5 p-2">
          <p className="text-sm break-words">{doc.erro}</p>
          {doc.details?.servicos_sem_cadastro?.length ? (
            <ul className="mt-1 list-inside list-disc text-xs text-muted-foreground">
              {doc.details.servicos_sem_cadastro.map((s) => <li key={s}>{s}</li>)}
            </ul>
          ) : null}
        </div>
      )}

      {pendenciasExtra.length > 0 && !emitida && (
        <ul className="mt-2 space-y-1">
          {pendenciasExtra.map((p, i) => (
            <li key={i} className="flex gap-2 text-xs text-muted-foreground">
              <span className={p.startsWith('AVISO:') ? 'text-muted-foreground' : 'text-amber-600'}>•</span>
              <span className="min-w-0">{p}</span>
            </li>
          ))}
        </ul>
      )}

      {rodape && <div className="mt-2">{rodape}</div>}
    </Card>
  );
}
