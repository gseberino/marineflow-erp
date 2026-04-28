import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Textarea } from '@/components/ui/textarea';
import { PageHeader } from '@/components/PageHeader';
import { Loader2, Sparkles, Copy } from 'lucide-react';
import { toast } from 'sonner';

export default function ProspectingPage() {
  const [prompt, setPrompt] = useState('');
  const [loading, setLoading] = useState(false);
  const [output, setOutput] = useState('');

  const handleGenerate = async () => {
    if (!prompt.trim()) {
      toast.error('Descreva o objetivo da mensagem');
      return;
    }
    setLoading(true);
    setOutput('');
    try {
      const { data, error } = await supabase.functions.invoke('ai-agent', {
        body: {
          messages: [{ role: 'user', content: prompt }],
          context: { route: '/prospecting', entityType: 'prospecting' },
          is_sales_copy: true,
        },
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);
      setOutput((data as any)?.message?.content || '');
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao gerar mensagem');
    } finally {
      setLoading(false);
    }
  };

  const handleCopy = async () => {
    if (!output) return;
    await navigator.clipboard.writeText(output);
    toast.success('Mensagem copiada');
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Prospecção & Vendas"
        description="Gere mensagens de WhatsApp persuasivas para captação e relacionamento"
      />

      <Card>
        <CardHeader>
          <CardTitle>Briefing</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <Textarea
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            rows={6}
            placeholder="Ex.: Enviar mensagem para o Sr. João, dono da lancha Aventura, oferecendo revisão preventiva do painel elétrico antes da temporada de verão. Tom consultivo, agendar visita."
          />
          <Button onClick={handleGenerate} disabled={loading}>
            {loading ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" /> Gerando...
              </>
            ) : (
              <>
                <Sparkles className="h-4 w-4 mr-2" /> Gerar mensagem
              </>
            )}
          </Button>
        </CardContent>
      </Card>

      {output && (
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0">
            <CardTitle>Mensagem pronta</CardTitle>
            <Button variant="outline" size="sm" onClick={handleCopy}>
              <Copy className="h-4 w-4 mr-2" /> Copiar
            </Button>
          </CardHeader>
          <CardContent>
            <pre className="whitespace-pre-wrap font-sans text-sm bg-muted p-4 rounded-md">
              {output}
            </pre>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
