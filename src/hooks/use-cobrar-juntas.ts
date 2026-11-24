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
// (conferirEEnviar) com o cliente inteiro — sem contagem de OS e chave do dia com prefixo 'extrato'.
// Respostas do dono (20/11/2026): sem nada em aberto, o extrato SAI como comprovante de quitação
// (travaDoExtrato: só genérico, opt-out, telefone e horário) e não é cobrança; COM saldo, ele "conta
// como cobrança do dia" — depois do envio confirmado passa pela mesma cobrar_juntas_registrar_envio,
// com p_os nulo (o cliente inteiro), e entra na regra "1 por dia" (last_auto_sent_at).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { extractInvokeErrorMessage } from '@/lib/invoke-error';
import { normalizePhoneE164 } from '@/lib/masks';
import {
  chaveDoCobrarJuntas, hojeLocal, horaEmBrasilia, mudancaNasContas, travaDoCobrarJuntas, travaDoExtrato,
} from '../../supabase/functions/_shared/receivables/cobrar-juntas';
import { lerDinheiroEsperando } from '../../supabase/functions/_shared/receivables/dinheiro-esperando';
import { desviadoPorTeste } from '../../supabase/functions/_shared/whatsapp/marcar-enviado';
import { criarFaturaParaCobrar } from '@/hooks/use-faturas';
import { colocarNumeroDaFatura } from '@/lib/fatura';

/** O relógio da tela (horário de cobrança) — os testes trocam, como relogioDoCobrarJuntas da tool. */
export const relogioDoCobrarJuntasTela = { agora: () => new Date() };

/** Hora em Brasília agora, pelo relógio da tela. */
export function horaDoCobrarJuntas(): number {
  return horaEmBrasilia(relogioDoCobrarJuntasTela.agora());
}

export interface PixEsperando { valor: number; data: string | null }

/**
 * Pix do cliente parado no Extrato esperando decisão — a MESMA leitura do assistente (pix-esperando.ts), pela mesma
 * função (24/11/2026): contam as entradas que a fila identificou como dele e as que o vínculo sugerido aponta para
 * uma conta aberta dele (os boletos da Apolo estavam na fila sem cliente e passavam pela trava). Leitura que falha
 * LANÇA: "nenhum Pix esperando" por erro mandaria cobrar quem pagou.
 */
async function lerPixEsperando(clientId: string): Promise<PixEsperando[]> {
  const todas = await lerDinheiroEsperando(supabase);
  return todas.filter((e) => e.clienteId === clientId).map((e) => ({ valor: e.valor, data: e.data }));
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
  /**
   * Fechar juntas F1 (20/11/2026): as OS escolhidas estão todas executadas, então as contas viram a fatura
   * FAT-N. Depois das travas e ANTES do WhatsApp, fatura_criar cria a fatura (ou acha a que já existe com
   * essas contas) e o número entra no lugar de NUMERO_DA_FATURA_NOVA na mensagem. Se o banco recusar,
   * nada sai. Se o WhatsApp falhar depois, a fatura fica (aparece na ficha; o próximo envio usa a mesma).
   */
  comFatura?: boolean;
}

export interface ResultadoCobrarJuntas {
  deduplicado: boolean;
  cobrancasRegistradas: number;
  /** Cobranças criadas junto com o envio (contas que não tinham nenhuma). */
  cobrancasCriadas: number;
  aviso: string | null;
  /** O modo de teste desviou o envio para o número de teste: o cliente NÃO recebeu. */
  modoTeste?: boolean;
  /** A fatura das contas (FAT-N), quando o envio foi com fatura. */
  fatura?: string | null;
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
  /**
   * Roda depois de todas as travas e antes do WhatsApp, e devolve a mensagem final (a fatura do
   * Cobrar juntas põe o número FAT-N nela). Se lançar, nada sai.
   */
  antesDoEnvio?: (mensagem: string, contexto: { modoTeste: boolean }) => Promise<string>;
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

