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
  // Correção de 29/10 (revisão do lote): as fontes das 9 recriadas da 20261030100500, para o agenda_correcao_2910_revisao.sql
  // conferir que as cópias só mudam nos blocos "-- CORREÇÃO 29/10 (revisão):" e rodar as definições de antes como pg_temp:
  // _agenda_mudancas (a correção de textos da Fase 6), agenda_livre_de_verdade e agenda_simular (P2), _agenda_modo_da_pergunta
  // e _agenda_vigia_limpeza (P3), agenda_aviso_pecas e agenda_aviso_enfileirar (P4) e agenda_vigiar (P5). A de
  // _agenda_linhas_do_fechamento (mig_leituras_fase5) já está acima.
  ['agenda_teste.mig_correcao_textos_fase6', '../../supabase/migrations/20261029100950_agenda_fase6_correcao_textos.sql'],
  ['agenda_teste.mig_correcao_livre', '../../supabase/migrations/20261030100100_agenda_correcao_livre.sql'],
  ['agenda_teste.mig_correcao_motor', '../../supabase/migrations/20261030100200_agenda_correcao_motor.sql'],
  ['agenda_teste.mig_correcao_aviso', '../../supabase/migrations/20261030100300_agenda_correcao_aviso.sql'],
  ['agenda_teste.mig_correcao_desempenho', '../../supabase/migrations/20261030100400_agenda_correcao_desempenho.sql'],
  // Correção de 30/10 (equipe): a fonte de _agenda_vigia_equipe_sem_dias recriado na 20261030100600 (a revisão do lote, a
  // única) e de _agenda_equipe_tem_dias (que não muda), para o agenda_correcao_2910_equipe.sql conferir que a cópia só muda
  // nos blocos "-- CORREÇÃO 30/10 (equipe):" e rodar a definição de antes como pg_temp. As das 3 leituras da Fase 1
  // (agenda_capacidade, agenda_capacidade_semanal e agenda_resolver_pessoa) são a mig_prontidao_fase1, já acima.
  ['agenda_teste.mig_correcao_revisao', '../../supabase/migrations/20261030100500_agenda_correcao_revisao.sql'],
  // Fase 7a (P1): a carteira REAL de qui 29/10 16:52 (gerada por gerar-replay-2910.mjs do SELECT de produção: as 11 OS, os 9
  // orçamentos grandes, a equipe pela semente, as 12 reservas do Lenine, as 3 perguntas e a config de produção; tira o mundo
  // sintético de 23/10 antes) e a sintética por cima dela (o rastro, a dupla dita, o deslocamento, o prometido firme, o sinal
  // não pago, as 3 OS do mesmo diarista, a ficha enfileirada e, com agenda_teste.fase7a_sabado = 'on', o sábado do Roberto).
  // Os pacotes seguintes acrescentam aqui as migrations de onde copiam os corpos que recriam (spec-fase7a §5.14) como
  // mig_*_fase7a; as que já estão acima não se repetem (a de _agenda_perguntas_antes, recriada no P1, é a mig_tabelas_fase3).
  ['agenda_teste.replay2910', 'fixture-replay-2910.sql'],
  ['agenda_teste.fase7a', 'fixture-fase7a.sql'],
  // Fase 7a (P7): as fontes de 2 das 6 recriadas da 20261031100600 que ainda não estavam acima — agenda_desfazer (a rodada da
  // Fase 6) e _agenda_ver_plano (o P1 do lote) —, a própria 20261031100600 (o R8 confere o comando do job agenda-gestor pelo
  // texto: a bancada não tem pg_cron; o R9, as cópias) e a migration de dado 20261031100990 (os 5 modos em sombra; FORA_DA_BANCADA:
  // o agenda_fase7a_sombra.sql a roda numa subtransação). As fontes das outras 4 já estão acima (mig_correcao_revisao,
  // mig_leituras_fase2, mig_correcao_livre e mig_correcao_textos_fase6).
  ['agenda_teste.mig_rodada_fase6', '../../supabase/migrations/20261029100600_agenda_fase6_rodada.sql'],
  ['agenda_teste.mig_correcao_leituras', '../../supabase/migrations/20261030100000_agenda_correcao_leituras.sql'],
  ['agenda_teste.mig_rodada_fase7a', '../../supabase/migrations/20261031100600_agenda_fase7a_rodada.sql'],
  ['agenda_teste.mig_sombra_fase7a', '../../supabase/migrations/20261031100990_agenda_fase7a_sombra.sql'],
  // Fase 7a (P8): as fontes de 2 das 5 recriadas da 20261031100700 que ainda não estavam acima — agenda_propor (o 7a P3) e
  // _agenda_gestor_decidir (o 7a P4) —, para o E6 de agenda_fase7a_encaixe.sql conferir que as cópias só acrescentam os blocos
  // "-- FASE 7: (7a P8" e rodar o motor de antes como pg_temp (o portão falso, byte a byte). As de _agenda_criticidade
  // (mig_motor_fase2), _agenda_criticidade_da_acao e _agenda_propor_e_aplicar (mig_conferencia_fase2) já estão acima.
  ['agenda_teste.mig_prontidao_fase7a', '../../supabase/migrations/20261031100200_agenda_fase7a_prontidao.sql'],
  ['agenda_teste.mig_perguntas_fase7a', '../../supabase/migrations/20261031100300_agenda_fase7a_perguntas.sql'],
  // Fase 7a (P9): a fonte de 1 das 4 recriadas da 20261031100750 que ainda não estava acima — _agenda_gestor_decidir (o 7a P8)
  // —, para o V7 de agenda_fase7a_revisao.sql conferir que as cópias só acrescentam os blocos "-- FASE 7: (7a P9". As de
  // agenda_replanejar (mig_conferencia_fase2), agenda_aplicar (mig_correcao_calculo_fase6) e _agenda_gestor_sombra
  // (mig_rodada_fase7a) já estão acima.
  ['agenda_teste.mig_encaixe_fase7a', '../../supabase/migrations/20261031100700_agenda_fase7a_encaixe.sql'],
  // Fase 7a (P11): as fontes de 2 das 7 recriadas da 20261031100850 que ainda não estavam acima — _agenda_gestor_decidir (o 7a
  // P9) e _agenda_modo_da_pergunta (o 7a P1) —, para o P4 de agenda_fase7a_protecoes.sql conferir que as cópias só acrescentam
  // os blocos "-- FASE 7: (7a P11" e o P5 rodar as de antes como pg_temp. As de _agenda_cliente_registrar
  // (mig_correcao_calculo_fase6), das 3 rotinas da equipe (mig_equipe_fase3) e de _agenda_linhas_do_fechamento
  // (mig_rodada_fase7a) já estão acima.
  ['agenda_teste.mig_revisao_fase7a', '../../supabase/migrations/20261031100750_agenda_fase7a_revisao.sql'],
  ['agenda_teste.mig_base_fase7a', '../../supabase/migrations/20261031100000_agenda_fase7a_base.sql'],
  // Fase 7a (P12): as fontes de 2 das 3 recriadas da 20261031100900 que ainda não estavam acima — _agenda_gestor_decidir (o 7a
  // P11) e _agenda_validar_itens (o 7a P5) —, para o S4 de agenda_fase7a_sinal_sabado.sql conferir que as cópias só acrescentam
  // os blocos "-- FASE 7: (7a P12" e o S5 rodar as de antes como pg_temp. A de _agenda_classe_da_os (mig_prontidao_fase7a) já
  // está acima.
  ['agenda_teste.mig_protecoes_fase7a', '../../supabase/migrations/20261031100850_agenda_fase7a_protecoes.sql'],
  ['agenda_teste.mig_teto_fase7a', '../../supabase/migrations/20261031100400_agenda_fase7a_teto.sql'],
  // Fase 7a (P13): a própria migration do bem (ela não recria nada), para o O3 de agenda_fase7a_bem.sql conferir pelo texto que
  // ela só cria o passo _agenda_gestor_bem.
  ['agenda_teste.mig_bem_fase7a', '../../supabase/migrations/20261031100950_agenda_fase7a_bem.sql'],
  // Fase 7a (correção da revisão): a própria migration da correção (20261031100980), para o Z9 de agenda_fase77a_correcao.sql conferir
  // pelo texto o job nos minutos ímpares e as funções de antes da 7a que ela recria (sem os blocos da Fase 7, o corpo de antes).
  ['agenda_teste.mig_correcao_fase7a', '../../supabase/migrations/20261031100980_agenda_fase77a_correcao.sql'],
  // Fase 7a (correção 2 da revisão): a própria migration da correção 2 (20261031100985), para o Y14 de agenda_fase77a_correcao2.sql
  // conferir pelo texto que as funções de antes da 7a que ela recria levam a mudança marcada (sem os blocos da Fase 7, o corpo de
  // antes). As fontes de antes da 7a já estão acima (mig_motor_fase2, mig_equipe_fase3, mig_correcao_revisao, mig_leituras_fase1) e o
  // Y13 roda a de 20261030100300 (mig_correcao_aviso) como pg_temp.
  ['agenda_teste.mig_correcao2_fase7a', '../../supabase/migrations/20261031100985_agenda_fase77a_correcao2.sql'],
  // Fase 7b (P1): a equipe de verdade de 30/10 (Roberto, João e Mickael fora; o Alex declarado pelo dono, sem telefone; a reserva do
  // Lenine solta; a pergunta dos dias do dono do lote aberta) e as pessoas da etapa (Mateus sob demanda sem perfil, Rafael diarista
  // com padrão e na rotina, Bruno o novato com uma data dita; o dono com a linha seg–sex só com agenda_teste.fase7b_dono = 'campo'),
  // por cima do replay de 29/10 e da sintética da 7a; e a própria migration da base da 7b (20261101100000), de onde os pacotes
  // seguintes conferem a cópia de _agenda_modo_da_pergunta (a fonte dela, a 20261031100850, já está acima: mig_protecoes_fase7a).
  // As fontes da tabela de cópias da 7b (spec-fase7b §R4.6) que ainda não estavam acima: a correção da equipe de 30/10
  // (agenda_capacidade e agenda_capacidade_semanal, P2), o 7a P10 (agenda_rascunho_gravar, P2; agenda_gestor_rodar, P6) e o 7a P12
  // (_agenda_validar_itens e _agenda_gestor_sabado, P4). As outras fontes da §R4.6 já estão acima (mig_rascunho_fase1,
  // mig_leituras_fase5, mig_equipe_fase3, mig_perguntas_fase7a, mig_rodada_fase7a, mig_acompanhamento_fase3, mig_correcao2_fase7a,
  // mig_correcao_fase7a, mig_dono_fase6, mig_teto_fase7a, mig_motor_fase2, mig_encaixe_fase7a, mig_correcao_textos_fase6,
  // mig_base_fase7a, mig_protecoes_fase7a). Os pacotes seguintes acrescentam aqui as migrations da própria 7b (mig_*_fase7b) quando
  // um teste precisar delas como texto.
  ['agenda_teste.fase7b', 'fixture-fase7b.sql'],
  ['agenda_teste.mig_tabelas_fase7b', '../../supabase/migrations/20261101100000_agenda_fase7b_tabelas.sql'],
  ['agenda_teste.mig_correcao_equipe', '../../supabase/migrations/20261030100600_agenda_correcao_equipe.sql'],
  ['agenda_teste.mig_compras_fase7a', '../../supabase/migrations/20261031100800_agenda_fase7a_compras.sql'],
  ['agenda_teste.mig_sinal_sabado_fase7a', '../../supabase/migrations/20261031100900_agenda_fase7a_sinal_sabado.sql'],
  // Fase 7b (P5): a migration de dado 20261101100900 (os 5 modos da 7b em sombra e, no DESFAZER, a dupla dita no início ou no fim
  // que passa a "o tempo todo"; FORA_DA_BANCADA: o agenda_fase7b_sombra.sql a roda numa subtransação). As fontes das 2 recriadas da
  // 20261101100400 já estão acima: os_plano_da_os (mig_correcao_textos_fase6) e agenda_saude (mig_rodada_fase7a).
  ['agenda_teste.mig_sombra_fase7b', '../../supabase/migrations/20261101100900_agenda_fase7b_sombra.sql'],
  // Fase 7b (P6): a fonte de 1 das 6 recriadas da 20261101100500 que ainda não estava acima — _agenda_dias_semana_motivos (o 7b P3) —,
  // para o C8 de agenda_fase7b_chamar.sql conferir que a cópia só acrescenta os blocos "-- FASE 7b:". As das outras 5 já estão acima:
  // agenda_gestor_rodar (mig_compras_fase7a), _agenda_gestor_dia_gravar (mig_base_fase7a), _agenda_ver_gestor (mig_correcao2_fase7a),
  // agenda_livre_de_verdade e _agenda_gestor_corte (mig_correcao_fase7a).
  ['agenda_teste.mig_pergunta_fase7b', '../../supabase/migrations/20261101100200_agenda_fase7b_pergunta_semanal.sql'],
  // Fase 7b (correção da revisão, 20261101100800): as fontes das recriadas que ainda não estavam acima — o P2 (agenda_rascunho_disponibilidade
  // e _agenda_equipe_dias_gravar), o P4 (_agenda_carga_da_pessoa, _agenda_contexto e agenda_propor) e o P6 (_agenda_ver_gestor,
  // agenda_livre_de_verdade, _agenda_quem_chamar e _agenda_gestor_dupla) —, para o X0 de agenda_fase77b_correcao.sql conferir que as
  // cópias só acrescentam os blocos "-- FASE 7b: (correção da revisão da 7b". A do P3 (mig_pergunta_fase7b) já está acima.
  ['agenda_teste.mig_disponibilidade_fase7b', '../../supabase/migrations/20261101100100_agenda_fase7b_disponibilidade.sql'],
  ['agenda_teste.mig_motor_fase7b', '../../supabase/migrations/20261101100300_agenda_fase7b_motor.sql'],
  ['agenda_teste.mig_quem_chamar_fase7b', '../../supabase/migrations/20261101100500_agenda_fase7b_quem_chamar.sql'],
  // Fase 7b (correção 2, 20261101100850: o achado 26, da 7a): a fonte de 1 das 3 recriadas que ainda não estava acima — a correção da
  // revisão 20261101100800 (_agenda_ver_gestor) —, para o W0 de agenda_fase77b_correcao2.sql conferir que a cópia só acrescenta os
  // blocos "(correção 2, achado 26 da 7a)" e o W4 rodar a de antes como comparação. As outras 2 já estão acima: _agenda_gestor_pessoa_meios
  // (mig_motor_fase7b) e _agenda_gestor_corte (mig_quem_chamar_fase7b).
  ['agenda_teste.mig_correcao_fase7b', '../../supabase/migrations/20261101100800_agenda_fase77b_correcao.sql'],
  // Fase 7c (P1): a fixture da etapa (por cima da da 7b: as linhas reais com o sistema e o verbo do catálogo; na sintética, Roberto e
  // João de volta com o padrão deles, o padrão do Bruno, as OS 171 a 179 da §8.2; as etiquetas dos testes M e V com
  // agenda_teste.fase7c_etiquetas = 'mv'; as variantes do novato com agenda_teste.fase7c_variante); a correção 3 da 7b (20261101100860:
  // a origem de _agenda_e_novato e _agenda_tecnico_declarado, recriadas no P1) e a própria base da 7c (20261102100000), de onde os
  // pacotes seguintes conferem as cópias (_agenda_modo_da_pergunta no P8; _agenda_e_novato de quem recriar depois). A fonte de
  // _agenda_modo_da_pergunta (a 20261101100000) já está acima: mig_tabelas_fase7b. Os pacotes seguintes acrescentam aqui as
  // migrations de onde copiam (spec-fase7c §R5.4) como mig_*_fase7c / mig_*_fase7b; as que já estão acima não se repetem.
  ['agenda_teste.fase7c', 'fixture-fase7c.sql'],
  ['agenda_teste.mig_correcao3_fase7b', '../../supabase/migrations/20261101100860_agenda_fase77b_correcao3.sql'],
  ['agenda_teste.mig_base_fase7c', '../../supabase/migrations/20261102100000_agenda_fase7c_base.sql'],
  // Fase 7c (P2): a fonte de 1 das 8 recriadas da 20261102100100 que ainda não estava acima — _agenda_alocacoes_imutavel (a 20261025100000
  // da Fase 2) —, para o M14 de agenda_fase7c_motor.sql conferir que as cópias só acrescentam os blocos "-- FASE 7c:" e o M1 rodar o
  // motor de antes no lugar; e a própria migration do motor da 7c (20261102100100), de onde o P3 e o 7d P4 conferem as cópias. As fontes
  // das outras 7 já estão acima: _agenda_contexto e agenda_propor (mig_correcao_fase7b), _agenda_tentar_bloco e _agenda_encaixar
  // (mig_motor_fase7b), _agenda_so_diaristas e _agenda_alocs_do_bloco (mig_motor_fase2) e _agenda_por_que_nao (mig_teto_fase7a).
  ['agenda_teste.mig_tabelas_fase2', '../../supabase/migrations/20261025100000_agenda_fase2_tabelas.sql'],
  ['agenda_teste.mig_motor_fase7c', '../../supabase/migrations/20261102100100_agenda_fase7c_motor.sql'],
  // Fase 7c (P3): a própria migration da violação e da escada (20261102100200), de onde o V7/V9 de agenda_fase7c_violacao.sql conferem
  // que as cópias só acrescentam os blocos "-- FASE 7c:" (e a marca de dentro "-- (7c …" na escada) e o 7d P4 confere a de
  // _agenda_violacoes. As fontes das 2 recriadas já estão acima: _agenda_violacoes (mig_correcao_calculo_fase6) e _agenda_gestor_reparo
  // (mig_correcao3_fase7b).
  ['agenda_teste.mig_violacao_fase7c', '../../supabase/migrations/20261102100200_agenda_fase7c_violacao.sql'],
  // Fase 7c (P4): a própria migration da conversa (20261102100300), de onde o C6 de agenda_fase7c_conversa.sql confere que as cópias de
  // _agenda_rascunho_frase e agenda_rascunho_gravar só acrescentam o bloco "-- FASE 7c:" e o P8 copia as duas (R5.4). A fonte delas, a
  // 20261101100100 (a 7b P2), já está acima: mig_disponibilidade_fase7b.
  ['agenda_teste.mig_conversa_fase7c', '../../supabase/migrations/20261102100300_agenda_fase7c_conversa.sql'],
  // Fase 7c (P5): a própria migration da rodada (20261102100400), de onde o R9 de agenda_fase7c_rodada.sql confere que a cópia de
  // _agenda_linhas_do_fechamento só acrescenta os blocos "-- FASE 7c:" e as marcas de dentro "-- (7c …" e o P8 a copia (R5.4). A fonte
  // dela, a 20261101100860 (a correção 3 da 7b), já está acima: mig_correcao3_fase7b.
  ['agenda_teste.mig_rodada_fase7c', '../../supabase/migrations/20261102100400_agenda_fase7c_rodada.sql'],
  // Fase 7c (P6): a própria migration das leituras (20261102100500), de onde o L6 de agenda_fase7c_leituras.sql confere que as 5 recriadas
  // só acrescentam o bloco "-- FASE 7c:" e o 7d P8 copia agenda_ver (a cadeia do fase7-registro §2). As fontes delas já estão acima:
  // agenda_ver (mig_rodada_fase7a), _agenda_linha_da_semana (mig_leituras_fase2) e os 3 textos do fora (mig_correcao2_fase7a).
  ['agenda_teste.mig_leituras_fase7c', '../../supabase/migrations/20261102100500_agenda_fase7c_leituras.sql'],
  // Fase 7c (P8): a fixture das etapas (por cima da da 7c: o catálogo do roteiro, o Alex com perfil, etiqueta, telefone e rotina — sem
  // telefone com agenda_teste.fase7c_tarefas_variante = 'alex_sem_telefone' —, o Mateus ajudante, as OS 97191 a 97196 com as linhas reais
  // e os roteiros) e a própria migration das etapas (20261102100550), de onde o T18 de agenda_fase7c_tarefas.sql confere que as 9
  // recriadas só acrescentam os blocos "-- FASE 7c: (7c P8" (e o 7d P8 e o 7f P5 conferem as cópias da ficha e da resposta da equipe).
  // As fontes das 9 já estão acima: mig_base_fase7c, mig_equipe_fase3, mig_correcao_fase7b, mig_leituras_fase1, mig_leituras_fase2,
  // mig_conversa_fase7c e mig_rodada_fase7c.
  ['agenda_teste.fase7c_tarefas', 'fixture-fase7c-tarefas.sql'],
  ['agenda_teste.mig_tarefas_fase7c', '../../supabase/migrations/20261102100550_agenda_fase7c_tarefas.sql'],
  // Fase 7c (correção da revisão): a própria migration da correção (20261102100580), de onde o K0 de agenda_fase77c_correcao.sql confere
  // que as 10 recriadas só acrescentam os blocos "-- FASE 7c: (7c correção" e as marcas "-- (7c correção" (as fontes já estão acima:
  // mig_tarefas_fase7c, mig_rodada_fase7c, mig_leituras_fase7c e mig_motor_fase7c); quem recriar depois uma delas copia desta.
  ['agenda_teste.mig_correcao_fase7c', '../../supabase/migrations/20261102100580_agenda_fase77c_correcao.sql'],
  // Fase 7c (correção 2 da revisão): a própria migration da correção 2 (20261102100590), de onde o C0 de agenda_fase77c_correcao2.sql
  // confere que as 6 recriadas só acrescentam os blocos "-- FASE 7c: (7c correção 2" e as marcas "-- (7c correção 2" (as fontes já estão
  // acima: mig_correcao_fase7c, mig_tarefas_fase7c e mig_correcao_fase7b); quem recriar depois uma delas copia desta.
  ['agenda_teste.mig_correcao2_fase7c', '../../supabase/migrations/20261102100590_agenda_fase77c_correcao2.sql'],
  // Fase 7c (P7): a migration de dado 20261102100600 (os 4 modos da 7c — modo_habilidade, modo_lider, modo_habilidade_propor e
  // modo_tarefas — de desligado a sombra, e o DESFAZER do cabeçalho; FORA_DA_BANCADA: o agenda_fase7c_sombra.sql a roda numa
  // subtransação).
  ['agenda_teste.mig_sombra_fase7c', '../../supabase/migrations/20261102100600_agenda_fase7c_sombra.sql'],
  // Fase 7d (P1): a fixture da etapa (por cima da da 7c: os 5 locais, com a MP como o pátio; os cenários J, julho de 2027, e D, dezembro de
  // 2026; spec-fase7d §8.2 com o R6.10) e a própria base da 7d (20261107100000), de onde o B6j de agenda_fase7d_base.sql confere a cópia de
  // _agenda_modo_da_pergunta (a fonte dela, mig_tarefas_fase7c, já está acima).
  ['agenda_teste.fase7d', 'fixture-fase7d.sql'],
  ['agenda_teste.mig_tabelas_fase7d', '../../supabase/migrations/20261107100000_agenda_fase7d_tabelas.sql'],
  // Fase 7d (P2): a própria migration do feriado do município (20261107100100), para o F6a de agenda_fase7d_feriados.sql conferir pelo
  // texto que ela só cria as 2 funções novas. A fonte de agenda_feriado (mig_calendario_fase1, o F4b) já está acima.
  ['agenda_teste.mig_feriados_fase7d', '../../supabase/migrations/20261107100100_agenda_fase7d_feriados.sql'],
  // Fase 7d (P3): a própria migration das leituras do local (20261107100200), para o L7 de agenda_fase7d_local.sql conferir pelo texto que ela só
  // cria as 8 funções novas. A fonte de _agenda_local_da_os e _agenda_bem_da_os (mig_equipe_fase3, o L7e) já está acima.
  ['agenda_teste.mig_local_fase7d', '../../supabase/migrations/20261107100200_agenda_fase7d_local.sql'],
  // Fase 7d (P4): a própria migration do motor (20261107100300), para o M9 de agenda_fase7d_motor.sql conferir que as 11 recriadas só mudam nos
  // blocos "-- FASE 7d:". As fontes delas já estão acima: mig_motor_fase7c, mig_correcao_fase7c, mig_violacao_fase7c, mig_motor_fase7b,
  // mig_correcao2_fase7b e mig_motor_fase2.
  // A fonte de _agenda_gestor_pessoa_meios (a correção 2 da 7b) ainda não estava: o M1 roda a de antes no lugar.
  ['agenda_teste.mig_correcao2_fase7b', '../../supabase/migrations/20261101100850_agenda_fase77b_correcao2.sql'],
  ['agenda_teste.mig_motor_fase7d', '../../supabase/migrations/20261107100300_agenda_fase7d_motor.sql'],
  // Fase 7d (P5): a própria migration do combinar (20261107100400), para o C9 de agenda_fase7d_combinar.sql conferir que as recriadas só mudam nos
  // blocos "-- FASE 7d:". As fontes já estão acima: mig_correcao_fase7b, mig_correcao2_fase7c, mig_rascunho_fase2 e mig_acompanhamento_fase3.
  ['agenda_teste.mig_combinar_fase7d', '../../supabase/migrations/20261107100400_agenda_fase7d_combinar.sql'],
  // Fase 7d (P6): a própria migration do M11 (20261107100500), para o K7 de agenda_fase7d_cliente.sql conferir que as recriadas só mudam nos blocos
  // "-- FASE 7d:". As fontes já estão acima: mig_correcao_rodada_fase5, mig_envio_fase5, mig_rodada_fase5, mig_combinar_fase7d e a do acabamento, abaixo.
  // A do retorno F0a (20261105100000, fora da bancada) vai como texto: o K8 a roda dentro da transação do teste, por baixo do M11 (R6.0).
  ['agenda_teste.mig_acabamento_fase6', '../../supabase/migrations/20261029100700_agenda_fase6_acabamento.sql'],
  ['agenda_teste.mig_cliente_fase7d', '../../supabase/migrations/20261107100500_agenda_fase7d_cliente.sql'],
  ['agenda_teste.mig_retorno_f0a', '../../supabase/migrations/20261105100000_retorno_f0a_canal_bloqueado.sql'],
  // Fase 7d (P6b): a própria migration do conserto do NOVO-agenda-91 (20261107100550), para o R0 de agenda_fase7d_responder.sql conferir as 3 recriadas. As fontes já
  // estão acima: mig_rascunho_fase2 e mig_cliente_fase7d.
  ['agenda_teste.mig_responder_fase7d', '../../supabase/migrations/20261107100550_agenda_fase7d_responder.sql'],
  // Fase 7d (P7): a própria migration do rascunho (20261107100600), para o R0 de agenda_fase7d_rascunho.sql conferir as 5 recriadas. As fontes já estão acima:
  // mig_tarefas_fase7c, mig_disponibilidade_fase7b e mig_cliente_fase7d.
  ['agenda_teste.mig_rascunho_fase7d', '../../supabase/migrations/20261107100600_agenda_fase7d_rascunho.sql'],
  // Fase 7d (P8): a própria migration das leituras (20261107100700), para o V6 de agenda_fase7d_leituras.sql conferir as recriadas, com a fonte de os_plano_da_os e agenda_saude (a 7b),
  // que ainda não estava (as outras já estão acima: mig_leituras_fase7c, mig_tarefas_fase7c, mig_equipe_fase3 e mig_acabamento_fase6). E o dado 20261107100900 (a semente; FORA_DA_BANCADA:
  // o agenda_fase7d_semente.sql o roda na transação do teste).
  ['agenda_teste.mig_leituras_fase7b', '../../supabase/migrations/20261101100400_agenda_fase7b_leituras.sql'],
  ['agenda_teste.mig_leituras_fase7d', '../../supabase/migrations/20261107100700_agenda_fase7d_leituras.sql'],
  ['agenda_teste.mig_semente_fase7d', '../../supabase/migrations/20261107100900_agenda_fase7d_semente.sql'],
  // Fase 7d (correção, Onda 1): a própria migration (20261107100800), para o T0 de agenda_fase7d_correcao.sql conferir as cópias.
  ['agenda_teste.mig_correcao_fase7d', '../../supabase/migrations/20261107100800_agenda_fase7d_correcao.sql'],
  // Fase 7d (correção, Onda 2): a própria migration (20261107100850), para o T0 de agenda_fase7d_correcao2.sql conferir as cópias.
  ['agenda_teste.mig_correcao2_fase7d', '../../supabase/migrations/20261107100850_agenda_fase7d_correcao2.sql'],
  // Fase 7d (correção, Onda 3): a própria migration (20261107100860), para o T0 de agenda_fase7d_correcao3.sql conferir as cópias.
  ['agenda_teste.mig_correcao3_fase7d', '../../supabase/migrations/20261107100860_agenda_fase7d_correcao3.sql'],
  // Fase 7d (correção, Onda 4): a própria migration (20261107100870), para o T0 de agenda_fase7d_correcao4.sql conferir as cópias.
  ['agenda_teste.mig_correcao4_fase7d', '../../supabase/migrations/20261107100870_agenda_fase7d_correcao4.sql'],
  // Fase 7f (P1): a fixture da etapa (por cima da da 7d: os dois relógios de novembro, as 8 perguntas com o tamanho real, as ações, a equipe e o cliente; spec-fase7f §8.2 com
  // o R8.12-8) e a própria base da 7f (20261109100000), de onde o B4 de agenda_fase7f_base.sql roda o backfill e confere a cópia de _agenda_perguntas_antes (a fonte dela,
  // mig_base_fase7a, já está acima).
  ['agenda_teste.fase7f', 'fixture-fase7f.sql'],
  ['agenda_teste.mig_base_fase7f', '../../supabase/migrations/20261109100000_agenda_fase7f_base.sql'],
  // Fase 7f (P2): a própria migration das perguntas (20261109100100), para o P9 de agenda_fase7f_perguntas.sql conferir as cópias. As fontes já estão acima: mig_correcao_fase7a,
  // mig_combinar_fase7d e mig_correcao4_fase7d.
  ['agenda_teste.mig_perguntas_fase7f', '../../supabase/migrations/20261109100100_agenda_fase7f_perguntas.sql'],
  // Fase 7f (P3): a própria migration do bloco (20261109100200), para o L6 e o L7 de agenda_fase7f_bloco.sql conferirem as cópias e o que o bloco lê.
  ['agenda_teste.mig_bloco_fase7f', '../../supabase/migrations/20261109100200_agenda_fase7f_bloco.sql'],
  // Fase 7f (P4): a própria migration do lote (20261109100300), para o O6 de agenda_fase7f_lote.sql conferir as cópias de agenda_aviso_pecas, agenda_aviso_enfileirar e
  // agenda_comunicar_rodar. As fontes já estão acima: mig_correcao2_fase7a, mig_correcao_revisao e mig_perguntas_fase7f.
  ['agenda_teste.mig_lote_fase7f', '../../supabase/migrations/20261109100300_agenda_fase7f_lote.sql'],
  // Fase 7f (P7): a própria migration das leituras (20261109100600), para o V0 de agenda_fase7f_leituras.sql conferir as cópias de _agenda_perguntas_antes, _agenda_ver_decisoes e
  // agenda_saude, e o B4z3 de agenda_fase7f_base.sql conferir o gatilho vivo. As fontes já estão acima: mig_base_fase7f, mig_correcao3_fase7d e mig_leituras_fase7d.
  ['agenda_teste.mig_leituras_fase7f', '../../supabase/migrations/20261109100600_agenda_fase7f_leituras.sql'],
  // Fase 7f (P8): a migration de dado 20261109100900 (os 3 modos com código — o bloco, o prazo e o lote — de desligado a sombra, e o DESFAZER do cabeçalho; FORA_DA_BANCADA:
  // o agenda_fase7f_sombra.sql a roda numa subtransação).
  ['agenda_teste.mig_sombra_fase7f', '../../supabase/migrations/20261109100900_agenda_fase7f_sombra.sql'],
  // Fase 7f (P5): a própria migration da equipe (20261109101000), para o E9 de agenda_fase7f_equipe.sql conferir as 8 cópias. As fontes já estão acima: mig_pergunta_fase7b,
  // mig_correcao2_fase7a, mig_protecoes_fase7a, mig_tarefas_fase7c e mig_equipe_fase3.
  ['agenda_teste.mig_equipe_fase7f', '../../supabase/migrations/20261109101000_agenda_fase7f_equipe.sql'],
  // Fase 7f (P6): a própria migration do cliente (20261109101100), para o C8 de agenda_fase7f_cliente.sql conferir as 13 cópias. As fontes já estão acima:
  // mig_cliente_fase7d, mig_correcao_fase7d, mig_protecoes_fase7a, mig_correcao_rodada_fase5, mig_respostas_fase5, mig_correcao_textos_fase6 e mig_leituras_fase7f.
  ['agenda_teste.mig_cliente_fase7f', '../../supabase/migrations/20261109101100_agenda_fase7f_cliente.sql'],
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
const feriadosMunicipais = ler(join(RAIZ, 'supabase', 'tests', 'agenda', 'feriados_municipais_2026_2035.json'));
await db.query(`select set_config('agenda_teste.feriados_municipais', $1, false)`, [feriadosMunicipais]);
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
