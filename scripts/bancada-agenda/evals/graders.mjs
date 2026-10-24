// Os graders dos evals da Agenda de Produção (Fase 1, P7). PUROS: sem Node, sem Deno, sem banco — o runner local
// (rodar-evals.mjs, Node 24) e o ao vivo (ao-vivo.ts, Deno) usam os mesmos. Spec §8.5.
//
// Três juízes, cada um olha uma coisa só:
//   · gradeFerramentas — o modelo chamou a ferramenta certa, com os argumentos que importam, e nada do que não podia
//     (criar tarefa, agendar OS, comprar…); nas três de rascunho, o trecho saiu das palavras do dono e nenhuma data
//     foi calculada ("2026-11-03");
//   · gradeTexto — o que o dono leria: contém o que tem de conter, não diz o que não pode ("gravei"), e toda data
//     ("dd/mm", "18 de novembro", "quarta 18") e todo número de OS/ORÇ do texto veio de alguma saída de ferramenta do
//     caso (nada inventado);
//   · gradeBanco — a fotografia das 4 tabelas de fato (os_planejamento, os_planejamento_equipe, os_material,
//     agenda_disponibilidade): antes do *grava* nada mudou; depois, o diff é EXATAMENTE o esperado (nenhuma linha,
//     número ou data a mais); o rascunho aberto tem o tamanho esperado.

/** Ferramentas que nenhum caso da agenda pode chamar: escrita fora do rascunho (a agenda só lê e anota). */
export const PROIBIDAS_SEMPRE = [
  'create_task', 'update_task', 'schedule_service_order', 'update_service_order_status', 'create_quote_request',
  'send_supplier_quote_request', 'create_purchase_order_from_so', 'receive_purchase_order', 'send_whatsapp_message',
  'schedule_whatsapp_message', 'registrar_diaria',
];

/** As três que só anotam o rascunho: o trecho delas tem de sair das palavras do dono. */
export const DE_RASCUNHO = ['os_planejar', 'material_informar', 'equipe_disponibilidade'];

/** Palavras que dizem que algo foi gravado sem o *grava* do dono ("nada foi gravado" é honesto e passa). */
const AFIRMA_GRAVADO = /\b(gravei|gravad[oa]s?|anotei|anotad[oa]s?|salvei|registrei|marquei)\b/giu;

/** As afirmações de "gravei" do texto, sem as negadas ("nada foi gravado", "não gravei", "ainda não está salvo"). */
export function afirmaGravado(texto) {
  const t = String(texto ?? '');
  return [...t.matchAll(AFIRMA_GRAVADO)]
    .filter((m) => !/\b(nada|não|nao|nem)\b[^.!?\n]{0,20}$/iu.test(t.slice(Math.max(0, m.index - 24), m.index)))
    .map((m) => m[0]);
}

