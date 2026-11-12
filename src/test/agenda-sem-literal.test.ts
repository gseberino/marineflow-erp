// Agenda de Produção, Fase 1 (P7): parâmetro da agenda mora em UM lugar — a linha de agenda_config.
//
// Spec §3, decisão 4: "Nenhum literal de parâmetro no TS nem no corpo das funções agenda_*/os_*". O risco é real e
// silencioso: um `* 0.8` esquecido numa função faz o dono mudar carga_max e a resposta "~5,4 diárias por semana" não
// mudar, ou mudar só numa das leituras (e as duas leituras passam a discordar). Nada no caminho avisa: o teste byte a
// byte da bancada usa os DEFAULTs, e literal = DEFAULT dá o mesmo texto.
//
// O que este teste varre:
//   · o corpo de TODA função das migrations 2026102416* (são todas da agenda: agenda_*, _agenda_*, os_*, _os_*,
//     aplicar_os_material, _autor_da_agenda), sem os comentários. Os DEFAULTs de agenda_config (160000) ficam fora:
//     é lá que os números moram;
//   · o TS da agenda (_shared/agenda/*.ts, a ferramenta agenda-producao.ts, o passo material-da-agenda.ts do motor) e
//     as partes do Secretário que leem a agenda (agendaDoFechamento, lerAgendaDoFechamento, semNadaMarcado,
//     amanhaComAAgenda, semanaCabe), sem os comentários.
//   · (Fase 2, P6) também as funções das migrations 2026102510* (o motor, a porta, a conferência, a vigia, o rascunho
//     dos pedidos e as leituras do plano — os DEFAULTs novos de agenda_config ficam em 20261025100000, fora de função),
//     o TS novo (_shared/agenda-modo.ts, task-automations/agenda-modos.ts e agenda-vigia.ts) e as partes do Secretário
//     que leem o plano (linhasDaAgendaQueCabem, comprasDoPlano, linhasDaAgenda, osDoPlano, planosDasOs). Os pesos da
//     pontuação do motor são inteiros (estrutura de ordem, não parâmetro do dono) e ficam nas constantes c_peso_*.
//   · (Fase 3, P1) também as funções das migrations 2026102610* (a base: os gatilhos da entrega, das mensagens à equipe e
//     os da Fase 2 recriados; os pacotes seguintes da fase entram aqui sozinhos pelo prefixo). Os DEFAULTs novos de
//     agenda_config (a janela e as horas da equipe, a validade do "ok", a meta do PPC…) ficam em 20261026100000, fora de
//     função.
//   · (Fase 3, P5) a comissão: o pct (20%) só existe no DEFAULT de comissao_config (20261026100000); o corpo de
//     comissao_tecnicos_do_mes e comissao_resumo_do_mes lê a linha (o "20%" do texto sai de comissao_config.pct).
//   · (Fase 3, P7a) as telas: as funções de 20261026100600 entram pelo prefixo (a cor da carga é c.carga_max, a da idade
//     é carteira_laranja_du/carteira_vermelho_du), e os hooks novos da tela (use-agenda-producao.ts, use-status-da-porta.ts)
//     entram no TS varrido. A jornada do dia é agenda_config.jornada_horas: JORNADA_PADRAO_HORAS (_shared/agenda-dia.ts)
//     só existe como o valor de quando a migration ainda não foi aplicada, nos lugares listados em USOS_DA_JORNADA_PADRAO.
// E cobra:
//   1. nenhum valor de parâmetro de agenda_config (carga 0,8, R$ 1.600 e R$ 764 por diária, fator 1,5, frequência
//      mínima 0,25, 1.000 de texto e de peça embutida, validade de 24/72 horas, horário dos turnos, municípios
//      locais) nem número da carteira medida (6,77 / 5,41 / ~5,4 / 4,43 / 2,33), em código ou em texto;
//   2. número com casa decimal só os ESTRUTURAIS listados (0,5 = meio dia, a unidade da duração);
//   3. as exceções (valor proibido usado como estrutura, não como parâmetro) são listadas uma a uma, com o porquê, e
//      somem daqui quando somem do código.
//   · (Fase 4, P1) também as funções das migrations 2026102710* (o prazo do fornecedor, a prontidão recriada, o rascunho
//     do fornecedor e os pacotes seguintes da fase, pelo prefixo). Os DEFAULTs novos de agenda_config (oc_viva_dias, os da
//     nota, do Pix, do detector e da mensagem ao fornecedor) ficam em 20261027100000, fora de função; o prazo de cada classe
//     continua só em prazo_classe_du/importacao_dias (20261024160000).
//   · (Fase 5, P1) também as funções das migrations 2026102810* (os textos ao cliente, o contexto, o proibido, o prometido e
//     os pacotes seguintes da fase, pelo prefixo). Os DEFAULTs novos de agenda_config (a janela, o teto, o intervalo, a
//     aprovação dos primeiros dias, as horas do toque e do preparo, as validades e a conversa) ficam em 20261028100000, fora
//     de função; o atraso longo e o remarcar confirmado são os da Fase 2 (reusados). A correção C1 (20261028100700) entra pelo
//     mesmo prefixo; o DEFAULT novo (cliente_pedido_max_du) fica fora de função, na própria 100700.
//   · (Fase 6, P1) também as funções das migrations 2026102910* (a classe de campo, os dias no início, a medida, o percentil,
//     o leitor e o gravador do que foi aprendido e os pacotes seguintes da fase, pelo prefixo). Os DEFAULTs novos de
//     agenda_config (a hora da rodada, a janela, a trava, os mínimos, os percentis, os limites de troca, a capacidade do dono,
//     o cliente, a revisão da carga, os gatilhos do planejador e as palavras da classe) ficam em 20261029100000, fora de
//     função; o 1,5 que o fator aprendido substitui é o estouro_fator da Fase 1 (o padrão chega ao gravador como parâmetro).
//   · (Correção de 29/10, P1) também as funções das migrations 2026103010* (as leituras do que o dono vê: o bloco inteiro, a
//     reserva com quem vai e a semana que vem na *agenda*; e os pacotes seguintes da correção, pelo prefixo). Nenhum DEFAULT
//     novo: o teto continua texto_max.
//   · (Correção de 29/10, P4) o aviso do gestor ao dono (20261030100300) entra pelo mesmo prefixo; os DEFAULTs novos de
//     agenda_config (a janela, o teto do dia e o tamanho do aviso: gestor_aviso_*) ficam na própria migration, fora de função.
//     O montador (_shared/agenda/aviso-do-gestor.ts) entra pela pasta e o passo do motor (task-automations/agenda-aviso.ts),
//     pela lista.
//   · (Fase 7a, P1) também as funções das migrations 2026103110* (a base do gestor da agenda: o portão, o modo, o dia avisado,
//     a fonte da duração, o gravador do diário, os validadores e o ampliador; e os pacotes seguintes da etapa, pelo prefixo).
//     Os DEFAULTs novos de agenda_config (os interruptores, as regras e os 30 parâmetros com o código AG7: R$ 300, 7 e 1 dias
//     úteis, 18:00, 8 diárias, meio dia…) ficam em 20261031100000, fora de função.
//   · (Fase 7b, P1) também as funções das migrations 2026110110* (a base da 7b: o modo de quem faz a pergunta dos dias; e os
//     pacotes seguintes da etapa, pelo prefixo: a disponibilidade, a pergunta da semana, o motor, as leituras e quem chamar). Os
//     DEFAULTs novos de agenda_config (os 5 interruptores e os 21 parâmetros com o código AG7: 16:45, 0,50, 5 dias úteis, 56
//     dias…) ficam em 20261101100000, fora de função.
//   · (Fase 7c, P1) também as funções das migrations 2026110210* (a base da 7c: o que cada pessoa faz, o que a OS pede, a regra
//     única "a equipe atende", o responsável e as avaliações do publicado; e os pacotes seguintes da etapa, pelo prefixo: o motor, a
//     violação, a conversa, a rodada, as leituras e as tarefas do dia). Os DEFAULTs novos de agenda_config (os 3 interruptores e os
//     17 parâmetros: os níveis, as regras e as palavras, 90 e 60 dias, 20 diárias, 16:10…) ficam em 20261102100000, fora de função.
//   · (Fase 7d, P1) também as funções das migrations 2026110710* (a base da 7d: o histórico dos locais, a regra do conferido, o modo com
//     o freio e o modo das 3 perguntas novas; e os pacotes seguintes da etapa, pelo prefixo: o feriado do município, as leituras do local,
//     o motor, o combinar, o M11, o rascunho e as leituras ao dono). Os DEFAULTs novos de agenda_config (os 6 interruptores e os 24
//     parâmetros com o código AG7: 365 dias, 2 e 1 dias úteis, 45 e 120 minutos, 1,30, 60 km/h, 16:15…) ficam em 20261107100000, fora de
//     função. O prefixo é o da 7d depois do mapa de 05/11 (spec-fase7d R6.2): 20261103* ficaria atrás do que já está em produção.
//   · (Fase 7f, P1) também as funções das migrations 2026110910* (a base da 7f: o modo com o freio, o padrão da pergunta, a zona e a classe; e os pacotes seguintes da
//     etapa, pelo prefixo). Os DEFAULTs novos de agenda_config (os 6 interruptores e os 15 parâmetros: 520 letras, 3 decisões, 5 perguntas, 72 horas, 15 segundos…) ficam em
//     20261109100000, fora de função.
//   · (Fase 7e, P1) também as funções das migrations 2026111110* (a base da 7e: o modo com o freio, a credibilidade, o z e a temporada; e os pacotes seguintes da etapa, pelo prefixo). Os DEFAULTs
//     novos de agenda_config (os 6 interruptores e os 32 parâmetros: 5, 0,50, 2,50, 0,15, 0,80, 12, 8, 6, 4, 0,30, 0,05, 0,60, 0,95, as listas de temporada, 17:30, 1, 3, 15, 5, 20 s…) ficam em
//     20261111100000, fora de função. A tabela da normal de _agenda_z (§4.5) é matemática, não parâmetro: escrita em inteiros (décimos de milésimo) para não confundir com um valor de agenda_config.
//   · (Fase 7g, P1) também as funções das migrations 2026111210* (a base da 7g: quem marcou, o degrau, a zona mais severa, o CHECK das suposições, os textos do porquê e os gatilhos das 3
//     tabelas; e os pacotes seguintes da etapa, pelo prefixo). Os DEFAULTs novos de agenda_config (os 4 interruptores e os 18 parâmetros: 1, 4, 3, 5, 10, 8, 0,50, 6, 28, 16:35, 15 s…) ficam
//     em 20261112100000, fora de função; o limiar da peça pequena chega ao texto pelo detalhe gravado, não por literal.
// Os inteiros pequenos (0, 1, 2, 7: meios-dias por dia, dias da semana…) e os limites de tamanho de texto dos CHECKs
// são estrutura e não entram na regra.
import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';

