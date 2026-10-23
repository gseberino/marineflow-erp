// "Quem paga pelos clientes" — a lista histórica para o dono conferir (leva 8, 22/10/2026, "siga pelo recomendado").
//
// Os pagamentos de cliente que vieram de OUTRO CPF/CNPJ (a empresa dele, o cônjuge, a marina, a seguradora), ou de
// alguém quando o cliente nem tem documento no cadastro. Cada par cliente × quem pagou vira um cartão com a prova
// ("X pagou 3× (R$ …) por Y", "Ver os pagamentos"), a relação OBRIGATÓRIA e a caixa de marcar; "Guardar os marcados"
// é o SIM do dono, registrado pelo banco (guardar_pagadores_do_cliente, com auth.uid()). Guardado, o próximo
// pagamento chega na fila com a sugestão e o motivo — e ainda pede o SIM em cada um; nada baixa sozinho.
//
// Fica FORA do lote e se decide um a um: quem pagou para vários clientes (a MUNDO DOCE), o documento que é de outro
// cliente (possível cadastro duplicado), a ligação duvidosa (a conciliação de um pagamento que já tem outra linha do
// banco) e o nome idêntico ao do cliente sem documento (deve ser ele mesmo: falta o CPF na ficha). "Não é pagador
// habitual" grava o par como RECUSADO (recusar_pagadores_do_cliente; o banco relê documento e nome da linha) e vale
// também para os casos com aviso — menos o nome idêntico, que se resolve na ficha.
//
// O que o financeiro guarda fica PROPOSTO e continua aqui, no bloco "Propostos pelo financeiro": o administrador
// confirma (é o SIM) ou recusa ali mesmo (decidir_pagador_do_cliente); o financeiro vê "aguardando o SIM do dono".
// Nada some da lista sem uma decisão.
//
// Mora em Financeiro → Regras porque é lá que o dono já aceita e recusa o que o sistema notou; fora do sistema
// (WhatsApp, Diário) iriam nomes e CPFs de terceiros.
import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { useI18n } from '@/i18n';
import { useOptionalAuth } from '@/hooks/use-auth';
import { useReaplicarRegras } from '@/hooks/use-finance-review';
import { mensagemDoErro } from '@/hooks/use-lancamentos';
import {
  CHAVE_DOS_PAGADORES, documentoMascarado, pedeRevisarFila, podeVerPagadores, RELACOES_DO_PAGADOR, ROTULO_DA_RELACAO,
  useDecidirPagador, useGuardarPagadores, usePagadoresParaConferir, useRecusarPagadores,
  type ItemParaGuardar, type PagadorParaConferir, type RelacaoDoPagador,
} from '@/hooks/use-pagadores-do-cliente';
import { nomeLimpo, nomeSemCpf } from '../../supabase/functions/_shared/banking/contraparte';
import { AlertTriangle, Check, ChevronDown, Clock, Receipt, Users, X } from 'lucide-react';

/** O máximo que guardar_pagadores_do_cliente aceita de uma vez. */
const MAXIMO_DO_LOTE = 50;

/** O motivo gravado quando o dono diz que não é pagador habitual (o banco usa o mesmo por padrão). */
const MOTIVO_DA_RECUSA = 'Não é pagador habitual';

/** Por que o item é decidido um a um: os avisos do banco e o nome idêntico, conferido aqui (normalização do motor). */
export type AvisoDoPar = NonNullable<PagadorParaConferir['aviso']> | 'nome_identico';

export function chaveDoPar(p: Pick<PagadorParaConferir, 'client_id' | 'pagador_documento'>): string {
  return `${p.client_id}:${p.pagador_documento}`;
}

/**
 * O aviso do par, ou null (cabe no lote). "Nome idêntico" só vale para o cliente SEM documento: com documento, nome
 * igual e documento diferente é a empresa dele (o MEI com o nome do dono) ou um homônimo — ali a relação resolve.
 */
