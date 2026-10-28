// Paridade do "Cobrar juntas" (28/10/2026): a mensagem que vai ao cliente tem de sair IGUAL pela tela
// (buildClientStatement com servicoIds, src/lib/client-statement.ts) e pelo assistente
// (mensagemDaCobrancaConjunta, _shared/ai/tools/cobrar-juntas.ts). As duas são montadas em lugares
// diferentes (a da tela usa date-fns, que não roda no Deno), então este caso fixo é lido pelos dois
// testes — client-statement.test.ts (vitest) e cobrar-juntas_test.ts (deno) — e cada um compara o seu
// texto com o MESMO `esperado`. Mudou o formato de um lado só, um dos dois testes acusa.
//
// Sem import nenhum (vale em Vite e em Deno). Só dado de teste: nenhuma função de produção importa.

export const PARIDADE_COBRAR_JUNTAS = {
  clienteNome: 'MP MOTOR HOMES',
  pixKey: '12.345.678/0001-90',
  hoje: '2026-10-28',
  os: [
    { id: '22222222-2222-4222-8222-222222222045', numero: 'OS-00045' },
    { id: '22222222-2222-4222-8222-222222222046', numero: 'OS-00046' },
  ],
  /** As contas das duas OS: o sinal pago e a cancelada ficam fora; vencida, parcial e a vencer entram. */
  contas: [
    {
      id: 'p45s', service_order_id: '22222222-2222-4222-8222-222222222045', numero_os: 'OS-00045',
      description: 'Sinal OS-00045', amount: 500, paid_amount: 500, balance_amount: 0, status: 'paid', due_date: '2026-06-05',
    },
    {
      id: 'p45', service_order_id: '22222222-2222-4222-8222-222222222045', numero_os: 'OS-00045',
      description: 'Saldo OS-00045', amount: 1650, paid_amount: 0, balance_amount: 1650, status: 'pending', due_date: '2026-07-22',
    },
    {
      id: 'p45c', service_order_id: '22222222-2222-4222-8222-222222222045', numero_os: 'OS-00045',
      description: 'Antiga', amount: 300, paid_amount: 0, balance_amount: 300, status: 'cancelled', due_date: '2026-07-01',
    },
    {
      id: 'p46', service_order_id: '22222222-2222-4222-8222-222222222046', numero_os: 'OS-00046',
      description: 'Saldo OS-00046', amount: 100, paid_amount: 80, balance_amount: 20, status: 'partially_paid', due_date: '2026-11-10',
    },
    {
      id: 'p46x', service_order_id: '22222222-2222-4222-8222-222222222046', numero_os: 'OS-00046',
      description: 'Peça extra', amount: 35, paid_amount: 0, balance_amount: 35, status: 'pending', due_date: '2026-11-30',
    },
  ],
  esperado:
    '📋 *Cobrança — HBR*\nCliente: MP\nOS: OS-00045, OS-00046\n\n' +
    '🔴 Saldo OS-00045 · vence 22/07/2026 · vencido: *R$ 1.650,00*\n' +
    '🟠 Saldo OS-00046 · vence 10/11/2026 · parcial: *R$ 20,00* (de R$ 100,00)\n' +
    '🟡 OS-00046 · Peça extra · vence 30/11/2026 · a vencer: *R$ 35,00*\n\n' +
    'Total: R$ 1.785,00\n' +
    'Pago: R$ 80,00\n' +
    '*Em aberto: R$ 1.705,00*\n\n' +
    '💠 Para pagar por Pix, use a chave: *12.345.678/0001-90*\n\n' +
    '_Qualquer dúvida sobre os valores, estamos à disposição._',
} as const;
