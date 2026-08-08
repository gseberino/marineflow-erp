import { describe, it, expect } from 'vitest';
import { decideAutosave, type AutosaveState } from './autosave-guard';

/**
 * O autosave escreve num registro com valores financeiros, e cada gravação
 * dispara o recálculo de totais da ordem. Errar para o lado de gravar demais
 * persiste número errado numa proposta que vai ao cliente; errar para o lado
 * de gravar de menos custa um clique em Salvar. Estes testes travam o lado
 * seguro.
 */
const completa: AutosaveState = {
  isNew: false,
  isLocked: false,
  orderId: 'os-1',
  clientId: 'c-1',
  vesselId: 'v-1',
  problemDescription: 'Trocar baterias',
  assinaturaAtual: '{"a":1}',
  assinaturaSalva: '{"a":0}',
};

describe('quando o autosave age', () => {
  it('ordem existente, completa e com mudança: salva', () => {
    expect(decideAutosave(completa)).toEqual({ salvar: true });
  });
});

describe('quando o autosave se cala', () => {
  it('ordem nova não nasce sozinha', () => {
    expect(decideAutosave({ ...completa, isNew: true }))
      .toEqual({ salvar: false, motivo: 'nova' });
    // Sem id também é ordem que ainda não existe.
    expect(decideAutosave({ ...completa, orderId: null }))
      .toEqual({ salvar: false, motivo: 'nova' });
  });

  it('faturada ou cancelada não recebe escrita', () => {
    expect(decideAutosave({ ...completa, isLocked: true }))
      .toEqual({ salvar: false, motivo: 'travada' });
  });

  // Aqui está o ponto: sem estes obrigatórios o salvamento manual RECUSA com
  // um aviso na tela. Um aviso a cada campo, enquanto a pessoa monta o
  // orçamento, faria qualquer um querer desligar o autosave.
  it.each([
    ['sem cliente', { clientId: null }],
    ['sem embarcação', { vesselId: null }],
    ['sem descrição', { problemDescription: '' }],
  ])('%s: não tenta gravar', (_nome, patch) => {
    expect(decideAutosave({ ...completa, ...patch } as AutosaveState))
      .toEqual({ salvar: false, motivo: 'incompleta' });
  });

  // Abrir a tela não pode gravar. Nem o servidor devolver os mesmos dados.
  it('sem mudança real não escreve', () => {
    expect(decideAutosave({ ...completa, assinaturaSalva: completa.assinaturaAtual }))
      .toEqual({ salvar: false, motivo: 'sem-mudanca' });
  });

  it('a primeira mudança depois de abrir salva (nada gravado ainda)', () => {
    expect(decideAutosave({ ...completa, assinaturaSalva: null }))
      .toEqual({ salvar: true });
  });

  // A ordem das recusas importa: ordem nova E incompleta é "nova", porque é
  // essa a razão que o usuário precisaria entender se fosse perguntar.
  it('ordem nova ganha da incompleta na explicação', () => {
    expect(decideAutosave({ ...completa, isNew: true, clientId: null }))
      .toEqual({ salvar: false, motivo: 'nova' });
  });
});
