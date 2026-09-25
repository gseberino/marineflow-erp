// Tool: o assistente manda o PDF de um orçamento/OS para o WhatsApp de QUEM PEDIU.
//
// Pedido do dono (25/09/2026): "me manda o PDF do orçamento 86" e receber o ARQUIVO na
// conversa. Até aqui o assistente só sabia mandar o LINK, e só para o cliente.
//
// O caminho é o da tela, peça por peça — nada foi reescrito:
//   montagem dos dados   → _shared/pdf/dados.ts      (a mesma do Baixar e do portal)
//   desenho do documento → _shared/pdf/documento.ts  (o mesmo do Baixar)
//   HTML → PDF           → /api/pdf no Vercel        (o mesmo Chromium do Baixar)
//   envio do arquivo     → edge whatsapp-send        (o mesmo do botão Enviar da tela)
//
// Decisões do dono (25/09/2026) que moram aqui:
//   · o PDF vai SÓ para quem pediu — não existe campo de telefone nem de cliente;
//   · só admin e financeiro pedem (o PDF leva preço, PIX e dados do cliente);
//   · pedir o PDF para si NÃO muda o status do orçamento;
//   · orçamento e OS (via do cliente); a via de execução do técnico fica de fora;
//   · o arquivo passa por um bucket PRIVADO, com URL de 10 minutos, e é apagado logo depois;
//   · se falhar, o link de reserva é a página interna (exige login), nunca o link público.

