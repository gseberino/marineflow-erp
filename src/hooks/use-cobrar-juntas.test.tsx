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
    for (const m of ['select', 'eq', 'not', 'in', 'is', 'range', 'limit', 'order']) {
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
      functions: {
        invoke: (nome: string, o: { body: Record<string, unknown> }) => {
          banco.invocacoes.push({ nome, body: o.body });
          return Promise.resolve(banco.envio);
        },
      },
    },
  };
});

import { AVISO_MODO_TESTE, relogioDoCobrarJuntasTela, useEnviarCobrarJuntas } from './use-cobrar-juntas';

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
    // 1ª leitura: cobranças das contas; 2ª: cobrança só com a OS.
    'collections.select': [ok([{ id: 'col45', status: 'pending' }]), ok([{ id: 'colOs46', status: 'sent' }])],
  };
  banco.chamadas = [];
  banco.invocacoes = [];
  banco.envio = { data: { success: true }, error: null };
});

describe('useEnviarCobrarJuntas', () => {
  it('envia com chave de idempotência e registra contato + last_auto_sent_at nas cobranças das contas', async () => {
    const r = await enviar();
    expect(r.isSuccess).toBe(true);
    expect(r.data).toEqual({ deduplicado: false, cobrancasRegistradas: 2, aviso: null });
    expect(banco.invocacoes).toHaveLength(1);
    const body = banco.invocacoes[0].body;
    expect(body).toMatchObject({ phone: '5547999990000', context: 'billing', kind: 'text' });
    expect(String(body.dedupe_key)).toMatch(/^cobrar-juntas:cli:\d{4}-\d{2}-\d{2}:/);

    // As contas relidas são as das OS escolhidas e do mesmo cliente (o que a ficha mostra).
    const contas = banco.chamadas.find((c) => c.alvo === 'receivables');
    expect(contas?.filtros).toContainEqual(['eq', 'client_id', 'cli']);
    expect(contas?.filtros).toContainEqual(['in', 'service_order_id', ['os45', 'os46']]);

    const leituras = banco.chamadas.filter((c) => c.alvo === 'collections' && c.op === 'select');
    expect(leituras[0].filtros).toContainEqual(['in', 'receivable_id', ['r45', 'r46']]);
    expect(leituras[0].filtros).toContainEqual(['not', 'status', 'in', '(paid,cancelled)']);
    expect(leituras[1].filtros).toContainEqual(['in', 'service_order_id', ['os45', 'os46']]);
    expect(leituras[1].filtros).toContainEqual(['is', 'receivable_id', null]);

    const contatos = banco.chamadas.filter((c) => c.alvo === 'collection_contacts' && c.op === 'insert');
    expect(contatos.map((c) => (c.valores as { collection_id: string }).collection_id)).toEqual(['col45', 'colOs46']);
    const updates = banco.chamadas.filter((c) => c.alvo === 'collections' && c.op === 'update');
    expect(updates).toHaveLength(2);
    expect(updates[0].valores).toMatchObject({ status: 'sent' });
    expect((updates[0].valores as { last_auto_sent_at: string }).last_auto_sent_at).toBeTruthy();
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

  it('sem cobrança formal nas contas: envia e avisa que nada ficou registrado', async () => {
    banco.respostas['collections.select'] = [ok([]), ok([])];
    const r = await enviar();
    expect(r.isSuccess).toBe(true);
    expect(r.data?.cobrancasRegistradas).toBe(0);
    expect(r.data?.aviso).toContain('o envio não fica registrado');
  });

  it('trava relida na hora: cadastro virou genérico no banco → não envia', async () => {
    banco.respostas['clients.select'] = ok({ name: 'Cliente Final', opt_out_whatsapp: false, generico: true });
    const r = await enviar();
    expect(r.isError).toBe(true);
    expect((r.error as Error).message).toContain('é genérico, sem CPF/CNPJ');
    expect(banco.invocacoes).toEqual([]);
  });

  it('Pix chegou depois de abrir a tela → não envia', async () => {
    banco.respostas['finance_review_queue.select'] = ok([{ suggested_amount: 1670, suggested_date: '2026-10-28' }]);
    const r = await enviar();
    expect((r.error as Error).message).toContain('Pix esperando no Extrato');
    expect(banco.invocacoes).toEqual([]);
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
    expect(r.data).toEqual({ deduplicado: true, cobrancasRegistradas: 0, aviso: null });
    expect(banco.chamadas.filter((c) => c.alvo === 'collection_contacts')).toEqual([]);
  });

  it('enviou mas o registro falhou: devolve aviso, não erro', async () => {
    banco.respostas['collection_contacts.insert'] = { data: null, error: { message: 'mês fechado' } };
    const r = await enviar();
    expect(r.isSuccess).toBe(true);
    expect(r.data?.aviso).toContain('A mensagem foi enviada, mas não consegui registrar o envio nas cobranças (mês fechado)');
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
    expect(r.data).toEqual({ deduplicado: false, cobrancasRegistradas: 0, aviso: AVISO_MODO_TESTE, modoTeste: true });
    expect(r.data?.aviso).toContain('foi para o número de teste');
    expect(banco.invocacoes[0].body.dedupe_key).toBe(`${chaveReal}:teste`);
    expect(banco.chamadas.filter((c) => c.alvo === 'collection_contacts')).toEqual([]);
    expect(banco.chamadas.filter((c) => c.alvo === 'collections' && c.op === 'update')).toEqual([]);
    const leitura = banco.chamadas.find((c) => c.alvo === 'app_settings' && c.filtros.some((f) => f[0] === 'in'));
    expect(leitura?.filtros).toContainEqual(['in', 'key', ['wa_test_mode', 'wa_test_number', 'zapi_test_mode', 'zapi_test_number']]);
  });

  it('modo de teste ligado SEM número: a edge não desvia — chave e registro de sempre (como a tool)', async () => {
    banco.respostas['app_settings.select:modo-teste'] = ok([{ key: 'wa_test_mode', value: 'true' }, { key: 'wa_test_number', value: '' }]);
    const r = await enviar();
    expect(r.data).toEqual({ deduplicado: false, cobrancasRegistradas: 2, aviso: null });
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
