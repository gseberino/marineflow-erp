// Financeiro › Diárias: quanto cada freelancer trabalhou, quanto recebeu e o saldo com ele.
//
// O saldo vem pronto do banco (saldo inicial + trabalhado − pago). O "pago" é o que já veio do
// extrato no nome dele (Pix, Caixa) e o que um sócio pagou do próprio bolso para ele — não se
// digita pagamento aqui: o banco traz. Aqui se lança o DIA.
import { useState } from 'react';
import { CalendarPlus, FileDown, FileText, Pencil, Trash2, UserPlus } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Skeleton } from '@/components/ui/skeleton';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { useI18n } from '@/i18n';
import {
  ESTADO_DO_SALDO, PERIODOS, diaCurto, intervaloDoMes, intervaloDoPeriodo, rotuloDaJornada,
  type PeriodoDasDiarias,
} from '@/lib/diarias';
import {
  diaParaEditar, useContaCorrente, useExcluirDiaComDesfazer, useResumoFreelancers,
  type DiaParaEditar, type FreelancerNoResumo,
} from '@/hooks/use-diarias';
import { useDocumentosDasDiarias } from '@/hooks/use-documentos-diarias';
import { RegistrarDiaDialog } from './RegistrarDiaDialog';
import { NovoFreelancerDialog } from './NovoFreelancerDialog';
import { GradeDiarias } from './GradeDiarias';

export interface FiltroDasDiarias {
  periodo: PeriodoDasDiarias;
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
  const { de, ate } = intervaloDoPeriodo(filtro.periodo);
  const resumo = useResumoFreelancers(de, ate);
  const pessoas = resumo.data?.pessoas ?? [];
  const [registrando, setRegistrando] = useState<Registrando | null>(null);
  const [cadastrando, setCadastrando] = useState(false);
  const documentos = useDocumentosDasDiarias();
  // O que os documentos cobrem: na grade, o mês que está na tela; nas outras abas, o período.
  const intervalo = aba === 'grade' ? intervaloDoMes(filtro.mes) : { de, ate };

