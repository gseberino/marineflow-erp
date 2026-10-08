// Configurações › Integrações › Dropbox (Fase 2A, 08/10/2026 — plans/marineflow-dropbox-fase2.md).
// Liga o sistema ao Dropbox da HBR: o botão leva ao "Permitir" do dropbox.com, que volta para cá
// com ?dropbox=ok|negado|expirou|falhou|nao_configurado. O token nunca chega ao navegador: a tela
// só pergunta o estado à edge dropbox-conectar.
import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { CheckCircle2, ExternalLink, FolderSync, Loader2, PlugZap, RefreshCw, Unplug } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { extractInvokeErrorMessage } from '@/lib/invoke-error';

interface EstadoDoDropbox {
  configurado: boolean;
  conectado: boolean;
  conta: {
    conta_id: string;
    email: string | null;
    nome: string | null;
    conectado_em: string;
    ultimo_uso_em: string | null;
    ultimo_erro: string | null;
    ultimo_erro_em: string | null;
  } | null;
  pastaBase: string;
  linkPastaBase: string;
  redirectUri: string;
  indice: { arquivos: number; atualizadoEm: string | null; lendoHistorico: boolean } | null;
}

interface ResultadoDoTeste {
  ok: boolean;
  conta: { nome: string; email: string; tipo: string };
  pastaBase: { existe: boolean; caminho: string };
}

const AVISOS_DA_VOLTA: Record<string, { ok: boolean; texto: string }> = {
  ok: { ok: true, texto: 'Dropbox conectado!' },
  negado: { ok: false, texto: 'A conexão foi cancelada no Dropbox.' },
  expirou: { ok: false, texto: 'O pedido de conexão expirou (10 minutos). Clique em Conectar de novo.' },
  falhou: { ok: false, texto: 'O Dropbox não confirmou a conexão. Tente de novo.' },
  nao_configurado: { ok: false, texto: 'As chaves do app do Dropbox ainda não estão no servidor.' },
  sem_codigo: { ok: false, texto: 'O Dropbox voltou sem o código de autorização. Tente de novo.' },
};

async function chamar<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('dropbox-conectar', { body });
  if (error) throw new Error(await extractInvokeErrorMessage(error));
  return data as T;
}

const quando = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—';

