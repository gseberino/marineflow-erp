// Os comandos do dono sobre a manhã nova (secretário, Passo 2, 15/10/2026) — leitor puro, sem banco.
//
// Lidos ANTES da IA, só do dono e só com resumo_formato = 'novo' (quem chama confere). Custo zero:
//   lista · lista dinheiro/clientes/obras/contatos · escritório · tudo
//   detalhe X · por que o X? · X feito · X amanhã · X segunda · X não · X espera [até dd/mm] · X até dd/mm
//   tira X · volta X (a letra de hoje ou um nome: "volta Flávio") · X (a letra sozinha abre o cartão pronto)
//
// NÃO PODE COLIDIR (provado em comandos_test.ts):
//   · confirmação (whatsapp-channel.ts: sim/s/ok/confirmar/1 · não/nao/n/cancelar/2): nenhum comando
//     começa por elas, e N e S não são letras;
//   · comprovantes (comprovantes/respostas.ts, lerComando): "pendentes" continua deles; cmp N, feito cmp N,
//     pular/depois, sair/pare, corrigir…, obs:… não são lidos aqui;
//   · registro de pergunta ativa (whatsapp/pergunta-ativa.ts): número, "um", "opção 2", "a 2", sim/não/ok
//     e emoji não são lidos aqui.
// O que não é comando devolve null e segue o caminho de sempre.

import { letraValida, paraBusca } from "./base.ts";
import type { Secao } from "./tipos.ts";

export type Adiamento = "amanha" | "segunda" | "espera" | { dia: number; mes: number | null };

export type ComandoDoSecretario =
  | { comando: "lista"; filtro: Secao | null }
  | { comando: "escritorio" }
  | { comando: "tudo" }
  | { comando: "detalhe"; letra: string }
  | { comando: "porque"; letra: string }
  | { comando: "acao"; letra: string; acao: "feito" | "nao" | "tirado" }
  | { comando: "adiar"; letra: string; quando: Adiamento }
  | { comando: "volta"; letra: string | null; nome: string | null }
  | { comando: "abrir"; letra: string };

