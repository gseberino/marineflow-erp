import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = process.cwd();
const read = (path: string) => readFileSync(resolve(root, path), 'utf8');

describe('signature security source boundaries', () => {
  it('does not expose permanent public signature storage URLs from submit-signature', () => {
    const source = read('supabase/functions/submit-signature/index.ts');

    expect(source).not.toContain('getPublicUrl');
    expect(source).toContain('createSignedUrl');
    expect(source).toContain('signed_pdf_path');
    expect(source).toContain('pdf_sha256');
  });

  it('loads the public service order through the token-scoped Edge Function', () => {
    const source = read('src/pages/PublicServiceOrderView.tsx');

    expect(source).toContain("supabase.functions.invoke('public-service-order'");
    expect(source).not.toContain(".from('service_orders')");
    expect(source).not.toContain(".from('service_order_signatures')");
  });

  it('keeps the internal signature panel behind an authenticated asset function', () => {
    const source = read('src/components/ServiceOrderSignatures.tsx');

    expect(source).toContain("supabase.functions.invoke('service-order-signature-assets'");
    expect(source).not.toContain(".from('service_order_signatures')");
  });

  it('does not keep a real .env file versioned in the release source tree', () => {
    expect(existsSync(resolve(root, '.env'))).toBe(false);
  });
});
