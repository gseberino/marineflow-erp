// Caixa de entrada financeira — onde o gestor decide o que o sistema propôs.
//
// O problema que esta tela resolve: passaram R$ 926 mil em saídas pela conta no último ano
// e existem 5 contas a pagar registradas. A despesa não foi lançada porque lançar 1.500
// linhas à mão é trabalho que ninguém faz. Aqui o sistema chega com tudo preenchido e o
// gestor só confirma — o esforço vira leitura, não digitação.
//
// Duas faixas, conforme a decisão do usuário: até R$ 500 aprova em bloco (é onde está o
// volume e o risco é baixo); acima disso, uma a uma, porque valor grande merece o olho.
//
// PRINCÍPIO DE INTERFACE (correção de 29/07): toda ação que o gestor precisa tomar fica NA
// LINHA, visível. A versão anterior escondia a troca de categoria dentro do "por que o
// sistema propôs isto" — ação atrás de explicação é ação que não existe.
import { useMemo, useState, type ReactNode } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import {
  Tooltip, TooltipContent, TooltipProvider, TooltipTrigger,
} from '@/components/ui/tooltip';
import { useI18n } from '@/i18n';
import { CategoriaDespesaSelect } from '@/components/CategoriaDespesaSelect';
import { PayeeFormDialog } from '@/components/PayeeFormDialog';
import {
  usePayees, useServiceOrdersVinculaveis, ROTULO_TIPO,
  CATEGORIAS_COM_FAVORECIDO, CATEGORIAS_COM_OS,
} from '@/hooks/use-payees';
import {
  useFinanceReviewQueue, useGerarPropostas, useAprovarPropostas, useRecusarPropostas,
  useMarcarDuplicata, useCriarCategoriaDespesa, useReaplicarRegras,
  LIMITE_LOTE, type PropostaFinanceira, type Correcao,
} from '@/hooks/use-finance-review';
import {
  Sparkles, Check, X, ChevronDown, ArrowLeftRight, TrendingDown, Info, RefreshCw,
  CopyX, Wand2, CreditCard, Landmark, AlertTriangle, Users, List, Layers,
} from 'lucide-react';
import {
  agruparPorFavorecido, resumoDoAgrupamento, SEM_CATEGORIA,
  type GrupoDeFavorecido,
} from '@/lib/finance-inbox-grouping';

function corDaConfianca(c: number): string {
  if (c >= 85) return 'bg-success/10 text-success border-success/30';
  if (c >= 60) return 'bg-warning/10 text-warning border-warning/30';
  return 'bg-muted text-muted-foreground';
}

function rotuloDaConfianca(c: number): string {
  if (c >= 85) return 'Alta';
  if (c >= 60) return 'Média';
  return 'Baixa';
}

/**
 * Tudo que o banco informou sobre a transação, em um lugar só.
 *
 * Existe para eliminar a ida ao internet banking: quem decide precisa saber para quem o
 * dinheiro foi, de qual conta, por qual meio e com que mensagem. Campo ausente
 * simplesmente não aparece — linha com "—" ocupa espaço e não informa nada.
 */
function IdentificacaoDaTransacao({ tx }: { tx: PropostaFinanceira['bank_transactions'] }) {
  if (!tx) return null;

  const conta = [tx.counterparty_bank && `Banco ${tx.counterparty_bank}`,
    tx.counterparty_branch && `Ag. ${tx.counterparty_branch}`,
    tx.counterparty_account && `C/C ${tx.counterparty_account}`].filter(Boolean).join(' · ');

  const linhas: Array<[string, string | null]> = [
    ['Favorecido', tx.counterparty_name],
    ['CNPJ/CPF', formatarDocumento(tx.counterparty_document)],
    ['Conta', conta || null],
    ['Meio', [tx.payment_method, tx.installment_label && `parcela ${tx.installment_label}`].filter(Boolean).join(' · ') || null],
    ['Mensagem', tx.payment_reason],
    ['Estabelecimento', tx.merchant_name],
    ['Identificador Pix', tx.pix_end_to_end_id],
    ['Histórico do banco', tx.description],
    // O id do provedor é o que garante que a mesma transação não entre duas vezes: existe
    // índice único sobre ele. Mostrar não é detalhe técnico — é o que permite conferir
    // contra o extrato do banco quando dois lançamentos parecem iguais.
    ['Identificação no banco', tx.bank_ref_id],
  ].filter(([, v]) => !!v) as Array<[string, string]>;

  if (linhas.length === 0) return null;

  return (
    <dl className="grid grid-cols-1 gap-x-4 gap-y-1 rounded-md border p-2 text-xs sm:grid-cols-2">
      {linhas.map(([rotulo, valor]) => (
        <div key={rotulo} className="flex min-w-0 gap-2">
          <dt className="shrink-0 text-muted-foreground">{rotulo}</dt>
          <dd className="min-w-0 flex-1 truncate font-medium" title={valor!}>{valor}</dd>
        </div>
      ))}
    </dl>
  );
}


