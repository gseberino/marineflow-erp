// Número da OS sem "OS " repetido nas telas.
//
// O service_order_number já traz o prefixo: "OS-00060" diz OS e "ORÇ-00112" diz orçamento
// (conferido em produção em 12/10/2026: 49 "OS-" e 64 "ORÇ-", nenhum sem prefixo). Pôr "OS " ou
// "OS #" na frente dá "OS OS-00060" — e "OS ORÇ-00112", que ainda chama orçamento de OS.
//
// POR QUE ISTO É UMA VARREDURA: o defeito voltava a cada tela nova escrita com o hábito antigo, e
// vários pontos são textos que não se veem num render barato (o push ao técnico atribuído no
// ServiceOrderForm, a conta a pagar da comissão na tela legada). Os pontos com comportamento que
// se vê têm teste próprio: FaturarOsDialog.smoke, SendViaWhatsAppDialog.validade (nome do PDF),
// use-agenda.conflito, OnMyWayButton, ActiveProspectingPage, CommissionsV2.descricao e
// ServiceOrderList (aria-label).
//
// Fica de fora, de propósito: FinanceReviewInbox.rotuloDaOS (tira o "OS-" antes de pôr "OS ") e
// textos com "OS " seguido de valor ou status, que não são o número.
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

const RAIZ = process.cwd();

/** "OS " ou "OS #" logo antes de uma interpolação (template `${…}` ou JSX `{…}`) do número. */
const OS_ANTES_DO_NUMERO =
  /OS #?\$?\{[^}]*(service_order_number|serviceOrderNumber|orderNumber|os\.numero|c\.label)[^}]*\}/g;
/** A variável {os} dos modelos por cliente (link e nome do PDF) já é o número com prefixo. */
const OS_ANTES_DA_VARIAVEL = /OS[ -]#?\{os\}/g;

function achados(texto: string): string[] {
  return [...texto.matchAll(OS_ANTES_DO_NUMERO), ...texto.matchAll(OS_ANTES_DA_VARIAVEL)].map((m) => m[0]);
}

function arquivosDe(dir: string): string[] {
  const saida: string[] = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) saida.push(...arquivosDe(p));
    else if (/\.tsx?$/.test(e.name) && !/\.test\.|\.smoke\./.test(e.name)) saida.push(p);
  }
  return saida;
}

// Os pontos corrigidos em 12/10/2026, um por um: cada linha falhava antes da correção.
const PONTOS: Array<[arquivo: string, onde: string]> = [
  ['src/components/fiscal/FaturarOsDialog.tsx', 'título "Faturar OS-00060"'],
  ['src/components/ServiceOrderForm.tsx', 'push ao técnico atribuído (criar e editar)'],
  ['src/components/agenda/OnMyWayButton.tsx', 'confirmação do "A caminho"'],
  ['src/hooks/use-agenda.ts', 'conflictMessage'],
  ['src/pages/ActiveProspectingPage.tsx', 'cartão, pedido à IA e rascunho ao cliente'],
  ['src/pages/CommissionsPage.tsx', 'descrição GRAVADA na conta a pagar (tela legada)'],
  ['src/v2/pages/CommissionsV2.tsx', 'descrição GRAVADA na conta a pagar'],
  ['src/pages/ServiceOrderList.tsx', 'aria-label "Mais ações da OS-00060"'],
  ['src/components/ClientFormDialog.tsx', 'exemplos do título do link e do nome do PDF por cliente'],
];

describe('número da OS sem "OS " repetido — varredura das telas', () => {
  it.each(PONTOS)('%s — %s', (arquivo) => {
    const texto = fs.readFileSync(path.join(RAIZ, arquivo), 'utf8');
    expect(achados(texto)).toEqual([]);
  });

  it('nenhum arquivo de src/ põe "OS " na frente do número', () => {
    const encontrados = arquivosDe(path.join(RAIZ, 'src')).flatMap((p) =>
      achados(fs.readFileSync(p, 'utf8')).map((a) => `${path.relative(RAIZ, p)}: ${a}`),
    );
    expect(encontrados).toEqual([]);
  });

  it('a varredura acha o padrão antigo (o portão não está cego)', () => {
    expect(achados('body: `Você foi atribuído à OS ${form.service_order_number ?? ""}`')).toHaveLength(1);
    expect(achados('<DialogTitle>Faturar OS {orderNumber ?? d?.os.numero}</DialogTitle>')).toHaveLength(1);
    expect(achados('description: `Comissão OS #${c.service_orders?.service_order_number} - x`')).toHaveLength(1);
    expect(achados('placeholder="OS-{os}-{cliente}.pdf"')).toHaveLength(1);
    // O que não é o número não conta.
    expect(achados('`OS ${formatCurrency(total)} · ${data}`')).toEqual([]);
    expect(achados("`OS ${numero.replace(/^OS-?/i, '')}`")).toEqual([]);
  });
});
