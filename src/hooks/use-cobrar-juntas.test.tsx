// Envio do "Cobrar juntas" (Fase 0, 28/10/2026): as travas são relidas na hora do envio (o que a tela
// mostrou pode ter mudado), a chave de idempotência vai junto e o envio fica registrado nas cobranças
// das contas escolhidas — como o lembrete do assistente faz (last_auto_sent_at).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

type Resposta = { data: unknown; error: { message: string } | null };

const banco = vi.hoisted(() => ({
  respostas: {} as Record<string, Resposta | Resposta[]>,
  chamadas: [] as Array<{ alvo: string; op: string; valores?: unknown; filtros: unknown[][] }>,
  invocacoes: [] as Array<{ nome: string; body: Record<string, unknown> }>,
  envio: { data: { success: true }, error: null } as Resposta,
}));

function responder(chave: string): Resposta {
  const r = banco.respostas[chave];
  if (Array.isArray(r)) return r.length > 1 ? r.shift()! : r[0];
  return r ?? { data: null, error: null };
}

vi.mock('@/integrations/supabase/client', () => {
  const consulta = (tabela: string) => {
    const registro = { alvo: tabela, op: 'select', valores: undefined as unknown, filtros: [] as unknown[][] };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const q: any = {};
    for (const m of ['select', 'eq', 'not', 'in', 'is', 'range', 'limit', 'order', 'gte']) {
      q[m] = (...a: unknown[]) => { registro.filtros.push([m, ...a]); return q; };
    }
    q.update = (v: unknown) => { registro.op = 'update'; registro.valores = v; return q; };
    q.insert = (v: unknown) => { registro.op = 'insert'; registro.valores = v; return q; };
    q.maybeSingle = () => q;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    q.then = (ok: any, erro: any) => {
      banco.chamadas.push(registro);
      // A leitura do modo de teste (app_settings por lista de chaves) tem resposta própria; o piso
      // (uma chave só) segue em 'app_settings.select'.
      const modoTeste = tabela === 'app_settings' && registro.filtros.some((f) => f[0] === 'in' && f[1] === 'key');
      return Promise.resolve(responder(modoTeste ? 'app_settings.select:modo-teste' : `${tabela}.${registro.op}`)).then(ok, erro);
    };
    return q;
  };
  return {
    supabase: {
      from: (t: string) => consulta(t),
      // cobrar_juntas_registrar_envio (20/11/2026): cria a cobrança que falta e registra o envio, no banco.
      rpc: (fn: string, args: unknown) => {
        banco.chamadas.push({ alvo: `rpc.${fn}`, op: 'rpc', valores: args, filtros: [] });
        return Promise.resolve(responder(`rpc.${fn}`));
      },
      functions: {
        invoke: (nome: string, o: { body: Record<string, unknown> }) => {
          banco.invocacoes.push({ nome, body: o.body });
          return Promise.resolve(banco.envio);
        },
      },
    },
  };
});

import {
  AVISO_MODO_TESTE, AVISO_MODO_TESTE_EXTRATO, NOTA_DA_COBRANCA_DO_CLIENTE, NOTA_DO_EXTRATO, avisoDeCobradoHoje,
  enviarCobrancaDoCliente, lerCobradosHoje, relogioDoCobrarJuntasTela, useCobrancasFormais, useEnviarCobrarJuntas,
  useEnviarExtrato,
} from './use-cobrar-juntas';
import { NUMERO_DA_FATURA_NOVA } from '@/lib/fatura';

const ok = (data: unknown): Resposta => ({ data, error: null });

// 28/10/2026 às 14h em Brasília: dentro do horário de cobrança.
const AS_14H = () => new Date('2026-10-28T17:00:00Z');

/** As contas das OS como estão no banco na hora do envio (iguais ao que a tela mostrou). */
const CONTAS_NO_BANCO = [
  { id: 'r45', status: 'pending', amount: 1650, paid_amount: 0, balance_amount: 1650 },
  { id: 'r46', status: 'partially_paid', amount: 50, paid_amount: 30, balance_amount: 20 },
  { id: 's45', status: 'paid', amount: 500, paid_amount: 500, balance_amount: 0 },
];

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

const ENVIO = {
  cliente: { id: 'cli', name: 'MP MOTOR HOMES' },
  mensagem: 'Cobrança — HBR …',
  contas: [{ id: 'r45', saldo: 1650 }, { id: 'r46', saldo: 20 }],
  servicoIds: ['os45', 'os46'],
};

