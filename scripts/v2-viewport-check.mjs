/* ── MarineFlow v2 — Princípio 0: verificação de scroll horizontal ──────────
   Faz login com o usuário demo, abre /design-preview e, para cada largura ×
   tema, assevera que NADA rola para o lado:
     - documentElement.scrollWidth ≤ clientWidth (página)
     - todo descendente com scrollWidth > clientWidth+1 é reportado (elemento)
   Também captura screenshots para aprovação visual.

   Uso:
     DEMO_EMAIL=... DEMO_PASSWORD=... node scripts/v2-viewport-check.mjs [baseURL] [outDir]
   Padrões: baseURL http://localhost:8080 · outDir ./v2-screenshots
   Sai com código 1 se qualquer verificação falhar.
──────────────────────────────────────────────────────────────────────────── */
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

const BASE = process.argv[2] || 'http://localhost:8080';
const OUT = process.argv[3] || './v2-screenshots';
const EMAIL = process.env.DEMO_EMAIL;
const PASSWORD = process.env.DEMO_PASSWORD;
const VIEWPORTS = [360, 390, 768, 1024, 1440];
/* Cada página verificada: /design-preview tem alternador de tema (2 modos);
   as rotas piloto v2 rodam no tema claro padrão por enquanto. */
/* Páginas v2 usam o V2Shell: o tema vem de localStorage('mf-v2-theme'), então
   o verificador seta a chave e recarrega para testar claro E escuro. O preview
   tem alternador próprio (botões Claro/Escuro). */
const PAGES = [
  { path: '/design-preview', modes: ['light', 'dark'], slug: 'preview', themeVia: 'buttons' },
  { path: '/v2/service-orders', modes: ['light', 'dark'], slug: 'os', themeVia: 'storage' },
  { path: '/v2/quotes', modes: ['light', 'dark'], slug: 'quotes', themeVia: 'storage' },
  { path: '/v2/dashboard', modes: ['light', 'dark'], slug: 'dash', themeVia: 'storage' },
  { path: '/v2/receivables', modes: ['light', 'dark'], slug: 'rec', themeVia: 'storage' },
  { path: '/v2/clients', modes: ['light', 'dark'], slug: 'clients', themeVia: 'storage' },
  { path: '/v2/vessels', modes: ['light', 'dark'], slug: 'vessels', themeVia: 'storage' },
  { path: '/v2/marinas', modes: ['light', 'dark'], slug: 'marinas', themeVia: 'storage' },
  { path: '/v2/products', modes: ['light', 'dark'], slug: 'products', themeVia: 'storage' },
  { path: '/v2/services', modes: ['light', 'dark'], slug: 'services', themeVia: 'storage' },
  { path: '/v2/suppliers', modes: ['light', 'dark'], slug: 'suppliers', themeVia: 'storage' },
  { path: '/v2/financial', modes: ['light', 'dark'], slug: 'financial', themeVia: 'storage' },
  { path: '/v2/financial?tab=payables', modes: ['light', 'dark'], slug: 'payables', themeVia: 'storage' },
  { path: '/v2/collections', modes: ['light', 'dark'], slug: 'collections', themeVia: 'storage' },
  { path: '/v2/commissions', modes: ['light', 'dark'], slug: 'commissions', themeVia: 'storage' },
  { path: '/v2/reports', modes: ['light', 'dark'], slug: 'reports', themeVia: 'storage' },
  { path: '/v2/inventory/smart-purchase', modes: ['light', 'dark'], slug: 'smartbuy', themeVia: 'storage' },
  { path: '/v2/inventory', modes: ['light', 'dark'], slug: 'inventory', themeVia: 'storage' },
  { path: '/v2/inventory?tab=movements', modes: ['light', 'dark'], slug: 'movements', themeVia: 'storage' },
  { path: '/v2/purchase-orders', modes: ['light', 'dark'], slug: 'po', themeVia: 'storage' },
  { path: '/v2/crm', modes: ['light', 'dark'], slug: 'crm', themeVia: 'storage' },
  { path: '/v2/external-quotes/catalog', modes: ['light', 'dark'], slug: 'catalog', themeVia: 'storage' },
  /* Compras: estas duas são telas de LISTA (cards). O mapa de cotação — o pior
     caso de largura do sistema (itens × fornecedores) — vive no DETALHE, em
     /purchasing/quotes/:id, e entra na lista em tempo de execução logo após o
     login, porque o id varia por ambiente. */
  { path: '/purchasing', modes: ['light', 'dark'], slug: 'purchasing-hub', themeVia: 'storage' },
  { path: '/purchasing/quotes', modes: ['light', 'dark'], slug: 'quotes-list', themeVia: 'storage' },
  /* Telas nascidas depois do inventário original do redesign (auditoria
     30/07/2026): tudo que entra no sistema entra também neste crivo. */
  { path: '/day-board', modes: ['light', 'dark'], slug: 'dayboard', themeVia: 'storage' },
  { path: '/v2/financial?tab=banks', modes: ['light', 'dark'], slug: 'fin-banks', themeVia: 'storage' },
  { path: '/v2/financial?tab=inbox', modes: ['light', 'dark'], slug: 'fin-inbox', themeVia: 'storage' },
  { path: '/v2/financial?tab=rules', modes: ['light', 'dark'], slug: 'fin-rules', themeVia: 'storage' },
];

