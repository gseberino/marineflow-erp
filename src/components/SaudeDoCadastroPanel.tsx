// Saúde do cadastro de fornecedores.
//
// A tela NÃO pergunta "qual é o apelido deste fornecedor?". Perguntar isso 41 vezes é
// trabalho de digitação disfarçado de decisão. Ela mostra o que está errado, a EVIDÊNCIA
// que sustenta a acusação, e propõe a correção — para o gestor aceitar em lote quando o
// diagnóstico é óbvio, e olhar de perto só onde há dúvida de verdade.
import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Skeleton } from '@/components/ui/skeleton';
import { useSaudeDoCadastro, useCorrigirCadastro } from '@/hooks/use-cadastro-saude';
import type { ProblemaDeCadastro } from '@/lib/cadastro-saude';
import { HeartPulse, AlertTriangle, Info, Users2 } from 'lucide-react';

const ROTULO_DO_TIPO: Record<string, string> = {
  fantasia_generica: 'Apelido que não identifica',
  fantasia_igual_razao: 'Apelido repete a razão social',
  sem_documento: 'Sem CNPJ/CPF',
  documento_invalido: 'CNPJ/CPF inválido',
  inerte: 'Nunca usado',
};

export function SaudeDoCadastroPanel() {
  const { data, isLoading } = useSaudeDoCadastro();
  const corrigir = useCorrigirCadastro();
  const [marcados, setMarcados] = useState<Set<string>>(new Set());

  const problemas = data?.problemas ?? [];
  const porTipo = useMemo(() => {
    const m = new Map<string, ProblemaDeCadastro[]>();
    for (const p of problemas) m.set(p.tipo, [...(m.get(p.tipo) ?? []), p]);
    // Alta gravidade primeiro: é a fila de trabalho, não um relatório.
    return [...m.entries()].sort((a, b) => {
      const peso = { alta: 0, media: 1, baixa: 2 } as const;
      return peso[a[1][0].gravidade] - peso[b[1][0].gravidade];
    });
  }, [problemas]);

  const chave = (p: ProblemaDeCadastro) => `${p.fornecedorId}|${p.tipo}`;
  const corrigiveis = problemas.filter((p) => p.correcao);
  const selecionados = corrigiveis.filter((p) => marcados.has(chave(p)));

  const aplicar = (lista: ProblemaDeCadastro[]) => {
    const correcoes = lista
      .filter((p) => p.correcao)
      .map((p) => ({ id: p.fornecedorId, campo: p.correcao!.campo, valor: p.correcao!.valor }));
    if (correcoes.length === 0) return;
    corrigir.mutate({ correcoes }, { onSuccess: () => setMarcados(new Set()) });
  };

  if (isLoading) {
    return (
      <div className="space-y-3">
        <Card className="p-4">
          <h3 className="flex items-center gap-2 font-semibold">
            <HeartPulse className="h-4 w-4 text-muted-foreground" />
            Saúde do cadastro
          </h3>
          <p className="mt-1 text-sm text-muted-foreground">Conferindo os fornecedores contra o extrato…</p>
        </Card>
        <Skeleton className="h-20 rounded-xl" />
      </div>
    );
  }

  if (problemas.length === 0 && (data?.duplicados.length ?? 0) === 0) {
    return (
      <Card className="p-8 text-center">
        <p className="text-muted-foreground">
          Nada a corrigir nos {data?.total ?? 0} fornecedores. Quando um cadastro puder
          atrapalhar o reconhecimento — apelido que identifica outra gente, documento
          inválido, duplicata —, ele aparece aqui com a evidência.
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      <Card className="p-4">
        <h3 className="flex items-center gap-2 font-semibold">
          <HeartPulse className="h-4 w-4 text-primary" />
          Saúde do cadastro
        </h3>
        <p className="mt-1 text-sm text-muted-foreground">
          <strong>{problemas.length}</strong> apontamento(s) em {data?.total} fornecedores.
          Cada um vem com o dado que sustenta a acusação — não com um palpite sobre o nome.
        </p>
      </Card>

      {selecionados.length > 0 && (
        <div className="sticky top-2 z-10 flex flex-wrap items-center justify-between gap-2 rounded-lg border bg-background/95 p-2 shadow-sm backdrop-blur">
          <span className="text-sm"><strong>{selecionados.length}</strong> selecionado(s)</span>
          <div className="flex gap-2">
            <Button size="sm" variant="ghost" onClick={() => setMarcados(new Set())}>Limpar</Button>
            <Button size="sm" disabled={corrigir.isPending} onClick={() => aplicar(selecionados)}>
              Aplicar {selecionados.length}
            </Button>
          </div>
        </div>
      )}

      {porTipo.map(([tipo, lista]) => {
        const g = lista[0].gravidade;
        const podeEmLote = lista.every((p) => p.correcao);
        return (
          <Card key={tipo} className={`p-3 ${g === 'alta' ? 'border-destructive/40 bg-destructive/5' : ''}`}>
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div className="min-w-0 flex-1">
                <p className="flex flex-wrap items-center gap-2 font-medium">
                  {g === 'alta' ? <AlertTriangle className="h-4 w-4 text-destructive" />
                    : <Info className="h-4 w-4 text-muted-foreground" />}
                  {ROTULO_DO_TIPO[tipo] ?? tipo}
                  <Badge variant="secondary" className="text-xs">{lista.length}</Badge>
                </p>
                <p className="mt-1 break-words text-xs text-muted-foreground">{lista[0].sugestao}</p>
              </div>
              {/* Aceitar em lote existe porque quase todos caem no mesmo padrão. Onde não
                  há correção automática (documento, por exemplo), o botão não aparece —
                  prometer um clique que não resolve é pior que não prometer. */}
              {podeEmLote && (
                <Button size="sm" variant="outline" disabled={corrigir.isPending}
                  onClick={() => aplicar(lista)}>
                  Aplicar nas {lista.length}
                </Button>
              )}
            </div>

            <ul className="mt-2 max-h-72 space-y-1 overflow-y-auto text-sm">
              {lista.map((p) => (
                <li key={chave(p)} className="flex min-w-0 items-start gap-2 rounded border p-2">
                  {p.correcao && (
                    <Checkbox
                      className="mt-0.5 shrink-0"
                      checked={marcados.has(chave(p))}
                      onCheckedChange={(v) => setMarcados((s) => {
                        const n = new Set(s);
                        if (v === true) n.add(chave(p)); else n.delete(chave(p));
                        return n;
                      })}
                      aria-label={`Selecionar ${p.fornecedor}`}
                    />
                  )}
                  <span className="min-w-0 flex-1 break-words">
                    <strong>{p.fornecedor}</strong>
                    <span className="block text-xs text-muted-foreground">{p.diagnostico}</span>
                    <span className="block text-xs text-muted-foreground">↳ {p.evidencia}</span>
                  </span>
                </li>
              ))}
            </ul>
          </Card>
        );
      })}

      {(data?.duplicados.length ?? 0) > 0 && (
        <Card className="p-3">
          <p className="flex flex-wrap items-center gap-2 font-medium">
            <Users2 className="h-4 w-4 text-muted-foreground" />
            Possíveis duplicatas
            <Badge variant="secondary" className="text-xs">{data!.duplicados.length}</Badge>
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            Dois cadastros para o mesmo fornecedor racham o histórico aprendido em dois: o
            sistema aprende metade em cada e não reconhece direito nenhum dos dois.
            <strong> Juntar mexe em lançamentos já feitos</strong>, então aqui eu só aponto —
            a fusão precisa da sua decisão caso a caso.
          </p>
          <ul className="mt-2 space-y-1 text-sm">
            {data!.duplicados.map((d) => (
              <li key={d.chave} className="rounded border p-2">
                <span className="text-xs text-muted-foreground">{d.motivo}</span>
                <ul className="mt-1">
                  {d.membros.map((m) => (
                    <li key={m.id} className="flex flex-wrap justify-between gap-2">
                      <span className="min-w-0 break-words">{m.name}</span>
                      <span className="shrink-0 text-xs text-muted-foreground">
                        {m.lancamentos} lançamento(s)
                      </span>
                    </li>
                  ))}
                </ul>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  );
}
