import { assert, assertEquals, assertMatch, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  caminhoNoBucket,
  chaveDoAviso,
  type DadosDoArquivo,
  extensaoDoMime,
  formatarCnpj,
  formatarReais,
  historicoDoAviso,
  type ItemDoAviso,
  lerLegenda,
  nomeNoDropbox,
  PASTA_A_CLASSIFICAR,
  PASTA_CANCELADOS,
  PASTA_COMPROVANTES,
  PASTA_PESSOAL,
  rotaDaMensagem,
  sha256HexSync,
  textoDoAviso,
} from "./nucleo.ts";

// ─── Legenda ──────────────────────────────────────────────────────────────────────────────

Deno.test("lerLegenda: sem legenda (nulo, vazio, só espaço)", () => {
  for (const c of [null, undefined, "", "   ", "\n"]) {
    assertEquals(lerLegenda(c), { forcado: false, dica: null, temTexto: false });
  }
});

Deno.test("lerLegenda: só a palavra-chave força e não tem texto", () => {
  for (const c of ["cupom", "Cupom", "CUPOM.", " nota ", "NF", "Pix", "comprovante!", "Recibo", "CMP", "pessoal", "Estoque", "ADM", "NF-e", "nfc-e", "NFS-e"]) {
    assertEquals(lerLegenda(c), { forcado: true, dica: null, temTexto: false }, c);
  }
});

Deno.test("lerLegenda: palavra-chave + só a referência de OS força, com texto e a OS na dica", () => {
  assertEquals(lerLegenda("cupom OS 123"), { forcado: true, dica: "OS 123", temTexto: true });
  assertEquals(lerLegenda("nota: os-45"), { forcado: true, dica: "os-45", temTexto: true });
  assertEquals(lerLegenda("NF-e OS123"), { forcado: true, dica: "OS123", temTexto: true });
});

Deno.test("lerLegenda: palavra-chave + texto livre NÃO força (a classificação decide), guarda a dica", () => {
  assertEquals(lerLegenda("cupom OS 123 Brisa"), { forcado: false, dica: "OS 123 Brisa", temTexto: true });
  assertEquals(lerLegenda("Comprovante: pix do João"), { forcado: false, dica: "pix do João", temTexto: true });
  assertEquals(lerLegenda("nf-e peças"), { forcado: false, dica: "peças", temTexto: true });
  // frases comuns que começam com palavra-chave
  assertEquals(lerLegenda("nota que o cliente mandou").forcado, false);
  assertEquals(lerLegenda("pessoal, olha isso").forcado, false);
  assertEquals(lerLegenda("empresa nova do Brisa").forcado, false);
  assertEquals(lerLegenda("estoque acabou").forcado, false);
});

Deno.test("lerLegenda: 'c' não é palavra-chave (no WhatsApp é 'você')", () => {
  assertEquals(lerLegenda("c"), { forcado: false, dica: null, temTexto: true });
  assertEquals(lerLegenda("c viu isso?"), { forcado: false, dica: null, temTexto: true });
});

Deno.test("lerLegenda: palavra-chave comparada sem acento", () => {
  assertEquals(lerLegenda("Comprovânte").forcado, true); // "comprovante" sem acento
  assertEquals(lerLegenda("NOTÁS").forcado, true); // "notas" sem acento
  assertEquals(lerLegenda("Notária").forcado, false); // outra palavra
});

Deno.test("lerLegenda: 'os <número>' nunca força — é a foto do serviço; a OS vai na dica", () => {
  assertEquals(lerLegenda("os 123"), { forcado: false, dica: "os 123", temTexto: true });
  assertEquals(lerLegenda("OS-123"), { forcado: false, dica: "OS-123", temTexto: true });
  assertEquals(lerLegenda("os123"), { forcado: false, dica: "os123", temTexto: true });
  assertEquals(lerLegenda("OS 0105 Brisa"), { forcado: false, dica: "OS 0105 Brisa", temTexto: true });
  assertEquals(lerLegenda("OS do Brisa"), { forcado: false, dica: null, temTexto: true });
  assertEquals(lerLegenda("os"), { forcado: false, dica: null, temTexto: true });
});

