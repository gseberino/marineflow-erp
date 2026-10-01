/**
 * Folha de comissionamento — o registro de como ficou uma instalação de energia.
 *
 * A via do técnico diz o que fazer; esta folha prova como ficou: números de série, o valor
 * do manual ao lado do valor medido ou configurado, testes e fotos. Serve à conferência,
 * à garantia do fabricante e ao próximo técnico.
 *
 * Regras do dono (01/10/2026):
 *  · NENHUM valor de tensão, torque ou corrente inventado. Toda linha tem a coluna
 *    "Esperado", que o técnico preenche com o manual DAQUELE modelo e a página.
 *  · Serve a todas as marcas (Victron, EcoFlow, Epever, Renogy, LiTime, Mastervolt,
 *    Furrion…): nada de passo de fabricante.
 *  · Blocos na ordem de recorrência da HBR: DC-DC, carregador, inversor, MPPT, lítio.
 *  · Só medições possíveis com os instrumentos da equipe: multímetro com alicate DC,
 *    torquímetro, testador de baterias Ikro e scanner Multimec X3.
 *
 * É a versão de teste em papel (fase 5a) montada a partir da OS (fase 5b): identificação
 * preenchida e um bloco por equipamento reconhecido entre as peças da OS. O registro dos
 * valores no sistema (5c) espera o teste em campo.
 */

export type TipoDeEquipamento = 'dcdc' | 'carregador' | 'inversor' | 'mppt' | 'bateria_litio';

/**
 * Reconhece o tipo de equipamento pelo nome da peça. A ordem importa: "carregador DC/DC"
 * é DC-DC, não carregador de tomada; "inversor carregador" é inversor.
 */
export function tipoDeEquipamento(nome: string | null | undefined): TipoDeEquipamento | null {
  const n = (nome || '').toLowerCase();
  if (!n) return null;
  if (/dc\s*[/-]?\s*dc|orion|conversor de bateria|carregador conversor/.test(n)) return 'dcdc';
  if (/mppt|controlador (solar|de carga)/.test(n)) return 'mppt';
  if (/inversor|multiplus|quattro|phoenix inverter|inverter/.test(n)) return 'inversor';
  if (/carregador|charger|blue ?smart|skylla/.test(n)) return 'carregador';
  if (/l[ií]tio|lifepo|lithium/.test(n) && /bateria|battery/.test(n)) return 'bateria_litio';
  return null;
}

export interface ComissionamentoHeader {
  orderNumber?: string | null;
  vehicle?: string | null;
  clientName?: string | null;
  technicianName?: string | null;
  companyName?: string | null;
}

export interface PecaDaOS {
  name: string;
  quantity?: number | null;
}

type Linha = [item: string, esperado: string, medido: string];
type Secao = { titulo?: string; linhas: Linha[] };

const L = '<span class="ln"></span>';

