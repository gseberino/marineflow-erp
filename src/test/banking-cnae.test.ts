import { describe, it, expect } from 'vitest';
import { categoriaPorCnae, lerRespostaDaReceita } from '../../supabase/functions/_shared/banking/cnae';

describe('categoriaPorCnae', () => {
  it('o prefixo mais específico vence', () => {
    expect(categoriaPorCnae('4731-8/00')).toBe('Combustível e deslocamento');
    expect(categoriaPorCnae(4744099)).toBe('Ferramentas e equipamentos');
    expect(categoriaPorCnae('4742300')).toBe('Peças e materiais');
    expect(categoriaPorCnae('4763603')).toBe('Peças e materiais');       // embarcações e acessórios
    expect(categoriaPorCnae('5611201')).toBe('Alimentação de campo');
    expect(categoriaPorCnae('6920601')).toBe('Contabilidade e assessoria');
    expect(categoriaPorCnae('4930202')).toBe('Frete e importação');
  });
  it('atividade desconhecida não inventa categoria', () => {
    expect(categoriaPorCnae('0111301')).toBeNull();   // cultivo de arroz
    expect(categoriaPorCnae(null)).toBeNull();
    expect(categoriaPorCnae('')).toBeNull();
  });
});

describe('lerRespostaDaReceita', () => {
  it('reduz a resposta da BrasilAPI ao que o cadastro usa', () => {
    const d = lerRespostaDaReceita('90136409000122', {
      razao_social: 'TSD LOGISTICA E DISTRIBUIDORA LTDA', nome_fantasia: '',
      cnae_fiscal: 4930202, cnae_fiscal_descricao: 'Transporte rodoviário de carga',
      descricao_tipo_de_logradouro: 'RUA', logradouro: 'BLUMENAU', numero: '100', municipio: 'ITAJAI', uf: 'SC',
      cep: '88301000', ddd_telefone_1: '(47) 3344-5566', descricao_situacao_cadastral: 'ATIVA',
    });
    expect(d).toMatchObject({
      razao_social: 'TSD LOGISTICA E DISTRIBUIDORA LTDA', nome_fantasia: null, cnae: '4930202',
      logradouro: 'RUA BLUMENAU', cidade: 'ITAJAI', telefone: '4733445566', situacao: 'ATIVA',
      categoria_sugerida: 'Frete e importação',
    });
  });
});
