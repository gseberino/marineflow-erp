// Informações complementares (infCpl) da NF-e para emitente do Simples Nacional.
//
// Regra fiscal por trás deste arquivo:
// - A declaração "DOCUMENTO EMITIDO POR ME OU EPP OPTANTE PELO SIMPLES NACIONAL"
//   é OBRIGATÓRIA (Resolução CGSN 140/2018, art. 60).
// - A frase que afirma o aproveitamento do crédito de ICMS só é válida com
//   **CSOSN 101** (tributada COM permissão de crédito) E os campos `pCredSN`
//   (alíquota) e `vCredICMSSN` (valor) preenchidos, e o texto precisa trazer o
//   VALOR em R$ e a ALÍQUOTA em % (art. 23 da LC 123/2006). Uma frase genérica
//   ("conforme a legislação") não transfere crédito nenhum.
// - Com **CSOSN 102** (tributada SEM permissão de crédito) essa frase é
//   CONTRADITÓRIA: o XML declara que não há crédito e o texto afirma o contrário.
//
// Versões antigas do sistema gravaram a frase inválida no infCpl. Como duplicar/
// reemitir uma nota reaproveita o texto da nota anterior, o erro se propagaria
// para notas novas — por isso a normalização abaixo.

export const SIMPLES_INFO_NOTE =
  'Documento emitido por ME ou EPP optante pelo Simples Nacional. ' +
  'Não gera direito a crédito fiscal de IPI.';

// Frase legada (e variações): termina na referência à LC 123/2006, que pode vir
// entre parênteses. O ponto de "art. 23" impede um corte ingênuo por sentença.
const LEGACY_ICMS_CREDIT_CLAIMS: RegExp[] = [
  /\s*Permite\s+o\s+aproveitamento\s+do\s+cr[ée]dito\s+de\s+ICMS[\s\S]*?123\s*\/\s*2006\s*\)?\s*\.?/gi,
  /\s*Permite\s+o\s+aproveitamento\s+do\s+cr[ée]dito\s+de\s+ICMS[^)]*\)\s*\.?/gi,
];

/** Remove a afirmação de crédito de ICMS inválida para CSOSN 102. */
export function stripInvalidIcmsCreditClaim(text: string): string {
  let out = String(text ?? '');
  for (const re of LEGACY_ICMS_CREDIT_CLAIMS) out = out.replace(re, '');
  return out.replace(/[ \t]{2,}/g, ' ').trim();
}

// Declaração do Simples em QUALQUER redação já usada pelo sistema — a antiga
// ("optante DO Simples Nacional") e a atual ("ME ou EPP optante PELO Simples
// Nacional") —, com ou sem a frase do IPI logo em seguida.
//
// Removemos todas e reinserimos UMA vez na redação canônica. Só *detectar* a
// declaração não bastava: a variante antiga escapava do teste de presença e a
// declaração acabava ANEXADA, saindo duplicada na nota.
const SIMPLES_DECLARATIONS =
  /Documento\s+emitido\s+por\s+(?:ME\s+ou\s+EPP\s+)?optante\s+(?:pelo|pela|do|da|de)\s+Simples\s+Nacional\s*\.?\s*(?:N[ãa]o\s+gera\s+direito\s+a\s+cr[ée]dito\s+fiscal\s+de\s+IPI\s*\.?)?/gi;

/**
 * Separador entre os blocos do infCpl — ";" (confirmado pela Contora).
 *
 * O infCpl não aceita caracteres de formatação (CR/LF/TAB): quebra literal é
 * causa conhecida de Rejeição 215 (falha no schema) e 588 (caractere de
 * controle), e uma emissão rejeitada já consumiu o número reservado (lacuna que
 * exige inutilização). Por isso NUNCA emitimos "\n" aqui.
 *
 * A Contora confirmou o comportamento do DANFE deles:
 *   - ";" é convertido em QUEBRA DE LINHA visual na impressão;
 *   - "|" NÃO é convertido — sairia impresso literalmente (era o que fazíamos);
 *   - a API até aceita "\n" em additional_info, mas ela própria sanitiza para
 *     ";" antes de gerar o XML — mandar ";" direto deixa o que gravamos idêntico
 *     ao que vai no XML (sem divergência entre payload salvo e documento).
 */
