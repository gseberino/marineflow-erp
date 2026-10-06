// Acertos de um freelancer, no Extrato (pedido do dono, 06/10/2026, a partir da pesquisa de apps de
// diárias): fechar o período ao pagar (foto: dias, vales, a pagar; recibo nº; dias travados), baixar
// o recibo e reabrir o último — com motivo. As mesmas funções do assistente.
//
// Fechar tem conferência antes, como o "sim" do WhatsApp: a função do banco simula e a tela mostra.
import { useEffect, useState } from 'react';
import { CheckCircle2, FileDown, Lock, RotateCcw, Send } from 'lucide-react';
import { toast } from 'sonner';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { useI18n } from '@/i18n';
import { hojeLocal } from '@/lib/dia';
import { numeroDoRecibo } from '@/lib/extrato-diarias';
import {
  simularAcerto, useFecharAcerto, useReabrirAcerto, type Acerto, type SimulacaoDoAcerto,
} from '@/hooks/use-diarias';

const ddmm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
const diasTexto = (n: number) => `${n.toLocaleString('pt-BR', { maximumFractionDigits: 2 })} diária(s)`;

export function AcertosDoFreelancer({ favorecidoId, nome, acertos, gerandoPdf, onRecibo }: {
  favorecidoId: string;
  nome: string;
  acertos: Acerto[];
  gerandoPdf: boolean;
  onRecibo: (a: Acerto) => void;
}) {
  const { formatCurrency, formatDate } = useI18n();
  const [fechando, setFechando] = useState(false);
  const [reabrindo, setReabrindo] = useState<Acerto | null>(null);
  const ultimoFechado = acertos.find((a) => a.status === 'fechado');

  return (
    <Card className="space-y-3 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="min-w-0">
          <p className="font-medium">Acertos</p>
          <p className="text-xs text-muted-foreground">
            Fechar o acerto guarda o período, gera o recibo numerado e trava os dias até a data. Os pagamentos do período são os vales.
          </p>
        </div>
        <Button size="sm" className="gap-1.5" onClick={() => setFechando(true)}>
          <Lock className="h-4 w-4" /> Fechar acerto
        </Button>
      </div>

      {acertos.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nenhum acerto fechado ainda.</p>
      ) : (
        <div className="divide-y rounded-md border">
          {acertos.map((a) => (
            <div key={a.id} className="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1 p-2 text-sm">
              <span className="font-semibold tabular-nums">nº {numeroDoRecibo(a.numero)}</span>
              <span className="tabular-nums">{ddmm(a.de)} a {ddmm(a.ate)}</span>
              <span className="text-muted-foreground">{diasTexto(a.dias)} · vales {formatCurrency(a.pago_no_periodo)}</span>
              <span className="font-medium tabular-nums">a pagar {formatCurrency(a.valor_do_acerto)}</span>
              {a.status === 'reaberto' ? (
                <Badge variant="outline" className="text-amber-700 dark:text-amber-400" title={a.motivo_reabertura ?? undefined}>Reaberto</Badge>
              ) : a.conferido_em ? (
                <Badge variant="outline" className="gap-1 text-success" title={`Respondeu "${a.conferido_texto ?? ''}"`}>
                  <CheckCircle2 className="h-3 w-3" /> Conferido {formatDate(a.conferido_em)}
                </Badge>
              ) : a.enviado_ao_freelancer_em ? (
                <Badge variant="outline" className="gap-1 text-muted-foreground"><Send className="h-3 w-3" /> Enviado, aguardando o OK</Badge>
              ) : null}
              <AcoesDaLinha
                className="ml-auto"
                rotulo={`acerto nº ${numeroDoRecibo(a.numero)}`}
                rapidas={[{ texto: 'Recibo em PDF', icone: FileDown, desabilitada: gerandoPdf, onClick: () => onRecibo(a) }]}
                menu={a.id === ultimoFechado?.id
                  ? [{ texto: 'Reabrir o acerto', icone: RotateCcw, perigo: true, onClick: () => setReabrindo(a) }]
                  : []}
              />
            </div>
          ))}
        </div>
      )}
      <p className="text-xs text-muted-foreground">
        Para mandar o recibo ao {nome.split(' ')[0]} conferir pelo WhatsApp, peça ao assistente: "manda o recibo pro {nome.split(' ')[0]} conferir".
      </p>

      {fechando && <FecharAcertoDialog favorecidoId={favorecidoId} nome={nome} onFechar={() => setFechando(false)} />}
      {reabrindo && <ReabrirAcertoDialog acerto={reabrindo} nome={nome} onFechar={() => setReabrindo(null)} />}
    </Card>
  );
}

