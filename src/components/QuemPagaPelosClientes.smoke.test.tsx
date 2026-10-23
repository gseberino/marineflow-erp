// "Quem paga pelos clientes" (leva 8, 22/10/2026): a lista histórica que o dono confere em Financeiro → Regras.
//
// O que se fixa: só administrador e financeiro veem (CPF de terceiro); CPF sai mascarado e CNPJ inteiro; a relação é
// obrigatória para marcar; "Guardar os marcados" manda só cliente, linha do banco e relação (o documento e o nome o
// banco relê); os casos com aviso — pagou para vários clientes, documento de outro cliente, nome idêntico — ficam
// FORA do lote mas se recusam um a um; "Não é pagador habitual" grava recusado (recusar_pagadores_do_cliente, só
// cliente e linha); o proposto pelo financeiro fica num bloco próprio — o administrador confirma ou recusa ali
// (decidir_pagador_do_cliente), o financeiro vê "aguardando o SIM do dono"; e erro de leitura aparece como erro, não
// como lista vazia.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import type { PagadorParaConferir } from '@/hooks/use-pagadores-do-cliente';

const estado = vi.hoisted(() => ({
  cargo: 'admin' as string,
  pares: [] as unknown[],
  erro: null as unknown,
  rpcs: [] as Array<{ nome: string; args: unknown }>,
  respostaRpc: { data: null as unknown, error: null as unknown },
  linhas: { data: [] as unknown, error: null as unknown },
  toasts: [] as Array<[string, string]>,
}));
const { guardarMock, reaplicarMock } = vi.hoisted(() => ({ guardarMock: vi.fn(), reaplicarMock: vi.fn() }));

vi.mock('@/hooks/use-auth', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-auth')>()),
  useOptionalAuth: () => ({ user: { role: estado.cargo } }),
}));
vi.mock('sonner', () => ({
  toast: {
    success: (m: string) => estado.toasts.push(['success', m]),
    warning: (m: string) => estado.toasts.push(['warning', m]),
    error: (m: string) => estado.toasts.push(['error', m]),
    info: (m: string) => estado.toasts.push(['info', m]),
  },
}));
vi.mock('@/integrations/supabase/client', () => {
  const cadeia: Record<string, unknown> = {};
  for (const m of ['select', 'in', 'order', 'eq']) cadeia[m] = () => cadeia;
  cadeia.then = (ok: (v: unknown) => unknown, nok: (e: unknown) => unknown) => Promise.resolve(estado.linhas).then(ok, nok);
  return {
    supabase: {
      from: () => cadeia,
      rpc: (nome: string, args: unknown) => { estado.rpcs.push({ nome, args }); return Promise.resolve(estado.respostaRpc); },
    },
  };
});
vi.mock('@/hooks/use-finance-review', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-finance-review')>()),
  useReaplicarRegras: () => ({ mutate: reaplicarMock, isPending: false }),
}));
vi.mock('@/hooks/use-pagadores-do-cliente', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-pagadores-do-cliente')>()),
  usePagadoresParaConferir: () => ({ data: estado.erro ? undefined : estado.pares, isLoading: false, error: estado.erro }),
  useGuardarPagadores: () => ({ mutate: guardarMock, isPending: false }),
}));

import { QuemPagaPelosClientes, avisoDoPar } from './QuemPagaPelosClientes';

function par(o: Partial<PagadorParaConferir>): PagadorParaConferir {
  return {
    client_id: 'c-ana', cliente_nome: 'Ana Souza', cliente_tem_documento: true,
    pagador_documento: '12345678901', pagador_nome: 'MARIA DA SILVA', tipo_documento: 'CPF',
    vezes: 3, total: 1500, primeira: '2026-06-01', ultima: '2026-09-10',
    bank_transaction_ids: ['bt-1', 'bt-2', 'bt-3'], grupo: 'documento_diferente', aviso: null,
    ...o,
  };
}

