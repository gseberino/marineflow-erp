// A escolha da manhã nova (secretário, Passo 2, 15/10/2026) — regra fixa, pura e testada. Sem IA.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-manha.md §4.
//
// 1. Cada candidato olha o próprio histórico (a mesma `referencia`, 30 dias, mesmo modo, sem hoje):
//      · o "marco" é o último "volta X" ou o último adiamento já vencido — o que veio antes não conta;
//      · adiado até depois de hoje → lista ("adiado até …");
//      · mesma impressão digital (fato) que a última ação: tirado → fora (nem lista); feito → fora (a
//        cobrança grande volta no dia seguinte: fica até entrar); não → lista;
//      · já apareceu DE MANHÃ com o mesmo fato → lista (2º dia só com fato novo) — exceto cobrança grande.
// 2. Ordem: o que se perde hoje → maior valor → mais antigo (entre grupos; o pacote dos orçamentos não
//    enviados vale a soma deles). O pedido de orçamento do dia se perde hoje, mas só um vai na frente.
// 3. Um assunto (o cliente; sem cliente, a OS ou o telefone) aparece uma vez: o grupo sobe pelo melhor
//    item que pode subir e leva os outros junto ("Também: …"), com a mesma letra. Os orçamentos montados
//    e não enviados (R$ 5 mil+) são UM assunto só: viram um item ("3 orçamentos … não enviados").
// 4. Manhã = até 3 grupos. A cobrança grande (R$ 5 mil+ vencida) tem lugar garantido: fica na manhã todo
//    dia até entrar ou o dono adiar com data (decisão do dono, 15/10/2026) — se não coube pela ordem,
//    entra no lugar do último. Os seguintes que podiam subir são o "logo abaixo"; o resto é a lista.
// 5. Letras: A, B, C de manhã; a lista continua na ordem dinheiro → clientes → obras → contatos. Passou
//    das 21 letras: sem letra, só contado.

import { brl, brlCurto, ddmm, letraDoIndice, quandoEmPalavras } from "../_shared/secretario/base.ts";
import { SECOES } from "../_shared/secretario/tipos.ts";
import { ASSUNTO_NAO_ENVIADOS, type Candidato, FRASE_DO_PEDIDO, REGRAS } from "./secretario-candidatos.ts";

/** Uma passagem anterior da mesma referência (resumo_itens, sem o dia de hoje). */
export interface PassagemDoHistorico {
  referencia: string;
  dia: string;
  posicao: "manha" | "lista";
  fato: string;
  acao: string | null;
  acao_em: string | null;
  adiado_ate: string | null;
  voltou_em: string | null;
  criado_em: string;
  /**
   * (16/10/2026) Como o adiamento foi pedido: 'semana' / '15dias' (a revisão respondida de uma vez, resumo_itens_acoes
   * grava a resposta no histórico do item). null/ausente = o adiamento comum ("X espera", "X até dd/mm").
   */
  adiado_por?: string | null;
}

/**
 * (16/10/2026) Regras do histórico que o dono pode mudar sem publicar (voz_unica_regras):
 *   semanaVoltaComFatoNovo (F7, padrão recomendado, aguarda o dono) — "X semana" (adiado até segunda) volta ANTES se
 *   o fato mudou (mensagem nova do cliente, pagamento, vencimento novo). Só esse adiamento: "X espera", "X até dd/mm" e
 *   "X 15 dias" seguram até a data, como antes.
 */
export interface OpcoesDoHistorico {
  semanaVoltaComFatoNovo: boolean;
}
export const OPCOES_PADRAO: Readonly<OpcoesDoHistorico> = Object.freeze({ semanaVoltaComFatoNovo: true });

/** O "como" do último adiamento no histórico jsonb de resumo_itens ({acao:'adiado', resposta:'semana'|'15dias'}). */
export function adiadoPor(historico: unknown): string | null {
  if (!Array.isArray(historico)) return null;
  for (let i = historico.length - 1; i >= 0; i--) {
    const h = historico[i] as { acao?: unknown; resposta?: unknown } | null;
    if (h && h.acao === "adiado") return typeof h.resposta === "string" ? h.resposta : null;
  }
  return null;
}

export type Lugar = "manha" | "lista" | "fora";

export interface Estado {
  lugar: Lugar;
  /** por que está na lista (null na manhã) */
  motivo: string | null;
  /** já apareceu de manhã antes, com outro fato */
  fatoNovo: boolean;
  adiadoAte: string | null;
}

const ACOES_DO_DONO = new Set(["feito", "adiado", "nao", "tirado"]);

function ms(iso: string | null | undefined): number {
  const t = iso ? Date.parse(iso) : NaN;
  return Number.isNaN(t) ? -Infinity : t;
}

