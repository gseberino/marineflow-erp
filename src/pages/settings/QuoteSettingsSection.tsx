// Aba "QuoteSettingsSection" de Configurações. Extraída de SettingsPage.tsx em 20/09/2026 (o arquivo
// tinha 1.981 linhas); comportamento idêntico, só mudou de endereço.
import { useState, useEffect } from 'react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { FileText, Loader2 } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { useAppSettings, useUpdateAppSettings } from '@/hooks/use-app-settings';
import { validadeDoOrcamento } from '@/lib/pdf-generator';

const PAYMENT_METHOD_OPTIONS = [
  { value: 'pix',           label: 'PIX' },
  { value: 'cash',          label: 'Dinheiro' },
  { value: 'bank_transfer', label: 'Transferência Bancária' },
  { value: 'debit_card',    label: 'Cartão de Débito' },
  { value: 'credit_card',   label: 'Cartão de Crédito' },
  { value: 'boleto',        label: 'Boleto' },
  { value: 'check',         label: 'Cheque' },
];

export function QuoteSettingsSection() {
  // Lê/escreve via os hooks compartilhados (useAppSettings/useUpdateAppSettings) — antes
  // esta seção usava supabase.from() direto, então salvar aqui não invalidava o cache do
  // React Query usado por ServiceOrderForm/PDFOptionsDialog: a validade padrão gravava no
  // banco, mas o resto do app só via o valor novo depois de um refresh completo da página.
  const { data: appSettings, isLoading: loading } = useAppSettings();
  const updateSettings = useUpdateAppSettings();
  const [cfg, setCfg] = useState({
    quote_deposit_percentage: 30,
    default_payment_method:   'pix',
    default_card_fee_percent: 0,
    iss_rate_pct:             5,
    quote_validity_days:      15,
    quote_followup_days:      7,
    survey_valor_limiar:      3000,
  });
  // `quote_expiry_days` saiu do que esta tela grava (26/09/2026): era o prazo em que a rotina
  // quote-reminders REJEITAVA o orçamento sozinha, e ela não o lê mais — o vencimento virou a
  // tarefa da R19. O valor fica no banco como estava (nem apagado, nem reescrito ao salvar) e
  // aparece aqui só para leitura.
  const expiracaoGuardada = appSettings?.quote_expiry_days || '';
  const [initialized, setInitialized] = useState(false);

  useEffect(() => {
    if (!appSettings || initialized) return;
    const m = appSettings;
    setCfg({
      quote_deposit_percentage: Number(m.quote_deposit_percentage) || 30,
      default_payment_method:   m.default_payment_method   || 'pix',
      default_card_fee_percent: Number(m.default_card_fee_percent) || 0,
      iss_rate_pct:             m.iss_rate_pct !== undefined && m.iss_rate_pct !== '' ? Number(m.iss_rate_pct) : 5,
      // O que o PDF e o aviso de vencimento usam de fato (inteiro >= 1, senão 15).
      quote_validity_days:      validadeDoOrcamento(null, m).days,
      quote_followup_days:      Number(m.quote_followup_days)      || 7,
      // Mesmo padrão da função should_survey_service (3000) — a tela e o banco concordam.
      survey_valor_limiar:      Number(m.survey_valor_limiar)      || 3000,
    });
    setInitialized(true);
  }, [appSettings, initialized]);

  const handleSave = async () => {
    const entries = Object.fromEntries(Object.entries(cfg).map(([k, v]) => [k, String(v)]));
    try {
      await updateSettings.mutateAsync(entries);
    } catch {
      /* erro já exibido pelo hook */
    }
  };

  const set = (k: keyof typeof cfg, v: any) => setCfg(prev => ({ ...prev, [k]: v }));
  const saving = updateSettings.isPending;

  if (loading || !initialized) return <p className="text-sm text-muted-foreground">Carregando...</p>;

  return (
    <div className="rounded-xl border bg-card p-6 space-y-5">
      <h3 className="text-sm font-semibold flex items-center gap-2">
        <FileText className="h-4 w-4" /> Configurações de Orçamento
      </h3>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {/* Deposit % */}
        <div className="space-y-1.5">
          <Label>Percentual do sinal (%)</Label>
          <Input type="number" min="0" max="100" value={cfg.quote_deposit_percentage}
            onChange={e => set('quote_deposit_percentage', Number(e.target.value))} />
          <p className="text-xs text-muted-foreground">Valor sugerido ao registrar o pagamento do sinal</p>
        </div>

        {/* Validity days */}
        <div className="space-y-1.5">
          <Label htmlFor="quote-validity-days">Validade padrão do orçamento (dias)</Label>
          <Input id="quote-validity-days" type="number" min="1" value={cfg.quote_validity_days}
            onChange={e => set('quote_validity_days', Number(e.target.value))} />
          <p className="text-xs text-muted-foreground">
            Pré-preenche a validade do orçamento e do PDF. Quando o orçamento não tem validade
            própria, é ela também que define quando aparece o aviso de orçamento vencido.
          </p>
        </div>

        {/* Default payment method */}
        <div className="space-y-1.5">
          <Label>Meio de pagamento padrão</Label>
          <Select value={cfg.default_payment_method} onValueChange={v => set('default_payment_method', v)}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {PAYMENT_METHOD_OPTIONS.map(m => (
                <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <p className="text-xs text-muted-foreground">Pré-selecionado no dialog de registro de sinal</p>
        </div>

        {/* Card fee */}
        <div className="space-y-1.5">
          <Label>Taxa padrão de cartão de crédito (%)</Label>
          <Input type="number" min="0" max="10" step="0.1" value={cfg.default_card_fee_percent}
            onChange={e => set('default_card_fee_percent', Number(e.target.value))} />
          <p className="text-xs text-muted-foreground">Pré-preenchida ao selecionar cartão de crédito</p>
        </div>

        {/* ISS rate */}
        <div className="space-y-1.5">
          <Label>Alíquota de ISS (%)</Label>
          <Input type="number" min="0" max="100" step="0.01" value={cfg.iss_rate_pct}
            onChange={e => set('iss_rate_pct', Number(e.target.value))} />
          <p className="text-xs text-muted-foreground">
            Usada no botão "Aplicar ISS" da composição financeira. Confirme a alíquota correta do seu anexo (Simples Nacional) com seu contador.
          </p>
        </div>

        {/* Expiry days — desativado desde 26/09/2026: ninguém lê mais esta chave (ver acima). */}
        <div className="space-y-1.5">
          <Label htmlFor="quote-expiry-days" className="text-muted-foreground">
            Dias para expiração automática (não é mais usado)
          </Label>
          <Input id="quote-expiry-days" type="number" value={expiracaoGuardada} placeholder="—"
            disabled readOnly />
          <p className="text-xs text-muted-foreground">
            O vencimento agora gera um AVISO: quando um orçamento enviado ou aguardando aprovação
            passa da validade, aparece na Agenda a tarefa "Orçamento vencido: renovar ou
            rejeitar?". Nenhum orçamento é rejeitado sozinho: quem decide é você. O número
            antigo fica guardado, sem efeito.
          </p>
        </div>

        {/* Follow-up days */}
        <div className="space-y-1.5">
          <Label>Dias para lembrete de follow-up</Label>
          <Input type="number" min="1" value={cfg.quote_followup_days}
            onChange={e => set('quote_followup_days', Number(e.target.value))} />
          <p className="text-xs text-muted-foreground">WhatsApp de follow-up automático enviado após esse prazo sem resposta</p>
        </div>

        {/* Limiar do levantamento técnico (NOVO-lev-32). Inteiro de propósito: o banco lê este
            valor com parse_valor_ptbr, que trata "." como separador de milhar. */}
        <div className="space-y-1.5">
          <Label>Valor que exige levantamento técnico (R$)</Label>
          <Input type="number" min="0" step="100" value={cfg.survey_valor_limiar}
            onChange={e => set('survey_valor_limiar', Math.max(0, Math.round(Number(e.target.value) || 0)))} />
          <p className="text-xs text-muted-foreground">Orçamento a partir deste valor pede levantamento antes do serviço (além dos outros motivos: serviço marcado, execuções que variaram, cliente novo)</p>
        </div>
      </div>

      <div className="flex justify-end">
        <Button onClick={handleSave} disabled={saving} size="sm">
          {saving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
          Salvar configurações de orçamento
        </Button>
      </div>
    </div>
  );
}
