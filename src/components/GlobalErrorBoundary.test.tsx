// A barreira de erro tem dois deveres que ninguém via falhar.
//
// 1. Ela prometia na tela que "nossos sistemas registraram o problema" e não registrava:
//    `logError` estava importado e nunca chamado. A tela branca — justamente o erro que o
//    usuário não consegue descrever depois — não deixava rastro em app_error_logs.
// 2. Quando o sistema é publicado com a aba aberta, o arquivo da tela carregada sob
//    demanda some, e a barreira anunciava "Ops! Algo deu errado" com um stack trace. O
//    usuário vai procurar um defeito que não existe: basta recarregar.
import { describe, it, expect, vi, beforeEach, afterAll } from 'vitest';
import { render, screen } from '@testing-library/react';
import { GlobalErrorBoundary } from './GlobalErrorBoundary';

vi.mock('@/lib/diagnostics', () => ({ logError: vi.fn(() => Promise.resolve()) }));
import { logError } from '@/lib/diagnostics';

/** Componente que estoura na renderização, como uma tela que não carregou. */
function Explode({ erro }: { erro: Error }): JSX.Element {
  throw erro;
}

// React imprime o erro capturado no console; aqui ele é esperado, não sintoma.
const consoleErro = vi.spyOn(console, 'error').mockImplementation(() => {});
afterAll(() => consoleErro.mockRestore());

describe('GlobalErrorBoundary', () => {
  beforeEach(() => vi.mocked(logError).mockClear());

  it('grava o erro em app_error_logs — o que a tela promete', () => {
    render(
      <GlobalErrorBoundary>
        <Explode erro={new Error('boom na renderização')} />
      </GlobalErrorBoundary>,
    );
    expect(logError).toHaveBeenCalledTimes(1);
    const chamada = vi.mocked(logError).mock.calls[0][0];
    expect(chamada.message).toContain('boom na renderização');
    expect(chamada.action).toBe('error_boundary');
  });

  it('erro comum: mostra a tela de falha com o detalhe técnico', () => {
    render(
      <GlobalErrorBoundary>
        <Explode erro={new Error('coluna inexistente na consulta')} />
      </GlobalErrorBoundary>,
    );
    expect(screen.getByText(/Algo deu errado/i)).toBeInTheDocument();
    expect(screen.getByText(/coluna inexistente na consulta/)).toBeInTheDocument();
  });

  it('arquivo que sumiu na publicação: diz que o sistema foi atualizado, não que quebrou', () => {
    render(
      <GlobalErrorBoundary>
        <Explode erro={new TypeError(
          'Failed to fetch dynamically imported module: https://marineflow-erp.vercel.app/assets/Dashboard-x1y2.js',
        )} />
      </GlobalErrorBoundary>,
    );
    expect(screen.getByText('O sistema foi atualizado')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Recarregar agora/i })).toBeInTheDocument();
    // Nem a palavra de susto nem a URL do arquivo aparecem para o usuário.
    expect(screen.queryByText(/Algo deu errado/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/assets\/Dashboard/)).not.toBeInTheDocument();
  });

  it('mesmo nesse caso o erro é registrado — é assim que se sabe que aconteceu', () => {
    render(
      <GlobalErrorBoundary>
        <Explode erro={new TypeError('Failed to fetch dynamically imported module: /assets/x.js')} />
      </GlobalErrorBoundary>,
    );
    expect(logError).toHaveBeenCalledTimes(1);
  });
});
