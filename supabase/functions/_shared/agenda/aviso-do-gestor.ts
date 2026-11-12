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
//
// (Fase 7f, P4) A mensagem da quinta (_agenda_comunicar_quinta, migration 20261109100300) vem com `semana`: o banco manda as
// peças do mesmo jeito, e o cabeçalho, o rodapé e "Para a semana que vem preciso de:" já vêm prontos. Ela pode vir sem mudança,
// com perguntas (é a mensagem da semana que sai mesmo sem mudança), e existe pelas perguntas: passando do teto, depois do que
// ficou de fora saem as últimas mudanças ("e mais N") e só então as perguntas. Sem mudança, as perguntas não saem: se nem elas
// cabem, nada a mandar (quem chama registra). O aviso de sempre (sem `semana`) segue o de antes, linha por linha.
//
// (Fase 7g, P6) Com o placar ligado, a quinta traz a peça `placar` ({texto, linha}): o placar da semana, depois do rodapé e
// antes das perguntas, separado por uma linha em branco dos dois lados (_agenda_lote_texto junta igual). No corte, o placar
// cede primeiro, inteiro, antes de qualquer corte de antes: o texto, depois a linha, depois só "Placar da semana em *agenda
// placar*.", depois nada; e só então os cortes de antes, na ordem de antes. Sem a peça, o texto e os cortes são os de antes.

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

/** (Fase 7g, P6) O placar da semana na mensagem da quinta: o texto (só as linhas com dado) e a versão de uma linha. */
export interface PlacarDoAviso {
  texto: string;
  linha: string | null;
}

/** (Fase 7g, P6) O que vai no lugar do placar quando nem a linha cabe. */
export const PLACAR_EM_OUTRO_LUGAR = "Placar da semana em *agenda placar*.";

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
  /** (Fase 7f, P4) a mensagem da quinta: pode vir sem mudança, com perguntas; no corte, as mudanças saem antes das perguntas */
  semana?: boolean;
  /** (Fase 7g, P6) o placar da semana, antes das perguntas; no corte, cede primeiro */
  placar?: PlacarDoAviso;
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
  cortes: Array<"placar" | "fora" | "perguntas" | "mudancas" | "linha">;
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
  // (Fase 7f, P4) só a mensagem da quinta vem sem mudança, e então com perguntas que contam
  const semana = r.semana === true;
  const p = r.perguntas && typeof r.perguntas === "object" ? r.perguntas as Record<string, unknown> : null;
  const textoDasPerguntas = textoLimpo(p?.texto);
  const perguntas = textoDasPerguntas ? { texto: textoDasPerguntas, perguntaIds: idsValidos(p?.pergunta_ids) } : null;
  if (!mudancas.length && !(semana && perguntas?.perguntaIds.length)) return null;
  // (Fase 7g, P6) o placar da semana: sem texto, não há placar (a chave fica de fora, como antes)
  const pl = r.placar && typeof r.placar === "object" && !Array.isArray(r.placar) ? r.placar as Record<string, unknown> : null;
  const textoDoPlacar = textoLimpo(pl?.texto);
  return {
    avisar: true,
    pecas: {
      rodada, dia, limite, cabecalho, mudancas,
      fora: textoLimpo(r.fora),
      rodape: textoLimpo(r.rodape),
      perguntas,
      ...(textoLimpo(r.perguntas_erro) ? { perguntasErro: textoLimpo(r.perguntas_erro) } : {}),
      ...(semana ? { semana: true } : {}),
      ...(textoDoPlacar ? { placar: { texto: textoDoPlacar, linha: textoLimpo(pl?.linha) } } : {}),
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

function juntar(
  p: PecasDoAviso,
  o: { fora: boolean; perguntas: boolean; k: number; primeira?: string; placar?: string | null },
): string {
  const n = p.mudancas.length;
  const linhas = [p.cabecalho, ...p.mudancas.slice(0, o.k).map((m, i) => `• ${i === 0 && o.primeira !== undefined ? o.primeira : m.texto}`)];
  if (o.k < n) linhas.push(eMais(n - o.k));
  if (o.fora && p.fora) linhas.push(p.fora);
  if (p.rodape) linhas.push(p.rodape);
  // (Fase 7g, P6) o placar, numa linha em branco própria, antes das perguntas (sem ele, o texto de antes)
  const corpo = o.placar ? `${linhas.join("\n")}\n\n${o.placar}` : linhas.join("\n");
  return o.perguntas && p.perguntas ? `${corpo}\n\n${p.perguntas.texto}` : corpo;
}

/** As peças → o texto do aviso e o que ele conta. null = nada a contar (nenhuma mudança; na da quinta, nem pergunta). */
export function montarAvisoDoGestor(p: PecasDoAviso): AvisoMontado | null {
  const n = p.mudancas.length;
  if (!n && !(p.semana && p.perguntas)) return null;
  const acaoIds = [...new Set(p.mudancas.flatMap((m) => m.acaoIds))];
  const pronto = (texto: string, perguntas: boolean, cortes: AvisoMontado["cortes"]): AvisoMontado => ({
    texto,
    acaoIds,
    perguntaIds: perguntas && p.perguntas ? p.perguntas.perguntaIds : [],
    comPerguntas: perguntas && !!p.perguntas,
    cortes,
  });
  const cortes: AvisoMontado["cortes"] = [];
  let t = juntar(p, { fora: true, perguntas: true, k: n, placar: p.placar?.texto });
  if (t.length <= p.limite) return pronto(t, true, cortes);
  // (Fase 7g, P6) o placar cede primeiro, antes de qualquer corte de antes: a linha, depois só onde ver; não cabendo, sai, e os
  // cortes de antes seguem sem ele
  if (p.placar) {
    cortes.push("placar");
    for (const versao of [p.placar.linha, PLACAR_EM_OUTRO_LUGAR]) {
      if (!versao) continue;
      t = juntar(p, { fora: true, perguntas: true, k: n, placar: versao });
      if (t.length <= p.limite) return pronto(t, true, cortes);
    }
    t = juntar(p, { fora: true, perguntas: true, k: n });
    if (t.length <= p.limite) return pronto(t, true, cortes);
  }
  // 1) sem o que ficou de fora
  if (p.fora) {
    cortes.push("fora");
    t = juntar(p, { fora: false, perguntas: true, k: n });
    if (t.length <= p.limite) return pronto(t, true, cortes);
  }
  // (Fase 7f, P4) a da quinta existe pelas perguntas: as últimas mudanças viram "e mais N" antes de elas saírem
  if (p.semana) {
    if (n > 1) {
      cortes.push("mudancas");
      for (let k = n - 1; k >= 1; k--) {
        t = juntar(p, { fora: false, perguntas: true, k });
        if (t.length <= p.limite) return pronto(t, true, cortes);
      }
    }
    // sem mudança, as perguntas sozinhas não cabem: nada a mandar
    if (!n) return null;
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
