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
import { useLancadosSozinhos, type LancadoSozinho } from '@/hooks/use-extrato-conta';
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

/** Recebimento baixado pelo boleto (24/11/2026): a conta casada com a linha do banco é a RECEBER — entrada, não saída. */
const ehRecebimentoBaixado = (l: LancadoSozinho) => l.automatica === 'boleto' && l.conta_baixada_tipo === 'receivable';

/** O que o sistema lançou sem clique, com o interruptor e o desfazer. */
function LancadosSozinhos({ contaId }: { contaId: string | null }) {
  const { formatCurrency, formatDate } = useI18n();
  // 24/11/2026 (revisão): `data = []` fazia a leitura que falhou (ou que ainda não voltou) virar "0" e "Nada foi
  // lançado sem clique" — justamente no bloco que mostra o que foi feito sem clique. Sem dado nenhum, o bloco diz que
  // não leu. A condição é "não há dado", não "deu erro": numa releitura que falha depois de uma boa, a lista boa
  // continua em mãos, com os Desfazer certos, e não pode ser trocada por um aviso.
  const { data, isError } = useLancadosSozinhos();
  const semLeitura = data === undefined;
  const ligado = useAppSetting('finance_auto_approve', 'off') === 'on';
  const salvar = useUpdateAppSetting();
  const desfazer = useDesfazerAprovacao();
  const [aberto, setAberto] = useState(false);
  // Desligar pede confirmação: um clique distraído mudava o comportamento do dia seguinte.
  const [confirmando, setConfirmando] = useState(false);
  const lista = useMemo(
    () => (data ?? []).filter((l) => !contaId || l.bank_transactions?.bank_connection_id === contaId),
    [data, contaId],
  );
  // 24/11/2026: o recebimento baixado pelo boleto é ENTRADA. O total do cabeçalho sempre foi "quanto saiu sem clique";
  // somar o crédito nele inflava o número. A entrada ganha contagem e valor à parte.
  const recebimentos = lista.filter(ehRecebimentoBaixado);
  const saidas = lista.filter((l) => !ehRecebimentoBaixado(l));
  const total = saidas.reduce((s, l) => s + Number(l.suggested_amount ?? 0), 0);
  const totalRecebido = recebimentos.reduce((s, l) => s + Number(l.suggested_amount ?? 0), 0);

  return (
    <Card className="p-3">
      <Collapsible open={aberto} onOpenChange={setAberto}>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CollapsibleTrigger asChild>
            <button type="button" className="flex min-w-0 items-center gap-2 text-left text-sm">
              <Bot className="h-4 w-4 shrink-0 text-primary" />
              <span className="min-w-0">
                {/* Sem leitura a lista está vazia, então os totais abaixo já não aparecem: só a contagem troca de texto. */}
                <b>Lançados sozinhos</b> nos últimos 30 dias: {semLeitura ? (isError ? 'não consegui ler — recarregue a página' : 'lendo…') : saidas.length}
                {saidas.length > 0 && ` · ${formatCurrency(total)}`}
                {recebimentos.length > 0 && ` · ${recebimentos.length} ${recebimentos.length === 1 ? 'recebimento baixado' : 'recebimentos baixados'} ${formatCurrency(totalRecebido)}`}
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
              mesmo com este interruptor desligado — menos nos casos acima. À parte disso, a conta que tem boleto
              conhecido é baixada quando o banco mostra o pagamento desse boleto (mesmo valor, mesmo banco, uma
              conta só): também aparece aqui, e Desfazer devolve a conta para "em aberto". O mesmo vale para o
              que você tem a receber: a conta a receber de NF-e com boleto é baixada quando o banco mostra o
              crédito do boleto no dia do vencimento, no mesmo valor. Aparece aqui como recebimento baixado,
              contado à parte das saídas, e Desfazer devolve a conta para "em aberto".
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
          {semLeitura ? (
            <p className="text-sm text-muted-foreground">
              {isError
                ? 'Não consegui ler os lançados sozinhos — recarregue a página. O que foi lançado ou baixado sem clique continua valendo.'
                : 'Lendo…'}
            </p>
          ) : lista.length === 0 ? (
            <p className="text-sm text-muted-foreground">Nada foi lançado sem clique neste período.</p>
          ) : (
            <ul className="max-h-80 divide-y overflow-y-auto rounded-md border text-sm">
              {lista.map((l) => {
                // 24/11/2026: a entrada não pode se confundir com as saídas da lista — a nota diz "Recebimento baixado…"
                // (inteira na dica, porque a linha corta) e o valor vai com "+" e na cor de entrada do Extrato com saldo.
                // 24/11/2026 (revisão): no celular a data na frente da nota comia a linha inteira e o cliente não
                // aparecia (a 360 px, "13/11/2026 · …"), e o título do recebimento é só "Receita: CREDITO DE BOLETO" —
                // o dono apertaria Desfazer sem ver de quem é a conta. Só no recebimento, a segunda linha pode ocupar
                // até DUAS linhas (a data continua: é ela que separa duas parcelas do mesmo cliente). Sem limite não
                // serve: um item tomava a lista inteira. A conta a pagar e os lançados continuam numa linha só.
                const recebimento = ehRecebimentoBaixado(l);
                return (
                <li key={l.id} className="flex min-w-0 items-center gap-2 p-2">
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-medium">{l.title}</span>
                    <span className={`${recebimento ? 'line-clamp-2 break-words' : 'block truncate'} text-xs text-muted-foreground`}
                      title={recebimento ? (l.decision_note ?? undefined) : undefined}>
                      {l.automatica === 'boleto'
                        ? <>{l.suggested_date ? formatDate(l.suggested_date) : ''} · {l.decision_note ?? (recebimento ? 'Recebimento baixado sozinho pelo boleto' : 'Baixada sozinha pelo boleto')}</>
                        : <>{l.suggested_date ? formatDate(l.suggested_date) : ''} · {l.suggested_category ?? '—'} · {l.decision_note ?? (l.automatica === 'regra' ? 'pela sua regra' : 'confiança alta')}</>}
                    </span>
                  </span>
                  <span className={`shrink-0 font-semibold tabular-nums${recebimento ? ' text-success' : ''}`}>
                    {recebimento && '+'}{formatCurrency(Number(l.suggested_amount ?? 0))}
                  </span>
                  {l.automatica === 'boleto' && l.conta_baixada_id && (
                    <Button size="sm" variant="ghost" className="h-7 shrink-0 gap-1 text-xs" disabled={desfazer.isPending}
                      title="Desfaz a baixa: a conta volta a ficar em aberto e a linha do banco volta para a fila, para você decidir"
                      onClick={() => desfazer.mutate({
                        // O lado da conta casada (24/11/2026): 'payable' fixo fazia o banco não achar a conta a receber.
                        tipo: l.conta_baixada_tipo ?? 'payable',
                        id: l.conta_baixada_id!,
                        motivo: recebimento ? 'Recebimento baixado pelo boleto — desfeito para revisão' : 'Baixada pelo boleto — desfeita para revisão',
                      })}>
                      <Undo2 className="h-3.5 w-3.5" /> Desfazer
                    </Button>
                  )}
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
                );
              })}
            </ul>
          )}
        </CollapsibleContent>
      </Collapsible>
    </Card>
  );
}

