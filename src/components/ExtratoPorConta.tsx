// O Extrato, conta por conta (Fase 3.2 do Financeiro Confiável).
//
// No desenho do Xero e do QuickBooks, cada conta tem a sua área: o que falta decidir, o
// extrato com saldo e o que saiu da fila. Aqui isso vive DENTRO do Extrato — o destino do
// menu continua o mesmo (decisão do dono de 23/09: menu é destino, aba é recorte), e
// "Fora da fila", que era aba solta, passa a ser uma das visões da conta.
import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useI18n } from '@/i18n';
import { useBankConnections } from '@/hooks/use-bank-connections';
import { useConferenciasDeSaldo } from '@/hooks/use-fechamento';
import { useLancadosSozinhos } from '@/hooks/use-extrato-conta';
import { useAppSetting, useUpdateAppSetting } from '@/hooks/use-app-settings';
import { useDesfazerAprovacao } from '@/hooks/use-lancamentos';
import { FinanceReviewInbox, type SementeDeRegra } from '@/components/FinanceReviewInbox';
import { IgnoradasPanel } from '@/components/IgnoradasPanel';
import { ExtratoComSaldo } from '@/components/ExtratoComSaldo';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Bot, ChevronDown, Undo2, Banknote, Calculator, NotebookPen } from 'lucide-react';
import { AjustarCaixaDialog, AnotacoesAguardando, AnotarTransacaoDialog, LancarNoCaixaDialog } from '@/components/CaixaDialogs';

export type VisaoDoExtrato = 'revisar' | 'saldo' | 'fora';
const TODAS = '__todas__';

