// Agenda de Produção, Fase 1 (P6): as palavras curtas da agenda, lidas ANTES da IA — leitor puro, sem banco.
// Spec: scratchpad agenda-pesquisa/spec-fase1.md §7.2 (decisão d03 do dono: a conversa é o canal, as palavras são atalho).
//
//   agenda · a agenda · agenda da semana · agenda dessa/desta semana                       → a semana
//   minha agenda · agenda hoje · agenda de hoje · agenda pra/para hoje                     → hoje (como a my_agenda:
//                                                     o marcado, as tarefas do dia e as atrasadas, pelo título)
//   agenda amanhã · agenda de amanhã · agenda pra/para amanhã · o que tem pra/para amanhã   → amanhã
//   agenda semana que vem · agenda da semana que vem · agenda (da) próxima semana          → a semana que vem
//   livre · quando fica livre · quando fico livre · quando a gente fica livre              → quando fica livre
//   atrasado(s/as) · o que está atrasado · o que tá atrasado                               → o que passou do prazo
//   o que (eu) tenho que/pra/para/de fazer · o que tem pra/para fazer (+ "hoje" no fim)     → o que eu tenho que fazer
//   grava · gravar · grave · pode gravar · grava tudo · pode gravar tudo                   → grava o rascunho conferido
//   descarta · descartar · descarte · descarta tudo                                        → descarta o rascunho
//
// Fase 2 (P5, 24/10/2026; spec-fase2.md §11) — a conferência do dia e o que a agenda fez sozinha:
//   dia feito [quando]                                     → o dia do plano foi como estava (agenda_conferir_dia)
//   dia nao <motivo> [quando] · dia nao                    → não andou (sem motivo, o banco pede o motivo)
//   dia parcial <motivo> [quando] · dia parcial            → andou em parte
//   choveu [quando]                                        → não andou por causa da chuva (agenda_choveu)
//   desfaz · desfazer · desfaz <alvo> · desfaz (a) semana  → desfaz o que a agenda mudou sozinha (agenda_desfazer_dito:
//                                                            é a ordem exata do dono, executa direto; ambíguo = pergunta)
//   o que mudou · o que voce mudou · agenda mudancas       → agenda_ver foco mudancas
//   agenda pendencias · o que voce precisa de mim          → agenda_ver foco decisoes
//   agenda plano · plano da semana                         → agenda_ver foco plano
//   <motivo> (uma palavra): material, cliente, equipe, anterior, informacao, clima, estimativa, imprevisto, urgencia,
//   esqueci → o código LCI. <quando>: hoje, ontem, anteontem, segunda…sábado, dd/mm. <alvo>: o nome do cliente (até 3
//   palavras, sem "do/da/de" nem as palavras de outras ferramentas: "desfaz o agrupamento do ORÇ-00120", "desfaz a baixa
//   da conta de luz", "desfaz isso" vão ao modelo), o número da OS ou "semana", até 40 caracteres, resolvido no banco (a
//   mesma resolução da Fase 1; ambíguo = pergunta; o nome que não acha nada vai ao modelo).
//   Estas palavras da Fase 2 só valem com a agenda automática fora de 'desligado' (ehPalavraDaFase2).
//
// Fase 3 (P3, 24/10/2026; spec-fase3.md §11) — concluir e entregar (executam direto: agenda_concluir_dito e
// agenda_entregar_dito, pela porta; a saída e as cobranças da condição na mesma transação, desfazível):
//   concluiu · concluiu <alvo> · concluido <alvo> · concluida <alvo>      → conclui (sem alvo: a OS do plano de hoje)
//   entreguei <alvo> · entregue <alvo>                                    → marca a entrega (conclui antes se faltava)
//   O alvo segue a régua do *desfaz*: o nome do cliente (até 3 palavras, sem conectivo nem palavra de outra ferramenta:
//   "concluiu o pagamento" vai ao modelo) ou o número, nunca uma letra ("concluiu b" não é palavra). "entregue" e
//   "entreguei" sozinhos não são palavra (precisa do alvo). Também só com a agenda automática fora de 'desligado'.
//
// Fase 3 (P4, 24/10/2026; spec-fase3.md §11) — a diária que a agenda lançou ou perguntou (agenda_diaria_dita):
//   diaria <nome> inteira|meia|nao [quando] · diaria <nome> dia inteiro [quando] · diaria do/da <nome> …
//   → responde a pergunta da diária aberta, ou corrige (meia/inteira) / apaga (não) a que a agenda lançou; sem nada da
//   agenda, o banco diz nao_achei e o turno segue ao modelo (o registrar_diaria de sempre). O nome é de 1 ou 2 palavras
//   (sem conectivo nem letra solta). Só com a diária automática (agenda_config.modo_diaria) fora de 'desligado'
//   (ehPalavraDaDiaria). "lança a diária do João", "registra a diária do Roberto" e "o João trabalhou meio dia" NÃO são
//   palavra (vão ao modelo e ao registrar_diaria); a agenda não usa "corrige" ("corrigir …" é dos comprovantes).
//
// Fase 3 (P6, 24/10/2026; spec-fase3.md §11) — o acompanhamento, pela agenda_ver (com a leitura fora de 'desligado', como as
// da Fase 1):
//   agenda ppc · como foi a semana                          → foco ppc (a semana medida: o quanto do plano foi cumprido)
//   agenda equipe                                           → foco equipe (o que a equipe respondeu hoje e no próximo dia útil)
//   comissao · comissao do mes · comissao <mês> · comissao mes passado → foco comissao (só a conta, nada é pago); o mês
//   vai como o dono disse (outubro), o banco resolve (_agenda_mes_dito). É a palavra que a linha do fechamento do 1º dia
//   útil do mês cita (*comissão outubro*).
//
// Fase 4 (P6, 25/10/2026; spec-fase4.md §7.2) — o material, pela agenda_ver (com a leitura fora de 'desligado', como as da
// Fase 1; o banco diz "em teste" do que é da sombra):
//   agenda compras                                          → foco compras (o que comprar e até quando, as notas sem serviço
//                                                             dito, o tempo até comprar e a pergunta ao fornecedor)
//   agenda fornecedores                                     → foco fornecedores (como a agenda conta o prazo de cada
//                                                             fornecedor; é a palavra que a pergunta dos principais cita)
//   As duas são de VER (valem com "?"); nenhuma age. "compras" sozinho, "o que falta comprar" e "agenda do fornecedor" são
//   conversa (vão ao modelo, que chama agenda_ver foco compras).
//
// Fase 5 (P5, 27/10/2026; spec-fase5.md §5.5, §7.2) — a mensagem ao cliente:
//   manda cliente · manda cliente <nome>        → aprova a mensagem-modelo que espera o dono (agenda_cliente_decidir_dito;
//                                                  sem nome, todas); só sai pelas travas de sempre
//   segura cliente · segura cliente <nome>      → segura (não sai), também a que ia sair sozinha
//   agenda clientes                             → foco clientes (o que espera, o que vai sair, o que saiu, quem respondeu)
//   O alvo segue a régua do *desfaz* (até 3 palavras, sem conectivo nem palavra de outra ferramenta, nunca uma letra):
//   "manda cliente o orçamento", "manda pro cliente o PDF", "manda o PDF ao cliente", "manda o pix" e "segura aí" NÃO são
//   palavra (vão ao modelo, que tem as ferramentas do orçamento e da mensagem com a confirmação dele). Só com
//   agenda_config.modo_cliente fora de 'desligado' (ehPalavraDoCliente; em teste o banco responde "nada sai ainda").
//
// Fase 6 (P8, 28/10/2026; spec-fase6.md §7) — o que a agenda aprendeu com o que aconteceu:
//   agenda aprendizado                          → foco aprendizado (o fator por tipo de OS, a presença, os fornecedores, a
//                                                  capacidade do dono, o R$ por diária, o cliente e a revisão da carga)
//   desfaz aprendizado · desfaz o aprendizado   → o *desfaz <alvo>* de sempre (agenda_desfazer_dito resolve "aprendizado" no
//                                                  banco, antes do nome do cliente: a última troca que a agenda fez sozinha)
//   desfaz aprendizado <coisa>                  → (correção C2) só aquela coisa: fator, presença, valor, diária, folga,
//                                                  capacidade, carga, fornecedor ou o nome de um fornecedor ("desfaz aprendizado
//                                                  Kamell"); a coisa vale mesmo quando é palavra de outra ferramenta no alvo de OS
//                                                  ("diária"); o nome do fornecedor segue a régua do alvo (até 3 palavras no todo)
//   De VER (vale com "?"); com a leitura fora de desligado, como as da Fase 1 (o banco diz "em teste" ou "desligado").
//   "aprendizado" não é nome de cliente, pessoa, bem nem fornecedor (0 de 559 clientes em 28/10/2026) nem palavra de outra
//   ferramenta (comandos_test.ts).
//
// Só a frase inteira vale (normalizada pelo MESMO normalizarComando do secretário: sem acento, sem negrito, sem
// pontuação no fim, sem o 🎤 do áudio). Qualquer palavra a mais é conversa e vai ao modelo como sempre.
// (Revisão da Fase 3, C1) A palavra que AGE (concluiu, entreguei, diária, desfaz, dia feito/não/parcial, choveu) dita com
// "?" no fim é pergunta, não ordem: "Concluiu o Lenine?" vai ao modelo. As de ver valem com "?" ("agenda?", "livre?").
//
// NÃO PODE COLIDIR (provado em comandos_test.ts):
//   · a confirmação do assistente (whatsapp-channel.ts: sim/s/ok/confirmar/1 · não/nao/n/cancelar/2): nenhum comando
//     começa por elas, e nenhum da tabela fixa é número;
//   · o secretário (_shared/secretario/comandos.ts): nenhum comando é letra, nenhum é lido por ele, e nada do que ele lê
//     é lido aqui ("tudo" é dele; "grava tudo" é daqui; "<letra> feito" e "volta X" são dele, "dia feito" e "desfaz X"
//     são daqui; "desfaz <letra>" — "desfaz B", "desfaz a", "desfaz o item C" — é dele: aqui o alvo nunca é uma letra);
//   · os comprovantes (comprovantes/respostas.ts, lerComando) e o registro de pergunta ativa (whatsapp/pergunta-ativa.ts).
//     Exceção conhecida: "grava", "grave" e "pode gravar" já são um "sim" para lerSimNao (o "sim" do CMP). Com a agenda
//     ligada o webhook marca o texto como comando (quemResponde → assistente, como os do secretário), e citar a pergunta
//     do CMP continua mandando ao CMP. O CMP pede "*sim*"; a agenda pede "*grava*".

