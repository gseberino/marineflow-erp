// Aba "PdfDefaultsSection" de Configurações. Extraída de SettingsPage.tsx em 20/09/2026 (o arquivo
// tinha 1.981 linhas); comportamento idêntico, só mudou de endereço.
import { useState, useEffect, useRef } from 'react';
import { useI18n } from '@/i18n';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { FileText, Loader2 } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useAppSettings, useUpdateAppSettings } from '@/hooks/use-app-settings';
import { Checkbox } from '@/components/ui/checkbox';
import { DEFAULT_PDF_OPTIONS, resolvePdfOptions, type PDFDocumentType, type PDFOptions } from '@/lib/pdf-generator';
import { pdfOptionItems } from '@/lib/pdf-options-catalog';

const PDF_DEFAULT_DOC_TYPES: Array<{ value: PDFDocumentType; label: string }> = [
  { value: 'quote',         label: 'Orçamento' },
  { value: 'service_order', label: 'Ordem de Serviço' },
  { value: 'invoice',       label: 'Fatura' },
];

/**
 * Padrão da empresa para os PDFs (MF-AUD-014).
 *
 * Esta tela é a ÚNICA que grava `app_settings.pdf_options_<tipo>`. O diálogo de
 * Baixar/Imprimir lê daqui e não escreve mais: o que se marca lá vale para um documento, o
 * que se marca aqui vale para a empresa — inclusive para os PDFs que saem por WhatsApp sem
 * passar por diálogo nenhum.
 */
export function PdfDefaultsSection() {
  const { t } = useI18n();
  const { data: appSettings, isLoading } = useAppSettings();
  const updateSettings = useUpdateAppSettings();

  const [docType, setDocType] = useState<PDFDocumentType>('quote');
  const [draft, setDraft] = useState<Record<string, PDFOptions>>({});
  const [dirty, setDirty] = useState<Set<string>>(new Set());
  const [initialized, setInitialized] = useState(false);
  // NOVO-021: o closure de `salvar` congela `draft` no clique; este ref enxerga o
  // estado pós-edição, para não descartar uma mudança feita com o salvar em voo.
  const draftRef = useRef(draft);
  draftRef.current = draft;

  useEffect(() => {
    if (!appSettings || initialized) return;
    const inicial: Record<string, PDFOptions> = {};
    for (const { value } of PDF_DEFAULT_DOC_TYPES) inicial[value] = resolvePdfOptions(appSettings, value);
    setDraft(inicial);
    setInitialized(true);
  }, [appSettings, initialized]);

  const atual = draft[docType] ?? { ...DEFAULT_PDF_OPTIONS };
  // `includeConditional: false`: fotos de produto aparecem sempre aqui. Lá no diálogo a opção
  // some quando o documento não tem peça com foto; aqui se configura a intenção, não um
  // documento — esconder faria a configuração depender de qual OS o dono abriu por último.
  const itens = pdfOptionItems(docType, t.pdf as unknown as Record<string, string>, { includeConditional: false });

  const alterna = (key: string, marcado: boolean) => {
    setDraft(prev => ({ ...prev, [docType]: { ...(prev[docType] ?? DEFAULT_PDF_OPTIONS), [key]: marcado } }));
    setDirty(prev => new Set(prev).add(docType));
  };

  const salvar = async () => {
    const entries: Record<string, string> = {};
    for (const tipo of dirty) entries[`pdf_options_${tipo}`] = JSON.stringify(draft[tipo] ?? DEFAULT_PDF_OPTIONS);
    if (Object.keys(entries).length === 0) return;
    try {
      await updateSettings.mutateAsync(entries);
      // NOVO-021: `setDirty(new Set())` zerava TUDO — uma marcação feita enquanto o
      // salvar estava em voo era descartada com a tela dizendo "salvo". Só limpa o
      // tipo cujo valor atual é exatamente o que acabou de ser gravado.
      setDirty(prev => {
        const next = new Set(prev);
        for (const chave of Object.keys(entries)) {
          const tipo = chave.replace('pdf_options_', '');
          const atualJson = JSON.stringify(draftRef.current[tipo] ?? DEFAULT_PDF_OPTIONS);
          if (atualJson === entries[chave]) next.delete(tipo);
        }
        return next;
      });
    } catch {
      /* erro já exibido pelo hook */
    }
  };

  if (isLoading || !initialized) {
    return <p className="text-sm text-muted-foreground">{t.common.loading}</p>;
  }

  return (
    <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl space-y-5">
      <div>
        <h3 className="text-sm font-semibold flex items-center gap-2">
          <FileText className="h-4 w-4" /> Padrão dos PDFs
        </h3>
        <p className="text-xs text-muted-foreground mt-1">
          O que sai marcado por padrão em cada documento — e o que vale nos PDFs enviados
          automaticamente por WhatsApp, que não passam pela tela de opções. No momento de gerar
          um documento é possível ajustar sem alterar este padrão.
        </p>
      </div>

      <div className="space-y-1.5">
        <Label>Documento</Label>
        <Select value={docType} onValueChange={(v) => setDocType(v as PDFDocumentType)}>
          <SelectTrigger className="w-full sm:w-64"><SelectValue /></SelectTrigger>
          <SelectContent>
            {PDF_DEFAULT_DOC_TYPES.map(d => (
              <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        {itens.map(({ key, label }) => (
          <div key={key} className="flex items-center gap-2">
            <Checkbox
              id={`pdf-default-${docType}-${key}`}
              checked={!!atual[key]}
              onCheckedChange={(checked) => alterna(key, !!checked)}
            />
            <Label htmlFor={`pdf-default-${docType}-${key}`} className="cursor-pointer text-sm font-normal">
              {label}
            </Label>
          </div>
        ))}
      </div>

      <div className="flex items-center justify-end gap-3">
        {dirty.size > 0 && (
          <span className="text-xs text-muted-foreground">
            {dirty.size === 1 ? '1 documento alterado' : `${dirty.size} documentos alterados`}
          </span>
        )}
        <Button
          onClick={salvar}
          disabled={dirty.size === 0 || updateSettings.isPending}
          className="bg-accent text-accent-foreground hover:bg-accent/90"
        >
          {updateSettings.isPending ? <Loader2 className="h-4 w-4 mr-1.5 animate-spin" /> : null}
          {t.common.saveChanges}
        </Button>
      </div>
    </div>
  );
}
