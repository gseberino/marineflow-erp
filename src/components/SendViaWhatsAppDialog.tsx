import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Checkbox } from '@/components/ui/checkbox';
import { Loader2, Send, CalendarClock, Sparkles } from 'lucide-react';
import { toast } from 'sonner';
import { normalizePhoneE164 } from '@/lib/masks';
import { type PDFDocumentType, type PDFOptions, opcoesPadraoDoDocumento } from '@/lib/pdf-generator';
import { usePDFData } from '@/hooks/use-pdf';
import { useAppSettings } from '@/hooks/use-app-settings';
import { useWhatsAppTemplates, applyTemplateVariables } from '@/hooks/use-whatsapp-templates';
import {
  useClientWhatsAppSettings,
  pickClientSetting,
  type ClientWhatsAppContext,
} from '@/hooks/use-client-whatsapp-settings';
import { ModeSelector, type SendMode } from '@/components/whatsapp/ModeSelector';
import { RetrySettings } from '@/components/whatsapp/RetrySettings';
import { MessageEditor } from '@/components/whatsapp/MessageEditor';
import { ScheduleSettings, defaultScheduleConfig, type ScheduleConfig } from '@/components/whatsapp/ScheduleSettings';
import { useWhatsAppSend } from '@/hooks/use-whatsapp-send';
import { useCreateScheduledSend } from '@/hooks/use-scheduled-sends';
import { supabase } from '@/integrations/supabase/client';
import { buildQuoteWhatsAppSummary } from '@/lib/quote-whatsapp-summary';
import {
  CHAVE_DA_SAUDACAO,
  SAUDACAO_PADRAO,
  ehSaudacao,
  mensagemPadrao,
  modoInicial,
  opcoesDeSaudacao,
  prepararEnvio,
  temLinkNoTexto,
  textoDaSaudacao,
  tirarLinkDoTexto,
  trocarSaudacao,
  type Saudacao,
} from '@/lib/whatsapp-mensagem-ao-cliente';
import { mesmoTelefone } from '../../supabase/functions/_shared/ai/phone';
import { dataBR } from '../../supabase/functions/_shared/pdf/datas';

export type SendViaWhatsAppTarget =
  | {
      kind: 'service_order';
      serviceOrderId: string;
      serviceOrderNumber: string;
      shareToken?: string | null;
      clientId?: string | null;
      clientName?: string | null;
      clientPhone?: string | null;
      documentType?: PDFDocumentType;
    }
  | {
      kind: 'receivable';
      receivableId: string;
      description: string;
      serviceOrderId?: string | null;
      shareToken?: string | null;
      clientId?: string | null;
      clientName?: string | null;
      clientPhone?: string | null;
      amount?: number | null;
      dueDate?: string | null;
    };

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  target: SendViaWhatsAppTarget | null;
}

