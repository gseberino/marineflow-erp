import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Package, Plus, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { useProducts } from '@/hooks/use-products';
import {
  useMaterialRules, useSaveMaterialRule, useApproveMaterialRule, useDeleteMaterialRule,
  ruleInWords, type QtyMode, type ConditionType,
} from '@/hooks/use-survey-material-rules';

/**
 * O que esta pergunta faz entrar no orçamento.
 *
 * A regra vive junto da pergunta porque é dela que ela nasce: perguntar a
 * distância só vale a pena se a distância virar metros de cabo. Antes disso, o
 * levantamento media 14 metros e alguém digitava o cabo na mão depois.
 *
 * A frase em voz alta ("2 m por unidade medida, +15% de folga, de Cabo 35 mm²")
 * é o que se aprova. Ninguém confere nove campos de formulário; todo mundo
 * confere uma frase.
 */
export function SurveyMaterialRules({ templateId }: { templateId: string }) {
  const { data: rules = [] } = useMaterialRules(templateId);
  const { data: produtos = [] } = useProducts();
  const salvar = useSaveMaterialRule();
  const aprovar = useApproveMaterialRule();
  const excluir = useDeleteMaterialRule();

  const [criando, setCriando] = useState(false);
  const [busca, setBusca] = useState('');
  const [nova, setNova] = useState({
    product_id: '', condition_type: 'sempre' as ConditionType, qty_mode: 'fixa' as QtyMode,
    qty_fixed: 1, qty_factor: 1, qty_slack_pct: 0, rationale: '',
  });

  const produtoPorId = useMemo(
    () => new Map((produtos as any[]).map((p) => [p.id, p])),
    [produtos],
  );

  // Busca só quando há o que buscar: jogar 426 produtos num select faz a
  // pessoa desistir e digitar o material na mão de novo.
  const achados = useMemo(() => {
    const termo = busca.trim().toLowerCase();
    if (termo.length < 2) return [];
    return (produtos as any[])
      .filter((p) => p.active && p.name?.toLowerCase().includes(termo))
      .slice(0, 8);
  }, [produtos, busca]);

  function criar() {
    if (!nova.product_id) return;
    salvar.mutate(
      { ...nova, template_id: templateId, origin: 'human', rationale: nova.rationale.trim() || null },
      {
        onSuccess: () => {
          setCriando(false); setBusca('');
          setNova({
            product_id: '', condition_type: 'sempre', qty_mode: 'fixa',
            qty_fixed: 1, qty_factor: 1, qty_slack_pct: 0, rationale: '',
          });
          toast.success('Regra criada. Ative para valer no orçamento.');
        },
        onError: (e: any) => toast.error(e?.message || 'Erro ao criar regra'),
      },
    );
  }

  return (
    <div className="mt-2 space-y-2 rounded-md border border-dashed p-2">
      <p className="flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
        <Package className="h-3 w-3" /> Material que esta resposta indica
      </p>

      {rules.length === 0 && !criando && (
        <p className="text-xs text-muted-foreground">
          Nenhuma regra ainda — a resposta é só informação, não vira item do orçamento.
        </p>
      )}

      {rules.map((r) => {
        const p = produtoPorId.get(r.product_id);
        return (
          <div key={r.id} className="flex items-start gap-2 rounded-md bg-muted/40 p-2">
            <div className="min-w-0 flex-1 space-y-1">
              <p className="text-xs leading-snug">{ruleInWords(r, p?.name, p?.unit)}</p>
              {r.rationale && (
                <p className="text-[11px] leading-snug text-muted-foreground">{r.rationale}</p>
              )}
              <Badge
                variant={r.active ? 'default' : 'outline'}
                className="text-[10px]"
              >
                {r.active ? 'em uso' : r.origin === 'ai' ? 'proposta da IA — aguarda você' : 'inativa'}
              </Badge>
            </div>
            <div className="flex shrink-0 items-center gap-1">
              <Button
                size="sm" variant={r.active ? 'ghost' : 'outline'} className="h-7 text-xs"
                onClick={() =>
                  aprovar.mutate({ id: r.id, active: !r.active }, {
                    onSuccess: () => toast.success(r.active ? 'Regra desligada.' : 'Regra em uso.'),
                    onError: (e: any) => toast.error(e?.message || 'Erro'),
                  })}
              >
                {r.active ? 'Desligar' : 'Ativar'}
              </Button>
              <Button
                size="sm" variant="ghost" className="h-7 w-7 p-0"
                onClick={() => excluir.mutate(r.id)}
              >
                <Trash2 className="h-3.5 w-3.5 text-muted-foreground" />
              </Button>
            </div>
          </div>
        );
      })}

      {criando ? (
        <div className="space-y-2 rounded-md border p-2">
          <Input
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            placeholder="Buscar o produto pelo nome"
            className="h-8 text-xs"
          />
          {achados.map((p) => (
            <button
              key={p.id}
              className={`block w-full truncate rounded px-2 py-1 text-left text-xs hover:bg-muted ${
                nova.product_id === p.id ? 'bg-muted font-medium' : ''
              }`}
              onClick={() => setNova((n) => ({ ...n, product_id: p.id }))}
            >
              {p.name} <span className="text-muted-foreground">({p.unit || '—'})</span>
            </button>
          ))}

          <div className="grid grid-cols-2 gap-2">
            <Select
              value={nova.qty_mode}
              onValueChange={(v) => setNova((n) => ({ ...n, qty_mode: v as QtyMode }))}
            >
              <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="fixa">Quantidade fixa</SelectItem>
                <SelectItem value="proporcional">Por unidade medida</SelectItem>
                <SelectItem value="por_unidade">Por item contado</SelectItem>
              </SelectContent>
            </Select>
            <Input
              type="number" min={0} step="0.1"
              className="h-8 text-xs"
              value={nova.qty_mode === 'fixa' ? nova.qty_fixed : nova.qty_factor}
              onChange={(e) => {
                const v = Number(e.target.value);
                setNova((n) => (n.qty_mode === 'fixa' ? { ...n, qty_fixed: v } : { ...n, qty_factor: v }));
              }}
              placeholder="quanto"
            />
          </div>

          <Input
            type="number" min={0} max={100}
            className="h-8 text-xs"
            value={nova.qty_slack_pct}
            onChange={(e) => setNova((n) => ({ ...n, qty_slack_pct: Number(e.target.value) }))}
            placeholder="folga %"
          />

          <Textarea
            value={nova.rationale}
            onChange={(e) => setNova((n) => ({ ...n, rationale: e.target.value }))}
            rows={2}
            className="text-xs"
            placeholder="Por que essa conta. Ex.: o positivo vai e o negativo volta, por isso 2 m por metro medido."
          />

          <div className="flex items-center gap-2">
            <Button size="sm" variant="ghost" className="h-7 text-xs" onClick={() => setCriando(false)}>
              Cancelar
            </Button>
            <Button
              size="sm" className="h-7 text-xs"
              disabled={!nova.product_id || salvar.isPending}
              onClick={criar}
            >
              Criar regra
            </Button>
          </div>
        </div>
      ) : (
        <Button
          size="sm" variant="outline" className="h-7 text-xs"
          onClick={() => setCriando(true)}
        >
          <Plus className="mr-1 h-3 w-3" /> Ligar material a esta pergunta
        </Button>
      )}
    </div>
  );
}