const BLOCOS: Record<TipoDeEquipamento, { titulo: string; terceiro: string; secoes: Secao[] }> = {
  dcdc: {
    titulo: 'Carregador conversor DC-DC',
    terceiro: 'Corrente nominal (A)',
    secoes: [
      { titulo: 'Antes de ligar', linhas: [
        ['Bateria de partida testada com o Ikro antes de instalar', 'resultado do testador', L],
        ['Códigos de falha do sistema de carga do veículo lidos com o scanner (antes)', '—', `nenhum ☐ · quais: ${L}`],
        ['Alternador: convencional ou controlado pela central do veículo (inteligente)?<div class="nota">Como identificou: scanner, manual do veículo ou tensão variando com o motor ligado.</div>', '—', '☐ convencional ☐ inteligente'],
        ['Fusível na entrada (lado bateria de partida), perto da bateria', `${L} A`, `${L} A · ${L} cm`],
        ['Fusível na saída (lado bateria de serviço), perto da bateria', `${L} A`, `${L} A · ${L} cm`],
        ['Bitola dos cabos de entrada e de saída', `${L} mm²`, `${L} mm²`],
        ['Aperto dos terminais com torquímetro e marca de torque feita', `${L} N·m`, `${L} N·m · ☐ marca`],
      ] },
      { titulo: 'Configuração', linhas: [
        ['Perfil de carga igual ao da bateria de serviço (ver bloco das baterias)', 'perfil do manual da bateria', L],
        ['Corrente máxima configurada', `${L} A`, `${L} A`],
        ['Como ele sabe que o motor ligou: tensão, sinal de ignição (D+) ou outro', 'modo indicado no manual para este alternador', L],
      ] },
      { titulo: 'Testes', linhas: [
        ['Motor ligado: carregando? Corrente na saída (alicate DC)', `até ${L} A`, `☐ sim · ${L} A`],
        ['Tensão na entrada do DC-DC com ele carregando no máximo', `acima de ${L} V`, `${L} V`],
        ['Motor desligado: parou de carregar sozinho?', '—', '☐ sim ☐ não'],
        ['Códigos de falha lidos com o scanner depois da instalação', 'nenhum novo', `☐ nenhum · ${L}`],
      ] },
    ],
  },
  carregador: {
    titulo: 'Carregador de baterias (tomada / cais / gerador)',
    terceiro: 'Corrente nominal (A)',
    secoes: [{ linhas: [
      ['Fusível do lado da bateria, perto dela', `${L} A`, `${L} A · ${L} cm`],
      ['Proteção do lado da tomada (disjuntor/DR existente no quadro)', '—', `☐ disjuntor ${L} A ☐ DR`],
      ['Carcaça ligada ao terra / chassi / casco, como pede o manual', '—', '☐ sim'],
      ['Perfil de carga: tensão de absorção e de flutuação', `absorção ${L} V · flutuação ${L} V`, `${L} V · ${L} V`],
      ['Corrente de carga configurada', `${L} A`, `${L} A`],
      ['Ligado na tomada: corrente de carga medida (alicate DC)', `até ${L} A`, `${L} A`],
    ] }],
  },
  inversor: {
    titulo: 'Inversor (ou inversor-carregador)',
    terceiro: 'Potência (W / VA)',
    secoes: [
      { titulo: 'Lado DC', linhas: [
        ['Fusível DC perto da bateria, do tamanho que o manual do inversor pede', `${L} A`, `${L} A · ${L} cm`],
        ['Bitola dos cabos DC para o comprimento instalado', `${L} mm² até ${L} m`, `${L} mm² · ${L} m`],
        ['Aperto dos terminais DC com torquímetro e marca de torque', `${L} N·m`, `${L} N·m · ☐ marca`],
        ['Desligamento por bateria baixa compatível com a bateria', `${L} V`, `${L} V`],
      ] },
      { titulo: 'Lado AC (127/220 V)', linhas: [
        ['Carcaça aterrada ao chassi / casco', '—', '☐ sim'],
        ['Neutro e fase não invertidos na saída (multímetro: fase–terra e neutro–terra)', '—', `F–T ${L} V · N–T ${L} V`],
        ['Inversor-carregador: tirar a tomada → o inversor assume? Religar → volta a carregar?', '—', '☐ assume ☐ volta'],
      ] },
      { titulo: 'Teste com carga', linhas: [
        [`Carga ligada (qual): ${L} · tensão AC na saída`, `${L} V`, `${L} V`],
        ['Com essa carga: corrente na bateria (alicate DC) e tensão na entrada do inversor', `acima de ${L} V`, `${L} A · ${L} V`],
      ] },
    ],
  },
  mppt: {
    titulo: 'Controlador solar MPPT',
    terceiro: 'Painéis (qtd × W, ligação)',
    secoes: [{ linhas: [
      ['<b>Tensão em aberto dos painéis, medida antes de ligar no MPPT</b><div class="nota">Tem que ficar abaixo do máximo do controlador, com a folga para frio que o manual indicar.</div>', `máx. do MPPT ${L} V`, `${L} V`],
      ['Chave ou disjuntor do lado dos painéis; fusível entre MPPT e bateria', `${L} A`, `☐ chave · ${L} A`],
      ['Perfil de carga igual ao da bateria', 'perfil do manual da bateria', L],
      ['Ligar a bateria antes dos painéis (ordem que o manual pedir)', 'ordem do manual', '☐ feito na ordem'],
      ['Com sol: corrente de carga medida (alicate DC) e horário/condição do céu', '—', `${L} A · ${L}`],
    ] }],
  },
  bateria_litio: {
    titulo: 'Baterias de lítio',
    terceiro: '',
    secoes: [{ linhas: [
      ['Ligação: série / paralelo; tensões das baterias próximas antes de unir', `diferença máx. ${L} V`, `☐ série ☐ paralelo · dif. ${L} V`],
      ['Limites do BMS: corrente máxima de carga e de descarga', `carga ${L} A · desc. ${L} A`, '☐ conferido com os outros blocos'],
      ['Perfil de carga que todas as fontes devem usar', `absorção ${L} V · flut. ${L} V`, '☐ copiado nos outros blocos'],
      ['Carga em baixa temperatura: a bateria ou o carregador corta?', `limite ${L} °C`, '☐ sim ☐ não se aplica'],
      ['Fusível principal perto da bateria (tipo e capacidade de interrupção do manual)', `${L} A · tipo ${L}`, `${L} A · ${L} cm`],
      ['Chave geral no positivo, fácil de alcançar', '—', `☐ sim · onde: ${L}`],
      ['Aperto dos terminais com torquímetro e marca de torque', `${L} N·m`, `${L} N·m · ☐ marca`],
      ['Baterias fixadas: empurrar com força, nada se mexe; terminais protegidos contra toque', '—', '☐ sim'],
      ['Teste de proteção do BMS, se o manual descrever um', 'procedimento do manual', '☐ feito ☐ manual não descreve'],
      ['Aplicativo (se tiver): SoC e maior diferença entre células na entrega', `diferença máx. ${L} mV`, `${L} % · ${L} mV`],
      ['Tensão do banco em repouso na entrega (multímetro)', '—', `${L} V`],
    ] }],
  },
};

