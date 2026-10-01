/**
 * Cancelar NF-e e Carta de Correção (CC-e): justificativa + confirmação, cada um com o próprio
 * texto. Saíram de FiscalEmission.tsx no D33 (01/10/2026). Montados por nota (key = id): antes o
 * texto morava na tela, e o motivo digitado para uma nota aparecia ao abrir o cancelamento de
 * outra (o cancelamento só limpava o texto ao fechar pelo X, não pelo "Voltar").
 */
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import { supabase } from '@/integrations/supabase/client';
import { extractInvokeErrorMessage } from '@/lib/invoke-error';
import { MIN_JUSTIFICATION_LENGTH, tempoDesdeAAutorizacao } from '@/lib/fiscal-justificativa';

interface Props<A> {
  alvo: A;
  /** A tela marca a linha da nota como ocupada enquanto o pedido corre. */
  ocupado: boolean;
  marcarOcupado: (id: string, busy: boolean) => void;
  onClose: () => void;
}

export function CancelarNotaDialog({ alvo, ocupado, marcarOcupado, onClose }: Props<{ id: string; authorized_at?: string | null }>) {
  const qc = useQueryClient();
  const cancelTarget = alvo;
  const [cancelReason, setCancelReason] = useState('');

  const handleConfirmCancel = async () => {
    if (!cancelTarget || cancelReason.trim().length < MIN_JUSTIFICATION_LENGTH) return;
    marcarOcupado(cancelTarget.id, true);
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', {
        body: { action: 'cancel', document_id: cancelTarget.id, reason: cancelReason.trim() },
      });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) throw new Error(data.error);
      toast.success('Cancelamento solicitado. Acompanhe o status.');
      marcarOcupado(cancelTarget.id, false);
      onClose();
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
    } catch (e) {
      const err = e as Error;
      toast.error('Erro ao cancelar: ' + err.message);
      marcarOcupado(cancelTarget.id, false);
    }
  };

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Cancelar NF-e</DialogTitle>
          <DialogDescription>Informe o motivo do cancelamento (a SEFAZ exige pelo menos {MIN_JUSTIFICATION_LENGTH} caracteres).</DialogDescription>
        </DialogHeader>
        {(() => {
          // Janela padrão de cancelamento sem ônus: 24h após a autorização.
          const desde = tempoDesdeAAutorizacao(cancelTarget?.authorized_at);
          if (!desde) return null;
          return !desde.dentroDoPrazo ? (
            <p className="text-xs text-destructive bg-destructive/10 rounded-md p-2">
              ⚠ Já se passaram {Math.floor(desde.horas)}h da autorização — o prazo de 24h para cancelamento sem ônus
              venceu. A SEFAZ pode recusar o cancelamento; se for só corrigir um dado, use a CC-e.
            </p>
          ) : (
            <p className="text-xs text-muted-foreground">
              Dentro do prazo de 24h (autorizada há {desde.texto}).
            </p>
          );
        })()}
        <Textarea value={cancelReason} onChange={(e) => setCancelReason(e.target.value)} placeholder="Ex.: Erro de digitação no endereço do destinatário" />
        <p className={`text-xs ${cancelReason.trim().length < MIN_JUSTIFICATION_LENGTH ? 'text-muted-foreground' : 'text-success'}`}>
          {cancelReason.trim().length}/{MIN_JUSTIFICATION_LENGTH} caracteres mínimos
        </p>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Voltar</Button>
          <Button
            variant="destructive"
            disabled={cancelReason.trim().length < MIN_JUSTIFICATION_LENGTH || ocupado}
            onClick={handleConfirmCancel}
          >
            {ocupado ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
            Confirmar Cancelamento
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function CartaDeCorrecaoDialog({ alvo, ocupado, marcarOcupado, onClose }: Props<{ id: string; number?: number; series?: number }>) {
  const qc = useQueryClient();
  const correctionTarget = alvo;
  const [correctionText, setCorrectionText] = useState('');

  // Carta de Correção Eletrônica (CC-e): corrige erros que NÃO alteram valores,
  // impostos, destinatário ou datas (ex.: endereço, observações). Prazo legal
  // de 30 dias. O backend (action="correction") exige nota autorizada + mínimo
  // de 15 caracteres.
  const handleConfirmCorrection = async () => {
    if (!correctionTarget || correctionText.trim().length < MIN_JUSTIFICATION_LENGTH) return;
    marcarOcupado(correctionTarget.id, true);
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', {
        body: { action: 'correction', document_id: correctionTarget.id, text: correctionText.trim() },
      });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) throw new Error(data.error);
      toast.success('Carta de Correção enviada. Acompanhe o status.');
      marcarOcupado(correctionTarget.id, false);
      onClose();
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
    } catch (e) {
      const err = e as Error;
      toast.error('Erro ao enviar a correção: ' + err.message);
      marcarOcupado(correctionTarget.id, false);
    }
  };

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Carta de Correção — NF-e {correctionTarget?.series}/{correctionTarget?.number}</DialogTitle>
          <DialogDescription>
            Corrija erros que <strong>não</strong> alteram valores, impostos, destinatário ou datas (ex.: endereço,
            informações complementares). Prazo legal: 30 dias da emissão.
          </DialogDescription>
        </DialogHeader>
        <Textarea
          value={correctionText}
          onChange={(e) => setCorrectionText(e.target.value)}
          placeholder="Ex.: No campo Informações Complementares, onde se lê X, leia-se Y."
          rows={4}
        />
        <p className={`text-xs ${correctionText.trim().length < MIN_JUSTIFICATION_LENGTH ? 'text-muted-foreground' : 'text-success'}`}>
          {correctionText.trim().length}/{MIN_JUSTIFICATION_LENGTH} caracteres mínimos
        </p>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Voltar</Button>
          <Button
            disabled={correctionText.trim().length < MIN_JUSTIFICATION_LENGTH || ocupado}
            onClick={handleConfirmCorrection}
          >
            {ocupado ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
            Enviar Correção
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