const RAIZ = process.cwd();
const MIGRATIONS = path.join(RAIZ, 'supabase', 'migrations');
const FUNCOES = path.join(RAIZ, 'supabase', 'functions');

/** Os valores que só podem estar em agenda_config (DEFAULT de 20261024160000) ou sair da medida das diárias. */
const PROIBIDOS: Array<{ nome: string; re: RegExp }> = [
  { nome: 'carga_max (0,8)', re: /(?<![\d.,])0[.,]80?(?!\d)/ },
  { nome: 'mo_por_diaria_preco (1.600)', re: /(?<![\d.,])1\.?600(?![\d.,]?\d)/ },
  { nome: 'mo_por_diaria_real (764)', re: /(?<![\d.,])764(?!\d)/ },
  { nome: 'fator_promessa / estouro_fator (1,5)', re: /(?<![\d.,])1[.,]50?(?!\d)/ },
  { nome: 'frequencia_minima (0,25)', re: /(?<![\d.,])0[.,]25(?!\d)/ },
  { nome: 'texto_max / peca_embutida_acima (1.000)', re: /(?<![\d.,])1\.?000(?![\d.,]?\d)/ },
  { nome: 'proposta_validade / rascunho_validade (72 / 24 horas)', re: /(?<!\d)(?:72|24)\s*(?:hours?|horas?|h\b)/i },
  { nome: 'horário dos turnos (08:00–12:00, 13:00–17:00)', re: /(?<!\d)(?:0?8|12|13|17):00(?!\d)/ },
  { nome: 'municipios_locais', re: /Itaja[ií]|Balne[aá]rio|Navegantes|Cambori[uú]|Tijucas|Blumenau|\bPenha\b/ },
  { nome: 'capacidade medida na carteira (6,77 / 5,41 / ~5,4 / 4,43 / 2,33)', re: /(?<![\d.,(])(?:6[.,]77|5[.,]41?|4[.,]43|2[.,]33)(?!\d)/ },
  // Fase 3 (P5): o pct da comissão "o maior dos dois" mora em comissao_config (DEFAULT 0.200 de 20261026100000).
  { nome: 'comissao_config.pct (20% / 0,2)', re: /(?<![\d.,])(?:20\s*%|0[.,]20?(?!\d))/ },
];

/** Números com casa decimal que são estrutura, não parâmetro. */
const DECIMAIS_ESTRUTURAIS = new Map<string, string>([
  ['0.5', 'meio dia: a unidade da duração (os_planejamento.dias anda de 0,5 em 0,5, CHECK dias * 2 = trunc(dias * 2))'],
]);

/** Valor proibido usado como estrutura: [onde, o que casou, quantas vezes, por quê]. */
const EXCECOES: Array<{ onde: string; casou: string; vezes: number; porque: string }> = [
  {
    onde: '_agenda_atrasos_de',
    casou: '1000',
    vezes: 1,
    porque: 'ordenação: os itens do cliente vêm depois dos da agenda (1000 + posição); não é texto_max nem peca_embutida_acima',
  },
  {
    onde: 'agenda_feriado',
    casou: 'Itajaí',
    vezes: 1,
    porque: 'o nome do feriado municipal de 15/06 (aniversário de Itajaí), o mesmo de _shared/secretario/feriados.ts; não é municipios_locais',
  },
  // Fase 7d (P2, spec-fase7d R6.2): o nome do feriado do município do local tem 2 palavras que casam com a regra, e cada uma conta.
  {
    onde: 'agenda_feriado_municipal',
    casou: 'Balneário',
    vezes: 1,
    porque: 'o nome do feriado de 20/07 (aniversário de Balneário Camboriú), o mesmo de _shared/secretario/feriados.ts; não é municipios_locais',
  },
  {
    onde: 'agenda_feriado_municipal',
    casou: 'Camboriú',
    vezes: 1,
    porque: 'o mesmo nome do feriado de 20/07 (aniversário de Balneário Camboriú); não é municipios_locais',
  },
  // Fase 7d (correção, Onda 3, G6): "Balneário" e "BC" são a cidade: o nome dela, no lugar novo "outro lugar em BC". Onda 4 (20261107100870): recriada (+1).
  {
    onde: '_agenda_local_novo',
    casou: 'Balneário',
    vezes: 2,
    porque: 'o nome da cidade que o dono disse pelo apelido ("outro lugar em BC"); não é municipios_locais',
  },
  {
    onde: '_agenda_local_novo',
    casou: 'Camboriú',
    vezes: 2,
    porque: 'o mesmo nome da cidade; não é municipios_locais',
  },
  // Fase 7d (P6): o exemplo do texto ao dono (spec-fase7d §6.3), na pergunta local sem leitura.
  {
    onde: '_agenda_cliente_anotar_onde',
    casou: 'Itajaí',
    // Fase 7d (correção, Onda 1, 20261107100800): recriada (+2: o exemplo de lugar da O19, nas 2 perguntas). Onda 3 (20261107100860): recriada (+2).
    vezes: 5,
    porque: 'o exemplo literal ao dono (§6.3; na correção O19, "o serviço do {nome} é na Marina Itajaí"); não é municipios_locais',
  },
  // Fase 2 (P6): as migrations 2026102510* entraram na varredura.
  {
    onde: 'agenda_vigiar',
    casou: '1000',
    // Correção de 29/10 (P5, 20261030100400): agenda_vigiar recriada (+1: a mesma duração da rodada; +1: o tempo de cada
    // passo, contagens.ms, também em ms). Correção de 29/10 (revisão do lote, 20261030100500): recriada de novo (+2: a mesma
    // cópia; +1: o tempo do passo novo, equipe_sem_dias, em contagens.ms).
    vezes: 6,
    porque: 'segundos → milissegundos (a duração da rodada e o tempo de cada passo em agenda_vigia_rodadas); não é texto_max nem peca_embutida_acima',
  },
  {
    onde: 'agenda_saude',
    casou: '24h',
    // Fase 3 (P4): 2 na versão da Fase 2 (20261025100300) + 3 na recriada (20261026100300: as mesmas 2 e o erros_24h da
    // rotina da equipe). Fase 4 (P5): + 6 na recriada (20261027100500: as mesmas 3 e o erros_24h da rodada do material,
    // contado e posto no bloco material). Fase 5 (P3): + 9 na recriada (20261028100300: as mesmas 6, o erros_24h da rodada do
    // cliente, contado e posto no bloco cliente, e a métrica resposta_24h_pct). Fase 6 (P6): + 10 na recriada (20261029100600:
    // as mesmas 9 e o erros_24h da rodada do aprendizado, contado e posto no bloco aprendizado). Correção C2 da Fase 6
    // (20261029100950): + 10 na recriada (a mesma cópia; as janelas novas do aprendizado vêm de agenda_config). Fase 7a (P7,
    // 20261031100600): + 12 na recriada (a mesma cópia, 10, e o rodadas_24h e o erros_24h da rodada do gestor, no bloco gestor).
    // Fase 7b (P5, 20261101100400): + 12 na recriada (a mesma cópia; a chave equipe_dias vem de _agenda_saude_equipe7b).
    // Fase 7d (P8, 20261107100700): + 12 na recriada (a mesma cópia; a chave local vem de _agenda_saude_local).
    // Fase 7f (P7, 20261109100600): + 12 na recriada (a mesma cópia; a chave comunicacao vem de _agenda_saude_comunicacao).
    // Fase 7f (P6, 20261109101100): + 12 na recriada (a mesma cópia; a semana na lista dos liberados não tem o literal).
    // Fase 7e (P7, 20261111100600): + 12 na recriada (a mesma cópia; a chave margem vem de _agenda_saude_margem, sem o literal).
    vezes: 112,
    porque: 'nomes das chaves do resultado (rodadas_24h, erros_24h, resposta_24h_pct: a janela de um dia da conferência); não é rascunho_validade',
  },
  // Fase 3 (P4): a rotina da equipe grava a rodada como a vigia.
  {
    onde: 'agenda_rotina_rodar',
    casou: '1000',
    vezes: 1,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas, como agenda_vigiar); não é texto_max nem peca_embutida_acima',
  },
  // Fase 4 (P5): a rodada do material grava a rodada como a vigia e a rotina.
  {
    onde: 'agenda_material_vigiar',
    casou: '1000',
    vezes: 1,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas, como agenda_vigiar e agenda_rotina_rodar); não é texto_max nem peca_embutida_acima',
  },
  // Fase 5 (P3): a rodada do cliente grava a rodada como a vigia, a rotina e o material.
  {
    onde: 'agenda_cliente_vigiar',
    casou: '1000',
    // Fase 7d (P6, 20261107100500): recriada (+1: a mesma duração da rodada).
    // Fase 7f (P6, 20261109101100): recriada (+1: a mesma duração da rodada; o passo semana entra na lista).
    vezes: 3,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas, como agenda_vigiar, agenda_rotina_rodar e agenda_material_vigiar); não é texto_max nem peca_embutida_acima',
  },
  // Fase 6 (P6): a rodada do aprendizado grava a rodada como a vigia, a rotina, o material e o cliente.
  // Correção C1 da Fase 6 (20261029100900): agenda_aprender recriada (+1: a mesma cópia).
  // Fase 7e (P7, 20261111100600): recriada (+1: a mesma cópia; os passos da margem e o relógio não têm o literal).
  {
    onde: 'agenda_aprender',
    casou: '1000',
    vezes: 3,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas, como agenda_cliente_vigiar); não é texto_max nem peca_embutida_acima',
  },
  // Fase 7a (P7, 20261031100600): a rodada do gestor da agenda grava a rodada como a vigia, a rotina, o material, o cliente e o
  // aprendizado. Fase 7a (P10, 20261031100800): recriada (+1: a mesma cópia; o bloco novo chama o compre_ate nos tiques).
  // Fase 7b (P6, 20261101100500): recriada (+1: a mesma cópia; o bloco novo põe os passos dupla e chamar).
  {
    onde: 'agenda_gestor_rodar',
    casou: '1000',
    vezes: 3,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas, como agenda_aprender); não é texto_max nem peca_embutida_acima',
  },
  // Fase 7b (P3, 20261101100200): a rodada da semana da equipe grava a rodada como a rotina, o aprendizado e o gestor.
  {
    onde: 'agenda_equipe_semana',
    casou: '1000',
    vezes: 1,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas, como agenda_rotina_rodar e agenda_gestor_rodar); não é texto_max nem peca_embutida_acima',
  },
  // Fase 7c (P5, 20261102100400): a rodada de quem faz o quê grava a rodada como o aprendizado e a semana da equipe.
  {
    onde: 'agenda_habilidade',
    casou: '1000',
    // Fase 7c, correção da revisão (20261102100580): recriada (+1: a mesma cópia; a pergunta por OS a cada tique).
    // Fase 7c, correção 2 da revisão (20261102100590): recriada (+1: a mesma cópia; a pergunta ligada que sobra depois do DESFAZER).
    vezes: 3,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas, como agenda_aprender e agenda_equipe_semana); não é texto_max nem peca_embutida_acima',
  },
  // Fase 7d (P8, 20261107100700): a saúde do local (a chave local de agenda_saude) nomeia as chaves como os outros blocos.
  {
    onde: '_agenda_saude_local',
    casou: '24h',
    vezes: 2,
    porque: 'nomes das chaves do resultado (rodadas_24h e erros_24h da rodada do local: a janela de um dia da conferência, como os blocos de agenda_saude); não é rascunho_validade',
  },
  // Fase 7f (P7, 20261109100600): a saúde da comunicação (a chave comunicacao de agenda_saude), o mesmo molde, mais as falhas do pré-passo do lote no mesmo dia.
  {
    onde: '_agenda_saude_comunicacao',
    casou: '24h',
    // Fase 7f (P9, 20261109101200): recriada (+3: a mesma cópia; os blocos da equipe e do cliente não têm o literal).
    vezes: 6,
    porque: 'nomes das chaves do resultado (rodadas_24h, erros_24h e falhas_lote_guardaria_24h da rodada comunicar: a janela de um dia da conferência, como os blocos de agenda_saude); não é rascunho_validade',
  },
  // Fase 7c (P8, 20261102100550): a rodada das etapas grava a rodada como a de quem faz o quê; a ordem e a conta do plano do dia têm
  // as constantes de estrutura delas, uma vez cada, com nome (o que é parâmetro vem de agenda_config: tarefas_*, jornada_horas,
  // equipe_hora_como_foi).
  // Fase 7d (P5): a rodada do local, o mesmo molde.
  {
    onde: 'agenda_local_vigiar',
    casou: '1000',
    // Fase 7d (correção, Onda 1, 20261107100800): recriada (+1: a mesma duração da rodada).
    vezes: 2,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas, como agenda_habilidade); não é texto_max nem peca_embutida_acima',
  },
  // Fase 7f (P2): a rodada comunicar, o mesmo molde. (P4: a 20261109100300 a recria com o pré-passo do lote, o corpo de antes inteiro: +1.)
  {
    onde: 'agenda_comunicar_rodar',
    casou: '1000',
    vezes: 2,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas, como agenda_habilidade); não é texto_max nem peca_embutida_acima',
  },
  {
    onde: 'agenda_tarefas_rodar',
    casou: '1000',
    vezes: 1,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas, como agenda_habilidade); não é texto_max nem peca_embutida_acima',
  },
  // Fase 7c, correção 2 da revisão (20261102100590): _agenda_tarefas_sincronizar recriada (+1: a mesma cópia; o carimbo da linha nova
  // de os_planejamento).
  ...([['_agenda_tarefas_sincronizar', 2], ['_agenda_aplicar_etapa', 1]] as const).map(([onde, vezes]) => ({
    onde,
    casou: '0.001',
    vezes,
    porque: 'c_casa: a menor casa de os_tarefas.ordem (numeric(8,3)), para a etapa nova entrar antes da vizinha quando o meio entre as duas não cabe nas 3 casas; não é parâmetro do dono',
  })),
  {
    onde: '_agenda_tarefas_planejar',
    casou: '0.25',
    // as duas regras casam a mesma constante (o valor de frequencia_minima e o decimal fora dos estruturais)
    // Fase 7c, correção da revisão (20261102100580): recriada (+2: a mesma cópia; quem responde e a OS começada antes das etapas).
    // Fase 7c, correção 2 da revisão (20261102100590): recriada (+2: a mesma cópia; a duração do plano).
    vezes: 6,
    porque: 'c_resto: a etapa começada pede ao menos ¼ de meio-dia (spec-fase7c §16.3.6, "max(meios − Σ fração congelada, 0,25)"); não é frequencia_minima',
  },
  {
    onde: '_agenda_tarefas_planejar',
    casou: '0.001',
    // Fase 7c, correção da revisão (20261102100580): recriada (+1: a mesma cópia).
    // Fase 7c, correção 2 da revisão (20261102100590): recriada (+1: a mesma cópia).
    vezes: 3,
    porque: 'c_resid: o resíduo das frações do plano (3 casas, as de os_tarefas_dia.fracao) não é etapa a fazer; não é parâmetro do dono',
  },
  {
    onde: '_agenda_tarefas_planejar',
    casou: '0.01',
    // Fase 7c, correção da revisão (20261102100580): recriada (+1: a mesma cópia).
    // Fase 7c, correção 2 da revisão (20261102100590): recriada (+1: a mesma cópia).
    vezes: 3,
    porque: 'c_folga: a sobra de um meio-dia abaixo de um centésimo não leva outra etapa (a régua do arredondamento); não é parâmetro do dono',
  },
  // Fase 7b (P6, 20261101100500): quem chamar diz quanto a conta custou (as duas voltas do motor), como o livre de verdade.
  {
    onde: '_agenda_quem_chamar',
    casou: '1000',
    // Fase 7b, correção da revisão (20261101100800): recriada (+1: a mesma cópia; a OS reservada fora do "sem lugar", os meios-dias sem
    // os do dono, o prazo da dupla dita e o que dizer no prazo).
    vezes: 2,
    porque: 'segundos → milissegundos (o custo das duas contas do motor no resultado, ms, como agenda_livre_de_verdade); não é texto_max nem peca_embutida_acima',
  },
  // Fase 7b (P5, 20261101100400): a saúde dos dias da equipe (a chave equipe_dias de agenda_saude) nomeia as chaves como os outros
  // blocos da conferência.
  {
    onde: '_agenda_saude_equipe7b',
    casou: '24h',
    vezes: 2,
    porque: 'nomes das chaves do resultado (rodadas_24h e erros_24h da rodada da semana da equipe: a janela de um dia da conferência, como os blocos de agenda_saude); não é rascunho_validade',
  },
  // Fase 3 (P6): o custo da simulação do livre de verdade e a ordem das OS do turno no job do Claude Max.
  {
    onde: 'agenda_livre_de_verdade',
    casou: '1000',
    // Correção de 29/10 (P2, 20261030100100): agenda_livre_de_verdade reescrita (+1: o mesmo ms do custo, no livre do plano).
    // Correção de 29/10 (revisão do lote, 20261030100500): recriada de novo (+1: a mesma cópia).
    // Fase 7a, correção da revisão (20261031100980): recriada de novo, com o teto da equipe e o dono fora da conta (+1: a mesma cópia).
    // Fase 7b (P6, 20261101100500): recriada de novo, com a linha de quem chamar (+1: a mesma cópia).
    // Fase 7b, correção da revisão (20261101100800): recriada de novo, com a linha de quem chamar fora do corte (+1: a mesma cópia).
    // Fase 7g (P4, 20261112100300): recriada de novo, com as livre_semanas semanas (+2: a mesma cópia, e o return de antes repetido no ramo de sombra,
    // que devolve a resposta de antes byte a byte com dados.teste).
    vezes: 8,
    porque: 'segundos → milissegundos (o custo da simulação no resultado, ms; a meta < 2 s é do teste); não é texto_max nem peca_embutida_acima',
  },
  {
    onde: 'ai_job_registrar_os',
    casou: '1000',
    vezes: 1,
    porque: 'ordenação: as OS novas do turno vêm depois das que o job já tinha (1000 + posição); não é texto_max nem peca_embutida_acima',
  },
  // Fase 4 (revisão, item 8): o prazo do cadastro guarda dias úteis por uma conversão fixa.
  {
    onde: 'agenda_rascunho_fornecedor',
    casou: '7.0',
    vezes: 1,
    porque: 'a semana: "N dias corridos" vira ceil(N × 5 / 7.0) dias úteis (5 úteis em 7 corridos), conversão fixa que não depende de hoje; não é parâmetro do dono',
  },
  // Fase 5 (P2): o nome de um motivo de recusa da mensagem ao cliente (a lista fechada de
  // agenda_cliente_mensagens.recusa_motivo, criada no P1). As horas são agenda_config.cliente_mesmo_tipo_horas.
  // Correção C1 da Fase 5 (20261028100700): revalidar e enfileirar recriados (+1 cada: a cópia leva o mesmo nome do motivo);
  // o corpo do botão foi para _pedir_confirmacao (a cópia de 100200, com o mesmo nome); a casca nova não tem nenhum.
  // Correção C2 da Fase 5 (20261028100800): revalidar e enfileirar recriados de novo (+1 cada: a mesma cópia).
  // Fase 6 (P7, 20261029100700): _pedir_confirmacao recriado (+1: a cópia leva o mesmo nome do motivo; o texto do botão sem "ele").
  // Fase 7d (P6, 20261107100500): revalidar recriado (+1: a mesma cópia).
  // Fase 7d (correção, Onda 1, 20261107100800): revalidar recriado (+1: a mesma cópia).
  // Fase 7f (P6, 20261109101100): revalidar recriado (+1: a mesma cópia; a regra da semana não tem o nome do motivo).
  // Fase 7f (P9, 20261109101200): revalidar recriado de novo (+1: a mesma cópia; a regra da semana que mudou não tem o nome do motivo).
  ...([['_agenda_cliente_revalidar', 7], ['_agenda_cliente_enfileirar', 3], ['pedir_confirmacao_do_agendamento', 1],
        ['_pedir_confirmacao', 2]] as const).map(([onde, vezes]) => ({
    onde,
    casou: '24h',
    vezes,
    porque: 'o nome do motivo mesmo_tipo_24h (a lista fechada de recusa_motivo); as horas vêm de cliente_mesmo_tipo_horas, não é rascunho_validade',
  })),
];

