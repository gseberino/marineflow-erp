// Roda os testes SQL da Agenda de Produção na bancada PGlite (scripts/bancada-agenda/bancada.mjs).
// Nada vai para produção; não lê .env nem credencial.
//
//   node scripts/bancada-agenda/rodar.mjs                         # todas as migrations do worktree
//   node scripts/bancada-agenda/rodar.mjs --ate 20261024160200    # corta na migration do pacote
//
// Sobe a bancada (snapshot + migrations duas vezes + fixture-2310.sql), passa o JSON de paridade dos feriados em
// agenda_teste.feriados e as fixtures que os testes executam por dentro como texto (FIXTURES_COMO_TEXTO: o estado
// pós-rodada da Fase 1 e os cenários da Fase 2, cada um no seu agenda_teste.<nome>), e roda, cada um no seu
// begin/rollback:
//   · supabase/tests/agenda_*.sql cuja linha "-- bancada: depende de <versão>" cabe no corte;
//   · supabase/tests/purchase_needs_*.sql (a Fase 0 de compras continua passando).
// Uma linha com ok = false, resultado <> 'PASS' ou detalhe "PULADO" reprova (na bancada nada pode ser pulado).
// Sai com código 1 se algo falhar.

import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { criarBancada, ler, RAIZ, TESTES } from './bancada.mjs';

function argumento(nome) {
  const i = process.argv.indexOf(nome);
  return i > 0 ? process.argv[i + 1] : undefined;
}
const ate = argumento('--ate');
if (ate !== undefined && !/^\d{14}$/.test(ate)) {
  console.error(`--ate espera a versão da migration (14 dígitos), veio "${ate}"`);
  process.exit(2);
}

/**
 * Fixtures que os testes executam por dentro, com `execute (select current_setting('agenda_teste.<nome>'))`, no seu
 * begin/rollback: [configuração, arquivo em scripts/bancada-agenda/]. Arquivo que ainda não existe (um cenário que o
 * pacote seguinte cria) fica de fora e é dito na saída; o teste que precisar dele quebra com o nome do que faltou.
 */
const FIXTURES_COMO_TEXTO = [
  // O estado esperado depois do *grava* do áudio R01 (Fase 1, P5): o teste do rascunho roda o R01 e compara.
  ['agenda_teste.pos_rodada', 'fixture-2310-pos-rodada.sql'],
  // Fase 2 (P2): a carteira até qua 28/10 com as respostas do dono, o cenário do motor à mão e o replay da OS-00104.
  ['agenda_teste.fase2', 'fixture-fase2.sql'],
  ['agenda_teste.cenario_motor', 'cenario-motor.sql'],
  ['agenda_teste.replay_0104', 'fixture-replay-0104.sql'],
  // Fase 2 (P2): a migration da prontidão da Fase 1, para o teste do motor conferir que a cópia de os_prontidao só
  // muda nos pontos "-- FASE 2:".
  ['agenda_teste.mig_prontidao_fase1', '../../supabase/migrations/20261024160400_agenda_fase1_prontidao.sql'],
];

/** Testes sem a linha "bancada: depende de": de qual migration eles precisam. */
const DEPENDENCIA_CONHECIDA = {
  'purchase_needs_reserva_e_a_caminho.sql': '20261024150200',
  'purchase_needs_parity.sql': '00000000000000',
};

let falhas = 0;
const linha = (ok, texto) => {
  if (!ok) falhas++;
  console.log(`${ok ? 'ok    ' : 'FALHOU'} ${texto}`);
};

function testesDoCorte() {
  return readdirSync(TESTES)
    .filter((f) => /^(agenda_.+|purchase_needs_.+)\.sql$/.test(f))
    .sort()
    .map((f) => {
      const cabeca = /^-- bancada: depende de (\d{14})\s*$/m.exec(ler(join(TESTES, f)));
      const depende = cabeca?.[1] ?? DEPENDENCIA_CONHECIDA[f];
      if (!depende) throw new Error(`${f} não diz de qual migration depende ("-- bancada: depende de <versão>")`);
      return { arquivo: f, depende };
    });
}

async function rodarTeste(db, arquivo) {
  let resultados;
  try {
    resultados = await db.exec(ler(join(TESTES, arquivo)));
  } catch (e) {
    await db.exec('rollback').catch(() => {});
    linha(false, `${arquivo} quebrou: ${String(e.message).split('\n')[0]}`);
    return;
  }
  const rows = resultados.filter((r) => r.fields?.length).at(-1)?.rows ?? [];
  if (!rows.length) {
    linha(false, `${arquivo}: a tabela final veio vazia`);
    return;
  }
  let boas = 0;
  for (const r of rows) {
    const pulado = typeof r.detalhe === 'string' && r.detalhe.startsWith('PULADO');
    const ok = 'ok' in r ? r.ok === true && !pulado : r.resultado === 'PASS';
    if (ok) boas++;
    const nome = r.teste ?? r.caso ?? r.nome ?? JSON.stringify(r);
    if (!ok) linha(false, `  ${arquivo} · ${nome}${r.detalhe ? ` — ${r.detalhe}` : ''}`);
  }
  linha(boas === rows.length, `${arquivo}: ${boas}/${rows.length}`);
}

const { db, migrations } = await criarBancada({ ate, fixture: true, log: linha });
console.log(`bancada até ${ate ?? migrations.at(-1)?.slice(0, 14)} (${migrations.length} migrations, duas vezes cada)\n`);

const feriados = ler(join(RAIZ, 'supabase', 'tests', 'agenda', 'feriados_2026_2035.json'));
await db.query(`select set_config('agenda_teste.feriados', $1, false)`, [feriados]);
for (const [nome, arquivo] of FIXTURES_COMO_TEXTO) {
  const caminho = join(RAIZ, 'scripts', 'bancada-agenda', arquivo);
  if (!existsSync(caminho)) {
    console.log(`       ${nome}: ${arquivo} ainda não existe`);
    continue;
  }
  await db.query(`select set_config($1, $2, false)`, [nome, ler(caminho)]);
}

for (const { arquivo, depende } of testesDoCorte()) {
  if (ate && depende > ate) {
    console.log(`       ${arquivo}: fora do corte (depende de ${depende})`);
    continue;
  }
  await rodarTeste(db, arquivo);
}
await db.close();

console.log(falhas ? `\n${falhas} falha(s)` : '\ntudo ok');
process.exit(falhas ? 1 : 0);
