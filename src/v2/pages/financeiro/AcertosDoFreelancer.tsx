// Recibos de um freelancer, no Extrato (pedido do dono, 06/10/2026, a partir da pesquisa de apps de
// diárias): fechar o período ao pagar (foto: dias, pagamentos, Pix; recibo nº; dias travados), baixar
// o recibo e reabrir o último — com motivo. As mesmas funções do assistente.
//
// Desde 27/10/2026 (F2 da revisão de 24/10) o recibo sai do Pix que ZERA a conta: o banco propõe o
// Pix (o último que zera) e o dono pode escolher outro entre os candidatos; a conferência mostra a
// conta do papel e, quando não pode fechar, TODAS as travas de uma vez, em frases prontas (sem CPF,
// Pix ainda na fila, adicional sem motivo, falta pagar…). Acerto do modelo antigo (fechado antes de
// pagar) continua na lista com "a pagar".
//
// Reembolsos (F2b dos comprovantes, 11/10/2026): as despesas da empresa que ele pagou, com o
// comprovante (CMP), entram no recibo a favor dele — na lista e na conferência, só quando há, com o
// rótulo de todo lugar: "Reembolso de despesas pagas pelo técnico" (resposta 9 do dono).
import { useEffect, useRef, useState } from 'react';
import { CheckCircle2, Eye, FileDown, Lock, Paperclip, RotateCcw, Send } from 'lucide-react';
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
import { ROTULO_REEMBOLSOS, numeroDoRecibo } from '@/lib/extrato-diarias';
import {
  simularAcerto, useFecharAcerto, useReabrirAcerto, type Acerto, type SimulacaoDoAcerto,
} from '@/hooks/use-diarias';
import { linkDoReciboAssinado, useAnexarReciboAssinado } from '@/hooks/use-documentos-diarias';

const ddmm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
const diasTexto = (n: number) => `${n.toLocaleString('pt-BR', { maximumFractionDigits: 2 })} diária(s)`;

/** "CMP-00124, CMP-00130" — até três códigos; com mais, "e mais N" (o recibo lista todos). */
function codigosDosReembolsos(itens: SimulacaoDoAcerto['reembolsos_itens']): string {
  const codigos = [...new Set(itens.map((r) => r.codigo).filter((c): c is string => !!c))];
  return codigos.length > 3 ? `${codigos.slice(0, 3).join(', ')} e mais ${codigos.length - 3}` : codigos.join(', ');
}

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
  // O papel assinado (F4): um seletor de arquivo só, apontado para o recibo da linha clicada.
  const arquivo = useRef<HTMLInputElement>(null);
  const [anexandoEm, setAnexandoEm] = useState<Acerto | null>(null);
  const anexar = useAnexarReciboAssinado();
  async function aoEscolher(f: File | undefined) {
    const a = anexandoEm;
    setAnexandoEm(null);
    if (!f || !a) return;
    try {
      toast.success((await anexar.mutateAsync({ acertoId: a.id, arquivo: f })).message);
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para anexar o papel assinado.');
    }
  }
  async function verPapel(a: Acerto) {
    try {
      window.open(await linkDoReciboAssinado(a.assinatura_arquivo!), '_blank', 'noopener');
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para abrir o papel assinado.');
    }
  }

  return (
    <Card className="space-y-3 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="min-w-0">
          <p className="font-medium">Recibos</p>
          <p className="text-xs text-muted-foreground">
            O recibo sai no Pix que zera a conta: guarda o papel, numera e trava os dias e os reembolsos até a data. Pague primeiro, aprove o Pix na fila e emita.
          </p>
        </div>
        <Button size="sm" className="gap-1.5" onClick={() => setFechando(true)}>
          <Lock className="h-4 w-4" /> Emitir recibo
        </Button>
      </div>

      {acertos.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nenhum recibo emitido ainda.</p>
      ) : (
        <div className="divide-y rounded-md border">
          {acertos.map((a) => (
            <div key={a.id} className="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1 p-2 text-sm">
              <span className="font-semibold tabular-nums">nº {numeroDoRecibo(a.numero)}</span>
              <span className="tabular-nums">{ddmm(a.de)} a {ddmm(a.ate)}</span>
              <span className="text-muted-foreground">
                {diasTexto(a.dias)}{a.reembolsos > 0 ? ` · ${ROTULO_REEMBOLSOS.toLowerCase()} ${formatCurrency(a.reembolsos)}` : ''} · {a.documento ? 'já recebido' : 'vales'} {formatCurrency(a.pago_no_periodo)}
              </span>
              <span className="font-medium tabular-nums">
                {a.documento ? `Pix ${formatCurrency(a.valor_do_acerto)}${a.pagos_ate ? ` em ${ddmm(a.pagos_ate)}` : ''}` : `a pagar ${formatCurrency(a.valor_do_acerto)}`}
              </span>
              {a.status === 'reaberto' ? (
                <Badge variant="outline" className="text-amber-700 dark:text-amber-400" title={a.motivo_reabertura ?? undefined}>Reaberto</Badge>
              ) : a.documento && !a.assinado_em ? (
                <Badge variant="outline" className="text-muted-foreground">Falta o papel assinado</Badge>
              ) : a.documento && a.assinado_em ? (
                <Badge variant="outline" className="gap-1 text-success"><CheckCircle2 className="h-3 w-3" /> Assinado {formatDate(a.assinado_em)}</Badge>
              ) : a.conferido_em ? (
                <Badge variant="outline" className="gap-1 text-success" title={`Respondeu "${a.conferido_texto ?? ''}"`}>
                  <CheckCircle2 className="h-3 w-3" /> Conferido {formatDate(a.conferido_em)}
                </Badge>
              ) : a.enviado_ao_freelancer_em ? (
                <Badge variant="outline" className="gap-1 text-muted-foreground"><Send className="h-3 w-3" /> Enviado, aguardando o OK</Badge>
              ) : null}
              <AcoesDaLinha
                className="ml-auto"
                rotulo={`recibo nº ${numeroDoRecibo(a.numero)}`}
                rapidas={[
                  { texto: 'Recibo em PDF', icone: FileDown, desabilitada: gerandoPdf, onClick: () => onRecibo(a) },
                  ...(a.assinatura_arquivo ? [{ texto: 'Ver papel assinado', icone: Eye, onClick: () => { void verPapel(a); } }] : []),
                ]}
                menu={[
                  ...(a.documento && a.status === 'fechado'
                    ? [{
                      texto: a.assinado_em ? 'Trocar o papel assinado' : 'Anexar papel assinado', icone: Paperclip,
                      desabilitada: anexar.isPending, onClick: () => { setAnexandoEm(a); arquivo.current?.click(); },
                    }]
                    : []),
                  ...(a.id === ultimoFechado?.id
                    ? [{ texto: 'Reabrir o recibo', icone: RotateCcw, perigo: true, onClick: () => setReabrindo(a) }]
                    : []),
                ]}
              />
            </div>
          ))}
        </div>
      )}
      <input ref={arquivo} type="file" accept="image/*,application/pdf" className="hidden" aria-label="Papel assinado"
             onChange={(e) => { void aoEscolher(e.target.files?.[0]); e.target.value = ''; }} />
      <p className="text-xs text-muted-foreground">
        Imprima o recibo, colha a assinatura com a data escrita à mão e anexe a foto do papel (menu ⋯ da linha). Para mandar o recibo ao {nome.split(' ')[0]} conferir pelo WhatsApp, peça ao assistente: "manda o recibo pro {nome.split(' ')[0]} conferir".
      </p>

      {fechando && (
        <EmitirReciboDialog favorecidoId={favorecidoId} nome={nome} primeiro={!ultimoFechado} onFechar={() => setFechando(false)} />
      )}
      {reabrindo && <ReabrirAcertoDialog acerto={reabrindo} nome={nome} onFechar={() => setReabrindo(null)} />}
    </Card>
  );
}

