import { useState } from 'react';
import { Link, Navigate, useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { Plus } from 'lucide-react';
import { usePendingReimbursements } from '@/hooks/use-service-order-expenses';
import { Button } from '@/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
// A comissão saiu do menu lateral (uso raro) e mora em Contas a Pagar — que é de onde ela é
// paga. O link antigo /v2/commissions leva para cá.
import { PainelDeComissoes } from '@/v2/pages/CommissionsV2';
import { LancarDialog, type TipoDeLancamento, type PorOnde } from '@/components/LancarDialog';
import { DespesasPanel } from '@/components/DespesasPanel';
import { ConciliacaoPanel } from '@/components/ConciliacaoPanel';
import { BankSourcesPanel } from '@/components/BankSourcesPanel';
import type { SementeDeRegra } from '@/components/FinanceReviewInbox';
import { FinanceRulesPanel, EditorDeRegra } from '@/components/FinanceRulesPanel';
import { ExtratoPorConta, type VisaoDoExtrato } from '@/components/ExtratoPorConta';
import { CartoesPanel } from '@/components/CartoesPanel';
import { FechamentoPanel } from '@/components/FechamentoPanel';
import { SaudeDoCadastroPanel } from '@/components/SaudeDoCadastroPanel';
import { ReimbursementsPanel } from '@/components/ReimbursementsPanel';
import { PageShell } from '@/v2/components/PageShell';
import { V2Shell } from '@/v2/components/V2Shell';
import { AvisoAbasMudaram } from '@/v2/components/AvisoAbasMudaram';
import { VisaoGeral } from '@/v2/pages/financeiro/VisaoGeral';
import { ContasAPagarLista } from '@/v2/pages/financeiro/ContasAPagarLista';
import { DiariasPanel, type FiltroDasDiarias } from '@/v2/pages/financeiro/DiariasPanel';
import { hojeLocal } from '@/lib/dia';
import {
  COMODOS, resolverFinanceiro, rotaDoComodo, paraQueServeDe, type Comodo,
} from '@/v2/pages/financeiro/rotas';
import '@/v2/tokens.css';

/* ─────────────────────────────────────────────────────────────────────────────
   Financeiro v2 — um cômodo por assunto (26/09/2026).

   Até aqui toda rota /v2/financial/<secao> mostrava a MESMA barra com 14 abas (Visão Geral,
   DRE, Contas a Pagar, Despesas, Comissões, Programação, Extrato, Conciliação, Cartões,
   Regras, Fechamento, Saúde do cadastro, Contas bancárias, Aging). O dono: "ainda achei
   abas demais". Agora cada rota abre SÓ o seu assunto, com título próprio, e as abas que
   sobram são recortes do mesmo material, num nível só:

     /v2/financial                 Visão Geral
     /v2/financial/inbox[/aba]     Extrato: Para revisar · Extrato com saldo · Fora da fila ·
                                   Cartão de crédito · Regras
     /v2/financial/reconciliation  Conciliação: Conciliação · Fechar o mês
     /v2/financial/payables        Contas a Pagar: Em aberto · Reembolsos · Comissões
     /v2/financial/despesas        Despesas
     /v2/financial/diarias[/aba]   Diárias: Resumo · Grade do mês · Extrato (freelancers, 28/09/2026)
     /v2/financial/banks           Contas bancárias
     /v2/financial/cadastro        Saúde do cadastro (a casa é Fornecedores; o link antigo
                                   continua abrindo o painel)

   DRE, Aging e Programação foram para a Central de relatórios (/v2/reports). Os links antigos
   (?tab=, /cartoes, /rules, /fechamento, /comissoes, /dre…) levam ao lugar novo — o mapa está
   em financeiro/rotas.ts, testado.
──────────────────────────────────────────────────────────────────────────── */

const TIPOS_DE_LANCAMENTO = ['despesa', 'recebimento', 'transferencia', 'contagem'];

export default function FinancialV2() {
  const navigate = useNavigate();
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const { secao, aba } = useParams<{ secao?: string; aba?: string }>();
  const rota = resolverFinanceiro(secao, aba, searchParams.get('tab'));

  // "+ Lançar": a porta única para registrar à mão, em toda tela do Financeiro. ?lancar=despesa
  // abre direto (atalho que o assistente pode mandar pelo WhatsApp).
  const [lancar, setLancar] = useState<{ tipo?: TipoDeLancamento; porOnde?: PorOnde } | null>(() => {
    const pedido = searchParams.get('lancar');
    return pedido && TIPOS_DE_LANCAMENTO.includes(pedido) ? { tipo: pedido as TipoDeLancamento } : null;
  });
  // Regra criada a partir de uma linha do Extrato: o editor abre preenchido, sem obrigar a
  // redigitar o fornecedor que está na tela.
  const [sementeRegra, setSementeRegra] = useState<SementeDeRegra | null>(null);
  // A conta escolhida nas fichas do Extrato sobrevive à troca de aba.
  const [contaDoExtrato, setContaDoExtrato] = useState<string | null>(null);
  // Diárias: o período e o freelancer escolhidos sobrevivem à troca entre Resumo e Extrato.
  const [filtroDiarias, setFiltroDiarias] = useState<FiltroDasDiarias>(
    () => ({ periodo: 'mes', favorecidoId: null, mes: hojeLocal().slice(0, 7) }),
  );
  const { data: pendingReimb } = usePendingReimbursements();

  if (rota.tipo === 'redirecionar') {
    // Leva o resto da query junto (?lancar=, ?view=); só o ?tab= antigo fica para trás.
    const resto = new URLSearchParams(location.search);
    resto.delete('tab');
    const busca = resto.toString();
    return <Navigate to={`${rota.para}${busca ? `${rota.para.includes('?') ? '&' : '?'}${busca}` : ''}`} replace />;
  }

  const { comodo, aba: abaAtiva } = rota;
  const def = COMODOS[comodo];
  // Aba é recorte: troca a rota, sempre dentro do mesmo cômodo (sair daqui ao clicar numa aba
  // foi a regressão de 30/07). A query fica para trás: ?lancar= é de uma vez só.
  const irPara = (c: Comodo, a?: string | null) => navigate(rotaDoComodo(c, a), { replace: true });

  const conteudo = (c: Comodo, a: string | null) => {
    switch (c) {
      case 'visao':
        return <VisaoGeral />;
      case 'extrato':
        if (a === 'cartao') return <CartoesPanel />;
        if (a === 'regras') return <FinanceRulesPanel />;
        return (
          <ExtratoPorConta
            visao={(a ?? 'revisar') as VisaoDoExtrato}
            contaId={contaDoExtrato}
            onEscolherConta={setContaDoExtrato}
            onCriarRegra={setSementeRegra}
          />
        );
      case 'conciliacao':
        return a === 'fechar' ? <FechamentoPanel /> : <ConciliacaoPanel />;
      case 'pagar':
        if (a === 'reembolsos') return <ReimbursementsPanel />;
        if (a === 'comissoes') return <PainelDeComissoes />;
        return <ContasAPagarLista onNovaConta={() => setLancar({ tipo: 'despesa', porOnde: 'depois' })} />;
      case 'despesas':
        return <DespesasPanel />;
      case 'diarias':
        return (
          <DiariasPanel
            aba={a === 'extrato' || a === 'grade' ? a : 'resumo'}
            filtro={filtroDiarias}
            onFiltro={setFiltroDiarias}
            onVerExtrato={(id) => { setFiltroDiarias({ ...filtroDiarias, favorecidoId: id }); irPara('diarias', 'extrato'); }}
          />
        );
      case 'bancos':
        return <BankSourcesPanel />;
      case 'cadastro':
        return (
          <div className="space-y-3">
            <p className="rounded-lg border bg-muted/40 px-3 py-2 text-sm">
              A casa desta tela agora é{' '}
              <Link to="/v2/suppliers/saude" className="font-medium text-accent underline-offset-2 hover:underline">
                Fornecedores › Saúde do cadastro
              </Link>
              : é cadastro de fornecedor.
            </p>
            <SaudeDoCadastroPanel />
          </div>
        );
    }
  };

  const rotuloDaAba = (a: string, rotulo: string) =>
    a === 'reembolsos' && (pendingReimb?.length ?? 0) > 0 ? `${rotulo} (${pendingReimb!.length})` : rotulo;

  return (
    <V2Shell>
      <PageShell
        breadcrumb={comodo === 'visao' ? [{ label: 'Financeiro' }, { label: def.nome }] : [{ label: 'Financeiro', to: '/v2/financial' }, { label: def.nome }]}
        title={def.nome}
        description={paraQueServeDe(comodo, abaAtiva)}
        actions={
          <Button className="gap-1.5" onClick={() => setLancar({})}>
            <Plus className="h-4 w-4" /> Lançar
          </Button>
        }
      >
        <AvisoAbasMudaram />

        {def.abas.length > 0 ? (
          <Tabs value={abaAtiva ?? def.abas[0].aba} onValueChange={(v) => irPara(comodo, v)}>
            <TabsList className="flex h-auto w-full flex-wrap justify-start">
              {def.abas.map((a) => (
                <TabsTrigger key={a.aba} value={a.aba}>{rotuloDaAba(a.aba, a.rotulo)}</TabsTrigger>
              ))}
            </TabsList>
            {def.abas.map((a) => (
              <TabsContent key={a.aba} value={a.aba} className="mt-4">
                {a.aba === abaAtiva && conteudo(comodo, a.aba)}
              </TabsContent>
            ))}
          </Tabs>
        ) : (
          conteudo(comodo, null)
        )}

        {/* Saída para a versão anterior enquanto a confiança na nova não se firma. Some
            quando a transição terminar — até lá, ficar preso é pior que ver um link. */}
        <p className="mt-8 text-center text-xs text-muted-foreground">
          Faltou alguma coisa?{' '}
          <a href="/financial?legacy=1" className="underline underline-offset-2 hover:text-foreground">
            Abrir a versão anterior
          </a>
        </p>
      </PageShell>

      {sementeRegra && (
        <EditorDeRegra
          key={sementeRegra.match_value}
          aberto
          onFechar={() => setSementeRegra(null)}
          regra={sementeRegra}
        />
      )}
      {lancar && <LancarDialog tipoInicial={lancar.tipo} porOndeInicial={lancar.porOnde} onFechar={() => setLancar(null)} />}
    </V2Shell>
  );
}
