/**
 * Prospecção › Revisões preventivas (refeita em 07/10/2026).
 *
 * A versão antiga escolhia a "última revisão" pelo created_at da OS, não via OS mais nova nem o
 * opt-out, e mandava o texto da IA pelo whatsapp-send-text cru — sem horário, sem modo de teste,
 * sem registro em ai_comms_log. Agora o envio é o mesmo do resto do sistema: o assistente prepara o
 * lembrete do PLANO (pendência com o texto exato) e nada sai sem o "Confirmar" do dono. Embarcação
 * sem plano não recebe mensagem daqui: a ação é criar o plano, e o lembrete passa a vir dele.
 */
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Anchor, Loader2, MessageCircle, Plus } from 'lucide-react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { useAlvosDeRevisao } from '@/hooks/use-planos-manutencao';
import { CLASSE_DA_SITUACAO, ROTULO_DA_SITUACAO, dataBR, prazoPorExtenso } from '@/lib/planos-manutencao';
import { PedirLembreteDialog, type AlvoDoLembrete } from '@/components/agenda/PlanoDialogs';

const moeda = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

export function RevisoesPreventivas() {
  const navigate = useNavigate();
  const { planos, semPlano, isLoading, erroPlanos, erroOrdens } = useAlvosDeRevisao();
  const [lembrete, setLembrete] = useState<AlvoDoLembrete | null>(null);

  if (isLoading) {
    return <p className="text-muted-foreground flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Analisando base de dados...</p>;
  }

  return (
    <div className="space-y-6">
      <section className="space-y-3">
        <h3 className="text-sm font-semibold">Planos vencendo ou vencidos ({planos.length})</h3>
        {erroPlanos ? (
          <p className="text-sm text-destructive">Não deu para ler os planos de manutenção: {erroPlanos.message}</p>
        ) : planos.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhum plano vence nos próximos 30 dias.</p>
        ) : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {planos.map((r) => {
              const embarcacao = r.vessel_name ?? 'Embarcação';
              const bloqueado = !!r.opt_out || !r.client_phone;
              return (
                <Card key={r.plan_id} className="hover:border-primary/50 transition-colors">
                  <CardHeader className="pb-3">
                    <span className={cn('w-fit rounded px-1.5 py-0.5 text-xs font-medium', CLASSE_DA_SITUACAO[r.situacao])}>
                      {ROTULO_DA_SITUACAO[r.situacao]}
                    </span>
                    <CardTitle className="text-lg mt-2 break-words">{embarcacao}</CardTitle>
                    <CardDescription>{r.name}{r.client_name ? ` · ${r.client_name}` : ''}</CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-3">
                    <p className="text-sm text-muted-foreground">
                      {dataBR(r.next_due_on)} · {prazoPorExtenso(r.dias_para_vencer)}
                      {r.estimated_value != null ? ` · ${moeda(Number(r.estimated_value))}` : ''}
                    </p>
                    {r.opt_out && <p className="text-xs text-destructive">Pediu para não receber WhatsApp.</p>}
                    {!r.opt_out && !r.client_phone && <p className="text-xs text-destructive">Cliente sem telefone no cadastro.</p>}
                    <Button className="w-full" disabled={bloqueado}
                      onClick={() => setLembrete({
                        planId: r.plan_id, rotulo: `${r.name} — ${embarcacao}`, plano: r.name, embarcacao,
                        cliente: r.client_name, vesselId: r.vessel_id, optOut: r.opt_out, semTelefone: !r.client_phone,
                      })}>
                      <MessageCircle className="h-4 w-4 mr-2" /> Preparar lembrete (com seu sim)
                    </Button>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
      </section>

      <section className="space-y-3">
        <h3 className="text-sm font-semibold">Sem plano, último serviço há 6+ meses ({semPlano.length})</h3>
        {erroOrdens ? (
          <p className="text-sm text-destructive">Não deu para ler o histórico de OS: {erroOrdens.message}</p>
        ) : semPlano.length === 0 ? (
          <div className="py-8 text-center bg-card rounded-xl border border-dashed">
            <p className="text-muted-foreground">Nenhuma embarcação parada sem plano.</p>
          </div>
        ) : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {semPlano.map((a) => (
              <Card key={a.vesselId} className="hover:border-primary/50 transition-colors">
                <CardHeader className="pb-3">
                  <Badge variant="outline" className="w-fit">Sem plano</Badge>
                  <CardTitle className="text-lg mt-2 break-words">{a.embarcacao}</CardTitle>
                  <CardDescription>Cliente: {a.cliente ?? '—'}</CardDescription>
                </CardHeader>
                <CardContent className="space-y-3">
                  <p className="text-sm text-muted-foreground">
                    Último serviço: {dataBR(a.ultimoServico)} ({a.meses} meses)
                  </p>
                  <div className="flex flex-wrap gap-2">
                    <Button className="flex-1" variant="outline" onClick={() => navigate(`/v2/vessels/${a.vesselId}?tab=maintenance`)}>
                      <Plus className="h-4 w-4 mr-2" /> Criar plano
                    </Button>
                    <Button variant="ghost" onClick={() => navigate(`/v2/vessels/${a.vesselId}`)}>
                      <Anchor className="h-4 w-4 mr-2" /> Abrir
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </section>

      <PedirLembreteDialog alvo={lembrete} onOpenChange={(v) => { if (!v) setLembrete(null); }} />
    </div>
  );
}
