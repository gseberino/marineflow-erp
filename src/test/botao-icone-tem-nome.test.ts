// Botão só de ícone precisa de nome acessível.
//
// POR QUE ISTO É UMA VARREDURA e não um teste de componente: o defeito não mora numa tela,
// mora no hábito. Um `<Button size="icon">` com `title="Excluir"` parece resolvido — mas
// `title` só aparece no hover do MOUSE. No celular ele nunca aparece, e o dono usa o
// sistema no iPhone: ali o botão vira um desenho sem legenda. Leitor de tela também o
// ignora, então uma lista de vinte linhas anuncia vinte botões chamados "botão".
//
// O que conta como nome: `aria-label`, `aria-labelledby` ou um `<span className="sr-only">`
// dentro do botão.
//
// Este teste guarda um TETO, não zero. Em 24/09/2026 havia 70 botões assim; 13 foram
// nomeados copiando o `title` que já existia, e os 57 restantes não têm title nenhum —
// para esses é preciso DECIDIR o nome, uma tela de cada vez. O teto impede que a fila
// cresça enquanto isso é feito, e deve ser baixado a cada lote resolvido.
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

/** Quantos ainda faltam. Só pode DESCER. */
const TETO = 57;

const RAIZ = process.cwd();
const PASTAS = ['src/pages', 'src/components', 'src/v2'];

function arquivosTsx(dir: string): string[] {
  const saida: string[] = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) saida.push(...arquivosTsx(p));
    else if (e.name.endsWith('.tsx') && !/\.test\.|\.smoke\./.test(e.name)) saida.push(p);
  }
  return saida;
}

/** Botões cujo conteúdo é só ícone e que não declaram nome nenhum. */
function semNome(conteudo: string): number {
  let n = 0;
  for (const b of conteudo.match(/<Button[\s>][\s\S]*?<\/Button>/g) ?? []) {
    const corpo = b.replace(/^<Button[\s\S]*?>/, '').replace(/<\/Button>$/, '');
    const texto = corpo.replace(/<[^>]*>/g, '').replace(/\{[^}]*\}/g, '').trim();
    const soIcone = texto.length === 0 && /<[A-Z]\w*[\s/]/.test(corpo);
    if (!soIcone) continue;
    if (/aria-label|sr-only|aria-labelledby/.test(b)) continue;
    n += 1;
  }
  return n;
}

describe('botão de ícone tem nome acessível', () => {
  const achados: Array<{ arquivo: string; quantos: number }> = [];
  for (const pasta of PASTAS) {
    const dir = path.join(RAIZ, pasta);
    if (!fs.existsSync(dir)) continue;
    for (const arquivo of arquivosTsx(dir)) {
      const quantos = semNome(fs.readFileSync(arquivo, 'utf8'));
      if (quantos > 0) achados.push({ arquivo: path.relative(RAIZ, arquivo), quantos });
    }
  }
  const total = achados.reduce((s, a) => s + a.quantos, 0);

  it(`não passa de ${TETO} botões sem nome`, () => {
    const piores = [...achados].sort((a, b) => b.quantos - a.quantos).slice(0, 8)
      .map((a) => `${a.quantos}× ${a.arquivo}`).join('\n  ');
    expect(total, `Botões de ícone sem nome acessível subiu para ${total}.\n  ${piores}\n` +
      'Use aria-label (ou title + aria-label) no botão novo.').toBeLessThanOrEqual(TETO);
  });

  it('o teto acompanha a realidade — baixe-o quando resolver um lote', () => {
    // Se isto falhar, é boa notícia: sobraram menos do que o teto diz. Baixe o TETO.
    expect(total, `Sobraram ${total}; o teto está em ${TETO} e pode ser baixado.`)
      .toBeGreaterThan(TETO - 10);
  });
});
