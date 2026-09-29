// A grade do mês: dias nas linhas, freelancers nas colunas. Clicar numa célula abre a ficha do dia.
//
// NÃO é o WeekView da Agenda (pessoa × 7 dias, cartões de OS e tarefa, arrastar e soltar): a
// semelhança se resume a "matriz com clique na célula", e extrair um componente comum obrigaria a
// mexer numa tela que funciona. Decisão registrada no plano (28/09/2026).
//
// Sem rolagem lateral (regra da casa): no computador a grade usa colunas elásticas; no celular vira
// uma lista por dia, com um botão por pessoa.
import { useMemo, useState } from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { useI18n } from '@/i18n';
import { hojeLocal } from '@/lib/dia';
import { diaCurto, diasDoMes, ehFimDeSemana, intervaloDoMes, nomeDoMes, somarMes, mesDe } from '@/lib/diarias';
import {
  diaParaEditar, useContasDoPeriodo,
  type DiaParaEditar, type FreelancerNoResumo, type LinhaDaContaCorrente,
} from '@/hooks/use-diarias';
import { FichaDoDia } from './FichaDoDia';

interface Props {
  pessoas: FreelancerNoResumo[];
  mes: string;
  onMes: (mes: string) => void;
  onEditar: (d: DiaParaEditar) => void;
  onNovo: (favorecidoId: string, data: string) => void;
}

type Celula = { dia: LinhaDaContaCorrente | null; pagamentos: LinhaDaContaCorrente[] };

const ROTULO_CURTO = { inteiro: 'Dia', meio: 'Meio', faltou: 'Faltou' } as const;