/** As partes do Secretário que leem a agenda (o resto do arquivo é do Secretário e tem os números dele). */
const PARTES_DO_SECRETARIO: Array<{ arquivo: string; funcoes: string[] }> = [
  { arquivo: 'ai-daily-briefing/secretario-tarde-coleta.ts', funcoes: ['agendaDoFechamento', 'lerAgendaDoFechamento'] },
  { arquivo: 'ai-daily-briefing/secretario-tarde-texto.ts', funcoes: ['semNadaMarcado', 'amanhaComAAgenda', 'semanaCabe', 'linhasDaAgendaQueCabem'] },
  // Fase 2 (P5): o plano no fechamento e na manhã (as linhas e as compras do plano, as OS do dia pelo plano).
  { arquivo: 'ai-daily-briefing/secretario-tarde-coleta.ts', funcoes: ['comprasDoPlano', 'linhasDaAgenda'] },
  { arquivo: 'ai-daily-briefing/secretario-coleta.ts', funcoes: ['osDoPlano', 'planosDasOs'] },
];

interface Trecho {
  onde: string;
  /** o código sem comentários */
  codigo: string;
  /** os números do código (literal numérico) */
  numeros: string[];
}

// ── SQL: o corpo de cada função das migrations da Fase 1 ─────────────────────────────────────────────────

