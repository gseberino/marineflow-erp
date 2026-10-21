import { describe, it, expect } from 'vitest';
import { manterSeMexeu, mesclarReleitura, mesmoValor } from './releitura-da-os';

describe('mesclarReleitura', () => {
  const base = { problem_description: 'Bomba não liga', technician_instructions: '', status: 'draft' };

  it('primeira leitura: vale o que veio do banco', () => {
    const remoto = { ...base, status: 'scheduled' };
    expect(mesclarReleitura(null, { problem_description: '', technician_instructions: '', status: 'draft' }, remoto))
      .toEqual(remoto);
  });

  it('o campo que a pessoa está digitando fica; o resto recebe o banco', () => {
    const local = { ...base, problem_description: 'Bomba não liga, fusível queimado' };
    // a gravação anterior voltou com o texto antigo, e o assistente mudou a instrução
    const remoto = { ...base, technician_instructions: 'Levar multímetro' };
    expect(mesclarReleitura(base, local, remoto)).toEqual({
      problem_description: 'Bomba não liga, fusível queimado',
      technician_instructions: 'Levar multímetro',
      status: 'draft',
    });
  });

  it('troca de status feita pelo banco aparece (a tela não mexeu no status)', () => {
    expect(mesclarReleitura(base, base, { ...base, status: 'approved' }).status).toBe('approved');
  });

  it('depois que a gravação chega, local e remoto coincidem e nada se perde', () => {
    const local = { ...base, problem_description: 'Novo texto' };
    expect(mesclarReleitura(base, local, { ...local })).toEqual(local);
  });

  it('campo que só existe na tela não é apagado', () => {
    const local = { ...base, extra: 'x' } as Record<string, unknown>;
    expect(mesclarReleitura(base as Record<string, unknown>, local, { ...base })).toHaveProperty('extra', 'x');
  });
});

describe('mesmoValor / manterSeMexeu', () => {
  it('número e texto do mesmo número são iguais; vazio e nulo também', () => {
    expect(mesmoValor(12, '12')).toBe(true);
    expect(mesmoValor(null, '')).toBe(true);
    expect(mesmoValor(0, '')).toBe(false);
  });

  it('listas pelo conteúdo', () => {
    expect(mesmoValor(['a', 'b'], ['a', 'b'])).toBe(true);
    expect(mesmoValor(['a'], ['a', 'b'])).toBe(false);
  });

  it('valor solto: sem base vale o remoto; mexido fica o local', () => {
    expect(manterSeMexeu<number>(undefined, 5, 10, false)).toBe(10);
    expect(manterSeMexeu<number>(0, 5, 10, true)).toBe(5);
    expect(manterSeMexeu<number>(0, 0, 10, true)).toBe(10);
  });
});
