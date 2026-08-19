// [F-NFSE-01] NFS-e — pré-voo, emissão, status, artefatos e cancelamento.
//
// Tudo passa pela edge function `fiscal-emit`: o token da Contora é secret do servidor e
// nunca chega ao navegador.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/** Faixa da justificativa de cancelamento, igual à do servidor e à da doc da Contora. */
export const MIN_JUSTIFICATIVA = 15;
export const MAX_JUSTIFICATIVA = 255;

export interface DocumentoNfse {
  id: string;
  number: number | null;
  series: number | null;
  status: string;
  environment: string;
  status_message: string | null;
  created_at: string | null;
  origin_id: string | null;
  /**
   * `number` é o RPS (numeração NOSSA, reservada antes do envio). O número da NFS-e em si
   * é NACIONAL, gerado pela Sefin na autorização — chega via status/reconcile e fica em
   * provider_status (nfse_number/display_number). Confundir os dois é erro clássico.
   */
  provider_status?: { nfse_number?: string | null; display_number?: string | null } | null;
}

/** Número nacional da NFS-e (pós-autorização), quando já sincronizado. */
export function numeroNacionalNfse(doc: DocumentoNfse): string | null {
  const n = doc.provider_status?.nfse_number ?? doc.provider_status?.display_number ?? null;
  return n != null && String(n).trim() !== '' ? String(n) : null;
}

export interface NfseHealth {
  pronto: boolean;
  empresa?: { id: string; legal_name?: string | null; document?: string | null };
  contora?: {
    ready?: boolean;
    standard?: string | null;
    city_code?: string | null;
    city_name?: string | null;
    certificate_ok?: boolean;
    certificate_valid_until?: string | null;
    pending?: string[];
    erro?: string;
  };
  cadastro?: Record<string, unknown> | null;
  pendencias_locais?: string[];
  divergencia_de_padrao?: string | null;
}

/**
 * Lê o corpo do erro da edge function.
 *
 * `functions.invoke` devolve só "non-2xx status code" e joga o motivo real no corpo — e o
 * motivo real aqui é justamente o que ensina a corrigir ("falta o percentual do Simples",
 * "códigos de tributação diferentes"). Sem isto, toda rejeição vira a mesma frase inútil.
 */
export async function chamarFiscalEmit<T>(body: Record<string, unknown>): Promise<T> {
  return await chamar<T>(body);
}

async function chamar<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('fiscal-emit', { body });
  if (error) {
    const resposta = (error as { context?: Response }).context;
    if (resposta && typeof resposta.json === 'function') {
      try {
        const corpo = await resposta.json();
        if (corpo?.error) {
          const e = new Error(String(corpo.error));
          // Preserva o sinal de "não adianta repetir" para a tela decidir o que oferecer.
          (e as Error & { cancelUnsupported?: boolean }).cancelUnsupported =
            corpo.cancel_unsupported === true;
          throw e;
        }
      } catch (e) {
        if (e instanceof Error && !e.message.includes('non-2xx')) throw e;
      }
    }
    throw error;
  }
  if ((data as { error?: string })?.error) throw new Error(String((data as { error: string }).error));
  return data as T;
}

export function useNfseHealth(enabled = true) {
  return useQuery({
    queryKey: ['nfse-health'],
    enabled,
    queryFn: async (): Promise<NfseHealth> => {
      const r = await chamar<{ data: NfseHealth }>({ action: 'nfse_health' });
      return r.data;
    },
    // Pré-voo é consulta de cadastro e certificado: muda raramente, e cada chamada bate na
    // Contora. Cinco minutos evita transformar abrir a tela em tráfego.
    staleTime: 5 * 60_000,
    retry: false,
  });
}

export function useNfseDocumentos() {
  return useQuery({
    queryKey: ['nfse-documentos'],
    queryFn: async (): Promise<DocumentoNfse[]> => {
      const { data, error } = await supabase
        .from('issued_fiscal_documents')
        .select('id, number, series, status, environment, status_message, created_at, origin_id, provider_status')
        .eq('document_type', 'nfse')
        .order('created_at', { ascending: false })
        .order('id', { ascending: true })
        .limit(200);
      if (error) throw error;
      return (data ?? []) as unknown as DocumentoNfse[];
    },
    staleTime: 30_000,
  });
}

