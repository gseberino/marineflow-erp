import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useMarkCollectionPaid, type Collection } from '@/hooks/use-collections';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  collection: Collection | null;
}

export function PaymentConfirmDialog({ open, onOpenChange, collection }: Props) {
  const [amount, setAmount] = useState('');
  const [method, setMethod] = useState('pix');
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [confirmedBy, setConfirmedBy] = useState<'manual' | 'whatsapp'>('manual');
  const [notes, setNotes] = useState('');
  const mutate = useMarkCollectionPaid();

  useEffect(() => {
    if (collection) setAmount(String(collection.amount));
  }, [collection]);

  if (!collection) return null;

  const handleConfirm = async () => {
    await mutate.mutateAsync({
      id: collection.id,
      paid_amount: Number(amount),
      paid_method: method,
      payment_date: date,
      confirmed_by: confirmedBy,
      notes: notes || undefined,
    });
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader><DialogTitle>Confirmar Pagamento</DialogTitle></DialogHeader>
        <div className="grid gap-4 py-2">
          <div className="space-y-2">
            <Label>Valor recebido (R$)</Label>
            <Input type="number" step="0.01" value={amount} onChange={e => setAmount(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Método</Label>
              <Select value={method} onValueChange={setMethod}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="pix">PIX</SelectItem>
                  <SelectItem value="card">Cartão</SelectItem>
                  <SelectItem value="cash">Dinheiro</SelectItem>
                  <SelectItem value="transfer">Transferência</SelectItem>
                  <SelectItem value="other">Outro</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Data</Label>
              <Input type="date" value={date} onChange={e => setDate(e.target.value)} />
            </div>
          </div>
          <div className="space-y-2">
            <Label>Confirmado por</Label>
            <Select value={confirmedBy} onValueChange={(v: any) => setConfirmedBy(v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="manual">Manual</SelectItem>
                <SelectItem value="whatsapp">WhatsApp</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>Observações</Label>
            <Textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleConfirm} disabled={mutate.isPending}>
            {mutate.isPending ? 'Confirmando...' : 'Confirmar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
