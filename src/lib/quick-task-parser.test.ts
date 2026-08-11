// Cobertura da captura rápida da Agenda — módulo sem teste até agora.
//
// É o caminho sem IA: o usuário digita "amanhã 14h ligar pro João" e a tarefa nasce pronta.
// Sendo determinístico e com `now` injetável, dá para testar cada regra de interpretação sem
// depender do relógio — e é o que este arquivo faz.
//
// Dois defeitos de interpretação apareceram enquanto eu escrevia: `NOVO-018` em
// audit/novos-achados.md. Estão documentados aqui pelo que fazem HOJE, marcados com o ID.
import { describe, it, expect } from 'vitest';
import { parseQuickTask } from './quick-task-parser';

/** Terça-feira, 11/08/2026 — todo caso parte daqui. */
const AGORA = new Date(2026, 7, 11);
const dia = (d: Date | null) => (d ? `${d.getDate()}/${d.getMonth() + 1}/${d.getFullYear()}` : null);

describe('dia citado', () => {
  it('"hoje" e "amanhã" (com e sem til)', () => {
    expect(dia(parseQuickTask('hoje revisar orçamento', AGORA).date)).toBe('11/8/2026');
    expect(dia(parseQuickTask('amanhã revisar orçamento', AGORA).date)).toBe('12/8/2026');
    expect(dia(parseQuickTask('amanha revisar orçamento', AGORA).date)).toBe('12/8/2026');
  });

  it('dia da semana vai para a próxima ocorrência', () => {
    expect(dia(parseQuickTask('sexta entregar laudo', AGORA).date)).toBe('14/8/2026');
    expect(dia(parseQuickTask('segunda-feira cobrar cliente', AGORA).date)).toBe('17/8/2026');
    expect(dia(parseQuickTask('sábado plantão', AGORA).date)).toBe('15/8/2026');
  });

  it('o dia da semana de HOJE significa a semana que vem, não agora', () => {
    // Numa terça, "terça" quase nunca quer dizer "daqui a zero dias" — quem quer hoje
    // escreve "hoje". A regra está no código e este caso a mantém.
    expect(dia(parseQuickTask('terça reunião', AGORA).date)).toBe('18/8/2026');
  });

  it('aceita dia da semana sem acento', () => {
    expect(dia(parseQuickTask('terca reunião', AGORA).date)).toBe('18/8/2026');
    expect(dia(parseQuickTask('sabado plantão', AGORA).date)).toBe('15/8/2026');
  });

  it('data dd/mm sem ano: se já passou neste ano, é do ano que vem', () => {
    expect(dia(parseQuickTask('20/12 confraternização', AGORA).date)).toBe('20/12/2026');
    expect(dia(parseQuickTask('05/03 revisão anual', AGORA).date)).toBe('5/3/2027');
  });

  it('data com ano explícito é respeitada, com dois ou quatro dígitos', () => {
    expect(dia(parseQuickTask('05/03/27 revisão', AGORA).date)).toBe('5/3/2027');
    expect(dia(parseQuickTask('05/03/2028 revisão', AGORA).date)).toBe('5/3/2028');
  });

  it('sem nenhuma pista de dia, a data fica nula — não assume hoje', () => {
    const r = parseQuickTask('comprar cabo de bateria', AGORA);
    expect(r.date).toBeNull();
    expect(r.time).toBeNull();
    expect(r.title).toBe('comprar cabo de bateria');
  });
});

describe('hora citada', () => {
  it('entende 14h, 14h30, 14:30 e "às 9"', () => {
    expect(parseQuickTask('amanhã 14h ligar', AGORA).time).toBe('14:00');
    expect(parseQuickTask('amanhã 14h30 ligar', AGORA).time).toBe('14:30');
    expect(parseQuickTask('amanhã 14:30 ligar', AGORA).time).toBe('14:30');
    expect(parseQuickTask('amanhã às 9 ligar', AGORA).time).toBe('09:00');
    expect(parseQuickTask('amanhã as 9 ligar', AGORA).time).toBe('09:00');
  });

  it('hora sem dia significa hoje', () => {
    const r = parseQuickTask('16h ligar pro estaleiro', AGORA);
    expect(r.time).toBe('16:00');
    expect(dia(r.date)).toBe('11/8/2026');
  });

  it('número acima de 23 não é hora', () => {
    const r = parseQuickTask('pagar boleto 25', AGORA);
    expect(r.time).toBeNull();
    expect(r.title).toBe('pagar boleto 25');
  });
});

describe('prioridade', () => {
  it('"urgente" e "!!" marcam urgente; "importante" e "!" marcam alta', () => {
    expect(parseQuickTask('urgente ligar pro cliente', AGORA).priority).toBe('urgent');
    expect(parseQuickTask('ligar pro cliente !! ', AGORA).priority).toBe('urgent');
    expect(parseQuickTask('importante ligar pro cliente', AGORA).priority).toBe('high');
    expect(parseQuickTask('ligar pro cliente ! ', AGORA).priority).toBe('high');
  });

  it('a palavra de prioridade sai do título', () => {
    expect(parseQuickTask('urgente ligar pro cliente', AGORA).title).toBe('ligar pro cliente');
  });

  it('sem marcação, prioridade é nula — não inventa "normal"', () => {
    expect(parseQuickTask('ligar pro cliente', AGORA).priority).toBeNull();
  });
});

describe('título', () => {
  it('sobra só o texto, sem as marcas consumidas e sem espaço dobrado', () => {
    const r = parseQuickTask('  urgente amanhã 14h30   ligar pro João do estaleiro  ', AGORA);
    expect(r.title).toBe('ligar pro João do estaleiro');
    expect(r.priority).toBe('urgent');
    expect(r.time).toBe('14:30');
    expect(dia(r.date)).toBe('12/8/2026');
  });

  it('entrada vazia não quebra', () => {
    expect(parseQuickTask('', AGORA)).toEqual({ title: '', date: null, time: null, priority: null });
    expect(parseQuickTask('   ', AGORA).title).toBe('');
  });
});

describe('[NOVO-018] interpretações erradas conhecidas — documentadas, não aprovadas', () => {
  it('quantidade no meio do texto é lida como hora, e some do título', () => {
    // "comprar 3 cabos" vira uma tarefa das 03:00 chamada "comprar cabos". Some a
    // quantidade — que é o dado que importa — e aparece um horário que ninguém pediu.
    const r = parseQuickTask('comprar 3 cabos', AGORA);
    expect(r.time).toBe('03:00');
    expect(r.title).toBe('comprar cabos');
    expect(dia(r.date)).toBe('11/8/2026');

    const r2 = parseQuickTask('comprar 10 disjuntores urgente', AGORA);
    expect(r2.time).toBe('10:00');
    expect(r2.title).toBe('comprar disjuntores');
  });

  it('data inexistente vira outro dia em vez de ser recusada', () => {
    // `new Date(2026, 1, 30)` não é inválida: o JavaScript normaliza 30 de fevereiro para
    // 2 de março. Como essa data já passou, a regra do "ano que vem" empurra para 2027 — e a
    // tarefa nasce a mais de um ano de distância, sem nenhum aviso.
    expect(dia(parseQuickTask('revisar 30/02', AGORA).date)).toBe('2/3/2027');
    expect(dia(parseQuickTask('revisar 31/11/2026', AGORA).date)).toBe('1/12/2026');
  });
});