/** trim; tira 🎤 e aspas da ponta, negrito/itálico do WhatsApp; minúsculo sem acento; sem pontuação final. */
export function normalizarComando(texto: string): string {
  let s = String(texto ?? "").trim();
  s = s.replace(/^[\s🎤"'“”‘’«»]+/u, "");
  s = s.replace(/[*_~]/g, "");
  s = s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  s = s.replace(/(\p{L})-(\p{L})/gu, "$1 $2"); // "segunda-feira" → "segunda feira" (a data 20/10 fica)
  s = s.replace(/\s+/g, " ").trim();
  s = s.replace(/[\s.!?,;:"'“”‘’«»]+$/u, "").trim();
  return s;
}

const FILTROS: Record<string, Secao> = {
  dinheiro: "dinheiro", cobranca: "dinheiro", cobrancas: "dinheiro",
  cliente: "clientes", clientes: "clientes", orcamento: "clientes", orcamentos: "clientes",
  obra: "obras", obras: "obras", os: "obras",
  contato: "contatos", contatos: "contatos",
};

// a letra (já minúscula): o alfabeto do dia, sem e, i, n, o, s
const L = "([a-df-hj-mp-rt-z])";
const ITEM = "(?:(?:o|a) )?(?:(?:item|letra) )?";

function letra(m: RegExpExecArray | null, i = 1): string | null {
  return m ? letraValida(m[i]) : null;
}

/** O comando, ou null (não é comando: segue para o assistente como sempre). */
export function lerComandoDoSecretario(texto: string): ComandoDoSecretario | null {
  const t = normalizarComando(texto);
  if (!t || t.length > 60) return null;

  if (t === "lista") return { comando: "lista", filtro: null };
  let m = /^lista (?:de |dos |das |do |da )?([a-z]+)$/.exec(t);
  if (m) return FILTROS[m[1]] ? { comando: "lista", filtro: FILTROS[m[1]] } : null;
  if (t === "escritorio") return { comando: "escritorio" };
  if (t === "tudo" || t === "resumo completo" || t === "resumo antigo") return { comando: "tudo" };

  let l: string | null;
  if ((l = letra(new RegExp(`^(?:letra )?${L}$`).exec(t)))) return { comando: "abrir", letra: l };
  if ((l = letra(new RegExp(`^detalhes? (?:d[oa] |de )?${ITEM}${L}$`).exec(t)))) return { comando: "detalhe", letra: l };
  if ((l = letra(new RegExp(`^(?:por que|porque|pq|por q) ${ITEM}${L}(?: subiu)?$`).exec(t)))) return { comando: "porque", letra: l };
  if ((l = letra(new RegExp(`^${L} (?:feito|feita|resolvido|resolvida|ja fiz|ja foi|pronto)$`).exec(t)))) {
    return { comando: "acao", letra: l, acao: "feito" };
  }
  if ((l = letra(new RegExp(`^${L} (?:nao|nao quero|nao vou)$`).exec(t)))) return { comando: "acao", letra: l, acao: "nao" };
  if ((l = letra(new RegExp(`^(?:tira|tirar|tire) ${ITEM}${L}$`).exec(t)))) return { comando: "acao", letra: l, acao: "tirado" };
  if ((l = letra(new RegExp(`^${L} amanha$`).exec(t)))) return { comando: "adiar", letra: l, quando: "amanha" };
  if ((l = letra(new RegExp(`^${L} (?:na )?segunda(?: feira)?$`).exec(t)))) return { comando: "adiar", letra: l, quando: "segunda" };
  if ((l = letra(new RegExp(`^${L} espera$`).exec(t)))) return { comando: "adiar", letra: l, quando: "espera" };
  m = new RegExp(`^${L} (?:espera )?ate (?:o )?(?:dia )?(\\d{1,2})(?:/(\\d{1,2}))?$`).exec(t);
  if ((l = letra(m)) && m) {
    const dia = Number(m[2]);
    const mes = m[3] ? Number(m[3]) : null;
    if (dia < 1 || dia > 31 || (mes !== null && (mes < 1 || mes > 12))) return null;
    return { comando: "adiar", letra: l, quando: { dia, mes } };
  }
  if ((l = letra(new RegExp(`^(?:volta|voltar|volte|desfaz|desfazer) ${ITEM}${L}$`).exec(t)))) {
    return { comando: "volta", letra: l, nome: null };
  }
  m = /^(?:volta|voltar|volte) (?:o |a )?(.{2,40})$/.exec(t);
  if (m) {
    const nome = paraBusca(m[1]);
    // "volta a" sozinho já foi a letra A acima; aqui só nome de verdade (2+ letras)
    if (nome.replace(/ /g, "").length >= 2) return { comando: "volta", letra: null, nome };
  }
  return null;
}

/**
 * O dia do adiamento ('aaaa-mm-dd') ou null (data inválida, no passado ou a mais de 90 dias). "espera"
 * usa o padrão do tipo do item (esperaDoTipo); "até 20" sem mês = o próximo dia 20.
 */
export function diaDoAdiamento(
  quando: Adiamento,
  hoje: string,
  padrao: "amanha" | "segunda",
  proximaSegunda: (dia: string) => string,
  somar: (dia: string, n: number) => string,
): string | null {
  const q = quando === "espera" ? padrao : quando;
  if (q === "amanha") return somar(hoje, 1);
  if (q === "segunda") return proximaSegunda(hoje);
  const ano = Number(hoje.slice(0, 4));
  const mesHoje = Number(hoje.slice(5, 7));
  const candidatos: string[] = [];
  const montar = (a: number, mes: number) => {
    const d = new Date(Date.UTC(a, mes - 1, q.dia));
    if (d.getUTCMonth() !== mes - 1) return; // 31/11 não existe
    candidatos.push(d.toISOString().slice(0, 10));
  };
  if (q.mes !== null) {
    montar(ano, q.mes);
    montar(ano + 1, q.mes);
  } else {
    montar(ano, mesHoje);
    montar(mesHoje === 12 ? ano + 1 : ano, mesHoje === 12 ? 1 : mesHoje + 1);
  }
  const limite = somar(hoje, 90);
  return candidatos.find((c) => c > hoje && c <= limite) ?? null;
}
