import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { AlertTriangle } from 'lucide-react';
import type { PDFOptions } from '@/lib/pdf-generator';
import { DEFAULT_PDF_OPTIONS } from '@/lib/pdf-generator';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  documentType: 'quote' | 'service_order';
  onGenerate: (options: PDFOptions) => void;
}

const OPTION_KEYS: Array<{ key: keyof PDFOptions; labelKey: keyof typeof import('@/i18n/en').en.pdf }> = [
  { key: 'showServicePrices', labelKey: 'showServicePrices' },
  { key: 'showPartsPrices', labelKey: 'showPartsPrices' },
  { key: 'showTravelCost', labelKey: 'showTravelCost' },
  { key: 'showDiscount', labelKey: 'showDiscount' },
  { key: 'showTax', labelKey: 'showTax' },
  { key: 'showCommission', labelKey: 'showCommission' },
  { key: 'showTerms', labelKey: 'showTerms' },
  { key: 'showSignature', labelKey: 'showSignature' },
];

export function PDFOptionsDialog({ open, onOpenChange, documentType, onGenerate }: Props) {
  const { t } = useI18n();
  const [options, setOptions] = useState<PDFOptions>({ ...DEFAULT_PDF_OPTIONS });

  useEffect(() => {
    if (open) setOptions({ ...DEFAULT_PDF_OPTIONS });
  }, [open]);

  const title = documentType === 'quote'
    ? `${t.pdf.generate} — ${t.pdf.quote}`
    : `${t.pdf.generate} — ${t.pdf.serviceOrder}`;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{t.pdf.pdfOptions}</DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-2">
          <p className="text-sm font-medium text-muted-foreground">{t.pdf.itemsToShow}</p>
          {OPTION_KEYS.map(({ key, labelKey }) => (
            <div key={key} className="flex items-center gap-2">
              <Checkbox
                id={key}
                checked={options[key]}
                onCheckedChange={(checked) =>
                  setOptions(p => ({ ...p, [key]: !!checked }))
                }
              />
              <Label htmlFor={key} className="cursor-pointer text-sm">
                {(t.pdf as any)[labelKey]}
              </Label>
            </div>
          ))}
        </div>

        <div className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3">
          <AlertTriangle className="h-4 w-4 text-amber-600 shrink-0 mt-0.5" />
          <p className="text-xs text-amber-800">{t.pdf.pdfHint}</p>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            {t.common.cancel}
          </Button>
          <Button
            onClick={() => onGenerate(options)}
            className="bg-accent text-accent-foreground hover:bg-accent/90"
          >
            {t.pdf.generate}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
