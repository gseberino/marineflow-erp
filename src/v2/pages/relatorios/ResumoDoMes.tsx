// Central de relatórios › Resumo do mês: quatro números, cada um dizendo de onde vem.
//
// Entrou e Saiu vêm do EXTRATO (o dinheiro que passou pelas contas); Vendido e Resultado vêm
// do DRE (o que foi lançado, pela data de emissão). São perguntas diferentes — "quanto
// dinheiro passou?" e "a empresa ganhou dinheiro?" — e a tela diz qual é qual.
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { AlertTriangle } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useAuth } from '@/hooks/use-auth';
import { useFluxoDeCaixa } from '@/hooks/use-fluxo-de-caixa';
import { useLancamentosDRE } from '@/hooks/use-dre';
import { montarDRE, doMes, coberturaDoDRE, BASE_DO_DRE } from '@/lib/dre';
import { hojeEmBrasilia, nomeDoMes, ultimosMeses } from '@/lib/fluxo-de-caixa';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Skeleton } from '@/components/ui/skeleton';
import { AjudaDoExtrato, FicouDeFora } from '@/components/FluxoDoExtrato';
import { KPIStat } from '@/v2/components/KPIStat';

export function ResumoDoMes() {
  const { formatCurrency } = useI18n();
  const { user } = useAuth();
  const hoje = hojeEmBrasilia();
  const opcoes = useMemo(() => ultimosMeses(12, hoje).reverse(), [hoje]);
  const [mes, setMes] = useState(opcoes[0]);
  const [ano, numeroDoMes] = mes.split('-').map(Number);

  const fluxo = useFluxoDeCaixa(1, mes);
  const dre = useLancamentosDRE(ano);
  const doMesNoDRE = useMemo(
    () => (dre.data ? doMes(dre.data, ano, numeroDoMes) : null),
    [dre.data, ano, numeroDoMes],
  );
  const doResultado = useMemo(() => (doMesNoDRE ? montarDRE(doMesNoDRE) : null), [doMesNoDRE]);

  const doMesNoExtrato = fluxo.data?.meses[0];
  const mesCorrente = mes === hoje.slice(0, 7);
  // Quem não é admin não enxerga pró-labore nem folha (a RLS os oculta): o resultado dele sai
  // incompleto, e a tela precisa dizer.
  const veTudo = user?.role === 'admin';
  // A mesma conta do selo do DRE (coberturaDoDRE): os dois lugares dizem o mesmo percentual.
  const cobertura = doMesNoExtrato && doMesNoDRE
    ? coberturaDoDRE(doMesNoDRE, doMesNoExtrato).pctReceita
    : null;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <Select value={mes} onValueChange={setMes}>
          <SelectTrigger className="h-9 w-56" aria-label="Mês do resumo"><SelectValue /></SelectTrigger>
          <SelectContent>
            {opcoes.map((m) => <SelectItem key={m} value={m}>{nomeDoMes(m)}</SelectItem>)}
          </SelectContent>
        </Select>
        {mesCorrente && <span className="text-xs text-muted-foreground">O mês ainda não acabou: os números mudam até o fim dele.</span>}
      </div>

      {(fluxo.error || dre.error) && (
        <p className="rounded-lg border border-destructive/40 bg-destructive/5 p-3 text-sm text-destructive">
          Não consegui ler {fluxo.error ? 'o extrato' : 'os lançamentos do DRE'}: {String(((fluxo.error || dre.error) as Error)?.message ?? 'erro')}
        </p>
      )}

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {fluxo.isLoading || !doMesNoExtrato ? (
          <>
            <Skeleton className="h-28 rounded-lg" />
            <Skeleton className="h-28 rounded-lg" />
          </>
        ) : (
          <>
            <KPIStat
              label="Entrou (extrato)"
              value={formatCurrency(doMesNoExtrato.entrou)}
              hint="Nas contas e no Caixa, pela data do extrato. Sem transferência entre contas suas."
              ajuda={<AjudaDoExtrato rotulo="De onde vem o Entrou" />}
            />
            <KPIStat
              label="Saiu (extrato)"
              value={formatCurrency(doMesNoExtrato.saiu)}
              hint="Das contas e do Caixa. O cartão de crédito conta quando a fatura é paga."
              ajuda={<AjudaDoExtrato rotulo="De onde vem o Saiu" />}
            />
          </>
        )}
        {dre.isLoading || !doResultado ? (
          <>
            <Skeleton className="h-28 rounded-lg" />
            <Skeleton className="h-28 rounded-lg" />
          </>
        ) : (
          <>
            <KPIStat
              label="Vendido"
              value={formatCurrency(doResultado.receitaTotal)}
              hint="Receita lançada no mês, pela data de emissão — a mesma do DRE."
            />
            <KPIStat
              label="Resultado"
              value={formatCurrency(doResultado.resultado)}
              hint={veTudo
                ? 'Vendido menos custos e despesas do mês — o do DRE.'
                : 'O do DRE, sem pró-labore e folha (seu perfil não os vê): está incompleto.'}
            />
          </>
        )}
      </div>

      {doMesNoExtrato && (
        <div className="space-y-1 rounded-lg border bg-card p-3 text-sm">
          <p>
            Entrou menos saiu em {nomeDoMes(mes)}:{' '}
            <b className={`tabular-nums ${doMesNoExtrato.liquido >= 0 ? 'text-success' : 'text-destructive'}`}>{formatCurrency(doMesNoExtrato.liquido)}</b>
          </p>
          <FicouDeFora transferencias={doMesNoExtrato.transferencias} creditoDoCartao={doMesNoExtrato.creditoDoCartao} />
        </div>
      )}

      {/* O DRE daqui nasce torto: o Extrato lança despesa sozinho, receita não. Sem este aviso,
          um resultado negativo parece prejuízo de verdade. */}
      {cobertura != null && cobertura < 60 && (
        <p className="flex items-start gap-2 rounded-lg border border-warning/40 bg-warning/10 p-3 text-sm text-warning">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            O vendido lançado é {cobertura}% do que entrou no banco neste mês: parte das vendas ainda não foi
            lançada, e o Resultado parece pior do que é. Veja o selo em{' '}
            <Link to="/v2/reports/dre" className="font-medium underline underline-offset-2">Resultado (DRE)</Link>.
          </span>
        </p>
      )}

      <p className="text-xs text-muted-foreground">Vendido e Resultado — {BASE_DO_DRE}</p>

      <p className="text-xs text-muted-foreground">
        Mês a mês: <Link to="/v2/reports/fluxo" className="underline underline-offset-2 hover:text-foreground">Fluxo de caixa</Link>
        {' · '}
        Linha por linha do resultado: <Link to="/v2/reports/dre" className="underline underline-offset-2 hover:text-foreground">Resultado (DRE)</Link>
        {' · '}
        Por categoria: <Link to="/v2/reports/categorias" className="underline underline-offset-2 hover:text-foreground">Para onde foi o dinheiro</Link>
      </p>
    </div>
  );
}
