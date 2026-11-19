/**
 * Banco falso para testes de tela e de hook: responde por "tabela.operação" e anota cada chamada.
 *
 * Uso (o vi.mock é içado; por isso o import é dinâmico dentro da fábrica):
 *
 *   vi.mock('@/integrations/supabase/client', async () => ({ supabase: (await import('@/test/banco-falso')).supabaseFalso }));
 *   import { banco, ok, falha, reiniciarBanco } from '@/test/banco-falso';
 *   banco.respostas['app_settings.select'] = falha('timeout');
 *
 * Operações: select, insert, update, upsert, delete; rpc vira "rpc.nome"; functions.invoke vira
 * "fn.nome". Uma lista de respostas é consumida em ordem (a última se repete). Sem resposta
 * cadastrada, devolve { data: null, error: null }.
 */
export type Resposta = { data: unknown; error: { message: string; code?: string } | null; count?: number | null };
export type Chamada = { alvo: string; op: string; valores?: unknown; filtros: unknown[][] };

export const banco = {
  respostas: {} as Record<string, Resposta | Resposta[]>,
  chamadas: [] as Chamada[],
};

export const ok = (data: unknown, count?: number): Resposta => ({ data, error: null, count: count ?? null });
export const falha = (message = 'falha simulada'): Resposta => ({ data: null, error: { message } });

export function reiniciarBanco() {
  banco.respostas = {};
  banco.chamadas = [];
}

/** As chamadas a uma tabela/operação ("payments.insert"). */
export function chamadasA(chave: string): Chamada[] {
  return banco.chamadas.filter((c) => `${c.alvo}.${c.op}` === chave);
}

function responder(chave: string): Resposta {
  const r = banco.respostas[chave];
  if (Array.isArray(r)) return r.length > 1 ? r.shift()! : r[0];
  return r ?? { data: null, error: null };
}

const FILTROS = [
  'select', 'eq', 'neq', 'in', 'not', 'is', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'or', 'and',
  'order', 'limit', 'range', 'filter', 'match', 'contains', 'overlaps', 'textSearch', 'returns', 'abortSignal',
];

function consulta(tabela: string) {
  const registro: Chamada = { alvo: tabela, op: 'select', valores: undefined, filtros: [] };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const q: any = {};
  for (const m of FILTROS) {
    q[m] = (...a: unknown[]) => { registro.filtros.push([m, ...a]); return q; };
  }
  for (const op of ['insert', 'update', 'upsert', 'delete']) {
    q[op] = (v?: unknown) => { registro.op = op; registro.valores = v; return q; };
  }
  q.single = () => q;
  q.maybeSingle = () => q;
  q.csv = () => q;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  q.then = (sucesso: any, erro: any) => {
    banco.chamadas.push(registro);
    return Promise.resolve(responder(`${tabela}.${registro.op}`)).then(sucesso, erro);
  };
  return q;
}

export const supabaseFalso = {
  from: (tabela: string) => consulta(tabela),
  rpc: (nome: string, args?: unknown) => {
    banco.chamadas.push({ alvo: `rpc`, op: nome, valores: args, filtros: [] });
    return Promise.resolve(responder(`rpc.${nome}`));
  },
  functions: {
    invoke: (nome: string, opcoes?: unknown) => {
      banco.chamadas.push({ alvo: 'fn', op: nome, valores: opcoes, filtros: [] });
      return Promise.resolve(responder(`fn.${nome}`));
    },
  },
  auth: {
    getUser: () => Promise.resolve({ data: { user: { id: 'u-teste', email: 'teste@exemplo.com' } }, error: null }),
    getSession: () => Promise.resolve({ data: { session: null }, error: null }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
  },
  channel: () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const c: any = { on: () => c, subscribe: () => c, unsubscribe: () => {} };
    return c;
  },
  removeChannel: () => {},
};
