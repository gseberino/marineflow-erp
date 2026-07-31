import { lazy, Suspense, type ReactNode } from "react";
import { QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Navigate, Route, Routes, useLocation, useParams, useSearchParams } from "react-router-dom";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { I18nProvider } from "@/i18n";
import { AuthProvider } from "@/hooks/use-auth";
import { ProtectedRoute } from "@/components/ProtectedRoute";
import { QueryGate } from "@/components/QueryGate";
import { AppLayout } from "@/components/AppLayout";
import { DiagnosticFallback } from "@/components/DiagnosticFallback";
import { GlobalErrorBoundary } from "@/components/GlobalErrorBoundary";
import { queryClient } from "@/lib/query-client";
const Dashboard = lazy(() => import("./pages/Dashboard"));
const ServiceOrderList = lazy(() => import("./pages/ServiceOrderList"));
const ServiceOrderDetail = lazy(() => import("./pages/ServiceOrderDetail"));
const ClientList = lazy(() => import("./pages/ClientList"));
const ClientDetail = lazy(() => import("./pages/ClientDetail"));
const VesselList = lazy(() => import("./pages/VesselList"));
const VesselDetail = lazy(() => import("./pages/VesselDetail"));
const MarinaList = lazy(() => import("./pages/MarinaList"));
const ProductList = lazy(() => import("./pages/ProductList"));
const InventoryPage = lazy(() => import("./pages/InventoryPage"));
const AgendaPage = lazy(() => import("./pages/AgendaPage"));
const DayBoardPage = lazy(() => import("./pages/DayBoardPage"));
const StepTemplatesPage = lazy(() => import("./pages/StepTemplatesPage"));
const FinancialPage = lazy(() => import("./pages/FinancialPage"));
const ReportsPage = lazy(() => import("./pages/ReportsPage"));
const CollectionsPage = lazy(() => import("./pages/CollectionsPage"));
const SettingsPage = lazy(() => import("./pages/SettingsPage"));
const SupplierList = lazy(() => import("./pages/SupplierList"));
const ServiceList = lazy(() => import("./pages/ServiceList"));
const AuditLogPage = lazy(() => import("./pages/AuditLogPage"));
const WhatsAppLeadsPage = lazy(() => import("./pages/WhatsAppLeadsPage"));
const WhatsAppLogsPage = lazy(() => import("./pages/WhatsAppLogsPage"));
const WhatsAppStatusPage = lazy(() => import("./pages/WhatsAppStatusPage"));
const WhatsAppScheduledPage = lazy(() => import("./pages/WhatsAppScheduledPage"));
import LoginPage from "./pages/LoginPage";
const ResetPasswordPage = lazy(() => import("./pages/ResetPasswordPage"));
const PublicServiceOrderView = lazy(() => import("./pages/PublicServiceOrderView"));
const ClientPortal = lazy(() => import("./pages/ClientPortal"));
const ActiveProspectingPage = lazy(() => import("./pages/ActiveProspectingPage"));
const ProspectingPage = lazy(() => import("./pages/ProspectingPage"));
const ImportFiscalXML = lazy(() => import("./pages/ImportFiscalXML"));
const FiscalEmission = lazy(() => import("./pages/FiscalEmission"));
const CommissionsPage = lazy(() => import("./pages/CommissionsPage"));
const SmartPurchasePage = lazy(() => import("./pages/SmartPurchasePage"));
const DesignPreviewV2 = lazy(() => import("./pages/DesignPreviewV2"));
const OrdersListV2 = lazy(() => import("./v2/pages/OrdersListV2"));
const DashboardV2 = lazy(() => import("./v2/pages/DashboardV2"));
const ReceivablesV2 = lazy(() => import("./v2/pages/ReceivablesV2"));
const FinancialV2 = lazy(() => import("./v2/pages/FinancialV2"));
const CollectionsV2 = lazy(() => import("./v2/pages/CollectionsV2"));
const CommissionsV2 = lazy(() => import("./v2/pages/CommissionsV2"));
const AuditLogV2 = lazy(() => import("./v2/pages/AuditLogV2"));
const ReportsV2 = lazy(() => import("./v2/pages/ReportsV2"));
const SmartPurchaseV2 = lazy(() => import("./v2/pages/SmartPurchaseV2"));
const InventoryV2 = lazy(() => import("./v2/pages/InventoryV2"));
const PurchaseOrdersV2 = lazy(() => import("./v2/pages/PurchaseOrdersV2"));
const ClientDetailV2 = lazy(() => import("./v2/pages/ClientDetailV2"));
const CRMKanbanV2 = lazy(() => import("./v2/pages/CRMKanbanV2"));
import {
  VesselDetailV2, ServiceOrderDetailV2, FiscalEmissionV2, SettingsV2, ImportFiscalXMLV2,
  WhatsAppLeadsV2, WhatsAppLogsV2, WhatsAppScheduledV2, WhatsAppStatusV2,
  ActiveProspectingV2, ExternalQuoteListV2, ExternalQuoteNewV2, ExternalQuoteApprovalV2,
  ExternalSellerLeadsV2, ExternalProductCatalogV2, ExternalQuoteDetailV2,
} from "./v2/pages/wrapped";
const ClientsListV2 = lazy(() => import("./v2/pages/ClientsListV2"));
const VesselsListV2 = lazy(() => import("./v2/pages/VesselsListV2"));
const MarinasListV2 = lazy(() => import("./v2/pages/MarinasListV2"));
const ProductsListV2 = lazy(() => import("./v2/pages/ProductsListV2"));
const ServicesListV2 = lazy(() => import("./v2/pages/ServicesListV2"));
const SuppliersListV2 = lazy(() => import("./v2/pages/SuppliersListV2"));
const QuoteList = lazy(() => import("./pages/QuoteList"));
import NotFound from "./pages/NotFound";
const EncodingFixerPage = lazy(() => import("./pages/EncodingFixerPage"));
const CRMKanbanPage = lazy(() => import("./pages/CRMKanbanPage"));
const ExternalQuoteListPage = lazy(() => import("./pages/ExternalQuoteListPage"));
const ExternalQuoteNewPage = lazy(() => import("./pages/ExternalQuoteNewPage"));
const ExternalQuoteApprovalPage = lazy(() => import("./pages/ExternalQuoteApprovalPage"));
const ExternalQuoteDetailPage = lazy(() => import("./pages/ExternalQuoteDetailPage"));
const ExternalSellerLeadsPage = lazy(() => import("./pages/ExternalSellerLeadsPage"));
const ExternalProductCatalogPage = lazy(() => import("./pages/ExternalProductCatalogPage"));
const PurchaseOrdersPage = lazy(() => import("./pages/PurchaseOrdersPage"));
const PurchasingHubPage = lazy(() => import("./pages/PurchasingHubPage"));
const QuoteRequestsPage = lazy(() => import("./pages/QuoteRequestsPage"));
const QuoteRequestDetailPage = lazy(() => import("./pages/QuoteRequestDetailPage"));
const AIActivityPage = lazy(() => import("./pages/AIActivityPage"));

