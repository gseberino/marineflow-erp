import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import type { WhatsAppTemplate } from '@/hooks/use-whatsapp-templates';

interface Props {
  message: string;
  onMessageChange: (v: string) => void;
  mode: 'link' | 'document';
  templates?: WhatsAppTemplate[];
  templateId: string;
  onTemplateChange: (id: string) => void;
  usingClientDefault?: boolean;
}

export function MessageEditor({
  message,
  onMessageChange,
  mode,
  templates,
  templateId,
  onTemplateChange,
  usingClientDefault,
}: Props) {
  return (
    <>
      {!!templates?.length && (
        <div className="space-y-2">
          <Label>Template</Label>
          <select
            className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
            value={templateId}
            onChange={(e) => onTemplateChange(e.target.value)}
          >
            <option value="">— mensagem livre —</option>
            {templates.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name}
              </option>
            ))}
          </select>
        </div>
      )}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <Label htmlFor="msg-whatsapp">{mode === 'document' ? 'Legenda do PDF' : 'Mensagem'}</Label>
          {usingClientDefault && (
            <span className="text-xs text-muted-foreground">
              ✓ Usando mensagem padrão do cliente
            </span>
          )}
        </div>
        <Textarea
          id="msg-whatsapp"
          rows={4}
          value={message}
          onChange={(e) => onMessageChange(e.target.value)}
        />
      </div>
    </>
  );
}
