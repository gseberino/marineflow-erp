// "Cobrar juntas" (Fase 0 do Fechar juntas, 28/10/2026): uma mensagem com o saldo de várias OS do
// mesmo cliente. Sem banco novo: é o extrato filtrado (buildClientStatement com servicoIds).
//
// O envio passa pelas MESMAS travas do send_collection_reminder do assistente — a regra mora em
// _shared/receivables/cobrar-juntas.ts e vale para os dois. O extrato antigo chamava o whatsapp-send
// direto, sem opt-out, sem "Pix esperando no Extrato" e sem piso, e não gravava last_auto_sent_at
// (que o assistente lê para não cobrar de novo no mesmo dia). Na hora do envio, relê o cadastro (o
// destino é o WhatsApp dele, nunca um número digitado), as contas das OS (saldo mudou = não envia) e
// confere o horário de cobrança (8h–20h em Brasília), como o portão do assistente.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { extractInvokeErrorMessage } from '@/lib/invoke-error';
import { normalizePhoneE164 } from '@/lib/masks';
import {
  chaveDoCobrarJuntas, hojeLocal, horaEmBrasilia, mudancaNasContas, SEM_COBRANCA_FORMAL, travaDoCobrarJuntas,
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

/** Para mostrar a trava ANTES do botão. O envio relê tudo na hora (useEnviarCobrarJuntas). */
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
  aviso: string | null;
  /** O modo de teste desviou o envio para o número de teste: o cliente NÃO recebeu. */
  modoTeste?: boolean;
}

/** Aviso da tela quando o envio foi desviado pelo modo de teste. */
export const AVISO_MODO_TESTE =
  'O modo de teste do WhatsApp está ligado: a mensagem foi para o número de teste, não para o cliente. Nada foi registrado nas cobranças.';

type Cob = { id: string; status: string | null };

/**
 * As cobranças formais (collections) abertas das contas escolhidas: pela conta, ou só pela OS (sem
 * conta). Duas leituras em vez de .or() (vírgula em filtro .or() já quebrou consulta aqui). LANÇA.
 */
async function lerCobrancasAbertas(contaIds: string[], servicoIds: string[]): Promise<Cob[]> {
  const ids = new Map<string, Cob>();
  if (contaIds.length) {
    const { data, error } = await supabase.from('collections').select('id, status')
      .in('receivable_id', contaIds).not('status', 'in', '(paid,cancelled)');
    if (error) throw new Error(error.message);
    for (const c of (data ?? []) as Cob[]) ids.set(c.id, c);
  }
  if (servicoIds.length) {
    const { data, error } = await supabase.from('collections').select('id, status')
      .in('service_order_id', servicoIds).is('receivable_id', null).not('status', 'in', '(paid,cancelled)');
    if (error) throw new Error(error.message);
    for (const c of (data ?? []) as Cob[]) ids.set(c.id, c);
  }
  return [...ids.values()];
}

/**
 * Quantas cobranças formais recebem o registro do envio — para avisar ANTES do botão quando não há
 * nenhuma (SEM_COBRANCA_FORMAL): aí o envio não fica registrado e o plano de inadimplência não o vê.
 */
export function useCobrancasFormais(contaIds: string[], servicoIds: string[], enabled = true) {
  return useQuery({
    queryKey: ['collections', 'cobrar-juntas', [...contaIds].sort(), [...servicoIds].sort()],
    enabled: enabled && (contaIds.length > 0 || servicoIds.length > 0),
    queryFn: async () => (await lerCobrancasAbertas(contaIds, servicoIds)).length,
    staleTime: 30 * 1000,
  });
}

/**
 * Registra o envio nas cobranças das contas escolhidas, como registrarEnvioDaCobranca
 * (_shared/ai/tools/cobrancas.ts): contato 'whatsapp_sent' + situação 'sent' + last_auto_sent_at.
 */
async function registrarNasCobrancas(contaIds: string[], servicoIds: string[]): Promise<{ n: number; erro: string | null }> {
  let cobrancas: Cob[];
  try {
    cobrancas = await lerCobrancasAbertas(contaIds, servicoIds);
  } catch (e) {
    return { n: 0, erro: (e as Error).message };
  }
  const agora = new Date().toISOString();
  let n = 0;
  for (const c of cobrancas) {
    const contato = await supabase.from('collection_contacts').insert({
      collection_id: c.id, contact_type: 'whatsapp_sent', notes: 'Cobrar juntas (várias OS numa mensagem)',
    } as never);
    const situacao = await supabase.from('collections').update({ status: 'sent', last_auto_sent_at: agora } as never).eq('id', c.id);
    const erro = contato.error ?? situacao.error;
    if (erro) return { n, erro: erro.message };
    n++;
  }
  return { n, erro: null };
}

