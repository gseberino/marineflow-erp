/**
 * Confirmação antes de uma ação que apaga, encerra ou descarta (03/10/2026).
 *
 * As linhas de lista que apagavam num clique (peça e serviço da OS, despesa, "não usar mais" um
 * serviço, descartar sugestão) passaram para o menu de três pontinhos (AcoesDaLinha) — e o item do
 * menu chama `pedir(...)`; a ação só roda no "Confirmar". Um diálogo por tela, não um por linha.
 */
import { useCallback, useRef, useState } from 'react';
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
  /** O texto do botão que desiste. Padrão "Voltar"; "Manter o cliente atual" diz o resultado. */
  voltar?: string;
  /** Desistiu (botão de voltar ou Esc). Não roda quando a pessoa confirma. */
  aoVoltar?: () => void;
  /** Depois de o diálogo fechar de vez (confirmando ou não), no lugar de devolver o foco a quem
      o abriu — útil quando esse elemento sumiu da tela. Aqui a página já não está escondida do
      leitor de tela, então é a hora de mover o foco e anunciar. */
  aoFechar?: () => void;
}

export function useConfirmacao() {
  const [pedido, setPedido] = useState<Pedido | null>(null);
  // O botão de confirmar também fecha o diálogo: sem esta marca, o fechar que vem depois do
  // clique contaria como desistência e chamaria aoVoltar.
  const confirmouRef = useRef(false);
  // Guardado à parte: quando o fechamento termina, o pedido já foi limpo.
  const aoFecharRef = useRef<(() => void) | null>(null);

  const pedir = useCallback((p: Pedido) => {
    confirmouRef.current = false;
    aoFecharRef.current = p.aoFechar ?? null;
    setPedido(p);
  }, []);

  const dialogo = (
    <AlertDialog
      open={!!pedido}
      onOpenChange={(aberto) => {
        if (aberto) return;
        const p = pedido;
        setPedido(null);
        if (!confirmouRef.current) p?.aoVoltar?.();
        confirmouRef.current = false;
      }}
    >
      <AlertDialogContent
        onCloseAutoFocus={(e) => {
          const depois = aoFecharRef.current;
          if (!depois) return;
          e.preventDefault();
          aoFecharRef.current = null;
          depois();
        }}
      >
        <AlertDialogHeader>
          <AlertDialogTitle>{pedido?.titulo}</AlertDialogTitle>
          {pedido?.descricao && <AlertDialogDescription>{pedido.descricao}</AlertDialogDescription>}
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>{pedido?.voltar ?? 'Voltar'}</AlertDialogCancel>
          <AlertDialogAction
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            onClick={() => { confirmouRef.current = true; const a = pedido?.acao; setPedido(null); a?.(); }}
          >
            {pedido?.confirmar}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );

  return { pedir, dialogo };
}
