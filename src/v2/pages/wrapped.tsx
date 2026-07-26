import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';
import VesselDetail from '@/pages/VesselDetail';
import ServiceOrderDetail from '@/pages/ServiceOrderDetail';
import FiscalEmission from '@/pages/FiscalEmission';
import SettingsPage from '@/pages/SettingsPage';
import ImportFiscalXML from '@/pages/ImportFiscalXML';
import WhatsAppLeadsPage from '@/pages/WhatsAppLeadsPage';
import WhatsAppLogsPage from '@/pages/WhatsAppLogsPage';
import WhatsAppScheduledPage from '@/pages/WhatsAppScheduledPage';
import WhatsAppStatusPage from '@/pages/WhatsAppStatusPage';
import ActiveProspectingPage from '@/pages/ActiveProspectingPage';
import ExternalQuoteListPage from '@/pages/ExternalQuoteListPage';
import ExternalQuoteNewPage from '@/pages/ExternalQuoteNewPage';
import ExternalQuoteApprovalPage from '@/pages/ExternalQuoteApprovalPage';
import ExternalSellerLeadsPage from '@/pages/ExternalSellerLeadsPage';
import ExternalProductCatalogPage from '@/pages/ExternalProductCatalogPage';
import ExternalQuoteDetailPage from '@/pages/ExternalQuoteDetailPage';

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

const wrap = (Comp: React.ComponentType) =>
  function WrappedV2() {
    return (
      <V2Shell>
        <Comp />
      </V2Shell>
    );
  };

export const VesselDetailV2 = wrap(VesselDetail);
export const ServiceOrderDetailV2 = wrap(ServiceOrderDetail);
export const FiscalEmissionV2 = wrap(FiscalEmission);
export const SettingsV2 = wrap(SettingsPage);
export const ImportFiscalXMLV2 = wrap(ImportFiscalXML);
export const WhatsAppLeadsV2 = wrap(WhatsAppLeadsPage);
export const WhatsAppLogsV2 = wrap(WhatsAppLogsPage);
export const WhatsAppScheduledV2 = wrap(WhatsAppScheduledPage);
export const WhatsAppStatusV2 = wrap(WhatsAppStatusPage);
export const ActiveProspectingV2 = wrap(ActiveProspectingPage);
export const ExternalQuoteListV2 = wrap(ExternalQuoteListPage);
export const ExternalQuoteNewV2 = wrap(ExternalQuoteNewPage);
export const ExternalQuoteApprovalV2 = wrap(ExternalQuoteApprovalPage);
export const ExternalSellerLeadsV2 = wrap(ExternalSellerLeadsPage);
export const ExternalProductCatalogV2 = wrap(ExternalProductCatalogPage);
export const ExternalQuoteDetailV2 = wrap(ExternalQuoteDetailPage);
