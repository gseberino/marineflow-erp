// Resolvedor por PALAVRA-CHAVE — o "a IA só comanda, o código executa".
//
// O LLM passa termos ("MultiPlus-II 12/3000"); este código casa cada termo contra o catálogo
// de forma DETERMINÍSTICA, na ordem: (1) APELIDO aprendido → (2) BUSCA FUZZY por trigrama
// (RPC search_products_trgm, tolera formatação/erro/acento) → pontuação por sobreposição de
// tokens para a escolha final. Traz o preço já praticado (com origem/data). Nunca interrompe
// por item: resolve tudo e REPORTA o que assumiu / o que ficou provisório.

export type ItemResolvido = {
  keyword: string;
  quantidade: number;
  status: "resolvido" | "assumido" | "provisorio";
  product_id?: string;
  nome?: string;
  preco_venda: number;
  custo: number;
  origem: string;
  candidatos?: number;
  preco_informado?: number;
};

/** Mesma regra do normalize_alias no banco: minúsculo, sem acento, espaços colapsados. */
export function normalizarTermo(s: string): string {
  return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
}

/** Tokens alfanuméricos. "MultiPlus-II 12/3000" -> [multiplus, ii, 12, 3000]. */
export function tokenizar(s: string): string[] {
  return normalizarTermo(s).split(/[^a-z0-9]+/i).filter((t) => t.length >= 2);
}

/** Só os tokens NUMÉRICOS do termo (identificam o modelo: "100/50" -> ["100","50"]). */
export function tokensNumericos(s: string): string[] {
  return tokenizar(s).filter((t) => /\d/.test(t));
}

// Palavras que denunciam ACESSÓRIO (não o equipamento principal). Se o candidato tem uma
// destas e o termo pedido NÃO, provavelmente casou um acessório no lugar do produto.
const ACESSORIO_RE = /\b(cabo|cabos|sensor|sensores|suporte|adaptador|conector|conectores|kit|remoto|capa|terminal|terminais|borne|bornes|prensa|luva)\b/;

/** Números do modelo pedido que NÃO aparecem como TOKEN no candidato. Comparação por token
 *  (não substring): "50" pedido não pode casar dentro de "250" do candidato. */
function numerosFaltando(termo: string, nome: string, sku: string | null): string[] {
  const alvoTokens = new Set(tokenizar(`${nome} ${sku || ""}`));
  // Número que vem antes de palavra de quantidade é QUANTO, não QUAL: em "10 metros de cabo
  // elétrico 70mm²" o modelo é 70mm e o 10 é o tamanho do rolo. Contar o 10 como modelo ausente
  // rejeitava "Cabo elétrico 70mm²", que é exatamente o produto pedido.
  const toks = tokenizar(termo);
  const quantidades = new Set<string>();
  for (let i = 0; i < toks.length - 1; i++) {
    if (/^\d+$/.test(toks[i]) && QUANTIDADE.has(toks[i + 1])) quantidades.add(toks[i]);
  }
  return tokensNumericos(termo).filter((n) => !alvoTokens.has(n) && !quantidades.has(n));
}

// Palavras que não identificam nada — não contam nem a favor nem contra na sobreposição.
const VAZIAS = new Set(["de", "da", "do", "para", "com", "sem", "em", "no", "na", "por", "ou", "e", "un", "pc"]);

/** Tokens que de fato identificam o item (fora preposição e afins). */
function tokensUteis(s: string): string[] {
  return tokenizar(s).filter((t) => !VAZIAS.has(t));
}

/**
 * O NÚCLEO do pedido: o primeiro token útil e não-numérico — o substantivo que diz O QUE é a peça.
 * "Terminal de olhal para cabo 25mm²" -> "terminal". "Fusível ANL 250A" -> "fusivel".
 *
 * Por que isto faltava e por que é a regra que mais importa: a pontuação casava por número e por
 * "ser acessório", e nunca comparava a COISA pedida. Foi assim que "Terminal de olhal 25mm²" virou
 * "SUPORTE PARA FACHO HOLMES 40X22-25MM" num orçamento real — o token `25mm` bateu (veio da medida
 * de um suporte) e ambos contêm palavra de acessório, então nenhum filtro disparou.
 */
