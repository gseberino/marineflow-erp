// Aba "Assistente de IA" de Configurações (03/10/2026): quem atende o assistente no WhatsApp e no
// chat do app — o OpenRouter (pago por uso) ou a assinatura Claude Max do dono, pelo HBR AI Gateway
// que roda no PC dele. Uma chave por canal em app_settings; a edge lê a cada mensagem, então virar
// a chave vale na próxima pergunta. Também mostra se o PC está no ar e como foram os últimos turnos.
//
// Termos da Anthropic: a assinatura é para uso individual do assinante — só o admin vai pelo Max;
// os outros usuários seguem no OpenRouter mesmo com a chave ligada (a edge e o gateway conferem).
import { useQuery } from '@tanstack/react-query';
import { Bot, CheckCircle2, Cpu, Info, Loader2, WifiOff } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/use-auth';
import { useAppSettings, useUpdateAppSetting } from '@/hooks/use-app-settings';

type Provedor = 'openrouter' | 'claude_max';
type Nivel = 'haiku' | 'sonnet' | 'opus';

interface EstadoDoProvider {
  available: boolean;
  until?: string;
  reason?: string;
}

interface WorkerDoGateway {
  id: string;
  enabled: boolean;
  last_seen_at: string | null;
  version: string | null;
  providers?: Record<string, EstadoDoProvider> | null;
  ativos?: number | null;
  maximo?: number | null;
}

interface TurnoRecente {
  tipo: string | null;
  status: string;
  model_used: string | null;
  duration_ms: number | null;
  error_code: string | null;
  created_at: string;
}

export interface StatusDoGateway {
  disponivel: boolean;
  agora: string;
  workers: WorkerDoGateway[];
  ultimos: TurnoRecente[];
}

export const CANAIS = [
  {
    id: 'whatsapp',
    titulo: 'WhatsApp',
    chaveProvedor: 'ai_provedor_whatsapp',
    chaveModelo: 'ai_whatsapp_max_modelo',
    explicacao: 'O assistente que responde suas mensagens no WhatsApp da HBR.',
  },
  {
    id: 'panel',
    titulo: 'Chat do app',
    chaveProvedor: 'ai_provedor_painel',
    chaveModelo: 'ai_painel_max_modelo',
    explicacao: 'O assistente do botão de IA aqui no MarineFlow. Pelo Max, a tela espera a resposta do seu PC.',
  },
] as const;

const NIVEIS: { id: Nivel; rotulo: string; dica: string }[] = [
  { id: 'haiku', rotulo: 'Haiku', dica: 'mais rápido' },
  { id: 'sonnet', rotulo: 'Sonnet', dica: 'equilibrado' },
  { id: 'opus', rotulo: 'Opus', dica: 'mais capaz, mais lento' },
];

export function provedorAtual(valor: string | undefined): Provedor {
  return (valor ?? '').trim().toLowerCase() === 'claude_max' ? 'claude_max' : 'openrouter';
}

export function nivelAtual(valor: string | undefined): Nivel {
  const v = (valor ?? '').trim().toLowerCase();
  return v === 'haiku' || v === 'opus' ? v : 'sonnet';
}

function haQuanto(iso: string | null | undefined, agoraIso?: string): string {
  if (!iso) return 'nunca';
  const s = Math.max(0, Math.round(((agoraIso ? Date.parse(agoraIso) : Date.now()) - Date.parse(iso)) / 1000));
  if (s < 60) return `há ${s} s`;
  if (s < 3600) return `há ${Math.round(s / 60)} min`;
  if (s < 86400) return `há ${Math.round(s / 3600)} h`;
  return `em ${new Date(iso).toLocaleDateString('pt-BR')}`;
}

const ROTULO_DO_TIPO: Record<string, string> = { agente_whatsapp: 'WhatsApp', agente_painel: 'App' };
const ROTULO_DO_STATUS: Record<string, string> = {
  completed: 'respondeu',
  failed: 'falhou',
  cancelled: 'cancelado',
  processing: 'trabalhando',
  pending: 'na fila',
};

function useStatusDoGateway(ligado: boolean) {
  return useQuery({
    queryKey: ['ai-gateway-status'],
    enabled: ligado,
    refetchInterval: 15_000,
    queryFn: async (): Promise<StatusDoGateway | null> => {
      const { data, error } = await supabase.rpc('ai_gateway_status');
      if (error) throw new Error(error.message);
      return (data as unknown as StatusDoGateway) ?? null;
    },
  });
}