export function useEnviarCobrarJuntas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (e: EnvioCobrarJuntas): Promise<ResultadoCobrarJuntas> => {
      // As travas de novo, com dado fresco: o que a tela mostrou pode ter mudado. A coluna generico
      // é pedida pelo nome: sem a migration 20261028190000 a leitura falha e nada sai (falha fechada,
      // como a tool cobrar_juntas) — com select('*') o "Cliente Final" passaria sem a recusa.
      // O destino é SEMPRE o WhatsApp (ou telefone) do cadastro, relido aqui — como a tool: cobrança a
      // número digitado expõe a dívida a terceiro (CDC; compliance-guard, destinatário identificado).
      const { data: cli, error: cliErr } = await supabase.from('clients')
        .select('name, opt_out_whatsapp, generico, whatsapp, phone').eq('id', e.cliente.id).maybeSingle();
      if (cliErr || !cli) throw new Error(`Não consegui ler o cadastro do cliente${cliErr ? `: ${cliErr.message}` : ''}.`);
      const c = cli as {
        name?: string | null; opt_out_whatsapp?: boolean | null; generico?: boolean | null;
        whatsapp?: string | null; phone?: string | null;
      };

      // As contas das OS escolhidas, relidas (a ficha guarda em cache por até 1 min e não relê ao
      // voltar para a aba): Pix aplicado em outra aba não pode virar cobrança de conta já paga.
      const { data: contasAgora, error: contasErr } = await supabase.from('receivables')
        .select('id, status, amount, paid_amount, balance_amount')
        .eq('client_id', e.cliente.id).in('service_order_id', e.servicoIds);
      if (contasErr) throw new Error(`Não consegui conferir o saldo das OS: ${contasErr.message}`);
      const mudou = mudancaNasContas(e.contas, (contasAgora ?? []) as Parameters<typeof mudancaNasContas>[1]);
      if (mudou) throw new Error(mudou);

      const [piso, pix, modoTeste] = await Promise.all([lerPiso(), lerPixEsperando(e.cliente.id), lerDesvioDeTeste()]);
      const telefoneDoCadastro = c.whatsapp || c.phone || '';
      const trava = travaDoCobrarJuntas({
        clienteNome: c.name ?? e.cliente.name,
        generico: c.generico === true || e.cliente.generico === true,
        quantidadeOs: e.servicoIds.length,
        optOut: c.opt_out_whatsapp,
        piso,
        totalEmAberto: e.contas.reduce((s, x) => s + x.saldo, 0),
        pixEsperando: pix,
        telefone: telefoneDoCadastro,
        horaBrasilia: horaDoCobrarJuntas(),
      });
      if (trava) throw new Error(trava);

      const telefone = normalizePhoneE164(telefoneDoCadastro, '55');
      const contaIds = e.contas.map((x) => x.id);
      const { data, error } = await supabase.functions.invoke('whatsapp-send', {
        body: {
          phone: telefone,
          message: e.mensagem,
          context: 'billing',
          kind: 'text',
          // Desviado pelo modo de teste, a chave ganha ":teste" (a mesma da tool): o teste não
          // reserva a chave do cliente para o dia.
          dedupe_key: chaveDoCobrarJuntas(e.cliente.id, contaIds, hojeLocal(), e.mensagem, modoTeste),
        },
      });
      if (error) throw new Error(await extractInvokeErrorMessage(error));
      const res = (data ?? {}) as { error?: string; success?: boolean; deduplicated?: boolean };
      if (res.error) throw new Error(res.error);
      if (res.success === false) throw new Error('O WhatsApp não confirmou o envio.');
      if (res.deduplicated) return { deduplicado: true, cobrancasRegistradas: 0, aviso: null, ...(modoTeste ? { modoTeste } : {}) };
      // Foi para o número de teste: nada se registra nas cobranças — o cliente não recebeu, e o
      // last_auto_sent_at faria o plano de inadimplência achar que ele já foi cobrado hoje.
      if (modoTeste) return { deduplicado: false, cobrancasRegistradas: 0, aviso: AVISO_MODO_TESTE, modoTeste };

      const r = await registrarNasCobrancas(contaIds, e.servicoIds);
      return {
        deduplicado: false,
        cobrancasRegistradas: r.n,
        aviso: r.erro
          ? `A mensagem foi enviada, mas não consegui registrar o envio nas cobranças (${r.erro}).`
          : r.n === 0
          ? `A mensagem foi enviada. ${SEM_COBRANCA_FORMAL}`
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
    onError: () => {
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['collections'] });
      qc.invalidateQueries({ queryKey: ['finance-review', 'pix-esperando'] });
      qc.invalidateQueries({ queryKey: ['app-settings'] });
    },
  });
}