import { blockTechnician, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { enviarDocumentoWhatsapp } from "./whatsapp.ts";
import { chaveDeEnvio } from "../../whatsapp/idempotencia.ts";
import { carregarPDFData } from "../../pdf/dados.ts";
import { documentTypeFor } from "../../pdf/document-type.ts";
import {
  buildOrderHTML,
  buildPDFFilename,
  esc,
  fmtCurrency,
  type PDFOptions,
  resolvePdfOptions,
  tituloParaImpressao,
} from "../../pdf/documento.ts";
import { renderizarPdf } from "../../pdf/renderizar.ts";

/**
 * Quem pode pedir. Lista explícita, e NÃO `NON_TECHNICIAN_ROLES`: aquela inclui o vendedor
 * externo, e este PDF leva preço, dados bancários e dados do cliente.
 */
export const CARGOS_DO_PDF: Role[] = ["admin", "financial"];

/** Bucket privado, sem policy nenhuma: só a chave de serviço lê e escreve. */
export const BUCKET_DO_PDF = "pdf-agente";
const VALIDADE_DA_URL_S = 600;
/** O whatsapp-send recusa nome de arquivo acima de 120 caracteres (zod). */
const NOME_MAXIMO = 120;
/** O que diz ao whatsapp-send que isto NÃO é envio ao cliente. Nunca 'quote'. */
export const CONTEXTO_DO_ENVIO = "agente_pdf_proprio";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Ordem = { id: string; service_order_number: string; status: string; share_token: string | null; updated_at: string | null };
type Localizacao = { ordem: Ordem } | { erro: string } | { opcoes: string[] };

const CAMPOS = "id, service_order_number, status, share_token, updated_at";

/** "ORÇ-00086", "orc 86", "OS-75", "86", "orçamento 86" → o que buscar. */
export function interpretarDocumento(bruto: string, tipo?: string): { digitos: string; prefixo: "ORÇ" | "OS" | null } | null {
  const t = bruto.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase();
  const digitos = t.replace(/\D/g, "").replace(/^0+(?=\d)/, "");
  if (!digitos) return null;
  // O que está escrito vence o `tipo`: "OS-75" é OS mesmo que o modelo mande tipo=orcamento.
  const prefixo = /\bORC/.test(t) ? "ORÇ"
    : /\bOS\b|\bOS\d|\bORDEM\b/.test(t) ? "OS"
    : tipo === "orcamento" ? "ORÇ"
    : tipo === "os" ? "OS"
    : null;
  return { digitos, prefixo };
}

/** Número canônico: ORÇ-00086 / OS-00075 (5 dígitos, como o banco grava). */
const numeroCanonico = (prefixo: "ORÇ" | "OS", digitos: string) => `${prefixo}-${digitos.padStart(5, "0")}`;

/**
 * Acha a ordem. "ultimo" = a mais recente não cancelada (decisão do dono: inclui orçamento
 * expirado/"rejected", porque é o que ele acabou de fazer mesmo que o prazo tenha vencido).
 */
// deno-lint-ignore no-explicit-any
export async function localizarOrdem(admin: any, documento: string, tipo?: string): Promise<Localizacao> {
  const bruto = String(documento ?? "").trim();
  if (!bruto) return { erro: "Diga qual documento: o número (ex.: ORÇ-00086 ou só 86) ou 'ultimo'." };

  if (UUID_RE.test(bruto)) {
    const { data, error } = await admin.from("service_orders").select(CAMPOS).eq("id", bruto).maybeSingle();
    if (error) return { erro: `Falha ao buscar o documento: ${error.message}` };
    return data ? { ordem: data } : { erro: "Não achei documento com esse id." };
  }

  const semAcento = bruto.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  if (/^(o |a )?(ultim[oa])\b/.test(semAcento)) {
    let q = admin.from("service_orders").select(CAMPOS).neq("status", "cancelled");
    if (tipo === "orcamento") q = q.eq("status", "draft");
    else if (tipo === "os") q = q.neq("status", "draft");
    const { data, error } = await q.order("created_at", { ascending: false }).limit(1);
    if (error) return { erro: `Falha ao buscar o documento: ${error.message}` };
    return data?.[0] ? { ordem: data[0] } : { erro: "Não há documento para mandar." };
  }

  const alvo = interpretarDocumento(bruto, tipo);
  if (!alvo) return { erro: `Não entendi o número "${bruto}". Use, por exemplo, ORÇ-00086, OS-00075 ou só 86.` };

  const candidatos = alvo.prefixo
    ? [numeroCanonico(alvo.prefixo, alvo.digitos)]
    : [numeroCanonico("ORÇ", alvo.digitos), numeroCanonico("OS", alvo.digitos)];
  const { data, error } = await admin.from("service_orders").select(CAMPOS).in("service_order_number", candidatos);
  if (error) return { erro: `Falha ao buscar o documento: ${error.message}` };
  const achados = (data ?? []) as Ordem[];
  if (achados.length === 1) return { ordem: achados[0] };
  if (achados.length > 1) return { opcoes: achados.map((o) => o.service_order_number).sort() };
  // Ao ser aprovado, o orçamento GANHA número OS novo e o ORÇ não fica guardado em coluna
  // nenhuma: pedir pelo número antigo depois da aprovação não acha, e o dono precisa saber por quê.
  const dica = alvo.prefixo !== "OS"
    ? " Se era um orçamento que já foi aprovado, ele virou OS com outro número — procure pelo cliente (list_service_orders) e mande pelo número da OS."
    : "";
  return { erro: `Não achei ${candidatos.join(" nem ")}.${dica}` };
}

/** Corta o nome para caber no limite do whatsapp-send, sem perder o ".pdf". */
export function limitarNomeDoArquivo(nome: string): string {
  if (nome.length <= NOME_MAXIMO) return nome;
  return `${nome.slice(0, NOME_MAXIMO - 4).replace(/[-_]+$/, "")}.pdf`;
}

/** Janela de 2 minutos: pedir duas vezes seguidas não manda dois arquivos iguais. */
const janelaDeDoisMinutos = () => Math.floor(Date.now() / 120_000);

async function falha(ctx: ToolCtx, ordem: Ordem | null, motivo: string) {
  const base = (ctx.settings.app_public_url || "").replace(/\/+$/, "");
  return {
    error: `Não consegui mandar o PDF: ${motivo}.`,
    // Página interna, que exige login — o link público /view/<token> não expira e deixa quem
    // o receber aprovar e assinar; não é o que se manda como "plano B" de um PDF para si.
    ...(ordem && base ? { link_interno: `${base}/service-orders/${ordem.id}` } : {}),
    orientacao: "Diga que o anexo falhou (sem fingir que mandou) e ofereça o link interno, que abre com login, ou tentar de novo daqui a pouco.",
  };
}

export const documentoPdfTools: ToolDef[] = [
  {
    name: "send_document_pdf_to_self",
    description:
      "Manda o PDF de um orçamento ou OS para o WhatsApp de QUEM ESTÁ PEDINDO (nunca para o cliente). Use quando o usuário pedir 'me manda o PDF', 'quero ver o PDF do orçamento 86', 'manda o orçamento pra mim'. Aceita o número (ORÇ-00086, OS-00075 ou só 86), o id, ou 'ultimo'. É o mesmo PDF do botão Baixar e não muda o status do orçamento. Para mandar ao CLIENTE use send_service_order_link.",
    input_schema: {
      type: "object",
      properties: {
        documento: { type: "string", description: "Número (ORÇ-00086, OS-00075, 86), id (UUID) ou 'ultimo'." },
        tipo: { type: "string", enum: ["orcamento", "os"], description: "Se o usuário disse 'orçamento' ou 'OS' — resolve número solto e 'ultimo'." },
      },
      required: ["documento"],
    },
    // Só para quem pede, e o conteúdo é o que ele já vê na tela: nada a confirmar.
    risk: "low",
    roles: CARGOS_DO_PDF,
    async execute(args, ctx) {
      const bloqueado = blockTechnician(ctx);
      if (bloqueado) return bloqueado;
      if (!CARGOS_DO_PDF.includes(ctx.userRole as Role)) return { error: "Só administrador e financeiro podem pedir o PDF pelo assistente." };

      const { admin } = ctx;
      const achado = await localizarOrdem(admin, String(args.documento ?? ""), args.tipo);
      if ("erro" in achado) return { error: achado.erro };
      if ("opcoes" in achado) {
        return { error: `Há mais de um documento com esse número: ${achado.opcoes.join(" e ")}. Pergunte qual.`, opcoes: achado.opcoes };
      }
      const ordem = achado.ordem;
      if (!ordem.share_token) return await falha(ctx, ordem, "a ordem não tem token de link");

      // Destino: o telefone de quem pediu, do cadastro — nunca de um texto.
      const { data: u, error: uErr } = await admin.from("app_users").select("phone_normalized").eq("id", ctx.userId).maybeSingle();
      if (uErr) return { error: `Falha ao ler o seu cadastro: ${uErr.message}` };
      const telefone = String(u?.phone_normalized ?? "").replace(/\D/g, "");
      if (!telefone) return { error: "Você não tem um WhatsApp cadastrado para receber o PDF. Cadastre em Configurações → Usuários (aba IA/Zap)." };

      // ── O documento, exatamente como o Baixar do formulário monta ──────────────────
      let dados;
      try {
        dados = await carregarPDFData(ordem.id, admin);
      } catch (e) {
        return await falha(ctx, ordem, `não consegui ler os dados do documento (${e instanceof Error ? e.message : String(e)})`);
      }
      const tipoDoc = documentTypeFor(ordem.status);
      dados.documentType = tipoDoc;
      // Validade: a do próprio orçamento; sem ela, o padrão da empresa — a mesma conta do
      // formulário (ServiceOrderForm: form.quote_validity_days || defaultQuoteValidityDays).
      const padraoDaEmpresa = Number(ctx.settings.quote_validity_days ?? 15) || 15;
      const opcoes: PDFOptions = {
        ...resolvePdfOptions(ctx.settings, tipoDoc),
        ...(tipoDoc === "quote"
          ? { validity: { mode: "days" as const, days: Number(dados.serviceOrder.quote_validity_days) || padraoDaEmpresa } }
          : {}),
      };
      const html = buildOrderHTML(dados, opcoes).replace(
        /<title>[^<]*<\/title>/,
        `<title>${esc(tituloParaImpressao(dados, opcoes))}</title>`,
      );
      const nomeDoArquivo = limitarNomeDoArquivo(buildPDFFilename(dados, opcoes));

      const render = await renderizarPdf({
        baseUrl: ctx.settings.app_public_url || "",
        html,
        filename: nomeDoArquivo,
        shareToken: ordem.share_token,
      });
      if (!render.ok) return await falha(ctx, ordem, render.motivo);

      // ── Guarda por minutos num bucket privado; a Evolution baixa pela URL assinada ──
      const caminho = `agente/${new Date().getUTCFullYear()}/${crypto.randomUUID()}.pdf`;
      const armazem = admin.storage.from(BUCKET_DO_PDF);
      const { error: upErr } = await armazem.upload(caminho, render.pdf, { contentType: "application/pdf", upsert: false });
      if (upErr) return await falha(ctx, ordem, `não consegui guardar o arquivo (${upErr.message})`);

      try {
        const { data: assinada, error: urlErr } = await armazem.createSignedUrl(caminho, VALIDADE_DA_URL_S);
        if (urlErr || !assinada?.signedUrl) return await falha(ctx, ordem, `não consegui gerar o endereço do arquivo (${urlErr?.message ?? "sem URL"})`);

        const rotulo = tipoDoc === "quote" ? "Orçamento" : "Ordem de Serviço";
        const numero = dados.serviceOrder.service_order_number;
        const cliente = dados.client?.name || "—";
        const barco = dados.vessel?.name ? ` · ${dados.vessel.name}` : "";
        const total = fmtCurrency(Number(dados.serviceOrder.grand_total) || 0);
        const legenda = `📄 ${rotulo} ${numero} — ${cliente}${barco}\nTotal: ${total}`;

        const envio = await enviarDocumentoWhatsapp({
          phone: telefone,
          url: assinada.signedUrl,
          filename: nomeDoArquivo,
          caption: legenda,
          context: CONTEXTO_DO_ENVIO,
          jwt: ctx.jwt,
          // Mesmo documento, mesma versão, mesma janela de 2 min: não manda duas vezes.
          dedupeKey: chaveDeEnvio("agente-pdf", ordem.id, ordem.updated_at, janelaDeDoisMinutos()),
        });
        if (!envio.ok) return await falha(ctx, ordem, envio.error);
        if (envio.deduplicated) {
          return { ok: true, deduplicated: true, aviso: `Esse mesmo PDF (${rotulo} ${numero}) já foi mandado há instantes; não reenviei.` };
        }
        // Sem URL e sem token: o resultado fica gravado no histórico do agente.
        return {
          ok: true,
          enviado_para: "o WhatsApp de quem pediu",
          documento: `${rotulo} ${numero}`,
          cliente,
          total,
          arquivo: nomeDoArquivo,
          observacao: "O arquivo já chegou no WhatsApp de quem pediu (no canal WhatsApp, antes desta resposta).",
        };
      } finally {
        // Sucesso ou falha, o arquivo não fica: o PDF leva preço e dados do cliente, e a
        // cópia que importa já está no WhatsApp. Falha ao apagar não derruba o envio.
        await armazem.remove([caminho]).catch(() => {});
      }
    },
  },
];
