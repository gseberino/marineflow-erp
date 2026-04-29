import { ReactNode, useState, useEffect } from 'react';
import { cn } from '@/lib/utils';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { useAuth } from '@/hooks/use-auth';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import {
  LayoutDashboard, Users, Ship, Anchor, Package, ClipboardList,
  DollarSign, BarChart3, Settings, ChevronLeft, ChevronRight, Menu,
  Warehouse, Building2, Wrench, History, LogOut, CalendarDays, MessageCircle, CreditCard,
  Database, ChevronDown, Rocket, ShoppingCart, FileDown, Target
} from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { NotificationBell } from '@/components/NotificationBell';
import { WhatsAppBell } from '@/components/WhatsAppBell';
import { PWAInstallPrompt } from '@/components/PWAInstallPrompt';
import { AIAgentWidget } from '@/components/ai/AIAgentWidget';
import { OfflineIndicator } from '@/components/OfflineIndicator';
import { DiagnosticExportButton } from '@/components/DiagnosticExportButton';

type NavItem = {
  label: string;
  icon: typeof LayoutDashboard;
  path: string;
  roles?: string[];
};

type NavGroup = {
  id: string;
  label: string;
  icon: typeof LayoutDashboard;
  roles?: string[];
  items: NavItem[];
};

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

  const { data: logoSetting } = useQuery({
    queryKey: ['company-logo'],
    queryFn: async () => {
      const { data } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'company_logo_url')
        .maybeSingle();
      return data?.value || null;
    },
    staleTime: 5 * 60 * 1000,
  });

  const isActive = (path: string) => {
    if (path === '/') return location.pathname === '/';
    return location.pathname.startsWith(path);
  };

  const groups: NavGroup[] = [
    {
      id: 'operacional',
      label: 'Operacional',
      icon: Wrench,
      items: [
        { label: 'CRM & Funil', icon: Target, path: '/crm' },
        { label: 'Ordens de Serviço', icon: ClipboardList, path: '/service-orders' },
        { label: 'Agenda', icon: CalendarDays, path: '/agenda' },
        { label: 'Motor de Vendas', icon: Rocket, path: '/prospecting', roles: ['admin'] },
        { label: 'Cobranças', icon: CreditCard, path: '/collections', roles: ['admin', 'financial'] },
      ],
    },
    {
      id: 'cadastros',
      label: 'Cadastros',
      icon: Database,
      items: [
        { label: 'Clientes', icon: Users, path: '/clients' },
        { label: 'Embarcações', icon: Ship, path: '/vessels' },
        { label: 'Marinas', icon: Anchor, path: '/marinas' },
        { label: 'Produtos', icon: Package, path: '/products' },
        { label: 'Serviços', icon: Wrench, path: '/services' },
        { label: 'Assistente de Compras', icon: ShoppingCart, path: '/inventory/smart-purchase', roles: ['admin', 'financial'] },
        { label: 'Fornecedores', icon: Building2, path: '/suppliers' },
        { label: 'Importar XML', icon: FileDown, path: '/inventory/import-xml', roles: ['admin'] },
      ],
    },
    {
      id: 'financeiro',
      label: 'Financeiro',
      icon: DollarSign,
      items: [
        { label: 'Financeiro', icon: DollarSign, path: '/financial', roles: ['admin', 'financial'] },
        { label: 'Comissões', icon: Users, path: '/commissions', roles: ['admin', 'financial'] },
        { label: 'Relatórios', icon: BarChart3, path: '/reports', roles: ['admin', 'financial'] },
      ],
    },
    {
      id: 'whatsapp',
      label: 'WhatsApp',
      icon: MessageCircle,
      items: [
        { label: 'Leads / Inbox', icon: MessageCircle, path: '/whatsapp/leads' },
        { label: 'Logs', icon: History, path: '/whatsapp/logs', roles: ['admin'] },
      ],
    },
    {
      id: 'sistema',
      label: 'Sistema',
      icon: Settings,
      roles: ['admin'],
      items: [
        { label: 'Configurações', icon: Settings, path: '/settings' },
        { label: 'Log de Auditoria', icon: History, path: '/audit-log' },
      ],
    },
  ];

  // Filter items based on roles
  const visibleGroups = groups
    .filter((g) => !g.roles || (user && g.roles.includes(user.role)))
    .map((g) => ({
      ...g,
      items: g.items.filter((i) => !i.roles || (user && i.roles.includes(user.role))),
    }))
    .filter((g) => g.items.length > 0);

  // Track open/closed state per group. Default: only "operacional" open.
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>(() => ({
    operacional: true,
  }));

  // Auto-expand the group that contains the active route
  useEffect(() => {
    const activeGroup = visibleGroups.find((g) => g.items.some((i) => isActive(i.path)));
    if (activeGroup) {
      setOpenGroups((prev) => (prev[activeGroup.id] ? prev : { ...prev, [activeGroup.id]: true }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.pathname]);

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

  const toggleGroup = (id: string) => setOpenGroups((p) => ({ ...p, [id]: !p[id] }));

  const renderNavItem = (item: NavItem, indent = true) => (
    <Link
      key={item.path}
      to={item.path}
      onClick={() => setMobileOpen(false)}
      className={cn(
        'flex items-center gap-3 rounded-lg py-2 text-sm font-medium transition-colors',
        indent && !collapsed ? 'pl-9 pr-3' : 'px-3',
        isActive(item.path)
          ? 'bg-sidebar-primary/15 text-sidebar-primary'
          : 'text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground'
      )}
      title={collapsed ? item.label : undefined}
    >
      <item.icon className="h-4 w-4 shrink-0" />
      {!collapsed && <span>{item.label}</span>}
    </Link>
  );

  const sidebarContent = (
    <div className="flex h-full flex-col">
      <div className="flex h-14 items-center gap-2 px-4 border-b border-sidebar-border">
        <Link to="/" className="flex h-8 w-8 items-center justify-center rounded-lg bg-sidebar-primary shrink-0">
          <Anchor className="h-4 w-4 text-sidebar-primary-foreground" />
        </Link>
        {!collapsed && (
          <Link to="/" className="flex flex-col">
            {logoSetting ? (
              <img src={logoSetting} alt="Logo" className="h-10 w-auto max-w-[140px] object-contain" />
            ) : (
              <>
                <span className="text-sm font-bold text-sidebar-accent-foreground">MarineFlow</span>
                <span className="text-[10px] text-sidebar-foreground">Marine ERP</span>
              </>
            )}
          </Link>
        )}
      </div>

      <nav className="flex-1 space-y-1 p-2 overflow-y-auto scrollbar-thin">
        {/* Dashboard always visible at top */}
        <Link
          to="/"
          onClick={() => setMobileOpen(false)}
          className={cn(
            'flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
            isActive('/')
              ? 'bg-sidebar-primary/15 text-sidebar-primary'
              : 'text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground'
          )}
          title={collapsed ? t.nav.dashboard : undefined}
        >
          <LayoutDashboard className="h-4 w-4 shrink-0" />
          {!collapsed && <span>{t.nav.dashboard}</span>}
        </Link>

        {visibleGroups.map((group) => {
          const groupHasActive = group.items.some((i) => isActive(i.path));
          const isOpen = openGroups[group.id] ?? false;

          if (collapsed) {
            // In collapsed mode, render items flat (icon-only) so navigation still works
            return (
              <div key={group.id} className="pt-1">
                {group.items.map((item) => renderNavItem(item, false))}
              </div>
            );
          }

          return (
            <Collapsible key={group.id} open={isOpen} onOpenChange={() => toggleGroup(group.id)}>
              <CollapsibleTrigger
                className={cn(
                  'flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-semibold transition-colors',
                  groupHasActive
                    ? 'text-sidebar-primary'
                    : 'text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground'
                )}
              >
                <group.icon className="h-4 w-4 shrink-0" />
                <span className="flex-1 text-left">{group.label}</span>
                <ChevronDown
                  className={cn(
                    'h-4 w-4 shrink-0 transition-transform',
                    isOpen ? 'rotate-0' : '-rotate-90'
                  )}
                />
              </CollapsibleTrigger>
              <CollapsibleContent className="space-y-0.5 pt-0.5">
                {group.items.map((item) => renderNavItem(item))}
              </CollapsibleContent>
            </Collapsible>
          );
        })}
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
            <WhatsAppBell />
            <NotificationBell />
            <div className="text-right hidden sm:block">
              <p className="text-sm font-medium leading-none truncate max-w-[120px]">
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
      <AIAgentWidget />
    </div>
  );
}
