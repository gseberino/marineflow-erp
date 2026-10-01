import { describe, it, expect } from 'vitest';
import { buildRouteSheetHtml } from './route-sheet';
import type { ServiceOrderStep, RouteMaterial } from '@/hooks/use-service-steps';

function step(over: Partial<ServiceOrderStep> = {}): ServiceOrderStep {
  return {
    id: over.id || 's1',
    service_order_id: 'os1',
    service_order_service_id: null,
    template_id: null,
    seq: 1,
    block: 'Preparação',
    block_key: null,
    block_note: null,
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

  it('sem roteiro, a seção some — nada de recado para o escritório na folha do técnico', () => {
    const html = buildRouteSheetHtml(header, []);
    expect(html).not.toContain('ainda não tem roteiro');
    expect(html).not.toContain('Roteiro de execução');
    expect(html).toContain('Chegada');
  });

  it('não imprime soma de tempo padrão como se fosse a estimativa da OS', () => {
    const html = buildRouteSheetHtml(header, [
      step({ id: 'a', standard_minutes: 45 }),
      step({ id: 'b', standard_minutes: 90 }),
    ]);
    expect(html).not.toContain('Previsto:');
    expect(html).not.toContain('2h15');
  });

  it('sempre traz as duas assinaturas e a instrução do que fazer ao travar', () => {
    const html = buildRouteSheetHtml(header, [step()]);
    expect(html).toContain('Assinatura do técnico');
    expect(html).toContain('Assinatura do cliente');
    expect(html).toContain('Travou?');
  });
});

/**
 * Pedidos do dono em 31/07: marca discreta, espaço para escrever à mão e a
 * separação de materiais — "inclusive o que será usado em cada uma das etapas".
 */
describe('folha do roteiro — marca, anotações e materiais', () => {
  const material = (over: Partial<RouteMaterial> = {}): RouteMaterial => ({
    id: over.id || 'm1',
    quantity: 2,
    notes: null,
    service_order_service_id: null,
    products: { name: 'Cabo 16mm² preto', sku: 'CB-16-PT', unit: 'm' },
    ...over,
  });

  it('traz a marca da empresa no cabeçalho e o endereço no rodapé', () => {
    const html = buildRouteSheetHtml(
      { ...header, companyName: 'HBR Marine Solutions', companyLogoUrl: 'https://x/logo.png',
        companyAddress: 'Itajaí-SC' },
      [step()],
    );
    expect(html).toContain('HBR Marine Solutions');
    expect(html).toContain('https://x/logo.png');
    expect(html).toContain('Itajaí-SC');
  });

  it('lista a separação de materiais com quantidade, unidade e SKU', () => {
    const html = buildRouteSheetHtml(header, [step()], [material()]);
    expect(html).toContain('separação de materiais');
    expect(html).toContain('2 m');
    expect(html).toContain('Cabo 16mm² preto');
    expect(html).toContain('CB-16-PT');
  });

  it('mostra o material da etapa dentro do bloco daquele serviço', () => {
    const html = buildRouteSheetHtml(
      header,
      [step({ block: '2 · Instalação de multimídia', block_key: 'linha:abc' })],
      [material({ id: 'm2', service_order_service_id: 'abc' })],
    );
    expect(html).toContain('Material desta etapa:');
  });

  it('não pendura material de outra linha no bloco errado', () => {
    const html = buildRouteSheetHtml(
      header,
      [step({ block: '2 · Instalação', block_key: 'linha:abc' })],
      [material({ id: 'm3', service_order_service_id: 'OUTRA-LINHA' })],
    );
    // Aparece só na separação geral, nunca como material da etapa.
    expect(html).not.toContain('Material desta etapa:');
    expect(html).toContain('separação de materiais');
  });

  it('escreve o escopo do bloco compartilhado, que era o que faltava', () => {
    const html = buildRouteSheetHtml(header, [
      step({
        block: '1 · Antes de mexer — Eletrônico',
        block_key: 'abertura:eletronico',
        block_note: 'Vale para os 3 serviços desta OS: multimídia, câmeras e Starlink.',
      }),
    ]);
    expect(html).toContain('Vale para os 3 serviços desta OS');
  });

  it('abre os três espaços de escrita à mão', () => {
    const html = buildRouteSheetHtml(header, [step()]);
    expect(html).toContain('Observações deste bloco');
    expect(html).toContain('O que encontrei');
    expect(html).toContain('Material usado além do previsto');
  });

  it('via do técnico: serviços contratados sem preço e levantamento com foto', () => {
    const html = buildRouteSheetHtml(header, [step()], [], {
      services: [
        { name: 'Instalação de inversor', quantity: 2, unit: 'un', description: 'Victron 3000VA' },
        { name: 'Diagnóstico elétrico', quantity: 1 },
      ],
      survey: [
        { question: 'Qual a bitola do cabo atual?', answer: '35 mm²', photoUrl: 'https://x/foto.jpg' },
        { question: 'Há espaço no painel?', skipped: 'não deu para abrir' },
      ],
    });
    expect(html).toContain('Serviços desta OS');
    expect(html).toContain('Instalação de inversor');
    expect(html).toContain('× 2 un');
    expect(html).toContain('Victron 3000VA');
    expect(html).not.toMatch(/R\$\s?\d/);
    expect(html).toContain('Levantamento');
    expect(html).toContain('35 mm²');
    expect(html).toContain('src="https://x/foto.jpg"');
    expect(html).toContain('pulada: não deu para abrir');
    expect(html).toContain('Via do técnico');
  });

  it('sem serviços nem levantamento, as seções novas simplesmente não aparecem', () => {
    const html = buildRouteSheetHtml(header, [step()], []);
    expect(html).not.toContain('Serviços desta OS');
    expect(html).not.toContain('>Levantamento<');
  });
});