  const totalEmAberto = e.contas.reduce((s, x) => s + x.saldo, 0);
  // Comprovante de quitação (extrato sem nada em aberto): piso e Pix esperando não se aplicam, e uma
  // leitura deles que falhe não pode barrar o comprovante.
  const quitacao = e.tipo === 'extrato' && !(totalEmAberto > 0);
  const [piso, pix, modoTeste] = await Promise.all([
    quitacao ? Promise.resolve(0) : lerPiso(),
    quitacao ? Promise.resolve([] as PixEsperando[]) : lerPixEsperando(e.cliente.id),
    lerDesvioDeTeste(),
  ]);
  const telefoneDoCadastro = c.whatsapp || c.phone || '';
  const entrada = {
    clienteNome: c.name ?? e.cliente.name,
    generico: c.generico === true || e.cliente.generico === true,
    optOut: c.opt_out_whatsapp,
    piso,
    totalEmAberto,
    pixEsperando: pix,
    telefone: telefoneDoCadastro,
    horaBrasilia: horaDoCobrarJuntas(),
  };
  const trava = e.tipo === 'extrato'
    ? travaDoExtrato({
      ...entrada,
      lancamentos: ((contasAgora ?? []) as Array<{ status?: string | null }>).filter((x) => x.status !== 'cancelled').length,
    })
    : travaDoCobrarJuntas({ ...entrada, quantidadeOs: e.servicoIds ? e.servicoIds.length : null });
  if (trava) throw new Error(trava);

  // Fatura (Fechar juntas F1): depois das travas e antes do WhatsApp. Se lançar, nada sai.
  const mensagem = e.antesDoEnvio ? await e.antesDoEnvio(e.mensagem, { modoTeste }) : e.mensagem;

