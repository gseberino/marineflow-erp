import type { ToolDef } from "./registry.ts";
import { clientTools } from "./clients.ts";
import { vesselTools } from "./vessels.ts";
import { productTools } from "./products.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { agendaTools } from "./agenda.ts";
import { financialTools } from "./financial.ts";
import { reportTools } from "./reports.ts";
import { purchasingTools } from "./purchasing.ts";
import { fiscalTools } from "./fiscal.ts";
import { quoteTools } from "./quotes.ts";
import { quoteBuilderTools } from "./quote-builder.ts";
import { crmTools } from "./crm.ts";
import { fieldOpsTools } from "./field-ops.ts";
import { routeOpsTools } from "./route-ops.ts";
import { soOpsTools } from "./so-ops.ts";
import { surveyOpsTools } from "./survey-ops.ts";
import { routeDraftingTools } from "./route-drafting.ts";
import { materialsOpsTools } from "./materials-ops.ts";
import { autonomyTools } from "./autonomy.ts";
import { contactTools } from "./contacts.ts";
import { entityMemoryTools } from "./entity-memory.ts";
import { fiscalEmitTools } from "./fiscal-emit.ts";
import { entity360Tools } from "./entity-360.ts";
import { registryCrudTools } from "./registry-crud.ts";
import { referenceDataTools } from "./reference-data.ts";
import { whatsappTools } from "./whatsapp.ts";
import { whatsappHistoryTools } from "./whatsapp-history.ts";
import { documentoPdfTools } from "./documentos-pdf.ts";
import { relatorioTools } from "./relatorios.ts";
import { emailTools } from "./email.ts";
import { uiTools } from "./ui.ts";
import { memoryTools } from "./memory.ts";
import { learningTools } from "./learning.ts";
import { overviewTools } from "./overview.ts";
import { flowMacroTools } from "./flow-macros.ts";
import { commsTools } from "./comms-tools.ts";
import { biTools } from "./bi.ts";
import { bomTools } from "./bom.ts";
import { statusTools } from "./status-tools.ts";
import { bankingTools } from "./banking.ts";
import { financeRulesTools } from "./finance-rules.ts";
import { lancamentoTools } from "./lancamentos.ts";
import { fechamentoTools } from "./fechamento.ts";
import { caixaTools } from "./caixa.ts";
// Diárias de freelancers (28/09/2026): substituem as 5 de jornada, que nunca foram chamadas (D7).
import { diariasTools } from "./diarias.ts";
import { followupTools } from "./followups.ts";
import { condicaoPagamentoTools } from "./condicao-pagamento.ts";
import { acompanhamentoTools } from "./acompanhamento.ts";
// operacional (07/10/2026): caixa de sugestões da agenda (listar, aceitar, descartar).
import { agendaSugestaoTools } from "./agenda-sugestoes.ts";
// financeiro (07/10/2026): anotações de Pix, estorno, cobrança formal e favorecido.
import { anotacaoTools } from "./anotacoes.ts";
import { estornoTools } from "./estorno.ts";
import { cobrancaTools } from "./cobrancas.ts";
import { favorecidoTools } from "./favorecidos.ts";
// fiscal e compras (07/10/2026): PDF da nota pelo WhatsApp; OC e cotação até o fim.
import { notaFiscalPdfTools } from "./nota-fiscal-pdf.ts";
import { comprasCicloTools } from "./compras-ciclo.ts";
// planos de manutenção (07/10/2026): planos, lembretes de revisão ao cliente (com o sim do dono) e métricas.
import { planosManutencaoTools } from "./planos-manutencao.ts";
// Dropbox (08/10/2026): buscar arquivos do barco, a pasta do barco e mandar um PDF para quem pede.
import { dropboxTools } from "./dropbox.ts";
// Comprovantes (F2, 11/10/2026): consultar o que o fluxo de comprovantes fez (só leitura).
import { comprovanteTools } from "./comprovantes.ts";
// Agrupar orçamentos (15/10/2026): listar os candidatos, agrupar e desagrupar (paridade com a tela).
import { agruparOrcamentosTools } from "./agrupar-orcamentos.ts";
// O lote semanal da papelada (16/10/2026, secretário Passo 5): só pela pendência do comando *lote*.
import { papeladaTools } from "./papelada.ts";

export type { ToolDef, ToolCtx, RiskLevel, Role } from "./registry.ts";

// Ordenadas por nome — ordem determinística é o que mantém o prefixo de tools
// estável entre turnos e permite cache hit no bloco de tools da Anthropic.
export const allTools: ToolDef[] = [
  ...clientTools,
  ...vesselTools,
  ...productTools,
  ...serviceOrderTools,
  ...condicaoPagamentoTools,
  ...agendaTools,
  ...financialTools,
  ...reportTools,
  ...purchasingTools,
  ...fiscalTools,
  ...quoteTools,
  ...quoteBuilderTools,
  ...crmTools,
  ...fieldOpsTools,
  ...routeOpsTools,
  ...soOpsTools,
  ...surveyOpsTools,
  ...routeDraftingTools,
  ...materialsOpsTools,
  ...autonomyTools,
  ...entity360Tools,
  ...registryCrudTools,
  ...referenceDataTools,
  ...contactTools,
  ...entityMemoryTools,
  ...fiscalEmitTools,
  ...whatsappTools,
  ...whatsappHistoryTools,
  ...acompanhamentoTools,
  ...documentoPdfTools,
  ...dropboxTools,
  ...relatorioTools,
  ...emailTools,
  ...uiTools,
  ...memoryTools,
  ...learningTools,
  ...overviewTools,
  ...flowMacroTools,
  ...commsTools,
  ...biTools,
  ...bomTools,
  ...statusTools,
  ...bankingTools,
  ...financeRulesTools,
  ...lancamentoTools,
  ...fechamentoTools,
  ...caixaTools,
  ...diariasTools,
  ...followupTools,
  // operacional (07/10/2026)
  ...agendaSugestaoTools,
  // financeiro (07/10/2026)
  ...anotacaoTools,
  ...estornoTools,
  ...cobrancaTools,
  ...favorecidoTools,
  // fiscal e compras (07/10/2026)
  ...notaFiscalPdfTools,
  ...comprasCicloTools,
  // planos de manutenção (07/10/2026)
  ...planosManutencaoTools,
  // comprovantes (11/10/2026)
  ...comprovanteTools,
  // agrupar orçamentos (15/10/2026)
  ...agruparOrcamentosTools,
].sort((a, b) => a.name.localeCompare(b.name));

/**
 * (16/10/2026, secretário Passo 5) Tools que só rodam por uma pendência aberta por um comando determinístico — nunca
 * pelo modelo: ficam FORA de allTools (a lista que vai ao modelo, e o prefixo cacheado não muda) e entram só no mapa
 * de execução das pendências (approveAndExecutePendingAction).
 */
export const toolsSoPelaPendencia: ToolDef[] = [...papeladaTools];

export const toolsByName: Record<string, ToolDef> = Object.fromEntries(
  [...allTools, ...toolsSoPelaPendencia].map((t) => [t.name, t]),
);
