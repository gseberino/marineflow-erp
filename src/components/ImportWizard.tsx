import { useState, useRef, useCallback } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Upload, CheckCircle, AlertTriangle, ArrowLeft, ArrowRight, FileText, Loader2 } from 'lucide-react';
import { parseCSVContent, detectFormat, applyMapping, type ParsedFile, type DetectionResult, type ColumnMapping } from '@/lib/import-detector';
import { useCheckConflicts, useImportRows, type ConflictItem } from '@/hooks/use-import';

type EntityType = 'products' | 'services' | 'clients' | 'suppliers' | 'auto';

interface ImportWizardProps {
  entityType: EntityType;
  open: boolean;
  onOpenChange: (v: boolean) => void;
  onComplete?: (count: number) => void;
}

const PRODUCT_FIELDS: Record<string, string> = {
  product_name: 'Nome*', sku: 'SKU', sale_price: 'Preço venda', cost_price: 'Preço custo',
  stock_quantity: 'Estoque atual', minimum_stock: 'Estoque mínimo', unit: 'Unidade',
  brand: 'Marca', location_bin: 'Localização', notes: 'Notas', active: 'Ativo',
};
const SERVICE_FIELDS: Record<string, string> = {
  service_name: 'Nome*', default_price: 'Preço padrão', billing_unit: 'Unidade', notes: 'Notas', active: 'Ativo',
};
const CLIENT_FIELDS: Record<string, string> = {
  full_name_or_company_name: 'Nome*', cnpj_cpf: 'CPF/CNPJ', email: 'Email', phone: 'Telefone',
  address_line_1: 'Endereço', postal_code: 'CEP', city: 'Cidade', state: 'Estado', notes: 'Notas',
};
const SUPPLIER_FIELDS: Record<string, string> = {
  supplier_name: 'Razão Social*', cnpj_cpf: 'CNPJ', contact_email: 'Email', contact_phone: 'Telefone',
  address_line_1: 'Endereço', postal_code: 'CEP', city: 'Cidade', state: 'Estado', notes: 'Notas',
};

function getFieldsForType(type: string): Record<string, string> {
  switch (type) {
    case 'products': return PRODUCT_FIELDS;
    case 'services': return SERVICE_FIELDS;
    case 'clients': case 'mixed': return CLIENT_FIELDS;
    case 'suppliers': return SUPPLIER_FIELDS;
    default: return PRODUCT_FIELDS;
  }
}

