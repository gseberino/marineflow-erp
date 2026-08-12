// [F-NFSE-03] Smoke de render da grade de verbos fiscais.
//
// O que se protege aqui não é layout. São duas coisas que, se quebrarem, quebram em silêncio:
//
//   1. A grade RENDERIZA. Build e typecheck não pegam erro de inicialização em tempo de
//      render (já aconteceu neste repo — TDZ em 24/07), e uma tela de Settings que explode
//      derruba a aba inteira.
//   2. Campo em branco vira NULL, não zero. Alíquota de ISS 0 é válida (MEI), então mandar
//      zero no lugar de "não definido" declararia isenção que ninguém pediu.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { VerbosFiscaisGrid } from './VerbosFiscaisGrid';

const { estado, salvarMock } = vi.hoisted(() => ({
  salvarMock: vi.fn(),
  estado: {
    verbos: [
      // Como as dez linhas nascem: existem e estão vazias.
      { verb_slug: 'instalacao', name: 'Instalação', servicos: 84,
        default_national_tax_code: null, default_service_code: null, default_cnae: null,
        default_iss_rate: null, default_iss_withheld: null, notes: null },
      { verb_slug: 'reparo', name: 'Reparo', servicos: 31,
        default_national_tax_code: '140101', default_service_code: null, default_cnae: '3313901',
        default_iss_rate: 5, default_iss_withheld: null, notes: 'confirmado pela contabilidade' },
    ] as any[],
  },
}));

vi.mock('@/hooks/use-service-fiscal', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-service-fiscal')>();
  return {
    ...real,
    useServiceFiscalVerbs: () => ({ data: estado.verbos, isLoading: false, error: null }),
    useUpdateServiceFiscalVerb: () => ({ mutate: salvarMock, isPending: false }),
  };
});

/** O placeholder aparece nas DUAS linhas; a que tem alíquota preenchida é a segunda. */
function campoIssDoReparo() {
  return screen.getAllByPlaceholderText('5')[1];
}

function renderGrade() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <VerbosFiscaisGrid />
    </QueryClientProvider>,
  );
}

describe('VerbosFiscaisGrid', () => {
  beforeEach(() => salvarMock.mockClear());

  it('renderiza sem explodir e mostra os verbos', () => {
    renderGrade();
    expect(screen.getByText('Instalação')).toBeInTheDocument();
    expect(screen.getByText('Reparo')).toBeInTheDocument();
  });

  it('mostra quantos serviços dependem de cada verbo', () => {
    renderGrade();
    // Mexer no verbo de 84 serviços não é o mesmo que mexer no que ninguém usa.
    expect(screen.getByText('84 serviços')).toBeInTheDocument();
    expect(screen.getByText('31 serviços')).toBeInTheDocument();
  });

  it('avisa quantos verbos ainda estão sem código', () => {
    renderGrade();
    expect(screen.getByText(/1 de 2 verbos ainda sem código/)).toBeInTheDocument();
  });

  it('o botão de salvar só acende quando a linha muda', async () => {
    const user = userEvent.setup();
    renderGrade();

    const botoes = screen.getAllByTitle(/Nada alterado|Salvar este verbo/);
    expect(botoes.every((b) => b.hasAttribute('disabled'))).toBe(true);

    await user.type(screen.getAllByPlaceholderText('140101')[0], '140601');
    expect(screen.getByTitle('Salvar este verbo')).toBeEnabled();
  });

  it('campo em branco salva como NULL — não como zero nem string vazia', async () => {
    const user = userEvent.setup();
    renderGrade();

    // Linha do "Reparo": limpa a alíquota que estava preenchida (5) e salva.
    const campoIss = campoIssDoReparo();
    await user.clear(campoIss);
    await user.click(screen.getByTitle('Salvar este verbo'));

    expect(salvarMock).toHaveBeenCalledTimes(1);
    const enviado = salvarMock.mock.calls[0][0];
    expect(enviado.verb_slug).toBe('reparo');
    expect(enviado.default_iss_rate).toBeNull();
    expect(enviado.default_iss_rate).not.toBe(0);
  });

  it('alíquota digitada com vírgula vira número', async () => {
    const user = userEvent.setup();
    renderGrade();

    const campoIss = campoIssDoReparo();
    await user.clear(campoIss);
    await user.type(campoIss, '3,5');
    await user.click(screen.getByTitle('Salvar este verbo'));

    expect(salvarMock.mock.calls[0][0].default_iss_rate).toBe(3.5);
  });
});
