// Mandar a via do técnico e registrar (13/11/2026) — o mesmo caminho para o assistente e para a agenda.
//
// Quem chama escolhe COMO o arquivo sai, porque a regra do whatsapp-send muda com isso:
//   · o assistente (o dono pediu e disse SIM) manda como "assistente" (tools/whatsapp.ts, enviarDocumentoWhatsapp);
//   · a agenda (sozinha, junto da ficha das 19:30) manda como "sistema" (enviarDocumentoComoSistema, aqui): para
//     quem não é usuário ativo — a equipe de campo não tem login — o whatsapp-send confere o bloqueio do número e a
//     janela de horário (8h às 20h de Brasília), como em todo envio automático.

import { guardarEEntregar } from "./gerar-e-guardar.ts";
import { legendaDaVia, linksDasFotosDaVia, type OrdemDaVia, prepararVia } from "./via-do-tecnico-dados.ts";
import type { DadosDaVia } from "./via-do-tecnico.ts";
import { liberarEnvio } from "../whatsapp/idempotencia.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

/** O que quem envia recebe e devolve (o mesmo formato de enviarDocumentoWhatsapp). */
export type EnviarDocumento = (p: {
  phone: string;
  url: string;
  filename: string;
  caption: string;
  context: string;
  jwt: string;
  dedupeKey?: string;
}) => Promise<{ ok: true; deduplicated?: boolean } | { ok: false; error: string; semResposta?: boolean; recusado?: boolean }>;

/**
 * Manda um PDF pelo whatsapp-send como SISTEMA (chave de serviço, sem `origem`): o envio automático. Recusa do
 * whatsapp-send (fora de horário, número bloqueado) volta com `recusado`. Nunca lança.
 */
export const enviarDocumentoComoSistema: EnviarDocumento = async (p) => {
  const controle = new AbortController();
  const relogio = setTimeout(() => controle.abort(), 25_000);
  try {
    const r = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/whatsapp-send`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}` },
      body: JSON.stringify({
        phone: p.phone,
        kind: "document",
        document_url: p.url,
        document_filename: p.filename,
        document_caption: p.caption,
        context: p.context,
        ...(p.dedupeKey ? { dedupe_key: p.dedupeKey } : {}),
      }),
      signal: controle.signal,
    });
    const data = await r.json().catch(() => ({})) as Record<string, unknown>;
    if (!r.ok) {
      const erro = data.error;
      return {
        ok: false,
        error: typeof erro === "string" ? erro : erro ? JSON.stringify(erro) : `HTTP ${r.status}`,
        ...(data.recusado === true ? { recusado: true } : {}),
      };
    }
    return { ok: true, ...(data.deduplicated ? { deduplicated: true } : {}) };
  } catch (e) {
    return { ok: false, error: `sem resposta do envio (${e instanceof Error ? e.message : String(e)})`, semResposta: true };
  } finally {
    clearTimeout(relogio);
  }
};

export type ResultadoDoEnvio =
  | { ok: true; deduplicado?: boolean; servicos: number; impressao: string }
  | { ok: false; motivo: string; pulado?: boolean; recusado?: boolean };

/**
 * Monta a via da pessoa (ou da OS inteira), renderiza e manda para o telefone. Quem chama decide o envio,
 * o contexto, a chave e o registro. Nunca lança.
 */
export async function mandarVia(p: {
  admin: Admin;
  settings: Record<string, string>;
  jwt: string;
  dados: DadosDaVia;
  ordem: OrdemDaVia;
  pessoa: { id: string; nome: string } | null;
  telefone: string;
  contexto: string;
  chave: (impressao: string) => string;
  enviar: EnviarDocumento;
  complementoDaLegenda?: string | null;
  /** A via já montada (a agenda monta antes para comparar a impressão): evita montar duas vezes. */
  linksDasFotos?: Record<string, string>;
}): Promise<ResultadoDoEnvio> {
  try {
    if (!p.ordem.shareToken) return { ok: false, motivo: "a OS não tem token de link (o PDF não tem como ser gerado)" };
    const links = p.linksDasFotos ?? await linksDasFotosDaVia(p.admin, p.dados);
    const via = prepararVia(p.dados, p.ordem.numero, p.pessoa, links);
    if (via.semServicoDaPessoa) {
      return { ok: false, pulado: true, motivo: `todos os serviços da ${p.ordem.numero} estão com outra pessoa` };
    }
    const chave = p.chave(via.impressao);
    const entrega = await guardarEEntregar({
      admin: p.admin,
      doc: { html: via.html, nomeDoArquivo: via.nomeDoArquivo },
      shareToken: p.ordem.shareToken,
      baseUrl: p.settings.app_public_url || "",
      rotuloDoLog: "via-do-tecnico",
      entregar: (url) =>
        p.enviar({
          phone: p.telefone,
          url,
          filename: via.nomeDoArquivo,
          caption: legendaDaVia(p.ordem, p.complementoDaLegenda),
          context: p.contexto,
          jwt: p.jwt,
          dedupeKey: chave,
        }),
    });
    if (!entrega.ok) return { ok: false, motivo: entrega.motivo };
    const envio = entrega.valor;
    if (!envio.ok) {
      // Sem resposta (tempo, rede): a reserva da chave ficaria de pé e o próximo pedido ouviria "já mandei".
      if (envio.semResposta) await liberarEnvio(p.admin, chave).catch(() => {});
      return { ok: false, motivo: envio.error, ...("recusado" in envio && envio.recusado ? { recusado: true } : {}) };
    }
    return { ok: true, deduplicado: envio.deduplicated === true, servicos: via.servicos, impressao: via.impressao };
  } catch (e) {
    return { ok: false, motivo: e instanceof Error ? e.message : String(e) };
  }
}

export interface LinhaDoRegistro {
  service_order_id: string;
  payee_id?: string | null;
  app_user_id?: string | null;
  origem: "agenda" | "assistente" | "para_si";
  estado: "enviado" | "falhou" | "pulado";
  motivo?: string | null;
  destino?: string | null;
  impressao?: string | null;
  servicos?: number | null;
  ficha_id?: string | null;
  dia?: string | null;
  pedido_por?: string | null;
}

/** Grava o envio. Falha ao gravar não desfaz o envio (o PDF já está no WhatsApp): só avisa no log. */
export async function registrarEnvioDaVia(admin: Admin, linha: LinhaDoRegistro): Promise<{ ok: boolean; codigo?: string }> {
  const destino = linha.destino && /^[0-9]{8,15}$/.test(linha.destino) ? linha.destino : null;
  const motivo = linha.estado === "enviado" ? (linha.motivo ?? null) : (linha.motivo || "sem motivo informado").slice(0, 300);
  const { error } = await admin.from("via_tecnico_envios").insert({ ...linha, destino, motivo });
  if (error) {
    console.warn(`[via-do-tecnico] envio sem registro (${error.code ?? ""}): ${error.message}`);
    return { ok: false, codigo: error.code ?? undefined };
  }
  return { ok: true };
}

/** "enviado" | "pulado" | "falhou", do resultado. */
export function estadoDoResultado(r: ResultadoDoEnvio): "enviado" | "pulado" | "falhou" {
  if (r.ok) return "enviado";
  return r.pulado ? "pulado" : "falhou";
}
