// Os destinos da busca Ctrl+K: os lugares do sistema e, desde 26/09/2026, os apelidos com os
// nomes antigos das abas do Financeiro, levando ao lugar novo. Separado da paleta para ser
// testado (todo destino tem de abrir uma tela de verdade).
import type { LucideIcon } from 'lucide-react';
import {
  Anchor, ArrowLeftRight, BarChart3, Boxes, Building2, CalendarDays, ClipboardList, CornerDownRight,
  DollarSign, FileText, Landmark, LayoutDashboard, MessageCircle, Package, Receipt, Settings, Ship,
  Sparkles, Target, TrendingDown, TrendingUp, Truck, Users, Wrench,
} from 'lucide-react';

export type ItemDaPaleta = {
  label: string;
  to: string;
  icon: LucideIcon;
  /** Outras palavras que acham o item (sinônimos, nome antigo). */
  keywords?: string[];
  /** Para apelido de nome antigo: onde a coisa mora agora, escrito ao lado. */
  onde?: string;
};

export const NAV: { group: string; items: ItemDaPaleta[] }[] = [
  {
    group: 'Operacional',
    items: [
      { label: 'Dashboard', to: '/v2/dashboard', icon: LayoutDashboard },
      { label: 'CRM & Funil', to: '/v2/crm', icon: Target },
      { label: 'Ordens de Serviço', to: '/v2/service-orders', icon: ClipboardList },
      { label: 'Orçamentos', to: '/v2/quotes', icon: FileText },
      { label: 'Agenda', to: '/v2/agenda', icon: CalendarDays },
    ],
  },
  {
    group: 'Cadastros',
    items: [
      { label: 'Clientes', to: '/v2/clients', icon: Users },
      { label: 'Embarcações', to: '/v2/vessels', icon: Ship },
      { label: 'Marinas', to: '/v2/marinas', icon: Anchor },
      { label: 'Produtos', to: '/v2/products', icon: Package },
      { label: 'Serviços', to: '/v2/services', icon: Wrench },
      { label: 'Fornecedores', to: '/v2/suppliers', icon: Building2 },
      { label: 'Contas bancárias', to: '/v2/financial/banks', icon: Landmark, keywords: ['banco', 'conexão', 'saldo'] },
    ],
  },
  {
    // 26/09/2026: um cômodo por assunto — os mesmos destinos do menu lateral.
    group: 'Financeiro',
    items: [
      { label: 'Visão Geral do Financeiro', to: '/v2/financial', icon: DollarSign, keywords: ['financeiro', 'saldo'] },
      { label: 'Extrato', to: '/v2/financial/inbox', icon: Sparkles, keywords: ['banco', 'revisar', 'caixa de entrada'] },
      { label: 'Conciliação', to: '/v2/financial/reconciliation', icon: ArrowLeftRight },
      { label: 'Contas a Receber', to: '/v2/receivables', icon: TrendingUp, keywords: ['recebíveis'] },
      { label: 'Contas a Pagar', to: '/v2/financial/payables', icon: TrendingDown, keywords: ['pagáveis', 'boletos'] },
      { label: 'Despesas', to: '/v2/financial/despesas', icon: Receipt, keywords: ['gastos'] },
      { label: 'Emissão Fiscal (NF-e)', to: '/v2/fiscal/emissao', icon: Receipt },
      { label: 'Notas de Serviço (NFS-e)', to: '/fiscal/nfse', icon: Receipt },
    ],
  },
  {
    group: 'Central de relatórios',
    items: [
      { label: 'Central de relatórios', to: '/v2/reports', icon: BarChart3, keywords: ['relatórios', 'demonstrativos'] },
      { label: 'Resumo do mês', to: '/v2/reports', icon: BarChart3 },
      { label: 'Fluxo de caixa', to: '/v2/reports/fluxo', icon: BarChart3, keywords: ['previsão', '8 semanas'] },
      { label: 'Resultado (DRE)', to: '/v2/reports/dre', icon: BarChart3, keywords: ['lucro', 'prejuízo'] },
      { label: 'Para onde foi o dinheiro', to: '/v2/reports/categorias', icon: BarChart3, keywords: ['despesas por categoria'] },
      { label: 'Quem deve e a quem devo', to: '/v2/reports/aging', icon: BarChart3, keywords: ['atraso', 'inadimplência'] },
      { label: 'Operação', to: '/v2/reports/operacao', icon: BarChart3, keywords: ['OS', 'técnicos', 'peças', 'lucratividade'] },
    ],
  },
  {
    // As abas que mudaram de lugar em 26/09/2026. Quem digita o nome de ontem chega ao lugar
    // de hoje — e vê, ao lado, onde ele mora agora.
    group: 'Nomes antigos',
    items: [
      { label: 'DRE', to: '/v2/reports/dre', icon: CornerDownRight, onde: 'Central de relatórios › Resultado (DRE)' },
      { label: 'Aging', to: '/v2/reports/aging', icon: CornerDownRight, onde: 'Central de relatórios › Quem deve e a quem devo', keywords: ['idade das contas'] },
      { label: 'Programação', to: '/v2/reports/fluxo', icon: CornerDownRight, onde: 'Central de relatórios › Fluxo de caixa' },
      { label: 'Gerenciais', to: '/v2/reports/operacao', icon: CornerDownRight, onde: 'Central de relatórios › Operação' },
      { label: 'Cartões', to: '/v2/financial/inbox/cartao', icon: CornerDownRight, onde: 'Extrato › Cartão de crédito', keywords: ['fatura'] },
      { label: 'Regras', to: '/v2/financial/inbox/regras', icon: CornerDownRight, onde: 'Extrato › Regras' },
      { label: 'Fechamento', to: '/v2/financial/reconciliation/fechar', icon: CornerDownRight, onde: 'Conciliação › Fechar o mês' },
      { label: 'Saúde do cadastro', to: '/v2/suppliers/saude', icon: CornerDownRight, onde: 'Fornecedores › Saúde do cadastro' },
      { label: 'Cobranças', to: '/v2/receivables/cobrancas', icon: CornerDownRight, onde: 'Contas a Receber › Cobranças' },
      { label: 'Comissões', to: '/v2/financial/payables/comissoes', icon: CornerDownRight, onde: 'Contas a Pagar › Comissões' },
      { label: 'Reembolsos', to: '/v2/financial/payables/reembolsos', icon: CornerDownRight, onde: 'Contas a Pagar › Reembolsos' },
      { label: 'Recebíveis', to: '/v2/receivables', icon: CornerDownRight, onde: 'Contas a Receber' },
    ],
  },
  {
    group: 'Estoque & Compras',
    items: [
      { label: 'Estoque', to: '/v2/inventory', icon: Boxes },
      { label: 'Ordens de Compra', to: '/v2/purchase-orders', icon: Truck },
      { label: 'Assistente de Compras', to: '/v2/inventory/smart-purchase', icon: Package },
      { label: 'Entrada de Mercadoria (XML)', to: '/v2/inventory/import-xml', icon: FileText },
    ],
  },
  {
    group: 'Sistema',
    items: [
      { label: 'WhatsApp — Inbox', to: '/v2/whatsapp/leads', icon: MessageCircle },
      { label: 'Configurações', to: '/v2/settings', icon: Settings },
    ],
  },
];
