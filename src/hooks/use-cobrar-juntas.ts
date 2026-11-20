// "Cobrar juntas" (Fase 0 do Fechar juntas, 28/10/2026): uma mensagem com o saldo de várias OS do
// mesmo cliente. É o extrato filtrado (buildClientStatement com servicoIds).
//
// O envio passa pelas MESMAS travas do send_collection_reminder do assistente — a regra mora em
// _shared/receivables/cobrar-juntas.ts e vale para os dois. Na hora do envio, relê o cadastro (o
// destino é o WhatsApp dele, nunca um número digitado), as contas (saldo mudou = não envia) e
// confere o horário de cobrança (8h–20h em Brasília), como o portão do assistente.
//
// Depois do envio confirmado (20/11/2026, decisão do dono "Criar a cobrança junto"): a função do
// banco cobrar_juntas_registrar_envio cria a cobrança (collections) das contas que não têm nenhuma e
// registra o envio em todas (contato 'whatsapp_sent' + 'sent' + last_auto_sent_at), tudo ou nada.
// Ordem: a mensagem sai PRIMEIRO; se não sai (erro, "em andamento", modo de teste, já enviada hoje),
// a função não é chamada e nenhuma cobrança é criada. Se a função falha depois do envio, nada é
// gravado e a tela avisa que a mensagem saiu sem registro.
//
// "Enviar extrato" (dono, 20/11/2026: "Sim, as mesmas travas"): o mesmo caminho de conferência
// (conferirEEnviar) com o cliente inteiro — sem contagem de OS, chave do dia com prefixo 'extrato'
// e sem criar cobrança (a decisão de criar foi só para o Cobrar juntas).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { extractInvokeErrorMessage } from '@/lib/invoke-error';
import { normalizePhoneE164 } from '@/lib/masks';
import {
  chaveDoCobrarJuntas, hojeLocal, horaEmBrasilia, mudancaNasContas, travaDoCobrarJuntas,
} from '../../supabase/functions/_shared/receivables/cobrar-juntas';
import { desviadoPorTeste } from '../../supabase/functions/_shared/whatsapp/marcar-enviado';

/** O relógio da tela (horário de cobrança) — os testes trocam, como relogioDoCobrarJuntas da tool. */
export const relogioDoCobrarJuntasTela = { agora: () => new Date() };

/** Hora em Brasília agora, pelo relógio da tela. */
export function horaDoCobrarJuntas(): number {
  return horaEmBrasilia(relogioDoCobrarJuntasTela.agora());
}

export interface PixEsperando { valor: number; data: string | null }

/**
 * Pix do cliente parado no Extrato esperando decisão (mesma leitura de pix-esperando.ts do
 * assistente). Leitura que falha LANÇA: "nenhum Pix esperando" por erro mandaria cobrar quem pagou.
 */
async function lerPixEsperando(clientId: string): Promise<PixEsperando[]> {
  const { data, error } = await supabase
    .from('finance_review_queue')
    .select('suggested_amount, suggested_date')
    .eq('status', 'pending')
    .eq('kind', 'create_receivable')
    .eq('suggested_client_id', clientId)
    .range(0, 999);
  if (error) throw new Error(`Não consegui ler os Pix que esperam no Extrato: ${error.message}`);
  return ((data ?? []) as Array<{ suggested_amount: number | null; suggested_date: string | null }>).map((l) => ({
    valor: Math.abs(Number(l.suggested_amount ?? 0)),
    data: l.suggested_date,
  }));
}

async function lerPiso(): Promise<number> {
  const { data, error } = await supabase.from('app_settings').select('value').eq('key', 'collection_min_amount').maybeSingle();
  if (error) throw new Error(`Não consegui ler o piso de cobrança: ${error.message}`);
  return Number((data as { value?: string | null } | null)?.value) || 0;
}

/**
 * O whatsapp-send vai desviar este envio para o número de teste? A MESMA regra da edge e das tools
 * (desviadoPorTeste, _shared/whatsapp/marcar-enviado.ts): ligado sem número não desvia. Leitura que
 * falha LANÇA: "não é teste" por erro gravaria a cobrança e queimaria a chave do cliente.
 */
