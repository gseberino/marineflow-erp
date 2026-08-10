// Cartões — separados de Pix e transferência, como o gestor pediu.
//
// "E cartões é totalmente separado. Lembra que a gente teve aquele problema com transações
//  de cartão misturada com transações de Pix e transferências e etcétera?"
//
// Cartão é outro objeto e por isso merece outra tela:
//   · não tem contraparte — a bandeira repassa estabelecimento e MCC, não o CNPJ;
//   · não sai do caixa na data da compra, e sim quando a fatura é paga;
//   · pertence a um ciclo que fecha, e é o ciclo que a pessoa quer ver.
//
// O QUE ESTA TELA REVELOU AO NASCER
// A empresa paga a fatura PARCIALMENTE e carrega saldo. Só 1 das 23 faturas foi paga pelo
// valor exato: uma de R$ 1.515 recebeu R$ 1.000 e R$ 990; outra de R$ 4.751 foi paga com
// R$ 6.370 (o ciclo mais o saldo anterior). Isso tem preço — há 42 lançamentos de juros,
// IOF e encargos no cartão — e ninguém conseguia ver nem uma coisa nem a outra.
import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { useI18n } from '@/i18n';
import {
  useFaturasDoCartao, useComprasDaFatura, usePagamentosDeFatura,
  useEncargosDoCartao, useComprasSemFatura,
  type FaturaDoCartao,
} from '@/hooks/use-cartoes';
// Importa a tabela do MOTOR, não uma cópia: duas listas do mesmo código é como uma delas
// fica para trás. Mesmo caminho que a caixa de entrada já usa.
import { categoriaPorMcc } from '../../supabase/functions/_shared/banking/mcc';
import { CreditCard, AlertTriangle, ChevronDown, ChevronRight, Percent } from 'lucide-react';

