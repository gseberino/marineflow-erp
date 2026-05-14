import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Rocket, Target, History, RefreshCw, MessageCircle, Send, TrendingUp, Sparkles, AlertCircle } from 'lucide-react';
import { useSendWhatsAppText } from '@/hooks/use-whatsapp-inbox';
import { toast } from 'sonner';
import { Textarea } from '@/components/ui/textarea';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';

export default function ActiveProspectingPage() {
  const [abandonedQuotes, setAbandonedQuotes] = useState<any[]>([]);
  const [maintenanceTargets, setMaintenanceTargets] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedTarget, setSelectedTarget] = useState<any>(null);
  const [draftMsg, setDraftMsg] = useState('');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [isGenerating, setIsGenerating] = useState(false);

  const sendWa = useSendWhatsAppText();

  const fetchTargets = async () => {
    setLoading(true);
    try {
      // 1. Orçamentos Abandonados (draft) há mais de 2 dias
      const twoDaysAgo = new Date();
      twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);

      const { data: quotes } = await supabase
        .from('service_orders')
        .select('*, clients(name:full_name_or_company_name, phone, whatsapp)')
        .eq('status', 'draft')
        .lte('created_at', twoDaysAgo.toISOString())
        .order('created_at', { ascending: false })
        .limit(20);

      setAbandonedQuotes(quotes || []);

      // 2. Embarcações que precisam de manutenção (última OS concluída há > 6 meses)
      const sixMonthsAgo = new Date();
      sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);

      // Usando uma query simples para pegar OS antigas e agrupar (simplificado para demonstração)
      const { data: oldOs } = await supabase
        .from('service_orders')
        .select('*, clients(name:full_name_or_company_name, phone, whatsapp), vessels(name:boat_name, engine_type)')
        .eq('status', 'completed')
        .lte('created_at', sixMonthsAgo.toISOString())
        .order('created_at', { ascending: false })
        .limit(20);

      // Filtrar duplicatas de embarcações
      const uniqueVessels = new Map();
      oldOs?.forEach(os => {
        if (os.vessel_id && !uniqueVessels.has(os.vessel_id)) {
          uniqueVessels.set(os.vessel_id, os);
        }
      });
      setMaintenanceTargets(Array.from(uniqueVessels.values()));

    } catch (e) {
      console.error(e);
      toast.error('Erro ao buscar alvos de prospecção');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchTargets();
  }, []);

  const generateSalesCopy = async (type: 'quote' | 'maintenance', target: any) => {
    setIsGenerating(true);
    const clientName = target.clients?.name?.split(' ')[0] || 'Cliente';
    const total = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(target.grand_total || 0);
    
    let prompt = '';
    if (type === 'quote') {
      prompt = `Crie uma mensagem curta de WhatsApp muito persuasiva e educada para ${clientName}. Ele tem um orçamento (OS #${target.service_order_number}) de ${total} parado no status rascunho. O objetivo é fechar a venda agora. Ofereça de forma sutil uma facilidade (tipo parcelamento ou prioridade na agenda). Use gatilhos mentais. Não pareça desesperado.`;
    } else {
      const boat = target.vessels?.name || 'sua embarcação';
      prompt = `Crie uma mensagem curta de WhatsApp para ${clientName}. Já faz mais de 6 meses que fizemos a última revisão no ${boat}. Sugira uma manutenção preventiva para evitar dores de cabeça e garantir a diversão no fim de semana. Seja muito amigável e focado em segurança e tranquilidade.`;
    }

    try {
      const { data, error } = await supabase.functions.invoke('ai-agent', {
        body: { 
          messages: [{ role: 'user', content: prompt }],
          is_sales_copy: true,
          context: { route: '/prospecting' }
        }
      });
      
      if (error) throw error;
      
      const aiText = data?.message?.content || data?.reply || "Olá, tudo bem? Notei que...";
      setDraftMsg(aiText.replace(/[*#]/g, ''));
    } catch (e) {
      console.error(e);
      // Fallbacks elegantes se a IA falhar
      if (type === 'quote') {
        setDraftMsg(`Olá ${clientName}, tudo bem? Estou revisando aqui o orçamento da sua OS #${target.service_order_number}. Queria ver com você se ficou alguma dúvida e se podemos aprovar para eu já garantir o seu horário na nossa agenda da semana. Conseguimos facilitar o pagamento se precisar! Me avise.`);
      } else {
        setDraftMsg(`Olá ${clientName}, tudo joia? Notei no nosso sistema que já faz um tempinho desde a última revisão do ${target.vessels?.name}. Para garantir sua tranquilidade e segurança nos próximos passeios, que tal agendarmos uma manutenção preventiva? Assim evitamos imprevistos. Um abraço!`);
      }
    } finally {
      setIsGenerating(false);
    }
  };

  const handleOpenDialog = (target: any, type: 'quote' | 'maintenance') => {
    setSelectedTarget({ ...target, _type: type });
    setDraftMsg('');
    setDialogOpen(true);
    generateSalesCopy(type, target);
  };

  const handleSend = async () => {
    if (!selectedTarget || !draftMsg) return;
    const phone = selectedTarget.clients?.whatsapp || selectedTarget.clients?.phone;
    
    if (!phone) {
      toast.error('Este cliente não possui telefone cadastrado.');
      return;
    }

    try {
      await sendWa.mutateAsync({ phone, message: draftMsg });
      toast.success('Mensagem de prospecção enviada!');
      setDialogOpen(false);
      // Remover da lista
      if (selectedTarget._type === 'quote') {
        setAbandonedQuotes(q => q.filter(x => x.id !== selectedTarget.id));
      } else {
        setMaintenanceTargets(m => m.filter(x => x.id !== selectedTarget.id));
      }
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader 
        title="Motor de Vendas & Prospecção" 
        description="Aumente seu fluxo de caixa reativando orçamentos parados e agendando manutenções preventivas com a ajuda da IA."
      />

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <Card className="bg-gradient-to-br from-primary/10 to-transparent border-primary/20 shadow-sm">
          <CardContent className="p-6">
            <div className="flex justify-between items-start">
              <div>
                <p className="text-sm font-medium text-muted-foreground mb-1">Potencial de Fechamento</p>
                <h3 className="text-3xl font-bold text-primary">
                  {new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
                    abandonedQuotes.reduce((acc, curr) => acc + (curr.grand_total || 0), 0)
                  )}
                </h3>
                <p className="text-xs text-muted-foreground mt-2">Em orçamentos pendentes</p>
              </div>
              <div className="p-3 bg-primary/10 rounded-xl"><TrendingUp className="h-6 w-6 text-primary" /></div>
            </div>
          </CardContent>
        </Card>
      </div>

      <Tabs defaultValue="quotes">
        <TabsList className="w-full justify-start border-b rounded-none h-auto bg-transparent p-0">
          <TabsTrigger value="quotes" className="data-[state=active]:border-b-2 data-[state=active]:border-primary rounded-none py-3 px-6">
            <Target className="h-4 w-4 mr-2" />
            Orçamentos Pendentes ({abandonedQuotes.length})
          </TabsTrigger>
          <TabsTrigger value="maintenance" className="data-[state=active]:border-b-2 data-[state=active]:border-primary rounded-none py-3 px-6">
            <History className="h-4 w-4 mr-2" />
            Revisões Preventivas ({maintenanceTargets.length})
          </TabsTrigger>
        </TabsList>

        <TabsContent value="quotes" className="pt-6">
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {loading ? (
              <p className="text-muted-foreground">Analisando base de dados...</p>
            ) : abandonedQuotes.length === 0 ? (
              <div className="col-span-full py-12 text-center bg-card rounded-xl border border-dashed">
                <AlertCircle className="h-8 w-8 mx-auto text-muted-foreground mb-3 opacity-50" />
                <p className="text-muted-foreground">Nenhum orçamento parado no momento. Ótimo trabalho!</p>
              </div>
            ) : (
              abandonedQuotes.map(quote => (
                <Card key={quote.id} className="hover:border-primary/50 transition-colors">
                  <CardHeader className="pb-3">
                    <div className="flex justify-between items-start">
                      <Badge variant="outline" className="bg-amber-100 text-amber-800">Rascunho</Badge>
                      <span className="text-xs text-muted-foreground">Há {Math.floor((Date.now() - new Date(quote.created_at).getTime()) / (1000 * 60 * 60 * 24))} dias</span>
                    </div>
                    <CardTitle className="text-lg mt-2">{quote.clients?.name}</CardTitle>
                    <CardDescription>OS #{quote.service_order_number}</CardDescription>
                  </CardHeader>
                  <CardContent>
                    <p className="text-2xl font-bold mb-4">
                      {new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(quote.grand_total || 0)}
                    </p>
                    <Button className="w-full" onClick={() => handleOpenDialog(quote, 'quote')}>
                      <Sparkles className="h-4 w-4 mr-2 text-yellow-300" />
                      Criar Abordagem com IA
                    </Button>
                  </CardContent>
                </Card>
              ))
            )}
          </div>
        </TabsContent>

        <TabsContent value="maintenance" className="pt-6">
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {loading ? (
               <p className="text-muted-foreground">Analisando base de dados...</p>
            ) : maintenanceTargets.length === 0 ? (
              <div className="col-span-full py-12 text-center bg-card rounded-xl border border-dashed">
                <p className="text-muted-foreground">Todas as embarcações estão com a manutenção em dia!</p>
              </div>
            ) : (
              maintenanceTargets.map(target => (
                <Card key={target.id} className="hover:border-primary/50 transition-colors">
                  <CardHeader className="pb-3">
                    <Badge variant="outline" className="bg-blue-100 text-blue-800 w-fit">Prevenção</Badge>
                    <CardTitle className="text-lg mt-2">{target.vessels?.name}</CardTitle>
                    <CardDescription>Cliente: {target.clients?.name}</CardDescription>
                  </CardHeader>
                  <CardContent>
                    <p className="text-sm text-muted-foreground mb-4">
                      Última revisão: {new Date(target.created_at).toLocaleDateString('pt-BR')}
                    </p>
                    <Button className="w-full bg-blue-600 hover:bg-blue-700 text-white" onClick={() => handleOpenDialog(target, 'maintenance')}>
                      <Sparkles className="h-4 w-4 mr-2 text-yellow-300" />
                      Oferecer Revisão (IA)
                    </Button>
                  </CardContent>
                </Card>
              ))
            )}
          </div>
        </TabsContent>
      </Tabs>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="sm:max-w-md max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <MessageCircle className="h-5 w-5 text-green-500" />
              Revisar Mensagem
            </DialogTitle>
          </DialogHeader>
          <div className="py-4">
            {isGenerating ? (
              <div className="flex flex-col items-center justify-center py-6 text-muted-foreground space-y-3">
                <RefreshCw className="h-8 w-8 animate-spin text-primary" />
                <p className="text-sm animate-pulse">IA está escrevendo a melhor abordagem comercial...</p>
              </div>
            ) : (
              <Textarea 
                value={draftMsg}
                onChange={(e) => setDraftMsg(e.target.value)}
                className="min-h-[150px] text-base p-4 resize-none focus-visible:ring-green-500"
              />
            )}
          </div>
          <DialogFooter className="flex gap-2 sm:justify-between">
            <p className="text-xs text-muted-foreground flex items-center">
              A mensagem será enviada via WhatsApp Oficial.
            </p>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancelar</Button>
              <Button onClick={handleSend} disabled={isGenerating || !draftMsg || sendWa.isPending} className="bg-green-600 hover:bg-green-700 text-white">
                <Send className="h-4 w-4 mr-2" />
                {sendWa.isPending ? 'Enviando...' : 'Enviar Agora'}
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
