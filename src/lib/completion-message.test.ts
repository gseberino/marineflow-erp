// A mensagem de conclusão só avisa que o serviço terminou (dono, 26/11/2026: "2. A"): o saldo e o Pix iam a um número
// digitável, sem as travas da cobrança; cobrar é pelo "Cobrar o cliente", com a conferência da ficha.
import { describe, it, expect } from 'vitest';
import { buildCompletionMessage } from './completion-message';

describe('buildCompletionMessage', () => {
  it('avisa a conclusão da OS com o primeiro nome', () => {
    const msg = buildCompletionMessage({ clientName: 'Charline Souza', osNumber: 'OS-00060' });
    expect(msg).toBe('Olá Charline!\n\nConcluímos o serviço da OS-00060.\n\nObrigado pela confiança — qualquer coisa, é só chamar!');
  });

  it('nunca leva valor, saldo, vencimento, Pix nem "quitado"', () => {
    const msg = buildCompletionMessage({ clientName: 'Ana', osNumber: 'OS-1', assetType: 'Motorhome' });
    expect(msg).not.toMatch(/R\$|saldo|venc|pix|quitad|pagamento/i);
  });

  it('sem nome: usa "Cliente"', () => {
    expect(buildCompletionMessage({ osNumber: 'OS-1' }).startsWith('Olá Cliente!\n\n')).toBe(true);
  });
});

describe('emoji pelo tipo da unidade (22/10/2026: motorhome recebia 🚤)', () => {
  it('veículo 🚐, barco 🛥️, equipamento ou sem tipo: nenhum', () => {
    const motorhome = buildCompletionMessage({ clientName: 'Rodrigo', osNumber: 'OS-00100', assetType: 'Motorhome' });
    expect(motorhome.startsWith('Olá Rodrigo! 🚐\n\n')).toBe(true);
    expect(motorhome).not.toContain('🚤');
    expect(buildCompletionMessage({ clientName: 'Ana', osNumber: 'OS-1', assetType: 'Lancha' }).startsWith('Olá Ana! 🛥️\n\n')).toBe(true);
    expect(buildCompletionMessage({ clientName: 'Ana', osNumber: 'OS-1', assetType: 'Equipamento' }).startsWith('Olá Ana!\n\n')).toBe(true);
    expect(buildCompletionMessage({ clientName: 'Ana', osNumber: 'OS-1' }).startsWith('Olá Ana!\n\n')).toBe(true);
  });
});
