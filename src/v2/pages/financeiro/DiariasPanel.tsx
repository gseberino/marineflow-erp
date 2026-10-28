// Financeiro › Diárias: quanto cada freelancer trabalhou, quanto recebeu e o saldo com ele.
//
// O saldo vem pronto do banco (saldo inicial + trabalhado − pago). O "pago" é o que já veio do
// extrato no nome dele (Pix, Caixa), o que um sócio pagou do próprio bolso para ele e — desde
// 06/10/2026 — o Pix lançado à mão que o banco ainda não confirmou ("Anotado") e, desde 27/10, o Pix
// que o banco já trouxe e espera a aprovação na fila ("Falta aprovar"). Só da categoria "Diárias
// de freelancers" ou ainda sem categoria (fase 1b, 27/10: almoço e peças não abatem). Aqui se lança o
// DIA e, por "Registrar pagamento", o que foi pago (as mesmas funções do "Lançar" e do assistente).
//
// Reembolso (F2b dos comprovantes, 11/10/2026): a despesa da empresa que ele pagou do bolso, com o
// comprovante (CMP), soma a favor dele e entra no próximo acerto. Não se lança nem se apaga aqui:
// nasce do SIM do comprovante pelo WhatsApp e só sai cancelando o CMP. Rótulo de todo lugar:
// "Reembolso de despesas pagas pelo técnico" (resposta 9 do dono).
//
// Pagamento dividido (resposta 4 do dono, 11/10/2026): o Pix das Diárias que veio do banco ganha
// "Dividir: diárias e reembolso" quando há reembolso em aberto (a parte do reembolso vai para a
// categoria de cada despesa; o saldo não muda) e, depois de dividido, "Desfazer a divisão".
import { useState } from 'react';
import { Banknote, CalendarPlus, FileDown, FileText, Lock, Pencil, Split, Trash2, Undo2, UserPlus } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Skeleton } from '@/components/ui/skeleton';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { useConfirmacao } from '@/components/Confirmacao';
import { useI18n } from '@/i18n';
import { hojeLocal } from '@/lib/dia';
import {
  ESTADO_DO_SALDO, PERIODOS, diaCurto, intervaloDoMes, pedidoDoPeriodo, rotuloDaJornada,
  type PedidoDePeriodo, type PeriodoDasDiarias,
} from '@/lib/diarias';
import {
  acertoQueTrava, comoTirarOReembolso, diaParaEditar, pagamentoDividido, pagamentoNaFila, pagamentoQueSeDivide, useAcertos, useContaCorrente,
  useDividirPagamentoDoFreelancer, useExcluirDiaComDesfazer, usePropostaDeDivisao, useResumoFreelancers,
  type Acerto, type DiaParaEditar, type FreelancerNoResumo,
} from '@/hooks/use-diarias';
import { useDocumentosDasDiarias } from '@/hooks/use-documentos-diarias';
import { ROTULO_REEMBOLSO, ROTULO_REEMBOLSOS, descricaoDoReembolso, numeroDoRecibo } from '@/lib/extrato-diarias';
import { AcertosDoFreelancer } from './AcertosDoFreelancer';
import { RegistrarDiaDialog } from './RegistrarDiaDialog';
import { NovoFreelancerDialog } from './NovoFreelancerDialog';
import { DividirPagamentoDialog, RegistrarPagamentoDialog, type PagamentoParaDividir } from './RegistrarPagamentoDialog';
import { GradeDiarias } from './GradeDiarias';

export interface FiltroDasDiarias {
  periodo: PeriodoDasDiarias;
  /** De/Até de "Escolher datas…" ('AAAA-MM-DD' ou vazio). */
  de: string;
  ate: string;
  favorecidoId: string | null;
  /** Mês da grade, 'AAAA-MM'. */
  mes: string;
}

interface Props {
  aba: 'resumo' | 'extrato' | 'grade';
  filtro: FiltroDasDiarias;
  onFiltro: (f: FiltroDasDiarias) => void;
  onVerExtrato: (favorecidoId: string) => void;
}

interface Registrando {
  favorecidoId?: string | null;
  dataInicial?: string | null;
  editar?: DiaParaEditar;
}

