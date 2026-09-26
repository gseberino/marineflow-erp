import {
  blockTechnician,
  cargosQueContam,
  lerSolicitante,
  NON_TECHNICIAN_ROLES,
  type Role,
  type ToolCtx,
  type ToolDef,
} from "./registry.ts";
import { chaveDeEnvio, diaLocal, hashCurto, liberarEnvio } from "../../whatsapp/idempotencia.ts";
import { guardaDeEnvio } from "../comms/send-guard.ts";
import { registrarEnvio } from "../comms/send-log.ts";
import { documentTypeFor } from "../../pdf/document-type.ts";
import { fmtCurrency } from "../../pdf/documento.ts";
import { guardarEEntregar, impressaoDigitalDoDocumento, montarDocumentoDaOrdem } from "../../pdf/gerar-e-guardar.ts";
import { desviadoPorTeste } from "../../whatsapp/marcar-enviado.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Prévia amigável de mídia ("identificar e encaminhar" — sem custo de vision/transcrição).
function prettyPreview(body?: string | null): string | null {
  const b = (body || "").trim();
  if (!b) return null;
  if (b === "[audio]") return "🎤 áudio";
  if (b === "[image]") return "📷 imagem";
  if (b === "[video]") return "🎬 vídeo";
  if (b === "[document]") return "📎 arquivo";
  return b.slice(0, 100);
}

/**
 * POST na edge whatsapp-send — o caminho único de envio das tools (texto e documento).
 * Lê env em tempo de chamada (não no import do módulo) para não quebrar testes que nunca
 * chamam isto.
 *
 * No canal WhatsApp não há JWT de usuário (o toolCtx traz jwt=""), então usamos a
 * service-role key: o whatsapp-send tem um bypass explícito (isServiceRoleCall) para
 * chamadas de sistema. No painel, jwt é o token real do usuário.
 *
 * NÃO enviar header `apikey`: espelha o chamador que já funciona
 * (whatsapp-process-scheduled manda só Authorization: Bearer <service_role>).
 * Enviar `apikey: anon` JUNTO com um bearer service_role faz o gateway rejeitar com
 * 401 (sem corpo) por conflito de papel — foi o "HTTP 401" que o envio do agente dava.
 * O whatsapp-send roda com verify_jwt=true (não está no config.toml, vale o padrão): o
 * gateway exige um JWT válido, e o Bearer já é um — o apikey não acrescenta nada.
 */
