import { supabase } from '@/integrations/supabase/client';
import { queryClient } from '@/lib/query-client';

const MAX_ERRORS = 50;
const MAX_NETWORK = 50;
const MAX_CONSOLE = 100;
const MAX_WHATSAPP = 50;

type ErrorEntry = {
  ts: string;
  type: 'error' | 'unhandledrejection';
  message: string;
  source?: string;
  lineno?: number;
  colno?: number;
  stack?: string;
};

type NetworkEntry = {
  ts: string;
  url: string;
  method: string;
  status?: number;
  ok?: boolean;
  durationMs?: number;
  errorMessage?: string;
};

type ConsoleEntry = {
  ts: string;
  level: 'log' | 'warn' | 'error' | 'info' | 'debug';
  message: string;
};

export type WhatsAppEvent = {
  ts: string;
  source: 'list_dropdown' | 'detail_dialog' | string;
  action: 'preview' | 'send';
  serviceOrderId?: string;
  serviceOrderNumber?: string;
  shareToken?: string;
  phoneRaw?: string;
  phoneNormalized?: string;
  hasPhone: boolean;
  opened?: boolean;
  popupBlocked?: boolean;
  errorMessage?: string;
  userAgent?: string;
};

const errorBuffer: ErrorEntry[] = [];
const networkBuffer: NetworkEntry[] = [];
const consoleBuffer: ConsoleEntry[] = [];
const whatsappBuffer: WhatsAppEvent[] = [];

function pushCapped<T>(buf: T[], item: T, max: number) {
  buf.push(item);
  if (buf.length > max) buf.splice(0, buf.length - max);
}

// --- masking ---
const JWT_RE = /\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{5,}\b/g;
const BEARER_RE = /Bearer\s+[A-Za-z0-9._\-]+/gi;
const LONG_TOKEN_RE = /\b[A-Za-z0-9_\-]{40,}\b/g;

function mask(input: string): string {
  if (!input) return input;
  return input
    .replace(JWT_RE, '<JWT:redacted>')
    .replace(BEARER_RE, 'Bearer <redacted>')
    .replace(LONG_TOKEN_RE, (m) => `<token:${m.length}c>`);
}

function maskUrl(url: string): string {
  try {
    const u = new URL(url, window.location.origin);
    // Strip query params that look sensitive
    u.searchParams.forEach((v, k) => {
      if (/token|key|secret|jwt|access|refresh|auth|password/i.test(k)) {
        u.searchParams.set(k, '<redacted>');
      } else if (v.length > 40) {
        u.searchParams.set(k, `<long:${v.length}c>`);
      }
    });
    return u.toString();
  } catch {
    return mask(url);
  }
}

function safeStringify(value: unknown): string {
  try {
    if (typeof value === 'string') return value;
    if (value instanceof Error) return `${value.name}: ${value.message}`;
    return JSON.stringify(value, (_k, v) => {
      if (typeof v === 'string' && v.length > 500) return v.slice(0, 500) + '…';
      return v;
    });
  } catch {
    return String(value);
  }
}

let installed = false;

export function installDiagnostics() {
  if (installed || typeof window === 'undefined') return;
  installed = true;

  // --- error listeners ---
  window.addEventListener('error', (ev) => {
    pushCapped(
      errorBuffer,
      {
        ts: new Date().toISOString(),
        type: 'error',
        message: mask(ev.message || 'Unknown error'),
        source: ev.filename ? maskUrl(ev.filename) : undefined,
        lineno: ev.lineno,
        colno: ev.colno,
        stack: ev.error?.stack ? mask(String(ev.error.stack)).slice(0, 4000) : undefined,
      },
      MAX_ERRORS,
    );
  });

  window.addEventListener('unhandledrejection', (ev) => {
    const reason = ev.reason;
    pushCapped(
      errorBuffer,
      {
        ts: new Date().toISOString(),
        type: 'unhandledrejection',
        message: mask(safeStringify(reason?.message ?? reason)),
        stack: reason?.stack ? mask(String(reason.stack)).slice(0, 4000) : undefined,
      },
      MAX_ERRORS,
    );
  });

  // --- console wrapper ---
  (['log', 'warn', 'error', 'info', 'debug'] as const).forEach((level) => {
    const original = console[level].bind(console);
    console[level] = (...args: unknown[]) => {
      try {
        pushCapped(
          consoleBuffer,
          {
            ts: new Date().toISOString(),
            level,
            message: mask(args.map(safeStringify).join(' ')).slice(0, 2000),
          },
          MAX_CONSOLE,
        );
      } catch {
        /* ignore */
      }
      original(...args);
    };
  });

  // --- fetch wrapper ---
  const originalFetch = window.fetch.bind(window);
  window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    const start = performance.now();
    const url =
      typeof input === 'string'
        ? input
        : input instanceof URL
          ? input.toString()
          : input.url;
    const method = (init?.method || (input instanceof Request ? input.method : 'GET') || 'GET').toUpperCase();
    try {
      const res = await originalFetch(input as RequestInfo, init);
      pushCapped(
        networkBuffer,
        {
          ts: new Date().toISOString(),
          url: maskUrl(url),
          method,
          status: res.status,
          ok: res.ok,
          durationMs: Math.round(performance.now() - start),
        },
        MAX_NETWORK,
      );
      return res;
    } catch (err: any) {
      pushCapped(
        networkBuffer,
        {
          ts: new Date().toISOString(),
          url: maskUrl(url),
          method,
          durationMs: Math.round(performance.now() - start),
          errorMessage: mask(String(err?.message || err)),
        },
        MAX_NETWORK,
      );
      throw err;
    }
  };
}

