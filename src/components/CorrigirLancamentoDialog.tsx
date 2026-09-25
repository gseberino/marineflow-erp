// Corrigir um lançamento — inclusive o que já está pago.
//
// O dono deixou de confiar no financeiro porque o que ele aprovava não tinha conserto: conta
// paga não abria, fornecedor e OS não mudavam depois de criados. Aqui tudo que pode estar
// errado num lançamento se corrige, e cada correção vai para a trilha com o antes e o depois.
//
// Duas coisas NÃO se corrigem aqui, de propósito:
//   * o valor de um lançamento que veio do banco — o número é o do extrato. Se ele está
//     errado, o caminho é desfazer a aprovação;
//   * lançamento de mês fechado — só a observação muda. O banco recusa o resto e a tela avisa
//     antes, para ninguém preencher o formulário à toa.
import { useEffect, useMemo, useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { EntityCombobox } from '@/components/EntityCombobox';
import { CategoriaDespesaSelect } from '@/components/CategoriaDespesaSelect';
import { QuickSupplierDialog } from '@/components/QuickSupplierDialog';
import { MoneyInput } from '@/components/MoneyInput';
import { useSuppliers } from '@/hooks/use-suppliers';
import { useCostCenters } from '@/hooks/use-cost-centers';
import { usePayees, useServiceOrdersVinculaveis, useClientesParaReceita, ROTULO_TIPO } from '@/hooks/use-payees';
import { usePeriodosFechados } from '@/hooks/use-fechamento';
import { useCorrigirLancamento, type TipoDeLancamento } from '@/hooks/use-lancamentos';
import { useI18n } from '@/i18n';
import { toast } from 'sonner';
import { Landmark, Lock } from 'lucide-react';

/** Sentinela de "nenhum" nos Selects: o Radix não aceita value vazio num item. */
const NENHUM = '__nenhum__';

/** A linha como as listas de contas a pagar e a receber já a carregam. */
export interface LancamentoParaCorrigir {
  id: string;
  description: string | null;
  amount: number | string | null;
  paid_amount?: number | string | null;
  status: string | null;
  issue_date: string | null;
  due_date: string | null;
  notes?: string | null;
  cost_center_id?: string | null;
  bank_transaction_id?: string | null;
  // a pagar
  expense_category?: string | null;
  supplier_id?: string | null;
  payee_id?: string | null;
  linked_service_order_id?: string | null;
  // a receber
  category?: string | null;
  client_id?: string | null;
  service_order_id?: string | null;
  service_orders?: { service_order_number?: string | null } | null;
  clients?: { name?: string | null } | null;
}

export interface Formulario {
  description: string;
  notes: string;
  categoria: string;
  contraparte: string;   // supplier_id (a pagar) ou client_id (a receber)
  payee_id: string;
  os: string;
  cost_center_id: string;
  issue_date: string;
  due_date: string;
  amount: number;
}

function doLancamento(l: LancamentoParaCorrigir, tipo: TipoDeLancamento): Formulario {
  return {
    description: l.description ?? '',
    notes: l.notes ?? '',
    categoria: (tipo === 'payable' ? l.expense_category : l.category) ?? '',
    contraparte: (tipo === 'payable' ? l.supplier_id : l.client_id) ?? '',
    payee_id: l.payee_id ?? '',
    os: (tipo === 'payable' ? l.linked_service_order_id : l.service_order_id) ?? '',
    cost_center_id: l.cost_center_id ?? '',
    issue_date: l.issue_date ?? '',
    due_date: l.due_date ?? '',
    amount: Number(l.amount ?? 0),
  };
}

/**
 * Só o que mudou vai para o banco. Mandar o formulário inteiro faria a trilha registrar
 * "corrigiu 10 campos" quando o dono trocou só a categoria — e trilha que exagera é trilha
 * que ninguém lê.
 */
export function camposQueMudaram(
  antes: Formulario, depois: Formulario, tipo: TipoDeLancamento,
): Record<string, string | number | null> {
  const nulo = (v: string) => (v.trim() === '' ? null : v.trim());
  const campos: Record<string, string | number | null> = {};
  if (depois.description.trim() !== antes.description.trim()) campos.description = depois.description.trim();
  if (depois.notes.trim() !== antes.notes.trim()) campos.notes = nulo(depois.notes);
  if (depois.categoria !== antes.categoria) campos[tipo === 'payable' ? 'expense_category' : 'category'] = nulo(depois.categoria);
  if (depois.contraparte !== antes.contraparte) campos[tipo === 'payable' ? 'supplier_id' : 'client_id'] = nulo(depois.contraparte);
  if (tipo === 'payable' && depois.payee_id !== antes.payee_id) campos.payee_id = nulo(depois.payee_id);
  if (depois.os !== antes.os) campos[tipo === 'payable' ? 'linked_service_order_id' : 'service_order_id'] = nulo(depois.os);
  if (depois.cost_center_id !== antes.cost_center_id) campos.cost_center_id = nulo(depois.cost_center_id);
  if (depois.issue_date !== antes.issue_date) campos.issue_date = depois.issue_date;
  if (depois.due_date !== antes.due_date) campos.due_date = depois.due_date;
  if (Math.abs(depois.amount - antes.amount) >= 0.005) campos.amount = Math.round(depois.amount * 100) / 100;
  return campos;
}

export function CorrigirLancamentoDialog({
  tipo, lancamento, onFechar,
}: {
  tipo: TipoDeLancamento;
  lancamento: LancamentoParaCorrigir | null;
  onFechar: () => void;
}) {
  const { formatCurrency, formatDate } = useI18n();
  const ehPagar = tipo === 'payable';
  const aberto = !!lancamento;

  const { data: fornecedores = [] } = useSuppliers();
  const { data: clientes = [] } = useClientesParaReceita(aberto && !ehPagar);
  const { data: favorecidos = [] } = usePayees();
  const { data: ordens = [] } = useServiceOrdersVinculaveis();
  const { data: centros = [] } = useCostCenters();
  const { data: periodos = [] } = usePeriodosFechados();
  const corrigir = useCorrigirLancamento();

  const inicial = useMemo(() => (lancamento ? doLancamento(lancamento, tipo) : null), [lancamento, tipo]);
  const [f, setF] = useState<Formulario | null>(inicial);
  const [motivo, setMotivo] = useState('');
  const [novoFornecedor, setNovoFornecedor] = useState<string | null>(null);

  useEffect(() => { setF(inicial); setMotivo(''); }, [inicial]);

  const veioDoBanco = !!lancamento?.bank_transaction_id;
  const mesFechado = useMemo(() => {
    const d = lancamento?.issue_date;
    if (!d) return false;
    const [ano, mes] = d.split('-').map(Number);
    return periodos.some((p) => p.ano === ano && p.mes === mes && !p.reaberto_em);
  }, [lancamento?.issue_date, periodos]);

  // A OS atual pode estar faturada e, por isso, fora da lista de vinculáveis — mas ela
  // precisa continuar aparecendo, senão o campo mostra vazio e parece que não há vínculo.
  const opcoesDeOS = useMemo(() => {
    const lista = ordens.map((o) => ({
      value: o.id, label: o.service_order_number, description: o.clients?.name ?? undefined,
    }));
    const atual = inicial?.os;
    if (atual && !lista.some((o) => o.value === atual)) {
      lista.unshift({ value: atual, label: lancamento?.service_orders?.service_order_number ?? 'OS atual', description: 'faturada ou encerrada' });
    }
    return [{ value: '', label: '— nenhuma' }, ...lista];
  }, [ordens, inicial?.os, lancamento?.service_orders?.service_order_number]);

  if (!lancamento || !f || !inicial) return null;

  const mudar = (p: Partial<Formulario>) => setF((atual) => (atual ? { ...atual, ...p } : atual));
  const campos = camposQueMudaram(inicial, f, tipo);
  const nada = Object.keys(campos).length === 0;
  const soObservacao = Object.keys(campos).every((k) => k === 'notes');

  const salvar = () => {
    if (nada) { onFechar(); return; }
    if (!f.description.trim()) { toast.error('A descrição não pode ficar vazia.'); return; }
    if (!ehPagar && !f.contraparte) { toast.error('Conta a receber precisa de cliente.'); return; }
    corrigir.mutate(
      { tipo, id: lancamento.id, campos, motivo: motivo.trim() || null },
      { onSuccess: () => onFechar() },
    );
  };

  const pago = Number(lancamento.paid_amount ?? 0);

  return (
    <Dialog open={aberto} onOpenChange={(v) => { if (!v) onFechar(); }}>
      <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Corrigir {ehPagar ? 'conta a pagar' : 'conta a receber'}</DialogTitle>
          <DialogDescription>
            {formatCurrency(Number(lancamento.amount ?? 0))}
            {lancamento.status === 'paid' ? ' · pago' : pago > 0 ? ` · ${formatCurrency(pago)} pago` : ' · em aberto'}
            {lancamento.issue_date ? ` · ${formatDate(lancamento.issue_date)}` : ''}
            . Toda correção fica registrada na trilha do Fechamento.
          </DialogDescription>
        </DialogHeader>

        {mesFechado && (
          <div className="flex items-start gap-2 rounded-md border border-amber-500/40 bg-amber-500/5 p-2 text-sm">
            <Lock className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
            <span className="min-w-0">
              O mês deste lançamento está fechado. Só a observação pode mudar; para o resto,
              reabra o mês em Financeiro › Fechamento.
            </span>
          </div>
        )}

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="sm:col-span-2">
            <Label>{ehPagar ? 'Fornecedor' : 'Cliente'}</Label>
            {ehPagar ? (
              <EntityCombobox
                value={f.contraparte}
                onChange={(v) => mudar({ contraparte: v })}
                placeholder="— sem fornecedor"
                options={[
                  { value: '', label: '— sem fornecedor' },
                  ...fornecedores.map((s) => ({
                    value: s.id, label: s.name, description: s.cnpj_cpf || undefined,
                    searchTerms: [s.cnpj_cpf || '', s.email || ''],
                  })),
                ]}
                onCreate={(digitado) => setNovoFornecedor(digitado)}
                createLabel="+ Cadastrar fornecedor"
                disabled={mesFechado}
                fullWidth
              />
            ) : (
              <EntityCombobox
                value={f.contraparte}
                onChange={(v) => mudar({ contraparte: v })}
                placeholder="Escolher cliente"
                options={clientes.map((c) => ({ value: c.id, label: c.name }))}
                fallbackLabel={lancamento.clients?.name ?? undefined}
                disabled={mesFechado}
                fullWidth
              />
            )}
          </div>

          <div>
            <Label>Categoria</Label>
            <CategoriaDespesaSelect
              valor={f.categoria}
              onMudar={(v) => mudar({ categoria: v })}
              tipo={tipo}
              className="h-10 text-sm"
            />
          </div>

          {ehPagar && (
            <div>
              <Label>Favorecido (pessoa)</Label>
              <Select
                value={f.payee_id || NENHUM}
                onValueChange={(v) => mudar({ payee_id: v === NENHUM ? '' : v })}
                disabled={mesFechado}
              >
                <SelectTrigger><SelectValue placeholder="— nenhum" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={NENHUM}>— nenhum</SelectItem>
                  {favorecidos.map((p) => (
                    <SelectItem key={p.id} value={p.id}>{p.name} · {ROTULO_TIPO[p.kind]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className={ehPagar ? 'sm:col-span-2' : undefined}>
            <Label>{ehPagar ? 'OS (custo de qual serviço)' : 'OS'}</Label>
            <EntityCombobox
              value={f.os}
              onChange={(v) => mudar({ os: v })}
              placeholder="— nenhuma"
              options={opcoesDeOS}
              disabled={mesFechado}
              fullWidth
            />
          </div>

          <div className="sm:col-span-2">
            <Label htmlFor="corrigir-descricao">Descrição</Label>
            <Input id="corrigir-descricao" value={f.description} onChange={(e) => mudar({ description: e.target.value })} disabled={mesFechado} />
          </div>

          <div>
            <Label htmlFor="corrigir-data">Data do lançamento</Label>
            <Input id="corrigir-data" type="date" value={f.issue_date} onChange={(e) => mudar({ issue_date: e.target.value })} disabled={mesFechado} />
          </div>
          <div>
            <Label htmlFor="corrigir-vencimento">Vencimento</Label>
            <Input id="corrigir-vencimento" type="date" value={f.due_date} onChange={(e) => mudar({ due_date: e.target.value })} disabled={mesFechado} />
          </div>

          <div>
            <Label>Valor</Label>
            {veioDoBanco ? (
              <>
                <Input readOnly value={formatCurrency(f.amount)} className="bg-muted" />
                <p className="mt-0.5 flex items-center gap-1 text-[11px] text-muted-foreground">
                  <Landmark className="h-3 w-3 shrink-0" />
                  Veio do extrato. Para mudar, desfaça a aprovação.
                </p>
              </>
            ) : (
              <MoneyInput value={f.amount} onValueChange={(v) => mudar({ amount: v })} disabled={mesFechado} />
            )}
          </div>

          <div>
            <Label>Centro de custo</Label>
            <Select
              value={f.cost_center_id || NENHUM}
              onValueChange={(v) => mudar({ cost_center_id: v === NENHUM ? '' : v })}
              disabled={mesFechado}
            >
              <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
              <SelectContent>
                <SelectItem value={NENHUM}>—</SelectItem>
                {(centros ?? [])
                  .filter((c) => (ehPagar ? c.type !== 'revenue' : c.type !== 'expense'))
                  .map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          <div className="sm:col-span-2">
            <Label htmlFor="corrigir-observacoes">Observações</Label>
            <Textarea id="corrigir-observacoes" rows={2} value={f.notes} onChange={(e) => mudar({ notes: e.target.value })} />
          </div>

          {!nada && !soObservacao && (
            <div className="sm:col-span-2">
              <Label htmlFor="corrigir-motivo">Por que corrigir? <span className="font-normal text-muted-foreground">(opcional, vai para a trilha)</span></Label>
              <Input id="corrigir-motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Ex.: era almoço da equipe, não material" />
            </div>
          )}
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onFechar}>Fechar</Button>
          <Button onClick={salvar} disabled={corrigir.isPending || nada || (mesFechado && !soObservacao)}>
            {corrigir.isPending ? 'Salvando…' : nada ? 'Nada mudou' : 'Salvar correção'}
          </Button>
        </DialogFooter>
      </DialogContent>

      {ehPagar && novoFornecedor != null && (
        <QuickSupplierDialog
          open={novoFornecedor != null}
          onOpenChange={(v) => { if (!v) setNovoFornecedor(null); }}
          initialName={novoFornecedor ?? ''}
          onCreated={(s) => { mudar({ contraparte: s.id }); setNovoFornecedor(null); }}
        />
      )}
    </Dialog>
  );
}
