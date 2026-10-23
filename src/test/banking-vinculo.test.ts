// Vínculo de uma linha do extrato com o que ela paga — casos de 25/09/2026.
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import {
  sugerirVinculo, vinculoAutomatico, exigeDecisao, perguntaDaOSAberta, temPerguntaDaOS,
} from '../../supabase/functions/_shared/banking/vinculo';
import type { BankTx, Candidate } from '../../supabase/functions/_shared/banking/types';

const entrada = (v: number, data: string, extra: Partial<BankTx> = {}): BankTx => ({
  id: 't', transaction_date: data, description: 'PIX RECEBIDO', amount: v, transaction_type: 'credit', ...extra,
});

describe('sugerirVinculo', () => {
  it('sinal já lançado à mão vira "casar", não receita nova (ORÇ-00084, R$ 591,41)', () => {
    const cands: Candidate[] = [{
      kind: 'existing_payment', id: 'pg1', label: 'Pagamento já lançado: Sinal — ORÇ-00084', amount: 591.41,
      direction: 'credit', dueDate: '2026-08-21', clientId: 'c-robson', clientName: 'ROBSON', receivableId: 'r84',
      serviceOrderId: 'os84', documentNumber: 'ORÇ-00084',
    }];
    const v = sugerirVinculo(entrada(591.41, '2026-08-20', { counterparty_name: 'POWER LOG LTDA', counterparty_document: '08878680000152' }), cands);
    expect(v?.principal).toMatchObject({ tipo: 'existing_payment', lancamentoId: 'r84', lado: 'receivable', jaLancado: true });
    // Valor exato, mas o pagador não é o cliente do orçamento: não decide sozinho…
    expect(vinculoAutomatico(v)).toBeNull();
    // …e por isso a aprovação às cegas é barrada: criaria a receita em dobro.
    expect(exigeDecisao(v)).toBe(true);
  });

  it('documento do cliente + valor exato é certeza — e mesmo assim pergunta (decisão do dono, 26/09/2026)', () => {
    const cands: Candidate[] = [{
      kind: 'receivable', id: 'r1', label: 'Saldo — OS-00045', amount: 1650, direction: 'credit',
      dueDate: '2026-09-05', clientId: 'c-mp', clientName: 'MP MOTOR HOMES', clientDocument: '44.051.448/0001-00',
    }];
    const v = sugerirVinculo(entrada(1650, '2026-09-05', { counterparty_document: '44051448000100' }), cands);
    expect(v?.principal.nivel).toBe('certain');
    // "O sistema deve sempre questionar": nenhum vínculo é usado sem a pessoa escolher.
    expect(vinculoAutomatico(v)).toBeNull();
    expect(exigeDecisao(v)).toBe(true);
  });

  it('sinal de orçamento nunca é automático, nem com certeza', () => {
    const cands: Candidate[] = [{
      kind: 'quote_deposit', id: 'orc', label: 'Sinal do ORÇ-00104', amount: 2000, direction: 'credit',
      referenceDate: '2026-04-20', clientId: 'c', clientName: 'Cliente', clientDocument: '11122233344', convertsQuote: true,
    }];
    const v = sugerirVinculo(entrada(2000, '2026-04-30', { counterparty_document: '11122233344' }), cands);
    expect(v?.principal.converteOrcamento).toBe(true);
    expect(vinculoAutomatico(v)).toBeNull();
  });

  it('cliente reconhecido pelo histórico sobe na lista', () => {
    const cands: Candidate[] = [
      { kind: 'service_order_balance', id: 'os-a', label: 'Saldo da OS-1', amount: 3947.48, direction: 'credit', referenceDate: '2026-01-20', clientId: 'c-outro', clientName: 'Outro' },
      { kind: 'service_order_balance', id: 'os-b', label: 'Saldo da OS-2', amount: 3947.48, direction: 'credit', referenceDate: '2026-01-20', clientId: 'c-acrisio', clientName: 'Acrisio' },
    ];
    const v = sugerirVinculo(entrada(3947.48, '2026-02-06', { counterparty_name: 'EQUIT ADMINISTRACAO' }), cands, { id: 'c-acrisio', nome: 'Acrisio' });
    expect(v?.principal.id).toBe('os-b');
    expect(v?.principal.motivos.join(' ')).toMatch(/cliente reconhecido \(Acrisio\)/);
  });

  it('saída não casa com entrada, e cobrança avulsa não é vínculo acionável', () => {
    const cands: Candidate[] = [
      { kind: 'receivable', id: 'r', label: 'x', amount: 100, direction: 'credit' },
      { kind: 'collection', id: 'c', label: 'y', amount: 100, direction: 'credit' },
    ];
    expect(sugerirVinculo({ ...entrada(100, '2026-09-01'), transaction_type: 'debit' }, cands)).toBeNull();
    expect(sugerirVinculo(entrada(100, '2026-09-01'), [cands[1]])).toBeNull();
  });

  it('possível duplicata que o motor não reconhece (ORÇ-00077: R$ 2.520 lançado, R$ 2.498 no banco)', () => {
    const cands: Candidate[] = [{
      kind: 'existing_payment', id: 'pg77', label: 'Pagamento já lançado: Sinal — ORÇ-00077', amount: 2520,
      direction: 'credit', dueDate: '2026-08-11', clientId: 'c-final', clientName: 'Cliente Final', receivableId: 'r77',
    }];
    const v = sugerirVinculo(entrada(2498, '2026-08-06', { counterparty_name: 'EDSON LUIS KREUSCH', counterparty_document: '17635478000190' }), cands);
    expect(v?.principal).toMatchObject({ tipo: 'existing_payment', lancamentoId: 'r77', jaLancado: true });
    expect(v?.principal.motivos.join(' ')).toMatch(/possível duplicata/);
    expect(exigeDecisao(v)).toBe(true);
  });

  it('pagamento já lançado de um ano depois não é o mesmo dinheiro (STONE)', () => {
    const cands: Candidate[] = [{
      kind: 'existing_payment', id: 'pg61', label: 'Pagamento já lançado: Sinal — ORÇ-00061', amount: 5000,
      direction: 'credit', dueDate: '2026-07-01', receivableId: 'r61',
    }];
    expect(sugerirVinculo(entrada(5000, '2025-08-07', { counterparty_name: 'STONE CONFECCOES LTDA' }), cands)).toBeNull();
  });

  it('valor exato já lançado por terceiro barra a aprovação no escuro (ORÇ-00075)', () => {
    const cands: Candidate[] = [{
      kind: 'existing_payment', id: 'pg75', label: 'Pagamento já lançado: Sinal — ORÇ-00075', amount: 500,
      direction: 'credit', dueDate: '2026-08-12', clientId: 'c-lu', clientName: 'LUCENIRA MARIA DE MELO', clientDocument: '12345678901', receivableId: 'r75',
    }];
    const v = sugerirVinculo(entrada(500, '2026-08-16', { counterparty_name: 'MP MOTORHOMES', counterparty_document: '44051448000100' }), cands);
    expect(v?.principal.jaLancado).toBe(true);
    expect(exigeDecisao(v)).toBe(true);
  });
});