export function avisoDoPar(p: PagadorParaConferir): AvisoDoPar | null {
  if (p.aviso) return p.aviso;
  if (p.grupo === 'cliente_sem_documento' && p.pagador_nome && nomeLimpo(p.pagador_nome) === nomeLimpo(p.cliente_nome)) {
    return 'nome_identico';
  }
  return null;
}

const FRASE_DO_AVISO: Record<AvisoDoPar, string> = {
  pagou_para_varios_clientes: 'Pagou por mais de um cliente (marina, seguradora?): guarde para cada cliente, um a um, ou diga que não é pagador habitual.',
  documento_de_outro_cliente: 'Este CPF/CNPJ é de outro cliente cadastrado: possível cadastro duplicado. Confira os dois cadastros antes — o sistema não guarda assim.',
  ligacao_duvidosa: 'Este Pix só está ligado ao cliente por uma conciliação de um pagamento que já tem outra linha do banco: deve ser conciliação errada, não um pagador. Confira os pagamentos antes de guardar.',
  nome_identico: 'Mesmo nome do cliente, que está sem CPF/CNPJ no cadastro: deve ser ele mesmo. Complete o CPF/CNPJ na ficha do cliente em vez de guardar.',
};

/** As linhas do banco que provam o par — lidas só quando alguém abre "Ver os pagamentos". */
function usePagamentosDoPar(ids: string[], aberto: boolean) {
  return useQuery({
    queryKey: [...CHAVE_DOS_PAGADORES, 'pagamentos-do-par', [...ids].sort()],
    enabled: aberto && ids.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('bank_transactions')
        .select('id, transaction_date, amount, counterparty_name, description')
        .in('id', ids)
        .order('transaction_date', { ascending: false });
      // Erro não vira "nenhum pagamento": a prova é o que o dono confere antes de guardar.
      if (error) throw error;
      return (data ?? []) as Array<{
        id: string; transaction_date: string; amount: number; counterparty_name: string | null; description: string | null;
      }>;
    },
    staleTime: 60 * 1000,
  });
}

function PagamentosDoPar({ ids }: { ids: string[] }) {
  const { formatCurrency, formatDate } = useI18n();
  const { data = [], isLoading, error } = usePagamentosDoPar(ids, true);
  if (isLoading) return <Skeleton className="mt-2 h-16 rounded-md" />;
  if (error) {
    return <p className="mt-2 text-xs text-destructive">Não foi possível ler os pagamentos: {mensagemDoErro(error)}</p>;
  }
  return (
    <ul className="mt-2 divide-y rounded-md border text-xs" aria-label="Pagamentos que embasam">
      {data.map((l) => (
        <li key={l.id} className="grid grid-cols-[minmax(0,1fr)_auto] gap-x-3 p-2">
          <span className="min-w-0 truncate">
            <span className="tabular-nums">{formatDate(l.transaction_date)}</span>
            {' · '}{nomeSemCpf(l.counterparty_name) ?? 'sem nome no extrato'}
          </span>
          <span className="text-right font-medium tabular-nums">{formatCurrency(Math.abs(Number(l.amount)))}</span>
          {/* O histórico do banco também traz o CPF de quem pagou ("PIX RECEBIDO 12345678901 MARIA"): mascarado. */}
          {l.description && <span className="col-span-2 min-w-0 truncate text-muted-foreground">{nomeSemCpf(l.description)}</span>}
        </li>
      ))}
    </ul>
  );
}

/** O nome de quem pagou como o banco escreveu, sem o CPF que às vezes vem dentro ("12345678901-MARIA"). */
function quemPagou(par: PagadorParaConferir): string {
  return nomeSemCpf(par.pagador_nome?.trim()) || 'Sem nome no extrato';
}