export function useEmitirNfse() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { serviceOrderId: string }) => {
      return await chamar<{ data: { id: string; status: string }; aviso?: string }>({
        document_type: 'nfse',
        service_order_id: v.serviceOrderId,
        // Estável por OS: um duplo clique não vira duas notas de serviço para o mesmo
        // trabalho. O servidor tem a própria guarda, esta é a primeira linha.
        idempotency_key: `nfse-os-${v.serviceOrderId}`,
      });
    },
    onSuccess: (r) => {
      qc.invalidateQueries({ queryKey: ['nfse-documentos'] });
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
      // A OS de origem pode ter mudado de invoicing_status — a lista precisa recarregar.
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      if (r.aviso) toast.warning(r.aviso, { duration: 12_000 });
      else toast.success('NFS-e enviada. Acompanhe o status abaixo.');
    },
    onError: (e: Error) => toast.error(e.message, { duration: 12_000 }),
  });
}

/** Ambiente REAL de emissão (secret do servidor) — alimenta o banner de produção. */
export function useAmbienteFiscal() {
  return useQuery({
    queryKey: ['fiscal-environment'],
    queryFn: async (): Promise<'homologacao' | 'producao'> => {
      const r = await chamar<{ data: { environment: string } }>({ action: 'environment' });
      return r.data.environment === 'producao' ? 'producao' : 'homologacao';
    },
    staleTime: 10 * 60_000,
    retry: false,
  });
}

export interface NfseAvulsaInput {
  clientId: string;
  descricao: string;
  valor: number;
  nationalTaxCode: string;
  cnae: string | null;
  issRate: number | null;
  issWithheld: boolean;
  /**
   * Gerada UMA vez ao entrar na conferência e reutilizada em todos os retries — um uuid
   * novo por clique deixaria um retry pós-timeout emitir a MESMA nota real duas vezes
   * (a avulsa não tem origem estável; a chave é a única dedupe).
   */
  idempotencyKey: string;
}

/**
 * NFS-e AVULSA — serviço que não virou OS (cobrança pontual). O servidor já aceitava
 * `service`/`taker`/`amounts` explícitos (caminho manual do handleCreateNfse); este hook
 * monta o tomador a partir do cadastro do cliente com o MESMO mapeamento da ponte de OS.
 */
export function useEmitirNfseAvulsa() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: NfseAvulsaInput) => {
      const { data: cli, error } = await supabase
        .from('clients')
        .select('name, cpf_cnpj, email, address_line_1, address_number, address_complement, neighborhood, city, state, postal_code')
        .eq('id', v.clientId)
        .maybeSingle();
      if (error) throw error;
      if (!cli) throw new Error('Cliente não encontrado.');
      return await chamar<{ data: { id: string; status: string; environment?: string }; aviso?: string }>({
        document_type: 'nfse',
        origin_type: 'manual',
        client_id: v.clientId,
        idempotency_key: v.idempotencyKey,
        service: {
          description: v.descricao,
          national_tax_code: v.nationalTaxCode,
          cnae: v.cnae,
          iss_rate: v.issRate,
          iss_withheld: v.issWithheld,
        },
        taker: {
          name: cli.name,
          document: cli.cpf_cnpj,
          email: cli.email,
          address: {
            street: cli.address_line_1,
            number: cli.address_number,
            complement: cli.address_complement,
            district: cli.neighborhood,
            city_name: cli.city,
            state_code: cli.state,
            postal_code: cli.postal_code,
          },
        },
        amounts: { service_amount: v.valor },
      });
    },
    onSuccess: (r) => {
      qc.invalidateQueries({ queryKey: ['nfse-documentos'] });
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
      if (r.aviso) toast.warning(r.aviso, { duration: 12_000 });
      else toast.success('NFS-e avulsa enviada. Acompanhe o status na lista.');
    },
    onError: (e: Error) => toast.error(e.message, { duration: 12_000 }),
  });
}

