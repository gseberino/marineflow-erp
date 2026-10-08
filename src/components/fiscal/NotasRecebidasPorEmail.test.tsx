// "Notas recebidas por e-mail" (08/10/2026): mostra só NF-e destinada à HBR e ainda não importada;
// "Conferir e importar" devolve o anexo para a MESMA conferência do arquivo.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

const dados = vi.hoisted(() => ({
  mensagens: [
    { received_at: '2026-10-07T13:00:00Z', email_accounts: { address: 'financeiro@hbrmarine.com.br' }, dados_extraidos: { nfes: [
      { anexo_id: 'a1', chave: 'C1', emitente: 'Coremma', numero: '812', valor: 1234.56, data: '2026-10-07', para_empresa: true },
      { anexo_id: 'a2', chave: 'C2', emitente: 'Outra', numero: '9', valor: 10, data: '2026-10-07', para_empresa: false },
    ] } },
    { received_at: '2026-10-06T13:00:00Z', email_accounts: { address: 'gustavo@hbrmarine.com.br' }, dados_extraidos: { nfes: [
      { anexo_id: 'a3', chave: 'C3', emitente: 'Marine Express', numero: '55', valor: 500, data: '2026-10-05', para_empresa: true },
    ], boletos: [] } },
  ],
  importadas: [{ nfe_key: 'C3' }],
}));

vi.mock('@/integrations/supabase/client', () => {
  const q = (resultado: () => unknown) => {
    const o: any = {};
    for (const m of ['select', 'not', 'gte', 'order', 'limit', 'in']) o[m] = () => o;
    o.then = (ok: any) => Promise.resolve({ data: resultado(), error: null }).then(ok);
    return o;
  };
  return { supabase: { from: (t: string) => q(() => (t === 'email_messages' ? dados.mensagens : dados.importadas)) } };
});

import { NotasRecebidasPorEmail } from './NotasRecebidasPorEmail';

describe('NotasRecebidasPorEmail', () => {
  it('lista só a destinada à HBR e não importada; o botão devolve o anexo', async () => {
    const onConferir = vi.fn();
    render(
      <QueryClientProvider client={new QueryClient()}>
        <I18nProvider>
          <NotasRecebidasPorEmail ocupado={false} onConferir={onConferir} />
        </I18nProvider>
      </QueryClientProvider>,
    );
    await waitFor(() => expect(screen.getByTestId('notas-por-email')).toBeTruthy());
    expect(screen.getByText(/Coremma · NF-e 812/)).toBeTruthy();
    expect(screen.queryByText(/Outra/)).toBeNull(); // de outro destinatário
    expect(screen.queryByText(/Marine Express/)).toBeNull(); // já importada
    fireEvent.click(screen.getByRole('button', { name: /Conferir e importar/ }));
    expect(onConferir).toHaveBeenCalledWith('a1');
  });
});
