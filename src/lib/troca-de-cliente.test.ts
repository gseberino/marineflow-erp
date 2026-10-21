// Textos da confirmação de troca de cliente e as regras de trocar cliente/embarcação no formulário.
import { describe, it, expect } from 'vitest';
import {
  descricaoDaTroca, perdasDaTrocaDeCliente, temPerda, tituloDaTroca, trocarClienteNoForm, trocarEmbarcacaoNoForm,
} from './troca-de-cliente';

describe('textos da troca de cliente', () => {
  it('título diz OS ou orçamento', () => {
    expect(tituloDaTroca('OS')).toBe('Trocar o cliente desta OS?');
    expect(tituloDaTroca('orçamento')).toBe('Trocar o cliente deste orçamento?');
  });

  it('plural, singular e nomes que faltam', () => {
    expect(descricaoDaTroca('João', 'Maria', { embarcacao: 'Netuno II', solicitante: 'Pedro' }))
      .toBe('De João para Maria. Saem: a embarcação Netuno II e o solicitante Pedro.');
    expect(descricaoDaTroca('João', 'Maria', { embarcacao: 'Netuno II' }))
      .toBe('De João para Maria. Sai: a embarcação Netuno II.');
    expect(descricaoDaTroca('João', 'Maria', { solicitante: '' }))
      .toBe('De João para Maria. Sai: o solicitante escolhido.');
    expect(descricaoDaTroca('João', null, { embarcacao: '' }))
      .toBe('De João para um cliente novo. Sai: a embarcação escolhida.');
    expect(descricaoDaTroca(null, 'Maria', { embarcacao: 'Netuno II' }))
      .toBe('Do cliente atual para Maria. Sai: a embarcação Netuno II.');
    expect(descricaoDaTroca('João', 'Maria', { embarcacao: 'Netuno II', solicitante: 'Pedro', marina: 'Itajaí', local: true }))
      .toBe('De João para Maria. Saem: a embarcação Netuno II, o solicitante Pedro, a marina sugerida (Itajaí) e o local e acesso da embarcação.');
  });

  it('a confirmação lista exatamente o que a troca tira (mesmos critérios)', () => {
    const barco = { marina_id: 'm1', access_notes: 'Vaga B12' };
    const f = { client_id: 'c1', vessel_id: 'v1', marina_id: 'm1', requested_by_contact_id: 'k1', requested_by_name: 'Pedro', site_access: 'Vaga B12' };
    const nomes = { embarcacao: 'Netuno II', solicitante: 'Pedro Marinheiro', marina: 'Itajaí' };
    expect(perdasDaTrocaDeCliente(f, barco, nomes))
      .toEqual({ embarcacao: 'Netuno II', solicitante: 'Pedro Marinheiro', marina: 'Itajaí', local: true });
    // marina e local escolhidos à mão não saem — e não aparecem
    const mexido = { ...f, marina_id: 'm9', site_access: 'Rampa do clube' };
    expect(perdasDaTrocaDeCliente(mexido, barco, nomes)).toMatchObject({ marina: null, local: false });
    const depois = trocarClienteNoForm(mexido, 'c2', barco);
    expect(depois.marina_id).toBe('m9');
    expect(depois.site_access).toBe('Rampa do clube');
  });

  it('perda só quando há embarcação ou solicitante', () => {
    expect(temPerda(undefined)).toBe(false);
    expect(temPerda({})).toBe(false);
    expect(temPerda({ embarcacao: null, solicitante: null })).toBe(false);
    expect(temPerda({ embarcacao: '' })).toBe(true);
  });
});

describe('trocarClienteNoForm', () => {
  const barco = { marina_id: 'm1', access_notes: 'Vaga B12, chave na portaria' };
  const f = {
    client_id: 'c1', vessel_id: 'v1', marina_id: 'm1', requested_by_contact_id: 'k1',
    requested_by_name: 'Pedro', site_access: 'Vaga B12, chave na portaria', problem_description: 'x',
  };

  it('embarcação e solicitante saem; marina e local que eram sugestão do barco saem junto; o resto fica', () => {
    expect(trocarClienteNoForm(f, 'c2', barco)).toEqual({
      ...f, client_id: 'c2', vessel_id: '', requested_by_contact_id: '', requested_by_name: '',
      marina_id: '', site_access: '',
    });
  });

  it('marina escolhida à mão e local escrito à mão ficam', () => {
    const mexido = { ...f, marina_id: 'm9', site_access: 'Casa do cliente, portão azul' };
    const r = trocarClienteNoForm(mexido, 'c2', barco);
    expect(r.marina_id).toBe('m9');
    expect(r.site_access).toBe('Casa do cliente, portão azul');
  });

  it('trocar o cliente e escolher o barco dele: entram a marina e o acesso do barco novo', () => {
    const barcoDaMaria = { marina_id: 'm2', access_notes: 'Seco, galpão 3' };
    const depois = trocarEmbarcacaoNoForm(trocarClienteNoForm(f, 'c2', barco), 'v2', undefined, barcoDaMaria);
    expect(depois).toMatchObject({ client_id: 'c2', vessel_id: 'v2', marina_id: 'm2', site_access: 'Seco, galpão 3' });
  });
});

describe('trocarEmbarcacaoNoForm', () => {
  const antigo = { marina_id: 'm1', access_notes: 'Vaga B12' };
  const novo = { marina_id: 'm2', access_notes: 'Seco, galpão 3' };
  const f = {
    vessel_id: 'v1', marina_id: 'm1', requested_by_contact_id: 'k1', requested_by_name: 'Pedro', site_access: 'Vaga B12',
  };

  it('a mesma embarcação de novo não muda nada (nem o solicitante)', () => {
    expect(trocarEmbarcacaoNoForm(f, 'v1', antigo, antigo)).toBe(f);
  });

  it('outra embarcação: contato sai, marina e local sugeridos acompanham', () => {
    expect(trocarEmbarcacaoNoForm(f, 'v2', antigo, novo)).toEqual({
      vessel_id: 'v2', marina_id: 'm2', requested_by_contact_id: '', requested_by_name: '', site_access: 'Seco, galpão 3',
    });
  });

  it('marina escolhida à mão e local escrito à mão ficam', () => {
    const mexido = { ...f, marina_id: 'm9', site_access: 'Rampa do clube' };
    const r = trocarEmbarcacaoNoForm(mexido, 'v2', antigo, novo);
    expect(r.marina_id).toBe('m9');
    expect(r.site_access).toBe('Rampa do clube');
  });

  it('nome digitado à mão (sem contato) fica', () => {
    const digitado = { ...f, requested_by_contact_id: '', requested_by_name: 'Everton' };
    expect(trocarEmbarcacaoNoForm(digitado, 'v2', antigo, novo).requested_by_name).toBe('Everton');
  });

  it('marina vazia recebe a do barco novo', () => {
    expect(trocarEmbarcacaoNoForm({ ...f, marina_id: '' }, 'v2', antigo, novo).marina_id).toBe('m2');
  });

  it('barco novo sem marina: a sugerida pelo barco antigo sai; a escolhida à mão fica', () => {
    const semMarina = { marina_id: null, access_notes: null };
    expect(trocarEmbarcacaoNoForm(f, 'v2', antigo, semMarina).marina_id).toBe('');
    expect(trocarEmbarcacaoNoForm({ ...f, marina_id: 'm9' }, 'v2', antigo, semMarina).marina_id).toBe('m9');
  });
});