/** Tira os comentários de linha ("--" até o fim da linha) que não estão dentro de uma string. */
function semComentarioSql(sql: string): string {
  let saida = '';
  let emString = false;
  for (let i = 0; i < sql.length; i++) {
    const c = sql[i];
    if (emString) {
      saida += c;
      if (c === "'") emString = false;
      continue;
    }
    if (c === "'") {
      emString = true;
      saida += c;
      continue;
    }
    if (c === '-' && sql[i + 1] === '-') {
      while (i < sql.length && sql[i] !== '\n') i++;
      saida += '\n';
      continue;
    }
    saida += c;
  }
  return saida;
}

export function corposDasFuncoes(sql: string, arquivo: string): Trecho[] {
  const trechos: Trecho[] = [];
  const cabeca = /^create or replace function public\.([a-z_0-9]+)\(/gm;
  let m: RegExpExecArray | null;
  while ((m = cabeca.exec(sql))) {
    const abre = /\$([a-z_]*)\$/g;
    abre.lastIndex = m.index;
    const a = abre.exec(sql);
    if (!a) throw new Error(`${arquivo}: ${m[1]} sem corpo entre $tag$`);
    const fim = sql.indexOf(a[0], a.index + a[0].length);
    if (fim < 0) throw new Error(`${arquivo}: ${m[1]} sem o $tag$ que fecha`);
    const codigo = semComentarioSql(sql.slice(a.index + a[0].length, fim));
    // Números fora das strings (dentro delas é texto e passa pela regra 1).
    const foraDeString = codigo.replace(/'(?:[^']|'')*'/g, "''");
    const numeros = [...foraDeString.matchAll(/(?<![\w.$])\d+(?:\.\d+)?(?![\w])/g)].map((x) => x[0]);
    trechos.push({ onde: m[1], codigo, numeros });
    cabeca.lastIndex = fim;
  }
  return trechos;
}

