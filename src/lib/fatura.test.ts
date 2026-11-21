// Fatura FAT-N (Fechar juntas F1, 20/11/2026): a regra que a tela mostra antes do clique é a mesma do
// banco (fatura_receber / _fatura_impedimento) — supabase/tests/fechar_juntas_fatura.sql prova a do banco.
import { describe, it, expect } from 'vitest';
import { NUMERO_DA_FATURA_NOVA, colocarNumeroDaFatura, osEntraNaFatura, previaDoRecebimento } from './fatura';

const brl = (v: number) => `R$ ${v.toFixed(2)}`;

describe('previaDoRecebimento', () => {
  it('Pix igual ao saldo quita; a menos é parcial', () => {
    expect(previaDoRecebimento(1670, 1670, 'pix', brl)).toEqual({ pode: true, mensagem: 'Quita a fatura.' });
    const p = previaDoRecebimento(1000, 1670, 'pix', brl);
    expect(p.pode).toBe(true);
    expect(p.mensagem).toContain('ficam faltando R$ 670.00');
  });

  it('Pix até R$ 10 a mais vira receita; entre 10 e 100 é do dono; acima de 100, avaliar', () => {
    expect(previaDoRecebimento(675, 670, 'pix', brl)).toMatchObject({ pode: true });
    expect(previaDoRecebimento(675, 670, 'pix', brl).mensagem).toContain('R$ 5.00 a mais viram receita');
    expect(previaDoRecebimento(680, 670, 'pix', brl).pode).toBe(true); // R$ 10 exatos ainda é receita
    const dono = previaDoRecebimento(720, 670, 'pix', brl);
    expect(dono.pode).toBe(false);
    expect(dono.mensagem).toContain('decisão do dono');
    const avaliar = previaDoRecebimento(820, 670, 'pix', brl);
    expect(avaliar.pode).toBe(false);
    expect(avaliar.mensagem).toContain('Acima de R$ 100');
  });

  it('dinheiro a mais é troco (recusa); dinheiro a menos é parcial', () => {
    expect(previaDoRecebimento(671, 670, 'dinheiro', brl)).toMatchObject({ pode: false });
    expect(previaDoRecebimento(671, 670, 'dinheiro', brl).mensagem).toContain('troco');
    expect(previaDoRecebimento(300, 670, 'dinheiro', brl).pode).toBe(true);
  });

  it('valor zero ou fatura sem saldo: não recebe', () => {
    expect(previaDoRecebimento(0, 670, 'pix', brl).pode).toBe(false);
    expect(previaDoRecebimento(10, 0, 'dinheiro', brl).pode).toBe(false);
  });
});

describe('osEntraNaFatura', () => {
  it('só OS concluída ou faturada, com número de OS e não agrupada', () => {
    expect(osEntraNaFatura({ status: 'completed' }, 'OS-00076')).toBe(true);
    expect(osEntraNaFatura({ status: 'invoiced' }, 'OS-00045')).toBe(true);
    expect(osEntraNaFatura({ status: 'in_progress' }, 'OS-00010')).toBe(false);
    expect(osEntraNaFatura({ status: 'awaiting_client' }, 'OS-00119')).toBe(false);
    expect(osEntraNaFatura({ status: 'completed' }, 'ORÇ-00109')).toBe(false);
    expect(osEntraNaFatura({ status: 'completed', merged_into_id: 'x' }, 'OS-00001')).toBe(false);
    expect(osEntraNaFatura(null, 'OS-00001')).toBe(false);
  });
});

describe('colocarNumeroDaFatura', () => {
  it('troca o provisório pelo número; sem a linha, a mensagem fica como está', () => {
    expect(colocarNumeroDaFatura(`OS: OS-1\nFatura: ${NUMERO_DA_FATURA_NOVA}`, 'FAT-00001')).toBe('OS: OS-1\nFatura: FAT-00001');
    expect(colocarNumeroDaFatura('sem a linha', 'FAT-00001')).toBe('sem a linha');
  });
});
