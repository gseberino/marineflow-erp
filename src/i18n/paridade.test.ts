// MF-AUD-030 — os dois dicionários têm que ter exatamente as mesmas chaves.
//
// O tipo `TranslationKeys` é derivado de `en`, então o TypeScript já cobra que pt-BR tenha
// tudo que en tem. O que ele NÃO cobra, e este teste cobra:
//   1. o caminho contrário — uma chave nova só em pt-BR passa pelo compilador quando entra em
//      um objeto aninhado (o excesso só é recusado no literal de primeiro nível);
//   2. valor vazio ou só espaço, que compila liso e aparece na tela como nada;
//   3. placeholder que existe num idioma e não no outro — a frase traduzida perde o dado.
//
// A auditoria registrou 782 × 781 chaves em 10/08/2026, com `address.dontKnowCep` faltando em
// en. A chave já está lá; este teste é o que impede o próximo desvio de durar meses.
import { describe, it, expect } from 'vitest';
import { en } from './en';
import { ptBR } from './pt-BR';

type Arvore = Record<string, unknown>;

/**
 * Caminhos de todas as folhas, em ordem: 'settings.terms', 'pdf.showTerms', …
 *
 * Arrays descem por índice (`agenda.monthNames.0`), de propósito: assim a paridade também
 * cobre o COMPRIMENTO — uma lista de meses com 11 itens em um idioma e 12 no outro é
 * exatamente o tipo de erro que passa despercebido até dezembro.
 */
function caminhos(obj: Arvore, prefixo = ''): string[] {
  const saida: string[] = [];
  for (const [chave, valor] of Object.entries(obj)) {
    const caminho = prefixo ? `${prefixo}.${chave}` : chave;
    if (valor !== null && typeof valor === 'object') {
      saida.push(...caminhos(valor as Arvore, caminho));
    } else {
      saida.push(caminho);
    }
  }
  return saida.sort();
}

function folha(obj: Arvore, caminho: string): unknown {
  return caminho.split('.').reduce<unknown>((acc, parte) => (acc as Arvore)?.[parte], obj);
}

/** `{cliente}`, `{n}`, … — o que a frase espera receber de fora. */
function placeholders(texto: string): string[] {
  return (texto.match(/\{[a-zA-Z0-9_]+\}/g) ?? []).sort();
}

const caminhosEn = caminhos(en as unknown as Arvore);
const caminhosPt = caminhos(ptBR as unknown as Arvore);

describe('paridade dos dicionários pt-BR × en', () => {
  it('nenhuma chave existe só em pt-BR', () => {
    const soEmPt = caminhosPt.filter(c => !caminhosEn.includes(c));
    expect(soEmPt, `chaves sem tradução em inglês: ${soEmPt.join(', ')}`).toEqual([]);
  });

  it('nenhuma chave existe só em en', () => {
    const soEmEn = caminhosEn.filter(c => !caminhosPt.includes(c));
    expect(soEmEn, `chaves sem texto em português: ${soEmEn.join(', ')}`).toEqual([]);
  });

  it('as duas árvores têm exatamente a mesma forma', () => {
    expect(caminhosPt).toEqual(caminhosEn);
  });

  it('toda folha é string — nunca número, null ou objeto vazio', () => {
    for (const dicionario of [en, ptBR] as unknown as Arvore[]) {
      for (const caminho of caminhos(dicionario)) {
        expect(typeof folha(dicionario, caminho), `${caminho} não é string`).toBe('string');
      }
    }
  });

  it('nenhum texto é vazio ou só espaço — compila liso e some da tela', () => {
    for (const [nome, dicionario] of [['en', en], ['pt-BR', ptBR]] as Array<[string, Arvore]>) {
      for (const caminho of caminhos(dicionario)) {
        const texto = folha(dicionario, caminho) as string;
        expect(texto.trim().length, `${nome}.${caminho} está vazio`).toBeGreaterThan(0);
      }
    }
  });

  it('os placeholders batem entre os dois idiomas', () => {
    for (const caminho of caminhosEn) {
      const textoEn = folha(en as unknown as Arvore, caminho) as string;
      const textoPt = folha(ptBR as unknown as Arvore, caminho) as string;
      if (typeof textoEn !== 'string' || typeof textoPt !== 'string') continue;
      expect(
        placeholders(textoPt),
        `${caminho}: placeholders diferentes — en ${JSON.stringify(placeholders(textoEn))}, pt-BR ${JSON.stringify(placeholders(textoPt))}`,
      ).toEqual(placeholders(textoEn));
    }
  });
});
