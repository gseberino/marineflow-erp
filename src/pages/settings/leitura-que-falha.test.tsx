// Configurações: leitura que falha NÃO abre o formulário com padrão/vazio editável (19/11/2026).
// Antes, "Salvar" depois de uma leitura falha gravava os padrões (ou campos vazios) por cima do
// que estava no banco — e os modelos de checklist eram apagados ao adicionar um novo.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

vi.mock('@/integrations/supabase/client', async () => ({ supabase: (await import('@/test/banco-falso')).supabaseFalso }));
const toast = vi.hoisted(() => ({ success: vi.fn(), error: vi.fn(), info: vi.fn() }));
vi.mock('sonner', () => ({ toast }));

import { I18nProvider } from '@/i18n';
import { FiscalTab } from './FiscalTab';
import { CompanyTab } from './CompanyTab';
import { TaskAutomationSettings } from '@/components/agenda/TaskAutomationSettings';
import { banco, ok, falha, reiniciarBanco, chamadasA } from '@/test/banco-falso';

function montar(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}><I18nProvider><MemoryRouter>{ui}</MemoryRouter></I18nProvider></QueryClientProvider>,
  );
}

beforeEach(() => {
  reiniciarBanco();
  toast.success.mockReset();
  toast.error.mockReset();
});

describe('FiscalTab', () => {
  it('leitura falha: mostra o erro e não há formulário nem "Salvar"', async () => {
    banco.respostas['app_settings.select'] = falha('timeout');
    montar(<FiscalTab />);
    expect(await screen.findByText(/Não consegui carregar as configurações fiscais/)).toBeInTheDocument();
    expect(screen.queryByText('Simples Nacional')).toBeNull();
    expect(screen.queryByRole('button', { name: /salvar/i })).toBeNull();
  });

  it('"Tentar de novo" relê e abre o formulário com o que está gravado', async () => {
    banco.respostas['app_settings.select'] = [falha('timeout'), ok([{ key: 'simples_aliquota', value: '8.5' }])];
    montar(<FiscalTab />);
    fireEvent.click(await screen.findByRole('button', { name: 'Tentar de novo' }));
    expect(await screen.findByDisplayValue('8.5')).toBeInTheDocument();
  });

  it('gravação que falha não diz "salvas com sucesso"', async () => {
    banco.respostas['app_settings.select'] = ok([]);
    banco.respostas['app_settings.upsert'] = falha('rls');
    montar(<FiscalTab />);
    fireEvent.click(await screen.findByRole('button', { name: /salvar/i }));
    await waitFor(() => expect(toast.error).toHaveBeenCalled());
    expect(toast.success).not.toHaveBeenCalled();
  });
});

describe('CompanyTab', () => {
  it('leitura falha: mostra o erro e não há formulário nem "Salvar"', async () => {
    banco.respostas['app_settings.select'] = falha('timeout');
    montar(<CompanyTab />);
    expect(await screen.findByText(/Não consegui carregar os dados da empresa/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /salvar/i })).toBeNull();
    expect(chamadasA('app_settings.upsert')).toHaveLength(0);
  });
});

describe('Modelos de checklist (Configurações › Automações)', () => {
  it('leitura falha: avisa e bloqueia "Adicionar" (não apaga os outros modelos)', async () => {
    banco.respostas['app_settings.maybeSingle'] = falha('timeout');
    banco.respostas['app_settings.select'] = falha('timeout');
    montar(<TaskAutomationSettings />);
    expect(await screen.findByText(/Não consegui carregar os modelos de checklist/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Adicionar' })).toBeDisabled();
    expect(screen.getByLabelText('Novo modelo de checklist')).toBeDisabled();
    expect(chamadasA('app_settings.upsert')).toHaveLength(0);
  });

  it('automações ilegíveis: avisa e trava os interruptores das regras', async () => {
    banco.respostas['app_settings.select'] = falha('timeout');
    montar(<TaskAutomationSettings />);
    expect(await screen.findByText(/Não consegui carregar as automações de tarefas/)).toBeInTheDocument();
    expect(screen.getByRole('switch', { name: 'OS parada' })).toBeDisabled();
  });
});
