// O aviso de conflito de agenda cita a OS pelo número que get_agenda_conflicts devolve no
// `label` — o service_order_number, que já traz o prefixo ("OS-00060"). Até 12/10/2026 o aviso
// punha "OS " na frente e dizia "o responsável já tem OS OS-00060 nesse horário".
import { describe, it, expect, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));

import { conflictMessage } from './use-agenda';

describe('conflictMessage — número da OS sem "OS " repetido', () => {
  it('a OS vai como vem; a tarefa, entre aspas', () => {
    expect(
      conflictMessage([
        { source: 'service_order', label: 'OS-00060' },
        { source: 'task', label: 'Revisão' },
      ]),
    ).toBe('Conflito de agenda: o responsável já tem OS-00060, "Revisão" nesse horário.');
  });

  it('(Fase 2) a alocação da agenda vai como a OS, e a OS que ocupa dois turnos aparece uma vez só', () => {
    expect(
      conflictMessage([
        { source: 'service_order', label: 'OS-00069' },
        { source: 'service_order', label: 'OS-00069' },
        { source: 'alocacao', label: 'OS-00074' },
        { source: 'alocacao', label: 'OS-00074' },
        { source: 'task', label: 'Revisão' },
      ]),
    ).toBe('Conflito de agenda: o responsável já tem OS-00069, OS-00074, "Revisão" nesse horário.');
  });

  it('o orçamento agendado diz o próprio número, sem "OS ORÇ-"', () => {
    const texto = conflictMessage([{ source: 'service_order', label: 'ORÇ-00112' }]);
    expect(texto).toBe('Conflito de agenda: o responsável já tem ORÇ-00112 nesse horário.');
    expect(texto).not.toContain('OS ORÇ-');
  });
});
