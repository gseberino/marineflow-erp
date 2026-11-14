// A via do técnico mudou para supabase/functions/_shared/pdf/via-do-tecnico.ts (13/11/2026): o
// assistente do WhatsApp e a agenda mandam a mesma folha em PDF. Aqui fica só o que é de navegador.
import { buildRouteSheetHtml, type RouteSheetHeader, type RouteSheetExtras } from '../../supabase/functions/_shared/pdf/via-do-tecnico';
import type { ServiceOrderStep, RouteMaterial } from '../../supabase/functions/_shared/pdf/via-do-tecnico';

export * from '../../supabase/functions/_shared/pdf/via-do-tecnico';

/** Abre a folha em nova janela e chama a impressão. */
export function printRouteSheet(
  header: RouteSheetHeader,
  steps: ServiceOrderStep[],
  materials: RouteMaterial[] = [],
  extras: RouteSheetExtras = {},
): boolean {
  const win = window.open('', '_blank', 'width=900,height=1000');
  if (!win) return false; // bloqueador de pop-up; quem chama avisa o usuário
  win.document.write(buildRouteSheetHtml(header, steps, materials, extras));
  win.document.close();
  win.focus();
  // Deixa o layout (e o logo) assentarem antes de abrir o diálogo de impressão.
  win.setTimeout(() => win.print(), 400);
  return true;
}
