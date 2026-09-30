// "O mês está pronto?" › Ver: as linhas por trás de um aviso, para conferir e corrigir dali
// (pedido do dono, 30/09/2026). A lista vem de linhas_do_checklist — os mesmos filtros do aviso,
// então o número do aviso e o da janela são sempre iguais. Despesa e receita se corrigem com o
// mesmo diálogo das outras telas; linha do banco sem destino se resolve na fila do Extrato.
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { supabase } from '@/integrations/supabase/client';
import { useI18n } from '@/i18n';
import { useLinhasDoChecklist, type ItemDoChecklist, type LinhaDoAviso } from '@/hooks/use-fechamento';
import { CorrigirLancamentoDialog, type LancamentoParaCorrigir } from '@/components/CorrigirLancamentoDialog';
import { rotaDoComodo } from '@/v2/pages/financeiro/rotas';

/** Onde cada aviso se resolve quando a linha não é um lançamento que se corrige aqui. */
const ONDE_RESOLVER: Record<string, { rotulo: string; url: string } | undefined> = {
  extrato_tratado: { rotulo: 'Abrir a fila do Extrato', url: rotaDoComodo('extrato') },
  saldo_confere: { rotulo: 'Abrir o Extrato com saldo', url: rotaDoComodo('extrato', 'saldo') },
  conciliacao_bate: { rotulo: 'Abrir a Conciliação', url: rotaDoComodo('conciliacao') },
  pago_sem_banco: { rotulo: 'Abrir a Conciliação', url: rotaDoComodo('conciliacao') },
};

export function LinhasDoAvisoDialog({
  ano, mes, item, onFechar,
}: {
  ano: number;
  mes: number;
  item: ItemDoChecklist | null;
  onFechar: () => void;
}) {
  const { formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const linhas = useLinhasDoChecklist(ano, mes, item?.chave ?? null);
  const [corrigindo, setCorrigindo] = useState<{ tipo: 'payable' | 'receivable'; l: LancamentoParaCorrigir } | null>(null);
  const onde = item ? ONDE_RESOLVER[item.chave] : undefined;

  const abrirCorrecao = async (l: LinhaDoAviso) => {
    if (l.tipo !== 'payable' && l.tipo !== 'receivable') return;
    const { data, error } = await supabase.from(l.tipo === 'payable' ? 'payables' : 'receivables').select('*').eq('id', l.id).maybeSingle();
    if (error || !data) { toast.error('Não deu para abrir o lançamento.'); return; }
    setCorrigindo({ tipo: l.tipo, l: data as unknown as LancamentoParaCorrigir });
  };

  const aoFecharCorrecao = () => {
    setCorrigindo(null);
    qc.invalidateQueries({ queryKey: ['linhas-do-checklist'] });
    qc.invalidateQueries({ queryKey: ['checklist-do-mes'] });
  };

  return (
    <>
      <Dialog open={!!item} onOpenChange={(aberto) => { if (!aberto) onFechar(); }}>
        <DialogContent className="max-h-[85dvh] max-w-2xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{item?.titulo}</DialogTitle>
            <DialogDescription>{item?.detalhe}</DialogDescription>
          </DialogHeader>

          {linhas.isLoading && <Skeleton className="h-24 w-full" />}
          {linhas.error && (
            <p className="text-sm text-destructive">Não deu para listar: {(linhas.error as Error).message}</p>
          )}
          {linhas.data && linhas.data.length === 0 && (
            <p className="text-sm text-muted-foreground">Nada mais aqui: o aviso já foi resolvido.</p>
          )}
          {linhas.data && linhas.data.length > 0 && (
            <ul className="divide-y rounded-md border text-sm">
              {linhas.data.map((l) => (
                <li key={`${l.tipo}-${l.id}`} className="flex min-w-0 flex-wrap items-start gap-x-3 gap-y-1 p-2">
                  <span className="w-12 shrink-0 text-xs text-muted-foreground">{l.data ? formatDate(l.data).slice(0, 5) : ''}</span>
                  <span className="min-w-0 flex-1 basis-48">
                    <span className="block break-words">{l.descricao}</span>
                    {l.quem && <span className="block break-words text-xs text-muted-foreground">{l.quem}</span>}
                    {l.detalhe && <span className="block text-xs text-muted-foreground">{l.detalhe}</span>}
                  </span>
                  <span className={`shrink-0 tabular-nums ${l.valor < 0 ? 'text-destructive' : 'text-success'}`}>
                    {formatCurrency(l.valor)}
                  </span>
                  {(l.tipo === 'payable' || l.tipo === 'receivable') && (
                    <Button size="sm" variant="outline" className="h-7 shrink-0 text-xs" onClick={() => abrirCorrecao(l)}>
                      Corrigir
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          )}

          <DialogFooter className="gap-2 sm:gap-0">
            {onde && (
              <Button variant="outline" onClick={() => { onFechar(); navigate(onde.url); }}>{onde.rotulo}</Button>
            )}
            <Button variant="ghost" onClick={onFechar}>Fechar</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      {corrigindo && <CorrigirLancamentoDialog tipo={corrigindo.tipo} lancamento={corrigindo.l} onFechar={aoFecharCorrecao} />}
    </>
  );
}