Deno.test("lerLegenda: legenda comum não força e tem texto", () => {
  assertEquals(lerLegenda("lança na OS do Brisa"), { forcado: false, dica: null, temTexto: true });
  assertEquals(lerLegenda("quanto ficou isso?"), { forcado: false, dica: null, temTexto: true });
  assertEquals(lerLegenda("😀"), { forcado: false, dica: null, temTexto: true });
  // "cupons" é palavra-chave; "cupomzinho" não
  assertEquals(lerLegenda("cupomzinho").forcado, false);
});

// ─── Rota ─────────────────────────────────────────────────────────────────────────────────

const BASE = { ehDono: true, mediaKind: "image" as const, temMsgId: true, caption: null as string | null };

Deno.test("rotaDaMensagem: off manda tudo ao agente", () => {
  assertEquals(rotaDaMensagem({ ...BASE, modo: "off" }), "agente");
  assertEquals(rotaDaMensagem({ ...BASE, modo: "off", caption: "cupom" }), "agente");
});

Deno.test("rotaDaMensagem: quem não é o dono, não-mídia ou sem id vai ao agente", () => {
  for (const modo of ["sombra", "dono"] as const) {
    assertEquals(rotaDaMensagem({ ...BASE, modo, ehDono: false }), "agente");
    assertEquals(rotaDaMensagem({ ...BASE, modo, mediaKind: null }), "agente");
    assertEquals(rotaDaMensagem({ ...BASE, modo, mediaKind: undefined }), "agente");
    assertEquals(rotaDaMensagem({ ...BASE, modo, temMsgId: false }), "agente");
  }
});

Deno.test("rotaDaMensagem: sombra é sempre ambos", () => {
  for (const caption of [null, "cupom", "cupom OS 1", "lança isso"]) {
    assertEquals(rotaDaMensagem({ ...BASE, modo: "sombra", caption }), "ambos");
    assertEquals(rotaDaMensagem({ ...BASE, modo: "sombra", caption, mediaKind: "document" }), "ambos");
  }
});

Deno.test("rotaDaMensagem: dono — a tabela da spec (3.2)", () => {
  assertEquals(rotaDaMensagem({ ...BASE, modo: "dono", caption: null }), "comprovante");
  assertEquals(rotaDaMensagem({ ...BASE, modo: "dono", caption: "cupom" }), "comprovante");
  assertEquals(rotaDaMensagem({ ...BASE, modo: "dono", caption: "cupom OS 123 Brisa" }), "ambos");
  assertEquals(rotaDaMensagem({ ...BASE, modo: "dono", caption: "lança na OS do Brisa" }), "ambos");
  assertEquals(rotaDaMensagem({ ...BASE, modo: "dono", caption: null, mediaKind: "document" }), "comprovante");
  // "os 123": o assistente continua anexando a foto à OS
  assertEquals(rotaDaMensagem({ ...BASE, modo: "dono", caption: "os 123" }), "ambos");
  assertEquals(rotaDaMensagem({ ...BASE, modo: "dono", caption: "c" }), "ambos");
});

Deno.test("rotaDaMensagem: documento que nunca é comprovante (xlsx, zip, docx) fica com o agente", () => {
  for (const modo of ["sombra", "dono"] as const) {
    for (const mimetype of [
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "application/vnd.ms-excel",
      "application/zip",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ]) {
      assertEquals(rotaDaMensagem({ ...BASE, modo, mediaKind: "document", mimetype }), "agente", `${modo} ${mimetype}`);
    }
    for (const mimetype of ["application/pdf", "application/xml", "text/xml", "image/jpeg", "application/octet-stream", null, ""]) {
      assertEquals(rotaDaMensagem({ ...BASE, modo, mediaKind: "document", mimetype }), modo === "dono" ? "comprovante" : "ambos", `${modo} ${mimetype}`);
    }
  }
  // imagem não olha o mimetype
  assertEquals(rotaDaMensagem({ ...BASE, modo: "dono", mimetype: "application/zip" }), "comprovante");
});

