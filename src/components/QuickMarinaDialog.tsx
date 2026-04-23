import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useCreateMarina, type Marina } from '@/hooks/use-marinas';
import { toast } from 'sonner';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initialName?: string;
  onCreated: (marina: Marina) => void;
}

export function QuickMarinaDialog({ open, onOpenChange, initialName = '', onCreated }: Props) {
  const [name, setName] = useState(initialName);
  const [city, setCity] = useState('');
  const [state, setState] = useState('');
  const create = useCreateMarina();

  useEffect(() => {
    if (open) {
      setName(initialName);
      setCity('');
      setState('');
    }
  }, [open, initialName]);

  const handleSave = async () => {
    if (!name.trim()) {
      toast.error('Nome da marina é obrigatório');
      return;
    }
    try {
      const created = await create.mutateAsync({
        marina_name: name.trim(),
        city: city.trim() || null,
        state: state.trim() || null,
        active: true,
      });
      toast.success('Marina cadastrada com sucesso. Complete o cadastro em Marinas.');
      onCreated(created as Marina);
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao cadastrar marina');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Cadastro rápido de marina</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>Nome da marina *</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} autoFocus />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Cidade</Label>
              <Input value={city} onChange={(e) => setCity(e.target.value)} />
            </div>
            <div>
              <Label>Estado</Label>
              <Input value={state} onChange={(e) => setState(e.target.value)} maxLength={2} />
            </div>
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
