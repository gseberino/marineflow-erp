import { useMemo, useRef, useState } from 'react';
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
  applyTemplateVariables, TEMPLATE_VARIABLES, type TemplateVariableDoc,
  type WhatsAppTemplate,
} from '@/hooks/use-whatsapp-templates';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

const CATEGORIES: Array<{ value: string; label: string }> = [
  { value: 'service_order', label: 'Ordem de Serviço' },
  { value: 'quote', label: 'Orçamento' },
  { value: 'billing', label: 'Cobrança' },
  { value: 'general', label: 'Geral' },
];

type CategoryKey = TemplateVariableDoc['contexts'][number];

function variablesForCategory(category: string): TemplateVariableDoc[] {
  const cat = (CATEGORIES.some(c => c.value === category) ? category : 'general') as CategoryKey;
  return TEMPLATE_VARIABLES.filter(v => v.contexts.includes(cat));
}

/** Painel lateral: lista variáveis disponíveis com descrição, exemplo e clique-para-inserir. */
function VariableHelper({
  category,
  onInsert,
}: {
  category: string;
  onInsert: (token: string) => void;
}) {
  const vars = variablesForCategory(category);
  return (
    <div className="rounded-lg border bg-muted/30 p-3 space-y-2">
      <div>
        <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          Variáveis disponíveis
        </p>
        <p className="text-[11px] text-muted-foreground">
          Clique em uma variável para inserir no texto. Use o formato <code className="font-mono">{'{nome}'}</code>.
        </p>
      </div>
      <div className="space-y-1.5 max-h-64 overflow-y-auto pr-1">
        {vars.map(v => (
          <button
            type="button"
            key={v.key}
            onClick={() => onInsert(`{${v.key}}`)}
            className="w-full text-left rounded-md border bg-background hover:bg-accent/40 px-2 py-1.5 transition-colors"
          >
            <div className="flex items-center justify-between gap-2">
              <code className="text-xs font-mono text-primary">{`{${v.key}}`}</code>
              <span className="text-[10px] text-muted-foreground truncate">{v.label}</span>
            </div>
            <p className="text-[11px] text-muted-foreground mt-0.5 line-clamp-2">{v.description}</p>
            <p className="text-[11px] mt-0.5">
              <span className="text-muted-foreground">Exemplo: </span>
              <span className="font-medium">{v.example}</span>
            </p>
          </button>
        ))}
      </div>
    </div>
  );
}

/** Constrói os valores de exemplo para o preview ao vivo, conforme a categoria. */
function buildPreviewVars(category: string): Record<string, string | number> {
  const map: Record<string, string | number> = {};
  for (const v of variablesForCategory(category)) {
    // valor entra como número para exercitar o formatador BRL
    map[v.key] = v.key === 'valor' ? 1250 : v.example;
  }
  return map;
}

export function WhatsAppTemplatesManager() {
  const { data: templates, isLoading } = useAllWhatsAppTemplates();
  const upsert = useUpsertWhatsAppTemplate();
  const del = useDeleteWhatsAppTemplate();
  const [editing, setEditing] = useState<Partial<WhatsAppTemplate> | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);

  const grouped = (templates || []).reduce<Record<string, WhatsAppTemplate[]>>((acc, t) => {
    (acc[t.category] = acc[t.category] || []).push(t);
    return acc;
  }, {});

  const editingCategory = editing?.category || 'general';
  const previewVars = useMemo(() => buildPreviewVars(editingCategory), [editingCategory]);
  const previewText = useMemo(
    () => (editing?.body ? applyTemplateVariables(editing.body, previewVars) : ''),
    [editing?.body, previewVars],
  );

  const insertAtCursor = (token: string) => {
    const ta = textareaRef.current;
    const current = editing?.body || '';
    if (!ta) {
      setEditing(prev => (prev ? { ...prev, body: current + token } : prev));
      return;
    }
    const start = ta.selectionStart ?? current.length;
    const end = ta.selectionEnd ?? current.length;
    const next = current.slice(0, start) + token + current.slice(end);
    setEditing(prev => (prev ? { ...prev, body: next } : prev));
    requestAnimationFrame(() => {
      ta.focus();
      const cursor = start + token.length;
      ta.setSelectionRange(cursor, cursor);
    });
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-base font-semibold">Templates de WhatsApp</h3>
          <p className="text-xs text-muted-foreground">
            Use <code className="font-mono">{'{cliente}'}</code>, <code className="font-mono">{'{valor}'}</code> e
            outras variáveis para personalizar suas mensagens.
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
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle>{editing?.id ? 'Editar template' : 'Novo template'}</DialogTitle>
          </DialogHeader>
          {editing && (
            <div className="grid gap-4 md:grid-cols-[1fr_280px]">
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
                  <p className="text-[11px] text-muted-foreground mt-1">
                    A categoria determina quais variáveis ficam disponíveis para esse template.
                  </p>
                </div>
                <div>
                  <Label>Mensagem</Label>
                  <Textarea
                    ref={textareaRef}
                    rows={6}
                    value={editing.body || ''}
                    onChange={e => setEditing({ ...editing, body: e.target.value })}
                    placeholder="Olá {cliente}, segue {descricao} no valor de R$ {valor}…"
                  />
                </div>
                <div>
                  <Label className="text-xs">Pré-visualização (com valores de exemplo)</Label>
                  <div className="mt-1 rounded-lg border bg-muted/40 p-3 text-sm whitespace-pre-wrap min-h-[80px]">
                    {previewText || (
                      <span className="text-muted-foreground italic">
                        Digite a mensagem para ver o preview.
                      </span>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  <div className="flex items-center gap-2">
                    <Switch
                      checked={editing.active ?? true}
                      onCheckedChange={v => setEditing({ ...editing, active: v })}
                    />
                    <Label className="!mt-0">Ativo</Label>
                  </div>
                  <div className="flex items-center gap-2">
                    <Label className="!mt-0 text-xs">Ordem</Label>
                    <Input
                      type="number"
                      className="h-8 w-20"
                      value={editing.sort_order ?? 0}
                      onChange={e => setEditing({ ...editing, sort_order: parseInt(e.target.value || '0', 10) })}
                    />
                  </div>
                </div>
              </div>

              <VariableHelper
                category={editingCategory}
                onInsert={insertAtCursor}
              />
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
