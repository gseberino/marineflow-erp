// Regras do financeiro — onde o gestor ENSINA o sistema em vez de corrigi-lo toda vez.
//
// A diferença entre uma ferramenta que ajuda e uma que cansa está aqui: sem este lugar, o
// gestor corrige a mesma classificação quarenta vezes e o sistema nunca aprende. Com ele,
// uma frase ("PIX para Gustavo Seberino é sempre pró-labore") resolve todas as próximas.
//
// O sistema também PROPÕE regras, a partir do que viu repetir. Elas chegam como sugestão —
// nunca ativas —, porque um padrão pode ser três erros iguais.
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { useI18n } from '@/i18n';
import { useSuppliers } from '@/hooks/use-suppliers';
import {
  useFinanceRules, useSalvarRegra, useMudarStatusRegra, useProporRegras, useLancamentosDaRegra,
  type RegraFinanceira,
} from '@/hooks/use-finance-review';
import { useFinancialCategories } from '@/hooks/use-financial-categories';
import { Sparkles, Plus, Pause, Play, Check, X, Pencil, Wand2, Receipt, ChevronDown } from 'lucide-react';

const ROTULO_ALVO: Record<RegraFinanceira['match_type'], string> = {
  document: 'CNPJ/CPF',
  supplier: 'Fornecedor',
  counterparty: 'Nome de quem recebe',
  text: 'Texto no histórico',
};

/** Frase legível da regra. O gestor precisa reconhecer o que ensinou sem decifrar campos. */
export function frasearRegra(r: RegraFinanceira, nomeFornecedor?: string): string {
  const alvo = r.match_type === 'supplier'
    ? (nomeFornecedor || 'este fornecedor')
    : r.match_type === 'document'
      ? `quem tem o CNPJ/CPF ${r.match_value}`
      : r.match_type === 'counterparty'
        ? `pagamentos para "${r.match_value}"`
        : `histórico com "${r.match_value}"`;

  const faixa = r.min_amount != null && r.max_amount != null
    ? ` entre R$ ${r.min_amount} e R$ ${r.max_amount}`
    : r.min_amount != null ? ` acima de R$ ${r.min_amount}`
    : r.max_amount != null ? ` até R$ ${r.max_amount}` : '';

  return `${alvo}${faixa} → ${r.set_category ?? '—'}`;
}

/**
 * As despesas que embasam a regra.
 *
 * "As últimas 5 foram lançadas como Ferramentas, sem exceção" é um resumo — e resumo
 * esconde o que muda a decisão: um dos cinco pode ser de outro fornecedor de nome
 * parecido, ou de valor tão fora da curva que denuncia classificação apressada. Sem ver
 * data, valor e para quem foi, aceitar a regra é confiar, não decidir.
 */