export function SendViaWhatsAppDialog({ open, onOpenChange, target }: Props) {
  // O padrão é o PDF, sem link (pedido do dono, 20/10/2026 — a mesma decisão de 05/10 do
  // assistente). Até aqui o diálogo abria no modo Link: o link ia mesmo sem ele pedir.
  const [mode, setMode] = useState<SendMode>('document');
  const [phone, setPhone] = useState('');
  const [message, setMessage] = useState('');
  // UMA caixa para o link, que vale no PDF (linha "Link online: …" na legenda), no Resumo e na
  // cobrança (desmarcada = texto puro, sem URL). Nasce desmarcada a cada abertura.
  const [enviarLink, setEnviarLink] = useState(false);
  // "Sem saudação" é o padrão: quase sempre ele já está conversando com o cliente. A tela
  // lembra a última escolha de quem usa (sem storage, volta ao padrão).
  const [saudacao, setSaudacao] = useState<Saudacao>(() => {
    try {
      const salva = localStorage.getItem(CHAVE_DA_SAUDACAO);
      return ehSaudacao(salva) ? salva : SAUDACAO_PADRAO;
    } catch { return SAUDACAO_PADRAO; }
  });
  const [templateId, setTemplateId] = useState<string>('');
  const [isGenerating, setIsGenerating] = useState(false);

  const [autoRetry, setAutoRetry] = useState<boolean>(() => {
    try { return localStorage.getItem('wa.autoRetry') !== '0'; } catch { return true; }
  });
  const [maxAttempts, setMaxAttempts] = useState<number>(() => {
    try {
      const v = parseInt(localStorage.getItem('wa.maxAttempts') || '3', 10);
      return Number.isFinite(v) && v >= 1 && v <= 5 ? v : 3;
    } catch { return 3; }
  });

  const [schedule, setSchedule] = useState<ScheduleConfig>(defaultScheduleConfig());
  const { send, sending, attemptInfo } = useWhatsAppSend();
  const createScheduled = useCreateScheduledSend();

  useEffect(() => {
    try { localStorage.setItem('wa.autoRetry', autoRetry ? '1' : '0'); } catch { /* sem localStorage (modo privado, cota): segue sem lembrar a preferência */ }
  }, [autoRetry]);
  useEffect(() => {
    try { localStorage.setItem('wa.maxAttempts', String(maxAttempts)); } catch { /* sem localStorage (modo privado, cota): segue sem lembrar a preferência */ }
  }, [maxAttempts]);

  const salesTemplates = useMemo(() => {
    if (target?.kind !== 'service_order') return [];
    const name = target.clientName?.split(' ')[0] || 'Cliente';
    const os = target.serviceOrderNumber;
    return [
      {
        id: 'tpl_follow_up',
        name: '📢 Lembrete / Follow-up',
        body: `Olá ${name}, passando para lembrar da proposta ${os} que enviamos. Ficou alguma dúvida ou algo que possamos ajudar?`,
        category: 'sales',
        active: true,
        sort_order: 0,
      },
      {
        id: 'tpl_negotiation',
        name: '💳 Negociação de Pagamento',
        body: `Olá ${name}, sobre o orçamento ${os}, podemos conversar sobre as condições de pagamento se necessário. O que fica melhor para você hoje?`,
        category: 'sales',
        active: true,
        sort_order: 1,
      },
      {
        id: 'tpl_scarcity',
        name: '⏳ Garantia de Vaga (Urgência)',
        body: `Olá ${name}, nossa agenda para os próximos dias está enchendo rapidamente. Gostaria de garantir sua vaga para a execução do serviço ${os}?`,
        category: 'sales',
        active: true,
        sort_order: 2,
      }
    ];
  }, [target]);

  const templateCategory =
    target?.kind === 'service_order'
      ? (target.documentType === 'quote' ? 'quote' : 'service_order')
      : 'billing';

  const { data: dbTemplates } = useWhatsAppTemplates(templateCategory);

  const templates = useMemo(() => {
    const list = [...(dbTemplates || [])];
    if (target?.kind === 'service_order') {
      list.unshift(...salesTemplates);
    }
    return list;
  }, [dbTemplates, salesTemplates, target]);

  const clientCtx: ClientWhatsAppContext =
    target?.kind === 'service_order'
      ? (target.documentType === 'quote' ? 'quote' : 'service_order')
      : 'billing';

  const { data: clientSettings } = useClientWhatsAppSettings(
    open ? (target?.clientId ?? null) : null,
  );
  const clientSetting = pickClientSetting(clientSettings, clientCtx);

  const pdfSourceId =
    target?.kind === 'service_order'
      ? target.serviceOrderId
      : target?.kind === 'receivable'
      ? target.serviceOrderId || undefined
      : undefined;
  // O resumo usa os MESMOS dados do PDF de propósito: se a mensagem escrita e o anexo
  // discordassem em algum valor, o cliente encontraria a diferença antes de nós.
  // Só orçamento/OS têm PDF e resumo neste envio; a cobrança vai como mensagem.
  const { data: pdfData } = usePDFData(
    open && target?.kind === 'service_order' && (mode === 'document' || mode === 'resumo') ? pdfSourceId : undefined,
  );

  const documentType: PDFDocumentType = useMemo(() => {
    if (target?.kind === 'service_order') return target.documentType || 'service_order';
    return 'invoice';
  }, [target]);

  // Mesma preferência de opções (mostrar termos, preços etc.) configurada em
  // Baixar/Imprimir PDF — sem isso, o envio via WhatsApp sempre usava o padrão de fábrica,
  // ignorando o que foi salvo em Configurações/PDFOptionsDialog para este tipo de documento.
  const { data: appSettings } = useAppSettings();
  //
  // A validade é do DOCUMENTO, e resolvePdfOptions a descarta de propósito (descreve um
  // padrão): opcoesPadraoDoDocumento a acrescenta — a data fixa do orçamento, senão os dias
  // dele, senão os da empresa. Sem ela o PDF anexado saía "Válido por 15 dias" (o literal do
  // gerador) para qualquer orçamento, inclusive os de 3 dias (até 26/09/2026).
  const pdfOptions = useMemo<PDFOptions>(
    () => opcoesPadraoDoDocumento(appSettings, documentType, pdfData?.serviceOrder),
    [appSettings, documentType, pdfData],
  );

  // Os DOIS números do cadastro (whatsapp e telefone), os mesmos que o whatsapp-send confere
  // para marcar o orçamento como enviado. Quem abre o diálogo passa só um (whatsapp || phone);
  // comparar só com ele faria a tela avisar "não marca" num envio que o servidor marca.
  const clienteId = target?.kind === 'service_order' ? target.clientId : null;
  const { data: numerosDoCliente } = useQuery({
    queryKey: ['client-phones', clienteId],
    enabled: open && !!clienteId,
    queryFn: async () => {
      const { data, error } = await supabase.from('clients').select('whatsapp, phone').eq('id', clienteId!).maybeSingle();
      if (error) throw error;
      return [data?.whatsapp, data?.phone];
    },
  });
  const numerosConhecidos = numerosDoCliente ?? [target?.clientPhone];
  const destinoEhDoCliente = numerosConhecidos.some((n) => mesmoTelefone(phone, n));
  const clienteTemNumero = numerosConhecidos.some((n) => String(n ?? '').replace(/\D/g, '').length >= 8);

  const publicUrl = useMemo(() => {
    if (!target) return '';
    const token = (target as any).shareToken;
    if (!token) return '';
    return `${window.location.origin}/view/${token}`;
  }, [target]);

  const templateVars = useMemo<Record<string, string | number>>(() => {
    if (!target) return {};
    const base: Record<string, string | number> = {
      cliente: target.clientName || '',
      link: publicUrl || '',
    };
    if (target.kind === 'service_order') {
      base.os = target.serviceOrderNumber;
      base.descricao = target.serviceOrderNumber;
    } else {
      base.descricao = target.description;
      if (target.amount != null) base.valor = Number(target.amount);
      base.vencimento = target.dueDate || '';
    }
    return base;
  }, [target, publicUrl]);

  /**
   * A abertura da mensagem pela saudação escolhida. "Bom dia/Boa tarde/Boa noite" segue a hora
   * em que a mensagem SAI: no envio agendado, a hora marcada — "Boa noite" escrito às 22h para
   * sair às 8h chegaria errado.
   */
  const horaDoEnvio = (): Date => {
    if (schedule.enabled && schedule.scheduledAt) {
      const marcada = new Date(schedule.scheduledAt);
      if (!Number.isNaN(marcada.getTime())) return marcada;
    }
    return new Date();
  };
  const abertura = textoDaSaudacao(saudacao, target?.clientName, horaDoEnvio());
  const opcoesSaudacao = opcoesDeSaudacao(target?.clientName, horaDoEnvio());

  // Os efeitos que MONTAM a mensagem (abertura do diálogo, resumo) leem a saudação daqui: com
  // ela nas dependências, trocar a saudação remontaria tudo e apagaria o que ele já editou.
  const saudacaoAtual = useRef(saudacao);
  const aberturaAtual = useRef(abertura);
  useEffect(() => {
    saudacaoAtual.current = saudacao;
    aberturaAtual.current = abertura;
  });
  /** A abertura que está na mensagem agora; mudou → troca só a abertura (efeito abaixo). */
  const aberturaAplicada = useRef<string | null>(null);

  // O link vai? Modo Link (mandar o link é a escolha) ou a caixa marcada.
  const linkVai = mode === 'link' || (enviarLink && !!publicUrl);

  useEffect(() => {
    if (!open || !target) return;
    setPhone(normalizePhoneE164(target.clientPhone || ''));
    // PDF quando dá para gerar; senão o Resumo; Link só se for o único; senão só a mensagem
    // (a cobrança). O resumo depende das opções do PDF (financeiros ocultos), mas o PDF vem
    // antes dele e é sempre possível num orçamento/OS.
    const podePdf = target.kind === 'service_order' && !!pdfSourceId;
    setMode(modoInicial({
      podePdf,
      podeResumo: podePdf,
      podeLink: target.kind === 'service_order' && !!publicUrl,
    }));
    setEnviarLink(false);
    setTemplateId('');
    setSchedule(defaultScheduleConfig());

    const agora = new Date();
    aberturaAplicada.current = textoDaSaudacao(saudacaoAtual.current, target.clientName, agora);
    if (clientSetting?.message_body) {
      // A mensagem padrão do cliente vale como ele a escreveu — só o link segue a caixa, que
      // nasce desmarcada: {link} fica sem valor e a frase que o apresenta sai junto.
      setMessage(tirarLinkDoTexto(applyTemplateVariables(clientSetting.message_body, { ...templateVars, link: '' }), publicUrl));
      return;
    }
    setMessage(mensagemPadrao({
      tipo: target.kind === 'service_order' ? (documentType === 'quote' ? 'quote' : 'service_order') : 'billing',
      numero: target.kind === 'service_order' ? target.serviceOrderNumber : null,
      descricao: target.kind === 'receivable' ? target.description : null,
      saudacao: saudacaoAtual.current,
      nomeDoCliente: target.clientName,
      agora,
    }));
  }, [open, target, pdfSourceId, publicUrl, documentType, clientSetting?.id, templateVars]);

  // Trocou a saudação (ou a hora do agendamento mudou o período): troca SÓ a abertura da
  // mensagem — o corpo que ele editou fica.
  useEffect(() => {
    if (!open || !target) return;
    if (aberturaAplicada.current === null || aberturaAplicada.current === abertura) {
      aberturaAplicada.current = abertura;
      return;
    }
    aberturaAplicada.current = abertura;
    setMessage((m) => trocarSaudacao(m, abertura, target.clientName));
  }, [open, target, abertura]);

  const escolherSaudacao = (valor: string) => {
    if (!ehSaudacao(valor)) return;
    setSaudacao(valor);
    try { localStorage.setItem(CHAVE_DA_SAUDACAO, valor); } catch { /* sem localStorage (modo privado, cota): segue sem lembrar a escolha */ }
  };

  const handleGenerateAI = async () => {
    if (!target || target.kind !== 'service_order') return;
    setIsGenerating(true);
    try {
      const clientName = target.clientName?.split(' ')[0] || 'Cliente';
      const prompt = target.documentType === 'quote'
        ? `Crie uma mensagem curta de WhatsApp muito persuasiva e educada para ${clientName}. Ele tem um orçamento (${target.serviceOrderNumber}) pendente. O objetivo é fechar a venda agora. Ofereça de forma sutil uma facilidade ou prioridade na agenda. Use gatilhos mentais. Não pareça desesperado.`
        // O número já traz o prefixo ("OS-00100"): "sobre a OS-00100", nunca "sobre a OS OS-00100".
        : `Crie uma mensagem de follow-up profissional para ${clientName} sobre a ${target.serviceOrderNumber}. Seja prestativo e foque na excelência do serviço.`;

      const { data, error } = await supabase.functions.invoke('ai-agent', {
        body: {
          messages: [{ role: 'user', content: prompt }],
          is_sales_copy: true,
          context: { route: '/crm', target: target.serviceOrderNumber }
        }
      });

      if (error) throw error;
      const aiText = data?.message?.content || data?.reply || "";
      if (aiText) setMessage(aiText.replace(/[*#]/g, ''));
      toast.success('Mensagem gerada com IA!');
    } catch (e) {
      console.error(e);
      toast.error('Falha ao gerar mensagem com IA');
    } finally {
      setIsGenerating(false);
    }
  };

  const applyTemplate = (id: string) => {
    setTemplateId(id);
    const tpl = templates?.find(t => t.id === id);
    if (!tpl || !target) return;
    // {valor} do orçamento/OS: o total do documento (o mesmo do PDF), quando já carregou. Sem
    // isso o modelo "Orçamento enviado" ia ao cliente com "no valor de {valor}" escrito.
    const total = target.kind === 'service_order' ? Number(pdfData?.serviceOrder?.grand_total) : NaN;
    const vars = {
      ...templateVars,
      ...(Number.isFinite(total) ? { valor: total } : {}),
      // Caixa desmarcada: {link} fica sem valor e a frase que o apresenta ("Acesso: ") sai junto.
      link: linkVai ? publicUrl : '',
    };
    const texto = applyTemplateVariables(tpl.body, vars);
    setMessage(linkVai ? texto : tirarLinkDoTexto(texto, publicUrl));
  };

  const canSendLink = !!publicUrl && target?.kind === 'service_order';
  const canSendDocument = target?.kind === 'service_order' && !!pdfSourceId;
  // Resumo escrito só faz sentido para orçamento/OS: uma cobrança avulsa não tem sinal,
  // saldo nem condição de pagamento para descrever.
  // Com os financeiros ocultos o resumo não teria o que dizer -- é um modo de valores.
  const canSendResumo = target?.kind === 'service_order' && !!pdfSourceId && !pdfOptions.hideFinancials;

  // Nenhum modo para escolher (a cobrança): o seletor não aparece, vai a mensagem.
  const temModoParaEscolher = canSendLink || canSendDocument || canSendResumo;

  /**
   * O que SAI, com o texto de agora: como viaja ('text', 'link' ou 'document'), o texto, a
   * legenda do PDF e se um link do texto vai sair por a caixa estar desmarcada.
   *
   * Até 20/10/2026 o Resumo viajava como 'link' — a Evolution colava a URL no fim — e não
   * havia como tirar. Agora Resumo e cobrança com a caixa desmarcada vão como TEXTO.
   */
  const envio = prepararEnvio({ modo: mode, mensagem: message, enviarLink, urlPublica: publicUrl });
  const modoDeEnvio = envio.transporte;
  // A caixa desmarcada tira o link do texto ao enviar — a tela avisa antes.
  const linkSaiDoTexto = !linkVai && temLinkNoTexto(message, publicUrl);
  /**
   * O agendamento ainda não anexa PDF: na hora marcada o servidor (whatsapp-process-scheduled)
   * manda o LINK no lugar. Com a caixa desmarcada isso seria o link que ele não pediu — então
   * o PDF agendado só sai com a caixa marcada (aí vai a mensagem com o link, e a tela diz).
   */
  const agendamentoSemPdf = schedule.enabled && mode === 'document';
  const agendarBloqueado = agendamentoSemPdf && !linkVai;

  /**
   * O texto do resumo, montado a partir do orçamento real.
   *
   * Fica num efeito e não no clique porque a pessoa precisa LER antes de enviar — e poder
   * editar. Orçamento é conversa comercial: a última palavra sobre o que vai escrito é de
   * quem está negociando, não do sistema.
   */
  useEffect(() => {
    if (!open || mode !== 'resumo' || !pdfData || target?.kind !== 'service_order') return;
    const so = pdfData.serviceOrder as Record<string, any>;
    // A linha "Olá, Fulano!" segue a saudação escolhida — "Sem saudação" = sem a linha.
    aberturaAplicada.current = aberturaAtual.current;
    setMessage(buildQuoteWhatsAppSummary({
      saudacao: aberturaAtual.current,
      numero: target.serviceOrderNumber,
      clienteNome: target.clientName,
      ativoNome: (pdfData as any)?.vessel?.name ?? null,
      orcamento: so,
      parcelas: so.payment_condition_installments ?? null,
      condicaoLabel: so.payment_condition_label ?? so.payment_conditions ?? null,
      // A MESMA validade do PDF deste envio (pdfOptions): data fixa, senão os dias do orçamento,
      // senão os da empresa — já normalizados. Antes o texto lia so.quote_validity_days cru e,
      // com data fixa, dizia "7 dias" enquanto o PDF dizia "até 10/10".
      validadeDias: pdfOptions.validity?.days ?? null,
      validadeAte: pdfOptions.validity?.mode === 'date' && pdfOptions.validity.date ? dataBR(pdfOptions.validity.date) : null,
      empresa: {
        nome: appSettings?.['company_name'],
        pixKey: appSettings?.['pix_key'],
        bankName: appSettings?.['bank_name'],
        bankAgency: appSettings?.['bank_agency'],
        bankAccount: appSettings?.['bank_account'],
      },
      opcoes: pdfOptions,
    }));
  }, [open, mode, pdfData, target, publicUrl, appSettings, pdfOptions]);

  useEffect(() => {
    if (!canSendLink && mode === 'link' && canSendDocument) setMode('document');
    // As opções do PDF chegam depois: com os financeiros ocultos o resumo deixa de existir.
    if (mode === 'resumo' && !canSendResumo) setMode(canSendDocument ? 'document' : 'texto');
  }, [canSendLink, canSendDocument, canSendResumo, mode]);

  if (!target) return null;

  // O número da OS já traz o prefixo ("OS-00100"): o título é ele, sem "OS " na frente.
  const titleLabel =
    target.kind === 'service_order'
      ? documentType === 'quote'
        ? `Orçamento ${target.serviceOrderNumber}`
        : target.serviceOrderNumber
      : `Cobrança — ${target.description}`;

  async function handleSend() {
    if (!target) return;
    // O número já traz o prefixo: a OS sai "OS-00100.pdf" (antes "OS-OS-00100.pdf"); o orçamento
    // segue "Orcamento-ORÇ-00100.pdf".
    const defaultFilename =
      target.kind === 'service_order'
        ? `${documentType === 'quote' ? `Orcamento-${target.serviceOrderNumber}` : target.serviceOrderNumber}.pdf`
        : `Cobranca-${target.receivableId.slice(0, 8)}.pdf`;
    const filename = clientSetting?.pdf_filename_pattern
      ? applyTemplateVariables(clientSetting.pdf_filename_pattern, templateVars)
          .replace(/[\\/:*?"<>|]/g, '_')
          .replace(/\.pdf$/i, '') + '.pdf'
      : defaultFilename;

    const link_title = clientSetting?.link_title
      ? applyTemplateVariables(clientSetting.link_title, templateVars)
      : titleLabel;
    const link_description = clientSetting?.link_description
      ? applyTemplateVariables(clientSetting.link_description, templateVars)
      : (target.kind === 'service_order'
          ? 'Toque para visualizar o documento completo.'
          : 'Toque para visualizar a cobrança.');

    // Caixa desmarcada: o texto sai sem link nenhum (envio.mensagem já vem sem ele) e a
    // legenda do PDF não ganha a linha "Link online".
    const caption = envio.legenda;

    if (schedule.enabled) {
      if (agendarBloqueado) {
        toast.error('O envio agendado ainda não anexa o PDF. Use o Resumo escrito, marque o link ou envie agora.');
        return;
      }
      const scheduledIso = new Date(schedule.scheduledAt).toISOString();
      if (new Date(scheduledIso).getTime() <= Date.now()) {
        toast.error('Escolha uma data/hora futura para o agendamento.');
        return;
      }
      try {
        await createScheduled.mutateAsync({
          target_kind: target.kind,
          service_order_id:
            target.kind === 'service_order' ? target.serviceOrderId : target.serviceOrderId || null,
          receivable_id: target.kind === 'receivable' ? target.receivableId : null,
          client_id: target.clientId || null,
          phone,
          message: envio.mensagem,
          send_mode: modoDeEnvio,
          context: target.kind === 'service_order' ? documentType : 'billing',
          link_title,
          link_description,
          pdf_filename: filename,
          caption,
          include_link_in_caption: envio.linkVai,
          scheduled_at: scheduledIso,
          recurrence_type: schedule.recurrenceType,
          recurrence_days_of_week:
            schedule.recurrenceType === 'weekly' ? schedule.daysOfWeek : undefined,
          recurrence_day_of_month:
            schedule.recurrenceType === 'monthly' ? schedule.dayOfMonth : undefined,
          recurrence_end_date: schedule.endDate
            ? new Date(schedule.endDate).toISOString()
            : null,
          auto_retry: autoRetry,
          max_attempts: maxAttempts,
        });
        onOpenChange(false);
      } catch {
        /* erro já exibido pelo hook */
      }
      return;
    }

    const ok = await send(
      {
        phone,
        message: envio.mensagem,
        mode: modoDeEnvio,
        context: target.kind === 'service_order' ? documentType : 'billing',
        service_order_id:
          target.kind === 'service_order'
            ? target.serviceOrderId
            : target.serviceOrderId || undefined,
        receivable_id: target.kind === 'receivable' ? target.receivableId : undefined,
        publicUrl,
        link_title,
        link_description,
        pdfData,
        documentType,
        filename,
        caption,
        pdfOptions,
      },
      { autoRetry, maxAttempts },
    );
    if (ok) onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={(v) => !sending && onOpenChange(v)}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Send className="h-5 w-5" /> Enviar via WhatsApp
          </DialogTitle>
          <DialogDescription>{titleLabel}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {temModoParaEscolher && (
            <ModeSelector
              mode={mode}
              onChange={setMode}
              canSendLink={canSendLink}
              canSendDocument={canSendDocument}
              canSendResumo={canSendResumo}
            />
          )}

          <div className="space-y-2">
            <Label htmlFor="phone-whatsapp">Telefone (com DDI)</Label>
            <Input
              id="phone-whatsapp"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="5521999998888"
            />
            {/* O envio só marca o orçamento como "enviado ao cliente" quando vai ao número do
                cliente (regra no whatsapp-send, 26/09/2026). Mandar para si ou para um terceiro
                continua possível — só não mexe no funil. Vale também para o envio agendado. */}
            {target?.kind === 'service_order' && documentType === 'quote'
              && phone.replace(/\D/g, '').length >= 8 && !destinoEhDoCliente && (
              <p className="text-xs text-amber-700 dark:text-amber-400">
                {clienteTemNumero ? 'Este número não é o cadastrado para o cliente' : 'O cliente não tem telefone cadastrado'}:
                {' '}enviar para ele não marca o orçamento como enviado ao cliente.
              </p>
            )}
          </div>

          {/* Trocar a saudação troca só a abertura da mensagem; o corpo editado fica. */}
          <div className="space-y-2">
            <Label htmlFor="saudacao-whatsapp">Saudação</Label>
            <select
              id="saudacao-whatsapp"
              className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
              value={saudacao}
              onChange={(e) => escolherSaudacao(e.target.value)}
              disabled={sending}
            >
              {opcoesSaudacao.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <div className="flex justify-between items-center">
              <Label>Mensagem</Label>
              {target?.kind === 'service_order' && (
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 text-xs gap-1.5 text-primary hover:text-primary hover:bg-primary/10"
                  onClick={handleGenerateAI}
                  disabled={isGenerating || sending}
                >
                  {isGenerating ? (
                    <Loader2 className="h-3 w-3 animate-spin" />
                  ) : (
                    <Sparkles className="h-3 w-3" />
                  )}
                  Gerar com IA
                </Button>
              )}
            </div>
            <MessageEditor
              message={message}
              onMessageChange={setMessage}
              mode={modoDeEnvio}
              templates={templates}
              templateId={templateId}
              onTemplateChange={applyTemplate}
              usingClientDefault={!!clientSetting?.message_body}
            />
            {linkSaiDoTexto && (
              <p className="text-xs text-amber-700 dark:text-amber-400">
                O link não vai: ele sai da mensagem ao enviar, porque a opção “Enviar também o link online” está desmarcada.
              </p>
            )}
          </div>

          {/* No modo Link o link É o envio; nos outros, só vai com esta caixa marcada. */}
          {mode !== 'link' && publicUrl && (
            <label className="flex items-start gap-2 text-sm cursor-pointer">
              <Checkbox
                checked={enviarLink}
                onCheckedChange={(v) => setEnviarLink(!!v)}
                className="mt-0.5"
              />
              <span>
                Enviar também o link online
                <span className="block text-xs text-muted-foreground">
                  {mode === 'document' ? 'Vai uma linha “Link online” na legenda do PDF.' : 'O link vai no fim da mensagem.'}
                </span>
              </span>
            </label>
          )}

          <RetrySettings
            autoRetry={autoRetry}
            onAutoRetryChange={setAutoRetry}
            maxAttempts={maxAttempts}
            onMaxAttemptsChange={setMaxAttempts}
            attemptInfo={attemptInfo}
            disabled={sending}
          />

          <ScheduleSettings
            value={schedule}
            onChange={setSchedule}
            disabled={sending || createScheduled.isPending}
          />

          {agendamentoSemPdf && (
            <p className="text-xs text-amber-700 dark:text-amber-400">
              {agendarBloqueado
                ? 'O envio agendado ainda não anexa o PDF: na hora marcada sairia o link online, e a opção do link está desmarcada. Para agendar, use o Resumo escrito ou marque “Enviar também o link online”; para mandar o PDF, envie agora.'
                : 'O envio agendado ainda não anexa o PDF: na hora marcada sai a mensagem com o link online.'}
            </p>
          )}
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={sending || createScheduled.isPending}
          >
            Cancelar
          </Button>
          <Button
            onClick={handleSend}
            disabled={sending || createScheduled.isPending || agendarBloqueado}
            className="gap-2"
          >
            {sending || createScheduled.isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : schedule.enabled ? (
              <CalendarClock className="h-4 w-4" />
            ) : (
              <Send className="h-4 w-4" />
            )}
            {schedule.enabled ? 'Agendar envio' : 'Enviar agora'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