export function nucleoDoTermo(termo: string): string | null {
  for (const t of tokensUteis(termo)) if (!/\d/.test(t) && !QUANTIDADE.has(t)) return t;
  return null;
}

/** Palavras de embalagem/quantidade: são o "quanto", não o "quê". "10 metros de cabo" pede CABO. */
const QUANTIDADE = new Set([
  "metro", "metros", "m", "kit", "kits", "par", "pares", "unidade", "unidades",
  "peca", "pecas", "rolo", "rolos", "caixa", "caixas", "conjunto", "jogo",
]);

/** Raiz aproximada: tira plural e sufixo curto, para "cabos"~"cabo" e "terminais"~"terminal". */
function raiz(t: string): string {
  return t.replace(/(oes|aes|ais|eis|is|ns|es|s)$/, "");
}

/**
 * O termo "fala do mesmo objeto" que o candidato? Verdadeiro se QUALQUER token útil não-numérico
 * do pedido aparece no candidato, tolerando plural.
 *
 * Por que não é mais só o PRIMEIRO token: veto por uma palavra posicional derruba casamento
 * perfeito em três formas de escrever que o dono usa todo dia — plural ("os cabos do inversor"),
 * marca ou categoria na frente ("Victron Cerbo GX", "Inversor MultiPlus-II") e unidade na frente
 * ("10 metros de cabo"). E anula a tolerância a erro de digitação que a busca por trigrama existe
 * para dar: "Disjuntro CC 200A" deixaria de achar "Disjuntor CC 200A".
 *
 * A regra continua pegando o bug que a originou, porque ali NENHUM token casa: "Terminal de olhal
 * para cabo 25mm²" não tem terminal, nem olhal, nem cabo em "SUPORTE PARA FACHO HOLMES".
 */
export function falaDoMesmoObjeto(termo: string, nome: string, sku: string | null): boolean {
  const alvo = tokenizar(`${nome} ${sku || ""}`);
  const alvoRaizes = new Set(alvo.map(raiz));
  const doTermo = tokensUteis(termo).filter((t) => !/\d/.test(t) && !QUANTIDADE.has(t));
  if (doTermo.length === 0) return true; // só números/quantidade: a regra não se aplica
  return doTermo.some((t) => alvoRaizes.has(raiz(t)) || alvo.some((a) => a.includes(t) || t.includes(a)));
}

/**
 * Siglas técnicas do pedido ausentes no candidato. Em eletroeletrônica a sigla é o TIPO da peça —
 * ANL, MRBF, MPPT, VSR, MIDI — e trocá-la troca o produto, mesmo com o resto todo igual.
 * "Fusível ANL 250A" e "Fusível Mega 250A/32V" compartilham palavra e número; só a sigla os separa.
 * Detecta pela grafia do termo ORIGINAL (por isso não recebe a versão normalizada).
 */
export function siglasFaltando(termoOriginal: string, nome: string, sku: string | null): string[] {
  const bruto = String(termoOriginal || "");
  const palavras = bruto.split(/[^A-Za-zÀ-ÿ0-9]+/).filter(Boolean);

  // O sinal é a MAIÚSCULA DESTACADA — só vale quando o texto tem minúsculas para contrastar.
  // Quem escreve "CABO PARA BATERIA 25MM" está gritando, não citando siglas; ali "PARA" não é o
  // tipo da peça, e tratá-la como tal rejeitaria "Cabo de bateria 25mm", que é o produto certo.
  const temMinuscula = palavras.some((p) => /[a-zà-ÿ]/.test(p));
  if (!temMinuscula) return [];

  const alvo = new Set(tokenizar(`${nome} ${sku || ""}`));
  return palavras
    .filter((p) => p.length >= 2 && p.length <= 6 && /^[A-ZÀ-Þ0-9]+$/.test(p) && /[A-ZÀ-Þ]/.test(p))
    .map((s) => normalizarTermo(s))
    // Preposição em caixa alta ("DE", "COM") não identifica peça nenhuma.
    .filter((s) => !VAZIAS.has(s))
    .filter((s) => !QUALIFICADOR_UNIVERSAL.has(s))
    .filter((s) => !alvo.has(s));
}

