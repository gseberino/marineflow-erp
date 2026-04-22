import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { PenLine, FileSignature, AlertTriangle, ExternalLink, FileText } from 'lucide-react';

interface Props {
  serviceOrderId: string;
}

interface SignatureRow {
  id: string;
  accepted_name: string;
  signed_at: string;
  signature_image_url: string | null;
  signed_pdf_url: string | null;
  document_hash: string;
  ip_address: string | null;
  user_agent: string | null;
  superseded_at: string | null;
  superseded_reason: string | null;
  accepted_terms_snapshot: string | null;
}

export function ServiceOrderSignatures({ serviceOrderId }: Props) {
  const { data: signatures, isLoading } = useQuery({
    queryKey: ['so-signatures', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_order_signatures')
        .select('id, accepted_name, signed_at, signature_image_url, signed_pdf_url, document_hash, ip_address, user_agent, superseded_at, superseded_reason, accepted_terms_snapshot')
        .eq('service_order_id', serviceOrderId)
        .order('signed_at', { ascending: false });
      if (error) throw error;
      return data as SignatureRow[];
    },
    enabled: !!serviceOrderId,
  });

  if (isLoading) {
    return <p className="text-sm text-muted-foreground">Carregando assinaturas...</p>;
  }

  if (!signatures || signatures.length === 0) {
    return (
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <FileSignature className="h-4 w-4" />
        Nenhuma assinatura registrada ainda.
      </div>
    );
  }

  const active = signatures.filter((s) => !s.superseded_at);
  const superseded = signatures.filter((s) => !!s.superseded_at);

  return (
    <div className="space-y-4">
      {active.map((sig) => (
        <SignatureCard key={sig.id} sig={sig} status="active" />
      ))}
      {superseded.length > 0 && (
        <details className="rounded-lg border border-dashed p-3">
          <summary className="cursor-pointer text-sm font-medium text-muted-foreground">
            Assinaturas superadas ({superseded.length})
          </summary>
          <div className="mt-3 space-y-3">
            {superseded.map((sig) => (
              <SignatureCard key={sig.id} sig={sig} status="superseded" />
            ))}
          </div>
        </details>
      )}
    </div>
  );
}

function SignatureCard({ sig, status }: { sig: SignatureRow; status: 'active' | 'superseded' }) {
  const isSuperseded = status === 'superseded';
  return (
    <div
      className={`rounded-lg border p-4 space-y-3 ${
        isSuperseded ? 'bg-muted/40 opacity-70' : 'bg-card'
      }`}
    >
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-2">
          <PenLine className={`h-4 w-4 ${isSuperseded ? 'text-muted-foreground' : 'text-success'}`} />
          <div>
            <p className="text-sm font-medium">{sig.accepted_name}</p>
            <p className="text-xs text-muted-foreground">
              {new Date(sig.signed_at).toLocaleString('pt-BR')}
            </p>
          </div>
        </div>
        {isSuperseded && (
          <div className="flex items-center gap-1 text-xs text-warning">
            <AlertTriangle className="h-3.5 w-3.5" />
            Superada {sig.superseded_reason ? `— ${sig.superseded_reason}` : ''}
          </div>
        )}
      </div>

      {sig.signature_image_url ? (
        <a
          href={sig.signature_image_url}
          target="_blank"
          rel="noopener noreferrer"
          className="block rounded-md border bg-background p-2 hover:border-accent transition-colors"
        >
          <img
            src={sig.signature_image_url}
            alt={`Assinatura de ${sig.accepted_name}`}
            className="h-24 w-auto mx-auto object-contain"
            loading="lazy"
          />
          <p className="mt-1 flex items-center justify-center gap-1 text-xs text-muted-foreground">
            <ExternalLink className="h-3 w-3" />
            Abrir imagem original
          </p>
        </a>
      ) : (
        <p className="text-xs text-muted-foreground italic">Imagem da assinatura indisponível.</p>
      )}

      {sig.signed_pdf_url ? (
        <a
          href={sig.signed_pdf_url}
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center justify-between gap-2 rounded-md border bg-primary/5 hover:bg-primary/10 transition-colors p-3"
        >
          <div className="flex items-center gap-2">
            <FileText className="h-4 w-4 text-primary" />
            <div>
              <p className="text-xs font-medium text-foreground">PDF arquivado da OS</p>
              <p className="text-[11px] text-muted-foreground">Documento imutável no momento da assinatura — prova jurídica</p>
            </div>
          </div>
          <ExternalLink className="h-4 w-4 text-muted-foreground" />
        </a>
      ) : (
        <p className="text-xs text-muted-foreground italic">
          PDF arquivado indisponível para esta assinatura (assinatura registrada antes da arquivação automática).
        </p>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs text-muted-foreground">
        <div>
          <span className="font-medium text-foreground">Hash do documento:</span>{' '}
          <code className="break-all">{sig.document_hash.slice(0, 24)}…</code>
        </div>
        {sig.ip_address && (
          <div>
            <span className="font-medium text-foreground">IP:</span> {sig.ip_address}
          </div>
        )}
        {sig.user_agent && (
          <div className="sm:col-span-2 truncate" title={sig.user_agent}>
            <span className="font-medium text-foreground">Dispositivo:</span> {sig.user_agent}
          </div>
        )}
      </div>
    </div>
  );
}