function StatusDoPc({ status, carregando, erro }: { status: StatusDoGateway | null | undefined; carregando: boolean; erro: string | null }) {
  if (carregando) {
    return (
      <p className="text-sm text-muted-foreground flex items-center gap-2">
        <Loader2 className="h-4 w-4 animate-spin" /> Consultando o gateway…
      </p>
    );
  }
  if (erro) return <p className="text-sm text-destructive">Não consegui ler o status: {erro}</p>;
  if (!status) return <p className="text-sm text-muted-foreground">Sem informação do gateway.</p>;

  const worker = status.workers[0];
  const claude = worker?.providers?.['claude-local'];
  return (
    <div className="space-y-3">
      <div className="flex items-start gap-3">
        {status.disponivel ? (
          <CheckCircle2 className="h-5 w-5 text-emerald-600 shrink-0 mt-0.5" />
        ) : (
          <WifiOff className="h-5 w-5 text-amber-600 shrink-0 mt-0.5" />
        )}
        <div className="min-w-0">
          <p className="text-sm font-medium">
            {status.disponivel ? 'Claude Max disponível' : 'Claude Max indisponível agora'}
          </p>
          <p className="text-xs text-muted-foreground break-words">
            {worker
              ? `PC ${worker.id} · último sinal ${haQuanto(worker.last_seen_at, status.agora)}${worker.version ? ` · versão ${worker.version}` : ''}${
                  typeof worker.ativos === 'number' && typeof worker.maximo === 'number' ? ` · ${worker.ativos}/${worker.maximo} em andamento` : ''
                }`
              : 'Nenhum PC cadastrado no gateway.'}
          </p>
          {!status.disponivel && (
            <p className="text-xs text-muted-foreground mt-1 break-words">
              {claude && !claude.available && claude.reason
                ? `Motivo: ${claude.reason}${claude.until ? ` (até ${new Date(claude.until).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })})` : ''}. `
                : 'O PC pode estar desligado ou sem internet. '}
              Enquanto isso, as mensagens vão pelo OpenRouter (se a reserva estiver ligada).
            </p>
          )}
        </div>
      </div>

      {status.ultimos.length > 0 && (
        <div>
          <p className="text-xs font-medium text-muted-foreground mb-1">Últimos turnos pelo Max</p>
          <ul className="space-y-1">
            {status.ultimos.map((t, i) => (
              <li key={`${t.created_at}-${i}`} className="text-xs flex flex-wrap gap-x-2 gap-y-0.5">
                <span className="text-muted-foreground">{haQuanto(t.created_at, status.agora)}</span>
                <span>{ROTULO_DO_TIPO[t.tipo ?? ''] ?? t.tipo ?? '—'}</span>
                <span className={t.status === 'failed' ? 'text-destructive' : ''}>
                  {ROTULO_DO_STATUS[t.status] ?? t.status}
                  {t.error_code ? ` (${t.error_code})` : ''}
                </span>
                {t.duration_ms != null && <span className="text-muted-foreground">{(t.duration_ms / 1000).toFixed(1)} s</span>}
                {t.model_used && <span className="text-muted-foreground break-all">{t.model_used}</span>}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function Escolha<T extends string>({
  rotulo,
  opcoes,
  valor,
  onEscolher,
  desabilitado,
}: {
  rotulo: string;
  opcoes: { id: T; rotulo: string; dica?: string }[];
  valor: T;
  onEscolher: (v: T) => void;
  desabilitado?: boolean;
}) {
  return (
    <div role="group" aria-label={rotulo} className="flex flex-wrap gap-2">
      {opcoes.map((o) => (
        <Button
          key={o.id}
          type="button"
          size="sm"
          variant={valor === o.id ? 'default' : 'outline'}
          aria-pressed={valor === o.id}
          disabled={desabilitado}
          onClick={() => valor !== o.id && onEscolher(o.id)}
        >
          {o.rotulo}
          {o.dica && <span className="ml-1 text-[11px] opacity-70">· {o.dica}</span>}
        </Button>
      ))}
    </div>
  );
}

export function AssistenteIATab() {
  const { user } = useAuth();
  const ehAdmin = user?.role === 'admin';
  const { data: settings, isLoading } = useAppSettings();
  const salvar = useUpdateAppSetting();
  const status = useStatusDoGateway(ehAdmin);

  if (!ehAdmin) {
    return (
      <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl">
        <p className="text-sm text-muted-foreground">Só o administrador escolhe quem atende o assistente de IA.</p>
      </div>
    );
  }

  const gravar = (key: string, value: string, aviso: string) =>
    salvar.mutate({ key, value }, { onSuccess: () => toast.success(aviso) });

  const reserva = (settings?.ai_whatsapp_max_reserva ?? '').trim().toLowerCase() !== 'off';

  return (
    <div className="space-y-4 max-w-2xl">
      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <h3 className="text-sm font-semibold mb-4 flex items-center gap-2">
          <Cpu className="h-4 w-4" /> Claude Max no seu PC (HBR AI Gateway)
        </h3>
        <StatusDoPc
          status={status.data}
          carregando={status.isLoading}
          erro={status.error ? (status.error as Error).message : null}
        />
      </div>

      {CANAIS.map((canal) => {
        const provedor = provedorAtual(settings?.[canal.chaveProvedor]);
        const nivel = nivelAtual(settings?.[canal.chaveModelo]);
        return (
          <div key={canal.id} className="rounded-xl border bg-card p-6 shadow-sm space-y-3">
            <div>
              <h3 className="text-sm font-semibold flex items-center gap-2">
                <Bot className="h-4 w-4" /> {canal.titulo}
              </h3>
              <p className="text-xs text-muted-foreground mt-1">{canal.explicacao}</p>
            </div>
            <div className="space-y-1">
              <p className="text-xs font-medium text-muted-foreground">Quem responde</p>
              <Escolha<Provedor>
                rotulo={`Quem responde — ${canal.titulo}`}
                opcoes={[
                  { id: 'openrouter', rotulo: 'OpenRouter' },
                  { id: 'claude_max', rotulo: 'Claude Max' },
                ]}
                valor={provedor}
                desabilitado={isLoading || salvar.isPending}
                onEscolher={(v) =>
                  gravar(canal.chaveProvedor, v, `${canal.titulo}: ${v === 'claude_max' ? 'agora pelo Claude Max' : 'agora pelo OpenRouter'}.`)
                }
              />
            </div>
            <div className="space-y-1">
              <p className="text-xs font-medium text-muted-foreground">Modelo do Claude Max</p>
              <Escolha<Nivel>
                rotulo={`Modelo do Claude Max — ${canal.titulo}`}
                opcoes={NIVEIS}
                valor={nivel}
                desabilitado={isLoading || salvar.isPending || provedor !== 'claude_max'}
                onEscolher={(v) => gravar(canal.chaveModelo, v, `${canal.titulo}: modelo ${v}.`)}
              />
            </div>
          </div>
        );
      })}

      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <p className="text-sm font-semibold">Se o Claude Max falhar, responder pelo OpenRouter</p>
            <p className="text-xs text-muted-foreground mt-1">
              PC desligado, limite da assinatura ou erro: com isto ligado, a mesma pergunta é refeita pelo OpenRouter (pago por
              uso). Desligado, o assistente só avisa que não conseguiu. Vale para o WhatsApp e para o app.
            </p>
          </div>
          <Switch
            aria-label="Reserva pelo OpenRouter"
            checked={reserva}
            disabled={isLoading || salvar.isPending}
            onCheckedChange={(v) =>
              gravar('ai_whatsapp_max_reserva', v ? 'on' : 'off', v ? 'Reserva pelo OpenRouter ligada.' : 'Reserva pelo OpenRouter desligada.')
            }
          />
        </div>
      </div>

      <div className="rounded-xl border bg-muted/30 p-4 space-y-2 text-xs text-muted-foreground">
        <p className="flex items-start gap-2">
          <Info className="h-4 w-4 shrink-0 mt-0.5" />
          <span>
            A assinatura Claude Max é pessoal: só você (administrador) é atendido por ela. Os demais usuários seguem no OpenRouter
            mesmo com a chave ligada.
          </span>
        </p>
        <p className="flex items-start gap-2">
          <Info className="h-4 w-4 shrink-0 mt-0.5" />
          <span>
            As outras funções de IA — revisão financeira, sugestão de NCM, acompanhamento de pendências, detector da caixa de
            mensagens, leitura de áudio e foto do WhatsApp, voz da agenda e triagem de e-mail — continuam no OpenRouter: rodam
            sozinhas, a qualquer hora ou sobre mensagens de terceiros, e custam pouco.
          </span>
        </p>
      </div>
    </div>
  );
}
