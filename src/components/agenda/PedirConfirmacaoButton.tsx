import { useState } from 'react';
import { MessageCircleQuestion, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';

/**
 * "Pedir confirmação" na tarefa R15 da Agenda (decisão do dono, 30/09/2026: "quero assim").
 * Manda ao cliente a mensagem pedindo SIM, pela função do banco (pedir_confirmacao_do_agendamento:
 * confere OS agendada, telefone, opt-out e modo de teste). Nada sai sem este clique. Quando o
 * cliente responde SIM, a OS fica confirmada para aquela data e a tarefa se fecha sozinha.
 */
export function PedirConfirmacaoButton({ osId }: { osId: string }) {
  const [aberto, setAberto] = useState(false);
  const [enviando, setEnviando] = useState(false);

  const enviar = async () => {
    setEnviando(true);
    try {
      const { data, error } = await supabase.rpc('pedir_confirmacao_do_agendamento' as never, { p_os: osId } as never);
      if (error) throw error;
      toast.success(String((data as unknown as { message?: string })?.message ?? 'Pedido de confirmação enviado.'));
      setAberto(false);
    } catch (e) {
      toast.error((e as Error)?.message || 'Não deu para enviar o pedido de confirmação.');
    } finally {
      setEnviando(false);
    }
  };

  return (
    <>
      <Button
        size="sm"
        variant="outline"
        className="h-6 px-2 text-[11px] border-primary/40 text-primary hover:bg-primary/10"
        onClick={(e) => { e.stopPropagation(); setAberto(true); }}
      >
        <MessageCircleQuestion className="mr-1 h-3 w-3" /> Pedir confirmação
      </Button>
      <span onClick={(e) => e.stopPropagation()}>
        <Dialog open={aberto} onOpenChange={setAberto}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Pedir confirmação ao cliente</DialogTitle>
              <DialogDescription>
                Vai agora, pelo WhatsApp da HBR, a mensagem com o dia e a hora do atendimento pedindo para o
                cliente responder SIM. Quando ele responder, a OS fica confirmada e esta tarefa se fecha sozinha.
              </DialogDescription>
            </DialogHeader>
            <DialogFooter>
              <Button variant="ghost" onClick={() => setAberto(false)} disabled={enviando}>Cancelar</Button>
              <Button onClick={enviar} disabled={enviando}>
                {enviando && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Enviar pedido
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </span>
    </>
  );
}
