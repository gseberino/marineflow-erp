import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useUpdateCollection, type Collection } from '@/hooks/use-collections';
import { maskPhone } from '@/lib/masks';

interface Props { open: boolean; onOpenChange: (v: boolean) => void; collection: Collection | null }

export function EditContactDialog({ open, onOpenChange, collection }: Props) {
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [whatsapp, setWhatsapp] = useState('');
  const update = useUpdateCollection();

  useEffect(() => {
    if (collection) {
      setName(collection.contact_name || '');
      setPhone(collection.phone || '');
      setWhatsapp(collection.contact_whatsapp || '');
    }
  }, [collection]);

  if (!collection) return null;

  const handleSave = async () => {
    await update.mutateAsync({
      id: collection.id,
      patch: { contact_name: name, phone: phone, contact_whatsapp: whatsapp },
    });
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader><DialogTitle>Alterar Contato</DialogTitle></DialogHeader>
        <div className="grid gap-4 py-2">
          <div className="space-y-2">
            <Label>Nome</Label>
            <Input value={name} onChange={e => setName(e.target.value)} />
          </div>
          <div className="space-y-2">
            <Label>Telefone</Label>
            <Input value={phone} onChange={e => setPhone(maskPhone(e.target.value))} />
          </div>
          <div className="space-y-2">
            <Label>WhatsApp</Label>
            <Input value={whatsapp} onChange={e => setWhatsapp(maskPhone(e.target.value))} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave} disabled={update.isPending}>Salvar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
