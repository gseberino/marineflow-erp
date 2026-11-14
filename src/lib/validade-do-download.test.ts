import { describe, it, expect, vi, beforeEach } from 'vitest';

const rpc = vi.fn();
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: (...a: unknown[]) => rpc(...a) } }));

import { validadeDoDownload, comValidadeDoDownload } from './validade-do-download';
import type { PDFOptions } from '@/lib/pdf-generator';

const BASE = { validity: { mode: 'days', days: 3 } } as PDFOptions;

describe('validade do download (F5, dúvida 5)', () => {
  beforeEach(() => rpc.mockReset());

  it('orçamento não enviado: grava e o PDF leva a data fixada', async () => {
    rpc.mockResolvedValue({ data: { ok: true, fixou: true, data: '2026-11-20', dias: 7 }, error: null });
    const o = await comValidadeDoDownload('os-1', 'quote', BASE);
    expect(rpc).toHaveBeenCalledWith('orcamento_validade_do_envio', { p_os: 'os-1', p_gravar: true });
    expect(o.validity).toEqual({ mode: 'date', date: '2026-11-20' });
  });

  it('já enviado: a data do 1º envio', async () => {
    rpc.mockResolvedValue({ data: { ok: true, fixou: false, motivo: 'ja_enviado', data: '2026-11-18' }, error: null });
    expect(await validadeDoDownload('os-1')).toBe('2026-11-18');
  });

  it.each(['desligada', 'vencida', 'funil', 'cargo', 'mudou'])('motivo %s: o PDF de antes', async (motivo) => {
    rpc.mockResolvedValue({ data: { ok: true, fixou: false, motivo, data: '2026-11-18' }, error: null });
    expect(await comValidadeDoDownload('os-1', 'quote', BASE)).toBe(BASE);
  });

  it('erro, ok falso ou exceção: o PDF de antes', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'x' } });
    expect(await validadeDoDownload('os-1')).toBeNull();
    rpc.mockResolvedValueOnce({ data: { ok: false, motivo: 'erro' }, error: null });
    expect(await validadeDoDownload('os-1')).toBeNull();
    rpc.mockRejectedValueOnce(new Error('rede'));
    expect(await validadeDoDownload('os-1')).toBeNull();
  });

  it('OS (não orçamento) e sem id: não chama o banco', async () => {
    expect(await comValidadeDoDownload('os-1', 'service_order', BASE)).toBe(BASE);
    expect(await comValidadeDoDownload(null, 'quote', BASE)).toBe(BASE);
    expect(rpc).not.toHaveBeenCalled();
  });
});
