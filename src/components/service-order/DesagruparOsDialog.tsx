// Desagrupar ORDENS DE SERVIÇO (28/10/2026). Desfaz um agrupamento enquanto a OS agrupada ainda não começou a
// ser executada. As originais voltam como estavam, com o link antigo, e o que o agrupar levou delas (sinais,
// contas a receber, cobranças, tarefas, compras) volta para cada uma; a agrupada fica cancelada como histórico.
// O que foi acrescentado ou editado na agrupada NÃO volta — o aviso diz isso com todas as letras antes do
// clique. Quem confere tudo é o banco (desagrupar_os).
import { useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { AlertTriangle, Loader2, Undo2 } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { useDesagruparOs } from '@/hooks/use-agrupar-os';

interface Props {
  aberto: boolean;
  onFechar: () => void;
  agrupadoId: string;
  agrupadoNumero: string;
  origens: Array<{ id: string; numero: string }>;
}

export function DesagruparOsDialog({ aberto, onFechar, agrupadoId, agrupadoNumero, origens }: Props) {
  const navigate = useNavigate();
  const desagrupar = useDesagruparOs();
  const [erro, setErro] = useState<string | null>(null);
  const enviando = useRef(false);
  const ocupado = desagrupar.isPending;
  const numeros = origens.map((o) => o.numero).join(', ');
  const uma = origens.length === 1;

  const fechar = () => {
    setErro(null);
    onFechar();
  };

  const confirmar = () => {
    if (enviando.current || ocupado) return;
    enviando.current = true;
    setErro(null);
    desagrupar.mutate(
      { p_agrupado: agrupadoId },
      {
        onSuccess: (r) => {
          const voltaram = r.origens?.length ? r.origens.join(', ') : numeros;
          const varias = (r.origens?.length ?? origens.length) !== 1;
          toast.success(`Desagrupado: ${voltaram} ${varias ? 'voltaram' : 'voltou'} a valer; ${r.agrupado || agrupadoNumero} foi cancelada`);
          fechar();
          const primeira = r.origens_ids?.[0] ?? origens[0]?.id;
          if (primeira) navigate(`/v2/service-orders/${primeira}`);
        },
        onError: (e) => {
          setErro(e.message);
          toast.error(e.message);
        },
        onSettled: () => {
          enviando.current = false;
        },
      },
    );
  };

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && !ocupado && fechar()}>
      <DialogContent className="max-h-[92dvh] w-[calc(100vw-2rem)] max-w-lg overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Undo2 className="h-5 w-5 text-primary" /> Desagrupar {agrupadoNumero}
          </DialogTitle>
          <DialogDescription>
            {agrupadoNumero} reúne {numeros || 'outras OS'}. Desagrupar desfaz isso.
          </DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-3 text-sm">
          <ul className="list-disc space-y-1 pl-5">
            <li>
              {numeros} {uma ? 'volta' : 'voltam'} a valer como {uma ? 'estava' : 'estavam'} antes do agrupamento, com o
              link antigo.
            </li>
            <li>
              Sinais, contas a receber, cobranças, tarefas e pedidos de compra que vieram {uma ? 'dela' : 'delas'} voltam
              para {uma ? 'ela' : 'cada uma'}, sem mudar valor nem situação.
            </li>
            <li>{agrupadoNumero} fica cancelada como histórico e o link dela para de funcionar.</li>
          </ul>

          <div className="flex items-start gap-2 rounded-md border border-warning/50 bg-warning/10 p-3">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
            <p className="min-w-0 break-words">
              <strong>As alterações feitas na {agrupadoNumero} não voltam</strong> para as originais: itens, preços, textos
              e técnicos acrescentados depois do agrupamento ficam só na {agrupadoNumero} cancelada.
            </p>
          </div>

          <p className="text-muted-foreground">
            Só dá para desagrupar enquanto a {agrupadoNumero} não começou a ser executada (sem hora apontada, despesa,
            foto, baixa de estoque, nota fiscal nem assinatura do cliente nela).
          </p>

          {erro && (
            <p role="alert" className="break-words rounded-md border border-destructive/40 p-3 text-destructive">
              {erro}
            </p>
          )}
        </div>

        <DialogFooter className="gap-2 pb-[env(safe-area-inset-bottom)] sm:gap-0">
          <Button variant="outline" onClick={fechar} disabled={ocupado}>
            Cancelar
          </Button>
          <Button variant="destructive" onClick={confirmar} disabled={ocupado} className="gap-1.5">
            {ocupado && <Loader2 className="h-4 w-4 animate-spin" />}
            Desagrupar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
