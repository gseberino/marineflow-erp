// Via v2, F2: o cartão da sugestão do assistente na linha do serviço (canal A). Só o aprovado vai ao papel.
import { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { LineViaTecnico, type SugestaoNaLinha } from './line-via-tecnico';
import type { SugestaoDeInstrucao } from '@/lib/instrucoes-sugeridas';

vi.mock('@/hooks/use-payees', () => ({ usePayees: () => ({ data: [] }) }));

const sugestao: SugestaoDeInstrucao = {
  id: 's1', linha_id: 'l1', numero: 3, nome: 'Instalação da antena de TV',
  texto: 'Fixação do suporte da antena, ligação do cabo coaxial e teste de imagem.',
  origem: 'ia', fonte_rotulo: null, criado_em: '2026-11-20T12:00:00Z',
};

function Cartao(props: Partial<SugestaoNaLinha> & { onAprovar?: (t: string) => void; onDescartar?: () => void; inicial?: SugestaoDeInstrucao }) {
  const s = props.inicial ?? sugestao;
  const [texto, setTexto] = useState(s.texto);
  return (
    <LineViaTecnico
      line={{ id: 'l1', technician_instructions: null }}
      orderId="os1"
      sugestao={{
        sugestao: s, texto, onEditar: setTexto,
        onAprovar: props.onAprovar ?? (() => {}), onDescartar: props.onDescartar ?? (() => {}),
      }}
    />
  );
}

function renderizar(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

describe('LineViaTecnico — cartão da sugestão do assistente', () => {
  it('mostra o rótulo acima ("sugestão do assistente", nunca "rascunho") e o texto sugerido, no lugar do campo', () => {
    renderizar(<Cartao />);
    expect(screen.getByText(/sugestão do assistente/)).toBeTruthy();
    expect(screen.getByText(/sai no papel depois de aprovada/)).toBeTruthy();
    expect((screen.getByRole('textbox') as HTMLTextAreaElement).value).toBe(sugestao.texto);
    expect(screen.queryByLabelText('Instrução ao técnico para este serviço')).toBeNull();
    expect(screen.queryByText(/rascunho/i)).toBeNull();
  });

  it('Aprovar manda o texto sugerido; editar troca o botão para "Aprovar com a correção" e manda o editado (uma linha só)', () => {
    const onAprovar = vi.fn();
    renderizar(<Cartao onAprovar={onAprovar} />);
    fireEvent.click(screen.getByRole('button', { name: 'Aprovar' }));
    expect(onAprovar).toHaveBeenLastCalledWith(sugestao.texto);

    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'Fixação da antena,\nligação do cabo e teste de imagem.' } });
    const botao = screen.getByRole('button', { name: 'Aprovar com a correção' });
    fireEvent.click(botao);
    expect(onAprovar).toHaveBeenLastCalledWith('Fixação da antena, ligação do cabo e teste de imagem.');
  });

  it('texto com R$ ou curto demais: avisa e não deixa aprovar', () => {
    renderizar(<Cartao />);
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'Troca e cobrança de R$ 50,00.' } });
    expect(screen.getByText(/Sem valor em R\$/)).toBeTruthy();
    expect((screen.getByRole('button', { name: 'Aprovar com a correção' }) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'Testar.' } });
    expect(screen.getByText(/pelo menos 10 letras/)).toBeTruthy();
  });

  it('reuso: mostra de onde veio', () => {
    renderizar(<Cartao inicial={{ ...sugestao, origem: 'reuso', fonte_rotulo: 'igual à do ORÇ-00131 · serviço 4' }} />);
    expect(screen.getByText('Igual à do ORÇ-00131 · serviço 4')).toBeTruthy();
  });

  it('sem sugestão: o campo de sempre, agora com rótulo acima', () => {
    renderizar(<LineViaTecnico line={{ id: 'l1', technician_instructions: 'Texto do dono.' }} orderId="os1" />);
    expect(screen.getByText('Instrução ao técnico (opcional)')).toBeTruthy();
    expect((screen.getByLabelText('Instrução ao técnico para este serviço') as HTMLInputElement).value).toBe('Texto do dono.');
  });
});
