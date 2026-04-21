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
 * Substitui placeholders {chave} por valores no texto.
 * Placeholders desconhecidos são preservados.
 */
export function applyTemplateVariables(body: string, vars: Record<string, string | number | undefined | null>): string {
  return body.replace(/\{(\w+)\}/g, (_m, key) => {
    const v = vars[key];
    return v === undefined || v === null ? `{${key}}` : String(v);
  });
}