function funcoesDasMigrations(): Trecho[] {
  return fs.readdirSync(MIGRATIONS)
    .filter((f) => /^(2026102416|2026102510|2026102610|2026102710|2026102810|2026102910|2026103010|2026103110|2026110110|2026110210|2026110710|2026110910|2026111110|2026111210)\d{4}_.+\.sql$/.test(f))
    .sort()
    .flatMap((f) => corposDasFuncoes(fs.readFileSync(path.join(MIGRATIONS, f), 'utf8').replace(/\r\n/g, '\n'), f));
}

// ── TS: o código sem comentários, pelo parser do TypeScript ─────────────────────────────────────────────

/** Os literais (texto e número) de um nó, sem comentário nenhum: é o que o código usa e o que o dono lê. */
export function trechoDoTs(no: ts.Node, onde: string): Trecho {
  const textos: string[] = [];
  const numeros: string[] = [];
  const visitar = (n: ts.Node) => {
    if (ts.isNumericLiteral(n)) numeros.push(n.text);
    else if (ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) textos.push(n.text);
    else if (ts.isTemplateHead(n) || ts.isTemplateMiddle(n) || ts.isTemplateTail(n)) textos.push(n.text);
    else if (ts.isRegularExpressionLiteral(n)) textos.push(n.text);
    ts.forEachChild(n, visitar);
  };
  visitar(no);
  return { onde, codigo: [...textos, ...numeros].join('\n'), numeros };
}

