/**
 * Releitura da OS sem apagar o que está sendo digitado.
 *
 * A tela relê a OS do banco depois de cada gravação (o salvamento automático invalida a
 * consulta), e o efeito de orderData reescrevia o formulário INTEIRO com o que veio: o que a
 * pessoa digitou enquanto a gravação ia e voltava sumia (provado em
 * ServiceOrderForm.rehidratar.test.tsx, 20/10/2026).
 *
 * A regra é a mesclagem de três vias, campo a campo:
 *   · base   = o que a tela recebeu na leitura ANTERIOR;
 *   · local  = o que está na tela agora;
 *   · remoto = o que acabou de chegar do banco.
 * Campo que a pessoa não mexeu desde a leitura anterior (local = base) recebe o remoto — é
 * assim que a troca de status, o sinal, a aprovação e a mudança feita por outra pessoa ou pelo
 * assistente continuam aparecendo. Campo que ela mexeu fica como está; o salvamento
 * automático o grava em seguida.
 *
 * Sem base (primeira leitura, ou outra OS na mesma tela) vale o remoto inteiro, como antes.
 */

/** Igualdade para comparar campos do formulário: 12 e "12" são o mesmo valor; listas e
    objetos (parcelas personalizadas) pelo conteúdo. */
export function mesmoValor(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  const objeto = (v: unknown) => v !== null && typeof v === 'object';
  if (objeto(a) || objeto(b)) return JSON.stringify(a) === JSON.stringify(b);
  return String(a ?? '') === String(b ?? '');
}

/** Um valor só: fica o local se a pessoa mexeu nele desde a base; senão, o remoto. */
export function manterSeMexeu<T>(base: T | undefined, local: T, remoto: T, temBase: boolean): T {
  if (!temBase) return remoto;
  return mesmoValor(local, base) ? remoto : local;
}

export function mesclarReleitura<F extends Record<string, unknown>>(
  base: F | null,
  local: F,
  remoto: F,
): F {
  if (!base) return remoto;
  const resultado: Record<string, unknown> = { ...local };
  for (const k of Object.keys(remoto)) {
    resultado[k] = manterSeMexeu(base[k], local[k], remoto[k], true);
  }
  return resultado as F;
}
