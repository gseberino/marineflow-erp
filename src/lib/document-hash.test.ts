// Cobertura do hash do documento assinado — módulo sem teste até agora.
//
// O que este hash faz: congela o conteúdo da OS no instante em que o cliente assina
// (`PublicServiceOrderView.tsx:306`), e o valor vai para `service_orders.signed_document_hash`.
// É a prova de que o documento assinado é aquele documento — a peça que responde "o cliente
// assinou ISTO" quando alguém contesta.
//
// Duas maneiras de ele falhar, as duas silenciosas:
//   1. deixar de mudar quando o documento muda → alteração posterior passa por assinada;
//   2. mudar quando o documento não mudou → assinatura válida vira suspeita.
//
// O teste mais importante do arquivo é o último bloco: ele LÊ a migration do trigger
// `detect_so_change_after_signature` e cobra que todo campo vigiado pelo banco também mude o
// hash. Os dois foram escritos juntos em abril e ninguém garante que continuem juntos — se
// alguém acrescentar um campo ao trigger e esquecer do hash, o banco pediria re-assinatura de
// uma mudança que o hash não registra.
import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { computeDocumentHash, type HashableServiceOrder, type HashableLine } from './document-hash';

const OS_BASE: HashableServiceOrder = {
  service_order_number: 'OS-00123',
  status: 'completed',
  problem_description: 'Painel elétrico desarmando',
  diagnosis: 'Disjuntor geral subdimensionado',
  solution_applied: 'Substituído por 63A',
  customer_visible_report: 'Serviço concluído e testado',
  payment_conditions: '50% na aprovação, 50% na entrega',
  extra_notes: 'Cliente pediu nota fiscal',
  grand_total: 4333.31,
  labor_cost_total: 2469.12,
  parts_cost_total: 1975.30,
  travel_cost_total: 333.33,
  discount_amount: 444.44,
  tax_amount: 0,
  operational_cost_total: 0,
  quote_validity_date: '2026-09-01',
};

const SERVICOS: HashableLine[] = [
  { name: 'Revisão do painel', qty: 2, unit_price: 500, line_total: 1000 },
  { name: 'Teste sob carga', qty: 1, unit_price: 300, line_total: 300 },
];

const PECAS: HashableLine[] = [
  { name: 'Disjuntor 63A', qty: 2, unit_price: 400, line_total: 800 },
];

const TERMOS = 'Garantia de 90 dias sobre a mão de obra.';

const hashPadrao = () => computeDocumentHash(OS_BASE, SERVICOS, PECAS, TERMOS);

describe('computeDocumentHash — estabilidade', () => {
  it('a mesma entrada devolve sempre o mesmo hash', async () => {
    expect(await hashPadrao()).toBe(await hashPadrao());
  });

  it('tem cara de SHA-256: 64 caracteres hexadecimais', async () => {
    expect(await hashPadrao()).toMatch(/^[0-9a-f]{64}$/);
  });

  it('a ORDEM dos itens não muda o hash — a lista chega ordenada do banco por acaso', async () => {
    const invertido = await computeDocumentHash(OS_BASE, [...SERVICOS].reverse(), [...PECAS].reverse(), TERMOS);
    expect(invertido).toBe(await hashPadrao());
  });

  it('null, undefined e string vazia são a mesma coisa — não pedem re-assinatura à toa', async () => {
    const comNulos = await computeDocumentHash(
      { ...OS_BASE, diagnosis: null, extra_notes: null },
      SERVICOS, PECAS, TERMOS,
    );
    const comVazios = await computeDocumentHash(
      { ...OS_BASE, diagnosis: '', extra_notes: undefined },
      SERVICOS, PECAS, TERMOS,
    );
    expect(comNulos).toBe(comVazios);
  });

  it('valor 0 e valor ausente são a mesma coisa', async () => {
    const comZero = await computeDocumentHash({ ...OS_BASE, tax_amount: 0 }, SERVICOS, PECAS, TERMOS);
    const semCampo = await computeDocumentHash({ ...OS_BASE, tax_amount: null }, SERVICOS, PECAS, TERMOS);
    expect(comZero).toBe(semCampo);
  });

  it('diferença abaixo de um centavo não conta — 4333.311 é o mesmo 4333.31', async () => {
    const arredondado = await computeDocumentHash({ ...OS_BASE, grand_total: 4333.311 }, SERVICOS, PECAS, TERMOS);
    expect(arredondado).toBe(await hashPadrao());
  });

  it('espaço em volta dos termos não conta; o texto conta', async () => {
    expect(await computeDocumentHash(OS_BASE, SERVICOS, PECAS, `  ${TERMOS}\n`)).toBe(await hashPadrao());
    expect(await computeDocumentHash(OS_BASE, SERVICOS, PECAS, `${TERMOS} Exceto peças.`)).not.toBe(await hashPadrao());
  });

  it('termos ausentes e termos vazios são a mesma coisa', async () => {
    expect(await computeDocumentHash(OS_BASE, SERVICOS, PECAS, undefined))
      .toBe(await computeDocumentHash(OS_BASE, SERVICOS, PECAS, '   '));
  });
});

