import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { LinkIcon, FileText, ReceiptText } from 'lucide-react';

/**
 * 'resumo' existe porque link e PDF exigem que o cliente ABRA alguma coisa para descobrir
 * quanto custa — e quem está no celular, no meio do dia, muitas vezes não abre. No resumo
 * os números vão no corpo da mensagem: total, sinal, saldo e como pagar.
 */
export type SendMode = 'link' | 'document' | 'resumo';

interface Props {
  mode: SendMode;
  onChange: (m: SendMode) => void;
  canSendLink: boolean;
  canSendDocument: boolean;
  canSendResumo?: boolean;
}

export function ModeSelector({ mode, onChange, canSendLink, canSendDocument, canSendResumo = false }: Props) {
  return (
    <div className="space-y-2">
      <Label>Modo de envio</Label>
      <RadioGroup
        value={mode}
        onValueChange={(v) => onChange(v as SendMode)}
        className={canSendResumo ? 'grid gap-2 sm:grid-cols-3' : 'grid grid-cols-2 gap-2'}
      >
        {canSendResumo && (
          <label
            className={`flex items-start gap-2 rounded-lg border p-3 cursor-pointer transition ${
              mode === 'resumo' ? 'border-accent bg-accent/5' : 'hover:bg-muted/40'
            }`}
          >
            <RadioGroupItem value="resumo" className="mt-0.5" />
            <div>
              <div className="font-medium text-sm flex items-center gap-1.5">
                <ReceiptText className="h-3.5 w-3.5" /> Resumo escrito
              </div>
              <p className="text-xs text-muted-foreground mt-0.5">
                Valores, sinal e chave PIX no corpo da mensagem.
              </p>
            </div>
          </label>
        )}
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
