// Registrar o que se PAGOU a um freelancer, da própria aba Diárias (pedido do dono, 06/10/2026: o
// Pix lançado pelo "Lançar" geral "não aparecia" — agora aparece, e daqui o caminho é direto).
//
// Uma função do banco só, a mesma do assistente (registrar_pagamento_do_freelancer, 11/10/2026):
//   Pix/transferência já feito → anota (anotar_transacao): casa com a linha quando o banco trouxer;
//     até lá aparece no extrato de diárias como "Anotado — aguardando o banco", já descontando.
//   Dinheiro do Caixa → sai do Caixa (lancar_no_caixa).
//   Bolso de um sócio → reembolso a pagar ao sócio (lancar_no_caixa), com o freelancer como quem recebeu.
//
// Divisão (resposta 4 do dono, 11/10/2026): com reembolso de despesa paga por ele em aberto, o banco
// PROPÕE quanto deste pagamento é reembolso (vai para a categoria de cada comprovante) e quanto é
// diária; o dono confirma ou desmarca. Sem reembolso em aberto, o diálogo é o de antes. O Pix que veio
// do banco sem registro se divide depois, pela ação "Dividir: diárias e reembolso" do Extrato
// (DividirPagamentoDialog, abaixo) — o mesmo bloco.
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { MoneyInput } from '@/components/MoneyInput';
import { useI18n } from '@/i18n';
import { hojeLocal } from '@/lib/dia';
import { ROTULO_REEMBOLSOS, descricaoDoReembolso, numeroDoRecibo } from '@/lib/extrato-diarias';
import { usePayees } from '@/hooks/use-payees';
import {
  CATEGORIA_DO_REEMBOLSO_SEM_CATEGORIA, divisaoEscolhida, useDividirPagamentoDoFreelancer, usePropostaDeDivisao,
  useRegistrarPagamentoDoFreelancer,
  type FormaDoPagamento, type FreelancerNoResumo, type PropostaDeDivisao, type ReembolsoEmAberto,
} from '@/hooks/use-diarias';

const FORMAS: Array<[FormaDoPagamento, string, string]> = [
  ['pix', 'Pix ou transferência (já feito)', 'Aparece já no extrato como "aguardando o banco" e casa com a linha quando o banco trouxer.'],
  ['dinheiro', 'Dinheiro do Caixa', 'Sai do Caixa agora.'],
  ['socio', 'Do bolso de um sócio', 'Vira reembolso a pagar ao sócio; o freelancer fica como quem recebeu.'],
];

const ddmm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;

/** O valor depois que a digitação para: a proposta não é pedida ao banco a cada tecla. */
function useValorAssentado(valor: number, ms = 400) {
  const [assentado, setAssentado] = useState(valor);
  useEffect(() => {
    const t = setTimeout(() => setAssentado(valor), ms);
    return () => clearTimeout(t);
  }, [valor, ms]);
  return assentado;
}

/**
 * Os reembolsos marcados: os que o banco propôs, até o dono mexer. Mudou a proposta (outro valor, outra
 * pessoa), volta a ser a do banco — sem efeito, a escolha é guardada junto da proposta a que se refere.
 */
function useEscolhaDaProposta(proposta: PropostaDeDivisao | undefined) {
  const chave = proposta ? `${proposta.favorecido?.id ?? ''}|${proposta.valor}|${proposta.propostos.join(',')}` : '';
  const [escolha, setEscolha] = useState<{ chave: string; ids: string[] }>({ chave: '', ids: [] });
  const ids = escolha.chave === chave ? escolha.ids : (proposta?.propostos ?? []);
  const alternar = (id: string) =>
    setEscolha({ chave, ids: ids.includes(id) ? ids.filter((x) => x !== id) : [...ids, id] });
  return { ids, alternar };
}

