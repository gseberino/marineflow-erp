import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useUpdateAppUser, USER_ROLES, type AppUser } from '@/hooks/use-app-users';
import { maskPhone, maskCEP, maskCPF, maskMoney, parseMoney, formatMoneyFromNumber } from '@/lib/masks';
import { useAddress } from '@/hooks/use-address';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Loader2, User, Home, Shield, Briefcase, DollarSign, Key, Mail } from 'lucide-react';

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
        ...form,
        full_name: form.full_name.trim(),
        email: form.email.trim(),
      });
      toast.success('Usuário atualizado');
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e.message || 'Erro ao salvar');
    }
  };

  const handleResetPassword = async () => {
    try {
      await supabase.auth.resetPasswordForEmail(form.email, {
        redirectTo: window.location.origin + '/reset-password',
      });
      toast.success(`Link de recuperação enviado para ${form.email}`);
    } catch {
      toast.error('Erro ao enviar email');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Editar usuário — {form.full_name}</DialogTitle>
        </DialogHeader>

        <Tabs defaultValue="basic" className="w-full">
          <TabsList className="grid w-full grid-cols-5 h-auto py-1">
            <TabsTrigger value="basic" className="flex flex-col py-2 gap-1">
              <User className="h-4 w-4" />
              <span className="text-[10px]">Básico</span>
            </TabsTrigger>
            <TabsTrigger value="address" className="flex flex-col py-2 gap-1">
              <Home className="h-4 w-4" />
              <span className="text-[10px]">Endereço</span>
            </TabsTrigger>
            <TabsTrigger value="hr" className="flex flex-col py-2 gap-1">
              <Briefcase className="h-4 w-4" />
              <span className="text-[10px]">RH/ID</span>
            </TabsTrigger>
            <TabsTrigger value="finance" className="flex flex-col py-2 gap-1">
              <DollarSign className="h-4 w-4" />
              <span className="text-[10px]">Financeiro</span>
            </TabsTrigger>
            <TabsTrigger value="permissions" className="flex flex-col py-2 gap-1">
              <Shield className="h-4 w-4" />
              <span className="text-[10px]">Acesso</span>
            </TabsTrigger>
          </TabsList>

          <TabsContent value="basic" className="space-y-3 pt-4">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>Nome Completo *</Label>
                <Input value={form.full_name} onChange={e => set('full_name', e.target.value)} />
              </div>
              <div>
                <Label>Email *</Label>
                <Input type="email" value={form.email} onChange={e => set('email', e.target.value)} />
              </div>
              <div>
                <Label>WhatsApp/Celular</Label>
                <Input
                  value={form.phone || ''}
                  onChange={e => set('phone', maskPhone(e.target.value))}
                  placeholder="(47) 99999-9999"
                  maxLength={15}
                />
              </div>
              <div className="flex items-end gap-2 pb-2">
                <Switch checked={form.active} onCheckedChange={v => set('active', v)} />
                <Label>Acesso Ativo</Label>
              </div>
            </div>
            <div>
              <Label>Observações Internas (RH/Gestão)</Label>
              <Textarea
                value={form.notes || ''}
                onChange={e => set('notes', e.target.value)}
                rows={3}
                placeholder="Observações sobre o colaborador..."
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
            </div>
          </TabsContent>

          <TabsContent value="hr" className="space-y-3 pt-4">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>CPF</Label>
                <Input 
                  value={form.cpf || ''} 
                  onChange={e => set('cpf', maskCPF(e.target.value))} 
                  placeholder="000.000.000-00"
                />
              </div>
              <div>
                <Label>RG</Label>
                <Input value={form.rg || ''} onChange={e => set('rg', e.target.value)} />
              </div>
              <div>
                <Label>Data de Nascimento</Label>
                <Input type="date" value={form.birth_date || ''} onChange={e => set('birth_date', e.target.value)} />
              </div>
              <div>
                <Label htmlFor="hiring_date">Data de Admissão</Label>
                <Input id="hiring_date" type="date" value={form.hiring_date || ''} onChange={e => set('hiring_date', e.target.value)} />
              </div>
              <div>
                <Label htmlFor="resignation_date">Data de Desligamento</Label>
                <Input id="resignation_date" type="date" value={form.resignation_date || ''} onChange={e => set('resignation_date', e.target.value)} />
              </div>
              <div className="col-span-2">
                <Label>Departamento / Área</Label>
                <Input 
                  value={form.department || ''} 
                  onChange={e => set('department', e.target.value)} 
                  placeholder="Ex: Comercial, Manutenção, Financeiro"
                />
              </div>
            </div>
          </TabsContent>

          <TabsContent value="finance" className="space-y-3 pt-4">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>Salário Base (R$)</Label>
                <Input 
                  value={formatMoneyFromNumber(form.salary_base || 0)} 
                  onChange={e => set('salary_base', parseMoney(e.target.value))} 
                />
              </div>
              <div>
                <Label>Chave PIX (Para Pagamentos)</Label>
                <Input 
                  value={form.pix_key || ''} 
                  onChange={e => set('pix_key', e.target.value)} 
                  placeholder="E-mail, CPF, Telefone ou Aleatória"
                />
              </div>
              <div className="col-span-2 p-3 bg-muted/30 rounded-lg border border-dashed mt-2">
                <p className="text-xs font-semibold mb-2">Contato de Emergência</p>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label className="text-[10px]">Nome do Contato</Label>
                    <Input 
                      value={form.emergency_contact_name || ''} 
                      onChange={e => set('emergency_contact_name', e.target.value)} 
                    />
                  </div>
                  <div>
                    <Label className="text-[10px]">Telefone de Emergência</Label>
                    <Input 
                      value={form.emergency_contact_phone || ''} 
                      onChange={e => set('emergency_contact_phone', maskPhone(e.target.value))} 
                    />
                  </div>
                </div>
              </div>
            </div>
          </TabsContent>

          <TabsContent value="permissions" className="space-y-4 pt-4">
            <div className="space-y-4">
              <div>
                <Label htmlFor="user-role">Cargo / Nível de Acesso *</Label>
                <Select
                  value={form.role}
                  onValueChange={v => set('role', v)}
                  disabled={!isCurrentUserAdmin}
                >
                  <SelectTrigger id="user-role"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {USER_ROLES.map(r => <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>

              <div className="grid grid-cols-1 gap-4">
                <p className="text-xs font-semibold text-muted-foreground uppercase">Capacidades deste cargo:</p>
                <div className="space-y-2">
                  {form.role === 'admin' && (
                    <div className="text-[11px] p-2 bg-primary/5 rounded border border-primary/10 space-y-1">
                      <p>✅ <strong>Acesso Total:</strong> Pode gerenciar usuários, financeiro e configurações.</p>
                      <p>✅ <strong>Dashboard:</strong> Visão completa de todas as métricas da empresa.</p>
                    </div>
                  )}
                  {form.role === 'financial' && (
                    <div className="text-[11px] p-2 bg-blue-50 rounded border border-blue-100 space-y-1 text-blue-800">
                      <p>✅ <strong>Financeiro:</strong> Pode gerenciar contas a pagar/receber e cobranças.</p>
                      <p>✅ <strong>Vendas:</strong> Pode visualizar e converter orçamentos.</p>
                      <p>❌ <strong>Sistema:</strong> Não pode alterar configurações globais.</p>
                    </div>
                  )}
                  {form.role === 'technician' && (
                    <div className="text-[11px] p-2 bg-slate-50 rounded border border-slate-200 space-y-1 text-slate-700">
                      <p>✅ <strong>Operacional:</strong> Pode executar OS e ver agenda.</p>
                      <p>❌ <strong>Financeiro:</strong> Não tem acesso a valores ou cobranças.</p>
                    </div>
                  )}
                  {form.role === 'external_seller' && (
                    <div className="text-[11px] p-2 bg-amber-50 rounded border border-amber-100 space-y-1 text-amber-800">
                      <p>✅ <strong>Vendas:</strong> Pode criar e acompanhar seus próprios orçamentos.</p>
                      <p>❌ <strong>Operacional:</strong> Não visualiza OS de terceiros nem agenda.</p>
                    </div>
                  )}
                </div>

                {isCurrentUserAdmin && (
                  <div className="space-y-3 pt-2 border-t">
                    <p className="text-xs font-semibold text-muted-foreground uppercase">Liberar Áreas do Menu (Personalizado):</p>
                    <div className="grid grid-cols-2 gap-2">
                      {[
                        { id: 'operacional', label: 'Operacional' },
                        { id: 'vendas-externas', label: 'Vendas Externas' },
                        { id: 'cadastros', label: 'Cadastros' },
                        { id: 'financeiro', label: 'Financeiro' },
                        { id: 'whatsapp', label: 'WhatsApp' },
                        { id: 'sistema', label: 'Sistema' },
                      ].map((area) => {
                        const metadata = form.metadata || {};
                        const currentAreas = metadata.visible_areas || [];
                        const isChecked = currentAreas.includes(area.id);
                        
                        return (
                          <div key={area.id} className="flex items-center gap-2 p-2 rounded border bg-muted/20">
                            <Switch 
                              checked={isChecked} 
                              onCheckedChange={(checked) => {
                                let newAreas = checked 
                                  ? [...currentAreas, area.id]
                                  : currentAreas.filter((p: string) => p !== area.id);
                                
                                newAreas = [...new Set(newAreas.filter((p: any) => p))];
                                set('metadata', { ...metadata, visible_areas: newAreas });
                              }} 
                            />
                            <span className="text-[11px] font-medium">{area.label}</span>
                          </div>
                        );
                      })}
                    </div>
                    <p className="text-[10px] text-muted-foreground italic">
                      * Se nenhuma área for selecionada, o sistema usará as permissões padrão do cargo.
                    </p>
                  </div>
                )}
              </div>

              <div className="rounded-lg border bg-amber-50/50 border-amber-100 p-4 space-y-3">
                <div className="flex items-center gap-2 text-amber-800 font-semibold text-sm">
                  <Key className="h-4 w-4" />
                  Acesso ao Sistema
                </div>
                <p className="text-xs text-amber-700">
                  O usuário utiliza o e-mail <strong>{form.email}</strong> para entrar. Se ele esqueceu a senha ou você deseja forçar a criação de uma nova, use o botão abaixo.
                </p>
                <Button 
                  variant="outline" 
                  size="sm" 
                  className="w-full bg-white border-amber-200 text-amber-700 hover:bg-amber-50"
                  onClick={handleResetPassword}
                >
                  <Mail className="h-3.5 w-3.5 mr-1" />
                  Enviar Link de Recuperação de Senha
                </Button>
              </div>
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
