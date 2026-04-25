import { useLocation, useParams } from 'react-router-dom';

export type AIContext = {
  route: string;
  entityType?: string;
  entityId?: string;
};

const ROUTE_ENTITY_MAP: Array<{ pattern: RegExp; type: string }> = [
  { pattern: /^\/clients\/([0-9a-f-]{36})/i, type: 'client' },
  { pattern: /^\/vessels\/([0-9a-f-]{36})/i, type: 'vessel' },
  { pattern: /^\/service-orders\/([0-9a-f-]{36})/i, type: 'service_order' },
];

export function useAIContext(): AIContext {
  const location = useLocation();
  const params = useParams();
  const route = location.pathname;

  for (const { pattern, type } of ROUTE_ENTITY_MAP) {
    const m = route.match(pattern);
    if (m) return { route, entityType: type, entityId: m[1] };
  }
  if (params.id) return { route, entityType: 'unknown', entityId: params.id };
  return { route };
}
