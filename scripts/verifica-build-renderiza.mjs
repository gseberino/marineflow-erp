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
 *
 * 04/10/2026 — o portão testava o build ERRADO quando várias sessões rodavam neste PC: a porta
 * era fixa (4173) e, no Windows, `spawn('npx', …, { shell: true })` + `kill()` matava só o
 * cmd — o `vite preview` ficava vivo. Um esquecido de outra pasta (desde 03/10 17:20) segurava
 * a porta; o preview novo não subia (--strictPort), mas a espera recebia 200 do esquecido. Deu
 * "OK" falso e, depois, 466 erros falsos num build bom. Agora: porta livre escolhida na hora,
 * vite rodado pelo node direto (o kill encerra o servidor de verdade) e conferência de que quem
 * responde serve ESTE dist/.
 */
import { spawn } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { createServer } from 'node:net';
import { dirname, join } from 'node:path';
import { chromium } from 'playwright';

const alvoExterno = process.argv[2];

/** Uma porta que ninguém está usando agora (o sistema escolhe). */
function portaLivre() {
  return new Promise((ok, falha) => {
    const s = createServer();
    s.once('error', falha);
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => ok(port));
    });
  });
}

/** O script de entrada que um index.html carrega (/assets/index-<hash>.js). */
function entradaDo(html) {
  return (html.match(/\/assets\/index-[^"']+\.js/) || [null])[0];
}

async function esperarServidor(url, tentativas = 40) {
  for (let i = 0; i < tentativas; i++) {
    if (preview && preview.exitCode !== null) return false; // o vite saiu (porta tomada no meio?)
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
  const porta = await portaLivre();
  const viteBin = join(dirname(createRequire(import.meta.url).resolve('vite/package.json')), 'bin', 'vite.js');
  // Node direto, sem shell: o kill() encerra o próprio vite (com shell, no Windows, sobrava ele).
  preview = spawn(process.execPath, [viteBin, 'preview', '--host', '127.0.0.1', '--port', String(porta), '--strictPort'], {
    stdio: 'ignore',
  });
  process.on('exit', () => { if (preview && preview.exitCode === null) preview.kill(); });
  url = `http://127.0.0.1:${porta}/`;
  if (!await esperarServidor(url)) {
    console.error('FALHOU: o servidor de preview não subiu. Rodou `npm run build` antes?');
    process.exit(1);
  }
  // Quem responde tem de servir ESTE build: mesmo script de entrada do dist/index.html.
  const servido = entradaDo(await (await fetch(url)).text());
  const local = entradaDo(readFileSync('dist/index.html', 'utf8'));
  if (!local || servido !== local) {
    console.error(`FALHOU: o servidor em ${url} não está servindo este dist/ (entrada ${servido} ≠ ${local}). O portão testaria outro build.`);
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

// Abrir o login só avalia o chunk principal. As telas carregadas sob demanda (OS, Fiscal,
// Configurações, Agenda… — 04/10/2026) só rodam quando a rota abre, e um ciclo entre chunks
// ("Cannot access 'X' before initialization") nelas passaria por aqui sem ser visto. Então,
// no build local, importa CADA chunk de dist/assets dentro da página: o erro de avaliação do
// módulo aparece no import.
let chunksAvaliados = 0;
if (!alvoExterno && estado.filhos > 0) {
  const chunks = readdirSync('dist/assets').filter((f) => f.endsWith('.js'));
  const falhas = await page.evaluate(async (lista) => {
    const out = [];
    for (const f of lista) {
      try { await import(`/assets/${f}`); } catch (e) { out.push(`${f}: ${e && e.message}`); }
    }
    return out;
  }, chunks);
  chunksAvaliados = chunks.length;
  falhas.forEach((f) => erros.push(`chunk ${f.slice(0, 200)}`));
  await page.waitForTimeout(500);
}

await browser.close();
if (preview) preview.kill();

// Erro de página (fatal) antes do barulho de console: com os 10 primeiros sendo 404 de console,
// o erro que derrubava o portão nem aparecia na saída.
erros.sort((a, b) => Number(a.startsWith('[console]')) - Number(b.startsWith('[console]')));

const renderizou = estado.filhos > 0 && estado.htmlLen > 200;
// Erro de página é fatal; erro de console pode ser barulho de terceiro (extensão, analytics).
const fatal = erros.filter((e) => !e.startsWith('[console]'));

console.log(`#root: ${estado.filhos} filho(s), ${estado.htmlLen} caracteres`);
if (chunksAvaliados) console.log(`chunks avaliados no navegador: ${chunksAvaliados}`);
if (erros.length) {
  console.log(`\n${erros.length} erro(s):`);
  erros.slice(0, 10).forEach((e) => console.log(' · ' + e));
}

if (renderizou && fatal.length > 0 && fatal.every((e) => e.startsWith('chunk '))) {
  console.error('\nFALHOU: o login abre, mas uma tela carregada sob demanda quebra ao abrir. Não publique este build.');
  process.exit(1);
}
if (!renderizou || fatal.length > 0) {
  console.error('\nFALHOU: a aplicação NÃO renderizou. Não publique este build.');
  process.exit(1);
}
console.log('\nOK: a aplicação renderizou.');
