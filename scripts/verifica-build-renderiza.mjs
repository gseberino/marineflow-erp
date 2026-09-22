/**
 * Prova que o BUILD abre: sobe o `vite preview`, carrega a página num navegador de verdade e
 * exige que `#root` tenha conteúdo e que nenhum erro de página tenha acontecido.
 *
 * Por que existe: em 19/09/2026 uma divisão manual de chunks (`build.rollupOptions.output
 * .manualChunks`) criou um ciclo de importação entre chunks; o resultado foi
 * "Cannot access 'P' before initialization" no boot e TELA BRANCA em produção por 3 dias.
 * `npx tsc -b`, `npm run build` e os 1.447 testes de componente passaram em todas as etapas —
 * o defeito só existe no bundle final avaliado pelo navegador. Este script é o portão que
 * faltava.
 *
 * Uso:  npm run build && node scripts/verifica-build-renderiza.mjs
 *       node scripts/verifica-build-renderiza.mjs https://marineflow-erp.vercel.app/   (produção)
 *
 * Sai com código 1 se a página não renderizar — serve para CI e para o passo anterior ao push.
 */
import { spawn } from 'node:child_process';
import { chromium } from 'playwright';

const alvoExterno = process.argv[2];
const PORTA = 4173;

async function esperarServidor(url, tentativas = 40) {
  for (let i = 0; i < tentativas; i++) {
    try {
      const r = await fetch(url);
      if (r.ok) return true;
    } catch { /* ainda subindo */ }
    await new Promise((r) => setTimeout(r, 500));
  }
  return false;
}

let preview = null;
let url = alvoExterno;

if (!alvoExterno) {
  preview = spawn('npx', ['vite', 'preview', '--port', String(PORTA), '--strictPort'], {
    stdio: 'ignore', shell: process.platform === 'win32',
  });
  url = `http://localhost:${PORTA}/`;
  if (!await esperarServidor(url)) {
    console.error('FALHOU: o servidor de preview não subiu. Rodou `npm run build` antes?');
    preview.kill();
    process.exit(1);
  }
}

const browser = await chromium.launch();
const page = await browser.newPage();
const erros = [];
page.on('pageerror', (e) => erros.push(`${e.name}: ${e.message}`));
page.on('console', (m) => { if (m.type() === 'error') erros.push(`[console] ${m.text().slice(0, 200)}`); });

let estado = { filhos: -1, htmlLen: -1 };
try {
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
  estado = await page.evaluate(() => {
    const r = document.getElementById('root');
    return { filhos: r ? r.children.length : -1, htmlLen: r ? r.innerHTML.length : -1 };
  });
} catch (e) {
  erros.push(`navegação: ${String(e).slice(0, 200)}`);
}

await browser.close();
if (preview) preview.kill();

const renderizou = estado.filhos > 0 && estado.htmlLen > 200;
// Erro de página é fatal; erro de console pode ser barulho de terceiro (extensão, analytics).
const fatal = erros.filter((e) => !e.startsWith('[console]'));

console.log(`#root: ${estado.filhos} filho(s), ${estado.htmlLen} caracteres`);
if (erros.length) {
  console.log(`\n${erros.length} erro(s):`);
  erros.slice(0, 10).forEach((e) => console.log(' · ' + e));
}

if (!renderizou || fatal.length > 0) {
  console.error('\nFALHOU: a aplicação NÃO renderizou. Não publique este build.');
  process.exit(1);
}
console.log('\nOK: a aplicação renderizou.');
