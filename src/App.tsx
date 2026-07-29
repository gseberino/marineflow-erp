import { lazy, Suspense } from "react";
import { QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Route, Routes } from "react-router-dom";
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
                          <ProtectedRoute roles={['admin', 'financial', 'technician', 'seller']} groupId="operacional">
                            <Dashboard />
                          </ProtectedRoute>
                        } />
                        <Route path="/crm" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><CRMKanbanPage /></ProtectedRoute>} />
                        <Route path="/service-orders" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><ServiceOrderList /></ProtectedRoute>} />
                        <Route path="/quotes" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><QuoteList /></ProtectedRoute>} />
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
                        <Route path="/v2/inventory" element={<ProtectedRoute roles={['admin','financial']}><InventoryV2 /></ProtectedRoute>} />
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
                        <Route path="/purchase-orders" element={<ProtectedRoute roles={['admin','financial']} groupId="operacional"><PurchaseOrdersPage /></ProtectedRoute>} />
                        <Route path="/service-orders/new" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><ServiceOrderDetail /></ProtectedRoute>} />
                        <Route path="/service-orders/:id" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><ServiceOrderDetail /></ProtectedRoute>} />
                        <Route path="/clients" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><ClientList /></ProtectedRoute>} />
                        <Route path="/clients/:id" element={<ProtectedRoute roles={['admin','financial','technician','seller']}><ClientDetail /></ProtectedRoute>} />
                        <Route path="/vessels" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><VesselList /></ProtectedRoute>} />
                        <Route path="/vessels/:id" element={<ProtectedRoute roles={['admin','financial','technician','seller']}><VesselDetail /></ProtectedRoute>} />
                        <Route path="/marinas" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><MarinaList /></ProtectedRoute>} />
                        <Route path="/products" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><ProductList /></ProtectedRoute>} />
                        <Route path="/suppliers" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><SupplierList /></ProtectedRoute>} />
                        <Route path="/services" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><ServiceList /></ProtectedRoute>} />
                        <Route path="/inventory" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="cadastros"><InventoryPage /></ProtectedRoute>} />
                        <Route path="/inventory/smart-purchase" element={<ProtectedRoute roles={['admin','financial']}><SmartPurchasePage /></ProtectedRoute>} />
                        <Route path="/inventory/import-xml" element={<ProtectedRoute roles={['admin']}><ImportFiscalXML /></ProtectedRoute>} />
                        <Route path="/fiscal/emissao" element={<ProtectedRoute roles={['admin']}><FiscalEmission /></ProtectedRoute>} />
                        <Route path="/agenda" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><AgendaPage /></ProtectedRoute>} />
                        <Route path="/day-board" element={<ProtectedRoute roles={['admin','financial','technician']} groupId="operacional"><DayBoardPage /></ProtectedRoute>} />
                        <Route path="/financial" element={
                          <ProtectedRoute roles={['admin', 'financial']} groupId="financeiro">
                            <FinancialPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/collections" element={
                          <ProtectedRoute roles={['admin', 'financial']} groupId="operacional">
                            <CollectionsPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/commissions" element={
                          <ProtectedRoute roles={['admin', 'financial']} groupId="financeiro">
                            <CommissionsPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/external-quotes" element={
                          <ProtectedRoute roles={['external_seller','admin','financial','seller']}>
                            <ExternalQuoteListPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/external-quotes/new" element={
                          <ProtectedRoute roles={['external_seller','admin','financial','seller']}>
                            <ExternalQuoteNewPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/external-quotes/approval" element={
                          <ProtectedRoute roles={['admin', 'financial']} groupId="vendas-externas">
                            <ExternalQuoteApprovalPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/external-quotes/leads" element={
                          <ProtectedRoute roles={['admin','financial']}>
                            <ExternalSellerLeadsPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/external-quotes/catalog" element={
                          <ProtectedRoute roles={['external_seller','admin','financial','seller']}>
                            <ExternalProductCatalogPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/external-quotes/:id" element={
                          <ProtectedRoute roles={['external_seller','admin','financial','seller']}>
                            <ExternalQuoteDetailPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/reports" element={<ProtectedRoute roles={['admin', 'financial']} groupId="financeiro"><ReportsPage /></ProtectedRoute>} />
                        <Route path="/prospecting" element={
                          <ProtectedRoute roles={['admin']} groupId="operacional">
                            <ActiveProspectingPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/whatsapp/leads" element={<ProtectedRoute roles={['admin','financial','seller']} groupId="whatsapp"><WhatsAppLeadsPage /></ProtectedRoute>} />
                        <Route path="/whatsapp/logs" element={
                          <ProtectedRoute roles={['admin']} groupId="whatsapp">
                            <WhatsAppLogsPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/whatsapp/scheduled" element={
                          <ProtectedRoute roles={['admin', 'financial']} groupId="whatsapp">
                            <WhatsAppScheduledPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/whatsapp/status" element={
                          <ProtectedRoute roles={['admin', 'financial', 'seller']} groupId="whatsapp">
                            <WhatsAppStatusPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/audit-log" element={
                          <ProtectedRoute roles={['admin']} groupId="sistema">
                            <AuditLogPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/ai-activity" element={
                          <ProtectedRoute roles={['admin']} groupId="sistema">
                            <AIActivityPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/settings" element={
                          <ProtectedRoute roles={['admin']} groupId="sistema">
                            <SettingsPage />
                          </ProtectedRoute>
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
