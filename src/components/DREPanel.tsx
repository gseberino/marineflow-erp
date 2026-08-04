// DRE — o resultado do período, montado pelos grupos do plano de contas.
//
// A versão anterior agrupava por CENTRO DE CUSTO e procurava nomes fixos ("Custos
// Variáveis (CPV/CSV)", "Despesas com Pessoal"). Nenhum centro de custo foi cadastrado e
// o campo `cost_center_id` está vazio nos 367 lançamentos: o relatório existia e mostrava
// zero em tudo. Este lê `dre_group`, que é onde a classificação de fato mora.
import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { useI18n } from '@/i18n';
import { useAuth } from '@/hooks/use-auth';
import { supabase } from '@/integrations/supabase/client';
import { exportToCSV } from '@/lib/export';
import { montarDRE, doMes, type LancamentoDRE, type GrupoDRE } from '@/lib/dre';
import { Download, ChevronDown, AlertTriangle, Lock } from 'lucide-react';

/** Lançamentos do ano com o grupo já resolvido pelo plano de contas. */
function useLancamentosDRE(ano: number) {
  return useQuery({
    queryKey: ['dre-lancamentos', ano],
    queryFn: async (): Promise<LancamentoDRE[]> => {
      const de = `${ano}-01-01`;
      const ate = `${ano}-12-31`;

      const [cats, pays, recs] = await Promise.all([
        supabase.from('financial_categories').select('name, type, dre_group'),
        supabase.from('payables').select('issue_date, amount, expense_category')
          .gte('issue_date', de).lte('issue_date', ate),
        supabase.from('receivables').select('issue_date, amount, category, status')
          .gte('issue_date', de).lte('issue_date', ate),
      ]);
      if (cats.error) throw cats.error;
      if (pays.error) throw pays.error;
      if (recs.error) throw recs.error;

      const grupoDe = new Map<string, GrupoDRE>();
      for (const c of (cats.data ?? []) as any[]) {
        if (c.dre_group) grupoDe.set(`${c.type}:${c.name}`, c.dre_group);
      }

      const despesas: LancamentoDRE[] = ((pays.data ?? []) as any[]).map((p) => ({
        data: p.issue_date,
        valor: Number(p.amount),
        categoria: p.expense_category,
        grupo: p.expense_category ? grupoDe.get(`payable:${p.expense_category}`) ?? null : null,
        tipo: 'despesa',
      }));

      const receitas: LancamentoDRE[] = ((recs.data ?? []) as any[])
        // Receita cancelada não é receita — entraria inflando o faturamento.
        .filter((r) => r.status !== 'cancelled')
        .map((r) => ({
          data: r.issue_date,
          valor: Number(r.amount),
          categoria: r.category,
          // Receita sem categoria ainda é receita: a natureza do lançamento já diz onde
          // entra, diferente da despesa, onde é a categoria que define o grupo.
          grupo: (r.category ? grupoDe.get(`receivable:${r.category}`) : null) ?? 'receita',
          tipo: 'receita',
        }));

      return [...despesas, ...receitas];
    },
    staleTime: 60_000,
  });
}

/**
 * Quanto entrou na conta e ainda não virou receita lançada.
 *
 * Existe porque este DRE nasce torto por construção: a caixa de entrada lança DESPESA
 * automaticamente, mas nunca receita — entrada quase sempre corresponde a um orçamento ou
 * OS que já existe, e criar receita avulsa duplicaria o faturamento na hora de faturar.
 * A consequência é um resultado com quase todas as despesas e quase nenhuma receita, que
 * mostra prejuízo onde não há. Sem este aviso, o número mente com cara de certo.
 */
function useEntradasNaoLancadas(ano: number) {
  return useQuery({
    queryKey: ['dre-entradas-pendentes', ano],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('bank_transactions')
        .select('amount')
        .eq('transaction_type', 'credit')
        .eq('reconciled', false)
        .eq('source_type', 'bank')
        .gte('transaction_date', `${ano}-01-01`)
        .lte('transaction_date', `${ano}-12-31`);
      if (error) throw error;
      const linhas = (data ?? []) as { amount: number }[];
      return {
        quantidade: linhas.length,
        valor: linhas.reduce((s, t) => s + Number(t.amount), 0),
      };
    },
    staleTime: 60_000,
  });
}

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