function fonte(arquivo: string): ts.SourceFile {
  return ts.createSourceFile(arquivo, fs.readFileSync(arquivo, 'utf8'), ts.ScriptTarget.ESNext, true);
}

function tsDaAgenda(): Trecho[] {
  const pasta = path.join(FUNCOES, '_shared', 'agenda');
  const inteiros = [
    ...fs.readdirSync(pasta).filter((f) => f.endsWith('.ts') && !f.endsWith('_test.ts')).map((f) => path.join(pasta, f)),
    path.join(FUNCOES, '_shared', 'ai', 'tools', 'agenda-producao.ts'),
    path.join(FUNCOES, 'task-automations', 'material-da-agenda.ts'),
    // Fase 2: o modo da proposta, os modos da vigia e o passo da vigia no motor de 15 min.
    path.join(FUNCOES, '_shared', 'agenda-modo.ts'),
    path.join(FUNCOES, 'task-automations', 'agenda-modos.ts'),
    path.join(FUNCOES, 'task-automations', 'agenda-vigia.ts'),
    // Fase 4 (P5): o passo da vigia do material no motor de 15 min.
    path.join(FUNCOES, 'task-automations', 'agenda-material.ts'),
    // Fase 5 (P3): o passo da rodada do cliente no motor de 15 min.
    path.join(FUNCOES, 'task-automations', 'agenda-cliente.ts'),
    // Fase 6 (P8): o passo da rodada do aprendizado no motor de 15 min.
    path.join(FUNCOES, 'task-automations', 'agenda-aprender.ts'),
    // Fase 7d (P5): o passo da rodada do local no motor de 15 min.
    path.join(FUNCOES, 'task-automations', 'agenda-local.ts'),
    // Correção de 29/10 (P4): o passo do aviso do gestor ao dono no motor de 15 min (o montador, _shared/agenda/
    // aviso-do-gestor.ts, já entra pela pasta).
    path.join(FUNCOES, 'task-automations', 'agenda-aviso.ts'),
    // Fase 3 (P7a): os hooks das telas (a Semana, a Carteira, o cartão Plano e o que a porta aceita pela tela).
    path.join(RAIZ, 'src', 'hooks', 'use-agenda-producao.ts'),
    path.join(RAIZ, 'src', 'hooks', 'use-status-da-porta.ts'),
  ];
  const trechos = inteiros.map((a) => trechoDoTs(fonte(a), path.relative(RAIZ, a)));
  for (const { arquivo, funcoes } of PARTES_DO_SECRETARIO) {
    const sf = fonte(path.join(FUNCOES, arquivo));
    const achadas = new Map<string, ts.Node>();
    const procurar = (n: ts.Node) => {
      if (ts.isFunctionDeclaration(n) && n.name && funcoes.includes(n.name.text)) achadas.set(n.name.text, n);
      ts.forEachChild(n, procurar);
    };
    procurar(sf);
    for (const f of funcoes) {
      const no = achadas.get(f);
      if (!no) throw new Error(`${arquivo}: a função ${f} sumiu (renomeada?) — atualize PARTES_DO_SECRETARIO`);
      trechos.push(trechoDoTs(no, `${arquivo}#${f}`));
    }
  }
  return trechos;
}

// ── Fase 3 (P7a): JORNADA_PADRAO_HORAS só como reserva ──────────────────────────────────────────────────

/** Onde o código (não o comentário) usa JORNADA_PADRAO_HORAS, e por quê: todos são o valor de quando agenda_config não
 *  responde (a migration ainda não aplicada, o login que não lê a tabela). Arquivo novo usando = falha; arquivo que
 *  deixou de usar = falha (a entrada tem de sair). */
