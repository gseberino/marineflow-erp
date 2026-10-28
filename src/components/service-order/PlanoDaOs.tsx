/**
 * O cartão "Plano" da OS (Agenda de Produção, Fase 3, P7a; plano §7): os 4 marcos, a duração com a fonte (e o "Corrigir
 * dias", o único campo novo), a presença do dono, o material por linha com o nível A–E e o trecho de onde veio, a janela
 * do bem, prometido × planejado e planejado × realizado por dia (a diária só "lançada" ou "a confirmar" — o valor nunca
 * aparece). O botão Entregue só com a OS concluída e sem a entrega. Tudo pronto de os_plano_da_os.
 *
 * Só para administrador e financeiro, OS fora de orçamento e a agenda de produção ligada (PlanoDaOsNaOs decide). Fecha
 * numa linha (o estado e a duração) para não empurrar o formulário no celular.
 *
 * Fase 5 (P6): o bloco "Cliente" — o que foi dito ao cliente (e se ainda vale), a confirmação e as mensagens desta OS
 * (lista curta, "em teste" quando o modo é sombra). Sem botão de mandar: a aprovação é pela palavra (*manda cliente
 * <nome>* / *segura cliente <nome>*) ou na conversa; a tela só cita a palavra que o banco escreve.
 */
import { useId, useState } from 'react';
import { AlertCircle, ChevronDown, Loader2, PackageCheck } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Campo } from '@/components/Campo';
import { Dado, DadosDaFicha } from '@/components/DadosDaFicha';
import { useOptionalAuth } from '@/hooks/use-auth';
import {
  useAgendaConfig, usePlanejarPelaTela, usePlanoDaOs, useRegistrarEntrega, type ClienteDoPlano, type MaterialDoPlano,
} from '@/hooks/use-agenda-producao';
import { cn } from '@/lib/utils';

const STATUS_SEM_DURACAO = ['completed', 'invoiced', 'cancelled'];

function SeloDoNivel({ item }: { item: MaterialDoPlano }) {
  return (
    <span
      className={cn('inline-flex h-6 min-w-6 shrink-0 items-center justify-center rounded border px-1 text-xs font-bold',
                    item.nivel === 'A' ? 'border-emerald-600 text-emerald-700 dark:text-emerald-400'
                      : item.nivel === 'E' ? 'border-red-600 text-red-700 dark:text-red-400'
                      : 'border-amber-600 text-amber-700 dark:text-amber-400')}
      title={item.nivel_texto}
    >
      {item.nivel}
    </span>
  );
}

/**
 * O bloco "Cliente" (Fase 5, P6). Some quando a mensagem ao cliente está desligada e não há nada dito nem mandado (o
 * cartão fica como na Fase 3). Rótulo acima do valor, como o resto do cartão. Nenhum botão: só o texto do banco.
 */
export function BlocoDoCliente({ cliente }: { cliente: ClienteDoPlano | null | undefined }) {
  if (!cliente) return null;
  if (cliente.modo === 'desligado' && !cliente.prometido && cliente.mensagens.length === 0) return null;
  const dito = cliente.prometido;
  return (
    <div className="min-w-0 space-y-3" data-testid="plano-cliente">
      <div className="flex min-w-0 flex-wrap items-center gap-2">
        <h3 className="text-xs font-semibold text-muted-foreground">Cliente{cliente.nome ? ` · ${cliente.nome}` : ''}</h3>
        {cliente.em_teste && (
          <span className="rounded border border-amber-600 px-1.5 text-[11px] font-medium text-amber-700 dark:text-amber-400">em teste</span>
        )}
      </div>
      {cliente.em_teste_texto && <p className="break-words text-xs text-muted-foreground">{cliente.em_teste_texto}</p>}
      {cliente.contato_texto && (
        <p className="break-words text-sm text-amber-700 dark:text-amber-400">Não recebe mensagem: {cliente.contato_texto}.</p>
      )}
      <DadosDaFicha>
        <Dado rotulo="O que foi dito ao cliente" largo>
          {dito ? dito.texto : 'Nada ainda.'}
          {dito?.risco_texto && <span className="block text-sm text-amber-700 dark:text-amber-400">{dito.risco_texto}</span>}
          {cliente.confirmado_texto && <span className="block text-sm">{cliente.confirmado_texto}</span>}
        </Dado>
        {cliente.servico && <Dado rotulo="O serviço, como ele ouve" largo>{cliente.servico}</Dado>}
      </DadosDaFicha>
      <div className="min-w-0 space-y-1.5">
        <p className="text-xs text-muted-foreground">Mensagens</p>
        {cliente.esperando_voce.texto && <p className="break-words text-sm font-medium">{cliente.esperando_voce.texto}</p>}
        {cliente.mensagens.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhuma mensagem a este cliente ainda.</p>
        ) : (
          <ul className="space-y-2">
            {cliente.mensagens.map((m, i) => (
              <li key={`${m.tipo}-${m.quando_texto}-${i}`} className="min-w-0 text-sm">
                <p className="break-words">
                  <span className="font-medium">{m.tipo_texto}</span>
                  {m.quando_texto && <span className="text-muted-foreground"> · {m.quando_texto}</span>}
                  {m.estado_texto && <span className={cn(m.espera_voce && 'font-medium')}> · {m.estado_texto}</span>}
                </p>
                <p className="break-words text-xs text-muted-foreground">“{m.texto}”</p>
              </li>
            ))}
          </ul>
        )}
        {cliente.mensagens_mais > 0 && (
          <p className="text-xs text-muted-foreground">E mais {cliente.mensagens_mais}: *agenda clientes* mostra todas.</p>
        )}
      </div>
    </div>
  );
}

