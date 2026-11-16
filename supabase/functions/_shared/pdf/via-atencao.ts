// O quadro "Atenção" da via do técnico: uma linha curta por risco grave (porte da via v2, F1, 16/11/2026).
//
// No lugar das páginas de "Segurança por sistema" (passos genéricos), a via aprovada pelo dono (base "limpa", 14/11;
// textos aprovados em 15/11, resposta 5) traz um quadro com 1 linha por energia que o serviço toca: 127/220 V, gás,
// combustível, fluido refrigerante, altura (teto do motorhome ou arco/mastro do barco), peça que se move, motor
// funcionando, 12/24 V (ou bateria de lítio), casco, furar ou cortar, resina ou esmerilhadeira — e o volante (airbag).
//
// A DETECÇÃO das energias é a da bancada (proposta/via-v2.ts, analisarEnergias, conferida em 61 + 3 vias reais),
// copiada sem mudar regra: o sistema de cada linha (o gravado na linha ou, na falta, o do cadastro do serviço —
// decisão 3A do dono: o sistema adivinhado pelo texto não conta), palavras inteiras no nome, nas notas, no trecho do
// pedido que é daquele serviço, no pedido da OS e no nome do material; mais o cadastro do veículo (inversor, energia
// de terra) quando o serviço mexe no sistema de energia. Linha sem sistema e sem palavra nenhuma entra como 12/24 V
// (na dúvida, inclui). Da bancada, o quadro só usa o CONJUNTO de energias e três sinais: barco (altura vira arco/
// mastro), lítio (o rótulo do 12/24 V) e volante/airbag (linha extra).
//
// Na via de uma pessoa, só as linhas dela (e as sem responsável) contam; o pedido da OS só entra quando ela tem todos
// os serviços. A linha de cobrança (frete, deslocamento, insumos) sai dos cartões, mas CONTA aqui (como na bancada).
// A Instrução por serviço não entra: aprovar uma instrução não muda o quadro.
//
// Puro (sem Deno, sem rede): a tela importa por src/lib/route-sheet.ts (Vite) e as edge functions pelo Deno.

import { camposDoTipo } from '../unidade.ts';
import { limparPedido, normalizar, tituloDoServico } from './via-texto.ts';

export type Energia =
  | 'dc' | 'ac' | 'gas' | 'combustivel' | 'refrigerante' | 'motor' | 'altura' | 'casco' | 'furo' | 'mecanico' | 'quimico';

/** O mínimo da via que o quadro lê (o DadosDaVia de via-do-tecnico.ts cabe aqui). */
export interface EntradaDaAtencao {
  header: {
    problemDescription?: string | null;
    assetType?: string | null;
    vehicleElectrical?: { inverterCharger?: string | null; shorePower?: string | null } | null;
  };
  linhas: Array<{
    id: string;
    name_snapshot?: string | null;
    services?: { name?: string | null; service_system?: string | null } | null;
    service_system?: string | null;
    notes?: string | null;
    responsavel_payee_id?: string | null;
  }>;
  materiais?: Array<{ service_order_service_id: string | null; products?: { name?: string | null } | null }> | null;
}

type Linha = EntradaDaAtencao['linhas'][number];

/** Rótulo curto de cada energia (a bancada: a linha "Cuidado" e o rótulo do grupo da pausa). */
export const CURTO: Record<Energia, string> = {
  dc: '12/24 V', ac: '127/220 V', gas: 'gás', combustivel: 'combustível', refrigerante: 'fluido refrigerante',
  motor: 'motor funcionando', altura: 'teto', casco: 'casco', furo: 'furar ou cortar', mecanico: 'peça que se move',
  quimico: 'resina ou esmerilhadeira',
};

/** Sistema do banco (linha ou cadastro do serviço) → energia. Hidráulico não leva nenhuma; estrutural é "furar ou cortar". */
export const SISTEMA_ENERGIA: Record<string, Energia | null> = {
  eletrico_dc: 'dc', eletronico: 'dc', refrigeracao: 'dc', eletrico_ac: 'ac', gas: 'gas',
  mecanico: 'mecanico', estrutural: 'furo', hidraulico: null, iluminacao: 'dc', nenhum: null,
};