const USOS_DA_JORNADA_PADRAO: Record<string, string> = {
  'supabase/functions/_shared/agenda-dia.ts': 'a definição e o padrão do parâmetro jornada de horasNoDia',
  'src/hooks/use-agenda-producao.ts': 'CONFIG_DE_ANTES e jornadaDaAgenda: a tela antes da migration',
  'src/hooks/use-agenda.ts': 'o padrão do parâmetro jornada de overloadWarning (quem chama passa jornadaDaAgenda)',
  'supabase/functions/_shared/ai/tools/agenda.ts': 'dayOverloadNotice: agenda_config sem resposta (o erro vai a app_error_logs)',
};

function usosDaJornadaPadrao(): string[] {
  const achados: string[] = [];
  const andar = (pasta: string) => {
    for (const nome of fs.readdirSync(pasta)) {
      const p = path.join(pasta, nome);
      if (fs.statSync(p).isDirectory()) {
        if (nome !== 'node_modules') andar(p);
        continue;
      }
      if (!/\.(ts|tsx)$/.test(nome) || /(_test|\.test|\.smoke\.test)\.tsx?$/.test(nome)) continue;
      const texto = fs.readFileSync(p, 'utf8');
      if (!texto.includes('JORNADA_PADRAO_HORAS')) continue;
      const sf = ts.createSourceFile(p, texto, ts.ScriptTarget.ESNext, true);
      let usa = false;
      const visitar = (n: ts.Node) => {
        if (ts.isIdentifier(n) && n.text === 'JORNADA_PADRAO_HORAS') usa = true;
        ts.forEachChild(n, visitar);
      };
      visitar(sf);
      if (usa) achados.push(path.relative(RAIZ, p).split(path.sep).join('/'));
    }
  };
  andar(path.join(RAIZ, 'src'));
  andar(FUNCOES);
  return achados.sort();
}

// ── A regra ─────────────────────────────────────────────────────────────────────────────────────────────

export interface Achado {
  onde: string;
  regra: string;
  casou: string;
}

export function achadosDe(trechos: Trecho[]): Achado[] {
  const achados: Achado[] = [];
  for (const t of trechos) {
    for (const p of PROIBIDOS) {
      for (const m of t.codigo.matchAll(new RegExp(p.re.source, p.re.flags.includes('g') ? p.re.flags : p.re.flags + 'g'))) {
        achados.push({ onde: t.onde, regra: p.nome, casou: m[0] });
      }
    }
    for (const n of t.numeros) {
      if (/\./.test(n) && !DECIMAIS_ESTRUTURAIS.has(String(Number(n)))) {
        achados.push({ onde: t.onde, regra: 'número com casa decimal fora dos estruturais', casou: n });
      }
    }
  }
  return achados;
}

/** Tira as exceções listadas (exatas: o mesmo lugar, o mesmo valor, as mesmas vezes). */
function semExcecoes(achados: Achado[]): { resto: Achado[]; sobrando: string[] } {
  const resto = [...achados];
  const sobrando: string[] = [];
  for (const e of EXCECOES) {
    const deste = resto.filter((a) => a.onde === e.onde && a.casou === e.casou);
    if (deste.length !== e.vezes) sobrando.push(`${e.onde} "${e.casou}": a exceção espera ${e.vezes}, o código tem ${deste.length}`);
    for (const a of deste) resto.splice(resto.indexOf(a), 1);
  }
  return { resto, sobrando };
}

const linha = (a: Achado) => `  ${a.onde}: ${a.regra} → "${a.casou}"`;