/**
 * Avaliação de 01/10/2026: a via imprimia só o nome dos serviços e deixava de fora o que
 * já estava no sistema. Estes testes guardam o que o técnico precisa ler sem poder ligar.
 */
describe('via do técnico — folha de rosto e volta (avaliação 01/10)', () => {
  const rosto = {
    orderNumber: 'OS-00104',
    clientName: 'Flávio',
    clientPhone: '(47) 99999-0000',
    clientWhatsapp: '47 99999-0000',
    requestedBy: 'Marinheiro João',
    assetName: 'Itapoã',
    assetType: 'Motorhome',
    assetMaker: 'Itapoã',
    assetModel: 'Sprinter',
    marinaName: 'Marina Itajaí',
    dockPosition: 'B-12',
    scheduledAt: '2026-09-28T12:00:00Z',
    problemDescription: 'Converter a geladeira para 12V\nSinal na aprovação: R$ 1.500,00\nCortesia: LED 12V',
    companyPhone: '(47) 3333-0000',
  };

  it('traz veículo, local, vaga e com quem falar — tudo que já está no cadastro', () => {
    const html = buildRouteSheetHtml(rosto, []);
    expect(html).toContain('Motorhome · Itapoã Sprinter');
    expect(html).toContain('Marina Itajaí · vaga B-12');
    // Mesmo número no telefone e no WhatsApp sai uma vez só.
    expect(html).toContain('tel./WhatsApp (47) 99999-0000');
    expect(html).toContain('Pedido por: <b>Marinheiro João</b>');
    expect(html).toContain('Escritório: <b>(47) 3333-0000</b>');
  });

  it('imprime o pedido do cliente e corta toda linha com valor em reais', () => {
    const html = buildRouteSheetHtml(rosto, []);
    expect(html).toContain('Pedido do cliente');
    expect(html).toContain('Converter a geladeira para 12V');
    expect(html).toContain('Cortesia: LED 12V');
    expect(html).not.toContain('R$');
    expect(html).not.toContain('1.500');
  });

  it('corta valor também do texto dos serviços', () => {
    const html = buildRouteSheetHtml(rosto, [], [], {
      services: [{ name: 'Instalação', notes: 'Trocar o inversor\nValor da mão de obra: R$ 900,00' }],
    });
    expect(html).toContain('Trocar o inversor');
    expect(html).not.toMatch(/R\$\s?\d/);
  });

  it('nunca leva o link do portal do cliente, que mostra preço', () => {
    const html = buildRouteSheetHtml(rosto, [step()]);
    expect(html).not.toContain('/view/');
    expect(html).not.toContain('OS no sistema');
  });

  it('avisa quando não há material lançado, em vez de sumir com a seção', () => {
    const html = buildRouteSheetHtml(rosto, []);
    expect(html).toContain('Nenhum material lançado nesta OS');
  });

  it('diz onde falta informação, para o técnico confirmar antes de sair', () => {
    const html = buildRouteSheetHtml({ orderNumber: 'OS-1', clientName: 'Sem fone' }, []);
    expect(html).toContain('Local não informado na OS');
    expect(html).toContain('sem telefone no cadastro');
    expect(html).toContain('A combinar com o escritório');
  });

  it('não imprime término anterior ao início', () => {
    const html = buildRouteSheetHtml(
      { ...rosto, scheduledAt: '2026-09-28T12:00:00Z', scheduledEndAt: '2026-09-24T21:00:00Z' },
      [],
    );
    expect(html).not.toContain('→');
  });

  it('escreve a regra de escopo: achado fora da lista não se executa sem aprovação', () => {
    const html = buildRouteSheetHtml(rosto, []);
    expect(html).toContain('Achou outro defeito ou algo fora desta lista?');
    expect(html).toContain('não execute');
  });

  it('cada serviço tem a volta: feito, parcial ou não feito, e o material dele', () => {
    const html = buildRouteSheetHtml(rosto, [], [
      { id: 'm1', quantity: 1, notes: null, service_order_service_id: 'linha-1',
        products: { name: 'Compressor 12V', sku: null, unit: 'un' } },
    ], { services: [{ id: 'linha-1', name: 'Conversão para 12V' }] });
    expect(html).toContain('1 · Conversão para 12V');
    expect(html).toContain('Material deste serviço:');
    expect(html).toContain('não feito');
    expect(html).toContain('parcial');
  });

  it('passo feito no sistema sai marcado; sugestão da IA não aprovada não sai', () => {
    const html = buildRouteSheetHtml(rosto, [
      step({ id: 'a', seq: 1, title: 'Desligar o disjuntor geral', status: 'done' }),
      step({ id: 'b', seq: 2, title: 'Passo que a IA sugeriu', origin: 'ai' as any }),
    ]);
    expect(html).toContain('Feito (registrado no sistema)');
    expect(html).toContain('✓');
    expect(html).not.toContain('Passo que a IA sugeriu');
  });

  it('assinatura do cliente diz o que ele atesta, com nome, data e hora', () => {
    const html = buildRouteSheetHtml(rosto, []);
    expect(html).toContain('Recebi os serviços marcados como feitos acima, testados na minha presença.');
    expect(html).toContain('Nome legível');
    expect(html).toContain('hora ____:____');
    expect(html).toContain('Chegada');
    expect(html).toContain('Saída');
  });

  it('número da OS e página em toda folha impressa', () => {
    const html = buildRouteSheetHtml(rosto, []);
    expect(html).toContain('"OS-00104 · pág. " counter(page) " de " counter(pages)');
  });
});

