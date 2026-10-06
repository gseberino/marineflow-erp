// Extrato em PDF e CSV do contador das diárias.
//
// O PDF é o HTML de `montarExtratoHtml` renderizado no servidor (/api/pdf, o mesmo Chromium dos
// orçamentos); se o servidor não responder, abre a impressão do navegador — o documento sempre sai.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { downloadBlob } from '@/lib/download';
import { exportToCSV } from '@/lib/export-utils';
import { credencialDaSessao, renderizarNoServidor } from '@/lib/pdf-server';
import {
  COLUNAS_DO_CSV, linhasDoCsv, montarExtratoHtml, montarReciboHtml, nomeDoArquivo, numeroDoRecibo,
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

  /** O recibo numerado do acerto: totais da foto do acerto; dias e vales da conta do mesmo período. */
  async function reciboEmPdf(favorecidoId: string, acerto: Acerto) {
    setGerando('pdf');
    try {
      const periodo: PedidoDePeriodo = { de: acerto.de, ate: acerto.ate, atalho: null };
      const [c, empresa, pessoas] = await Promise.all([conta(favorecidoId, periodo), lerEmpresa(), lerFreelancers([favorecidoId])]);
      const freelancer = pessoas.get(favorecidoId) ?? { nome: c.favorecido.nome, documento: null, pix: null };
      const html = montarReciboHtml({ empresa, freelancer, acerto, linhas: c.linhas, geradoEm: new Date() });
      const arquivo = nomeDoArquivo(`recibo-diarias-${numeroDoRecibo(acerto.numero)}`, freelancer.nome, acerto, 'pdf');
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

  /** Todos os dias e pagamentos do período, de todos os freelancers — a planilha do contador. */
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
        toast.info('Nenhum dia nem pagamento no período.');
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
