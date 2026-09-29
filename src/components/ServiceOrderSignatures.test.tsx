// Assinaturas da OS na tela interna. Desde 29/09/2026 o bucket é privado: o banco guarda o
// caminho e a tela gera link temporário. O que se protege: a imagem e o PDF abrem pelo link
// temporário (nunca pelo caminho cru), e as assinaturas antigas, gravadas com link público,
// continuam abrindo porque o caminho é tirado de dentro do link.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const estado = vi.hoisted(() => ({
  linhas: [] as Record<string, unknown>[],
  assinados: [] as string[],
}));

vi.mock('@/integrations/supabase/client', () => {
  const q: Record<string, unknown> = {};
  Object.assign(q, {
    select: () => q, eq: () => q,
    order: async () => ({ data: estado.linhas, error: null }),
  });
  return {
    supabase: {
      from: () => q,
      storage: {
        from: (bucket: string) => ({
          createSignedUrl: async (caminho: string) => {
            estado.assinados.push(`${bucket}/${caminho}`);
            return { data: { signedUrl: `https://sb.example/storage/v1/object/sign/${bucket}/${caminho}?token=t` }, error: null };
          },
        }),
      },
    },
  };
});

import { ServiceOrderSignatures } from './ServiceOrderSignatures';

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><ServiceOrderSignatures serviceOrderId="os-1" /></QueryClientProvider>);
}

const linha = (img: string, pdf: string) => ({
  id: 's-1', accepted_name: 'Cliente Teste', signed_at: '2026-08-23T18:47:17Z',
  signature_image_url: img, signed_pdf_url: pdf, document_hash: 'abc123def456abc123def456',
  ip_address: null, user_agent: null, superseded_at: null, superseded_reason: null, accepted_terms_snapshot: null,
});

beforeEach(() => { estado.assinados = []; });

describe('assinaturas da OS (bucket privado)', () => {
  it('caminho gravado: imagem e PDF abrem por link temporário', async () => {
    estado.linhas = [linha('os-1/1.png', 'os-1/signed-1.pdf')];
    montar();
    const img = await screen.findByAltText('Assinatura de Cliente Teste');
    expect(img.getAttribute('src')).toContain('/object/sign/signatures/os-1/1.png?token=');
    await waitFor(() => expect(screen.getByText('PDF arquivado da OS').closest('a')?.getAttribute('href'))
      .toContain('/object/sign/signatures/os-1/signed-1.pdf?token='));
  });

  it('assinatura antiga com link público: o caminho sai de dentro do link', async () => {
    const base = 'https://okurngvcodmljjicopdp.supabase.co/storage/v1/object/public/signatures';
    estado.linhas = [linha(`${base}/os-1/1.png`, `${base}/os-1/signed-1.pdf`)];
    montar();
    await screen.findByAltText('Assinatura de Cliente Teste');
    await waitFor(() => expect(estado.assinados).toEqual(expect.arrayContaining([
      'signatures/os-1/1.png', 'signatures/os-1/signed-1.pdf',
    ])));
  });
});