async function postarWhatsappSend(corpo: Record<string, unknown>, jwt: string, signal?: AbortSignal): Promise<Response> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const authToken = jwt || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return await fetch(`${supabaseUrl}/functions/v1/whatsapp-send`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${authToken}`,
    },
    body: JSON.stringify(corpo),
    signal,
  });
}

/**
 * Manda um PDF (por URL que a Evolution baixa) para um número.
 *
 * `context` é obrigatório e nunca 'quote': com context='quote' + service_order_id o
 * whatsapp-send marca o orçamento como ENVIADO AO CLIENTE (whatsapp-send/index.ts), e daí
 * vêm a expiração automática, a tarefa de follow-up e o briefing tratando como enviado.
 * Quem chama daqui não passa service_order_id — o vínculo fica na auditoria do agente.
 */
export async function enviarDocumentoWhatsapp(p: {
  phone: string;
  url: string;
  filename: string;
  caption: string;
  context: string;
  jwt: string;
  dedupeKey?: string;
  limiteMs?: number;
}): Promise<{ ok: true; deduplicated?: boolean } | { ok: false; error: string; semResposta?: boolean }> {
  if (p.context === "quote") return { ok: false, error: "context 'quote' marca o orçamento como enviado ao cliente" };
  const controle = new AbortController();
  const relogio = setTimeout(() => controle.abort(), p.limiteMs ?? 25_000);
  try {
    const r = await postarWhatsappSend({
      phone: p.phone,
      kind: "document",
      document_url: p.url,
      document_filename: p.filename,
      document_caption: p.caption,
      context: p.context,
      ...(p.dedupeKey ? { dedupe_key: p.dedupeKey } : {}),
    }, p.jwt, controle.signal);
    const data = await r.json().catch(() => ({}));
    if (!r.ok) {
      const erro = (data as any).error;
      return { ok: false, error: typeof erro === "string" ? erro : erro ? JSON.stringify(erro) : `HTTP ${r.status}` };
    }
    return { ok: true, ...((data as any).deduplicated ? { deduplicated: true } : {}) };
  } catch (e) {
    // Sem resposta HTTP (tempo esgotado ou rede): desfecho desconhecido — ver enviarOrdemAoCliente.
    const abortado = e instanceof DOMException && e.name === "AbortError";
    return {
      ok: false,
      error: abortado ? "o envio pelo WhatsApp não respondeu em 25 s" : e instanceof Error ? e.message : String(e),
      semResposta: true,
    };
  } finally {
    clearTimeout(relogio);
  }
}

/**
 * Manda uma ORDEM (orçamento/OS) ao CLIENTE — texto com o link, ou o PDF com o link na legenda.
 *
 * Caminho PRÓPRIO, separado de `enviarDocumentoWhatsapp`, e é de propósito: aquele recusa
 * context='quote' para que o PDF que o dono pede PARA SI nunca marque o orçamento como
 * enviado. Aqui é o contrário — é o envio ao cliente, e ele TEM de levar context +
 * service_order_id: é o que vincula o registro do audit_log à ordem e deixa o whatsapp-send
 * marcar 'sent' quando o envio foi de fato ao cliente. Quem decide se marca é a edge
 * (_shared/whatsapp/marcar-enviado.ts): só marca se o destino for o telefone do cliente da
 * ordem, fora do modo de teste, em orçamento draft não convertido. Tirar a recusa de lá para
 * reaproveitar a função abriria o caminho de volta ao bug de 26/09/2026 (ORÇ-00072 e
 * ORÇ-00078 rejeitados sozinhos depois de envios que só foram ao número de teste).
 *
 * `context` é tipado: só 'quote' ou 'service_order'. `phone` vem do cadastro do cliente —
 * nunca de um argumento da tool.
 */
export async function enviarOrdemAoCliente(p: {
  phone: string;
  serviceOrderId: string;
  context: "quote" | "service_order";
  jwt: string;
  dedupeKey: string;
  conteudo: { kind: "text"; message: string } | { kind: "document"; url: string; filename: string; caption: string };
  /** Documento: 25 s (a Evolution baixa o arquivo dentro da chamada). Texto: sem corte, como sempre foi. */
  limiteMs?: number;
}): Promise<
  | { ok: true; deduplicated?: boolean; messageId?: string | null }
  | { ok: false; error: string; semResposta?: boolean }
> {
  const limite = p.limiteMs ?? (p.conteudo.kind === "document" ? 25_000 : null);
  const controle = new AbortController();
  const relogio = limite ? setTimeout(() => controle.abort(), limite) : null;
  const conteudo = p.conteudo.kind === "text"
    ? { kind: "text", message: p.conteudo.message }
    : {
      kind: "document",
      document_url: p.conteudo.url,
      document_filename: p.conteudo.filename,
      document_caption: p.conteudo.caption,
    };
  try {
    const r = await postarWhatsappSend({
      phone: p.phone,
      ...conteudo,
      context: p.context,
      service_order_id: p.serviceOrderId,
      dedupe_key: p.dedupeKey,
    }, p.jwt, controle.signal);
    const data = await r.json().catch(() => ({}));
    if (!r.ok) {
      const erro = (data as any).error;
      return { ok: false, error: typeof erro === "string" ? erro : erro ? JSON.stringify(erro) : `HTTP ${r.status}` };
    }
    if ((data as any).deduplicated) return { ok: true, deduplicated: true, messageId: null };
    return { ok: true, messageId: (data as any).messageId ?? null };
  } catch (e) {
    // Nenhuma resposta HTTP: tempo esgotado ou rede. A edge pode ter reservado a chave e até
    // enviado — `semResposta` é o que diz a quem chama que o desfecho é desconhecido (e que
    // só nesse caso a chave pode ser liberada).
    const abortado = e instanceof DOMException && e.name === "AbortError";
    return abortado
      ? { ok: false, error: `o envio pelo WhatsApp não respondeu em ${Math.round((limite ?? 0) / 1000)} s`, semResposta: true }
      : { ok: false, error: e instanceof Error ? e.message : String(e), semResposta: true };
  } finally {
    if (relogio) clearTimeout(relogio);
  }
}

// ─── Envio de orçamento/OS ao cliente: formato, cargos e resumo da confirmação ──────────

/** Os dois jeitos de mandar uma ordem ao cliente pelo assistente. */
export type FormatoDoEnvio = "pdf_e_link" | "link";

/**
 * Decisão do dono (26/09/2026): o padrão é o ARQUIVO PDF com o link na legenda — o cliente vê
 * o documento na conversa, sem abrir nada, e o link continua lá para aprovar e assinar.
 * "Só o link" é quando o dono pede.
 */
export const FORMATO_PADRAO: FormatoDoEnvio = "pdf_e_link";

/**
 * O formato pedido. Ausente/vazio → o padrão. Valor desconhecido → null: a tool recusa em vez
 * de adivinhar (adivinhar 'link' mandaria menos do que o dono quis; adivinhar 'pdf' mandaria
 * preço e PIX sem ele ter pedido).
 *
 * A trava de autonomia (autonomy-policy.ts, NEVER_AUTONOMOUS_WHEN) normaliza igual — só
 * "link" é liberável; o teste confere que as duas leituras não se separam.
 */
export function formatoDoEnvio(args: { formato?: unknown } | null | undefined): FormatoDoEnvio | null {
  const bruto = args?.formato;
  if (bruto === undefined || bruto === null || String(bruto).trim() === "") return FORMATO_PADRAO;
  const f = String(bruto).trim().toLowerCase();
  return f === "link" || f === "pdf_e_link" ? f : null;
}

/**
 * Quem pode mandar o PDF ao cliente. Lista explícita, e NÃO `NON_TECHNICIAN_ROLES`: aquela
 * inclui o vendedor externo, e o PDF leva preço, dados bancários e a chave PIX da empresa
 * num arquivo que não se desfaz. O formato 'link' mantém os cargos de sempre.
 */
export const CARGOS_DO_PDF_AO_CLIENTE: Role[] = ["admin", "financial", "seller"];

/**
 * Formato e cargo do envio ao cliente — a MESMA checagem no gancho `preValidar` (antes de a
 * pendência nascer, para o dono não aprovar no sino um pedido que vai falhar) e no `execute`
 * (depois do "sim").
 *
 * Cargo: o de quem PEDIU (gravado na pendência, ver gravarSolicitante) e o de quem executa
 * têm de poder mandar o PDF (cargosQueContam, em registry.ts). Sem isto, o admin que aprovasse
 * no painel a pendência de um vendedor externo mandaria o PDF com o cargo dele.
 */
export function validarPedidoDeEnvio(
  args: Record<string, unknown> | null | undefined,
  ctx: Pick<ToolCtx, "userRole" | "userId">,
): ({ error: string } & Record<string, unknown>) | null {
  const formato = formatoDoEnvio(args);
  if (!formato) return { error: `Formato "${String(args?.formato)}" não existe. Use 'pdf_e_link' (padrão) ou 'link'.` };
  if (formato !== "pdf_e_link") return null;
  if (cargosQueContam(args, ctx).every((c) => CARGOS_DO_PDF_AO_CLIENTE.includes(c as Role))) return null;
  const solicitante = lerSolicitante(args);
  const outraPessoaPediu = !!solicitante && solicitante.user_id !== ctx.userId &&
    !CARGOS_DO_PDF_AO_CLIENTE.includes(solicitante.cargo as Role);
  const quem = outraPessoaPediu ? `O cargo de quem pediu (${solicitante!.nome ?? "outro usuário"})` : "Seu cargo";
  return {
    error: `${quem} não manda o PDF ao cliente (o arquivo leva preço e dados de pagamento). Posso mandar só o link, com formato 'link' — é um envio novo e pede nova confirmação.`,
    alternativa: "formato 'link'",
    nada_enviado: true,
  };
}

/** "••••1234" — o dono reconhece o número pelo final; o resumo não expõe o telefone inteiro. */
export function mascararTelefone(telefone: unknown): string {
  const digitos = String(telefone ?? "").replace(/\D/g, "");
  return digitos.length >= 4 ? `••••${digitos.slice(-4)}` : "••••";
}

const CAMPOS_DA_ORDEM_PARA_ENVIO = "id, service_order_number, share_token, client_id, status, grand_total, quote_status";

/** Acha a ordem pelo UUID ou pelo número (ORÇ-00086 / OS-00075 / formato antigo). */
// deno-lint-ignore no-explicit-any
async function buscarOrdemParaEnvio(admin: any, idOuNumero: unknown) {
  const valor = String(idOuNumero ?? "");
  let q = admin.from("service_orders").select(CAMPOS_DA_ORDEM_PARA_ENVIO);
  q = UUID_RE.test(valor) ? q.eq("id", valor) : q.eq("service_order_number", valor);
  return await q.maybeSingle();
}

/**
 * Resumo da confirmação de send_service_order_link (painel e "sim <PIN>" no WhatsApp).
 *
 * Até 26/09/2026 o resumo era a lista crua dos argumentos: "OS/Orçamento: ORÇ-00086". O dono
 * dava o PIN sem ver PARA QUEM ia, em que número e com que valor — e agora o padrão manda um
 * arquivo com preço e PIX, que não se desfaz. O "sim" tem de ser sobre o que vai sair de fato:
 * cliente, telefone (mascarado), número, total e formato. O telefone é o do cadastro, que é o
 * único destino que a tool aceita.
 *
 * null = não achou a ordem; quem chama cai no resumo genérico.
 */
// deno-lint-ignore no-explicit-any
export async function resumirEnvioAoCliente(admin: any, args: Record<string, unknown>): Promise<string | null> {
  const { data: so } = await buscarOrdemParaEnvio(admin, args?.service_order_id);
  if (!so) return null;
  const { data: c } = so.client_id
    ? await admin.from("clients").select("name, display_name, whatsapp, phone, opt_out_whatsapp").eq("id", so.client_id).maybeSingle()
    : { data: null };
  const formato = formatoDoEnvio(args as { formato?: unknown });
  const rotulo = documentTypeFor(so.status) === "quote" ? "Orçamento" : "Ordem de Serviço";
  const telefone = c?.whatsapp || c?.phone;
  const linhas = [
    `Cliente: *${c?.name || "—"}*`,
    telefone ? `WhatsApp: ${mascararTelefone(telefone)} (do cadastro)` : "WhatsApp: ⚠️ cliente sem WhatsApp/telefone no cadastro — o envio vai falhar",
    `${rotulo}: *${so.service_order_number}* — Total *${fmtCurrency(Number(so.grand_total) || 0)}*`,
    formato === "link"
      ? "Formato: *só o link* (para ver online e aprovar)"
      : formato === "pdf_e_link"
      ? "Formato: *PDF anexado + link* (o arquivo com preço e PIX vai na conversa)"
      : `Formato: ⚠️ "${String(args?.formato)}" não existe — o envio será recusado`,
  ];
  if (typeof args?.custom_message === "string" && args.custom_message.trim()) {
    linhas.push(`Mensagem: "${args.custom_message.trim().slice(0, 200)}"`);
  }
  if (so.status === "cancelled") linhas.push("⚠️ A ordem está CANCELADA — o envio será recusado.");
  // Em 26/09/2026, 41 dos 51 orçamentos estavam 'rejected' — a maioria vencida pela rotina
  // quote-reminders. O PDF sai com a validade ORIGINAL, já passada: o dono tem de ver isso
  // antes do "sim" (não bloqueia: reenviar um vencido para reabrir a conversa é legítimo).
  if (so.status === "draft" && so.quote_status === "rejected") {
    linhas.push("⚠️ Este orçamento está RECUSADO/VENCIDO no funil: o PDF sai com a validade original, já vencida.");
  }
  if (c?.opt_out_whatsapp) linhas.push("⚠️ O cliente pediu para não receber WhatsApp (opt-out) — o envio será recusado.");
  return linhas.join("\n");
}

/**
 * O PDF não saiu: NADA foi ao cliente. O caminho de volta é mandar só o link — um envio novo,
 * com nova confirmação. Trocar o formato sozinho mandaria ao cliente algo que o dono não
 * aprovou.
 *
 * A oferta vai DENTRO do `error`, não só em `orientacao`: depois do "sim" (painel ou
 * "sim <PIN>" no WhatsApp) quem fala com o dono é o ai-agent, sem o modelo, e ele mostra só
 * "⚠️ <título> — falhou: <error>".
 */
function anexoFalhou(motivo: string) {
  return {
    error: `O PDF não foi anexado (${motivo}). Nada foi enviado ao cliente. Se quiser, mando só o link — é um envio novo e pede nova confirmação.`,
    nada_enviado: true,
    alternativa: "mandar só o link (formato 'link')",
    orientacao:
      "Diga ao usuário que o anexo do PDF falhou e que NADA foi enviado ao cliente — não diga que mandou. Ofereça mandar só o link: se ele aceitar, chame send_service_order_link de novo com formato='link' (é um envio novo e pede nova confirmação). Não troque o formato por conta própria.",
  };
}

/**
 * Usa a edge function whatsapp-send (não whatsapp-send-text) para respeitar
 * wa_test_mode/wa_test_number do app_settings.
 */
export async function sendWhatsapp(phone: string, message: string, jwt: string, dedupeKey?: string) {
  const r = await postarWhatsappSend({ phone, message, kind: "text", ...(dedupeKey ? { dedupe_key: dedupeKey } : {}) }, jwt);
  const data = await r.json().catch(() => ({}));
  if (!r.ok) return { error: (data as any).error || `HTTP ${r.status}` };
  if ((data as any).deduplicated) {
    // A edge reconheceu a chave: esta mesma mensagem já saiu hoje para este número.
    return { ok: true, messageId: null, deduplicated: true, aviso: "Esta mesma mensagem já tinha sido enviada hoje para este número; não reenviei." };
  }
  return { ok: true, messageId: (data as any).messageId };
}

export const whatsappTools: ToolDef[] = [
  {
    name: "send_whatsapp_message",
    description: "Envia mensagem de WhatsApp via Evolution API. Forneça to_phone OU client_id (busca o WhatsApp/telefone do cliente).",
    input_schema: {
      type: "object",
      properties: {
        to_phone: { type: "string" },
        client_id: { type: "string" },
        message: { type: "string" },
      },
      required: ["message"],
    },
    // "pior caso" para o filtro por cargo — o risco real depende do destinatário.
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    computeRisk: (args) => (args?.client_id ? "high" : "medium"),
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb, jwt } = ctx;
      let phone = args.to_phone;
      if (!phone && args.client_id) {
        const { data: c } = await sb.from("clients").select("whatsapp, phone").eq("id", args.client_id).maybeSingle();
        phone = c?.whatsapp || c?.phone;
      }
      if (!phone) return { error: "Telefone não fornecido nem encontrado para o cliente." };
      // Idempotência: mesmo texto, mesmo número, mesmo dia = um envio (protege contra o
      // laço do agente repetir a tool após um timeout).
      const chave = chaveDeEnvio("agente-msg", String(phone).replace(/\D/g, ""), diaLocal(), hashCurto(String(args.message)));
      return await sendWhatsapp(phone, args.message, jwt, chave);
    },
  },
  {
    name: "send_supplier_quote_request",
    description:
      // O passo a passo do ciclo (ler resposta -> registrar preço -> comparar -> aplicar ->
      // gerar OC) vivia aqui E na seção COTAÇÃO A FORNECEDORES do system prompt. Uma cópia
      // basta, e o lugar do workflow é o prompt — descrição de tool é contrato.
      "Envia um pedido de COTAÇÃO por WhatsApp a um ou mais FORNECEDORES (ação sensível — pede confirmação). Informe supplier_ids (ache com suggest_suppliers) e os itens a cotar. MOSTRE a prévia da mensagem e a lista de fornecedores antes de confirmar. O envio é o começo do ciclo de cotação, não o fim.",
    input_schema: {
      type: "object",
      properties: {
        supplier_ids: { type: "array", items: { type: "string" }, description: "UUIDs dos fornecedores (de suggest_suppliers/create_supplier)." },
        items: {
          type: "array",
          description: "Itens a cotar.",
          items: {
            type: "object",
            properties: { description: { type: "string" }, quantity: { type: "number" } },
            required: ["description"],
          },
        },
        notes: { type: "string", description: "Observação opcional que VAI na mensagem (ex.: condição de pagamento). NÃO use para prazo (quem define é o fornecedor, só se ele perguntar) nem para descrever a aplicação/'pra que serve' (confunde quem atende)." },
        quote_request_id: { type: "string", description: "UUID de uma cotação criada com create_quote_request. FORMA PREFERIDA: manda o código COT-XXXXX e os itens numerados, o que faz a resposta do fornecedor voltar interpretável." },
      },
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb, admin, jwt }) {
      let supplierIds: string[] = Array.isArray(args.supplier_ids) ? args.supplier_ids : [];
      let items: any[] = Array.isArray(args.items) ? args.items : [];
      let codigo = "";

      // Caminho preferido: a cotação já existe → usa código + itens numerados dela.
      if (args.quote_request_id) {
        const { data: req } = await sb
          .from("quote_requests")
          .select("id, code, sent_supplier_ids, notes")
          .eq("id", args.quote_request_id)
          .maybeSingle();
        if (!req) return { error: "Cotação não encontrada." };
        const { data: qItems } = await sb
          .from("quote_request_items")
          .select("position, description, quantity")
          .eq("quote_request_id", req.id)
          .order("position", { ascending: true });
        codigo = req.code;
        if (supplierIds.length === 0) supplierIds = (req.sent_supplier_ids as string[]) || [];
        items = (qItems || []).map((i: any) => ({ position: i.position, description: i.description, quantity: Number(i.quantity) }));
        // req.notes fica INTERNO de propósito: aplicação ("pra que serve") e prazo NÃO vão na
        // mensagem ao fornecedor — descrever a aplicação confunde quem atende, e o prazo quem
        // define é o fornecedor. Só um args.notes explícito (ex.: condição de pagamento) é enviado.
      }

      if (supplierIds.length === 0) return { error: "Informe ao menos um fornecedor (supplier_ids) ou uma cotação com fornecedores." };
      if (items.length === 0) return { error: "Informe ao menos um item para cotar." };

      const { data: comp } = await sb.from("app_settings").select("value").eq("key", "company_name").maybeSingle();
      const company = comp?.value || "nossa empresa";
      const { data: suppliers } = await sb.from("suppliers").select("id, name, trade_name, phone, opt_out_whatsapp").in("id", supplierIds);
      const byId: Record<string, any> = Object.fromEntries((suppliers || []).map((s: any) => [s.id, s]));
      // Itens NUMERADOS: é o que faz o fornecedor responder "1 - R$ 850 - 5 dias".
      const itemLines = items
        .map((it, i) => `${it.position ?? i + 1}. ${it.quantity ? `${it.quantity}x ` : ""}${it.description ?? ""}`.trimEnd())
        .join("\n");

      const resultados: Array<{ fornecedor: string; status: string }> = [];
      const avisos = new Set<string>();
      for (const sid of supplierIds) {
        const sup = byId[sid];
        if (!sup) { resultados.push({ fornecedor: sid, status: "não encontrado" }); continue; }
        const nomeForn = sup.trade_name || sup.name || sid;
        if (sup.opt_out_whatsapp) { resultados.push({ fornecedor: nomeForn, status: "opt-out (não receber)" }); continue; }
        if (!sup.phone) { resultados.push({ fornecedor: nomeForn, status: "sem WhatsApp cadastrado" }); continue; }
        // Mensagem ENXUTA de propósito: saudação neutra (sem razão social, que às vezes é
        // genérica) + itens numerados. Sem descrever a aplicação, sem estipular prazo e sem
        // ensinar o fornecedor a responder — ele responde pela lista. (Ver feedback do dono.)
        const msg =
          `Olá, tudo bem? Aqui é da ${company}.\n` +
          `Gostaríamos de uma cotação${codigo ? ` (${codigo})` : ""}:\n${itemLines}` +
          `${args.notes ? `\n\n${args.notes}` : ""}\n\n` +
          `Obrigado!`;
        // Portão de comunicação: conformidade (bloqueia) + estilo (avisa).
        const g = guardaDeEnvio(msg, { tipo: "cotacao", audiencia: "fornecedor", canal: "whatsapp", destinatarioIdentificado: true });
        if (g.bloqueado) {
          resultados.push({ fornecedor: nomeForn, status: `bloqueado: ${g.motivo}` });
          await registrarEnvio(admin, { tipo: "cotacao", audiencia: "fornecedor", entityKind: "supplier", entityId: sid, phone: sup.phone, preview: msg, status: "blocked", blockCode: g.codigoBloqueio });
          continue;
        }
        g.avisos.forEach((a) => avisos.add(a));
        const r = await sendWhatsapp(sup.phone, msg, jwt, chaveDeEnvio("cotacao", codigo || hashCurto(itemLines), sid, diaLocal()));
        resultados.push({ fornecedor: nomeForn, status: r.ok ? (r.deduplicated ? "já enviado hoje" : "enviado") : `falhou: ${r.error}` });
        await registrarEnvio(admin, { tipo: "cotacao", audiencia: "fornecedor", entityKind: "supplier", entityId: sid, phone: sup.phone, preview: msg, status: r.ok ? "sent" : "failed" });
      }
      const enviados = resultados.filter((r) => r.status === "enviado").length;
      return { ok: true, cotacao: codigo || null, enviados, total: supplierIds.length, resultados, ...(avisos.size ? { avisos_estilo: [...avisos] } : {}) };
    },
  },
  {
    name: "send_collection_reminder",
    description: "Envia um lembrete de cobrança por WhatsApp para o contato da cobrança.",
    input_schema: {
      type: "object",
      properties: { collection_id: { type: "string" }, custom_message: { type: "string" } },
      required: ["collection_id"],
    },
    // Sempre envia pro contato da cobrança — sempre cliente, nunca equipe.
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb, admin, jwt } = ctx;
      const { data: col, error } = await sb
        .from("collections")
        .select("id, amount, due_date, contact_whatsapp, phone, contact_name, client_id, description")
        .eq("id", args.collection_id)
        .maybeSingle();
      if (error || !col) return { error: "Cobrança não encontrada" };
      // D21 (dono, 17/09/2026): piso de materialidade — abaixo dele não se cobra por mensagem.
      const { data: cfgPiso } = await admin.from("app_settings").select("value").eq("key", "collection_min_amount").maybeSingle();
      const piso = Number((cfgPiso as { value?: string } | null)?.value) || 0;
      if (piso > 0 && Number(col.amount) < piso) {
        return { error: `Cobrança de R$ ${Number(col.amount).toFixed(2)} fica abaixo do piso de R$ ${piso} (Configurações): só listar, não cobrar por WhatsApp.` };
      }
      // Perfil do contato: nome usado (display_name) e opt-out.
      let c: any = null;
      if (col.client_id) {
        const r = await sb.from("clients").select("whatsapp, phone, name, display_name, opt_out_whatsapp").eq("id", col.client_id).maybeSingle();
        c = r.data;
      }
      if (c?.opt_out_whatsapp) return { error: "Este cliente pediu para não receber mensagens no WhatsApp (opt-out). Cobre por outro canal." };
      const phone = col.contact_whatsapp || col.phone || c?.whatsapp || c?.phone;
      if (!phone) return { error: "Sem telefone para enviar o lembrete." };
      const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(col.amount);
      const nomeUsado = c?.display_name || col.contact_name || (c?.name ? String(c.name).trim().split(/\s+/)[0] : "");
      const msg =
        args.custom_message ||
        `Olá${nomeUsado ? ` ${nomeUsado}` : ""}, lembrete amigável: você possui um valor de ${fmt} com vencimento em ${col.due_date}. Qualquer dúvida estamos à disposição.`;
      // Portão: conformidade (horário, número identificado) bloqueia; estilo (ameaça) avisa.
      const g = guardaDeEnvio(msg, { tipo: "cobranca", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: !!col.client_id, texto: msg });
      if (g.bloqueado) {
        await registrarEnvio(admin, { tipo: "cobranca", audiencia: "cliente", entityKind: "client", entityId: col.client_id, phone, preview: msg, status: "blocked", blockCode: g.codigoBloqueio });
        return { error: g.motivo };
      }
      const r = await sendWhatsapp(phone, msg, jwt, chaveDeEnvio("cobranca", col.id, diaLocal()));
      if (r.ok && !r.deduplicated) {
        await admin.from("collections").update({ last_auto_sent_at: new Date().toISOString() }).eq("id", col.id);
      }
      await registrarEnvio(admin, { tipo: "cobranca", audiencia: "cliente", entityKind: "client", entityId: col.client_id, phone, preview: msg, status: r.ok ? "sent" : "failed" });
      return { ...r, ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}) };
    },
  },
  {
    name: "send_service_order_link",
    description:
      "Envia um orçamento/OS AO CLIENTE pelo WhatsApp, sempre para o WhatsApp/telefone do cadastro do cliente (não existe campo de telefone). Use sempre que o usuário pedir 'enviar orçamento', 'mandar OS', 'enviar para o cliente' etc. PADRÃO (formato='pdf_e_link'): o ARQUIVO PDF, igual ao botão Baixar, com o total e o link para ver online e aprovar na legenda. formato='link' manda só o link, em texto — use apenas quando o usuário pedir 'só o link' ou quando o PDF falhar e ele aceitar. Vendedor externo só pode formato='link'. O campo service_order_id aceita TANTO o UUID (campo 'id' do list_service_orders) QUANTO o número do documento (ex: 'ORÇ-00001' para orçamentos, 'OS-00042' para OS, ou o formato antigo 'OS-2026-XXXXX'). Prefira sempre o UUID.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID (campo id) ou número da OS (campo numero, ex: OS-2026-152542)" },
        formato: {
          type: "string",
          enum: ["pdf_e_link", "link"],
          description: "pdf_e_link (padrão) = arquivo PDF com o link na legenda; link = só o link em texto, quando o usuário pedir.",
        },
        custom_message: { type: "string", description: "Mensagem personalizada. No formato link substitui o texto padrão; no pdf_e_link vira a primeira linha da legenda (número, total e link vêm sempre)." },
      },
      required: ["service_order_id"],
    },
    // Sempre envia pro cliente dono da OS — sempre cliente, nunca equipe. Sem computeRisk de
    // propósito: nenhum argumento torna isto "baixo risco", e o PDF nunca roda sem o "sim"
    // (ver NEVER_AUTONOMOUS_WHEN em autonomy-policy.ts).
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    // Formato inexistente e PDF pedido por vendedor externo são recusados ANTES de a pendência
    // nascer: o sino não mostra "PDF anexado" para um pedido que o execute vai recusar.
    preValidar: (args, ctx) => validarPedidoDeEnvio(args, ctx),
    // A pendência grava quem pediu: o execute revalida o cargo DELE, não o de quem aprova.
    gravarSolicitante: true,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      // Antes de ler qualquer coisa: o PDF leva preço e PIX, e o vendedor externo não manda —
      // nem pela mão de um admin que aprove a pendência dele (validarPedidoDeEnvio).
      const recusado = validarPedidoDeEnvio(args, ctx);
      if (recusado) return recusado;
      const formato = formatoDoEnvio(args)!;
      const { admin, jwt, appOrigin, settings } = ctx;
      const { data: so, error: soErr } = await buscarOrdemParaEnvio(admin, args.service_order_id);
      if (soErr || !so) return { error: `OS não encontrada. Verifique se o número ou ID está correto. Valor recebido: "${args.service_order_id}"` };
      if (so.status === "cancelled") {
        return { error: `A ordem ${so.service_order_number} está CANCELADA: não se manda ao cliente. Se ela voltou a valer, reabra antes (reopen_service_order).` };
      }
      if (!so.share_token) return { error: `A OS ${so.service_order_number} não possui link público ainda. Abra a OS no app, clique em "Compartilhar" para gerar o link, e tente novamente.` };
      // Destino: SÓ o cadastro do cliente da ordem. Nenhum telefone dos argumentos é lido —
      // é o que garante que o arquivo com preço e PIX vai para quem é dono do orçamento.
      const { data: c } = await admin.from("clients").select("whatsapp, phone, name, display_name, opt_out_whatsapp").eq("id", so.client_id).maybeSingle();
      if (c?.opt_out_whatsapp) return { error: "Este cliente pediu para não receber mensagens no WhatsApp (opt-out)." };
      const phone = c?.whatsapp || c?.phone;
      if (!phone) return { error: "Cliente sem WhatsApp/telefone cadastrado." };
      const origin = appOrigin || settings.app_public_url || "https://marineflow-erp.vercel.app";
      const link = `${origin}/view/${so.share_token}`;
      const nomeUsado = c?.display_name || (c?.name ? String(c.name).trim().split(/\s+/)[0] : "");
      // 'quote' só para orçamento: é o que deixa o whatsapp-send marcar 'sent' (e ele ainda
      // confere destino, modo de teste e status). OS vai como 'service_order' — só o vínculo.
      const contexto = documentTypeFor(so.status) === "quote" ? "quote" as const : "service_order" as const;
      const digitos = String(phone).replace(/\D/g, "");
      // Modo de teste: o whatsapp-send desvia o envio para o número de teste (e aí não marca o
      // orçamento como enviado). Entra nas chaves anti-duplicado: sem isso, o envio de teste
      // reservava a chave do CLIENTE e, desligado o modo no mesmo dia, o envio de verdade ouvia
      // "já foi enviado hoje" — sem o cliente ter recebido nada. Fora do desvio a parte some
      // (chaveDeEnvio descarta null) e a chave é a mesma de sempre.
      // A pergunta é "a edge VAI desviar?", não "o interruptor está ligado?": ligado sem número
      // de teste a edge manda ao cliente — a chave tem de ser a do cliente e o resultado não
      // pode dizer "foi para o teste". Por isso a mesma função da edge (marcar-enviado.ts).
      const modoTeste = desviadoPorTeste(settings);
      const marcaDeTeste = modoTeste ? "teste" : null;

      if (formato === "link") {
        const msg = args.custom_message || `Olá${nomeUsado ? ` ${nomeUsado}` : ""}, segue o link da OS ${so.service_order_number}: ${link}`;
        const g = guardaDeEnvio(msg, { tipo: "os_link", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: !!so.client_id });
        if (g.bloqueado) {
          await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: msg, status: "blocked", blockCode: g.codigoBloqueio });
          return { error: g.motivo };
        }
        const envio = await enviarOrdemAoCliente({
          phone,
          serviceOrderId: so.id,
          context: contexto,
          jwt,
          dedupeKey: chaveDeEnvio("os-link", so.id, digitos, diaLocal(), marcaDeTeste),
          conteudo: { kind: "text", message: msg },
        });
        // Mesmo formato de resposta de antes (sendWhatsapp), para o modelo ler igual.
        const r = !envio.ok
          ? { error: envio.error }
          : envio.deduplicated
          ? { ok: true, messageId: null, deduplicated: true, aviso: "Esta mesma mensagem já tinha sido enviada hoje para este número; não reenviei." }
          : { ok: true, messageId: envio.messageId ?? null };
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: msg, status: envio.ok ? "sent" : "failed" });
        return { ...r, ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}) };
      }

      // ── formato 'pdf_e_link': o arquivo do Baixar, com o link na legenda ──────────────
      const montado = await montarDocumentoDaOrdem(admin, so, settings);
      if (!montado.ok) {
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `[pdf+link] não gerado: ${montado.motivo}`, status: "failed" });
        return anexoFalhou(montado.motivo);
      }
      const doc = montado.doc;
      const abertura = typeof args.custom_message === "string" && args.custom_message.trim()
        ? args.custom_message.trim()
        : `Olá${nomeUsado ? ` ${nomeUsado}` : ""}, segue ${doc.tipoDoc === "quote" ? "o orçamento" : "a ordem de serviço"} em PDF.`;
      // Número, total e link vêm SEMPRE, mesmo com mensagem personalizada: o dono aprovou o
      // envio vendo esses três no resumo da confirmação.
      const legenda = `${abertura}\n\n${doc.rotulo} ${doc.numero} — Total ${doc.total}\nPara ver online e aprovar: ${link}`;
      // O whatsapp-send recusa legenda acima de 1024 caracteres (zod). Melhor dizer agora do
      // que gerar o PDF e ouvir um 400.
      if (legenda.length > 1024) return { error: "A mensagem personalizada ficou longa demais para a legenda do PDF (limite do WhatsApp). Encurte e tente de novo." };
      // Portão de comunicação ANTES de gerar o arquivo: fora da janela 8h–20h não adianta renderizar.
      const g = guardaDeEnvio(legenda, { tipo: "os_link", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: !!so.client_id });
      if (g.bloqueado) {
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `[pdf+link] ${legenda}`, status: "blocked", blockCode: g.codigoBloqueio });
        return { error: g.motivo };
      }

      // Anti-duplicado pelo CONTEÚDO do documento, não por updated_at: o mesmo PDF para o mesmo
      // número no mesmo dia sai uma vez só (o laço do agente repetindo a tool depois de um
      // tempo esgotado não manda dois arquivos ao cliente). Mudou item, valor ou validade, o
      // conteúdo muda e o envio passa. O carimbo "Emitido em" fica fora da conta.
      const chave = chaveDeEnvio("os-pdf", so.id, digitos, diaLocal(), impressaoDigitalDoDocumento(doc.html), marcaDeTeste);
      const entrega = await guardarEEntregar({
        admin,
        doc,
        shareToken: so.share_token,
        baseUrl: settings.app_public_url || "",
        rotuloDoLog: "send_service_order_link",
        entregar: (url) =>
          enviarOrdemAoCliente({
            phone,
            serviceOrderId: so.id,
            context: contexto,
            jwt,
            dedupeKey: chave,
            conteudo: { kind: "document", url, filename: doc.nomeDoArquivo, caption: legenda },
          }),
      });
      if (!entrega.ok) {
        // Renderizar, guardar ou assinar falhou: `entregar` nem foi chamado — nada saiu.
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `[pdf+link] não gerado: ${entrega.motivo}`, status: "failed" });
        return anexoFalhou(entrega.motivo);
      }
      const envio = entrega.valor;
      if (!envio.ok) {
        // Libera a chave SÓ quando não houve resposta definitiva (25 s esgotados, rede): a edge
        // reservou a chave antes de chamar a Evolution e, com a tool tendo desistido no meio, a
        // reserva ficaria de pé — o próximo pedido ouviria "já enviado" sem nada entregue. Um
        // PDF repetido ao cliente é o erro menor.
        // Com resposta definitiva, NÃO mexe: 400/401/500 a edge devolve ANTES de reservar — a
        // chave, se existe, é de um envio anterior JÁ CONCLUÍDO, e apagá-la abriria a porta
        // para mandar o mesmo PDF de novo; no 502 a própria edge já liberou.
        if (envio.semResposta) await liberarEnvio(admin, chave).catch(() => {});
        await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `[pdf+link] ${legenda}`, status: "failed" });
        if (envio.semResposta) {
          return {
            error: `O WhatsApp não confirmou o envio do PDF (${envio.error}): pode ter chegado ou não. Confira a conversa do cliente antes de reenviar.`,
            orientacao:
              "Diga que o envio não foi confirmado. Antes de oferecer reenviar, confira a conversa do cliente (get_whatsapp_conversation) para ver se o PDF chegou; se não chegou, ofereça reenviar ou mandar só o link (formato='link') — os dois pedem nova confirmação.",
          };
        }
        return anexoFalhou(`o WhatsApp recusou o envio: ${envio.error}`);
      }
      const rotuloDoc = `${doc.rotulo} ${doc.numero}`;
      if (envio.deduplicated) {
        return { ok: true, deduplicated: true, aviso: `Este mesmo PDF (${rotuloDoc}) já foi enviado hoje para este cliente; não reenviei.` };
      }
      await registrarEnvio(admin, { tipo: "os_link", audiencia: "cliente", entityKind: "service_order", entityId: so.id, phone, preview: `[pdf+link] ${legenda}`, status: "sent" });
      // Modo de teste (calculado lá em cima): dizer "chegou ao cliente" seria fingir.
      // Sem URL e sem token no resultado: ele fica gravado no histórico do agente.
      return {
        ok: true,
        formato: "pdf_e_link",
        enviado_para: modoTeste ? "o número de TESTE do WhatsApp (modo de teste ligado), não o cliente" : `o WhatsApp do cliente (${mascararTelefone(phone)})`,
        documento: rotuloDoc,
        cliente: doc.cliente,
        total: doc.total,
        arquivo: doc.nomeDoArquivo,
        observacao: modoTeste
          ? "O modo de teste do WhatsApp está ligado: o PDF foi para o número de teste, NÃO para o cliente. Diga isso."
          : "O cliente recebeu o PDF com o link para ver online e aprovar.",
        ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}),
      };
    },
  },
  {
    name: "schedule_whatsapp_message",
    description:
      "Agenda uma mensagem WhatsApp para ser enviada em data/hora específica. Use para 'agendar envio', 'mandar amanhã', 'lembrete automático' etc. Para envios com link de OS, informe service_order_id.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone do destinatário com DDI+DDD (ex: 5547999999999). Obrigatório se não informar client_id." },
        client_id: { type: "string", description: "UUID do cliente — busca o WhatsApp/telefone automaticamente." },
        message: { type: "string", description: "Texto da mensagem a ser enviada." },
        scheduled_at: { type: "string", description: "Data e hora do envio em ISO 8601 (ex: 2026-05-10T09:00:00)." },
        recurrence_type: { type: "string", enum: ["once", "daily", "weekly", "monthly"], description: "Recorrência do envio. Padrão: once." },
        service_order_id: { type: "string", description: "UUID ou número da OS para envio de link (send_mode=link)." },
        send_mode: { type: "string", enum: ["text", "link"], description: "Modo de envio. Padrão: text. Use 'link' para enviar o link público de uma OS." },
      },
      required: ["message", "scheduled_at"],
    },
    // "pior caso" para o filtro por cargo — client_id/service_order_id indicam cliente.
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    computeRisk: (args) => (args?.client_id || args?.service_order_id ? "high" : "medium"),
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb, admin, userId } = ctx;
      let phone = args.phone;
      const clientId = args.client_id || null;

      if (!phone && clientId) {
        const { data: c } = await sb.from("clients").select("whatsapp, phone").eq("id", clientId).maybeSingle();
        phone = c?.whatsapp || c?.phone;
      }
      if (!phone) return { error: "Telefone não informado. Forneça phone ou client_id." };

      let soId: string | null = null;
      if (args.service_order_id) {
        const isUUID = UUID_RE.test(String(args.service_order_id));
        if (isUUID) {
          soId = args.service_order_id;
        } else {
          const { data: so } = await admin.from("service_orders").select("id").eq("service_order_number", args.service_order_id).maybeSingle();
          soId = so?.id || null;
        }
      }

      const scheduledAt = new Date(args.scheduled_at).toISOString();
      const sendMode = args.send_mode || (soId ? "link" : "text");
      const recurrenceType = args.recurrence_type || "once";

      const { data: created, error: insErr } = await admin
        .from("whatsapp_scheduled_sends")
        .insert({
          phone: String(phone).replace(/\D/g, ""),
          message: args.message,
          scheduled_at: scheduledAt,
          next_run_at: scheduledAt,
          recurrence_type: recurrenceType,
          send_mode: sendMode,
          target_kind: soId ? "service_order" : "manual",
          service_order_id: soId,
          client_id: clientId,
          status: "pending",
          created_by: userId,
          auto_retry: true,
          max_attempts: 3,
        })
        .select()
        .single();

      if (insErr) return { error: insErr.message };
      return {
        ok: true,
        scheduled_id: created.id,
        phone: created.phone,
        scheduled_at: created.scheduled_at,
        recurrence_type: created.recurrence_type,
        message_preview: created.message.slice(0, 100),
      };
    },
  },
  {
    name: "list_scheduled_whatsapp",
    description: "Lista as mensagens WhatsApp agendadas. Pode filtrar por status.",
    input_schema: {
      type: "object",
      properties: {
        status: { type: "string", enum: ["pending", "sent", "failed", "cancelled", "all"], description: "Filtro de status. Padrão: pending." },
        limit: { type: "number", description: "Máximo de registros. Padrão: 10." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const status = args.status || "pending";
      const limit = Math.min(Number(args.limit) || 10, 30);

      let q = admin
        .from("whatsapp_scheduled_sends")
        .select("id, phone, message, status, next_run_at, recurrence_type, send_mode, last_error, client_id")
        .order("next_run_at", { ascending: true })
        .limit(limit);

      if (status !== "all") q = q.eq("status", status);

      const { data, error } = await q;
      if (error) return { error: error.message };
      return { results: data, count: data?.length ?? 0 };
    },
  },
  {
    name: "cancel_scheduled_whatsapp",
    description: "Cancela um agendamento de WhatsApp pelo ID.",
    input_schema: {
      type: "object",
      properties: { scheduled_id: { type: "string", description: "UUID do agendamento a cancelar." } },
      required: ["scheduled_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { error } = await admin.from("whatsapp_scheduled_sends").update({ status: "cancelled" }).eq("id", args.scheduled_id);
      if (error) return { error: error.message };
      return { ok: true, cancelled_id: args.scheduled_id };
    },
  },
  {
    // ÚNICA tool de WhatsApp SEM restrição de cargo, e é de propósito.
    // Decisão do dono (10/08/2026): o técnico não dispara nem agenda WhatsApp pelo
    // assistente — as outras oito ganharam NON_TECHNICIAN_ROLES. Esta ficou de fora
    // porque não fala com ninguém: busca o telefone do PRÓPRIO solicitante em app_users
    // pelo ctx.userId e agenda para ele mesmo. Não aceita client_id nem telefone livre,
    // então não há caminho para chegar a um cliente. É ferramenta de trabalho pessoal.
    name: "schedule_self_reminder",
    description:
      "LEMBRETE PARA O PRÓPRIO USUÁRIO (a pessoa que está falando com você), NUNCA para um cliente. Use SEMPRE que o pedido for 'me lembre', 'me avise', 'lembrete pra mim', 'não me deixe esquecer', 'me cutuca amanhã' etc. Agenda uma mensagem de WhatsApp para o número do próprio solicitante. NÃO use client_id, NÃO use schedule_whatsapp_message, NÃO peça confirmação — é uma ação interna e segura.",
    input_schema: {
      type: "object",
      properties: {
        message: {
          type: "string",
          description: "O texto que a pessoa vai receber. Escreva claro e amigável, já com a lista de pendências que ela pediu para lembrar (uma por linha).",
        },
        delay_minutes: {
          type: "number",
          description: "Para lembretes RELATIVOS ('daqui a X minutos/horas'): minutos a partir de AGORA (ex.: 'daqui a 3 min' → 3; 'em 2 horas' → 120). Use este campo nesses casos e NÃO calcule horário absoluto. Com delay_minutes, pode omitir scheduled_at.",
        },
        scheduled_at: {
          type: "string",
          description: "Para horário ABSOLUTO ('amanhã 8h', 'hoje 15h'): data/hora ISO 8601 no horário de Brasília (ex: 2026-07-19T08:00:00 — pode omitir o fuso, o sistema assume Brasília). 'bem cedo'/'de manhã' → 07:00; 'amanhã' sem hora → 08:00. NÃO use para 'daqui a X' (use delay_minutes).",
        },
        recurrence_type: {
          type: "string",
          enum: ["once", "daily", "weekly", "monthly"],
          description: "Recorrência do lembrete. Padrão: once (uma vez).",
        },
      },
      required: ["message"],
    },
    risk: "low",
    async execute(args, { admin, userId }) {
      let when: Date;
      if (args.delay_minutes != null && Number(args.delay_minutes) > 0) {
        // Lembrete relativo: o servidor calcula "agora + X" (sem conta de fuso pelo modelo).
        when = new Date(Date.now() + Number(args.delay_minutes) * 60000);
      } else {
        const raw = String(args.scheduled_at || "").trim();
        // Horário absoluto sem fuso (naive) → interpreta como Brasília (-03:00), não UTC.
        const hasTz = /[zZ]$|[+-]\d{2}:?\d{2}$/.test(raw);
        when = new Date(hasTz || !raw ? raw : `${raw}-03:00`);
      }
      if (isNaN(when.getTime())) return { error: "Data/hora do lembrete inválida. Informe delay_minutes (relativo) ou scheduled_at (absoluto)." };
      // Rede de segurança: se caiu no passado (ex.: erro de fuso), joga 1 min à frente em vez
      // de disparar imediatamente.
      if (when.getTime() < Date.now() - 30000) when = new Date(Date.now() + 60000);
      const { data: u } = await admin.from("app_users").select("phone_normalized, full_name").eq("id", userId).maybeSingle();
      const phone = (u?.phone_normalized || "").replace(/\D/g, "");
      if (!phone) {
        return { error: "Você ainda não tem um número de WhatsApp cadastrado para receber lembretes. Cadastre em Configurações → Usuários (aba IA/Zap)." };
      }
      // Envelope padronizado do lembrete (com nome, se houver) — evita mensagem crua/genérica.
      const firstName = String(u?.full_name || "").trim().split(/\s+/)[0] || "";
      const reminderText = firstName
        ? `⏰ *Lembrete, ${firstName}!*\n\n${args.message}`
        : `⏰ *Lembrete!*\n\n${args.message}`;
      const scheduledAt = when.toISOString();
      const { data: created, error } = await admin
        .from("whatsapp_scheduled_sends")
        .insert({
          phone,
          message: reminderText,
          scheduled_at: scheduledAt,
          next_run_at: scheduledAt,
          recurrence_type: args.recurrence_type || "once",
          send_mode: "text",
          target_kind: "self_reminder",
          status: "pending",
          created_by: userId,
          auto_retry: true,
          max_attempts: 3,
        })
        .select("id, scheduled_at, recurrence_type")
        .single();
      if (error) return { error: error.message };
      return {
        ok: true,
        reminder_id: created.id,
        scheduled_at: created.scheduled_at,
        recurrence_type: created.recurrence_type,
        message_preview: args.message.slice(0, 120),
      };
    },
  },
  {
    name: "list_unanswered_messages",
    description:
      "CAIXA DE ENTRADA — mensagens recebidas ainda NÃO respondidas. Use quando perguntarem quem mandou mensagem, o que chegou, quem está esperando resposta, ou pedirem o resumo do WhatsApp. Retorna os contatos cuja última mensagem recebida veio DEPOIS da última resposta enviada, com nome, há quanto tempo chegou, quantas não lidas, se é cliente vinculado ou outro contato, e uma prévia. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        since_hours: { type: "number", description: "Opcional: considerar só mensagens recebidas nas últimas N horas (ex.: 24 = 'hoje', 48). Sem valor = todas as pendentes." },
        limit: { type: "number", description: "Máximo de contatos a retornar. Padrão 15, teto 30." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const limit = Math.min(Math.max(Number(args.limit) || 15, 1), 30);
      const since = Number(args.since_hours) > 0
        ? new Date(Date.now() - Number(args.since_hours) * 3_600_000).toISOString()
        : null;
      // Fonte da verdade = whatsapp_messages (via RPC whatsapp_pending_inbox). NÃO usa o
      // cache whatsapp_leads, que pode congelar. Pendente = última entrada depois da
      // última saída, por telefone; exclui a equipe interna (IA no WhatsApp).
      const { data, error } = await admin.rpc("whatsapp_pending_inbox", { _since: since, _limit: limit });
      if (error) return { error: error.message };
      const rows = (data as any[]) || [];
      if (rows.length === 0) {
        return { ok: true, total: 0, pendentes: [], message: "Nenhuma mensagem pendente de resposta." };
      }
      const now = Date.now();
      const pendentes = rows.map((r: any) => {
        const mins = Math.max(0, Math.round((now - new Date(r.last_inbound_at).getTime()) / 60000));
        const ha = mins < 60 ? `${mins} min` : mins < 1440 ? `${Math.round(mins / 60)} h` : `${Math.round(mins / 1440)} d`;
        return {
          contato: r.contato,
          tipo: r.is_client ? "cliente" : "contato",
          ha,
          recebida_em: r.last_inbound_at,
          nao_lidas: r.unread_count || 0,
          previa: prettyPreview(r.last_body),
        };
      });
      return { ok: true, total: pendentes.length, pendentes };
    },
  },
  {
    name: "mute_contact",
    description:
      "SILENCIAR um contato na caixa de entrada / digest de mensagens. Use quando o usuário disser 'não me avise sobre X', 'silenciar fulano', 'esse contato não é relevante', 'pode ignorar a [empresa]', 'para de me lembrar do fornecedor Y'. O contato para de aparecer em 'quem está esperando resposta'. Informe phone (só dígitos) OU name (parte do nome). Baixo risco.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone do contato (só dígitos, DDI+DDD). Opcional se informar o nome." },
        name: { type: "string", description: "Nome (ou parte) do contato. Opcional se informar o telefone." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const phone = String(args.phone || "").replace(/\D/g, "");
      const name = String(args.name || "").trim();
      if (!phone && !name) return { error: "Diga o telefone ou o nome do contato a silenciar." };
      const nowIso = new Date().toISOString();
      if (phone) {
        const { data: existing } = await admin.from("whatsapp_leads").select("id, name, phone_normalized").eq("phone_normalized", phone);
        if (existing && existing.length > 0) {
          await admin.from("whatsapp_leads").update({ muted_at: nowIso }).in("id", existing.map((l: any) => l.id));
          return { ok: true, silenciados: existing.map((l: any) => l.name || l.phone_normalized) };
        }
        const { data: created, error } = await admin.from("whatsapp_leads")
          .insert({ phone_normalized: phone, name: name || null, status: "pending", muted_at: nowIso })
          .select("name, phone_normalized").single();
        if (error) return { error: error.message };
        return { ok: true, silenciados: [created.name || created.phone_normalized] };
      }
      const { data: matches } = await admin.from("whatsapp_leads").select("id, name, phone_normalized").ilike("name", `%${name}%`).limit(10);
      if (!matches || matches.length === 0) return { error: `Não encontrei nenhum contato com "${name}".` };
      if (matches.length > 1) {
        return { precisa_desambiguar: true, opcoes: matches.map((l: any) => ({ nome: l.name, phone: l.phone_normalized })), instrucao: "Pergunte ao usuário qual silenciar e chame de novo com o phone específico." };
      }
      await admin.from("whatsapp_leads").update({ muted_at: nowIso }).eq("id", matches[0].id);
      return { ok: true, silenciados: [matches[0].name || matches[0].phone_normalized] };
    },
  },
  {
    name: "unmute_contact",
    description:
      "REATIVAR um contato silenciado (volta a aparecer na caixa de entrada / digest). Use quando o usuário disser 'volte a me avisar sobre X', 'reativar fulano', 'tirar do silêncio'. Informe phone OU name.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone do contato (só dígitos). Opcional se informar o nome." },
        name: { type: "string", description: "Nome (ou parte) do contato. Opcional se informar o telefone." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const phone = String(args.phone || "").replace(/\D/g, "");
      const name = String(args.name || "").trim();
      if (!phone && !name) return { error: "Diga o telefone ou o nome do contato a reativar." };
      let q = admin.from("whatsapp_leads").select("id, name, phone_normalized").not("muted_at", "is", null);
      q = phone ? q.eq("phone_normalized", phone) : q.ilike("name", `%${name}%`);
      const { data: matches } = await q.limit(10);
      if (!matches || matches.length === 0) return { error: "Não encontrei contato silenciado com esse dado." };
      if (matches.length > 1) {
        return { precisa_desambiguar: true, opcoes: matches.map((l: any) => ({ nome: l.name, phone: l.phone_normalized })) };
      }
      await admin.from("whatsapp_leads").update({ muted_at: null }).eq("id", matches[0].id);
      return { ok: true, reativado: matches[0].name || matches[0].phone_normalized };
    },
  },
  {
    name: "link_whatsapp_lead_to_client",
    description:
      "VINCULAR um contato/lead do WhatsApp a um cliente cadastrado, para as mensagens dele passarem a aparecer no histórico do cliente. Use quando o usuário disser 'esse número é do fulano', 'liga esse contato ao cliente X', 'o lead tal é o cliente Y'. Informe o lead (telefone ou nome) e o cliente (id ou nome). Não cria cliente novo: se o cliente não existir, diga isso.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone do contato (só dígitos, DDI+DDD). Opcional se informar lead_name." },
        lead_name: { type: "string", description: "Nome (ou parte) do contato na caixa de entrada. Opcional se informar phone." },
        client_id: { type: "string", description: "Id do cliente. Opcional se informar client_name." },
        client_name: { type: "string", description: "Nome (ou parte) do cliente cadastrado. Opcional se informar client_id." },
      },
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const phone = String(args.phone || "").replace(/\D/g, "");
      const leadName = String(args.lead_name || "").trim();
      const clientId = String(args.client_id || "").trim();
      const clientName = String(args.client_name || "").trim();
      if (!phone && !leadName) return { error: "Diga o telefone ou o nome do contato a vincular." };
      if (!clientId && !clientName) return { error: "Diga o id ou o nome do cliente ao qual vincular." };

      let ql = admin.from("whatsapp_leads").select("id, name, phone_normalized, status, linked_client_id");
      ql = phone ? ql.eq("phone_normalized", phone) : ql.ilike("name", `%${leadName}%`);
      const { data: leads } = await ql.limit(10);
      if (!leads || leads.length === 0) return { error: "Não encontrei esse contato na caixa de entrada do WhatsApp." };
      if (leads.length > 1) {
        return { precisa_desambiguar: "contato", opcoes: leads.map((l: any) => ({ nome: l.name, phone: l.phone_normalized })) };
      }
      const lead = leads[0] as any;

      let qc = admin.from("clients").select("id, name, display_name, whatsapp, phone").eq("active", true);
      qc = UUID_RE.test(clientId) ? qc.eq("id", clientId) : qc.ilike("name", `%${clientName}%`);
      const { data: clientes } = await qc.limit(10);
      if (!clientes || clientes.length === 0) return { error: "Não encontrei esse cliente no cadastro. Se for cliente novo, cadastre antes de vincular." };
      if (clientes.length > 1) {
        return { precisa_desambiguar: "cliente", opcoes: clientes.map((c: any) => ({ id: c.id, nome: c.display_name || c.name })) };
      }
      const cliente = clientes[0] as any;

      if (lead.linked_client_id === cliente.id) {
        return { ok: true, ja_estava: true, contato: lead.name || lead.phone_normalized, cliente: cliente.display_name || cliente.name };
      }
      // Mesmo caminho da tela (useLinkLeadToClient): lead vira "linked" e as mensagens já
      // recebidas desse telefone passam a pertencer ao cliente.
      const { error: e1 } = await admin.from("whatsapp_leads")
        .update({ status: "linked", linked_client_id: cliente.id, updated_at: new Date().toISOString() })
        .eq("id", lead.id);
      if (e1) return { error: `Falha ao vincular: ${e1.message}` };
      const { count } = await admin.from("whatsapp_messages")
        .update({ client_id: cliente.id }, { count: "exact" })
        .eq("phone_normalized", lead.phone_normalized)
        .is("client_id", null);
      // Sem WhatsApp no cadastro, o telefone do contato vira o WhatsApp do cliente: é o que
      // faz o próximo envio ao cliente sair pelo número certo.
      if (!cliente.whatsapp && !cliente.phone) {
        await admin.from("clients").update({ whatsapp: lead.phone_normalized }).eq("id", cliente.id);
      }
      return {
        ok: true,
        contato: lead.name || lead.phone_normalized,
        cliente: cliente.display_name || cliente.name,
        mensagens_vinculadas: count ?? 0,
      };
    },
  },
];
