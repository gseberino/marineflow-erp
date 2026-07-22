// Espelho / Pré-DANFE — pré-visualização SEM VALOR FISCAL de uma NF-e antes da
// emissão. Renderizado pelo próprio sistema a partir do payload EXATO que seria
// enviado ao provedor (impostos por item e CFOP já resolvidos no servidor), sem
// nenhuma chamada à SEFAZ.
//
// Por que renderizar aqui em vez de pedir o PDF ao provedor: a DANFE só existe
// depois da autorização (ela estampa o protocolo da SEFAZ) — antes disso não há
// PDF válido para baixar. É o mesmo caminho dos ERPs de mercado, que chamam isso
// de "pré-nota"/"Pré-DANFE" (Omie), ou "visualizar a DANFE antes da emissão"
// (Conta Azul, NF-Easy): um documento de conferência marcado "SEM VALOR FISCAL".
//
// Função pura (string HTML) → fácil de testar e de abrir numa aba para o usuário
// conferir e salvar como PDF (Ctrl+P → Salvar como PDF).

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

// tPag do leiaute NF-e 4.00 — inclui o 14 (Duplicata Mercantil), usado quando a
// nota tem grupo de cobrança (fatura + duplicatas).
const TPAG_LABELS: Record<string, string> = {
  '01': 'Dinheiro',
  '02': 'Cheque',
  '03': 'Cartão de Crédito',
  '04': 'Cartão de Débito',
  '05': 'Crédito Loja',
  '10': 'Vale Alimentação',
  '11': 'Vale Refeição',
  '12': 'Vale Presente',
  '13': 'Vale Combustível',
  '14': 'Duplicata Mercantil',
  '15': 'Boleto Bancário',
  '16': 'Depósito Bancário',
  '17': 'PIX',
  '18': 'Transferência bancária / Carteira digital',
  '19': 'Programa de fidelidade / Cashback',
  '90': 'Sem Pagamento',
  '99': 'Outros',
};

const IE_INDICATOR_LABELS: Record<string, string> = {
  '1': 'Contribuinte do ICMS',
  '2': 'Isento de Inscrição Estadual',
  '9': 'Não contribuinte',
};

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
  if (!Number.isFinite(v)) return '—';
  return v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
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
  return d || '—';
}

function maskCep(digits: unknown): string {
  const d = String(digits ?? '').replace(/\D/g, '');
  return d.length === 8 ? d.replace(/^(\d{5})(\d{3})$/, '$1-$2') : (d || '—');
}

function addressLine(a: {
  street?: unknown; number?: unknown; complement?: unknown; district?: unknown;
  city_name?: unknown; state_code?: unknown; postal_code?: unknown;
}): string {
  const parts = [
    [a.street, a.number].filter(Boolean).join(', '),
    a.complement,
    a.district,
    [a.city_name, a.state_code].filter(Boolean).join(' - '),
    a.postal_code ? `CEP ${maskCep(a.postal_code)}` : '',
  ].filter((p) => p && String(p).trim());
  return parts.join(' · ');
}

function itemTotal(it: Record<string, any>): number {
  return Number(it?.quantity ?? 0) * Number(it?.unit_price ?? 0);
}

/** Rótulo da forma de pagamento de um item do grupo `payments`. */
function paymentLabel(method: unknown): string {
  const code = String(method ?? '').padStart(2, '0');
  return TPAG_LABELS[code] ? `${code} — ${TPAG_LABELS[code]}` : (code || '—');
}

