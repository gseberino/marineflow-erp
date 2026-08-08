import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { downloadBlob, downloadText, downloadCSV, withBom } from './download';

/**
 * O download tinha um bug em seis lugares do sistema:
 *
 *     link.click();
 *     URL.revokeObjectURL(url);   // ← na linha seguinte
 *
 * No Chrome costuma passar; no Firefox e no Safari o URL morre antes de o
 * arquivo começar a baixar e o download falha SEM ERRO. Estes testes travam as
 * três coisas que impedem isso: o link entra no documento, o clique acontece
 * com ele lá dentro, e a revogação só vem muito depois.
 */
describe('entrega de arquivo ao usuário', () => {
  let criados: string[];
  let revogados: string[];

  beforeEach(() => {
    vi.useFakeTimers();
    criados = [];
    revogados = [];
    let n = 0;
    (URL as any).createObjectURL = vi.fn(() => {
      const u = `blob:teste/${++n}`;
      criados.push(u);
      return u;
    });
    (URL as any).revokeObjectURL = vi.fn((u: string) => revogados.push(u));
  });

  afterEach(() => vi.useRealTimers());

  it('o link está NO documento na hora do clique', () => {
    let estavaNoDom = false;
    const original = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function (this: HTMLAnchorElement) {
      estavaNoDom = document.body.contains(this);
    };
    try {
      downloadBlob(new Blob(['x']), 'a.txt');
    } finally {
      HTMLAnchorElement.prototype.click = original;
    }
    // Link solto na memória não dispara download em todos os navegadores.
    expect(estavaNoDom).toBe(true);
  });

  it('não deixa o link no documento depois', () => {
    downloadBlob(new Blob(['x']), 'a.txt');
    expect(document.querySelectorAll('a[download]')).toHaveLength(0);
  });

  it('NÃO revoga o URL junto com o clique', () => {
    downloadBlob(new Blob(['x']), 'a.txt');
    // A regressão exata: revogar aqui mata o download no Firefox e no Safari.
    expect(revogados).toEqual([]);
  });

  it('revoga só bem depois, para não vazar memória', () => {
    downloadBlob(new Blob(['x']), 'a.txt');
    vi.advanceTimersByTime(59_000);
    expect(revogados).toEqual([]);
    vi.advanceTimersByTime(2_000);
    expect(revogados).toEqual(criados);
  });

  it('usa o nome de arquivo pedido', () => {
    let nome = '';
    const original = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function (this: HTMLAnchorElement) {
      nome = this.download;
    };
    try {
      downloadText('oi', 'conversa.txt');
    } finally {
      HTMLAnchorElement.prototype.click = original;
    }
    expect(nome).toBe('conversa.txt');
  });

  it('CSV também passa pelo caminho único de download', () => {
    downloadCSV('Serviço;Instalação', 'relatorio.csv');
    expect(criados).toHaveLength(1);
    expect(revogados).toEqual([]);
  });
});

describe('BOM do CSV', () => {
  // Sem o BOM, o Excel brasileiro assume a codificação da máquina e
  // "Instalação" chega como "InstalaÃ§Ã£o" na tela do contador.
  it('põe o BOM quando falta', () => {
    expect(withBom('Serviço')).toBe('﻿Serviço');
  });

  // Vários chamadores já concatenavam o BOM; dois deles deixariam lixo na
  // frente da primeira coluna.
  it('não duplica quando já tem', () => {
    expect(withBom('﻿Serviço')).toBe('﻿Serviço');
    expect(withBom('﻿Serviço').match(/﻿/g)).toHaveLength(1);
  });

  it('aguenta texto vazio', () => {
    expect(withBom('')).toBe('﻿');
  });
});
