// Rede de segurança da EMISSÃO (D33, 01/10/2026), antes de partir o diálogo de emissão em partes.
//
// Percorre a tela como o dono faz: a lista mostra uma nota autorizada, "Duplicar para nova nota"
// preenche o formulário inteiro a partir dela, "Emitir NF-e" manda o corpo para a conferência
// (espelho) e "Confirmar emissão" manda o corpo da emissão. Os dois corpos são capturados: o
// snapshot fixa o conteúdo EXATO que iria para a SEFAZ. Qualquer reorganização da tela tem de
// manter este teste verde sem atualizar o snapshot; mudar o snapshot é mudar a nota.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

const NOTA = {
  id: 'nf-31', document_type: 'nfe', series: 2, number: 31, status: 'authorized', environment: 'producao',
  origin_type: 'manual', client_id: 'cli-1', provider_document_id: 'prov-31',
  access_key: '42260912345678000199550020000000311000000310',
  authorized_at: '2026-09-10T12:00:00-03:00', created_at: '2026-09-10T11:50:00-03:00',
  customer_po_number: '4512', customer_buyer_name: 'Ana',
  payment_terms: {
    mode: 'parcelado', method: '14',
    installments: [
      { due_date: '2026-10-10', amount: 500, method: '14' },
      { due_date: '2026-11-09', amount: 499.5, method: '14' },
    ],
  },
  request_payload: {
    purpose: 1, nature_operation: 'Venda de mercadoria', operation_type: 'saida',
    presence_indicator: 1, consumer_final: false,
    additional_info: 'Pedido de Compra: 4512 - Comprador: Ana; Entregar no píer 3; Documento emitido por ME ou EPP optante pelo Simples Nacional. Não gera direito a crédito fiscal de IPI.',
    recipient: {
      name: 'MARINA EXEMPLO LTDA', document: '12345678000199', email: 'compras@marina.example',
      state_registration_indicator: 1, state_registration: '254000000',
      address: {
        street: 'Rua do Porto', number: 'S/N', complement: 'Galpão 2', district: 'Centro',
        city_name: 'Florianópolis', state_code: 'SC', postal_code: '88010000',
      },
    },
    payments: [{ method: '14', amount: 999.5 }],
    items: [
      {
        code: 'BAT-100', name: 'Bateria 100Ah', ncm: '85072010', cfop: '5102', unit: 'UN', quantity: 2, unit_price: 450,
        taxes: { icms: { code: '102', origin: 0, aliquot: 0 }, pis: { aliquot: 0 }, cofins: { aliquot: 0 }, ipi: { aliquot: 0 } },
      },
      {
        code: 'CAB-6', name: 'Cabo 6mm', ncm: '85444900', cfop: '5102', unit: 'M', quantity: 10, unit_price: 9.95,
        taxes: { icms: { code: '102', origin: 0, aliquot: 0 }, pis: { aliquot: 0 }, cofins: { aliquot: 0 }, ipi: { aliquot: 0 } },
      },
    ],
  },
};

const banco = vi.hoisted(() => ({ chamadas: [] as Array<{ action: string; body: Record<string, unknown> }> }));

vi.mock('@/integrations/supabase/client', () => {
  const builder = (tabela: string) => {
    const o: Record<string, unknown> = {};
    for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'lt', 'gt', 'order', 'limit', 'is', 'not',
      'like', 'update', 'insert', 'delete', 'upsert', 'filter', 'or', 'ilike', 'range']) {
      o[k] = () => o;
    }
    const empresa = { id: 'cfs-1', state_code: 'SC', legal_name: 'HBR MARINE', cnpj: '12345678000100', crt: 1 };
    o.maybeSingle = async () => ({ data: tabela === 'company_fiscal_settings' ? empresa : null, error: null });
    o.single = async () => ({ data: null, error: null });
    o.then = (res: (v: unknown) => unknown) =>
      Promise.resolve({ data: tabela === 'issued_fiscal_documents' ? [NOTA] : [], error: null }).then(res);
    return o;
  };
  return {
    supabase: {
      from: (tabela: string) => builder(tabela),
      rpc: async () => ({ data: [], error: null }),
      auth: { getUser: async () => ({ data: { user: { id: 'u1', email: 'dono@hbr.example' } } }) },
      channel: () => ({ on() { return this; }, subscribe() { return this; } }),
      removeChannel: () => {},
      functions: {
        invoke: async (_nome: string, opts: { body: Record<string, unknown> }) => {
          const action = String(opts?.body?.action ?? '');
          if (action === 'environment') return { data: { data: { environment: 'homologacao' } }, error: null };
          if (action === 'preview' || action === 'create') banco.chamadas.push({ action, body: opts.body });
          if (action === 'preview') {
            return {
              data: { payload: NOTA.request_payload, emitter: {}, number: 32, series: 2, environment: 'homologacao' },
              error: null,
            };
          }
          if (action === 'create') return { data: { data: { environment: 'homologacao' } }, error: null };
          return { data: { data: {} }, error: null };
        },
      },
    },
  };
});

