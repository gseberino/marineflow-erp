import { type ServiceOrderStatus, type ServiceOrderPriority, type ServiceType } from '@/types/domain';

export const statusConfig: Record<ServiceOrderStatus, { label: string; className: string }> = {
  draft: { label: 'Draft', className: 'bg-muted text-muted-foreground' },
  scheduled: { label: 'Scheduled', className: 'bg-info/15 text-info border border-info/30' },
  open: { label: 'Open', className: 'bg-primary/10 text-primary border border-primary/30' },
  in_progress: { label: 'In Progress', className: 'bg-warning/15 text-warning border border-warning/30' },
  awaiting_parts: { label: 'Awaiting Parts', className: 'bg-destructive/10 text-destructive border border-destructive/30' },
  awaiting_client: { label: 'Awaiting Client', className: 'bg-muted text-muted-foreground border border-border' },
  completed: { label: 'Completed', className: 'bg-success/15 text-success border border-success/30' },
  invoiced: { label: 'Invoiced', className: 'bg-accent/15 text-accent border border-accent/30' },
  cancelled: { label: 'Cancelled', className: 'bg-destructive/10 text-muted-foreground line-through' },
};

export const priorityConfig: Record<ServiceOrderPriority, { label: string; className: string }> = {
  low: { label: 'Low', className: 'text-muted-foreground' },
  normal: { label: 'Normal', className: 'text-foreground' },
  high: { label: 'High', className: 'text-warning font-semibold' },
  urgent: { label: 'Urgent', className: 'text-destructive font-bold' },
};

export const serviceTypeLabels: Record<ServiceType, string> = {
  diagnosis: 'Diagnosis',
  repair: 'Repair',
  installation: 'Installation',
  preventive_maintenance: 'Preventive Maintenance',
  consulting: 'Consulting',
  engineering_project: 'Engineering Project',
  commissioning: 'Commissioning',
  inspection: 'Inspection',
};

export const paymentStatusConfig: Record<string, { label: string; className: string }> = {
  unpaid: { label: 'Unpaid', className: 'bg-destructive/10 text-destructive border border-destructive/30' },
  partially_paid: { label: 'Partial', className: 'bg-warning/15 text-warning border border-warning/30' },
  paid: { label: 'Paid', className: 'bg-success/15 text-success border border-success/30' },
  pending: { label: 'Pending', className: 'bg-warning/15 text-warning border border-warning/30' },
  overdue: { label: 'Overdue', className: 'bg-destructive/10 text-destructive border border-destructive/30' },
  cancelled: { label: 'Cancelled', className: 'bg-muted text-muted-foreground' },
};

export function formatCurrency(value: number): string {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
}

export function formatDate(date: string): string {
  return new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

export function formatDateTime(date: string): string {
  return new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}