export function ExtratoPorConta({
  visaoInicial = 'revisar', visao: visaoControlada, contaId: contaControlada, onEscolherConta, onCriarRegra,
}: {
  visaoInicial?: VisaoDoExtrato;
  /**
   * Visão escolhida por fora (as abas da tela do Extrato, 26/09/2026). Com ela, o seletor
   * interno some: a tela já mostra as visões como abas, e dois seletores para a mesma coisa
   * seriam a duplicação que a reorganização veio desfazer.
   */
  visao?: VisaoDoExtrato;
  /** Conta escolhida por fora: trocar de aba não perde a conta das fichas. */
  contaId?: string | null;
  onEscolherConta?: (id: string | null) => void;
  onCriarRegra?: (s: SementeDeRegra) => void;
}) {
  const { data: conexoes = [] } = useBankConnections();
  const [contaInterna, setContaInterna] = useState<string | null>(null);
  const [visaoInterna, setVisaoInterna] = useState<VisaoDoExtrato>(visaoInicial);
  const controlada = visaoControlada !== undefined;
  const visao = visaoControlada ?? visaoInterna;
  const contaId = contaControlada !== undefined ? contaControlada : contaInterna;
  const setContaId = (id: string | null) => {
    if (onEscolherConta) onEscolherConta(id);
    if (contaControlada === undefined) setContaInterna(id);
  };
  const contaAtual = conexoes.find((c) => c.id === contaId);
  const [anotando, setAnotando] = useState(false);

  return (
    <div className="space-y-3">
      {/* As contas com o saldo de cada uma, sempre à vista. Clicar escolhe a conta; a ficha do
          Caixa tem "Lançar" e "Contei o dinheiro". */}
      <SaldosDasContas contaAtiva={contaId} onEscolher={setContaId} />

      {/* Com a visão escolhida por fora, as abas da tela já dizem para que serve cada uma:
          fica só o "Anotar antes do banco", que é da fila. */}
      {(!controlada || visao === 'revisar') && (
        <div className="flex flex-wrap items-center gap-2">
          {!controlada && (
            <>
              <div className="flex flex-wrap gap-1" role="tablist" aria-label="Visão do extrato">
                {([
                  ['revisar', 'Para revisar'],
                  ['saldo', 'Extrato com saldo'],
                  ['fora', 'Fora da fila'],
                ] as const).map(([v, r]) => (
                  <Button key={v} role="tab" aria-selected={visao === v} size="sm" variant={visao === v ? 'default' : 'outline'} className="h-8 text-xs"
                    onClick={() => setVisaoInterna(v)}>
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
            </>
          )}
          {visao === 'revisar' && (
            <Button size="sm" variant="ghost" className="h-8 gap-1 text-xs sm:ml-auto" onClick={() => setAnotando(true)}>
              <NotebookPen className="h-3.5 w-3.5" /> Anotar antes do banco
            </Button>
          )}
        </div>
      )}

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
