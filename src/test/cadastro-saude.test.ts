// Saúde do cadastro de fornecedores.
//
// O caso que originou tudo: o cadastro da Coremma tinha fantasia "Itajai" — a CIDADE —, e
// isso atribuiu 160 despesas ao fornecedor errado. O que se testa aqui é o princípio que
// substitui o julgamento sobre a palavra: o apelido que aparece em transações de OUTROS
// não identifica ninguém, e a acusação vem com número em vez de opinião.
import { describe, it, expect } from 'vitest';
import {
  analisarFornecedor, acharDuplicados, ordenarProblemas, documentoValido, normalizar,
  type FornecedorParaAnalise,
} from '@/lib/cadastro-saude';

const forn = (o: Partial<FornecedorParaAnalise> = {}): FornecedorParaAnalise => ({
  id: 'f1', name: 'Fornecedor Teste', trade_name: null, cnpj_cpf: null,
  active: true, lancamentos: 5, ...o,
});

describe('apelido que não identifica', () => {
  it('acusa a fantasia que aparece em transações de outros — o caso Itajai', () => {
    const [p] = analisarFornecedor(forn({
      name: 'Coremma Ltda', trade_name: 'Itajai', fantasia_em_terceiros: 89,
      cnpj_cpf: '83.109.504/0006-86',
    }));
    expect(p.tipo).toBe('fantasia_generica');
    expect(p.gravidade).toBe('alta');
    // A acusação tem de trazer o número: sem evidência é opinião sobre a palavra.
    expect(p.evidencia).toContain('89');
    expect(p.correcao).toEqual({ campo: 'trade_name', valor: null });
  });

  it('não acusa apelido legítimo, mesmo sendo uma palavra só', () => {
    // "KAMELL" é uma palavra e é o que o extrato escreve — apelido de verdade. Julgar
    // pelo formato condenaria este junto com "Itajai".
    const problemas = analisarFornecedor(forn({
      name: 'KAMELL COMERCIO GLOBAL LTDA', trade_name: 'KAMELL',
      fantasia_em_terceiros: 0, cnpj_cpf: '11.222.333/0001-81',
    }));
    expect(problemas.find((p) => p.tipo === 'fantasia_generica')).toBeUndefined();
  });

  it('fantasia igual à razão social é ruído, não perigo', () => {
    const [p] = analisarFornecedor(forn({
      name: 'SR Contabilidade', trade_name: 'SR Contabilidade',
      cnpj_cpf: '11.222.333/0001-81',
    }));
    expect(p.tipo).toBe('fantasia_igual_razao');
    expect(p.gravidade).toBe('baixa');
  });
});

describe('documento', () => {
  it('reconhece CNPJ e CPF válidos', () => {
    expect(documentoValido('11.222.333/0001-81')).toBe(true);
    expect(documentoValido('529.982.247-25')).toBe(true);
  });

  it('recusa dígito verificador errado e sequência repetida', () => {
    expect(documentoValido('11.222.333/0001-99')).toBe(false);
    expect(documentoValido('111.111.111-11')).toBe(false);
    expect(documentoValido('123')).toBe(false);
  });

  it('documento inválido é ALTA, e sem documento é média', () => {
    const [invalido] = analisarFornecedor(forn({ cnpj_cpf: '11.222.333/0001-99' }));
    expect(invalido.tipo).toBe('documento_invalido');
    expect(invalido.gravidade).toBe('alta');

    const [vazio] = analisarFornecedor(forn({ cnpj_cpf: null, lancamentos: 3 }));
    expect(vazio.tipo).toBe('sem_documento');
    expect(vazio.gravidade).toBe('media');
  });

  it('não cobra documento de cadastro que ninguém usa', () => {
    // Exigir ficha completa de cadastro inerte é criar trabalho que não muda nada.
    const problemas = analisarFornecedor(forn({ cnpj_cpf: null, lancamentos: 0 }));
    expect(problemas.find((p) => p.tipo === 'sem_documento')).toBeUndefined();
    expect(problemas.find((p) => p.tipo === 'inerte')).toBeDefined();
  });
});

describe('cadastro inerte', () => {
  it('propõe arquivar, não apagar', () => {
    const [p] = analisarFornecedor(forn({ lancamentos: 0, cnpj_cpf: '11.222.333/0001-81' }));
    expect(p.tipo).toBe('inerte');
    expect(p.correcao).toEqual({ campo: 'active', valor: false });
    expect(p.sugestao).toContain('volta a qualquer momento');
  });

  it('não incomoda com quem já está arquivado', () => {
    const problemas = analisarFornecedor(forn({ lancamentos: 0, active: false, cnpj_cpf: '11.222.333/0001-81' }));
    expect(problemas).toEqual([]);
  });
});

describe('duplicados', () => {
  it('mesmo documento é certeza, não suspeita', () => {
    const grupos = acharDuplicados([
      forn({ id: 'a', name: 'PREMEL MAT ELETRICOS', cnpj_cpf: '00.725.876/0008-71' }),
      forn({ id: 'b', name: 'Premel Materiais', cnpj_cpf: '00725876000871' }),
    ]);
    expect(grupos).toHaveLength(1);
    expect(grupos[0].motivo).toContain('CNPJ');
    expect(grupos[0].membros).toHaveLength(2);
  });

  it('mesmo nome também agrupa, sem repetir quem já foi pego pelo documento', () => {
    const grupos = acharDuplicados([
      forn({ id: 'a', name: 'Loja X', cnpj_cpf: '11.222.333/0001-81' }),
      forn({ id: 'b', name: 'LOJA X', cnpj_cpf: '11222333000181' }),
      forn({ id: 'c', name: 'Outra' }),
      forn({ id: 'd', name: 'OUTRA' }),
    ]);
    expect(grupos).toHaveLength(2);
    expect(grupos.filter((g) => g.motivo === 'Mesmo nome')).toHaveLength(1);
  });

  it('documento diferente não vira duplicata só porque o nome parece', () => {
    const grupos = acharDuplicados([
      forn({ id: 'a', name: 'Marine Express', cnpj_cpf: '11.222.333/0001-81' }),
      forn({ id: 'b', name: 'Marine Sports', cnpj_cpf: '11.444.777/0001-61' }),
    ]);
    expect(grupos).toHaveLength(0);
  });
});

describe('fila de trabalho', () => {
  it('o que sequestra casamento vem antes do que só ocupa espaço', () => {
    const problemas = ordenarProblemas([
      ...analisarFornecedor(forn({ id: 'z', name: 'Zeta', lancamentos: 0, cnpj_cpf: '11.222.333/0001-81' })),
      ...analisarFornecedor(forn({ id: 'a', name: 'Alfa', trade_name: 'Itajai', fantasia_em_terceiros: 89, cnpj_cpf: '11.222.333/0001-81' })),
    ]);
    expect(problemas[0].gravidade).toBe('alta');
    expect(problemas[0].fornecedor).toBe('Alfa');
  });
});

describe('normalização', () => {
  it('ignora acento, caixa e pontuação', () => {
    expect(normalizar('Ótica  São-João Ltda.')).toBe('OTICA SAO JOAO LTDA');
    expect(normalizar(null)).toBe('');
  });
});
