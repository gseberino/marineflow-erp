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

export function PDFOptionsDialog({ open, onOpenChange, documentType, onGenerate }: Props) {
  const { t } = useI18n();
  const [options, setOptions] = useState<PDFOptions>({ ...DEFAULT_PDF_OPTIONS });

  useEffect(() => {
    if (open) setOptions({ ...DEFAULT_PDF_OPTIONS });
  }, [open]);

  const title = documentType === 'quote'
    ? `${t.pdf.generate} — ${t.pdf.quote}`
    : `${t.pdf.generate} — ${t.pdf.serviceOrder}`;

  const checkboxItems: Array<{ key: keyof PDFOptions; label: string }> = [
    { key: 'showServicePrices', label: t.pdf.showServicePrices },
    { key: 'showPartsPrices', label: t.pdf.showPartsPrices },
    { key: 'showTravelCost', label: t.pdf.showTravelCost },
    { key: 'showDiscount', label: t.pdf.showDiscount },
    { key: 'showTax', label: t.pdf.showTax },
    { key: 'showCommission', label: t.pdf.showCommission },
    { key: 'showTerms', label: t.pdf.showTerms },
    { key: 'showSignature', label: t.pdf.showSignature },
  ];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{t.pdf.pdfOptions}</DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-2">
          <p className="text-sm font-medium text-muted-foreground">{t.pdf.itemsToShow}</p>
          {checkboxItems.map(({ key, label }) => (
            <div key={key} className="flex items-center gap-2">
              <Checkbox
                id={key}
                checked={options[key]}
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

        <div className="flex items-start gap-2 rounded-lg border border-border bg-muted p-3">
          <AlertTriangle className="h-4 w-4 text-muted-foreground shrink-0 mt-0.5" />
          <p className="text-xs text-muted-foreground">{t.pdf.pdfHint}</p>
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
