import { useEffect, useId, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { usePayees } from '@/hooks/use-payees';
import {
  LIMITE_SUAVE_DA_INSTRUCAO, normalizarInstrucao, problemaDaInstrucao, type SugestaoDeInstrucao,
} from '@/lib/instrucoes-sugeridas';

/** Quem pode fazer o serviço: a equipe de campo (comissionado é venda). O mesmo critério do assistente. */
const TIPOS_DA_EQUIPE = new Set(['socio', 'funcionario', 'diarista', 'prestador']);
/** O Select não aceita valor vazio: este é o "sem responsável". */
const NINGUEM = '__ninguem__';

/** As situações que a via mostra no cartão do serviço. As três últimas vêm do papel. */
export const SITUACOES_NA_VIA: Array<{ value: string; label: string }> = [
  { value: 'a_fazer', label: 'A fazer' },
  { value: 'so_levantar', label: 'Só levantar (não executar)' },
  { value: 'aguarda_peca', label: 'Aguarda peça' },
  { value: 'feito', label: 'Já feito' },
  { value: 'parcial', label: 'Parcial' },
  { value: 'nao_feito', label: 'Não feito' },
];

/** O que a seção de serviços passa quando a linha tem sugestão do assistente esperando (via v2, F2). */
export interface SugestaoNaLinha {
  sugestao: SugestaoDeInstrucao;
  /** O texto do cartão (a seção guarda as edições, para o "Aprovar todas" levar o que está escrito). */
  texto: string;
  onEditar: (texto: string) => void;
  onAprovar: (texto: string) => void;
  onDescartar: () => void;
  ocupada?: boolean;
}

/**
 * Como esta linha sai na via do técnico: a situação (a fazer, só levantar, aguarda peça…)
 * e uma instrução curta só para o técnico. Grava direto na linha, como a classificação
 * de sistema logo acima — não depende do Salvar da OS.
 *
 * 13/11/2026: e QUEM FAZ (o responsável da linha). A via do técnico que vai pelo WhatsApp a cada
 * pessoa leva só os serviços dela e os sem responsável (decisão do dono).
 *
 * 20/11/2026 (via v2, F2): com sugestão do assistente esperando, o cartão da sugestão toma o lugar do campo
 * (só o aprovado sai no papel); o campo ganhou rótulo acima.
 */
export function LineViaTecnico({
  line, orderId, sugestao,
}: {
  line: { id: string; field_status?: string | null; technician_instructions?: string | null; responsavel_payee_id?: string | null };
  orderId: string;
  sugestao?: SugestaoNaLinha;
}) {
  const qc = useQueryClient();
  const { data: favorecidos = [] } = usePayees(true);
  const equipe = favorecidos.filter((p) => TIPOS_DA_EQUIPE.has(p.kind) || p.id === line.responsavel_payee_id);
  const [instrucao, setInstrucao] = useState(line.technician_instructions ?? '');
  useEffect(() => { setInstrucao(line.technician_instructions ?? ''); }, [line.id, line.technician_instructions]);
  const idDoCampo = useId();

  async function gravar(patch: { field_status?: string; technician_instructions?: string | null; responsavel_payee_id?: string | null }) {
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
      <Select
        value={line.responsavel_payee_id || NINGUEM}
        onValueChange={(v) => gravar({ responsavel_payee_id: v === NINGUEM ? null : v })}
      >
        <SelectTrigger className="h-7 w-[190px] text-xs" aria-label="Quem faz este serviço">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value={NINGUEM} className="text-xs">Quem faz: todos da OS</SelectItem>
          {equipe.map((p) => (
            <SelectItem key={p.id} value={p.id} className="text-xs">Quem faz: {p.name}</SelectItem>
          ))}
        </SelectContent>
      </Select>
      {sugestao ? (
        <CartaoDaSugestao {...sugestao} />
      ) : (
        <div className="flex w-full basis-full flex-col gap-1">
          <label htmlFor={idDoCampo} className="text-muted-foreground">Instrução ao técnico (opcional)</label>
          <Input
            id={idDoCampo}
            className="h-7 w-full text-xs"
            aria-label="Instrução ao técnico para este serviço"
            placeholder="Ex.: remoção da peça antiga, instalação da nova, ligação e teste"
            value={instrucao}
            onChange={(e) => setInstrucao(e.target.value)}
            onBlur={() => {
              const novo = instrucao.trim() || null;
              if (novo !== (line.technician_instructions || null)) void gravar({ technician_instructions: novo });
            }}
          />
        </div>
      )}
    </div>
  );
}

/** A sugestão do assistente: rótulo acima, o texto editável, "Aprovar" à vista e "Descartar" no menu. */
function CartaoDaSugestao({ sugestao, texto, onEditar, onAprovar, onDescartar, ocupada }: SugestaoNaLinha) {
  const idDoCampo = useId();
  const editado = normalizarInstrucao(texto) !== normalizarInstrucao(sugestao.texto);
  const problema = problemaDaInstrucao(texto);
  const letras = normalizarInstrucao(texto).length;
  return (
    <div className="w-full basis-full space-y-1.5 rounded-md border border-sky-200 bg-sky-50/60 p-2 dark:border-sky-900 dark:bg-sky-950/30">
      <label htmlFor={idDoCampo} className="block font-medium text-foreground">
        Instrução ao técnico · sugestão do assistente
        <span className="font-normal text-muted-foreground"> — sai no papel depois de aprovada</span>
      </label>
      {sugestao.fonte_rotulo && (
        <p className="text-[11px] text-muted-foreground">
          {sugestao.fonte_rotulo.charAt(0).toUpperCase() + sugestao.fonte_rotulo.slice(1)}
        </p>
      )}
      <Textarea
        id={idDoCampo}
        rows={2}
        className="w-full min-h-0 text-xs"
        value={texto}
        onChange={(e) => onEditar(e.target.value)}
      />
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className={letras > LIMITE_SUAVE_DA_INSTRUCAO || problema ? 'text-amber-700 dark:text-amber-400' : 'text-muted-foreground'}>
          {problema ?? `${letras}/${LIMITE_SUAVE_DA_INSTRUCAO} letras${letras > LIMITE_SUAVE_DA_INSTRUCAO ? ' — passa de 2 linhas no cartão' : ''}`}
        </span>
        <div className="flex items-center gap-1">
          <Button size="sm" className="h-7 text-xs" disabled={!!problema || ocupada} onClick={() => onAprovar(normalizarInstrucao(texto))}>
            {editado ? 'Aprovar com a correção' : 'Aprovar'}
          </Button>
          <AcoesDaLinha
            rotulo={`sugestão do serviço ${sugestao.numero}`}
            ocupada={ocupada}
            menu={[{ texto: 'Descartar sugestão', icone: X, onClick: onDescartar }]}
          />
        </div>
      </div>
    </div>
  );
}
