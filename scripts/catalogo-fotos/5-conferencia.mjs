// Passo 5 — gera a página de conferência: uma grade com a foto que cada produto
// vai receber, para o dono aprovar ou rejeitar ANTES de qualquer gravação.
//
//   node scripts/catalogo-fotos/5-conferencia.mjs [pastaDeDados]
//
// Entradas: <dados>/casamento.json + <dados>/miniaturas/*.jpg
// Saída:    <dados>/conferencia.html  (miniaturas embutidas em base64, sem
//           depender de rede — é o formato que o Artifact aceita)

import fs from 'node:fs';
import path from 'node:path';

const dados = process.argv[2] || path.join(process.cwd(), '.catalogo-fotos');
const casamento = JSON.parse(fs.readFileSync(path.join(dados, 'casamento.json'), 'utf8'));
const pastaMini = path.join(dados, 'miniaturas');

const chaveDe = (item) =>
  item.sku || item.name.replace(/[^a-z0-9]+/gi, '-').slice(0, 40).toLowerCase();

const escapar = (s) =>
  String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

const dinheiro = (n) =>
  Number(n) > 0 ? Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }) : '—';

const NIVEIS = {
  'variante-exata': { rotulo: 'Variante confirmada', classe: 'ok' },
  variante: { rotulo: 'Variante provável', classe: 'ok' },
  familia: { rotulo: 'Foto da linha', classe: 'conferir' },
  aproximada: { rotulo: 'Aproximada', classe: 'conferir' },
};

const cartoes = casamento.map((item) => {
  const chave = chaveDe(item);
  const arquivoMini = path.join(pastaMini, `${chave}.jpg`);
  const temFoto = fs.existsSync(arquivoMini);
  const b64 = temFoto ? fs.readFileSync(arquivoMini).toString('base64') : null;
  const nivel = NIVEIS[item.nivel] || { rotulo: 'Sem candidato', classe: 'pendente' };
  return { ...item, chave, b64, nivel };
});

const conta = (c) => cartoes.filter((x) => x.nivel.classe === c).length;
// um cartão sem candidato já entra como "pendente"; não somar duas vezes
const semFoto = cartoes.filter((x) => !x.b64 && x.nivel.classe !== 'pendente').length;

