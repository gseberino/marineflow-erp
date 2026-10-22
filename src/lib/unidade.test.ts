// Regra única de nomes da unidade (decisão 9, 21/10/2026): o tipo como rótulo quando há uma
// unidade à vista; "Embarcação ou veículo" quando não há.
import { describe, it, expect } from 'vitest';
import {
  TERMO_GERAL, TIPOS_DE_UNIDADE, camposDoTipo, campoDaUnidade, comprimentoDoTipo, emojiDaUnidade, grupoDoTipo,
  linhaDaUnidade, metrosParaPes, nomeDaUnidade, pesParaMetros, rotuloDaIdentificacao, rotuloDaUnidade,
  sinonimosDoTipo, suaUnidade, tipoDoSeletor, unidadeNaFrase,
} from './unidade';

const daily = { name: 'Iveco Daily', asset_type: 'Motorhome', manufacturer: 'Iveco', model: 'Daily 55C17', hull_id_or_registration: 'ABC1D23' };
const netuno = { name: 'Netuno II', asset_type: 'Lancha', manufacturer: 'Schaefer', model: '400', hull_id_or_registration: '441-0012345' };

describe('campoDaUnidade / linhaDaUnidade', () => {
  it('o tipo é o rótulo; nome, modelo e identificação certa para o tipo', () => {
    expect(linhaDaUnidade(daily)).toBe('Motorhome: Iveco Daily · Iveco Daily 55C17 · placa ABC1D23');
    expect(linhaDaUnidade(netuno)).toBe('Lancha: Netuno II · Schaefer 400 · inscrição 441-0012345');
  });

  it('o modelo não se repete quando o nome já o contém', () => {
    expect(linhaDaUnidade({ name: 'Iveco Daily 55C17', asset_type: 'Motorhome', manufacturer: 'Iveco', model: 'Daily 55C17' }))
      .toBe('Motorhome: Iveco Daily 55C17');
  });

  it('nunca "Motorhome: Motorhome": nome igual ao tipo e nada mais usa o termo geral', () => {
    expect(campoDaUnidade({ name: 'Motorhome', asset_type: 'Motorhome' })).toEqual({ rotulo: TERMO_GERAL, valor: 'Motorhome' });
    expect(linhaDaUnidade({ name: 'motorhome', asset_type: 'Motorhome' })).toBe('Embarcação ou veículo: Motorhome');
  });

  it('nome igual ao tipo, mas com modelo: o tipo volta a ser o rótulo', () => {
    expect(linhaDaUnidade({ name: 'Motorhome', asset_type: 'Motorhome', manufacturer: 'Iveco', model: 'Daily' }))
      .toBe('Motorhome: Iveco Daily');
  });

  it('sem tipo (ou "Outro"): o termo geral e o nome', () => {
    expect(linhaDaUnidade({ name: 'Netuno II', asset_type: null })).toBe('Embarcação ou veículo: Netuno II');
    expect(linhaDaUnidade({ name: 'Netuno II', asset_type: 'Outro' })).toBe('Embarcação ou veículo: Netuno II');
  });

  it('identificação de fora quando o documento já a mostra; placa igual ao nome não repete', () => {
    expect(linhaDaUnidade(daily, { comIdentificacao: false, comModelo: false })).toBe('Motorhome: Iveco Daily');
    expect(linhaDaUnidade({ name: 'ABC1D23', asset_type: 'Trailer', hull_id_or_registration: 'abc1d23' })).toBe('Trailer: ABC1D23');
  });

  it('sem unidade: rótulo geral e linha vazia', () => {
    expect(campoDaUnidade(null)).toEqual({ rotulo: TERMO_GERAL, valor: '' });
    expect(linhaDaUnidade(undefined)).toBe('');
  });
});

