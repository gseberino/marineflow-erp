import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import {
  Camera, Check, ChevronDown, ChevronRight, Layers, Loader2, Pencil, Ruler,
  ShieldAlert, Sparkles, X,
} from 'lucide-react';
import { toast } from 'sonner';
import {
  useStepBlocks, useApproveBlock, useRejectBlock, useUpdateBlock, useBlockImpact,
  blockPendingApproval, groupBlocks, type StepBlock,
} from '@/hooks/use-step-blocks';
import { formatMinutes } from '@/hooks/use-service-steps';

/**
 * Blocos componíveis — a revisão que rende mais por decisão tomada.
 *
 * Roteiro = abertura do SISTEMA + corpo do VERBO + fechamento do SISTEMA.
 * Aprovar o bloco de abertura do elétrico DC libera roteiro para os 54 serviços
 * de elétrico DC de uma vez; e o dia em que a regra de segurança de gás mudar,
 * é um bloco corrigido, não 10 roteiros reescritos.
 *
 * Mesma disciplina da tela de templates: sem "aprovar todos". Aprovação em lote
 * é o mesmo que não revisar — e aqui um passo errado entra no roteiro de dezenas
 * de serviços, não de um.
 */
export function StepBlocksSection() {
  const { data: blocks = [], isLoading } = useStepBlocks();
  const { data: impacto } = useBlockImpact();
  const approve = useApproveBlock();
  const reject = useRejectBlock();
  const update = useUpdateBlock();

  const [aberto, setAberto] = useState<Record<string, boolean>>({});
  const [editando, setEditando] = useState<string | null>(null);
  const [rascunho, setRascunho] = useState({ title: '', detail: '', minutes: '' });

  const grupos = useMemo(() => groupBlocks(blocks), [blocks]);
  const totalPendente = useMemo(() => blocks.filter(blockPendingApproval).length, [blocks]);

  function abrirEdicao(b: StepBlock) {
    setEditando(b.id);
    setRascunho({
      title: b.title,
      detail: b.detail || '',
      minutes: b.standard_minutes != null ? String(b.standard_minutes) : '',
    });
  }

  function salvarEAprovar(b: StepBlock) {
    const minutos = rascunho.minutes.trim() ? Number(rascunho.minutes) : null;
    if (minutos !== null && (Number.isNaN(minutos) || minutos <= 0)) {
      toast.error('O tempo precisa ser um número de minutos maior que zero.');
      return;
    }
    const mudou =
      rascunho.title.trim() !== b.title ||
      (rascunho.detail.trim() || null) !== b.detail ||
      minutos !== b.standard_minutes;

    update.mutate(
      {
        id: b.id,
        patch: {
          title: rascunho.title.trim(),
          detail: rascunho.detail.trim() || null,
          standard_minutes: minutos,
        },
      },
      {
        onSuccess: () => {
          approve.mutate(
            { block: { ...b, title: rascunho.title.trim(), standard_minutes: minutos }, edited: mudou },
            {
              onSuccess: () => { setEditando(null); toast.success('Passo aprovado.'); },
              onError: (e: any) => toast.error(e?.message || 'Erro ao aprovar'),
            },
          );
        },
        onError: (e: any) => toast.error(e?.message || 'Erro ao salvar'),
      },
    );
  }

  if (isLoading) {
    return (
      <p className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" /> Carregando blocos…
      </p>
    );
  }

  if (blocks.length === 0) return null;

  return (
    <section className="space-y-3">
      <div className="flex items-start gap-2">
        <Layers className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
        <div className="min-w-0">
          <h2 className="text-sm font-semibold">Blocos componíveis</h2>
          <p className="text-xs text-muted-foreground">
            O roteiro de cada serviço se monta com três peças: a abertura do sistema que ele toca,
            o corpo do verbo e o fechamento do sistema. Aprovar um bloco vale por todos os serviços
            daquele eixo.
          </p>
        </div>
      </div>

      {totalPendente > 0 && (
        <Card className="flex items-start gap-2 border-primary/40 bg-primary/5 p-3 text-sm">
          <Sparkles className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
          <span className="min-w-0">
            <strong>{totalPendente} passo(s) de bloco aguardando sua revisão.</strong>{' '}
            Nenhum roteiro é gerado enquanto não houver bloco aprovado. Confira com atenção os de{' '}
            <strong>gás</strong> e <strong>elétrico AC</strong>: são os que carregam risco físico.
            Onde o procedimento depende de um número (torque, pressão, temperatura), o passo diz
            "conferir no manual" de propósito — nada foi inventado aqui.
          </span>
        </Card>
      )}

      <div className="space-y-3">
        {grupos.map((g) => {
          const expandido = aberto[g.key] ?? false;
          const alcance = g.role === 'corpo'
            ? impacto?.porVerbo?.[g.eixo]
            : impacto?.porSistema?.[g.eixo];
          return (
            <Card key={g.key} className="overflow-hidden">
              <button
                className="flex w-full items-center justify-between gap-3 p-3 text-left transition-colors hover:bg-muted/50"
                onClick={() => setAberto((s) => ({ ...s, [g.key]: !expandido }))}
              >
                <div className="flex min-w-0 items-center gap-2">
                  {expandido ? <ChevronDown className="h-4 w-4 shrink-0" /> : <ChevronRight className="h-4 w-4 shrink-0" />}
                  <span className="truncate text-sm font-medium">{g.eixoLabel}</span>
                  <Badge variant="secondary" className="shrink-0 text-[10px]">{g.roleLabel}</Badge>
                </div>
                <div className="flex shrink-0 flex-wrap items-center justify-end gap-2 text-xs tabular-nums text-muted-foreground">
                  {alcance != null && <span>{alcance} serviços</span>}
                  <span>{g.steps.length} passos</span>
                  <span>{formatMinutes(g.minutosTotais)}</span>
                  {g.pendentes > 0 && (
                    <Badge className="bg-primary text-[10px] text-primary-foreground">
                      {g.pendentes} a revisar
                    </Badge>
                  )}
                </div>
              </button>

              {expandido && (
                <div className="divide-y border-t">
                  {g.steps.map((b) => {
                    const pendente = blockPendingApproval(b);
                    const emEdicao = editando === b.id;
                    return (
                      <div key={b.id} className={`p-3 ${pendente ? 'bg-primary/5' : ''}`}>
                        {emEdicao ? (
                          <div className="space-y-2">
                            <Input
                              value={rascunho.title}
                              onChange={(e) => setRascunho((r) => ({ ...r, title: e.target.value }))}
                              placeholder="Título do passo (verbo no imperativo)"
                              className="h-9"
                            />
                            <Textarea
                              value={rascunho.detail}
                              onChange={(e) => setRascunho((r) => ({ ...r, detail: e.target.value }))}
                              placeholder="Detalhe — o 'como' e o porquê. Opcional."
                              rows={3}
                            />
                            <div className="flex flex-wrap items-center gap-2">
                              <Input
                                value={rascunho.minutes}
                                onChange={(e) => setRascunho((r) => ({ ...r, minutes: e.target.value }))}
                                placeholder="minutos"
                                inputMode="numeric"
                                className="h-9 w-28"
                              />
                              <Button size="sm" variant="ghost" onClick={() => setEditando(null)}>
                                Cancelar
                              </Button>
                              <Button
                                size="sm"
                                disabled={!rascunho.title.trim() || update.isPending || approve.isPending}
                                onClick={() => salvarEAprovar(b)}
                              >
                                Salvar e aprovar
                              </Button>
                            </div>
                          </div>
                        ) : (
                          <div className="flex items-start gap-3">
                            <span className="mt-0.5 w-5 shrink-0 text-[11px] tabular-nums text-muted-foreground">
                              {b.seq}
                            </span>
                            <div className="min-w-0 flex-1 space-y-1">
                              <div className="flex flex-wrap items-center gap-1.5">
                                <span className="text-sm font-medium">{b.title}</span>
                                {b.kind === 'safety' && <ShieldAlert className="h-3.5 w-3.5 text-red-600" />}
                                {b.is_killer && (
                                  <Badge variant="outline" className="border-amber-500 text-[10px] text-amber-700 dark:text-amber-400">
                                    crítico
                                  </Badge>
                                )}
                                {b.requires_photo && <Camera className="h-3.5 w-3.5 text-muted-foreground" />}
                                {b.requires_measure && (
                                  <Badge variant="outline" className="gap-1 text-[10px]">
                                    <Ruler className="h-3 w-3" />
                                    {b.measure_unit ? `medir (${b.measure_unit})` : 'medir'}
                                  </Badge>
                                )}
                                {b.mode === 'read_do' && (
                                  <Badge variant="outline" className="text-[10px]">leia e faça</Badge>
                                )}
                              </div>
                              {b.detail && (
                                <p className="text-xs leading-snug text-muted-foreground">{b.detail}</p>
                              )}
                              <div className="flex flex-wrap items-center gap-2 text-[11px] tabular-nums text-muted-foreground">
                                <span>{formatMinutes(b.standard_minutes)}</span>
                                {pendente ? (
                                  <span className="text-primary">rascunho da IA — aguarda sua decisão</span>
                                ) : b.active ? (
                                  <span className="text-emerald-700 dark:text-emerald-400">em uso</span>
                                ) : (
                                  <span>inativo</span>
                                )}
                              </div>
                            </div>

                            {pendente && (
                              <div className="flex shrink-0 gap-1">
                                <Button
                                  size="sm" variant="ghost" className="h-7 px-2 text-destructive"
                                  title="Descartar este passo"
                                  onClick={() => reject.mutate(b, {
                                    onError: (e: any) => toast.error(e?.message || 'Erro'),
                                  })}
                                >
                                  <X className="h-3.5 w-3.5" />
                                </Button>
                                <Button
                                  size="sm" variant="outline" className="h-7 px-2"
                                  title="Editar antes de aprovar"
                                  onClick={() => abrirEdicao(b)}
                                >
                                  <Pencil className="h-3.5 w-3.5" />
                                </Button>
                                <Button
                                  size="sm" className="h-7 px-2"
                                  title="Aprovar como está"
                                  onClick={() => approve.mutate({ block: b }, {
                                    onSuccess: () => toast.success('Passo aprovado.'),
                                    onError: (e: any) => toast.error(e?.message || 'Erro'),
                                  })}
                                >
                                  <Check className="h-3.5 w-3.5" />
                                </Button>
                              </div>
                            )}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </Card>
          );
        })}
      </div>
    </section>
  );
}
