// Busca de cliente (nome sem acento, dígitos de CPF/telefone) e o "falta para a nota" da ficha
// do cliente na OS — este último espelha os validadores do servidor fiscal.
import { describe, it, expect } from 'vitest';
import { filtrarClientes } from './busca-cliente';
import { enderecoEmUmaLinha, faltasParaNota } from './ficha-cliente';

const base = { email: null, phone: null, whatsapp: null, cpf_cnpj: null, active: true };
const clientes = [
  { ...base, id: '1', name: 'João da Silva', phone: '(47) 99999-1234', cpf_cnpj: '123.456.789-00' },
  { ...base, id: '2', name: 'Marina Itajaí Ltda', whatsapp: '47 3300-1122', email: 'contato@marina.com.br' },
  { ...base, id: '3', name: 'Joana Inativa', active: false },
];

describe('filtrarClientes', () => {
  it('até 3 caracteres devolve os ativos, como sempre foi', () => {
    expect(filtrarClientes(clientes, 'jo').map((c) => c.id)).toEqual(['1', '2']);
  });

  it('acha sem acento e ignora inativos', () => {
    expect(filtrarClientes(clientes, 'joao').map((c) => c.id)).toEqual(['1']);
    expect(filtrarClientes(clientes, 'itajai').map((c) => c.id)).toEqual(['2']);
    expect(filtrarClientes(clientes, 'joana')).toEqual([]);
  });

  it('número sem pontuação acha telefone e CPF formatados', () => {
    expect(filtrarClientes(clientes, '47999991234').map((c) => c.id)).toEqual(['1']);
    expect(filtrarClientes(clientes, '12345678900').map((c) => c.id)).toEqual(['1']);
    expect(filtrarClientes(clientes, '33001122').map((c) => c.id)).toEqual(['2']);
  });

  it('com letra no termo, os dígitos não viram busca por telefone', () => {
    // "300" está no WhatsApp da marina, mas "Rua 300" é texto: não pode puxá-la.
    expect(filtrarClientes(clientes, 'Rua 300')).toEqual([]);
  });

  it('e-mail continua achando', () => {
    expect(filtrarClientes(clientes, 'contato@').map((c) => c.id)).toEqual(['2']);
  });
});

describe('faltasParaNota', () => {
  const completo = {
    cpf_cnpj: '123.456.789-00', address_line_1: 'Rua A, 10', neighborhood: 'Centro', city: 'Itajaí',
    state: 'SC', postal_code: '88300-000', ie_indicator: 9, state_registration: null,
  };

  it('cadastro completo não tem falta', () => {
    expect(faltasParaNota(completo)).toEqual([]);
  });

  it('lista o que o servidor recusaria', () => {
    expect(faltasParaNota({ ...completo, cpf_cnpj: null, neighborhood: '', postal_code: null }))
      .toEqual(['CPF/CNPJ', 'bairro', 'CEP']);
  });

  it('documento e CEP pela metade contam como falta', () => {
    expect(faltasParaNota({ ...completo, cpf_cnpj: '123.456', postal_code: '8830' }))
      .toEqual(['CPF/CNPJ incompleto', 'CEP incompleto']);
  });

  it('contribuinte do ICMS sem IE', () => {
    expect(faltasParaNota({ ...completo, ie_indicator: 1 })).toEqual(['inscrição estadual']);
    expect(faltasParaNota({ ...completo, ie_indicator: 1, state_registration: '123.456.789' })).toEqual([]);
  });
});

describe('enderecoEmUmaLinha', () => {
  it('junta rua, bairro e cidade/UF; null sem nada', () => {
    expect(enderecoEmUmaLinha({ address_line_1: 'Rua A, 10', neighborhood: 'Centro', city: 'Itajaí', state: 'SC' }))
      .toBe('Rua A, 10 — Centro, Itajaí/SC');
    expect(enderecoEmUmaLinha({ address_line_1: null, neighborhood: null, city: 'Itajaí', state: null })).toBe('Itajaí');
    expect(enderecoEmUmaLinha({ address_line_1: null, neighborhood: null, city: null, state: null })).toBeNull();
  });
});
