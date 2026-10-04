import { useState, useRef, useCallback, useMemo } from 'react';
import { toast } from 'sonner';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Upload, CheckCircle, AlertTriangle, ArrowLeft, ArrowRight, FileText, Loader2 } from 'lucide-react';
import { parseCSVContent, detectFormat, applyMapping, celulasInvalidas, type ParsedFile, type DetectionResult, type ColumnMapping } from '@/lib/import-detector';
import { useCheckConflicts, useImportRows, type ConflictItem } from '@/hooks/use-import';

type EntityType = 'products' | 'services' | 'clients' | 'suppliers' | 'auto';

interface ImportWizardProps {
  entityType: EntityType;
  open: boolean;
  onOpenChange: (v: boolean) => void;
  onComplete?: (count: number) => void;
}

const PRODUCT_FIELDS: Record<string, string> = {
  name: 'Nome*', sku: 'SKU', sale_price: 'Preço venda', cost_price: 'Preço custo',
  stock_quantity: 'Estoque atual', minimum_stock: 'Estoque mínimo', unit: 'Unidade',
  brand: 'Marca', location_bin: 'Localização', notes: 'Notas', active: 'Ativo',
};
const SERVICE_FIELDS: Record<string, string> = {
  name: 'Nome*', default_price: 'Preço padrão', billing_unit: 'Unidade', notes: 'Notas', active: 'Ativo',
};
const CLIENT_FIELDS: Record<string, string> = {
  name: 'Nome*', cnpj_cpf: 'CPF/CNPJ', email: 'Email', phone: 'Telefone',
  address_line_1: 'Endereço', postal_code: 'CEP', city: 'Cidade', state: 'Estado', notes: 'Notas',
};
const SUPPLIER_FIELDS: Record<string, string> = {
  name: 'Razão Social*', cnpj_cpf: 'CNPJ', email: 'Email', phone: 'Telefone',
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
  // Texto no lugar de número ("sob consulta"): a célula fica vazia, nunca 0 — e a conferência
  // diz qual linha (NOVO-import-01, decisão do dono de 12/08/2026).
  const invalidas = useMemo(() => (parsedFile ? celulasInvalidas(parsedFile.rows, mapping) : []), [parsedFile, mapping]);

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
    let parsed = parseCSVContent(content, 'utf-8');

    // Check for garbled chars in headers OR first few rows
    const checkGarbled = (p: ParsedFile) => {
      const sample = [
        ...p.headers,
        ...p.rows.slice(0, 50).flatMap(r => Object.values(r))
      ].join(' ');
      return sample.includes('\ufffd') || sample.includes('Ã') || sample.includes('â');
    };

    if (checkGarbled(parsed)) {
      content = await readWithEncoding('ISO-8859-1');
      parsed = parseCSVContent(content, 'iso-8859-1');
    }

    setParsedFile(parsed);
    const det = detectFormat(parsed);
    setDetection(det);
    setMapping(det.suggestedMapping);
    
    if (entityType === 'auto' || det.confidence >= 80) {
      setResolvedType(det.entityType === 'mixed' ? 'mixed' : det.entityType);
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
      toast.error('Erro ao verificar conflitos: ' + (err?.message || 'Tente novamente'));
    } finally {
      setChecking(false);
    }
  };

  const handleImport = async () => {
    setStep(4);
    try {
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
    } catch (err: any) {
      toast.error('Erro na importação: ' + (err?.message || 'Tente novamente'));
      setStep(3);
    }
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
              // Sem rolagem lateral (Princípio 0, 03/10/2026): a prévia encolhe e corta o texto; o valor
              // inteiro fica no title. No celular, só as 3 primeiras colunas.
              <div className="overflow-y-auto max-h-40 rounded border">
                <table className="text-xs w-full table-fixed">
                  <thead><tr className="bg-muted/50">
                    {parsedFile.headers.slice(0, 6).map((h, c) => (
                      <th key={h} className={`px-2 py-1 text-left font-medium truncate ${c >= 3 ? 'hidden sm:table-cell' : ''}`} title={h}>{h}</th>
                    ))}
                  </tr></thead>
                  <tbody>
                    {parsedFile.rows.slice(0, 3).map((row, i) => (
                      <tr key={i} className="border-t">
                        {parsedFile.headers.slice(0, 6).map((h, c) => (
                          <td key={h} className={`px-2 py-1 truncate ${c >= 3 ? 'hidden sm:table-cell' : ''}`} title={String(row[h] ?? '')}>{row[h]}</td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
                {parsedFile.headers.length > 3 && (
                  <p className="px-2 py-1 text-[11px] text-muted-foreground border-t">
                    {parsedFile.headers.length} colunas no arquivo; a prévia mostra as primeiras.
                  </p>
                )}
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

            {/* Uma linha por coluna do arquivo; no celular, empilhada (sem rolagem lateral). */}
            <div className="overflow-y-auto max-h-[400px] rounded border text-sm" data-testid="mapeamento">
              <div className="hidden sm:grid grid-cols-3 gap-3 bg-muted/50 px-3 py-2 font-medium">
                <span>{t.imports.sourceColumn}</span>
                <span>{t.imports.sampleValue}</span>
                <span>{t.imports.targetField}</span>
              </div>
              <div>
                  {parsedFile.headers.map(header => {
                    const sample = parsedFile.rows[0]?.[header] ?? '';
                    const fields = getFieldsForType(resolvedType);
                    return (
                      <div key={header} className="grid grid-cols-1 sm:grid-cols-3 gap-1 sm:gap-3 items-center border-t px-3 py-2">
                        <span className="font-medium break-words">{header}</span>
                        <span className="text-muted-foreground truncate" title={String(sample)}>{String(sample)}</span>
                        <div>
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
                        </div>
                      </div>
                    );
                  })}
              </div>
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

            {invalidas.length > 0 && (
              <div className="rounded-lg border border-warning/40 bg-warning/5 p-3 text-sm space-y-1" data-testid="celulas-invalidas">
                <p className="font-medium flex items-center gap-2">
                  <AlertTriangle className="h-4 w-4 text-warning shrink-0" />
                  {invalidas.length === 1 ? '1 célula com texto no lugar de número' : `${invalidas.length} células com texto no lugar de número`}
                </p>
                <p className="text-xs text-muted-foreground">
                  Entram vazias, nunca como 0: o produto novo fica sem preço (aparece em "sem preço" no catálogo) e o que já existe mantém o valor atual.
                </p>
                <ul className="text-xs space-y-0.5">
                  {invalidas.slice(0, 20).map((c) => (
                    <li key={`${c.linha}-${c.campo}`} className="break-words">
                      Linha {c.linha} · {({ sale_price: 'preço de venda', cost_price: 'custo', default_price: 'preço', stock_quantity: 'estoque', minimum_stock: 'estoque mínimo' } as Record<string, string>)[c.campo] ?? c.campo}: "{c.valor}"
                    </li>
                  ))}
                </ul>
                {invalidas.length > 20 && <p className="text-xs text-muted-foreground">e mais {invalidas.length - 20}.</p>}
              </div>
            )}

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
                    const name = c.existing.name || c.existing.name ||
                      c.existing.name || c.existing.name || '—';
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
          <div className="flex flex-col items-center justify-center py-12 gap-4">
            {!importResult ? (
              <>
                <Loader2 className="h-10 w-10 animate-spin text-primary" />
                <p className="text-sm font-medium">{t.imports.importing}</p>
                <p className="text-xs text-muted-foreground">
                  Importando {newRows.length} registros em lotes...
                </p>
              </>
            ) : (
              <>
                <CheckCircle className="h-12 w-12 text-success" />
                <p className="text-lg font-semibold">{t.imports.importDone}</p>
                <p className="text-sm text-muted-foreground">
                  {t.imports.importSummary
                    .replace('{inserted}', String(importResult.inserted))
                    .replace('{updated}', String(importResult.updated))}
                </p>
                <Button onClick={() => { reset(); onOpenChange(false); }}>Fechar</Button>
              </>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
