// [VERIFICAÇÃO 18/08] O número NACIONAL da NFS-e vem do provider_status — este teste
// trava o mapeamento contra uma FIXTURE REAL (status da Contora após a autorização da
// nossa nota de homologação, RPS 6 → NFS-e nº 2, 15/08/2026 + campos do retorno que o
// suporte confirmou em 16/08). Se a Contora renomear os campos, este teste aponta antes
// de a UI voltar a mostrar RPS como se fosse o número da nota.
import { describe, it, expect } from 'vitest';
import { numeroNacionalNfse, type DocumentoNfse } from '@/hooks/use-nfse';

// Recorte do GET .../status real (campos relevantes) mesclado no provider_status pelo
// applyStatusUpdate — como fica na linha de issued_fiscal_documents.
const FIXTURE_STATUS_AUTORIZADO = {
  environment: 'homologacao',
  rps_number: 6,
  nfse_number: '2',
  display_number: '2',
  access_key: '42082032250057049000159000000000000226086675782875',
  lifecycle: { status: 'authorized', processing_status: 'completed' },
};

function doc(providerStatus: Record<string, unknown> | null): DocumentoNfse {
  return {
    id: 'x', number: 6, series: 1, status: 'authorized', environment: 'homologacao',
    status_message: null, created_at: null, origin_id: null,
    provider_status: providerStatus as DocumentoNfse['provider_status'],
  };
}

describe('número nacional da NFS-e (fixture real da Contora)', () => {
  it('extrai o nfse_number — e ele é DIFERENTE do RPS', () => {
    const d = doc(FIXTURE_STATUS_AUTORIZADO);
    expect(numeroNacionalNfse(d)).toBe('2');
    expect(numeroNacionalNfse(d)).not.toBe(String(d.number)); // RPS 6 ≠ nota 2
  });

  it('cai para display_number quando nfse_number falta', () => {
    expect(numeroNacionalNfse(doc({ display_number: '7' }))).toBe('7');
  });

  it('sem status sincronizado ainda, devolve null (a UI mostra o RPS rotulado)', () => {
    expect(numeroNacionalNfse(doc(null))).toBeNull();
    expect(numeroNacionalNfse(doc({ nfse_number: '' }))).toBeNull();
    expect(numeroNacionalNfse(doc({ nfse_number: null }))).toBeNull();
  });
});
