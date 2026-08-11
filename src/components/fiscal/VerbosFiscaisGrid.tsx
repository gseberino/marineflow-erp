// [F-NFSE-03] Grade do cadastro fiscal por verbo.
//
// Dez linhas. É o total do trabalho que a contabilidade precisa fazer para o catálogo inteiro
// de 243 serviços passar a emitir NFS-e — porque o serviço HERDA daqui quando não tem código
// próprio. Preencher serviço a serviço seria 243 linhas e uma manutenção impossível.
//
// Nasce inteiramente vazia, e isso é proposital: código de tributação errado declara à
// prefeitura serviço que não foi prestado, e ninguém confere isso depois da nota autorizada.
// Nenhum valor aqui foi chutado pelo sistema.
import { useEffect, useState } from 'react';
import {
  useServiceFiscalVerbs,
  useUpdateServiceFiscalVerb,
  type ServiceFiscalVerbRow,
} from '@/hooks/use-service-fiscal';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Check, Info } from 'lucide-react';

/** Campos editáveis de uma linha, como texto — o parse acontece no salvar. */
interface Rascunho {
  default_national_tax_code: string;
  default_cnae: string;
  default_iss_rate: string;
  notes: string;
}

function rascunhoDe(v: ServiceFiscalVerbRow): Rascunho {
  return {
    default_national_tax_code: v.default_national_tax_code ?? '',
    default_cnae: v.default_cnae ?? '',
    default_iss_rate: v.default_iss_rate == null ? '' : String(v.default_iss_rate),
    notes: v.notes ?? '',
  };
}

export function VerbosFiscaisGrid() {
  const { data: verbos, isLoading, error } = useServiceFiscalVerbs();
  const salvar = useUpdateServiceFiscalVerb();
  const [rascunhos, setRascunhos] = useState<Record<string, Rascunho>>({});

  // Só semeia o rascunho quando os dados chegam; não sobrescreve o que está sendo digitado.
  useEffect(() => {
    if (!verbos) return;
    setRascunhos((atual) => {
      const novo = { ...atual };
      for (const v of verbos) if (!novo[v.verb_slug]) novo[v.verb_slug] = rascunhoDe(v);
      return novo;
    });
  }, [verbos]);

  if (error) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-destructive">
          Não foi possível carregar os verbos fiscais: {String((error as any)?.message ?? error)}
        </CardContent>
      </Card>
    );
  }

  const alterada = (v: ServiceFiscalVerbRow) => {
    const r = rascunhos[v.verb_slug];
    if (!r) return false;
    const base = rascunhoDe(v);
    return (Object.keys(base) as (keyof Rascunho)[]).some((k) => r[k] !== base[k]);
  };

  const aplicar = (v: ServiceFiscalVerbRow) => {
    const r = rascunhos[v.verb_slug];
    if (!r) return;
    const vazioVira = (s: string) => (s.trim() === '' ? null : s.trim());
    const taxa = r.default_iss_rate.trim();
    salvar.mutate({
      verb_slug: v.verb_slug,
      default_national_tax_code: vazioVira(r.default_national_tax_code),
      default_cnae: vazioVira(r.default_cnae),
      // Campo em branco = "não definido" (null), não zero. Zero é alíquota válida (MEI), então
      // confundir os dois faria o sistema declarar isenção que ninguém pediu.
      default_iss_rate: taxa === '' ? null : Number(taxa.replace(',', '.')),
      notes: vazioVira(r.notes),
    });
  };

  const pendentes = (verbos ?? []).filter((v) => !v.default_national_tax_code);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Cadastro fiscal por verbo (NFS-e)</CardTitle>
        <CardDescription>
          O serviço herda estes valores quando não tem código próprio. São dez linhas para o
          catálogo inteiro — mexer aqui vale para todos os serviços da mesma atividade.
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        <div className="flex gap-2 rounded-lg border border-amber-500/30 bg-amber-500/5 p-3 text-sm">
          <Info className="mt-0.5 h-4 w-4 shrink-0 text-amber-600 dark:text-amber-500" />
          <div className="space-y-1 text-muted-foreground">
            <p>
              <strong className="text-foreground">Estes códigos vêm da contabilidade.</strong> O
              código de tributação nacional tem 6 dígitos e <em>não</em> é o municipal sem os
              pontos: &quot;14.01&quot; corresponde a <code className="font-mono">140101</code>, não
              a 140100. O CNAE tem 7 dígitos e a alíquota de ISS é a de Itajaí, em percentual.
            </p>
            {pendentes.length > 0 && (
              <p>
                {pendentes.length} de {verbos?.length ?? 0} verbos ainda sem código — os serviços
                que dependem deles não emitem NFS-e.
              </p>
            )}
          </div>
        </div>

        {isLoading ? (
          <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-12 w-full" />)}
          </div>
        ) : (
          <div className="overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[760px]">
              <thead>
                <tr className="border-b bg-muted/50 text-left text-muted-foreground">
                  <th className="px-3 py-2 font-medium">Verbo</th>
                  <th className="px-3 py-2 font-medium">Cód. nacional</th>
                  <th className="px-3 py-2 font-medium">CNAE</th>
                  <th className="px-3 py-2 font-medium">ISS %</th>
                  <th className="px-3 py-2 font-medium">Justificativa</th>
                  <th className="px-3 py-2 w-10" />
                </tr>
              </thead>
              <tbody>
                {(verbos ?? []).map((v) => {
                  const r = rascunhos[v.verb_slug] ?? rascunhoDe(v);
                  const mudou = alterada(v);
                  const set = (campo: keyof Rascunho, valor: string) =>
                    setRascunhos((a) => ({ ...a, [v.verb_slug]: { ...r, [campo]: valor } }));

                  return (
                    <tr key={v.verb_slug} className="border-b last:border-0">
                      <td className="px-3 py-2">
                        <div className="font-medium">{v.name}</div>
                        {/* Quantos serviços herdam daqui: mexer no verbo de 84 serviços não é
                            o mesmo que mexer no que ninguém usa. */}
                        <div className="text-xs text-muted-foreground">
                          {v.servicos === 0 ? 'nenhum serviço' : `${v.servicos} serviço${v.servicos > 1 ? 's' : ''}`}
                        </div>
                      </td>
                      <td className="px-3 py-2">
                        <Input
                          value={r.default_national_tax_code}
                          onChange={(e) => set('default_national_tax_code', e.target.value)}
                          placeholder="140101"
                          inputMode="numeric"
                          maxLength={6}
                          className="h-8 w-24 font-mono text-xs"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <Input
                          value={r.default_cnae}
                          onChange={(e) => set('default_cnae', e.target.value)}
                          placeholder="3313901"
                          inputMode="numeric"
                          maxLength={7}
                          className="h-8 w-24 font-mono text-xs"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <Input
                          value={r.default_iss_rate}
                          onChange={(e) => set('default_iss_rate', e.target.value)}
                          placeholder="5"
                          inputMode="decimal"
                          className="h-8 w-16 text-xs"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <Input
                          value={r.notes}
                          onChange={(e) => set('notes', e.target.value)}
                          placeholder="por que este código"
                          className="h-8 min-w-[140px] text-xs"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <Button
                          size="icon"
                          variant={mudou ? 'default' : 'ghost'}
                          className="h-7 w-7"
                          disabled={!mudou || salvar.isPending}
                          onClick={() => aplicar(v)}
                          title={mudou ? 'Salvar este verbo' : 'Nada alterado'}
                        >
                          <Check className="h-3.5 w-3.5" />
                        </Button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
