// Passo 2 — casa cada produto do ERP com uma página oficial Victron e escolhe a
// melhor foto daquela página.
//
//   node scripts/catalogo-fotos/2-casar.mjs [pastaDeDados]
//
// Entradas:  <dados>/victron-catalogo.json  (passo 1)
//            <dados>/produtos.json          (export do ERP: sku, name, estoque, preco)
// Saída:     <dados>/casamento.json
//
// O casamento é determinístico e auditável: a família sai de uma tabela de
// regras (victron-regras.json) e a variante sai do confronto entre os números do
// nosso nome (12/3000/120-32) e os do nome do arquivo oficial
// (`...Multiplus-II 12V 3kVA_120-32 230V (front).png`). Nada é adivinhado por
// semelhança difusa — o que não casa sai marcado como pendente para revisão.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const dados = process.argv[2] || path.join(process.cwd(), '.catalogo-fotos');

const catalogo = JSON.parse(fs.readFileSync(path.join(dados, 'victron-catalogo.json'), 'utf8'));
const produtos = JSON.parse(fs.readFileSync(path.join(dados, 'produtos.json'), 'utf8'));
const { regras } = JSON.parse(fs.readFileSync(path.join(aqui, 'victron-regras.json'), 'utf8'));

const porSlug = new Map(catalogo.map((c) => [c.slug, c]));

/** minúsculas, sem acento, separadores normalizados */
const decodificar = (s) => {
  try {
    return decodeURIComponent(s);
  } catch {
    return s; // nome de arquivo com % solto
  }
};

const normalizar = (s) =>
  decodificar(s)
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

/**
 * Números que identificam a variante. Converte kVA em VA (3kva -> 3000) e trata
 * 220V e 230V como a mesma coisa (o nome brasileiro diz 220, o oficial diz 230).
 */
function especificacoes(texto) {
  const t = normalizar(texto)
    // ruído que não descreve a variante: part number (PMP122305010), carimbo do
    // CMS (20180706100526), resolução (300dpi), polegadas da tela
    .replace(/\b[a-z]{2,5}\d{5,}[a-z0-9]*\b/g, ' ')
    .replace(/\b\d{6,}\b/g, ' ')
    .replace(/\d+\s*dpi\b/g, ' ')
    .replace(/\bip\s*\d+/g, ' ')
    .replace(/\b2x\s*/g, ' ') // "2x120V" é a mesma tensão, não um número de variante
    // kVA -> VA para comparar com "3000" do nosso nome
    .replace(/(\d+)[.,](\d+)\s*kva/g, (_, a, b) => String(Number(`${a}.${b}`) * 1000))
    .replace(/(\d+)\s*kva/g, (_, a) => String(Number(a) * 1000))
    .replace(/(\d+)\s*va\b/g, '$1')
    // "12,8v" -> 128 atrapalha; vira 12
    .replace(/(\d+)[.,]\d+\s*v\b/g, '$1');
  const nums = [...t.matchAll(/\d+/g)].map((m) => Number(m[0])).filter((n) => n > 0 && n < 100000);
  // 220V (nome brasileiro) e 230V (nome oficial) são a mesma máquina
  return new Set(nums.map((n) => (n === 220 || n === 230 ? 230 : n)));
}

/** É a foto-herói da família (a que a Victron usa no topo da página)? */
const ehHeroi = (url) => /\/upload\/products\//.test(url);

