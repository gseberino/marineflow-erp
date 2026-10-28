// Registrar pagamento com a divisão entre diárias e reembolso (resposta 4 do dono, 11/10/2026: "sim,
// mas eu sempre vou sinalizar o que é o que"). O banco PROPÕE (os reembolsos em aberto que cabem no
// valor, por data) e o dono confirma ou desmarca; a tela manda os marcados para a MESMA função do
// assistente (registrar_pagamento_do_freelancer). Sem reembolso em aberto, o diálogo é o de antes.
//
// Simula só a fronteira com o banco (supabase.rpc), na forma do contrato da spec dos ajustes (4.1).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import type { FreelancerNoResumo } from '@/hooks/use-diarias';
import { toast } from 'sonner';
import { RegistrarPagamentoDialog } from './RegistrarPagamentoDialog';

const rpc = vi.fn();
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: (...a: unknown[]) => rpc(...a) } }));
vi.mock('sonner', () => ({ toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn(), warning: vi.fn() }) }));
vi.mock('@/hooks/use-payees', () => ({ usePayees: () => ({ data: [{ id: 's1', name: 'Gustavo', kind: 'socio' }] }) }));

const roberto: FreelancerNoResumo = {
  id: 'r', nome: 'Roberto Daniel', diaria: 160, desde: '2026-08-25', dias: 3, trabalhado: 480, pago: 0, reembolsos: 92,
  ultimo_pagamento: null, saldo_final: 572, estado: 'deve', de: null, ate: null, pago_aguardando_banco: 0, pago_falta_aprovar: 0,
};

/** Os reembolsos em aberto do Roberto (o do acerto nº 0007 primeiro, por data). */
let emAberto: Array<Record<string, unknown>> = [];
const CMP124 = { id: 'rb1', codigo: 'CMP-00124', data: '2026-09-18', valor: 62, categoria: 'Peças e materiais',
  descricao: 'Reembolso CMP-00124 · AutoZone', acerto: 7 };
const CMP130 = { id: 'rb2', codigo: 'CMP-00130', data: '2026-09-25', valor: 30, categoria: null,
  descricao: 'Reembolso CMP-00130 · Posto', acerto: null };
let propostaFalha = false;
/** O que a anotação do Pix disse além do ok (anotar_transacao): quantas iguais ela trocou. */
let substituidas = 0;

beforeEach(() => {
  emAberto = [];
  propostaFalha = false;
  substituidas = 0;
  vi.mocked(toast.success).mockReset();
  vi.mocked(toast.warning).mockReset();
  rpc.mockReset();
  rpc.mockImplementation(async (nome: string, args: Record<string, unknown>) => {
    if (nome === 'proposta_de_divisao_do_pagamento') {
      if (propostaFalha) return { data: null, error: { message: 'function proposta_de_divisao_do_pagamento does not exist' } };
      // como o banco: por data, somando enquanto cabe no valor
      const valor = Number(args.p_valor);
      const propostos: string[] = [];
      let soma = 0;
      for (const r of emAberto) if (soma + Number(r.valor) <= valor) { propostos.push(String(r.id)); soma += Number(r.valor); }
      return { data: { favorecido: { id: 'r', nome: 'Roberto Daniel' }, valor, em_aberto: emAberto, propostos,
        reembolsos: soma, diarias: valor - soma, partes: [] }, error: null };
    }
    if (nome === 'registrar_pagamento_do_freelancer') {
      return { data: { ok: true, forma: args.p_forma, anotacao_id: 'a9', payable_id: null,
        divisao: { id: 'dv1', status: 'pendente', diarias: 0, reembolsos: 0, partes: [] }, substituidas,
        message: substituidas ? 'Troquei a anotação anterior igual (mesma pessoa e valor) por esta. Pagamento registrado.' : 'Pagamento registrado.' },
        error: null };
    }
    return { data: null, error: { message: `rpc inesperada: ${nome}` } };
  });
});

function renderizar(onFechar = vi.fn()) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <RegistrarPagamentoDialog pessoas={[roberto]} favorecidoInicial="r" onFechar={onFechar} />
      </I18nProvider>
    </QueryClientProvider>,
  );
  return { dialogo: screen.getByRole('dialog'), onFechar };
}

