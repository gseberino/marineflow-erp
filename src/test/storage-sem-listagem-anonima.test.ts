// Guarda estática dos buckets com dado de cliente (migration 20260926210000).
//
// Em 26/09/2026 o anônimo LISTAVA o bucket 'signatures' — 3 orçamentos assinados em PDF e 3
// assinaturas, em pastas com o id da OS — e o 'whatsapp_status'; os de comprovante de despesa
// e de foto de OS estavam vazios, mas todo arquivo novo já nasceria listável. A causa era a
// mesma do 'documents': regra de SELECT para public/anon só com `bucket_id = ...`, e as
// funções de listagem do Storage rodam com a permissão de quem chama.
//
// ═══ AS DUAS METADES DA REGRA ═══
//
// 1. Nenhuma regra VIGENTE de leitura para public/anon pode citar esses quatro buckets. Uma
//    migration futura que recrie `create policy ... for select using (bucket_id = 'signatures')`
//    sem `to authenticated` (o padrão do Postgres é PUBLIC) reabre a listagem sem ninguém ver.
//
// 2. A outra metade é não quebrar a tela. Tirar a leitura pública derruba junto a leitura de
//    quem está logado, e o Storage exige SELECT em mais operações do que parece (storage-js
//    2.105): remove() precisa de SELECT+DELETE e, sem SELECT, apaga ZERO objetos e devolve
//    sucesso — "Excluir esta foto" some da tela e o arquivo continua no ar pelo link. Upload
//    com upsert:true (foto do levantamento) precisa de SELECT+INSERT+UPDATE e falha com erro de
//    RLS. Por isso este teste lê o front, acha cada operação dessas nos quatro buckets e cobra
//    a regra de SELECT para authenticated. Ensaiado num Postgres 17 local: sem a regra, o
//    remove() da foto voltou 0 linhas e o upsert deu "new row violates row-level security".
//
// O que ele NÃO faz: não conecta em banco. A prova em produção é
// `supabase/tests/storage_sem_listagem_anonima.sql` (read-only, olha com os olhos do anônimo).
// E o repositório não é a produção: as regras do whatsapp_status nasceram fora das migrations
// — por isso a migration derruba por nome E verifica pelo texto das regras no pg_policies.

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

/** Métodos do storage-js 2.105 cuja nota "RLS policy permissions required" inclui `select`. */
const EXIGEM_SELECT = new Set([
  "remove", "list", "download", "createSignedUrl", "createSignedUrls",
  "move", "copy", "update", "info", "exists",
]);

type Regra = { nome: string; arquivo: string; comando: string; papeis: string[]; buckets: string[] };

/**
 * As regras de storage.objects VIGENTES ao fim de todas as migrations: cada CREATE vale até um
 * DROP posterior, na ordem dos arquivos e, dentro do arquivo, na ordem do texto. Nome sem
 * aspas o Postgres guarda em minúsculas; com aspas, como está.
 */
function regrasVigentesDoStorage(): Map<string, Regra> {
  const vivas = new Map<string, Regra>();
  const reEvento =
    /\b(create|drop)\s+policy\s+(?:if\s+exists\s+)?(?:"([^"]+)"|([a-z_][a-z0-9_]*))\s+on\s+storage\.objects\b([^;]*);/gi;

  const arquivos = readdirSync(DIR_MIGRATIONS).filter((f) => f.endsWith(".sql")).sort();
  for (const arquivo of arquivos) {
    const sql = readFileSync(join(DIR_MIGRATIONS, arquivo), "utf8").replace(/--[^\n]*/g, "");
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
      vivas.set(nome, { nome, arquivo, comando, papeis, buckets });
    }
  }
  return vivas;
}

const lePrimeiro = (r: Regra) => r.comando === "SELECT" || r.comando === "ALL";

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

describe("buckets com dado de cliente — sem listagem anônima", () => {
  const regras = regrasVigentesDoStorage();

  it("nenhuma regra vigente de leitura para public/anon cita os quatro buckets", () => {
    const abertas = [...regras.values()]
      .filter((r) => lePrimeiro(r) && r.papeis.some((p) => p === "public" || p === "anon"))
      .filter((r) => r.buckets.some((b) => (BUCKETS_COM_DADO_DE_CLIENTE as readonly string[]).includes(b)))
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
});

describe("front — toda operação que exige SELECT tem a regra para logado", () => {
  const regras = regrasVigentesDoStorage();
  const { operacoes, cegas } = operacoesDeStorage(["src", "api"]);
  const nosQuatro = operacoes.filter((o) =>
    (BUCKETS_COM_DADO_DE_CLIENTE as readonly string[]).includes(o.bucket));

  it("o leitor entende toda chamada de Storage do front", () => {
    expect(cegas).toEqual([]);
  });

  it("acha as operações conhecidas (senão a cobrança abaixo passaria por omissão)", () => {
    const vistas = new Set(nosQuatro.map((o) => `${o.bucket}:${o.metodo}${o.upsert ? "+upsert" : ""}`));
    expect(vistas).toContain("service-order-photos:remove");       // Excluir esta foto
    expect(vistas).toContain("service-order-photos:upload+upsert"); // foto do levantamento
    expect(vistas).toContain("expense-receipts:remove");            // remover comprovante
  });

  it("remove/list/download/upsert nesses buckets têm SELECT para authenticated", () => {
    const semRegra = nosQuatro
      .filter((o) => EXIGEM_SELECT.has(o.metodo) || o.upsert)
      // PUBLIC inclui authenticated; regra PUBLIC nesses buckets já é barrada no bloco de cima.
      .filter((o) => ![...regras.values()].some((r) =>
        lePrimeiro(r) && (r.papeis.includes("authenticated") || r.papeis.includes("public"))
        && r.buckets.includes(o.bucket)))
      .map((o) => `${o.arquivo}: ${o.bucket}.${o.metodo}${o.upsert ? " (upsert)" : ""}`);
    expect(semRegra).toEqual([]);
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
        if (!(BUCKETS_COM_DADO_DE_CLIENTE as readonly string[]).includes(m[3])) continue;
        if (m[1] === "admin") vistasComAdmin++;
        else comUsuario.push(`${arquivo}: ${m[1]}.storage.from('${m[3]}')`);
      }
    }
    expect(comUsuario).toEqual([]);
    // submit-signature: upload + getPublicUrl do PNG e do PDF assinado.
    expect(vistasComAdmin).toBeGreaterThanOrEqual(4);
  });
});
