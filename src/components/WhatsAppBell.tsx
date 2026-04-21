import { useNavigate } from 'react-router-dom';
import { MessageCircle } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { useWhatsAppUnread } from '@/hooks/use-whatsapp-realtime';

export function WhatsAppBell() {
  const navigate = useNavigate();
  const { count } = useWhatsAppUnread();

  return (
    <button
      type="button"
      onClick={() => navigate('/whatsapp-leads')}
      className="relative rounded-lg p-2 hover:bg-muted transition-colors"
      aria-label="Mensagens do WhatsApp"
      title="Mensagens do WhatsApp"
    >
      <MessageCircle className="h-5 w-5" />
      {count > 0 && (
        <Badge
          variant="destructive"
          className="absolute -top-0.5 -right-0.5 h-4 min-w-4 px-1 text-[10px] flex items-center justify-center rounded-full"
        >
          {count > 9 ? '9+' : count}
        </Badge>
      )}
    </button>
  );
}