const LISTA: PagadorParaConferir[] = [
  par({}),
  par({
    client_id: 'c-rui', cliente_nome: 'Rui Prado', pagador_documento: '04754513000149', pagador_nome: 'PRADO NAUTICA LTDA',
    tipo_documento: 'CNPJ', vezes: 1, total: 800, bank_transaction_ids: ['bt-9'],
  }),
  par({
    client_id: 'c-leo', cliente_nome: 'Leo Dias', cliente_tem_documento: false, grupo: 'cliente_sem_documento',
    pagador_documento: '11122233344', pagador_nome: 'CARLA DIAS', vezes: 2, total: 400, bank_transaction_ids: ['bt-20'],
  }),
  par({
    client_id: 'c-bia', cliente_nome: 'Bia Lima', pagador_documento: '55566677788000', pagador_nome: 'MUNDO DOCE',
    tipo_documento: 'CNPJ', aviso: 'pagou_para_varios_clientes', bank_transaction_ids: ['bt-30'],
  }),
  par({
    client_id: 'c-gil', cliente_nome: 'Gil Rocha', pagador_documento: '99988877766', pagador_nome: 'OTAVIO ROCHA',
    aviso: 'documento_de_outro_cliente', bank_transaction_ids: ['bt-40'],
  }),
  par({
    client_id: 'c-zeca', cliente_nome: 'Zeca Moura', cliente_tem_documento: false, grupo: 'cliente_sem_documento',
    pagador_documento: '44455566677', pagador_nome: 'ZECA MOURA', bank_transaction_ids: ['bt-50'],
  }),
];

function renderizar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(<QueryClientProvider client={qc}><I18nProvider><QuemPagaPelosClientes /></I18nProvider></QueryClientProvider>);
}

function cartaoDe(texto: RegExp) {
  return screen.getAllByTestId('par-para-conferir').find((c) => texto.test(c.textContent ?? ''))!;
}

async function escolherRelacao(user: ReturnType<typeof userEvent.setup>, cartao: HTMLElement, rotulo: string) {
  await user.click(within(cartao).getByRole('combobox'));
  await user.click(await screen.findByRole('option', { name: rotulo }));
}

beforeEach(() => {
  guardarMock.mockReset(); reaplicarMock.mockReset();
  Object.assign(estado, {
    cargo: 'admin', pares: LISTA, erro: null, rpcs: [], toasts: [],
    respostaRpc: { data: null, error: null }, linhas: { data: [], error: null },
  });
});

