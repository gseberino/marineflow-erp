import { describe, it, expect } from 'vitest';
import { parseAnalysis, buildPrompt, type CatalogQuestion } from './use-description-analysis';

/**
 * O parse é o ponto frágil de qualquer coisa que peça JSON a um modelo. Ele
 * falha em produção, não em teste — e quando falha não pode derrubar a tela:
 * sem análise, o levantamento continua abrindo do jeito manual.
 */
describe('leitura do JSON que o modelo devolve', () => {
  it('lê JSON puro', () => {
    expect(parseAnalysis('{"sistema":"eletrico_dc","verbo":"substituicao"}')).toEqual({
      sistema: 'eletrico_dc', verbo: 'substituicao',
    });
  });

  it('lê JSON dentro de cerca de código', () => {
    const raw = '```json\n{"sistema":"gas"}\n```';
    expect(parseAnalysis(raw)?.sistema).toBe('gas');
  });

  it('lê JSON com prosa antes e depois', () => {
    const raw = 'Claro! Aqui está:\n{"sistema":"hidraulico"}\nEspero ter ajudado.';
    expect(parseAnalysis(raw)?.sistema).toBe('hidraulico');
  });

  // Falhar devolvendo null é o comportamento certo: quem chama trata como
  // "não deu para ler" e o fluxo manual segue.
  it.each([
    ['', 'vazio'],
    ['desculpe, não consegui', 'sem chaves'],
    ['{isso não é json}', 'chaves com lixo dentro'],
    ['}{', 'chaves invertidas'],
  ])('devolve null para %s (%s)', (raw) => {
    expect(parseAnalysis(raw)).toBeNull();
  });
});

describe('o pedido enviado ao modelo', () => {
  const catalogo: CatalogQuestion[] = [
    {
      id: 'q1', eixo: 'eletrico_dc', tipo_eixo: 'sistema',
      question: 'Qual a distância entre o banco e o quadro?',
      answer_type: 'medida', options: null, price_impact: 'alto',
    },
    {
      id: 'q2', eixo: 'substituicao', tipo_eixo: 'verbo',
      question: 'A peça nova tem a mesma medida?',
      answer_type: 'escolha', options: ['mesma', 'muda'], price_impact: 'alto',
    },
  ];

  it('manda id, eixo e tipo de cada pergunta', () => {
    const p = buildPrompt('Trocar baterias', catalogo);
    expect(p).toContain('q1|sistema:eletrico_dc|medida|');
    expect(p).toContain('q2|verbo:substituicao|escolha|');
  });

  it('manda as opções das perguntas de escolha', () => {
    expect(buildPrompt('x', catalogo)).toContain('[opções: mesma | muda]');
  });

  // A instrução que mais importa: sem ela o modelo preenche metragem
  // plausível, e metragem plausível vira cabo comprado errado.
  it('proíbe inventar medida', () => {
    const p = buildPrompt('Trocar baterias', catalogo);
    expect(p).toMatch(/NUNCA invente medida/);
    expect(p).toMatch(/Se a descrição não responde a pergunta, NÃO a inclua/);
  });

  it('inclui a descrição do orçamento', () => {
    expect(buildPrompt('Substituir baterias LiFePO4', catalogo))
      .toContain('Substituir baterias LiFePO4');
  });
});