describe('rótulos', () => {
  it('rótulo da unidade e da identificação por tipo', () => {
    expect(rotuloDaUnidade('Trailer')).toBe('Trailer');
    expect(rotuloDaUnidade('')).toBe(TERMO_GERAL);
    expect(rotuloDaIdentificacao('Motorhome')).toBe('Placa');
    expect(rotuloDaIdentificacao('Camper')).toBe('Placa');
    expect(rotuloDaIdentificacao('Catamarã')).toBe('Inscrição');
    expect(rotuloDaIdentificacao('Jet Ski')).toBe('Inscrição');
    expect(rotuloDaIdentificacao('Equipamento')).toBe('Nº de série');
    expect(rotuloDaIdentificacao(null)).toBe('Inscrição / placa');
  });

  it('nome curto (já usado na troca)', () => {
    expect(nomeDaUnidade(daily)).toBe('Motorhome Iveco Daily');
    expect(nomeDaUnidade({ name: 'Motorhome', asset_type: 'Motorhome' })).toBe('Motorhome');
  });
});

describe('nome que já começa pelo tipo ("Trailer Darlan", 6 cadastros em 21/10/2026)', () => {
  const darlan = { name: 'Trailer Darlan', asset_type: 'Trailer' };
  it('o tipo não sai duas vezes em lugar nenhum', () => {
    expect(nomeDaUnidade(darlan)).toBe('Trailer Darlan');
    expect(unidadeNaFrase(darlan, 'de')).toBe('do trailer Darlan');
    expect(linhaDaUnidade(darlan)).toBe('Trailer: Darlan');
    expect(nomeDaUnidade({ name: 'motorhome NVT', asset_type: 'Motorhome' })).toBe('Motorhome NVT');
  });
  it('só tira o tipo inteiro seguido de espaço ("Lanchão" não é "Lancha")', () => {
    expect(nomeDaUnidade({ name: 'Lanchão do Zé', asset_type: 'Lancha' })).toBe('Lancha Lanchão do Zé');
  });
  it('sem nada, o termo geral', () => {
    expect(nomeDaUnidade(null)).toBe(TERMO_GERAL);
    expect(nomeDaUnidade({ name: '', asset_type: null })).toBe(TERMO_GERAL);
  });
});

describe('tipos novos (decisão 10, 22/10/2026)', () => {
  it('"Outra embarcação" e "Outro veículo" viram o rótulo do grupo', () => {
    expect(linhaDaUnidade({ name: 'Netuno', asset_type: 'Outra embarcação' })).toBe('Embarcação: Netuno');
    expect(linhaDaUnidade({ name: 'Kombi', asset_type: 'Outro veículo' })).toBe('Veículo: Kombi');
    expect(unidadeNaFrase({ name: 'Netuno', asset_type: 'Outra embarcação' }, 'em')).toBe('na embarcação Netuno');
    expect(unidadeNaFrase({ name: 'Kombi', asset_type: 'Outro veículo' }, 'de')).toBe('do veículo Kombi');
    expect(rotuloDaIdentificacao('Outro veículo')).toBe('Placa');
  });
  it('"Jet Ski" antigo vale como moto aquática; o seletor mostra o valor novo', () => {
    expect(linhaDaUnidade({ name: 'Azul', asset_type: 'Jet Ski' })).toBe('Moto aquática: Azul');
    expect(unidadeNaFrase({ name: 'Azul', asset_type: 'Jet Ski' }, 'em')).toBe('na moto aquática Azul');
    expect(tipoDoSeletor('Jet Ski')).toBe('Moto aquática');
    expect(tipoDoSeletor('Outro')).toBe('');
    expect(tipoDoSeletor('motorhome')).toBe('Motorhome');
    expect(sinonimosDoTipo('Moto aquática')).toContain('jet ski');
    expect(sinonimosDoTipo('Motorhome')).toContain('van');
  });
  it('todo tipo da lista tem grupo (nenhum cai em "outro" sem querer), salvo Equipamento', () => {
    for (const g of TIPOS_DE_UNIDADE) for (const t of g.tipos) {
      if (t.valor === 'Equipamento') continue;
      expect(grupoDoTipo(t.valor), t.valor).toBe(g.grupo === 'Embarcações' ? 'embarcacao' : 'veiculo');
    }
  });
});

