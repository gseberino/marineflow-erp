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
  Database, ChevronDown, Rocket, ShoppingCart, FileDown, Target, CheckCircle2, Bell, CalendarClock, Truck, Camera, FileText
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
import { Badge } from '@/components/ui/badge';
import { NotificationBell } from '@/components/NotificationBell';
import { WhatsAppBell } from '@/components/WhatsAppBell';
import { PWAInstallPrompt } from '@/components/PWAInstallPrompt';
import { AIAgentWidget } from '@/components/ai/AIAgentWidget';
import { OfflineIndicator } from '@/components/OfflineIndicator';
import { DiagnosticExportButton } from '@/components/DiagnosticExportButton';
import { Button } from '@/components/ui/button';
import { usePushNotifications, requestPushPermission } from '@/hooks/use-push-notifications';
import { toast } from 'sonner';

// ── HBR Systems brand mark (inline SVG) ──────────────────────────────────────
function HbrMark({ size = 32 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
      <rect width="32" height="32" rx="7" fill="#C8A063" fillOpacity="0.15" />
      <text x="5" y="22" fontSize="17" fontWeight="900" fill="#C8A063" fontFamily="system-ui, sans-serif" letterSpacing="-0.5">H</text>
      <path d="M3 26 C8 21 13 27 19 24 C23 22 27 23 30 21" stroke="#C8A063" strokeWidth="1.8" fill="none" strokeLinecap="round"/>
      <path d="M3 28 C9 23 15 29 21 26 C25 24 28 25 31 24" stroke="#7FA0B8" strokeWidth="1.2" fill="none" strokeLinecap="round" opacity="0.65"/>
    </svg>
  );
}

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
  external_seller: 'Vendedor Externo',
  other: 'Usuário',
};

