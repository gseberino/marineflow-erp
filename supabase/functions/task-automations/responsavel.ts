// Quem recebe a tarefa que a regra criou (saiu do index.ts em 23/10/2026 para ter teste).
//
// A regra diz o CARGO ('admin' ou 'financial') ou um uuid; aqui o cargo vira o primeiro app_user
// ativo dele. Até 23/10 o cargo sem ninguém ativo dava null, e a cobrança ia para "sem
// responsável". E a leitura que falhava também dava null, calada. Agora:
//   · 'financial' sem financeiro ativo → o admin (as cobranças e contas são do dono, d02);
//   · erro de leitura → lança: o motor registra a falha da regra na rodada (não cria tarefa órfã).
//
// Enquanto o "Usuário Demo (UI v2)" (financial) estiver ativo, as cobranças novas continuam caindo
// nele. Desativá-lo é pergunta ao dono (Fase 0, decisão de desenho 9).

// deno-lint-ignore no-explicit-any
type Db = any; // mesmo padrão das demais functions: client supabase-js sem schema tipado

export type Cargo = 'admin' | 'financial';

/** O primeiro app_user ativo do cargo (o mais antigo), ou null. Erro de leitura lança. */
async function primeiroAtivoDoCargo(db: Db, cargo: Cargo): Promise<string | null> {
  const { data, error } = await db.from('app_users')
    .select('id').eq('active', true).eq('role', cargo)
    .order('created_at', { ascending: true }).limit(1).maybeSingle();
  if (error) throw error;
  return (data as { id?: string } | null)?.id ?? null;
}

/**
 * Resolve 'admin'/'financial' para um app_user ativo; uuid passa direto; null fica null.
 * `cache` vale por rodada do motor (uma leitura por cargo).
 */
export async function resolveAssignee(
  db: Db,
  who: string | null,
  cache: Map<string, string | null>,
): Promise<string | null> {
  if (!who) return null;
  if (who !== 'admin' && who !== 'financial') return who;
  if (cache.has(who)) return cache.get(who)!;
  let id = await primeiroAtivoDoCargo(db, who);
  if (!id && who === 'financial') id = await resolveAssignee(db, 'admin', cache);
  cache.set(who, id);
  return id;
}