if (!EMAIL || !PASSWORD) {
  console.error('Defina DEMO_EMAIL e DEMO_PASSWORD no ambiente.');
  process.exit(1);
}

mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
/* Contexto explícito, e não browser.newPage(): a suíte troca de página a cada
   tela para não acumular memória (ver o loop adiante), e páginas do MESMO
   contexto compartilham localStorage — que é onde a sessão do Supabase vive.
   Com browser.newPage() cada página nasceria isolada e deslogada. */
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
let page = await context.newPage();
let failures = 0;

// Login pela UI (mesmo caminho do usuário real)
await page.goto(`${BASE}/login`, { waitUntil: 'networkidle' });
await page.fill('input[type="email"]', EMAIL);
await page.fill('input[type="password"]', PASSWORD);
await page.click('button[type="submit"]');

// A LoginPage não navega quando o signIn falha: mostra um toast e fica em
// /login. Esperar só pela URL transforma "senha errada", "email não confirmado"
// e "muitas tentativas" num TimeoutError mudo, que custa uma sessão inteira de
// diagnóstico. Corremos as duas coisas e relatamos a que chegar primeiro.
const TOAST = '[data-sonner-toast], [role="status"]';
const navegou = page
  .waitForURL((u) => !u.pathname.includes('/login'), { timeout: 30000 })
  .then(() => null);
const erroNoToast = page
  .locator(TOAST)
  .first()
  .waitFor({ state: 'visible', timeout: 30000 })
  .then(() => page.locator(TOAST).first().innerText())
  .then((t) => t.replace(/\s+/g, ' ').trim());

const desfecho = await Promise.race([navegou, erroNoToast]).catch(
  () => 'login não concluiu em 30s (sem toast e sem navegação)',
);
if (desfecho) {
  console.error(`login FALHOU: ${desfecho}`);
  await page.screenshot({ path: join(OUT, 'login-falhou.png'), fullPage: true });
  await browser.close();
  process.exit(1);
}
console.log('login ok');

/* O mapa de cotação (detalhe) é o pior caso de largura, mas o id varia por
   ambiente — descobrimos pelo primeiro card da lista em vez de fixar um UUID.
   Sem cotação cadastrada a entrada é pulada, e o aviso deixa claro que a tela
   mais crítica do módulo ficou sem cobertura naquela rodada. */
await page.goto(`${BASE}/purchasing/quotes`, { waitUntil: 'networkidle', timeout: 60000 });
const primeiraCotacao = await page.evaluate(() => {
  const a = document.querySelector('a[href*="/purchasing/quotes/"]');
  return a ? new URL(a.href).pathname : null;
});
if (primeiraCotacao) {
  PAGES.push({ path: primeiraCotacao, modes: ['light', 'dark'], slug: 'quote-detail', themeVia: 'storage' });
  console.log(`mapa de cotação: ${primeiraCotacao}`);
} else {
  console.warn('AVISO: nenhuma cotação cadastrada — mapa de cotação NÃO verificado.');
}