import { normalizarComando } from "../secretario/comandos.ts";

export type PeriodoDoComando = "semana" | "hoje" | "amanha" | "proxima_semana";
export type FocoDoComando =
  | "tudo" | "livre" | "atrasos" | "o_que_fazer" | "mudancas" | "decisoes" | "plano"
  // (Fase 3, P6) a semana medida, o que a equipe respondeu e a comissão do mês
  | "ppc" | "equipe" | "comissao"
  // (Fase 4, P6) o que comprar e até quando; como a agenda conta o prazo de cada fornecedor
  | "compras" | "fornecedores"
  // (Fase 5, P5) as mensagens ao cliente
  | "clientes"
  // (Fase 6, P8) o que a agenda aprendeu com o que aconteceu
  | "aprendizado";
export type ResultadoDoDia = "cumprido" | "parcial" | "nao_cumprido";

export type ComandoDaAgenda =
  /**
   * agenda_ver com o período, o foco e a pessoa ("eu" no "o que eu tenho que fazer"). (Fase 3, P6) mes: o mês da comissão
   * como o dono disse ("outubro", "mes passado"); só no foco comissao, e só quando ele disse.
   */
  | { comando: "ver"; periodo: PeriodoDoComando | null; foco: FocoDoComando; pessoa: "eu" | null; mes?: string }
  /** agenda_rascunho_gravar: o rascunho que o dono conferiu vira fato */
  | { comando: "gravar" }
  /** agenda_rascunho_descartar */
  | { comando: "descartar" }
  /** (Fase 2) agenda_conferir_dia: o dia do plano foi feito, não andou ou andou em parte (motivo = o código LCI) */
  | { comando: "dia"; resultado: ResultadoDoDia; motivo: string | null; quando: string | null }
  /** (Fase 2) agenda_choveu */
  | { comando: "choveu"; quando: string | null }
  /** (Fase 2) agenda_desfazer_dito: o alvo como o dono disse (null = o que a agenda contou por último) */
  | { comando: "desfazer"; alvo: string | null }
  /** (Fase 3) agenda_concluir_dito: o alvo como o dono disse (null = a OS do plano de hoje, se for uma só) */
  | { comando: "concluir"; alvo: string | null }
  /** (Fase 3) agenda_entregar_dito: o alvo como o dono disse */
  | { comando: "entregar"; alvo: string }
  /** (Fase 3, P4) agenda_diaria_dita: a pessoa como o dono disse, a jornada e o dia (null = o da pergunta ou hoje) */
  | { comando: "diaria"; nome: string; jornada: JornadaDita; quando: string | null }
  /** (Fase 5, P5) agenda_cliente_decidir_dito: manda ou segura a mensagem ao cliente (alvo null = todas as que esperam) */
  | { comando: "cliente"; acao: "manda" | "segura"; alvo: string | null };

