import { describe, it, expect } from 'vitest';
import { tipoDeEquipamento, blocosDaFolha, buildCommissioningSheetHtml } from './folha-comissionamento';

describe('folha de comissionamento — reconhece o equipamento pelo nome da peça', () => {
  // Nomes reais do catálogo da HBR (01/10/2026).
  it.each([
    ['Carregador DC/DC - Para Baterias de Lítio Victron', 'dcdc'],
    ['Conversor de Bateria DC-DC 12V - 30A', 'dcdc'],
    ['Carregador de Bateria Victron 12V - 50A', 'carregador'],
    ['Bateria de Litio 12V - 314Ah', 'bateria_litio'],
    ['Controlador Solar MPPT 100/30', 'mppt'],
    ['Inversor Senoidal 2000W 12V', 'inversor'],
  ])('%s → %s', (nome, tipo) => {
    expect(tipoDeEquipamento(nome)).toBe(tipo);
  });

  it.each([
    'Conversor de Energia 12V p/ Starlink V4 - G3',
    'Bateria Estacionária 12V/185Ah Moura',
    'Kit Porta Fusível + Fusível Midi - 60A',
    'Sensor de Nível de Gás Bluetooth para Victron',
  ])('%s não vira bloco', (nome) => {
    expect(tipoDeEquipamento(nome)).toBeNull();
  });
});

describe('folha de comissionamento — montada a partir da OS', () => {
  // As peças da OS-00034 (camper, instalação de lítio).
  const os34 = [
    { name: 'Ar Condicionado 12V - Stonni Night Power', quantity: 1 },
    { name: 'Bateria de Litio 12V - 314Ah', quantity: 2 },
    { name: 'Carregador de Bateria Victron 12V - 50A', quantity: 1 },
    { name: 'Kit Porta Fusível + Fusível Midi  - 60A', quantity: 3 },
    { name: 'Conversor de Bateria DC-DC 12V - 30A', quantity: 1 },
  ];

  it('um bloco por aparelho, na ordem de recorrência; as baterias juntas', () => {
    const blocos = blocosDaFolha(os34);
    expect(blocos.map((b) => b.tipo)).toEqual(['dcdc', 'carregador', 'bateria_litio']);
    expect(blocos[2].modelos).toHaveLength(2);
  });

  it('dois DC-DC na OS dão dois blocos', () => {
    const blocos = blocosDaFolha([{ name: 'Carregador DC/DC - Para Baterias de Lítio Victron', quantity: 2 }]);
    expect(blocos.filter((b) => b.tipo === 'dcdc')).toHaveLength(2);
  });

  it('sem equipamento reconhecido, sai o modelo inteiro', () => {
    expect(blocosDaFolha([{ name: 'Materiais diversos' }]).map((b) => b.tipo))
      .toEqual(['dcdc', 'carregador', 'inversor', 'mppt', 'bateria_litio']);
  });

  it('identificação preenchida, sem preço, sem valor inventado', () => {
    const html = buildCommissioningSheetHtml(
      { orderNumber: 'OS-00034', vehicle: 'Camper', clientName: 'Cliente', technicianName: 'Roberto' },
      os34,
    );
    expect(html).toContain('OS-00034');
    expect(html).toContain('Camper');
    expect(html).toContain('Roberto');
    expect(html).toContain('Conversor de Bateria DC-DC 12V - 30A');
    expect(html).toContain('Bateria de Litio 12V - 314Ah');
    expect(html).not.toContain('R$');
    // Toda linha de valor diz de onde ele vem: a coluna é do manual do modelo.
    expect(html).toContain('Esperado (manual, pág.)');
    expect(html).not.toMatch(/\b\d+\s?N·m\b/);
    expect(html).toContain('Fora do esperado? Não entregue.');
  });
});
