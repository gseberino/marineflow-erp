// A leitura do guardado (secretário, Passo 4, P4.5 base, 16/10/2026): a manhã das 07:30 e o fechamento das 17:30
// (e as revisões, que ocupam o lugar dele) levam o que o portão guardou para elas.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md §6.3.
//
//   avisos_para_a_mensagem (o que esta mensagem leva) → "ainda é verdade?" (D8: o que se resolveu some —
//   aviso_resolver) → as linhas no texto → avisos_incluir_na_mensagem com o id da fila quando a mensagem é DE
//   FATO enfileirada.
//
// EM SOMBRA (a manhã/o fechamento só GUARDAM o texto novo; o dono recebe o de sempre): o texto guardado mostra as
// linhas, e nada vira "entregue" — a migration 20261016120000 faz a sombra sem fila marcar "incluido" (mostrado na
// mensagem-sombra), que não volta a aparecer e não conta como entregue. Com a voz única ligada de verdade (P4.5),
// só a mensagem que vai para a fila marca, com o id dela.
// Nada aqui derruba a mensagem: erro de leitura = sem o bloco (o guardado continua guardado para a próxima).

import { ddmm, umaLinha } from "../secretario/base.ts";
import { diaBR, horaBR } from "../pdf/datas.ts";
import type { ModoDoPortao, RegrasDaVozUnica } from "./portao.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** Um aviso guardado, como avisos_para_a_mensagem devolve. */
export interface AvisoGuardado {
  id: string;
  fonte: string;
  assunto: string;
  destino: string;
  motivo: string | null;
  texto: string | null;
  dados: Record<string, unknown> | null;
  registrado_em: string;
  dia: string;
  mensagem: string | null;
  reaberto: number;
}

export type MensagemFixa = "manha" | "fechamento";

// ─── As linhas (puras) ──────────────────────────────────────────────────────────────────────────

/** Sem emoji, sem negrito, uma linha, a 1ª frase. */
export function limpar(t: string | null | undefined, max = 90): string {
  const s = String(t ?? "")
    .replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/gu, "")
    .replace(/[*_]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  const frase = s.split(/(?<=[.!?])\s|\n/)[0] ?? s;
  return umaLinha(frase.replace(/[.!]$/, ""), max);
}

/** "às 09:02" (hoje), "ontem às 17:12", "em 06/10". */
function quando(iso: unknown, hoje: string): string | null {
  if (typeof iso !== "string" || Number.isNaN(Date.parse(iso))) return null;
  const d = new Date(iso);
  const dia = diaBR(d);
  if (dia === hoje) return `às ${horaBR(d)}`;
  const ontem = new Date(Date.parse(`${hoje}T12:00:00Z`) - 86_400_000).toISOString().slice(0, 10);
  if (dia === ontem) return `ontem às ${horaBR(d)}`;
  return `em ${ddmm(dia)}`;
}

const s = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

const CABECA_DO_CLIENTE: Record<string, string> = {
  fechar_hoje: "quer fechar hoje",
  fechar: "quer fechar",
  pressa: "pede para hoje",
  desistencia: "disse que fechou com outra empresa ou desistiu",
};

