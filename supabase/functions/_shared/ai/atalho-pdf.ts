// Atalho sem modelo: "me manda o PDF do orçamento 108" (decisão do dono, 29/09/2026).
//
// O pedido mais comum ao assistente pelo WhatsApp custava uma chamada ao modelo (US$ 0,03 com
// cache, US$ 0,18 regravando; 43% dos turnos começam com o cache expirado) e ~17 s. Aqui ele é
// reconhecido por texto e vai direto à MESMA tool (send_document_pdf_to_self), que manda o PDF
// para quem pediu — nunca para o cliente.
//
// O leitor é estrito DE PROPÓSITO: só reconhece mensagens feitas inteiramente de palavras do
// vocabulário abaixo, com "pdf" e um documento. Qualquer outra palavra ("pro cliente",
// "com desconto", "e o da OS") devolve null e a mensagem segue para o modelo, como antes.

export type PedidoDePdf = { documento: string; tipo?: "orcamento" | "os" };

const VOCABULARIO = new Set([
  "me", "manda", "mande", "mandar", "envia", "envie", "enviar", "passa", "passe", "quero", "preciso",
  "ver", "o", "a", "do", "da", "de", "em", "no", "na", "pdf", "pra", "para", "mim", "por", "favor",
  "pf", "pfv", "pfvr", "aqui", "numero", "n", "no.", "nº", "n°",
]);
const PALAVRAS_DE_ORCAMENTO = new Set(["orcamento", "orc", "orc.", "orcamentos"]);
const PALAVRAS_DE_OS = new Set(["os", "o.s", "o.s.", "ordem", "servico"]);
const PALAVRAS_DE_ULTIMO = new Set(["ultimo", "ultima"]);

function normalizar(texto: string): string {
  return texto
    .toLowerCase()
    .normalize("NFD").replace(/[̀-ͯ]/g, "") // orçamento -> orcamento, último -> ultimo
    .replace(/[!?,;:]+/g, " ")
    .replace(/\.(\s|$)/g, " ") // ponto final de frase (mantém o de "o.s.")
    .trim();
}

/** O pedido de PDF, se a mensagem for SÓ isso; null para qualquer outra coisa. */
export function lerPedidoDePdf(texto: string): PedidoDePdf | null {
  const t = normalizar(texto);
  if (!t || t.length > 80) return null;
  const palavras = t.split(/\s+/);
  if (!palavras.includes("pdf")) return null;

  let documento: string | null = null;
  let tipo: PedidoDePdf["tipo"];
  for (const p of palavras) {
    const codigo = p.match(/^(orc|os)-?0*(\d{1,6})$/);
    if (codigo) {
      if (documento) return null; // dois documentos: o modelo decide
      documento = codigo[2];
      tipo = codigo[1] === "os" ? "os" : "orcamento";
      continue;
    }
    if (/^\d{1,6}$/.test(p)) {
      if (documento) return null;
      documento = String(Number(p));
      continue;
    }
    if (PALAVRAS_DE_ULTIMO.has(p)) {
      if (documento) return null;
      documento = "ultimo";
      continue;
    }
    if (PALAVRAS_DE_ORCAMENTO.has(p)) { if (tipo === "os") return null; tipo = "orcamento"; continue; }
    if (PALAVRAS_DE_OS.has(p)) { if (tipo === "orcamento" && p !== "servico") return null; tipo = tipo ?? "os"; continue; }
    if (VOCABULARIO.has(p)) continue;
    return null; // palavra fora do vocabulário: segue para o modelo
  }
  if (!documento) return null;
  return tipo ? { documento, tipo } : { documento };
}

/** Resposta ao dono a partir do resultado da tool (mesma forma que o modelo recebe). */
export function textoDoAtalhoPdf(r: Record<string, unknown>): string {
  if (r.ok === true && r.deduplicated === true) return String(r.aviso ?? "Esse PDF já foi mandado há instantes; não reenviei.");
  if (r.ok === true) {
    const doc = String(r.documento ?? "o documento");
    const detalhe = [r.cliente, r.total].filter(Boolean).join(", ");
    const teste = String(r.enviado_para ?? "").includes("TESTE")
      ? " Atenção: o modo de teste do WhatsApp está ligado e o arquivo foi para o número de teste."
      : "";
    return `Pronto: mandei o PDF do ${doc}${detalhe ? ` (${detalhe})` : ""}.${teste}`;
  }
  if (Array.isArray(r.opcoes) && r.opcoes.length > 0) {
    return `Achei mais de um com esse número: ${(r.opcoes as unknown[]).join(" e ")}. Qual deles? Mande de novo com o número completo (ex.: "pdf ${String(r.opcoes[0])}").`;
  }
  const link = typeof r.link_interno === "string" ? ` Pelo sistema: ${r.link_interno}` : "";
  return `Não consegui mandar o PDF: ${String(r.error ?? r.motivo ?? "erro desconhecido")}.${link}`;
}
