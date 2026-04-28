import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { BrainCircuit, Sparkles, Loader2, ArrowRight, TrendingUp, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface AIConsultantProps {
  data: {
    revenue?: any;
    performance?: any;
    profitability?: any;
  };
}

export function AIConsultantDashboard({ data }: AIConsultantProps) {
  const [analysis, setAnalysis] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const generateAnalysis = async () => {
    setLoading(true);
    try {
      const prompt = `
        Aja como um consultor de negócios especializado em oficinas náuticas. 
        Analise os seguintes dados reais da empresa MarineFlow e forneça um resumo executivo de 2 parágrafos com insights acionáveis e tom de voz motivador e profissional.
        
        DADOS:
        - Faturamento Total (30d): ${data.profitability?.totalRevenue || 'Sem dados'}
        - Lucro Real (30d): ${data.profitability?.totalProfit || 'Sem dados'}
        - Margem Média: ${data.profitability?.avgMargin?.toFixed(1) || '—'}%
        - OS Concluídas: ${data.performance?.completedCount || 0}
        - Conversão de Orçamentos: ${data.performance?.conversionRate?.toFixed(1) || 0}%
        - Tempo Médio de Entrega: ${data.performance?.avgCompletionHours?.toFixed(1) || 0} horas
      `;

      const { data: aiResponse, error } = await supabase.functions.invoke('ai-agent', {
        body: { 
          prompt,
          is_sales_copy: true // Usando o modo sales_copy para um tom mais polido/humanizado
        }
      });

      if (error) throw error;
      setAnalysis(aiResponse?.response || "Não foi possível gerar a análise no momento.");
    } catch (error) {
      console.error(error);
      toast.error("Erro ao consultar a IA.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card className="border-primary/20 bg-gradient-to-br from-primary/5 via-background to-background shadow-lg overflow-hidden">
      <CardHeader className="pb-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="p-2 bg-primary/10 rounded-lg">
              <BrainCircuit className="h-5 w-5 text-primary" />
            </div>
            <div>
              <CardTitle className="text-lg">Consultor Estratégico IA</CardTitle>
              <CardDescription>Análise inteligente baseada nos seus números reais.</CardDescription>
            </div>
          </div>
          {!analysis && (
            <Button 
              onClick={generateAnalysis} 
              disabled={loading}
              size="sm"
              className="bg-primary hover:bg-primary/90"
            >
              {loading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Sparkles className="h-4 w-4 mr-2" />}
              Gerar Insight
            </Button>
          )}
        </div>
      </CardHeader>
      <CardContent>
        {analysis ? (
          <div className="space-y-4 animate-in fade-in slide-in-from-top-2 duration-500">
            <div className="p-4 bg-card border rounded-xl shadow-sm relative group">
              <div className="absolute -top-3 -right-3 p-1 bg-emerald-500 text-white rounded-full">
                <TrendingUp className="h-4 w-4" />
              </div>
              <p className="text-sm leading-relaxed text-foreground whitespace-pre-wrap">
                {analysis}
              </p>
            </div>
            <div className="flex justify-between items-center text-[10px] text-muted-foreground italic px-2">
              <span>* Esta análise é gerada automaticamente com base nos dados do sistema.</span>
              <Button variant="ghost" size="sm" className="h-6 text-[10px]" onClick={() => setAnalysis(null)}>
                Nova Consulta
              </Button>
            </div>
          </div>
        ) : (
          <div className="py-8 flex flex-col items-center justify-center text-center gap-3">
            <div className="p-4 bg-muted/50 rounded-full">
              <Sparkles className="h-8 w-8 text-muted-foreground/30" />
            </div>
            <div className="max-w-[300px]">
              <p className="text-sm font-medium text-muted-foreground">Clique no botão acima para que a IA analise sua performance financeira e operacional.</p>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