/** A jornada da palavra *diária*: inteira (também "dia inteiro"), meia ou não (não lançar / apagar). */
export type JornadaDita = "inteira" | "meia" | "nao";

const ver = (periodo: PeriodoDoComando | null, foco: FocoDoComando = "tudo", pessoa: "eu" | null = null): ComandoDaAgenda =>
  ({ comando: "ver", periodo, foco, pessoa });

/** A frase inteira (normalizada) → o comando. Montada uma vez; a ordem não importa (só igualdade). */
const FRASES = new Map<string, ComandoDaAgenda>();

function frases(lista: string[], cmd: ComandoDaAgenda): void {
  for (const f of lista) FRASES.set(f, cmd);
}

frases(["agenda", "a agenda", "agenda da semana", "agenda dessa semana", "agenda desta semana"], ver("semana"));
// "minha agenda" era a my_agenda (o dia: tarefas atrasadas, as do dia e os compromissos): vai ao dia, não à semana.
frases(["minha agenda", "agenda hoje", "agenda de hoje", "agenda pra hoje", "agenda para hoje"], ver("hoje"));
frases(
  ["agenda amanha", "agenda de amanha", "agenda pra amanha", "agenda para amanha", "o que tem pra amanha", "o que tem para amanha"],
  ver("amanha"),
);
frases(
  ["agenda semana que vem", "agenda da semana que vem", "agenda proxima semana", "agenda da proxima semana"],
  ver("proxima_semana"),
);
frases(["livre", "quando fica livre", "quando fico livre", "quando a gente fica livre"], ver(null, "livre"));
frases(
  ["atrasado", "atrasados", "atrasadas", "o que esta atrasado", "o que ta atrasado"],
  ver(null, "atrasos"),
);
// "o que eu tenho que fazer" e as variações (com ou sem "eu"; que / pra / para / de), com ou sem "hoje" no fim
for (const eu of ["o que eu tenho", "o que tenho"]) {
  for (const liga of ["que", "pra", "para", "de"]) {
    frases([`${eu} ${liga} fazer`, `${eu} ${liga} fazer hoje`], ver(null, "o_que_fazer", "eu"));
  }
}
frases(["o que tem pra fazer", "o que tem para fazer", "o que tem pra fazer hoje", "o que tem para fazer hoje"], ver(null, "o_que_fazer", "eu"));
frases(["grava", "gravar", "grave", "pode gravar", "grava tudo", "pode gravar tudo"], { comando: "gravar" });
frases(["descarta", "descartar", "descarte", "descarta tudo"], { comando: "descartar" });
// Fase 2: o que a agenda fez sozinha, o que ela precisa do dono e o plano publicado
frases(["o que mudou", "o que voce mudou", "agenda mudancas", "agenda mudou"], ver(null, "mudancas"));
frases(["agenda pendencias", "o que voce precisa de mim"], ver(null, "decisoes"));
frases(["agenda plano", "plano da semana"], ver(null, "plano"));
// Fase 3 (P6): a semana medida, o que a equipe respondeu e a comissão do mês (o mês dito vai pelas palavras com complemento)
frases(["agenda ppc", "como foi a semana"], ver(null, "ppc"));
frases(["agenda equipe"], ver(null, "equipe"));
frases(["comissao", "comissao do mes"], ver(null, "comissao"));
// Fase 4 (P6): o material e o prazo dos fornecedores
frases(["agenda compras"], ver(null, "compras"));
frases(["agenda fornecedores"], ver(null, "fornecedores"));
// Fase 5 (P5): as mensagens ao cliente
frases(["agenda clientes"], ver(null, "clientes"));
// Fase 6 (P8): o que a agenda aprendeu (o *desfaz aprendizado* já é o *desfaz <alvo>* da Fase 2: o banco resolve o alvo)
frases(["agenda aprendizado"], ver(null, "aprendizado"));

