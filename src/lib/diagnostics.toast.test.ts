// O interceptador de toast.error faz duas coisas ao mesmo tempo, e elas puxam para
// lados opostos: mostra a frase amigável na TELA e guarda o texto original no LOG.
//
// Testar só o tradutor não provaria nada disto — provaria que a função traduz. O que
// pode quebrar é a ligação: mandar a tradução para o log (e perder a evidência de
// diagnóstico), ou mandar o original para a tela (e manter o problema que começou tudo,
// o "duplicate key value violates unique constraint" que o dono viu cinco vezes).
import { describe, it, expect, vi, beforeEach } from 'vitest';

const rpc = vi.fn((..._a: unknown[]) => Promise.resolve({ data: null, error: null }));
vi.mock("@/integrations/supabase/client", () => ({ supabase: { rpc: (...a: unknown[]) => rpc(...a) } }));
vi.mock('@/lib/query-client', () => ({ queryClient: { getQueryCache: () => ({ getAll: () => [] }) } }));

const erroOriginal = vi.fn();
vi.mock('sonner', () => ({ toast: { error: (...a: unknown[]) => erroOriginal(...a), warning: vi.fn() } }));

import { installDiagnostics } from './diagnostics';
import { toast } from 'sonner';

/** O que o RPC de log recebeu como mensagem, na última chamada. */
function mensagemLogada(): string | undefined {
  const ultima = rpc.mock.calls.at(-1) as unknown as [string, { p_message?: string }] | undefined;
  return ultima?.[1]?.p_message;
}

describe('toast.error interceptado', () => {
  beforeEach(() => {
    rpc.mockClear();
    erroOriginal.mockClear();
    installDiagnostics(); // idempotente: instala uma vez só
  });

  it('erro de banco: tela em português, log com o texto original', async () => {
    const cru = 'duplicate key value violates unique constraint "products_sku_key"';
    toast.error(cru);
    await Promise.resolve();

    expect(erroOriginal).toHaveBeenCalledWith('Já existe um(a) produto com este SKU.', undefined);
    expect(mensagemLogada()).toBe(cru);
  });

  it('mensagem já em português passa intacta para os dois lados', async () => {
    const msg = 'Preencha cliente, embarcação e descrição do problema';
    toast.error(msg);
    await Promise.resolve();

    expect(erroOriginal).toHaveBeenCalledWith(msg, undefined);
    expect(mensagemLogada()).toBe(msg);
  });

  it('as opções do toast (ação, duração) continuam chegando', () => {
    const opcoes = { duration: 8000 };
    toast.error('Estoque insuficiente. Disponível: 0', opcoes);
    expect(erroOriginal).toHaveBeenCalledWith('Estoque insuficiente. Disponível: 0', opcoes);
  });
});
