import { useQuery } from '@tanstack/react-query';
import { Mail, FileCheck2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';
import { useI18n } from '@/i18n';

/**
 * "Notas recebidas por e-mail" (08/10/2026, etapa 4 do e-mail no assistente).
 *
 * A NF-e que um fornecedor manda para financeiro@ ou gustavo@ é lida pela função email-imap,
 * conferida por dígito verificador e por ser destinada à HBR, e aparece aqui. "Conferir e importar"
 * entra na MESMA conferência do arquivo que a pessoa sobe — nada vai para o estoque sozinho. Some da
 * lista assim que a nota é importada (fiscal_notes.nfe_key).
 */
export interface NotaDoEmail {
  anexoId: string;
  chave: string;
  emitente: string | null;
  numero: string | null;
  valor: number | null;
  data: string | null;
  recebidaEm: string;
  caixa: string | null;
}

export function useNotasRecebidasPorEmail() {
  return useQuery({
    queryKey: ['notas-recebidas-por-email'],
    queryFn: async (): Promise<NotaDoEmail[]> => {
      const desde = new Date(Date.now() - 120 * 86400_000).toISOString();
      const { data, error } = await supabase
        .from('email_messages')
        .select('received_at, dados_extraidos, email_accounts(address)')
        .not('dados_extraidos', 'is', null)
        .gte('received_at', desde)
        .order('received_at', { ascending: false })
        .limit(200);
      if (error) throw error;
      const notas: NotaDoEmail[] = [];
      for (const m of (data ?? []) as any[]) {
        for (const n of (m.dados_extraidos?.nfes ?? []) as any[]) {
          if (!n?.para_empresa || !n?.anexo_id || !n?.chave) continue;
          notas.push({
            anexoId: n.anexo_id, chave: n.chave, emitente: n.emitente ?? null, numero: n.numero ?? null,
            valor: n.valor ?? null, data: n.data ?? null, recebidaEm: m.received_at, caixa: m.email_accounts?.address ?? null,
          });
        }
      }
      if (notas.length === 0) return [];
      // Já importadas saem da lista.
      const { data: importadas, error: iErr } = await supabase
        .from('fiscal_notes').select('nfe_key').in('nfe_key', notas.map((n) => n.chave));
      if (iErr) throw iErr;
      const jaTem = new Set(((importadas ?? []) as { nfe_key: string }[]).map((x) => x.nfe_key));
      const vistas = new Set<string>();
      return notas.filter((n) => !jaTem.has(n.chave) && !vistas.has(n.chave) && vistas.add(n.chave));
    },
  });
}

export function NotasRecebidasPorEmail({ onConferir, ocupado }: { onConferir: (anexoId: string) => void; ocupado: boolean }) {
  const { formatCurrency, formatDate } = useI18n();
  const { data: notas = [], isLoading } = useNotasRecebidasPorEmail();
  if (isLoading || notas.length === 0) return null;
  return (
    <Card data-testid="notas-por-email">
      <CardContent className="space-y-2 p-4">
        <div className="flex items-center gap-2">
          <Mail className="h-4 w-4 text-primary" />
          <h3 className="font-semibold">Notas recebidas por e-mail ({notas.length})</h3>
        </div>
        <p className="text-xs text-muted-foreground">
          Chegaram em financeiro@ ou gustavo@, destinadas à HBR, com a chave conferida. Nada entra no estoque até você conferir e confirmar.
        </p>
        <ul className="divide-y">
          {notas.map((n) => (
            <li key={n.chave} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
              <div className="min-w-0">
                <div className="font-medium">{n.emitente ?? 'Emitente não identificado'} · NF-e {n.numero ?? '?'}</div>
                <div className="text-xs text-muted-foreground">
                  {n.valor != null ? formatCurrency(n.valor) : 'valor ?'}
                  {n.data ? ` · emitida em ${formatDate(n.data)}` : ''}
                  {` · chegou em ${formatDate(n.recebidaEm)}`}
                  {n.caixa ? ` · ${n.caixa}` : ''}
                </div>
              </div>
              <Button size="sm" variant="outline" className="gap-1.5" disabled={ocupado} onClick={() => onConferir(n.anexoId)}>
                <FileCheck2 className="h-3.5 w-3.5" /> Conferir e importar
              </Button>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
