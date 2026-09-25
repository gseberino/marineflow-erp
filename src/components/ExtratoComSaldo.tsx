// O extrato de uma conta como o banco mostra — com saldo linha a linha — e o que cada
// linha virou no sistema.
//
// Fase 3.2 do Financeiro Confiável. A fila do Extrato mostra o que FALTA decidir; esta tela
// mostra o mês inteiro da conta, para conferir com o app do banco de olho: mesmo saldo,
// mesmas linhas, e ao lado de cada uma o lançamento que ela gerou (ou por que não gerou).
// O saldo é a mesma conta da conferência de saldo, calculada no banco.
import { useMemo, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { useI18n } from '@/i18n';
import { supabase } from '@/integrations/supabase/client';
import { useExtratoDaConta, type LinhaDoExtrato } from '@/hooks/use-extrato-conta';
import { CorrigirLancamentoDialog, type LancamentoParaCorrigir } from '@/components/CorrigirLancamentoDialog';
import { DesfazerOuCancelarDialog } from '@/components/DesfazerOuCancelarDialog';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { casaComBusca } from '@/lib/busca-financeira';
import { Pencil, Undo2, AlertTriangle } from 'lucide-react';
import { toast } from 'sonner';

type Filtro = 'tudo' | 'lancadas' | 'fila' | 'fora' | 'sem_destino';

const ROTULO_DO_FILTRO: Record<Filtro, string> = {
  tudo: 'Tudo', lancadas: 'Lançadas', fila: 'Na fila', fora: 'Fora da fila', sem_destino: 'Sem destino',
};

function passaNoFiltro(l: LinhaDoExtrato, f: Filtro): boolean {
  if (f === 'tudo') return true;
  if (f === 'lancadas') return l.situacao === 'lancada' || l.situacao === 'conciliada';
  if (f === 'fila') return !!l.proposta_id;
  if (f === 'fora') return l.situacao === 'fora';
  return l.situacao === 'nova' && !l.proposta_id;
}

function mesAtual(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

function limitesDoMes(mes: string): { de: string; ate: string } {
  const [a, m] = mes.split('-').map(Number);
  const ultimo = new Date(a, m, 0).getDate();
  return { de: `${mes}-01`, ate: `${mes}-${String(ultimo).padStart(2, '0')}` };
}

export function ExtratoComSaldo({ conexaoId, nomeDaConta }: { conexaoId: string; nomeDaConta: string }) {
  const { formatCurrency, formatDate } = useI18n();
  const [mes, setMes] = useState(mesAtual());
  const [filtro, setFiltro] = useState<Filtro>('tudo');
  const [busca, setBusca] = useState('');
  const { de, ate } = limitesDoMes(mes);
  const { data: linhas = [], isLoading, error } = useExtratoDaConta(conexaoId, de, ate);

  const [corrigindo, setCorrigindo] = useState<{ tipo: 'payable' | 'receivable'; l: LancamentoParaCorrigir } | null>(null);
  const [desfazendo, setDesfazendo] = useState<{ tipo: 'payable' | 'receivable'; l: LancamentoParaCorrigir & { origin?: string | null } } | null>(null);

  const visiveis = useMemo(
    () => linhas.filter((l) => passaNoFiltro(l, filtro)
      && casaComBusca({ textos: [l.descricao, l.contraparte, l.documento, l.quem, l.categoria], valores: [Math.abs(l.valor)] }, { termo: busca })),
    [linhas, filtro, busca],
  );

  // A linha mais antiga do mês traz o saldo de ABERTURA (saldo dela menos o próprio valor).
  const resumo = useMemo(() => {
    const efetivas = linhas.filter((l) => !l.pendente);
    const entradas = efetivas.filter((l) => l.valor > 0).reduce((s, l) => s + l.valor, 0);
    const saidas = efetivas.filter((l) => l.valor < 0).reduce((s, l) => s - l.valor, 0);
    const maisNova = efetivas.find((l) => l.saldo_apos != null);
    const maisAntiga = [...efetivas].reverse().find((l) => l.saldo_apos != null);
    return {
      entradas, saidas,
      final: maisNova?.saldo_apos ?? null,
      inicial: maisAntiga?.saldo_apos != null ? maisAntiga.saldo_apos - maisAntiga.valor : null,
    };
  }, [linhas]);

  const contagem = useMemo(() => {
    const c: Record<Filtro, number> = { tudo: linhas.length, lancadas: 0, fila: 0, fora: 0, sem_destino: 0 };
    for (const l of linhas) for (const f of ['lancadas', 'fila', 'fora', 'sem_destino'] as Filtro[]) if (passaNoFiltro(l, f)) c[f] += 1;
    return c;
  }, [linhas]);

  /** Busca o lançamento inteiro só na hora de corrigir: a lista não precisa carregá-lo. */
  const abrir = async (l: LinhaDoExtrato, acao: 'corrigir' | 'desfazer') => {
    if (!l.lancamento_id || !l.lancamento_tipo) return;
    const tabela = l.lancamento_tipo === 'payable' ? 'payables' : 'receivables';
    const { data, error: e } = await supabase.from(tabela).select('*').eq('id', l.lancamento_id).maybeSingle();
    if (e || !data) { toast.error('Não deu para abrir o lançamento.'); return; }
    if (acao === 'corrigir') setCorrigindo({ tipo: l.lancamento_tipo, l: data as unknown as LancamentoParaCorrigir });
    else setDesfazendo({ tipo: l.lancamento_tipo, l: data as never });
  };

  return (
    <div className="space-y-3">
      <Card className="p-3">
        <div className="flex flex-wrap items-center gap-2">
          <Input type="month" value={mes} onChange={(e) => e.target.value && setMes(e.target.value)} className="h-9 w-40" aria-label="Mês" />
          <Input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar nome, CPF/CNPJ ou valor" className="h-9 min-w-0 flex-1 basis-48" aria-label="Buscar no extrato" />
        </div>
        <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
          {[
            ['Saldo no início', resumo.inicial],
            ['Entradas', resumo.entradas],
            ['Saídas', resumo.saidas],
            ['Saldo no fim', resumo.final],
          ].map(([r, v]) => (
            <div key={String(r)} className="rounded-md border p-2">
              <p className="truncate text-xs text-muted-foreground">{r}</p>
              <p className="truncate font-semibold tabular-nums">{v == null ? '—' : formatCurrency(Number(v))}</p>
            </div>
          ))}
        </div>
        {resumo.final == null && linhas.length > 0 && (
          <p className="mt-2 flex items-start gap-1.5 text-xs text-muted-foreground">
            <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
            O saldo aparece depois da próxima sincronização de {nomeDaConta}, que fixa a linha de base da conta.
          </p>
        )}
        <div className="mt-3 flex flex-wrap gap-1.5">
          {(Object.keys(ROTULO_DO_FILTRO) as Filtro[]).map((f) => (
            <Button key={f} size="sm" variant={filtro === f ? 'default' : 'outline'} className="h-7 text-xs" onClick={() => setFiltro(f)}>
              {ROTULO_DO_FILTRO[f]} ({contagem[f]})
            </Button>
          ))}
        </div>
      </Card>

      {isLoading ? (
        <Skeleton className="h-48 w-full" />
      ) : error ? (
        <Card className="border-destructive/40 p-4 text-sm text-destructive">Não deu para carregar o extrato: {(error as Error).message}</Card>
      ) : visiveis.length === 0 ? (
        <Card className="p-6 text-center text-sm text-muted-foreground">Nenhuma linha {filtro === 'tudo' && !busca ? 'neste mês' : 'com este filtro'}.</Card>
      ) : (
        <Card className="divide-y p-0">
          {visiveis.map((l) => (
            <div key={l.id} className={`flex min-w-0 items-start gap-3 p-3 ${l.pendente ? 'opacity-60' : ''}`}>
              <div className="min-w-0 flex-1">
                <p className="flex min-w-0 flex-wrap items-center gap-x-2 text-sm">
                  <span className="shrink-0 text-muted-foreground">{formatDate(l.data)}</span>
                  <span className="min-w-0 truncate font-medium">{l.contraparte || l.descricao || 'Sem descrição'}</span>
                  {l.pendente && <Badge variant="outline" className="text-[10px]">pendente no banco</Badge>}
                </p>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  {l.situacao === 'lancada' || l.situacao === 'conciliada'
                    ? <>Lançada: <b className="text-foreground">{l.categoria ?? 'sem categoria'}</b>{l.quem ? ` · ${l.quem}` : ''}</>
                    : l.situacao === 'fora'
                      ? <>Fora da fila: {l.motivo_fora ?? l.tipo_fora}</>
                      : l.proposta_id
                        ? 'Esperando decisão no Extrato'
                        : l.situacao === 'sem_rastro' ? 'Marcada como tratada, sem lançamento ligado' : 'Sem destino'}
                </p>
              </div>
              <div className="shrink-0 text-right">
                <p className={`font-semibold tabular-nums ${l.valor < 0 ? 'text-destructive' : 'text-success'}`}>{formatCurrency(l.valor)}</p>
                {l.saldo_apos != null && <p className="text-xs tabular-nums text-muted-foreground">saldo {formatCurrency(l.saldo_apos)}</p>}
              </div>
              {l.lancamento_id && (
                <AcoesDaLinha
                  rotulo={l.contraparte || l.descricao || 'linha'}
                  menu={[
                    { texto: 'Corrigir lançamento', icone: Pencil, onClick: () => { void abrir(l, 'corrigir'); } },
                    { texto: 'Desfazer aprovação', icone: Undo2, onClick: () => { void abrir(l, 'desfazer'); } },
                  ]}
                />
              )}
            </div>
          ))}
        </Card>
      )}

      {/* Montados só quando abertos: o formulário de correção carrega fornecedores, clientes,
          favorecidos e OS, e não há por que fazer isso a cada abertura do extrato. */}
      {corrigindo && <CorrigirLancamentoDialog tipo={corrigindo.tipo} lancamento={corrigindo.l} onFechar={() => setCorrigindo(null)} />}
      {desfazendo && (
        <DesfazerOuCancelarDialog tipo={desfazendo.tipo} acao="desfazer" lancamento={desfazendo.l} onFechar={() => setDesfazendo(null)} />
      )}
    </div>
  );
}
