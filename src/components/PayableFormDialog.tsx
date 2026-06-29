import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { EntityCombobox } from '@/components/EntityCombobox';
import { CategorySelect } from '@/components/CategorySelect';
import { QuickSupplierDialog } from '@/components/QuickSupplierDialog';
import { useI18n } from '@/i18n';
import { useSuppliers } from '@/hooks/use-suppliers';
import { useServiceOrders } from '@/hooks/use-service-orders';
import { useCreatePayable, useUpdatePayable } from '@/hooks/use-financial';
import { useCostCenters } from '@/hooks/use-cost-centers';
import { toast } from 'sonner';
import { MoneyInput } from '@/components/MoneyInput';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Quando passado, entra em modo de edição */
  initialData?: any;
}

export function PayableFormDialog({ open, onOpenChange, initialData }: Props) {
  const { t } = useI18n();
  const { data: suppliers } = useSuppliers();
  const { data: orders } = useServiceOrders();
  const { data: costCenters } = useCostCenters();
  const create = useCreatePayable();
  const update = useUpdatePayable();
  const isEditing = !!initialData;

  const [supplierId, setSupplierId] = useState('');
  const [supplierName, setSupplierName] = useState('');
  const [category, setCategory] = useState('');
  const [costCenterId, setCostCenterId] = useState('');
  const [description, setDescription] = useState('');
  const [issueDate, setIssueDate] = useState(new Date().toISOString().split('T')[0]);
  const [dueDate, setDueDate] = useState('');
  const [amount, setAmount] = useState<number>(0);
  const [currency, setCurrency] = useState('BRL');
  const [soId, setSoId] = useState('');
  const [notes, setNotes] = useState('');
  const [quickSupplierOpen, setQuickSupplierOpen] = useState(false);
  const [quickSupplierName, setQuickSupplierName] = useState('');

  // Preenche campos ao entrar em modo edição
  useEffect(() => {
    if (open && initialData) {
      setSupplierId(initialData.supplier_id || '');
      setSupplierName('');
      setCategory(initialData.expense_category || '');
      setCostCenterId(initialData.cost_center_id || '');
      setDescription(initialData.description || '');
      setIssueDate(initialData.issue_date || new Date().toISOString().split('T')[0]);
      setDueDate(initialData.due_date || '');
      setAmount(Number(initialData.amount || 0));
      setCurrency(initialData.currency || 'BRL');
      setSoId(initialData.linked_service_order_id || '');
      setNotes(initialData.notes || '');
    } else if (open && !initialData) {
      setSupplierId(''); setSupplierName(''); setCategory(''); setCostCenterId('');
      setDescription(''); setIssueDate(new Date().toISOString().split('T')[0]);
      setDueDate(''); setAmount(0); setCurrency('BRL'); setSoId(''); setNotes('');
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
          expense_category: category || undefined,
          cost_center_id: costCenterId || undefined,
          notes: notes || undefined,
          ...(hasPaidAmount ? {} : { amount }),
        });
        toast.success('Pagável atualizado');
      } else {
        const selectedSupplier = suppliers?.find(s => s.id === supplierId);
        await create.mutateAsync({
          description, issue_date: issueDate, due_date: dueDate,
          amount, currency,
          expense_category: category || undefined,
          cost_center_id: costCenterId || undefined,
          supplier_id: supplierId || undefined,
          name: selectedSupplier?.name || supplierName || undefined,
          linked_service_order_id: soId || undefined,
          notes: notes || undefined,
        });
        toast.success(t.financial.newPayable);
      }
      onOpenChange(false);
    } catch { toast.error(isEditing ? 'Erro ao atualizar' : 'Erro ao criar despesa'); }
  };

  const isPending = create.isPending || update.isPending;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEditing ? 'Editar Pagável' : t.financial.newPayable}</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          {!isEditing && (
            <>
              <div><Label>{t.financial.supplierOptional}</Label>
                <EntityCombobox
                  value={supplierId}
                  onChange={v => { setSupplierId(v); setSupplierName(''); }}
                  placeholder="—"
                  options={(suppliers || []).map(s => ({
                    value: s.id, label: s.name,
                    description: s.cnpj_cpf || undefined,
                    searchTerms: [s.cnpj_cpf || '', s.contact_email || ''],
                  }))}
                  onCreate={(typed) => { setQuickSupplierName(typed); setQuickSupplierOpen(true); }}
                  createLabel="+ Cadastrar novo fornecedor"
                />
              </div>
              {!supplierId && (
                <div><Label>Nome do fornecedor</Label>
                  <Input value={supplierName} onChange={e => setSupplierName(e.target.value)} />
                </div>
              )}
            </>
          )}
          <div className="grid grid-cols-2 gap-3">
            <div><Label>{t.financial.expenseCategory}</Label>
              <CategorySelect type="payable" value={category} onChange={setCategory} placeholder="—" />
            </div>
            <div><Label>Centro de Custo</Label>
              <Select value={costCenterId} onValueChange={setCostCenterId}>
                <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="">—</SelectItem>
                  {(costCenters || []).filter(c => c.type !== 'revenue').map(c => (
                    <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div><Label>{t.common.description} *</Label>
            <Input value={description} onChange={e => setDescription(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-3">
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
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>{t.common.amount} *</Label>
              {hasPaidAmount ? (
                <div>
                  <Input readOnly value={amount.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })} className="bg-muted" />
                  <p className="text-[10px] text-muted-foreground mt-0.5">Valor bloqueado — há pagamentos</p>
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
          {!isEditing && (
            <div><Label>{t.financial.linkedOrder}</Label>
              <EntityCombobox
                value={soId}
                onChange={setSoId}
                placeholder="—"
                options={[
                  { value: '', label: '—' },
                  ...(orders || []).map(o => ({ value: o.id, label: o.service_order_number })),
                ]}
              />
            </div>
          )}
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
      {!isEditing && (
        <QuickSupplierDialog
          open={quickSupplierOpen}
          onOpenChange={setQuickSupplierOpen}
          initialName={quickSupplierName}
          onCreated={(s) => { setSupplierId(s.id); setSupplierName(''); }}
        />
      )}
    </Dialog>
  );
}
