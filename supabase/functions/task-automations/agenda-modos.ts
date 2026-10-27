// Os modos da Agenda de Produção, lidos uma vez por rodada do motor de 15 min (Fase 2, P3 — 24/10/2026).
//
// O interruptor da regra antiga é o mesmo da substituta (spec-fase2 §3.3 d8, decisão d13 do dono): com
// agenda_config.modo_proposta = 'ligado' a agenda marca as OS e diz o que comprar — a R1 e a R16 param de criar tarefa e
// as vivas se resolvem sozinhas; com modo_vigia = 'ligado' a vigia pergunta quando a OS para — a R2 para. Assim é
// impossível ficar com as duas (o dono ouviria a mesma coisa duas vezes) ou com nenhuma.
//
// Leitura que falha aqui NÃO desliga nada: erro, linha ausente ou valor estranho = 'desligado', ou seja, as regras ficam
// como hoje (o lado seguro: no máximo o dono recebe a tarefa antiga). O erro volta em `erro` para entrar no resumo da
// rodada; quem registra em app_error_logs é a vigia, que lê a mesma tabela e falha junto.

// deno-lint-ignore no-explicit-any
type Db = any;

export type ModoDaAgenda = "desligado" | "sombra" | "ligado";

export interface ModosDaAgenda {
  /** agenda_config.modo_proposta: o que o motor FAZ (publicar, replanejar, status, datas). */
  proposta: ModoDaAgenda;
  /** agenda_config.modo_vigia: o que o sistema DIZ sozinho (perguntas, acorde). */
  vigia: ModoDaAgenda;
  /** A leitura falhou (as regras ficam como hoje). */
  erro?: string;
  /** (Fase 5, P3) o modo da mensagem ao cliente, lido à parte (lerModosDoCliente): a R15 sai com a confirmação ligada. */
  cliente?: ModosDoCliente;
}

export const MODOS_DESLIGADOS: Readonly<ModosDaAgenda> = Object.freeze({ proposta: "desligado", vigia: "desligado" });

/** 'ligado', ' Sombra ', '"sombra"' → o modo; qualquer outra coisa → 'desligado'. */
export function lerModo(v: unknown): ModoDaAgenda {
  const s = typeof v === "string" ? v.trim().replace(/^"(.*)"$/, "$1").trim().toLowerCase() : "";
  return s === "sombra" || s === "ligado" ? s : "desligado";
}

/** Um SELECT em agenda_config. Nunca lança: erro = desligado (com o motivo em `erro`). */
export async function lerModosDaAgenda(db: Db): Promise<ModosDaAgenda> {
  try {
    const { data, error } = await db.from("agenda_config").select("modo_proposta, modo_vigia").maybeSingle();
    if (error) return { ...MODOS_DESLIGADOS, erro: String(error.message ?? error.code ?? "erro na leitura") };
    if (!data) return { ...MODOS_DESLIGADOS, erro: "agenda_config sem a linha de parâmetros" };
    return { proposta: lerModo(data.modo_proposta), vigia: lerModo(data.modo_vigia) };
  } catch (e) {
    return { ...MODOS_DESLIGADOS, erro: String((e as Error)?.message ?? e) };
  }
}

// ── Fase 3 (P4, 24/10/2026): os modos da equipe e da diária ─────────────────────────────────────────────
// Lidos num SELECT à parte: a coluna modo_diaria só existe com a migration 20261026100000, e um SELECT que falhasse por
// ela não pode derrubar os modos da Fase 2 (a R1, a R2 e a R16 voltariam com a agenda ligada). Ilegível = desligado e a
// rotina não roda.
// Revisão da Fase 3 (C1, R4): para a R10 o lado seguro depende do erro. Coluna ou tabela que ainda não existe (PGRST204,
// 42703, PGRST205, 42P01: a migration da Fase 3 não foi aplicada, a ficha não existe) ou a linha que falta = a R10 segue
// como hoje. Qualquer outro erro (a rede, o tempo, a permissão) = a R10 PULA aquele tique: com a ficha talvez ligada, o
// técnico receberia as duas. Nos dois casos o erro vai a app_error_logs (index.ts, action agenda:r10).

export interface ModosDaEquipe {
  /** agenda_config.modo_equipe: a ficha, a confirmação e o "como foi hoje?" (em ligado a R10 para). */
  equipe: ModoDaAgenda;
  /** agenda_config.modo_diaria: a diária automática. */
  diaria: ModoDaAgenda;
  /** A leitura falhou (o motivo). */
  erro?: string;
  /** (C1, R4) o código do erro da leitura (PostgREST/Postgres), ou SEM_LINHA / EXCECAO */
  codigo?: string;
}

