import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { AlertTriangle, Download, Printer, Loader2 } from 'lucide-react';
import type { PDFOptions, PDFDocumentType } from '@/lib/pdf-generator';
import { DEFAULT_PDF_OPTIONS } from '@/lib/pdf-generator';

export type ValidityConfig = {
  mode: 'days' | 'date';
  days?: number;
  date?: string;
};

export type PDFAction = 'print' | 'download';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  documentType: PDFDocumentType;
  onGenerate: (action: PDFAction, options: PDFOptions, validity?: ValidityConfig, dueDate?: string) => void | Promise<void>;
  hasProductImages?: boolean;
  initialValidityDays?: number;
}

const PREFS_KEY = (docType: PDFDocumentType) => `pdf.prefs.${docType}`;

function loadPrefs(docType: PDFDocumentType): Partial<PDFOptions> {
  try {
    const raw = localStorage.getItem(PREFS_KEY(docType));
    return raw ? JSON.parse(raw) : {};
  } catch { return {}; }
}

function savePrefs(docType: PDFDocumentType, opts: PDFOptions) {
  try { localStorage.setItem(PREFS_KEY(docType), JSON.stringify(opts)); } catch {}
}

export function PDFOptionsDialog({ open, onOpenChange, documentType, onGenerate, hasProductImages, initialValidityDays }: Props) {
  const { t } = useI18n();
  const [options, setOptions] = useState<PDFOptions>({ ...DEFAULT_PDF_OPTIONS });
  const [downloading, setDownloading] = useState(false);
  const [validityMode, setValidityMode] = useState<'days' | 'date'>('days');
  const [validityDays, setValidityDays] = useState(initialValidityDays ?? 15);
  const [validityDate, setValidityDate] = useState('');
  const [dueDate, setDueDate] = useState(() => {
    const d = new Date();
    d.setDate(d.getDate() + 15);
    return d.toISOString().split('T')[0];
  });

  useEffect(() => {
    if (open) {
      // Restore saved preferences for this document type
      const saved = loadPrefs(documentType);
      setOptions({ ...DEFAULT_PDF_OPTIONS, ...saved });
      setDownloading(false);
      setValidityMode('days');
      setValidityDays(initialValidityDays ?? 15);
      setValidityDate('');
      const d = new Date();
      d.setDate(d.getDate() + 15);
      setDueDate(d.toISOString().split('T')[0]);
    }
  }, [open, documentType]);

  const titleMap: Record<PDFDocumentType, string> = {
    quote: `${t.pdf.generate} — ${t.pdf.quote}`,
    service_order: `${t.pdf.generate} — ${t.pdf.serviceOrder}`,
    invoice: `${t.pdf.generate} — Fatura`,
    receipt: `${t.pdf.generate} — Recibo`,
  };

  // Different checkbox set per document type
  const checkboxItems: Array<{ key: keyof PDFOptions; label: string }> = (() => {
    if (documentType === 'invoice') {
      const items: Array<{ key: keyof PDFOptions; label: string }> = [
        { key: 'showServicePrices', label: t.pdf.showServicePrices },
        { key: 'showTravelCost', label: t.pdf.showTravelCost },
        { key: 'showDiscount', label: t.pdf.showDiscount },
        { key: 'showTax', label: t.pdf.showTax },
        { key: 'showBankDetails', label: 'Mostrar dados bancários' },
        { key: 'showPaymentInstructions', label: 'Mostrar instruções de pagamento' },
        { key: 'showTerms', label: t.pdf.showTerms },
      ];
      if (hasProductImages) items.push({ key: 'showProductImages', label: 'Incluir fotos dos produtos' });
      return items;
    }
    if (documentType === 'receipt') {
      // Receipt has no toggleable line-item options; render no checkboxes.
      return [];
    }
    const items: Array<{ key: keyof PDFOptions; label: string }> = [
      { key: 'showServicePrices', label: t.pdf.showServicePrices },
      { key: 'showPartsPrices', label: t.pdf.showPartsPrices },
      { key: 'showTravelCost', label: t.pdf.showTravelCost },
      { key: 'showDiscount', label: t.pdf.showDiscount },
      { key: 'showTax', label: t.pdf.showTax },
      { key: 'showCommission', label: t.pdf.showCommission },
      { key: 'showTerms', label: t.pdf.showTerms },
      { key: 'showSignature', label: t.pdf.showSignature },
    ];
    if (hasProductImages) items.push({ key: 'showProductImages', label: 'Incluir fotos dos produtos' });
    return items;
  })();

  const triggerAction = async (action: PDFAction) => {
    const validity = documentType === 'quote'
      ? { mode: validityMode, days: validityDays, date: validityDate }
      : undefined;
    const due = documentType === 'invoice' ? dueDate : undefined;
    // Persist options for next time
    savePrefs(documentType, options);
    if (action === 'download') {
      setDownloading(true);
      try {
        await onGenerate('download', options, validity, due);
      } finally {
        setDownloading(false);
      }
    } else {
      onGenerate('print', options, validity, due);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!downloading) onOpenChange(v); }}>
      <DialogContent className="sm:max-w-md max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{titleMap[documentType]}</DialogTitle>
          <DialogDescription>{t.pdf.pdfOptions}</DialogDescription>
        </DialogHeader>

        {checkboxItems.length > 0 && (
          <div className="space-y-3 py-2">
            <p className="text-sm font-medium text-muted-foreground">{t.pdf.itemsToShow}</p>
            {checkboxItems.map(({ key, label }) => (
              <div key={key} className="flex items-center gap-2">
                <Checkbox
                  id={key}
                  checked={!!options[key]}
                  onCheckedChange={(checked) =>
                    setOptions(p => ({ ...p, [key]: !!checked }))
                  }
                />
                <Label htmlFor={key} className="cursor-pointer text-sm">
                  {label}
                </Label>
              </div>
            ))}
          </div>
        )}

        {/* Quote validity section */}
        {documentType === 'quote' && (
          <div className="space-y-3 rounded-lg border border-border p-3">
            <p className="text-sm font-medium">Validade do Orçamento</p>
            <div className="flex gap-3">
              <label className="flex items-center gap-1.5 text-sm cursor-pointer">
                <input
                  type="radio"
                  name="validityMode"
                  checked={validityMode === 'days'}
                  onChange={() => setValidityMode('days')}
                />
                Em dias
              </label>
              <label className="flex items-center gap-1.5 text-sm cursor-pointer">
                <input
                  type="radio"
                  name="validityMode"
                  checked={validityMode === 'date'}
                  onChange={() => setValidityMode('date')}
                />
                Data específica
              </label>
            </div>
            {validityMode === 'days' ? (
              <div className="flex items-center gap-2">
                <Input
                  type="number"
                  min={1}
                  value={validityDays}
                  onChange={(e) => setValidityDays(Number(e.target.value) || 15)}
                  className="w-24"
                />
                <span className="text-sm text-muted-foreground">dias a partir da emissão</span>
              </div>
            ) : (
              <Input
                type="date"
                value={validityDate}
                onChange={(e) => setValidityDate(e.target.value)}
                min={new Date().toISOString().split('T')[0]}
              />
            )}
          </div>
        )}

        {/* Invoice due date */}
        {documentType === 'invoice' && (
          <div className="space-y-2 rounded-lg border border-border p-3">
            <Label htmlFor="invoice-due-date" className="text-sm font-medium">Data de Vencimento</Label>
            <Input
              id="invoice-due-date"
              type="date"
              value={dueDate}
              onChange={(e) => setDueDate(e.target.value)}
              min={new Date().toISOString().split('T')[0]}
            />
          </div>
        )}

        <div className="flex items-start gap-2 rounded-lg border border-border bg-muted p-3">
          <AlertTriangle className="h-4 w-4 text-muted-foreground shrink-0 mt-0.5" />
          <p className="text-xs text-muted-foreground">{t.pdf.pdfHint}</p>
        </div>

        <DialogFooter className="flex-col sm:flex-row gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={downloading}>
            {t.common.cancel}
          </Button>
          <Button
            variant="outline"
            disabled={downloading}
            onClick={() => triggerAction('print')}
          >
            <Printer className="h-4 w-4 mr-1.5" />
            {t.pdf.print}
          </Button>
          <Button
            disabled={downloading}
            onClick={() => triggerAction('download')}
            className="bg-accent text-accent-foreground hover:bg-accent/90"
          >
            {downloading
              ? <Loader2 className="h-4 w-4 mr-1.5 animate-spin" />
              : <Download className="h-4 w-4 mr-1.5" />}
            {downloading ? t.pdf.generating : t.pdf.download}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
