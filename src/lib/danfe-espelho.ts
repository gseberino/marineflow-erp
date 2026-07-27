// Espelho / Pré-DANFE — pré-visualização SEM VALOR FISCAL de uma NF-e antes da
// emissão, renderizada no LAYOUT OFICIAL da DANFE (Documento Auxiliar da NF-e).
// Montada a partir do payload EXATO que seria enviado ao provedor (impostos por
// item e CFOP já resolvidos no servidor), sem nenhuma chamada à SEFAZ.
//
// Por que renderizar aqui em vez de pedir o PDF ao provedor: a DANFE real só
// existe depois da autorização (ela estampa o protocolo e a chave da SEFAZ) —
// antes disso não há PDF válido. É o mesmo caminho dos ERPs de mercado: uma
// pré-visualização da DANFE marcada "SEM VALOR FISCAL", para conferência e para
// enviar ao cliente/fornecedor antes de emitir.
//
// Função pura (string HTML) → fácil de abrir numa aba e salvar como PDF.

export interface EspelhoEmitter {
  legal_name?: string | null;
  trade_name?: string | null;
  cnpj?: string | null;
  state_registration?: string | null;
  tax_regime?: string | null;
  crt?: number | null;
  street?: string | null;
  number?: string | null;
  complement?: string | null;
  district?: string | null;
  city_name?: string | null;
  state_code?: string | null;
  postal_code?: string | null;
}

// O payload é o mesmo objeto montado por buildNfeDraftPayload (layout Contora).
// Tipado de forma frouxa de propósito: o espelho só lê, e campos novos no
// payload não devem quebrar a pré-visualização.
export type EspelhoPayload = Record<string, any>;

