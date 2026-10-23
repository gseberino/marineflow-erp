// Quem é e o que paga — a prova e a escolha na linha do Extrato (Fase 2).
//
// O que se fixa: a prova do reconhecimento aparece escrita; "Cadastrar" abre o cadastro já
// preenchido e manda o documento; e a linha que pode já estar lançada NÃO se aprova no
// escuro — o caso dos três sinais de orçamento que viravam receita em dobro.
//
// Leva 8 (22/10/2026): na ENTRADA não existe mais "Cadastrar cliente" — a pergunta "De quem é
// este pagamento?" com três saídas; o cliente de pagador conhecido ou de histórico de terceiro é
// âmbar e pede "Sim, é do X"; e quem pagou por outro se guarda pelo "Guardar … como quem paga
// por …" (só administrador e financeiro). As saídas não mudam.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { EvidenciaDaLinha, VinculoDaLinha } from './ExtratoIdentificacao';
import type { VinculoSugerido, OpcaoDeVinculo } from '../../supabase/functions/_shared/banking/vinculo';

const { cadastrarMock, receita, guardarMock, reaplicarMock, sessao } = vi.hoisted(() => ({
  cadastrarMock: vi.fn(),
  receita: { dados: null as unknown },
  guardarMock: vi.fn(),
  reaplicarMock: vi.fn(),
  sessao: { cargo: 'admin' as string },
}));

vi.mock('@/hooks/use-contraparte', () => ({
  useConsultaDeDocumento: () => ({ data: receita.dados ? { ok: true, tipo: 'cnpj', documento: '90136409000122', dados: receita.dados } : undefined, isLoading: false }),
  useCadastrarContraparte: () => ({ mutate: cadastrarMock, isPending: false }),
}));
vi.mock('@/hooks/use-financial-categories', () => ({
  useFinancialCategories: () => ({ data: [{ id: '1', name: 'Frete e importação' }, { id: '2', name: 'Outras despesas' }] }),
}));
vi.mock('@/hooks/use-finance-review', () => ({
  useCriarCategoriaDespesa: () => ({ mutate: vi.fn(), isPending: false }),
  useReaplicarRegras: () => ({ mutate: reaplicarMock, isPending: false }),
}));
vi.mock('@/hooks/use-auth', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-auth')>()),
  useOptionalAuth: () => ({ user: { role: sessao.cargo } }),
}));
vi.mock('@/hooks/use-payees', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-payees')>()),
  useClientesParaReceita: () => ({ data: [{ id: 'c-ana', name: 'Ana Souza' }, { id: 'c-rui', name: 'Rui Prado' }] }),
}));
vi.mock('@/hooks/use-pagadores-do-cliente', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-pagadores-do-cliente')>()),
  useGuardarPagadores: () => ({ mutate: guardarMock, isPending: false }),
}));

function renderizar(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><I18nProvider>{ui}</I18nProvider></QueryClientProvider>);
}

beforeEach(() => {
  cadastrarMock.mockReset(); guardarMock.mockReset(); reaplicarMock.mockReset();
  receita.dados = null; sessao.cargo = 'admin';
});

const linhaDoBanco = { id: 'bt-1', documento: '123.456.789-01', nome: 'MARIA DA SILVA' };

