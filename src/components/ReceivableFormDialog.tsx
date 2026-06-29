import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { EntityCombobox } from '@/components/EntityCombobox';
import { useI18n } from '@/i18n';
import { useClients } from '@/hooks/use-clients';
import { useServiceOrders } from '@/hooks/use-service-orders';
import { useCreateReceivable, useUpdateReceivable } from '@/hooks/use-financial';
import { useCostCenters } from '@/hooks/use-cost-centers';
import { toast } from 'sonner';
import { MoneyInput } from '@/components/MoneyInput';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Quando passado, entra em modo de edição */
  initialData?: any;
}

export function ReceivableFormDialog({ open, onOpenChange, initialData }: Props) {
  const { t } = useI18n();
  const { data: clients } = useClients();
  const { data: orders } = useServiceOrders();
  const { data: costCenters } = useCostCenters();
  const create = useCreateReceivable();
  const update = useUpdateReceivable();
  const isEditing = !!initialData;

  const [clientId, setClientId] = useState('');
  const [costCenterId, setCostCenterId] = useState('');
  const [soId, setSoId] = useState('');
  const [description, setDescription] = useState('');
  const [issueDate, setIssueDate] = useState(new Date().toISOString().split('T')[0]);
  const [dueDate, setDueDate] = useState('');
  const [amount, setAmount] = useState<number>(0);
  const [currency, setCurrency] = useState('BRL');
  const [notes, setNotes] = useState('');

  // Preenche campos ao entrar em modo edição
  useEffect(() => {
    if (open && initialData) {
      setClientId(initialData.client_id || '');
      setCostCenterId(initialData.cost_center_id || '');
      setSoId(initialData.service_order_id || '');
      setDescription(initialData.description || '');
      setIssueDate(initialData.issue_date || new Date().toISOString().split('T')[0]);
      setDueDate(initialData.due_date || '');
      setAmount(Number(initialData.amount || 0));
      setCurrency(initialData.currency || 'BRL');
      setNotes(initialData.notes || '');
    } else if (open && !initialData) {
      // Reset para criação
      setClientId(''); setCostCenterId(''); setSoId(''); setDescription('');
      setIssueDate(new Date().toISOString().split('T')[0]);
      setDueDate(''); setAmount(0); setCurrency('BRL'); setNotes('');
    }
  }, [open, initialData]);

  const hasPaidAmount = initialData && Number(initialData.paid_amount || 0) > 0;

  const handleSave = async () => {
    if (!description || !dueDate || !amount) return;
    try {
      if (isEditing) {
        await update.mutateAsync({
          id: initialData.id,
          description,
          due_date: dueDate,
          // Só permite alterar amount se não há pagamentos parciais
          ...(hasPaidAmount ? {} : { amount }),
          notes: notes || undefined,
          cost_center_id: costCenterId || undefined,
        });
        toast.success('Recebível atualizado');
      } else {
        if (!clientId) return;
        await create.mutateAsync({
          client_id: clientId, description, issue_date: issueDate,
          due_date: dueDate, amount, currency,
          cost_center_id: costCenterId || undefined,
          service_order_id: soId || undefined, notes: notes || undefined,
        });
        toast.success(t.financial.newReceivable);
      }
      onOpenChange(false);
    } catch { toast.error(isEditing ? 'Erro ao atualizar' : 'Erro ao criar cobrança'); }
  };

  const clientOrders = orders?.filter(o => o.client_id === clientId) || [];
  const isPending = create.isPending || update.isPending;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEditing ? 'Editar Recebível' : t.financial.newReceivable}</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          {/* Cliente — somente em criação */}
          {!isEditing && (
            <div><Label>{t.serviceOrders.client} *</Label>
              <EntityCombobox
                value={clientId}
                onChange={setClientId}
                placeholder={t.serviceOrders.client}
                options={(clients || []).map(c => ({
                  value: c.id,
                  label: c.name,
                  description: c.cpf_cnpj || undefined,
                  searchTerms: [c.cpf_cnpj || '', c.email || ''],
                }))}
              />
            </div>
          )}
          {!isEditing && clientId && clientOrders.length > 0 && (
            <div><Label>{t.financial.linkedOrder}</Label>
              <EntityCombobox
                value={soId}
                onChange={setSoId}
                placeholder="—"
                options={clientOrders.map(o => ({ value: o.id, label: o.service_order_number }))}
              />
            </div>
          )}
          <div><Label>Centro de Custo (Opcional)</Label>
            <Select value={costCenterId} onValueChange={setCostCenterId}>
              <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="">—</SelectItem>
                {(costCenters || []).filter(c => c.type !== 'expense').map(c => (
                  <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div><Label>{t.common.description} *</Label>
            <Input value={description} onChange={e => setDescription(e.target.value)} />
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            {!isEditing && (
              <div><Label>{t.common.date}</Label>
                <Input type="date" value={issueDate} onChange={e => setIssueDate(e.target.value)} />
              </div>
            )}
            <div className={isEditing ? 'col-span-2' : ''}>
              <Label>{t.financial.dueDate} *</Label>
              <Input type="date" value={dueDate} onChange={e => setDueDate(e.target.value)} />
            </div>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <Label>{t.common.amount} *</Label>
              {hasPaidAmount ? (
                <div>
                  <Input readOnly value={amount.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })} className="bg-muted" />
                  <p className="text-[10px] text-muted-foreground mt-0.5">Valor bloqueado — há pagamentos registrados</p>
                </div>
              ) : (
                <MoneyInput value={amount} onValueChange={setAmount} />
              )}
            </div>
            {!isEditing && (
              <div><Label>Moeda</Label>
                <Select value={currency} onValueChange={setCurrency}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="BRL">BRL</SelectItem>
                    <SelectItem value="USD">USD</SelectItem>
                    <SelectItem value="EUR">EUR</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            )}
          </div>
          <div><Label>{t.common.notes}</Label>
            <Textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} />
          </div>
        </div>
        <DialogFooter>
          <Button onClick={handleSave} disabled={isPending}>
            {isPending ? 'Salvando...' : t.common.save}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
