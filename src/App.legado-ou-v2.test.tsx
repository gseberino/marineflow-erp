// O atalho sem prefixo (/fiscal/emissao…) cai na tela v2 pelo LegadoOuV2. Quem navega com
// `state` (a devolução ao fornecedor do Importar XML, o "Faturar" da OS com a NF-e campo a campo)
// precisa que o state atravesse o redirecionamento — senão a tela de destino abre vazia.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import { LegadoOuV2 } from '@/App';

vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: () => ({ insert: async () => ({}) }) } }));

function Destino() {
  const location = useLocation();
  return (
    <>
      <p>caminho: {location.pathname}{location.search}</p>
      <p>state: {JSON.stringify(location.state)}</p>
    </>
  );
}

function abrir(entrada: { pathname: string; search?: string; state?: unknown }) {
  render(
    <MemoryRouter initialEntries={[entrada]}>
      <Routes>
        <Route path="/fiscal/emissao" element={<LegadoOuV2 to="/v2/fiscal/emissao" legacy={<p>tela antiga</p>} />} />
        <Route path="/v2/fiscal/emissao" element={<Destino />} />
        <Route path="/purchasing/quotes/:id" element={<LegadoOuV2 to="/v2/purchasing/quotes/:id" legacy={<p>tela antiga</p>} />} />
        <Route path="/v2/purchasing/quotes/:id" element={<Destino />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('LegadoOuV2', () => {
  it('leva o state junto para a tela v2 (devolução ao fornecedor, faturar a OS)', () => {
    abrir({ pathname: '/fiscal/emissao', state: { returnToSupplier: { chave: '3526' } } });
    expect(screen.getByText('caminho: /v2/fiscal/emissao')).toBeInTheDocument();
    expect(screen.getByText('state: {"returnToSupplier":{"chave":"3526"}}')).toBeInTheDocument();
  });

  it('continua levando :params e a query; sem state, nada inventado', () => {
    abrir({ pathname: '/purchasing/quotes/abc', search: '?aba=itens' });
    expect(screen.getByText('caminho: /v2/purchasing/quotes/abc?aba=itens')).toBeInTheDocument();
    expect(screen.getByText('state: null')).toBeInTheDocument();
  });

  it('?legacy=1 abre a tela antiga', () => {
    abrir({ pathname: '/fiscal/emissao', search: '?legacy=1' });
    expect(screen.getByText('tela antiga')).toBeInTheDocument();
  });
});
