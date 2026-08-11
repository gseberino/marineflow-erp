// Cobertura da exportação de CSV — módulo sem teste até agora.
//
// Todo "Exportar" de cadastro passa por aqui: produtos, serviços, clientes, embarcações,
// marinas e fornecedores. O arquivo gerado sai da empresa — vai para o contador, para uma
// planilha de conferência, às vezes para outro sistema. Estrutura errada aqui não dá erro em
// tela: dá coluna deslocada na planilha de outra pessoa.
//
// Três defeitos apareceram e estão registrados como NOVO-013 — documentados aqui pelo que
// fazem hoje, com o ID no nome do caso.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { exportToCSV, PRODUCTS_COLUMNS, CLIENTS_COLUMNS, VESSELS_COLUMNS } from './export-utils';

const { baixados } = vi.hoisted(() => ({ baixados: [] as Array<{ csv: string; filename: string }> }));

vi.mock('./download', () => ({
  downloadCSV: (csv: string, filename: string) => { baixados.push({ csv, filename }); },
}));

beforeEach(() => { baixados.length = 0; });

/** Última exportação, já sem o BOM, quebrada em linhas. */
function linhas(): string[] {
  const { csv } = baixados[baixados.length - 1];
  return csv.replace(/^﻿/, '').split('\n');
}

const COLUNAS = [
  { header: 'Nome', key: 'name' },
  { header: 'Obs', key: 'notes' },
];

describe('exportToCSV — estrutura do arquivo', () => {
  it('começa com BOM — sem ele o Excel abre acentuação quebrada', () => {
    exportToCSV([{ name: 'Cabo', notes: 'ok' }], 'x.csv', COLUNAS);
    expect(baixados[0].csv.startsWith('﻿')).toBe(true);
  });

  it('usa ponto e vírgula, que é o que o Excel pt-BR espera', () => {
    exportToCSV([{ name: 'Cabo', notes: 'flexível' }], 'x.csv', COLUNAS);
    expect(linhas()[0]).toBe('Nome;Obs');
    expect(linhas()[1]).toBe('Cabo;flexível');
  });

  it('passa o nome do arquivo adiante', () => {
    exportToCSV([], 'produtos-2026-08.csv', COLUNAS);
    expect(baixados[0].filename).toBe('produtos-2026-08.csv');
  });

  it('lista vazia gera só o cabeçalho, não um arquivo vazio', () => {
    exportToCSV([], 'x.csv', COLUNAS);
    expect(linhas()).toEqual(['Nome;Obs']);
  });

  it('valor nulo ou ausente vira campo vazio, não "null"', () => {
    exportToCSV([{ name: null, notes: undefined }], 'x.csv', COLUNAS);
    expect(linhas()[1]).toBe(';');
  });

  it('valor com ponto e vírgula é envolvido em aspas — senão vira duas colunas', () => {
    exportToCSV([{ name: 'Cabo 6mm; azul', notes: 'ok' }], 'x.csv', COLUNAS);
    expect(linhas()[1]).toBe('"Cabo 6mm; azul";ok');
  });

  it('valor com quebra de linha é envolvido em aspas — senão vira duas linhas', () => {
    exportToCSV([{ name: 'Cabo', notes: 'linha 1\nlinha 2' }], 'x.csv', COLUNAS);
    const csv = baixados[0].csv.replace(/^﻿/, '');
    expect(csv).toContain('"linha 1\nlinha 2"');
  });

  it('aplica o transform da coluna', () => {
    exportToCSV(
      [{ active: true }, { active: false }],
      'x.csv',
      [{ header: 'Situação', key: 'active', transform: v => (v ? 'Ativo' : 'Inativo') }],
    );
    expect(linhas().slice(1)).toEqual(['Ativo', 'Inativo']);
  });

  it('exporta uma linha por registro, na ordem recebida', () => {
    exportToCSV([{ name: 'A' }, { name: 'B' }, { name: 'C' }], 'x.csv', [{ header: 'Nome', key: 'name' }]);
    expect(linhas().slice(1)).toEqual(['A', 'B', 'C']);
  });
});

describe('catálogos de colunas', () => {
  it('produtos e clientes traduzem "ativo" para texto', () => {
    const colAtivo = PRODUCTS_COLUMNS.find(c => c.key === 'active')!;
    expect(colAtivo.transform!(true)).toBe('Ativo');
    expect(colAtivo.transform!(false)).toBe('Inativo');
    const colTipo = CLIENTS_COLUMNS.find(c => c.key === 'type')!;
    expect(colTipo.transform!('company')).toBe('PJ');
    expect(colTipo.transform!('individual')).toBe('PF');
  });

  it('nenhum catálogo tem cabeçalho repetido', () => {
    for (const [nome, cols] of [['produtos', PRODUCTS_COLUMNS], ['clientes', CLIENTS_COLUMNS]] as const) {
      const headers = cols.map(c => c.header);
      expect(new Set(headers).size, `${nome} tem cabeçalho repetido`).toBe(headers.length);
    }
  });

  // ⚠️ NOVO-013(a) — a coluna "Marina" do export de embarcações lê a chave `name`, que é o
  // nome da EMBARCAÇÃO. A planilha sai com o nome do barco repetido na coluna da marina.
  it('[NOVO-013] no export de embarcações, "Marina" repete o nome da embarcação', () => {
    const marina = VESSELS_COLUMNS.find(c => c.header === 'Marina')!;
    const nome = VESSELS_COLUMNS.find(c => c.header === 'Nome')!;
    expect(marina.key).toBe(nome.key); // as duas leem `name` — é o defeito

    exportToCSV([{ name: 'Lancha Azul' }], 'x.csv', VESSELS_COLUMNS);
    const celulas = linhas()[1].split(';');
    const iNome = VESSELS_COLUMNS.findIndex(c => c.header === 'Nome');
    const iMarina = VESSELS_COLUMNS.findIndex(c => c.header === 'Marina');
    expect(celulas[iMarina]).toBe(celulas[iNome]);
    expect(celulas[iMarina]).toBe('Lancha Azul'); // deveria ser o nome da marina
  });
});

describe('[NOVO-013] escapes que faltam', () => {
  it('aspas sem outro separador saem duplicadas e sem envelope', () => {
    // O código escapa `"` para `""` mas só envolve o campo quando há `;` ou quebra de linha.
    // Resultado: `cabo "flex"` chega ao Excel como `cabo ""flex""`.
    exportToCSV([{ name: 'cabo "flex" 6mm', notes: 'ok' }], 'x.csv', COLUNAS);
    expect(linhas()[1]).toBe('cabo ""flex"" 6mm;ok');
  });

  it('valor começando com = sai como fórmula para o Excel', () => {
    // Injeção de fórmula em CSV: um campo de texto do cadastro que comece com = + - @ é
    // executado ao abrir a planilha. O conteúdo vem do usuário e sai da empresa.
    exportToCSV([{ name: '=1+1', notes: '@SUM(A1:A9)' }], 'x.csv', COLUNAS);
    expect(linhas()[1]).toBe('=1+1;@SUM(A1:A9)');
  });
});
