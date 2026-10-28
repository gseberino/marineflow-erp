// Extrato em PDF, recibo (e o papel assinado dele) e CSV do contador das diárias.
//
// O PDF é o HTML de `montarExtratoHtml` renderizado no servidor (/api/pdf, o mesmo Chromium dos
// orçamentos); se o servidor não responder, abre a impressão do navegador — o documento sempre sai.
import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { downloadBlob } from '@/lib/download';
import { exportToCSV } from '@/lib/export-utils';
import { credencialDaSessao, renderizarNoServidor } from '@/lib/pdf-server';
import {
  COLUNAS_DO_CSV, linhasDoCsv, montarExtratoHtml, montarReciboDeServicosHtml, montarReciboHtml, nomeDoArquivo, numeroDoRecibo,
  type EmpresaNoDocumento, type FreelancerNoDocumento,
} from '@/lib/extrato-diarias';
import { chaveDaConta, lerContaCorrente, type Acerto, type ContaCorrente } from '@/hooks/use-diarias';
import type { PedidoDePeriodo } from '@/lib/diarias';

async function lerEmpresa(): Promise<EmpresaNoDocumento> {
  const { data } = await supabase.from('app_settings').select('key, value').in('key', ['company_name', 'cnpj', 'city', 'state']);
  const v = Object.fromEntries(((data ?? []) as Array<{ key: string; value: unknown }>).map((r) => [r.key, String(r.value ?? '')]));
  return {
    nome: v.company_name || 'HBR',
    cnpj: v.cnpj || null,
    cidade: [v.city, v.state].filter(Boolean).join('/') || null,
  };
}

/**
 * O dono liberou o recibo (contrato, contadora e advogado — portão F0J da revisão de 24/10)? Até lá o
 * papel sai com o aviso de conferência. Chave app_settings "diarias_recibo_liberado" = true.
 */
async function reciboLiberado(): Promise<boolean> {
  const { data } = await supabase.from('app_settings').select('value').eq('key', 'diarias_recibo_liberado').maybeSingle();
  const v = (data as { value?: unknown } | null)?.value;
  return v === true || v === 'true';
}

async function lerFreelancers(ids: string[]): Promise<Map<string, FreelancerNoDocumento>> {
  const { data, error } = await supabase.from('payees').select('id, name, document, pix_key').in('id', ids);
  if (error) throw error;
  return new Map(((data ?? []) as Array<{ id: string; name: string; document: string | null; pix_key: string | null }>)
    .map((p) => [p.id, { nome: p.name, documento: p.document, pix: p.pix_key }]));
}

/** Abre o HTML numa janela e chama a impressão (reserva quando o servidor de PDF não responde). */
function imprimir(html: string): boolean {
  const win = window.open('', '_blank', 'width=900,height=1000');
  if (!win) return false;
  win.document.write(html);
  win.document.close();
  win.focus();
  win.setTimeout(() => win.print(), 400);
  return true;
}