export function DiariasPanel({ aba, filtro, onFiltro, onVerExtrato }: Props) {
  const periodo = pedidoDoPeriodo(filtro.periodo, { de: filtro.de, ate: filtro.ate });
  const resumo = useResumoFreelancers(periodo.de, periodo.ate, periodo.atalho);
  const pessoas = resumo.data?.pessoas ?? [];
  const [registrando, setRegistrando] = useState<Registrando | null>(null);
  const [cadastrando, setCadastrando] = useState(false);
  /** undefined = fechado; null = aberto sem pessoa escolhida. */
  const [pagando, setPagando] = useState<string | null | undefined>(undefined);
  const documentos = useDocumentosDasDiarias();
  // O que os documentos cobrem: na grade, o mês que está na tela; nas outras abas, o período.
  const intervalo: PedidoDePeriodo = aba === 'grade' ? { ...intervaloDoMes(filtro.mes), atalho: null } : periodo;
  const datasInvertidas = filtro.periodo === 'personalizado' && !!filtro.de && !!filtro.ate && filtro.de > filtro.ate;

  const barra = (
    <div className="flex flex-wrap items-center gap-2">
      {/* A grade anda de mês em mês pelas setas dela; o período vale para Resumo e Extrato. */}
      {aba !== 'grade' && (
        <Select value={filtro.periodo} onValueChange={(v) => onFiltro({ ...filtro, periodo: v as PeriodoDasDiarias })}>
          <SelectTrigger className="h-9 w-56 max-w-full" aria-label="Período"><SelectValue /></SelectTrigger>
          <SelectContent>
            {PERIODOS.map((p) => <SelectItem key={p.valor} value={p.valor}>{p.rotulo}</SelectItem>)}
          </SelectContent>
        </Select>
      )}
      {aba !== 'grade' && filtro.periodo === 'personalizado' && (
        <div className="flex flex-wrap items-center gap-2">
          <Input type="date" className="h-9 w-40" aria-label="Data inicial" value={filtro.de} max={hojeLocal()}
                 onChange={(e) => onFiltro({ ...filtro, de: e.target.value })} />
          <span className="text-sm text-muted-foreground">até</span>
          <Input type="date" className="h-9 w-40" aria-label="Data final" value={filtro.ate}
                 onChange={(e) => onFiltro({ ...filtro, ate: e.target.value })} />
          {datasInvertidas && <span className="text-sm text-destructive">A data inicial é depois da final.</span>}
        </div>
      )}
      {aba === 'extrato' && (
        <Select value={filtro.favorecidoId ?? ''} onValueChange={(v) => onFiltro({ ...filtro, favorecidoId: v })}>
          <SelectTrigger className="h-9 w-56 max-w-full" aria-label="Freelancer"><SelectValue placeholder="Escolha o freelancer" /></SelectTrigger>
          <SelectContent>
            {pessoas.map((p) => <SelectItem key={p.id} value={p.id}>{p.nome}</SelectItem>)}
          </SelectContent>
        </Select>
      )}
      <div className="ml-auto flex flex-wrap gap-2">
        {aba === 'extrato' && filtro.favorecidoId && (
          <Button size="sm" variant="outline" className="gap-1.5" disabled={!!documentos.gerando}
                  onClick={() => { void documentos.extratoEmPdf(filtro.favorecidoId!, intervalo); }}>
            <FileText className="h-4 w-4" /> {documentos.gerando === 'pdf' ? 'Gerando…' : 'Extrato em PDF'}
          </Button>
        )}
        <Button size="sm" variant="outline" className="gap-1.5" disabled={!!documentos.gerando || pessoas.length === 0}
                title="Todos os dias, reembolsos e pagamentos do período, de todos os freelancers, para o contador"
                onClick={() => { void documentos.csvDoPeriodo(pessoas.map((p) => p.id), intervalo); }}>
          <FileDown className="h-4 w-4" /> {documentos.gerando === 'csv' ? 'Gerando…' : 'Planilha do contador (CSV)'}
        </Button>
        <Button size="sm" variant="outline" className="gap-1.5" onClick={() => setCadastrando(true)}>
          <UserPlus className="h-4 w-4" /> Novo freelancer
        </Button>
        <Button size="sm" variant="outline" className="gap-1.5" disabled={pessoas.length === 0}
                onClick={() => setPagando(aba === 'extrato' ? filtro.favorecidoId : null)}>
          <Banknote className="h-4 w-4" /> Registrar pagamento
        </Button>
        <Button size="sm" className="gap-1.5"
                onClick={() => setRegistrando({ favorecidoId: aba === 'extrato' ? filtro.favorecidoId : null })}>
          <CalendarPlus className="h-4 w-4" /> Registrar dia
        </Button>
      </div>
    </div>
  );

  return (
    <div className="space-y-4">
      {barra}
      {datasInvertidas ? (
        <Card className="p-6 text-center text-sm text-muted-foreground">Acerte as datas para ver o período.</Card>
      ) : resumo.isLoading ? (
        <Skeleton className="h-48 w-full" />
      ) : resumo.error ? (
        <Card className="border-destructive/40 p-4 text-sm text-destructive">
          Não deu para carregar as diárias: {(resumo.error as Error).message}
        </Card>
      ) : pessoas.length === 0 ? (
        <Card className="space-y-3 p-6 text-center text-sm text-muted-foreground">
          <p>Nenhum freelancer com diária cadastrada.</p>
          <Button size="sm" className="gap-1.5" onClick={() => setCadastrando(true)}>
            <UserPlus className="h-4 w-4" /> Cadastrar o primeiro
          </Button>
        </Card>
      ) : aba === 'resumo' ? (
        <Resumo pessoas={pessoas} total={resumo.data!} onVerExtrato={onVerExtrato}
                onRegistrar={(id) => setRegistrando({ favorecidoId: id })}
                gerandoPdf={documentos.gerando === 'pdf'}
                porPessoa={!!periodo.atalho}
                onPagar={(id) => setPagando(id)}
                onPdf={(id) => { void documentos.extratoEmPdf(id, periodo); }} />
      ) : aba === 'grade' ? (
        <GradeDiarias
          pessoas={pessoas}
          mes={filtro.mes}
          onMes={(mes) => onFiltro({ ...filtro, mes })}
          onEditar={(d) => setRegistrando({ editar: d })}
          onNovo={(favorecidoId, data) => setRegistrando({ favorecidoId, dataInicial: data })}
        />
      ) : (
        <Extrato favorecidoId={filtro.favorecidoId} periodo={periodo}
                 onEditar={(d) => setRegistrando({ editar: d })}
                 gerandoPdf={documentos.gerando === 'pdf'}
                 onRecibo={(id, a) => { void documentos.reciboEmPdf(id, a); }} />
      )}

      {registrando && (
        <RegistrarDiaDialog
          pessoas={pessoas}
          favorecidoInicial={registrando.favorecidoId}
          dataInicial={registrando.dataInicial}
          editar={registrando.editar}
          onFechar={() => setRegistrando(null)}
        />
      )}
      {cadastrando && <NovoFreelancerDialog onFechar={() => setCadastrando(false)} />}
      {pagando !== undefined && (
        <RegistrarPagamentoDialog pessoas={pessoas} favorecidoInicial={pagando} onFechar={() => setPagando(undefined)} />
      )}
    </div>
  );
}

