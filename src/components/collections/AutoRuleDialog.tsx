import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useAppSettings } from '@/hooks/use-app-settings';
import { useCollectionTemplates } from '@/hooks/use-collections';
import { useQueryClient } from '@tanstack/react-query';

interface Props { open: boolean; onOpenChange: (v: boolean) => void }

const KEYS = {
  enabled: 'collection_rule_enabled',
  daysBefore: 'collection_rule_days_before',
  onDue: 'collection_rule_on_due',
  daysAfter: 'collection_rule_days_after',
  tplBefore: 'collection_rule_tpl_before',
  tplOnDue: 'collection_rule_tpl_on_due',
  tplAfter: 'collection_rule_tpl_after',
};

export function AutoRuleDialog({ open, onOpenChange }: Props) {
  const { data: settings } = useAppSettings();
  const { data: templates } = useCollectionTemplates();
  const qc = useQueryClient();

  const [enabled, setEnabled] = useState(false);
  const [daysBefore, setDaysBefore] = useState('3');
  const [onDue, setOnDue] = useState(true);
  const [daysAfter, setDaysAfter] = useState('5');
  const [tplBefore, setTplBefore] = useState('');
  const [tplOnDue, setTplOnDue] = useState('');
  const [tplAfter, setTplAfter] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!settings) return;
    setEnabled(settings[KEYS.enabled] === 'true');
    setDaysBefore(settings[KEYS.daysBefore] || '3');
    setOnDue(settings[KEYS.onDue] !== 'false');
    setDaysAfter(settings[KEYS.daysAfter] || '5');
    setTplBefore(settings[KEYS.tplBefore] || '');
    setTplOnDue(settings[KEYS.tplOnDue] || '');
    setTplAfter(settings[KEYS.tplAfter] || '');
  }, [settings, open]);

  const save = async () => {
    setSaving(true);
    try {
      const rows = [
        { key: KEYS.enabled, value: String(enabled) },
        { key: KEYS.daysBefore, value: String(daysBefore) },
        { key: KEYS.onDue, value: String(onDue) },
        { key: KEYS.daysAfter, value: String(daysAfter) },
        { key: KEYS.tplBefore, value: tplBefore },
        { key: KEYS.tplOnDue, value: tplOnDue },
        { key: KEYS.tplAfter, value: tplAfter },
      ];
      const { error } = await supabase.from('app_settings').upsert(rows as never, { onConflict: 'key' });
      if (error) throw error;
      toast.success('Régua salva');
      qc.invalidateQueries({ queryKey: ['app-settings'] });
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e.message || 'Erro ao salvar');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>Régua de Cobrança</DialogTitle></DialogHeader>
        <div className="grid gap-4 py-2">
          <div className="flex items-center justify-between rounded-lg border p-3">
            <div>
              <Label>Ativar régua automática global</Label>
              <p className="text-xs text-muted-foreground">Aplica a cobranças com régua habilitada</p>
            </div>
            <Switch checked={enabled} onCheckedChange={setEnabled} />
          </div>

          <div className="space-y-3 border-t pt-3">
            <div className="flex items-center justify-between gap-3">
              <div className="flex-1">
                <Label>Dias antes do vencimento</Label>
                <Input type="number" value={daysBefore} onChange={e => setDaysBefore(e.target.value)} />
              </div>
              <div className="flex-1">
                <Label>Template</Label>
                <Select value={tplBefore} onValueChange={setTplBefore}>
                  <SelectTrigger><SelectValue placeholder="Selecionar..." /></SelectTrigger>
                  <SelectContent>
                    {(templates || []).map(t => (<SelectItem key={t.id} value={t.id}>{t.name}</SelectItem>))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="flex items-center justify-between gap-3">
              <div className="flex-1 flex items-center gap-2">
                <Switch checked={onDue} onCheckedChange={setOnDue} />
                <Label>Enviar no dia do vencimento</Label>
              </div>
              <div className="flex-1">
                <Label>Template</Label>
                <Select value={tplOnDue} onValueChange={setTplOnDue}>
                  <SelectTrigger><SelectValue placeholder="Selecionar..." /></SelectTrigger>
                  <SelectContent>
                    {(templates || []).map(t => (<SelectItem key={t.id} value={t.id}>{t.name}</SelectItem>))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="flex items-center justify-between gap-3">
              <div className="flex-1">
                <Label>Dias após o vencimento</Label>
                <Input type="number" value={daysAfter} onChange={e => setDaysAfter(e.target.value)} />
              </div>
              <div className="flex-1">
                <Label>Template</Label>
                <Select value={tplAfter} onValueChange={setTplAfter}>
                  <SelectTrigger><SelectValue placeholder="Selecionar..." /></SelectTrigger>
                  <SelectContent>
                    {(templates || []).map(t => (<SelectItem key={t.id} value={t.id}>{t.name}</SelectItem>))}
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={save} disabled={saving}>Salvar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
