import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import {
  AlertTriangle, Clock, Eye, GitCompare, Loader2, Lock, RefreshCw, RotateCcw, Undo2,
} from 'lucide-react';
import { ROTULOS_STATUS_OS } from '../../supabase/functions/_shared/service-order-status';
import {
  ehHistoricoSemPermissao, mensagemDoErro, useHistoricoDocumento, useRestaurarDocumento,
  type DiferencasDoDocumento, type EventoDoHistorico, type ItemDoEvento, type LinhaDaVersao,
  type MudancaDoHistorico, type ResultadoDaRestauracao, type VersaoDoDocumento,
} from '@/hooks/use-historico-documento';
import { useOptionalAuth } from '@/hooks/use-auth';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { Skeleton } from '@/components/ui/skeleton';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { cn } from '@/lib/utils';

/**
 * Histórico do orçamento/OS (F4 do histórico de documentos, 16/11/2026).
 *
 * Antes esta aba lia o audit_log cru e montava o "antes → depois" na tela, com um mapa de
 * rótulos próprio. Agora quem monta é o banco (public.documento_historico): o mesmo texto que o
 * assistente lê no WhatsApp, já com nomes no lugar de uuid, R$ e datas de Brasília. Daqui só se
 * desenha — e se pede para desfazer/voltar (public.documento_restaurar), sempre simulando antes.
 *
 * Três regras da casa que moram aqui:
 *  - leitura que falha mostra a FALHA, com "tentar de novo" — nunca "nenhuma alteração";
 *  - o técnico não lê o histórico (o banco dá 42501): frase amigável, não o erro cru;
 *  - desfazer/voltar só em documento aberto e para administrador/financeiro (o banco recusa
 *    o resto de qualquer jeito; esconder a ação evita oferecer o que vai dar erro).
 */

const ACAO_COR: Record<string, string> = {
  'incluído': 'text-emerald-700 border-emerald-300 dark:text-emerald-400 dark:border-emerald-800',
  'removido': 'text-red-700 border-red-300 dark:text-red-400 dark:border-red-800',
  'alterado': 'text-blue-700 border-blue-300 dark:text-blue-400 dark:border-blue-800',
  'restaurado': 'text-purple-700 border-purple-300 dark:text-purple-400 dark:border-purple-800',
};

const POR_PAGINA = 20;
/** O banco corta em 100 eventos por leitura. */
const LIMITE_MAXIMO = 100;

const SEM_PERMISSAO = 'O histórico é visível só para administrador e financeiro.';

export interface DocumentoDaTimeline {
  status?: string | null;
  invoicing_status?: string | null;
  merged_into_id?: string | null;
}

/** Por que o documento não aceita desfazer/voltar — ou null quando aceita. Espelha a RPC. */
function motivoDeFechado(d: DocumentoDaTimeline | null | undefined): string | null {
  if (!d) return 'situação desconhecida';
  if (d.merged_into_id) return 'Agrupado';
  if (d.status === 'completed' || d.status === 'invoiced' || d.status === 'cancelled') {
    return ROTULOS_STATUS_OS[d.status];
  }
  if (d.invoicing_status === 'invoiced') return 'Faturado';
  return null;
}

type PedidoDeRestauracao =
  | { modo: 'versao'; versao: number }
  | { modo: 'eventos'; ids: string[]; quando: string };

// ── Peças pequenas ──────────────────────────────────────────────────────────────

function LinhaDaMudanca({ m }: { m: MudancaDoHistorico }) {
  return (
    <p className={cn('text-xs break-words [overflow-wrap:anywhere]', m.calculado && 'opacity-70')}>
      <span className="font-medium text-muted-foreground">{m.campo}:</span>{' '}
      {m.antes != null && <span className="text-muted-foreground">{m.antes}</span>}
      {m.antes != null && m.depois != null && <span className="text-muted-foreground"> → </span>}
      {m.depois != null && <span className="font-medium text-foreground">{m.depois}</span>}
      {m.antes == null && m.depois == null && <span className="text-muted-foreground">—</span>}
      {m.calculado && <span className="ml-1 text-[10px] text-muted-foreground">(recalculado)</span>}
    </p>
  );
}

