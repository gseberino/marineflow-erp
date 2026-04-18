import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Bell, DollarSign, Package, Clock, AlertTriangle, Check, CheckCheck } from 'lucide-react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { cn } from '@/lib/utils';
import { useNotifications, type AppNotification, type NotificationType } from '@/hooks/use-notifications';

const typeConfig: Record<NotificationType, { Icon: typeof Bell; className: string }> = {
  OVERDUE_RECEIVABLE: { Icon: DollarSign, className: 'text-destructive bg-destructive/10' },
  LOW_STOCK: { Icon: Package, className: 'text-amber-600 bg-amber-500/10' },
  OS_UPCOMING: { Icon: Clock, className: 'text-blue-600 bg-blue-500/10' },
  OS_STALE: { Icon: AlertTriangle, className: 'text-amber-600 bg-amber-500/10' },
};

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const min = Math.floor(diff / 60000);
  if (min < 1) return 'agora';
  if (min < 60) return `há ${min} min`;
  const hours = Math.floor(min / 60);
  if (hours < 24) return `há ${hours} h`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `há ${days} d`;
  const months = Math.floor(days / 30);
  return `há ${months} m`;
}

export function NotificationBell() {
  const [open, setOpen] = useState(false);
  const navigate = useNavigate();
  const { notifications, unreadCount, isRead, markAsRead, markAllAsRead } = useNotifications();

  const handleClick = (n: AppNotification) => {
    markAsRead(n.id);
    setOpen(false);
    navigate(n.navigate_to);
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          className="relative rounded-lg p-2 hover:bg-muted transition-colors"
          aria-label="Notificações"
        >
          <Bell className="h-5 w-5" />
          {unreadCount > 0 && (
            <Badge
              variant="destructive"
              className="absolute -top-0.5 -right-0.5 h-4 min-w-4 px-1 text-[10px] flex items-center justify-center rounded-full"
            >
              {unreadCount > 9 ? '9+' : unreadCount}
            </Badge>
          )}
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-80 p-0">
        <div className="flex items-center justify-between border-b px-3 py-2">
          <p className="text-sm font-semibold">Notificações</p>
          {unreadCount > 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="h-7 text-xs gap-1"
              onClick={markAllAsRead}
            >
              <CheckCheck className="h-3 w-3" />
              Marcar todas
            </Button>
          )}
        </div>
        <ScrollArea className="max-h-[420px]">
          {notifications.length === 0 ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              Nenhuma notificação
            </div>
          ) : (
            <ul className="divide-y">
              {notifications.map(n => {
                const { Icon, className } = typeConfig[n.type];
                const read = isRead(n.id);
                return (
                  <li key={n.id}>
                    <div
                      className={cn(
                        'flex gap-3 px-3 py-3 hover:bg-muted/50 cursor-pointer transition-colors',
                        !read && 'bg-primary/5'
                      )}
                      onClick={() => handleClick(n)}
                    >
                      <div className={cn('h-8 w-8 shrink-0 rounded-full flex items-center justify-center', className)}>
                        <Icon className="h-4 w-4" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-start justify-between gap-2">
                          <p className="text-sm font-medium leading-tight">{n.title}</p>
                          {!read && <span className="h-2 w-2 rounded-full bg-primary mt-1 shrink-0" />}
                        </div>
                        <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">
                          {n.description}
                        </p>
                        <div className="flex items-center justify-between mt-1">
                          <span className="text-[10px] text-muted-foreground">{timeAgo(n.created_at)}</span>
                          {!read && (
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                markAsRead(n.id);
                              }}
                              className="text-[10px] text-muted-foreground hover:text-primary inline-flex items-center gap-1"
                            >
                              <Check className="h-3 w-3" />
                              Marcar como lida
                            </button>
                          )}
                        </div>
                      </div>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </ScrollArea>
      </PopoverContent>
    </Popover>
  );
}