/**
 * Fallback do carregamento sob demanda: as páginas viram chunks separados, então
 * abrir a Agenda não baixa mais o ERP inteiro (fiscal, PDF, relatórios, telas v2…).
 * Barra fina no topo em vez de tela em branco — a troca costuma ser imperceptível.
 */
function RouteLoading() {
  return (
    <div
      role="status"
      aria-label="Carregando"
      className="fixed inset-x-0 top-0 z-50 h-0.5 overflow-hidden bg-primary/20"
    >
      <div className="h-full w-1/3 animate-[loading_1s_ease-in-out_infinite] bg-primary" />
      <style>{`@keyframes loading{0%{transform:translateX(-100%)}100%{transform:translateX(300%)}}
        @media (prefers-reduced-motion: reduce){[role="status"] > div{animation:none;width:100%}}`}</style>
    </div>
  );
}

/**
 * Rota `/financial` durante a transição para a v2.
 *
 * Redirecionar em vez de trocar o componente preserva o endereço na barra: quem chegou por
 * um link antigo vê que agora o Financeiro mora em outro lugar, em vez de ficar com uma
 * tela nova sob um endereço velho — e o próximo favorito já sai certo.
 */
function FinanceiroLegadoOuV2() {
  const [params] = useSearchParams();
  const location = useLocation();
  if (params.get('legacy') === '1') return <FinancialPage />;
  // Preserva a query (?tab=payables etc.) na travessia para a v2.
  return <Navigate to={'/v2/financial' + location.search} replace />;
}

/**
 * Redesign em todo o ERP (30/07/2026): generalização do padrão acima para
 * TODAS as telas com gêmea v2. Redireciona preservando :params e query string;
 * `?legacy=1` ainda abre a tela antiga — saída de emergência enquanto a
 * transição não termina (o código v1 permanece no repositório).
 */
