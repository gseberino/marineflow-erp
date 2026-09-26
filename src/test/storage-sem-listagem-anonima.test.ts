// Guarda estática dos buckets com dado de cliente (migration 20260926210000).
//
// Em 26/09/2026 o anônimo LISTAVA o bucket 'signatures' — 3 orçamentos assinados em PDF e 3
// assinaturas, em pastas com o id da OS — e o 'whatsapp_status'; os de comprovante de despesa
// e de foto de OS estavam vazios, mas todo arquivo novo já nasceria listável. A causa era a
// mesma do 'documents': regra de SELECT para public/anon só com `bucket_id = ...`, e as
// funções de listagem do Storage rodam com a permissão de quem chama.
//
// ═══ AS TRÊS METADES DA REGRA ═══
//
// 1. Nenhuma regra VIGENTE de leitura para public/anon pode citar esses quatro buckets. Uma
//    migration futura que recrie `create policy ... for select using (bucket_id = 'signatures')`
//    sem `to authenticated` (o padrão do Postgres é PUBLIC) reabre a listagem sem ninguém ver.
//
// 2. A leitura de quem está LOGADO segue a tabela dona de cada caminho — não o bucket inteiro.
//    expense-receipts guarda despesa (expenses/, tabela service_order_expenses: qualquer logado)
//    e SINAL (deposits/, tabela payments: só admin/financeiro); service-order-photos guarda
//    foto de OS (qualquer logado) e de levantamento (surveys/, service_surveys: menos vendedor
//    externo). Para cobrar isso sem banco, este teste AVALIA a expressão USING de cada regra
//    vigente contra perfis e objetos de exemplo, somando as permissivas por OR como o Postgres.
//    O avaliador conhece só o que as regras de storage.objects usam hoje; termo novo o faz
//    falhar alto, em vez de passar sem ter entendido.
//
// 3. Não quebrar a tela. Tirar a leitura pública derruba junto a leitura de quem está logado,
//    e o Storage exige SELECT em mais operações do que parece (storage-js 2.105): remove()
//    precisa de SELECT+DELETE e, sem SELECT, apaga ZERO objetos e devolve sucesso — "Excluir
//    esta foto" some da tela e o arquivo continua no ar pelo link. Upload com upsert:true (foto
//    do levantamento) precisa de SELECT+INSERT+UPDATE e falha com erro de RLS. Por isso este
//    teste lê o front, acha cada operação dessas nos quatro buckets e cobra que QUEM a faz
//    enxergue O CAMINHO que ela toca.
//
// O que ele NÃO faz: não conecta em banco. A prova em produção é
// `supabase/tests/storage_sem_listagem_anonima.sql` (read-only, olha com os olhos do anônimo e
// de cada perfil logado). E o repositório não é a produção: há regras que nasceram à mão no
// painel e não aparecem em migration nenhuma — o inventário fixo abaixo as põe no jogo, e cada
// uma de LEITURA precisa ser derrubada por nome numa migration.

import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

const raizDoRepo = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const DIR_MIGRATIONS = join(raizDoRepo, "supabase", "migrations");

const BUCKETS_COM_DADO_DE_CLIENTE = [
  "signatures",
  "expense-receipts",
  "service-order-photos",
  "whatsapp_status",
] as const;
const ehDeCliente = (b: string) => (BUCKETS_COM_DADO_DE_CLIENTE as readonly string[]).includes(b);

/** Métodos do storage-js 2.105 cuja nota "RLS policy permissions required" inclui `select`. */
const EXIGEM_SELECT = new Set([
  "remove", "list", "download", "createSignedUrl", "createSignedUrls",
  "move", "copy", "update", "info", "exists",
]);

type Regra = {
  nome: string;
  arquivo: string;
  comando: string;
  papeis: string[];
  buckets: string[];
  /** Miolo do USING, sem os parênteses de fora; null quando a regra não tem USING. */
  using: string | null;
  restritiva: boolean;
};

