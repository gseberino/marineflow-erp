// Configurações › Orçamentos depois que o vencimento virou AVISO (R19, 26/09/2026).
//
// Até ali a tela prometia "Dias para expiração automática — orçamentos sem resposta são
// marcados como Reprovados", e a rotina quote-reminders fazia isso em silêncio. A rotina
// não lê mais quote_expiry_days; uma tela que continuasse oferecendo o campo seria o dono
// configurando um número que não faz nada. O teste segura três coisas: o texto não promete
// mais rejeição, o campo está desabilitado, e salvar não reescreve a chave (fica como estava).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QuoteSettingsSection } from './QuoteSettingsSection';

const estado = vi.hoisted(() => ({
  ajustes: {} as Record<string, string>,
  gravados: [] as Array<Record<string, string>>,
}));

vi.mock('@/hooks/use-app-settings', () => ({
  useAppSettings: () => ({ data: estado.ajustes, isLoading: false }),
  useUpdateAppSettings: () => ({
    mutateAsync: async (entradas: Record<string, string>) => { estado.gravados.push(entradas); },
    isPending: false,
  }),
}));
vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));

beforeEach(() => {
  estado.ajustes = { quote_validity_days: '3', quote_expiry_days: '7', quote_followup_days: '5' };
  estado.gravados.length = 0;
});

describe('Configurações › Orçamentos — vencimento é aviso', () => {
  it('não promete mais rejeição automática; explica o aviso', () => {
    render(<QuoteSettingsSection />);
    expect(screen.queryByText(/marcados como Reprovados/i)).toBeNull();
    expect(screen.getByText(/Orçamento vencido: renovar ou rejeitar\?/)).toBeTruthy();
    expect(screen.getByText(/Nenhum orçamento é rejeitado sozinho/)).toBeTruthy();
  });

  it('a validade padrão diz que também decide quando o aviso aparece', () => {
    render(<QuoteSettingsSection />);
    expect(screen.getByText(/Quando o orçamento não tem validade\s+própria, é ela também que define quando aparece o aviso/)).toBeTruthy();
    expect((screen.getByLabelText(/Validade padrão do orçamento/) as HTMLInputElement).value).toBe('3');
  });

  it('o campo de expiração está desabilitado e mostra o número guardado', () => {
    render(<QuoteSettingsSection />);
    const campo = screen.getByLabelText(/Dias para expiração automática/) as HTMLInputElement;
    expect(campo.disabled).toBe(true);
    expect(campo.value).toBe('7');
  });

  it('salvar não reescreve quote_expiry_days (nem apaga): o banco fica como estava', async () => {
    render(<QuoteSettingsSection />);
    await userEvent.click(screen.getByRole('button', { name: /Salvar configurações de orçamento/ }));
    expect(estado.gravados).toHaveLength(1);
    expect(estado.gravados[0]).not.toHaveProperty('quote_expiry_days');
    // o resto continua sendo salvo
    expect(estado.gravados[0].quote_validity_days).toBe('3');
    expect(estado.gravados[0].quote_followup_days).toBe('5');
  });

  it('sem a chave no banco, o campo fica vazio e nada é criado ao salvar', async () => {
    estado.ajustes = { quote_validity_days: '3' };
    render(<QuoteSettingsSection />);
    expect((screen.getByLabelText(/Dias para expiração automática/) as HTMLInputElement).value).toBe('');
    await userEvent.click(screen.getByRole('button', { name: /Salvar configurações de orçamento/ }));
    expect(estado.gravados[0]).not.toHaveProperty('quote_expiry_days');
  });
});
