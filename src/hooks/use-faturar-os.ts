// [FATURAR-OS] Faturamento da OS em um clique: NFS-e (serviços) + NF-e (peças).
//
// O desenho segue o padrão dos ERPs de mercado (SIGE/Omie, pesquisado em 13/08/2026):
// etapas INDEPENDENTES com checklist bloqueante antes, status por documento depois e
// NUNCA rollback automático — cancelamento de NFS-e tem prazo municipal curto e não é
// ferramenta de desfazer. Se um documento falha, o outro fica de pé e o que falhou
// mostra o erro com botão de repetir.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { chamarFiscalEmit } from '@/hooks/use-nfse';

export interface PreflightDocumento {
  aplicavel: boolean;
  pronto: boolean;
  motivo?: string;
  erro?: string;
  details?: {
    servicos_sem_cadastro?: string[];
    codigos_encontrados?: string[];
    /**
     * Acionável nos DOIS casos:
     *  · `service_id` → abre o cadastro do serviço no popup;
     *  · `service_id` null (linha digitada à mão) → `line_id` deixa gravar o
     *    verbo fiscal na PRÓPRIA LINHA, sem sair do assistente.
     *
     * `line_id` é opcional porque o servidor antigo não o mandava — uma tela
     * nova contra um edge não deployado deve degradar, não quebrar.
     */
    servicos_pendentes?: Array<{ service_id: string | null; line_id?: string | null; name: string }>;
    /** Acionável: abre o cadastro do produto no popup (falta NCM etc.). */
    produtos_pendentes?: Array<{ product_id: string; name: string; faltas: string[] }>;
  } | null;
  resumo?: Record<string, unknown> | null;
}

export interface DocumentoDaOs {
  id: string;
  document_type: string;
  status: string;
  /** RPS/número interno reservado por nós — o número NACIONAL da NFS-e fica no provider_status. */
  number: number | null;
  series: number | null;
  environment: string;
  status_message: string | null;
  created_at: string | null;
  provider_status?: { nfse_number?: string | null; display_number?: string | null } | null;
}

export interface BillingPreflight {
  os: {
    id: string;
    numero: string | null;
    status: string;
    invoicing_status: string | null;
    grand_total: number | null;
  };
  ambiente: 'homologacao' | 'producao';
  nfse: PreflightDocumento;
  nfe: PreflightDocumento;
  documentos: DocumentoDaOs[];
}

/**
 * O retrato dos DOIS documentos da OS de uma vez, sem emitir nada (action
 * billing_preflight do fiscal-emit — local, sem Contora, sem cota, sem numeração).
 */
export function useBillingPreflight(serviceOrderId: string | null, enabled: boolean) {
  return useQuery({
    queryKey: ['billing-preflight', serviceOrderId],
    enabled: enabled && !!serviceOrderId,
    // Sempre fresco ao abrir o assistente: o usuário pode ter acabado de corrigir o
    // cadastro que o checklist apontou.
    staleTime: 0,
    retry: false,
    queryFn: async (): Promise<BillingPreflight> => {
      const r = await chamarFiscalEmit<{ data: BillingPreflight }>({
        action: 'billing_preflight',
        service_order_id: serviceOrderId,
      });
      return r.data;
    },
  });
}

/**
 * Grava o verbo fiscal na LINHA da ordem — a saída da linha digitada à mão.
 *
 * A linha sem `service_id` não tem cadastro de catálogo onde o fiscal possa
 * morar. Antes disso, a tela de emissão só sabia dizer "linha avulsa — vincule
 * ao catálogo na OS", e vincular não existia em lugar nenhum: 33 linhas em 10
 * ordens presas, R$ 2.525 sem virar nota.
 *
 * Escrita CIRÚRGICA, de propósito: só esta coluna, por `line_id`. A tabela tem
 * seis caminhos de INSERT e sete de UPDATE, cada um com a sua lista explícita de
 * campos — foi assim que `warranty_months` e `warranty_days` morreram, gravados
 * por um caminho e ignorados pelos outros. Uma coluna que só esta mutação toca
 * não entra nessa fila.
 */
