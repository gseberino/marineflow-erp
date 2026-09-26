// "+ Lançar": uma porta só para registrar qualquer movimento à mão.
//
// Pedido do dono (26/09/2026): "seria interessante ter a opção de lançar manualmente alguma
// despesa". Existia — espalhado em cinco portas, nenhuma chamada "lançar despesa" (Nova
// Despesa em Contas a Pagar, Lançar no Caixa escondido atrás de um seletor, Anotar antes do
// banco, a OS e o WhatsApp). Aqui a pessoa diz quanto, o que foi e POR ONDE pagou; o sistema
// escolhe o caminho — as mesmas funções do banco que o assistente do WhatsApp chama:
//   dinheiro → lancar_no_caixa · banco/cartão → anotar_transacao (casa com a linha quando ela
//   chegar) · bolso de sócio → lancar_no_caixa como reembolso · ainda vou pagar → conta a pagar.
// É o que o QuickBooks separa em "Expense" (já paguei) × "Bill" (vou pagar), numa janela só.
import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { EntityCombobox } from '@/components/EntityCombobox';
import { CategoriaDespesaSelect } from '@/components/CategoriaDespesaSelect';
import { MoneyInput } from '@/components/MoneyInput';
import { Ajuda } from '@/components/Ajuda';
import { usePayees, useServiceOrdersVinculaveis, useClientesParaReceita, ROTULO_TIPO } from '@/hooks/use-payees';
import { useSuppliers } from '@/hooks/use-suppliers';
import { useFinanceRules } from '@/hooks/use-finance-review';
import { useLancarNoCaixa, useMoverCaixa, useAjustarCaixa, useAnotarTransacao } from '@/hooks/use-caixa';
import { useCreatePayable, useCreateReceivable } from '@/hooks/use-financial';
import { destinoDoGasto } from '@/lib/destino-do-gasto';
import type { RegraFinanceira } from '../../supabase/functions/_shared/banking/proposals';
import { toast } from 'sonner';
import { mensagemDoErro } from '@/hooks/use-lancamentos';
import { cn } from '@/lib/utils';

export type TipoDeLancamento = 'despesa' | 'recebimento' | 'transferencia' | 'contagem';
export type PorOnde = 'caixa' | 'banco' | 'cartao' | 'socio' | 'depois';

const TIPOS: Array<[TipoDeLancamento, string]> = [
  ['despesa', 'Despesa'], ['recebimento', 'Recebimento'], ['transferencia', 'Transferência'], ['contagem', 'Contei o dinheiro'],
];

const POR_ONDE_DESPESA: Array<[PorOnde, string, string]> = [
  ['caixa', 'Dinheiro do Caixa', 'Sai do Caixa (dinheiro vivo) agora.'],
  ['banco', 'Pix, débito ou boleto', 'Fica anotado; quando a linha chegar do banco, entra já classificada (se já chegou, classifica na hora).'],
  ['cartao', 'Cartão de crédito', 'Fica anotado; casa com a compra quando ela aparecer na fatura.'],
  ['socio', 'Do bolso de um sócio', 'Vira despesa e fica como reembolso a pagar ao sócio. O Caixa não mexe.'],
  ['depois', 'Ainda vou pagar', 'Vira conta a pagar, com vencimento.'],
];
const POR_ONDE_RECEBIMENTO: Array<[PorOnde, string, string]> = [
  ['caixa', 'Em dinheiro', 'Entra no Caixa agora.'],
  ['banco', 'Pix, transferência ou boleto', 'Fica anotado; quando o dinheiro aparecer no banco, a linha entra já ligada ao cliente.'],
  ['depois', 'Ainda vai pagar', 'Vira conta a receber, com vencimento.'],
];

function hoje(): string {
  return new Date(Date.now() - 3 * 3600_000).toISOString().slice(0, 10);
}

