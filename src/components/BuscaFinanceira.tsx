// A caixa de busca das listas do financeiro: um texto (nome, CPF/CNPJ ou valor) e um
// período. Mesma barra no Extrato e em "Fora da fila" — quem aprende a usar numa, usa na
// outra. A regra de o que casa com o quê está em src/lib/busca-financeira.ts.
import { Search, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { buscaAtiva, type CriterioDeBusca } from '@/lib/busca-financeira';

export function BuscaFinanceira({
  criterio, onMudar, encontrados, total, placeholder = 'Buscar por nome, CPF/CNPJ ou valor (ex.: 1.250,00)',
}: {
  criterio: CriterioDeBusca;
  onMudar: (c: CriterioDeBusca) => void;
  /** Quantos passaram pelo filtro — só aparece com busca ativa. */
  encontrados?: number;
  total?: number;
  placeholder?: string;
}) {
  const ativa = buscaAtiva(criterio);
  return (
    <div className="flex flex-wrap items-center gap-2">
      <div className="relative min-w-0 flex-1 basis-56">
        <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={criterio.termo}
          onChange={(e) => onMudar({ ...criterio, termo: e.target.value })}
          placeholder={placeholder}
          aria-label="Buscar"
          className="h-9 pl-8"
        />
      </div>
      <div className="flex items-center gap-1.5">
        <Input
          type="date" aria-label="De" title="De"
          value={criterio.de ?? ''}
          onChange={(e) => onMudar({ ...criterio, de: e.target.value || undefined })}
          className="h-9 w-[9.5rem]"
        />
        <span className="text-xs text-muted-foreground">até</span>
        <Input
          type="date" aria-label="Até" title="Até"
          value={criterio.ate ?? ''}
          onChange={(e) => onMudar({ ...criterio, ate: e.target.value || undefined })}
          className="h-9 w-[9.5rem]"
        />
      </div>
      {ativa && (
        <>
          {encontrados != null && total != null && (
            <span className="text-xs text-muted-foreground tabular-nums">{encontrados} de {total}</span>
          )}
          <Button variant="ghost" size="sm" className="h-9 gap-1" onClick={() => onMudar({ termo: '' })}>
            <X className="h-3.5 w-3.5" /> Limpar
          </Button>
        </>
      )}
    </div>
  );
}
