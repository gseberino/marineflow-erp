import { useEffect, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { MoneyInput } from '@/components/MoneyInput';
import { useCreateProduct } from '@/hooks/use-products';
import { toast } from 'sonner';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  initialName?: string;
  /** Called with the newly created product after a successful insert */
  onCreated: (product: { id: string; product_name: string; sale_price: number; cost_price: number }) => void;
}

/**
 * Minimal product creation dialog used inline in the Service Order form.
 * Only requires Name + Sale Price — all other fields use defaults.
 */
export function QuickProductDialog({ open, onOpenChange, initialName = '', onCreated }: Props) {
  const create = useCreateProduct();
  const [name, setName] = useState(initialName);
  const [salePrice, setSalePrice] = useState(0);

  useEffect(() => {
    if (open) {
      setName(initialName);
      setSalePrice(0);
    }
  }, [open, initialName]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) {
      toast.error('Informe o nome do produto.');
      return;
    }
    if (salePrice <= 0) {
      toast.error('Informe o preço de venda.');
      return;
    }
    try {
      const created = await create.mutateAsync({
        product_name: trimmed,
        sale_price: salePrice,
        cost_price: 0,
        active: true,
        unit: 'pcs',
        cost_currency: 'BRL',
        sale_currency: 'BRL',
        stock_quantity: 0,
        minimum_stock: 0,
      });
      onCreated({
        id: (created as any).id,
        product_name: (created as any).product_name,
        sale_price: Number((created as any).sale_price) || 0,
        cost_price: Number((created as any).cost_price) || 0,
      });
      toast.success('Produto cadastrado e adicionado à OS. Complete o cadastro em Produtos.');
      onOpenChange(false);
    } catch (err: any) {
      toast.error(err?.message || 'Erro ao cadastrar produto.');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Cadastro rápido de produto</DialogTitle>
          <DialogDescription>
            Cadastre apenas o essencial. Complete os demais campos depois em Produtos.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-3">
          <div>
            <Label>Nome *</Label>
            <Input
              required
              autoFocus
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Nome do produto"
            />
          </div>
          <div>
            <Label>Preço de Venda *</Label>
            <MoneyInput value={salePrice} onValueChange={setSalePrice} />
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancelar
            </Button>
            <Button type="submit" disabled={create.isPending}>
              {create.isPending ? 'Salvando...' : 'Cadastrar e adicionar'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