export function LancarDialog({ onFechar, tipoInicial = 'despesa', porOndeInicial }: {
  onFechar: () => void;
  tipoInicial?: TipoDeLancamento;
  porOndeInicial?: PorOnde;
}) {
  const [tipo, setTipo] = useState<TipoDeLancamento>(tipoInicial);
  const [porOnde, setPorOnde] = useState<PorOnde | null>(porOndeInicial ?? null);
  const [valor, setValor] = useState(0);
  const [descricao, setDescricao] = useState('');
  const [data, setData] = useState('');
  const [vencimento, setVencimento] = useState('');
  const [categoria, setCategoria] = useState('');
  const [quem, setQuem] = useState('');
  const [cliente, setCliente] = useState('');
  const [os, setOs] = useState('');
  const [socio, setSocio] = useState('');
  const [sentidoTransf, setSentidoTransf] = useState<'saque' | 'deposito'>('saque');
  const [contado, setContado] = useState(0);
  const [motivo, setMotivo] = useState('');

  const { data: favorecidos = [] } = usePayees();
  const { data: fornecedores = [] } = useSuppliers();
  const { data: clientes = [] } = useClientesParaReceita(tipo === 'recebimento');
  const { data: ordens = [] } = useServiceOrdersVinculaveis();
  const { data: regras = [] } = useFinanceRules();
  const lancarNoCaixa = useLancarNoCaixa();
  const mover = useMoverCaixa();
  const ajustar = useAjustarCaixa();
  const anotar = useAnotarTransacao();
  const criarPagar = useCreatePayable();
  const criarReceber = useCreateReceivable();
  const ocupado = [lancarNoCaixa, mover, ajustar, anotar, criarPagar, criarReceber].some((m) => m.isPending);

  const socios = favorecidos.filter((f) => f.kind === 'socio');
  const quemRecebe = [
    ...favorecidos.map((f) => ({ value: `p:${f.id}`, label: f.name, description: ROTULO_TIPO[f.kind] })),
    ...fornecedores.map((s) => ({ value: `f:${s.id}`, label: s.name, description: 'Fornecedor', searchTerms: [s.cnpj_cpf || ''] })),
  ];
  const favorecido = quem.startsWith('p:') ? favorecidos.find((f) => f.id === quem.slice(2)) : undefined;
  const fornecedor = quem.startsWith('f:') ? fornecedores.find((f) => f.id === quem.slice(2)) : undefined;
  const destino = tipo === 'despesa'
    ? destinoDoGasto(categoria, favorecido ? { nome: favorecido.name, categoria: favorecido.default_category } : null,
        descricao, valor, regras as unknown as RegraFinanceira[])
    : null;
  const opcoes = tipo === 'recebimento' ? POR_ONDE_RECEBIMENTO : POR_ONDE_DESPESA;
  const escolhida = opcoes.find(([k]) => k === porOnde);

  const falta = (() => {
    if (tipo === 'contagem') return !motivo.trim() ? 'o motivo' : null;
    if (!(valor > 0)) return 'o valor';
    if (tipo === 'transferencia') return null;
    if (!descricao.trim()) return 'o que foi';
    if (tipo === 'recebimento' && !cliente) return 'o cliente';
    if (!escolhida) return 'por onde';
    if (porOnde === 'socio' && !socio) return 'o sócio';
    if (porOnde === 'depois' && !vencimento) return 'o vencimento';
    // Anotação do banco sem categoria decidida, sem quem e sem OS: a função recusa (não há o que
    // classificar) e mandar a reserva "Outras despesas" apagaria o que o motor acharia sozinho.
    if (tipo === 'despesa' && (porOnde === 'banco' || porOnde === 'cartao') && destino?.reserva && !quem && !os) return 'a categoria ou para quem';
    return null;
  })();

  const fim = { onSuccess: () => onFechar() };
  const erro = (e: unknown) => toast.error(mensagemDoErro(e));

  const salvar = () => {
    if (falta) return;
    if (tipo === 'contagem') { ajustar.mutate({ saldoContado: contado, motivo: motivo.trim() }, fim); return; }
    if (tipo === 'transferencia') { mover.mutate({ sentido: sentidoTransf, valor, data: data || null }, fim); return; }
    const desc = descricao.trim();
    const favorecidoId = favorecido?.id ?? null;
    const fornecedorId = fornecedor?.id ?? null;

    if (tipo === 'despesa') {
      const cat = destino?.categoria ?? null;
      if (porOnde === 'caixa' || porOnde === 'socio') {
        lancarNoCaixa.mutate({
          sentido: 'saida', valor, descricao: desc, data: data || null, categoria: cat,
          favorecidoId, fornecedorId, osId: os || null,
          pagoPor: porOnde === 'socio' ? 'socio' : 'caixa', socioId: porOnde === 'socio' ? socio : null,
        }, fim);
      } else if (porOnde === 'banco' || porOnde === 'cartao') {
        anotar.mutate({
          sentido: 'saida', valor, data: data || null, categoria: destino?.reserva ? null : cat, favorecidoId, fornecedorId,
          osId: os || null, descricao: desc,
        }, fim);
      } else if (porOnde === 'depois') {
        criarPagar.mutate({
          description: desc, issue_date: hoje(), due_date: vencimento, amount: valor,
          expense_category: cat ?? undefined, supplier_id: fornecedorId ?? undefined,
          supplier_name: fornecedor?.name ?? favorecido?.name ?? undefined,
          payee_id: favorecidoId ?? undefined, linked_service_order_id: os || undefined,
        }, { onSuccess: () => { toast.success('Conta a pagar criada'); onFechar(); }, onError: erro });
      }
      return;
    }

    // Recebimento
    if (porOnde === 'caixa') {
      lancarNoCaixa.mutate({ sentido: 'entrada', valor, descricao: desc, data: data || null, clienteId: cliente, osId: os || null }, fim);
    } else if (porOnde === 'banco') {
      anotar.mutate({ sentido: 'entrada', valor, data: data || null, clienteId: cliente, osId: os || null, descricao: desc }, fim);
    } else if (porOnde === 'depois') {
      criarReceber.mutate({
        client_id: cliente, description: desc, issue_date: hoje(), due_date: vencimento, amount: valor,
        service_order_id: os || undefined,
      }, { onSuccess: () => { toast.success('Conta a receber criada'); onFechar(); }, onError: erro });
    }
  };

  const trocarTipo = (t: TipoDeLancamento) => { setTipo(t); if (t !== tipo) setPorOnde(null); };

  return (
    <Dialog open onOpenChange={(v) => { if (!v) onFechar(); }}>
      <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Lançar</DialogTitle>
          <DialogDescription>Diga quanto foi, o que foi e por onde passou o dinheiro. O sistema põe no lugar certo.</DialogDescription>
        </DialogHeader>

        <div className="flex flex-wrap gap-1" role="tablist" aria-label="O que lançar">
          {TIPOS.map(([t, r]) => (
            <Button key={t} role="tab" aria-selected={tipo === t} size="sm" variant={tipo === t ? 'default' : 'outline'}
              className="h-8 text-xs" onClick={() => trocarTipo(t)}>{r}</Button>
          ))}
        </div>

        {tipo === 'contagem' && (
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Quanto dinheiro vivo da EMPRESA há agora. O Caixa passa a bater com a contagem, e a sobra ou a
              falta fica registrada com o motivo. Serve também para o saldo inicial. Dinheiro pessoal não entra.
            </p>
            <div><Label>Quanto há no caixa agora</Label><MoneyInput value={contado} onValueChange={setContado} aria-label="Saldo contado" /></div>
            <div><Label htmlFor="lancar-motivo">Motivo</Label><Input id="lancar-motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Ex.: saldo inicial; contagem de sexta" /></div>
          </div>
        )}

        {tipo === 'transferencia' && (
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">Dinheiro que só mudou de lugar: não é despesa nem receita.</p>
            <div className="flex flex-wrap gap-1">
              {([['saque', 'Saque do banco para o Caixa'], ['deposito', 'Depósito do Caixa no banco']] as const).map(([s, r]) => (
                <Button key={s} size="sm" variant={sentidoTransf === s ? 'default' : 'outline'} className="h-8 text-xs" onClick={() => setSentidoTransf(s)}>{r}</Button>
              ))}
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div><Label>Valor *</Label><MoneyInput value={valor} onValueChange={setValor} aria-label="Valor" /></div>
              <div><Label htmlFor="lancar-data-t">Data</Label><Input id="lancar-data-t" type="date" value={data} onChange={(e) => setData(e.target.value)} /></div>
            </div>
          </div>
        )}

        {(tipo === 'despesa' || tipo === 'recebimento') && (
          <div className="space-y-3">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div><Label>Valor *</Label><MoneyInput value={valor} onValueChange={setValor} aria-label="Valor" /></div>
              {porOnde === 'depois'
                ? <div><Label htmlFor="lancar-venc">Vencimento *</Label><Input id="lancar-venc" type="date" value={vencimento} onChange={(e) => setVencimento(e.target.value)} /></div>
                : <div><Label htmlFor="lancar-data">Quando</Label><Input id="lancar-data" type="date" value={data} onChange={(e) => setData(e.target.value)} /></div>}
              <div className="sm:col-span-2">
                <Label htmlFor="lancar-desc">O que foi *</Label>
                <Input id="lancar-desc" value={descricao} onChange={(e) => setDescricao(e.target.value)}
                  placeholder={tipo === 'despesa' ? 'Ex.: almoço da equipe, gasolina da van, peça no balcão' : 'Ex.: serviço pago pelo cliente'} />
              </div>
              {tipo === 'despesa' ? (
                <>
                  <div className="sm:col-span-2">
                    <Label>Para quem (opcional)</Label>
                    <EntityCombobox value={quem} onChange={setQuem} options={[{ value: '', label: '— ninguém em especial' }, ...quemRecebe]} placeholder="— ninguém em especial" fullWidth />
                  </div>
                  <div>
                    <Label className="flex items-center gap-1">Categoria
                      <Ajuda rotulo="Como a categoria é escolhida">
                        Se você não escolher, vale a categoria padrão de quem recebeu; sem ela, o sistema deduz pelo
                        que você escreveu (almoço → Alimentação de campo) — a mesma leitura do Extrato e do assistente.
                      </Ajuda>
                    </Label>
                    <CategoriaDespesaSelect valor={categoria} onMudar={setCategoria} className="h-10 text-sm" placeholder="Deduzir pelo texto" />
                  </div>
                  {destino && (descricao.trim() || categoria) && (
                    <p className="self-end pb-2 text-xs text-muted-foreground" aria-live="polite">
                      Vai entrar em: <b className="text-foreground">{destino.categoria}</b>{destino.porque ? ` (${destino.porque})` : ''}
                    </p>
                  )}
                </>
              ) : (
                <div className="sm:col-span-2">
                  <Label>Cliente *</Label>
                  <EntityCombobox value={cliente} onChange={setCliente} options={clientes.map((c) => ({ value: c.id, label: c.name }))} placeholder="De quem veio?" fullWidth />
                </div>
              )}
              <div className="sm:col-span-2">
                <Label>OS (opcional)</Label>
                <EntityCombobox value={os} onChange={setOs} options={[{ value: '', label: '— nenhuma' }, ...ordens.map((o) => ({ value: o.id, label: o.service_order_number, description: o.clients?.name ?? undefined }))]} placeholder="— nenhuma" fullWidth />
              </div>
            </div>

            <fieldset className="space-y-1.5">
              <legend className="text-sm font-medium">{tipo === 'despesa' ? 'Já pagou? Por onde?' : 'Já recebeu? Por onde?'}</legend>
              <div className="grid grid-cols-1 gap-1.5 sm:grid-cols-2">
                {opcoes.map(([k, r]) => (
                  <Button key={k} type="button" variant={porOnde === k ? 'default' : 'outline'} aria-pressed={porOnde === k}
                    className={cn('h-auto justify-start whitespace-normal py-2 text-left text-sm')} onClick={() => setPorOnde(k)}>
                    {r}
                  </Button>
                ))}
              </div>
              {escolhida && <p className="text-xs text-muted-foreground">{escolhida[2]}</p>}
              {porOnde === 'socio' && (
                <EntityCombobox value={socio} onChange={setSocio} options={socios.map((s) => ({ value: s.id, label: s.name }))} placeholder="Qual sócio pagou?" fullWidth />
              )}
            </fieldset>
          </div>
        )}

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onFechar}>Cancelar</Button>
          <Button onClick={salvar} disabled={!!falta || ocupado}>
            {ocupado ? 'Lançando…' : falta ? `Falta ${falta}` : 'Lançar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
