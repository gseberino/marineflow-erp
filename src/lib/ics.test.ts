import { describe, it, expect } from 'vitest';
import { gerarIcs, icsEscape, icsFold, tarefaParaVevento } from './ics';

const agora = new Date('2026-09-19T12:00:00Z');

describe('exportação .ics da agenda', () => {
  it('compromisso com hora vira evento com DTSTART/DTEND em UTC', () => {
    const v = tarefaParaVevento(
      { id: 'a1', title: 'Visita Vanderlei', scheduled_start_at: '2026-09-22T13:00:00Z', scheduled_end_at: '2026-09-22T15:30:00Z' },
      agora,
    )!;
    expect(v).toContain('DTSTART:20260922T130000Z');
    expect(v).toContain('DTEND:20260922T153000Z');
    expect(v).toContain('SUMMARY:Visita Vanderlei');
    expect(v).toContain('UID:marineflow-tarefa-a1@hbrmarine');
  });

  it('início sem fim ganha uma hora; tarefa só com prazo vira dia inteiro com fim exclusivo', () => {
    const semFim = tarefaParaVevento({ id: 'b', title: 'x', scheduled_start_at: '2026-09-22T13:00:00Z' }, agora)!;
    expect(semFim).toContain('DTEND:20260922T140000Z');
    const soPrazo = tarefaParaVevento({ id: 'c', title: 'Pagar Kamell', due_at: '2026-09-25T12:00:00Z' }, agora)!;
    expect(soPrazo).toMatch(/DTSTART;VALUE=DATE:2026092[45]/);
    expect(soPrazo).toMatch(/DTEND;VALUE=DATE:2026092[56]/);
  });

  it('sem data nenhuma não vira evento', () => {
    expect(tarefaParaVevento({ id: 'd', title: 'sem data' }, agora)).toBeNull();
  });

  it('escapa vírgula, ponto e vírgula e quebra de linha', () => {
    expect(icsEscape('Trocar bateria; conferir, depois\nligar')).toBe('Trocar bateria\\; conferir\\, depois\\nligar');
  });

  it('dobra linhas longas em 75 octetos com continuação por espaço', () => {
    const longa = 'DESCRIPTION:' + 'a'.repeat(200);
    const dobrada = icsFold(longa);
    const linhas = dobrada.split('\r\n');
    expect(linhas.length).toBeGreaterThan(1);
    expect(linhas[0].length).toBe(75);
    for (const l of linhas.slice(1)) expect(l.startsWith(' ')).toBe(true);
    expect(dobrada.replace(/\r\n /g, '')).toBe(longa);
  });

  it('o calendário abre e fecha e traz só os eventos com data', () => {
    const ics = gerarIcs([
      { id: '1', title: 'Com data', due_at: '2026-09-25T12:00:00Z', status: 'done' },
      { id: '2', title: 'Sem data' },
    ], agora);
    expect(ics.startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0')).toBe(true);
    expect(ics.trim().endsWith('END:VCALENDAR')).toBe(true);
    expect((ics.match(/BEGIN:VEVENT/g) ?? []).length).toBe(1);
    expect(ics).toContain('STATUS:COMPLETED');
  });
});
