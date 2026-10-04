// Checagem de tipos de todas as Edge Functions (NOVO-001 / MF-AUD-046, 03/10/2026).
//
// O CI só rodava `deno test --no-check`: erro de tipo numa função só aparecia em produção (o
// incidente de 24/09 passou por todos os portões). `tsc` não cobre supabase/functions.
//
// `--node-modules-dir=none`: com o node_modules/ do frontend na raiz, o Deno procurava ali os
// pacotes `npm:` das funções (nodemailer, web-push) e falhava; sem ele, usa o cache próprio.
// Uso: node scripts/check-edge.mjs   (o mesmo comando no CI e na máquina, Windows ou Linux)
import { readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const raiz = join(import.meta.dirname, '..', 'supabase', 'functions');
const entradas = readdirSync(raiz, { withFileTypes: true })
  .filter((d) => d.isDirectory() && !d.name.startsWith('_') && existsSync(join(raiz, d.name, 'index.ts')))
  .map((d) => join('supabase', 'functions', d.name, 'index.ts'));

console.log(`deno check em ${entradas.length} funções…`);
const r = spawnSync('deno', ['check', '--node-modules-dir=none', ...entradas], {
  cwd: join(import.meta.dirname, '..'),
  stdio: 'inherit',
  shell: process.platform === 'win32',
});
process.exit(r.status ?? 1);
