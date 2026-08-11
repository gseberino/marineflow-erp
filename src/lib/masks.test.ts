// Cobertura das máscaras e validações de cadastro — módulo sem teste até agora.
//
// São funções pequenas usadas em quase toda tela de cadastro, e duas delas passam de
// "formatação" para "dado que sai do sistema":
//   · `normalizePhoneE164` decide o número para onde o WhatsApp é enviado;
//   · `parseMoney`/`maskMoney` são a ida e a volta de todo campo de dinheiro digitado.
//
// Máscara errada não derruba nada — só grava o dado torto, e ninguém revisa cadastro antigo.
import { describe, it, expect } from 'vitest';
import {
  maskCPF, maskCNPJ, maskCPFCNPJ, maskPhone, maskCEP,
  maskMoney, parseMoney, formatMoneyFromNumber,
  isValidCPF, isValidCNPJ, isValidPhone, normalizePhoneE164,
} from './masks';

describe('máscaras de documento', () => {
  it('CPF ganha pontos e traço na medida em que é digitado', () => {
    expect(maskCPF('123')).toBe('123');
    expect(maskCPF('123456')).toBe('123.456');
    expect(maskCPF('123456789')).toBe('123.456.789');
    expect(maskCPF('12345678909')).toBe('123.456.789-09');
  });

  it('CNPJ idem, com a barra da filial', () => {
    expect(maskCNPJ('12')).toBe('12');
    expect(maskCNPJ('12345')).toBe('12.345');
    expect(maskCNPJ('12345678')).toBe('12.345.678');
    expect(maskCNPJ('123456780001')).toBe('12.345.678/0001');
    expect(maskCNPJ('12345678000199')).toBe('12.345.678/0001-99');
  });

  it('dígito a mais é descartado em vez de deformar a máscara', () => {
    expect(maskCPF('123456789099999')).toBe('123.456.789-09');
    expect(maskCNPJ('1234567800019999')).toBe('12.345.678/0001-99');
  });

  it('texto colado com pontuação é remascarado, não duplicado', () => {
    expect(maskCPF('123.456.789-09')).toBe('123.456.789-09');
    expect(maskCNPJ('12.345.678/0001-99')).toBe('12.345.678/0001-99');
    expect(maskCPF('abc123def456ghi789jkl09')).toBe('123.456.789-09');
  });

  it('o campo único decide entre CPF e CNPJ pelo número de dígitos', () => {
    expect(maskCPFCNPJ('12345678909')).toBe('123.456.789-09');
    expect(maskCPFCNPJ('12345678000199')).toBe('12.345.678/0001-99');
    // na transição, os 12 dígitos já são tratados como CNPJ
    expect(maskCPFCNPJ('123456789099')).toBe('12.345.678/9099');
  });

  it('CEP e telefone', () => {
    expect(maskCEP('88301000')).toBe('88301-000');
    expect(maskCEP('883')).toBe('883');
    expect(maskPhone('')).toBe('');
    expect(maskPhone('47')).toBe('(47');
    expect(maskPhone('4733')).toBe('(47) 33');
    expect(maskPhone('4733001234')).toBe('(47) 3300-1234');   // fixo, 10 dígitos
    expect(maskPhone('47999990000')).toBe('(47) 99999-0000'); // celular, 11
  });
});

describe('validação de documento', () => {
  it('aceita CPF e CNPJ com dígito verificador correto', () => {
    expect(isValidCPF('123.456.789-09')).toBe(true);
    expect(isValidCNPJ('11.222.333/0001-81')).toBe(true);
  });

  it('recusa dígito verificador errado', () => {
    expect(isValidCPF('123.456.789-00')).toBe(false);
    expect(isValidCNPJ('11.222.333/0001-00')).toBe(false);
  });

  it('recusa comprimento errado', () => {
    expect(isValidCPF('1234567890')).toBe(false);
    expect(isValidCNPJ('1122233300018')).toBe(false);
    expect(isValidCPF('')).toBe(false);
  });

  it('recusa a sequência repetida, que passa na conta mas não existe', () => {
    // 111.111.111-11 fecha a aritmética do dígito verificador. É o caso que todo validador
    // ingênuo aceita — e o que mais aparece em cadastro preenchido às pressas.
    for (const d of ['00000000000', '11111111111', '99999999999']) {
      expect(isValidCPF(d), d).toBe(false);
    }
    expect(isValidCNPJ('11111111111111')).toBe(false);
  });

  it('telefone válido é o de 10 ou 11 dígitos', () => {
    expect(isValidPhone('(47) 3300-1234')).toBe(true);
    expect(isValidPhone('(47) 99999-0000')).toBe(true);
    expect(isValidPhone('99999-0000')).toBe(false);   // sem DDD
    expect(isValidPhone('47999990000123')).toBe(false);
  });
});