/** "X pagou N× (R$ …) por Y" e, embaixo, o documento (CPF mascarado) e as datas. */
function ResumoDoPar({ par }: { par: PagadorParaConferir }) {
  const { formatCurrency, formatDate } = useI18n();
  const doc = documentoMascarado(par.pagador_documento);
  return (
    <div>
      <p className="break-words text-sm">
        <b>{quemPagou(par)}</b> pagou {par.vezes}× ({formatCurrency(par.total)}) por <b>{par.cliente_nome}</b>
      </p>
      <p className="text-xs text-muted-foreground">
        {doc ? `${par.tipo_documento} ${doc}` : par.tipo_documento}
        {' · '}
        {par.primeira === par.ultima ? formatDate(par.primeira) : `${formatDate(par.primeira)} a ${formatDate(par.ultima)}`}
      </p>
    </div>
  );
}

function FraseDoAviso({ par, aviso }: { par: PagadorParaConferir; aviso: AvisoDoPar }) {
  return (
    <p className="flex items-start gap-1.5 rounded-md border border-amber-500/40 bg-amber-500/5 p-2 text-xs">
      <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" />
      <span className="min-w-0">
        {FRASE_DO_AVISO[aviso]}
        {(aviso === 'documento_de_outro_cliente' || aviso === 'nome_identico') && (
          <>
            {' '}
            <a className="text-primary underline" href={`/clients/${par.client_id}`} target="_blank" rel="noreferrer">
              Abrir a ficha de {par.cliente_nome}
            </a>
          </>
        )}
      </span>
    </p>
  );
}

function BotaoVerPagamentos({ aberto, onClick }: { aberto: boolean; onClick: () => void }) {
  return (
    <Button type="button" size="sm" variant="ghost" className="h-7 gap-1 px-2 text-xs text-primary"
      aria-expanded={aberto} onClick={onClick}>
      <Receipt className="h-3 w-3" />
      Ver os pagamentos
      <ChevronDown className={`h-3 w-3 transition-transform ${aberto ? 'rotate-180' : ''}`} />
    </Button>
  );
}

