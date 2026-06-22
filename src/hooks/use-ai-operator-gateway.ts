import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

// Resultado do gateway ai-operator-gateway (espelha OperatorTurnResult do edge).
export interface OperatorIntent {
  kind: string;
  confidence: number;
  params: Record<string, string>;
  matchedBy: string;
}

export interface PolicyReason {
  code: string;
  level: 'auto_send' | 'needs_approval' | 'blocked';
  message: string;
}

export interface PolicyDecision {
  decision: 'auto_send' | 'needs_approval' | 'blocked';
  reasons: PolicyReason[];
  shadow: boolean;
  approvalRoute?: { kind: 'manager_whatsapp' | 'in_app'; to: string | null };
}

export interface OperatorResult {
  intent: OperatorIntent;
  plan: 'read' | 'create' | 'outbound' | 'llm' | 'none';
  policyDecision?: PolicyDecision;
  params: Record<string, string>;
  llmText?: string;
  message: string;
  executedWrite: boolean;
}

/**
 * Conversa com o ai-operator-gateway (Modo Operador beta).
 * O gateway NÃO executa escrita/envio — só devolve o plano/decisão.
 */
export function useAIOperatorGateway() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<OperatorResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function send(text: string): Promise<OperatorResult | null> {
    setLoading(true);
    setError(null);
    try {
      const { data, error: invokeErr } = await supabase.functions.invoke(
        'ai-operator-gateway',
        { body: { text } },
      );
      if (invokeErr) throw invokeErr;
      if ((data as any)?.error) throw new Error((data as any).error);
      const res = (data as any).result as OperatorResult;
      setResult(res);
      return res;
    } catch (e: any) {
      setError(e?.message || 'Erro ao consultar o operador');
      return null;
    } finally {
      setLoading(false);
    }
  }

  return { send, loading, result, error };
}
