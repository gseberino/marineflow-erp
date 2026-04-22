import { Checkbox } from '@/components/ui/checkbox';
import { RefreshCw } from 'lucide-react';

interface Props {
  autoRetry: boolean;
  onAutoRetryChange: (v: boolean) => void;
  maxAttempts: number;
  onMaxAttemptsChange: (n: number) => void;
  attemptInfo?: string;
  disabled?: boolean;
}

export function RetrySettings({
  autoRetry,
  onAutoRetryChange,
  maxAttempts,
  onMaxAttemptsChange,
  attemptInfo,
  disabled,
}: Props) {
  return (
    <div className="rounded-lg border p-3 space-y-2 bg-muted/30">
      <label className="flex items-center gap-2 text-sm font-medium cursor-pointer">
        <Checkbox checked={autoRetry} onCheckedChange={(v) => onAutoRetryChange(!!v)} />
        <RefreshCw className="h-3.5 w-3.5" />
        Reenviar automaticamente em caso de falha
      </label>
      {autoRetry && (
        <div className="flex items-center gap-2 text-xs text-muted-foreground pl-6 flex-wrap">
          <span>Máx. tentativas:</span>
          <select
            className="h-7 rounded border border-input bg-background px-2 text-xs"
            value={maxAttempts}
            onChange={(e) => onMaxAttemptsChange(parseInt(e.target.value, 10))}
            disabled={disabled}
          >
            {[2, 3, 4, 5].map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
          <span>(backoff 1s → 2s → 4s; PDF é recalculado a cada tentativa)</span>
        </div>
      )}
      {attemptInfo && <p className="text-xs text-accent pl-6">{attemptInfo}</p>}
    </div>
  );
}