/**
 * Siglas que descrevem CONTEXTO, não o tipo da peça. "Fusível ANL 100A para proteção CC" pede o
 * mesmo fusível que "Fusível ANL 100A com porta-fusível" — o CC diz onde ele vai, não o que ele é,
 * e o nome do produto quase nunca o carrega. Tratá-las como sigla de tipo fazia o produto EXATO do
 * catálogo ser rejeitado, e o orçamento cadastrava uma duplicata valendo R$ 0,00.
 */
const QUALIFICADOR_UNIVERSAL = new Set([
  "cc", "ca", "dc", "ac", "v", "a", "ah", "w", "kw", "kv", "hz", "mm", "cm", "ip", "un", "pc",
]);

/** Fração dos tokens úteis do termo presentes no candidato. 1 = casou tudo. */
export function fracaoCasada(termo: string, nome: string, sku: string | null): number {
  const toks = tokensUteis(termo);
  if (toks.length === 0) return 0;
  const alvo = normalizarTermo(`${nome} ${sku || ""}`);
  return toks.filter((t) => alvo.includes(t)).length / toks.length;
}

/** Abaixo disto o candidato não é aceito nem como "assumido" — vira provisório com motivo.
 *  Metade dos tokens úteis é o mínimo para a linha valer o preço que carrega. */
export const PISO_DE_CONFIANCA = 0.5;

/**
 * Match FRACO = provável produto ERRADO, mesmo com tokens sobrepostos. Quatro regras, e o pedido
 * precisa passar por todas:
 *  - o NÚCLEO (o substantivo pedido) tem que estar no candidato — terminal ≠ suporte;
 *  - SIGLA técnica do pedido não pode faltar — ANL ≠ Mega;
 *  - número de modelo do termo ausente no candidato ("100/50" pedido, "250/100" achado);
 *  - candidato é acessório (cabo/sensor/suporte...) sem o termo pedir acessório;
 *  - e, por fim, um PISO: menos de metade dos tokens úteis casados não é casamento.
 * Nesses casos é mais honesto virar PROVISÓRIO (sem preço) do que assumir o preço de um item
 * que não é o pedido — foi o que poluía o total e exigia correção manual depois.
 */
export function matchFraco(termo: string, nome: string, sku: string | null): { fraco: boolean; motivo: string } {
  const alvo = normalizarTermo(`${nome} ${sku || ""}`);

  if (!falaDoMesmoObjeto(termo, nome, sku)) {
    const nucleo = nucleoDoTermo(termo);
    return { fraco: true, motivo: nucleo ? `pedido é "${nucleo}" e o candidato não é` : "candidato não corresponde ao pedido" };
  }

  const siglas = siglasFaltando(termo, nome, sku);
  if (siglas.length > 0) {
    return { fraco: true, motivo: `tipo diferente (falta ${siglas.join("/").toUpperCase()})` };
  }

  const faltando = numerosFaltando(termo, nome, sku);
  if (faltando.length > 0) return { fraco: true, motivo: `modelo diferente (falta ${faltando.join("/")})` };

  if (ACESSORIO_RE.test(alvo) && !ACESSORIO_RE.test(normalizarTermo(termo))) return { fraco: true, motivo: "candidato é acessório, não o equipamento" };

  const fracao = fracaoCasada(termo, nome, sku);
  if (fracao < PISO_DE_CONFIANCA) {
    return { fraco: true, motivo: `só ${Math.round(fracao * 100)}% do pedido casou` };
  }

  return { fraco: false, motivo: "" };
}

/** Pontua o candidato: nº de tokens do termo presentes no nome/sku; desempate por nome mais
 *  curto (mais específico). Penaliza número de modelo ausente e acessório no lugar do principal,
 *  para o candidato CERTO vencer os parecidos-porém-errados. */
