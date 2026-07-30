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
];

if (!EMAIL || !PASSWORD) {
  console.error('Defina DEMO_EMAIL e DEMO_PASSWORD no ambiente.');
  process.exit(1);
}

mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
let failures = 0;

// Login pela UI (mesmo caminho do usuário real)
await page.goto(`${BASE}/login`, { waitUntil: 'networkidle' });
await page.fill('input[type="email"]', EMAIL);
await page.fill('input[type="password"]', PASSWORD);
await page.click('button[type="submit"]');
await page.waitForURL((u) => !u.pathname.includes('/login'), { timeout: 20000 });
console.log('login ok');

for (const pg of PAGES) {
  await page.setViewportSize({ width: 1280, height: 900 });
  // Primeira visita usa timeout largo: o Vite compila a página sob demanda
  // no dev server e a transformação fria pode passar de 20s.
  await page.goto(`${BASE}${pg.path}`, { waitUntil: 'networkidle', timeout: 60000 });
  // Tema global (R1): .themev2 vive no <html>, que o Playwright não considera
  // "visível" — esperar por presença (attached), não visibilidade.
  await page.waitForSelector('.themev2', { timeout: 60000, state: 'attached' });

  for (const mode of pg.modes) {
    if (pg.themeVia === 'buttons') {
      await page.click(mode === 'light' ? 'button:has-text("Claro")' : 'button:has-text("Escuro")');
      await page.waitForTimeout(250);
    } else {
      await page.evaluate((m) => localStorage.setItem('mf-v2-theme', m), mode);
      await page.reload({ waitUntil: 'networkidle' });
      await page.waitForSelector('.themev2', { timeout: 20000, state: 'attached' });
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

      await page.screenshot({
        path: join(OUT, `${pg.slug}-${mode}-${width}.png`),
        fullPage: width >= 768,
      });
    }
  }
}

await browser.close();
console.log(failures === 0 ? '\nPrincípio 0: OK em todas as combinações.' : `\n${failures} combinações FALHARAM.`);
process.exit(failures === 0 ? 0 : 1);
