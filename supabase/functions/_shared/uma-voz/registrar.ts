// Uma voz só (secretário, Passo 4, 15/10/2026): a ponte das fontes com o portão (aviso_registrar).
//
// Regra de ouro da sombra (P4.1): registrar NUNCA muda o que a fonte manda e NUNCA derruba a fonte. Erro na
// leitura das chaves = desligado (nada é registrado); erro no registro = um aviso no log e segue. Com
// voz_unica = desligado a única coisa a mais é a leitura das chaves.
//
// (20/10/2026, P4.5) Com a voz única LIGADA de verdade (vozEfetiva: a manhã nova e o fechamento ligado no ar), só o
// telefone do DONO passa pelo portão, e ANTES de mandar (perguntarAoPortao → Fala): 'acordar' e 'deixar' mandam;
// 'guardar', 'acabar' e 'repetido' não; portão ilegível = manda como sempre (nunca calar por erro). O acorde que vai
// pela fila leva dedupe_key 'aviso:<id>' (linhaDoAcordeNaFila): se a fila desistir, a próxima mensagem fixa o devolve
// a guardado e o leva (avisos_para_a_mensagem, migration 20261020200000). Envio síncrono que falhou → reabrirNoPortao.
// A equipe (os outros telefones) recebe o de sempre e não é registrada no modo ligado.

import {
  type AvisoDaFonte, CHAVE_FREIO, CHAVE_REGRAS, CHAVE_VOZ_UNICA, CHAVES_DOS_CONSUMIDORES, type Decisao, lerFreio, lerRegras,
  lerVozUnica, type ModoDoPortao, modoDoRegistro, pedidoAoPortao, type RegrasDaVozUnica, REGRAS_PADRAO, type RespostaDoPortao,
  vozEfetiva, type VozUnica,
} from "./portao.ts";
import { tentativasAteAs20h } from "./janela.ts";
import { type Dono, donoDoWhatsApp } from "../whatsapp/dono.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export interface PortaoDaRodada {
  /** O valor da chave voz_unica (o que o dono escolheu). */
  voz: VozUnica;
  /**
   * O modo que vale (vozEfetiva): null = as fontes não registram (desligado); 'sombra' = registram depois de mandar;
   * 'ligado' = o dono só ouve pelo portão. 'ligado' sem a manhã nova e o fechamento ligado vira 'sombra'.
   */
  modo: ModoDoPortao | null;
  regras: RegrasDaVozUnica;
  /** O freio do acompanhamento (P4.3) está ligado. */
  freio: boolean;
}

export const PORTAO_DESLIGADO: Readonly<PortaoDaRodada> = Object.freeze({
  voz: "desligado", modo: null, regras: { ...REGRAS_PADRAO }, freio: false,
});

/**
 * acompanhar-conversas: em que modo o aviso é registrado no portão. Com a voz única em sombra, sempre (depois de
 * sair); (20/10/2026) ligada, o aviso ao DONO (peloPortao) é registrado ANTES, em 'ligado' (perguntarAoPortao); o de
 * outro telefone segue como se a voz estivesse desligada. Desligada: só o do modo acompanhar e só com o freio ligado
 * (é a conta do freio), em 'sombra'. null = não registra (nada muda).
 */
export function modoDoRegistroDoAcompanhamento(
  portao: Pick<PortaoDaRodada, "modo" | "freio">,
  modo: "acompanhar" | "lembrar_em" | "promessa",
  peloPortao = false,
): ModoDoPortao | null {
  if (portao.modo === "sombra") return "sombra";
  if (portao.modo === "ligado" && peloPortao) return "ligado";
  return modo === "acompanhar" && portao.freio ? "sombra" : null;
}

/**
 * As chaves do portão a partir das configurações já lidas pela função (chave → valor). Quem lê as configurações por
 * conta própria precisa trazer também CHAVES_DOS_CONSUMIDORES (a trava do 'ligado'); sem elas, 'ligado' age como
 * 'sombra'.
 */
