export type DuplicateKeyRule = Record<string, string[]>;

export type ForeignKeyRule = {
  table: string;
  column: string;
  references: string;
};

export const duplicateKeyRules: DuplicateKeyRule = {
  clients: ['email', 'cpf_cnpj'],
  suppliers: ['email', 'cnpj_cpf'],
  services: ['name'],
};

export const foreignKeyRules: ForeignKeyRule[] = [
  { table: 'service_orders', column: 'client_id', references: 'clients' },
  { table: 'service_orders', column: 'vessel_id', references: 'vessels' },
  { table: 'service_order_parts', column: 'service_order_id', references: 'service_orders' },
  { table: 'service_order_services', column: 'service_order_id', references: 'service_orders' },
  { table: 'service_order_technicians', column: 'service_order_id', references: 'service_orders' },
  { table: 'external_quotes', column: 'lead_id', references: 'external_quote_leads' },
];

export const importGuardMessage =
  'Set CONFIRM_IMPORT=true only after backup confirmation, dry-run approval, and explicit authorization.';

export const blockedProjectRefs = [
  'vmareepfbgocyleknrgg',
  'zssewfqhmrlagqbfqsmb',
];

export function extractSupabaseProjectRef(input: string | undefined | null): string | null {
  if (!input) {
    return null;
  }

  const value = input.trim();
  if (!value) {
    return null;
  }

  for (const blockedRef of blockedProjectRefs) {
    if (value.includes(blockedRef)) {
      return blockedRef;
    }
  }

  try {
    const parsed = new URL(value);
    const hostnameParts = parsed.hostname.split('.');
    if (hostnameParts.length >= 3 && hostnameParts.at(-2) === 'supabase' && hostnameParts.at(-1) === 'co') {
      return hostnameParts[0] ?? null;
    }
  } catch {
    // Not a URL. Fall through to a gentle heuristic.
  }

  const refMatch = value.match(/[a-z0-9]{20,}/i);
  return refMatch?.[0] ?? null;
}

export function isBlockedSupabaseProjectRef(input: string | undefined | null): boolean {
  const ref = extractSupabaseProjectRef(input);
  return Boolean(ref && blockedProjectRefs.includes(ref));
}

export function isProbablyProductionContext(env: Record<string, string | undefined> = process.env): boolean {
  const nodeEnv = env.NODE_ENV?.toLowerCase();
  const vercelEnv = env.VERCEL_ENV?.toLowerCase();
  if (nodeEnv === 'production' || vercelEnv === 'production') {
    return true;
  }

  const appUrl = env.APP_PUBLIC_URL?.trim().toLowerCase() ?? '';
  if (!appUrl) {
    return false;
  }

  if (appUrl.includes('localhost') || appUrl.includes('127.0.0.1') || appUrl.includes('0.0.0.0')) {
    return false;
  }

  return appUrl.includes('vercel.app') || appUrl.includes('lovable.app') || appUrl.includes('production');
}