/**
 * Regras de LEITURA de storage.objects que existem em produção e não nascem de migration
 * nenhuma (criadas à mão no painel; pg_policies de 26/09/2026). O leitor de migrations não as
 * enxerga, então sem este inventário a garantia "nenhuma leitura anônima" dependeria de sorte.
 * Cada uma daqui precisa de `drop policy if exists <nome> on storage.objects` numa migration.
 *
 * whatsapp_status_auth_insert e whatsapp_status_auth_delete também só existem em produção, mas
 * são de escrita e ficam: a tela de status sobe a imagem com INSERT.
 */
const LEITURAS_CRIADAS_FORA_DAS_MIGRATIONS: Regra[] = [
  {
    nome: "whatsapp_status_public_read",
    arquivo: "(produção, criada fora das migrations)",
    comando: "SELECT",
    papeis: ["anon", "authenticated"],
    buckets: ["whatsapp_status"],
    using: "bucket_id = 'whatsapp_status'",
    restritiva: false,
  },
];

/** Texto das migrations em ordem, sem comentários de linha. */
function migrationsEmOrdem(): { arquivo: string; sql: string }[] {
  return readdirSync(DIR_MIGRATIONS)
    .filter((f) => f.endsWith(".sql"))
    .sort()
    .map((arquivo) => ({
      arquivo,
      sql: readFileSync(join(DIR_MIGRATIONS, arquivo), "utf8").replace(/--[^\n]*/g, ""),
    }));
}

