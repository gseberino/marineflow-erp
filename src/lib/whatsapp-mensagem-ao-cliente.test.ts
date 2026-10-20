// A mensagem que a tela manda ao cliente pelo "Enviar via WhatsApp" (pedido do dono, 20/10/2026):
// o link só vai quando ele marca a caixa, e a saudação é escolha dele — o padrão é sem saudação.
//
// Os modelos abaixo são os do banco (whatsapp_templates, semeados em 21/04/2026), passados pela
// MESMA applyTemplateVariables da tela — é ela que deixa "{link}" no texto quando o link não vai.
import { describe, it, expect, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));

import { applyTemplateVariables } from '@/hooks/use-whatsapp-templates';
import { buildQuoteWhatsAppSummary } from './quote-whatsapp-summary';
import {
  corpoPadrao,
  mensagemPadrao,
  modoInicial,
  opcoesDeSaudacao,
  periodoDoDia,
  prepararEnvio,
  primeiroNome,
  temLinkNoTexto,
  textoDaSaudacao,
  tirarLinkDoTexto,
  trocarSaudacao,
} from './whatsapp-mensagem-ao-cliente';

const URL_PUBLICA = 'https://marineflow-erp.vercel.app/view/3f9c2a7e-1b4d-4c8a-9e21-7a6b5c4d3e2f';

/** Brasília é UTC−3 (sem horário de verão desde 2019): 14h em Brasília = 17h UTC. */
const emBrasilia = (hora: number, minuto = 0) =>
  new Date(Date.UTC(2026, 9, 20, hora + 3, minuto));

const MODELOS_DO_BANCO = {
  confirmacaoDeOs: 'Olá {cliente}, sua Ordem de Serviço {os} foi aberta. Acompanhe pelo link: {link}',
  orcamentoEnviado: 'Olá {cliente}, segue o orçamento {os} no valor de {valor}. Acesso: {link}',
  osConcluida: 'Olá {cliente}, sua OS {os} foi concluída. Total: {valor}. Detalhes: {link}',
};

/** O que a tela faz com a caixa desmarcada: {link} sem valor, depois tirarLinkDoTexto. */
const semLink = (modelo: string, vars: Record<string, string | number>) =>
  tirarLinkDoTexto(applyTemplateVariables(modelo, { ...vars, link: '' }), URL_PUBLICA);

describe('link fora do texto quando a caixa está desmarcada', () => {
  it('"Orçamento enviado": some "Acesso: {link}" e sobra a frase fechada', () => {
    expect(semLink(MODELOS_DO_BANCO.orcamentoEnviado, { cliente: 'Sandro Roberto', os: 'ORÇ-00123', valor: 1250 }))
      .toBe('Olá Sandro Roberto, segue o orçamento ORÇ-00123 no valor de 1.250,00.');
  });

  it('"Confirmação de OS": some "Acompanhe pelo link: {link}"', () => {
    expect(semLink(MODELOS_DO_BANCO.confirmacaoDeOs, { cliente: 'Sandro Roberto', os: 'OS-00100' }))
      .toBe('Olá Sandro Roberto, sua Ordem de Serviço OS-00100 foi aberta.');
  });

  it('"OS concluída": some "Detalhes: {link}" e o Total fica', () => {
    expect(semLink(MODELOS_DO_BANCO.osConcluida, { cliente: 'Sandro Roberto', os: 'OS-00100', valor: 980.5 }))
      .toBe('Olá Sandro Roberto, sua OS OS-00100 foi concluída. Total: 980,50.');
  });

  it('a URL já resolvida no texto sai com a frase dela', () => {
    expect(tirarLinkDoTexto(`Segue o orçamento. Acesso: ${URL_PUBLICA}`, URL_PUBLICA)).toBe('Segue o orçamento.');
    expect(tirarLinkDoTexto(`Segue o orçamento. Acesso: ${URL_PUBLICA}.`, URL_PUBLICA)).toBe('Segue o orçamento.');
  });

  it('a linha "Link online: …" some inteira, sem deixar linha em branco no fim', () => {
    expect(tirarLinkDoTexto(`Segue o ORÇ-00123.\n\nLink online: ${URL_PUBLICA}`, URL_PUBLICA)).toBe('Segue o ORÇ-00123.');
  });

  it('{{link}} (a outra sintaxe dos modelos) também sai', () => {
    expect(tirarLinkDoTexto('Segue a OS. Detalhes: {{ link }}', '')).toBe('Segue a OS.');
  });

  it('um /view/ de OUTRO documento ou domínio colado no texto também sai', () => {
    expect(tirarLinkDoTexto('Veja https://app.hbr.com.br/view/abc123 e me diga.', URL_PUBLICA)).toBe('Veja e me diga.');
  });

  it('apresentação depois de vírgula: a frase fecha com ponto', () => {
    expect(tirarLinkDoTexto('Sua OS foi aberta, acompanhe pelo link: {link}', '')).toBe('Sua OS foi aberta.');
  });

  it('parênteses que sobram vazios somem', () => {
    expect(tirarLinkDoTexto(`Detalhes (acesse: ${URL_PUBLICA}) abaixo.`, URL_PUBLICA)).toBe('Detalhes abaixo.');
  });

  it('texto sem link fica EXATAMENTE igual — inclusive quebras de linha', () => {
    const texto = 'Boa tarde!\n\n\nSegue o ORÇ-00123. Pix: 50.057.049/0001-59. Qualquer dúvida: wa.me/5547999990000';
    expect(tirarLinkDoTexto(texto, URL_PUBLICA)).toBe(texto);
    expect(temLinkNoTexto(texto, URL_PUBLICA)).toBe(false);
  });

  it('outros endereços (que não são o documento) ficam', () => {
    const texto = 'Nosso site: https://hbrsystems.com.br e o Instagram https://instagram.com/hbr';
    expect(tirarLinkDoTexto(texto, URL_PUBLICA)).toBe(texto);
  });

  it('temLinkNoTexto acusa {link} e a URL pública', () => {
    expect(temLinkNoTexto('Acesso: {link}', '')).toBe(true);
    expect(temLinkNoTexto(`Olha: ${URL_PUBLICA}`, URL_PUBLICA)).toBe(true);
  });
});

