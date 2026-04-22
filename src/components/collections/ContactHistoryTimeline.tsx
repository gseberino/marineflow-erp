import {
  MessageCircle, CheckCheck, Phone, PhoneMissed, Mail,
  FileText, Handshake, CheckCircle,
} from 'lucide-react';
import type { CollectionContact, CollectionContactType } from '@/hooks/use-collections';

const ICONS: Record<CollectionContactType, { Icon: typeof MessageCircle; color: string; label: string }> = {
  whatsapp_sent:      { Icon: MessageCircle, color: 'text-green-600',  label: 'WhatsApp enviado' },
  whatsapp_delivered: { Icon: CheckCheck,    color: 'text-blue-600',   label: 'WhatsApp entregue' },
  whatsapp_read:      { Icon: CheckCheck,    color: 'text-purple-600', label: 'WhatsApp lido' },
  call_made:          { Icon: Phone,         color: 'text-green-600',  label: 'Ligação feita' },
  call_answered:      { Icon: Phone,         color: 'text-green-600',  label: 'Ligação atendida' },
  call_no_answer:     { Icon: PhoneMissed,   color: 'text-red-600',    label: 'Ligação sem resposta' },
  email_sent:         { Icon: Mail,          color: 'text-blue-600',   label: 'E-mail enviado' },
  manual_note:        { Icon: FileText,      color: 'text-muted-foreground', label: 'Anotação' },
  payment_promised:   { Icon: Handshake,     color: 'text-amber-600',  label: 'Prometeu pagar' },
  paid:               { Icon: CheckCircle,   color: 'text-green-600',  label: 'Pagamento confirmado' },
};

export function ContactHistoryTimeline({ items }: { items: CollectionContact[] }) {
  if (items.length === 0) {
    return <p className="text-sm text-muted-foreground py-4">Nenhum contato registrado ainda.</p>;
  }
  return (
    <ol className="relative border-l border-border ml-3 space-y-4">
      {items.map(item => {
        const meta = ICONS[item.contact_type] || ICONS.manual_note;
        const Icon = meta.Icon;
        return (
          <li key={item.id} className="ml-4">
            <span className="absolute -left-3 flex h-6 w-6 items-center justify-center rounded-full bg-background border">
              <Icon className={`h-3.5 w-3.5 ${meta.color}`} />
            </span>
            <div className="flex flex-col">
              <span className="text-sm font-medium">{meta.label}</span>
              <span className="text-xs text-muted-foreground">
                {new Date(item.created_at).toLocaleString('pt-BR')}
              </span>
              {item.notes && <p className="mt-1 text-sm">{item.notes}</p>}
              {item.contact_type === 'payment_promised' && item.promised_date && (
                <p className="mt-1 text-xs text-amber-700 dark:text-amber-300">
                  Prometeu pagar em {new Date(item.promised_date).toLocaleDateString('pt-BR')}
                </p>
              )}
            </div>
          </li>
        );
      })}
    </ol>
  );
}
