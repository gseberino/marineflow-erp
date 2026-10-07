// Tools: o assistente manda o PDF de uma NOTA FISCAL (DANFE da NF-e ou PDF da NFS-e) pelo
// WhatsApp — para quem pediu ("me manda o PDF da nota da OS-00098") e para o cliente ("envia a
// nota da OS-00105 para o cliente").
//
// Pedido do dono, aprovado em 07/10/2026. O caminho é o da tela Notas Fiscais
// (src/pages/FiscalEmission.tsx, handleSendToClient), peça por peça:
//   o arquivo        → o PDF que a própria emissão ARQUIVOU no bucket privado fiscal-xml
//                      (issued_fiscal_documents.pdf_storage_path, gravado por apply-status.ts) —
//                      é o mesmo DANFE/PDF do botão "PDF" da tela, sem passar pelo provedor;
//   o endereço       → URL assinada curta desse arquivo, que a Evolution baixa dentro do envio;
//   o envio          → edge whatsapp-send, kind=document (enviarDocumentoWhatsapp, o mesmo do
//                      PDF de orçamento), com context 'nfe' como a tela.
//
// Decisões que moram aqui:
//   · só nota AUTORIZADA e de PRODUÇÃO (homologação não tem valor fiscal; cancelada e rejeitada
//     não se mandam);
//   · só o ADMINISTRADOR — como a tela: Notas Fiscais é admin-only e a policy ifd_select de
//     issued_fiscal_documents só deixa o admin ler (pelo WhatsApp o assistente lê sem RLS);
//   · para si: sem confirmação, só para o telefone de quem pediu (do cadastro);
//   · para o cliente: risco alto, NUNCA autônomo, confirmação com a nota, o cliente e o telefone
//     inteiro; o destino é o WhatsApp do cadastro do cliente DA NOTA — nenhum telefone vem dos
//     argumentos;
//   · a frase do dono ("com a frase: segue a nota do serviço de ontem") vira a legenda inteira,
//     como no PDF de orçamento (formato 'pdf' de send_service_order_link).
//
// O arquivo NÃO é apagado depois: diferente do PDF de orçamento (gerado na hora e jogado fora),
// este é o arquivo da nota, guardado de propósito.