describe('o que sai em cada modo', () => {
  const MSG = 'Segue o ORÇ-00123, conforme solicitado. Qualquer dúvida, estamos à disposição.';

  it('PDF com a caixa desmarcada: documento, legenda = a mensagem, sem link', () => {
    const e = prepararEnvio({ modo: 'document', mensagem: MSG, enviarLink: false, urlPublica: URL_PUBLICA });
    expect(e).toMatchObject({ transporte: 'document', mensagem: MSG, legenda: MSG, linkVai: false, linkTirado: false });
  });

  it('PDF com a caixa marcada: a legenda ganha "Link online: …"', () => {
    const e = prepararEnvio({ modo: 'document', mensagem: MSG, enviarLink: true, urlPublica: URL_PUBLICA });
    expect(e.legenda).toBe(`${MSG}\n\nLink online: ${URL_PUBLICA}`);
    expect(e.linkVai).toBe(true);
  });

  it('PDF com a caixa marcada e o link já no texto: não repete', () => {
    const comLink = `${MSG} Acesso: ${URL_PUBLICA}`;
    expect(prepararEnvio({ modo: 'document', mensagem: comLink, enviarLink: true, urlPublica: URL_PUBLICA }).legenda).toBe(comLink);
  });

  it('Resumo com a caixa desmarcada viaja como TEXTO (antes ia como link, com a URL no fim)', () => {
    expect(prepararEnvio({ modo: 'resumo', mensagem: '*Valores*', enviarLink: false, urlPublica: URL_PUBLICA }).transporte).toBe('text');
  });

  it('Resumo com a caixa marcada viaja como link, como era', () => {
    expect(prepararEnvio({ modo: 'resumo', mensagem: '*Valores*', enviarLink: true, urlPublica: URL_PUBLICA }).transporte).toBe('link');
  });

  it('cobrança (só mensagem): texto; caixa marcada sem link público continua texto', () => {
    expect(prepararEnvio({ modo: 'texto', mensagem: MSG, enviarLink: false, urlPublica: URL_PUBLICA }).transporte).toBe('text');
    expect(prepararEnvio({ modo: 'texto', mensagem: MSG, enviarLink: true, urlPublica: '' }).transporte).toBe('text');
    expect(prepararEnvio({ modo: 'texto', mensagem: MSG, enviarLink: true, urlPublica: URL_PUBLICA }).transporte).toBe('link');
  });

  it('modo Link é a escolha de mandar o link: vai, e o texto não é mexido', () => {
    const comLink = `Veja: ${URL_PUBLICA}`;
    const e = prepararEnvio({ modo: 'link', mensagem: comLink, enviarLink: false, urlPublica: URL_PUBLICA });
    expect(e).toMatchObject({ transporte: 'link', mensagem: comLink, linkVai: true, linkTirado: false });
  });

  it('caixa desmarcada e URL no texto editado: sai ao enviar, e a tela sabe que saiu', () => {
    const e = prepararEnvio({ modo: 'document', mensagem: `${MSG}\nAcesse: ${URL_PUBLICA}`, enviarLink: false, urlPublica: URL_PUBLICA });
    expect(e.mensagem).toBe(MSG);
    expect(e.legenda).toBe(MSG);
    expect(e.linkTirado).toBe(true);
  });
});