// ─── Pagador conhecido (leva 8, 22/10/2026): sugere, nunca dá baixa ─────────────────────────────
describe('pagador conhecido no vínculo', () => {
  // A EQUIT (empresa do Acrisio) paga o saldo exato da única conta em aberto dele.
  const contaDoAcrisio: Candidate = {
    kind: 'receivable', id: 'r-acrisio', label: 'Saldo — OS-00060', amount: 3947.48, direction: 'credit',
    dueDate: '2026-02-06', clientId: 'c-acrisio', clientName: 'Acrisio Cançado Lopes', clientDocument: '000.000.000-01',
  };
  const contaDeOutro: Candidate = {
    kind: 'receivable', id: 'r-outro', label: 'Saldo — OS-00061', amount: 3947.48, direction: 'credit',
    dueDate: '2026-02-06', clientId: 'c-outro', clientName: 'Outro Cliente', clientDocument: '111.111.111-11',
  };
  const pixDaEquit = entrada(3947.48, '2026-02-06', { counterparty_name: 'EQUIT ADMINISTRACAO DE BENS LTDA', counterparty_document: '04754513000149' });
  const acrisio = { id: 'c-acrisio', nome: 'Acrisio Cançado Lopes', por: 'pagador_conhecido', relacao: 'empresa_do_cliente' };

  it('valor exato e título único: no máximo "provável", sem baixa sozinha, e pergunta', () => {
    const v = sugerirVinculo(pixDaEquit, [contaDoAcrisio], acrisio);
    // 45 (valor exato) + 15 (data) + 10 (cliente reconhecido) = 70: provável, nunca certo
    expect(v?.principal).toMatchObject({ id: 'r-acrisio', nivel: 'probable', confianca: 70 });
    expect(vinculoAutomatico(v)).toBeNull();
    expect(exigeDecisao(v)).toBe(true);
  });

  it('o terceiro guardado não é mais evidência contra AQUELE cliente — e o motivo diz quem pagou', () => {
    const v = sugerirVinculo(pixDaEquit, [contaDoAcrisio], acrisio);
    const motivos = v!.principal.motivos.join(' | ');
    expect(motivos).not.toMatch(/confira se foi um terceiro pagando/);
    expect(motivos).toMatch(/Pago pela empresa de Acrisio Cançado Lopes \(pagador conhecido\)/);
    // sem o pagador conhecido, o mesmo candidato leva a penalidade de 20 e o aviso
    const sem = sugerirVinculo(pixDaEquit, [contaDoAcrisio], null);
    expect(sem!.principal.motivos.join(' | ')).toMatch(/confira se foi um terceiro pagando/);
    expect(v!.principal.confianca).toBeGreaterThanOrEqual(sem!.principal.confianca + 20);
  });

  it('a penalidade continua para os candidatos de OUTRO cliente', () => {
    const v = sugerirVinculo(pixDaEquit, [contaDoAcrisio, contaDeOutro], acrisio);
    const outro = [v!.principal, ...v!.alternativas].find((o) => o.id === 'r-outro');
    expect(v!.principal.id).toBe('r-acrisio');
    expect(outro?.motivos.join(' | ')).toMatch(/confira se foi um terceiro pagando/);
    expect(outro?.motivos.join(' | ')).not.toMatch(/pagador conhecido/);
  });

  it('o candidato que a penalidade escondia (data longe, só o valor) volta a aparecer — para perguntar', () => {
    // Saldo de OS sem vencimento e a 60 dias: o valor exato (45) menos a penalidade (20) ficava abaixo do corte (35).
    const saldo: Candidate = {
      kind: 'service_order_balance', id: 'os-acrisio', label: 'Saldo da OS-00060', amount: 3947.48, direction: 'credit',
      referenceDate: '2025-12-08', clientId: 'c-acrisio', clientName: 'Acrisio Cançado Lopes', clientDocument: '000.000.000-01',
    };
    expect(sugerirVinculo(pixDaEquit, [saldo], null)).toBeNull();
    const com = sugerirVinculo(pixDaEquit, [saldo], acrisio);
    expect(com?.principal).toMatchObject({ id: 'os-acrisio', nivel: 'weak' });
    expect(exigeDecisao(com)).toBe(true);
    expect(vinculoAutomatico(com)).toBeNull();
  });

  it('TRAVA: nem com o documento do pagador igual ao do cadastro a camada de certeza vale para pagador conhecido', () => {
    // Se o documento de quem pagou fosse parar no clientDocument, documento + valor exato daria certeza e baixa.
    const comODocDoPagador: Candidate = { ...contaDoAcrisio, clientDocument: '04754513000149' };
    const v = sugerirVinculo(pixDaEquit, [comODocDoPagador], acrisio);
    expect(v?.principal.nivel).not.toBe('certain');
    expect(vinculoAutomatico(v)).toBeNull();
  });

  it('histórico e documento continuam como antes (só o pagador conhecido muda a pontuação)', () => {
    const porHistorico = sugerirVinculo(pixDaEquit, [contaDoAcrisio], { id: 'c-acrisio', nome: 'Acrisio Cançado Lopes', por: 'historico' });
    expect(porHistorico!.principal.motivos.join(' | ')).toMatch(/confira se foi um terceiro pagando/);
    expect(porHistorico!.principal.motivos.join(' | ')).toMatch(/cliente reconhecido \(Acrisio Cançado Lopes\)/);
  });

  it('portão da Conciliação: o banking-reconcile continua sem aplicar sugestão sozinho', () => {
    // Os outros portões têm teste próprio: lançar sozinho (finance-lancar-sozinho.test.ts), lote da papelada
    // (papelada/lote_test.ts) e vinculoAutomatico (acima). Este é texto: a função não exporta a decisão.
    const fonte = fs.readFileSync(path.join(__dirname, '../../supabase/functions/banking-reconcile/index.ts'), 'utf8');
    expect(fonte).toMatch(/const aplicarSozinha = false;/);
    // e o matching.ts não recebe o documento de quem pagou: o motor do vínculo não escreve clientDocument
    const vinculo = fs.readFileSync(path.join(__dirname, '../../supabase/functions/_shared/banking/vinculo.ts'), 'utf8');
    expect(vinculo).not.toMatch(/clientDocument\s*[:=]/);
  });
});

