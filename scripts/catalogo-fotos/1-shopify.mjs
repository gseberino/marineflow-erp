// Passo 1, variante Shopify — para fabricantes cuja loja roda em Shopify.
//
//   node scripts/catalogo-fotos/1-shopify.mjs <pastaDeDados> <https://loja.com>
//
// Saída: <dados>/victron-catalogo.json  (mesmo formato do 1-sitemap.mjs, de
// propósito: os passos 2 a 6 não mudam nada)
//
// Por que existe: loja Shopify expõe /products.json, um catálogo estruturado com
// título, variantes e URLs de imagem em CDN. É melhor que sitemap — não precisa
// parsear HTML nem adivinhar qual <img> é a foto do produto. Descoberto ao
// procurar a fonte da EcoWorthy, e serve para qualquer marca na mesma plataforma.
//
// O "slug" aqui é o handle do Shopify, e as "imagens" saem na ordem em que a loja
// as publica — a primeira costuma ser a foto principal, que é o que o passo 2 usa
// como foto-herói quando não acha a variante exata.

import fs from 'node:fs';
import path from 'node:path';

const dados = process.argv[2];
const loja = (process.argv[3] || '').replace(/\/+$/, '');
if (!dados || !loja) {
  console.error('uso: node 1-shopify.mjs <pastaDeDados> <https://loja.com>');
  process.exit(1);
}
fs.mkdirSync(dados, { recursive: true });

const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const catalogo = [];
let pagina = 1;

while (pagina <= 40) {
  const url = `${loja}/products.json?limit=250&page=${pagina}`;
  const res = await fetch(url, {
    headers: { 'user-agent': 'MarineFlow-catalog/1.0 (+catálogo de revendedor)' },
  });
  if (!res.ok) {
    if (pagina === 1) throw new Error(`${loja} respondeu ${res.status} — a loja é mesmo Shopify?`);
    break;
  }
  const { products } = await res.json();
  if (!products?.length) break;

  for (const p of products) {
    catalogo.push({
      url: `${loja}/products/${p.handle}`,
      categoria: p.product_type || 'shopify',
      slug: p.handle,
      titulo: p.title,
      // variantes entram no nome do "arquivo" para o passo 2 casar especificação
      variantes: (p.variants || []).map((v) => v.title).filter((t) => t && t !== 'Default Title'),
      imagens: (p.images || []).map((i) => i.src),
    });
  }
  console.log(`página ${pagina}: ${products.length} produtos (total ${catalogo.length})`);
  pagina++;
  await pausa(600); // é a loja do fabricante, não uma API nossa
}

const destino = path.join(dados, 'victron-catalogo.json');
fs.writeFileSync(destino, JSON.stringify(catalogo, null, 2));

console.log(`\nprodutos: ${catalogo.length}`);
console.log(`com imagem: ${catalogo.filter((c) => c.imagens.length).length}`);
console.log(`imagens no total: ${catalogo.reduce((a, c) => a + c.imagens.length, 0)}`);
console.log('->', destino);
