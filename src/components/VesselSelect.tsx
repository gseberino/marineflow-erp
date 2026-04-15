import { useState } from 'react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { VesselFormDialog } from '@/components/VesselFormDialog';
import { Plus } from 'lucide-react';

interface VesselOption {
  id: string;
  boat_name: string;
  manufacturer?: string | null;
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

  const activeVessels = vessels.filter(v => v.active);

  return (
    <>
      <Select value={value} onValueChange={onChange} disabled={disabled}>
        <SelectTrigger><SelectValue placeholder="Selecionar embarcação" /></SelectTrigger>
        <SelectContent>
          {activeVessels.map(v => (
            <SelectItem key={v.id} value={v.id}>
              {v.boat_name} {v.manufacturer ? `(${v.manufacturer})` : ''}
            </SelectItem>
          ))}
          <div
            className="relative flex w-full cursor-pointer select-none items-center rounded-sm py-1.5 px-2 text-sm text-primary hover:bg-accent outline-none border-t mt-1 pt-2"
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              setShowCreate(true);
            }}
          >
            <Plus className="mr-2 h-4 w-4" />
            Nova Embarcação para este cliente
          </div>
        </SelectContent>
      </Select>

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