/** Palavras inteiras (sem acento, minúsculas). Viés para INCLUIR. */
export const PALAVRAS: Array<{ energia: Energia; re: RegExp }> = [
  { energia: 'ac', re: /\b(?:110|120|127|220|230)\s?v\b|\b(?:110|120|127|220)\/(?:110|120|127|220)\b|\b\d+(?:[.,]\d+)?\s?k?va\b|\btomadas?\b(?!\s+(?:usb|12\s?v|de 12))|\bcais\b|\benergia de terra\b|\btomada externa\b|\benergia externa\b|\binversor(?:es)?\b|\bgerador(?:es)?\b|\bar[- ]condicionados?\b|\bautotransformador\b|\bestabilizador(?:es)?\b|\bcorrente alternada\b|\bshore\b|\bmultiplus\b|\btechnomaster\b|\btm41\b|\btmi\d*\b|\bats\b|\btransferencia automatica\b|\bchave de transferencia\b|\bfontes? carregador(?:a|as|es)?\b|\bcarregador(?:es)? de baterias?\b/ },
  // "Conversão … para 12 V" / "transformar … em 12V": o que existe hoje é da rede (o plafon, a geladeira).
  { energia: 'ac', re: /\bconvers(?:ao|oes)\b[^.;]{0,90}\bpara (?:led )?12\s?v\b|\btransformar\b[^.;]{0,60}\bem 12\s?v\b/ },
  // "quadro" sem 12 V/CC perto é o quadro da rede; "alimentação (elétrica) externa" é a entrada de 220 V. Cooktop (não a
  // gás), fogão/placa de indução, micro-ondas e secador de cabelo são aparelhos de 127/220 V.
  { energia: 'ac', re: /\bquadros?\b(?!\s+(?:decorativ|de bicicleta|do chassi))(?![^.;\n]{0,30}?(?:\b(?:12|24)\s?v\b|\b12\/24\b|\bcc\b|\bdc\b|\bcorrente continua\b))|\balimentacao (?:eletrica )?externa\b|\bcooktops?\b(?![^.;\n]{0,25}?\b(?:gas|glp)\b)|\b(?:fogao|fogoes|placa|chapa)\s+(?:de\s+|por\s+|a\s+)?inducao\b|\bmicro[- ]?ondas\b|\bsecador(?:es)? de cabelo\b/ },
  { energia: 'gas', re: /\bgas\b|\bglp\b|\bbotij(?:ao|oes)\b|\bfog(?:ao|oes)\b|\bchurrasqueira\b|\bpropano\b|\bbutano\b|\bforno\b/ },
  // Motor de popa (lancha) é motor a gasolina.
  { energia: 'combustivel', re: /\bdiesel\b|\bgasolina\b|\bcombustive(?:l|is)\b|\btanques?\b|\bgerador(?:es)?\b|\bwebasto\b|\baquecedor estacionario\b|\bmotor(?:es)? de popa\b/ },
  { energia: 'refrigerante', re: /\bfluido refrigerante\b|\brefrigerante\b|\bfiltro secador\b|\bvacuo\b|\bbrasagem\b|\bmacarico\b|\bnitrogenio\b|\bcarga de gas\b|\brecarga de gas\b/ },
  { energia: 'altura', re: /\btetos?\b|\bantenas?\b|\bstarlink\b|\bclaraboias?\b|\bplacas? solar(?:es)?\b|\bpaineis solares\b|\bpainel solar\b|\bmodulos? solar(?:es)?\b|\bar[- ]condicionado de teto\b|\bradar(?:es)?\b|\bhardtop\b|\bmastros?\b|\barco do radar\b|\btoldos?\b/ },
  { energia: 'casco', re: /\bcasco\b|\bpassantes?\b|\btransdutor(?:es)?\b|\blinha d.?agua\b/ },
  // "refixação" é a mesma "fixação".
  { energia: 'furo', re: /\bfur(?:ar|o|os|acao|ado|ados)\b|\brecortes?\b|\bcortar\b|\bchapas?\b|\bchapa-piso\b|\bpiso\b|\bassoalho\b|\bparedes?\b|\bmoveis\b|\bmovel\b|\bmarcenaria\b|\bpassa-?cabos?\b|\bsuportes?\b|\b(?:re)?fixacao\b|\brefixar\b|\besmerilhadeira\b|\bclaraboias?\b/ },
  { energia: 'mecanico', re: /\bslides?\b|\bslide-out\b|\btoldos?\b|\bsapatas?\b|\bguincho\b|\bplataformas?\b|\bcremalheiras?\b|\bescada retratil\b|\bmacaco\b|\bmolas?\b/ },
  // Tinta, pintura, spray e cola de contato (Cascola é cola de contato) também são vapor de solvente.
  { energia: 'quimico', re: /\bresina\b|\bgelcoat\b|\blaminacao\b|\bfibra de vidro\b|\besmerilhadeira\b|\blixadeira\b|\bsolvente\b|\bthinner\b|\btintas?\b|\bpintura\b|\bpintar\b|\bspray\b|\bcola de contato\b|\badesivo de contato\b|\bcascola\b/ },
  { energia: 'dc', re: /\b(?:12|24)\s?v\b|\b12\/24\b|\bbaterias?\b|\blitio\b|\blifepo4\b|\balternador\b|\bfusive(?:l|is)\b|\bporta-fusive(?:l|is)\b|\bdc\b|\bcc\b|\bdc-dc\b|\bdc\/dc\b|\bsolar(?:es)?\b|\bleds?\b|\bconversor(?:es)?\b|\bcarregador(?:es)?\b|\binversor(?:es)?\b|\bstarlink\b|\bsmartshunt\b|\bshunt\b|\breles?\b|\bfiacao\b|\bcabos?\b|\bchicote\b|\bfarol\b|\bfarois\b|\blampadas?\b|\bsinaleira\b|\biluminacao\b|\bluminarias?\b|\bplafons?\b|\bcameras?\b|\bradio\b|\bradar\b|\bgps\b|\bnmea\s?2000\b|\bnmea\b|\bsonda\b|\btv\b|\beletric[ao]s?\b|\beletronic[ao]s?\b|\balarmes?\b|\bbombas?\b|\bpainel\b|\bmonitoramento\b|\bvictron\b|\bbms\b|\bbarramentos?\b|\bbusbar\b|\bdisjuntor(?:es)?\b|\bsensor(?:es)?\b|\bdisplay\b|\bvoltimetro\b|\binterruptor(?:es)?\b|\bbotao\b|\bventilador\b|\bexaustor\b|\bgiroflex\b|\bbuzina\b|\bcentral\b|\bquadros?\b|\bsom\b|\balto-falantes?\b|\bhome theater\b|\bdvr\b|\bconector(?:es)?\b|\bgeladeira\b|\brefrigerador\b|\bcompressor\b|\bvolante\b|\bairbag\b/ },
];