/** A linha curta de um aviso guardado (sem o ponto final). Usa os dados; sem eles, o texto que a fonte gravou. */
export function linhaDoGuardado(a: AvisoGuardado, hoje: string): string {
  const d = a.dados ?? {};
  const texto = a.texto ?? "";
  switch (a.fonte) {
    case "acompanhar": {
      const nome = s(d.contato) ?? /Acompanhamento \(pedido seu\): (.+?) \(\+?[\d ()+-]+\) está esperando/.exec(texto)?.[1] ?? null;
      const q = quando(d.mensagem_em, hoje);
      return nome ? `${umaLinha(nome, 30)} escreveu${q ? ` ${q}` : ""} e espera resposta` : "um contato que você pediu para acompanhar espera resposta";
    }
    case "cliente": {
      const nome = umaLinha(s(d.nome) ?? "um cliente", 30);
      const q = quando(d.mensagem_em, hoje);
      return `${nome} ${CABECA_DO_CLIENTE[String(d.gatilho)] ?? "pede resposta"}${q ? ` (${q.replace(/^às /, "")})` : ""}`;
    }
    case "promessa": {
      const m = /você escreveu a (.+?) \(\+?[\d ()+-]+\): "(.+?)"/.exec(texto);
      const nome = s(d.contato) ?? m?.[1] ?? null;
      const promessa = s(d.promessa) ?? m?.[2] ?? null;
      return `promessa sua${nome ? ` a ${umaLinha(nome, 30)}` : ""}${promessa ? `: "${umaLinha(promessa, 40)}"` : ""}`;
    }
    case "conexao": {
      const de = typeof d.desde === "string" ? d.desde : null;
      const ate = typeof d.ate === "string" ? d.ate : null;
      return de && ate ? `o WhatsApp ficou fora das ${horaBR(new Date(de))} às ${horaBR(new Date(ate))}` : "o WhatsApp ficou fora do ar";
    }
    case "email": {
      const quem = a.assunto.replace(/^(golpe|email):/, "");
      return a.assunto.startsWith("golpe:") ? `parece golpe no e-mail: ${umaLinha(quem, 40)}` : `e-mail urgente de ${umaLinha(quem, 40)}`;
    }
    case "vigia_negocio": {
      if (a.assunto.startsWith("saldo_divergente")) {
        const m = /Extrato de (.+?): .*?diferença (-?R\$\s?-?\d[\d.]*(?:,\d{2})?)/.exec(texto);
        // a diferença sem o sinal ("-R$ 41,00" = o sistema tem a mais): o dono confere no app do banco
        return m ? `o saldo do banco ${umaLinha(m[1], 20)} não bate com o sistema (${m[2].replace(/\s+/g, " ").replace(/^-/, "")} de diferença)` : "o saldo do banco não bate com o sistema";
      }
      if (a.assunto.startsWith("estoque_divergente")) {
        const n = /(\d+) produto/.exec(texto)?.[1];
        return `${n ?? "alguns"} ${n === "1" ? "produto está" : "produtos estão"} com estoque diferente dos movimentos`;
      }
      if (a.assunto.startsWith("cota_fiscal")) {
        const n = /~\*?(\d+)\*?\/500/.exec(texto)?.[1];
        return n ? `a cota fiscal do mês está em ${n} de 500` : "a cota fiscal do mês está perto do limite";
      }
      if (a.assunto.startsWith("fiscal:cert")) {
        const dias = Number(d.dias);
        const validade = s(d.validade);
        return Number.isFinite(dias)
          ? `o certificado A1 ${dias < 0 ? "venceu" : `vence em ${dias} ${dias === 1 ? "dia" : "dias"}`}${validade ? ` (${ddmm(validade)})` : ""}`
          : "o certificado A1 está perto de vencer";
      }
      if (a.assunto.startsWith("banco:consent")) {
        const dias = Number(d.dias);
        return Number.isFinite(dias) ? `a conexão do extrato do banco vence em ${dias} ${dias === 1 ? "dia" : "dias"}` : "a conexão do extrato do banco está perto de vencer";
      }
      if (a.assunto === "fiscal:nfe_rejeitada") {
        if (s(d.numero)) return `a NF-e nº ${d.numero}${s(d.cliente) ? ` (${umaLinha(String(d.cliente), 24)})` : ""} foi rejeitada`;
        const n = /\*?(\d+)\*? NF-e/.exec(texto)?.[1];
        return `${n ?? "uma"} NF-e ${n && n !== "1" ? "rejeitadas" : "rejeitada"} nas últimas 24 h`;
      }
      if (a.assunto === "sistema") return `a manhã de ${ddmm(a.dia)} não chegou (WhatsApp fora do ar)`;
      return limpar(texto) || "um aviso do vigia";
    }
    default:
      return limpar(texto) || `um aviso (${a.fonte})`;
  }
}

