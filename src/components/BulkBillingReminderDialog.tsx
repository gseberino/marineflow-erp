// "Cobrar em lote" (Contas a Receber) — dono, 26/11/2026: "1. A", o lote ganha a mesma conferência da ficha, com prévia.
//
// Antes (MF-AUD-050): uma mensagem POR CONTA, com modelo, a número sem conferência, sem piso, sem olhar a entrada
// esperando no Extrato, sem opt-out, sem horário, sem registrar nada, e com agendamento/repetição que mandava sozinho
// depois. Nunca foi usado (levantamento de 24/11/2026: 0 envios, 0 agendados).
//
// Agora (montarLoteDaTela, src/lib/cobrar-em-lote.ts): UMA mensagem por cliente — a cobrança do cliente inteiro, o mesmo
// texto do "cobra o Fulano" do assistente —, as travas da ficha em cada um, quem fica de fora com o motivo, uma mensagem
// por número, no máximo 20. Cada mensagem pode ser lida antes. No envio, cliente a cliente, enviarCobrancaDoCliente relê
// o cadastro e as contas, confere as travas de novo e registra a cobrança do dia; recusa ou falha aparece na lista e
// NÃO se repete sozinha (falha incerta não reenvia). Sem agendamento: a conferência vale para a hora do envio.
import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import {
  AlertTriangle, CheckCircle2, ChevronDown, ChevronUp, Info, Loader2, Send, XCircle,
} from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAppSettings } from '@/hooks/use-app-settings';
import {
  enviarCobrancaDoCliente, horaDoCobrarJuntas, invalidarDepoisDoLote, lerCobradosHoje,
} from '@/hooks/use-cobrar-juntas';
import {
  MAX_CLIENTES_DO_LOTE, intervaloDoLote, montarLoteDaTela, type ClienteParaOLote, type ContaParaOLote, type FiltroDoLote,
  type ItemDoLoteDaTela, type LoteDaTela,
} from '@/lib/cobrar-em-lote';
import {
  HORA_FIM_COBRANCA, HORA_INICIO_COBRANCA, hojeLocal,
} from '../../supabase/functions/_shared/receivables/cobrar-juntas';
import { lerDinheiroEsperando } from '../../supabase/functions/_shared/receivables/dinheiro-esperando';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  /** 'overdue' (padrão): clientes com conta vencida. 'all': todo cliente com saldo. */
  initialFilter?: 'overdue' | 'all';
}

type Situacao =
  | { fase: 'fila' }
  | { fase: 'enviando' }
  | { fase: 'enviado'; aviso?: string | null }
  | { fase: 'ja-saiu' }
  | { fase: 'teste' }
  | { fase: 'recusado'; motivo: string }
  | { fase: 'parado' };

