import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import {
  AlertTriangle, Check, ChevronDown, ChevronRight, Hammer, Loader2, Pencil, Plus, X,
} from 'lucide-react';
import { toast } from 'sonner';
import {
  useServiceVerbsStatus, useCreateServiceVerb, useUpdateServiceVerb,
  verbIncomplete, slugify, type ServiceVerbStatus,
} from '@/hooks/use-service-systems';

/**
 * Tipos de serviço (verbos) — o que se faz.
 *
 * `intervem_no_sistema` responde a uma pergunta só: este trabalho expõe alguém
 * à energia do sistema? Se sim, o roteiro traz a preparação e o fechamento de
 * segurança da categoria; se não, traz só o corpo.
 *
 * O critério é a exposição, NÃO o lugar — um levantamento de projeto acontece
 * no barco e continua sendo observação. Até 03/08 este campo se chamava
 * "vai a campo", que fazia a pergunta errada; o dono percebeu ao ver
 * "projeto/consultoria" marcado como se nunca saísse do escritório.
 */
export function ServiceVerbsSection() {
  const { data: verbos = [], isLoading } = useServiceVerbsStatus();
  const criar = useCreateServiceVerb();
  const atualizar = useUpdateServiceVerb();

  const [aberto, setAberto] = useState(false);
  const [novo, setNovo] = useState({ name: '', intervem_no_sistema: true });
  const [editando, setEditando] = useState<string | null>(null);
  const [rascunho, setRascunho] = useState({ name: '', intervem_no_sistema: true });

  function abrirEdicao(v: ServiceVerbStatus) {
    setEditando(v.slug);
    setRascunho({ name: v.name, intervem_no_sistema: v.intervem_no_sistema });
  }

  function salvar(slug: string) {
    const nome = rascunho.name.trim();
    if (!nome) return;
    atualizar.mutate(
      { slug, patch: { name: nome, intervem_no_sistema: rascunho.intervem_no_sistema } },
      {
        onSuccess: () => { setEditando(null); toast.success('Tipo de serviço atualizado.'); },
        onError: (e: any) => toast.error(e?.message || 'Erro ao salvar'),
      },
    );
  }

  function handleCriar() {
    const nome = novo.name.trim();
    if (!nome) return;
    criar.mutate(
      { name: nome, intervem_no_sistema: novo.intervem_no_sistema },
      {
        onSuccess: () => {
          setNovo({ name: '', intervem_no_sistema: true });
          toast.success('Tipo criado. Agora escreva os passos do corpo dele.');
        },
        onError: (e: any) => toast.error(e?.message || 'Erro ao criar tipo'),
      },
    );
  }

  if (isLoading) {
    return (
      <p className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" /> Carregando tipos de serviço…
      </p>
    );
  }

  const incompletos = verbos.filter(verbIncomplete).length;

  return (
    <section className="space-y-3">
      <div className="flex items-start gap-2">
        <Hammer className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
        <div className="min-w-0">
          <h2 className="text-sm font-semibold">Tipos de serviço</h2>
          <p className="text-xs text-muted-foreground">
            O tipo decide o corpo do roteiro — o miolo do que se faz. Marque
            <strong> mexe no sistema</strong> quando o trabalho expõe alguém à energia (elétrica,
            gás, pressão): é isso que faz o roteiro trazer a preparação e o fechamento de segurança
            da categoria. Observar, medir e fotografar não expõe, mesmo indo até o barco.
          </p>
        </div>
      </div>

      {incompletos > 0 && (
        <Card className="flex items-start gap-2 border-amber-500/50 bg-amber-50 p-3 text-sm dark:bg-amber-950/30">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
          <span className="min-w-0">
            <strong>{incompletos} tipo(s) sem corpo escrito.</strong>{' '}
            Os serviços deles não recebem passo nenhum na parte da execução — o roteiro sai só
            com a preparação e o fechamento, se houver.
          </span>
        </Card>
      )}

      <Card className="overflow-hidden">
        <button
          className="flex w-full items-center justify-between gap-3 p-3 text-left transition-colors hover:bg-muted/50"
          onClick={() => setAberto((a) => !a)}
        >
          <div className="flex min-w-0 items-center gap-2">
            {aberto ? <ChevronDown className="h-4 w-4 shrink-0" /> : <ChevronRight className="h-4 w-4 shrink-0" />}
            <span className="truncate text-sm font-medium">{verbos.length} tipos</span>
          </div>
          <span className="shrink-0 text-xs text-muted-foreground">gerenciar</span>
        </button>

        {aberto && (
          <div className="divide-y border-t">
            {verbos.map((v) => {
              const emEdicao = editando === v.slug;
              return (
                <div key={v.slug} className="p-3">
                  {emEdicao ? (
                    <div className="space-y-2">
                      <Input
                        value={rascunho.name}
                        onChange={(e) => setRascunho((r) => ({ ...r, name: e.target.value }))}
                        className="h-9 w-full sm:w-64"
                      />
                      <div className="flex flex-wrap items-center gap-2">
                        <div className="flex items-center gap-2">
                          <Switch
                            id={`mexe-${v.slug}`}
                            checked={rascunho.intervem_no_sistema}
                            onCheckedChange={(x) => setRascunho((r) => ({ ...r, intervem_no_sistema: x }))}
                          />
                          <Label htmlFor={`mexe-${v.slug}`} className="text-xs font-normal">
                            mexe no sistema
                          </Label>
                        </div>
                        <Button size="sm" variant="ghost" onClick={() => setEditando(null)}>
                          <X className="mr-1.5 h-3.5 w-3.5" /> Cancelar
                        </Button>
                        <Button
                          size="sm"
                          disabled={!rascunho.name.trim() || atualizar.isPending}
                          onClick={() => salvar(v.slug)}
                        >
                          <Check className="mr-1.5 h-3.5 w-3.5" /> Salvar
                        </Button>
                      </div>
                      <p className="text-[11px] text-muted-foreground">
                        {rascunho.intervem_no_sistema
                          ? 'Recebe a preparação e o fechamento de segurança da categoria do serviço.'
                          : 'Só o corpo: sem preparação de segurança, mesmo com categoria preenchida.'}
                      </p>
                    </div>
                  ) : (
                    <div className="flex flex-wrap items-center gap-2">
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-1.5">
                          <span className="text-sm font-medium">{v.name}</span>
                          {v.intervem_no_sistema ? (
                            <Badge variant="outline" className="text-[10px]">mexe no sistema</Badge>
                          ) : (
                            <Badge variant="outline" className="text-[10px]">só observa</Badge>
                          )}
                          {verbIncomplete(v) && (
                            <Badge variant="outline" className="border-amber-500 text-[10px] text-amber-700 dark:text-amber-400">
                              sem corpo
                            </Badge>
                          )}
                        </div>
                        <p className="text-[11px] tabular-nums text-muted-foreground">
                          {v.servicos} serviço(s) · {v.passos_corpo} passo(s) de corpo ·{' '}
                          {v.perguntas} pergunta(s)
                        </p>
                      </div>
                      <Button size="sm" variant="outline" className="h-8 px-2"
                              title="Editar nome e critério de segurança"
                              onClick={() => abrirEdicao(v)}>
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                  )}
                </div>
              );
            })}

            <div className="space-y-2 bg-muted/30 p-3">
              <Label className="text-xs">Novo tipo de serviço</Label>
              <div className="flex flex-wrap items-center gap-2">
                <Input
                  value={novo.name}
                  onChange={(e) => setNovo((n) => ({ ...n, name: e.target.value }))}
                  placeholder="Ex.: Vistoria, Treinamento"
                  className="h-9 w-full sm:w-64"
                />
                <div className="flex items-center gap-2">
                  <Switch
                    id="mexe-novo"
                    checked={novo.intervem_no_sistema}
                    onCheckedChange={(v) => setNovo((n) => ({ ...n, intervem_no_sistema: v }))}
                  />
                  <Label htmlFor="mexe-novo" className="text-xs font-normal">mexe no sistema</Label>
                </div>
                <Button size="sm" disabled={!novo.name.trim() || criar.isPending} onClick={handleCriar}>
                  <Plus className="mr-1.5 h-3.5 w-3.5" /> Criar
                </Button>
              </div>
              {novo.name.trim() && (
                <p className="text-[11px] text-muted-foreground">
                  Identificador: <code>{slugify(novo.name)}</code>
                  {novo.intervem_no_sistema
                    ? ' · recebe a preparação e o fechamento da categoria do serviço'
                    : ' · só o corpo, sem preparação de segurança'}
                </p>
              )}
            </div>
          </div>
        )}
      </Card>
    </section>
  );
}
