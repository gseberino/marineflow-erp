// Dados fiscais da empresa (D33, 01/10/2026): formulário a partir do cadastro e conversão para o banco.
import { describe, it, expect } from 'vitest';
import { formularioDaEmpresa, payloadDasConfiguracoes } from './fiscal-configuracao';

describe('formularioDaEmpresa', () => {
  it('sem cadastro: os padrões (Simples, CRT 1, série 1, NFS-e nacional, IM no CNC)', () => {
    expect(formularioDaEmpresa(null)).toMatchObject({
      tax_regime: 'simples', crt: 1, nfe_series_producao: 1, nfse_standard: 'nacional',
      nfse_total_tax_rate_sn: '', nfse_municipal_registration_in_cnc: true, nfse_default_series: 1,
    });
  });

  it('com cadastro: copia os campos; zero e false são valores, não "vazio"', () => {
    const f = formularioDaEmpresa({
      legal_name: 'HBR MARINE', cnpj: '12345678000199', crt: 0, state_code: 'SC',
      nfse_total_tax_rate_sn: 0, nfse_municipal_registration_in_cnc: false, nfe_series_producao: 2,
    });
    expect(f).toMatchObject({
      legal_name: 'HBR MARINE', cnpj: '12345678000199', crt: 0, state_code: 'SC',
      nfse_total_tax_rate_sn: 0, nfse_municipal_registration_in_cnc: false, nfe_series_producao: 2,
    });
  });
});

describe('payloadDasConfiguracoes', () => {
  const base = formularioDaEmpresa({ state_code: 'SC' });
  const agora = new Date('2026-10-01T12:00:00Z');

  it('vazio da NFS-e vira null; série vazia vira 1', () => {
    const p = payloadDasConfiguracoes({ ...base, ibge_city_code: '  ', nfse_total_tax_rate_sn: '', nfse_default_series: 0 }, agora);
    expect(p.ibge_city_code).toBeNull();
    expect(p.nfse_total_tax_rate_sn).toBeNull();
    expect(p.nfse_default_series).toBe(1);
    expect(p.updated_at).toBe('2026-10-01T12:00:00.000Z');
  });

  it('pTotTribSN em texto vira número; zero continua zero', () => {
    expect(payloadDasConfiguracoes({ ...base, nfse_total_tax_rate_sn: '6.54' }, agora).nfse_total_tax_rate_sn).toBe(6.54);
    expect(payloadDasConfiguracoes({ ...base, nfse_total_tax_rate_sn: 0 }, agora).nfse_total_tax_rate_sn).toBe(0);
  });

  it('código IBGE aparado', () => {
    expect(payloadDasConfiguracoes({ ...base, ibge_city_code: ' 4205407 ' }, agora).ibge_city_code).toBe('4205407');
  });
});