export function useCancelarNfse() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { documentId: string; motivo: string }) => {
      return await chamar({ action: 'cancel', document_id: v.documentId, reason: v.motivo });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['nfse-documentos'] });
      toast.success('Cancelamento enviado.');
    },
    onError: (e: Error) => {
      // Município que não cancela por webservice: repetir não adianta, então a mensagem
      // fica mais tempo na tela e não sugere nova tentativa.
      const semSuporte = (e as Error & { cancelUnsupported?: boolean }).cancelUnsupported;
      toast.error(e.message, { duration: semSuporte ? 20_000 : 10_000 });
    },
  });
}

export function useAtualizarStatusNfse() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async () => {
      // A sincronização mora na function `fiscal-reconcile` (a mesma que o cron usa), com
      // `document_id` por nota. O `fiscal-emit` NÃO tem action "reconcile" — a versão
      // anterior deste hook chamava uma action inexistente, caía no default (emitir NF-e)
      // e devolvia um erro de validação sem relação com o botão.
      const { data: pendentes, error } = await supabase
        .from('issued_fiscal_documents')
        .select('id')
        .eq('document_type', 'nfse')
        .not('provider_document_id', 'is', null)
        .in('status', ['draft', 'queued', 'processing'])
        .order('created_at', { ascending: false })
        .limit(20);
      if (error) throw error;
      for (const d of pendentes ?? []) {
        const { error: err } = await supabase.functions.invoke('fiscal-reconcile', {
          body: { document_id: d.id },
        });
        if (err) throw new Error(`Falha ao sincronizar uma das notas: ${err.message}`);
      }
      return { sincronizados: pendentes?.length ?? 0 };
    },
    onSuccess: (r) => {
      qc.invalidateQueries({ queryKey: ['nfse-documentos'] });
      toast.success(
        r.sincronizados > 0
          ? `Status sincronizado (${r.sincronizados} nota${r.sincronizados > 1 ? 's' : ''}).`
          : 'Nenhuma nota pendente de sincronização.',
      );
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

export function useArtefatoNfse() {
  return useMutation({
    mutationFn: async (v: {
      documentId: string;
      tipo: 'xml' | 'pdf';
      numero?: number | null;
      serie?: number | null;
    }) => {
      // O download passa pelo servidor porque as URLs da Contora são autenticadas (Bearer):
      // abrir no navegador devolve "token ausente".
      //
      // Contrato REAL do handleArtifact (fiscal-emit): campo `artifact` com
      // 'xml_authorized' | 'pdf_danfe' (o DANFSe da Contora sai no MESMO slot pdf_danfe da
      // DANFE) e resposta em Blob cru com Content-Disposition — não JSON/base64. A versão
      // anterior mandava `artifact_type: 'pdf_danfse'` e esperava JSON: quebrado nos dois
      // eixos.
      const { data, error } = await supabase.functions.invoke('fiscal-emit', {
        body: {
          action: 'artifact',
          document_id: v.documentId,
          artifact: v.tipo === 'xml' ? 'xml_authorized' : 'pdf_danfe',
        },
      });
      if (error) {
        const resposta = (error as { context?: Response }).context;
        if (resposta && typeof resposta.json === 'function') {
          try {
            const corpo = await resposta.json();
            if (corpo?.error) throw new Error(String(corpo.error));
          } catch (e) {
            if (e instanceof Error && !e.message.includes('non-2xx')) throw e;
          }
        }
        throw error;
      }
      const ehXml = v.tipo === 'xml';
      const tipoConteudo = ehXml ? 'application/xml' : 'application/pdf';
      const blob = data instanceof Blob
        ? data
        : new Blob([typeof data === 'string' ? data : JSON.stringify(data)], { type: tipoConteudo });
      const sufixo = v.numero != null ? `${v.serie ?? 1}-${v.numero}` : v.documentId.slice(0, 8);
      return { blob, filename: `NFSe-${sufixo}.${ehXml ? 'xml' : 'pdf'}` };
    },
    onSuccess: (d) => {
      const url = URL.createObjectURL(d.blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = d.filename;
      a.click();
      URL.revokeObjectURL(url);
    },
    onError: (e: Error) => toast.error(`Não deu para baixar: ${e.message}`),
  });
}