describe('em que modo o diálogo abre', () => {
  it('PDF quando dá; senão Resumo; Link só se for o único; senão só a mensagem', () => {
    expect(modoInicial({ podePdf: true, podeResumo: true, podeLink: true })).toBe('document');
    expect(modoInicial({ podePdf: false, podeResumo: true, podeLink: true })).toBe('resumo');
    expect(modoInicial({ podePdf: false, podeResumo: false, podeLink: true })).toBe('link');
    expect(modoInicial({ podePdf: false, podeResumo: false, podeLink: false })).toBe('texto');
  });
});

describe('saudação', () => {
  it('período pelo horário de Brasília: até 12h bom dia, até 18h boa tarde, depois boa noite', () => {
    expect(periodoDoDia(emBrasilia(0, 30))).toBe('Bom dia');
    expect(periodoDoDia(emBrasilia(11, 59))).toBe('Bom dia');
    expect(periodoDoDia(emBrasilia(12, 0))).toBe('Boa tarde');
    expect(periodoDoDia(emBrasilia(17, 59))).toBe('Boa tarde');
    expect(periodoDoDia(emBrasilia(18, 0))).toBe('Boa noite');
    expect(periodoDoDia(emBrasilia(23, 10))).toBe('Boa noite');
  });

  it('o texto da abertura usa só o primeiro nome', () => {
    const t = emBrasilia(14);
    expect(textoDaSaudacao('nenhuma', 'Sandro Roberto', t)).toBe('');
    expect(textoDaSaudacao('ola', 'Sandro Roberto', t)).toBe('Olá, Sandro!');
    expect(textoDaSaudacao('periodo', 'Sandro Roberto', t)).toBe('Boa tarde, Sandro!');
  });

  it('sem nome no cadastro: "Olá!" / "Bom dia!"', () => {
    expect(textoDaSaudacao('ola', null, emBrasilia(9))).toBe('Olá!');
    expect(textoDaSaudacao('periodo', '', emBrasilia(9))).toBe('Bom dia!');
    expect(textoDaSaudacao('periodo', '  ', emBrasilia(20))).toBe('Boa noite!');
  });

  it('primeiro nome: tira o resto do cadastro e não grita', () => {
    expect(primeiroNome('Nelson - S.I. 7.8')).toBe('Nelson');
    expect(primeiroNome('ROBSON')).toBe('Robson');
    expect(primeiroNome('Flávio da Igreja')).toBe('Flávio');
    expect(primeiroNome('- 7.8')).toBe('');
  });

  it('o campo mostra as opções com o nome e o período de agora', () => {
    expect(opcoesDeSaudacao('Sandro Roberto', emBrasilia(14)).map((o) => o.label))
      .toEqual(['Sem saudação', 'Olá, Sandro!', 'Boa tarde, Sandro! (pelo horário)']);
  });
});

describe('corpo padrão', () => {
  it('orçamento: o número com o prefixo, sem "Orçamento ORÇ-" duplicado', () => {
    const corpo = corpoPadrao({ tipo: 'quote', numero: 'ORÇ-00555' });
    expect(corpo).toBe('Segue o ORÇ-00555, conforme solicitado. Qualquer dúvida, estamos à disposição.');
    expect(corpo).not.toMatch(/Orçamento ORÇ/i);
  });

  it('OS: "Segue a OS-00100", sem "OS OS-"', () => {
    expect(corpoPadrao({ tipo: 'service_order', numero: 'OS-00100' }))
      .toBe('Segue a OS-00100. Qualquer dúvida, estamos à disposição.');
  });

  it('cobrança: pela descrição, sem ponto dobrado', () => {
    expect(corpoPadrao({ tipo: 'billing', descricao: 'Saldo da OS-00100.' }))
      .toBe('Segue a cobrança referente a Saldo da OS-00100. Qualquer dúvida, estamos à disposição.');
  });

  it('número antigo sem prefixo ganha a palavra na frente', () => {
    expect(corpoPadrao({ tipo: 'quote', numero: '00555' })).toBe('Segue o orçamento 00555, conforme solicitado. Qualquer dúvida, estamos à disposição.');
    expect(corpoPadrao({ tipo: 'service_order', numero: '00100' })).toBe('Segue a OS 00100. Qualquer dúvida, estamos à disposição.');
  });

  it('padrão = sem saudação; com saudação, ela abre a mesma frase', () => {
    const base = { tipo: 'quote' as const, numero: 'ORÇ-00555', nomeDoCliente: 'Sandro Roberto', agora: emBrasilia(14) };
    expect(mensagemPadrao({ ...base, saudacao: 'nenhuma' }))
      .toBe('Segue o ORÇ-00555, conforme solicitado. Qualquer dúvida, estamos à disposição.');
    expect(mensagemPadrao({ ...base, saudacao: 'ola' }))
      .toBe('Olá, Sandro! Segue o ORÇ-00555, conforme solicitado. Qualquer dúvida, estamos à disposição.');
    expect(mensagemPadrao({ ...base, saudacao: 'periodo' }))
      .toBe('Boa tarde, Sandro! Segue o ORÇ-00555, conforme solicitado. Qualquer dúvida, estamos à disposição.');
  });
});