/** Material: só as energias que o nome de uma peça revela sem ruído (o inversor na separação, a tinta spray). */
export const ENERGIAS_DO_MATERIAL = new Set<Energia>(['ac', 'gas', 'combustivel', 'refrigerante', 'altura', 'casco', 'quimico']);

/**
 * O serviço mexe no sistema de energia (não só num circuito): banco, carga, inversor, quadro, porta-fusível,
 * fusíveis, cabos deteriorados, bomba de porão. Com isso, o inversor ou a energia de terra do cadastro do veículo contam.
 */
export const MEXE_NO_BANCO = /\bbaterias?\b|\blitio\b|\blifepo4\b|\bbanco\b|\balternador\b|\bcarregador|\bsolar|\binversor|\bbarramento|\bbusbar\b|\bshunt\b|\bsmartshunt\b|\bdc-dc\b|\bdc\/dc\b|\bchave geral\b|\bgerador|\bvictron\b|\bbms\b|\bmultiplus\b|\btechnomaster\b|\btm41\b|\bfusivel principal\b|\bconversor|\bquadros?\b|\busina\b|\bvsr\b|\bporta[- ]?fusive(?:l|is)\b|\bfusiveis\b|\bcabos? deteriorados?\b|\bbombas? de porao\b/;
/** Linha de água (vaso, torneira, cano): não leva energia nem vira 12/24 V "na dúvida". */
export const HIDRAULICO = /\bvaso sanitario\b|\btorneiras?\b|\bencanamento\b|\bcanos?\b|\bhidraulic[oa]s?\b|\bdescarga\b|\bacumulador(?:es)? de pressao\b|\bcaixa coletora\b|\bpia\b|\bralo\b/;
/** Gerador ou motor de popa revisado, testado, regulado, consertado: motor girando. */
export const MOTOR_EM_TESTE = /\b(?:revis|teste|testar|rotac|governador|regula|sob carga|partida|manutenc|oleo|filtro|ignic|bobina|montagem|reparo|diagnost)/;

