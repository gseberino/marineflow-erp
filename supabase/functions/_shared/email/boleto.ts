// Leitura e VALIDAÇÃO de boleto a partir de texto — 100% determinístico, sem LLM.
//
// POR QUE SEM IA: a linha digitável carrega dígitos verificadores. Dá para provar que o
// número está correto por aritmética, com certeza — não com probabilidade. Um modelo que
// "quase acerta" um valor a pagar é pior que nenhum modelo. A IA só entra depois, para
// dizer de quem é a cobrança; o número, o valor e o vencimento saem daqui conferidos.
//
// Dois formatos convivem no Brasil:
//  · Título bancário  — 47 dígitos. Campos 1-3 com DV módulo 10, DV geral módulo 11.
//  · Arrecadação/convênio (água, luz, tributo) — 48 dígitos, começa com 8, 4 blocos de 12.

export interface BoletoTitulo {
  tipo: "titulo";
  linhaDigitavel: string;      // 47 dígitos
  codigoBarras: string;        // 44 dígitos
  bancoCodigo: string;         // 3 dígitos
  valor: number | null;        // reais; null quando o boleto vem sem valor fixo
  fatorVencimento: number;
  vencimento: string | null;   // YYYY-MM-DD; null quando indeterminado (ver nota do fator)
  vencimentoIncerto: boolean;
}

export interface BoletoArrecadacao {
  tipo: "arrecadacao";
  linhaDigitavel: string;      // 48 dígitos
  valor: number | null;
  vencimento: null;
  vencimentoIncerto: false;
}

export type Boleto = BoletoTitulo | BoletoArrecadacao;

// ───────────────────────── dígitos verificadores ─────────────────────────

/** Módulo 10 dos campos 1-3 da linha digitável (pesos 2,1,2,1… da direita para a esquerda). */
export function mod10(digits: string): number {
  let soma = 0;
  let peso = 2;
  for (let i = digits.length - 1; i >= 0; i--) {
    let p = Number(digits[i]) * peso;
    if (p > 9) p -= 9; // soma dos algarismos: 12 → 1+2 = 3 = 12-9
    soma += p;
    peso = peso === 2 ? 1 : 2;
  }
  const resto = soma % 10;
  return resto === 0 ? 0 : 10 - resto;
}

/**
 * Módulo 11 do DV geral do código de barras (pesos 2..9 ciclando da direita).
 * Regra da FEBRABAN: resto 0, 1 ou 10 → DV = 1.
 */
export function mod11Barcode(digits43: string): number {
  let soma = 0;
  let peso = 2;
  for (let i = digits43.length - 1; i >= 0; i--) {
    soma += Number(digits43[i]) * peso;
    peso = peso === 9 ? 2 : peso + 1;
  }
  const resto = soma % 11;
  const dv = 11 - resto;
  return dv === 0 || dv === 10 || dv === 11 ? 1 : dv;
}

/** Módulo 11 dos blocos de arrecadação (pesos 2..9, resto 0/1 → 0, resto 10 → 1). */
export function mod11Bloco(digits: string): number {
  let soma = 0;
  let peso = 2;
  for (let i = digits.length - 1; i >= 0; i--) {
    soma += Number(digits[i]) * peso;
    peso = peso === 9 ? 2 : peso + 1;
  }
  const resto = soma % 11;
  if (resto === 0 || resto === 1) return 0;
  if (resto === 10) return 1;
  return 11 - resto;
}

// ───────────────────────── fator de vencimento ─────────────────────────

/** Base histórica do fator de vencimento (fator 1000 = 07/10/1997). */
const BASE_ANTIGA = Date.UTC(1997, 9, 7);
/** Após o fator estourar 9999 em 21/02/2025, a contagem reiniciou em 1000 no dia 22/02/2025. */
const BASE_NOVA = Date.UTC(2025, 1, 22);
const DIA_MS = 86400000;

function fromFator(base: number, fator: number): string {
  return new Date(base + (fator - 1000) * DIA_MS).toISOString().slice(0, 10);
}

/**
 * Converte o fator de vencimento em data.
 *
 * O fator é ambíguo desde a virada de 2025: o mesmo número tem duas leituras possíveis
 * (ciclo antigo e ciclo novo). Em vez de chutar, resolvemos pela data de recebimento do
 * e-mail: fica a leitura plausível — de 60 dias antes a 2 anos depois do recebimento.
 * Se as duas forem plausíveis, ou nenhuma, devolve incerto e NÃO inventa vencimento.
 */
export function vencimentoDoFator(
  fator: number,
  recebidoEm: Date,
): { vencimento: string | null; incerto: boolean } {
  if (!Number.isFinite(fator) || fator <= 0) return { vencimento: null, incerto: true };

  const ref = recebidoEm.getTime();
  const min = ref - 60 * DIA_MS;
  const max = ref + 730 * DIA_MS;

  const candidatas = [fromFator(BASE_NOVA, fator), fromFator(BASE_ANTIGA, fator)]
    .filter((d) => {
      const t = Date.parse(`${d}T12:00:00Z`);
      return Number.isFinite(t) && t >= min && t <= max;
    });

  if (candidatas.length === 1) return { vencimento: candidatas[0], incerto: false };
  if (candidatas.length === 0) return { vencimento: null, incerto: true };
  // Empate: prefere a leitura do ciclo atual, mas marca como incerta para revisão humana.
  return { vencimento: candidatas[0], incerto: true };
}

