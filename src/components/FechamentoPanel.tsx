// Fechar o mês, ler a trilha e conferir a integridade do extrato.
//
// POR QUE ESTA TELA EXISTE
// Três controles que os ERPs tratam como básicos e que faltavam aqui:
//
// 1. FECHAR O MÊS. Sem isso, uma conciliação feita hoje altera o resultado de um mês já
//    entregue ao contador, e ninguém percebe — o relatório é recalculado a cada abertura.
// 2. TRILHA. "O que foi feito no mês passado, por quem, e com base em quê" era uma
//    pergunta sem resposta: o rastro existia espalhado, nunca reunido.
// 3. CONFERÊNCIA DE SALDO. Responde a única pergunta que nenhuma outra responde — FALTA
//    transação? Um lançamento perdido na sincronização não deixa buraco visível: ele
//    simplesmente não existe para o sistema.
import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useI18n } from '@/i18n';
import {
  usePeriodosFechados, useFecharPeriodo, useReabrirPeriodo,
  useTrilhaDeConciliacao, useConferenciasDeSaldo, useChecklistDoMes, ROTULO_DA_ACAO,
} from '@/hooks/use-fechamento';
import { useBankConnections } from '@/hooks/use-bank-connections';
import { Lock, LockOpen, ScrollText, Scale, AlertTriangle, CheckCircle2, XCircle } from 'lucide-react';

const MESES = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