const ORDEM: TipoDeEquipamento[] = ['dcdc', 'carregador', 'inversor', 'mppt', 'bateria_litio'];

function esc(v: string | null | undefined): string {
  return (v || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function tabela(secoes: Secao[]): string {
  return `<table>
    <tr><th></th><th>Item</th><th>Esperado (manual, pág.)</th><th>Medido / deixado</th></tr>
    ${secoes.map((s) => `
      ${s.titulo ? `<tr><td colspan="4" class="sec">${s.titulo}</td></tr>` : ''}
      ${s.linhas.map(([it, esp, med]) => `<tr><td class="c"><span class="bx"></span></td><td class="it">${it}</td><td class="esp">${esp}</td><td class="med">${med}</td></tr>`).join('')}
    `).join('')}
  </table>`;
}

/**
 * Os blocos que a folha terá: um por aparelho reconhecido nas peças da OS (DC-DC duplo dá
 * dois blocos), baterias juntas num bloco só. Sem nada reconhecido, sai o modelo inteiro.
 */
export function blocosDaFolha(pecas: PecaDaOS[]): Array<{ tipo: TipoDeEquipamento; modelos: string[] }> {
  const porTipo = new Map<TipoDeEquipamento, string[]>();
  for (const p of pecas) {
    const tipo = tipoDeEquipamento(p.name);
    if (!tipo) continue;
    const qtd = Math.max(1, Math.round(Number(p.quantity) || 1));
    const lista = porTipo.get(tipo) ?? [];
    for (let i = 0; i < qtd; i++) lista.push(p.name);
    porTipo.set(tipo, lista);
  }
  if (!porTipo.size) return ORDEM.map((tipo) => ({ tipo, modelos: [] }));
  const blocos: Array<{ tipo: TipoDeEquipamento; modelos: string[] }> = [];
  for (const tipo of ORDEM) {
    const modelos = porTipo.get(tipo);
    if (!modelos) continue;
    if (tipo === 'bateria_litio') blocos.push({ tipo, modelos });
    else for (const m of modelos) blocos.push({ tipo, modelos: [m] });
  }
  return blocos;
}

export function buildCommissioningSheetHtml(header: ComissionamentoHeader, pecas: PecaDaOS[]): string {
  const blocos = blocosDaFolha(pecas);
  const reconhecidos = blocos.some((b) => b.modelos.length);
  const numero = esc(header.orderNumber) || '________';

  const blocosHtml = blocos.map((b, i) => {
    const def = BLOCOS[b.tipo];
    const n = i + 1;
    if (b.tipo === 'bateria_litio') {
      const linhas = Math.max(b.modelos.length, 2);
      return `
      <div class="bloco">
        <div class="bh"><span class="n">${n} · ${def.titulo}</span><span class="s">uma linha por bateria</span></div>
        <table>
          <tr><th></th><th>Bateria (marca, modelo, Ah)</th><th>Nº de série · foto</th><th>Tensão antes de unir</th></tr>
          ${Array.from({ length: linhas }, (_, k) => `<tr><td class="c">${k + 1}</td><td class="it">${esc(b.modelos[k] || '')}</td><td class="esp">${L} · ☐</td><td class="med">${L} V</td></tr>`).join('')}
        </table>
        <div style="height:1.5mm"></div>
        ${tabela(def.secoes)}
      </div>`;
    }
    return `
      <div class="bloco">
        <div class="bh"><span class="n">${n} · ${def.titulo}</span></div>
        <div class="eqp"><div>${b.modelos[0] ? `<b>${esc(b.modelos[0])}</b>` : 'Marca e modelo'}</div><div>Nº de série</div><div>${def.terceiro}</div><div>☐ foto da etiqueta</div></div>
        ${tabela(def.secoes)}
      </div>`;
  }).join('');

  const nProt = blocos.length + 1;
  const nEntrega = blocos.length + 2;

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Comissionamento ${numero}</title>
<style>
  @page { size: A4; margin: 10mm 10mm 13mm;
    @bottom-left { content: "Folha de comissionamento · versão de teste · anote na margem o que não serviu"; font: 7.5pt Arial, sans-serif; color: #444; }
    @bottom-right { content: "${numero} · pág. " counter(page) " de " counter(pages); font: 7.5pt Arial, sans-serif; color: #444; }
  }
  * { box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; font-size: 9.5pt; color: #000; margin: 0; }
  h1 { font-size: 14pt; margin: 0; color: #002B5B; }
  .top { display: flex; justify-content: space-between; align-items: flex-end; border-bottom: 1.2pt solid #002B5B; padding-bottom: 2mm; margin-bottom: 3mm; }
  .top .k { font-size: 7.5pt; letter-spacing: .1em; text-transform: uppercase; color: #444; }
  .id { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 2mm 6mm; margin-bottom: 3mm; }
  .id div { border-bottom: .5pt solid #000; padding: 1mm 0 .5mm; font-size: 9pt; min-height: 9mm; }
  .id small { display: block; font-size: 7pt; color: #444; text-transform: uppercase; letter-spacing: .06em; }
  .guia { border: 1pt dashed #000; padding: 2mm 3mm; margin-bottom: 3mm; font-size: 8.5pt; line-height: 1.35; }
  .bloco { margin-bottom: 4mm; }
  .bh { display: flex; justify-content: space-between; align-items: baseline; border-bottom: 1.2pt solid #000; padding: 1.5mm 0 1mm; margin-bottom: 1mm; break-after: avoid; }
  .bh .n { font-size: 11pt; font-weight: bold; text-transform: uppercase; letter-spacing: .04em; }
  .bh .s { font-size: 8pt; color: #333; }
  .eqp { display: grid; grid-template-columns: 2fr 2fr 1.4fr 1.4fr; gap: 0 4mm; font-size: 8pt; color: #444; margin: 1mm 0 1.5mm; }
  .eqp div { border-bottom: .5pt solid #000; padding-top: 4mm; }
  .eqp b { color: #000; font-size: 8.5pt; }
  table { width: 100%; border-collapse: collapse; }
  th { font-size: 7pt; text-transform: uppercase; letter-spacing: .05em; text-align: left; color: #444; font-weight: normal; padding: .8mm 1mm; border-bottom: .5pt solid #888; }
  td { padding: 1.4mm 1mm; border-bottom: .4pt dotted #999; vertical-align: top; line-height: 1.3; }
  tr { break-inside: avoid; }
  td.c { width: 5mm; }
  .bx { display: inline-block; width: 3.6mm; height: 3.6mm; border: .9pt solid #000; }
  td.it { width: 46%; }
  td.esp { width: 27%; font-size: 8pt; color: #222; }
  td.med { width: 27%; }
  .ln { display: inline-block; border-bottom: .5pt solid #000; min-width: 16mm; height: 3.5mm; }
  .nota { font-size: 7.8pt; color: #333; font-style: italic; }
  .sec { font-weight: bold; font-size: 8pt; text-transform: uppercase; letter-spacing: .05em; padding-top: 2mm; }
  .pare { border: 1.2pt solid #000; padding: 1.8mm 3mm; margin: 2mm 0 4mm; font-size: 8.5pt; break-inside: avoid; }
  .grid2 { break-inside: avoid; display: grid; grid-template-columns: 1fr 1fr; gap: 3mm 6mm; }
  .esq { border: .8pt solid #000; height: 70mm; position: relative; }
  .esq span { position: absolute; top: 1.5mm; left: 2mm; font-size: 7.5pt; color: #444; }
  .sign { display: flex; gap: 8mm; margin-top: 6mm; break-inside: avoid; }
  .sign div { flex: 1; border-top: .5pt solid #000; padding-top: 1mm; font-size: 8pt; }
</style>
</head>
<body>
<div class="top">
  <div><div class="k">${esc(header.companyName) || 'HBR'} · versão de teste</div><h1>Folha de comissionamento</h1></div>
  <div class="k">Sistema de energia · barco ou motorhome</div>
</div>

<div class="id">
  <div><small>OS</small>${numero}</div>
  <div><small>Veículo</small>${esc(header.vehicle)}</div>
  <div><small>Data</small></div>
  <div><small>Técnico</small>${esc(header.technicianName)}</div>
  <div><small>Cliente</small>${esc(header.clientName)}</div>
  <div><small>Tensão do sistema (12 / 24 / 48 V)</small></div>
</div>

<div class="guia">
  <b>Como usar.</b> ${reconhecidos
    ? 'Os blocos abaixo saíram dos equipamentos lançados nesta OS. Se instalou algo que não está aqui, use o verso ou peça a folha completa.'
    : 'Nenhum equipamento desta OS foi reconhecido pelo nome: preencha só os blocos do que foi instalado e risque os outros.'}
  Na coluna <b>Esperado</b>, escreva o valor do manual do fabricante <b>daquele modelo</b> e a página;
  nunca um valor "de costume". Sem manual, escreva "sem manual" e avise o escritório.
  <br><b>Instrumentos:</b> multímetro com alicate amperímetro DC · torquímetro · testador de baterias Ikro ·
  scanner automotivo Multimec X3.
</div>

<div class="pare"><b>Fora do esperado? Não entregue.</b> Anote o valor, fotografe e fale com o escritório antes de liberar o sistema ao cliente.</div>

${blocosHtml}

<div class="bloco">
  <div class="bh"><span class="n">${nProt} · Proteções, cabos e queda de tensão</span><span class="s">vale para a instalação inteira</span></div>
  <table>
    <tr><th></th><th>Fusível / disjuntor (onde fica, o que protege)</th><th>Valor e tipo</th><th>Etiquetado?</th></tr>
    ${[1, 2, 3, 4, 5].map((k) => `<tr><td class="c">${k}</td><td class="it"></td><td class="esp"></td><td class="med">☐</td></tr>`).join('')}
  </table>
  <div style="height:1.5mm"></div>
  ${tabela([{ linhas: [
    ['Polaridade de todos os cabos conferida antes de energizar', '—', '☐'],
    ['Cabos identificados nas duas pontas', '—', '☐'],
    ['Queda de tensão no maior consumidor ligado: medir no positivo e no negativo, separados<div class="nota">Multímetro de uma ponta à outra do mesmo cabo, com a carga ligada. Anote a corrente.</div>', `máx. ${L} %`, `+ ${L} V · – ${L} V a ${L} A`],
  ] }])}
</div>

<div class="bloco">
  <div class="bh"><span class="n">${nEntrega} · Fotos, esquema e entrega</span></div>
  <div class="grid2">
    <div>
      <div class="sec">Fotos obrigatórias (mande pelo WhatsApp da HBR)</div>
      <table>
        ${['Etiqueta de série de cada equipamento', 'Terminais das baterias com a marca de torque', 'Fusíveis e chave geral',
          'Tela de configuração de cada equipamento (app ou display)', 'Compartimento inteiro, depois de pronto',
          'Multímetro mostrando a tensão do banco na entrega'].map((f) => `<tr><td class="c"><span class="bx"></span></td><td>${f}</td></tr>`).join('')}
      </table>
      <div class="sec" style="margin-top:3mm">Explicado ao cliente</div>
      <table>
        ${['Onde fica a chave geral e como desligar tudo numa emergência', 'Onde ficam os fusíveis',
          'Como ver a carga da bateria (app ou display) e o que fazer com alarme',
          'Cuidados: não descarregar até o fim, carga em frio, armazenamento'].map((f) => `<tr><td class="c"><span class="bx"></span></td><td>${f}</td></tr>`).join('')}
      </table>
    </div>
    <div class="esq"><span>Esquema como instalado: baterias, fusíveis, chave geral, equipamentos e bitolas</span></div>
  </div>
  <div class="sec" style="margin-top:4mm">Pendências e observações</div>
  <table><tr><td style="height:7mm"></td></tr><tr><td style="height:7mm"></td></tr><tr><td style="height:7mm"></td></tr></table>
  <div class="sign">
    <div>Técnico · nome legível e assinatura</div>
    <div>Cliente · "Recebi o sistema funcionando e as instruções acima." · nome, assinatura, data e hora</div>
  </div>
</div>
</body>
</html>`;
}

/** Abre a folha em nova janela e chama a impressão. */
export function printCommissioningSheet(header: ComissionamentoHeader, pecas: PecaDaOS[]): boolean {
  const win = window.open('', '_blank', 'width=900,height=1000');
  if (!win) return false;
  win.document.write(buildCommissioningSheetHtml(header, pecas));
  win.document.close();
  win.focus();
  win.setTimeout(() => win.print(), 400);
  return true;
}
