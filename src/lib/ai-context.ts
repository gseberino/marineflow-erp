import { useLocation, useParams } from 'react-router-dom';

export type AIContext = {
  route: string;
  entityType?: string;
  entityId?: string;
};

// O prefixo /v2 é opcional e NÃO captura: m[1] continua sendo o id. Sem ele, nas telas novas
// (/v2/clients/:id, /v2/vessels/:id, /v2/service-orders/:id) o assistente não recebia a ficha
// aberta (defeito achado na revisão de 21/10/2026; decisão 5 do dono, 22/10/2026).
const ROUTE_ENTITY_MAP: Array<{ pattern: RegExp; type: string }> = [
  { pattern: /^(?:\/v2)?\/clients\/([0-9a-f-]{36})/i, type: 'client' },
  { pattern: /^(?:\/v2)?\/vessels\/([0-9a-f-]{36})/i, type: 'vessel' },
  { pattern: /^(?:\/v2)?\/service-orders\/([0-9a-f-]{36})/i, type: 'service_order' },
  // /collections leva a /v2/collections, que leva a /v2/receivables/cobrancas (App.tsx)
  { pattern: /^(?:(?:\/v2)?\/collections|\/v2\/receivables\/cobrancas)/i, type: 'collections' },
  { pattern: /^(?:\/v2)?\/financial/i, type: 'financial' },
  { pattern: /^(?:\/v2)?\/whatsapp\/leads/i, type: 'whatsapp_leads' },
  { pattern: /^(?:\/v2)?\/agenda/i, type: 'agenda' },
  { pattern: /^(?:\/v2)?\/products/i, type: 'products' },
];

/** A parte pura: da rota (e do :id da rota, se houver) à entidade que o assistente recebe. */
export function contextoDaRota(route: string, idDaRota?: string): AIContext {
  for (const { pattern, type } of ROUTE_ENTITY_MAP) {
    const m = route.match(pattern);
    if (m) return { route, entityType: type, entityId: m[1] };
  }
  if (idDaRota) return { route, entityType: 'unknown', entityId: idDaRota };
  return { route };
}

export function useAIContext(): AIContext {
  const location = useLocation();
  const params = useParams();
  return contextoDaRota(location.pathname, params.id);
}