function esc(v: unknown): string {
  return String(v ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function brl(n: unknown): string {
  const v = Number(n);
  if (!Number.isFinite(v)) return '0,00';
  return v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function num(n: unknown, digits = 4): string {
  const v = Number(n);
  if (!Number.isFinite(v)) return '—';
  return v.toLocaleString('pt-BR', { minimumFractionDigits: 0, maximumFractionDigits: digits });
}

// Datas do payload vêm em YYYY-MM-DD (sem hora) — formatar sem passar por Date
// evita o clássico deslocamento de fuso que joga o vencimento para o dia anterior.
function dateBR(iso: unknown): string {
  const s = String(iso ?? '');
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : (s || '—');
}

function maskDoc(digits: unknown): string {
  const d = String(digits ?? '').replace(/\D/g, '');
  if (d.length === 14) return d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
  if (d.length === 11) return d.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, '$1.$2.$3-$4');
  return d || '';
}

function maskCep(digits: unknown): string {
  const d = String(digits ?? '').replace(/\D/g, '');
  return d.length === 8 ? d.replace(/^(\d{5})(\d{3})$/, '$1-$2') : (d || '');
}

// Bruto do item (qtd × preço), antes do desconto.
function itemGross(it: Record<string, any>): number {
  return Number(it?.quantity ?? 0) * Number(it?.unit_price ?? 0);
}

// IPI devolvido do item (impostoDevol/vIPIDevol) — na devolução do Simples,
// entra no total da nota (regra W16-10). No campo "Valor do IPI" da DANFE.
function itemIpiDevol(it: Record<string, any>): number {
  return Math.max(0, Number(it?.returned_ipi?.value) || 0);
}

// Líquido do item = bruto − desconto + despesas acessórias + IPI devolvido
// (vProd − vDesc + vOutro + vIPIDevol). É o que compõe o total da nota.
function itemTotal(it: Record<string, any>): number {
  return itemGross(it)
    - Math.max(0, Number(it?.discount) || 0)
    + Math.max(0, Number(it?.other_expenses) || 0)
    + itemIpiDevol(it);
}

// Chave de acesso formatada em grupos de 4 (só visual). Aceita 44 dígitos.
function chaveFmt(chave: unknown): string {
  const d = String(chave ?? '').replace(/\D/g, '');
  if (d.length !== 44) return '';
  return d.replace(/(\d{4})(?=\d)/g, '$1 ').trim();
}

// tPag do leiaute NF-e 4.00 (inclui o 14 = Duplicata Mercantil, usado quando a
// nota tem grupo de cobrança).
const TPAG_LABELS: Record<string, string> = {
  '01': 'Dinheiro', '02': 'Cheque', '03': 'Cartão de Crédito', '04': 'Cartão de Débito',
  '05': 'Crédito Loja', '10': 'Vale Alimentação', '11': 'Vale Refeição', '12': 'Vale Presente',
  '13': 'Vale Combustível', '14': 'Duplicata Mercantil', '15': 'Boleto Bancário',
  '16': 'Depósito Bancário', '17': 'PIX', '18': 'Transferência bancária / Carteira digital',
  '19': 'Programa de fidelidade / Cashback', '90': 'Sem Pagamento', '99': 'Outros',
};

function paymentLabel(method: unknown): string {
  const code = String(method ?? '').padStart(2, '0');
  return TPAG_LABELS[code] ? `${code} — ${TPAG_LABELS[code]}` : (code || '—');
}

/**
 * Monta o documento HTML do espelho no layout oficial da DANFE. Autocontido:
 * sem CSS/JS externo, pronto para abrir numa aba e salvar como PDF.
 */
export function buildEspelhoHtml(
  payload: EspelhoPayload,
  emitter: EspelhoEmitter,
  opts: {
    environment?: string | null;
    generatedAt?: Date;
    /** Número/série PREVISTOS (a reserva só ocorre na emissão). */
    number?: number | string | null;
    series?: number | string | null;
  } = {},
): string {
  const items: Record<string, any>[] = Array.isArray(payload?.items) ? payload.items : [];
  const totalBruto = items.reduce((s, it) => s + itemGross(it), 0);
  const totalDescItens = items.reduce((s, it) => s + Math.max(0, Number(it?.discount) || 0), 0);
  const totalOutroItens = items.reduce((s, it) => s + Math.max(0, Number(it?.other_expenses) || 0), 0);
  const totalIpi = items.reduce((s, it) => s + itemIpiDevol(it), 0);
  // ICMS não é destacado na devolução do Simples (CSOSN, aliquot 0). Somamos o
  // que houver no payload para não "inventar" valor que a nota não terá.
  const totalIcms = items.reduce((s, it) => {
    const a = Number(it?.taxes?.icms?.aliquot) || 0;
    const base = a > 0 ? itemGross(it) - (Number(it?.discount) || 0) : 0;
    return s + (a > 0 ? base * (a / 100) : 0);
  }, 0);
  const baseIcms = items.reduce((s, it) => {
    const a = Number(it?.taxes?.icms?.aliquot) || 0;
    return s + (a > 0 ? itemGross(it) - (Number(it?.discount) || 0) : 0);
  }, 0);
  const totalNota = totalBruto - totalDescItens + totalOutroItens + totalIpi; // vNF
  const billing = payload?.billing ?? null;
  const rec = payload?.recipient ?? {};
  const recAddr = rec?.address ?? {};
  const when = opts.generatedAt ?? new Date();
  const dataEmissao = when.toLocaleDateString('pt-BR');
  const horaEmissao = when.toLocaleTimeString('pt-BR');
  const isProducao = String(opts.environment ?? '') === 'producao';
  const ambiente = isProducao ? 'PRODUÇÃO' : 'HOMOLOGAÇÃO';
  const isSaida = payload?.operation_type !== 'entrada';
  const emitterName = emitter?.legal_name || emitter?.trade_name || '(empresa não configurada)';
  const numeroFmt = opts.number ? String(opts.number).padStart(9, '0').replace(/^(\d{3})(\d{3})(\d{3})$/, '$1.$2.$3') : '—';
  const serieFmt = opts.series ? String(opts.series).padStart(3, '0') : '—';
  const chaveReal = chaveFmt(payload?.access_key ?? payload?.chave ?? '');

  const enderecoEmit = [emitter?.street, emitter?.number].filter(Boolean).join(', ')
    + (emitter?.complement ? ` - ${emitter.complement}` : '');
  const enderecoDest = [recAddr?.street, recAddr?.number].filter(Boolean).join(', ')
    + (recAddr?.complement ? ` - ${recAddr.complement}` : '');

  // Fatura (à vista / a prazo) na linha de FATURA/DUPLICATA da DANFE.
  const faturaLinha = billing?.invoice
    ? `Fatura ${esc(billing.invoice.number)} · Valor Original ${brl(billing.invoice.original_amount)} · Desconto ${brl(billing.invoice.discount_amount)} · Valor Líquido ${brl(billing.invoice.net_amount)}`
    : (payload?.payments?.some((p: any) => String(p?.method) === '90')
        ? 'Sem pagamento (devolução / remessa)'
        : `À vista · Valor ${brl(totalNota)}`);

  const payments: Record<string, any>[] = Array.isArray(payload?.payments) ? payload.payments : [];
  const duplicatas: Record<string, any>[] = Array.isArray(billing?.installments) ? billing.installments : [];
  // Forma de pagamento com à vista/a prazo (a API não manda indicator no pagamento
  // único da venda à vista → inferimos pela existência de fatura). tPag 90
  // (devolução/remessa) não é à vista nem a prazo.
  const pagamentosLinha = payments.length
    ? payments.map((p) => {
        const code = String(p?.method ?? '').padStart(2, '0');
        const prazo = code === '90' ? '' : (p?.indicator === 1 || !!billing) ? ' · a prazo' : ' · à vista';
        return `${paymentLabel(p?.method)}${prazo} — ${brl(p?.amount)}`;
      }).join('<br>')
    : '—';
  const duplicatasLinha = duplicatas.length
    ? duplicatas.map((d) => `${esc(d?.number)} · venc. ${dateBR(d?.due_date)} · ${brl(d?.amount)}`).join(' &nbsp;|&nbsp; ')
    : '';

  // Informações complementares: o ";" vira quebra de linha (o DANFE converte;
  // confirmado pela Contora). Dividir ANTES de escapar (entidades HTML terminam
  // em ";"). A referência da nota de origem já vem no additional_info.
  const infoCompl = String(payload?.additional_info ?? '')
    .split(/;[ \t]*/)
    .map((p) => esc(p))
    .filter((p) => p.trim())
    .join('<br>');

  const itemRows = items.map((it, i) => {
    const icms = it?.taxes?.icms ?? {};
    const oCst = `${esc(icms?.origin ?? '')}${esc(icms?.code ?? '')}`; // O/CST ex.: 0900
    const aliqIcms = Number(icms?.aliquot) || 0;
    const baseItem = aliqIcms > 0 ? itemGross(it) - (Number(it?.discount) || 0) : 0;
    const vIcms = aliqIcms > 0 ? baseItem * (aliqIcms / 100) : 0;
    const vIpi = itemIpiDevol(it);
    return `<tr>
      <td class="c">${esc(it?.code)}</td>
      <td>${esc(it?.name)}</td>
      <td class="c">${esc(it?.ncm)}</td>
      <td class="c">${oCst}</td>
      <td class="c">${esc(it?.cfop)}</td>
      <td class="c">${esc(it?.unit)}</td>
      <td class="r">${num(it?.quantity)}</td>
      <td class="r">${brl(it?.unit_price)}</td>
      <td class="r">${brl(itemGross(it))}</td>
      <td class="r">${brl(baseItem)}</td>
      <td class="r">${brl(vIcms)}</td>
      <td class="r">${brl(vIpi)}</td>
      <td class="r">${aliqIcms > 0 ? num(aliqIcms, 2) : '0,00'}</td>
      <td class="r">${vIpi > 0 ? 'devol.' : '—'}</td>
    </tr>`;
  }).join('');

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Espelho DANFE — ${esc(rec?.name || 'pré-visualização')}</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: Arial, "Helvetica Neue", sans-serif; margin: 0; padding: 14px;
         background: #eef2f6; color: #000; font-size: 10px; }
  .toolbar { max-width: 900px; margin: 0 auto 12px; display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
  .btn { background: #0f172a; color: #fff; border: 0; border-radius: 6px; padding: 8px 14px;
         font-size: 13px; font-weight: 600; cursor: pointer; }
  .btn.sec { background: #fff; color: #0f172a; border: 1px solid #cbd5e1; }
  .hint { color: #475569; font-size: 12px; }

  .danfe { max-width: 900px; margin: 0 auto; background: #fff; padding: 10px 12px 16px;
           box-shadow: 0 1px 4px rgba(0,0,0,.15); position: relative; }
  /* Marca d'água "SEM VALOR FISCAL" sobre o corpo (igual às pré-DANFEs de mercado). */
  .wm { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
        pointer-events: none; z-index: 5; }
  .wm span { color: rgba(220,38,38,.16); font-size: 46px; font-weight: 900; letter-spacing: 2px;
             text-align: center; line-height: 1.1; }

  table { border-collapse: collapse; width: 100%; }
  .b { border: .8px solid #000; }
  .cap { font-size: 6.5px; text-transform: uppercase; color: #333; display: block; letter-spacing: .2px; }
  .val { font-size: 10px; font-weight: 700; }
  .cell { border: .8px solid #000; padding: 2px 4px; vertical-align: top; }
  .c { text-align: center; } .r { text-align: right; } .bold { font-weight: 700; }

  /* Canhoto */
  .canhoto { border: .8px solid #000; padding: 4px 6px; font-size: 8px; margin-bottom: 2px; display: flex; }
  .canhoto .txt { flex: 1; }
  .canhoto .nfbox { border-left: .8px solid #000; padding-left: 8px; text-align: center; min-width: 120px; }
  .nfbig { font-size: 15px; font-weight: 800; }

  /* Cabeçalho */
  .head { display: flex; border: .8px solid #000; }
  .head .emit { flex: 1.4; padding: 6px 8px; border-right: .8px solid #000; }
  .head .emit .nome { font-size: 12px; font-weight: 800; margin: 2px 0; }
  .head .danfe-c { width: 150px; padding: 6px 6px; border-right: .8px solid #000; text-align: center; }
  .head .danfe-c .t { font-size: 15px; font-weight: 800; }
  .head .danfe-c .s { font-size: 7px; }
  .head .danfe-c .es { display: flex; justify-content: center; gap: 6px; margin: 4px 0; align-items: center; }
  .head .danfe-c .es .qd { border: .8px solid #000; width: 16px; height: 16px; display: inline-flex;
        align-items: center; justify-content: center; font-weight: 800; }
  .head .chave { flex: 1.3; padding: 6px 8px; }
  .barcode { height: 26px; background: repeating-linear-gradient(90deg,#000 0 2px,#fff 2px 4px,#000 4px 5px,#fff 5px 8px);
             margin-bottom: 3px; }
  .chavebox { border: .8px solid #000; padding: 3px 5px; font-size: 10px; font-weight: 700; letter-spacing: .5px;
              word-spacing: 2px; text-align: center; }

  .row { display: flex; } .row > .cell { flex: 1; }
  .prod th { border: .8px solid #000; background: #f0f0f0; font-size: 6.5px; padding: 3px 2px;
             text-transform: uppercase; }
  .prod td { border: .8px solid #000; padding: 2px 3px; font-size: 8.5px; }
  .prod td.c { text-align: center; } .prod td.r { text-align: right; white-space: nowrap; }
  .prod tbody { position: relative; z-index: 1; }

  .infbox { border: .8px solid #000; min-height: 60px; padding: 4px 6px; }
  .infbox .cap { margin-bottom: 3px; }
  .infcpl { font-size: 9px; line-height: 1.5; }
  .foot { color: #64748b; font-size: 9px; margin-top: 10px; line-height: 1.5; }

  @media print {
    body { background: #fff; padding: 0; }
    .danfe { box-shadow: none; max-width: none; padding: 0; }
    .toolbar { display: none !important; }
    .head, .prod tr, .canhoto { break-inside: avoid; }
  }
  @page { size: A4 portrait; margin: 8mm; }
</style>
</head>
<body>
  <div class="toolbar">
    <button class="btn" onclick="window.print()">Imprimir / Salvar como PDF</button>
    <button class="btn sec" onclick="window.close()">Fechar</button>
    <span class="hint">Para enviar ao fornecedor: <b>Imprimir → Destino: Salvar como PDF</b>.</span>
  </div>

  <div class="danfe">
    <div class="wm"><span>PRÉ-VISUALIZAÇÃO DA DANFE<br>SEM VALOR FISCAL</span></div>

    <!-- Canhoto -->
    <div class="canhoto">
      <div class="txt">
        RECEBEMOS DE <b>${esc(emitterName)}</b> OS PRODUTOS E/OU SERVIÇOS CONSTANTES DA NOTA FISCAL ELETRÔNICA INDICADA ABAIXO.
        <br><b>NF-e EM AMBIENTE DE ${ambiente} — PRÉ-VISUALIZAÇÃO SEM VALOR FISCAL.</b>
        <br><br>DATA DE RECEBIMENTO: ____/____/______ &nbsp;&nbsp; IDENTIFICAÇÃO E ASSINATURA DO RECEBEDOR: ______________________________
      </div>
      <div class="nfbox">
        <div>NF-e</div>
        <div class="nfbig">Nº ${esc(numeroFmt)}</div>
        <div>Série ${esc(serieFmt)}</div>
      </div>
    </div>

    <!-- Cabeçalho: emitente / DANFE / chave -->
    <div class="head">
      <div class="emit">
        <span class="cap">Identificação do emitente</span>
        <div class="nome">${esc(emitterName)}</div>
        <div>${esc(enderecoEmit || '—')}</div>
        <div>${esc(emitter?.district ? emitter.district + ' - ' : '')}${esc(emitter?.city_name || '')}${emitter?.state_code ? ' / ' + esc(emitter.state_code) : ''}</div>
        <div>CEP: ${esc(maskCep(emitter?.postal_code) || '—')}</div>
      </div>
      <div class="danfe-c">
        <div class="t">DANFE</div>
        <div class="s">Documento Auxiliar da Nota Fiscal Eletrônica</div>
        <div class="es">
          <span class="s">0-ENTRADA<br>1-SAÍDA</span>
          <span class="qd">${isSaida ? '1' : '0'}</span>
        </div>
        <div class="s bold">Nº ${esc(numeroFmt)}</div>
        <div class="s">Série ${esc(serieFmt)} · Folha 1/1</div>
        <div class="s" style="font-size:6px">(nº/série previstos — reserva na emissão)</div>
      </div>
      <div class="chave">
        <div class="barcode"></div>
        <span class="cap">Chave de acesso</span>
        <div class="chavebox">${chaveReal || 'gerada na autorização da SEFAZ'}</div>
        <div class="s" style="text-align:center;margin-top:3px">Consulta em www.nfe.fazenda.gov.br/portal</div>
      </div>
    </div>

    <!-- Natureza + protocolo -->
    <div class="row">
      <div class="cell" style="flex:2"><span class="cap">Natureza da operação</span><span class="val">${esc(payload?.nature_operation || '—')}</span></div>
      <div class="cell" style="flex:1.5"><span class="cap">Protocolo de autorização de uso</span><span class="val">— (gerado na autorização)</span></div>
    </div>
    <div class="row">
      <div class="cell"><span class="cap">Inscrição Estadual</span><span class="val">${esc(emitter?.state_registration || '—')}</span></div>
      <div class="cell"><span class="cap">Insc. Est. Subst. Trib.</span><span class="val">—</span></div>
      <div class="cell"><span class="cap">CNPJ / CPF</span><span class="val">${esc(maskDoc(emitter?.cnpj) || '—')}</span></div>
    </div>

    <!-- Destinatário -->
    <div class="cell b" style="background:#f0f0f0;font-weight:700;text-transform:uppercase;font-size:7px;padding:2px 4px">Destinatário / Remetente</div>
    <div class="row">
      <div class="cell" style="flex:2.4"><span class="cap">Nome / Razão social</span><span class="val">${esc(rec?.name || '—')}</span></div>
      <div class="cell"><span class="cap">CNPJ / CPF</span><span class="val">${esc(maskDoc(rec?.document) || '—')}</span></div>
      <div class="cell"><span class="cap">Data da emissão</span><span class="val">${esc(dataEmissao)}</span></div>
    </div>
    <div class="row">
      <div class="cell" style="flex:2.4"><span class="cap">Endereço</span><span class="val">${esc(enderecoDest || '—')}</span></div>
      <div class="cell"><span class="cap">Bairro / Distrito</span><span class="val">${esc(recAddr?.district || '—')}</span></div>
      <div class="cell"><span class="cap">CEP</span><span class="val">${esc(maskCep(recAddr?.postal_code) || '—')}</span></div>
    </div>
    <div class="row">
      <div class="cell"><span class="cap">Município</span><span class="val">${esc(recAddr?.city_name || '—')}</span></div>
      <div class="cell"><span class="cap">UF</span><span class="val">${esc(recAddr?.state_code || '—')}</span></div>
      <div class="cell"><span class="cap">Inscrição Estadual</span><span class="val">${esc(rec?.state_registration || '—')}</span></div>
      <div class="cell"><span class="cap">Data / hora saída</span><span class="val">${esc(dataEmissao)} ${esc(horaEmissao)}</span></div>
    </div>

    <!-- Fatura / Duplicata -->
    <div class="cell b" style="background:#f0f0f0;font-weight:700;text-transform:uppercase;font-size:7px;padding:2px 4px">Fatura / Duplicata</div>
    <div class="cell b" style="font-size:9px;padding:3px 5px">${faturaLinha}</div>
    ${duplicatasLinha ? `<div class="cell b" style="font-size:9px;padding:3px 5px"><span class="cap">Duplicatas</span>${duplicatasLinha}</div>` : ''}
    <div class="cell b" style="font-size:9px;padding:3px 5px"><span class="cap">Forma de pagamento</span>${pagamentosLinha}</div>

    <!-- Cálculo do imposto -->
    <div class="cell b" style="background:#f0f0f0;font-weight:700;text-transform:uppercase;font-size:7px;padding:2px 4px">Cálculo do imposto</div>
    <div class="row">
      <div class="cell r"><span class="cap">Base de cálculo do ICMS</span><span class="val">${brl(baseIcms)}</span></div>
      <div class="cell r"><span class="cap">Valor do ICMS</span><span class="val">${brl(totalIcms)}</span></div>
      <div class="cell r"><span class="cap">BC ICMS ST</span><span class="val">0,00</span></div>
      <div class="cell r"><span class="cap">Valor ICMS ST</span><span class="val">0,00</span></div>
      <div class="cell r"><span class="cap">Valor total dos produtos</span><span class="val">${brl(totalBruto)}</span></div>
    </div>
    <div class="row">
      <div class="cell r"><span class="cap">Valor do frete</span><span class="val">0,00</span></div>
      <div class="cell r"><span class="cap">Valor do seguro</span><span class="val">0,00</span></div>
      <div class="cell r"><span class="cap">Desconto</span><span class="val">${brl(totalDescItens)}</span></div>
      <div class="cell r"><span class="cap">Outras despesas</span><span class="val">${brl(totalOutroItens)}</span></div>
      <div class="cell r"><span class="cap">Valor total do IPI</span><span class="val">${brl(totalIpi)}</span></div>
      <div class="cell r" style="background:#fafafa"><span class="cap">Valor total da nota</span><span class="val" style="font-size:12px">${brl(totalNota)}</span></div>
    </div>

    <!-- Transportador -->
    <div class="cell b" style="background:#f0f0f0;font-weight:700;text-transform:uppercase;font-size:7px;padding:2px 4px">Transportador / Volumes transportados</div>
    <div class="row">
      <div class="cell" style="flex:2"><span class="cap">Nome / Razão social</span><span class="val">—</span></div>
      <div class="cell"><span class="cap">Frete por conta</span><span class="val">9 - Sem frete</span></div>
      <div class="cell"><span class="cap">Quantidade</span><span class="val">0</span></div>
      <div class="cell"><span class="cap">Peso líquido</span><span class="val">0,000</span></div>
    </div>

    <!-- Produtos -->
    <div class="cell b" style="background:#f0f0f0;font-weight:700;text-transform:uppercase;font-size:7px;padding:2px 4px">Dados dos produtos / serviços</div>
    <table class="prod">
      <thead>
        <tr>
          <th style="width:56px">Código</th><th>Descrição do produto / serviço</th>
          <th style="width:54px">NCM/SH</th><th style="width:34px">O/CST</th><th style="width:34px">CFOP</th>
          <th style="width:26px">UN</th><th style="width:44px">Quant.</th><th style="width:58px">V. unit.</th>
          <th style="width:62px">V. total</th><th style="width:58px">BC ICMS</th><th style="width:52px">V. ICMS</th>
          <th style="width:52px">V. IPI</th><th style="width:34px">Alíq ICMS</th><th style="width:34px">Alíq IPI</th>
        </tr>
      </thead>
      <tbody>${itemRows || '<tr><td colspan="14" class="c">Nenhum item</td></tr>'}</tbody>
    </table>

    <!-- Dados adicionais -->
    <div class="cell b" style="background:#f0f0f0;font-weight:700;text-transform:uppercase;font-size:7px;padding:2px 4px">Dados adicionais</div>
    <div class="infbox">
      <span class="cap">Informações complementares</span>
      <div class="infcpl">${infoCompl || '—'}</div>
    </div>

    <div class="foot">
      Espelho gerado pelo MarineFlow ERP a partir dos dados exatos que serão enviados na emissão. É uma
      <b>pré-visualização SEM VALOR FISCAL</b> — não é uma DANFE. A chave de acesso e o protocolo de autorização
      só existem depois que a NF-e é transmitida e autorizada pela SEFAZ (ambiente previsto: ${esc(ambiente)}).
    </div>
  </div>
</body>
</html>`;
}
