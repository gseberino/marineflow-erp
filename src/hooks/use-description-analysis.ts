import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * A descrição do orçamento vira levantamento.
 *
 * O dono escreve "Substituir as baterias para sistema lifepo4, trocar os cabos
 * em acordo com o dimensionamento, colocar dispositivos de proteção nos
 * circuitos" — e até aqui o único botão de IA sobre esse texto reescrevia a
 * redação. O texto já diz o verbo, o sistema e metade das respostas.
 *
 * A IA escolhe o EIXO e pré-responde; ela NÃO inventa pergunta. Pergunta
 * inventada na hora não tem impacto no preço declarado, não entra no histórico
 * do ativo e não dispara regra de material: vira texto solto e morre ali. As
 * perguntas do catálogo fazem as três coisas.
 */

export interface CatalogQuestion {
  id: string;
  eixo: string;
  tipo_eixo: 'sistema' | 'verbo';
  question: string;
  answer_type: string;
  options: string[] | null;
  price_impact: string;
}

export interface PreAnswer {
  id: string;
  question: string;
  answer: string;
  /** 'alta' = a descrição diz isso com todas as letras. 'media' = dedução. */
  certeza: 'alta' | 'media';
  answer_type: string;
  options: string[] | null;
}

export interface DescriptionAnalysis {
  sistema: string | null;
  verbo: string | null;
  respostas: PreAnswer[];
  /** Perguntas do eixo que a descrição não respondeu — o que ainda falta. */
  faltam: CatalogQuestion[];
  materiais_citados: string[];
}

export function useQuestionCatalog() {
  return useQuery({
    queryKey: ['survey-question-catalog'],
    staleTime: 10 * 60 * 1000,
    queryFn: async (): Promise<CatalogQuestion[]> => {
      const { data, error } = await supabase.rpc('survey_question_catalog');
      if (error) throw error;
      return (data || []) as unknown as CatalogQuestion[];
    },
  });
}

/**
 * Lê o JSON que o modelo devolveu.
 *
 * Modelo devolve cerca ```json quando bem-comportado e prosa antes do objeto
 * quando não. Recortar do primeiro `{` ao último `}` aguenta os dois casos —
 * e falhar aqui não pode derrubar a tela: sem análise, o levantamento continua
 * abrindo do jeito manual.
 */
export function parseAnalysis(raw: string): {
  sistema?: string; verbo?: string;
  respostas?: Array<{ id: string; resposta: string; certeza?: string }>;
  materiais_citados?: string[];
} | null {
  if (!raw) return null;
  const inicio = raw.indexOf('{');
  const fim = raw.lastIndexOf('}');
  if (inicio < 0 || fim <= inicio) return null;
  try {
    return JSON.parse(raw.slice(inicio, fim + 1));
  } catch {
    return null;
  }
}

/** Monta o pedido. Separado da chamada para poder ser testado sem rede. */
export function buildPrompt(descricao: string, catalogo: CatalogQuestion[]): string {
  const perguntas = catalogo
    .map((q) => {
      const opc = q.options?.length ? ` [opções: ${q.options.join(' | ')}]` : '';
      return `${q.id}|${q.tipo_eixo}:${q.eixo}|${q.answer_type}|${q.question}${opc}`;
    })
    .join('\n');

  return [
    'Você conhece serviços de eletroeletrônica embarcada (Victron, LiFePO4) em lanchas, motorhomes e campers.',
    'Leia a DESCRIÇÃO de um orçamento e devolva SOMENTE um objeto JSON, sem cercas de código e sem comentários.',
    '',
    'Campos:',
    '- "sistema": um dos eixos de tipo sistema abaixo, ou null se não der para saber.',
    '- "verbo": um dos eixos de tipo verbo abaixo, ou null.',
    '- "respostas": lista de {"id","resposta","certeza"} SOMENTE para perguntas que a descrição realmente responde.',
    '  "certeza":"alta" quando o texto diz com todas as letras; "media" quando você deduziu.',
    '  NUNCA invente medida, corrente, distância ou modelo que não esteja escrito.',
    '  Se a descrição não responde a pergunta, NÃO a inclua.',
    '- "materiais_citados": materiais que o texto menciona, em palavras curtas.',
    '',
    'PERGUNTAS DISPONÍVEIS (id|eixo|tipo|pergunta):',
    perguntas,
    '',
    `DESCRIÇÃO:\n${descricao}`,
  ].join('\n');
}

export function useDescriptionAnalysis() {
  const [analisando, setAnalisando] = useState(false);
  const { data: catalogo = [] } = useQuestionCatalog();

  async function analisar(descricao: string): Promise<DescriptionAnalysis | null> {
    if (!descricao || descricao.trim().length < 15) return null;
    setAnalisando(true);
    try {
      const { data, error } = await supabase.functions.invoke('ai-agent', {
        body: {
          messages: [
            { role: 'system', content: 'Responda apenas com JSON válido.' },
            { role: 'user', content: buildPrompt(descricao, catalogo) },
          ],
          context: { entityType: 'quote_description', entityId: 'none' },
        },
      });
      if (error) throw error;

      const parsed = parseAnalysis(data?.message?.content || '');
      if (!parsed) return null;

      const porId = new Map(catalogo.map((q) => [q.id, q]));
      // Só entra resposta cuja pergunta existe no catálogo. Se o modelo
      // alucinar um id, a linha é descartada em silêncio — melhor perder uma
      // pré-resposta do que exibir uma pergunta que ninguém aprovou.
      const respostas: PreAnswer[] = (parsed.respostas || [])
        .filter((r) => r?.id && r?.resposta && porId.has(r.id))
        .map((r) => {
          const q = porId.get(r.id)!;
          return {
            id: r.id,
            question: q.question,
            answer: String(r.resposta),
            certeza: r.certeza === 'alta' ? 'alta' : 'media',
            answer_type: q.answer_type,
            options: q.options,
          };
        });

      const respondidas = new Set(respostas.map((r) => r.id));
      const doEixo = catalogo.filter(
        (q) =>
          (parsed.sistema && q.eixo === parsed.sistema) ||
          (parsed.verbo && q.eixo === parsed.verbo),
      );

      return {
        sistema: parsed.sistema ?? null,
        verbo: parsed.verbo ?? null,
        respostas,
        faltam: doEixo.filter((q) => !respondidas.has(q.id)),
        materiais_citados: (parsed.materiais_citados || []).filter(Boolean).slice(0, 12),
      };
    } catch {
      return null;
    } finally {
      setAnalisando(false);
    }
  }

  return { analisar, analisando, catalogo };
}
