// Dados de exemplo das telas de produção (Fase 3, P7a), no formato que o banco devolve (agenda_tela_semana,
// agenda_tela_carteira, os_plano_da_os) — tirados da bancada com a carteira sintética da Fase 3 (só primeiros nomes).
// Servem aos testes de render; nada aqui vai para produção.
import type { CarteiraDeProducao, ClienteDoPlano, PlanoDaOsDados, SemanaDeProducao } from '@/hooks/use-agenda-producao';

export const SEMANA_DE_EXEMPLO: SemanaDeProducao = {
  modo: 'ligado', em_teste: false, de: '2026-11-02', ate: '2026-11-07',
  titulo: 'Semana de 03 a 06/11 (seg 02 é Finados)',
  // revisão da Fase 3: sem o PPC — a semana passada (26 a 30/10) não tinha dia conferido, então o resumo não fala dela
  resumo: 'comprometido 79% · livre 3 diárias',
  comprometido_pct: 79, livre_diarias: 3, ppc_anterior: null,
  livre_de_verdade: 'Livre de verdade (pela simulação da agenda): a partir da semana de 07/12. É simulação: não muda nada.',
  dias: [
    { dia: '2026-11-02', rotulo: 'SEG 02/11', hoje: false, feriado: 'Finados', pessoas: [], blocos: [], livre_texto: null },
    {
      dia: '2026-11-03', rotulo: 'TER 03/11', hoje: true, feriado: null,
      pessoas: [
        { payee_id: 'p1', nome: 'Gustavo', eh_dono: true, meios_usados: 2, meios_esperados: 2, pct: 100, cor: 'ambar', texto: 'Gustavo 2/2' },
        { payee_id: 'p3', nome: 'João', eh_dono: false, meios_usados: 1, meios_esperados: 0, pct: null, cor: 'vermelho', texto: 'João 1/0' },
        { payee_id: 'p2', nome: 'Roberto', eh_dono: false, meios_usados: 1, meios_esperados: 2, pct: 50, cor: 'verde', texto: 'Roberto 1/2' },
      ],
      blocos: [
        {
          os: 'os-69', numero: 'OS-00069', cliente: 'Vanderlei', bem: 'Mar Azul', local: null, hora: '08:00',
          pessoas_texto: 'você abre, Roberto o dia todo', dia_n: 1, dias_total: 3, dia_texto: 'dia 1 de 3',
          confirmado_cliente: true, reserva: false, reserva_texto: null, condicao: null, tipo: 'execucao', fixada: false,
          resultado: null, resultado_texto: null,
        },
        {
          os: 'os-203', numero: 'OS-00203', cliente: 'Caio', bem: 'Lancha com nome comprido de verdade', local: 'Marina',
          hora: '13:00', pessoas_texto: 'João à tarde', dia_n: null, dias_total: null, dia_texto: null,
          confirmado_cliente: false, reserva: true, reserva_texto: 'Reserva, a confirmar',
          condicao: 'se o material da Premel estiver na mão', tipo: 'reserva', fixada: false, resultado: null, resultado_texto: null,
        },
      ],
      livre_texto: 'livre: Roberto tarde',
    },
  ],
  mudancas: [
    {
      acao_id: 'a1', tipo: 'publicacao', os: 'os-69', numero: 'OS-00069',
      texto: 'Publiquei a semana de 03 a 06/11 (seg 02 é Finados): Vanderlei (OS-00069): ter 03 a qui 05/11, você abre e fecha, Roberto os 3 dias.',
      desfazivel: true, desfeita: false, desfazivel_ate: '2026-10-30T19:30:00Z', perda: null,
    },
    {
      acao_id: 'a2', tipo: 'concluir', os: 'os-74', numero: 'OS-00074',
      // revisão da Fase 3 (item 5): concluída hoje (ter 03/11), então "vence hoje" é hoje mesmo; de outro dia, o banco diz a data
      texto: 'Lenine (OS-00074): concluída — saída ter 03/11 16:30. Cobrança: Saldo R$ 2.280,00 (vence hoje).',
      desfazivel: true, desfeita: false, desfazivel_ate: '2026-11-04T19:30:00Z', perda: 'cobranca',
    },
  ],
  decisoes: [{ pergunta_id: 'q1', n: 1, tipo: 'nao_cabe', texto: 'Decisão 1: Não cabe tudo até qui 05/11. Qual aceita atrasar? 1) Nelson (OS-00112) atrasa; 2) Deixo o Nelson fora do plano por enquanto. Recomendo a 1.' }],
  como_responder: 'Responda no WhatsApp: diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2").',
};

