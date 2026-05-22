import { describe, expect, it } from 'vitest';
import {
  extractSignatureStoragePath,
  getSignedPdfDownloadSource,
  isPublicSignatureAssetUrl,
  isTemporarySignatureAssetUrl,
} from './signature-assets';

const publicPdfUrl =
  'https://okurngvcodmljjicopdp.supabase.co/storage/v1/object/public/signatures/order-1/signed-123.pdf';

const signedPdfUrl =
  'https://okurngvcodmljjicopdp.supabase.co/storage/v1/object/sign/signatures/order-1/signed-123.pdf?token=abc';

describe('signature asset helpers', () => {
  it('identifies permanent public signature URLs as unsafe', () => {
    expect(isPublicSignatureAssetUrl(publicPdfUrl)).toBe(true);
    expect(isTemporarySignatureAssetUrl(publicPdfUrl)).toBe(false);
  });

  it('identifies temporary signed URLs as safe to present to users', () => {
    expect(isPublicSignatureAssetUrl(signedPdfUrl)).toBe(false);
    expect(isTemporarySignatureAssetUrl(signedPdfUrl)).toBe(true);
  });

  it('extracts a storage path from legacy public URLs for migration/backfill', () => {
    expect(extractSignatureStoragePath(publicPdfUrl)).toBe('order-1/signed-123.pdf');
  });

  it('keeps already-normalized storage paths unchanged', () => {
    expect(extractSignatureStoragePath('order-1/signed-123.pdf')).toBe('order-1/signed-123.pdf');
  });

  it('uses the archived signed PDF instead of regenerating a signed document in the browser', () => {
    expect(getSignedPdfDownloadSource({ signed_pdf_url: signedPdfUrl })).toEqual({
      kind: 'archived',
      url: signedPdfUrl,
    });
  });

  it('requires a new unsigned PDF only when there is no archived signed PDF', () => {
    expect(getSignedPdfDownloadSource({ signed_pdf_url: null })).toEqual({
      kind: 'generate',
      url: null,
    });
  });
});
