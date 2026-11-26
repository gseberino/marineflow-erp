// Relatório financeiro em PDF pedido ao assistente (06/10/2026, pedido do dono: "pedir um PDF
// ao assistente sobre as despesas de setembro", "extrato de pagamentos do freelancer Roberto",
// "saídas de hoje").
//
// Um desenho só para todos os relatórios: título, período, quadro de resumo e tabelas com total.
// HTML estático (o /api/pdf roda com JavaScript desligado), A4, texto real. Quem monta os DADOS
// é a tool (_shared/ai/tools/relatorios.ts); aqui só se desenha — e tudo passa por `esc`.

import { esc } from "./documento.ts";
import { dataBR, dataHoraBR } from "./datas.ts";
import { cssDasCoresDaMarca, cssDasFontesDaMarca, FIO_EM_DEGRADE, FONTE_DO_TEXTO, FONTE_DOS_TITULOS, SLOGAN } from "./marca.ts";

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
  /** O logo da empresa (app_settings.company_logo_url, o desenho original). Sem ele, o cabeçalho sai só com o título. */
  logoUrl?: string | null;
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
  // A identidade das folhas de papel novas (25/11/2026, marca.ts): logo | fio cinza | título, o fio em degradê, títulos
  // de tabela com a marca em círculo e o fio fino, cabeçalho de tabela claro e o slogan no pé. Só o desenho mudou.
  const logo = (r.logoUrl ?? "").trim();
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>${esc(r.titulo)}</title>
<style>
${cssDasFontesDaMarca()}
${cssDasCoresDaMarca()}
@page{size:A4;margin:12mm}
*{box-sizing:border-box}
body{font-family:${FONTE_DO_TEXTO};color:var(--marinho);font-size:10.5pt;margin:0;line-height:1.36;
  -webkit-print-color-adjust:exact;print-color-adjust:exact}
header{display:flex;align-items:center;gap:5mm}
.logo{display:block;flex:none;height:13mm;width:auto;max-width:36mm;object-fit:contain}
.nome{flex:1;min-width:0}
.logo+.nome{border-left:.3mm solid var(--cinza);padding-left:5mm}
.empresa{font-size:7.5pt;font-weight:600;color:var(--azul);letter-spacing:.08em;text-transform:uppercase}
h1{font-family:${FONTE_DOS_TITULOS};font-weight:800;font-size:16pt;line-height:1.1;margin:.6mm 0 .8mm;color:var(--marinho);
  text-transform:uppercase;letter-spacing:.02em}
.periodo{font-size:9.5pt;color:var(--azul)}
.filtros{font-size:8.5pt;color:var(--azul);margin-top:.5mm}
.fio{height:.9mm;border-radius:1mm;background:${FIO_EM_DEGRADE};margin:2.2mm 0 3.2mm}
.resumo{display:flex;flex-wrap:wrap;gap:2mm;margin:0 0 1.5mm}
.resumo div{border:.3mm solid var(--claro);border-radius:1.2mm;padding:1.4mm 3mm;min-width:32mm}
.resumo b{display:block;font-family:${FONTE_DOS_TITULOS};font-weight:700;font-size:12pt;line-height:1.25}
.resumo span{font-size:8pt;color:var(--azul)}
.avisos{background:#FBF7F0;border:.3mm solid var(--ouro-claro);border-left:1.2mm solid var(--ouro);border-radius:1.1mm;
  padding:1.6mm 3mm;margin:2.5mm 0;font-size:9pt}
.avisos p{margin:.5mm 0}
h2{display:flex;align-items:center;gap:2.2mm;font-family:${FONTE_DOS_TITULOS};font-size:10.5pt;font-weight:700;
  text-transform:uppercase;letter-spacing:.07em;color:var(--marinho);margin:4mm 0 1mm;break-after:avoid}
h2::before{content:"";flex:none;width:2.6mm;height:2.6mm;border-radius:50%;background:var(--marinho)}
h2::after{content:"";flex:1 1 8mm;height:.3mm;background:var(--cinza)}
.nota{font-size:8.5pt;color:var(--azul);margin:0 0 1.5mm}
table{width:100%;border-collapse:collapse;font-size:9pt}
th,td{text-align:left;padding:1mm 1.6mm;border-bottom:.25mm solid var(--pauta);vertical-align:top}
th{font-size:7.5pt;font-weight:700;text-transform:uppercase;letter-spacing:.05em;color:var(--azul);background:var(--fundo);
  border-top:.25mm solid var(--grade);border-bottom:.25mm solid var(--grade)}
.num{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}
tfoot td{font-weight:700;border-top:.4mm solid var(--marinho);border-bottom:none}
tr{break-inside:avoid}
thead{display:table-header-group}
.vazio{color:var(--azul);font-style:italic}
footer{margin-top:5mm;padding-top:1.6mm;border-top:.3mm solid var(--cinza);display:flex;justify-content:space-between;
  align-items:baseline;gap:4mm;font-size:8pt;color:var(--azul)}
footer em{flex:none;font-style:normal;font-size:6.5pt;font-weight:600;letter-spacing:.14em;color:var(--marinho)}
</style></head><body>
<header>${logo ? `<img class="logo" src="${esc(logo)}" alt="">` : ""}<div class="nome"><div class="empresa">${esc(r.empresa)}</div><h1>${esc(r.titulo)}</h1>
<div class="periodo">${esc(r.periodo)}</div>${r.filtros?.length ? `<div class="filtros">${r.filtros.map(esc).join(" · ")}</div>` : ""}</div></header>
<div class="fio"></div>
${r.resumo.length ? `<div class="resumo">${r.resumo.map((x) => `<div><b>${esc(x.valor)}</b><span>${esc(x.rotulo)}</span></div>`).join("")}</div>` : ""}
${r.avisos?.length ? `<div class="avisos">${r.avisos.map((a) => `<p>${esc(a)}</p>`).join("")}</div>` : ""}
${r.tabelas.map(tabela).join("\n")}
<footer><span>Gerado pelo assistente do MarineFlow em ${esc(gerado)}. Valores do sistema na hora do pedido.</span><em>${esc(SLOGAN)}</em></footer>
</body></html>`;
}

/** "despesas-2026-09.pdf" — só letras, números e hífen. */
export function nomeDoRelatorio(partes: string[]): string {
  const base = partes.join("-").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80);
  return `${base || "relatorio"}.pdf`;
}