/**
 * Decisão do dono, 01/10/2026: a via do menu Ações leva só a segurança de cada sistema;
 * o roteiro completo continua saindo pelo painel Roteiro, para ser testado à parte.
 */
describe('via do técnico — roteiro só com a segurança de cada sistema', () => {
  const roteiro = [
    step({ id: 'a', seq: 1, block: '1 · Antes de mexer — Hidráulico', block_key: 'abertura:hidraulico', title: 'Fechar o registro' }),
    step({ id: 'b', seq: 2, block: '2 · Troca do cano', block_key: 'linha:x', title: 'Confirmar que a peça nova é equivalente' }),
    step({ id: 'c', seq: 3, block: '3 · Antes de entregar — Hidráulico', block_key: 'fechamento:hidraulico', title: 'Reabrir o registro devagar' }),
  ];

  it('na via, ficam a abertura e o fechamento do sistema; o corpo genérico sai', () => {
    const html = buildRouteSheetHtml(header, roteiro, [], { roteiro: 'seguranca' });
    expect(html).toContain('Segurança por sistema');
    expect(html).toContain('Fechar o registro');
    expect(html).toContain('Reabrir o registro devagar');
    expect(html).not.toContain('Confirmar que a peça nova é equivalente');
  });

  it('roteiro antigo, sem chave de bloco, contribui só com passos de segurança', () => {
    const html = buildRouteSheetHtml(header, [
      step({ id: 'd', kind: 'safety', title: 'Desligar a chave geral' }),
      step({ id: 'e', seq: 2, kind: 'do', title: 'Instalar o inversor' }),
    ], [], { roteiro: 'seguranca' });
    expect(html).toContain('Desligar a chave geral');
    expect(html).not.toContain('Instalar o inversor');
  });

  it('no painel Roteiro, sai tudo, para testar o roteiro à parte', () => {
    const html = buildRouteSheetHtml(header, roteiro, [], { roteiro: 'completo' });
    expect(html).toContain('Roteiro de execução');
    expect(html).toContain('roteiro completo');
    expect(html).toContain('Confirmar que a peça nova é equivalente');
  });
});