/** A maior frase da tabela: texto maior do que isto nunca é comando da tabela (custo zero na conversa comum). */
const MAIOR = Math.max(...[...FRASES.keys()].map((f) => f.length));

/** Todas as frases fixas (normalizadas) que viram comando — para os testes de colisão. */
export function frasesDaAgenda(): string[] {
  return [...FRASES.keys()];
}

// ─── Fase 2: as palavras com complemento (dia feito, dia não + motivo, choveu, desfaz) ─────────────────────

/** A palavra do motivo (uma, sem acento) → o código LCI de agenda_alocacoes.motivo (o banco aceita os dois). */
export const MOTIVOS_DO_DIA: Readonly<Record<string, string>> = Object.freeze({
  material: "material",
  cliente: "cliente_ou_bem",
  equipe: "equipe_faltou",
  anterior: "trabalho_anterior",
  informacao: "informacao",
  clima: "clima",
  estimativa: "estimativa",
  imprevisto: "imprevisto_tecnico",
  urgencia: "urgencia_outra_os",
  esqueci: "esqueci",
});

/** "hoje", "ontem", "anteontem", "segunda" (ou "segunda feira"), …, "sabado", "dd/mm". O banco resolve a data. */
const QUANDO = /^(?:hoje|ontem|anteontem|(?:segunda|terca|quarta|quinta|sexta)(?: feira)?|sabado|\d{1,2}\/\d{1,2})$/;

