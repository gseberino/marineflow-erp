import { useState } from 'react';
import { Check, ChevronsUpDown, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandInput, CommandList, CommandEmpty, CommandGroup, CommandItem } from '@/components/ui/command';
import { useFinancialCategories, useCreateFinancialCategory } from '@/hooks/use-financial-categories';
import { cn } from '@/lib/utils';

interface Props {
  type: 'payable' | 'receivable';
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}

export function CategorySelect({ type, value, onChange, placeholder }: Props) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const { data: categories } = useFinancialCategories(type);
  const createCat = useCreateFinancialCategory();

  const filtered = (categories || []).filter(c =>
    c.name.toLowerCase().includes(search.toLowerCase())
  );

  const showCreate = search.trim().length > 0 && !filtered.some(c => c.name.toLowerCase() === search.trim().toLowerCase());

  const handleCreate = async () => {
    try {
      await createCat.mutateAsync({ name: search.trim(), type });
      onChange(search.trim());
      setSearch('');
      setOpen(false);
    } catch {}
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="outline" role="combobox" aria-expanded={open} className="w-full justify-between font-normal">
          {value ? (
            <span className="flex items-center gap-2">
              {(() => {
                const cat = (categories || []).find(c => c.name === value);
                return cat ? <span className="w-2.5 h-2.5 rounded-full inline-block" style={{ backgroundColor: cat.color || '#6b7280' }} /> : null;
              })()}
              {value}
            </span>
          ) : (
            <span className="text-muted-foreground">{placeholder || '—'}</span>
          )}
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[280px] p-0" align="start">
        <Command shouldFilter={false}>
          <CommandInput placeholder="Buscar categoria..." value={search} onValueChange={setSearch} />
          <CommandList>
            <CommandEmpty>
              {search.trim() ? null : 'Nenhuma categoria.'}
            </CommandEmpty>
            <CommandGroup>
              {filtered.map(c => (
                <CommandItem
                  key={c.id}
                  onSelect={() => {
                    onChange(c.name);
                    setOpen(false);
                    setSearch('');
                  }}
                >
                  <span className="w-2.5 h-2.5 rounded-full mr-2" style={{ backgroundColor: c.color || '#6b7280' }} />
                  {c.name}
                  {value === c.name && <Check className="ml-auto h-4 w-4" />}
                </CommandItem>
              ))}
              {showCreate && (
                <CommandItem onSelect={handleCreate}>
                  <Plus className="h-4 w-4 mr-2 text-primary" />
                  <span className="text-primary">Criar &quot;{search.trim()}&quot;</span>
                </CommandItem>
              )}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
