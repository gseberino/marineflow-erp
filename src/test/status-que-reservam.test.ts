// A lista de status que RESERVA estoque é a mesma nos três lugares (Agenda de Produção, Fase 0, P5).
//
// A reserva própria (24/10/2026) só funciona se "a OS reserva?" for respondido igual por quem RESERVA
// (recompute_product_reservations, no banco) e por quem DESCONTA a reserva própria (a CTE `os` de
// get_os_purchase_needs e STATUS_QUE_RESERVAM em src/lib/purchase-needs.ts). Se uma das três ganhar um
// status e as outras não, a conta volta a errar calada: com 'open' só de um lado, por exemplo, a OS
// aberta devolveria ao disponível uma reserva que nunca existiu e enxergaria a peça de outra OS.
//
// 'open' fica fora das três hoje (NOVO-agenda-01: registrado, não corrigido). Mudar isso é mudar as três
// juntas — e este teste é o que obriga.

import { describe, expect, it } from 'vitest';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { STATUS_QUE_RESERVAM } from '@/lib/purchase-needs';

const MIGRATIONS = join(process.cwd(), 'supabase', 'migrations');

function ler(arquivo: string): string {
  return readFileSync(join(MIGRATIONS, arquivo), 'utf8').replace(/\r\n/g, '\n');
}

/** Os status de um `... status in ('a','b', …)` como lista ordenada. */
function lista(trecho: string): string[] {
  return [...trecho.matchAll(/'(\w+)'/g)].map((m) => m[1]).sort();
}

/** A migration MAIS RECENTE que (re)define recompute_product_reservations. */
function ultimaQueDefineORecalculo(): string {
  const candidatas = readdirSync(MIGRATIONS)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .filter((f) => /function\s+public\.recompute_product_reservations\s*\(/i.test(ler(f)));
  return candidatas[candidatas.length - 1];
}

describe('status que reservam estoque', () => {
  it('a definição vigente do recálculo é a de 20260724220000 (senão, confira a lista nova)', () => {
    expect(ultimaQueDefineORecalculo()).toBe('20260724220000_stock_v2_status_sets_fix.sql');
  });

  it('o TS (STATUS_QUE_RESERVAM) = recompute_product_reservations', () => {
    const sql = ler(ultimaQueDefineORecalculo());
    const corpo = sql.slice(sql.search(/function\s+public\.recompute_product_reservations/i));
    const fim = corpo.indexOf('$$;');
    const m = /so\.status\s+in\s*\(([^)]*)\)/i.exec(corpo.slice(0, fim));
    expect(m, 'a lista do recálculo não foi encontrada').not.toBeNull();
    expect(lista(m![1])).toEqual([...STATUS_QUE_RESERVAM].sort());
  });

  it('o TS = a CTE `os` de get_os_purchase_needs (20261024150100)', () => {
    const sql = ler('20261024150100_compras_reserva_propria_e_ja_pedido.sql');
    const m = /so\.status\s+in\s*\(([^)]*)\)\s+as\s+reserva/i.exec(sql);
    expect(m, 'a lista da reserva própria não foi encontrada').not.toBeNull();
    expect(lista(m![1])).toEqual([...STATUS_QUE_RESERVAM].sort());
  });

  // Desde a Fase 1 (P2) get_os_purchase_needs = aplicar_os_material(os_necessidade_bruta(…), os_material):
  // a CTE `os` vive na conta bruta, que é o corpo de 150100 copiado sem mudar uma linha.
  const corpo = (arquivo: string, funcao: string): string => {
    const sql = ler(arquivo);
    const i = sql.indexOf(`create or replace function public.${funcao}(p_so_id uuid)`);
    expect(i, `${funcao} não está em ${arquivo}`).toBeGreaterThanOrEqual(0);
    const a = sql.indexOf('as $function$', i) + 'as $function$'.length;
    return sql.slice(a, sql.indexOf('$function$;', a));
  };

  it('o TS = a CTE `os` de os_necessidade_bruta (20261024160300), a conta bruta da RPC', () => {
    const m = /so\.status\s+in\s*\(([^)]*)\)\s+as\s+reserva/i.exec(
      corpo('20261024160300_agenda_fase1_material.sql', 'os_necessidade_bruta'));
    expect(m, 'a lista da reserva própria não foi encontrada na conta bruta').not.toBeNull();
    expect(lista(m![1])).toEqual([...STATUS_QUE_RESERVAM].sort());
  });

  it('os_necessidade_bruta é o corpo de get_os_purchase_needs de 150100, sem mudar uma linha', () => {
    expect(corpo('20261024160300_agenda_fase1_material.sql', 'os_necessidade_bruta'))
      .toBe(corpo('20261024150100_compras_reserva_propria_e_ja_pedido.sql', 'get_os_purchase_needs'));
  });

  it("'open' não reserva (NOVO-agenda-01) e nenhum status encerrado reserva", () => {
    for (const s of ['open', 'draft', 'completed', 'invoiced', 'cancelled']) {
      expect(STATUS_QUE_RESERVAM as readonly string[]).not.toContain(s);
    }
  });
});