describe('agenda: parâmetro só em agenda_config', () => {
  const sql = funcoesDasMigrations();
  const tsAgenda = tsDaAgenda();

  it('a varredura enxerga as funções e os arquivos (senão passaria vazia)', () => {
    expect(sql.length, 'funções das migrations 2026102416*').toBeGreaterThan(90);
    expect(sql.map((t) => t.onde)).toEqual(expect.arrayContaining([
      'agenda_ver', 'agenda_semana', 'os_prontidao', 'os_duracao_sugerida', 'agenda_capacidade_semanal',
      'agenda_rascunho_planejar', 'agenda_disponibilidade_semear', 'aplicar_os_material', '_autor_da_agenda',
      // Fase 2 (P6): o motor, a porta, a vigia, a saúde, o rascunho dos pedidos e as leituras do plano
      'agenda_propor', 'os_transicionar_status', 'agenda_vigiar', 'agenda_saude', 'agenda_rascunho_andamento',
      'agenda_propor_dito', 'agenda_linhas_do_dia',
      // Fase 3 (P1): a base (o gatilho da entrega e o das mensagens à equipe)
      '_so_entrega_pela_porta', '_agenda_equipe_mensagens_so_responde',
      // Fase 3 (P5): a comissão (só a conta)
      'comissao_tecnicos_do_mes', 'comissao_resumo_do_mes',
      // Fase 3 (P7a): as telas e a regra da porta que a tela lê
      'agenda_tela_semana', 'agenda_tela_carteira', 'os_plano_da_os', 'os_status_da_tela', '_os_porta_regra',
      // Fase 4 (P1): o prazo do fornecedor, o gatilho do original da previsão e o rascunho do fornecedor
      '_agenda_prazo_do_fornecedor', '_agenda_chegada_pela_classe', '_os_material_previsao_original', 'agenda_rascunho_fornecedor',
      // Fase 5 (P1): o contexto e os textos ao cliente, o proibido e a gravação do prometido
      '_agenda_cliente_contexto', '_agenda_cliente_texto', '_agenda_cliente_texto_proibido', '_agenda_cliente_gravar_prometido',
      // Fase 5 (P2): o envio (a hora, a revalidação, o registro, as travas, o passo da fila) e o D9 recriado
      '_agenda_cliente_quando', '_agenda_cliente_revalidar', '_agenda_cliente_registrar', '_agenda_cliente_enfileirar',
      '_agenda_fila_do_cliente', '_agenda_cliente_fila', 'pedir_confirmacao_do_agendamento', 'registrar_confirmacao_do_cliente',
      // Correção C1 da Fase 5: o botão interno, a outra conversa, o motivo em texto e o aviso de "não saiu"
      '_pedir_confirmacao', '_agenda_cliente_outra_conversa', '_agenda_cliente_motivo_texto', '_agenda_cliente_avisar_recusa',
      // Correção C2 da Fase 5: o texto sem artigo, o prometido que sai e o erro de uma OS
      '_agenda_cliente_sem_artigo', '_agenda_cliente_tirar_prometido', '_agenda_cliente_erro_da_os',
      // Fase 6 (P1): a classe de campo, os dias no início, a medida, o percentil, o leitor, os textos e o gravador
      '_agenda_classe_de_campo', '_agenda_classe_pares_ok', '_agenda_dias_no_inicio', '_agenda_aprender_congelar',
      'agenda_medir_os', '_agenda_aprender_medir', '_agenda_percentil', '_agenda_aprendido', '_agenda_aprendizado_texto',
      '_agenda_aprendizado_gravar',
      // Fase 6 (P2): o fator de campo, o R$ por diária e a presença aprendida (os passos e as leituras)
      '_agenda_aprender_fator', 'agenda_fator_de_campo', '_agenda_aprender_mo', '_agenda_mo_por_diaria_real',
      '_agenda_aprender_presenca', '_agenda_presenca_aprendida',
      // Fase 6 (P3): o atraso e o prazo medidos do fornecedor (o passo e a leitura)
      '_agenda_aprender_fornecedor', '_agenda_atraso_do_fornecedor',
      // Fase 6 (P4): a capacidade do dono (o passo) e a carga de cada pessoa no motor
      '_agenda_aprender_capacidade', '_agenda_carga_da_pessoa',
      // Fase 6 (P5): a pontualidade e a folga do aviso ao cliente (o passo); o risco e o gravador do prometido recriados
      '_agenda_aprender_cliente', '_agenda_cliente_risco', '_agenda_cliente_gravar_prometido',
      // Fase 6 (P6): a rodada, a revisão da carga, o planejador mais forte, a decisão, o *desfaz* e a escrita da carga; as
      // recriadas (agenda_decidir, agenda_desfazer, agenda_desfazer_dito e agenda_saude) já estavam na lista pelas fases de antes
      'agenda_aprender', '_agenda_aprender_revisao', '_agenda_aprender_solver', '_agenda_aprendizado_decidir',
      '_agenda_desfazer_aprendizado', '_agenda_aprendizado_carga',
      // Fase 6 (P7): o acabamento dos textos da Fase 5 (nenhuma nova; as recriadas que ainda não estavam na lista)
      'agenda_cliente_preparar', 'agenda_resposta_do_cliente', '_agenda_cliente_da_os', '_agenda_ver_clientes',
      '_agenda_cliente_confirmar_dia', '_agenda_cliente_anotar_acesso', '_agenda_cliente_pedido_de_dia', '_agenda_desfazer_cliente',
      '_agenda_cliente_teria_feito',
      // Fase 6 (P8): o foco aprendizado e o foco fornecedores recriado (agenda_ver e os_plano_da_os já estavam na lista)
      '_agenda_ver_aprendizado', '_agenda_ver_fornecedores',
      // Correção C1 da Fase 6: o fornecedor da medida e o dia da conclusão (as recriadas já estavam na lista)
      '_agenda_fornecedor_da_medida', '_agenda_concluida_em',
    ]));
    expect(tsAgenda.map((t) => t.onde)).toEqual(expect.arrayContaining([
      path.join('supabase', 'functions', 'task-automations', 'agenda-vigia.ts'),
      'ai-daily-briefing/secretario-tarde-texto.ts#linhasDaAgendaQueCabem',
    ]));
    expect(tsAgenda.length).toBeGreaterThanOrEqual(10);
    // A varredura vê o literal estrutural que existe (prova de que lê números e texto).
    expect(sql.find((t) => t.onde === '_agenda_dias')!.numeros).toContain('0.5');
    expect(sql.find((t) => t.onde === 'agenda_ver')!.codigo).toContain("'o_que_fazer'");
  });

  it('nenhum literal de parâmetro nem número da carteira no corpo das funções da agenda', () => {
    const { resto, sobrando } = semExcecoes(achadosDe(sql));
    expect(resto.map(linha), `literal de parâmetro em função da agenda (leia de agenda_config: _agenda_cfg()):\n${resto.map(linha).join('\n')}`).toEqual([]);
    expect(sobrando, 'exceção listada que não bate mais com o código: ajuste ou tire de EXCECOES').toEqual([]);
  });

  it('nenhum literal de parâmetro nem número da carteira no TS da agenda (e nas partes do Secretário que a leem)', () => {
    const achados = achadosDe(tsAgenda);
    expect(achados.map(linha), `literal de parâmetro no TS da agenda (o número vem do banco):\n${achados.map(linha).join('\n')}`).toEqual([]);
  });

  it('JORNADA_PADRAO_HORAS só como o valor de quando agenda_config não responde (Fase 3, P7a)', () => {
    expect(usosDaJornadaPadrao(), 'a jornada do dia é agenda_config.jornada_horas; a constante é só a reserva listada')
      .toEqual(Object.keys(USOS_DA_JORNADA_PADRAO).sort());
    // a grade da Agenda lê a jornada da config (useAgendaConfig), não a constante
    expect(usosDaJornadaPadrao()).not.toContain('src/pages/AgendaPage.tsx');
  });

  it('a regra acusa o que deve e deixa passar o que é estrutura (sem isto, um regex quebrado passaria tudo)', () => {
    const sqlRuim = corposDasFuncoes([
      "create or replace function public.agenda_x(p numeric) returns numeric language sql as $function$",
      "  -- 0.8 no comentário não conta; c.carga_max sim é o certo",
      "  select p * 0.8 + 1600 + 764 + 0.25 + 1.5 + 0.6 + 1000, '~5,4 diárias', interval '24 hours', '13:00'::time, 'Itajaí', '20% do lucro'",
      "$function$;",
      "create or replace function public.agenda_y(p numeric) returns numeric language sql as $function$",
      "  select greatest(0.5, round(p * 2) / 2) * c.carga_max from agenda_config c where 'meio dia' <> '1 dia'",
      "$function$;",
    ].join('\n'), 'ensaio.sql');
    const achados = achadosDe(sqlRuim);
    expect(achados.filter((a) => a.onde === 'agenda_y')).toEqual([]);
    const regras = new Set(achados.filter((a) => a.onde === 'agenda_x').map((a) => a.regra));
    // Cada regra da lista acusa o seu valor no ensaio (uma regra que nunca acusa é uma regra quebrada).
    for (const p of PROIBIDOS) expect(regras.has(p.nome), p.nome).toBe(true);
    expect(regras.has('número com casa decimal fora dos estruturais')).toBe(true);
    // O 0,6 não está na lista de proibidos, mas é decimal fora dos estruturais: a regra 2 pega o parâmetro novo.
    expect(achados.some((a) => a.onde === 'agenda_x' && a.casou === '0.6')).toBe(true);

    const tsRuim = ts.createSourceFile('ensaio.ts', [
      '// 0.8 e 1600 no comentário não contam',
      'const carga = 0.8;',
      'const texto = `~5,4 diárias de equipe por semana`;',
      'const meio = 0.5; const pagina = 200; const dias = 7;',
    ].join('\n'), ts.ScriptTarget.ESNext, true);
    const doTs = achadosDe([trechoDoTs(tsRuim, 'ensaio.ts')]);
    expect(doTs.map((a) => a.casou).sort()).toEqual(['0.8', '0.8', '5,4'].sort());
  });
});
