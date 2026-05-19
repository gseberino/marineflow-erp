import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  INSPECTION_STATUS_LABEL,
  groupDraftBySystem,
  type InspectionDraftItem,
  type InspectionItemStatus,
} from '@/lib/inspection/marine-template';

type Props = {
  items: InspectionDraftItem[];
  onChange: (next: InspectionDraftItem[]) => void;
};

const STATUS_VARIANTS: Record<InspectionItemStatus, string> = {
  pending: 'bg-muted text-muted-foreground',
  ok: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-200',
  attention: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200',
  critical: 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200',
  not_applicable: 'bg-slate-100 text-slate-700 dark:bg-slate-800/60 dark:text-slate-200',
};

export function InspectionChecklist({ items, onChange }: Props) {
  const groups = groupDraftBySystem(items);

  const updateItem = (id: string, patch: Partial<InspectionDraftItem>) => {
    onChange(items.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  };

  return (
    <div className="flex flex-col gap-6">
      {groups.map(({ systemGroup, items: groupItems }) => (
        <section key={systemGroup} className="rounded-lg border bg-card">
          <header className="border-b px-4 py-2 flex items-center justify-between">
            <h3 className="text-sm font-semibold">{systemGroup}</h3>
            <span className="text-xs text-muted-foreground">{groupItems.length} item(ns)</span>
          </header>
          <ul className="divide-y">
            {groupItems.map((item) => (
              <li key={item.id} className="p-4 flex flex-col gap-3 md:flex-row md:items-start md:gap-4">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <Badge variant="outline" className="text-[10px] font-normal">
                      {item.category}
                    </Badge>
                    <span className={`text-[10px] rounded px-1.5 py-0.5 ${STATUS_VARIANTS[item.status]}`}>
                      {INSPECTION_STATUS_LABEL[item.status]}
                    </span>
                  </div>
                  <p className="text-sm font-medium mt-1">{item.label}</p>
                  {item.hint && (
                    <p className="text-xs text-muted-foreground mt-0.5">{item.hint}</p>
                  )}
                  <div className="mt-2">
                    <Label htmlFor={`obs-${item.id}`} className="text-xs text-muted-foreground">
                      Observação
                    </Label>
                    <Textarea
                      id={`obs-${item.id}`}
                      value={item.observations ?? ''}
                      onChange={(e) => updateItem(item.id, { observations: e.target.value })}
                      placeholder="Observação técnica (opcional)"
                      rows={2}
                      className="mt-1 text-sm"
                    />
                  </div>
                </div>
                <div className="md:w-48 flex-shrink-0">
                  <Label className="text-xs text-muted-foreground">Status</Label>
                  <Select
                    value={item.status}
                    onValueChange={(v) => updateItem(item.id, { status: v as InspectionItemStatus })}
                  >
                    <SelectTrigger className="mt-1">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {(Object.keys(INSPECTION_STATUS_LABEL) as InspectionItemStatus[]).map((s) => (
                        <SelectItem key={s} value={s}>
                          {INSPECTION_STATUS_LABEL[s]}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}