/** O alvo do *desfaz*: até 40 caracteres, nunca uma letra (com ou sem "o/a", "item", "letra"): "desfaz B" é do secretário. */
const ALVO_MAX = 40;
const ALVO_DE_LETRA = /^(?:(?:o|a) )?(?:(?:item|letra) )?[a-z]$/;
/**
 * O alvo é uma OS (o nome do cliente, até 3 palavras, ou o número): o que o prompt ensina para outras ferramentas
 * ("desfaz o agrupamento do ORÇ-00120" é desagrupar_orcamento; "desfaz a baixa da conta de luz" é estornar_pagamento;
 * "desfaz o último lançamento", "desfaz o pix do Roberto") e o "desfaz isso" sem dizer de quê vão ao modelo. Por isso o
 * alvo não tem conectivo ("do", "da", "de"…) nem estas palavras.
 */
const ALVO_MAX_PALAVRAS = 3;
const CONECTIVOS_DO_ALVO = new Set(["de", "do", "da", "dos", "das", "no", "na", "nos", "nas", "em", "pra", "para", "com", "por", "que"]);
const NAO_E_ALVO = new Set([
  "isso", "isto", "aquilo", "tudo", "ai", "agrupamento", "agrupar", "baixa", "pix", "pagamento", "pagamentos", "lancamento",
  "lancamentos", "estorno", "envio", "conta", "contas", "cobranca", "nota", "compra", "pedido", "orcamento", "item", "tarefa",
  "lembrete", "despesa", "recebimento", "transferencia", "mensagem", "diaria",
]);

/**
 * (Fase 6, correção C2) A coisa do *desfaz aprendizado <coisa>*: o item do que a agenda aprendeu (o fator, a presença, o
 * valor ou a diária, a folga, a capacidade ou a carga, os fornecedores). Já normalizado (sem acento): "presenca", "diaria".
 */
const COISA_DO_APRENDIZADO = /^(?:o )?aprendizado (fator|presenca|valor|diaria|folga|capacidade|carga|fornecedor)$/;

