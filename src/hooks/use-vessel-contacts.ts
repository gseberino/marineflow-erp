import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export const VESSEL_CONTACT_ROLES = [
  { value: 'owner', label: 'Proprietário' },
  { value: 'captain', label: 'Comandante' },
  { value: 'sailor', label: 'Marinheiro' },
  { value: 'manager', label: 'Administrador' },
  { value: 'mechanic', label: 'Mecânico responsável' },
  { value: 'contact', label: 'Contato geral' },
];

export function useVesselContacts(vesselId: string | undefined) {
  return useQuery({
    queryKey: ['vessel-contacts', vesselId],
    queryFn: async () => {
      if (!vesselId) return [];
      const { data, error } = await supabase
        .from('vessel_contacts')
        .select('*')
        .eq('vessel_id', vesselId)
        .eq('active', true)
        .order('full_name');
      if (error) throw error;
      return data || [];
    },
    enabled: !!vesselId,
  });
}

export function useCreateVesselContact() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      vessel_id: string;
      full_name: string;
      role: string;
      phone?: string;
      email?: string;
      notes?: string;
    }) => {
      const { data, error } = await supabase
        .from('vessel_contacts')
        .insert(input)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: (data) => {
      qc.invalidateQueries({ queryKey: ['vessel-contacts', data.vessel_id] });
    },
  });
}
