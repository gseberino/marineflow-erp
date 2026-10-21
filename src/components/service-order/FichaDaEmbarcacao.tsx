/* Embarcação/veículo da OS: o mesmo problema do cliente — a tela só mostrava o nome. A ficha
   traz o que o técnico e o escritório perguntam primeiro (tipo, modelo, ano, tamanho, motores,
   onde está) e o "Editar" do cadastro, sem sair da OS (20/10/2026). */
import { useState, type ReactNode } from 'react';
import { Cog, Hash, MapPin, Pencil, Ruler } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { VesselFormDialog } from '@/components/VesselFormDialog';
import type { Vessel } from '@/hooks/use-vessels';

type VesselDaLista = Vessel & { marinas?: { name?: string | null } | null };

export function FichaDaEmbarcacao({ embarcacao: v }: { embarcacao: VesselDaLista }) {
  const [editando, setEditando] = useState(false);

  const titulo = [v.asset_type, [v.manufacturer, v.model].filter(Boolean).join(' ')].filter(Boolean).join(' · ');
  const medidas = [v.year ? String(v.year) : null, v.length_feet ? `${v.length_feet} pés` : null].filter(Boolean).join(' · ');
  const motores = [v.engine_brand, v.engine_model].filter(Boolean).join(' ');
  const motor = motores ? `${v.engine_quantity && v.engine_quantity > 1 ? `${v.engine_quantity}× ` : ''}${motores}` : null;
  const marina = v.marinas?.name || v.current_marina_name_snapshot;
  const onde = [marina, v.current_dock_position ? `vaga ${v.current_dock_position}` : null].filter(Boolean).join(' · ');
  const vazio = !titulo && !medidas && !v.hull_id_or_registration && !motor && !onde;

  return (
    <div className="mt-2 space-y-1.5 rounded-lg border bg-muted/30 p-3 text-sm" aria-label="Dados da embarcação">
      <div className="flex items-start justify-between gap-2">
        <p className={vazio ? 'text-xs text-muted-foreground' : 'min-w-0 break-words font-medium leading-tight'}>
          {vazio ? 'Cadastro sem detalhes (modelo, ano, motores).' : titulo || v.name}
        </p>
        <Button
          type="button" variant="outline" size="sm" className="h-8 shrink-0 gap-1 px-2.5"
          onClick={() => setEditando(true)} aria-label="Editar cadastro da embarcação"
        >
          <Pencil className="h-3.5 w-3.5" /> Editar
        </Button>
      </div>
      {!vazio && (
        <ul className="space-y-1">
          {medidas && <Linha icone={Ruler}>{medidas}</Linha>}
          {v.hull_id_or_registration && <Linha icone={Hash}>{v.hull_id_or_registration}</Linha>}
          {motor && <Linha icone={Cog}>{motor}</Linha>}
          {onde && <Linha icone={MapPin}>{onde}</Linha>}
        </ul>
      )}
      {/* Só montado ao editar: fechado, ele não precisa carregar clientes, marinas e contatos. */}
      {editando && <VesselFormDialog open onOpenChange={setEditando} vessel={v} />}
    </div>
  );
}

function Linha({ icone: Icone, children }: { icone: typeof Cog; children: ReactNode }) {
  return (
    <li className="flex items-start gap-2">
      <Icone className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
      <span className="min-w-0 break-words">{children}</span>
    </li>
  );
}
