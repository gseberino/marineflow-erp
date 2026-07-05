// Meta-tools de UI (não tocam banco) + optimize_text (chamada de LLM sem tools).
// Desvio pequeno da árvore de arquivos original do plano (não havia módulo dedicado
// para elas) — agrupadas aqui por não pertencerem a nenhum domínio de negócio.
//
// propose_action existiu na Fase 1 mas foi removida na Fase 3: agent.ts agora
// intercepta automaticamente qualquer tool com risk !== "low" (sem o modelo precisar
// chamar uma meta-tool própria) e gera a pendência de aprovação sozinho.
import type { ToolDef } from "./registry.ts";
import { callClaude } from "../anthropic.ts";
import { MODEL_LITE } from "../models.ts";

const CONTEXT_LABELS: Record<string, string> = {
  problem_description: "descrição de problema técnico em embarcação",
  service_notes: "observações de serviço técnico náutico",
  proposal: "proposta comercial de serviço náutico",
  observation: "observação técnica",
};

export const uiTools: ToolDef[] = [
  {
    name: "present_options",
    description:
      "Use quando precisar que o usuário escolha entre opções. Exemplos: múltiplos clientes, múltiplas OSs, sim/não. Prefira sempre esta tool a escrever uma lista em texto. Máximo 6 opções visíveis. Se houver mais de 5 resultados, mostre os 5 mais relevantes + última opção sendo {label:'🔍 Refinar busca — digitar mais detalhes',value:'__refine__'}. Se o usuário escolher __refine__, peça mais informações específicas (sobrenome, telefone, CNPJ).",
    input_schema: {
      type: "object",
      properties: {
        question: { type: "string", description: "Pergunta clara para o usuário (ex: 'Qual cliente você quer?')" },
        options: {
          type: "array",
          maxItems: 6,
          items: {
            type: "object",
            properties: {
              label: { type: "string", description: "Texto visível no botão (curto, max 50 chars). Inclua info útil: nome + telefone ou nome + cidade." },
              value: { type: "string", description: "Valor interno: UUID do registro, ou '__refine__' para pedir mais detalhes." },
            },
            required: ["label", "value"],
          },
          description: "Lista de opções (máx 6). Se resultados > 5, inclua os 5 melhores + {label:'🔍 Refinar busca',value:'__refine__'}.",
        },
        total_found: { type: "number", description: "Total de resultados encontrados (para informar o usuário quando > 5)" },
      },
      required: ["question", "options"],
    },
    risk: "low",
    async execute(args) {
      // Read-only: sinaliza para o frontend renderizar botões clicáveis.
      return {
        options_ready: true,
        question: args.question,
        options: args.options,
        instruction: "Aguardando seleção do usuário.",
      };
    },
  },
  {
    name: "optimize_text",
    description: "Melhora/reescreve um texto de observação, descrição de problema ou proposta usando IA. Retorna o texto otimizado.",
    input_schema: {
      type: "object",
      properties: {
        text: { type: "string", description: "Texto original a ser melhorado" },
        context: { type: "string", description: "Contexto: 'problem_description', 'service_notes', 'proposal', 'observation'" },
      },
      required: ["text", "context"],
    },
    risk: "low",
    async execute(args) {
      const label = CONTEXT_LABELS[args.context] || args.context;
      const result = await callClaude({
        model: MODEL_LITE,
        system: [
          {
            type: "text",
            text: `Você é um especialista em comunicação técnica náutica. Reescreva o texto a seguir como ${label}, mantendo as informações originais mas tornando-o mais claro, profissional e preciso. Responda APENAS com o texto reescrito, sem explicações.`,
          },
        ],
        messages: [{ role: "user", content: [{ type: "text", text: String(args.text || "") }] }],
        maxTokens: 1024,
      });
      const optimized =
        result.content
          .filter((b): b is { type: "text"; text: string } => b.type === "text")
          .map((b) => b.text)
          .join("\n")
          .trim() || args.text;
      return { original: args.text, optimized };
    },
  },
];