/**
 * Uma linha por risco grave, curta (textos aprovados pelo dono em 15/11/2026, resposta 5). A chave é a energia;
 * a altura se divide em `teto` (veículo) e `barco` (arco, hardtop, mastro).
 */
export const ATENCAO: Record<string, string> = {
  ac: 'antes de abrir, tomada externa solta, gerador sem partida automática e inversor desligado; no fim, teste terra, fase e neutro.',
  gas: 'feche o botijão antes de abrir; nada de chama; no fim, espuma em cada conexão mexida.',
  combustivel: 'feche o registro antes de abrir linha, filtro ou tanque; nada de faísca.',
  refrigerante: 'só quem é habilitado abre o circuito; nunca com maçarico.',
  teto: 'escada amarrada ou plataforma; nunca pise em claraboia ou painel; nunca sozinho.',
  barco: 'alguém junto e uma mão para se segurar; com o barco na água, colete.',
  mecanico: 'escore o que pode cair; embaixo do veículo, só em cavalete, nunca só na sapata.',
  motor: 'mãos longe de correia e ventoinha; só ao ar livre.',
  dc: 'desligue chave geral, carregador, solar e DC-DC; ferramenta isolada; religue tudo no fim.',
  furo: 'veja o que passa atrás (cabo, gás, combustível, freio); vede cada furo.',
  casco: 'furo no casco só com o barco fora d’água.',
  quimico: 'máscara, óculos e luva; ventile.',
};
/** A ordem das linhas no quadro (a da bancada, enxuta/S/render.ts). */
export const ORDEM: Energia[] = ['ac', 'gas', 'combustivel', 'refrigerante', 'altura', 'mecanico', 'motor', 'dc', 'casco', 'furo', 'quimico'];

/** A linha do volante: só junto do 12/24 V (é a bateria que se desliga), quando o serviço cita volante ou airbag. */
export const VOLANTE = 'desligue a bateria e espere 3 min antes de soltar; nunca meça o airbag.';

/** Texto onde a palavra é negada ("funciona sem inversor ou gerador") ou é água ("tanque de água") não conta. */
export function textoParaEnergia(texto: string, tanqueDeAgua = false): string {
  const t0 = normalizar(texto);
  // Numa OS cujo tanque é o de água ("Reparo do tanque de água"), "do tanque" sozinho também é água.
  const agua = tanqueDeAgua && !/\b(?:diesel|gasolina|combustive(?:l|is))\b/.test(t0);
  // Pintura que NÃO é do técnico não conta ("pintura não inclusa"; "… tratadas diretamente com o pintor").
  const t1 = /\bpintor(?:es|a)?\b/.test(t0) ? t0.replace(/\bpintura\b|\bpintar\b/g, ' ') : t0;
  return (agua ? t1.replace(/\btanques?\b/g, ' ') : t1)
    .replace(/\b(?:pintura|tinta)\s+nao\s+inclus[ao]s?\b|\bsem\s+pintura\b|\bnao\s+inclui\s+(?:a\s+)?pintura\b/g, ' ')
    .replace(/\bsem\s+(?:inversor|gerador|tomada externa)(?:\s+(?:ou|e|nem)\s+(?:inversor|gerador))?/g, ' ')
    .replace(/\btanques?\s+(?:de\s+)?d?.?agua\b/g, ' ')
    // O gás do ar-condicionado é fluido refrigerante (ar-condicionado não queima GLP). Troca SÓ a palavra "gás":
    // a palavra "ar-condicionado" fica e continua dando 127/220 V.
    .replace(/\b(ar[- ]condicionados?)\b([^.;]{0,40}?)\bgas\b/g, '$1$2 fluido refrigerante')
    // Na geladeira, só com palavra de refrigeração ("vazando gás", "carga de gás"): "geladeira a gás" (trivolt) é GLP.
    .replace(/\b(geladeiras?|refrigerador(?:es)?|compressor(?:es)?)\b([^.;]{0,40}?)\b(vazando|vazamento de|carga de|recarga de|completar o|recolhimento do)\s+gas\b/g, '$1$2 $3 fluido refrigerante')
    .replace(/\bgas\s+refrigerante\b/g, 'fluido refrigerante')
    // O fogão como LUGAR ("puxador do móvel aéreo sobre o fogão") não é mexer no gás. Virar, trocar ou mover o fogão
    // continua dando gás (a conexão sofre).
    .replace(/\b(sobre|acima|abaixo|perto|atras|embaixo|em cima|ao lado)\s+(d?[oa]s?\s+)?fog(?:ao|oes)\b/g, '$1 $2local')
    // "detector eletrônico" (de vazamento de gás) é ferramenta, não circuito do veículo
    .replace(/\bdetector(?:es)? eletronicos?\b/g, 'detector');
}

