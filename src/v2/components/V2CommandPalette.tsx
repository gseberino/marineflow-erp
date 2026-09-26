import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { ClipboardList, Moon, Sun, Users } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import {
  CommandDialog, CommandEmpty, CommandGroup, CommandInput, CommandItem,
  CommandList, CommandSeparator,
} from '@/components/ui/command';
import { NAV } from './destinos-da-paleta';

/* Fase 4 · Command Palette (⌘K / Ctrl+K) — presente em todas as rotas v2.
   Navegação por qualquer tela + busca ao vivo de OS e clientes. */

export function V2CommandPalette({ onToggleTheme, mode }: { onToggleTheme: () => void; mode: 'light' | 'dark' }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const navigate = useNavigate();

  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (e.key === 'k' && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        setOpen((o) => !o);
      }
    };
    document.addEventListener('keydown', down);
    return () => document.removeEventListener('keydown', down);
  }, []);

  const term = query.trim();
  const { data: hits } = useQuery({
    queryKey: ['v2-cmdk-search', term],
    enabled: open && term.length >= 2,
    staleTime: 30_000,
    queryFn: async () => {
      const [os, clients] = await Promise.all([
        supabase
          .from('service_orders')
          .select('id, service_order_number, status, clients(name)')
          .ilike('service_order_number', `%${term}%`)
          .limit(5),
        supabase
          .from('clients')
          .select('id, name')
          .ilike('name', `%${term}%`)
          .limit(5),
      ]);
      return {
        orders: (os.data ?? []) as { id: string; service_order_number: string; status: string; clients: { name?: string } | null }[],
        clients: (clients.data ?? []) as { id: string; name: string }[],
      };
    },
  });

  const go = (to: string) => {
    setOpen(false);
    setQuery('');
    navigate(to);
  };

  return (
    <CommandDialog open={open} onOpenChange={(v) => { setOpen(v); if (!v) setQuery(''); }}>
      <CommandInput placeholder="Ir para… ou buscar OS e clientes" value={query} onValueChange={setQuery} />
      <CommandList className="themev2" data-mode={mode}>
        <CommandEmpty>Nada encontrado.</CommandEmpty>

        {hits && (hits.orders.length > 0 || hits.clients.length > 0) && (
          <>
            {hits.orders.length > 0 && (
              <CommandGroup heading="Ordens de Serviço">
                {hits.orders.map((o) => (
                  <CommandItem key={o.id} value={`os-${o.service_order_number}`} onSelect={() => go(`/v2/service-orders/${o.id}`)}>
                    <ClipboardList className="mr-2 h-4 w-4" />
                    <span className="font-semibold">{o.service_order_number}</span>
                    {o.clients?.name && <span className="ml-2 truncate text-muted-foreground">{o.clients.name}</span>}
                  </CommandItem>
                ))}
              </CommandGroup>
            )}
            {hits.clients.length > 0 && (
              <CommandGroup heading="Clientes">
                {hits.clients.map((c) => (
                  <CommandItem key={c.id} value={`cli-${c.name}`} onSelect={() => go(`/v2/clients/${c.id}`)}>
                    <Users className="mr-2 h-4 w-4" />
                    <span className="truncate">{c.name}</span>
                  </CommandItem>
                ))}
              </CommandGroup>
            )}
            <CommandSeparator />
          </>
        )}

        {NAV.map((g) => (
          <CommandGroup key={g.group} heading={g.group}>
            {g.items.map((item) => (
              <CommandItem
                key={`${g.group}-${item.label}`}
                value={`${g.group} ${item.label}`}
                keywords={[...(item.keywords ?? []), ...(item.onde ? [item.onde] : [])]}
                onSelect={() => go(item.to)}
              >
                <item.icon className="mr-2 h-4 w-4 shrink-0" />
                <span className="truncate">{item.label}</span>
                {item.onde && <span className="ml-2 truncate text-xs text-muted-foreground">→ {item.onde}</span>}
              </CommandItem>
            ))}
          </CommandGroup>
        ))}

        <CommandSeparator />
        <CommandGroup heading="Preferências">
          <CommandItem value="tema alternar claro escuro" onSelect={() => { onToggleTheme(); setOpen(false); }}>
            {mode === 'light' ? <Moon className="mr-2 h-4 w-4" /> : <Sun className="mr-2 h-4 w-4" />}
            Alternar tema ({mode === 'light' ? 'Ponte de Comando' : 'Estaleiro Claro'})
          </CommandItem>
        </CommandGroup>
      </CommandList>
    </CommandDialog>
  );
}
