// Via v2, F2: as regras da tela das instruções sugeridas pelo assistente (canal A).
import { describe, expect, it } from 'vitest';
import {
  estadoDoPedido,
  faltaDeInstrucaoNaVia,
  normalizarInstrucao,
  problemaDaInstrucao,
  resumoDaDecisao,
  resumoDoPedido,
  retratoVazio,
  type RetratoDasInstrucoes,
} from './instrucoes-sugeridas';

const base: RetratoDasInstrucoes = { ...retratoVazio('os1'), em_uso: true };

describe('normalizarInstrucao — o texto como o banco grava (uma linha só)', () => {
  it('troca quebra de linha e tab por espaço e junta espaços', () => {
    expect(normalizarInstrucao('Remoção da bomba,\n instalação\t da nova  e teste.')).toBe('Remoção da bomba, instalação da nova e teste.');
  });
  it('vazio vira vazio', () => {
    expect(normalizarInstrucao('   \n ')).toBe('');
  });
});

describe('problemaDaInstrucao — o mesmo limite do banco (10 a 400 letras, sem R$)', () => {
  it('aceita uma frase normal', () => {
    expect(problemaDaInstrucao('Troca do fusível e teste do guincho.')).toBeNull();
  });
  it('recusa curto demais', () => {
    expect(problemaDaInstrucao('Testar.')).toMatch(/10 letras/);
  });
  it('recusa acima de 400', () => {
    expect(problemaDaInstrucao('a'.repeat(401))).toMatch(/400/);
  });
  it('recusa valor em R$ (sumiria do papel)', () => {
    expect(problemaDaInstrucao('Troca do fusível, cobrar r$ 50,00 no fim.')).toMatch(/R\$/);
  });
  it('mede depois de normalizar (quebra de linha não conta como letra a mais)', () => {
    expect(problemaDaInstrucao('Troca do\nfusível.')).toBeNull();
  });
});

describe('estadoDoPedido — o que o botão mostra', () => {
  it('sem job: livre', () => {
    expect(estadoDoPedido(base)).toBe('livre');
  });
  it('job na fila sem começar: na_fila; rodando: rascunhando', () => {
    const job = { id: 'j', status: 'pending', criado_em: '2026-11-20T12:00:00Z', iniciado_em: null, terminado_em: null,
      error_code: null, error: null, linhas: 3, recebidos: null, sem_sugestao: null };
    expect(estadoDoPedido({ ...base, job })).toBe('na_fila');
    expect(estadoDoPedido({ ...base, job: { ...job, status: 'processing', iniciado_em: '2026-11-20T12:00:05Z' } })).toBe('rascunhando');
  });
  it('falhou ou cancelado recente: falhou; pronto: livre', () => {
    const job = { id: 'j', status: 'failed', criado_em: 'x', iniciado_em: null, terminado_em: 'y', error_code: 'timeout', error: null,
      linhas: 1, recebidos: null, sem_sugestao: null };
    expect(estadoDoPedido({ ...base, job })).toBe('falhou');
    expect(estadoDoPedido({ ...base, job: { ...job, status: 'cancelled' } })).toBe('falhou');
    expect(estadoDoPedido({ ...base, job: { ...job, status: 'completed' } })).toBe('livre');
  });
});

describe('resumoDoPedido — o aviso depois do clique', () => {
  it('reuso e assistente juntos', () => {
    expect(resumoDoPedido({ job_id: 'j', job_novo: true, reusadas: 3, pedidas: 5, esperando_job: 0, ja_tem: 0, cobranca: 1, pendentes: 0, sem_sugestao: 0 }))
      .toBe('3 vieram de serviços iguais já aprovados; o assistente está rascunhando as outras 5.');
  });
  it('só o assistente, uma', () => {
    expect(resumoDoPedido({ job_id: 'j', job_novo: true, reusadas: 0, pedidas: 1, esperando_job: 0, ja_tem: 2, cobranca: 0, pendentes: 0, sem_sugestao: 0 }))
      .toBe('O assistente está rascunhando 1 instrução.');
  });
  it('já havia pedido aberto', () => {
    expect(resumoDoPedido({ job_id: 'j', job_novo: false, reusadas: 0, pedidas: 0, esperando_job: 2, ja_tem: 0, cobranca: 0, pendentes: 0, sem_sugestao: 0 }))
      .toBe('O assistente já está rascunhando estas instruções.');
  });
  it('nada a pedir', () => {
    expect(resumoDoPedido({ job_id: null, job_novo: false, reusadas: 0, pedidas: 0, esperando_job: 0, ja_tem: 4, cobranca: 1, pendentes: 0, sem_sugestao: 0 }))
      .toBe('Nenhum serviço precisa de sugestão agora.');
  });
});

describe('resumoDaDecisao — o aviso depois de aprovar', () => {
  it('conta aprovadas, corrigidas e as que não entraram', () => {
    expect(resumoDaDecisao({ itens: [], totais: { aprovado: 10, corrigido: 2, substituido: 1 } }))
      .toBe('12 instruções aprovadas. 1 não entrou: o serviço já tinha instrução ou mudou.');
  });
  it('descartada', () => {
    expect(resumoDaDecisao({ itens: [], totais: { descartado: 1 } })).toBe('Sugestão descartada.');
  });
  it('outro canal já tinha decidido', () => {
    expect(resumoDaDecisao({ itens: [], totais: { ja_decidido: 1 } })).toBe('Esta sugestão já tinha sido decidida.');
  });
});

describe('faltaDeInstrucaoNaVia — o aviso antes de imprimir', () => {
  it('nada pendente: nada', () => {
    expect(faltaDeInstrucaoNaVia(0)).toBeNull();
  });
  it('singular e plural', () => {
    expect(faltaDeInstrucaoNaVia(1)).toBe('instrução sugerida esperando aprovação em 1 serviço');
    expect(faltaDeInstrucaoNaVia(3)).toBe('instrução sugerida esperando aprovação em 3 serviços');
  });
});