  const barra = (
    <div className="flex flex-wrap items-center gap-2">
      {/* A grade anda de mês em mês pelas setas dela; o período vale para Resumo e Extrato. */}
      {aba !== 'grade' && (
        <Select value={filtro.periodo} onValueChange={(v) => onFiltro({ ...filtro, periodo: v as PeriodoDasDiarias })}>
          <SelectTrigger className="h-9 w-40" aria-label="Período"><SelectValue /></SelectTrigger>
          <SelectContent>
            {PERIODOS.map((p) => <SelectItem key={p.valor} value={p.valor}>{p.rotulo}</SelectItem>)}
          </SelectContent>
        </Select>
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
                  onClick={() => { void documentos.extratoEmPdf(filtro.favorecidoId!, intervalo.de, intervalo.ate); }}>
            <FileText className="h-4 w-4" /> {documentos.gerando === 'pdf' ? 'Gerando…' : 'Extrato em PDF'}
          </Button>
        )}
        <Button size="sm" variant="outline" className="gap-1.5" disabled={!!documentos.gerando || pessoas.length === 0}
                title="Todos os dias e pagamentos do período, de todos os freelancers, para o contador"
                onClick={() => { void documentos.csvDoPeriodo(pessoas.map((p) => p.id), intervalo.de, intervalo.ate); }}>
          <FileDown className="h-4 w-4" /> {documentos.gerando === 'csv' ? 'Gerando…' : 'Planilha do contador (CSV)'}
        </Button>
        <Button size="sm" variant="outline" className="gap-1.5" onClick={() => setCadastrando(true)}>
          <UserPlus className="h-4 w-4" /> Novo freelancer
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
      {resumo.isLoading ? (
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
                onPdf={(id) => { void documentos.extratoEmPdf(id, de, ate); }} />
      ) : aba === 'grade' ? (
        <GradeDiarias
          pessoas={pessoas}
          mes={filtro.mes}
          onMes={(mes) => onFiltro({ ...filtro, mes })}
          onEditar={(d) => setRegistrando({ editar: d })}
          onNovo={(favorecidoId, data) => setRegistrando({ favorecidoId, dataInicial: data })}
        />
      ) : (
        <Extrato favorecidoId={filtro.favorecidoId} de={de} ate={ate}
                 onEditar={(d) => setRegistrando({ editar: d })} />
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
    </div>
  );
}

function Resumo({ pessoas, total, onVerExtrato, onRegistrar, onPdf, gerandoPdf }: {
  pessoas: FreelancerNoResumo[];
  total: { trabalhado: number; pago: number; dias: number; deve: number; adiantado: number };
  onVerExtrato: (id: string) => void;
  onRegistrar: (id: string) => void;
  onPdf: (id: string) => void;
  gerandoPdf: boolean;
}) {
  const { formatCurrency, formatDate } = useI18n();
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
        {([
          ['Trabalhado no período', formatCurrency(total.trabalhado), `${total.dias.toLocaleString('pt-BR')} diárias`],
          ['Pago no período', formatCurrency(total.pago), 'do extrato e do bolso de sócio'],
          ['Você deve (acumulado)', formatCurrency(total.deve), 'até o fim do período'],
          ['Adiantado (acumulado)', formatCurrency(total.adiantado), 'pago antes do trabalho'],
        ] as const).map(([rotulo, valor, nota]) => (
          <Card key={rotulo} className="min-w-0 p-3">
            <p className="truncate text-xs text-muted-foreground">{rotulo}</p>
            <p className="truncate text-lg font-semibold tabular-nums">{valor}</p>
            <p className="truncate text-xs text-muted-foreground">{nota}</p>
          </Card>
        ))}
      </div>

      <div className="grid gap-3 md:grid-cols-2">
        {pessoas.map((p) => {
          const estado = ESTADO_DO_SALDO[p.estado];
          return (
            <Card key={p.id} className="min-w-0 p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="truncate text-lg font-semibold">{p.nome}</p>
                  <p className="text-sm text-muted-foreground">
                    {p.diaria != null ? <>Diária <span className="tabular-nums">{formatCurrency(p.diaria)}</span></> : 'Sem diária no cadastro'}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-xs text-muted-foreground">Saldo acumulado</p>
                  <p className={`text-2xl font-bold tabular-nums ${estado.classe}`}>{formatCurrency(Math.abs(p.saldo_final))}</p>
                  <Badge variant="outline" className={estado.classe}>{estado.rotulo}</Badge>
                </div>
              </div>
              <dl className="mt-3 grid grid-cols-2 gap-2 border-t pt-3 text-sm sm:grid-cols-4">
                <div><dt className="text-xs text-muted-foreground">Dias</dt><dd className="font-medium tabular-nums">{p.dias.toLocaleString('pt-BR')}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Trabalhado</dt><dd className="font-medium tabular-nums">{formatCurrency(p.trabalhado)}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Pago</dt><dd className="font-medium tabular-nums">{formatCurrency(p.pago)}</dd></div>
                <div><dt className="text-xs text-muted-foreground">Último pagamento</dt><dd className="font-medium tabular-nums">{p.ultimo_pagamento ? formatDate(p.ultimo_pagamento) : '—'}</dd></div>
              </dl>
              <AcoesDaLinha
                className="mt-3 justify-start"
                rotulo={p.nome}
                rapidas={[
                  { texto: 'Registrar dia', icone: CalendarPlus, onClick: () => onRegistrar(p.id) },
                  { texto: 'Ver extrato', icone: FileText, onClick: () => onVerExtrato(p.id) },
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
        Saldo = saldo inicial + dias trabalhados (diária + extras − descontos) − o que ele recebeu. Os pagamentos vêm do extrato; não se digitam aqui.
      </p>
    </div>
  );
}

function Extrato({ favorecidoId, de, ate, onEditar }: {
  favorecidoId: string | null;
  de: string | null;
  ate: string | null;
  onEditar: (d: DiaParaEditar) => void;
}) {
  const { formatCurrency } = useI18n();
  const conta = useContaCorrente(favorecidoId, de, ate);
  const { excluir, excluindo } = useExcluirDiaComDesfazer();

  if (!favorecidoId) {
    return <Card className="p-6 text-center text-sm text-muted-foreground">Escolha o freelancer para ver o extrato.</Card>;
  }
  if (conta.isLoading) return <Skeleton className="h-48 w-full" />;
  if (conta.error) {
    return <Card className="border-destructive/40 p-4 text-sm text-destructive">Não deu para carregar o extrato: {(conta.error as Error).message}</Card>;
  }
  const c = conta.data!;
  const estado = ESTADO_DO_SALDO[c.estado];

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
        {([
          [c.de ? 'Saldo antes do período' : 'Saldo inicial', formatCurrency(c.saldo_anterior)],
          ['Trabalhado', formatCurrency(c.trabalhado)],
          ['Pago', formatCurrency(c.pago)],
          ['Saldo no fim', formatCurrency(c.saldo_final)],
        ] as const).map(([rotulo, valor]) => (
          <Card key={rotulo} className="min-w-0 p-3">
            <p className="truncate text-xs text-muted-foreground">{rotulo}</p>
            <p className="truncate font-semibold tabular-nums">{valor}</p>
          </Card>
        ))}
      </div>
      <div className="text-sm">
        <Badge variant="outline" className={estado.classe}>{estado.rotulo}</Badge>
        <span className="ml-2 text-muted-foreground">
          {c.favorecido.desde ? `Conta corrente desde ${diaCurto(c.favorecido.desde)}/${c.favorecido.desde.slice(0, 4)}.` : ''}
          {' '}Saldo positivo = você deve; negativo = pagou adiantado.
        </span>
      </div>

      {c.linhas.length === 0 ? (
        <Card className="p-6 text-center text-sm text-muted-foreground">Nenhum dia nem pagamento neste período.</Card>
      ) : (
        <Card className="divide-y p-0">
          {c.linhas.map((l) => (
            <div key={`${l.tipo}-${l.id}`} className="flex min-w-0 items-start gap-3 p-3">
              <div className="w-16 shrink-0 text-sm">
                <p className="font-semibold tabular-nums">{diaCurto(l.data).slice(4)}</p>
                <p className="text-xs text-muted-foreground">{diaCurto(l.data).slice(0, 3)}</p>
              </div>
              <div className="min-w-0 flex-1">
                {l.tipo === 'dia' ? (
                  <>
                    <div className="flex flex-wrap items-center gap-x-2 text-sm">
                      <Badge variant="outline" className={l.jornada === 'faltou' ? 'text-muted-foreground' : 'text-success'}>
                        {rotuloDaJornada(l.jornada)}
                      </Badge>
                      {l.os.length > 0 && <span className="min-w-0 truncate">OS {l.os.map((o) => o.numero).join(', ')}</span>}
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
                      <Badge variant="outline" className="text-sky-700 dark:text-sky-400">Pagamento</Badge>
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
                  {l.tipo === 'pagamento' ? `− ${formatCurrency(l.pago)}` : formatCurrency(l.trabalhado)}
                </p>
                <p className="text-xs tabular-nums text-muted-foreground">saldo {formatCurrency(l.saldo)}</p>
              </div>
              {l.tipo === 'dia' ? (
                <AcoesDaLinha
                  rotulo={`dia ${diaCurto(l.data)}`}
                  ocupada={excluindo}
                  menu={[
                    { texto: 'Corrigir o dia', icone: Pencil, onClick: () => onEditar(diaParaEditar(c.favorecido.id, l)) },
                    { texto: 'Excluir o dia', icone: Trash2, perigo: true, onClick: () => { void excluir(l.id); } },
                  ]}
                />
              ) : (
                <span className="w-8 shrink-0" aria-hidden />
              )}
            </div>
          ))}
        </Card>
      )}
    </div>
  );
}
