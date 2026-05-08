import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useCreateSupplier, type Supplier } from '@/hooks/use-suppliers';
import { maskPhone } from '@/lib/masks';
import { toast } from 'sonner';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initialName?: string;
  onCreated: (supplier: Supplier) => void;
}

export function QuickSupplierDialog({ open, onOpenChange, initialName = '', onCreated }: Props) {
  const [name, setName] = useState(initialName);
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const create = useCreateSupplier();

  useEffect(() => {
    if (open) {
      setName(initialName);
      setPhone('');
      setEmail('');
    }
  }, [open, initialName]);

  const handleSave = async () => {
    if (!name.trim()) {
      toast.error('Nome do fornecedor é obrigatório');
      return;
    }
    try {
      const created = await create.mutateAsync({
        supplier_name: name.trim(),
        contact_phone: phone.trim() || null,
        contact_email: email.trim() || null,
        active: true,
      });
      toast.success('Fornecedor cadastrado. Complete o cadastro em Fornecedores.');
      onCreated(created as Supplier);
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao cadastrar fornecedor');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Cadastro rápido de fornecedor</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>Nome do fornecedor *</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} autoFocus />
          </div>
          <div>
            <Label>Telefone</Label>
            <Input value={phone} onChange={(e) => setPhone(maskPhone(e.target.value))} placeholder="(47) 99999-9999" maxLength={15} />
          </div>
          <div>
            <Label>E-mail</Label>
            <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave} disabled={create.isPending}>
            {create.isPending ? 'Salvando...' : 'Salvar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
