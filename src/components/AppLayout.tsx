import { ReactNode, useState } from 'react';
import { cn } from '@/lib/utils';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { useAuth } from '@/hooks/use-auth';
import {
  LayoutDashboard, Users, Ship, Anchor, Package, ClipboardList,
  DollarSign, BarChart3, Settings, ChevronLeft, ChevronRight, Menu,
  Warehouse, Building2, Wrench, History, LogOut, CalendarDays, MessageCircle
} from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { NotificationBell } from '@/components/NotificationBell';
import { PWAInstallPrompt } from '@/components/PWAInstallPrompt';
import { OfflineIndicator } from '@/components/OfflineIndicator';
import { DiagnosticExportButton } from '@/components/DiagnosticExportButton';

const navKeys = [
  { key: 'dashboard' as const, icon: LayoutDashboard, path: '/' },
  { key: 'serviceOrders' as const, icon: ClipboardList, path: '/service-orders' },
  { key: 'agenda' as const, icon: CalendarDays, path: '/agenda' },
  { key: 'clients' as const, icon: Users, path: '/clients' },
  { key: 'vessels' as const, icon: Ship, path: '/vessels' },
  { key: 'marinas' as const, icon: Anchor, path: '/marinas' },
  { key: 'products' as const, icon: Package, path: '/products' },
  { key: 'suppliers' as const, icon: Building2, path: '/suppliers' },
  { key: 'services' as const, icon: Wrench, path: '/services' },
  { key: 'inventory' as const, icon: Warehouse, path: '/inventory' },
  { key: 'financial' as const, icon: DollarSign, path: '/financial' },
  { key: 'reports' as const, icon: BarChart3, path: '/reports' },
  { key: 'auditLog' as const, icon: History, path: '/audit-log' },
  { key: 'settings' as const, icon: Settings, path: '/settings' },
];

const extraNav = [
  { label: 'WhatsApp Leads', icon: MessageCircle, path: '/whatsapp/leads' },
];

const roleLabels: Record<string, string> = {
  admin: 'Administrador',
  technician: 'Técnico',
  financial: 'Financeiro',
  seller: 'Vendedor',
  other: 'Usuário',
};

export function AppLayout({ children }: { children: ReactNode }) {
  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();
  const { t } = useI18n();
  const { user, signOut } = useAuth();

  const isActive = (path: string) => {
    if (path === '/') return location.pathname === '/';
    return location.pathname.startsWith(path);
  };

  const visibleNavKeys = navKeys.filter(item => {
    if (!user) return true;
    if (item.path === '/financial') {
      return ['admin', 'financial'].includes(user.role);
    }
    if (item.path === '/audit-log') {
      return user.role === 'admin';
    }
    if (item.path === '/settings') {
      return ['admin', 'seller', 'financial', 'other'].includes(user.role)
        || !user.role;
    }
    return true;
  });

  const initials = user?.full_name
    ?.split(' ')
    .map(n => n[0])
    .slice(0, 2)
    .join('')
    .toUpperCase() || '?';

  const handleSignOut = async () => {
    await signOut();
    navigate('/login');
  };

  const sidebarContent = (
    <div className="flex h-full flex-col">
      <div className="flex h-14 items-center gap-2 px-4 border-b border-sidebar-border">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-sidebar-primary">
          <Anchor className="h-4 w-4 text-sidebar-primary-foreground" />
        </div>
        {!collapsed && (
          <div className="flex flex-col">
            <span className="text-sm font-bold text-sidebar-accent-foreground">MarineFlow</span>
            <span className="text-[10px] text-sidebar-foreground">Marine ERP</span>
          </div>
        )}
      </div>

      <nav className="flex-1 space-y-1 p-2 overflow-y-auto scrollbar-thin">
        {visibleNavKeys.map((item) => (
          <Link
            key={item.path}
            to={item.path}
            onClick={() => setMobileOpen(false)}
            className={cn(
              'flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
              isActive(item.path)
                ? 'bg-sidebar-primary/15 text-sidebar-primary'
                : 'text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground'
            )}
          >
            <item.icon className="h-4 w-4 shrink-0" />
            {!collapsed && <span>{t.nav[item.key]}</span>}
          </Link>
        ))}
        {extraNav.map((item) => (
          <Link
            key={item.path}
            to={item.path}
            onClick={() => setMobileOpen(false)}
            className={cn(
              'flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
              isActive(item.path)
                ? 'bg-sidebar-primary/15 text-sidebar-primary'
                : 'text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground'
            )}
          >
            <item.icon className="h-4 w-4 shrink-0" />
            {!collapsed && <span>{item.label}</span>}
          </Link>
        ))}
      </nav>

      <div className="hidden lg:flex border-t border-sidebar-border p-2">
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="flex w-full items-center justify-center rounded-lg py-2 text-sidebar-foreground hover:bg-sidebar-accent transition-colors"
        >
          {collapsed ? <ChevronRight className="h-4 w-4" /> : <ChevronLeft className="h-4 w-4" />}
        </button>
      </div>
    </div>
  );

  return (
    <div className="flex h-screen w-full overflow-hidden bg-background">
      <aside
        className={cn(
          'hidden lg:flex flex-col bg-sidebar border-r border-sidebar-border transition-all duration-200 shrink-0',
          collapsed ? 'w-16' : 'w-60'
        )}
      >
        {sidebarContent}
      </aside>

      {mobileOpen && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <div className="absolute inset-0 bg-foreground/50" onClick={() => setMobileOpen(false)} />
          <aside className="absolute left-0 top-0 h-full w-64 bg-sidebar shadow-xl animate-slide-in-right">
            {sidebarContent}
          </aside>
        </div>
      )}

      <div className="flex flex-1 flex-col overflow-hidden">
        <OfflineIndicator />
        <header className="flex h-14 items-center gap-4 border-b px-4 lg:px-6 shrink-0">
          <button
            onClick={() => setMobileOpen(true)}
            className="lg:hidden rounded-lg p-1.5 hover:bg-muted transition-colors"
          >
            <Menu className="h-5 w-5" />
          </button>
          <div className="flex-1" />
          <div className="flex items-center gap-3">
            <DiagnosticExportButton />
            <NotificationBell />
            <div className="text-right hidden sm:block">
              <p className="text-sm font-medium leading-none">
                {user?.full_name || 'Usuário'}
              </p>
              <p className="text-xs text-muted-foreground mt-0.5">
                {roleLabels[user?.role || ''] || ''}
              </p>
            </div>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button
                  className="flex h-8 w-8 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs font-bold shrink-0 hover:opacity-80 transition-opacity cursor-pointer"
                >
                  {initials}
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-48">
                <DropdownMenuLabel className="font-normal">
                  <div className="flex flex-col space-y-1">
                    <p className="text-sm font-medium">{user?.full_name}</p>
                    <p className="text-xs text-muted-foreground">{user?.email}</p>
                  </div>
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  onClick={handleSignOut}
                  className="text-destructive focus:text-destructive cursor-pointer"
                >
                  <LogOut className="mr-2 h-4 w-4" />
                  Sair
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </header>

        <main className="flex-1 overflow-auto p-4 lg:p-6">
          {children}
        </main>
      </div>
      <PWAInstallPrompt />
    </div>
  );
}
