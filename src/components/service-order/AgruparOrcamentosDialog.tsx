// Agrupar orçamentos (15/10/2026). O cliente aprova vários orçamentos juntos e pede UM atualizado: os
// escolhidos (mesmo cliente, mesma embarcação) viram um orçamento novo, com os preços que já tinham. O banco
// (agrupar_orcamentos) valida tudo e grava numa transação só; esta janela só mostra o que vai acontecer.
import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { AlertTriangle, Layers, Loader2 } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { useAgruparOrcamentos, useCandidatosParaAgrupar } from '@/hooks/use-agrupar-orcamentos';
import {
  MAX_AGRUPAR,
  MIN_AGRUPAR,
  diferencasEntreOrcamentos,
  emReais,
  motivoForaDoAgrupamento,
  principalPadrao,
  somaDosTotais,
} from '@/lib/agrupar-orcamentos';
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

export function AgruparOrcamentosDialog({ aberto, onFechar, clientId, vesselId, unidade, preSelecionados, principalSugerido }: Props) {
  const navigate = useNavigate();
  // "do mesmo motorhome", "da mesma lancha"; sem tipo, "da mesma embarcação ou veículo" (decisão 9).
  const tipo = rotuloDaUnidade(unidade?.asset_type).toLowerCase();
  const feminino = ehFeminino(unidade?.asset_type);
  const candidatos = useCandidatosParaAgrupar({ clientId, vesselId, enabled: aberto });
  const agrupar = useAgruparOrcamentos();

  const [selecionados, setSelecionados] = useState<string[]>(preSelecionados);
  const [principal, setPrincipal] = useState(principalSugerido ?? '');
  const [erro, setErro] = useState<string | null>(null);
  // Trava o clique duplo antes mesmo de o isPending chegar à tela (dois cliques no mesmo quadro).
  const enviando = useRef(false);

  // A cada abertura, volta ao que a tela de origem escolheu.
  const chaveDosPre = preSelecionados.join('|');
  useEffect(() => {
    if (!aberto) return;
    setSelecionados(chaveDosPre ? chaveDosPre.split('|') : []);
    setPrincipal(principalSugerido ?? '');
    setErro(null);
  }, [aberto, chaveDosPre, principalSugerido]);

  const lista = useMemo(() => candidatos.data ?? [], [candidatos.data]);
  const escolhidos = useMemo(
    () => lista.filter((c) => selecionados.includes(c.id) && !motivoForaDoAgrupamento(c)),
    [lista, selecionados],
  );
  const principalEfetivo = escolhidos.some((c) => c.id === principal) ? principal : principalPadrao(escolhidos);
  const numeroDoPrincipal = escolhidos.find((c) => c.id === principalEfetivo)?.service_order_number ?? '';
  const total = somaDosTotais(escolhidos);
  const diferencas = useMemo(() => diferencasEntreOrcamentos(escolhidos), [escolhidos]);
  const n = escolhidos.length;
  const foraDoLimite = n < MIN_AGRUPAR || n > MAX_AGRUPAR;
  const ocupado = agrupar.isPending;
  // A lista está sendo relida (ao abrir ou depois de uma recusa): o total na tela pode ser o velho, e é ele
  // que vai como p_total_esperado. Espera chegar.
  const relendo = !!candidatos.isFetching;
  const ausentes = candidatos.data
    ? chaveDosPre.split('|').filter((id) => id && !lista.some((c) => c.id === id)).length
    : 0;

  const alternar = (id: string, marcar: boolean) => {
    setErro(null);
    setSelecionados((atual) => (marcar ? (atual.includes(id) ? atual : [...atual, id]) : atual.filter((x) => x !== id)));
  };

  const confirmar = () => {
    if (enviando.current || foraDoLimite || ocupado || relendo) return;
    enviando.current = true;
    setErro(null);
    agrupar.mutate(
      { p_orcamentos: escolhidos.map((c) => c.id), p_base: principalEfetivo, p_total_esperado: total },
      {
        onSuccess: (r) => {
          toast.success(`Criado ${r.numero}: reúne ${r.origens.join(', ')}`);
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
      <DialogContent className="max-h-[92vh] w-[calc(100vw-2rem)] max-w-2xl overflow-y-auto overflow-x-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Layers className="h-5 w-5 text-primary" /> Agrupar orçamentos
          </DialogTitle>
          <DialogDescription>
            Os orçamentos escolhidos viram um orçamento novo, do mesmo cliente e {feminino ? 'da mesma' : 'do mesmo'} {tipo}.
          </DialogDescription>
        </DialogHeader>

        {candidatos.isLoading && (
          <div className="flex items-center gap-2 py-6 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Carregando os orçamentos…
          </div>
        )}

        {candidatos.error && (
          <p role="alert" className="rounded-md border border-destructive/40 p-3 text-sm text-destructive">
            Não foi possível carregar os orçamentos: {candidatos.error.message}
          </p>
        )}

        {candidatos.data && lista.length === 0 && (
          <p className="py-4 text-sm text-muted-foreground">
            Nenhum orçamento em aberto deste cliente e {feminino ? 'desta' : 'deste'} {tipo}.
          </p>
        )}

        {lista.length > 0 && (
          <div className="min-w-0 space-y-4">
            <ul className="divide-y rounded-md border" aria-label="Orçamentos em aberto do cliente">
              {lista.map((c) => {
                const motivo = motivoForaDoAgrupamento(c);
                const marcado = !motivo && selecionados.includes(c.id);
                return (
                  <li key={c.id} className="flex items-start gap-3 px-3 py-2 text-sm">
                    <Checkbox
                      id={`agrupar-${c.id}`}
                      className="mt-0.5"
                      checked={marcado}
                      disabled={!!motivo || ocupado}
                      onCheckedChange={(v) => alternar(c.id, v === true)}
                      aria-label={`Incluir ${c.service_order_number}`}
                      // Desabilitado: o leitor de tela diz por quê (o selo com o motivo).
                      aria-describedby={motivo ? `agrupar-motivo-${c.id}` : undefined}
                    />
                    <label htmlFor={`agrupar-${c.id}`} className={`min-w-0 flex-1 ${motivo ? 'text-muted-foreground' : 'cursor-pointer'}`}>
                      <span className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                        <span className="font-medium">{c.service_order_number}</span>
                        <span className="text-xs text-muted-foreground">{dataCurta(c.created_at)}</span>
                        {motivo && <Badge id={`agrupar-motivo-${c.id}`} variant="outline">{motivo}</Badge>}
                      </span>
                      {c.problem_description && (
                        <span className="block truncate text-xs text-muted-foreground" title={c.problem_description}>
                          {c.problem_description}
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
                  ? '1 orçamento escolhido não está mais em aberto (virou OS, foi cancelado ou já foi agrupado) e ficou de fora.'
                  : `${ausentes} orçamentos escolhidos não estão mais em aberto (viraram OS, foram cancelados ou já foram agrupados) e ficaram de fora.`}
              </p>
            )}

            {n > 0 && (
              <div className="space-y-1.5">
                <Label>Orçamento principal</Label>
                <p className="text-xs text-muted-foreground">Dele vêm a condição de pagamento, o contato e a comissão.</p>
                <RadioGroup
                  value={principalEfetivo}
                  onValueChange={setPrincipal}
                  className="flex flex-wrap gap-x-4 gap-y-2"
                  aria-label="Orçamento principal"
                >
                  {escolhidos.map((c) => (
                    <div key={c.id} className="flex items-center gap-2">
                      <RadioGroupItem value={c.id} id={`principal-${c.id}`} disabled={ocupado} />
                      <Label htmlFor={`principal-${c.id}`} className="cursor-pointer font-normal">
                        {c.service_order_number}
                      </Label>
                    </div>
                  ))}
                </RadioGroup>
              </div>
            )}

            <div className="space-y-2 rounded-md border bg-muted/30 p-3 text-sm">
              <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                <span>
                  {n === 1 ? '1 orçamento selecionado' : `${n} orçamentos selecionados`}
                </span>
                <span className="font-semibold">Total previsto: {emReais(total)}</span>
              </div>
              {n > MAX_AGRUPAR && (
                <p className="text-destructive">Agrupe no máximo {MAX_AGRUPAR} orçamentos de uma vez.</p>
              )}
              {n < MIN_AGRUPAR && <p className="text-muted-foreground">Escolha pelo menos {MIN_AGRUPAR} orçamentos.</p>}
              <ul className="list-disc space-y-1 pl-5 text-muted-foreground">
                <li>Preços mantidos: cada item entra com o preço que tem hoje no seu orçamento.</li>
                <li>
                  Condição de pagamento, contato e comissão vêm do principal{numeroDoPrincipal ? ` (${numeroDoPrincipal})` : ''};
                  a comissão é recalculada sobre o total novo.
                </li>
                <li>
                  Os escolhidos ficam cancelados como histórico e o link antigo deles para de funcionar. Dá para
                  desagrupar enquanto o novo não virar OS nem for assinado.
                </li>
              </ul>
            </div>

            {diferencas.length > 0 && (
              <div className="flex items-start gap-2 rounded-md border border-warning/50 bg-warning/10 p-3 text-sm">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
                <ul className="min-w-0 space-y-1 break-words" aria-label="Diferenças entre os orçamentos">
                  {diferencas.map((d) => (
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

        <DialogFooter className="gap-2 sm:gap-0">
          <Button variant="outline" onClick={onFechar} disabled={ocupado}>
            Cancelar
          </Button>
          <Button onClick={confirmar} disabled={foraDoLimite || ocupado || relendo} className="gap-1.5">
            {(ocupado || relendo) && <Loader2 className="h-4 w-4 animate-spin" />}
            {n === 1 ? 'Agrupar 1 orçamento' : `Agrupar ${n} orçamentos`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
