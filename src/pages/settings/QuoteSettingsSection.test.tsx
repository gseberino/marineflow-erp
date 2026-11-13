// Configurações › Orçamentos depois que o vencimento virou AVISO (R19, 26/09/2026).
//
// Até ali a tela prometia "Dias para expiração automática — orçamentos sem resposta são
// marcados como Reprovados", e a rotina quote-reminders fazia isso em silêncio. A rotina
// não lê mais quote_expiry_days; uma tela que continuasse oferecendo o campo seria o dono
// configurando um número que não faz nada. O teste segura três coisas: o texto não promete
// mais rejeição, o campo está desabilitado, e salvar não reescreve a chave (fica como estava).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
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
    // o resto continua sendo salvo (Retorno F5, P12.4: o quote_followup_days saiu da tela, como o quote_expiry_days)
    expect(estado.gravados[0].quote_validity_days).toBe('3');
    expect(estado.gravados[0]).not.toHaveProperty('quote_followup_days');
  });

  it('sem a chave no banco, o campo fica vazio e nada é criado ao salvar', async () => {
    estado.ajustes = { quote_validity_days: '3' };
    render(<QuoteSettingsSection />);
    expect((screen.getByLabelText(/Dias para expiração automática/) as HTMLInputElement).value).toBe('');
    await userEvent.click(screen.getByRole('button', { name: /Salvar configurações de orçamento/ }));
    expect(estado.gravados[0]).not.toHaveProperty('quote_expiry_days');
  });
});

// A validade padrão era gravada como Number(digitado), sem filtro: -1, 0 e 2.5 iam para
// app_settings. Agora só um inteiro de 1 a 3650 é gravado — a faixa que o PDF, a R19 e o
// assistente aceitam (validadeGravavel).
describe('Configurações › Orçamentos — validade padrão só grava inteiro de 1 a 3650', () => {
  const campo = () => screen.getByLabelText(/Validade padrão do orçamento/) as HTMLInputElement;
  const salvar = () => screen.getByRole('button', { name: /Salvar configurações de orçamento/ });

  it('o campo pede inteiro de 1 a 3650 (min, max, step)', () => {
    render(<QuoteSettingsSection />);
    expect(campo().min).toBe('1');
    expect(campo().max).toBe('3650');
    expect(campo().step).toBe('1');
  });

  it.each(['-1', '0', '2.5', '3651', '1e9', ''])('com %j no campo, nada é gravado e a tela diz por quê', async (digitado) => {
    render(<QuoteSettingsSection />);
    fireEvent.change(campo(), { target: { value: digitado } });
    expect(screen.getByRole('alert').textContent).toMatch(/inteiro de 1 a 3650 dias/);
    expect(campo().getAttribute('aria-invalid')).toBe('true');
    expect((salvar() as HTMLButtonElement).disabled).toBe(true);
    await userEvent.click(salvar());
    expect(estado.gravados).toHaveLength(0);
  });

  it('um inteiro válido é gravado como texto do inteiro', async () => {
    render(<QuoteSettingsSection />);
    fireEvent.change(campo(), { target: { value: '30' } });
    expect(screen.queryByRole('alert')).toBeNull();
    await userEvent.click(salvar());
    expect(estado.gravados).toHaveLength(1);
    expect(estado.gravados[0].quote_validity_days).toBe('30');
  });

  it('um valor gravado inválido (-1) abre como o que o PDF usa (15), não como -1', () => {
    estado.ajustes = { quote_validity_days: '-1' };
    render(<QuoteSettingsSection />);
    expect(campo().value).toBe('15');
  });
});

// Retorno F5 (P12.4): o "Dias para lembrete de follow-up" prometia um WhatsApp automático que nunca existiu (o número era
// gravado e lido por ninguém). A cadência do orçamento enviado é a do K7 e é ligada pelo retorno: o campo some, o texto só
// de leitura explica, e salvar não escreve a chave (o valor fica no banco como está, como o quote_expiry_days).
describe('Configurações › Orçamentos — o follow-up saiu da tela (F5)', () => {
  it('o campo some, e não há mais promessa de WhatsApp automático', () => {
    render(<QuoteSettingsSection />);
    expect(screen.queryByText(/Dias para lembrete de follow-up/)).toBeNull();
    expect(screen.queryByText(/WhatsApp de follow-up automático/)).toBeNull();
    expect(screen.getByText(/Acompanhamento do orçamento enviado: lembrete em 2 dias úteis, outro na véspera do vencimento e encerramento 1 dia útil depois\. É ligado pelo retorno, não por esta tela\./)).toBeTruthy();
  });

  it('salvar não escreve quote_followup_days nem quote_expiry_days: o banco fica como estava', async () => {
    render(<QuoteSettingsSection />);
    await userEvent.click(screen.getByRole('button', { name: /Salvar configurações de orçamento/ }));
    expect(estado.gravados).toHaveLength(1);
    expect(estado.gravados[0]).not.toHaveProperty('quote_followup_days');
    expect(estado.gravados[0]).not.toHaveProperty('quote_expiry_days');
  });

  it('a ajuda da validade diz que, com a validade do envio ligada, o enviado vale 7 dias contados do envio', () => {
    render(<QuoteSettingsSection />);
    expect(screen.getByText(/Com a validade do envio ligada, o orçamento enviado vale 7 dias contados do envio; este número vale só para o rascunho\./)).toBeTruthy();
  });
});