/** O que o histórico diz deste candidato hoje. */
export function estadoPeloHistorico(
  c: Candidato,
  historico: PassagemDoHistorico[],
  hoje: string,
  opcoes: OpcoesDoHistorico = OPCOES_PADRAO,
): Estado {
  let passagens = historico.filter((h) => h.referencia === c.referencia && h.dia < hoje);
  // o marco: o último "volta" e o último adiamento que já venceu
  let marco = -Infinity;
  for (const h of passagens) {
    marco = Math.max(marco, ms(h.voltou_em));
    if (h.acao === "adiado" && h.adiado_ate && h.adiado_ate <= hoje) marco = Math.max(marco, ms(h.acao_em));
  }
  passagens = passagens.filter((h) => ms(h.criado_em) > marco);

  const ultima = passagens.filter((h) => h.acao && ACOES_DO_DONO.has(h.acao))
    .sort((a, b) => ms(a.acao_em) - ms(b.acao_em)).pop();
  // F7 (16/10/2026): o "X semana" volta antes da segunda quando o fato mudou (o "X espera"/"até dd/mm" segura até a data)
  const voltouDoAdiamento = !!ultima && ultima.acao === "adiado" && !!ultima.adiado_ate && ultima.adiado_ate > hoje &&
    opcoes.semanaVoltaComFatoNovo && ultima.adiado_por === "semana" && ultima.fato !== c.fato;
  if (ultima?.acao === "adiado" && ultima.adiado_ate && ultima.adiado_ate > hoje && !voltouDoAdiamento) {
    return { lugar: "lista", motivo: `Ficou na lista: adiado até ${quandoEmPalavras(ultima.adiado_ate, hoje)}.`, fatoNovo: false, adiadoAte: ultima.adiado_ate };
  }
  if (ultima && ultima.fato === c.fato) {
    if (ultima.acao === "tirado") return { lugar: "fora", motivo: null, fatoNovo: false, adiadoAte: null };
    if (ultima.acao === "feito" && !c.todoDia) return { lugar: "fora", motivo: null, fatoNovo: false, adiadoAte: null };
    if (ultima.acao === "nao") {
      return { lugar: "lista", motivo: `Ficou na lista: você respondeu "não" em ${ddmm(ultima.dia)}; volta de manhã com fato novo.`, fatoNovo: false, adiadoAte: null };
    }
  }
  if (!c.elegivel) return { lugar: "lista", motivo: c.porqueNaoSobe ?? "Ficou na lista.", fatoNovo: false, adiadoAte: null };

  const deManha = passagens.filter((h) => h.posicao === "manha").sort((a, b) => a.dia.localeCompare(b.dia));
  const mesmoFato = deManha.filter((h) => h.fato === c.fato);
  if (mesmoFato.length && !c.todoDia) {
    return {
      lugar: "lista",
      motivo: `Ficou na lista: já apareceu de manhã em ${ddmm(mesmoFato[mesmoFato.length - 1].dia)} e não há fato novo.`,
      fatoNovo: false,
      adiadoAte: null,
    };
  }
  return { lugar: "manha", motivo: null, fatoNovo: (deManha.length > 0 && mesmoFato.length === 0) || voltouDoAdiamento, adiadoAte: null };
}

/** O que se perde hoje → maior valor → mais antigo (e a referência, para empate nunca virar sorteio). */
export function ordemDosCandidatos(a: Candidato, b: Candidato): number {
  if (a.perdeHoje !== b.perdeHoje) return a.perdeHoje ? -1 : 1;
  if (a.valor !== b.valor) return b.valor - a.valor;
  const d = ms(a.desde) - ms(b.desde);
  if (d !== 0) return d;
  return a.referencia.localeCompare(b.referencia);
}

export interface MembroDoGrupo {
  c: Candidato;
  estado: Estado;
}

export interface GrupoDoDia {
  letra: string | null;
  posicao: "manha" | "lista";
  /** o primeiro é o principal */
  membros: MembroDoGrupo[];
  /** por que subiu (manhã) ou por que ficou na lista; o {L} já trocado pela letra */
  motivo: string;
  /** podia subir e passou do limite de 3 */
  quaseEntrou: boolean;
  /** 2+ orçamentos montados e não enviados num item só (o texto e a letra sozinha listam todos) */
  pacote: boolean;
}

/** 2+ orçamentos montados e não enviados juntos (o assunto ASSUNTO_NAO_ENVIADOS). */
export function ehPacote(membros: MembroDoGrupo[]): boolean {
  return membros.length > 1 && membros.every((m) => m.c.assunto === ASSUNTO_NAO_ENVIADOS);
}

/** O valor do grupo na ordem: o pacote vale a soma; os outros, o principal. */
export function valorDoGrupo(membros: MembroDoGrupo[]): number {
  return ehPacote(membros) ? membros.reduce((s, m) => s + m.c.valor, 0) : membros[0].c.valor;
}

