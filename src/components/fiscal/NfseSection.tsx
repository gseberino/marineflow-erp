// [F-NFSE-01] Seção de NFS-e — serviço, não produto.
//
// Componente SEPARADO de propósito. A FiscalEmission tem 3.505 linhas e está registrada
// como MF-AUD-069 (decompor) — enfiar a NFS-e lá dentro engordaria o arquivo que já é o
// problema. Aqui ela nasce isolada e testável, e a página só a monta.
//
// NADA DE EMITIR ANTES DO PRE-FLIGHT VERDE. A NFS-e tem dois caminhos (padrão nacional ×
// layout municipal) e quem decide é o MUNICÍPIO, não o regime da empresa. Descobrir isso
// por tentativa e erro custa numeração fiscal a cada tentativa — por isso o botão de emitir
// só acende depois do health.
import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Skeleton } from '@/components/ui/skeleton';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { useI18n } from '@/i18n';
import {
  useNfseHealth, useNfseDocumentos, useEmitirNfse, useCancelarNfse,
  useArtefatoNfse, useAtualizarStatusNfse, numeroNacionalNfse,
  MIN_JUSTIFICATIVA, MAX_JUSTIFICATIVA,
  type DocumentoNfse,
} from '@/hooks/use-nfse';
import {
  Stethoscope, AlertTriangle, CheckCircle2, FileText, Download, Ban,
  RefreshCw, Loader2,
} from 'lucide-react';

export function NfseSection({ serviceOrderId }: { serviceOrderId?: string | null }) {
  const { formatCurrency, formatDate } = useI18n();
  const health = useNfseHealth();
  const documentos = useNfseDocumentos();
  const emitir = useEmitirNfse();
  const atualizar = useAtualizarStatusNfse();
  const [cancelando, setCancelando] = useState<DocumentoNfse | null>(null);
  // Emissão por OS exige CONFIRMAÇÃO — era o último caminho que emitia nota (real, em
  // produção) num clique só, sem conferência.
  const [confirmandoEmissao, setConfirmandoEmissao] = useState(false);

  const pronto = health.data?.pronto === true;

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">NFS-e — Nota Fiscal de Serviço</h2>
        <p className="mt-0.5 text-sm text-muted-foreground">
          Documento de <strong>serviço</strong>. As peças da OS continuam na NF-e — são
          documentos diferentes, com numerações diferentes.
        </p>
      </div>

      <PainelDeProntidao health={health} />

      {pronto && (
        <Card className="p-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="min-w-0">
              <p className="font-medium">Emitir NFS-e</p>
              <p className="text-sm text-muted-foreground">
                {serviceOrderId
                  ? 'A partir dos serviços desta OS. As peças não entram.'
                  : 'Use "Faturar (NFS-e + NF-e)" na lista de OS/Orçamentos — ou conclua a OS, que o assistente abre sozinho.'}
              </p>
            </div>
            <Button
              disabled={!serviceOrderId || emitir.isPending}
              onClick={() => serviceOrderId && setConfirmandoEmissao(true)}
            >
              {emitir.isPending
                ? <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                : <FileText className="mr-2 h-4 w-4" />}
              Emitir NFS-e da OS
            </Button>
          </div>
        </Card>
      )}

      {/* Confirmação da emissão por OS — em produção é nota real e o cancelamento tem
          prazo municipal; um clique só não basta. */}
      <AlertDialog open={confirmandoEmissao} onOpenChange={setConfirmandoEmissao}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Emitir a NFS-e desta OS?</AlertDialogTitle>
            <AlertDialogDescription>
              A nota sai com TODOS os serviços da OS consolidados (as peças ficam de fora —
              elas são NF-e). No ambiente de produção a nota é real e o cancelamento tem
              prazo curto definido pelo município.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Voltar</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                setConfirmandoEmissao(false);
                if (serviceOrderId) emitir.mutate({ serviceOrderId });
              }}
            >
              Emitir
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <div>
        <div className="mb-2 flex items-center justify-between">
          <h3 className="font-semibold">Notas de serviço</h3>
          <Button
            variant="outline" size="sm"
            onClick={() => atualizar.mutate()}
            disabled={atualizar.isPending}
          >
            <RefreshCw className={`mr-1.5 h-4 w-4 ${atualizar.isPending ? 'animate-spin' : ''}`} />
            Atualizar status
          </Button>
        </div>

        {documentos.isLoading ? (
          <div className="space-y-2">{[0, 1].map((i) => <Skeleton key={i} className="h-16" />)}</div>
        ) : documentos.error ? (
          <Card className="border-destructive/40 p-4">
            <p className="text-sm text-destructive break-words">
              Não deu para carregar as notas: {documentos.error.message}
            </p>
          </Card>
        ) : (documentos.data?.length ?? 0) === 0 ? (
          <Card className="p-6 text-center text-sm text-muted-foreground">
            Nenhuma NFS-e emitida ainda.
          </Card>
        ) : (
          <div className="space-y-2">
            {documentos.data!.map((d) => (
              <LinhaDaNota
                key={d.id}
                doc={d}
                onCancelar={() => setCancelando(d)}
                formatCurrency={formatCurrency}
                formatDate={formatDate}
              />
            ))}
          </div>
        )}
      </div>

      <DialogoDeCancelamento
        doc={cancelando}
        onFechar={() => setCancelando(null)}
      />
    </div>
  );
}

