// Favorecidos — quem recebe dinheiro da empresa sem ser fornecedor nem usuário do sistema.
//
// Existe porque o cadastro só podia ser aberto de dentro da caixa de entrada, no meio de
// uma conferência. Faltava o lugar óbvio: manter a lista, corrigir uma chave Pix errada,
// desativar quem saiu. Cadastro sem tela de gestão é cadastro que envelhece errado.
import { useMemo, useState } from 'react';
import { PageShell } from '@/v2/components/PageShell';
import { V2Shell } from '@/v2/components/V2Shell';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Tooltip, TooltipContent, TooltipProvider, TooltipTrigger,
} from '@/components/ui/tooltip';
import { PayeeFormDialog } from '@/components/PayeeFormDialog';
import {
  usePayees, useSalvarPayee, ROTULO_TIPO, type Favorecido, type TipoFavorecido,
} from '@/hooks/use-payees';
import { Plus, Pencil, Search, UserX, UserCheck, KeyRound, Landmark } from 'lucide-react';

const TONS: Record<TipoFavorecido, string> = {
  socio: 'border-primary/40 bg-primary/10 text-primary',
  funcionario: 'border-info/40 bg-info/10 text-info',
  diarista: 'border-warning/40 bg-warning/10 text-warning',
  prestador: 'border-border bg-muted text-muted-foreground',
  comissionado: 'border-success/40 bg-success/10 text-success',
};

/** Mostra CPF/CNPJ legível: dígitos crus não se conferem de olho. */
function mascara(doc: string | null): string | null {
  if (!doc) return null;
  if (doc.length === 14) return doc.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, '$1.$2.$3/$4-$5');
  if (doc.length === 11) return doc.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, '$1.$2.$3-$4');
  return doc;
}

export default function PayeesPage() {
  const { data: favorecidos = [], isLoading } = usePayees(false);   // inclui inativos
  const salvar = useSalvarPayee();

  const [busca, setBusca] = useState('');
  const [filtroTipo, setFiltroTipo] = useState<TipoFavorecido | 'todos'>('todos');
  const [editando, setEditando] = useState<Favorecido | null>(null);
  const [criando, setCriando] = useState(false);

  const visiveis = useMemo(() => {
    const termo = busca.trim().toLowerCase();
    return favorecidos.filter((f) => {
      if (filtroTipo !== 'todos' && f.kind !== filtroTipo) return false;
      if (!termo) return true;
      return [f.name, f.document, f.pix_key, f.email]
        .some((v) => (v ?? '').toLowerCase().includes(termo));
    });
  }, [favorecidos, busca, filtroTipo]);

  const contagem = useMemo(() => {
    const c: Record<string, number> = { todos: favorecidos.length };
    for (const f of favorecidos) c[f.kind] = (c[f.kind] ?? 0) + 1;
    return c;
  }, [favorecidos]);

  const alternarAtivo = (f: Favorecido) =>
    salvar.mutate({ id: f.id, active: !f.active });

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Financeiro' }, { label: 'Favorecidos' }]}
        title="Favorecidos"
        description="Quem recebe da empresa sem ser fornecedor: sócios, funcionários, diaristas, prestadores e comissionados."
        actions={
          <Button onClick={() => setCriando(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Novo favorecido
          </Button>
        }
      >
        <div className="space-y-4">
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative min-w-0 flex-1 sm:max-w-xs">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                value={busca}
                onChange={(e) => setBusca(e.target.value)}
                placeholder="Nome, CPF/CNPJ, chave Pix…"
                className="pl-8"
              />
            </div>
          </div>

          <Tabs value={filtroTipo} onValueChange={(v) => setFiltroTipo(v as never)}>
            <TabsList className="flex h-auto w-full flex-wrap justify-start">
              <TabsTrigger value="todos">Todos ({contagem.todos ?? 0})</TabsTrigger>
              {(Object.keys(ROTULO_TIPO) as TipoFavorecido[]).map((k) => (
                <TabsTrigger key={k} value={k}>
                  {ROTULO_TIPO[k]} ({contagem[k] ?? 0})
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>

          {isLoading ? (
            <div className="space-y-2">
              {[...Array(4)].map((_, i) => <Skeleton key={i} className="h-16 rounded-xl" />)}
            </div>
          ) : visiveis.length === 0 ? (
            <Card className="p-8 text-center">
              <p className="text-muted-foreground">
                {favorecidos.length === 0
                  ? 'Nenhum favorecido cadastrado ainda. Comece pelos sócios que recebem pró-labore.'
                  : 'Nenhum favorecido corresponde a esta busca.'}
              </p>
            </Card>
          ) : (
            <TooltipProvider>
              <div className="space-y-2">
                {visiveis.map((f) => (
                  <Card key={f.id} className={`p-3 ${f.active ? '' : 'opacity-60'}`}>
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="truncate font-medium">{f.name}</span>
                          <Badge variant="outline" className={`shrink-0 text-xs ${TONS[f.kind]}`}>
                            {ROTULO_TIPO[f.kind]}
                          </Badge>
                          {f.kind === 'comissionado' && f.commission_percentage != null && (
                            <Badge variant="secondary" className="shrink-0 text-xs">
                              {f.commission_percentage}%
                            </Badge>
                          )}
                          {!f.active && <Badge variant="secondary" className="shrink-0 text-xs">Inativo</Badge>}
                        </div>

                        <div className="mt-1 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
                          {f.document && <span>{mascara(f.document)}</span>}
                          {f.pix_key && (
                            <span className="flex min-w-0 items-center gap-1">
                              <KeyRound className="h-3 w-3 shrink-0" />
                              <span className="truncate">{f.pix_key}</span>
                            </span>
                          )}
                          {f.bank_name && (
                            <span className="flex items-center gap-1">
                              <Landmark className="h-3 w-3 shrink-0" />
                              {[f.bank_name, f.bank_branch, f.bank_account].filter(Boolean).join(' · ')}
                            </span>
                          )}
                          {f.default_category && <span>Padrão: {f.default_category}</span>}
                        </div>
                      </div>

                      <div className="flex shrink-0 gap-1">
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <Button size="sm" variant="ghost" aria-label={`Editar ${f.name}`}
                              onClick={() => setEditando(f)}>
                              <Pencil className="h-4 w-4" />
                            </Button>
                          </TooltipTrigger>
                          <TooltipContent>Editar</TooltipContent>
                        </Tooltip>
                        <Tooltip>
                          <TooltipTrigger asChild>
                            {/* Desativar, nunca apagar: pagamentos antigos apontam para cá,
                                e apagar deixaria despesas órfãs no histórico. */}
                            <Button size="sm" variant="ghost" disabled={salvar.isPending}
                              aria-label={`${f.active ? 'Desativar' : 'Reativar'} ${f.name}`}
                              onClick={() => alternarAtivo(f)}>
                              {f.active ? <UserX className="h-4 w-4" /> : <UserCheck className="h-4 w-4" />}
                            </Button>
                          </TooltipTrigger>
                          <TooltipContent>
                            {f.active ? 'Desativar (some das listas, histórico fica)' : 'Reativar'}
                          </TooltipContent>
                        </Tooltip>
                      </div>
                    </div>
                  </Card>
                ))}
              </div>
            </TooltipProvider>
          )}
        </div>
      </PageShell>

      <PayeeFormDialog aberto={criando} onFechar={() => setCriando(false)} />
      {editando && (
        <PayeeFormDialog
          key={editando.id}
          aberto
          onFechar={() => setEditando(null)}
          favorecido={editando}
        />
      )}
    </V2Shell>
  );
}
