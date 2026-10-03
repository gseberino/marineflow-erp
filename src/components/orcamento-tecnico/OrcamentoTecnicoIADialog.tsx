// Orçamento técnico com IA (03/10/2026). O admin descreve o serviço; o banco monta o pacote de dados
// (catálogo, custos, orçamentos recentes, margem praticada) e a fila ai_jobs leva ao Claude da
// assinatura do dono (HBR AI Gateway). A proposta volta aqui; só vira rascunho de orçamento por clique.
import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { AlertTriangle, ExternalLink, Loader2, RotateCcw, Sparkles } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { ClientCombobox } from '@/components/ClientCombobox';
import { VesselSelect } from '@/components/VesselSelect';
import { useClients } from '@/hooks/use-clients';
import { useVessels } from '@/hooks/use-vessels';
import {
  useCancelarPedidoDeOrcamentoTecnico,
  useCriarRascunhoDoOrcamentoTecnico,
  useJobDeOrcamentoTecnico,
  usePedidosDeOrcamentoTecnico,
  useSolicitarOrcamentoTecnico,
  type ModeloDoOrcamento,
} from '@/hooks/use-orcamento-tecnico-ia';
import {
  conferirContas,
  duracaoLegivel,
  estadoDoPedido,
  lerProposta,
  motivoDaFalha,
  rascunhosCriados,
  type OrcamentoDaProposta,
} from '@/lib/orcamento-tecnico-ia';
import { formatCurrency } from '@/lib/constants';

const MIN_CARACTERES = 15;

const MODELOS: Array<{ valor: ModeloDoOrcamento; rotulo: string; detalhe: string }> = [
  { valor: 'opus', rotulo: 'Opus', detalhe: 'mais caprichado · 3 a 5 min' },
  { valor: 'sonnet', rotulo: 'Sonnet', detalhe: 'mais rápido · 1 a 3 min' },
];

const ROTULO_DO_STATUS: Record<string, string> = {
  pending: 'na fila',
  processing: 'montando',
  completed: 'pronta',
  failed: 'falhou',
  cancelled: 'cancelado',
};

const dataCurta = (iso: string) =>
  new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

interface Props {
  aberto: boolean;
  onFechar: () => void;
}

