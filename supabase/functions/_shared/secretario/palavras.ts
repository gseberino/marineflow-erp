// As palavras do secretário (16/10/2026): a MESMA regra para a manhã (ai-daily-briefing/secretario-candidatos.ts)
// e para o "me acorde se" (_shared/uma-voz/acorde.ts). Regra de palavras, sem IA. Tudo sobre o texto já
// passado por paraBusca (sem acento, minúsculo).
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md §3.1.

import { paraBusca } from "./base.ts";

// PEDIR preço, não falar de preço (ensaio de 15/10: "preço de tabela… proposta diferenciada" era um vendedor
// oferecendo, e "diferença de preços entre a 288 e 628" era conversa de fornecedor). Vale: "quanto fica/custa…",
// "qual o valor", "me passa o orçamento", "preciso de um orçamento", "orçar", "quero fechar".
export const PEDE_PRECO = new RegExp(String.raw`\b(?:` + [
  String.raw`quanto (?:custa|custaria|fica|ficaria|sai|sairia|cobra|cobram|cobraria|seria|e|vai ficar|vale)`,
  String.raw`(?:qual|quais) (?:e |seria |sera |o |a |os |as )*(?:valor|valores|preco|precos)`,
  String.raw`(?:passa|passe|manda|mande|envia|envie|faz|faca|ve) (?:me |pra mim |para mim )?(?:o |um |uma |a |os )?(?:orcamento|orcamentos|preco|valor|proposta|cotacao)`,
  // o infinitivo só é pedido com quem pede na frente (16/10/2026: "o PIX pode ser feito após a expedição finalizar
  // e passar o valor do frete" era o fornecedor Jaison avisando, e virou o B da manhã-sombra)
  String.raw`(?:pode|podes|poderia|consegue|conseguiria|tem como|teria como|da pra|da para|favor|por favor) (?:me )?(?:passar|mandar|enviar|fazer|ver) (?:pra mim |para mim )?(?:o |um |uma |a |os )?(?:orcamento|orcamentos|preco|valor|proposta|cotacao)`,
  String.raw`(?:preciso|precisava|precisamos|gostaria|queria|quero) (?:de )?(?:um |uma |o |a )?(?:orcamento|preco|valor|cotacao|proposta)`,
  String.raw`orcar|orcamento pra|orcamento para`,
  String.raw`(?:quero|vamos|podemos|queremos|quer) fechar`,
].join("|") + String.raw`)\b`);

/** Pressa: "hoje", "urgente", "o quanto antes"… */
export const COM_PRESSA = /\b(hoje|urgente|urgencia|ainda hoje|o quanto antes|o mais rapido)\b/;

/**
 * Quer fechar (spec §3.1): "quero/vamos/podemos/pode/preciso fechar", "fechado", "está aprovado", "pode/favor
 * seguir". "fechado" sozinho a whatsapp_esperando_resposta já trata como "ok" (encerrada) — aqui vale quando vem
 * numa frase.
 */
export const QUER_FECHAR =
  /\b(?:(?:quero|queremos|vamos|podemos|pode|posso|preciso|precisamos|precisava)(?: de)? fechar|fechado|esta aprovado|ta aprovado|(?:pode|podem|favor) seguir)\b/;

/** O lead PEDE algo (para a pressa contar num contato sem cadastro): pergunta, "consegue", "tem disponibilidade"… */
export const PEDIDO_DE_LEAD = /\?|\b(?:consegue|conseguem|conseguiria|pode|podem|poderia|tem disponibilidade|teria disponibilidade|quanto|orcamento)\b/;

/** Condicional ("se aprovado…", "caso aprovem…"): não é pressa de verdade (spec §3.1). */
export const CONDICIONAL = /\b(?:se (?:for |forem )?aprovad|caso (?:seja |sejam )?aprov|se aprovarem)/;

/**
 * As palavras de um agradecimento, cumprimento ou confirmação (sem acento, minúsculas). Uma mensagem feita SÓ delas
 * (e de emoji) não pede nada. Fica de fora de propósito o que pede ou pergunta (quanto, manda, consegue, pode, hoje,
 * orçamento…): basta uma palavra fora da lista para não ser "só agradecimento".
 */