export function portaoDasConfiguracoes(settings: Record<string, unknown>): PortaoDaRodada {
  const voz = lerVozUnica(settings[CHAVE_VOZ_UNICA]);
  const efetiva = vozEfetiva(voz, { manha: settings[CHAVES_DOS_CONSUMIDORES[0]], fechamento: settings[CHAVES_DOS_CONSUMIDORES[1]] });
  return { voz, modo: modoDoRegistro(efetiva), regras: lerRegras(settings[CHAVE_REGRAS]), freio: lerFreio(settings[CHAVE_FREIO]) };
}

/** As chaves que lerPortao lê (e que quem monta as configurações à mão tem de trazer). */
export const CHAVES_DO_PORTAO = [CHAVE_VOZ_UNICA, CHAVE_REGRAS, CHAVE_FREIO, ...CHAVES_DOS_CONSUMIDORES] as const;

/** Lê as cinco chaves num SELECT só. Nunca lança: erro = desligado (e freio desligado). */
export async function lerPortao(admin: Db): Promise<PortaoDaRodada> {
  try {
    const { data, error } = await admin.from("app_settings").select("key, value").in("key", [...CHAVES_DO_PORTAO]);
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

/**
 * O mesmo aviso para vários telefones (o vigia e os saldos mandam a admin e financeiro), DEPOIS de mandar. Só na
 * sombra: (20/10/2026) com a voz ligada quem fala com o dono pergunta ANTES (perguntarAoPortao) e a equipe não é
 * registrada — um guardado de um telefone que nenhuma mensagem fixa lê nunca chegaria. Nunca lança.
 */
export async function registrarParaTodos(
  admin: Db,
  modo: ModoDoPortao | null,
  phones: Array<string | null | undefined>,
  avisos: AvisoDaFonte[],
  agora?: Date,
): Promise<number> {
  if (modo !== "sombra" || !avisos.length) return 0;
  let n = 0;
  for (const phone of new Set(phones.filter((p): p is string => typeof p === "string" && p.length > 0))) {
    for (const a of avisos) if (await registrarNoPortao(admin, modo, phone, a, agora)) n++;
  }
  return n;
}

/**
 * (16/10/2026, D11) Os acordes de HOJE (dia de Brasília) do mesmo assunto, com os dados (a mensagem que cada um
 * cobriu). null = não deu para ler: quem chama NÃO marca fato novo (como antes — um acorde a menos é melhor que
 * dois sobre a mesma mensagem).
 */
export async function acordesDeHojeDoAssunto(
  admin: Db, p: { phone: string; modo: ModoDoPortao; dia: string; assunto: string },
): Promise<Array<{ dados: Record<string, unknown> | null }> | null> {
  try {
    const { data, error } = await admin.from("avisos_do_dono").select("dados")
      .eq("phone_normalized", p.phone).eq("modo", p.modo).eq("dia", p.dia).eq("assunto", p.assunto).eq("situacao", "acordou")
      .limit(20);
    if (error) return null;
    return (data ?? []) as Array<{ dados: Record<string, unknown> | null }>;
  } catch {
    return null;
  }
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

// ─── (20/10/2026, P4.5) A voz única ligada de verdade ───────────────────────────────────────────

/** O que a fonte faz com o aviso do dono, pela resposta do portão (pura). */
export interface Fala {
  /** manda agora: 'acordar', 'deixar' (pedido do próprio dono) ou portão ilegível (como sempre) */
  manda: boolean;
  /** o acorde pode levar cartão de sim/não (só depois das 09:30) */
  cartao: boolean;
  /** o id do aviso que acordou: se o envio falhar, reabrirNoPortao; vai na dedupe_key da fila */
  acordou: string | null;
  /** o que o portão decidiu; 'erro' = sem resposta legível (a fonte manda como sempre) */
  decisao: Decisao | "erro";
}

/**
 * A resposta do portão → a fala. Sem resposta, ok=false ou decisão desconhecida = 'erro' (manda como sempre: nunca
 * calar por erro). 'repetido' não manda (a mesma chave já passou — já acordou, já está guardada ou já acabou), salvo
 * se antes foi 'deixar' (o alarme do dono que voltou a tocar com a mesma chave).
 */
export function falaDoPortao(r: RespostaDoPortao | null): Fala {
  const erro: Fala = { manda: true, cartao: false, acordou: null, decisao: "erro" };
  if (!r || r.ok !== true) return erro;
  switch (r.decisao) {
    case "acordar":
      return { manda: true, cartao: r.cartao === true, acordou: typeof r.id === "string" ? r.id : null, decisao: "acordar" };
    case "deixar":
      return { manda: true, cartao: false, acordou: null, decisao: "deixar" };
    case "guardar":
    case "acabar":
      return { manda: false, cartao: false, acordou: null, decisao: r.decisao };
    case "repetido":
      return { manda: (r as { antes?: unknown }).antes === "deixar", cartao: false, acordou: null, decisao: "repetido" };
    default:
      return erro;
  }
}

/** Pergunta ao portão (modo ligado) ANTES de mandar ao dono. Nunca lança (erro = manda como sempre). */
export async function perguntarAoPortao(admin: Db, phone: string, aviso: AvisoDaFonte, agora?: Date): Promise<Fala> {
  return falaDoPortao(await registrarNoPortao(admin, "ligado", phone, aviso, agora));
}

/** O acorde não saiu (envio que falhou na hora) → volta a guardado e libera a vaga do dia. Nunca lança. */
export async function reabrirNoPortao(admin: Db, id: string | null | undefined, agora?: Date): Promise<boolean> {
  if (!id) return false;
  try {
    const { data, error } = await admin.rpc("aviso_reabrir", { p: { id, ...(agora ? { agora: agora.toISOString() } : {}) } });
    if (error) {
      console.warn("[uma-voz] aviso não reaberto:", error.message ?? error);
      return false;
    }
    return (data as { resultado?: string } | null)?.resultado === "reaberto";
  } catch (e) {
    console.warn("[uma-voz] aviso não reaberto:", (e as Error)?.message ?? e);
    return false;
  }
}

/** O dono da voz (o mesmo da manhã: donoDoWhatsApp). Nunca lança: erro = null (ninguém passa pelo portão). */
export async function lerDonoDaVoz(admin: Db): Promise<Dono | null> {
  try {
    return await donoDoWhatsApp(admin);
  } catch {
    return null;
  }
}

/** Este telefone só ouve pelo portão: a voz ligada de verdade e é o dono. */
export function falaPeloPortao(portao: Pick<PortaoDaRodada, "modo">, dono: Dono | null | undefined, phone: string | null | undefined): boolean {
  return portao.modo === "ligado" && !!dono && !!phone && String(phone) === dono.phone;
}

/** A chave da fila do acorde: uma linha por aviso (a fila recusa a 2ª) e o elo para a conferência da entrega. */
export function chaveDaFilaDoAcorde(avisoId: string): string {
  return `aviso:${avisoId}`;
}

/**
 * A linha da fila de um acorde: prioridade 1, tentativas só até as 20h (o acorde não entra na noite; se a fila
 * desistir, a próxima mensagem fixa o leva) e a chave aviso:<id>.
 */
export function linhaDoAcordeNaFila(p: { phone: string; texto: string; avisoId: string; agora: Date; source: string }): Record<string, unknown> {
  return {
    phone_normalized: p.phone,
    message: p.texto,
    source: p.source,
    priority: 1,
    max_attempts: tentativasAteAs20h(p.agora),
    dedupe_key: chaveDaFilaDoAcorde(p.avisoId),
    source_ref_id: p.avisoId,
  };
}

/**
 * Enfileira o acorde que o portão liberou. Falhou o insert = reabre (volta a guardado, a vaga do dia fica livre).
 * A mesma chave já na fila (23505) = já foi: conta como enfileirado. Nunca lança.
 */
export async function enfileirarAcorde(
  admin: Db, p: { phone: string; texto: string; avisoId: string; agora: Date; source: string },
): Promise<boolean> {
  try {
    const { error } = await admin.from("whatsapp_send_queue").insert(linhaDoAcordeNaFila(p));
    if (!error) return true;
    if ((error as { code?: string }).code === "23505") return true;
    console.warn("[uma-voz] acorde fora da fila:", error.message ?? error);
  } catch (e) {
    console.warn("[uma-voz] acorde fora da fila:", (e as Error)?.message ?? e);
  }
  await reabrirNoPortao(admin, p.avisoId, p.agora);
  return false;
}
