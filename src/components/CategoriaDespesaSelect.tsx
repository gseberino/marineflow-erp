// Seletor de categoria de despesa — o MESMO nas duas telas do financeiro.
//
// POR QUE EXISTE: a Conciliação usava uma lista fixa de dez itens no código
// (`OPERATIONAL_EXPENSE_CATEGORIES`: alimentação, pedágio, hospedagem, ferry…), que é a
// lista de reembolso de viagem de técnico e nunca teve relação com o plano de contas. A
// Caixa de entrada usava as 25 categorias reais. Quem trabalhava nas duas via dois
// financeiros diferentes, e classificar a mesma despesa dava resultados que não somam.
//
// Também cria a categoria que falta, ali mesmo: sem isso, encontrar uma despesa que não se
// encaixa em nada obriga a sair da tela, e o caminho mais curto vira jogar em "Outros".
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useFinancialCategories } from '@/hooks/use-financial-categories';
import { useCriarCategoriaDespesa } from '@/hooks/use-finance-review';
import { X } from 'lucide-react';

/** Valor sentinela do item "criar": não pode colidir com nome de categoria real. */
export const NOVA_CATEGORIA = '__nova__';

export function CategoriaDespesaSelect({
  valor, onMudar, grupoSugerido = null, tipo = 'payable', placeholder = 'Escolher categoria',
  className = 'h-8 text-xs',
}: {
  valor: string;
  onMudar: (v: string) => void;
  /** Grupo do DRE herdado — a categoria nova nasce no lugar certo do resultado. */
  grupoSugerido?: string | null;
  tipo?: 'payable' | 'receivable';
  placeholder?: string;
  className?: string;
}) {
  const { data: categorias = [] } = useFinancialCategories(tipo);
  const criar = useCriarCategoriaDespesa();
  const [abrindo, setAbrindo] = useState(false);
  const [nome, setNome] = useState('');

  const confirmar = () => {
    const limpo = nome.trim();
    if (!limpo) return;
    criar.mutate(
      { name: limpo, dre_group: grupoSugerido, type: tipo },
      {
        onSuccess: () => {
          onMudar(limpo);      // já aplica na linha que motivou a criação
          setNome('');
          setAbrindo(false);
        },
      },
    );
  };

  if (abrindo) {
    return (
      <div className="flex items-center gap-1">
        <Input
          autoFocus
          value={nome}
          onChange={(e) => setNome(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') confirmar();
            if (e.key === 'Escape') setAbrindo(false);
          }}
          placeholder="Nome da categoria nova"
          className={className}
        />
        <Button size="sm" className="h-8 shrink-0" disabled={!nome.trim() || criar.isPending} onClick={confirmar}>
          Criar
        </Button>
        <Button size="sm" variant="ghost" className="h-8 shrink-0" aria-label="Cancelar"
          onClick={() => setAbrindo(false)}>
          <X className="h-4 w-4" />
        </Button>
      </div>
    );
  }

  return (
    <Select value={valor} onValueChange={(v) => (v === NOVA_CATEGORIA ? setAbrindo(true) : onMudar(v))}>
      <SelectTrigger className={className}>
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        {categorias.map((c) => (
          <SelectItem key={c.name} value={c.name}>{c.name}</SelectItem>
        ))}
        <SelectItem value={NOVA_CATEGORIA} className="font-medium text-primary">
          + Criar categoria nova…
        </SelectItem>
      </SelectContent>
    </Select>
  );
}