  const telefone = normalizePhoneE164(telefoneDoCadastro, '55');
  const { data, error } = await supabase.functions.invoke('whatsapp-send', {
    body: {
      phone: telefone,
      message: mensagem,
      context: 'billing',
      kind: 'text',
      // Desviado pelo modo de teste, a chave ganha ":teste" (a mesma da tool): o teste não
      // reserva a chave do cliente para o dia.
      dedupe_key: chaveDoCobrarJuntas(e.cliente.id, e.contas.map((x) => x.id), hojeLocal(), mensagem, modoTeste, e.tipo),
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
async function registrarNoBanco(
  e: { cliente: { id: string }; contas: Array<{ id: string }> },
  servicoIds: string[] | null,
  nota: string,
): Promise<{ criadas: number; registradas: number; erro: string | null }> {
  const { data, error } = await supabase.rpc('cobrar_juntas_registrar_envio', {
    p_cliente: e.cliente.id,
    p_contas: e.contas.map((x) => x.id),
    // null = o cliente inteiro ("Enviar extrato"): as contas só precisam ser do cliente.
    p_os: servicoIds,
    p_nota: nota,
  });
  if (error) return { criadas: 0, registradas: 0, erro: error.message };
  const r = (data ?? {}) as { criadas?: number; registradas?: number };
  return { criadas: Number(r.criadas) || 0, registradas: Number(r.registradas) || 0, erro: null };
}

export function useEnviarCobrarJuntas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (e: EnvioCobrarJuntas): Promise<ResultadoCobrarJuntas> => {
      const doEnvio: { fatura: string | null } = { fatura: null };
      const envio = await conferirEEnviar({
        ...e,
        tipo: 'cobrar-juntas',
        antesDoEnvio: e.comFatura
          ? async (mensagem, { modoTeste }) => {
            // Modo de teste: nada se cria (como as cobranças); o número de teste vê o provisório.
            if (modoTeste) return colocarNumeroDaFatura(mensagem, 'FAT-(teste)');
            const f = await criarFaturaParaCobrar(e.cliente.id, e.contas.map((x) => x.id));
            doEnvio.fatura = f.numero;
            return colocarNumeroDaFatura(mensagem, f.numero);
          }
          : undefined,
      });
      const vazio = { cobrancasRegistradas: 0, cobrancasCriadas: 0, ...(doEnvio.fatura ? { fatura: doEnvio.fatura } : {}) };
      if (envio.deduplicado) {
        return { deduplicado: true, ...vazio, aviso: null, ...(envio.modoTeste ? { modoTeste: true } : {}) };
      }
      // Foi para o número de teste: nada se cria nem se registra — o cliente não recebeu, e o
      // last_auto_sent_at faria o plano de inadimplência achar que ele já foi cobrado hoje.
      if (envio.modoTeste) return { deduplicado: false, ...vazio, aviso: AVISO_MODO_TESTE, modoTeste: true };

      const r = await registrarNoBanco(e, e.servicoIds, 'Cobrar juntas (várias OS numa mensagem)');
      return {
        deduplicado: false,
        cobrancasRegistradas: r.registradas,
        cobrancasCriadas: r.criadas,
        ...(doEnvio.fatura ? { fatura: doEnvio.fatura } : {}),
        aviso: r.erro
          ? `A mensagem foi enviada, mas não consegui criar/registrar a cobrança (${r.erro}). Nada foi gravado nas cobranças: `
            + 'confira em Cobranças antes de cobrar este cliente de novo hoje.'
          : null,
      };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['collections'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['faturas'] });
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
  // A fatura pode ter nascido antes de o WhatsApp falhar: a ficha mostra.
  qc.invalidateQueries({ queryKey: ['faturas'] });
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
  /** Saiu sem nada em aberto: comprovante de quitação (não é cobrança, nada registrado). */
  quitacao?: boolean;
  /** Com saldo: cobranças que receberam o registro do envio (a cobrança do dia). */
  cobrancasRegistradas?: number;
  /** Com saldo: cobranças criadas junto (contas que não tinham nenhuma). */
  cobrancasCriadas?: number;
}

/** Aviso da tela quando o extrato foi desviado pelo modo de teste. */
export const AVISO_MODO_TESTE_EXTRATO =
  'O modo de teste do WhatsApp está ligado: o extrato foi para o número de teste, não para o cliente.';

/** A nota do contato 'whatsapp_sent' que o extrato com saldo deixa em cada cobrança. */
export const NOTA_DO_EXTRATO = 'Extrato do cliente com saldo (Enviar extrato)';

/**
 * "Enviar extrato" da ficha do cliente com as travas do Cobrar juntas (dono, 20/11/2026): o mesmo
 * conferirEEnviar, com o cliente inteiro. Sem nada em aberto sai como comprovante de quitação e não
 * registra nada. Com saldo conta como a cobrança do dia: depois do envio confirmado (não desviado
 * pelo modo de teste, não "já enviado hoje"), cobrar_juntas_registrar_envio com p_os nulo cria a
 * cobrança das contas que não têm e registra o envio em todas (last_auto_sent_at de hoje).
 */
export function useEnviarExtrato() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (e: EnvioDoExtrato): Promise<ResultadoDoExtrato> => {
      const envio = await conferirEEnviar({ ...e, servicoIds: null, tipo: 'extrato' });
      const quitacao = e.contas.length === 0;
      const base = { deduplicado: envio.deduplicado, ...(quitacao ? { quitacao: true } : {}) };
      if (envio.modoTeste) {
        return { ...base, aviso: envio.deduplicado ? null : AVISO_MODO_TESTE_EXTRATO, modoTeste: true };
      }
      if (envio.deduplicado || quitacao) return { ...base, aviso: null };

      const r = await registrarNoBanco(e, null, NOTA_DO_EXTRATO);
      return {
        ...base,
        cobrancasRegistradas: r.registradas,
        cobrancasCriadas: r.criadas,
        aviso: r.erro
          ? `O extrato foi enviado, mas não consegui registrar a cobrança do dia (${r.erro}). Nada foi gravado nas cobranças: `
            + 'confira em Cobranças antes de cobrar este cliente de novo hoje.'
          : null,
      };
    },
    onSuccess: (r) => {
      if (r.cobrancasRegistradas || r.cobrancasCriadas) {
        qc.invalidateQueries({ queryKey: ['collections'] });
        qc.invalidateQueries({ queryKey: ['receivables'] });
      }
    },
    onError: () => invalidarDepoisDaRecusa(qc),
  });
}
