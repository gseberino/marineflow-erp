/**
 * Ponte entre o campo `<input type="datetime-local">` e o banco (`timestamptz`).
 *
 * O campo trabalha com hora LOCAL sem fuso ("2026-09-28T09:00"). O banco guarda um
 * instante. Mandar o texto do campo direto faz o Postgres ler como UTC — 09:00 digitado
 * vira 06:00 em todo lugar que formata com o fuso de Brasília. E ler o instante do banco
 * com `.slice(0, 16)` faz o caminho inverso errado: mostra a hora UTC como se fosse local.
 * Como os dois erros se anulam no próprio formulário, quem digita nunca vê o problema; ele
 * aparece na via do técnico, na agenda e nas listas (achado de 01/10/2026, OS-00104).
 */

const dois = (n: number) => String(n).padStart(2, '0');

/** Instante do banco → texto do campo, na hora local de quem está usando. */
export function isoParaInputLocal(iso: string | null | undefined): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return `${d.getFullYear()}-${dois(d.getMonth() + 1)}-${dois(d.getDate())}T${dois(d.getHours())}:${dois(d.getMinutes())}`;
}

/** Texto do campo (hora local) → instante ISO com fuso, pronto para o banco. Vazio vira null. */
export function inputLocalParaIso(valor: string | null | undefined): string | null {
  if (!valor || !valor.trim()) return null;
  const d = new Date(valor);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}
