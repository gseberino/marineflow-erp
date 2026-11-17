// O técnico pede pelo WhatsApp dele: "imprime minha via", "imprime a via da 136" (17/11/2026, decisão do dono:
// "os técnicos podem pedir").
//
// A equipe de campo não conversa com o assistente (não tem login; o webhook só chama o ai-agent para app_users com
// ai_whatsapp_enabled). Por isso o pedido é lido aqui, por texto e sem modelo, ANTES do leitor da agenda
// (respostaDaEquipe): reconhecido = a mensagem é desta função e os outros leitores não a leem ("o ok tem um dono só").
//
// Regras:
//   · só quem é da equipe ATIVA (payees sócio/funcionário/diarista/prestador) com o telefone do cadastro;
//   · só a VIA DO TÉCNICO (sem preço): a da pessoa, ou a da OS inteira se nada da OS for dela;
//   · sem número: as OS do próximo dia dela na agenda (de hoje em diante), no máximo 3;
//   · no máximo 10 pedidos por pessoa por dia; desligar: app_settings.impressao_equipe = 'off'.
// A resposta sai como envio de sistema (whatsapp-send com a chave de serviço): para quem não é usuário, ele confere o
// bloqueio do número e a janela de 8h às 20h. Fora dela o papel sai e a resposta não (fica no log).

// Nada de ../ai/tools aqui: o webhook carregaria o pacote inteiro de tools do assistente em toda mensagem recebida.
import { mesmoTelefone } from "../ai/phone.ts";
import { logEdgeError } from "../log-error.ts";
import { chaveDeEnvio } from "../whatsapp/idempotencia.ts";
import { fraseDoResultado, impressoesDeHojeDaPessoa, impressoraNoAr } from "./fila.ts";
import { proximoDiaDaPessoa } from "./agenda.ts";
import { abrirViaPeloId, type Impressao, imprimirVia } from "./imprimir.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export const PEDIDOS_POR_DIA_DA_PESSOA = 10;
export const VIAS_DO_TECNICO_MAX = 3;
/** A equipe de campo — a mesma lista de TIPOS_DA_EQUIPE (tools/via-do-tecnico.ts); o teste confere que não divergem. */
export const TIPOS_DA_EQUIPE_NA_IMPRESSAO = ["socio", "funcionario", "diarista", "prestador"] as const;

/**
 * A OS pelo número que o técnico disse ("136" → OS-00136; se não houver, ORÇ-00136, cuja via também não tem preço).
 * Erro em frase curta.
 */
export async function acharOsPeloNumero(admin: Admin, digitos: string): Promise<{ id: string } | { erro: string }> {
  const n = digitos.replace(/\D/g, "").replace(/^0+(?=\d)/, "").padStart(5, "0");
  const { data, error } = await admin.from("service_orders").select("id, service_order_number")
    .in("service_order_number", [`OS-${n}`, `ORÇ-${n}`]);
  if (error) return { erro: `não consegui procurar a OS (${error.message})` };
  const achados = (data ?? []) as Array<{ id: string; service_order_number: string }>;
  const os = achados.find((o) => o.service_order_number.startsWith("OS-")) ?? achados[0];
  return os ? { id: os.id } : { erro: "não achei" };
}

const normalizar = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();

/**
 * "imprime minha via" → { documento: null }; "imprime a via da 136" / "pode imprimir a OS-136?" → { documento: "136" }.
 * Precisa do verbo imprimir; mensagem longa (conversa) ou com dois números = null (não é pedido, segue como sempre).
 */
export function lerPedidoDaEquipe(texto: string | null | undefined): { documento: string | null } | null {
  const t = normalizar(String(texto ?? ""));
  if (!t || t.length > 120) return null;
  if (!/\bimprim\w*|\bimpressao\b/.test(t)) return null;
  // "não precisa imprimir" / "já imprimi" não é pedido
  if (/\b(nao|nem|ja)\s+(precisa\s+|precisa de\s+)?(imprim|impress)/.test(t)) return null;
  const numeros = [...t.matchAll(/(?:^|[^\d])(?:os|orc)?\s*-?\s*0*(\d{1,6})(?!\d)/g)].map((m) => String(Number(m[1])));
  const unicos = [...new Set(numeros)];
  if (unicos.length > 1) return null;
  return { documento: unicos[0] ?? null };
}

export interface PessoaDaEquipe {
  id: string;
  nome: string;
}

/** A pessoa da equipe ativa com este telefone (últimos 8 dígitos). Erro de leitura = null (segue como sempre). */
export async function pessoaDaEquipePeloTelefone(admin: Admin, phone: string): Promise<PessoaDaEquipe | null> {
  const { data, error } = await admin.from("payees").select("id, name, phone")
    .eq("active", true).in("kind", [...TIPOS_DA_EQUIPE_NA_IMPRESSAO]).not("phone", "is", null);
  if (error) return null;
  const achada = ((data ?? []) as Array<{ id: string; name: string; phone: string | null }>).find((p) => mesmoTelefone(p.phone, phone));
  return achada ? { id: achada.id, nome: achada.name } : null;
}

