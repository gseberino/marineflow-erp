// Passo 6 — sobe as fotos aprovadas para o bucket product-images.
//
//   node scripts/catalogo-fotos/6-subir.mjs <pastaDeDados> [opções]
//
//   --seco                 não escreve nada: só lista o que faria
//   --rejeitar 2763,2775   pula esses SKUs (o que foi vetado na conferência)
//   --gravar-url           também grava products.image_url (por padrão NÃO grava:
//                          o passo de banco costuma ser feito por SQL revisado)
//
// Credenciais pelo ambiente, nunca impressas nem gravadas:
//   SUPABASE_URL                 ex.: https://<ref>.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY
//
// Sem dependência de pacote — fala HTTP direto com a API de Storage. Assim roda
// de qualquer pasta, inclusive worktree sem node_modules. (A CLI do Supabase não
// serve aqui: este projeto usa o storage legado, que a CLI atual não escreve.)
//
// Idempotente: o caminho é derivado do SKU e sobe com x-upsert, então rodar de
// novo substitui o arquivo em vez de criar cópia.

import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const dados =
  args[0] && !args[0].startsWith('--') ? args[0] : path.join(process.cwd(), '.catalogo-fotos');
const opcao = (nome) => {
  const i = args.indexOf(`--${nome}`);
  return i === -1 ? null : args[i + 1];
};
const tem = (nome) => args.includes(`--${nome}`);

const rejeitados = new Set(
  (opcao('rejeitar') || '').split(',').map((s) => s.trim()).filter(Boolean),
);
const seco = tem('seco');
const gravarUrl = tem('gravar-url');

const BUCKET = 'product-images';
const PREFIXO = 'catalogo/victron';

const base = (process.env.SUPABASE_URL || '').replace(/\/+$/, '');
const chave = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!seco && (!base || !chave)) {
  console.error('faltam SUPABASE_URL e/ou SUPABASE_SERVICE_ROLE_KEY no ambiente.');
  console.error('(use --seco para ver o que o script faria, sem credencial)');
  process.exit(1);
}

const casamento = JSON.parse(fs.readFileSync(path.join(dados, 'casamento.json'), 'utf8'));
const pasta = path.join(dados, 'normalizadas');

const chaveDe = (item) =>
  item.sku || item.name.replace(/[^a-z0-9]+/gi, '-').slice(0, 40).toLowerCase();

const fila = casamento
  .filter((c) => c.status === 'candidato')
  .map((c) => ({ ...c, chave: chaveDe(c) }))
  .filter((c) => !rejeitados.has(c.chave))
  .filter((c) => fs.existsSync(path.join(pasta, `${c.chave}.jpg`)));

console.log(
  `na fila: ${fila.length}  ·  vetados: ${rejeitados.size}  ·  modo: ${
    seco ? 'seco' : gravarUrl ? 'subir + gravar image_url' : 'só subir'
  }`,
);

const urlPublica = (destino) => `${base}/storage/v1/object/public/${BUCKET}/${destino}`;
const mapa = [];
let subidas = 0;
let gravadas = 0;
const falhas = [];

for (const item of fila) {
  const arquivo = path.join(pasta, `${item.chave}.jpg`);
  const destino = `${PREFIXO}/${item.chave}.jpg`;
  mapa.push({ sku: item.sku, name: item.name, chave: item.chave, url: urlPublica(destino) });

  if (seco) {
    console.log(`  [seco] ${item.chave} -> ${BUCKET}/${destino}`);
    continue;
  }

  const corpo = fs.readFileSync(arquivo);
  const res = await fetch(`${base}/storage/v1/object/${BUCKET}/${destino}`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${chave}`,
      'content-type': 'image/jpeg',
      'cache-control': 'max-age=31536000',
      'x-upsert': 'true',
    },
    body: corpo,
  });

  if (!res.ok) {
    const detalhe = await res.text().catch(() => '');
    falhas.push({ chave: item.chave, etapa: 'upload', status: res.status, detalhe: detalhe.slice(0, 200) });
    console.error(`  ${item.chave}: upload falhou (${res.status})`);
    continue;
  }
  subidas++;
  console.log(`  ${item.chave} subiu`);

  if (!gravarUrl) continue;

  // só onde ainda não há foto: o lote não atropela trabalho manual do dono
  const filtro = item.sku
    ? `sku=eq.${encodeURIComponent(item.sku)}`
    : `name=eq.${encodeURIComponent(item.name)}`;
  const resDb = await fetch(`${base}/rest/v1/products?${filtro}&image_url=is.null`, {
    method: 'PATCH',
    headers: {
      authorization: `Bearer ${chave}`,
      apikey: chave,
      'content-type': 'application/json',
      prefer: 'return=representation',
    },
    body: JSON.stringify({ image_url: urlPublica(destino) }),
  });

  if (!resDb.ok) {
    const detalhe = await resDb.text().catch(() => '');
    falhas.push({ chave: item.chave, etapa: 'update', status: resDb.status, detalhe: detalhe.slice(0, 200) });
    console.error(`  ${item.chave}: update falhou (${resDb.status})`);
    continue;
  }
  const linhas = await resDb.json().catch(() => []);
  if (!linhas.length) {
    console.warn(`  ${item.chave}: nenhuma linha atualizada (já tinha foto? SKU mudou?)`);
    continue;
  }
  gravadas++;
}

fs.writeFileSync(path.join(dados, 'urls-publicas.json'), JSON.stringify(mapa, null, 2));
console.log(`\nsubidas: ${subidas}  ·  image_url gravados: ${gravadas}  ·  falhas: ${falhas.length}`);
console.log(`mapa sku -> url público: ${path.join(dados, 'urls-publicas.json')}`);
if (falhas.length) console.log(JSON.stringify(falhas, null, 2));
