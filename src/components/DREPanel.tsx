// DRE — o resultado do período, montado pelos grupos do plano de contas.
//
// A versão anterior agrupava por CENTRO DE CUSTO e procurava nomes fixos ("Custos
// Variáveis (CPV/CSV)", "Despesas com Pessoal"). Nenhum centro de custo foi cadastrado e
// o campo `cost_center_id` está vazio nos 367 lançamentos: o relatório existia e mostrava
// zero em tudo. Este lê `dre_group`, que é onde a classificação de fato mora.
import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { useI18n } from '@/i18n';
import { useAuth } from '@/hooks/use-auth';
import { exportToCSV } from '@/lib/export';
import { montarDRE, doMes, coberturaDoDRE } from '@/lib/dre';
// Os lançamentos do ano, com o grupo do plano de contas: a mesma leitura serve o Resumo do
// mês da Central de relatórios, para "vendido" e "resultado" não terem dois números.
import { useLancamentosDRE } from '@/hooks/use-dre';
import { useFluxoDeCaixa } from '@/hooks/use-fluxo-de-caixa';
import { Download, ChevronDown, AlertTriangle, CheckCircle2, Lock } from 'lucide-react';

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

export function DREPanel() {
  const { formatCurrency } = useI18n();
  const { user } = useAuth();
  const anoAtual = new Date().getFullYear();
  const [ano, setAno] = useState(anoAtual);
  const [mes, setMes] = useState<number | 'ano'>('ano');

  const { data: lancamentos = [], isLoading } = useLancamentosDRE(ano);
  // O ano inteiro do extrato, com a regra da Central de relatórios (transferência pareada fora,
  // importação repetida fora…): o selo e o Resumo do mês dizem a mesma cobertura.
  const { data: fluxoDoAno } = useFluxoDeCaixa(12, `${ano}-12`);

  const recorte = useMemo(
    () => (mes === 'ano' ? lancamentos : doMes(lancamentos, ano, mes)),
    [lancamentos, ano, mes],
  );
  const dre = useMemo(() => montarDRE(recorte), [recorte]);

  /*
   * Cobertura: quanto do dinheiro que passou pelo banco este resultado explica.
   *
   * Este DRE nasce torto por construção: a caixa de entrada lança DESPESA automaticamente, mas
   * nunca receita — entrada quase sempre corresponde a um orçamento ou OS que já existe, e criar
   * receita avulsa duplicaria o faturamento na hora de faturar. Medido em 22/09/2026: 38% das
   * entradas do ano viraram receita, contra 96% das saídas. O resultado mostra prejuízo onde
   * não há.
   *
   * O selo acompanha o recorte escolhido: olhar o ano inteiro quando a tela mostra março diria
   * que o número está bom enquanto março está vazio.
   */
  const selo = useMemo(() => {
    const meses = (fluxoDoAno?.meses ?? []).filter((m) => mes === 'ano' || Number(m.mes.slice(5, 7)) === mes);
    const somaEm = (f: (m: typeof meses[number]) => number) =>
      Math.round(meses.reduce((s, m) => s + Math.round(f(m) * 100), 0)) / 100;
    return coberturaDoDRE(recorte, { entrou: somaEm((m) => m.entrou), saiu: somaEm((m) => m.saiu) });
  }, [fluxoDoAno, recorte, mes]);

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

      {/* Primeiro elemento da tela, de propósito: quem lê um resultado precisa saber o
          quanto ele é confiável ANTES de ler o número, não depois. */}
      {!selo.semMovimento && (
        <SeloDeConfiabilidade selo={selo} formatCurrency={formatCurrency} />
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


/**
 * O selo diz, em uma linha, o quanto deste resultado dá para acreditar — e mostra a conta
 * que sustenta a afirmação, para ninguém precisar confiar no rótulo.
 *
 * Faixa deliberada: até 60% o resultado não serve para decidir; de 60 a 90 serve com
 * ressalva; acima de 90 fecha. O lado da despesa passa de 100% quando a conta foi emitida
 * num mês e paga noutro — é descasamento de data, e o texto diz isso em vez de esconder.
 */
function SeloDeConfiabilidade({
  selo, formatCurrency,
}: {
  selo: {
    receita: number; entrada: number; despesa: number; saida: number;
    pctReceita: number | null; pctDespesa: number | null; faltaReceita: number;
  };
  formatCurrency: (v: number) => string;
}) {
  const pct = selo.pctReceita;
  const nivel = pct == null ? 'sem' : pct >= 90 ? 'bom' : pct >= 60 ? 'parcial' : 'ruim';

  const estilo = {
    bom: 'border-success/40 bg-success/10 text-success',
    parcial: 'border-warning/40 bg-warning/10 text-warning',
    ruim: 'border-destructive/40 bg-destructive/10 text-destructive',
    sem: 'border-muted-foreground/30 bg-muted/40 text-muted-foreground',
  }[nivel];

  const titulo = {
    bom: 'Resultado confiável.',
    parcial: 'Resultado parcial.',
    ruim: 'Este resultado não fecha.',
    sem: 'Sem entrada no banco neste período.',
  }[nivel];

  return (
    <div className={`rounded-lg border p-3 text-sm ${estilo}`}>
      <div className="flex items-start gap-2">
        {nivel === 'bom'
          ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
          : <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />}
        <div className="min-w-0 space-y-1.5">
          <p>
            <strong>{titulo}</strong>{' '}
            {pct != null && (
              <>
                O sistema explica <strong>{pct}%</strong> do que entrou na conta
                {selo.faltaReceita > 0 && (
                  <> — faltam <strong>{formatCurrency(selo.faltaReceita)}</strong> sem receita lançada</>
                )}
                .{' '}
              </>
            )}
            {nivel === 'ruim' && (
              <>A despesa está quase toda aqui e boa parte da receita não, então o resultado
              abaixo <strong>parece pior do que é</strong>. Concilie as entradas em Financeiro ›
              Conciliação — ou feche no sistema as ordens de serviço que geraram esse dinheiro.</>
            )}
            {nivel === 'parcial' && (
              <>Serve para acompanhar a tendência, ainda não para decidir com precisão.</>
            )}
            {nivel === 'bom' && (
              <>Entradas e lançamentos batem: o resultado abaixo pode ser usado para decidir.</>
            )}
          </p>

          {/* A conta, à vista: o rótulo acima é uma leitura, isto é o dado. */}
          <div className="flex flex-wrap gap-x-5 gap-y-1 text-xs tabular-nums opacity-90">
            <span>
              Receita lançada {formatCurrency(selo.receita)} de {formatCurrency(selo.entrada)} que entrou
            </span>
            <span>
              Despesa lançada {formatCurrency(selo.despesa)} de {formatCurrency(selo.saida)} que saiu
              {selo.pctDespesa != null && ` (${selo.pctDespesa}%)`}
            </span>
          </div>
          {selo.pctDespesa != null && selo.pctDespesa > 105 && (
            <p className="text-xs opacity-80">
              A despesa passa de 100% porque a conta é contada pela emissão e a saída do banco
              pelo pagamento: contas emitidas neste mês saíram da conta noutro.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
