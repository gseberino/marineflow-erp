// Passo 6 — sobe as fotos aprovadas para o bucket product-images e grava
// products.image_url.
//
//   node scripts/catalogo-fotos/6-subir.mjs <pastaDeDados> [opções]
//
//   --rejeitar 2763,2775   não sobe nem grava esses SKUs (o que você vetou na conferência)
//   --so-subir             sobe os arquivos mas NÃO toca em products.image_url
//   --seco                 não escreve nada: só lista o que faria
//
// Credenciais vêm do ambiente e nunca são impressas:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Idempotente: o caminho no bucket é derivado do SKU, então rodar de novo
// substitui o arquivo em vez de criar cópia. Só grava image_url de produto que
// ainda está sem foto — nunca sobrescreve foto existente sem --forcar.

import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const dados = args[0] && !args[0].startsWith('--') ? args[0] : path.join(process.cwd(), '.catalogo-fotos');
const opcao = (nome) => {
  const i = args.indexOf(`--${nome}`);
  return i === -1 ? null : args[i + 1];
};
const tem = (nome) => args.includes(`--${nome}`);

const rejeitados = new Set((opcao('rejeitar') || '').split(',').map((s) => s.trim()).filter(Boolean));
const soSubir = tem('so-subir');
const seco = tem('seco');
const forcar = tem('forcar');

const BUCKET = 'product-images';
const PREFIXO = 'catalogo/victron';

const url = process.env.SUPABASE_URL;
const chave = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!seco && (!url || !chave)) {
  console.error('faltam SUPABASE_URL e/ou SUPABASE_SERVICE_ROLE_KEY no ambiente.');
  console.error('(rode com --seco para ver o que o script faria sem credencial)');
  process.exit(1);
}
// import tardio: o ensaio (--seco) roda sem o SDK, útil em worktree sem node_modules
const sb = seco
  ? null
  : (await import('@supabase/supabase-js')).createClient(url, chave, {
      auth: { persistSession: false },
    });

const casamento = JSON.parse(fs.readFileSync(path.join(dados, 'casamento.json'), 'utf8'));
const pasta = path.join(dados, 'normalizadas');

const chaveDe = (item) =>
  item.sku || item.name.replace(/[^a-z0-9]+/gi, '-').slice(0, 40).toLowerCase();

const fila = casamento
  .filter((c) => c.status === 'candidato')
  .map((c) => ({ ...c, chave: chaveDe(c) }))
  .filter((c) => !rejeitados.has(c.chave))
  .filter((c) => fs.existsSync(path.join(pasta, `${c.chave}.jpg`)));

console.log(`na fila: ${fila.length}  ·  vetados: ${rejeitados.size}  ·  modo: ${
  seco ? 'seco' : soSubir ? 'só subir' : 'subir + gravar'
}`);

let subidas = 0;
let gravadas = 0;
const falhas = [];

for (const item of fila) {
  const arquivo = path.join(pasta, `${item.chave}.jpg`);
  const destino = `${PREFIXO}/${item.chave}.jpg`;

  if (seco) {
    console.log(`  [seco] ${item.chave} -> ${BUCKET}/${destino}`);
    continue;
  }

  const { error: erroUpload } = await sb.storage
    .from(BUCKET)
    .upload(destino, fs.readFileSync(arquivo), {
      contentType: 'image/jpeg',
      cacheControl: '31536000',
      upsert: true,
    });

  if (erroUpload) {
    falhas.push({ chave: item.chave, etapa: 'upload', erro: erroUpload.message });
    console.error(`  ${item.chave}: upload falhou — ${erroUpload.message}`);
    continue;
  }
  subidas++;

  if (soSubir) continue;

  const { data: publica } = sb.storage.from(BUCKET).getPublicUrl(destino);

  // grava só onde ainda não há foto: o piloto não sobrescreve trabalho manual
  let q = sb.from('products').update({ image_url: publica.publicUrl });
  q = item.sku ? q.eq('sku', item.sku) : q.eq('name', item.name);
  if (!forcar) q = q.is('image_url', null);

  const { data, error: erroUpdate } = await q.select('id');
  if (erroUpdate) {
    falhas.push({ chave: item.chave, etapa: 'update', erro: erroUpdate.message });
    console.error(`  ${item.chave}: update falhou — ${erroUpdate.message}`);
    continue;
  }
  if (!data?.length) {
    console.warn(`  ${item.chave}: nenhuma linha atualizada (já tinha foto? SKU mudou?)`);
    continue;
  }
  gravadas++;
  console.log(`  ${item.chave} ok`);
}

console.log(`\nsubidas: ${subidas}  ·  image_url gravados: ${gravadas}  ·  falhas: ${falhas.length}`);
if (falhas.length) console.log(JSON.stringify(falhas, null, 2));
