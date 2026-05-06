import { Button } from '@/components/ui/button';
import { HelpCircle } from 'lucide-react';

export type OptionItem = { label: string; value: string };

export function AIOptionsCard({
  question,
  options,
  status,
  onSelect,
  selectedValue,
}: {
  question: string;
  options: OptionItem[];
  status: 'pending' | 'selected';
  onSelect: (value: string, label: string) => void;
  selectedValue?: string;
}) {
  return (
    <div className="rounded-lg border border-border bg-muted/40 p-3">
      <div className="flex items-center gap-2 mb-2">
        <HelpCircle className="h-4 w-4 text-muted-foreground shrink-0" />
        <span className="text-sm font-medium text-foreground">{question}</span>
      </div>
      <div className="flex flex-wrap gap-2">
        {options.map((opt) => {
          const isSelected = selectedValue === opt.value;
          return (
            <Button
              key={opt.value}
              size="sm"
              variant={isSelected ? 'default' : 'outline'}
              onClick={() => status === 'pending' && onSelect(opt.value, opt.label)}
              disabled={status === 'selected' && !isSelected}
              className="text-xs h-8 px-3"
            >
              {opt.label}
            </Button>
          );
        })}
      </div>
      {status === 'selected' && selectedValue && (
        <p className="text-xs text-muted-foreground mt-2 italic">
          ✓ Selecionado: {options.find(o => o.value === selectedValue)?.label}
        </p>
      )}
    </div>
  );
}
