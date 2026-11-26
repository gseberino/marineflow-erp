// A tela de atividade do assistente não lista o rastro por mensagem (pacote 1, C4, 25/11/2026).
//
// Cada mensagem que chega ao assistente pelo WhatsApp deixa uma linha "rota:<camada>" em ai_operator_audit
// (supabase/functions/_shared/ai/rota-da-mensagem.ts). São ~15 linhas por dia: sem o filtro, elas tomam os 50
// "últimos eventos" da tela e a atividade de verdade (aprovações, ferramentas, recusas) some.
//
// O que este teste cobra: a leitura da tela exclui as linhas pelo MESMO prefixo que a edge function grava. Se o
// prefixo mudar lá e não aqui, o filtro para de valer calado; por isso o prefixo é importado, e não repetido.
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { CAMADAS_DA_ROTA, PREFIXO_DA_ROTA, linhaDaRota } from '../../supabase/functions/_shared/ai/rota-da-mensagem';

const tela = fs.readFileSync(path.join(process.cwd(), 'src', 'pages', 'AIActivityPage.tsx'), 'utf8').replace(/\r\n/g, '\n');

/** A leitura dos últimos eventos: do .from('ai_operator_audit') até o fim da consulta. */
function consultaDaAuditoria(): string {
  const ini = tela.indexOf(".from('ai_operator_audit')");
  expect(ini, 'a tela lê ai_operator_audit').toBeGreaterThan(0);
  const fim = tela.indexOf(';', ini);
  return tela.slice(ini, fim);
}

describe('tela de atividade: o rastro por mensagem fica fora dos últimos eventos', () => {
  it('a consulta exclui o event_type que começa pelo prefixo da rota, antes de ordenar e de cortar em 50', () => {
    const consulta = consultaDaAuditoria();
    const filtro = `.not('event_type', 'like', '${PREFIXO_DA_ROTA}%')`;
    expect(consulta).toContain(filtro);
    expect(consulta.indexOf(filtro)).toBeLessThan(consulta.indexOf(".order('created_at', { ascending: false })"));
    expect(consulta.indexOf(filtro)).toBeLessThan(consulta.indexOf('.limit(50)'));
    // a tela só lê a auditoria neste ponto: não há outra lista por onde a rota entraria
    expect(tela.split(".from('ai_operator_audit')").length - 1).toBe(1);
  });

  it('toda rota gravada começa pelo prefixo que a tela exclui', () => {
    expect(PREFIXO_DA_ROTA).toBe('rota:');
    for (const camada of CAMADAS_DA_ROTA) {
      const { event_type } = linhaDaRota({ sessionId: null, mensagemId: null, canal: 'whatsapp', camada });
      expect(event_type.startsWith(PREFIXO_DA_ROTA), camada).toBe(true);
    }
  });
});
