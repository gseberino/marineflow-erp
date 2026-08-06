// O livro das transações que saíram da fila.
//
// POR QUE ESTA TELA EXISTE
// 380 transações (R$ 370 mil) tinham saído de vista com um texto solto em `dismissed_reason`
// e nada mais: sem quem, sem quando, sem tipo e sem volta. Cada caso estava certo —
// duplicata da importação, pagamento de fatura, transferência entre contas próprias, perna
// de compra parcelada — e o conjunto era inauditável. Para quem precisa confiar no número,
// inauditável dá no mesmo que errado: o gestor abriu a Conciliação, viu centenas de linhas
// ignoradas que não se lembrava de ter ignorado, e a suspeita foi de que a IA tinha feito
// aquilo sozinha.
//
// A regra que esta tela materializa: TODA saída da fila é reversível e diz quem, quando e
// por quê. É o que separa "o sistema resolveu" de "o sistema escondeu".
import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { useI18n } from '@/i18n';
import { useIgnoradas, useDesfazerIgnorada, type GrupoIgnorado } from '@/hooks/use-finance-review';
import { EyeOff, ChevronDown, Undo2, Info } from 'lucide-react';

/**
 * O que desfazer um grupo inteiro provoca.
 *
 * Escrito por tipo porque a consequência é diferente em cada um: devolver uma duplicata só
 * repõe a linha, enquanto devolver uma parcela desfaz o lançamento da compra inteira. Quem
 * clica precisa saber qual dos dois está prestes a acontecer.
 */
const CONSEQUENCIA: Record<string, string> = {
  duplicata: 'As transações voltam para a fila. Se elas forem mesmo duplicatas, você verá o mesmo movimento duas vezes.',
  fatura_cartao: 'O pagamento da fatura volta para a fila. Cuidado: os gastos do cartão já estão lançados item a item, então lançar a fatura de novo contaria tudo duas vezes.',
  transferencia: 'As duas pernas da transferência voltam para a fila — o dinheiro que saiu de uma conta e entrou na outra.',
  mecanica_cartao: 'Voltam para a fila. Estes lançamentos são mecânica do banco (limite, estorno, ajuste), não receita nem despesa.',
  parcela: 'ATENÇÃO: desfaz a COMPRA inteira. O lançamento criado é apagado e todas as parcelas voltam para a fila.',
  manual: 'As transações voltam para a fila.',
};

export function IgnoradasPanel() {
  const { formatCurrency, formatDate } = useI18n();
  const { data: grupos = [], isLoading } = useIgnoradas();
  const desfazer = useDesfazerIgnorada();
  const [aberto, setAberto] = useState<string | null>(null);
  const [confirmando, setConfirmando] = useState<GrupoIgnorado | null>(null);

  // Carregando com TÍTULO: uma aba que abre só com retângulos cinza não diz o que está
  // vindo, e quem clicou fica sem saber se errou de lugar ou se o sistema travou.
  if (isLoading) {
    return (
      <div className="space-y-3">
        <Card className="p-4">
          <h3 className="flex items-center gap-2 font-semibold">
            <EyeOff className="h-4 w-4 text-muted-foreground" />
            Transações fora da fila
          </h3>
          <p className="mt-1 text-sm text-muted-foreground">Carregando o que saiu da conciliação…</p>
        </Card>
        {[...Array(2)].map((_, i) => <Skeleton key={i} className="h-20 rounded-xl" />)}
      </div>
    );
  }

  const total = grupos.reduce((s, g) => s + g.transacoes.length, 0);
  const valor = grupos.reduce((s, g) => s + g.total, 0);

  if (total === 0) {
    return (
      <Card className="p-8 text-center">
        <p className="text-muted-foreground">
          Nenhuma transação foi tirada da fila. Quando isso acontecer — duplicata,
          transferência entre contas, parcela de uma compra —, ela aparece aqui com o motivo
          e o botão de desfazer.
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      <Card className="p-4">
        <h3 className="flex items-center gap-2 font-semibold">
          <EyeOff className="h-4 w-4 text-muted-foreground" />
          Transações fora da fila
        </h3>
        <p className="mt-1 text-sm text-muted-foreground">
          <strong>{total}</strong> transações, somando <strong>{formatCurrency(valor)}</strong>,
          foram tiradas da conciliação. Nenhuma some do sistema: todas estão aqui, com o
          motivo, e qualquer uma pode voltar.
        </p>
      </Card>

      {grupos.map((g) => (
        <Card key={g.kind} className="p-3">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-2">
                <span className="truncate font-medium">{g.rotulo}</span>
                <Badge variant="secondary" className="shrink-0 text-xs">
                  {g.transacoes.length}
                </Badge>
                <span className="font-semibold tabular-nums">{formatCurrency(g.total)}</span>
              </div>
              <p className="mt-1 break-words text-xs text-muted-foreground">{g.motivo}</p>
            </div>
            <Button
              size="sm"
              variant="outline"
              disabled={desfazer.isPending}
              onClick={() => setConfirmando(g)}
            >
              <Undo2 className="mr-2 h-4 w-4" />
              Devolver à fila
            </Button>
          </div>

          <Collapsible open={aberto === g.kind} onOpenChange={(v) => setAberto(v ? g.kind : null)}>
            <CollapsibleTrigger asChild>
              <button type="button" className="mt-2 inline-flex items-center gap-1 text-xs text-primary hover:underline">
                <Info className="h-3 w-3" />
                {aberto === g.kind ? 'Esconder' : `Ver as ${g.transacoes.length}`}
                <ChevronDown className={`h-3 w-3 transition-transform ${aberto === g.kind ? 'rotate-180' : ''}`} />
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent className="mt-2">
              <ul className="max-h-72 space-y-1 overflow-y-auto rounded-md border p-2 text-sm">
                {g.transacoes.map((t) => (
                  <li key={t.id} className="flex min-w-0 items-baseline justify-between gap-2">
                    <span className="min-w-0 flex-1 break-words">
                      <span className="text-muted-foreground">{formatDate(t.transaction_date)}</span>{' '}
                      {t.counterparty_name || t.description}
                    </span>
                    <span className="shrink-0 whitespace-nowrap font-medium tabular-nums">
                      {formatCurrency(t.amount)}
                    </span>
                    <Button
                      size="sm" variant="ghost" className="h-6 shrink-0 px-2 text-xs"
                      disabled={desfazer.isPending}
                      onClick={() => desfazer.mutate([t.id])}
                    >
                      Devolver
                    </Button>
                  </li>
                ))}
              </ul>
            </CollapsibleContent>
          </Collapsible>
        </Card>
      ))}

      <AlertDialog open={!!confirmando} onOpenChange={(v) => !v && setConfirmando(null)}>
        <AlertDialogContent className="max-w-[min(32rem,calc(100vw-2rem))] overflow-hidden">
          <AlertDialogHeader className="min-w-0">
            <AlertDialogTitle className="break-words">
              Devolver {confirmando?.transacoes.length} à fila?
            </AlertDialogTitle>
            <AlertDialogDescription className="break-words">
              {confirmando ? (CONSEQUENCIA[confirmando.kind] ?? CONSEQUENCIA.manual) : ''}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (confirmando) desfazer.mutate(confirmando.transacoes.map((t) => t.id));
                setConfirmando(null);
              }}
            >
              Devolver à fila
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