/** O que o sistema lançou sem clique, com o interruptor e o desfazer. */
function LancadosSozinhos({ contaId }: { contaId: string | null }) {
  const { formatCurrency, formatDate } = useI18n();
  const { data = [] } = useLancadosSozinhos();
  const ligado = useAppSetting('finance_auto_approve', 'off') === 'on';
  const salvar = useUpdateAppSetting();
  const desfazer = useDesfazerAprovacao();
  const [aberto, setAberto] = useState(false);
  const lista = useMemo(
    () => data.filter((l) => !contaId || l.bank_transactions?.bank_connection_id === contaId),
    [data, contaId],
  );
  const total = lista.reduce((s, l) => s + Number(l.suggested_amount ?? 0), 0);

  return (
    <Card className="p-3">
      <Collapsible open={aberto} onOpenChange={setAberto}>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CollapsibleTrigger asChild>
            <button type="button" className="flex min-w-0 items-center gap-2 text-left text-sm">
              <Bot className="h-4 w-4 shrink-0 text-primary" />
              <span className="min-w-0">
                <b>Lançados sozinhos</b> nos últimos 30 dias: {lista.length}
                {lista.length > 0 && ` · ${formatCurrency(total)}`}
              </span>
              <ChevronDown className={`h-3.5 w-3.5 shrink-0 transition-transform ${aberto ? 'rotate-180' : ''}`} />
            </button>
          </CollapsibleTrigger>
          <span className="flex items-center gap-2 text-xs text-muted-foreground">
            Saídas de confiança alta até o limite de lote
            <Button size="sm" variant={ligado ? 'secondary' : 'outline'} className="h-7 text-xs"
              disabled={salvar.isPending}
              onClick={() => salvar.mutate({ key: 'finance_auto_approve', value: ligado ? 'off' : 'on' })}>
              {ligado ? 'Ligado — desligar' : 'Desligado — ligar'}
            </Button>
          </span>
        </div>
        <CollapsibleContent className="mt-2">
          {lista.length === 0 ? (
            <p className="text-sm text-muted-foreground">Nada foi lançado sem clique neste período.</p>
          ) : (
            <ul className="max-h-80 divide-y overflow-y-auto rounded-md border text-sm">
              {lista.map((l) => (
                <li key={l.id} className="flex min-w-0 items-center gap-2 p-2">
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-medium">{l.title}</span>
                    <span className="block truncate text-xs text-muted-foreground">
                      {l.suggested_date ? formatDate(l.suggested_date) : ''} · {l.suggested_category ?? '—'} · {l.decision_note ?? (l.automatica === 'regra' ? 'pela sua regra' : 'confiança alta')}
                    </span>
                  </span>
                  <span className="shrink-0 font-semibold tabular-nums">{formatCurrency(Number(l.suggested_amount ?? 0))}</span>
                  {(l.created_payable_id || l.created_receivable_id) && (
                    <Button size="sm" variant="ghost" className="h-7 shrink-0 gap-1 text-xs" disabled={desfazer.isPending}
                      title="Cancela o lançamento e devolve a linha para a fila, para decidir à mão"
                      onClick={() => desfazer.mutate({
                        tipo: l.created_payable_id ? 'payable' : 'receivable',
                        id: (l.created_payable_id ?? l.created_receivable_id)!,
                        motivo: 'Lançado sozinho — desfeito para revisão',
                      })}>
                      <Undo2 className="h-3.5 w-3.5" /> Desfazer
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </CollapsibleContent>
      </Collapsible>
    </Card>
  );
}

export function ExtratoPorConta({
  visaoInicial = 'revisar', onCriarRegra,
}: {
  visaoInicial?: VisaoDoExtrato;
  onCriarRegra?: (s: SementeDeRegra) => void;
}) {
  const { formatCurrency } = useI18n();
  const { data: conexoes = [] } = useBankConnections();
  const { data: conferencias = [] } = useConferenciasDeSaldo();
  const [conta, setConta] = useState<string>(TODAS);
  const [visao, setVisao] = useState<VisaoDoExtrato>(visaoInicial);
  const contaId = conta === TODAS ? null : conta;
  const contaAtual = conexoes.find((c) => c.id === contaId);
  // O Caixa é uma conta como as do banco, mas quem põe as linhas nele é você (ou o
  // assistente): não há sincronização, há lançamento e contagem.
  const ehCaixa = contaAtual?.provider === 'caixa';
  const [dialogo, setDialogo] = useState<'lancar' | 'contar' | 'anotar' | null>(null);

  // A situação da conta hoje: a última conferência de saldo dela.
  const ultima = useMemo(() => {
    if (!contaId) return null;
    return (conferencias as Array<{ bank_connection_id: string; fecha: boolean; diferenca: number; saldo_do_provedor?: number }>)
      .find((c) => c.bank_connection_id === contaId) ?? null;
  }, [conferencias, contaId]);

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Select value={conta} onValueChange={(v) => { setConta(v); if (v === TODAS && visao === 'saldo') setVisao('revisar'); }}>
          <SelectTrigger className="h-9 w-64 max-w-full" aria-label="Conta"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={TODAS}>Todas as contas</SelectItem>
            {conexoes.map((c) => <SelectItem key={c.id} value={c.id}>{c.label}</SelectItem>)}
          </SelectContent>
        </Select>
        {ultima && (
          ultima.fecha
            ? <Badge variant="secondary" className="text-xs">saldo confere{ultima.saldo_do_provedor != null ? ` · ${formatCurrency(Number(ultima.saldo_do_provedor))}` : ''}</Badge>
            : <Badge variant="outline" className="border-amber-500/50 text-xs text-amber-600">saldo difere {formatCurrency(Math.abs(Number(ultima.diferenca)))}</Badge>
        )}
        {ehCaixa && (
          <>
            <Button size="sm" className="h-8 gap-1 text-xs" onClick={() => setDialogo('lancar')}>
              <Banknote className="h-3.5 w-3.5" /> Lançar no Caixa
            </Button>
            <Button size="sm" variant="outline" className="h-8 gap-1 text-xs" onClick={() => setDialogo('contar')}>
              <Calculator className="h-3.5 w-3.5" /> Contei o dinheiro
            </Button>
          </>
        )}
        <div className="flex flex-wrap gap-1 sm:ml-auto" role="tablist" aria-label="Visão do extrato">
          {([
            ['revisar', 'Para revisar'],
            ['saldo', 'Extrato com saldo'],
            ['fora', 'Fora da fila'],
          ] as const).map(([v, r]) => (
            <Button key={v} role="tab" aria-selected={visao === v} size="sm" variant={visao === v ? 'default' : 'outline'} className="h-8 text-xs"
              disabled={v === 'saldo' && !contaId}
              title={v === 'saldo' && !contaId ? 'Escolha uma conta para ver o extrato com saldo' : undefined}
              onClick={() => setVisao(v)}>
              {r}
            </Button>
          ))}
        </div>
      </div>

      {visao === 'revisar' && (
        <>
          <div className="flex justify-end">
            <Button size="sm" variant="ghost" className="h-8 gap-1 text-xs" onClick={() => setDialogo('anotar')}
              title="Classificar agora um Pix ou boleto que o banco ainda vai trazer">
              <NotebookPen className="h-3.5 w-3.5" /> Anotar antes do banco
            </Button>
          </div>
          <AnotacoesAguardando />
          <LancadosSozinhos contaId={contaId} />
          <FinanceReviewInbox onCriarRegra={onCriarRegra} contaId={contaId} />
        </>
      )}
      {visao === 'saldo' && contaId && <ExtratoComSaldo conexaoId={contaId} nomeDaConta={contaAtual?.label ?? 'a conta'} />}
      {visao === 'fora' && <IgnoradasPanel contaId={contaId} />}

      {dialogo === 'lancar' && <LancarNoCaixaDialog onFechar={() => setDialogo(null)} />}
      {dialogo === 'contar' && <AjustarCaixaDialog onFechar={() => setDialogo(null)} />}
      {dialogo === 'anotar' && <AnotarTransacaoDialog onFechar={() => setDialogo(null)} />}
    </div>
  );
}
