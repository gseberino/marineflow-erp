// Aba "UsersTab" de Configurações. Extraída de SettingsPage.tsx em 20/09/2026 (o arquivo
// tinha 1.981 linhas); comportamento idêntico, só mudou de endereço.
import { useState } from 'react';
import { useI18n } from '@/i18n';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Users, Mail, Pencil } from 'lucide-react';
import { AppUserEditDialog } from '@/components/AppUserEditDialog';
import { useAuth } from '@/hooks/use-auth';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useAppUsers as useAppUsersHook, useCreateAppUser, useUpdateAppUser, USER_ROLES } from '@/hooks/use-app-users';
import { Switch } from '@/components/ui/switch';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { maskPhone } from '@/lib/masks';

export function UsersTab() {
  const { t } = useI18n();
  const { user: currentUser } = useAuth();
  const isCurrentUserAdmin = currentUser?.role === 'admin';
  const { data: users, isLoading } = useAppUsersHook();
  const createUser = useCreateAppUser();
  const updateUser = useUpdateAppUser();
  const [showNew, setShowNew] = useState(false);
  const [editingUser, setEditingUser] = useState<any | null>(null);
  const [newForm, setNewForm] = useState({
    full_name: '', email: '', role: 'technician', phone: '', department: '',
  });

  const handleCreate = async () => {
    if (!newForm.full_name || !newForm.email) {
      toast.error('Nome e email são obrigatórios'); return;
    }
    try {
      await createUser.mutateAsync(newForm);
      setShowNew(false);
      setNewForm({ full_name: '', email: '', role: 'technician', phone: '', department: '' });
      toast.success('Usuário criado com sucesso');
    } catch (e: any) { toast.error(e.message || 'Erro'); }
  };

  if (isLoading) return <p className="text-sm text-muted-foreground">{t.common.loading}</p>;

  return (
    <div className="space-y-4 max-w-3xl">
      <div className="rounded-lg border border-primary/20 bg-primary/5 p-4 text-sm space-y-2">
        <div className="flex items-center gap-2 font-semibold text-primary">
          <Users className="h-4 w-4" />
          Gestão de Equipe
        </div>
        <p className="text-muted-foreground">
          Cadastre técnicos, vendedores e outros membros da equipe. Eles aparecerão como opções nas OS.
        </p>
        <div className="pt-2 border-t border-primary/10 mt-2 text-xs text-primary/80">
          <strong>💡 Como convidar:</strong> Primeiro crie o perfil abaixo. Depois, clique no botão <strong>"Enviar acesso"</strong> na lista para que o usuário receba o link de criação de senha por e-mail.
        </div>
      </div>

      <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
        <table className="w-full text-sm min-w-[700px]">
          <thead>
            <tr className="border-b bg-muted/50">
              <th className="px-4 py-3 text-left font-medium text-muted-foreground">Nome / Departamento</th>
              <th className="px-4 py-3 text-left font-medium text-muted-foreground">Email / Contato</th>
              <th className="px-4 py-3 text-left font-medium text-muted-foreground">Função</th>
              <th className="px-4 py-3 text-center font-medium text-muted-foreground">{t.common.active}</th>
              <th className="px-4 py-3 text-center font-medium text-muted-foreground">Ações</th>
            </tr>
          </thead>
          <tbody>
            {(users || []).map(u => (
              <tr key={u.id} className="border-b last:border-0 hover:bg-muted/30">
                <td className="px-4 py-2">
                  <div className="font-medium">{u.full_name}</div>
                  <div className="text-[10px] text-muted-foreground uppercase">{u.department || 'Sem Depto'}</div>
                </td>
                <td className="px-4 py-2">
                  <div className="text-muted-foreground">{u.email}</div>
                  <div className="text-[10px] text-muted-foreground">{u.phone || 'S/ Tel'}</div>
                </td>
                <td className="px-4 py-2">
                  <span className="text-xs font-medium px-2 py-1 rounded bg-primary/10 text-primary">
                    {USER_ROLES.find(r => r.value === u.role)?.label || u.role}
                  </span>
                </td>
                <td className="px-4 py-2 text-center">
                  <Switch checked={u.active} onCheckedChange={v => updateUser.mutate({ id: u.id, active: v })} />
                </td>
                <td className="px-4 py-2 text-center">
                  <div className="flex items-center justify-center gap-1">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setEditingUser(u)}
                    >
                      <Pencil className="h-3.5 w-3.5 mr-1" />
                      Editar
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={async () => {
                        try {
                          await supabase.auth.resetPasswordForEmail(u.email, {
                            redirectTo: window.location.origin + '/reset-password',
                          });
                          toast.success(`Link enviado para ${u.email}`);
                        } catch {
                          toast.error('Erro ao enviar email');
                        }
                      }}
                    >
                      <Mail className="h-3.5 w-3.5 mr-1" />
                      Enviar acesso
                    </Button>
                  </div>
                </td>
              </tr>
            ))}
            {(users || []).length === 0 && (
              <tr><td colSpan={6} className="px-4 py-8 text-center text-muted-foreground">Nenhum usuário cadastrado ainda</td></tr>
            )}
          </tbody>
        </table>
      </div>

      <p className="text-xs text-muted-foreground">{(users || []).length} usuários</p>

      {showNew ? (
        <div className="rounded-xl border bg-card p-4 shadow-sm space-y-3">
          <h4 className="text-sm font-semibold">Novo Usuário</h4>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="text-xs font-medium text-muted-foreground">Nome *</label>
              <Input value={newForm.full_name} onChange={e => setNewForm(p => ({ ...p, full_name: e.target.value }))} className="mt-1" />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">Email *</label>
              <Input value={newForm.email} onChange={e => setNewForm(p => ({ ...p, email: e.target.value }))} className="mt-1" />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">Telefone</label>
              <Input value={newForm.phone} onChange={e => setNewForm(p => ({ ...p, phone: maskPhone(e.target.value) }))} className="mt-1" placeholder="(47) 99999-9999" maxLength={15} />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">Departamento</label>
              <Input value={newForm.department || ''} onChange={e => setNewForm(p => ({ ...p, department: e.target.value }))} className="mt-1" placeholder="Ex: Manutenção" />
            </div>
            <div className="col-span-2">
              <label className="text-xs font-medium text-muted-foreground">Função</label>
              <Select value={newForm.role} onValueChange={v => setNewForm(p => ({ ...p, role: v }))}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {USER_ROLES.map(r => <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="flex gap-2">
            <Button size="sm" onClick={handleCreate} disabled={createUser.isPending}>Salvar</Button>
            <Button size="sm" variant="ghost" onClick={() => setShowNew(false)}>{t.common.cancel}</Button>
          </div>
        </div>
      ) : (
        <Button variant="outline" size="sm" onClick={() => setShowNew(true)}>
          + Novo Usuário
        </Button>
      )}

      <AppUserEditDialog
        user={editingUser}
        open={!!editingUser}
        onOpenChange={(o) => { if (!o) setEditingUser(null); }}
        isCurrentUserAdmin={isCurrentUserAdmin}
      />
    </div>
  );
}