// ───────────────────────── parsing ─────────────────────────

export function onlyDigits(s: string): string {
  return String(s ?? "").replace(/\D/g, "");
}

/**
 * Título bancário de 47 dígitos.
 * Campo 1: banco(3)+moeda(1)+posições 20-24 do código de barras(5)+DV(1)
 * Campo 2: posições 25-34(10)+DV(1) · Campo 3: posições 35-44(10)+DV(1)
 * Campo 4: DV geral(1) · Campo 5: fator(4)+valor(10)
 */
export function parseTitulo(linha47: string, recebidoEm: Date = new Date()): BoletoTitulo | null {
  const d = onlyDigits(linha47);
  if (d.length !== 47) return null;

  const c1 = d.slice(0, 9), dv1 = Number(d[9]);
  const c2 = d.slice(10, 20), dv2 = Number(d[20]);
  const c3 = d.slice(21, 31), dv3 = Number(d[31]);
  const dvGeral = Number(d[32]);
  const fator = Number(d.slice(33, 37));
  const valorRaw = d.slice(37, 47);

  if (mod10(c1) !== dv1 || mod10(c2) !== dv2 || mod10(c3) !== dv3) return null;

  // Remonta o código de barras (44) para conferir o DV geral — a checagem mais forte.
  const banco = d.slice(0, 3);
  const moeda = d[3];
  const campoLivre = d.slice(4, 9) + c2 + c3;               // 5 + 10 + 10 = 25
  const semDv = banco + moeda + d.slice(33, 37) + valorRaw + campoLivre; // 43
  if (semDv.length !== 43) return null;
  if (mod11Barcode(semDv) !== dvGeral) return null;

  const centavos = Number(valorRaw);
  const { vencimento, incerto } = vencimentoDoFator(fator, recebidoEm);

  return {
    tipo: "titulo",
    linhaDigitavel: d,
    codigoBarras: banco + moeda + String(dvGeral) + d.slice(33, 37) + valorRaw + campoLivre,
    bancoCodigo: banco,
    valor: centavos > 0 ? centavos / 100 : null,
    fatorVencimento: fator,
    vencimento,
    vencimentoIncerto: incerto,
  };
}

/**
 * Arrecadação/convênio de 48 dígitos (começa com 8). Quatro blocos de 12: 11 dígitos + DV.
 * O 3º dígito (identificador de valor) diz se o DV dos blocos é módulo 10 ou 11.
 */
export function parseArrecadacao(linha48: string): BoletoArrecadacao | null {
  const d = onlyDigits(linha48);
  if (d.length !== 48 || d[0] !== "8") return null;

  const idValor = d[2];
  const usaMod10 = idValor === "6" || idValor === "7";

  for (let b = 0; b < 4; b++) {
    const bloco = d.slice(b * 12, b * 12 + 12);
    const corpo = bloco.slice(0, 11);
    const dv = Number(bloco[11]);
    const esperado = usaMod10 ? mod10(corpo) : mod11Bloco(corpo);
    if (esperado !== dv) return null;
  }

  // Valor efetivo: posições 5-15 do "código de barras" (blocos sem DV), em centavos.
  const semDv = d.slice(0, 11) + d.slice(12, 23) + d.slice(24, 35) + d.slice(36, 47);
  const centavos = Number(semDv.slice(4, 15));
  return {
    tipo: "arrecadacao",
    linhaDigitavel: d,
    valor: Number.isFinite(centavos) && centavos > 0 ? centavos / 100 : null,
    vencimento: null,
    vencimentoIncerto: false,
  };
}

/**
 * Varre um texto (corpo de e-mail, texto extraído de PDF) e devolve os boletos VÁLIDOS.
 *
 * Só entra na lista o que passou no dígito verificador — número que não fecha é descartado
 * em silêncio, porque quase sempre é outro número qualquer (CNPJ, chave de acesso, telefone)
 * que por acaso tinha a quantidade certa de dígitos.
 */
export function extractBoletos(texto: string, recebidoEm: Date = new Date()): Boleto[] {
  const t = String(texto ?? "");
  if (!t) return [];

  // Sequências de dígitos com separadores comuns (espaço, ponto, hífen).
  const candidatos = t.match(/[\d][\d.\-\s]{40,70}[\d]/g) ?? [];
  const achados: Boleto[] = [];
  const vistos = new Set<string>();

  for (const bruto of candidatos) {
    const d = onlyDigits(bruto);
    // Uma sequência longa pode conter o número junto de outro; testa janelas de 47 e 48.
    for (const tamanho of [47, 48]) {
      for (let i = 0; i + tamanho <= d.length; i++) {
        const janela = d.slice(i, i + tamanho);
        if (vistos.has(janela)) continue;
        const parsed = tamanho === 47 ? parseTitulo(janela, recebidoEm) : parseArrecadacao(janela);
        if (parsed) {
          vistos.add(janela);
          achados.push(parsed);
        }
      }
    }
  }
  return achados;
}