describe('EvidenciaDaLinha', () => {
  it('diz quem é e por qual prova', () => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} evidencia={{
      cliente: { id: 'c', nome: 'Acrisio Cançado Lopes', por: 'historico', detalhe: 'Este CNPJ já pagou 1× em nome de Acrisio — confira' },
    }} />);
    expect(screen.getByText('Acrisio Cançado Lopes')).toBeInTheDocument();
    expect(screen.getByText(/por lançamentos anteriores/)).toBeInTheDocument();
  });

  it('histórico de terceiro na ENTRADA é âmbar e pede "Sim, é do X"; na SAÍDA continua verde', async () => {
    const onMudar = vi.fn();
    const user = userEvent.setup();
    const { unmount } = renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={onMudar}
      evidencia={{ cliente: { id: 'c-ana', nome: 'Ana Souza', por: 'historico', detalhe: 'Este CPF já pagou 2× em nome de Ana Souza — confira' } }} />);
    expect(screen.getByText(/Cliente:/).closest('div')!.className).toMatch(/amber/);
    const caixa = screen.getByTestId('cliente-pede-sim');
    expect(within(caixa).getByText(/já pagou 2× em nome de Ana Souza — confira\. É dele\?/)).toBeInTheDocument();
    await user.click(within(caixa).getByRole('button', { name: 'Sim, é do Ana Souza' }));
    expect(onMudar).toHaveBeenCalledWith({ clientId: 'c-ana' });
    unmount();

    renderizar(<EvidenciaDaLinha ehReceita={false} categoria="Peças e materiais" ocupado={false}
      evidencia={{ fornecedor: { id: 'f', nome: 'Coremma', por: 'historico', detalhe: 'Este CNPJ já recebeu 3×' } }} />);
    expect(screen.getByText(/Fornecedor:/).closest('div')!.className).toMatch(/text-success/);
    expect(screen.queryByTestId('cliente-pede-sim')).not.toBeInTheDocument();
  });

  it('pagador conhecido: chip âmbar com o motivo, "Sim, é do X" — e depois do SIM, "desfazer"', async () => {
    const onMudar = vi.fn();
    const user = userEvent.setup();
    const evidencia = { cliente: {
      id: 'c-ana', nome: 'Ana Souza', por: 'pagador_conhecido' as const, relacao: 'conjuge',
      detalhe: 'Pago pelo cônjuge de Ana Souza, guardado por você em 12/10 — confira',
    } };
    const { rerender } = renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false}
      onMudar={onMudar} transacao={linhaDoBanco} evidencia={evidencia} />);
    expect(screen.getByText(/por pagador conhecido — confira/)).toBeInTheDocument();
    expect(screen.getByText(/Pago pelo cônjuge de Ana Souza, guardado por você em 12\/10 — confira\. É dele\?/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Sim, é do Ana Souza' }));
    expect(onMudar).toHaveBeenCalledWith({ clientId: 'c-ana' });

    // Respondido: já guardado para ela, não oferece guardar de novo.
    rerender(<QueryClientProvider client={new QueryClient()}><I18nProvider>
      <EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={onMudar}
        transacao={linhaDoBanco} evidencia={evidencia} clienteId="c-ana" />
    </I18nProvider></QueryClientProvider>);
    expect(screen.getByText(/Você confirmou: é do/)).toBeInTheDocument();
    expect(screen.queryByText(/como quem paga por/)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'desfazer' }));
    expect(onMudar).toHaveBeenLastCalledWith({ clientId: undefined });
  });

  it('ENTRADA sem cliente: nunca "Cadastrar cliente" — pergunta de quem é, com as três saídas', async () => {
    const onMudar = vi.fn();
    const user = userEvent.setup();
    renderizar(<EvidenciaDaLinha ehReceita categoria="Outras receitas" ocupado={false} onMudar={onMudar} transacao={linhaDoBanco}
      evidencia={{ deQuemE: { documento: '12345678901', nome: 'MARIA DA SILVA', candidatos: [] } }} />);
    expect(screen.queryByRole('button', { name: /Cadastrar cliente/ })).not.toBeInTheDocument();
    const pergunta = screen.getByTestId('de-quem-e');
    expect(within(pergunta).getByText('De quem é este pagamento?')).toBeInTheDocument();
    expect(within(pergunta).getByText(/ainda não pagou por nenhum cliente/)).toBeInTheDocument();
    expect(within(pergunta).getByText(/escolha em "De qual cliente veio\?"/)).toBeInTheDocument();

    // (iii) Não é de cliente: as categorias que dispensam cliente.
    await user.click(within(pergunta).getByRole('button', { name: 'Aporte de sócio' }));
    expect(onMudar).toHaveBeenCalledWith({ category: 'Aporte de sócio' });
    expect(within(pergunta).getByRole('button', { name: 'Transferência entre contas' })).toBeInTheDocument();

    // (ii) É cliente novo: a ÚNICA saída que abre o cadastro, já como cliente.
    await user.click(within(pergunta).getByRole('button', { name: /É cliente novo \(quem pagou é o próprio cliente\)/ }));
    expect(screen.getByText('Cadastrar a partir do extrato')).toBeInTheDocument();
    expect(screen.getByDisplayValue('MARIA DA SILVA')).toBeInTheDocument();
    expect(screen.getByText('Cliente (quem me paga)')).toBeInTheDocument();
  });

  it('linha antiga da fila que ainda traz "cadastrar cliente" vira a mesma pergunta', () => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Outras receitas" ocupado={false} onMudar={() => {}}
      evidencia={{ cadastrar: { tipo: 'cliente', documento: '12345678901', nome: 'MARIA DA SILVA' } }} />);
    expect(screen.queryByRole('button', { name: /Cadastrar cliente/ })).not.toBeInTheDocument();
    expect(screen.getByTestId('de-quem-e')).toBeInTheDocument();
  });

  it('pagou por mais de um cliente: os candidatos viram botões, nenhum é escolhido sozinho', async () => {
    const onMudar = vi.fn();
    const user = userEvent.setup();
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={onMudar}
      evidencia={{ deQuemE: { documento: '04754513000149', nome: 'MUNDO DOCE', candidatos: [
        { id: 'c-ana', nome: 'Ana Souza', relacao: 'marina' }, { id: 'c-rui', nome: 'Rui Prado', relacao: 'marina' },
      ] } }} />);
    expect(screen.getByText(/paga por mais de um cliente — de qual é este\?/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'É do Rui Prado (Marina)' }));
    expect(onMudar).toHaveBeenCalledWith({ clientId: 'c-rui' });
  });

  it('escolhido um dos candidatos (já é pagador confirmado dele): não oferece guardar de novo — nem ao financeiro', () => {
    const mundoDoce = { id: 'bt-30', documento: '04.754.513/0001-49', nome: 'MUNDO DOCE' };
    const evidencia = { deQuemE: { documento: '04754513000149', nome: 'MUNDO DOCE', candidatos: [
      { id: 'c-ana', nome: 'Ana Souza', relacao: 'marina' }, { id: 'c-rui', nome: 'Rui Prado', relacao: 'marina' },
    ] } };
    const { rerender, unmount } = renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false}
      onMudar={() => {}} transacao={mundoDoce} clienteId="c-rui" evidencia={evidencia} />);
    expect(screen.getByText(/De quem é este pagamento:/)).toHaveTextContent('Rui Prado');
    expect(screen.queryByText(/como quem paga por/)).not.toBeInTheDocument();

    // Escolhido um cliente que NÃO está entre os candidatos (escolheu em "De qual cliente veio?"): aí sim, oferece.
    const em = (clienteId: string, candidatos: Array<{ id: string; nome: string; relacao: string }>) => (
      <QueryClientProvider client={new QueryClient()}><I18nProvider>
        <EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
          transacao={mundoDoce} clienteId={clienteId} evidencia={{ deQuemE: { ...evidencia.deQuemE, candidatos } }} />
      </I18nProvider></QueryClientProvider>
    );
    rerender(em('c-rui', [{ id: 'c-ana', nome: 'Ana Souza', relacao: 'marina' }]));
    expect(screen.getByRole('button', { name: 'Guardar MUNDO DOCE como quem paga por Rui Prado' })).toBeInTheDocument();

    // O candidato "regra antiga" (regra de outro cliente em conflito) não é pagador guardado: guardar é o SIM que falta.
    rerender(em('c-rui', [{ id: 'c-ana', nome: 'Ana Souza', relacao: 'marina' }, { id: 'c-rui', nome: 'Rui Prado', relacao: 'regra antiga' }]));
    expect(screen.getByRole('button', { name: 'Guardar MUNDO DOCE como quem paga por Rui Prado' })).toBeInTheDocument();
    // O candidato que é o dono do documento também não oferece (o banco recusaria: é o próprio cliente).
    rerender(em('c-rui', [{ id: 'c-ana', nome: 'Ana Souza', relacao: 'marina' }, { id: 'c-rui', nome: 'Rui Prado', relacao: 'documento do cliente' }]));
    expect(screen.queryByText(/como quem paga por/)).not.toBeInTheDocument();
    unmount();

    sessao.cargo = 'financial';
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false}
      onMudar={() => {}} transacao={mundoDoce} clienteId="c-ana" evidencia={evidencia} />);
    expect(screen.queryByText(/como quem paga por/)).not.toBeInTheDocument();
  });

  it('cliente escolhido e documento de outra pessoa: "Guardar … como quem paga por …" grava pela função e revisa a fila', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      transacao={linhaDoBanco} clienteId="c-ana"
      evidencia={{ deQuemE: { documento: '12345678901', nome: 'MARIA DA SILVA', candidatos: [] } }} />);
    // Escolhido: a pergunta encolhe para a resposta.
    expect(screen.queryByTestId('de-quem-e')).not.toBeInTheDocument();
    expect(screen.getByText(/De quem é este pagamento:/)).toHaveTextContent('Ana Souza');

    await user.click(screen.getByRole('button', { name: 'Guardar MARIA DA SILVA como quem paga por Ana Souza' }));
    // CPF de terceiro mascarado, e a relação é obrigatória.
    expect(screen.getByText(/CPF \*\*\*\.456\.789-\*\*/)).toBeInTheDocument();
    expect(screen.getByText(/fica confirmado \(é o seu SIM\)/)).toBeInTheDocument();
    const salvar = screen.getByRole('button', { name: 'Guardar' });
    expect(salvar).toBeDisabled();
    await user.click(screen.getByRole('combobox', { name: 'Quem é para o cliente?' }));
    await user.click(await screen.findByRole('option', { name: 'Cônjuge' }));
    await user.click(salvar);
    // O documento e o nome NÃO vão: o banco os relê da linha.
    expect(guardarMock.mock.calls[0][0]).toEqual([
      { client_id: 'c-ana', bank_transaction_id: 'bt-1', relacao: 'conjuge', observacao: null, origem: 'fila' },
    ]);
    guardarMock.mock.calls[0][1].onSuccess({
      ok: true, recusados: [], regras_consolidadas: [], message: '1 pagador guardado e confirmado.',
      gravados: [{ id: 'p1', client_id: 'c-ana', cliente: 'Ana Souza', nome: 'MARIA DA SILVA', relacao: 'conjuge', situacao: 'confirmado', ja_existia: false, regras_consolidadas: [] }],
    });
    expect(reaplicarMock).toHaveBeenCalledWith({ silencioso: true });
  });

  it('financeiro também guarda (fica proposto); técnico nem vê o link', () => {
    sessao.cargo = 'financial';
    const props = {
      ehReceita: true, categoria: 'Serviços prestados', ocupado: false, onMudar: () => {}, transacao: linhaDoBanco,
      clienteId: 'c-ana', evidencia: { deQuemE: { documento: '12345678901', nome: 'MARIA DA SILVA', candidatos: [] } },
    };
    const { unmount } = renderizar(<EvidenciaDaLinha {...props} />);
    expect(screen.getByRole('button', { name: /como quem paga por Ana Souza/ })).toBeInTheDocument();
    unmount();
    sessao.cargo = 'technician';
    renderizar(<EvidenciaDaLinha {...props} />);
    expect(screen.queryByRole('button', { name: /como quem paga por/ })).not.toBeInTheDocument();
  });

  it('documento do próprio cliente não oferece guardar; nome igual ao do cliente avisa para completar o CPF', () => {
    const { unmount } = renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      transacao={linhaDoBanco} clienteId="c-ana"
      evidencia={{ cliente: { id: 'c-ana', nome: 'Ana Souza', por: 'documento', detalhe: 'CPF confere com o cliente Ana Souza' } }} />);
    expect(screen.queryByRole('button', { name: /como quem paga por/ })).not.toBeInTheDocument();
    expect(screen.queryByTestId('cliente-pede-sim')).not.toBeInTheDocument();
    unmount();

    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      transacao={{ id: 'bt-2', documento: '98765432100', nome: 'ANA SOUZA' }} clienteId="c-ana"
      evidencia={{ deQuemE: { documento: '98765432100', nome: 'ANA SOUZA', candidatos: [] } }} />);
    expect(screen.getByText(/Mesmo nome do cliente: se for ele mesmo, complete o CPF\/CNPJ na ficha dele/)).toBeInTheDocument();
  });

  it('entrada marcada como transferência ou aporte não pergunta de quem é', () => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Transferência entre contas" ocupado={false} onMudar={() => {}}
      evidencia={{ deQuemE: { documento: '12345678901', nome: 'MARIA DA SILVA', candidatos: [] } }} />);
    expect(screen.queryByTestId('de-quem-e')).not.toBeInTheDocument();
  });

  // Revisão de 23/10/2026: a anotação do dono ("o Pix de 1.500 é da TSD") é o SIM dele. O _aplicar_anotacao troca o
  // cliente sugerido e deixa a prova antiga do motor (de outro cliente) na evidência.
  it('anotação que trocou o cliente: vale o anotado, sem "Sim, é do <outro>" nem chip da prova antiga', () => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      transacao={linhaDoBanco} clienteSugeridoId="c-rui" clienteId="c-rui"
      evidencia={{
        cliente: { id: 'c-ana', nome: 'Ana Souza', por: 'pagador_conhecido', relacao: 'conjuge', detalhe: 'Pago pelo cônjuge de Ana Souza — confira' },
        // A marca que o _aplicar_anotacao grava (jsonb_strip_nulls({id, os_id})).
        anotacao: { id: 'an-1' },
      }} />);
    expect(screen.queryByTestId('cliente-pede-sim')).not.toBeInTheDocument();
    expect(screen.queryByTestId('cliente-falta-escolher')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Sim, é do/ })).not.toBeInTheDocument();
    expect(screen.queryByText(/Cliente:/)).not.toBeInTheDocument();
    const linha = screen.getByTestId('cliente-de-fora-do-motor');
    expect(linha).toHaveTextContent('Você anotou: é do Rui Prado.');
    expect(linha).toHaveTextContent('O sistema tinha sugerido Ana Souza (pagador conhecido — confira) — vale a sua anotação.');
    // Quem pagou não é o Rui pela prova: guardar continua oferecido.
    expect(screen.getByRole('button', { name: 'Guardar MARIA DA SILVA como quem paga por Rui Prado' })).toBeInTheDocument();
  });

  it('anotação com a OS do mesmo cliente da prova é o SIM: sem a caixa âmbar, e o chip deixa de ser âmbar', () => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      clienteSugeridoId="c-ana" clienteId="c-ana"
      evidencia={{
        cliente: { id: 'c-ana', nome: 'Ana Souza', por: 'historico', detalhe: 'Este CPF já pagou 2× em nome de Ana Souza — confira' },
        anotacao: { id: 'an-2', os_id: 'os-60' },
      }} />);
    expect(screen.queryByTestId('cliente-pede-sim')).not.toBeInTheDocument();
    expect(screen.queryByText(/Você confirmou/)).not.toBeInTheDocument();
    expect(screen.getByText(/Cliente:/).closest('div')!.className).not.toMatch(/amber/);
    expect(screen.getByTestId('cliente-de-fora-do-motor')).toHaveTextContent('Você anotou: é do Ana Souza.');
  });

  it('anotação só com categoria não é o SIM: a prova do mesmo cliente continua pedindo "Sim, é do X"', () => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      clienteSugeridoId="c-ana" clienteId={null}
      evidencia={{
        cliente: { id: 'c-ana', nome: 'Ana Souza', por: 'historico', detalhe: 'Este CPF já pagou 2× em nome de Ana Souza — confira' },
        anotacao: { id: 'an-3', os_id: null },
      }} />);
    expect(screen.getByRole('button', { name: 'Sim, é do Ana Souza' })).toBeInTheDocument();
    expect(screen.queryByTestId('cliente-de-fora-do-motor')).not.toBeInTheDocument();
    expect(screen.queryByTestId('cliente-falta-escolher')).not.toBeInTheDocument();
  });

  // 4ª rodada: desligar o comprovante desfaz a anotação — a marca sai da evidência e o sugerido que ela pôs FICA. O
  // sugerido não é o da prova e ninguém mais disse de quem é: o servidor recusa com "Escolha o cliente…".
  it('anotação desfeita (sugerido ≠ prova, sem a marca): falta escolher — nenhum cliente oferecido, nem "Sim, é do <prova>"', () => {
    const evidencia = {
      cliente: { id: 'c-ana', nome: 'Ana Souza', por: 'pagador_conhecido' as const, relacao: 'conjuge', detalhe: 'Pago pelo cônjuge de Ana Souza — confira' },
    };
    const { container, rerender } = renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false}
      onMudar={() => {}} transacao={linhaDoBanco} clienteSugeridoId="c-rui" clienteId={null} evidencia={evidencia} />);
    const aviso = screen.getByTestId('cliente-falta-escolher');
    expect(aviso).toHaveTextContent('De quem é este pagamento?');
    expect(aviso).toHaveTextContent('Escolha o cliente em "De qual cliente veio?"');
    expect(screen.queryByTestId('cliente-pede-sim')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Sim, é do/ })).not.toBeInTheDocument();
    expect(screen.queryByText(/Cliente:/)).not.toBeInTheDocument();
    expect(screen.queryByTestId('cliente-de-fora-do-motor')).not.toBeInTheDocument();
    expect(screen.queryByText(/Você anotou/)).not.toBeInTheDocument();
    expect(screen.queryByText(/Guardar/)).not.toBeInTheDocument();
    // Nenhum cliente é nomeado: nem o sugerido (Rui), nem o da prova antiga (Ana).
    expect(container.textContent).not.toMatch(/Rui Prado|Ana Souza/);

    // Escolhido o cliente em "De qual cliente veio?": o aviso sai e quem pagou pode ser guardado como pagador dele.
    rerender(<QueryClientProvider client={new QueryClient()}><I18nProvider>
      <EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}} transacao={linhaDoBanco}
        clienteSugeridoId="c-rui" clienteId="c-rui" evidencia={evidencia} />
    </I18nProvider></QueryClientProvider>);
    expect(screen.queryByTestId('cliente-falta-escolher')).not.toBeInTheDocument();
    expect(screen.queryByText(/Você anotou/)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Guardar MARIA DA SILVA como quem paga por Rui Prado' })).toBeInTheDocument();
  });

  it('marca de anotação sem o id (não é a de uma anotação em vigor) também não basta: falta escolher', () => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      clienteSugeridoId="c-rui" clienteId={null}
      evidencia={{
        cliente: { id: 'c-ana', nome: 'Ana Souza', por: 'historico', detalhe: 'Este CPF já pagou 2× em nome de Ana Souza — confira' },
        anotacao: { os_id: null },
      }} />);
    expect(screen.getByTestId('cliente-falta-escolher')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Sim, é do/ })).not.toBeInTheDocument();
  });

  it('a pergunta "de quem é?" que SOBROU depois da anotação ou do "É cliente novo" não volta', () => {
    const deQuemE = { documento: '12345678901', nome: 'MARIA DA SILVA', candidatos: [] };
    // Anotação: diz de onde veio o cliente.
    const { unmount } = renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      transacao={linhaDoBanco} clienteSugeridoId="c-rui" clienteId="c-rui"
      evidencia={{ deQuemE, anotacao: { id: 'an-4', os_id: null } }} />);
    expect(screen.queryByTestId('de-quem-e')).not.toBeInTheDocument();
    expect(screen.queryByText(/De quem é este pagamento/)).not.toBeInTheDocument();
    expect(screen.getByTestId('cliente-de-fora-do-motor')).toHaveTextContent('Você anotou: é do Rui Prado.');
    unmount();

    // Cadastro pela linha ("É cliente novo": quem pagou É o cliente). O banco tira o `cadastrar`, põe o cliente novo no
    // sugerido e grava a prova por documento (extrato_quem_e_quem): nada a perguntar, nada a guardar.
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      transacao={linhaDoBanco} clienteSugeridoId="c-novo" clienteId="c-novo"
      evidencia={{ deQuemE, cliente: { id: 'c-novo', nome: 'MARIA DA SILVA', por: 'documento', detalhe: 'CPF confere com o cliente MARIA DA SILVA' } }} />);
    expect(screen.queryByTestId('de-quem-e')).not.toBeInTheDocument();
    expect(screen.queryByTestId('cliente-falta-escolher')).not.toBeInTheDocument();
    expect(screen.getByText(/Cliente:/)).toHaveTextContent('Cliente: MARIA DA SILVA · por CPF/CNPJ');
    expect(screen.queryByText(/Guardar/)).not.toBeInTheDocument();
  });

  it('a pergunta que estava na evidência VOLTA quando ninguém resolveu de quem é (sugerido sem prova nem anotação)', () => {
    // A anotação que respondeu "de quem é?" foi desfeita: a marca sai, o sugerido fica — a pergunta vale de novo (como
    // no assistente), sem oferecer o sugerido.
    const { container } = renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      transacao={linhaDoBanco} clienteSugeridoId="c-rui" clienteId={null}
      evidencia={{ deQuemE: { documento: '12345678901', nome: 'MARIA DA SILVA', candidatos: [] } }} />);
    expect(screen.getByTestId('de-quem-e')).toHaveTextContent('MARIA DA SILVA ainda não pagou por nenhum cliente');
    // A pergunta já pede a escolha: sem o aviso repetido, e sem nomear o sugerido.
    expect(screen.queryByTestId('cliente-falta-escolher')).not.toBeInTheDocument();
    expect(screen.queryByTestId('cliente-de-fora-do-motor')).not.toBeInTheDocument();
    expect(container.textContent).not.toMatch(/Rui Prado/);
  });

  // 4ª rodada (C3): com UM candidato só, a frase vem da relação dele. Um candidato só aparece quando NÃO deu para ler
  // os pagadores guardados (nome idêntico, regra antiga) — "já foi guardado" ali seria falso.
  it.each([
    ['nome idêntico', 'O nome é idêntico ao do cliente Ana Souza, mas não deu para conferir os pagadores guardados — confirme.', 'É do Ana Souza (nome idêntico)'],
    ['regra antiga', 'Uma regra antiga diz que este CPF/CNPJ é do cliente Ana Souza, mas não deu para conferir os pagadores guardados — confirme.', 'É do Ana Souza (regra antiga)'],
    ['documento do cliente', 'Pode ser do Ana Souza — confirme.', 'É do Ana Souza (documento do cliente)'],
  ])('um candidato com relação "%s": sem "já foi guardado"', (relacao, frase, botao) => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      transacao={linhaDoBanco}
      evidencia={{ deQuemE: { documento: '12345678901', nome: 'MARIA DA SILVA', candidatos: [{ id: 'c-ana', nome: 'Ana Souza', relacao }] } }} />);
    const pergunta = screen.getByTestId('de-quem-e');
    expect(pergunta).toHaveTextContent(frase);
    expect(pergunta).not.toHaveTextContent(/já foi guardado/);
    expect(within(pergunta).getByRole('button', { name: botao })).toBeInTheDocument();
  });

  it('um candidato com relação de pagador (cônjuge): "já foi guardado como quem paga por X"', () => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      transacao={linhaDoBanco}
      evidencia={{ deQuemE: { documento: '12345678901', nome: 'MARIA DA SILVA', candidatos: [{ id: 'c-ana', nome: 'Ana Souza', relacao: 'conjuge' }] } }} />);
    const pergunta = screen.getByTestId('de-quem-e');
    expect(pergunta).toHaveTextContent('MARIA DA SILVA já foi guardado como quem paga por Ana Souza.');
    expect(within(pergunta).getByRole('button', { name: 'É do Ana Souza (Cônjuge)' })).toBeInTheDocument();
  });

  it('sem cliente sugerido, a pergunta continua — também na linha antiga com "cadastrar cliente"', () => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}}
      clienteSugeridoId={null}
      evidencia={{ cadastrar: { tipo: 'cliente', documento: '12345678901', nome: 'MARIA DA SILVA' } }} />);
    expect(screen.getByTestId('de-quem-e')).toBeInTheDocument();
  });

  it('nome do banco com o CPF dentro sai mascarado na pergunta e no "Guardar …"', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    const comCpf = { id: 'bt-7', documento: '12345678901', nome: '12345678901-MARIA DA SILVA' };
    const { container, rerender } = renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false}
      onMudar={() => {}} transacao={comCpf}
      evidencia={{ deQuemE: { documento: '12345678901', nome: '12345678901-MARIA DA SILVA', candidatos: [] } }} />);
    expect(screen.getByTestId('de-quem-e')).toHaveTextContent('***.456.789-**-MARIA DA SILVA ainda não pagou por nenhum cliente');
    expect(container.textContent).not.toMatch(/12345678901/);

    rerender(<QueryClientProvider client={new QueryClient()}><I18nProvider>
      <EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} onMudar={() => {}} transacao={comCpf}
        clienteId="c-ana" evidencia={{ deQuemE: { documento: '12345678901', nome: '12345678901-MARIA DA SILVA', candidatos: [] } }} />
    </I18nProvider></QueryClientProvider>);
    await user.click(screen.getByRole('button', { name: 'Guardar ***.456.789-**-MARIA DA SILVA como quem paga por Ana Souza' }));
    const dialogo = await screen.findByRole('dialog');
    expect(dialogo).toHaveTextContent('***.456.789-**-MARIA DA SILVA (CPF ***.456.789-**) pagou por Ana Souza');
    expect(document.body.textContent).not.toMatch(/12345678901/);
  });

  it('cadastrar abre preenchido pela Receita e manda o documento e a categoria da atividade', async () => {
    receita.dados = {
      cnpj: '90136409000122', razao_social: 'TSD LOGISTICA E DISTRIBUIDORA LTDA', nome_fantasia: 'TSD',
      situacao: 'ATIVA', cnae: '4930202', cnae_descricao: 'Transporte rodoviário de carga', cidade: 'ITAJAI', uf: 'SC',
      cep: null, logradouro: null, numero: null, complemento: null, bairro: null, telefone: null, email: null,
      categoria_sugerida: 'Frete e importação',
    };
    const user = userEvent.setup();
    renderizar(<EvidenciaDaLinha ehReceita={false} categoria="Outras despesas" ocupado={false} evidencia={{
      cadastrar: { tipo: 'fornecedor', documento: '90136409000122', nome: 'TSD LOGISTICA' },
    }} />);
    await user.click(screen.getByRole('button', { name: /Cadastrar fornecedor/ }));
    expect(screen.getByDisplayValue('TSD LOGISTICA E DISTRIBUIDORA LTDA')).toBeInTheDocument();
    expect(screen.getByText(/Sugerida pela atividade na Receita: Frete e importação/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Cadastrar' }));
    expect(cadastrarMock.mock.calls[0][0]).toMatchObject({
      tipo: 'fornecedor',
      dados: { documento: '90136409000122', nome: 'TSD LOGISTICA E DISTRIBUIDORA LTDA', categoria: 'Frete e importação', cidade: 'ITAJAI' },
    });
  });
});

