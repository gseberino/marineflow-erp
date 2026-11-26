// "Cobrar em lote" da tela (dono, 26/11/2026: "1. A"): uma mensagem por cliente, as travas da ficha em cada um, quem
// fica de fora com o motivo, uma mensagem por número, no máximo 20.
import { describe, it, expect } from 'vitest';
import { MAX_CLIENTES_DO_LOTE, montarLoteDaTela, type ClienteParaOLote, type ContaParaOLote } from './cobrar-em-lote';

const HOJE = '2026-11-26';

const conta = (id: string, client_id: string | null, extra: Partial<ContaParaOLote> = {}): ContaParaOLote => ({
  id, client_id, description: `Conta ${id}`, status: 'pending', amount: 1000, paid_amount: 0, balance_amount: 1000,
  due_date: '2026-11-10', service_order_id: null, numero_os: null, ...extra,
});
const cliente = (id: string, name: string, extra: Partial<ClienteParaOLote> = {}): ClienteParaOLote => ({
  id, name, generico: false, opt_out_whatsapp: false, whatsapp: `(47) 99999-${id.padStart(4, '0').slice(-4)}`, phone: null, ...extra,
});

function lote(p: Partial<Parameters<typeof montarLoteDaTela>[0]> = {}) {
  return montarLoteDaTela({
    contas: [], clientes: [], filtro: 'vencidas', hoje: HOJE, piso: 0, pixKey: 'hbr@pix',
    pixEsperando: new Map(), cobradosHoje: new Map(), ...p,
  });
}

describe('montarLoteDaTela', () => {
  it('uma mensagem por cliente com TODAS as contas com saldo dele (a vencer também), a cobrança do cliente inteiro', () => {
    const r = lote({
      contas: [
        conta('a1', '1', { balance_amount: 1000, due_date: '2026-11-10' }),
        conta('a2', '1', { amount: 500, balance_amount: 500, due_date: '2026-12-20' }),
        conta('a3', '1', { status: 'paid', amount: 300, paid_amount: 300, balance_amount: 0 }),
      ],
      clientes: [cliente('1', 'Flávio Souza')],
    });
    expect(r.fora).toEqual([]);
    expect(r.vao).toHaveLength(1);
    const i = r.vao[0];
    expect(i.contas).toEqual([{ id: 'a1', saldo: 1000 }, { id: 'a2', saldo: 500 }]);
    expect([i.total, i.vencido]).toEqual([1500, 1000]);
    expect(i.mensagem.startsWith('📋 *Cobrança — HBR*\nCliente: Flávio')).toBe(true);
    expect(i.mensagem).toContain('a vencer');
    expect(i.mensagem).not.toContain('Conta a3');
    expect(i.mensagem).toContain('hbr@pix');
  });

  it('"vencidas" deixa de lado (sem motivo) quem não tem nada vencido; "todas" entra com todo cliente com saldo', () => {
    const p = { contas: [conta('a1', '1'), conta('b1', '2', { due_date: '2026-12-20' })], clientes: [cliente('1', 'Ana'), cliente('2', 'Bia')] };
    expect(lote(p).vao.map((i) => i.cliente.name)).toEqual(['Ana']);
    expect(lote(p).fora).toEqual([]);
    expect(lote({ ...p, filtro: 'todas' }).vao.map((i) => i.cliente.name)).toEqual(['Ana', 'Bia']);
  });

  it('ficam de fora com o motivo: genérico, entrada esperando no Extrato, abaixo do piso, opt-out, sem telefone e já cobrado hoje', () => {
    const r = lote({
      contas: ['1', '2', '3', '4', '5', '6', '7'].map((c) => conta(`c${c}`, c, c === '3' ? { amount: 100, balance_amount: 100 } : {})),
      clientes: [
        cliente('1', 'Cliente Final', { generico: true }),
        cliente('2', 'Apolo'),
        cliente('3', 'Lírio'),
        cliente('4', 'Nelson', { opt_out_whatsapp: true }),
        cliente('5', 'Carlson', { whatsapp: null, phone: null }),
        cliente('6', 'João Hang'),
        cliente('7', 'Sergio'),
      ],
      piso: 200,
      pixEsperando: new Map([['2', [{ valor: 1000, data: '2026-11-20' }]]]),
      cobradosHoje: new Map([['6', '2026-11-26T13:15:00Z']]),
    });
    expect(r.vao.map((i) => i.cliente.name)).toEqual(['Sergio']);
    const motivo = (nome: string) => r.fora.find((f) => f.cliente === nome)?.motivo ?? '';
    expect(motivo('Cliente Final')).toContain('é genérico');
    expect(motivo('Apolo')).toContain('entrada esperando no Extrato');
    expect(motivo('Lírio')).toContain('abaixo do piso');
    expect(motivo('Nelson')).toContain('opt-out');
    expect(motivo('Carlson')).toBe('Sem telefone para enviar a cobrança.');
    expect(motivo('João Hang')).toBe('Já recebeu cobrança hoje (às 10h15).');
  });

  it('o horário não trava item a item (a tela confere uma vez para o lote; o envio confere de novo)', () => {
    const r = lote({ contas: [conta('a1', '1')], clientes: [cliente('1', 'Ana')] });
    expect(r.vao).toHaveLength(1);
  });

  it('uma mensagem por número: o segundo cliente com o mesmo WhatsApp fica de fora, citando quem já recebe', () => {
    const r = lote({
      contas: [conta('a1', '1', { balance_amount: 2000, amount: 2000 }), conta('b1', '2')],
      clientes: [cliente('1', 'Rodrigo', { whatsapp: '(47) 98888-1111' }), cliente('2', 'Rodrigo ME', { whatsapp: '+55 47 98888-1111' })],
    });
    expect(r.vao.map((i) => i.cliente.name)).toEqual(['Rodrigo']);
    expect(r.fora).toEqual([{ cliente: 'Rodrigo ME', motivo: 'O mesmo número já recebe a cobrança de Rodrigo neste lote.' }]);
  });

  it('quem deve mais vencido vem primeiro; passou de 20, o resto fica de fora para o próximo lote', () => {
    const ids = Array.from({ length: MAX_CLIENTES_DO_LOTE + 2 }, (_, k) => String(k + 1));
    const r = lote({
      contas: ids.map((id) => conta(`c${id}`, id, { amount: 100 * Number(id), balance_amount: 100 * Number(id) })),
      clientes: ids.map((id) => cliente(id, `Cliente ${id}`)),
    });
    expect(r.vao).toHaveLength(MAX_CLIENTES_DO_LOTE);
    expect(r.vao[0].cliente.name).toBe('Cliente 22');
    expect(r.fora.map((f) => f.cliente)).toEqual(['Cliente 2', 'Cliente 1']);
    expect(r.fora[0].motivo).toBe('Passa do limite de 20 clientes por lote: cobre no próximo.');
  });

  it('conta sem cliente do cadastro aparece de fora (contada), e cadastro não achado também', () => {
    const r = lote({
      contas: [conta('a1', null), conta('a2', null), conta('a3', '9'), conta('a4', null, { due_date: '2026-12-30' })],
      clientes: [],
    });
    expect(r.vao).toEqual([]);
    expect(r.fora).toEqual([
      { cliente: 'cliente', motivo: 'O cadastro do cliente não foi encontrado.' },
      { cliente: '2 contas', motivo: 'Sem cliente do cadastro: ligue a conta a um cliente para cobrar.' },
    ]);
  });
});
