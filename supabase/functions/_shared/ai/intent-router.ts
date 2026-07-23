// Roteador de Intenção (Onda 5A) — envia ao modelo só as tools do DOMÍNIO detectado, para
// cortar o bloco de tools (cache) e melhorar o foco. SEGURO por construção:
//  - todas as tools de LEITURA (search_/list_/get_) e as essenciais ficam SEMPRE (core);
//  - só tools de ESCRITA de domínios NÃO detectados são removidas;
//  - em qualquer dúvida (nenhum domínio, 3+ domínios, sobrou pouca coisa) → retorna null =
//    "envie TUDO" (comportamento atual, zero risco).
// Fica atrás de um flag (ai_intent_router) DESLIGADO por padrão.

export const DOMINIOS = ["financeiro", "compras", "agenda", "cadastro", "fiscal", "comunicacao", "crm", "campo"] as const;
export type Dominio = typeof DOMINIOS[number];

function norm(s: string): string {
  return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

const SINAIS: Record<Dominio, RegExp> = {
  financeiro: /cobr|receb|pagar|pagamento|paguei|vencid|inadimpl|fatur|caixa|financ|comiss|sinal|deposito|pix|parcel|\bdre\b|margem/,
  compras: /cotac|cota[çc]|fornecedor|compra|ordem de compra|\boc\b|suprimento|orcar com/,
  agenda: /agenda|agendar|horario|marcar|remarcar|compromisso|calendario|disponib/,
  cadastro: /cadastr|cri(ar|a|e)\s+(um |uma )?(cliente|produto|fornecedor|servi[çc]o|ve[íi]culo|barco|marina|ativo)|(cliente|produto|fornecedor|ativo) novo|novo (cliente|produto|fornecedor)|atualiz|corrig|pre[çc]o do produto|\bncm\b|editar cadastro/,
  fiscal: /nota fiscal|nf-?e|nfs-?e|sefaz|danfe|emitir nota|espelho|fiscal|imposto/,
  comunicacao: /whatsapp|mensagem|enviar|mandar|responder|follow-?up|lembrete|avisar|inbox|caixa de entrada/,
  crm: /manuten|revis[ãa]o|reativ|cliente sumido|parado h|oportunidade|prospec/,
  campo: /cheguei|comecei|terminei|check-?in|check-?out|estou no|no barco|foto do servi/,
};

/** Domínios detectados na mensagem (pode ser vazio). */
export function detectarDominios(texto: string): Dominio[] {
  const n = norm(texto);
  return DOMINIOS.filter((d) => SINAIS[d].test(n));
}

// Tools que são CORE (sempre enviadas): toda leitura + um punhado de essenciais de escrita.
const ESSENCIAIS = new Set<string>([
  "present_options", "create_quote_from_items", "get_situation_overview",
  "interpret_customer_reply", "check_followup_cadence", "agent_health_report",
]);
export function ehCore(nome: string): boolean {
  return /^(search_|list_|get_)/.test(nome) || ESSENCIAIS.has(nome);
}

// Tag de domínio de uma tool de ESCRITA, por padrão de nome.
const REGRAS_TOOL: Array<{ d: Dominio; re: RegExp }> = [
  { d: "financeiro", re: /payment|receivable|payable|collection|commission|deposit|delinquency|register_payment|financ|charges/ },
  { d: "compras", re: /quote_request|supplier|purchase_order|apply_quote_price|record_quote_response|suggest_suppliers/ },
  { d: "agenda", re: /agenda|schedule_service_order|technician_availability|schedule_whatsapp|schedule_self/ },
  { d: "cadastro", re: /create_(client|product|vessel|supplier|service)|update_(client|product|vessel|supplier|service)|learn_product_alias/ },
  { d: "fiscal", re: /fiscal|emit_|nota/ },
  { d: "comunicacao", re: /whatsapp|send_|collection_reminder|mute_|link_contact|identify_contact|optimize_text/ },
  { d: "crm", re: /maintenance|inactive|untouched|reactiv/ },
  { d: "campo", re: /check_in|check_out|log_service_order_progress|attach_photo/ },
];
export function dominiosDaTool(nome: string): Dominio[] {
  return REGRAS_TOOL.filter((r) => r.re.test(nome)).map((r) => r.d);
}

/** Nº mínimo de tools abaixo do qual desconfiamos do corte e mandamos tudo. */
export const MIN_TOOLS = 30;

/**
 * Subconjunto de tools para esta mensagem, ou null = envie TODAS (fallback seguro).
 * Nunca remove leitura; só remove escrita de domínios não pedidos.
 */
export function filtrarTools(texto: string, nomes: string[]): Set<string> | null {
  const doms = detectarDominios(texto);
  if (doms.length === 0 || doms.length >= 3) return null; // inseguro → tudo
  const permit = new Set<string>();
  for (const n of nomes) {
    if (ehCore(n)) { permit.add(n); continue; }
    const td = dominiosDaTool(n);
    if (td.length === 0 || td.some((d) => doms.includes(d))) permit.add(n); // sem tag → mantém (seguro)
  }
  if (permit.size < MIN_TOOLS || permit.size >= nomes.length) return null; // cortou pouco/nada → tudo
  return permit;
}