export function OrcamentoTecnicoIADialog({ aberto, onFechar }: Props) {
  const navigate = useNavigate();
  const [jobId, setJobId] = useState<string | null>(null);
  const [pedido, setPedido] = useState('');
  const [modelo, setModelo] = useState<ModeloDoOrcamento>('opus');
  const [indice, setIndice] = useState(0);
  const [clienteId, setClienteId] = useState('');
  const [ativoId, setAtivoId] = useState('');
  const [agora, setAgora] = useState(() => Date.now());

  const solicitar = useSolicitarOrcamentoTecnico();
  const criar = useCriarRascunhoDoOrcamentoTecnico();
  const cancelar = useCancelarPedidoDeOrcamentoTecnico();
  const recentes = usePedidosDeOrcamentoTecnico(aberto && !jobId);
  const job = useJobDeOrcamentoTecnico(aberto ? jobId : null);
  const { data: clientes } = useClients();
  const { data: ativos } = useVessels();

  const estado = job.data ? estadoDoPedido(job.data) : null;
  const proposta = useMemo(() => (job.data ? lerProposta(job.data.response) : null), [job.data]);
  const criados = useMemo(() => rascunhosCriados(job.data?.metadata), [job.data]);
  const ativosDoCliente = useMemo(() => (ativos ?? []).filter((v) => v.client_id === clienteId), [ativos, clienteId]);
  const orcamento: OrcamentoDaProposta | undefined = proposta?.orcamentos[Math.min(indice, (proposta?.orcamentos.length ?? 1) - 1)];
  const avisosDeConta = useMemo(() => (orcamento ? conferirContas(orcamento) : []), [orcamento]);
  const rodando = estado === 'na_fila' || estado === 'montando';

  // Relógio da espera.
  useEffect(() => {
    if (!rodando) return;
    const t = setInterval(() => setAgora(Date.now()), 1000);
    return () => clearInterval(t);
  }, [rodando]);

  // Cliente com um ativo só: escolhe sozinho, como o formulário de OS.
  useEffect(() => {
    if (clienteId && ativosDoCliente.length === 1 && !ativoId) setAtivoId(ativosDoCliente[0]!.id);
  }, [clienteId, ativosDoCliente, ativoId]);

  const novoPedido = () => {
    setJobId(null);
    setIndice(0);
  };

  const enviar = () => {
    solicitar.mutate(
      { pedido: pedido.trim(), modelo },
      {
        onSuccess: (id) => {
          setJobId(id);
          setIndice(0);
        },
      },
    );
  };

  const criarRascunho = () => {
    if (!jobId) return;
    criar.mutate(
      { jobId, indice, clienteId, ativoId },
      {
        onSuccess: (r) => {
          toast.success(
            r.ja_existia
              ? `Este orçamento já tinha virado o rascunho ${r.numero}.`
              : `Rascunho ${r.numero} criado com ${r.pecas ?? 0} peça(s) e ${r.servicos ?? 0} serviço(s).`,
          );
          onFechar();
          navigate(`/v2/service-orders/${r.service_order_id}`);
        },
      },
    );
  };

  const desdeQuando = job.data ? Date.parse(job.data.started_at ?? job.data.created_at) : agora;
  const rascunhoDeste = criados[indice];

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-h-[92vh] w-[calc(100vw-2rem)] max-w-4xl overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Sparkles className="h-5 w-5 text-primary" /> Orçamento técnico com IA
          </DialogTitle>
          <DialogDescription>
            O Claude monta a proposta com o catálogo, os custos e os orçamentos da HBR. Nada é gravado no ERP até você
            criar o rascunho.
          </DialogDescription>
        </DialogHeader>

        {/* 1. Pedido */}
        {!jobId && (
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="pedido-orcamento-ia">O que precisa ser orçado?</Label>
              <Textarea
                id="pedido-orcamento-ia"
                rows={7}
                value={pedido}
                onChange={(e) => setPedido(e.target.value)}
                placeholder="Ex.: Troca do sistema elétrico de um motorhome por LiFePO4 12 V, sem baterias: inversor/carregador 3000 W, DC/DC, controlador solar, monitor, proteções, cabos e mão de obra. Dois orçamentos: Victron e Usina."
              />
              <p className="text-xs text-muted-foreground">
                Quanto mais detalhe (equipamentos, distâncias, o que incluir ou não), melhor a proposta.
              </p>
            </div>

            <div className="space-y-1.5">
              <Label>Modelo</Label>
              <div className="flex flex-wrap gap-2">
                {MODELOS.map((m) => (
                  <Button
                    key={m.valor}
                    type="button"
                    variant={modelo === m.valor ? 'default' : 'outline'}
                    aria-pressed={modelo === m.valor}
                    onClick={() => setModelo(m.valor)}
                    className="h-auto flex-col items-start px-3 py-1.5"
                  >
                    <span className="font-medium">{m.rotulo}</span>
                    <span className="text-xs opacity-80">{m.detalhe}</span>
                  </Button>
                ))}
              </div>
            </div>

            <div className="flex justify-end">
              <Button onClick={enviar} disabled={pedido.trim().length < MIN_CARACTERES || solicitar.isPending} className="gap-1.5">
                {solicitar.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Sparkles className="h-4 w-4" />}
                Gerar proposta
              </Button>
            </div>

            {(recentes.data?.length ?? 0) > 0 && (
              <div className="space-y-1.5 border-t pt-3">
                <p className="text-sm font-medium">Pedidos recentes</p>
                <ul className="space-y-1">
                  {recentes.data!.map((r) => (
                    <li key={r.id} className="flex items-center gap-2 rounded-md border px-2 py-1.5 text-sm">
                      <span className="shrink-0 text-xs text-muted-foreground">{dataCurta(r.created_at)}</span>
                      <Badge variant={r.status === 'completed' ? 'default' : r.status === 'failed' ? 'destructive' : 'secondary'} className="shrink-0">
                        {ROTULO_DO_STATUS[r.status] ?? r.status}
                      </Badge>
                      <span className="min-w-0 flex-1 truncate" title={r.prompt}>{r.prompt}</span>
                      <Button size="sm" variant="ghost" onClick={() => setJobId(r.id)} aria-label={`Abrir o pedido de ${dataCurta(r.created_at)}`}>
                        Abrir
                      </Button>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}

        {/* 2. Carregando o pedido escolhido */}
        {jobId && !job.data && (
          <div className="flex items-center gap-2 py-8 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Carregando o pedido…
          </div>
        )}

        {/* 3. Na fila / montando */}
        {jobId && job.data && rodando && (
          <div className="space-y-4 py-4">
            <div className="flex items-center gap-3">
              <Loader2 className="h-6 w-6 shrink-0 animate-spin text-primary" />
              <div>
                <p className="font-medium">
                  {estado === 'na_fila' ? 'Na fila do gateway…' : 'O Claude está montando a proposta…'}
                </p>
                <p className="text-sm text-muted-foreground">
                  {duracaoLegivel(agora - desdeQuando)} · modelo {job.data.model}
                </p>
              </div>
            </div>
            <p className="text-sm text-muted-foreground">
              Pode fechar esta janela: a proposta fica guardada em "Pedidos recentes".
            </p>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => cancelar.mutate(jobId)} disabled={cancelar.isPending}>
                Cancelar pedido
              </Button>
            </div>
          </div>
        )}

        {/* 4. Falhou / cancelado / formato inesperado */}
        {jobId && job.data && !rodando && (estado !== 'pronta' || !proposta) && (
          <div className="space-y-4 py-4">
            <div className="flex items-start gap-2 rounded-md border border-destructive/40 p-3 text-sm">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-destructive" />
              <span className="min-w-0 break-words">
                {estado === 'pronta' ? 'A resposta veio num formato inesperado.' : motivoDaFalha(job.data)}
              </span>
            </div>
            <Button variant="outline" onClick={novoPedido} className="gap-1.5">
              <RotateCcw className="h-4 w-4" /> Novo pedido
            </Button>
          </div>
        )}

        {/* 5. Proposta pronta */}
        {jobId && job.data && estado === 'pronta' && proposta && orcamento && (
          <div className="min-w-0 space-y-4">
            <p className="text-xs text-muted-foreground">
              Montada em {duracaoLegivel(job.data.duration_ms ?? 0)} pelo {job.data.model_used ?? job.data.model}.
            </p>

            {proposta.orcamentos.length > 1 && (
              <div className="flex flex-wrap gap-2" role="tablist" aria-label="Orçamentos da proposta">
                {proposta.orcamentos.map((o, i) => (
                  <Button
                    key={i}
                    role="tab"
                    aria-selected={i === indice}
                    variant={i === indice ? 'default' : 'outline'}
                    size="sm"
                    onClick={() => setIndice(i)}
                  >
                    Orçamento {i + 1} · {formatCurrency(o.resumo.totalGeral)}
                  </Button>
                ))}
              </div>
            )}

            <div className="space-y-3">
              <h3 className="break-words font-semibold">{orcamento.titulo}</h3>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                <Resumo rotulo="Custo estimado" valor={orcamento.resumo.custoEstimado} />
                <Resumo rotulo="Materiais e equipamentos" valor={orcamento.resumo.totalMateriaisEEquipamentos} />
                <Resumo rotulo="Mão de obra" valor={orcamento.resumo.totalMaoDeObra} />
                <Resumo rotulo="Total" valor={orcamento.resumo.totalGeral} destaque />
              </div>
              {proposta.margem && (
                <p className="break-words text-xs text-muted-foreground">
                  Margem: markup {proposta.margem.markup.toLocaleString('pt-BR')} — {proposta.margem.criterio}
                </p>
              )}
            </div>

            {avisosDeConta.length > 0 && (
              <div className="flex items-start gap-2 rounded-md border border-amber-500/50 p-3 text-sm">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
                <ul className="min-w-0 space-y-0.5 break-words">
                  {avisosDeConta.map((a) => <li key={a}>{a}</li>)}
                  <li className="text-muted-foreground">O rascunho recalcula os totais pelas linhas.</li>
                </ul>
              </div>
            )}

            <ul className="divide-y rounded-md border" aria-label="Itens do orçamento">
              {orcamento.itens.map((it, i) => (
                <li key={i} className="grid grid-cols-[minmax(0,1fr)_auto] gap-x-3 gap-y-0.5 px-3 py-2 text-sm">
                  <div className="min-w-0">
                    <div className="break-words">
                      {it.descricao}
                      {it.provisorio && <Badge variant="outline" className="ml-2 border-amber-500 text-amber-700">Provisório</Badge>}
                      {it.tipo === 'mao_de_obra' && <Badge variant="secondary" className="ml-2">Mão de obra</Badge>}
                    </div>
                    <p className="break-words text-xs text-muted-foreground">
                      {it.origemDoCusto}
                      {it.dataDoCusto ? ` · ${it.dataDoCusto}` : ''}
                      {it.custoUnitario > 0 ? ` · custo ${formatCurrency(it.custoUnitario)}` : ''}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="whitespace-nowrap font-medium">{formatCurrency(it.totalVenda)}</p>
                    <p className="whitespace-nowrap text-xs text-muted-foreground">
                      {it.quantidade.toLocaleString('pt-BR')} {it.unidade} × {formatCurrency(it.precoVendaUnitario)}
                    </p>
                  </div>
                </li>
              ))}
            </ul>

            <Lista titulo="Valores provisórios" itens={orcamento.observacoesProvisorias} />
            <Lista titulo="Perguntas pendentes" itens={proposta.perguntasPendentes} />
            <Lista titulo="Premissas técnicas" itens={proposta.premissas} />

            <div className="space-y-3 rounded-md border bg-muted/30 p-3">
              {rascunhoDeste ? (
                <div className="flex flex-wrap items-center gap-2 text-sm">
                  <span>Este orçamento já virou rascunho.</span>
                  <Button size="sm" variant="outline" className="gap-1.5" onClick={() => { onFechar(); navigate(`/v2/service-orders/${rascunhoDeste}`); }}>
                    <ExternalLink className="h-4 w-4" /> Abrir o rascunho
                  </Button>
                </div>
              ) : (
                <>
                  <p className="text-sm font-medium">Criar rascunho de orçamento</p>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <div className="min-w-0 space-y-1.5">
                      <Label>Cliente</Label>
                      <ClientCombobox
                        value={clienteId}
                        clients={clientes}
                        onChange={(id) => {
                          setClienteId(id);
                          setAtivoId('');
                        }}
                      />
                    </div>
                    <div className="min-w-0 space-y-1.5">
                      <Label>Embarcação / ativo</Label>
                      <VesselSelect
                        value={ativoId}
                        clientId={clienteId}
                        vessels={ativosDoCliente}
                        disabled={!clienteId}
                        onChange={setAtivoId}
                        onVesselCreated={(v) => setAtivoId(v.id)}
                      />
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    Itens fora do catálogo entram como produto pendente; nada vai ao cliente até você revisar e enviar.
                  </p>
                  <div className="flex flex-wrap justify-end gap-2">
                    <Button variant="outline" onClick={novoPedido} className="gap-1.5">
                      <RotateCcw className="h-4 w-4" /> Novo pedido
                    </Button>
                    <Button onClick={criarRascunho} disabled={!clienteId || !ativoId || criar.isPending} className="gap-1.5">
                      {criar.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                      Criar rascunho deste orçamento
                    </Button>
                  </div>
                </>
              )}
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

function Resumo({ rotulo, valor, destaque }: { rotulo: string; valor: number; destaque?: boolean }) {
  return (
    <div className="min-w-0 rounded-md border p-2">
      <p className="truncate text-xs text-muted-foreground">{rotulo}</p>
      <p className={destaque ? 'text-base font-semibold' : 'text-sm font-medium'}>{formatCurrency(valor)}</p>
    </div>
  );
}

function Lista({ titulo, itens }: { titulo: string; itens: string[] }) {
  if (!itens.length) return null;
  return (
    <div className="space-y-1">
      <p className="text-sm font-medium">{titulo}</p>
      <ul className="list-disc space-y-0.5 pl-5 text-sm text-muted-foreground">
        {itens.map((t, i) => <li key={i} className="break-words">{t}</li>)}
      </ul>
    </div>
  );
}