export function pontuaCandidato(termo: string, nome: string, sku: string | null): number {
  const tokens = tokenizar(termo);
  const alvo = normalizarTermo(`${nome} ${sku || ""}`);
  let achou = 0;
  for (const t of tokens) if (alvo.includes(t)) achou++;
  let score = achou * 1000 - String(nome).length;
  score -= 5000 * numerosFaltando(termo, nome, sku).length; // modelo errado (número ausente) perde
  if (ACESSORIO_RE.test(alvo) && !ACESSORIO_RE.test(normalizarTermo(termo))) score -= 4000; // acessório perde
  return score;
}

function origemDoHistorico(row: any): string {
  const so = Array.isArray(row?.service_orders) ? row.service_orders[0] : row?.service_orders;
  const quando = so?.created_at || row?.created_at;
  const data = quando ? new Date(quando).toLocaleDateString("pt-BR") : null;
  if (so?.service_order_number && data) return `praticado na ${so.service_order_number} em ${data}`;
  if (data) return `praticado em ${data}`;
  return "praticado antes";
}

/**
 * Preço de venda da linha, na ordem de precedência: informado no pedido → praticado antes →
 * cadastro do catálogo. Zero em qualquer um deles é AUSÊNCIA de preço, não preço.
 *
 * O `??` que estava aqui deixava o zero vencer: um produto cadastrado sem preço (o que acontece
 * sempre que o item nasce de um orçamento sem estimativa) devolvia 0 e a linha entrava valendo
 * R$ 0,00 com status "resolvido" — sem aviso nenhum, porque tecnicamente "achou no catálogo".
 */
export function precoDoItem(informado: number | undefined, praticado: number | null, catalogo: unknown): number {
  if (informado != null && Number(informado) > 0) return Number(informado);
  if (praticado != null && Number(praticado) > 0) return Number(praticado);
  const cat = Number(catalogo);
  return Number.isFinite(cat) && cat > 0 ? cat : 0;
}

/** Preço já praticado deste produto (fonte da verdade de "valor já usado"). */
// Preferência de preço: último praticado a ESTE cliente → último praticado (global) → catálogo.
// Mesma precedência da RPC resolve_practiced_price (fonte de verdade), mantida aqui em TS só para
// preservar o número da OS na origem (que a RPC não devolve). Se mudar a regra, mude nos dois.
async function ultimoPreco(sb: any, productId: string, clientId?: string | null): Promise<{ preco: number | null; origem: string }> {
  // 1) Último praticado a ESTE cliente.
  if (clientId) {
    const { data: h1 } = await sb
      .from("service_order_parts")
      .select("unit_sale_snapshot, created_at, service_orders!inner(service_order_number, created_at, client_id)")
      .eq("product_id", productId)
      .eq("service_orders.client_id", clientId)
      // > 0, e não apenas "não nulo": um item cadastrado sem preço grava snapshot ZERO, e zero
      // lido como "preço praticado" faz a linha voltar valendo R$ 0,00 no orçamento seguinte —
      // com status "resolvido", sem aviso nenhum. Zero não é preço, é ausência de preço.
      .gt("unit_sale_snapshot", 0)
      .order("created_at", { ascending: false })
      .limit(1);
    const hh = ((h1 as any[]) || [])[0];
    if (hh?.unit_sale_snapshot != null) return { preco: Number(hh.unit_sale_snapshot), origem: origemDoHistorico(hh) };
  }
  // 2) Último praticado a qualquer cliente.
  const { data: hist } = await sb
    .from("service_order_parts")
    .select("unit_sale_snapshot, created_at, service_orders(service_order_number, created_at)")
    .eq("product_id", productId)
    .gt("unit_sale_snapshot", 0)   // mesmo motivo do bloco acima: zero não é preço praticado
    .order("created_at", { ascending: false })
    .limit(1);
  const h = ((hist as any[]) || [])[0];
  if (h?.unit_sale_snapshot != null) return { preco: Number(h.unit_sale_snapshot), origem: origemDoHistorico(h) };
  // 3) Catálogo (o caller preenche com sale_price).
  return { preco: null, origem: "cadastro atual do catálogo" };
}

/**
 * Resolve uma lista de itens (palavra-chave + quantidade + preço opcional), em paralelo.
 */
