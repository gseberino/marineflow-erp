// Passo 1 — baixa o sitemap público da Victron e extrai o índice de páginas de
// produto com as imagens associadas (o sitemap usa a extensão image: do schema
// do Google, então cada página já vem com a lista de fotos oficiais).
//
//   node scripts/catalogo-fotos/1-sitemap.mjs [pastaDeDados]
//
// Saída: <pastaDeDados>/victron-catalogo.json

import fs from 'node:fs';
import path from 'node:path';

const SITEMAP = 'https://www.victronenergy.com/sitemap.xml';
const dados = process.argv[2] || path.join(process.cwd(), '.catalogo-fotos');
fs.mkdirSync(dados, { recursive: true });

const destinoXml = path.join(dados, 'victron-sitemap.xml');
const destinoJson = path.join(dados, 'victron-catalogo.json');

let xml;
if (fs.existsSync(destinoXml) && !process.argv.includes('--forcar')) {
  console.log('sitemap em cache:', destinoXml, '(use --forcar para rebaixar)');
  xml = fs.readFileSync(destinoXml, 'utf8');
} else {
  console.log('baixando', SITEMAP);
  const res = await fetch(SITEMAP, {
    headers: { 'user-agent': 'MarineFlow-catalog/1.0 (+catálogo de revendedor)' },
  });
  if (!res.ok) throw new Error(`sitemap respondeu ${res.status}`);
  xml = await res.text();
  fs.writeFileSync(destinoXml, xml);
}

const catalogo = [];
for (const bloco of xml.split('<url>').slice(1)) {
  const loc = /<loc>([^<]+)<\/loc>/.exec(bloco)?.[1];
  if (!loc) continue;
  const partes = loc.replace(/^https?:\/\/[^/]+\/?/, '').split('/').filter(Boolean);
  if (partes.length !== 2) continue; // só /categoria/slug = página de produto
  catalogo.push({
    url: loc,
    categoria: partes[0],
    slug: partes[1],
    imagens: [...bloco.matchAll(/<image:loc>([^<]+)<\/image:loc>/g)].map((m) => m[1].trim()),
  });
}

// o mesmo produto aparece em mais de uma categoria; consolida por slug
const porSlug = new Map();
for (const p of catalogo) {
  const anterior = porSlug.get(p.slug);
  if (!anterior) porSlug.set(p.slug, p);
  else anterior.imagens = [...new Set([...anterior.imagens, ...p.imagens])];
}

const consolidado = [...porSlug.values()];
fs.writeFileSync(destinoJson, JSON.stringify(consolidado, null, 2));

console.log(`páginas de produto: ${consolidado.length}`);
console.log(`com imagem: ${consolidado.filter((c) => c.imagens.length).length}`);
console.log(`imagens no total: ${consolidado.reduce((a, c) => a + c.imagens.length, 0)}`);
console.log('->', destinoJson);
