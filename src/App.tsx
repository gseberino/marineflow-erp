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
import Dashboard from "./pages/Dashboard";
import ServiceOrderList from "./pages/ServiceOrderList";
import ServiceOrderDetail from "./pages/ServiceOrderDetail";
import ClientList from "./pages/ClientList";
import ClientDetail from "./pages/ClientDetail";
import VesselList from "./pages/VesselList";
import VesselDetail from "./pages/VesselDetail";
import MarinaList from "./pages/MarinaList";
import ProductList from "./pages/ProductList";
import InventoryPage from "./pages/InventoryPage";
import AgendaPage from "./pages/AgendaPage";
import FinancialPage from "./pages/FinancialPage";
import ReportsPage from "./pages/ReportsPage";
import CollectionsPage from "./pages/CollectionsPage";
import SettingsPage from "./pages/SettingsPage";
import SupplierList from "./pages/SupplierList";
import ServiceList from "./pages/ServiceList";
import AuditLogPage from "./pages/AuditLogPage";
import WhatsAppLeadsPage from "./pages/WhatsAppLeadsPage";
import WhatsAppLogsPage from "./pages/WhatsAppLogsPage";
import WhatsAppStatusPage from "./pages/WhatsAppStatusPage";
import WhatsAppScheduledPage from "./pages/WhatsAppScheduledPage";
import LoginPage from "./pages/LoginPage";
import ResetPasswordPage from "./pages/ResetPasswordPage";
import PublicServiceOrderView from "./pages/PublicServiceOrderView";
import ClientPortal from "./pages/ClientPortal";
import ActiveProspectingPage from "./pages/ActiveProspectingPage";
import ProspectingPage from "./pages/ProspectingPage";
import ImportFiscalXML from "./pages/ImportFiscalXML";
import CommissionsPage from "./pages/CommissionsPage";
import SmartPurchasePage from "./pages/SmartPurchasePage";
import QuoteList from "./pages/QuoteList";
import NotFound from "./pages/NotFound";
import EncodingFixerPage from "./pages/EncodingFixerPage";
import CRMKanbanPage from "./pages/CRMKanbanPage";
import ExternalQuoteListPage from "./pages/ExternalQuoteListPage";
import ExternalQuoteNewPage from "./pages/ExternalQuoteNewPage";
import ExternalQuoteApprovalPage from "./pages/ExternalQuoteApprovalPage";
import ExternalQuoteDetailPage from "./pages/ExternalQuoteDetailPage";
import ExternalSellerLeadsPage from "./pages/ExternalSellerLeadsPage";
import ExternalProductCatalogPage from "./pages/ExternalProductCatalogPage";
import PurchaseOrdersPage from "./pages/PurchaseOrdersPage";
import AIActivityPage from "./pages/AIActivityPage";

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
            <Routes>
              <Route path="/login" element={<LoginPage />} />
              <Route path="/portal" element={<ClientPortal />} />
              <Route path="/reset-password" element={<ResetPasswordPage />} />
              <Route path="/view/:token" element={<PublicServiceOrderView />} />
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
                        <Route path="/agenda" element={<ProtectedRoute roles={['admin','financial','technician','seller']} groupId="operacional"><AgendaPage /></ProtectedRoute>} />
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
                        <Route path="/inventory/import-xml" element={
                          <ProtectedRoute roles={['admin']}>
                            <ImportFiscalXML />
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
          </AuthProvider>
        </BrowserRouter>
      </GlobalErrorBoundary>
    </TooltipProvider>
    </I18nProvider>
  </QueryClientProvider>
);

export default App;
