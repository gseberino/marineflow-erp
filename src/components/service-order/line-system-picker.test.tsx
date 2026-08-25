// O bug que este teste existe para impedir de voltar:
//
// Os dois Select usavam `defaultValue` e gravavam no `onValueChange`. O campo já
// vem PREENCHIDO com o palpite da regra, e `onValueChange` não dispara quando se
// escolhe o valor que já estava lá — então ACEITAR a sugestão era um clique que
// não gravava nada, e a linha continuava pendente sem a tela dizer por quê.
//
// O dono relatou exatamente assim: "mesmo selecionando a categoria e o tipo de
// serviço, não existe nenhum botão de confirmar esses dados e salvá-los, e o
// serviço continua aguardando confirmação".
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { LineSystemPicker } from './line-system-picker';
import type { LineMissingSystem } from '@/hooks/use-service-systems';

const gravou: Array<{ lineId: string; system?: string | null; verb?: string | null }> = [];

// Referências ESTÁVEIS: objeto novo a cada chamada põe os useEffect em laço.
vi.mock('@/hooks/use-service-systems', async (orig) => {
  const real = await orig<any>();
  const sistemas = {
    data: [
      { slug: 'eletrico_dc', name: 'Elétrico DC', short_name: 'DC', is_physical: true, sort: 1, active: true },
      { slug: 'gas', name: 'Gás', short_name: 'Gás', is_physical: true, sort: 2, active: true },
    ],
  };
  const verbos = {
    data: [
      { slug: 'instalacao', name: 'Instalação', intervem_no_sistema: true, sort: 1, active: true },
      { slug: 'reparo', name: 'Reparo', intervem_no_sistema: true, sort: 2, active: true },
    ],
  };
  const mut = {
    isPending: false,
    mutate: (args: any, opts?: any) => { gravou.push(args); opts?.onSuccess?.(); },
  };
  return {
    ...real,
    useServiceSystems: () => sistemas,
    useServiceVerbs: () => verbos,
    useSetLineClassification: () => mut,
  };
});

const linhaComPalpite: LineMissingSystem = {
  line_id: 'linha-1',
  service_name: 'Instalação da fonte 120A',
  service_verb: null,
  sistema_sugerido: 'eletrico_dc',
  verbo_sugerido: 'instalacao',
  origem_sistema: 'linha',
  origem_verbo: 'linha',
};

describe('LineSystemPicker', () => {
  beforeEach(() => { gravou.length = 0; });

  // ESTE é o teste do bug. Sem tocar em nenhum Select — só confirmando o que a
  // regra sugeriu — a classificação precisa ser gravada.
  it('confirmar a sugestão SEM mexer nos campos grava os dois eixos', () => {
    render(<LineSystemPicker linha={linhaComPalpite} />);

    fireEvent.click(screen.getByRole('button', { name: /Confirmar/i }));

    expect(gravou).toHaveLength(1);
    expect(gravou[0]).toEqual({
      lineId: 'linha-1',
      system: 'eletrico_dc',
      verb: 'instalacao',
    });
  });

  // Sem palpite não há o que confirmar, e o botão precisa DIZER o que falta —
  // botão morto sem motivo visível é a mesma frustração de antes.
  it('sem palpite, o botão fica travado e a tela diz o que falta', () => {
    render(
      <LineSystemPicker
        linha={{ ...linhaComPalpite, sistema_sugerido: null, verbo_sugerido: null, origem_sistema: null, origem_verbo: null }}
      />,
    );

    const botao = screen.getByRole('button', { name: /Confirmar/i }) as HTMLButtonElement;
    expect(botao.disabled).toBe(true);
    expect(screen.getByText(/Escolha a categoria e o tipo de serviço/i)).toBeTruthy();
    expect(gravou).toHaveLength(0);
  });

  // Linha que já tem verbo (do catálogo) não mostra o seletor de tipo, e o
  // Confirmar não pode mandar `verb` — sobrescreveria com undefined.
  it('linha que já tem tipo de serviço grava só a categoria', () => {
    render(<LineSystemPicker linha={{ ...linhaComPalpite, service_verb: 'diagnostico' }} />);

    fireEvent.click(screen.getByRole('button', { name: /Confirmar/i }));

    expect(gravou).toHaveLength(1);
    expect(gravou[0]).toEqual({ lineId: 'linha-1', system: 'eletrico_dc' });
    expect('verb' in gravou[0]).toBe(false);
  });

  // A confiança do palpite muda o texto: fraco pede atenção antes de confirmar.
  it('avisa quando o palpite veio do contexto da OS, não da linha', () => {
    render(<LineSystemPicker linha={{ ...linhaComPalpite, origem_sistema: 'os' }} />);
    expect(screen.getByText(/Palpite fraco/i)).toBeTruthy();
  });
});