export const EQUIPE_DESLIGADA: Readonly<ModosDaEquipe> = Object.freeze({ equipe: "desligado", diaria: "desligado" });

/** Um SELECT em agenda_config (modo_equipe, modo_diaria). Nunca lança: erro = desligado (com o motivo em `erro`). */
export async function lerModosDaEquipe(db: Db): Promise<ModosDaEquipe> {
  try {
    const { data, error } = await db.from("agenda_config").select("modo_equipe, modo_diaria").maybeSingle();
    if (error) {
      return {
        ...EQUIPE_DESLIGADA,
        erro: String(error.message ?? error.code ?? "erro na leitura"),
        codigo: String(error.code ?? "") || "SEM_CODIGO",
      };
    }
    if (!data) return { ...EQUIPE_DESLIGADA, erro: "agenda_config sem a linha de parâmetros", codigo: "SEM_LINHA" };
    return { equipe: lerModo(data.modo_equipe), diaria: lerModo(data.modo_diaria) };
  } catch (e) {
    return { ...EQUIPE_DESLIGADA, erro: String((e as Error)?.message ?? e), codigo: "EXCECAO" };
  }
}

/** (C1, R4) Os códigos de "a coluna ou a tabela ainda não existe" (a Fase 3 não foi aplicada) e a linha que falta. */
const LEITURA_SEM_A_FASE_3: ReadonlySet<string> = new Set(["PGRST204", "42703", "PGRST205", "42P01", "SEM_LINHA"]);

/** (C1, R4) O texto do resumo quando a R10 pula o tique porque o modo da equipe não foi lido. */
export const R10_PULADA = "pulada: não consegui ler o modo da equipe (a ficha pode estar ligada)";

/** O texto do resumo quando a R10 sai (spec-fase3 §7.6, d15): a ficha das 19:30 a substitui no instante em que liga. */
export const R10_DESLIGADA = "desligada: a ficha da agenda substitui";

/**
 * A R10 (o lembrete interno de OS agendada) sai no mesmo instante em que a ficha da agenda liga (modo_equipe = 'ligado';
 * decisão d13 do dono: a regra antiga sai no dia em que a substituta entra). Sombra e desligado = a R10 continua.
 */
export function r10DesligadaPelaAgenda(m: Pick<ModosDaEquipe, "equipe" | "erro" | "codigo">): string | null {
  if (m.equipe === "ligado") return R10_DESLIGADA;
  // (C1, R4) a leitura que falhou por outro motivo que não a Fase 3 ausente: a R10 pula este tique
  if (m.erro !== undefined && !LEITURA_SEM_A_FASE_3.has(m.codigo ?? "")) return R10_PULADA;
  return null;
}

// ── Fase 4 (P5, 25/10/2026): os modos do material (a nota, o Pix, o detector e a mensagem ao fornecedor) ─────────────
// Lidos num SELECT à parte, como os da equipe: as colunas só existem com a migration 20261027100000, e um SELECT que
// falhasse por elas não pode derrubar os modos das Fases 2 e 3. Ilegível = desligado e o passo do material não chama o
// banco (o lado seguro: nada é gravado e nada sai ao fornecedor).

export interface ModosDoMaterial {
  /** agenda_config.modo_material: a nota, o Pix, as perguntas de material e de cadastro. */
  material: ModoDaAgenda;
  /** agenda_config.modo_detector: a leitura da conversa do fornecedor. */
  detector: ModoDaAgenda;
  /** agenda_config.modo_fornecedor: a mensagem-modelo ao fornecedor nos terços do prazo. */
  fornecedor: ModoDaAgenda;
  /** A leitura falhou (o motivo). */
  erro?: string;
  /** O código do erro da leitura (PostgREST/Postgres), ou SEM_LINHA / EXCECAO. */
  codigo?: string;
}

export const MATERIAL_DESLIGADO: Readonly<ModosDoMaterial> = Object.freeze({
  material: "desligado",
  detector: "desligado",
  fornecedor: "desligado",
});