const html = `<title>Fotos do catálogo Victron — conferência do piloto</title>
<style>
  :root {
    color-scheme: light dark;
    --papel: #eef2f5;
    --superficie: #ffffff;
    --superficie-2: #f4f7f9;
    --borda: #d3dde4;
    --tinta: #0d1a23;
    --tinta-fraca: #55697a;
    --azul: #12608f;
    --azul-fraco: #e3eef6;
    --ok: #146b52;
    --ok-fraco: #e0f0ea;
    --conferir: #96601a;
    --conferir-fraco: #f7eddc;
    --pendente: #9c3a2c;
    --pendente-fraco: #f8e6e2;
    --sombra: 0 1px 2px rgba(13,26,35,.06), 0 6px 18px rgba(13,26,35,.07);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --papel: #08131b;
      --superficie: #0e1d27;
      --superficie-2: #132532;
      --borda: #21394a;
      --tinta: #e4eef5;
      --tinta-fraca: #90a6b6;
      --azul: #57b0e4;
      --azul-fraco: #11303f;
      --ok: #56c39b;
      --ok-fraco: #0f2f27;
      --conferir: #dfab5c;
      --conferir-fraco: #33260f;
      --pendente: #e2887a;
      --pendente-fraco: #351a16;
      --sombra: 0 1px 2px rgba(0,0,0,.35), 0 8px 22px rgba(0,0,0,.35);
    }
  }
  :root[data-theme="light"] {
    --papel: #eef2f5; --superficie: #ffffff; --superficie-2: #f4f7f9; --borda: #d3dde4;
    --tinta: #0d1a23; --tinta-fraca: #55697a; --azul: #12608f; --azul-fraco: #e3eef6;
    --ok: #146b52; --ok-fraco: #e0f0ea; --conferir: #96601a; --conferir-fraco: #f7eddc;
    --pendente: #9c3a2c; --pendente-fraco: #f8e6e2;
    --sombra: 0 1px 2px rgba(13,26,35,.06), 0 6px 18px rgba(13,26,35,.07);
  }
  :root[data-theme="dark"] {
    --papel: #08131b; --superficie: #0e1d27; --superficie-2: #132532; --borda: #21394a;
    --tinta: #e4eef5; --tinta-fraca: #90a6b6; --azul: #57b0e4; --azul-fraco: #11303f;
    --ok: #56c39b; --ok-fraco: #0f2f27; --conferir: #dfab5c; --conferir-fraco: #33260f;
    --pendente: #e2887a; --pendente-fraco: #351a16;
    --sombra: 0 1px 2px rgba(0,0,0,.35), 0 8px 22px rgba(0,0,0,.35);
  }

  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--papel); color: var(--tinta);
    font-family: "Segoe UI Variable Text", "Segoe UI", system-ui, -apple-system, sans-serif;
    line-height: 1.5; overflow-x: hidden; -webkit-font-smoothing: antialiased;
  }
  .env { max-width: 1180px; margin: 0 auto; padding: 36px 20px 64px; }

  header h1 {
    font-family: "Segoe UI Variable Display", "Segoe UI Semibold", "Segoe UI", system-ui, sans-serif;
    font-size: clamp(24px, 3.4vw, 33px); font-weight: 650; letter-spacing: -.021em;
    margin: 0 0 8px; text-wrap: balance;
  }
  .sub { color: var(--tinta-fraca); max-width: 68ch; margin: 0; font-size: 15px; }
  .marca {
    display: inline-block; font-size: 11px; font-weight: 700; letter-spacing: .13em;
    text-transform: uppercase; color: var(--azul); margin-bottom: 10px;
  }

  .placar { display: grid; grid-template-columns: repeat(auto-fit, minmax(148px, 1fr)); gap: 10px; margin: 26px 0 6px; }
  .tile {
    background: var(--superficie); border: 1px solid var(--borda); border-radius: 10px;
    padding: 12px 14px; box-shadow: var(--sombra);
  }
  .tile .n {
    font-size: 26px; font-weight: 660; font-variant-numeric: tabular-nums; line-height: 1.1;
    font-family: "Segoe UI Variable Display", "Segoe UI", system-ui, sans-serif;
  }
  .tile .r { font-size: 12px; color: var(--tinta-fraca); margin-top: 2px; }
  .tile.ok .n { color: var(--ok); }
  .tile.conferir .n { color: var(--conferir); }
  .tile.pendente .n { color: var(--pendente); }

  .aviso {
    margin: 22px 0 0; padding: 14px 16px; border-radius: 10px;
    background: var(--azul-fraco); border: 1px solid color-mix(in srgb, var(--azul) 26%, transparent);
    font-size: 14px;
  }
  .aviso b { font-weight: 640; }

  .filtros { display: flex; flex-wrap: wrap; gap: 8px; margin: 26px 0 14px; }
  .chip {
    font: inherit; font-size: 13px; font-weight: 560; cursor: pointer;
    background: var(--superficie); color: var(--tinta-fraca);
    border: 1px solid var(--borda); border-radius: 999px; padding: 6px 14px;
  }
  .chip[aria-pressed="true"] { background: var(--tinta); color: var(--papel); border-color: var(--tinta); }
  .chip:focus-visible { outline: 2px solid var(--azul); outline-offset: 2px; }

  .grade { display: grid; grid-template-columns: repeat(auto-fill, minmax(232px, 1fr)); gap: 14px; }
  .cartao {
    background: var(--superficie); border: 1px solid var(--borda); border-radius: 12px;
    overflow: hidden; box-shadow: var(--sombra); display: flex; flex-direction: column;
    transition: opacity .15s ease;
  }
  .cartao.fora { display: none; }
  .cartao.rejeitado { opacity: .38; }
  .cartao.rejeitado .placa { filter: grayscale(1); }

  /* foto de produto vive sobre branco nos dois temas — é assim que o fabricante entrega */
  .placa { background: #fff; aspect-ratio: 4 / 3; display: grid; place-items: center; padding: 10px; }
  .placa img { max-width: 100%; max-height: 100%; object-fit: contain; }
  .placa.vazia { background: var(--superficie-2); color: var(--tinta-fraca); font-size: 13px; }

  .corpo { padding: 11px 13px 13px; display: flex; flex-direction: column; gap: 7px; flex: 1; }
  .nome { font-size: 13.5px; font-weight: 600; line-height: 1.32; }
  .selo {
    align-self: flex-start; font-size: 10.5px; font-weight: 700; letter-spacing: .04em;
    text-transform: uppercase; padding: 3px 8px; border-radius: 5px;
  }
  .selo.ok { background: var(--ok-fraco); color: var(--ok); }
  .selo.conferir { background: var(--conferir-fraco); color: var(--conferir); }
  .selo.pendente { background: var(--pendente-fraco); color: var(--pendente); }

  .dados {
    font-family: Consolas, "Cascadia Mono", ui-monospace, monospace;
    font-size: 11px; color: var(--tinta-fraca); line-height: 1.45;
    font-variant-numeric: tabular-nums; word-break: break-word;
  }
  .dados .rot { color: color-mix(in srgb, var(--tinta-fraca) 72%, transparent); }
  .rodape {
    margin-top: auto; padding-top: 9px; border-top: 1px solid var(--borda);
    display: flex; align-items: center; justify-content: space-between; gap: 8px;
    font-size: 12px; color: var(--tinta-fraca); font-variant-numeric: tabular-nums;
  }
  .rodape a { color: var(--azul); text-decoration: none; font-weight: 560; }
  .rodape a:hover { text-decoration: underline; }
  .rodape a:focus-visible { outline: 2px solid var(--azul); outline-offset: 2px; border-radius: 3px; }
  .estoque { font-weight: 640; color: var(--ok); }

  .btn-rej {
    font: inherit; font-size: 12px; font-weight: 560; cursor: pointer; width: 100%;
    background: var(--superficie-2); color: var(--tinta-fraca);
    border: 1px solid var(--borda); border-radius: 7px; padding: 6px;
  }
  .btn-rej:hover { color: var(--pendente); border-color: color-mix(in srgb, var(--pendente) 45%, var(--borda)); }
  .btn-rej:focus-visible { outline: 2px solid var(--azul); outline-offset: 2px; }
  .cartao.rejeitado .btn-rej { background: var(--pendente-fraco); color: var(--pendente); border-color: var(--pendente); }

  .saida {
    margin-top: 28px; background: var(--superficie); border: 1px solid var(--borda);
    border-radius: 12px; padding: 16px 18px; box-shadow: var(--sombra);
  }
  .saida h2 { font-size: 14px; margin: 0 0 6px; font-weight: 640; }
  .saida p { margin: 0 0 10px; font-size: 13px; color: var(--tinta-fraca); }
  .saida code {
    display: block; font-family: Consolas, "Cascadia Mono", ui-monospace, monospace;
    font-size: 12.5px; background: var(--superficie-2); border: 1px solid var(--borda);
    border-radius: 7px; padding: 10px 12px; overflow-x: auto; white-space: pre-wrap; word-break: break-word;
  }
  footer { margin-top: 30px; padding-top: 14px; border-top: 1px solid var(--borda);
    font-size: 12px; color: var(--tinta-fraca); }
  @media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
</style>

<div class="env">
  <header>
    <span class="marca">MarineFlow · Vendedor autônomo · Piloto Victron</span>
    <h1>${cartoes.filter((c) => c.b64).length} produtos ganharam foto oficial. Confira antes de gravar.</h1>
    <p class="sub">
      Cada foto veio do site do fabricante, casada com o modelo pelo nome. Nada foi gravado no
      catálogo ainda — esta página é só para você vetar o que estiver errado.
    </p>
  </header>

  <div class="placar">
    <div class="tile ok"><div class="n">${conta('ok')}</div><div class="r">variante casada</div></div>
    <div class="tile conferir"><div class="n">${conta('conferir')}</div><div class="r">foto da linha</div></div>
    <div class="tile pendente"><div class="n">${conta('pendente') + semFoto}</div><div class="r">sem candidato</div></div>
    <div class="tile"><div class="n">${cartoes.length}</div><div class="r">produtos nesta leva</div></div>
  </div>

  <div class="aviso">
    <b>Variante casada</b> = os números do modelo batem com o nome do arquivo oficial (o 48/5000 recebeu
    a foto do 48/5000). <b>Foto da linha</b> = não achei a variante exata, então entra a foto da família —
    é o produto certo, pode não ser a unidade exata. Preferi isso a arriscar a foto do modelo vizinho.
  </div>

  <div class="filtros">
    <button class="chip" data-f="tudo" aria-pressed="true">Tudo (${cartoes.length})</button>
    <button class="chip" data-f="ok" aria-pressed="false">Variante casada (${conta('ok')})</button>
    <button class="chip" data-f="conferir" aria-pressed="false">Foto da linha (${conta('conferir')})</button>
    <button class="chip" data-f="estoque" aria-pressed="false">Só com estoque</button>
  </div>

  <div class="grade">
${cartoes
  .map((c) => {
    const nome = escapar(c.name.replace(' - Victron Energy', ''));
    const temEstoque = Number(c.estoque) > 0;
    return `    <article class="cartao" data-nivel="${c.nivel.classe}" data-estoque="${temEstoque ? 1 : 0}" data-chave="${escapar(c.chave)}">
      <div class="placa${c.b64 ? '' : ' vazia'}">${
        c.b64
          ? `<img src="data:image/jpeg;base64,${c.b64}" alt="${nome}" loading="lazy">`
          : 'sem foto candidata'
      }</div>
      <div class="corpo">
        <span class="selo ${c.nivel.classe}">${c.nivel.rotulo}</span>
        <div class="nome">${nome}</div>
        <div class="dados">
          <span class="rot">SKU</span> ${escapar(c.sku || '—')}<br>
          <span class="rot">arquivo</span> ${escapar((c.arquivo || c.motivo || '—').slice(0, 70))}
        </div>
        <div class="rodape">
          <span>${temEstoque ? `<span class="estoque">${c.estoque} em estoque</span>` : dinheiro(c.preco)}</span>
          ${c.pagina ? `<a href="${escapar(c.pagina)}" target="_blank" rel="noopener">página oficial ↗</a>` : ''}
        </div>
        <button class="btn-rej" type="button">Rejeitar esta foto</button>
      </div>
    </article>`;
  })
  .join('\n')}
  </div>

  <section class="saida">
    <h2>Rejeitadas</h2>
    <p>Marque acima o que estiver errado e me mande esta linha — eu refaço só essas.</p>
    <code id="lista">nenhuma rejeitada</code>
  </section>

  <footer>
    Fotos: catálogo público da Victron Energy (sitemap oficial), normalizadas para 1200px sobre fundo
    branco. Origem de cada arquivo registrada no casamento — dá para refazer a qualquer momento.
  </footer>
</div>

<script>
  var grade = document.querySelector('.grade');
  var lista = document.getElementById('lista');
  var rejeitadas = [];

  document.querySelectorAll('.chip').forEach(function (chip) {
    chip.addEventListener('click', function () {
      document.querySelectorAll('.chip').forEach(function (c) { c.setAttribute('aria-pressed', 'false'); });
      chip.setAttribute('aria-pressed', 'true');
      var f = chip.dataset.f;
      document.querySelectorAll('.cartao').forEach(function (card) {
        var mostrar =
          f === 'tudo' ||
          (f === 'estoque' && card.dataset.estoque === '1') ||
          card.dataset.nivel === f;
        card.classList.toggle('fora', !mostrar);
      });
    });
  });

  grade.addEventListener('click', function (ev) {
    var botao = ev.target.closest('.btn-rej');
    if (!botao) return;
    var card = botao.closest('.cartao');
    var chave = card.dataset.chave;
    var i = rejeitadas.indexOf(chave);
    if (i === -1) { rejeitadas.push(chave); } else { rejeitadas.splice(i, 1); }
    card.classList.toggle('rejeitado', i === -1);
    botao.textContent = i === -1 ? 'Rejeitada — desfazer' : 'Rejeitar esta foto';
    lista.textContent = rejeitadas.length ? 'rejeitar: ' + rejeitadas.join(', ') : 'nenhuma rejeitada';
  });
</script>
`;

const destino = path.join(dados, 'conferencia.html');
fs.writeFileSync(destino, html);
console.log(`cartões: ${cartoes.length} (ok ${conta('ok')} · conferir ${conta('conferir')} · pendente ${conta('pendente') + semFoto})`);
console.log(`tamanho: ${(Buffer.byteLength(html) / 1024 / 1024).toFixed(2)} MB`);
console.log('->', destino);
