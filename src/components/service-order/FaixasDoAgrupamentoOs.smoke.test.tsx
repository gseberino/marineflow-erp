// Faixas do agrupamento de OS (28/10/2026): render de verdade (tsc/build não pegam TDZ) e os textos que
// dizem ao dono para onde a OS foi, o que a agrupada reúne e onde ficaram as assinaturas.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { FaixaOsAgrupadaEm, FaixaOsQueReune } from './FaixasDoAgrupamentoOs';

const comRota = (ui: React.ReactNode) => render(<MemoryRouter>{ui}</MemoryRouter>);

describe('FaixaOsAgrupadaEm', () => {
  it('diz para onde foi, que o dinheiro está lá, e leva até ela', () => {
    comRota(<FaixaOsAgrupadaEm agrupadoId="nova-1" agrupadoNumero="OS-00140" desagrupavel />);
    expect(screen.getByText('Esta OS foi agrupada em OS-00140.')).toBeInTheDocument();
    expect(screen.getByText(/Sinais, contas a receber, tarefas e compras desta OS estão na OS-00140\. Para mexer nesta, desagrupe a OS-00140\./)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Abrir OS-00140' })).toHaveAttribute('href', '/v2/service-orders/nova-1');
  });

  it('agrupada que já começou: fica só como histórico', () => {
    comRota(<FaixaOsAgrupadaEm agrupadoId="nova-1" agrupadoNumero="OS-00140" desagrupavel={false} />);
    expect(screen.getByText(/A OS-00140 já começou a ser executada .* não dá mais para desagrupar/)).toBeInTheDocument();
  });

  it('com a frase do banco: mostra o motivo dele', () => {
    comRota(<FaixaOsAgrupadaEm agrupadoId="nova-1" agrupadoNumero="OS-00140" desagrupavel={false} motivo="OS-00140 ganhou conta a receber depois de agrupar. Cancele ou mova isso para uma das originais antes de desagrupar." />);
    expect(screen.getByText(/OS-00140 ganhou conta a receber depois de agrupar\. .* Enquanto não for desagrupada, esta fica só como histórico\./)).toBeInTheDocument();
    expect(screen.queryByText(/já começou a ser executada/)).not.toBeInTheDocument();
  });

  it('antes de a consulta chegar, não inventa número', () => {
    comRota(<FaixaOsAgrupadaEm agrupadoId="nova-1" agrupadoNumero={null} desagrupavel={null} />);
    expect(screen.getByText('Esta OS foi agrupada em outra OS.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Abrir a OS agrupada' })).toBeInTheDocument();
  });
});

describe('FaixaOsQueReune', () => {
  const ORIGENS = [
    { id: 'a', numero: 'OS-00032', assinada: false },
    { id: 'b', numero: 'OS-00033', assinada: true },
  ];

  it('diz o que reúne e onde ficou a assinatura; o Desagrupar chama a janela', async () => {
    const onDesagrupar = vi.fn();
    comRota(<FaixaOsQueReune origens={ORIGENS} podeDesagrupar cancelarPedeDesagrupar onDesagrupar={onDesagrupar} />);
    expect(screen.getByText('Esta OS reúne OS-00032, OS-00033.')).toBeInTheDocument();
    expect(screen.getByText(/A assinatura do cliente ficou na OS-00033, como histórico; esta OS nasceu sem assinatura\./)).toBeInTheDocument();
    expect(screen.getByText(/Para cancelá-la, desagrupe primeiro/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Desagrupar' }));
    expect(onDesagrupar).toHaveBeenCalledTimes(1);
  });

  it('sem cargo ou já começada: sem botão; sem assinatura: sem aviso', () => {
    comRota(
      <FaixaOsQueReune
        origens={[{ id: 'a', numero: 'OS-00100' }, { id: 'b', numero: 'OS-00128' }]}
        podeDesagrupar={false}
        cancelarPedeDesagrupar={false}
        onDesagrupar={() => {}}
      />,
    );
    expect(screen.queryByRole('button', { name: 'Desagrupar' })).not.toBeInTheDocument();
    expect(screen.queryByText(/assinatura/)).not.toBeInTheDocument();
    expect(screen.queryByText(/desagrupe primeiro/)).not.toBeInTheDocument();
  });

  it('o banco não deixa mais desagrupar: mostra a frase dele, sem botão e sem "desagrupe primeiro"', () => {
    comRota(
      <FaixaOsQueReune
        origens={[{ id: 'a', numero: 'OS-00100' }, { id: 'b', numero: 'OS-00128' }]}
        podeDesagrupar={false}
        cancelarPedeDesagrupar={false}
        motivoSemDesagrupar="OS-00131 já começou a ser executada (hora apontada): não dá mais para desagrupar. As originais ficam como histórico."
        onDesagrupar={() => {}}
      />,
    );
    expect(screen.getByText(/OS-00131 já começou a ser executada \(hora apontada\)/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Desagrupar' })).not.toBeInTheDocument();
    expect(screen.queryByText(/desagrupe primeiro/)).not.toBeInTheDocument();
  });

  it('várias assinadas: no plural', () => {
    comRota(
      <FaixaOsQueReune
        origens={[{ id: 'a', numero: 'OS-00032', assinada: true }, { id: 'b', numero: 'OS-00033', assinada: true }]}
        podeDesagrupar={false}
        cancelarPedeDesagrupar={false}
        onDesagrupar={() => {}}
      />,
    );
    expect(screen.getByText(/As assinaturas do cliente ficaram nas OS originais \(OS-00032, OS-00033\)/)).toBeInTheDocument();
  });
});
