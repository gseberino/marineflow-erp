// "Este Pix paga…" (02/10/2026): a mesma regra da função do banco, dita antes do clique.
import { describe, it, expect } from 'vitest';
import {
  analisarItem, resumir, distribuirPeloVencimento, montarAplicacoes, type ContaEmAberto,
} from './este-pix-paga';

const brl = (v: number) => `R$ ${v.toFixed(2).replace('.', ',')}`;

const conta = (id: string, saldo: number, vencimento: string): ContaEmAberto => ({
  id, descricao: `Conta ${id}`, documento: null, vencimento, valor: saldo, pago: 0, saldo,
});

describe('analisarItem', () => {
  it('valor igual ao saldo: nada a dizer', () => {
    const a = analisarItem({ contaId: 'a', saldo: 2280, valor: 2280, quitar: false }, brl);
    expect(a).toMatchObject({ acrescimo: 0, falta: 0, erro: null, aviso: null });
  });

  it('até R$ 10 a mais vira receita da conta (o caso do ORÇ-00073: R$ 0,53)', () => {
    const a = analisarItem({ contaId: 'a', saldo: 1865.47, valor: 1866, quitar: false }, brl);
    expect(a.acrescimo).toBe(0.53);
    expect(a.erro).toBeNull();
    expect(a.aviso).toContain('R$ 0,53 a mais viram receita');
  });

  it('mais de R$ 10 a mais é erro: avaliar antes', () => {
    const a = analisarItem({ contaId: 'a', saldo: 400, valor: 500, quitar: false }, brl);
    expect(a.erro).toContain('Acima de R$ 10');
  });

  it('até R$ 10 a menos pode quitar com desconto; sem quitar, fica em aberto', () => {
    const sem = analisarItem({ contaId: 'a', saldo: 1000, valor: 995, quitar: false }, brl);
    expect(sem.podeQuitar).toBe(true);
    expect(sem.desconto).toBe(0);
    expect(sem.aviso).toContain('Ficam R$ 5,00 em aberto');
    const com = analisarItem({ contaId: 'a', saldo: 1000, valor: 995, quitar: true }, brl);
    expect(com.desconto).toBe(5);
    expect(com.aviso).toContain('viram desconto');
  });

  it('mais de R$ 10 a menos não quita: fica em aberto (pagamento parcial)', () => {
    const a = analisarItem({ contaId: 'a', saldo: 1000, valor: 600, quitar: true }, brl);
    expect(a.podeQuitar).toBe(false);
    expect(a.desconto).toBe(0);
    expect(a.aviso).toContain('Ficam R$ 400,00 em aberto');
  });

  it('valor zero é erro', () => {
    expect(analisarItem({ contaId: 'a', saldo: 100, valor: 0, quitar: false }, brl).erro).toBeTruthy();
  });
});

describe('resumir', () => {
  it('o Pix do Lenine nos dois sinais: aplicado inteiro, pode aplicar', () => {
    const s = resumir(4800, [
      { contaId: 'a', saldo: 2280, valor: 2280, quitar: false },
      { contaId: 'b', saldo: 2520, valor: 2520, quitar: false },
    ], [], brl);
    expect(s).toMatchObject({ aplicado: 4800, sobra: 0, podeAplicar: true });
  });

  it('sobra trava e explica; até R$ 10 sugere pôr numa das contas', () => {
    const grande = resumir(4800, [{ contaId: 'a', saldo: 2280, valor: 2280, quitar: false }], [], brl);
    expect(grande.podeAplicar).toBe(false);
    expect(grande.mensagem).toContain('Sobram R$ 2520,00');
    const pequena = resumir(1866, [{ contaId: 'a', saldo: 1865.47, valor: 1865.47, quitar: false }], [], brl);
    expect(pequena.mensagem).toContain('até R$ 10 vira receita');
  });

  it('passar do que falta aplicar trava', () => {
    const s = resumir(500, [{ contaId: 'a', saldo: 600, valor: 600, quitar: false }], [], brl);
    expect(s.podeAplicar).toBe(false);
    expect(s.mensagem).toContain('Passa R$ 100,00');
  });

  it('pagamento já lançado conta no aplicado', () => {
    const s = resumir(700, [], [700], brl);
    expect(s.podeAplicar).toBe(true);
  });

  it('nada marcado não aplica', () => {
    expect(resumir(100, [], [], brl).podeAplicar).toBe(false);
  });

  it('erro de uma conta trava mesmo com a soma certa', () => {
    const s = resumir(500, [{ contaId: 'a', saldo: 400, valor: 500, quitar: false }], [], brl);
    expect(s.podeAplicar).toBe(false);
    expect(s.mensagem).toContain('Acima de R$ 10');
  });

  it('centavos sem erro de arredondamento', () => {
    const s = resumir(0.3, [
      { contaId: 'a', saldo: 0.1, valor: 0.1, quitar: false },
      { contaId: 'b', saldo: 0.2, valor: 0.2, quitar: false },
    ], [], brl);
    expect(s.sobra).toBe(0);
    expect(s.podeAplicar).toBe(true);
  });
});

describe('distribuirPeloVencimento', () => {
  it('a mais antiga primeiro, até a entrada acabar', () => {
    const d = distribuirPeloVencimento(3000, [
      conta('nova', 2000, '2026-09-10'),
      conta('velha', 2280, '2026-08-01'),
    ]);
    expect(d).toEqual({ velha: 2280, nova: 720 });
  });

  it('entrada maior que tudo: cada conta recebe o seu saldo', () => {
    expect(distribuirPeloVencimento(10000, [conta('a', 100, '2026-01-01')])).toEqual({ a: 100 });
  });
});

describe('montarAplicacoes', () => {
  it('quitar só vai quando a falta cabe na tolerância', () => {
    expect(montarAplicacoes([
      { contaId: 'a', saldo: 1000, valor: 995, quitar: true },
      { contaId: 'b', saldo: 1000, valor: 600, quitar: true },
    ], ['p1'])).toEqual([
      { receivable_id: 'a', valor: 995, quitar: true },
      { receivable_id: 'b', valor: 600, quitar: false },
      { pagamento_id: 'p1' },
    ]);
  });
});
