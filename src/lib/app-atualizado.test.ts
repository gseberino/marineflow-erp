// A falha de "o sistema foi publicado com a aba aberta" tem um texto por navegador.
//
// Errar a detecção estraga dos dois lados: deixar passar devolve ao dono a mensagem
// técnica que ele recebeu em 24/09 ("Failed to fetch dynamically imported module"), e
// pegar demais manda recarregar a página por causa de um erro de rede comum, jogando
// fora o que ele estava preenchendo.
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ehChunkQueSumiu, avisarSeForAppAtualizado, esqueceQueAvisou } from './app-atualizado';

vi.mock('sonner', () => ({ toast: { warning: vi.fn() } }));
import { toast } from 'sonner';

describe('reconhece o arquivo que sumiu no deploy', () => {
  it('Chrome/Edge', () => {
    expect(ehChunkQueSumiu(new TypeError(
      'Failed to fetch dynamically imported module: https://marineflow-erp.vercel.app/assets/html2pdf-BiCI6F9Z.js',
    ))).toBe(true);
  });

  it('Firefox', () => {
    expect(ehChunkQueSumiu(new TypeError('error loading dynamically imported module'))).toBe(true);
  });

  it('Safari', () => {
    expect(ehChunkQueSumiu(new TypeError('Importing a module script failed.'))).toBe(true);
  });

  it('quando a hospedagem devolve o index.html no lugar do arquivo', () => {
    expect(ehChunkQueSumiu(new TypeError(
      "Failed to load module script: Expected a JavaScript module script but the server responded with a MIME type of \"text/html\". Strict MIME type checking is enforced for module scripts per HTML spec.",
    ))).toBe(true);
  });

  it('folha de estilo do chunk (Vite)', () => {
    expect(ehChunkQueSumiu(new Error('Unable to preload CSS for /assets/index-abc.css'))).toBe(true);
  });

  it('erro marcado pelo nome, sem mensagem reconhecível', () => {
    const e = new Error('loading chunk 42 failed');
    e.name = 'ChunkLoadError';
    expect(ehChunkQueSumiu(e)).toBe(true);
  });

  it('texto solto também vale — nem todo motivo de rejeição é um Error', () => {
    expect(ehChunkQueSumiu('Failed to fetch dynamically imported module')).toBe(true);
  });

  it('maiúsculas e minúsculas não mudam nada', () => {
    expect(ehChunkQueSumiu(new Error('FAILED TO FETCH DYNAMICALLY IMPORTED MODULE'))).toBe(true);
  });
});

describe('não confunde com erro comum', () => {
  it.each([
    ['falha de rede da API', new TypeError('Failed to fetch')],
    ['erro de banco', new Error('duplicate key value violates unique constraint')],
    ['erro do próprio código', new TypeError("Cannot read properties of undefined (reading 'map')")],
    ['permissão', new Error('new row violates row-level security policy')],
    ['nada', null],
    ['indefinido', undefined],
    ['objeto sem mensagem', {}],
  ])('%s', (_caso, erro) => {
    expect(ehChunkQueSumiu(erro)).toBe(false);
  });

  // "Failed to fetch" sozinho é a API fora do ar — o caso mais comum de todos, e o que
  // mais estragaria se virasse "recarregue a página".
  it('a API fora do ar não vira pedido de recarregar', () => {
    esqueceQueAvisou();
    expect(avisarSeForAppAtualizado(new TypeError('Failed to fetch'))).toBe(false);
    expect(toast.warning).not.toHaveBeenCalled();
  });
});

describe('o aviso', () => {
  beforeEach(() => {
    esqueceQueAvisou();
    vi.mocked(toast.warning).mockClear();
  });
  afterEach(() => esqueceQueAvisou());

  it('aparece uma vez e oferece recarregar', () => {
    const erro = new TypeError('Failed to fetch dynamically imported module: /assets/x.js');
    expect(avisarSeForAppAtualizado(erro)).toBe(true);
    expect(toast.warning).toHaveBeenCalledTimes(1);
    const [titulo, opcoes] = vi.mocked(toast.warning).mock.calls[0] as [string, any];
    expect(titulo).toContain('atualizado');
    expect(opcoes.action.label).toBe('Recarregar');
    // Some só quando o usuário decidir: um aviso de 4 segundos passa despercebido
    // justamente em quem estava lendo outra coisa na tela.
    expect(opcoes.duration).toBe(Infinity);
  });

  // O mesmo deploy derruba o clique seguinte, e o seguinte. Três avisos empilhados
  // dizem a mesma coisa três vezes.
  it('não repete no segundo erro igual', () => {
    const erro = new TypeError('Failed to fetch dynamically imported module: /assets/x.js');
    avisarSeForAppAtualizado(erro);
    avisarSeForAppAtualizado(erro);
    avisarSeForAppAtualizado(new TypeError('error loading dynamically imported module'));
    expect(toast.warning).toHaveBeenCalledTimes(1);
  });
});
