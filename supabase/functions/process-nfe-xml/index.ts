import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Decodifica entidades XML no texto lido.
 *
 * Lemos o XML por regex (sem parser), então as entidades chegam cruas: uma NF-e
 * real da Kamell traz `ECRA TOUCH GX TOUCH 50 (5&amp;quot;)`, que sem decodificar
 * viraria o NOME DO PRODUTO no cadastro — e seguiria para a SEFAZ na devolução.
 * Faz duas passadas no máximo porque há emissores que codificam em dobro
 * (`&amp;quot;` em vez de `&quot;`), e `&amp;` é sempre resolvido POR ÚLTIMO em
 * cada passada: o contrário transformaria `&amp;lt;` em `<` indevidamente.
 */
function decodeEntities(s: string): string {
  const once = (t: string) =>
    t.replace(/&lt;/gi, "<")
      .replace(/&gt;/gi, ">")
      .replace(/&quot;/gi, '"')
      .replace(/&apos;/gi, "'")
      .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
      .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
      .replace(/&amp;/gi, "&");
  const first = once(s);
  return /&(amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);/i.test(first) ? once(first) : first;
}

/** Extracts a single value from XML using a tag name. Searches case-insensitively. */
function tag(xml: string, name: string): string | null {
  const re = new RegExp(`<${name}[^>]*>([^<]*)<\\/${name}>`, "is");
  const raw = xml.match(re)?.[1];
  return raw == null ? null : decodeEntities(raw).trim();
}

/** Finds all occurrences of a block tag and returns their content. */
function tagAll(xml: string, name: string): string[] {
  const re = new RegExp(`<${name}[^>]*>([\\s\\S]*?)<\\/${name}>`, "ig");
  return [...xml.matchAll(re)].map((m) => m[1]);
}

