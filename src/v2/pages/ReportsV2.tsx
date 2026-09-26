import { Navigate, useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { DREPanel } from '@/components/DREPanel';
import { AgingReportPanel } from '@/components/AgingReportPanel';
import { PageShell } from '@/v2/components/PageShell';
import { V2Shell } from '@/v2/components/V2Shell';
import { AvisoAbasMudaram } from '@/v2/components/AvisoAbasMudaram';
import { SECOES_DA_CENTRAL, resolverCentral, rotaDaSecao, type SecaoDaCentral } from '@/v2/pages/relatorios/secoes';
import { ResumoDoMes } from '@/v2/pages/relatorios/ResumoDoMes';
import { FluxoDeCaixaSecao } from '@/v2/pages/relatorios/FluxoDeCaixaSecao';
import { ParaOndeFoi } from '@/v2/pages/relatorios/ParaOndeFoi';
import { Operacao } from '@/v2/pages/relatorios/Operacao';
import '@/v2/tokens.css';

/* Central de relatórios (26/09/2026) — uma porta só para tudo que é demonstrativo.

   Pedido do dono: "tudo que é demonstrativo ou relatório deveria estar em uma só aba, e lá
   dentro teria opções de aging, gráficos etc.". Antes eram três destinos soltos no menu (DRE,
   Aging, Gerenciais) e mais a Programação escondida entre as 14 abas do Financeiro. Agora:

     /v2/reports             Resumo do mês (padrão; o link antigo abre aqui)
     /v2/reports/fluxo       Fluxo de caixa — mês a mês pelo extrato + próximas 8 semanas
     /v2/reports/dre         Resultado (DRE)
     /v2/reports/categorias  Para onde foi o dinheiro
     /v2/reports/aging       Quem deve e a quem devo
     /v2/reports/operacao    Operação (a antiga "Gerenciais"; ?tab= antigo abre a parte certa)

   Um nível só de abas; cada seção diz para que serve embaixo do título. */

function conteudo(secao: SecaoDaCentral) {
  switch (secao) {
    case 'resumo': return <ResumoDoMes />;
    case 'fluxo': return <FluxoDeCaixaSecao />;
    case 'dre': return <DREPanel />;
    case 'categorias': return <ParaOndeFoi />;
    case 'aging': return <AgingReportPanel />;
    case 'operacao': return <Operacao />;
  }
}

export default function ReportsV2() {
  const navigate = useNavigate();
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const { secao } = useParams<{ secao?: string }>();
  const rota = resolverCentral(secao, searchParams.get('tab'));

  if (rota.tipo === 'redirecionar') {
    // A query vai junto (menos o ?tab=, que o redirecionamento já traduziu).
    const resto = new URLSearchParams(location.search);
    resto.delete('tab');
    const busca = resto.toString();
    return <Navigate to={`${rota.para}${busca ? `${rota.para.includes('?') ? '&' : '?'}${busca}` : ''}`} replace />;
  }

  const atual = SECOES_DA_CENTRAL.find((s) => s.secao === rota.secao)!;

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Central de relatórios', to: '/v2/reports' }, { label: atual.rotulo }]}
        title="Central de relatórios"
        description={atual.paraQueServe}
      >
        <AvisoAbasMudaram />
        <Tabs value={rota.secao} onValueChange={(v) => navigate(rotaDaSecao(v as SecaoDaCentral), { replace: true })}>
          <TabsList className="flex h-auto w-full flex-wrap justify-start">
            {SECOES_DA_CENTRAL.map((s) => (
              <TabsTrigger key={s.secao} value={s.secao}>{s.rotulo}</TabsTrigger>
            ))}
          </TabsList>
          {SECOES_DA_CENTRAL.map((s) => (
            <TabsContent key={s.secao} value={s.secao} className="mt-4">
              {s.secao === rota.secao && conteudo(s.secao)}
            </TabsContent>
          ))}
        </Tabs>
      </PageShell>
    </V2Shell>
  );
}
