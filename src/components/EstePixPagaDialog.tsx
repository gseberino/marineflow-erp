/**
 * "Este Pix paga…": uma entrada do banco aplicada em uma ou mais contas a receber (forma A, F2 —
 * 02/10/2026).
 *
 * Pedido do dono: um Pix que paga duas OS e uma OS paga em dois Pix. Escolhe-se o cliente, marcam-se
 * as contas em aberto (o valor vem preenchido pelo que falta em cada uma e pode mudar) ou o
 * pagamento já lançado à mão que este Pix é; o rodapé mostra quanto da entrada fica aplicado e o
 * que sobra. A regra é a da função do banco aplicar_entrada_em_contas, repetida em
 * src/lib/este-pix-paga.ts para a tela avisar antes do clique (até R$ 10 a mais vira receita da
 * conta; até R$ 10 a menos pode quitar com desconto; a entrada é aplicada por inteiro).
 *
 * F4 (03/10/2026): pode abrir já preenchido com o que a linha "parece pagar" (contas e pagamentos à
 * mão do cliente identificado cuja soma bate). Só preenche: quem aplica é a pessoa, no "Aplicar".
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { EntityCombobox } from '@/components/EntityCombobox';
import { MoneyInput } from '@/components/MoneyInput';
import { useI18n } from '@/i18n';
import { cn } from '@/lib/utils';
import { useClientesParaReceita } from '@/hooks/use-payees';
import {
  useAplicarEntradaEmContas, useContasEmAbertoDoCliente, useEntradaAplicada, usePagamentosSemPixDoCliente,
} from '@/hooks/use-lancamentos';
import {
  analisarItem, distribuirPeloVencimento, montarAplicacoes, resumir, type ItemDaAplicacao,
} from '@/lib/este-pix-paga';
import { ListChecks } from 'lucide-react';
import type { ParecePagar } from '../../supabase/functions/_shared/banking/parece-pagar';

type Escolha = { valor: number; quitar: boolean };

export function EstePixPagaDialog({
  aberto, onFechar, entradaId, clienteInicial, onConcluido, sugestao,
}: {
  aberto: boolean;
  onFechar: () => void;
  entradaId: string | null;
  clienteInicial?: string | null;
  onConcluido?: () => void;
  /** O que a linha parece pagar: abre com essas contas e pagamentos já marcados. */
  sugestao?: ParecePagar | null;
}) {
  const { formatCurrency, formatDate } = useI18n();
  const { data: entrada, isLoading: lendoEntrada } = useEntradaAplicada(aberto ? entradaId : null);
  const { data: clientes = [] } = useClientesParaReceita(aberto);
  const [clienteId, setClienteId] = useState<string | null>(clienteInicial ?? null);
  const { data: contas = [], isLoading: lendoContas } = useContasEmAbertoDoCliente(aberto ? clienteId : null);
  const { data: pagamentos = [] } = usePagamentosSemPixDoCliente(aberto ? clienteId : null);
  const aplicar = useAplicarEntradaEmContas();

  const [escolhas, setEscolhas] = useState<Record<string, Escolha>>({});
  const [ligados, setLigados] = useState<Set<string>>(new Set());
  const [confirmando, setConfirmando] = useState(false);

  // Cada abertura começa do zero, com o cliente que a linha já sugeria — e, se ela parece pagar
  // contas que já existem, com elas marcadas. A sugestão é lida só na abertura: uma releitura da
  // fila no meio não apaga o que a pessoa já mudou.
  const sugestaoNaAbertura = useRef(sugestao);
  sugestaoNaAbertura.current = sugestao;
  const [preenchido, setPreenchido] = useState(false);
  useEffect(() => {
    if (!aberto) return;
    const sug = sugestaoNaAbertura.current;
    setClienteId(clienteInicial ?? null);
    setEscolhas(sug
      ? Object.fromEntries(sug.itens.filter((i) => i.tipo === 'conta').map((i) => [i.id, { valor: i.valor, quitar: i.quitar }]))
      : {});
    setLigados(new Set(sug ? sug.itens.filter((i) => i.tipo === 'pagamento').map((i) => i.id) : []));
    setPreenchido(!!sug);
    setConfirmando(false);
  }, [aberto, entradaId, clienteInicial]);

  const restante = entrada ? Math.round((entrada.valor - entrada.aplicado) * 100) / 100 : 0;

  const itens: ItemDaAplicacao[] = useMemo(
    () => contas.filter((cta) => escolhas[cta.id]).map((cta) => ({
      contaId: cta.id, saldo: cta.saldo, valor: escolhas[cta.id].valor, quitar: escolhas[cta.id].quitar,
    })),
    [contas, escolhas],
  );
  const valoresLigados = pagamentos.filter((p) => ligados.has(p.id)).map((p) => p.valor);
  const resumo = resumir(restante, itens, valoresLigados, formatCurrency);

  const mudarCliente = (id: string) => {
    setPreenchido(false);
    setClienteId(id || null);
    setEscolhas({});
    setLigados(new Set());
    setConfirmando(false);
  };

  const marcar = (contaId: string, saldo: number, marcado: boolean) => {
    setConfirmando(false);
    setEscolhas((atual) => {
      const novo = { ...atual };
      if (!marcado) { delete novo[contaId]; return novo; }
      // O que ainda falta aplicar da entrada, sem passar do que falta nesta conta.
      const jaEscolhido = Object.values(novo).reduce((s, e) => s + e.valor, 0) + valoresLigados.reduce((s, v) => s + v, 0);
      const livre = Math.max(0, Math.round((restante - jaEscolhido) * 100) / 100);
      novo[contaId] = { valor: Math.min(saldo, livre) || saldo, quitar: true };
      return novo;
    });
  };

  const preencherPelaMaisAntiga = () => {
    setConfirmando(false);
    const livre = Math.round((restante - valoresLigados.reduce((s, v) => s + v, 0)) * 100) / 100;
    const d = distribuirPeloVencimento(livre, contas);
    setEscolhas(Object.fromEntries(Object.entries(d).map(([id, valor]) => [id, { valor, quitar: true }])));
  };

  const confirmar = () => {
    if (!entradaId) return;
    aplicar.mutate(
      { bankTransactionId: entradaId, aplicacoes: montarAplicacoes(itens, [...ligados]) },
      { onSuccess: () => { onConcluido?.(); onFechar(); } },
    );
  };

  const opcoesDeCliente = useMemo(() => clientes.map((cl) => ({ value: cl.id, label: cl.name })), [clientes]);

  return (
    <Dialog open={aberto} onOpenChange={(v) => { if (!v) onFechar(); }}>
      <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto" data-testid="este-pix-paga">
        <DialogHeader>
          <DialogTitle>Este Pix paga…</DialogTitle>
          <DialogDescription>
            {lendoEntrada || !entrada
              ? 'Lendo a entrada do banco…'
              : <>
                  {formatDate(entrada.data)} · {entrada.quem} · {formatCurrency(entrada.valor)}
                  {entrada.aplicado > 0 && <> · já aplicado {formatCurrency(entrada.aplicado)}, faltam {formatCurrency(restante)}</>}
                </>}
          </DialogDescription>
        </DialogHeader>

        {entrada && restante <= 0 ? (
          <p className="text-sm">Esta entrada já está toda aplicada.</p>
        ) : (
          <div className="space-y-3">
            {preenchido && (
              <p className="rounded-md border border-primary/30 bg-primary/5 p-2 text-xs" data-testid="preenchido-pela-sugestao">
                Já marquei o que esta entrada parece pagar. Confira os valores antes de aplicar.
              </p>
            )}
            <div className="space-y-1">
              <Label>De qual cliente são as contas?</Label>
              <EntityCombobox
                value={clienteId}
                onChange={mudarCliente}
                placeholder="Escolher cliente"
                options={opcoesDeCliente}
                fullWidth
              />
              <p className="text-xs text-muted-foreground">
                Quem fez o Pix pode ter outro nome (um parente, a empresa dele): escolha o cliente das contas.
              </p>
            </div>

            {clienteId && (
              <div className="space-y-2">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="text-sm font-medium">Contas em aberto</p>
                  {contas.length > 1 && (
                    <Button type="button" size="sm" variant="ghost" className="h-7 px-2 text-xs" onClick={preencherPelaMaisAntiga}>
                      Preencher pela mais antiga
                    </Button>
                  )}
                </div>
                {lendoContas ? (
                  <p className="text-xs text-muted-foreground">Lendo as contas…</p>
                ) : contas.length === 0 ? (
                  <p className="text-xs text-muted-foreground">Este cliente não tem conta em aberto.</p>
                ) : (
                  <ul className="space-y-2">
                    {contas.map((cta) => {
                      const e = escolhas[cta.id];
                      const a = e ? analisarItem({ contaId: cta.id, saldo: cta.saldo, valor: e.valor, quitar: e.quitar }, formatCurrency) : null;
                      return (
                        <li key={cta.id} className={cn('rounded-md border p-2', e && 'border-primary/40 bg-primary/5')}>
                          <div className="flex items-start gap-2">
                            <Checkbox
                              id={`conta-${cta.id}`}
                              checked={!!e}
                              onCheckedChange={(v) => marcar(cta.id, cta.saldo, v === true)}
                              className="mt-0.5 shrink-0"
                              aria-label={`Este Pix paga ${cta.descricao}`}
                            />
                            <label htmlFor={`conta-${cta.id}`} className="min-w-0 flex-1 cursor-pointer text-sm">
                              <span className="block truncate font-medium" title={cta.descricao}>{cta.descricao}</span>
                              <span className="block text-xs text-muted-foreground">
                                {[cta.documento, `vence ${formatDate(cta.vencimento)}`, `falta ${formatCurrency(cta.saldo)}`].filter(Boolean).join(' · ')}
                              </span>
                            </label>
                            {e && (
                              <MoneyInput
                                className="h-8 w-28 shrink-0 text-right"
                                value={e.valor}
                                onValueChange={(v) => { setConfirmando(false); setEscolhas((at) => ({ ...at, [cta.id]: { ...at[cta.id], valor: v } })); }}
                                aria-label={`Quanto vai para ${cta.descricao}`}
                              />
                            )}
                          </div>
                          {a && (a.erro || a.aviso) && (
                            <p className={cn('mt-1 pl-6 text-xs', a.erro ? 'text-destructive' : 'text-muted-foreground')}>{a.erro ?? a.aviso}</p>
                          )}
                          {e && a?.podeQuitar && !a.erro && (
                            <label className="mt-1 flex items-center gap-2 pl-6 text-xs">
                              <Checkbox
                                checked={e.quitar}
                                onCheckedChange={(v) => { setConfirmando(false); setEscolhas((at) => ({ ...at, [cta.id]: { ...at[cta.id], quitar: v === true } })); }}
                                aria-label={`Quitar ${cta.descricao} com desconto`}
                              />
                              Quitar: os {formatCurrency(a.falta)} que faltam viram desconto
                            </label>
                          )}
                        </li>
                      );
                    })}
                  </ul>
                )}

                {pagamentos.length > 0 && (
                  <div className="space-y-1 pt-1">
                    <p className="text-sm font-medium">Ou é um pagamento que você já lançou à mão</p>
                    <p className="text-xs text-muted-foreground">
                      Como o sinal registrado no "Receber sinal": marque e este Pix passa a ser a origem dele, sem criar outro.
                    </p>
                    <ul className="space-y-1">
                      {pagamentos.map((p) => (
                        <li key={p.id} className="flex items-start gap-2 rounded-md border p-2 text-sm">
                          <Checkbox
                            id={`pag-${p.id}`}
                            checked={ligados.has(p.id)}
                            onCheckedChange={(v) => {
                              setConfirmando(false);
                              setLigados((at) => { const n = new Set(at); if (v === true) n.add(p.id); else n.delete(p.id); return n; });
                            }}
                            className="mt-0.5 shrink-0"
                            aria-label={`Este Pix é o pagamento de ${p.descricao}`}
                          />
                          <label htmlFor={`pag-${p.id}`} className="min-w-0 flex-1 cursor-pointer">
                            <span className="block truncate" title={p.descricao}>{p.descricao}</span>
                            <span className="block text-xs text-muted-foreground">
                              {[p.documento, `${formatCurrency(p.valor)} em ${formatDate(p.data)}`].filter(Boolean).join(' · ')}
                            </span>
                          </label>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
              </div>
            )}

            {entrada && clienteId && (
              <div
                className={cn('rounded-md border p-2 text-sm', resumo.podeAplicar ? 'bg-muted/30' : 'border-amber-500/40 bg-amber-500/5')}
                data-testid="resumo-da-aplicacao"
              >
                <p className="font-medium">
                  {formatCurrency(restante)} a aplicar · escolhido {formatCurrency(resumo.aplicado)} · sobra {formatCurrency(resumo.sobra)}
                </p>
                <p className="text-xs">{resumo.mensagem}</p>
              </div>
            )}

            {confirmando && (
              <div className="rounded-md border bg-background p-2 text-xs">
                Vai registrar {itens.length} pagamento(s) com a data desta entrada
                {ligados.size > 0 && <> e ligar {ligados.size} pagamento(s) já lançado(s) a ela</>}. Fica na trilha, e cada aplicação
                pode ser desfeita depois na correção do lançamento.
              </div>
            )}
          </div>
        )}

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={confirmando ? () => setConfirmando(false) : onFechar} disabled={aplicar.isPending}>
            {confirmando ? 'Voltar' : 'Cancelar'}
          </Button>
          {confirmando ? (
            <Button onClick={confirmar} disabled={aplicar.isPending}>
              {aplicar.isPending ? 'Gravando…' : 'Confirmar'}
            </Button>
          ) : (
            <Button onClick={() => setConfirmando(true)} disabled={!resumo.podeAplicar || !entrada || restante <= 0}>
              Aplicar
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** O botão que abre o "Este Pix paga…" a partir de uma entrada do banco. */
export function BotaoEstePixPaga({
  entradaId, clienteInicial, disabled, rotulo, variante = 'link', onConcluido, sugestao,
}: {
  entradaId: string;
  clienteInicial?: string | null;
  disabled?: boolean;
  rotulo?: string;
  variante?: 'link' | 'outline' | 'default';
  onConcluido?: () => void;
  sugestao?: ParecePagar | null;
}) {
  const [aberto, setAberto] = useState(false);
  return (
    <>
      <Button
        type="button"
        size="sm"
        variant={variante}
        className={cn(variante === 'link' && 'h-auto gap-1 px-0 text-xs')}
        disabled={disabled}
        onClick={() => setAberto(true)}
      >
        <ListChecks className="h-3.5 w-3.5 shrink-0" />
        {rotulo ?? 'Este Pix paga contas que já existem (uma ou várias)…'}
      </Button>
      <EstePixPagaDialog
        aberto={aberto}
        onFechar={() => setAberto(false)}
        entradaId={entradaId}
        clienteInicial={clienteInicial}
        onConcluido={onConcluido}
        sugestao={sugestao}
      />
    </>
  );
}
