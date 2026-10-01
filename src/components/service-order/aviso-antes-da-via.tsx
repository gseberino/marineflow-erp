import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';

/**
 * Aviso antes de imprimir a via do técnico: o que vai faltar no papel.
 *
 * O escritório decide se completa ou imprime assim. Quem paga pela lacuna é o técnico,
 * que no barco ou no motorhome não pode ligar para perguntar.
 */
export function AvisoAntesDaVia({
  faltas, onImprimir, onFechar,
}: {
  faltas: string[] | null;
  onImprimir: () => void;
  onFechar: () => void;
}) {
  return (
    <AlertDialog open={!!faltas && faltas.length > 0} onOpenChange={(aberto) => { if (!aberto) onFechar(); }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>A via vai sair sem:</AlertDialogTitle>
          <AlertDialogDescription asChild>
            <div className="space-y-2 text-sm">
              <ul className="list-disc space-y-0.5 pl-5">
                {(faltas ?? []).map((f) => <li key={f}>{f}</li>)}
              </ul>
              <p>
                No local, o técnico não vai ter a quem perguntar. Completar agora costuma levar menos
                tempo que uma viagem perdida.
              </p>
            </div>
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Voltar e completar</AlertDialogCancel>
          <AlertDialogAction onClick={onImprimir}>Imprimir assim</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
