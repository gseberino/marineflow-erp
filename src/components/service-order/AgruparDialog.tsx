// "Agrupar" único (decisão 4B do dono, 18/11/2026). Mostra os ORÇ e as OS do mesmo cliente e da mesma embarcação.
//  - Apresentar junto (conjunto): nada muda nos documentos; o cliente recebe um PDF só. Vale para ORÇ + OS e para OS
//    que já começou.
//  - Juntar de vez (a fusão de antes): só aparece como escolha quando os escolhidos podem ser fundidos; aí a janela
//    entrega para o diálogo de sempre (AgruparOrcamentosDialog / AgruparOsDialog), que confere total e mostra o que vai junto.
import { useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Info, Layers, Loader2 } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { useAgruparParaCliente, useDocumentosParaConjunto } from '@/hooks/use-conjunto';
import {
  type CandidatoAoConjunto,
  type Conjunto,
  decidirComoAgrupar,
  situacaoDoDocumento,
} from '@/lib/conjunto';

const brl = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

interface Props {
  aberto: boolean;
  onFechar: () => void;
  /** O documento de onde a janela foi aberta (sempre na lista). */
  documentoId: string;
  /** Escolhidos na lista (barra de seleção); o documento já conta. */
  preSelecionados?: string[];
  /** Escolheu "Juntar de vez": o pai abre o diálogo de fusão de sempre com estes documentos. */
  onJuntarDeVez: (tipo: 'orcamentos' | 'os', ids: string[], principal: string) => void;
  /** Conjunto criado (para oferecer o envio em seguida). */
  onAgrupado?: (conjunto: Conjunto) => void;
}

type Modo = 'conjunto' | 'juntar';