/** As energias que as palavras do texto revelam, com as palavras achadas (o material de rede descarta "tomada"). */
export function palavrasDeEnergia(texto: string, tanqueDeAgua = false): Map<Energia, string[]> {
  const t = textoParaEnergia(texto, tanqueDeAgua);
  const out = new Map<Energia, string[]>();
  for (const { energia, re } of PALAVRAS) {
    const g = new RegExp(re.source, 'g');
    const achou = [...new Set([...t.matchAll(g)].map((x) => x[0].trim()))];
    if (achou.length) out.set(energia, [...new Set([...(out.get(energia) ?? []), ...achou])]);
  }
  return out;
}

function nomeDaLinha(l: Linha): string {
  return l.name_snapshot || l.services?.name || 'Serviço';
}

/**
 * O pedido dividido entre os serviços: o parágrafo que começa pelo título de um serviço seguido de ":" ou travessão
 * ("Kit 3 — Sistema de Energia: substituição do inversor…") é o "o que fazer" DAQUELE serviço; um "Inclui…" logo
 * depois continua o mesmo kit. O resto (sobra) é o pedido da OS.
 */
export function trechosDosServicos(
  pedidoLimpo: string,
  servicos: Array<{ numero: number; titulo: string }>,
): { anexos: Map<number, string>; sobra: string[] } {
  const sobra: string[] = [];
  const anexos = new Map<number, string>();
  let ultimoKit: number | null = null;
  for (const p of pedidoLimpo.split('\n').filter(Boolean)) {
    const pn = normalizar(p);
    const s = servicos.find((sv) => {
      const tn = normalizar(sv.titulo);
      return tn.length >= 8 && pn.startsWith(tn) && /^\s*[:—–-]/.test(pn.slice(tn.length));
    });
    const resto = s ? p.slice(s.titulo.length).replace(/^[\s:—–-]+/, '').trim() : '';
    if (s && resto) { anexos.set(s.numero, resto.charAt(0).toUpperCase() + resto.slice(1)); ultimoKit = s.numero; continue; }
    // "Inclui conexões hidráulicas." numa linha própria logo depois do kit é continuação dele.
    if (ultimoKit != null && /^(?:inclui|incluindo|com |obs)/i.test(p)) { anexos.set(ultimoKit, `${anexos.get(ultimoKit)} ${p}`); continue; }
    ultimoKit = null;
    sobra.push(p);
  }
  return { anexos, sobra };
}

/** O que o quadro precisa saber da parte da via: as energias e os três sinais que mudam o texto. */
export interface EnergiasDaVia {
  energias: Set<Energia>;
  /** Barco: a altura vira arco/hardtop/mastro ("Altura"). */
  nautico: boolean;
  /** Lítio no texto da parte: o 12/24 V vira "Bateria de lítio". */
  litio: boolean;
  /** Volante ou airbag no texto da parte: linha extra depois do 12/24 V. */
  airbag: boolean;
}

