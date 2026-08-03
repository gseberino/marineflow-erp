import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import {
  AlertTriangle, ChevronDown, ChevronRight, Hammer, Loader2, Plus,
} from 'lucide-react';
import { toast } from 'sonner';
import {
  useServiceVerbsStatus, useCreateServiceVerb, verbIncomplete, slugify,
} from '@/hooks/use-service-systems';

/**
 * Tipos de serviço (verbos) — o que se faz.
 *
 * Irmã da tela de categorias, e pela mesma razão: faltava um tipo adequado
 * ("projeto") e sete serviços de assessoria acabaram como "logística", herdando
 * o roteiro de quem viaja — conferir ferramenta antes de sair, fotografar o bem
 * na retirada. Classificação errada não é só desorganização: vira roteiro
 * errado na mão do técnico.
 *
 * `is_fieldwork` existe por causa desse caso: projeto tem sistema (elétrico,
 * hidráulico) mas não vai a campo, então não deve receber "desligue a
 * alimentação".
 */
export function ServiceVerbsSection() {
  const { data: verbos = [], isLoading } = useServiceVerbsStatus();
  const criar = useCreateServiceVerb();

  const [aberto, setAberto] = useState(false);
  const [novo, setNovo] = useState({ name: '', is_fieldwork: true });

  function handleCriar() {
    const nome = novo.name.trim();
    if (!nome) return;
    criar.mutate(
      { name: nome, is_fieldwork: novo.is_fieldwork },
      {
        onSuccess: () => {
          setNovo({ name: '', is_fieldwork: true });
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
            O tipo decide o corpo do roteiro — o miolo do que se faz. A categoria decide a
            preparação e o fechamento de segurança ao redor dele.
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
            {verbos.map((v) => (
              <div key={v.slug} className="flex flex-wrap items-center gap-2 p-3">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <span className="text-sm font-medium">{v.name}</span>
                    {!v.is_fieldwork && (
                      <Badge variant="outline" className="text-[10px]">não vai a campo</Badge>
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
              </div>
            ))}

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
                    id="campo"
                    checked={novo.is_fieldwork}
                    onCheckedChange={(v) => setNovo((n) => ({ ...n, is_fieldwork: v }))}
                  />
                  <Label htmlFor="campo" className="text-xs font-normal">vai a campo</Label>
                </div>
                <Button size="sm" disabled={!novo.name.trim() || criar.isPending} onClick={handleCriar}>
                  <Plus className="mr-1.5 h-3.5 w-3.5" /> Criar
                </Button>
              </div>
              {novo.name.trim() && (
                <p className="text-[11px] text-muted-foreground">
                  Identificador: <code>{slugify(novo.name)}</code>
                  {novo.is_fieldwork
                    ? ' · recebe a preparação e o fechamento da categoria do serviço'
                    : ' · não recebe preparação de segurança, mesmo com categoria preenchida'}
                </p>
              )}
            </div>
          </div>
        )}
      </Card>
    </section>
  );
}
