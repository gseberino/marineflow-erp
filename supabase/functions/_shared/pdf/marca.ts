// A marca da HBR nos documentos em PDF (25/11/2026): a mesma "cara" das folhas de papel novas (ficha de entrada e folha
// de follow-up, 23–25/11/2026). Começou pela via do técnico e pelo relatório do assistente; os próximos documentos
// reaproveitam daqui — paleta, pilhas de fonte, as fontes embutidas, o fio em degradê e o slogan.
//
// A restrição que manda: o PDF sai pelo /api/pdf (Chromium do @sparticuz/chromium, JavaScript desligado), que só tem a
// Open Sans. Por isso as duas fontes vão EMBUTIDAS no HTML (@font-face com data: woff2, marca-fontes.ts), e a Open Sans
// fica logo depois na pilha: o subconjunto latino das fontes da marca não tem todo caractere, e o que faltar sai nela
// (e só nela, no servidor — o teste de glifos da via continua valendo contra a Open Sans). No navegador do escritório
// (Imprimir) é o mesmo HTML, com as mesmas fontes.
//
// Logo: o de app_settings.company_logo_url (o desenho ORIGINAL, 320×160). O nome por extenso no texto é só "HBR".

import { ARCHIVO_WOFF2_BASE64, HANKEN_GROTESK_WOFF2_BASE64 } from './marca-fontes.ts';

/** As cores do manual da marca (as mesmas das folhas de papel). */
export const MARCA = {
  marinho: '#0D1B2A',
  azul: '#274A6D',
  azulClaro: '#7FA0B8',
  dourado: '#B8894A',
  douradoClaro: '#C8A063',
  cinza: '#D9DDE1',
  /** Linhas de tabela. */
  grade: '#B9C6D3',
  /** Fundo do cabeçalho de tabela e de faixas claras. */
  fundo: '#EEF2F6',
  /** Pauta para escrever à mão. */
  pauta: '#C3CFDA',
} as const;

/** Texto corrido. A Open Sans logo depois: é a fonte do servidor, e cobre o que o subconjunto latino não tem. */
export const FONTE_DO_TEXTO = '"Hanken Grotesk", "Open Sans", Arial, sans-serif';
/** Títulos, número do documento e rótulos de seção. */
export const FONTE_DOS_TITULOS = '"Archivo", "Open Sans", Arial, sans-serif';

/** O slogan do rodapé das folhas. */
export const SLOGAN = 'Energia. Controle. Confiança.';

/** O fio sob o cabeçalho: dourado → cinza → azul. */
export const FIO_EM_DEGRADE =
  `linear-gradient(90deg, ${MARCA.dourado} 0%, ${MARCA.douradoClaro} 30%, ${MARCA.cinza} 52%, ${MARCA.azulClaro} 78%, ${MARCA.azul} 100%)`;

/**
 * As duas fontes da marca embutidas (~93 KB de texto no HTML; o PDF passa de ~240 para ~500 KB). Eixo de peso inteiro
 * (100–900): bold e 800 são da própria fonte. Sem itálico no arquivo: `font-style: italic` sai inclinado pelo navegador.
 * `swap`: se a impressão (o Imprimir da tela chama print() 400 ms depois de abrir a janela) pegar a fonte ainda
 * carregando, o texto sai na Open Sans — nunca invisível, como faria `block`.
 */
export function cssDasFontesDaMarca(): string {
  // Na tela as fontes chegam sob demanda (src/lib/marca-fontes-sob-demanda.ts, troca feita pelo vite.config.ts): antes
  // de chegarem, nada de @font-face com data: vazio — a folha sai na letra de reserva da pilha. No servidor estão sempre aqui.
  if (!ARCHIVO_WOFF2_BASE64 || !HANKEN_GROTESK_WOFF2_BASE64) return '';
  return `@font-face { font-family: "Archivo"; font-style: normal; font-weight: 100 900; font-display: swap;
    src: url(data:font/woff2;base64,${ARCHIVO_WOFF2_BASE64}) format("woff2"); }
  @font-face { font-family: "Hanken Grotesk"; font-style: normal; font-weight: 100 900; font-display: swap;
    src: url(data:font/woff2;base64,${HANKEN_GROTESK_WOFF2_BASE64}) format("woff2"); }`;
}

/** As cores como variáveis CSS (--marinho, --azul, …), para o `<style>` de cada documento. */
export function cssDasCoresDaMarca(): string {
  return `:root { --marinho: ${MARCA.marinho}; --azul: ${MARCA.azul}; --claro: ${MARCA.azulClaro}; --ouro: ${MARCA.dourado};
    --ouro-claro: ${MARCA.douradoClaro}; --cinza: ${MARCA.cinza}; --grade: ${MARCA.grade}; --fundo: ${MARCA.fundo};
    --pauta: ${MARCA.pauta}; }`;
}
