import { describe, it, expect } from 'vitest';
import { nomeDoBanco, origemDoDinheiro } from './origem-do-dinheiro';

// As quatro contas da HBR como estão cadastradas (28/09/2026).
const C6 = { label: 'C6 - Conta PJ HBR', institution: null, provider: 'pluggy' };
const NUBANK = { label: 'Nubank PJ HBR', institution: null, provider: 'pluggy' };
const INFINITEPAY = { label: 'Infinitepay PJ - HBR', institution: null, provider: 'pluggy' };
const CAIXA = { label: 'Caixa (dinheiro)', institution: 'Dinheiro em espécie', provider: 'caixa' };

describe('origem do dinheiro', () => {
  it('o nome do banco sai do rótulo da conexão', () => {
    expect(nomeDoBanco(C6)).toBe('C6');
    expect(nomeDoBanco(NUBANK)).toBe('Nubank');
    expect(nomeDoBanco(INFINITEPAY)).toBe('InfinitePay');
    expect(nomeDoBanco({ label: 'Banco Inter PJ' })).toBe('Inter');
    expect(nomeDoBanco({ label: 'Cooperativa X - PJ' })).toBe('Cooperativa');
    expect(nomeDoBanco(null)).toBeNull();
  });

  it('conta, cartão com o final e o Caixa', () => {
    expect(origemDoDinheiro({ source_type: 'bank' }, C6)).toBe('Conta C6');
    expect(origemDoDinheiro({ source_type: 'bank' }, NUBANK)).toBe('Conta Nubank');
    expect(origemDoDinheiro({ source_type: 'credit_card', card_last_digits: '4922' }, NUBANK)).toBe('Cartão Nubank final 4922');
    expect(origemDoDinheiro({ source_type: 'credit_card', card_last_digits: '****7130' }, C6)).toBe('Cartão C6 final 7130');
    expect(origemDoDinheiro({ source_type: 'credit_card', card_last_digits: null }, C6)).toBe('Cartão C6');
    expect(origemDoDinheiro({ source_type: 'cash' }, CAIXA)).toBe('Caixa (dinheiro)');
    expect(origemDoDinheiro({ source_type: 'bank' }, CAIXA)).toBe('Caixa (dinheiro)');
  });

  it('sem a conta (linha antiga importada à mão) fica só o tipo; sem linha, nada', () => {
    expect(origemDoDinheiro({ source_type: 'bank' }, null)).toBe('Conta corrente');
    expect(origemDoDinheiro({ source_type: 'credit_card', card_last_digits: '9282' }, undefined)).toBe('Cartão de crédito final 9282');
    expect(origemDoDinheiro(null, C6)).toBeNull();
  });
});
