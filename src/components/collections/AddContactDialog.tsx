import { useState } from 'react';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useAddCollectionContact, type CollectionContactType } from '@/hooks/use-collections';

interface Props { open: boolean; onOpenChange: (v: boolean) => void; collectionId: string }

const TYPES: { value: CollectionContactType; label: string }[] = [
  { value: 'whatsapp_sent',   label: '📱 WhatsApp enviado' },
  { value: 'call_answered',   label: '📞 Ligou — atendeu' },
  { value: 'call_no_answer',  label: '📞 Ligou — não atendeu' },
  { value: 'manual_note',     label: '📝 Anotação manual' },
  { value: 'payment_promised',label: '🤝 Prometeu pagar' },
  { value: 'paid',            label: '✅ Pagamento confirmado' },
];

export function AddContactDialog({ open, onOpenChange, collectionId }: Props) {
  const [type, setType] = useState<CollectionContactType>('manual_note');
  const [notes, setNotes] = useState('');
  const [promised, setPromised] = useState('');
  const add = useAddCollectionContact();

  const handleSave = async () => {
    await add.mutateAsync({
      collection_id: collectionId,
      contact_type: type,
      notes: notes || undefined,
      promised_date: type === 'payment_promised' ? promised || null : null,
    });
    setNotes(''); setPromised(''); setType('manual_note');
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader><DialogTitle>Registrar Contato</DialogTitle></DialogHeader>
        <div className="grid gap-4 py-2">
          <div className="space-y-2">
            <Label>Tipo de contato</Label>
            <Select value={type} onValueChange={(v: any) => setType(v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {TYPES.map(t => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>Observações</Label>
            <Textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3} />
          </div>
          {type === 'payment_promised' && (
            <div className="space-y-2">
              <Label>Prometeu pagar em</Label>
              <Input type="date" value={promised} onChange={e => setPromised(e.target.value)} />
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave} disabled={add.isPending}>Salvar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
