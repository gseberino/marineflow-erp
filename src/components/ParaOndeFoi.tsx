// "Para onde foi?" e a observação — o que a linha do Extrato precisava além da categoria.
//
// Pedido do dono (26/09/2026): "quando uma despesa aparece para ser revisada, só tem o campo de
// selecionar a despesa e os botões de ações, isso não basta". Serviço de terceiro pago a um CPF
// precisa dizer QUAL serviço e PARA ONDE foi — o trabalho num barco, motorhome ou equipamento de
// um cliente (custo daquele serviço, na OS dele) ou a própria HBR: pintura, obra na sede,
// veículo, equipamento da empresa (despesa da empresa, com centro de custo). Qualquer outra linha
// ganha, se o dono quiser, uma observação e o centro de custo.
//
// A regra do que falta é a mesma do servidor (supabase/functions/_shared/banking/destino.ts):
// o que a tela deixa aprovar é o que o servidor aceita.
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useServiceOrdersVinculaveis } from '@/hooks/use-payees';
import { useCostCenters, centrosParaEscolher } from '@/hooks/use-cost-centers';
import {
  SERVICO_DE_CLIENTE, SERVICO_DA_EMPRESA, destinoEfetivo, fraseDaFalta, type FaltaNoDestino,
} from '@/lib/extrato-vinculo';
import type { Correcao } from '@/hooks/use-finance-review';

/** Radix não aceita SelectItem de valor vazio: cada "nenhum" tem valor próprio. */
const SEM_OS = '__sem_os_no_sistema__';
const SEM_CENTRO = '__sem_centro_de_custo__';

export function ParaOndeFoi({
  categoria, correcao, osJaDita, falta, onMudar, ocupado, emGrupo = false,
}: {
  categoria: string;
  correcao: Correcao | undefined;
  /** OS que o dono já disse (anotação pelo WhatsApp) quando a tela não respondeu outra. */
  osJaDita?: string | null;
  falta: FaltaNoDestino[];
  onMudar: (c: Partial<Correcao>) => void;
  ocupado: boolean;
  /** No cabeçalho do grupo a resposta desce para todas as linhas dele. */
  emGrupo?: boolean;
}) {
  const destino = destinoEfetivo(categoria, correcao, osJaDita);
  const { data: ordens = [] } = useServiceOrdersVinculaveis({ incluirFaturadas: true });
  const { data: centros } = useCostCenters();
  const opcoesDeCentro = centrosParaEscolher(centros, 'payable', correcao?.costCenterId ?? null);
  const os = correcao?.serviceOrderId;
  const osMostrada = typeof os === 'string' ? os : os === null ? SEM_OS : (osJaDita ?? '');

  return (
    <div className="mt-2 max-w-2xl space-y-2 rounded-md border border-primary/30 bg-primary/5 p-2 text-xs">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-medium">
          {emGrupo ? 'Para onde foram estes serviços?' : 'Para onde foi este serviço?'}
        </span>
        <Button
          type="button" size="sm" className="h-7 text-xs" disabled={ocupado}
          variant={destino === 'cliente' ? 'default' : 'outline'}
          aria-pressed={destino === 'cliente'}
          // "Não é desta OS" (null) dito antes não vira "sem OS": a OS do cliente é pergunta nova.
          onClick={() => onMudar({ destino: 'cliente', category: SERVICO_DE_CLIENTE, serviceOrderId: typeof os === 'string' ? os : undefined })}
        >
          Serviço de um cliente
        </Button>
        <Button
          type="button" size="sm" className="h-7 text-xs" disabled={ocupado}
          variant={destino === 'empresa' ? 'default' : 'outline'}
          aria-pressed={destino === 'empresa'}
          onClick={() => onMudar({ destino: 'empresa', category: SERVICO_DA_EMPRESA, serviceOrderId: null })}
        >
          Para a HBR
        </Button>
      </div>

      {destino === 'cliente' && (
        <Select
          value={osMostrada}
          onValueChange={(v) => onMudar({ serviceOrderId: v === SEM_OS ? null : v })}
          disabled={ocupado}
        >
          <SelectTrigger className="h-8 max-w-[20rem] text-xs" aria-label="De qual OS">
            <SelectValue placeholder="De qual OS?" />
          </SelectTrigger>
          <SelectContent>
            {ordens.map((o) => (
              <SelectItem key={o.id} value={o.id}>
                {o.service_order_number} · {o.clients?.name ?? 'sem cliente'}{o.status === 'invoiced' ? ' (faturada)' : ''}
              </SelectItem>
            ))}
            <SelectItem value={SEM_OS}>O serviço não tem OS no sistema</SelectItem>
          </SelectContent>
        </Select>
      )}

      {destino === 'empresa' && (
        <div className="flex flex-wrap items-center gap-2">
          <Select
            value={correcao?.costCenterId ?? ''}
            onValueChange={(v) => onMudar({ costCenterId: v })}
            disabled={ocupado}
          >
            <SelectTrigger className="h-8 max-w-[17rem] text-xs" aria-label="Centro de custo">
              <SelectValue placeholder="Em qual centro de custo?" />
            </SelectTrigger>
            <SelectContent>
              {opcoesDeCentro.map((c) => <SelectItem key={c.id} value={c.id}>{c.rotulo}</SelectItem>)}
            </SelectContent>
          </Select>
          <span className="text-muted-foreground">Entra como despesa da empresa, não como custo de serviço.</span>
        </div>
      )}

      <Input
        value={correcao?.notes ?? ''}
        onChange={(e) => onMudar({ notes: e.target.value })}
        disabled={ocupado}
        maxLength={500}
        aria-label="O que foi feito"
        className="h-8 text-xs"
        placeholder={destino === 'empresa'
          ? 'O que foi feito? Ex.: pintura da fachada da sede'
          : 'O que foi feito? Ex.: solda no casco do barco do João'}
      />

      {falta.length > 0 && <p className="text-amber-600">{fraseDaFalta(falta)}.</p>}
    </div>
  );
}

