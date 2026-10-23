// "Guardar <quem pagou> como quem paga por <cliente>" — leva 8 (22/10/2026, "siga pelo recomendado").
//
// Nasce de uma linha do Extrato: a fila perguntou "de quem é este pagamento?", alguém escolheu o cliente, e quem
// pagou não é ele (a empresa dele, o cônjuge, a marina). Em vez de uma regra "documento → cliente" — que a fila
// passava a usar como se fosse o cliente —, o pagador fica guardado na ficha do cliente com a RELAÇÃO dita por
// quem guardou, e volta como SUGESTÃO com motivo ("Pago pelo cônjuge de X — confira"), pedindo o SIM em cada
// pagamento. Quem grava é o banco (guardar_pagadores_do_cliente, com auth.uid()): o documento e o nome saem da
// linha do banco, nunca desta tela; administrador grava confirmado (é o SIM do dono), financeiro grava proposto.
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useOptionalAuth } from '@/hooks/use-auth';
import { useClientesParaReceita } from '@/hooks/use-payees';
import { useReaplicarRegras } from '@/hooks/use-finance-review';
import {
  documentoMascarado, nomeSemCpf, pedeRevisarFila, podeVerPagadores, RELACOES_DO_PAGADOR, ROTULO_DA_RELACAO,
  useGuardarPagadores, type RelacaoDoPagador,
} from '@/hooks/use-pagadores-do-cliente';

/** O que a tela sabe da linha e do cliente escolhido. O documento e o nome são só para MOSTRAR. */
export interface PedidoDeGuardarPagador {
  clientId: string;
  /** Sem ele, o diálogo procura no cadastro. */
  clienteNome?: string | null;
  bankTransactionId: string;
  pagadorNome: string | null;
  pagadorDocumento: string | null;
  origem?: 'fila' | 'historico';
}

/** Quem pode guardar (e ver CPF de terceiro): administrador e financeiro. */
export function usePodeGuardarPagador(): boolean {
  return podeVerPagadores(useOptionalAuth()?.user?.role);
}

export function GuardarPagadorDialog({
  pedido, onFechar, onSoCategoria,
}: {
  pedido: PedidoDeGuardarPagador;
  onFechar: () => void;
  /**
   * "Virar regra" de uma entrada com cliente escolhido abre este diálogo; quem só queria ensinar a CATEGORIA deste
   * documento segue por aqui (regra de entrada sem cliente).
   */
  onSoCategoria?: () => void;
}) {
  const cargo = useOptionalAuth()?.user?.role;
  const admin = cargo === 'admin';
  const guardar = useGuardarPagadores();
  const revisarFila = useReaplicarRegras();
  const { data: clientes = [] } = useClientesParaReceita(!pedido.clienteNome);
  const nomeDoCliente = pedido.clienteNome || clientes.find((c) => c.id === pedido.clientId)?.name || null;
  // O nome como o banco escreveu pode trazer o CPF ("12345678901-MARIA"): na tela, mascarado como o documento.
  const quem = nomeSemCpf(pedido.pagadorNome?.trim()) || 'Quem pagou';
  const doc = documentoMascarado(pedido.pagadorDocumento);
  const tipoDoc = (pedido.pagadorDocumento ?? '').replace(/\D/g, '').length === 14 ? 'CNPJ' : 'CPF';

  const [relacao, setRelacao] = useState<RelacaoDoPagador | ''>('');
  const [observacao, setObservacao] = useState('');

  const salvar = () => {
    if (!relacao) return;
    guardar.mutate([{
      client_id: pedido.clientId,
      bank_transaction_id: pedido.bankTransactionId,
      relacao,
      observacao: observacao.trim() || null,
      origem: pedido.origem ?? 'fila',
    }], {
      onSuccess: (r) => {
        // Confirmado muda o que a fila sugere: as linhas pendentes deste documento são refeitas agora ("Revisar a
        // fila", em silêncio), não só na varredura diária. Proposto pelo financeiro não muda nada.
        if (pedeRevisarFila(r)) revisarFila.mutate({ silencioso: true });
        // Recusado pelo banco (documento do próprio cliente, de outro cliente…): o motivo já saiu no aviso, e o
        // diálogo fica aberto para quem quiser trocar a relação ou cancelar.
        if (r.gravados.length > 0) onFechar();
      },
    });
  };

  return (
    <Dialog open onOpenChange={(v) => { if (!v) onFechar(); }}>
      <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{nomeDoCliente ? `Guardar quem paga por ${nomeDoCliente}` : 'Guardar quem paga pelo cliente'}</DialogTitle>
          <DialogDescription>
            <b>{quem}</b>{doc ? ` (${tipoDoc} ${doc})` : ''} pagou {nomeDoCliente ? <>por <b>{nomeDoCliente}</b></> : 'pelo cliente escolhido'}.
            Guardado, o próximo pagamento dele chega na fila com {nomeDoCliente ? `a sugestão "${nomeDoCliente}"` : 'o cliente sugerido'} e
            o motivo — e ainda pede o seu SIM em cada pagamento. Nada é baixado sozinho.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div>
            <Label htmlFor="pagador-relacao">Quem é para o cliente? *</Label>
            <Select value={relacao} onValueChange={(v) => setRelacao(v as RelacaoDoPagador)}>
              <SelectTrigger id="pagador-relacao" aria-label="Quem é para o cliente?">
                <SelectValue placeholder="Escolher a relação" />
              </SelectTrigger>
              <SelectContent>
                {RELACOES_DO_PAGADOR.map((r) => (
                  <SelectItem key={r} value={r}>{ROTULO_DA_RELACAO[r]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label htmlFor="pagador-observacao">Observação (opcional)</Label>
            <Input
              id="pagador-observacao" value={observacao} maxLength={500}
              placeholder="ex.: paga as mensalidades da marina"
              onChange={(e) => setObservacao(e.target.value)}
            />
          </div>
          <p className="rounded-md bg-muted/50 p-2 text-xs text-muted-foreground">
            {admin
              ? 'Você é o administrador: o pagador fica confirmado (é o seu SIM).'
              : 'Fica proposto: o administrador confirma na ficha do cliente antes de a fila usar.'}
            {' '}O CPF/CNPJ e o nome saem da linha do banco, não do que se digita aqui.
          </p>
        </div>

        <DialogFooter className="gap-2">
          {onSoCategoria && (
            <Button variant="ghost" className="h-auto whitespace-normal sm:mr-auto" onClick={onSoCategoria}>
              Só a categoria (regra sem cliente)
            </Button>
          )}
          <Button variant="outline" onClick={onFechar}>Cancelar</Button>
          <Button onClick={salvar} disabled={!relacao || guardar.isPending}>
            {guardar.isPending ? 'Guardando…' : 'Guardar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