describe("perguntas da OS e da OC (decisão do dono, 26/09/2026)", () => {
  const vinc = (os: string) => ({ principal: {
    tipo: "payable", id: "c", rotulo: "Conta", valor: 1, confianca: 80, nivel: "probable", motivos: [], diferenca: 0,
    lancamentoId: "c", lado: "payable", ordemDeServicoId: os, clienteId: null, clienteNome: null, converteOrcamento: false, jaLancado: false,
  }, alternativas: [] }) as never;

  it("OS fora do vínculo sem resposta: aberta; respondida: fechada", () => {
    expect(perguntaDaOSAberta({ suggested_service_order_id: "os1" })).toBe(true);
    expect(perguntaDaOSAberta({ suggested_service_order_id: "os1" }, { serviceOrderId: null })).toBe(false);
  });

  it("OS do próprio vínculo: o vínculo pergunta", () => {
    expect(temPerguntaDaOS({ suggested_service_order_id: "os1", vinculo_sugerido: vinc("os1") })).toBe(false);
    expect(perguntaDaOSAberta({ suggested_service_order_id: "os1", vinculo_sugerido: vinc("os1") })).toBe(false);
  });

  it("OS anotada: aparece (para poder desdizer), mas já é resposta", () => {
    const p = { suggested_service_order_id: "os1", vinculo_sugerido: vinc("os1"), evidencia: { anotacao: { id: "a", os_id: "os1" } } };
    expect(temPerguntaDaOS(p)).toBe(true);
    expect(perguntaDaOSAberta(p)).toBe(false);
  });

  it("OC sem resposta: aberta; 'Sim, é dela' com a OS da OC fecha as duas", () => {
    expect(perguntaDaOSAberta({ suggested_purchase_order_id: "oc1" })).toBe(true);
    expect(perguntaDaOSAberta({ suggested_purchase_order_id: "oc1", suggested_service_order_id: "os1" },
      { purchaseOrderId: "oc1", serviceOrderId: "os1" })).toBe(false);
    expect(perguntaDaOSAberta({ suggested_purchase_order_id: "oc1", suggested_service_order_id: "os1" },
      { purchaseOrderId: null })).toBe(true);
  });
});
