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
// Só a frase inteira vale (normalizada pelo MESMO normalizarComando do secretário: sem acento, sem negrito, sem
// pontuação no fim, sem o 🎤 do áudio). Qualquer palavra a mais é conversa e vai ao modelo como sempre.
//
// NÃO PODE COLIDIR (provado em comandos_test.ts):
//   · a confirmação do assistente (whatsapp-channel.ts: sim/s/ok/confirmar/1 · não/nao/n/cancelar/2): nenhum comando
//     começa por elas, e nenhum é número;
//   · o secretário (_shared/secretario/comandos.ts): nenhum comando é letra, nenhum é lido por ele, e nada do que ele lê
//     é lido aqui ("tudo" é dele; "grava tudo" é daqui);
//   · os comprovantes (comprovantes/respostas.ts, lerComando) e o registro de pergunta ativa (whatsapp/pergunta-ativa.ts).
//     Exceção conhecida: "grava", "grave" e "pode gravar" já são um "sim" para lerSimNao (o "sim" do CMP). Com a agenda
//     ligada o webhook marca o texto como comando (quemResponde → assistente, como os do secretário), e citar a pergunta
//     do CMP continua mandando ao CMP. O CMP pede "*sim*"; a agenda pede "*grava*".

import { normalizarComando } from "../secretario/comandos.ts";

export type PeriodoDoComando = "semana" | "hoje" | "amanha" | "proxima_semana";
export type FocoDoComando = "tudo" | "livre" | "atrasos" | "o_que_fazer";

export type ComandoDaAgenda =
  /** agenda_ver com o período, o foco e a pessoa ("eu" no "o que eu tenho que fazer") */
  | { comando: "ver"; periodo: PeriodoDoComando | null; foco: FocoDoComando; pessoa: "eu" | null }
  /** agenda_rascunho_gravar: o rascunho que o dono conferiu vira fato */
  | { comando: "gravar" }
  /** agenda_rascunho_descartar */
  | { comando: "descartar" };

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

/** A maior frase da tabela: texto maior do que isto nunca é comando (custo zero na conversa comum). */
const MAIOR = Math.max(...[...FRASES.keys()].map((f) => f.length));

/** Todas as frases (normalizadas) que viram comando — para os testes de colisão. */
export function frasesDaAgenda(): string[] {
  return [...FRASES.keys()];
}

/** O comando, ou null (não é comando: segue para o assistente como sempre). */
export function lerComandoDaAgenda(texto: string): ComandoDaAgenda | null {
  if (typeof texto !== "string" || texto.length > 200) return null;
  const t = normalizarComando(texto);
  if (!t || t.length > MAIOR) return null;
  const cmd = FRASES.get(t);
  // cópia: quem chama não muda a tabela
  return cmd ? { ...cmd } : null;
}