/**
 * O vínculo que a categoria pede — e só ele.
 *
 * A categoria diz a que mundo a despesa pertence, então é ela que decide a próxima
 * pergunta: pró-labore pertence a uma PESSOA, peça pertence a um SERVIÇO. Mostrar os dois
 * campos em toda linha viraria ruído em quase todas; não mostrar nenhum deixa R$ 36 mil de
 * pró-labore sem dono e R$ 37 mil de peça sem serviço.
 */
function VinculoDaCategoria({
  categoria, favorecidoId, osId, onMudar, ocupado,
}: {
  categoria: string;
  favorecidoId: string | null;
  osId: string | null;
  onMudar: (v: { payeeId?: string | null; serviceOrderId?: string | null }) => void;
  ocupado: boolean;
}) {
  const pedeFavorecido = CATEGORIAS_COM_FAVORECIDO.includes(categoria);
  const pedeOS = CATEGORIAS_COM_OS.includes(categoria);

  const { data: favorecidos = [] } = usePayees();
  const { data: ordens = [] } = useServiceOrdersVinculaveis();
  const [cadastrando, setCadastrando] = useState(false);

  if (!pedeFavorecido && !pedeOS) return null;

  return (
    <div className="mt-2 flex max-w-lg flex-wrap items-center gap-2">
      {pedeFavorecido && (
        <>
          <Select
            value={favorecidoId ?? ''}
            onValueChange={(v) => (v === NOVO_FAVORECIDO ? setCadastrando(true) : onMudar({ payeeId: v }))}
            disabled={ocupado}
          >
            <SelectTrigger className="h-8 max-w-[15rem] text-xs">
              <SelectValue placeholder="Quem recebeu?" />
            </SelectTrigger>
            <SelectContent>
              {favorecidos.map((f) => (
                <SelectItem key={f.id} value={f.id}>
                  {f.name} · {ROTULO_TIPO[f.kind]}
                </SelectItem>
              ))}
              <SelectItem value={NOVO_FAVORECIDO} className="font-medium text-primary">
                + Cadastrar favorecido…
              </SelectItem>
            </SelectContent>
          </Select>
          <PayeeFormDialog
            aberto={cadastrando}
            onFechar={() => setCadastrando(false)}
            categoriaSugerida={categoria}
            onCriado={(id) => onMudar({ payeeId: id })}
          />
        </>
      )}

      {pedeOS && (
        <Select
          value={osId ?? ''}
          onValueChange={(v) => onMudar({ serviceOrderId: v === SEM_OS ? null : v })}
          disabled={ocupado}
        >
          <SelectTrigger className="h-8 max-w-[17rem] text-xs">
            <SelectValue placeholder="Comprado para qual OS?" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={SEM_OS}>Nenhuma — despesa geral</SelectItem>
            {ordens.map((o) => (
              <SelectItem key={o.id} value={o.id}>
                {o.service_order_number} · {o.clients?.name ?? 'sem cliente'}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )}
    </div>
  );
}

const NOVO_FAVORECIDO = '__novo_favorecido__';
/** Radix não aceita SelectItem com valor vazio; "nenhuma" precisa de um valor próprio. */
const SEM_OS = '__sem_os__';

/** CNPJ e CPF em máscara: 14 dígitos crus são ilegíveis para conferir de olho. */
function formatarDocumento(doc: string | null): string | null {
  if (!doc) return null;
  if (doc.length === 14) return doc.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, '$1.$2.$3/$4-$5');
  if (doc.length === 11) return doc.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, '$1.$2.$3-$4');
  return doc;
}

interface LinhaProps {
  p: PropostaFinanceira;
  selecionada: boolean;
  onSelecionar: (marcada: boolean) => void;
  correcao: Correcao | undefined;
  onCorrigir: (c: Correcao) => void;
  onAprovar: () => void;
  onRecusar: () => void;
  onDuplicata: () => void;
  onCriarRegra: () => void;
  ocupado: boolean;
  /** Em lote a seleção manda; individualmente cada linha tem seus botões. */
  modoLote: boolean;
}

function LinhaProposta({
  p, selecionada, onSelecionar, correcao, onCorrigir,
  onAprovar, onRecusar, onDuplicata, onCriarRegra, ocupado, modoLote,
}: LinhaProps) {
  const { formatCurrency, formatDate } = useI18n();
  const [aberta, setAberta] = useState(false);

  const transferencia = p.kind === 'internal_transfer';
  const categoria = correcao?.category ?? p.suggested_category ?? '';
  const porRegra = !!p.applied_rule_id;
  // "3/10" → 10. O total é o que interessa aqui; qual parcela chegou primeiro é detalhe
  // da fatura, não da compra.
  const parcelas = Number(p.bank_transactions?.installment_label?.split('/')[1]) || null;

  return (
    <Card className="p-3">
      <div className="flex items-start gap-3">
        {modoLote && (
          <Checkbox
            checked={selecionada}
            onCheckedChange={(v) => onSelecionar(v === true)}
            className="mt-1 shrink-0"
            aria-label={`Selecionar ${p.title}`}
          />
        )}

        <div className="min-w-0 flex-1">
          {/* min-w-0 + truncate: histórico de banco é longo e sem isto empurra a linha
              para fora da tela. Nunca deve haver rolagem lateral. */}
          <div className="flex flex-wrap items-center gap-2">
            {transferencia
              ? <ArrowLeftRight className="h-4 w-4 shrink-0 text-primary" />
              : <TrendingDown className="h-4 w-4 shrink-0 text-destructive" />}
            <span className="truncate font-medium">{p.title}</span>
            {porRegra
              ? <Badge variant="secondary" className="shrink-0 text-xs">Pela sua regra</Badge>
              : (
                <Badge variant="outline" className={`shrink-0 text-xs ${corDaConfianca(p.confidence)}`}>
                  {rotuloDaConfianca(p.confidence)} · {p.confidence}%
                </Badge>
              )}
          </div>

          <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
            <span>{p.suggested_date ? formatDate(p.suggested_date) : '—'}</span>
            <span className="font-semibold text-foreground">
              {formatCurrency(Number(p.suggested_amount ?? 0))}
            </span>
            {/* De onde veio muda onde se confere: gasto de cartão se acha na fatura, gasto
                de conta no extrato bancário. Sem isso o gestor procura no lugar errado. */}
            {p.bank_transactions?.source_type && (
              <Badge variant="outline" className="gap-1 text-xs">
                {p.bank_transactions.source_type === 'credit_card'
                  ? <><CreditCard className="h-3 w-3" />Fatura de cartão</>
                  : <><Landmark className="h-3 w-3" />Conta corrente</>}
              </Badge>
            )}
            {/* Uma compra, não N despesas: o valor mostrado é o da COMPRA, e o rótulo
                avisa que ela chega em parcelas para quem for conferir na fatura. */}
            {parcelas && (
              <Badge variant="outline" className="gap-1 text-xs">
                <Layers className="h-3 w-3" />
                Compra em {parcelas}x
              </Badge>
            )}
            {transferencia && (
              <Badge variant="secondary" className="text-xs">Não entra no resultado</Badge>
            )}
          </div>

          {/* A categoria é a decisão principal da tela: fica editável na linha, sempre. */}
          {!transferencia && (
            <div className="mt-2 max-w-sm">
              <CategoriaDespesaSelect
                valor={categoria}
                onMudar={(v) => onCorrigir({ ...correcao, category: v })}
                grupoSugerido={p.dre_group}
              />
            </div>
          )}

          {!transferencia && (
            <VinculoDaCategoria
              categoria={categoria}
              favorecidoId={correcao?.payeeId ?? p.suggested_payee_id ?? null}
              osId={correcao?.serviceOrderId ?? p.suggested_service_order_id ?? null}
              onMudar={(v) => onCorrigir({ ...correcao, ...v })}
              ocupado={ocupado}
            />
          )}

          <Collapsible open={aberta} onOpenChange={setAberta}>
            <CollapsibleTrigger asChild>
              <button type="button" className="mt-1 inline-flex items-center gap-1 text-xs text-primary hover:underline">
                <Info className="h-3 w-3" />
                Por que o sistema propôs isto
                <ChevronDown className={`h-3 w-3 transition-transform ${aberta ? 'rotate-180' : ''}`} />
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent className="mt-2 space-y-2">
              <p className="rounded-md bg-muted/50 p-2 text-xs text-muted-foreground">
                {p.reasoning || 'Sem justificativa registrada.'}
              </p>
              <IdentificacaoDaTransacao tx={p.bank_transactions} />
            </CollapsibleContent>
          </Collapsible>
        </div>

        <TooltipProvider>
          <div className="flex shrink-0 flex-wrap justify-end gap-1">
            {/* aria-label além do tooltip: botão só de ícone precisa de nome para leitor
                de tela, e o texto do tooltip não conta — ele só existe no hover. */}
            {!modoLote && (
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button size="sm" variant="outline" disabled={ocupado} onClick={onAprovar}
                    aria-label="Aprovar e lançar">
                    <Check className="h-4 w-4" />
                  </Button>
                </TooltipTrigger>
                <TooltipContent>Aprovar e lançar</TooltipContent>
              </Tooltip>
            )}

            {!transferencia && (
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button size="sm" variant="ghost" disabled={ocupado} onClick={onCriarRegra}
                    aria-label="Criar uma regra a partir desta linha">
                    <Wand2 className="h-4 w-4" />
                  </Button>
                </TooltipTrigger>
                <TooltipContent>Criar uma regra a partir desta linha</TooltipContent>
              </Tooltip>
            )}

            <Tooltip>
              <TooltipTrigger asChild>
                <Button size="sm" variant="ghost" disabled={ocupado} onClick={onDuplicata}
                  aria-label="É duplicata — tirar da fila">
                  <CopyX className="h-4 w-4" />
                </Button>
              </TooltipTrigger>
              <TooltipContent>É duplicata — tirar da fila</TooltipContent>
            </Tooltip>

            <Tooltip>
              <TooltipTrigger asChild>
                <Button size="sm" variant="ghost" disabled={ocupado} onClick={onRecusar}
                  aria-label="Descartar esta proposta">
                  <X className="h-4 w-4" />
                </Button>
              </TooltipTrigger>
              <TooltipContent>Descartar esta proposta</TooltipContent>
            </Tooltip>
          </div>
        </TooltipProvider>
      </div>
    </Card>
  );
}

/**
 * Um favorecido e tudo que se deve a ele, como uma decisão só.
 *
 * A escolha de desenho que importa: a CATEGORIA vale para o grupo inteiro, mas o botão de
 * aprovar só alcança o que está abaixo do limite de lote. Classificar é barato e
 * reversível; aprovar cria lançamento. Assim as 34 compras no mesmo lugar viram uma
 * pergunta, e a saída de R$ 4 mil do mesmo favorecido continua pedindo olho — só que já
 * chega classificada.
 */
function CartaoDoFavorecido({
  grupo, categoria, favorecidoId, osId, onMudar, onAprovarLote, onCriarRegra, ocupado, children,
}: {
  grupo: GrupoDeFavorecido;
  categoria: string;
  favorecidoId: string | null;
  osId: string | null;
  onMudar: (c: Correcao) => void;
  onAprovarLote: () => void;
  onCriarRegra: () => void;
  ocupado: boolean;
  children: ReactNode;
}) {
  const { formatCurrency, formatDate } = useI18n();
  const [aberto, setAberto] = useState(false);

  const podeAprovar = grupo.emLote.length > 0 && !!categoria && categoria !== SEM_CATEGORIA;

  return (
    <Card className="p-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <Users className="h-4 w-4 shrink-0 text-primary" />
            <span className="truncate font-medium">{grupo.rotulo}</span>
            <Badge variant="secondary" className="shrink-0 text-xs">
              {grupo.propostas.length === 1 ? '1 proposta' : `${grupo.propostas.length} propostas`}
            </Badge>
            {grupo.semCategoria && (
              <Badge variant="outline" className="shrink-0 border-amber-500/50 text-xs text-amber-600">
                sem categoria
              </Badge>
            )}
            {/* Duas categorias no mesmo favorecido é o sistema em dúvida, não variedade
                legítima — e é exatamente onde uma escolha sua vale mais. */}
            {grupo.categorias.length > 1 && (
              <Badge variant="outline" className="shrink-0 text-xs">
                {grupo.categorias.length} categorias diferentes
              </Badge>
            )}
          </div>

          <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
            <span className="font-semibold text-foreground">{formatCurrency(grupo.total)}</span>
            {grupo.primeiraData && grupo.ultimaData && (
              <span>
                {grupo.primeiraData === grupo.ultimaData
                  ? formatDate(grupo.primeiraData)
                  : `${formatDate(grupo.primeiraData)} a ${formatDate(grupo.ultimaData)}`}
              </span>
            )}
            {grupo.individuais.length > 0 && (
              <span className="text-amber-600">
                {grupo.individuais.length} exige(m) revisão individual
              </span>
            )}
          </div>

          <div className="mt-2 max-w-sm">
            <CategoriaDespesaSelect
              valor={categoria}
              onMudar={(v) => onMudar({ category: v })}
              grupoSugerido={grupo.propostas[0]?.dre_group ?? null}
            />
          </div>

          <VinculoDaCategoria
            categoria={categoria}
            favorecidoId={favorecidoId}
            osId={osId}
            onMudar={(v) => onMudar(v)}
            ocupado={ocupado}
          />
        </div>

        <div className="flex shrink-0 flex-col items-end gap-1">
          <Button
            size="sm"
            disabled={ocupado || !podeAprovar}
            onClick={onAprovarLote}
            title={
              grupo.emLote.length === 0
                ? 'Todas deste favorecido passam do limite de lote — aprove uma a uma abaixo'
                : !categoria || categoria === SEM_CATEGORIA
                  ? 'Escolha a categoria antes de aprovar'
                  : undefined
            }
          >
            <Check className="mr-2 h-4 w-4" />
            {grupo.emLote.length > 0
              ? `Aprovar ${grupo.emLote.length} · ${formatCurrency(grupo.totalEmLote)}`
              : 'Nada em lote aqui'}
          </Button>
          <Button size="sm" variant="ghost" disabled={ocupado} onClick={onCriarRegra}>
            <Wand2 className="mr-2 h-4 w-4" />
            Virar regra
          </Button>
        </div>
      </div>

      <Collapsible open={aberto} onOpenChange={setAberto}>
        <CollapsibleTrigger asChild>
          <button type="button" className="mt-2 inline-flex items-center gap-1 text-xs text-primary hover:underline">
            <Info className="h-3 w-3" />
            {aberto ? 'Esconder' : `Ver as ${grupo.propostas.length} linhas`}
            <ChevronDown className={`h-3 w-3 transition-transform ${aberto ? 'rotate-180' : ''}`} />
          </button>
        </CollapsibleTrigger>
        <CollapsibleContent className="mt-2 space-y-2">{children}</CollapsibleContent>
      </Collapsible>
    </Card>
  );
}

export interface SementeDeRegra {
  match_type: 'counterparty' | 'supplier';
  match_value: string;
  set_category: string | null;
}

export function FinanceReviewInbox({
  onCriarRegra,
}: {
  /** A tela que hospeda abre o editor de regras já preenchido com esta linha. */
  onCriarRegra?: (semente: SementeDeRegra) => void;
} = {}) {
  const { formatCurrency } = useI18n();
  const { data: propostas = [], isLoading, error: erroDaFila } = useFinanceReviewQueue();

  const gerar = useGerarPropostas();
  const aprovar = useAprovarPropostas();
  const recusar = useRecusarPropostas();
  const duplicata = useMarcarDuplicata();
  const reaplicar = useReaplicarRegras();
  const ocupado = gerar.isPending || aprovar.isPending || recusar.isPending
    || duplicata.isPending || reaplicar.isPending;

  const [selecionadas, setSelecionadas] = useState<Set<string>>(new Set());
  const [correcoes, setCorrecoes] = useState<Record<string, Correcao>>({});
  // Trabalhar cartão e conta separados é mais rápido: a fatura tem muitos gastos pequenos
  // de estabelecimento, a conta tem poucos gastos grandes de fornecedor. Misturar os dois
  // obriga a trocar de raciocínio a cada linha.
  const [origem, setOrigem] = useState<'todas' | 'bank' | 'credit_card'>('todas');

  /**
   * Agrupado por favorecido só quando há volume que justifique.
   *
   * Com meia dúzia de propostas o agrupamento só acrescenta um clique para abrir cada
   * grupo; com mil, ele é a diferença entre 253 decisões e 558. O limiar deixa a tela do
   * dia a dia como sempre foi e liga o modo de mutirão sozinho, quando ele passa a valer.
   */
  const [modo, setModo] = useState<'favorecido' | 'lista' | null>(null);
  const agrupar = modo === null ? propostas.length >= 20 : modo === 'favorecido';

  const porOrigem = useMemo(
    () => (origem === 'todas'
      ? propostas
      : propostas.filter((p) => p.bank_transactions?.source_type === origem)),
    [propostas, origem],
  );

  const contagem = useMemo(() => ({
    todas: propostas.length,
    bank: propostas.filter((p) => p.bank_transactions?.source_type === 'bank').length,
    credit_card: propostas.filter((p) => p.bank_transactions?.source_type === 'credit_card').length,
  }), [propostas]);

  const { lote, individuais, totalValor } = useMemo(() => {
    const lote: PropostaFinanceira[] = [];
    const individuais: PropostaFinanceira[] = [];
    let totalValor = 0;
    for (const p of porOrigem) {
      totalValor += Number(p.suggested_amount ?? 0);
      // Transferência entre contas vai sempre para a revisão individual: confirmar que
      // dois lançamentos são o mesmo dinheiro é decisão de fato, não volume.
      if (p.kind !== 'internal_transfer' && Number(p.suggested_amount ?? 0) < LIMITE_LOTE) lote.push(p);
      else individuais.push(p);
    }
    return { lote, individuais, totalValor };
  }, [porOrigem]);

  const marcar = (id: string, marcada: boolean) => {
    setSelecionadas((s) => {
      const n = new Set(s);
      if (marcada) n.add(id); else n.delete(id);
      return n;
    });
  };

  const marcarTodasDoLote = (marcar: boolean) => {
    setSelecionadas(marcar ? new Set(lote.map((p) => p.id)) : new Set());
  };

  const corrigir = (id: string, c: Correcao) => setCorrecoes((m) => ({ ...m, [id]: c }));

  const aprovarSelecionadas = () => {
    const ids = [...selecionadas];
    if (ids.length === 0) return;
    const overrides: Record<string, Correcao> = {};
    for (const id of ids) if (correcoes[id]) overrides[id] = correcoes[id];
    aprovar.mutate({ ids, overrides }, { onSuccess: () => setSelecionadas(new Set()) });
  };

  // Calculado nos dois modos: é uma passada só na lista, e o botão precisa saber quantos
  // favorecidos existem ANTES de alguém trocar de modo — senão ele oferece "Por favorecido
  // (0)" justamente quando o agrupamento seria útil.
  const grupos = useMemo(() => agruparPorFavorecido(porOrigem, LIMITE_LOTE), [porOrigem]);
  const resumo = useMemo(() => resumoDoAgrupamento(grupos), [grupos]);

  /**
   * A categoria que vale para o grupo.
   *
   * Sai da correção já feita; se não houve, só assume a sugestão do sistema quando ela é a
   * MESMA em todas as linhas. Grupo em que o sistema hesitou entre duas categorias começa
   * em branco de propósito: preencher com uma delas esconderia a hesitação, e o botão de
   * aprovar aplicaria a escolha do sistema como se fosse a sua.
   */
  const estadoDoGrupo = (g: GrupoDeFavorecido): Correcao => {
    const corrigida = g.propostas.map((p) => correcoes[p.id]).find((c) => c?.category);
    const unica = g.categorias.length === 1 ? g.categorias[0] : '';
    return {
      category: corrigida?.category ?? (unica === SEM_CATEGORIA ? '' : unica),
      payeeId: g.propostas.map((p) => correcoes[p.id]?.payeeId ?? p.suggested_payee_id).find(Boolean) ?? null,
      serviceOrderId: g.propostas.map((p) => correcoes[p.id]?.serviceOrderId ?? p.suggested_service_order_id).find(Boolean) ?? null,
    };
  };

  /** Uma escolha no cabeçalho vira correção em cada linha — inclusive nas grandes. */
  const corrigirGrupo = (g: GrupoDeFavorecido, c: Correcao) => {
    setCorrecoes((m) => {
      const n = { ...m };
      for (const p of g.propostas) n[p.id] = { ...n[p.id], ...c };
      return n;
    });
  };

  const aprovarGrupo = (g: GrupoDeFavorecido) => {
    const ids = g.emLote.map((p) => p.id);
    if (ids.length === 0) return;
    const overrides: Record<string, Correcao> = {};
    for (const id of ids) if (correcoes[id]) overrides[id] = correcoes[id];
    aprovar.mutate({ ids, overrides });
  };

  const criarRegraDoGrupo = (g: GrupoDeFavorecido) => {
    onCriarRegra?.({
      match_type: g.supplierId ? 'supplier' : 'counterparty',
      match_value: g.supplierId ?? g.rotulo,
      set_category: estadoDoGrupo(g).category || null,
    });
  };

  const criarRegraDaLinha = (p: PropostaFinanceira) => {
    onCriarRegra?.({
      match_type: p.suggested_supplier_id ? 'supplier' : 'counterparty',
      match_value: p.suggested_supplier_id ?? (p.suggested_description ?? p.title),
      set_category: correcoes[p.id]?.category ?? p.suggested_category,
    });
  };

  const valorSelecionado = useMemo(
    () => lote.filter((p) => selecionadas.has(p.id)).reduce((s, p) => s + Number(p.suggested_amount ?? 0), 0),
    [lote, selecionadas],
  );

  const propsComuns = (p: PropostaFinanceira) => ({
    p,
    correcao: correcoes[p.id],
    onCorrigir: (c: Correcao) => corrigir(p.id, c),
    onAprovar: () => aprovar.mutate({ ids: [p.id], overrides: correcoes[p.id] ? { [p.id]: correcoes[p.id] } : {} }),
    onRecusar: () => recusar.mutate({ ids: [p.id] }),
    onDuplicata: () => duplicata.mutate({ propostaId: p.id, bankTransactionId: p.bank_transaction_id }),
    onCriarRegra: () => criarRegraDaLinha(p),
    ocupado,
  });

  if (isLoading) {
    return <div className="space-y-2">{[...Array(4)].map((_, i) => <Skeleton key={i} className="h-20 rounded-xl" />)}</div>;
  }

  // Consulta que falha não pode se passar por fila vazia. Era exatamente o que acontecia:
  // o join da identificação quebrou, a lista voltou vazia e a tela anunciou "nenhuma
  // proposta pendente" enquanto 1.178 esperavam decisão — com o contador do menu, que não
  // usa join, marcando 99+ ao lado. Erro invisível é pior que erro: some o problema E some
  // o trabalho.
  if (erroDaFila) {
    return (
      <Card className="border-destructive/40 bg-destructive/5 p-6">
        <h3 className="flex items-center gap-2 font-semibold text-destructive">
          <AlertTriangle className="h-4 w-4" />
          Não foi possível carregar a fila
        </h3>
        <p className="mt-2 text-sm text-muted-foreground">
          As propostas existem — o que falhou foi a leitura desta tela. Nada foi perdido.
        </p>
        <p className="mt-2 break-words rounded-md bg-background/60 p-2 font-mono text-xs">
          {(erroDaFila as Error)?.message ?? String(erroDaFila)}
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <Card className="p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <h3 className="flex items-center gap-2 font-semibold">
              <Sparkles className="h-4 w-4 text-primary" />
              Caixa de entrada financeira
            </h3>
            <p className="mt-1 text-sm text-muted-foreground">
              O sistema lê o extrato e propõe o lançamento pronto. Aprovar cria o registro da
              despesa — <strong>nenhum pagamento é feito aqui</strong>.
            </p>
          </div>
          <div className="flex shrink-0 flex-wrap gap-2">
            <Button variant="outline" size="sm" disabled={ocupado} onClick={() => gerar.mutate(false)}>
              <RefreshCw className={`mr-2 h-4 w-4 ${gerar.isPending ? 'animate-spin' : ''}`} />
              Analisar últimos 90 dias
            </Button>
            {/* O parâmetro existia na função desde o início, mas não havia como acioná-lo
                pela tela — então tudo que passava de 90 dias só aparecia na Conciliação e
                nunca chegava aqui. Fica separado do botão do dia a dia porque traz uma
                quantidade de propostas que atrapalha se vier sem querer. */}
            <Button
              variant="ghost"
              size="sm"
              disabled={ocupado}
              onClick={() => gerar.mutate(true)}
              title="Varre TODO o extrato, inclusive o que passa de 90 dias"
            >
              Incluir histórico antigo
            </Button>
            {/* Roda sozinho ao salvar uma regra; o botão existe para o caso de a regra ter
                sido criada em outro lugar (pelo agente, por voz) ou de o plano de contas
                ter mudado depois. */}
            {propostas.length > 0 && (
              <Button
                variant="ghost"
                size="sm"
                disabled={ocupado}
                onClick={() => reaplicar.mutate()}
                title="Reavalia as propostas da fila com as regras de hoje — não aprova nada"
              >
                <Wand2 className={`mr-2 h-4 w-4 ${reaplicar.isPending ? 'animate-pulse' : ''}`} />
                Aplicar minhas regras à fila
              </Button>
            )}
          </div>
        </div>

        {propostas.length > 0 && contagem.credit_card > 0 && contagem.bank > 0 && (
          <div className="mt-3 flex flex-wrap gap-1.5">
            {([
              ['todas', `Tudo (${contagem.todas})`, null],
              ['bank', `Conta corrente (${contagem.bank})`, <Landmark key="l" className="h-3 w-3" />],
              ['credit_card', `Fatura de cartão (${contagem.credit_card})`, <CreditCard key="c" className="h-3 w-3" />],
            ] as const).map(([valor, rotulo, icone]) => (
              <Button
                key={valor}
                size="sm"
                variant={origem === valor ? 'default' : 'outline'}
                className="h-7 gap-1.5 text-xs"
                onClick={() => setOrigem(valor as never)}
              >
                {icone}{rotulo}
              </Button>
            ))}
          </div>
        )}

        {propostas.length >= 20 && (
          <div className="mt-3 flex flex-wrap items-center gap-1.5">
            <Button
              size="sm" variant={agrupar ? 'default' : 'outline'}
              className="h-7 gap-1.5 text-xs" onClick={() => setModo('favorecido')}
            >
              <Users className="h-3 w-3" />Por favorecido ({grupos.length})
            </Button>
            <Button
              size="sm" variant={!agrupar ? 'default' : 'outline'}
              className="h-7 gap-1.5 text-xs" onClick={() => setModo('lista')}
            >
              <List className="h-3 w-3" />Uma a uma ({porOrigem.length})
            </Button>
            {agrupar && resumo.repetidos > 0 && (
              <span className="text-xs text-muted-foreground">
                {resumo.propostasEmRepetidos} linhas repetidas se resolvem em{' '}
                {resumo.repetidos === 1 ? 'uma decisão' : `${resumo.repetidos} decisões`}
              </span>
            )}
          </div>
        )}

        {propostas.length > 0 && (
          <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            {[
              { rotulo: 'Propostas', valor: String(porOrigem.length) },
              { rotulo: 'Valor total', valor: formatCurrency(totalValor) },
              { rotulo: agrupar ? 'Favorecidos' : `Até ${formatCurrency(LIMITE_LOTE)}`,
                valor: String(agrupar ? grupos.length : lote.length) },
              { rotulo: agrupar ? 'Sem categoria' : 'Revisar uma a uma',
                valor: String(agrupar ? resumo.semCategoria : individuais.length) },
            ].map((k) => (
              <div key={k.rotulo} className="rounded-lg border p-2">
                <p className="truncate text-xs text-muted-foreground">{k.rotulo}</p>
                <p className="truncate text-lg font-semibold">{k.valor}</p>
              </div>
            ))}
          </div>
        )}
      </Card>

      {propostas.length === 0 && (
        <Card className="p-8 text-center">
          <p className="text-muted-foreground">
            Nenhuma proposta pendente. <strong>Analisar últimos 90 dias</strong> varre o
            movimento recente; <strong>Incluir histórico antigo</strong> alcança o extrato
            inteiro — é onde está a maior parte do que ainda não virou lançamento.
          </p>
        </Card>
      )}

      {agrupar && grupos.map((g) => {
        const estado = estadoDoGrupo(g);
        return (
          <CartaoDoFavorecido
            key={g.chave}
            grupo={g}
            categoria={estado.category ?? ''}
            favorecidoId={estado.payeeId ?? null}
            osId={estado.serviceOrderId ?? null}
            onMudar={(c) => corrigirGrupo(g, c)}
            onAprovarLote={() => aprovarGrupo(g)}
            onCriarRegra={() => criarRegraDoGrupo(g)}
            ocupado={ocupado}
          >
            {g.propostas.map((p) => (
              <LinhaProposta
                key={p.id} {...propsComuns(p)} modoLote={false}
                selecionada={false} onSelecionar={() => {}}
              />
            ))}
          </CartaoDoFavorecido>
        );
      })}

      {!agrupar && lote.length > 0 && (
        <div className="space-y-2">
          <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border bg-muted/30 p-2">
            <div className="flex items-center gap-2">
              <Checkbox
                checked={selecionadas.size > 0 && selecionadas.size === lote.length}
                onCheckedChange={(v) => marcarTodasDoLote(v === true)}
                aria-label="Selecionar todas do lote"
              />
              <span className="text-sm font-medium">
                Aprovação em lote — até {formatCurrency(LIMITE_LOTE)} ({lote.length})
              </span>
            </div>
            <div className="flex items-center gap-2">
              {selecionadas.size > 0 && (
                <span className="text-xs text-muted-foreground">
                  {selecionadas.size} · {formatCurrency(valorSelecionado)}
                </span>
              )}
              <Button size="sm" disabled={ocupado || selecionadas.size === 0} onClick={aprovarSelecionadas}>
                <Check className="mr-2 h-4 w-4" />
                Aprovar selecionadas
              </Button>
            </div>
          </div>

          {lote.map((p) => (
            <LinhaProposta
              key={p.id} {...propsComuns(p)} modoLote
              selecionada={selecionadas.has(p.id)}
              onSelecionar={(m) => marcar(p.id, m)}
            />
          ))}
        </div>
      )}

      {!agrupar && individuais.length > 0 && (
        <div className="space-y-2">
          <div className="rounded-lg border bg-muted/30 p-2">
            <p className="text-sm font-medium">
              Revisar uma a uma — acima de {formatCurrency(LIMITE_LOTE)} e transferências ({individuais.length})
            </p>
          </div>
          {individuais.map((p) => (
            <LinhaProposta
              key={p.id} {...propsComuns(p)} modoLote={false}
              selecionada={false} onSelecionar={() => {}}
            />
          ))}
        </div>
      )}
    </div>
  );
}