describe('QuemPagaPelosClientes', () => {
  it('técnico e vendedor não veem nada (CPF de terceiro)', () => {
    estado.cargo = 'technician';
    const { container } = renderizar();
    expect(container).toBeEmptyDOMElement();
  });

  it('separa os dois grupos do que se decide um a um; CPF mascarado, CNPJ inteiro', () => {
    renderizar();
    expect(screen.getByText('6 para conferir')).toBeInTheDocument();
    expect(screen.getByText('Pagaram com outro CPF/CNPJ (2)')).toBeInTheDocument();
    expect(screen.getByText('Cliente sem CPF/CNPJ no cadastro (1)')).toBeInTheDocument();
    expect(screen.getByText('Decida um a um (3)')).toBeInTheDocument();
    const maria = cartaoDe(/MARIA DA SILVA/);
    expect(maria).toHaveTextContent(/MARIA DA SILVA pagou 3× \(R\$\s?1\.500,00\) por Ana Souza/);
    expect(maria).toHaveTextContent('CPF ***.456.789-**');
    expect(maria).not.toHaveTextContent('123.456.789-01');
    expect(cartaoDe(/PRADO NAUTICA/)).toHaveTextContent('CNPJ 04.754.513/0001-49');
  });

  it('a relação é obrigatória: sem ela não marca; escolhida, marca e "Guardar os marcados" manda só cliente, linha e relação', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderizar();
    const maria = cartaoDe(/MARIA DA SILVA/);
    expect(within(maria).getByRole('checkbox')).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Guardar os marcados (0)' })).toBeDisabled();

    await escolherRelacao(user, maria, 'Cônjuge');
    expect(within(maria).getByRole('checkbox')).toBeChecked();
    await escolherRelacao(user, cartaoDe(/PRADO NAUTICA/), 'Empresa do cliente');
    expect(screen.getByText('Ficam confirmados (é o seu SIM).')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Guardar os marcados (2)' }));
    expect(guardarMock.mock.calls[0][0]).toEqual([
      { client_id: 'c-ana', bank_transaction_id: 'bt-1', relacao: 'conjuge', origem: 'historico' },
      { client_id: 'c-rui', bank_transaction_id: 'bt-9', relacao: 'empresa_do_cliente', origem: 'historico' },
    ]);
  });

  it('desmarcado não vai; o recusado pelo banco continua marcado; confirmado revisa a fila', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderizar();
    const maria = cartaoDe(/MARIA DA SILVA/);
    await escolherRelacao(user, maria, 'Cônjuge');
    await escolherRelacao(user, cartaoDe(/PRADO NAUTICA/), 'Empresa do cliente');
    await escolherRelacao(user, cartaoDe(/CARLA DIAS/), 'Parente');
    await user.click(within(cartaoDe(/CARLA DIAS/)).getByRole('checkbox'));
    await user.click(screen.getByRole('button', { name: 'Guardar os marcados (2)' }));
    expect(guardarMock.mock.calls[0][0].map((i: { client_id: string }) => i.client_id)).toEqual(['c-ana', 'c-rui']);

    // O banco gravou a MARIA e recusou a PRADO (índice 2).
    guardarMock.mock.calls[0][1].onSuccess({
      ok: true, regras_consolidadas: [], message: '1 pagador guardado e confirmado.',
      gravados: [{ id: 'p1', client_id: 'c-ana', cliente: 'Ana Souza', nome: 'MARIA DA SILVA', relacao: 'conjuge', situacao: 'confirmado', ja_existia: false, regras_consolidadas: [] }],
      recusados: [{ indice: 2, client_id: 'c-rui', bank_transaction_id: 'bt-9', motivo: 'x' }],
    });
    expect(reaplicarMock).toHaveBeenCalledWith({ silencioso: true });
    expect(await screen.findByRole('button', { name: 'Guardar os marcados (1)' })).toBeInTheDocument();
    expect(within(cartaoDe(/PRADO NAUTICA/)).getByRole('checkbox')).toBeChecked();
  });

  it('casos com aviso ficam fora do lote: um a um, cada um com o que dá para fazer', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderizar();
    // Pagou para vários clientes: relação e "Guardar este", sem caixa de marcar.
    const mundo = cartaoDe(/MUNDO DOCE/);
    expect(within(mundo).queryByRole('checkbox')).not.toBeInTheDocument();
    expect(mundo).toHaveTextContent(/Pagou por mais de um cliente/);
    const guardarEste = within(mundo).getByRole('button', { name: 'Guardar este' });
    expect(guardarEste).toBeDisabled();
    await escolherRelacao(user, mundo, 'Marina');
    // Escolher a relação de um caso com aviso não o põe no lote.
    expect(screen.getByRole('button', { name: 'Guardar os marcados (0)' })).toBeDisabled();
    await user.click(guardarEste);
    expect(guardarMock.mock.calls[0][0]).toEqual([
      { client_id: 'c-bia', bank_transaction_id: 'bt-30', relacao: 'marina', origem: 'historico' },
    ]);

    // Documento de outro cliente: o banco não guarda — confira os cadastros.
    const otavio = cartaoDe(/OTAVIO ROCHA/);
    expect(otavio).toHaveTextContent(/possível cadastro duplicado/);
    expect(within(otavio).queryByRole('combobox')).not.toBeInTheDocument();
    expect(within(otavio).getByRole('link', { name: 'Abrir a ficha de Gil Rocha' })).toHaveAttribute('href', '/clients/c-gil');

    // Nome idêntico ao do cliente sem documento: é ele mesmo — completar o CPF na ficha.
    const zeca = cartaoDe(/ZECA MOURA pagou/);
    expect(zeca).toHaveTextContent(/Complete o CPF\/CNPJ na ficha do cliente/);
    expect(within(zeca).queryByRole('combobox')).not.toBeInTheDocument();
    expect(within(zeca).queryByRole('button', { name: /Não é pagador habitual/ })).not.toBeInTheDocument();
  });

  it('"Não é pagador habitual" grava recusado pela função do banco (só cliente e linha) e o par sai do lote', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estado.respostaRpc = { data: {
      ok: true, recusados: [], regras_consolidadas: [], avisos: [],
      gravados: [{ id: 'p1', client_id: 'c-ana', cliente: 'Ana Souza', nome: 'MARIA DA SILVA', relacao: 'outro', situacao: 'recusado', ja_existia: false, situacao_anterior: null, regras_consolidadas: [] }],
      message: '1 pagador recusado: não volta a ser sugerido nem à lista para conferir.',
    }, error: null };
    renderizar();
    const maria = cartaoDe(/MARIA DA SILVA/);
    // Marcada antes (relação escolhida); recusada, sai do lote.
    await escolherRelacao(user, maria, 'Cônjuge');
    expect(screen.getByRole('button', { name: 'Guardar os marcados (1)' })).toBeEnabled();
    await user.click(within(maria).getByRole('button', { name: /Não é pagador habitual/ }));
    expect(estado.rpcs).toEqual([{
      nome: 'recusar_pagadores_do_cliente',
      args: { p_itens: [{ client_id: 'c-ana', bank_transaction_id: 'bt-1', origem: 'historico' }], p_motivo: 'Não é pagador habitual' },
    }]);
    await vi.waitFor(() => expect(estado.toasts).toContainEqual(
      ['success', '1 pagador recusado: não volta a ser sugerido nem à lista para conferir.']));
    expect(await screen.findByRole('button', { name: 'Guardar os marcados (0)' })).toBeDisabled();
    // Um par novo recusado é o VETO do motor (revisão de 23/10/2026): o histórico deixa de sugerir aquele cliente, então
    // a fila é revisada em silêncio. Nada foi guardado por outro caminho.
    expect(reaplicarMock).toHaveBeenCalledWith({ silencioso: true });
    expect(guardarMock).not.toHaveBeenCalled();
  });

  it('os casos com aviso ficam fora do lote mas se recusam um a um (cadastro duplicado, vários clientes, ligação duvidosa)', async () => {
    const user = userEvent.setup();
    estado.pares = [...LISTA, par({
      client_id: 'c-col', cliente_nome: 'Colombo Doces', pagador_documento: '33344455566000', pagador_nome: 'MUNDO DOCE COLOMBO',
      tipo_documento: 'CNPJ', aviso: 'ligacao_duvidosa', bank_transaction_ids: ['bt-60'],
    })];
    estado.respostaRpc = { data: {
      ok: true, recusados: [], regras_consolidadas: [], avisos: [], message: '1 pagador recusado: não volta a ser sugerido nem à lista para conferir.',
      gravados: [{ id: 'p2', client_id: 'x', cliente: 'X', nome: 'N', relacao: 'outro', situacao: 'recusado', ja_existia: false, situacao_anterior: null, regras_consolidadas: [] }],
    }, error: null };
    renderizar();
    expect(screen.getByText('Decida um a um (4)')).toBeInTheDocument();
    const colombo = cartaoDe(/MUNDO DOCE COLOMBO/);
    expect(colombo).toHaveTextContent(/deve ser conciliação errada/);
    expect(within(colombo).queryByRole('checkbox')).not.toBeInTheDocument();

    await user.click(within(cartaoDe(/OTAVIO ROCHA/)).getByRole('button', { name: /Não é pagador habitual/ }));
    await user.click(within(cartaoDe(/MUNDO DOCE pagou/)).getByRole('button', { name: /Não é pagador habitual/ }));
    await user.click(within(colombo).getByRole('button', { name: /Não é pagador habitual/ }));
    expect(estado.rpcs.map((r) => r.nome)).toEqual(Array(3).fill('recusar_pagadores_do_cliente'));
    expect(estado.rpcs.map((r) => (r.args as { p_itens: Array<{ client_id: string; bank_transaction_id: string }> }).p_itens))
      .toEqual([
        [{ client_id: 'c-gil', bank_transaction_id: 'bt-40', origem: 'historico' }],
        [{ client_id: 'c-bia', bank_transaction_id: 'bt-30', origem: 'historico' }],
        [{ client_id: 'c-col', bank_transaction_id: 'bt-60', origem: 'historico' }],
      ]);
    expect(guardarMock).not.toHaveBeenCalled();
  });

  it('recusa barrada pelo banco (o financeiro diante de um confirmado) aparece como erro, com o motivo', async () => {
    const user = userEvent.setup();
    estado.cargo = 'financial';
    estado.respostaRpc = { data: {
      ok: false, gravados: [], regras_consolidadas: [], avisos: [],
      recusados: [{ indice: 1, client_id: 'c-ana', bank_transaction_id: 'bt-1', motivo: 'MARIA DA SILVA é pagador confirmado de Ana Souza; só o administrador recusa.' }],
      message: 'Nenhum pagador recusado. 1 não foi recusado: MARIA DA SILVA é pagador confirmado de Ana Souza; só o administrador recusa.',
    }, error: null };
    renderizar();
    await user.click(within(cartaoDe(/MARIA DA SILVA/)).getByRole('button', { name: /Não é pagador habitual/ }));
    await vi.waitFor(() => expect(estado.toasts).toContainEqual(
      ['error', 'Nenhum pagador recusado. 1 não foi recusado: MARIA DA SILVA é pagador confirmado de Ana Souza; só o administrador recusa.']));
  });

  it('"Ver os pagamentos" mostra as linhas do banco; erro de leitura aparece como erro', async () => {
    const user = userEvent.setup();
    estado.linhas = { data: [
      { id: 'bt-1', transaction_date: '2026-09-10', amount: 500, counterparty_name: 'MARIA DA SILVA', description: 'Pix recebido' },
    ], error: null };
    const { unmount } = renderizar();
    await user.click(within(cartaoDe(/MARIA DA SILVA/)).getByRole('button', { name: /Ver os pagamentos/ }));
    const lista = await screen.findByRole('list', { name: 'Pagamentos que embasam' });
    expect(lista).toHaveTextContent(/R\$\s?500,00/);
    expect(lista).toHaveTextContent('Pix recebido');
    unmount();

    estado.linhas = { data: null, error: { message: 'permission denied for table bank_transactions' } };
    renderizar();
    await user.click(within(cartaoDe(/MARIA DA SILVA/)).getByRole('button', { name: /Ver os pagamentos/ }));
    expect(await screen.findByText(/Não foi possível ler os pagamentos: permission denied/)).toBeInTheDocument();
  });

  it('nome do banco com o CPF dentro (cartão, linhas do banco e o toast do banco) sai mascarado', async () => {
    const user = userEvent.setup();
    estado.pares = [par({ pagador_nome: '12345678901-MARIA DA SILVA', bank_transaction_ids: ['bt-1'] })];
    estado.linhas = { data: [{
      id: 'bt-1', transaction_date: '2026-09-10', amount: 500,
      counterparty_name: '12345678901-MARIA DA SILVA', description: 'PIX RECEBIDO 123.456.789-01 MARIA',
    }], error: null };
    estado.respostaRpc = { data: {
      ok: true, recusados: [], regras_consolidadas: [], avisos: [],
      gravados: [{ id: 'p1', client_id: 'c-ana', cliente: 'Ana Souza', nome: '12345678901-MARIA DA SILVA', relacao: 'outro', situacao: 'recusado', ja_existia: false, situacao_anterior: null, regras_consolidadas: [] }],
      message: '12345678901-MARIA DA SILVA recusado como pagador de Ana Souza.',
    }, error: null };
    const { container } = renderizar();
    const cartao = cartaoDe(/MARIA DA SILVA/);
    expect(cartao).toHaveTextContent('***.456.789-**-MARIA DA SILVA pagou 3×');
    expect(within(cartao).getByRole('checkbox', { name: /Marcar \*\*\*\.456\.789-\*\*-MARIA DA SILVA/ })).toBeInTheDocument();
    await user.click(within(cartao).getByRole('button', { name: /Ver os pagamentos/ }));
    const lista = await screen.findByRole('list', { name: 'Pagamentos que embasam' });
    expect(lista).toHaveTextContent('***.456.789-**-MARIA DA SILVA');
    expect(lista).toHaveTextContent('PIX RECEBIDO ***.456.789-** MARIA');
    expect(container.textContent).not.toMatch(/12345678901|123\.456\.789-01/);

    await user.click(within(cartao).getByRole('button', { name: /Não é pagador habitual/ }));
    await vi.waitFor(() => expect(estado.toasts).toContainEqual(
      ['success', '***.456.789-**-MARIA DA SILVA recusado como pagador de Ana Souza.']));
  });

  it('erro na lista aparece como erro, não como "nada para conferir"', () => {
    estado.erro = { message: 'function pagadores_para_conferir() does not exist' };
    renderizar();
    expect(screen.getByText('Não foi possível carregar quem paga pelos clientes')).toBeInTheDocument();
    expect(screen.getByText(/does not exist/)).toBeInTheDocument();
  });

  it('financeiro: o que guardar fica proposto', async () => {
    estado.cargo = 'financial';
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderizar();
    expect(screen.getByText(/Você é do financeiro: o que guardar fica proposto/)).toBeInTheDocument();
    await escolherRelacao(user, cartaoDe(/MARIA DA SILVA/), 'Cônjuge');
    expect(screen.getByText('Ficam propostos: falta o SIM do administrador.')).toBeInTheDocument();
  });
});