function FecharAcertoDialog({ favorecidoId, nome, onFechar }: { favorecidoId: string; nome: string; onFechar: () => void }) {
  const { formatCurrency } = useI18n();
  const hoje = hojeLocal();
  const [ate, setAte] = useState(hoje);
  const [previa, setPrevia] = useState<SimulacaoDoAcerto | null>(null);
  const [recusa, setRecusa] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);
  const fechar = useFecharAcerto();

  // A conferência acompanha a data: cada data nova pergunta de novo ao banco o que o acerto seria.
  useEffect(() => {
    let vivo = true;
    if (!ate || ate > hoje) { setPrevia(null); setRecusa(ate > hoje ? 'O acerto não pode ir além de hoje.' : null); return; }
    setCarregando(true);
    simularAcerto(favorecidoId, ate)
      .then((s) => { if (vivo) { setPrevia(s); setRecusa(null); } })
      .catch((e: Error) => { if (vivo) { setPrevia(null); setRecusa(e.message || 'O acerto seria recusado.'); } })
      .finally(() => { if (vivo) setCarregando(false); });
    return () => { vivo = false; };
  }, [favorecidoId, ate, hoje]);

  async function confirmar() {
    try {
      const r = await fechar.mutateAsync({ favorecidoId, ate });
      toast.success(r.message);
      onFechar();
    } catch (e) {
      setRecusa((e as Error).message || 'Não foi possível fechar o acerto.');
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Fechar acerto — {nome}</DialogTitle>
          <DialogDescription>Do dia seguinte ao último acerto até a data escolhida. Os dias até lá ficam travados.</DialogDescription>
        </DialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="acerto-ate">Fechar até</Label>
          <Input id="acerto-ate" type="date" value={ate} max={hoje} onChange={(e) => setAte(e.target.value)} />
        </div>
        {carregando ? (
          <p className="text-sm text-muted-foreground">Conferindo…</p>
        ) : previa ? (
          <dl className="grid grid-cols-2 gap-x-3 gap-y-1 rounded-md border p-3 text-sm">
            <dt className="text-muted-foreground">Período</dt><dd className="text-right tabular-nums">{ddmm(previa.de)} a {ddmm(previa.ate)}</dd>
            {previa.saldo_anterior !== 0 && (<><dt className="text-muted-foreground">Saldo anterior</dt><dd className="text-right tabular-nums">{formatCurrency(previa.saldo_anterior)}</dd></>)}
            <dt className="text-muted-foreground">Trabalhado ({diasTexto(previa.dias)})</dt><dd className="text-right tabular-nums">{formatCurrency(previa.trabalhado)}</dd>
            <dt className="text-muted-foreground">(−) Vales já pagos</dt><dd className="text-right tabular-nums">{formatCurrency(previa.pago_no_periodo)}</dd>
            <dt className="font-semibold">A pagar neste acerto</dt><dd className="text-right font-semibold tabular-nums">{formatCurrency(previa.valor_do_acerto)}</dd>
            {previa.pago_aguardando_banco > 0 && (
              <dd className="col-span-2 text-xs text-amber-700 dark:text-amber-400">
                {formatCurrency(previa.pago_aguardando_banco)} dos vales são Pix lançados à mão que o banco ainda não confirmou.
              </dd>
            )}
          </dl>
        ) : null}
        {recusa && <p role="alert" className="text-sm text-destructive">{recusa}</p>}
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onFechar}>Cancelar</Button>
          <Button type="button" onClick={confirmar} disabled={!previa || carregando || fechar.isPending}>
            {fechar.isPending ? 'Fechando…' : 'Fechar acerto'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ReabrirAcertoDialog({ acerto, nome, onFechar }: { acerto: Acerto; nome: string; onFechar: () => void }) {
  const [motivo, setMotivo] = useState('');
  const reabrir = useReabrirAcerto();
  async function confirmar() {
    try {
      const r = await reabrir.mutateAsync({ acertoId: acerto.id, motivo: motivo.trim() });
      toast.success(r.message);
      onFechar();
    } catch (e) {
      toast.error((e as Error).message || 'Não foi possível reabrir o acerto.');
    }
  }
  return (
    <Dialog open onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Reabrir o acerto nº {numeroDoRecibo(acerto.numero)} — {nome}</DialogTitle>
          <DialogDescription>
            Os dias de {ddmm(acerto.de)} a {ddmm(acerto.ate)} voltam a poder ser corrigidos. O recibo deste acerto deixa de valer: feche de novo depois de corrigir.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="acerto-motivo">Motivo (fica registrado)</Label>
          <Textarea id="acerto-motivo" rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Ex.: dia 24 lançado como inteiro, foi meio" />
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onFechar}>Cancelar</Button>
          <Button type="button" variant="destructive" onClick={confirmar} disabled={!motivo.trim() || reabrir.isPending}>
            {reabrir.isPending ? 'Reabrindo…' : 'Reabrir'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
