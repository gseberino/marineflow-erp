import { useEffect, useMemo, useRef, useState } from 'react';
import { useLocation } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { AddressFields } from '@/components/AddressFields';
import { ClientFormDialog } from '@/components/ClientFormDialog';
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
  Stethoscope, CheckCircle2, XCircle, Undo2, Send, FileDown, Copy, Boxes,
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
import { createZipBlob, type ZipEntry } from '@/lib/zip';
import { parseLegacyAddress } from '@/lib/address-legacy';
import { CSOSN_OPTIONS, FISCAL_ORIGIN_OPTIONS } from '@/lib/price-calculator';
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
  // Devolução: seleção total/parcial + referência por item (VC02-14).
  included?: boolean; // marcado por padrão; desmarcar exclui o item (parcial)
  maxQuantity?: number; // teto = qtd da nota original (só no modo devolução)
  referencedKey?: string | null; // chave da NF-e original
  referencedItemNumber?: number | null; // nItem na nota original
}

const EMPTY_RESOLVED = { csosn: '400', origin: 0, icms_rate: 0, pis_rate: 0, cofins_rate: 0, ipi_rate: 0 };

// Resultado do diagnóstico da conta na Contora (action="diagnostics" no fiscal-emit).
interface DiagnosticsResult {
  token_ok: boolean;
  sefaz_ok: boolean;
  // Candidatos ao verProc (versão do software, máx 20 na NF-e). O que tiver
  // comprimento > 20 é o suspeito do erro "verProc length 21".
  verproc_candidates?: {
    token_name?: string | null;
    token_name_len?: number;
    legal_name?: string | null;
    legal_name_len?: number;
    trade_name?: string | null;
    trade_name_len?: number;
  };
  company: {
    found: boolean;
    legal_name?: string | null;
    trade_name?: string | null;
    state_code?: string | null;
    city_code?: string | null;
    has_certificate?: boolean;
    default_environment?: string | null;
  } | null;
  message?: string;
}

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

// Ambiente REAL de emissão, lido do servidor (secret FISCAL_ENVIRONMENT) — não
// um palpite do front. Alimenta o banner de "PRODUÇÃO / nota real". Em erro,
// assume 'homologacao' (a confirmação de verdade continua sendo a mensagem
// pós-emissão + o botão Diagnóstico); nunca grita produção por engano.
function useFiscalEnvironment() {
  return useQuery({
    queryKey: ['fiscal_environment'],
    queryFn: async () => {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', {
        body: { action: 'environment' },
      });
      if (error) return 'homologacao';
      return ((data as any)?.data?.environment as string) || 'homologacao';
    },
    staleTime: 30_000,
  });
}

// Diagnóstico da conta (empresa/certificado/SEFAZ) para o Painel de Saúde Fiscal.
// Cacheado por 10 min (faz chamadas à Contora, mas de graça — não consome cota).
function useFiscalDiagnostics() {
  return useQuery({
    queryKey: ['fiscal_diagnostics_health'],
    queryFn: async () => {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', {
        body: { action: 'diagnostics' },
      });
      if (error) return null;
      return (data as any)?.data ?? null;
    },
    staleTime: 10 * 60_000,
    refetchOnWindowFocus: false,
  });
}

