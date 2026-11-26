// O banco falso e os dados do lembrete antes do vencimento, para os testes (núcleo, tool e rotina). Sem Deno.test aqui.
// deno-lint-ignore no-explicit-any
export type Linha = Record<string, any>;

export const CONTA = "44444444-4444-4444-8444-444444444134";
export const FLAVIO = "7a1b2c3d-1111-4222-8333-444455556666";
export const OS134 = "22222222-2222-4222-8222-222222222134";

export function conta(extra: Linha = {}): Linha {
  return {
    id: CONTA, client_id: FLAVIO, status: "pending", amount: 3292, paid_amount: 0, balance_amount: 3292, due_date: "2026-11-29",
    description: "Saldo — OS-00134", service_order_id: OS134, is_deposit: false, reminder_sent_at: null, ...extra,
  };
}
export function flavio(extra: Linha = {}): Linha {
  return { id: FLAVIO, name: "Flávio da Igreja", display_name: null, whatsapp: "(47) 99999-0001", phone: null, opt_out_whatsapp: false, generico: false, ...extra };
}

/** Banco falso com os filtros que o lembrete usa (eq, in, is, gte, lte, range), update encadeado e insert gravado. */
export function bancoFalso(tabelas: Record<string, Linha[]>, falhas: string[] = []) {
  const chamadas = { insert: [] as [string, unknown][], update: [] as [string, Linha, Array<[string, string, unknown]>][] };
  // deno-lint-ignore no-explicit-any
  const db: any = {
    chamadas,
    tabelas,
    rpc: () => Promise.resolve({ data: null, error: null }),
    from(tabela: string) {
      const filtros: Array<[string, string, unknown]> = [];
      const erro = falhas.includes(tabela) ? { message: `${tabela} fora do ar` } : null;
      const valor = (l: Linha, c: string) => {
        const m = /^(\w+)->>(\w+)$/.exec(c);
        return m ? (l[m[1]] ?? {})[m[2]] : l[c];
      };
      const passa = (l: Linha) => filtros.every(([op, c, v]) => {
        const x = valor(l, c);
        if (op === "eq") return x === v;
        if (op === "in") return (v as unknown[]).includes(x);
        if (op === "is") return (x ?? null) === v;
        if (op === "gte") return x != null && String(x) >= String(v);
        if (op === "lte") return x != null && String(x) <= String(v);
        if (op === "not.is") return (x ?? null) !== v;
        return true;
      });
      const linhas = () => (tabelas[tabela] ?? []).filter(passa);
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q, order: () => q, limit: () => q, range: () => q,
        eq: (c: string, v: unknown) => (filtros.push(["eq", c, v]), q),
        in: (c: string, v: unknown[]) => (filtros.push(["in", c, v]), q),
        is: (c: string, v: unknown) => (filtros.push(["is", c, v]), q),
        gte: (c: string, v: unknown) => (filtros.push(["gte", c, v]), q),
        lte: (c: string, v: unknown) => (filtros.push(["lte", c, v]), q),
        not: (c: string, op: string, v: unknown) => (filtros.push([`not.${op}`, c, v]), q),
        maybeSingle: () => Promise.resolve({ data: erro ? null : linhas()[0] ?? null, error: erro }),
        single: () => Promise.resolve({ data: erro ? null : linhas()[0] ?? null, error: erro }),
        // deno-lint-ignore no-explicit-any
        then: (ok: any, ko: any) => Promise.resolve({ data: erro ? null : linhas(), error: erro }).then(ok, ko),
        insert: (v: unknown) => {
          chamadas.insert.push([tabela, v]);
          const novos: Linha[] = [];
          if (!erro) {
            for (const l of Array.isArray(v) ? v : [v]) {
              const linha = { id: `novo-${tabela}-${(tabelas[tabela] ?? []).length}`, ...l as Linha };
              (tabelas[tabela] ??= []).push(linha);
              novos.push(linha);
            }
          }
          // deno-lint-ignore no-explicit-any
          const r: any = Promise.resolve({ data: null, error: erro });
          r.select = () => {
            // deno-lint-ignore no-explicit-any
            const s: any = Promise.resolve({ data: erro ? null : novos.map((x) => ({ id: x.id })), error: erro });
            s.single = () => Promise.resolve({ data: erro ? null : { id: novos[0]?.id }, error: erro });
            return s;
          };
          return r;
        },
        update: (v: Linha) => {
          const f: Array<[string, string, unknown]> = [];
          // deno-lint-ignore no-explicit-any
          const u: any = {
            eq: (c: string, val: unknown) => (f.push(["eq", c, val]), u),
            is: (c: string, val: unknown) => (f.push(["is", c, val]), u),
            // deno-lint-ignore no-explicit-any
            then: (ok: any, ko: any) => {
              chamadas.update.push([tabela, v, f]);
              if (!erro) {
                for (const l of tabelas[tabela] ?? []) {
                  if (f.every(([op, c, val]) => op === "eq" ? l[c] === val : (l[c] ?? null) === val)) Object.assign(l, v);
                }
              }
              return Promise.resolve({ data: null, error: erro }).then(ok, ko);
            },
          };
          return u;
        },
      };
      return q;
    },
  };
  return db;
}

export function ambiente(tabelas: Record<string, Linha[]> = {}, falhas: string[] = []) {
  return bancoFalso({
    receivables: [conta()],
    clients: [flavio()],
    service_orders: [{ id: OS134, service_order_number: "OS-00134" }],
    app_settings: [{ key: "company_name", value: "HBR Marine Solutions" }, { key: "collection_min_amount", value: "200" }],
    finance_review_queue: [],
    ...tabelas,
  }, falhas);
}
