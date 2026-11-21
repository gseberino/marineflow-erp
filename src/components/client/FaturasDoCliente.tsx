// Faturas FAT-N do cliente ("Fechar juntas", Fase 1, 20/11/2026), na aba Financeiro da ficha.
//
// Cada fatura: número, OS, total, recebido e o que falta. À vista só "Receber em dinheiro" (a ação do dia
// a dia); "Desfazer a fatura" fica no menu, com confirmação (padrão AcoesDaLinha + useConfirmacao). O Pix
// não se recebe aqui: ele chega pelo Extrato, e o "Este Pix paga…" da linha tem a opção "Esta entrada paga
// a fatura" — o mesmo caminho de sempre, sem um segundo jeito de baixar conta.
// Os recebimentos que entraram pela fatura aparecem embaixo, cada um com "Desfazer este recebimento".
// Some sozinho quando o cliente não tem fatura.
import { useEffect, useState } from 'react';
import { Banknote, Layers } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { Campo } from '@/components/Campo';
import { MoneyInput } from '@/components/MoneyInput';
import { useConfirmacao } from '@/components/Confirmacao';
import { useI18n } from '@/i18n';
import { cn } from '@/lib/utils';
import { previaDoRecebimento } from '@/lib/fatura';
import {
  useDesfazerFatura, useDesfazerRecebimentoDaFatura, useFaturasDoCliente, useReceberFatura, useRecebimentosDaFatura,
  type FaturaResumo,
} from '@/hooks/use-faturas';
import { hojeLocal } from '../../../supabase/functions/_shared/receivables/cobrar-juntas';

export function FaturasDoCliente({ clienteId }: { clienteId: string | null | undefined }) {
  const { data: faturas = [], error } = useFaturasDoCliente(clienteId);
  const { pedir, dialogo } = useConfirmacao();
  const desfazer = useDesfazerFatura();
  const [emDinheiro, setEmDinheiro] = useState<FaturaResumo | null>(null);

  if (error) {
    return <p role="alert" className="rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-2 text-sm text-destructive">{(error as Error).message}</p>;
  }
  if (faturas.length === 0) return null;

  return (
    <section className="space-y-2" aria-label="Faturas do cliente" data-testid="faturas-do-cliente">
      {faturas.map((f) => (
        <CartaoDaFatura
          key={f.id}
          fatura={f}
          ocupada={desfazer.isPending}
          onReceberEmDinheiro={() => setEmDinheiro(f)}
          onDesfazer={() => pedir({
            titulo: `Desfazer a fatura ${f.numero}?`,
            descricao: `As contas de ${f.os.join(', ')} saem da fatura e voltam a ser cobradas cada uma pela sua OS. Nenhum valor muda.`,
            confirmar: 'Desfazer a fatura',
            voltar: 'Manter a fatura',
            acao: () => desfazer.mutate({ faturaId: f.id }),
          })}
          pedir={pedir}
        />
      ))}
      <ReceberEmDinheiro fatura={emDinheiro} onFechar={() => setEmDinheiro(null)} />
      {dialogo}
    </section>
  );
}