export function AgruparDialog({ aberto, onFechar, documentoId, preSelecionados, onJuntarDeVez, onAgrupado }: Props) {
  const leitura = useDocumentosParaConjunto(documentoId, aberto);
  const agrupar = useAgruparParaCliente();
  const [escolhidos, setEscolhidos] = useState<string[]>([]);
  const [principal, setPrincipal] = useState<string>('');
  const [modo, setModo] = useState<Modo>('conjunto');
  const [erro, setErro] = useState<string | null>(null);

  const todos: CandidatoAoConjunto[] = useMemo(() => {
    if (!leitura.data) return [];
    return [leitura.data.documento, ...leitura.data.candidatos];
  }, [leitura.data]);

  // Escolha inicial: o documento + os pré-selecionados que podem entrar.
  useEffect(() => {
    if (!leitura.data) return;
    const pode = new Set(todos.filter((d) => !d.motivo).map((d) => d.id));
    const ini = [documentoId, ...(preSelecionados ?? [])].filter((id, i, a) => a.indexOf(id) === i && pode.has(id));
    setEscolhidos(ini);
    setPrincipal(ini.includes(documentoId) ? documentoId : ini[0] ?? '');
    setErro(null);
  }, [leitura.data]); // eslint-disable-line react-hooks/exhaustive-deps

  const selecionados = todos.filter((d) => escolhidos.includes(d.id));
  const decisao = decidirComoAgrupar(selecionados);
  const principalEfetivo = escolhidos.includes(principal) ? principal : escolhidos[0] ?? '';
  const total = selecionados.reduce((s, d) => s + d.grand_total, 0);
  const modoEfetivo: Modo = decisao.fusao ? modo : 'conjunto';
  const ocupado = agrupar.isPending;

  const alternar = (id: string, marcar: boolean) => {
    setErro(null);
    setEscolhidos((atual) => (marcar ? [...atual, id] : atual.filter((x) => x !== id)));
  };

  async function confirmar() {
    if (!decisao.podeConjunto) return;
    if (modoEfetivo === 'juntar' && decisao.fusao) {
      onJuntarDeVez(decisao.fusao, escolhidos, principalEfetivo);
      return;
    }
    try {
      const r = await agrupar.mutateAsync({ ids: escolhidos, principal: principalEfetivo });
      toast.success(`Pronto: ${r.nome} agora são apresentados juntos.`);
      r.avisos.forEach((a) => toast.info(a));
      onFechar();
      if (r.conjunto) onAgrupado?.(r.conjunto);
    } catch (e) {
      setErro((e as { message?: string })?.message ?? 'Não deu para agrupar.');
    }
  }

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && !ocupado && onFechar()}>
      <DialogContent className="max-h-[90dvh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Layers className="h-5 w-5" /> Agrupar
          </DialogTitle>
          <DialogDescription>
            Orçamentos e OS do mesmo cliente e da mesma embarcação.
          </DialogDescription>
        </DialogHeader>

        {leitura.isLoading && (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Buscando os documentos…
          </p>
        )}
        {leitura.error && (
          <p role="alert" className="break-words text-sm text-destructive">
            Não deu para buscar os documentos ({(leitura.error as Error).message}).
          </p>
        )}

        {leitura.data && (
          <div className="space-y-4">
            {leitura.data.documento.motivo && (
              <p role="alert" className="break-words rounded-md border border-destructive/40 p-3 text-sm text-destructive">
                {leitura.data.documento.motivo}
              </p>
            )}

            {todos.length < 2 ? (
              <p className="text-sm text-muted-foreground">
                Não há outro orçamento ou OS deste cliente para esta embarcação.
              </p>
            ) : (
              <ul className="divide-y rounded-md border" aria-label="Documentos para agrupar">
                {todos.map((d) => {
                  const marcado = escolhidos.includes(d.id);
                  return (
                    <li key={d.id} className="flex items-start gap-3 p-3 text-sm">
                      <Checkbox
                        id={`agrupar-${d.id}`}
                        checked={marcado}
                        disabled={!!d.motivo || ocupado}
                        onCheckedChange={(v) => alternar(d.id, v === true)}
                        className="mt-0.5"
                      />
                      <label htmlFor={`agrupar-${d.id}`} className="min-w-0 flex-1 cursor-pointer">
                        <span className="flex flex-wrap items-center gap-1.5">
                          <span className="font-medium">{d.numero}</span>
                          <Badge variant="outline">{d.tipo === 'orcamento' ? 'Orçamento' : 'OS'}</Badge>
                          <span className="text-xs text-muted-foreground">
                            {situacaoDoDocumento({ ...d, assinado: false })}
                          </span>
                        </span>
                        {d.motivo && <span className="mt-0.5 block break-words text-xs text-muted-foreground">{d.motivo}</span>}
                      </label>
                      <span className="whitespace-nowrap font-medium">{brl(d.grand_total)}</span>
                    </li>
                  );
                })}
              </ul>
            )}

            {escolhidos.length >= 2 && (
              <div className="space-y-1.5">
                <Label>Documento principal</Label>
                <p className="text-xs text-muted-foreground">Vem primeiro no PDF.</p>
                <RadioGroup
                  value={principalEfetivo}
                  onValueChange={setPrincipal}
                  className="flex flex-wrap gap-x-4 gap-y-2"
                  aria-label="Documento principal"
                >
                  {selecionados.map((d) => (
                    <div key={d.id} className="flex items-center gap-2">
                      <RadioGroupItem value={d.id} id={`principal-${d.id}`} disabled={ocupado} />
                      <Label htmlFor={`principal-${d.id}`} className="cursor-pointer font-normal">{d.numero}</Label>
                    </div>
                  ))}
                </RadioGroup>
              </div>
            )}

            {decisao.podeConjunto && decisao.fusao && (
              <RadioGroup
                value={modo}
                onValueChange={(v) => setModo(v as Modo)}
                className="space-y-2"
                aria-label="Como agrupar"
              >
                <label htmlFor="modo-conjunto" className="flex cursor-pointer items-start gap-3 rounded-md border p-3 text-sm">
                  <RadioGroupItem value="conjunto" id="modo-conjunto" className="mt-0.5" disabled={ocupado} />
                  <span>
                    <span className="block font-medium">Apresentar junto</span>
                    <span className="block text-muted-foreground">
                      Cada documento continua o seu. O cliente recebe um PDF só, com todos.
                    </span>
                  </span>
                </label>
                <label htmlFor="modo-juntar" className="flex cursor-pointer items-start gap-3 rounded-md border p-3 text-sm">
                  <RadioGroupItem value="juntar" id="modo-juntar" className="mt-0.5" disabled={ocupado} />
                  <span>
                    <span className="block font-medium">Juntar de vez</span>
                    <span className="block text-muted-foreground">
                      Vira {decisao.fusao === 'os' ? 'uma OS nova' : 'um orçamento novo'}; os escolhidos ficam como histórico.
                    </span>
                  </span>
                </label>
              </RadioGroup>
            )}

            {decisao.podeConjunto && modoEfetivo === 'conjunto' && (
              <div className="space-y-2 rounded-md border bg-muted/30 p-3 text-sm">
                <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                  <span>{escolhidos.length} documentos</span>
                  <span className="font-semibold">Total geral: {brl(total)}</span>
                </div>
                <ul className="list-disc space-y-1 pl-5 text-muted-foreground">
                  <li>Nada muda nos documentos: execução, sinal, assinatura e nota continuam em cada um.</li>
                  <li>O PDF ao cliente tem uma capa com os valores e, depois, cada documento completo.</li>
                  <li>Dá para desfazer a qualquer momento.</li>
                </ul>
                {decisao.porQueNaoFunde && (
                  <p className="flex items-start gap-1.5 break-words text-xs text-muted-foreground">
                    <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                    <span>Juntar de vez não é possível aqui: {decisao.porQueNaoFunde}</span>
                  </p>
                )}
              </div>
            )}

            {!decisao.podeConjunto && escolhidos.length > 0 && todos.length >= 2 && (
              <p className="text-sm text-muted-foreground">{decisao.motivoConjunto}</p>
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
          <Button onClick={confirmar} disabled={!decisao.podeConjunto || ocupado || !leitura.data} className="gap-1.5">
            {ocupado && <Loader2 className="h-4 w-4 animate-spin" />}
            {modoEfetivo === 'juntar' ? 'Continuar' : 'Agrupar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
