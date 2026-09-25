// Quem é e o que paga — a prova e a escolha na linha do Extrato (Fase 2).
//
// O que se fixa: a prova do reconhecimento aparece escrita; "Cadastrar" abre o cadastro já
// preenchido e manda o documento; e a linha que pode já estar lançada NÃO se aprova no
// escuro — o caso dos três sinais de orçamento que viravam receita em dobro.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { EvidenciaDaLinha, VinculoDaLinha } from './ExtratoIdentificacao';
import type { VinculoSugerido, OpcaoDeVinculo } from '../../supabase/functions/_shared/banking/vinculo';

const { cadastrarMock, receita } = vi.hoisted(() => ({
  cadastrarMock: vi.fn(),
  receita: { dados: null as unknown },
}));

vi.mock('@/hooks/use-contraparte', () => ({
  useConsultaDeDocumento: () => ({ data: receita.dados ? { ok: true, tipo: 'cnpj', documento: '90136409000122', dados: receita.dados } : undefined, isLoading: false }),
  useCadastrarContraparte: () => ({ mutate: cadastrarMock, isPending: false }),
}));
vi.mock('@/hooks/use-financial-categories', () => ({
  useFinancialCategories: () => ({ data: [{ id: '1', name: 'Frete e importação' }, { id: '2', name: 'Outras despesas' }] }),
}));
vi.mock('@/hooks/use-finance-review', () => ({ useCriarCategoriaDespesa: () => ({ mutate: vi.fn(), isPending: false }) }));

function renderizar(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><I18nProvider>{ui}</I18nProvider></QueryClientProvider>);
}

beforeEach(() => { cadastrarMock.mockReset(); receita.dados = null; });

describe('EvidenciaDaLinha', () => {
  it('diz quem é e por qual prova', () => {
    renderizar(<EvidenciaDaLinha ehReceita categoria="Serviços prestados" ocupado={false} evidencia={{
      cliente: { id: 'c', nome: 'Acrisio Cançado Lopes', por: 'historico', detalhe: 'Este CNPJ já pagou 1× em nome de Acrisio' },
    }} />);
    expect(screen.getByText('Acrisio Cançado Lopes')).toBeInTheDocument();
    expect(screen.getByText(/por lançamentos anteriores/)).toBeInTheDocument();
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