export function GradeDiarias({ pessoas, mes, onMes, onEditar, onNovo }: Props) {
  const { formatCurrency } = useI18n();
  const { de, ate } = intervaloDoMes(mes);
  const hoje = hojeLocal();
  const dias = diasDoMes(mes);
  const contas = useContasDoPeriodo(pessoas.map((p) => p.id), de, ate);
  const [aberta, setAberta] = useState<{ pessoaId: string; data: string } | null>(null);

  // Índice pessoa|data → o dia e os pagamentos. A ficha lê daqui a cada render, então o que muda
  // pelas três ações aparece nela sem fechar e abrir.
  const celulas = useMemo(() => {
    const m = new Map<string, Celula>();
    pessoas.forEach((p, i) => {
      for (const l of contas[i]?.data?.linhas ?? []) {
        const k = `${p.id}|${l.data}`;
        const c = m.get(k) ?? { dia: null, pagamentos: [] };
        if (l.tipo === 'dia') c.dia = l; else c.pagamentos.push(l);
        m.set(k, c);
      }
    });
    return m;
  }, [pessoas, contas]);
  const celula = (pessoaId: string, data: string): Celula => celulas.get(`${pessoaId}|${data}`) ?? { dia: null, pagamentos: [] };
  // Antes do início da conta corrente e no futuro não se lança: a célula fica apagada.
  const bloqueada = (p: FreelancerNoResumo, data: string) => data > hoje || (!!p.desde && data < p.desde);

  const carregando = contas.some((c) => c.isLoading);
  const erro = contas.find((c) => c.error)?.error as Error | undefined;

  const totalDoDia = (data: string) => pessoas.reduce((s, p) => s + (celula(p.id, data).dia?.trabalhado ?? 0), 0);
  const conteudoDaCelula = (c: Celula) => (
    <>
      {c.dia && (
        <span className={`rounded px-1.5 py-0.5 text-[11px] font-semibold ${c.dia.jornada === 'faltou'
          ? 'bg-muted text-muted-foreground' : 'bg-success/15 text-success'}`}>
          {ROTULO_CURTO[c.dia.jornada ?? 'inteiro']}{c.dia.jornada !== 'faltou' ? ` ${formatCurrency(c.dia.trabalhado)}` : ''}
        </span>
      )}
      {c.pagamentos.map((p) => (
        <span key={p.id} className="rounded bg-sky-500/10 px-1.5 py-0.5 text-[11px] font-semibold text-sky-700 dark:text-sky-400">
          pago {formatCurrency(p.pago)}
        </span>
      ))}
    </>
  );

  const pessoaAberta = aberta ? pessoas.find((p) => p.id === aberta.pessoaId) : null;
  const linhasAbertas = aberta ? (() => { const c = celula(aberta.pessoaId, aberta.data); return [...(c.dia ? [c.dia] : []), ...c.pagamentos]; })() : [];

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Button size="sm" variant="outline" aria-label="Mês anterior" onClick={() => onMes(somarMes(mes, -1))}>
          <ChevronLeft className="h-4 w-4" />
        </Button>
        <h3 className="min-w-44 text-center text-lg font-semibold">{nomeDoMes(mes)}</h3>
        <Button size="sm" variant="outline" aria-label="Próximo mês" onClick={() => onMes(somarMes(mes, 1))}>
          <ChevronRight className="h-4 w-4" />
        </Button>
        {mes !== mesDe(hoje) && <Button size="sm" variant="ghost" onClick={() => onMes(mesDe(hoje))}>Este mês</Button>}
        <span className="text-xs text-muted-foreground">Clique num dia para marcar, corrigir ou excluir.</span>
      </div>

      {carregando ? (
        <Skeleton className="h-96 w-full" />
      ) : erro ? (
        <Card className="border-destructive/40 p-4 text-sm text-destructive">Não deu para carregar a grade: {erro.message}</Card>
      ) : (
        <>
          {/* Computador: a matriz. Colunas elásticas — sem rolagem lateral. */}
          <Card className="hidden overflow-hidden p-0 md:block">
            <div role="grid" aria-label={`Diárias de ${nomeDoMes(mes)}`} className="grid text-sm"
                 style={{ gridTemplateColumns: `5.5rem repeat(${pessoas.length}, minmax(0, 1fr)) 7.5rem` }}>
              <div role="row" className="contents">
                <div role="columnheader" className="border-b bg-muted/50 px-2 py-1.5 text-xs font-semibold text-muted-foreground">Dia</div>
                {pessoas.map((p) => (
                  <div key={p.id} role="columnheader" className="truncate border-b border-l bg-muted/50 px-2 py-1.5 text-xs font-semibold">{p.nome}</div>
                ))}
                <div role="columnheader" className="border-b border-l bg-muted/50 px-2 py-1.5 text-right text-xs font-semibold text-muted-foreground">Total do dia</div>
              </div>
              {dias.map((d) => {
                const fds = ehFimDeSemana(d);
                const total = totalDoDia(d);
                return (
                  <div key={d} role="row" className="contents">
                    <div role="rowheader" className={`flex items-center gap-1.5 border-b px-2 py-1 tabular-nums ${fds ? 'bg-muted/40' : ''} ${d === hoje ? 'font-bold text-primary' : ''}`}>
                      <span className="font-semibold">{d.slice(8)}</span>
                      <span className="text-xs text-muted-foreground">{diaCurto(d).slice(0, 3)}</span>
                    </div>
                    {pessoas.map((p) => {
                      const c = celula(p.id, d);
                      const off = bloqueada(p, d);
                      return (
                        <button key={p.id} type="button" role="gridcell" disabled={off}
                                aria-label={`${p.nome} em ${diaCurto(d)}`}
                                onClick={() => setAberta({ pessoaId: p.id, data: d })}
                                className={`flex min-h-9 min-w-0 flex-wrap items-center gap-1 border-b border-l px-2 py-1 text-left
                                  ${fds ? 'bg-muted/40' : ''} ${off ? 'cursor-not-allowed opacity-40' : 'hover:bg-muted'}`}>
                          {conteudoDaCelula(c)}
                        </button>
                      );
                    })}
                    <div role="gridcell" className={`border-b border-l px-2 py-1 text-right tabular-nums ${fds ? 'bg-muted/40' : ''}`}>
                      {total ? formatCurrency(total) : <span className="text-muted-foreground">–</span>}
                    </div>
                  </div>
                );
              })}
              {([
                ['Diárias no mês', (i: number) => (contas[i]?.data?.dias ?? 0).toLocaleString('pt-BR'),
                  () => contas.reduce((s, c) => s + (c.data?.dias ?? 0), 0).toLocaleString('pt-BR')],
                ['Trabalhado', (i: number) => formatCurrency(contas[i]?.data?.trabalhado ?? 0),
                  () => formatCurrency(contas.reduce((s, c) => s + (c.data?.trabalhado ?? 0), 0))],
                ['Pago', (i: number) => formatCurrency(contas[i]?.data?.pago ?? 0),
                  () => formatCurrency(contas.reduce((s, c) => s + (c.data?.pago ?? 0), 0))],
                ['Saldo acumulado', (i: number) => formatCurrency(contas[i]?.data?.saldo_final ?? 0),
                  () => formatCurrency(contas.reduce((s, c) => s + (c.data?.saldo_final ?? 0), 0))],
              ] as const).map(([rotulo, porPessoa, soma]) => (
                <div key={rotulo} role="row" className="contents">
                  <div role="rowheader" className="border-b bg-muted/50 px-2 py-1.5 text-xs font-semibold text-muted-foreground">{rotulo}</div>
                  {pessoas.map((p, i) => (
                    <div key={p.id} role="gridcell" className="truncate border-b border-l bg-muted/50 px-2 py-1.5 text-right font-semibold tabular-nums">{porPessoa(i)}</div>
                  ))}
                  <div role="gridcell" className="border-b border-l bg-muted/50 px-2 py-1.5 text-right font-semibold tabular-nums">{soma()}</div>
                </div>
              ))}
            </div>
          </Card>

          {/* Celular: um bloco por dia, um botão por pessoa. */}
          <div className="space-y-1.5 md:hidden">
            {dias.map((d) => (
              <Card key={d} className={`p-2 ${ehFimDeSemana(d) ? 'bg-muted/40' : ''}`}>
                <p className={`text-sm font-semibold ${d === hoje ? 'text-primary' : ''}`}>{diaCurto(d)}</p>
                <div className="mt-1 grid gap-1">
                  {pessoas.map((p) => {
                    const off = bloqueada(p, d);
                    return (
                      <button key={p.id} type="button" disabled={off} onClick={() => setAberta({ pessoaId: p.id, data: d })}
                              aria-label={`${p.nome} em ${diaCurto(d)}`}
                              className={`flex min-w-0 flex-wrap items-center gap-1 rounded border px-2 py-1 text-left text-sm ${off ? 'opacity-40' : 'hover:bg-muted'}`}>
                        <span className="mr-1 min-w-0 truncate">{p.nome.split(' ')[0]}</span>
                        {conteudoDaCelula(celula(p.id, d))}
                      </button>
                    );
                  })}
                </div>
              </Card>
            ))}
            <Card className="grid grid-cols-2 gap-2 p-3 text-sm">
              {pessoas.map((p, i) => (
                <div key={p.id} className="min-w-0">
                  <p className="truncate font-medium">{p.nome.split(' ')[0]}</p>
                  <p className="text-xs text-muted-foreground">{(contas[i]?.data?.dias ?? 0).toLocaleString('pt-BR')} diárias · saldo {formatCurrency(contas[i]?.data?.saldo_final ?? 0)}</p>
                </div>
              ))}
            </Card>
          </div>
          <p className="text-xs text-muted-foreground">
            Saldo acumulado = tudo trabalhado até o fim deste mês menos tudo pago, desde o início da conta corrente.
          </p>
        </>
      )}

      {aberta && pessoaAberta && (
        <FichaDoDia
          pessoa={pessoaAberta}
          data={aberta.data}
          linhas={linhasAbertas}
          onFechar={() => setAberta(null)}
          onEditar={(d) => { setAberta(null); onEditar(d); }}
          onDetalhes={() => {
            const dia = celula(aberta.pessoaId, aberta.data).dia;
            setAberta(null);
            if (dia) onEditar(diaParaEditar(aberta.pessoaId, dia));
            else onNovo(aberta.pessoaId, aberta.data);
          }}
        />
      )}
    </div>
  );
}
