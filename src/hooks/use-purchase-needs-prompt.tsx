import { useCallback, useState } from 'react';
import { PurchaseNeedsDialog } from '@/components/purchasing/PurchaseNeedsDialog';

/**
 * Liga a aprovação do orçamento ao aviso de compra.
 *
 * A conversão ORÇ→OS acontece em vários lugares (lista de orçamentos, troca rápida de
 * status, kanban, formulário da OS). Em vez de repetir o estado do diálogo em cada um,
 * cada tela usa este hook: chama `promptIfConverted` com o resultado da mutação e
 * renderiza `{dialog}`. Se não houve conversão (mudança de status comum), nada abre.
 *
 * Uso:
 *   const { promptIfConverted, dialog } = usePurchaseNeedsPrompt();
 *   const res = await updateStatus.mutateAsync({ id, status });
 *   promptIfConverted(res, { id, number, client });
 *   ...
 *   {dialog}
 */

interface Target {
  id: string;
  number?: string | null;
  client?: string | null;
}

export function usePurchaseNeedsPrompt() {
  const [target, setTarget] = useState<Target | null>(null);

  const promptIfConverted = useCallback((result: any, meta: Target) => {
    if (result?.justConverted) setTarget(meta);
  }, []);

  /** Para abrir o aviso fora de uma conversão (ex.: botão na própria OS). */
  const promptNow = useCallback((meta: Target) => setTarget(meta), []);

  const dialog = target ? (
    <PurchaseNeedsDialog
      open
      onOpenChange={o => { if (!o) setTarget(null); }}
      serviceOrderId={target.id}
      serviceOrderNumber={target.number}
      clientName={target.client}
    />
  ) : null;

  return { promptIfConverted, promptNow, dialog };
}
