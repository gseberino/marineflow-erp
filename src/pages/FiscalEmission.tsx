import { useEffect, useMemo, useRef, useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { AddressFields } from '@/components/AddressFields';
import { EntityCombobox, type EntityOption } from '@/components/EntityCombobox';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  FileText, Loader2, Plus, Trash2, RefreshCw, Download, Ban, Pencil, Settings2, Upload,
} from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useClients } from '@/hooks/use-clients';
import { useProducts } from '@/hooks/use-products';
import { useProductCategories } from '@/hooks/use-product-categories';
import { useAppSettings } from '@/hooks/use-app-settings';
import { useI18n } from '@/i18n';
import { maskCPFCNPJ } from '@/lib/masks';
import { parseNfeReferenceXml } from '@/lib/nfe-xml-parser';
// Reaproveita os mesmos módulos que a edge function fiscal-emit usa no
// servidor — evita duplicar a lista de formas de pagamento, natureza de
// operação/CFOP e o CFOP padrão.
import {
  PAYMENT_METHODS, NATURE_OF_OPERATION_OPTIONS, findNatureOfOperation, computeCfop,
} from '../../supabase/functions/_shared/fiscal/payload-builder';
import {
  resolveProductFiscal, type GlobalFiscalDefaults, type ResolvedProductFiscal,
} from '../../supabase/functions/_shared/fiscal/product-fiscal';

// Indicador de IE do destinatário (indIEDest).
const IE_INDICATORS = [
  { value: 9, label: 'Não contribuinte (consumidor)' },
  { value: 1, label: 'Contribuinte do ICMS' },
  { value: 2, label: 'Isento de Inscrição Estadual' },
];

// Indicador de presença (indPres) — os casos comuns do HBR.
const PRESENCE_INDICATORS = [
  { value: 1, label: 'Presencial' },
  { value: 9, label: 'Não presencial / outros' },
  { value: 2, label: 'Internet' },
  { value: 4, label: 'Entrega a domicílio' },
  { value: 0, label: 'Não se aplica' },
];

const SIMPLES_INFO_NOTE =
  'Documento emitido por optante do Simples Nacional. Não gera direito a crédito fiscal de IPI. ' +
  'Permite o aproveitamento do crédito de ICMS conforme a legislação (art. 23 da LC 123/2006).';

const MIN_JUSTIFICATION_LENGTH = 15; // mesmo mínimo exigido pela SEFAZ, checado de novo no backend

const BRAZILIAN_STATES = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG',
  'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
];

// ── Types ──────────────────────────────────────────────────────────────────
interface DraftItem {
  productId: string | null;
  code: string;
  name: string;
  ncm: string;
  cfop: string;
  unit: string;
  quantity: number;
  unit_price: number;
  // Campos tributários (auto-preenchidos do produto, editáveis). Viram o bloco
  // `taxes` no servidor. O CST de PIS/COFINS vem do default global (não por item).
  csosn: string;
  origin: number;
  icms_rate: number;
  pis_rate: number;
  cofins_rate: number;
  ipi_rate: number;
}

const EMPTY_RESOLVED = { csosn: '400', origin: 0, icms_rate: 0, pis_rate: 0, cofins_rate: 0, ipi_rate: 0 };

interface AddressState {
  postal_code: string;
  address_line_1: string;
  address_number: string;
  address_complement: string;
  neighborhood: string;
  city: string;
  state: string;
  country: string;
}

const EMPTY_ADDRESS: AddressState = {
  postal_code: '', address_line_1: '', address_number: '', address_complement: '',
  neighborhood: '', city: '', state: '', country: 'Brasil',
};

const STATUS_MAP: Record<string, { label: string; className: string }> = {
  draft:      { label: 'Rascunho',    className: 'bg-muted text-muted-foreground' },
  queued:     { label: 'Na fila',     className: 'bg-amber-100 text-amber-800' },
  processing: { label: 'Processando', className: 'bg-amber-100 text-amber-800' },
  authorized: { label: 'Autorizada',  className: 'bg-success/15 text-success' },
  rejected:   { label: 'Rejeitada',   className: 'bg-destructive/15 text-destructive' },
  failed:     { label: 'Falhou',      className: 'bg-destructive/15 text-destructive' },
  cancelled:  { label: 'Cancelada',   className: 'bg-muted text-muted-foreground' },
};

// supabase-js lança FunctionsHttpError em qualquer resposta não-2xx, com uma
// mensagem genérica ("Edge Function returned a non-2xx status code") — o
// corpo JSON real ({error: "..."}) só é acessível via error.context.json().
// Sem isso, toda mensagem específica do backend (validação, rejeição da
// SEFAZ, etc.) era substituída por esse texto inútil no toast.
async function extractInvokeErrorMessage(error: unknown): Promise<string> {
  if (error && typeof error === 'object' && 'context' in error) {
    const ctx = (error as { context?: unknown }).context;
    if (ctx && typeof (ctx as Response).json === 'function') {
      try {
        const parsed = await (ctx as Response).clone().json();
        if (parsed?.error) return String(parsed.error);
      } catch {
        // corpo não era JSON — cai para a mensagem genérica abaixo
      }
    }
  }
  return error instanceof Error ? error.message : String(error);
}

