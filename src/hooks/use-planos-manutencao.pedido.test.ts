// O pedido da tela Revisões ao assistente ("Pedir lembrete agora"): até 22/10/2026 dizia sempre "da
// embarcação …" — e as telas já mandavam o nome com o tipo, saindo "da embarcação Motorhome Iveco
// Daily". Com o tipo, a unidade vai pelo tipo; sem ele, só o nome.
import { describe, it, expect, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));

import { pedidoDoLembrete } from './use-planos-manutencao';

const base = { planId: 'p1', plano: 'Revisão das baterias', cliente: 'Rodrigo', vesselId: 'v1' };

describe('pedidoDoLembrete', () => {
  it('com o tipo: "do motorhome Iveco Daily", "da lancha Mar Azul" (o nome com o tipo na frente não repete)', () => {
    expect(pedidoDoLembrete({ ...base, embarcacao: 'Iveco Daily', tipo: 'Motorhome' }))
      .toContain('("Revisão das baterias" do motorhome Iveco Daily, cliente Rodrigo)');
    expect(pedidoDoLembrete({ ...base, embarcacao: 'Motorhome Iveco Daily', tipo: 'Motorhome' }))
      .toContain('("Revisão das baterias" do motorhome Iveco Daily, cliente Rodrigo)');
    expect(pedidoDoLembrete({ ...base, embarcacao: 'Mar Azul', tipo: 'Lancha', cliente: null }))
      .toContain('("Revisão das baterias" da lancha Mar Azul)');
  });

  it('sem o tipo: só o nome, nunca "da embarcação" chutado', () => {
    const t = pedidoDoLembrete({ ...base, embarcacao: 'Motorhome Iveco Daily' });
    expect(t).toContain('("Revisão das baterias" — Motorhome Iveco Daily, cliente Rodrigo)');
    expect(t).not.toContain('da embarcação');
  });

  it('o resto do pedido não muda: a tool, o plan_id e o "sem minha confirmação"', () => {
    const t = pedidoDoLembrete({ ...base, embarcacao: 'Mar Azul', tipo: 'Lancha' });
    expect(t).toMatch(/^Pedido da tela Revisões: prepare AGORA o lembrete de revisão do plano p1 /);
    expect(t).toContain('Use send_maintenance_reminder_now com plan_id p1. Não envie nada sem a minha confirmação.');
  });
});