function SemPermissao() {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <Lock className="mb-3 h-10 w-10 text-muted-foreground/40" />
      <p className="text-sm text-muted-foreground">{SEM_PERMISSAO}</p>
    </div>
  );
}

function FalhaNaLeitura({ erro, onTentar, oQue }: { erro: unknown; onTentar: () => void; oQue: string }) {
  if (ehHistoricoSemPermissao(erro)) return <SemPermissao />;
  return (
    <div role="alert" className="rounded-lg border border-destructive/40 bg-destructive/5 p-4 text-sm">
      <p className="flex items-center gap-2 font-medium text-destructive">
        <AlertTriangle className="h-4 w-4 flex-shrink-0" />
        Não foi possível carregar {oQue}.
      </p>
      <p className="mt-1 text-xs text-muted-foreground break-words [overflow-wrap:anywhere]">{mensagemDoErro(erro)}</p>
      <Button size="sm" variant="outline" className="mt-3" onClick={onTentar}>
        <RefreshCw className="mr-1.5 h-3.5 w-3.5" />
        Tentar de novo
      </Button>
    </div>
  );
}

function Carregando() {
  return (
    <div className="space-y-4 py-4 px-1" aria-busy="true" aria-label="Carregando o histórico">
      {[1, 2, 3].map((i) => (
        <div key={i} className="space-y-2 rounded-lg border p-3">
          <Skeleton className="h-4 w-40" />
          <Skeleton className="h-3 w-56" />
          <Skeleton className="h-3 w-32" />
        </div>
      ))}
    </div>
  );
}

