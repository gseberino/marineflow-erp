import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog';
import { Plus, Pencil, Trash2 } from 'lucide-react';
import {
  useAllWhatsAppTemplates, useUpsertWhatsAppTemplate, useDeleteWhatsAppTemplate,
  type WhatsAppTemplate,
} from '@/hooks/use-whatsapp-templates';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

const CATEGORIES: Array<{ value: string; label: string }> = [
  { value: 'service_order', label: 'Ordem de Serviço' },
  { value: 'quote', label: 'Orçamento' },
  { value: 'billing', label: 'Cobrança' },
  { value: 'general', label: 'Geral' },
];

const PLACEHOLDERS = '{cliente} • {os} • {valor} • {link} • {descricao} • {vencimento}';

export function WhatsAppTemplatesManager() {
  const { data: templates, isLoading } = useAllWhatsAppTemplates();
  const upsert = useUpsertWhatsAppTemplate();
  const del = useDeleteWhatsAppTemplate();
  const [editing, setEditing] = useState<Partial<WhatsAppTemplate> | null>(null);

  const grouped = (templates || []).reduce<Record<string, WhatsAppTemplate[]>>((acc, t) => {
    (acc[t.category] = acc[t.category] || []).push(t);
    return acc;
  }, {});

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-base font-semibold">Templates de WhatsApp</h3>
          <p className="text-xs text-muted-foreground">
            Placeholders disponíveis: {PLACEHOLDERS}
          </p>
        </div>
        <Button size="sm" onClick={() => setEditing({ category: 'general', active: true })} className="gap-1">
          <Plus className="h-4 w-4" /> Novo template
        </Button>
      </div>

      {isLoading ? (
        <p className="text-sm text-muted-foreground">Carregando…</p>
      ) : !templates?.length ? (
        <p className="text-sm text-muted-foreground italic">Nenhum template cadastrado.</p>
      ) : (
        <div className="space-y-4">
          {CATEGORIES.map(cat => {
            const items = grouped[cat.value];
            if (!items?.length) return null;
            return (
              <div key={cat.value}>
                <p className="text-xs font-semibold uppercase text-muted-foreground mb-2">{cat.label}</p>
                <div className="space-y-2">
                  {items.map(t => (
                    <div key={t.id} className="rounded-lg border bg-card p-3 flex items-start gap-3">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1">
                          <p className="font-medium text-sm">{t.name}</p>
                          {!t.active && <Badge variant="outline" className="text-[10px]">inativo</Badge>}
                        </div>
                        <p className="text-xs text-muted-foreground line-clamp-3 whitespace-pre-wrap">{t.body}</p>
                      </div>
                      <div className="flex gap-1 shrink-0">
                        <Button size="icon" variant="ghost" className="h-8 w-8" onClick={() => setEditing(t)}>
                          <Pencil className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          size="icon" variant="ghost" className="h-8 w-8 text-destructive"
                          onClick={() => { if (confirm(`Remover "${t.name}"?`)) del.mutate(t.id); }}
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      )}

      <Dialog open={!!editing} onOpenChange={v => { if (!v) setEditing(null); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{editing?.id ? 'Editar template' : 'Novo template'}</DialogTitle>
          </DialogHeader>
          {editing && (
            <div className="space-y-3">
              <div>
                <Label>Nome</Label>
                <Input value={editing.name || ''} onChange={e => setEditing({ ...editing, name: e.target.value })} />
              </div>
              <div>
                <Label>Categoria</Label>
                <Select value={editing.category || 'general'} onValueChange={v => setEditing({ ...editing, category: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {CATEGORIES.map(c => <SelectItem key={c.value} value={c.value}>{c.label}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div>
                <Label>Mensagem</Label>
                <Textarea
                  rows={5}
                  value={editing.body || ''}
                  onChange={e => setEditing({ ...editing, body: e.target.value })}
                  placeholder="Olá {cliente}, ..."
                />
                <p className="text-xs text-muted-foreground mt-1">Placeholders: {PLACEHOLDERS}</p>
              </div>
              <div className="flex items-center gap-2">
                <Switch
                  checked={editing.active ?? true}
                  onCheckedChange={v => setEditing({ ...editing, active: v })}
                />
                <Label className="!mt-0">Ativo</Label>
              </div>
              <div>
                <Label>Ordem</Label>
                <Input
                  type="number"
                  value={editing.sort_order ?? 0}
                  onChange={e => setEditing({ ...editing, sort_order: parseInt(e.target.value || '0', 10) })}
                />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditing(null)}>Cancelar</Button>
            <Button
              disabled={!editing?.name || !editing?.body || upsert.isPending}
              onClick={async () => {
                if (!editing?.name || !editing?.body || !editing?.category) return;
                await upsert.mutateAsync({
                  id: editing.id,
                  name: editing.name, body: editing.body, category: editing.category,
                  active: editing.active ?? true, sort_order: editing.sort_order ?? 0,
                });
                setEditing(null);
              }}
            >
              Salvar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