// ─── Extensão e caminho ───────────────────────────────────────────────────────────────────

Deno.test("extensaoDoMime: os tipos aceitos e o resto nulo", () => {
  assertEquals(extensaoDoMime("image/jpeg"), "jpg");
  assertEquals(extensaoDoMime("IMAGE/PNG"), "png");
  assertEquals(extensaoDoMime("image/webp"), "webp");
  assertEquals(extensaoDoMime("image/heic"), "heic");
  assertEquals(extensaoDoMime("image/heif"), "heic");
  assertEquals(extensaoDoMime("application/pdf"), "pdf");
  assertEquals(extensaoDoMime("application/pdf; charset=binary"), "pdf");
  assertEquals(extensaoDoMime("application/xml"), "xml");
  assertEquals(extensaoDoMime("text/xml"), "xml");
  assertEquals(extensaoDoMime("application/vnd.ms-excel"), null);
  assertEquals(extensaoDoMime(""), null);
});

Deno.test("caminhoNoBucket: mês de São Paulo, id em minúsculas", () => {
  const id = "0A1B2C3D-0000-4000-8000-00000000000F";
  // 02:00 UTC de 1º/11 ainda é 31/10 em São Paulo
  assertEquals(caminhoNoBucket(id, new Date("2026-11-01T02:00:00Z"), "jpg"), "2026/10/0a1b2c3d-0000-4000-8000-00000000000f.jpg");
  assertEquals(caminhoNoBucket(id, new Date("2026-11-01T03:30:00Z"), "pdf"), "2026/11/0a1b2c3d-0000-4000-8000-00000000000f.pdf");
  assertMatch(caminhoNoBucket(id, new Date(), "xml"), /^[0-9]{4}\/[0-9]{2}\/[0-9a-f-]{36}\.(jpg|png|webp|heic|pdf|xml)$/);
});

Deno.test("a pasta do Dropbox é constante", () => {
  assertEquals(PASTA_COMPROVANTES, "/MANAGEMENT/FINANCIALS/COMPROVANTES");
  assertEquals(PASTA_A_CLASSIFICAR, "/MANAGEMENT/FINANCIALS/COMPROVANTES/_A CLASSIFICAR");
});

// ─── Nome no Dropbox ──────────────────────────────────────────────────────────────────────

const DA: DadosDoArquivo = {
  id: "00000000-0000-4000-8000-000000000001",
  codigo: "CMP-00123",
  situacao: "lido",
  tipo: "nfce",
  valor: "62.00",
  valor_confianca: "alta",
  data_compra: "2026-10-08",
  hora_compra: "12:57:56",
  recebido_em: "2026-10-10T22:40:57Z",
  fornecedor_nome: "Auto Posto São João",
  arquivo_path: "2026/10/00000000-0000-4000-8000-000000000001.jpg",
  arquivo_mime: "image/jpeg",
};

Deno.test("nomeNoDropbox: completo com selo alta", () => {
  assertEquals(nomeNoDropbox(DA), "2026-10-08 12h57 CMP-00123 NFCE R$ 62,00 Auto Posto Sao Joao.jpg");
});

Deno.test("nomeNoDropbox: sem valor quando o selo não é alta", () => {
  assertEquals(nomeNoDropbox({ ...DA, valor_confianca: "media" }), "2026-10-08 12h57 CMP-00123 NFCE Auto Posto Sao Joao.jpg");
  assertEquals(nomeNoDropbox({ ...DA, valor_confianca: null }), "2026-10-08 12h57 CMP-00123 NFCE Auto Posto Sao Joao.jpg");
});

