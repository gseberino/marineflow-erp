import { render, screen } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';
import { MasterDataPanel } from './MasterDataManagement';

vi.mock('@/i18n', () => ({
  useI18n: () => ({
    t: {},
  }),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {},
}));

describe('MasterDataPanel', () => {
  test('keeps export available and blocks critical import from the UI', () => {
    render(<MasterDataPanel />);

    expect(screen.getByRole('button', { name: /Exportar Dados/i })).toBeEnabled();

    const importButton = screen.getByRole('button', { name: /Importar Dados/i });
    expect(importButton).toBeDisabled();

    expect(screen.getByText(/scripts\/migration/i)).toBeInTheDocument();
    expect(screen.getByText(/foi bloqueada/i)).toBeInTheDocument();
  });
});
