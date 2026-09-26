// O Extrato, conta por conta (Fase 3.2 do Financeiro Confiável).
//
// No desenho do Xero e do QuickBooks, cada conta tem a sua área: o que falta decidir, o
// extrato com saldo e o que saiu da fila. Aqui isso vive DENTRO do Extrato — o destino do
// menu continua o mesmo (decisão do dono de 23/09: menu é destino, aba é recorte), e
// "Fora da fila", que era aba solta, passa a ser uma das visões da conta.
//
// 26/09/2026: a conta se escolhe pelas FICHAS de saldo (SaldosDasContas), não mais por um
// seletor "Todas as contas". O dono não achou o Caixa nem o "Contei o dinheiro", que só
// apareciam depois de trocar o seletor.
import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { useI18n } from '@/i18n';
import { useBankConnections } from '@/hooks/use-bank-connections';
import { useLancadosSozinhos } from '@/hooks/use-extrato-conta';
import { useAppSetting, useUpdateAppSetting } from '@/hooks/use-app-settings';
import { useDesfazerAprovacao } from '@/hooks/use-lancamentos';
import { FinanceReviewInbox, type SementeDeRegra } from '@/components/FinanceReviewInbox';
import { IgnoradasPanel } from '@/components/IgnoradasPanel';
import { ExtratoComSaldo } from '@/components/ExtratoComSaldo';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Bot, ChevronDown, Undo2, NotebookPen } from 'lucide-react';
import { AnotacoesAguardando, AnotarTransacaoDialog } from '@/components/CaixaDialogs';
import { SaldosDasContas } from '@/components/SaldosDasContas';
import { Ajuda } from '@/components/Ajuda';

export type VisaoDoExtrato = 'revisar' | 'saldo' | 'fora';

/** O que o sistema lançou sem clique, com o interruptor e o desfazer. */
function LancadosSozinhos({ contaId }: { contaId: string | null }) {
  const { formatCurrency, formatDate } = useI18n();
  const { data = [] } = useLancadosSozinhos();
  const ligado = useAppSetting('finance_auto_approve', 'off') === 'on';
  const salvar = useUpdateAppSetting();
  const desfazer = useDesfazerAprovacao();
  const [aberto, setAberto] = useState(false);
  // Desligar pede confirmação: um clique distraído mudava o comportamento do dia seguinte.
  const [confirmando, setConfirmando] = useState(false);
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
          <span className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            Saídas de confiança alta até o limite de lote
            <Ajuda rotulo="Como funciona o lançar sozinho">
              Nas análises das 6h e das 15h, saídas com confiança 90 ou mais, abaixo do limite de lote e com
              categoria de verdade são lançadas sem clique. Nunca vão sozinhas: compra no débito sem loja, o
              que fica fora do resultado (fatura, empréstimo, retirada), fornecedor reconhecido só pelo nome
              cortado pelo banco, linha com OS, OC ou vínculo sugerido (é pergunta sua) e o que veio de regra
              marcada "só sugerir". Tudo aparece aqui, com Desfazer. As regras marcadas "Lançar sozinha" valem
              mesmo com este interruptor desligado — menos nos casos acima.
            </Ajuda>
            {confirmando ? (
              <>
                <span className="text-foreground">Desligar?</span>
                <Button size="sm" variant="destructive" className="h-7 text-xs" disabled={salvar.isPending}
                  onClick={() => { salvar.mutate({ key: 'finance_auto_approve', value: 'off' }); setConfirmando(false); }}>
                  Sim, desligar
                </Button>
                <Button size="sm" variant="outline" className="h-7 text-xs" onClick={() => setConfirmando(false)}>Não</Button>
              </>
            ) : (
              <Button size="sm" variant={ligado ? 'secondary' : 'outline'} className="h-7 text-xs"
                disabled={salvar.isPending}
                onClick={() => (ligado ? setConfirmando(true) : salvar.mutate({ key: 'finance_auto_approve', value: 'on' }))}>
                {ligado ? 'Ligado — desligar' : 'Desligado — ligar'}
              </Button>
            )}
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
  const { data: conexoes = [] } = useBankConnections();
  const [contaId, setContaId] = useState<string | null>(null);
  const [visao, setVisao] = useState<VisaoDoExtrato>(visaoInicial);
  const contaAtual = conexoes.find((c) => c.id === contaId);
  const [anotando, setAnotando] = useState(false);

  return (
    <div className="space-y-3">
      {/* As contas com o saldo de cada uma, sempre à vista. Clicar escolhe a conta; a ficha do
          Caixa tem "Lançar" e "Contei o dinheiro". */}
      <SaldosDasContas contaAtiva={contaId} onEscolher={setContaId} />

      <div className="flex flex-wrap items-center gap-2">
        <div className="flex flex-wrap gap-1" role="tablist" aria-label="Visão do extrato">
          {([
            ['revisar', 'Para revisar'],
            ['saldo', 'Extrato com saldo'],
            ['fora', 'Fora da fila'],
          ] as const).map(([v, r]) => (
            <Button key={v} role="tab" aria-selected={visao === v} size="sm" variant={visao === v ? 'default' : 'outline'} className="h-8 text-xs"
              onClick={() => setVisao(v)}>
              {r}
            </Button>
          ))}
        </div>
        <Ajuda rotulo="O que cada visão mostra">
          <b>Para revisar</b>: o que o banco trouxe e ainda precisa de uma decisão sua — aprovar só
          registra, nenhum pagamento é feito. <b>Extrato com saldo</b>: o mês de uma conta como no app do
          banco, com o saldo linha a linha e o que cada movimento virou. <b>Fora da fila</b>: o que saiu
          da fila sem virar lançamento (duplicata, fatura, transferência entre contas suas), com o
          motivo e o botão Devolver.
        </Ajuda>
        {visao === 'revisar' && (
          <Button size="sm" variant="ghost" className="h-8 gap-1 text-xs sm:ml-auto" onClick={() => setAnotando(true)}>
            <NotebookPen className="h-3.5 w-3.5" /> Anotar antes do banco
          </Button>
        )}
      </div>

      {visao === 'revisar' && (
        <>
          <p className="text-xs text-muted-foreground">
            Fez um Pix ou pagou no débito? Em <b>Anotar antes do banco</b> (ou pelo WhatsApp) você diz o que
            foi; quando a linha chegar do banco, ela entra já classificada.
          </p>
          <AnotacoesAguardando />
          <LancadosSozinhos contaId={contaId} />
          <FinanceReviewInbox onCriarRegra={onCriarRegra} contaId={contaId} />
        </>
      )}
      {visao === 'saldo' && contaId && <ExtratoComSaldo conexaoId={contaId} nomeDaConta={contaAtual?.label ?? 'a conta'} />}
      {/* Escrito, não botão apagado: botão apagado não mostra dica, e o motivo ficava invisível. */}
      {visao === 'saldo' && !contaId && (
        <Card className="p-4 text-sm text-muted-foreground">
          Escolha uma conta nas fichas acima para ver o extrato dela com o saldo linha a linha.
        </Card>
      )}
      {visao === 'fora' && <IgnoradasPanel contaId={contaId} />}

      {anotando && <AnotarTransacaoDialog onFechar={() => setAnotando(false)} />}
    </div>
  );
}