/** O telefone de um assunto "contato:<telefone>" (null para os outros). */
export function foneDoAssunto(assunto: string): string | null {
  const m = /^contato:(\d{8,15})$/.exec(assunto);
  return m ? m[1] : null;
}

export interface PlanoDoGuardado {
  /** as linhas do bloco (fora o escritório), na ordem */
  linhas: string[];
  /** as linhas que vão na linha do escritório (só o fechamento as leva) */
  escritorio: string[];
  /** ids que a mensagem leva (com linha ou cobertos por um item) — o escritório só se a mensagem sair com ele */
  mostrados: string[];
  /** ids do escritório (marcados só quando o fechamento não ficou calado) */
  doEscritorio: string[];
  /** ids que deixaram de ser verdade (D8 = some) */
  resolvidos: string[];
  /** quantos ficaram para a próxima (passaram do máximo de linhas) */
  restantes: number;
}

/**
 * Do guardado ao que a mensagem mostra. `resolvidosAgora` = os que deixaram de ser verdade; `cobertos` = telefones
 * que já são item com letra na mensagem (um assunto aparece uma vez: o aviso vai junto, sem linha própria);
 * `max` = linhas no bloco (o resto espera a próxima mensagem fixa — nada é descartado).
 */
export function planoDoGuardado(p: {
  avisos: AvisoGuardado[];
  mensagem: MensagemFixa;
  hoje: string;
  resolvidosAgora: Set<string>;
  regras: Pick<RegrasDaVozUnica, "guardado_resolvido">;
  cobertos?: Set<string>;
  max?: number;
}): PlanoDoGuardado {
  const max = p.max ?? 3;
  const plano: PlanoDoGuardado = { linhas: [], escritorio: [], mostrados: [], doEscritorio: [], resolvidos: [], restantes: 0 };
  const vistos = new Set<string>();
  for (const a of p.avisos) {
    const resolvido = p.resolvidosAgora.has(a.id);
    if (resolvido && p.regras.guardado_resolvido === "some") {
      plano.resolvidos.push(a.id);
      continue;
    }
    const sufixo = resolvido ? " (já se resolveu)" : "";
    if (a.destino === "escritorio") {
      if (p.mensagem !== "fechamento") continue; // o escritório só sai no fechamento
      plano.escritorio.push(linhaDoGuardado(a, p.hoje) + sufixo);
      plano.doEscritorio.push(a.id);
      continue;
    }
    const fone = foneDoAssunto(a.assunto);
    if (fone && p.cobertos?.has(fone)) {
      plano.mostrados.push(a.id);
      continue;
    }
    const linha = linhaDoGuardado(a, p.hoje) + sufixo;
    // o mesmo assunto duas vezes (dois avisos do mesmo contato no dia): uma linha só
    const chave = fone ? `fone:${fone}` : linha;
    if (vistos.has(chave)) {
      plano.mostrados.push(a.id);
      continue;
    }
    if (plano.linhas.length >= max) {
      plano.restantes++;
      continue;
    }
    vistos.add(chave);
    plano.linhas.push(linha);
    plano.mostrados.push(a.id);
  }
  return plano;
}

/** "Guardei 2 avisos para não te interromper: X; Y." (manhã) — null sem linhas. */
export function blocoDaManha(plano: PlanoDoGuardado, curto = false): string | null {
  if (!plano.linhas.length) return null;
  const n = plano.linhas.length + plano.restantes;
  const linhas = curto ? plano.linhas.slice(0, 1).map((l) => umaLinha(l, 60)) : plano.linhas;
  const resto = n - linhas.length;
  return `Guardei ${n === 1 ? "1 aviso" : `${n} avisos`} para não te interromper: ${linhas.join("; ")}` +
    `${resto > 0 ? `; e mais ${resto} na próxima mensagem` : ""}.`;
}