function LegadoOuV2({ to, legacy }: { to: string; legacy: ReactNode }) {
  const params = useParams();
  const location = useLocation();
  if (new URLSearchParams(location.search).get('legacy') === '1') return <>{legacy}</>;
  let path = to;
  for (const [k, v] of Object.entries(params)) path = path.replace(`:${k}`, v ?? '');
  return <Navigate to={path + location.search} replace />;
}

const App = () => (
  <QueryClientProvider client={queryClient}>
    <I18nProvider>
      <TooltipProvider>
        <Toaster />
        <Sonner />
        <GlobalErrorBoundary>
          <BrowserRouter>
          <AuthProvider>
            <DiagnosticFallback />
            <Suspense fallback={<RouteLoading />}>
            <Routes>
              <Route path="/login" element={<LoginPage />} />
              <Route path="/portal" element={<ClientPortal />} />
              <Route path="/reset-password" element={<ResetPasswordPage />} />
              <Route path="/view/:token" element={<PublicServiceOrderView />} />
              {/* Preview isolado do kit v2 (Fase 0) — read-only, fora do AppLayout v1 */}
              <Route path="/design-preview" element={
                <ProtectedRoute roles={['admin', 'financial']}>
                  <DesignPreviewV2 />
                </ProtectedRoute>
              } />
              <Route path="/*" element={
                <ProtectedRoute>
                  <QueryGate>
                    <AppLayout>
                      <Routes>
                        <Route path="/" element={
                          <ProtectedRoute roles={['admin', 'financial', 'technician', 'seller']} groupId="operacional"><LegadoOuV2 to="/v2/dashboard" legacy={<Dashboard />} /></ProtectedRoute>
                        } />
                        <Route path="/crm" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><LegadoOuV2 to="/v2/crm" legacy={<CRMKanbanPage />} /></ProtectedRoute>} />
                        <Route path="/service-orders" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><LegadoOuV2 to="/v2/service-orders" legacy={<ServiceOrderList />} /></ProtectedRoute>} />
                        <Route path="/quotes" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><LegadoOuV2 to="/v2/quotes" legacy={<QuoteList />} /></ProtectedRoute>} />
                        {/* Fase 1 UI v2 — telas gêmeas em rota paralela; as v1 acima permanecem intactas */}
                        <Route path="/v2/service-orders" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><OrdersListV2 mode="orders" /></ProtectedRoute>} />
                        <Route path="/v2/quotes" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><OrdersListV2 mode="quotes" /></ProtectedRoute>} />
                        <Route path="/v2/dashboard" element={<ProtectedRoute roles={['admin','financial','technician','seller']}><DashboardV2 /></ProtectedRoute>} />
                        <Route path="/v2/receivables" element={<ProtectedRoute roles={['admin','financial']}><ReceivablesV2 /></ProtectedRoute>} />
                        <Route path="/v2/financial" element={<ProtectedRoute roles={['admin','financial']}><FinancialV2 /></ProtectedRoute>} />
                        <Route path="/v2/collections" element={<ProtectedRoute roles={['admin','financial']} groupId="operacional"><CollectionsV2 /></ProtectedRoute>} />
                        <Route path="/v2/commissions" element={<ProtectedRoute roles={['admin','financial']}><CommissionsV2 /></ProtectedRoute>} />
                        <Route path="/v2/audit-log" element={<ProtectedRoute roles={['admin']}><AuditLogV2 /></ProtectedRoute>} />
                        <Route path="/v2/reports" element={<ProtectedRoute roles={['admin','financial']}><ReportsV2 /></ProtectedRoute>} />
                        <Route path="/v2/inventory/smart-purchase" element={<ProtectedRoute roles={['admin','financial']}><SmartPurchaseV2 /></ProtectedRoute>} />
                        <Route path="/v2/inventory" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><InventoryV2 /></ProtectedRoute>} />
                        <Route path="/v2/purchase-orders" element={<ProtectedRoute roles={['admin','financial']} groupId="operacional"><PurchaseOrdersV2 /></ProtectedRoute>} />
                        <Route path="/v2/clients/:id" element={<ProtectedRoute roles={['admin','financial','technician','seller']}><ClientDetailV2 /></ProtectedRoute>} />
                        <Route path="/v2/vessels/:id" element={<ProtectedRoute roles={['admin','financial','technician','seller']}><VesselDetailV2 /></ProtectedRoute>} />
                        <Route path="/v2/crm" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><CRMKanbanV2 /></ProtectedRoute>} />
                        <Route path="/v2/service-orders/new" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><ServiceOrderDetailV2 /></ProtectedRoute>} />
                        <Route path="/v2/service-orders/:id" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><ServiceOrderDetailV2 /></ProtectedRoute>} />
                        <Route path="/v2/fiscal/emissao" element={<ProtectedRoute roles={['admin']}><FiscalEmissionV2 /></ProtectedRoute>} />
                        <Route path="/v2/inventory/import-xml" element={<ProtectedRoute roles={['admin']}><ImportFiscalXMLV2 /></ProtectedRoute>} />
                        <Route path="/v2/settings" element={<ProtectedRoute roles={['admin']}><SettingsV2 /></ProtectedRoute>} />
                        <Route path="/v2/whatsapp/leads" element={<ProtectedRoute roles={['admin','financial','seller']} groupId="whatsapp"><WhatsAppLeadsV2 /></ProtectedRoute>} />
                        <Route path="/v2/whatsapp/logs" element={<ProtectedRoute roles={['admin']} groupId="whatsapp"><WhatsAppLogsV2 /></ProtectedRoute>} />
                        <Route path="/v2/whatsapp/scheduled" element={<ProtectedRoute roles={['admin','financial']} groupId="whatsapp"><WhatsAppScheduledV2 /></ProtectedRoute>} />
                        <Route path="/v2/whatsapp/status" element={<ProtectedRoute roles={['admin','financial','seller']} groupId="whatsapp"><WhatsAppStatusV2 /></ProtectedRoute>} />
                        <Route path="/v2/prospecting" element={<ProtectedRoute roles={['admin']}><ActiveProspectingV2 /></ProtectedRoute>} />
                        <Route path="/v2/external-quotes" element={<ProtectedRoute><ExternalQuoteListV2 /></ProtectedRoute>} />
                        <Route path="/v2/external-quotes/new" element={<ProtectedRoute><ExternalQuoteNewV2 /></ProtectedRoute>} />
                        <Route path="/v2/external-quotes/approval" element={<ProtectedRoute roles={['admin','financial']}><ExternalQuoteApprovalV2 /></ProtectedRoute>} />
                        <Route path="/v2/external-quotes/leads" element={<ProtectedRoute><ExternalSellerLeadsV2 /></ProtectedRoute>} />
                        <Route path="/v2/external-quotes/catalog" element={<ProtectedRoute><ExternalProductCatalogV2 /></ProtectedRoute>} />
                        <Route path="/v2/external-quotes/:id" element={<ProtectedRoute><ExternalQuoteDetailV2 /></ProtectedRoute>} />
                        <Route path="/v2/clients" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><ClientsListV2 /></ProtectedRoute>} />
                        <Route path="/v2/vessels" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><VesselsListV2 /></ProtectedRoute>} />
                        <Route path="/v2/marinas" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><MarinasListV2 /></ProtectedRoute>} />
                        <Route path="/v2/products" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><ProductsListV2 /></ProtectedRoute>} />
                        <Route path="/v2/services" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><ServicesListV2 /></ProtectedRoute>} />
                        <Route path="/v2/suppliers" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><SuppliersListV2 /></ProtectedRoute>} />

                        <Route path="/purchase-orders" element={<ProtectedRoute roles={['admin','financial']} groupId="operacional"><LegadoOuV2 to="/v2/purchase-orders" legacy={<PurchaseOrdersPage />} /></ProtectedRoute>} />
                        <Route path="/service-orders/new" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><LegadoOuV2 to="/v2/service-orders/new" legacy={<ServiceOrderDetail />} /></ProtectedRoute>} />
                        <Route path="/service-orders/:id" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><LegadoOuV2 to="/v2/service-orders/:id" legacy={<ServiceOrderDetail />} /></ProtectedRoute>} />
                        <Route path="/clients" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><LegadoOuV2 to="/v2/clients" legacy={<ClientList />} /></ProtectedRoute>} />
                        <Route path="/clients/:id" element={<ProtectedRoute roles={['admin','financial','technician','seller']}><LegadoOuV2 to="/v2/clients/:id" legacy={<ClientDetail />} /></ProtectedRoute>} />
                        <Route path="/vessels" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><LegadoOuV2 to="/v2/vessels" legacy={<VesselList />} /></ProtectedRoute>} />
                        <Route path="/vessels/:id" element={<ProtectedRoute roles={['admin','financial','technician','seller']}><LegadoOuV2 to="/v2/vessels/:id" legacy={<VesselDetail />} /></ProtectedRoute>} />
                        <Route path="/marinas" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><LegadoOuV2 to="/v2/marinas" legacy={<MarinaList />} /></ProtectedRoute>} />
                        <Route path="/products" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><LegadoOuV2 to="/v2/products" legacy={<ProductList />} /></ProtectedRoute>} />
                        <Route path="/suppliers" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><LegadoOuV2 to="/v2/suppliers" legacy={<SupplierList />} /></ProtectedRoute>} />
                        <Route path="/services" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><LegadoOuV2 to="/v2/services" legacy={<ServiceList />} /></ProtectedRoute>} />
                        <Route path="/inventory" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><LegadoOuV2 to="/v2/inventory" legacy={<InventoryPage />} /></ProtectedRoute>} />
                        <Route path="/inventory/smart-purchase" element={<ProtectedRoute roles={['admin','financial']}><LegadoOuV2 to="/v2/inventory/smart-purchase" legacy={<SmartPurchasePage />} /></ProtectedRoute>} />
                        <Route path="/inventory/import-xml" element={<ProtectedRoute roles={['admin']}><LegadoOuV2 to="/v2/inventory/import-xml" legacy={<ImportFiscalXML />} /></ProtectedRoute>} />
                        <Route path="/fiscal/emissao" element={<ProtectedRoute roles={['admin']}><LegadoOuV2 to="/v2/fiscal/emissao" legacy={<FiscalEmission />} /></ProtectedRoute>} />
                        {/* Compras: telas NOVAS, então não existe versão antiga delas. As
                            rotas sem prefixo ficam como atalho e caem na v2 preservando :id
                            e query, pelo mesmo LegadoOuV2 do resto do ERP. */}
                        <Route path="/purchasing" element={<ProtectedRoute roles={['admin','financial']} groupId="operacional"><LegadoOuV2 to="/v2/purchasing" legacy={<PurchasingHubPage />} /></ProtectedRoute>} />
                        <Route path="/purchasing/quotes" element={<ProtectedRoute roles={['admin','financial']} groupId="operacional"><LegadoOuV2 to="/v2/purchasing/quotes" legacy={<QuoteRequestsPage />} /></ProtectedRoute>} />
                        <Route path="/purchasing/quotes/:id" element={<ProtectedRoute roles={['admin','financial']} groupId="operacional"><LegadoOuV2 to="/v2/purchasing/quotes/:id" legacy={<QuoteRequestDetailPage />} /></ProtectedRoute>} />
                        <Route path="/v2/purchasing" element={<ProtectedRoute roles={['admin','financial']} groupId="operacional"><PurchasingHubPage /></ProtectedRoute>} />
                        <Route path="/v2/purchasing/quotes" element={<ProtectedRoute roles={['admin','financial']} groupId="operacional"><QuoteRequestsPage /></ProtectedRoute>} />
                        <Route path="/v2/purchasing/quotes/:id" element={<ProtectedRoute roles={['admin','financial']} groupId="operacional"><QuoteRequestDetailPage /></ProtectedRoute>} />
                        <Route path="/agenda" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><AgendaPage /></ProtectedRoute>} />
                        <Route path="/day-board" element={<ProtectedRoute roles={['admin','financial','technician']} groupId="operacional"><DayBoardPage /></ProtectedRoute>} />
                        <Route path="/step-templates" element={<ProtectedRoute roles={['admin','financial','technician']} groupId="operacional"><StepTemplatesPage /></ProtectedRoute>} />
                        {/* Financeiro migrado para a v2 em 30/07/2026. Links antigos,
                            favoritos e telas que apontam para cá continuam funcionando —
                            caem na versão nova. `?legacy=1` ainda abre a antiga, que é a
                            saída de emergência enquanto a transição não termina. */}
                        <Route path="/financial" element={
                          <ProtectedRoute roles={['admin', 'financial']} groupId="financeiro">
                            <FinanceiroLegadoOuV2 />
                          </ProtectedRoute>
                        } />
                        <Route path="/collections" element={
                          <ProtectedRoute roles={['admin', 'financial']} groupId="operacional"><LegadoOuV2 to="/v2/collections" legacy={<CollectionsPage />} /></ProtectedRoute>
                        } />
                        <Route path="/commissions" element={
                          <ProtectedRoute roles={['admin', 'financial']} groupId="financeiro"><LegadoOuV2 to="/v2/commissions" legacy={<CommissionsPage />} /></ProtectedRoute>
                        } />
                        <Route path="/external-quotes" element={
                          <ProtectedRoute roles={['external_seller','admin','financial','seller']}><LegadoOuV2 to="/v2/external-quotes" legacy={<ExternalQuoteListPage />} /></ProtectedRoute>
                        } />
                        <Route path="/external-quotes/new" element={
                          <ProtectedRoute roles={['external_seller','admin','financial','seller']}><LegadoOuV2 to="/v2/external-quotes/new" legacy={<ExternalQuoteNewPage />} /></ProtectedRoute>
                        } />
                        <Route path="/external-quotes/approval" element={
                          <ProtectedRoute roles={['admin', 'financial']} groupId="vendas-externas"><LegadoOuV2 to="/v2/external-quotes/approval" legacy={<ExternalQuoteApprovalPage />} /></ProtectedRoute>
                        } />
                        <Route path="/external-quotes/leads" element={
                          <ProtectedRoute roles={['admin','financial']}><LegadoOuV2 to="/v2/external-quotes/leads" legacy={<ExternalSellerLeadsPage />} /></ProtectedRoute>
                        } />
                        <Route path="/external-quotes/catalog" element={
                          <ProtectedRoute roles={['external_seller','admin','financial','seller']}><LegadoOuV2 to="/v2/external-quotes/catalog" legacy={<ExternalProductCatalogPage />} /></ProtectedRoute>
                        } />
                        <Route path="/external-quotes/:id" element={
                          <ProtectedRoute roles={['external_seller','admin','financial','seller']}><LegadoOuV2 to="/v2/external-quotes/:id" legacy={<ExternalQuoteDetailPage />} /></ProtectedRoute>
                        } />
                        <Route path="/reports" element={<ProtectedRoute roles={['admin', 'financial']} groupId="financeiro"><LegadoOuV2 to="/v2/reports" legacy={<ReportsPage />} /></ProtectedRoute>} />
                        <Route path="/prospecting" element={
                          <ProtectedRoute roles={['admin']} groupId="operacional"><LegadoOuV2 to="/v2/prospecting" legacy={<ActiveProspectingPage />} /></ProtectedRoute>
                        } />
                        <Route path="/whatsapp/leads" element={<ProtectedRoute roles={['admin','financial','seller']} groupId="whatsapp"><LegadoOuV2 to="/v2/whatsapp/leads" legacy={<WhatsAppLeadsPage />} /></ProtectedRoute>} />
                        <Route path="/whatsapp/logs" element={
                          <ProtectedRoute roles={['admin']} groupId="whatsapp"><LegadoOuV2 to="/v2/whatsapp/logs" legacy={<WhatsAppLogsPage />} /></ProtectedRoute>
                        } />
                        <Route path="/whatsapp/scheduled" element={
                          <ProtectedRoute roles={['admin', 'financial']} groupId="whatsapp"><LegadoOuV2 to="/v2/whatsapp/scheduled" legacy={<WhatsAppScheduledPage />} /></ProtectedRoute>
                        } />
                        <Route path="/whatsapp/status" element={
                          <ProtectedRoute roles={['admin', 'financial', 'seller']} groupId="whatsapp"><LegadoOuV2 to="/v2/whatsapp/status" legacy={<WhatsAppStatusPage />} /></ProtectedRoute>
                        } />
                        <Route path="/audit-log" element={
                          <ProtectedRoute roles={['admin']} groupId="sistema"><LegadoOuV2 to="/v2/audit-log" legacy={<AuditLogPage />} /></ProtectedRoute>
                        } />
                        <Route path="/ai-activity" element={
                          <ProtectedRoute roles={['admin']} groupId="sistema">
                            <AIActivityPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/settings" element={
                          <ProtectedRoute roles={['admin']} groupId="sistema"><LegadoOuV2 to="/v2/settings" legacy={<SettingsPage />} /></ProtectedRoute>
                        } />
                        <Route path="/tools/encoding-fixer" element={
                          <ProtectedRoute roles={['admin']} groupId="sistema">
                            <EncodingFixerPage />
                          </ProtectedRoute>
                        } />
                        <Route path="*" element={<NotFound />} />
                      </Routes>
                    </AppLayout>
                  </QueryGate>
                </ProtectedRoute>
              } />
            </Routes>
            </Suspense>
          </AuthProvider>
        </BrowserRouter>
      </GlobalErrorBoundary>
    </TooltipProvider>
    </I18nProvider>
  </QueryClientProvider>
);

export default App;
