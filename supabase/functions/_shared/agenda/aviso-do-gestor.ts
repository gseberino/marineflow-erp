// O aviso do gestor da agenda ao dono pelo WhatsApp (Agenda de Produção, correção de 29/10, P4) — o MONTADOR.
//
// O banco diz o que contar (agenda_aviso_pecas, migration 20261030100300): o cabeçalho, uma linha por mudança (o texto do
// *o que mudou*: o que marcou ou reservou, quem vai, os dias e o *desfaz*), o que ficou de fora e por quê (curto), o rodapé
// e, uma vez por dia, as perguntas que destravam (o texto da rodada de aprontar). Aqui só se junta, na ordem, e se corta
// pelo teto que o banco manda (agenda_config.gestor_aviso_texto_max). Nenhuma data, nome ou número é calculado aqui: tudo o
// que o dono lê vem pronto do banco.
//
// A ordem do texto:
//   Agenda — o que eu mudei sozinho:
//   • <cada mudança>
//   Ficaram de fora N: … (o porquê numa palavra)
//   *agenda plano* mostra tudo.
//   (linha em branco)
//   <as perguntas da rodada de aprontar>
//
// Quando passa do teto, nesta ordem: 1) sai o que ficou de fora; 2) saem as perguntas (e elas não contam como mostradas);
// 3) saem as últimas mudanças, com "• e mais N mudanças: *o que mudou* mostra todas." — essas contam (o dono sabe que
// existem e tem a palavra que as mostra); 4) a única que sobrou e ainda passa é cortada na palavra, com "…". O texto nunca
// passa do teto.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Uma mudança contada: o texto do banco e as ações dela (as que o aviso conta). */
export interface MudancaDoAviso {
  texto: string;
  acaoIds: string[];
}

/** As perguntas que destravam (o texto da rodada de aprontar) e as perguntas abertas que ele cobre. */
export interface PerguntasDoAviso {
  texto: string;
  perguntaIds: string[];
}

/** As peças que o banco devolve quando é para avisar. */
export interface PecasDoAviso {
  rodada: string;
  dia: string;
  /** o teto do texto (gestor_aviso_texto_max) */
  limite: number;
  cabecalho: string;
  mudancas: MudancaDoAviso[];
  fora: string | null;
  rodape: string | null;
  perguntas: PerguntasDoAviso | null;
  /** a rodada de aprontar falhou no banco (o que mudou sai do mesmo jeito; quem chama registra o erro) */
  perguntasErro?: string | null;
}

/** A resposta de agenda_aviso_pecas, conferida. */
export type RespostaDasPecas =
  | { avisar: true; pecas: PecasDoAviso }
  | { avisar: false; motivo: string; pendentes: number | null };

/** O que vai para a fila. */
export interface AvisoMontado {
  texto: string;
  /** todas as ações das mudanças (também as do "e mais N") */
  acaoIds: string[];
  /** só quando as perguntas foram no texto */
  perguntaIds: string[];
  comPerguntas: boolean;
  /** o que o teto tirou, na ordem */
  cortes: Array<"fora" | "perguntas" | "mudancas" | "linha">;
}

function textoLimpo(v: unknown): string | null {
  return typeof v === "string" && v.trim() ? v.trim() : null;
}

function idsValidos(v: unknown): string[] {
  return Array.isArray(v) ? [...new Set(v.filter((x): x is string => typeof x === "string" && UUID.test(x)))] : [];
}

/**
 * agenda_aviso_pecas → a resposta conferida. null = o formato não é o combinado (quem chama registra o erro e não manda
 * nada). A mudança sem texto ou sem ação válida fica de fora; sem nenhuma mudança que sobre, também null.
 */