export function useDocumentosDasDiarias() {
  const qc = useQueryClient();
  const [gerando, setGerando] = useState<'pdf' | 'csv' | null>(null);

  const conta = (id: string, p: PedidoDePeriodo) =>
    qc.fetchQuery({
      queryKey: chaveDaConta(id, p.de, p.ate, p.atalho),
      queryFn: () => lerContaCorrente(id, p.de, p.ate, p.atalho),
      staleTime: 30_000,
    });

  async function extratoEmPdf(favorecidoId: string, periodo: PedidoDePeriodo) {
    setGerando('pdf');
    try {
      const [c, empresa, pessoas] = await Promise.all([conta(favorecidoId, periodo), lerEmpresa(), lerFreelancers([favorecidoId])]);
      const freelancer = pessoas.get(favorecidoId) ?? { nome: c.favorecido.nome, documento: null, pix: null };
      const html = montarExtratoHtml({ empresa, freelancer, conta: c, geradoEm: new Date() });
      const arquivo = nomeDoArquivo('extrato-diarias', freelancer.nome, c, 'pdf');
      const pdf = await renderizarNoServidor(html, arquivo, await credencialDaSessao());
      if (pdf) {
        downloadBlob(pdf, arquivo);
        toast.success(`Extrato baixado: ${arquivo}`);
      } else if (!imprimir(html)) {
        toast.error('O navegador bloqueou a janela de impressão. Libere pop-ups para este site e tente de novo.');
      }
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para gerar o extrato.');
    } finally {
      setGerando(null);
    }
  }

  /**
   * O recibo numerado. Recibo de serviços (F2, 27/10/2026): só da foto congelada no banco
   * (`documento`) — o papel reimpresso é sempre o mesmo. Acerto do modelo antigo (sem foto): totais
   * da foto do acerto (inclusive `reembolsos`, F2b); dias, reembolsos e vales da conta do período.
   */
  async function reciboEmPdf(favorecidoId: string, acerto: Acerto) {
    setGerando('pdf');
    try {
      let html: string;
      let nome: string;
      if (acerto.documento) {
        html = montarReciboDeServicosHtml({ numero: acerto.numero, documento: acerto.documento, liberado: await reciboLiberado(), geradoEm: new Date() });
        nome = acerto.documento.prestador.nome;
      } else {
        const periodo: PedidoDePeriodo = { de: acerto.de, ate: acerto.ate, atalho: null };
        const [c, empresa, pessoas] = await Promise.all([conta(favorecidoId, periodo), lerEmpresa(), lerFreelancers([favorecidoId])]);
        const freelancer = pessoas.get(favorecidoId) ?? { nome: c.favorecido.nome, documento: null, pix: null };
        html = montarReciboHtml({ empresa, freelancer, acerto, linhas: c.linhas, geradoEm: new Date() });
        nome = freelancer.nome;
      }
      const arquivo = nomeDoArquivo(`recibo-${acerto.documento ? 'servicos' : 'diarias'}-${numeroDoRecibo(acerto.numero)}`, nome, acerto, 'pdf');
      const pdf = await renderizarNoServidor(html, arquivo, await credencialDaSessao());
      if (pdf) {
        downloadBlob(pdf, arquivo);
        toast.success(`Recibo baixado: ${arquivo}`);
      } else if (!imprimir(html)) {
        toast.error('O navegador bloqueou a janela de impressão. Libere pop-ups para este site e tente de novo.');
      }
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para gerar o recibo.');
    } finally {
      setGerando(null);
    }
  }

  /**
   * Todos os dias, reembolsos de comprovantes e pagamentos do período, de todos os freelancers — a
   * planilha do contador (o reembolso vai na última coluna, "Reembolso de despesa paga pelo técnico").
   */
  async function csvDoPeriodo(favorecidoIds: string[], periodo: PedidoDePeriodo) {
    setGerando('csv');
    const { de, ate } = periodo;
    try {
      const [contas, pessoas] = await Promise.all([
        Promise.all(favorecidoIds.map((id) => conta(id, periodo))),
        lerFreelancers(favorecidoIds),
      ]);
      const linhas = linhasDoCsv(contas.map((c: ContaCorrente) => ({ conta: c, documento: pessoas.get(c.favorecido.id)?.documento ?? null })));
      if (!linhas.length) {
        toast.info('Nenhum dia, reembolso nem pagamento no período.');
        return;
      }
      const arquivo = nomeDoArquivo('diarias', '', contas[0] ?? { de, ate }, 'csv');
      exportToCSV(linhas, arquivo, COLUNAS_DO_CSV);
      toast.success(`Planilha baixada: ${arquivo}`);
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para gerar a planilha.');
    } finally {
      setGerando(null);
    }
  }

  return { extratoEmPdf, reciboEmPdf, csvDoPeriodo, gerando };
}

// ── O papel assinado (documento, não lançamento: não passa pela paridade tela × assistente) ──

/**
 * O papel assinado do recibo (F4, 27/10/2026): sobe a foto/PDF no bucket privado "documents"
 * (diarias/recibos/<acerto>/…) e o banco marca o recibo como assinado (anexar_recibo_assinado).
 */
export function useAnexarReciboAssinado() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ acertoId, arquivo }: { acertoId: string; arquivo: File }) => {
      const ext = (arquivo.name.split('.').pop() ?? '').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
      const caminho = `diarias/recibos/${acertoId}/${Date.now()}.${ext}`;
      const { error: erroDoUpload } = await supabase.storage.from('documents')
        .upload(caminho, arquivo, { contentType: arquivo.type || undefined, upsert: false });
      if (erroDoUpload) throw erroDoUpload;
      const { data, error } = await supabase.rpc('anexar_recibo_assinado' as never, { p_acerto_id: acertoId, p_arquivo: caminho } as never);
      if (error) throw error;
      return data as unknown as { message: string };
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['diarias'] }),
  });
}

/** Link de 5 minutos para ver o papel assinado (o bucket é privado). */
export async function linkDoReciboAssinado(caminho: string): Promise<string> {
  const { data, error } = await supabase.storage.from('documents').createSignedUrl(caminho, 300);
  if (error || !data?.signedUrl) throw error ?? new Error('Não deu para abrir o papel assinado.');
  return data.signedUrl;
}
