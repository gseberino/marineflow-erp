// Uma voz só (secretário, Passo 4, 15/10/2026): a ponte das fontes com o portão (aviso_registrar).
//
// Regra de ouro desta publicação (P4.1 em sombra): registrar NUNCA muda o que a fonte manda e NUNCA
// derruba a fonte. Erro na leitura das chaves = desligado (nada é registrado); erro no registro = um
// aviso no log e segue. Com voz_unica = desligado a única coisa a mais é a leitura das chaves.

import {
  CHAVE_FREIO, CHAVE_REGRAS, CHAVE_VOZ_UNICA, lerFreio, lerRegras, lerVozUnica, modoDoRegistro, type AvisoDaFonte,
  type ModoDoPortao, pedidoAoPortao, type RegrasDaVozUnica, type RespostaDoPortao, REGRAS_PADRAO, type VozUnica,
} from "./portao.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export interface PortaoDaRodada {
  voz: VozUnica;
  /** null = as fontes não registram (voz_unica desligado). */
  modo: ModoDoPortao | null;
  regras: RegrasDaVozUnica;
  /** O freio do acompanhamento (P4.3) está ligado. */
  freio: boolean;
}

export const PORTAO_DESLIGADO: Readonly<PortaoDaRodada> = Object.freeze({
  voz: "desligado", modo: null, regras: { ...REGRAS_PADRAO }, freio: false,
});

/**
 * acompanhar-conversas: em que modo o aviso que SAIU é registrado no portão. Com a voz única ligada
 * (sombra), sempre; com ela desligada, só o do modo acompanhar e só com o freio ligado (é a conta do
 * freio). null = não registra (voz desligada e freio desligado: nada muda).
 */
export function modoDoRegistroDoAcompanhamento(
  portao: Pick<PortaoDaRodada, "modo" | "freio">,
  modo: "acompanhar" | "lembrar_em" | "promessa",
): ModoDoPortao | null {
  if (portao.modo) return portao.modo;
  return modo === "acompanhar" && portao.freio ? "sombra" : null;
}

/** As chaves do portão a partir das configurações já lidas pela função (chave → valor). */
export function portaoDasConfiguracoes(settings: Record<string, unknown>): PortaoDaRodada {
  const voz = lerVozUnica(settings[CHAVE_VOZ_UNICA]);
  return { voz, modo: modoDoRegistro(voz), regras: lerRegras(settings[CHAVE_REGRAS]), freio: lerFreio(settings[CHAVE_FREIO]) };
}

/** Lê as três chaves num SELECT só. Nunca lança: erro = desligado (e freio desligado). */
export async function lerPortao(admin: Db): Promise<PortaoDaRodada> {
  try {
    const { data, error } = await admin.from("app_settings").select("key, value").in("key", [CHAVE_VOZ_UNICA, CHAVE_REGRAS, CHAVE_FREIO]);
    if (error) return { ...PORTAO_DESLIGADO, regras: { ...REGRAS_PADRAO } };
    const s: Record<string, unknown> = {};
    for (const r of (data ?? []) as Array<{ key: string; value: unknown }>) s[r.key] = r.value;
    return portaoDasConfiguracoes(s);
  } catch {
    return { ...PORTAO_DESLIGADO, regras: { ...REGRAS_PADRAO } };
  }
}

/**
 * Registra um aviso no portão. `modo` null = não faz nada (voz_unica desligado). Devolve a resposta do
 * portão, ou null quando não registrou (desligado ou erro). Nunca lança.
 */
export async function registrarNoPortao(
  admin: Db,
  modo: ModoDoPortao | null,
  phone: string | null | undefined,
  aviso: AvisoDaFonte,
  agora?: Date,
): Promise<RespostaDoPortao | null> {
  if (!modo || !phone) return null;
  try {
    const { data, error } = await admin.rpc("aviso_registrar", { p: pedidoAoPortao(phone, modo, aviso, agora) });
    if (error) {
      console.warn(`[uma-voz] o portão não registrou ${aviso.fonte}/${aviso.chave}:`, error.message ?? error);
      return null;
    }
    return (data ?? null) as RespostaDoPortao | null;
  } catch (e) {
    console.warn(`[uma-voz] o portão não registrou ${aviso.fonte}/${aviso.chave}:`, (e as Error)?.message ?? e);
    return null;
  }
}

/** O mesmo aviso para vários telefones (o vigia e os saldos mandam a admin e financeiro). Nunca lança. */
export async function registrarParaTodos(
  admin: Db,
  modo: ModoDoPortao | null,
  phones: Array<string | null | undefined>,
  avisos: AvisoDaFonte[],
  agora?: Date,
): Promise<number> {
  if (!modo || !avisos.length) return 0;
  let n = 0;
  for (const phone of new Set(phones.filter((p): p is string => typeof p === "string" && p.length > 0))) {
    for (const a of avisos) if (await registrarNoPortao(admin, modo, phone, a, agora)) n++;
  }
  return n;
}

/**
 * Quantos avisos de acompanhamento já saíram sobre esta mensagem do contato (a referência
 * acomp:<id>:<última recebida>), em qualquer modo. null = não deu para contar (o freio não age: avisar
 * a mais é melhor que calar por um erro de leitura).
 */
export async function avisosDestaMensagem(admin: Db, referencia: string): Promise<number | null> {
  try {
    const { count, error } = await admin.from("avisos_do_dono").select("id", { count: "exact", head: true })
      .eq("fonte", "acompanhar").eq("referencia", referencia);
    if (error) return null;
    return typeof count === "number" ? count : null;
  } catch {
    return null;
  }
}
