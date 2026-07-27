// Seletor de data no formato brasileiro (DD/MM/AAAA), independente do locale do navegador.
// O <input type="date"> nativo exibe a data conforme o idioma do navegador (en-US → MM/DD/AAAA),
// e isso não é controlável por HTML. Este componente usa Popover + Calendar (shadcn) e mostra
// SEMPRE dd/MM/yyyy (pt-BR), enquanto guarda/retorna a data em ISO 'yyyy-MM-dd' — mesmo formato
// que os <input type="date"> já usavam, então é troca direta.
import { format, parse, isValid } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { CalendarIcon } from 'lucide-react';
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Calendar } from '@/components/ui/calendar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { cn } from '@/lib/utils';

/** Data de HOJE em ISO 'yyyy-MM-dd' pelo fuso LOCAL (evita o off-by-one do toISOString em UTC). */
export function todayISO(): string {
  return format(new Date(), 'yyyy-MM-dd');
}

interface Props {
  /** ISO 'yyyy-MM-dd' (ou '' para vazio). */
  value: string;
  onChange: (iso: string) => void;
  disabled?: boolean;
  className?: string;
  placeholder?: string;
  id?: string;
}

export function DatePickerBR({ value, onChange, disabled, className, placeholder = 'Selecionar data', id }: Props) {
  const [open, setOpen] = useState(false);
  const parsed = value ? parse(value, 'yyyy-MM-dd', new Date()) : undefined;
  const selected = parsed && isValid(parsed) ? parsed : undefined;

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          id={id}
          type="button"
          variant="outline"
          disabled={disabled}
          className={cn('w-full justify-start text-left font-normal', !selected && 'text-muted-foreground', className)}
        >
          <CalendarIcon className="mr-2 h-4 w-4 shrink-0" />
          {selected ? format(selected, 'dd/MM/yyyy', { locale: ptBR }) : placeholder}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-auto p-0" align="start">
        <Calendar
          mode="single"
          selected={selected}
          onSelect={(d) => {
            if (d) {
              onChange(format(d, 'yyyy-MM-dd')); // ISO pelo fuso local — sem shift de timezone
              setOpen(false);
            }
          }}
          initialFocus
          locale={ptBR}
        />
      </PopoverContent>
    </Popover>
  );
}