async function lerDesvioDeTeste(): Promise<boolean> {
  const { data, error } = await supabase.from('app_settings').select('key, value')
    .in('key', ['wa_test_mode', 'wa_test_number', 'zapi_test_mode', 'zapi_test_number']);
  if (error) throw new Error(`Não consegui ler o modo de teste do WhatsApp: ${error.message}`);
  const cfg = Object.fromEntries(((data ?? []) as Array<{ key: string; value: string | null }>).map((s) => [s.key, s.value]));
  return desviadoPorTeste(cfg);
}

/** Para mostrar a trava ANTES do botão. O envio relê tudo na hora (conferirEEnviar). */
export function usePixEsperandoDoCliente(clientId: string | null | undefined, enabled = true) {
  return useQuery({
    queryKey: ['finance-review', 'pix-esperando', clientId],
    enabled: enabled && !!clientId,
    queryFn: () => lerPixEsperando(clientId!),
    staleTime: 30 * 1000,
  });
}

export interface EnvioCobrarJuntas {
  cliente: { id: string; name?: string | null; generico?: boolean | null };
  mensagem: string;
  /**
   * As contas abertas que entraram na mensagem, com o saldo que a tela mostrou. O envio relê as
   * contas das OS e recusa se o conjunto ou algum saldo mudou (como o retrato da tool).
   */
  contas: Array<{ id: string; saldo: number }>;
  /** As OS escolhidas (cobrança sem conta, só com a OS, também é registrada). */
  servicoIds: string[];
}

export interface ResultadoCobrarJuntas {
  deduplicado: boolean;
  cobrancasRegistradas: number;
  /** Cobranças criadas junto com o envio (contas que não tinham nenhuma). */
  cobrancasCriadas: number;
  aviso: string | null;
  /** O modo de teste desviou o envio para o número de teste: o cliente NÃO recebeu. */
  modoTeste?: boolean;
}

/** Aviso da tela quando o envio foi desviado pelo modo de teste. */
export const AVISO_MODO_TESTE =
  'O modo de teste do WhatsApp está ligado: a mensagem foi para o número de teste, não para o cliente. Nada foi registrado nas cobranças.';

/** Uma cobrança aberta das contas/OS escolhidas (para saber quais contas ganham cobrança no envio). */
export type CobrancaAberta = { id: string; status: string | null; receivable_id: string | null; service_order_id: string | null };

/**
 * As cobranças formais (collections) abertas das contas escolhidas: pela conta, ou só pela OS (sem
 * conta). Duas leituras em vez de .or() (vírgula em filtro .or() já quebrou consulta aqui). LANÇA.
 */
async function lerCobrancasAbertas(contaIds: string[], servicoIds: string[]): Promise<CobrancaAberta[]> {
  const ids = new Map<string, CobrancaAberta>();
  const colunas = 'id, status, receivable_id, service_order_id';
  if (contaIds.length) {
    const { data, error } = await supabase.from('collections').select(colunas)
      .in('receivable_id', contaIds).not('status', 'in', '(paid,cancelled)');
    if (error) throw new Error(error.message);
    for (const c of (data ?? []) as CobrancaAberta[]) ids.set(c.id, c);
  }
  if (servicoIds.length) {
    const { data, error } = await supabase.from('collections').select(colunas)
      .in('service_order_id', servicoIds).is('receivable_id', null).not('status', 'in', '(paid,cancelled)');
    if (error) throw new Error(error.message);
    for (const c of (data ?? []) as CobrancaAberta[]) ids.set(c.id, c);
  }
  return [...ids.values()];
}

/**
 * As cobranças formais abertas das contas e OS escolhidas — para avisar ANTES do botão quais contas
 * ganham cobrança no envio (contasSemCobranca + avisoDaCobrancaCriada).
 */
export function useCobrancasFormais(contaIds: string[], servicoIds: string[], enabled = true) {
  return useQuery({
    queryKey: ['collections', 'cobrar-juntas', [...contaIds].sort(), [...servicoIds].sort()],
    enabled: enabled && (contaIds.length > 0 || servicoIds.length > 0),
    queryFn: () => lerCobrancasAbertas(contaIds, servicoIds),
    staleTime: 30 * 1000,
  });
}