function CartaoDoPar({
  par, aviso, relacao, onRelacao, marcado, onMarcar, onGuardarEste, onRecusar, ocupado,
}: {
  par: PagadorParaConferir;
  aviso: AvisoDoPar | null;
  relacao: RelacaoDoPagador | undefined;
  onRelacao: (r: RelacaoDoPagador) => void;
  marcado: boolean;
  onMarcar: (m: boolean) => void;
  onGuardarEste: () => void;
  onRecusar: () => void;
  ocupado: boolean;
}) {
  const [verPagamentos, setVerPagamentos] = useState(false);
  const quem = quemPagou(par);
  const noLote = !aviso;
  // Documento de outro cliente o banco recusa; nome idêntico pede o CPF na ficha. Os dois não se guardam aqui.
  const podeGuardar = aviso !== 'documento_de_outro_cliente' && aviso !== 'nome_identico';
  const idSelect = `relacao-${chaveDoPar(par)}`;

  return (
    <Card className="p-3" data-testid="par-para-conferir">
      <div className="flex items-start gap-3">
        {noLote && (
          <Checkbox
            className="mt-1 shrink-0"
            checked={marcado}
            disabled={ocupado || !relacao}
            onCheckedChange={(v) => onMarcar(v === true)}
            aria-label={`Marcar ${quem} como quem paga por ${par.cliente_nome}`}
          />
        )}
        <div className="min-w-0 flex-1 space-y-2">
          <ResumoDoPar par={par} />

          {aviso && <FraseDoAviso par={par} aviso={aviso} />}

          {podeGuardar && (
            <div className="max-w-xs">
              <Label htmlFor={idSelect} className="text-xs">Quem é para o cliente? *</Label>
              <Select value={relacao ?? ''} onValueChange={(v) => onRelacao(v as RelacaoDoPagador)} disabled={ocupado}>
                <SelectTrigger id={idSelect} className="h-8 text-xs" aria-label={`Quem é ${quem} para ${par.cliente_nome}?`}>
                  <SelectValue placeholder="Escolher a relação" />
                </SelectTrigger>
                <SelectContent>
                  {RELACOES_DO_PAGADOR.map((r) => (
                    <SelectItem key={r} value={r} className="text-xs">{ROTULO_DA_RELACAO[r]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="flex flex-wrap items-center gap-2">
            <BotaoVerPagamentos aberto={verPagamentos} onClick={() => setVerPagamentos((v) => !v)} />
            {!noLote && podeGuardar && (
              <Button type="button" size="sm" variant="outline" className="h-7 text-xs" disabled={ocupado || !relacao}
                onClick={onGuardarEste}>
                Guardar este
              </Button>
            )}
            {aviso !== 'nome_identico' && (
              <Button type="button" size="sm" variant="ghost" className="h-7 gap-1 px-2 text-xs" disabled={ocupado}
                onClick={onRecusar}>
                <X className="h-3 w-3" />
                Não é pagador habitual
              </Button>
            )}
          </div>
          {verPagamentos && <PagamentosDoPar ids={par.bank_transaction_ids} />}
        </div>
      </div>
    </Card>
  );
}

/**
 * O par que o financeiro guardou (proposto): a relação que ele escolheu, quem e quando. O administrador confirma (é o
 * SIM) ou recusa aqui mesmo; o financeiro só vê que está aguardando o dono.
 */
function CartaoDoProposto({
  par, aviso, admin, onConfirmar, onRecusar, ocupado,
}: {
  par: PagadorParaConferir;
  aviso: AvisoDoPar | null;
  admin: boolean;
  /** Confirma com a relação escolhida aqui (a do financeiro, ou a que o administrador trocou). */
  onConfirmar: (relacao: RelacaoDoPagador | null) => void;
  onRecusar: () => void;
  ocupado: boolean;
}) {
  const { formatDate } = useI18n();
  const [verPagamentos, setVerPagamentos] = useState(false);
  // O administrador pode trocar a relação ao confirmar (decisão do dono, 23/10/2026: "pelo recomendado").
  const [relacaoEscolhida, setRelacaoEscolhida] = useState<RelacaoDoPagador | null>(
    (par.relacao_proposta as RelacaoDoPagador | null) ?? null,
  );
  const quem = quemPagou(par);
  const relacao = par.relacao_proposta
    ? (ROTULO_DA_RELACAO[par.relacao_proposta]?.toLowerCase() ?? par.relacao_proposta)
    : null;
  const porQuem = par.proposto_por_nome ? ` por ${par.proposto_por_nome}` : ' pelo financeiro';
  const quando = par.proposto_em ? ` em ${formatDate(par.proposto_em)}` : '';

  return (
    <Card className="p-3" data-testid="par-proposto">
      <div className="min-w-0 space-y-2">
        <ResumoDoPar par={par} />
        <p className="break-words text-xs">
          Proposto como <b>{relacao ?? 'pagador'}</b>{porQuem}{quando}.
        </p>

        {aviso && <FraseDoAviso par={par} aviso={aviso} />}

        <div className="flex flex-wrap items-center gap-2">
          <BotaoVerPagamentos aberto={verPagamentos} onClick={() => setVerPagamentos((v) => !v)} />
          {admin ? (
            <>
              <Select value={relacaoEscolhida ?? ''} onValueChange={(v) => setRelacaoEscolhida(v as RelacaoDoPagador)} disabled={ocupado}>
                <SelectTrigger className="h-7 w-auto min-w-[9rem] text-xs" aria-label={`Relação de ${quem} com ${par.cliente_nome} ao confirmar`}>
                  <SelectValue placeholder="Escolher a relação" />
                </SelectTrigger>
                <SelectContent>
                  {RELACOES_DO_PAGADOR.map((r) => (
                    <SelectItem key={r} value={r} className="text-xs">{ROTULO_DA_RELACAO[r]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Button type="button" size="sm" className="h-7 gap-1 text-xs" disabled={ocupado || !par.pagador_id || !relacaoEscolhida}
                aria-label={`Confirmar ${quem} como quem paga por ${par.cliente_nome}`} onClick={() => onConfirmar(relacaoEscolhida)}>
                <Check className="h-3 w-3" />
                Confirmar
              </Button>
              <Button type="button" size="sm" variant="ghost" className="h-7 gap-1 px-2 text-xs" disabled={ocupado || !par.pagador_id}
                aria-label={`Recusar ${quem} como quem paga por ${par.cliente_nome}`} onClick={onRecusar}>
                <X className="h-3 w-3" />
                Recusar
              </Button>
            </>
          ) : (
            <Badge variant="outline" className="gap-1 text-xs font-normal">
              <Clock className="h-3 w-3" />
              Aguardando o SIM do dono
            </Badge>
          )}
        </div>
        {verPagamentos && <PagamentosDoPar ids={par.bank_transaction_ids} />}
      </div>
    </Card>
  );
}

export function QuemPagaPelosClientes() {
  const cargo = useOptionalAuth()?.user?.role;
  const podeVer = podeVerPagadores(cargo);
  const admin = cargo === 'admin';
  const { data: pares = [], isLoading, error } = usePagadoresParaConferir();
  const guardar = useGuardarPagadores();
  const recusar = useRecusarPagadores();
  const decidir = useDecidirPagador();
  const revisarFila = useReaplicarRegras();

  const [relacoes, setRelacoes] = useState<Record<string, RelacaoDoPagador>>({});
  const [marcados, setMarcados] = useState<Set<string>>(new Set());

  const comAviso = useMemo(() => new Map(pares.map((p) => [chaveDoPar(p), avisoDoPar(p)])), [pares]);
  // O proposto pelo financeiro espera a decisão do administrador num bloco próprio: não entra no lote.
  const propostos = pares.filter((p) => p.situacao === 'proposto');
  const pendentes = pares.filter((p) => p.situacao !== 'proposto');
  const noLote = (p: PagadorParaConferir) => !comAviso.get(chaveDoPar(p));
  const documentoDiferente = pendentes.filter((p) => noLote(p) && p.grupo === 'documento_diferente');
  const semDocumento = pendentes.filter((p) => noLote(p) && p.grupo === 'cliente_sem_documento');
  const umAUm = pendentes.filter((p) => !noLote(p));
  // Só o que ainda está na lista e tem relação: o que saiu (guardado em outra aba) não vai no pedido.
  const lote = pendentes.filter((p) => noLote(p) && marcados.has(chaveDoPar(p)) && !!relacoes[chaveDoPar(p)]);
  const ocupado = guardar.isPending || recusar.isPending || decidir.isPending;

  if (!podeVer) return null;
  if (isLoading) return <Skeleton className="h-20 rounded-xl" />;
  if (error) {
    return (
      <Card className="border-destructive/40 bg-destructive/5 p-4">
        <p className="flex items-center gap-2 text-sm font-medium text-destructive">
          <AlertTriangle className="h-4 w-4" />
          Não foi possível carregar quem paga pelos clientes
        </p>
        <p className="mt-1 break-words text-xs text-muted-foreground">{mensagemDoErro(error)}</p>
      </Card>
    );
  }
  if (pares.length === 0) return null;

  const item = (p: PagadorParaConferir): ItemParaGuardar => ({
    client_id: p.client_id,
    // Qualquer linha do par prova: o banco relê o documento e o nome dela.
    bank_transaction_id: p.bank_transaction_ids[0],
    relacao: relacoes[chaveDoPar(p)],
    origem: 'historico',
  });

  const desmarcar = (chaves: string[]) => setMarcados((m) => {
    const n = new Set(m);
    for (const k of chaves) n.delete(k);
    return n;
  });

  /** Guarda os pares; o recusado pelo banco (com o motivo no aviso) continua marcado, o resto sai da lista. */
  const guardarPares = (lista: PagadorParaConferir[]) => {
    if (lista.length === 0 || lista.length > MAXIMO_DO_LOTE || lista.some((p) => !relacoes[chaveDoPar(p)])) return;
    guardar.mutate(lista.map(item), {
      onSuccess: (r) => {
        const recusados = new Set(r.recusados.map((x) => x.indice));
        desmarcar(lista.filter((_, i) => !recusados.has(i + 1)).map(chaveDoPar));
        // Confirmado muda o que a fila do Extrato sugere: as linhas pendentes são refeitas agora, em silêncio.
        if (pedeRevisarFila(r)) revisarFila.mutate({ silencioso: true });
      },
    });
  };

  /**
   * "Não é pagador habitual": grava o par como recusado (o banco relê documento e nome da linha) — não volta à lista
   * nem vira sugestão. Vale também para os casos com aviso (o cadastro duplicado, a MUNDO DOCE, a ligação duvidosa).
   */
  const recusarPar = (p: PagadorParaConferir) => {
    recusar.mutate({
      itens: [{ client_id: p.client_id, bank_transaction_id: p.bank_transaction_ids[0], origem: 'historico' }],
      motivo: MOTIVO_DA_RECUSA,
    }, {
      onSuccess: (r) => {
        if (r.gravados.length > 0) desmarcar([chaveDoPar(p)]);
        // O recusado é o VETO do motor (o histórico e o nome idêntico deixam de sugerir este cliente): a fila é refeita.
        if (pedeRevisarFila(r)) revisarFila.mutate({ silencioso: true });
      },
    });
  };

  /**
   * O administrador decide o proposto: confirmar é o SIM; recusar tira da lista. Os dois mudam o que a fila sugere
   * (revisão de 23/10/2026): o recusado é o VETO do motor, mesmo vindo de um proposto — a fila é refeita em silêncio.
   */
  const decidirProposto = (p: PagadorParaConferir, decisao: 'confirmar' | 'recusar', relacao?: RelacaoDoPagador | null) => {
    if (!admin || !p.pagador_id) return;
    // Relação só no confirmar, e só quando o administrador trocou a do financeiro (a RPC valida a lista).
    const trocouRelacao = decisao === 'confirmar' && !!relacao && relacao !== p.relacao_proposta;
    decidir.mutate({
      id: p.pagador_id, decisao, motivo: decisao === 'recusar' ? MOTIVO_DA_RECUSA : null,
      relacao: trocouRelacao ? relacao : null,
    }, {
      onSuccess: (r) => { if (pedeRevisarFila(r)) revisarFila.mutate({ silencioso: true }); },
    });
  };

  const mudarRelacao = (p: PagadorParaConferir, r: RelacaoDoPagador) => {
    const k = chaveDoPar(p);
    setRelacoes((m) => ({ ...m, [k]: r }));
    // Escolher a relação já é dizer "este sim": marca (dá para desmarcar).
    if (noLote(p)) setMarcados((m) => new Set(m).add(k));
  };

  const cartoes = (lista: PagadorParaConferir[]) => lista.map((p) => {
    const k = chaveDoPar(p);
    return (
      <CartaoDoPar
        key={k}
        par={p}
        aviso={comAviso.get(k) ?? null}
        relacao={relacoes[k]}
        onRelacao={(r) => mudarRelacao(p, r)}
        marcado={marcados.has(k)}
        onMarcar={(m) => setMarcados((s) => { const n = new Set(s); if (m) n.add(k); else n.delete(k); return n; })}
        onGuardarEste={() => guardarPares([p])}
        onRecusar={() => recusarPar(p)}
        ocupado={ocupado}
      />
    );
  });

  return (
    <Card className="space-y-4 p-4" data-testid="quem-paga-pelos-clientes">
      <div>
        <h3 className="flex flex-wrap items-center gap-2 font-semibold">
          <Users className="h-4 w-4 text-primary" />
          Quem paga pelos clientes
          {pendentes.length > 0 && <Badge variant="secondary" className="text-xs">{pendentes.length} para conferir</Badge>}
          {propostos.length > 0 && (
            <Badge variant="outline" className="text-xs">
              {propostos.length === 1 ? '1 proposto' : `${propostos.length} propostos`}
            </Badge>
          )}
        </h3>
        <p className="mt-1 text-sm text-muted-foreground">
          Pagamentos de cliente que vieram de outra pessoa ou empresa: a empresa do cliente, o cônjuge, a marina. Guardar
          é o seu SIM: o próximo pagamento dele chega no Extrato com o cliente sugerido e o motivo, e ainda pede a sua
          confirmação em cada um. Nada é baixado sozinho.
        </p>
        {!admin && (
          <p className="mt-1 text-xs text-muted-foreground">
            Você é do financeiro: o que guardar fica proposto, e o administrador confirma aqui mesmo, em "Propostos pelo
            financeiro".
          </p>
        )}
      </div>

      {propostos.length > 0 && (
        <section className="space-y-2" aria-label="Propostos pelo financeiro">
          <p className="text-sm font-medium">Propostos pelo financeiro ({propostos.length})</p>
          <p className="text-xs text-muted-foreground">
            {admin
              ? 'Confirmar é o seu SIM: o próximo pagamento dele chega no Extrato com o cliente sugerido, e ainda pede a sua confirmação em cada um. Recusar tira da lista: não volta a ser sugerido.'
              : 'Ficam aqui até o dono decidir. Confirmados, passam a ser sugeridos na fila do Extrato.'}
          </p>
          {propostos.map((p) => {
            const k = chaveDoPar(p);
            return (
              <CartaoDoProposto
                key={k}
                par={p}
                aviso={comAviso.get(k) ?? null}
                admin={admin}
                onConfirmar={(relacao) => decidirProposto(p, 'confirmar', relacao)}
                onRecusar={() => decidirProposto(p, 'recusar')}
                ocupado={ocupado}
              />
            );
          })}
        </section>
      )}
      {documentoDiferente.length > 0 && (
        <section className="space-y-2" aria-label="Pagaram com outro CPF/CNPJ">
          <p className="text-sm font-medium">Pagaram com outro CPF/CNPJ ({documentoDiferente.length})</p>
          {cartoes(documentoDiferente)}
        </section>
      )}
      {semDocumento.length > 0 && (
        <section className="space-y-2" aria-label="Cliente sem CPF/CNPJ no cadastro">
          <p className="text-sm font-medium">Cliente sem CPF/CNPJ no cadastro ({semDocumento.length})</p>
          <p className="text-xs text-muted-foreground">
            O nome de quem pagou é diferente do nome do cliente — nome diferente nunca identifica ninguém, por isso a
            pergunta. Se for o próprio cliente, complete o CPF/CNPJ na ficha dele.
          </p>
          {cartoes(semDocumento)}
        </section>
      )}
      {umAUm.length > 0 && (
        <section className="space-y-2" aria-label="Decida um a um">
          <p className="text-sm font-medium">Decida um a um ({umAUm.length})</p>
          {cartoes(umAUm)}
        </section>
      )}

      {(documentoDiferente.length > 0 || semDocumento.length > 0) && (
        <div className="sticky bottom-2 z-10 flex flex-wrap items-center justify-between gap-2 rounded-lg border bg-background/95 p-2 shadow-sm backdrop-blur">
          <span className="text-xs text-muted-foreground">
            {lote.length === 0
              ? 'Escolha a relação de quem você reconhece: ele fica marcado.'
              : lote.length > MAXIMO_DO_LOTE
                ? `No máximo ${MAXIMO_DO_LOTE} de uma vez — desmarque ${lote.length - MAXIMO_DO_LOTE}.`
                : admin ? 'Ficam confirmados (é o seu SIM).' : 'Ficam propostos: falta o SIM do administrador.'}
          </span>
          <Button size="sm" disabled={ocupado || lote.length === 0 || lote.length > MAXIMO_DO_LOTE} onClick={() => guardarPares(lote)}>
            {guardar.isPending ? 'Guardando…' : `Guardar os marcados (${lote.length})`}
          </Button>
        </div>
      )}
    </Card>
  );
}
