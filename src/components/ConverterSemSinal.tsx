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
 *
 * JÁ FOI FEITO (18/11/2026, OS-00129): a confirmação mostra a data do orçamento e, com sinal de serviço já feito
 * (lib sinais-de-ja-feito, a mesma regra do cartão do assistente), avisa. Com "O serviço já foi feito" marcado, o passo 2
 * vai à porta direto em concluída (ela converte e conclui numa chamada só), com a saída no dia informado: a OS não entra na
 * agenda (nenhum dia, nenhuma ficha ao técnico) e a cobrança nasce na conclusão. Sem o aviso de compra (o serviço acabou).
 */
import { useCallback, useState } from 'react';
import { toast } from 'sonner';
import { useQueryClient } from '@tanstack/react-query';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import type { Json } from '@/integrations/supabase/types';
import { useUpdateServiceOrderStatus } from '@/hooks/use-service-orders';
import { usePaymentConditionPresets } from '@/hooks/use-payment-conditions';
import { usePurchaseNeedsPrompt } from '@/hooks/use-purchase-needs-prompt';
import { condicaoTudoNaConclusao, type CondicaoGravada } from '@/lib/condicao-na-conclusao';
import {
  dataComIdade, diaEmBrasilia, diaFeitoValido, motivoDoAviso, saidaDoDia, sinaisDeJaFeito, type SinaisDeJaFeito,
} from '@/lib/sinais-de-ja-feito';

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

/** O que já entrou nas contas a receber do orçamento. null = não deu para conferir (não vira R$ 0). */
async function lerRecebido(id: string): Promise<number | null> {
  const { data, error } = await supabase.from('receivables').select('paid_amount, status').eq('service_order_id', id);
  if (error) return null;
  return (data ?? []).filter((r) => r.status !== 'cancelled').reduce((s, r) => s + (Number(r.paid_amount) || 0), 0);
}

export function useConverterSemSinal({ aoConverter }: Opcoes = {}) {
  const qc = useQueryClient();
  const updateStatus = useUpdateServiceOrderStatus();
  const { data: presets } = usePaymentConditionPresets();
  const { promptIfConverted, dialog: avisoDeCompra } = usePurchaseNeedsPrompt();
  const [alvo, setAlvo] = useState<Alvo | null>(null);
  const [assinado, setAssinado] = useState(false);
  const [convertendo, setConvertendo] = useState(false);
  const [sinais, setSinais] = useState<SinaisDeJaFeito | null>(null);
  const [jaFeito, setJaFeito] = useState(false);
  const [diaFeito, setDiaFeito] = useState('');

  // Orçamento assinado com outra condição: trocar a condição pede assinatura nova — a
  // confirmação avisa antes (a mesma regra da definir_condicao_pagamento do assistente).
  // (18/11/2026) Na mesma leitura, os sinais de serviço já feito (data, notas, check-in/saída, dinheiro recebido).
  const pedir = useCallback((a: Alvo) => {
    setAssinado(false);
    setSinais(null);
    setJaFeito(false);
    setDiaFeito(diaEmBrasilia(new Date()));
    setAlvo(a);
    Promise.all([
      supabase.from('service_orders')
        .select('signed_at, created_at, technician_notes, diagnosis, check_in_at, check_out_at')
        .eq('id', a.id).maybeSingle(),
      lerRecebido(a.id),
    ]).then(([{ data }, recebido]) => {
      setAssinado(!!data?.signed_at);
      if (data) {
        setSinais(sinaisDeJaFeito({
          criadoEm: data.created_at, technicianNotes: data.technician_notes, diagnosis: data.diagnosis,
          checkInAt: data.check_in_at, checkOutAt: data.check_out_at, recebido,
        }, new Date()));
      }
    }, () => {});
  }, []);

  const converter = async () => {
    if (!alvo) return;
    if (jaFeito && !diaFeitoValido(diaFeito, new Date())) {
      toast.error('Diga o dia em que o serviço foi feito (até hoje).');
      return;
    }
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
      // Sem writeAuditLog manual: o gatilho do histórico (migration 20270121100000) já grava este update com o valor de
      // ANTES e quem fez — a linha manual só duplicava, e sem o antes.

      const res = await updateStatus.mutateAsync(jaFeito
        ? { id: alvo.id, status: 'completed', checkOut: saidaDoDia(diaFeito) }
        : { id: alvo.id, status: 'approved' });
      // Agenda (Fase 3): o status vai pela porta, que devolve o número depois da conversão em `numero` (só o prefixo troca).
      const numero: string | null | undefined = res?.numero || alvo.number;
      qc.invalidateQueries({ queryKey: ['pdf-data'] });
      if (jaFeito) {
        toast.success(`${numero} convertido e concluído — não entra na agenda. A cobrança nasceu agora.`);
      } else {
        toast.success(`${numero} convertido em OS — pagamento integral na conclusão`);
        promptIfConverted(res, { id: alvo.id, number: numero, client: alvo.client });
      }
      setAlvo(null);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Erro ao converter em OS');
    } finally {
      setConvertendo(false);
    }
  };

  const dataDoOrcamento = sinais ? dataComIdade(sinais) : null;
  const motivo = sinais ? motivoDoAviso(sinais) : null;
  const hoje = diaEmBrasilia(new Date());

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
                {dataDoOrcamento && <p>Orçamento de {dataDoOrcamento}.</p>}
                {motivo && !jaFeito && (
                  <p className="rounded-md border border-amber-300 bg-amber-50 p-2 text-amber-800 dark:border-amber-700 dark:bg-amber-950 dark:text-amber-200">
                    Atenção: {motivo}. Se o serviço já foi feito, marque abaixo — a OS nasce concluída e não entra na agenda.
                  </p>
                )}
                {assinado && (
                  <p className="text-amber-700">
                    Este orçamento foi assinado com a condição anterior: com a troca, o cliente
                    precisa assinar de novo.
                  </p>
                )}
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <div className="space-y-3">
            <div className="flex items-center gap-2">
              <Checkbox
                id="converter-ja-feito"
                checked={jaFeito}
                disabled={convertendo}
                onCheckedChange={(v) => setJaFeito(v === true)}
              />
              <Label htmlFor="converter-ja-feito" className="cursor-pointer">O serviço já foi feito</Label>
            </div>
            {jaFeito && (
              <div className="space-y-1">
                <Label htmlFor="converter-dia-feito">Feito em</Label>
                <Input
                  id="converter-dia-feito"
                  type="date"
                  value={diaFeito}
                  max={hoje}
                  disabled={convertendo}
                  onChange={(e) => setDiaFeito(e.target.value)}
                  className="w-44"
                />
                <p className="text-xs text-muted-foreground">
                  A OS nasce concluída nesse dia: nenhum dia na agenda, nenhuma ficha ao técnico. A cobrança nasce agora.
                </p>
              </div>
            )}
          </div>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={convertendo}>Voltar</AlertDialogCancel>
            <AlertDialogAction
              disabled={convertendo}
              onClick={(e) => { e.preventDefault(); converter(); }}
            >
              {convertendo ? 'Convertendo…' : jaFeito ? 'Converter já concluída' : 'Converter sem sinal'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      {avisoDeCompra}
    </>
  );

  return { pedir, dialogo, convertendo };
}