Deno.test("nomeNoDropbox: sem data usa o dia da chegada em SP; sem hora e sem fornecedor", () => {
  const d = { ...DA, data_compra: null, hora_compra: null, fornecedor_nome: null, recebido_em: "2026-11-01T02:00:00Z" };
  assertEquals(nomeNoDropbox(d), "2026-10-31 CMP-00123 NFCE R$ 62,00.jpg");
});

Deno.test("nomeNoDropbox: siglas, milhar e limpeza de caractere proibido", () => {
  const d = { ...DA, tipo: "boleto_pago", valor: "1234.5", fornecedor_nome: 'Marina "A/B": Ltda <filial>|01', arquivo_path: "2026/10/x.pdf" };
  assertEquals(nomeNoDropbox(d), "2026-10-08 12h57 CMP-00123 CP R$ 1.234,50 Marina -A-B- Ltda -filial-01.pdf");
  assertEquals(nomeNoDropbox({ ...DA, tipo: "outro" }).includes(" DOC "), true);
  assertEquals(nomeNoDropbox({ ...DA, tipo: "nfe_xml", arquivo_path: "2026/10/x.xml" }).includes(" NFE-XML "), true);
});

Deno.test("nomeNoDropbox: fornecedor cortado em 40 caracteres", () => {
  const nome = nomeNoDropbox({ ...DA, valor_confianca: "media", fornecedor_nome: "A".repeat(60) });
  assertEquals(nome, `2026-10-08 12h57 CMP-00123 NFCE ${"A".repeat(40)}.jpg`);
});

Deno.test("nomeNoDropbox: CMP sem leitura vira 'A LER'", () => {
  const d = { ...DA, situacao: "falhou", tipo: null, valor: null, data_compra: null, hora_compra: null, fornecedor_nome: null, arquivo_path: "2026/10/x.pdf" };
  assertEquals(nomeNoDropbox(d), "2026-10-10 CMP-00123 A LER.pdf");
});

Deno.test("formatarReais e formatarCnpj", () => {
  assertEquals(formatarReais("62.00"), "R$ 62,00");
  assertEquals(formatarReais(187.4), "R$ 187,40");
  assertEquals(formatarReais("1234567.89"), "R$ 1.234.567,89");
  assertEquals(formatarReais(null), null);
  assertEquals(formatarReais("abc"), null);
  assertEquals(formatarReais("0"), null);
  assertEquals(formatarCnpj("11222333000181"), "11.222.333/0001-81");
  assertEquals(formatarCnpj("12ABC34501DE35"), "12.ABC.345/01DE-35");
  assertEquals(formatarCnpj("123"), null);
});

// ─── Aviso ────────────────────────────────────────────────────────────────────────────────

const ITEM: ItemDoAviso = {
  id: "00000000-0000-4000-8000-000000000123",
  codigo: "CMP-00123",
  decisao: "cmp",
  tipo: "nfce",
  valor: "62.00",
  valor_confianca: "media",
  data_compra: "2026-10-08",
  fornecedor_nome: "AUTO POSTO EXEMPLO",
  emitente_cnpj: "11222333000181",
  cnpj_confianca: "alta",
  recebido_em: "2026-10-10T22:40:57Z",
  erro: null,
  duplicado: null,
};

Deno.test("textoDoAviso: 1 CMP (o texto da spec)", () => {
  assertEquals(
    textoDoAviso([ITEM]),
    "CMP-00123 guardado: cupom NFC-e, AUTO POSTO EXEMPLO (CNPJ conferido), 08/10, R$ 62,00 (confira). " +
      "Está em COMPROVANTES/_A CLASSIFICAR. Ainda não lancei nada. Não precisa responder.",
  );
});

Deno.test("textoDoAviso: valor com selo alta sem '(confira)'; baixa omite o valor", () => {
  assertStringIncludes(textoDoAviso([{ ...ITEM, valor_confianca: "alta" }]), "08/10, R$ 62,00. Está em");
  const baixa = textoDoAviso([{ ...ITEM, valor_confianca: "baixa" }]);
  assertEquals(baixa.includes("R$"), false);
  assertStringIncludes(baixa, "(CNPJ conferido), 08/10. Está em");
});