for (const pg of PAGES) {
  /* Uma página que não carrega é FALHA dela, não motivo para abortar as
     demais: antes, um timeout aqui derrubava o processo e deixava todas as
     telas seguintes — inclusive as de compras, que vêm no fim da lista — sem
     verificação nenhuma, sem que isso ficasse evidente na saída. */
  try {
    /* Página nova a cada tela. Sem isso, o Chrome ia acumulando memória ao
       longo das ~290 combinações (screenshots de página inteira em listas
       longas) e, por volta da metade da suíte, telas pesadas simplesmente
       paravam de renderizar — a falha migrava entre services e suppliers e
       sumia quando a tela era aberta isolada. O contexto é o mesmo, então a
       sessão continua válida e não é preciso relogar. */
    const anterior = page;
    page = await context.newPage();
    await anterior.close();

    await page.setViewportSize({ width: 1280, height: 900 });
    // Primeira visita usa timeout largo: o Vite compila a página sob demanda
    // no dev server e a transformação fria pode passar de 20s.
    await page.goto(`${BASE}${pg.path}`, { waitUntil: 'networkidle', timeout: 60000 });
    // Tema global (R1): .themev2 vive no <html>, que o Playwright não considera
    // "visível" — esperar por presença (attached), não visibilidade.
    await page.waitForSelector('.themev2', { timeout: 60000, state: 'attached' });
  } catch (e) {
    failures++;
    console.log(`FAIL  ${pg.slug.padEnd(7)} —— não carregou: ${String(e.message).split('\n')[0]}`);
    continue;
  }

  for (const mode of pg.modes) {
    // Mesma regra da navegação: se a troca de tema não completar, é falha
    // deste modo — as outras telas continuam sendo verificadas.
    try {
      if (pg.themeVia === 'buttons') {
        await page.click(mode === 'light' ? 'button:has-text("Claro")' : 'button:has-text("Escuro")');
        await page.waitForTimeout(250);
      } else {
        await page.evaluate((m) => localStorage.setItem('mf-v2-theme', m), mode);
        await page.reload({ waitUntil: 'networkidle' });
        // Mesmo teto da navegação inicial (60s): sob carga acumulada da suíte,
        // 20s produzia FAIL intermitente em telas pesadas que passam sozinhas.
        await page.waitForSelector('.themev2', { timeout: 60000, state: 'attached' });
      }
    } catch (e) {
      failures++;
      console.log(`FAIL  ${pg.slug.padEnd(7)} ${mode.padEnd(5)} —— tema não aplicou: ${String(e.message).split('\n')[0]}`);
      continue;
    }
    for (const width of VIEWPORTS) {
      await page.setViewportSize({ width, height: 900 });
      await page.waitForTimeout(400); // ResizeObserver do DataTable reagir

      const report = await page.evaluate(() => {
        const doc = document.documentElement;
        const pageOverflow = doc.scrollWidth - doc.clientWidth;
        // Elemento com overflow interno só é ofensor se NENHUM ancestral (até
        // .themev2) o clipa: conteúdo clipado por overflow-x hidden não gera
        // barra de rolagem — é decisão deliberada de corte, não vazamento.
        const clippedByAncestor = (el) => {
          for (let n = el; n && n !== document.body; n = n.parentElement) {
            if (getComputedStyle(n).overflowX === 'hidden') return true;
          }
          return false;
        };
        const offenders = [];
        for (const el of document.querySelectorAll('.themev2 *')) {
          if (el.scrollWidth > el.clientWidth + 1 && !clippedByAncestor(el)) {
            offenders.push(
              `${el.tagName.toLowerCase()}.${String(el.className).split(' ').slice(0, 3).join('.')} ` +
              `(${el.scrollWidth}>${el.clientWidth})`,
            );
          }
        }
        return { pageOverflow, offenders: offenders.slice(0, 5) };
      });

      const ok = report.pageOverflow <= 0 && report.offenders.length === 0;
      if (!ok) failures++;
      console.log(
        `${ok ? 'PASS' : 'FAIL'}  ${pg.slug.padEnd(7)} ${mode.padEnd(5)} ${String(width).padStart(4)}px` +
        (report.pageOverflow > 0 ? `  página estoura ${report.pageOverflow}px` : '') +
        (report.offenders.length ? `  elementos: ${report.offenders.join(' | ')}` : ''),
      );

      /* O screenshot é aprovação visual, não é a verificação — esta já rodou
         acima. Em páginas muito altas (listas longas) o Chrome recusa o
         fullPage com "Unable to capture screenshot", e derrubar a suíte inteira
         por causa disso deixava as telas seguintes sem verificação nenhuma.
         Cai para viewport-only e, se ainda assim falhar, segue em frente. */
      const alvo = join(OUT, `${pg.slug}-${mode}-${width}.png`);
      try {
        await page.screenshot({ path: alvo, fullPage: width >= 768 });
      } catch {
        try {
          await page.screenshot({ path: alvo, fullPage: false });
          console.warn(`      (screenshot de ${pg.slug} ${mode} ${width}px: só viewport, página alta demais)`);
        } catch {
          console.warn(`      (screenshot de ${pg.slug} ${mode} ${width}px falhou — verificação acima vale)`);
        }
      }
    }
  }
}

await browser.close();
console.log(failures === 0 ? '\nPrincípio 0: OK em todas as combinações.' : `\n${failures} combinações FALHARAM.`);
process.exit(failures === 0 ? 0 : 1);
