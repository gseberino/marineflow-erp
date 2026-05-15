import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { MoneyInput } from '@/components/MoneyInput';
import { useCreateProduct, type Product } from '@/hooks/use-products';
import { toast } from 'sonner';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initialName?: string;
  onCreated: (product: Product) => void;
}

export function QuickProductDialog({ open, onOpenChange, initialName = '', onCreated }: Props) {
  const [name, setName] = useState(initialName);
  const [salePrice, setSalePrice] = useState(0);
  const create = useCreateProduct();

  useEffect(() => {
    if (open) {
      setName(initialName);
      setSalePrice(0);
    }
  }, [open, initialName]);

  const handleSave = async () => {
    if (!name.trim()) {
      toast.error('Nome é obrigatório');
      return;
    }
    try {
      const created = await create.mutateAsync({
        product_name: name.trim(),
        sale_price: salePrice,
        cost_price: 0,
        unit: 'pcs',
        stock_quantity: 0,
        minimum_stock: 0,
        active: true,
        sale_currency: 'BRL',
        cost_currency: 'BRL',
      } as any);
      toast.success('Produto cadastrado e adicionado à OS. Complete o cadastro em Produtos.');
      onCreated(created as Product);
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao cadastrar produto');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Cadastro rápido de produto</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>Nome *</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} autoFocus />
          </div>
          <div>
            <Label>Preço de Venda</Label>
            <MoneyInput value={salePrice} onValueChange={setSalePrice} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave} disabled={create.isPending}>
            {create.isPending ? 'Salvando...' : 'Salvar e adicionar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
