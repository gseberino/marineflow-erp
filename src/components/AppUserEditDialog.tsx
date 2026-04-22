import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useUpdateAppUser, USER_ROLES } from '@/hooks/use-app-users';
import { maskPhone, maskCEP } from '@/lib/masks';
import { useAddress } from '@/hooks/use-address';
import { toast } from 'sonner';
import { Loader2 } from 'lucide-react';

interface AppUser {
  id: string;
  full_name: string;
  email: string;
  role: string;
  phone?: string | null;
  active: boolean;
  postal_code?: string | null;
  address_line_1?: string | null;
  address_number?: string | null;
  address_complement?: string | null;
  neighborhood?: string | null;
  city?: string | null;
  state?: string | null;
  country?: string | null;
  notes?: string | null;
}

interface Props {
  user: AppUser | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  isCurrentUserAdmin: boolean;
}

export function AppUserEditDialog({ user, open, onOpenChange, isCurrentUserAdmin }: Props) {
  const updateUser = useUpdateAppUser();
  const { fetchByCep, cepLoading } = useAddress();
  const [form, setForm] = useState<AppUser | null>(null);

  useEffect(() => {
    if (user) setForm({ ...user });
  }, [user]);

  if (!form) return null;

  const set = (k: keyof AppUser, v: any) => setForm(p => p ? { ...p, [k]: v } : p);

  const handleCepBlur = async () => {
    const digits = (form.postal_code || '').replace(/\D/g, '');
    if (digits.length === 8) {
      const r = await fetchByCep(digits);
      if (r) {
        setForm(p => p ? {
          ...p,
          address_line_1: r.logradouro || p.address_line_1,
          neighborhood: r.bairro || p.neighborhood,
          city: r.localidade || p.city,
          state: r.uf || p.state,
        } : p);
      }
    }
  };

  const handleSave = async () => {
    if (!form.full_name.trim() || !form.email.trim()) {
      toast.error('Nome e email são obrigatórios');
      return;
    }
    try {
      await updateUser.mutateAsync({
        id: form.id,
        full_name: form.full_name.trim(),
        email: form.email.trim(),
        phone: form.phone || null,
        role: form.role,
        active: form.active,
        postal_code: form.postal_code || null,
        address_line_1: form.address_line_1 || null,
        address_number: form.address_number || null,
        address_complement: form.address_complement || null,
        neighborhood: form.neighborhood || null,
        city: form.city || null,
        state: form.state || null,
        country: form.country || null,
        notes: form.notes || null,
      });
      toast.success('Usuário atualizado');
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e.message || 'Erro ao salvar');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Editar usuário — {form.full_name}</DialogTitle>
        </DialogHeader>

        <Tabs defaultValue="basic" className="w-full">
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="basic">Dados Básicos</TabsTrigger>
            <TabsTrigger value="address">Endereço</TabsTrigger>
            <TabsTrigger value="permissions">Permissões</TabsTrigger>
          </TabsList>

          <TabsContent value="basic" className="space-y-3 pt-4">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>Nome *</Label>
                <Input value={form.full_name} onChange={e => set('full_name', e.target.value)} />
              </div>
              <div>
                <Label>Email *</Label>
                <Input type="email" value={form.email} onChange={e => set('email', e.target.value)} />
              </div>
              <div>
                <Label>Telefone</Label>
                <Input
                  value={form.phone || ''}
                  onChange={e => set('phone', maskPhone(e.target.value))}
                  placeholder="(47) 99999-9999"
                  maxLength={15}
                />
              </div>
              <div className="flex items-end gap-2">
                <Switch checked={form.active} onCheckedChange={v => set('active', v)} />
                <Label>Usuário ativo</Label>
              </div>
            </div>
            <div>
              <Label>Observações internas</Label>
              <Textarea
                value={form.notes || ''}
                onChange={e => set('notes', e.target.value)}
                rows={3}
                placeholder="Notas sobre o usuário..."
              />
            </div>
          </TabsContent>

          <TabsContent value="address" className="space-y-3 pt-4">
            <div className="grid grid-cols-3 gap-3">
              <div>
                <Label>CEP</Label>
                <div className="relative">
                  <Input
                    value={form.postal_code || ''}
                    onChange={e => set('postal_code', maskCEP(e.target.value))}
                    onBlur={handleCepBlur}
                    placeholder="00000-000"
                    maxLength={9}
                  />
                  {cepLoading && <Loader2 className="absolute right-2 top-1/2 -translate-y-1/2 h-4 w-4 animate-spin text-muted-foreground" />}
                </div>
              </div>
              <div className="col-span-2">
                <Label>Logradouro</Label>
                <Input value={form.address_line_1 || ''} onChange={e => set('address_line_1', e.target.value)} />
              </div>
              <div>
                <Label>Número</Label>
                <Input value={form.address_number || ''} onChange={e => set('address_number', e.target.value)} />
              </div>
              <div className="col-span-2">
                <Label>Complemento</Label>
                <Input value={form.address_complement || ''} onChange={e => set('address_complement', e.target.value)} />
              </div>
              <div>
                <Label>Bairro</Label>
                <Input value={form.neighborhood || ''} onChange={e => set('neighborhood', e.target.value)} />
              </div>
              <div>
                <Label>Cidade</Label>
                <Input value={form.city || ''} onChange={e => set('city', e.target.value)} />
              </div>
              <div>
                <Label>Estado (UF)</Label>
                <Input value={form.state || ''} onChange={e => set('state', e.target.value.toUpperCase().slice(0, 2))} maxLength={2} />
              </div>
              <div className="col-span-3">
                <Label>País</Label>
                <Input value={form.country || ''} onChange={e => set('country', e.target.value)} />
              </div>
            </div>
          </TabsContent>

          <TabsContent value="permissions" className="space-y-3 pt-4">
            <div className="rounded-lg border bg-muted/30 p-3 text-sm space-y-2">
              <p><strong>Função do usuário</strong> — define o nível de acesso no sistema.</p>
              <ul className="text-xs text-muted-foreground space-y-1 list-disc pl-4">
                <li><strong>Administrador:</strong> acesso total, gerencia usuários, configurações e financeiro.</li>
                <li><strong>Técnico:</strong> executa OS, registra horas e despesas.</li>
                <li><strong>Financeiro:</strong> gestão de cobranças, pagamentos e conciliação.</li>
                <li><strong>Vendedor / Indicador:</strong> aparece em OS para comissionamento.</li>
                <li><strong>Outro:</strong> acesso padrão, sem permissões administrativas.</li>
              </ul>
            </div>
            <div>
              <Label>Função *</Label>
              <Select
                value={form.role}
                onValueChange={v => set('role', v)}
                disabled={!isCurrentUserAdmin}
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {USER_ROLES.map(r => <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>)}
                </SelectContent>
              </Select>
              {!isCurrentUserAdmin && (
                <p className="text-xs text-muted-foreground mt-1">
                  Apenas administradores podem alterar funções.
                </p>
              )}
            </div>
          </TabsContent>
        </Tabs>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave} disabled={updateUser.isPending}>
            {updateUser.isPending ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : null}
            Salvar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