vi.mock('@/hooks/use-clients', () => ({ useClients: () => ({ data: [] }) }));
vi.mock('@/hooks/use-products', () => ({ useProducts: () => ({ data: [] }) }));
vi.mock('@/hooks/use-product-categories', () => ({ useProductCategories: () => ({ data: [] }) }));
vi.mock('@/hooks/use-app-settings', () => ({ useAppSettings: () => ({ data: {} }) }));
vi.mock('@/components/ClientFormDialog', () => ({ ClientFormDialog: () => null }));

import FiscalEmission from './FiscalEmission';

beforeEach(() => {
  banco.chamadas = [];
});

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>
          <FiscalEmission />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

/** O corpo sem o que muda a cada emissão (a chave de idempotência é um UUID novo). */
const semVariaveis = (b: Record<string, unknown>) => {
  const { idempotency_key: _k, action: _a, origin_type: _o, origin_id: _i, ...resto } = b;
  return resto;
};

describe('Emissão — duplicar uma nota e emitir', () => {
  it('o corpo da conferência e o da emissão são os mesmos, e são estes', async () => {
    // Cliques normais, como o dono faz. Foi este teste que achou o defeito de 01/10: o clique no
    // item do menu subia até a linha da tabela, que abria a nota SÓ PARA LEITURA — o diálogo
    // abria em "consulta", sem o botão de emitir. Corrigido no AcoesDaLinha.
    const user = userEvent.setup();
    montar();

    await user.click((await screen.findAllByRole('button', { name: /Mais ações para NF-e 2\/31/ }))[0]);
    await user.click(await screen.findByRole('menuitem', { name: /Duplicar para nova nota/ }));
    expect(screen.queryByText(/— consulta/)).toBeNull();

    const emitir = await screen.findByRole('button', { name: /a nota só vai à SEFAZ depois que você confirmar/ });
    await waitFor(() => expect((emitir as HTMLButtonElement).disabled).toBe(false));
    await user.click(emitir);
    await waitFor(() => expect(banco.chamadas.map((c) => c.action)).toEqual(['preview']));

    await user.click(await screen.findByRole('button', { name: /Confirmar emissão/ }));
    await waitFor(() => expect(banco.chamadas.map((c) => c.action)).toEqual(['preview', 'create']));

    const [conferencia, emissao] = banco.chamadas.map((c) => c.body);
    expect(emissao.origin_type).toBe('manual');
    expect(typeof emissao.idempotency_key).toBe('string');
    expect(semVariaveis(emissao)).toEqual(semVariaveis(conferencia));

    // O que mais importa, explícito (o snapshot abaixo fixa o resto):
    const corpo = semVariaveis(emissao) as Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any
    expect(corpo.nature_of_operation).toBe('venda');
    expect(corpo.payment_method).toBe('14');
    expect(corpo.payment_terms.mode).toBe('parcelado');
    expect(corpo.payment_terms.installments.map((p: { due_date: string }) => p.due_date)).toEqual(['2026-10-10', '2026-11-09']);
    expect(corpo.recipient.state_registration).toBe('254000000');
    expect(corpo.recipient.address.number).toBe(''); // "S/N" não volta como número
    expect(corpo.customer_po_number).toBe('4512');
    expect(corpo.additional_info.startsWith('Pedido de Compra: 4512 - Comprador: Ana')).toBe(true);
    expect(corpo.items).toHaveLength(2);

    expect(corpo).toMatchSnapshot();
  });
});