export const BLOCK_SEPARATOR = '; ';

/**
 * Iniciar o infCpl com o separador (para o conteúdo cair na linha de baixo).
 *
 * DESLIGADO — não é mais necessário. Histórico: o DANFE da Contora imprimia o
 * rótulo "Inf. Contribuinte:" grudado no início do infCpl. O prefixo era do
 * renderizador DELES (nunca do nosso XML: o `additional_info` que enviamos nunca
 * conteve rótulo) e era redundante com o título do quadro "INFORMAÇÕES
 * COMPLEMENTARES" do layout oficial. Levamos o caso à Contora e eles
 * implementaram uma **preferência por CNPJ que suprime o prefixo**, já ativada
 * para a HBR — só o PDF do DANFE muda; XML, assinatura e validade seguem iguais.
 *
 * Eles confirmaram que o ";" inicial *é* preservado na normalização, mas
 * recomendaram enviar o conteúdo direto, sem ele — o que fazemos agora.
 * Religar apenas se algum provedor voltar a prefixar o quadro.
 */
export const START_CONTENT_ON_NEW_LINE = false;

// Delimitador de bloco aceito ao LER textos já gravados: ";" (atual) ou "|"
// (usado brevemente antes da confirmação da Contora).
const DELIM = '[;|]';

// Segmentos "Pedido de Compra: …" / "Comprador: …" que NÓS compomos — sempre no
// início do texto ou logo após um separador de blocos. A âncora inicial evita
// engolir um "Comprador:" que o usuário tenha escrito no meio do texto dele.
const PURCHASE_SEGMENTS = new RegExp(
  `(?:^|${DELIM})\\s*(?:Pedido\\s+de\\s+Compra|Comprador)\\s*:[^;|]*`,
  'gi',
);

function tidy(text: string): string {
  return text
    // Quebras digitadas pelo usuário viram o separador de blocos: assim elas
    // aparecem como linhas no DANFE, sem jamais colocar CR/LF no XML.
    .replace(/[\r\n\t]+/g, BLOCK_SEPARATOR)
    .replace(new RegExp(`\\s*${DELIM}\\s*(?=${DELIM})`, 'g'), '') // separadores em sequência
    .replace(new RegExp(`^\\s*${DELIM}\\s*`), '')
    .replace(new RegExp(`\\s*${DELIM}\\s*$`), '')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

/** Remove o bloco de pedido/comprador já composto (evita duplicá-lo ao recompor). */
export function stripPurchaseBlock(text: string | null | undefined): string {
  return tidy(String(text ?? '').replace(PURCHASE_SEGMENTS, ''));
}

/**
 * Devolve só o texto do USUÁRIO: sem a declaração do Simples e sem a frase
 * inválida de crédito de ICMS — os blocos que o sistema gerencia e reinsere.
 * É o que deve aparecer no campo editável da tela.
 */
export function stripManagedBlocks(text: string | null | undefined): string {
  return tidy(
    stripInvalidIcmsCreditClaim(String(text ?? '')).replace(SIMPLES_DECLARATIONS, ''),
  );
}

/**
 * Monta o infCpl na ordem fixa, por contrato:
 *   1) Pedido de Compra / Comprador   2) texto livre   3) declaração do Simples.
 * A declaração obrigatória fica SEMPRE por último, e os dados do cliente
 * sempre primeiro — sem depender de como o usuário digitou.
 */
export function composeAdditionalInfo(input: {
  purchaseOrder?: string | null;
  buyer?: string | null;
  freeText?: string | null;
}): string {
  const purchase = [
    input.purchaseOrder?.trim() ? `Pedido de Compra: ${input.purchaseOrder.trim()}` : '',
    input.buyer?.trim() ? `Comprador: ${input.buyer.trim()}` : '',
  ].filter(Boolean).join(' - ');

  const managed = stripManagedBlocks(input.freeText);
  // Só limpamos o bloco de pedido quando vamos reinseri-lo — assim um texto
  // livre legado que contenha "Comprador: ..." não é apagado à toa.
  const free = purchase ? stripPurchaseBlock(managed) : managed;

  const corpo = [purchase, free, SIMPLES_INFO_NOTE].filter(Boolean).join(BLOCK_SEPARATOR);
  return START_CONTENT_ON_NEW_LINE ? `${BLOCK_SEPARATOR}${corpo}` : corpo;
}

/**
 * Normaliza um infCpl existente (duplicar/reemitir, devoluções): tira a frase de
 * crédito de ICMS inválida, remove qualquer redação da declaração do Simples e
 * devolve o texto com a declaração obrigatória UMA única vez, ao final.
 * Preserva o texto livre do usuário.
 */
export function normalizeAdditionalInfo(text: string | null | undefined): string {
  return composeAdditionalInfo({ freeText: text });
}

// "R$ " montado à mão de propósito: o style:'currency' do toLocaleString insere
// um espaço NÃO-QUEBRÁVEL (U+00A0) antes do número. Ele não é caractere de
// controle, então passaria pelo cleanText e iria parar no XML fiscal — melhor
// não arriscar num campo que a SEFAZ valida por charset.
function brl(v: number): string {
  return 'R$ ' + v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// YYYY-MM-DD -> DD/MM/YYYY sem passar por Date (evita o deslocamento de fuso
// que mostraria o dia anterior).
function dataBR(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso ?? ''));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : '';
}

