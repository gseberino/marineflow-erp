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
import SettingsPage from "./pages/SettingsPage";
import SupplierList from "./pages/SupplierList";
import ServiceList from "./pages/ServiceList";
import AuditLogPage from "./pages/AuditLogPage";
import WhatsAppLeadsPage from "./pages/WhatsAppLeadsPage";
import LoginPage from "./pages/LoginPage";
import ResetPasswordPage from "./pages/ResetPasswordPage";
import PublicServiceOrderView from "./pages/PublicServiceOrderView";
import NotFound from "./pages/NotFound";

const App = () => (
  <QueryClientProvider client={queryClient}>
    <I18nProvider>
      <TooltipProvider>
        <Toaster />
        <Sonner />
        <BrowserRouter>
          <AuthProvider>
            <DiagnosticFallback />
            <Routes>
              <Route path="/login" element={<LoginPage />} />
              <Route path="/reset-password" element={<ResetPasswordPage />} />
              <Route path="/view/:token" element={<PublicServiceOrderView />} />
              <Route path="/*" element={
                <ProtectedRoute>
                  <QueryGate>
                    <AppLayout>
                      <Routes>
                        <Route path="/" element={<Dashboard />} />
                        <Route path="/service-orders" element={<ServiceOrderList />} />
                        <Route path="/service-orders/new" element={<ServiceOrderDetail />} />
                        <Route path="/service-orders/:id" element={<ServiceOrderDetail />} />
                        <Route path="/clients" element={<ClientList />} />
                        <Route path="/clients/:id" element={<ClientDetail />} />
                        <Route path="/vessels" element={<VesselList />} />
                        <Route path="/vessels/:id" element={<VesselDetail />} />
                        <Route path="/marinas" element={<MarinaList />} />
                        <Route path="/products" element={<ProductList />} />
                        <Route path="/suppliers" element={<SupplierList />} />
                        <Route path="/services" element={<ServiceList />} />
                        <Route path="/inventory" element={<InventoryPage />} />
                        <Route path="/agenda" element={<AgendaPage />} />
                        <Route path="/financial" element={
                          <ProtectedRoute roles={['admin', 'financial']}>
                            <FinancialPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/reports" element={<ReportsPage />} />
                        <Route path="/whatsapp/leads" element={<WhatsAppLeadsPage />} />
                        <Route path="/audit-log" element={
                          <ProtectedRoute roles={['admin']}>
                            <AuditLogPage />
                          </ProtectedRoute>
                        } />
                        <Route path="/settings" element={
                          <ProtectedRoute roles={['admin']}>
                            <SettingsPage />
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
      </TooltipProvider>
    </I18nProvider>
  </QueryClientProvider>
);

export default App;