describe('falando com o cliente: "seu motorhome", "sua lancha" (dono, 22/10/2026)', () => {
  it('possessivo pelo gênero do tipo, com preposição', () => {
    expect(suaUnidade(daily)).toBe('seu motorhome');
    expect(suaUnidade(netuno)).toBe('sua lancha');
    expect(suaUnidade({ asset_type: 'Trailer' }, 'de')).toBe('do seu trailer');
    expect(suaUnidade(daily, 'em')).toBe('no seu motorhome');
    expect(suaUnidade(netuno, 'em')).toBe('na sua lancha');
    expect(suaUnidade({ asset_type: 'Moto aquática' }, 'para')).toBe('para a sua moto aquática');
    expect(suaUnidade(null)).toBe('sua embarcação ou veículo');
  });
  it('com o nome (cliente com duas unidades precisa saber qual), sem repetir o tipo', () => {
    expect(suaUnidade(daily, 'em', { comNome: true })).toBe('no seu motorhome Iveco Daily');
    expect(suaUnidade(netuno, 'de', { comNome: true })).toBe('da sua lancha Netuno II');
    expect(suaUnidade({ name: 'Trailer Darlan', asset_type: 'Trailer' }, 'de', { comNome: true })).toBe('do seu trailer Darlan');
    expect(suaUnidade({ name: 'Motorhome', asset_type: 'Motorhome' }, 'de', { comNome: true })).toBe('do seu motorhome');
  });
  it('emoji pelo grupo: nada de barquinho para motorhome', () => {
    expect(emojiDaUnidade('Lancha')).toBe('🛥️');
    expect(emojiDaUnidade('Motorhome')).toBe('🚐');
    expect(emojiDaUnidade('Equipamento')).toBe('');
  });
});

describe('campos por tipo (dono, 22/10/2026: "ajustar conforme cada tipo")', () => {
  it('barco: tudo, em pés; veículo: sem campos náuticos, em metros; equipamento: sem comprimento e motores', () => {
    expect(camposDoTipo('Lancha')).toMatchObject({ nauticos: true, comprimento: 'pes', motores: true, rotuloOndeFica: 'Marina' });
    expect(camposDoTipo('Motorhome')).toMatchObject({ nauticos: false, comprimento: 'metros', motores: true, rotuloOndeFica: 'Onde fica' });
    expect(camposDoTipo('Equipamento')).toMatchObject({ nauticos: false, comprimento: null, motores: false });
    expect(camposDoTipo(null)).toMatchObject({ nauticos: true, comprimento: 'pes' });
  });
  it('comprimento: pés para barco, metros para veículo (o banco guarda pés)', () => {
    expect(comprimentoDoTipo(40, 'Lancha')).toBe('40 pés');
    expect(comprimentoDoTipo(40, 'Motorhome')).toBe('12,2 m');
    expect(comprimentoDoTipo(40, 'Equipamento')).toBe('');
    expect(comprimentoDoTipo(null, 'Lancha')).toBe('');
    expect(metrosParaPes(pesParaMetros(40))).toBeCloseTo(40, 1);
  });
});

describe('unidadeNaFrase', () => {
  it('artigo e preposição pelo gênero do tipo, tipo em minúscula', () => {
    expect(unidadeNaFrase(daily, 'em')).toBe('no motorhome Iveco Daily');
    expect(unidadeNaFrase(netuno, 'em')).toBe('na lancha Netuno II');
    expect(unidadeNaFrase(netuno, 'de')).toBe('da lancha Netuno II');
    expect(unidadeNaFrase(daily)).toBe('o motorhome Iveco Daily');
    expect(unidadeNaFrase({ name: 'Turiscar', asset_type: 'Trailer' }, 'para')).toBe('para o trailer Turiscar');
  });

  it('nome igual ao tipo não repete; sem tipo usa o termo geral', () => {
    expect(unidadeNaFrase({ name: 'Motorhome', asset_type: 'Motorhome' }, 'em')).toBe('no motorhome');
    expect(unidadeNaFrase({ name: 'Netuno II', asset_type: null }, 'em')).toBe('na embarcação ou veículo Netuno II');
  });
});