function EmitirReciboDialog({ favorecidoId, nome, primeiro, onFechar }: {
  favorecidoId: string;
  nome: string;
  /** Primeiro recibo dele: o dono pode dizer de quando começa (os seguintes começam no dia seguinte ao anterior). */
  primeiro: boolean;
  onFechar: () => void;
}) {
  const { formatCurrency } = useI18n();
  const hoje = hojeLocal();
  const [ate, setAte] = useState('');
  const [de, setDe] = useState('');
  const [pixId, setPixId] = useState<string | null>(null);
  const [previa, setPrevia] = useState<SimulacaoDoAcerto | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);
  const fechar = useFecharAcerto();

  // A conferência acompanha cada escolha: o banco diz de novo o que o recibo seria (nada é gravado).
  useEffect(() => {
    let vivo = true;
    if (ate && ate > hoje) { setPrevia(null); setErro('Os serviços não podem ir além de hoje.'); return; }
    setCarregando(true);
    simularAcerto(favorecidoId, ate || null, pixId, primeiro ? de || null : null)
      .then((s) => { if (vivo) { setPrevia(s); setErro(null); } })
      .catch((e: Error) => { if (vivo) { setPrevia(null); setErro(e.message || 'O recibo seria recusado.'); } })
      .finally(() => { if (vivo) setCarregando(false); });
    return () => { vivo = false; };
  }, [favorecidoId, ate, de, pixId, primeiro, hoje]);

  async function confirmar() {
    if (!previa?.pix) return;
    try {
      const r = await fechar.mutateAsync({ favorecidoId, ate: ate || null, pixId: previa.pix.id, de: primeiro ? de || null : null });
      toast.success(r.message);
      onFechar();
    } catch (e) {
      setErro((e as Error).message || 'Não foi possível emitir o recibo.');
    }
  }

  // Os Pix que zeram e os mais recentes: a lista inteira desde o último recibo pode ser longa.
  const candidatos = (previa?.candidatos ?? []).filter((c, i, todos) => c.zera || i >= todos.length - 4 || c.id === previa?.pix?.id);

  return (
    <Dialog open onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Emitir recibo — {nome}</DialogTitle>
          <DialogDescription>
            O recibo quita os serviços até a data no Pix que zera a conta. Os dias até lá ficam travados; o papel sai para ele assinar.
          </DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          {primeiro && (
            <div className="space-y-1.5">
              <Label htmlFor="recibo-de">Serviços desde</Label>
              <Input id="recibo-de" type="date" value={de} max={hoje} onChange={(e) => setDe(e.target.value)} />
            </div>
          )}
          <div className="space-y-1.5">
            <Label htmlFor="recibo-ate">Serviços até</Label>
            <Input id="recibo-ate" type="date" value={ate} max={hoje} onChange={(e) => setAte(e.target.value)} />
          </div>
        </div>
        <p className="text-xs text-muted-foreground">
          Em branco: {primeiro ? 'desde o início da conta dele e ' : ''}até o dia do Pix.
        </p>

        {candidatos.length > 0 && (
          <fieldset className="space-y-1.5">
            <legend className="text-sm font-medium">Pix que quita</legend>
            <div className="divide-y rounded-md border">
              {candidatos.map((c) => {
                const escolhido = c.id === previa?.pix?.id;
                return (
                  <button key={c.id} type="button" aria-pressed={escolhido} onClick={() => setPixId(c.id)}
                    className={`flex w-full min-w-0 items-center gap-2 p-2 text-left text-sm ${escolhido ? 'bg-muted font-medium' : ''}`}>
                    <span className="tabular-nums">{ddmm(c.data)}</span>
                    <span className="tabular-nums">{formatCurrency(c.valor)}</span>
                    <span className="min-w-0 flex-1 truncate text-xs text-muted-foreground">{c.aguardando ? 'na fila' : c.conta ?? ''}</span>
                    <span className="text-xs tabular-nums">
                      {c.zera ? 'zera a conta' : c.saldo_final > 0 ? `falta ${formatCurrency(c.saldo_final)}` : `sobra ${formatCurrency(-c.saldo_final)}`}
                    </span>
                  </button>
                );
              })}
            </div>
          </fieldset>
        )}

        {carregando ? (
          <p className="text-sm text-muted-foreground">Conferindo…</p>
        ) : previa?.pix ? (
          <dl className="grid grid-cols-2 gap-x-3 gap-y-1 rounded-md border p-3 text-sm">
            <dt className="text-muted-foreground">Serviços</dt><dd className="text-right tabular-nums">{ddmm(previa.de)} a {ddmm(previa.ate)}</dd>
            {previa.saldo_anterior !== 0 && (<><dt className="text-muted-foreground">{previa.saldo_anterior > 0 ? 'Saldo de antes' : '(−) Adiantamento de antes'}</dt><dd className="text-right tabular-nums">{formatCurrency(Math.abs(previa.saldo_anterior))}</dd></>)}
            <dt className="text-muted-foreground">Trabalhado ({diasTexto(previa.dias)})</dt><dd className="text-right tabular-nums">{formatCurrency(previa.trabalhado)}</dd>
            {previa.reembolsos > 0 && (
              <>
                <dt className="min-w-0 break-words text-muted-foreground">
                  {/* sem nenhum código (origem_codigo pode ser nulo), nada de "()" vazio */}
                  (+) {ROTULO_REEMBOLSOS}{codigosDosReembolsos(previa.reembolsos_itens) ? ` (${codigosDosReembolsos(previa.reembolsos_itens)})` : ''}
                </dt>
                <dd className="text-right tabular-nums">{formatCurrency(previa.reembolsos)}</dd>
              </>
            )}
            <dt className="text-muted-foreground">(−) Já recebido</dt><dd className="text-right tabular-nums">{formatCurrency(previa.pago_no_periodo)}</dd>
            <dt className="font-semibold">Pix de {ddmm(previa.pix.data)}</dt><dd className="text-right font-semibold tabular-nums">{formatCurrency(previa.pix.valor)}</dd>
          </dl>
        ) : null}

        {previa && previa.travas.length > 0 && (
          <div role="alert" className="space-y-1 rounded-md border border-amber-300 p-3 text-sm dark:border-amber-700">
            <p className="font-medium">Antes do recibo:</p>
            <ul className="list-disc space-y-0.5 pl-5">
              {previa.travas.map((t) => <li key={t}>{t}</li>)}
            </ul>
          </div>
        )}
        {erro && <p role="alert" className="text-sm text-destructive">{erro}</p>}
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onFechar}>Cancelar</Button>
          <Button type="button" onClick={confirmar} disabled={!previa?.ok || !previa.pix || carregando || fechar.isPending}>
            {fechar.isPending ? 'Emitindo…' : 'Emitir recibo'}
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
      toast.error((e as Error).message || 'Não foi possível reabrir o recibo.');
    }
  }
  return (
    <Dialog open onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Reabrir o recibo nº {numeroDoRecibo(acerto.numero)} — {nome}</DialogTitle>
          <DialogDescription>
            Os dias e os reembolsos de {ddmm(acerto.de)} a {ddmm(acerto.ate)} voltam a poder ser corrigidos (o reembolso, cancelando o comprovante). Este recibo deixa de valer: emita outro depois de corrigir.
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
