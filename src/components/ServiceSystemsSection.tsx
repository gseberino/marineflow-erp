import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import {
  AlertTriangle, Check, ChevronDown, ChevronRight, Layers3, Loader2, Pencil, Plus, X,
} from 'lucide-react';
import { toast } from 'sonner';
import {
  useServiceSystemsStatus, useCreateServiceSystem, useUpdateServiceSystem,
  systemIncomplete, slugify, type ServiceSystemStatus,
} from '@/hooks/use-service-systems';

/**
 * Categorias técnicas (sistemas) — o cadastro que faltava.
 *
 * A categoria é o que traz a abertura e o fechamento de segurança do roteiro.
 * Por isso a tela insiste num ponto: criar a categoria é o começo, não o fim.
 * Enquanto ela não tiver os dois blocos escritos, os serviços dela rodam sem
 * preparação nenhuma — e o aviso fica visível até que isso se resolva.
 */
export function ServiceSystemsSection() {
  const { data: sistemas = [], isLoading } = useServiceSystemsStatus();
  const criar = useCreateServiceSystem();
  const atualizar = useUpdateServiceSystem();

  const [aberto, setAberto] = useState(false);
  const [novo, setNovo] = useState({ name: '', is_physical: true });
  const [editando, setEditando] = useState<string | null>(null);
  const [rascunho, setRascunho] = useState({ name: '', short_name: '' });

  function abrirEdicao(s: ServiceSystemStatus) {
    setEditando(s.slug);
    setRascunho({ name: s.name, short_name: s.short_name || '' });
  }

  function salvar(slug: string) {
    const nome = rascunho.name.trim();
    if (!nome) return;
    atualizar.mutate(
      { slug, patch: { name: nome, short_name: rascunho.short_name.trim() || nome } },
      {
        onSuccess: () => { setEditando(null); toast.success('Categoria atualizada.'); },
        onError: (e: any) => toast.error(e?.message || 'Erro ao salvar'),
      },
    );
  }

  function handleCriar() {
    const nome = novo.name.trim();
    if (!nome) return;
    criar.mutate(
      { name: nome, is_physical: novo.is_physical },
      {
        onSuccess: () => {
          setNovo({ name: '', is_physical: true });
          toast.success(
            novo.is_physical
              ? 'Categoria criada. Agora escreva a abertura e o fechamento dela.'
              : 'Categoria criada.',
          );
        },
        onError: (e: any) => toast.error(e?.message || 'Erro ao criar categoria'),
      },
    );
  }

  if (isLoading) {
    return (
      <p className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" /> Carregando categorias…
      </p>
    );
  }

  const incompletas = sistemas.filter(systemIncomplete).length;

  return (
    <section className="space-y-3">
      <div className="flex items-start gap-2">
        <Layers3 className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
        <div className="min-w-0">
          <h2 className="text-sm font-semibold">Categorias técnicas</h2>
          <p className="text-xs text-muted-foreground">
            A categoria de um serviço decide qual preparação e qual fechamento ele recebe.
            Criar uma nova é o primeiro passo — ela só passa a proteger depois que os blocos
            dela estiverem escritos.
          </p>
        </div>
      </div>

      {incompletas > 0 && (
        <Card className="flex items-start gap-2 border-amber-500/50 bg-amber-50 p-3 text-sm dark:bg-amber-950/30">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
          <span className="min-w-0">
            <strong>{incompletas} categoria(s) sem preparação ou sem fechamento.</strong>{' '}
            Os serviços nelas recebem só o corpo do verbo — entram e saem sem nenhum passo de
            segurança do sistema.
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
            <span className="truncate text-sm font-medium">{sistemas.length} categorias</span>
          </div>
          <span className="shrink-0 text-xs text-muted-foreground">gerenciar</span>
        </button>

        {aberto && (
          <div className="divide-y border-t">
            {sistemas.map((s) => {
              const incompleta = systemIncomplete(s);
              const emEdicao = editando === s.slug;
              return (
                <div key={s.slug} className="p-3">
                  {emEdicao ? (
                    <div className="space-y-2">
                      <Input
                        value={rascunho.name}
                        onChange={(e) => setRascunho((r) => ({ ...r, name: e.target.value }))}
                        placeholder="Nome completo"
                        className="h-9 w-full sm:w-72"
                      />
                      <div className="flex flex-wrap items-center gap-2">
                        <Input
                          value={rascunho.short_name}
                          onChange={(e) => setRascunho((r) => ({ ...r, short_name: e.target.value }))}
                          placeholder="Nome curto (aparece no roteiro)"
                          className="h-9 w-full sm:w-56"
                        />
                        <Button size="sm" variant="ghost" onClick={() => setEditando(null)}>
                          <X className="mr-1.5 h-3.5 w-3.5" /> Cancelar
                        </Button>
                        <Button
                          size="sm"
                          disabled={!rascunho.name.trim() || atualizar.isPending}
                          onClick={() => salvar(s.slug)}
                        >
                          <Check className="mr-1.5 h-3.5 w-3.5" /> Salvar
                        </Button>
                      </div>
                      <p className="text-[11px] text-muted-foreground">
                        O nome curto é o que sai no rótulo do bloco: “Antes de mexer —{' '}
                        {rascunho.short_name.trim() || rascunho.name.trim() || '…'}”.
                      </p>
                    </div>
                  ) : (
                    <div className="flex flex-wrap items-center gap-2">
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-1.5">
                          <span className="text-sm font-medium">{s.name}</span>
                          {!s.is_physical && (
                            <Badge variant="outline" className="text-[10px]">sem risco físico</Badge>
                          )}
                          {incompleta && (
                            <Badge variant="outline" className="border-amber-500 text-[10px] text-amber-700 dark:text-amber-400">
                              faltam blocos
                            </Badge>
                          )}
                        </div>
                        <p className="text-[11px] tabular-nums text-muted-foreground">
                          {s.servicos} serviço(s) · {s.passos_abertura} de abertura ·{' '}
                          {s.passos_fechamento} de fechamento · {s.perguntas} pergunta(s)
                        </p>
                      </div>
                      <Button size="sm" variant="outline" className="h-8 px-2"
                              title="Editar nome da categoria"
                              onClick={() => abrirEdicao(s)}>
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                  )}
                </div>
              );
            })}

            <div className="space-y-2 bg-muted/30 p-3">
              <Label className="text-xs">Nova categoria</Label>
              <div className="flex flex-wrap items-center gap-2">
                <Input
                  value={novo.name}
                  onChange={(e) => setNovo((n) => ({ ...n, name: e.target.value }))}
                  placeholder="Ex.: Ar comprimido"
                  className="h-9 w-full sm:w-64"
                />
                <div className="flex items-center gap-2">
                  <Switch
                    id="fisico"
                    checked={novo.is_physical}
                    onCheckedChange={(v) => setNovo((n) => ({ ...n, is_physical: v }))}
                  />
                  <Label htmlFor="fisico" className="text-xs font-normal">
                    tem risco físico
                  </Label>
                </div>
                <Button size="sm" disabled={!novo.name.trim() || criar.isPending} onClick={handleCriar}>
                  <Plus className="mr-1.5 h-3.5 w-3.5" /> Criar
                </Button>
              </div>
              {novo.name.trim() && (
                <p className="text-[11px] text-muted-foreground">
                  Identificador: <code>{slugify(novo.name)}</code>
                  {novo.is_physical && ' · você precisará escrever a abertura e o fechamento dela'}
                </p>
              )}
            </div>
          </div>
        )}
      </Card>
    </section>
  );
}
