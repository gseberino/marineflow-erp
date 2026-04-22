import { useState } from 'react';
import { VesselFormDialog } from '@/components/VesselFormDialog';
import { EntityCombobox } from '@/components/EntityCombobox';

interface VesselOption {
  id: string;
  boat_name: string;
  manufacturer?: string | null;
  model?: string | null;
  hull_id_or_registration?: string | null;
  marina_id?: string | null;
  active: boolean;
}

interface Props {
  value: string;
  onChange: (vesselId: string) => void;
  vessels: VesselOption[];
  clientId: string;
  disabled?: boolean;
  onVesselCreated?: (vessel: { id: string; boat_name: string; marina_id?: string | null }) => void;
}

export function VesselSelect({ value, onChange, vessels, clientId, disabled, onVesselCreated }: Props) {
  const [showCreate, setShowCreate] = useState(false);

  const options = vessels
    .filter(v => v.active)
    .map(v => ({
      value: v.id,
      label: v.boat_name,
      description: [v.manufacturer, v.model].filter(Boolean).join(' ') || undefined,
      searchTerms: [
        v.manufacturer || '',
        v.model || '',
        v.hull_id_or_registration || '',
      ],
    }));

  return (
    <>
      <EntityCombobox
        value={value}
        onChange={onChange}
        options={options}
        disabled={disabled}
        placeholder="Selecionar embarcação"
        searchPlaceholder="Buscar embarcação... (digite 3+ letras)"
        emptyText="Nenhuma embarcação encontrada"
        onCreate={() => setShowCreate(true)}
        createLabel="Nova embarcação para este cliente"
      />

      <VesselFormDialog
        open={showCreate}
        onOpenChange={setShowCreate}
        initialClientId={clientId}
        onCreated={(vessel) => {
          if (onVesselCreated) onVesselCreated(vessel);
        }}
      />
    </>
  );
}