Deno.test("textoDoAviso: sem fornecedor do cadastro mostra o CNPJ formatado, nunca nome do OCR", () => {
  const t = textoDoAviso([{ ...ITEM, fornecedor_nome: null }]);
  assertStringIncludes(t, "cupom NFC-e, CNPJ 11.222.333/0001-81 (conferido), 08/10");
  const t2 = textoDoAviso([{ ...ITEM, fornecedor_nome: null, cnpj_confianca: "media" }]);
  assertStringIncludes(t2, "cupom NFC-e, CNPJ 11.222.333/0001-81, 08/10");
});

Deno.test("textoDoAviso: vários contínuos (o texto da spec)", () => {
  const itens = [123, 124, 125, 126, 127].map((n, i) => ({
    ...ITEM,
    id: `id-${n}`,
    codigo: `CMP-00${n}`,
    valor_confianca: i < 3 ? "alta" : "media",
  }));
  assertEquals(
    textoDoAviso(itens),
    "Guardei 5 comprovantes: CMP-00123 a CMP-00127. 3 com valor conferido, 2 para conferir. " +
      "Estão em COMPROVANTES/_A CLASSIFICAR. Ainda não lancei nada. Não precisa responder.",
  );
});

Deno.test("textoDoAviso: códigos não contínuos listam até 5 e 'e mais N'", () => {
  const itens = [101, 103, 105, 107, 109, 111, 113].map((n) => ({ ...ITEM, id: `id-${n}`, codigo: `CMP-00${n}`, valor_confianca: "media" }));
  assertStringIncludes(textoDoAviso(itens), "Guardei 7 comprovantes: CMP-00101, CMP-00103, CMP-00105, CMP-00107, CMP-00109 e mais 2. 7 para conferir.");
  const dois = [{ ...ITEM }, { ...ITEM, id: "b", codigo: "CMP-00124", valor_confianca: "alta" }];
  assertStringIncludes(textoDoAviso(dois), "Guardei 2 comprovantes: CMP-00123 e CMP-00124. 1 com valor conferido, 1 para conferir.");
});

Deno.test("textoDoAviso: duplicado (o texto da spec)", () => {
  const dup: ItemDoAviso = { ...ITEM, codigo: null, decisao: "duplicado", duplicado: { codigo: "CMP-00098", data_compra: "2026-10-09", valor: "187.40" } };
  assertEquals(textoDoAviso([dup]), "Esse comprovante já é o CMP-00098 (09/10, R$ 187,40). Não guardei de novo.");
});

Deno.test("textoDoAviso: sem leitura (o texto da spec)", () => {
  const s: ItemDoAviso = { ...ITEM, decisao: "cmp_sem_leitura", tipo: null, valor: null, valor_confianca: null };
  assertEquals(
    textoDoAviso([s]),
    "CMP-00123 guardado, mas não consegui ler o arquivo. Está em COMPROVANTES/_A CLASSIFICAR com 'A LER' no nome.",
  );
});

Deno.test("textoDoAviso: não guardado, com a hora de São Paulo e o motivo", () => {
  const n: ItemDoAviso = { ...ITEM, codigo: null, decisao: "nao_guardado", erro: "midia_indisponivel", recebido_em: "2026-10-10T22:40:00Z" };
  assertEquals(
    textoDoAviso([n]),
    "Não consegui guardar o arquivo que você mandou às 19:40 (o WhatsApp não entregou a mídia). Pode mandar de novo como foto ou PDF?",
  );
  assertStringIncludes(textoDoAviso([{ ...n, erro: "formato_nao_suportado" }]), "(o formato não é foto, PDF nem XML)");
  assertStringIncludes(textoDoAviso([{ ...n, erro: "arquivo_grande" }]), "(passa de 15 MB)");
});

