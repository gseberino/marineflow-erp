import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Navigation, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';

/**
 * "Estou a caminho" (padrão Jobber/Housecall — reduz no-show): mensagem ao cliente
 * da OS, SEMPRE com confirmação explícita, respeitando o modo de teste do WhatsApp.
 */
export function OnMyWayButton({ order }: { order: any }) {
  const [open, setOpen] = useState(false);
  const [sending, setSending] = useState(false);
  const clientName = order.clients?.name || 'o cliente';

  const send = async () => {
    setSending(true);
    try {
      const { data: os, error } = await supabase
        .from('service_orders')
        .select('id, service_order_number, clients(name, phone, whatsapp), vessels(name)')
        .eq('id', order.id)
        .single();
      if (error) throw error;
      const phone = String((os as any).clients?.whatsapp || (os as any).clients?.phone || '').replace(/\D/g, '');
      if (!phone || phone.length < 10) { toast.error('Cliente sem telefone cadastrado.'); return; }

      const { data: settings } = await supabase
        .from('app_settings').select('key, value')
        .in('key', ['wa_test_mode', 'wa_test_number', 'zapi_test_mode', 'zapi_test_number']);
      const map = Object.fromEntries((settings || []).map((s: any) => [s.key, s.value]));
      const testMode = (map['wa_test_mode'] ?? map['zapi_test_mode']) === 'true';
      const testNumber = String(map['wa_test_number'] ?? map['zapi_test_number'] ?? '').replace(/\D/g, '');
      if (testMode && !testNumber) { toast.error('Modo de teste ativo sem número de teste configurado.'); return; }

      const { error: qErr } = await supabase.from('whatsapp_send_queue').insert({
        phone_normalized: testMode ? testNumber : phone,
        message: `Olá${(os as any).clients?.name ? `, ${(os as any).clients.name}` : ''}! Nossa equipe está a caminho para o atendimento` +
          `${(os as any).vessels?.name ? ` (${(os as any).vessels.name})` : ''}. Até já! — HBR Marine`,
        source: 'on-my-way',
        source_ref_id: order.id,
        priority: 3,
      });
      if (qErr) throw qErr;
      toast.success(testMode ? 'Mensagem enfileirada (modo de teste — vai para o número de teste)' : 'Cliente avisado: equipe a caminho');
      setOpen(false);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao enviar');
    } finally {
      setSending(false);
    }
  };

  return (
    <>
      <Button
        size="sm"
        variant="outline"
        className="h-6 px-2 text-[11px]"
        onClick={(e) => { e.stopPropagation(); setOpen(true); }}
        title="Avisar o cliente que a equipe está a caminho"
      >
        <Navigation className="h-3 w-3 mr-1" /> A caminho
      </Button>
      <span onClick={(e) => e.stopPropagation()}>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogContent className="max-w-sm">
            <DialogHeader>
              <DialogTitle>Avisar {clientName}?</DialogTitle>
            </DialogHeader>
            <p className="text-sm text-muted-foreground">
              Envia agora, por WhatsApp, que a equipe está a caminho do atendimento da OS {order.service_order_number}.
            </p>
            <DialogFooter>
              <Button variant="outline" onClick={() => setOpen(false)} disabled={sending}>Cancelar</Button>
              <Button onClick={send} disabled={sending}>
                {sending && <Loader2 className="h-4 w-4 animate-spin mr-1" />} Enviar
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </span>
    </>
  );
}