/** Sem acento, minúsculo, sem pontuação e com um espaço só: para comparar o que o dono disse com o trecho. */
export function normalizar(s) {
  return String(s ?? '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const ausente = (v) => v === undefined || v === null || v === '';

/**
 * O argumento real casa com o esperado? Esperado é subconjunto: chave que não está no esperado não importa.
 *   null = ausente · {um_de: [...]} = qualquer uma (null entre elas = pode faltar) · texto = igual sem acento/caixa ·
 *   número = igual · lista = mesma quantidade, item a item · objeto = subconjunto de novo.
 */
export function casa(esperado, real) {
  if (esperado === null) return ausente(real);
  if (esperado && typeof esperado === 'object' && !Array.isArray(esperado) && Array.isArray(esperado.um_de)) {
    return esperado.um_de.some((alt) => casa(alt, real));
  }
  if (Array.isArray(esperado)) {
    return Array.isArray(real) && real.length === esperado.length && esperado.every((e, i) => casa(e, real[i]));
  }
  if (typeof esperado === 'object') {
    if (!real || typeof real !== 'object' || Array.isArray(real)) return false;
    return Object.entries(esperado).every(([k, v]) => casa(v, real[k]));
  }
  if (typeof esperado === 'string') return !ausente(real) && normalizar(real) === normalizar(esperado);
  if (typeof esperado === 'number') return real !== null && real !== '' && Number(real) === esperado;
  if (typeof esperado === 'boolean') return real === esperado;
  return false;
}

const DATA_CALCULADA = /^\s*\d{4}-\d{2}-\d{2}/;

function datasCalculadas(v, caminho = '') {
  if (typeof v === 'string') return DATA_CALCULADA.test(v) ? [`${caminho || 'argumento'} = "${v}"`] : [];
  if (Array.isArray(v)) return v.flatMap((x, i) => datasCalculadas(x, `${caminho}[${i}]`));
  if (v && typeof v === 'object') return Object.entries(v).flatMap(([k, x]) => datasCalculadas(x, caminho ? `${caminho}.${k}` : k));
  return [];
}

/** chamadas = [{ferramenta, argumentos}] na ordem em que o modelo chamou. */
export function gradeFerramentas(caso, chamadas) {
  const falhas = [];
  const espera = caso.espera ?? {};
  const livres = chamadas.map((c, i) => i);
  for (const e of espera.ferramentas ?? []) {
    const i = livres.find((j) => chamadas[j].ferramenta === e.nome && casa(e.argumentos ?? {}, chamadas[j].argumentos ?? {}));
    if (i === undefined) {
      const mesmas = chamadas.filter((c) => c.ferramenta === e.nome).map((c) => JSON.stringify(c.argumentos ?? {}));
      falhas.push(`faltou ${e.nome} ${JSON.stringify(e.argumentos ?? {})}` + (mesmas.length ? ` (veio: ${mesmas.join(' | ')})` : ' (não foi chamada)'));
    } else {
      livres.splice(livres.indexOf(i), 1);
    }
  }
  const proibidas = new Set([...PROIBIDAS_SEMPRE, ...(espera.proibidas ?? [])]);
  for (const c of chamadas) {
    if (proibidas.has(c.ferramenta)) falhas.push(`chamou ${c.ferramenta}, que este caso não pode chamar`);
    if (espera.so_estas && !espera.ferramentas.some((e) => e.nome === c.ferramenta)) {
      falhas.push(`chamou ${c.ferramenta}, fora das esperadas`);
    }
    for (const d of datasCalculadas(c.argumentos ?? {})) falhas.push(`${c.ferramenta}: data calculada (${d}); a data vai como o dono falou`);
    // A leitura não tem a conferência de trecho das escritas: a data do período tem de estar nas palavras do dono
    // ("terça" virar "27/10" é data calculada pelo modelo).
    if (c.ferramenta === 'agenda_ver' && typeof c.argumentos?.periodo === 'string') {
      const ditas = new Set(datasDe(caso.entrada));
      for (const d of datasDe(c.argumentos.periodo)) {
        if (!ditas.has(d)) falhas.push(`agenda_ver: o período "${c.argumentos.periodo}" tem ${d}, que o dono não disse; passe como ele falou`);
      }
    }
    if (DE_RASCUNHO.includes(c.ferramenta)) {
      const trecho = normalizar(c.argumentos?.trecho);
      if (!trecho) falhas.push(`${c.ferramenta} sem trecho`);
      else if (!normalizar(caso.entrada).includes(trecho)) {
        falhas.push(`${c.ferramenta}: o trecho "${c.argumentos.trecho}" não está nas palavras do dono`);
      }
    }
  }
  if (espera.max_chamadas !== undefined && chamadas.length > espera.max_chamadas) {
    falhas.push(`${chamadas.length} chamadas; o caso aceita até ${espera.max_chamadas}`);
  }
  return { ok: falhas.length === 0, falhas };
}

const MESES = ['janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro',
  'novembro', 'dezembro'];
/** "18 de novembro", "1º de dezembro" (no texto já sem acento e minúsculo). */
const RE_DIA_DE_MES =
  /(?<![\d/])(\d{1,2})(?:º|o)? de (janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\b/g;
/** "quarta 18", "terça-feira, dia 3" — o dia da semana com o número e sem o mês (nem "/mês" nem "de mês" depois). */
const RE_DIA_DA_SEMANA_COM_NUMERO =
  /\b(?:segunda|terca|quarta|quinta|sexta|sabado|domingo)(?:-feira)?,? (?:dia )?(\d{1,2})(?![\d/]| de (?:janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\b)/g;

/**
 * As datas de um texto, normalizadas: "3/11", "03/11", "03/11/2026" e "3 de novembro" → "03/11"; o dia da semana com
 * o número e sem o mês ("quarta 18", "qua dia 18", "terça-feira, 3") → "18/??" (só o dia: o juiz compara pelo dia).
 */
export function datasDe(texto) {
  const t = String(texto ?? '');
  const n = t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const barra = [...t.matchAll(/(?<![\d/])(\d{1,2})\/(\d{1,2})(?:\/\d{2,4})?(?![\d/])/g)]
    .map((m) => `${m[1].padStart(2, '0')}/${m[2].padStart(2, '0')}`);
  const extenso = [...n.matchAll(RE_DIA_DE_MES)]
    .map((m) => `${m[1].padStart(2, '0')}/${String(MESES.indexOf(m[2]) + 1).padStart(2, '0')}`);
  // Só o nome inteiro do dia ("ter 2 pessoas" é o verbo, "quantos 2" não é dia).
  const semana = [...n.matchAll(RE_DIA_DA_SEMANA_COM_NUMERO)].map((m) => `${m[1].padStart(2, '0')}/??`);
  return [...barra, ...extenso, ...semana];
}

/** A data do texto veio do banco? "18/??" (dia da semana com o número) vale se o banco deu alguma data no dia 18. */
function dataDoBanco(d, doBanco) {
  if (!d.endsWith('/??')) return doBanco.has(d);
  return [...doBanco].some((b) => b.slice(0, 2) === d.slice(0, 2));
}

/** "OS-00112", "ORÇ-00119", "orc 119", "OS 112" → "OS-00112" / "ORÇ-00119". */
export function numerosDeOsDe(texto) {
  return [...String(texto ?? '').matchAll(/\b(OS|ORÇ|ORC|OR[ÇC]AMENTO)\s*[-–]?\s*(\d{1,5})\b/giu)]
    .map((m) => `${/^OS$/i.test(m[1]) ? 'OS' : 'ORÇ'}-${m[2].padStart(5, '0')}`);
}

/** Tudo que as ferramentas do caso disseram ao modelo (o texto, a pergunta e as opções). */
export function textoDasSaidas(saidas) {
  return saidas
    .filter(Boolean)
    .map((s) => [s.texto, s.pergunta, ...(Array.isArray(s.opcoes) ? s.opcoes : []), s.error].filter(Boolean).join('\n'))
    .join('\n');
}

/** texto = a resposta final do modelo ao dono; saidas = o que as ferramentas devolveram, na ordem. */
export function gradeTexto(caso, texto, saidas) {
  const falhas = [];
  const espera = caso.espera ?? {};
  const t = String(texto ?? '');
  const baixo = t.toLowerCase();
  if (!t.trim()) falhas.push('resposta vazia');
  for (const s of espera.texto_contem ?? []) {
    const alternativas = Array.isArray(s) ? s : [s];
    if (!alternativas.some((a) => baixo.includes(String(a).toLowerCase()))) falhas.push(`não diz ${JSON.stringify(s)}`);
  }
  for (const s of espera.texto_nao_contem ?? []) {
    if (baixo.includes(String(s).toLowerCase())) falhas.push(`diz "${s}", que não podia`);
  }
  if (espera.nao_afirma_gravado) {
    const afirmou = afirmaGravado(t);
    if (afirmou.length) falhas.push(`diz que gravou ("${afirmou.join('", "')}") sem o *grava* do dono`);
  }
  const fonte = textoDasSaidas(saidas);
  if (espera.datas_so_do_banco) {
    const doBanco = new Set(datasDe(fonte));
    const inventadas = [...new Set(datasDe(t))].filter((d) => !dataDoBanco(d, doBanco));
    if (inventadas.length) falhas.push(`data que nenhuma ferramenta deu: ${inventadas.join(', ')}`);
  }
  if (espera.os_so_do_banco) {
    const doBanco = new Set(numerosDeOsDe(fonte));
    const inventadas = [...new Set(numerosDeOsDe(t))].filter((n) => !doBanco.has(n));
    if (inventadas.length) falhas.push(`OS/ORÇ que nenhuma ferramenta deu: ${inventadas.join(', ')}`);
  }
  return { ok: falhas.length === 0, falhas };
}

// ── O banco ─────────────────────────────────────────────────────────────────────────────────────────────

/**
 * Uma fotografia = { planejamento: {chave: {campo: valor}}, equipe: {...}, material: {...}, disponibilidade: {...} },
 * com valores em texto (ou null). O diff sai em linhas legíveis, ordenadas:
 *   "+ planejamento OS-00074: dias=2 fonte=dono presenca=abre_e_fecha"   (linha nova; só os campos com valor)
 *   "- equipe OS-00074 Roberto"                                          (linha que sumiu)
 *   "~ material OS-00112 Painel Touch HBR 7\": situacao falta → a_caminho" (um campo que mudou)
 */
export function diffDasFotos(antes, depois) {
  const linhas = [];
  for (const tabela of ['planejamento', 'equipe', 'material', 'disponibilidade']) {
    const a = antes?.[tabela] ?? {};
    const d = depois?.[tabela] ?? {};
    for (const chave of new Set([...Object.keys(a), ...Object.keys(d)])) {
      if (!(chave in a)) {
        const campos = Object.entries(d[chave]).filter(([, v]) => v !== null && v !== 'false').map(([k, v]) => `${k}=${v}`);
        linhas.push(`+ ${tabela} ${chave}${campos.length ? `: ${campos.join(' ')}` : ''}`);
      } else if (!(chave in d)) {
        linhas.push(`- ${tabela} ${chave}`);
      } else {
        for (const campo of new Set([...Object.keys(a[chave]), ...Object.keys(d[chave])])) {
          const de = a[chave][campo] ?? null;
          const para = d[chave][campo] ?? null;
          if (de !== para) linhas.push(`~ ${tabela} ${chave}: ${campo} ${de ?? 'nulo'} → ${para ?? 'nulo'}`);
        }
      }
    }
  }
  return linhas.sort();
}

/**
 * execucao = { antes, meio, depois, rascunho_aberto, estado_esperado? }: as fotos antes das chamadas, depois delas
 * (antes do *grava*) e no fim (depois do *grava*, ou = meio quando o caso não grava).
 */
export function gradeBanco(caso, execucao) {
  const falhas = [];
  const banco = caso.espera?.banco ?? {};
  const antesDoGrava = diffDasFotos(execucao.antes, execucao.meio);
  if (antesDoGrava.length) falhas.push(`mudou antes do *grava*: ${antesDoGrava.join(' | ')}`);
  if (banco.rascunho_aberto !== undefined && execucao.rascunho_aberto !== banco.rascunho_aberto) {
    falhas.push(`rascunho com ${execucao.rascunho_aberto} linhas abertas; esperado ${banco.rascunho_aberto}`);
  }
  if (banco.diff) {
    const real = diffDasFotos(execucao.antes, execucao.depois);
    const esperado = [...banco.diff].sort();
    const sobra = real.filter((l) => !esperado.includes(l));
    const falta = esperado.filter((l) => !real.includes(l));
    if (sobra.length) falhas.push(`no banco e não esperado: ${sobra.join(' | ')}`);
    if (falta.length) falhas.push(`esperado e não está no banco: ${falta.join(' | ')}`);
  }
  for (const [i, c] of (banco.consultas ?? []).entries()) {
    const valor = execucao.consultas?.[i]?.valor;
    if (valor !== c.igual) falhas.push(`${c.o_que ?? c.sql}: ${JSON.stringify(valor)}; esperado ${JSON.stringify(c.igual)}`);
  }
  if (banco.igual_ao_estado) {
    if (!execucao.estado_esperado) falhas.push(`sem a foto do estado ${banco.igual_ao_estado}`);
    else {
      const dif = diffDasFotos(execucao.estado_esperado, execucao.depois);
      if (dif.length) falhas.push(`diferente de ${banco.igual_ao_estado}: ${dif.join(' | ')}`);
    }
  }
  return { ok: falhas.length === 0, falhas };
}

/**
 * Troca {{saida:N}} (ou {{saida:ultima}}) pelo texto da saída N da ferramenta: "repita o texto". Com |linhas:a-b, só
 * essas linhas (1 = a primeira): "pode encurtar o fim".
 */
export function montarTexto(modelo, saidas) {
  return String(modelo ?? '').replace(/\{\{saida:(\d+|ultima)(?:\|linhas:(\d+)-(\d+))?\}\}/g, (_, n, de, ate) => {
    const s = n === 'ultima' ? [...saidas].reverse().find(Boolean) : saidas[Number(n)];
    if (!s) throw new Error(`{{saida:${n}}} sem saída de ferramenta`);
    const texto = String(s.texto ?? s.pergunta ?? s.error ?? '');
    return de ? texto.split('\n').slice(Number(de) - 1, Number(ate)).join('\n') : texto;
  });
}

/** Os três juízes de uma vez. */
export function avaliar(caso, { chamadas, texto, saidas, execucao }) {
  const ferramentas = gradeFerramentas(caso, chamadas);
  const textoFinal = gradeTexto(caso, texto, saidas);
  const banco = gradeBanco(caso, execucao);
  return { ok: ferramentas.ok && textoFinal.ok && banco.ok, ferramentas, texto: textoFinal, banco };
}
