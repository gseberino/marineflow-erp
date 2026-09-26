// As fichas de saldo: uma por conta, com o Caixa e os dois botões dele sempre à vista.
//
// O dono não achou o "Contei o dinheiro" (26/09/2026): os botões só apareciam depois de
// trocar um seletor escondido ("Todas as contas" → "Caixa"). Aqui cada conta é uma ficha com
// o saldo; no Extrato, clicar na ficha escolhe a conta (substitui o seletor).
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { useI18n } from '@/i18n';
import { useSaldoDasContas, type SaldoDaConta } from '@/hooks/use-saldo-das-contas';
import { LancarDialog } from '@/components/LancarDialog';
import { Ajuda } from '@/components/Ajuda';
import { Banknote, Calculator, Landmark, AlertTriangle, Check } from 'lucide-react';
import { cn } from '@/lib/utils';

function quando(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });
}

function Situacao({ c }: { c: SaldoDaConta }) {
  const { formatCurrency } = useI18n();
  if (c.ehCaixa) {
    return c.contado
      ? <span className="text-xs text-muted-foreground">pelo que foi lançado</span>
      : <span className="flex items-center gap-1 text-xs text-amber-600"><AlertTriangle className="h-3 w-3" /> conte o dinheiro para começar</span>;
  }
  if (c.confere == null) return <span className="text-xs text-muted-foreground">ainda sem conferência</span>;
  return c.confere
    ? <span className="flex items-center gap-1 text-xs text-muted-foreground"><Check className="h-3 w-3 text-success" /> confere · {quando(c.conferidoEm)}</span>
    : <span className="text-xs text-amber-600">difere {formatCurrency(Math.abs(c.diferenca ?? 0))} · {quando(c.conferidoEm)}</span>;
}

export function SaldosDasContas({ contaAtiva, onEscolher, mostrarTotal = true, className }: {
  /** Conta escolhida (Extrato). undefined = fichas só informativas. */
  contaAtiva?: string | null;
  onEscolher?: (id: string | null) => void;
  mostrarTotal?: boolean;
  className?: string;
}) {
  const { formatCurrency } = useI18n();
  const { data, isLoading, error } = useSaldoDasContas();
  const [dialogo, setDialogo] = useState<'lancar' | 'contar' | null>(null);
  const escolhe = !!onEscolher;

  if (isLoading) return <Skeleton className={cn('h-20 w-full', className)} />;
  if (error || !data) {
    return <p className={cn('text-sm text-destructive', className)}>Não consegui ler os saldos: {String((error as Error)?.message ?? 'erro')}</p>;
  }

  const ficha = 'min-w-0 rounded-lg border bg-card p-2.5 text-left transition-colors';
  const ativa = (id: string | null) => escolhe && (contaAtiva ?? null) === id;

  return (
    <div className={cn('space-y-2', className)}>
      {mostrarTotal && (
        <p className="flex flex-wrap items-center gap-1 text-sm">
          <span className="text-muted-foreground">Dinheiro disponível:</span>
          <b className="tabular-nums">{formatCurrency(data.disponivel)}</b>
          <Ajuda rotulo="Como é calculado o dinheiro disponível">
            Soma do saldo que cada banco informou na última busca (6h e 15h) com o saldo do Caixa em
            dinheiro. O saldo do banco vem do próprio banco; o do Caixa, do que foi lançado e contado.
          </Ajuda>
        </p>
      )}
      <div className="grid grid-cols-[repeat(auto-fill,minmax(11rem,1fr))] gap-2">
        {escolhe && (
          <button type="button" aria-pressed={ativa(null)} onClick={() => onEscolher?.(null)}
            className={cn(ficha, 'hover:bg-muted/50', ativa(null) && 'border-primary ring-1 ring-primary')}>
            <span className="block text-xs text-muted-foreground">Todas as contas</span>
            <span className="block font-semibold tabular-nums">{formatCurrency(data.disponivel)}</span>
          </button>
        )}
        {data.contas.map((c) => {
          const cabeca = (
            <>
              <span className="flex min-w-0 items-center gap-1 text-xs text-muted-foreground">
                {c.ehCaixa ? <Banknote className="h-3 w-3 shrink-0" /> : <Landmark className="h-3 w-3 shrink-0" />}
                <span className="truncate">{c.nome}</span>
              </span>
              <span className={cn('block font-semibold tabular-nums', (c.saldo ?? 0) < 0 && 'text-destructive')}>
                {c.saldo == null ? '—' : formatCurrency(c.saldo)}
              </span>
              <Situacao c={c} />
            </>
          );
          return (
            <div key={c.id} className={cn(ficha, 'flex flex-col gap-1.5', ativa(c.id) && 'border-primary ring-1 ring-primary')}>
              {escolhe
                ? <button type="button" aria-pressed={ativa(c.id)} onClick={() => onEscolher?.(c.id)} className="min-w-0 text-left">{cabeca}</button>
                : <div className="min-w-0">{cabeca}</div>}
              {c.ehCaixa && (
                <div className="flex flex-wrap gap-1">
                  <Button size="sm" className="h-7 gap-1 px-2 text-xs" onClick={() => setDialogo('lancar')}>
                    <Banknote className="h-3.5 w-3.5" /> Lançar
                  </Button>
                  <Button size="sm" variant="outline" className="h-7 gap-1 px-2 text-xs" onClick={() => setDialogo('contar')}>
                    <Calculator className="h-3.5 w-3.5" /> Contei o dinheiro
                  </Button>
                </div>
              )}
            </div>
          );
        })}
      </div>
      {/* A mesma janela do "+ Lançar", já em Dinheiro do Caixa / Contei o dinheiro: uma porta só. */}
      {dialogo === 'lancar' && <LancarDialog porOndeInicial="caixa" onFechar={() => setDialogo(null)} />}
      {dialogo === 'contar' && <LancarDialog tipoInicial="contagem" onFechar={() => setDialogo(null)} />}
    </div>
  );
}