/**
 * As energias da via (da OS inteira, ou da parte de uma pessoa): o sistema de cada linha, as palavras do nome, das
 * notas e do trecho do pedido que é dela, o pedido da OS (só quando a parte tem todos os serviços), o material da
 * parte e o cadastro do veículo. A regra é a da bancada (proposta/via-v2.ts, analisarEnergias), sem os motivos.
 */
export function energiasDaVia(d: EntradaDaAtencao, pessoa: { id: string } | null = null): EnergiasDaVia {
  const minhas = pessoa ? d.linhas.filter((l) => !l.responsavel_payee_id || l.responsavel_payee_id === pessoa.id) : d.linhas;
  const comPedido = minhas.length === d.linhas.length;
  const numero = new Map(d.linhas.map((l, i) => [l.id, i + 1]));
  const meusIds = new Set(minhas.map((l) => l.id));
  const energias = new Set<Energia>();
  // O trecho do pedido que é de um serviço vai com ele; o resto do pedido é da OS e só entra com a OS inteira.
  const { anexos, sobra } = trechosDosServicos(
    limparPedido(d.header.problemDescription),
    minhas.map((l) => ({ numero: numero.get(l.id) ?? 0, titulo: tituloDoServico(nomeDaLinha(l)) })),
  );
  const pedido = comPedido ? sobra.join('\n') : '';
  const daParte = normalizar([pedido, ...minhas.map((l) => nomeDaLinha(l)), ...anexos.values()].join('\n'));
  const tanqueDeAgua = /\btanques?\s+(?:de\s+)?d?.?agua\b/.test(daParte);
  const nautico = camposDoTipo(d.header.assetType).nauticos;
  const textos: string[] = [pedido];
  for (const l of minhas) {
    const n = numero.get(l.id) ?? null;
    let algum = false;
    // Decisão 3A: o sistema gravado na linha ou, na falta, o do cadastro do serviço.
    const sistema = l.service_system ?? l.services?.service_system ?? null;
    if (sistema) {
      const e = Object.prototype.hasOwnProperty.call(SISTEMA_ENERGIA, sistema) ? SISTEMA_ENERGIA[sistema] : undefined;
      if (sistema === 'nenhum' || sistema === 'hidraulico') algum = true;
      if (e) { algum = true; energias.add(e); }
    }
    const proprio = `${nomeDaLinha(l)}\n${l.notes ?? ''}`;
    const anexo = n != null ? anexos.get(n) ?? '' : '';
    const texto = anexo ? `${proprio}\n${anexo}` : proprio;
    textos.push(texto);
    const palavras = new Set(palavrasDeEnergia(proprio, tanqueDeAgua).keys());
    if (anexo) for (const e of palavrasDeEnergia(anexo, tanqueDeAgua).keys()) palavras.add(e);
    for (const e of palavras) { algum = true; energias.add(e); }
    const tn = textoParaEnergia(texto, tanqueDeAgua); // já sem negação ("sem inversor ou gerador") e sem "tanque de água"
    // Ar-condicionado de motorhome fica no teto: instalar, trocar ou consertar é subir.
    if (!nautico && /\bar[- ]condicionados?\b|\bclimatizador\b/.test(tn) && !palavras.has('altura')) energias.add('altura');
    // Gerador revisado, testado, consertado ou INSTALADO (a partida de teste vem logo depois): motor girando.
    // "Instalação de ATS para o gerador" não conta: o objeto tem de ser o gerador.
    const geradorInstalado = /\binstala(?:cao|r)\s+(?:d[oe]\s+|o\s+|um\s+|de\s+um\s+)?(?:novo\s+)?geradore?s?\b/.test(tn);
    // Gerador montado, desmontado, retirado ou instalado é peça pesada; na revisão ou regulagem só, não.
    const geradorPesado = geradorInstalado ||
      /\b(?:montagem|desmontagem|desmontar|montar|retirada|retirar|remocao|remover|substituicao|troca)\s+(?:d[oe]s?\s+|o\s+|um\s+)?geradore?s?\b/.test(tn);
    const geradorRevisao = /\brevis(?:ao|ar|oes)\b|\bregula(?:gem|r|cao)\b|\bgovernador\b/.test(tn);
    if (/\bgerador(?:es)?\b/.test(tn) && (MOTOR_EM_TESTE.test(tn) || geradorInstalado)) {
      energias.add('motor');
      if (!geradorRevisao || geradorPesado) energias.add('mecanico');
    } else if (/\bgerador(?:es)?\b/.test(tn) && geradorPesado) {
      energias.add('mecanico');
    }
    // Motor de popa revisado, consertado ou testado em navegação: motor funcionando.
    if (/\bmotor(?:es)? de popa\b/.test(tn) && (MOTOR_EM_TESTE.test(tn) || /\bnavegacao\b/.test(tn))) energias.add('motor');
    // Porão de barco: vapor de combustível — na dúvida, inclui.
    if (nautico && /\bporao\b|\bcasa de maquinas\b|\bpraca de maquinas\b/.test(tn)) energias.add('combustivel');
    // Trabalho embaixo do veículo.
    if (/\bembaixo do (?:caminhao|veiculo|motorhome|chassi|onibus)\b|\bsob o (?:veiculo|chassi)\b/.test(tn)) energias.add('mecanico');
    // Linha de água (vaso, torneira, cano) não leva energia: não vira 12/24 V "na dúvida".
    if (!algum && HIDRAULICO.test(tn)) algum = true;
    if (!algum) energias.add('dc');
  }
  // O pedido é da OS inteira: entra na via da OS e na de quem tem todos os serviços.
  if (comPedido) for (const e of palavrasDeEnergia(pedido, tanqueDeAgua).keys()) energias.add(e);
  // O material da parte (ligado a um serviço dela, ou sem serviço — que vai para todos).
  for (const m of d.materiais ?? []) {
    if (m.service_order_service_id && !meusIds.has(m.service_order_service_id)) continue;
    const nome = m.products?.name ?? '';
    if (!nome) continue;
    textos.push(nome);
    for (const [e, ws0] of palavrasDeEnergia(nome, tanqueDeAgua)) {
      if (!ENERGIAS_DO_MATERIAL.has(e)) continue;
      // No nome de peça, "tomada" é quase sempre outra coisa ("Adaptador de Tomada Veicular 12V").
      const ws = e === 'ac' ? ws0.filter((w) => !/^tomadas?$/.test(w)) : ws0;
      if (ws.length) energias.add(e);
    }
  }
  const tudo = normalizar(textos.join('\n'));
  // O cadastro do veículo: inversor ou energia de terra cadastrados entram quando o serviço mexe no sistema de energia.
  const el = d.header.vehicleElectrical;
  const veiculoAc = [el?.inverterCharger, el?.shorePower].filter((x) => (x ?? '').trim()).join(' · ');
  if (veiculoAc && MEXE_NO_BANCO.test(tudo)) energias.add('ac');
  return {
    energias,
    nautico,
    litio: /\blitio\b|\blifepo4\b/.test(tudo),
    airbag: /\bvolante\b|\bairbag\b/.test(tudo),
  };
}

