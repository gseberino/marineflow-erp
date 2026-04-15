import { useState, useMemo } from 'react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList, CommandSeparator } from '@/components/ui/command';
import { ClientFormDialog } from '@/components/ClientFormDialog';
import { Button } from '@/components/ui/button';
import { ChevronsUpDown, Plus, Check } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { Client } from '@/hooks/use-clients';

interface Props {
  value: string;
  onChange: (clientId: string, clientName: string) => void;
  clients: Client[] | undefined;
  disabled?: boolean;
}

export function ClientCombobox({ value, onChange, clients, disabled }: Props) {
  const [open, setOpen] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [search, setSearch] = useState('');

  const filtered = useMemo(() => {
    if (!clients) return [];
    const active = clients.filter(c => c.active);
    if (!search) return active.slice(0, 30);
    const q = search.toLowerCase();
    return active.filter(c =>
      c.full_name_or_company_name.toLowerCase().includes(q) ||
      (c.cpf_cnpj || '').includes(q)
    ).slice(0, 30);
  }, [clients, search]);

  const selectedClient = clients?.find(c => c.id === value);

  return (
    <>
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <Button
            variant="outline"
            role="combobox"
            aria-expanded={open}
            className="w-full justify-between font-normal"
            disabled={disabled}
          >
            {selectedClient
              ? selectedClient.full_name_or_company_name
              : 'Selecionar cliente...'}
            <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-[--radix-popover-trigger-width] p-0" align="start">
          <Command shouldFilter={false}>
            <CommandInput
              placeholder="Buscar cliente..."
              value={search}
              onValueChange={setSearch}
            />
            <CommandList>
              <CommandEmpty>
                <div className="py-2 text-center text-sm">
                  <p className="text-muted-foreground">Nenhum cliente encontrado</p>
                  <button
                    type="button"
                    onClick={() => { setOpen(false); setShowCreate(true); }}
                    className="mt-1 inline-flex items-center gap-1 text-primary hover:underline text-sm"
                  >
                    <Plus className="h-3 w-3" />
                    Cadastrar &quot;{search}&quot;
                  </button>
                </div>
              </CommandEmpty>
              <CommandGroup>
                {filtered.map(client => (
                  <CommandItem
                    key={client.id}
                    value={client.id}
                    onSelect={() => {
                      onChange(client.id, client.full_name_or_company_name);
                      setOpen(false);
                      setSearch('');
                    }}
                  >
                    <Check className={cn('mr-2 h-4 w-4', value === client.id ? 'opacity-100' : 'opacity-0')} />
                    <div className="flex flex-col">
                      <span className="text-sm">{client.full_name_or_company_name}</span>
                      {client.cpf_cnpj && (
                        <span className="text-xs text-muted-foreground">{client.cpf_cnpj}</span>
                      )}
                    </div>
                  </CommandItem>
                ))}
              </CommandGroup>
              <CommandSeparator />
              <CommandGroup>
                <CommandItem
                  onSelect={() => { setOpen(false); setShowCreate(true); }}
                  className="text-primary cursor-pointer"
                >
                  <Plus className="mr-2 h-4 w-4" />
                  Novo Cliente
                </CommandItem>
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>

      <ClientFormDialog
        open={showCreate}
        onOpenChange={setShowCreate}
        initialName={search}
        onCreated={(newClient) => {
          onChange(newClient.id, newClient.full_name_or_company_name);
          setSearch('');
        }}
      />
    </>
  );
}
