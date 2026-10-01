import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { inputLocalParaIso } from '@/lib/datetime-local';
import {
  linhasParaGravar, registroDaVia, juntarNotas, type LancamentoDaVia,
} from '@/lib/lancar-via';

/**
 * Grava o que veio no papel da via do técnico: situação de cada serviço, chegada e saída,
 * o relato nas notas do técnico e o material além do previsto nas notas internas (somados
 * ao que já existia). Ver `src/lib/lancar-via.ts`.
 */
export function useLancarVia() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: {
      orderId: string;
      notasAtuais: string | null | undefined;
      notasInternasAtuais?: string | null;
      lancamento: LancamentoDaVia;
    }) => {
      const linhas = linhasParaGravar(args.lancamento);
      for (const linha of linhas) {
        const { error } = await supabase
          .from('service_order_services')
          .update({ field_status: linha.field_status, field_status_note: linha.field_status_note })
          .eq('id', linha.id);
        if (error) throw error;
      }

      const patch: {
        check_in_at?: string; check_out_at?: string; technician_notes?: string; internal_notes?: string;
      } = {};
      const chegada = inputLocalParaIso(args.lancamento.chegada);
      const saida = inputLocalParaIso(args.lancamento.saida);
      if (chegada) patch.check_in_at = chegada;
      if (saida) patch.check_out_at = saida;
      const registro = registroDaVia(args.lancamento, new Date());
      if (registro.tecnico) patch.technician_notes = juntarNotas(args.notasAtuais, registro.tecnico);
      if (registro.interno) patch.internal_notes = juntarNotas(args.notasInternasAtuais, registro.interno);

      if (Object.keys(patch).length) {
        const { error } = await supabase.from('service_orders').update(patch).eq('id', args.orderId);
        if (error) throw error;
      }
      return {
        servicos: linhas.length,
        technicianNotes: patch.technician_notes,
        internalNotes: patch.internal_notes,
      };
    },
    onSuccess: (_r, args) => {
      qc.invalidateQueries({ queryKey: ['so-services', args.orderId] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
  });
}
