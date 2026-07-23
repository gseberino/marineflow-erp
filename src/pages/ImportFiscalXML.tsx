import { useEffect, useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  Upload, FileText, CheckCircle2, AlertCircle, Loader2, Package, Banknote, RefreshCw, Undo2, ArrowLeft,
} from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { useSuppliers } from '@/hooks/use-suppliers';
import { usePurchaseOrders, usePurchaseOrder } from '@/hooks/use-purchase-orders';
import { useI18n } from '@/i18n';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { useProducts } from '@/hooks/use-products';
import { parseNfeSupplierNote } from '@/lib/nfe-xml-parser';
import { extractInvokeErrorMessage } from '@/lib/invoke-error';

// ── Types ──────────────────────────────────────────────────────────────────
interface NFeItem {
  index: number;
  sku_supplier: string | null;
  description: string | null;
  ncm: string | null;
  cfop: string | null;
  unit: string | null;
  quantity: number;
  unit_price: number;
  total_price: number;
  icms_value: number;
  // Extraídos do XML a partir da correção do parser: GTIN (casamento por código
  // de barras), origem da mercadoria e desconto do item.
  barcode?: string | null;
  origin?: string | null;
  discount?: number;
}

interface NFeParsed {
  noteId: string;
  nfeKey: string | null;
  nfeNumber: string | null;
  issueDate: string | null;
  issuerName: string | null;
  issuerCNPJ: string | null;
  totalNF: number;
  totalICMS: number;
  totalIPI: number;
  totalPIS: number;
  totalCOFINS: number;
  items: NFeItem[];
  // Emitente completo (IE, fantasia, endereço) — permite identificar o
  // fornecedor pelo CNPJ do XML ou cadastrá-lo já preenchido.
  issuer?: {
    name: string | null;
    document: string | null;
    tradeName: string | null;
    stateRegistration: string | null;
    address: Record<string, string | null>;
  } | null;
}

// ── Status badge helper ────────────────────────────────────────────────────
const STATUS_MAP: Record<string, { label: string; className: string }> = {
  pending:   { label: 'Pendente',   className: 'bg-amber-100 text-amber-800' },
  confirmed: { label: 'Confirmada', className: 'bg-success/15 text-success' },
  cancelled: { label: 'Cancelada',  className: 'bg-destructive/15 text-destructive' },
  error:     { label: 'Erro',       className: 'bg-destructive/15 text-destructive' },
};

// ── Hooks ──────────────────────────────────────────────────────────────────
function useFiscalNotes() {
  return useQuery({
    queryKey: ['fiscal_notes'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('fiscal_notes')
        .select('id, nfe_key, nfe_number, issuer_name, issued_at, total_amount, tax_icms, status, confirmed_at, created_at')
        .order('created_at', { ascending: false })
        .limit(100);
      if (error) throw error;
      return data || [];
    },
    staleTime: 30_000,
  });
}