/** O bloco "Divisão deste pagamento": uma caixa por comprovante e o total de cada lado. */
function BlocoDaDivisao({ nome, emAberto, ids, onAlternar, valor }: {
  nome: string;
  emAberto: ReembolsoEmAberto[];
  ids: string[];
  onAlternar: (id: string) => void;
  valor: number;
}) {
  const { formatCurrency } = useI18n();
  const divisao = divisaoEscolhida(emAberto, ids, valor);
  return (
    <div className="min-w-0 space-y-2 rounded-md border p-3" role="group" aria-labelledby="pag-divisao">
      <p id="pag-divisao" className="text-sm font-medium">Divisão deste pagamento</p>
      <p className="text-xs text-muted-foreground">
        {nome.split(' ')[0]} tem despesa da empresa paga por ele, com comprovante, ainda não reembolsada. Marque o que este
        pagamento reembolsa: essa parte entra na categoria de cada despesa; o resto fica em Diárias. O saldo com ele não muda.
      </p>
      <ul className="divide-y rounded-md border">
        {emAberto.map((r) => (
          <li key={r.id}>
            <label className="flex min-w-0 cursor-pointer items-start gap-2 p-2 text-sm">
              <input type="checkbox" className="mt-1 shrink-0" checked={ids.includes(r.id)} onChange={() => onAlternar(r.id)} />
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">
                  {[r.codigo, ddmm(r.data), r.acerto != null ? `acerto nº ${numeroDoRecibo(r.acerto)}` : null].filter(Boolean).join(' · ')}
                </span>
                <span className="block truncate text-xs text-muted-foreground">
                  {[descricaoDoReembolso(r), r.categoria ?? `sem categoria (vai para ${CATEGORIA_DO_REEMBOLSO_SEM_CATEGORIA})`].filter(Boolean).join(' · ')}
                </span>
              </span>
              <span className="shrink-0 tabular-nums">{formatCurrency(r.valor)}</span>
            </label>
          </li>
        ))}
      </ul>
      <p className="flex flex-wrap gap-x-3 gap-y-1 text-sm" aria-live="polite">
        <span>Diárias <span className="font-semibold tabular-nums">{formatCurrency(Math.max(divisao.diarias, 0))}</span></span>
        <span>{ROTULO_REEMBOLSOS} <span className="font-semibold tabular-nums">{formatCurrency(divisao.reembolsos)}</span></span>
      </p>
    </div>
  );
}