function HistoricoDaRegra({ regra }: { regra: RegraFinanceira }) {
  const { formatCurrency, formatDate } = useI18n();
  const { data: lancamentos = [], isLoading } = useLancamentosDaRegra(regra);

  if (isLoading) return <Skeleton className="mt-2 h-24 rounded-md" />;

  if (lancamentos.length === 0) {
    return (
      <p className="mt-2 rounded-md border border-dashed p-3 text-xs text-muted-foreground">
        Nenhum lançamento encontrado para este alvo. A regra continua válida para o que
        vier, mas não há histórico que a sustente — vale conferir antes de aceitar.
      </p>
    );
  }

  const total = lancamentos.reduce((s, l) => s + l.amount, 0);
  const categorias = new Set(lancamentos.map((l) => l.expense_category).filter(Boolean));

  return (
    <div className="mt-2 space-y-2">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
        <span><b className="text-foreground">{lancamentos.length}</b> lançamento(s)</span>
        <span>Total <b className="text-foreground">{formatCurrency(total)}</b></span>
        {/* Mais de uma categoria no histórico é o sinal de que a unanimidade não é real. */}
        {categorias.size > 1 && (
          <span className="text-warning">
            Atenção: {categorias.size} categorias diferentes neste histórico
          </span>
        )}
      </div>

      <div className="overflow-x-auto rounded-md border">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b bg-muted/40 text-muted-foreground">
              <th className="whitespace-nowrap p-2 text-left font-medium">Data</th>
              <th className="whitespace-nowrap p-2 text-left font-medium">Para quem</th>
              <th className="whitespace-nowrap p-2 text-left font-medium">Descrição</th>
              <th className="whitespace-nowrap p-2 text-left font-medium">Categoria</th>
              <th className="whitespace-nowrap p-2 text-right font-medium">Valor</th>
            </tr>
          </thead>
          <tbody>
            {lancamentos.map((l) => (
              <tr key={l.id} className="border-b last:border-0">
                <td className="whitespace-nowrap p-2 tabular-nums">{formatDate(l.issue_date)}</td>
                <td className="max-w-[13rem] p-2">
                  {/* Operação do próprio banco (juros, tarifa) não tem favorecido. Dizer
                      isso é melhor que uma célula vazia, que parece dado faltando. */}
                  <span className="block truncate">
                    {l.fornecedor || l.contraparte || l.supplier_name
                      || <span className="italic text-muted-foreground">sem favorecido — operação do banco</span>}
                  </span>
                  {(l.documento || l.banco || l.meio) && (
                    <span className="block truncate text-[11px] text-muted-foreground">
                      {[l.documento && formatarDoc(l.documento), l.banco && `banco ${l.banco}`, l.meio]
                        .filter(Boolean).join(' · ')}
                    </span>
                  )}
                </td>
                <td className="max-w-[15rem] p-2"><span className="block truncate">{l.description}</span></td>
                <td className="whitespace-nowrap p-2">{l.expense_category ?? '—'}</td>
                <td className="whitespace-nowrap p-2 text-right font-medium tabular-nums">
                  {formatCurrency(l.amount)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/** CPF/CNPJ com máscara: dígitos crus não se conferem de olho. */
function formatarDoc(doc: string): string {
  if (doc.length === 14) return doc.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, '$1.$2.$3/$4-$5');
  if (doc.length === 11) return doc.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, '$1.$2.$3-$4');
  return doc;
}

interface EditorProps {
  aberto: boolean;
  onFechar: () => void;
  regra: Partial<RegraFinanceira> | null;
}

export function EditorDeRegra({ aberto, onFechar, regra }: EditorProps) {
  const salvar = useSalvarRegra();
  const { data: fornecedores = [] } = useSuppliers();
  const { data: categorias = [] } = useFinancialCategories('payable');

  const [tipo, setTipo] = useState<RegraFinanceira['match_type']>(regra?.match_type ?? 'counterparty');
  const [valor, setValor] = useState(regra?.match_value ?? '');
  const [categoria, setCategoria] = useState(regra?.set_category ?? '');
  const [autonomia, setAutonomia] = useState<RegraFinanceira['autonomy']>(regra?.autonomy ?? 'suggest');
  const [minimo, setMinimo] = useState(regra?.min_amount != null ? String(regra.min_amount) : '');
  const [maximo, setMaximo] = useState(regra?.max_amount != null ? String(regra.max_amount) : '');

  const grupoDa = (nome: string) => categorias.find((c) => c.name === nome)?.dre_group ?? null;

  const podeSalvar = valor.trim().length > 0 && categoria.length > 0;

  const confirmar = () => {
    salvar.mutate({
      id: regra?.id,
      match_type: tipo,
      match_value: valor.trim(),
      direction: 'debit',
      set_category: categoria,
      set_dre_group: grupoDa(categoria),
      set_supplier_id: tipo === 'supplier' ? valor.trim() : null,
      autonomy: autonomia,
      min_amount: minimo ? Number(minimo) : null,
      max_amount: maximo ? Number(maximo) : null,
      status: 'active',
      origin: regra?.origin ?? 'user',
    }, { onSuccess: onFechar });
  };

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{regra?.id ? 'Editar regra' : 'Ensinar uma regra'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <Label className="text-xs">Reconhecer por</Label>
              <Select value={tipo} onValueChange={(v) => { setTipo(v as never); setValor(''); }}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {Object.entries(ROTULO_ALVO).map(([k, v]) => (
                    <SelectItem key={k} value={k}>{v}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div>
              <Label className="text-xs">
                {tipo === 'supplier' ? 'Qual fornecedor' : tipo === 'document' ? 'CNPJ ou CPF' : tipo === 'text' ? 'Trecho do histórico' : 'Nome de quem recebe'}
              </Label>
              {tipo === 'supplier' ? (
                <Select value={valor} onValueChange={setValor}>
                  <SelectTrigger><SelectValue placeholder="Escolher" /></SelectTrigger>
                  <SelectContent>
                    {fornecedores.map((f: any) => (
                      <SelectItem key={f.id} value={f.id}>{f.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <Input
                  value={valor}
                  onChange={(e) => setValor(e.target.value)}
                  placeholder={tipo === 'text' ? 'ex.: POSTO IPIRANGA' : 'ex.: GUSTAVO SEBERINO DA SILVA'}
                />
              )}
            </div>
          </div>

          <div>
            <Label className="text-xs">Classificar sempre como</Label>
            <Select value={categoria} onValueChange={setCategoria}>
              <SelectTrigger><SelectValue placeholder="Escolher categoria" /></SelectTrigger>
              <SelectContent>
                {categorias.map((c) => <SelectItem key={c.name} value={c.name}>{c.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          {/* Faixa opcional: "acima de X é investimento, abaixo é manutenção" é uma
              distinção que o gestor faz de cabeça e que o sistema não tem como deduzir. */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-xs">Só a partir de (opcional)</Label>
              <Input type="number" inputMode="decimal" value={minimo} onChange={(e) => setMinimo(e.target.value)} placeholder="R$" />
            </div>
            <div>
              <Label className="text-xs">Só até (opcional)</Label>
              <Input type="number" inputMode="decimal" value={maximo} onChange={(e) => setMaximo(e.target.value)} placeholder="R$" />
            </div>
          </div>

          <div>
            <Label className="text-xs">O quanto ela pode agir sozinha</Label>
            <Select value={autonomia} onValueChange={(v) => setAutonomia(v as never)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="suggest">Preencher e esperar meu OK</SelectItem>
                <SelectItem value="apply">Lançar sozinha (fica marcado, dá para desfazer)</SelectItem>
              </SelectContent>
            </Select>
            <p className="mt-1 text-xs text-muted-foreground">
              {autonomia === 'apply'
                ? 'A despesa nasce pronta e aparece separada, como lançada por regra.'
                : 'A despesa fica na fila já classificada, aguardando sua confirmação.'}
            </p>
          </div>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={onFechar}>Cancelar</Button>
          <Button disabled={!podeSalvar || salvar.isPending} onClick={confirmar}>Salvar regra</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function FinanceRulesPanel() {
  const { formatDate } = useI18n();
  const { data: regras = [], isLoading } = useFinanceRules();
  const { data: fornecedores = [] } = useSuppliers();
  const mudarStatus = useMudarStatusRegra();
  const propor = useProporRegras();

  const [editando, setEditando] = useState<Partial<RegraFinanceira> | null>(null);
  const [abertoNovo, setAbertoNovo] = useState(false);

  const nomeDo = (id: string | null) =>
    (fornecedores as any[]).find((f) => f.id === id)?.name as string | undefined;

  const propostas = regras.filter((r) => r.status === 'proposed');
  const ativas = regras.filter((r) => r.status === 'active');
  const pausadas = regras.filter((r) => r.status === 'paused');

  if (isLoading) {
    return <div className="space-y-2">{[...Array(3)].map((_, i) => <Skeleton key={i} className="h-16 rounded-xl" />)}</div>;
  }

  const linha = (r: RegraFinanceira) => (
    <Card key={r.id} className="p-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="truncate font-medium">
              {frasearRegra(r, r.match_type === 'supplier' ? nomeDo(r.match_value) : undefined)}
            </span>
            {r.origin === 'ai' && <Badge variant="outline" className="shrink-0 text-xs">Sugerida</Badge>}
            {r.autonomy === 'apply' && (
              <Badge variant="secondary" className="shrink-0 text-xs">Lança sozinha</Badge>
            )}
          </div>
          <p className="mt-1 text-xs text-muted-foreground">
            {ROTULO_ALVO[r.match_type]}
            {r.times_applied > 0 && ` · aplicada ${r.times_applied}x`}
            {r.last_applied_at && ` · última vez em ${formatDate(r.last_applied_at)}`}
          </p>
          {r.reasoning && (
            <p className="mt-1 rounded-md bg-muted/50 p-2 text-xs text-muted-foreground">{r.reasoning}</p>
          )}

          {/* Aberto por padrão nas SUGERIDAS: é onde a decisão acontece, e evidência que
              exige um clique a mais é evidência que ninguém lê antes de aceitar. */}
          <Collapsible defaultOpen={r.status === 'proposed'}>
            <CollapsibleTrigger asChild>
              <button type="button" className="mt-1 inline-flex items-center gap-1 text-xs text-primary hover:underline">
                <Receipt className="h-3 w-3" />
                Ver os lançamentos que embasam
                <ChevronDown className="h-3 w-3" />
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <HistoricoDaRegra regra={r} />
            </CollapsibleContent>
          </Collapsible>
        </div>

        <div className="flex shrink-0 gap-1">
          {r.status === 'proposed' ? (
            <>
              <Button size="sm" variant="outline" title="Aceitar"
                onClick={() => mudarStatus.mutate({ id: r.id, status: 'active' })}>
                <Check className="h-4 w-4" />
              </Button>
              <Button size="sm" variant="ghost" title="Recusar"
                onClick={() => mudarStatus.mutate({ id: r.id, status: 'rejected' })}>
                <X className="h-4 w-4" />
              </Button>
            </>
          ) : (
            <>
              <Button size="sm" variant="ghost" title="Editar" onClick={() => setEditando(r)}>
                <Pencil className="h-4 w-4" />
              </Button>
              <Button size="sm" variant="ghost"
                title={r.status === 'active' ? 'Pausar' : 'Reativar'}
                onClick={() => mudarStatus.mutate({ id: r.id, status: r.status === 'active' ? 'paused' : 'active' })}>
                {r.status === 'active' ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
              </Button>
            </>
          )}
        </div>
      </div>
    </Card>
  );

  return (
    <div className="space-y-4">
      <Card className="p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <h3 className="flex items-center gap-2 font-semibold">
              <Sparkles className="h-4 w-4 text-primary" />
              O que você ensinou ao sistema
            </h3>
            <p className="mt-1 text-sm text-muted-foreground">
              Uma regra vale para tudo que vier depois. Em vez de corrigir a mesma
              classificação toda semana, você diz uma vez.
            </p>
          </div>
          <div className="flex shrink-0 flex-wrap gap-2">
            <Button variant="outline" size="sm" disabled={propor.isPending} onClick={() => propor.mutate()}>
              <Wand2 className="mr-2 h-4 w-4" />
              Sugerir regras
            </Button>
            <Button size="sm" onClick={() => setAbertoNovo(true)}>
              <Plus className="mr-2 h-4 w-4" />
              Nova regra
            </Button>
          </div>
        </div>
      </Card>

      {propostas.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm font-medium">
            O sistema notou um padrão e sugere ({propostas.length})
          </p>
          {propostas.map(linha)}
        </div>
      )}

      {ativas.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm font-medium">Valendo agora ({ativas.length})</p>
          {ativas.map(linha)}
        </div>
      )}

      {pausadas.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm font-medium text-muted-foreground">Pausadas ({pausadas.length})</p>
          {pausadas.map(linha)}
        </div>
      )}

      {regras.length === 0 && (
        <Card className="p-8 text-center">
          <p className="text-muted-foreground">
            Nenhuma regra ainda. Use <strong>Sugerir regras</strong> para o sistema olhar o
            que você já classificou e propor as repetições que encontrar.
          </p>
        </Card>
      )}

      {/* key remonta o editor a cada regra diferente: os campos são estado local
          inicializado na montagem, e sem isto o formulário abriria com os dados da regra
          anterior. */}
      <EditorDeRegra key={abertoNovo ? 'novo' : 'fechado'} aberto={abertoNovo} onFechar={() => setAbertoNovo(false)} regra={null} />
      {editando && (
        <EditorDeRegra key={editando.id ?? 'edit'} aberto onFechar={() => setEditando(null)} regra={editando} />
      )}
    </div>
  );
}