describe('dinheiro — ida e volta do campo digitado', () => {
  it('máscara de caixa registradora: os dois últimos dígitos são centavos', () => {
    expect(maskMoney('19990')).toBe('199,90');
    expect(maskMoney('1299900')).toBe('12.999,00');
    expect(maskMoney('1')).toBe('0,01');
    expect(maskMoney('')).toBe('');
    expect(maskMoney(null)).toBe('');
    expect(maskMoney(undefined)).toBe('');
  });

  it('separador de milhar entra a cada três casas', () => {
    expect(maskMoney('100000000')).toBe('1.000.000,00');
  });

  it('zeros à esquerda não sobram', () => {
    expect(maskMoney('000019990')).toBe('199,90');
  });

  it('parseMoney entende o texto mascarado — inclusive com milhar', () => {
    // É a diferença desta implementação para a do importador de CSV (NOVO-011): aqui os
    // dígitos são extraídos e divididos por 100, então o ponto de milhar não atrapalha.
    expect(parseMoney('1.299,90')).toBe(1299.9);
    expect(parseMoney('199,90')).toBe(199.9);
    expect(parseMoney('12.999,00')).toBe(12999);
    expect(parseMoney('')).toBe(0);
    expect(parseMoney(null)).toBe(0);
    expect(parseMoney(42.5)).toBe(42.5);
  });

  it('ida e volta preserva o valor', () => {
    for (const centavos of ['1', '19990', '1299900', '100000000']) {
      expect(parseMoney(maskMoney(centavos))).toBe(parseInt(centavos, 10) / 100);
    }
  });

  it('formatMoneyFromNumber arredonda para o centavo mais próximo', () => {
    expect(formatMoneyFromNumber(199.9)).toBe('199,90');
    expect(formatMoneyFromNumber(199.999)).toBe('200,00');
    expect(formatMoneyFromNumber(12999)).toBe('12.999,00');
  });

  it('zero e inválido viram campo vazio — o input mostra o placeholder', () => {
    expect(formatMoneyFromNumber(0)).toBe('');
    expect(formatMoneyFromNumber(null)).toBe('');
    expect(formatMoneyFromNumber(NaN)).toBe('');
    expect(formatMoneyFromNumber(Infinity)).toBe('');
  });
});

describe('normalizePhoneE164 — o número para onde a mensagem vai', () => {
  it('número brasileiro com DDD ganha o DDI 55', () => {
    expect(normalizePhoneE164('(47) 99999-0000')).toBe('5547999990000');
    expect(normalizePhoneE164('4733001234')).toBe('554733001234');
  });

  it('número que já tem DDI é mantido', () => {
    expect(normalizePhoneE164('5547999990000')).toBe('5547999990000');
    expect(normalizePhoneE164('+55 47 99999-0000')).toBe('5547999990000');
  });

  it('prefixo internacional 00 é removido antes de decidir', () => {
    expect(normalizePhoneE164('005547999990000')).toBe('5547999990000');
  });

  it('número curto demais volta só com os dígitos — não inventa DDD', () => {
    // Um "99999-0000" sem DDD não dá para completar por adivinhação: prefixar 55 aqui
    // produziria um número existente de OUTRA pessoa.
    expect(normalizePhoneE164('99999-0000')).toBe('999990000');
    expect(normalizePhoneE164('33001234')).toBe('33001234');
  });

  it('vazio e nulo devolvem string vazia, nunca "55"', () => {
    expect(normalizePhoneE164('')).toBe('');
    expect(normalizePhoneE164(null)).toBe('');
    expect(normalizePhoneE164(undefined)).toBe('');
    expect(normalizePhoneE164('sem número')).toBe('');
  });

  it('aceita outro DDI quando informado', () => {
    expect(normalizePhoneE164('4733001234', '1')).toBe('14733001234');
  });
});
