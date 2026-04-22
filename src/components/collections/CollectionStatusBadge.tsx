import { StatusBadge } from '@/components/StatusBadge';
import type { CollectionStatus } from '@/hooks/use-collections';

const MAP: Record<CollectionStatus, { label: string; cls: string }> = {
  pending:   { label: 'Pendente',     cls: 'bg-amber-500/15 text-amber-700 dark:text-amber-300' },
  sent:      { label: 'Enviada',      cls: 'bg-blue-500/15 text-blue-700 dark:text-blue-300' },
  viewed:    { label: 'Visualizada',  cls: 'bg-purple-500/15 text-purple-700 dark:text-purple-300' },
  paid:      { label: 'Paga',         cls: 'bg-green-500/15 text-green-700 dark:text-green-300' },
  overdue:   { label: 'Vencida',      cls: 'bg-red-500/15 text-red-700 dark:text-red-300' },
  disputed:  { label: 'Em disputa',   cls: 'bg-orange-500/15 text-orange-700 dark:text-orange-300' },
  cancelled: { label: 'Cancelada',    cls: 'bg-muted text-muted-foreground' },
};

export const COLLECTION_STATUS_OPTIONS = (Object.keys(MAP) as CollectionStatus[]).map(k => ({
  value: k, label: MAP[k].label,
}));

export function CollectionStatusBadge({ status }: { status: CollectionStatus }) {
  const m = MAP[status] || MAP.pending;
  return <StatusBadge className={m.cls}>{m.label}</StatusBadge>;
}
