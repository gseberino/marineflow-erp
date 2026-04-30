import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useExternalQuotes, useUpdateExternalQuoteStatus } from '@/hooks/use-external-quotes';
import { Check, X, Eye, User, Phone, Anchor, MessageCircle, AlertCircle } from 'lucide-react';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';

export default function ExternalQuoteApprovalPage() {
  const navigate = useNavigate();
  const { data: quotes, isLoading } = useExternalQuotes({ status: 'pending_approval' });
  const updateStatus = useUpdateExternalQuoteStatus();
  
  const [selectedQuote, setSelectedQuote] = useState<any>(null);
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [rejectionReason, setRejectionReason] = useState('');

  const handleApprove = async (quote: any) => {
    try {
      await updateStatus.mutateAsync({ id: quote.id, status: 'approved' });
      toast.success('Orçamento aprovado!');
    } catch (e) {
      console.error(e);
    }
  };

  const handleReject = async () => {
    if (!rejectionReason) {
      toast.error('Informe o motivo da recusa.');
      return;
    }
    try {
      await updateStatus.mutateAsync({ 
        id: selectedQuote.id, 
        status: 'cancelled',
        rejection_reason: rejectionReason 
      });
      setRejectDialogOpen(false);
      setRejectionReason('');
      setSelectedQuote(null);
      toast.success('Orçamento recusado.');
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader 
        title="Aprovação de Orçamentos Externos" 
        description="Revise as solicitações dos vendedores externos antes de converter em Ordem de Serviço."
      />

      <div className="grid grid-cols-1 gap-4">
        {isLoading ? (
          Array.from({ length: 3 }).map((_, i) => (
            <Card key={i} className="h-32 animate-pulse bg-muted/50" />
          ))
        ) : !quotes || quotes.length === 0 ? (
          <div className="py-20 text-center bg-muted/20 rounded-xl border-2 border-dashed">
            <Check className="h-12 w-12 text-green-500 mx-auto mb-3 opacity-20" />
            <p className="text-muted-foreground">Tudo em dia! Nenhuma solicitação pendente.</p>
          </div>
        ) : (
          quotes.map(quote => (
            <Card key={quote.id} className="overflow-hidden border-amber-100 hover:border-amber-200 transition-colors">
              <div className="flex flex-col md:flex-row">
                <div className="p-6 flex-1 space-y-4">
                  <div className="flex justify-between items-start">
                    <div className="space-y-1">
                      <div className="flex items-center gap-2">
                        <Badge variant="outline" className="text-amber-600 border-amber-200 bg-amber-50">Aguardando Revisão</Badge>
                        <span className="text-xs text-muted-foreground">
                          Enviado em {format(new Date(quote.created_at), "dd/MM/yyyy 'às' HH:mm", { locale: ptBR })}
                        </span>
                      </div>
                      <h3 className="text-xl font-bold flex items-center gap-2">
                        <User className="h-5 w-5 text-muted-foreground" />
                        {quote.client_name}
                      </h3>
                    </div>
                    <div className="text-right">
                      <p className="text-xs text-muted-foreground uppercase font-semibold">Total do Orçamento</p>
                      <p className="text-2xl font-bold text-primary">
                        {new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(quote.grand_total)}
                      </p>
                    </div>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm bg-muted/30 p-3 rounded-lg">
                    <div className="flex items-center gap-2">
                      <Phone className="h-4 w-4 text-muted-foreground" />
                      {quote.client_phone}
                    </div>
                    {quote.vessel_name && (
                      <div className="flex items-center gap-2">
                        <Anchor className="h-4 w-4 text-muted-foreground" />
                        {quote.vessel_name}
                      </div>
                    )}
                    <div className="flex items-center gap-2">
                      <User className="h-4 w-4 text-blue-500" />
                      <span className="font-medium">Vendedor: {quote.seller?.full_name || 'Desconhecido'}</span>
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label className="text-xs text-muted-foreground uppercase">Itens Solicitados</Label>
                    <div className="space-y-1">
                      {quote.items?.map((item: any) => (
                        <div key={item.id} className="flex justify-between text-sm py-1 border-b border-dashed last:border-0">
                          <span>{item.quantity}x {item.product_name_manual || 'Item s/ nome'}</span>
                          <span className="font-medium">{new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(item.line_total)}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>

                <div className="bg-muted/10 border-t md:border-t-0 md:border-l p-6 flex flex-row md:flex-col justify-center gap-3">
                  <Button 
                    className="w-full bg-green-600 hover:bg-green-700 gap-2"
                    onClick={() => handleApprove(quote)}
                    disabled={updateStatus.isPending}
                  >
                    <Check className="h-4 w-4" /> Aprovar
                  </Button>
                  <Button 
                    variant="outline" 
                    className="w-full text-destructive hover:bg-destructive/10 gap-2 border-destructive/20"
                    onClick={() => {
                      setSelectedQuote(quote);
                      setRejectDialogOpen(true);
                    }}
                    disabled={updateStatus.isPending}
                  >
                    <X className="h-4 w-4" /> Recusar
                  </Button>
                  <Button 
                    variant="secondary" 
                    className="w-full gap-2"
                    onClick={() => navigate(`/external-quotes/${quote.id}`)}
                  >
                    <Eye className="h-4 w-4" /> Ver Detalhes
                  </Button>
                  <Button variant="ghost" className="w-full gap-2 text-xs h-8">
                    <MessageCircle className="h-3 w-3" /> Falar com Vendedor
                  </Button>
                </div>
              </div>
            </Card>
          ))
        )}
      </div>

      <Dialog open={rejectDialogOpen} onOpenChange={setRejectDialogOpen}>
        <DialogContent className="max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-destructive">
              <AlertCircle className="h-5 w-5" /> Motivo da Recusa
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Explique o motivo para o vendedor</Label>
              <Textarea 
                placeholder="Ex: Preço incorreto, item fora de estoque, etc."
                value={rejectionReason}
                onChange={e => setRejectionReason(e.target.value)}
                rows={4}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRejectDialogOpen(false)}>Voltar</Button>
            <Button variant="destructive" onClick={handleReject}>Confirmar Recusa</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