/**
 * Monta o documento HTML do espelho (pré-DANFE). Autocontido: sem CSS/JS
 * externo, pronto para abrir numa aba e salvar como PDF.
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
  const totalProdutos = items.reduce((s, it) => s + itemTotal(it), 0);
  const payments: Record<string, any>[] = Array.isArray(payload?.payments) ? payload.payments : [];
  const billing = payload?.billing ?? null;
  const duplicatas: Record<string, any>[] = Array.isArray(billing?.installments) ? billing.installments : [];
  const rec = payload?.recipient ?? {};
  const recAddr = rec?.address ?? {};
  const when = opts.generatedAt ?? new Date();
  const isProducao = String(opts.environment ?? '') === 'producao';

  const itemRows = items.map((it, i) => {
    const t = it?.taxes ?? {};
    const icms = t?.icms ?? {};
    const impostos = [
      icms?.code ? `CSOSN ${esc(icms.code)}` : '',
      icms?.origin != null ? `Orig. ${esc(icms.origin)}` : '',
      Number(icms?.aliquot) > 0 ? `ICMS ${num(icms.aliquot, 2)}%` : '',
      Number(t?.ipi?.aliquot) > 0 ? `IPI ${num(t.ipi.aliquot, 2)}%` : '',
      Number(t?.pis?.aliquot) > 0 ? `PIS ${num(t.pis.aliquot, 2)}%` : '',
      Number(t?.cofins?.aliquot) > 0 ? `COFINS ${num(t.cofins.aliquot, 2)}%` : '',
    ].filter(Boolean).join(' · ');
    const ref = it?.referenced_document
      ? `<div class="ref">Ref. NF-e ${esc(it.referenced_document.access_key)} · item ${esc(it.referenced_document.item)}</div>`
      : '';
    return `<tr>
      <td class="c">${i + 1}</td>
      <td>${esc(it?.code)}</td>
      <td>${esc(it?.name)}${ref}<div class="tax">${impostos || '&nbsp;'}</div></td>
      <td class="c">${esc(it?.ncm)}</td>
      <td class="c">${esc(it?.cfop)}</td>
      <td class="c">${esc(it?.unit)}</td>
      <td class="r">${num(it?.quantity)}</td>
      <td class="r">${brl(it?.unit_price)}</td>
      <td class="r b">${brl(itemTotal(it))}</td>
    </tr>`;
  }).join('');

  const duplicataRows = duplicatas.map((d) => `<tr>
      <td class="c">${esc(d?.number)}</td>
      <td class="c">${dateBR(d?.due_date)}</td>
      <td class="r b">${brl(d?.amount)}</td>
    </tr>`).join('');

  const cobrancaBloco = billing
    ? `<div class="box">
        <div class="box-title">Fatura / Duplicatas</div>
        <div class="grid3">
          <div><span class="lbl">Fatura nº</span>${esc(billing?.invoice?.number)}</div>
          <div><span class="lbl">Valor original</span>${brl(billing?.invoice?.original_amount)}</div>
          <div><span class="lbl">Desconto</span>${brl(billing?.invoice?.discount_amount)}</div>
          <div><span class="lbl">Valor líquido</span><b>${brl(billing?.invoice?.net_amount)}</b></div>
        </div>
        <table class="tbl dup">
          <thead><tr><th>Parcela</th><th>Vencimento</th><th>Valor</th></tr></thead>
          <tbody>${duplicataRows}</tbody>
        </table>
      </div>`
    : '';

  const pagamentosLinha = payments.length
    ? payments.map((p) => `${paymentLabel(p?.method)} — ${brl(p?.amount)}`).join('<br>')
    : '—';

  // O quadro começa direto pelo conteúdo, igual ao DANFE. A Contora imprimia um
  // rótulo "Inf. Contribuinte:" antes do infCpl; a pedido nosso, criaram uma
  // preferência por CNPJ que o suprime (já ativa para a HBR) — o rótulo era
  // redundante com o título do próprio quadro. Se o espelho continuasse
  // mostrando o rótulo, voltaria a divergir do papel.
  //
  // O ";" é convertido em quebra de linha visual pelo DANFE (confirmado pela
  // Contora) — o espelho faz o mesmo, senão mostraria em linha corrida algo que
  // sairá quebrado no papel. Dividir ANTES de escapar: entidades HTML
  // (&lt; &gt; &amp;) terminam em ";", então trocar depois do escape o corromperia.
  const infCplHtml = String(payload?.additional_info ?? '')
    .split(/;[ \t]*/)
    .map((parte) => esc(parte))
    .join('<br>');
  const infoAdicional = payload?.additional_info
    ? `<div class="box">
        <div class="box-title">Dados adicionais / Informações complementares</div>
        <div class="infcpl">${infCplHtml}</div>
      </div>`
    : '';

  const emitterName = emitter?.legal_name || emitter?.trade_name || '(empresa não configurada)';

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Espelho NF-e — ${esc(rec?.name || 'pré-visualização')}</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, "Segoe UI", Roboto, Arial, sans-serif; margin: 0; padding: 16px;
         background: #f1f5f9; color: #0f172a; font-size: 12px; }
  .sheet { max-width: 820px; margin: 0 auto; background: #fff; padding: 20px 22px 28px;
           box-shadow: 0 1px 4px rgba(0,0,0,.12); }
  .toolbar { max-width: 820px; margin: 0 auto 12px; display: flex; gap: 8px; align-items: center; }
  .btn { background: #0f172a; color: #fff; border: 0; border-radius: 6px; padding: 8px 14px;
         font-size: 13px; font-weight: 600; cursor: pointer; }
  .btn.sec { background: #fff; color: #0f172a; border: 1px solid #cbd5e1; }
  .hint { color: #475569; font-size: 12px; }
  .banner { border: 2px dashed #b91c1c; color: #b91c1c; text-align: center; padding: 10px;
            font-weight: 800; letter-spacing: .5px; font-size: 15px; margin-bottom: 4px; }
  .banner small { display: block; font-weight: 500; letter-spacing: 0; font-size: 11px; margin-top: 4px; color: #7f1d1d; }
  .meta { display: flex; justify-content: space-between; color: #64748b; font-size: 10.5px; margin: 6px 2px 14px; }
  .box { border: 1px solid #94a3b8; margin-bottom: 10px; }
  .box-title { background: #e2e8f0; border-bottom: 1px solid #94a3b8; padding: 4px 8px;
               font-weight: 700; font-size: 10.5px; text-transform: uppercase; letter-spacing: .4px; }
  .box > .pad { padding: 8px; }
  .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 14px; padding: 8px; }
  .grid3 { display: grid; grid-template-columns: repeat(4, 1fr); gap: 4px 14px; padding: 8px; }
  .lbl { display: block; color: #64748b; font-size: 9.5px; text-transform: uppercase; letter-spacing: .3px; }
  .tbl { width: 100%; border-collapse: collapse; }
  .tbl th { background: #f1f5f9; border-top: 1px solid #94a3b8; border-bottom: 1px solid #94a3b8;
            padding: 5px 6px; font-size: 9.5px; text-transform: uppercase; letter-spacing: .3px; text-align: left; }
  .tbl td { border-bottom: 1px solid #e2e8f0; padding: 5px 6px; vertical-align: top; }
  .tbl .c { text-align: center; }
  .tbl .r { text-align: right; white-space: nowrap; }
  .tbl .b { font-weight: 700; }
  .tax { color: #64748b; font-size: 9.5px; margin-top: 2px; }
  .ref { color: #7c3aed; font-size: 9.5px; margin-top: 2px; }
  .dup { margin-top: 2px; }
  .dup th, .dup td { font-size: 11px; }
  .totais { display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px 14px; padding: 8px; }
  .total-nota { font-size: 15px; font-weight: 800; }
  .infcpl { padding: 8px; white-space: pre-wrap; line-height: 1.45; }
  .foot { margin-top: 14px; color: #64748b; font-size: 10px; line-height: 1.5; border-top: 1px solid #e2e8f0; padding-top: 8px; }
  @media print {
    body { background: #fff; padding: 0; font-size: 10.5px; }
    .sheet { box-shadow: none; max-width: none; padding: 0; }
    .toolbar { display: none !important; }
    .box { break-inside: avoid; }
    tr { break-inside: avoid; }
  }
  @page { size: A4 portrait; margin: 12mm; }
</style>
</head>
<body>
  <div class="toolbar">
    <button class="btn" onclick="window.print()">Imprimir / Salvar como PDF</button>
    <button class="btn sec" onclick="window.close()">Fechar</button>
    <span class="hint">Para enviar ao cliente/fornecedor: <b>Imprimir → Destino: Salvar como PDF</b>.</span>
  </div>

  <div class="sheet">
    <div class="banner">
      ESPELHO — PRÉ-VISUALIZAÇÃO SEM VALOR FISCAL
      <small>Documento de conferência. Não é uma DANFE. A NF-e só terá valor fiscal após ser transmitida e autorizada pela SEFAZ.</small>
    </div>
    <div class="meta">
      <span>Gerado em ${esc(when.toLocaleString('pt-BR'))}</span>
      <span>${opts.number ? `NF-e nº ${esc(opts.number)} · série ${esc(opts.series ?? '')} (previsto) · ` : ''}${isProducao ? 'emissão em PRODUÇÃO' : 'emissão em homologação'}</span>
    </div>

    <div class="box">
      <div class="box-title">Emitente</div>
      <div class="grid2">
        <div><span class="lbl">Razão social</span>${esc(emitterName)}</div>
        <div><span class="lbl">CNPJ</span>${maskDoc(emitter?.cnpj)}</div>
        <div><span class="lbl">Inscrição Estadual</span>${esc(emitter?.state_registration || '—')}</div>
        <div><span class="lbl">Regime tributário</span>${esc(emitter?.tax_regime || '—')}${emitter?.crt != null ? ` (CRT ${esc(emitter.crt)})` : ''}</div>
        <div style="grid-column: 1 / -1"><span class="lbl">Endereço</span>${esc(addressLine({
          street: emitter?.street, number: emitter?.number, complement: emitter?.complement,
          district: emitter?.district, city_name: emitter?.city_name, state_code: emitter?.state_code,
          postal_code: emitter?.postal_code,
        }) || '—')}</div>
      </div>
    </div>

    <div class="box">
      <div class="box-title">Operação</div>
      <div class="grid3">
        <div><span class="lbl">Natureza da operação</span>${esc(payload?.nature_operation || '—')}</div>
        <div><span class="lbl">Tipo</span>${esc(payload?.operation_type === 'entrada' ? 'Entrada' : 'Saída')}</div>
        <div><span class="lbl">Finalidade</span>${payload?.purpose === 4 ? 'Devolução' : payload?.purpose === 3 ? 'Ajuste' : payload?.purpose === 2 ? 'Complementar' : 'Normal'}</div>
        <div><span class="lbl">Consumidor final</span>${payload?.consumer_final ? 'Sim' : 'Não'}</div>
      </div>
    </div>

    <div class="box">
      <div class="box-title">Destinatário</div>
      <div class="grid2">
        <div><span class="lbl">Nome / Razão social</span>${esc(rec?.name || '—')}</div>
        <div><span class="lbl">CNPJ / CPF</span>${maskDoc(rec?.document)}</div>
        <div><span class="lbl">Indicador de IE</span>${esc(IE_INDICATOR_LABELS[String(rec?.state_registration_indicator ?? '9')] || '—')}</div>
        <div><span class="lbl">Inscrição Estadual</span>${esc(rec?.state_registration || '—')}</div>
        <div style="grid-column: 1 / -1"><span class="lbl">Endereço</span>${esc(addressLine(recAddr) || '—')}</div>
      </div>
    </div>

    <div class="box">
      <div class="box-title">Produtos / Serviços</div>
      <table class="tbl">
        <thead>
          <tr>
            <th style="width:24px">#</th><th style="width:78px">Código</th><th>Descrição</th>
            <th style="width:70px">NCM</th><th style="width:46px">CFOP</th><th style="width:36px">Un</th>
            <th style="width:58px">Qtd</th><th style="width:82px">Vl. unit.</th><th style="width:88px">Total</th>
          </tr>
        </thead>
        <tbody>${itemRows || '<tr><td colspan="9" class="c">Nenhum item</td></tr>'}</tbody>
      </table>
    </div>

    <div class="box">
      <div class="box-title">Totais</div>
      <div class="totais">
        <div><span class="lbl">Total dos produtos</span>${brl(totalProdutos)}</div>
        <div><span class="lbl">Desconto</span>${brl(billing?.invoice?.discount_amount ?? 0)}</div>
        <div><span class="lbl">Total da nota</span><span class="total-nota">${brl(billing?.invoice?.net_amount ?? totalProdutos)}</span></div>
      </div>
    </div>

    <div class="box">
      <div class="box-title">Pagamento</div>
      <div class="pad">${pagamentosLinha}</div>
    </div>

    ${cobrancaBloco}
    ${infoAdicional}

    <div class="foot">
      Este espelho foi gerado pelo MarineFlow ERP a partir dos dados exatos que serão enviados na emissão
      (impostos por item e CFOP já calculados). Números de nota, chave de acesso e protocolo de autorização
      só existem depois que a NF-e é transmitida e autorizada pela SEFAZ — por isso não constam aqui.
    </div>
  </div>
</body>
</html>`;
}
