import { useI18n } from '@/i18n';
import { useRecordHistory } from '@/hooks/use-audit-log';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Badge } from '@/components/ui/badge';
import { History } from 'lucide-react';

const ACTION_COLORS: Record<string, string> = {
  update: 'bg-blue-100 text-blue-700',
  cancel: 'bg-destructive/10 text-destructive',
  reopen: 'bg-amber-100 text-amber-700',
  reversal: 'bg-purple-100 text-purple-700',
  cascade_update: 'bg-muted text-muted-foreground',
};

interface RecordHistoryProps {
  tableName: string;
  recordId: string | undefined;
}

export function RecordHistory({ tableName, recordId }: RecordHistoryProps) {
  const { t } = useI18n();
  const { data: history } = useRecordHistory(tableName, recordId);
  const auditT = t.auditLog as any;
  const actionsMap = auditT?.actions as Record<string, string> || {};

  if (!recordId || !history || history.length === 0) return null;

  return (
    <Collapsible>
      <CollapsibleTrigger className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors py-2">
        <History className="h-4 w-4" />
        {t.serviceOrders.recordHistory} ({history.length})
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div className="mt-2 space-y-2 border-l-2 border-muted pl-4">
          {history.map((entry: any) => (
            <div key={entry.id} className="flex items-start gap-3 text-sm">
              <span className="text-xs text-muted-foreground whitespace-nowrap min-w-[100px]">
                {new Date(entry.changed_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}
              </span>
              <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold ${ACTION_COLORS[entry.action] || ''}`}>
                {actionsMap[entry.action] || entry.action}
              </span>
              <span className="text-muted-foreground text-xs flex-1 truncate">
                {entry.reason || '—'}
              </span>
              <Badge variant="outline" className="text-xs">{entry.changed_by}</Badge>
            </div>
          ))}
        </div>
      </CollapsibleContent>
    </Collapsible>
  );
}
