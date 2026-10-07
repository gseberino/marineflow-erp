// Regras puras dos defeitos de tela da auditoria de 06–07/10/2026: a cobrança ligada à conta a
// receber (2), as travas da ordem de compra (4) e a regra de repetição da tarefa (5).
import { describe, it, expect } from 'vitest';
import { escolherRecebivel, recebivelDaEscolha, type RecebivelDaOS } from './recebivel-da-cobranca';
import { motivoDaTrava, podeCancelar, podeEditar, podeExcluir, situacoesPermitidas } from './travas-da-oc';
import { descreverRepeticao, lerRepeticao, montarRrule } from './regra-de-repeticao';
// O motor e o assistente: a regra que a tela grava tem de ser lida igual por eles.
import { parseRRule } from '../../supabase/functions/_shared/recurrence';

const conta = (id: string, status: string, saldo = 100): RecebivelDaOS =>
  ({ id, description: `Parcela ${id}`, amount: saldo, balance_amount: saldo, due_date: '2026-10-20', status });

describe('escolherRecebivel (2: cobrança da OS ligada à conta a receber)', () => {
  it('uma conta em aberto: é ela', () => {
    const e = escolherRecebivel([conta('a', 'paid'), conta('b', 'pending')]);
    expect(e.tipo).toBe('uma');
    expect(recebivelDaEscolha(e)?.id).toBe('b');
  });

  it('várias em aberto: nenhuma até a pessoa escolher', () => {
    const contas = [conta('a', 'pending'), conta('b', 'overdue'), conta('c', 'partially_paid')];
    const e = escolherRecebivel(contas);
    expect(e.tipo).toBe('escolher');
    expect(recebivelDaEscolha(e)).toBeNull();
    expect(recebivelDaEscolha(escolherRecebivel(contas, 'c'))?.id).toBe('c');
  });

  it('todas pagas: não há o que cobrar; sem conta: fica sem vínculo; cancelada não conta', () => {
    expect(escolherRecebivel([conta('a', 'paid')]).tipo).toBe('pagas');
    expect(escolherRecebivel([]).tipo).toBe('sem_conta');
    expect(escolherRecebivel([conta('a', 'cancelled')]).tipo).toBe('sem_conta');
  });
});

describe('travas da OC (4: como as tools de compras-ciclo.ts)', () => {
  const oc = (status: any, recebido = 0) => ({ status, purchase_order_items: [{ received_qty: recebido }] });

  it('recebida: nada — nem cancelar, nem excluir, nem editar, nem mudar situação', () => {
    expect(podeCancelar(oc('received', 2))).toBe(false);
    expect(podeExcluir(oc('received', 2))).toBe(false);
    expect(podeEditar(oc('received', 2))).toBe(false);
    expect(situacoesPermitidas(oc('received', 2))).toEqual([]);
    expect(motivoDaTrava(oc('received', 2), 'editar')).toMatch(/Toda recebida/);
  });

  it('recebida em parte: não cancela (deixaria a compra sem conta a pagar) nem exclui', () => {
    expect(podeCancelar(oc('partial', 1))).toBe(false);
    expect(podeExcluir(oc('partial', 1))).toBe(false);
    expect(situacoesPermitidas(oc('partial', 1))).toEqual([]);
  });

  it('rascunho sem nada recebido: tudo; enviada: cancela e edita, mas não exclui', () => {
    expect([podeCancelar(oc('draft')), podeExcluir(oc('draft')), podeEditar(oc('draft'))]).toEqual([true, true, true]);
    expect([podeCancelar(oc('sent')), podeExcluir(oc('sent')), podeEditar(oc('sent'))]).toEqual([true, false, true]);
    expect(motivoDaTrava(oc('sent'), 'excluir')).toMatch(/cancele/);
    expect(situacoesPermitidas(oc('sent'))).toEqual(['draft', 'cancelled']);
  });

  it('item já recebido trava mesmo com a situação desatualizada', () => {
    expect(podeCancelar(oc('sent', 1))).toBe(false);
    expect(podeExcluir(oc('draft', 1))).toBe(false);
  });

  it('cancelada volta para rascunho ou enviada, mas não se edita direto', () => {
    expect(situacoesPermitidas(oc('cancelled'))).toEqual(['draft', 'sent']);
    expect(podeEditar(oc('cancelled'))).toBe(false);
  });
});

describe('regra de repetição (5: o diálogo não apaga INTERVAL e BYDAY)', () => {
  const OITO_DA_MANHA = '2026-10-12T11:00:00.000Z';   // segunda, 08:00 em Brasília
  const NOVE_DA_NOITE = '2026-10-12T00:30:00.000Z';   // domingo, 21:30 em Brasília (segunda em UTC)

  it('"a cada 15 dias" volta igual', () => {
    const r = lerRepeticao('FREQ=DAILY;INTERVAL=15', OITO_DA_MANHA)!;
    expect(r).toMatchObject({ freq: 'DAILY', intervalo: 15, dias: [] });
    expect(montarRrule(r, OITO_DA_MANHA)).toBe('FREQ=DAILY;INTERVAL=15');
    expect(descreverRepeticao(r)).toBe('a cada 15 dias');
  });

  it('"toda segunda e quinta até 31/12" volta igual', () => {
    const rrule = 'FREQ=WEEKLY;BYDAY=MO,TH;UNTIL=20261231';
    const r = lerRepeticao(rrule, OITO_DA_MANHA)!;
    expect(r).toMatchObject({ freq: 'WEEKLY', intervalo: 1, dias: [1, 4], ate: '2026-12-31' });
    expect(montarRrule(r, OITO_DA_MANHA)).toBe(rrule);
    expect(descreverRepeticao(r)).toBe('toda segunda e quinta');
  });

  it('BYDAY é o dia de UTC: às 21h30 de domingo em Brasília a regra diz MO, a tela mostra domingo', () => {
    const r = lerRepeticao('FREQ=WEEKLY;BYDAY=MO', NOVE_DA_NOITE)!;
    expect(r.dias).toEqual([0]);
    expect(montarRrule(r, NOVE_DA_NOITE)).toBe('FREQ=WEEKLY;BYDAY=MO');
    // Mudou o horário para 08:00 de domingo: o mesmo domingo em Brasília vira SU em UTC.
    expect(montarRrule(r, '2026-10-11T11:00:00.000Z')).toBe('FREQ=WEEKLY;BYDAY=SU');
  });

  it('parte que o diálogo não edita volta como veio; o motor lê o que a tela grava', () => {
    const r = lerRepeticao('FREQ=MONTHLY;INTERVAL=2;COUNT=5', OITO_DA_MANHA)!;
    const gravada = montarRrule(r, OITO_DA_MANHA);
    expect(gravada).toBe('FREQ=MONTHLY;INTERVAL=2;COUNT=5');
    expect(parseRRule(gravada)).toMatchObject({ freq: 'MONTHLY', interval: 2 });
    expect(parseRRule(montarRrule({ freq: 'WEEKLY', intervalo: 2, dias: [1, 4], ate: '', outras: [] }, OITO_DA_MANHA)))
      .toMatchObject({ freq: 'WEEKLY', interval: 2, byday: [1, 4] });
  });

  it('sem regra (ou regra que o motor não entende) = não repete', () => {
    expect(lerRepeticao(null)).toBeNull();
    expect(lerRepeticao('FREQ=YEARLY')).toBeNull();
  });
});
