import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { useCreateService, useUpdateService } from '@/hooks/use-services';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { toast } from 'sonner';
import { MoneyInput } from '@/components/MoneyInput';
import {
  useServiceSystems, AXIS_LABEL, DEPENDS_ON_ORDER, DEPENDS_ON_ORDER_LABEL,
  systemChoiceToDb, systemDbToChoice,
} from '@/hooks/use-service-systems';
import { VERBOS, VERB_LABEL } from '@/hooks/use-service-classification';
import { useServiceFiscalVerbs } from '@/hooks/use-service-fiscal';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  editData?: any;
  onCreated?: (service: any) => void;
  /** Chamado após QUALQUER salvar com sucesso (criar ou editar) — p/ quem abriu o popup revalidar (ex.: pré-voo fiscal). */
  onSaved?: (id: string) => void;
}

export function ServiceFormDialog({ open, onOpenChange, editData, onCreated, onSaved }: Props) {
  const { t } = useI18n();
  const create = useCreateService();
  const update = useUpdateService();
  const { data: sistemas = [] } = useServiceSystems();
  const { data: verbosFiscais = [] } = useServiceFiscalVerbs();

  // `category` (texto livre) foi aposentado em 02/08: estava vazio em 257 dos
  // 262 serviços e concorria com service_system, que é o que de fato classifica
  // — é ele que traz a abertura e o fechamento de segurança do roteiro.
  const VAZIO = {
    name: '',
    description: '',
    service_system: '',
    service_verb: '',
    billing_unit: 'hour',
    default_price: 0,
    currency: 'BRL',
    active: true,
    default_warranty_days: 0,
    // Cadastro fiscal PRÓPRIO (override). Vazio = herda do verbo fiscal — é o caminho
    // normal: a contabilidade preenche as 10 linhas de verbo e o catálogo inteiro resolve.
    fiscal_verb: '',
    national_tax_code: '',
    service_code: '',
    cnae: '',
    iss_rate: '' as string | number,
    iss_withheld: 'herda' as 'herda' | 'sim' | 'nao',
  };
  const [form, setForm] = useState(VAZIO);

  useEffect(() => {
    if (editData) {
      setForm({
        name: editData.name || '',
        description: editData.description || '',
        service_system: editData.service_system || '',
        service_verb: editData.service_verb || '',
        billing_unit: editData.billing_unit || 'hour',
        default_price: editData.default_price || 0,
        currency: editData.currency || 'BRL',
        active: editData.active ?? true,
        default_warranty_days: editData.default_warranty_days ?? 0,
        fiscal_verb: editData.fiscal_verb || '',
        national_tax_code: editData.national_tax_code || '',
        service_code: editData.service_code || '',
        cnae: editData.cnae || '',
        iss_rate: editData.iss_rate ?? '',
        iss_withheld: editData.iss_withheld === true ? 'sim' : editData.iss_withheld === false ? 'nao' : 'herda',
      });
    } else {
      setForm(VAZIO);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editData, open]);

  const set = (field: string, value: any) => setForm((p) => ({ ...p, [field]: value }));

  const handleSave = async () => {
    if (!form.name.trim()) return;
    // CHECKs do banco viram mensagem ANTES do submit — o formato de rejeição da prefeitura
    // chegaria minutos depois e longe da causa.
    const ntc = String(form.national_tax_code).replace(/\D/g, '');
    if (form.national_tax_code && ntc.length !== 6) {
      toast.error('Código de tributação nacional precisa ter exatamente 6 dígitos (ex.: 140101).');
      return;
    }
    const cnaeDigits = String(form.cnae).replace(/\D/g, '');
    if (form.cnae && cnaeDigits.length !== 7) {
      toast.error('CNAE precisa ter exatamente 7 dígitos, sem pontos nem barra.');
      return;
    }
    try {
      // A coluna é `name`. O código antigo mandava `service_name`, que não
      // existe no schema — salvar por este diálogo falhava em silêncio para
      // quem não olhava o toast de erro.
      // Vazio vira null de propósito: '' violaria a FK de service_systems, e
      // sistema nulo tem significado ("depende da OS").
      // Fiscal: vazio = null = herda do verbo fiscal; iss_withheld null = "não decidido"
      // (a herança do NOVO-014 depende disso — false explícito NÃO herda).
      const payload = {
        ...form,
        service_system: form.service_system || null,
        service_verb: form.service_verb || null,
        fiscal_verb: form.fiscal_verb || null,
        national_tax_code: ntc || null,
        service_code: String(form.service_code).trim() || null,
        cnae: cnaeDigits || null,
        iss_rate: form.iss_rate === '' || form.iss_rate == null ? null : Number(form.iss_rate),
        iss_withheld: form.iss_withheld === 'herda' ? null : form.iss_withheld === 'sim',
      };
      if (editData?.id) {
        await update.mutateAsync({ id: editData.id, ...payload });
        toast.success(t.services.updateSuccess);
        onSaved?.(editData.id);
      } else {
        const result = await create.mutateAsync(payload);
        toast.success(t.services.createSuccess);
        onCreated?.(result);
        if ((result as any)?.id) onSaved?.((result as any).id);
      }
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e.message || 'Erro');
    }
  };

  const billingUnits = [
    { value: 'hour', label: t.services.unitHour },
    { value: 'visit', label: t.services.unitVisit },
    { value: 'day', label: t.services.unitDay },
    { value: 'unit', label: t.services.unitUnit },
  ];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{editData ? t.services.editService : t.services.newService}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div>
            <Label>{t.services.serviceName} *</Label>
            <Input value={form.name} onChange={(e) => set('name', e.target.value)} className="mt-1" />
          </div>
          <div>
            <Label>{t.common.description}</Label>
            <Textarea value={form.description} onChange={(e) => set('description', e.target.value)} rows={2} className="mt-1" />
          </div>
          {/* Os dois eixos que geram o roteiro. O sistema decide a preparação e
              o fechamento de segurança; o verbo decide o corpo. Deixar o sistema
              em branco é dizer "depende da OS" — aí quem monta a OS escolhe. */}
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <Label>{AXIS_LABEL}</Label>
              <Select
                value={systemDbToChoice(form.service_system)}
                onValueChange={(v) => set('service_system', systemChoiceToDb(v) ?? '')}
              >
                <SelectTrigger className="mt-1">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {/* Primeiro item de propósito: é a escolha que transforma o
                      serviço em genérico, e antes ela não existia. */}
                  <SelectItem value={DEPENDS_ON_ORDER}>{DEPENDS_ON_ORDER_LABEL}</SelectItem>
                  {sistemas.map((s) => (
                    <SelectItem key={s.slug} value={s.slug}>{s.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {!form.service_system && (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  Cada OS vai perguntar qual sistema este serviço toca — e o roteiro sai diferente
                  conforme a resposta.
                </p>
              )}
            </div>
            <div>
              <Label>O que se faz (verbo)</Label>
              <Select value={form.service_verb} onValueChange={(v) => set('service_verb', v)}>
                <SelectTrigger className="mt-1">
                  <SelectValue placeholder="Não definido" />
                </SelectTrigger>
                <SelectContent>
                  {VERBOS.map((v) => (
                    <SelectItem key={v} value={v}>{VERB_LABEL[v] ?? v}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>{t.services.billingUnit}</Label>
              <Select value={form.billing_unit} onValueChange={(v) => set('billing_unit', v)}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {billingUnits.map((u) => (
                    <SelectItem key={u.value} value={u.value}>{u.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>{t.services.defaultPrice}</Label>
              <MoneyInput value={form.default_price} onValueChange={(v) => set('default_price', v)} className="mt-1" />
            </div>
            <div>
              <Label>{t.products.costCurrency}</Label>
              <Select value={form.currency} onValueChange={(v) => set('currency', v)}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="BRL">BRL</SelectItem>
                  <SelectItem value="USD">USD</SelectItem>
                  <SelectItem value="EUR">EUR</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <Switch checked={form.active} onCheckedChange={(v) => set('active', v)} />
              <Label>{t.common.active}</Label>
            </div>
            <div className="flex-1">
              <Label className="text-xs">Garantia Padrão (dias)</Label>
              <Input type="number" min="0" value={(form as any).default_warranty_days ?? 0} onChange={(e) => set('default_warranty_days', Number(e.target.value))} />
            </div>
          </div>

          {/* ── Fiscal (NFS-e) ─────────────────────────────────────────────────
              O caminho normal é HERDAR do verbo fiscal (a contabilidade preenche 10 linhas
              em Configurações → Fiscal e o catálogo inteiro resolve). Os campos daqui são o
              OVERRIDE para o serviço que foge da regra da atividade. */}
          <div className="rounded-md border p-3 space-y-3">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <p className="text-sm font-semibold">Fiscal (NFS-e)</p>
                <p className="text-xs text-muted-foreground">
                  Deixe em branco para herdar do verbo fiscal — preencher aqui é a exceção.
                </p>
              </div>
              {/* Preenche pela regra CONFIRMADA pela contadora (18/08/2026): tudo 14.01,
                  ISS 3% Itajaí, CNAE 3317102. Preferência: ligar a HERANÇA pelo verbo
                  (corrigir o verbo corrige o catálogo); sem verbo, valores próprios. */}
              <Button
                type="button" variant="outline" size="sm"
                onClick={() => {
                  const verboOperacional = form.service_verb || '';
                  if (verboOperacional) {
                    set('fiscal_verb', verboOperacional);
                    set('national_tax_code', '');
                    set('cnae', '');
                    set('iss_rate', '');
                    set('service_code', '');
                    toast.info(`Herança ligada pelo verbo "${verboOperacional}" (regra da contadora: 14.01, ISS 3%). Confira e salve.`);
                  } else {
                    set('national_tax_code', '140101');
                    set('cnae', '3317102');
                    set('iss_rate', '3');
                    set('service_code', '14.01');
                    toast.info('Valores da regra da contadora aplicados (14.01, ISS 3%, CNAE 3317102). Confira e salve.');
                  }
                  set('iss_withheld', 'nao');
                }}
              >
                Aplicar regra da contadora
              </Button>
            </div>
            <div>
              <Label>Verbo fiscal (herança)</Label>
              <Select value={form.fiscal_verb || 'nenhum'} onValueChange={(v) => set('fiscal_verb', v === 'nenhum' ? '' : v)}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="nenhum">Sem herança (só o cadastro próprio vale)</SelectItem>
                  {verbosFiscais.map((v) => (
                    <SelectItem key={v.verb_slug} value={v.verb_slug}>
                      {v.name}{v.default_national_tax_code ? ` · ${v.default_national_tax_code}` : ' · sem código ainda'}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {form.fiscal_verb && !form.national_tax_code && (() => {
                const verbo = verbosFiscais.find((v) => v.verb_slug === form.fiscal_verb);
                return (
                  <p className="mt-1 text-[11px] text-muted-foreground">
                    {verbo?.default_national_tax_code
                      ? `Este serviço herda o código ${verbo.default_national_tax_code} do verbo "${verbo.name}".`
                      : 'O verbo escolhido ainda não tem código — a contabilidade preenche em Configurações → Fiscal → Verbos.'}
                  </p>
                );
              })()}
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <Label>Código de tributação nacional</Label>
                <Input
                  value={form.national_tax_code}
                  onChange={(e) => set('national_tax_code', e.target.value)}
                  placeholder="6 dígitos, ex.: 140101"
                  className="mt-1"
                  inputMode="numeric"
                />
              </div>
              <div>
                <Label>CNAE</Label>
                <Input
                  value={form.cnae}
                  onChange={(e) => set('cnae', e.target.value)}
                  placeholder="7 dígitos"
                  className="mt-1"
                  inputMode="numeric"
                />
              </div>
              <div>
                <Label>Código municipal do serviço</Label>
                <Input
                  value={form.service_code}
                  onChange={(e) => set('service_code', e.target.value)}
                  placeholder="Opcional (ex.: 14.01)"
                  className="mt-1"
                />
              </div>
              <div>
                <Label>Alíquota de ISS (%)</Label>
                <Input
                  type="number" min="0" max="100" step="0.01"
                  value={form.iss_rate}
                  onChange={(e) => set('iss_rate', e.target.value)}
                  placeholder="Ex.: 3"
                  className="mt-1"
                />
              </div>
            </div>
            <div>
              <Label>Retenção de ISS pelo tomador</Label>
              <Select value={form.iss_withheld} onValueChange={(v) => set('iss_withheld', v)}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="herda">Herdar do verbo fiscal (padrão)</SelectItem>
                  <SelectItem value="nao">Sem retenção (decisão deste serviço)</SelectItem>
                  <SelectItem value="sim">Retido pelo tomador</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => onOpenChange(false)}>{t.common.cancel}</Button>
            <Button onClick={handleSave} disabled={create.isPending || update.isPending}
              className="bg-accent text-accent-foreground hover:bg-accent/90">
              {t.common.save}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