/** A mesma ordem dos candidatos, entre grupos (o pacote pelo valor somado). */
export function ordemDosGrupos(a: MembroDoGrupo[], b: MembroDoGrupo[]): number {
  const pa = a[0].c, pb = b[0].c;
  if (pa.perdeHoje !== pb.perdeHoje) return pa.perdeHoje ? -1 : 1;
  const va = valorDoGrupo(a), vb = valorDoGrupo(b);
  if (va !== vb) return vb - va;
  return ordemDosCandidatos(pa, pb);
}

/** A cobrança grande que pode subir hoje dá ao grupo o lugar garantido na manhã. */
function temCobrancaGrande(membros: MembroDoGrupo[]): boolean {
  return membros.some((m) => m.c.todoDia && m.estado.lugar === "manha");
}

/** Os textos do pacote (a linha da manhã, a curta da lista, o "logo abaixo", o nome e o motivo). */
export function textosDoPacote(membros: MembroDoGrupo[]): {
  titulo: string; curto: string; rotulo: string; nome: string; motivo: string;
} {
  const n = membros.length;
  const total = membros.reduce((s, m) => s + m.c.valor, 0);
  const numero = (m: MembroDoGrupo) => m.c.nome.split(" ")[0];
  const numeros = membros.map(numero);
  // o formato do dono: "3 orçamentos montados e ainda não enviados, R$ 211 mil: ORÇ-00117, ORÇ-00116, ORÇ-00118"
  // (o valor de cada um vem quando ele manda a letra)
  const lista = `${numeros.slice(0, 3).join(", ")}${n > 3 ? ` e mais ${n - 3}` : ""}`;
  // "Montado em" dd/mm/aaaa (dos fatos do candidato) → o mais antigo
  const montados = membros.map((m) => m.c.fatos.find(([r]) => r === "Montado em")?.[1])
    .map((d) => /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(d ?? ""))
    .filter((x): x is RegExpExecArray => !!x)
    .map((x) => `${x[3]}-${x[2]}-${x[1]}`).sort();
  const maisAntigo = montados.length ? ddmm(montados[0]) : null;
  return {
    titulo: `*${n} orçamentos montados e ainda não enviados*, ${brlCurto(total)}: ${lista}.`,
    curto: `${n} orçamentos montados, não enviados (${brlCurto(total)}): ${numeros.slice(0, 4).join(", ")}${n > 4 ? ` e mais ${n - 4}` : ""}`,
    rotulo: `${n} orçamentos não enviados (${brlCurto(total)})`,
    nome: `${n} orçamentos não enviados: ${numeros.join(", ")}`.slice(0, 120),
    motivo: `Subiu porque são ${n} orçamentos de R$ 5 mil ou mais montados e ainda não enviados ao cliente` +
      ` (${brl(total)} no total${maisAntigo ? `; o mais antigo montado em ${maisAntigo}` : ""}). Um assunto só: vão juntos num item.`,
  };
}

export interface Selecao {
  manha: GrupoDoDia[];
  lista: GrupoDoDia[];
  /** os candidatos ao "logo abaixo ficaram…" (até 3; o texto usa 2, tirando a cobrança grande que o "Na rua" nomeia) */
  logoAbaixo: GrupoDoDia[];
  /** grupos da lista que passaram das 21 letras */
  semLetra: number;
}

/** Troca o {L} dos textos pela letra (sem letra: "a letra"). */
export function comLetra(texto: string, letra: string | null): string {
  return texto.replaceAll("{L}", letra ?? "a letra");
}

/**
 * `max` = quantos sobem (0 no domingo e no feriado: tudo fica na lista); `motivoDoLimite` = o que a lista
 * diz de quem podia subir e não coube.
 */
