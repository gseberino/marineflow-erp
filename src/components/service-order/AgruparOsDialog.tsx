// Agrupar ORDENS DE SERVIÇO (28/10/2026). O cliente pede que várias OS que ainda não começaram virem UMA: as
// escolhidas (mesmo cliente, mesma embarcação) viram uma OS nova, com os preços que já tinham, e o dinheiro,
// as tarefas manuais e as compras delas vão junto. O banco (agrupar_os) valida tudo e grava numa transação
// só; esta janela só mostra o que vai acontecer — inclusive quanto dinheiro muda de OS.
// Janela própria, não um "modo" da de orçamentos: a prévia aqui tem o dinheiro, as tarefas, as compras e as
// assinaturas, que orçamento não tem; o que é igual (soma, principal, diferenças) vem da mesma lib.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { AlertTriangle, Layers, Loader2 } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { useAgruparOs, useCandidatasOsParaAgrupar, useLeituraOsParaAgrupar, usePreviaDoAgrupamentoOs } from '@/hooks/use-agrupar-os';
import { PO_STATUS_LABELS, type POStatus } from '@/hooks/use-purchase-orders';
import {
  MAX_AGRUPAR,
  MIN_AGRUPAR,
  avisosDaOsNova,
  diferencasEntreOs,
  emReais,
  motivoForaDoAgrupamentoOs,
  principalPadrao,
  resumoDosRecebiveis,
  rotuloDoRecebivel,
  somaDosTotais,
  type CandidataOs,
} from '@/lib/agrupar-os';
import { ehFeminino, rotuloDaUnidade, type UnidadeResumo } from '@/lib/unidade';

interface Props {
  aberto: boolean;
  onFechar: () => void;
  clientId: string;
  vesselId: string;
  /** A unidade (vesselId), para o texto dizer "do mesmo motorhome"; sem ela, o termo geral. */
  unidade?: UnidadeResumo | null;
  preSelecionados: string[];
  principalSugerido?: string;
}

const dataCurta = (iso: string) => new Date(iso).toLocaleDateString('pt-BR');