export function RegistrarPagamentoDialog({ pessoas, favorecidoInicial, onFechar }: {
  pessoas: FreelancerNoResumo[];
  favorecidoInicial?: string | null;
  onFechar: () => void;
}) {
  const { formatCurrency } = useI18n();
  const hoje = hojeLocal();
  const { data: favorecidos = [] } = usePayees();
  const socios = favorecidos.filter((f) => f.kind === 'socio');
  const registrar = useRegistrarPagamentoDoFreelancer();

  const [favorecidoId, setFavorecidoId] = useState(favorecidoInicial ?? (pessoas.length === 1 ? pessoas[0].id : ''));
  const [valor, setValor] = useState(0);
  const [data, setData] = useState(hoje);
  const [forma, setForma] = useState<FormaDoPagamento>('pix');
  const [socio, setSocio] = useState(socios.length === 1 ? socios[0].id : '');
  const [observacao, setObservacao] = useState('');

  const valorAssentado = useValorAssentado(valor);
  const proposta = usePropostaDeDivisao(favorecidoId, valorAssentado);
  // A proposta é a do valor que está na tela? (com o valor mudando, a de antes não vale; a chave da
  // consulta é o valor assentado, então o dado que veio é sempre o dele)
  const propostaAtual = valorAssentado === valor ? proposta.data : undefined;
  const emAberto = propostaAtual?.em_aberto ?? [];
  const { ids, alternar } = useEscolhaDaProposta(propostaAtual);
  const divisao = divisaoEscolhida(emAberto, ids, valor);
  // Enquanto confere, não registra: um clique rápido gravaria tudo em Diárias sem o dono ver a divisão.
  const conferindo = !!favorecidoId && valor > 0 && !proposta.error && (valorAssentado !== valor || proposta.isFetching || !proposta.data);

  const pessoa = pessoas.find((p) => p.id === favorecidoId);
  const socioEscolhido = socio || (socios.length === 1 ? socios[0].id : '');
  const erro = !favorecidoId ? 'Escolha o freelancer.'
    : !(valor > 0) ? 'Informe o valor.'
    : !data ? 'Informe a data.'
    : data > hoje ? 'Pagamento no futuro não se lança: lance quando pagar.'
    : forma === 'socio' && !socioEscolhido ? 'Escolha o sócio que pagou.'
    : divisao.passou ? 'Os reembolsos marcados passam do valor pago: desmarque algum.'
    : null;

  function salvar() {
    if (erro || conferindo || !pessoa) return;
    const descricao = observacao.trim() || `Pagamento de diárias — ${pessoa.nome.split(' ')[0]}`;
    registrar.mutate({
      favorecidoId, valor, data, forma, socioId: forma === 'socio' ? socioEscolhido : null,
      reembolsos: divisao.marcados.map((r) => r.id), descricao,
    }, { onSuccess: () => onFechar() });
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
          {emAberto.length > 0 && pessoa && (
            <div className="min-w-0 sm:col-span-2">
              <BlocoDaDivisao nome={pessoa.nome} emAberto={emAberto} ids={ids} onAlternar={alternar} valor={valor} />
            </div>
          )}
          {proposta.error && valor > 0 && (
            <p className="text-xs text-warning sm:col-span-2">
              Não deu para conferir os reembolsos em aberto ({(proposta.error as Error).message}): este pagamento vai todo para
              Diárias. Se ele quitar reembolso de despesa, divida depois pelo Extrato.
            </p>
          )}
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
            <Button type="button" onClick={salvar} disabled={!!erro || conferindo || registrar.isPending}>
              {registrar.isPending ? 'Salvando…' : conferindo && !erro ? 'Conferindo…' : 'Registrar pagamento'}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** O pagamento das Diárias que veio do banco, como o Extrato o mostra. */
export interface PagamentoParaDividir {
  /** O lançamento (payables.id) da linha do banco. */
  id: string;
  valor: number;
  data: string;
}

/**
 * "Dividir: diárias e reembolso" — o Pix que chegou do banco sem registro (regra por CPF, aprovado no
 * Extrato) e já está todo em Diárias. A mesma proposta do registrar; o banco divide o lançamento em
 * partes na mesma linha (uma por categoria) e o saldo com ele não muda.
 */
export function DividirPagamentoDialog({ favorecidoId, nome, pagamento, onFechar }: {
  favorecidoId: string;
  nome: string;
  pagamento: PagamentoParaDividir;
  onFechar: () => void;
}) {
  const { formatCurrency } = useI18n();
  const proposta = usePropostaDeDivisao(favorecidoId, pagamento.valor);
  const dividir = useDividirPagamentoDoFreelancer();
  const emAberto = proposta.data?.em_aberto ?? [];
  const { ids, alternar } = useEscolhaDaProposta(proposta.data);
  const divisao = divisaoEscolhida(emAberto, ids, pagamento.valor);
  const erro = divisao.passou ? 'Os reembolsos marcados passam do valor pago: desmarque algum.'
    : divisao.marcados.length === 0 ? 'Marque ao menos um reembolso.'
    : null;

  function confirmar() {
    if (erro) return;
    dividir.mutate({ payableId: pagamento.id, reembolsos: divisao.marcados.map((r) => r.id) }, { onSuccess: () => onFechar() });
  }

  return (
    <Dialog open onOpenChange={(aberto) => !aberto && onFechar()}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Dividir: diárias e reembolso</DialogTitle>
          <DialogDescription>
            Pagamento de {formatCurrency(pagamento.valor)} em {ddmm(pagamento.data)} a {nome}, que veio do banco todo em Diárias. A parte de
            reembolso passa para a categoria de cada despesa; o saldo com ele não muda.
          </DialogDescription>
        </DialogHeader>
        {proposta.isLoading ? (
          <p className="text-sm text-muted-foreground">Conferindo os reembolsos em aberto…</p>
        ) : proposta.error ? (
          <p role="alert" className="text-sm text-destructive">Não deu para conferir os reembolsos: {(proposta.error as Error).message}</p>
        ) : emAberto.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhum reembolso de despesa paga por ele em aberto: não há o que dividir.</p>
        ) : (
          <BlocoDaDivisao nome={nome} emAberto={emAberto} ids={ids} onAlternar={alternar} valor={pagamento.valor} />
        )}
        <DialogFooter className="flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm text-destructive">{emAberto.length > 0 ? erro ?? '' : ''}</p>
          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={onFechar}>Cancelar</Button>
            <Button type="button" onClick={confirmar} disabled={!!erro || emAberto.length === 0 || dividir.isPending}>
              {dividir.isPending ? 'Dividindo…' : 'Dividir'}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