describe('Propostos pelo financeiro (o SIM do administrador)', () => {
  const PROPOSTO = par({
    client_id: 'c-tom', cliente_nome: 'Tom Reis', pagador_documento: '22233344455', pagador_nome: 'LUIZA REIS',
    vezes: 2, total: 700, bank_transaction_ids: ['bt-70'],
    pagador_id: 'p-9', situacao: 'proposto', relacao_proposta: 'conjuge', proposto_por_nome: 'Felipe', proposto_em: '2026-10-21T15:00:00Z',
  });

  function cartaoProposto() {
    return screen.getAllByTestId('par-proposto').find((c) => /LUIZA REIS/.test(c.textContent ?? ''))!;
  }

  it('administrador: o proposto fica num bloco próprio, fora do lote, com quem propôs — e "Confirmar" é o SIM', async () => {
    const user = userEvent.setup();
    estado.pares = [PROPOSTO, ...LISTA];
    estado.respostaRpc = { data: {
      ok: true, id: 'p-9', situacao: 'confirmado', regras_consolidadas: [], message: 'LUIZA REIS confirmado como pagador de Tom Reis.',
    }, error: null };
    renderizar();
    // Os contadores separam o que falta conferir do que espera o SIM.
    expect(screen.getByText('6 para conferir')).toBeInTheDocument();
    expect(screen.getByText('1 proposto')).toBeInTheDocument();
    expect(screen.getByText('Propostos pelo financeiro (1)')).toBeInTheDocument();
    const cartao = cartaoProposto();
    expect(cartao).toHaveTextContent(/LUIZA REIS pagou 2× \(R\$\s?700,00\) por Tom Reis/);
    expect(cartao).toHaveTextContent('Proposto como cônjuge por Felipe em 21/10/2026.');
    expect(cartao).toHaveTextContent('CPF ***.333.444-**');
    // Fora do lote: sem caixa e não está entre os cartões para conferir. O seletor é o da relação AO CONFIRMAR,
    // já com a que o financeiro escolheu.
    expect(within(cartao).queryByRole('checkbox')).not.toBeInTheDocument();
    expect(within(cartao).getByRole('combobox', { name: 'Relação de LUIZA REIS com Tom Reis ao confirmar' })).toHaveTextContent('Cônjuge');
    expect(screen.getAllByTestId('par-para-conferir').some((c) => /LUIZA REIS/.test(c.textContent ?? ''))).toBe(false);

    await user.click(within(cartao).getByRole('button', { name: 'Confirmar LUIZA REIS como quem paga por Tom Reis' }));
    expect(estado.rpcs).toEqual([{
      nome: 'decidir_pagador_do_cliente', args: { p_id: 'p-9', p_decisao: 'confirmar', p_motivo: undefined },
    }]);
    // Confirmado muda o que a fila sugere: "Revisar a fila" em silêncio.
    await vi.waitFor(() => expect(reaplicarMock).toHaveBeenCalledWith({ silencioso: true }));
    expect(estado.toasts).toContainEqual(['success', 'LUIZA REIS confirmado como pagador de Tom Reis.']);
    expect(guardarMock).not.toHaveBeenCalled();
  });

  it('administrador: pode trocar a relação ao confirmar (vai p_relacao só quando trocou)', async () => {
    const user = userEvent.setup();
    estado.pares = [PROPOSTO];
    estado.respostaRpc = { data: {
      ok: true, id: 'p-9', situacao: 'confirmado', regras_consolidadas: [], message: 'LUIZA REIS confirmado como pagador de Tom Reis.',
    }, error: null };
    renderizar();
    const cartao = cartaoProposto();
    await user.click(within(cartao).getByRole('combobox', { name: 'Relação de LUIZA REIS com Tom Reis ao confirmar' }));
    await user.click(await screen.findByRole('option', { name: 'Parente' }));
    await user.click(within(cartaoProposto()).getByRole('button', { name: 'Confirmar LUIZA REIS como quem paga por Tom Reis' }));
    expect(estado.rpcs).toEqual([{
      nome: 'decidir_pagador_do_cliente', args: { p_id: 'p-9', p_decisao: 'confirmar', p_motivo: undefined, p_relacao: 'parente' },
    }]);
  });

  it('administrador: "Recusar" decide o proposto com o motivo e revisa a fila (o recusado é o veto do motor)', async () => {
    const user = userEvent.setup();
    estado.pares = [PROPOSTO];
    estado.respostaRpc = { data: {
      ok: true, id: 'p-9', situacao: 'recusado', regras_consolidadas: [], message: 'LUIZA REIS recusado como pagador de Tom Reis: não volta a ser sugerido.',
    }, error: null };
    renderizar();
    // Só com proposto, o bloco aparece (não é "nada para conferir").
    expect(screen.getByTestId('quem-paga-pelos-clientes')).toBeInTheDocument();
    expect(screen.queryByText(/para conferir$/)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Guardar os marcados/ })).not.toBeInTheDocument();

    await user.click(within(cartaoProposto()).getByRole('button', { name: 'Recusar LUIZA REIS como quem paga por Tom Reis' }));
    expect(estado.rpcs).toEqual([{
      nome: 'decidir_pagador_do_cliente', args: { p_id: 'p-9', p_decisao: 'recusar', p_motivo: 'Não é pagador habitual' },
    }]);
    await vi.waitFor(() => expect(estado.toasts).toContainEqual(
      ['success', 'LUIZA REIS recusado como pagador de Tom Reis: não volta a ser sugerido.']));
    // Recusar um PROPOSTO também muda a fila: o histórico e o nome idêntico deixam de sugerir Tom Reis para este CPF.
    await vi.waitFor(() => expect(reaplicarMock).toHaveBeenCalledWith({ silencioso: true }));
    expect(reaplicarMock).toHaveBeenCalledTimes(1);
  });

  it('financeiro: vê o proposto como "aguardando o SIM do dono", sem confirmar nem recusar', () => {
    estado.cargo = 'financial';
    estado.pares = [PROPOSTO, ...LISTA];
    renderizar();
    const cartao = cartaoProposto();
    expect(within(cartao).getByText('Aguardando o SIM do dono')).toBeInTheDocument();
    expect(within(cartao).queryByRole('button', { name: /Confirmar/ })).not.toBeInTheDocument();
    expect(within(cartao).queryByRole('button', { name: /Recusar|Não é pagador habitual/ })).not.toBeInTheDocument();
    expect(within(cartao).queryByRole('checkbox')).not.toBeInTheDocument();
    expect(within(cartao).getByRole('button', { name: /Ver os pagamentos/ })).toBeInTheDocument();
    expect(screen.getByText(/o administrador confirma aqui mesmo, em "Propostos pelo financeiro"/)).toBeInTheDocument();
  });

  it('proposto sem o nome de quem propôs (RLS de app_users) diz "pelo financeiro"; o aviso continua visível', () => {
    estado.pares = [par({ ...PROPOSTO, proposto_por_nome: null, aviso: 'pagou_para_varios_clientes' })];
    renderizar();
    const cartao = cartaoProposto();
    expect(cartao).toHaveTextContent('Proposto como cônjuge pelo financeiro em 21/10/2026.');
    expect(cartao).toHaveTextContent(/Pagou por mais de um cliente/);
  });
});

describe('avisoDoPar', () => {
  it('nome idêntico só conta para cliente SEM documento (com documento é a empresa dele ou homônimo)', () => {
    expect(avisoDoPar(par({ grupo: 'cliente_sem_documento', cliente_nome: 'Zeca Moura', pagador_nome: 'ZECA MOURA' }))).toBe('nome_identico');
    expect(avisoDoPar(par({ grupo: 'cliente_sem_documento', cliente_nome: 'Zeca Moura', pagador_nome: '65.010.587 ZECA MOURA' }))).toBe('nome_identico');
    expect(avisoDoPar(par({ grupo: 'documento_diferente', cliente_nome: 'Zeca Moura', pagador_nome: '65.010.587 ZECA MOURA' }))).toBeNull();
    expect(avisoDoPar(par({ grupo: 'cliente_sem_documento', cliente_nome: 'Zeca Moura', pagador_nome: 'ZECA MOURAO' }))).toBeNull();
    expect(avisoDoPar(par({ aviso: 'documento_de_outro_cliente' }))).toBe('documento_de_outro_cliente');
  });
});