/**
 * Pré-voo. Mostra o que falta ANTES da primeira emissão, em vez de deixar a pessoa
 * descobrir pelo código de rejeição da prefeitura.
 */
function PainelDeProntidao({ health }: { health: ReturnType<typeof useNfseHealth> }) {
  if (health.isLoading) return <Skeleton className="h-28 w-full" />;

  if (health.error) {
    return (
      <Card className="border-destructive/40 p-4">
        <div className="flex items-start gap-3">
          <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-destructive" />
          <div className="min-w-0">
            <p className="font-semibold">Não deu para consultar a prontidão</p>
            <p className="mt-1 text-sm text-muted-foreground break-words">{health.error.message}</p>
          </div>
        </div>
      </Card>
    );
  }

  const d = health.data;
  const pendencias = [
    ...(d?.pendencias_locais ?? []),
    ...(d?.contora?.pending ?? []),
  ];

  return (
    <Card className={`p-4 ${d?.pronto ? 'border-success/40' : 'border-amber-500/40'}`}>
      <div className="flex items-start gap-3">
        {d?.pronto
          ? <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-success" />
          : <Stethoscope className="mt-0.5 h-5 w-5 shrink-0 text-amber-600" />}
        <div className="min-w-0 flex-1">
          <p className="font-semibold">
            {d?.pronto ? 'Pronto para emitir NFS-e' : 'Ainda não dá para emitir'}
          </p>

          <div className="mt-1 flex flex-wrap gap-2 text-xs">
            {d?.contora?.standard && (
              <Badge variant="outline">
                caminho ativo: {d.contora.standard}
              </Badge>
            )}
            {d?.contora?.city_name && <Badge variant="outline">{d.contora.city_name}</Badge>}
            {d?.contora?.certificate_ok && (
              <Badge variant="outline" className="text-success">
                certificado ok
                {d.contora.certificate_valid_until ? ` até ${d.contora.certificate_valid_until}` : ''}
              </Badge>
            )}
          </div>

          {d?.divergencia_de_padrao && (
            <p className="mt-2 rounded-md border border-amber-500/40 bg-amber-500/5 p-2 text-sm">
              {d.divergencia_de_padrao} Qual vale é decisão fiscal — confira antes de emitir.
            </p>
          )}

          {pendencias.length > 0 && (
            <ul className="mt-2 space-y-1.5">
              {pendencias.map((p, i) => (
                <li key={i} className="flex gap-2 text-sm">
                  <span className="text-amber-600">•</span>
                  <span className="min-w-0">{p}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </Card>
  );
}

function LinhaDaNota({ doc, onCancelar, formatCurrency, formatDate }: {
  doc: DocumentoNfse;
  onCancelar: () => void;
  formatCurrency: (n: number) => string;
  formatDate: (d: string) => string;
}) {
  const artefato = useArtefatoNfse();
  const cor: Record<string, string> = {
    authorized: 'bg-success/15 text-success',
    cancelled: 'bg-muted text-muted-foreground',
    rejected: 'bg-destructive/10 text-destructive',
    failed: 'bg-destructive/10 text-destructive',
  };

  return (
    <Card className="p-3">
      <div className="flex flex-wrap items-center gap-3">
        <div className="min-w-0 flex-1">
          {/* O número que vale é o NACIONAL (gerado pela Sefin na autorização); o RPS é a
              nossa numeração interna de envio. Antes de autorizar só existe o RPS. */}
          <p className="truncate font-medium">
            {numeroNacionalNfse(doc)
              ? <>NFS-e nº {numeroNacionalNfse(doc)} <span className="font-normal text-muted-foreground">· RPS {doc.number ?? '—'}/{doc.series ?? '—'}</span></>
              : <>RPS {doc.number ?? '—'} · série {doc.series ?? '—'}</>}
          </p>
          <p className="truncate text-xs text-muted-foreground">
            {doc.created_at ? formatDate(doc.created_at) : ''}
            {doc.environment === 'homologacao' && ' · homologação (sem valor fiscal)'}
            {doc.status_message ? ` · ${doc.status_message}` : ''}
          </p>
        </div>

        <Badge className={`shrink-0 ${cor[doc.status] ?? 'bg-secondary'}`}>{doc.status}</Badge>

        {doc.status === 'authorized' && (
          <>
            <Button
              size="sm" variant="outline" className="shrink-0"
              onClick={() => artefato.mutate({ documentId: doc.id, tipo: 'xml', numero: doc.number, serie: doc.series })}
              disabled={artefato.isPending}
            >
              <Download className="mr-1.5 h-4 w-4" />XML
            </Button>
            <Button
              size="sm" variant="outline" className="shrink-0"
              onClick={() => artefato.mutate({ documentId: doc.id, tipo: 'pdf', numero: doc.number, serie: doc.series })}
              disabled={artefato.isPending}
            >
              <Download className="mr-1.5 h-4 w-4" />DANFSe
            </Button>
            <Button size="sm" variant="outline" className="shrink-0" onClick={onCancelar}>
              <Ban className="mr-1.5 h-4 w-4" />Cancelar
            </Button>
          </>
        )}
      </div>
    </Card>
  );
}

function DialogoDeCancelamento({ doc, onFechar }: {
  doc: DocumentoNfse | null;
  onFechar: () => void;
}) {
  const cancelar = useCancelarNfse();
  const [motivo, setMotivo] = useState('');
  const tamanho = motivo.trim().length;
  const valido = tamanho >= MIN_JUSTIFICATIVA && tamanho <= MAX_JUSTIFICATIVA;

  return (
    <AlertDialog open={!!doc} onOpenChange={(o) => { if (!o) { setMotivo(''); onFechar(); } }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            Cancelar NFS-e {doc && numeroNacionalNfse(doc) ? `nº ${numeroNacionalNfse(doc)}` : `(RPS ${doc?.number})`}
          </AlertDialogTitle>
          <AlertDialogDescription asChild>
            <div className="space-y-2">
              <p>
                A justificativa vai para a prefeitura e fica no documento. Entre{' '}
                {MIN_JUSTIFICATIVA} e {MAX_JUSTIFICATIVA} caracteres.
              </p>
              <p className="text-xs">
                Nem toda prefeitura cancela por sistema. Onde não cancela, a nota continua
                autorizada e o cancelamento é feito no portal — o sistema avisa se for o caso.
              </p>
            </div>
          </AlertDialogDescription>
        </AlertDialogHeader>

        <Textarea
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          placeholder="Ex.: Serviço cancelado a pedido do cliente antes da execução."
          rows={3}
        />
        {/* O contador aparece SEMPRE, não só quando erra: assim a pessoa vê a faixa
            enquanto escreve, em vez de descobrir o limite ao ser barrada. */}
        <p className={`text-xs ${valido ? 'text-muted-foreground' : 'text-amber-600'}`}>
          {tamanho} de {MIN_JUSTIFICATIVA}–{MAX_JUSTIFICATIVA} caracteres
        </p>

        <AlertDialogFooter>
          <AlertDialogCancel>Voltar</AlertDialogCancel>
          <AlertDialogAction
            disabled={!valido || cancelar.isPending}
            onClick={(e) => {
              e.preventDefault();
              if (!doc) return;
              cancelar.mutate(
                { documentId: doc.id, motivo: motivo.trim() },
                { onSuccess: () => { setMotivo(''); onFechar(); } },
              );
            }}
          >
            Cancelar a nota
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