export function PlanoDaOs({ osId, status, className }: { osId: string; status: string; className?: string }) {
  const { data, isLoading, error, refetch, isFetching } = usePlanoDaOs(osId);
  const planejar = usePlanejarPelaTela();
  const entregar = useRegistrarEntrega();
  const [aberto, setAberto] = useState(false);
  const [dias, setDias] = useState('');
  const idDias = useId();
  const idAjudaDias = useId();
  const idCorpo = useId();

  if (isLoading) {
    return (
      <section className={cn('rounded-xl border bg-card p-5 shadow-sm', className)} role="status">
        <p className="flex items-center gap-2 text-sm text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> Carregando o plano…
        </p>
      </section>
    );
  }
  if (error) {
    return (
      <section className={cn('space-y-2 rounded-xl border bg-card p-5 shadow-sm', className)} role="alert">
        <p className="flex items-center gap-2 text-sm text-destructive">
          <AlertCircle className="h-4 w-4 shrink-0" aria-hidden />
          <span className="break-words">Não consegui ler o plano: {error instanceof Error ? error.message : String(error)}</span>
        </p>
        <Button size="sm" variant="outline" onClick={() => refetch()} disabled={isFetching}>Tentar de novo</Button>
      </section>
    );
  }
  // A tela ainda não está no banco: a OS fica como era, sem o cartão.
  if (!data) return null;

  const gravarDias = async () => {
    const n = Number(dias.replace(',', '.'));
    try {
      const texto = await planejar.mutateAsync({ osId, dias: n });
      toast.success(texto || 'Duração gravada.');
      setDias('');
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'O banco não gravou a duração.');
    }
  };
  const registrarEntrega = async () => {
    try {
      const texto = await entregar.mutateAsync(osId);
      toast.success(texto || 'Entrega registrada.');
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'O banco não registrou a entrega.');
    }
  };
  const resumo = [data.estado, data.duracao.texto].filter(Boolean).join(' · ');
  const janela = [data.janela.bem_indisponivel, data.janela.nao_antes_texto, data.janela.precisa_ate_texto].filter(Boolean);

  return (
    <section className={cn('space-y-4 rounded-xl border bg-card p-5 shadow-sm', className)} aria-labelledby={`${idCorpo}-titulo`} data-testid="plano-da-os">
      <div className="flex min-w-0 flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <h2 id={`${idCorpo}-titulo`} className="text-sm font-semibold">Plano</h2>
          {resumo && <p className="break-words text-sm text-muted-foreground">{resumo}</p>}
        </div>
        <div className="flex shrink-0 flex-wrap gap-2">
          {data.pode_entregar && (
            <Button size="sm" className="gap-1" onClick={registrarEntrega} disabled={entregar.isPending}>
              {entregar.isPending ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> : <PackageCheck className="h-4 w-4" aria-hidden />}
              Entregue
            </Button>
          )}
          <Button size="sm" variant="outline" className="gap-1" aria-expanded={aberto} aria-controls={idCorpo}
                  onClick={() => setAberto((v) => !v)}>
            {aberto ? 'Esconder o plano' : 'Ver o plano'}
            <ChevronDown className={cn('h-4 w-4 transition-transform', aberto && 'rotate-180')} aria-hidden />
          </Button>
        </div>
      </div>

      {aberto && (
        <div id={idCorpo} className="space-y-5">
          <DadosDaFicha>
            <Dado rotulo="Marcos" largo>{data.marcos.texto}</Dado>
            <Dado rotulo="Duração">
              {data.duracao.texto}
              {data.duracao.faixa_texto && <span className="block text-xs text-muted-foreground">{data.duracao.faixa_texto}</span>}
            </Dado>
            <Dado rotulo="Presença do dono">{data.presenca_dono.texto}</Dado>
            <Dado rotulo="Janela do bem">{janela.length > 0 ? janela.join(' · ') : 'Sem restrição'}</Dado>
            <Dado rotulo="Prometido × planejado">{data.prometido_planejado.texto ?? 'Sem data do cliente e sem plano'}</Dado>
          </DadosDaFicha>

          {!STATUS_SEM_DURACAO.includes(status) && (
            <Campo rotulo="Corrigir dias" htmlFor={idDias} idAjuda={idAjudaDias}
                   ajuda="Quantos dias de serviço, de meio em meio dia (por exemplo, 2 ou 2,5).">
              <div className="flex flex-wrap gap-2">
                <Input id={idDias} type="number" inputMode="decimal" min={0.5} step={0.5} value={dias}
                       onChange={(e) => setDias(e.target.value)} aria-describedby={idAjudaDias} className="w-32" />
                <Button size="sm" onClick={gravarDias} disabled={!dias.trim() || planejar.isPending}>
                  {planejar.isPending && <Loader2 className="mr-1 h-4 w-4 animate-spin" aria-hidden />} Gravar
                </Button>
              </div>
            </Campo>
          )}

          <BlocoDoCliente cliente={data.cliente} />

          <div className="space-y-2">
            <h3 className="text-xs font-semibold text-muted-foreground">Material</h3>
            {data.material.itens.length === 0 ? (
              <p className="text-sm text-muted-foreground">Nenhuma linha de material.</p>
            ) : (
              <ul className="space-y-2">
                {data.material.itens.map((m, i) => (
                  <li key={`${m.descricao}-${i}`} className="flex min-w-0 gap-2 text-sm">
                    <SeloDoNivel item={m} />
                    <div className="min-w-0">
                      <p className="break-words">{m.descricao}</p>
                      <p className="break-words text-xs text-muted-foreground">
                        {[m.previsao?.startsWith(m.nivel_texto) ? null : m.nivel_texto, m.previsao, m.fornecedor, m.critico ? null : 'pode começar sem']
                          .filter(Boolean).join(' · ')}
                      </p>
                      {m.trecho && <p className="break-words text-xs italic text-muted-foreground">“{m.trecho}”</p>}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="space-y-2">
            <h3 className="text-xs font-semibold text-muted-foreground">Planejado × realizado</h3>
            {data.planejado_realizado.length === 0 ? (
              <p className="text-sm text-muted-foreground">Ainda sem dia no plano.</p>
            ) : (
              <ul className="space-y-1.5">
                {data.planejado_realizado.map((d) => (
                  <li key={d.dia} className="min-w-0 break-words text-sm">
                    <span className="font-medium">{d.rotulo}</span>
                    {d.dia_texto && <span className="text-muted-foreground"> · {d.dia_texto}</span>}
                    {d.pessoas_texto && <span> · {d.pessoas_texto}</span>}
                    {d.resultado_texto && <span> · {d.resultado_texto}</span>}
                    {d.motivo_texto && <span className="text-muted-foreground"> ({d.motivo_texto})</span>}
                    {d.diaria && <span className="text-muted-foreground"> · diária {d.diaria}</span>}
                  </li>
                ))}
              </ul>
            )}
          </div>

          {data.intervencoes.length > 0 && (
            <div className="space-y-1">
              <h3 className="text-xs font-semibold text-muted-foreground">Quando você foi sem estar no plano</h3>
              <ul className="space-y-1">
                {data.intervencoes.map((i, n) => <li key={`${i.dia}-${n}`} className="break-words text-sm">{i.texto}</li>)}
              </ul>
            </div>
          )}
        </div>
      )}
    </section>
  );
}

/** O cartão na tela da OS: só para administrador e financeiro, OS fora de orçamento e a agenda de produção ligada. */
export function PlanoDaOsNaOs({ osId, status, className }: { osId: string; status: string; className?: string }) {
  const papel = useOptionalAuth()?.user?.role;
  const { config } = useAgendaConfig();
  if (status === 'draft' || (papel !== 'admin' && papel !== 'financial')) return null;
  if (config.modo_leitura === 'desligado') return null;
  return <PlanoDaOs osId={osId} status={status} className={className} />;
}