export function DropboxIntegracaoTab() {
  const qc = useQueryClient();
  const [params, setParams] = useSearchParams();
  const [ocupado, setOcupado] = useState<'conectar' | 'testar' | 'desconectar' | 'indice' | null>(null);
  const [confirmandoSaida, setConfirmandoSaida] = useState(false);
  const [teste, setTeste] = useState<ResultadoDoTeste | null>(null);

  const { data: info, isLoading, isFetching, error, refetch } = useQuery({
    queryKey: ['dropbox-conexao'],
    queryFn: () => chamar<EstadoDoDropbox>({ acao: 'status' }),
    retry: false,
  });

  // A volta do dropbox.com: avisa uma vez e limpa a URL.
  useEffect(() => {
    const volta = params.get('dropbox');
    if (!volta) return;
    const aviso = AVISOS_DA_VOLTA[volta] ?? { ok: false, texto: 'Resposta inesperada do Dropbox.' };
    if (aviso.ok) toast.success(aviso.texto);
    else toast.error(aviso.texto);
    const sem = new URLSearchParams(params);
    sem.delete('dropbox');
    setParams(sem, { replace: true });
    qc.invalidateQueries({ queryKey: ['dropbox-conexao'] });
  }, [params, setParams, qc]);

  const conectar = async () => {
    setOcupado('conectar');
    try {
      const { url } = await chamar<{ url: string }>({ acao: 'iniciar' });
      window.location.href = url;
    } catch (e) {
      toast.error((e as Error).message || 'Não consegui iniciar a conexão.');
      setOcupado(null);
    }
  };

  const testar = async () => {
    setOcupado('testar');
    setTeste(null);
    try {
      const r = await chamar<ResultadoDoTeste>({ acao: 'testar' });
      setTeste(r);
      toast.success('O Dropbox respondeu.');
    } catch (e) {
      toast.error((e as Error).message || 'O teste falhou.');
    } finally {
      setOcupado(null);
      qc.invalidateQueries({ queryKey: ['dropbox-conexao'] });
    }
  };

  const atualizarIndice = async () => {
    setOcupado('indice');
    try {
      const { data, error } = await supabase.functions.invoke('dropbox-indice', { body: {} });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      const r = data as { gravados?: number; novasPastas?: number; emDia?: boolean; motivo?: string };
      if (r.motivo) toast.info(r.motivo);
      else toast.success(`Índice atualizado: ${r.gravados ?? 0} arquivo(s) lido(s)${r.novasPastas ? `, ${r.novasPastas} pasta(s) nova(s)` : ''}${r.emDia ? '' : ' — continua na próxima rodada'}.`);
    } catch (e) {
      toast.error((e as Error).message || 'Não consegui atualizar o índice.');
    } finally {
      setOcupado(null);
      qc.invalidateQueries({ queryKey: ['dropbox-conexao'] });
    }
  };

  const desconectar = async () => {
    setOcupado('desconectar');
    try {
      await chamar({ acao: 'desconectar' });
      toast.success('Dropbox desconectado. Nada foi apagado no Dropbox.');
      setConfirmandoSaida(false);
      setTeste(null);
      await qc.invalidateQueries({ queryKey: ['dropbox-conexao'] });
    } catch (e) {
      toast.error((e as Error).message || 'Não consegui desconectar.');
    } finally {
      setOcupado(null);
    }
  };

  return (
    <div className="rounded-xl border bg-card p-4 sm:p-6 space-y-4 max-w-2xl">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-sm font-semibold flex items-center gap-2">
          <FolderSync className="h-4 w-4" /> Dropbox
        </h3>
        <Button variant="ghost" size="sm" onClick={() => refetch()} disabled={isFetching} aria-label="Atualizar estado">
          <RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />
        </Button>
      </div>

      <p className="text-sm text-muted-foreground">
        O sistema cria a pasta de cada barco e guarda nela os PDFs de orçamento e OS. Ele só cria pastas e
        acrescenta arquivos: nunca apaga nem sobrescreve nada no seu Dropbox.
      </p>

      {isLoading && (
        <p className="text-sm text-muted-foreground flex items-center gap-2">
          <Loader2 className="h-4 w-4 animate-spin" /> Conferindo a conexão…
        </p>
      )}
      {error && !isLoading && (
        <p className="text-sm text-destructive">{(error as Error).message || 'Não consegui ler o estado da conexão.'}</p>
      )}

      {info && !info.configurado && (
        <p className="text-sm rounded-lg border border-amber-500/40 bg-amber-500/10 p-3">
          As chaves do app do Dropbox ainda não estão no servidor. Rode o comando do PowerShell que o Claude
          passou e depois atualize esta tela.
        </p>
      )}

      {info?.configurado && !info.conectado && (
        <div className="space-y-3">
          <p className="text-sm">Ainda não conectado.</p>
          <Button onClick={conectar} disabled={ocupado !== null}>
            {ocupado === 'conectar' ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <PlugZap className="h-4 w-4 mr-2" />}
            Conectar ao Dropbox
          </Button>
          <p className="text-xs text-muted-foreground">
            Você vai para o dropbox.com, entra com a conta da HBR e clica em "Permitir". Depois volta sozinho para cá.
          </p>
        </div>
      )}

      {info?.conectado && info.conta && (
        <div className="space-y-3">
          <p className="text-sm flex items-center gap-2">
            <CheckCircle2 className="h-4 w-4 text-green-600" />
            Conectado como <strong>{info.conta.nome || '—'}</strong>
            {info.conta.email && <span className="text-muted-foreground">({info.conta.email})</span>}
          </p>
          <dl className="grid grid-cols-[auto,1fr] gap-x-3 gap-y-1 text-sm">
            <dt className="text-muted-foreground">Conectado em</dt>
            <dd>{quando(info.conta.conectado_em)}</dd>
            <dt className="text-muted-foreground">Último uso</dt>
            <dd>{quando(info.conta.ultimo_uso_em)}</dd>
            <dt className="text-muted-foreground">Pasta dos barcos</dt>
            <dd className="break-all">
              <a href={info.linkPastaBase} target="_blank" rel="noreferrer" className="underline inline-flex items-center gap-1">
                {info.pastaBase} <ExternalLink className="h-3 w-3" />
              </a>
            </dd>
          </dl>
          {info.indice && (
            <div className="text-sm rounded-lg border p-3 space-y-2">
              <p>
                <strong>Arquivos indexados:</strong> {info.indice.arquivos.toLocaleString('pt-BR')}
                {' · '}última leitura {quando(info.indice.atualizadoEm)}
              </p>
              {info.indice.lendoHistorico && (
                <p className="text-muted-foreground">Lendo o histórico das pastas aos poucos (a cada 10 minutos). Pode levar algumas horas na primeira vez.</p>
              )}
              <Button variant="outline" size="sm" onClick={atualizarIndice} disabled={ocupado !== null}>
                {ocupado === 'indice' ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <RefreshCw className="h-4 w-4 mr-2" />}
                Atualizar agora
              </Button>
            </div>
          )}
          {info.conta.ultimo_erro && (
            <p className="text-sm text-destructive break-words">
              Último erro ({quando(info.conta.ultimo_erro_em)}): {info.conta.ultimo_erro}
            </p>
          )}
          {teste && (
            <div className="text-sm rounded-lg border p-3 space-y-1">
              <p>Conta: {teste.conta.nome} ({teste.conta.email})</p>
              <p>
                Pasta dos barcos: {teste.pastaBase.existe ? 'encontrada' : 'ainda não existe (será criada no primeiro uso)'}
              </p>
            </div>
          )}
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" onClick={testar} disabled={ocupado !== null}>
              {ocupado === 'testar' && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
              Testar conexão
            </Button>
            {!confirmandoSaida ? (
              <Button variant="ghost" onClick={() => setConfirmandoSaida(true)} disabled={ocupado !== null}>
                <Unplug className="h-4 w-4 mr-2" /> Desconectar
              </Button>
            ) : (
              <>
                <Button variant="destructive" onClick={desconectar} disabled={ocupado !== null}>
                  {ocupado === 'desconectar' && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
                  Sim, desconectar
                </Button>
                <Button variant="ghost" onClick={() => setConfirmandoSaida(false)} disabled={ocupado !== null}>
                  Cancelar
                </Button>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
