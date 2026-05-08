import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { useI18n } from '@/i18n';
import {
  DollarSign,
  Users,
  CheckCircle2,
  Clock,
  Search,
  Filter,
  ArrowRight,
  TrendingUp,
  CreditCard,
  Download,
} from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { toast } from 'sonner';

export default function CommissionsPage() {
  const { t, formatCurrency, formatDate } = useI18n();
  const qc = useQueryClient();
  const [searchTerm, setSearchTerm] = useState('');

  // 1. Buscar Comissões
  const { data: commissions, isLoading } = useQuery({
    queryKey: ['commissions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('commissions')
        .select(`
          *,
          app_users(full_name),
          service_orders(service_order_number, grand_total, status)
        `)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    }
  });

  // 2. Mutação para Aprovar Pagamento (gera conta a pagar)
  const approveMutation = useMutation({
    mutationFn: async (commission: any) => {
      // Cria a conta a pagar
      const { data: payable, error: payErr } = await supabase.from('payables').insert({
        description: `Comissão OS #${commission.service_orders.service_order_number} - ${commission.app_users.full_name}`,
        amount: commission.amount,
        balance_amount: commission.amount,
        issue_date: new Date().toISOString().split('T')[0],
        due_date: new Date().toISOString().split('T')[0],
        expense_category: 'Comissões',
        status: 'pending',
        origin: 'commission'
      }).select().single();

      if (payErr) throw payErr;

      // Atualiza status da comissão
      const { error: updErr } = await supabase
        .from('commissions')
        .update({ status: 'approved', payable_id: payable.id })
        .eq('id', commission.id);
      
      if (updErr) throw updErr;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['commissions'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      toast.success('Comissão aprovada e enviada para o financeiro!');
    }
  });

  const filtered = commissions?.filter(c => 
    c.app_users?.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.service_orders?.service_order_number.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const stats = {
    pending: commissions?.filter(c => c.status === 'pending').reduce((s, c) => s + Number(c.amount), 0) || 0,
    approved: commissions?.filter(c => c.status === 'approved').reduce((s, c) => s + Number(c.amount), 0) || 0,
    totalCount: commissions?.length || 0
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader 
        title="Gestão de Comissões" 
        description="Controle e aprove os pagamentos de técnicos e vendedores com base no lucro real das OS."
      />

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <KPICard title="Aguardando Aprovação" value={formatCurrency(stats.pending)} icon={Clock} className="border-amber-200" />
        <KPICard title="Aprovado (No Financeiro)" value={formatCurrency(stats.approved)} icon={CreditCard} className="border-blue-200" />
        <KPICard title="Total de Lançamentos" value={String(stats.totalCount)} icon={TrendingUp} />
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-4">
          <CardTitle>Lançamentos de Comissões</CardTitle>
          <div className="flex items-center gap-2">
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Buscar técnico ou OS..."
                className="pl-8 w-[250px]"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
              />
            </div>
            <Button variant="outline" size="icon"><Filter className="h-4 w-4" /></Button>
            <Button variant="outline" size="sm" className="gap-1" onClick={() => {
              const rows = (filtered || []).map((c: any) => ({
                'Técnico/Vendedor': c.app_users?.full_name || '—',
                'OS': c.service_orders?.service_order_number || '—',
                'Valor OS': Number(c.os_grand_total || 0).toFixed(2),
                'Comissão %': c.commission_rate,
                'Valor Comissão': Number(c.commission_amount || 0).toFixed(2),
                'Status': c.status,
                'Data': c.created_at ? new Date(c.created_at).toLocaleDateString('pt-BR') : '',
              }));
              if (!rows.length) return;
              const csv = [Object.keys(rows[0]).join(','), ...rows.map((r: any) => Object.values(r).map((v: any) => `"${String(v ?? '').replace(/"/g,'""')}"`).join(','))].join('\n');
              const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿'+csv], {type:'text/csv;charset=utf-8;'})); a.download = 'comissoes.csv'; a.click();
            }}>
              <Download className="h-3.5 w-3.5" /> Exportar
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Técnico / Vendedor</TableHead>
                <TableHead>OS Ref.</TableHead>
                <TableHead className="text-right hidden sm:table-cell">Valor OS</TableHead>
                <TableHead className="text-right">Comissão</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={6} className="text-center py-8">Carregando comissões...</TableCell></TableRow>
              ) : filtered?.length === 0 ? (
                <TableRow><TableCell colSpan={6} className="text-center py-8 text-muted-foreground">Nenhuma comissão encontrada.</TableCell></TableRow>
              ) : (
                filtered?.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell className="font-medium">{c.app_users?.full_name}</TableCell>
                    <TableCell>
                      <div className="text-sm font-semibold">{c.service_orders?.service_order_number}</div>
                      <div className="text-[10px] text-muted-foreground">{formatDate(c.created_at)}</div>
                    </TableCell>
                    <TableCell className="text-right hidden sm:table-cell">{formatCurrency(c.service_orders?.grand_total || 0)}</TableCell>
                    <TableCell className="text-right font-bold text-emerald-600">
                      {formatCurrency(c.amount)}
                      <span className="block text-[10px] font-normal text-muted-foreground">{c.percentage}% do lucro</span>
                    </TableCell>
                    <TableCell>
                      <Badge variant="outline" className={
                        c.status === 'pending' ? 'bg-amber-50 text-amber-700' :
                        c.status === 'approved' ? 'bg-blue-50 text-blue-700' :
                        'bg-emerald-50 text-emerald-700'
                      }>
                        {c.status === 'pending' ? 'Pendente' : c.status === 'approved' ? 'Aprovado' : 'Pago'}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      {c.status === 'pending' && (
                        <Button 
                          size="sm" 
                          onClick={() => approveMutation.mutate(c)}
                          disabled={approveMutation.isPending}
                          className="bg-emerald-600 hover:bg-emerald-700"
                        >
                          Aprovar <ArrowRight className="h-4 w-4 ml-1" />
                        </Button>
                      )}
                      {c.status === 'approved' && (
                        <div className="flex items-center justify-end text-xs text-blue-600 font-medium">
                          <CheckCircle2 className="h-3 w-3 mr-1" /> No Contas a Pagar
                        </div>
                      )}
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
