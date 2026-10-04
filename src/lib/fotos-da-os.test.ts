// Fotos da OS em bucket privado (04/10/2026): a galeria do PDF e os links temporários da tela.
import { describe, it, expect, vi, beforeEach } from 'vitest';

const storage = vi.hoisted(() => ({
  pedidos: [] as Array<{ bucket: string; caminhos: string[]; validade: number }>,
  resposta: { data: [] as Array<{ path: string | null; signedUrl: string | null; error: string | null }>, error: null as null | { message: string } },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    storage: {
      from: (bucket: string) => ({
        createSignedUrls: async (caminhos: string[], validade: number) => {
          storage.pedidos.push({ bucket, caminhos, validade });
          return storage.resposta;
        },
      }),
    },
  },
}));

import { linksDasFotos, linksEmOrdem, VALIDADE_DO_LINK_DA_FOTO_S } from './fotos-da-os';
import { carregarPDFData } from '../../supabase/functions/_shared/pdf/dados';

/** Banco de mentira: toda consulta é encadeável e devolve o que a tabela mandar. */
function bancoFalso(ordem: Record<string, unknown>) {
  const selecoes: string[] = [];
  const consulta = (tabela: string) => {
    const resultado = tabela === 'service_orders'
      ? { data: ordem, error: null }
      : { data: [], error: null };
    const q: Record<string, unknown> = {};
    for (const m of ['eq', 'not', 'order', 'in']) q[m] = () => q;
    q.select = (s: string) => { selecoes.push(`${tabela}: ${s}`); return q; };
    q.single = async () => resultado;
    q.then = (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(resultado).then(ok, erro);
    return q;
  };
  return { db: { from: consulta }, selecoes };
}

const ordemComFotos = {
  id: 'os-1', service_order_number: 'OS-00050', status: 'in_progress',
  service_order_photos: [
    { storage_path: 'os-1/depois.jpg', created_at: '2026-10-02T10:00:00Z' },
    { storage_path: 'os-1/antes.jpg', created_at: '2026-10-01T10:00:00Z' },
  ],
};

beforeEach(() => {
  storage.pedidos = [];
  storage.resposta = { data: [], error: null };
});

describe('galeria do PDF com fotos privadas', () => {
  it('pede o caminho (não o link público antigo) e assina na ordem em que as fotos foram tiradas', async () => {
    const { db, selecoes } = bancoFalso(ordemComFotos);
    const assinar = vi.fn(async (caminhos: string[]) => caminhos.map((c) => `https://link/${c}?token=x`));
    const pdf = await carregarPDFData('os-1', db, { assinarFotos: assinar });

    expect(selecoes.find((s) => s.startsWith('service_orders'))).toContain('service_order_photos!service_order_photos_service_order_id_fkey(storage_path, created_at)');
    expect(selecoes.join('\n')).not.toContain('public_url');
    expect(assinar).toHaveBeenCalledWith(['os-1/antes.jpg', 'os-1/depois.jpg']);
    expect(pdf.photos).toEqual(['https://link/os-1/antes.jpg?token=x', 'https://link/os-1/depois.jpg?token=x']);
  });

  it('sem quem assine (link público do cliente), a galeria sai vazia', async () => {
    const { db } = bancoFalso(ordemComFotos);
    const pdf = await carregarPDFData('os-1', db, { publico: true });
    expect(pdf.photos).toEqual([]);
  });

  it('falha ao gerar o link tira só as fotos: o documento sai', async () => {
    const { db } = bancoFalso(ordemComFotos);
    const aviso = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const pdf = await carregarPDFData('os-1', db, { assinarFotos: async () => { throw new Error('storage fora'); } });
    expect(pdf.photos).toEqual([]);
    expect(pdf.documentType).toBe('service_order');
    expect(aviso).toHaveBeenCalledWith('[pdf] fotos da OS sem link temporário:', expect.any(Error));
    aviso.mockRestore();
  });

  it('OS sem foto não pede link nenhum', async () => {
    const { db } = bancoFalso({ ...ordemComFotos, service_order_photos: [] });
    const assinar = vi.fn(async () => []);
    await carregarPDFData('os-1', db, { assinarFotos: assinar });
    expect(assinar).not.toHaveBeenCalled();
  });
});

describe('links temporários da tela', () => {
  it('um pedido só para a galeria, sem repetir caminho, no bucket das fotos', async () => {
    storage.resposta = {
      data: [
        { path: 'os-1/a.jpg', signedUrl: 'https://s/a', error: null },
        { path: 'os-1/b.jpg', signedUrl: 'https://s/b', error: null },
      ],
      error: null,
    };
    const links = await linksDasFotos(['os-1/a.jpg', 'os-1/b.jpg', 'os-1/a.jpg', '']);
    expect(storage.pedidos).toEqual([
      { bucket: 'service-order-photos', caminhos: ['os-1/a.jpg', 'os-1/b.jpg'], validade: VALIDADE_DO_LINK_DA_FOTO_S },
    ]);
    expect(links).toEqual({ 'os-1/a.jpg': 'https://s/a', 'os-1/b.jpg': 'https://s/b' });
  });

  it('caminho que o perfil não vê (ex.: levantamento para o vendedor externo) fica de fora, o resto vem', async () => {
    storage.resposta = {
      data: [
        { path: 'os-1/a.jpg', signedUrl: 'https://s/a', error: null },
        { path: 'surveys/sv-1/1.jpg', signedUrl: null, error: 'Either the object does not exist or you do not have access to it' },
      ],
      error: null,
    };
    expect(await linksEmOrdem(['surveys/sv-1/1.jpg', 'os-1/a.jpg'])).toEqual(['https://s/a']);
  });

  it('lista vazia não chama o Storage', async () => {
    expect(await linksDasFotos([])).toEqual({});
    expect(storage.pedidos).toEqual([]);
  });

  it('erro do Storage não vira "sem foto" calado: lança', async () => {
    storage.resposta = { data: [], error: { message: 'JWT expired' } };
    await expect(linksDasFotos(['os-1/a.jpg'])).rejects.toBeTruthy();
  });
});
