import { AlertTriangle, RefreshCw } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { useBankConnections, useSyncBank, type BankConnection, type SyncResult } from '@/hooks/use-bank-connections';
import { cn } from '@/lib/utils';

/**
 * "Atualizar extrato" — o mesmo botão em todo cômodo do Financeiro que lê o extrato (06/10/2026).
 *
 * Antes ele só existia em Cadastros › Contas bancárias, com o nome "Buscar extrato", e quem
 * estava no Extrato ou na Conciliação tinha de sair da tela para trazer o que o banco mandou.
 *
 * O que ele faz e o que NÃO faz: lê no Pluggy o que o banco já entregou. As conexões são do
 * MeuPluggy, que vai ao banco sozinho uma vez a cada 24 h e não aceita pedido de "ir agora"
 * (docs.pluggy.ai, Meu Pluggy). Por isso o selo ao lado diz a idade do dado do BANCO — não a
 * hora do clique —, para ninguém achar que "atualizado agora" quer dizer "tem a compra de agora".
 */

/** Conexões que o botão de fato busca: ativas e de banco (o Caixa é lançado à mão). */
export function conexoesBuscaveis(conexoes: BankConnection[] | undefined): BankConnection[] {
  return (conexoes ?? []).filter((c) => c.active !== false && c.provider !== 'caixa');
}

const HORA = new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });
const DIA = new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Sao_Paulo' });
const diaLocal = (d: Date) => DIA.format(d);

/** "hoje às 09:12", "ontem às 18:40", "amanhã às 09:00", "03/10 às 15:00". */
export function quandoFoi(iso: string | null | undefined, agora = new Date()): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const ontem = new Date(agora.getTime() - 86400000);
  const amanha = new Date(agora.getTime() + 86400000);
  const dia = diaLocal(d) === diaLocal(agora) ? 'hoje'
    : diaLocal(d) === diaLocal(ontem) ? 'ontem'
    : diaLocal(d) === diaLocal(amanha) ? 'amanhã'
    : diaLocal(d);
  return `${dia} às ${HORA.format(d)}`;
}

/**
 * A data mais VELHA entre as contas: se uma está atrasada, é ela que diz o que pode faltar.
 * Usa a data em que o Pluggy foi ao banco (`provider_updated_at`) quando já foi gravada; senão,
 * a da última leitura pelo ERP.
 */
export function dadoMaisVelho(conexoes: BankConnection[]): { iso: string; conta: string } | null {
  let pior: { iso: string; conta: string } | null = null;
  for (const c of conexoes) {
    const iso = c.provider_updated_at ?? c.last_synced_at;
    if (!iso) continue;
    if (!pior || iso < pior.iso) pior = { iso, conta: c.label };
  }
  return pior;
}

/**
 * Dado do banco com mais de 36 h: o Pluggy vai ao banco uma vez por dia, então passar de um dia e
 * meio quer dizer que uma ida falhou (consentimento, banco fora do ar). O selo fica amarelo.
 */
export const HORAS_PARA_ATRASADO = 36;
export function estaAtrasado(iso: string | null | undefined, agora = new Date()): boolean {
  if (!iso) return false;
  const t = new Date(iso).getTime();
  return Number.isFinite(t) && agora.getTime() - t > HORAS_PARA_ATRASADO * 3600_000;
}

/** Aviso do resultado da busca: o mesmo em toda tela. */
export function avisarResultadoDaBusca(r: SyncResult) {
  const comErro = r.resultados.filter((x) => x.status === 'error');
  if (comErro.length > 0) toast.warning(comErro.map((x) => `${x.conexao}: ${x.mensagem}`).join(' · '));
  else toast.success(r.message);
}

export function AtualizarExtrato({ className, comSelo = true }: { className?: string; comSelo?: boolean }) {
  const { data: conexoes } = useBankConnections();
  const sincronizar = useSyncBank();
  const buscaveis = conexoesBuscaveis(conexoes);
  if (buscaveis.length === 0) return null;

  const velho = dadoMaisVelho(buscaveis);
  const quando = quandoFoi(velho?.iso);
  const atrasado = estaAtrasado(velho?.iso);

  const atualizar = async () => {
    try {
      avisarResultadoDaBusca(await sincronizar.mutateAsync({}));
    } catch (e: any) {
      toast.error(e?.message || 'Não consegui atualizar o extrato');
    }
  };

  return (
    <div className={cn('flex items-center gap-2', className)}>
      {comSelo && quando && (
        <span
          className={cn(
            'items-center gap-1 text-xs',
            // Atrasado aparece também no celular: é o aviso que importa.
            atrasado ? 'inline-flex rounded-md bg-warning/15 px-2 py-1 font-medium text-warning' : 'hidden text-muted-foreground sm:inline-flex',
          )}
          data-testid="idade-do-extrato"
          data-atrasado={atrasado ? 'sim' : undefined}
          title={atrasado
            ? `${velho!.conta} está sem dado novo do banco desde ${quando}. O Pluggy vai ao banco uma vez por dia: confira em Cadastros › Contas bancárias se a conexão pede para reconectar no meu.pluggy.ai.`
            : `O banco manda o extrato ao Pluggy uma vez por dia; o dado mais antigo é o de ${velho!.conta}. Em Cadastros › Contas bancárias, cada conta mostra o seu.`}
        >
          {atrasado && <AlertTriangle className="h-3.5 w-3.5" />}
          {atrasado ? `${velho!.conta}: sem dado novo desde ${quando}` : `Bancos: dado de ${quando}`}
        </span>
      )}
      <Button variant="outline" className="gap-1.5" onClick={atualizar} disabled={sincronizar.isPending}>
        <RefreshCw className={cn('h-4 w-4', sincronizar.isPending && 'animate-spin')} />
        {sincronizar.isPending ? 'Atualizando…' : 'Atualizar extrato'}
      </Button>
    </div>
  );
}