export function AppLayout({ children }: { children: ReactNode }) {
  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();
  const { t } = useI18n();
  const { user, signOut } = useAuth();
  usePushNotifications();

  const [showPushBanner, setShowPushBanner] = useState(false);

  useEffect(() => {
    if (!user) return;
    if (localStorage.getItem('push_banner_dismissed') === '1') return;
    if (localStorage.getItem('push_registered') === '1') return;
    if (!('PushManager' in window)) return;
    const isMobile = window.innerWidth < 640;
    if (!isMobile) return;
    supabase
      .from('push_subscriptions')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle()
      .then(({ data }) => {
        if (!data) setShowPushBanner(true);
      });
  }, [user?.id]);

  const handleEnablePush = async () => {
    if (!user) return;
    const ok = await requestPushPermission(user.id);
    if (ok) {
      localStorage.setItem('push_registered', '1');
      setShowPushBanner(false);
      toast.success('Notificações ativadas!');
    } else {
      toast.error('Permissão negada. Ative nas configurações do iPhone em Safari → MarineFlow.');
    }
  };

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



  const groups: NavGroup[] = [
    {
      id: 'operacional',
      label: 'Operacional',
      icon: Wrench,
      roles: ['admin', 'financial', 'technician', 'seller'],
      items: [
        { label: 'CRM & Funil', icon: Target, path: '/crm' },
        { label: 'Ordens de Serviço', icon: ClipboardList, path: '/service-orders' },
        { label: 'Orçamentos', icon: FileText, path: '/quotes' },
        { label: 'Ordens de Compra', icon: Truck, path: '/purchase-orders', roles: ['admin', 'financial'] },
        { label: 'Agenda', icon: CalendarDays, path: '/agenda' },
        { label: 'Motor de Vendas', icon: Rocket, path: '/prospecting', roles: ['admin'] },
        { label: 'Cobranças', icon: CreditCard, path: '/collections', roles: ['admin', 'financial'] },
      ],
    },
    {
      id: 'vendas-externas',
      label: 'Vendas Externas',
      icon: ShoppingCart,
      items: [
        { label: 'Meus Orçamentos', icon: ClipboardList, path: '/external-quotes' },
        { label: 'Meus Prospectos', icon: Users, path: '/external-quotes/leads', roles: ['external_seller', 'seller', 'admin'] },
        { label: 'Catálogo de Produtos', icon: Package, path: '/external-quotes/catalog', roles: ['external_seller', 'seller', 'admin'] },
        { label: 'Aprovar Orçamentos', icon: CheckCircle2, path: '/external-quotes/approval', roles: ['admin', 'financial'] },
      ],
    },
    {
      id: 'cadastros',
      label: 'Cadastros',
      icon: Database,
      roles: ['admin', 'financial', 'technician', 'seller'],
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
      roles: ['admin', 'financial', 'seller'],
      items: [
        { label: 'Leads / Inbox', icon: MessageCircle, path: '/whatsapp/leads' },
        { label: 'Agendar Status', icon: Camera, path: '/whatsapp/status' },
        { label: 'Agendamentos', icon: CalendarClock, path: '/whatsapp/scheduled', roles: ['admin', 'financial'] },
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

  const isActive = (path: string) => {
    if (path === '/') return location.pathname === '/';
    if (location.pathname === path) return true;
    
    // Check if another menu item is a better (longer) match
    const allPaths = groups.flatMap(g => g.items.map(i => i.path));
    const matchingPaths = allPaths.filter(p => location.pathname.startsWith(p) && (location.pathname.length === p.length || location.pathname.charAt(p.length) === '/'));
    const longestMatch = matchingPaths.reduce((a, b) => a.length > b.length ? a : b, '');
    
    if (longestMatch) {
      return path === longestMatch;
    }
    
    // Fallback for paths that don't match any menu exactly (like /clients/new)
    return location.pathname.startsWith(path + '/');
  };

  // Filter items based on roles and dynamic permissions (metadata.visible_areas)
  const visibleAreas = (user?.metadata as any)?.visible_areas as string[] | undefined;
  // Support legacy department field too just in case
  const legacyAreas = user?.department ? user.department.split(',').map(s => s.trim()) : [];
  const allowedGroups = visibleAreas || (legacyAreas.length > 0 ? legacyAreas : null);

  const visibleGroups = groups
    .filter((g) => {
      // Admins always see everything
      if (user?.role === 'admin') return true;

      // If user has specific group permissions, use them
      if (allowedGroups && allowedGroups.length > 0) {
        return allowedGroups.includes(g.id);
      }
      // Fallback to role-based filtering
      return !g.roles || (user && g.roles.includes(user.role));
    })
    .map((g) => ({
      ...g,
      items: g.items.filter((i) => !i.roles || (user && i.roles.includes(user.role))),
    }))
    .filter((g) => g.items.length > 0);

  // Track open/closed state per group. Default: only "operacional" open.
  const [openGroup, setOpenGroup] = useState<string | null>('operacional');

  // Auto-expand the group that contains the active route
  useEffect(() => {
    const activeGroup = visibleGroups.find((g) => g.items.some((i) => isActive(i.path)));
    if (activeGroup) {
      setOpenGroup(activeGroup.id);
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

  const toggleGroup = (id: string) => setOpenGroup((prev) => (prev === id ? null : id));

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
      {/* ── Brand Header ── */}
      <div className="flex h-16 items-center gap-3 px-3 border-b border-sidebar-border">
        <Link to="/" className="flex items-center gap-2.5 min-w-0">
          <HbrMark size={collapsed ? 36 : 32} />
          {!collapsed && (
            logoSetting ? (
              <img src={logoSetting} alt="HBR Systems" className="h-9 w-auto max-w-[120px] object-contain" />
            ) : (
              <div className="flex flex-col leading-none select-none">
                <span className="text-[17px] font-black tracking-[0.18em] text-sidebar-primary">HBR</span>
                <div className="flex items-center gap-1 mt-[3px]">
                  <div className="h-px w-3.5 bg-sidebar-primary/60" />
                  <span className="text-[7.5px] font-bold tracking-[0.38em] text-sidebar-foreground/75 uppercase">Systems</span>
                  <div className="h-px w-3.5 bg-[#7FA0B8]/50" />
                </div>
              </div>
            )
          )}
        </Link>
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
          const isOpen = openGroup === group.id;

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

      {/* Version footer */}
      {!collapsed && (
        <div className="px-3 pb-1 pt-0">
          <p className="text-[10px] text-sidebar-foreground/30 text-center select-none">v1.2.0</p>
        </div>
      )}
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
        <header className="flex h-14 items-center gap-4 border-b border-border/60 bg-background px-4 lg:px-6 shrink-0">
          <button
            onClick={() => setMobileOpen(true)}
            className="lg:hidden rounded-lg p-1.5 hover:bg-muted transition-colors"
          >
            <Menu className="h-5 w-5" />
          </button>
          {/* Mobile brand mark */}
          <Link to="/" className="lg:hidden flex items-center gap-2">
            <HbrMark size={28} />
            <span className="text-sm font-black tracking-widest text-primary">HBR</span>
          </Link>
          <div className="flex-1" />
          <div className="flex items-center gap-3">
            <DiagnosticExportButton />
            <WhatsAppBell />
            <NotificationBell />
            <div className="text-right hidden sm:block">
              <p className="text-sm font-medium leading-none truncate max-w-[120px]">
                {user?.full_name || 'Usuário'}
              </p>
              <div className="flex justify-end gap-1 mt-1">
                <Badge variant="outline" className="text-[10px] py-0 h-4 bg-primary/5 border-primary/20 text-primary">
                  {roleLabels[user?.role || ''] || user?.role || ''}
                </Badge>
              </div>
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
      {showPushBanner && (
        <div className="fixed bottom-20 left-4 right-4 z-50 bg-primary text-primary-foreground rounded-xl p-3 flex items-center justify-between shadow-lg sm:hidden">
          <div className="flex items-center gap-2 text-sm min-w-0">
            <Bell className="h-4 w-4 flex-shrink-0" />
            <span className="truncate">Ativar notificações de OS</span>
          </div>
          <div className="flex gap-2 ml-2 flex-shrink-0">
            <Button
              size="sm"
              variant="secondary"
              className="h-7 text-xs"
              onClick={handleEnablePush}
            >
              Ativar
            </Button>
            <Button
              size="sm"
              variant="ghost"
              className="h-7 w-7 p-0 text-primary-foreground/70"
              onClick={() => {
                setShowPushBanner(false);
                localStorage.setItem('push_banner_dismissed', '1');
              }}
            >
              ×
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
