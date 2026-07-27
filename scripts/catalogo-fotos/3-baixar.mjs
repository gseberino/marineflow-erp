// Passo 3 — baixa as fotos oficiais escolhidas no passo 2.
//
//   node scripts/catalogo-fotos/3-baixar.mjs [pastaDeDados]
//
// Entrada: <dados>/casamento.json
// Saída:   <dados>/fotos/<sku>.<ext>  +  <dados>/baixadas.json
//
// Ritmo deliberadamente lento (uma foto por vez, com pausa): é o site de um
// fabricante, não uma API nossa.

import fs from 'node:fs';
import path from 'node:path';

const dados = process.argv[2] || path.join(process.cwd(), '.catalogo-fotos');
const pastaFotos = path.join(dados, 'fotos');
fs.mkdirSync(pastaFotos, { recursive: true });

const casamento = JSON.parse(fs.readFileSync(path.join(dados, 'casamento.json'), 'utf8'));
const alvos = casamento.filter((c) => c.status === 'candidato' && c.imagem);

const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const baixadas = [];

for (const [i, item] of alvos.entries()) {
  const ext = (path.extname(new URL(item.imagem).pathname) || '.png').toLowerCase();
  const chave = item.sku || item.name.replace(/[^a-z0-9]+/gi, '-').slice(0, 40).toLowerCase();
  const destino = path.join(pastaFotos, `${chave}${ext}`);

  if (fs.existsSync(destino) && !process.argv.includes('--forcar')) {
    baixadas.push({ ...item, arquivo_local: destino, bytes: fs.statSync(destino).size });
    continue;
  }

  try {
    const res = await fetch(item.imagem, {
      headers: { 'user-agent': 'MarineFlow-catalog/1.0 (+catálogo de revendedor)' },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(destino, buf);
    baixadas.push({ ...item, arquivo_local: destino, bytes: buf.length });
    console.log(
      `${String(i + 1).padStart(2)}/${alvos.length}  ${chave}${ext}  ${(buf.length / 1024).toFixed(0)} KB`,
    );
  } catch (err) {
    console.error(`${String(i + 1).padStart(2)}/${alvos.length}  ${chave}: FALHOU — ${err.message}`);
    baixadas.push({ ...item, erro: String(err.message) });
  }
  await pausa(700);
}

fs.writeFileSync(path.join(dados, 'baixadas.json'), JSON.stringify(baixadas, null, 2));
const ok = baixadas.filter((b) => b.arquivo_local);
console.log(`\nbaixadas: ${ok.length}/${alvos.length}`);
console.log(`peso total: ${(ok.reduce((a, b) => a + (b.bytes || 0), 0) / 1024 / 1024).toFixed(1)} MB`);
console.log('->', pastaFotos);
