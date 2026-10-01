import { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Input } from '@/components/ui/input';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';

/** As situações que a via mostra no cartão do serviço. As três últimas vêm do papel. */
export const SITUACOES_NA_VIA: Array<{ value: string; label: string }> = [
  { value: 'a_fazer', label: 'A fazer' },
  { value: 'so_levantar', label: 'Só levantar (não executar)' },
  { value: 'aguarda_peca', label: 'Aguarda peça' },
  { value: 'feito', label: 'Já feito' },
  { value: 'parcial', label: 'Parcial' },
  { value: 'nao_feito', label: 'Não feito' },
];

/**
 * Como esta linha sai na via do técnico: a situação (a fazer, só levantar, aguarda peça…)
 * e uma instrução curta só para o técnico. Grava direto na linha, como a classificação
 * de sistema logo acima — não depende do Salvar da OS.
 */
export function LineViaTecnico({
  line, orderId,
}: {
  line: { id: string; field_status?: string | null; technician_instructions?: string | null };
  orderId: string;
}) {
  const qc = useQueryClient();
  const [instrucao, setInstrucao] = useState(line.technician_instructions ?? '');
  useEffect(() => { setInstrucao(line.technician_instructions ?? ''); }, [line.id, line.technician_instructions]);

  async function gravar(patch: { field_status?: string; technician_instructions?: string | null }) {
    const { error } = await supabase.from('service_order_services').update(patch).eq('id', line.id);
    if (error) {
      toast.error(error.message || 'Não deu para gravar na linha');
      return;
    }
    qc.invalidateQueries({ queryKey: ['so-services', orderId] });
  }

  return (
    <div className="mt-1.5 flex flex-wrap items-center gap-2 text-xs">
      <span className="text-muted-foreground">Na via do técnico:</span>
      <Select value={line.field_status || 'a_fazer'} onValueChange={(v) => gravar({ field_status: v })}>
        <SelectTrigger className="h-7 w-[190px] text-xs" aria-label="Situação na via do técnico">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {SITUACOES_NA_VIA.map((s) => (
            <SelectItem key={s.value} value={s.value} className="text-xs">{s.label}</SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Input
        className="h-7 min-w-[12rem] flex-1 text-xs"
        aria-label="Instrução ao técnico para este serviço"
        placeholder="Instrução ao técnico para este serviço (opcional)"
        value={instrucao}
        onChange={(e) => setInstrucao(e.target.value)}
        onBlur={() => {
          const novo = instrucao.trim() || null;
          if (novo !== (line.technician_instructions || null)) void gravar({ technician_instructions: novo });
        }}
      />
    </div>
  );
}