// ── Página ─────────────────────────────────────────────────────────────────
export default function FiscalEmission() {
  const { formatCurrency, formatDate } = useI18n();
  const qc = useQueryClient();
  const location = useLocation();

  const { data: company, isLoading: loadingCompany } = useCompanyFiscalSettings();
  const { data: documents, isLoading: loadingDocs } = useIssuedFiscalDocuments();
  const { data: fiscalEnv } = useFiscalEnvironment();
  const isProducao = fiscalEnv === 'producao';
  const { data: health } = useFiscalDiagnostics();
  const { data: clients } = useClients();

  // Métricas do mês corrente para o Painel de Saúde Fiscal (calculadas do
  // histórico já carregado — no volume do HBR as 100 notas recentes cobrem o mês).
  const monthStats = useMemo(() => {
    const now = new Date();
    const y = now.getFullYear();
    const m = now.getMonth();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const month = (documents || []).filter((d: any) => {
      const dt = new Date(d.created_at);
      return dt.getFullYear() === y && dt.getMonth() === m;
    });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const by = (s: string) => month.filter((d: any) => d.status === s);
    const authorized = by('authorized');
    const faturamento = authorized.reduce(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (sum: number, d: any) => sum + Number(d.request_payload?.payments?.[0]?.amount ?? 0),
      0,
    );
    const rejected = by('rejected').length;
    const cancelled = by('cancelled').length;
    // Proxy da cota Contora: eventos que chegaram à SEFAZ (autorizada+rejeitada+cancelada).
    const eventos = authorized.length + rejected + cancelled;
    return { authorized: authorized.length, rejected, cancelled, faturamento, eventos };
  }, [documents]);

  // Validade do certificado A1 → dias a vencer (alerta antecipado de "apagão fiscal").
  const certInfo = useMemo(() => {
    const vu = health?.company?.certificate_valid_until as string | undefined;
    if (!vu) return null;
    const days = Math.floor((new Date(`${vu}T23:59:59`).getTime() - Date.now()) / 86_400_000);
    return { validUntil: vu, days };
  }, [health]);
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
  const [runningDiag, setRunningDiag] = useState(false);
  const [diagResult, setDiagResult] = useState<DiagnosticsResult | null>(null);
  const [settingsForm, setSettingsForm] = useState({
    legal_name: '', trade_name: '', cnpj: '', state_registration: '',
    municipal_registration: '', tax_regime: 'simples', crt: 1, state_code: '',
    street: '', number: '', district: '', city_name: '', postal_code: '',
  });

  const [showClientForm, setShowClientForm] = useState(false);

  // Export de XMLs / relatório p/ contadora (período).
  const [showExport, setShowExport] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [exportFrom, setExportFrom] = useState(() => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
  });
  const [exportTo, setExportTo] = useState(() => new Date().toISOString().slice(0, 10));

  const [showEmit, setShowEmit] = useState(false);
  const [emitting, setEmitting] = useState(false);
  const [emitIdempotencyKey, setEmitIdempotencyKey] = useState('');
  // Origem da emissão: 'manual' (avulsa) ou uma OS/orçamento sendo faturado.
  const [emitOrigin, setEmitOrigin] = useState<{ type: string; id: string | null }>({ type: 'manual', id: null });
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

  const clientOptions: EntityOption[] = useMemo(() => (clients || [])
    .filter((c) => c.active)
    .map((c) => ({
      value: c.id,
      label: c.name,
      description: c.cpf_cnpj || undefined,
      searchTerms: [c.cpf_cnpj || '', c.city || ''],
    })), [clients]);

  // Checklist de pré-voo: o que ainda falta para a nota poder ser autorizada.
  // Mostrado no diálogo para orientar o usuário antes de gastar cota fiscal.
  const docDigits = recipientDocument.replace(/\D/g, '');
  // Só os itens marcados (no modo devolução, o usuário pode desmarcar — parcial).
  const includedItems = items.filter((it) => it.included !== false);
  const itemsOk = includedItems.length > 0 && includedItems.every((it) =>
    it.ncm.replace(/\D/g, '').length === 8 && it.csosn &&
    /^\d{4}$/.test((it.cfop || '').trim()) && it.quantity > 0 && it.unit_price > 0);
  const isReturn = selectedNature.purpose === 4;
  // Numa devolução por item (VC02-14) cada item incluído precisa referenciar a
  // nota original (chave + nItem). Quando a devolução vem do botão "Gerar
  // devolução", isso já vem preenchido; no fluxo manual, ao menos a chave.
  const returnRefsOk = !isReturn
    || includedItems.every((it) => (it.referencedKey || '').replace(/\D/g, '').length === 44 && !!it.referencedItemNumber)
    || !!referencedAccessKey.replace(/\D/g, '');
  const preflight = [
    { ok: !!company?.state_code, label: 'UF da empresa emissora definida (calcula o CFOP)' },
    { ok: !!recipientName.trim() && (docDigits.length === 11 || docDigits.length === 14), label: 'Destinatário com nome e CPF/CNPJ válido' },
    { ok: !!(address.address_line_1 && address.city && address.state) && address.postal_code.replace(/\D/g, '').length === 8, label: 'Endereço do destinatário completo (CEP com 8 dígitos)' },
    { ok: recipientIeIndicator !== 1 || !!recipientIe.trim(), label: 'IE informada (destinatário contribuinte)' },
    { ok: itemsOk, label: 'Itens com NCM (8 díg.), CFOP (4 díg.), CSOSN, qtd e valor' },
    ...(isReturn ? [{ ok: returnRefsOk, label: 'Referência à NF-e original por item (chave + nº do item)' }] : []),
  ];
  const preflightOk = preflight.every((p) => p.ok);

  const [cancelTarget, setCancelTarget] = useState<{ id: string; authorized_at?: string | null } | null>(null);
  const [cancelReason, setCancelReason] = useState('');
  const [correctionTarget, setCorrectionTarget] = useState<{ id: string; number?: number; series?: number } | null>(null);
  const [correctionText, setCorrectionText] = useState('');
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

  // Consulta o estado real da conta na Contora (empresa/city_code/certificado/
  // ambiente/SEFAZ). Read-only, não gasta cota — serve para o usuário entender
  // por que a emissão falha (ex.: "empresa sem city_code" é corrigido no console
  // da Contora, não aqui).
  const handleRunDiagnostics = async () => {
    setRunningDiag(true);
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', { body: { action: 'diagnostics' } });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) throw new Error(data.error);
      setDiagResult((data?.data ?? data) as DiagnosticsResult);
    } catch (err: any) {
      toast.error('Erro no diagnóstico: ' + err.message);
      setDiagResult(null);
    } finally {
      setRunningDiag(false);
    }
  };

  // ── Dialog de emissão ────────────────────────────────────────────────────
  const openEmitDialog = () => {
    setEmitOrigin({ type: 'manual', id: null });
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

  // Preenche o destinatário a partir de um registro de cliente. Extraído para
  // ser reusado tanto na seleção do combo quanto após editar o cadastro no popup.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const populateFromClient = (c: any) => {
    setRecipientName(c.name || '');
    setRecipientDocument(c.cpf_cnpj || '');
    setRecipientEmail(c.email || '');
    // IE/indicador e consumidor final vindos do cadastro. Fallback conservador
    // = 9 (não contribuinte) para não travar exigindo IE de quem não tem.
    const digits = (c.cpf_cnpj || '').replace(/\D/g, '');
    setRecipientIeIndicator(Number(c.ie_indicator ?? 9) || 9);
    setRecipientIe(c.state_registration || '');
    setConsumerFinal(digits.length === 11);
    // Preferir colunas estruturadas; se vazias, desempacotar o endereço legado.
    const legacy = parseLegacyAddress(c.address_line_1, c.address_line_2);
    setAddress({
      postal_code: c.postal_code || '',
      address_line_1: legacy.street || c.address_line_1 || '',
      address_number: c.address_number || legacy.number,
      address_complement: c.address_complement || legacy.complement,
      neighborhood: c.neighborhood || legacy.neighborhood,
      city: c.city || '',
      state: c.state || '',
      country: c.country || 'Brasil',
    });
  };

  const handleClientChange = (id: string) => {
    setClientId(id);
    const c = (clients || []).find((cl) => cl.id === id);
    if (c) populateFromClient(c);
  };

  // Depois de editar o cadastro no popup: busca a versão fresca (a lista em
  // cache pode ainda estar desatualizada no instante do onSaved) e repreenche
  // o destinatário com os dados novos — sem o usuário redigitar nada.
  const handleClientSaved = async (savedClientId: string) => {
    setShowClientForm(false);
    qc.invalidateQueries({ queryKey: ['clients'] });
    setClientId(savedClientId);
    const { data } = await (supabase.from as any)('clients').select('*').eq('id', savedClientId).maybeSingle();
    if (data) populateFromClient(data);
  };

  // "Corrigir e reemitir" (notas com falha/rejeitada/cancelada) e "Duplicar"
  // (notas autorizadas): reabre o diálogo já preenchido a partir do payload de
  // uma NF-e registrada. Gera sempre uma NOVA emissão — origem manual (sem
  // conflito com o índice único por origem), nova chave de idempotência e novo
  // número; o documento original permanece intacto no histórico.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleReemitFromDoc = (doc: any) => {
    const p = doc.request_payload || {};
    const r = p.recipient || {};
    const a = r.address || {};
    const nat = NATURE_OF_OPERATION_OPTIONS.find(
      (o) => o.natureOperation === p.nature_operation && o.operationType === (p.operation_type || 'saida'),
    ) || NATURE_OF_OPERATION_OPTIONS.find((o) => o.natureOperation === p.nature_operation)
      || NATURE_OF_OPERATION_OPTIONS[0];

    setEmitOrigin({ type: 'manual', id: null });
    setEmitIdempotencyKey(crypto.randomUUID());
    setNatureOfOperation(nat.value);
    setClientId(doc.client_id || '');
    setRecipientName(r.name || '');
    setRecipientDocument(r.document || '');
    setRecipientEmail(r.email || '');
    setRecipientIeIndicator(Number(r.state_registration_indicator ?? 9) || 9);
    setRecipientIe(r.state_registration || '');
    setConsumerFinal(p.consumer_final !== false);
    setPresenceIndicator(Number(p.presence_indicator ?? 1) || 1);
    setAdditionalInfo(p.additional_info || '');
    setReferencedAccessKey((p.referenced_access_keys && p.referenced_access_keys[0]) || '');
    setPaymentMethod((p.payments && p.payments[0]?.method) || '01');
    setAddress({
      postal_code: a.postal_code || '',
      address_line_1: a.street || '',
      address_number: a.number && a.number !== 'S/N' ? a.number : '',
      address_complement: a.complement || '',
      neighborhood: a.district || '',
      city: a.city_name || '',
      state: a.state_code || '',
      country: 'Brasil',
    });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    setItems((p.items || []).map((it: any) => {
      const t = it.taxes || {};
      const icms = t.icms || {}; const pis = t.pis || {}; const cofins = t.cofins || {}; const ipi = t.ipi || {};
      return {
        productId: null,
        code: it.code || '', name: it.name || '', ncm: it.ncm || '',
        cfop: it.cfop || '', unit: it.unit || 'UN',
        quantity: Number(it.quantity) || 0, unit_price: Number(it.unit_price) || 0,
        csosn: icms.code || '400', origin: Number(icms.origin ?? 0) || 0,
        icms_rate: Number(icms.aliquot ?? 0) || 0,
        pis_rate: Number(pis.aliquot ?? 0) || 0,
        cofins_rate: Number(cofins.aliquot ?? 0) || 0,
        ipi_rate: Number(ipi.aliquot ?? 0) || 0,
        included: true,
      };
    }));
    setShowEmit(true);
  };

  // "Gerar devolução" a partir de uma nota AUTORIZADA: cria uma NF-e de devolução
  // de venda (entrada, finNFe=4, CFOP 1202/2202) espelhando exatamente a nota
  // original (itens, impostos, cliente) e referenciando-a POR ITEM (VC02-14:
  // chave + nItem). O usuário escolhe total ou parcial (checkbox + quantidade).
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleGenerateReturn = (doc: any) => {
    const p = doc.request_payload || {};
    const r = p.recipient || {};
    const a = r.address || {};
    const key: string = doc.access_key || '';
    // CFOP de devolução de venda calculado agora (o state da natureza ainda não
    // atualizou neste render), para já gravar 1202/2202 em cada item.
    const nature = findNatureOfOperation('devolucao_venda');
    const devCfop = computeCfop(nature.baseCfopCode, nature.operationType, company?.state_code, a.state_code);

    setEmitOrigin({ type: 'manual', id: null });
    setEmitIdempotencyKey(crypto.randomUUID());
    setNatureOfOperation('devolucao_venda');
    setClientId(doc.client_id || '');
    setRecipientName(r.name || '');
    setRecipientDocument(r.document || '');
    setRecipientEmail(r.email || '');
    setRecipientIeIndicator(Number(r.state_registration_indicator ?? 9) || 9);
    setRecipientIe(r.state_registration || '');
    setConsumerFinal(p.consumer_final !== false);
    setPresenceIndicator(Number(p.presence_indicator ?? 1) || 1);
    setAdditionalInfo(`Devolução referente à NF-e nº ${doc.number}, série ${doc.series}${key ? `, chave ${key}` : ''}.`);
    setReferencedAccessKey(key);
    setPaymentMethod((p.payments && p.payments[0]?.method) || '01');
    setAddress({
      postal_code: a.postal_code || '',
      address_line_1: a.street || '',
      address_number: a.number && a.number !== 'S/N' ? a.number : '',
      address_complement: a.complement || '',
      neighborhood: a.district || '',
      city: a.city_name || '',
      state: a.state_code || '',
      country: 'Brasil',
    });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    setItems((p.items || []).map((it: any, i: number) => {
      const t = it.taxes || {};
      const icms = t.icms || {}; const pis = t.pis || {}; const cofins = t.cofins || {}; const ipi = t.ipi || {};
      const qty = Number(it.quantity) || 0;
      return {
        productId: null,
        code: it.code || '', name: it.name || '', ncm: it.ncm || '',
        cfop: devCfop, unit: it.unit || 'UN',
        quantity: qty, unit_price: Number(it.unit_price) || 0,
        // Espelha os impostos da nota original (é a nossa própria nota Simples).
        csosn: icms.code || '400', origin: Number(icms.origin ?? 0) || 0,
        icms_rate: Number(icms.aliquot ?? 0) || 0,
        pis_rate: Number(pis.aliquot ?? 0) || 0,
        cofins_rate: Number(cofins.aliquot ?? 0) || 0,
        ipi_rate: Number(ipi.aliquot ?? 0) || 0,
        included: true,
        maxQuantity: qty, // não deixa devolver mais do que foi vendido
        referencedKey: key,
        referencedItemNumber: i + 1, // nItem na nota original
      };
    }));
    setShowEmit(true);
  };

  // Faturar um orçamento/OS: abre a emissão pré-preenchida com o cliente e os
  // PRODUTOS da OS (serviços/mão de obra ficam de fora — NF-e é de produto). A
  // nota fica vinculada à OS (origin_type=service_order) e marca invoicing_status.
  const handleInvoiceFrom = (inv: { serviceOrderId: string; clientId: string | null; items: Array<{ productId: string; quantity: number; unitPrice: number }> }) => {
    setEmitOrigin({ type: 'service_order', id: inv.serviceOrderId });
    setEmitIdempotencyKey(crypto.randomUUID());
    setNatureOfOperation('venda');
    setPaymentMethod('01');
    setPresenceIndicator(1);
    setConsumerFinal(true);
    setAdditionalInfo(SIMPLES_INFO_NOTE);
    setReferencedAccessKey('');
    const c = inv.clientId ? (clients || []).find((cl) => cl.id === inv.clientId) : null;
    if (c) { setClientId(c.id); populateFromClient(c); }
    else {
      setClientId(''); setRecipientName(''); setRecipientDocument(''); setRecipientEmail('');
      setRecipientIeIndicator(9); setRecipientIe(''); setAddress(EMPTY_ADDRESS);
    }
    // CFOP de venda calculado agora (state ainda não atualizou): intra/inter UF.
    const vendaCfop = computeCfop('102', 'saida', company?.state_code, c?.state);
    setItems(inv.items.map((it) => {
      const p = (products || []).find((pr) => pr.id === it.productId);
      const rf = resolveItemFiscal(it.productId);
      return {
        productId: it.productId,
        code: p?.sku || it.productId.slice(0, 8),
        name: p?.name || '',
        ncm: rf.ncm || p?.ncm || '',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        cfop: (p as any)?.cfop || vendaCfop,
        unit: p?.unit || 'UN',
        quantity: it.quantity,
        unit_price: it.unitPrice,
        csosn: rf.csosn, origin: rf.origin, icms_rate: rf.icmsRate,
        pis_rate: rf.pisRate, cofins_rate: rf.cofinsRate, ipi_rate: rf.ipiRate,
        included: true,
      };
    }));
    setShowEmit(true);
  };

  // Faturar a partir de um orçamento/OS: QuoteList/ServiceOrderList navegam para
  // cá com o estado `invoiceFrom`. Espera company+products carregarem (para
  // resolver os impostos), abre o diálogo e limpa o estado (não reabre ao voltar).
  useEffect(() => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const inv = (location.state as any)?.invoiceFrom;
    if (inv && company && products) {
      handleInvoiceFrom(inv);
      window.history.replaceState({}, '');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.state, company, products]);

  // Devolução ao fornecedor a partir de uma nota de COMPRA importada
  // (ImportFiscalXML navega para cá com `returnToSupplier`). Emite uma NF-e de
  // SAÍDA, finalidade 4, CFOP 5202/6202 (devolução de compra p/ comercialização),
  // destinatário = fornecedor (emitente da original), referência POR ITEM
  // (chave do fornecedor + nItem, VC02-14). CSOSN 900 é o padrão do Simples para
  // devolução de compra (a contadora ajusta se necessário); origem e valores
  // vêm EXATOS do XML da compra. Sem pagamento (tPag 90, resolvido no builder).
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleReturnToSupplier = (ret: any) => {
    const nature = findNatureOfOperation('devolucao_compra');
    const uf = ret?.issuer?.address?.stateCode || '';
    const devCfop = computeCfop(nature.baseCfopCode, nature.operationType, company?.state_code, uf);
    const key: string = ret?.accessKey || '';
    const hasIe = !!String(ret?.issuer?.stateRegistration || '').replace(/\D/g, '').length;

    setEmitOrigin({ type: 'manual', id: null });
    setEmitIdempotencyKey(crypto.randomUUID());
    setNatureOfOperation('devolucao_compra');
    setClientId(''); // o fornecedor não é um "cliente" do cadastro
    setRecipientName(ret?.issuer?.name || '');
    setRecipientDocument(ret?.issuer?.document || '');
    setRecipientEmail('');
    // Fornecedor é contribuinte do ICMS (Regime Normal) → indIEDest=1 + IE quando
    // veio no XML; sem IE, cai para 9 (não contribuinte) para não travar a emissão.
    setRecipientIeIndicator(hasIe ? 1 : 9);
    setRecipientIe(ret?.issuer?.stateRegistration || '');
    setConsumerFinal(false); // devolução B2B — o fornecedor não é consumidor final
    setPresenceIndicator(1);
    setPaymentMethod('01'); // ignorado (natureza sem pagamento → tPag 90)
    setAdditionalInfo(`Devolução de compra referente à NF-e do fornecedor${key ? `, chave ${key}` : ''}.`);
    setReferencedAccessKey(key);
    const a = ret?.issuer?.address || {};
    setAddress({
      postal_code: a.postalCode || '',
      address_line_1: a.street || '',
      address_number: a.number && a.number !== 'S/N' ? a.number : '',
      address_complement: a.complement || '',
      neighborhood: a.district || '',
      city: a.cityName || '',
      state: a.stateCode || '',
      country: 'Brasil',
    });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    setItems((ret?.items || []).map((it: any, i: number) => {
      const qty = Number(it.quantity) || 0;
      return {
        productId: null,
        code: it.code || '', name: it.name || '', ncm: it.ncm || '',
        cfop: devCfop, unit: it.unit || 'UN',
        quantity: qty, unit_price: Number(it.unitPrice) || 0,
        // Simples em devolução de compra: CSOSN 900, sem destaque de ICMS. A
        // origem da mercadoria é preservada do XML da compra (intrínseca ao item).
        csosn: '900', origin: Number(it.origin ?? 0) || 0,
        icms_rate: 0, pis_rate: 0, cofins_rate: 0, ipi_rate: 0,
        included: true,
        maxQuantity: qty, // não permite devolver mais do que foi comprado
        referencedKey: key,
        referencedItemNumber: i + 1, // nItem na nota de compra original
      };
    }));
    setShowEmit(true);
  };

  useEffect(() => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const ret = (location.state as any)?.returnToSupplier;
    if (ret && company) {
      handleReturnToSupplier(ret);
      window.history.replaceState({}, '');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.state, company]);

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

  // No modo devolução o usuário pode desmarcar itens (parcial) — só contam/vão
  // os incluídos (included !== false).
  const activeItems = items.filter((it) => it.included !== false);
  const total = activeItems.reduce((sum, it) => sum + it.quantity * it.unit_price, 0);

  const handleEmit = async () => {
    setEmitting(true);
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', {
        body: {
          action: 'create',
          origin_type: emitOrigin.type,
          origin_id: emitOrigin.id || undefined,
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
          items: activeItems.map((it) => ({
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
            referenced_key: it.referencedKey || undefined,
            referenced_item: it.referencedItemNumber || undefined,
          })),
        },
      });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) throw new Error(data.error);

      const env = data?.data?.environment === 'producao' ? 'produção' : 'homologação';
      toast.success(`NF-e enviada para processamento (ambiente: ${env}). Acompanhe o status abaixo.`);
      // Ao faturar um orçamento/OS, marca a OS como faturada.
      if (emitOrigin.type === 'service_order' && emitOrigin.id) {
        await (supabase.from as any)('service_orders')
          .update({ invoicing_status: 'invoiced', updated_at: new Date().toISOString() })
          .eq('id', emitOrigin.id);
        qc.invalidateQueries({ queryKey: ['service-orders'] });
      }
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

  // Carta de Correção Eletrônica (CC-e): corrige erros que NÃO alteram valores,
  // impostos, destinatário ou datas (ex.: endereço, observações). Prazo legal
  // de 30 dias. O backend (action="correction") exige nota autorizada + mínimo
  // de 15 caracteres.
  const handleConfirmCorrection = async () => {
    if (!correctionTarget || correctionText.trim().length < MIN_JUSTIFICATION_LENGTH) return;
    markBusy(correctionTarget.id, true);
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', {
        body: { action: 'correction', document_id: correctionTarget.id, text: correctionText.trim() },
      });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      if (data?.error) throw new Error(data.error);
      toast.success('Carta de Correção enviada. Acompanhe o status.');
      markBusy(correctionTarget.id, false);
      setCorrectionTarget(null);
      setCorrectionText('');
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
    } catch (err: any) {
      toast.error('Erro ao enviar a correção: ' + err.message);
      markBusy(correctionTarget.id, false);
    }
  };

  // Abre DANFE/XML pelo proxy autenticado — as URLs de artefato da Contora
  // exigem o Bearer token, então não dá para abrir direto no navegador
  // ("Bearer token ausente"). O edge function busca com o token e devolve os
  // bytes; abrimos como blob local.
  const handleViewArtifact = async (docId: string, kind: 'pdf_danfe' | 'xml_authorized') => {
    markBusy(docId, true);
    try {
      const { data, error } = await supabase.functions.invoke('fiscal-emit', {
        body: { action: 'artifact', document_id: docId, artifact: kind },
      });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      const blob = data instanceof Blob
        ? data
        : new Blob([data as BlobPart], { type: kind === 'pdf_danfe' ? 'application/pdf' : 'application/xml' });
      const url = URL.createObjectURL(blob);
      window.open(url, '_blank');
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    } catch (err: any) {
      toast.error('Erro ao abrir o documento: ' + err.message);
    } finally {
      markBusy(docId, false);
    }
  };

  // Envia o DANFE (PDF) ao cliente por WhatsApp. O PDF é arquivado no bucket
  // privado fiscal-xml (apply-status, autenticado) — geramos uma URL assinada
  // de curta duração (o front tem policy de leitura só p/ admin) e a passamos
  // ao whatsapp-send (kind=document). Se o PDF ainda não foi arquivado (webhook
  // pode não ter chegado), força um reconcile pontual e re-lê o caminho.
  const handleSendToClient = async (doc: any) => {
    const client = (clients || []).find((c: any) => c.id === doc.client_id);
    const phoneRaw: string = client?.whatsapp || client?.phone || '';
    const phoneDigits = phoneRaw.replace(/\D/g, '');
    if (!doc.client_id || phoneDigits.length < 10) {
      toast.error('Cliente sem WhatsApp/telefone válido. Edite o cadastro do cliente (com DDD) e tente de novo.');
      return;
    }
    markBusy(doc.id, true);
    const tId = toast.loading('Preparando o DANFE e enviando…');
    try {
      let pdfPath: string | null = doc.pdf_storage_path || null;
      if (!pdfPath) {
        // Arquiva sob demanda (idempotente): reconcile reconsulta a nota
        // autorizada sem PDF e baixa o DANFE para o Storage.
        await supabase.functions.invoke('fiscal-reconcile', { body: { document_id: doc.id } });
        const { data: fresh } = await (supabase.from as any)('issued_fiscal_documents')
          .select('pdf_storage_path')
          .eq('id', doc.id)
          .maybeSingle();
        pdfPath = fresh?.pdf_storage_path || null;
      }
      if (!pdfPath) {
        toast.error('O DANFE ainda está sendo gerado. Tente novamente em alguns instantes.', { id: tId });
        return;
      }
      const { data: signed, error: signErr } = await supabase.storage
        .from('fiscal-xml')
        .createSignedUrl(pdfPath, 3600);
      if (signErr || !signed?.signedUrl) throw new Error(signErr?.message || 'Falha ao gerar o link do DANFE.');

      const filename = `NFe-${doc.series}-${doc.number}.pdf`;
      const caption = `Olá${client?.name ? ' ' + client.name : ''}! Segue em anexo o DANFE da NF-e ${doc.series}/${doc.number}. Qualquer dúvida, estamos à disposição.`;
      const { data: sendRes, error: sendErr } = await supabase.functions.invoke('whatsapp-send', {
        body: {
          phone: phoneDigits,
          kind: 'document',
          document_url: signed.signedUrl,
          document_filename: filename,
          document_caption: caption,
          context: 'nfe',
        },
      });
      if (sendErr) throw new Error(await extractInvokeErrorMessage(sendErr));
      if ((sendRes as any)?.error) {
        const e = (sendRes as any).error;
        throw new Error(typeof e === 'string' ? e : 'Falha no envio pelo WhatsApp.');
      }
      toast.success('DANFE enviado ao cliente por WhatsApp.', { id: tId });
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
    } catch (err: any) {
      toast.error('Erro ao enviar ao cliente: ' + (err?.message || 'desconhecido'), { id: tId });
    } finally {
      markBusy(doc.id, false);
    }
  };

  // "Baixar estoque + gerar recebível" (opt-in) numa NF-e AVULSA autorizada.
  // Chama a RPC atômica settle_nfe_stock_and_receivable: baixa o estoque dos
  // itens ligados a produtos do catálogo e cria o recebível (à vista). Notas de
  // OS não entram (a OS já faz); é idempotente (o botão some após lançar).
  const handleSettleStock = async (doc: any) => {
    markBusy(doc.id, true);
    const tId = toast.loading('Baixando estoque e gerando recebível…');
    try {
      const { data, error } = await (supabase.rpc as any)('settle_nfe_stock_and_receivable', {
        p_document_id: doc.id,
      });
      if (error) throw new Error(error.message);
      if (data && data.ok === false) throw new Error(data.error || 'Falha ao lançar.');
      const n = Number(data?.stock_items ?? 0);
      toast.success(`Recebível gerado${n > 0 ? ` e estoque baixado (${n} item${n > 1 ? 'ns' : ''})` : ''}.`, { id: tId });
      qc.invalidateQueries({ queryKey: ['issued_fiscal_documents'] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
    } catch (err: any) {
      toast.error('Erro ao lançar estoque/recebível: ' + (err?.message || 'desconhecido'), { id: tId });
    } finally {
      markBusy(doc.id, false);
    }
  };

  // Export de XMLs autorizados de um período + um resumo CSV (livro de saída),
  // num único .zip para a contadora. Os XMLs são baixados pelo proxy autenticado
  // (action "artifact") — as URLs da Contora exigem token; o CSV é montado a
  // partir dos próprios registros (série/nº, chave, data, valor, destinatário).
  const handleExportXmls = async () => {
    if (!exportFrom || !exportTo || exportFrom > exportTo) {
      toast.error('Informe um período válido (início ≤ fim).');
      return;
    }
    setExporting(true);
    const tId = toast.loading('Consultando notas do período…');
    try {
      // Converte os limites do dia LOCAL para instantes UTC — authorized_at é
      // timestamptz; comparar string ingênua colocaria notas da virada do dia no
      // mês errado. Inclui autorizadas E canceladas (a contadora precisa da
      // cancelada no livro; senão o número parece uma inutilização/lacuna).
      const fromInstant = new Date(`${exportFrom}T00:00:00`).toISOString();
      const toInstant = new Date(`${exportTo}T23:59:59.999`).toISOString();
      const { data: docs, error } = await (supabase.from as any)('issued_fiscal_documents')
        .select('id, series, number, access_key, status, authorized_at, environment, request_payload')
        .in('status', ['authorized', 'cancelled'])
        .gte('authorized_at', fromInstant)
        .lte('authorized_at', toInstant)
        .order('number', { ascending: true });
      if (error) throw error;
      if (!docs?.length) {
        toast.error('Nenhuma NF-e autorizada/cancelada nesse período.', { id: tId });
        return;
      }

      // CSV com ; (Excel pt-BR) e BOM UTF-8; sanitiza campos livres.
      const csvSafe = (s: string) => String(s ?? '').replace(/[;\r\n]+/g, ' ').trim();
      const rows = ['Serie;Numero;Chave de Acesso;Data;Valor Total;Destinatario;CNPJ/CPF;Situacao;Ambiente'];
      const entries: ZipEntry[] = [];
      let ok = 0;
      let failed = 0;

      for (let i = 0; i < docs.length; i++) {
        const d = docs[i];
        toast.loading(`Baixando XML ${i + 1}/${docs.length}…`, { id: tId });
        const rec = d.request_payload?.recipient || {};
        const total = Number(d.request_payload?.payments?.[0]?.amount ?? 0);
        const dateStr = d.authorized_at ? new Date(d.authorized_at).toLocaleDateString('pt-BR') : '';
        rows.push([
          d.series, d.number, d.access_key || '', dateStr,
          total.toFixed(2).replace('.', ','),
          csvSafe(rec.name || ''), rec.document || '',
          d.status === 'cancelled' ? 'Cancelada' : 'Autorizada',
          d.environment === 'producao' ? 'Producao' : 'Homologacao',
        ].join(';'));

        try {
          const { data: xmlData, error: xmlErr } = await supabase.functions.invoke('fiscal-emit', {
            body: { action: 'artifact', document_id: d.id, artifact: 'xml_authorized' },
          });
          if (xmlErr) throw xmlErr;
          const text = xmlData instanceof Blob
            ? await xmlData.text()
            : typeof xmlData === 'string'
              ? xmlData
              : new TextDecoder().decode(xmlData as ArrayBuffer);
          if (text && text.trim().startsWith('<')) {
            const num = String(d.number).padStart(9, '0');
            entries.push({ name: `NFe-${d.series}-${num}-${d.access_key || d.id}.xml`, content: text });
            ok++;
          } else {
            failed++;
          }
        } catch {
          failed++;
        }
      }

      entries.push({ name: '_resumo-livro-saida.csv', content: '﻿' + rows.join('\r\n') + '\r\n' });
      const blob = createZipBlob(entries);
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `NFe-XMLs_${exportFrom}_a_${exportTo}.zip`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60_000);

      toast.success(`Exportadas ${ok} nota(s)${failed ? ` (${failed} XML não baixado)` : ''} + resumo CSV.`, { id: tId });
      setShowExport(false);
    } catch (err: any) {
      toast.error('Erro ao exportar: ' + (err?.message || 'desconhecido'), { id: tId });
    } finally {
      setExporting(false);
    }
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
        <Button variant="outline" onClick={() => setShowExport(true)} title="Baixar os XMLs autorizados de um período + resumo CSV para a contadora">
          <FileDown className="h-4 w-4 mr-2" />
          Exportar XMLs
        </Button>
        <Button onClick={openEmitDialog} disabled={!company}>
          <FileText className="h-4 w-4 mr-2" />
          Emitir NF-e
        </Button>
      </PageHeader>

      {isProducao && (
        <div className="rounded-lg border-2 border-red-500 bg-red-50 px-4 py-2.5 flex items-center gap-2">
          <span className="text-red-600 font-bold">⚠ AMBIENTE DE PRODUÇÃO</span>
          <span className="text-sm text-red-800">
            As NF-e emitidas aqui são <strong>reais</strong> e vão para a SEFAZ. Confira cada nota antes de emitir.
          </span>
        </div>
      )}

      {/* ── Painel de Saúde Fiscal ── */}
      {company && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
          {/* Certificado A1 */}
          {(() => {
            let tone = 'muted', label = '—', sub = 'Consultando…';
            if (certInfo) {
              sub = `Vence em ${formatDate(certInfo.validUntil)}`;
              if (certInfo.days < 0) { tone = 'red'; label = 'VENCIDO'; }
              else if (certInfo.days <= 7) { tone = 'red'; label = `Vence em ${certInfo.days}d`; }
              else if (certInfo.days <= 30) { tone = 'amber'; label = `Vence em ${certInfo.days}d`; }
              else { tone = 'green'; label = 'Válido'; }
            } else if (health?.company?.has_certificate) { tone = 'green'; label = 'Carregado'; sub = 'Sem data de validade informada'; }
            else if (health && health.company && health.company.has_certificate === false) { tone = 'red'; label = 'Sem certificado'; sub = 'Suba o A1 no painel da Contora'; }
            const t = { red: 'border-red-300 bg-red-50 text-red-700', amber: 'border-amber-300 bg-amber-50 text-amber-700', green: 'border-emerald-200 bg-emerald-50 text-emerald-700', muted: 'border-border bg-card text-muted-foreground' }[tone];
            return (
              <div className={`rounded-xl border p-3 ${t}`}>
                <p className="text-xs opacity-70">Certificado A1</p>
                <p className="text-base font-bold leading-tight">{label}</p>
                <p className="text-[11px] opacity-70 mt-0.5">{sub}</p>
              </div>
            );
          })()}

          {/* Cota Contora do mês (estimada) */}
          {(() => {
            const pct = monthStats.eventos / 500;
            const tone = pct >= 1 ? 'red' : pct >= 0.8 ? 'amber' : 'green';
            const bar = { red: 'bg-red-500', amber: 'bg-amber-500', green: 'bg-emerald-500' }[tone];
            return (
              <div className="rounded-xl border bg-card p-3">
                <p className="text-xs text-muted-foreground">Cota do mês (estimada)</p>
                <p className="text-base font-bold leading-tight">{monthStats.eventos} <span className="text-muted-foreground font-normal">/ 500</span></p>
                <div className="h-1.5 rounded-full bg-muted mt-2 overflow-hidden">
                  <div className={`h-full ${bar}`} style={{ width: `${Math.min(100, pct * 100)}%` }} />
                </div>
              </div>
            );
          })()}

          {/* Faturamento do mês */}
          <div className="rounded-xl border bg-card p-3">
            <p className="text-xs text-muted-foreground">Faturado no mês</p>
            <p className="text-base font-bold leading-tight">{formatCurrency(monthStats.faturamento)}</p>
            <p className="text-[11px] text-muted-foreground mt-0.5">{monthStats.authorized} nota(s) autorizada(s)</p>
          </div>

          {/* Notas por status */}
          <div className={`rounded-xl border p-3 ${monthStats.rejected > 0 ? 'border-red-300 bg-red-50' : 'bg-card'}`}>
            <p className="text-xs text-muted-foreground">Notas do mês</p>
            <p className="text-base font-bold leading-tight">
              <span className="text-emerald-600">{monthStats.authorized}</span>
              <span className="text-muted-foreground font-normal text-sm"> aut.</span>
              {monthStats.rejected > 0 && <span className="text-red-600 ml-2">{monthStats.rejected} <span className="font-normal text-sm">rej.</span></span>}
            </p>
            <p className="text-[11px] text-muted-foreground mt-0.5">
              {monthStats.cancelled > 0 ? `${monthStats.cancelled} cancelada(s)` : 'nenhuma cancelada'}
            </p>
          </div>
        </div>
      )}

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
                        {['failed', 'rejected', 'cancelled', 'draft'].includes(doc.status) && doc.request_payload && (
                          <Button
                            size="sm" variant="outline" className="text-xs"
                            onClick={() => handleReemitFromDoc(doc)}
                            title="Reabrir esta nota já preenchida para corrigir os dados e emitir de novo"
                          >
                            <Pencil className="h-3.5 w-3.5 mr-1" />Corrigir e reemitir
                          </Button>
                        )}
                        {['draft', 'queued', 'processing'].includes(doc.status) && (
                          <Button size="sm" variant="outline" disabled={isBusy} onClick={() => handleRefreshStatus(doc.id)}>
                            {isBusy ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <RefreshCw className="h-3.5 w-3.5" />}
                          </Button>
                        )}
                        {doc.status === 'authorized' && (
                          <>
                            <Button size="sm" variant="outline" disabled={isBusy} title="Baixar XML autorizado" onClick={() => handleViewArtifact(doc.id, 'xml_authorized')}>
                              <Download className="h-3.5 w-3.5" />
                            </Button>
                            <Button size="sm" variant="outline" disabled={isBusy} onClick={() => handleViewArtifact(doc.id, 'pdf_danfe')}>
                              DANFE
                            </Button>
                            {doc.client_id && (
                              <Button
                                size="sm" variant="outline" className="text-xs"
                                disabled={isBusy}
                                title="Enviar o DANFE (PDF) ao cliente por WhatsApp"
                                onClick={() => handleSendToClient(doc)}
                              >
                                <Send className="h-3.5 w-3.5 mr-1" />Enviar ao cliente
                              </Button>
                            )}
                            {doc.request_payload?.purpose !== 4 && doc.access_key && (
                              <Button
                                size="sm" variant="outline" className="text-xs"
                                title="Gerar uma NF-e de devolução (total ou parcial) desta venda, já referenciando a nota original"
                                onClick={() => handleGenerateReturn(doc)}
                              >
                                <Undo2 className="h-3.5 w-3.5 mr-1" />Gerar devolução
                              </Button>
                            )}
                            {doc.request_payload?.purpose !== 4 && doc.request_payload && (
                              <Button
                                size="sm" variant="outline" className="text-xs"
                                disabled={isBusy}
                                title="Duplicar: abre uma nova NF-e com os mesmos dados desta (cliente, itens, impostos). Ganha um novo número e você revisa antes de emitir — ideal para vendas recorrentes."
                                onClick={() => handleReemitFromDoc(doc)}
                              >
                                <Copy className="h-3.5 w-3.5 mr-1" />Duplicar
                              </Button>
                            )}
                            {doc.request_payload?.purpose !== 4
                              && doc.origin_type === 'manual'
                              && doc.client_id
                              && !doc.stock_settled_at && (
                              <Button
                                size="sm" variant="outline" className="text-xs"
                                disabled={isBusy}
                                title="Baixar o estoque dos itens ligados a produtos do catálogo e gerar um recebível (à vista) desta venda avulsa. Notas de OS já fazem isso pelo fluxo da OS."
                                onClick={() => handleSettleStock(doc)}
                              >
                                <Boxes className="h-3.5 w-3.5 mr-1" />Baixar estoque + recebível
                              </Button>
                            )}
                            <Button
                              size="sm" variant="outline" className="text-xs"
                              disabled={isBusy}
                              title="Carta de Correção Eletrônica (CC-e) — corrige erros que não mudam valores, impostos, destinatário ou datas"
                              onClick={() => { setCorrectionTarget({ id: doc.id, number: doc.number, series: doc.series }); setCorrectionText(''); }}
                            >
                              CC-e
                            </Button>
                            <Button
                              size="sm" variant="ghost" className="text-destructive hover:text-destructive"
                              disabled={isBusy}
                              title="Cancelar a NF-e (janela de 24h após a autorização)"
                              onClick={() => setCancelTarget({ id: doc.id, authorized_at: doc.authorized_at })}
                            >
                              <Ban className="h-3.5 w-3.5" />
                            </Button>
                          </>
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

            {/* Diagnóstico da conta na Contora — mostra o que impede a emissão. */}
            <div className="rounded-lg border p-3 space-y-2">
              <div className="flex items-center justify-between">
                <p className="text-sm font-semibold flex items-center gap-1.5">
                  <Stethoscope className="h-4 w-4" /> Diagnóstico da conta Contora
                </p>
                <Button type="button" size="sm" variant="outline" onClick={handleRunDiagnostics} disabled={runningDiag}>
                  {runningDiag ? <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" /> : <RefreshCw className="h-3.5 w-3.5 mr-1" />}
                  Verificar
                </Button>
              </div>
              {!diagResult ? (
                <p className="text-xs text-muted-foreground">
                  Confirma, direto na Contora, se a empresa emissora está pronta (município/IBGE, certificado, ambiente) e
                  se a SEFAZ está online. Não gasta cota fiscal.
                </p>
              ) : (
                <ul className="space-y-1 text-xs">
                  {[
                    { ok: diagResult.token_ok, label: 'Token da Contora válido' },
                    { ok: !!diagResult.company?.found, label: `Empresa cadastrada na Contora${diagResult.company?.legal_name ? ` (${diagResult.company.legal_name})` : ''}` },
                    { ok: !!diagResult.company?.city_code, label: `Município/código IBGE preenchido${diagResult.company?.city_code ? ` (${diagResult.company.city_code})` : ''}` },
                    { ok: !!diagResult.company?.has_certificate, label: 'Certificado A1 enviado' },
                    { ok: diagResult.sefaz_ok, label: 'SEFAZ online' },
                  ].map((c, i) => (
                    <li key={i} className={`flex items-center gap-2 ${c.ok ? 'text-success' : 'text-destructive'}`}>
                      {c.ok ? <CheckCircle2 className="h-3.5 w-3.5" /> : <XCircle className="h-3.5 w-3.5" />}
                      {c.label}
                    </li>
                  ))}
                  {!diagResult.company?.city_code && (
                    <li className="text-amber-700 mt-1">
                      ⚠ Corrija no <strong>console da Contora → Empresas → editar → Município</strong>. Esse campo não é
                      editável por aqui (a API não expõe update de empresa).
                    </li>
                  )}
                  {/* Diagnóstico do verProc: o campo que a Contora usa como "versão do
                      software" tem limite de 20 caracteres. Mostramos os candidatos e
                      o comprimento — o que passar de 20 é a causa do erro de schema. */}
                  {diagResult.verproc_candidates && (() => {
                    const vc = diagResult.verproc_candidates!;
                    const rows = [
                      { label: 'Nome do token de API', val: vc.token_name, len: vc.token_name_len ?? 0 },
                      { label: 'Razão social (Contora)', val: vc.legal_name, len: vc.legal_name_len ?? 0 },
                      { label: 'Nome fantasia (Contora)', val: vc.trade_name, len: vc.trade_name_len ?? 0 },
                    ].filter((r) => r.val);
                    const suspect = rows.find((r) => r.len > 20);
                    return (
                      <li className="mt-2 border-t pt-2 list-none">
                        <p className="font-semibold text-foreground">verProc (versão do software, máx. 20):</p>
                        {rows.map((r, i) => (
                          <div key={i} className={r.len > 20 ? 'text-destructive' : 'text-muted-foreground'}>
                            {r.len > 20 ? '❌' : '•'} {r.label}: "{r.val}" ({r.len} caract.)
                          </div>
                        ))}
                        {suspect && (
                          <p className="text-amber-700 mt-1">
                            ⚠ O campo <strong>{suspect.label}</strong> tem {suspect.len} caracteres (a Contora provavelmente
                            o usa como verProc, limitado a 20). Renomeie-o para ≤20 no console da Contora e reemita.
                          </p>
                        )}
                      </li>
                    );
                  })()}
                </ul>
              )}
            </div>
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
            {isProducao && (
              <div className="rounded-lg border-2 border-red-500 bg-red-50 p-3 text-sm text-red-800">
                <span className="font-bold text-red-600">⚠ PRODUÇÃO — nota fiscal REAL.</span>{' '}
                Esta emissão vai para a SEFAZ de verdade e não é um teste. Revise destinatário, itens e impostos.
              </div>
            )}
            {isReturn && (
              <div className="rounded-lg border border-blue-300 bg-blue-50 p-3 text-xs text-blue-900 space-y-1">
                <p className="font-semibold flex items-center gap-1.5"><Undo2 className="h-3.5 w-3.5" />Nota de Devolução (finalidade 4)</p>
                <p>
                  Os itens abaixo espelham a nota original e já referenciam a NF-e origem <strong>por item</strong> (regra
                  VC02-14). Para devolução <strong>parcial</strong>, desmarque itens ou reduza a quantidade (teto = o que foi
                  vendido). Confira os valores e o CSOSN com a contadora antes de emitir em produção.
                </p>
              </div>
            )}
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
              <div className="flex gap-2">
                <div className="flex-1">
                  <EntityCombobox
                    value={clientId || null}
                    onChange={(v) => handleClientChange(v)}
                    options={clientOptions}
                    placeholder="Selecione um cliente..."
                    searchPlaceholder="Buscar cliente... (digite 3+ letras)"
                    emptyText="Nenhum cliente encontrado"
                  />
                </div>
                <Button
                  type="button" variant="outline" disabled={!clientId}
                  onClick={() => setShowClientForm(true)}
                  title="Abrir o cadastro do cliente para completar/corrigir (IE, endereço) sem sair da emissão"
                >
                  <Pencil className="h-3.5 w-3.5 mr-1" />Editar cadastro
                </Button>
              </div>
              {clientId && (
                <p className="text-[11px] text-muted-foreground mt-1">
                  Faltou algum dado (IE, número, bairro)? Edite o cadastro aqui — ele é salvo e os campos abaixo se
                  atualizam na hora.
                </p>
              )}
            </div>

            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-sm">Destinatário</CardTitle></CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label>Nome / Razão Social</Label>
                    <Input maxLength={60} value={recipientName} onChange={(e) => setRecipientName(e.target.value)} />
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
                  <div key={index} className={`rounded-lg border p-3 space-y-2 ${it.included === false ? 'opacity-50' : ''}`}>
                    {/* Devolução: incluir/excluir o item (parcial) + referência por item (VC02-14). */}
                    {it.referencedItemNumber != null && (
                      <div className="flex items-center justify-between gap-2 border-b pb-2 mb-1">
                        <label className="flex items-center gap-2 text-xs cursor-pointer">
                          <input type="checkbox" className="h-4 w-4" checked={it.included !== false} onChange={(e) => updateItem(index, { included: e.target.checked })} />
                          Incluir na devolução
                        </label>
                        <span className="text-[10px] text-muted-foreground font-mono">
                          ref: item {it.referencedItemNumber} da NF-e {it.referencedKey ? `…${it.referencedKey.slice(-6)}` : '—'}
                        </span>
                      </div>
                    )}
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
                      <Input placeholder="Descrição" className="h-8 text-xs" maxLength={120} value={it.name} onChange={(e) => updateItem(index, { name: e.target.value })} />
                      <Input placeholder="Código" className="h-8 text-xs" maxLength={60} value={it.code} onChange={(e) => updateItem(index, { code: e.target.value })} />
                    </div>
                    <div className="grid grid-cols-4 gap-2">
                      <div>
                        <Label className="text-[10px] text-muted-foreground">NCM</Label>
                        <Input placeholder="NCM" className="h-8 text-xs" maxLength={8} value={it.ncm} onChange={(e) => updateItem(index, { ncm: e.target.value.replace(/\D/g, '') })} />
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">CFOP</Label>
                        <Input placeholder="CFOP" className="h-8 text-xs" maxLength={4} value={it.cfop} onChange={(e) => updateItem(index, { cfop: e.target.value.replace(/\D/g, '') })} />
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">Unid.</Label>
                        <Input placeholder="Unid." className="h-8 text-xs" maxLength={6} value={it.unit} onChange={(e) => updateItem(index, { unit: e.target.value })} />
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">Qtd{it.maxQuantity != null ? ` (máx ${it.maxQuantity})` : ''}</Label>
                        <Input
                          type="number" min="0" max={it.maxQuantity ?? undefined} placeholder="Qtd" className="h-8 text-xs"
                          value={it.quantity}
                          onChange={(e) => {
                            let q = Math.max(0, parseFloat(e.target.value) || 0);
                            // Devolução não pode exceder a quantidade vendida na nota original.
                            if (it.maxQuantity != null && q > it.maxQuantity) q = it.maxQuantity;
                            updateItem(index, { quantity: q });
                          }}
                        />
                      </div>
                    </div>
                    {/* Impostos — auto-preenchidos do cadastro fiscal do produto, editáveis. */}
                    <div className="grid grid-cols-2 gap-2">
                      <div>
                        <Label className="text-[10px] text-muted-foreground">CSOSN (situação do ICMS)</Label>
                        <Select value={it.csosn || '400'} onValueChange={(v) => updateItem(index, { csosn: v })}>
                          <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {CSOSN_OPTIONS.map((o) => (
                              <SelectItem key={o.value} value={o.value} className="text-xs">{o.label}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        {['101', '201', '202', '500'].includes(it.csosn) && (
                          <p className="text-[10px] text-amber-700 mt-0.5">
                            Este CSOSN exige campos extras (crédito/ICMS-ST) que ainda não enviamos — confirme com a contadora.
                          </p>
                        )}
                      </div>
                      <div>
                        <Label className="text-[10px] text-muted-foreground">Origem da mercadoria</Label>
                        <Select value={String(it.origin ?? 0)} onValueChange={(v) => updateItem(index, { origin: Number(v) })}>
                          <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {FISCAL_ORIGIN_OPTIONS.map((o) => (
                              <SelectItem key={o.value} value={String(o.value)} className="text-xs">{o.label}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    </div>
                    <div className="grid grid-cols-3 gap-2">
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
                {selectedNature.hasPayment ? (
                  <Select value={paymentMethod} onValueChange={setPaymentMethod}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {PAYMENT_METHODS.filter((m) => m.value !== '90').map((m) => (
                        <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                ) : (
                  <div className="h-10 flex items-center px-3 rounded-md border bg-muted/40 text-sm text-muted-foreground">
                    Sem Pagamento (devolução/remessa não têm transação financeira)
                  </div>
                )}
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
            <Button onClick={handleEmit} disabled={emitting || includedItems.length === 0 || !preflightOk}>
              {emitting ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <FileText className="h-4 w-4 mr-2" />}
              {isReturn ? 'Emitir Devolução' : 'Emitir NF-e'}
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
          {(() => {
            // Janela padrão de cancelamento sem ônus: 24h após a autorização.
            const authAt = cancelTarget?.authorized_at ? new Date(cancelTarget.authorized_at).getTime() : null;
            const hrs = authAt ? (Date.now() - authAt) / 3_600_000 : null;
            if (hrs == null) return null;
            return hrs > 24 ? (
              <p className="text-xs text-destructive bg-destructive/10 rounded-md p-2">
                ⚠ Já se passaram {Math.floor(hrs)}h da autorização — o prazo de 24h para cancelamento sem ônus
                venceu. A SEFAZ pode recusar o cancelamento; se for só corrigir um dado, use a CC-e.
              </p>
            ) : (
              <p className="text-xs text-muted-foreground">
                Dentro do prazo de 24h (autorizada há {Math.floor(hrs)}h{Math.round((hrs % 1) * 60)}min).
              </p>
            );
          })()}
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

      {/* ── Dialog: Carta de Correção (CC-e) ── */}
      <Dialog open={!!correctionTarget} onOpenChange={(o) => { if (!o) { setCorrectionTarget(null); setCorrectionText(''); } }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Carta de Correção — NF-e {correctionTarget?.series}/{correctionTarget?.number}</DialogTitle>
            <DialogDescription>
              Corrija erros que <strong>não</strong> alteram valores, impostos, destinatário ou datas (ex.: endereço,
              informações complementares). Prazo legal: 30 dias da emissão.
            </DialogDescription>
          </DialogHeader>
          <Textarea
            value={correctionText}
            onChange={(e) => setCorrectionText(e.target.value)}
            placeholder="Ex.: No campo Informações Complementares, onde se lê X, leia-se Y."
            rows={4}
          />
          <p className={`text-xs ${correctionText.trim().length < MIN_JUSTIFICATION_LENGTH ? 'text-muted-foreground' : 'text-success'}`}>
            {correctionText.trim().length}/{MIN_JUSTIFICATION_LENGTH} caracteres mínimos
          </p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCorrectionTarget(null)}>Voltar</Button>
            <Button
              disabled={correctionText.trim().length < MIN_JUSTIFICATION_LENGTH || (correctionTarget ? busyDocIds.has(correctionTarget.id) : false)}
              onClick={handleConfirmCorrection}
            >
              {correctionTarget && busyDocIds.has(correctionTarget.id) ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Enviar Correção
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ── Dialog: exportar XMLs do período (contadora) ── */}
      <Dialog open={showExport} onOpenChange={(o) => { if (!exporting) setShowExport(o); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Exportar XMLs para a contadora</DialogTitle>
            <DialogDescription>
              Baixa, num único arquivo .zip, os XMLs de todas as NF-es <strong>autorizadas</strong> no
              período escolhido, mais um resumo em CSV (livro de saída: série/nº, chave, data, valor, destinatário).
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Início</Label>
              <Input type="date" value={exportFrom} max={exportTo} onChange={(e) => setExportFrom(e.target.value)} />
            </div>
            <div>
              <Label>Fim</Label>
              <Input type="date" value={exportTo} min={exportFrom} onChange={(e) => setExportTo(e.target.value)} />
            </div>
          </div>
          <p className="text-xs text-muted-foreground">
            Cada XML é baixado com autenticação (a chave/token nunca sai do servidor). Em períodos com muitas
            notas o download pode levar alguns segundos.
          </p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowExport(false)} disabled={exporting}>Voltar</Button>
            <Button onClick={handleExportXmls} disabled={exporting}>
              {exporting ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <FileDown className="h-4 w-4 mr-2" />}
              Exportar .zip
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Cadastro do cliente (popup) — editar na hora durante a emissão. */}
      <ClientFormDialog
        open={showClientForm}
        onOpenChange={setShowClientForm}
        client={(clients || []).find((c) => c.id === clientId) || null}
        onSaved={handleClientSaved}
      />
    </div>
  );
}