const jaLancado: OpcaoDeVinculo = {
  tipo: 'existing_payment', id: 'pg84', rotulo: 'Pagamento já lançado: Sinal — ORÇ-00084', valor: 591.41,
  confianca: 60, nivel: 'weak', motivos: ['Valor exato'], diferenca: 0, lancamentoId: 'r84', lado: 'receivable',
  ordemDeServicoId: 'os84', clienteId: 'c', clienteNome: 'ROBSON', converteOrcamento: false, jaLancado: true,
};
const vinculo: VinculoSugerido = { principal: jaLancado, alternativas: [] };

describe('VinculoDaLinha', () => {
  it('pede a escolha quando pode já estar lançado, e registra "casar"', async () => {
    const onEscolher = vi.fn();
    const user = userEvent.setup();
    renderizar(<VinculoDaLinha vinculo={vinculo} escolha={undefined} onEscolher={onEscolher} ocupado={false} />);
    expect(screen.getByText('Pode já estar lançado')).toBeInTheDocument();
    expect(screen.getByText(/escolha antes de aprovar/)).toBeInTheDocument();
    await user.click(screen.getByRole('radio', { name: /Casar com Sinal — ORÇ-00084/ }));
    expect(onEscolher).toHaveBeenCalledWith({ id: 'pg84' });
  });

  it('"lançar como receita nova" também é uma escolha — e tira o aviso', () => {
    renderizar(<VinculoDaLinha vinculo={vinculo} escolha="nenhum" onEscolher={() => {}} ocupado={false} />);
    expect(screen.queryByText(/escolha antes de aprovar/)).not.toBeInTheDocument();
    expect(screen.getByRole('radio', { name: /lançar como receita nova/ })).toBeChecked();
  });
});
