// Favorecidos (07/10/2026): desativar pela lista apagava o CPF/CNPJ e não pausava as regras dele.
//
// O botão Desativar/Reativar mandava só { id, active } para useSalvarPayee, que transformava o
// `document` ausente em null — o favorecido desativado perdia o documento. E a regra do dono
// ("Desativar cadastro: pausar as regras dele") só valia pelo assistente: pela tela, o próximo Pix
// continuava entrando classificado no desativado.
import { describe, it, expect, vi, beforeEach } from 'vitest';

type Resposta = { data: unknown; error: { message: string } | null };

const banco = vi.hoisted(() => ({
  respostas: {} as Record<string, Resposta | Resposta[]>,
  chamadas: [] as Array<{ alvo: string; op: string; valores?: unknown; filtros: unknown[][] }>,
}));

function responder(chave: string): Resposta {
  const r = banco.respostas[chave];
  if (Array.isArray(r)) return r.length > 1 ? r.shift()! : r[0];
  return r ?? { data: null, error: null };
}

vi.mock('@/integrations/supabase/client', () => {
  const consulta = (tabela: string) => {
    const registro = { alvo: tabela, op: 'select', valores: undefined as unknown, filtros: [] as unknown[][] };
    // deno-lint-ignore no-explicit-any
    const q: any = {};
    for (const m of ['select', 'eq', 'in', 'limit', 'order']) {
      q[m] = (...a: unknown[]) => { registro.filtros.push([m, ...a]); return q; };
    }
    q.update = (v: unknown) => { registro.op = 'update'; registro.valores = v; return q; };
    q.insert = (v: unknown) => { registro.op = 'insert'; registro.valores = v; return q; };
    q.single = () => q;
    // deno-lint-ignore no-explicit-any
    q.then = (ok: any, erro: any) => {
      banco.chamadas.push(registro);
      return Promise.resolve(responder(`${tabela}.${registro.op}`)).then(ok, erro);
    };
    return q;
  };
  return { supabase: { from: (t: string) => consulta(t) } };
});

import { camposDoFavorecido, mudarAtivoDoFavorecido } from './use-payees';
// O mesmo módulo que o assistente usa (favorecidos.ts reexporta daqui).
import { tirarPausa } from '../../supabase/functions/_shared/banking/pausa-do-favorecido';

const ok = (data: unknown): Resposta => ({ data, error: null });
const gravacoes = (tabela: string) => banco.chamadas.filter((c) => c.alvo === tabela && c.op === 'update');

const ELIANE = { id: 'fav1', name: 'Eliane Souza', document: '12345678901' };
const REGRAS = [
  { id: 'r-doc', match_type: 'document', match_value: '123.456.789-01', set_category: 'Pró-labore', status: 'active', note: null },
  { id: 'r-nome', match_type: 'counterparty', match_value: 'PIX ELIANE SOUZA', set_category: 'Pró-labore', status: 'proposed', note: 'do dono' },
  { id: 'r-outra', match_type: 'document', match_value: '99999999999', set_category: 'Aluguel', status: 'active', note: null },
];

beforeEach(() => {
  banco.respostas = {};
  banco.chamadas = [];
});

describe('camposDoFavorecido', () => {
  it('desativar manda só o ativo: o documento não vira null', () => {
    expect(camposDoFavorecido({ id: 'fav1', active: false })).toEqual({ active: false });
  });

  it('documento enviado vai só com dígitos; vazio vira null', () => {
    expect(camposDoFavorecido({ name: 'X', document: '123.456.789-01' })).toEqual({ name: 'X', document: '12345678901' });
    expect(camposDoFavorecido({ id: 'a', document: '' })).toEqual({ document: null });
  });
});

describe('mudarAtivoDoFavorecido', () => {
  it('desativar: só o ativo vai para o cadastro e pausa as regras que apontam (documento e nome completo)', async () => {
    banco.respostas['finance_rules.select'] = ok(REGRAS);
    const r = await mudarAtivoDoFavorecido(ELIANE, false);
    expect(r).toEqual({ regras: 2, aviso: null });
    expect(gravacoes('payees')[0].valores).toEqual({ active: false });
    const leitura = banco.chamadas.find((c) => c.alvo === 'finance_rules' && c.op === 'select')!;
    expect(leitura.filtros).toContainEqual(['in', 'status', ['active', 'proposed']]);
    const regras = gravacoes('finance_rules');
    expect(regras.map((g) => g.filtros.find((f) => f[0] === 'eq')![2])).toEqual(['r-doc', 'r-nome']);
    expect(regras[0].valores).toMatchObject({ status: 'paused' });
    expect((regras[1].valores as { note: string }).note).toContain('fav:fav1]');
    // A marca é a do assistente: o tirarPausa dele devolve a situação de antes.
    expect(tirarPausa((regras[1].valores as { note: string }).note, 'fav1')).toEqual({ status: 'proposed', note: 'do dono' });
  });

  it('reativar: devolve só as pausadas por esta desativação, na situação de antes', async () => {
    banco.respostas['finance_rules.select'] = ok([
      { id: 'r1', match_type: 'document', match_value: '12345678901', set_category: null, status: 'paused',
        note: 'x [pausada ao desativar o favorecido Eliane Souza em 07/10/2026 · era proposed · fav:fav1]' },
      { id: 'r2', match_type: 'document', match_value: '12345678901', set_category: null, status: 'paused', note: 'pausada à mão' },
    ]);
    const r = await mudarAtivoDoFavorecido(ELIANE, true);
    expect(r.regras).toBe(1);
    expect(gravacoes('payees')[0].valores).toEqual({ active: true });
    expect(gravacoes('finance_rules')).toHaveLength(1);
    expect(gravacoes('finance_rules')[0].valores).toEqual({ status: 'proposed', note: 'x' });
  });

  it('leitura das regras que falha não mexe em nada', async () => {
    banco.respostas['finance_rules.select'] = { data: null, error: { message: 'boom' } };
    await expect(mudarAtivoDoFavorecido(ELIANE, false)).rejects.toThrow('Não consegui ler as regras do extrato (boom). Nada mudou.');
    expect(gravacoes('payees')).toEqual([]);
  });

  it('regra que não grava vira aviso, sem desfazer o resto', async () => {
    banco.respostas['finance_rules.select'] = ok(REGRAS);
    banco.respostas['finance_rules.update'] = [{ data: null, error: { message: 'negado' } }, ok(null)];
    const r = await mudarAtivoDoFavorecido(ELIANE, false);
    expect(r.regras).toBe(1);
    expect(r.aviso).toContain('negado');
  });
});