Deno.test("textoDoAviso: mistura — uma frase por categoria, na ordem, fecho uma vez", () => {
  const t = textoDoAviso([
    { ...ITEM, id: "n", codigo: null, decisao: "nao_guardado", erro: "arquivo_grande" },
    { ...ITEM, id: "s", codigo: "CMP-00124", decisao: "cmp_sem_leitura" },
    { ...ITEM, id: "d", codigo: null, decisao: "duplicado", duplicado: { codigo: "CMP-00098", data_compra: null, valor: null } },
    { ...ITEM },
  ]);
  const ordem = ["CMP-00123 guardado:", "já é o CMP-00098.", "CMP-00124 guardado, mas", "Não consegui guardar", "Ainda não lancei nada."];
  let ultimo = -1;
  for (const trecho of ordem) {
    const i = t.indexOf(trecho);
    assert(i > ultimo, `fora de ordem: ${trecho}\n${t}`);
    ultimo = i;
  }
  assertEquals(t.split("Ainda não lancei nada.").length, 2);
});

Deno.test("textoDoAviso: sem emoji e no máximo 4096 caracteres", () => {
  const muitos = Array.from({ length: 300 }, (_, i) => ({ ...ITEM, id: `i${i}`, codigo: null, decisao: "duplicado" as const, duplicado: { codigo: `CMP-${i}`.padEnd(30, "9"), data_compra: null, valor: null } }));
  const t = textoDoAviso(muitos);
  assert(t.length <= 4096);
  assertEquals(/\p{Extended_Pictographic}/u.test(textoDoAviso([ITEM])), false);
});

Deno.test("historicoDoAviso: marca 🤖, o aviso e as referências; sem CPF", () => {
  const texto = textoDoAviso([ITEM]);
  const h = historicoDoAviso([ITEM], texto);
  assertEquals(h.user, "🤖 Aviso automático do sistema de comprovantes (não foi o dono que escreveu): 1 arquivo guardado.");
  assertEquals(h.assistant, `${texto}\n\nReferência: CMP-00123 (id ${ITEM.id}). Nada foi lançado no financeiro.`);
  const h2 = historicoDoAviso([ITEM, { ...ITEM, id: "x", codigo: null, decisao: "duplicado", duplicado: { codigo: "CMP-00098", data_compra: null, valor: null } }], "t");
  assertStringIncludes(h2.user, "1 arquivo guardado, 1 repetido.");
  assertStringIncludes(h2.assistant, "repetido de CMP-00098 (id x)");
});

// ─── Chave do aviso ───────────────────────────────────────────────────────────────────────

Deno.test("sha256HexSync confere com o WebCrypto", async () => {
  for (const s of ["", "abc", "a".repeat(55), "a".repeat(56), "a".repeat(64), "x".repeat(1000), "ção 🤖 CMP"]) {
    const esperado = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))]
      .map((b) => b.toString(16).padStart(2, "0")).join("");
    assertEquals(sha256HexSync(s), esperado, `entrada de ${s.length} caracteres`);
  }
});

Deno.test("chaveDoAviso: formato fixo e independente da ordem", () => {
  const a = chaveDoAviso(["b-2", "a-1"]);
  assertMatch(a, /^cmp:aviso:[0-9a-f]{16}$/);
  assertEquals(a, chaveDoAviso(["a-1", "b-2"]));
  assert(a !== chaveDoAviso(["a-1"]));
});

// ─── Pastas da F2 ─────────────────────────────────────────────────────────────────────────

Deno.test("F2: _CANCELADOS e PESSOAL ficam dentro de COMPROVANTES (constantes, nunca de app_settings)", () => {
  assertEquals(PASTA_CANCELADOS, "/MANAGEMENT/FINANCIALS/COMPROVANTES/_CANCELADOS");
  assertEquals(PASTA_PESSOAL, "/MANAGEMENT/FINANCIALS/COMPROVANTES/PESSOAL");
  assert(PASTA_CANCELADOS.startsWith(`${PASTA_COMPROVANTES}/`) && PASTA_PESSOAL.startsWith(`${PASTA_COMPROVANTES}/`));
});
