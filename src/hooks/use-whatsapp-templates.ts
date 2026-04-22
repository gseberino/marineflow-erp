import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export interface WhatsAppTemplate {
  id: string;
  name: string;
  category: string;
  body: string;
  active: boolean;
  sort_order: number;
}

export function useWhatsAppTemplates(category?: string) {
  return useQuery({
    queryKey: ['whatsapp-templates', category || 'all'],
    queryFn: async () => {
      let q = supabase
        .from('whatsapp_templates')
        .select('*')
        .eq('active', true)
        .order('sort_order', { ascending: true });
      if (category) q = q.eq('category', category);
      const { data, error } = await q;
      if (error) throw error;
      return data as WhatsAppTemplate[];
    },
  });
}

export function useAllWhatsAppTemplates() {
  return useQuery({
    queryKey: ['whatsapp-templates', 'admin'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('whatsapp_templates')
        .select('*')
        .order('category', { ascending: true })
        .order('sort_order', { ascending: true });
      if (error) throw error;
      return data as WhatsAppTemplate[];
    },
  });
}

export function useUpsertWhatsAppTemplate() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (t: Partial<WhatsAppTemplate> & { name: string; body: string; category: string }) => {
      if (t.id) {
        const { error } = await supabase.from('whatsapp_templates').update({
          name: t.name, body: t.body, category: t.category,
          active: t.active ?? true, sort_order: t.sort_order ?? 0,
        }).eq('id', t.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('whatsapp_templates').insert({
          name: t.name, body: t.body, category: t.category,
          active: t.active ?? true, sort_order: t.sort_order ?? 0,
        });
        if (error) throw error;
      }
    },
    onSuccess: () => {
      toast.success('Template salvo.');
      qc.invalidateQueries({ queryKey: ['whatsapp-templates'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao salvar template.'),
  });
}

export function useDeleteWhatsAppTemplate() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('whatsapp_templates').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Template removido.');
      qc.invalidateQueries({ queryKey: ['whatsapp-templates'] });
    },
  });
}

/**
 * Substitui placeholders {chave} OU {{chave}} por valores no texto.
 * - Aceita ambas as sintaxes para retro-compatibilidade.
 * - Números em campos monetários conhecidos são formatados em BRL (450 → "450,00").
 * - Datas ISO (YYYY-MM-DD) viram "DD/MM/YYYY".
 * - Placeholders desconhecidos são preservados intactos.
 */
export function applyTemplateVariables(
  body: string,
  vars: Record<string, string | number | undefined | null>,
): string {
  const formatValue = (key: string, v: unknown): string => {
    if (v === undefined || v === null || v === '') return `{${key}}`;
    if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}/.test(v)) {
      const [y, m, d] = v.split('T')[0].split('-');
      return `${d}/${m}/${y}`;
    }
    if (typeof v === 'number' || (typeof v === 'string' && /^-?\d+(\.\d+)?$/.test(v))) {
      const monetaryKeys = ['valor', 'total', 'amount', 'subtotal', 'desconto'];
      if (monetaryKeys.includes(key.toLowerCase())) {
        return Number(v).toLocaleString('pt-BR', {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        });
      }
    }
    return String(v);
  };
  return body
    .replace(/\{\{\s*(\w+)\s*\}\}/g, (_m, key) => formatValue(key, vars[key]))
    .replace(/\{(\w+)\}/g, (_m, key) => formatValue(key, vars[key]));
}

/**
 * Catálogo central de variáveis suportadas em templates de WhatsApp.
 * Usado pela UI do editor para mostrar ao usuário quais placeholders existem
 * e como ficará o resultado ao serem substituídos.
 */
export interface TemplateVariableDoc {
  key: string;
  label: string;
  description: string;
  example: string;
  contexts: Array<'service_order' | 'quote' | 'billing' | 'general'>;
}

export const TEMPLATE_VARIABLES: TemplateVariableDoc[] = [
  {
    key: 'cliente',
    label: 'Nome do cliente',
    description: 'Nome completo ou razão social do cliente.',
    example: 'José Nelson Seberino da Silva',
    contexts: ['service_order', 'quote', 'billing', 'general'],
  },
  {
    key: 'os',
    label: 'Número da OS',
    description: 'Número da Ordem de Serviço vinculada (sinônimo: numero_os).',
    example: 'OS-2026-0042',
    contexts: ['service_order', 'quote', 'billing'],
  },
  {
    key: 'descricao',
    label: 'Descrição',
    description: 'Descrição da OS (problema relatado) ou da cobrança.',
    example: 'Manutenção preventiva do motor',
    contexts: ['service_order', 'quote', 'billing'],
  },
  {
    key: 'valor',
    label: 'Valor (R$)',
    description: 'Valor monetário formatado em reais com 2 casas decimais.',
    example: '1.250,00',
    contexts: ['quote', 'billing'],
  },
  {
    key: 'vencimento',
    label: 'Data de vencimento',
    description: 'Data de vencimento no formato DD/MM/YYYY.',
    example: '29/04/2026',
    contexts: ['billing'],
  },
  {
    key: 'link',
    label: 'Link público do documento',
    description: 'URL para o cliente abrir o documento (OS, orçamento ou cobrança) no navegador.',
    example: 'https://hbrmarine.online/view/abc123…',
    contexts: ['service_order', 'quote', 'billing'],
  },
  {
    key: 'empresa',
    label: 'Nome da empresa',
    description: 'Nome da sua empresa (configurado em Ajustes).',
    example: 'HBR Marine',
    contexts: ['service_order', 'quote', 'billing', 'general'],
  },
  {
    key: 'pix',
    label: 'Chave PIX',
    description: 'Chave PIX da empresa (apenas em cobranças via PIX/transferência).',
    example: '12.345.678/0001-90',
    contexts: ['billing'],
  },
];