// ── Main Page ──────────────────────────────────────────────────────────────
export default function ImportFiscalXML() {
  const { formatCurrency, formatDate } = useI18n();
  const qc = useQueryClient();
  const navigate = useNavigate();

  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [parsed, setParsed] = useState<NFeParsed | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [supplierId, setSupplierId] = useState<string>('__none');
  const [showConfirm, setShowConfirm] = useState(false);
  const [manualMappings, setManualMappings] = useState<Record<string, string>>({});
  const [returningNoteId, setReturningNoteId] = useState<string | null>(null);
  // Conferência: simulação read-only do que a confirmação faria (preview_nfe_import).
  const [preview, setPreview] = useState<any | null>(null);
  const [loadingPreview, setLoadingPreview] = useState(false);
  // Três vias: vincular a nota ao pedido de compra que a originou.
  const [purchaseOrderId, setPurchaseOrderId] = useState<string>('__none');
  const [creatingSupplier, setCreatingSupplier] = useState(false);
  const [revertingId, setRevertingId] = useState<string | null>(null);
  // Numa nota com dezenas de itens, os que casaram com certeza são ruído. Este
  // filtro deixa só o que merece um olhar: item que será criado, casado pela
  // descrição (fuzzy, menos certo) ou com divergência de custo/unidade/NCM.
  const [soAtencao, setSoAtencao] = useState(false);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const precisaAtencao = (pv: any) =>
    !pv?.product_id || pv?.match_reason === 'novo' || pv?.match_reason === 'descricao'
    || pv?.cost_changed || pv?.unit_changed || pv?.ncm_changed;

  // '__new' significa FORCAR produto novo; qualquer outro valor e um vinculo
  // manual a um produto existente. Traduzir num lugar so evita divergencia
  // entre o que a conferencia mostra e o que a confirmacao grava.
  const mapeamentosParaEnvio = () =>
    Object.entries(manualMappings).map(([sku, prodId]) =>
      prodId === '__new'
        ? { sku_supplier: sku, force_new: true }
        : { sku_supplier: sku, internal_product_id: prodId },
    );

  // Zera TODO o estado da conferência. Sem isto, o fornecedor, as parcelas e os
  // vínculos manuais (que são por SKU do fornecedor) de uma nota vazavam para a
  // próxima — dois fornecedores podem usar o mesmo código para produtos
  // diferentes, então o carryover casaria o item errado silenciosamente.
  const resetConference = () => {
    setShowConfirm(false);
    setParsed(null);
    setFile(null);
    setSupplierId('__none');
    setPurchaseOrderId('__none');
    setManualMappings({});
    setPreview(null);
    setSoAtencao(false);
  };

  const { data: fiscalNotes, isLoading: loadingNotes } = useFiscalNotes();
  const { data: suppliers } = useSuppliers();
  const { data: purchaseOrders } = usePurchaseOrders();
  const { data: products } = useProducts();
  // Três vias: quando um pedido é vinculado, carrega seus itens para confrontar
  // com a nota (quantidade e preço), pegando divergência de recebimento.
  const { data: linkedPO } = usePurchaseOrder(purchaseOrderId === '__none' ? undefined : purchaseOrderId);

  // Confronto pedido × nota, por produto. Casa o item da nota (produto resolvido
  // pelo preview do servidor) com o item do pedido (product_id). Só compara o que
  // dá para casar com segurança — o resto vira aviso, não erro.
  const poCompare = (() => {
    if (!linkedPO?.purchase_order_items?.length || !preview?.items) return null;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const poItems = linkedPO.purchase_order_items as any[];
    const usados = new Set<string>();
    const linhas = (preview.items as any[]).map((pv) => {
      const po = pv.product_id ? poItems.find((p) => p.product_id === pv.product_id && !usados.has(p.id)) : null;
      if (po) usados.add(po.id);
      const notaQtd = Number(pv.quantity) || 0;
      const notaPreco = Number(pv.unit_price) || 0;
      return {
        descricao: pv.description as string,
        casou: !!po,
        qtdDiverge: po ? Math.abs((Number(po.quantity) || 0) - notaQtd) > 0.001 : false,
        precoDiverge: po ? Math.abs((Number(po.unit_cost) || 0) - notaPreco) > 0.005 : false,
        poQtd: po ? Number(po.quantity) || 0 : null,
        poPreco: po ? Number(po.unit_cost) || 0 : null,
        notaQtd, notaPreco,
      };
    });
    const naoCasados = poItems.filter((p) => !usados.has(p.id));
    const divergentes = linhas.filter((l) => l.casou && (l.qtdDiverge || l.precoDiverge));
    const semPedido = linhas.filter((l) => !l.casou);
    return { linhas, divergentes, semPedido, naoCasados };
  })();

  // ── Upload & parse XML ─────────────────────────────────────────────────
  const handleUpload = async () => {
    if (!file) return;
    setUploading(true);
    try {
      const reader = new FileReader();
      const xmlBase64 = await new Promise<string>((resolve, reject) => {
        reader.onload = (e) => {
          const b64 = (e.target?.result as string).split(',')[1];
          if (b64) resolve(b64);
          else reject(new Error('Falha ao codificar arquivo'));
        };
        reader.onerror = () => reject(new Error('Erro ao ler arquivo'));
        reader.readAsDataURL(file);
      });

      const { data, error } = await supabase.functions.invoke('process-nfe-xml', {
        body: { xmlBase64 },
      });

      // A mensagem útil ("Arquivo não é uma NF-e válida", "chave de acesso
      // ilegível", "destinatário não é a sua empresa") vem no CORPO da resposta.
      // Sem extrair, o usuário e o log recebiam apenas "Edge Function returned a
      // non-2xx status code", que não diz nada.
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) {
        if (data.duplicate) {
          toast.warning(data.error);
          setFile(null);
          return;
        }
        throw new Error(data.error);
      }

      const nota = data as NFeParsed;
      setParsed(nota);

      // Fornecedor pelo CNPJ do PRÓPRIO XML. Antes o campo começava em "nenhum"
      // e, se o usuário esquecesse de escolher, a importação seguia sem aprender
      // o de-para e sem gerar a conta a pagar — silenciosamente.
      const cnpjXml = String((nota as any).issuerCNPJ || '').replace(/\D/g, '');
      const achado = cnpjXml
        ? (suppliers || []).find((s: any) => String(s.cnpj_cpf || '').replace(/\D/g, '') === cnpjXml)
        : null;
      setSupplierId(achado ? achado.id : '__none');

      setShowConfirm(true);
      toast.success(
        achado
          ? `XML processado! Fornecedor identificado: ${achado.name}. Confira os itens antes de confirmar.`
          : 'XML processado! Confira os itens antes de confirmar.',
      );
    } catch (err: any) {
      toast.error('Erro ao processar XML: ' + err.message);
    } finally {
      setUploading(false);
    }
  };

  // ── Conferência: simula a importação sem tocar em estoque/financeiro ────
  // Recalcula quando muda o fornecedor ou um vínculo manual, porque ambos
  // alteram o casamento (o de-para é por fornecedor).
  useEffect(() => {
    if (!parsed?.noteId) { setPreview(null); return; }
    let cancelado = false;
    (async () => {
      setLoadingPreview(true);
      try {
        const { data, error } = await (supabase.rpc as any)('preview_nfe_import', {
          p_note_id: parsed.noteId,
          p_supplier_id: supplierId === '__none' ? null : supplierId,
          p_manual_mappings: mapeamentosParaEnvio(),
        });
        if (error) throw error;
        if (!cancelado) setPreview(data);
      } catch (err: any) {
        if (!cancelado) {
          setPreview(null);
          toast.error('Erro ao conferir a nota: ' + err.message);
        }
      } finally {
        if (!cancelado) setLoadingPreview(false);
      }
    })();
    return () => { cancelado = true; };
  }, [parsed?.noteId, supplierId, manualMappings]);

  // ── Cadastrar o fornecedor a partir do XML ─────────────────────────────
  const handleCreateSupplierFromXml = async () => {
    const emit = (parsed as any)?.issuer;
    if (!emit?.document) { toast.error('O XML não trouxe o CNPJ do emitente.'); return; }
    setCreatingSupplier(true);
    try {
      const { data, error } = await supabase.from('suppliers').insert({
        name: emit.name || 'Fornecedor sem nome',
        trade_name: emit.tradeName || null,
        cnpj_cpf: String(emit.document).replace(/\D/g, ''),
        phone: emit.address?.phone || null,
        postal_code: emit.address?.postalCode || null,
        address_line_1: emit.address?.street || null,
        address_number: emit.address?.number || null,
        address_complement: emit.address?.complement || null,
        neighborhood: emit.address?.district || null,
        city: emit.address?.cityName || null,
        state: emit.address?.stateCode || null,
        country: 'Brasil',
        active: true,
      }).select().single();
      if (error) throw error;
      setSupplierId(data.id);
      qc.invalidateQueries({ queryKey: ['suppliers'] });
      toast.success(`Fornecedor "${data.name}" cadastrado a partir do XML.`);
    } catch (err: any) {
      toast.error('Erro ao cadastrar fornecedor: ' + err.message);
    } finally {
      setCreatingSupplier(false);
    }
  };

  // ── Desfazer importação (estorna estoque e conta a pagar) ───────────────
  const handleRevert = async (noteId: string) => {
    setRevertingId(noteId);
    try {
      const { data, error } = await (supabase.rpc as any)('revert_nfe_import', { p_note_id: noteId });
      if (error) throw error;
      const r = data as any;
      toast.success(
        `Importação desfeita: ${r.movements_reverted} movimento(s) estornado(s)` +
        (r.payables_removed ? `, ${r.payables_removed} conta(s) a pagar removida(s)` : '') + '.',
      );
      await writeAuditLog({
        table_name: 'fiscal_notes', record_id: noteId, action: 'revert_import' as any,
        new_value: r, reason: 'Reversão de importação de NF-e pelo usuário',
      });
      qc.invalidateQueries({ queryKey: ['fiscal_notes'] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
    } catch (err: any) {
      toast.error('Erro ao desfazer: ' + err.message);
    } finally {
      setRevertingId(null);
    }
  };

  // ── Confirm import → calls RPC ─────────────────────────────────────────
  const handleConfirmImport = async () => {
    if (!parsed?.noteId) return;
    setConfirming(true);
    try {
      const { data, error } = await (supabase.rpc as any)('confirm_nfe_import', {
        p_note_id:     parsed.noteId,
        p_supplier_id: supplierId === '__none' ? null : supplierId,
        p_manual_mappings: mapeamentosParaEnvio(),
        // Três vias: amarra a nota ao pedido de compra que a originou.
        p_purchase_order_id: purchaseOrderId === '__none' ? null : purchaseOrderId,
      });
      if (error) throw error;

      const result = data as any;
      toast.success(
        `Importação confirmada! ${result.movements_created} movimentos · ${result.products_created} produtos criados.`
      );

      // Audit
      await writeAuditLog({
        table_name: 'fiscal_notes',
        record_id:  parsed.noteId,
        action:     'confirm_import' as any,
        new_value: {
          nfe_number: parsed.nfeNumber,
          total:      parsed.totalNF,
          supplier_id: supplierId !== '__none' ? supplierId : null,
        },
        reason: 'Confirmação manual de importação de NF-e pelo usuário',
      });

      resetConference();
      qc.invalidateQueries({ queryKey: ['fiscal_notes'] });
      qc.invalidateQueries({ queryKey: ['inventory'] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
    } catch (err: any) {
      toast.error('Erro ao confirmar importação: ' + err.message);
    } finally {
      setConfirming(false);
    }
  };

  // ── Cancel pending note ────────────────────────────────────────────────
  const handleCancelNote = async (id: string) => {
    const { error } = await supabase
      .from('fiscal_notes')
      .update({ status: 'cancelled', updated_at: new Date().toISOString() })
      .eq('id', id);
    if (error) {
      toast.error('Erro ao cancelar nota: ' + error.message);
    } else {
      toast.success('Nota cancelada.');
      qc.invalidateQueries({ queryKey: ['fiscal_notes'] });
    }
  };

  // ── Devolução ao fornecedor ────────────────────────────────────────────
  // Relê o XML original da nota de compra (fiscal_notes.xml_content) para
  // extrair EXATAMENTE o fornecedor (emitente), a chave de acesso e os itens
  // (qtd/valor/origem), e navega para a Emissão Fiscal em modo devolução de
  // compra (CFOP 5202/6202, referência por item). Nada é emitido aqui — o
  // usuário revisa e confirma na tela fiscal.
  const handleReturnToSupplier = async (noteId: string) => {
    setReturningNoteId(noteId);
    try {
      const { data, error } = await supabase
        .from('fiscal_notes')
        .select('xml_content')
        .eq('id', noteId)
        .single();
      if (error) throw error;
      const xml = (data as any)?.xml_content as string | null;
      if (!xml) {
        toast.error('Esta nota não tem o XML original arquivado — não é possível gerar a devolução com exatidão.');
        return;
      }
      const supplierNote = parseNfeSupplierNote(xml);
      if (!supplierNote) {
        toast.error('Não foi possível ler a chave de acesso / o emitente do XML desta nota.');
        return;
      }
      navigate('/fiscal/emissao', { state: { returnToSupplier: supplierNote } });
    } catch (err: any) {
      toast.error('Erro ao preparar a devolução: ' + (err?.message || 'desconhecido'));
    } finally {
      setReturningNoteId(null);
    }
  };

  // ── Render ─────────────────────────────────────────────────────────────
  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Notas Fiscais Eletrônicas (NF-e)"
        description="Importe XMLs de NF-e para dar entrada no estoque, registrar fornecedores e gerar contas a pagar automaticamente."
      />

      {/* ── Upload area (oculta enquanto uma nota está sendo conferida) ── */}
      {!showConfirm && (
      <Card className="border-dashed border-2 bg-muted/20">
        <CardContent className="flex flex-col items-center justify-center py-10 space-y-4">
          <div className="h-16 w-16 bg-primary/10 rounded-full flex items-center justify-center">
            <Upload className="h-8 w-8 text-primary" />
          </div>
          <div className="text-center">
            <h3 className="text-lg font-semibold">Selecione o XML da NF-e</h3>
            <p className="text-sm text-muted-foreground mt-1">
              Formatos aceitos: .xml · Arquivos NF-e modelo 55
            </p>
          </div>
          <Input
            id="xml-upload"
            type="file"
            accept=".xml"
            className="hidden"
            onChange={(e) => setFile(e.target.files?.[0] ?? null)}
          />
          <Button
            variant="outline"
            onClick={() => document.getElementById('xml-upload')?.click()}
          >
            <FileText className="h-4 w-4 mr-2" />
            {file ? file.name : 'Escolher Arquivo'}
          </Button>
          {file && (
            <Button
              onClick={handleUpload}
              disabled={uploading}
              className="w-full max-w-xs"
            >
              {uploading
                ? <><Loader2 className="h-4 w-4 animate-spin mr-2" />Processando...</>
                : <><Upload className="h-4 w-4 mr-2" />Processar XML</>
              }
            </Button>
          )}
        </CardContent>
      </Card>
      )}

      {/* ── Conferência da entrada — PÁGINA, não modal ──
          Conferir dezenas de itens, trocar vínculos e ler divergências é uma
          tarefa de verdade; modal apertava. Enquanto uma nota é conferida, esta
          seção substitui o upload/histórico e usa a largura toda. */}
      {showConfirm && parsed && (
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Button variant="ghost" size="sm" className="gap-1.5"
              onClick={resetConference}>
              <ArrowLeft className="h-4 w-4" /> Voltar
            </Button>
            <div>
              <h2 className="text-lg font-semibold leading-tight">Conferir entrada de mercadoria</h2>
              <p className="text-sm text-muted-foreground">
                Nada é gravado até você confirmar. Ao confirmar, o estoque entra e a conta a pagar é criada.
              </p>
            </div>
          </div>

          {parsed && (
            <div className="space-y-4">
              {/* Cabeçalho da nota — uma faixa só, com alturas iguais. Antes eram
                  4 cards com tipografia disparatada (2xl ao lado de sm), o que
                  deixava a linha visualmente torta. */}
              {/* Identificação da nota: nome do fornecedor e total são o que o
                  conferente procura primeiro, então ficam nas pontas. Antes eram
                  4 colunas rígidas — sem min-w-0 a do fornecedor esticava e
                  empurrava o Total para fora do diálogo (ele aparecia cortado). */}
              <div className="flex flex-wrap items-start justify-between gap-3 rounded-lg border bg-muted/30 p-3">
                <div className="min-w-0">
                  <p className="truncate font-medium" title={parsed.issuerName || ''}>
                    {parsed.issuerName || '—'}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    CNPJ {parsed.issuerCNPJ || '—'} · NF-e nº {parsed.nfeNumber || '—'}
                    {parsed.issueDate ? ` · ${formatDate(parsed.issueDate)}` : ''}
                  </p>
                </div>
                <div className="shrink-0 text-right">
                  <p className="text-xl font-semibold leading-tight">{formatCurrency(parsed.totalNF)}</p>
                  <p className="text-xs text-muted-foreground">
                    {parsed.items.length} {parsed.items.length === 1 ? 'item' : 'itens'}
                  </p>
                </div>
              </div>

              {/* Composição do total. Antes a tela só comparava a soma dos itens
                  com o total e gritava "divergente" — o que acontecia em TODA
                  nota com IPI. Mostrar as parcelas explica de onde vem a diferença
                  e só alerta quando a conta realmente não fecha. */}
              {preview && (
                <div className={`rounded-lg border p-3 text-sm ${
                  preview.total_matches ? 'bg-muted/30' : 'border-destructive/40 bg-destructive/10'
                }`}>
                  <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                    <span className="text-muted-foreground">Produtos</span>
                    <span className="font-medium">{formatCurrency(Number(preview.items_sum))}</span>
                    {Number(preview.total_ipi) > 0 && (
                      <><span className="text-muted-foreground">+ IPI</span>
                        <span className="font-medium">{formatCurrency(Number(preview.total_ipi))}</span></>
                    )}
                    {Number(preview.total_freight) > 0 && (
                      <><span className="text-muted-foreground">+ frete</span>
                        <span className="font-medium">{formatCurrency(Number(preview.total_freight))}</span></>
                    )}
                    {Number(preview.total_other) > 0 && (
                      <><span className="text-muted-foreground">+ despesas</span>
                        <span className="font-medium">{formatCurrency(Number(preview.total_other))}</span></>
                    )}
                    {Number(preview.total_discount) > 0 && (
                      <><span className="text-muted-foreground">− desconto</span>
                        <span className="font-medium">{formatCurrency(Number(preview.total_discount))}</span></>
                    )}
                    <span className="text-muted-foreground">=</span>
                    <span className="font-semibold">{formatCurrency(Number(preview.expected_total))}</span>
                    {preview.total_matches
                      ? <Badge variant="outline" className="border-success/40 bg-success/10 text-success">confere com a nota</Badge>
                      : <Badge variant="destructive">não fecha com o total da nota ({formatCurrency(Number(preview.note_total))})</Badge>}
                  </div>
                </div>
              )}

              {/* Fornecedor — identificado pelo CNPJ do próprio XML */}
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-1">
                  {/* "aprende o de-para" era jargão: ninguém de fora do projeto
                      sabe o que significa. O rótulo agora só nomeia o campo, e o
                      efeito é explicado em português abaixo. */}
                  <Label>Fornecedor desta compra</Label>
                  <Select value={supplierId} onValueChange={setSupplierId}>
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Selecione..." />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="__none">Não vincular</SelectItem>
                      {(suppliers || []).map((s: any) => (
                        <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {supplierId === '__none' ? (
                    <div className="rounded border border-amber-300 bg-amber-50 p-2 text-[11px] leading-relaxed text-amber-900">
                      Sem informar o fornecedor, a importação <b>não cria a conta a pagar</b> desta
                      compra e <b>não memoriza</b> quais produtos seus correspondem aos códigos dele —
                      então na próxima nota você terá que vincular tudo de novo.
                      {(parsed as any).issuer?.document && (
                        <Button
                          type="button" size="sm" variant="outline" className="mt-2 w-full"
                          onClick={handleCreateSupplierFromXml} disabled={creatingSupplier}
                        >
                          {creatingSupplier ? 'Cadastrando…' : `Cadastrar "${(parsed as any).issuer?.name}" a partir do XML`}
                        </Button>
                      )}
                    </div>
                  ) : (
                    <p className="text-[11px] leading-relaxed text-muted-foreground">
                      Cria a conta a pagar desta compra e memoriza a correspondência entre os códigos
                      do fornecedor e os seus produtos — na próxima nota dele, os itens já vêm vinculados.
                    </p>
                  )}
                </div>

                {/* Três vias: pedido × nota × recebimento */}
                <div className="space-y-1">
                  <Label>Ordem de compra (opcional)</Label>
                  <Select value={purchaseOrderId} onValueChange={setPurchaseOrderId}>
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Selecione..." />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="__none">Não vincular</SelectItem>
                      {(purchaseOrders || []).map((po: any) => (
                        <SelectItem key={po.id} value={po.id}>
                          {po.po_number || po.id.slice(0, 8)} — {po.supplier_name || po.suppliers?.name || 'sem fornecedor'}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <p className="text-[11px] text-muted-foreground">
                    Amarra a nota ao pedido, evitando receber a mesma mercadoria duas vezes.
                  </p>
                </div>
              </div>

              {/* Confronto pedido × nota (três vias). Só aparece com um pedido
                  vinculado; destaca o que diverge para conferir antes de aceitar. */}
              {poCompare && (
                <div className={`rounded-lg border p-3 text-sm ${
                  poCompare.divergentes.length || poCompare.naoCasados.length
                    ? 'border-amber-300 bg-amber-50' : 'border-success/40 bg-success/10'
                }`}>
                  <div className="mb-1 font-medium">
                    {poCompare.divergentes.length || poCompare.naoCasados.length
                      ? 'Confira as diferenças com o pedido de compra'
                      : 'Nota confere com o pedido de compra'}
                  </div>
                  {poCompare.divergentes.map((l, i) => (
                    <div key={i} className="text-[12px] text-amber-900">
                      • <b>{l.descricao}</b>:
                      {l.qtdDiverge && ` quantidade pedido ${l.poQtd} × nota ${l.notaQtd};`}
                      {l.precoDiverge && ` preço pedido ${formatCurrency(l.poPreco!)} × nota ${formatCurrency(l.notaPreco)};`}
                    </div>
                  ))}
                  {poCompare.semPedido.length > 0 && (
                    <div className="text-[12px] text-amber-900">
                      • {poCompare.semPedido.length} item(ns) da nota não estão no pedido.
                    </div>
                  )}
                  {poCompare.naoCasados.length > 0 && (
                    <div className="text-[12px] text-amber-900">
                      • {poCompare.naoCasados.length} item(ns) do pedido não vieram nesta nota (recebimento parcial?).
                    </div>
                  )}
                </div>
              )}

              {/* Itens — LISTA, não tabela.
                  A tabela tinha 7 colunas com largura mínima fixa (900px): ela
                  empurrava o diálogo inteiro, cortava o "Total" do cabeçalho e
                  criava a barra horizontal. Uma lista se adapta à largura
                  disponível, dá espaço para a descrição (que é longa) e para o
                  seletor de vínculo, e funciona igual no celular. */}
              <div className="rounded-lg border">
                {(() => {
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  const qtdAtencao = (preview?.items || []).filter((p: any) => precisaAtencao(p)).length;
                  return (
                    <div className="flex flex-wrap items-center justify-between gap-2 border-b bg-muted/30 px-3 py-2">
                      <span className="text-sm font-medium">
                        Itens da nota ({parsed.items.length})
                      </span>
                      <div className="flex items-center gap-3">
                        {loadingPreview && (
                          <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
                            <Loader2 className="h-3 w-3 animate-spin" /> conferindo…
                          </span>
                        )}
                        {preview && qtdAtencao > 0 && (
                          <Button
                            type="button" size="sm" variant={soAtencao ? 'default' : 'outline'}
                            className="h-7 gap-1.5 text-xs"
                            onClick={() => setSoAtencao((v) => !v)}
                          >
                            <AlertCircle className="h-3.5 w-3.5" />
                            {soAtencao ? 'Mostrar todos' : `Só o que precisa de atenção (${qtdAtencao})`}
                          </Button>
                        )}
                      </div>
                    </div>
                  );
                })()}

                <div className="divide-y">
                  {parsed.items.map((item) => {
                    const sku = item.sku_supplier || '';
                    // O casamento vem do SERVIDOR (preview_nfe_import): a tela
                    // mostra exatamente o que a confirmação fará, em vez de
                    // recalcular no cliente com regra própria (que divergia).
                    // eslint-disable-next-line @typescript-eslint/no-explicit-any
                    const pv = (preview?.items || []).find((p: any) => p.index === item.index);
                    // Filtro "só atenção": esconde os itens já resolvidos. Enquanto
                    // o preview carrega (pv indefinido) mostramos tudo.
                    if (soAtencao && preview && !precisaAtencao(pv)) return null;
                    const vinculado = !!pv?.product_id;
                    const motivo: Record<string, { txt: string; cls: string }> = {
                      manual:    { txt: 'você escolheu',        cls: 'border-blue-200 bg-blue-50 text-blue-700' },
                      barcode:   { txt: 'código de barras',     cls: 'border-emerald-200 bg-emerald-50 text-emerald-700' },
                      de_para:   { txt: 'compra anterior',      cls: 'border-emerald-200 bg-emerald-50 text-emerald-700' },
                      sku:       { txt: 'código do produto',    cls: 'border-teal-200 bg-teal-50 text-teal-700' },
                      descricao: { txt: 'pela descrição',       cls: 'border-amber-300 bg-amber-50 text-amber-800' },
                      novo:      { txt: 'será criado',          cls: 'border-amber-300 bg-amber-50 text-amber-800' },
                    };
                    const sel = motivo[pv?.match_reason] ?? null;
                    const divergencias = [
                      pv?.cost_changed
                        && `Custo ${formatCurrency(Number(pv.current_cost))} → ${formatCurrency(item.unit_price)}`,
                      pv?.unit_changed && `Unidade difere do cadastro (${pv.product_unit})`,
                      pv?.ncm_changed && `NCM difere do cadastro (${pv.product_ncm})`,
                    ].filter(Boolean) as string[];

                    return (
                      <div key={item.index} className="p-3">
                        {/* Cabeçalho do item: descrição à esquerda, valores à
                            direita. min-w-0 no bloco flexível é o que permite a
                            descrição truncar em vez de esticar a linha. */}
                        <div className="flex items-start gap-3">
                          <span className="w-5 shrink-0 pt-0.5 text-xs text-muted-foreground">{item.index}</span>

                          <div className="min-w-0 flex-1">
                            {/* Fornecedores usam " - " como quebra dentro do xProd
                                (a Kamell faz em todos os itens) — normalizar evita
                                o truncamento irregular. Texto completo no title. */}
                            <p className="truncate font-medium leading-snug" title={item.description || ''}>
                              {(item.description || '').replace(/\s+-\s+/g, ' — ').replace(/\s{2,}/g, ' ')}
                            </p>
                            <p className="mt-0.5 text-xs text-muted-foreground">
                              cód. fornecedor {sku || '—'}
                              {item.ncm ? ` · NCM ${item.ncm}` : ''}
                              {item.barcode ? ` · EAN ${item.barcode}` : ''}
                            </p>
                          </div>

                          <div className="shrink-0 text-right">
                            <p className="font-semibold tabular-nums">{formatCurrency(item.total_price)}</p>
                            <p className="text-xs text-muted-foreground tabular-nums">
                              {item.quantity} {item.unit || 'un'} × {formatCurrency(item.unit_price)}
                            </p>
                          </div>
                        </div>

                        {/* Vínculo com o catálogo + por que casou */}
                        <div className="mt-2 flex flex-wrap items-center gap-2 pl-8">
                          {sel && (
                            <span className={`rounded border px-1.5 py-0.5 text-[10px] ${sel.cls}`}>{sel.txt}</span>
                          )}
                          {divergencias.map((d) => (
                            <span key={d} className="text-[11px] text-amber-700">{d}</span>
                          ))}
                        </div>

                        <div className="mt-1.5 pl-8">
                          <Select
                            value={pv?.product_id || '__new'}
                            onValueChange={(val) => {
                              if (!sku) return;
                              setManualMappings((prev) => ({
                                // '__new' é uma DECISÃO (forçar produto novo), não
                                // ausência de decisão: se removêssemos a chave, a
                                // cascata rodaria e poderia vincular a um produto
                                // existente, contrariando a escolha.
                                ...prev,
                                [sku]: val,
                              }));
                            }}
                          >
                            <SelectTrigger
                              className={`h-9 text-xs ${
                                vinculado
                                  ? 'border-success/30 bg-success/5 text-success'
                                  : 'border-amber-300 bg-amber-50 text-amber-700'
                              }`}
                            >
                              <div className="flex min-w-0 items-center gap-1.5">
                                {vinculado
                                  ? <CheckCircle2 className="h-3.5 w-3.5 shrink-0" />
                                  : <AlertCircle className="h-3.5 w-3.5 shrink-0" />}
                                <span className="truncate"><SelectValue /></span>
                              </div>
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="__new" className="font-medium text-amber-700">
                                Criar como produto novo
                              </SelectItem>
                              <div className="my-1 border-t" />
                              {(products || []).filter((p) => p.active).map((p) => (
                                <SelectItem key={p.id} value={p.id} className="text-xs">
                                  {p.name}{p.sku ? ` (${p.sku})` : ''}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

            </div>
          )}

          {/* Barra de ação STICKY: acompanha a rolagem da página e mantém
              "Confirmar" sempre alcançável, com o resumo do que será feito. */}
          {parsed && (
            <div className="sticky bottom-0 z-10 flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-background/95 px-4 py-3 shadow-sm backdrop-blur supports-[backdrop-filter]:bg-background/80">
              <p className="text-xs text-muted-foreground">
                {(() => {
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  const novos = (preview?.items || []).filter((i: any) => !i.product_id).length;
                  const total = parsed.items.length;
                  return novos > 0
                    ? `${total - novos} vinculado(s) ao catálogo · ${novos} será(ão) criado(s)`
                    : `${total} item(ns) vinculado(s) ao catálogo`;
                })()}
              </p>
              <div className="flex gap-2">
                <Button variant="outline" onClick={resetConference}>
                  Cancelar
                </Button>
                <Button onClick={handleConfirmImport} disabled={confirming || loadingPreview}
                  className="bg-success text-white hover:bg-success/90">
                  {confirming
                    ? <><Loader2 className="h-4 w-4 animate-spin mr-2" />Confirmando…</>
                    : <><Package className="h-4 w-4 mr-2" />Confirmar entrada</>
                  }
                </Button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* ── Histórico (oculto enquanto uma nota está sendo conferida) ── */}
      {!showConfirm && (
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold">Histórico de NF-es Importadas</h2>
          <Button variant="ghost" size="sm" onClick={() => qc.invalidateQueries({ queryKey: ['fiscal_notes'] })}>
            <RefreshCw className="h-4 w-4 mr-1" />Atualizar
          </Button>
        </div>

        <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nº NF-e</TableHead>
                <TableHead>Emitente</TableHead>
                <TableHead>Emissão</TableHead>
                <TableHead className="text-right">Total</TableHead>
                <TableHead className="text-right">ICMS</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loadingNotes ? (
                Array.from({ length: 3 }).map((_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={7}><Skeleton className="h-8 w-full" /></TableCell>
                  </TableRow>
                ))
              ) : !fiscalNotes?.length ? (
                <TableRow>
                  <TableCell colSpan={7} className="text-center py-10 text-muted-foreground">
                    Nenhuma NF-e importada ainda. Use o upload acima para começar.
                  </TableCell>
                </TableRow>
              ) : fiscalNotes.map((note: any) => {
                const s = STATUS_MAP[note.status] ?? STATUS_MAP.pending;
                return (
                  <TableRow key={note.id} className="hover:bg-muted/30">
                    <TableCell className="font-mono font-medium">{note.nfe_number || '—'}</TableCell>
                    <TableCell className="max-w-[200px] truncate">{note.issuer_name || '—'}</TableCell>
                    <TableCell className="text-muted-foreground text-sm">{note.issued_at ? formatDate(note.issued_at) : '—'}</TableCell>
                    <TableCell className="text-right font-semibold">{formatCurrency(note.total_amount || 0)}</TableCell>
                    <TableCell className="text-right text-muted-foreground">{formatCurrency(note.tax_icms || 0)}</TableCell>
                    <TableCell>
                      <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold ${s.className}`}>
                        {s.label}
                      </span>
                    </TableCell>
                    <TableCell className="text-right">
                      {note.status === 'pending' && (
                        <div className="flex justify-end gap-1">
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={async () => {
                              // Re-fetch full note to populate confirm dialog
                              const { data } = await supabase
                                .from('fiscal_notes')
                                .select('*')
                                .eq('id', note.id)
                                .single();
                              if (data) {
                                const d = data as any;
                                // Limpa o estado da nota anterior antes de abrir
                                // outra (senão os vínculos manuais vazam por SKU).
                                resetConference();
                                setParsed({
                                  noteId:     d.id,
                                  nfeKey:     d.nfe_key,
                                  nfeNumber:  d.nfe_number,
                                  issueDate:  d.issued_at ?? d.issue_date,
                                  issuerName: d.issuer_name,
                                  issuerCNPJ: d.issuer_cnpj,
                                  totalNF:    d.total_amount ?? d.total_value,
                                  totalICMS:  d.tax_icms,
                                  totalIPI:   d.tax_ipi,
                                  totalPIS:   d.tax_pis,
                                  totalCOFINS: d.tax_cofins,
                                  items:      d.items || [],
                                });
                                // Fornecedor já vinculado à nota, ou casado pelo
                                // CNPJ do emitente — poupa reescolher a cada vez.
                                const cnpj = String(d.issuer_cnpj || '').replace(/\D/g, '');
                                const forn = d.supplier_id
                                  || (cnpj && (suppliers || []).find((s: any) => String(s.cnpj_cpf || '').replace(/\D/g, '') === cnpj)?.id);
                                if (forn) setSupplierId(forn);
                                if (d.purchase_order_id) setPurchaseOrderId(d.purchase_order_id);
                                setShowConfirm(true);
                              }
                            }}
                          >
                            <Banknote className="h-3.5 w-3.5 mr-1" />Confirmar
                          </Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            className="text-destructive hover:text-destructive"
                            onClick={() => handleCancelNote(note.id)}
                          >
                            Cancelar
                          </Button>
                        </div>
                      )}
                      {note.status === 'confirmed' && (
                        <div className="flex items-center justify-end gap-2">
                          <span className="text-xs text-muted-foreground">
                            {note.confirmed_at ? formatDate(note.confirmed_at) : 'Confirmada'}
                          </span>
                          <Button
                            size="sm"
                            variant="outline"
                            className="text-xs"
                            disabled={returningNoteId === note.id}
                            title="Gerar uma NF-e de devolução (total ou parcial) desta compra ao fornecedor, referenciando a nota original por item"
                            onClick={() => handleReturnToSupplier(note.id)}
                          >
                            {returningNoteId === note.id
                              ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                              : <Undo2 className="h-3.5 w-3.5 mr-1" />}
                            Devolver ao fornecedor
                          </Button>
                          {/* Desfazer a ENTRADA (erro de conferência). Diferente da
                              devolução, que é uma operação fiscal com o fornecedor. */}
                          <Button
                            size="sm"
                            variant="ghost"
                            className="text-xs text-destructive hover:text-destructive"
                            disabled={revertingId === note.id}
                            title="Estorna o estoque e remove a conta a pagar desta importação, devolvendo a nota para 'Pendente'. Não emite nada ao fisco."
                            onClick={() => {
                              if (confirm(
                                'Desfazer a importação desta nota?\n\n' +
                                'O estoque será estornado e a conta a pagar (se não houver pagamento) será removida. ' +
                                'A nota volta para "Pendente" e pode ser conferida de novo.',
                              )) handleRevert(note.id);
                            }}
                          >
                            {revertingId === note.id
                              ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                              : <RefreshCw className="h-3.5 w-3.5 mr-1" />}
                            Desfazer entrada
                          </Button>
                        </div>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </div>
      </div>
      )}
    </div>
  );
}