/** Penaliza ângulos que não servem de vitrine; premia a foto frontal/hero. */
function pontuarAngulo(arquivo) {
  const a = normalizar(arquivo);
  let p = 0;
  if (/\(front\)|_front|frontal/.test(a)) p += 6;
  if (/_nw\.|_nw@|\/upload\/products\//.test(a)) p += 4; // imagem-herói da família
  if (/\(connection|conexao|wiring/.test(a)) p -= 8;
  if (/\((bottom|rear|back|left|right|top|side|inside|open)\)/.test(a)) p -= 6;
  if (/dimension|drawing|desenho|dwg|scale/.test(a)) p -= 10;
  if (/logo|icon|banner|award|badge/.test(a)) p -= 10;
  return p;
}

const resultado = [];

for (const prod of produtos) {
  const nome = normalizar(prod.name);
  const regra = regras.find((r) => new RegExp(r.padrao, 'i').test(nome));

  if (!regra) {
    resultado.push({ ...prod, status: 'sem-regra', motivo: 'nenhuma regra de família casou' });
    continue;
  }
  const pagina = porSlug.get(regra.slug);
  if (!pagina) {
    resultado.push({
      ...prod,
      status: 'pagina-ausente',
      slug: regra.slug,
      motivo: `slug "${regra.slug}" não existe no sitemap`,
    });
    continue;
  }
  if (!pagina.imagens.length) {
    resultado.push({
      ...prod,
      status: 'sem-imagem',
      slug: regra.slug,
      pagina: pagina.url,
      motivo: 'página sem imagem no sitemap',
    });
    continue;
  }

  const especProduto = especificacoes(prod.name);
  const candidatos = pagina.imagens
    .map((url) => {
      const arquivo = decodificar(url.split('/').pop() || url);
      const especArquivo = especificacoes(arquivo);
      const casados = [...especProduto].filter((n) => especArquivo.has(n));
      // Conflito = número que define variante e aparece só de um lado. É o que
      // separa "a foto certa" da "foto do irmão de 12V": sem isto, o 48/5000
      // casava com a imagem do 24/5000 só porque ambos têm 5000 e 230.
      const faltando = [...especProduto].filter((n) => !especArquivo.has(n));
      const sobrando = [...especArquivo].filter((n) => !especProduto.has(n));
      return {
        url,
        arquivo,
        casados,
        faltando,
        sobrando,
        // "sobrando" pesa: número no arquivo que não temos = é OUTRA variante.
        // "faltando" quase não pesa: o nome oficial costuma ser mais curto que o
        // nosso (o arquivo diz "24V 3kVA", nós dizemos "24/3000/70-32 220V").
        pontos:
          casados.length * 5 - sobrando.length * 4 - faltando.length + pontuarAngulo(url),
      };
    })
    .sort((a, b) => b.pontos - a.pontos || a.arquivo.length - b.arquivo.length);

  const melhor = candidatos[0];
  // Variante confirmada = nenhum número do arquivo contradiz o nosso nome.
  const exata = melhor.casados.length >= 2 && !melhor.sobrando.length;

  if (exata) {
    resultado.push({
      ...prod,
      status: 'candidato',
      nivel: melhor.faltando.length ? 'variante' : 'variante-exata',
      slug: regra.slug,
      pagina: pagina.url,
      conf_familia: regra.conf,
      imagem: melhor.url,
      arquivo: melhor.arquivo,
      numeros_casados: melhor.casados,
      alternativas: candidatos.slice(1, 4).map((c) => ({ url: c.url, arquivo: c.arquivo })),
    });
    continue;
  }

  // Sem variante exata: a foto-herói da família é honesta (é a linha certa do
  // produto), enquanto a foto de OUTRA variante seria enganosa. Preferimos a
  // herói e marcamos para conferência humana.
  const heroi = candidatos.filter((c) => ehHeroi(c.url)).sort((a, b) => b.pontos - a.pontos)[0];
  const escolhida = heroi || melhor;

  resultado.push({
    ...prod,
    status: 'candidato',
    nivel: heroi ? 'familia' : 'aproximada',
    slug: regra.slug,
    pagina: pagina.url,
    conf_familia: regra.conf,
    imagem: escolhida.url,
    arquivo: escolhida.arquivo,
    numeros_casados: escolhida.casados,
    numeros_conflitantes: { faltando: escolhida.faltando, sobrando: escolhida.sobrando },
    alternativas: candidatos
      .filter((c) => c.url !== escolhida.url)
      .slice(0, 3)
      .map((c) => ({ url: c.url, arquivo: c.arquivo })),
  });
}

fs.writeFileSync(path.join(dados, 'casamento.json'), JSON.stringify(resultado, null, 2));

const conta = (f) => resultado.filter(f).length;
console.log(`produtos: ${resultado.length}`);
console.log(`  com candidato: ${conta((r) => r.status === 'candidato')}`);
console.log(`    variante exata (0 conflitos):  ${conta((r) => r.nivel === 'variante-exata')}`);
console.log(`    variante provável:            ${conta((r) => r.nivel === 'variante')}`);
console.log(`    foto da família (conferir):    ${conta((r) => r.nivel === 'familia')}`);
console.log(`    aproximada (conferir):         ${conta((r) => r.nivel === 'aproximada')}`);
console.log(`  sem regra:      ${conta((r) => r.status === 'sem-regra')}`);
console.log(`  página ausente: ${conta((r) => r.status === 'pagina-ausente')}`);
console.log(`  sem imagem:     ${conta((r) => r.status === 'sem-imagem')}`);
console.log('->', path.join(dados, 'casamento.json'));