export function lerPecasDoAviso(v: unknown): RespostaDasPecas | null {
  const r = v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : null;
  if (!r || typeof r.avisar !== "boolean") return null;
  if (!r.avisar) {
    const motivo = textoLimpo(r.motivo);
    if (!motivo) return null;
    const pend = Number(r.pendentes);
    return { avisar: false, motivo, pendentes: r.pendentes != null && Number.isFinite(pend) ? pend : null };
  }
  const limite = Number(r.limite);
  const cabecalho = textoLimpo(r.cabecalho);
  const rodada = textoLimpo(r.rodada);
  const dia = textoLimpo(r.dia);
  if (!Number.isInteger(limite) || limite <= 0 || !cabecalho || !rodada || !dia || !Array.isArray(r.mudancas)) return null;
  const mudancas = r.mudancas.flatMap((m) => {
    const x = (m ?? {}) as Record<string, unknown>;
    const texto = textoLimpo(x.texto);
    const acaoIds = idsValidos(x.acao_ids);
    return texto && acaoIds.length ? [{ texto, acaoIds }] : [];
  });
  if (!mudancas.length) return null;
  const p = r.perguntas && typeof r.perguntas === "object" ? r.perguntas as Record<string, unknown> : null;
  const textoDasPerguntas = textoLimpo(p?.texto);
  return {
    avisar: true,
    pecas: {
      rodada, dia, limite, cabecalho, mudancas,
      fora: textoLimpo(r.fora),
      rodape: textoLimpo(r.rodape),
      perguntas: textoDasPerguntas ? { texto: textoDasPerguntas, perguntaIds: idsValidos(p?.pergunta_ids) } : null,
      ...(textoLimpo(r.perguntas_erro) ? { perguntasErro: textoLimpo(r.perguntas_erro) } : {}),
    },
  };
}

/** Corta na palavra, com "…", para caber em `max` letras (nunca devolve mais que `max`). */
function cortarNaPalavra(texto: string, max: number): string {
  if (texto.length <= max) return texto;
  if (max <= 1) return "…".slice(0, Math.max(max, 0));
  const pedaco = texto.slice(0, max - 1);
  const ate = pedaco.replace(/\s+\S*$/, "").replace(/[\s,;:.(–—-]+$/, "");
  return `${ate || pedaco}…`;
}

function eMais(n: number): string {
  return `• e mais ${n} ${n === 1 ? "mudança" : "mudanças"}: *o que mudou* mostra todas.`;
}

function juntar(p: PecasDoAviso, o: { fora: boolean; perguntas: boolean; k: number; primeira?: string }): string {
  const n = p.mudancas.length;
  const linhas = [p.cabecalho, ...p.mudancas.slice(0, o.k).map((m, i) => `• ${i === 0 && o.primeira !== undefined ? o.primeira : m.texto}`)];
  if (o.k < n) linhas.push(eMais(n - o.k));
  if (o.fora && p.fora) linhas.push(p.fora);
  if (p.rodape) linhas.push(p.rodape);
  const corpo = linhas.join("\n");
  return o.perguntas && p.perguntas ? `${corpo}\n\n${p.perguntas.texto}` : corpo;
}

/** As peças → o texto do aviso e o que ele conta. null = nada a contar (nenhuma mudança). */
export function montarAvisoDoGestor(p: PecasDoAviso): AvisoMontado | null {
  const n = p.mudancas.length;
  if (!n) return null;
  const acaoIds = [...new Set(p.mudancas.flatMap((m) => m.acaoIds))];
  const pronto = (texto: string, perguntas: boolean, cortes: AvisoMontado["cortes"]): AvisoMontado => ({
    texto,
    acaoIds,
    perguntaIds: perguntas && p.perguntas ? p.perguntas.perguntaIds : [],
    comPerguntas: perguntas && !!p.perguntas,
    cortes,
  });
  const cortes: AvisoMontado["cortes"] = [];
  let t = juntar(p, { fora: true, perguntas: true, k: n });
  if (t.length <= p.limite) return pronto(t, true, cortes);
  // 1) sem o que ficou de fora
  if (p.fora) {
    cortes.push("fora");
    t = juntar(p, { fora: false, perguntas: true, k: n });
    if (t.length <= p.limite) return pronto(t, true, cortes);
  }
  // 2) sem as perguntas
  if (p.perguntas) {
    cortes.push("perguntas");
    t = juntar(p, { fora: false, perguntas: false, k: n });
    if (t.length <= p.limite) return pronto(t, false, cortes);
  }
  // 3) as últimas mudanças viram "e mais N"
  if (n > 1) {
    cortes.push("mudancas");
    for (let k = n - 1; k >= 1; k--) {
      t = juntar(p, { fora: false, perguntas: false, k });
      if (t.length <= p.limite) return pronto(t, false, cortes);
    }
  }
  // 4) a 1ª mudança cortada na palavra (o resto do texto como ficou)
  cortes.push("linha");
  const semALinha = juntar(p, { fora: false, perguntas: false, k: 1, primeira: "" });
  const cabe = Math.max(p.limite - semALinha.length, 0);
  t = juntar(p, { fora: false, perguntas: false, k: 1, primeira: cortarNaPalavra(p.mudancas[0].texto, cabe) });
  return pronto(t.length <= p.limite ? t : cortarNaPalavra(t, p.limite), false, cortes);
}
