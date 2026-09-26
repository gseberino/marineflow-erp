// "É este?" — a parcela de uma nota importada que parece já ter sido paga pelo banco.
//
// A importação do XML acha, para cada parcela, pagamentos de mesmo valor ao mesmo fornecedor já
// lançados pelo Extrato (perto do vencimento). Não liga sozinha — decisão do dono de 26/09/2026:
// "o sistema deve sempre questionar". Esta janela faz a pergunta; só o "É este" liga
// (ligar_parcela_ao_pagamento): o pagamento passa a ser a parcela e a conta a pagar dela sai. Sem
// resposta, a parcela continua em Contas a Pagar — e a pergunta pode ser reaberta pela nota.
import { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { supabase } from '@/integrations/supabase/client';
import { useI18n } from '@/i18n';

export interface CandidatoDePagamento {
  payable_id: string;
  data: string;
  valor: number;
  descricao: string;
}

export interface ParcelaDaImportacao {
  parcela: number;
  valor: number;
  vencimento: string | null;
  payable_id: string;
  como: string;
  candidatos?: CandidatoDePagamento[];
}

/** As parcelas que têm pergunta a fazer. */
export function parcelasComPergunta(parcelas: ParcelaDaImportacao[] | null | undefined): ParcelaDaImportacao[] {
  return (parcelas ?? []).filter((p) => p.como === 'a_pagar' && (p.candidatos?.length ?? 0) > 0);
}

export function PerguntasDaNota({
  nota, parcelas, onFechar,
}: {
  nota: string | null;
  parcelas: ParcelaDaImportacao[];
  onFechar: () => void;
}) {
  const { formatCurrency, formatDate } = useI18n();
  const qc = useQueryClient();
  const [respostas, setRespostas] = useState<Record<string, 'ligada' | 'nao'>>({});
  const [ocupado, setOcupado] = useState<string | null>(null);
  // A pergunta pode ser reaberta depois: só vale para a parcela que continua A PAGAR (uma já ligada
  // saiu; uma paga por outro caminho não tem mais o que perguntar).
  const [abertas, setAbertas] = useState<Set<string> | null>(null);
  const comPergunta = parcelasComPergunta(parcelas);

  useEffect(() => {
    let vivo = true;
    const ids = comPergunta.map((p) => p.payable_id);
    if (ids.length === 0) { setAbertas(new Set()); return; }
    void supabase.from('payables').select('id, status').in('id', ids).then(({ data }) => {
      if (!vivo) return;
      setAbertas(new Set(((data ?? []) as Array<{ id: string; status: string }>)
        .filter((r) => r.status === 'pending').map((r) => r.id)));
    });
    return () => { vivo = false; };
    // As parcelas vêm da importação e não mudam enquanto a janela está aberta.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const visiveis = comPergunta.filter((p) => respostas[p.payable_id] || abertas?.has(p.payable_id));
  const faltam = visiveis.filter((p) => !respostas[p.payable_id]).length;

  const ligar = async (p: ParcelaDaImportacao, c: CandidatoDePagamento) => {
    setOcupado(p.payable_id);
    try {
      const { error } = await supabase.rpc('ligar_parcela_ao_pagamento' as never, {
        p_parcela: p.payable_id, p_pagamento: c.payable_id,
      } as never);
      if (error) throw error;
      setRespostas((r) => ({ ...r, [p.payable_id]: 'ligada' }));
      toast.success('Ligado: esta parcela é o pagamento que já saiu pelo banco, e deixou de ficar a pagar.');
      void qc.invalidateQueries({ queryKey: ['payables'] });
    } catch (e) {
      toast.error(`Não liguei: ${String((e as { message?: string })?.message ?? e).replace(/^(P0001|42501):\s*/, '')}`);
    } finally {
      setOcupado(null);
    }
  };

  return (
    <Dialog open onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Parcelas que parecem já pagas</DialogTitle>
          <DialogDescription>
            {nota ? `Nota ${nota}: ` : ''}há pagamento de mesmo valor a este fornecedor, lançado pelo
            Extrato, perto do vencimento destas parcelas. Se for o mesmo dinheiro, diga "É este" — a
            parcela deixa de ficar a pagar e nada é contado duas vezes. Se não for, ela continua em
            Contas a Pagar.
          </DialogDescription>
        </DialogHeader>

        {abertas === null ? (
          <p className="text-sm text-muted-foreground">Conferindo as parcelas…</p>
        ) : visiveis.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhuma parcela desta nota tem pergunta aberta.</p>
        ) : (
          <ul className="space-y-3">
            {visiveis.map((p) => (
              <li key={p.payable_id} className="rounded-md border p-3 text-sm">
                <p className="font-medium">
                  Parcela {p.parcela} · {formatCurrency(Number(p.valor))} · vence {p.vencimento ? formatDate(p.vencimento) : '—'}
                </p>
                {respostas[p.payable_id] === 'ligada' ? (
                  <p className="mt-1 text-success">Ligada ao pagamento — saiu de Contas a Pagar.</p>
                ) : respostas[p.payable_id] === 'nao' ? (
                  <p className="mt-1 text-muted-foreground">Continua a pagar.</p>
                ) : (
                  <div className="mt-2 space-y-2">
                    {(p.candidatos ?? []).map((c) => (
                      <div key={c.payable_id} className="flex flex-wrap items-center justify-between gap-2">
                        <span className="min-w-0 break-words text-muted-foreground">
                          Pago em {formatDate(c.data)} · {formatCurrency(Number(c.valor))} · {c.descricao}
                        </span>
                        <Button size="sm" variant="outline" disabled={!!ocupado} onClick={() => void ligar(p, c)}>
                          É este
                        </Button>
                      </div>
                    ))}
                    <Button size="sm" variant="ghost" disabled={!!ocupado}
                      onClick={() => setRespostas((r) => ({ ...r, [p.payable_id]: 'nao' }))}>
                      Não é nenhum destes
                    </Button>
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}

        <DialogFooter>
          <Button onClick={onFechar}>{faltam > 0 ? 'Responder depois' : 'Concluir'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
