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
//     de função; o atraso longo e o remarcar confirmado são os da Fase 2 (reusados).
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
  // Fase 2 (P6): as migrations 2026102510* entraram na varredura.
  {
    onde: 'agenda_vigiar',
    casou: '1000',
    vezes: 1,
    porque: 'segundos → milissegundos (a duração da rodada em agenda_vigia_rodadas); não é texto_max nem peca_embutida_acima',
  },
  {
    onde: 'agenda_saude',
    casou: '24h',
    // Fase 3 (P4): 2 na versão da Fase 2 (20261025100300) + 3 na recriada (20261026100300: as mesmas 2 e o erros_24h da
    // rotina da equipe). Fase 4 (P5): + 6 na recriada (20261027100500: as mesmas 3 e o erros_24h da rodada do material,
    // contado e posto no bloco material).
    vezes: 11,
    porque: 'nomes das chaves do resultado (rodadas_24h, erros_24h: a janela de um dia da conferência); não é rascunho_validade',
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
  // Fase 3 (P6): o custo da simulação do livre de verdade e a ordem das OS do turno no job do Claude Max.
  {
    onde: 'agenda_livre_de_verdade',
    casou: '1000',
    vezes: 1,
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
  ...['_agenda_cliente_revalidar', '_agenda_cliente_enfileirar', 'pedir_confirmacao_do_agendamento'].map((onde) => ({
    onde,
    casou: '24h',
    vezes: 1,
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
    .filter((f) => /^(2026102416|2026102510|2026102610|2026102710|2026102810)\d{4}_.+\.sql$/.test(f))
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
