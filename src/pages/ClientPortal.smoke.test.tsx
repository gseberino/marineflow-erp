// O portal do cliente foi aposentado em 29/09/2026. Antes, o "login" era digitar 5 dígitos
// de qualquer telefone ou um CPF, e a resposta trazia as OS do cliente com o link público
// (que abre o cadastro completo). O que se protege aqui: a página não pede nenhum dado e
// não chama nenhuma função — quem guardou o endereço só lê o aviso.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

const chamou = vi.hoisted(() => ({ invoke: 0, from: 0 }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    functions: { invoke: () => { chamou.invoke++; return Promise.resolve({ data: null, error: null }); } },
    from: () => { chamou.from++; throw new Error('o portal não pode ler o banco'); },
  },
}));

import ClientPortal from './ClientPortal';

describe('portal do cliente aposentado', () => {
  it('mostra o aviso, sem campo para digitar documento ou telefone', () => {
    render(<ClientPortal />);
    expect(screen.getByText('Esta página não está mais disponível.')).toBeInTheDocument();
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
    expect(chamou).toEqual({ invoke: 0, from: 0 });
  });

  it('a função client-portal não existe mais (apagada do servidor em 03/10 e do repo em 06/10/2026)', () => {
    expect(existsSync(resolve(__dirname, '../../supabase/functions/client-portal'))).toBe(false);
  });
});
