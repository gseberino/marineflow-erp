// Relatório financeiro em PDF pedido ao assistente (06/10/2026, pedido do dono: "pedir um PDF
// ao assistente sobre as despesas de setembro", "extrato de pagamentos do freelancer Roberto",
// "saídas de hoje").
//
// Um desenho só para todos os relatórios: título, período, quadro de resumo e tabelas com total.
// HTML estático (o /api/pdf roda com JavaScript desligado), A4, texto real. Quem monta os DADOS
// é a tool (_shared/ai/tools/relatorios.ts); aqui só se desenha — e tudo passa por `esc`.

import { esc } from "./documento.ts";
import { dataBR, dataHoraBR } from "./datas.ts";

export interface ColunaDoRelatorio {
  titulo: string;
  /** "valor" alinha à direita e formata em R$; "data" formata dd/mm/aaaa. */
  tipo?: "texto" | "valor" | "data";
}

export interface TabelaDoRelatorio {
  titulo: string;
  /** Uma linha de explicação abaixo do título (o que entra e o que não entra). */
  nota?: string;
  colunas: ColunaDoRelatorio[];
  linhas: (string | number | null)[][];
  /** Rótulo e valor da linha de total (o valor vai na última coluna de valor). */
  total?: { rotulo: string; valor: number };
}

export interface Relatorio {
  empresa: string;
  titulo: string;
  periodo: string;
  /** Filtros como a pessoa pediu ("categoria: Combustível", "conta: C6"). */
  filtros?: string[];
  resumo: { rotulo: string; valor: string }[];
  tabelas: TabelaDoRelatorio[];
  /** Avisos que mudam a leitura (compras ainda não lançadas, consulta parcial…). */
  avisos?: string[];
  geradoEm?: Date;
}

const REAL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
export const reais = (n: number) => REAL.format(Number.isFinite(n) ? n : 0);

function celula(v: string | number | null, tipo: ColunaDoRelatorio["tipo"]): string {
  if (v === null || v === undefined || v === "") return "—";
  if (tipo === "valor") return esc(reais(Number(v)));
  if (tipo === "data") return esc(/^\d{4}-\d{2}-\d{2}/.test(String(v)) ? dataBR(String(v).slice(0, 10)) : String(v));
  return esc(String(v));
}

function tabela(t: TabelaDoRelatorio): string {
  const ultimaDeValor = t.colunas.map((c) => c.tipo).lastIndexOf("valor");
  const cab = t.colunas.map((c) => `<th class="${c.tipo === "valor" ? "num" : ""}">${esc(c.titulo)}</th>`).join("");
  const corpo = t.linhas.length
    ? t.linhas.map((l) =>
      `<tr>${t.colunas.map((c, i) => `<td class="${c.tipo === "valor" ? "num" : ""}">${celula(l[i] ?? null, c.tipo)}</td>`).join("")}</tr>`
    ).join("")
    : `<tr><td colspan="${t.colunas.length}" class="vazio">Nada no período.</td></tr>`;
  const total = t.total && ultimaDeValor >= 0
    ? `<tfoot><tr>${t.colunas.map((_, i) =>
      i === 0 ? `<td>${esc(t.total!.rotulo)}</td>` : i === ultimaDeValor ? `<td class="num">${esc(reais(t.total!.valor))}</td>` : "<td></td>"
    ).join("")}</tr></tfoot>`
    : "";
  return `<section><h2>${esc(t.titulo)}</h2>${t.nota ? `<p class="nota">${esc(t.nota)}</p>` : ""}
<table><thead><tr>${cab}</tr></thead><tbody>${corpo}</tbody>${total}</table></section>`;
}

export function montarRelatorioHtml(r: Relatorio): string {
  const gerado = dataHoraBR(r.geradoEm ?? new Date());
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>${esc(r.titulo)}</title>
<style>
@page{size:A4;margin:12mm}
*{box-sizing:border-box}
body{font-family:"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:#18293a;font-size:10.5pt;margin:0}
header{border-bottom:2px solid #0b3d66;padding-bottom:6px;margin-bottom:10px}
.empresa{font-size:9pt;color:#55687c;letter-spacing:.06em;text-transform:uppercase}
h1{font-size:16pt;margin:2px 0 2px;color:#0b3d66}
.periodo{font-size:10pt;color:#55687c}
.filtros{font-size:9pt;color:#55687c;margin-top:2px}
.resumo{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0 4px}
.resumo div{border:1px solid #d5dee7;border-radius:6px;padding:5px 9px;min-width:120px}
.resumo b{display:block;font-size:12pt}
.resumo span{font-size:8.5pt;color:#55687c}
.avisos{background:#f5edd6;border:1px solid #e3d3a4;border-radius:6px;padding:6px 9px;margin:8px 0;font-size:9pt}
.avisos p{margin:2px 0}
h2{font-size:11.5pt;margin:12px 0 2px;color:#0b3d66}
.nota{font-size:8.5pt;color:#55687c;margin:0 0 4px}
table{width:100%;border-collapse:collapse;font-size:9pt}
th,td{text-align:left;padding:3px 5px;border-bottom:1px solid #e3e9ef;vertical-align:top}
th{font-size:8pt;text-transform:uppercase;letter-spacing:.04em;color:#55687c;border-bottom:1px solid #b9c6d3}
.num{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}
tfoot td{font-weight:700;border-top:1px solid #b9c6d3;border-bottom:none}
tr{break-inside:avoid}
thead{display:table-header-group}
.vazio{color:#55687c;font-style:italic}
footer{margin-top:14px;font-size:8pt;color:#55687c}
</style></head><body>
<header><div class="empresa">${esc(r.empresa)}</div><h1>${esc(r.titulo)}</h1>
<div class="periodo">${esc(r.periodo)}</div>${r.filtros?.length ? `<div class="filtros">${r.filtros.map(esc).join(" · ")}</div>` : ""}</header>
${r.resumo.length ? `<div class="resumo">${r.resumo.map((x) => `<div><b>${esc(x.valor)}</b><span>${esc(x.rotulo)}</span></div>`).join("")}</div>` : ""}
${r.avisos?.length ? `<div class="avisos">${r.avisos.map((a) => `<p>${esc(a)}</p>`).join("")}</div>` : ""}
${r.tabelas.map(tabela).join("\n")}
<footer>Gerado pelo assistente do MarineFlow em ${esc(gerado)}. Valores do sistema na hora do pedido.</footer>
</body></html>`;
}

/** "despesas-2026-09.pdf" — só letras, números e hífen. */
export function nomeDoRelatorio(partes: string[]): string {
  const base = partes.join("-").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80);
  return `${base || "relatorio"}.pdf`;
}
