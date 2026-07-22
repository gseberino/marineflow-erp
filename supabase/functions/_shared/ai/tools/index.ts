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
import { crmTools } from "./crm.ts";
import { fieldOpsTools } from "./field-ops.ts";
import { autonomyTools } from "./autonomy.ts";
import { contactTools } from "./contacts.ts";
import { entityMemoryTools } from "./entity-memory.ts";
import { fiscalEmitTools } from "./fiscal-emit.ts";
import { entity360Tools } from "./entity-360.ts";
import { registryCrudTools } from "./registry-crud.ts";
import { referenceDataTools } from "./reference-data.ts";
import { whatsappTools } from "./whatsapp.ts";
import { uiTools } from "./ui.ts";
import { memoryTools } from "./memory.ts";

export type { ToolDef, ToolCtx, RiskLevel, Role } from "./registry.ts";

// Ordenadas por nome — ordem determinística é o que mantém o prefixo de tools
// estável entre turnos e permite cache hit no bloco de tools da Anthropic.
export const allTools: ToolDef[] = [
  ...clientTools,
  ...vesselTools,
  ...productTools,
  ...serviceOrderTools,
  ...agendaTools,
  ...financialTools,
  ...reportTools,
  ...purchasingTools,
  ...fiscalTools,
  ...quoteTools,
  ...crmTools,
  ...fieldOpsTools,
  ...autonomyTools,
  ...entity360Tools,
  ...registryCrudTools,
  ...referenceDataTools,
  ...contactTools,
  ...entityMemoryTools,
  ...fiscalEmitTools,
  ...whatsappTools,
  ...uiTools,
  ...memoryTools,
].sort((a, b) => a.name.localeCompare(b.name));

export const toolsByName: Record<string, ToolDef> = Object.fromEntries(allTools.map((t) => [t.name, t]));
