// Peças comuns das ferramentas do financeiro pela conversa (07/10/2026): anotações de Pix, estorno,
// cobrança formal e favorecido. Cada uma faz o MESMO que a tela; aqui mora só o que as quatro
// repetiriam — como se compara um nome dito, como se entende "sexta" ou "dia 20" no futuro.
import { blockTechnician, type Role, type ToolCtx } from "./registry.ts";
import { normal } from "./caixa.ts";
import { hojeEmBrasilia, somarDias } from "../../banking/fluxo-de-caixa.ts";

export const CARGOS_DO_FINANCEIRO: Role[] = ["admin", "financial"];
export const brl = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

/** 'AAAA-MM-DD' → 'dd/mm'. */
export const ddmm = (iso: string | null | undefined) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}` : "—");

export function semAcessoDoFinanceiro(ctx: ToolCtx): { error: string } | null {
  const b = blockTechnician(ctx);
  if (b) return b;
  if (!CARGOS_DO_FINANCEIRO.includes(ctx.userRole as Role)) return { error: "Apenas administrador ou financeiro." };
  return null;
}

/**
 * O nome dito aponta este nome cadastrado? Igual, ou TODAS as palavras ditas no nome ("eliane" acha
 * "Eliane Souza"). Nunca "parecido": a regra do dono (26/09) é nome igual ou cortado.
 */
export function casaNome(dito: unknown, nome: unknown): boolean {
  const d = normal(dito);
  const n = normal(nome);
  if (!d || !n) return false;
  if (d === n) return true;
  const palavras = d.split(" ").filter((p) => p.length >= 2);
  return palavras.length > 0 && palavras.every((p) => ` ${n} `.includes(` ${p} `));
}

const DIA_DA_SEMANA: Record<string, number> = { domingo: 0, segunda: 1, terca: 2, quarta: 3, quinta: 4, sexta: 5, sabado: 6 };

/**
 * Data dita para a FRENTE — vencimento e promessa de pagamento: "hoje", "amanhã", "sexta" (a próxima,
 * hoje se hoje for sexta), "dia 20" (deste mês se ainda não passou, senão do próximo), dd/mm[/aaaa]
 * e AAAA-MM-DD. O resto é nulo (a tool pergunta).
 */
export function dataFuturaDita(d: unknown, agora = new Date()): string | null {
  if (d == null || d === "") return null;
  const hoje = hojeEmBrasilia(agora);
  const s = normal(d).replace(/\s*feira$/, "").replace(/^(na|no|nesta|neste|esta|este|proxima|proximo)\s+/, "");
  if (s === "hoje") return hoje;
  if (s === "amanha") return somarDias(hoje, 1);
  if (s === "depois de amanha") return somarDias(hoje, 2);
  if (s in DIA_DA_SEMANA) {
    const dow = new Date(`${hoje}T12:00:00Z`).getUTCDay();
    return somarDias(hoje, (DIA_DA_SEMANA[s] - dow + 7) % 7);
  }
  const dia = s.match(/^dia (\d{1,2})$/);
  if (dia) {
    const n = Number(dia[1]);
    if (n < 1 || n > 31) return null;
    let [a, m] = hoje.split("-").map(Number);
    if (n < Number(hoje.slice(8, 10))) { m += 1; if (m > 12) { m = 1; a += 1; } }
    const ultimo = new Date(Date.UTC(a, m, 0)).getUTCDate();
    return `${a}-${String(m).padStart(2, "0")}-${String(Math.min(n, ultimo)).padStart(2, "0")}`;
  }
  const br = String(d).trim().match(/^(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?$/);
  if (br) {
    const ano = br[3] ? (br[3].length === 2 ? 2000 + Number(br[3]) : Number(br[3])) : Number(hoje.slice(0, 4));
    return `${ano}-${br[2].padStart(2, "0")}-${br[1].padStart(2, "0")}`;
  }
  if (/^\d{4}-\d{2}-\d{2}$/.test(String(d).trim())) return String(d).trim();
  return null;
}

/** Dias inteiros de `de` até `ate` ('AAAA-MM-DD'); negativo se `ate` vem antes. */
export function diasEntre(de: string, ate: string): number {
  return Math.round((Date.parse(`${ate.slice(0, 10)}T00:00:00Z`) - Date.parse(`${de.slice(0, 10)}T00:00:00Z`)) / 86_400_000);
}

/** Valor dito ("1.050", "1050,50", 1050) → número com centavos; o resto, nulo. */
export function valorDito(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) && v > 0 ? Math.round(v * 100) / 100 : null;
  const s = String(v ?? "").replace(/R\$|\s/g, "");
  if (!s) return null;
  const n = Number(s.includes(",") ? s.replace(/\./g, "").replace(",", ".") : s);
  return Number.isFinite(n) && n > 0 ? Math.round(n * 100) / 100 : null;
}

export const mesmoValor = (a: unknown, b: unknown) => Math.abs(Number(a) - Number(b)) < 0.01;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const ehUuid = (v: unknown) => typeof v === "string" && UUID_RE.test(v.trim());

export interface OrdemAchada { id: string; service_order_number: string; client_id: string | null; grand_total: number | null; status: string }

/**
 * A OS (ou orçamento) dita: o uuid, "OS-00112", "ORÇ-00112" ou só "112" — o mesmo critério de
 * localizarOrdem (documentos-pdf.ts): o prefixo escrito manda; sem prefixo, ORÇ e OS com o mesmo
 * número são pergunta. Mensagens numa linha só.
 */
export async function ordemDita(cliente: ToolCtx["sb"], dita: unknown): Promise<{ ordem: OrdemAchada } | { error: string }> {
  const bruto = String(dita ?? "").trim();
  if (!bruto) return { error: "Diga o número da OS." };
  const campos = "id, service_order_number, client_id, grand_total, status";
  if (ehUuid(bruto)) {
    const { data, error } = await cliente.from("service_orders").select(campos).eq("id", bruto).maybeSingle();
    if (error) return { error: `Não consegui ler a OS (${error.message}).` };
    return data ? { ordem: data as OrdemAchada } : { error: "OS não encontrada." };
  }
  const t = bruto.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase();
  const digitos = t.replace(/\D/g, "").replace(/^0+(?=\d)/, "");
  if (!digitos) return { error: `Não entendi a OS "${bruto}". Use, por exemplo, OS-00112 ou só 112.` };
  const prefixo = /\bORC/.test(t) ? "ORÇ" : /\bOS\b|\bOS\d|\bORDEM\b/.test(t) ? "OS" : null;
  const numero = (p: string) => `${p}-${digitos.padStart(5, "0")}`;
  const candidatos = prefixo ? [numero(prefixo)] : [numero("OS"), numero("ORÇ")];
  const { data, error } = await cliente.from("service_orders").select(campos).in("service_order_number", candidatos);
  if (error) return { error: `Não consegui ler a OS (${error.message}).` };
  const achadas = (data ?? []) as OrdemAchada[];
  if (achadas.length === 1) return { ordem: achadas[0] };
  if (achadas.length > 1) return { error: `Qual delas: ${achadas.map((o) => o.service_order_number).sort().join(" ou ")}?` };
  return { error: `Não achei ${candidatos.join(" nem ")}.` };
}

/** O uuid do retrato da pendência (o alvo resolvido quando o dono viu o resumo), se houver. */
export function alvoDoRetrato(retrato: Record<string, unknown> | null, chave: string): string | null {
  const v = retrato?.[chave];
  return typeof v === "string" && v ? v : null;
}