/** O nome do alvo (já sem "o/a/do/da") serve? Até 3 palavras, sem conectivo e sem as palavras de outras ferramentas. */
function alvoDeOs(nome: string): boolean {
  const palavras = nome.split(" ").filter(Boolean);
  if (palavras.length === 0 || palavras.length > ALVO_MAX_PALAVRAS) return false;
  if (palavras.some((p) => CONECTIVOS_DO_ALVO.has(p) || NAO_E_ALVO.has(p))) return false;
  return nome.replace(/ /g, "").length >= 2;
}

function quandoDito(s: string | undefined): string | null | undefined {
  if (s === undefined || s === "") return null;
  return QUANDO.test(s) ? s : undefined;
}

/**
 * O alvo de *desfaz*, *concluiu* e *entreguei*: até 40 caracteres, nunca uma letra; "o/a/do/da" na frente sai; o nome
 * passa pela régua de alvoDeOs. undefined = não serve (a frase vai ao modelo).
 */
function alvoDito(alvo: string): string | undefined {
  if (alvo.length > ALVO_MAX || ALVO_DE_LETRA.test(alvo)) return undefined;
  const nome = alvo.replace(/^(?:o|a|do|da) /, "");
  return alvoDeOs(nome) ? nome : undefined;
}

/** "dia feito [quando]", "dia nao|parcial [motivo] [quando]", "choveu [quando]", "desfaz [alvo]" → o comando, ou null. */
function lerPalavraComplemento(t: string): ComandoDaAgenda | null {
  let m = /^dia feito(?: (.+))?$/.exec(t);
  if (m) {
    const quando = quandoDito(m[1]);
    return quando === undefined ? null : { comando: "dia", resultado: "cumprido", motivo: null, quando };
  }
  m = /^dia (nao|parcial)(?: ([a-z]+))?(?: (.+))?$/.exec(t);
  if (m) {
    const resultado: ResultadoDoDia = m[1] === "nao" ? "nao_cumprido" : "parcial";
    let motivo: string | null = null;
    let resto = m[3];
    if (m[2] !== undefined) {
      if (MOTIVOS_DO_DIA[m[2]]) {
        motivo = MOTIVOS_DO_DIA[m[2]];
      } else {
        // sem motivo, mas com o dia ("dia nao ontem", "dia parcial segunda feira"): o banco pede o motivo do dia dito
        const comoDia = [m[2], m[3]].filter((x) => x !== undefined).join(" ");
        if (!QUANDO.test(comoDia)) return null;
        resto = comoDia;
      }
    }
    const quando = quandoDito(resto);
    return quando === undefined ? null : { comando: "dia", resultado, motivo, quando };
  }
  m = /^choveu(?: (.+))?$/.exec(t);
  if (m) {
    const quando = quandoDito(m[1]);
    return quando === undefined ? null : { comando: "choveu", quando };
  }
  m = /^(?:desfaz|desfazer|desfaca)(?: (.+))?$/.exec(t);
  if (m) {
    const alvo = (m[1] ?? "").trim();
    if (!alvo) return { comando: "desfazer", alvo: null };
    if (alvo.length > ALVO_MAX || ALVO_DE_LETRA.test(alvo)) return null;
    // "desfaz a semana", "desfaz semana" → "semana"; "desfaz o Nelson" → "nelson" (o banco resolve o nome)
    if (/^(?:a |da )?semana$/.test(alvo)) return { comando: "desfazer", alvo: "semana" };
    // Fase 6 (correção C2, item 6): *desfaz aprendizado <coisa>* — a coisa do aprendizado vale mesmo quando é palavra de
    // outra ferramenta no alvo de OS ("diaria" está em NAO_E_ALVO); o nome do fornecedor ("desfaz aprendizado Kamell")
    // segue a régua de sempre (alvoDito). O banco resolve as duas (agenda_desfazer_dito).
    const doAprendizado = COISA_DO_APRENDIZADO.exec(alvo);
    if (doAprendizado) return { comando: "desfazer", alvo: `aprendizado ${doAprendizado[1]}` };
    const nome = alvoDito(alvo);
    return nome === undefined ? null : { comando: "desfazer", alvo: nome };
  }
  // Fase 3: concluir (sem alvo só "concluiu") e entregar (sempre com alvo)
  m = /^(concluiu|concluido|concluida)(?: (.+))?$/.exec(t);
  if (m) {
    const alvo = (m[2] ?? "").trim();
    if (!alvo) return m[1] === "concluiu" ? { comando: "concluir", alvo: null } : null;
    const nome = alvoDito(alvo);
    return nome === undefined ? null : { comando: "concluir", alvo: nome };
  }
  m = /^(?:entreguei|entregue) (.+)$/.exec(t);
  if (m) {
    const nome = alvoDito(m[1].trim());
    return nome === undefined ? null : { comando: "entregar", alvo: nome };
  }
  // Fase 3 (P6): *comissão <mês>* ("comissão outubro", "comissão de setembro", "comissão do mês passado")
  m = /^comissao (?:de |do |em )?(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro|mes passado)$/.exec(t);
  if (m) return { comando: "ver", periodo: null, foco: "comissao", pessoa: null, mes: m[1] };
  // Fase 3 (P4): *diária <nome> inteira|meia|não [quando]* (também "dia inteiro" e "diária do/da <nome> …")
  m = /^diaria (.+?) (inteira|meia|nao|dia inteiro)(?: (.+))?$/.exec(t);
  if (m) {
    const nome = pessoaDita(m[1]);
    const quando = quandoDito(m[3]);
    if (nome === undefined || quando === undefined) return null;
    const jornada: JornadaDita = m[2] === "meia" ? "meia" : m[2] === "nao" ? "nao" : "inteira";
    return { comando: "diaria", nome, jornada, quando };
  }
  // Fase 5 (P5): *manda cliente [nome]* / *segura cliente [nome]* (o nome pela régua do *desfaz*)
  m = /^(manda|segura) cliente(?: (.+))?$/.exec(t);
  if (m) {
    const acao = m[1] as "manda" | "segura";
    const alvo = (m[2] ?? "").trim();
    if (!alvo) return { comando: "cliente", acao, alvo: null };
    // Correção C1 da Fase 5 (item 18): "manda cliente todos/todas/tudo" é o mesmo que sem nome (todas as que esperam);
    // "agora" e "depois" não são nome (NAO_E_CLIENTE: a frase vai ao modelo)
    if (/^(?:todos|todas|tudo)$/.test(alvo)) return { comando: "cliente", acao, alvo: null };
    const nome = alvoDito(alvo);
    if (nome === undefined || nome.split(" ").some((p) => NAO_E_CLIENTE.has(p))) return null;
    return { comando: "cliente", acao, alvo: nome };
  }
  return null;
}

