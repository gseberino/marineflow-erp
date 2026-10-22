// Quando a troca da embarcação/veículo de uma OS passa direto e o que a confirmação diz (21/10/2026).
import { describe, it, expect } from 'vitest';
import {
  descricaoDaTrocaDeEmbarcacao, grupoDoTipo, motivosDaTrocaDeEmbarcacao, nomeDaUnidade, tituloDaTrocaDeEmbarcacao,
} from './troca-de-embarcacao';

const lancha = { name: 'Netuno II', asset_type: 'Lancha' };
const veleiro = { name: 'Brisa', asset_type: 'Veleiro' };
const motorhome = { name: 'Iveco Daily', asset_type: 'Motorhome' };
const salva = { salva: true, temLevantamento: false as boolean | null };

describe('motivosDaTrocaDeEmbarcacao', () => {
  it('OS nova não pede nada, mesmo com tudo', () => {
    expect(motivosDaTrocaDeEmbarcacao({ salva: false, temLevantamento: true, contatoSolicitante: 'Carlos', quoteStatus: 'approved' }, lancha, motorhome)).toEqual([]);
  });

  it('OS salva sem nada ligado e do mesmo grupo: troca direto (marina e local não contam)', () => {
    expect(motivosDaTrocaDeEmbarcacao({ ...salva, quoteStatus: 'draft' }, lancha, veleiro)).toEqual([]);
  });

  it('cada perda ou impacto vira uma frase, com o gênero da unidade antiga (feminino: lancha)', () => {
    const m = motivosDaTrocaDeEmbarcacao({
      salva: true, documento: 'orçamento', contatoSolicitante: 'Carlos', temLevantamento: true, quoteStatus: 'sent', checkInFeito: true,
    }, lancha, motorhome);
    expect(m).toEqual([
      'Sai o solicitante Carlos, que é contato da antiga.',
      'O levantamento feito na antiga fica com ela: este orçamento vai precisar de outro.',
      'O cliente já recebeu este orçamento: reenvie depois da troca.',
      'O trabalho já começou (check-in feito).',
      'Muda o tipo, de lancha para motorhome: confira serviços, peças e roteiro.',
    ]);
  });

  it('masculino para motorhome, veleiro, trailer…', () => {
    const m = motivosDaTrocaDeEmbarcacao({ salva: true, contatoSolicitante: 'Carlos', temLevantamento: true }, motorhome, null);
    expect(m).toEqual([
      'Sai o solicitante Carlos, que é contato do antigo.',
      'O levantamento feito no antigo fica com ele: esta OS vai precisar de outro.',
    ]);
  });

  it('não conseguir conferir o levantamento é motivo, nunca "passa"', () => {
    expect(motivosDaTrocaDeEmbarcacao({ salva: true, temLevantamento: null }, lancha, veleiro))
      .toEqual(['Não deu para conferir se esta OS tem levantamento.']);
  });

  it('unidade atual desconhecida (lista carregando ou com erro) numa OS salva pede confirmação', () => {
    expect(motivosDaTrocaDeEmbarcacao(salva, undefined, veleiro))
      .toEqual(['Não deu para conferir a embarcação ou veículo atual.']);
  });

  it('assinatura: pede nova assinatura (e não repete o "já recebeu")', () => {
    expect(motivosDaTrocaDeEmbarcacao({ ...salva, assinadaPeloCliente: true, quoteStatus: 'approved' }, lancha, veleiro))
      .toEqual(['O cliente já assinou esta OS: depois da troca, peça uma nova assinatura.']);
  });

  it('convertida em OS ou confirmação de agendamento pedida contam como "já foi ao cliente"', () => {
    expect(motivosDaTrocaDeEmbarcacao({ ...salva, convertidaEmOS: true }, lancha, veleiro)).toHaveLength(1);
    expect(motivosDaTrocaDeEmbarcacao({ ...salva, confirmacaoDoAgendamentoPedida: true }, lancha, veleiro)).toHaveLength(1);
  });

  it('solicitante sem nome conhecido (contato inativo, lista carregando) ainda é motivo', () => {
    expect(motivosDaTrocaDeEmbarcacao({ ...salva, contatoSolicitante: '' }, lancha, veleiro))
      .toEqual(['Sai o solicitante, que é contato da antiga.']);
    expect(motivosDaTrocaDeEmbarcacao({ ...salva, contatoSolicitante: null }, lancha, veleiro)).toEqual([]);
  });

  it('cadastro novo (novo = null) não compara tipo', () => {
    expect(motivosDaTrocaDeEmbarcacao({ ...salva, contatoSolicitante: 'Carlos' }, lancha, null)).toHaveLength(1);
  });
});

describe('textos e tipos', () => {
  it('grupo do tipo', () => {
    expect(grupoDoTipo('Lancha')).toBe('embarcacao');
    expect(grupoDoTipo('Jet Ski')).toBe('embarcacao');
    expect(grupoDoTipo('Motorhome')).toBe('veiculo');
    expect(grupoDoTipo('Automóvel')).toBe('veiculo');
    expect(grupoDoTipo('Equipamento')).toBe('outro');
    expect(grupoDoTipo(null)).toBe('outro');
  });

  it('nome da unidade: tipo + nome, sem repetir; "Outro" não entra no nome', () => {
    expect(nomeDaUnidade(lancha)).toBe('Lancha Netuno II');
    expect(nomeDaUnidade({ name: 'Motorhome', asset_type: 'Motorhome' })).toBe('Motorhome');
    expect(nomeDaUnidade({ name: 'Netuno II', asset_type: null })).toBe('Netuno II');
    expect(nomeDaUnidade({ name: 'HOMEBUS', asset_type: 'Outro' })).toBe('HOMEBUS');
  });

  it('título com o tipo da unidade atual (decisão 9); sem tipo ou sem a atual, o termo geral', () => {
    expect(tituloDaTrocaDeEmbarcacao('OS', lancha)).toBe('Trocar a lancha desta OS?');
    expect(tituloDaTrocaDeEmbarcacao('orçamento', motorhome)).toBe('Trocar o motorhome deste orçamento?');
    expect(tituloDaTrocaDeEmbarcacao('OS', { name: 'HOMEBUS', asset_type: 'Outro' })).toBe('Trocar a embarcação ou veículo desta OS?');
    expect(tituloDaTrocaDeEmbarcacao('OS')).toBe('Trocar a embarcação ou veículo desta OS?');
    expect(tituloDaTrocaDeEmbarcacao('orçamento', null)).toBe('Trocar a embarcação ou veículo deste orçamento?');
  });

  it('descrição: de qual para qual, com o tipo; atual desconhecida não vira "De a unidade escolhida"', () => {
    expect(descricaoDaTrocaDeEmbarcacao(lancha, motorhome, ['Frase.'])).toBe('De Lancha Netuno II para Motorhome Iveco Daily. Frase.');
    expect(descricaoDaTrocaDeEmbarcacao(lancha, null, [])).toBe('De Lancha Netuno II para um cadastro novo.');
    expect(descricaoDaTrocaDeEmbarcacao(undefined, veleiro, [])).toBe('Da embarcação ou veículo atual para Veleiro Brisa.');
  });
});
