import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export function useAITextOptimizer() {
  const [isOptimizing, setIsOptimizing] = useState(false);

  const optimizeText = async (text: string): Promise<string> => {
    if (!text || text.trim().length < 5) {
      toast.error('Texto muito curto para otimizar');
      return text;
    }

    setIsOptimizing(true);
    try {
      const { data, error } = await supabase.functions.invoke('ai-agent', {
        body: {
          messages: [
            {
              role: 'system',
              content: 'Você é um especialista em redação técnica para manutenção naval e automação de motorhomes. Sua tarefa é melhorar a descrição a seguir. Deixe-a mais profissional, clara, objetiva e com jargões técnicos adequados. Corrija a gramática se necessário. Retorne APENAS o texto reescrito, sem introduções ou aspas.'
            },
            {
              role: 'user',
              content: text
            }
          ],
          context: { entityType: 'unknown', entityId: 'none' }
        }
      });

      if (error) throw error;
      if (data?.error) throw new Error(data.error);

      // Extract the assistant's reply
      const replyContent = data?.message?.content || '';
      
      if (replyContent) {
        toast.success('Texto otimizado com sucesso!');
        return replyContent.trim();
      } else {
        toast.error('A IA não retornou um texto válido.');
        return text;
      }
    } catch (e: any) {
      console.error('Text optimizer error:', e);
      toast.error('Erro ao otimizar texto: ' + (e.message || 'Erro desconhecido'));
      return text;
    } finally {
      setIsOptimizing(false);
    }
  };

  return { isOptimizing, optimizeText };
}
