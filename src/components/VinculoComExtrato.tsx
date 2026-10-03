/**
 * "Ligado ao extrato": dentro da correção de um lançamento, a linha do banco a que ele está
 * ligado, o que não bate (em palavras) e o conserto a um clique — com confirmação.
 *
 * Pedido do dono (02/10/2026): a correção só dizia "Veio do extrato. Para mudar, desfaça a
 * aprovação", sem dizer qual aprovação nem oferecer o botão. O diagnóstico é uma função pura e
 * testada (src/lib/vinculo-extrato.ts); as ações são funções do banco (ajustar_ao_valor_do_banco,
 * desfazer_aprovacao), com trilha e recusa de mês fechado.
 *
 * Um Pix para várias contas (forma A, F2 — 02/10/2026): a caixa mostra as outras contas que a
 * mesma entrada pagou (cada uma pode sair dela: desfazer_aplicacao) e, se sobrou parte da entrada,
 * oferece aplicá-la em outra conta ("Este Pix paga…").
 */
import { useState } from 'react';
import { Landmark } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useI18n } from '@/i18n';
import { cn } from '@/lib/utils';
import { diagnosticoDoVinculo } from '@/lib/vinculo-extrato';
import { BotaoEstePixPaga } from '@/components/EstePixPagaDialog';
import {
  useAjustarAoValorDoBanco, useDesfazerAplicacao, useDesfazerAprovacao, useEntradaAplicada, useVinculoComExtrato,
  type TipoDeLancamento,
} from '@/hooks/use-lancamentos';

type Confirmando = 'ajustar' | 'desfazer' | { tirar: string; descricao: string; valor: number } | null;

export function VinculoComExtrato({
  tipo, lancamentoId, valor, linhaId, mesFechado, onConcluido, clienteId,
}: {
  tipo: TipoDeLancamento;
  lancamentoId: string;
  valor: number;
  linhaId: string;
  mesFechado: boolean;
  /** Depois de ajustar ou desfazer, a correção fecha: o lançamento mudou por baixo dela. */
  onConcluido: () => void;
  /** O cliente da conta: o "Este Pix paga…" da sobra já abre nele. */
  clienteId?: string | null;
}) {
  const { formatCurrency, formatDate } = useI18n();
  const { data, isLoading } = useVinculoComExtrato(tipo, lancamentoId, linhaId);
  const { data: entrada } = useEntradaAplicada(tipo === 'receivable' ? linhaId : null);
  const ajustar = useAjustarAoValorDoBanco();
  const desfazer = useDesfazerAprovacao();
  const tirar = useDesfazerAplicacao();
  const [confirmando, setConfirmando] = useState<Confirmando>(null);

  if (isLoading) return <p className="text-xs text-muted-foreground">Lendo a linha do banco…</p>;
  if (!data) return null;

  const outras = (entrada?.aplicacoes ?? []).filter((a) => a.contaId !== lancamentoId);
  const d = diagnosticoDoVinculo({
    tipo, valor, linha: data.linha, pagamentos: data.pagamentos, nasceuDoExtrato: data.nasceuDoExtrato,
    formatar: formatCurrency, formatarData: formatDate,
    outrasContas: outras.map((o) => ({ descricao: o.descricao, valor: o.valor })),
    sobraDaEntrada: entrada?.sobra ?? 0,
  });
  const rotuloDesfazer = data.nasceuDoExtrato ? 'Desfazer a aprovação' : 'Desfazer o vínculo com o extrato';
  const ocupado = ajustar.isPending || desfazer.isPending || tirar.isPending;

  const confirmar = () => {
    const depois = { onSuccess: () => { setConfirmando(null); onConcluido(); } };
    if (confirmando === 'ajustar') ajustar.mutate({ tipo, id: lancamentoId }, depois);
    else if (confirmando === 'desfazer') desfazer.mutate({ tipo, id: lancamentoId }, depois);
    else if (confirmando) tirar.mutate({ pagamentoId: confirmando.tirar }, { onSuccess: () => setConfirmando(null) });
  };

  const textoDaConfirmacao = confirmando === 'ajustar'
    ? d.efeitoDoAjuste
    : confirmando === 'desfazer'
      ? d.efeitoDoDesfazer
      : confirmando
        ? `"${confirmando.descricao}" deixa de ser paga por esta entrada: os ${formatCurrency(confirmando.valor)} voltam a faltar nela `
          + '(se era um pagamento lançado à mão, ele continua valendo e só deixa de vir deste Pix). Fica na trilha.'
        : '';

  return (
    <div
      className={cn(
        'space-y-2 rounded-md border p-3 text-sm',
        d.situacao === 'bate' || (d.situacao === 'varias_contas' && !d.podeAplicarSobra) ? 'bg-muted/30' : 'border-amber-500/40 bg-amber-500/5',
      )}
    >
      <p className="flex items-start gap-1.5 font-medium">
        <Landmark className="mt-0.5 h-4 w-4 shrink-0" />
        <span className="min-w-0">
          Ligado ao extrato: {formatDate(data.linha.data)} · {data.linha.descricao} · {formatCurrency(Math.abs(data.linha.valor))}
        </span>
      </p>
      <p>{d.texto}</p>

      {outras.length > 0 && !mesFechado && !confirmando && (
        <ul className="space-y-1 text-xs">
          {outras.map((o) => (
            <li key={o.pagamentoId} className="flex flex-wrap items-center justify-between gap-2 rounded border bg-background px-2 py-1">
              <span className="min-w-0 truncate" title={o.descricao}>{o.descricao} · {formatCurrency(o.valor)}</span>
              <Button
                size="sm" variant="ghost" className="h-6 px-2 text-xs"
                onClick={() => setConfirmando({ tirar: o.pagamentoId, descricao: o.descricao, valor: o.valor })}
              >
                Tirar desta entrada
              </Button>
            </li>
          ))}
        </ul>
      )}

      {mesFechado ? (
        <p className="text-xs text-muted-foreground">
          O mês está fechado: para ajustar ou desfazer, reabra o mês em Conciliação › Fechar o mês.
        </p>
      ) : confirmando ? (
        <div className="space-y-2 rounded border bg-background p-2">
          <p className="text-xs">{textoDaConfirmacao}</p>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={confirmar} disabled={ocupado}>
              {ocupado ? 'Gravando…'
                : confirmando === 'ajustar' ? 'Confirmar ajuste'
                : confirmando === 'desfazer' ? `Confirmar: ${rotuloDesfazer.toLowerCase()}`
                : 'Confirmar: tirar desta entrada'}
            </Button>
            <Button size="sm" variant="outline" onClick={() => setConfirmando(null)} disabled={ocupado}>Voltar</Button>
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap gap-2">
          {d.podeAplicarSobra && d.rotuloDaSobra && (
            <BotaoEstePixPaga
              entradaId={linhaId}
              clienteInicial={clienteId ?? null}
              variante="outline"
              rotulo={d.rotuloDaSobra}
              onConcluido={onConcluido}
            />
          )}
          {d.podeAjustar && d.rotuloDoAjuste && (
            <Button size="sm" variant={d.podeAplicarSobra ? 'outline' : 'default'} onClick={() => setConfirmando('ajustar')}>
              {d.rotuloDoAjuste}
            </Button>
          )}
          <Button size="sm" variant="outline" onClick={() => setConfirmando('desfazer')}>{rotuloDesfazer}</Button>
        </div>
      )}
    </div>
  );
}
