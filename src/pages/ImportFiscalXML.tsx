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
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  Upload, FileText, CheckCircle2, AlertCircle, Loader2, Package, Banknote, RefreshCw, Undo2,
} from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { useSuppliers } from '@/hooks/use-suppliers';
import { usePurchaseOrders } from '@/hooks/use-purchase-orders';
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

  const { data: fiscalNotes, isLoading: loadingNotes } = useFiscalNotes();
  const { data: suppliers } = useSuppliers();
  const { data: purchaseOrders } = usePurchaseOrders();
  const { data: products } = useProducts();

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
          p_manual_mappings: Object.entries(manualMappings).map(([sku, prodId]) => ({
            sku_supplier: sku, internal_product_id: prodId,
          })),
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
        p_manual_mappings: Object.entries(manualMappings).map(([sku, prodId]) => ({
          sku_supplier: sku,
          internal_product_id: prodId
        })),
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

      setParsed(null);
      setFile(null);
      setSupplierId('__none');
      setPurchaseOrderId('__none');
      setPreview(null);
      setManualMappings({});
      setShowConfirm(false);
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

      {/* ── Upload area ── */}
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

      {/* ── Confirmation dialog ── */}
      <Dialog open={showConfirm} onOpenChange={(o) => { if (!o) { setShowConfirm(false); setParsed(null); setFile(null); } }}>
        <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Confirmar Importação da NF-e</DialogTitle>
            <DialogDescription>
              Revise os itens abaixo. Ao confirmar, o estoque será atualizado e um lançamento financeiro será criado.
            </DialogDescription>
          </DialogHeader>

          {parsed && (
            <div className="space-y-4 mt-2">
              {/* Header cards */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                <Card>
                  <CardHeader className="pb-1"><CardTitle className="text-xs text-muted-foreground uppercase">Emitente</CardTitle></CardHeader>
                  <CardContent><p className="font-semibold text-sm leading-tight">{parsed.issuerName || '—'}</p><p className="text-xs text-muted-foreground">{parsed.issuerCNPJ || '—'}</p></CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-1"><CardTitle className="text-xs text-muted-foreground uppercase">Nº da Nota</CardTitle></CardHeader>
                  <CardContent><p className="font-semibold text-2xl text-primary">{parsed.nfeNumber || '—'}</p></CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-1"><CardTitle className="text-xs text-muted-foreground uppercase">Total NF-e</CardTitle></CardHeader>
                  <CardContent><p className="font-semibold text-2xl">{formatCurrency(parsed.totalNF)}</p></CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-1"><CardTitle className="text-xs text-muted-foreground uppercase">ICMS Total</CardTitle></CardHeader>
                  <CardContent><p className="font-semibold text-sm">{formatCurrency(parsed.totalICMS)}</p><p className="text-xs text-muted-foreground">IPI: {formatCurrency(parsed.totalIPI)}</p></CardContent>
                </Card>
              </div>

              {/* Fornecedor — identificado pelo CNPJ do próprio XML */}
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-1">
                  <Label>Fornecedor (gera a Conta a Pagar e aprende o de-para)</Label>
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
                  {supplierId === '__none' && (
                    <div className="rounded border border-amber-300 bg-amber-50 p-2 text-[11px] text-amber-900">
                      Sem fornecedor a importação <b>não gera conta a pagar</b> e <b>não memoriza</b> o
                      vínculo dos códigos para as próximas notas.
                      {(parsed as any).issuer?.document && (
                        <Button
                          type="button" size="sm" variant="outline" className="mt-2 w-full"
                          onClick={handleCreateSupplierFromXml} disabled={creatingSupplier}
                        >
                          {creatingSupplier ? 'Cadastrando…' : `Cadastrar "${(parsed as any).issuer?.name}" a partir do XML`}
                        </Button>
                      )}
                    </div>
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

              {/* Conferência de totais: soma dos itens x total da nota */}
              {preview && !preview.total_matches && (
                <div className="rounded border border-destructive/40 bg-destructive/10 p-3 text-xs">
                  <b>Atenção:</b> a soma dos itens ({formatCurrency(Number(preview.items_sum))}) é
                  diferente do total da nota ({formatCurrency(Number(preview.note_total))}). Isso
                  costuma ser frete, desconto ou despesas acessórias não distribuídos nos itens —
                  confira antes de confirmar.
                </div>
              )}

              {/* Items table */}
              <Card>
                <CardHeader><CardTitle className="text-sm">Itens da Nota ({parsed.items.length})</CardTitle></CardHeader>
                <CardContent className="p-0">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>#</TableHead>
                        <TableHead>Descrição</TableHead>
                        <TableHead>NCM</TableHead>
                        <TableHead className="text-right">Qtd</TableHead>
                        <TableHead className="text-right">V. Unit.</TableHead>
                        <TableHead className="text-right">Total</TableHead>
                        <TableHead>No Sistema</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {parsed.items.map((item) => {
                        const sku = item.sku_supplier || '';
                        // O casamento vem do SERVIDOR (preview_nfe_import): a tela
                        // mostra exatamente o que a confirmação fará, em vez de
                        // recalcular no cliente com regra própria (que divergia).
                        const pv = (preview?.items || []).find((p: any) => p.index === item.index);
                        const match = pv?.product_id
                          ? { id: pv.product_id, name: pv.product_name }
                          : null;
                        const motivo: Record<string, { txt: string; cls: string }> = {
                          manual:    { txt: 'vínculo manual',      cls: 'bg-blue-50 text-blue-700 border-blue-200' },
                          barcode:   { txt: 'código de barras',    cls: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
                          de_para:   { txt: 'histórico do fornec.', cls: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
                          sku:       { txt: 'código interno',      cls: 'bg-teal-50 text-teal-700 border-teal-200' },
                          descricao: { txt: 'descrição',           cls: 'bg-amber-50 text-amber-800 border-amber-300' },
                          novo:      { txt: 'produto novo',        cls: 'bg-amber-50 text-amber-800 border-amber-300' },
                        };
                        const sel = motivo[pv?.match_reason] || null;

                        return (
                          <TableRow key={item.index}>
                            <TableCell className="text-muted-foreground">{item.index}</TableCell>
                            <TableCell>
                              <p className="font-medium">{item.description}</p>
                              <p className="text-[11px] text-muted-foreground">
                                SKU: {sku || '—'}{item.barcode ? ` · EAN: ${item.barcode}` : ''}
                              </p>
                              {sel && (
                                <span className={`inline-block mt-1 rounded border px-1.5 py-0.5 text-[10px] ${sel.cls}`}>
                                  {sel.txt}
                                </span>
                              )}
                              {/* Divergências que o conferente precisa ver ANTES de aceitar */}
                              {pv?.cost_changed && (
                                <p className="text-[10px] text-amber-700 mt-0.5">
                                  Custo atual {formatCurrency(Number(pv.current_cost))} → {formatCurrency(item.unit_price)}
                                </p>
                              )}
                              {pv?.unit_changed && (
                                <p className="text-[10px] text-amber-700">Unidade difere do cadastro ({pv.product_unit})</p>
                              )}
                              {pv?.ncm_changed && (
                                <p className="text-[10px] text-amber-700">NCM difere do cadastro ({pv.product_ncm})</p>
                              )}
                            </TableCell>
                            <TableCell className="text-muted-foreground text-xs">{item.ncm || '—'}</TableCell>
                            <TableCell className="text-right">{item.quantity} {item.unit || 'un'}</TableCell>
                            <TableCell className="text-right">{formatCurrency(item.unit_price)}</TableCell>
                            <TableCell className="text-right font-semibold">{formatCurrency(item.total_price)}</TableCell>
                            <TableCell className="min-w-[200px]">
                              <Select 
                                value={match?.id || '__new'} 
                                onValueChange={(val) => {
                                  if (sku) {
                                    setManualMappings(prev => {
                                      const next = { ...prev };
                                      // Mandar '' faria o servidor tratar como "sem
                                      // vínculo manual" e recair na cascata; remover
                                      // a chave expressa a mesma intenção sem ruído.
                                      if (val === '__new') delete next[sku];
                                      else next[sku] = val;
                                      return next;
                                    });
                                  }
                                }}
                              >
                                <SelectTrigger className={`h-8 text-xs ${match ? 'text-success border-success/30 bg-success/5' : 'text-amber-600 border-amber-300 bg-amber-50'}`}>
                                  <div className="flex items-center gap-1.5 truncate">
                                    {match ? <CheckCircle2 className="h-3 w-3" /> : <AlertCircle className="h-3 w-3" />}
                                    <SelectValue />
                                  </div>
                                </SelectTrigger>
                                <SelectContent>
                                  <SelectItem value="__new" className="text-amber-600 font-medium">✨ Criar como Novo Produto</SelectItem>
                                  <div className="border-t my-1" />
                                  {(products || []).filter(p => p.active).map(p => (
                                    <SelectItem key={p.id} value={p.id} className="text-xs">
                                      {p.name} {p.sku ? `(${p.sku})` : ''}
                                    </SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                            </TableCell>
                          </TableRow>
                        );
                      })}
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>

              <div className="flex justify-end gap-3">
                <Button variant="outline" onClick={() => { setShowConfirm(false); setParsed(null); setFile(null); }}>
                  Cancelar
                </Button>
                <Button onClick={handleConfirmImport} disabled={confirming} className="bg-success text-white hover:bg-success/90 px-8">
                  {confirming
                    ? <><Loader2 className="h-4 w-4 animate-spin mr-2" />Confirmando...</>
                    : <><Package className="h-4 w-4 mr-2" />Confirmar Entrada no Estoque</>
                  }
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* ── Fiscal notes list ── */}
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
    </div>
  );
}