function CartaoDaFatura({
  fatura: f, ocupada, onReceberEmDinheiro, onDesfazer, pedir,
}: {
  fatura: FaturaResumo;
  ocupada: boolean;
  onReceberEmDinheiro: () => void;
  onDesfazer: () => void;
  pedir: ReturnType<typeof useConfirmacao>['pedir'];
}) {
  const { formatCurrency, formatDate } = useI18n();
  const aberta = f.status === 'open';
  return (
    <div className="min-w-0 space-y-3 rounded-lg border bg-card p-4 text-sm" data-testid={`fatura-${f.numero}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="flex items-center gap-2 font-semibold">
            <Layers className="h-4 w-4 shrink-0 text-primary" />
            Fatura {f.numero}
            <span className={cn('rounded-full px-2 py-0.5 text-xs font-medium',
              aberta ? 'bg-warning/15 text-warning' : 'bg-success/15 text-success')}>
              {aberta ? 'Aberta' : 'Quitada'}
            </span>
          </p>
          <p className="break-words text-xs text-muted-foreground">
            {f.os.join(', ')}{f.vencimento ? ` · vence ${formatDate(f.vencimento)}` : ''}
          </p>
        </div>
        <AcoesDaLinha
          rotulo={`fatura ${f.numero}`}
          ocupada={ocupada}
          rapidas={aberta ? [{ texto: 'Receber em dinheiro', icone: Banknote, onClick: onReceberEmDinheiro }] : []}
          menu={[{
            texto: 'Desfazer a fatura',
            perigo: true,
            onClick: onDesfazer,
            desabilitada: f.recebido > 0.005,
            titulo: f.recebido > 0.005 ? 'Já entrou dinheiro por ela: desfaça os recebimentos antes.' : undefined,
          }]}
        />
      </div>

      <dl className="grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
        <div className="min-w-0">
          <dt className="text-xs text-muted-foreground">Total</dt>
          <dd className="font-semibold tabular-nums">{formatCurrency(f.total)}</dd>
        </div>
        <div className="min-w-0">
          <dt className="text-xs text-muted-foreground">Recebido</dt>
          <dd className="font-semibold tabular-nums text-success">{formatCurrency(f.recebido)}</dd>
        </div>
        <div className="min-w-0">
          <dt className="text-xs text-muted-foreground">Falta</dt>
          <dd className="font-semibold tabular-nums" data-testid={`fatura-${f.numero}-saldo`}>{formatCurrency(f.saldo)}</dd>
        </div>
        <div className="min-w-0">
          <dt className="text-xs text-muted-foreground">Contas</dt>
          <dd className="font-semibold tabular-nums">{f.contas}</dd>
        </div>
      </dl>

      {aberta && (
        <p className="text-xs text-muted-foreground">
          Pix: no Extrato, abra a entrada e use “Este Pix paga…” › “Esta entrada paga a fatura {f.numero}”.
          As contas desta fatura só mudam por ela.
        </p>
      )}

      {f.recebido > 0.005 && <RecebimentosDaFatura fatura={f} pedir={pedir} />}
    </div>
  );
}

function RecebimentosDaFatura({ fatura: f, pedir }: { fatura: FaturaResumo; pedir: ReturnType<typeof useConfirmacao>['pedir'] }) {
  const { formatCurrency, formatDate } = useI18n();
  const { data: recebimentos = [], error } = useRecebimentosDaFatura(f.id, f.criadaEm);
  const desfazer = useDesfazerRecebimentoDaFatura();
  if (error) return <p role="alert" className="text-xs text-destructive">{(error as Error).message}</p>;
  if (recebimentos.length === 0) return null;
  return (
    <div className="space-y-1.5">
      <p className="text-xs text-muted-foreground">Recebimentos desta fatura</p>
      <ul className="space-y-1.5">
        {recebimentos.map((p) => (
          <li key={p.pagamentoId} className="flex min-w-0 items-center gap-2 rounded-md border bg-muted/30 px-3 py-1.5">
            <span className="min-w-0 flex-1">
              <span className="block truncate">{p.descricao}</span>
              <span className="block text-xs text-muted-foreground">
                {formatDate(p.data)} · {p.doExtrato ? 'do Extrato' : 'em dinheiro'}
              </span>
            </span>
            <span className="shrink-0 font-semibold tabular-nums">{formatCurrency(p.valor)}</span>
            <AcoesDaLinha
              rotulo={`recebimento de ${formatCurrency(p.valor)} em ${formatDate(p.data)}`}
              ocupada={desfazer.isPending}
              menu={[{
                texto: 'Desfazer este recebimento',
                perigo: true,
                onClick: () => pedir({
                  titulo: 'Desfazer este recebimento?',
                  descricao: `${formatCurrency(p.valor)} de ${formatDate(p.data)} (${p.descricao}) voltam a faltar na fatura ${f.numero}. `
                    + (p.doExtrato ? 'A entrada do banco volta para a fila do Extrato.' : 'O pagamento em dinheiro é estornado.'),
                  confirmar: 'Desfazer o recebimento',
                  acao: () => desfazer.mutate({ pagamentoId: p.pagamentoId }),
                }),
              }]}
            />
          </li>
        ))}
      </ul>
    </div>
  );
}

function ReceberEmDinheiro({ fatura, onFechar }: { fatura: FaturaResumo | null; onFechar: () => void }) {
  const { formatCurrency } = useI18n();
  const receber = useReceberFatura();
  const [valor, setValor] = useState(0);
  const [dia, setDia] = useState(hojeLocal());
  // Cada abertura começa com o que falta e com hoje.
  const faturaId = fatura?.id ?? null;
  const saldoNaAbertura = fatura?.saldo ?? 0;
  useEffect(() => {
    if (!faturaId) return;
    setValor(saldoNaAbertura);
    setDia(hojeLocal());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [faturaId]);

  const previa = fatura ? previaDoRecebimento(valor, fatura.saldo, 'dinheiro', formatCurrency) : null;
  const futuro = dia > hojeLocal();
  const pode = !!previa?.pode && !!dia && !futuro && !receber.isPending;

  return (
    <Dialog open={!!fatura} onOpenChange={(v) => { if (!v && !receber.isPending) onFechar(); }}>
      <DialogContent className="max-h-[90dvh] max-w-md overflow-y-auto" data-testid="receber-em-dinheiro">
        <DialogHeader>
          <DialogTitle>Receber em dinheiro{fatura ? ` — ${fatura.numero}` : ''}</DialogTitle>
          <DialogDescription>
            {fatura ? `Falta ${formatCurrency(fatura.saldo)}. A conta que vence primeiro recebe primeiro.` : ''}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-6 py-1">
          <Campo rotulo="Quanto entrou em dinheiro" htmlFor="fatura-dinheiro-valor">
            <MoneyInput id="fatura-dinheiro-valor" value={valor} onValueChange={setValor} />
          </Campo>
          <Campo rotulo="Dia do recebimento" htmlFor="fatura-dinheiro-dia" ajuda={futuro ? 'O dia não pode ser no futuro.' : undefined}>
            <Input id="fatura-dinheiro-dia" type="date" value={dia} max={hojeLocal()} onChange={(e) => setDia(e.target.value)} />
          </Campo>
          {previa && (
            <p className={cn('rounded-md border px-3 py-2 text-sm', previa.pode ? 'bg-muted/40' : 'border-destructive/40 bg-destructive/10 text-destructive')}
               data-testid="previa-dinheiro">
              {previa.mensagem}
            </p>
          )}
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onFechar} disabled={receber.isPending}>Voltar</Button>
          <Button
            disabled={!pode}
            onClick={() => fatura && receber.mutate({ faturaId: fatura.id, valor, data: dia }, { onSuccess: onFechar })}
          >
            {receber.isPending ? 'Gravando…' : 'Registrar recebimento'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