export function DREPanel() {
  const { formatCurrency } = useI18n();
  const { user } = useAuth();
  const anoAtual = new Date().getFullYear();
  const [ano, setAno] = useState(anoAtual);
  const [mes, setMes] = useState<number | 'ano'>('ano');

  const { data: lancamentos = [], isLoading } = useLancamentosDRE(ano);
  const { data: entradasPendentes } = useEntradasNaoLancadas(ano);

  const recorte = useMemo(
    () => (mes === 'ano' ? lancamentos : doMes(lancamentos, ano, mes)),
    [lancamentos, ano, mes],
  );
  const dre = useMemo(() => montarDRE(recorte), [recorte]);

  // Quem não é admin não enxerga pró-labore nem folha (a RLS os oculta). Sem dizer isso, o
  // resultado parece melhor do que é e ninguém tem como desconfiar.
  const veTudo = user?.role === 'admin';

  const exportar = () => {
    exportToCSV(
      dre.linhas.map((l) => ({
        linha: l.rotulo,
        valor: l.valor,
        percentual: l.percentual,
      })),
      `dre-${ano}${mes === 'ano' ? '' : '-' + String(mes).padStart(2, '0')}`,
      [
        { key: 'linha', label: 'Linha' },
        // Duas casas e ponto decimal: o CSV vai para planilha, não para leitura humana.
        { key: 'valor', label: 'Valor', format: (v) => Number(v).toFixed(2) },
        { key: 'percentual', label: '% da receita', format: (v) => (v == null ? '' : Number(v).toFixed(1)) },
      ],
    );
  };

  if (isLoading) {
    return <div className="space-y-2">{[...Array(6)].map((_, i) => <Skeleton key={i} className="h-10 rounded-lg" />)}</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Select value={String(ano)} onValueChange={(v) => setAno(Number(v))}>
            <SelectTrigger className="h-9 w-28"><SelectValue /></SelectTrigger>
            <SelectContent>
              {[anoAtual, anoAtual - 1, anoAtual - 2].map((a) => (
                <SelectItem key={a} value={String(a)}>{a}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={String(mes)} onValueChange={(v) => setMes(v === 'ano' ? 'ano' : Number(v))}>
            <SelectTrigger className="h-9 w-40"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="ano">Ano inteiro</SelectItem>
              {MESES.map((m, i) => <SelectItem key={m} value={String(i + 1)}>{m}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        <Button variant="outline" size="sm" onClick={exportar}>
          <Download className="mr-2 h-4 w-4" />Exportar
        </Button>
      </div>

      {!veTudo && (
        <div className="flex items-start gap-2 rounded-lg border border-info/40 bg-info/10 p-3 text-sm text-info">
          <Lock className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            Pró-labore e folha não aparecem no seu perfil, então o resultado abaixo está
            <strong> incompleto</strong>. Peça a versão completa a um administrador.
          </span>
        </div>
      )}

      {/* Primeiro aviso da tela, de propósito: quem lê um resultado precisa saber que ele
          está torto ANTES de ler o número, não depois. */}
      {!!entradasPendentes?.quantidade && (
        <div className="flex items-start gap-2 rounded-lg border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            <strong>Este resultado está incompleto do lado da receita.</strong>{' '}
            {entradasPendentes.quantidade} entrada(s) somando{' '}
            <strong>{formatCurrency(entradasPendentes.valor)}</strong> caíram na conta e
            ainda não viraram receita lançada — o sistema não cria receita sozinho para não
            duplicar o que a OS vai faturar. Enquanto isso, quase toda a despesa já está
            aqui, então o resultado abaixo <strong>parece pior do que é</strong>.
            Concilie as entradas na aba Conciliação para o número fechar.
          </span>
        </div>
      )}

      {dre.semGrupo !== 0 && (
        <div className="flex items-start gap-2 rounded-lg border border-warning/40 bg-warning/10 p-3 text-sm text-warning">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            <strong>{formatCurrency(dre.semGrupo)}</strong> em lançamentos sem grupo no
            plano de contas — não entram em nenhuma linha abaixo. Classifique-os para o
            resultado fechar.
          </span>
        </div>
      )}

      <Card className="overflow-hidden">
        {dre.linhas.map((linha) => {
          const negativo = linha.valor < 0;
          const temDetalhe = !!linha.detalhe?.length;

          const conteudo = (
            <div className={`flex items-center justify-between gap-3 px-4 py-2.5 ${
              linha.total ? 'bg-muted/50 font-semibold' : ''
            }`}>
              <span className="flex min-w-0 items-center gap-1.5">
                {temDetalhe && <ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />}
                <span className="truncate">{linha.rotulo}</span>
              </span>
              <span className="flex shrink-0 items-center gap-3">
                {linha.percentual != null && (
                  <span className="w-14 text-right text-xs tabular-nums text-muted-foreground">
                    {linha.percentual.toFixed(1)}%
                  </span>
                )}
                <span className={`w-32 text-right tabular-nums ${
                  linha.chave === 'resultado'
                    ? (linha.valor >= 0 ? 'text-success' : 'text-destructive')
                    : negativo ? 'text-muted-foreground' : ''
                }`}>
                  {formatCurrency(linha.valor)}
                </span>
              </span>
            </div>
          );

          if (!temDetalhe) {
            return <div key={linha.chave} className="border-b last:border-0">{conteudo}</div>;
          }

          return (
            <Collapsible key={linha.chave}>
              <div className="border-b last:border-0">
                <CollapsibleTrigger className="w-full text-left hover:bg-muted/30">
                  {conteudo}
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <div className="bg-muted/20 px-4 pb-2">
                    {linha.detalhe!.map((d) => (
                      <div key={d.categoria} className="flex items-center justify-between gap-3 py-1 pl-6 text-sm">
                        <span className="truncate text-muted-foreground">{d.categoria}</span>
                        <span className="w-32 shrink-0 text-right tabular-nums text-muted-foreground">
                          {formatCurrency(d.valor)}
                        </span>
                      </div>
                    ))}
                  </div>
                </CollapsibleContent>
              </div>
            </Collapsible>
          );
        })}
      </Card>

      {dre.naoOperacional !== 0 && (
        <Card className="p-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="min-w-0">
              <p className="font-medium">Fora do resultado</p>
              {/* A linha que mais engana num resultado caseiro. */}
              <p className="mt-0.5 text-sm text-muted-foreground">
                Pagamento de fatura, transferência entre contas próprias e aplicação
                financeira movimentam dinheiro sem ser despesa — a despesa está nos itens
                dentro da fatura, não nela.
              </p>
            </div>
            <span className="shrink-0 text-lg font-semibold tabular-nums">
              {formatCurrency(dre.naoOperacional)}
            </span>
          </div>
        </Card>
      )}
    </div>
  );
}