export function selecionar(
  candidatos: Candidato[],
  historico: PassagemDoHistorico[],
  hoje: string,
  max: number = REGRAS.maxManha,
  motivoDoLimite = "Ficou na lista: podia subir, mas passou do limite de 3 da manhã.",
  opcoes: OpcoesDoHistorico = OPCOES_PADRAO,
): Selecao {
  const vivos: MembroDoGrupo[] = candidatos
    .map((c) => ({ c, estado: estadoPeloHistorico(c, historico, hoje, opcoes) }))
    .filter((m) => m.estado.lugar !== "fora");
  // pedido de orçamento do dia: "se perde hoje" para UM só, o mais antigo que pode subir (no pior caso ele
  // ocupa 1 dos 3 lugares); os outros seguem a ordem comum, sem a frase do "se perde hoje"
  const pedidos = vivos.filter((m) => m.c.soPeloPedido && m.c.perdeHoje && m.estado.lugar === "manha")
    .sort((a, b) => ms(a.c.desde) - ms(b.c.desde) || a.c.referencia.localeCompare(b.c.referencia));
  for (const m of pedidos.slice(1)) {
    m.c = { ...m.c, perdeHoje: false, soPeloPedido: false, motivo: m.c.motivo.replace(FRASE_DO_PEDIDO, "") };
  }
  vivos.sort((a, b) => ordemDosCandidatos(a.c, b.c));

  // um assunto, um grupo; o principal é o melhor que pode subir (senão o melhor de todos)
  const porAssunto = new Map<string, MembroDoGrupo[]>();
  for (const m of vivos) {
    const l = porAssunto.get(m.c.assunto) ?? [];
    l.push(m);
    porAssunto.set(m.c.assunto, l);
  }
  const grupos = [...porAssunto.values()].map((membros) => {
    const i = membros.findIndex((m) => m.estado.lugar === "manha");
    const ordenados = i > 0 ? [membros[i], ...membros.filter((_, j) => j !== i)] : membros;
    return { membros: ordenados, podeSubir: ordenados[0].estado.lugar === "manha", pacote: ehPacote(ordenados) };
  }).sort((a, b) => ordemDosGrupos(a.membros, b.membros));

  // por que subiu: o do principal, ou o do pacote ("fato novo" se algum dos membros o trouxe)
  const motivoBase = (g: { membros: MembroDoGrupo[]; pacote: boolean }) =>
    g.pacote ? textosDoPacote(g.membros).motivo : g.membros[0].c.motivo;
  const temNovidade = (g: { membros: MembroDoGrupo[] }) => g.membros.some((m) => m.estado.fatoNovo);
  const motivoDeManha = (g: { membros: MembroDoGrupo[]; pacote: boolean }) =>
    (temNovidade(g) ? "Voltou com fato novo. " : "") + motivoBase(g);
  const motivoDeQuase = (g: { membros: MembroDoGrupo[]; pacote: boolean }) =>
    `${motivoDoLimite} Pela regra, ${motivoBase(g).replace(/^Subiu porque/, "subiria porque")}` +
    (temNovidade(g) ? " Há fato novo desde a última vez." : "");

  // a manhã: primeiro o lugar garantido da cobrança grande (até `max`), depois a ordem; mostrada na ordem
  const podem = grupos.filter((g) => g.podeSubir);
  const escolhidos = new Set(podem.filter((g) => temCobrancaGrande(g.membros)).slice(0, max));
  for (const g of podem) {
    if (escolhidos.size >= max) break;
    escolhidos.add(g);
  }
  const manha: GrupoDoDia[] = podem.filter((g) => escolhidos.has(g)).map((g) => ({
    letra: null, posicao: "manha", membros: g.membros, quaseEntrou: false, pacote: g.pacote,
    motivo: motivoDeManha(g),
  }));
  const quase = podem.filter((g) => !escolhidos.has(g)).map((g) => ({
    letra: null, posicao: "lista" as const, membros: g.membros, quaseEntrou: true, pacote: g.pacote,
    motivo: motivoDeQuase(g),
  }));
  const resto = grupos.filter((g) => !g.podeSubir).map((g) => ({
    letra: null, posicao: "lista" as const, membros: g.membros, quaseEntrou: false, pacote: g.pacote,
    motivo: g.membros[0].estado.motivo ?? "Ficou na lista.",
  }));

  // a lista na ordem das seções; dentro, primeiro quem podia subir (as letras acabam em 21: no ensaio de 15/10
  // o contato que pediu orçamento ficou sem letra atrás de 7 contatos parados), depois a mesma ordem da manhã
  const lista: GrupoDoDia[] = [...quase, ...resto].sort((a, b) =>
    SECOES.indexOf(a.membros[0].c.secao) - SECOES.indexOf(b.membros[0].c.secao)
    || Number(b.quaseEntrou) - Number(a.quaseEntrou)
    || ordemDosGrupos(a.membros, b.membros));

  let i = 0;
  for (const g of manha) g.letra = letraDoIndice(i++);
  let semLetra = 0;
  for (const g of lista) {
    g.letra = letraDoIndice(i++);
    if (!g.letra) semLetra++;
  }
  for (const g of [...manha, ...lista]) g.motivo = comLetra(g.motivo, g.letra);

  // "logo abaixo": os que quase entraram, na ordem da manhã; sem eles, os mais bem colocados da lista
  // (contato e adiado não). Até 3: o texto tira dali a cobrança grande que a linha "Na rua" já nomeia.
  const candidatosAbaixo = (quase.length
    ? lista.filter((g) => g.quaseEntrou)
    : lista.filter((g) => g.membros[0].c.secao !== "contatos" && !g.membros[0].estado.adiadoAte))
    .sort((a, b) => ordemDosGrupos(a.membros, b.membros));
  return { manha, lista, logoAbaixo: candidatosAbaixo.slice(0, 3), semLetra };
}