interface Conferencia {
  cliente: { id: string; name?: string | null; generico?: boolean | null };
  mensagem: string;
  contas: Array<{ id: string; saldo: number }>;
  /** As OS escolhidas (Cobrar juntas); null = o cliente inteiro ("Enviar extrato"). */
  servicoIds: string[] | null;
  tipo: 'cobrar-juntas' | 'extrato';
}

/**
 * As travas de novo, com dado fresco, e o envio. Recusa = LANÇA com a frase pronta (nada saiu).
 * Devolve se o whatsapp-send deduplicou e se desviou para o número de teste.
 */
async function conferirEEnviar(e: Conferencia): Promise<{ deduplicado: boolean; modoTeste: boolean }> {
  // A coluna generico é pedida pelo nome: sem a migration 20261028190000 a leitura falha e nada sai
  // (falha fechada, como a tool cobrar_juntas) — com select('*') o "Cliente Final" passaria.
  // O destino é SEMPRE o WhatsApp (ou telefone) do cadastro, relido aqui — como a tool: cobrança a
  // número digitado expõe a dívida a terceiro (CDC; compliance-guard, destinatário identificado).
  const { data: cli, error: cliErr } = await supabase.from('clients')
    .select('name, opt_out_whatsapp, generico, whatsapp, phone').eq('id', e.cliente.id).maybeSingle();
  if (cliErr || !cli) throw new Error(`Não consegui ler o cadastro do cliente${cliErr ? `: ${cliErr.message}` : ''}.`);
  const c = cli as {
    name?: string | null; opt_out_whatsapp?: boolean | null; generico?: boolean | null;
    whatsapp?: string | null; phone?: string | null;
  };

  // As contas relidas (a ficha guarda em cache por até 1 min e não relê ao voltar para a aba): Pix
  // aplicado em outra aba não pode virar cobrança de conta já paga. Só as do cliente (o titular).
  let consulta = supabase.from('receivables')
    .select('id, status, amount, paid_amount, balance_amount')
    .eq('client_id', e.cliente.id);
  if (e.servicoIds) consulta = consulta.in('service_order_id', e.servicoIds);
  const { data: contasAgora, error: contasErr } = await consulta;
  if (contasErr) throw new Error(`Não consegui conferir o saldo ${e.servicoIds ? 'das OS' : 'do cliente'}: ${contasErr.message}`);
  const mudou = mudancaNasContas(e.contas, (contasAgora ?? []) as Parameters<typeof mudancaNasContas>[1], e.tipo);
  if (mudou) throw new Error(mudou);

  const [piso, pix, modoTeste] = await Promise.all([lerPiso(), lerPixEsperando(e.cliente.id), lerDesvioDeTeste()]);
  const telefoneDoCadastro = c.whatsapp || c.phone || '';
  const trava = travaDoCobrarJuntas({
    clienteNome: c.name ?? e.cliente.name,
    generico: c.generico === true || e.cliente.generico === true,
    quantidadeOs: e.servicoIds ? e.servicoIds.length : null,
    optOut: c.opt_out_whatsapp,
    piso,
    totalEmAberto: e.contas.reduce((s, x) => s + x.saldo, 0),
    pixEsperando: pix,
    telefone: telefoneDoCadastro,
    horaBrasilia: horaDoCobrarJuntas(),
  });
  if (trava) throw new Error(trava);

  const telefone = normalizePhoneE164(telefoneDoCadastro, '55');
  const { data, error } = await supabase.functions.invoke('whatsapp-send', {
    body: {
      phone: telefone,
      message: e.mensagem,
      context: 'billing',
      kind: 'text',
      // Desviado pelo modo de teste, a chave ganha ":teste" (a mesma da tool): o teste não
      // reserva a chave do cliente para o dia.
      dedupe_key: chaveDoCobrarJuntas(e.cliente.id, e.contas.map((x) => x.id), hojeLocal(), e.mensagem, modoTeste, e.tipo),
    },
  });
  if (error) throw new Error(await extractInvokeErrorMessage(error));
  const res = (data ?? {}) as { error?: string; success?: boolean; deduplicated?: boolean };
  if (res.error) throw new Error(res.error);
  if (res.success === false) throw new Error('O WhatsApp não confirmou o envio.');
  return { deduplicado: !!res.deduplicated, modoTeste };
}