/**
 * Texto de dados adicionais de uma DEVOLUÇÃO AO FORNECEDOR.
 *
 * Reproduz o que o fornecedor precisa para se creditar (formato pedido pela
 * Kamell): referência à nota de compra original e os valores de ICMS e IPI
 * destacados nela. Emitente do Simples Nacional não destaca ICMS/IPI na nota —
 * por isso os valores vão informados aqui, e o IPI entra em "despesas
 * acessórias" (outras despesas) para o total da devolução fechar com a compra.
 *
 * Cada bloco é separado por ";" → vira uma linha no DANFE.
 */
export function buildDevolucaoInfo(input: {
  noteNumber?: string | null;
  noteSeries?: string | null;
  issueDate?: string | null; // YYYY-MM-DD
  accessKey?: string | null;
  icmsValue?: number | null;
  ipiValue?: number | null;
  partial?: boolean;
}): string {
  const partes: string[] = [];

  const numero = String(input.noteNumber ?? '').trim();
  if (numero) {
    // "40480" -> "40.480", como o fornecedor escreve na conferência.
    const numeroFmt = /^\d+$/.test(numero) ? Number(numero).toLocaleString('pt-BR') : numero;
    const serie = String(input.noteSeries ?? '').trim();
    const data = dataBR(String(input.issueDate ?? ''));
    partes.push(
      `Devolução ${input.partial === false ? 'Total' : 'Parcial'} Ref. NF-e nº ${numeroFmt}` +
      (serie ? `, série ${serie}` : '') +
      (data ? `, de ${data}` : ''),
    );
  }

  const chave = String(input.accessKey ?? '').replace(/\D/g, '');
  if (chave.length === 44) partes.push(`Chave de acesso da NF-e de origem: ${chave}`);

  if (input.icmsValue != null && input.icmsValue > 0) {
    partes.push(`Valor do ICMS para crédito do destinatário: ${brl(input.icmsValue)}`);
  }
  if (input.ipiValue != null && input.ipiValue > 0) {
    partes.push(
      `Valor do IPI para crédito do destinatário (informado no campo despesas acessórias): ${brl(input.ipiValue)}`,
    );
  }

  return partes.join(BLOCK_SEPARATOR);
}