function QuadroDeDiferencas({ d }: { d: DiferencasDoDocumento }) {
  if (d.sem_diferenca) {
    return <p className="text-sm text-muted-foreground">Nenhuma diferença: o documento está igual.</p>;
  }
  const qtd = (q: number | string | null) => (q == null || q === '' ? '' : `${q} × `);
  return (
    <div className="space-y-3 text-sm">
      {d.cabecalho.length > 0 && (
        <section>
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Cabeçalho</h4>
          <div className="space-y-0.5">{d.cabecalho.map((m, i) => <LinhaDaMudanca key={i} m={m} />)}</div>
        </section>
      )}
      {d.itens_incluidos.length > 0 && (
        <section>
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-emerald-700 dark:text-emerald-400">Entram</h4>
          <ul className="space-y-0.5">
            {d.itens_incluidos.map((it, i) => (
              <li key={i} className="text-xs break-words [overflow-wrap:anywhere]">
                + {qtd(it.quantidade)}{it.item}{it.total ? ` — ${it.total}` : ''}
              </li>
            ))}
          </ul>
        </section>
      )}
      {d.itens_removidos.length > 0 && (
        <section>
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-red-700 dark:text-red-400">Saem</h4>
          <ul className="space-y-0.5">
            {d.itens_removidos.map((it, i) => (
              <li key={i} className="text-xs break-words [overflow-wrap:anywhere]">
                − {qtd(it.quantidade)}{it.item}{it.total ? ` — ${it.total}` : ''}
              </li>
            ))}
          </ul>
        </section>
      )}
      {d.itens_alterados.length > 0 && (
        <section>
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Mudam</h4>
          <ul className="space-y-1.5">
            {d.itens_alterados.map((it, i) => (
              <li key={i}>
                <p className="text-xs font-medium break-words [overflow-wrap:anywhere]">{it.item}</p>
                <div className="ml-3 space-y-0.5">{it.mudancas.map((m, j) => <LinhaDaMudanca key={j} m={m} />)}</div>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}

// ── Alterações ──────────────────────────────────────────────────────────────────

function ItemDoEventoView({ item }: { item: ItemDoEvento }) {
  return (
    <div className="space-y-1">
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <span className="min-w-0 text-sm font-medium break-words [overflow-wrap:anywhere]">{item.item}</span>
        <Badge variant="outline" className={cn('h-5 py-0 text-[10px] font-semibold', ACAO_COR[item.acao])}>
          {item.acao}
        </Badge>
      </div>
      {item.mudancas.length > 0 && (
        <div className="space-y-0.5 pl-1">{item.mudancas.map((m, i) => <LinhaDaMudanca key={i} m={m} />)}</div>
      )}
      {item.motivo && (
        <p className="text-xs text-muted-foreground break-words [overflow-wrap:anywhere]">
          <span className="font-medium">Motivo:</span> {item.motivo}
        </p>
      )}
    </div>
  );
}

function CartaoDoEvento({
  evento, podeCorrigir, onDesfazer,
}: { evento: EventoDoHistorico; podeCorrigir: boolean; onDesfazer: (ids: string[]) => void }) {
  // Quem diz o que se desfaz é o banco (desfazivel): situação, total recalculado, envio, versão e registro antigo não vão
  // — mandá-los só viraria "fica como está". Evento sem nada desfazível não oferece o "Desfazer".
  const ids = evento.desfazivel
    ? evento.itens.filter((i) => i.desfazivel === true && i.registro_id).map((i) => i.registro_id)
    : [];
  return (
    <li className="rounded-lg border bg-card p-3 shadow-sm" data-testid="evento-do-historico">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 space-y-0.5">
          <p className="text-sm font-semibold tabular-nums">{evento.quando}</p>
          <p className="text-xs text-muted-foreground break-words [overflow-wrap:anywhere]">
            {/* por_onde vem pronto do banco ("tela", "assistente (WhatsApp)", "cliente pelo link"…):
                sem "pela"/"pelo" na frente, que erraria o gênero de metade deles. */}
            por <span className="font-medium text-foreground">{evento.quem}</span> · {evento.por_onde}
          </p>
        </div>
        {podeCorrigir && ids.length > 0 && (
          <AcoesDaLinha
            rotulo={`alteração de ${evento.quando}`}
            menu={[{ texto: 'Desfazer esta alteração', icone: Undo2, onClick: () => onDesfazer(ids) }]}
          />
        )}
      </div>
      <div className="mt-2 space-y-2 border-t pt-2">
        {evento.itens.map((item) => <ItemDoEventoView key={item.registro_id} item={item} />)}
      </div>
    </li>
  );
}

function VisaoAlteracoes({
  orderId, podeCorrigir, onRestaurar,
}: { orderId: string; podeCorrigir: boolean; onRestaurar: (p: PedidoDeRestauracao) => void }) {
  const [limite, setLimite] = useState(POR_PAGINA);
  const { data, error, isLoading, isFetching, refetch } = useHistoricoDocumento({
    tipo: 'os', ref: orderId, modo: 'alteracoes', limite, manterAnterior: true,
  });

  if (isLoading) return <Carregando />;
  if (error || !data) {
    return <FalhaNaLeitura erro={error ?? new Error('sem resposta')} onTentar={() => void refetch()} oQue="o histórico" />;
  }
  if (data.eventos.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center">
        <Clock className="mb-3 h-10 w-10 text-muted-foreground/40" />
        <p className="text-sm text-muted-foreground">Nenhuma alteração registrada ainda.</p>
        <p className="mt-1 text-xs text-muted-foreground/60">
          Alterações neste documento serão registradas aqui automaticamente.
        </p>
      </div>
    );
  }

  const cortado = !!data.aviso || data.total_de_eventos > data.eventos.length;
  return (
    <div className="space-y-4">
      <ol className="space-y-3">
        {data.eventos.map((ev, i) => (
          <CartaoDoEvento
            key={`${ev.quando_iso}-${i}`}
            evento={ev}
            podeCorrigir={podeCorrigir}
            onDesfazer={(ids) => onRestaurar({ modo: 'eventos', ids, quando: ev.quando })}
          />
        ))}
      </ol>
      {cortado && (
        <div className="flex flex-col items-center gap-2 text-center">
          <p className="text-xs text-muted-foreground">
            Mostrando as {data.eventos.length} alterações mais recentes de {data.total_de_eventos}.
          </p>
          {limite < LIMITE_MAXIMO ? (
            <Button
              size="sm"
              variant="outline"
              disabled={isFetching}
              onClick={() => setLimite((l) => Math.min(l + POR_PAGINA, LIMITE_MAXIMO))}
            >
              {isFetching && <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
              Mostrar mais
            </Button>
          ) : (
            <p className="text-xs text-muted-foreground">
              Para as mais antigas, peça ao assistente o histórico de um período.
            </p>
          )}
        </div>
      )}
    </div>
  );
}

// ── Versões ─────────────────────────────────────────────────────────────────────

function LinhaDaVersaoView({
  v, podeCorrigir, onVer, onComparar, onVoltar,
}: {
  v: VersaoDoDocumento; podeCorrigir: boolean;
  onVer: () => void; onComparar: () => void; onVoltar: () => void;
}) {
  const partes = [
    v.situacao,
    v.pecas != null ? `${v.pecas} ${v.pecas === 1 ? 'peça' : 'peças'}` : null,
    v.servicos != null ? `${v.servicos} ${v.servicos === 1 ? 'serviço' : 'serviços'}` : null,
  ].filter(Boolean);
  return (
    <li className="rounded-lg border bg-card p-3 shadow-sm" data-testid="versao-do-documento">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 space-y-0.5">
          <p className="text-sm font-semibold break-words [overflow-wrap:anywhere]">
            Versão {v.versao}
            {v.marco && <span className="font-normal text-muted-foreground"> · {v.marco}</span>}
          </p>
          <p className="text-xs text-muted-foreground break-words [overflow-wrap:anywhere]">
            {v.quando} · {v.quem}
          </p>
          {partes.length > 0 && <p className="text-xs text-muted-foreground">{partes.join(' · ')}</p>}
        </div>
        <div className="flex flex-shrink-0 flex-col items-end gap-1">
          {v.total && <span className="text-sm font-semibold tabular-nums">{v.total}</span>}
          <AcoesDaLinha
            rotulo={`versão ${v.versao}`}
            rapidas={[{ texto: 'Ver', icone: Eye, titulo: 'Ver o conteúdo desta versão', onClick: onVer }]}
            menu={[
              { texto: 'Comparar com o atual', icone: GitCompare, onClick: onComparar },
              ...(podeCorrigir ? [{ texto: 'Voltar para esta versão', icone: RotateCcw, onClick: onVoltar }] : []),
            ]}
          />
        </div>
      </div>
    </li>
  );
}

function VisaoVersoes({
  orderId, podeCorrigir, onRestaurar,
}: { orderId: string; podeCorrigir: boolean; onRestaurar: (p: PedidoDeRestauracao) => void }) {
  const [ver, setVer] = useState<number | null>(null);
  const [comparar, setComparar] = useState<number | null>(null);
  const { data, error, isLoading, refetch } = useHistoricoDocumento({ tipo: 'os', ref: orderId, modo: 'versoes' });

  if (isLoading) return <Carregando />;
  if (error || !data) {
    return <FalhaNaLeitura erro={error ?? new Error('sem resposta')} onTentar={() => void refetch()} oQue="as versões" />;
  }
  if (data.versoes.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center">
        <Clock className="mb-3 h-10 w-10 text-muted-foreground/40" />
        <p className="text-sm text-muted-foreground">Nenhuma versão guardada ainda.</p>
        <p className="mt-1 text-xs text-muted-foreground/60">
          Uma versão é guardada nos marcos do documento (envio ao cliente, aprovação, conclusão).
        </p>
      </div>
    );
  }
  return (
    <>
      <ol className="space-y-3">
        {data.versoes.map((v) => (
          <LinhaDaVersaoView
            key={v.versao}
            v={v}
            podeCorrigir={podeCorrigir}
            onVer={() => setVer(v.versao)}
            onComparar={() => setComparar(v.versao)}
            onVoltar={() => onRestaurar({ modo: 'versao', versao: v.versao })}
          />
        ))}
      </ol>
      <DialogoVerVersao orderId={orderId} versao={ver} onFechar={() => setVer(null)} />
      <DialogoComparar orderId={orderId} versao={comparar} onFechar={() => setComparar(null)} />
    </>
  );
}

function LinhasDaVersao({ titulo, linhas }: { titulo: string; linhas: LinhaDaVersao[] | null }) {
  if (!linhas || linhas.length === 0) return null;
  return (
    <section>
      <h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{titulo}</h4>
      <ul className="space-y-1">
        {linhas.map((l, i) => (
          <li key={i} className="flex items-start justify-between gap-3 text-xs">
            <span className="min-w-0 break-words [overflow-wrap:anywhere]">
              {l.quantidade != null && `${l.quantidade} × `}{l.nome}
              {l.preco_unitario && <span className="text-muted-foreground"> ({l.preco_unitario} cada)</span>}
              {l.desconto && <span className="text-muted-foreground"> · desconto {l.desconto}</span>}
            </span>
            {l.total && <span className="flex-shrink-0 font-medium tabular-nums">{l.total}</span>}
          </li>
        ))}
      </ul>
    </section>
  );
}

function CampoDaVersao({ rotulo, valor }: { rotulo: string; valor: string | null | undefined }) {
  if (!valor) return null;
  return (
    <div>
      <p className="text-xs font-medium text-muted-foreground">{rotulo}</p>
      <p className="text-sm whitespace-pre-line break-words [overflow-wrap:anywhere]">{valor}</p>
    </div>
  );
}

function DialogoVerVersao({ orderId, versao, onFechar }: { orderId: string; versao: number | null; onFechar: () => void }) {
  const aberto = versao != null;
  const { data, error, isLoading, refetch } = useHistoricoDocumento({
    tipo: 'os', ref: orderId, modo: 'ver_versao', versao, enabled: aberto,
  });
  const c = data?.conteudo;
  const totais = c?.totais;
  return (
    <Dialog open={aberto} onOpenChange={(o) => { if (!o) onFechar(); }}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Versão {versao}{data?.marco ? ` · ${data.marco}` : ''}</DialogTitle>
          <DialogDescription>
            {data ? `${data.quando} · ${data.quem}` : 'O documento como estava nesta versão.'}
          </DialogDescription>
        </DialogHeader>
        {aberto && isLoading && <Carregando />}
        {aberto && !isLoading && (error || !data) && (
          <FalhaNaLeitura erro={error ?? new Error('sem resposta')} onTentar={() => void refetch()} oQue="a versão" />
        )}
        {c && (
          <div className="space-y-4">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <CampoDaVersao rotulo="Situação" valor={c.situacao} />
              <CampoDaVersao rotulo="Situação do orçamento" valor={c.situacao_do_orcamento} />
              <CampoDaVersao rotulo="Cliente" valor={c.cliente} />
              <CampoDaVersao rotulo="Embarcação" valor={c.embarcacao} />
              <CampoDaVersao rotulo="Validade" valor={c.validade} />
            </div>
            <CampoDaVersao rotulo="Descrição" valor={c.descricao} />
            <CampoDaVersao rotulo="Relatório ao cliente" valor={c.relatorio_ao_cliente} />
            <CampoDaVersao rotulo="Condições de pagamento" valor={c.condicoes_de_pagamento} />
            <LinhasDaVersao titulo="Serviços" linhas={c.servicos} />
            <LinhasDaVersao titulo="Peças" linhas={c.pecas} />
            {totais && (
              <section className="space-y-0.5 border-t pt-2 text-xs">
                {([
                  ['Mão de obra', totais.mao_de_obra], ['Peças', totais.pecas], ['Deslocamento', totais.deslocamento],
                  ['Desconto', totais.desconto], ['Impostos', totais.impostos],
                ] as const).filter(([, v]) => !!v).map(([r, v]) => (
                  <p key={r} className="flex justify-between gap-3">
                    <span className="text-muted-foreground">{r}</span><span className="tabular-nums">{v}</span>
                  </p>
                ))}
                {totais.total && (
                  <p className="flex justify-between gap-3 text-sm font-semibold">
                    <span>Total</span><span className="tabular-nums">{totais.total}</span>
                  </p>
                )}
              </section>
            )}
            {c.parcelas && c.parcelas.length > 0 && (
              <section>
                <h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Parcelas</h4>
                <ul className="space-y-0.5">
                  {c.parcelas.map((p, i) => (
                    <li key={i} className="flex items-start justify-between gap-3 text-xs">
                      <span className="min-w-0 break-words [overflow-wrap:anywhere]">
                        {p.descricao ?? `Parcela ${i + 1}`}
                        {p.vencimento && <span className="text-muted-foreground"> · vence {p.vencimento}</span>}
                        {p.situacao && <span className="text-muted-foreground"> · {p.situacao}</span>}
                      </span>
                      {p.valor && <span className="flex-shrink-0 tabular-nums">{p.valor}</span>}
                    </li>
                  ))}
                </ul>
              </section>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

function DialogoComparar({ orderId, versao, onFechar }: { orderId: string; versao: number | null; onFechar: () => void }) {
  const aberto = versao != null;
  const { data, error, isLoading, refetch } = useHistoricoDocumento({
    tipo: 'os', ref: orderId, modo: 'comparar', versao, enabled: aberto,
  });
  return (
    <Dialog open={aberto} onOpenChange={(o) => { if (!o) onFechar(); }}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Versão {versao} × estado atual</DialogTitle>
          <DialogDescription>O que mudou da versão {versao} até agora.</DialogDescription>
        </DialogHeader>
        {aberto && isLoading && <Carregando />}
        {aberto && !isLoading && (error || !data) && (
          <FalhaNaLeitura erro={error ?? new Error('sem resposta')} onTentar={() => void refetch()} oQue="a comparação" />
        )}
        {data && <QuadroDeDiferencas d={data.diferencas} />}
      </DialogContent>
    </Dialog>
  );
}

// ── Desfazer / voltar ───────────────────────────────────────────────────────────

/**
 * Desfazer uma alteração ou voltar para uma versão: primeiro SIMULA (o banco faz tudo e desfaz,
 * então o que aparece é exatamente o que vai acontecer), depois confirma com o hash da simulação —
 * se alguém mexeu no documento no meio, o banco recusa e a pessoa confere de novo.
 */
function DialogoRestaurar({
  orderId, pedido, onFechar,
}: { orderId: string; pedido: PedidoDeRestauracao | null; onFechar: () => void }) {
  const simular = useRestaurarDocumento();
  const confirmar = useRestaurarDocumento();
  const [motivo, setMotivo] = useState('');

  const argumentos = pedido
    ? (pedido.modo === 'versao' ? { versao: pedido.versao } : { eventos: pedido.ids })
    : null;

  const rodarSimulacao = () => {
    if (!argumentos) return;
    confirmar.reset();
    simular.mutate({ ref: orderId, idDoDocumento: orderId, ...argumentos, simular: true });
  };

  // Abriu (ou trocou de pedido): simula de novo, do zero.
  useEffect(() => {
    setMotivo('');
    simular.reset();
    confirmar.reset();
    if (pedido) rodarSimulacao();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pedido]);

  const sim: ResultadoDaRestauracao | undefined = simular.data;
  const nada = !!sim?.o_que_muda.sem_diferenca;
  const avisos = sim?.avisos ?? [];

  const aoConfirmar = () => {
    if (!argumentos || !sim) return;
    confirmar.mutate(
      { ref: orderId, idDoDocumento: orderId, ...argumentos, motivo, simular: false, conferirHash: sim.hash_do_documento },
      {
        onSuccess: (r) => {
          if (r.restaurado) {
            toast.success(`${r.documento} restaurado${r.versao_nova ? ` — guardado como versão ${r.versao_nova}` : ''}.`);
          } else {
            toast.info(r.mensagem ?? 'Nada a mudar: o documento já está assim.');
          }
          if (r.aviso_das_parcelas) {
            toast.warning(`O documento foi restaurado, mas as parcelas não foram redistribuídas: ${r.aviso_das_parcelas}`);
          }
          onFechar();
        },
      },
    );
  };

  const titulo = !pedido ? '' : pedido.modo === 'versao'
    ? `Voltar para a versão ${pedido.versao}`
    : `Desfazer a alteração de ${pedido.quando}`;

  return (
    <Dialog open={!!pedido} onOpenChange={(o) => { if (!o && !confirmar.isPending) onFechar(); }}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{titulo}</DialogTitle>
          <DialogDescription>Confira o que muda antes de confirmar. Nada foi alterado ainda.</DialogDescription>
        </DialogHeader>

        {simular.isPending && (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Calculando o que muda…
          </p>
        )}

        {simular.isError && (
          <div role="alert" className="rounded-lg border border-destructive/40 bg-destructive/5 p-3 text-sm">
            <p className="font-medium text-destructive">Não foi possível preparar a restauração.</p>
            <p className="mt-1 text-xs text-muted-foreground break-words [overflow-wrap:anywhere]">{mensagemDoErro(simular.error)}</p>
            <Button size="sm" variant="outline" className="mt-2" onClick={rodarSimulacao}>
              <RefreshCw className="mr-1.5 h-3.5 w-3.5" /> Tentar de novo
            </Button>
          </div>
        )}

        {sim && (
          <div className="space-y-4">
            {nada
              ? <p className="text-sm text-muted-foreground">{sim.mensagem || 'Nada a mudar: o documento já está assim.'}</p>
              : <QuadroDeDiferencas d={sim.o_que_muda} />}
            {!nada && sim.mensagem && <p className="text-sm text-muted-foreground">{sim.mensagem}</p>}

            {avisos.length > 0 && (
              <section
                role="alert"
                data-testid="avisos-da-restauracao"
                className="rounded-md border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-200"
              >
                <p className="mb-1 flex items-center gap-1.5 font-semibold">
                  <AlertTriangle className="h-3.5 w-3.5 flex-shrink-0" /> Atenção
                </p>
                <ul className="space-y-0.5">
                  {avisos.map((a, i) => (
                    <li key={i} className="break-words [overflow-wrap:anywhere]">
                      <span className="font-medium">{a.item}:</span> {a.aviso}
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {sim.total_antes !== sim.total_depois && (
              <p className="text-sm">
                <span className="font-medium">Total:</span>{' '}
                <span className="text-muted-foreground tabular-nums">{sim.total_antes ?? '—'}</span>
                {' → '}
                <span className="font-semibold tabular-nums">{sim.total_depois ?? '—'}</span>
              </p>
            )}

            {sim.pede_nova_assinatura && (
              <p className="flex items-start gap-2 rounded-md border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-200">
                <AlertTriangle className="mt-0.5 h-3.5 w-3.5 flex-shrink-0" />
                O cliente já assinou este documento: depois de restaurar, ele volta a pedir a assinatura.
              </p>
            )}

            {sim.nao_desfeito.length > 0 && (
              <section>
                <h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Fica como está</h4>
                <ul className="space-y-0.5">
                  {sim.nao_desfeito.map((n, i) => (
                    <li key={i} className="text-xs break-words [overflow-wrap:anywhere]">
                      <span className="font-medium">{n.item}{n.campo ? ` — ${n.campo}` : ''}:</span> {n.motivo}
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {!nada && (
              <div className="space-y-1.5">
                <Label htmlFor="motivo-da-restauracao">Motivo (opcional)</Label>
                <Textarea
                  id="motivo-da-restauracao"
                  value={motivo}
                  onChange={(e) => setMotivo(e.target.value)}
                  maxLength={400}
                  rows={2}
                  placeholder="Ex.: o cliente pediu de volta o orçamento enviado"
                />
              </div>
            )}

            {confirmar.isError && (
              <div role="alert" className="rounded-lg border border-destructive/40 bg-destructive/5 p-3 text-sm">
                <p className="font-medium text-destructive">A restauração não foi feita.</p>
                <p className="mt-1 text-xs text-muted-foreground break-words [overflow-wrap:anywhere]">{mensagemDoErro(confirmar.error)}</p>
                <Button size="sm" variant="outline" className="mt-2" onClick={rodarSimulacao}>
                  <RefreshCw className="mr-1.5 h-3.5 w-3.5" /> Conferir de novo
                </Button>
              </div>
            )}
          </div>
        )}

        <DialogFooter className="gap-2 sm:gap-0">
          <Button variant="outline" onClick={onFechar} disabled={confirmar.isPending}>Voltar</Button>
          <Button onClick={aoConfirmar} disabled={!sim || nada || simular.isPending || confirmar.isPending}>
            {confirmar.isPending && <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
            {pedido?.modo === 'versao' ? 'Voltar para esta versão' : 'Desfazer'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ── Principal ───────────────────────────────────────────────────────────────────

export function ServiceOrderTimeline({
  orderId, documento,
}: {
  orderId: string | undefined;
  /** Situação do documento: desfazer/voltar só aparecem com ele aberto. Sem isto, ficam escondidos. */
  documento?: DocumentoDaTimeline | null;
}) {
  const papel = useOptionalAuth()?.user?.role;
  const [pedido, setPedido] = useState<PedidoDeRestauracao | null>(null);

  // Sem papel ainda (perfil carregando, teste sem AuthProvider) quem decide é o banco (42501).
  const cargoLe = !papel || papel === 'admin' || papel === 'financial';
  const cargoCorrige = papel === 'admin' || papel === 'financial';
  const fechado = motivoDeFechado(documento);
  const podeCorrigir = cargoCorrige && !fechado;

  if (!orderId) return null;
  if (!cargoLe) return <SemPermissao />;

  return (
    <div className="space-y-4">
      {cargoCorrige && fechado && documento && (
        <p className="text-xs text-muted-foreground">
          {fechado}: desfazer e voltar versão só valem para documento em aberto.
        </p>
      )}
      <Tabs defaultValue="alteracoes">
        <TabsList className="grid w-full grid-cols-2 sm:inline-grid sm:w-auto">
          <TabsTrigger value="alteracoes">Alterações</TabsTrigger>
          <TabsTrigger value="versoes">Versões</TabsTrigger>
        </TabsList>
        <TabsContent value="alteracoes" className="mt-4">
          <VisaoAlteracoes orderId={orderId} podeCorrigir={podeCorrigir} onRestaurar={setPedido} />
        </TabsContent>
        <TabsContent value="versoes" className="mt-4">
          <VisaoVersoes orderId={orderId} podeCorrigir={podeCorrigir} onRestaurar={setPedido} />
        </TabsContent>
      </Tabs>
      <DialogoRestaurar orderId={orderId} pedido={podeCorrigir ? pedido : null} onFechar={() => setPedido(null)} />
    </div>
  );
}
