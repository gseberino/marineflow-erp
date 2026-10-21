/* Embarcação/veículo da OS: o mesmo problema do cliente — a tela só mostrava o nome. A ficha
   traz o que o técnico e o escritório perguntam primeiro (tipo, modelo, ano, tamanho, motores,
   onde está) e o "Editar" do cadastro, sem sair da OS (20/10/2026). Desde 21/10 cada dado tem o
   rótulo em cima (pedido do dono): "2019 · 40 pés" sozinho não dizia o que era cada número. */
import { useState } from 'react';
import { Pencil } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { VesselFormDialog } from '@/components/VesselFormDialog';
import { Dado, DadosDaFicha } from '@/components/DadosDaFicha';
import type { Vessel } from '@/hooks/use-vessels';

type VesselDaLista = Vessel & { marinas?: { name?: string | null } | null };

export function FichaDaEmbarcacao({ embarcacao: v }: { embarcacao: VesselDaLista }) {
  const [editando, setEditando] = useState(false);

  const modelo = [v.manufacturer, v.model].filter(Boolean).join(' ');
  const motores = [v.engine_brand, v.engine_model].filter(Boolean).join(' ');
  const motor = motores ? `${v.engine_quantity && v.engine_quantity > 1 ? `${v.engine_quantity}× ` : ''}${motores}` : null;
  const marina = v.marinas?.name || v.current_marina_name_snapshot;
  // "Onde fica", não "Marina": não confundir com o campo Marina da OS, que pode ser outro lugar.
  const onde = [marina, v.current_dock_position ? `vaga ${v.current_dock_position}` : null].filter(Boolean).join(' · ');
  const vazio = !v.asset_type && !modelo && !v.year && !v.length_feet && !v.hull_id_or_registration && !motor && !onde;

  return (
    <div role="group" aria-label="Dados da embarcação" className="space-y-2.5 rounded-lg border bg-muted/30 p-3 text-sm">
      <div className="flex items-center justify-between gap-2">
        <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Dados da embarcação</p>
        <Button
          type="button" variant="outline" size="sm" className="h-11 shrink-0 gap-1 px-2.5 sm:h-8"
          onClick={() => setEditando(true)} aria-label="Editar cadastro da embarcação"
        >
          <Pencil className="h-3.5 w-3.5" aria-hidden /> Editar
        </Button>
      </div>
      {/* O nome não se repete: já está no campo logo acima. Só aparece o que está preenchido —
          nenhum processo exige estes dados, e uma coluna de "Não informado" seria só ruído. */}
      {vazio ? (
        <p className="text-xs text-muted-foreground">Cadastro sem detalhes (modelo, ano, motores). Use “Editar” para completar.</p>
      ) : (
        // Duas colunas já no celular: os valores daqui são curtos ("2019", "40 pés"), e numa
        // coluna só a ficha ficava com meia tela de altura.
        <DadosDaFicha className="grid-cols-2">
          {v.asset_type && <Dado rotulo="Tipo">{v.asset_type}</Dado>}
          {modelo && <Dado rotulo="Fabricante e modelo">{modelo}</Dado>}
          {v.year ? <Dado rotulo="Ano">{String(v.year)}</Dado> : null}
          {v.length_feet ? <Dado rotulo="Comprimento">{`${v.length_feet} pés`}</Dado> : null}
          {v.hull_id_or_registration && <Dado rotulo="Inscrição / placa">{v.hull_id_or_registration}</Dado>}
          {motor && <Dado rotulo="Motores">{motor}</Dado>}
          {onde && <Dado rotulo="Onde fica" largo>{onde}</Dado>}
        </DadosDaFicha>
      )}
      {/* Só montado ao editar: fechado, ele não precisa carregar clientes, marinas e contatos. */}
      {editando && <VesselFormDialog open onOpenChange={setEditando} vessel={v} />}
    </div>
  );
}
