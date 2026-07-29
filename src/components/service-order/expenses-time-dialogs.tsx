/* Diálogos Despesas Operacionais + Controle de Horas da OS,
   extraídos 1:1 do ServiceOrderForm (Fase 3, passo 4). */
import { Clock, ExternalLink, FileImage, FileText, Paperclip, Pencil, Plus, Receipt, Trash2, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { MoneyInput } from '@/components/MoneyInput';
import { EntityCombobox } from '@/components/EntityCombobox';
import { StatusBadge } from '@/components/StatusBadge';
import { OPERATIONAL_EXPENSE_CATEGORIES } from '@/lib/expense-categories';
import { useI18n } from '@/i18n';
import type { Dispatch, SetStateAction } from 'react';

interface ExpensesTimeDialogsProps {
  isNew: boolean;
  orderId?: string;
  showExpensesDialog: boolean;
  setShowExpensesDialog: Dispatch<SetStateAction<boolean>>;
  showTimeDialog: boolean;
  setShowTimeDialog: Dispatch<SetStateAction<boolean>>;
  showExpForm: boolean;
  setShowExpForm: Dispatch<SetStateAction<boolean>>;
  showTimeForm: boolean;
  setShowTimeForm: Dispatch<SetStateAction<boolean>>;
  expForm: Record<string, any>;
  setExpForm: Dispatch<SetStateAction<any>>;
  timeForm: Record<string, any>;
  setTimeForm: Dispatch<SetStateAction<any>>;
  editingExpenseId: string | null;
  resetExpForm: (...args: any[]) => any;
  handleAddExpense: (...args: any[]) => any;
  handleAddTime: (...args: any[]) => any;
  handleEditExpense: (...args: any[]) => any;
  handleUploadReceipt: (...args: any[]) => any;
  handleRemoveReceipt: (...args: any[]) => any;
  uploadingReceipt: any;
  receiptInputRef: any;
  soExpenses: any[] | undefined;
  timeEntries: any[] | undefined;
  suppliers: any[] | undefined;
  appUsers: any[] | undefined;
  addExpense: any;
  addTime: any;
  removeExpense: any;
  removeTime: any;
  updateExpense: any;
  setQuickSupplierOpen: Dispatch<SetStateAction<boolean>>;
  setQuickSupplierName: Dispatch<SetStateAction<string>>;
}

export function ExpensesTimeDialogs(props: ExpensesTimeDialogsProps) {
  const {
    isNew, orderId,
    showExpensesDialog, setShowExpensesDialog, showTimeDialog, setShowTimeDialog,
    showExpForm, setShowExpForm, showTimeForm, setShowTimeForm,
    expForm, setExpForm, timeForm, setTimeForm,
    editingExpenseId, resetExpForm,
    handleAddExpense, handleAddTime, handleEditExpense,
    handleUploadReceipt, handleRemoveReceipt, uploadingReceipt, receiptInputRef,
    soExpenses, timeEntries, suppliers, appUsers,
    addExpense, addTime, removeExpense, removeTime, updateExpense,
    setQuickSupplierOpen, setQuickSupplierName,
  } = props;
  const { t, formatCurrency, formatDate, formatDateTime } = useI18n();

  return (
    <>
      {!isNew && (
        <Dialog open={showExpensesDialog} onOpenChange={setShowExpensesDialog}>
          <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <Receipt className="h-4 w-4" /> Despesas Operacionais
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-0">
              <div className="flex items-center justify-between pb-3">
                <h2 className="font-semibold text-sm">{t.serviceOrders.operationalExpenses}</h2>
                <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowExpForm(!showExpForm)}>
                  <Plus className="h-3 w-3" /> {t.serviceOrders.addExpense}
                </Button>
              </div>
              {showExpForm && (
                <div className="p-4 border rounded-lg bg-muted/30 space-y-3 mb-3">
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div>
                      <Label>{t.products.category}</Label>
                      <Select value={expForm.category} onValueChange={(v) => setExpForm({ ...expForm, category: v })}>
                        <SelectTrigger><SelectValue placeholder={t.products.category} /></SelectTrigger>
                        <SelectContent>
                          {OPERATIONAL_EXPENSE_CATEGORIES.map((c) => (
                            <SelectItem key={c} value={c}>{c}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div>
                      <Label>{t.serviceOrders.expenseDate}</Label>
                      <Input type="date" value={expForm.expense_date} onChange={(e) => setExpForm({ ...expForm, expense_date: e.target.value })} />
                    </div>
                    <div>
                      <Label>{t.common.amount}</Label>
                      <MoneyInput value={expForm.amount}
                        onValueChange={(v) => setExpForm({ ...expForm, amount: v })} />
                    </div>
                  </div>
                  <div>
                    <Label>{t.common.description}</Label>
                    <Input value={expForm.description} onChange={(e) => setExpForm({ ...expForm, description: e.target.value })} />
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div>
                      <Label>{t.serviceOrders.paidBy}</Label>
                      <Select value={expForm.paid_by} onValueChange={(v: 'company' | 'technician') => setExpForm({ ...expForm, paid_by: v })}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="company">{t.serviceOrders.paidByCompany}</SelectItem>
                          <SelectItem value="technician">{t.serviceOrders.paidByTechnician}</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    {expForm.paid_by === 'technician' && (
                      <div>
                        <Label>{t.serviceOrders.technicians}</Label>
                        <Select value={expForm.technician_user_id} onValueChange={(v) => setExpForm({ ...expForm, technician_user_id: v })}>
                          <SelectTrigger><SelectValue placeholder={t.serviceOrders.technicians} /></SelectTrigger>
                          <SelectContent>
                            {appUsers?.map((u) => (
                              <SelectItem key={u.id} value={u.id}>{u.full_name}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <p className="text-xs text-warning mt-1">{t.serviceOrders.pendingReimbursement}</p>
                      </div>
                    )}
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div>
                      <Label>Comprovante</Label>
                      <input
                        ref={receiptInputRef}
                        type="file"
                        accept="image/*,application/pdf"
                        capture="environment"
                        className="hidden"
                        onChange={(e) => {
                          const f = e.target.files?.[0];
                          if (f) handleUploadReceipt(f);
                        }}
                      />
                      {expForm.receipt_url ? (
                        <div className="flex items-center gap-2 mt-1 p-2 rounded-md border bg-background">
                          {/\.(png|jpe?g|gif|webp|svg)$/i.test(expForm.receipt_url) ? (
                            <img
                              src={expForm.receipt_url}
                              alt="Comprovante"
                              className="h-[60px] w-[60px] object-cover rounded border"
                            />
                          ) : (
                            <div className="h-[60px] w-[60px] flex items-center justify-center rounded border bg-muted">
                              <FileText className="h-6 w-6 text-muted-foreground" />
                            </div>
                          )}
                          <a
                            href={expForm.receipt_url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-xs text-primary hover:underline truncate flex-1"
                          >
                            Ver comprovante
                          </a>
                          <Button
                            type="button"
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7"
                            onClick={handleRemoveReceipt}
                          >
                            <X className="h-3.5 w-3.5" />
                          </Button>
                        </div>
                      ) : (
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          className="w-full gap-2 mt-1"
                          onClick={() => receiptInputRef.current?.click()}
                          disabled={uploadingReceipt}
                        >
                          <Paperclip className="h-3.5 w-3.5" />
                          {uploadingReceipt ? 'Enviando...' : '📎 Anexar comprovante'}
                        </Button>
                      )}
                    </div>
                    <div>
                      <Label>{t.common.notes}</Label>
                      <Input value={expForm.notes} onChange={(e) => setExpForm({ ...expForm, notes: e.target.value })} />
                    </div>
                  </div>
                  <div>
                    <Label>Fornecedor</Label>
                    <EntityCombobox
                      value={expForm.supplier_id}
                      onChange={(v) => setExpForm({ ...expForm, supplier_id: v })}
                      options={(suppliers || []).filter((s) => s.active).map((s) => ({
                        value: s.id,
                        label: s.name,
                        description: s.cnpj_cpf || undefined,
                      }))}
                      placeholder="—"
                      onCreate={(typed) => {
                        setQuickSupplierName(typed);
                        setQuickSupplierOpen(true);
                      }}
                      createLabel="+ Cadastrar novo fornecedor"
                    />
                  </div>
                  {!editingExpenseId && (
                    <label className="flex items-center gap-2 text-sm cursor-pointer">
                      <input type="checkbox" checked={expForm.also_create_payable}
                        onChange={(e) => setExpForm({ ...expForm, also_create_payable: e.target.checked })} />
                      {t.serviceOrders.alsoCreatePayable}
                    </label>
                  )}
                  <label className="flex items-center gap-2 text-sm cursor-pointer">
                    <input type="checkbox" checked={expForm.billable_to_client}
                      onChange={(e) => setExpForm({ ...expForm, billable_to_client: e.target.checked })} />
                    Faturável ao cliente
                    <span className="text-xs text-muted-foreground">(desmarque para custo interno, não repassado no orçamento/OS)</span>
                  </label>
                  <div className="flex gap-2">
                    <Button size="sm" onClick={handleAddExpense} disabled={addExpense.isPending || updateExpense.isPending}>
                      {editingExpenseId ? 'Atualizar' : t.common.save}
                    </Button>
                    <Button size="sm" variant="outline" onClick={() => { resetExpForm(); setShowExpForm(false); }}>
                      {t.common.cancel}
                    </Button>
                  </div>
                </div>
              )}
              {(!soExpenses || soExpenses.length === 0) ? (
                <p className="text-sm text-muted-foreground p-5">{t.serviceOrders.noExpensesYet}</p>
              ) : (
                <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b bg-muted/50">
                      <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.common.date}</th>
                      <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.products.category}</th>
                      <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.common.description}</th>
                      <th className="px-4 py-2 text-left font-medium text-muted-foreground hidden sm:table-cell">Fornecedor</th>
                      <th className="px-4 py-2 text-left font-medium text-muted-foreground hidden sm:table-cell">{t.serviceOrders.paidBy}</th>
                      <th className="px-4 py-2 text-center font-medium text-muted-foreground hidden md:table-cell">Comprovante</th>
                      <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.common.amount}</th>
                      <th className="px-4 py-2 w-20"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {soExpenses.map((exp: any) => (
                      <tr key={exp.id} className="border-b last:border-0">
                        <td className="px-4 py-3 text-muted-foreground">{formatDate(exp.expense_date)}</td>
                        <td className="px-4 py-3"><StatusBadge className="bg-secondary text-secondary-foreground">{exp.category}</StatusBadge></td>
                        <td className="px-4 py-3 font-medium">
                          {exp.description}
                          {exp.billable_to_client === false && (
                            <StatusBadge className="bg-muted text-muted-foreground ml-1">Interno</StatusBadge>
                          )}
                        </td>
                        <td className="px-4 py-3 text-muted-foreground hidden sm:table-cell">
                          {exp.suppliers?.name || '—'}
                        </td>
                        <td className="px-4 py-3 hidden sm:table-cell">
                          {exp.paid_by === 'technician' ? (
                            <span className="text-warning">{exp.app_users?.full_name || t.serviceOrders.paidByTechnician}
                              {!exp.reimbursed && <StatusBadge className="bg-warning/15 text-warning ml-1">{t.serviceOrders.pendingReimbursement}</StatusBadge>}
                              {exp.reimbursed && <StatusBadge className="bg-success/15 text-success ml-1">{t.serviceOrders.reimbursed}</StatusBadge>}
                            </span>
                          ) : t.serviceOrders.paidByCompany}
                        </td>
                        <td className="px-4 py-3 text-center hidden md:table-cell">
                          {exp.receipt_url ? (
                            /\.(png|jpe?g|gif|webp|svg)$/i.test(exp.receipt_url) ? (
                              <a href={exp.receipt_url} target="_blank" rel="noopener noreferrer" className="inline-block">
                                <img src={exp.receipt_url} alt="Comprovante" className="h-8 w-8 object-cover rounded border inline-block" />
                              </a>
                            ) : (
                              <a href={exp.receipt_url} target="_blank" rel="noopener noreferrer" className="text-primary inline-flex items-center gap-1 hover:underline">
                                <FileImage className="h-4 w-4" />
                                <ExternalLink className="h-3 w-3" />
                              </a>
                            )
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </td>
                        <td className="px-4 py-3 text-right font-semibold">{formatCurrency(Number(exp.amount))}</td>
                        <td className="px-4 py-3">
                          <div className="flex items-center justify-end gap-1">
                            <Button variant="ghost" size="icon" className="h-7 w-7"
                              onClick={() => handleEditExpense(exp)}>
                              <Pencil className="h-3.5 w-3.5" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive"
                              onClick={() => removeExpense.mutate({ id: exp.id, service_order_id: orderId! })}>
                              <Trash2 className="h-3.5 w-3.5" />
                            </Button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                </div>
              )}
            </div>
          </DialogContent>
        </Dialog>
      )}

      {!isNew && (
        <Dialog open={showTimeDialog} onOpenChange={setShowTimeDialog}>
          <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <Clock className="h-4 w-4" /> Controle de Horas
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-0">
              <div className="flex items-center justify-between pb-3">
                <div>
                  <h2 className="font-semibold text-sm">{t.services.timeSection}</h2>
                  <p className="text-xs text-muted-foreground mt-0.5">{t.services.timeNote}</p>
                </div>
                <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowTimeForm(!showTimeForm)}>
                  <Plus className="h-3 w-3" /> {t.serviceOrders.addTimeEntry}
                </Button>
              </div>
              {showTimeForm && (
                <div className="p-4 border rounded-lg bg-muted/30 space-y-3 mb-3">
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div>
                      <Label>{t.serviceOrders.technicians}</Label>
                      <Select value={timeForm.technician_user_id}
                        onValueChange={(v) => setTimeForm({ ...timeForm, technician_user_id: v })}>
                        <SelectTrigger><SelectValue placeholder="Selecionar técnico" /></SelectTrigger>
                        <SelectContent>
                          {appUsers?.map((u) => (
                            <SelectItem key={u.id} value={u.id}>{u.full_name}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div>
                      <Label>{t.serviceOrders.scheduledStart}</Label>
                      <Input type="datetime-local" value={timeForm.started_at}
                        onChange={(e) => setTimeForm({ ...timeForm, started_at: e.target.value })} />
                    </div>
                    <div>
                      <Label>{t.serviceOrders.scheduledEnd}</Label>
                      <Input type="datetime-local" value={timeForm.ended_at}
                        onChange={(e) => setTimeForm({ ...timeForm, ended_at: e.target.value })} />
                    </div>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div>
                      <Label>Duração (min)</Label>
                      <Input type="number" value={timeForm.duration_minutes}
                        onChange={(e) => setTimeForm({ ...timeForm, duration_minutes: parseInt(e.target.value) || 0 })} />
                    </div>
                    <div className="flex items-end gap-2">
                      <label className="flex items-center gap-1.5 text-sm">
                        <Switch checked={timeForm.billable}
                          onCheckedChange={(v) => setTimeForm({ ...timeForm, billable: v })} />
                        {t.serviceOrders.billable}
                      </label>
                    </div>
                    <div>
                      <Label>{t.common.notes}</Label>
                      <Input value={timeForm.notes}
                        onChange={(e) => setTimeForm({ ...timeForm, notes: e.target.value })} />
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <Button size="sm" onClick={handleAddTime} disabled={addTime.isPending}>{t.common.save}</Button>
                    <Button size="sm" variant="outline" onClick={() => setShowTimeForm(false)}>{t.common.cancel}</Button>
                  </div>
                </div>
              )}
              {(!timeEntries || timeEntries.length === 0) ? (
                <p className="text-sm text-muted-foreground p-5">{t.serviceOrders.noTimeEntries}</p>
              ) : (
                <div className="divide-y">
                  {timeEntries.map((te: any) => (
                    <div key={te.id} className="flex items-start justify-between p-4">
                      <div>
                        <p className="text-sm font-medium">{te.app_users?.full_name}</p>
                        {te.notes && <p className="text-xs text-muted-foreground">{te.notes}</p>}
                        <p className="text-xs text-muted-foreground mt-1">
                          {formatDateTime(te.started_at)} → {te.ended_at ? formatDateTime(te.ended_at) : '...'}
                        </p>
                      </div>
                      <div className="flex items-center gap-3">
                        <div className="text-right">
                          <p className="text-sm font-semibold">{((te.duration_minutes || 0) / 60).toFixed(1)}h</p>
                          <StatusBadge className={te.billable ? 'bg-success/15 text-success' : 'bg-muted text-muted-foreground'}>
                            {te.billable ? t.serviceOrders.billable : t.serviceOrders.nonBillable}
                          </StatusBadge>
                        </div>
                        <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive"
                          onClick={() => removeTime.mutate({ id: te.id, service_order_id: orderId! })}>
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </DialogContent>
        </Dialog>
      )}
    </>
  );
}
