import { describe, it, expect } from 'vitest';
import { buildRouteSheetHtml } from './route-sheet';
import type { ServiceOrderStep } from '@/hooks/use-service-steps';

function step(over: Partial<ServiceOrderStep> = {}): ServiceOrderStep {
  return {
    id: over.id || 's1',
    service_order_id: 'os1',
    service_order_service_id: null,
    template_id: null,
    seq: 1,
    block: 'Preparação',
    title: 'Desligar o disjuntor geral',
    detail: null,
    kind: 'do',
    mode: 'do_confirm',
    standard_minutes: 10,
    is_killer: false,
    requires_photo: false,
    requires_measure: null,
    measure_unit: null,
    measure_value: null,
    status: 'pending',
    na_reason: null,
    blocked_reason_code: null,
    blocked_note: null,
    assigned_user_id: null,
    started_at: null,
    completed_at: null,
    actual_minutes: null,
    origin: 'template',
    notes: null,
    ...over,
  };
}

const header = { orderNumber: 'OS-00051', clientName: 'Cliente Teste', assetName: 'Motorhome Clóvis' };

describe('folha A4 do roteiro', () => {
  it('agrupa por bloco preservando a ordem dos passos', () => {
    const html = buildRouteSheetHtml(header, [
      step({ id: 'a', seq: 1, block: 'Preparação', title: 'Isolar o circuito' }),
      step({ id: 'b', seq: 2, block: 'Execução', title: 'Trocar o banco de baterias' }),
      step({ id: 'c', seq: 3, block: 'Execução', title: 'Refazer os terminais' }),
    ]);
    expect(html.indexOf('Isolar o circuito')).toBeLessThan(html.indexOf('Trocar o banco'));
    expect(html.indexOf('Trocar o banco')).toBeLessThan(html.indexOf('Refazer os terminais'));
    // Dois blocos distintos, não três nem um
    expect(html.match(/class="blockname"/g)).toHaveLength(2);
  });

  it('marca segurança, item crítico e foto para quem lê no papel', () => {
    const html = buildRouteSheetHtml(header, [
      step({ kind: 'safety', is_killer: true, requires_photo: true }),
    ]);
    expect(html).toContain('SEGURANÇA');
    expect(html).toContain('CRÍTICO');
    expect(html).toContain('FOTO');
  });

  it('abre campo de medição com a unidade quando o passo exige', () => {
    const html = buildRouteSheetHtml(header, [
      step({ requires_measure: 'tensao_v', measure_unit: 'V' }),
    ]);
    expect(html).toContain('Medição (V)');
  });

  it('escapa HTML vindo do cadastro — nome de cliente não pode virar marcação', () => {
    const html = buildRouteSheetHtml(
      { orderNumber: 'OS-1', clientName: '<script>alert(1)</script>' },
      [step({ title: 'Passo & teste <b>' })],
    );
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
    expect(html).toContain('Passo &amp; teste &lt;b&gt;');
  });

  it('imprime aviso claro quando não há roteiro, em vez de folha em branco', () => {
    const html = buildRouteSheetHtml(header, []);
    expect(html).toContain('ainda não tem roteiro gerado');
  });

  it('soma o tempo previsto no cabeçalho', () => {
    const html = buildRouteSheetHtml(header, [
      step({ id: 'a', standard_minutes: 45 }),
      step({ id: 'b', standard_minutes: 90 }),
    ]);
    expect(html).toContain('Previsto: 2h15');
  });

  it('sempre traz as duas assinaturas e a instrução do que fazer ao travar', () => {
    const html = buildRouteSheetHtml(header, [step()]);
    expect(html).toContain('Assinatura do técnico');
    expect(html).toContain('Assinatura do cliente');
    expect(html).toContain('Travou?');
  });
});
