// Desagrupar orçamentos (15/10/2026). Desfaz um agrupamento enquanto o agrupado ainda é um orçamento em
// aberto (não virou OS, não foi assinado, sem dinheiro ligado). Os originais voltam como estavam, com o link
// antigo; o agrupado fica cancelado como histórico. O que foi editado no agrupado NÃO volta — o aviso diz isso
// com todas as letras antes do clique. Quem confere tudo é o banco (desagrupar_orcamentos).
import { useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { AlertTriangle, Loader2, Undo2 } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { useDesagruparOrcamento } from '@/hooks/use-agrupar-orcamentos';

interface Props {
  aberto: boolean;
  onFechar: () => void;
  agrupadoId: string;
  agrupadoNumero: string;
  origens: Array<{ id: string; numero: string }>;
}

export function DesagruparOrcamentoDialog({ aberto, onFechar, agrupadoId, agrupadoNumero, origens }: Props) {
  const navigate = useNavigate();
  const desagrupar = useDesagruparOrcamento();
  const [erro, setErro] = useState<string | null>(null);
  // Trava o clique duplo antes mesmo de o isPending chegar à tela.
  const enviando = useRef(false);
  const ocupado = desagrupar.isPending;
  const numeros = origens.map((o) => o.numero).join(', ');

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
          toast.success(`Desagrupado: ${voltaram} voltaram a valer; ${r.agrupado || agrupadoNumero} foi cancelado`);
          fechar();
          const primeiro = r.origens_ids?.[0] ?? origens[0]?.id;
          if (primeiro) navigate(`/v2/service-orders/${primeiro}`);
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
      <DialogContent className="max-h-[92vh] w-[calc(100vw-2rem)] max-w-lg overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Undo2 className="h-5 w-5 text-primary" /> Desagrupar {agrupadoNumero}
          </DialogTitle>
          <DialogDescription>
            {agrupadoNumero} reúne {numeros || 'outros orçamentos'}. Desagrupar desfaz isso.
          </DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-3 text-sm">
          <ul className="list-disc space-y-1 pl-5">
            <li>
              {origens.length === 1 ? `${numeros} volta` : `${numeros} voltam`} a valer exatamente como
              {origens.length === 1 ? ' estava' : ' estavam'}, com o link antigo.
            </li>
            <li>{agrupadoNumero} fica cancelado como histórico e o link dele para de funcionar.</li>
          </ul>

          <div className="flex items-start gap-2 rounded-md border border-warning/50 bg-warning/10 p-3">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
            <p className="min-w-0 break-words">
              <strong>As alterações feitas no {agrupadoNumero} não voltam</strong> para os originais: itens, preços e
              textos mudados depois do agrupamento ficam só no {agrupadoNumero} cancelado.
            </p>
          </div>

          {erro && (
            <p role="alert" className="break-words rounded-md border border-destructive/40 p-3 text-destructive">
              {erro}
            </p>
          )}
        </div>

        <DialogFooter className="gap-2 sm:gap-0">
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