export function useSetLineFiscalVerb() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ lineId, fiscalVerb }: { lineId: string; fiscalVerb: string | null }) => {
      const { error } = await supabase
        .from('service_order_services')
        .update({ fiscal_verb: fiscalVerb })
        .eq('id', lineId);
      if (error) throw error;
    },
    // O pré-voo é o que decide se a nota sai: revalidar é o ponto todo da ação.
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['billing-preflight'] });
      qc.invalidateQueries({ queryKey: ['so-services'] });
    },
  });
}

/**
 * NF-e da OS emitida pelo SERVIDOR (ponte buildBodyFromServiceOrder do fiscal-emit):
 * destinatário, itens, CFOP e impostos resolvidos lá — o mesmo caminho que o agente de IA
 * usa. A alternativa com conferência campo a campo continua sendo a página de emissão
 * (botão "emissão detalhada" no assistente).
 */
export function useEmitirNfeDaOs() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { serviceOrderId: string }) => {
      return await chamarFiscalEmit<{ ok: boolean; data: { id: string; status: string; environment?: string } }>({
        service_order_id: v.serviceOrderId,
        // Estável por OS: um retry/duplo clique não vira segunda NF-e. O servidor ainda
        // tem a guarda própria (uq_ifd_active_per_origin por tipo de documento).
        idempotency_key: `nfe-os-${v.serviceOrderId}`,
        payment_method: '01',
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
    },
  });
}

/**
 * Recalcula o `invoicing_status` da OS a partir dos documentos que EXISTEM — não do que
 * acabou de ser clicado. invoiced = todo documento aplicável tem nota viva (não
 * cancelada/rejeitada/falha); partially_invoiced = só parte; not_invoiced = nenhuma.
 *
 * `aplicaveis` é opcional: sem ele, os tipos "aplicáveis" são os já TENTADOS nesta OS —
 * a mesma aproximação do recompute do servidor (webhook/reconcile). É o caminho de quem
 * emite fora do assistente (ex.: NfseSection), que não tem o preflight em mãos.
 */
export async function atualizarInvoicingStatus(
  serviceOrderId: string,
  aplicaveis?: { nfse: boolean; nfe: boolean },
): Promise<void> {
  const { data: docs, error } = await supabase
    .from('issued_fiscal_documents')
    .select('document_type, status')
    .eq('origin_type', 'service_order')
    .eq('origin_id', serviceOrderId);
  // Consulta falhou ≠ "não há notas": escrever not_invoiced em cima de uma OS faturada
  // por causa de um erro de rede seria mentir no marcador. Aborta sem escrever.
  if (error) {
    console.error('[faturar-os] invoicing_status não recalculado (select falhou):', error);
    return;
  }

  const vivos = new Set(
    (docs ?? [])
      .filter((d) => ['draft', 'queued', 'processing', 'authorized'].includes(d.status))
      .map((d) => d.document_type),
  );
  const esperados = aplicaveis
    ? [
      ...(aplicaveis.nfse ? ['nfse'] : []),
      ...(aplicaveis.nfe ? ['nfe'] : []),
    ]
    : [...new Set((docs ?? []).map((d) => d.document_type))];
  const emitidos = esperados.filter((t) => vivos.has(t)).length;
  const status = esperados.length === 0 || emitidos === 0
    ? 'not_invoiced'
    : emitidos === esperados.length
      ? 'invoiced'
      : 'partially_invoiced';

  const { error: upErr } = await supabase
    .from('service_orders')
    .update({ invoicing_status: status, updated_at: new Date().toISOString() })
    .eq('id', serviceOrderId);
  if (upErr) console.error('[faturar-os] falha ao gravar invoicing_status:', upErr);
}
