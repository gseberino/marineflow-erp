// A lista de ações da auditoria vive em dois lugares — e eles têm que dizer a mesma coisa.
//
// `audit_log.action` tem um CHECK de LISTA FECHADA no banco. Quando uma funcionalidade
// nova audita algo com um nome que não está lá, o insert vira erro 23514 e a linha
// simplesmente não entra. Não é hipótese: até 24/09/2026 seis ações eram recusadas em
// produção — `import_xml`, `confirm_import`, `revert_import`, `whatsapp_preview`,
// `whatsapp_send_open` e `whatsapp_unread_reminder_enqueued` — todas com ZERO linhas
// gravadas, e nenhum aviso em lugar nenhum, porque o `writeAuditLog` não olhava o erro.
//
// A marca do problema estava no próprio código: `action: 'confirm_import' as any`. O
// `as any` calava o TypeScript, e o banco recusava mesmo assim.
//
// Esta varredura compara três coisas:
//   1. o CHECK da migration MAIS RECENTE que o define (a que está de fato no banco),
//   2. o tipo `AuditAction` do frontend,
//   3. o que o código realmente escreve, no frontend e nas edge functions.
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

const RAIZ = process.cwd();

/** As ações permitidas, lidas da migration mais recente que redefine o CHECK. */
function acoesDoBanco(): string[] {
  const pasta = path.join(RAIZ, 'supabase', 'migrations');
  const candidatas = fs.readdirSync(pasta)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .filter((f) => /audit_log_action_check/i.test(fs.readFileSync(path.join(pasta, f), 'utf8')));
  expect(candidatas.length, 'nenhuma migration define audit_log_action_check').toBeGreaterThan(0);

  const sql = fs.readFileSync(path.join(pasta, candidatas[candidatas.length - 1]), 'utf8');
  // Só o ADD CONSTRAINT interessa: o DROP acima dele cita o mesmo nome.
  const add = sql.slice(sql.search(/ADD\s+CONSTRAINT\s+audit_log_action_check/i));
  const lista = add.slice(add.indexOf('ARRAY['), add.indexOf(']'));
  const acoes = [...lista.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
  expect(acoes.length, 'não consegui ler a lista do CHECK').toBeGreaterThan(5);
  return acoes;
}

/** As ações que o tipo do frontend declara. */
function acoesDoTipo(): string[] {
  const s = fs.readFileSync(path.join(RAIZ, 'src/hooks/use-audit-log.ts'), 'utf8');
  const bloco = s.slice(s.indexOf('export type AuditAction'), s.indexOf(';', s.indexOf('export type AuditAction')));
  return [...bloco.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
}

/**
 * As ações que o código de fato grava.
 *
 * Procura o `action:` dentro de uma chamada de `writeAuditLog` ou de um insert em
 * `audit_log` — não todo `action:` do sistema, que também aparece em log de erro e em
 * chamada de edge function.
 */
function acoesEscritas(): Array<{ acao: string; onde: string }> {
  const achados: Array<{ acao: string; onde: string }> = [];
  const anda = (dir: string) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { anda(p); continue; }
      if (!/\.tsx?$/.test(e.name) || /\.test\./.test(e.name)) continue;
      const s = fs.readFileSync(p, 'utf8');
      const gatilho = /writeAuditLog\(|from\(\s*["']audit_log["']\s*\)/g;
      for (const m of s.matchAll(gatilho)) {
        // A chamada cabe folgadamente nos 700 caracteres seguintes ao gatilho.
        const trecho = s.slice(m.index!, m.index! + 700);
        const a = /\baction:\s*["']([a-z_]+)["']/.exec(trecho);
        if (!a) continue;
        achados.push({
          acao: a[1],
          onde: `${path.relative(RAIZ, p)}:${s.slice(0, m.index).split('\n').length}`,
        });
      }
    }
  };
  for (const pasta of ['src', 'supabase/functions']) {
    const d = path.join(RAIZ, pasta);
    if (fs.existsSync(d)) anda(d);
  }
  return achados;
}

describe('ações da auditoria', () => {
  const doBanco = acoesDoBanco();
  const doTipo = acoesDoTipo();
  const escritas = acoesEscritas();

  it('o tipo do frontend declara exatamente o que o banco aceita', () => {
    expect([...doTipo].sort(), 'AuditAction e o CHECK divergiram — ajuste os dois juntos')
      .toEqual([...doBanco].sort());
  });

  it('toda ação que o código grava está na lista do banco', () => {
    const forade = escritas.filter((e) => !doBanco.includes(e.acao));
    const lista = forade.map((e) => `  ${e.onde} grava "${e.acao}"`).join('\n');
    expect(forade, `Ação de auditoria que o CHECK recusa (a linha NÃO será gravada):\n${lista}\n\n` +
      'Acrescente a ação ao CHECK numa migration nova E ao tipo AuditAction. Sem a\n' +
      'migration, o insert falha com 23514 e o rastro se perde em silêncio.').toEqual([]);
  });

  it('achei as chamadas de verdade (a varredura não ficou cega)', () => {
    // Se um refactor renomear writeAuditLog, este teste cai junto em vez de passar vazio.
    expect(escritas.length).toBeGreaterThanOrEqual(8);
    expect(new Set(escritas.map((e) => e.acao)).size).toBeGreaterThanOrEqual(5);
  });
});