/** Recorta um bloco do XML para ler tags de dentro dele sem pegar homônimas. */
function block(xml: string, name: string): string {
  return xml.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)<\\/${name}>`, "i"))?.[1] ?? "";
}

/**
 * Decodifica o XML respeitando o encoding.
 *
 * `atob` devolve uma "binary string" (1 char = 1 byte): usar o resultado direto
 * corrompe todo acento — "PEÇA DE REPOSIÇÃO" virava "PEÃA DE REPOSIÃÃO", e esse
 * nome quebrado ia parar no cadastro do produto. Decodificamos os BYTES com o
 * encoding declarado: a NF-e é UTF-8 por norma, mas há emissores que gravam
 * ISO-8859-1 (forçar UTF-8 nesses quebraria os acentos do mesmo jeito).
 */
function decodeXml(base64: string): string {
  const bin = atob(base64);
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  const head = new TextDecoder("ascii").decode(bytes.slice(0, 200));
  const declared = /encoding=["']([^"']+)["']/i.exec(head)?.[1] ?? "utf-8";
  const label = /8859|latin/i.test(declared) ? "iso-8859-1" : "utf-8";
  return new TextDecoder(label).decode(bytes);
}

/** GTIN válido (8/12/13/14 dígitos) ou null — "SEM GTIN" e afins viram null. */
function normalizeGtin(raw: string | null): string | null {
  const d = (raw ?? "").replace(/\D/g, "");
  return [8, 12, 13, 14].includes(d.length) ? d : null;
}

// ── Main handler ─────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    const body = await req.json();
    if (!body.xmlBase64) throw new Error("XML não fornecido (xmlBase64 ausente)");

    // ── 1. Decode XML ──────────────────────────────────────────────────────
    let xmlText: string;
    try {
      xmlText = decodeXml(body.xmlBase64);
    } catch {
      throw new Error("Base64 inválido — verifique o encoding do arquivo XML.");
    }

    // ── 2. Validate minimal NFe structure ─────────────────────────────────
    if (!xmlText.includes("<infNFe") && !xmlText.includes("<NFe")) {
      throw new Error("Arquivo não é uma NF-e válida (tag <infNFe> não encontrada).");
    }

    // ── 3. Extract header fields ───────────────────────────────────────────
    // \bId="NFe" + 44 dígitos: o padrão antigo ([^I]*) parava no primeiro "i"
    // dos atributos (ex.: xmlns=".../inf.br/nfe") e devolvia a chave vazia.
    const nfeKey = xmlText.match(/<infNFe[^>]*\bId="NFe(\d{44})"/i)?.[1] ?? null;

    const ide = block(xmlText, "ide");
    const nfeNumber = tag(ide, "nNF") ?? tag(xmlText, "nNF");
    const issueDateRaw = tag(ide, "dhEmi") ?? tag(ide, "dEmi") ?? tag(xmlText, "dhEmi");

    // Emitente = FORNECEDOR. Guardamos também IE e endereço para permitir
    // identificar/cadastrar o fornecedor a partir do próprio XML.
    const emit = block(xmlText, "emit");
    const enderEmit = block(emit, "enderEmit");
    const issuerName = tag(emit, "xNome");
    const issuerCNPJ = tag(emit, "CNPJ") ?? tag(emit, "CPF");
    const issuer = {
      name: issuerName,
      document: issuerCNPJ,
      tradeName: tag(emit, "xFant"),
      stateRegistration: tag(emit, "IE"),
      address: {
        street: tag(enderEmit, "xLgr"),
        number: tag(enderEmit, "nro"),
        complement: tag(enderEmit, "xCpl"),
        district: tag(enderEmit, "xBairro"),
        cityName: tag(enderEmit, "xMun"),
        stateCode: tag(enderEmit, "UF"),
        postalCode: tag(enderEmit, "CEP"),
        phone: tag(enderEmit, "fone"),
      },
    };

    // TOTAIS: ler do grupo <ICMSTot>, não do documento inteiro. As tags vICMS,
    // vIPI, vPIS e vCOFINS existem TAMBÉM dentro de cada item, e como <det> vem
    // antes de <total> no XML, a busca global devolvia o imposto do PRIMEIRO
    // ITEM como se fosse o total da nota.
    const totals = block(xmlText, "ICMSTot");
    const totalNF      = parseFloat(tag(totals, "vNF") ?? "0");
    const totalICMS    = parseFloat(tag(totals, "vICMS") ?? "0");
    const totalIPI     = parseFloat(tag(totals, "vIPI") ?? "0");
    const totalPIS     = parseFloat(tag(totals, "vPIS") ?? "0");
    const totalCOFINS  = parseFloat(tag(totals, "vCOFINS") ?? "0");
    const totalProducts = parseFloat(tag(totals, "vProd") ?? "0");
    const totalDiscount = parseFloat(tag(totals, "vDesc") ?? "0");
    const totalFreight  = parseFloat(tag(totals, "vFrete") ?? "0");
    const totalOther    = parseFloat(tag(totals, "vOutro") ?? "0");
    const totalInsurance = parseFloat(tag(totals, "vSeg") ?? "0");

    // ── 4. Extract items (det blocks) ─────────────────────────────────────
    const detBlocks = tagAll(xmlText, "det");
    const items = detBlocks.map((det, idx) => {
      const prod = det.match(/<prod>([\s\S]*?)<\/prod>/i)?.[1] ?? det;
      const icmsBlock = det.match(/<ICMS>([\s\S]*?)<\/ICMS>/i)?.[1] ?? "";

      const qty    = parseFloat(tag(prod, "qCom") ?? "0");
      const price  = parseFloat(tag(prod, "vUnCom") ?? "0");
      const total  = parseFloat(tag(prod, "vProd") ?? "0");
      const icmsQty = parseFloat(tag(icmsBlock, "vICMS") ?? "0");

      return {
        index:        idx + 1,
        sku_supplier: tag(prod, "cProd"),
        description:  tag(prod, "xProd"),
        ncm:          tag(prod, "NCM"),
        cfop:         tag(prod, "CFOP"),
        unit:         tag(prod, "uCom"),
        quantity:     qty,
        unit_price:   price,
        total_price:  total,
        icms_value:   icmsQty,
        // GTIN/EAN: a chave de casamento MAIS confiável (é global, ao contrário
        // do código interno do fornecedor). Vem em cEAN (comercial) e cEANTrib
        // (tributável); "SEM GTIN" e valores inválidos viram null.
        barcode:      normalizeGtin(tag(prod, "cEAN")) ?? normalizeGtin(tag(prod, "cEANTrib")),
        // Origem da mercadoria (0=nacional, 1/2=estrangeira…) — atributo fiscal
        // do produto, aproveitado no cadastro e na devolução ao fornecedor.
        origin:       tag(icmsBlock, "orig"),
        discount:     parseFloat(tag(prod, "vDesc") ?? "0") || 0,
      };
    });

    // ── 4b. A nota é MESMO de entrada para esta empresa? ───────────────────
    // Sem isso, subir por engano uma NF-e de VENDA da própria empresa faria o
    // sistema somar ao estoque o que foi vendido e criar uma conta a pagar para
    // o próprio cliente. O destinatário do XML tem que ser o nosso CNPJ.
    const dest = block(xmlText, "dest");
    const destCnpj = (tag(dest, "CNPJ") ?? tag(dest, "CPF") ?? "").replace(/\D/g, "");
    const { data: empresa } = await supabase
      .from("company_fiscal_settings")
      .select("cnpj")
      .limit(1)
      .maybeSingle();
    const ownCnpj = String(empresa?.cnpj ?? "").replace(/\D/g, "");
    const emitCnpj = String(issuerCNPJ ?? "").replace(/\D/g, "");

    if (ownCnpj && emitCnpj && emitCnpj === ownCnpj) {
      throw new Error(
        "Esta NF-e foi EMITIDA pela sua empresa (nota de saída) — não pode dar entrada em estoque. " +
        "Para dar entrada, use o XML enviado pelo fornecedor.",
      );
    }
    if (ownCnpj && destCnpj && destCnpj !== ownCnpj) {
      throw new Error(
        "O destinatário desta NF-e não é a sua empresa (CNPJ do destinatário: " +
        destCnpj + "). Confira se o XML é da nota de compra correta.",
      );
    }

    // ── 5. Duplicate check via NFe key ─────────────────────────────────────
    // Sem chave não há como impedir a mesma nota de entrar duas vezes — e
    // entrada duplicada infla estoque e financeiro. Melhor recusar o arquivo.
    if (!nfeKey) {
      throw new Error(
        "Não foi possível ler a chave de acesso (44 dígitos) deste XML. " +
        "Sem ela não é possível garantir que a nota não será importada em duplicidade.",
      );
    }
    if (nfeKey) {
      const { data: existing } = await supabase
        .from("fiscal_notes")
        .select("id")
        .eq("nfe_key", nfeKey)
        .maybeSingle();

      if (existing) {
        return new Response(
          JSON.stringify({
            error: `NF-e já importada (chave ${nfeKey.slice(0, 12)}…). Duplicata ignorada.`,
            duplicate: true,
          }),
          {
            status: 409,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
    }

    // ── 6. Persist in fiscal_notes (store original XML) ───────────────────
    const { data: noteRow, error: insertErr } = await supabase
      .from("fiscal_notes")
      .insert({
        nfe_key:       nfeKey,
        nfe_number:    nfeNumber,
        issuer_name:   issuerName,
        issuer_cnpj:   issuerCNPJ,
        issued_at:     issueDateRaw ?? new Date().toISOString(),
        total_amount:  totalNF,
        tax_icms:      totalICMS,
        tax_ipi:       totalIPI,
        tax_pis:       totalPIS,
        tax_cofins:    totalCOFINS,
        // Composicao do total: sem ela a conferencia acusava divergencia em
        // toda nota com IPI (vNF = produtos + IPI + frete + seguro + outros - desconto).
        total_products:  totalProducts,
        total_discount:  totalDiscount,
        total_freight:   totalFreight,
        total_insurance: totalInsurance,
        total_other:     totalOther,
        items:         items,
        xml_content:   xmlText,   // ← Armazena o XML original
        status:        "pending",
      })
      .select("id")
      .single();

    if (insertErr) throw new Error(`Erro ao salvar NF-e: ${insertErr.message}`);

    const noteId = noteRow.id;

    // ── 7. Audit log ───────────────────────────────────────────────────────
    // A tabela é audit_log (SINGULAR). Estava gravando em "audit_logs", que não
    // existe — e como o insert não checava o erro, toda importação perdia o
    // rastro de auditoria em silêncio.
    const { error: auditErr } = await supabase.from("audit_log").insert({
      table_name: "fiscal_notes",
      record_id:  noteId,
      action:     "import_xml",
      new_value: {
        nfe_key:    nfeKey,
        nfe_number: nfeNumber,
        items:      items.length,
        total:      totalNF,
      },
      reason: "Importação automática de XML de NF-e",
    });
    // A auditoria é acessória: não derruba a importação, mas precisa aparecer
    // em algum lugar — silenciar foi justamente o que escondeu o bug do nome.
    if (auditErr) console.error("[process-nfe-xml] falha ao gravar audit_log:", auditErr.message);

    // ── 8. Return parsed data (UI will confirm stock update) ──────────────
    return new Response(
      JSON.stringify({
        noteId,
        nfeKey,
        nfeNumber,
        issueDate:  issueDateRaw,
        issuerName,
        issuerCNPJ,
        // Emitente completo (IE, nome fantasia, endereço): permite à UI achar o
        // fornecedor pelo CNPJ do próprio XML — ou oferecer o cadastro já
        // preenchido, em vez de exigir que o usuário escolha na mão.
        issuer,
        totalNF,
        totalICMS,
        totalIPI,
        totalPIS,
        totalCOFINS,
        totalProducts,
        totalDiscount,
        totalFreight,
        totalInsurance,
        totalOther,
        items,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (e: any) {
    console.error("[process-nfe-xml]", e.message);
    return new Response(
      JSON.stringify({ error: e.message }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
