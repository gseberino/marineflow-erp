import type { StatusTone } from './components/StatusChip';

/** Mapa único de status de OS → tom semântico (substitui os className soltos de statusConfig). */
export const serviceOrderStatusTone: Record<string, StatusTone> = {
  draft: 'neutral',
  scheduled: 'info',
  open: 'info',
  in_progress: 'info',
  awaiting_parts: 'warning',
  awaiting_client: 'warning',
  completed: 'success',
  invoiced: 'success',
  cancelled: 'critical',
};

export const priorityTone: Record<string, StatusTone> = {
  low: 'neutral',
  normal: 'neutral',
  high: 'warning',
  urgent: 'critical',
};
