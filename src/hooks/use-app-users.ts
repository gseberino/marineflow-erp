import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface AppUser {
  id: string;
  full_name: string;
  email: string;
  role: string;
  phone?: string | null;
  active: boolean;
  avatar_url?: string | null;
  postal_code?: string | null;
  address_line_1?: string | null;
  address_number?: string | null;
  address_complement?: string | null;
  neighborhood?: string | null;
  city?: string | null;
  state?: string | null;
  country?: string | null;
  notes?: string | null;
  // Novos campos de RH
  cpf?: string | null;
  rg?: string | null;
  birth_date?: string | null;
  hiring_date?: string | null;
  resignation_date?: string | null;
  department?: string | null;
  salary_base?: number | null;
  pix_key?: string | null;
  emergency_contact_name?: string | null;
  emergency_contact_phone?: string | null;
  metadata?: any;
}

export const USER_ROLES = [
  { value: 'admin', label: 'Administrador' },
  { value: 'technician', label: 'Técnico' },
  { value: 'financial', label: 'Financeiro' },
  { value: 'seller', label: 'Vendedor / Indicador' },
  { value: 'external_seller', label: 'Vendedor Externo' },
  { value: 'other', label: 'Outro' },
];

export function useAppUsers() {
  return useQuery({
    queryKey: ['app-users'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_users')
        .select('*')
        .order('full_name');
      if (error) throw error;
      return data as AppUser[];
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
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (user: Omit<AppUser, 'id' | 'active'>) => {
      const { data, error } = await supabase
        .from('app_users')
        .insert([{ ...user, id: crypto.randomUUID(), active: true } as any])
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['app-users'] });
      queryClient.invalidateQueries({ queryKey: ['app-users-commissionable'] });
    },
  });
}

export function useUpdateAppUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (user: Partial<AppUser> & { id: string }) => {
      const { id, ...changes } = user;
      const { data, error } = await supabase
        .from('app_users')
        .update(changes as any)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['app-users'] });
      queryClient.invalidateQueries({ queryKey: ['app-users-commissionable'] });
    },
  });
}
