// Gerar cobranças da OS: leitura que falha PARA, em vez de seguir com "nada" (19/11/2026).
//  1. As cobranças existentes ilegíveis: não gera (seria cobrança em dobro).
//  2. O preset ilegível: não gera (ignorava auto_generate_collections=false e virava "à vista").
//  3. Parcela que não grava é contada em `failed` (o caller avisa).
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', async () => ({ supabase: (await import('@/test/banco-falso')).supabaseFalso }));

import { generateCollectionsFromOS } from './generate-collections';
import { banco, ok, falha, reiniciarBanco, chamadasA } from '@/test/banco-falso';

const os = { id: 'so-1', grand_total: 1000, client_id: 'c1', payment_condition_preset_id: 'p1', clients: { name: 'Ana' } };
const entrada = { serviceOrderId: 'so-1', approvalDate: '2026-11-19', trigger: 'status_change' as const, autoSend: false };

beforeEach(() => {
  reiniciarBanco();
  banco.respostas['service_orders.select'] = ok(os);
});

describe('generateCollectionsFromOS — leituras que falham', () => {
  it('cobranças existentes ilegíveis: lança e não cria nada', async () => {
    banco.respostas['collections.select'] = falha('timeout');
    await expect(generateCollectionsFromOS(entrada)).rejects.toThrow(/cobranças que já existem/);
    expect(chamadasA('collections.insert')).toHaveLength(0);
  });

  it('preset ilegível: lança e não cria nada', async () => {
    banco.respostas['collections.select'] = ok([]);
    banco.respostas['payment_condition_presets.select'] = falha('timeout');
    await expect(generateCollectionsFromOS(entrada)).rejects.toThrow(/condição de pagamento/);
    expect(chamadasA('collections.insert')).toHaveLength(0);
  });

  it('configurações ilegíveis: lança e não cria nada', async () => {
    banco.respostas['collections.select'] = ok([]);
    banco.respostas['payment_condition_presets.select'] = ok({ installments: [], auto_generate_collections: true });
    banco.respostas['app_settings.select'] = falha('timeout');
    await expect(generateCollectionsFromOS(entrada)).rejects.toThrow(/configurações de cobrança/);
    expect(chamadasA('collections.insert')).toHaveLength(0);
  });

  it('preset com auto_generate_collections=false: pula', async () => {
    banco.respostas['collections.select'] = ok([]);
    banco.respostas['payment_condition_presets.select'] = ok({ installments: [], auto_generate_collections: false });
    await expect(generateCollectionsFromOS(entrada)).resolves.toEqual({ created: 0, skipped: true, failed: 0 });
    expect(chamadasA('collections.insert')).toHaveLength(0);
  });

  it('parcela que não grava é contada em failed', async () => {
    banco.respostas['collections.select'] = ok([]);
    banco.respostas['payment_condition_presets.select'] = ok({
      auto_generate_collections: true,
      installments: [{ label: 'Sinal', percent: 50, days_after_approval: 0 }, { label: 'Saldo', percent: 50, days_after_approval: 30 }],
    });
    banco.respostas['app_settings.select'] = ok([]);
    banco.respostas['collections.insert'] = [ok({ id: 'col-1' }), falha('violação')];
    await expect(generateCollectionsFromOS(entrada)).resolves.toEqual({ created: 1, skipped: false, failed: 1 });
  });
});