/** O miolo de `using ( ... )`, respeitando parênteses aninhados e texto entre aspas. */
function clausulaUsing(corpo: string): string | null {
  const m = /\busing\s*\(/i.exec(corpo);
  if (!m) return null;
  const inicio = m.index + m[0].length;
  let nivel = 1;
  let emTexto = false;
  let i = inicio;
  for (; i < corpo.length && nivel > 0; i++) {
    const c = corpo[i];
    if (c === "'") emTexto = !emTexto;
    else if (!emTexto && c === "(") nivel++;
    else if (!emTexto && c === ")") nivel--;
  }
  return corpo.slice(inicio, i - 1);
}

/**
 * As regras de storage.objects VIGENTES: as criadas fora das migrations e, por cima, cada
 * CREATE das migrations valendo até um DROP posterior, na ordem dos arquivos e, dentro do
 * arquivo, na ordem do texto. Nome sem aspas o Postgres guarda em minúsculas; com aspas, como
 * está.
 */
function regrasVigentesDoStorage(): Map<string, Regra> {
  const vivas = new Map<string, Regra>(LEITURAS_CRIADAS_FORA_DAS_MIGRATIONS.map((r) => [r.nome, r]));
  const reEvento =
    /\b(create|drop)\s+policy\s+(?:if\s+exists\s+)?(?:"([^"]+)"|([a-z_][a-z0-9_]*))\s+on\s+storage\.objects\b([^;]*);/gi;

  for (const { arquivo, sql } of migrationsEmOrdem()) {
    for (const m of sql.matchAll(reEvento)) {
      const nome = m[2] ?? m[3].toLowerCase();
      if (nome.includes("%")) continue; // format string de bloco DO, não é regra literal
      if (m[1].toLowerCase() === "drop") {
        vivas.delete(nome);
        continue;
      }
      const corpo = m[4];
      const cabeca = corpo.split(/\busing\b|\bwith\s+check\b/i)[0].trim();
      const comando = /\bfor\s+(all|select|insert|update|delete)\b/i.exec(cabeca)?.[1].toUpperCase() ?? "ALL";
      const papeis = /\bto\s+([\w\s,"]+?)$/i.exec(cabeca)?.[1]
        .split(",")
        .map((p) => p.trim().replace(/"/g, "").toLowerCase()) ?? ["public"]; // sem TO = PUBLIC
      const buckets = [...corpo.matchAll(/'([^']+)'/g)].map((b) => b[1]);
      const restritiva = /\bas\s+restrictive\b/i.test(cabeca);
      vivas.set(nome, { nome, arquivo, comando, papeis, buckets, using: clausulaUsing(corpo), restritiva });
    }
  }
  return vivas;
}

/** Nomes derrubados por `drop policy if exists <nome> on storage.objects` em alguma migration. */
function derrubadasComIfExists(): Set<string> {
  const re = /\bdrop\s+policy\s+if\s+exists\s+(?:"([^"]+)"|([a-z_][a-z0-9_]*))\s+on\s+storage\.objects\b/gi;
  const nomes = new Set<string>();
  for (const { sql } of migrationsEmOrdem()) {
    for (const m of sql.matchAll(re)) nomes.add(m[1] ?? m[2].toLowerCase());
  }
  return nomes;
}

const lePrimeiro = (r: Regra) => r.comando === "SELECT" || r.comando === "ALL";

// ═══ O AVALIADOR DE REGRAS ═══════════════════════════════════════════════════════════════

type Valor = string | boolean | null;
type Perfil = { rotulo: string; papel: "anon" | "authenticated"; uid: string | null; cargos: string[] };
type Objeto = { bucket_id: string; name: string; owner_id: string | null };

const COLUNAS = new Set(["bucket_id", "name", "owner_id"]);

function tokenizar(expr: string): string[] {
  const re = /\s*(?:('(?:[^']|'')*')|(::\s*[a-z_]\w*)|(<>|!=|[()=,])|([a-z_][\w.]*))/giy;
  const texto = expr.trim();
  const saida: string[] = [];
  let pos = 0;
  while (pos < texto.length) {
    re.lastIndex = pos;
    const m = re.exec(texto);
    if (!m) throw new Error(`o avaliador não entende a regra a partir de «${texto.slice(pos, pos + 40)}»`);
    pos = re.lastIndex;
    if (m[2]) continue; // cast (::text): aqui texto e uuid já são a mesma string
    saida.push(m[1] ?? m[3] ?? m[4].toLowerCase());
  }
  return saida;
}

const likeCasa = (texto: string, padrao: string) => {
  const corpo = padrao.replace(/[.*+?^$()|[\]{}\\]/g, "\\$&").replace(/%/g, ".*").replace(/_/g, ".");
  return new RegExp("^" + corpo + "$", "s").test(texto);
};

/**
 * Avalia o USING de uma regra para um perfil e um objeto, com a lógica de três valores do SQL
 * (null não é true: a linha não aparece). Entende: colunas bucket_id/name/owner_id, texto
 * entre aspas, = <> like/not like, and/or/not, parênteses, `(select auth.uid())`, casts e as
 * funções de cargo. Qualquer outra coisa lança erro — melhor falhar do que adivinhar.
 */
function avaliar(expr: string, perfil: Perfil, obj: Objeto): Valor {
  const t = tokenizar(expr);
  let i = 0;
  const proximo = () => t[i];
  const consome = (esperado?: string): string => {
    const tok = t[i++];
    if (tok === undefined || (esperado !== undefined && tok !== esperado)) {
      throw new Error(`regra mal lida: esperava «${esperado ?? "algo"}», veio «${tok}» em: ${expr}`);
    }
    return tok;
  };
  const e = (a: Valor, b: Valor): Valor => (a === false || b === false ? false : a === null || b === null ? null : true);
  const ou = (a: Valor, b: Valor): Valor => (a === true || b === true ? true : a === null || b === null ? null : false);

  const chamar = (nome: string, args: Valor[]): Valor => {
    const temCargo = (...cargos: string[]) =>
      args[0] !== null && args[0] === perfil.uid && cargos.some((c) => perfil.cargos.includes(c));
    switch (nome.replace(/^public\./, "")) {
      case "auth.uid": return perfil.uid;
      case "is_admin": return temCargo("admin");
      case "is_admin_or_financial": return temCargo("admin", "financial");
      case "is_external_seller": return temCargo("external_seller");
      default: throw new Error(`função que o avaliador não conhece: ${nome} — ensine-a antes de confiar no resultado`);
    }
  };

  const primario = (): Valor => {
    const tok = consome();
    if (tok === "(") {
      let v: Valor;
      if (proximo() === "select") { // (select auth.uid()) — subconsulta escalar
        consome();
        v = disjuncao();
        if (proximo() === "as") { consome(); consome(); }
      } else {
        v = disjuncao();
      }
      consome(")");
      return v;
    }
    if (tok.startsWith("'")) return tok.slice(1, -1).replace(/''/g, "'");
    if (tok === "null") return null;
    if (tok === "true") return true;
    if (tok === "false") return false;
    if (proximo() === "(") {
      consome("(");
      const args: Valor[] = [];
      if (proximo() !== ")") {
        args.push(disjuncao());
        while (proximo() === ",") { consome(); args.push(disjuncao()); }
      }
      consome(")");
      return chamar(tok, args);
    }
    if (COLUNAS.has(tok)) return obj[tok as keyof Objeto];
    throw new Error(`termo que o avaliador não conhece: «${tok}» em: ${expr}`);
  };
  const comparacao = (): Valor => {
    const a = primario();
    const op = proximo();
    if (op === "=" || op === "<>" || op === "!=") {
      consome();
      const b = primario();
      if (a === null || b === null) return null;
      return op === "=" ? a === b : a !== b;
    }
    const negado = op === "not" && t[i + 1] === "like";
    if (negado) consome();
    if (proximo() === "like") {
      consome();
      const padrao = primario();
      if (a === null || padrao === null) return null;
      const casa = likeCasa(String(a), String(padrao));
      return negado ? !casa : casa;
    }
    return a;
  };
  const negacao = (): Valor => {
    if (proximo() !== "not") return comparacao();
    consome();
    const v = negacao();
    return v === null ? null : !v;
  };
  // Sem curto-circuito de propósito: o lado direito é sempre lido, para termo desconhecido
  // aparecer mesmo quando o esquerdo já decidiu.
  const conjuncao = (): Valor => {
    let v = negacao();
    while (proximo() === "and") { consome(); v = e(v, negacao()); }
    return v;
  };
  function disjuncao(): Valor {
    let v = conjuncao();
    while (proximo() === "or") { consome(); v = ou(v, conjuncao()); }
    return v;
  }

  const v = disjuncao();
  if (i !== t.length) throw new Error(`sobrou texto na regra: «${t.slice(i).join(" ")}» em: ${expr}`);
  return v;
}

/** O que o perfil enxerga: OR das permissivas que valem para o papel, AND das restritivas. */
function enxerga(perfil: Perfil, obj: Objeto, regras: Regra[]): boolean {
  const aplicaveis = regras.filter((r) => lePrimeiro(r) && r.papeis.some((p) => p === "public" || p === perfil.papel));
  const resultado = (r: Regra) => {
    if (r.using === null) throw new Error(`regra de leitura sem USING: ${r.nome} (${r.arquivo})`);
    return avaliar(r.using, perfil, obj) === true;
  };
  const permissivas = aplicaveis.filter((r) => !r.restritiva).map(resultado);
  const restritivas = aplicaveis.filter((r) => r.restritiva).map(resultado);
  return permissivas.some(Boolean) && restritivas.every(Boolean);
}

// Vendedor interno e técnico são o mesmo perfil para estas regras: nenhum dos dois é
// admin/financeiro nem vendedor externo.
const PERFIS: Record<"anonimo" | "tecnico" | "externo" | "financeiro" | "admin", Perfil> = {
  anonimo: { rotulo: "anônimo", papel: "anon", uid: null, cargos: [] },
  tecnico: { rotulo: "técnico/vendedor interno", papel: "authenticated", uid: "uid-tecnico", cargos: [] },
  externo: { rotulo: "vendedor externo", papel: "authenticated", uid: "uid-externo", cargos: ["external_seller"] },
  financeiro: { rotulo: "financeiro", papel: "authenticated", uid: "uid-financeiro", cargos: ["financial"] },
  admin: { rotulo: "admin", papel: "authenticated", uid: "uid-admin", cargos: ["admin"] },
};

const OBJETOS = {
  despesa: { bucket_id: "expense-receipts", name: "expenses/os-1/a.pdf", owner_id: "uid-outro" },
  sinal: { bucket_id: "expense-receipts", name: "deposits/os-2/b.jpg", owner_id: "uid-outro" },
  sinalQueOTecnicoSubiu: { bucket_id: "expense-receipts", name: "deposits/os-3/c.jpg", owner_id: "uid-tecnico" },
  fotoDaOs: { bucket_id: "service-order-photos", name: "os-1/d.jpg", owner_id: "uid-outro" },
  fotoDoLevantamento: { bucket_id: "service-order-photos", name: "surveys/sv-1/1-1727380000000.jpg", owner_id: "uid-outro" },
  assinatura: { bucket_id: "signatures", name: "os-1/signed-1.pdf", owner_id: null },
  status: { bucket_id: "whatsapp_status", name: "status/a.jpg", owner_id: "uid-admin" },
  logo: { bucket_id: "company-assets", name: "company/logo.png", owner_id: null },
} satisfies Record<string, Objeto>;

describe("buckets com dado de cliente — sem listagem anônima", () => {
  const regras = regrasVigentesDoStorage();

  it("nenhuma regra vigente de leitura para public/anon cita os quatro buckets", () => {
    const abertas = [...regras.values()]
      .filter((r) => lePrimeiro(r) && r.papeis.some((p) => p === "public" || p === "anon"))
      .filter((r) => r.buckets.some(ehDeCliente))
      .map((r) => `${r.nome} (${r.arquivo}, papéis ${r.papeis.join("/")})`);
    expect(abertas).toEqual([]);
  });

  it("o leitor de regras enxerga as públicas que DEVEM ficar (senão o teste acima passaria cego)", () => {
    const publicas = [...regras.values()]
      .filter((r) => lePrimeiro(r) && r.papeis.includes("public"))
      .map((r) => r.nome)
      .sort();
    expect(publicas).toEqual(["company_assets_public_read", "product_images_public_read"]);
  });

  it("cada leitura criada fora das migrations é derrubada por nome, com IF EXISTS, numa migration", () => {
    // IF EXISTS porque num banco novo (branch, ensaio local) a regra não existe, e um DROP
    // sem ele derrubaria a migration inteira.
    const derrubadas = derrubadasComIfExists();
    const faltando = LEITURAS_CRIADAS_FORA_DAS_MIGRATIONS
      .filter((r) => !derrubadas.has(r.nome))
      .map((r) => `${r.nome} (${r.papeis.join("/")} em ${r.buckets.join(", ")})`);
    expect(faltando).toEqual([]);
  });
});

describe("quem enxerga o quê — a leitura segue a tabela dona do caminho", () => {
  const regras = [...regrasVigentesDoStorage().values()];
  type Linha = [keyof typeof PERFIS, keyof typeof OBJETOS, boolean, string];
  const TABELA: Linha[] = [
    ["anonimo", "despesa", false, "nada de cliente para anônimo"],
    ["anonimo", "sinal", false, "nada de cliente para anônimo"],
    ["anonimo", "fotoDaOs", false, "nada de cliente para anônimo"],
    ["anonimo", "fotoDoLevantamento", false, "nada de cliente para anônimo"],
    ["anonimo", "assinatura", false, "nada de cliente para anônimo"],
    ["anonimo", "status", false, "nada de cliente para anônimo"],
    ["anonimo", "logo", true, "company-assets é público por natureza (e prova que o avaliador lê as públicas)"],

    ["tecnico", "despesa", true, "service_order_expenses: qualquer logado"],
    ["tecnico", "sinal", false, "payments: só admin/financeiro"],
    ["tecnico", "sinalQueOTecnicoSubiu", true, "quem anexou remove o que acabou de anexar"],
    ["tecnico", "fotoDaOs", true, "service_order_photos: qualquer logado"],
    ["tecnico", "fotoDoLevantamento", true, "service_surveys: todo mundo menos vendedor externo"],
    ["tecnico", "assinatura", false, "só a edge submit-signature mexe, com a chave de serviço"],
    ["tecnico", "status", false, "nenhuma tela lê o bucket de status pela API"],

    ["externo", "despesa", true, "service_order_expenses: qualquer logado"],
    ["externo", "sinal", false, "payments: só admin/financeiro"],
    ["externo", "sinalQueOTecnicoSubiu", false, "payments: só admin/financeiro"],
    ["externo", "fotoDaOs", true, "service_order_photos: qualquer logado"],
    ["externo", "fotoDoLevantamento", false, "service_surveys: NOT is_external_seller"],

    ["financeiro", "despesa", true, "qualquer logado"],
    ["financeiro", "sinal", true, "payments: admin/financeiro"],
    ["financeiro", "sinalQueOTecnicoSubiu", true, "payments: admin/financeiro"],
    ["financeiro", "fotoDoLevantamento", true, "não é vendedor externo"],

    ["admin", "sinal", true, "payments: admin/financeiro"],
    ["admin", "fotoDoLevantamento", true, "não é vendedor externo"],
  ];

  it("cada perfil enxerga exatamente o que a tabela dona do caminho deixa", () => {
    const divergentes = TABELA
      .filter(([p, o, esperado]) => enxerga(PERFIS[p], OBJETOS[o], regras) !== esperado)
      .map(([p, o, esperado, porque]) =>
        `${PERFIS[p].rotulo} × ${OBJETOS[o].bucket_id}/${OBJETOS[o].name}: devia ${esperado ? "" : "NÃO "}enxergar (${porque})`);
    expect(divergentes).toEqual([]);
  });
});

/** Todos os .ts/.tsx de uma pasta, sem testes (eles simulam o Storage, não o chamam). */
function arquivosDeCodigo(dir: string): string[] {
  const saida: string[] = [];
  const andar = (d: string) => {
    for (const nome of readdirSync(d)) {
      const caminho = join(d, nome);
      if (statSync(caminho).isDirectory()) {
        if (nome !== "node_modules") andar(caminho);
      } else if (/\.(ts|tsx)$/.test(nome) && !/\.test\.|_test\./.test(nome)) {
        saida.push(caminho);
      }
    }
  };
  andar(dir);
  return saida;
}

type Operacao = { arquivo: string; cliente: string; bucket: string; metodo: string; upsert: boolean };

/** Cada `<cliente>.storage.from('<bucket>').<método>(` do código, com o upsert do upload. */
function operacoesDeStorage(dirs: string[]): { operacoes: Operacao[]; cegas: string[] } {
  const operacoes: Operacao[] = [];
  const cegas: string[] = [];
  const reChamada = /(\w+)\s*\.storage\s*\.from\(\s*(['"`])([^'"`]+)\2\s*\)\s*\.(\w+)\(/g;
  for (const dir of dirs) {
    for (const caminho of arquivosDeCodigo(join(raizDoRepo, dir))) {
      const codigo = readFileSync(caminho, "utf8");
      const arquivo = relative(raizDoRepo, caminho).replace(/\\/g, "/");
      const legiveis = [...codigo.matchAll(reChamada)];
      for (const m of legiveis) {
        const resto = codigo.slice(m.index! + m[0].length, m.index! + m[0].length + 300).split(";")[0];
        operacoes.push({
          arquivo, cliente: m[1], bucket: m[3], metodo: m[4],
          upsert: m[4] === "upload" && /upsert\s*:\s*true/.test(resto),
        });
      }
      // Chamada que o leitor acima não entende (bucket em variável, from() guardado para
      // depois): o teste ficaria cego a ela e passaria por omissão.
      const todas = [...codigo.matchAll(/\.storage\s*\.from\(/g)].length;
      if (todas !== legiveis.length) cegas.push(`${arquivo} (${todas - legiveis.length} chamada(s))`);
    }
  }
  return { operacoes, cegas };
}

const chaveDaOperacao = (o: Operacao) => `${o.arquivo} ${o.bucket}.${o.metodo}${o.upsert ? "+upsert" : ""}`;

/**
 * Quem faz cada operação que exige SELECT, e em que caminho. Não basta existir "alguma regra
 * no bucket": a regra tem de deixar ESSE perfil enxergar ESSE objeto, senão o remove() apaga
 * zero em silêncio e o upsert falha. Operação nova nos quatro buckets entra aqui.
 */
const QUEM_FAZ: Record<string, { perfis: (keyof typeof PERFIS)[]; objeto: (p: Perfil) => Objeto; porque: string }> = {
  "src/components/ServiceOrderPhotos.tsx service-order-photos.remove": {
    perfis: ["tecnico", "externo", "financeiro", "admin"],
    objeto: () => OBJETOS.fotoDaOs,
    porque: "Excluir esta foto: qualquer logado apaga a foto de OS que outro subiu",
  },
  "src/hooks/use-service-survey.ts service-order-photos.upload+upsert": {
    perfis: ["tecnico", "financeiro", "admin"],
    objeto: (p) => ({ bucket_id: "service-order-photos", name: "surveys/sv-1/2-1727380000000.jpg", owner_id: p.uid }),
    porque: "foto do levantamento: INSERT ... ON CONFLICT DO UPDATE exige que a linha nova passe no SELECT",
  },
  "src/components/RegisterDepositDialog.tsx expense-receipts.remove": {
    perfis: ["tecnico", "externo", "financeiro", "admin"],
    objeto: (p) => ({ bucket_id: "expense-receipts", name: "deposits/os-2/novo.jpg", owner_id: p.uid }),
    porque: "remover comprovante do sinal: apaga o arquivo que o próprio usuário acabou de anexar",
  },
  "src/components/ServiceOrderForm.tsx expense-receipts.remove": {
    perfis: ["tecnico", "externo", "financeiro", "admin"],
    objeto: () => OBJETOS.despesa,
    porque: "remover comprovante da despesa: o caminho vem da despesa salva, que outro pode ter subido",
  },
};

describe("front — toda operação que exige SELECT tem a regra para quem a faz", () => {
  const regras = [...regrasVigentesDoStorage().values()];
  const { operacoes, cegas } = operacoesDeStorage(["src", "api"]);
  const nosQuatro = operacoes.filter((o) => ehDeCliente(o.bucket));
  const exigemSelect = nosQuatro.filter((o) => EXIGEM_SELECT.has(o.metodo) || o.upsert);

  it("o leitor entende toda chamada de Storage do front", () => {
    expect(cegas).toEqual([]);
  });

  it("acha as operações conhecidas (senão a cobrança abaixo passaria por omissão)", () => {
    const vistas = new Set(exigemSelect.map(chaveDaOperacao));
    expect([...vistas].sort()).toEqual(Object.keys(QUEM_FAZ).sort());
  });

  it("quem faz cada remove/upsert enxerga o caminho que ele toca", () => {
    const problemas: string[] = [];
    for (const o of exigemSelect) {
      const uso = QUEM_FAZ[chaveDaOperacao(o)];
      if (!uso) {
        problemas.push(`${chaveDaOperacao(o)}: operação nova — diga em QUEM_FAZ quem a faz e em que caminho`);
        continue;
      }
      for (const p of uso.perfis) {
        const obj = uso.objeto(PERFIS[p]);
        if (!enxerga(PERFIS[p], obj, regras)) {
          problemas.push(`${chaveDaOperacao(o)}: ${PERFIS[p].rotulo} não enxerga ${obj.name} (${uso.porque})`);
        }
      }
    }
    expect(problemas).toEqual([]);
  });
});

describe("edge functions — os quatro buckets só com a chave de serviço", () => {
  // O bucket 'signatures' não ganhou leitura para logado porque só a edge submit-signature
  // mexe nele, com o cliente `admin` (chave de serviço, que ignora a RLS). Se uma função
  // passar a usar o cliente do usuário nesses buckets, essa premissa cai e a regra precisa
  // ser revista.
  it("toda chamada de Storage nos quatro buckets usa o cliente admin", () => {
    // Aqui basta o from(): o método pode vir depois, numa variável, e continua sendo o cliente
    // que decide se a RLS vale.
    const reFrom = /(\w+)\s*\.storage\s*\.from\(\s*(['"`])([^'"`]+)\2\s*\)/g;
    const comUsuario: string[] = [];
    let vistasComAdmin = 0;
    for (const caminho of arquivosDeCodigo(join(raizDoRepo, "supabase", "functions"))) {
      const arquivo = relative(raizDoRepo, caminho).replace(/\\/g, "/");
      for (const m of readFileSync(caminho, "utf8").matchAll(reFrom)) {
        if (!ehDeCliente(m[3])) continue;
        if (m[1] === "admin") vistasComAdmin++;
        else comUsuario.push(`${arquivo}: ${m[1]}.storage.from('${m[3]}')`);
      }
    }
    expect(comUsuario).toEqual([]);
    // submit-signature: upload + getPublicUrl do PNG e do PDF assinado.
    expect(vistasComAdmin).toBeGreaterThanOrEqual(4);
  });
});
