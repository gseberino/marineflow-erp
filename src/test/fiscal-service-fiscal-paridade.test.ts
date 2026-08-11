// [F-NFSE-03] Guarda de paridade entre o resolvedor fiscal em SQL e o espelho em TypeScript.
//
// Aqui as duas implementações não são duas cópias de TypeScript (como em quote-deposit): uma
// é a função `public.resolve_service_fiscal`, no Postgres, e a outra é
// `_shared/fiscal/service-fiscal.ts`, no edge. Não dá para rodar as duas lado a lado sem um
// banco, então este teste faz a única coisa honesta que dá para fazer offline: LÊ a migration
// e verifica que a ordem de precedência declarada no SQL é a mesma que o TypeScript aplica.
//
// Não é o mesmo que executar as duas — e vale dizer com todas as letras. O que ele pega é a
// divergência que de fato acontece: alguém inverter um COALESCE de um lado e esquecer o outro,
// ou acrescentar herança a um campo em SQL sem espelhar. O que ele NÃO pega é diferença de
// semântica do próprio Postgres em tempo de execução.

import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  resolveServiceFiscal,
  semCodigoFiscal,
  type ServiceFiscalVerbDefaults,
} from "../../supabase/functions/_shared/fiscal/service-fiscal";

// O caminho do repositório tem espaço ("Claude Code"), então nada de montar path na mão.
const raizDoRepo = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const MIGRATION = join(
  raizDoRepo,
  "supabase",
  "migrations",
  "20260811003000_nfse_verbos_fiscais_com_heranca.sql",
);

/** A migration inteira — para as regras que vivem fora do corpo do resolvedor. */
function migrationDaHeranca(): string {
  return readFileSync(MIGRATION, "utf8");
}

function corpoDoResolvedor(): string {
  const sql = readFileSync(MIGRATION, "utf8");
  const inicio = sql.indexOf("create or replace function public.resolve_service_fiscal");
  expect(inicio, "a função resolve_service_fiscal sumiu da migration").toBeGreaterThan(-1);
  const fim = sql.indexOf("$fn$;", inicio);
  return sql.slice(inicio, fim);
}

/** Pares `coalesce(a, b)` na ordem em que aparecem no corpo da função. */
function paresCoalesce(corpo: string): Array<[string, string]> {
  return [...corpo.matchAll(/coalesce\(\s*([\w.]+)\s*,\s*([\w.]+)\s*\)/gi)]
    .map((m) => [m[1], m[2]] as [string, string]);
}

describe("paridade SQL × TypeScript — ordem de precedência", () => {
  it("o SQL herda os quatro campos do verbo, e sempre com o valor PRÓPRIO na frente", () => {
    const pares = paresCoalesce(corpoDoResolvedor());

    expect(pares).toEqual([
      ["s.national_tax_code", "f.default_national_tax_code"],
      ["s.service_code", "f.default_service_code"],
      ["s.cnae", "f.default_cnae"],
      ["s.iss_rate", "f.default_iss_rate"],
    ]);

    // O que este `toEqual` está protegendo, dito em português: o primeiro argumento é SEMPRE
    // a coluna do serviço. Invertido, o default do verbo passaria por cima do cadastro
    // específico — e o serviço que a contabilidade classificou à mão sairia com o código
    // genérico da atividade, sem ninguém notar.
    for (const [primeiro, segundo] of pares) {
      expect(primeiro.startsWith("s."), `${primeiro} deveria ser a coluna do serviço`).toBe(true);
      expect(segundo.startsWith("f."), `${segundo} deveria ser o default do verbo`).toBe(true);
    }
  });

  it("iss_withheld herda com TRÊS níveis: serviço → verbo → false (NOVO-014)", () => {
    // O gestor respondeu o NOVO-014 em 11/08/2026: nenhum `false` existente foi decisão de
    // retenção — vieram todos do DEFAULT da coluna, e o cadastro fiscal nunca foi preenchido.
    // A coluna virou nullable e NULL passou a significar "não decidido, herda do verbo".
    const corpo = corpoDoResolvedor();

    // No SQL: dentro de um coalesce de TRÊS argumentos, com `false` fechando.
    expect(corpo).toMatch(/coalesce\(\s*s\.iss_withheld,\s*f\.default_iss_withheld,\s*false\s*\)/);

    // Serviço decidiu: manda, mesmo contrariando o verbo.
    expect(resolveServiceFiscal({ iss_withheld: false }, { default_iss_withheld: true }).issWithheld)
      .toBe(false);
    expect(resolveServiceFiscal({ iss_withheld: true }, { default_iss_withheld: false }).issWithheld)
      .toBe(true);

    // Serviço não decidiu (NULL): herda o verbo. É este caso que o `=== true` de antes
    // achatava em `false`, matando a herança em silêncio.
    expect(resolveServiceFiscal({ iss_withheld: null }, { default_iss_withheld: true }).issWithheld)
      .toBe(true);

    // Ninguém decidiu: `false`, porque retenção precisa de resposta booleana.
    expect(resolveServiceFiscal({ iss_withheld: null }, null).issWithheld).toBe(false);
  });

  it("o verbo é o piso da herança de retenção — NOT NULL no banco", () => {
    // Se `default_iss_withheld` pudesse ser nulo, o COALESCE cairia no `false` final sem
    // ninguém ter decidido — o mesmo buraco que o NOVO-014 fechou do lado do serviço.
    const sql = migrationDaHeranca();
    expect(sql).toMatch(/default_iss_withheld\s+boolean\s+not null\s+default false/i);
  });

  it("a migration solta o NOT NULL de services.iss_withheld ANTES de apagar os false", () => {
    // Ordem importa: o UPDATE para NULL é rejeitado enquanto a coluna for NOT NULL.
    const sql = migrationDaHeranca();
    const posDrop = sql.search(/alter column iss_withheld drop not null/i);
    const posUpdate = sql.search(/set iss_withheld = null/i);
    expect(posDrop).toBeGreaterThan(-1);
    expect(posUpdate).toBeGreaterThan(posDrop);
  });

  it("o UPDATE só apaga false de serviço SEM nenhum campo fiscal preenchido", () => {
    // A salvaguarda: se alguém já tiver marcado retenção de propósito num serviço com
    // cadastro fiscal, este UPDATE não pode apagar essa decisão.
    const sql = migrationDaHeranca();
    const bloco = sql.slice(sql.search(/set iss_withheld = null/i), sql.search(/set iss_withheld = null/i) + 400);
    expect(bloco).toMatch(/national_tax_code is null/i);
    expect(bloco).toMatch(/cnae is null/i);
    expect(bloco).toMatch(/iss_rate is null/i);
  });

  it("o rótulo de procedência olha o código NACIONAL — igual ao CASE do SQL", () => {
    const corpo = corpoDoResolvedor();
    expect(corpo).toMatch(/when s\.national_tax_code is not null\s+then 'proprio'/);
    expect(corpo).toMatch(/when f\.default_national_tax_code is not null\s+then 'verbo'/);
    expect(corpo).toMatch(/else 'nenhum'/);

    expect(resolveServiceFiscal({ national_tax_code: "140101" }, null).codeSource).toBe("proprio");
    expect(resolveServiceFiscal({}, { default_national_tax_code: "140101" }).codeSource).toBe("verbo");
    expect(resolveServiceFiscal({}, null).codeSource).toBe("nenhum");
  });
});