describe('trocar a saudação troca só a abertura', () => {
  const NOME = 'Sandro Roberto';
  const CORPO = 'Segue o ORÇ-00555 com a troca do inversor, como falamos.';

  it('sem → com, com → outra, com → sem; o corpo editado fica', () => {
    const comOla = trocarSaudacao(CORPO, 'Olá, Sandro!', NOME);
    expect(comOla).toBe(`Olá, Sandro! ${CORPO}`);
    const comTarde = trocarSaudacao(comOla, 'Boa tarde, Sandro!', NOME);
    expect(comTarde).toBe(`Boa tarde, Sandro! ${CORPO}`);
    expect(trocarSaudacao(comTarde, '', NOME)).toBe(CORPO);
  });

  it('a mesma saudação de novo não muda nada', () => {
    const m = `Boa tarde, Sandro! ${CORPO}`;
    expect(trocarSaudacao(m, 'Boa tarde, Sandro!', NOME)).toBe(m);
  });

  it('a saudação de um modelo ("Olá Sandro Roberto, segue…") sai com o nome completo', () => {
    expect(trocarSaudacao('Olá Sandro Roberto, segue o orçamento ORÇ-00123.', '', NOME)).toBe('Segue o orçamento ORÇ-00123.');
    expect(trocarSaudacao('Olá Sandro Roberto, segue o orçamento ORÇ-00123.', 'Bom dia, Sandro!', NOME))
      .toBe('Bom dia, Sandro! Segue o orçamento ORÇ-00123.');
  });

  it('não confunde palavra com saudação ("Oito…") nem engole o resto da frase', () => {
    expect(trocarSaudacao('Oito itens no orçamento.', 'Olá, Sandro!', NOME)).toBe('Olá, Sandro! Oito itens no orçamento.');
    expect(trocarSaudacao('Olá, tudo bem? Segue o ORÇ-00555.', 'Boa tarde, Sandro!', NOME))
      .toBe('Boa tarde, Sandro! Tudo bem? Segue o ORÇ-00555.');
  });

  it('quebra de linha depois da saudação é mantida', () => {
    expect(trocarSaudacao('Bom dia, Sandro!\n\nSegue o ORÇ-00555.', 'Olá, Sandro!', NOME)).toBe('Olá, Sandro!\n\nSegue o ORÇ-00555.');
  });

  it('no resumo de valores a saudação é a linha abaixo do cabeçalho — igual ao que o resumo monta', () => {
    const input = {
      numero: 'ORÇ-00123',
      clienteNome: NOME,
      ativoNome: 'Lancha Exemplo',
      orcamento: { labor_cost_total: 1000, parts_cost_total: 500, grand_total: 1500 },
      empresa: { nome: 'HBR Marine' },
    };
    const sem = buildQuoteWhatsAppSummary({ ...input, saudacao: '' });
    const comTarde = buildQuoteWhatsAppSummary({ ...input, saudacao: 'Boa tarde, Sandro!' });
    const comOla = buildQuoteWhatsAppSummary({ ...input, saudacao: 'Olá, Sandro!' });
    expect(trocarSaudacao(sem, 'Boa tarde, Sandro!', NOME)).toBe(comTarde);
    expect(trocarSaudacao(comTarde, 'Olá, Sandro!', NOME)).toBe(comOla);
    expect(trocarSaudacao(comOla, '', NOME)).toBe(sem);
  });

  it('resumo sem embarcação: a linha entra e sai sem bagunçar o espaçamento', () => {
    const input = { numero: 'ORÇ-00123', clienteNome: NOME, orcamento: { labor_cost_total: 1000, grand_total: 1000 } };
    const sem = buildQuoteWhatsAppSummary({ ...input, saudacao: '' });
    const com = buildQuoteWhatsAppSummary({ ...input, saudacao: 'Olá, Sandro!' });
    expect(trocarSaudacao(sem, 'Olá, Sandro!', NOME)).toBe(com);
    expect(trocarSaudacao(com, '', NOME)).toBe(sem);
  });
});
