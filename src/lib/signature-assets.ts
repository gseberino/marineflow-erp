export const SIGNATURE_ASSET_TTL_SECONDS = 15 * 60;

type SignatureDownloadInput = {
  signed_pdf_url?: string | null;
};

export type SignedPdfDownloadSource =
  | { kind: 'archived'; url: string }
  | { kind: 'generate'; url: null };

export function isPublicSignatureAssetUrl(value: string | null | undefined): boolean {
  return typeof value === 'string' && value.includes('/storage/v1/object/public/signatures/');
}

export function isTemporarySignatureAssetUrl(value: string | null | undefined): boolean {
  return typeof value === 'string'
    && value.includes('/storage/v1/object/sign/signatures/')
    && value.includes('token=');
}

export function extractSignatureStoragePath(value: string | null | undefined): string | null {
  const clean = String(value || '').trim();
  if (!clean) return null;

  const publicMarker = '/storage/v1/object/public/signatures/';
  const signedMarker = '/storage/v1/object/sign/signatures/';
  const marker = clean.includes(publicMarker) ? publicMarker : signedMarker;
  const markerIndex = clean.indexOf(marker);

  if (markerIndex >= 0) {
    const rawPath = clean.slice(markerIndex + marker.length).split('?')[0];
    return decodeURIComponent(rawPath).replace(/^\/+/, '') || null;
  }

  if (/^https?:\/\//i.test(clean)) return null;
  return clean.replace(/^\/+/, '') || null;
}

export function getSignedPdfDownloadSource(signature: SignatureDownloadInput | null | undefined): SignedPdfDownloadSource {
  const url = String(signature?.signed_pdf_url || '').trim();
  if (url) return { kind: 'archived', url };
  return { kind: 'generate', url: null };
}