export function ImportWizard({ entityType, open, onOpenChange, onComplete }: ImportWizardProps) {
  const { t } = useI18n();
  const fileRef = useRef<HTMLInputElement>(null);
  const [step, setStep] = useState<1 | 2 | 3 | 4>(1);
  const [parsedFile, setParsedFile] = useState<ParsedFile | null>(null);
  const [detection, setDetection] = useState<DetectionResult | null>(null);
  const [mapping, setMapping] = useState<ColumnMapping>({});
  const [resolvedType, setResolvedType] = useState<string>(entityType === 'auto' ? 'products' : entityType);
  const [newRows, setNewRows] = useState<Record<string, any>[]>([]);
  const [conflicts, setConflicts] = useState<ConflictItem[]>([]);
  const [checking, setChecking] = useState(false);
  const [importResult, setImportResult] = useState<{ inserted: number; updated: number } | null>(null);

  const checkConflicts = useCheckConflicts();
  const importRows = useImportRows();

  const reset = useCallback(() => {
    setStep(1);
    setParsedFile(null);
    setDetection(null);
    setMapping({});
    setNewRows([]);
    setConflicts([]);
    setChecking(false);
    setImportResult(null);
  }, []);

  const handleFile = async (file: File) => {
    const readWithEncoding = (enc: string): Promise<string> =>
      new Promise((res, rej) => {
        const reader = new FileReader();
        reader.onload = () => res(reader.result as string);
        reader.onerror = rej;
        reader.readAsText(file, enc);
      });

    let content = await readWithEncoding('UTF-8');
    const parsed = parseCSVContent(content, 'utf-8');

    // Check for garbled chars and retry with latin-1
    const hasGarbled = parsed.headers.some(h => h.includes('�') || h.includes('Ã'));
    if (hasGarbled) {
      content = await readWithEncoding('ISO-8859-1');
      const reParsed = parseCSVContent(content, 'iso-8859-1');
      setParsedFile(reParsed);
      const det = detectFormat(reParsed);
      setDetection(det);
      setMapping(det.suggestedMapping);
      if (det.entityType !== 'mixed') setResolvedType(det.entityType);
      else setResolvedType('mixed');
    } else {
      setParsedFile(parsed);
      const det = detectFormat(parsed);
      setDetection(det);
      setMapping(det.suggestedMapping);
      if (entityType === 'auto' || det.confidence >= 80) {
        if (det.entityType !== 'mixed') setResolvedType(det.entityType);
        else setResolvedType('mixed');
      }
    }
  };

  const goToReview = async () => {
    if (!parsedFile || checking) return;
    setChecking(true);
    try {
      const transformed = applyMapping(parsedFile.rows, mapping, resolvedType);
      const result = await checkConflicts.mutateAsync({ entityType: resolvedType, rows: transformed });
      setNewRows(result.newRows);
      setConflicts(result.conflicts);
      setStep(3);
    } catch (err: any) {
      console.error('Conflict check failed:', err);
    } finally {
      setChecking(false);
    }
  };

  const handleImport = async () => {
    setStep(4);
    const updates = conflicts
      .filter(c => c.resolution === 'replace')
      .map(c => ({ id: c.existing.id, data: c.incoming }));

    const result = await importRows.mutateAsync({
      entityType: resolvedType,
      newRows,
      updates,
    });
    setImportResult(result);
    onComplete?.(result.inserted + result.updated);
  };

  const setAllConflictResolutions = (res: 'keep' | 'replace') => {
    setConflicts(prev => prev.map(c => ({ ...c, resolution: res })));
  };

  const stepLabels = [t.imports.stepUpload, t.imports.stepMapping, t.imports.stepReview, t.imports.stepDone];

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) reset(); onOpenChange(v); }}>
      <DialogContent className="max-w-3xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{t.imports.title}</DialogTitle>
        </DialogHeader>

        {/* Step indicator */}
        <div className="flex items-center gap-2 mb-4">
          {stepLabels.map((label, i) => (
            <div key={i} className="flex items-center gap-1">
              <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-medium ${
                step > i + 1 ? 'bg-primary text-primary-foreground' :
                step === i + 1 ? 'bg-accent text-accent-foreground' :
                'bg-muted text-muted-foreground'
              }`}>{i + 1}</div>
              <span className={`text-xs ${step === i + 1 ? 'font-medium' : 'text-muted-foreground'}`}>{label}</span>
              {i < 3 && <ArrowRight className="h-3 w-3 text-muted-foreground" />}
            </div>
          ))}
        </div>

        {/* STEP 1: Upload */}
        {step === 1 && (
          <div className="space-y-4">
            <div
              className="border-2 border-dashed rounded-xl p-12 text-center cursor-pointer hover:border-accent/50 transition-colors"
              onClick={() => fileRef.current?.click()}
              onDragOver={(e) => { e.preventDefault(); e.stopPropagation(); }}
              onDrop={(e) => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f) handleFile(f); }}
            >
              <Upload className="h-10 w-10 mx-auto mb-3 text-muted-foreground" />
              <p className="text-muted-foreground">{t.imports.dragDropHere}</p>
              <p className="text-xs text-muted-foreground mt-1">.csv, .txt</p>
              <input ref={fileRef} type="file" accept=".csv,.txt" className="hidden"
                onChange={e => { const f = e.target.files?.[0]; if (f) handleFile(f); }} />
            </div>

            {detection && (
              <div className={`rounded-lg p-4 ${detection.confidence >= 80
                ? 'bg-success/10 border border-success/30'
                : 'bg-warning/10 border border-warning/30'}`}>
                <div className="flex items-center gap-2 mb-1">
                  {detection.confidence >= 80 ? <CheckCircle className="h-4 w-4 text-success" /> : <AlertTriangle className="h-4 w-4 text-warning" />}
                  <span className="font-medium">
                    {detection.confidence >= 80 ? `${t.imports.formatRecognized}: ${detection.formatLabel}` : t.imports.formatUnknown}
                  </span>
                </div>
                {detection.confidence >= 80 && (
                  <p className="text-sm text-muted-foreground">
                    {detection.recordCount} {t.imports.recordsFound}
                    {detection.entityType === 'mixed' && <span className="ml-2">— {t.imports.mixedFileInfo}</span>}
                  </p>
                )}
              </div>
            )}

            {parsedFile && parsedFile.rows.length > 0 && (
              <div className="overflow-x-auto max-h-40 rounded border">
                <table className="text-xs w-full">
                  <thead><tr className="bg-muted/50">
                    {parsedFile.headers.slice(0, 6).map(h => <th key={h} className="px-2 py-1 text-left font-medium">{h}</th>)}
                    {parsedFile.headers.length > 6 && <th className="px-2 py-1">...</th>}
                  </tr></thead>
                  <tbody>
                    {parsedFile.rows.slice(0, 3).map((row, i) => (
                      <tr key={i} className="border-t">
                        {parsedFile.headers.slice(0, 6).map(h => <td key={h} className="px-2 py-1 truncate max-w-[150px]">{row[h]}</td>)}
                        {parsedFile.headers.length > 6 && <td className="px-2 py-1">...</td>}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {detection && (
              <div className="flex justify-end gap-2">
                {detection.confidence >= 80 ? (
                  <Button onClick={goToReview} disabled={checking}>
                    {checking ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                    {t.imports.continueAuto}
                  </Button>
                ) : (
                  <>
                    {entityType === 'auto' && (
                      <Select value={resolvedType} onValueChange={setResolvedType}>
                        <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="products">{t.nav.products}</SelectItem>
                          <SelectItem value="services">{t.nav.services}</SelectItem>
                          <SelectItem value="clients">{t.nav.clients}</SelectItem>
                          <SelectItem value="suppliers">{t.nav.suppliers}</SelectItem>
                        </SelectContent>
                      </Select>
                    )}
                    <Button onClick={() => setStep(2)}>{t.imports.configureMapping}</Button>
                  </>
                )}
              </div>
            )}
          </div>
        )}

        {/* STEP 2: Column Mapping */}
        {step === 2 && parsedFile && (
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">{t.imports.configMappingDesc}</p>

            <div className="overflow-x-auto max-h-[400px] rounded border">
              <table className="text-sm w-full">
                <thead><tr className="bg-muted/50">
                  <th className="px-3 py-2 text-left font-medium">{t.imports.sourceColumn}</th>
                  <th className="px-3 py-2 text-left font-medium">{t.imports.sampleValue}</th>
                  <th className="px-3 py-2 text-left font-medium">{t.imports.targetField}</th>
                </tr></thead>
                <tbody>
                  {parsedFile.headers.map(header => {
                    const sample = parsedFile.rows[0]?.[header] ?? '';
                    const fields = getFieldsForType(resolvedType);
                    return (
                      <tr key={header} className="border-t">
                        <td className="px-3 py-2 font-medium">{header}</td>
                        <td className="px-3 py-2 text-muted-foreground truncate max-w-[150px]">{String(sample)}</td>
                        <td className="px-3 py-2">
                          <Select
                            value={mapping[header] || '_ignore'}
                            onValueChange={v => setMapping(prev => ({ ...prev, [header]: v === '_ignore' ? null : v }))}
                          >
                            <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
                            <SelectContent>
                              <SelectItem value="_ignore">{t.imports.ignoreColumn}</SelectItem>
                              {Object.entries(fields).map(([key, label]) => (
                                <SelectItem key={key} value={key}>{label}</SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            <div className="flex justify-between">
              <Button variant="outline" onClick={() => setStep(1)}><ArrowLeft className="h-4 w-4 mr-1" />{t.common.back}</Button>
              <Button onClick={goToReview} disabled={checking}>
                {checking ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                {t.imports.continueAuto}
              </Button>
            </div>
          </div>
        )}

        {/* STEP 3: Review & Conflicts */}
        {step === 3 && (
          <div className="space-y-4">
            <div className="grid grid-cols-3 gap-3">
              <div className="rounded-lg border p-3 text-center">
                <FileText className="h-5 w-5 mx-auto mb-1 text-muted-foreground" />
                <p className="text-lg font-bold">{(newRows.length + conflicts.length)}</p>
                <p className="text-xs text-muted-foreground">{t.imports.totalInFile}</p>
              </div>
              <div className="rounded-lg border p-3 text-center bg-success/5">
                <p className="text-lg font-bold text-success">{newRows.length}</p>
                <p className="text-xs text-muted-foreground">{t.imports.newRecords}</p>
              </div>
              <div className={`rounded-lg border p-3 text-center ${conflicts.length > 0 ? 'bg-warning/5' : ''}`}>
                <p className={`text-lg font-bold ${conflicts.length > 0 ? 'text-warning' : ''}`}>{conflicts.length}</p>
                <p className="text-xs text-muted-foreground">{t.imports.conflicts}</p>
              </div>
            </div>

            {conflicts.length > 0 && (
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <h4 className="font-medium text-sm">{t.imports.conflicts}</h4>
                  <div className="flex gap-1">
                    <Button size="sm" variant="outline" onClick={() => setAllConflictResolutions('keep')}>
                      {t.imports.keepCurrent}
                    </Button>
                    <Button size="sm" variant="outline" onClick={() => setAllConflictResolutions('replace')}>
                      {t.imports.replaceWithNew}
                    </Button>
                  </div>
                </div>
                <div className="max-h-48 overflow-y-auto space-y-1">
                  {conflicts.slice(0, 20).map((c, i) => {
                    const name = c.existing.product_name || c.existing.service_name ||
                      c.existing.full_name_or_company_name || c.existing.supplier_name || '—';
                    return (
                      <div key={i} className="flex items-center justify-between rounded border px-3 py-2 text-sm">
                        <span className="truncate flex-1">{name}</span>
                        <div className="flex gap-1">
                          <Button size="sm" variant={c.resolution === 'keep' ? 'default' : 'outline'} className="h-6 text-xs px-2"
                            onClick={() => setConflicts(prev => prev.map((cc, ii) => ii === i ? { ...cc, resolution: 'keep' } : cc))}>
                            {t.imports.keepCurrent}
                          </Button>
                          <Button size="sm" variant={c.resolution === 'replace' ? 'default' : 'outline'} className="h-6 text-xs px-2"
                            onClick={() => setConflicts(prev => prev.map((cc, ii) => ii === i ? { ...cc, resolution: 'replace' } : cc))}>
                            {t.imports.replaceWithNew}
                          </Button>
                        </div>
                      </div>
                    );
                  })}
                  {conflicts.length > 20 && (
                    <p className="text-xs text-muted-foreground text-center">... +{conflicts.length - 20}</p>
                  )}
                </div>
              </div>
            )}

            <div className="flex justify-between">
              <Button variant="outline" onClick={() => setStep(detection?.confidence && detection.confidence >= 80 ? 1 : 2)}>
                <ArrowLeft className="h-4 w-4 mr-1" />{t.common.back}
              </Button>
              <Button onClick={handleImport}>
                {t.imports.startImport} {newRows.length + conflicts.filter(c => c.resolution === 'replace').length} {t.imports.recordsFound.split(' ')[0]}
              </Button>
            </div>
          </div>
        )}

        {/* STEP 4: Importing / Done */}
        {step === 4 && (
          <div className="py-12 text-center space-y-4">
            {!importResult ? (
              <>
                <Loader2 className="h-10 w-10 animate-spin mx-auto text-accent" />
                <p className="font-medium">{t.imports.importing}</p>
              </>
            ) : (
              <>
                <CheckCircle className="h-12 w-12 mx-auto text-success" />
                <p className="text-lg font-bold">{t.imports.importDone}</p>
                <p className="text-muted-foreground">
                  {t.imports.importSummary
                    .replace('{inserted}', String(importResult.inserted))
                    .replace('{updated}', String(importResult.updated))}
                </p>
                <Button onClick={() => { reset(); onOpenChange(false); }}>{t.common.back}</Button>
              </>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
