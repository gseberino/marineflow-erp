/**
 * Confirmação antes de uma ação que apaga, encerra ou descarta (03/10/2026).
 *
 * As linhas de lista que apagavam num clique (peça e serviço da OS, despesa, "não usar mais" um
 * serviço, descartar sugestão) passaram para o menu de três pontinhos (AcoesDaLinha) — e o item do
 * menu chama `pedir(...)`; a ação só roda no "Confirmar". Um diálogo por tela, não um por linha.
 */
import { useCallback, useState } from 'react';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';

interface Pedido {
  titulo: string;
  descricao?: string;
  /** O texto do botão que confirma ("Excluir", "Finalizar", "Descartar"). */
  confirmar: string;
  acao: () => void;
}

export function useConfirmacao() {
  const [pedido, setPedido] = useState<Pedido | null>(null);

  const pedir = useCallback((p: Pedido) => setPedido(p), []);

  const dialogo = (
    <AlertDialog open={!!pedido} onOpenChange={(aberto) => { if (!aberto) setPedido(null); }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{pedido?.titulo}</AlertDialogTitle>
          {pedido?.descricao && <AlertDialogDescription>{pedido.descricao}</AlertDialogDescription>}
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Voltar</AlertDialogCancel>
          <AlertDialogAction
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            onClick={() => { const a = pedido?.acao; setPedido(null); a?.(); }}
          >
            {pedido?.confirmar}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );

  return { pedir, dialogo };
}