const CHAVE_DO_LOTE = ['receivables', 'cobrar-em-lote'];
const brl = (v: number) => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const esperar = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** Tudo que o lote precisa, numa leitura (ao abrir). Leitura que falha = nada sai (a tela mostra o erro). */
async function lerOLote(): Promise<{
  contas: ContaParaOLote[];
  clientes: ClienteParaOLote[];
  pix: Map<string, Array<{ valor: number; data: string | null }>>;
  cobradosHoje: Map<string, string>;
}> {
  // Em páginas: o servidor corta em 1.000 linhas sem avisar, e a conta cortada faria a mensagem sair incompleta (e o envio
  // recusaria sempre, porque a releitura do cliente acha a conta que faltou).
  const contas: ContaParaOLote[] = [];
  for (let de = 0; de < 20_000; de += 1000) {
    const { data: linhas, error } = await supabase.from('receivables')
      .select('id, client_id, description, due_date, status, amount, paid_amount, balance_amount, service_order_id, service_orders!receivables_service_order_id_fkey(service_order_number)')
      .not('status', 'in', '(paid,cancelled)')
      .order('due_date', { ascending: true })
      .order('id', { ascending: true })
      .range(de, de + 999);
    if (error) throw new Error(`Não consegui ler as contas em aberto: ${error.message}`);
    const lote = (linhas ?? []) as unknown as Array<ContaParaOLote & { service_orders?: { service_order_number?: string | null } | null }>;
    contas.push(...lote.map(({ service_orders, ...c }) => ({ ...c, numero_os: service_orders?.service_order_number ?? null })));
    if (lote.length < 1000) break;
  }
  const ids = [...new Set(contas.map((c) => c.client_id).filter((x): x is string => !!x))];
  if (!ids.length) return { contas, clientes: [], pix: new Map(), cobradosHoje: new Map() };
  // A coluna generico é pedida pelo nome: sem ela a leitura falha e nada sai (falha fechada, como a ficha). Em blocos: a
  // lista de códigos vai na URL do pedido.
  const cli: ClienteParaOLote[] = [];
  for (let i = 0; i < ids.length; i += 150) {
    const { data, error: eCli } = await supabase.from('clients')
      .select('id, name, generico, opt_out_whatsapp, whatsapp, phone').in('id', ids.slice(i, i + 150));
    if (eCli) throw new Error(`Não consegui ler o cadastro dos clientes: ${eCli.message}`);
    cli.push(...((data ?? []) as ClienteParaOLote[]));
  }
  const [esperando, cobradosHoje] = await Promise.all([lerDinheiroEsperando(supabase), lerCobradosHoje(ids)]);
  const pix = new Map<string, Array<{ valor: number; data: string | null }>>();
  for (const e of esperando) {
    if (!e.clienteId) continue;
    const lista = pix.get(e.clienteId) ?? [];
    lista.push({ valor: e.valor, data: e.data });
    pix.set(e.clienteId, lista);
  }
  return { contas, clientes: cli, pix, cobradosHoje };
}

/** Já recebeu cobrança hoje, conferido na hora do envio (outra aba ou o assistente pode ter cobrado depois da leitura). */
async function cobradoAgora(clienteId: string): Promise<string | null> {
  try {
    const ultima = (await lerCobradosHoje([clienteId])).get(clienteId);
    if (!ultima) return null;
    const hora = new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' })
      .format(new Date(ultima)).replace(':', 'h');
    return `Já recebeu cobrança hoje (às ${hora}), depois que a lista foi aberta: não mandei outra.`;
  } catch (e) {
    return `Não consegui conferir se já recebeu cobrança hoje (${(e as Error).message}): não mandei.`;
  }
}