export const CARTEIRA_DE_EXEMPLO: CarteiraDeProducao = {
  modo: 'ligado',
  grupos: [
    { chave: 'prontas_sem_data', rotulo: 'Prontas sem data', n: 1 },
    { chave: 'material_com_data', rotulo: 'Material com data', n: 1 },
    { chave: 'material_sem_previsao', rotulo: 'Material sem previsão', n: 0 },
    { chave: 'material_atrasado', rotulo: 'Material atrasado', n: 0 },
    { chave: 'aguardando_cliente', rotulo: 'Aguardando o cliente', n: 1 },
    { chave: 'sem_estimativa', rotulo: 'Sem estimativa', n: 0 },
    { chave: 'congeladas', rotulo: 'Congeladas', n: 0 },
    { chave: 'em_execucao', rotulo: 'Em execução', n: 0 },
    { chave: 'concluidas_nao_entregues', rotulo: 'Concluídas e não entregues', n: 0 },
  ],
  cartoes: [
    {
      os: 'os-100', numero: 'OS-00100', cliente: 'Giancarlo', bem: 'Motorhome', grupo: 'prontas_sem_data',
      estado: 'pronto a partir de qui 12/11', desde: '2026-10-13', idade_du: 14, idade_texto: 'há 14 dias úteis', cor: 'laranja',
      proxima_acao: 'entrar no plano da semana', quem_trava: null, quem_trava_texto: null,
    },
    {
      os: 'os-112', numero: 'OS-00112', cliente: 'Nelson', bem: 'Veleiro', grupo: 'material_com_data',
      estado: 'pronto a partir de qui 05/11', desde: '2026-10-06', idade_du: 18, idade_texto: 'há 18 dias úteis', cor: 'laranja',
      proxima_acao: 'esperar "Painel Touch de Monitoramento e…" (ter 03/11)', quem_trava: 'fornecedor', quem_trava_texto: 'trava: o fornecedor',
    },
    {
      os: 'os-32', numero: 'OS-00032', cliente: 'Kalmar', bem: 'Kalmar 40', grupo: 'aguardando_cliente',
      estado: 'esperando o cliente', desde: '2026-05-15', idade_du: 118, idade_texto: 'há 118 dias úteis', cor: 'vermelho',
      proxima_acao: 'o cliente liberar', quem_trava: 'cliente', quem_trava_texto: 'trava: o cliente',
    },
  ],
};

export const PLANO_DE_EXEMPLO: PlanoDaOsDados = {
  os: 'os-69', numero: 'OS-00069', status: 'completed', estado: 'concluído',
  marcos: { texto: 'Entrada qua 29/07 · início ter 03/11 (68 dias úteis) · conclusão qui 05/11 (2 dias úteis) · entrega —', sem_entrega_du: 1 },
  pode_entregar: true,
  duracao: {
    dias: 3, fonte: 'dono', fonte_texto: 'você disse', faixa: { otimista: 2, realista: 3.5 }, faixa_texto: 'faixa 2 a 3,5 dias',
    texto: '3 dias: Roberto (dia todo) (você disse)',
  },
  presenca_dono: { valor: 'abre_e_fecha', pela_regra: true, texto: 'Você abre e fecha (pela regra)' },
  material: {
    estado: 'previsto',
    itens: [
      { descricao: 'Kit Cabos/ Conectores/ Terminais do Novo Sistema', nivel: 'A', nivel_texto: 'na mão', situacao: 'na_mao',
        previsao: 'na mão desde ter 27/10', trecho: 'o material do Vanderlei chegou da Premel', critico: true, fornecedor: 'Premel' },
      { descricao: 'Painel Touch de Monitoramento e Controle', nivel: 'C', nivel_texto: 'previsão sua', situacao: 'comprado',
        previsao: 'chega ter 03/11', trecho: 'o painel chega terça', critico: false, fornecedor: null },
    ],
  },
  janela: { bem_indisponivel: null, nao_antes_de: null, motivo: null, precisa_ate: '2026-11-05', nao_antes_texto: null,
            precisa_ate_texto: 'o cliente precisa até qui 05/11' },
  prometido_planejado: { precisa_ate: '2026-11-05', fim_publicado: '2026-11-05', folga_du: 0,
                         texto: 'O plano termina qui 05/11, o dia em que o cliente precisa.' },
  planejado_realizado: [
    { dia: '2026-11-03', rotulo: 'Ter 03/11', pessoas_texto: 'você abre, Roberto o dia todo', dia_texto: 'dia 1 de 3', meios: 2,
      resultado: 'cumprido', resultado_texto: 'feito', motivo_texto: null, diaria: 'lançada' },
    { dia: '2026-11-04', rotulo: 'Qua 04/11', pessoas_texto: 'Roberto o dia todo', dia_texto: 'dia 2 de 3', meios: 2,
      resultado: 'parcial', resultado_texto: 'feito em parte', motivo_texto: 'chuva', diaria: 'a confirmar' },
  ],
  intervencoes: [{ dia: '2026-11-04', texto: 'Qua 04/11: você foi à tarde (no plano: nada)' }],
};

