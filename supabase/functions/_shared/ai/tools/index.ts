import type { ToolDef } from "./registry.ts";
import { clientTools } from "./clients.ts";
import { vesselTools } from "./vessels.ts";
import { productTools } from "./products.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { agendaTools } from "./agenda.ts";
import { financialTools } from "./financial.ts";
import { reportTools } from "./reports.ts";
import { purchasingTools } from "./purchasing.ts";
import { whatsappTools } from "./whatsapp.ts";
import { uiTools } from "./ui.ts";

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
  ...whatsappTools,
  ...uiTools,
].sort((a, b) => a.name.localeCompare(b.name));

export const toolsByName: Record<string, ToolDef> = Object.fromEntries(allTools.map((t) => [t.name, t]));
