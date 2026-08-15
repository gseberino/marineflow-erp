import { describe, it, expect } from 'vitest';
import { buildSurveySheetHtml, type SurveySheetQuestion } from './survey-sheet';

/**
 * A folha de levantamento é o único artefato desta frente que sai do sistema e
 * vai para a mão do técnico sem ninguém revisando. Se faltar um bloco, quem
 * descobre é quem já está no local, longe da oficina.
 *
 * Cada teste aqui trava um dos motivos pelos quais orçamento estoura, e não a
 * aparência da folha.
 */
const header = {
  orderNumber: 'ORÇ-00074',
  clientName: 'Cliente Teste',
  clientPhone: '(47) 99999-0000',
  assetName: 'Motorhome Overlander',
  assetType: 'Motorhome',
  serviceName: 'Substituição LiFePO4',
  companyName: 'HBR Marine Solutions',
};

const perguntas: SurveySheetQuestion[] = [
  {
    id: 'q1', question: 'Qual a distância entre o banco e o quadro?',
    help_text: 'Medir o percurso real do cabo.', answer_type: 'medida',
    options: null, price_impact: 'alto',
  },
  {
    id: 'q2', question: 'Onde fica o cilindro de gás?',
    answer_type: 'texto', options: null, price_impact: 'baixo',
    previousAnswer: 'bagageiro traseiro', previousWhen: 'OS-00042',
  },
  {
    id: 'q3', question: 'Foto do quadro elétrico atual',
    answer_type: 'foto', options: null, price_impact: 'alto',
  },
];

describe('a folha de levantamento', () => {
  const html = buildSurveySheetHtml(header, perguntas, { cases: 0 });

  it('identifica a ordem, o cliente e o ativo', () => {
    expect(html).toContain('ORÇ-00074');
    expect(html).toContain('Cliente Teste');
    expect(html).toContain('Motorhome Overlander');
  });

  // Quem vai a campo precisa do telefone de quem está lá — voltar por não
  // conseguir entrar custa o dia.
  it('leva o contato do cliente', () => {
    expect(html).toContain('(47) 99999-0000');
  });

  it('tem espaço para hora de chegada e saída', () => {
    expect(html).toContain('Chegada');
    expect(html).toContain('Saída');
  });
});

describe('os três blocos que existem por causa de estouro de orçamento', () => {
  const html = buildSurveySheetHtml(header, perguntas, { cases: 0 });

  // "Já que você está aqui, pode ver isso também?" — não registrado no momento,
  // não chega ao faturamento e vira trabalho de graça.
  it('captura o pedido extra no momento em que acontece', () => {
    expect(html).toContain('Enquanto eu estava lá');
    expect(html).toMatch(/vira trabalho de graça/);
  });

  // O que não foi verificado volta como surpresa na execução. Declarado, vira
  // contingência no preço.
  it('pede o que NÃO deu para verificar', () => {
    expect(html).toContain('O que NÃO deu para verificar');
  });

  // Foto do estado original: depois de desmontado não há como provar como era.
  it('manda fotografar antes de mexer', () => {
    expect(html).toMatch(/Fotografei o conjunto ANTES/);
  });
});

describe('as perguntas na folha', () => {
  const html = buildSurveySheetHtml(header, perguntas, { cases: 0 });

  // Killer items primeiro e destacados — checklist bom cobre o que é perigoso
  // pular, não o que é fácil listar.
  it('separa o que muda o preço do resto', () => {
    expect(html).toContain('O que muda o preço');
    expect(html).toContain('Bom saber antes de orçar');
    // A de impacto alto aparece antes da de impacto baixo.
    expect(html.indexOf('distância entre o banco')).toBeLessThan(html.indexOf('cilindro de gás'));
  });

  // "14" anotado sem unidade volta e ninguém sabe se é metro ou centímetro —
  // e quem mediu já foi embora.
  it('imprime a unidade ao lado do campo de medida', () => {
    expect(html).toMatch(/m &nbsp;·&nbsp; cm/);
  });

  it('dá caixas de marcar para pergunta de foto, com saída para quando não deu', () => {
    expect(html).toContain('Fotografei');
    expect(html).toMatch(/Não deu — por quê/);
  });

  // Memória do ativo em papel: confirmar é mais rápido que medir de novo.
  it('mostra a resposta anterior deste ativo, para conferir', () => {
    expect(html).toContain('bagageiro traseiro');
    expect(html).toContain('OS-00042');
    expect(html).toContain('continua igual');
  });
});

describe('o histórico do serviço', () => {
  it('com base, mostra o previsto e o pior caso', () => {
    const html = buildSurveySheetHtml(header, perguntas, {
      cases: 5, p50Minutes: 220, p80Minutes: 300,
      examples: [{ os: 'OS-00041', minutos: 210 }],
    });
    expect(html).toContain('5 execuções');
    expect(html).toContain('3h40');   // 220 min
    expect(html).toContain('5h');     // 300 min
    expect(html).toContain('OS-00041');
  });

  // Com uma ou duas execuções, uma "média" seria número inventado — e quem lê
  // trata número como fato.
  it('sem base suficiente, NÃO inventa média — pede a estimativa do técnico', () => {
    const html = buildSurveySheetHtml(header, perguntas, { cases: 2 });
    expect(html).toContain('Sem histórico deste serviço ainda');
    expect(html).not.toContain('Costuma levar');
    expect(html).toContain('Estimativa');
  });
});

describe('o fechamento', () => {
  const html = buildSurveySheetHtml(header, perguntas, { cases: 0 });

  // Sair do local sem decidir é o que produz orçamento chutado.
  it('força a decisão de confiança antes de sair', () => {
    expect(html).toContain('Dá para orçar com o que eu vi?');
    expect(html).toContain('Não — preciso voltar');
  });

  it('pergunta o que levar se precisar voltar', () => {
    expect(html).toContain('Se precisar voltar, levar');
  });

  it('tem assinatura de quem levantou e de quem acompanhou', () => {
    expect(html).toContain('Técnico que levantou');
    expect(html).toContain('Quem acompanhou no local');
  });

  // O papel só vale se voltar para o sistema.
  it('diz onde lançar o que foi anotado', () => {
    expect(html).toMatch(/aba Levantamento/);
  });

  it('tem croqui para desenhar o percurso', () => {
    expect(html).toContain('Croqui');
  });
});

describe('segurança do conteúdo', () => {
  it('escapa HTML vindo do cadastro', () => {
    const html = buildSurveySheetHtml(
      { ...header, clientName: '<script>alert(1)</script>' },
      perguntas,
    );
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
  });

  // Nenhum valor entra aqui: a folha é de levantamento, não de orçamento.
  it('não carrega preço nenhum', () => {
    const html = buildSurveySheetHtml(header, perguntas, { cases: 0 });
    expect(html).not.toMatch(/R\$/);
  });
});
