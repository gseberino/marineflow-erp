import { useEffect, useState } from 'react';
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
 *
 * Agenda de Produção, Fase 5 (P6): com a mensagem ao cliente ligada E a confirmação na onda ligada
 * (agenda_config.modo_cliente = 'ligado' e 'confirmar' em cliente_tipos_ligados), o banco não manda na
 * hora: registra a confirmação pela agenda, que sai no horário de mensagens ao cliente e dentro do
 * limite por cliente (o aviso depois do clique diz quando). Fora disso — desligado, em teste ou com a
 * confirmação ainda fora das ondas — vai na hora, como antes. O texto do diálogo diz qual dos dois
 * acontece; quando a tela não consegue ler o modo, diz os dois. O comportamento é todo do banco.
 */

/** Como o pedido sai, pelo que a tela leu de agenda_config. */
export type ComoSaiAConfirmacao = 'agenda' | 'agora' | 'agora_em_teste' | 'agora_sem_onda' | 'nao_sei';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Cliente = any;

/**
 * Lê o modo da mensagem ao cliente. A tabela (ou a coluna da Fase 5) que ainda não existe = a função de
 * antes, que manda na hora; sem linha (o login não lê agenda_config) ou outro erro = não sei. Nunca lança.
 */
export async function lerComoSaiAConfirmacao(db: Cliente): Promise<ComoSaiAConfirmacao> {
  try {
    const { data, error } = await db.from('agenda_config').select('modo_cliente, cliente_tipos_ligados').maybeSingle();
    if (error) {
      const code = (error as { code?: unknown }).code;
      return code === 'PGRST205' || code === '42P01' || code === '42703' || code === 'PGRST204' ? 'agora' : 'nao_sei';
    }
    if (!data) return 'nao_sei';
    const tipos: unknown = data.cliente_tipos_ligados;
    const comConfirmacao = Array.isArray(tipos) && tipos.includes('confirmar');
    if (data.modo_cliente === 'ligado') return comConfirmacao ? 'agenda' : 'agora_sem_onda';
    if (data.modo_cliente === 'sombra') return 'agora_em_teste';
    return 'agora';
  } catch {
    return 'nao_sei';
  }
}

const DEPOIS = 'Quando ele responder SIM, a OS fica confirmada e esta tarefa se fecha sozinha.';

export function textoDoPedido(como: ComoSaiAConfirmacao): string {
  switch (como) {
    case 'agenda':
      return 'A confirmação ao cliente agora é da agenda: a mensagem com o dia do atendimento, pedindo para ele responder '
        + 'SIM, sai no horário de mensagens ao cliente e dentro do limite de mensagens por cliente — agora, ou no próximo '
        + 'horário que couber. O aviso depois do clique diz quando ela sai. ' + DEPOIS;
    case 'agora_em_teste':
      return 'Vai agora, pelo WhatsApp da HBR, a mensagem com o dia e a hora do atendimento pedindo para o cliente responder '
        + 'SIM. As mensagens automáticas da agenda ao cliente estão em teste, mas este pedido sai de verdade. ' + DEPOIS;
    case 'agora_sem_onda':
      return 'Vai agora, pelo WhatsApp da HBR, a mensagem com o dia e a hora do atendimento pedindo para o cliente responder '
        + 'SIM (a confirmação automática da agenda ainda não está ligada, então este pedido sai como antes). ' + DEPOIS;
    case 'agora':
      return 'Vai agora, pelo WhatsApp da HBR, a mensagem com o dia e a hora do atendimento pedindo para o cliente responder '
        + 'SIM. ' + DEPOIS;
    default:
      return 'A mensagem com o dia do atendimento, pedindo para o cliente responder SIM, vai pelo WhatsApp da HBR: na hora, '
        + 'ou no próximo horário de mensagens ao cliente quando a agenda cuida da confirmação. O aviso depois do clique diz '
        + 'o que aconteceu. ' + DEPOIS;
  }
}

export function PedirConfirmacaoButton({ osId }: { osId: string }) {
  const [aberto, setAberto] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [como, setComo] = useState<ComoSaiAConfirmacao>('nao_sei');

  // o modo é lido ao abrir o diálogo (muda com as ondas; nada é lido sem o dono abrir)
  useEffect(() => {
    if (!aberto) return;
    let vivo = true;
    lerComoSaiAConfirmacao(supabase).then((c) => { if (vivo) setComo(c); });
    return () => { vivo = false; };
  }, [aberto]);

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
              <DialogDescription>{textoDoPedido(como)}</DialogDescription>
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
