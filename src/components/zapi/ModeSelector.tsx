import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { LinkIcon, FileText } from 'lucide-react';

export type SendMode = 'link' | 'document';

interface Props {
  mode: SendMode;
  onChange: (m: SendMode) => void;
  canSendLink: boolean;
  canSendDocument: boolean;
}

export function ModeSelector({ mode, onChange, canSendLink, canSendDocument }: Props) {
  return (
    <div className="space-y-2">
      <Label>Modo de envio</Label>
      <RadioGroup
        value={mode}
        onValueChange={(v) => onChange(v as SendMode)}
        className="grid grid-cols-2 gap-2"
      >
        <label
          className={`flex items-start gap-2 rounded-lg border p-3 cursor-pointer transition ${
            mode === 'link' ? 'border-accent bg-accent/5' : 'hover:bg-muted/40'
          } ${!canSendLink ? 'opacity-50 cursor-not-allowed' : ''}`}
        >
          <RadioGroupItem value="link" disabled={!canSendLink} className="mt-0.5" />
          <div>
            <div className="font-medium text-sm flex items-center gap-1.5">
              <LinkIcon className="h-3.5 w-3.5" /> Link com preview
            </div>
            <p className="text-xs text-muted-foreground mt-0.5">
              Card clicável apontando para a página pública.
            </p>
          </div>
        </label>
        <label
          className={`flex items-start gap-2 rounded-lg border p-3 cursor-pointer transition ${
            mode === 'document' ? 'border-accent bg-accent/5' : 'hover:bg-muted/40'
          } ${!canSendDocument ? 'opacity-50 cursor-not-allowed' : ''}`}
        >
          <RadioGroupItem value="document" disabled={!canSendDocument} className="mt-0.5" />
          <div>
            <div className="font-medium text-sm flex items-center gap-1.5">
              <FileText className="h-3.5 w-3.5" /> PDF anexado
            </div>
            <p className="text-xs text-muted-foreground mt-0.5">
              Gera e anexa o arquivo .pdf na mensagem.
            </p>
          </div>
        </label>
      </RadioGroup>
      {!canSendLink && (
        <p className="text-xs text-muted-foreground">
          ⚠ OS sem link público — apenas envio por PDF disponível.
        </p>
      )}
    </div>
  );
}