describe("resolveServiceFiscal", () => {
  const verbo: ServiceFiscalVerbDefaults = {
    default_national_tax_code: "140101",
    default_service_code: "14.01",
    default_cnae: "3313901",
    default_iss_rate: 5,
  };

  it("o cadastro próprio do serviço vence o default do verbo", () => {
    const r = resolveServiceFiscal(
      { national_tax_code: "140601", cnae: "4321500", iss_rate: 3 },
      verbo,
    );
    expect(r.nationalTaxCode).toBe("140601");
    expect(r.cnae).toBe("4321500");
    expect(r.issRate).toBe(3);
    expect(r.codeSource).toBe("proprio");
  });

  it("serviço sem cadastro herda o verbo inteiro", () => {
    const r = resolveServiceFiscal({}, verbo);
    expect(r.nationalTaxCode).toBe("140101");
    expect(r.serviceCode).toBe("14.01");
    expect(r.cnae).toBe("3313901");
    expect(r.issRate).toBe(5);
    expect(r.codeSource).toBe("verbo");
  });

  it("herda campo a campo — cadastro pela metade não anula o resto", () => {
    // O serviço tem código próprio mas nunca recebeu CNAE: o CNAE ainda vem do verbo.
    const r = resolveServiceFiscal({ national_tax_code: "140601" }, verbo);
    expect(r.nationalTaxCode).toBe("140601");
    expect(r.cnae).toBe("3313901");
    expect(r.codeSource).toBe("proprio");
  });

  it("verbo com campos nulos (o estado de HOJE) não inventa nada", () => {
    // As dez linhas nascem assim: existem, e vazias. Herdar daqui não pode produzir código.
    const vazio: ServiceFiscalVerbDefaults = {
      default_national_tax_code: null,
      default_cnae: null,
      default_iss_rate: null,
    };
    const r = resolveServiceFiscal({}, vazio);
    expect(r.nationalTaxCode).toBeNull();
    expect(r.cnae).toBeNull();
    expect(r.codeSource).toBe("nenhum");
    expect(semCodigoFiscal(r)).toBe(true);
  });

  it("serviço sem verbo (o caso MÃO DE OBRA) fica pendente, não herda de ninguém", () => {
    const r = resolveServiceFiscal({ national_tax_code: null }, null);
    expect(r.nationalTaxCode).toBeNull();
    expect(semCodigoFiscal(r)).toBe(true);
  });

  it("alíquota ZERO é valor, não ausência", () => {
    // Clássico de `||` no lugar de coalesce: 0 é falsy e viraria 5 silenciosamente.
    const r = resolveServiceFiscal({ iss_rate: 0 }, verbo);
    expect(r.issRate).toBe(0);
  });

  it("string vazia não cede a vez — o Postgres também não cede", () => {
    const r = resolveServiceFiscal({ national_tax_code: "" }, verbo);
    expect(r.nationalTaxCode).toBe("");
    expect(semCodigoFiscal(r)).toBe(true); // vazio não emite nota
  });
});
