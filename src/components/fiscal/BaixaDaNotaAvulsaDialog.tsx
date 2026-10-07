/**
 * "Baixar estoque + gerar recebível" de uma NF-e AVULSA autorizada: à vista vira um recebível
 * único; parcelado, um recebível por parcela. Baixa o estoque dos itens ligados a produto.
 * Idempotente (a ação some da nota depois de lançada).
 *
 * Saiu de FiscalEmission.tsx no D33 (01/10/2026) com o próprio estado: antes eram oito
 * useState na tela, que só este diálogo usava. O plano inicial e as parcelas são funções
 * puras e testadas (src/lib/fiscal-parcelas.ts); o JSX veio copiado da tela.
 */
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Boxes, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { useI18n } from '@/i18n';
import { totalDaNota } from '@/lib/nota-fiscal-leitura';
import { metodoDoRecebimentoNaHora, parcelasParaLancar as calcularParcelasParaLancar, planoInicialDaBaixa, type Parcela } from '@/lib/fiscal-parcelas';
import { Checkbox } from '@/components/ui/checkbox';
import { useRegisterPayment } from '@/hooks/use-financial';
import { PAYMENT_METHODS } from '../../../supabase/functions/_shared/fiscal/payload-builder';

export function BaixaDaNotaAvulsaDialog({ doc, ocupado, marcarOcupado, onClose }: {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  doc: any;
  /** A tela marca a linha da nota como ocupada enquanto o lançamento corre. */
  ocupado: boolean;
  marcarOcupado: (id: string, busy: boolean) => void;
  onClose: () => void;
}) {
  const { formatCurrency, formatDate } = useI18n();
  const qc = useQueryClient();
  const settleTarget = doc;

  // O plano com que o diálogo abre: o da nota, intacto, ou à vista na data da nota.
  const [inicial] = useState(() => planoInicialDaBaixa(doc));
  const [settleMode, setSettleMode] = useState<'avista' | 'parcelado'>(inicial.modo);
  const [settleN, setSettleN] = useState(inicial.n);
  const [settleInterval, setSettleInterval] = useState(inicial.intervaloDias);
  const [settleFirstDue, setSettleFirstDue] = useState(inicial.primeiroVencimento);
  const [settleMethod, setSettleMethod] = useState(inicial.metodo);
  /** O plano que a PRÓPRIA NOTA declarou: enquanto ninguém mexe nos campos, é ele que vale. */
  const settleParcelasDaNota = inicial.parcelasDaNota;
  /** Vira true assim que o usuário edita algo: daí em diante a conta é recalculada. */
  const [settleAjustado, setSettleAjustado] = useState(false);
  /** Venda de balcão: o cliente pagou na hora — registra o pagamento junto (só à vista). */
  const [recebidoNaHora, setRecebidoNaHora] = useState(false);
  const registrarPagamento = useRegisterPayment();
  const metodoNaHora = metodoDoRecebimentoNaHora(settleMethod);

  const parcelasParaLancar = () => calcularParcelasParaLancar({
    modo: settleMode === 'parcelado' ? 'parcelado' : 'avista',
    ajustado: settleAjustado,
    parcelasDaNota: settleParcelasDaNota,
    total: totalDaNota(settleTarget),
    n: settleN,
    primeiroVencimento: settleFirstDue,
    intervaloDias: settleInterval,
    metodo: settleMethod,
  });

  // "Baixar estoque + gerar recebível(is)" (opt-in) numa NF-e AVULSA autorizada.
  // À vista → 1 recebível hoje; parcelado → 1 recebível por parcela (vencimentos).
  // Baixa o estoque dos itens ligados a produto. Idempotente (some após lançar).
  const handleSettleStock = async (alvo: { id: string }, installments: Parcela[] | null) => {
    marcarOcupado(alvo.id, true);
    const tId = toast.loading('Baixando estoque e gerando recebível(is)…');
    try {
      const { data: resposta, error } = await supabase.rpc('settle_nfe_stock_and_receivable' as never, {
        p_document_id: alvo.id,
        p_installments: installments && installments.length ? installments : null,
      } as never);
      const data = resposta as { ok?: boolean; error?: string; stock_items?: number; installments?: number; receivable_id?: string; amount?: number; issue_date?: string } | null;
      if (error) throw new Error(error.message);
      if (data && data.ok === false) throw new Error(data.error || 'Falha ao lançar.');
      const nItems = Number(data?.stock_items ?? 0);
      const nParc = Number(data?.installments ?? 1);
      // Já recebido no balcão: o pagamento entra agora, pela mesma função do "Registrar pagamento".
      // Se falhar, o recebível já existe — o aviso diz para registrar à mão, sem desfazer a baixa.
      let pago = false;
      if (recebidoNaHora && metodoNaHora && settleMode === 'avista' && data?.receivable_id) {
        try {
          await registrarPagamento.mutateAsync({
            receivable_id: data.receivable_id,
            amount: Number(data.amount ?? totalDaNota(alvo)),
            payment_date: String(data.issue_date ?? new Date().toISOString().slice(0, 10)),
            payment_method: metodoNaHora,
            notes: 'Recebido no balcão (baixa da NF-e avulsa)',
          });
          pago = true;
        } catch (e) {
          toast.warning(`Estoque baixado e recebível gerado, mas o pagamento não foi registrado (${(e as Error)?.message ?? 'erro'}). Registre em Contas a Receber.`);
        }
      }
      toast.success(
        `${pago ? 'Recebido e lançado como pago' : nParc > 1 ? `${nParc} recebíveis gerados` : 'Recebível gerado'}${nItems > 0 ? ` · estoque baixado (${nItems} item${nItems > 1 ? 'ns' : ''})` : ''}.`,
        { id: tId },
      );
      onClose();
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
    } catch (err) {
      toast.error('Erro ao lançar estoque/recebível: ' + ((err as Error)?.message || 'desconhecido'), { id: tId });
    } finally {
      marcarOcupado(alvo.id, false);
    }
  };

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Baixar estoque + gerar recebível</DialogTitle>
          <DialogDescription>
            NF-e {settleTarget?.series}/{settleTarget?.number} — total {formatCurrency(totalDaNota(settleTarget))}.
            Baixa o estoque dos itens ligados a produto e gera o financeiro. Idempotente.
          </DialogDescription>
        </DialogHeader>
        {settleTarget && (() => {
          // O valor que vira CONTA A RECEBER. Ler pelo pagamento declarado dava o numero
          // certo por coincidencia na venda a vista e errado em tudo mais -- e um titulo
          // nasce uma vez so.
          const total = totalDaNota(settleTarget);
          const schedule = parcelasParaLancar() ?? [];
          const planoDaNota = settleParcelasDaNota;
          const somaDoPlano = schedule.reduce((acc, p) => acc + p.amount, 0);
          const difere = Math.abs(somaDoPlano - total) > 0.005;
          const semPlanoNaNota = !planoDaNota;
          return (
            <div className="space-y-3">
              {/* O que a NOTA diz, antes de qualquer campo editável: é contra isto que o
                  lançamento tem de fechar, e era justamente o que não aparecia. */}
              {planoDaNota ? (
                <div className="rounded-lg border border-emerald-300 bg-emerald-50 p-2.5 text-xs">
                  <p className="font-semibold text-emerald-900">
                    Plano declarado na nota — {planoDaNota.length}x
                  </p>
                  <ul className="mt-1 space-y-0.5 text-emerald-800">
                    {planoDaNota.map((p, i) => (
                      <li key={i} className="flex justify-between gap-2 tabular-nums">
                        <span>{i + 1}/{planoDaNota.length} · vence {formatDate(p.due_date)}</span>
                        <span className="font-medium">{formatCurrency(p.amount)}</span>
                      </li>
                    ))}
                  </ul>
                  {!settleAjustado && (
                    <p className="mt-1.5 text-[11px] text-emerald-700">
                      Será lançado exatamente assim, no centavo.
                    </p>
                  )}
                </div>
              ) : (
                <div className="rounded-lg border border-amber-300 bg-amber-50 p-2.5 text-xs text-amber-900">
                  <p className="font-semibold">Esta nota não declarou plano de pagamento.</p>
                  <p className="mt-0.5 text-amber-800">
                    Não há o que copiar do documento, então o vencimento abaixo parte da
                    data da própria nota — confira antes de confirmar.
                  </p>
                </div>
              )}

              {settleAjustado && planoDaNota && (
                <div className="rounded-lg border border-amber-300 bg-amber-50 p-2.5 text-xs text-amber-900">
                  <p className="font-semibold">Você alterou o plano.</p>
                  <p className="mt-0.5 text-amber-800">
                    O que será lançado deixa de bater com a nota que o cliente recebeu.
                  </p>
                  <Button
                    type="button" variant="outline" size="sm" className="mt-1.5 h-7 text-[11px]"
                    onClick={() => {
                      setSettleAjustado(false);
                      setSettleMode('parcelado');
                      setSettleN(planoDaNota.length);
                      setSettleFirstDue(planoDaNota[0].due_date);
                      setSettleMethod(planoDaNota[0].method);
                    }}
                  >
                    Voltar ao plano da nota
                  </Button>
                </div>
              )}

              <div className="flex gap-2">
                <Button
                  type="button" size="sm"
                  variant={settleMode === 'avista' ? 'default' : 'outline'}
                  onClick={() => { setSettleMode('avista'); if (planoDaNota) setSettleAjustado(true); }}
                >À vista</Button>
                <Button
                  type="button" size="sm"
                  variant={settleMode === 'parcelado' ? 'default' : 'outline'}
                  onClick={() => { setSettleMode('parcelado'); if (semPlanoNaNota) setSettleAjustado(true); }}
                >Parcelado</Button>
              </div>

              {settleMode === 'parcelado' && (
                <>
                  <div className="grid grid-cols-3 gap-2">
                    <div>
                      <Label htmlFor="baixa-parcelas" className="text-xs">Parcelas</Label>
                      <Input id="baixa-parcelas" type="number" min={2} max={60} className="h-8 text-xs"
                        value={settleN}
                        onChange={(e) => { setSettleAjustado(true); setSettleN(Math.max(1, Math.min(60, parseInt(e.target.value, 10) || 1))); }} />
                    </div>
                    <div>
                      <Label htmlFor="baixa-vencimento" className="text-xs">1º vencimento</Label>
                      <Input id="baixa-vencimento" type="date" className="h-8 text-xs"
                        value={settleFirstDue}
                        onChange={(e) => { setSettleAjustado(true); setSettleFirstDue(e.target.value); }} />
                    </div>
                    <div>
                      <Label htmlFor="baixa-intervalo" className="text-xs">Intervalo (dias)</Label>
                      <Input id="baixa-intervalo" type="number" min={1} max={365} className="h-8 text-xs"
                        value={settleInterval}
                        onChange={(e) => { setSettleAjustado(true); setSettleInterval(Math.max(1, parseInt(e.target.value, 10) || 30)); }} />
                    </div>
                  </div>
                  <div>
                    <Label htmlFor="baixa-forma" className="text-xs">Forma de pagamento</Label>
                    <Select value={settleMethod} onValueChange={(v) => { setSettleAjustado(true); setSettleMethod(v); }}>
                      <SelectTrigger id="baixa-forma" className="h-8 text-xs"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {PAYMENT_METHODS.filter((m) => m.value !== '90').map((m) => (
                          <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  {/* Prévia das parcelas */}
                  <div className="rounded-lg border bg-muted/30 max-h-40 overflow-y-auto">
                    <table className="w-full text-xs">
                      <thead className="text-muted-foreground">
                        <tr><th className="text-left px-2 py-1">Parcela</th><th className="text-left px-2 py-1">Vencimento</th><th className="text-right px-2 py-1">Valor</th></tr>
                      </thead>
                      <tbody>
                        {schedule.map((p, i) => (
                          <tr key={i} className="border-t">
                            <td className="px-2 py-1">{i + 1}/{schedule.length}</td>
                            <td className="px-2 py-1">{formatDate(p.due_date)}</td>
                            <td className="px-2 py-1 text-right font-medium">{formatCurrency(p.amount)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  {/* A conferencia que faltava: a soma das parcelas contra o total da
                      nota. Um titulo que nao fecha com o documento so aparecia meses
                      depois, na cobranca. */}
                  <p className={difere ? 'text-[11px] font-medium text-destructive' : 'text-[11px] text-muted-foreground'}>
                    {difere
                      ? `Atenção: as parcelas somam ${formatCurrency(somaDoPlano)}, e a nota é de ${formatCurrency(total)}.`
                      : `As parcelas somam ${formatCurrency(somaDoPlano)} — fecha com a nota.`}
                  </p>
                  <p className="text-[11px] text-muted-foreground">
                    Gera um recebível por parcela em Contas a Receber; você registra o pagamento de cada uma quando for paga.
                  </p>
                </>
              )}
              {settleMode === 'avista' && (
                <p className="text-xs text-muted-foreground">
                  Gera <strong>um recebível único</strong> de {formatCurrency(total)}, o valor total da nota.
                </p>
              )}
              {settleMode === 'avista' && metodoNaHora && (
                <label className="flex items-start gap-2 rounded-lg border p-2.5 text-xs" data-testid="recebido-na-hora">
                  <Checkbox checked={recebidoNaHora} onCheckedChange={(v) => setRecebidoNaHora(v === true)} className="mt-0.5" />
                  <span>
                    <span className="font-medium">Já recebi no balcão</span> — registra o pagamento de {formatCurrency(total)} agora
                    (mesma forma de pagamento da nota), e a conta já nasce paga.
                    {metodoNaHora === 'pix' && ' Quando o Pix aparecer no Extrato, ele se liga a este pagamento.'}
                  </span>
                </label>
              )}
            </div>
          );
        })()}
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={ocupado}>Voltar</Button>
          <Button
            disabled={ocupado}
            onClick={() => handleSettleStock(settleTarget, parcelasParaLancar())}
          >
            {ocupado ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Boxes className="h-4 w-4 mr-2" />}
            Confirmar lançamento
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
