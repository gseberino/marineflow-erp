// A ficha aberta que o assistente recebe, nas telas antigas e nas novas (/v2) — decisão 5 do dono,
// 22/10/2026: nas telas /v2 o assistente não recebia a ficha (o mapa só conhecia /clients/:id etc.).
import { describe, it, expect } from 'vitest';
import { contextoDaRota } from './ai-context';

const ID = '3f2b8c1e-9a4d-4e7b-8c21-0d5f6a7b8c9d';

describe('contextoDaRota', () => {
  it('telas novas (/v2): cliente, unidade e OS chegam com o id', () => {
    expect(contextoDaRota(`/v2/clients/${ID}`)).toEqual({ route: `/v2/clients/${ID}`, entityType: 'client', entityId: ID });
    expect(contextoDaRota(`/v2/vessels/${ID}`)).toEqual({ route: `/v2/vessels/${ID}`, entityType: 'vessel', entityId: ID });
    expect(contextoDaRota(`/v2/service-orders/${ID}`)).toEqual({ route: `/v2/service-orders/${ID}`, entityType: 'service_order', entityId: ID });
  });

  it('telas antigas continuam iguais', () => {
    expect(contextoDaRota(`/clients/${ID}`)).toEqual({ route: `/clients/${ID}`, entityType: 'client', entityId: ID });
    expect(contextoDaRota(`/vessels/${ID}`)).toEqual({ route: `/vessels/${ID}`, entityType: 'vessel', entityId: ID });
    expect(contextoDaRota(`/service-orders/${ID}`)).toEqual({ route: `/service-orders/${ID}`, entityType: 'service_order', entityId: ID });
  });

  it('o id é sempre o da entidade, nunca o "/v2" (grupo não capturante)', () => {
    const c = contextoDaRota(`/v2/service-orders/${ID}?aba=itens`);
    expect(c.entityId).toBe(ID);
    expect(c.entityId).not.toContain('v2');
  });

  it('telas de área, com e sem /v2', () => {
    for (const [rota, tipo] of [
      ['/financial', 'financial'], ['/v2/financial/payables/comissoes', 'financial'],
      ['/collections', 'collections'], ['/v2/collections', 'collections'], ['/v2/receivables/cobrancas', 'collections'],
      ['/whatsapp/leads', 'whatsapp_leads'], ['/v2/whatsapp/leads', 'whatsapp_leads'],
      ['/agenda', 'agenda'], ['/v2/agenda/acompanhamentos', 'agenda'],
      ['/products', 'products'], ['/v2/products', 'products'],
    ] as const) {
      expect(contextoDaRota(rota), rota).toEqual({ route: rota, entityType: tipo, entityId: undefined });
    }
  });

  it('OS nova (/v2/service-orders/new) não é ficha aberta; outras rotas com :id ficam "unknown"', () => {
    expect(contextoDaRota('/v2/service-orders/new')).toEqual({ route: '/v2/service-orders/new' });
    expect(contextoDaRota(`/v2/purchase-orders/${ID}`, ID)).toEqual({ route: `/v2/purchase-orders/${ID}`, entityType: 'unknown', entityId: ID });
    expect(contextoDaRota('/v2/receivables/a-receber')).toEqual({ route: '/v2/receivables/a-receber' });
  });

  it('o /v2 só vale no começo da rota', () => {
    expect(contextoDaRota(`/x/v2/clients/${ID}`)).toEqual({ route: `/x/v2/clients/${ID}` });
    expect(contextoDaRota(`/v3/clients/${ID}`)).toEqual({ route: `/v3/clients/${ID}` });
  });
});