export function CartoesPanel() {
  const { formatCurrency, formatDate } = useI18n();
  const faturas = useFaturasDoCartao();
  const pagamentos = usePagamentosDeFatura();
  const encargos = useEncargosDoCartao();
  const semFatura = useComprasSemFatura();
  const [aberta, setAberta] = useState<string | null>(null);

  const resumo = useMemo(() => {
    const faturado = (faturas.data ?? []).reduce((s, f) => s + Number(f.total ?? 0), 0);
    const pago = (pagamentos.data ?? []).reduce((s, p) => s + Number(p.amount ?? 0), 0);
    return { faturado, pago, saldo: faturado - pago };
  }, [faturas.data, pagamentos.data]);

  // Erro precisa aparecer como erro. Lista vazia por falha de consulta parece "nada aqui" —
  // e foi assim que 1.178 propostas ficaram invisíveis atrás de um PGRST201.
  if (faturas.error) {
    return (
      <Card className="p-6 border-destructive/40">
        <div className="flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 shrink-0 text-destructive mt-0.5" />
          <div className="min-w-0">
            <h3 className="font-semibold">Não deu para carregar as faturas</h3>
            <p className="mt-1 text-sm text-muted-foreground break-words">{faturas.error.message}</p>
          </div>
        </div>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Cartões</h2>
        <p className="mt-0.5 text-sm text-muted-foreground">
          Cada compra é uma <strong>despesa</strong> na data em que foi feita. A{' '}
          <strong>fatura</strong> é o que se deve — e é ela que sai do banco.
        </p>
      </div>

      {faturas.isLoading ? (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-20" />)}
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <Numero rotulo="Faturado" valor={formatCurrency(resumo.faturado)}
            detalhe={`${faturas.data?.length ?? 0} faturas`} />
          <Numero rotulo="Pago ao cartão" valor={formatCurrency(resumo.pago)}
            detalhe={`${pagamentos.data?.length ?? 0} pagamentos`} />
          <Numero
            rotulo="Saldo em aberto"
            valor={formatCurrency(resumo.saldo)}
            detalhe={resumo.saldo > 0 ? 'faturado que ainda não foi pago' : 'nada em aberto'}
            alerta={resumo.saldo > 0}
          />
          <Numero
            rotulo="Juros e encargos"
            valor={formatCurrency(encargos.data?.total ?? 0)}
            detalhe={`${encargos.data?.quantidade ?? 0} lançamentos`}
            alerta={(encargos.data?.quantidade ?? 0) > 0}
            icone={<Percent className="h-3.5 w-3.5" />}
          />
        </div>
      )}

      {resumo.saldo > 0 && !faturas.isLoading && (
        <Card className="border-amber-500/40 bg-amber-500/5 p-3">
          <div className="flex items-start gap-2 text-sm">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
            <p className="min-w-0">
              A fatura vem sendo paga <strong>em parte</strong>: só 1 das{' '}
              {faturas.data?.length ?? 0} fechou pelo valor exato. O resto vira saldo
              rotativo, que é o que cobra os{' '}
              <strong>{encargos.data?.quantidade ?? 0} lançamentos de juros</strong> acima.
            </p>
          </div>
        </Card>
      )}

      <div className="space-y-2">
        {(faturas.data ?? []).map((f) => (
          <LinhaDaFatura
            key={f.bill_id}
            fatura={f}
            aberta={aberta === f.bill_id}
            onAlternar={() => setAberta((a) => (a === f.bill_id ? null : f.bill_id))}
            formatCurrency={formatCurrency}
            formatDate={formatDate}
          />
        ))}
      </div>

      {(semFatura.data?.length ?? 0) > 0 && (
        <Card className="p-3">
          <div className="flex items-start gap-2 text-sm">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
            <p className="min-w-0">
              <strong>{semFatura.data!.length} compras</strong> ainda não pertencem a fatura
              nenhuma — o provedor só informa o ciclo depois que ele fecha. Elas já contam
              como despesa; só não aparecem em nenhuma fatura acima.
            </p>
          </div>
        </Card>
      )}
    </div>
  );
}

function Numero({ rotulo, valor, detalhe, alerta = false, icone }: {
  rotulo: string; valor: string; detalhe: string; alerta?: boolean; icone?: React.ReactNode;
}) {
  return (
    <Card className={`p-3 ${alerta ? 'border-amber-500/40' : ''}`}>
      <p className="flex items-center gap-1.5 text-xs text-muted-foreground">{icone}{rotulo}</p>
      <p className={`mt-1 text-xl font-semibold tabular-nums ${alerta ? 'text-amber-600' : ''}`}>
        {valor}
      </p>
      <p className="mt-0.5 truncate text-xs text-muted-foreground">{detalhe}</p>
    </Card>
  );
}

function LinhaDaFatura({ fatura: f, aberta, onAlternar, formatCurrency, formatDate }: {
  fatura: FaturaDoCartao;
  aberta: boolean;
  onAlternar: () => void;
  formatCurrency: (n: number) => string;
  formatDate: (d: string) => string;
}) {
  return (
    <Card className="overflow-hidden">
      <button
        onClick={onAlternar}
        className="flex w-full items-center gap-3 p-3 text-left transition-colors hover:bg-muted/40"
      >
        {aberta ? <ChevronDown className="h-4 w-4 shrink-0" /> : <ChevronRight className="h-4 w-4 shrink-0" />}
        <CreditCard className="h-4 w-4 shrink-0 text-muted-foreground" />

        {/* min-w-0 nos filhos flex: sem isso um período longo empurra a linha e nasce
            rolagem lateral, que nesta casa não pode existir. */}
        <div className="min-w-0 flex-1">
          <p className="truncate font-medium">
            {formatDate(f.primeira_compra)} a {formatDate(f.ultima_compra)}
          </p>
          <p className="truncate text-xs text-muted-foreground">
            {f.compras} {f.compras === 1 ? 'compra' : 'compras'}
            {f.compras_parceladas > 0 && ` · ${f.compras_parceladas} parcelada(s)`}
            {f.cartoes && ` · cartão ····${f.cartoes.split(', ').join(', ····')}`}
          </p>
        </div>

        {f.pagamento_id ? (
          <Badge className="shrink-0 bg-success/15 text-success hover:bg-success/15">
            paga em {f.pagamento_data ? formatDate(f.pagamento_data) : '—'}
          </Badge>
        ) : (
          <Badge variant="outline" className="shrink-0 text-muted-foreground">
            pagamento não identificado
          </Badge>
        )}

        <span className="shrink-0 font-semibold tabular-nums">{formatCurrency(Number(f.total))}</span>
      </button>

      {aberta && <ComprasDaFatura billId={f.bill_id} formatCurrency={formatCurrency} formatDate={formatDate} />}
    </Card>
  );
}

function ComprasDaFatura({ billId, formatCurrency, formatDate }: {
  billId: string;
  formatCurrency: (n: number) => string;
  formatDate: (d: string) => string;
}) {
  const compras = useComprasDaFatura(billId);

  if (compras.isLoading) return <div className="border-t p-3"><Skeleton className="h-20 w-full" /></div>;
  if (compras.error) {
    return (
      <div className="border-t p-3 text-sm text-destructive break-words">
        Não deu para carregar as compras: {compras.error.message}
      </div>
    );
  }

  return (
    <div className="space-y-1 border-t bg-muted/20 p-3">
      {(compras.data ?? []).map((c) => {
        const ramo = categoriaPorMcc(c.payee_mcc)?.rotulo;
        return (
          <div key={c.id} className="flex items-center gap-2 text-sm">
            <span className="shrink-0 text-xs text-muted-foreground tabular-nums">
              {formatDate(c.transaction_date)}
            </span>
            <div className="min-w-0 flex-1">
              <p className="truncate">{c.counterparty_name || c.description || 'Sem descrição'}</p>
              {/* A identificação que compra de cartão TEM: ramo pela bandeira, categoria do
                  provedor e final do cartão. CNPJ não vem — só 4% têm, e não é defeito. */}
              {(ramo || c.provider_category || c.card_last_digits) && (
                <p className="truncate text-xs text-muted-foreground">
                  {[ramo, c.provider_category, c.card_last_digits && `cartão ····${c.card_last_digits}`,
                    c.installment_label && `parcela ${c.installment_label}`]
                    .filter(Boolean).join(' · ')}
                </p>
              )}
            </div>
            <span className="shrink-0 tabular-nums">{formatCurrency(Number(c.amount))}</span>
          </div>
        );
      })}
    </div>
  );
}
