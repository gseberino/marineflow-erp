// Desfazer a aprovação ou cancelar um lançamento — sempre dizendo antes o que vai acontecer.
//
// As duas ações parecem iguais para quem clica ("tirar isto daqui") e têm consequências
// diferentes para a linha do extrato:
//   * DESFAZER devolve a linha para a fila do Extrato, para aprovar de outro jeito. É o
//     botão de "aprovei errado".
//   * CANCELAR diz que o movimento não é receita nem despesa da empresa. A linha vai para
//     "Fora da fila" com o motivo — de lá ela pode voltar. É o "excluir" que não apaga nada.
import { useEffect, useState } from 'react';
import {
  AlertDialog, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useI18n } from '@/i18n';
import { useCancelarLancamento, useDesfazerAprovacao, type TipoDeLancamento } from '@/hooks/use-lancamentos';

export type AcaoNoLancamento = 'desfazer' | 'cancelar';

export interface LancamentoAlvo {
  id: string;
  description: string | null;
  amount: number | string | null;
  bank_transaction_id?: string | null;
  /** 'bank_reconciliation' = nasceu da aprovação de uma linha do extrato. */
  origin?: string | null;
}

export function DesfazerOuCancelarDialog({
  tipo, acao, lancamento, onFechar,
}: {
  tipo: TipoDeLancamento;
  acao: AcaoNoLancamento | null;
  lancamento: LancamentoAlvo | null;
  onFechar: () => void;
}) {
  const { formatCurrency } = useI18n();
  const desfazer = useDesfazerAprovacao();
  const cancelar = useCancelarLancamento();
  const [motivo, setMotivo] = useState('');

  useEffect(() => { setMotivo(''); }, [lancamento?.id, acao]);

  if (!lancamento || !acao) return null;

  const veioDoBanco = !!lancamento.bank_transaction_id;
  const nasceuDoExtrato = lancamento.origin === 'bank_reconciliation';
  const ocupado = desfazer.isPending || cancelar.isPending;
  const motivoOk = motivo.trim().length >= 3;
  const nome = `${lancamento.description ?? 'Lançamento'} · ${formatCurrency(Number(lancamento.amount ?? 0))}`;

  const confirmar = () => {
    const fim = { onSuccess: () => onFechar() };
    if (acao === 'desfazer') {
      desfazer.mutate({ tipo, id: lancamento.id, motivo: motivo.trim() || null }, fim);
    } else {
      cancelar.mutate({ tipo, id: lancamento.id, motivo: motivo.trim() }, fim);
    }
  };

  const consequencia = acao === 'desfazer'
    ? (nasceuDoExtrato
      ? 'O lançamento é cancelado e a linha do extrato volta para a fila do Extrato, com a proposta, para você aprovar do jeito certo.'
      : 'Se o lançamento nasceu da aprovação, ele é cancelado e a linha volta para a fila do Extrato. Se ele já existia e só foi casado com o extrato, perde o vínculo e continua valendo; o pagamento que o casamento registrou é estornado.')
    : ('O lançamento sai do resultado e das listas, mas continua registrado com o motivo — nada é apagado.'
      + (veioDoBanco
        ? (nasceuDoExtrato
          ? ' A linha do extrato vai para "Fora da fila" com o mesmo motivo; de lá ela pode voltar.'
          : ' A linha do extrato volta para a fila, porque o dinheiro passou pelo banco e precisa de destino.')
        : ' Pagamentos registrados nele são estornados.'));

  return (
    <AlertDialog open onOpenChange={(v) => { if (!v) onFechar(); }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{acao === 'desfazer' ? 'Desfazer a aprovação?' : 'Cancelar este lançamento?'}</AlertDialogTitle>
          <AlertDialogDescription className="space-y-2">
            <span className="block break-words font-medium text-foreground">{nome}</span>
            <span className="block">{consequencia}</span>
          </AlertDialogDescription>
        </AlertDialogHeader>

        <div className="space-y-1">
          <Label htmlFor="motivo-lancamento">
            Motivo
            {acao === 'desfazer' && <span className="font-normal text-muted-foreground"> (opcional)</span>}
          </Label>
          <Input
            id="motivo-lancamento"
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            placeholder={acao === 'cancelar' ? 'Ex.: despesa pessoal, lançada em dobro' : 'Ex.: aprovei na categoria errada'}
            autoFocus
          />
        </div>

        <AlertDialogFooter>
          <AlertDialogCancel disabled={ocupado}>Voltar</AlertDialogCancel>
          <Button
            variant={acao === 'cancelar' ? 'destructive' : 'default'}
            onClick={confirmar}
            disabled={ocupado || (acao === 'cancelar' && !motivoOk)}
          >
            {ocupado ? 'Aguarde…' : acao === 'desfazer' ? 'Desfazer aprovação' : 'Cancelar lançamento'}
          </Button>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
