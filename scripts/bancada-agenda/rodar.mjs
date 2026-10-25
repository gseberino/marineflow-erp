// Roda os testes SQL da Agenda de Produção na bancada PGlite (scripts/bancada-agenda/bancada.mjs).
// Nada vai para produção; não lê .env nem credencial.
//
//   node scripts/bancada-agenda/rodar.mjs                         # todas as migrations do worktree
//   node scripts/bancada-agenda/rodar.mjs --ate 20261024160200    # corta na migration do pacote
//
// Sobe a bancada (snapshot + migrations duas vezes + fixture-2310.sql), passa o JSON de paridade dos feriados em
// agenda_teste.feriados e as fixtures que os testes executam por dentro como texto (FIXTURES_COMO_TEXTO: o estado
// pós-rodada da Fase 1 e os cenários das Fases 2 e 3, cada um no seu agenda_teste.<nome>), e roda, cada um no seu
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
  // Fase 3 (P1): a carteira da Fase 2 com a semana de 03 a 06/11 publicada, a equipe da rotina, as condições de
  // pagamento e o acerto fechado do João. (P2) as 21 conclusões reais, só números, e os casos de paridade dos recebíveis
  // com o esperado gerado pelo TS de hoje (JSON, lido pelo teste como texto).
  ['agenda_teste.fase3', 'fixture-fase3.sql'],
  ['agenda_teste.replay_conclusoes', 'fixture-replay-conclusoes.sql'],
  ['agenda_teste.recebiveis_casos', 'recebiveis-casos.json'],
  // Fase 3 (P2): a migration do motor da Fase 2, para o teste da conclusão conferir que a cópia de agenda_desfazer só muda
  // no bloco "-- FASE 3:".
  ['agenda_teste.mig_motor_fase2', '../../supabase/migrations/20261025100200_agenda_fase2_motor.sql'],
  // Fase 3 (P5): a comissão — o cenário sintético de novembro (números à mão) e o espelho de produção (as 21 OS de i04 e
  // as 56 diárias de i09, só números).
  ['agenda_teste.cenario_comissao', 'cenario-comissao.sql'],
  ['agenda_teste.cenario_comissao_2410', 'cenario-comissao-2410.sql'],
  // Fase 3 (P7b): a migration das telas, para o teste do D11 conferir que a cópia da porta só muda no bloco
  // "-- FASE 3 (P7b):"; e a migration de dado da sombra da Fase 3 (fora da bancada), que o teste dela roda numa
  // subtransação desfeita (desligado → sombra, idempotência, a semente pela regra e o DESFAZER do cabeçalho).
  ['agenda_teste.mig_telas_fase3', '../../supabase/migrations/20261026100600_agenda_fase3_telas.sql'],
  ['agenda_teste.mig_sombra_fase3', '../../supabase/migrations/20261026101000_agenda_fase3_sombra.sql'],
  // Fase 4 (P1): a carteira de sex 30/10 com os fornecedores da Fase 4 (por cima da fixture-fase3); o replay da conversa do
  // fornecedor da OS-00104 (P4); a migration da conferência e da vigia da Fase 2 (as cópias de agenda_saude e o molde da
  // fila, P5); e as dos caminhos da Fase 3 e do rascunho da Fase 2, para o B8 conferir que as cópias de
  // agenda_rascunho_gravar e _agenda_rascunho_frase só mudam nos blocos "-- FASE 4:" (a do motor da Fase 2,
  // mig_motor_fase2, já está acima: o B7 confere a de os_prontidao contra ela).
  ['agenda_teste.fase4', 'fixture-fase4.sql'],
  ['agenda_teste.replay_fornecedor_0104', 'fixture-replay-fornecedor-0104.sql'],
  ['agenda_teste.mig_conferencia_fase2', '../../supabase/migrations/20261025100300_agenda_fase2_conferencia_vigia.sql'],
  ['agenda_teste.mig_caminhos_fase3', '../../supabase/migrations/20261026100200_agenda_fase3_caminhos.sql'],
  ['agenda_teste.mig_rascunho_fase2', '../../supabase/migrations/20261025100400_agenda_fase2_rascunho.sql'],
  // Fase 4 (P2): as migrations de onde a 20261027100200 copiou os corpos — o material da Fase 1 (a conta bruta, o que o
  // dono informou, get_os_purchase_needs e a sincronização), o recebimento de 07/10 e a prontidão do P1 —, para o
  // agenda_fase4_compras.sql conferir que as cópias só mudam nos blocos "-- FASE 4:" e rodar as versões de antes (a
  // saída idêntica sem vínculo e sem linha do dono; a conta a pagar do recebimento igual à de hoje).
  ['agenda_teste.mig_material_fase1', '../../supabase/migrations/20261024160300_agenda_fase1_material.sql'],
  ['agenda_teste.mig_receive_po', '../../supabase/migrations/20261007160000_receive_po_confere_a_oc.sql'],
  ['agenda_teste.mig_fornecedores_fase4', '../../supabase/migrations/20261027100100_agenda_fase4_fornecedores.sql'],
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