export function AgruparOsDialog({ aberto, onFechar, clientId, vesselId, unidade, preSelecionados, principalSugerido }: Props) {
  const navigate = useNavigate();
  const tipo = rotuloDaUnidade(unidade?.asset_type).toLowerCase();
  const feminino = ehFeminino(unidade?.asset_type);
  const candidatas = useCandidatasOsParaAgrupar({ clientId, vesselId, enabled: aberto });
  const agrupar = useAgruparOs();

  const [selecionadas, setSelecionadas] = useState<string[]>(preSelecionados);
  const [principal, setPrincipal] = useState(principalSugerido ?? '');
  const [erro, setErro] = useState<string | null>(null);
  // Trava o clique duplo antes mesmo de o isPending chegar à tela (dois cliques no mesmo quadro).
  const enviando = useRef(false);

  const chaveDosPre = preSelecionados.join('|');
  useEffect(() => {
    if (!aberto) return;
    setSelecionadas(chaveDosPre ? chaveDosPre.split('|') : []);
    setPrincipal(principalSugerido ?? '');
    setErro(null);
  }, [aberto, chaveDosPre, principalSugerido]);

  const lista = useMemo(() => candidatas.data ?? [], [candidatas.data]);
  // O banco diz, OS por OS, o que só ele enxerga (nota, comissão, hora apontada, foto…), com a frase dele.
  const banco = useLeituraOsParaAgrupar({
    clientId, vesselId, incluir: lista.map((c) => c.id), enabled: aberto && lista.length > 0,
  });
  const fraseDoBanco = useCallback(
    (c: CandidataOs): string | null => {
      const b = banco.data?.get(c.id);
      return b && !b.elegivel ? (b.motivo ?? 'O banco não aceita esta OS no agrupamento.') : null;
    },
    [banco.data],
  );
  const motivoDe = useCallback(
    (c: CandidataOs): string | null => motivoForaDoAgrupamentoOs(c) ?? (fraseDoBanco(c) ? 'Não entra' : null),
    [fraseDoBanco],
  );
  const escolhidas = useMemo(
    () => lista.filter((c) => selecionadas.includes(c.id) && !motivoDe(c)),
    [lista, selecionadas, motivoDe],
  );
  const idsEscolhidos = useMemo(() => escolhidas.map((c) => c.id), [escolhidas]);
  const previa = usePreviaDoAgrupamentoOs(idsEscolhidos, aberto && escolhidas.length >= MIN_AGRUPAR);
  const numeroPorId = useMemo(() => new Map(lista.map((c) => [c.id, c.service_order_number])), [lista]);

  const principalEfetivo = escolhidas.some((c) => c.id === principal) ? principal : principalPadrao(escolhidas);
  const numeroDoPrincipal = escolhidas.find((c) => c.id === principalEfetivo)?.service_order_number ?? '';
  const total = somaDosTotais(escolhidas);
  const avisos = useMemo(
    () => [...diferencasEntreOs(escolhidas), ...avisosDaOsNova(escolhidas, principalEfetivo)],
    [escolhidas, principalEfetivo],
  );
  const n = escolhidas.length;
  const foraDoLimite = n < MIN_AGRUPAR || n > MAX_AGRUPAR;
  const ocupado = agrupar.isPending;
  // A lista está sendo relida (ao abrir ou depois de uma recusa): o total na tela pode ser o velho, e é ele
  // que vai como p_total_esperado. Espera chegar.
  const relendo = !!candidatas.isFetching;
  const ausentes = candidatas.data
    ? chaveDosPre.split('|').filter((id) => id && !lista.some((c) => c.id === id)).length
    : 0;

  const recebiveis = previa.data?.recebiveis ?? [];
  const dinheiro = resumoDosRecebiveis(recebiveis);
  const tarefas = previa.data?.tarefas ?? [];
  const compras = previa.data?.compras ?? [];

  const alternar = (id: string, marcar: boolean) => {
    setErro(null);
    setSelecionadas((atual) => (marcar ? (atual.includes(id) ? atual : [...atual, id]) : atual.filter((x) => x !== id)));
  };

  const confirmar = () => {
    if (enviando.current || foraDoLimite || ocupado || relendo) return;
    enviando.current = true;
    setErro(null);
    agrupar.mutate(
      { p_os: idsEscolhidos, p_base: principalEfetivo, p_total_esperado: total },
      {
        onSuccess: (r) => {
          const doBanco = (r.avisos ?? []).filter(Boolean);
          toast.success(
            `Criada ${r.numero}: reúne ${r.origens.join(', ')}`,
            doBanco.length ? { description: doBanco.join(' ') } : undefined,
          );
          onFechar();
          navigate(`/v2/service-orders/${r.service_order_id}`);
        },
        onError: (e) => {
          setErro(e.message);
          toast.error(e.message);
        },
        onSettled: () => {
          enviando.current = false;
        },
      },
    );
  };

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && !ocupado && onFechar()}>
      <DialogContent className="max-h-[92dvh] w-[calc(100vw-2rem)] max-w-2xl overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Layers className="h-5 w-5 text-primary" /> Agrupar OS
          </DialogTitle>
          <DialogDescription>
            As OS escolhidas viram uma OS nova, do mesmo cliente e {feminino ? 'da mesma' : 'do mesmo'} {tipo}. Só entram
            OS que ainda não começaram a ser executadas.
          </DialogDescription>
        </DialogHeader>

        {candidatas.isLoading && (
          <div className="flex items-center gap-2 py-6 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Carregando as OS…
          </div>
        )}

        {candidatas.error && (
          <p role="alert" className="rounded-md border border-destructive/40 p-3 text-sm text-destructive">
            Não foi possível carregar as OS: {candidatas.error.message}
          </p>
        )}

        {candidatas.data && lista.length === 0 && (
          <p className="py-4 text-sm text-muted-foreground">
            Nenhuma OS em aberto deste cliente e {feminino ? 'desta' : 'deste'} {tipo}.
          </p>
        )}

        {lista.length > 0 && (
          <div className="min-w-0 space-y-4">
            <ul className="divide-y rounded-md border" aria-label="OS em aberto do cliente">
              {lista.map((c) => {
                const motivo = motivoDe(c);
                const frase = motivoForaDoAgrupamentoOs(c) ? null : fraseDoBanco(c);
                const marcada = !motivo && selecionadas.includes(c.id);
                return (
                  <li key={c.id} className="flex items-start gap-3 px-3 py-2 text-sm">
                    <Checkbox
                      id={`agrupar-os-${c.id}`}
                      className="mt-0.5"
                      checked={marcada}
                      disabled={!!motivo || ocupado}
                      onCheckedChange={(v) => alternar(c.id, v === true)}
                      aria-label={`Incluir ${c.service_order_number}`}
                      aria-describedby={motivo ? `agrupar-os-motivo-${c.id}${frase ? ` agrupar-os-frase-${c.id}` : ''}` : undefined}
                    />
                    <label htmlFor={`agrupar-os-${c.id}`} className={`min-w-0 flex-1 ${motivo ? 'text-muted-foreground' : 'cursor-pointer'}`}>
                      <span className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                        <span className="font-medium">{c.service_order_number}</span>
                        <span className="text-xs text-muted-foreground">{dataCurta(c.created_at)}</span>
                        {c.signed_at && !motivo && <Badge variant="secondary">Assinada</Badge>}
                        {motivo && <Badge id={`agrupar-os-motivo-${c.id}`} variant="outline">{motivo}</Badge>}
                      </span>
                      {c.problem_description && (
                        <span className="block truncate text-xs text-muted-foreground" title={c.problem_description}>
                          {c.problem_description}
                        </span>
                      )}
                      {frase && (
                        <span id={`agrupar-os-frase-${c.id}`} className="mt-0.5 block break-words text-xs text-foreground/80">
                          {frase}
                        </span>
                      )}
                    </label>
                    <span className="whitespace-nowrap font-medium">{emReais(Number(c.grand_total) || 0)}</span>
                  </li>
                );
              })}
            </ul>

            {ausentes > 0 && (
              <p className="text-xs text-muted-foreground">
                {ausentes === 1
                  ? '1 OS escolhida não está mais em aberto (começou, foi cancelada ou já foi agrupada) e ficou de fora.'
                  : `${ausentes} OS escolhidas não estão mais em aberto (começaram, foram canceladas ou já foram agrupadas) e ficaram de fora.`}
              </p>
            )}

            {n > 0 && (
              <div className="space-y-1.5">
                <Label>OS principal</Label>
                <p className="text-xs text-muted-foreground">Dela vêm a condição de pagamento, o contato e a comissão.</p>
                <RadioGroup
                  value={principalEfetivo}
                  onValueChange={setPrincipal}
                  className="flex flex-wrap gap-x-4 gap-y-2"
                  aria-label="OS principal"
                >
                  {escolhidas.map((c) => (
                    <div key={c.id} className="flex items-center gap-2">
                      <RadioGroupItem value={c.id} id={`principal-os-${c.id}`} disabled={ocupado} />
                      <Label htmlFor={`principal-os-${c.id}`} className="cursor-pointer font-normal">
                        {c.service_order_number}
                      </Label>
                    </div>
                  ))}
                </RadioGroup>
              </div>
            )}

            <div className="space-y-2 rounded-md border bg-muted/30 p-3 text-sm">
              <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                <span>{n === 1 ? '1 OS selecionada' : `${n} OS selecionadas`}</span>
                <span className="font-semibold">Total previsto: {emReais(total)}</span>
              </div>
              {n > MAX_AGRUPAR && <p className="text-destructive">Agrupe no máximo {MAX_AGRUPAR} OS de uma vez.</p>}
              {n < MIN_AGRUPAR && <p className="text-muted-foreground">Escolha pelo menos {MIN_AGRUPAR} OS.</p>}
              <ul className="list-disc space-y-1 pl-5 text-muted-foreground">
                <li>Preços mantidos: cada item entra com o preço que tem hoje na sua OS. Os técnicos de todas vão juntos.</li>
                <li>
                  Condição de pagamento, contato e comissão vêm da principal{numeroDoPrincipal ? ` (${numeroDoPrincipal})` : ''};
                  a comissão é recalculada sobre o total novo.
                </li>
                <li>
                  As escolhidas ficam canceladas como histórico e o link antigo delas para de funcionar. Dá para
                  desagrupar enquanto a OS nova não começar a ser executada; o que for acrescentado nela depois não
                  volta para as originais.
                </li>
              </ul>
            </div>

            {n >= MIN_AGRUPAR && (
              <div className="space-y-2 rounded-md border p-3 text-sm" aria-label="O que vai junto para a OS nova" role="group">
                <p className="font-medium">Vai junto para a OS nova</p>
                {previa.isLoading && (
                  <p className="flex items-center gap-2 text-muted-foreground">
                    <Loader2 className="h-4 w-4 animate-spin" /> Conferindo dinheiro, tarefas e compras…
                  </p>
                )}
                {previa.error && (
                  <p className="text-destructive">
                    Não deu para conferir o que vai junto ({previa.error.message}). O agrupamento leva tudo do mesmo jeito.
                  </p>
                )}
                {previa.data && (
                  <>
                    {recebiveis.length === 0 ? (
                      <p className="text-muted-foreground">Nenhum sinal ou conta a receber nestas OS.</p>
                    ) : (
                      <div className="space-y-1">
                        <p>
                          {dinheiro.quantidade === 1 ? '1 conta a receber' : `${dinheiro.quantidade} contas a receber`}:{' '}
                          {emReais(dinheiro.total)}, das quais {emReais(dinheiro.recebido)} já recebidos e{' '}
                          {emReais(dinheiro.emAberto)} em aberto. Valores e situação não mudam; só passam a ser da OS nova.
                        </p>
                        <ul className="list-disc space-y-0.5 pl-5 text-muted-foreground" aria-label="Contas a receber que vão junto">
                          {recebiveis.map((r) => (
                            <li key={r.id} className="break-words">
                              {numeroPorId.get(r.service_order_id ?? '') ?? ''}: {rotuloDoRecebivel(r)}
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                    {tarefas.length > 0 && (
                      <div className="space-y-1">
                        <p>{tarefas.length === 1 ? '1 tarefa pendente' : `${tarefas.length} tarefas pendentes`}:</p>
                        <ul className="list-disc space-y-0.5 pl-5 text-muted-foreground" aria-label="Tarefas que vão junto">
                          {tarefas.map((t) => (
                            <li key={t.id} className="break-words">
                              {t.title} ({numeroPorId.get(t.related_entity_id ?? '') ?? ''})
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                    {compras.length > 0 && (
                      <div className="space-y-1">
                        <p>{compras.length === 1 ? '1 pedido de compra' : `${compras.length} pedidos de compra`}:</p>
                        <ul className="list-disc space-y-0.5 pl-5 text-muted-foreground" aria-label="Compras que vão junto">
                          {compras.map((c) => (
                            <li key={c.id} className="break-words">
                              {c.po_number} · {PO_STATUS_LABELS[c.status as POStatus] ?? c.status} · {emReais(Number(c.total_amount) || 0)}{' '}
                              ({numeroPorId.get(c.service_order_id ?? '') ?? ''})
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </>
                )}
              </div>
            )}

            {avisos.length > 0 && (
              <div className="flex items-start gap-2 rounded-md border border-warning/50 bg-warning/10 p-3 text-sm">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
                <ul className="min-w-0 space-y-1 break-words" aria-label="Avisos antes de agrupar">
                  {avisos.map((d) => (
                    <li key={d}>{d}</li>
                  ))}
                </ul>
              </div>
            )}

            {erro && (
              <p role="alert" className="break-words rounded-md border border-destructive/40 p-3 text-sm text-destructive">
                {erro}
              </p>
            )}
          </div>
        )}

        <DialogFooter className="gap-2 pb-[env(safe-area-inset-bottom)] sm:gap-0">
          <Button variant="outline" onClick={onFechar} disabled={ocupado}>
            Cancelar
          </Button>
          <Button onClick={confirmar} disabled={foraDoLimite || ocupado || relendo} className="gap-1.5">
            {(ocupado || relendo) && <Loader2 className="h-4 w-4 animate-spin" />}
            {n === 1 ? 'Agrupar 1 OS' : `Agrupar ${n} OS`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