async function enviar(e = ENVIO, qc?: QueryClient) {
  const comCliente = qc
    ? ({ children }: { children: ReactNode }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>
    : wrapper;
  const { result } = renderHook(() => useEnviarCobrarJuntas(), { wrapper: comCliente });
  result.current.mutate(e);
  await waitFor(() => expect(result.current.isSuccess || result.current.isError).toBe(true));
  return result.current;
}

beforeEach(() => {
  relogioDoCobrarJuntasTela.agora = AS_14H;
  banco.respostas = {
    'clients.select': ok({ name: 'MP MOTOR HOMES', opt_out_whatsapp: false, generico: false, whatsapp: '(47) 99999-0000', phone: null }),
    'receivables.select': ok(CONTAS_NO_BANCO),
    'app_settings.select': ok({ value: '0' }),
    'app_settings.select:modo-teste': ok([{ key: 'wa_test_mode', value: 'false' }]),
    'finance_review_queue.select': ok([]),
    // 1ª leitura: cobranças das contas; 2ª: cobrança só com a OS (useCobrancasFormais).
    'collections.select': [
      ok([{ id: 'col45', status: 'pending', receivable_id: 'r45', service_order_id: 'os45' }]),
      ok([{ id: 'colOs46', status: 'sent', receivable_id: null, service_order_id: 'os46' }]),
    ],
    'rpc.cobrar_juntas_registrar_envio': ok({ criadas: 0, registradas: 2, cobrancas_criadas: [] }),
  };
  banco.chamadas = [];
  banco.invocacoes = [];
  banco.envio = { data: { success: true }, error: null };
});

describe('useEnviarCobrarJuntas', () => {
  it('envia com chave de idempotência e registra pelo banco (cobrar_juntas_registrar_envio) DEPOIS do envio', async () => {
    const r = await enviar();
    expect(r.isSuccess).toBe(true);
    expect(r.data).toEqual({ deduplicado: false, cobrancasRegistradas: 2, cobrancasCriadas: 0, aviso: null });
    expect(banco.invocacoes).toHaveLength(1);
    const body = banco.invocacoes[0].body;
    expect(body).toMatchObject({ phone: '5547999990000', context: 'billing', kind: 'text' });
    expect(String(body.dedupe_key)).toMatch(/^cobrar-juntas:cli:\d{4}-\d{2}-\d{2}:/);

    // As contas relidas são as das OS escolhidas e do mesmo cliente (o que a ficha mostra).
    const contas = banco.chamadas.find((c) => c.alvo === 'receivables');
    expect(contas?.filtros).toContainEqual(['eq', 'client_id', 'cli']);
    expect(contas?.filtros).toContainEqual(['in', 'service_order_id', ['os45', 'os46']]);

    // Registro: uma chamada só à função do banco (tudo ou nada), com o cliente, as contas e as OS — e só
    // depois do envio. Nada é gravado direto em collections/collection_contacts pela tela.
    const ordem = banco.chamadas.map((c) => c.alvo);
    expect(ordem.filter((a) => a.startsWith('rpc.'))).toEqual(['rpc.cobrar_juntas_registrar_envio']);
    const rpc = banco.chamadas.find((c) => c.alvo === 'rpc.cobrar_juntas_registrar_envio');
    expect(rpc?.valores).toEqual({
      p_cliente: 'cli', p_contas: ['r45', 'r46'], p_os: ['os45', 'os46'], p_nota: 'Cobrar juntas (várias OS numa mensagem)',
    });
    expect(banco.chamadas.filter((c) => c.alvo === 'collection_contacts' || (c.alvo === 'collections' && c.op !== 'select'))).toEqual([]);
  });

  it('a mensagem não saiu (erro do WhatsApp): a função do banco nem é chamada — nenhuma cobrança criada', async () => {
    banco.envio = { data: { error: 'provedor fora do ar' }, error: null };
    const r = await enviar();
    expect(r.isError).toBe(true);
    expect((r.error as Error).message).toContain('provedor fora do ar');
    expect(banco.chamadas.filter((c) => c.alvo.startsWith('rpc.'))).toEqual([]);
  });

  it('saldo mudou desde que a tela abriu (Pix aplicado em outra aba) → não envia', async () => {
    banco.respostas['receivables.select'] = ok(CONTAS_NO_BANCO.map((c) => c.id === 'r45' ? { ...c, status: 'paid', paid_amount: 1650, balance_amount: 0 } : c));
    const r = await enviar();
    expect(r.isError).toBe(true);
    expect((r.error as Error).message).toContain('As contas em aberto destas OS mudaram desde que a tela abriu');
    expect(banco.invocacoes).toEqual([]);

    banco.respostas['receivables.select'] = ok(CONTAS_NO_BANCO.map((c) => c.id === 'r46' ? { ...c, paid_amount: 40, balance_amount: 10 } : c));
    expect(((await enviar()).error as Error).message).toContain('O saldo das OS mudou desde que a tela abriu');
    expect(banco.invocacoes).toEqual([]);
  });

  it('conta nova com saldo entrou numa das OS → não envia', async () => {
    banco.respostas['receivables.select'] = ok([...CONTAS_NO_BANCO, { id: 'r46x', status: 'pending', amount: 35, paid_amount: 0, balance_amount: 35 }]);
    expect(((await enviar()).error as Error).message).toContain('mudaram desde que a tela abriu');
    expect(banco.invocacoes).toEqual([]);
  });

  it('leitura das contas que falha não envia', async () => {
    banco.respostas['receivables.select'] = { data: null, error: { message: 'timeout' } };
    expect(((await enviar()).error as Error).message).toContain('Não consegui conferir o saldo das OS: timeout');
    expect(banco.invocacoes).toEqual([]);
  });

  it('o destino é o WhatsApp do cadastro relido, não o que a tela tinha', async () => {
    banco.respostas['clients.select'] = ok({ name: 'MP', opt_out_whatsapp: false, generico: false, whatsapp: null, phone: '(47) 3333-4444' });
    await enviar();
    expect(banco.invocacoes[0].body.phone).toBe('554733334444');
  });

  it('cadastro sem telefone → não envia', async () => {
    banco.respostas['clients.select'] = ok({ name: 'MP', opt_out_whatsapp: false, generico: false, whatsapp: null, phone: null });
    expect(((await enviar()).error as Error).message).toContain('Sem telefone');
    expect(banco.invocacoes).toEqual([]);
  });

  it('fora do horário de cobrança (22h em Brasília) → não envia', async () => {
    relogioDoCobrarJuntasTela.agora = () => new Date('2026-10-29T01:00:00Z');
    expect(((await enviar()).error as Error).message).toContain('Fora do horário de cobrança (22h');
    expect(banco.invocacoes).toEqual([]);
  });

  it('uma OS só → não envia (como a tool)', async () => {
    banco.respostas['receivables.select'] = ok([CONTAS_NO_BANCO[0]]);
    const r = await enviar({ ...ENVIO, contas: [{ id: 'r45', saldo: 1650 }], servicoIds: ['os45'] });
    expect((r.error as Error).message).toContain('2 OS ou mais');
    expect(banco.invocacoes).toEqual([]);
  });

  it('sem cobrança nas contas (a MP): a função do banco cria as duas e o envio fica registrado, sem aviso', async () => {
    banco.respostas['rpc.cobrar_juntas_registrar_envio'] = ok({ criadas: 2, registradas: 2, cobrancas_criadas: ['n1', 'n2'] });
    const r = await enviar();
    expect(r.isSuccess).toBe(true);
    expect(r.data).toEqual({ deduplicado: false, cobrancasRegistradas: 2, cobrancasCriadas: 2, aviso: null });
  });

  it('trava relida na hora: cadastro virou genérico no banco → não envia', async () => {
    banco.respostas['clients.select'] = ok({ name: 'Cliente Final', opt_out_whatsapp: false, generico: true });
    const r = await enviar();
    expect(r.isError).toBe(true);
    expect((r.error as Error).message).toContain('é genérico, sem CPF/CNPJ');
    expect(banco.invocacoes).toEqual([]);
  });

  it('Pix chegou depois de abrir a tela → não envia', async () => {
    banco.respostas['finance_review_queue.select'] = ok([{ suggested_client_id: 'cli', suggested_amount: 1670, suggested_date: '2026-10-28' }]);
    const r = await enviar();
    expect((r.error as Error).message).toContain('entrada esperando no Extrato');
    expect(banco.invocacoes).toEqual([]);
  });

  // 24/11/2026: os boletos da Apolo estavam na fila SEM cliente, só com o vínculo sugerido apontando a conta aberta, e
  // passavam pela trava. A tela usa a mesma regra do assistente (_shared/receivables/dinheiro-esperando.ts).
  it('entrada sem cliente na fila, com o vínculo apontando uma conta aberta dele → não envia', async () => {
    banco.respostas['receivables.select'] = ok(CONTAS_NO_BANCO.map((c) => ({ ...c, client_id: 'cli' })));
    banco.respostas['finance_review_queue.select'] = ok([{
      suggested_client_id: null, suggested_amount: 1650, suggested_date: '2026-10-28',
      vinculo_sugerido: { principal: { tipo: 'receivable', lancamentoId: 'r45', nivel: 'weak' } },
    }]);
    const r = await enviar();
    expect((r.error as Error).message).toContain('entrada esperando no Extrato');
    expect(banco.invocacoes).toEqual([]);
  });

  it('entrada de OUTRO cliente (ou sem cliente e sem conta dele apontada) não segura a cobrança deste', async () => {
    banco.respostas['finance_review_queue.select'] = ok([
      { suggested_client_id: 'outro', suggested_amount: 1670, suggested_date: '2026-10-28' },
      { suggested_client_id: null, suggested_amount: 500, suggested_date: '2026-10-28', vinculo_sugerido: null },
      { suggested_client_id: null, suggested_amount: 500, suggested_date: '2026-10-28', vinculo_sugerido: { principal: { tipo: 'existing_payment', lancamentoId: 'r45' } } },
    ]);
    const r = await enviar();
    expect(r.isSuccess).toBe(true);
    expect(banco.invocacoes).toHaveLength(1);
  });

  it('leitura do Extrato que falha não vira "nenhum Pix": não envia', async () => {
    banco.respostas['finance_review_queue.select'] = { data: null, error: { message: 'permission denied' } };
    const r = await enviar();
    expect((r.error as Error).message).toContain('Não consegui ler os Pix');
    expect(banco.invocacoes).toEqual([]);
  });

  it('piso e opt-out relidos do banco', async () => {
    banco.respostas['app_settings.select'] = ok({ value: '5000' });
    expect(((await enviar()).error as Error).message).toContain('abaixo do piso');
    banco.respostas['app_settings.select'] = ok({ value: '0' });
    banco.respostas['clients.select'] = ok({ name: 'MP', opt_out_whatsapp: true, generico: false, whatsapp: '47999990000' });
    expect(((await enviar()).error as Error).message).toContain('opt-out');
    expect(banco.invocacoes).toEqual([]);
  });

  it('mesma cobrança já enviada hoje (deduplicated): não registra de novo', async () => {
    banco.envio = { data: { success: true, deduplicated: true }, error: null };
    const r = await enviar();
    expect(r.data).toEqual({ deduplicado: true, cobrancasRegistradas: 0, cobrancasCriadas: 0, aviso: null });
    expect(banco.chamadas.filter((c) => c.alvo.startsWith('rpc.'))).toEqual([]);
  });

  it('enviou mas a função do banco falhou: devolve aviso (nada gravado), não erro', async () => {
    banco.respostas['rpc.cobrar_juntas_registrar_envio'] = { data: null, error: { message: 'mês fechado' } };
    const r = await enviar();
    expect(r.isSuccess).toBe(true);
    expect(r.data?.cobrancasCriadas).toBe(0);
    expect(r.data?.aviso).toContain('A mensagem foi enviada, mas não consegui criar/registrar a cobrança (mês fechado). Nada foi gravado nas cobranças');
  });

  // A ficha não relê ao voltar para a aba (refetchOnWindowFocus false): sem invalidar no erro, o
  // "feche e abra o Cobrar juntas de novo" mostrava os saldos velhos e a recusa se repetia.
  it('recusa por saldo que mudou invalida as contas da ficha (reabrir traz o saldo novo)', async () => {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
    const FICHA = ['receivables', 'client', 'cli', 'com-os'];
    qc.setQueryData(FICHA, [{ id: 'r45', balance_amount: 1650 }]);
    qc.setQueryData(['collections', 'cobrar-juntas', ['r45'], ['os45']], 1);
    banco.respostas['receivables.select'] = ok(CONTAS_NO_BANCO.map((c) => c.id === 'r45' ? { ...c, status: 'paid', paid_amount: 1650, balance_amount: 0 } : c));
    const r = await enviar(ENVIO, qc);
    expect(r.isError).toBe(true);
    expect(qc.getQueryState(FICHA)?.isInvalidated).toBe(true);
    expect(qc.getQueryState(['collections', 'cobrar-juntas', ['r45'], ['os45']])?.isInvalidated).toBe(true);
    expect(banco.invocacoes).toEqual([]);
  });

  it('qualquer recusa também invalida (ex.: fora do horário)', async () => {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
    qc.setQueryData(['receivables', 'client', 'cli', 'com-os'], []);
    relogioDoCobrarJuntasTela.agora = () => new Date('2026-10-29T01:00:00Z');
    expect((await enviar(ENVIO, qc)).isError).toBe(true);
    expect(qc.getQueryState(['receivables', 'client', 'cli', 'com-os'])?.isInvalidated).toBe(true);
  });

  it('modo de teste (desvia para o número de teste): chave com ":teste", nada registrado nas cobranças, aviso de teste', async () => {
    await enviar();
    const chaveReal = String(banco.invocacoes[0].body.dedupe_key);
    expect(chaveReal.endsWith(':teste')).toBe(false);
    banco.chamadas = [];
    banco.invocacoes = [];

    banco.respostas['app_settings.select:modo-teste'] = ok([
      { key: 'wa_test_mode', value: 'true' }, { key: 'wa_test_number', value: '5547900001111' },
    ]);
    const r = await enviar();
    expect(r.isSuccess).toBe(true);
    expect(r.data).toEqual({ deduplicado: false, cobrancasRegistradas: 0, cobrancasCriadas: 0, aviso: AVISO_MODO_TESTE, modoTeste: true });
    expect(r.data?.aviso).toContain('foi para o número de teste');
    expect(banco.invocacoes[0].body.dedupe_key).toBe(`${chaveReal}:teste`);
    expect(banco.chamadas.filter((c) => c.alvo.startsWith('rpc.'))).toEqual([]);
    const leitura = banco.chamadas.find((c) => c.alvo === 'app_settings' && c.filtros.some((f) => f[0] === 'in'));
    expect(leitura?.filtros).toContainEqual(['in', 'key', ['wa_test_mode', 'wa_test_number', 'zapi_test_mode', 'zapi_test_number']]);
  });

  it('modo de teste ligado SEM número: a edge não desvia — chave e registro de sempre (como a tool)', async () => {
    banco.respostas['app_settings.select:modo-teste'] = ok([{ key: 'wa_test_mode', value: 'true' }, { key: 'wa_test_number', value: '' }]);
    const r = await enviar();
    expect(r.data).toEqual({ deduplicado: false, cobrancasRegistradas: 2, cobrancasCriadas: 0, aviso: null });
    expect(String(banco.invocacoes[0].body.dedupe_key).endsWith(':teste')).toBe(false);
  });

  it('leitura do modo de teste que falha não vira "não é teste": não envia', async () => {
    banco.respostas['app_settings.select:modo-teste'] = { data: null, error: { message: 'permission denied' } };
    const r = await enviar();
    expect(r.isError).toBe(true);
    expect((r.error as Error).message).toContain('Não consegui ler o modo de teste do WhatsApp: permission denied');
    expect(banco.invocacoes).toEqual([]);
  });
});

describe('useCobrancasFormais', () => {
  it('devolve as cobranças abertas das contas e as da OS sem conta (para saber quais contas ganham cobrança)', async () => {
    const { result } = renderHook(() => useCobrancasFormais(['r45', 'r46'], ['os45', 'os46']), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data?.map((c) => c.id).sort()).toEqual(['col45', 'colOs46']);
    const leituras = banco.chamadas.filter((c) => c.alvo === 'collections' && c.op === 'select');
    expect(leituras[0].filtros).toContainEqual(['in', 'receivable_id', ['r45', 'r46']]);
    expect(leituras[0].filtros).toContainEqual(['not', 'status', 'in', '(paid,cancelled)']);
    expect(leituras[1].filtros).toContainEqual(['in', 'service_order_id', ['os45', 'os46']]);
    expect(leituras[1].filtros).toContainEqual(['is', 'receivable_id', null]);
  });
});

// "Enviar extrato" com as mesmas travas do Cobrar juntas (dono, 20/11/2026).
describe('useEnviarExtrato', () => {
  const EXTRATO = {
    cliente: { id: 'cli', name: 'MP MOTOR HOMES' },
    mensagem: 'Extrato financeiro — HBR …',
    contas: [{ id: 'r45', saldo: 1650 }, { id: 'r46', saldo: 20 }],
  };

  async function enviarExtrato(e = EXTRATO) {
    const { result } = renderHook(() => useEnviarExtrato(), { wrapper });
    result.current.mutate(e);
    await waitFor(() => expect(result.current.isSuccess || result.current.isError).toBe(true));
    return result.current;
  }

  it('envia ao cadastro com a chave do dia "extrato:", relê as contas do cliente inteiro e registra como a cobrança do dia DEPOIS do envio', async () => {
    banco.respostas['rpc.cobrar_juntas_registrar_envio'] = ok({ criadas: 1, registradas: 2, cobrancas_criadas: ['k-nova'] });
    const r = await enviarExtrato();
    expect(r.isSuccess).toBe(true);
    expect(r.data).toEqual({ deduplicado: false, aviso: null, cobrancasRegistradas: 2, cobrancasCriadas: 1 });
    expect(banco.invocacoes[0].body).toMatchObject({ phone: '5547999990000', context: 'billing', kind: 'text' });
    expect(String(banco.invocacoes[0].body.dedupe_key)).toMatch(/^extrato:cli:\d{4}-\d{2}-\d{2}:/);
    const contas = banco.chamadas.find((c) => c.alvo === 'receivables');
    expect(contas?.filtros).toContainEqual(['eq', 'client_id', 'cli']);
    expect(contas?.filtros.some((f) => f[0] === 'in')).toBe(false);
    // Dono (20/11/2026): "conta como cobrança do dia" — a mesma função do Cobrar juntas, com p_os nulo
    // (o cliente inteiro), chamada só depois do envio.
    const rpc = banco.chamadas.filter((c) => c.alvo === 'rpc.cobrar_juntas_registrar_envio');
    expect(rpc).toHaveLength(1);
    expect(rpc[0].valores).toEqual({ p_cliente: 'cli', p_contas: ['r45', 'r46'], p_os: null, p_nota: NOTA_DO_EXTRATO });
    expect(banco.chamadas.indexOf(rpc[0])).toBeGreaterThan(banco.chamadas.findIndex((c) => c.alvo === 'receivables'));
    expect(banco.chamadas.filter((c) => c.alvo === 'collection_contacts' || (c.alvo === 'collections' && c.op !== 'select'))).toEqual([]);
  });

  it('com saldo: a mensagem não saiu, saiu repetida ou foi para o número de teste → nada registrado', async () => {
    banco.envio = { data: null, error: { message: 'falhou' } };
    expect((await enviarExtrato()).isError).toBe(true);
    banco.envio = { data: { success: true, deduplicated: true }, error: null };
    expect((await enviarExtrato()).data).toEqual({ deduplicado: true, aviso: null });
    banco.envio = { data: { success: true }, error: null };
    banco.respostas['app_settings.select:modo-teste'] = ok([
      { key: 'wa_test_mode', value: 'true' }, { key: 'wa_test_number', value: '5547900001111' },
    ]);
    expect((await enviarExtrato()).data?.modoTeste).toBe(true);
    expect(banco.chamadas.filter((c) => c.alvo.startsWith('rpc.'))).toEqual([]);
  });

  it('com saldo: enviou mas o registro falhou → aviso (a mensagem saiu, nada gravado), não erro', async () => {
    banco.respostas['rpc.cobrar_juntas_registrar_envio'] = { data: null, error: { message: 'Seu cargo não mexe em cobranças.' } };
    const r = await enviarExtrato();
    expect(r.isSuccess).toBe(true);
    expect(r.data?.aviso).toContain('O extrato foi enviado, mas não consegui registrar a cobrança do dia (Seu cargo não mexe em cobranças.)');
  });

  it('uma conta só também sai (o extrato não tem contagem de OS)', async () => {
    banco.respostas['receivables.select'] = ok([CONTAS_NO_BANCO[0]]);
    const r = await enviarExtrato({ ...EXTRATO, contas: [{ id: 'r45', saldo: 1650 }] });
    expect(r.isSuccess).toBe(true);
  });

  it('as travas barram: genérico, Pix esperando, opt-out, piso, sem telefone e fora do horário', async () => {
    banco.respostas['clients.select'] = ok({ name: 'Cliente Final', opt_out_whatsapp: false, generico: true, whatsapp: '47999990000' });
    expect(((await enviarExtrato()).error as Error).message).toContain('é genérico, sem CPF/CNPJ');
    banco.respostas['clients.select'] = ok({ name: 'MP', opt_out_whatsapp: false, generico: false, whatsapp: '47999990000' });
    banco.respostas['finance_review_queue.select'] = ok([{ suggested_client_id: 'cli', suggested_amount: 1670, suggested_date: '2026-10-28' }]);
    expect(((await enviarExtrato()).error as Error).message).toContain('entrada esperando no Extrato');
    banco.respostas['finance_review_queue.select'] = ok([]);
    banco.respostas['clients.select'] = ok({ name: 'MP', opt_out_whatsapp: true, generico: false, whatsapp: '47999990000' });
    expect(((await enviarExtrato()).error as Error).message).toContain('opt-out');
    banco.respostas['clients.select'] = ok({ name: 'MP', opt_out_whatsapp: false, generico: false, whatsapp: null, phone: null });
    expect(((await enviarExtrato()).error as Error).message).toContain('Sem telefone');
    banco.respostas['clients.select'] = ok({ name: 'MP', opt_out_whatsapp: false, generico: false, whatsapp: '47999990000' });
    banco.respostas['app_settings.select'] = ok({ value: '5000' });
    expect(((await enviarExtrato()).error as Error).message).toContain('abaixo do piso');
    banco.respostas['app_settings.select'] = ok({ value: '0' });
    relogioDoCobrarJuntasTela.agora = () => new Date('2026-10-29T01:00:00Z');
    expect(((await enviarExtrato()).error as Error).message).toContain('Fora do horário de cobrança (22h');
    expect(banco.invocacoes).toEqual([]);
  });

  it('nada em aberto: sai como comprovante de quitação e não registra cobrança (dono, 20/11/2026)', async () => {
    banco.respostas['receivables.select'] = ok([CONTAS_NO_BANCO[2]]);
    // Piso alto e Pix esperando não barram a quitação (nem são lidos).
    banco.respostas['app_settings.select'] = ok({ value: '5000' });
    banco.respostas['finance_review_queue.select'] = ok([{ suggested_client_id: 'cli', suggested_amount: 100, suggested_date: '2026-10-28' }]);
    const r = await enviarExtrato({ ...EXTRATO, mensagem: 'Comprovante de quitação — HBR …', contas: [] });
    expect(r.isSuccess).toBe(true);
    expect(r.data).toEqual({ deduplicado: false, aviso: null, quitacao: true });
    expect(banco.invocacoes).toHaveLength(1);
    expect(String(banco.invocacoes[0].body.dedupe_key)).toMatch(/^extrato:cli:/);
    expect(banco.chamadas.filter((c) => c.alvo.startsWith('rpc.') || c.alvo === 'finance_review_queue')).toEqual([]);
  });

  it('nada em aberto: genérico, opt-out, sem telefone e fora do horário barram; sem lançamento nenhum também', async () => {
    banco.respostas['receivables.select'] = ok([CONTAS_NO_BANCO[2]]);
    const Q = { ...EXTRATO, contas: [] };
    banco.respostas['clients.select'] = ok({ name: 'Cliente Final', opt_out_whatsapp: false, generico: true, whatsapp: '47999990000' });
    expect(((await enviarExtrato(Q)).error as Error).message).toContain('não recebe extrato');
    banco.respostas['clients.select'] = ok({ name: 'MP', opt_out_whatsapp: true, generico: false, whatsapp: '47999990000' });
    expect(((await enviarExtrato(Q)).error as Error).message).toContain('opt-out');
    banco.respostas['clients.select'] = ok({ name: 'MP', opt_out_whatsapp: false, generico: false, whatsapp: null, phone: null });
    expect(((await enviarExtrato(Q)).error as Error).message).toBe('Sem telefone para enviar o extrato.');
    banco.respostas['clients.select'] = ok({ name: 'MP', opt_out_whatsapp: false, generico: false, whatsapp: '47999990000' });
    relogioDoCobrarJuntasTela.agora = () => new Date('2026-10-29T01:00:00Z');
    expect(((await enviarExtrato(Q)).error as Error).message).toContain('Fora do horário');
    relogioDoCobrarJuntasTela.agora = AS_14H;
    banco.respostas['receivables.select'] = ok([]);
    expect(((await enviarExtrato(Q)).error as Error).message).toBe('Este cliente não tem lançamentos: não há extrato para enviar.');
    expect(banco.invocacoes).toEqual([]);
  });

  it('saldo mudou desde que a tela abriu: não envia, com a frase do extrato', async () => {
    banco.respostas['receivables.select'] = ok(CONTAS_NO_BANCO.map((c) => c.id === 'r46' ? { ...c, paid_amount: 40, balance_amount: 10 } : c));
    const r = await enviarExtrato();
    expect((r.error as Error).message).toContain('O saldo do cliente mudou desde que a tela abriu');
    expect((r.error as Error).message).toContain('feche e abra o extrato de novo');
    expect(banco.invocacoes).toEqual([]);
  });

  it('modo de teste: chave com ":teste" e aviso de que foi para o número de teste', async () => {
    banco.respostas['app_settings.select:modo-teste'] = ok([
      { key: 'wa_test_mode', value: 'true' }, { key: 'wa_test_number', value: '5547900001111' },
    ]);
    const r = await enviarExtrato();
    expect(r.data).toEqual({ deduplicado: false, aviso: AVISO_MODO_TESTE_EXTRATO, modoTeste: true });
    expect(banco.chamadas.filter((c) => c.alvo.startsWith('rpc.'))).toEqual([]);
    expect(String(banco.invocacoes[0].body.dedupe_key)).toMatch(/^extrato:cli:.*:teste$/);
  });
});

// Fatura FAT-N (Fechar juntas F1, 20/11/2026): com as OS todas executadas a tela pede comFatura — a fatura
// nasce depois das travas e antes do WhatsApp, e o número entra no lugar do provisório.
describe('useEnviarCobrarJuntas com fatura', () => {
  const COM_FATURA = { ...ENVIO, mensagem: `Cobrança — HBR\nFatura: ${NUMERO_DA_FATURA_NOVA}\n…`, comFatura: true };

  it('cria a fatura antes do envio, cita o número na mensagem e registra depois', async () => {
    banco.respostas['rpc.fatura_criar'] = ok({ ok: true, criada: true, fatura_id: 'fat1', numero: 'FAT-00001' });
    const r = await enviar(COM_FATURA);
    expect(r.isSuccess).toBe(true);
    expect(r.data).toMatchObject({ deduplicado: false, fatura: 'FAT-00001', cobrancasRegistradas: 2 });
    const rpcs = banco.chamadas.filter((c) => c.alvo.startsWith('rpc.')).map((c) => c.alvo);
    expect(rpcs).toEqual(['rpc.fatura_criar', 'rpc.cobrar_juntas_registrar_envio']);
    expect(banco.chamadas.find((c) => c.alvo === 'rpc.fatura_criar')?.valores).toEqual({ p_cliente: 'cli', p_contas: ['r45', 'r46'] });
    expect(banco.invocacoes).toHaveLength(1);
    expect(String(banco.invocacoes[0].body.message)).toContain('Fatura: FAT-00001');
    expect(String(banco.invocacoes[0].body.message)).not.toContain(NUMERO_DA_FATURA_NOVA);
  });

  it('o banco recusa a fatura (conta já noutra fatura): nada sai nem é registrado', async () => {
    banco.respostas['rpc.fatura_criar'] = { data: null, error: { message: 'Estas contas já estão numa fatura: Saldo (FAT-00002).' } };
    const r = await enviar(COM_FATURA);
    expect(r.isError).toBe(true);
    expect((r.error as Error).message).toContain('já estão numa fatura');
    expect(banco.invocacoes).toHaveLength(0);
    expect(banco.chamadas.some((c) => c.alvo === 'rpc.cobrar_juntas_registrar_envio')).toBe(false);
  });

  it('travas antes da fatura: fora do horário, nem a fatura nasce', async () => {
    relogioDoCobrarJuntasTela.agora = () => new Date('2026-10-29T01:00:00Z'); // 22h em Brasília
    const r = await enviar(COM_FATURA);
    expect(r.isError).toBe(true);
    expect(banco.chamadas.some((c) => c.alvo === 'rpc.fatura_criar')).toBe(false);
    expect(banco.invocacoes).toHaveLength(0);
  });

  it('modo de teste: a fatura não nasce e o número de teste vê o provisório de teste', async () => {
    banco.respostas['app_settings.select:modo-teste'] = ok([{ key: 'wa_test_mode', value: 'true' }, { key: 'wa_test_number', value: '5547900000000' }]);
    const r = await enviar(COM_FATURA);
    expect(r.isSuccess).toBe(true);
    expect(banco.chamadas.some((c) => c.alvo === 'rpc.fatura_criar')).toBe(false);
    expect(String(banco.invocacoes[0].body.message)).toContain('Fatura: FAT-(teste)');
    expect(r.data).not.toHaveProperty('fatura');
  });

  it('sem comFatura: nada muda (nenhuma chamada a fatura_criar)', async () => {
    await enviar();
    expect(banco.chamadas.some((c) => c.alvo === 'rpc.fatura_criar')).toBe(false);
  });
});

// A cobrança do cliente pela tela (dono, 26/11/2026: "1. A" — o botão da linha, o da aba Cobranças e o Cobrar em lote
// ganham a conferência da ficha): o mesmo conferirEEnviar do extrato, sem comprovante de quitação, chave "cobrar-cliente:".
describe('enviarCobrancaDoCliente', () => {
  const COBRANCA = {
    cliente: { id: 'cli', name: 'MP MOTOR HOMES' },
    mensagem: 'Cobrança — HBR …',
    contas: [{ id: 'r45', saldo: 1650 }, { id: 'r46', saldo: 20 }],
  };
  const tentar = async (e = COBRANCA) => {
    try { return { ok: await enviarCobrancaDoCliente(e), erro: null as string | null }; } catch (x) { return { ok: null, erro: (x as Error).message }; }
  };

  it('envia ao cadastro com a chave "cobrar-cliente:", relê as contas do cliente inteiro e registra a cobrança do dia DEPOIS do envio', async () => {
    banco.respostas['rpc.cobrar_juntas_registrar_envio'] = ok({ criadas: 1, registradas: 2, cobrancas_criadas: ['k-nova'] });
    const r = await tentar();
    expect(r.erro).toBeNull();
    expect(r.ok).toEqual({ deduplicado: false, cobrancasRegistradas: 2, cobrancasCriadas: 1, aviso: null });
    expect(banco.invocacoes[0].body).toMatchObject({ phone: '5547999990000', context: 'billing', kind: 'text', message: 'Cobrança — HBR …' });
    expect(String(banco.invocacoes[0].body.dedupe_key)).toMatch(/^cobrar-cliente:cli:\d{4}-\d{2}-\d{2}:/);
    const contas = banco.chamadas.find((c) => c.alvo === 'receivables');
    expect(contas?.filtros).toContainEqual(['eq', 'client_id', 'cli']);
    expect(contas?.filtros.some((f) => f[0] === 'in')).toBe(false);
    const rpc = banco.chamadas.filter((c) => c.alvo === 'rpc.cobrar_juntas_registrar_envio');
    expect(rpc).toHaveLength(1);
    expect(rpc[0].valores).toEqual({ p_cliente: 'cli', p_contas: ['r45', 'r46'], p_os: null, p_nota: NOTA_DA_COBRANCA_DO_CLIENTE });
    expect(banco.chamadas.filter((c) => c.alvo === 'collection_contacts' || (c.alvo === 'collections' && c.op !== 'select'))).toEqual([]);
  });

  it('sem conta com saldo: não vira comprovante de quitação — não sai nada', async () => {
    banco.respostas['receivables.select'] = ok([{ id: 's45', status: 'paid', amount: 500, paid_amount: 500, balance_amount: 0 }]);
    const r = await tentar({ ...COBRANCA, contas: [] });
    expect(r.erro).toBe('Este cliente não tem saldo em aberto: não há o que cobrar.');
    expect(banco.invocacoes).toEqual([]);
  });

  it('as travas da ficha barram com dado fresco: entrada esperando no Extrato, opt-out, genérico, piso e fora do horário', async () => {
    banco.respostas['finance_review_queue.select'] = ok([{ suggested_client_id: 'cli', suggested_amount: 1670, suggested_date: '2026-10-28' }]);
    expect((await tentar()).erro).toContain('entrada esperando no Extrato');
    banco.respostas['finance_review_queue.select'] = ok([]);
    banco.respostas['clients.select'] = ok({ name: 'MP MOTOR HOMES', opt_out_whatsapp: true, generico: false, whatsapp: '(47) 99999-0000', phone: null });
    expect((await tentar()).erro).toContain('opt-out');
    banco.respostas['clients.select'] = ok({ name: 'Cliente Final', opt_out_whatsapp: false, generico: true, whatsapp: '(47) 99999-0000', phone: null });
    expect((await tentar()).erro).toContain('é genérico');
    banco.respostas['clients.select'] = ok({ name: 'MP MOTOR HOMES', opt_out_whatsapp: false, generico: false, whatsapp: '(47) 99999-0000', phone: null });
    banco.respostas['app_settings.select'] = ok({ value: '5000' });
    expect((await tentar()).erro).toContain('abaixo do piso');
    banco.respostas['app_settings.select'] = ok({ value: '0' });
    relogioDoCobrarJuntasTela.agora = () => new Date('2026-10-29T01:00:00Z'); // 22h em Brasília
    expect((await tentar()).erro).toContain('Fora do horário de cobrança');
    expect(banco.invocacoes).toEqual([]);
  });

  it('saldo mudou desde que a tela abriu: não envia, e a frase manda abrir a cobrança de novo', async () => {
    banco.respostas['receivables.select'] = ok(CONTAS_NO_BANCO.map((c) => c.id === 'r46' ? { ...c, paid_amount: 40, balance_amount: 10 } : c));
    const r = await tentar();
    expect(r.erro).toContain('O saldo do cliente mudou desde que a tela abriu');
    expect(r.erro).toContain('feche e abra a cobrança de novo');
    expect(banco.invocacoes).toEqual([]);
  });

  it('não saiu, saiu repetida ou foi para o número de teste → nada registrado; teste com chave ":teste" e aviso', async () => {
    banco.envio = { data: null, error: { message: 'falhou' } };
    expect((await tentar()).erro).toBeTruthy();
    banco.envio = { data: { success: true, deduplicated: true }, error: null };
    expect((await tentar()).ok).toEqual({ deduplicado: true, aviso: null });
    banco.envio = { data: { success: true }, error: null };
    banco.invocacoes = [];
    banco.respostas['app_settings.select:modo-teste'] = ok([
      { key: 'wa_test_mode', value: 'true' }, { key: 'wa_test_number', value: '5547900001111' },
    ]);
    expect((await tentar()).ok).toEqual({ deduplicado: false, aviso: AVISO_MODO_TESTE, modoTeste: true });
    expect(String(banco.invocacoes[0].body.dedupe_key)).toMatch(/^cobrar-cliente:cli:.*:teste$/);
    expect(banco.chamadas.filter((c) => c.alvo.startsWith('rpc.'))).toEqual([]);
  });

  it('enviou mas o registro falhou → aviso (a mensagem saiu, nada gravado), não erro', async () => {
    banco.respostas['rpc.cobrar_juntas_registrar_envio'] = { data: null, error: { message: 'boom' } };
    const r = await tentar();
    expect(r.erro).toBeNull();
    expect(r.ok?.aviso).toContain('A cobrança foi enviada, mas não consegui registrá-la (boom)');
  });
});

// "Já cobrado hoje" (o aviso da cobrança do cliente e o "fica de fora" do Cobrar em lote): só as de hoje em Brasília.
describe('lerCobradosHoje', () => {
  it('lê só as cobranças registradas desde a meia-noite de Brasília e guarda a última de cada cliente', async () => {
    relogioDoCobrarJuntasTela.agora = () => new Date('2026-11-26T02:30:00Z'); // 25/11 às 23h30 em Brasília
    banco.respostas['collections.select'] = ok([
      { client_id: 'a', last_auto_sent_at: '2026-11-25T13:00:00Z' },
      { client_id: 'a', last_auto_sent_at: '2026-11-25T18:15:00Z' },
      { client_id: 'b', last_auto_sent_at: '2026-11-25T12:00:00Z' },
    ]);
    const m = await lerCobradosHoje(['a', 'b', 'a']);
    expect([...m.entries()]).toEqual([['a', '2026-11-25T18:15:00Z'], ['b', '2026-11-25T12:00:00Z']]);
    const leitura = banco.chamadas.find((c) => c.alvo === 'collections');
    expect(leitura?.filtros).toContainEqual(['in', 'client_id', ['a', 'b']]);
    expect(leitura?.filtros).toContainEqual(['gte', 'last_auto_sent_at', '2026-11-25T03:00:00.000Z']);
    expect(avisoDeCobradoHoje('2026-11-25T18:15:00Z')).toBe('Este cliente já recebeu cobrança hoje (às 15h15). Confira se precisa mesmo de outra mensagem.');
    expect(avisoDeCobradoHoje(null)).toBeNull();
  });

  it('sem clientes não lê; leitura que falha LANÇA (nunca "ninguém foi cobrado")', async () => {
    expect((await lerCobradosHoje([])).size).toBe(0);
    expect(banco.chamadas).toEqual([]);
    banco.respostas['collections.select'] = { data: null, error: { message: 'permission denied' } };
    await expect(lerCobradosHoje(['a'])).rejects.toThrow('Não consegui ler as cobranças de hoje: permission denied');
  });
});