// Fase 5 (P6): o bloco "Cliente" do cartão, no formato de os_plano_da_os.cliente — o Nelson da fixture-fase5 (sex 30/10,
// 17:30), com a mensagem ao cliente ligada e o aviso de atraso esperando o dono; e o mesmo em teste (sombra).
const AVISO_DO_NELSON = 'Nelson, quero te avisar com antecedência: a peça do serviço no seu veleiro ainda não chegou e agora está '
  + 'prevista para quarta (11/11). Por isso, o serviço no seu veleiro, que estava para quinta (05/11), deve ficar entre quinta '
  + '(12/11) e sexta (13/11). Te confirmo a data assim que a peça chegar. Se isso atrapalhar algum plano seu, me diga.';
const CONFIRMACAO_DO_NELSON = 'Olá, Nelson! Aqui é o Gustavo, da HBR Marine Solutions. Conseguimos encaixar o serviço no seu veleiro '
  + 'para quinta (05/11), o dia todo, com previsão de 1 dia de trabalho. Pode ser? Responda SIM para confirmar, ou me diga um dia '
  + 'melhor. A partir de agora te mando por aqui as novidades do serviço.';

export const CLIENTE_DO_PLANO_DE_EXEMPLO: ClienteDoPlano = {
  modo: 'ligado', em_teste: false, em_teste_texto: null, nome: 'Nelson',
  telefone_ok: true, conversou: true, opt_out: false, contato_texto: null, servico: null,
  prometido: {
    tipo: 'firme', de: '2026-11-05', ate: '2026-11-05', original_ate: '2026-11-05', fonte: 'mensagem',
    texto: 'qui 05/11 (data firme, por mensagem da agenda em qui 22/10)',
    risco_texto: 'Pode atrasar: agora a previsão é de qui 12/11 a sex 13/11.',
  },
  confirmado_texto: null,
  mensagens: [
    { tipo: 'pode_atrasar', tipo_texto: 'Aviso de atraso', quando_texto: 'amanhã às 09:01', estado: 'aguardando_dono',
      estado_texto: 'espera você', texto: AVISO_DO_NELSON, em_teste: false, espera_voce: true },
    { tipo: 'confirmar', tipo_texto: 'Confirmação', quando_texto: 'qui 22/10 às 10:00', estado: 'sem_resposta',
      estado_texto: 'mandada; sem resposta', texto: CONFIRMACAO_DO_NELSON, em_teste: false, espera_voce: false },
  ],
  mensagens_mais: 0,
  esperando_voce: { n: 1, texto: '1 mensagem esperando você: *manda cliente Nelson* manda; *segura cliente Nelson* segura.' },
};

export const CLIENTE_DO_PLANO_EM_TESTE: ClienteDoPlano = {
  ...CLIENTE_DO_PLANO_DE_EXEMPLO,
  modo: 'sombra', em_teste: true, em_teste_texto: 'Em teste: nada sai ainda. Aqui fica o que eu teria mandado.',
  mensagens: [
    { ...CLIENTE_DO_PLANO_DE_EXEMPLO.mensagens[0], quando_texto: 'amanhã às 09:00', estado: 'registrada',
      estado_texto: 'em teste: sairia', em_teste: true, espera_voce: false },
    CLIENTE_DO_PLANO_DE_EXEMPLO.mensagens[1],
  ],
  esperando_voce: { n: 0, texto: null },
};