/**
 * (Fase 5, P5) O que o dono manda AO cliente pelas outras ferramentas ("manda cliente o pdf", "manda cliente a foto",
 * "manda cliente o link"): não é nome de cliente — a frase vai ao modelo (o envio do orçamento e a mensagem com a
 * confirmação dele).
 */
const NAO_E_CLIENTE = new Set([
  "pdf", "link", "proposta", "foto", "fotos", "documento", "recibo", "boleto", "contrato", "arquivo", "video", "audio",
  "relatorio", "laudo", "comprovante", "valor", "preco", "desconto", "resumo", "os", "orc", "texto", "msg", "localizacao",
  // Correção C1 da Fase 5 (item 18): "manda cliente agora" / "manda cliente depois" não é nome de cliente
  "agora", "depois",
]);

/**
 * (Fase 5, P5) As palavras da mensagem ao cliente (*manda cliente*, *segura cliente*, *agenda clientes*): só valem com
 * agenda_config.modo_cliente fora de 'desligado' (antes disso não há mensagem da agenda ao cliente, e "manda cliente …" é
 * conversa com o modelo).
 */
export function ehPalavraDoCliente(cmd: ComandoDaAgenda): boolean {
  return cmd.comando === "cliente" || (cmd.comando === "ver" && cmd.foco === "clientes");
}

/**
 * A pessoa da palavra *diária*: "do/da/de" na frente sai; 1 ou 2 palavras de letras, cada uma com 2+ letras, sem conectivo
 * nem palavra de outra ferramenta ("diária do pix meia" vai ao modelo). undefined = não serve.
 */
