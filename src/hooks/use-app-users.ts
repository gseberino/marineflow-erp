import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export const USER_ROLES = [
  { value: 'admin', label: 'Administrador' },
  { value: 'technician', label: 'Técnico' },
  { value: 'financial', label: 'Financeiro' },
  { value: 'seller', label: 'Vendedor / Indicador' },
  { value: 'other', label: 'Outro' },
];

export function useAppUsers() {
  return useQuery({
    queryKey: ['app-users'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_users')
        .select('*')
        .eq('active', true)
        .order('full_name');
      if (error) throw error;
      return data || [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useCommissionableUsers() {
  return useQuery({
    queryKey: ['app-users-commissionable'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_users')
        .select('id, full_name, role, email')
        .eq('active', true)
        .order('full_name');
      if (error) throw error;
      return data || [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useCreateAppUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      full_name: string; email: string; role: string; phone?: string;
    }) => {
      const { data, error } = await supabase
        .from('app_users')
        .insert({ ...input, id: crypto.randomUUID() })
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['app-users'] });
      qc.invalidateQueries({ queryKey: ['app-users-commissionable'] });
    },
  });
}

export function useUpdateAppUser() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...input }: {
      id: string; full_name?: string; email?: string;
      role?: string; phone?: string; active?: boolean;
    }) => {
      const { data, error } = await supabase
        .from('app_users')
        .update(input)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['app-users'] });
      qc.invalidateQueries({ queryKey: ['app-users-commissionable'] });
    },
  });
}
