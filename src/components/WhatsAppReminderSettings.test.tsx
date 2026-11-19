// Lembretes de mensagens não respondidas: a tela não promete o que não roda (19/11/2026).
//  - não existe agendamento do whatsapp-unread-reminder: nada de "verifica a cada 15 minutos";
//  - sem a chave gravada, o interruptor aparece DESLIGADO, como o webhook trata;
//  - leitura que falha mostra o erro (sem interruptor para gravar por cima).
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';

vi.mock('@/integrations/supabase/client', async () => ({ supabase: (await import('@/test/banco-falso')).supabaseFalso }));
vi.mock('@/hooks/use-app-users', () => ({ useAppUsers: () => ({ data: [] }) }));
vi.mock('@/hooks/use-toast', () => ({ toast: vi.fn() }));

import { WhatsAppReminderSettings } from './WhatsAppReminderSettings';
import { banco, ok, falha, reiniciarBanco } from '@/test/banco-falso';

beforeEach(() => reiniciarBanco());

describe('WhatsAppReminderSettings', () => {
  it('sem a chave gravada: interruptor desligado e texto honesto sobre o agendamento', async () => {
    banco.respostas['app_settings.select'] = ok([]);
    render(<WhatsAppReminderSettings />);
    const sw = await screen.findByRole('switch', { name: /Ativar\/desativar lembretes/ });
    expect(sw.getAttribute('aria-checked')).toBe('false');
    expect(screen.getByText(/não está agendado/)).toBeInTheDocument();
    expect(screen.queryByText(/a cada 15 minutos/)).toBeNull();
    expect(screen.getByRole('button', { name: /Executar agora/ })).toBeInTheDocument();
  });

  it('chave = true: interruptor ligado', async () => {
    banco.respostas['app_settings.select'] = ok([{ key: 'whatsapp_reminder_enabled', value: 'true' }]);
    render(<WhatsAppReminderSettings />);
    const sw = await screen.findByRole('switch', { name: /Ativar\/desativar lembretes/ });
    expect(sw.getAttribute('aria-checked')).toBe('true');
  });

  it('leitura falha: mostra o erro e não o interruptor', async () => {
    banco.respostas['app_settings.select'] = falha('timeout');
    render(<WhatsAppReminderSettings />);
    expect(await screen.findByText(/Não consegui carregar os lembretes de mensagens/)).toBeInTheDocument();
    expect(screen.queryByRole('switch')).toBeNull();
  });
});
