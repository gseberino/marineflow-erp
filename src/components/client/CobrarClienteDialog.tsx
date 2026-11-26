// "Cobrar o cliente" pela tela (dono, 26/11/2026: "1. A" — os botões sem trava ganham a mesma conferência, com prévia).
// O botão da linha em Contas a Receber e o da aba Cobranças abrem ESTE diálogo, que lê o cadastro (o destino é o
// WhatsApp dele, nunca um número digitado) e as contas do cliente, e mostra o ClientStatementDialog no modo "cobranca":
// a mensagem com tudo que ele tem em aberto, as travas da ficha (genérico, piso, entrada esperando no Extrato, opt-out,
// telefone, horário), o aviso de quem já foi cobrado hoje e o registro da cobrança do dia depois do envio.
// Antes, a linha abria o envio livre (número editável, mensagem sem valor) e a aba Cobranças enviava no clique.
import { AlertTriangle, Loader2 } from 'lucide-react';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { ClientStatementDialog } from '@/components/ClientStatementDialog';
import { useCadastroParaCobrar, useContasDoCliente } from '@/hooks/use-contas-do-cliente';

interface Props {
  /** O cliente a cobrar; null = fechado. */
  clienteId: string | null;
  onFechar: () => void;
}

export function CobrarClienteDialog({ clienteId, onFechar }: Props) {
  const aberto = !!clienteId;
  const cadastro = useCadastroParaCobrar(clienteId, aberto);
  const contas = useContasDoCliente(clienteId, aberto);
  if (!aberto) return null;

  if (cadastro.data && contas.data) {
    return (
      <ClientStatementDialog
        open
        onOpenChange={(v) => { if (!v) onFechar(); }}
        cliente={cadastro.data}
        items={contas.data}
        modo="cobranca"
      />
    );
  }

  const erro = cadastro.error || contas.error;
  const naoAchou = !erro && cadastro.isSuccess && cadastro.data === null;
  return (
    <Dialog open onOpenChange={(v) => { if (!v) onFechar(); }}>
      <DialogContent className="max-w-md" data-testid="cobrar-cliente-carregando">
        <DialogHeader>
          <DialogTitle>Cobrar o cliente</DialogTitle>
          <DialogDescription>A mensagem e as travas aparecem antes de enviar — nada sai sem confirmar.</DialogDescription>
        </DialogHeader>
        {erro || naoAchou ? (
          <p role="alert" className="flex gap-2 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
            <span className="min-w-0 break-words">
              {naoAchou
                ? 'Este cliente não foi encontrado no cadastro. Nada foi enviado.'
                : `${(erro as Error).message || 'Não consegui ler o cliente.'} Nada foi enviado; tente de novo.`}
            </span>
          </p>
        ) : (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Conferindo o cadastro e as contas do cliente…
          </p>
        )}
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>Fechar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
