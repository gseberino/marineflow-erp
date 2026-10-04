import { lazy, Suspense, type ComponentType } from 'react';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* ─────────────────────────────────────────────────────────────────────────────
   Onda C / Fase 3 · Rotas v2 por CASCA DE TEMA.
   Estas telas já são P0-limpas (sem scroll lateral) e majoritariamente
   tokenizadas — o V2Shell cascateia os tokens Estaleiro Claro / Ponte de
   Comando para dentro delas, dando tema + alternador sem reescrever a
   lógica. Os monólitos da Fase 3 (OS/Fiscal/Config) entram aqui de
   propósito: a decomposição interna deles exige antes a rede de testes de
   paridade de cálculo (portão da Fase 3), e a casca mantém o FLUXO v2
   inteiro consistente enquanto isso.
──────────────────────────────────────────────────────────────────────────── */

/* Carregamento sob demanda (04/10/2026). Este arquivo importava as 17 telas de uma vez e o
   App importa este arquivo direto — então OS, Fiscal, Configurações, Agenda e as telas de
   orçamento externo iam TODAS no pacote do login (o chunk principal tinha 2,4 MB). Agora cada
   tela vira um pedaço próprio, baixado quando a rota abre; a casca (menu, tema) já aparece e
   só o miolo espera. */
const wrap = (carregar: () => Promise<{ default: ComponentType }>) => {
  const Tela = lazy(carregar);
  return function WrappedV2() {
    return (
      <V2Shell>
        <Suspense fallback={<CarregandoTela />}>
          <Tela />
        </Suspense>
      </V2Shell>
    );
  };
};

function CarregandoTela() {
  return (
    <div role="status" aria-label="Carregando" className="flex justify-center py-16">
      <div className="h-6 w-6 animate-spin rounded-full border-2 border-primary border-t-transparent" />
    </div>
  );
}

/* A Agenda ficou fora da v2 até agora porque outra sessão a estava reescrevendo ao mesmo
   tempo (fios soltos, detector, caixa de entrada) — mexer nela em paralelo teria dado
   conflito. Aquela frente terminou, então ela entra aqui e o mapa v2 fica completo.
   Casca, não reescrita: a Agenda já é P0-limpa (a Semana empilha no celular, o calendário
   do mês encolhe os pinos) e o que faltava era tema, alternador claro/escuro e ⌘K. */
export const AgendaV2 = wrap(() => import('@/pages/AgendaPage'));

export const VesselDetailV2 = wrap(() => import('@/pages/VesselDetail'));
export const ServiceOrderDetailV2 = wrap(() => import('@/pages/ServiceOrderDetail'));
export const FiscalEmissionV2 = wrap(() => import('@/pages/FiscalEmission'));
export const SettingsV2 = wrap(() => import('@/pages/SettingsPage'));
export const ImportFiscalXMLV2 = wrap(() => import('@/pages/ImportFiscalXML'));
export const WhatsAppLeadsV2 = wrap(() => import('@/pages/WhatsAppLeadsPage'));
export const WhatsAppLogsV2 = wrap(() => import('@/pages/WhatsAppLogsPage'));
export const WhatsAppScheduledV2 = wrap(() => import('@/pages/WhatsAppScheduledPage'));
export const WhatsAppStatusV2 = wrap(() => import('@/pages/WhatsAppStatusPage'));
export const ActiveProspectingV2 = wrap(() => import('@/pages/ActiveProspectingPage'));
export const ExternalQuoteListV2 = wrap(() => import('@/pages/ExternalQuoteListPage'));
export const ExternalQuoteNewV2 = wrap(() => import('@/pages/ExternalQuoteNewPage'));
export const ExternalQuoteApprovalV2 = wrap(() => import('@/pages/ExternalQuoteApprovalPage'));
export const ExternalSellerLeadsV2 = wrap(() => import('@/pages/ExternalSellerLeadsPage'));
export const ExternalProductCatalogV2 = wrap(() => import('@/pages/ExternalProductCatalogPage'));
export const ExternalQuoteDetailV2 = wrap(() => import('@/pages/ExternalQuoteDetailPage'));
