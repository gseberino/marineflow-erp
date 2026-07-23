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
const MODES = ['light', 'dark'];

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

await page.goto(`${BASE}/design-preview`, { waitUntil: 'networkidle' });
await page.waitForSelector('.themev2', { timeout: 20000 });

for (const mode of MODES) {
  await page.click(mode === 'light' ? 'button:has-text("Claro")' : 'button:has-text("Escuro")');
  await page.waitForTimeout(250);
  for (const width of VIEWPORTS) {
    await page.setViewportSize({ width, height: 900 });
    await page.waitForTimeout(400); // ResizeObserver do DataTable reagir

    const report = await page.evaluate(() => {
      const doc = document.documentElement;
      const pageOverflow = doc.scrollWidth - doc.clientWidth;
      const offenders = [];
      for (const el of document.querySelectorAll('.themev2 *')) {
        if (el.scrollWidth > el.clientWidth + 1 && getComputedStyle(el).overflowX !== 'hidden') {
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
      `${ok ? 'PASS' : 'FAIL'}  ${mode.padEnd(5)} ${String(width).padStart(4)}px` +
      (report.pageOverflow > 0 ? `  página estoura ${report.pageOverflow}px` : '') +
      (report.offenders.length ? `  elementos: ${report.offenders.join(' | ')}` : ''),
    );

    await page.screenshot({
      path: join(OUT, `preview-${mode}-${width}.png`),
      fullPage: width >= 768,
    });
  }
}

await browser.close();
console.log(failures === 0 ? '\nPrincípio 0: OK em todas as combinações.' : `\n${failures} combinações FALHARAM.`);
process.exit(failures === 0 ? 0 : 1);