function snapshotSession(session: any, user: any, authReady: boolean) {
  const expiresAt = session?.expires_at ? Number(session.expires_at) : null;
  const nowSec = Math.floor(Date.now() / 1000);
  return {
    authReady,
    hasSession: !!session,
    expiresAt: expiresAt ? new Date(expiresAt * 1000).toISOString() : null,
    secondsUntilExpiry: expiresAt ? expiresAt - nowSec : null,
    tokenType: session?.token_type ?? null,
    user: user
      ? {
          id: user.id,
          email: user.email,
          role: user.role,
          fullName: user.full_name,
        }
      : null,
  };
}

function snapshotEnv() {
  return {
    userAgent: navigator.userAgent,
    language: navigator.language,
    online: navigator.onLine,
    viewport: { w: window.innerWidth, h: window.innerHeight, dpr: window.devicePixelRatio },
    url: maskUrl(window.location.href),
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    mode: import.meta.env.MODE,
    timestamp: new Date().toISOString(),
  };
}

function snapshotStorage() {
  const entries: Array<{ key: string; sizeChars: number }> = [];
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (!key) continue;
      if (/supabase|sb-|marineflow/i.test(key)) {
        const v = localStorage.getItem(key);
        entries.push({ key, sizeChars: v?.length ?? 0 });
      }
    }
  } catch {
    /* ignore */
  }
  return entries;
}

function snapshotQueries() {
  try {
    return queryClient
      .getQueryCache()
      .getAll()
      .map((q) => ({
        queryKey: q.queryKey,
        status: q.state.status,
        fetchStatus: q.state.fetchStatus,
        dataUpdatedAt: q.state.dataUpdatedAt
          ? new Date(q.state.dataUpdatedAt).toISOString()
          : null,
        errorUpdatedAt: q.state.errorUpdatedAt
          ? new Date(q.state.errorUpdatedAt).toISOString()
          : null,
        errorMessage: q.state.error ? mask(String((q.state.error as any)?.message ?? q.state.error)) : null,
        observers: q.getObserversCount(),
      }));
  } catch (err) {
    return [{ error: mask(String(err)) }];
  }
}

async function snapshotAuditLog(userId: string | null) {
  if (!userId) return [];
  try {
    const { data, error } = await supabase
      .from('audit_log')
      .select('id, table_name, record_id, action, changed_at, changed_by, reason, new_value')
      .eq('changed_by', userId)
      .order('changed_at', { ascending: false })
      .limit(100);
    if (error) return [{ error: mask(error.message) }];
    return data ?? [];
  } catch (err: any) {
    return [{ error: mask(String(err?.message || err)) }];
  }
}

function maskPhone(phone?: string): string | undefined {
  if (!phone) return phone;
  // keep country code + last 2 digits visible: +5511*****12
  if (phone.length < 6) return phone;
  return phone.slice(0, 3) + '*'.repeat(Math.max(0, phone.length - 5)) + phone.slice(-2);
}

export function recordWhatsAppEvent(ev: Omit<WhatsAppEvent, 'ts' | 'hasPhone' | 'userAgent'> & { phoneNormalized?: string; phoneRaw?: string }) {
  const entry: WhatsAppEvent = {
    ts: new Date().toISOString(),
    source: ev.source,
    action: ev.action,
    serviceOrderId: ev.serviceOrderId,
    serviceOrderNumber: ev.serviceOrderNumber,
    shareToken: ev.shareToken,
    phoneRaw: maskPhone(ev.phoneRaw),
    phoneNormalized: maskPhone(ev.phoneNormalized),
    hasPhone: !!ev.phoneNormalized,
    opened: ev.opened,
    popupBlocked: ev.popupBlocked,
    errorMessage: ev.errorMessage ? mask(ev.errorMessage) : undefined,
    userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : undefined,
  };
  pushCapped(whatsappBuffer, entry, MAX_WHATSAPP);
  // Mirror in console buffer for cross-reference
  try {
    console.info('[whatsapp]', entry.action, entry.source, {
      so: entry.serviceOrderNumber,
      opened: entry.opened,
      hasPhone: entry.hasPhone,
    });
  } catch {
    /* ignore */
  }
}

export type DiagnosticContext = {
  authReady: boolean;
  session: any;
  user: any;
};

export async function buildDiagnosticPackage(ctx: DiagnosticContext) {
  const audit = await snapshotAuditLog(ctx.user?.id ?? ctx.session?.user?.id ?? null);
  return {
    schemaVersion: 2,
    generatedAt: new Date().toISOString(),
    app: 'MarineFlow',
    environment: snapshotEnv(),
    session: snapshotSession(ctx.session, ctx.user, ctx.authReady),
    storage: snapshotStorage(),
    reactQuery: snapshotQueries(),
    recentErrors: [...errorBuffer],
    recentNetwork: [...networkBuffer],
    recentConsole: [...consoleBuffer],
    whatsappEvents: [...whatsappBuffer],
    auditLog: audit,
  };
}

export function downloadDiagnosticFile(pkg: unknown) {
  const json = JSON.stringify(pkg, null, 2);
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  a.href = url;
  a.download = `marineflow-diagnostico-${ts}.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