const chamadas = (nome: string) => rpc.mock.calls.filter(([n]) => n === nome).map(([, a]) => a as Record<string, unknown>);
const digitarValor = (dialogo: HTMLElement, centavos: string) =>
  fireEvent.change(within(dialogo).getByLabelText('Valor (R$)'), { target: { value: centavos } });

/** O botão depois de conferir os reembolsos em aberto. */
async function botaoDeRegistrar(dialogo: HTMLElement) {
  const botao = await within(dialogo).findByRole('button', { name: 'Registrar pagamento' });
  await waitFor(() => expect(botao).toBeEnabled());
  return botao;
}

/** "Diárias R$ X · Reembolso de despesas pagas pelo técnico R$ Y", como a tela mostra. */
const totaisDaDivisao = (dialogo: HTMLElement) => within(dialogo).getByText(/^Diárias/).closest('p')!.textContent ?? '';

describe('RegistrarPagamentoDialog com a divisão', () => {
  it('sem reembolso em aberto: o diálogo de antes, tudo em Diárias', async () => {
    const user = userEvent.setup();
    const { dialogo, onFechar } = renderizar();
    digitarValor(dialogo, '20000');
    await user.click(await botaoDeRegistrar(dialogo));
    await waitFor(() => expect(chamadas('registrar_pagamento_do_freelancer')).toHaveLength(1));
    expect(chamadas('registrar_pagamento_do_freelancer')[0]).toMatchObject({ p_favorecido_id: 'r', p_valor: 200, p_forma: 'pix', p_reembolsos: [] });
    expect(within(dialogo).queryByText('Divisão deste pagamento')).not.toBeInTheDocument();
    await waitFor(() => expect(onFechar).toHaveBeenCalled());
  });

  it('com reembolsos em aberto: o banco propõe, a tela mostra cada CMP marcado e os dois totais', async () => {
    emAberto = [CMP124, CMP130];
    const { dialogo } = renderizar();
    digitarValor(dialogo, '50000');
    expect(await within(dialogo).findByText('Divisão deste pagamento')).toBeInTheDocument();
    const c124 = within(dialogo).getByRole('checkbox', { name: /CMP-00124/ });
    const c130 = within(dialogo).getByRole('checkbox', { name: /CMP-00130/ });
    expect(c124).toBeChecked();
    expect(c130).toBeChecked();
    // código, data, acerto; descrição sem o prefixo do banco e a categoria (sem categoria: para onde vai)
    expect(within(dialogo).getByText('CMP-00124 · 18/09 · acerto nº 0007')).toBeInTheDocument();
    expect(within(dialogo).getByText('AutoZone · Peças e materiais')).toBeInTheDocument();
    expect(within(dialogo).getByText('Posto · sem categoria (vai para Outras despesas)')).toBeInTheDocument();
    expect(totaisDaDivisao(dialogo)).toMatch(/Diárias R\$\s?408,00/);
    expect(totaisDaDivisao(dialogo)).toMatch(/Reembolso de despesas pagas pelo técnico R\$\s?92,00/);
    expect(chamadas('proposta_de_divisao_do_pagamento')).toContainEqual({ p_favorecido_id: 'r', p_valor: 500 });
  });

  it('o dono desmarca um reembolso: os totais acompanham e só o marcado vai para o banco', async () => {
    emAberto = [CMP124, CMP130];
    const user = userEvent.setup();
    const { dialogo } = renderizar();
    digitarValor(dialogo, '50000');
    await user.click(await within(dialogo).findByRole('checkbox', { name: /CMP-00130/ }));
    expect(totaisDaDivisao(dialogo)).toMatch(/Diárias R\$\s?438,00/);
    expect(totaisDaDivisao(dialogo)).toMatch(/Reembolso de despesas pagas pelo técnico R\$\s?62,00/);
    await user.click(within(dialogo).getByRole('radio', { name: /Dinheiro do Caixa/ }));
    await user.click(await botaoDeRegistrar(dialogo));
    await waitFor(() => expect(chamadas('registrar_pagamento_do_freelancer')).toHaveLength(1));
    expect(chamadas('registrar_pagamento_do_freelancer')[0]).toEqual({
      p_favorecido_id: 'r', p_valor: 500, p_data: expect.any(String), p_forma: 'dinheiro', p_socio_id: null,
      p_reembolsos: ['rb1'], p_descricao: 'Pagamento de diárias — Roberto',
    });
  });

  it('reembolso marcado que passa do valor pago: avisa e não registra', async () => {
    emAberto = [CMP124];
    const user = userEvent.setup();
    const { dialogo } = renderizar();
    digitarValor(dialogo, '5000');
    // R$ 62,00 não cabe em R$ 50,00: o banco não propõe; o dono marca à mão
    const caixa = await within(dialogo).findByRole('checkbox', { name: /CMP-00124/ });
    expect(caixa).not.toBeChecked();
    await user.click(caixa);
    expect(within(dialogo).getByText('Os reembolsos marcados passam do valor pago: desmarque algum.')).toBeInTheDocument();
    expect(within(dialogo).getByRole('button', { name: 'Registrar pagamento' })).toBeDisabled();
    expect(chamadas('registrar_pagamento_do_freelancer')).toEqual([]);
  });

  it('enquanto confere os reembolsos do valor digitado, não registra (o clique rápido não pula a divisão)', async () => {
    emAberto = [CMP124];
    const { dialogo } = renderizar();
    digitarValor(dialogo, '20000');
    const conferindo = within(dialogo).getByRole('button', { name: 'Conferindo…' });
    expect(conferindo).toBeDisabled();
    expect(await within(dialogo).findByRole('checkbox', { name: /CMP-00124/ })).toBeChecked();
  });

  it('a proposta falhou: avisa que vai tudo para Diárias e deixa registrar', async () => {
    propostaFalha = true;
    const user = userEvent.setup();
    const { dialogo } = renderizar();
    digitarValor(dialogo, '20000');
    expect(await within(dialogo).findByText(/Não deu para conferir os reembolsos em aberto/)).toBeInTheDocument();
    await user.click(await botaoDeRegistrar(dialogo));
    await waitFor(() => expect(chamadas('registrar_pagamento_do_freelancer')).toHaveLength(1));
    expect(chamadas('registrar_pagamento_do_freelancer')[0]).toMatchObject({ p_reembolsos: [] });
  });

  it('no celular o bloco empilha: nada com largura fixa que role de lado', async () => {
    emAberto = [CMP124, CMP130];
    const { dialogo } = renderizar();
    digitarValor(dialogo, '50000');
    const bloco = (await within(dialogo).findByText('Divisão deste pagamento')).closest('[role="group"]')!;
    expect(bloco).toHaveClass('min-w-0');
    // cada linha corta o texto (truncate) e o valor não encolhe
    for (const caixa of within(bloco as HTMLElement).getAllByRole('checkbox')) {
      const rotulo = caixa.closest('label')!;
      expect(rotulo).toHaveClass('min-w-0');
      expect(rotulo.querySelector('.truncate')).not.toBeNull();
    }
    expect(bloco.innerHTML).not.toMatch(/\bw-\[\d+px\]|min-w-\[\d+px\]/);
  });

  // Revisão dos ajustes (11/10/2026): o Pix que trocou uma anotação igual avisa por 15 s, como o Caixa
  // (caso do dono de 06/10/2026: dois "R$ 100 ao Roberto", um sumiu) — nunca o sucesso de 4 segundos.
  it('o Pix que substituiu uma anotação igual: aviso de 15 s, não sucesso', async () => {
    substituidas = 1;
    const user = userEvent.setup();
    const { dialogo } = renderizar();
    digitarValor(dialogo, '10000');
    await user.click(await botaoDeRegistrar(dialogo));
    await waitFor(() => expect(toast.warning).toHaveBeenCalledWith(expect.stringContaining('Troquei a anotação anterior igual'), { duration: 15_000 }));
    expect(toast.success).not.toHaveBeenCalled();
  });

  it('o Pix sem substituição: o sucesso de sempre', async () => {
    const user = userEvent.setup();
    const { dialogo } = renderizar();
    digitarValor(dialogo, '10000');
    await user.click(await botaoDeRegistrar(dialogo));
    await waitFor(() => expect(toast.success).toHaveBeenCalledWith('Pagamento registrado.'));
    expect(toast.warning).not.toHaveBeenCalled();
  });
});
