/**
 * "Ligado ao extrato": dentro da correção de um lançamento, a linha do banco a que ele está
 * ligado, o que não bate (em palavras) e o conserto a um clique — com confirmação.
 *
 * Pedido do dono (02/10/2026): a correção só dizia "Veio do extrato. Para mudar, desfaça a
 * aprovação", sem dizer qual aprovação nem oferecer o botão. O diagnóstico é uma função pura e
 * testada (src/lib/vinculo-extrato.ts); as ações são funções do banco (ajustar_ao_valor_do_banco,
 * desfazer_aprovacao), com trilha e recusa de mês fechado.
 */
import { useState } from 'react';
import { Landmark } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useI18n } from '@/i18n';
import { cn } from '@/lib/utils';
import { diagnosticoDoVinculo } from '@/lib/vinculo-extrato';
import {
  useAjustarAoValorDoBanco, useDesfazerAprovacao, useVinculoComExtrato, type TipoDeLancamento,
} from '@/hooks/use-lancamentos';

export function VinculoComExtrato({
  tipo, lancamentoId, valor, linhaId, mesFechado, onConcluido,
}: {
  tipo: TipoDeLancamento;
  lancamentoId: string;
  valor: number;
  linhaId: string;
  mesFechado: boolean;
  /** Depois de ajustar ou desfazer, a correção fecha: o lançamento mudou por baixo dela. */
  onConcluido: () => void;
}) {
  const { formatCurrency, formatDate } = useI18n();
  const { data, isLoading } = useVinculoComExtrato(tipo, lancamentoId, linhaId);
  const ajustar = useAjustarAoValorDoBanco();
  const desfazer = useDesfazerAprovacao();
  const [confirmando, setConfirmando] = useState<'ajustar' | 'desfazer' | null>(null);

  if (isLoading) return <p className="text-xs text-muted-foreground">Lendo a linha do banco…</p>;
  if (!data) return null;

  const d = diagnosticoDoVinculo({
    tipo, valor, linha: data.linha, pagamentos: data.pagamentos, nasceuDoExtrato: data.nasceuDoExtrato,
    formatar: formatCurrency, formatarData: formatDate,
  });
  const rotuloDesfazer = data.nasceuDoExtrato ? 'Desfazer a aprovação' : 'Desfazer o vínculo com o extrato';
  const ocupado = ajustar.isPending || desfazer.isPending;

  const confirmar = () => {
    const depois = { onSuccess: () => { setConfirmando(null); onConcluido(); } };
    if (confirmando === 'ajustar') ajustar.mutate({ tipo, id: lancamentoId }, depois);
    else desfazer.mutate({ tipo, id: lancamentoId }, depois);
  };

  return (
    <div
      className={cn(
        'space-y-2 rounded-md border p-3 text-sm',
        d.situacao === 'bate' ? 'bg-muted/30' : 'border-amber-500/40 bg-amber-500/5',
      )}
    >
      <p className="flex items-start gap-1.5 font-medium">
        <Landmark className="mt-0.5 h-4 w-4 shrink-0" />
        <span className="min-w-0">
          Ligado ao extrato: {formatDate(data.linha.data)} · {data.linha.descricao} · {formatCurrency(Math.abs(data.linha.valor))}
        </span>
      </p>
      <p>{d.texto}</p>

      {mesFechado ? (
        <p className="text-xs text-muted-foreground">
          O mês está fechado: para ajustar ou desfazer, reabra o mês em Conciliação › Fechar o mês.
        </p>
      ) : confirmando ? (
        <div className="space-y-2 rounded border bg-background p-2">
          <p className="text-xs">{confirmando === 'ajustar' ? d.efeitoDoAjuste : d.efeitoDoDesfazer}</p>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={confirmar} disabled={ocupado}>
              {ocupado ? 'Gravando…' : confirmando === 'ajustar' ? 'Confirmar ajuste' : `Confirmar: ${rotuloDesfazer.toLowerCase()}`}
            </Button>
            <Button size="sm" variant="outline" onClick={() => setConfirmando(null)} disabled={ocupado}>Voltar</Button>
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap gap-2">
          {d.podeAjustar && d.rotuloDoAjuste && (
            <Button size="sm" onClick={() => setConfirmando('ajustar')}>{d.rotuloDoAjuste}</Button>
          )}
          <Button size="sm" variant="outline" onClick={() => setConfirmando('desfazer')}>{rotuloDesfazer}</Button>
        </div>
      )}
    </div>
  );
}