/** Uma linha do quadro: "<b>{rotulo}:</b> {texto}". */
export interface LinhaDeAtencao {
  rotulo: string;
  texto: string;
}

/** O quadro "Atenção" da via (da OS inteira, ou da parte de uma pessoa), na ordem de ORDEM. Vazio = sem quadro. */
export function linhasDeAtencao(d: EntradaDaAtencao, pessoa: { id: string } | null = null): LinhaDeAtencao[] {
  const { energias, nautico, litio, airbag } = energiasDaVia(d, pessoa);
  const out: LinhaDeAtencao[] = [];
  for (const e of ORDEM) {
    if (!energias.has(e)) continue;
    if (e === 'altura') {
      out.push(nautico ? { rotulo: 'Altura', texto: ATENCAO.barco } : { rotulo: 'Teto', texto: ATENCAO.teto });
      continue;
    }
    const curto = CURTO[e];
    const rotulo = e === 'dc' ? (litio ? 'Bateria de lítio' : '12/24 V')
      : curto.charAt(0).toLocaleUpperCase('pt-BR') + curto.slice(1);
    out.push({ rotulo, texto: ATENCAO[e] });
    if (e === 'dc' && airbag) out.push({ rotulo: 'Volante', texto: VOLANTE });
  }
  return out;
}
