// Demonstrativo do mês em PDF (pedido do dono, 29/09/2026: "fechar o mês no papel").
//
// Lê o mês com os MESMOS filtros do DRE (use-dre.ts: despesa cancelada e receita cancelada não
// entram), o fluxo pelo extrato (carregarFluxoDeCaixa, o da Central de relatórios) e a lista do
// "Mês pronto?" (checklist_do_mes). O PDF sai do servidor (/api/pdf, o mesmo Chromium dos
// orçamentos); se o servidor não responder, abre a impressão do navegador — o documento sempre sai.
import { useState } from 'react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { lerEmPaginas } from '@/lib/ler-em-paginas';
import { downloadBlob } from '@/lib/download';
import { credencialDaSessao, renderizarNoServidor } from '@/lib/pdf-server';
import { carregarFluxoDeCaixa } from '@/hooks/use-fluxo-de-caixa';
import type { GrupoDRE } from '@/lib/dre';
import {
  montarDemonstrativoHtml, nomeDoArquivoDoDemonstrativo,
  type ItemDoMesPronto, type LancamentoDoDemonstrativo,
} from '@/lib/demonstrativo-do-mes';

function ultimoDia(ano: number, mes: number): string {
  return new Date(Date.UTC(ano, mes, 0)).toISOString().slice(0, 10);
}

export async function lerLancamentosDoMes(ano: number, mes: number): Promise<LancamentoDoDemonstrativo[]> {
  const m = String(mes).padStart(2, '0');
  const de = `${ano}-${m}-01`;
  const ate = ultimoDia(ano, mes);
  const [cats, pagar, receber] = await Promise.all([
    supabase.from('financial_categories').select('name, type, dre_group'),
    lerEmPaginas((i, f) => supabase.from('payables')
      .select('id, issue_date, amount, expense_category, description, supplier_name, status, payees!payables_payee_id_fkey(name)')
      .neq('status', 'cancelled')
      .gte('issue_date', de).lte('issue_date', ate)
      .order('id').range(i, f)),
    lerEmPaginas((i, f) => supabase.from('receivables')
      .select('id, issue_date, amount, category, description, status, clients!receivables_client_id_fkey(name)')
      .gte('issue_date', de).lte('issue_date', ate)
      .order('id').range(i, f)),
  ]);
  if (cats.error) throw cats.error;

  const grupoDe = new Map<string, GrupoDRE>();
  for (const c of (cats.data ?? []) as Array<{ name: string; type: string; dre_group: GrupoDRE | null }>) {
    if (c.dre_group) grupoDe.set(`${c.type}:${c.name}`, c.dre_group);
  }

  const despesas = (pagar as any[]).map((p): LancamentoDoDemonstrativo => ({
    data: p.issue_date,
    valor: Number(p.amount),
    categoria: p.expense_category,
    grupo: p.expense_category ? grupoDe.get(`payable:${p.expense_category}`) ?? null : null,
    tipo: 'despesa',
    descricao: p.description || p.supplier_name || 'Sem descrição',
    quem: p.payees?.name ?? p.supplier_name ?? null,
    situacao: p.status,
  }));
  const receitas = (receber as any[])
    .filter((r) => r.status !== 'cancelled')
    .map((r): LancamentoDoDemonstrativo => ({
      data: r.issue_date,
      valor: Number(r.amount),
      categoria: r.category,
      grupo: (r.category ? grupoDe.get(`receivable:${r.category}`) : null) ?? 'receita',
      tipo: 'receita',
      descricao: r.description || 'Recebimento',
      quem: r.clients?.name ?? null,
      situacao: r.status,
    }));
  return [...despesas, ...receitas];
}

async function lerEmpresa(): Promise<{ nome: string; cnpj: string | null }> {
  const { data } = await supabase.from('app_settings').select('key, value').in('key', ['company_name', 'cnpj']);
  const v = Object.fromEntries(((data ?? []) as Array<{ key: string; value: unknown }>).map((r) => [r.key, String(r.value ?? '')]));
  return { nome: v.company_name || 'HBR', cnpj: v.cnpj || null };
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

export function useDemonstrativoDoMes() {
  const [gerando, setGerando] = useState(false);

  async function gerar(ano: number, mes: number, fechado: boolean) {
    setGerando(true);
    const chave = `${ano}-${String(mes).padStart(2, '0')}`;
    try {
      // Extrato e "Mês pronto?" podem faltar sem impedir o documento: ele diz o que não veio.
      const [lancamentos, empresa, extrato, checklist] = await Promise.all([
        lerLancamentosDoMes(ano, mes),
        lerEmpresa(),
        carregarFluxoDeCaixa(1, chave).then((f) => f.meses[0] ?? null).catch(() => null),
        Promise.resolve(supabase.rpc('checklist_do_mes' as never, { p_ano: ano, p_mes: mes } as never))
          .then(({ data, error }) => (error ? null : data as unknown as { pronto: boolean; itens: ItemDoMesPronto[] }))
          .catch(() => null),
      ]);
      const html = montarDemonstrativoHtml({ empresa, mes: chave, lancamentos, extrato, checklist, fechado, geradoEm: new Date() });
      const arquivo = nomeDoArquivoDoDemonstrativo(chave);
      const pdf = await renderizarNoServidor(html, arquivo, await credencialDaSessao());
      if (pdf) {
        downloadBlob(pdf, arquivo);
        toast.success(`Demonstrativo baixado: ${arquivo}`);
      } else if (!imprimir(html)) {
        toast.error('O navegador bloqueou a janela de impressão. Libere pop-ups para este site e tente de novo.');
      }
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para gerar o demonstrativo.');
    } finally {
      setGerando(false);
    }
  }

  return { gerar, gerando };
}
