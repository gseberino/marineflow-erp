import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useExternalQuotes, type ExternalQuoteStatus } from '@/hooks/use-external-quotes';
import { Plus, Clock, CheckCircle2, XCircle, ShoppingBag, FileText, TrendingUp, Filter } from 'lucide-react';
import { Link } from 'react-router-dom';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useAuth } from '@/hooks/use-auth';

export default function ExternalQuoteListPage() {
  const { user } = useAuth();
  const [statusFilter, setStatusFilter] = useState<string>('all');
  
  // Se não for admin nem financeiro, filtra pelo próprio ID do usuário
  const sellerId = (user?.role !== 'admin' && user?.role !== 'financial') ? user?.id : undefined;
  
  const { data: quotes, isLoading } = useExternalQuotes({
    status: statusFilter === 'all' ? undefined : statusFilter,
    seller_id: sellerId
  });

  const getStatusBadge = (status: ExternalQuoteStatus) => {
    switch (status) {
      case 'draft': return <Badge variant="secondary">Rascunho</Badge>;
      case 'pending_approval': return <Badge variant="outline" className="text-amber-600 border-amber-200 bg-amber-50">Aguardando Aprovação</Badge>;
      case 'pending_product': return <Badge variant="outline" className="text-blue-600 border-blue-200 bg-blue-50">Cadastrando Produto</Badge>;
      case 'approved': return <Badge variant="outline" className="text-green-600 border-green-200 bg-green-50">Aprovado</Badge>;
      case 'converted': return <Badge className="bg-green-600">Convertido em OS</Badge>;
      case 'cancelled': return <Badge variant="destructive">Cancelado</Badge>;
      default: return <Badge>{status}</Badge>;
    }
  };

  const getStatusIcon = (status: ExternalQuoteStatus) => {
    switch (status) {
      case 'pending_approval': return <Clock className="h-5 w-5 text-amber-500" />;
      case 'approved': return <CheckCircle2 className="h-5 w-5 text-green-500" />;
      case 'cancelled': return <XCircle className="h-5 w-5 text-red-500" />;
      case 'converted': return <ShoppingBag className="h-5 w-5 text-green-600" />;
      default: return <FileText className="h-5 w-5 text-muted-foreground" />;
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader 
        title="Meus Orçamentos Externos" 
        description="Acompanhe o status dos orçamentos enviados para aprovação."
      >
        <Link to="/external-quotes/new">
          <Button className="gap-2">
            <Plus className="h-4 w-4" /> Novo Orçamento
          </Button>
        </Link>
      </PageHeader>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="bg-gradient-to-br from-primary/5 to-transparent border-primary/10">
          <CardContent className="p-6 flex items-center gap-4">
            <div className="p-3 bg-primary/10 rounded-xl">
              <TrendingUp className="h-6 w-6 text-primary" />
            </div>
            <div>
              <p className="text-sm font-medium text-muted-foreground">Total em Orçamentos</p>
              <h3 className="text-2xl font-bold">
                {new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
                  quotes?.reduce((acc, curr) => acc + (curr.grand_total || 0), 0) || 0
                )}
              </h3>
            </div>
          </CardContent>
        </Card>

        <Card className="bg-gradient-to-br from-amber-50 to-transparent border-amber-100">
          <CardContent className="p-6 flex items-center gap-4">
            <div className="p-3 bg-amber-100 rounded-xl">
              <Clock className="h-6 w-6 text-amber-600" />
            </div>
            <div>
              <p className="text-sm font-medium text-muted-foreground">Aguardando Aprovação</p>
              <h3 className="text-2xl font-bold">
                {quotes?.filter(q => q.status === 'pending_approval').length || 0}
              </h3>
            </div>
          </CardContent>
        </Card>

        <Card className="bg-gradient-to-br from-green-50 to-transparent border-green-100">
          <CardContent className="p-6 flex items-center gap-4">
            <div className="p-3 bg-green-100 rounded-xl">
              <CheckCircle2 className="h-6 w-6 text-green-600" />
            </div>
            <div>
              <p className="text-sm font-medium text-muted-foreground">Aprovados este Mês</p>
              <h3 className="text-2xl font-bold">
                {quotes?.filter(q => q.status === 'approved' || q.status === 'converted').length || 0}
              </h3>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="flex justify-end items-center gap-3 bg-muted/30 p-2 rounded-lg">
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <Filter className="h-4 w-4" /> Filtrar por:
        </div>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-[180px] h-9 bg-white">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos os Status</SelectItem>
            <SelectItem value="draft">Rascunho</SelectItem>
            <SelectItem value="pending_approval">Pendente</SelectItem>
            <SelectItem value="approved">Aprovado</SelectItem>
            <SelectItem value="converted">Convertido</SelectItem>
            <SelectItem value="cancelled">Cancelado</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {isLoading ? (
          Array.from({ length: 6 }).map((_, i) => (
            <Card key={i} className="h-48 animate-pulse bg-muted/50" />
          ))
        ) : quotes?.length === 0 ? (
          <div className="col-span-full py-20 text-center space-y-4">
            <FileText className="h-12 w-12 text-muted-foreground mx-auto opacity-20" />
            <p className="text-muted-foreground">Nenhum orçamento encontrado com este filtro.</p>
            <Link to="/external-quotes/new">
              <Button variant="link">Criar seu primeiro orçamento</Button>
            </Link>
          </div>
        ) : (
          quotes?.map(quote => (
            <Card key={quote.id} className="hover:border-primary/40 transition-all group">
              <CardHeader className="pb-3 flex flex-row items-center justify-between space-y-0">
                <div className="flex items-center gap-3">
                  <div className="p-2 bg-muted rounded-lg group-hover:bg-primary/10 transition-colors">
                    {getStatusIcon(quote.status)}
                  </div>
                  <div>
                    <CardTitle className="text-sm font-medium">{quote.client_name}</CardTitle>
                    <p className="text-xs text-muted-foreground">
                      {format(new Date(quote.created_at), "dd 'de' MMMM", { locale: ptBR })}
                    </p>
                  </div>
                </div>
                {getStatusBadge(quote.status)}
              </CardHeader>
              <CardContent>
                <div className="flex justify-between items-end">
                  <div className="space-y-1">
                    <p className="text-xs text-muted-foreground">Total</p>
                    <p className="text-xl font-bold text-primary">
                      {new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(quote.grand_total)}
                    </p>
                  </div>
                  {quote.status === 'pending_approval' && (
                    <Badge variant="outline" className="text-[10px] animate-pulse">Pendente</Badge>
                  )}
                </div>
                
                {quote.rejection_reason && (
                  <div className="mt-3 p-2 bg-red-50 border border-red-100 rounded text-[10px] text-red-600">
                    <strong>Motivo da recusa:</strong> {quote.rejection_reason}
                  </div>
                )}

                <div className="mt-4 pt-4 border-t flex justify-between items-center text-[10px] text-muted-foreground">
                  <span>{quote.items?.length || 0} itens</span>
                  <Link to={`/external-quotes/${quote.id}`}>
                    <Button variant="ghost" size="sm" className="h-7 text-xs">Ver Detalhes</Button>
                  </Link>
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>
    </div>
  );
}