/**
 * Depois do envio confirmado: cria a cobrança das contas que não têm e registra o envio em todas
 * (cobrar_juntas_registrar_envio, tudo ou nada). Não lança: a mensagem já saiu.
 */
async function registrarNoBanco(e: EnvioCobrarJuntas): Promise<{ criadas: number; registradas: number; erro: string | null }> {
  const { data, error } = await supabase.rpc('cobrar_juntas_registrar_envio', {
    p_cliente: e.cliente.id,
    p_contas: e.contas.map((x) => x.id),
    p_os: e.servicoIds,
    p_nota: 'Cobrar juntas (várias OS numa mensagem)',
  });
  if (error) return { criadas: 0, registradas: 0, erro: error.message };
  const r = (data ?? {}) as { criadas?: number; registradas?: number };
  return { criadas: Number(r.criadas) || 0, registradas: Number(r.registradas) || 0, erro: null };
}

export function useEnviarCobrarJuntas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (e: EnvioCobrarJuntas): Promise<ResultadoCobrarJuntas> => {
      const envio = await conferirEEnviar({ ...e, tipo: 'cobrar-juntas' });
      const vazio = { cobrancasRegistradas: 0, cobrancasCriadas: 0 };
      if (envio.deduplicado) {
        return { deduplicado: true, ...vazio, aviso: null, ...(envio.modoTeste ? { modoTeste: true } : {}) };
      }
      // Foi para o número de teste: nada se cria nem se registra — o cliente não recebeu, e o
      // last_auto_sent_at faria o plano de inadimplência achar que ele já foi cobrado hoje.
      if (envio.modoTeste) return { deduplicado: false, ...vazio, aviso: AVISO_MODO_TESTE, modoTeste: true };

      const r = await registrarNoBanco(e);
      return {
        deduplicado: false,
        cobrancasRegistradas: r.registradas,
        cobrancasCriadas: r.criadas,
        aviso: r.erro
          ? `A mensagem foi enviada, mas não consegui criar/registrar a cobrança (${r.erro}). Nada foi gravado nas cobranças: `
            + 'confira em Cobranças antes de cobrar este cliente de novo hoje.'
          : null,
      };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['collections'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
    },
    // Recusa ou falha: o dado que a tela mostrou pode estar velho (o caso do "saldo mudou desde que
    // a tela abriu"). Sem invalidar, a ficha (sem refetch ao voltar para a aba) reabria o Cobrar
    // juntas com os saldos antigos e a recusa se repetia até recarregar a página.
    onError: () => invalidarDepoisDaRecusa(qc),
  });
}

function invalidarDepoisDaRecusa(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['receivables'] });
  qc.invalidateQueries({ queryKey: ['collections'] });
  qc.invalidateQueries({ queryKey: ['finance-review', 'pix-esperando'] });
  qc.invalidateQueries({ queryKey: ['app-settings'] });
}

export interface EnvioDoExtrato {
  cliente: { id: string; name?: string | null; generico?: boolean | null };
  mensagem: string;
  /** As contas com saldo do cliente, com o saldo que a tela mostrou (o envio relê e recusa se mudou). */
  contas: Array<{ id: string; saldo: number }>;
}

export interface ResultadoDoExtrato {
  deduplicado: boolean;
  aviso: string | null;
  modoTeste?: boolean;
}

/** Aviso da tela quando o extrato foi desviado pelo modo de teste. */
export const AVISO_MODO_TESTE_EXTRATO =
  'O modo de teste do WhatsApp está ligado: o extrato foi para o número de teste, não para o cliente.';

/**
 * "Enviar extrato" da ficha do cliente com as travas do Cobrar juntas (dono, 20/11/2026): o mesmo
 * conferirEEnviar, com o cliente inteiro. Não cria nem registra cobrança.
 */
export function useEnviarExtrato() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (e: EnvioDoExtrato): Promise<ResultadoDoExtrato> => {
      const envio = await conferirEEnviar({ ...e, servicoIds: null, tipo: 'extrato' });
      if (envio.modoTeste) {
        return { deduplicado: envio.deduplicado, aviso: envio.deduplicado ? null : AVISO_MODO_TESTE_EXTRATO, modoTeste: true };
      }
      return { deduplicado: envio.deduplicado, aviso: null };
    },
    onError: () => invalidarDepoisDaRecusa(qc),
  });
}
