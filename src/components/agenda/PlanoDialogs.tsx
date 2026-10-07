/**
 * Diálogos das ações de um plano de manutenção (07/10/2026): "Serviço feito", "Adiar" e "Pedir
 * lembrete agora". Ficam num arquivo só porque três telas usam os mesmos: o painel da embarcação,
 * a aba Revisões da Agenda e o cartão da tarefa R14 ("Propor revisão").
 */
import { useEffect, useState } from 'react';
import { Loader2, MessageCircle } from 'lucide-react';
import { toast } from 'sonner';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { AIConfirmCard } from '@/components/ai/AIConfirmCard';
import {
  useAdiarPlano, useDecidirLembrete, usePedirLembreteAgora, useRegistrarServico, type PropostaDeLembrete,
} from '@/hooks/use-planos-manutencao';
import { dataBR, hojeEmBrasilia, somarDias } from '@/lib/planos-manutencao';

export interface AlvoDoPlano {
  planId: string;
  /** "Revisão de motor — Mar Azul": aparece no título do diálogo. */
  rotulo: string;
}

const msg = (e: unknown, padrao: string) => (e as Error)?.message || padrao;

/** "Serviço feito": a data é a de Brasília por padrão e pode ser corrigida (serviço da semana passada). */
export function RegistrarServicoDialog({
  alvo, onOpenChange,
}: { alvo: AlvoDoPlano | null; onOpenChange: (aberto: boolean) => void }) {
  const registrar = useRegistrarServico();
  const [dia, setDia] = useState(hojeEmBrasilia());
  useEffect(() => { if (alvo) setDia(hojeEmBrasilia()); }, [alvo]);
  const hoje = hojeEmBrasilia();

  const salvar = () => {
    if (!alvo) return;
    registrar.mutate({ planId: alvo.planId, dia }, {
      onSuccess: () => {
        toast.success(`Serviço registrado em ${dataBR(dia)} — o ciclo recomeça e a tarefa de revisão se fecha sozinha.`);
        onOpenChange(false);
      },
      onError: (e) => toast.error(msg(e, 'Não deu para registrar o serviço.')),
    });
  };

  return (
    <Dialog open={!!alvo} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm" onClick={(e) => e.stopPropagation()}>
        <DialogHeader>
          <DialogTitle>Serviço feito</DialogTitle>
          <DialogDescription>{alvo?.rotulo}</DialogDescription>
        </DialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="dia-servico-plano">Data do serviço</Label>
          <Input id="dia-servico-plano" type="date" value={dia} max={hoje} onChange={(e) => setDia(e.target.value)} />
          <p className="text-xs text-muted-foreground">
            OS concluída da embarcação já registra sozinha; use isto para serviço feito fora do sistema.
          </p>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={registrar.isPending}>Voltar</Button>
          <Button onClick={salvar} disabled={!dia || dia > hoje || registrar.isPending}>
            {registrar.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Registrar serviço
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

const OPCOES_DE_ADIAMENTO = [
  { texto: '1 semana', dias: 7 },
  { texto: '1 mês', dias: 30 },
  { texto: '3 meses', dias: 90 },
];

/** "Adiar": o cliente pediu para depois; o plano sai da janela até a data e nenhum lembrete sai antes. */
export function AdiarPlanoDialog({
  alvo, onOpenChange,
}: { alvo: AlvoDoPlano | null; onOpenChange: (aberto: boolean) => void }) {
  const adiar = useAdiarPlano();
  const hoje = hojeEmBrasilia();
  const [ate, setAte] = useState(somarDias(hoje, 30));
  const [motivo, setMotivo] = useState('');
  useEffect(() => { if (alvo) { setAte(somarDias(hojeEmBrasilia(), 30)); setMotivo(''); } }, [alvo]);

  const salvar = () => {
    if (!alvo) return;
    adiar.mutate({ planId: alvo.planId, ate, motivo }, {
      onSuccess: () => {
        toast.success(`Adiado até ${dataBR(ate)}.`);
        onOpenChange(false);
      },
      onError: (e) => toast.error(msg(e, 'Não deu para adiar.')),
    });
  };

  return (
    <Dialog open={!!alvo} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm" onClick={(e) => e.stopPropagation()}>
        <DialogHeader>
          <DialogTitle>Adiar revisão</DialogTitle>
          <DialogDescription>{alvo?.rotulo}</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="flex flex-wrap gap-1.5">
            {OPCOES_DE_ADIAMENTO.map((o) => (
              <Button key={o.dias} type="button" size="sm" variant={ate === somarDias(hoje, o.dias) ? 'default' : 'outline'}
                onClick={() => setAte(somarDias(hoje, o.dias))}>
                {o.texto}
              </Button>
            ))}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="adiar-plano-ate">Até</Label>
            <Input id="adiar-plano-ate" type="date" value={ate} min={somarDias(hoje, 1)} onChange={(e) => setAte(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="adiar-plano-motivo">Motivo (opcional)</Label>
            <Input id="adiar-plano-motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)}
              placeholder="cliente viajando, barco fora d'água…" />
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={adiar.isPending}>Voltar</Button>
          <Button onClick={salvar} disabled={!ate || ate <= hoje || adiar.isPending}>
            {adiar.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Adiar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Id do plano a partir da chave da R14 ("r14:plan:<id>:<ciclo>") — mesma regra do keyOf do motor. */
export function planoDaChaveR14(chave: string | null | undefined): string | null {
  if (!chave?.startsWith('r14:plan:')) return null;
  return chave.split(':')[2] || null;
}

const CLASSE_BOTAO_DO_CARTAO = 'h-6 px-2 text-[11px] border-primary/40 text-primary hover:bg-primary/10';

/**
 * Os dois botões que resolvem a tarefa "Propor revisão" (R14) direto no cartão da Agenda: o
 * serviço foi feito, ou o cliente pediu para depois. Qualquer um muda o ciclo do plano e o motor
 * fecha a tarefa sozinho na próxima passada.
 */
export function AcoesDaTarefaDeRevisao({ planId, rotulo }: { planId: string; rotulo: string }) {
  const [servico, setServico] = useState<AlvoDoPlano | null>(null);
  const [adiar, setAdiar] = useState<AlvoDoPlano | null>(null);
  const alvo: AlvoDoPlano = { planId, rotulo };
  return (
    <>
      <Button size="sm" variant="outline" className={CLASSE_BOTAO_DO_CARTAO}
        onClick={(e) => { e.stopPropagation(); setServico(alvo); }}>
        Serviço feito
      </Button>
      <Button size="sm" variant="outline" className={CLASSE_BOTAO_DO_CARTAO}
        onClick={(e) => { e.stopPropagation(); setAdiar(alvo); }}>
        Adiar
      </Button>
      <span onClick={(e) => e.stopPropagation()}>
        <RegistrarServicoDialog alvo={servico} onOpenChange={(v) => { if (!v) setServico(null); }} />
        <AdiarPlanoDialog alvo={adiar} onOpenChange={(v) => { if (!v) setAdiar(null); }} />
      </span>
    </>
  );
}

export interface AlvoDoLembrete extends AlvoDoPlano {
  plano: string;
  embarcacao: string;
  cliente: string | null;
  vesselId: string;
  optOut?: boolean | null;
  semTelefone?: boolean;
}

/**
 * "Pedir lembrete agora". Decisão do dono (07/10/2026): lembrete ao cliente sai SEMPRE com o
 * "sim" dele. O diálogo pede ao assistente que prepare a mensagem (pendência com o texto exato) e
 * mostra o cartão de confirmação: nada sai antes do "Confirmar".
 */
export function PedirLembreteDialog({
  alvo, onOpenChange,
}: { alvo: AlvoDoLembrete | null; onOpenChange: (aberto: boolean) => void }) {
  const pedir = usePedirLembreteAgora();
  const decidir = useDecidirLembrete();
  const [proposta, setProposta] = useState<PropostaDeLembrete | null>(null);
  const [resposta, setResposta] = useState('');
  const [status, setStatus] = useState<'pending' | 'confirmed' | 'cancelled' | 'executed'>('pending');

  useEffect(() => {
    if (alvo) { setProposta(null); setResposta(''); setStatus('pending'); }
  }, [alvo]);

  const bloqueio = alvo?.optOut
    ? 'Este cliente pediu para não receber WhatsApp (PARAR). Combine por telefone.'
    : alvo?.semTelefone ? 'O cliente não tem WhatsApp nem telefone no cadastro.' : null;

  const preparar = () => {
    if (!alvo) return;
    pedir.mutate(
      { planId: alvo.planId, plano: alvo.plano, embarcacao: alvo.embarcacao, cliente: alvo.cliente, vesselId: alvo.vesselId },
      {
        onSuccess: (r) => { setProposta(r.proposta); setResposta(r.texto); },
        onError: (e) => toast.error(msg(e, 'O assistente não conseguiu preparar o lembrete.')),
      },
    );
  };

  const decide = (decisao: 'approve' | 'reject', nota?: string) => {
    if (!proposta) return;
    setStatus(decisao === 'approve' ? 'confirmed' : 'cancelled');
    decidir.mutate({ id: proposta.pending_action_id, decisao, nota }, {
      onSuccess: (texto) => {
        if (decisao === 'approve') {
          setStatus('executed');
          toast.success(texto || 'Lembrete enviado para a fila do WhatsApp.');
        } else {
          toast.info('Lembrete descartado — nada foi enviado.');
        }
      },
      onError: (e) => { setStatus('pending'); toast.error(msg(e, 'Não deu para concluir.')); },
    });
  };

  return (
    <Dialog open={!!alvo} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <MessageCircle className="h-5 w-5 text-primary" /> Lembrete de revisão
          </DialogTitle>
          <DialogDescription>{alvo?.rotulo}</DialogDescription>
        </DialogHeader>

        {bloqueio ? (
          <p className="rounded-md border border-destructive/40 bg-destructive/10 p-2.5 text-sm text-destructive">{bloqueio}</p>
        ) : !proposta && !resposta ? (
          <p className="text-sm text-muted-foreground">
            O assistente monta a mensagem certa para o momento do plano (com as datas e a faixa de valor) e
            mostra aqui o texto exato. Nada vai ao cliente antes de você confirmar; fora do horário comercial,
            a mensagem espera a próxima janela (terça a quinta, 9h–11h ou 14h–17h).
          </p>
        ) : proposta ? (
          <AIConfirmCard
            proposal={proposta}
            status={status}
            disabled={decidir.isPending}
            onConfirm={(nota) => decide('approve', nota)}
            onCancel={(nota) => decide('reject', nota)}
          />
        ) : (
          // Sem pendência: o assistente explicou por quê (opt-out, sem telefone, já enviado neste ciclo…).
          <p className="whitespace-pre-wrap rounded-md border bg-muted/40 p-2.5 text-sm">{resposta}</p>
        )}

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Fechar</Button>
          {!bloqueio && !proposta && (
            <Button onClick={preparar} disabled={pedir.isPending}>
              {pedir.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              {resposta ? 'Tentar de novo' : 'Preparar lembrete'}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
