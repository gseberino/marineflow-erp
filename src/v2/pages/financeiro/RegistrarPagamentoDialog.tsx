// Registrar o que se PAGOU a um freelancer, da própria aba Diárias (pedido do dono, 06/10/2026: o
// Pix lançado pelo "Lançar" geral "não aparecia" — agora aparece, e daqui o caminho é direto).
//
// As MESMAS funções do "Lançar" e do assistente (registrar_pagamento_freelancer):
//   Pix/transferência já feito → anotar_transacao: casa com a linha quando o banco trouxer; até lá
//     aparece no extrato de diárias como "Anotado — aguardando o banco", já descontando.
//   Dinheiro do Caixa → lancar_no_caixa (sai do Caixa).
//   Bolso de um sócio → lancar_no_caixa como reembolso ao sócio, com o freelancer como quem recebeu.
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { MoneyInput } from '@/components/MoneyInput';
import { useI18n } from '@/i18n';
import { hojeLocal } from '@/lib/dia';
import { usePayees } from '@/hooks/use-payees';
import { useAnotarTransacao, useLancarNoCaixa } from '@/hooks/use-caixa';
import type { FreelancerNoResumo } from '@/hooks/use-diarias';

export const CATEGORIA_DIARIAS = 'Diárias de freelancers';

type Forma = 'pix' | 'dinheiro' | 'socio';
const FORMAS: Array<[Forma, string, string]> = [
  ['pix', 'Pix ou transferência (já feito)', 'Aparece já no extrato como "aguardando o banco" e casa com a linha quando o banco trouxer.'],
  ['dinheiro', 'Dinheiro do Caixa', 'Sai do Caixa agora.'],
  ['socio', 'Do bolso de um sócio', 'Vira reembolso a pagar ao sócio; o freelancer fica como quem recebeu.'],
];

export function RegistrarPagamentoDialog({ pessoas, favorecidoInicial, onFechar }: {
  pessoas: FreelancerNoResumo[];
  favorecidoInicial?: string | null;
  onFechar: () => void;
}) {
  const { formatCurrency } = useI18n();
  const hoje = hojeLocal();
  const { data: favorecidos = [] } = usePayees();
  const socios = favorecidos.filter((f) => f.kind === 'socio');
  const anotar = useAnotarTransacao();
  const lancar = useLancarNoCaixa();
  const ocupado = anotar.isPending || lancar.isPending;

  const [favorecidoId, setFavorecidoId] = useState(favorecidoInicial ?? (pessoas.length === 1 ? pessoas[0].id : ''));
  const [valor, setValor] = useState(0);
  const [data, setData] = useState(hoje);
  const [forma, setForma] = useState<Forma>('pix');
  const [socio, setSocio] = useState(socios.length === 1 ? socios[0].id : '');
  const [observacao, setObservacao] = useState('');

  const pessoa = pessoas.find((p) => p.id === favorecidoId);
  const socioEscolhido = socio || (socios.length === 1 ? socios[0].id : '');
  const erro = !favorecidoId ? 'Escolha o freelancer.'
    : !(valor > 0) ? 'Informe o valor.'
    : !data ? 'Informe a data.'
    : data > hoje ? 'Pagamento no futuro não se lança: lance quando pagar.'
    : forma === 'socio' && !socioEscolhido ? 'Escolha o sócio que pagou.'
    : null;

  function salvar() {
    if (erro || !pessoa) return;
    const descricao = observacao.trim() || `Pagamento de diárias — ${pessoa.nome.split(' ')[0]}`;
    const fim = { onSuccess: () => onFechar() };
    if (forma === 'pix') {
      anotar.mutate({ sentido: 'saida', valor, data, favorecidoId, categoria: CATEGORIA_DIARIAS, descricao }, fim);
    } else {
      lancar.mutate({
        sentido: 'saida', valor, descricao, data, categoria: CATEGORIA_DIARIAS, favorecidoId,
        pagoPor: forma === 'dinheiro' ? 'caixa' : 'socio', socioId: forma === 'socio' ? socioEscolhido : null,
      }, fim);
    }
  }

  return (
    <Dialog open onOpenChange={(aberto) => !aberto && onFechar()}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Registrar pagamento</DialogTitle>
          <DialogDescription>O que já foi pago ao freelancer. Desconta do saldo com ele na hora.</DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="pag-freelancer">Freelancer</Label>
            <Select value={favorecidoId} onValueChange={setFavorecidoId}>
              <SelectTrigger id="pag-freelancer"><SelectValue placeholder="Escolha…" /></SelectTrigger>
              <SelectContent>
                {pessoas.map((p) => <SelectItem key={p.id} value={p.id}>{p.nome}</SelectItem>)}
              </SelectContent>
            </Select>
            {pessoa && (
              <p className="text-xs text-muted-foreground">
                Saldo acumulado com ele: <span className="tabular-nums">{formatCurrency(pessoa.saldo_final)}</span>
                {valor > 0 && <> → depois deste: <span className="tabular-nums">{formatCurrency(pessoa.saldo_final - valor)}</span></>}
              </p>
            )}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pag-valor">Valor (R$)</Label>
            <MoneyInput id="pag-valor" value={valor} onValueChange={setValor} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pag-data">Data do pagamento</Label>
            <Input id="pag-data" type="date" value={data} max={hoje} onChange={(e) => setData(e.target.value)} />
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <span className="text-sm font-medium" id="pag-forma">Como foi pago</span>
            <div className="grid gap-2" role="radiogroup" aria-labelledby="pag-forma">
              {FORMAS.map(([v, rotulo, nota]) => (
                <button key={v} type="button" role="radio" aria-checked={forma === v} onClick={() => setForma(v)}
                        className={`rounded-md border p-2 text-left text-sm ${forma === v ? 'border-primary bg-primary/5' : 'hover:bg-muted/50'}`}>
                  <span className="font-medium">{rotulo}</span>
                  <span className="block text-xs text-muted-foreground">{nota}</span>
                </button>
              ))}
            </div>
          </div>
          {forma === 'socio' && (
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="pag-socio">Sócio que pagou</Label>
              <Select value={socioEscolhido} onValueChange={setSocio}>
                <SelectTrigger id="pag-socio"><SelectValue placeholder="Escolha…" /></SelectTrigger>
                <SelectContent>
                  {socios.map((s) => <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          )}
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="pag-obs">Descrição (opcional)</Label>
            <Input id="pag-obs" value={observacao} onChange={(e) => setObservacao(e.target.value)}
                   placeholder="Ex.: adiantamento, acerto da quinzena" />
          </div>
        </div>

        <DialogFooter className="flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm text-destructive">{valor > 0 || favorecidoId ? erro ?? '' : ''}</p>
          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={onFechar}>Cancelar</Button>
            <Button type="button" onClick={salvar} disabled={!!erro || ocupado}>{ocupado ? 'Salvando…' : 'Registrar pagamento'}</Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
