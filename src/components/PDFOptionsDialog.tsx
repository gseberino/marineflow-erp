import { useState, useEffect, useRef } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { AlertTriangle, Download, Printer, Loader2 } from 'lucide-react';
import type { PDFOptions, PDFDocumentType } from '@/lib/pdf-generator';
import { DEFAULT_PDF_OPTIONS, resolvePdfOptions } from '@/lib/pdf-generator';
import { pdfOptionItems } from '@/lib/pdf-options-catalog';
import { useAppSetting, useAppSettings } from '@/hooks/use-app-settings';

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

export function PDFOptionsDialog({ open, onOpenChange, documentType, onGenerate, hasProductImages, initialValidityDays }: Props) {
  const { t } = useI18n();
  // Este diálogo NÃO guarda preferência (MF-AUD-014). Ele parte do padrão da empresa —
  // configurado em Configurações › Documentos, chave app_settings.pdf_options_<tipo> — e o
  // que for mexido aqui vale só para o documento que está saindo agora.
  //
  // Antes, cada clique em Baixar/Imprimir gravava os checkboxes em app_settings, que é
  // configuração GLOBAL da empresa: qualquer usuário que desmarcasse "termos e condições"
  // uma vez desligava os termos de todos os documentos futuros daquele tipo, inclusive os
  // enviados por WhatsApp — sem pedir nada e sem avisar ninguém.
  const { data: appSettings } = useAppSettings();
  const defaultQuoteValidityDays = Number(useAppSetting('quote_validity_days', '15')) || 15;

  const [options, setOptions] = useState<PDFOptions>({ ...DEFAULT_PDF_OPTIONS });
  // Enquanto ninguém mexeu nos checkboxes, o padrão da empresa que chegar depois (a query de
  // app_settings pode resolver com o diálogo já aberto) ainda é aplicado. Depois do primeiro
  // clique, não — seria trocar a escolha do usuário debaixo dele.
  const optionsTouched = useRef(false);
  const [downloading, setDownloading] = useState(false);
  const [validityMode, setValidityMode] = useState<'days' | 'date'>('days');
  const [validityDays, setValidityDays] = useState(initialValidityDays ?? defaultQuoteValidityDays);
  const [validityDate, setValidityDate] = useState('');
  const [dueDate, setDueDate] = useState(() => {
    const d = new Date();
    d.setDate(d.getDate() + 15);
    return d.toISOString().split('T')[0];
  });

  // A via de execução (NOVO-006b) é escolha de UM documento e sempre começa desmarcada: um
  // padrão que apagasse valores sem ninguém pedir seria pior que o problema que ela resolve.
  const padraoDaEmpresa = (settings: Record<string, string> | undefined): PDFOptions =>
    ({ ...resolvePdfOptions(settings, documentType), hideFinancials: false });

  useEffect(() => {
    if (open) {
      optionsTouched.current = false;
      setOptions(padraoDaEmpresa(appSettings));
      setDownloading(false);
      setValidityMode('days');
      setValidityDays(initialValidityDays ?? defaultQuoteValidityDays);
      setValidityDate('');
      const d = new Date();
      d.setDate(d.getDate() + 15);
      setDueDate(d.toISOString().split('T')[0]);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, documentType]);

  // O padrão da empresa que chega tarde (query ainda em voo quando o diálogo abriu) precisa
  // alcançar os checkboxes; sem isto, quem abrisse o diálogo antes da rede responder geraria
  // o documento com o padrão de fábrica em vez do configurado.
  useEffect(() => {
    if (!open || optionsTouched.current || !appSettings) return;
    setOptions(padraoDaEmpresa(appSettings));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, appSettings, documentType]);

  const titleMap: Record<PDFDocumentType, string> = {
    quote: `${t.pdf.generate} — ${t.pdf.quote}`,
    service_order: `${t.pdf.generate} — ${t.pdf.serviceOrder}`,
    invoice: `${t.pdf.generate} — Fatura`,
    receipt: `${t.pdf.generate} — Recibo`,
  };

  // Quais toggles existem por tipo de documento vem do catálogo compartilhado com a tela de
  // padrão da empresa (recibo não tem nenhum). Duas listas separadas divergiriam na primeira
  // opção nova.
  const checkboxItems = pdfOptionItems(documentType, t.pdf as unknown as Record<string, string>, { hasProductImages });

  // "Via de execução" não convive com os outros: ela tira TODOS os valores do documento, e os
  // demais toggles decidem quais valores aparecem. Deixá-los clicáveis prometeria um efeito
  // que não existe — então ficam desabilitados enquanto ela estiver marcada.
  const anulaOsOutros = checkboxItems.some(i => i.overridesOthers && !!options[i.key]);

  const triggerAction = async (action: PDFAction) => {
    const validity = documentType === 'quote'
      ? { mode: validityMode, days: validityDays, date: validityDate }
      : undefined;
    const due = documentType === 'invoice' ? dueDate : undefined;
    // Nada é gravado aqui, de propósito: o que foi marcado vale para este documento e acaba
    // quando o diálogo fecha. Mudar o padrão é em Configurações › Documentos (MF-AUD-014).
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
            <div className="space-y-0.5">
              <p className="text-sm font-medium text-muted-foreground">{t.pdf.itemsToShow}</p>
              <p className="text-xs text-muted-foreground">{t.pdf.optionsScopeHint}</p>
            </div>
            {checkboxItems.map(({ key, label, overridesOthers }) => {
              const desabilitado = anulaOsOutros && !overridesOthers;
              return (
                <div key={key} className={`flex items-center gap-2${desabilitado ? ' opacity-50' : ''}`}>
                  <Checkbox
                    id={key}
                    checked={!!options[key]}
                    disabled={desabilitado}
                    onCheckedChange={(checked) => {
                      optionsTouched.current = true;
                      setOptions(p => ({ ...p, [key]: !!checked }));
                    }}
                  />
                  <Label htmlFor={key} className={`text-sm${desabilitado ? '' : ' cursor-pointer'}`}>
                    {label}
                  </Label>
                </div>
              );
            })}
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
                  onChange={(e) => setValidityDays(Number(e.target.value) || defaultQuoteValidityDays)}
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
