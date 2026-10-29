// Aprovação em lote, Fase 1 (29/10/2026): o cartão mostra o que aconteceu de verdade. Antes ele dizia "✅ Ação executada
// com sucesso" sempre que a chamada HTTP dava certo — e a ação que falhava voltava 200 com "falhou".
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AIConfirmCard } from './AIConfirmCard';
import { statusDoCartao, type Proposal } from '@/hooks/use-ai-agent';

vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));

const CARTAO: Proposal = {
  pending_action_id: 'p1',
  title: 'Cadastrar serviço',
  summary_markdown: '- Nome: Realocação do banco de baterias\n- Cobrança: por unidade\n- Preço: R$ 1.135,00',
  risk_level: 'medium',
};

describe('statusDoCartao: o status vem do servidor, não do HTTP', () => {
  it('executada, falhou, rejeitada e já decidida em outro lugar', () => {
    expect(statusDoCartao({ ok: true, resultado: 'executed' })).toBe('executed');
    expect(statusDoCartao({ ok: true, resultado: 'failed' })).toBe('failed');
    expect(statusDoCartao({ ok: true, resultado: 'rejected' })).toBe('cancelled');
    expect(statusDoCartao({ ok: false, resultado: 'expired' })).toBe('decidida');
    expect(statusDoCartao({ ok: false, resultado: 'executed' })).toBe('executed');
  });
  it('servidor antigo (sem resultado) segue como antes; erro sem resposta volta a esperar', () => {
    expect(statusDoCartao({ ok: true })).toBe('executed');
    expect(statusDoCartao({ ok: false })).toBe('pending');
  });
});

describe('AIConfirmCard', () => {
  const nada = () => {};
  it('ação que falhou não diz "executada com sucesso"', () => {
    render(<AIConfirmCard proposal={CARTAO} status="failed" onConfirm={nada} onCancel={nada} />);
    expect(screen.getByText(/Não foi feito: a ação falhou/)).toBeTruthy();
    expect(screen.queryByText(/executada com sucesso/)).toBeNull();
    expect(screen.queryByRole('button', { name: /Confirmar/ })).toBeNull();
  });
  it('já decidida em outro lugar: avisa e não oferece os botões', () => {
    render(<AIConfirmCard proposal={CARTAO} status="decidida" onConfirm={nada} onCancel={nada} />);
    expect(screen.getByText(/já tinha sido decidido/)).toBeTruthy();
    expect(screen.queryByRole('button', { name: /Confirmar/ })).toBeNull();
  });
  it('o cartão real de 28/10 sai em português', () => {
    render(<AIConfirmCard proposal={CARTAO} status="pending" onConfirm={nada} onCancel={nada} />);
    expect(screen.getByText('Cadastrar serviço')).toBeTruthy();
    expect(screen.getByText(/Cobrança: por unidade/)).toBeTruthy();
    expect(screen.getByRole('button', { name: /Confirmar/ })).toBeTruthy();
  });
});
