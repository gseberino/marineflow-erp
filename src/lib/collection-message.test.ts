// A mensagem de cobrança não promete o que o sistema não faz (19/11/2026): não existe emissão de
// boleto, e o texto dizia "O boleto será enviado em breve ao seu email."
import { describe, expect, it } from 'vitest';
import { buildCollectionMessage, type RenderTemplateFn } from './collection-message';

const render: RenderTemplateFn = (body, ctx) => body.replace('{nome}', ctx.nome);
const cobranca = { amount: 500, due_date: '2026-11-30', contact_name: 'Ana', service_order: { service_order_number: 'OS-00100' } };

describe('buildCollectionMessage — boleto', () => {
  it('não promete envio automático de boleto por email', () => {
    const msg = buildCollectionMessage({
      template: 'Olá {nome}', renderTemplate: render, collection: cobranca, paymentMethod: 'boleto', settings: {},
    });
    expect(msg).toContain('Forma de pagamento: Boleto Bancário');
    expect(msg).toContain('Para receber o boleto, é só responder esta mensagem.');
    expect(msg).not.toMatch(/será enviado/);
    expect(msg).not.toMatch(/email/i);
  });

  it('Pix continua com a chave', () => {
    const msg = buildCollectionMessage({
      template: 'Olá {nome}', renderTemplate: render, collection: cobranca, paymentMethod: 'pix', settings: { pix_key: 'chave@x' },
    });
    expect(msg).toContain('Chave PIX: *chave@x*');
  });
});