/** Um SELECT em agenda_config (modo_material, modo_detector, modo_fornecedor). Nunca lança: erro = desligado. */
export async function lerModosDoMaterial(db: Db): Promise<ModosDoMaterial> {
  try {
    const { data, error } = await db.from("agenda_config").select("modo_material, modo_detector, modo_fornecedor").maybeSingle();
    if (error) {
      return {
        ...MATERIAL_DESLIGADO,
        erro: String(error.message ?? error.code ?? "erro na leitura"),
        codigo: String(error.code ?? "") || "SEM_CODIGO",
      };
    }
    if (!data) return { ...MATERIAL_DESLIGADO, erro: "agenda_config sem a linha de parâmetros", codigo: "SEM_LINHA" };
    return { material: lerModo(data.modo_material), detector: lerModo(data.modo_detector), fornecedor: lerModo(data.modo_fornecedor) };
  } catch (e) {
    return { ...MATERIAL_DESLIGADO, erro: String((e as Error)?.message ?? e), codigo: "EXCECAO" };
  }
}

/** (P5) A leitura falhou porque a Fase 4 ainda não está no banco: a coluna ou a tabela que não existe, a linha que falta. */
export function leituraSemAFase4(m: Pick<ModosDoMaterial, "erro" | "codigo">): boolean {
  return m.erro !== undefined && LEITURA_SEM_A_FASE_3.has(m.codigo ?? "");
}

// ── Fase 5 (P3, 27/10/2026): o modo da mensagem ao cliente e a R15 ──────────────────────────────────────────────────
// Lido num SELECT à parte, como os da equipe e do material: as colunas (cliente_tipos_ligados) só existem com a migration
// 20261028100000, e um SELECT que falhasse por elas não pode derrubar os modos das Fases 2 a 4. Ilegível = desligado: a
// R15 (a tarefa "Confirmar com fulano", que só envia com o clique do dono) continua como hoje — o lado seguro, porque
// sem ela ninguém confirmaria com o cliente.

export interface ModosDoCliente {
  /** agenda_config.modo_cliente: a agenda manda ao cliente as mensagens-modelo (desligado | sombra | ligado). */
  cliente: ModoDaAgenda;
  /** agenda_config.cliente_tipos_ligados: os tipos das ondas que já saem (os outros ficam em teste). */
  tipos: string[];
  /** A leitura falhou (o motivo). */
  erro?: string;
  /** O código do erro da leitura (PostgREST/Postgres), ou SEM_LINHA / EXCECAO. */
  codigo?: string;
}

export const CLIENTE_DESLIGADO: Readonly<ModosDoCliente> = Object.freeze({ cliente: "desligado", tipos: [] as string[] });

/** Um SELECT em agenda_config (modo_cliente, cliente_tipos_ligados). Nunca lança: erro = desligado (com o motivo). */
export async function lerModosDoCliente(db: Db): Promise<ModosDoCliente> {
  try {
    const { data, error } = await db.from("agenda_config").select("modo_cliente, cliente_tipos_ligados").maybeSingle();
    if (error) {
      return {
        cliente: "desligado", tipos: [],
        erro: String(error.message ?? error.code ?? "erro na leitura"),
        codigo: String(error.code ?? "") || "SEM_CODIGO",
      };
    }
    if (!data) return { cliente: "desligado", tipos: [], erro: "agenda_config sem a linha de parâmetros", codigo: "SEM_LINHA" };
    const tipos = Array.isArray(data.cliente_tipos_ligados)
      ? data.cliente_tipos_ligados.filter((t: unknown): t is string => typeof t === "string").map((t: string) => t.trim())
      : [];
    return { cliente: lerModo(data.modo_cliente), tipos };
  } catch (e) {
    return { cliente: "desligado", tipos: [], erro: String((e as Error)?.message ?? e), codigo: "EXCECAO" };
  }
}

/** O motivo da R15 resolvida pela agenda (vai para o notes da tarefa viva que se resolve). */
export const R15_DESLIGADA = "a confirmação com o cliente agora é da agenda";

/**
 * A R15 sai no mesmo instante em que a confirmação da agenda liga — a onda 2 (modo_cliente = 'ligado' E 'confirmar' em
 * cliente_tipos_ligados; decisão d13 do dono: a regra antiga sai no dia em que a substituta entra). Sombra, desligado, a
 * confirmação fora das ondas ou o modo ilegível = a R15 continua (o dono confirma pelo botão, como hoje).
 */
export function r15DesligadaPelaAgenda(m: Pick<ModosDoCliente, "cliente" | "tipos"> | null | undefined): boolean {
  return !!m && m.cliente === "ligado" && Array.isArray(m.tipos) && m.tipos.includes("confirmar");
}