export async function resolverItens(
  sb: any,
  itens: Array<{ keyword: string; quantity?: number; unit_price?: number }>,
  clientId?: string | null,
): Promise<ItemResolvido[]> {
  return await Promise.all(
    itens.map(async (it): Promise<ItemResolvido> => {
      const termo = String(it.keyword || "").trim();
      const qtd = Number(it.quantity) || 1;
      const precoInformado = it.unit_price != null ? Number(it.unit_price) : undefined;
      const provisorio = (origem: string): ItemResolvido => ({ keyword: termo, quantidade: qtd, status: "provisorio", preco_venda: precoInformado ?? 0, custo: 0, origem, preco_informado: precoInformado });

      if (termo.length < 2) return provisorio("termo vazio");

      // 1) APELIDO aprendido — acerto direto, sem adivinhação.
      const norm = normalizarTermo(termo);
      const { data: alias } = await sb.from("product_aliases").select("product_id").eq("alias_normalized", norm).maybeSingle();
      if (alias?.product_id) {
        const { data: p } = await sb.from("products").select("id, name, cost_price, sale_price").eq("id", alias.product_id).maybeSingle();
        if (p) {
          const preco = await ultimoPreco(sb, p.id, clientId);
          return {
            keyword: termo, quantidade: qtd, status: "resolvido", product_id: p.id, nome: p.name,
            preco_venda: precoDoItem(precoInformado, preco.preco, p.sale_price),
            custo: p.cost_price != null ? Number(p.cost_price) : 0,
            origem: precoInformado != null ? "preço informado no pedido" : (preco.preco != null ? preco.origem : "apelido aprendido → cadastro"),
            preco_informado: precoInformado,
          };
        }
      }

      // 2) BUSCA FUZZY (trigrama) — tolera formatação, erro de digitação e acento.
      const { data: cands } = await sb.rpc("search_products_trgm", { _term: termo, _lim: 20 });
      const lista = (cands as any[]) || [];
      if (lista.length === 0) return provisorio("não encontrado no catálogo — aguardando cotação");

      // 3) Escolha final pela sobreposição COMPLETA de tokens (spec incluída), desempate por nome curto.
      lista.sort((a, b) => pontuaCandidato(termo, b.name, b.sku) - pontuaCandidato(termo, a.name, a.sku));
      const p = lista[0];

      // Match fraco (modelo diferente / acessório no lugar do principal) → PROVISÓRIO: melhor
      // sinalizar "cote isto" do que colocar no total o preço de um item que não é o pedido.
      const fraqueza = matchFraco(termo, p.name, p.sku);
      if (fraqueza.fraco) return provisorio(`${fraqueza.motivo}; mais perto: "${p.name}" — aguardando cotação`);

      const toks = tokenizar(termo);
      const alvo = normalizarTermo(`${p.name} ${p.sku || ""}`);
      const casados = toks.filter((t) => alvo.includes(t)).length;
      // Casou todos os tokens = alta confiança; parcial = assumido (o dono confirma).
      const status: ItemResolvido["status"] = toks.length > 0 && casados === toks.length ? "resolvido" : "assumido";

      const preco = await ultimoPreco(sb, p.id, clientId);
      const precoFinal = precoDoItem(precoInformado, preco.preco, p.sale_price);
      // Casou o produto certo, mas ninguém sabe por quanto vender: não é "resolvido". Marcar como
      // assumido faz a macro devolvê-lo em `confirmar`, e o dono vê a lacuna antes de mandar ao
      // cliente. Sem isto a linha entra valendo R$ 0,00 com cara de item conferido.
      const statusFinal: ItemResolvido["status"] = precoFinal > 0 ? status : "assumido";
      return {
        keyword: termo, quantidade: qtd, status: statusFinal, product_id: p.id, nome: p.name,
        preco_venda: precoFinal,
        custo: p.cost_price != null ? Number(p.cost_price) : 0,
        origem: precoFinal === 0
          ? "SEM PREÇO — o produto existe no catálogo mas não tem valor de venda"
          : (precoInformado != null && precoInformado > 0 ? "preço informado no pedido" : (preco.preco != null ? preco.origem : "cadastro atual do catálogo")),
        candidatos: lista.length,
        preco_informado: precoInformado,
      };
    }),
  );
}