/** Domingo e feriado: "1 coisa ficou de ontem: X." — null sem linhas. */
export function blocoDaFolga(plano: PlanoDoGuardado): string | null {
  if (!plano.linhas.length) return null;
  const n = plano.linhas.length + plano.restantes;
  return `${n === 1 ? "1 coisa ficou" : `${n} coisas ficaram`} de ontem: ${plano.linhas.join("; ")}.`;
}

/** "Não te interrompi com: X; Y." (fechamento e revisões) — null sem linhas. */
export function blocoDoFechamento(plano: PlanoDoGuardado, curto = false): string | null {
  if (!plano.linhas.length) return null;
  const linhas = curto ? plano.linhas.slice(0, 2).map((l) => umaLinha(l, 60)) : plano.linhas;
  const resto = plano.linhas.length + plano.restantes - linhas.length;
  return `Não te interrompi com: ${linhas.join("; ")}${resto > 0 ? `; e mais ${resto}` : ""}.`;
}

// ─── O banco ────────────────────────────────────────────────────────────────────────────────────

/** O que o portão guardou para esta mensagem. null = erro (sem bloco; o guardado espera a próxima). */
export async function lerGuardado(admin: Db, p: { phone: string; modo: ModoDoPortao; mensagem: MensagemFixa; agora: Date }): Promise<AvisoGuardado[] | null> {
  try {
    const { data, error } = await admin.rpc("avisos_para_a_mensagem", {
      p: { phone: p.phone, modo: p.modo, mensagem: p.mensagem, agora: p.agora.toISOString() },
    });
    if (error || !data?.ok) {
      console.warn("[uma-voz] guardado não lido:", error?.message ?? data?.erro ?? "sem ok");
      return null;
    }
    return (Array.isArray(data.avisos) ? data.avisos : []) as AvisoGuardado[];
  } catch (e) {
    console.warn("[uma-voz] guardado não lido:", (e as Error)?.message ?? e);
    return null;
  }
}

/**
 * D8 — o que deixou de ser verdade antes da mensagem: o contato que já foi respondido (saída para ele depois da
 * mensagem que gerou o aviso) e a NF-e que não está mais rejeitada. Erro = nenhum (mostra; melhor a mais que calar).
 */
export async function quaisSeResolveram(admin: Db, avisos: AvisoGuardado[]): Promise<Set<string>> {
  const resolvidos = new Set<string>();
  const porFone = new Map<string, AvisoGuardado[]>();
  for (const a of avisos) {
    const f = foneDoAssunto(a.assunto);
    if (f) porFone.set(f, [...(porFone.get(f) ?? []), a]);
  }
  try {
    if (porFone.size) {
      const desde = avisos.map((a) => Date.parse(a.registrado_em)).filter((t) => !Number.isNaN(t))
        .reduce((m, t) => Math.min(m, t), Date.now()) - 3 * 86_400_000;
      const { data, error } = await admin.from("whatsapp_messages").select("phone_normalized, occurred_at")
        .eq("direction", "outbound").in("phone_normalized", [...porFone.keys()]).gte("occurred_at", new Date(desde).toISOString())
        .order("occurred_at", { ascending: false }).limit(500);
      if (error) throw error;
      const ultima = new Map<string, number>();
      for (const m of (data ?? []) as Array<{ phone_normalized: string; occurred_at: string }>) {
        const t = Date.parse(m.occurred_at);
        if (!ultima.has(m.phone_normalized) || ultima.get(m.phone_normalized)! < t) ultima.set(m.phone_normalized, t);
      }
      for (const [fone, lista] of porFone) {
        const saida = ultima.get(fone);
        if (saida === undefined) continue;
        for (const a of lista) {
          const base = typeof a.dados?.mensagem_em === "string" ? Date.parse(a.dados.mensagem_em as string) : Date.parse(a.registrado_em);
          if (!Number.isNaN(base) && saida > base) resolvidos.add(a.id);
        }
      }
    }
  } catch (e) {
    console.warn("[uma-voz] conferência do guardado (contatos) falhou:", (e as Error)?.message ?? e);
  }
  try {
    const notas = avisos.filter((a) => typeof a.dados?.nota_id === "string");
    if (notas.length) {
      const { data, error } = await admin.from("issued_fiscal_documents").select("id, status")
        .in("id", notas.map((a) => a.dados!.nota_id as string));
      if (error) throw error;
      const status = new Map(((data ?? []) as Array<{ id: string; status: string }>).map((n) => [String(n.id), n.status]));
      for (const a of notas) {
        const st = status.get(String(a.dados!.nota_id));
        if (st && st !== "rejected") resolvidos.add(a.id);
      }
    }
  } catch (e) {
    console.warn("[uma-voz] conferência do guardado (notas) falhou:", (e as Error)?.message ?? e);
  }
  return resolvidos;
}

