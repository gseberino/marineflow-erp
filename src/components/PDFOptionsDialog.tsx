import { useState, useEffect, useRef } from 'react';
import { useI18n } from '@/i18n';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { AlertTriangle, Download, Printer, Loader2 } from 'lucide-react';
import type { PDFOptions, PDFDocumentType } from '@/lib/pdf-generator';
import {
  DEFAULT_PDF_OPTIONS,
  primeiraValidade,
  resolvePdfOptions,
  VALIDADE_MAXIMA_EM_DIAS,
  validadeDoOrcamento,
} from '@/lib/pdf-generator';
import { pdfOptionItems } from '@/lib/pdf-options-catalog';
import { isFinancialOption } from '@/lib/pdf-visibility';
import { useAppSettings } from '@/hooks/use-app-settings';

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
  /**
   * A data fixa de validade do orçamento (service_orders.quote_validity_date), se houver. Com
   * ela o diálogo abre em "Data específica" com essa data — a mesma que a R19 usa para avisar
   * do vencimento. Sem ela o PDF dizia "Válido por N dias" de um orçamento com data fixa.
   */
  initialValidityDate?: string | null;
}

export function PDFOptionsDialog({
  open, onOpenChange, documentType, onGenerate, hasProductImages, initialValidityDays, initialValidityDate,
}: Props) {
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
  // O ponto de partida da validade, pela função única do PDF — a mesma do formulário, do
  // envio pela tela, do portal, do assistente e da R19: a data fixa do orçamento, senão os
  // dias dele, senão o padrão da empresa (app_settings), senão 15. A cópia própria que havia
  // aqui (`Number(...) || 15`) aceitava -1 e 2.5; um initialValidityDays inválido (-1, 2.5,
  // 1e9) também não chega ao campo — passa a vez ao padrão.
  const inicial = validadeDoOrcamento(initialValidityDays, appSettings, initialValidityDate);
  const inicialModo = inicial.mode;
  const inicialDias = inicial.days;
  const inicialData = inicial.mode === 'date' ? inicial.date : '';

  const [options, setOptions] = useState<PDFOptions>({ ...DEFAULT_PDF_OPTIONS });
  // Enquanto ninguém mexeu nos checkboxes, o padrão da empresa que chegar depois (a query de
  // app_settings pode resolver com o diálogo já aberto) ainda é aplicado. Depois do primeiro
  // clique, não — seria trocar a escolha do usuário debaixo dele.
  const optionsTouched = useRef(false);
  // O mesmo para a validade. As listas abrem o diálogo no clique, antes de os dados da ordem
  // chegarem: `initialValidityDays` nasce com o padrão da empresa e só depois vira a validade
  // do orçamento. Sem acompanhar essa troca, o campo ficava no padrão e o PDF saía com ele.
  const validityTouched = useRef(false);
  const [downloading, setDownloading] = useState(false);
  const [validityMode, setValidityMode] = useState<'days' | 'date'>(inicialModo);
  const [validityDays, setValidityDays] = useState(inicialDias);
  const [validityDate, setValidityDate] = useState(inicialData);
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
      validityTouched.current = false;
      setOptions(padraoDaEmpresa(appSettings));
      setDownloading(false);
      setValidityMode(inicialModo);
      setValidityDays(inicialDias);
      setValidityDate(inicialData);
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

  // A validade do orçamento (ou o padrão da empresa) que chega tarde alcança o campo enquanto
  // ninguém o editou; depois de editado, o que a pessoa escolheu fica.
  useEffect(() => {
    if (!open || validityTouched.current) return;
    setValidityMode(inicialModo);
    setValidityDays(inicialDias);
    setValidityDate(inicialData);
  }, [open, inicialModo, inicialDias, inicialData]);

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

  // "Via de execução" não convive com os toggles de VALOR: ela tira todos os valores do
  // documento, e esses toggles decidem quais valores aparecem. Deixá-los clicáveis prometeria
  // um efeito que não existe — então ficam desabilitados enquanto ela estiver marcada. Os que
  // não decidem valor (termos, assinatura, fotos) continuam valendo na folha de campo, e o
  // gerador continua lendo cada um: quem quer a via de execução SEM termos precisa desmarcar.
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
              const desabilitado = anulaOsOutros && !overridesOthers && isFinancialOption(key);
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
                  onChange={() => { validityTouched.current = true; setValidityMode('days'); }}
                />
                Em dias
              </label>
              <label className="flex items-center gap-1.5 text-sm cursor-pointer">
                <input
                  type="radio"
                  name="validityMode"
                  checked={validityMode === 'date'}
                  onChange={() => { validityTouched.current = true; setValidityMode('date'); }}
                />
                Data específica
              </label>
            </div>
            {validityMode === 'days' ? (
              <div className="flex items-center gap-2">
                <Input
                  type="number"
                  min={1}
                  max={VALIDADE_MAXIMA_EM_DIAS}
                  step={1}
                  value={validityDays}
                  onChange={(e) => {
                    validityTouched.current = true;
                    // A mesma regra do PDF (primeiraValidade): -1, 0, 2.5 e 1e9 não entram. O
                    // que não serve volta ao número com que o diálogo abriu (o do orçamento,
                    // senão o da empresa). Era `Number(x) || padrão`, que deixava -1 e 2.5.
                    setValidityDays(primeiraValidade(e.target.value, inicialDias));
                  }}
                  className="w-24"
                />
                <span className="text-sm text-muted-foreground">dias a partir da emissão</span>
              </div>
            ) : (
              <Input
                type="date"
                value={validityDate}
                onChange={(e) => { validityTouched.current = true; setValidityDate(e.target.value); }}
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
