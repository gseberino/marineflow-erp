/**
 * Converter orçamento em OS SEM sinal — o valor inteiro fica para a conclusão (27/10/2026).
 *
 * Caso real: orçamento adicional de um cliente com serviço em andamento, em que tudo se acerta no
 * final. Antes, o funil só saía de "Aprovado"/"Aguardando sinal" recebendo um sinal maior que zero.
 *
 * O que a confirmação faz, nesta ordem:
 *  1. troca a condição de pagamento para "100% na entrega" (lib condicao-na-conclusao) e marca o
 *     orçamento como aprovado — sem isso a OS ficaria "aguardando sinal" com o botão de registrar;
 *  2. converte pelo mesmo caminho do "Converter em OS" (ORÇ→OS, valor orçado preservado);
 *  3. abre o aviso de necessidade de compra.
 * As contas a receber nascem na conclusão (ensureCompletionReceivables), vencendo no dia.
 */
import { useCallback, useState } from 'react';
import { toast } from 'sonner';
import { useQueryClient } from '@tanstack/react-query';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { supabase } from '@/integrations/supabase/client';
import type { Json } from '@/integrations/supabase/types';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { useUpdateServiceOrderStatus } from '@/hooks/use-service-orders';
import { usePaymentConditionPresets } from '@/hooks/use-payment-conditions';
import { usePurchaseNeedsPrompt } from '@/hooks/use-purchase-needs-prompt';
import { condicaoTudoNaConclusao, type CondicaoGravada } from '@/lib/condicao-na-conclusao';

interface Alvo {
  id: string;
  number?: string | null;
  client?: string | null;
  grandTotal?: number;
}

interface Opcoes {
  /** Depois de gravar: a tela aberta aplica a condição no próprio estado. Sem isto, uma edição
      não salva dos campos de condição venceria a releitura (mesclarReleitura) e voltaria a
      condição antiga no próximo salvar. */
  aoConverter?: (condicao: CondicaoGravada) => void;
}

const brl = (n: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(n);

export function useConverterSemSinal({ aoConverter }: Opcoes = {}) {
  const qc = useQueryClient();
  const updateStatus = useUpdateServiceOrderStatus();
  const { data: presets } = usePaymentConditionPresets();
  const { promptIfConverted, dialog: avisoDeCompra } = usePurchaseNeedsPrompt();
  const [alvo, setAlvo] = useState<Alvo | null>(null);
  const [assinado, setAssinado] = useState(false);
  const [convertendo, setConvertendo] = useState(false);

  // Orçamento assinado com outra condição: trocar a condição pede assinatura nova — a
  // confirmação avisa antes (a mesma regra da definir_condicao_pagamento do assistente).
  const pedir = useCallback((a: Alvo) => {
    setAssinado(false);
    setAlvo(a);
    supabase.from('service_orders').select('signed_at').eq('id', a.id).maybeSingle()
      .then(({ data }) => setAssinado(!!data?.signed_at), () => {});
  }, []);

  const converter = async () => {
    if (!alvo) return;
    setConvertendo(true);
    try {
      const condicao = condicaoTudoNaConclusao(presets);
      const { error } = await supabase
        .from('service_orders')
        .update({
          ...condicao,
          custom_payment_installments: condicao.custom_payment_installments as unknown as Json,
          quote_status: 'approved',
        })
        .eq('id', alvo.id);
      if (error) throw error;
      aoConverter?.(condicao);
      await writeAuditLog({
        table_name: 'service_orders',
        record_id: alvo.id,
        action: 'update',
        new_value: { ...condicao, quote_status: 'approved', motivo: 'convertido sem sinal' },
      });

      const res = await updateStatus.mutateAsync({ id: alvo.id, status: 'approved' });
      const numero: string | null | undefined = res?.service_order_number || alvo.number;
      toast.success(`${numero} convertido em OS — pagamento integral na conclusão`);
      qc.invalidateQueries({ queryKey: ['pdf-data'] });
      promptIfConverted(res, { id: alvo.id, number: numero, client: alvo.client });
      setAlvo(null);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Erro ao converter em OS');
    } finally {
      setConvertendo(false);
    }
  };

  const dialogo = (
    <>
      <AlertDialog open={!!alvo} onOpenChange={(aberto) => { if (!aberto && !convertendo) setAlvo(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Converter {alvo?.number || 'o orçamento'} em OS sem sinal?</AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-2 text-sm text-muted-foreground">
                <p>
                  O serviço começa sem entrada. O valor inteiro
                  {alvo?.grandTotal ? <> (<strong className="text-foreground">{brl(alvo.grandTotal)}</strong>)</> : null}
                  {' '}fica para ser cobrado na conclusão.
                </p>
                <p>
                  A condição de pagamento passa a ser <strong className="text-foreground">100% na entrega</strong> —
                  é o que sai no PDF e na conta a receber.
                </p>
                {assinado && (
                  <p className="text-amber-700">
                    Este orçamento foi assinado com a condição anterior: com a troca, o cliente
                    precisa assinar de novo.
                  </p>
                )}
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={convertendo}>Voltar</AlertDialogCancel>
            <AlertDialogAction
              disabled={convertendo}
              onClick={(e) => { e.preventDefault(); converter(); }}
            >
              {convertendo ? 'Convertendo…' : 'Converter sem sinal'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      {avisoDeCompra}
    </>
  );

  return { pedir, dialogo, convertendo };
}
