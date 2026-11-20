// "Agrupar para o cliente" F2: o cliente aprovou o conjunto. A janela mostra, ANTES de gravar, o que o banco vai fazer com
// cada documento (aprovar_conjunto com p_ensaio): o que já está assinado, as OS e o que já foi aprovado não mudam; cada
// orçamento marcado segue a PRÓPRIA condição (3A) — com sinal, aguarda o sinal dele e vira OS quando ele entrar; sem sinal,
// vira OS agora — e fica marcado "complementa a OS-X" (5A). Converter não se desfaz: por isso a confirmação lista tudo.
import { useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { CheckCheck, Loader2 } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Badge } from '@/components/ui/badge';
import { useAprovarConjunto, useEnsaioDaAprovacao, useSinaisDosOrcamentos } from '@/hooks/use-conjunto';
import type { Conjunto } from '@/lib/conjunto';
import { type AcaoNaAprovacao, orcamentosAprovaveis, resumoDaAprovacao } from '@/lib/conjunto-aprovacao';

const brl = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

const SELO: Record<AcaoNaAprovacao, { rotulo: string; classe: string }> = {
  virar_os: { rotulo: 'Vira OS agora', classe: 'border-emerald-300 text-emerald-800 dark:border-emerald-700 dark:text-emerald-200' },
  aguardar_sinal: { rotulo: 'Aguarda o sinal', classe: 'border-orange-300 text-orange-800 dark:border-orange-700 dark:text-orange-200' },
  nao_muda: { rotulo: 'Não muda', classe: 'text-muted-foreground' },
};

interface Props {
  aberto: boolean;
  onFechar: () => void;
  conjunto: Conjunto;
}

export function AprovarConjuntoDialog({ aberto, onFechar, conjunto }: Props) {
  const aprovaveis = useMemo(() => orcamentosAprovaveis(conjunto), [conjunto]);
  const [escolhidos, setEscolhidos] = useState<string[]>(() => aprovaveis.map((d) => d.id));
  const [erro, setErro] = useState<string | null>(null);
  useEffect(() => {
    if (aberto) {
      setEscolhidos(aprovaveis.map((d) => d.id));
      setErro(null);
    }
  }, [aberto]); // eslint-disable-line react-hooks/exhaustive-deps

  const ensaio = useEnsaioDaAprovacao(conjunto.id, escolhidos, aberto);
  const sinais = useSinaisDosOrcamentos(aprovaveis.map((d) => d.id), aberto);
  const aprovar = useAprovarConjunto();
  const ocupado = aprovar.isPending;
  const plano = ensaio.data;
  const podeAprovar = !!plano && plano.aprovados > 0 && !ensaio.isFetching && !ocupado;
  const aprovavel = new Set(aprovaveis.map((d) => d.id));

  const alternar = (id: string, marcar: boolean) => {
    setErro(null);
    setEscolhidos((atual) => (marcar ? [...atual, id] : atual.filter((x) => x !== id)));
  };

  async function confirmar() {
    if (!podeAprovar) return;
    try {
      const r = await aprovar.mutateAsync({ conjuntoId: conjunto.id, ids: escolhidos });
      toast.success(resumoDaAprovacao(r));
      onFechar();
    } catch (e) {
      setErro((e as { message?: string })?.message ?? 'Não deu para aprovar.');
    }
  }

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && !ocupado && onFechar()}>
      <DialogContent className="max-h-[90dvh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <CheckCheck className="h-5 w-5" /> Aprovar {conjunto.nome}
          </DialogTitle>
          <DialogDescription>
            O cliente aprovou? Cada orçamento segue a própria condição de pagamento. O que já está assinado não muda.
          </DialogDescription>
        </DialogHeader>

        {ensaio.isLoading && (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Conferindo os documentos…
          </p>
        )}
        {ensaio.error && (
          <p role="alert" className="break-words text-sm text-destructive">
            Não deu para conferir ({(ensaio.error as Error).message}).
          </p>
        )}

        {plano && (
          <div className="space-y-4">
            <ul className="divide-y rounded-md border" aria-label="Documentos do conjunto">
              {plano.documentos.map((d) => {
                const marcavel = aprovavel.has(d.id);
                const sinal = sinais.data?.[d.id];
                return (
                  <li key={d.id} className="flex items-start gap-3 p-3 text-sm">
                    {marcavel ? (
                      <Checkbox
                        id={`aprovar-${d.id}`}
                        checked={escolhidos.includes(d.id)}
                        disabled={ocupado}
                        onCheckedChange={(v) => alternar(d.id, v === true)}
                        className="mt-0.5"
                        aria-label={`Aprovar ${d.numero}`}
                      />
                    ) : (
                      <span className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
                    )}
                    <label htmlFor={marcavel ? `aprovar-${d.id}` : undefined} className="min-w-0 flex-1">
                      <span className="flex flex-wrap items-center gap-1.5">
                        <span className="font-medium">{d.numero}</span>
                        <Badge variant="outline" className={SELO[d.acao].classe}>{SELO[d.acao].rotulo}</Badge>
                      </span>
                      <span className="mt-0.5 block break-words text-xs text-muted-foreground">{d.texto}</span>
                      {d.acao === 'aguardar_sinal' && sinal && (
                        <span className="mt-0.5 block text-xs">
                          Sinal dele: <strong>{brl(sinal.valor)}</strong>
                          {sinal.padrao && <span className="text-muted-foreground"> (condição padrão: 50% do serviço + peças e despesas)</span>}
                        </span>
                      )}
                    </label>
                  </li>
                );
              })}
            </ul>

            <ul className="list-disc space-y-1 rounded-md border bg-muted/30 p-3 pl-8 text-sm text-muted-foreground">
              <li>Com sinal: o orçamento fica aprovado e vira OS própria quando o sinal dele for registrado (como hoje).</li>
              <li>Sem sinal na condição: vira OS própria agora e entra na agenda; a cobrança nasce na conclusão.</li>
              {plano.complementa ? (
                <li>
                  Os aprovados ficam marcados <strong className="text-foreground">complementa a {plano.complementa.numero}</strong>:
                  {' '}são OS próprias, não entram nela.
                </li>
              ) : (
                <li>Não há OS no conjunto: cada orçamento aprovado vira uma OS independente.</li>
              )}
              <li>Converter em OS não se desfaz por aqui.</li>
            </ul>

            {plano.aprovados === 0 && !ensaio.isFetching && (
              <p className="text-sm text-muted-foreground">Marque pelo menos um orçamento para aprovar.</p>
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
          <Button onClick={confirmar} disabled={!podeAprovar} className="gap-1.5">
            {ocupado && <Loader2 className="h-4 w-4 animate-spin" />}
            {plano && plano.aprovados > 0 ? `Aprovar ${plano.aprovados}` : 'Aprovar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
