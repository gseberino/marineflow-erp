// Aba "WhatsApp" de Configurações: o número da HBR está conectado? Se não, reconectar por aqui.
//
// Em 29/09/2026 o celular removeu o aparelho conectado às 16:21 e ninguém soube por 4 horas;
// reconectar exigia o Claude gerar o QR no PC. Agora a tela mostra o estado, gera o QR (para ler
// de outra tela) ou o código de 8 dígitos (para conectar só com o celular, "Conectar com número
// de telefone"), e o vigia da função whatsapp-conexao avisa no sino quando o número cai.
import { useCallback, useEffect, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { CheckCircle2, Loader2, MessageCircle, QrCode, RefreshCw, Smartphone, WifiOff } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import { extractInvokeErrorMessage } from '@/lib/invoke-error';

type Estado = 'open' | 'connecting' | 'close' | 'inacessivel';

interface InfoDaConexao {
  estado: Estado;
  detalhe: string | null;
  perfil: string | null;
  numero: string | null;
  queda: { em: string; motivo: string | null } | null;
  vigia: { estado: Estado; desde: string; verificado_em: string } | null;
}

interface RespostaDoConectar {
  estado: Estado;
  qr: string | null;
  codigo: string | null;
  detalhe: string | null;
}

type Modo = 'qr' | 'codigo';

/** Tempo máximo esperando a leitura; depois disso a pessoa pede de novo. */
const LIMITE_MS = 5 * 60 * 1000;

async function chamar<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('whatsapp-conexao', { body });
  if (error) throw new Error(await extractInvokeErrorMessage(error));
  return data as T;
}

export function formatarTelefone(digitos: string | null | undefined): string {
  const d = String(digitos ?? '').replace(/\D/g, '').replace(/^55/, '');
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return d;
}

export function formatarCodigo(codigo: string): string {
  const c = codigo.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  return c.length === 8 ? `${c.slice(0, 4)}-${c.slice(4)}` : c;
}

function hora(iso: string | null | undefined): string {
  if (!iso) return '';
  return new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}

function quando(iso: string): string {
  const d = new Date(iso);
  const hoje = new Date();
  const mesmoDia = d.toDateString() === hoje.toDateString();
  return mesmoDia ? `às ${hora(iso)}` : `em ${d.toLocaleDateString('pt-BR')} às ${hora(iso)}`;
}

function Situacao({ info }: { info: InfoDaConexao }) {
  if (info.estado === 'open') {
    const quem = [info.perfil, formatarTelefone(info.numero)].filter(Boolean).join(' · ');
    return (
      <div className="flex items-start gap-3">
        <CheckCircle2 className="h-5 w-5 text-emerald-600 shrink-0 mt-0.5" />
        <div>
          <p className="font-medium">Conectado</p>
          {quem && <p className="text-sm text-muted-foreground break-words">{quem}</p>}
        </div>
      </div>
    );
  }
  if (info.estado === 'inacessivel') {
    return (
      <div className="flex items-start gap-3">
        <WifiOff className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
        <div>
          <p className="font-medium">Servidor do WhatsApp fora do ar</p>
          <p className="text-sm text-muted-foreground break-words">
            {info.detalhe ? `O ERP não alcança o servidor no PC: ${info.detalhe}.` : 'O ERP não alcança o servidor no PC.'}
            {' '}Precisa religar no PC (Docker e túnel). Conectar por aqui não resolve.
          </p>
        </div>
      </div>
    );
  }
  const desde = info.queda?.em ? ` desde ${quando(info.queda.em)}` : '';
  return (
    <div className="flex items-start gap-3">
      <WifiOff className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
      <div>
        <p className="font-medium">
          {info.estado === 'connecting' ? 'Esperando a leitura do QR' : 'Desconectado'}{desde}
        </p>
        <p className="text-sm text-muted-foreground break-words">
          Nenhuma mensagem entra ou sai{info.queda?.motivo ? `: ${info.queda.motivo}` : ''}.
        </p>
      </div>
    </div>
  );
}