/**
 * Observação e centro de custo de qualquer linha — fechados até alguém pedir, para não virar
 * ruído nas centenas de linhas que não precisam deles.
 */
export function ObservacaoECentro({
  correcao, ehReceita, onMudar, ocupado,
}: {
  correcao: Correcao | undefined;
  ehReceita: boolean;
  onMudar: (c: Partial<Correcao>) => void;
  ocupado: boolean;
}) {
  const [aberto, setAberto] = useState(() => !!(correcao?.notes || correcao?.costCenterId));
  const { data: centros } = useCostCenters();
  const opcoes = centrosParaEscolher(centros, ehReceita ? 'receivable' : 'payable', correcao?.costCenterId ?? null);

  if (!aberto) {
    return (
      <button
        type="button" disabled={ocupado} onClick={() => setAberto(true)}
        className="mt-1 inline-flex items-center gap-1 text-xs text-primary hover:underline disabled:opacity-50"
      >
        + Observação{opcoes.length > 0 ? ' e centro de custo' : ''}
      </button>
    );
  }

  return (
    <div className="mt-2 flex max-w-2xl flex-wrap items-center gap-2">
      <Input
        value={correcao?.notes ?? ''}
        onChange={(e) => onMudar({ notes: e.target.value })}
        disabled={ocupado}
        maxLength={500}
        aria-label="Observação"
        placeholder="Observação (opcional)"
        className="h-8 min-w-0 flex-1 basis-48 text-xs"
      />
      {opcoes.length > 0 && (
        <Select
          value={correcao?.costCenterId ?? SEM_CENTRO}
          onValueChange={(v) => onMudar({ costCenterId: v === SEM_CENTRO ? null : v })}
          disabled={ocupado}
        >
          <SelectTrigger className="h-8 w-auto max-w-[15rem] text-xs" aria-label="Centro de custo">
            <SelectValue placeholder="Centro de custo" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={SEM_CENTRO}>Sem centro de custo</SelectItem>
            {opcoes.map((c) => <SelectItem key={c.id} value={c.id}>{c.rotulo}</SelectItem>)}
          </SelectContent>
        </Select>
      )}
    </div>
  );
}