// ── Hooks locais ───────────────────────────────────────────────────────────
// company_fiscal_settings e issued_fiscal_documents são tabelas novas (ver
// migração 20260714120000_fiscal_emit_foundation.sql) ainda não presentes no
// types.ts gerado — mesmo padrão de cast já usado em ImportFiscalXML.tsx para
// a RPC confirm_nfe_import. Regenerar os tipos do Supabase remove a necessidade.
function useCompanyFiscalSettings() {
  return useQuery({
    queryKey: ['company_fiscal_settings'],
    queryFn: async () => {
      const { data, error } = await (supabase.from as any)('company_fiscal_settings')
        .select('*')
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
    staleTime: 60_000,
  });
}

function useIssuedFiscalDocuments() {
  return useQuery({
    queryKey: ['issued_fiscal_documents'],
    queryFn: async () => {
      const { data, error } = await (supabase.from as any)('issued_fiscal_documents')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(100);
      if (error) throw error;
      return data || [];
    },
    staleTime: 15_000,
  });
}

// ── Página ─────────────────────────────────────────────────────────────────
export default function FiscalEmission() {
  const { formatCurrency, formatDate } = useI18n();
  const qc = useQueryClient();

  const { data: company, isLoading: loadingCompany } = useCompanyFiscalSettings();
  const { data: documents, isLoading: loadingDocs } = useIssuedFiscalDocuments();
  const { data: clients } = useClients();
  const { data: products } = useProducts();
  const { data: productCategories } = useProductCategories();
  const { data: appSettings } = useAppSettings();

  // Defaults fiscais globais (fim da hierarquia produto→categoria→global). O
  // hook devolve um mapa key→value; convertemos para o formato do resolver.
  const globalFiscalDefaults: GlobalFiscalDefaults = useMemo(() => {
    const m = appSettings || {};
    const n = (k: string) => (m[k] != null && m[k] !== '' && !Number.isNaN(Number(m[k])) ? Number(m[k]) : undefined);
    return {
      default_csosn: m['default_csosn'] || undefined,
      default_fiscal_origin: n('default_fiscal_origin'),
      default_icms_rate: n('default_icms_rate'),
      default_ipi_rate: n('default_ipi_rate'),
      default_pis_rate: n('default_pis_rate'),
      default_cofins_rate: n('default_cofins_rate'),
      default_pis_cst: m['default_pis_cst'] || undefined,
      default_cofins_cst: m['default_cofins_cst'] || undefined,
    };
  }, [appSettings]);

  // Resolve os campos fiscais efetivos de um produto (produto→categoria→global),
  // para pré-preencher os impostos do item. Mesmo cálculo do servidor.
  const resolveItemFiscal = (productId: string | null): ResolvedProductFiscal => {
    const p = productId ? (products || []).find((pr) => pr.id === productId) : null;
    const cat = p?.product_category_id ? (productCategories || []).find((c) => c.id === p.product_category_id) : null;
    return resolveProductFiscal(p, cat, globalFiscalDefaults);
  };

  const [showSettings, setShowSettings] = useState(false);
  const [savingSettings, setSavingSettings] = useState(false);
  const [settingsForm, setSettingsForm] = useState({
    legal_name: '', trade_name: '', cnpj: '', state_registration: '',
    municipal_registration: '', tax_regime: 'simples', crt: 1, state_code: '',
    street: '', number: '', district: '', city_name: '', postal_code: '',
  });

  const [showEmit, setShowEmit] = useState(false);
  const [emitting, setEmitting] = useState(false);
  const [emitIdempotencyKey, setEmitIdempotencyKey] = useState('');
  const [natureOfOperation, setNatureOfOperation] = useState('venda');
  const [clientId, setClientId] = useState<string>('');
  const [recipientName, setRecipientName] = useState('');
  const [recipientDocument, setRecipientDocument] = useState('');
  const [recipientEmail, setRecipientEmail] = useState('');
  const [recipientIeIndicator, setRecipientIeIndicator] = useState(9);
  const [recipientIe, setRecipientIe] = useState('');
  const [address, setAddress] = useState<AddressState>(EMPTY_ADDRESS);
  const [paymentMethod, setPaymentMethod] = useState('01');
  const [presenceIndicator, setPresenceIndicator] = useState(1);
  const [consumerFinal, setConsumerFinal] = useState(true);
  const [additionalInfo, setAdditionalInfo] = useState('');
  const [referencedAccessKey, setReferencedAccessKey] = useState('');
  const [items, setItems] = useState<DraftItem[]>([]);
  const xmlInputRef = useRef<HTMLInputElement>(null);

  const selectedNature = useMemo(() => findNatureOfOperation(natureOfOperation), [natureOfOperation]);
  // Prévia do CFOP que será aplicado a itens novos — a mesma regra que o
  // backend usa (intra vs. interestadual conforme UF emitente x destinatário),
  // só que calculada aqui pra já popular os campos sem round-trip.
  const defaultItemCfop = useMemo(
    () => computeCfop(selectedNature.baseCfopCode, selectedNature.operationType, company?.state_code, address.state),
    [selectedNature, company?.state_code, address.state],
  );

  // addItem()/handleItemProductChange() gravam defaultItemCfop no item no
  // momento em que ele é criado, mas não reagem a uma troca posterior de
  // Natureza da Operação (ex.: usuário adiciona itens em "Venda" e só depois
  // muda para "Devolução ao fornecedor") — sem isso os itens ficariam com um
  // CFOP de venda numa nota de devolução. Só reajusta itens cujo CFOP ainda é
  // o default anterior (auto-preenchido); um CFOP editado manualmente, vindo
  // do cadastro do produto ou importado de XML de referência é preservado.
  const prevDefaultCfopRef = useRef(defaultItemCfop);
  useEffect(() => {
    const prev = prevDefaultCfopRef.current;
    if (prev !== defaultItemCfop) {
      setItems((current) => current.map((it) => (it.cfop === prev ? { ...it, cfop: defaultItemCfop } : it)));
    }
    prevDefaultCfopRef.current = defaultItemCfop;
  }, [defaultItemCfop]);

  const productOptions: EntityOption[] = useMemo(() => (products || [])
    .filter((p) => p.active)
    .map((p) => ({
      value: p.id,
      label: p.name,
      description: p.sku || undefined,
      searchTerms: [p.ncm || '', (p as any).cfop || ''],
    })), [products]);

  // Checklist de pré-voo: o que ainda falta para a nota poder ser autorizada.
  // Mostrado no diálogo para orientar o usuário antes de gastar cota fiscal.
  const docDigits = recipientDocument.replace(/\D/g, '');
  const itemsOk = items.length > 0 && items.every((it) => it.ncm.replace(/\D/g, '') && it.csosn && it.quantity > 0 && it.unit_price > 0);
  const preflight = [
    { ok: !!company?.state_code, label: 'UF da empresa emissora definida (calcula o CFOP)' },
    { ok: !!recipientName.trim() && (docDigits.length === 11 || docDigits.length === 14), label: 'Destinatário com nome e CPF/CNPJ válido' },
    { ok: !!(address.address_line_1 && address.city && address.state && address.postal_code), label: 'Endereço do destinatário completo' },
    { ok: recipientIeIndicator !== 1 || !!recipientIe.trim(), label: 'IE informada (destinatário contribuinte)' },
    { ok: itemsOk, label: 'Itens com NCM, CSOSN, quantidade e valor' },
    { ok: !selectedNature.requiresReference || !!referencedAccessKey.replace(/\D/g, ''), label: 'Chave da NF-e original (devolução)' },
  ];
  const preflightOk = preflight.every((p) => p.ok);

  const [cancelTarget, setCancelTarget] = useState<{ id: string } | null>(null);
  const [cancelReason, setCancelReason] = useState('');
  // Por documento (não um único valor global) — senão a conclusão da ação de
  // um documento pode reabilitar/destravar o botão de outro ainda em voo.
  const [busyDocIds, setBusyDocIds] = useState<Set<string>>(new Set());
  const markBusy = (id: string, busy: boolean) => {
    setBusyDocIds((prev) => {
      const next = new Set(prev);
      if (busy) next.add(id); else next.delete(id);
      return next;
    });
  };

  // ── Config da empresa emitente ──────────────────────────────────────────
  const openSettings = () => {
    if (company) {
      setSettingsForm({
        legal_name: company.legal_name || '',
        trade_name: company.trade_name || '',
        cnpj: company.cnpj || '',
        state_registration: company.state_registration || '',
        municipal_registration: company.municipal_registration || '',
        tax_regime: company.tax_regime || 'simples',
        crt: company.crt ?? 1,
        state_code: company.state_code || '',
        street: company.street || '',
        number: company.number || '',
        district: company.district || '',
        city_name: company.city_name || '',
        postal_code: company.postal_code || '',
      });
    }
    setShowSettings(true);
  };

  const handleSaveSettings = async () => {
    // UF é obrigatória: define se o CFOP calculado é interno (5xxx/1xxx) ou
    // interestadual (6xxx/2xxx). Sem ela a emissão trava no backend.
    if (!settingsForm.state_code) {
      toast.error('Selecione a UF da empresa — ela é obrigatória para calcular o CFOP das notas.');
      return;
    }
    setSavingSettings(true);
    try {
      const payload = { ...settingsForm, updated_at: new Date().toISOString() };
      const { error } = company
        ? await (supabase.from as any)('company_fiscal_settings').update(payload).eq('id', company.id)
        : await (supabase.from as any)('company_fiscal_settings').insert(payload);
      // Corrida rara: duas pessoas configurando ao mesmo tempo na primeira vez
      // — a constraint de linha única (singleton_guard) rejeita o segundo
      // insert com 23505. Trata como "alguém já salvou primeiro": recarrega e
      // avisa em vez de mostrar um erro de banco cru.
      if (error && (error as any).code === '23505' && !company) {
        qc.invalidateQueries({ queryKey: ['company_fiscal_settings'] });
        toast.warning('A empresa já foi configurada por outra pessoa nesse meio-tempo. Reabra para editar.');
        setShowSettings(false);
        return;
      }
      if (error) throw error;
      toast.success('Dados fiscais da empresa salvos.');
      setShowSettings(false);
      qc.invalidateQueries({ queryKey: ['company_fiscal_settings'] });
    } catch (err: any) {
      toast.error('Erro ao salvar: ' + err.message);
    } finally {
      setSavingSettings(false);
    }
  };

  // ── Dialog de emissão ────────────────────────────────────────────────────
  const openEmitDialog = () => {
    setNatureOfOperation('venda');
    setClientId('');
    setRecipientName('');
    setRecipientDocument('');
    setRecipientEmail('');
    setRecipientIeIndicator(9);
    setRecipientIe('');
    setAddress(EMPTY_ADDRESS);
    setPaymentMethod('01');
    setPresenceIndicator(1);
    setConsumerFinal(true);
    setAdditionalInfo(SIMPLES_INFO_NOTE);
    setReferencedAccessKey('');
    setItems([]);
    // Gerada uma vez por abertura do diálogo: um duplo clique ou retry de
    // rede no mesmo envio reusa esta chave, e o backend deduplica por ela —
    // sem isso o fluxo manual (o único hoje na UI) não tinha proteção alguma
    // contra emitir duas NF-e reais para a mesma venda.
    setEmitIdempotencyKey(crypto.randomUUID());
    setShowEmit(true);
  };

  const handleClientChange = (id: string) => {
    setClientId(id);
    const c = (clients || []).find((cl) => cl.id === id);
    if (!c) return;
    setRecipientName(c.name || '');
    setRecipientDocument(c.cpf_cnpj || '');
    setRecipientEmail(c.email || '');
    // IE/indicador e consumidor final vindos do cadastro do cliente (colunas
    // novas). Fallback conservador = 9 (não contribuinte), para não travar a
    // emissão exigindo IE de quem não tem; o usuário marca "Contribuinte" quando
    // for o caso (ex.: revenda). Consumidor final: CNPJ (revenda) → não.
    const digits = (c.cpf_cnpj || '').replace(/\D/g, '');
    const indicator = (c as any).ie_indicator ?? 9;
    setRecipientIeIndicator(Number(indicator) || 9);
    setRecipientIe((c as any).state_registration || '');
    setConsumerFinal(digits.length === 11);
    setAddress({
      postal_code: c.postal_code || '',
      address_line_1: c.address_line_1 || '',
      address_number: '',
      address_complement: c.address_line_2 || '',
      neighborhood: '',
      city: c.city || '',
      state: c.state || '',
      country: c.country || 'Brasil',
    });
  };

  const addItem = () => {
    setItems((prev) => [
      ...prev,
      {
        productId: null, code: '', name: '', ncm: '', cfop: defaultItemCfop, unit: 'UN',
        quantity: 1, unit_price: 0, ...EMPTY_RESOLVED,
        // item avulso novo: herda os defaults globais de imposto
        ...(() => { const r = resolveItemFiscal(null); return { csosn: r.csosn, origin: r.origin, icms_rate: r.icmsRate, pis_rate: r.pisRate, cofins_rate: r.cofinsRate, ipi_rate: r.ipiRate }; })(),
      },
    ]);
  };

  const updateItem = (index: number, patch: Partial<DraftItem>) => {
    setItems((prev) => prev.map((it, i) => (i === index ? { ...it, ...patch } : it)));
  };

  const removeItem = (index: number) => {
    setItems((prev) => prev.filter((_, i) => i !== index));
  };

  const handleItemProductChange = (index: number, productId: string) => {
    const p = (products || []).find((pr) => pr.id === productId);
    if (!p) {
      updateItem(index, { productId: null });
      return;
    }
    const rf = resolveItemFiscal(p.id);
    updateItem(index, {
      productId: p.id,
      code: p.sku || p.id.slice(0, 8),
      name: p.name,
      ncm: rf.ncm || p.ncm || '',
      cfop: (p as any).cfop || defaultItemCfop,
      unit: p.unit || 'UN',
      unit_price: Number(p.sale_price || 0),
      csosn: rf.csosn,
      origin: rf.origin,
      icms_rate: rf.icmsRate,
      pis_rate: rf.pisRate,
      cofins_rate: rf.cofinsRate,
      ipi_rate: rf.ipiRate,
    });
  };

  // Callback do "+ Cadastrar novo" do EntityCombobox — não cria um produto no
  // catálogo (isso seria um escopo bem maior), só inicia um item avulso já
  // com o nome digitado, deixando NCM/CFOP/valor pra preencher nos campos
  // abaixo. Resolve a queixa de "não dá pra cadastrar avulso direto no campo".
  const handleItemAvulso = (index: number, typedName: string) => {
    updateItem(index, { productId: null, name: typedName || items[index]?.name || '' });
  };

  const handleXmlFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = ''; // permite selecionar o mesmo arquivo de novo depois
    if (!file) return;
    try {
      const text = await file.text();
      const parsed = parseNfeReferenceXml(text);
      if (!parsed) {
        toast.error('Arquivo não parece ser um XML de NF-e válido.');
        return;
      }
      setClientId(''); // XML importado não necessariamente bate com um cliente cadastrado
      setRecipientName(parsed.recipient.name);
      setRecipientDocument(parsed.recipient.document);
      setRecipientEmail(parsed.recipient.email);
      setAddress({
        postal_code: parsed.recipient.address.postalCode,
        address_line_1: parsed.recipient.address.street,
        address_number: parsed.recipient.address.number,
        address_complement: parsed.recipient.address.complement,
        neighborhood: parsed.recipient.address.district,
        city: parsed.recipient.address.cityName,
        state: parsed.recipient.address.stateCode,
        country: 'Brasil',
      });
      if (parsed.items.length) {
        const r = resolveItemFiscal(null); // XML de referência não vincula produto → defaults globais
        setItems(parsed.items.map((it) => ({
          productId: null,
          code: it.code,
          name: it.name,
          ncm: it.ncm,
          cfop: it.cfop || defaultItemCfop,
          unit: it.unit || 'UN',
          quantity: it.quantity,
          unit_price: it.unitPrice,
          csosn: r.csosn,
          origin: r.origin,
          icms_rate: r.icmsRate,
          pis_rate: r.pisRate,
          cofins_rate: r.cofinsRate,
          ipi_rate: r.ipiRate,
        })));
      }
      toast.success(`Dados importados de "${file.name}". Confira quantidade, valores e a natureza da operação antes de emitir.`);
    } catch (err: any) {
      toast.error('Erro ao ler o XML: ' + err.message);
    }
  };

  const total = items.reduce((sum, it) => sum + it.quantity * it.unit_price, 0);

  const handleEmit = async () => {
    setEmitting(true);
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', {
        body: {
          action: 'create',
          origin_type: 'manual',
          idempotency_key: emitIdempotencyKey,
          client_id: clientId || null,
          nature_of_operation: natureOfOperation,
          payment_method: paymentMethod,
          presence_indicator: presenceIndicator,
          consumer_final: consumerFinal,
          additional_info: additionalInfo || undefined,
          referenced_access_key: selectedNature.requiresReference ? (referencedAccessKey || undefined) : undefined,
          recipient: {
            name: recipientName,
            document: recipientDocument,
            email: recipientEmail || undefined,
            state_registration_indicator: recipientIeIndicator,
            state_registration: recipientIeIndicator === 1 ? (recipientIe || undefined) : undefined,
            address: {
              street: address.address_line_1,
              number: address.address_number,
              complement: address.address_complement || undefined,
              district: address.neighborhood,
              city_name: address.city,
              state_code: address.state,
              postal_code: address.postal_code,
            },
          },
          items: items.map((it) => ({
            product_id: it.productId || undefined,
            code: it.code,
            name: it.name,
            ncm: it.ncm,
            cfop: it.cfop,
            unit: it.unit,
            quantity: it.quantity,
            unit_price: it.unit_price,
            csosn: it.csosn || undefined,
            origin: it.origin,
            icms_rate: it.icms_rate,
            pis_rate: it.pis_rate,
            cofins_rate: it.cofins_rate,
            ipi_rate: it.ipi_rate,
          })),
        },
      });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) throw new Error(data.error);

      const env = data?.data?.environment === 'producao' ? 'produção' : 'homologação';
      toast.success(`NF-e enviada para processamento (ambiente: ${env}). Acompanhe o status abaixo.`);
      setShowEmit(false);
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
    } catch (err: any) {
      toast.error('Erro ao emitir NF-e: ' + err.message);
      // Ataque concluído (com erro): a próxima tentativa deliberada do
      // usuário é um envio novo, não um retry do mesmo — gera outra chave.
      setEmitIdempotencyKey(crypto.randomUUID());
    } finally {
      setEmitting(false);
    }
  };

  // ── Ações do histórico ──────────────────────────────────────────────────
  const handleRefreshStatus = async (docId: string) => {
    markBusy(docId, true);
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-reconcile', {
        body: { document_id: docId },
      });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) throw new Error(data.error);
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
    } catch (err: any) {
      toast.error('Erro ao atualizar status: ' + err.message);
    } finally {
      markBusy(docId, false);
    }
  };

  const handleConfirmCancel = async () => {
    if (!cancelTarget || cancelReason.trim().length < MIN_JUSTIFICATION_LENGTH) return;
    markBusy(cancelTarget.id, true);
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', {
        body: { action: 'cancel', document_id: cancelTarget.id, reason: cancelReason.trim() },
      });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) throw new Error(data.error);
      toast.success('Cancelamento solicitado. Acompanhe o status.');
      markBusy(cancelTarget.id, false);
      setCancelTarget(null);
      setCancelReason('');
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
    } catch (err: any) {
      toast.error('Erro ao cancelar: ' + err.message);
      markBusy(cancelTarget.id, false);
    }
  };

  const handleDownloadXml = async (path: string) => {
    const { data, error } = await supabase.storage.from('fiscal-xml').createSignedUrl(path, 60);
    if (error || !data?.signedUrl) {
      toast.error('Erro ao gerar link de download: ' + (error?.message || ''));
      return;
    }
    window.open(data.signedUrl, '_blank');
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Emissão Fiscal (NF-e)"
        description="Emita notas fiscais eletrônicas de produto via Contora e acompanhe o status de autorização."
      >
        <Button variant="outline" onClick={openSettings}>
          <Settings2 className="h-4 w-4 mr-2" />
          {company ? 'Dados da Empresa' : 'Configurar Empresa'}
        </Button>
        <Button onClick={openEmitDialog} disabled={!company}>
          <FileText className="h-4 w-4 mr-2" />
          Emitir NF-e
        </Button>
      </PageHeader>

      {!loadingCompany && !company && (
        <Card className="border-dashed border-2 border-amber-300 bg-amber-50">
          <CardContent className="py-6">
            <p className="text-sm text-amber-800">
              Antes de emitir a primeira NF-e, preencha os dados fiscais da empresa emissora (CNPJ, IE, IM, regime tributário).
            </p>
            <Button size="sm" variant="outline" className="mt-3" onClick={openSettings}>
              <Pencil className="h-3.5 w-3.5 mr-1" />Configurar agora
            </Button>
          </CardContent>
        </Card>
      )}

      {/* ── Histórico ── */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold">Histórico de NF-es Emitidas</h2>
          <Button variant="ghost" size="sm" onClick={() => qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] })}>
            <RefreshCw className="h-4 w-4 mr-1" />Atualizar
          </Button>
        </div>

        <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Série/Nº</TableHead>
                <TableHead>Ambiente</TableHead>
                <TableHead>Emissão</TableHead>
                <TableHead className="text-right">Total</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loadingDocs ? (
                Array.from({ length: 3 }).map((_, i) => (
                  <TableRow key={i}><TableCell colSpan={6}><Skeleton className="h-8 w-full" /></TableCell></TableRow>
                ))
              ) : !documents?.length ? (
                <TableRow>
                  <TableCell colSpan={6} className="text-center py-10 text-muted-foreground">
                    Nenhuma NF-e emitida ainda. Use o botão "Emitir NF-e" para começar.
                  </TableCell>
                </TableRow>
              ) : documents.map((doc: any) => {
                const s = STATUS_MAP[doc.status] ?? STATUS_MAP.draft;
                const isBusy = busyDocIds.has(doc.id);
                // Lê o total já calculado/arredondado pelo backend em vez de
                // recalcular no cliente (as duas contas podem divergir por
                // arredondamento, e recalcular em toda renderização é trabalho à toa).
                const docTotal = Number(doc.request_payload?.payments?.[0]?.amount ?? 0);
                return (
                  <TableRow key={doc.id} className="hover:bg-muted/30">
                    <TableCell className="font-mono">{doc.series}/{doc.number}</TableCell>
                    <TableCell className="text-xs text-muted-foreground">
                      {doc.environment === 'producao' ? 'Produção' : 'Homologação'}
                    </TableCell>
                    <TableCell className="text-muted-foreground text-sm">{formatDate(doc.created_at)}</TableCell>
                    <TableCell className="text-right font-semibold">{formatCurrency(docTotal)}</TableCell>
                    <TableCell>
                      <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold ${s.className}`}>
                        {s.label}
                      </span>
                      {doc.status_message && (
                        <p className="text-[11px] text-muted-foreground mt-0.5 max-w-[220px] truncate" title={doc.status_message}>
                          {doc.status_message}
                        </p>
                      )}
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        {['draft', 'queued', 'processing'].includes(doc.status) && (
                          <Button size="sm" variant="outline" disabled={isBusy} onClick={() => handleRefreshStatus(doc.id)}>
                            {isBusy ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <RefreshCw className="h-3.5 w-3.5" />}
                          </Button>
                        )}
                        {doc.xml_storage_path && (
                          <Button size="sm" variant="outline" onClick={() => handleDownloadXml(doc.xml_storage_path)}>
                            <Download className="h-3.5 w-3.5" />
                          </Button>
                        )}
                        {doc.pdf_url && (
                          <Button size="sm" variant="outline" onClick={() => window.open(doc.pdf_url, '_blank')}>
                            DANFE
                          </Button>
                        )}
                        {doc.status === 'authorized' && (
                          <Button
                            size="sm" variant="ghost" className="text-destructive hover:text-destructive"
                            disabled={isBusy}
                            onClick={() => setCancelTarget({ id: doc.id })}
                          >
                            <Ban className="h-3.5 w-3.5" />
                          </Button>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </div>
      </div>

      {/* ── Dialog: configurar empresa emissora ── */}
      <Dialog open={showSettings} onOpenChange={setShowSettings}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Dados Fiscais da Empresa</DialogTitle>
            <DialogDescription>Registro local para controle interno.</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <Label>Razão Social</Label>
              <Input value={settingsForm.legal_name} onChange={(e) => setSettingsForm((p) => ({ ...p, legal_name: e.target.value }))} />
            </div>
            <div>
              <Label>Nome Fantasia</Label>
              <Input value={settingsForm.trade_name} onChange={(e) => setSettingsForm((p) => ({ ...p, trade_name: e.target.value }))} />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>CNPJ</Label>
                <Input
                  value={maskCPFCNPJ(settingsForm.cnpj)}
                  onChange={(e) => setSettingsForm((p) => ({ ...p, cnpj: e.target.value.replace(/\D/g, '').slice(0, 14) }))}
                />
              </div>
              <div>
                <Label>Regime Tributário</Label>
                <Select value={settingsForm.tax_regime} onValueChange={(v) => setSettingsForm((p) => ({ ...p, tax_regime: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="mei">MEI</SelectItem>
                    <SelectItem value="simples">Simples Nacional</SelectItem>
                    <SelectItem value="presumido">Lucro Presumido</SelectItem>
                    <SelectItem value="real">Lucro Real</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="grid grid-cols-3 gap-3">
              <div>
                <Label>Inscrição Estadual</Label>
                <Input value={settingsForm.state_registration} onChange={(e) => setSettingsForm((p) => ({ ...p, state_registration: e.target.value }))} />
              </div>
              <div>
                <Label>Inscrição Municipal</Label>
                <Input value={settingsForm.municipal_registration} onChange={(e) => setSettingsForm((p) => ({ ...p, municipal_registration: e.target.value }))} />
              </div>
              <div>
                <Label>UF <span className="text-destructive">*</span></Label>
                <Select value={settingsForm.state_code} onValueChange={(v) => setSettingsForm((p) => ({ ...p, state_code: v }))}>
                  <SelectTrigger className={!settingsForm.state_code ? 'border-destructive' : ''}><SelectValue placeholder="UF" /></SelectTrigger>
                  <SelectContent>
                    {BRAZILIAN_STATES.map((uf) => (
                      <SelectItem key={uf} value={uf}>{uf}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            {/* Endereço do emitente — registro interno (a nota usa o cadastro da Contora). */}
            <div className="grid grid-cols-6 gap-2">
              <div className="col-span-4">
                <Label className="text-xs">Logradouro</Label>
                <Input className="h-8 text-xs" value={settingsForm.street} onChange={(e) => setSettingsForm((p) => ({ ...p, street: e.target.value }))} />
              </div>
              <div className="col-span-2">
                <Label className="text-xs">Número</Label>
                <Input className="h-8 text-xs" value={settingsForm.number} onChange={(e) => setSettingsForm((p) => ({ ...p, number: e.target.value }))} />
              </div>
              <div className="col-span-2">
                <Label className="text-xs">Bairro</Label>
                <Input className="h-8 text-xs" value={settingsForm.district} onChange={(e) => setSettingsForm((p) => ({ ...p, district: e.target.value }))} />
              </div>
              <div className="col-span-2">
                <Label className="text-xs">Cidade</Label>
                <Input className="h-8 text-xs" value={settingsForm.city_name} onChange={(e) => setSettingsForm((p) => ({ ...p, city_name: e.target.value }))} />
              </div>
              <div className="col-span-2">
                <Label className="text-xs">CEP</Label>
                <Input className="h-8 text-xs" value={settingsForm.postal_code} onChange={(e) => setSettingsForm((p) => ({ ...p, postal_code: e.target.value.replace(/\D/g, '').slice(0, 8) }))} />
              </div>
            </div>

            <p className="text-xs text-muted-foreground">
              A <strong>UF é obrigatória</strong>: define se o CFOP calculado em cada emissão é de operação interna (mesmo
              estado) ou interestadual. Os demais dados são registro local, para exibição — não são enviados à Contora e não
              determinam qual empresa efetivamente emite. Quem manda isso é o cadastro feito direto no console da Contora
              (CNPJ + certificado A1), vinculado ao token configurado nos Secrets do Supabase.
            </p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowSettings(false)}>Cancelar</Button>
            <Button onClick={handleSaveSettings} disabled={savingSettings}>
              {savingSettings ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Salvar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ── Dialog: emitir NF-e ── */}
      <Dialog open={showEmit} onOpenChange={setShowEmit}>
        <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Emitir NF-e</DialogTitle>
            <DialogDescription>
              O ambiente de emissão (homologação ou produção) é definido nos Secrets do servidor e confirmado na mensagem
              de sucesso. A autorização chega em segundos a minutos — acompanhe pelo histórico.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-5">
            <div className="flex items-end justify-between gap-4">
              <div className="flex-1">
                <Label>Natureza da Operação</Label>
                <Select value={natureOfOperation} onValueChange={setNatureOfOperation}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {NATURE_OF_OPERATION_OPTIONS.map((n) => (
                      <SelectItem key={n.value} value={n.value}>{n.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {selectedNature.operationType === 'entrada' && (
                  <p className="text-xs text-amber-700 mt-1">
                    Nota de ENTRADA — registra recebimento (ex.: devolução do cliente), não uma venda.
                  </p>
                )}
                <p className="text-xs text-muted-foreground mt-1">
                  CFOP dos novos itens: <span className="font-mono">{defaultItemCfop}</span>
                  {!company?.state_code && ' (defina a UF da empresa em "Dados da Empresa" para o cálculo correto)'}
                </p>
              </div>
              <input ref={xmlInputRef} type="file" accept=".xml" className="hidden" onChange={handleXmlFileChange} />
              <Button type="button" size="sm" variant="outline" onClick={() => xmlInputRef.current?.click()}>
                <Upload className="h-3.5 w-3.5 mr-1" />Importar de XML
              </Button>
            </div>

            {selectedNature.requiresReference && (
              <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 space-y-1">
                <Label className="text-amber-900">Chave da NF-e original (devolução) — 44 dígitos</Label>
                <Input
                  className="font-mono"
                  placeholder="0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000"
                  value={referencedAccessKey}
                  onChange={(e) => setReferencedAccessKey(e.target.value.replace(/\D/g, '').slice(0, 44))}
                />
                <p className="text-xs text-amber-800">
                  Uma nota de devolução (finalidade 4) deve referenciar a chave de acesso da NF-e original. O envio desse
                  campo à Contora ainda está em validação — teste a devolução em homologação antes de usar em produção.
                </p>
              </div>
            )}

            <div>
              <Label>Cliente cadastrado (opcional — preenche os dados abaixo)</Label>
              <Select value={clientId || '__none'} onValueChange={(v) => handleClientChange(v === '__none' ? '' : v)}>
                <SelectTrigger><SelectValue placeholder="Selecione um cliente..." /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none">Sem cliente vinculado</SelectItem>
                  {(clients || []).filter((c) => c.active).map((c) => (
                    <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-sm">Destinatário</CardTitle></CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label>Nome / Razão Social</Label>
                    <Input value={recipientName} onChange={(e) => setRecipientName(e.target.value)} />
                  </div>
                  <div>
                    <Label>CPF/CNPJ</Label>
                    <Input
                      value={maskCPFCNPJ(recipientDocument)}
                      onChange={(e) => setRecipientDocument(e.target.value.replace(/\D/g, ''))}
                    />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label>E-mail (opcional)</Label>
                    <Input type="email" value={recipientEmail} onChange={(e) => setRecipientEmail(e.target.value)} />
                  </div>
                  <div>
                    <Label>Indicador de IE</Label>
                    <Select value={String(recipientIeIndicator)} onValueChange={(v) => setRecipientIeIndicator(Number(v))}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {IE_INDICATORS.map((i) => (
                          <SelectItem key={i.value} value={String(i.value)}>{i.label}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </div>
                {recipientIeIndicator === 1 && (
                  <div>
                    <Label>Inscrição Estadual do destinatário <span className="text-destructive">*</span></Label>
                    <Input value={recipientIe} onChange={(e) => setRecipientIe(e.target.value)} placeholder="Obrigatória para contribuinte do ICMS" />
                  </div>
                )}
                <div className="grid grid-cols-2 gap-3 items-end">
                  <div>
                    <Label>Indicador de presença</Label>
                    <Select value={String(presenceIndicator)} onValueChange={(v) => setPresenceIndicator(Number(v))}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {PRESENCE_INDICATORS.map((i) => (
                          <SelectItem key={i.value} value={String(i.value)}>{i.label}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <label className="flex items-center gap-2 text-sm h-9 cursor-pointer">
                    <input type="checkbox" className="h-4 w-4" checked={consumerFinal} onChange={(e) => setConsumerFinal(e.target.checked)} />
                    Consumidor final
                  </label>
                </div>
                <AddressFields
                  value={address as any}
                  onChange={(field, value) => setAddress((p) => ({ ...p, [field]: value as string }))}
                  showCoordinates={false}
                />
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="pb-2 flex flex-row items-center justify-between">
                <CardTitle className="text-sm">Itens ({items.length})</CardTitle>
                <Button size="sm" variant="outline" onClick={addItem}>
                  <Plus className="h-3.5 w-3.5 mr-1" />Adicionar item
                </Button>
              </CardHeader>
              <CardContent className="space-y-3">
                {items.length === 0 && (
                  <p className="text-sm text-muted-foreground">Nenhum item adicionado ainda.</p>
                )}
                {items.map((it, index) => (
                  <div key={index} className="rounded-lg border p-3 space-y-2">
                    <div className="flex items-center justify-between gap-2">
                      <EntityCombobox
                        value={it.productId}
                        onChange={(v) => handleItemProductChange(index, v)}
                        options={productOptions}
                        placeholder="Produto do estoque (opcional)"
                        searchPlaceholder="Buscar produto... (digite 3+ letras)"
                        emptyText="Nenhum produto encontrado"
                        fallbackLabel={!it.productId && it.name ? `Avulso: ${it.name}` : undefined}
                        onCreate={(typed) => handleItemAvulso(index, typed)}
                        createLabel="Item avulso (preencher manualmente)"
                        triggerClassName="h-8 text-xs"
                      />
                      <Button size="icon" variant="ghost" className="h-8 w-8 text-destructive shrink-0" onClick={() => removeItem(index)}>
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                    <div className="grid grid-cols-2 gap-2">
                      <Input placeholder="Descrição" className="h-8 text-xs" value={it.name} onChange={(e) => updateItem(index, { name: e.target.value })} />
                      <Input placeholder="Código" className="h-8 text-xs" value={it.code} onChange={(e) => updateItem(index, { code: e.target.value })} />
                    </div>
                    <div className="grid grid-cols-4 gap-2">
                      <div>
                        <Label className="text-[10px] text-muted-foreground">NCM</Label>
                        <Input placeholder="NCM" className="h-8 text-xs" maxLength={8} value={it.ncm} onChange={(e) => updateItem(index, { ncm: e.target.value.replace(/\D/g, '') })} />
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">CFOP</Label>
                        <Input placeholder="CFOP" className="h-8 text-xs" value={it.cfop} onChange={(e) => updateItem(index, { cfop: e.target.value })} />
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">Unid.</Label>
                        <Input placeholder="Unid." className="h-8 text-xs" value={it.unit} onChange={(e) => updateItem(index, { unit: e.target.value })} />
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">Qtd</Label>
                        <Input type="number" min="0" placeholder="Qtd" className="h-8 text-xs" value={it.quantity} onChange={(e) => updateItem(index, { quantity: Math.max(0, parseFloat(e.target.value) || 0) })} />
                      </div>
                    </div>
                    {/* Impostos — auto-preenchidos do cadastro fiscal do produto, editáveis. */}
                    <div className="grid grid-cols-5 gap-2">
                      <div>
                        <Label className="text-[10px] text-muted-foreground">CSOSN</Label>
                        <Input placeholder="CSOSN" className="h-8 text-xs" value={it.csosn} onChange={(e) => updateItem(index, { csosn: e.target.value.replace(/\D/g, '').slice(0, 3) })} />
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">Origem</Label>
                        <Input type="number" min="0" max="8" className="h-8 text-xs" value={it.origin} onChange={(e) => updateItem(index, { origin: Math.max(0, Math.min(8, parseInt(e.target.value) || 0)) })} />
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">ICMS %</Label>
                        <Input type="number" min="0" step="0.01" className="h-8 text-xs" value={it.icms_rate} onChange={(e) => updateItem(index, { icms_rate: Math.max(0, parseFloat(e.target.value) || 0) })} />
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">PIS %</Label>
                        <Input type="number" min="0" step="0.01" className="h-8 text-xs" value={it.pis_rate} onChange={(e) => updateItem(index, { pis_rate: Math.max(0, parseFloat(e.target.value) || 0) })} />
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">COFINS %</Label>
                        <Input type="number" min="0" step="0.01" className="h-8 text-xs" value={it.cofins_rate} onChange={(e) => updateItem(index, { cofins_rate: Math.max(0, parseFloat(e.target.value) || 0) })} />
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Label className="text-xs whitespace-nowrap">Valor unitário</Label>
                      <Input type="number" min="0" step="0.01" className="h-8 text-xs" value={it.unit_price} onChange={(e) => updateItem(index, { unit_price: Math.max(0, parseFloat(e.target.value) || 0) })} />
                      <span className="text-xs text-muted-foreground whitespace-nowrap ml-auto">
                        Total: {formatCurrency(it.quantity * it.unit_price)}
                      </span>
                    </div>
                  </div>
                ))}
                <p className="text-[11px] text-muted-foreground">
                  CSOSN, origem e alíquotas vêm do cadastro fiscal do produto (ou do padrão global das Configurações) e
                  podem ser ajustados por item. O CST de PIS/COFINS usa o padrão global.
                </p>
              </CardContent>
            </Card>

            <div className="flex items-center justify-between gap-4">
              <div className="flex-1">
                <Label>Forma de Pagamento</Label>
                <Select value={paymentMethod} onValueChange={setPaymentMethod}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {PAYMENT_METHODS.map((m) => (
                      <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="text-right">
                <p className="text-xs text-muted-foreground uppercase">Total da Nota</p>
                <p className="text-2xl font-bold">{formatCurrency(total)}</p>
              </div>
            </div>

            <div>
              <Label>Informações complementares (opcional)</Label>
              <Textarea
                className="text-sm"
                rows={2}
                value={additionalInfo}
                onChange={(e) => setAdditionalInfo(e.target.value)}
                placeholder="Observações que saem no rodapé da nota"
              />
              <p className="text-[11px] text-muted-foreground mt-1">
                A nota-padrão do Simples Nacional já vem preenchida. Ajuste conforme orientação da contadora.
              </p>
            </div>

            {/* Checklist de pré-voo */}
            <div className="rounded-lg border bg-muted/30 p-3">
              <p className="text-xs font-semibold mb-2">Pronto para emitir?</p>
              <ul className="space-y-1">
                {preflight.map((p, i) => (
                  <li key={i} className={`flex items-center gap-2 text-xs ${p.ok ? 'text-success' : 'text-muted-foreground'}`}>
                    <span className={`inline-block h-2 w-2 rounded-full ${p.ok ? 'bg-success' : 'bg-amber-400'}`} />
                    {p.label}
                  </li>
                ))}
              </ul>
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setShowEmit(false)}>Cancelar</Button>
            <Button onClick={handleEmit} disabled={emitting || items.length === 0 || !preflightOk}>
              {emitting ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <FileText className="h-4 w-4 mr-2" />}
              Emitir NF-e
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ── Dialog: cancelar ── */}
      <Dialog open={!!cancelTarget} onOpenChange={(o) => { if (!o) { setCancelTarget(null); setCancelReason(''); } }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Cancelar NF-e</DialogTitle>
            <DialogDescription>Informe o motivo do cancelamento (a SEFAZ exige pelo menos {MIN_JUSTIFICATION_LENGTH} caracteres).</DialogDescription>
          </DialogHeader>
          <Textarea value={cancelReason} onChange={(e) => setCancelReason(e.target.value)} placeholder="Ex.: Erro de digitação no endereço do destinatário" />
          <p className={`text-xs ${cancelReason.trim().length < MIN_JUSTIFICATION_LENGTH ? 'text-muted-foreground' : 'text-success'}`}>
            {cancelReason.trim().length}/{MIN_JUSTIFICATION_LENGTH} caracteres mínimos
          </p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCancelTarget(null)}>Voltar</Button>
            <Button
              variant="destructive"
              disabled={cancelReason.trim().length < MIN_JUSTIFICATION_LENGTH || (cancelTarget ? busyDocIds.has(cancelTarget.id) : false)}
              onClick={handleConfirmCancel}
            >
              {cancelTarget && busyDocIds.has(cancelTarget.id) ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Confirmar Cancelamento
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