/**
 * Depois que a mensagem fixa foi gravada (sombra) ou enfileirada (ligado): os resolvidos somem (aviso_resolver) e
 * os mostrados ficam marcados (avisos_incluir_na_mensagem; sem fila = a sombra: "incluido", nunca "entregue").
 * Nunca lança.
 */
export async function marcarNaMensagem(admin: Db, p: {
  phone: string;
  modo: ModoDoPortao;
  mostrados: string[];
  resolvidos: string[];
  filaId?: string | null;
  agora?: Date;
}): Promise<{ incluidos: number; resolvidos: number }> {
  const r = { incluidos: 0, resolvidos: 0 };
  try {
    if (p.resolvidos.length) {
      const { data, error } = await admin.rpc("aviso_resolver", { p: { phone: p.phone, modo: p.modo, ids: p.resolvidos, motivo: "ja_resolvido" } });
      if (error) throw error;
      r.resolvidos = Number(data?.resolvidos ?? 0);
    }
    if (p.mostrados.length) {
      const { data, error } = await admin.rpc("avisos_incluir_na_mensagem", {
        p: {
          phone: p.phone, modo: p.modo, ids: p.mostrados,
          ...(p.filaId ? { fila_id: p.filaId } : {}),
          ...(p.agora ? { agora: p.agora.toISOString() } : {}),
        },
      });
      if (error) throw error;
      r.incluidos = Number(data?.incluidos ?? 0);
    }
  } catch (e) {
    console.warn("[uma-voz] guardado não marcado na mensagem:", (e as Error)?.message ?? e);
  }
  return r;
}


/**
 * (16/10/2026) Os contatos que o portão acordou HOJE (assunto contato:<telefone>, situação 'acordou'): telefone → a hora
 * do acorde. O fechamento os cita na linha "Sem resposta desde hoje" se continuam sem resposta. Erro = vazio.
 */
export async function acordadosDeHoje(admin: Db, p: { phone: string; modo: ModoDoPortao; dia: string }): Promise<Map<string, string>> {
  const m = new Map<string, string>();
  try {
    const { data, error } = await admin.from("avisos_do_dono").select("assunto, registrado_em")
      .eq("phone_normalized", p.phone).eq("modo", p.modo).eq("dia", p.dia).eq("situacao", "acordou")
      .like("assunto", "contato:%").order("registrado_em", { ascending: true }).limit(20);
    if (error) throw error;
    for (const a of (data ?? []) as Array<{ assunto: string; registrado_em: string }>) {
      const f = foneDoAssunto(a.assunto);
      if (f && !m.has(f)) m.set(f, a.registrado_em);
    }
  } catch (e) {
    console.warn("[uma-voz] acordes de hoje não lidos:", (e as Error)?.message ?? e);
  }
  return m;
}