import { blockTechnician, cargosQueContam, lerRetrato, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { enviarDocumentoWhatsapp, mascararTelefone } from "./whatsapp.ts";
import { localizarOrdem } from "./documentos-pdf.ts";
import { escolherPorNome } from "./caixa.ts";
import { telefoneLegivel, telefoneParaEnvio } from "./agendamento.ts";
import { guardaDeEnvio } from "../comms/send-guard.ts";
import { registrarEnvio } from "../comms/send-log.ts";
import { chaveDeEnvio, diaLocal, hashCurto, liberarEnvio } from "../../whatsapp/idempotencia.ts";
import { desviadoPorTeste } from "../../whatsapp/marcar-enviado.ts";
import { limitarNomeDoArquivo, VALIDADE_DA_URL_S } from "../../pdf/gerar-e-guardar.ts";

/** Quem manda nota: só o admin, como a tela Notas Fiscais e a policy de leitura das notas. */
export const CARGOS_DA_NOTA: Role[] = ["admin"];
/** Bucket privado onde a emissão arquiva o XML e o PDF da nota (apply-status.ts). */
export const BUCKET_DA_NOTA = "fiscal-xml";
/** O mesmo `context` do botão "Enviar ao cliente por WhatsApp" da tela. Nunca 'quote'. */
export const CONTEXTO_DA_NOTA_AO_CLIENTE = "nfe";
/** Para quem pediu: não é envio ao cliente. */
export const CONTEXTO_DA_NOTA_PROPRIA = "agente_nota_propria";
/** O whatsapp-send recusa legenda acima de 1024 caracteres; a frase do dono fica um pouco abaixo. */
export const LIMITE_DA_FRASE = 1000;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CAMPOS_DA_NOTA =
  "id, document_type, origin_type, origin_id, client_id, environment, series, number, status, pdf_storage_path, request_payload, authorized_at, created_at";

export type Nota = {
  id: string;
  document_type: string;
  origin_type: string | null;
  origin_id: string | null;
  client_id: string | null;
  environment: string;
  series: number | null;
  number: number | null;
  status: string;
  pdf_storage_path: string | null;
  // deno-lint-ignore no-explicit-any
  request_payload?: any;
  authorized_at: string | null;
  created_at: string | null;
};

const TIPO_ROTULO: Record<string, string> = { nfe: "NF-e", nfce: "NFC-e", nfse: "NFS-e" };
const STATUS_ROTULO: Record<string, string> = {
  draft: "rascunho", queued: "na fila", processing: "processando", authorized: "autorizada",
  rejected: "rejeitada", failed: "com falha", cancelled: "cancelada",
};

/** "NF-e 2/29" / "NFS-e 1/5" — como a tela escreve a nota. */
export function rotuloDaNota(n: Pick<Nota, "document_type" | "series" | "number">): string {
  return `${TIPO_ROTULO[n.document_type] ?? n.document_type} ${n.series ?? ""}/${n.number ?? "?"}`;
}

/** "nfe" / "nfse" a partir do que foi dito ("nota de serviço", "NFS-e", "danfe", "produto"). */
export function tipoDaNotaDito(bruto: unknown): "nfe" | "nfse" | null {
  const t = String(bruto ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  if (!t.trim()) return null;
  if (/nfs|servico/.test(t)) return "nfse";
  if (/nf-?e|nfe|danfe|produto|mercadoria|venda/.test(t)) return "nfe";
  return null;
}

/** Nome do arquivo como o "PDF" da tela baixa: "NF-e 29-2 CLIENTE.pdf" (buildArtifactFilename). */
export function nomeDoArquivoDaNota(n: Nota): string {
  const tipo = TIPO_ROTULO[n.document_type] ?? "NF-e";
  const cliente = String(n.request_payload?.recipient?.name || "")
    // deno-lint-ignore no-control-regex
    .replace(/[<>:"/\\|?*\x00-\x1f]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 40);
  return limitarNomeDoArquivo(`${`${tipo} ${n.number ?? ""}-${n.series ?? ""}${cliente ? " " + cliente : ""}`.trim()}.pdf`);
}

type Localizada = { nota: Nota; os: string | null } | { erro: string; opcoes?: string[] };

/** Nota que se manda: autorizada, de produção e com o PDF arquivado. */
function motivoParaNaoMandar(n: Nota): string | null {
  const r = rotuloDaNota(n);
  if (n.status !== "authorized") return `A ${r} está ${STATUS_ROTULO[n.status] ?? n.status} — só nota AUTORIZADA vai pelo WhatsApp.`;
  if (n.environment !== "producao") return `A ${r} é de HOMOLOGAÇÃO (teste, sem valor fiscal) — não se manda.`;
  if (!n.pdf_storage_path) {
    return `O PDF da ${r} ainda não foi arquivado no sistema. Na tela Notas Fiscais, use "Atualizar situação na SEFAZ" nessa nota (o sistema baixa o PDF) e peça de novo.`;
  }
  return null;
}

const ordenarRecentes = (xs: Nota[]) =>
  [...xs].sort((a, b) => String(b.authorized_at ?? b.created_at ?? "").localeCompare(String(a.authorized_at ?? a.created_at ?? "")));

/**
 * Acha a nota pelo que o dono disse: o número da OS ("a nota da OS-00098"), o número da nota
 * ("a nota 29", "2/29"), o cliente ("a última nota do Miguel" → a mais recente dele) ou "ultima".
 * `tipo` (nfe/nfse) desempata a OS que tem as duas notas.
 *
 * Nome nunca identifica por parecença: o cliente é procurado SÓ entre quem tem nota, pelo nome
 * igual ou cortado ("Nelson" acha "Nelson da Silva"); dois que servem → pergunta.
 */
// deno-lint-ignore no-explicit-any
export async function localizarNota(admin: any, args: Record<string, unknown>): Promise<Localizada> {
  const notaDita = String(args?.nota ?? "").trim();
  const osDita = String(args?.os ?? "").trim();
  const clienteDito = String(args?.cliente ?? "").trim();
  const tipo = tipoDaNotaDito(args?.tipo);
  const ultima = /^(a |o )?ultim[ao]\b/.test(notaDita.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase());

  if (!notaDita && !osDita && !clienteDito) {
    return { erro: "Diga qual nota: o número da OS (OS-00098), o número da nota (29 ou 2/29) ou o cliente." };
  }

  // 1) Pelo id: a nota exata.
  if (UUID_RE.test(notaDita)) {
    const { data, error } = await admin.from("issued_fiscal_documents").select(CAMPOS_DA_NOTA).eq("id", notaDita).maybeSingle();
    if (error) return { erro: `A consulta das notas falhou (${error.message}). Tente de novo.` };
    if (!data) return { erro: "Não achei nota com esse id." };
    const motivo = motivoParaNaoMandar(data as Nota);
    return motivo ? { erro: motivo } : { nota: data as Nota, os: null };
  }

  let candidatas: Nota[] = [];
  let osNumero: string | null = null;

  if (osDita) {
    // 2) Pela OS: as notas cuja origem é a ordem (mesmo localizador do PDF do orçamento).
    const achada = await localizarOrdem(admin, osDita, "os");
    if ("erro" in achada) return { erro: achada.erro };
    if ("opcoes" in achada) return { erro: `Há mais de um documento com esse número: ${achada.opcoes.join(" e ")}. Pergunte qual.`, opcoes: achada.opcoes };
    osNumero = achada.ordem.service_order_number;
    const { data, error } = await admin.from("issued_fiscal_documents").select(CAMPOS_DA_NOTA)
      .eq("origin_type", "service_order").eq("origin_id", achada.ordem.id);
    if (error) return { erro: `A consulta das notas falhou (${error.message}). Tente de novo.` };
    candidatas = (data ?? []) as Nota[];
    if (!candidatas.length) return { erro: `A ${osNumero} não tem nota fiscal emitida pelo sistema.` };
  } else if (notaDita && !ultima) {
    // 3) Pelo número da nota: "29", "2/29", "NF-e 29", "nota 5".
    const serieNumero = notaDita.match(/(\d+)\s*\/\s*(\d+)/);
    const numero = serieNumero ? Number(serieNumero[2]) : Number(notaDita.replace(/\D/g, ""));
    if (!numero) return { erro: `Não entendi o número da nota "${notaDita}". Use, por exemplo, 29 ou 2/29.` };
    let q = admin.from("issued_fiscal_documents").select(CAMPOS_DA_NOTA).eq("number", numero);
    if (serieNumero) q = q.eq("series", Number(serieNumero[1]));
    const { data, error } = await q;
    if (error) return { erro: `A consulta das notas falhou (${error.message}). Tente de novo.` };
    candidatas = (data ?? []) as Nota[];
    if (!candidatas.length) return { erro: `Não achei nota fiscal com o número ${notaDita}.` };
  } else {
    // 4) Pelo cliente, ou só "a última": as notas de produção, a mais recente vence.
    const { data, error } = await admin.from("issued_fiscal_documents").select(CAMPOS_DA_NOTA)
      .eq("environment", "producao").order("created_at", { ascending: false }).limit(500);
    if (error) return { erro: `A consulta das notas falhou (${error.message}). Tente de novo.` };
    candidatas = (data ?? []) as Nota[];
    if (clienteDito) {
      let clienteId: string | null = null;
      if (UUID_RE.test(clienteDito)) {
        clienteId = clienteDito;
      } else {
        const ids = [...new Set(candidatas.map((n) => n.client_id).filter(Boolean))] as string[];
        if (!ids.length) return { erro: "Nenhuma nota de produção tem cliente vinculado." };
        const { data: clientes, error: cErr } = await admin.from("clients").select("id, name, display_name").in("id", ids);
        if (cErr) return { erro: `A consulta dos clientes falhou (${cErr.message}). Tente de novo.` };
        const lista = ((clientes ?? []) as Array<{ id: string; name: string; display_name: string | null }>).flatMap((c) => [
          { id: c.id, nome: c.name },
          ...(c.display_name ? [{ id: c.id, nome: c.display_name }] : []),
        ]);
        const escolha = escolherPorNome(clienteDito, lista);
        if ("nenhum" in escolha) return { erro: `Nenhum cliente com nota fiscal se chama "${clienteDito}". Confira o nome (list_fiscal_documents mostra as notas).` };
        if ("ambiguo" in escolha) {
          const nomes = [...new Map(escolha.ambiguo.map((x) => [x.id, x.nome])).values()];
          if (nomes.length > 1) return { erro: `Mais de um cliente com nota serve para "${clienteDito}": ${nomes.join("; ")}. Pergunte qual.`, opcoes: nomes };
          clienteId = escolha.ambiguo[0].id;
        } else {
          clienteId = escolha.achado.id;
        }
      }
      candidatas = candidatas.filter((n) => n.client_id === clienteId);
      if (!candidatas.length) return { erro: "Esse cliente não tem nota fiscal de produção emitida pelo sistema." };
    }
  }

  if (tipo) {
    const doTipo = candidatas.filter((n) => n.document_type === tipo);
    if (!doTipo.length) {
      const outras = [...new Set(candidatas.map((n) => rotuloDaNota(n)))];
      return { erro: `Não há ${TIPO_ROTULO[tipo]} aí${outras.length ? ` — só ${outras.join(", ")}` : ""}.` };
    }
    candidatas = doTipo;
  }

  const mandaveis = ordenarRecentes(candidatas.filter((n) => !motivoParaNaoMandar(n)));
  if (!mandaveis.length) {
    // Nenhuma serve: diz por que a mais recente não vai (cancelada, homologação, sem PDF…).
    return { erro: motivoParaNaoMandar(ordenarRecentes(candidatas)[0])! };
  }
  // Pelo cliente ou "a última": a mais recente, como o dono pediu. Pela OS ou pelo número, duas
  // que servem (NF-e e NFS-e da mesma OS; NF-e 5 e NFS-e 5) é pergunta — mandar a errada ao
  // cliente não se desfaz.
  const pelaMaisRecente = !osDita && (!notaDita || ultima);
  if (!pelaMaisRecente && mandaveis.length > 1) {
    const opcoes = mandaveis.map((n) => rotuloDaNota(n));
    return { erro: `Há ${mandaveis.length} notas autorizadas aí: ${opcoes.join(" e ")}. Pergunte qual (a de produto, NF-e, ou a de serviço, NFS-e) e repita com tipo.`, opcoes };
  }
  const nota = mandaveis[0];
  if (!osNumero && nota.origin_type === "service_order" && nota.origin_id) {
    const { data: so } = await admin.from("service_orders").select("service_order_number").eq("id", nota.origin_id).maybeSingle();
    osNumero = so?.service_order_number ?? null;
  }
  return { nota, os: osNumero };
}

/** O cliente da nota e o destino do envio — SÓ do cadastro do cliente da nota. */
// deno-lint-ignore no-explicit-any
async function clienteDaNota(admin: any, nota: Nota) {
  if (!nota.client_id) return { erro: `A ${rotuloDaNota(nota)} não tem cliente cadastrado vinculado — não há para quem mandar.` };
  const { data: c, error } = await admin.from("clients").select("name, display_name, whatsapp, phone, opt_out_whatsapp").eq("id", nota.client_id).maybeSingle();
  if (error) return { erro: `A consulta do cliente falhou (${error.message}). Tente de novo.` };
  if (!c) return { erro: "O cliente da nota não existe mais no cadastro." };
  const telefone = telefoneParaEnvio(c.whatsapp || c.phone);
  return { cliente: c as { name: string; display_name: string | null; opt_out_whatsapp: boolean | null }, telefone };
}

/** A legenda: a frase do dono, ou o texto da tela (corrigido para a NFS-e, que não tem DANFE). */
export function legendaDaNota(nota: Nota, nomeUsado: string, frase: string): string {
  if (frase) return frase;
  const doc = nota.document_type === "nfse"
    ? `a NFS-e ${nota.series ?? ""}/${nota.number ?? ""} (nota fiscal de serviço)`
    : `o DANFE da NF-e ${nota.series ?? ""}/${nota.number ?? ""}`;
  return `Olá${nomeUsado ? ` ${nomeUsado}` : ""}! Segue em anexo ${doc}. Qualquer dúvida, estamos à disposição.`;
}

/** URL assinada curta do PDF arquivado (a Evolution baixa dentro da chamada de envio). */
// deno-lint-ignore no-explicit-any
async function urlDoPdf(admin: any, nota: Nota): Promise<{ url: string } | { erro: string }> {
  const { data, error } = await admin.storage.from(BUCKET_DA_NOTA).createSignedUrl(nota.pdf_storage_path, VALIDADE_DA_URL_S);
  if (error || !data?.signedUrl) return { erro: `não consegui gerar o endereço do PDF (${error?.message ?? "sem URL"})` };
  return { url: data.signedUrl };
}

const fraseDos = (args: Record<string, unknown>) => (typeof args?.custom_message === "string" ? args.custom_message.trim() : "");

/** Recusa barata (sem banco): cargo e tamanho da frase. Usada antes da pendência e no execute. */
export function validarPedidoDaNota(args: Record<string, unknown>, ctx: Pick<ToolCtx, "userRole">) {
  if (cargosQueContam(args, ctx).some((c) => !CARGOS_DA_NOTA.includes(c as Role))) {
    return { error: "Só o administrador manda nota fiscal pelo assistente (como na tela Notas Fiscais)." };
  }
  const frase = fraseDos(args);
  if (frase.length > LIMITE_DA_FRASE) {
    return { error: `A frase tem ${frase.length} caracteres; junto do PDF cabem até ${LIMITE_DA_FRASE}. Encurte e peça de novo.` };
  }
  return null;
}

/**
 * O retrato do que o dono aprova: QUAL nota (o id — "a última do Miguel" pode mudar até o "sim")
 * e o telefone do cadastro (em hash). O execute manda exatamente essa nota e recusa se o
 * telefone mudou.
 */
// deno-lint-ignore no-explicit-any
export async function retratoDaNota(admin: any, args: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  const achada = await localizarNota(admin, args);
  if ("erro" in achada) return null;
  const dono = await clienteDaNota(admin, achada.nota);
  if ("erro" in dono) return { nota_id: achada.nota.id };
  return { nota_id: achada.nota.id, telefone: hashCurto(dono.telefone ?? "") };
}

/**
 * Resumo da confirmação (painel e "sim <PIN>"): a nota, a OS, o cliente, o telefone INTEIRO do
 * cadastro e a legenda que vai junto. Quando a nota não serve, uma linha "⚠️" dizendo por quê.
 */
// deno-lint-ignore no-explicit-any
export async function resumirEnvioDaNota(admin: any, args: Record<string, unknown>): Promise<string> {
  const achada = await localizarNota(admin, args);
  if ("erro" in achada) return `⚠️ ${achada.erro}`;
  const { nota, os } = achada;
  const dono = await clienteDaNota(admin, nota);
  if ("erro" in dono) return `⚠️ ${dono.erro}`;
  const nomeUsado = dono.cliente.display_name || String(dono.cliente.name ?? "").trim().split(/\s+/)[0] || "";
  const frase = fraseDos(args);
  const linhas = [
    `Enviar ao CLIENTE pelo WhatsApp o PDF da *${rotuloDaNota(nota)}*${os ? ` (${os})` : ""}`,
    `Cliente: *${dono.cliente.name || "—"}*`,
    dono.telefone ? `WhatsApp: *${telefoneLegivel(dono.telefone)}* (do cadastro)` : "WhatsApp: ⚠️ cliente sem WhatsApp/telefone válido no cadastro — o envio vai falhar",
    `Legenda: "${legendaDaNota(nota, nomeUsado, frase)}"`,
  ];
  if (frase.length > LIMITE_DA_FRASE) linhas.push(`⚠️ A frase tem ${frase.length} caracteres (limite ${LIMITE_DA_FRASE}) — o envio será recusado.`);
  if (dono.cliente.opt_out_whatsapp) linhas.push("⚠️ O cliente pediu para não receber WhatsApp (opt-out) — o envio será recusado.");
  return linhas.join("\n");
}

const PROPRIEDADES_DA_NOTA = {
  os: { type: "string", description: "Número da OS de origem da nota, como foi dito (OS-00098, 98) ou o id." },
  nota: { type: "string", description: "Número da nota (29, 2/29), o id dela, ou 'ultima'." },
  cliente: { type: "string", description: "Nome do cliente como foi dito (ou o client_id): manda a nota MAIS RECENTE dele." },
  tipo: { type: "string", enum: ["nfe", "nfse"], description: "nfe = nota de produto (DANFE); nfse = nota de serviço. Use quando o dono disser, ou quando a tool perguntar." },
};

/** Janela de 2 minutos: pedir duas vezes seguidas não manda dois arquivos iguais para si. */
const janelaDeDoisMinutos = () => Math.floor(Date.now() / 120_000);

export const notaFiscalPdfTools: ToolDef[] = [
  {
    name: "send_fiscal_pdf_to_self",
    description:
      "Manda o PDF de uma NOTA FISCAL já autorizada (DANFE da NF-e ou PDF da NFS-e) para o WhatsApp de QUEM ESTÁ PEDINDO (nunca para o cliente). Use para 'me manda o PDF da nota da OS-00098', 'quero ver a nota 29', 'manda pra mim a última nota do Miguel'. Ache a nota pela OS (os), pelo número (nota) ou pelo cliente (a mais recente dele). É o mesmo arquivo do botão PDF da tela Notas Fiscais. Para mandar ao CLIENTE use send_fiscal_pdf_to_client.",
    input_schema: { type: "object", properties: PROPRIEDADES_DA_NOTA },
    // Só para quem pede, e o conteúdo é o que ele já vê na tela: nada a confirmar.
    risk: "low",
    roles: CARGOS_DA_NOTA,
    async execute(args, ctx) {
      const bloqueado = blockTechnician(ctx);
      if (bloqueado) return bloqueado;
      const recusado = validarPedidoDaNota(args, ctx);
      if (recusado) return recusado;
      const { admin } = ctx;
      const achada = await localizarNota(admin, args);
      if ("erro" in achada) return { error: achada.erro, ...(achada.opcoes ? { opcoes: achada.opcoes } : {}) };
      const { nota, os } = achada;

      // Destino: o telefone de quem pediu, do cadastro — nunca de um texto.
      const { data: u, error: uErr } = await admin.from("app_users").select("phone_normalized").eq("id", ctx.userId).maybeSingle();
      if (uErr) return { error: `Falha ao ler o seu cadastro: ${uErr.message}` };
      const telefone = String(u?.phone_normalized ?? "").replace(/\D/g, "");
      if (!telefone) return { error: "Você não tem um WhatsApp cadastrado para receber o PDF. Cadastre em Configurações → Usuários (aba IA/Zap)." };

      const endereco = await urlDoPdf(admin, nota);
      if ("erro" in endereco) return { error: `Não consegui mandar o PDF da nota: ${endereco.erro}.` };
      const rotulo = rotuloDaNota(nota);
      const cliente = String(nota.request_payload?.recipient?.name || "").trim();
      const legenda = `🧾 ${rotulo}${cliente ? ` — ${cliente}` : ""}${os ? ` · ${os}` : ""}`;
      const chave = chaveDeEnvio("agente-nota", nota.id, telefone, janelaDeDoisMinutos());
      const envio = await enviarDocumentoWhatsapp({
        phone: telefone,
        url: endereco.url,
        filename: nomeDoArquivoDaNota(nota),
        caption: legenda,
        context: CONTEXTO_DA_NOTA_PROPRIA,
        jwt: ctx.jwt,
        dedupeKey: chave,
      });
      if (!envio.ok) {
        // Sem resposta (25 s, rede): a reserva da chave ficaria de pé e o próximo pedido ouviria
        // "já mandei" — libera (o mesmo critério do PDF de orçamento).
        if (envio.semResposta) await liberarEnvio(admin, chave).catch(() => {});
        return { error: `Não consegui mandar o PDF da nota: ${envio.error}.`, orientacao: "Diga que o anexo falhou (sem fingir que mandou) e ofereça tentar de novo daqui a pouco, ou baixar pela tela Notas Fiscais." };
      }
      if (envio.deduplicated) return { ok: true, deduplicated: true, aviso: `Esse mesmo PDF (${rotulo}) já foi mandado para você há instantes; não reenviei.` };
      const modoTeste = desviadoPorTeste(ctx.settings);
      return {
        ok: true,
        enviado_para: modoTeste ? "o número de TESTE do WhatsApp (modo de teste ligado)" : "o WhatsApp de quem pediu",
        nota: rotulo,
        os,
        cliente: cliente || null,
        arquivo: nomeDoArquivoDaNota(nota),
        observacao: modoTeste
          ? "O modo de teste do WhatsApp está ligado: o arquivo foi para o número de teste, não para quem pediu. Diga isso."
          : "O arquivo já chegou no WhatsApp de quem pediu.",
      };
    },
  },
  {
    name: "send_fiscal_pdf_to_client",
    description:
      "Manda o PDF de uma NOTA FISCAL autorizada (DANFE da NF-e ou PDF da NFS-e) AO CLIENTE da nota pelo WhatsApp do cadastro dele (não existe campo de telefone). Use para 'envia a nota da OS-00105 para o cliente', 'reenvia a última nota do Miguel', 'manda a nota de serviço do Nelson com a frase: …'. Ache a nota pela OS (os), pelo número (nota) ou pelo cliente (a mais recente dele); 'nota de serviço' = tipo nfse. custom_message = a frase que o dono quer junto (vira a legenda inteira); sem frase vai o texto padrão da tela. Sempre pede a confirmação do usuário, que vê a nota, o cliente e o telefone.",
    input_schema: {
      type: "object",
      properties: {
        ...PROPRIEDADES_DA_NOTA,
        custom_message: { type: "string", description: "A frase que o dono quer junto do PDF, escrita como ele pediu (até 1000 caracteres). Sem ela, vai 'Olá <nome>! Segue em anexo o DANFE/a NFS-e…'." },
      },
    },
    // Arquivo com valores e dados fiscais a terceiro, que não se desfaz: sempre com o "sim"
    // (NEVER_AUTONOMOUS em autonomy-policy.ts).
    risk: "high",
    roles: CARGOS_DA_NOTA,
    preValidar: (args, ctx) => validarPedidoDaNota(args, ctx),
    // Sem gravarSolicitante de propósito: só o admin pede E só o admin aprova (roles e o execute),
    // e a linha "Pedido por" impediria o resumo de uma linha "⚠️" de virar recusa
    // (RESUMO_QUE_RESOLVE em agent.ts) — o dono veria no sino uma nota que não vai sair.
    // QUAL nota e para qual telefone: mudou até o "sim", não envia.
    retratoDaPendencia: (args, ctx) => retratoDaNota(ctx.admin, args),
    async execute(args, ctx) {
      const bloqueado = blockTechnician(ctx);
      if (bloqueado) return bloqueado;
      const recusado = validarPedidoDaNota(args, ctx);
      if (recusado) return recusado;
      const { admin, settings } = ctx;
      const retrato = lerRetrato(args);
      // Com retrato, a nota é a que o dono aprovou — não "a mais recente de agora".
      const achada = typeof retrato?.nota_id === "string"
        ? await localizarNota(admin, { nota: retrato.nota_id })
        : await localizarNota(admin, args);
      if ("erro" in achada) return { error: achada.erro, nada_enviado: true, ...(achada.opcoes ? { opcoes: achada.opcoes } : {}) };
      const { nota, os } = achada;
      const dono = await clienteDaNota(admin, nota);
      if ("erro" in dono) return { error: dono.erro, nada_enviado: true };
      if (dono.cliente.opt_out_whatsapp) return { error: "Este cliente pediu para não receber mensagens no WhatsApp (opt-out).", nada_enviado: true };
      const telefone = dono.telefone;
      if (!telefone) return { error: "Cliente sem WhatsApp/telefone válido no cadastro (com DDD). Corrija o cadastro e peça de novo.", nada_enviado: true };
      if (typeof retrato?.telefone === "string" && retrato.telefone !== hashCurto(telefone)) {
        return { error: "Desde o pedido, o WhatsApp do cliente no cadastro mudou. Nada foi enviado — peça de novo para confirmar com o número de agora.", nada_enviado: true };
      }

      const nomeUsado = dono.cliente.display_name || String(dono.cliente.name ?? "").trim().split(/\s+/)[0] || "";
      const frase = fraseDos(args);
      const legenda = legendaDaNota(nota, nomeUsado, frase);
      const rotulo = rotuloDaNota(nota);
      // Portão de comunicação ANTES de gerar o endereço: fora de 8h–20h não sai.
      const g = guardaDeEnvio(legenda, { tipo: "generico", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: true });
      const registro = { tipo: "nota_fiscal", audiencia: "cliente", entityKind: "fiscal_document", entityId: nota.id, phone: telefone };
      if (g.bloqueado) {
        await registrarEnvio(admin, { ...registro, preview: `[${rotulo}] ${legenda}`, status: "blocked", blockCode: g.codigoBloqueio });
        return { error: g.motivo, nada_enviado: true };
      }
      const endereco = await urlDoPdf(admin, nota);
      if ("erro" in endereco) {
        await registrarEnvio(admin, { ...registro, preview: `[${rotulo}] não gerado: ${endereco.erro}`, status: "failed" });
        return { error: `O PDF da nota não foi anexado (${endereco.erro}). Nada foi enviado ao cliente.`, nada_enviado: true };
      }
      // Modo de teste entra na chave: o envio desviado não pode reservar a chave do cliente.
      const modoTeste = desviadoPorTeste(settings);
      const chave = chaveDeEnvio("nota-pdf", nota.id, telefone, diaLocal(), hashCurto(legenda), modoTeste ? "teste" : null);
      const envio = await enviarDocumentoWhatsapp({
        phone: telefone,
        url: endereco.url,
        filename: nomeDoArquivoDaNota(nota),
        caption: legenda,
        context: CONTEXTO_DA_NOTA_AO_CLIENTE,
        jwt: ctx.jwt,
        dedupeKey: chave,
      });
      if (!envio.ok) {
        if (envio.semResposta) await liberarEnvio(admin, chave).catch(() => {});
        await registrarEnvio(admin, { ...registro, preview: `[${rotulo}] ${legenda}`, status: "failed" });
        return envio.semResposta
          ? { error: `O WhatsApp não confirmou o envio da nota (${envio.error}): pode ter chegado ou não. Confira a conversa do cliente antes de reenviar.` }
          : { error: `O WhatsApp recusou o envio da nota (${envio.error}). Nada foi enviado ao cliente.`, nada_enviado: true };
      }
      if (envio.deduplicated) return { ok: true, deduplicated: true, aviso: `Este mesmo PDF (${rotulo}) já foi enviado hoje para este cliente; não reenviei.` };
      await registrarEnvio(admin, { ...registro, preview: `[${rotulo}] ${legenda}`, status: "sent" });
      return {
        ok: true,
        nota: rotulo,
        os,
        cliente: dono.cliente.name,
        enviado_para: modoTeste ? "o número de TESTE do WhatsApp (modo de teste ligado), não o cliente" : `o WhatsApp do cliente (${mascararTelefone(telefone)})`,
        observacao: modoTeste
          ? "O modo de teste do WhatsApp está ligado: o PDF foi para o número de teste, NÃO para o cliente. Diga isso."
          : frase ? "O cliente recebeu o PDF da nota com a sua frase na legenda." : "O cliente recebeu o PDF da nota com o texto padrão.",
        ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}),
      };
    },
  },
];
