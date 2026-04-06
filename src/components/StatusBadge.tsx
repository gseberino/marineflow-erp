import { cn } from '@/lib/utils';

interface StatusBadgeProps {
  className?: string;
  children: React.ReactNode;
}

export function StatusBadge({ className, children }: StatusBadgeProps) {
  return (
    <span className={cn('inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium', className)}>
      {children}
    </span>
  );
}
