import { useState } from 'react';
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
  Upload, FileText, CheckCircle2, AlertCircle, Loader2, Package, Banknote, RefreshCw,
} from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useSuppliers } from '@/hooks/use-suppliers';
import { useI18n } from '@/i18n';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { useProducts } from '@/hooks/use-products';

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

  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [parsed, setParsed] = useState<NFeParsed | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [supplierId, setSupplierId] = useState<string>('__none');
  const [showConfirm, setShowConfirm] = useState(false);
  const [manualMappings, setManualMappings] = useState<Record<string, string>>({});

  const { data: fiscalNotes, isLoading: loadingNotes } = useFiscalNotes();
  const { data: suppliers } = useSuppliers();
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

      if (error) throw error;
      if (data?.error) {
        if (data.duplicate) {
          toast.warning(data.error);
          setFile(null);
          return;
        }
        throw new Error(data.error);
      }

      setParsed(data as NFeParsed);
      setShowConfirm(true);
      toast.success('XML processado! Revise os itens antes de confirmar.');
    } catch (err: any) {
      toast.error('Erro ao processar XML: ' + err.message);
    } finally {
      setUploading(false);
    }
  };

  // ── Confirm import → calls RPC ─────────────────────────────────────────
  const handleConfirmImport = async () => {
    if (!parsed?.noteId) return;
    setConfirming(true);
    try {
      const { data, error } = await supabase.rpc('confirm_nfe_import', {
        p_note_id:     parsed.noteId,
        p_supplier_id: supplierId === '__none' ? null : supplierId,
        p_manual_mappings: Object.entries(manualMappings).map(([sku, prodId]) => ({
          sku_supplier: sku,
          internal_product_id: prodId
        }))
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

              {/* Supplier link */}
              <div className="space-y-1">
                <Label>Vincular ao Fornecedor (opcional — gera Conta a Pagar)</Label>
                <Select value={supplierId} onValueChange={setSupplierId}>
                  <SelectTrigger className="w-full max-w-sm">
                    <SelectValue placeholder="Selecione..." />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none">Não vincular</SelectItem>
                    {(suppliers || []).map((s: any) => (
                      <SelectItem key={s.id} value={s.id}>{s.supplier_name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

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
                        const manualId = manualMappings[sku];
                        const match = (products || []).find(
                          (p) => (manualId ? p.id === manualId : (p.sku === sku || p.product_name?.toLowerCase() === item.description?.toLowerCase()))
                        );
                        
                        return (
                          <TableRow key={item.index}>
                            <TableCell className="text-muted-foreground">{item.index}</TableCell>
                            <TableCell>
                              <p className="font-medium">{item.description}</p>
                              <p className="text-[11px] text-muted-foreground">SKU: {sku || '—'}</p>
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
                                    setManualMappings(prev => ({
                                      ...prev,
                                      [sku]: val === '__new' ? '' : val
                                    }));
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
                                      {p.product_name} {p.sku ? `(${p.sku})` : ''}
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
                                setParsed({
                                  noteId:     data.id,
                                  nfeKey:     data.nfe_key,
                                  nfeNumber:  data.nfe_number,
                                  issueDate:  data.issued_at,
                                  issuerName: data.issuer_name,
                                  issuerCNPJ: data.issuer_cnpj,
                                  totalNF:    data.total_amount,
                                  totalICMS:  data.tax_icms,
                                  totalIPI:   data.tax_ipi,
                                  totalPIS:   data.tax_pis,
                                  totalCOFINS: data.tax_cofins,
                                  items:      data.items || [],
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
                        <span className="text-xs text-muted-foreground">
                          {note.confirmed_at ? formatDate(note.confirmed_at) : 'Confirmada'}
                        </span>
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