/** "desde 28/09", "28/09 a 06/10" — o período de UMA pessoa quando o atalho é por pessoa. */
function textoDoPeriodoDaPessoa(de: string | null, ate: string | null): string | null {
  const curto = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
  if (de && ate) return `${curto(de)} a ${curto(ate)}`;
  if (de) return `desde ${curto(de)}`;
  return null;
}

function Resumo({ pessoas, total, onVerExtrato, onRegistrar, onPagar, onPdf, gerandoPdf, porPessoa }: {
  pessoas: FreelancerNoResumo[];
  total: { trabalhado: number; pago: number; reembolsos: number; dias: number; deve: number; adiantado: number };
  onVerExtrato: (id: string) => void;
  onRegistrar: (id: string) => void;
  onPagar: (id: string) => void;
  onPdf: (id: string) => void;
  gerandoPdf: boolean;
  /** O período é de cada um ("em aberto"): o cartão diz qual é o dele. */
  porPessoa: boolean;
}) {
  const { formatCurrency, formatDate } = useI18n();
  // F4 da revisão (27/10/2026): no topo, só o que se deve a todos (e o adiantado, quando há) — os
  // totais do período e os acumulados não fechavam entre si. Cada pessoa tem UM número, "A pagar";
  // os cartões vêm na ordem do que mais se deve. Reembolsos (F2b) só aparecem quando há.
  const ordenadas = [...pessoas].sort((a, b) => b.saldo_final - a.saldo_final);
  const topo: Array<readonly [string, string, string]> = [
    ['A pagar a todos', formatCurrency(total.deve), 'text-foreground'],
    ...(total.adiantado > 0 ? [['Adiantado', formatCurrency(total.adiantado), 'text-destructive'] as const] : []),
    ...(total.reembolsos > 0 ? [[ROTULO_REEMBOLSOS, formatCurrency(total.reembolsos), 'text-foreground'] as const] : []),
  ];
  return (
    <div className="space-y-4">
      <Card className="flex min-w-0 flex-wrap gap-x-8 gap-y-2 p-3">
        {topo.map(([rotulo, valor, classe]) => (
          <div key={rotulo} className="min-w-0">
            <p className="truncate text-xs text-muted-foreground" title={rotulo}>{rotulo}</p>
            <p className={`truncate text-lg font-semibold tabular-nums ${classe}`}>{valor}</p>
          </div>
        ))}
      </Card>

      <div className="grid gap-3 md:grid-cols-2">
        {ordenadas.map((p) => {
          const estado = ESTADO_DO_SALDO[p.estado];
          return (
            <Card key={p.id} className="min-w-0 p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="truncate text-lg font-semibold">{p.nome}</p>
                  <p className="text-sm text-muted-foreground">
                    {p.diaria != null ? <>Diária <span className="tabular-nums">{formatCurrency(p.diaria)}</span></> : 'Sem diária no cadastro'}
                    {porPessoa && textoDoPeriodoDaPessoa(p.de, p.ate) && <> · período {textoDoPeriodoDaPessoa(p.de, p.ate)}</>}
                  </p>
                </div>
                <div className="text-right">
                  <p className={`text-xs font-medium ${estado.classe}`}>{estado.rotulo}</p>
                  <p className={`text-2xl font-bold tabular-nums ${estado.classe}`}>{formatCurrency(Math.abs(p.saldo_final))}</p>
                </div>
              </div>
              {/* Com reembolso são 5 campos: 3 por linha no celular grande, sem apertar a ponto de rolar de lado. */}
              <dl className={`mt-3 grid grid-cols-2 gap-2 border-t pt-3 text-sm ${p.reembolsos > 0 ? 'sm:grid-cols-3' : 'sm:grid-cols-4'}`}>
                <div><dt className="text-xs text-muted-foreground">Dias</dt><dd className="font-medium tabular-nums">{p.dias.toLocaleString('pt-BR')}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Trabalhado</dt><dd className="font-medium tabular-nums">{formatCurrency(p.trabalhado)}</dd></div>
                {p.reembolsos > 0 && (
                  <div className="min-w-0" title="Despesas da empresa que ele pagou, com comprovante (CMP): entram no próximo acerto">
                    <dt className="text-xs text-muted-foreground">{ROTULO_REEMBOLSOS}</dt><dd className="font-medium tabular-nums">{formatCurrency(p.reembolsos)}</dd>
                  </div>
                )}
                <div><dt className="text-xs text-muted-foreground">Pago</dt><dd className="font-medium tabular-nums">{formatCurrency(p.pago)}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Último pagamento</dt><dd className="font-medium tabular-nums">{p.ultimo_pagamento ? formatDate(p.ultimo_pagamento) : '—'}</dd></div>
              </dl>
              {p.pago_aguardando_banco > 0 && (
                <p className="mt-2 text-xs text-amber-700 dark:text-amber-400">
                  Inclui <span className="tabular-nums">{formatCurrency(p.pago_aguardando_banco)}</span> lançado(s) à mão, aguardando o banco confirmar.
                </p>
              )}
              {p.pago_falta_aprovar > 0 && (
                <p className="mt-2 text-xs text-amber-700 dark:text-amber-400">
                  Inclui <span className="tabular-nums">{formatCurrency(p.pago_falta_aprovar)}</span> em Pix que já saiu do banco para ele e falta aprovar na fila de lançamentos.
                </p>
              )}
              <AcoesDaLinha
                className="mt-3 justify-start"
                rotulo={p.nome}
                rapidas={[
                  { texto: 'Registrar dia', icone: CalendarPlus, onClick: () => onRegistrar(p.id) },
                  { texto: 'Pagar', icone: Banknote, onClick: () => onPagar(p.id) },
                  { texto: 'Lançamentos e recibo', icone: FileText, onClick: () => onVerExtrato(p.id) },
                ]}
                menu={[
                  { texto: 'Extrato em PDF', icone: FileDown, desabilitada: gerandoPdf, onClick: () => onPdf(p.id) },
                ]}
              />
            </Card>
          );
        })}
      </div>
      <p className="text-xs text-muted-foreground">
        Saldo = saldo inicial + dias trabalhados (diária + extras − descontos) + reembolso de despesas pagas pelo técnico (com comprovante) − o que ele recebeu. Os pagamentos vêm do
        extrato do banco; o Pix registrado à mão ("Registrar pagamento" ou "Lançar") aparece na hora como "aguardando o
        banco" e já desconta — não lance de novo quando a linha do banco chegar. O Pix que saiu do banco para o CPF dele
        também desconta, como "falta aprovar", até ser aprovado na fila. Só desconta o que é da categoria "Diárias de
        freelancers" (ou ainda sem categoria): um Pix de almoço ou de peças para ele não entra aqui.
      </p>
    </div>
  );
}

