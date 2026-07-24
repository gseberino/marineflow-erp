import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Wrench, Plus, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';

function nextDue(p: any): Date {
  const base = p.last_service_at ? new Date(p.last_service_at) : new Date(p.created_at);
  const d = new Date(base);
  d.setMonth(d.getMonth() + Number(p.interval_months));
  return d;
}

/**
 * Planos de manutenção recorrente da embarcação (Fase 8 — padrão ServiceTitan
 * memberships). O motor cria "Propor revisão" quando o plano entra na janela;
 * registrar o serviço aqui reinicia o ciclo.
 */
export function MaintenancePlansPanel({ vesselId }: { vesselId: string | undefined }) {
  const qc = useQueryClient();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [name, setName] = useState('');
  const [months, setMonths] = useState('12');
  const [value, setValue] = useState('');
  const [scope, setScope] = useState('');
  const [lastAt, setLastAt] = useState('');

  const { data: plans = [] } = useQuery({
    queryKey: ['maintenance-plans', vesselId],
    enabled: !!vesselId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('maintenance_plans')
        .select('*')
        .eq('vessel_id', vesselId!)
        .order('created_at');
      if (error) throw error;
      return data || [];
    },
  });

  const invalidate = () => qc.invalidateQueries({ queryKey: ['maintenance-plans', vesselId] });

  const create = useMutation({
    mutationFn: async () => {
      const { data: u } = await supabase.auth.getUser();
      const { error } = await supabase.from('maintenance_plans').insert({
        vessel_id: vesselId!,
        name: name.trim(),
        interval_months: Number(months) || 12,
        estimated_value: value ? Number(value) : null,
        scope: scope.trim() || null,
        last_service_at: lastAt || null,
        created_by: u?.user?.id ?? null,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Plano criado — o motor proporá a revisão na janela certa');
      setDialogOpen(false);
      setName(''); setMonths('12'); setValue(''); setScope(''); setLastAt('');
      invalidate();
    },
    onError: (e: any) => toast.error(e?.message || 'Erro ao criar plano'),
  });

  const update = useMutation({
    mutationFn: async ({ id, patch }: { id: string; patch: any }) => {
      const { error } = await supabase.from('maintenance_plans').update(patch).eq('id', id);
      if (error) throw error;
    },
    onSuccess: invalidate,
    onError: (e: any) => toast.error(e?.message || 'Erro ao atualizar'),
  });

  if (!vesselId) return null;
  const fmt = (d: Date) => d.toLocaleDateString('pt-BR');
  const today = new Date();

  return (
    <Card className="p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm font-semibold">
          <Wrench className="h-4 w-4 text-primary" /> Planos de manutenção
        </div>
        <Button size="sm" variant="outline" onClick={() => setDialogOpen(true)}>
          <Plus className="h-4 w-4 mr-1" /> Novo plano
        </Button>
      </div>

      {plans.length === 0 && (
        <p className="text-xs text-muted-foreground">
          Nenhum plano. Crie um (ex.: "Revisão de motor · a cada 12 meses") e o sistema
          lembrará de propor o serviço na hora certa — receita recorrente sem esforço.
        </p>
      )}

      <div className="space-y-2">
        {plans.map((p: any) => {
          const due = nextDue(p);
          const overdue = due <= today;
          return (
            <div key={p.id} className="flex items-center gap-3 rounded-md border px-3 py-2 text-sm">
              <div className="min-w-0 flex-1">
                <p className="font-medium">{p.name} <span className="text-xs text-muted-foreground">· a cada {p.interval_months} mês(es)</span></p>
                <p className={`text-[11px] ${overdue && p.active ? 'text-amber-600 dark:text-amber-400 font-semibold' : 'text-muted-foreground'}`}>
                  Próxima: {fmt(due)}{overdue && p.active ? ' — na janela de proposta' : ''}
                  {p.last_service_at ? ` · último serviço ${fmt(new Date(p.last_service_at))}` : ' · sem serviço registrado'}
                </p>
              </div>
              <Button size="sm" variant="ghost" className="text-xs h-7"
                onClick={() => update.mutate({ id: p.id, patch: { last_service_at: new Date().toISOString().slice(0, 10) } })}
                title="Registrar que o serviço foi feito hoje (reinicia o ciclo)">
                Serviço feito
              </Button>
              <Switch checked={p.active}
                onCheckedChange={(v) => update.mutate({ id: p.id, patch: { active: v } })} />
            </div>
          );
        })}
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Novo plano de manutenção</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label>Nome *</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Revisão de motor" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>A cada (meses) *</Label>
                <Input type="number" min={1} max={60} value={months} onChange={(e) => setMonths(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>Valor estimado (R$)</Label>
                <Input type="number" value={value} onChange={(e) => setValue(e.target.value)} placeholder="opcional" />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Último serviço (se já houve)</Label>
              <Input type="date" value={lastAt} onChange={(e) => setLastAt(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Escopo</Label>
              <Input value={scope} onChange={(e) => setScope(e.target.value)} placeholder="óleo, filtros, correias…" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancelar</Button>
            <Button onClick={() => create.mutate()} disabled={!name.trim() || create.isPending}>
              {create.isPending && <Loader2 className="h-4 w-4 animate-spin mr-1" />} Criar plano
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
