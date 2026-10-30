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
  // Fase 4 (P3): as migrations de onde a 20261027100300 copiou agenda_rascunho_material e _agenda_aplicar_material (o
  // rascunho da Fase 1) e agenda_carona e _agenda_mudancas (o acompanhamento da Fase 3), para o N9 conferir que as cópias
  // só acrescentam os blocos "-- FASE 4:" (_agenda_rascunho_frase e agenda_rascunho_gravar: contra mig_fornecedores_fase4).
  ['agenda_teste.mig_rascunho_fase1', '../../supabase/migrations/20261024160600_agenda_fase1_rascunho.sql'],
  ['agenda_teste.mig_acompanhamento_fase3', '../../supabase/migrations/20261026100500_agenda_fase3_acompanhamento.sql'],
  // Fase 4 (P4): as migrations de onde a 20261027100400 copiou agenda_desfazer (a equipe e as diárias da Fase 3, a mais
  // nova) e o gatilho do original da previsão (as tabelas da Fase 4), para o D8 conferir que as cópias só acrescentam os
  // blocos "-- FASE 4:" (_agenda_vigia_limpeza e _agenda_vigia_chegou: contra mig_conferencia_fase2, acima).
  ['agenda_teste.mig_equipe_fase3', '../../supabase/migrations/20261026100300_agenda_fase3_equipe_diarias.sql'],
  ['agenda_teste.mig_tabelas_fase4', '../../supabase/migrations/20261027100000_agenda_fase4_tabelas.sql'],
  // Fase 4 (C1 da revisão): o calendário da Fase 1, de onde a 20261027100400 copiou _agenda_data_um (o D8 confere que a
  // cópia só acrescenta os blocos "-- FASE 4:").
  ['agenda_teste.mig_calendario_fase1', '../../supabase/migrations/20261024160100_agenda_fase1_calendario.sql'],
  // Fase 4 (P6): as migrations de dado da Fase 4 (fora da bancada), que os testes delas rodam numa subtransação desfeita (a
  // sombra: desligado → sombra, o original herdado, idempotência e o DESFAZER; o acento das cidades: só a lista fechada e o
  // DESFAZER). A cópia de agenda_ver (L6) confere contra mig_acompanhamento_fase3, acima.
  ['agenda_teste.mig_sombra_fase4', '../../supabase/migrations/20261027101000_agenda_fase4_sombra.sql'],
  ['agenda_teste.mig_acento_fase4', '../../supabase/migrations/20261027102000_fornecedores_cidade_com_acento.sql'],
  // Fase 5 (P1): a carteira de sex 30/10 com os clientes e a conversa (por cima da fixture-fase4) e as migrations de onde a
  // Fase 5 copia os corpos que recria (spec-fase5 §5.7), para os testes de cada pacote conferirem que as cópias só mudam nos
  // blocos "-- FASE 5:": a confirmação do agendamento de 30/09 e a de 12/10 (D9, P2), a vigia do fornecedor
  // (agenda_saude, P3), o detector (agenda_desfazer, P4), as leituras da Fase 4 (agenda_ver, P5) e as notas e o Pix
  // (_agenda_rascunho_frase, P5). As outras fontes da §5.7 já estão acima: mig_equipe_fase3 (agenda_decidir),
  // mig_acompanhamento_fase3 (_agenda_linhas_do_fechamento), mig_rascunho_fase2 (agenda_rascunho_planejar e
  // _agenda_aplicar_planejar) e mig_telas_fase3 (os_plano_da_os).
  ['agenda_teste.fase5', 'fixture-fase5.sql'],
  ['agenda_teste.mig_confirmacao', '../../supabase/migrations/20260930130000_confirmacao_do_agendamento.sql'],
  ['agenda_teste.mig_confirmacao_1012', '../../supabase/migrations/20261012101000_numero_da_os_sem_prefixo_repetido.sql'],
  ['agenda_teste.mig_vigia_fornecedor_fase4', '../../supabase/migrations/20261027100500_agenda_fase4_vigia_fornecedor.sql'],
  ['agenda_teste.mig_detector_fase4', '../../supabase/migrations/20261027100400_agenda_fase4_detector.sql'],
  ['agenda_teste.mig_leituras_fase4', '../../supabase/migrations/20261027100600_agenda_fase4_leituras.sql'],
  ['agenda_teste.mig_notas_pix_fase4', '../../supabase/migrations/20261027100300_agenda_fase4_notas_pix.sql'],
  // Fase 5 (P6): a migration de dado (modo_cliente em sombra), que a bancada não aplica (FORA_DA_BANCADA): o
  // agenda_fase5_sombra.sql a roda como texto numa subtransação (e o DESFAZER do cabeçalho dela).
  ['agenda_teste.mig_sombra_fase5', '../../supabase/migrations/20261028101000_agenda_fase5_sombra.sql'],
  // Correção C1 da Fase 5: as migrations de onde a 20261028100700 copia os corpos que recria (o envio, a rodada e a
  // resposta), para o C1z (agenda_fase5_correcao_resposta.sql) conferir que as cópias só mudam nos blocos
  // "-- CORREÇÃO FASE 5:".
  ['agenda_teste.mig_envio_fase5', '../../supabase/migrations/20261028100200_agenda_fase5_envio.sql'],
  ['agenda_teste.mig_rodada_fase5', '../../supabase/migrations/20261028100300_agenda_fase5_rodada.sql'],
  ['agenda_teste.mig_respostas_fase5', '../../supabase/migrations/20261028100400_agenda_fase5_respostas.sql'],
  // Correção C2 da Fase 5: as outras migrations de onde a 20261028100800 copia os corpos (os textos, as leituras, a tela e a
  // própria C1), para o C2z (agenda_fase5_correcao_rodada.sql) conferir que as cópias só mudam nos blocos
  // "-- CORREÇÃO FASE 5:" (e guardam os da C1). O envio e a rodada já estão acima.
  ['agenda_teste.mig_textos_fase5', '../../supabase/migrations/20261028100100_agenda_fase5_textos.sql'],
  ['agenda_teste.mig_leituras_fase5', '../../supabase/migrations/20261028100500_agenda_fase5_leituras.sql'],
  ['agenda_teste.mig_telas_fase5', '../../supabase/migrations/20261028100600_agenda_fase5_telas.sql'],
  ['agenda_teste.mig_correcao_resposta_fase5', '../../supabase/migrations/20261028100700_agenda_fase5_correcao_resposta.sql'],
  // Fase 6 (P1): a história de 07/09 a 29/10 que o aprendizado mede (14 OS concluídas com os dias ditos, o plano conferido, as
  // diárias ligadas, a 1ª promessa e os avisos de atraso; por cima da fixture-fase5). Os pacotes seguintes acrescentam aqui as
  // migrations de onde copiam os corpos que recriam (spec-fase6 §5.9) como mig_*_fase6, para as conferências das cópias (o
  // C2z e o C1z tiram os blocos "-- FASE 6:"); as que já estão acima não se repetem.
  ['agenda_teste.fase6', 'fixture-fase6.sql'],
  // Fase 6 (P2): a fonte de _agenda_aprendizado_texto (a 20261029100100 do P1), para o O6 de agenda_fase6_os.sql conferir a
  // cópia; as de os_duracao_sugerida/os_presenca_do_dono (mig_prontidao_fase1) e de _agenda_vigia_estouro
  // (mig_conferencia_fase2) já estão acima.
  ['agenda_teste.mig_medicao_fase6', '../../supabase/migrations/20261029100100_agenda_fase6_medicao.sql'],
  // Fase 6 (P3): as fontes do que agenda_fase6_fornecedor.sql confere — os_prontidao de 20261027100200 (a cópia e a definição
  // de antes rodada como pg_temp, para o byte a byte em teste) e _agenda_aprendizado_texto de 20261029100200 (o P2); a própria
  // 20261029100300, para provar que nada nela escreve mensagem a terceiros. _agenda_prazo_do_fornecedor (mig_fornecedores_fase4)
  // e _agenda_compras_da_os/_agenda_ver_compras (mig_leituras_fase4) já estão acima.
  ['agenda_teste.mig_compras_fase4', '../../supabase/migrations/20261027100200_agenda_fase4_compras.sql'],
  ['agenda_teste.mig_os_fase6', '../../supabase/migrations/20261029100200_agenda_fase6_os.sql'],
  ['agenda_teste.mig_fornecedor_fase6', '../../supabase/migrations/20261029100300_agenda_fase6_fornecedor.sql'],
  // Fase 6 (P5): as fontes do que agenda_fase6_cliente.sql confere — _agenda_cliente_risco de 20261028100800 (a cópia e a
  // definição de antes rodada no lugar, para o byte a byte em teste), _agenda_aprendizado_texto de 20261029100400 (o P4) e a
  // própria 20261029100500 (o preenchimento da 1ª promessa rodado de novo, e nada nela escreve mensagem a terceiros).
  // _agenda_cliente_gravar_prometido (mig_textos_fase5) já está acima.
  ['agenda_teste.mig_correcao_rodada_fase5', '../../supabase/migrations/20261028100800_agenda_fase5_correcao_rodada.sql'],
  ['agenda_teste.mig_dono_fase6', '../../supabase/migrations/20261029100400_agenda_fase6_dono.sql'],
  ['agenda_teste.mig_cliente_fase6', '../../supabase/migrations/20261029100500_agenda_fase6_cliente.sql'],
  // Fase 6 (P8): a migration de dado 20261029101000 (o aprendizado em sombra), que a bancada não aplica (FORA_DA_BANCADA):
  // agenda_fase6_sombra.sql a roda numa subtransação desfeita. As fontes das 3 recriadas da 20261029100800 já estão acima
  // (agenda_ver: mig_leituras_fase5; os_plano_da_os: mig_telas_fase5; _agenda_ver_fornecedores: mig_leituras_fase4).
  ['agenda_teste.mig_sombra_fase6', '../../supabase/migrations/20261029101000_agenda_fase6_sombra.sql'],
  // Pós-merge (C): as fontes das 5 recriadas da 20261029110000 — a porta (20261026100700) e o agrupar/desagrupar de OS
  // (20261028120000) —, para o agenda_posmerge_agrupar.sql conferir que as cópias só mudam nos blocos "-- PÓS-MERGE: (C)".
  ['agenda_teste.mig_levantamento_fase3', '../../supabase/migrations/20261026100700_agenda_fase3_levantamento_na_porta.sql'],
  ['agenda_teste.mig_agrupar_os', '../../supabase/migrations/20261028120000_agrupar_os.sql'],
  // (e a do "Fechar juntas", 20261028190000: a mais nova de _os_impedimento_para_agrupar)
  ['agenda_teste.mig_fechar_juntas', '../../supabase/migrations/20261028190000_fechar_juntas_f0.sql'],
  // Correção de 29/10 (P1): as fontes das 3 recriadas da 20261030100000 — as leituras da Fase 1 (_agenda_semana_de e
  // agenda_semana, também rodadas como pg_temp: a régua do que não muda) e as da Fase 2 (_agenda_ver_plano) —, para o
  // agenda_correcao_2910_p1.sql conferir que as cópias só acrescentam os blocos "-- CORREÇÃO 29/10 (P1):".
  ['agenda_teste.mig_leituras_fase1', '../../supabase/migrations/20261024160500_agenda_fase1_leituras.sql'],
  ['agenda_teste.mig_leituras_fase2', '../../supabase/migrations/20261025100500_agenda_fase2_leituras.sql'],
  // Correção de 29/10 (P2): a fonte de agenda_ver recriada na 20261030100100 (as leituras da Fase 6, a mais nova), para o
  // agenda_correcao_2910_p2.sql conferir que a cópia só acrescenta os blocos "-- CORREÇÃO 29/10 (P2):" e rodar a definição
  // de antes como pg_temp (fora de ligado, byte a byte). A de agenda_simular (mig_leituras_fase1) já está acima.
  ['agenda_teste.mig_leituras_fase6', '../../supabase/migrations/20261029100800_agenda_fase6_leituras.sql'],
  // Correção de 29/10 (P3): a fonte de agenda_propor recriada na 20261030100200 (a correção C1 da Fase 6, a mais nova), para o
  // agenda_correcao_2910_p3.sql conferir que a cópia só acrescenta os blocos "-- CORREÇÃO 29/10 (P3):" e rodar a definição de
  // antes como pg_temp (sem reserva, byte a byte). As de _agenda_encaixar (mig_motor_fase2), _agenda_vigia_limpeza
  // (mig_detector_fase4) e _agenda_vigia_padrao_do_dono (mig_conferencia_fase2) já estão acima.
  ['agenda_teste.mig_correcao_calculo_fase6', '../../supabase/migrations/20261029100900_agenda_fase6_correcao_calculo.sql'],
  // Correção de 29/10 (P4): a fonte do gatilho _agenda_acoes_so_desfaz recriado na 20261030100300 (as tabelas da Fase 3, a mais
  // nova), para o agenda_correcao_2910_p4.sql conferir que a cópia só acrescenta o bloco "-- CORREÇÃO 29/10 (P4):".
  ['agenda_teste.mig_tabelas_fase3', '../../supabase/migrations/20261026100000_agenda_fase3_tabelas.sql'],
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