function Extrato({ favorecidoId, periodo, onEditar, onRecibo, gerandoPdf }: {
  favorecidoId: string | null;
  periodo: PedidoDePeriodo;
  onEditar: (d: DiaParaEditar) => void;
  onRecibo: (favorecidoId: string, a: Acerto) => void;
  gerandoPdf: boolean;
}) {
  const { formatCurrency } = useI18n();
  const conta = useContaCorrente(favorecidoId, periodo.de, periodo.ate, periodo.atalho);
  const acertos = useAcertos(favorecidoId);
  const { excluir, excluindo } = useExcluirDiaComDesfazer();
  const [dividindo, setDividindo] = useState<PagamentoParaDividir | null>(null);
  const juntar = useDividirPagamentoDoFreelancer();
  // desfazer a divisão muda a categoria de lançamentos e devolve os reembolsos: pede confirmação (padrão do projeto)
  const { pedir, dialogo } = useConfirmacao();
  // "Dividir" só aparece com reembolso em aberto: uma pergunta ao banco por extrato (a lista em aberto
  // não depende do valor; vai o do maior pagamento do banco ainda não dividido, se houver algum).
  const divisiveis = (conta.data?.linhas ?? []).filter((l) => pagamentoQueSeDivide(l) && !pagamentoDividido(l));
  const emAberto = usePropostaDeDivisao(favorecidoId, divisiveis.reduce((m, l) => Math.max(m, l.pago), 0));
  const haReembolsoEmAberto = (emAberto.data?.em_aberto.length ?? 0) > 0;

  if (!favorecidoId) {
    return <Card className="p-6 text-center text-sm text-muted-foreground">Escolha o freelancer para ver o extrato.</Card>;
  }
  if (conta.isLoading) return <Skeleton className="h-48 w-full" />;
  if (conta.error) {
    return <Card className="border-destructive/40 p-4 text-sm text-destructive">Não deu para carregar o extrato: {(conta.error as Error).message}</Card>;
  }
  const c = conta.data!;
  const estado = ESTADO_DO_SALDO[c.estado];
  const totais: Array<readonly [string, string]> = [
    [c.de ? 'Saldo antes do período' : 'Saldo inicial', formatCurrency(c.saldo_anterior)],
    ['Trabalhado', formatCurrency(c.trabalhado)],
    ...(c.reembolsos > 0 ? [[ROTULO_REEMBOLSOS, formatCurrency(c.reembolsos)] as const] : []),
    ['Pago', formatCurrency(c.pago)],
    ['Saldo no fim', formatCurrency(c.saldo_final)],
  ];

  return (
    <div className="space-y-3">
      <div className={`grid grid-cols-2 gap-2 ${totais.length > 4 ? 'lg:grid-cols-5' : 'lg:grid-cols-4'}`}>
        {totais.map(([rotulo, valor]) => (
          <Card key={rotulo} className="min-w-0 p-3">
            <p className="truncate text-xs text-muted-foreground" title={rotulo}>{rotulo}</p>
            <p className="truncate font-semibold tabular-nums">{valor}</p>
          </Card>
        ))}
      </div>
      <div className="text-sm">
        <Badge variant="outline" className={estado.classe}>{estado.rotulo}</Badge>
        <span className="ml-2 text-muted-foreground">
          {periodo.atalho && textoDoPeriodoDaPessoa(c.de, c.ate) ? `Período ${textoDoPeriodoDaPessoa(c.de, c.ate)}. ` : ''}
          {c.favorecido.desde ? `Conta corrente desde ${diaCurto(c.favorecido.desde)}/${c.favorecido.desde.slice(0, 4)}.` : ''}
          {' '}Saldo positivo = você deve; negativo = pagou adiantado.
        </span>
      </div>

      <AcertosDoFreelancer favorecidoId={c.favorecido.id} nome={c.favorecido.nome} acertos={acertos.data ?? []}
                           gerandoPdf={gerandoPdf} onRecibo={(a) => onRecibo(c.favorecido.id, a)} />

      {c.linhas.length === 0 ? (
        <Card className="p-6 text-center text-sm text-muted-foreground">Nenhum dia, reembolso nem pagamento neste período.</Card>
      ) : (
        <Card className="divide-y p-0">
          {c.linhas.map((l) => (
            <div key={`${l.tipo}-${l.id}`} className="flex min-w-0 items-start gap-3 p-3"
                 title={l.tipo === 'reembolso' ? `Para tirar, cancele o ${l.conta ?? 'comprovante'} pelo WhatsApp` : undefined}>
              <div className="w-16 shrink-0 text-sm">
                <p className="font-semibold tabular-nums">{diaCurto(l.data).slice(4)}</p>
                <p className="text-xs text-muted-foreground">{diaCurto(l.data).slice(0, 3)}</p>
              </div>
              <div className="min-w-0 flex-1">
                {l.tipo === 'reembolso' ? (
                  <>
                    <div className="flex flex-wrap items-center gap-x-2 text-sm">
                      {/* o rótulo inteiro (resposta 9 do dono); no celular, corta com reticências */}
                      <Badge variant="outline" className="min-w-0 max-w-full text-muted-foreground" title={ROTULO_REEMBOLSO}>
                        <span className="truncate">{ROTULO_REEMBOLSO}</span>
                      </Badge>
                      <span className="min-w-0 truncate">{l.conta}</span>
                      {/* o número já vem como "OS-0042" (ou "ORÇ-…"): sem outro "OS " na frente */}
                      {l.os.length > 0 && <span className="min-w-0 truncate">{l.os.map((o) => o.numero).join(', ')}</span>}
                    </div>
                    {/* a descrição sem o "Reembolso CMP-00124 · " do banco: o selo e o código já estão acima;
                        coberto por um pagamento dividido, o banco diz quando ("pago em 12/10") */}
                    <p className="mt-0.5 truncate text-xs text-muted-foreground">
                      {[descricaoDoReembolso(l), l.categoria, l.observacao].filter(Boolean).join(' · ')}
                    </p>
                    <p className="mt-0.5 text-xs text-muted-foreground">{comoTirarOReembolso(l.conta, acertoQueTrava(acertos.data, l.data))}</p>
                  </>
                ) : l.tipo === 'dia' ? (
                  <>
                    <div className="flex flex-wrap items-center gap-x-2 text-sm">
                      <Badge variant="outline" className={l.jornada === 'faltou' ? 'text-muted-foreground' : 'text-success'}>
                        {rotuloDaJornada(l.jornada)}
                      </Badge>
                      {/* como no reembolso: o número já vem como "OS-0042" (ou "ORÇ-…") */}
                      {l.os.length > 0 && <span className="min-w-0 truncate">{l.os.map((o) => o.numero).join(', ')}</span>}
                    </div>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      {l.jornada === 'faltou' ? 'Sem diária' : `${l.fracao === 0.5 ? '½ × ' : ''}${formatCurrency(l.valor_diaria ?? 0)}`}
                      {l.extras ? ` + extras ${formatCurrency(l.extras)}` : ''}
                      {l.descontos ? ` − desc. ${formatCurrency(l.descontos)}` : ''}
                      {l.observacao ? ` · ${l.observacao}` : ''}
                    </p>
                  </>
                ) : (
                  <>
                    <div className="flex flex-wrap items-center gap-x-2 text-sm">
                      {pagamentoNaFila(l) ? (
                        <Badge variant="outline" className="text-amber-700 dark:text-amber-400"
                               title="Já saiu do banco para ele; vira o pagamento quando for aprovado na fila de lançamentos">
                          Falta aprovar
                        </Badge>
                      ) : l.aguardando ? (
                        <Badge variant="outline" className="text-amber-700 dark:text-amber-400"
                               title="Lançado à mão; vira o pagamento do banco quando a linha chegar e for aprovada">
                          Anotado
                        </Badge>
                      ) : (
                        <Badge variant="outline" className="text-sky-700 dark:text-sky-400">Pagamento</Badge>
                      )}
                      <span className="min-w-0 truncate">{l.conta}</span>
                    </div>
                    <p className="mt-0.5 truncate text-xs text-muted-foreground">
                      {l.descricao}{l.categoria ? ` · ${l.categoria}` : ''}
                    </p>
                  </>
                )}
              </div>
              <div className="shrink-0 text-right">
                <p className={`font-semibold tabular-nums ${l.tipo === 'pagamento' ? 'text-success' : ''}`}>
                  {l.tipo === 'pagamento' ? `− ${formatCurrency(l.pago)}`
                    : l.tipo === 'reembolso' ? `+ ${formatCurrency(l.trabalhado)}`
                    : formatCurrency(l.trabalhado)}
                </p>
                <p className="text-xs tabular-nums text-muted-foreground">saldo {formatCurrency(l.saldo)}</p>
              </div>
              {l.tipo === 'dia' ? (
                <AcoesDaLinha
                  rotulo={`dia ${diaCurto(l.data)}`}
                  ocupada={excluindo}
                  // Dia dentro de acerto fechado: travado (o banco recusaria). Reabrir é no bloco Acertos.
                  menu={acertoQueTrava(acertos.data, l.data) ? [
                    { texto: `Travado no acerto nº ${numeroDoRecibo(acertoQueTrava(acertos.data, l.data)!.numero)}`, icone: Lock, desabilitada: true, onClick: () => {} },
                  ] : [
                    { texto: 'Corrigir o dia', icone: Pencil, onClick: () => onEditar(diaParaEditar(c.favorecido.id, l)) },
                    { texto: 'Excluir o dia', icone: Trash2, perigo: true, onClick: () => { void excluir(l.id); } },
                  ]}
                />
              ) : pagamentoDividido(l) ? (
                // Já dividido: juntar de volta (tudo em Diárias) libera os reembolsos para outra divisão.
                <AcoesDaLinha
                  rotulo={`pagamento ${diaCurto(l.data)}`}
                  ocupada={juntar.isPending}
                  menu={[{
                    texto: 'Desfazer a divisão (tudo volta para Diárias)', icone: Undo2,
                    onClick: () => pedir({
                      titulo: 'Desfazer a divisão?',
                      descricao: 'O pagamento volta inteiro para Diárias e os reembolsos voltam a ficar em aberto.',
                      confirmar: 'Desfazer',
                      acao: () => juntar.mutate({ payableId: l.id, reembolsos: [] }),
                    }),
                  }]}
                />
              ) : haReembolsoEmAberto && pagamentoQueSeDivide(l) ? (
                <AcoesDaLinha
                  rotulo={`pagamento ${diaCurto(l.data)}`}
                  menu={[{
                    texto: 'Dividir: diárias e reembolso', icone: Split,
                    titulo: `Separar deste pagamento o ${ROTULO_REEMBOLSOS.toLowerCase()}`,
                    onClick: () => setDividindo({ id: l.id, valor: l.pago, data: l.data }),
                  }]}
                />
              ) : (
                // Pagamento vem do extrato; reembolso só sai cancelando o CMP: nenhum dos dois tem menu aqui.
                <span className="w-8 shrink-0" aria-hidden />
              )}
            </div>
          ))}
        </Card>
      )}

      {dividindo && (
        <DividirPagamentoDialog favorecidoId={c.favorecido.id} nome={c.favorecido.nome} pagamento={dividindo}
                                onFechar={() => setDividindo(null)} />
      )}
      {dialogo}
    </div>
  );
}