describe('computeDocumentHash — sensibilidade: o que TEM que mudar o hash', () => {
  it('um centavo a mais no total', async () => {
    expect(await computeDocumentHash({ ...OS_BASE, grand_total: 4333.32 }, SERVICOS, PECAS, TERMOS))
      .not.toBe(await hashPadrao());
  });

  it('trocar a quantidade de um item', async () => {
    const outros = [{ ...SERVICOS[0], qty: 3 }, SERVICOS[1]];
    expect(await computeDocumentHash(OS_BASE, outros, PECAS, TERMOS)).not.toBe(await hashPadrao());
  });

  it('trocar o preço unitário de uma peça sem mexer no total da linha', async () => {
    const outras = [{ ...PECAS[0], unit_price: 450 }];
    expect(await computeDocumentHash(OS_BASE, SERVICOS, outras, TERMOS)).not.toBe(await hashPadrao());
  });

  it('acrescentar uma peça', async () => {
    const outras = [...PECAS, { name: 'Cabo 6mm', qty: 10, unit_price: 12, line_total: 120 }];
    expect(await computeDocumentHash(OS_BASE, SERVICOS, outras, TERMOS)).not.toBe(await hashPadrao());
  });

  it('remover um serviço', async () => {
    expect(await computeDocumentHash(OS_BASE, [SERVICOS[0]], PECAS, TERMOS)).not.toBe(await hashPadrao());
  });

  it('renomear um item', async () => {
    const outros = [{ ...SERVICOS[0], name: 'Revisão do painel (revisada)' }, SERVICOS[1]];
    expect(await computeDocumentHash(OS_BASE, outros, PECAS, TERMOS)).not.toBe(await hashPadrao());
  });

  it('mudar a condição de pagamento', async () => {
    expect(await computeDocumentHash({ ...OS_BASE, payment_conditions: '100% na entrega' }, SERVICOS, PECAS, TERMOS))
      .not.toBe(await hashPadrao());
  });
});

describe('o hash cobre tudo que o banco vigia (trigger detect_so_change_after_signature)', () => {
  // Lê a migration do trigger e extrai os campos comparados com IS DISTINCT FROM. Cada um
  // deles, ao mudar, tem que mudar o hash — senão o banco pede re-assinatura de uma alteração
  // que o documento assinado não registra, e a prova fica incompleta justamente no caso em
  // que ela é necessária.
  const migration = (() => {
    const arquivo = readdirSync(join(process.cwd(), 'supabase', 'migrations'))
      .find(f => f.includes('f41d70d9')); // detect_so_change_after_signature
    if (!arquivo) throw new Error('migration do trigger de re-assinatura não encontrada');
    return readFileSync(join(process.cwd(), 'supabase', 'migrations', arquivo), 'utf8');
  })();

  const camposVigiados = Array.from(
    migration.matchAll(/NEW\.(\w+)\s+IS\s+DISTINCT\s+FROM\s+OLD\.\1/gi),
  ).map(m => m[1]);

  it('a migration realmente lista campos — se o regex parar de casar, o teste inteiro é fumaça', () => {
    expect(camposVigiados.length).toBeGreaterThanOrEqual(10);
  });

  it.each(camposVigiados)('mudar %s muda o hash', async (campo) => {
    // Campo que o trigger vigia e o OS_BASE não conhece ainda é tratado como texto: o que
    // interessa medir é se ele chega ao hash, não o tipo dele.
    const atual = (OS_BASE as unknown as Record<string, unknown>)[campo];
    const novo = typeof atual === 'number' ? atual + 13.37 : `${atual ?? ''} alterado`;
    const mudado = await computeDocumentHash(
      { ...OS_BASE, [campo]: novo } as HashableServiceOrder,
      SERVICOS, PECAS, TERMOS,
    );
    expect(mudado, `${campo} é vigiado pelo trigger mas não entra no hash`).not.toBe(await hashPadrao());
  });
});
