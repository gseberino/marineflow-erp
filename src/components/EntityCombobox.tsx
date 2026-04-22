import { useMemo, useState } from 'react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
} from '@/components/ui/command';
import { Button } from '@/components/ui/button';
import { ChevronsUpDown, Plus, Check } from 'lucide-react';
import { cn } from '@/lib/utils';

export interface EntityOption {
  /** Unique value passed to onChange */
  value: string;
  /** Primary line displayed and used in matching */
  label: string;
  /** Optional muted second line (e.g. SKU, CPF, marca) */
  description?: string;
  /** Extra strings to match against in search (not displayed) */
  searchTerms?: string[];
  /** Disable selection of this row */
  disabled?: boolean;
}

interface EntityComboboxProps {
  value: string | null | undefined;
  onChange: (value: string) => void;
  options: EntityOption[];
  placeholder?: string;
  searchPlaceholder?: string;
  emptyText?: string;
  disabled?: boolean;
  className?: string;
  triggerClassName?: string;
  /** Optional handler shown as a footer "+ Cadastrar novo" item */
  onCreate?: (typedSearch: string) => void;
  createLabel?: string;
  /** Minimum characters before filtering — below this, the full list is shown. Default 3. */
  minSearchChars?: number;
  /** Hard cap on rendered rows for performance. Default 200. */
  maxRows?: number;
  /** Used when nothing is selected and no value matches an option */
  fallbackLabel?: string;
  /** When true, the trigger has `w-full` */
  fullWidth?: boolean;
}

/**
 * Searchable combobox for picking pre-registered entities.
 *
 * Behavior:
 * - Shows the full active list before the user types {minSearchChars} characters
 * - After {minSearchChars} chars, filters by label, description and any extra searchTerms
 * - Optional "+ Cadastrar novo" footer that receives the current typed search
 */
export function EntityCombobox({
  value,
  onChange,
  options,
  placeholder = 'Selecionar...',
  searchPlaceholder = 'Buscar... (digite ao menos 3 letras)',
  emptyText = 'Nada encontrado',
  disabled,
  className,
  triggerClassName,
  onCreate,
  createLabel = 'Cadastrar novo',
  minSearchChars = 3,
  maxRows = 200,
  fallbackLabel,
  fullWidth = true,
}: EntityComboboxProps) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');

  const selected = useMemo(
    () => options.find((o) => o.value === value),
    [options, value],
  );

  const filtered = useMemo(() => {
    const trimmed = search.trim().toLowerCase();
    if (trimmed.length < minSearchChars) {
      return options.slice(0, maxRows);
    }
    return options
      .filter((o) => {
        const haystack = [o.label, o.description || '', ...(o.searchTerms || [])]
          .join(' ')
          .toLowerCase();
        return haystack.includes(trimmed);
      })
      .slice(0, maxRows);
  }, [options, search, minSearchChars, maxRows]);

  return (
    <div className={className}>
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <Button
            type="button"
            variant="outline"
            role="combobox"
            aria-expanded={open}
            disabled={disabled}
            className={cn(
              fullWidth && 'w-full',
              'justify-between font-normal',
              triggerClassName,
            )}
          >
            <span className="truncate text-left">
              {selected
                ? selected.label
                : fallbackLabel || (
                    <span className="text-muted-foreground">{placeholder}</span>
                  )}
            </span>
            <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
          </Button>
        </PopoverTrigger>

        <PopoverContent
          className="w-[--radix-popover-trigger-width] p-0"
          align="start"
        >
          <Command shouldFilter={false}>
            <CommandInput
              placeholder={searchPlaceholder}
              value={search}
              onValueChange={setSearch}
            />
            <CommandList>
              {filtered.length === 0 ? (
                <CommandEmpty>
                  <div className="py-3 text-center text-sm">
                    <p className="text-muted-foreground">{emptyText}</p>
                    {onCreate && (
                      <button
                        type="button"
                        onClick={() => {
                          setOpen(false);
                          onCreate(search);
                        }}
                        className="mt-2 inline-flex items-center gap-1 text-primary hover:underline"
                      >
                        <Plus className="h-3 w-3" />
                        {search
                          ? `Cadastrar "${search}"`
                          : createLabel}
                      </button>
                    )}
                  </div>
                </CommandEmpty>
              ) : (
                <CommandGroup>
                  {filtered.map((opt) => (
                    <CommandItem
                      key={opt.value}
                      value={opt.value}
                      disabled={opt.disabled}
                      onSelect={() => {
                        onChange(opt.value);
                        setOpen(false);
                        setSearch('');
                      }}
                    >
                      <Check
                        className={cn(
                          'mr-2 h-4 w-4',
                          value === opt.value ? 'opacity-100' : 'opacity-0',
                        )}
                      />
                      <div className="flex min-w-0 flex-col">
                        <span className="truncate text-sm">{opt.label}</span>
                        {opt.description && (
                          <span className="truncate text-xs text-muted-foreground">
                            {opt.description}
                          </span>
                        )}
                      </div>
                    </CommandItem>
                  ))}
                </CommandGroup>
              )}

              {onCreate && filtered.length > 0 && (
                <>
                  <CommandSeparator />
                  <CommandGroup>
                    <CommandItem
                      onSelect={() => {
                        setOpen(false);
                        onCreate(search);
                      }}
                      className="text-primary cursor-pointer"
                    >
                      <Plus className="mr-2 h-4 w-4" />
                      {createLabel}
                    </CommandItem>
                  </CommandGroup>
                </>
              )}
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
    </div>
  );
}
