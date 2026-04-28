import { useState, useEffect, useRef } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { ScanBarcode, PackagePlus, AlertCircle } from 'lucide-react';
import { useProducts } from '@/hooks/use-products';
import { toast } from 'sonner';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onProductScanned: (product: any) => void;
}

export function BarcodeScannerModal({ open, onOpenChange, onProductScanned }: Props) {
  const [barcode, setBarcode] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);
  const { data: products } = useProducts();

  // Focus input automatically
  useEffect(() => {
    if (open) {
      setTimeout(() => inputRef.current?.focus(), 100);
    } else {
      setBarcode('');
    }
  }, [open]);

  const handleScan = (e: React.FormEvent) => {
    e.preventDefault();
    if (!barcode.trim()) return;
    
    const product = products?.find(p => p.barcode === barcode || p.sku === barcode);
    if (product) {
      toast.success(`Produto localizado: ${product.product_name}`);
      onProductScanned(product);
      setBarcode('');
      // Mantém o foco para o próximo bip
      inputRef.current?.focus();
    } else {
      toast.error('Código não encontrado no sistema.');
      setBarcode('');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md text-center p-6">
        <DialogHeader>
          <DialogTitle className="text-center text-xl flex items-center justify-center gap-2">
            <ScanBarcode className="h-6 w-6 text-primary" />
            Leitor de Código de Barras
          </DialogTitle>
        </DialogHeader>
        
        <div className="py-8 space-y-4">
          <div className="animate-pulse bg-primary/10 p-4 rounded-full w-24 h-24 mx-auto flex items-center justify-center">
            <ScanBarcode className="h-12 w-12 text-primary" />
          </div>
          
          <p className="text-muted-foreground text-sm">
            Posicione o cursor no campo abaixo e utilize o leitor físico, ou digite o código manualmente.
          </p>

          <form onSubmit={handleScan} className="flex gap-2 max-w-sm mx-auto">
            <Input 
              ref={inputRef}
              value={barcode}
              onChange={(e) => setBarcode(e.target.value)}
              placeholder="Ex: 7891234567890"
              className="text-center font-mono text-lg"
              autoComplete="off"
              autoFocus
            />
            <Button type="submit">Buscar</Button>
          </form>
        </div>
      </DialogContent>
    </Dialog>
  );
}