const SO_AGRADECIMENTO = new Set([
  // agradecer
  "obrigado", "obrigada", "obrigados", "obrigadas", "obg", "brigado", "brigada", "valeu", "vlw", "agradeco", "grato", "grata",
  // confirmar / aprovar a conversa
  "ok", "okay", "okk", "blz", "beleza", "show", "top", "otimo", "otima", "perfeito", "perfeita", "combinado", "fechado", "certo",
  "certinho", "joia", "legal", "massa", "maravilha", "excelente", "tranquilo", "sim", "isso", "entendi", "ta", "bom", "boa",
  // cumprimentar e despedir
  "bom", "dia", "tarde", "noite", "oi", "ola", "opa", "abraco", "abracos", "abs", "ate", "mais", "tudo", "bem", "de", "nada",
  // o nome do dono e os enchimentos
  "gustavo", "e", "muito", "demais", "entao", "ah", "kkk", "kkkk", "rs",
]);

/** Confirmação opcional + "vou dar sequência", "pode deixar (comigo)", "vou providenciar", "(assim que sair) te aviso". */
const ENCERRA_AGINDO = new RegExp(
  String.raw`^(?:(?:` + [...SO_AGRADECIMENTO].join("|") + String.raw`) )*(?:` + [
    String.raw`(?:ja )?vou dar (?:sequencia|seguimento|andamento)(?: (?:aqui|no pedido|nisso))?`,
    String.raw`(?:ja )?(?:estou|to|tou) dando (?:sequencia|seguimento|andamento)`,
    String.raw`pode deixar(?: comigo)?`,
    String.raw`(?:ja )?(?:vou providenciar|providencio|estou providenciando)`,
    String.raw`(?:assim que (?:sair|tiver|chegar|ficar pronto) )?(?:eu )?(?:te|lhe) (?:aviso|retorno|confirmo)`,
  ].join("|") + String.raw`)(?: (?:` + [...SO_AGRADECIMENTO].join("|") + String.raw`))*$`,
);

/**
 * (16/10/2026) A mensagem é SÓ cumprimento, agradecimento, confirmação ou emoji ("Bom dia Gustavo! Ótimo 👍", "Obrigado!",
 * "ok", "👍") — sem pergunta e sem pedido. Quem mandou isso não está "sem resposta": a conversa acabou de um jeito
 * educado. Pergunta ("?") ou qualquer palavra fora da lista ("Obrigado, e quanto fica?", "ok, me manda o orçamento")
 * NÃO é. Áudio, foto e arquivo também não (o conteúdo não se lê aqui). A regra da whatsapp_esperando_resposta
 * (`encerrada`) só pegava a mensagem que é exatamente "ok/obrigado"; esta pega o cumprimento junto.
 * Usada pela manhã (candidatos de conversa) e pelo fechamento (F1). O detector do "me acorde se" não precisa: ele exige
 * palavra de pressa, fechar ou desistência.
 */
export function pareceSoAgradecimento(texto: string | null | undefined): boolean {
  const bruto = String(texto ?? "").trim();
  if (!bruto || bruto.includes("?")) return false;
  if (/^\s*(?:🎤|\[(?:audio|image|video|document|conteúdo vazio)\])/u.test(bruto)) return false;
  const semEmoji = bruto.replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}\u{1F3FB}-\u{1F3FF}]/gu, " ");
  const palavras = semEmoji.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z]+/g, " ").trim().split(" ").filter(Boolean);
  if (!palavras.length) return semEmoji.trim() !== bruto; // só emoji (👍, 🙏): agradecimento; só pontuação: não
  if (palavras.every((p) => SO_AGRADECIMENTO.has(p))) return true;
  // (16/10/2026) o contato encerra dizendo que ELE vai agir ("Perfeito, vou dar sequencia" do fornecedor Jaison, que
  // virou o B da manhã-sombra): também não pede resposta. "Fico no aguardo"/"aguardo seu retorno" NÃO entram — aí
  // quem deve a resposta é o dono.
  return ENCERRA_AGINDO.test(palavras.join(" "));
}

/**
 * Cadastro genérico ("Cliente Final", "Consumidor Final") não é um assunto: no ensaio de 13/10 ele juntou num
 * item só o ORÇ-00103 (a lancha do Miguel), o caminhão da OS-00110 e três motorhomes — e um "B feito" valeria
 * para os cinco. Com ele, cada orçamento, OS ou cobrança vale por si (e não empresta valor a uma conversa). No
 * "me acorde se", quem está num cadastro genérico conta como lead (spec §3.1). Morava em
 * ai-daily-briefing/secretario-candidatos.ts até 16/10/2026 (lá continua reexportada).
 */
export function ehClienteGenerico(nome: string | null | undefined): boolean {
  return /^(?:cliente|consumidor) final$/.test(paraBusca(nome));
}