export function BulkBillingReminderDialog({ open, onOpenChange, initialFilter = 'overdue' }: Props) {
  const qc = useQueryClient();
  const config = useAppSettings();
  const settings = config.data;
  const [filtro, setFiltro] = useState<FiltroDoLote>(initialFilter === 'all' ? 'todas' : 'vencidas');
  const [desmarcados, setDesmarcados] = useState<Set<string>>(new Set());
  const [aberta, setAberta] = useState<string | null>(null);
  const [confirmando, setConfirmando] = useState(false);
  const [rodando, setRodando] = useState(false);
  const [situacao, setSituacao] = useState<Record<string, Situacao>>({});
  /** O lote como estava quando o envio começou: a releitura depois do envio não apaga o resultado de cada um. */
  const [congelado, setCongelado] = useState<LoteDaTela | null>(null);
  const parar = useRef(false);

  const leitura = useQuery({
    queryKey: CHAVE_DO_LOTE,
    enabled: open,
    queryFn: lerOLote,
    staleTime: 0,
    gcTime: 0,
  });

  useEffect(() => {
    // Fechado: o que foi lido sai do cache — reabrir nunca mostra (nem envia) a lista velha enquanto relê.
    if (!open) {
      qc.removeQueries({ queryKey: CHAVE_DO_LOTE });
      return;
    }
    setFiltro(initialFilter === 'all' ? 'todas' : 'vencidas');
    setDesmarcados(new Set());
    setAberta(null);
    setConfirmando(false);
    setSituacao({});
    setCongelado(null);
    parar.current = false;
  }, [open, initialFilter, qc]);

  // A tela saiu no meio do envio (voltar do navegador, outra rota): o laço para depois do cliente da vez.
  useEffect(() => () => { parar.current = true; }, []);

  const lido = useMemo(() => {
    if (!leitura.data) return null;
    return montarLoteDaTela({
      contas: leitura.data.contas,
      clientes: leitura.data.clientes,
      filtro,
      hoje: hojeLocal(),
      piso: Number(settings?.['collection_min_amount']) || 0,
      pixKey: settings?.['pix_key'] ?? null,
      pixEsperando: leitura.data.pix,
      cobradosHoje: leitura.data.cobradosHoje,
    });
  }, [leitura.data, filtro, settings]);
  const lote = congelado ?? lido;

  const hora = horaDoCobrarJuntas();
  const foraDoHorario = hora < HORA_INICIO_COBRANCA || hora >= HORA_FIM_COBRANCA;
  const escolhidos: ItemDoLoteDaTela[] = (lote?.vao ?? []).filter((i) => !desmarcados.has(i.cliente.id));
  const totalEscolhido = escolhidos.reduce((s, i) => s + i.total, 0);
  const terminou = !rodando && Object.keys(situacao).length > 0;
  // Só com a leitura desta abertura completa e sem erro, e com as configurações (a chave Pix da mensagem e o piso) lidas.
  const leituraBoa = leitura.isSuccess && !leitura.isError && !leitura.isFetching && config.isSuccess && !config.isError;
  const podeEnviar = !rodando && !terminou && !foraDoHorario && escolhidos.length > 0 && leituraBoa;

  const alternar = (id: string) => setDesmarcados((d) => {
    const n = new Set(d);
    if (n.has(id)) n.delete(id); else n.add(id);
    return n;
  });

  async function enviarTodos() {
    setConfirmando(false);
    setRodando(true);
    setCongelado(lote);
    parar.current = false;
    const fila = [...escolhidos];
    setSituacao(Object.fromEntries(fila.map((i) => [i.cliente.id, { fase: 'fila' } as Situacao])));
    for (let k = 0; k < fila.length; k++) {
      const item = fila[k];
      if (parar.current) break;
      setSituacao((s) => ({ ...s, [item.cliente.id]: { fase: 'enviando' } }));
      let nova: Situacao;
      const jaCobrado = await cobradoAgora(item.cliente.id);
      if (jaCobrado) {
        setSituacao((s) => ({ ...s, [item.cliente.id]: { fase: 'recusado', motivo: jaCobrado } }));
        continue;
      }
      try {
        const r = await enviarCobrancaDoCliente({
          cliente: { id: item.cliente.id, name: item.cliente.name, generico: item.cliente.generico },
          mensagem: item.mensagem,
          contas: item.contas,
        });
        nova = r.deduplicado ? { fase: 'ja-saiu' } : r.modoTeste ? { fase: 'teste' } : { fase: 'enviado', aviso: r.aviso };
      } catch (e) {
        nova = { fase: 'recusado', motivo: (e as Error).message || 'Não saiu.' };
      }
      setSituacao((s) => ({ ...s, [item.cliente.id]: nova }));
      if (k < fila.length - 1 && !parar.current) await esperar(intervaloDoLote.ms);
    }
    // Parou no meio: quem ficou na fila não foi enviado.
    setSituacao((s) => Object.fromEntries(Object.entries(s).map(([id, x]) => [id, x.fase === 'fila' ? { fase: 'parado' } as Situacao : x])));
    setRodando(false);
    invalidarDepoisDoLote(qc);
  }

  const contagem = (fase: Situacao['fase']) => Object.values(situacao).filter((s) => s.fase === fase).length;

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!rodando) onOpenChange(v); }}>
      <DialogContent className="max-h-[90dvh] max-w-2xl overflow-y-auto" data-testid="cobrar-em-lote">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Send className="h-5 w-5 text-primary" /> Cobrar em lote
          </DialogTitle>
          <DialogDescription>
            Uma mensagem por cliente, com tudo que ele tem em aberto e as mesmas travas da ficha. Confira antes de enviar.
          </DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-3">
          <div className="flex flex-wrap gap-2" role="group" aria-label="Quais clientes">
            <Button
              type="button" size="sm" variant={filtro === 'vencidas' ? 'default' : 'outline'}
              disabled={rodando || terminou} onClick={() => { setFiltro('vencidas'); setDesmarcados(new Set()); }}
            >
              Com conta vencida
            </Button>
            <Button
              type="button" size="sm" variant={filtro === 'todas' ? 'default' : 'outline'}
              disabled={rodando || terminou} onClick={() => { setFiltro('todas'); setDesmarcados(new Set()); }}
            >
              Todos com saldo
            </Button>
          </div>

          {foraDoHorario && (
            <p role="alert" className="flex gap-2 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span className="min-w-0 break-words">
                Fora do horário de cobrança ({hora}h; janela {HORA_INICIO_COBRANCA}–{HORA_FIM_COBRANCA}h em Brasília): envie a partir das {HORA_INICIO_COBRANCA}h.
              </span>
            </p>
          )}

          {leitura.isLoading && (
            <p className="flex items-center gap-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" /> Conferindo as contas, os cadastros e o Extrato…
            </p>
          )}
          {config.isError && (
            <p role="alert" className="flex gap-2 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span className="min-w-0 break-words">Não consegui ler as configurações (a chave Pix e o piso). Nada foi enviado; feche e abra de novo.</span>
            </p>
          )}
          {leitura.error && (
            <p role="alert" className="flex gap-2 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span className="min-w-0 break-words">{(leitura.error as Error).message} Nada foi enviado; feche e abra de novo.</span>
            </p>
          )}

          {lote && (
            <>
              {lote.vao.length === 0 ? (
                <p className="rounded-md border bg-muted/40 px-3 py-2 text-sm" data-testid="lote-vazio">
                  Nenhum cliente para cobrar agora{lote.fora.length ? ': veja abaixo quem ficou de fora e por quê.' : '.'}
                </p>
              ) : (
                <ul className="space-y-2" aria-label="Recebem a cobrança">
                  {lote.vao.map((i) => {
                    const s = situacao[i.cliente.id];
                    const marcado = !desmarcados.has(i.cliente.id);
                    return (
                      <li key={i.cliente.id} className="min-w-0 rounded-md border p-2.5" data-testid="lote-item">
                        <div className="flex items-start gap-2">
                          <Checkbox
                            checked={marcado}
                            disabled={rodando || terminou}
                            onCheckedChange={() => alternar(i.cliente.id)}
                            aria-label={`Cobrar ${i.cliente.name || 'cliente'}`}
                            className="mt-0.5"
                          />
                          <div className="min-w-0 flex-1">
                            <p className="break-words text-sm font-medium">{(i.cliente.name || '').trim() || 'Cliente'}</p>
                            <p className="break-words text-xs text-muted-foreground tabular-nums">
                              {i.telefone} · em aberto {brl(i.total)}{i.vencido > 0 ? ` · vencido ${brl(i.vencido)}` : ''}
                            </p>
                            {s && <LinhaDaSituacao s={s} />}
                          </div>
                          <Button
                            type="button" variant="ghost" size="sm" className="h-7 shrink-0 gap-1 px-2 text-xs"
                            onClick={() => setAberta(aberta === i.cliente.id ? null : i.cliente.id)}
                            aria-expanded={aberta === i.cliente.id}
                          >
                            Mensagem {aberta === i.cliente.id ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
                          </Button>
                        </div>
                        {aberta === i.cliente.id && (
                          <pre className="mt-2 max-h-64 overflow-y-auto whitespace-pre-wrap break-words rounded-md bg-muted p-2 font-mono text-xs">
                            {i.mensagem}
                          </pre>
                        )}
                      </li>
                    );
                  })}
                </ul>
              )}

              {lote.fora.length > 0 && (
                <div className="space-y-1" data-testid="lote-fora">
                  <p className="text-xs font-medium text-muted-foreground">Ficam de fora (não recebem):</p>
                  <ul className="space-y-1">
                    {lote.fora.map((f, k) => (
                      <li key={`${f.cliente}-${k}`} className="break-words text-xs text-muted-foreground">
                        <span className="font-medium text-foreground">{f.cliente}</span>: {f.motivo}
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {!terminou && escolhidos.length > 0 && (
                <p className="flex gap-2 rounded-md border bg-muted/40 px-3 py-2 text-sm">
                  <Info className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
                  <span className="min-w-0 break-words">
                    Cada mensagem conta como a cobrança de hoje do cliente (fica registrada em Cobranças). No envio, cada
                    um é conferido de novo: o que mudou desde agora não sai. Até {MAX_CLIENTES_DO_LOTE} clientes por vez.
                  </span>
                </p>
              )}

              {terminou && (
                <p className="rounded-md border bg-muted/40 px-3 py-2 text-sm" data-testid="lote-resultado">
                  Enviadas: {contagem('enviado')} · já tinham saído hoje: {contagem('ja-saiu')} · não saíram: {contagem('recusado')}
                  {contagem('teste') ? ` · para o número de TESTE: ${contagem('teste')}` : ''}
                  {contagem('parado') ? ` · não enviadas (parou): ${contagem('parado')}` : ''}
                </p>
              )}
            </>
          )}
        </div>

        <DialogFooter className="gap-2 sm:gap-0">
          {rodando ? (
            <Button variant="outline" onClick={() => { parar.current = true; }}>Parar depois deste</Button>
          ) : confirmando ? (
            <>
              <Button variant="outline" onClick={() => setConfirmando(false)}>Voltar</Button>
              <Button onClick={() => void enviarTodos()} className="gap-2" disabled={!podeEnviar}>
                <Send className="h-4 w-4" /> Confirmar: enviar {escolhidos.length} {escolhidos.length === 1 ? 'mensagem' : 'mensagens'}
              </Button>
            </>
          ) : (
            <>
              <Button variant="outline" onClick={() => onOpenChange(false)}>Fechar</Button>
              {lote && !terminou && (
                <Button onClick={() => setConfirmando(true)} className="gap-2" disabled={!podeEnviar}>
                  <Send className="h-4 w-4" />
                  Enviar a {escolhidos.length} {escolhidos.length === 1 ? 'cliente' : 'clientes'} ({brl(totalEscolhido)})
                </Button>
              )}
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function LinhaDaSituacao({ s }: { s: Situacao }) {
  if (s.fase === 'fila') return <p className="mt-1 text-xs text-muted-foreground">Na fila…</p>;
  if (s.fase === 'enviando') {
    return <p className="mt-1 flex items-center gap-1 text-xs text-muted-foreground"><Loader2 className="h-3 w-3 animate-spin" /> Enviando…</p>;
  }
  if (s.fase === 'enviado') {
    return (
      <p className="mt-1 flex items-start gap-1 break-words text-xs text-success">
        <CheckCircle2 className="mt-0.5 h-3 w-3 shrink-0" /> <span className="min-w-0">Enviada.{s.aviso ? ` ${s.aviso}` : ''}</span>
      </p>
    );
  }
  if (s.fase === 'ja-saiu') return <p className="mt-1 text-xs text-muted-foreground">Esta mesma cobrança já tinha saído hoje: não enviei de novo.</p>;
  if (s.fase === 'teste') return <p className="mt-1 text-xs text-warning">Foi para o número de TESTE (modo de teste ligado): o cliente não recebeu.</p>;
  if (s.fase === 'parado') return <p className="mt-1 text-xs text-muted-foreground">Não enviada.</p>;
  return (
    <p className="mt-1 flex items-start gap-1 break-words text-xs text-destructive">
      <XCircle className="mt-0.5 h-3 w-3 shrink-0" /> <span className="min-w-0">Não saiu: {s.motivo}</span>
    </p>
  );
}
