import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  getExternalQuotePartName,
  getExternalQuotePartyName,
  getExternalQuoteServiceName,
  getExternalQuoteVesselName,
  useExternalQuote,
} from '@/hooks/use-external-quotes';
import { ChevronLeft, Phone, Anchor, User, Calendar, MessageCircle, AlertCircle, ShoppingCart, CheckCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';

export default function ExternalQuoteDetailPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { data: quote, isLoading, refetch } = useExternalQuote(id || '');
  const [isConverting, setIsConverting] = useState(false);

  const handleConvertToOS = async () => {
    if (!id) return;
    setIsConverting(true);
    try {
      // Chama a função RPC que o Lovable criou no banco
      const { data, error } = await supabase.rpc('convert_external_quote_to_so', { 
        _quote_id: id 
      });

      if (error) throw error;

      toast.success('Convertido em Ordem de Serviço com sucesso!');
      refetch(); // Atualiza o status para 'converted'
      
      // Se retornou o ID da nova OS, podemos oferecer para navegar até ela
      if (data) {
        toast.info('Nova OS gerada!', {
          action: {
            label: 'Ver OS',
            onClick: () => navigate(`/service-orders/${data}`)
          }
        });
      }
    } catch (e: any) {
      console.error(e);
      toast.error('Erro na conversão: ' + e.message);
    } finally {
      setIsConverting(false);
    }
  };

  if (isLoading) return <div className="p-8 text-center">Carregando detalhes...</div>;
  if (!quote) return <div className="p-8 text-center text-red-500">Orçamento não encontrado.</div>;

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'pending_approval': return <Badge variant="outline" className="text-amber-600 border-amber-200 bg-amber-50">Aguardando Aprovação</Badge>;
      case 'approved': return <Badge variant="outline" className="text-green-600 border-green-200 bg-green-50">Aprovado</Badge>;
      case 'converted': return <Badge className="bg-green-600">Convertido em OS</Badge>;
      case 'cancelled': return <Badge variant="destructive">Recusado/Cancelado</Badge>;
      default: return <Badge variant="secondary">{status}</Badge>;
    }
  };

  return (
    <div className="space-y-6 animate-fade-in max-w-4xl mx-auto">
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={() => navigate(-1)}>
          <ChevronLeft className="h-5 w-5" />
        </Button>
        <PageHeader 
          title={`Orçamento #${quote.id.slice(0, 8)}`} 
          description="Detalhes da solicitação de venda externa"
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="md:col-span-2 space-y-6">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between">
              <CardTitle>Produtos e Serviços</CardTitle>
              {getStatusBadge(quote.status)}
            </CardHeader>
            <CardContent>
                <div className="space-y-4">
                  {quote.parts?.map((item, index) => (
                    <div key={item.id} className="flex justify-between items-start py-3 border-b last:border-0">
                      <div>
                        <p className="font-medium">{getExternalQuotePartName(item)}</p>
                        <p className="text-xs text-muted-foreground">Qtd: {item.quantity}</p>
                      </div>
                      <div className="text-right">
                        <p className="font-semibold">
                          {new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(item.line_total_sale)}
                        </p>
                        <p className="text-[10px] text-muted-foreground">
                          {new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(item.unit_sale_snapshot)} /un
                        </p>
                      </div>
                    </div>
                  ))}
                  {quote.services?.map((item, index) => (
                    <div key={item.id} className="flex justify-between items-start py-3 border-b last:border-0">
                      <div>
                        <p className="font-medium">{getExternalQuoteServiceName(item)}</p>
                        <p className="text-xs text-muted-foreground">Qtd: {item.quantity}</p>
                      </div>
                      <div className="text-right">
                        <p className="font-semibold">
                          {new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(item.line_total)}
                        </p>
                        <p className="text-[10px] text-muted-foreground">
                          {new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(item.unit_price_snapshot)} /un
                        </p>
                      </div>
                    </div>
                  ))}

                <div className="pt-4 space-y-2">
                  <div className="flex justify-between text-sm">
                    <span className="text-muted-foreground">Subtotal</span>
                    <span>{new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format((quote as any).subtotal ?? quote.grand_total)}</span>
                  </div>
                  {quote.discount_amount > 0 && (
                    <div className="flex justify-between text-sm text-green-600">
                      <span>Desconto</span>
                      <span>-{new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(quote.discount_amount)}</span>
                    </div>
                  )}
                  <div className="flex justify-between text-xl font-bold border-t pt-2">
                    <span>Total</span>
                    <span className="text-primary">{new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(quote.grand_total || 0)}</span>
                  </div>
                </div>
              </div>

              {quote.parts?.some((it: any) => !it.product_id) && (
                <div className="mt-4 p-3 bg-amber-50 border border-amber-200 rounded-lg flex items-start gap-2 text-sm text-amber-800">
                  <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
                  <div>
                    <p className="font-semibold">Itens não vinculados ao estoque</p>
                    <p className="text-xs">Existem itens neste orçamento que não estão vinculados a produtos do catálogo. Eles serão ignorados na geração da OS. Vincule-os antes de converter.</p>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>

          {quote.rejection_reason && (
            <Card className="border-red-200 bg-red-50">
              <CardHeader className="pb-2">
                <CardTitle className="text-sm flex items-center gap-2 text-red-700">
                  <AlertCircle className="h-4 w-4" /> Motivo da Recusa
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-red-600 italic">"{quote.rejection_reason}"</p>
              </CardContent>
            </Card>
          )}
        </div>

        <div className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-sm">Cliente</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-primary/10 rounded-full">
                  <User className="h-4 w-4 text-primary" />
                </div>
                <div>
                  <p className="text-sm font-medium">{getExternalQuotePartyName(quote)}</p>
                  <p className="text-xs text-muted-foreground">{quote.client?.phone || quote.lead?.phone || '—'}</p>
                </div>
              </div>
              {(quote.vessel?.boat_name || quote.lead?.boat_name) && (
                <div className="flex items-center gap-3">
                  <div className="p-2 bg-blue-100 rounded-full">
                    <Anchor className="h-4 w-4 text-blue-600" />
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Embarcação/Unidade</p>
                    <p className="text-sm font-medium">{getExternalQuoteVesselName(quote)}</p>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-sm">Histórico</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm">
              <div className="flex items-center gap-2 text-muted-foreground">
                <Calendar className="h-4 w-4" />
                <span>Criado em: {format(new Date(quote.created_at), "dd/MM/yyyy HH:mm", { locale: ptBR })}</span>
              </div>
              {(quote as any).approved_at && (
                <div className="flex items-center gap-2 text-green-600">
                  <Calendar className="h-4 w-4" />
                  <span>Aprovado em: {format(new Date((quote as any).approved_at), "dd/MM/yyyy HH:mm", { locale: ptBR })}</span>
                </div>
              )}
            </CardContent>
          </Card>

          <Button className="w-full gap-2" variant="outline">
            <MessageCircle className="h-4 w-4" /> Falar com Financeiro
          </Button>

          {quote.status === 'approved' && (
            <Button 
              className="w-full gap-2 bg-green-600 hover:bg-green-700" 
              onClick={handleConvertToOS}
              disabled={isConverting}
            >
              <ShoppingCart className="h-4 w-4" /> 
              {isConverting ? 'Convertendo...' : 'Gerar Ordem de Serviço'}
            </Button>
          )}

          {quote.status === 'converted' && quote.converted_service_order_id && (
            <Button 
              className="w-full gap-2 border-green-200 text-green-700 bg-green-50" 
              variant="outline"
              onClick={() => navigate(`/service-orders/${quote.converted_service_order_id}`)}
            >
              <CheckCircle className="h-4 w-4" /> Ver OS Gerada
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}