/** A resposta ao técnico (texto, como sistema). Nunca lança. */
async function responder(phone: string, texto: string, chave: string): Promise<void> {
  try {
    const r = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/whatsapp-send`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}` },
      body: JSON.stringify({ phone, kind: "text", message: texto, context: "impressao_equipe", dedupe_key: chave }),
      signal: AbortSignal.timeout(25_000),
    });
    if (!r.ok) console.warn(`[impressao] resposta ao técnico não saiu (${r.status})`);
  } catch (e) {
    console.warn("[impressao] resposta ao técnico não saiu:", e instanceof Error ? e.message : String(e));
  }
}

async function lerConfiguracoes(admin: Admin): Promise<Record<string, string>> {
  const { data, error } = await admin.from("app_settings").select("key, value");
  if (error) throw new Error(`não consegui ler as configurações (${error.message})`);
  return Object.fromEntries(((data ?? []) as Array<{ key: string; value: unknown }>).map((s) => [s.key, String(s.value ?? "")]));
}

/** Imprime e devolve a frase para o técnico. Nunca lança. */
export async function atenderPedidoDaEquipe(
  admin: Admin,
  p: { pessoa: PessoaDaEquipe; documento: string | null; settings: Record<string, string> },
): Promise<string> {
  try {
    if (await impressoesDeHojeDaPessoa(admin, p.pessoa.id) >= PEDIDOS_POR_DIA_DA_PESSOA) {
      return `Hoje já foram ${PEDIDOS_POR_DIA_DA_PESSOA} impressões pedidas por você; peça ao escritório se precisar de mais.`;
    }
    const noAr = await impressoraNoAr(admin);
    if (!noAr.ok) return `Não deu para imprimir agora: ${noAr.motivo}.`;

    let ids: string[];
    let dia: string | null = null;
    if (p.documento) {
      const achado = await acharOsPeloNumero(admin, p.documento);
      if ("erro" in achado) {
        return achado.erro === "não achei"
          ? `Não achei a OS ${p.documento}. Mande o número da OS, assim: imprime a 136.`
          : `Não deu para imprimir agora: ${achado.erro}.`;
      }
      ids = [achado.id];
    } else {
      const proximo = await proximoDiaDaPessoa(admin, p.pessoa.id);
      if (!proximo || !proximo.os.length) return "Não achei OS sua na agenda de hoje em diante. Mande o número, assim: imprime a 136.";
      ids = proximo.os.slice(0, VIAS_DO_TECNICO_MAX);
      dia = proximo.dia;
    }

    const opcoes = { pedidoPor: { payee: p.pessoa.id, nome: p.pessoa.nome } };
    const feitas: Impressao[] = [];
    for (const id of ids) {
      const aberta = await abrirViaPeloId(admin, id, p.settings);
      if ("erro" in aberta) {
        feitas.push({ oque: "a via", copias: 1, resultado: { ok: false, motivo: aberta.erro } });
        continue;
      }
      const dias = dia ? [dia] : [];
      let feita = await imprimirVia(admin, p.settings, aberta, { id: p.pessoa.id, nome: p.pessoa.nome }, dias, opcoes);
      // Nada da OS é dele (serviços com outra pessoa): a via da OS inteira — ele pediu esta OS de propósito.
      if (feita.semServicoDaPessoa) feita = await imprimirVia(admin, p.settings, aberta, null, [], opcoes);
      feitas.push(feita);
    }
    return feitas.map((f) => fraseDoResultado(f.oque, f.resultado, f.copias)).join("\n");
  } catch (e) {
    await logEdgeError(admin, {
      context: "whatsapp-webhook",
      action: "impressao:equipe",
      message: `pedido de impressão da equipe falhou: ${e instanceof Error ? e.message : String(e)}`,
      error: e,
    }).catch(() => {});
    return "Não consegui imprimir agora (erro no sistema). Peça ao escritório.";
  }
}

/**
 * O webhook chama ANTES do leitor da agenda. true = a mensagem é um pedido de impressão de alguém da equipe e já foi
 * despachado (o trabalho pesado corre no fundo, por `noFundo`); false = segue como sempre. Nunca lança.
 */
export async function pedidoDeImpressaoDaEquipe(
  admin: Admin,
  p: { phone: string; body: string | null | undefined; messageId?: string | null; noFundo: (pr: Promise<unknown>) => void },
): Promise<boolean> {
  try {
    const pedido = lerPedidoDaEquipe(p.body);
    if (!pedido || !p.phone) return false;
    const pessoa = await pessoaDaEquipePeloTelefone(admin, p.phone);
    if (!pessoa) return false;
    const settings = await lerConfiguracoes(admin);
    if ((settings.impressao_equipe || "").trim().toLowerCase() === "off") return false;
    p.noFundo((async () => {
      const frase = await atenderPedidoDaEquipe(admin, { pessoa, documento: pedido.documento, settings });
      await responder(p.phone, frase, chaveDeEnvio("impressao-equipe", p.messageId ?? `${pessoa.id}:${Date.now()}`));
    })());
    return true;
  } catch (e) {
    console.warn("[impressao] pedido da equipe não lido:", e instanceof Error ? e.message : String(e));
    return false;
  }
}
