// Anotação antecipada pela tela (Fase 4 do Financeiro Confiável).
//
// As mesmas funções que o assistente do WhatsApp chama. Na tela, os cadastros são
// escolhidos em lista; no WhatsApp, pelo nome dito — o banco recebe a mesma coisa.
// Lançar no Caixa e "Contei o dinheiro" moraram aqui até 26/09/2026; hoje são abas da
// janela única "+ Lançar" (LancarDialog), que a ficha do Caixa abre já no lugar certo.
import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { EntityCombobox } from '@/components/EntityCombobox';
import { CategoriaDespesaSelect } from '@/components/CategoriaDespesaSelect';
import { MoneyInput } from '@/components/MoneyInput';
import { useI18n } from '@/i18n';
import { usePayees, useServiceOrdersVinculaveis, useClientesParaReceita, ROTULO_TIPO } from '@/hooks/use-payees';
import { useSuppliers } from '@/hooks/use-suppliers';
import { useAnotarTransacao, useAnotacoesAguardando, useCancelarAnotacao } from '@/hooks/use-caixa';
import { Clock, X } from 'lucide-react';

/** "Quem": favorecido (pessoa) ou fornecedor, numa lista só — como a pessoa pensa. */
function useQuemRecebe() {
  const { data: favorecidos = [] } = usePayees();
  const { data: fornecedores = [] } = useSuppliers();
  return [
    ...favorecidos.map((f) => ({ value: `p:${f.id}`, label: f.name, description: ROTULO_TIPO[f.kind] })),
    ...fornecedores.map((s) => ({ value: `f:${s.id}`, label: s.name, description: 'Fornecedor', searchTerms: [s.cnpj_cpf || ''] })),
  ];
}

export function AnotarTransacaoDialog({ onFechar }: { onFechar: () => void }) {
  const [sentido, setSentido] = useState<'saida' | 'entrada'>('saida');
  const [valor, setValor] = useState(0);
  const [data, setData] = useState('');
  const [documento, setDocumento] = useState('');
  const [quem, setQuem] = useState('');
  const [cliente, setCliente] = useState('');
  const [categoria, setCategoria] = useState('');
  const [os, setOs] = useState('');
  const [descricao, setDescricao] = useState('');
  const quemRecebe = useQuemRecebe();
  const { data: clientes = [] } = useClientesParaReceita(sentido === 'entrada');
  const { data: ordens = [] } = useServiceOrdersVinculaveis();
  const anotar = useAnotarTransacao();
  const temClassificacao = !!(quem || cliente || categoria || os);

  return (
    <Dialog open onOpenChange={(v) => { if (!v) onFechar(); }}>
      <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Anotar antes do banco</DialogTitle>
          <DialogDescription>Um Pix ou boleto que o banco ainda vai trazer. Quando a linha chegar, ela entra já classificada.</DialogDescription>
        </DialogHeader>
        <div className="flex gap-1">
          {(['saida', 'entrada'] as const).map((s) => (
            <Button key={s} size="sm" variant={sentido === s ? 'default' : 'outline'} className="h-8 text-xs" onClick={() => setSentido(s)}>
              {s === 'saida' ? 'Saída' : 'Entrada'}
            </Button>
          ))}
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div><Label>Valor *</Label><MoneyInput value={valor} onValueChange={setValor} aria-label="Valor" /></div>
          <div><Label htmlFor="anot-data">Data</Label><Input id="anot-data" type="date" value={data} onChange={(e) => setData(e.target.value)} /></div>
          <div className="sm:col-span-2"><Label htmlFor="anot-doc">CPF/CNPJ (opcional)</Label><Input id="anot-doc" value={documento} onChange={(e) => setDocumento(e.target.value)} /></div>
          {sentido === 'saida' ? (
            <div className="sm:col-span-2"><Label>Classificar como</Label>
              <EntityCombobox value={quem} onChange={setQuem} options={[{ value: '', label: '—' }, ...quemRecebe]} placeholder="Fornecedor ou favorecido" fullWidth /></div>
          ) : (
            <div className="sm:col-span-2"><Label>Cliente</Label>
              <EntityCombobox value={cliente} onChange={setCliente} options={clientes.map((c) => ({ value: c.id, label: c.name }))} placeholder="De quem vai entrar?" fullWidth /></div>
          )}
          <div><Label>Categoria</Label><CategoriaDespesaSelect valor={categoria} onMudar={setCategoria} tipo={sentido === 'saida' ? 'payable' : 'receivable'} className="h-10 text-sm" /></div>
          <div><Label>OS</Label>
            <EntityCombobox value={os} onChange={setOs} options={[{ value: '', label: '— nenhuma' }, ...ordens.map((o) => ({ value: o.id, label: o.service_order_number }))]} placeholder="— nenhuma" fullWidth /></div>
          <div className="sm:col-span-2"><Label htmlFor="anot-desc">Descrição (opcional)</Label><Input id="anot-desc" value={descricao} onChange={(e) => setDescricao(e.target.value)} /></div>
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onFechar}>Cancelar</Button>
          <Button disabled={!(valor > 0) || !temClassificacao || anotar.isPending}
            title={!temClassificacao ? 'Diga como classificar: quem, categoria ou OS' : undefined}
            onClick={() => anotar.mutate({
              sentido, valor, data: data || null, documento: documento || null,
              favorecidoId: quem.startsWith('p:') ? quem.slice(2) : null, fornecedorId: quem.startsWith('f:') ? quem.slice(2) : null,
              clienteId: sentido === 'entrada' ? cliente || null : null, categoria: categoria || null, osId: os || null,
              descricao: descricao || null,
            }, { onSuccess: () => onFechar() })}>
            Anotar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** O que foi anotado e ainda espera o banco — com cancelar. */
export function AnotacoesAguardando() {
  const { formatCurrency, formatDate } = useI18n();
  const { data = [] } = useAnotacoesAguardando();
  const cancelar = useCancelarAnotacao();
  if (data.length === 0) return null;
  return (
    <Card className="p-3">
      <p className="mb-2 flex items-center gap-2 text-sm font-medium"><Clock className="h-4 w-4 text-primary" /> Anotado, esperando o banco ({data.length})</p>
      <ul className="space-y-1 text-sm">
        {data.map((a) => (
          <li key={a.id} className="flex min-w-0 items-center gap-2">
            <span className="min-w-0 flex-1 truncate">
              {a.sentido === 'debit' ? 'Saída' : 'Entrada'} de <b>{formatCurrency(Number(a.valor))}</b> · {formatDate(a.data_prevista)} ·{' '}
              {a.suppliers?.name ?? a.payees?.name ?? a.clients?.name ?? a.nome ?? a.categoria ?? a.service_orders?.service_order_number ?? a.descricao}
            </span>
            <Button size="sm" variant="ghost" className="h-7 w-7 shrink-0 p-0" aria-label="Cancelar anotação" disabled={cancelar.isPending} onClick={() => cancelar.mutate(a.id)}>
              <X className="h-3.5 w-3.5" />
            </Button>
          </li>
        ))}
      </ul>
    </Card>
  );
}