export function FechamentoPanel() {
  const { formatCurrency, formatDate } = useI18n();
  const { data: periodos = [], isLoading } = usePeriodosFechados();
  const { data: trilha = [] } = useTrilhaDeConciliacao();
  const { data: conferencias = [] } = useConferenciasDeSaldo();
  const fechar = useFecharPeriodo();
  const reabrir = useReabrirPeriodo();

  const hoje = new Date();
  // O mês CORRENTE não aparece de propósito: fechar um mês que ainda está acontecendo é
  // travar lançamento que ainda vai chegar.
  const [ano, setAno] = useState(hoje.getMonth() === 0 ? hoje.getFullYear() - 1 : hoje.getFullYear());
  const [mes, setMes] = useState(hoje.getMonth() === 0 ? 12 : hoje.getMonth());
  const [reabrindo, setReabrindo] = useState<string | null>(null);
  const [motivo, setMotivo] = useState('');
  // "Fechar mesmo assim" — só aparece quando a verificação não passou, e pede o porquê.
  const [assimMesmo, setAssimMesmo] = useState(false);
  const [motivoPendencia, setMotivoPendencia] = useState('');
  const checklist = useChecklistDoMes(ano, mes);

  const { data: conexoes = [] } = useBankConnections();

  /**
   * A última conferência de cada conta — a situação de HOJE.
   *
   * A tela listava as 50 últimas conferências e dizia "N não fecharam". Isso misturava
   * passado com presente: em 25/09/2026 ela mostraria seis conferências do C6 que falharam
   * por um erro de conta (débito somando em vez de subtrair), já corrigido. O que importa
   * para fechar o mês é se cada conta confere agora.
   */
  type Conferencia = { id: string; conferido_em: string; diferenca: number; fecha: boolean; observacao: string | null; bank_connection_id: string };
  const situacaoPorConta = useMemo(() => {
    const ultima = new Map<string, Conferencia>();
    for (const c of conferencias as Conferencia[]) {
      if (!ultima.has(c.bank_connection_id)) ultima.set(c.bank_connection_id, c);
    }
    return [...ultima.entries()].map(([id, c]) => ({
      id,
      conta: conexoes.find((x) => x.id === id)?.label ?? 'Conta',
      conferencia: c,
    }));
  }, [conferencias, conexoes]);
  const naoFechadas = situacaoPorConta.filter((s) => !s.conferencia.fecha);

  if (isLoading) {
    return (
      <div className="space-y-3">
        <Card className="p-4">
          <h3 className="flex items-center gap-2 font-semibold">
            <Lock className="h-4 w-4 text-muted-foreground" />
            Fechamento e auditoria
          </h3>
          <p className="mt-1 text-sm text-muted-foreground">Carregando os períodos…</p>
        </Card>
        <Skeleton className="h-20 rounded-xl" />
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <Card className="p-4">
        <h3 className="flex items-center gap-2 font-semibold">
          <Lock className="h-4 w-4 text-primary" />
          Fechar o mês
        </h3>
        <p className="mt-1 text-sm text-muted-foreground">
          Fechar diz <strong>estes números não mudam mais</strong>. Depois disso o sistema
          recusa lançamento com data no período — a trava está no banco, então vale também
          para o assistente e para qualquer integração.
        </p>

        <div className="mt-3 flex flex-wrap items-end gap-2">
          <Select value={String(mes)} onValueChange={(v) => setMes(Number(v))}>
            <SelectTrigger className="h-9 w-40" aria-label="Mês"><SelectValue /></SelectTrigger>
            <SelectContent>
              {MESES.map((m, i) => <SelectItem key={m} value={String(i + 1)}>{m}</SelectItem>)}
            </SelectContent>
          </Select>
          <Input
            type="number" className="h-9 w-28" value={ano} aria-label="Ano"
            onChange={(e) => setAno(Number(e.target.value))}
          />
          <Button
            size="sm"
            disabled={fechar.isPending || checklist.isLoading || !checklist.data?.pronto}
            title={checklist.data?.pronto ? undefined : 'O mês ainda não está pronto: veja os itens abaixo'}
            onClick={() => fechar.mutate({ ano, mes })}
          >
            <Lock className="mr-2 h-4 w-4" />
            Fechar {MESES[mes - 1]}/{ano}
          </Button>
        </div>

        {/* O MÊS ESTÁ PRONTO? — o que separa "fechei" de "fechei com prova". Calculado no
            banco; o fechamento confere de novo no clique, então a tela velha não fecha nada. */}
        <div className="mt-3 rounded-md border p-3">
          <p className="mb-2 text-sm font-medium">
            O mês está pronto?{' '}
            {checklist.data && (
              checklist.data.pronto
                ? <span className="text-success">Sim — pode fechar.</span>
                : <span className="text-destructive">Ainda não.</span>
            )}
          </p>
          {checklist.isLoading && <Skeleton className="h-24 w-full" />}
          {checklist.error && <p className="text-sm text-destructive">Não deu para verificar o mês: {(checklist.error as Error).message}</p>}
          <ul className="space-y-1.5 text-sm">
            {(checklist.data?.itens ?? []).map((i) => (
              <li key={i.chave} className="flex min-w-0 items-start gap-2">
                {i.ok
                  ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-success" />
                  : i.bloqueia
                    ? <XCircle className="mt-0.5 h-4 w-4 shrink-0 text-destructive" />
                    : <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />}
                <span className="min-w-0 flex-1">
                  <span className="block">{i.titulo}{!i.ok && !i.bloqueia ? ' (aviso)' : ''}</span>
                  <span className="block text-xs text-muted-foreground">{i.detalhe}</span>
                </span>
              </li>
            ))}
          </ul>
          {checklist.data && !checklist.data.pronto && (
            assimMesmo ? (
              <div className="mt-3 flex flex-wrap items-center gap-2">
                <Input
                  className="h-9 min-w-0 flex-1" placeholder="Por que fechar com pendência? (vai para a trilha)"
                  value={motivoPendencia} onChange={(e) => setMotivoPendencia(e.target.value)}
                />
                <Button size="sm" variant="destructive"
                  disabled={motivoPendencia.trim().length < 10 || fechar.isPending}
                  onClick={() => fechar.mutate({ ano, mes, motivo: motivoPendencia.trim() }, {
                    onSuccess: () => { setAssimMesmo(false); setMotivoPendencia(''); },
                  })}>
                  Fechar com pendência
                </Button>
                <Button size="sm" variant="ghost" onClick={() => setAssimMesmo(false)}>Cancelar</Button>
              </div>
            ) : (
              <Button size="sm" variant="ghost" className="mt-2 h-8 text-xs" onClick={() => setAssimMesmo(true)}>
                Fechar mesmo assim…
              </Button>
            )
          )}
        </div>
      </Card>

      {periodos.length > 0 && (
        <Card className="p-3">
          <p className="mb-2 text-sm font-medium">Períodos</p>
          <ul className="space-y-1 text-sm">
            {periodos.map((p) => (
              <li key={p.id} className="flex min-w-0 flex-wrap items-center justify-between gap-2 rounded border p-2">
                <span className="min-w-0 flex-1 break-words">
                  <strong>{MESES[p.mes - 1]}/{p.ano}</strong>
                  {p.reaberto_em ? (
                    <>
                      <Badge variant="outline" className="ml-2 border-amber-500/50 text-xs text-amber-600">
                        reaberto
                      </Badge>
                      {p.motivo_da_reabertura && (
                        <span className="ml-2 text-xs text-muted-foreground">{p.motivo_da_reabertura}</span>
                      )}
                    </>
                  ) : (
                    <Badge variant="secondary" className="ml-2 text-xs">fechado</Badge>
                  )}
                </span>
                {!p.reaberto_em && (
                  reabrindo === p.id ? (
                    <span className="flex flex-wrap items-center gap-2">
                      <Input
                        autoFocus className="h-8 w-56" placeholder="Por que está reabrindo?"
                        value={motivo} onChange={(e) => setMotivo(e.target.value)}
                      />
                      <Button size="sm" disabled={!motivo.trim() || reabrir.isPending}
                        onClick={() => { reabrir.mutate({ id: p.id, motivo }); setReabrindo(null); setMotivo(''); }}>
                        Reabrir
                      </Button>
                      <Button size="sm" variant="ghost" onClick={() => setReabrindo(null)}>Cancelar</Button>
                    </span>
                  ) : (
                    <Button size="sm" variant="ghost" onClick={() => setReabrindo(p.id)}>
                      <LockOpen className="mr-1 h-3 w-3" />Reabrir
                    </Button>
                  )
                )}
              </li>
            ))}
          </ul>
        </Card>
      )}

      {/* A conferência responde "falta transação?". Só aparece quando NÃO fecha, porque o
          normal é fechar e uma lista de "tudo certo" vira ruído que ninguém lê. */}
      {naoFechadas.length > 0 && (
        <Card className="border-amber-500/40 bg-amber-500/5 p-3">
          <p className="flex items-center gap-2 text-sm font-medium text-amber-700">
            <AlertTriangle className="h-4 w-4" />
            {naoFechadas.length === 1 ? 'Uma conta não confere' : `${naoFechadas.length} contas não conferem`} com o saldo do banco
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            O saldo que o banco informa não bate com o que as transações explicam. Se a
            diferença sumir na próxima sincronização, era só atraso do banco; se continuar,
            confira no app do banco se falta alguma transação no sistema.
          </p>
          <ul className="mt-2 space-y-1 text-sm">
            {naoFechadas.map((s) => (
              <li key={s.id} className="flex min-w-0 justify-between gap-2">
                <span className="min-w-0 truncate">{s.conta} · {formatDate(s.conferencia.conferido_em.slice(0, 10))}</span>
                <span className="shrink-0 font-semibold tabular-nums">{formatCurrency(Number(s.conferencia.diferenca))}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      <Card className="p-3">
        <p className="mb-2 flex items-center gap-2 text-sm font-medium">
          <ScrollText className="h-4 w-4 text-muted-foreground" />
          O que foi feito ({trilha.length})
        </p>
        {trilha.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Ainda não há registro. A partir de agora, toda aprovação, ignorada e devolução
            fica anotada aqui — com autor, valor e o que mudou.
          </p>
        ) : (
          <ul className="max-h-96 space-y-1 overflow-y-auto text-sm">
            {trilha.map((l) => (
              <li key={l.id} className="flex min-w-0 items-baseline justify-between gap-2 border-b py-1 last:border-0">
                <span className="min-w-0 flex-1 break-words">
                  <span className="text-muted-foreground">{formatDate(l.ocorrido_em.slice(0, 10))}</span>{' '}
                  <Badge variant="outline" className="text-xs">{ROTULO_DA_ACAO[l.acao] ?? l.acao}</Badge>{' '}
                  {l.detalhe}
                </span>
                {l.valor != null && (
                  <span className="shrink-0 whitespace-nowrap tabular-nums">
                    {formatCurrency(Number(l.valor))}
                  </span>
                )}
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card className="p-3">
        <p className="flex items-center gap-2 text-sm font-medium">
          <Scale className="h-4 w-4 text-muted-foreground" />
          Integridade do extrato
        </p>
        {situacaoPorConta.length === 0 ? (
          <p className="mt-1 text-xs text-muted-foreground">
            Nenhuma conferência ainda. Ela roda a cada sincronização bancária, às 06:00 e às 15:00.
          </p>
        ) : (
          <ul className="mt-2 space-y-1 text-sm">
            {situacaoPorConta.map((s) => (
              <li key={s.id} className="flex min-w-0 items-center justify-between gap-2">
                <span className="min-w-0 truncate">{s.conta}</span>
                {s.conferencia.fecha
                  ? <Badge variant="secondary" className="shrink-0 text-xs">confere</Badge>
                  : <Badge variant="outline" className="shrink-0 border-amber-500/50 text-xs text-amber-600">difere {formatCurrency(Math.abs(Number(s.conferencia.diferenca)))}</Badge>}
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