function pessoaDita(dito: string): string | undefined {
  const nome = dito.trim().replace(/^(?:do|da|de) /, "");
  const palavras = nome.split(" ").filter(Boolean);
  if (palavras.length === 0 || palavras.length > 2) return undefined;
  if (palavras.some((p) => p.length < 2 || !/^[a-z]+$/.test(p) || CONECTIVOS_DO_ALVO.has(p) || NAO_E_ALVO.has(p))) return undefined;
  return palavras.join(" ");
}

/**
 * (Fase 3, P4) A palavra da diária automática: só vale com agenda_config.modo_diaria fora de 'desligado' (antes disso não
 * há diária da agenda para responder nem corrigir, e "diária …" é do registrar_diaria pelo modelo).
 */
export function ehPalavraDaDiaria(cmd: ComandoDaAgenda): boolean {
  return cmd.comando === "diaria";
}

/**
 * (Fase 2) As palavras da agenda que se monta sozinha: a conferência do dia, o *choveu*, o *desfaz* e os focos novos
 * ("o que mudou", "agenda pendências", "agenda plano"). Só valem com a agenda automática (modo_proposta ou modo_vigia)
 * fora de 'desligado': antes disso não há plano nem mudança dela, e "desfaz …" é de outras ferramentas.
 * (Fase 3) *concluiu* e *entreguei* também (spec-fase3 §11: "lida com modo_proposta ou modo_vigia ≠ desligado").
 */
export function ehPalavraDaFase2(cmd: ComandoDaAgenda): boolean {
  if (cmd.comando === "dia" || cmd.comando === "choveu" || cmd.comando === "desfazer") return true;
  if (cmd.comando === "concluir" || cmd.comando === "entregar") return true;
  return cmd.comando === "ver" && (cmd.foco === "mudancas" || cmd.foco === "decisoes" || cmd.foco === "plano");
}

/**
 * (Revisão da Fase 3, C1) As palavras que AGEM — concluem, entregam, lançam ou apagam diária, desfazem, anotam o dia ou a
 * chuva. Dita como pergunta ("Concluiu o Lenine?", "concluiu?", "Diária Roberto meia?", "desfaz?") ela não é ordem: vai ao
 * modelo, que responde. As palavras de VER continuam valendo com "?" ("agenda?", "livre?", "comissão?"). O *grava* e o
 * *descarta* ficam como na Fase 1 (só gravam o rascunho que o próprio dono acabou de conferir).
 */
const PALAVRAS_QUE_AGEM: ReadonlySet<ComandoDaAgenda["comando"]> = new Set([
  "concluir", "entregar", "diaria", "desfazer", "dia", "choveu",
  // (Fase 5, P5) "manda cliente Nelson?" é pergunta, não ordem
  "cliente",
]);

/** O texto termina em pergunta? O "?" final que o normalizarComando tira (também com negrito, espaço ou aspas depois). */
function terminaEmPergunta(texto: string): boolean {
  const fim = /[\s.!?,;:"'“”‘’«»]+$/u.exec(String(texto ?? "").replace(/[*_~]/g, "").trim());
  return fim !== null && fim[0].includes("?");
}

/** O comando, ou null (não é comando: segue para o assistente como sempre). */
export function lerComandoDaAgenda(texto: string): ComandoDaAgenda | null {
  if (typeof texto !== "string" || texto.length > 200) return null;
  const t = normalizarComando(texto);
  if (!t) return null;
  let cmd: ComandoDaAgenda | null = null;
  if (t.length <= MAIOR) {
    const fixo = FRASES.get(t);
    // cópia: quem chama não muda a tabela
    if (fixo) cmd = { ...fixo };
  }
  // Fase 2: as palavras com complemento (curtas: "desfaz" + até 40 caracteres; Fase 5: "segura cliente " + 40 é a maior)
  if (!cmd && t.length <= ALVO_MAX + 16) cmd = lerPalavraComplemento(t);
  // (C1) a pergunta do dono nunca vira ordem
  if (cmd && PALAVRAS_QUE_AGEM.has(cmd.comando) && terminaEmPergunta(texto)) return null;
  return cmd;
}