export function WhatsAppConexaoTab({ intervaloMs = 4000 }: { intervaloMs?: number }) {
  const qc = useQueryClient();
  const { data: info, isLoading, isFetching, error, refetch } = useQuery({
    queryKey: ['whatsapp-conexao'],
    queryFn: () => chamar<InfoDaConexao>({ acao: 'estado' }),
    refetchInterval: 60 * 1000,
    retry: false,
  });

  const [modo, setModo] = useState<Modo | null>(null);
  const [numero, setNumero] = useState('');
  const [sessao, setSessao] = useState<RespostaDoConectar | null>(null);
  const [consultas, setConsultas] = useState(0);
  const [esgotou, setEsgotou] = useState(false);
  const inicio = useRef(0);
  const emVoo = useRef(false);
  const preencheu = useRef(false);

  // O número da instância vem preenchido uma vez; se a pessoa apagar para digitar outro, fica apagado.
  useEffect(() => {
    if (info?.numero && !preencheu.current) {
      preencheu.current = true;
      setNumero(formatarTelefone(info.numero));
    }
  }, [info?.numero]);

  const pedir = useCallback(async (m: Modo, primeira: boolean) => {
    if (emVoo.current) return;
    emVoo.current = true;
    try {
      const r = await chamar<RespostaDoConectar>({
        acao: 'conectar',
        ...(m === 'codigo' ? { numero } : {}),
        ...(primeira ? { inicio: true } : {}),
      });
      setSessao(r);
      setConsultas((n) => n + 1);
      if (r.estado === 'open') {
        setModo(null);
        setSessao(null);
        toast.success('WhatsApp conectado!');
        qc.invalidateQueries({ queryKey: ['whatsapp-conexao'] });
      }
    } catch (e) {
      setModo(null);
      toast.error((e as Error).message || 'Não consegui falar com o WhatsApp.');
    } finally {
      emVoo.current = false;
    }
  }, [numero, qc]);

  const comecar = (m: Modo) => {
    setModo(m);
    setSessao(null);
    setConsultas(0);
    setEsgotou(false);
    inicio.current = Date.now();
    void pedir(m, true);
  };

  useEffect(() => {
    if (!modo) return;
    const id = setInterval(() => {
      if (Date.now() - inicio.current > LIMITE_MS) {
        setModo(null);
        setSessao(null);
        setEsgotou(true);
        return;
      }
      void pedir(modo, false);
    }, intervaloMs);
    return () => clearInterval(id);
  }, [modo, pedir, intervaloMs]);

  const numeroValido = numero.replace(/\D/g, '').length >= 10;
  const conectado = info?.estado === 'open';
  const semCodigoAinda = modo === 'codigo' && !sessao?.codigo;
  // Um QR já aberto (sem número) não troca para código: a Evolution só gera o código ao iniciar.
  const codigoNaoVeio = semCodigoAinda && consultas >= 3 && !!sessao?.qr;

  return (
    <div className="rounded-xl border bg-card p-4 sm:p-6 space-y-4 max-w-2xl">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-sm font-semibold flex items-center gap-2">
          <MessageCircle className="h-4 w-4" /> WhatsApp da HBR
        </h3>
        <Button variant="ghost" size="sm" onClick={() => refetch()} disabled={isFetching} aria-label="Atualizar estado">
          <RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />
        </Button>
      </div>

      {isLoading && (
        <p className="text-sm text-muted-foreground flex items-center gap-2">
          <Loader2 className="h-4 w-4 animate-spin" /> Conferindo a conexão…
        </p>
      )}
      {error && !isLoading && (
        <p className="text-sm text-destructive">{(error as Error).message}</p>
      )}
      {info && <Situacao info={info} />}

      {info && !conectado && info.estado !== 'inacessivel' && !modo && (
        <div className="space-y-4 border-t pt-4">
          {esgotou && (
            <p className="text-sm text-muted-foreground">O tempo para ler acabou. Peça de novo quando estiver com o celular na mão.</p>
          )}
          <div className="space-y-2">
            <p className="text-sm font-medium">Tenho outra tela (computador ou tablet)</p>
            <Button onClick={() => comecar('qr')} className="w-full sm:w-auto">
              <QrCode className="h-4 w-4 mr-2" /> Mostrar QR code
            </Button>
          </div>
          <div className="space-y-2">
            <p className="text-sm font-medium">Só tenho o celular da HBR</p>
            <div className="flex flex-col sm:flex-row gap-2 sm:items-end">
              <div className="space-y-1.5 flex-1 min-w-0">
                <Label htmlFor="whatsapp-numero">Número do WhatsApp da HBR</Label>
                <Input id="whatsapp-numero" inputMode="tel" placeholder="(47) 99999-0000"
                  value={numero} onChange={(e) => setNumero(e.target.value)} />
              </div>
              <Button variant="outline" onClick={() => comecar('codigo')} disabled={!numeroValido}>
                <Smartphone className="h-4 w-4 mr-2" /> Receber código
              </Button>
            </div>
          </div>
        </div>
      )}

      {modo && (
        <div className="space-y-4 border-t pt-4">
          {modo === 'qr' || codigoNaoVeio ? (
            <div className="space-y-3 text-center">
              {codigoNaoVeio && (
                <p className="text-sm text-muted-foreground text-left">
                  Já havia um QR aberto, e o código só sai numa conexão nova. Leia este QR, ou cancele e peça o código daqui a alguns minutos.
                </p>
              )}
              {sessao?.qr ? (
                <div className="inline-block rounded-lg bg-white p-3">
                  <img src={sessao.qr} alt="QR code para conectar o WhatsApp" className="w-64 max-w-full h-auto" />
                </div>
              ) : (
                <p className="text-sm text-muted-foreground flex items-center justify-center gap-2">
                  <Loader2 className="h-4 w-4 animate-spin" /> Gerando o QR…
                </p>
              )}
              <ol className="text-sm text-left list-decimal pl-5 space-y-1">
                <li>No celular da HBR, abra o WhatsApp → <b>Configurações</b> → <b>Dispositivos conectados</b>.</li>
                <li>Toque em <b>Conectar dispositivo</b> e aponte a câmera para o código.</li>
                <li>O código troca sozinho a cada ~20 segundos; se falhar, espere o próximo.</li>
              </ol>
            </div>
          ) : (
            <div className="space-y-3">
              {sessao?.codigo ? (
                <p className="text-center text-3xl font-mono font-bold tracking-widest" aria-label="Código de conexão">
                  {formatarCodigo(sessao.codigo)}
                </p>
              ) : (
                <p className="text-sm text-muted-foreground flex items-center gap-2">
                  <Loader2 className="h-4 w-4 animate-spin" /> Pedindo o código ao WhatsApp…
                </p>
              )}
              <ol className="text-sm list-decimal pl-5 space-y-1">
                <li>No celular da HBR, abra o WhatsApp → <b>Configurações</b> → <b>Dispositivos conectados</b>.</li>
                <li>Toque em <b>Conectar dispositivo</b> e depois em <b>Conectar com número de telefone</b>.</li>
                <li>Digite o código acima.</li>
              </ol>
            </div>
          )}
          <div className="flex items-center justify-between gap-2 flex-wrap">
            <p className="text-xs text-muted-foreground flex items-center gap-2">
              <Loader2 className="h-3 w-3 animate-spin" /> Esperando a conexão…
            </p>
            <Button variant="ghost" size="sm" onClick={() => { setModo(null); setSessao(null); }}>Cancelar</Button>
          </div>
        </div>
      )}

      <p className="text-xs text-muted-foreground">
        O ERP confere a conexão sozinho a cada 5 minutos e avisa no sino se o número ficar 10 minutos fora do ar.
        {info?.vigia?.verificado_em ? ` Última conferência automática às ${hora(info.vigia.verificado_em)}.` : ''}
      </p>
    </div>
  );
}
